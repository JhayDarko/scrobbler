import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:scrobbler/services/background_service_entry.dart' as bg; // Ya no usamos onStart de aquí, pero dejamos import por tipos si falla algo

Future<void> initializeService(Function(ServiceInstance) onStartCallback) async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'scrobbler_service',
    'Scrobbler Service',
    description: 'Monitorizando música en segundo plano',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  print('🛠️ Configurando Background Service...');
  
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStartCallback,
      isForegroundMode: true,
      autoStart: true, // Intenta auto-arranque
      autoStartOnBoot: true, // Auto-inicio después de reiniciar
      notificationChannelId: 'scrobbler_service',
      initialNotificationTitle: 'Scrobbler Activo',
      initialNotificationContent: 'Iniciando servicio...',
      foregroundServiceNotificationId: 888,
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
    const platform = MethodChannel('com.example.scrobbler/restart_service');
    await platform.invokeMethod('startRestartService');
    print('🛡️ Servicio de reinicio automático activado');
  } catch (e) {
    print('⚠️ No se pudo iniciar RestartService: $e');
  }
  
  // Iniciar Watchdog con AlarmManager (revisa cada 15 min)
  try {
    const platform = MethodChannel('com.example.scrobbler/restart_service');
    await platform.invokeMethod('startWatchdog');
    print('🐕 Watchdog activado - Verificará el servicio cada 15 minutos');
  } catch (e) {
    print('⚠️ No se pudo iniciar Watchdog: $e');
  }
}
