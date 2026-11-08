import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../database/local_db.dart';
import '../models/offline_map_pack.dart';

class SearchResultLocation {
  final String name;
  final String displayName;
  final double latitude;
  final double longitude;
  final String type;

  SearchResultLocation({
    required this.name,
    required this.displayName,
    required this.latitude,
    required this.longitude,
    required this.type,
  });

  factory SearchResultLocation.fromJson(Map<String, dynamic> json) {
    return SearchResultLocation(
      name: json['name'] as String? ?? json['display_name'] as String? ?? 'Lokasi',
      displayName: json['display_name'] as String? ?? '',
      latitude: double.tryParse(json['lat']?.toString() ?? '0') ?? 0.0,
      longitude: double.tryParse(json['lon']?.toString() ?? '0') ?? 0.0,
      type: json['type'] as String? ?? json['class'] as String? ?? 'place',
    );
  }
}

class OfflineDownloadProgress {
  final int totalTiles;
  final int downloadedTiles;
  final int failedTiles;
  final double progress; // 0.0 to 1.0
  final String statusMessage;
  final bool isCompleted;
  final bool isCancelled;

  OfflineDownloadProgress({
    required this.totalTiles,
    required this.downloadedTiles,
    required this.failedTiles,
    required this.progress,
    required this.statusMessage,
    this.isCompleted = false,
    this.isCancelled = false,
  });
}

class OfflineMapService {
  static final OfflineMapService instance = OfflineMapService._init();
  OfflineMapService._init();

  static const String sourceGoogleHybrid = 'google_hybrid';
  static const String sourceEsriSat = 'esri_sat';
  static const String sourceGoogleTerrain = 'google_terrain';
  static const String sourceEsriTopo = 'esri_topo';
  static const String sourceCartoDark = 'cartodark';
  static const String sourceOsm = 'osm';
  static const String sourceOpenTopo = 'opentopo';
  static const String sourceCustom = 'custom';

  static const Map<String, String> tileUrls = {
    sourceGoogleHybrid: 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
    sourceEsriSat: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    sourceGoogleTerrain: 'https://mt1.google.com/vt/lyrs=p&x={x}&y={y}&z={z}',
    sourceEsriTopo: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
    sourceCartoDark: 'https://basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}.png',
    sourceOsm: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    sourceOpenTopo: 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
  };

  static const Map<String, String> sourceNames = {
    sourceGoogleHybrid: 'Satelit + Jalan (Google)',
    sourceEsriSat: 'Citra Satelit Resolusi Tinggi (ESRI)',
    sourceGoogleTerrain: 'Topografi & Relief 3D (Google)',
    sourceEsriTopo: 'Topografi & Elevasi (ESRI)',
    sourceCartoDark: 'Taktis Gelap (Night Ops / OLED)',
    sourceOsm: 'OpenStreetMap Standar (Jalan/Kota)',
    sourceOpenTopo: 'Kontur Topografi (OpenTopo)',
  };

  /// 1x1 Transparent PNG bytes untuk fallback offline tanpa ubin rusak
  static final Uint8List kTransparentPng = Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  Directory? _tilesDirectory;

  Future<Directory> get tilesDirectory async {
    if (_tilesDirectory != null) return _tilesDirectory!;
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'offline_tiles'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    _tilesDirectory = dir;
    return dir;
  }

  /// Lokasi file tile di penyimpanan lokal
  Future<File> getTileFile(String source, int z, int x, int y) async {
    final root = await tilesDirectory;
    return File(p.join(root.path, source, '$z', '$x', '$y.png'));
  }

  /// Cek apakah tile sudah tersedia secara offline di lokal
  Future<bool> hasTile(String source, int z, int x, int y) async {
    final file = await getTileFile(source, z, x, y);
    return file.existsSync() && file.lengthSync() > 0;
  }

  /// Konversi derajat Bujur (Longitude) ke koordinat X tile Web Mercator
  int lon2tile(double lon, int z) {
    return ((lon + 180.0) / 360.0 * (1 << z)).floor();
  }

  /// Konversi derajat Lintang (Latitude) ke koordinat Y tile Web Mercator
  int lat2tile(double lat, int z) {
    final latRad = lat * math.pi / 180.0;
    return ((1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) / 2.0 * (1 << z)).floor();
  }

  /// Konversi koordinat X tile kembali ke Longitude (ujung barat)
  double tile2lon(int x, int z) {
    return x / (1 << z) * 360.0 - 180.0;
  }

  /// Konversi koordinat Y tile kembali ke Latitude (ujung utara)
  double tile2lat(int y, int z) {
    final n = math.pi - 2.0 * math.pi * y / (1 << z);
    return 180.0 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  }

  /// Mencari lokasi/tempat (gunung, posko, kota, desa) via API OpenStreetMap Nominatim
  Future<List<SearchResultLocation>> searchLocations(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(cleanQuery)}&format=json&limit=6&addressdetails=1',
      );
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6)
        ..userAgent = 'SinyalNol-TacticalSAR/1.0';
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'SinyalNol-TacticalSAR/1.0');
      request.headers.set('Accept-Language', 'id,en');
      final response = await request.close().timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final List<dynamic> jsonList = json.decode(body) as List<dynamic>;
        return jsonList
            .map((item) => SearchResultLocation.fromJson(item as Map<String, dynamic>))
            .where((loc) => loc.latitude != 0.0 && loc.longitude != 0.0)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Hitung estimasi jumlah tile yang dibutuhkan untuk suatu radius (km) dan rentang zoom
  int estimateTileCount({
    required double centerLat,
    required double centerLon,
    required double radiusKm,
    required int minZoom,
    required int maxZoom,
  }) {
    final latDelta = radiusKm / 111.0;
    final lonDelta = radiusKm / (111.0 * math.cos(centerLat * math.pi / 180.0));

    final minLat = centerLat - latDelta;
    final maxLat = centerLat + latDelta;
    final minLon = centerLon - lonDelta;
    final maxLon = centerLon + lonDelta;

    int total = 0;
    for (int z = minZoom; z <= maxZoom; z++) {
      final minX = lon2tile(minLon, z);
      final maxX = lon2tile(maxLon, z);
      final minY = lat2tile(maxLat, z); // lat terbalik di Y
      final maxY = lat2tile(minLat, z);

      final countX = (maxX - minX + 1).clamp(1, 10000);
      final countY = (maxY - minY + 1).clamp(1, 10000);
      total += (countX * countY);
    }
    return total;
  }

  /// Unduh paket peta offline dengan laporan progres real-time
  Stream<OfflineDownloadProgress> downloadRegion({
    required String packName,
    required double centerLat,
    required double centerLon,
    required double radiusKm,
    required int minZoom,
    required int maxZoom,
    required String tileSource,
    bool Function()? cancelCheck,
  }) async* {
    final latDelta = radiusKm / 111.0;
    final lonDelta = radiusKm / (111.0 * math.cos(centerLat * math.pi / 180.0));

    final minLat = centerLat - latDelta;
    final maxLat = centerLat + latDelta;
    final minLon = centerLon - lonDelta;
    final maxLon = centerLon + lonDelta;

    // Buat daftar tile koordinat (z, x, y)
    final List<List<int>> tileCoords = [];
    for (int z = minZoom; z <= maxZoom; z++) {
      final minX = lon2tile(minLon, z);
      final maxX = lon2tile(maxLon, z);
      final minY = lat2tile(maxLat, z);
      final maxY = lat2tile(minLat, z);

      for (int x = minX; x <= maxX; x++) {
        for (int y = minY; y <= maxY; y++) {
          tileCoords.add([z, x, y]);
        }
      }
    }

    final totalTiles = tileCoords.length;
    int downloadedTiles = 0;
    int failedTiles = 0;
    int totalBytes = 0;

    yield OfflineDownloadProgress(
      totalTiles: totalTiles,
      downloadedTiles: 0,
      failedTiles: 0,
      progress: 0.0,
      statusMessage: 'Menyiapkan unduhan $totalTiles ubin peta...',
    );

    final urlTemplate = tileUrls[tileSource] ?? tileUrls[sourceCartoDark]!;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = 'SinyalNol-TacticalMap/1.0';

    // Download secara terkontrol dengan konkurensi (batch 4 tile)
    const batchSize = 4;
    for (int i = 0; i < tileCoords.length; i += batchSize) {
      if (cancelCheck != null && cancelCheck()) {
        yield OfflineDownloadProgress(
          totalTiles: totalTiles,
          downloadedTiles: downloadedTiles,
          failedTiles: failedTiles,
          progress: downloadedTiles / totalTiles,
          statusMessage: 'Pengunduhan dibatalkan.',
          isCancelled: true,
        );
        client.close(force: true);
        return;
      }

      final batch = tileCoords.sublist(i, math.min(i + batchSize, tileCoords.length));
      await Future.wait(batch.map((coord) async {
        final z = coord[0];
        final x = coord[1];
        final y = coord[2];

        final tileFile = await getTileFile(tileSource, z, x, y);
        if (tileFile.existsSync() && tileFile.lengthSync() > 0) {
          downloadedTiles++;
          totalBytes += tileFile.lengthSync();
          return;
        }

        final tileUrl = urlTemplate
            .replaceAll('{z}', '$z')
            .replaceAll('{x}', '$x')
            .replaceAll('{y}', '$y');

        try {
          final request = await client.getUrl(Uri.parse(tileUrl));
          request.headers.set('User-Agent', 'SinyalNol-Tactical/1.0');
          final response = await request.close().timeout(const Duration(seconds: 6));
          if (response.statusCode == 200) {
            final bytes = await consolidateHttpClientResponseBytes(response);
            if (bytes.isNotEmpty) {
              await tileFile.parent.create(recursive: true);
              await tileFile.writeAsBytes(bytes, flush: true);
              downloadedTiles++;
              totalBytes += bytes.length;
              return;
            }
          }
          failedTiles++;
        } catch (_) {
          failedTiles++;
        }
      }));

      final prog = (downloadedTiles + failedTiles) / totalTiles;
      yield OfflineDownloadProgress(
        totalTiles: totalTiles,
        downloadedTiles: downloadedTiles,
        failedTiles: failedTiles,
        progress: prog.clamp(0.0, 1.0),
        statusMessage: 'Mengunduh: $downloadedTiles / $totalTiles ubin (${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB)',
      );

      // Sedikit jeda agar tidak di-rate-limit server ubin OSM
      await Future.delayed(const Duration(milliseconds: 30));
    }

    client.close();

    // Simpan metadata paket ke database lokal
    final pack = OfflineMapPack(
      id: const Uuid().v4(),
      name: packName,
      centerLat: centerLat,
      centerLon: centerLon,
      radiusKm: radiusKm,
      minZoom: minZoom,
      maxZoom: maxZoom,
      tileCount: downloadedTiles,
      sizeBytes: totalBytes,
      tileSource: tileSource,
      createdAt: DateTime.now(),
    );

    await LocalDatabase.instance.insertOfflinePack(pack);

    yield OfflineDownloadProgress(
      totalTiles: totalTiles,
      downloadedTiles: downloadedTiles,
      failedTiles: failedTiles,
      progress: 1.0,
      statusMessage: 'Selesai! $downloadedTiles ubin (${pack.formattedSize}) tersimpan permanen.',
      isCompleted: true,
    );
  }

  /// Dapatkan ukuran total memori cache peta offline (Bytes)
  Future<int> getTotalCacheSizeBytes() async {
    final root = await tilesDirectory;
    int total = 0;
    if (!root.existsSync()) return 0;
    try {
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          total += entity.lengthSync();
        }
      }
    } catch (_) {}
    return total;
  }

  /// Dapatkan jumlah file ubin tersimpan
  Future<int> getTotalCachedTilesCount() async {
    final root = await tilesDirectory;
    int count = 0;
    if (!root.existsSync()) return 0;
    try {
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is File && entity.path.endsWith('.png')) {
          count++;
        }
      }
    } catch (_) {}
    return count;
  }

  /// Hapus paket peta dari SQLite dan bersihkan file terkait
  Future<void> deletePack(String packId) async {
    await LocalDatabase.instance.deleteOfflinePack(packId);
  }

  /// Hapus seluruh file cache peta di penyimpanan lokal
  Future<void> clearAllTiles() async {
    final root = await tilesDirectory;
    if (root.existsSync()) {
      try {
        await root.delete(recursive: true);
        await root.create(recursive: true);
      } catch (_) {}
    }
  }
}

/// Custom TileProvider untuk flutter_map dengan dukungan offline-first
class TacticalOfflineTileProvider extends TileProvider {
  final String tileSource;
  final OfflineMapService service = OfflineMapService.instance;

  TacticalOfflineTileProvider({
    required this.tileSource,
    super.headers,
  });

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final urlTemplate = options.urlTemplate ??
        OfflineMapService.tileUrls[tileSource] ??
        OfflineMapService.tileUrls[OfflineMapService.sourceCartoDark]!;

    final url = urlTemplate
        .replaceAll('{z}', '${coordinates.z}')
        .replaceAll('{x}', '${coordinates.x}')
        .replaceAll('{y}', '${coordinates.y}');

    return TacticalTileImageProvider(
      source: tileSource,
      z: coordinates.z,
      x: coordinates.x,
      y: coordinates.y,
      url: url,
      headers: headers,
    );
  }
}

/// ImageProvider yang memprioritaskan disk lokal sebelum menyentuh jaringan.
/// Jika offline dan ubin belum tersimpan, memuat gambar transparan sehingga
/// tidak ada error merah / crash di layar operasi.
class TacticalTileImageProvider extends ImageProvider<TacticalTileImageProvider> {
  final String source;
  final int z;
  final int x;
  final int y;
  final String url;
  final Map<String, String> headers;

  TacticalTileImageProvider({
    required this.source,
    required this.z,
    required this.x,
    required this.y,
    required this.url,
    required this.headers,
  });

  @override
  Future<TacticalTileImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<TacticalTileImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(TacticalTileImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(decode),
      scale: 1.0,
      informationCollector: () => [
        DiagnosticsProperty('url', url),
        DiagnosticsProperty('source', source),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(ImageDecoderCallback decode) async {
    final file = await OfflineMapService.instance.getTileFile(source, z, x, y);

    // 1. Prioritas Utama: Baca dari penyimpanan lokal jika sudah ada
    if (file.existsSync() && file.lengthSync() > 0) {
      try {
        final bytes = await file.readAsBytes();
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        return await decode(buffer);
      } catch (_) {}
    }

    // 2. Jika belum ada di disk, coba ambil via internet (auto-caching)
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4)
        ..userAgent = 'SinyalNol-Tactical/1.0';
      final request = await client.getUrl(Uri.parse(url));
      headers.forEach((k, v) => request.headers.set(k, v));
      final response = await request.close().timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final bytes = await consolidateHttpClientResponseBytes(response);
        if (bytes.isNotEmpty) {
          // Simpan ke disk secara asinkron untuk penggunaan offline selanjutnya
          unawaited(() async {
            try {
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes, flush: true);
            } catch (_) {}
          }());

          final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
          return await decode(buffer);
        }
      }
    } catch (_) {
      // Gagal koneksi (mode pesawat / tanpa internet di blank spot)
    }

    // 3. Fallback Taktis: Jika offline & file belum terunduh, kembalikan ubin transparan
    // sehingga warna latar taktis radar grid tetap terlihat tanpa error layar
    final buffer = await ui.ImmutableBuffer.fromUint8List(OfflineMapService.kTransparentPng);
    return await decode(buffer);
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is TacticalTileImageProvider &&
        other.source == source &&
        other.z == z &&
        other.x == x &&
        other.y == y;
  }

  @override
  int get hashCode => Object.hash(source, z, x, y);
}

