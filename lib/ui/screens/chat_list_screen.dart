import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/signal_indicator.dart';
import 'chat_conversation_screen.dart';
import 'tactical_qr_scanner_screen.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        // Cari pesan broadcast terakhir
        final broadcastMsgs = provider.messages.where((m) => m.isBroadcast).toList();
        final lastBroadcast = broadcastMsgs.isNotEmpty ? broadcastMsgs.last : null;

        // Kumpulkan daftar peer unik dari pesan yang tersimpan & peer yang sedang terdeteksi
        final Map<String, String> peerNames = {};
        for (final p in provider.peers) {
          peerNames[p.deviceId] = p.deviceName;
        }
        for (final m in provider.messages) {
          if (!m.isBroadcast) {
            final otherId = m.senderId == provider.localDeviceId ? m.recipientId : m.senderId;
            if (otherId != null && !peerNames.containsKey(otherId)) {
              peerNames[otherId] = m.senderId == provider.localDeviceId ? otherId : m.senderName;
            }
          }
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('SinyalNol • Percakapan'),
            actions: [
              IconButton(
                icon: const Icon(Icons.qr_code_scanner_rounded, color: AppTheme.accent),
                tooltip: 'Pindai QR Identitas Rekan SAR',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TacticalQrScannerScreen()),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Muat ulang',
                onPressed: () => provider.loadMessages(),
              ),
            ],
          ),
          body: Column(
            children: [
              const SignalIndicatorBanner(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  children: [
                    // Saluran Broadcast Publik
                    Card(
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.podcasts_rounded, color: AppTheme.primary, size: 24),
                        ),
                        title: const Text(
                          'Saluran Publik (Broadcast)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        subtitle: Text(
                          lastBroadcast != null
                              ? '${lastBroadcast.senderName}: ${lastBroadcast.body}'
                              : 'Kirim pesan ke seluruh perangkat sekitar...',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${broadcastMsgs.length}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ChatConversationScreen(
                                peerId: 'BROADCAST',
                                peerName: 'Saluran Publik (Semua Perangkat)',
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        Text(
                          'PERANGKAT TERHUBUNG / KONTAK LOKAL',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (peerNames.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.radar_rounded, size: 40, color: AppTheme.textSecondary),
                            const SizedBox(height: 12),
                            const Text(
                              'Belum ada perangkat terhubung secara langsung.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Hubungkan kedua ponsel ke Wi-Fi Hotspot portabel yang sama atau buka tab "Radar" untuk mendeteksi perangkat sekitar.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      )
                    else
                      ...peerNames.entries.map((entry) {
                        final peerId = entry.key;
                        final peerName = entry.value;
                        final isOnline = provider.peers.any((p) => p.deviceId == peerId);

                        // Cari pesan terakhir dengan peer ini
                        final directMsgs = provider.messages.where((m) {
                          return (m.recipientId == peerId && m.senderId == provider.localDeviceId) ||
                              (m.senderId == peerId && m.recipientId == provider.localDeviceId);
                        }).toList();
                        final lastDirect = directMsgs.isNotEmpty ? directMsgs.last : null;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Stack(
                              children: [
                                CircleAvatar(
                                  backgroundColor: AppTheme.surfaceVariant,
                                  child: const Icon(Icons.phone_android_rounded, color: AppTheme.primary),
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isOnline ? AppTheme.accent : AppTheme.textMuted,
                                      border: Border.all(color: AppTheme.surface, width: 2),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            title: Text(
                              peerName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                            ),
                            subtitle: Text(
                              lastDirect != null ? lastDirect.body : (isOnline ? 'Online di sekitar' : 'Pernah terhubung'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                            ),
                            trailing: isOnline
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.accent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'TERHUBUNG',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.accent,
                                      ),
                                    ),
                                  )
                                : null,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatConversationScreen(
                                    peerId: peerId,
                                    peerName: peerName,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.black,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Broadcast'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ChatConversationScreen(
                    peerId: 'BROADCAST',
                    peerName: 'Saluran Publik (Semua Perangkat)',
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
