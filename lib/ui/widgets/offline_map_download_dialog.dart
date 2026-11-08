import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../services/offline_map_service.dart';
import '../theme/app_theme.dart';

class OfflineMapDownloadDialog extends StatefulWidget {
  final double currentLat;
  final double currentLon;

  const OfflineMapDownloadDialog({
    super.key,
    required this.currentLat,
    required this.currentLon,
  });

  @override
  State<OfflineMapDownloadDialog> createState() => _OfflineMapDownloadDialogState();
}

class _OfflineMapDownloadDialogState extends State<OfflineMapDownloadDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  late double _centerLat;
  late double _centerLon;

  final TextEditingController _nameController = TextEditingController(text: 'Area Operasi SAR');
  final TextEditingController _searchController = TextEditingController();
  List<SearchResultLocation> _searchResults = [];
  bool _isSearching = false;

  double _radiusKm = 3.0;
  int _minZoom = 12;
  int _maxZoom = 15;
  String _selectedSource = OfflineMapService.sourceGoogleHybrid;

  bool _isDownloading = false;
  bool _cancelRequested = false;
  OfflineDownloadProgress? _currentProgress;
  StreamSubscription<OfflineDownloadProgress>? _downloadSub;

  int _totalCacheBytes = 0;
  int _totalCacheTiles = 0;
  bool _isLoadingCacheStats = true;

  @override
  void initState() {
    super.initState();
    _centerLat = widget.currentLat;
    _centerLon = widget.currentLon;
    _tabController = TabController(length: 2, vsync: this);
    _loadCacheStats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _searchController.dispose();
    _downloadSub?.cancel();
    super.dispose();
  }

  Future<void> _loadCacheStats() async {
    setState(() => _isLoadingCacheStats = true);
    final bytes = await OfflineMapService.instance.getTotalCacheSizeBytes();
    final tiles = await OfflineMapService.instance.getTotalCachedTilesCount();
    if (mounted) {
      setState(() {
        _totalCacheBytes = bytes;
        _totalCacheTiles = tiles;
        _isLoadingCacheStats = false;
      });
    }
  }

  Future<void> _executeSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _isSearching = true);
    final results = await OfflineMapService.instance.searchLocations(query);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  int get _estimatedTiles {
    return OfflineMapService.instance.estimateTileCount(
      centerLat: _centerLat,
      centerLon: _centerLon,
      radiusKm: _radiusKm,
      minZoom: _minZoom,
      maxZoom: _maxZoom,
    );
  }

  String get _estimatedSizeMB {
    final estBytes = _estimatedTiles * 22 * 1024;
    return (estBytes / 1024 / 1024).toStringAsFixed(1);
  }

  void _startDownload() {
    final packName = _nameController.text.trim().isEmpty ? 'Area Lapangan' : _nameController.text.trim();

    setState(() {
      _isDownloading = true;
      _cancelRequested = false;
      _currentProgress = null;
    });

    final stream = OfflineMapService.instance.downloadRegion(
      packName: packName,
      centerLat: _centerLat,
      centerLon: _centerLon,
      radiusKm: _radiusKm,
      minZoom: _minZoom,
      maxZoom: _maxZoom,
      tileSource: _selectedSource,
      cancelCheck: () => _cancelRequested,
    );

    _downloadSub = stream.listen((progress) {
      if (mounted) {
        setState(() {
          _currentProgress = progress;
        });

        if (progress.isCompleted || progress.isCancelled) {
          _isDownloading = false;
          _loadCacheStats();
          final provider = Provider.of<AppProvider>(context, listen: false);
          provider.loadOfflineMapPacks();
        }
      }
    }, onError: (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengunduh peta: $e')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 650),
        child: Column(
          children: [
            // Header Dialog
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF131A24),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.download_for_offline_rounded, color: AppTheme.primary, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Pusat Peta Offline SAR',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: AppTheme.textSecondary),
                    onPressed: _isDownloading ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Tab Bar
            TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.primary,
              labelColor: AppTheme.primary,
              unselectedLabelColor: AppTheme.textSecondary,
              tabs: const [
                Tab(icon: Icon(Icons.cloud_download_outlined, size: 18), text: 'Unduh Area Baru'),
                Tab(icon: Icon(Icons.folder_special_outlined, size: 18), text: 'Peta Tersimpan'),
              ],
            ),

            // Content Tabs
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDownloadTab(),
                  _buildSavedPacksTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bilah Pencarian Lokasi (Geocoding API)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  enabled: !_isDownloading,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _executeSearch,
                  decoration: InputDecoration(
                    hintText: 'Cari gunung, kota, atau posko...',
                    hintStyle: const TextStyle(fontSize: 12),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _isSearching
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchResults = []);
                                },
                              )
                            : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _isDownloading ? null : () => _executeSearch(_searchController.text),
                child: const Text('Cari'),
              ),
            ],
          ),

          // Hasil Pencarian Dropdown
          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A2332),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primary, width: 0.8),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _searchResults.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.border),
                itemBuilder: (ctx, i) {
                  final loc = _searchResults[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on, color: AppTheme.accent, size: 18),
                    title: Text(loc.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    subtitle: Text(
                      loc.displayName,
                      style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      setState(() {
                        _centerLat = loc.latitude;
                        _centerLon = loc.longitude;
                        _nameController.text = loc.name;
                        _searchResults = [];
                        _searchController.text = loc.name;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Pusat koordinat disetel ke: ${loc.name}'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Nama Wilayah
          TextField(
            controller: _nameController,
            enabled: !_isDownloading,
            decoration: const InputDecoration(
              labelText: 'Nama Paket Peta Lapangan',
              prefixIcon: Icon(Icons.label_outline, size: 18),
            ),
          ),
          const SizedBox(height: 12),

          // Pilihan Sumber Peta API
          const Text(
            'SUMBER API UBIN PETA:',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _selectedSource,
            dropdownColor: AppTheme.surfaceVariant,
            decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
            items: [
              DropdownMenuItem(
                value: OfflineMapService.sourceGoogleHybrid,
                child: const Row(
                  children: [
                    Icon(Icons.satellite_alt_rounded, color: Colors.orangeAccent, size: 16),
                    SizedBox(width: 8),
                    Text('Satelit + Jalan (Google)', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              DropdownMenuItem(
                value: OfflineMapService.sourceEsriSat,
                child: const Row(
                  children: [
                    Icon(Icons.public_rounded, color: Colors.cyanAccent, size: 16),
                    SizedBox(width: 8),
                    Text('Citra Satelit Resolusi Tinggi (ESRI)', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              DropdownMenuItem(
                value: OfflineMapService.sourceGoogleTerrain,
                child: const Row(
                  children: [
                    Icon(Icons.landscape_rounded, color: Colors.greenAccent, size: 16),
                    SizedBox(width: 8),
                    Text('Topografi & Relief 3D (Google)', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              DropdownMenuItem(
                value: OfflineMapService.sourceEsriTopo,
                child: const Row(
                  children: [
                    Icon(Icons.terrain_rounded, color: Colors.lightGreenAccent, size: 16),
                    SizedBox(width: 8),
                    Text('Topografi & Elevasi Resmi (ESRI)', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              DropdownMenuItem(
                value: OfflineMapService.sourceCartoDark,
                child: const Row(
                  children: [
                    Icon(Icons.dark_mode_rounded, color: AppTheme.primary, size: 16),
                    SizedBox(width: 8),
                    Text('Taktis Gelap (Night Ops / OLED)', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              DropdownMenuItem(
                value: OfflineMapService.sourceOsm,
                child: const Row(
                  children: [
                    Icon(Icons.map_rounded, color: Colors.blueAccent, size: 16),
                    SizedBox(width: 8),
                    Text('OpenStreetMap Standar (Jalan/Kota)', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
            onChanged: _isDownloading ? null : (val) {
              if (val != null) setState(() => _selectedSource = val);
            },
          ),
          const SizedBox(height: 12),

          // Radius Jangkauan
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'RADIUS WILAYAH:',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
              ),
              Text(
                '${_radiusKm.toStringAsFixed(0)} KM',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary, fontFamily: 'monospace'),
              ),
            ],
          ),
          Slider(
            value: _radiusKm,
            min: 1.0,
            max: 15.0,
            divisions: 14,
            activeColor: AppTheme.primary,
            onChanged: _isDownloading ? null : (val) => setState(() => _radiusKm = val),
          ),

          // Zoom Level Presets
          const Text(
            'RESOLUSI / LEVEL DETAIL ZOOM:',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('Ringan (11-14)', style: TextStyle(fontSize: 11)),
                  selected: _minZoom == 11 && _maxZoom == 14,
                  onSelected: _isDownloading ? null : (sel) {
                    if (sel) setState(() { _minZoom = 11; _maxZoom = 14; });
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ChoiceChip(
                  label: const Text('Standar (12-15)', style: TextStyle(fontSize: 11)),
                  selected: _minZoom == 12 && _maxZoom == 15,
                  onSelected: _isDownloading ? null : (sel) {
                    if (sel) setState(() { _minZoom = 12; _maxZoom = 15; });
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ChoiceChip(
                  label: const Text('Detail (13-16)', style: TextStyle(fontSize: 11)),
                  selected: _minZoom == 13 && _maxZoom == 16,
                  onSelected: _isDownloading ? null : (sel) {
                    if (sel) setState(() { _minZoom = 13; _maxZoom = 16; });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Estimasi Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF161F2E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('Total Ubin', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                    const SizedBox(height: 2),
                    Text(
                      '$_estimatedTiles',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'monospace', color: Colors.white),
                    ),
                  ],
                ),
                Container(width: 1, height: 26, color: AppTheme.border),
                Column(
                  children: [
                    const Text('Est. Ukuran', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                    const SizedBox(height: 2),
                    Text(
                      '~$_estimatedSizeMB MB',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'monospace', color: AppTheme.accent),
                    ),
                  ],
                ),
                Container(width: 1, height: 26, color: AppTheme.border),
                Column(
                  children: [
                    const Text('Pusat Koordinat', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                    const SizedBox(height: 2),
                    Text(
                      '${_centerLat.toStringAsFixed(2)}, ${_centerLon.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Download Progress Bar
          if (_isDownloading && _currentProgress != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _currentProgress!.progress,
                minHeight: 8,
                backgroundColor: AppTheme.surfaceVariant,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _currentProgress!.statusMessage,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${(_currentProgress!.progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.primary, fontFamily: 'monospace'),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // Tombol Aksi
          Row(
            children: [
              if (_isDownloading)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _cancelRequested = true),
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.sosRed),
                    child: const Text('Batalkan'),
                  ),
                )
              else
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Unduh Peta Wilayah Ini'),
                    onPressed: _startDownload,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSavedPacksTab() {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        final packs = provider.offlineMapPacks;

        return Column(
          children: [
            // Cache Storage Overview Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: const Color(0xFF131A24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TOTAL PENYIMPANAN OFFLINE:', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      _isLoadingCacheStats
                          ? const Text('Menghitung...', style: TextStyle(fontSize: 12))
                          : Text(
                              '${(_totalCacheBytes / 1024 / 1024).toStringAsFixed(1)} MB ($_totalCacheTiles ubin)',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace', color: AppTheme.accent),
                            ),
                    ],
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_sweep_rounded, size: 16, color: AppTheme.sosRed),
                    label: const Text('Kosongkan', style: TextStyle(fontSize: 11, color: AppTheme.sosRed)),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: AppTheme.surface,
                          title: const Text('Hapus Seluruh Cache Peta?'),
                          content: const Text('Semua ubin peta offline yang tersimpan akan dihapus dari penyimpanan HP.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.sosRed),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Hapus Semua'),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        await OfflineMapService.instance.clearAllTiles();
                        await _loadCacheStats();
                        provider.loadOfflineMapPacks();
                      }
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.border),

            // List of Saved Packs
            Expanded(
              child: packs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map_outlined, size: 40, color: AppTheme.textSecondary.withValues(alpha: 0.4)),
                          const SizedBox(height: 8),
                          const Text(
                            'Belum ada paket peta offline tersimpan.\nSilakan unduh pada tab "Unduh Area Baru".',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: packs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.border),
                      itemBuilder: (ctx, i) {
                        final p = packs[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.surfaceVariant,
                            child: Icon(
                              p.tileSource == 'google_hybrid' || p.tileSource == 'esri_sat'
                                  ? Icons.satellite_alt_rounded
                                  : p.tileSource == 'google_terrain' || p.tileSource == 'esri_topo'
                                      ? Icons.terrain_rounded
                                      : p.tileSource == 'cartodark'
                                          ? Icons.dark_mode_rounded
                                          : Icons.map_rounded,
                              color: AppTheme.primary,
                              size: 20,
                            ),
                          ),
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Text(
                            '${p.sourceLabel} • ${p.formattedSize} (${p.tileCount} ubin)\nRadius: ${p.radiusKm.toStringAsFixed(0)} km (Zoom ${p.minZoom}-${p.maxZoom})',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppTheme.textSecondary, size: 18),
                            onPressed: () async {
                              await provider.deleteOfflineMapPack(p.id);
                              await _loadCacheStats();
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
