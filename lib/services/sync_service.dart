import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/db_helper.dart';

class SyncService {
  final _dbHelper = DBHelper();
  final _supabase = Supabase.instance.client;
  
  bool _isSyncing = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  /// Sincronizar scrobbles no sincronizados con Supabase
  Future<SyncResult> syncData() async {
    // Evitar sincronizaciones concurrentes
    if (_isSyncing) {
      print('⏳ Sincronización ya en progreso, saltando...');
      return SyncResult(success: false, message: 'Sync en progreso');
    }

    _isSyncing = true;
    print('🔄 Iniciando sincronización...');

    try {
      final unsynced = await _dbHelper.getUnsynced();

      if (unsynced.isEmpty) {
        print('✅ No hay scrobbles pendientes de sincronizar');
        _isSyncing = false;
        return SyncResult(success: true, message: 'Sin pendientes', syncedCount: 0);
      }

      print('📤 Sincronizando ${unsynced.length} scrobbles...');
      int syncedCount = 0;
      int errorCount = 0;

      for (var item in unsynced) {
        try {
          // Enviar a Supabase
          await _supabase.from('scrobbles').insert({
            'track': item['track'],
            'artist': item['artist'],
            'album': item['album'],
            'duration': item['duration'],
            'timestamp': item['timestamp'],
          });

          // Marcar como sincronizado en DB local
          await _dbHelper.markAsSynced(item['id'] as int);
          syncedCount++;
          
          print('✅ Scrobble ${item['id']} sincronizado');
        } catch (e) {
          errorCount++;
          print('❌ Error sincronizando scrobble ${item['id']}: $e');
          
          // Si es error de red, detener intentos adicionales
          if (e.toString().contains('SocketException') || 
              e.toString().contains('NetworkError')) {
            print('🔌 Sin conexión, deteniendo sincronización');
            break;
          }
        }
      }

      _retryCount = 0; // Resetear contador de reintentos en éxito
      _isSyncing = false;

      final message = errorCount > 0
          ? 'Sincronizados $syncedCount de ${unsynced.length}'
          : 'Todos sincronizados';

      print('📊 Sincronización completada: $syncedCount exitosos, $errorCount errores');
      return SyncResult(
        success: errorCount == 0,
        message: message,
        syncedCount: syncedCount,
        errorCount: errorCount,
      );
    } catch (e) {
      _isSyncing = false;
      print('❌ Error general en sincronización: $e');
      
      // Retry con exponential backoff
      if (_retryCount < _maxRetries) {
        _retryCount++;
        final delaySeconds = _retryCount * 2; // 2s, 4s, 6s
        print('🔄 Reintentando en ${delaySeconds}s (intento $_retryCount/$_maxRetries)');
        
        await Future.delayed(Duration(seconds: delaySeconds));
        return await syncData(); // Recursivo con backoff
      } else {
        _retryCount = 0;
        return SyncResult(
          success: false,
          message: 'Error: $e',
          errorCount: 1,
        );
      }
    }
  }

  /// Verificar si hay conexión a internet (simplificado)
  Future<bool> hasConnection() async {
    try {
      // Intentar una operación simple con Supabase
      await _supabase.from('scrobbles').select().limit(1);
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