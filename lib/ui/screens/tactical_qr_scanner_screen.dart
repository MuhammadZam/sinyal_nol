import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../theme/app_theme.dart';

class TacticalQrScannerScreen extends StatefulWidget {
  const TacticalQrScannerScreen({super.key});

  @override
  State<TacticalQrScannerScreen> createState() => _TacticalQrScannerScreenState();
}

class _TacticalQrScannerScreenState extends State<TacticalQrScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _isProcessing = false;
  bool _isTorchOn = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _handleDetectedRaw(String raw) {
    if (_isProcessing || !mounted) return;
    _isProcessing = true;

    HapticFeedback.heavyImpact();
    final provider = Provider.of<AppProvider>(context, listen: false);
    final success = provider.verifyPeerFromQr(raw);

    if (success) {
      final parts = raw.split('|');
      final peerId = parts.length > 1 ? parts[1] : '';
      final peerName = parts.length > 2 ? parts[2] : 'Node';
      final fingerprint = parts.length > 3 ? parts[3] : '';

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Row(
            children: [
              Icon(Icons.verified_rounded, color: AppTheme.accent, size: 24),
              SizedBox(width: 8),
              Text('IDENTITAS TERVERIFIKASI', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.accent)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Kunci publik X25519 dan sidik jari kriptografis rekan SAR ini telah berhasil divalidasi dan disimpan ke database lokal.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nama: $peerName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text('Node ID: $peerId', style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.primary)),
                    const SizedBox(height: 4),
                    Text('Fingerprint:\n$fingerprint', style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppTheme.accent)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Status: Terpercaya (Encrypted E2EE & Verified)',
                style: TextStyle(fontSize: 11, color: AppTheme.accent, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx); // Tutup dialog
                Navigator.pop(context); // Kembali ke layar sebelumnya
              },
              child: const Text('Selesai'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.sosRed,
          content: Text('Format QR tidak valid. Pastikan memindai Kartu Identitas Taktis SinyalNol.'),
          duration: Duration(seconds: 2),
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _isProcessing = false);
      });
    }
  }

  void _showManualInputDialog() {
    final textCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Input Manual / Tempel Teks', style: TextStyle(fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gunakan jika kamera mengalami gangguan atau lensa kotor di lapangan.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textCtrl,
              maxLines: 3,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                labelText: 'Payload Kartu Identitas',
                hintText: 'SINYALNOL|NODE-XXXX|...|...',
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.paste_rounded, size: 14),
              label: const Text('Tempel dari Clipboard', style: TextStyle(fontSize: 11)),
              onPressed: () async {
                final data = await Clipboard.getData('text/plain');
                if (data?.text != null) {
                  textCtrl.text = data!.text!.trim();
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              final raw = textCtrl.text.trim();
              Navigator.pop(ctx);
              _handleDetectedRaw(raw);
            },
            child: const Text('Verifikasi'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Pindai QR Identitas SAR', style: TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: Icon(
              _isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              color: _isTorchOn ? AppTheme.accent : Colors.white70,
            ),
            tooltip: 'Senter Kamera',
            onPressed: () async {
              await _scannerController.toggleTorch();
              setState(() => _isTorchOn = !_isTorchOn);
            },
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white70),
            tooltip: 'Ganti Kamera',
            onPressed: () => _scannerController.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Live Camera Stream
          MobileScanner(
            controller: _scannerController,
            onDetect: (capture) {
              if (_isProcessing) return;
              for (final barcode in capture.barcodes) {
                final raw = barcode.rawValue;
                if (raw != null && raw.isNotEmpty) {
                  _handleDetectedRaw(raw);
                  break;
                }
              }
            },
          ),

          // 2. Tactical Reticle & Overlay Canvas
          CustomPaint(
            size: Size.infinite,
            painter: _TacticalScannerOverlayPainter(),
          ),

          // 3. Top Tactical Monospace Instructions
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xCC0D1117),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border, width: 0.8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.qr_code_scanner_rounded, color: AppTheme.accent, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Arahkan kamera ke Kartu Identitas Taktis rekan SAR untuk mengunci verifikasi kriptografis.',
                      style: TextStyle(fontSize: 11, color: AppTheme.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 4. Bottom Fallback Button
          Positioned(
            bottom: 30,
            left: 24,
            right: 24,
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xCC0D1117),
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppTheme.border),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.edit_note_rounded, size: 18, color: AppTheme.primary),
                label: const Text('Input / Tempel Teks Manual', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: _showManualInputDialog,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TacticalScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const scanBoxSize = 250.0;
    final left = (size.width - scanBoxSize) / 2;
    final top = (size.height - scanBoxSize) / 2 - 20;
    final scanRect = Rect.fromLTWH(left, top, scanBoxSize, scanBoxSize);

    // Dark semi-transparent background outside target
    final bgPaint = Paint()..color = Colors.black.withValues(alpha: 0.6);
    final bgPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(12)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(bgPath, bgPaint);

    // Reticle Corners (Cyan / Tactical Green)
    final cornerPaint = Paint()
      ..color = AppTheme.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    const cornerLen = 28.0;

    // Top-Left
    canvas.drawLine(Offset(left, top), Offset(left + cornerLen, top), cornerPaint);
    canvas.drawLine(Offset(left, top), Offset(left, top + cornerLen), cornerPaint);

    // Top-Right
    canvas.drawLine(Offset(left + scanBoxSize, top), Offset(left + scanBoxSize - cornerLen, top), cornerPaint);
    canvas.drawLine(Offset(left + scanBoxSize, top), Offset(left + scanBoxSize, top + cornerLen), cornerPaint);

    // Bottom-Left
    canvas.drawLine(Offset(left, top + scanBoxSize), Offset(left + cornerLen, top + scanBoxSize), cornerPaint);
    canvas.drawLine(Offset(left, top + scanBoxSize), Offset(left, top + scanBoxSize - cornerLen), cornerPaint);

    // Bottom-Right
    canvas.drawLine(Offset(left + scanBoxSize, top + scanBoxSize), Offset(left + scanBoxSize - cornerLen, top + scanBoxSize), cornerPaint);
    canvas.drawLine(Offset(left + scanBoxSize, top + scanBoxSize), Offset(left + scanBoxSize, top + scanBoxSize - cornerLen), cornerPaint);

    // Crosshair Center
    final centerPaint = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(scanRect.center.dx - 12, scanRect.center.dy), Offset(scanRect.center.dx + 12, scanRect.center.dy), centerPaint);
    canvas.drawLine(Offset(scanRect.center.dx, scanRect.center.dy - 12), Offset(scanRect.center.dx, scanRect.center.dy + 12), centerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
