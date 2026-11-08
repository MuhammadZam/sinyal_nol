import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/torch_service.dart';

class SosStrobeScreen extends StatefulWidget {
  const SosStrobeScreen({super.key});

  @override
  State<SosStrobeScreen> createState() => _SosStrobeScreenState();
}

class _SosStrobeScreenState extends State<SosStrobeScreen> {
  bool _isLightOn = false;
  bool _isRunning = true;
  bool _enableSound = true;
  bool _enableTorch = true;
  String _currentMorseChar = 'S';
  Timer? _strobeTimer;

  // Pola Morse Standar SOS: S (...), O (---), S (...)
  // Durasi dalam milidetik (on/off)
  final List<_MorseStep> _sosPattern = [
    // S: dot, dot, dot
    _MorseStep(true, 180, 'S (•)'),
    _MorseStep(false, 150, 'S'),
    _MorseStep(true, 180, 'S (•)'),
    _MorseStep(false, 150, 'S'),
    _MorseStep(true, 180, 'S (•)'),
    _MorseStep(false, 450, 'S -> O'),
    // O: dash, dash, dash
    _MorseStep(true, 550, 'O (—)'),
    _MorseStep(false, 150, 'O'),
    _MorseStep(true, 550, 'O (—)'),
    _MorseStep(false, 150, 'O'),
    _MorseStep(true, 550, 'O (—)'),
    _MorseStep(false, 450, 'O -> S'),
    // S: dot, dot, dot
    _MorseStep(true, 180, 'S (•)'),
    _MorseStep(false, 150, 'S'),
    _MorseStep(true, 180, 'S (•)'),
    _MorseStep(false, 150, 'S'),
    _MorseStep(true, 180, 'S (•)'),
    _MorseStep(false, 1400, 'PAUSE'),
  ];

  int _stepIndex = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _executeNextMorseStep();
  }

  void _executeNextMorseStep() {
    if (!mounted || !_isRunning) return;

    final step = _sosPattern[_stepIndex];
    setState(() {
      _isLightOn = step.isOn;
      _currentMorseChar = step.label;
    });

    if (step.isOn) {
      HapticFeedback.heavyImpact();
      if (_enableSound) {
        SystemSound.play(SystemSoundType.alert);
      }
    }

    if (_enableTorch) {
      TorchService.setTorch(step.isOn);
    }

    _strobeTimer = Timer(Duration(milliseconds: step.durationMs), () {
      if (!mounted || !_isRunning) return;
      _stepIndex = (_stepIndex + 1) % _sosPattern.length;
      _executeNextMorseStep();
    });
  }

  @override
  void dispose() {
    _isRunning = false;
    _strobeTimer?.cancel();
    TorchService.setTorch(false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _isLightOn ? Colors.white : const Color(0xFF8B0000);
    final textColor = _isLightOn ? Colors.black : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: textColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'OPTICAL MORSE BEACON',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                        color: textColor,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          _enableTorch ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                          color: textColor,
                          size: 24,
                        ),
                        tooltip: _enableTorch ? 'Matikan Senter Kamera' : 'Aktifkan Senter Kamera',
                        onPressed: () {
                          setState(() {
                            _enableTorch = !_enableTorch;
                            if (!_enableTorch) {
                              TorchService.setTorch(false);
                            }
                          });
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          _enableSound ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                          color: textColor,
                          size: 24,
                        ),
                        tooltip: _enableSound ? 'Matikan Sirena Akustik' : 'Aktifkan Sirena Akustik',
                        onPressed: () {
                          setState(() {
                            _enableSound = !_enableSound;
                          });
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: textColor, size: 28),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),

              // Center Visual Readout
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isLightOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    size: 80,
                    color: textColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'SOS',
                    style: TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 8,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• • •   — — —   • • •',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: textColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'PULSA: $_currentMorseChar',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),

              // Bottom Instruction
              Column(
                children: [
                  Text(
                    'Arahkan layar ponsel ini ke atas / ke arah tim pencari atau helikopter.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: textColor.withValues(alpha: 0.8)),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: textColor,
                        foregroundColor: bgColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('HENTIKAN STROBO', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MorseStep {
  final bool isOn;
  final int durationMs;
  final String label;

  _MorseStep(this.isOn, this.durationMs, this.label);
}
