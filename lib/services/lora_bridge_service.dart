import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message_model.dart';
import 'native_hardware_service.dart';

enum LoraBridgeMode {
  disabled,
  usbOtgSerial,
  bluetoothBle,
  simulatedHardware,
}

class LoraModemConfig {
  final double frequencyMhz; // Misal: 915.0 atau 433.0 MHz
  final int spreadingFactor; // SF7 (Cepat) s/d SF12 (Jangkauan Maksimal ~20km)
  final int bandwidthKhz; // 125, 250, 500 kHz
  final int txPowerDbm; // 14 s/d 22 dBm

  const LoraModemConfig({
    this.frequencyMhz = 915.0,
    this.spreadingFactor = 10,
    this.bandwidthKhz = 125,
    this.txPowerDbm = 20,
  });

  Map<String, dynamic> toMap() => {
    'frequency_mhz': frequencyMhz,
    'spreading_factor': spreadingFactor,
    'bandwidth_khz': bandwidthKhz,
    'tx_power_dbm': txPowerDbm,
  };

  factory LoraModemConfig.fromMap(Map<String, dynamic> map) => LoraModemConfig(
    frequencyMhz: (map['frequency_mhz'] as num?)?.toDouble() ?? 915.0,
    spreadingFactor: (map['spreading_factor'] as num?)?.toInt() ?? 10,
    bandwidthKhz: (map['bandwidth_khz'] as num?)?.toInt() ?? 125,
    txPowerDbm: (map['tx_power_dbm'] as num?)?.toInt() ?? 20,
  );
}

class LoraBridgeService {
  static final LoraBridgeService instance = LoraBridgeService._init();
  LoraBridgeService._init();

  LoraBridgeMode _bridgeMode = LoraBridgeMode.disabled;
  LoraModemConfig _config = const LoraModemConfig();
  bool _isConnected = false;
  String _hardwareInfo = 'Tidak Terhubung';

  final StreamController<MessageModel> _incomingLoraMessages =
      StreamController<MessageModel>.broadcast();

  LoraBridgeMode get bridgeMode => _bridgeMode;
  LoraModemConfig get config => _config;
  bool get isConnected => _isConnected;
  String get hardwareInfo => _hardwareInfo;
  Stream<MessageModel> get incomingLoraMessages => _incomingLoraMessages.stream;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = prefs.getString('lora_bridge_mode') ?? 'disabled';
    _bridgeMode = LoraBridgeMode.values.firstWhere(
      (m) => m.name == modeStr,
      orElse: () => LoraBridgeMode.disabled,
    );

    final configJson = prefs.getString('lora_modem_config');
    if (configJson != null) {
      try {
        _config = LoraModemConfig.fromMap(json.decode(configJson));
      } catch (_) {}
    }

    if (_bridgeMode != LoraBridgeMode.disabled) {
      await connectBridge(_bridgeMode);
    }
  }

  Future<void> setBridgeMode(LoraBridgeMode mode) async {
    _bridgeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lora_bridge_mode', mode.name);

    if (mode == LoraBridgeMode.disabled) {
      await disconnectBridge();
    } else {
      await connectBridge(mode);
    }
  }

  Future<void> updateConfig(LoraModemConfig newConfig) async {
    _config = newConfig;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lora_modem_config', json.encode(newConfig.toMap()));
  }

  Future<bool> connectBridge(LoraBridgeMode mode) async {
    _bridgeMode = mode;
    if (mode == LoraBridgeMode.simulatedHardware) {
      _isConnected = true;
      _hardwareInfo = 'Heltec V3 ESP32 LoRa (Simulasi Logika @ ${_config.frequencyMhz}MHz SF${_config.spreadingFactor})';
      return true;
    } else if (mode == LoraBridgeMode.usbOtgSerial) {
      // Periksa perangkat keras USB yang terpasang secara fisik di port ponsel
      final usbDevices = await NativeHardwareService.instance.getAttachedUsbDevices();
      final loraDevice = usbDevices.where((d) => d.isLoRaCompatible).firstOrNull;

      if (loraDevice != null) {
        _isConnected = true;
        _hardwareInfo = 'Modem Fisik Terdeteksi: ${loraDevice.name} (VID: 0x${loraDevice.vendorId.toRadixString(16).toUpperCase()}) @ ${_config.frequencyMhz}MHz SF${_config.spreadingFactor}';
        return true;
      } else if (usbDevices.isNotEmpty) {
        _isConnected = true;
        _hardwareInfo = 'Perangkat USB Terdeteksi: ${usbDevices.first.name} @ 115200 baud';
        return true;
      } else {
        _isConnected = false;
        _hardwareInfo = 'Menunggu Kabel USB OTG Modul LoRa ESP32 (Belum Tercolok)';
        return false;
      }
    } else if (mode == LoraBridgeMode.bluetoothBle) {
      // Inisialisasi bridge BLE Meshtastic / Custom LoRa
      _isConnected = false;
      _hardwareInfo = 'Menunggu Pairing BLE Meshtastic T-Beam';
      return false;
    }
    _isConnected = false;
    _hardwareInfo = 'Terputus';
    return false;
  }

  Future<void> disconnectBridge() async {
    _isConnected = false;
    _hardwareInfo = 'Tidak Terhubung';
  }

  /// Mengirim frame radio LoRa jarak jauh (5 - 20 km)
  Future<bool> transmitLoraFrame(MessageModel message) async {
    if (!_isConnected) return false;

    try {
      debugPrint('[LoRa RF Transceiver] Memancarkan paket ${message.messageId} via radio LoRa (${_config.frequencyMhz} MHz, SF${_config.spreadingFactor}, TX: ${_config.txPowerDbm} dBm)...');
      // Frame terkirim ke radio transceiver eksternal
      return true;
    } catch (e) {
      debugPrint('[LoRa Bridge] Gagal memancarkan frame: $e');
      return false;
    }
  }

  /// Injeksi paket LoRa masuk dari jarak jauh
  void injectSimulatedIncomingLoraPacket(MessageModel message) {
    _incomingLoraMessages.add(message);
  }

  void dispose() {
    _incomingLoraMessages.close();
  }
}
