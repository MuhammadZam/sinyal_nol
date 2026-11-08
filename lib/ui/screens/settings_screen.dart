import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../providers/app_provider.dart';
import '../../services/lora_bridge_service.dart';
import '../../services/tactical_audio_service.dart';
import '../theme/app_theme.dart';
import 'tactical_qr_scanner_screen.dart';
import '../widgets/tactical_hotspot_assistant_modal.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<AppProvider>(context, listen: false);
    _nameController = TextEditingController(text: provider.localDeviceName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _saveName(AppProvider provider) {
    provider.updateDeviceName(_nameController.text);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nama perangkat berhasil diperbarui.')),
    );
  }

  void _showIdentityQrModal(BuildContext context, AppProvider provider) {
    final payload = 'SINYALNOL|${provider.localDeviceId}|${provider.localDeviceName}|${provider.deviceFingerprint}|${provider.myPublicKey}';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_user_rounded, color: AppTheme.primary, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'KARTU IDENTITAS TAKTIS OFFLINE',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primary, letterSpacing: 0.8),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Tunjukkan QR ini ke perangkat rekan SAR untuk validasi identitas fisik secara offline tanpa internet.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.2),
                      blurRadius: 16,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: QrImageView(
                  data: payload,
                  version: QrVersions.auto,
                  size: 200.0,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                provider.localDeviceName,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 4),
              SelectableText(
                'FINGERPRINT: ${provider.deviceFingerprint}',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.accent),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF132D28)),
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 18, color: AppTheme.accent),
                  label: const Text('Buka Pemindai Kamera QR Rekan', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TacticalQrScannerScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Salin Data'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: payload));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Payload identitas disalin ke clipboard.')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.surfaceVariant),
                      icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textPrimary),
                      label: const Text('Tutup', style: TextStyle(color: AppTheme.textPrimary)),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showExportDone(String title, String path) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Row(
          children: [
            const Icon(Icons.file_download_done_rounded, color: AppTheme.accent, size: 22),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('File berhasil disimpan ke penyimpanan lokal perangkat:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black45,
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
            child: const Text('Tutup', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
  }

  void _confirmClearData(BuildContext context, AppProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Hapus Semua Data Lokal?'),
        content: const Text(
          'Seluruh riwayat pesan offline dan log uji lapangan di database SQLite akan dihapus permanen dari ponsel ini.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.sosRed),
            onPressed: () async {
              await provider.clearAllHistory();
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Database lokal telah dibersihkan.')),
                );
              }
            },
            child: const Text('Hapus Data'),
          ),
        ],
      ),
    );
  }

  void _showLoraConfigModal(BuildContext context, AppProvider provider) {
    double freq = provider.loraConfig.frequencyMhz;
    int sf = provider.loraConfig.spreadingFactor;
    int bw = provider.loraConfig.bandwidthKhz;
    int txPower = provider.loraConfig.txPowerDbm;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Row(
                    children: [
                      Icon(Icons.settings_input_antenna_rounded, color: AppTheme.primary, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'PARAMETER MODEM LORA TAKTIS',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primary, letterSpacing: 0.8),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Konfigurasi RF radio transceiver eksternal (Heltec ESP32, SX1262, T-Beam) untuk jangkauan 5 - 20 km.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 18),
                  const Text('FREKUENSI OPERASIONAL:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<double>(
                    initialValue: freq,
                    dropdownColor: AppTheme.surfaceVariant,
                    decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    items: const [
                      DropdownMenuItem(value: 915.0, child: Text('915.0 MHz (Indonesia & US ISM Band)')),
                      DropdownMenuItem(value: 923.0, child: Text('923.0 MHz (AS923 Regional)')),
                      DropdownMenuItem(value: 433.0, child: Text('433.0 MHz (UHF Penetrasi Hutan)')),
                      DropdownMenuItem(value: 868.0, child: Text('868.0 MHz (EU ISM Band)')),
                    ],
                    onChanged: (val) {
                      if (val != null) setModalState(() => freq = val);
                    },
                  ),
                  const SizedBox(height: 14),
                  const Text('SPREADING FACTOR (SF):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int>(
                    initialValue: sf,
                    dropdownColor: AppTheme.surfaceVariant,
                    decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    items: const [
                      DropdownMenuItem(value: 7, child: Text('SF7 (Kecepatan Tertinggi, Jarak Pendek ~3km)')),
                      DropdownMenuItem(value: 8, child: Text('SF8 (Standar Cepat)')),
                      DropdownMenuItem(value: 10, child: Text('SF10 (Default Taktis SAR ~10-15km)')),
                      DropdownMenuItem(value: 12, child: Text('SF12 (Jangkauan Maksimal ~20km, Ekstrem)')),
                    ],
                    onChanged: (val) {
                      if (val != null) setModalState(() => sf = val);
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('BANDWIDTH (BW):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<int>(
                              initialValue: bw,
                              dropdownColor: AppTheme.surfaceVariant,
                              decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                              items: const [
                                DropdownMenuItem(value: 125, child: Text('125 kHz')),
                                DropdownMenuItem(value: 250, child: Text('250 kHz')),
                                DropdownMenuItem(value: 500, child: Text('500 kHz')),
                              ],
                              onChanged: (val) {
                                if (val != null) setModalState(() => bw = val);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('DAYA PANCAR (TX):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<int>(
                              initialValue: txPower,
                              dropdownColor: AppTheme.surfaceVariant,
                              decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                              items: const [
                                DropdownMenuItem(value: 14, child: Text('14 dBm (25 mW)')),
                                DropdownMenuItem(value: 17, child: Text('17 dBm (50 mW)')),
                                DropdownMenuItem(value: 20, child: Text('20 dBm (100 mW)')),
                                DropdownMenuItem(value: 22, child: Text('22 dBm (Maks)')),
                              ],
                              onChanged: (val) {
                                if (val != null) setModalState(() => txPower = val);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Terapkan Konfigurasi RF'),
                      onPressed: () {
                        provider.updateLoraConfig(LoraModemConfig(
                          frequencyMhz: freq,
                          spreadingFactor: sf,
                          bandwidthKhz: bw,
                          txPowerDbm: txPower,
                        ));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Konfigurasi LoRa diperbarui: ${freq}MHz SF$sf')),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (consumerCtx, provider, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Pengaturan & Relay'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Identitas Perangkat
              const Text(
                'IDENTITAS PERANGKAT LOKAL',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Device ID (UUID Unik):', style: TextStyle(color: AppTheme.textSecondary)),
                          Text(
                            provider.localDeviceId,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: AppTheme.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('SHA-256 Fingerprint:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: provider.deviceFingerprint));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Fingerprint disalin ke clipboard.')),
                              );
                            },
                            child: Row(
                              children: [
                                Text(
                                  provider.deviceFingerprint,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: AppTheme.accent,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.copy_rounded, size: 12, color: AppTheme.textSecondary),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24, color: AppTheme.border),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _nameController,
                              decoration: const InputDecoration(labelText: 'Nama Perangkat'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: () => _saveName(provider),
                            child: const Text('Simpan'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                          label: const Text('Buka QR Code Identitas Lapangan'),
                          onPressed: () => _showIdentityQrModal(context, provider),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF132D28)),
                          icon: const Icon(Icons.qr_code_scanner_rounded, size: 18, color: AppTheme.accent),
                          label: const Text('Pindai Kamera QR Rekan SAR', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold)),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const TacticalQrScannerScreen()),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Konektivitas Lapangan Taktis (Off-Grid)
              const Text(
                'KONEKTIVITAS LAPANGAN TAKTIS (OFF-GRID)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),

              Card(
                child: ListTile(
                  leading: const Icon(Icons.wifi_tethering_rounded, color: AppTheme.primary),
                  title: const Text('Asisten Hotspot & Bluetooth Lapangan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('Panduan 1-klik untuk menghubungkan HP tanpa router dan tanpa internet.', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
                  onTap: () => TacticalHotspotAssistantModal.show(context),
                ),
              ),

              const SizedBox(height: 20),

              // Manajemen Daya & Efisiensi Radio
              const Text(
                'MANAJEMEN DAYA RADIO & BATERAI',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),

              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Mode Hemat Daya Lapangan (Eco Mode)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text(
                        'Memperlambat interval beacon radio menjadi 15 detik alih-alih 4 detik saat kondisi siaga untuk menghemat baterai hingga 60%.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      value: provider.isBatterySaverEnabled,
                      activeThumbColor: AppTheme.warning,
                      onChanged: (val) => provider.setBatterySaver(val),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              const SizedBox(height: 20),

              // Audio Taktis, Nada & Notifikasi Radar
              const Text(
                'AUDIO TAKTIS, NADA & NOTIFIKASI RADAR',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),

              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Master Efek Suara Taktis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text(
                        'Mengaktifkan generator nada audio in-memory untuk semua peristiwa taktis.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      value: provider.isSfxEnabled,
                      activeThumbColor: AppTheme.primary,
                      onChanged: (val) => provider.setSfxEnabled(val),
                    ),
                    const Divider(height: 1, color: AppTheme.border),
                    SwitchListTile(
                      title: const Text('Nada Sonar Radar (Node Baru Terhubung)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text(
                        'Bunyikan nada sonar ping (880Hz -> 1320Hz) saat perangkat rekan baru masuk ke dalam radar mesh Anda.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      value: provider.isRadarPingEnabled,
                      activeThumbColor: AppTheme.accent,
                      onChanged: provider.isSfxEnabled ? (val) => provider.setRadarPing(val) : null,
                    ),
                    const Divider(height: 1, color: AppTheme.border),
                    SwitchListTile(
                      title: const Text('Nada Notifikasi Pesan / Info Masuk', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text(
                        'Bunyikan chirp ganda (950Hz -> 1250Hz) setiap kali ada pesan teks atau koordinat darurat baru diterima.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      value: provider.isMessageToneEnabled,
                      activeThumbColor: AppTheme.primary,
                      onChanged: provider.isSfxEnabled ? (val) => provider.setMessageTone(val) : null,
                    ),
                    const Divider(height: 1, color: AppTheme.border),
                    SwitchListTile(
                      title: const Text('Getar Taktis (Haptic Feedback)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text(
                        'Getaran fisik pada ponsel saat ada rekan terhubung, pesan masuk, atau koordinat peta diperbarui.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      value: provider.isVibrationEnabled,
                      activeThumbColor: AppTheme.primary,
                      onChanged: (val) => provider.setVibration(val),
                    ),
                    const Divider(height: 1, color: AppTheme.border),
                    SwitchListTile(
                      title: const Text('Auto-Squawk Suara PTT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text(
                        'Memutar transmisi suara secara otomatis melalui speaker saat diterima, seperti HT/Walkie-Talkie fisik di lapangan.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      value: provider.isAutoSquawkEnabled,
                      activeThumbColor: AppTheme.primary,
                      onChanged: provider.isSfxEnabled ? (val) => provider.setAutoSquawk(val) : null,
                    ),
                    const Divider(height: 1, color: AppTheme.border),
                    SwitchListTile(
                      title: const Text('Roger Beep 2-Tone (Quindar)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text(
                        'Bunyikan nada konfirmasi frekuensi (1200Hz -> 1800Hz) setiap kali Anda selesai memancarkan suara via tombol PTT.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      value: provider.isRogerBeepEnabled,
                      activeThumbColor: AppTheme.primary,
                      onChanged: provider.isSfxEnabled ? (val) => provider.setRogerBeep(val) : null,
                    ),
                    const Divider(height: 1, color: AppTheme.border),
                    // Tombol Uji Coba Nada Langsung
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('UJI COBA NADA AUDIO TAKTIS:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                                icon: const Icon(Icons.radar_rounded, size: 14, color: AppTheme.accent),
                                label: const Text('Sonar Radar', style: TextStyle(fontSize: 11)),
                                onPressed: () => TacticalAudioService.instance.playNodeConnectedSonar(),
                              ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                                icon: const Icon(Icons.mark_chat_unread_rounded, size: 14, color: AppTheme.primary),
                                label: const Text('Pesan Masuk', style: TextStyle(fontSize: 11)),
                                onPressed: () => TacticalAudioService.instance.playIncomingMessageTone(),
                              ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                                icon: const Icon(Icons.sos_rounded, size: 14, color: AppTheme.sosRed),
                                label: const Text('Alarm SOS', style: TextStyle(fontSize: 11, color: AppTheme.sosRed)),
                                onPressed: () => TacticalAudioService.instance.playSosAlert(),
                              ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                                icon: const Icon(Icons.pin_drop_rounded, size: 14, color: AppTheme.warning),
                                label: const Text('Nada Peta', style: TextStyle(fontSize: 11)),
                                onPressed: () => TacticalAudioService.instance.playWaypointTone(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Hardware Bridge LoRa / Meshtastic (5 - 20 KM)
              const Text(
                'HARDWARE BRIDGE LoRa / MESHTASTIC (5 - 20 KM)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                provider.isLoraConnected ? Icons.cell_tower_rounded : Icons.signal_cellular_connected_no_internet_0_bar_rounded,
                                color: provider.isLoraConnected ? AppTheme.accent : AppTheme.textSecondary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Text('Status Modem RF:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: provider.isLoraConnected ? AppTheme.accent.withValues(alpha: 0.15) : AppTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              provider.isLoraConnected ? 'TERHUBUNG' : 'STANDALONE WI-FI',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                color: provider.isLoraConnected ? AppTheme.accent : AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        provider.loraHardwareInfo,
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.textSecondary),
                      ),
                      const Divider(height: 20, color: AppTheme.border),
                      const Text('MODE MODEM LORA:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<LoraBridgeMode>(
                        initialValue: provider.loraBridgeMode,
                        dropdownColor: AppTheme.surfaceVariant,
                        decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                        items: const [
                          DropdownMenuItem(value: LoraBridgeMode.disabled, child: Text('Nonaktif (P2P Wi-Fi / Hotspot Saja)')),
                          DropdownMenuItem(value: LoraBridgeMode.usbOtgSerial, child: Text('USB OTG Serial (CH340/CP2102 SX1262)')),
                          DropdownMenuItem(value: LoraBridgeMode.bluetoothBle, child: Text('Bluetooth BLE (Meshtastic T-Beam)')),
                          DropdownMenuItem(value: LoraBridgeMode.simulatedHardware, child: Text('Simulasi Hardware LoRa Heltec V3')),
                        ],
                        onChanged: (val) {
                          if (val != null) provider.setLoraBridgeMode(val);
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'RF: ${provider.loraConfig.frequencyMhz}MHz | SF${provider.loraConfig.spreadingFactor} | ${provider.loraConfig.bandwidthKhz}kHz | ${provider.loraConfig.txPowerDbm}dBm',
                            style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppTheme.primary),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                            icon: const Icon(Icons.tune_rounded, size: 14),
                            label: const Text('Ubah Parameter', style: TextStyle(fontSize: 11)),
                            onPressed: () => _showLoraConfigModal(context, provider),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Pengaturan Smart Relay (Bagian 7.4)
              const Text(
                'PENGATURAN SMART RELAY (MESH)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),

              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Aktifkan Smart Relay', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text(
                        'Izinkan perangkat ini meneruskan pesan tetangga yang belum mencapai tujuan.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      value: provider.isRelayEnabled,
                      activeThumbColor: AppTheme.accent,
                      onChanged: (val) => provider.setRelayEnabled(val),
                    ),
                    const Divider(height: 1, color: AppTheme.border),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Batas Lompatan (Hop Limit):', style: TextStyle(fontSize: 13)),
                              Text('${provider.maxHops} hop', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                            ],
                          ),
                          Slider(
                            value: provider.maxHops.toDouble(),
                            min: 1,
                            max: 6,
                            divisions: 5,
                            label: '${provider.maxHops} hop',
                            activeColor: AppTheme.primary,
                            onChanged: (val) => provider.setMaxHops(val.toInt()),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Masa Berlaku Pesan (TTL):', style: TextStyle(fontSize: 13)),
                              Text('${provider.ttlHours} jam', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                            ],
                          ),
                          Slider(
                            value: provider.ttlHours.toDouble(),
                            min: 6,
                            max: 72,
                            divisions: 11,
                            label: '${provider.ttlHours} jam',
                            activeColor: AppTheme.primary,
                            onChanged: (val) => provider.setTtlHours(val.toInt()),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Status GPS & Privasi
              const Text(
                'LOKASI & PRIVASI',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Status GPS Terakhir:', style: TextStyle(color: AppTheme.textSecondary)),
                          Text(
                            provider.lastLocation != null
                                ? provider.lastLocation!.formattedCoordinates
                                : 'Belum diambil',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: provider.isFetchingLocation
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.gps_fixed, size: 16),
                          label: const Text('Kunci Posisi GNSS Sekarang (Single Fetch)'),
                          onPressed: provider.isFetchingLocation ? null : () => provider.fetchCurrentGpsLocation(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Prinsip Privasi: Koordinat hanya dilampirkan jika Anda menekan ikon lokasi secara eksplisit saat mengirim pesan.',
                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Ekspor & Arsip Data Offline
              const Text(
                'EKSPOR & ARSIP DATA OFFLINE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.table_chart_outlined, color: AppTheme.accent),
                        title: const Text('Ekspor Log Uji Lapangan (.CSV)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Simpan benchmark RSSI, latensi, dan jarak', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                        trailing: const Icon(Icons.download_rounded, size: 20, color: AppTheme.primary),
                        onTap: () async {
                          final path = await provider.exportFieldTestLogsToCsv();
                          if (!mounted) return;
                          _showExportDone('Ekspor Log Uji (.CSV)', path);
                        },
                      ),
                      const Divider(height: 1, color: AppTheme.border),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.chat_outlined, color: AppTheme.primary),
                        title: const Text('Ekspor Riwayat Pesan (.CSV)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Simpan database percakapan & koordinat', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                        trailing: const Icon(Icons.download_rounded, size: 20, color: AppTheme.primary),
                        onTap: () async {
                          final path = await provider.exportMessagesToCsv();
                          if (!mounted) return;
                          _showExportDone('Ekspor Pesan (.CSV)', path);
                        },
                      ),
                      const Divider(height: 1, color: AppTheme.border),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.code_rounded, color: AppTheme.warning),
                        title: const Text('Full Backup Dump (.JSON)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Cadangkan seluruh database ke format JSON terstruktur', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                        trailing: const Icon(Icons.download_rounded, size: 20, color: AppTheme.primary),
                        onTap: () async {
                          final path = await provider.exportAllToJson();
                          if (!mounted) return;
                          _showExportDone('Full Dump (.JSON)', path);
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Pembersihan Database
              Card(
                color: AppTheme.sosRed.withValues(alpha: 0.05),
                child: ListTile(
                  leading: const Icon(Icons.delete_outline, color: AppTheme.sosRed),
                  title: const Text('Bersihkan Database SQLite', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('Hapus seluruh pesan tersimpan & log pengujian', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  onTap: () => _confirmClearData(context, provider),
                ),
              ),

              const SizedBox(height: 24),

              // Informasi Versi
              const Center(
                child: Text(
                  'SinyalNol v0.3 Taktis • Tactical SAR Offline Mesh\nE2EE X25519 • Peta Taktis & Waypoint • Dead Man\'s Switch • Kejujuran Status',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
