import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/message_model.dart';
import '../models/peer_device.dart';
import '../models/sar_waypoint.dart';
import '../models/offline_map_pack.dart';
import '../models/breadcrumb_point.dart';
import '../database/local_db.dart';
import '../services/connectivity_service.dart';
import '../services/message_service.dart';
import '../services/location_service.dart';
import '../services/encryption_service.dart';
import '../services/foreground_service.dart';
import '../services/compass_service.dart';
import '../services/tactical_audio_service.dart';
import '../services/lora_bridge_service.dart';
import '../services/voice_service.dart';
import '../utils/tactical_coords.dart';
import 'package:geolocator/geolocator.dart';

class AppProvider with ChangeNotifier {
  final LocalDatabase _db = LocalDatabase.instance;
  final LocationService _locationService = LocationService();
  late final IConnectivityService _connectivity;
  MessageService? _messageService;

  String _localDeviceId = '';
  String _localDeviceName = 'Node-${DateTime.now().millisecond}';
  bool _isInitialized = false;

  bool _isRadioActive = false;
  bool _isRelayEnabled = true;
  bool _isBatterySaverEnabled = false;
  int _maxHops = 3;
  int _ttlHours = 24;

  LocationResult? _lastLocation;
  bool _isFetchingLocation = false;

  List<MessageModel> _messages = [];
  List<PeerDevice> _peers = [];
  List<Map<String, dynamic>> _fieldTestLogs = [];
  List<SarWaypoint> _waypoints = [];
  List<BreadcrumbPoint> _breadcrumbs = [];
  bool _isRecordingBreadcrumbs = false;
  StreamSubscription<Position>? _breadcrumbSub;
  List<OfflineMapPack> _offlineMapPacks = [];

  // Dead Man's Switch (Safeguard Responder SAR)
  bool _isDeadManSwitchActive = false;
  int _deadManIntervalMinutes = 15;
  int _deadManSecondsRemaining = 0;
  Timer? _deadManTimer;
  bool _isDeadManWarning = false;

  // Hardware Compass & LoRa Bridge State
  double _compassHeading = 0.0;
  StreamSubscription? _compassSub;
  StreamSubscription? _loraSub;
  StreamSubscription? _msgSub;
  StreamSubscription? _peersSub;

  // Getters
  String get localDeviceId => _localDeviceId;
  String get localDeviceName => _localDeviceName;
  bool get isInitialized => _isInitialized;
  bool get isRadioActive => _isRadioActive;
  bool get isRelayEnabled => _isRelayEnabled;
  bool get isBatterySaverEnabled => _isBatterySaverEnabled;
  int get maxHops => _maxHops;
  int get ttlHours => _ttlHours;
  LocationResult? get lastLocation => _lastLocation;
  bool get isFetchingLocation => _isFetchingLocation;
  List<MessageModel> get messages => _messages;
  List<PeerDevice> get peers => _peers;
  List<Map<String, dynamic>> get fieldTestLogs => _fieldTestLogs;
  List<SarWaypoint> get waypoints => _waypoints;
  List<BreadcrumbPoint> get breadcrumbs => _breadcrumbs;
  bool get isRecordingBreadcrumbs => _isRecordingBreadcrumbs;
  List<OfflineMapPack> get offlineMapPacks => _offlineMapPacks;

  double get totalBreadcrumbDistanceMeters {
    if (_breadcrumbs.length < 2) return 0.0;
    double dist = 0.0;
    for (int i = 0; i < _breadcrumbs.length - 1; i++) {
      dist += TacticalCoords.calculateDistanceMeters(
        _breadcrumbs[i].latitude,
        _breadcrumbs[i].longitude,
        _breadcrumbs[i + 1].latitude,
        _breadcrumbs[i + 1].longitude,
      );
    }
    return dist;
  }
  String get myPublicKey => EncryptionService.instance.myPublicKeyBase64;
  bool hasPeerE2eeKey(String? peerId) => EncryptionService.instance.hasPeerKey(peerId);
  bool isPeerVerified(String? peerId) => EncryptionService.instance.isPeerVerified(peerId);

  /// Memverifikasi identitas rekan melalui payload string QR Code Taktis
  bool verifyPeerFromQr(String qrString) {
    final parts = qrString.trim().split('|');
    if (parts.length < 4 || parts[0] != 'SINYALNOL') {
      return false;
    }
    final peerId = parts[1];
    final pubKey = parts.length >= 5 ? parts[4] : '';

    if (pubKey.isNotEmpty) {
      EncryptionService.instance.registerPeerPublicKey(peerId, pubKey, isVerified: true);
    } else {
      EncryptionService.instance.markPeerVerified(peerId);
    }

    _peers = _peers.map((p) {
      if (p.deviceId == peerId) {
        return p.copyWith(
          isVerified: true,
          publicKey: pubKey.isNotEmpty ? pubKey : p.publicKey,
        );
      }
      return p;
    }).toList();

    notifyListeners();
    return true;
  }

  // Compass Heading Getter
  double get compassHeading => _compassHeading;

  final Set<String> _knownPeerIds = {};

  // Tactical Audio & Alert Getters
  bool get isSfxEnabled => TacticalAudioService.instance.isSfxEnabled;
  bool get isAutoSquawkEnabled => TacticalAudioService.instance.isAutoSquawkEnabled;
  bool get isRogerBeepEnabled => TacticalAudioService.instance.isRogerBeepEnabled;
  bool get isRadarPingEnabled => TacticalAudioService.instance.isRadarPingEnabled;
  bool get isMessageToneEnabled => TacticalAudioService.instance.isMessageToneEnabled;
  bool get isVibrationEnabled => TacticalAudioService.instance.isVibrationEnabled;

  // LoRa Hardware Bridge Getters
  LoraBridgeMode get loraBridgeMode => LoraBridgeService.instance.bridgeMode;
  LoraModemConfig get loraConfig => LoraBridgeService.instance.config;
  bool get isLoraConnected => LoraBridgeService.instance.isConnected;
  String get loraHardwareInfo => LoraBridgeService.instance.hardwareInfo;

  // Dead Man's Switch Getters
  bool get isDeadManSwitchActive => _isDeadManSwitchActive;
  int get deadManIntervalMinutes => _deadManIntervalMinutes;
  int get deadManSecondsRemaining => _deadManSecondsRemaining;
  bool get isDeadManWarning => _isDeadManWarning;
  String get deadManCountdownFormatted {
    final mins = (_deadManSecondsRemaining ~/ 60).toString().padLeft(2, '0');
    final secs = (_deadManSecondsRemaining % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  /// Sidik jari kriptografis perangkat (SHA-256 Node Fingerprint) untuk verifikasi identitas taktis
  String get deviceFingerprint {
    final bytes = utf8.encode('SINYALNOL_NODE:$_localDeviceId');
    final digest = sha256.convert(bytes).toString().toUpperCase();
    return '${digest.substring(0, 4)}:${digest.substring(4, 8)}:${digest.substring(8, 12)}:${digest.substring(12, 16)}';
  }

  AppProvider() {
    _connectivity = WifiLocalConnectivityService();
    init();
  }

  Future<void> init() async {
    // Inisialisasi Kriptografi Asimetris X25519 & AES-256-GCM
    await EncryptionService.instance.initialize();

    // Inisialisasi Audio Taktis & Bridge LoRa
    await TacticalAudioService.instance.init();
    await LoraBridgeService.instance.init();

    final prefs = await SharedPreferences.getInstance();
    _localDeviceId = prefs.getString('local_device_id') ?? const Uuid().v4().substring(0, 8).toUpperCase();
    _localDeviceName = prefs.getString('local_device_name') ?? 'Ponsel-${_localDeviceId.substring(0, 4)}';
    _isRelayEnabled = prefs.getBool('is_relay_enabled') ?? true;
    _isBatterySaverEnabled = prefs.getBool('is_battery_saver_enabled') ?? false;
    _maxHops = prefs.getInt('max_hops') ?? 3;
    _ttlHours = prefs.getInt('ttl_hours') ?? 24;

    await prefs.setString('local_device_id', _localDeviceId);
    await prefs.setString('local_device_name', _localDeviceName);

    _messageService = MessageService(
      connectivity: _connectivity,
      localDeviceId: _localDeviceId,
      localDeviceName: _localDeviceName,
    );
    _messageService!.isRelayEnabled = _isRelayEnabled;
    _messageService!.maxHopsLimit = _maxHops;
    _messageService!.defaultTtlHours = _ttlHours;
    _messageService!.initialize();

    // Terapkan interval beacon sesuai status hemat baterai
    if (_isBatterySaverEnabled) {
      _connectivity.setBeaconInterval(const Duration(seconds: 15));
    }

    // Dengarkan kompas magnetometer perangkat secara real-time
    _compassSub = CompassService.instance.headingStream.listen((heading) {
      _compassHeading = heading;
      notifyListeners();
    });

    // Dengarkan pesan masuk dari lapisan konektivitas lokal
    _msgSub = _messageService!.onNewMessage.listen((msg) async {
      await loadMessages();
      await ForegroundService.instance.updateNotification(
        title: 'SinyalNol Mesh: Pesan Baru',
        text: 'Dari: ${msg.senderName} (${msg.messageType.name.toUpperCase()})',
      );

      // Suara & Notifikasi Taktis untuk pesan dari pihak lain
      if (msg.senderId != _localDeviceId) {
        if (msg.messageType == MessageType.sos) {
          // Sirene darurat SOS
          await TacticalAudioService.instance.playSosAlert();
        } else if (msg.messageType == MessageType.voice) {
          // Auto-Squawk PTT Walkie-Talkie
          if (TacticalAudioService.instance.isAutoSquawkEnabled) {
            await TacticalAudioService.instance.playIncomingSquawk();
            if (msg.voiceBase64Data.isNotEmpty) {
              try {
                await VoiceService.instance.playVoiceMessage(msg.messageId, msg.voiceBase64Data);
              } catch (e) {
                debugPrint('[AppProvider] Auto-squawk error: $e');
              }
            }
          }
        } else {
          // Chirp notifikasi teks / info masuk
          await TacticalAudioService.instance.playIncomingMessageTone();
        }
      }
    });

    // Dengarkan pesan dari hardware LoRa jarak jauh
    _loraSub = LoraBridgeService.instance.incomingLoraMessages.listen((msg) async {
      await _db.insertMessage(msg);
      await loadMessages();
      if (msg.senderId != _localDeviceId) {
        if (msg.messageType == MessageType.sos) {
          await TacticalAudioService.instance.playSosAlert();
        } else if (msg.messageType == MessageType.voice && TacticalAudioService.instance.isAutoSquawkEnabled) {
          await TacticalAudioService.instance.playIncomingSquawk();
          if (msg.voiceBase64Data.isNotEmpty) {
            try {
              await VoiceService.instance.playVoiceMessage(msg.messageId, msg.voiceBase64Data);
            } catch (_) {}
          }
        } else {
          await TacticalAudioService.instance.playIncomingMessageTone();
        }
      }
    });

    // Dengarkan perubahan peer
    _peersSub = _connectivity.peersStream.listen((updatedPeers) {
      // Deteksi jika ada rekan / node baru yang masuk ke dalam jangkauan radar
      final newPeers = updatedPeers.where((p) => !_knownPeerIds.contains(p.deviceId)).toList();
      if (newPeers.isNotEmpty && _isInitialized) {
        // Nada Sonar Radar: Perangkat rekan terhubung / terdeteksi
        TacticalAudioService.instance.playNodeConnectedSonar();
      }
      _knownPeerIds.clear();
      _knownPeerIds.addAll(updatedPeers.map((p) => p.deviceId));

      _peers = updatedPeers;
      ForegroundService.instance.updateNotification(
        title: 'SinyalNol Mesh Siaga 24/7',
        text: '${_peers.length} node radio terdeteksi di sekitar',
      );
      notifyListeners();
    });

    // Mulai radio secara default dengan menyertakan Public Key
    await startRadio();

    await loadMessages();
    await loadFieldTestLogs();
    await loadWaypoints();
    await loadBreadcrumbs();
    await loadOfflineMapPacks();
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setBatterySaver(bool value) async {
    _isBatterySaverEnabled = value;
    _connectivity.setBeaconInterval(
      value ? const Duration(seconds: 15) : const Duration(seconds: 4),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_battery_saver_enabled', value);
    notifyListeners();
  }

  Future<void> updateDeviceName(String newName) async {
    _localDeviceName = newName.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('local_device_name', _localDeviceName);
    notifyListeners();
  }

  Future<void> setRelayEnabled(bool value) async {
    _isRelayEnabled = value;
    _messageService?.isRelayEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_relay_enabled', value);
    notifyListeners();
  }

  Future<void> setMaxHops(int value) async {
    _maxHops = value;
    _messageService?.maxHopsLimit = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('max_hops', value);
    notifyListeners();
  }

  Future<void> setTtlHours(int value) async {
    _ttlHours = value;
    _messageService?.defaultTtlHours = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ttl_hours', value);
    notifyListeners();
  }

  Future<void> startRadio() async {
    if (_isRadioActive) return;
    await _connectivity.start(
      localDeviceId: _localDeviceId,
      localDeviceName: _localDeviceName,
      localPublicKey: EncryptionService.instance.myPublicKeyBase64,
    );
    _isRadioActive = true;
    await ForegroundService.instance.start(
      title: 'SinyalNol Mesh Siaga 24/7',
      text: 'Node: $_localDeviceName | Peering Radio Aktif',
    );
    notifyListeners();
  }

  Future<void> stopRadio() async {
    await _connectivity.stop();
    _isRadioActive = false;
    _peers = [];
    await ForegroundService.instance.stop();
    notifyListeners();
  }

  Future<void> setSfxEnabled(bool value) async {
    await TacticalAudioService.instance.setSfxEnabled(value);
    notifyListeners();
  }

  Future<void> setAutoSquawk(bool value) async {
    await TacticalAudioService.instance.setAutoSquawk(value);
    notifyListeners();
  }

  Future<void> setRogerBeep(bool value) async {
    await TacticalAudioService.instance.setRogerBeep(value);
    notifyListeners();
  }

  Future<void> setRadarPing(bool value) async {
    await TacticalAudioService.instance.setRadarPing(value);
    notifyListeners();
  }

  Future<void> setMessageTone(bool value) async {
    await TacticalAudioService.instance.setMessageTone(value);
    notifyListeners();
  }

  Future<void> setVibration(bool value) async {
    await TacticalAudioService.instance.setVibration(value);
    notifyListeners();
  }

  Future<void> setLoraBridgeMode(LoraBridgeMode mode) async {
    await LoraBridgeService.instance.setBridgeMode(mode);
    notifyListeners();
  }

  Future<void> updateLoraConfig(LoraModemConfig config) async {
    await LoraBridgeService.instance.updateConfig(config);
    notifyListeners();
  }

  Future<void> loadMessages() async {
    _messages = await _db.getAllMessages();
    notifyListeners();
  }

  Future<void> loadFieldTestLogs() async {
    _fieldTestLogs = await _db.getFieldTestLogs();
    notifyListeners();
  }

  /// Memperbarui koordinat GPS satu kali dengan persetujuan pengguna
  Future<LocationResult?> fetchCurrentGpsLocation() async {
    _isFetchingLocation = true;
    notifyListeners();
    final loc = await _locationService.getCurrentLocation();
    _lastLocation = loc;
    _isFetchingLocation = false;
    notifyListeners();
    return loc;
  }

  /// Mengirim pesan teks atau berbagi lokasi
  Future<void> sendMessage({
    required String body,
    String? recipientId,
    bool attachLocation = false,
    double? customLatitude,
    double? customLongitude,
    double? customAltitude,
  }) async {
    if (_messageService == null) return;

    double? lat = customLatitude;
    double? lng = customLongitude;
    double? alt = customAltitude;

    if (attachLocation && lat == null) {
      final loc = await _locationService.getCurrentLocation();
      if (loc != null) {
        lat = loc.latitude;
        lng = loc.longitude;
        alt = loc.altitude;
        _lastLocation = loc;
      }
    }

    final msg = await _messageService!.createAndSendMessage(
      recipientId: recipientId,
      body: body,
      type: (attachLocation || lat != null) ? MessageType.location : MessageType.text,
      latitude: lat,
      longitude: lng,
      altitude: alt,
    );

    // Pancarkan juga ke hardware LoRa bridge jika terhubung
    if (LoraBridgeService.instance.isConnected) {
      await LoraBridgeService.instance.transmitLoraFrame(msg);
    }
  }

  /// Mengirim pesan SOS Darurat dengan peringatan jujur
  Future<void> sendSosBroadcast({required String emergencyNote, bool attachLocation = true}) async {
    if (_messageService == null) return;

    double? lat;
    double? lng;
    double? alt;

    if (attachLocation) {
      final loc = await _locationService.getCurrentLocation();
      if (loc != null) {
        lat = loc.latitude;
        lng = loc.longitude;
        alt = loc.altitude;
        _lastLocation = loc;
      }
    }

    final body = emergencyNote.trim().isEmpty ? 'DARURAT! Membutuhkan bantuan segera.' : emergencyNote;

    final msg = await _messageService!.createAndSendMessage(
      recipientId: 'BROADCAST',
      body: '[SOS DARURAT] $body',
      type: MessageType.sos,
      latitude: lat,
      longitude: lng,
      altitude: alt,
    );

    // Pancarkan SOS via LoRa jarak jauh
    if (LoraBridgeService.instance.isConnected) {
      await LoraBridgeService.instance.transmitLoraFrame(msg);
    }
  }

  /// Menambahkan peer simulasi (untuk menguji mekanisme offline & relay pada simulator/1 perangkat)
  Future<void> addSimulatedPeer({
    required String name,
    required double estimatedDistance,
    int rssi = -65,
  }) async {
    final simKeyPair = await X25519().newKeyPair();
    final simPubKey = await simKeyPair.extractPublicKey();
    final simPubKeyBase64 = base64.encode(simPubKey.bytes);
    final simId = 'SIM-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';

    EncryptionService.instance.registerPeerPublicKey(simId, simPubKeyBase64, isVerified: true);

    final simPeer = PeerDevice(
      deviceId: simId,
      deviceName: name,
      address: '192.168.43.10',
      port: 8888,
      connectionType: ConnectionType.simulated,
      rssi: rssi,
      lastSeen: DateTime.now(),
      estimatedDistanceMeters: estimatedDistance,
      publicKey: simPubKeyBase64,
      isVerified: true,
    );
    _connectivity.injectSimulatedPeer(simPeer);
  }

  /// Mencatat log uji lapangan pengiriman pesan
  Future<void> recordFieldTest({
    required String targetPeer,
    required double distanceMeters,
    required String terrainType,
    required bool success,
    required int latencyMs,
    required int rssi,
    required double batteryLevel,
    required String notes,
  }) async {
    final log = {
      'timestamp': DateTime.now().toIso8601String(),
      'target_peer': targetPeer,
      'distance_meters': distanceMeters,
      'terrain_type': terrainType,
      'success': success ? 1 : 0,
      'latency_ms': latencyMs,
      'rssi': rssi,
      'battery_level': batteryLevel,
      'notes': notes,
    };
    await _db.insertFieldTestLog(log);
    await loadFieldTestLogs();
  }

  /// Ekspor log uji lapangan ke file CSV lokal
  Future<String> exportFieldTestLogsToCsv() => _db.exportFieldTestLogsToCsv();

  /// Ekspor seluruh riwayat pesan ke file CSV lokal
  Future<String> exportMessagesToCsv() => _db.exportMessagesToCsv();

  // --- Manajemen Waypoint SAR & Grid Taktis ---

  Future<void> loadWaypoints() async {
    _waypoints = await _db.getAllWaypoints();
    notifyListeners();
  }

  Future<void> addWaypoint(SarWaypoint waypoint) async {
    await _db.insertWaypoint(waypoint);
    await TacticalAudioService.instance.playWaypointTone();
    await loadWaypoints();
  }

  Future<void> removeWaypoint(String id) async {
    await _db.deleteWaypoint(id);
    await loadWaypoints();
  }

  /// Menyiarkan Waypoint Taktis ke seluruh rekan di jaringan mesh
  Future<void> broadcastWaypoint(SarWaypoint wp) async {
    final notePart = wp.notes != null && wp.notes!.isNotEmpty ? ' | Catatan: ${wp.notes}' : '';
    final body = '[WAYPOINT] ${wp.name} (${wp.categoryLabel})$notePart';
    await sendMessage(
      body: body,
      customLatitude: wp.latitude,
      customLongitude: wp.longitude,
      customAltitude: wp.altitude,
    );
  }

  // --- Manajemen Jejak Rute GPS (Breadcrumbs Trail) ---

  Future<void> loadBreadcrumbs() async {
    _breadcrumbs = await _db.getAllBreadcrumbs();
    notifyListeners();
  }

  Future<void> startBreadcrumbRecording() async {
    if (_isRecordingBreadcrumbs) return;
    final hasPerm = await _locationService.checkAndRequestPermission();
    if (!hasPerm) return;

    _isRecordingBreadcrumbs = true;
    notifyListeners();

    _breadcrumbSub?.cancel();
    _breadcrumbSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8, // Catat setiap pergeseran 8 meter
      ),
    ).listen((pos) async {
      final point = BreadcrumbPoint(
        latitude: pos.latitude,
        longitude: pos.longitude,
        altitude: pos.altitude,
        timestamp: pos.timestamp,
      );
      _breadcrumbs.add(point);
      await _db.insertBreadcrumb(point);
      notifyListeners();
    });
  }

  Future<void> stopBreadcrumbRecording() async {
    _isRecordingBreadcrumbs = false;
    await _breadcrumbSub?.cancel();
    _breadcrumbSub = null;
    notifyListeners();
  }

  Future<void> clearBreadcrumbs() async {
    await stopBreadcrumbRecording();
    await _db.clearBreadcrumbs();
    _breadcrumbs.clear();
    notifyListeners();
  }

  // --- Manajemen Paket Peta Offline ---

  Future<void> loadOfflineMapPacks() async {
    _offlineMapPacks = await _db.getAllOfflinePacks();
    notifyListeners();
  }

  Future<void> deleteOfflineMapPack(String id) async {
    await _db.deleteOfflinePack(id);
    await loadOfflineMapPacks();
  }

  // --- Fitur Dead Man's Switch (Safeguard Responder SAR) ---

  Future<void> startDeadManSwitch(int minutes) async {
    _deadManTimer?.cancel();
    _deadManIntervalMinutes = minutes;
    _deadManSecondsRemaining = minutes * 60;
    _isDeadManSwitchActive = true;
    _isDeadManWarning = false;
    notifyListeners();

    _deadManTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isDeadManSwitchActive) {
        timer.cancel();
        return;
      }

      if (_deadManSecondsRemaining > 0) {
        _deadManSecondsRemaining--;
        if (_deadManSecondsRemaining <= 60 && !_isDeadManWarning) {
          _isDeadManWarning = true;
        }
        notifyListeners();
      } else {
        // Waktu habis! Responder tidak merespons check-in
        timer.cancel();
        _triggerDeadManSos();
      }
    });
  }

  void stopDeadManSwitch() {
    _deadManTimer?.cancel();
    _isDeadManSwitchActive = false;
    _isDeadManWarning = false;
    _deadManSecondsRemaining = 0;
    notifyListeners();
  }

  void checkInDeadManSwitch() {
    if (!_isDeadManSwitchActive) return;
    _deadManSecondsRemaining = _deadManIntervalMinutes * 60;
    _isDeadManWarning = false;
    notifyListeners();
  }

  /// Mengirim pesan suara Walkie-Talkie Asinkron PTT Offline
  Future<void> sendVoiceNote({
    required String voicePayloadJson,
    String? recipientId,
  }) async {
    if (_messageService == null) return;
    final msg = await _messageService!.createAndSendMessage(
      recipientId: recipientId,
      body: voicePayloadJson,
      type: MessageType.voice,
      latitude: _lastLocation?.latitude,
      longitude: _lastLocation?.longitude,
      altitude: _lastLocation?.altitude,
    );

    // Mainkan nada Roger Beep khas radio
    await TacticalAudioService.instance.playRogerBeep();

    // Pancarkan ke LoRa jika terhubung
    if (LoraBridgeService.instance.isConnected) {
      await LoraBridgeService.instance.transmitLoraFrame(msg);
    }
  }

  Future<void> _triggerDeadManSos() async {
    _isDeadManWarning = true;
    notifyListeners();
    await sendSosBroadcast(
      emergencyNote: '[DEAD MAN SWITCH TRIGGERED] Responder/Pendaki (Node-$_localDeviceId) tidak merespons konfirmasi "Saya Selamat"! Periksa koordinat GNSS darurat segera.',
      attachLocation: true,
    );
  }

  /// Ekspor seluruh data (Pesan + Uji Lapangan + Waypoints) ke file JSON lokal
  Future<String> exportAllToJson() => _db.exportAllToJson();

  /// Hapus riwayat chat & data lokal
  Future<void> clearAllHistory() async {
    await _db.clearAllData();
    await loadMessages();
    await loadFieldTestLogs();
    await loadWaypoints();
  }

  @override
  void dispose() {
    _deadManTimer?.cancel();
    _compassSub?.cancel();
    _loraSub?.cancel();
    _msgSub?.cancel();
    _peersSub?.cancel();
    _messageService?.dispose();
    _connectivity.stop();
    TacticalAudioService.instance.dispose();
    LoraBridgeService.instance.dispose();
    super.dispose();
  }
}
