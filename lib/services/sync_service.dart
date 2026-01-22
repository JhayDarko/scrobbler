import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/db_helper.dart';
import '../config/app_config.dart';

class SyncService {
  final _dbHelper = DBHelper();
  final _supabase = Supabase.instance.client;

  bool _isSyncing = false;
  int _retryCount = 0;
  static const int _maxRetries = AppConfig.maxSyncRetries;

  /// Sincronizar scrobbles no sincronizados con Supabase
  Future<SyncResult> syncData() async {
    // Evitar sincronizaciones concurrentes
    if (_isSyncing) {
      print('⏳ Sincronización ya en progreso, saltando...');
      return SyncResult(success: false, message: 'Sync en progreso');
    }

    _isSyncing = true;
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🔄 INICIANDO SINCRONIZACIÓN');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    try {
      // Timeout de 30 segundos para todo el proceso
      final result = await _syncWithTimeout();
      _isSyncing = false;
      return result;
    } catch (e) {
      _isSyncing = false;
      print('❌ Error crítico en sincronización: $e');
      
      // Retry solo para errores de red, no para errores de validación
      if (_shouldRetry(e)) {
        return await _retrySync();
      }
      
      return SyncResult(
        success: false,
        message: 'Error: ${_getErrorMessage(e)}',
        errorCount: 1,
      );
    }
  }

  /// Sincronización con timeout
  Future<SyncResult> _syncWithTimeout() async {
    return await Future.any([
      _performSync(),
      Future.delayed(
        const Duration(seconds: 30),
        () => throw TimeoutException('Sincronización excedió 30 segundos'),
      ),
    ]);
  }

  /// Función de diagnóstico para verificar conexión y permisos de Supabase
  Future<Map<String, dynamic>> diagnosticSupabase() async {
    final result = <String, dynamic>{
      'connection': false,
      'canRead': false,
      'canInsert': false,
      'tableExists': false,
      'error': null,
    };

    try {
      // 1. Verificar conexión básica
      print('🔍 [DIAGNÓSTICO] Verificando conexión...');
      final connectionTest = await hasConnection();
      result['connection'] = connectionTest;
      print('   ${connectionTest ? '✅' : '❌'} Conexión: $connectionTest');

      if (!connectionTest) {
        result['error'] = 'Sin conexión a Supabase';
        return result;
      }

      // 2. Verificar si la tabla existe y podemos leer
      print('🔍 [DIAGNÓSTICO] Verificando lectura de tabla...');
      try {
        final readTest = await _supabase
            .from('scrobbles')
            .select('*')
            .limit(1)
            .timeout(const Duration(seconds: 5));
        result['tableExists'] = true;
        result['canRead'] = true;
        print('   ✅ Lectura: OK (encontrados ${readTest.length} registros)');
      } catch (e) {
        result['tableExists'] = false;
        result['canRead'] = false;
        print('   ❌ Lectura: ERROR - $e');
        result['error'] = 'Error al leer tabla: $e';
      }

      // 3. Verificar si podemos insertar (con datos de prueba)
      print('🔍 [DIAGNÓSTICO] Verificando inserción...');
      try {
        final testData = {
          'track': '__TEST_DIAGNOSTIC__',
          'artist': '__TEST_DIAGNOSTIC__',
          'album': 'TEST',
          'duration': 999,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        };
        
        final insertTest = await _supabase
            .from('scrobbles')
            .insert(testData)
            .select()
            .timeout(const Duration(seconds: 5));
        
        result['canInsert'] = insertTest.isNotEmpty;
        print('   ✅ Inserción: OK');
        print('   📦 Respuesta: $insertTest');
        
        // Limpiar dato de prueba si se insertó correctamente
        if (insertTest.isNotEmpty && insertTest[0]['id'] != null) {
          try {
            await _supabase
                .from('scrobbles')
                .delete()
                .eq('track', '__TEST_DIAGNOSTIC__')
                .eq('artist', '__TEST_DIAGNOSTIC__');
            print('   🗑️ Dato de prueba eliminado');
          } catch (deleteError) {
            print('   ⚠️ No se pudo eliminar dato de prueba: $deleteError');
          }
        }
      } catch (e) {
        result['canInsert'] = false;
        print('   ❌ Inserción: ERROR - $e');
        result['error'] = 'Error al insertar: $e';
        
        // Detectar si es un error de RLS
        if (e.toString().toLowerCase().contains('policy') || 
            e.toString().toLowerCase().contains('permission') ||
            e.toString().toLowerCase().contains('rls')) {
          result['error'] = '🔒 Row Level Security (RLS) está bloqueando inserts. Revisa las políticas en Supabase Dashboard.';
        }
      }

      return result;
    } catch (e) {
      print('   ❌ Error general en diagnóstico: $e');
      result['error'] = 'Error general: $e';
      return result;
    }
  }

  /// Realiza la sincronización actual
  Future<SyncResult> _performSync() async {
    final unsynced = await _dbHelper.getUnsynced();

    if (unsynced.isEmpty) {
      print('✅ No hay scrobbles pendientes de sincronizar');
      return SyncResult(
        success: true,
        message: 'Sin pendientes',
        syncedCount: 0,
      );
    }

    print('📤 Encontrados ${unsynced.length} scrobbles pendientes');
    int syncedCount = 0;
    int errorCount = 0;
    int skippedCount = 0;

    for (var item in unsynced) {
      try {
        // Validar datos antes de enviar
        final validationError = _validateScrobbleData(item);
        if (validationError != null) {
          print('⚠️ Scrobble ${item['id']} inválido: $validationError');
          skippedCount++;
          // Marcar como sincronizado para no reintentar datos inválidos
          await _dbHelper.markAsSynced(item['id'] as int);
          continue;
        }

        // Preparar datos para Supabase (no enviar campos vacíos)
        final albumValue = item['album'] as String?;
        final scrobbleData = <String, dynamic>{
          'track': item['track'],
          'artist': item['artist'],
          'duration': item['duration'],
          'timestamp': item['timestamp'],
        };
        
        // Solo incluir album si tiene valor
        if (albumValue != null && albumValue.isNotEmpty) {
          scrobbleData['album'] = albumValue;
        }

        print('   🎵 Sincronizando: ${item['track']} - ${item['artist']}');
        print('   📦 Datos a enviar: $scrobbleData');

        // Enviar a Supabase con timeout individual y capturar respuesta
        final response = await _supabase
            .from('scrobbles')
            .insert(scrobbleData)
            .select() // CRÍTICO: Forzar respuesta para detectar errores de RLS
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw TimeoutException('Timeout en insert'),
            );
        
        print('   📨 Respuesta de Supabase: $response');

        // Marcar como sincronizado en DB local
        final marked = await _dbHelper.markAsSynced(item['id'] as int);
        if (marked) {
          syncedCount++;
          print('   ✅ Scrobble ${item['id']} sincronizado');
        } else {
          print('   ⚠️ No se pudo marcar scrobble ${item['id']}');
        }
      } catch (e) {
        errorCount++;
        final errorMsg = _getDetailedError(e, item);
        print('   ❌ Error en scrobble ${item['id']}: $errorMsg');

        // Si es error de red, detener intentos adicionales
        if (_isNetworkError(e)) {
          print('🔌 Sin conexión, deteniendo sincronización');
          break;
        }
        
        // Si es error de duplicado en Supabase, marcar como sincronizado
        if (_isDuplicateError(e)) {
          print('   📝 Duplicado en servidor, marcando como sincronizado');
          await _dbHelper.markAsSynced(item['id'] as int);
          errorCount--;
          skippedCount++;
        }
      }
    }

    _retryCount = 0; // Resetear contador de reintentos en éxito

    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📊 RESULTADO DE SINCRONIZACIÓN');
    print('   ✅ Exitosos: $syncedCount');
    print('   ❌ Errores: $errorCount');
    if (skippedCount > 0) {
      print('   ⏭️  Omitidos: $skippedCount');
    }
    print('   📈 Total procesados: ${syncedCount + errorCount + skippedCount}/${unsynced.length}');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    final message = errorCount > 0
        ? 'Sincronizados $syncedCount de ${unsynced.length}'
        : 'Todos sincronizados ($syncedCount)';

    return SyncResult(
      success: errorCount == 0,
      message: message,
      syncedCount: syncedCount,
      errorCount: errorCount,
    );
  }

  /// Validar datos del scrobble antes de enviar
  String? _validateScrobbleData(Map<String, dynamic> item) {
    if (item['track'] == null || (item['track'] as String).trim().isEmpty) {
      return 'Track vacío';
    }
    if (item['artist'] == null || (item['artist'] as String).trim().isEmpty) {
      return 'Artista vacío';
    }
    if (item['timestamp'] == null) {
      return 'Timestamp faltante';
    }
    if (item['duration'] == null || item['duration'] < 0) {
      return 'Duración inválida';
    }
    return null;
  }

  /// Determinar si es un error de red
  bool _isNetworkError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('socket') ||
        errorStr.contains('network') ||
        errorStr.contains('connection') ||
        errorStr.contains('timeout') ||
        errorStr.contains('failed host lookup');
  }

  /// Determinar si es un error de duplicado
  bool _isDuplicateError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('duplicate') ||
        errorStr.contains('unique') ||
        errorStr.contains('constraint') ||
        errorStr.contains('already exists');
  }

  /// Determinar si debe reintentar
  bool _shouldRetry(dynamic error) {
    return _isNetworkError(error) && _retryCount < _maxRetries;
  }

  /// Obtener mensaje de error detallado
  String _getDetailedError(dynamic error, Map<String, dynamic> item) {
    if (_isNetworkError(error)) {
      return 'Sin conexión a internet';
    }
    if (_isDuplicateError(error)) {
      return 'Duplicado en servidor';
    }
    return error.toString();
  }

  /// Obtener mensaje de error simple
  String _getErrorMessage(dynamic error) {
    if (_isNetworkError(error)) {
      return 'Sin conexión';
    }
    if (error is TimeoutException) {
      return 'Tiempo de espera agotado';
    }
    return error.toString();
  }

  /// Reintentar sincronización con backoff
  Future<SyncResult> _retrySync() async {
    if (_retryCount >= _maxRetries) {
      _retryCount = 0;
      return SyncResult(
        success: false,
        message: 'Máximo de reintentos alcanzado',
        errorCount: 1,
      );
    }

    _retryCount++;
    final delaySeconds = _retryCount * 2; // 2s, 4s, 6s
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🔄 Reintento $_retryCount/$_maxRetries en ${delaySeconds}s...');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    await Future.delayed(Duration(seconds: delaySeconds));
    return await syncData();
  }

  /// Verificar si hay conexión a internet
  Future<bool> hasConnection() async {
    try {
      await _supabase
          .from('scrobbles')
          .select()
          .limit(1)
          .timeout(const Duration(seconds: 5));
      return true;
    } catch (e) {
      print('🔌 Sin conexión detectada');
      return false;
    }
  }

  /// Obtener estado de sincronización
  bool get isSyncing => _isSyncing;
}

/// Clase para resultado de sincronización
class SyncResult {
  final bool success;
  final String message;
  final int syncedCount;
  final int errorCount;

  SyncResult({
    required this.success,
    required this.message,
    this.syncedCount = 0,
    this.errorCount = 0,
  });

  @override
  String toString() {
    return 'SyncResult(success: $success, message: $message, synced: $syncedCount, errors: $errorCount)';
  }
}
