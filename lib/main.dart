import 'dart:async';
import 'dart:convert';
import 'dart:ui'; // Para DartPluginRegistrant
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:scrobbler/services/scrobble_service.dart';
import 'package:scrobbler/database/db_helper.dart';
import 'package:scrobbler/models/scrobble.dart';
import 'package:scrobbler/services/sync_service.dart';
import 'package:scrobbler/pages/settings_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'package:scrobbler/services/service_initializer.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Esta es la función que se ejecuta en el "limbo" de Android para Workmanager
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await Supabase.initialize(
      url: 'https://uimgfmkfiikhsemgbgva.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVpbWdmbWtmaWlraHNlbWdiZ3ZhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg4NTk5NzEsImV4cCI6MjA4NDQzNTk3MX0.lv4iIntC7cpOq8DAbMp_4T507M-5WqV2oOv6cUHFZP8',
    );

    await SyncService().syncData();
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicializar servicio en background PASANDO la función onStart
  await initializeService(onStart);

  await Supabase.initialize(
    url: 'https://uimgfmkfiikhsemgbgva.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVpbWdmbWtmaWlraHNlbWdiZ3ZhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg4NTk5NzEsImV4cCI6MjA4NDQzNTk3MX0.lv4iIntC7cpOq8DAbMp_4T507M-5WqV2oOv6cUHFZP8',
  );

  // Inicializar Workmanager
  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  // Registrar tarea periódica (cada 15 min mínimo por Android)
  Workmanager().registerPeriodicTask(
    "1",
    "syncTask",
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
  );

  ScrobbleService().startListening();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return MaterialApp(
          title: 'YTM Scrobbler',
          theme: ThemeData(colorScheme: lightDynamic, useMaterial3: true),
          darkTheme: ThemeData(colorScheme: darkDynamic, useMaterial3: true),
          home: const HomeScreen(),
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _dbHelper = DBHelper();
  final _syncService = SyncService();
  final _streamController = StreamController<List<Scrobble>>.broadcast();
  Timer? _refreshTimer;
  Timer? _statusCheckTimer;
  bool _isSyncing = false;
  bool _isServiceEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadScrobbles();
    _checkServiceStatus();

    // Actualizar cada 5 segundos para reflejar cambios
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _loadScrobbles();
    });

    // Verificar estado del servicio cada 10 segundos
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkServiceStatus();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _statusCheckTimer?.cancel();
    _streamController.close();
    super.dispose();
  }

  Future<void> _checkServiceStatus() async {
    try {
      final hasPermission = await NativeNotificationService.isPermissionGranted();
      if (mounted && _isServiceEnabled != hasPermission) {
        setState(() => _isServiceEnabled = hasPermission);
      }
    } catch (e) {
      print('Error verificando estado del servicio: $e');
    }
  }

  Future<void> _loadScrobbles() async {
    final scrobbles = await _dbHelper.getScrobbles(limit: 100);
    if (!_streamController.isClosed) {
      _streamController.add(scrobbles);
    }
  }

  Future<void> _syncManually() async {
    if (_isSyncing) return;

    setState(() => _isSyncing = true);

    try {
      final result = await _syncService.syncData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                result.success ? '✅ ${result.message}' : '❌ ${result.message}'),
            backgroundColor: result.success ? Colors.green : Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      await _loadScrobbles(); // Recargar después de sync
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "YTM Scrobbler",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          // Botón de sync manual
          IconButton(
            onPressed: _isSyncing ? null : _syncManually,
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload),
            tooltip: 'Sincronizar ahora',
          ),
          // Botón de configuración
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
            tooltip: 'Configuración',
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner de advertencia si servicio no está activo
          if (!_isServiceEnabled)
            MaterialBanner(
              backgroundColor: Colors.orange.shade100,
              leading: const Icon(Icons.warning, color: Colors.orange),
              content: const Text(
                'Servicio de detección inactivo.\nActiva los permisos para detectar música.',
                style: TextStyle(fontSize: 13),
              ),
              actions: [
                TextButton(
                  onPressed: _openSettings,
                  child: const Text('CONFIGURAR'),
                ),
              ],
            ),

          // Lista de scrobbles
          Expanded(
            child: StreamBuilder<List<Scrobble>>(
              stream: _streamController.stream,
              builder: (context, snapshot) {
                // Loading
                if (!snapshot.hasData) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Cargando scrobbles...'),
                      ],
                    ),
                  );
                }

                final scrobbles = snapshot.data!;

                // Empty state
                if (scrobbles.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.music_note_outlined,
                          size: 80,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No hay scrobbles aún',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            _isServiceEnabled
                                ? 'Reproduce música en YouTube Music\npara comenzar a registrar scrobbles'
                                : 'Activa el servicio en Configuración\ny luego reproduce música',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (!_isServiceEnabled)
                          FilledButton.icon(
                            onPressed: _openSettings,
                            icon: const Icon(Icons.settings),
                            label: const Text('Configurar Ahora'),
                          ),
                      ],
                    ),
                  );
                }

                // List of scrobbles
                return RefreshIndicator(
                  onRefresh: () async {
                    await _syncManually();
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: scrobbles.length,
                    itemBuilder: (context, index) {
                      final scrobble = scrobbles[index];
                      return Card(
                        elevation: 0,
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          leading: CircleAvatar(
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
                            child: const Icon(Icons.music_note,
                                color: Colors.white),
                          ),
                          title: Text(
                            scrobble.track,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                scrobble.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${scrobble.album} • ${scrobble.formattedDuration}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                          trailing: Icon(
                            scrobble.isSynced == 1
                                ? Icons.check_circle
                                : Icons.cloud_upload_outlined,
                            color: scrobble.isSynced == 1
                                ? Colors.green
                                : Theme.of(context).colorScheme.outline,
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- BACKGROUND SERVICE LOGIC ---

// Punto de entrada global para el background service
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // CRÍTICO: Inicializar Supabase en este isolate
  // ScrobbleService -> SyncService necesita Supabase.instance
  await Supabase.initialize(
    url: 'https://uimgfmkfiikhsemgbgva.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVpbWdmbWtmaWlraHNlbWdiZ3ZhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg4NTk5NzEsImV4cCI6MjA4NDQzNTk3MX0.lv4iIntC7cpOq8DAbMp_4T507M-5WqV2oOv6cUHFZP8',
  );

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

  print('🚀 BACKGROUND SERVICE: Iniciando lógica (Supabase OK)...');
  
  // Instancia del servicio de lógica
  final scrobbleLogic = BackgroundScrobbleLogic();
  
  // Timer principal: Revisa la cola cada 2 segundos
  Timer.periodic(const Duration(seconds: 2), (timer) async {
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
    await prefs.reload(); // FORZAMOS RECARGA

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
          await prefs.setString('scrobble_queue', "[]");
       }
    }
  }
}
