/// Configuración centralizada de la aplicación
///
/// NOTA DE SEGURIDAD: En producción, estas credenciales deberían
/// moverse a variables de entorno usando flutter_dotenv o similar
class AppConfig {
  // Prevenir instanciación
  AppConfig._();

  /// URL de Supabase
  static const String supabaseUrl = 'https://uimgfmkfiikhsemgbgva.supabase.co';

  /// Clave anónima de Supabase (pública)
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVpbWdmbWtmaWlraHNlbWdiZ3ZhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg4NTk5NzEsImV4cCI6MjA4NDQzNTk3MX0.lv4iIntC7cpOq8DAbMp_4T507M-5WqV2oOv6cUHFZP8';

  /// Configuración de scrobbling (estándares de Last.fm/Pano Scrobbler)
  /// Mínimo absoluto para que una canción sea válida
  static const int minTrackDurationSeconds = 30;
  
  /// Umbral de scrobble: 50% de la canción O 4 minutos (lo que ocurra primero)
  static const int scrobbleThresholdSeconds = 30; // Mínimo antes de evaluar
  static const int scrobbleMaxThresholdSeconds = 240; // 4 minutos máximo
  static const double scrobblePercentageThreshold = 0.5; // 50%
  
  /// Ventana de tiempo para considerar un scrobble duplicado (en minutos)
  static const int duplicateWindowMinutes = 2;
  
  /// Duración mínima de reproducción para considerar válido (segundos)
  static const int minPlayedDurationSeconds = 30;

  /// Configuración de sincronización
  static const int syncIntervalMinutes = 15;
  static const int maxSyncRetries = 3;

  /// Configuración de limpieza de base de datos
  static const int cleanupDaysOld = 30;

  /// Configuración de notificaciones
  static const String notificationChannelId = 'scrobbler_service';
  static const String notificationChannelName = 'Scrobbler Service';
  static const String notificationChannelDescription =
      'Monitorizando música en segundo plano';
  static const int foregroundServiceNotificationId = 888;

  /// Method channels
  static const String notificationsMethodChannel =
      'com.example.scrobbler/notifications_method';
  static const String restartServiceMethodChannel =
      'com.example.scrobbler/restart_service';
}
