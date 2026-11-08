import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/message_model.dart';
import '../../services/voice_service.dart';
import '../theme/app_theme.dart';

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final VoidCallback? onLocationTap;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.onLocationTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSos = message.messageType == MessageType.sos;
    final timeStr = DateFormat('HH:mm').format(message.createdAt);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: isSos
              ? AppTheme.sosRed.withValues(alpha: 0.15)
              : (isMe ? const Color(0xFF1E3A5F) : AppTheme.surfaceVariant),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isMe ? 14 : 2),
            bottomRight: Radius.circular(isMe ? 2 : 14),
          ),
          border: Border.all(
            color: isSos
                ? AppTheme.sosRed
                : (isMe ? const Color(0xFF2A5288) : AppTheme.border),
            width: isSos ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Nama Pengirim & Tag SOS / Broadcast
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSos) ...[
                  const Icon(Icons.warning_amber_rounded, color: AppTheme.sosRed, size: 16),
                  const SizedBox(width: 4),
                  const Text(
                    'SOS DARURAT',
                    style: TextStyle(
                      color: AppTheme.sosRed,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  isMe ? 'Anda' : message.senderName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isMe ? AppTheme.primary : AppTheme.accent,
                  ),
                ),
                if (message.isBroadcast) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'PUBLIK',
                      style: TextStyle(fontSize: 9, color: AppTheme.textSecondary),
                    ),
                  ),
                ] else if (message.isEncrypted) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4), width: 0.6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_rounded, size: 9, color: AppTheme.accent),
                        SizedBox(width: 2),
                        Text(
                          'E2EE',
                          style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: AppTheme.accent),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),

            // Isi Pesan Teks atau Voice Note Player
            if (message.isVoice)
              _buildVoicePlayer(context)
            else
              Text(
                message.body,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14.5,
                  height: 1.35,
                ),
              ),

            // Informasi Lokasi GPS jika dilampirkan
            if (message.hasLocation) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: onLocationTap,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_rounded, color: AppTheme.accent, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Koordinat GPS GNSS Terlampir:',
                              style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                            ),
                            Text(
                              '${message.latitude!.toStringAsFixed(5)}, ${message.longitude!.toStringAsFixed(5)}'
                              '${message.altitude != null ? ' (Alt: ${message.altitude!.toStringAsFixed(0)}m)' : ''}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accent,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.explore_outlined, color: AppTheme.textSecondary, size: 16),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 6),

            // Footer: Waktu, Checksum, & Status Pengiriman Jujur
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (message.integrityHash != null && message.integrityHash!.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '#${message.integrityHash!.substring(0, 6)}',
                      style: const TextStyle(fontSize: 8.5, fontFamily: 'monospace', color: AppTheme.textMuted),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (message.hopCount > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Hop: ${message.hopCount}',
                      style: const TextStyle(fontSize: 9, color: AppTheme.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  timeStr,
                  style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                ),
                if (isMe) ...[
                  const SizedBox(width: 5),
                  _buildDeliveryStatusIcon(message.deliveryStatus, message.deliveredAt),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryStatusIcon(DeliveryStatus status, DateTime? deliveredAt) {
    switch (status) {
      case DeliveryStatus.queued:
        return const Tooltip(
          message: 'Tersimpan offline di SQLite lokal (Menunggu radio)',
          child: Icon(Icons.schedule, size: 13, color: AppTheme.textSecondary),
        );
      case DeliveryStatus.sending:
        return const Tooltip(
          message: 'Sedang dalam proses transmisi...',
          child: SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.primary),
          ),
        );
      case DeliveryStatus.relayed:
        return const Tooltip(
          message: 'Terkirim ke perangkat perantara / relay tetangga',
          child: Icon(Icons.alt_route_rounded, size: 13, color: AppTheme.warning),
        );
      case DeliveryStatus.delivered:
        final ackTime = deliveredAt != null ? DateFormat('HH:mm:ss').format(deliveredAt) : '';
        return Tooltip(
          message: 'Diterima oleh tujuan akhir (ACK Terverifikasi ${ackTime.isNotEmpty ? 'pukul $ackTime' : ''})',
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.done_all_rounded, size: 14, color: AppTheme.accent),
            ],
          ),
        );
      case DeliveryStatus.failed:
        return const Tooltip(
          message: 'Kadaluwarsa / Batas TTL habis',
          child: Icon(Icons.error_outline, size: 13, color: AppTheme.sosRed),
        );
    }
  }

  Widget _buildVoicePlayer(BuildContext context) {
    final durationSec = message.voiceDurationSeconds;
    final base64 = message.voiceBase64Data;
    final sizeKb = (base64.length * 3 / 4 / 1024).toStringAsFixed(1);

    return ValueListenableBuilder<String?>(
      valueListenable: VoiceService.instance.playingMessageIdNotifier,
      builder: (context, playingId, child) {
        final isPlaying = playingId == message.messageId;

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isPlaying ? AppTheme.accent : Colors.white12,
              width: isPlaying ? 1.2 : 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  isPlaying ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded,
                  color: isPlaying ? AppTheme.accent : AppTheme.primary,
                  size: 32,
                ),
                onPressed: () {
                  VoiceService.instance.playVoiceMessage(message.messageId, base64);
                },
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        isPlaying ? 'MEMUTAR SUARA...' : 'PTT VOICE NOTE',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isPlaying ? AppTheme.accent : AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${durationSec}s • $sizeKb KB',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Waveform visual bars
                  Row(
                    children: List.generate(14, (index) {
                      final heights = [6, 12, 18, 10, 14, 20, 8, 16, 12, 18, 14, 8, 12, 6];
                      final h = heights[index % heights.length].toDouble();
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        width: 3,
                        height: isPlaying ? (h * 1.1) : h,
                        decoration: BoxDecoration(
                          color: isPlaying ? AppTheme.accent : Colors.white38,
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
