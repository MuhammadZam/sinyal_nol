import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/peer_device.dart';
import '../../providers/app_provider.dart';
import '../theme/app_theme.dart';
import 'chat_conversation_screen.dart';
import 'tactical_map_screen.dart';
import 'tactical_qr_scanner_screen.dart';
import '../widgets/tactical_hotspot_assistant_modal.dart';

class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _showAddSimulatedPeerDialog(BuildContext context, AppProvider provider) {
    final nameCtrl = TextEditingController(text: 'Posko-SAR-Alpha');
    final distCtrl = TextEditingController(text: '120');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Tambah Node Simulasi (Uji Coba)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Gunakan simulasi ini untuk menguji pengiriman pesan dan rantai Smart Relay di satu perangkat.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nama Node / Perangkat'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: distCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Perkiraan Jarak (meter)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final dist = double.tryParse(distCtrl.text.trim()) ?? 100.0;
              await provider.addSimulatedPeer(name: name, estimatedDistance: dist);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Tambahkan'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        final peers = provider.peers;

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Radar & Navigasi Taktis'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.wifi_tethering_rounded, color: AppTheme.primary),
                  tooltip: 'Asisten Jaringan Lapangan (Hotspot / Bluetooth)',
                  onPressed: () => TacticalHotspotAssistantModal.show(context),
                ),
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner_rounded, color: AppTheme.accent),
                  tooltip: 'Pindai QR Identitas Rekan SAR',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TacticalQrScannerScreen()),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Simulasi Node untuk Uji Coba',
                  onPressed: () => _showAddSimulatedPeerDialog(context, provider),
                ),
              ],
              bottom: const TabBar(
                indicatorColor: AppTheme.primary,
                indicatorWeight: 3,
                tabs: [
                  Tab(
                    icon: Icon(Icons.radar_rounded),
                    text: 'Radar Sinyal RF',
                  ),
                  Tab(
                    icon: Icon(Icons.explore_rounded),
                    text: 'Peta Taktis & Waypoint',
                  ),
                ],
              ),
            ),
            body: TabBarView(
              physics: const NeverScrollableScrollPhysics(), // Memastikan gesture canvas di map tidak terpotong tab swipe
              children: [
                _buildRfRadarView(context, provider, peers),
                const TacticalMapScreen(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRfRadarView(BuildContext context, AppProvider provider, List<PeerDevice> peers) {
    return Column(
      children: [
              // Radar Visualizer Header
              Container(
                height: 220,
                width: double.infinity,
                color: AppTheme.surface,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Concentric Animated Rings
                    AnimatedBuilder(
                      animation: _animController,
                      builder: (context, child) {
                        return CustomPaint(
                          size: const Size(220, 220),
                          painter: RadarPainter(progress: _animController.value),
                        );
                      },
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cell_tower, color: AppTheme.primary, size: 36),
                        const SizedBox(height: 6),
                        Text(
                          'ID: ${provider.localDeviceId}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                        ),
                        Text(
                          '${peers.length} Node Terdeteksi',
                          style: const TextStyle(fontSize: 11, color: AppTheme.accent),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () {
                            provider.setBatterySaver(!provider.isBatterySaverEnabled);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: provider.isBatterySaverEnabled
                                  ? AppTheme.warning.withValues(alpha: 0.2)
                                  : AppTheme.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: provider.isBatterySaverEnabled ? AppTheme.warning : AppTheme.primary,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  provider.isBatterySaverEnabled ? Icons.battery_saver : Icons.bolt,
                                  size: 13,
                                  color: provider.isBatterySaverEnabled ? AppTheme.warning : AppTheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  provider.isBatterySaverEnabled ? 'ECO BEACON (15s)' : 'ACTIVE BEACON (4s)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    color: provider.isBatterySaverEnabled ? AppTheme.warning : AppTheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceVariant,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.explore_outlined, size: 11, color: AppTheme.primary),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${provider.compassHeading.toStringAsFixed(0)}°',
                                    style: const TextStyle(fontSize: 9, fontFamily: 'monospace', color: AppTheme.primary, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: provider.isLoraConnected ? AppTheme.accent.withValues(alpha: 0.15) : AppTheme.surfaceVariant,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.cell_tower,
                                    size: 11,
                                    color: provider.isLoraConnected ? AppTheme.accent : AppTheme.textSecondary,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    provider.isLoraConnected ? 'LoRa ON' : 'LoRa OFF',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontFamily: 'monospace',
                                      color: provider.isLoraConnected ? AppTheme.accent : AppTheme.textSecondary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, color: AppTheme.border),

              // Banner Panduan Jaringan Taktis
              InkWell(
                onTap: () => TacticalHotspotAssistantModal.show(context),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.wifi_tethering_rounded, size: 16, color: AppTheme.primary),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Asisten Jaringan: Buka Hotspot / Bluetooth Lapangan',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppTheme.textSecondary),
                    ],
                  ),
                ),
              ),

              // Daftar Perangkat Sekitar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'PERANGKAT DALAM JANGKAUAN:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    Text(
                      provider.isRadioActive ? 'Memindai...' : 'Radio Nonaktif',
                      style: TextStyle(
                        fontSize: 11,
                        color: provider.isRadioActive ? AppTheme.accent : AppTheme.sosRed,
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: peers.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.portable_wifi_off_rounded, size: 48, color: AppTheme.textMuted),
                              const SizedBox(height: 12),
                              const Text(
                                'Belum menemukan perangkat fisik di sekitar.',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Pastikan kedua ponsel berada di jaringan Hotspot lokal yang sama, atau klik tombol (+) di pojok kanan atas untuk mensimulasikan node pengujian.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: peers.length,
                        itemBuilder: (context, index) {
                          final peer = peers[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppTheme.surfaceVariant,
                                child: Icon(
                                  peer.connectionType == ConnectionType.simulated
                                      ? Icons.memory_rounded
                                      : Icons.wifi_tethering_rounded,
                                  color: AppTheme.primary,
                                ),
                              ),
                              title: Text(
                                peer.deviceName,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'ID: ${peer.deviceId} • ${peer.address}\nSinyal: ${peer.rssi} dBm ${peer.estimatedDistanceMeters != null ? '• ~${peer.estimatedDistanceMeters!.toStringAsFixed(0)}m' : ''}',
                                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                              ),
                              isThreeLine: true,
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ChatConversationScreen(
                                        peerId: peer.deviceId,
                                        peerName: peer.deviceName,
                                      ),
                                    ),
                                  );
                                },
                                child: const Text('Chat Direct', style: TextStyle(fontSize: 12)),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
  }
}

class RadarPainter extends CustomPainter {
  final double progress;

  RadarPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    final paintLine = Paint()
      ..color = AppTheme.border.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Lingkaran statis
    canvas.drawCircle(center, maxRadius * 0.33, paintLine);
    canvas.drawCircle(center, maxRadius * 0.66, paintLine);
    canvas.drawCircle(center, maxRadius, paintLine);

    // Garis bidik
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), paintLine);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paintLine);

    // Gelombang radar berdenyut
    final pulseRadius = maxRadius * progress;
    final pulsePaint = Paint()
      ..color = AppTheme.primary.withValues(alpha: (1.0 - progress) * 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(center, pulseRadius, pulsePaint);
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) => true;
}
