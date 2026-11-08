import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/app_provider.dart';
import '../theme/app_theme.dart';

class FieldTestScreen extends StatefulWidget {
  const FieldTestScreen({super.key});

  @override
  State<FieldTestScreen> createState() => _FieldTestScreenState();
}

class _FieldTestScreenState extends State<FieldTestScreen> {
  final _distController = TextEditingController(text: '50');
  final _notesController = TextEditingController();
  final _latencyController = TextEditingController(text: '45');
  final _batteryController = TextEditingController(text: '88');
  final _rssiController = TextEditingController(text: '-65');

  String _selectedTerrain = 'Ruang Terbuka (Line-of-Sight)';
  bool _isSuccess = true;

  final List<String> _terrains = [
    'Ruang Terbuka (Line-of-Sight)',
    'Pepohonan / Hutan Rimbun',
    'Permukiman / Bangunan Beton',
    'Lereng Pegunungan / Terhalang Bukit',
  ];

  @override
  void dispose() {
    _distController.dispose();
    _notesController.dispose();
    _latencyController.dispose();
    _batteryController.dispose();
    _rssiController.dispose();
    super.dispose();
  }

  void _submitTestLog(AppProvider provider) async {
    final dist = double.tryParse(_distController.text.trim()) ?? 0.0;
    final latency = int.tryParse(_latencyController.text.trim()) ?? 0;
    final battery = double.tryParse(_batteryController.text.trim()) ?? 100.0;
    final rssi = int.tryParse(_rssiController.text.trim()) ?? -70;
    final notes = _notesController.text.trim();

    final targetPeer = provider.peers.isNotEmpty
        ? provider.peers.first.deviceName
        : 'Node-Uji';

    await provider.recordFieldTest(
      targetPeer: targetPeer,
      distanceMeters: dist,
      terrainType: _selectedTerrain,
      success: _isSuccess,
      latencyMs: latency,
      rssi: rssi,
      batteryLevel: battery,
      notes: notes.isEmpty ? 'Uji lapangan standar' : notes,
    );

    _notesController.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hasil pengujian lapangan berhasil dicatat di SQLite lokal.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        final logs = provider.fieldTestLogs;
        final totalTests = logs.length;
        final successfulTests = logs.where((l) => l['success'] == 1).length;
        final double successRate = totalTests > 0 ? (successfulTests / totalTests * 100) : 0.0;

        double maxVerifiedDist = 0.0;
        for (final l in logs) {
          if (l['success'] == 1 && l['distance_meters'] != null) {
            final d = (l['distance_meters'] as num).toDouble();
            if (d > maxVerifiedDist) maxVerifiedDist = d;
          }
        }

        void showExportResult(String title, String path) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppTheme.surface,
              title: Row(
                children: [
                  const Icon(Icons.file_download_done_rounded, color: AppTheme.accent, size: 22),
                  const SizedBox(width: 8),
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('File data berhasil diekspor secara offline ke penyimpanan lokal:', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: SelectableText(
                      path,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppTheme.primary),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Selesai', style: TextStyle(color: AppTheme.accent)),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Diagnostik & Uji Lapangan'),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.download_rounded, color: AppTheme.primary),
                tooltip: 'Ekspor Data Penelitian',
                color: AppTheme.surfaceVariant,
                onSelected: (value) async {
                  if (value == 'csv_logs') {
                    final path = await provider.exportFieldTestLogsToCsv();
                    showExportResult('Ekspor Log Uji CSV', path);
                  } else if (value == 'csv_msgs') {
                    final path = await provider.exportMessagesToCsv();
                    showExportResult('Ekspor Riwayat Pesan CSV', path);
                  } else if (value == 'json_dump') {
                    final path = await provider.exportAllToJson();
                    showExportResult('Ekspor Full Dump JSON', path);
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'csv_logs',
                    child: Row(
                      children: [
                        Icon(Icons.table_chart_outlined, size: 18, color: AppTheme.accent),
                        SizedBox(width: 8),
                        Text('Ekspor Log Uji (.CSV)'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'csv_msgs',
                    child: Row(
                      children: [
                        Icon(Icons.chat_outlined, size: 18, color: AppTheme.primary),
                        SizedBox(width: 8),
                        Text('Ekspor Pesan (.CSV)'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'json_dump',
                    child: Row(
                      children: [
                        Icon(Icons.code_rounded, size: 18, color: AppTheme.warning),
                        SizedBox(width: 8),
                        Text('Ekspor Full Dump (.JSON)'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Card Batasan Fisik & Target Penelitian (Kepatuhan Spesifikasi Bagian 1, 9, 10)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.science_outlined, color: AppTheme.primary, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'STANDAR PENELITIAN & UJI LAPANGAN',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Sinyal radio ponsel standar (Bluetooth / Wi-Fi) memiliki batas daya fisik. Target jarak 5–20 km diperlakukan sebagai sasaran penelitian, bukan klaim kemampuan instan tanpa relay perantara. Catat data lapangan secara objektif di sini.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.35),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Kartu Statistik Pengujian
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total Pengujian', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                          const SizedBox(height: 4),
                          Text('$totalTests kali', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Tingkat Keberhasilan', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                          const SizedBox(height: 4),
                          Text(
                            '${successRate.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: successRate > 70 ? AppTheme.accent : AppTheme.warning,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Jarak Teruji Maks', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                          const SizedBox(height: 4),
                          Text(
                            maxVerifiedDist > 1000
                                ? '${(maxVerifiedDist / 1000).toStringAsFixed(1)} km'
                                : '${maxVerifiedDist.toStringAsFixed(0)} m',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Form Catat Uji Lapangan Baru
              const Text(
                'CATAT PENGUJIAN BARU:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 10),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _selectedTerrain,
                        decoration: const InputDecoration(labelText: 'Kondisi Medan / Lingkungan'),
                        items: _terrains.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13)))).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedTerrain = val);
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _distController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Jarak (meter)'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _rssiController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'RSSI (dBm)'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _latencyController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Latency (ms)'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _batteryController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Baterai (%)'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _notesController,
                        decoration: const InputDecoration(labelText: 'Catatan Kendala / Rintangan'),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: const Text('Pengiriman Berhasil (ACK Diterima)', style: TextStyle(fontSize: 14)),
                        value: _isSuccess,
                        activeThumbColor: AppTheme.accent,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) => setState(() => _isSuccess = val),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.save_rounded, size: 18),
                          label: const Text('Simpan Data Uji Lapangan'),
                          onPressed: () => _submitTestLog(provider),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Riwayat Pengujian
              const Text(
                'RIWAYAT HASIL UJI LAPANGAN:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 10),

              if (logs.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Text('Belum ada log uji lapangan tersimpan.', style: TextStyle(color: AppTheme.textSecondary)),
                  ),
                )
              else
                ...logs.map((log) {
                  final bool ok = log['success'] == 1;
                  final timeStr = DateFormat('dd/MM HH:mm').format(DateTime.parse(log['timestamp']));
                  final dist = log['distance_meters'] ?? 0;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        color: ok ? AppTheme.accent : AppTheme.sosRed,
                      ),
                      title: Text(
                        '${dist}m • ${log['terrain_type']}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      subtitle: Text(
                        '$timeStr • RSSI: ${log['rssi']} dBm • Latency: ${log['latency_ms']}ms\nCatatan: ${log['notes'] ?? '-'}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                      isThreeLine: true,
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}
