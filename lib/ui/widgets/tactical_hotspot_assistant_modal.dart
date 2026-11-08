import 'package:flutter/material.dart';
import '../../services/native_hardware_service.dart';
import '../../services/lora_bridge_service.dart';
import '../theme/app_theme.dart';

class TacticalHotspotAssistantModal extends StatefulWidget {
  const TacticalHotspotAssistantModal({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const TacticalHotspotAssistantModal(),
    );
  }

  @override
  State<TacticalHotspotAssistantModal> createState() => _TacticalHotspotAssistantModalState();
}

class _TacticalHotspotAssistantModalState extends State<TacticalHotspotAssistantModal> {
  String _localIp = 'Memeriksa...';
  bool _isBtEnabled = false;
  int _bondedBtCount = 0;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _fetchNetworkStatus();
  }

  Future<void> _fetchNetworkStatus() async {
    setState(() => _isChecking = true);
    final ip = await NativeHardwareService.instance.getLocalIpAddress();
    final btEnabled = await NativeHardwareService.instance.isBluetoothEnabled();
    final bonded = await NativeHardwareService.instance.getBondedBluetoothDevices();

    if (mounted) {
      setState(() {
        _localIp = ip;
        _isBtEnabled = btEnabled;
        _bondedBtCount = bonded.length;
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPoskoHotspot = _localIp.startsWith('192.168.43.1') || _localIp.endsWith('.1');
    final isConnectedSubnet = _localIp != '127.0.0.1' && _localIp != 'Memeriksa...';
    final lora = LoraBridgeService.instance;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.wifi_tethering_rounded, color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ASISTEN JARINGAN LAPANGAN TAKTIS',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: AppTheme.primary,
                      ),
                    ),
                    Text(
                      'Komunikasi darurat jarak dekat hingga 20 km tanpa internet',
                      style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              _isChecking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                    )
                  : IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 20, color: AppTheme.textSecondary),
                      tooltip: 'Perbarui Status',
                      onPressed: _fetchNetworkStatus,
                    ),
            ],
          ),

          const SizedBox(height: 16),

          // Status Kartu Diagnostik Radio
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isConnectedSubnet ? AppTheme.accent.withValues(alpha: 0.4) : AppTheme.border,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Status IP Subnet:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isConnectedSubnet ? AppTheme.accent : AppTheme.warning,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _localIp,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isConnectedSubnet ? AppTheme.accent : AppTheme.warning,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Peran Wi-Fi Saat Ini:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    Text(
                      isPoskoHotspot
                          ? 'PUSAT HOTSPOT (POSKO)'
                          : isConnectedSubnet
                              ? 'TERHUBUNG KE HOTSPOT'
                              : 'STANDALONE (BELUM TERSAMBUNG)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isConnectedSubnet ? AppTheme.textPrimary : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16, color: AppTheme.border),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Bluetooth RFCOMM:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    Text(
                      _isBtEnabled ? 'AKTIF ($_bondedBtCount Terpasang)' : 'NONAKTIF',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: _isBtEnabled ? AppTheme.primary : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Modem LoRa (5-20km):', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    Text(
                      lora.isConnected ? 'TERHUBUNG' : 'STANDBY (USB OTG)',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: lora.isConnected ? AppTheme.accent : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Tombol Tindakan Cepat
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF132D28),
                    foregroundColor: AppTheme.accent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
                  label: const Text('Buka Hotspot HP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () => NativeHardwareService.instance.openTetheringSettings(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.bluetooth_rounded, size: 18),
                  label: const Text('Buka Bluetooth', style: TextStyle(fontSize: 12)),
                  onPressed: () => NativeHardwareService.instance.openBluetoothSettings(),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // SOP Taktis Lapangan
          const Text(
            'SOP PEMBENTUKAN JARINGAN DARURAT TANPA INTERNET:',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.6),
          ),
          const SizedBox(height: 8),

          _buildStepRow(
            step: '1',
            title: 'Satu HP Menyalakan Hotspot (Pusat Posko)',
            desc: 'Salah satu relawan menyalakan "Hotspot Portabel" di HP (tidak perlu ada kuota atau pulsa).',
          ),
          const SizedBox(height: 8),
          _buildStepRow(
            step: '2',
            title: 'HP Rekan-Rekan Menyambung ke Wi-Fi Hotspot',
            desc: 'Semua anggota tim menyambung ke Wi-Fi tersebut. Dalam 1 detik, radar SinyalNol akan saling mendeteksi secara otomatis.',
          ),
          const SizedBox(height: 8),
          _buildStepRow(
            step: '3',
            title: 'Jalur Cadangan Bluetooth (Tanpa Wi-Fi)',
            desc: 'Jika Wi-Fi mati, pasangkan (pair) HP via Bluetooth. Pesan teks dan koordinat SOS akan otomatis terkirim lewat jalur Bluetooth RFCOMM.',
          ),
          const SizedBox(height: 8),
          _buildStepRow(
            step: '4',
            title: 'Jarak Ekstrem 5 - 20 KM (Radio LoRa)',
            desc: 'Untuk menembus gunung atau hutan lebat, colokkan modul radio ESP32 LoRa fisik ke port USB-C ponsel menggunakan kabel USB-OTG.',
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow({required String step, required String title, required String desc}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5)),
          ),
          child: Text(
            step,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              const SizedBox(height: 2),
              Text(desc, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}
