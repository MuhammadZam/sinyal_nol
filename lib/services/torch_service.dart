import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class TorchService {
  static const MethodChannel _channel = MethodChannel('com.sinyalnol/mesh_service');

  /// Menghidupkan atau mematikan LED senter kamera belakang (Torch Flashlight)
  static Future<void> setTorch(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setTorchMode', {'enabled': enabled});
    } catch (e) {
      debugPrint('[TorchService] Gagal mengatur senter: $e');
    }
  }
}
