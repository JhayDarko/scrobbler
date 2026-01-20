import 'dart:async';
import 'package:flutter/services.dart';
import '../database/db_helper.dart';
import '../models/scrobble.dart';
import 'sync_service.dart';

/// Clase para manejar la comunicación con el código nativo
class NativeNotificationService {
  static const MethodChannel _methodChannel = MethodChannel('com.example.scrobbler/notifications_method');
  // Eliminado: static const EventChannel _eventChannel ... (Ya no se usa)

  /// Verificar si tenemos permisos
  static Future<bool> isPermissionGranted() async {
    try {
      final bool result = await _methodChannel.invokeMethod('isPermissionGranted');
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
  int? _totalDuration;
  Timer? _scrobbleTimer;
  int? _currentScrobbleId;
  
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
      final hasPermission = await NativeNotificationService.isPermissionGranted();
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
      
      final String? packageName = data['packageName'] as String?;
      // if (packageName != "com.google.android.apps.youtube.music") return; // Ya filtrado en nativo

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

      if (album == "YouTube Music" || album == "Siguiente" || album == "Anterior") album = "";

      // --- DETECCIÓN ---
      final isNewTrack = currentTrack != _lastTrack || artist != _lastArtist;

      if (isNewTrack) {
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print('🎶 NUEVA CANCIÓN DETECTADA (Background)');
        print('   🎵 Track: $currentTrack');
        print('   👤 Artista: $artist');
        print('   💿 Álbum: ${album?.isEmpty == true ? "(Pendiente...)" : album}');
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

        // 3. Programar scrobble a los 30s
        _scrobbleTimer?.cancel();
        _scrobbleTimer = Timer(const Duration(seconds: 30), () {
          _saveInitialScrobble(
            track: _lastTrack!,
            artist: _lastArtist ?? "Desconocido",
            album: _lastAlbum ?? "", 
            duration: _totalDuration ?? 0,
          );
        });
      } else {
          // --- ENRIQUECIMIENTO DE DATOS ---
          bool updated = false;

          if ((_lastAlbum == null || _lastAlbum!.isEmpty) && (album != null && album.isNotEmpty)) {
              print('✨ Álbum detectado tarde: "$album"');
              _lastAlbum = album;
              updated = true;
          }

          if ((_totalDuration == null || _totalDuration == 0) && (duration != null && duration > 0)) {
              _totalDuration = duration;
              updated = true;
          }
      }
    } catch (e) {
        print('❌ Error procesando evento interno: $e');
    }
  }

  void _saveInitialScrobble({
    required String track,
    required String artist,
    required String album,
    required int duration,
  }) {
    if (_trackStartTime == null) return;

    print('⏱️ 30s alcanzados. Guardando en BD...');

    final scrobble = Scrobble(
      track: track,
      artist: artist,
      album: album,
      duration: duration,
      timestamp: _trackStartTime!,
    );

    _dbHelper.insertScrobble(scrobble).then((id) {
      _currentScrobbleId = id;
      print('✅ Scrobble guardado correctamente (ID: $id)');
      
      if (duration > 0) {
        _syncService.syncData();
      }
    });
  }

  void _finalizePreviousScrobble() {
    if (_trackStartTime == null || _currentScrobbleId == null) return;

    if (_totalDuration != null && _totalDuration! > 0) {
      return;
    }

    final durationCalc = DateTime.now().difference(_trackStartTime!);
    final durationMs = durationCalc.inMilliseconds;

    if (durationCalc.inSeconds >= 30) {
      _dbHelper.updateScrobbleDuration(_currentScrobbleId!, durationMs).then((_) {
        _syncService.syncData();
      });
    }
  }

  String _formatDuration(int milliseconds) {
    if (milliseconds == 0) return "0:00";
    final seconds = milliseconds ~/ 1000;
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  void dispose() {
    _scrobbleTimer?.cancel();
    // _subscription?.cancel(); // Ya no hay subscription
    if (_currentScrobbleId != null) _finalizePreviousScrobble();
  }
}