import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/message_model.dart';
import '../../models/peer_device.dart';
import '../../models/sar_waypoint.dart';
import '../../providers/app_provider.dart';
import '../../services/offline_map_service.dart';
import '../../utils/tactical_coords.dart';
import '../theme/app_theme.dart';
import '../widgets/offline_map_download_dialog.dart';

enum SearchPatternType { none, expandingSquare, sectorSearch, parallelSweep }

enum MapDisplayMode {
  darkTactical,   // CartoDB Dark Matter (Night Ops / OLED)
  googleHybrid,   // Satelit + Label Jalan (Google)
  esriSatellite,  // Citra Satelit Resolusi Tinggi (ESRI)
  googleTerrain,  // Topografi & Relief 3D (Google)
  esriTopo,       // Topografi Resmi (ESRI)
  openTopo,       // OpenTopoMap Relief & Kontur SAR
  osmStandard,    // OpenStreetMap Standar
  radarGrid,      // Kanvas Matematis Taktis Murni (0 KB)
}

class TacticalMapScreen extends StatefulWidget {
  const TacticalMapScreen({super.key});

  @override
  State<TacticalMapScreen> createState() => _TacticalMapScreenState();
}

class _TacticalMapScreenState extends State<TacticalMapScreen> {
  final MapController _mapController = MapController();
  MapDisplayMode _displayMode = MapDisplayMode.darkTactical;

  // Zoom & Pan for pure radar grid fallback
  double _radarScale = 0.5;
  Offset _radarPanOffset = Offset.zero;

  bool _showUtm = false;
  SearchPatternType _activePattern = SearchPatternType.none;
  final double _patternSweepWidthMeters = 60.0;

  // Measuring Tool (Pengukur Jarak & Azimuth)
  bool _isMeasuring = false;
  LatLng? _measurePointA;
  LatLng? _measurePointB;

  // Selected item for Target Lock HUD
  SarWaypoint? _selectedWaypoint;
  PeerDevice? _selectedPeer;
  MessageModel? _selectedSos;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = Provider.of<AppProvider>(context, listen: false);
      if (p.lastLocation == null) {
        p.fetchCurrentGpsLocation();
      }
    });
  }

  void _recenter(double lat, double lon) {
    if (_displayMode == MapDisplayMode.radarGrid) {
      setState(() {
        _radarPanOffset = Offset.zero;
        _radarScale = 0.5;
      });
    } else {
      _mapController.move(LatLng(lat, lon), 15.0);
    }
  }

  void _showAddWaypointDialog(BuildContext context, AppProvider provider, {double? customLat, double? customLon}) {
    final nameCtrl = TextEditingController(text: 'Titik-Taktis-${provider.waypoints.length + 1}');
    final notesCtrl = TextEditingController();
    WaypointCategory category = WaypointCategory.camp;

    final selfLat = customLat ?? provider.lastLocation?.latitude ?? -7.2504;
    final selfLon = customLon ?? provider.lastLocation?.longitude ?? 112.7688;

    final latCtrl = TextEditingController(text: selfLat.toStringAsFixed(6));
    final lonCtrl = TextEditingController(text: selfLon.toStringAsFixed(6));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Row(
            children: [
              Icon(Icons.add_location_alt_rounded, color: AppTheme.primary, size: 22),
              SizedBox(width: 8),
              Text('Tambah Waypoint SAR', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Waypoint disimpan permanen di memori HP (SQLite) dan dapat disiarkan langsung ke jaringan radio mesh rekan.',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Titik / Sasaran'),
                ),
                const SizedBox(height: 12),
                const Text('KATEGORI WAYPOINT:', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                DropdownButtonFormField<WaypointCategory>(
                  initialValue: category,
                  dropdownColor: AppTheme.surfaceVariant,
                  decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                  items: WaypointCategory.values.map((cat) {
                    final dummyWp = SarWaypoint(
                      id: '',
                      name: '',
                      category: cat,
                      latitude: 0,
                      longitude: 0,
                      createdAt: DateTime.now(),
                      createdBy: '',
                    );
                    return DropdownMenuItem(
                      value: cat,
                      child: Row(
                        children: [
                          Icon(dummyWp.categoryIcon, color: dummyWp.categoryColor, size: 18),
                          const SizedBox(width: 8),
                          Text(dummyWp.categoryLabel, style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setDlgState(() => category = val);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: latCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: const InputDecoration(labelText: 'Latitude'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: lonCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: const InputDecoration(labelText: 'Longitude'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'Catatan Lapangan (Opsional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final lat = double.tryParse(latCtrl.text.trim()) ?? selfLat;
                final lon = double.tryParse(lonCtrl.text.trim()) ?? selfLon;
                if (name.isEmpty) return;

                final newWp = SarWaypoint(
                  id: const Uuid().v4(),
                  name: name,
                  category: category,
                  latitude: lat,
                  longitude: lon,
                  altitude: provider.lastLocation?.altitude,
                  createdAt: DateTime.now(),
                  createdBy: provider.localDeviceId,
                  notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                );

                await provider.addWaypoint(newWp);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Simpan Waypoint'),
            ),
          ],
        ),
      ),
    );
  }

  void _showWaypointListSheet(BuildContext context, AppProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollCtrl) {
          final waypoints = provider.waypoints;
          return Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'DAFTAR WAYPOINT SAR (${waypoints.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: AppTheme.primary, size: 20),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showAddWaypointDialog(context, provider);
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppTheme.border),
              Expanded(
                child: waypoints.isEmpty
                    ? const Center(
                        child: Text(
                          'Belum ada waypoint taktis tersimpan.\nTekan + atau sentuh lama pada peta.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollCtrl,
                        itemCount: waypoints.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.border),
                        itemBuilder: (ctx, i) {
                          final wp = waypoints[i];
                          final selfLoc = provider.lastLocation;
                          String distStr = '-';
                          String bearingStr = '-';
                          if (selfLoc != null) {
                            final d = TacticalCoords.calculateDistanceMeters(
                              selfLoc.latitude,
                              selfLoc.longitude,
                              wp.latitude,
                              wp.longitude,
                            );
                            final b = TacticalCoords.calculateBearing(
                              selfLoc.latitude,
                              selfLoc.longitude,
                              wp.latitude,
                              wp.longitude,
                            );
                            distStr = TacticalCoords.formatDistance(d);
                            bearingStr = TacticalCoords.bearingToCardinal(b);
                          }

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: wp.categoryColor.withValues(alpha: 0.15),
                              child: Icon(wp.categoryIcon, color: wp.categoryColor, size: 20),
                            ),
                            title: Text(wp.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: Text(
                              '${wp.categoryLabel} • $distStr ($bearingStr)\n${wp.latitude.toStringAsFixed(5)}, ${wp.longitude.toStringAsFixed(5)}',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppTheme.textSecondary, size: 18),
                              onPressed: () async {
                                await provider.removeWaypoint(wp.id);
                              },
                            ),
                            onTap: () {
                              setState(() {
                                _selectedWaypoint = wp;
                                _selectedPeer = null;
                                _selectedSos = null;
                              });
                              _mapController.move(LatLng(wp.latitude, wp.longitude), 16.0);
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSearchLocationSheet(BuildContext context) {
    final searchCtrl = TextEditingController();
    List<SearchResultLocation> results = [];
    bool isSearching = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.travel_explore_rounded, color: AppTheme.primary, size: 20),
                  SizedBox(width: 8),
                  Text('Cari Lokasi / Sasaran Operasi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (q) async {
                        if (q.trim().isEmpty) return;
                        setSheetState(() => isSearching = true);
                        final res = await OfflineMapService.instance.searchLocations(q);
                        setSheetState(() {
                          results = res;
                          isSearching = false;
                        });
                      },
                      decoration: const InputDecoration(
                        hintText: 'Ketik nama gunung, kota, posko, atau desa...',
                        prefixIcon: Icon(Icons.search, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: isSearching ? null : () async {
                      if (searchCtrl.text.trim().isEmpty) return;
                      setSheetState(() => isSearching = true);
                      final res = await OfflineMapService.instance.searchLocations(searchCtrl.text);
                      setSheetState(() {
                        results = res;
                        isSearching = false;
                      });
                    },
                    child: isSearching
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Cari'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (results.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.border),
                    itemBuilder: (_, i) {
                      final item = results[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.location_on, color: AppTheme.accent, size: 18),
                        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        subtitle: Text(item.displayName, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          Navigator.pop(ctx);
                          _mapController.move(LatLng(item.latitude, item.longitude), 14.0);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Menuju ke: ${item.name} (${item.latitude.toStringAsFixed(4)}, ${item.longitude.toStringAsFixed(4)})')),
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLayerSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('PILIH LAPISAN PETA OFFLINE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8)),
              ),
              ListTile(
                leading: const Icon(Icons.satellite_alt_rounded, color: Colors.orangeAccent),
                title: const Text('Satelit + Jalan (Google Hybrid)'),
                subtitle: const Text('Citra satelit tajam lengkap dengan nama jalan & jalur', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                trailing: _displayMode == MapDisplayMode.googleHybrid ? const Icon(Icons.check, color: AppTheme.primary) : null,
                onTap: () {
                  setState(() => _displayMode = MapDisplayMode.googleHybrid);
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.public_rounded, color: Colors.cyanAccent),
                title: const Text('Citra Satelit Global (ESRI)'),
                subtitle: const Text('Foto udara resolusi tinggi resmi ESRI ArcGIS', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                trailing: _displayMode == MapDisplayMode.esriSatellite ? const Icon(Icons.check, color: AppTheme.primary) : null,
                onTap: () {
                  setState(() => _displayMode = MapDisplayMode.esriSatellite);
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.landscape_rounded, color: Colors.greenAccent),
                title: const Text('Topografi & Relief 3D (Google Terrain)'),
                subtitle: const Text('Shaded relief bukit, lembah pegunungan, & elevasi cepat', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                trailing: _displayMode == MapDisplayMode.googleTerrain ? const Icon(Icons.check, color: AppTheme.primary) : null,
                onTap: () {
                  setState(() => _displayMode = MapDisplayMode.googleTerrain);
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.terrain_rounded, color: Colors.lightGreenAccent),
                title: const Text('Topografi & Elevasi Resmi (ESRI Topo)'),
                subtitle: const Text('Peta topografi kontur dan fitur fisik daratan', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                trailing: _displayMode == MapDisplayMode.esriTopo ? const Icon(Icons.check, color: AppTheme.primary) : null,
                onTap: () {
                  setState(() => _displayMode = MapDisplayMode.esriTopo);
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.dark_mode_rounded, color: AppTheme.primary),
                title: const Text('Taktis Gelap (Night Ops / OLED)'),
                subtitle: const Text('Kontras tinggi, nyaman di mata malam hari, hemat daya', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                trailing: _displayMode == MapDisplayMode.darkTactical ? const Icon(Icons.check, color: AppTheme.primary) : null,
                onTap: () {
                  setState(() => _displayMode = MapDisplayMode.darkTactical);
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.map_rounded, color: Colors.blueAccent),
                title: const Text('OpenStreetMap Standar'),
                subtitle: const Text('Jalan raya, pemukiman, & fasilitas umum komunitas', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                trailing: _displayMode == MapDisplayMode.osmStandard ? const Icon(Icons.check, color: AppTheme.primary) : null,
                onTap: () {
                  setState(() => _displayMode = MapDisplayMode.osmStandard);
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.grid_4x4_rounded, color: AppTheme.accent),
                title: const Text('Radar Grid Taktis Murni (0 KB)'),
                subtitle: const Text('Kanvas radar matematis tanpa ubin (darurat baterai kritis)', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                trailing: _displayMode == MapDisplayMode.radarGrid ? const Icon(Icons.check, color: AppTheme.primary) : null,
                onTap: () {
                  setState(() => _displayMode = MapDisplayMode.radarGrid);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _cycleSearchPattern() {
    setState(() {
      switch (_activePattern) {
        case SearchPatternType.none:
          _activePattern = SearchPatternType.expandingSquare;
          break;
        case SearchPatternType.expandingSquare:
          _activePattern = SearchPatternType.sectorSearch;
          break;
        case SearchPatternType.sectorSearch:
          _activePattern = SearchPatternType.parallelSweep;
          break;
        case SearchPatternType.parallelSweep:
          _activePattern = SearchPatternType.none;
          break;
      }
    });
  }

  String _patternName(SearchPatternType type) {
    switch (type) {
      case SearchPatternType.none:
        return 'NONAKTIF';
      case SearchPatternType.expandingSquare:
        return 'EXPANDING SQUARE (SPIRAL)';
      case SearchPatternType.sectorSearch:
        return 'SECTOR SEARCH (360°)';
      case SearchPatternType.parallelSweep:
        return 'PARALLEL SWEEP (GRID)';
    }
  }

  /// Menghasilkan titik-titik koordinat nyata untuk Search Pattern di atas peta
  List<LatLng> _generatePatternCoordinates(double centerLat, double centerLon) {
    final List<LatLng> points = [];
    final sweepMeters = _patternSweepWidthMeters;

    LatLng offsetMetersToLatLng(double dx, double dy) {
      final lat = centerLat + (dy / 111320.0);
      final lon = centerLon + (dx / (111320.0 * math.cos(centerLat * math.pi / 180.0)));
      return LatLng(lat, lon);
    }

    if (_activePattern == SearchPatternType.expandingSquare) {
      points.add(LatLng(centerLat, centerLon));
      double curX = 0;
      double curY = 0;
      double leg = sweepMeters;

      for (int i = 0; i < 4; i++) {
        // Utara
        curY += leg;
        points.add(offsetMetersToLatLng(curX, curY));
        // Timur
        curX += leg;
        points.add(offsetMetersToLatLng(curX, curY));
        leg += sweepMeters;
        // Selatan
        curY -= leg;
        points.add(offsetMetersToLatLng(curX, curY));
        // Barat
        curX -= leg;
        points.add(offsetMetersToLatLng(curX, curY));
        leg += sweepMeters;
      }
    } else if (_activePattern == SearchPatternType.sectorSearch) {
      final radius = sweepMeters * 5;
      final center = LatLng(centerLat, centerLon);
      points.add(center);

      for (int i = 0; i < 9; i++) {
        final a1 = (i * 120.0) * (math.pi / 180.0);
        final a2 = ((i * 120.0) + 60.0) * (math.pi / 180.0);
        final p1 = offsetMetersToLatLng(radius * math.sin(a1), radius * math.cos(a1));
        final p2 = offsetMetersToLatLng(radius * math.sin(a2), radius * math.cos(a2));
        points.add(p1);
        points.add(p2);
        points.add(center);
      }
    } else if (_activePattern == SearchPatternType.parallelSweep) {
      final halfW = sweepMeters * 3;
      final step = sweepMeters;
      for (double y = -step * 3; y <= step * 3; y += step * 2) {
        points.add(offsetMetersToLatLng(-halfW, y));
        points.add(offsetMetersToLatLng(halfW, y));
        points.add(offsetMetersToLatLng(halfW, y + step));
        points.add(offsetMetersToLatLng(-halfW, y + step));
      }
    }

    return points;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        final selfLoc = provider.lastLocation;
        final refLat = selfLoc?.latitude ?? -7.2504;
        final refLon = selfLoc?.longitude ?? 112.7688;

        // List pesan darurat SOS aktif
        final sosMessages = provider.messages
            .where((m) => m.messageType == MessageType.sos && m.latitude != null && m.longitude != null)
            .toList();

        return Scaffold(
          backgroundColor: const Color(0xFF0A0E14),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0F141C),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Peta Offline & Waypoint SAR', style: TextStyle(fontSize: 15)),
                Text(
                  _displayMode == MapDisplayMode.googleHybrid
                      ? 'Mode: Satelit + Jalan (Google)'
                      : _displayMode == MapDisplayMode.esriSatellite
                          ? 'Mode: Satelit Resolusi Tinggi (ESRI)'
                          : _displayMode == MapDisplayMode.googleTerrain
                              ? 'Mode: Topografi & Relief 3D'
                              : _displayMode == MapDisplayMode.esriTopo
                                  ? 'Mode: Topografi Resmi (ESRI)'
                                  : _displayMode == MapDisplayMode.darkTactical
                                      ? 'Mode: Taktis Gelap (Night Ops)'
                                      : _displayMode == MapDisplayMode.openTopo
                                          ? 'Mode: Kontur Topografi'
                                          : _displayMode == MapDisplayMode.osmStandard
                                              ? 'Mode: OpenStreetMap'
                                              : 'Mode: Radar Grid Taktis (0 KB)',
                  style: const TextStyle(fontSize: 10, color: AppTheme.primary, fontFamily: 'monospace'),
                ),
              ],
            ),
            actions: [
              // Cari Lokasi
              IconButton(
                icon: const Icon(Icons.search_rounded),
                tooltip: 'Cari Lokasi / Sasaran Operasi',
                onPressed: () => _showSearchLocationSheet(context),
              ),
              // Unduh Peta Offline
              IconButton(
                icon: const Icon(Icons.download_for_offline_rounded, color: AppTheme.accent),
                tooltip: 'Pusat Peta Offline',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => OfflineMapDownloadDialog(currentLat: refLat, currentLon: refLon),
                  );
                },
              ),
              // Pengukur Jarak Taktis
              IconButton(
                icon: Icon(
                  Icons.straighten_rounded,
                  color: _isMeasuring ? AppTheme.accent : Colors.white,
                ),
                tooltip: _isMeasuring ? 'Matikan Pengukur Jarak' : 'Ukur Jarak & Azimuth',
                onPressed: () {
                  setState(() {
                    _isMeasuring = !_isMeasuring;
                    if (!_isMeasuring) {
                      _measurePointA = null;
                      _measurePointB = null;
                    }
                  });
                },
              ),
              // Rekam Rute / Jejak GPS (Breadcrumbs)
              IconButton(
                icon: Icon(
                  provider.isRecordingBreadcrumbs ? Icons.route_rounded : Icons.add_road_rounded,
                  color: provider.isRecordingBreadcrumbs ? AppTheme.accent : Colors.white,
                ),
                tooltip: provider.isRecordingBreadcrumbs ? 'Hentikan Rekam Jejak' : 'Rekam Jejak Rute GPS',
                onPressed: () {
                  if (provider.isRecordingBreadcrumbs) {
                    provider.stopBreadcrumbRecording();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Perekaman jejak rute dihentikan.')),
                    );
                  } else {
                    provider.startBreadcrumbRecording();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Mulai merekam jejak rute GPS offline...')),
                    );
                  }
                },
              ),
              // Lapisan Peta
              IconButton(
                icon: const Icon(Icons.layers_rounded),
                tooltip: 'Pilih Lapisan Peta',
                onPressed: () => _showLayerSelector(context),
              ),
              // Daftar Waypoint
              IconButton(
                icon: const Icon(Icons.list_alt_rounded),
                tooltip: 'Daftar Waypoint',
                onPressed: () => _showWaypointListSheet(context, provider),
              ),
            ],
          ),
          body: Stack(
            children: [
              // 1. Interactive Map Engine (flutter_map) or Radar Canvas Fallback
              if (_displayMode == MapDisplayMode.radarGrid)
                GestureDetector(
                  onScaleUpdate: (details) {
                    setState(() {
                      _radarScale = (_radarScale * details.scale).clamp(0.05, 5.0);
                      _radarPanOffset += details.focalPointDelta;
                    });
                  },
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: TacticalGridPainter(
                      centerLat: refLat,
                      centerLon: refLon,
                      panOffset: _radarPanOffset,
                      scale: _radarScale,
                      selfLocation: selfLoc,
                      peers: provider.peers,
                      sosMessages: sosMessages,
                      waypoints: provider.waypoints,
                      selectedWaypoint: _selectedWaypoint,
                      selectedPeer: _selectedPeer,
                      selectedSos: _selectedSos,
                      searchPattern: _activePattern,
                      sweepWidthMeters: _patternSweepWidthMeters,
                      heading: provider.compassHeading,
                    ),
                  ),
                )
              else
                _buildFlutterMap(context, provider, refLat, refLon, sosMessages),

              // 2. Tactical Monospace HUD Top Bar
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: _buildTopHudBar(provider, refLat, refLon, selfLoc),
              ),

              // 3. Measuring Tool Floating HUD (if active)
              if (_isMeasuring)
                Positioned(
                  top: 76,
                  left: 10,
                  right: 10,
                  child: _buildMeasuringHud(),
                ),

              // 4. Target Tracking HUD (if waypoint/peer/sos selected)
              if (_selectedWaypoint != null || _selectedPeer != null || _selectedSos != null)
                Positioned(
                  bottom: 76,
                  left: 12,
                  right: 12,
                  child: _buildTargetLockHud(provider, refLat, refLon),
                ),

              // 5. Floating Action Controls (Right Bottom)
              Positioned(
                bottom: 16,
                right: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'fab_zoom_in',
                      backgroundColor: AppTheme.surfaceVariant,
                      child: const Icon(Icons.add, color: Colors.white),
                      onPressed: () {
                        if (_displayMode == MapDisplayMode.radarGrid) {
                          setState(() => _radarScale = (_radarScale * 1.3).clamp(0.05, 5.0));
                        } else {
                          _mapController.move(
                            _mapController.camera.center,
                            (_mapController.camera.zoom + 1).clamp(3.0, 18.0),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'fab_zoom_out',
                      backgroundColor: AppTheme.surfaceVariant,
                      child: const Icon(Icons.remove, color: Colors.white),
                      onPressed: () {
                        if (_displayMode == MapDisplayMode.radarGrid) {
                          setState(() => _radarScale = (_radarScale / 1.3).clamp(0.05, 5.0));
                        } else {
                          _mapController.move(
                            _mapController.camera.center,
                            (_mapController.camera.zoom - 1).clamp(3.0, 18.0),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'fab_pattern',
                      backgroundColor: _activePattern != SearchPatternType.none
                          ? AppTheme.primary
                          : AppTheme.surfaceVariant,
                      tooltip: 'Pola Pencarian SAR',
                      onPressed: _cycleSearchPattern,
                      child: Icon(
                        Icons.swap_calls_rounded,
                        color: _activePattern != SearchPatternType.none ? Colors.black : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'fab_recenter',
                      backgroundColor: AppTheme.surfaceVariant,
                      tooltip: 'Pusatkan ke Posisi Diri',
                      onPressed: () => _recenter(refLat, refLon),
                      child: const Icon(Icons.my_location_rounded, color: AppTheme.primary),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton(
                      heroTag: 'fab_add_wp',
                      backgroundColor: AppTheme.primary,
                      tooltip: 'Tandai Waypoint SAR',
                      child: const Icon(Icons.add_location_alt_rounded, color: Colors.black),
                      onPressed: () => _showAddWaypointDialog(context, provider),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFlutterMap(
    BuildContext context,
    AppProvider provider,
    double refLat,
    double refLon,
    List<MessageModel> sosMessages,
  ) {
    String tileSource = OfflineMapService.sourceCartoDark;
    if (_displayMode == MapDisplayMode.googleHybrid) {
      tileSource = OfflineMapService.sourceGoogleHybrid;
    } else if (_displayMode == MapDisplayMode.esriSatellite) {
      tileSource = OfflineMapService.sourceEsriSat;
    } else if (_displayMode == MapDisplayMode.googleTerrain) {
      tileSource = OfflineMapService.sourceGoogleTerrain;
    } else if (_displayMode == MapDisplayMode.esriTopo) {
      tileSource = OfflineMapService.sourceEsriTopo;
    } else if (_displayMode == MapDisplayMode.openTopo) {
      tileSource = OfflineMapService.sourceOpenTopo;
    } else if (_displayMode == MapDisplayMode.osmStandard) {
      tileSource = OfflineMapService.sourceOsm;
    }

    // Pattern coordinates
    final patternPoints = _generatePatternCoordinates(refLat, refLon);

    // Breadcrumb coordinates
    final breadcrumbPoints = provider.breadcrumbs
        .map((b) => LatLng(b.latitude, b.longitude))
        .toList();

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: LatLng(refLat, refLon),
        initialZoom: 15.0,
        minZoom: 3.0,
        maxZoom: 18.0,
        backgroundColor: const Color(0xFF0A0E14),
        onTap: (tapPosition, point) {
          if (_isMeasuring) {
            setState(() {
              if (_measurePointA == null) {
                _measurePointA = point;
              } else if (_measurePointB == null) {
                _measurePointB = point;
              } else {
                _measurePointA = point;
                _measurePointB = null;
              }
            });
          }
        },
        onLongPress: (tapPosition, point) {
          _showAddWaypointDialog(
            context,
            provider,
            customLat: point.latitude,
            customLon: point.longitude,
          );
        },
      ),
      children: [
        // 1. Offline-first Tile Layer
        TileLayer(
          urlTemplate: OfflineMapService.tileUrls[tileSource],
          tileProvider: TacticalOfflineTileProvider(tileSource: tileSource),
          userAgentPackageName: 'com.sinyalnol.app',
        ),

        // 2. Jejak Rute GPS (Breadcrumbs Trail)
        if (breadcrumbPoints.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: breadcrumbPoints,
                color: AppTheme.accent,
                strokeWidth: 3.5,
              ),
            ],
          ),

        // 3. Pola Pencarian SAR (Search Pattern)
        if (_activePattern != SearchPatternType.none && patternPoints.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: patternPoints,
                color: AppTheme.primary,
                strokeWidth: 2.2,
              ),
            ],
          ),

        // 4. Garis Pengukur Jarak Taktis
        if (_measurePointA != null && _measurePointB != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [_measurePointA!, _measurePointB!],
                color: Colors.amberAccent,
                strokeWidth: 2.5,
              ),
            ],
          ),

        // 5. Lingkaran Akurasi GNSS Diri
        if (provider.lastLocation != null)
          CircleLayer(
            circles: [
              CircleMarker(
                point: LatLng(refLat, refLon),
                radius: (provider.lastLocation?.accuracy ?? 15.0).clamp(10.0, 60.0),
                useRadiusInMeter: true,
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderColor: AppTheme.primary.withValues(alpha: 0.5),
                borderStrokeWidth: 1.0,
              ),
            ],
          ),

        // 6. Marker Lapisan (Waypoints, Rekan Mesh, SOS, Posisi Diri)
        MarkerLayer(
          markers: [
            // Waypoints SAR
            ...provider.waypoints.map((wp) {
              final isSelected = _selectedWaypoint?.id == wp.id;
              return Marker(
                point: LatLng(wp.latitude, wp.longitude),
                width: 70,
                height: 50,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedWaypoint = wp;
                      _selectedPeer = null;
                      _selectedSos = null;
                    });
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: wp.categoryColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.black,
                            width: isSelected ? 2.0 : 1.0,
                          ),
                          boxShadow: isSelected
                              ? [BoxShadow(color: wp.categoryColor, blurRadius: 8, spreadRadius: 2)]
                              : null,
                        ),
                        child: Icon(wp.categoryIcon, color: Colors.white, size: 14),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          wp.name,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: wp.categoryColor,
                            fontFamily: 'monospace',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

            // Pesan SOS Darurat
            ...sosMessages.map((sos) {
              return Marker(
                point: LatLng(sos.latitude!, sos.longitude!),
                width: 80,
                height: 60,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedSos = sos;
                      _selectedWaypoint = null;
                      _selectedPeer = null;
                    });
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: AppTheme.sosRed,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: AppTheme.sosRed, blurRadius: 12, spreadRadius: 3),
                          ],
                        ),
                        child: const Icon(Icons.emergency_rounded, color: Colors.white, size: 18),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'SOS: ${sos.senderName}',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.sosRed,
                            fontFamily: 'monospace',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

            // Marker Posisi Diri dengan Panah Arah Kompas Magnetometer
            Marker(
              point: LatLng(refLat, refLon),
              width: 50,
              height: 50,
              child: Transform.rotate(
                angle: provider.compassHeading * (math.pi / 180.0),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const Icon(Icons.navigation_rounded, color: AppTheme.primary, size: 32),
                  ],
                ),
              ),
            ),

            // Marker Pengukur Jarak (Titik A & B)
            if (_measurePointA != null)
              Marker(
                point: _measurePointA!,
                width: 30,
                height: 30,
                child: const CircleAvatar(
                  backgroundColor: Colors.amberAccent,
                  child: Text('A', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
            if (_measurePointB != null)
              Marker(
                point: _measurePointB!,
                width: 30,
                height: 30,
                child: const CircleAvatar(
                  backgroundColor: Colors.amberAccent,
                  child: Text('B', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTopHudBar(AppProvider provider, double refLat, double refLon, dynamic selfLoc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF121820).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border, width: 0.8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: selfLoc != null ? AppTheme.accent : AppTheme.warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    selfLoc != null ? 'GNSS: TERKUNCI' : 'GNSS: MENCARI SATELIT',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: selfLoc != null ? AppTheme.accent : AppTheme.warning,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.explore_outlined, color: AppTheme.primary, size: 12),
                  const SizedBox(width: 3),
                  Text(
                    TacticalCoords.bearingToCardinal(provider.compassHeading),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              GestureDetector(
                onTap: () => setState(() => _showUtm = !_showUtm),
                child: Text(
                  _showUtm
                      ? TacticalCoords.toUtmString(refLat, refLon)
                      : 'LAT: ${refLat.toStringAsFixed(6)} | LON: ${refLon.toStringAsFixed(6)}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (provider.isRecordingBreadcrumbs)
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(color: AppTheme.accent, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'JEJAK: ${TacticalCoords.formatDistance(provider.totalBreadcrumbDistanceMeters)}',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: AppTheme.accent, fontWeight: FontWeight.bold),
                    ),
                  ],
                )
              else
                Text(
                  'WAYPOINT: ${provider.waypoints.length}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: AppTheme.textSecondary),
                ),
              if (_activePattern != SearchPatternType.none)
                Text(
                  'POLA: ${_patternName(_activePattern)}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: AppTheme.primary, fontWeight: FontWeight.bold),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMeasuringHud() {
    double dist = 0;
    double bearing = 0;
    if (_measurePointA != null && _measurePointB != null) {
      dist = TacticalCoords.calculateDistanceMeters(
        _measurePointA!.latitude,
        _measurePointA!.longitude,
        _measurePointB!.latitude,
        _measurePointB!.longitude,
      );
      bearing = TacticalCoords.calculateBearing(
        _measurePointA!.latitude,
        _measurePointA!.longitude,
        _measurePointB!.latitude,
        _measurePointB!.longitude,
      );
    }

    // Estimasi waktu tempuh jalan kaki di medan SAR (~3.5 km/jam)
    final walkMinutes = (dist / (3500.0 / 60.0)).round();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF221A0F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amberAccent, width: 1.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  children: [
                    Icon(Icons.straighten_rounded, color: Colors.amberAccent, size: 14),
                    SizedBox(width: 6),
                    Text('PENGUKUR JARAK TAKTIS:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                  ],
                ),
                const SizedBox(height: 2),
                if (_measurePointA == null)
                  const Text('Ketuk titik pertama (Titik A) di peta...', style: TextStyle(fontSize: 11, color: Colors.white70))
                else if (_measurePointB == null)
                  const Text('Titik A terpilih. Ketuk sasaran (Titik B)...', style: TextStyle(fontSize: 11, color: Colors.white70))
                else
                  Text(
                    'Jarak: ${TacticalCoords.formatDistance(dist)} | Azimuth: ${TacticalCoords.bearingToCardinal(bearing)} (~$walkMinutes mnt jalan)',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Colors.white),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.amberAccent),
            tooltip: 'Reset Titik Ukur',
            onPressed: () {
              setState(() {
                _measurePointA = null;
                _measurePointB = null;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTargetLockHud(AppProvider provider, double selfLat, double selfLon) {
    String title = '';
    String sub = '';
    double targetLat = 0;
    double targetLon = 0;
    Color accentColor = AppTheme.primary;
    IconData icon = Icons.gps_fixed;

    if (_selectedWaypoint != null) {
      final wp = _selectedWaypoint!;
      title = wp.name;
      sub = wp.categoryLabel;
      targetLat = wp.latitude;
      targetLon = wp.longitude;
      accentColor = wp.categoryColor;
      icon = wp.categoryIcon;
    } else if (_selectedPeer != null) {
      final peer = _selectedPeer!;
      title = peer.deviceName;
      sub = 'Node Mesh (${peer.deviceId})';
      accentColor = AppTheme.accent;
      icon = Icons.cell_tower;
    } else if (_selectedSos != null) {
      final sos = _selectedSos!;
      title = 'DISTRESS SOS: ${sos.senderName}';
      sub = sos.body;
      targetLat = sos.latitude!;
      targetLon = sos.longitude!;
      accentColor = AppTheme.sosRed;
      icon = Icons.emergency_rounded;
    }

    final dist = targetLat != 0
        ? TacticalCoords.calculateDistanceMeters(selfLat, selfLon, targetLat, targetLon)
        : (_selectedPeer?.estimatedDistanceMeters ?? 0.0);

    final bearing = targetLat != 0
        ? TacticalCoords.calculateBearing(selfLat, selfLon, targetLat, targetLon)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161F2B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.2),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: accentColor.withValues(alpha: 0.2),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      sub,
                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'JARAK: ${TacticalCoords.formatDistance(dist)}',
                          style: TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold, color: accentColor),
                        ),
                        const SizedBox(width: 10),
                        if (targetLat != 0)
                          Text(
                            'AZIMUTH: ${TacticalCoords.bearingToCardinal(bearing)}',
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white70),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.textSecondary),
                onPressed: () {
                  setState(() {
                    _selectedWaypoint = null;
                    _selectedPeer = null;
                    _selectedSos = null;
                  });
                },
              ),
            ],
          ),
          if (_selectedWaypoint != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accentColor,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                  icon: const Icon(Icons.share_location_rounded, size: 14),
                  label: const Text('Siarkan ke Radio Mesh', style: TextStyle(fontSize: 11)),
                  onPressed: () async {
                    await provider.broadcastWaypoint(_selectedWaypoint!);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Waypoint "${_selectedWaypoint!.name}" disiarkan ke seluruh node rekan.')),
                      );
                    }
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Canvas Painter Taktis Militer & SAR Waypoint (Fallback Mode 0 KB)
class TacticalGridPainter extends CustomPainter {
  final double centerLat;
  final double centerLon;
  final Offset panOffset;
  final double scale; // px per meter
  final dynamic selfLocation;
  final List<PeerDevice> peers;
  final List<MessageModel> sosMessages;
  final List<SarWaypoint> waypoints;
  final SarWaypoint? selectedWaypoint;
  final PeerDevice? selectedPeer;
  final MessageModel? selectedSos;
  final SearchPatternType searchPattern;
  final double sweepWidthMeters;
  final double heading;

  TacticalGridPainter({
    required this.centerLat,
    required this.centerLon,
    required this.panOffset,
    required this.scale,
    required this.selfLocation,
    required this.peers,
    required this.sosMessages,
    required this.waypoints,
    this.selectedWaypoint,
    this.selectedPeer,
    this.selectedSos,
    required this.searchPattern,
    required this.sweepWidthMeters,
    this.heading = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2 + panOffset.dx, size.height / 2 + panOffset.dy);

    _drawRangeRingsAndGrid(canvas, size, center);

    if (searchPattern != SearchPatternType.none) {
      _drawSearchPattern(canvas, center);
    }

    _drawWaypoints(canvas, center);
    _drawSosSignals(canvas, center);
    _drawPeers(canvas, center);
    _drawSelfMarker(canvas, center);
    _drawTargetLockVector(canvas, center);
  }

  void _drawRangeRingsAndGrid(Canvas canvas, Size size, Offset center) {
    final gridPaint = Paint()
      ..color = const Color(0xFF1E2838)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final ringPaint = Paint()
      ..color = const Color(0xFF1F3048)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), gridPaint);
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), gridPaint);

    final ranges = [50.0, 100.0, 250.0, 500.0, 1000.0, 2500.0, 5000.0];
    for (final r in ranges) {
      final radiusPx = r * scale;
      if (radiusPx > 15 && radiusPx < math.max(size.width, size.height) * 1.5) {
        canvas.drawCircle(center, radiusPx, ringPaint);

        final textSpan = TextSpan(
          text: TacticalCoords.formatDistance(r),
          style: const TextStyle(
            color: Color(0xFF4A6572),
            fontSize: 9,
            fontFamily: 'monospace',
          ),
        );
        final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, Offset(center.dx + 4, center.dy - radiusPx - 10));
      }
    }
  }

  void _drawSearchPattern(Canvas canvas, Offset center) {
    final patternPaint = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final sweepPx = sweepWidthMeters * scale;

    if (searchPattern == SearchPatternType.expandingSquare) {
      final path = Path()..moveTo(center.dx, center.dy);
      double currentX = center.dx;
      double currentY = center.dy;
      double leg = sweepPx;

      for (int i = 1; i <= 8; i++) {
        currentY -= leg;
        path.lineTo(currentX, currentY);
        currentX += leg;
        path.lineTo(currentX, currentY);
        leg += sweepPx;
        currentY += leg;
        path.lineTo(currentX, currentY);
        currentX -= leg;
        path.lineTo(currentX, currentY);
        leg += sweepPx;
      }
      canvas.drawPath(path, patternPaint);
    } else if (searchPattern == SearchPatternType.sectorSearch) {
      final radius = 300.0 * scale;
      final path = Path()..moveTo(center.dx, center.dy);
      for (int i = 0; i < 9; i++) {
        final angle1 = (i * 120.0) * (math.pi / 180.0);
        final angle2 = ((i * 120.0) + 60.0) * (math.pi / 180.0);
        final p1 = Offset(center.dx + radius * math.sin(angle1), center.dy - radius * math.cos(angle1));
        final p2 = Offset(center.dx + radius * math.sin(angle2), center.dy - radius * math.cos(angle2));
        path.lineTo(p1.dx, p1.dy);
        path.lineTo(p2.dx, p2.dy);
        path.lineTo(center.dx, center.dy);
      }
      canvas.drawPath(path, patternPaint);
    } else if (searchPattern == SearchPatternType.parallelSweep) {
      final width = 400.0 * scale;
      final halfW = width / 2;
      final path = Path();
      for (double y = -200.0 * scale; y <= 200.0 * scale; y += sweepPx * 2) {
        path.moveTo(center.dx - halfW, center.dy + y);
        path.lineTo(center.dx + halfW, center.dy + y);
        path.lineTo(center.dx + halfW, center.dy + y + sweepPx);
        path.lineTo(center.dx - halfW, center.dy + y + sweepPx);
      }
      canvas.drawPath(path, patternPaint);
    }
  }

  void _drawWaypoints(Canvas canvas, Offset center) {
    for (final wp in waypoints) {
      final offsetMeters = TacticalCoords.toMetersOffset(wp.latitude, wp.longitude, centerLat, centerLon);
      final wpPos = Offset(center.dx + offsetMeters.x * scale, center.dy + offsetMeters.y * scale);

      final isSelected = selectedWaypoint?.id == wp.id;

      final paint = Paint()
        ..color = wp.categoryColor
        ..style = PaintingStyle.fill;

      canvas.drawCircle(wpPos, isSelected ? 8.0 : 6.0, paint);

      if (isSelected) {
        final selectRing = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawCircle(wpPos, 12.0, selectRing);
      }

      final textSpan = TextSpan(
        text: wp.name,
        style: TextStyle(
          color: wp.categoryColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
          backgroundColor: const Color(0xFF0F141C).withValues(alpha: 0.8),
        ),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(wpPos.dx - tp.width / 2, wpPos.dy + 8));
    }
  }

  void _drawSosSignals(Canvas canvas, Offset center) {
    for (final sos in sosMessages) {
      if (sos.latitude == null || sos.longitude == null) continue;
      final offsetMeters = TacticalCoords.toMetersOffset(sos.latitude!, sos.longitude!, centerLat, centerLon);
      final sosPos = Offset(center.dx + offsetMeters.x * scale, center.dy + offsetMeters.y * scale);

      final beaconPaint = Paint()
        ..color = AppTheme.sosRed.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(sosPos, 16.0, beaconPaint);

      final corePaint = Paint()
        ..color = AppTheme.sosRed
        ..style = PaintingStyle.fill;
      canvas.drawCircle(sosPos, 7.0, corePaint);

      final textSpan = TextSpan(
        text: 'SOS: ${sos.senderName}',
        style: const TextStyle(
          color: AppTheme.sosRed,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
          backgroundColor: Color(0xCC000000),
        ),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(sosPos.dx - tp.width / 2, sosPos.dy + 10));
    }
  }

  void _drawPeers(Canvas canvas, Offset center) {
    int index = 0;
    for (final peer in peers) {
      final angle = (index * (360.0 / math.max(peers.length, 1))) * (math.pi / 180.0);
      final distMeters = peer.estimatedDistanceMeters ?? 50.0;
      final peerPos = Offset(
        center.dx + math.sin(angle) * distMeters * scale,
        center.dy - math.cos(angle) * distMeters * scale,
      );

      final peerPaint = Paint()
        ..color = AppTheme.accent
        ..style = PaintingStyle.fill;
      canvas.drawCircle(peerPos, 5.0, peerPaint);

      final textSpan = TextSpan(
        text: peer.deviceName,
        style: const TextStyle(
          color: AppTheme.accent,
          fontSize: 9,
          fontFamily: 'monospace',
          backgroundColor: Color(0xCC000000),
        ),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(peerPos.dx - tp.width / 2, peerPos.dy + 7));

      index++;
    }
  }

  void _drawSelfMarker(Canvas canvas, Offset center) {
    final acc = (selfLocation?.accuracy ?? 15.0) * scale;
    final accPaint = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, acc.clamp(12.0, 60.0), accPaint);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(heading * (math.pi / 180.0));

    final trianglePaint = Paint()
      ..color = AppTheme.primary
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, -14);
    path.lineTo(8, 8);
    path.lineTo(0, 4);
    path.lineTo(-8, 8);
    path.close();
    canvas.drawPath(path, trianglePaint);

    final northTipPaint = Paint()
      ..color = AppTheme.sosRed
      ..style = PaintingStyle.fill;
    final tipPath = Path();
    tipPath.moveTo(0, -14);
    tipPath.lineTo(4, -5);
    tipPath.lineTo(-4, -5);
    tipPath.close();
    canvas.drawPath(tipPath, northTipPaint);

    canvas.restore();

    final textSpan = TextSpan(
      text: 'ANDA (${heading.toStringAsFixed(0)}°)',
      style: const TextStyle(
        color: AppTheme.primary,
        fontSize: 9,
        fontWeight: FontWeight.bold,
        fontFamily: 'monospace',
      ),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy + 12));
  }

  void _drawTargetLockVector(Canvas canvas, Offset center) {
    Offset? targetPos;
    Color vectorColor = AppTheme.primary;

    if (selectedWaypoint != null) {
      final wp = selectedWaypoint!;
      final offsetMeters = TacticalCoords.toMetersOffset(wp.latitude, wp.longitude, centerLat, centerLon);
      targetPos = Offset(center.dx + offsetMeters.x * scale, center.dy + offsetMeters.y * scale);
      vectorColor = wp.categoryColor;
    } else if (selectedSos != null && selectedSos!.latitude != null && selectedSos!.longitude != null) {
      final offsetMeters = TacticalCoords.toMetersOffset(selectedSos!.latitude!, selectedSos!.longitude!, centerLat, centerLon);
      targetPos = Offset(center.dx + offsetMeters.x * scale, center.dy + offsetMeters.y * scale);
      vectorColor = AppTheme.sosRed;
    }

    if (targetPos != null) {
      final linePaint = Paint()
        ..color = vectorColor.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawLine(center, targetPos, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant TacticalGridPainter oldDelegate) {
    return oldDelegate.scale != scale ||
        oldDelegate.panOffset != panOffset ||
        oldDelegate.waypoints != waypoints ||
        oldDelegate.peers != peers ||
        oldDelegate.selectedWaypoint != selectedWaypoint ||
        oldDelegate.selectedPeer != selectedPeer ||
        oldDelegate.selectedSos != selectedSos ||
        oldDelegate.searchPattern != searchPattern;
  }
}
