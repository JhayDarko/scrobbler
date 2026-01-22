import 'package:flutter/material.dart';
import '../services/scrobble_service.dart'; // Para NativeNotificationService
import 'diagnostic_page.dart'; // Para diagnóstico de Supabase

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isServiceEnabled = false;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkServiceStatus();
  }

  Future<void> _checkServiceStatus() async {
    setState(() => _isChecking = true);

    try {
      final hasPermission =
          await NativeNotificationService.isPermissionGranted();
      setState(() {
        _isServiceEnabled = hasPermission;
        _isChecking = false;
      });
    } catch (e) {
      print('Error verificando estado del servicio: $e');
      setState(() {
        _isServiceEnabled = false;
        _isChecking = false;
      });
    }
  }

  Future<void> _requestPermission() async {
    try {
      await NativeNotificationService.requestPermission();
      // Esperar un poco antes de verificar de nuevo
      await Future.delayed(const Duration(seconds: 1));
      await _checkServiceStatus();
    } catch (e) {
      print('Error solicitando permiso: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración'), centerTitle: true),
      body: _isChecking
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Estado del servicio
                Card(
                  color: _isServiceEnabled
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(
                          _isServiceEnabled
                              ? Icons.check_circle
                              : Icons.error_outline,
                          size: 64,
                          color: _isServiceEnabled ? Colors.green : Colors.red,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isServiceEnabled
                              ? '✅ Servicio Activo'
                              : '❌ Servicio Inactivo',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: _isServiceEnabled
                                    ? Colors.green
                                    : Colors.red,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isServiceEnabled
                              ? 'La app puede detectar música de YouTube Music'
                              : 'Necesitas activar los permisos para que funcione',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Botón de diagnóstico de Supabase
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.medical_services),
                    title: const Text('Diagnóstico de Supabase'),
                    subtitle: const Text('Verificar sincronización y permisos'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const DiagnosticPage(),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 24),

                // Instrucciones paso a paso
                if (!_isServiceEnabled) ...[
                  Text(
                    'Cómo activar el servicio',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildStep(
                    context,
                    number: 1,
                    title: 'Abrir configuración',
                    description:
                        'Presiona el botón abajo para abrir la configuración del sistema',
                  ),
                  const SizedBox(height: 12),
                  _buildStep(
                    context,
                    number: 2,
                    title: 'Buscar "YTM Scrobbler" o "scrobbler"',
                    description:
                        'En la lista de apps, busca y selecciona esta aplicación',
                  ),
                  const SizedBox(height: 12),
                  _buildStep(
                    context,
                    number: 3,
                    title: 'Activar el switch',
                    description:
                        'Activa el interruptor para permitir que la app lea notificaciones',
                  ),
                  const SizedBox(height: 12),
                  _buildStep(
                    context,
                    number: 4,
                    title: 'Volver a la app',
                    description:
                        'Regresa a esta app y verifica que el estado cambió a "Activo"',
                  ),
                  const SizedBox(height: 24),

                  // Botón para abrir configuración
                  FilledButton.icon(
                    onPressed: _requestPermission,
                    icon: const Icon(Icons.settings),
                    label: const Text('Abrir Configuración del Sistema'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Botón para verificar de nuevo
                OutlinedButton.icon(
                  onPressed: _checkServiceStatus,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Verificar Estado Nuevamente'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),

                const SizedBox(height: 32),

                // Información adicional
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Información importante',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '• Esta app necesita acceso a notificaciones para detectar qué música estás reproduciendo en YouTube Music\n\n'
                          '• Solo lee notificaciones de YouTube Music, ninguna otra app\n\n'
                          '• Los datos se guardan localmente y se sincronizan con tu cuenta de Supabase\n\n'
                          '• Si el servicio se desactiva, necesitarás volver a activarlo desde esta página',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStep(
    BuildContext context, {
    required int number,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Text(
            '$number',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
