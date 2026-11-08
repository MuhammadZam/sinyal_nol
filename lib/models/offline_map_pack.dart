class OfflineMapPack {
  final String id;
  final String name;
  final double centerLat;
  final double centerLon;
  final double radiusKm;
  final int minZoom;
  final int maxZoom;
  final int tileCount;
  final int sizeBytes;
  final String tileSource; // 'osm', 'opentopo', 'cartodark'
  final DateTime createdAt;

  OfflineMapPack({
    required this.id,
    required this.name,
    required this.centerLat,
    required this.centerLon,
    required this.radiusKm,
    required this.minZoom,
    required this.maxZoom,
    required this.tileCount,
    required this.sizeBytes,
    required this.tileSource,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'center_lat': centerLat,
      'center_lon': centerLon,
      'radius_km': radiusKm,
      'min_zoom': minZoom,
      'max_zoom': maxZoom,
      'tile_count': tileCount,
      'size_bytes': sizeBytes,
      'tile_source': tileSource,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory OfflineMapPack.fromMap(Map<String, dynamic> map) {
    return OfflineMapPack(
      id: map['id'] as String,
      name: map['name'] as String,
      centerLat: (map['center_lat'] as num).toDouble(),
      centerLon: (map['center_lon'] as num).toDouble(),
      radiusKm: (map['radius_km'] as num).toDouble(),
      minZoom: map['min_zoom'] as int,
      maxZoom: map['max_zoom'] as int,
      tileCount: map['tile_count'] as int,
      sizeBytes: map['size_bytes'] as int,
      tileSource: map['tile_source'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  String get formattedSize {
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get sourceLabel {
    switch (tileSource) {
      case 'google_hybrid':
        return 'Satelit + Jalan (Google)';
      case 'esri_sat':
        return 'Citra Satelit Global (ESRI)';
      case 'google_terrain':
        return 'Topografi & Relief 3D (Google)';
      case 'esri_topo':
        return 'Topografi Resmi (ESRI)';
      case 'opentopo':
        return 'Topografi Kontur (OpenTopo)';
      case 'cartodark':
        return 'Taktis Gelap (Night Ops)';
      case 'custom':
        return 'Server Tile Kustom';
      case 'osm':
      default:
        return 'OpenStreetMap Standar';
    }
  }
}

