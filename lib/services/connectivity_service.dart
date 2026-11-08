import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/message_model.dart';
import '../models/peer_device.dart';
import 'encryption_service.dart';
import 'native_hardware_service.dart';

/// Kontrak Lapisan Konektivitas (Mendukung Hybrid Dual-Stack: Wi-Fi Subnet & Bluetooth RFCOMM)
abstract class IConnectivityService {
  Stream<List<PeerDevice>> get peersStream;
  Stream<MessageModel> get messageReceivedStream;
  List<PeerDevice> get currentPeers;
  bool get isRunning;
  Duration get currentBeaconInterval;

  Future<void> start({
    required String localDeviceId,
    required String localDeviceName,
    String? localPublicKey,
  });
  Future<void> stop();
  void setBeaconInterval(Duration interval);
  Future<bool> sendDirectMessage(MessageModel message, PeerDevice target);
  Future<int> broadcastMessage(MessageModel message);
  void injectSimulatedPeer(PeerDevice peer);
}

/// Implementasi P2P Hybrid (Wi-Fi Subnet / Hotspot Ad-Hoc + Bluetooth RFCOMM SPP)
/// Berjalan 100% tanpa internet: Menggabungkan throughput tinggi Wi-Fi (Voice PTT & Foto)
/// dan kehandalan darurat Bluetooth Classic RFCOMM.
class WifiLocalConnectivityService implements IConnectivityService {
  static const int defaultPort = 8888;
  static const int discoveryPort = 8889;

  String _localId = '';
  String _localName = '';
  String? _localPublicKey;
  bool _isRunning = false;
  Duration _beaconInterval = const Duration(seconds: 4);

  RawDatagramSocket? _discoverySocket;
  ServerSocket? _tcpServer;
  Timer? _beaconTimer;
  Timer? _cleanupTimer;

  // Bluetooth RFCOMM Components
  StreamSubscription<BluetoothIncomingPacket>? _btPacketSub;
  Timer? _btScanTimer;

  final Map<String, PeerDevice> _peers = {};
  final StreamController<List<PeerDevice>> _peersController =
      StreamController<List<PeerDevice>>.broadcast();
  final StreamController<MessageModel> _messageController =
      StreamController<MessageModel>.broadcast();

  @override
  Stream<List<PeerDevice>> get peersStream => _peersController.stream;

  @override
  Stream<MessageModel> get messageReceivedStream => _messageController.stream;

  @override
  List<PeerDevice> get currentPeers => _peers.values.toList();

  @override
  bool get isRunning => _isRunning;

  @override
  Duration get currentBeaconInterval => _beaconInterval;

  @override
  void setBeaconInterval(Duration interval) {
    _beaconInterval = interval;
    _beaconTimer?.cancel();
    if (_isRunning && _discoverySocket != null) {
      _beaconTimer = Timer.periodic(_beaconInterval, (_) => _sendDiscoveryBeacon());
    }
  }

  @override
  Future<void> start({
    required String localDeviceId,
    required String localDeviceName,
    String? localPublicKey,
  }) async {
    if (_isRunning) return;
    _localId = localDeviceId;
    _localName = localDeviceName;
    _localPublicKey = localPublicKey;
    _isRunning = true;

    try {
      // 1. Jalankan Wi-Fi TCP & UDP Subnet Server
      await _startTcpServer();
      await _startUdpDiscovery();

      // 2. Jalankan Native Bluetooth RFCOMM SPP Server & Listener
      await _startBluetoothRfcommIntegration();

      // 3. Broadcast beacon penemuan berkala sesuai interval adaptif
      _beaconTimer = Timer.periodic(_beaconInterval, (_) => _sendDiscoveryBeacon());

      // 4. Bersihkan perangkat yang tidak lagi mengirim heartbeat (>45 detik)
      _cleanupTimer = Timer.periodic(const Duration(seconds: 10), (_) => _cleanupStalePeers());
    } catch (_) {}
  }

  Future<void> _startTcpServer() async {
    try {
      _tcpServer = await ServerSocket.bind(InternetAddress.anyIPv4, defaultPort, shared: true);
      _tcpServer?.listen(_handleIncomingTcpConnection, onError: (_) {});
    } catch (_) {}
  }

  void _handleIncomingTcpConnection(Socket socket) {
    final buffer = StringBuffer();
    socket.listen(
      (data) {
        buffer.write(utf8.decode(data));
      },
      onDone: () {
        final content = buffer.toString().trim();
        if (content.isNotEmpty) {
          _processIncomingRawPayload(content);
        }
        socket.close();
      },
      onError: (_) => socket.close(),
      cancelOnError: true,
    );
  }

  Future<void> _startUdpDiscovery() async {
    try {
      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
      _discoverySocket?.broadcastEnabled = true;
      _discoverySocket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _discoverySocket?.receive();
          if (datagram != null) {
            _handleDiscoveryPacket(datagram);
          }
        }
      });
    } catch (_) {}
  }

  // --- Bluetooth RFCOMM Integration ---

  Future<void> _startBluetoothRfcommIntegration() async {
    try {
      final isSupported = await NativeHardwareService.instance.isBluetoothSupported();
      if (!isSupported) return;

      // Nyalakan SPP Server di background
      await NativeHardwareService.instance.startBluetoothRfcommServer();

      // Dengarkan paket masuk dari Bluetooth RFCOMM
      _btPacketSub?.cancel();
      _btPacketSub = NativeHardwareService.instance.onBluetoothPacketReceived
          .listen(_handleIncomingBluetoothPacket);

      // Sinkronisasi daftar perangkat Bluetooth yang sudah dipasangkan (Bonded)
      await _syncBondedBluetoothDevices();
      _btScanTimer?.cancel();
      _btScanTimer = Timer.periodic(const Duration(seconds: 15), (_) => _syncBondedBluetoothDevices());
    } catch (_) {}
  }

  Future<void> _syncBondedBluetoothDevices() async {
    if (!_isRunning) return;
    try {
      final bonded = await NativeHardwareService.instance.getBondedBluetoothDevices();
      bool changed = false;

      for (final dev in bonded) {
        final btKey = 'BT_${dev.address.replaceAll(":", "")}';
        // Hanya tambahkan jika belum terhubung via Wi-Fi berkecepatan tinggi
        if (!_peers.containsKey(btKey) && !_peers.values.any((p) => p.deviceName == dev.name)) {
          _peers[btKey] = PeerDevice(
            deviceId: btKey,
            deviceName: '${dev.name} (BT)',
            address: dev.address,
            port: 0,
            connectionType: ConnectionType.bluetoothLe,
            rssi: -65,
            lastSeen: DateTime.now(),
          );
          changed = true;
        }
      }

      if (changed) {
        _peersController.add(_peers.values.toList());
      }
    } catch (_) {}
  }

  void _handleIncomingBluetoothPacket(BluetoothIncomingPacket packet) {
    _processIncomingRawPayload(packet.rawData, fallbackSenderName: packet.senderName, fallbackAddress: packet.senderAddress);
  }

  // --- Pemrosesan Pesan & Beacon Universal ---

  void _processIncomingRawPayload(String rawPayload, {String? fallbackSenderName, String? fallbackAddress}) {
    try {
      final jsonMap = json.decode(rawPayload);
      if (jsonMap is Map<String, dynamic>) {
        if (jsonMap.containsKey('type') && jsonMap['type'] == 'ack') {
          final ackMsg = MessageModel(
            messageId: (jsonMap['ack_id'] as String?) ?? 'ACK-${DateTime.now().millisecondsSinceEpoch}',
            senderId: (jsonMap['sender_id'] as String?) ?? '',
            senderName: (jsonMap['sender_name'] as String?) ?? (fallbackSenderName ?? 'Peer'),
            recipientId: jsonMap['recipient_id'] as String?,
            createdAt: DateTime.now(),
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
            messageType: MessageType.ack,
            body: 'ACK_DELIVERED',
            ackForMessageId: jsonMap['target_message_id'] as String?,
            deliveryStatus: DeliveryStatus.delivered,
            deliveredAt: DateTime.now(),
          );
          _messageController.add(ackMsg);
        } else if (jsonMap.containsKey('type') && jsonMap['type'] == 'sinyalnol_beacon') {
          final senderId = jsonMap['id'] as String;
          if (senderId == _localId) return;

          final senderName = (jsonMap['name'] as String?) ?? (fallbackSenderName ?? 'Node SinyalNol');
          final peerPort = (jsonMap['port'] as num?)?.toInt() ?? defaultPort;
          final peerPubKey = jsonMap['pubkey'] as String?;

          if (peerPubKey != null && peerPubKey.isNotEmpty) {
            EncryptionService.instance.registerPeerPublicKey(senderId, peerPubKey);
          }

          final connType = fallbackAddress != null && fallbackAddress.contains(':') && fallbackAddress.length == 17
              ? ConnectionType.bluetoothLe
              : ConnectionType.wifiLocal;

          _peers[senderId] = PeerDevice(
            deviceId: senderId,
            deviceName: senderName,
            address: fallbackAddress ?? '127.0.0.1',
            port: peerPort,
            connectionType: connType,
            rssi: -55,
            lastSeen: DateTime.now(),
            publicKey: peerPubKey,
          );

          _peersController.add(_peers.values.toList());
        } else if (jsonMap.containsKey('message_id')) {
          final message = MessageModel.fromMap(jsonMap);
          _messageController.add(message);
        }
      }
    } catch (_) {}
  }

  void _sendDiscoveryBeacon() {
    if (_discoverySocket == null || !_isRunning) return;
    final beacon = {
      'type': 'sinyalnol_beacon',
      'id': _localId,
      'name': _localName,
      'port': defaultPort,
      'pubkey': _localPublicKey,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    final data = utf8.encode(json.encode(beacon));

    try {
      // 1. Broadcast ke Wi-Fi Subnet lokal
      _discoverySocket?.send(data, InternetAddress('255.255.255.255'), discoveryPort);
    } catch (_) {}
  }

  void _handleDiscoveryPacket(Datagram datagram) {
    try {
      final text = utf8.decode(datagram.data);
      final jsonMap = json.decode(text);

      if (jsonMap is Map<String, dynamic> && jsonMap['type'] == 'sinyalnol_beacon') {
        final senderId = jsonMap['id'] as String;
        if (senderId == _localId) return;

        final senderName = (jsonMap['name'] as String?) ?? 'Perangkat SinyalNol';
        final peerPort = (jsonMap['port'] as num?)?.toInt() ?? defaultPort;
        final senderAddress = datagram.address.address;
        final peerPubKey = jsonMap['pubkey'] as String?;

        if (peerPubKey != null && peerPubKey.isNotEmpty) {
          EncryptionService.instance.registerPeerPublicKey(senderId, peerPubKey);
        }

        _peers[senderId] = PeerDevice(
          deviceId: senderId,
          deviceName: senderName,
          address: senderAddress,
          port: peerPort,
          connectionType: ConnectionType.wifiLocal,
          rssi: -55,
          lastSeen: DateTime.now(),
          publicKey: peerPubKey,
        );

        _peersController.add(_peers.values.toList());
      }
    } catch (_) {}
  }

  void _cleanupStalePeers() {
    final now = DateTime.now();
    bool changed = false;
    _peers.removeWhere((id, peer) {
      // Pertahankan bonded Bluetooth peer lebih lama (90 detik)
      final timeoutSecs = peer.connectionType == ConnectionType.bluetoothLe ? 90 : 40;
      if (now.difference(peer.lastSeen).inSeconds > timeoutSecs) {
        changed = true;
        return true;
      }
      return false;
    });
    if (changed) {
      _peersController.add(_peers.values.toList());
    }
  }

  @override
  Future<bool> sendDirectMessage(MessageModel message, PeerDevice target) async {
    // 1. Jika peer terhubung via Bluetooth RFCOMM
    if (target.connectionType == ConnectionType.bluetoothLe) {
      try {
        final payload = message.toJson();
        return await NativeHardwareService.instance.sendBluetoothRfcommMessage(
          address: target.address,
          message: payload,
        );
      } catch (_) {
        return false;
      }
    }

    // 2. Jika peer terhubung via Wi-Fi TCP Subnet
    try {
      final socket = await Socket.connect(
        target.address,
        target.port,
        timeout: const Duration(seconds: 4),
      );
      final payload = utf8.encode(message.toJson());
      socket.add(payload);
      await socket.flush();
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<int> broadcastMessage(MessageModel message) async {
    int sentCount = 0;
    final activePeers = currentPeers;
    for (final peer in activePeers) {
      final success = await sendDirectMessage(message, peer);
      if (success) sentCount++;
    }
    return sentCount;
  }

  @override
  void injectSimulatedPeer(PeerDevice peer) {
    _peers[peer.deviceId] = peer;
    _peersController.add(_peers.values.toList());
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
    _beaconTimer?.cancel();
    _cleanupTimer?.cancel();
    _btScanTimer?.cancel();
    _btPacketSub?.cancel();

    _discoverySocket?.close();
    await _tcpServer?.close();
    await NativeHardwareService.instance.stopBluetoothRfcommServer();

    _discoverySocket = null;
    _tcpServer = null;
    _peers.clear();
    _peersController.add([]);
  }
}
