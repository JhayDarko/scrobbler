import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scrobbler/services/scrobble_service.dart'; // Reutilizamos lógica de negocio

// Punto de entrada global para el background service
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Inicialización de notificaciones para el Foreground Service
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'scrobbler_service',
    'Scrobbler Service',
    description: 'Monitorizando música en segundo plano',
    importance: Importance.low,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // NOTA: Configuración YA FUE HECHA en main.dart con service.configure()
  // No debemos llamar configure() aquí dentro.
  
  // Instancia del servicio de lógica
  print('🚀 BACKGROUND SERVICE: Iniciando lógica...');
  final scrobbleLogic = BackgroundScrobbleLogic();
  
  // Timer principal: Revisa la cola cada 2 segundos
  Timer.periodic(const Duration(seconds: 2), (timer) async {
    // print('⏰ Tick de background...'); // Demasiado ruido, solo logs útiles
    await scrobbleLogic.processQueue();
  });
}

class BackgroundScrobbleLogic {
  final ScrobbleService _scrobbleService = ScrobbleService();
  
  BackgroundScrobbleLogic() {
    print('📦 BackgroundLogic: Constructor');
    _scrobbleService.initDB();
  }

  Future<void> processQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // FORZAMOS RECARGA para ver cambios de otros procesos (Nativo)

    // DEBUG PROFUNDO DE KEYS (Solo la primera vez o si hay cola)
    // final keys = prefs.getKeys();
    // if (keys.contains('scrobble_queue')) {
    //    print('🔑 Keys encontradas: $keys'); 
    // }

    final String? rawQueue = prefs.getString('scrobble_queue');
    
    if (rawQueue != null && rawQueue != "[]") {
       print('📥 COLA ENCONTRADA (Raw): $rawQueue');
       
       try {
          final List<dynamic> queue = jsonDecode(rawQueue);
          if (queue.isNotEmpty) {
             print('🔄 Procesando ${queue.length} items...');
             for (var item in queue) {
                _scrobbleService.processBackgroundEvent(item);
             }
             await prefs.setString('scrobble_queue', "[]");
             print('🗑️ Cola vaciada.');
          }
       } catch (e) {
          print('❌ Error decode JSON: $e');
       }
    }
  }
}
