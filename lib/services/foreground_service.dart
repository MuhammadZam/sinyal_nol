import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ForegroundService {
  static final ForegroundService instance = ForegroundService._init();
  ForegroundService._init();

  static const MethodChannel _channel = MethodChannel('com.sinyalnol/mesh_service');
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  /// Memulai Android Foreground Service dengan notifikasi persisten & Wakelock
  Future<void> start({
    String title = 'SinyalNol Mesh Radio Siaga',
    String text = 'Radio P2P & Dead Man\'s Switch aktif di latar belakang',
  }) async {
    if (!Platform.isAndroid) return;
    try {
      final success = await _channel.invokeMethod<bool>('startForegroundService', {
        'title': title,
        'text': text,
      });
      _isRunning = success ?? false;
      debugPrint('[ForegroundService] Started: $_isRunning');
    } catch (e) {
      debugPrint('[ForegroundService] Gagal memulai service: $e');
    }
  }

  /// Memperbarui teks notifikasi persisten (misal: jumlah node terdeteksi)
  Future<void> updateNotification({
    required String title,
    required String text,
  }) async {
    if (!Platform.isAndroid || !_isRunning) return;
    try {
      await _channel.invokeMethod<bool>('updateNotification', {
        'title': title,
        'text': text,
      });
    } catch (e) {
      debugPrint('[ForegroundService] Gagal update notifikasi: $e');
    }
  }

  /// Menghentikan foreground service & melepaskan wakelock
  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('stopForegroundService');
      _isRunning = false;
      debugPrint('[ForegroundService] Stopped');
    } catch (e) {
      debugPrint('[ForegroundService] Gagal menghentikan service: $e');
    }
  }
}
