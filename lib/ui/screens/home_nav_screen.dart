import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../theme/app_theme.dart';
import 'chat_list_screen.dart';
import 'sos_screen.dart';
import 'radar_screen.dart';
import 'field_test_screen.dart';
import 'settings_screen.dart';

class HomeNavScreen extends StatefulWidget {
  const HomeNavScreen({super.key});

  @override
  State<HomeNavScreen> createState() => _HomeNavScreenState();
}

class _HomeNavScreenState extends State<HomeNavScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    ChatListScreen(),
    SosScreen(),
    RadarScreen(),
    FieldTestScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          body: Column(
            children: [
              // Global Dead Man's Switch Safety HUD Bar
              if (provider.isDeadManSwitchActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: provider.isDeadManWarning
                        ? AppTheme.sosRed
                        : const Color(0xFF161E2E),
                    border: Border(
                      bottom: BorderSide(
                        color: provider.isDeadManWarning ? Colors.white70 : AppTheme.border,
                        width: 1,
                      ),
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              provider.isDeadManWarning
                                  ? Icons.warning_amber_rounded
                                  : Icons.shield_rounded,
                              size: 16,
                              color: provider.isDeadManWarning ? Colors.white : AppTheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  provider.isDeadManWarning
                                      ? 'PERINGATAN CHECK-IN RESIDUAL'
                                      : 'DEAD MAN\'S SWITCH AKTIF',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.8,
                                    color: provider.isDeadManWarning ? Colors.white : AppTheme.textSecondary,
                                  ),
                                ),
                                Text(
                                  'Sisa Waktu: ${provider.deadManCountdownFormatted}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    color: provider.isDeadManWarning ? Colors.white : AppTheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: provider.isDeadManWarning ? Colors.white : AppTheme.accent,
                            foregroundColor: provider.isDeadManWarning ? AppTheme.sosRed : Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.check_circle_rounded, size: 14),
                          label: const Text(
                            'SAYA SELAMAT',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () {
                            provider.checkInDeadManSwitch();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Check-in keselamatan diterima. Timer disetel ulang.'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

              Expanded(
                child: IndexedStack(
                  index: _currentIndex,
                  children: _screens,
                ),
              ),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            items: [
              const BottomNavigationBarItem(
                icon: Icon(Icons.chat_bubble_outline),
                activeIcon: Icon(Icons.chat_bubble_rounded),
                label: 'Chat',
              ),
              BottomNavigationBarItem(
                icon: Badge(
                  isLabelVisible: provider.isDeadManWarning,
                  backgroundColor: AppTheme.sosRed,
                  smallSize: 8,
                  child: const Icon(Icons.emergency_outlined, color: AppTheme.sosRed),
                ),
                activeIcon: Badge(
                  isLabelVisible: provider.isDeadManWarning,
                  backgroundColor: AppTheme.sosRed,
                  smallSize: 8,
                  child: const Icon(Icons.emergency, color: AppTheme.sosRed),
                ),
                label: 'SOS',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.radar_outlined),
                activeIcon: Icon(Icons.radar_rounded),
                label: 'Radar',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.science_outlined),
                activeIcon: Icon(Icons.science_rounded),
                label: 'Uji Lapang',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.settings_outlined),
                activeIcon: Icon(Icons.settings_rounded),
                label: 'Pengaturan',
              ),
            ],
          ),
        );
      },
    );
  }
}
