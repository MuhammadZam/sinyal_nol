import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../theme/app_theme.dart';
import 'sos_strobe_screen.dart';
import 'tactical_map_screen.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  final TextEditingController _noteController = TextEditingController();
  bool _includeGps = true;
  String _selectedPreset = 'Butuh Evakuasi Medis Segera';

  // SAR Casualty Triage Counters (START Protocol)
  int _triageRed = 0; // Immediate / Kritis
  int _triageYellow = 0; // Delayed / Mendesak
  int _triageGreen = 0; // Minor / Luka Ringan
  int _triageBlack = 0; // Deceased / Meninggal

  int _selectedDeadManInterval = 15;

  final List<String> _presets = [
    'Butuh Evakuasi Medis Segera',
    'Tersesat / Kehilangan Arah di Hutan/Gunung',
    'Bencana Alam / Gempa / Terjebak Reruntuhan',
    'Kehabisan Bahan Makanan & Air Bersih',
    'Kecelakaan Kendaraan / Butuh Bantuan Teknis',
  ];

  @override
  void initState() {
    super.initState();
    _noteController.text = _selectedPreset;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _syncTriageToNotes() {
    final hasTriage = _triageRed > 0 || _triageYellow > 0 || _triageGreen > 0 || _triageBlack > 0;
    String baseText = _noteController.text;

    // Bersihkan tag triage sebelumnya jika ada
    baseText = baseText.replaceAll(RegExp(r'\s*\[TRIAGE:.*?\]'), '').trim();

    if (hasTriage) {
      final parts = <String>[];
      if (_triageRed > 0) parts.add('$_triageRed Merah (Kritis)');
      if (_triageYellow > 0) parts.add('$_triageYellow Kuning (Mendesak)');
      if (_triageGreen > 0) parts.add('$_triageGreen Hijau (Ringan)');
      if (_triageBlack > 0) parts.add('$_triageBlack Hitam (Meninggal)');
      baseText = '$baseText [TRIAGE: ${parts.join(', ')}]';
    }

    _noteController.text = baseText;
  }

  void _triggerSos(BuildContext context, AppProvider provider) async {
    final note = _noteController.text.trim();

    await provider.sendSosBroadcast(
      emergencyNote: note,
      attachLocation: _includeGps,
    );

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: AppTheme.sosRed),
              SizedBox(width: 8),
              Text('SOS Telah Dipancarkan'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pesan darurat telah disimpan di database lokal dan dipancarkan ke seluruh node sekitar.',
                style: TextStyle(color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Catatan: $note\nLokasi GPS: ${_includeGps ? 'Terlampir' : 'Tidak disertakan'}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Ingat: Jika tidak ada perangkat dalam jangkauan radio (Bluetooth/Wi-Fi), pesan tetap tersimpan dan akan diteruskan otomatis saat perangkat lain terdeteksi.',
                style: TextStyle(fontSize: 11, color: AppTheme.warning),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup', style: TextStyle(color: AppTheme.primary)),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Mode Darurat SOS & SAR'),
            actions: [
              IconButton(
                icon: const Icon(Icons.explore_rounded),
                tooltip: 'Peta Taktis & Waypoint SAR',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TacticalMapScreen()),
                  );
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Peringatan Batasan Penting
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.sosRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.sosRed.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppTheme.sosRed, size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PEMBERITAHUAN PENTING SOS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.sosRed,
                              letterSpacing: 0.5,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Tombol SOS ini memancarkan sinyal ke radio lokal ponsel di sekitar tanpa internet. Tombol ini TIDAK MENJAMIN bantuan instan tiba jika tidak ada node penerima dalam jangkauan fisik.',
                            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // DEAD MAN'S SWITCH SECTION (Safeguard Responder SAR)
              _buildDeadManSwitchCard(context, provider),

              const SizedBox(height: 20),

              // Tombol SOS Besar dengan Efek Visual
              Center(
                child: GestureDetector(
                  onTap: () => _triggerSos(context, provider),
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [
                          Color(0xFFFF5252),
                          Color(0xFFD50000),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.sosRed.withValues(alpha: 0.5),
                          blurRadius: 24,
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.emergency_share_rounded, size: 44, color: Colors.white),
                          SizedBox(height: 6),
                          Text(
                            'KIRIM SOS',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Tombol Tindakan Cepat (Strobo Morse & Peta Taktis)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.sosRed,
                        side: const BorderSide(color: AppTheme.sosRed),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.flash_on_rounded, size: 18),
                      label: const Text('Strobo & Sirena', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SosStrobeScreen()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.explore_rounded, size: 18),
                      label: const Text('Peta Taktis SAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const TacticalMapScreen()),
                        );
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // FITUR ASSISTANT TRIAGE KORBAN (START Protocol)
              _buildTriageSection(context),

              const SizedBox(height: 16),

              // Pilihan Template Darurat
              const Text(
                'PILIH KATEGORI DARURAT:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _presets.map((preset) {
                  final isSelected = _selectedPreset == preset;
                  return ChoiceChip(
                    label: Text(preset, style: TextStyle(fontSize: 12, color: isSelected ? Colors.black : AppTheme.textPrimary)),
                    selected: isSelected,
                    selectedColor: AppTheme.primary,
                    backgroundColor: AppTheme.surfaceVariant,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedPreset = preset;
                          _noteController.text = preset;
                          _syncTriageToNotes();
                        });
                      }
                    },
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // Input Catatan Kustom
              TextField(
                controller: _noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Keterangan Tambahan / Kondisi Korban',
                ),
              ),

              const SizedBox(height: 16),

              // Opsi GPS Lokasi
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: SwitchListTile(
                  title: const Text('Sertakan Koordinat GPS GNSS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(
                    provider.lastLocation != null
                        ? 'Terkunci: ${provider.lastLocation!.formattedCoordinates}'
                        : 'Lokasi akan diambil dari sensor GNSS satelit saat tombol ditekan.',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  value: _includeGps,
                  activeThumbColor: AppTheme.sosRed,
                  onChanged: (val) {
                    setState(() {
                      _includeGps = val;
                    });
                    if (val && provider.lastLocation == null) {
                      provider.fetchCurrentGpsLocation();
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDeadManSwitchCard(BuildContext context, AppProvider provider) {
    if (provider.isDeadManSwitchActive) {
      final isWarning = provider.isDeadManWarning;
      final borderColor = isWarning ? AppTheme.sosRed : AppTheme.warning;

      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF161F2B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: isWarning ? 2.0 : 1.2),
          boxShadow: isWarning
              ? [
                  BoxShadow(
                    color: AppTheme.sosRed.withValues(alpha: 0.4),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      isWarning ? Icons.alarm_on_rounded : Icons.timer_outlined,
                      color: borderColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'DEAD MAN\'S SWITCH AKTIF',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.8,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: borderColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    provider.deadManCountdownFormatted,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: borderColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isWarning
                  ? 'PERINGATAN: Sisa waktu di bawah 60 detik! Segera check-in untuk mencegah transmisi SOS darurat otomatis.'
                  : 'Aplikasi memantau respons Anda. Jika timer habis tanpa check-in, SOS dan koordinat GPS Anda akan otomatis dipancarkan.',
              style: TextStyle(fontSize: 11, color: isWarning ? AppTheme.sosRed : AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.verified_user_rounded, size: 20),
                    label: const Text(
                      'SAYA SELAMAT',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8),
                    ),
                    onPressed: () {
                      HapticFeedback.heavyImpact();
                      provider.checkInDeadManSwitch();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Konfirmasi "Saya Selamat" berhasil. Timer keselamatan direset.'),
                          duration: Duration(seconds: 2),
                          backgroundColor: AppTheme.surfaceVariant,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      side: const BorderSide(color: AppTheme.border),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => provider.stopDeadManSwitch(),
                    child: const Text('Hentikan', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(12),
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
                Icon(Icons.shield_outlined, color: AppTheme.primary, size: 18),
                SizedBox(width: 8),
                Text(
                  'Dead Man\'s Switch (Timer Keselamatan)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Aplikasi akan bergetar meminta konfirmasi "Saya Selamat". Jika tidak direspons sebelum batas toleransi habis, SOS darurat & koordinat GNSS akan otomatis dipancarkan ke seluruh jaringan radio sekitar.',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.3),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _buildIntervalChip(15, '15m'),
                    _buildIntervalChip(30, '30m'),
                    _buildIntervalChip(60, '1 Jam'),
                    _buildIntervalChip(120, '2 Jam'),
                  ],
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  onPressed: () {
                    provider.startDeadManSwitch(_selectedDeadManInterval);
                  },
                  child: const Text('Aktifkan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      );
    }
  }

  Widget _buildIntervalChip(int intervalMinutes, String label) {
    final isSel = _selectedDeadManInterval == intervalMinutes;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 11, color: isSel ? Colors.black : Colors.white)),
        selected: isSel,
        selectedColor: AppTheme.primary,
        backgroundColor: AppTheme.surface,
        onSelected: (val) {
          if (val) setState(() => _selectedDeadManInterval = intervalMinutes);
        },
      ),
    );
  }

  Widget _buildTriageSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.health_and_safety_outlined, color: AppTheme.sosRed, size: 18),
                  SizedBox(width: 8),
                  Text('Asisten Triage Korban (START)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              if (_triageRed > 0 || _triageYellow > 0 || _triageGreen > 0 || _triageBlack > 0)
                InkWell(
                  onTap: () {
                    setState(() {
                      _triageRed = 0;
                      _triageYellow = 0;
                      _triageGreen = 0;
                      _triageBlack = 0;
                      _syncTriageToNotes();
                    });
                  },
                  child: const Text('Reset', style: TextStyle(color: AppTheme.primary, fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Klasifikasikan jumlah korban berdasarkan prioritas medis untuk laporan evakuasi.',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildTriageCounter(
                  label: 'Merah (Kritis)',
                  count: _triageRed,
                  color: const Color(0xFFFF1744),
                  onChanged: (c) {
                    setState(() {
                      _triageRed = c;
                      _syncTriageToNotes();
                    });
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildTriageCounter(
                  label: 'Kuning (Mendesak)',
                  count: _triageYellow,
                  color: const Color(0xFFFFD600),
                  onChanged: (c) {
                    setState(() {
                      _triageYellow = c;
                      _syncTriageToNotes();
                    });
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildTriageCounter(
                  label: 'Hijau (Ringan)',
                  count: _triageGreen,
                  color: const Color(0xFF00E676),
                  onChanged: (c) {
                    setState(() {
                      _triageGreen = c;
                      _syncTriageToNotes();
                    });
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildTriageCounter(
                  label: 'Hitam (Meninggal)',
                  count: _triageBlack,
                  color: const Color(0xFF9E9E9E),
                  onChanged: (c) {
                    setState(() {
                      _triageBlack = c;
                      _syncTriageToNotes();
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTriageCounter({
    required String label,
    required int count,
    required Color color,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF121820),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.0),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            '$count',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              InkWell(
                onTap: () {
                  if (count > 0) onChanged(count - 1);
                },
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: AppTheme.surfaceVariant, borderRadius: BorderRadius.circular(4)),
                  child: const Icon(Icons.remove, size: 12, color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => onChanged(count + 1),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: AppTheme.surfaceVariant, borderRadius: BorderRadius.circular(4)),
                  child: const Icon(Icons.add, size: 12, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
