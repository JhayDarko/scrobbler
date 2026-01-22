import 'package:flutter/material.dart';
import '../services/sync_service.dart';
import '../database/db_helper.dart';

/// Página de diagnóstico para troubleshooting de Supabase
class DiagnosticPage extends StatefulWidget {
  const DiagnosticPage({super.key});

  @override
  State<DiagnosticPage> createState() => _DiagnosticPageState();
}

class _DiagnosticPageState extends State<DiagnosticPage> {
  final SyncService _syncService = SyncService();
  final DBHelper _dbHelper = DBHelper();
  
  Map<String, dynamic>? _diagnosticResult;
  bool _isRunning = false;
  int _unsyncedCount = 0;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _loadLocalStats();
  }

  Future<void> _loadLocalStats() async {
    final unsynced = await _dbHelper.getUnsynced();
    final all = await _dbHelper.getScrobbles();
    setState(() {
      _unsyncedCount = unsynced.length;
      _totalCount = all.length;
    });
  }

  Future<void> _runDiagnostic() async {
    setState(() {
      _isRunning = true;
      _diagnosticResult = null;
    });

    try {
      final result = await _syncService.diagnosticSupabase();
      setState(() {
        _diagnosticResult = result;
      });
    } catch (e) {
      setState(() {
        _diagnosticResult = {
          'connection': false,
          'canRead': false,
          'canInsert': false,
          'tableExists': false,
          'error': 'Error ejecutando diagnóstico: $e',
        };
      });
    } finally {
      setState(() {
        _isRunning = false;
      });
    }
  }

  Color _getStatusColor(bool? status) {
    if (status == null) return Colors.grey;
    return status ? Colors.green : Colors.red;
  }

  IconData _getStatusIcon(bool? status) {
    if (status == null) return Icons.help_outline;
    return status ? Icons.check_circle : Icons.error;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico de Supabase'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Estadísticas locales
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Base de datos local',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatCard(
                          'Total',
                          '$_totalCount',
                          Icons.music_note,
                          Colors.blue,
                        ),
                        _buildStatCard(
                          'Sin sincronizar',
                          '$_unsyncedCount',
                          Icons.cloud_off,
                          _unsyncedCount > 0 ? Colors.orange : Colors.green,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Botón de diagnóstico
            Center(
              child: ElevatedButton.icon(
                onPressed: _isRunning ? null : _runDiagnostic,
                icon: _isRunning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.medical_services),
                label: Text(
                  _isRunning ? 'Ejecutando...' : 'Ejecutar diagnóstico',
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Resultados del diagnóstico
            if (_diagnosticResult != null) ...[
              Text(
                'Resultados',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ListView(
                      children: [
                        _buildDiagnosticItem(
                          'Conexión a Supabase',
                          _diagnosticResult!['connection'] as bool?,
                        ),
                        const Divider(),
                        _buildDiagnosticItem(
                          'Tabla existe',
                          _diagnosticResult!['tableExists'] as bool?,
                        ),
                        const Divider(),
                        _buildDiagnosticItem(
                          'Puede leer',
                          _diagnosticResult!['canRead'] as bool?,
                        ),
                        const Divider(),
                        _buildDiagnosticItem(
                          'Puede insertar',
                          _diagnosticResult!['canInsert'] as bool?,
                        ),
                        if (_diagnosticResult!['error'] != null) ...[
                          const Divider(),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.error, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text(
                                      'Error detectado',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _diagnosticResult!['error'].toString(),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              
              // Soluciones recomendadas
              if (_diagnosticResult!['canInsert'] == false)
                Card(
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.lightbulb, color: Colors.orange),
                            SizedBox(width: 8),
                            Text(
                              'Solución probable',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '1. Ve a Supabase Dashboard\n'
                          '2. Authentication → Policies (tabla scrobbles)\n'
                          '3. Desactiva RLS o agrega política de INSERT para anon\n\n'
                          'SQL recomendado:',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const SelectableText(
                            'CREATE POLICY "Allow anon insert"\n'
                            'ON scrobbles FOR INSERT\n'
                            'TO anon WITH CHECK (true);',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, size: 32, color: color),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildDiagnosticItem(String label, bool? status) {
    return ListTile(
      leading: Icon(
        _getStatusIcon(status),
        color: _getStatusColor(status),
        size: 32,
      ),
      title: Text(label),
      trailing: Text(
        status == null ? 'N/A' : (status ? 'OK' : 'ERROR'),
        style: TextStyle(
          color: _getStatusColor(status),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
