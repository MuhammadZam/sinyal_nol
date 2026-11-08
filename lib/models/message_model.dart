import 'dart:convert';

/// Status pengiriman pesan yang jujur dan tidak menyesatkan (sesuai spesifikasi SinyalNol)
enum DeliveryStatus {
  queued, // Tersimpan di database lokal, menunggu radio/koneksi tersedia
  sending, // Sedang dalam proses transmisi
  relayed, // Terkirim ke perangkat perantara/tetangga (belum tentu sampai ke penerima akhir)
  delivered, // Diterima oleh perangkat tujuan akhir (dibuktikan dengan tanda terima/ACK)
  failed, // Gagal terkirim atau masa berlaku (TTL) habis
}

/// Tipe pesan
enum MessageType {
  text,
  sos,
  location,
  ack, // Konfirmasi tanda terima dua arah (Two-Way Delivery Receipt)
  voice, // Walkie-Talkie Asinkron PTT (Voice Note Ultra-Ringan)
}

class MessageModel {
  final String messageId;
  final String senderId;
  final String senderName;
  final String? recipientId; // null atau 'BROADCAST' untuk pesan publik/grup
  final DateTime createdAt;
  final DateTime expiresAt; // Time-to-Live (TTL)
  final MessageType messageType;
  final String body;
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final int hopCount;
  final int maxHops;
  DeliveryStatus deliveryStatus;
  final String? relayedBy; // ID perangkat yang meneruskan
  final String? ackForMessageId; // ID pesan yang dikonfirmasi oleh paket ACK ini
  final DateTime? deliveredAt; // Waktu pasti paket ACK diterima
  final String? integrityHash; // SHA-256 Hash untuk mendeteksi manipulasi payload di jalur relay
  final bool isEncrypted; // Indikator apakah payload pesan diamankan dengan E2EE

  MessageModel({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    this.recipientId,
    required this.createdAt,
    required this.expiresAt,
    this.messageType = MessageType.text,
    required this.body,
    this.latitude,
    this.longitude,
    this.altitude,
    this.hopCount = 0,
    this.maxHops = 3,
    this.deliveryStatus = DeliveryStatus.queued,
    this.relayedBy,
    this.ackForMessageId,
    this.deliveredAt,
    this.integrityHash,
    this.isEncrypted = false,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isBroadcast => recipientId == null || recipientId == 'BROADCAST';
  bool get hasLocation => latitude != null && longitude != null;
  bool get isAck => messageType == MessageType.ack;
  bool get isVoice => messageType == MessageType.voice;

  int get voiceDurationSeconds {
    if (!isVoice) return 0;
    try {
      final decoded = json.decode(body);
      if (decoded is Map) {
        return (decoded['duration_seconds'] as num?)?.toInt() ?? 5;
      }
    } catch (_) {}
    return 5;
  }

  String get voiceBase64Data {
    if (!isVoice) return '';
    try {
      final decoded = json.decode(body);
      if (decoded is Map && decoded['voice_base64'] != null) {
        return decoded['voice_base64'] as String;
      }
    } catch (_) {}
    return body;
  }

  Map<String, dynamic> toMap() {
    return {
      'message_id': messageId,
      'sender_id': senderId,
      'sender_name': senderName,
      'recipient_id': recipientId ?? 'BROADCAST',
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'message_type': messageType.name,
      'body': body,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'hop_count': hopCount,
      'max_hops': maxHops,
      'delivery_status': deliveryStatus.name,
      'relayed_by': relayedBy,
      'ack_for_message_id': ackForMessageId,
      'delivered_at': deliveredAt?.toIso8601String(),
      'integrity_hash': integrityHash,
      'is_encrypted': isEncrypted ? 1 : 0,
    };
  }

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      messageId: map['message_id'] as String,
      senderId: map['sender_id'] as String,
      senderName: (map['sender_name'] as String?) ?? 'Anonim',
      recipientId: map['recipient_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      expiresAt: DateTime.parse(map['expires_at'] as String),
      messageType: MessageType.values.firstWhere(
        (e) => e.name == map['message_type'],
        orElse: () => MessageType.text,
      ),
      body: map['body'] as String? ?? '',
      latitude: map['latitude'] != null ? (map['latitude'] as num).toDouble() : null,
      longitude: map['longitude'] != null ? (map['longitude'] as num).toDouble() : null,
      altitude: map['altitude'] != null ? (map['altitude'] as num).toDouble() : null,
      hopCount: (map['hop_count'] as num?)?.toInt() ?? 0,
      maxHops: (map['max_hops'] as num?)?.toInt() ?? 3,
      deliveryStatus: DeliveryStatus.values.firstWhere(
        (e) => e.name == map['delivery_status'],
        orElse: () => DeliveryStatus.queued,
      ),
      relayedBy: map['relayed_by'] as String?,
      ackForMessageId: map['ack_for_message_id'] as String?,
      deliveredAt: map['delivered_at'] != null ? DateTime.tryParse(map['delivered_at'] as String) : null,
      integrityHash: map['integrity_hash'] as String?,
      isEncrypted: map['is_encrypted'] == 1 || map['is_encrypted'] == true,
    );
  }

  String toJson() => json.encode(toMap());

  factory MessageModel.fromJson(String source) =>
      MessageModel.fromMap(json.decode(source) as Map<String, dynamic>);

  MessageModel copyWith({
    String? messageId,
    String? senderId,
    String? senderName,
    String? recipientId,
    DateTime? createdAt,
    DateTime? expiresAt,
    MessageType? messageType,
    String? body,
    double? latitude,
    double? longitude,
    double? altitude,
    int? hopCount,
    int? maxHops,
    DeliveryStatus? deliveryStatus,
    String? relayedBy,
    String? ackForMessageId,
    DateTime? deliveredAt,
    String? integrityHash,
    bool? isEncrypted,
  }) {
    return MessageModel(
      messageId: messageId ?? this.messageId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      recipientId: recipientId ?? this.recipientId,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      messageType: messageType ?? this.messageType,
      body: body ?? this.body,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      hopCount: hopCount ?? this.hopCount,
      maxHops: maxHops ?? this.maxHops,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      relayedBy: relayedBy ?? this.relayedBy,
      ackForMessageId: ackForMessageId ?? this.ackForMessageId,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      integrityHash: integrityHash ?? this.integrityHash,
      isEncrypted: isEncrypted ?? this.isEncrypted,
    );
  }
}
