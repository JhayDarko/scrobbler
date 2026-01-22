import 'dart:async';
import 'package:flutter/services.dart';
import '../database/db_helper.dart';
import '../models/scrobble.dart';
import '../config/app_config.dart';
import 'sync_service.dart';

/// Clase para manejar la comunicación con el código nativo
class NativeNotificationService {
  static const MethodChannel _methodChannel = MethodChannel(
    AppConfig.notificationsMethodChannel,
  );
  // Eliminado: static const EventChannel _eventChannel ... (Ya no se usa)

  /// Verificar si tenemos permisos
  static Future<bool> isPermissionGranted() async {
    try {
      final bool result = await _methodChannel.invokeMethod(
        'isPermissionGranted',
      );
      // print("🔍 Estado del permiso (Nativo): $result"); // Debug
      return result;
    } on PlatformException catch (e) {
      print("Error verificando permisos: ${e.message}");
      return false;
    }
  }

  /// Solicitar permisos (abre la configuración)
  static Future<void> requestPermission() async {
    try {
      await _methodChannel.invokeMethod('requestPermission');
    } on PlatformException catch (e) {
      print("Error solicitando permisos: ${e.message}");
    }
  }
}

class ScrobbleService {
  final _dbHelper = DBHelper();
  final _syncService = SyncService();

  // Control de estado de reproducción
  String? _lastTrack;
  String? _lastArtist;
  String? _lastAlbum;
  DateTime? _trackStartTime;
  int? _totalDuration; // Duración total de la canción en ms
  Timer? _scrobbleTimer;
  int? _currentScrobbleId;
  bool _hasBeenScrobbled = false; // Prevenir scrobbles duplicados
  DateTime? _lastScrobbleTimestamp; // Última vez que se guardó un scrobble
  DateTime? _lastNotificationTime; // Última vez que recibimos una notificación
  bool _isPaused = false; // Estado de pausa
  DateTime? _pauseStartTime; // Momento en que se pausó

  // Singleton pattern para asegurar que solo una instancia maneje el estado
  // Esto es vital ahora que el background service crea su instancia.
  // Sin embargo, como el background service corre en otro Isolate, el singleton NO se comparte.
  // Cada Isolate tiene su propio estado en memoria.
  // Esto está bien: El UI Isolate solo lee BD. El Background Isolate escribe BD.
  // La instancia de ScrobbleService en UI no necesita saber lo que pasa en Background,
  // solo DB Helper lo sabe.

  Future<void> startListening() async {
    // En la nueva arquitectura, este método solo verifica permisos
    // No inicia ningún stream porque el Background Service hace el polling.

    try {
      final hasPermission =
          await NativeNotificationService.isPermissionGranted();
      if (!hasPermission) {
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print('⚠️ PERMISOS PENDIENTES');
        print('   Activa el acceso a notificaciones.');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      } else {
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print('✅ MONITOR ACTIVO (Modo Segundo Plano)');
        print('   El servicio de fondo detectará la música.');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      }
    } catch (e) {
      print('⚠️ Error verificación inicial: $e');
    }
  }

  Future<void> initDB() async {
    await _dbHelper.db;
  }

  // Método público para ser llamado desde el Background Service
  void processBackgroundEvent(dynamic eventData) {
    try {
      final Map<String, dynamic> data = eventData as Map<String, dynamic>;

      final String title = data['title'] ?? "";
      if (title.isEmpty) return;

      // Detectar pausa/reanudación
      final now = DateTime.now();
      if (_lastNotificationTime != null) {
        final timeSinceLastNotification = now.difference(_lastNotificationTime!);
        
        // Si han pasado más de 5 segundos sin notificaciones, probablemente estaba pausado
        if (timeSinceLastNotification.inSeconds > 5) {
          if (!_isPaused) {
            print('⏸️ Pausa detectada (${timeSinceLastNotification.inSeconds}s sin notificaciones)');
            _isPaused = true;
            _pauseStartTime = _lastNotificationTime;
          }
        }
      }
      
      _lastNotificationTime = now;

      final enrichedData = {
        'packageName': data['source'],
        'title': title,
        'artist': data['artist'],
        'album': data['album'],
        'duration': data['duration'],
      };

      _processNotificationInternal(enrichedData);
    } catch (e) {
      print("Error processing background event: $e");
    }
  }

  // Lógica interna de negocio (reutilizada)
  void _processNotificationInternal(dynamic event) {
    try {
      final Map<dynamic, dynamic> data = event as Map<dynamic, dynamic>;

      // packageName ya fue filtrado en el lado nativo

      final String? title = data['title'] as String?;
      String? artist = data['artist'] as String?;
      String? album = data['album'] as String?;
      int? duration = data['duration'] as int?;

      final String? text = data['text'] as String?;
      final String? subText = data['subText'] as String?;

      if (title == null || title.isEmpty) return;
      final String currentTrack = title.trim();

      // --- LOGICA DE FALLBACK ---
      if (artist == null || artist.isEmpty) {
        if (text != null && text.contains(' • ')) {
          final parts = text.split(' • ');
          artist = parts[0].trim();
        } else {
          artist = text?.trim() ?? 'Artista desconocido';
        }
      }

      if (album == null || album.isEmpty || album == "YouTube Music") {
        if (text != null && text.contains(' • ')) {
          final parts = text.split(' • ');
          if (parts.length > 1) album = parts[1].trim();
        } else if (subText != null && subText != "YouTube Music") {
          album = subText.trim();
        } else {
          album = "";
        }
      }

      if (album == "YouTube Music" ||
          album == "Siguiente" ||
          album == "Anterior") {
        album = "";
      }

      // --- DETECCIÓN DE NUEVA CANCIÓN ---
      final isNewTrack = _isNewTrack(currentTrack, artist, album);

      if (isNewTrack) {
        // Si estaba pausado y es la misma canción, es una reanudación
        if (_isPaused && currentTrack == _lastTrack && artist == _lastArtist) {
          print('▶️ Reanudación detectada de: $currentTrack');
          _isPaused = false;
          _pauseStartTime = null;
          // No reiniciar el timer, continúa donde se quedó
          return;
        }
        
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print('🎶 NUEVA CANCIÓN DETECTADA (Background)');
        print('   🎵 Track: $currentTrack');
        print('   👤 Artista: $artist');
        print(
          '   💿 Álbum: ${album?.isEmpty == true ? "(Pendiente...)" : album}',
        );
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

        // 1. Finalizar anterior
        if (_lastTrack != null && _currentScrobbleId != null) {
          _finalizePreviousScrobble();
        }

        // 2. Iniciar nueva
        _lastTrack = currentTrack;
        _lastArtist = artist;
        _lastAlbum = album;
        _totalDuration = duration;
        _trackStartTime = DateTime.now();
        _currentScrobbleId = null;
        _isPaused = false;
        _pauseStartTime = null;

        // 3. Programar scrobble con lógica profesional
        _scrobbleTimer?.cancel();
        _hasBeenScrobbled = false;
        
        // Calcular cuándo hacer el scrobble basado en la duración
        final scrobbleDelay = _calculateScrobbleDelay(_totalDuration);
        
        print('⏰ Scrobble programado en ${scrobbleDelay}s');
        
        _scrobbleTimer = Timer(
          Duration(seconds: scrobbleDelay),
          () {
            _saveScrobble(
              track: _lastTrack!,
              artist: _lastArtist ?? "Desconocido",
              album: _lastAlbum ?? "",
              duration: _totalDuration ?? 0,
            );
          },
        );
      } else {
        // --- ENRIQUECIMIENTO DE DATOS ---
        if ((_lastAlbum == null || _lastAlbum!.isEmpty) &&
            (album != null && album.isNotEmpty)) {
          print('✨ Álbum detectado tarde: "$album"');
          _lastAlbum = album;
        }

        if ((_totalDuration == null || _totalDuration == 0) &&
            (duration != null && duration > 0)) {
          _totalDuration = duration;
        }
      }
    } catch (e) {
      print('❌ Error procesando evento interno: $e');
    }
  }

  /// Calcula el delay óptimo para scrobble según duración de la canción
  /// Regla: 50% de la canción O 4 minutos, lo que ocurra primero
  /// Mínimo: 30 segundos
  int _calculateScrobbleDelay(int? durationMs) {
    if (durationMs == null || durationMs == 0) {
      // Sin duración conocida, usar mínimo
      return AppConfig.scrobbleThresholdSeconds;
    }

    final durationSeconds = durationMs ~/ 1000;
    
    // Regla del 50%
    final halfDuration = (durationSeconds * AppConfig.scrobblePercentageThreshold).round();
    
    // Aplicar límites: mínimo 30s, máximo 4 minutos
    final delay = halfDuration.clamp(
      AppConfig.scrobbleThresholdSeconds,
      AppConfig.scrobbleMaxThresholdSeconds,
    );
    
    return delay;
  }

  /// Verifica si es una canción nueva o repetición válida
  bool _isNewTrack(String track, String? artist, String? album) {
    // Primera canción
    if (_lastTrack == null) return true;
    
    // Cambio de canción
    if (track != _lastTrack || artist != _lastArtist) return true;
    
    // Misma canción - verificar ventana de duplicados
    if (_lastScrobbleTimestamp != null) {
      final timeSinceLastScrobble = DateTime.now().difference(_lastScrobbleTimestamp!);
      
      // Si han pasado más de X minutos, permitir scrobble duplicado
      if (timeSinceLastScrobble.inMinutes >= AppConfig.duplicateWindowMinutes) {
        print('🔄 Misma canción pero fuera de ventana de duplicados');
        return true;
      }
      
      print('⏭️ Canción duplicada ignorada (dentro de ventana de ${AppConfig.duplicateWindowMinutes}min)');
      return false;
    }
    
    return false;
  }

  /// Valida si la canción cumple los requisitos mínimos para scrobble
  bool _isValidForScrobble(String track, String artist, int durationMs) {
    // Track y artista no pueden estar vacíos
    if (track.trim().isEmpty) {
      print('❌ Track vacío, scrobble inválido');
      return false;
    }
    
    if (artist.trim().isEmpty || artist == 'Artista desconocido') {
      print('⚠️ Artista desconocido');
      // Permitir pero advertir
    }
    
    // Validar duración mínima si está disponible
    if (durationMs > 0) {
      final durationSeconds = durationMs ~/ 1000;
      if (durationSeconds < AppConfig.minTrackDurationSeconds) {
        print('❌ Canción muy corta (${durationSeconds}s < ${AppConfig.minTrackDurationSeconds}s), ignorada');
        return false;
      }
    }
    
    return true;
  }

  /// Guarda el scrobble con validaciones profesionales
  void _saveScrobble({
    required String track,
    required String artist,
    required String album,
    required int duration,
  }) {
    if (_trackStartTime == null || _hasBeenScrobbled) return;

    // Validar que cumple requisitos
    if (!_isValidForScrobble(track, artist, duration)) {
      print('⏭️ Scrobble no cumple requisitos, ignorado');
      return;
    }

    // Calcular duración real de reproducción (excluyendo tiempo en pausa)
    var actualPlayedDuration = DateTime.now().difference(_trackStartTime!).inMilliseconds;
    
    // Si estuvo pausado, restar el tiempo de pausa
    if (_pauseStartTime != null && _isPaused) {
      final pauseDuration = DateTime.now().difference(_pauseStartTime!);
      actualPlayedDuration -= pauseDuration.inMilliseconds;
      print('⏸️ Restando ${pauseDuration.inSeconds}s de pausa');
    }
    
    final actualPlayedSeconds = actualPlayedDuration ~/ 1000;
    
    // Verificar que se reprodujo el mínimo requerido
    if (actualPlayedSeconds < AppConfig.minPlayedDurationSeconds) {
      print('⏭️ No alcanzó el mínimo de reproducción (${actualPlayedSeconds}s < ${AppConfig.minPlayedDurationSeconds}s)');
      return;
    }

    // VALIDACIÓN ESTRICTA: No guardar si faltan datos críticos
    final cleanTrack = track.trim();
    final cleanArtist = artist.trim();
    final cleanAlbum = album.trim();
    
    if (cleanTrack.isEmpty) {
      print('❌ Track vacío, scrobble cancelado');
      return;
    }
    
    if (cleanArtist.isEmpty || cleanArtist == 'Artista desconocido') {
      print('❌ Artista inválido, scrobble cancelado');
      return;
    }

    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('💾 GUARDANDO SCROBBLE');
    print('   🎵 Track: $cleanTrack');
    print('   👤 Artista: $cleanArtist');
    if (cleanAlbum.isNotEmpty) {
      print('   💿 Álbum: $cleanAlbum');
    }
    print('   ⏱️ Duración total: ${duration ~/ 1000}s');
    print('   ▶️ Reproducido: ${actualPlayedSeconds}s');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    final scrobble = Scrobble(
      track: cleanTrack,
      artist: cleanArtist,
      album: cleanAlbum.isNotEmpty ? cleanAlbum : null, // No guardar string vacío
      duration: duration > 0 ? duration : actualPlayedDuration,
      timestamp: _trackStartTime!,
    );

    _dbHelper.insertScrobble(scrobble).then((id) {
      if (id > 0) {
        _currentScrobbleId = id;
        _hasBeenScrobbled = true;
        _lastScrobbleTimestamp = DateTime.now();
        print('✅ Scrobble guardado (ID: $id)');
        
        // Sincronizar si hay duración válida
        if (duration > 0 || actualPlayedDuration > 0) {
          _syncService.syncData();
        }
      } else {
        print('⚠️ Scrobble posiblemente duplicado, ignorado');
      }
    }).catchError((error) {
      print('❌ Error guardando scrobble: $error');
    });
  }

  /// Finaliza el scrobble anterior si no se guardó
  void _finalizePreviousScrobble() {
    // Si ya fue scrobbleado, no hacer nada
    if (_hasBeenScrobbled || _trackStartTime == null) return;

    // Calcular duración real de reproducción
    final actualDuration = DateTime.now().difference(_trackStartTime!);
    final actualSeconds = actualDuration.inSeconds;

    // Solo finalizar si alcanzó el mínimo
    if (actualSeconds >= AppConfig.minPlayedDurationSeconds && _lastTrack != null) {
      print('🔚 Finalizando scrobble anterior (${actualSeconds}s reproducidos)');
      
      _saveScrobble(
        track: _lastTrack!,
        artist: _lastArtist ?? "Desconocido",
        album: _lastAlbum ?? "",
        duration: _totalDuration ?? actualDuration.inMilliseconds,
      );
    } else {
      print('⏭️ Canción anterior no alcanzó el mínimo (${actualSeconds}s), descartada');
    }
  }

  void dispose() {
    _scrobbleTimer?.cancel();
    if (_currentScrobbleId != null) _finalizePreviousScrobble();
  }
}
