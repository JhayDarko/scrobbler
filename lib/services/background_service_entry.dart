import 'dart:async';
import 'dart:convert';
import 'dart:ui';
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
    importance: Importance.high, // Alta para servicio persistente
    showBadge: true,
    playSound: false,
    enableVibration: false,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // NOTA: Configuración YA FUE HECHA en main.dart con service.configure()
  // No debemos llamar configure() aquí dentro.
  
  // Actualizar notificación foreground con estado actual
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: "🎵 Scrobbler Activo",
      content: "Monitoreando música - Presiona para abrir",
    );
  }
  
  // Instancia del servicio de lógica
  print('🚀 BACKGROUND SERVICE: Iniciando lógica...');
  final scrobbleLogic = BackgroundScrobbleLogic(service);
  
  // Timer principal: Revisa la cola cada 2 segundos
  Timer.periodic(const Duration(seconds: 2), (timer) async {
    await scrobbleLogic.processQueue();
  });
  
  // Timer para actualizar la notificación cada 30 segundos
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    await scrobbleLogic.updateNotification();
  });
}

class BackgroundScrobbleLogic {
  final ScrobbleService _scrobbleService = ScrobbleService();
  final ServiceInstance _serviceInstance;
  int _scrobblesProcessed = 0;
  DateTime? _lastScrobbleTime;
  
  BackgroundScrobbleLogic(this._serviceInstance) {
    print('📦 BackgroundLogic: Constructor');
    _scrobbleService.initDB();
  }

  Future<void> updateNotification() async {
    if (_serviceInstance is AndroidServiceInstance) {
      final elapsed = _lastScrobbleTime != null 
          ? DateTime.now().difference(_lastScrobbleTime!).inMinutes 
          : 0;
      
      final content = _scrobblesProcessed > 0
          ? "✅ $_scrobblesProcessed scrobbles • Último hace ${elapsed}min"
          : "🎧 Esperando música...";
      
      (_serviceInstance as AndroidServiceInstance).setForegroundNotificationInfo(
        title: "🎵 Scrobbler Activo",
        content: content,
      );
    }
  }

  Future<void> processQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // FORZAMOS RECARGA para ver cambios de otros procesos (Nativo)

    final String? rawQueue = prefs.getString('scrobble_queue');
    
    if (rawQueue != null && rawQueue != "[]") {
       print('📥 COLA ENCONTRADA (Raw): $rawQueue');
       
       try {
          final List<dynamic> queue = jsonDecode(rawQueue);
          if (queue.isNotEmpty) {
             print('🔄 Procesando ${queue.length} items...');
             for (var item in queue) {
                _scrobbleService.processBackgroundEvent(item);
                _scrobblesProcessed++;
                _lastScrobbleTime = DateTime.now();
             }
             await prefs.setString('scrobble_queue', "[]");
             print('🗑️ Cola vaciada.');
             
             // Actualizar notificación inmediatamente después de procesar
             await updateNotification();
          }
       } catch (e) {
          print('❌ Error decode JSON: $e');
       }
    }
  }
}
