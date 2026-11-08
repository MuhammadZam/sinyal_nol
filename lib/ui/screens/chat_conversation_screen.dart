import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/message_model.dart';
import '../../providers/app_provider.dart';
import '../../services/location_service.dart';
import '../../services/voice_service.dart';
import '../theme/app_theme.dart';
import '../widgets/message_bubble.dart';
import 'tactical_qr_scanner_screen.dart';

class ChatConversationScreen extends StatefulWidget {
  final String? peerId;
  final String peerName;

  const ChatConversationScreen({
    super.key,
    this.peerId,
    required this.peerName,
  });

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _attachLocation = false;
  final LocationService _locationService = LocationService();

  // Walkie-Talkie Asinkron PTT State
  bool _isRecordingPtt = false;
  int _pttDurationSec = 0;
  Timer? _pttTimer;

  @override
  void dispose() {
    _pttTimer?.cancel();
    VoiceService.instance.cancelRecording();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _startPttRecording() async {
    HapticFeedback.heavyImpact();
    final started = await VoiceService.instance.startRecording();
    if (!started) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Izin mikrofon diperlukan untuk merekam suara PTT.')),
        );
      }
      return;
    }

    setState(() {
      _isRecordingPtt = true;
      _pttDurationSec = 0;
    });

    _pttTimer?.cancel();
    _pttTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_isRecordingPtt) {
        timer.cancel();
        return;
      }
      setState(() {
        _pttDurationSec++;
      });
      if (_pttDurationSec >= 10) {
        // Otomatis stop pada 10 detik batas maksimal paket suara radio mesh
        timer.cancel();
        final p = Provider.of<AppProvider>(context, listen: false);
        _stopAndSendPtt(p);
      }
    });
  }

  Future<void> _stopAndSendPtt(AppProvider provider) async {
    _pttTimer?.cancel();
    if (!_isRecordingPtt) return;

    HapticFeedback.mediumImpact();
    final result = await VoiceService.instance.stopRecording();
    setState(() {
      _isRecordingPtt = false;
    });

    if (result != null && result.durationSeconds >= 1) {
      await provider.sendVoiceNote(
        voicePayloadJson: result.toPayloadJson(),
        recipientId: widget.peerId,
      );
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    }
  }

  Future<void> _cancelPttRecording() async {
    _pttTimer?.cancel();
    await VoiceService.instance.cancelRecording();
    setState(() {
      _isRecordingPtt = false;
      _pttDurationSec = 0;
    });
  }

  Future<void> _handleSend(AppProvider provider) async {
    final text = _textController.text.trim();
    if (text.isEmpty && !_attachLocation) return;

    final body = text.isEmpty ? 'Membagikan koordinat lokasi offline.' : text;
    final bool attach = _attachLocation;

    _textController.clear();
    setState(() {
      _attachLocation = false;
    });

    await provider.sendMessage(
      body: body,
      recipientId: widget.peerId,
      attachLocation: attach,
    );

    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  void _showCoordinateCompassModal(BuildContext context, MessageModel msg, AppProvider provider) {
    if (msg.latitude == null || msg.longitude == null) return;

    double? distanceMeters;
    double? bearingDegrees;
    String directionName = '-';

    final myLoc = provider.lastLocation;
    if (myLoc != null) {
      distanceMeters = _locationService.calculateDistance(
        myLoc.latitude,
        myLoc.longitude,
        msg.latitude!,
        msg.longitude!,
      );
      bearingDegrees = _locationService.calculateBearing(
        myLoc.latitude,
        myLoc.longitude,
        msg.latitude!,
        msg.longitude!,
      );
      directionName = _locationService.getCardinalDirection(bearingDegrees);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
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
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              const Row(
                children: [
                  Icon(Icons.explore, color: AppTheme.primary, size: 24),
                  SizedBox(width: 10),
                  Text(
                    'Navigasi Koordinat Offline',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Koordinat Pengirim:', style: TextStyle(color: AppTheme.textSecondary)),
                        Text(
                          '${msg.latitude!.toStringAsFixed(6)}, ${msg.longitude!.toStringAsFixed(6)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                    if (msg.altitude != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Ketinggian (Altitude):', style: TextStyle(color: AppTheme.textSecondary)),
                          Text('${msg.altitude!.toStringAsFixed(1)} m dpl', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (myLoc != null && distanceMeters != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF132B25),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          children: [
                            const Text('Perkiraan Jarak', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                            const SizedBox(height: 4),
                            Text(
                              distanceMeters > 1000
                                  ? '${(distanceMeters / 1000).toStringAsFixed(2)} km'
                                  : '${distanceMeters.toStringAsFixed(0)} m',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.accent),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF13233A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          children: [
                            const Text('Arah Mata Angin', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                            const SizedBox(height: 4),
                            Text(
                              '$directionName (${bearingDegrees!.toStringAsFixed(0)}°)',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: AppTheme.warning, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Nyalakan GPS ponsel Anda untuk menghitung jarak & arah relatif tanpa koneksi internet.',
                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Catatan: Kompas & jarak dihitung murni secara matematis dari sensor GPS lokal tanpa server online.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        // Filter pesan untuk percakapan ini
        final filteredMessages = provider.messages.where((m) {
          if (widget.peerId == null || widget.peerId == 'BROADCAST') {
            return m.isBroadcast || m.messageType == MessageType.sos;
          } else {
            return (m.recipientId == widget.peerId && m.senderId == provider.localDeviceId) ||
                (m.senderId == widget.peerId && m.recipientId == provider.localDeviceId);
          }
        }).toList();

        final isDirectChat = widget.peerId != null && widget.peerId != 'BROADCAST';
        final isE2eeActive = isDirectChat && provider.hasPeerE2eeKey(widget.peerId);
        final isVerified = isDirectChat && provider.isPeerVerified(widget.peerId);

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(widget.peerName),
                    if (isVerified) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.verified_rounded, size: 16, color: AppTheme.accent),
                    ],
                  ],
                ),
                Row(
                  children: [
                    if (isDirectChat) ...[
                      Icon(
                        isE2eeActive ? Icons.lock_rounded : Icons.lock_open_rounded,
                        size: 11,
                        color: isE2eeActive ? AppTheme.accent : AppTheme.warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isE2eeActive ? 'E2EE X25519 Terenkripsi' : 'Menunggu Kunci E2EE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isE2eeActive ? AppTheme.accent : AppTheme.warning,
                        ),
                      ),
                      if (isVerified) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('VERIFIED', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: AppTheme.accent)),
                        ),
                      ],
                      const SizedBox(width: 6),
                      Text('• ID: ${widget.peerId}', style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                    ] else ...[
                      const Text(
                        'Saluran Terbuka • Siaran RF Tanpa Enkripsi',
                        style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            actions: [
              if (isDirectChat)
                IconButton(
                  icon: Icon(
                    isVerified ? Icons.verified_user_rounded : Icons.qr_code_scanner_rounded,
                    color: isVerified ? AppTheme.accent : AppTheme.primary,
                    size: 20,
                  ),
                  tooltip: isVerified ? 'Node Terverifikasi Fisik' : 'Pindai QR Verifikasi Node Ini',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TacticalQrScannerScreen()),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Muat ulang pesan lokal',
                onPressed: () => provider.loadMessages(),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: filteredMessages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline, size: 48, color: AppTheme.textMuted),
                            const SizedBox(height: 12),
                            const Text(
                              'Belum ada pesan tersimpan.',
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Pesan akan tetap tersimpan di SQLite lokal ponsel.',
                              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: filteredMessages.length,
                        itemBuilder: (context, index) {
                          final msg = filteredMessages[index];
                          final isMe = msg.senderId == provider.localDeviceId;
                          return MessageBubble(
                            message: msg,
                            isMe: isMe,
                            onLocationTap: () => _showCoordinateCompassModal(context, msg, provider),
                          );
                        },
                      ),
              ),

              // Indikator lampiran GPS aktif
              if (_attachLocation)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  child: Row(
                    children: [
                      const Icon(Icons.my_location, size: 16, color: AppTheme.accent),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Koordinat GPS GNSS akan dilampirkan bersama pesan ini.',
                          style: TextStyle(fontSize: 12, color: AppTheme.accent),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: AppTheme.textSecondary),
                        onPressed: () => setState(() => _attachLocation = false),
                      ),
                    ],
                  ),
                ),

              // Baris Input Pesan / PTT Walkie-Talkie
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppTheme.surface,
                  border: Border(top: BorderSide(color: AppTheme.border)),
                ),
                child: SafeArea(
                  child: _isRecordingPtt
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.sosRed.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.sosRed, width: 1.2),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.fiber_manual_record, color: AppTheme.sosRed, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'MEREKAM PTT: 00:0${_pttDurationSec}s / MAX 10s',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.sosRed,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                                tooltip: 'Batalkan PTT',
                                onPressed: _cancelPttRecording,
                              ),
                              const SizedBox(width: 4),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                icon: const Icon(Icons.send_rounded, size: 16),
                                label: const Text('Pancarkan PTT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                onPressed: () => _stopAndSendPtt(provider),
                              ),
                            ],
                          ),
                        )
                      : Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                _attachLocation ? Icons.location_on : Icons.location_on_outlined,
                                color: _attachLocation ? AppTheme.accent : AppTheme.textSecondary,
                              ),
                              tooltip: 'Lampirkan koordinat GPS satu kali',
                              onPressed: () async {
                                if (!_attachLocation) {
                                  final loc = await provider.fetchCurrentGpsLocation();
                                  if (loc == null && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Izin lokasi ditolak atau sinyal GPS belum terkunci.'),
                                      ),
                                    );
                                  } else {
                                    setState(() => _attachLocation = true);
                                  }
                                } else {
                                  setState(() => _attachLocation = false);
                                }
                              },
                            ),
                            Expanded(
                              child: TextField(
                                controller: _textController,
                                textCapitalization: TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  hintText: isE2eeActive
                                      ? 'Pesan terenkripsi E2EE...'
                                      : (isDirectChat ? 'Ketik pesan langsung...' : 'Ketik siaran publik...'),
                                  prefixIcon: isE2eeActive
                                      ? const Icon(Icons.lock_rounded, size: 16, color: AppTheme.accent)
                                      : null,
                                  isDense: true,
                                ),
                                onSubmitted: (_) => _handleSend(provider),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Tombol Walkie-Talkie Push-To-Talk (PTT)
                            GestureDetector(
                              onLongPressStart: (_) => _startPttRecording(),
                              onLongPressEnd: (_) => _stopAndSendPtt(provider),
                              child: IconButton(
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFF1B2838),
                                  foregroundColor: AppTheme.accent,
                                ),
                                icon: const Icon(Icons.mic_rounded, size: 20),
                                tooltip: 'Tekan & tahan untuk Walkie-Talkie PTT',
                                onPressed: () => _startPttRecording(),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              style: IconButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.black,
                              ),
                              icon: const Icon(Icons.send_rounded, size: 20),
                              onPressed: () => _handleSend(provider),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
