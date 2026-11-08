class BreadcrumbPoint {
  final int? id;
  final double latitude;
  final double longitude;
  final double? altitude;
  final DateTime timestamp;

  BreadcrumbPoint({
    this.id,
    required this.latitude,
    required this.longitude,
    this.altitude,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'timestamp': timestamp.toIso8601String(),
    };
    if (id != null) map['id'] = id;
    return map;
  }

  factory BreadcrumbPoint.fromMap(Map<String, dynamic> map) {
    return BreadcrumbPoint(
      id: map['id'] as int?,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      altitude: (map['altitude'] as num?)?.toDouble(),
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

