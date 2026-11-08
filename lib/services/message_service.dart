import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../models/message_model.dart';
import '../database/local_db.dart';
import 'connectivity_service.dart';
import 'encryption_service.dart';
import 'lora_bridge_service.dart';

class MessageService {
  final LocalDatabase _db = LocalDatabase.instance;
  final IConnectivityService _connectivity;
  final EncryptionService _encryption = EncryptionService.instance;
  final String localDeviceId;
  final String localDeviceName;

  bool isRelayEnabled = true;
  int defaultTtlHours = 24;
  int maxHopsLimit = 3;

  StreamSubscription? _incomingSub;
  StreamSubscription? _peersSub;

  final Set<String> _processedPacketIds = {};

  final StreamController<MessageModel> _onNewMessageController =
      StreamController<MessageModel>.broadcast();

  Stream<MessageModel> get onNewMessage => _onNewMessageController.stream;

  MessageService({
    required IConnectivityService connectivity,
    required this.localDeviceId,
    required this.localDeviceName,
  }) : _connectivity = connectivity;

  void initialize() {
    _incomingSub?.cancel();
    _peersSub?.cancel();

    // Dengarkan pesan masuk dari lapisan konektivitas
    _incomingSub = _connectivity.messageReceivedStream.listen(_handleIncomingMessage);

    // Ketika perangkat tetangga terdeteksi, coba kirim antrean pesan
    _peersSub = _connectivity.peersStream.listen((peers) {
      if (peers.isNotEmpty) {
        processMessageQueue();
      }
    });
  }

  /// Membuat dan menyimpan pesan baru ke database lokal (Offline-First)
  Future<MessageModel> createAndSendMessage({
    String? recipientId,
    required String body,
    MessageType type = MessageType.text,
    double? latitude,
    double? longitude,
    double? altitude,
  }) async {
    const uuid = Uuid();
    final now = DateTime.now();
    final expiresAt = now.add(Duration(hours: defaultTtlHours));
    final msgId = uuid.v4();

    // Cek apakah pesan direct dapat diamankan dengan E2EE
    final bool canEncrypt = recipientId != null &&
        recipientId != 'BROADCAST' &&
        _encryption.hasPeerKey(recipientId);

    // Hitung Checksum SHA-256 untuk mendeteksi integritas data di jalur relay
    final hashSource = '$localDeviceId:${recipientId ?? "BROADCAST"}:$body:${now.millisecondsSinceEpoch}';
    final integrityHash = sha256.convert(utf8.encode(hashSource)).toString().substring(0, 16);

    // Pesan lokal yang disimpan di SQLite (plaintext agar pengirim dapat membaca riwayatnya sendiri)
    final localMessage = MessageModel(
      messageId: msgId,
      senderId: localDeviceId,
      senderName: localDeviceName,
      recipientId: recipientId,
      createdAt: now,
      expiresAt: expiresAt,
      messageType: type,
      body: body,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      hopCount: 0,
      maxHops: maxHopsLimit,
      deliveryStatus: DeliveryStatus.queued,
      integrityHash: integrityHash,
      isEncrypted: canEncrypt,
    );

    // Tandai ID ini sebagai sudah diproses di memori
    _processedPacketIds.add(msgId);

    // Simpan ke SQLite lokal terlebih dahulu
    await _db.insertMessage(localMessage);
    _onNewMessageController.add(localMessage);

    // Siapkan paket radio: Jika E2EE aktif, enkripsi payload body sebelum ditransmisikan
    MessageModel wireMessage = localMessage;
    if (canEncrypt) {
      final ciphertext = await _encryption.encryptForPeer(peerId: recipientId, plaintext: body);
      wireMessage = localMessage.copyWith(body: ciphertext, isEncrypted: true);
    }

    // Coba kirim segera jika radio aktif dan peer tersedia
    await _tryDispatchMessage(wireMessage);

    return localMessage;
  }

  /// Penanganan pesan masuk dari perangkat lain
  Future<void> _handleIncomingMessage(MessageModel incoming) async {
    // 1. Cek masa berlaku (TTL)
    if (incoming.isExpired) {
      return;
    }

    // 2. Deteksi apakah ini paket konfirmasi tanda terima (ACK)
    if (incoming.isAck || incoming.ackForMessageId != null) {
      final ackTargetId = incoming.ackForMessageId ?? incoming.body;
      if (ackTargetId.isNotEmpty) {
        final confirmed = await _db.confirmDeliveryByAck(ackTargetId, incoming.createdAt);
        if (confirmed) {
          // Emit update agar UI mengubah centang pesan menjadi 'delivered'
          _onNewMessageController.add(incoming);
        }
      }

      // Jika ACK ini bukan untuk diri sendiri dan relay aktif, teruskan ACK ke node tetangga
      final isAckForMe = incoming.recipientId == localDeviceId;
      if (!isAckForMe && isRelayEnabled && incoming.hopCount < incoming.maxHops) {
        if (!_processedPacketIds.contains(incoming.messageId)) {
          _processedPacketIds.add(incoming.messageId);
          final relayedAck = incoming.copyWith(
            hopCount: incoming.hopCount + 1,
            relayedBy: localDeviceId,
          );
          await _connectivity.broadcastMessage(relayedAck);
        }
      }
      return;
    }

    // 3. Deteksi duplikasi paket di memori & SQLite
    if (_processedPacketIds.contains(incoming.messageId)) {
      return;
    }
    final exists = await _db.messageExists(incoming.messageId);
    if (exists) {
      _processedPacketIds.add(incoming.messageId);
      return; // Abaikan pesan duplikat
    }

    // Batasi ukuran cache memori maksimal 500 ID
    if (_processedPacketIds.length > 500) {
      _processedPacketIds.clear();
    }
    _processedPacketIds.add(incoming.messageId);

    // 4. Dekripsi E2EE jika pesan ini ditujukan untuk diri saya
    final isForMe = incoming.recipientId == null ||
        incoming.recipientId == 'BROADCAST' ||
        incoming.recipientId == localDeviceId;

    String displayBody = incoming.body;
    bool isEncrypted = incoming.isEncrypted;

    if (isForMe && incoming.isEncrypted) {
      displayBody = await _encryption.decryptFromPeer(
        senderPeerId: incoming.senderId,
        payload: incoming.body,
      );
    }

    // Simpan pesan yang baru diterima ke database lokal
    final savedMessage = incoming.copyWith(
      body: displayBody,
      isEncrypted: isEncrypted,
      deliveryStatus: isForMe ? DeliveryStatus.delivered : DeliveryStatus.relayed,
    );
    await _db.insertMessage(savedMessage);
    _onNewMessageController.add(savedMessage);

    // 5. Jika pesan ini khusus ditujukan untuk saya (Direct Message), kirimkan ACK balik ke pengirim
    if (isForMe && !incoming.isBroadcast && incoming.senderId.isNotEmpty) {
      _sendAckResponse(incoming);
    }

    // 6. Logika Smart Relay (Penerusan Zero-Knowledge jika bukan untuk diri sendiri dan relay aktif)
    // Relay node HANYA meneruskan pesan asli (termasuk ciphertext yang tidak bisa dibaca relay)
    if (!isForMe && isRelayEnabled && incoming.hopCount < incoming.maxHops) {
      final relayedMessage = incoming.copyWith(
        hopCount: incoming.hopCount + 1,
        relayedBy: localDeviceId,
      );

      // Teruskan ke perangkat tetangga lain
      await _connectivity.broadcastMessage(relayedMessage);
    }
  }

  /// Memancarkan paket ACK konfirmasi penerimaan balik ke pengirim
  Future<void> _sendAckResponse(MessageModel originalMessage) async {
    const uuid = Uuid();
    final now = DateTime.now();
    final ackMessage = MessageModel(
      messageId: 'ACK-${uuid.v4().substring(0, 8)}',
      senderId: localDeviceId,
      senderName: localDeviceName,
      recipientId: originalMessage.senderId,
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 4)),
      messageType: MessageType.ack,
      body: originalMessage.messageId,
      ackForMessageId: originalMessage.messageId,
      hopCount: 0,
      maxHops: maxHopsLimit,
      deliveryStatus: DeliveryStatus.delivered,
      deliveredAt: now,
    );

    // Coba kirim langsung ke peer jika terdaftar di radio
    await _tryDispatchMessage(ackMessage);
  }

  /// Coba kirim pesan melalui koneksi yang tersedia
  Future<void> _tryDispatchMessage(MessageModel message) async {
    final peers = _connectivity.currentPeers;
    if (peers.isEmpty) return;

    if (message.isBroadcast) {
      final sentCount = await _connectivity.broadcastMessage(message);
      if (sentCount > 0) {
        await _db.updateDeliveryStatus(message.messageId, DeliveryStatus.relayed);
        message.deliveryStatus = DeliveryStatus.relayed;
        _onNewMessageController.add(message);
      }
    } else {
      // Direct message
      final targetPeer = peers.where((p) => p.deviceId == message.recipientId).firstOrNull;
      if (targetPeer != null) {
        final success = await _connectivity.sendDirectMessage(message, targetPeer);
        if (success) {
          await _db.updateDeliveryStatus(message.messageId, DeliveryStatus.delivered);
          message.deliveryStatus = DeliveryStatus.delivered;
          _onNewMessageController.add(message);
        }
      } else if (isRelayEnabled) {
        // Jika target belum kelihatan langsung, kirim ke perangkat tetangga (relayed)
        final sentCount = await _connectivity.broadcastMessage(message);
        if (sentCount > 0) {
          await _db.updateDeliveryStatus(message.messageId, DeliveryStatus.relayed);
          message.deliveryStatus = DeliveryStatus.relayed;
          _onNewMessageController.add(message);
        }
      }
    }
    // Transmisikan juga via LoRa Transceiver jika terhubung (Jangkauan 5 - 20 KM)
    if (LoraBridgeService.instance.isConnected) {
      await LoraBridgeService.instance.transmitLoraFrame(message);
    }
  }

  /// Memproses antrean pesan yang masih berstatus 'queued' serta sinkronisasi Data Mule
  Future<void> processMessageQueue() async {
    final queued = await _db.getQueuedMessages();
    for (final msg in queued) {
      if (msg.isExpired) {
        await _db.updateDeliveryStatus(msg.messageId, DeliveryStatus.failed);
      } else {
        await _tryDispatchMessage(msg);
      }
    }

    // Delay-Tolerant Networking (DTN) Data Mule:
    // Sinkronisasi pesan broadcast aktif ke node yang baru ditemui
    try {
      final activeBroadcasts = await _db.getBroadcastMessages();
      for (final bMsg in activeBroadcasts.take(10)) {
        if (!bMsg.isExpired) {
          await _connectivity.broadcastMessage(bMsg);
        }
      }
    } catch (_) {}
  }

  void dispose() {
    _incomingSub?.cancel();
    _peersSub?.cancel();
    _onNewMessageController.close();
  }
}
