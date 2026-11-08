import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/message_model.dart';
import '../models/sar_waypoint.dart';
import '../models/offline_map_pack.dart';
import '../models/breadcrumb_point.dart';

class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._init();
  static Database? _database;

  LocalDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('sinyalnol.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 5,
      onCreate: _createDB,
      onUpgrade: _onUpgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Tabel pesan offline
    await db.execute('''
      CREATE TABLE messages (
        message_id TEXT PRIMARY KEY,
        sender_id TEXT NOT NULL,
        sender_name TEXT NOT NULL,
        recipient_id TEXT,
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        message_type TEXT NOT NULL,
        body TEXT,
        latitude REAL,
        longitude REAL,
        altitude REAL,
        hop_count INTEGER NOT NULL,
        max_hops INTEGER NOT NULL,
        delivery_status TEXT NOT NULL,
        relayed_by TEXT,
        ack_for_message_id TEXT,
        delivered_at TEXT,
        integrity_hash TEXT,
        is_encrypted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Index untuk query riwayat chat berdasarkan recipient & waktu
    await db.execute('CREATE INDEX idx_messages_recipient ON messages(recipient_id)');
    await db.execute('CREATE INDEX idx_messages_created ON messages(created_at)');

    // Tabel log uji lapangan (benchmark jarak & stabilitas radio)
    await db.execute('''
      CREATE TABLE field_test_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        target_peer TEXT NOT NULL,
        distance_meters REAL,
        terrain_type TEXT,
        success INTEGER NOT NULL,
        latency_ms INTEGER,
        rssi INTEGER,
        battery_level REAL,
        notes TEXT
      )
    ''');

    // Tabel Waypoint SAR & Grid Taktis
    await db.execute('''
      CREATE TABLE sar_waypoints (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        altitude REAL,
        created_at TEXT NOT NULL,
        created_by TEXT NOT NULL,
        notes TEXT
      )
    ''');

    // Tabel Paket Peta Offline Tersimpan
    await db.execute('''
      CREATE TABLE offline_map_packs (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        center_lat REAL NOT NULL,
        center_lon REAL NOT NULL,
        radius_km REAL NOT NULL,
        min_zoom INTEGER NOT NULL,
        max_zoom INTEGER NOT NULL,
        tile_count INTEGER NOT NULL,
        size_bytes INTEGER NOT NULL,
        tile_source TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // Tabel Jejak Lintasan GPS Offline (Breadcrumbs Trail)
    await db.execute('''
      CREATE TABLE breadcrumbs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        altitude REAL,
        timestamp TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE messages ADD COLUMN ack_for_message_id TEXT');
      await db.execute('ALTER TABLE messages ADD COLUMN delivered_at TEXT');
      await db.execute('ALTER TABLE messages ADD COLUMN integrity_hash TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE messages ADD COLUMN is_encrypted INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sar_waypoints (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          category TEXT NOT NULL,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          altitude REAL,
          created_at TEXT NOT NULL,
          created_by TEXT NOT NULL,
          notes TEXT
        )
      ''');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS offline_map_packs (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          center_lat REAL NOT NULL,
          center_lon REAL NOT NULL,
          radius_km REAL NOT NULL,
          min_zoom INTEGER NOT NULL,
          max_zoom INTEGER NOT NULL,
          tile_count INTEGER NOT NULL,
          size_bytes INTEGER NOT NULL,
          tile_source TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS breadcrumbs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          altitude REAL,
          timestamp TEXT NOT NULL
        )
      ''');
    }
  }

  // --- CRUD Pesan ---

  Future<bool> insertMessage(MessageModel message) async {
    final db = await database;
    try {
      final rows = await db.insert(
        'messages',
        message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore, // Mencegah duplikasi (id unik)
      );
      return rows > 0;
    } catch (e) {
      return false;
    }
  }

  Future<bool> messageExists(String messageId) async {
    final db = await database;
    final res = await db.query(
      'messages',
      columns: ['message_id'],
      where: 'message_id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    return res.isNotEmpty;
  }

  Future<void> updateDeliveryStatus(String messageId, DeliveryStatus status, {String? relayedBy}) async {
    final db = await database;
    final Map<String, dynamic> values = {
      'delivery_status': status.name,
    };
    if (relayedBy != null) {
      values['relayed_by'] = relayedBy;
    }

    await db.update(
      'messages',
      values,
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  /// Memperbarui status pesan menjadi 'delivered' berdasarkan tanda terima ACK dua arah
  Future<bool> confirmDeliveryByAck(String messageId, DateTime deliveredAt) async {
    final db = await database;
    final count = await db.update(
      'messages',
      {
        'delivery_status': DeliveryStatus.delivered.name,
        'delivered_at': deliveredAt.toIso8601String(),
      },
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
    return count > 0;
  }

  Future<List<MessageModel>> getAllMessages() async {
    final db = await database;
    final maps = await db.query('messages', orderBy: 'created_at ASC');
    return maps.map((m) => MessageModel.fromMap(m)).toList();
  }

  Future<List<MessageModel>> getMessagesForPeer(String peerId) async {
    final db = await database;
    final maps = await db.query(
      'messages',
      where: '(recipient_id = ? OR sender_id = ?)',
      whereArgs: [peerId, peerId],
      orderBy: 'created_at ASC',
    );
    return maps.map((m) => MessageModel.fromMap(m)).toList();
  }

  Future<List<MessageModel>> getBroadcastMessages() async {
    final db = await database;
    final maps = await db.query(
      'messages',
      where: 'recipient_id = ? OR recipient_id IS NULL OR message_type = ?',
      whereArgs: ['BROADCAST', MessageType.sos.name],
      orderBy: 'created_at ASC',
    );
    return maps.map((m) => MessageModel.fromMap(m)).toList();
  }

  Future<List<MessageModel>> getQueuedMessages() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final maps = await db.query(
      'messages',
      where: 'delivery_status = ? AND expires_at > ?',
      whereArgs: [DeliveryStatus.queued.name, now],
      orderBy: 'created_at ASC',
    );
    return maps.map((m) => MessageModel.fromMap(m)).toList();
  }

  Future<void> purgeExpiredMessages() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'messages',
      {'delivery_status': DeliveryStatus.failed.name},
      where: 'delivery_status = ? AND expires_at <= ?',
      whereArgs: [DeliveryStatus.queued.name, now],
    );
  }

  // --- Uji Lapangan Logs ---

  Future<int> insertFieldTestLog(Map<String, dynamic> log) async {
    final db = await database;
    return await db.insert('field_test_logs', log);
  }

  Future<List<Map<String, dynamic>>> getFieldTestLogs() async {
    final db = await database;
    return await db.query('field_test_logs', orderBy: 'id DESC');
  }

  // --- Mesin Ekspor Data Offline (CSV & JSON) ---

  /// Ekspor log uji lapangan ke format CSV untuk analisis GIS/spreadsheet
  Future<String> exportFieldTestLogsToCsv() async {
    final logs = await getFieldTestLogs();
    final buffer = StringBuffer();
    buffer.writeln('ID,Timestamp,TargetPeer,DistanceMeters,TerrainType,Success,LatencyMs,RSSI_dBm,BatteryLevel,Notes');

    for (final l in logs) {
      final safeNotes = (l['notes'] as String? ?? '').replaceAll('"', '""');
      buffer.writeln(
        '${l['id']},"${l['timestamp']}","${l['target_peer']}",${l['distance_meters']},"${l['terrain_type']}",${l['success']},${l['latency_ms']},${l['rssi']},${l['battery_level']},"$safeNotes"',
      );
    }

    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'sinyalnol_field_test_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(buffer.toString());
    return file.path;
  }

  // --- CRUD Waypoint SAR ---

  Future<bool> insertWaypoint(SarWaypoint waypoint) async {
    final db = await database;
    try {
      final rows = await db.insert(
        'sar_waypoints',
        waypoint.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return rows > 0;
    } catch (e) {
      return false;
    }
  }

  Future<List<SarWaypoint>> getAllWaypoints() async {
    final db = await database;
    final res = await db.query('sar_waypoints', orderBy: 'created_at DESC');
    return res.map((map) => SarWaypoint.fromMap(map)).toList();
  }

  Future<bool> deleteWaypoint(String id) async {
    final db = await database;
    final rows = await db.delete(
      'sar_waypoints',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows > 0;
  }

  /// Ekspor seluruh riwayat pesan ke format CSV
  Future<String> exportMessagesToCsv() async {
    final messages = await getAllMessages();
    final buffer = StringBuffer();
    buffer.writeln('MessageID,SenderID,SenderName,RecipientID,CreatedAt,ExpiresAt,Type,Body,Latitude,Longitude,Altitude,HopCount,MaxHops,Status,RelayedBy,DeliveredAt');

    for (final m in messages) {
      final safeBody = m.body.replaceAll('"', '""');
      buffer.writeln(
        '"${m.messageId}","${m.senderId}","${m.senderName}","${m.recipientId ?? 'BROADCAST'}","${m.createdAt.toIso8601String()}","${m.expiresAt.toIso8601String()}","${m.messageType.name}","$safeBody",${m.latitude ?? ''},${m.longitude ?? ''},${m.altitude ?? ''},${m.hopCount},${m.maxHops},"${m.deliveryStatus.name}","${m.relayedBy ?? ''}","${m.deliveredAt?.toIso8601String() ?? ''}"',
      );
    }

    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'sinyalnol_messages_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(buffer.toString());
    return file.path;
  }

  /// Ekspor seluruh data (Pesan + Uji Lapangan + Waypoint SAR) ke format JSON terstruktur
  Future<String> exportAllToJson() async {
    final messages = await getAllMessages();
    final logs = await getFieldTestLogs();
    final waypoints = await getAllWaypoints();

    final exportData = {
      'system': 'SinyalNol Offline Mesh',
      'exported_at': DateTime.now().toIso8601String(),
      'version': '0.3-tactical',
      'sar_waypoints': waypoints.map((w) => w.toMap()).toList(),
      'field_test_logs': logs,
      'messages': messages.map((m) => m.toMap()).toList(),
    };

    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'sinyalnol_full_dump_${DateTime.now().millisecondsSinceEpoch}.json';
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(exportData));
    return file.path;
  }

  // --- CRUD Paket Peta Offline & Breadcrumbs ---

  Future<bool> insertOfflinePack(OfflineMapPack pack) async {
    final db = await database;
    try {
      final rows = await db.insert(
        'offline_map_packs',
        pack.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return rows > 0;
    } catch (e) {
      return false;
    }
  }

  Future<List<OfflineMapPack>> getAllOfflinePacks() async {
    final db = await database;
    final res = await db.query('offline_map_packs', orderBy: 'created_at DESC');
    return res.map((m) => OfflineMapPack.fromMap(m)).toList();
  }

  Future<int> deleteOfflinePack(String id) async {
    final db = await database;
    return await db.delete('offline_map_packs', where: 'id = ?', whereArgs: [id]);
  }

  Future<bool> insertBreadcrumb(BreadcrumbPoint point) async {
    final db = await database;
    try {
      final id = await db.insert('breadcrumbs', point.toMap());
      return id > 0;
    } catch (e) {
      return false;
    }
  }

  Future<List<BreadcrumbPoint>> getAllBreadcrumbs() async {
    final db = await database;
    final res = await db.query('breadcrumbs', orderBy: 'id ASC');
    return res.map((m) => BreadcrumbPoint.fromMap(m)).toList();
  }

  Future<int> clearBreadcrumbs() async {
    final db = await database;
    return await db.delete('breadcrumbs');
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('messages');
    await db.delete('field_test_logs');
    await db.delete('sar_waypoints');
    await db.delete('offline_map_packs');
    await db.delete('breadcrumbs');
  }
}
