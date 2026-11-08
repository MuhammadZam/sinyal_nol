import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../theme/app_theme.dart';

class SignalIndicatorBanner extends StatelessWidget {
  const SignalIndicatorBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        final isRadioOn = provider.isRadioActive;
        final peerCount = provider.peers.length;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isRadioOn ? const Color(0xFF0F2D1F) : const Color(0xFF281C1C),
            border: Border(
              bottom: BorderSide(
                color: isRadioOn ? AppTheme.accent.withValues(alpha: 0.3) : AppTheme.sosRed.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isRadioOn ? AppTheme.accent : AppTheme.sosRed,
                  boxShadow: [
                    BoxShadow(
                      color: isRadioOn ? AppTheme.accent.withValues(alpha: 0.6) : AppTheme.sosRed.withValues(alpha: 0.6),
                      blurRadius: 4,
                      spreadRadius: 1,
                    )
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          isRadioOn ? 'SINYAL NOL AKTIF (OFFLINE P2P)' : 'RADIO MATI (HANYA SIMPAN LOKAL)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: isRadioOn ? AppTheme.accent : AppTheme.sosRed,
                          ),
                        ),
                        if (isRadioOn) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: provider.isBatterySaverEnabled
                                  ? AppTheme.warning.withValues(alpha: 0.2)
                                  : AppTheme.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: provider.isBatterySaverEnabled
                                    ? AppTheme.warning.withValues(alpha: 0.5)
                                    : AppTheme.primary.withValues(alpha: 0.4),
                                width: 0.7,
                              ),
                            ),
                            child: Text(
                              provider.isBatterySaverEnabled ? 'ECO 15s' : 'ACT 4s',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                color: provider.isBatterySaverEnabled ? AppTheme.warning : AppTheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isRadioOn
                          ? '$peerCount node terdeteksi • ${provider.isRelayEnabled ? 'Smart Relay On' : 'Relay Off'} • Node: ${provider.localDeviceId}'
                          : 'Pesan akan disimpan di SQLite antrean lokal',
                      style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isRadioOn,
                activeThumbColor: AppTheme.accent,
                onChanged: (val) {
                  if (val) {
                    provider.startRadio();
                  } else {
                    provider.stopRadio();
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
