import 'dart:async';
import 'package:flutter/services.dart';

class UsbDeviceInfo {
  final String name;
  final int vendorId;
  final int productId;
  final String deviceName;
  final bool isLoRaCompatible;

  UsbDeviceInfo({
    required this.name,
    required this.vendorId,
    required this.productId,
    required this.deviceName,
    required this.isLoRaCompatible,
  });

  factory UsbDeviceInfo.fromMap(Map<dynamic, dynamic> map) {
    return UsbDeviceInfo(
      name: (map['name'] as String?) ?? 'USB Device',
      vendorId: (map['vendorId'] as num?)?.toInt() ?? 0,
      productId: (map['productId'] as num?)?.toInt() ?? 0,
      deviceName: (map['deviceName'] as String?) ?? '',
      isLoRaCompatible: map['isLoRaCompatible'] == true,
    );
  }
}

class BondedBluetoothDevice {
  final String name;
  final String address;

  BondedBluetoothDevice({required this.name, required this.address});

  factory BondedBluetoothDevice.fromMap(Map<dynamic, dynamic> map) {
    return BondedBluetoothDevice(
      name: (map['name'] as String?) ?? 'Bluetooth Device',
      address: (map['address'] as String?) ?? '',
    );
  }
}

class BluetoothIncomingPacket {
  final String rawData;
  final String senderAddress;
  final String senderName;

  BluetoothIncomingPacket({
    required this.rawData,
    required this.senderAddress,
    required this.senderName,
  });
}

class NativeHardwareService {
  static final NativeHardwareService instance = NativeHardwareService._init();
  NativeHardwareService._init();

  static const _systemChannel = MethodChannel('com.sinyalnol/system_settings');
  static const _bluetoothChannel = MethodChannel('com.sinyalnol/bluetooth');
  static const _bluetoothEventsChannel = EventChannel('com.sinyalnol/bluetooth_events');
  static const _usbLoraChannel = MethodChannel('com.sinyalnol/usb_lora');

  final StreamController<BluetoothIncomingPacket> _bluetoothIncomingController =
      StreamController<BluetoothIncomingPacket>.broadcast();

  Stream<BluetoothIncomingPacket> get onBluetoothPacketReceived =>
      _bluetoothIncomingController.stream;

  StreamSubscription? _btEventSub;
  bool _isListeningBt = false;

  void initialize() {
    if (_isListeningBt) return;
    _btEventSub = _bluetoothEventsChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          final data = (event['data'] as String?) ?? '';
          final address = (event['address'] as String?) ?? '';
          final name = (event['name'] as String?) ?? 'Bluetooth Node';
          if (data.isNotEmpty) {
            _bluetoothIncomingController.add(
              BluetoothIncomingPacket(
                rawData: data,
                senderAddress: address,
                senderName: name,
              ),
            );
          }
        }
      },
      onError: (_) {},
    );
    _isListeningBt = true;
  }

  // --- 1. System Settings & Local IP ---

  Future<void> openTetheringSettings() async {
    try {
      await _systemChannel.invokeMethod('openTetheringSettings');
    } catch (_) {}
  }

  Future<void> openBluetoothSettings() async {
    try {
      await _systemChannel.invokeMethod('openBluetoothSettings');
    } catch (_) {}
  }

  Future<String> getLocalIpAddress() async {
    try {
      final ip = await _systemChannel.invokeMethod<String>('getLocalIpAddress');
      return ip ?? '127.0.0.1';
    } catch (_) {
      return '127.0.0.1';
    }
  }

  // --- 2. Native Bluetooth RFCOMM ---

  Future<bool> isBluetoothSupported() async {
    try {
      return await _bluetoothChannel.invokeMethod<bool>('isBluetoothSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isBluetoothEnabled() async {
    try {
      return await _bluetoothChannel.invokeMethod<bool>('isBluetoothEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<List<BondedBluetoothDevice>> getBondedBluetoothDevices() async {
    try {
      final list = await _bluetoothChannel.invokeMethod<List<dynamic>>('getBondedDevices');
      if (list == null) return [];
      return list
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => BondedBluetoothDevice.fromMap(m))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> startBluetoothRfcommServer() async {
    try {
      initialize();
      return await _bluetoothChannel.invokeMethod<bool>('startRfcommServer') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopBluetoothRfcommServer() async {
    try {
      return await _bluetoothChannel.invokeMethod<bool>('stopRfcommServer') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendBluetoothRfcommMessage({
    required String address,
    required String message,
  }) async {
    try {
      return await _bluetoothChannel.invokeMethod<bool>('sendRfcommMessage', {
            'address': address,
            'message': message,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  // --- 3. USB OTG LoRa Transceiver Hardware Detection ---

  Future<List<UsbDeviceInfo>> getAttachedUsbDevices() async {
    try {
      final list = await _usbLoraChannel.invokeMethod<List<dynamic>>('getAttachedUsbDevices');
      if (list == null) return [];
      return list
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => UsbDeviceInfo.fromMap(m))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void dispose() {
    _btEventSub?.cancel();
    _bluetoothIncomingController.close();
  }
}
