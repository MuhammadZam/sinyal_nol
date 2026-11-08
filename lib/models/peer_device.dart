enum ConnectionType {
  wifiLocal, // Local Wi-Fi subnet / Hotspot Ad-Hoc
  wifiDirect, // Wi-Fi Direct P2P
  bluetoothLe, // Bluetooth Low Energy
  simulated, // Simulator / Mock untuk uji coba
}

class PeerDevice {
  final String deviceId;
  final String deviceName;
  final String address; // IP Address atau Bluetooth MAC/UUID
  final int port;
  final ConnectionType connectionType;
  final int rssi; // Signal strength dBm
  final DateTime lastSeen;
  final bool isPaired;
  final double? estimatedDistanceMeters;
  final String? publicKey; // Kunci publik X25519 untuk E2EE
  final bool isVerified; // Terverifikasi via QR fisik

  PeerDevice({
    required this.deviceId,
    required this.deviceName,
    required this.address,
    this.port = 8888,
    required this.connectionType,
    this.rssi = -60,
    required this.lastSeen,
    this.isPaired = false,
    this.estimatedDistanceMeters,
    this.publicKey,
    this.isVerified = false,
  });

  bool get isOnline {
    final diff = DateTime.now().difference(lastSeen).inSeconds;
    return diff < 45; // Aktif jika heartbeat dalam 45 detik terakhir
  }

  PeerDevice copyWith({
    String? deviceId,
    String? deviceName,
    String? address,
    int? port,
    ConnectionType? connectionType,
    int? rssi,
    DateTime? lastSeen,
    bool? isPaired,
    double? estimatedDistanceMeters,
    String? publicKey,
    bool? isVerified,
  }) {
    return PeerDevice(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      address: address ?? this.address,
      port: port ?? this.port,
      connectionType: connectionType ?? this.connectionType,
      rssi: rssi ?? this.rssi,
      lastSeen: lastSeen ?? this.lastSeen,
      isPaired: isPaired ?? this.isPaired,
      estimatedDistanceMeters: estimatedDistanceMeters ?? this.estimatedDistanceMeters,
      publicKey: publicKey ?? this.publicKey,
      isVerified: isVerified ?? this.isVerified,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'device_id': deviceId,
      'device_name': deviceName,
      'address': address,
      'port': port,
      'connection_type': connectionType.name,
      'rssi': rssi,
      'last_seen': lastSeen.toIso8601String(),
      'public_key': publicKey,
      'is_verified': isVerified ? 1 : 0,
    };
  }

  factory PeerDevice.fromMap(Map<String, dynamic> map) {
    return PeerDevice(
      deviceId: map['device_id'] as String,
      deviceName: map['device_name'] as String,
      address: map['address'] as String,
      port: (map['port'] as num?)?.toInt() ?? 8888,
      connectionType: ConnectionType.values.firstWhere(
        (e) => e.name == map['connection_type'],
        orElse: () => ConnectionType.wifiLocal,
      ),
      rssi: (map['rssi'] as num?)?.toInt() ?? -60,
      lastSeen: DateTime.parse(map['last_seen'] as String),
      publicKey: map['public_key'] as String?,
      isVerified: map['is_verified'] == 1 || map['is_verified'] == true,
    );
  }
}
