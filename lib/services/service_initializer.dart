import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:scrobbler/config/app_config.dart';

Future<void> initializeService(
  Function(ServiceInstance) onStartCallback,
) async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    AppConfig.notificationChannelId,
    AppConfig.notificationChannelName,
    description: AppConfig.notificationChannelDescription,
    importance: Importance.high, // Alta para foreground service
    showBadge: true,
    playSound: false,
    enableVibration: false,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  print('🛠️ Configurando Background Service...');

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStartCallback,
      isForegroundMode: true, // CRÍTICO: Foreground service
      autoStart: true,
      autoStartOnBoot: true,
      notificationChannelId: AppConfig.notificationChannelId,
      initialNotificationTitle: '🎵 Scrobbler Activo',
      initialNotificationContent: 'Monitoreando tu música en segundo plano',
      foregroundServiceNotificationId:
          AppConfig.foregroundServiceNotificationId,
    ),
    iosConfiguration: IosConfiguration(),
  );

  // Forzar inicio explícito por si acaso autoStart falla
  final isRunning = await service.isRunning();
  if (!isRunning) {
    print('🚀 Forzando inicio del servicio...');
    service.startService();
  } else {
    print('✅ El servicio ya estaba corriendo.');
  }

  // Iniciar servicio nativo de monitoreo para reiniciar después de clear all
  try {
    const platform = MethodChannel(AppConfig.restartServiceMethodChannel);
    await platform.invokeMethod('startRestartService');
    print('🛡️ Servicio de reinicio automático activado');
  } catch (e) {
    print('⚠️ No se pudo iniciar RestartService: $e');
  }

  // Iniciar Watchdog con AlarmManager (revisa cada 5 min - más agresivo)
  try {
    const platform = MethodChannel(AppConfig.restartServiceMethodChannel);
    await platform.invokeMethod('startWatchdog');
    print('🐕 Watchdog activado - Verificará el servicio cada 5 minutos');
  } catch (e) {
    print('⚠️ No se pudo iniciar Watchdog: $e');
  }
  
  // Watchdog adicional desde Flutter (verifica cada 5 minutos)
  try {
    const platform = MethodChannel(AppConfig.restartServiceMethodChannel);
    await platform.invokeMethod('startWatchdog');
    print('🐕‍🦺 Watchdog Flutter activado - Verificará cada 5 minutos');
  } catch (e) {
    print('⚠️ No se pudo iniciar Watchdog Flutter: $e');
  }
}
