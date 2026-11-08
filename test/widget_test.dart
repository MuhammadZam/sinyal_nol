import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:sinyal_nol/models/message_model.dart';
import 'package:sinyal_nol/models/sar_waypoint.dart';
import 'package:sinyal_nol/models/offline_map_pack.dart';
import 'package:sinyal_nol/models/breadcrumb_point.dart';
import 'package:sinyal_nol/services/encryption_service.dart';
import 'package:sinyal_nol/services/lora_bridge_service.dart';
import 'package:sinyal_nol/services/tactical_audio_service.dart';
import 'package:sinyal_nol/services/offline_map_service.dart';
import 'package:sinyal_nol/utils/tactical_coords.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers.global'), (call) async => 1);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers'), (call) async => 1);
  test('MessageModel serialization and TTL verification test', () {
    final now = DateTime.now();
    final expires = now.add(const Duration(hours: 24));

    final msg = MessageModel(
      messageId: 'test-uuid-1234',
      senderId: 'device-alpha',
      senderName: 'Alpha Node',
      recipientId: 'BROADCAST',
      createdAt: now,
      expiresAt: expires,
      messageType: MessageType.sos,
      body: 'Pengujian darurat SOS tanpa internet',
      latitude: -7.250445,
      longitude: 112.768845,
      hopCount: 1,
      maxHops: 3,
      deliveryStatus: DeliveryStatus.queued,
    );

    // Verify properties
    expect(msg.isBroadcast, isTrue);
    expect(msg.hasLocation, isTrue);
    expect(msg.isExpired, isFalse);

    // Test JSON Serialization & Deserialization
    final jsonStr = msg.toJson();
    final parsed = MessageModel.fromJson(jsonStr);

    expect(parsed.messageId, equals('test-uuid-1234'));
    expect(parsed.senderName, equals('Alpha Node'));
    expect(parsed.latitude, closeTo(-7.250445, 0.0001));
    expect(parsed.messageType, equals(MessageType.sos));
    expect(parsed.deliveryStatus, equals(DeliveryStatus.queued));
  });

  test('ACK message type and delivery receipt verification test', () {
    final now = DateTime.now();
    final deliveredTime = now.add(const Duration(seconds: 2));

    final ackMsg = MessageModel(
      messageId: 'ACK-889900',
      senderId: 'device-bravo',
      senderName: 'Bravo Node',
      recipientId: 'device-alpha',
      createdAt: deliveredTime,
      expiresAt: now.add(const Duration(hours: 1)),
      messageType: MessageType.ack,
      body: 'ACK_DELIVERED',
      ackForMessageId: 'ORIGINAL-MSG-001',
      deliveryStatus: DeliveryStatus.delivered,
      deliveredAt: deliveredTime,
      integrityHash: '8F2A4B1C',
    );

    expect(ackMsg.isAck, isTrue);
    expect(ackMsg.ackForMessageId, equals('ORIGINAL-MSG-001'));
    expect(ackMsg.deliveredAt, equals(deliveredTime));
    expect(ackMsg.integrityHash, equals('8F2A4B1C'));

    // Serialization round trip
    final jsonStr = ackMsg.toJson();
    final parsed = MessageModel.fromJson(jsonStr);

    expect(parsed.messageType, equals(MessageType.ack));
    expect(parsed.ackForMessageId, equals('ORIGINAL-MSG-001'));
    expect(parsed.deliveryStatus, equals(DeliveryStatus.delivered));
    expect(parsed.integrityHash, equals('8F2A4B1C'));
  });

  test('E2EE X25519 and AES-256-GCM encryption/decryption round-trip test', () async {
    final encService = EncryptionService.instance;
    await encService.initialize();

    // Buat mock keypair untuk penerima (Peer Bravo)
    final bravoKeyPair = await X25519().newKeyPair();
    final bravoPubKey = await bravoKeyPair.extractPublicKey();
    final bravoPubKeyBase64 = base64.encode(bravoPubKey.bytes);

    // Daftarkan kunci publik Bravo ke service
    encService.registerPeerPublicKey('peer-bravo', bravoPubKeyBase64);

    expect(encService.hasPeerKey('peer-bravo'), isTrue);

    // Enkripsi pesan dari Alpha untuk Bravo
    const originalSecretText = 'Koordinat logistik tersembunyi di posko alpha: -7.250, 112.768';
    final encryptedEnvelope = await encService.encryptForPeer(
      peerId: 'peer-bravo',
      plaintext: originalSecretText,
    );

    // Pastikan ciphertext tidak sama dengan plaintext dan berformat envelope JSON
    expect(encryptedEnvelope, isNot(equals(originalSecretText)));
    expect(encService.isEncryptedPayload(encryptedEnvelope), isTrue);

    // Sekarang simulasikan dekripsi dari sisi Bravo menggunakan shared secret yang sama
    // Bravo menghitung shared secret dengan kunci publik Alpha
    final alphaPubKeyBytes = base64.decode(encService.myPublicKeyBase64);
    final alphaPubKey = SimplePublicKey(alphaPubKeyBytes, type: KeyPairType.x25519);

    final bravoSharedSecret = await X25519().sharedSecretKey(
      keyPair: bravoKeyPair,
      remotePublicKey: alphaPubKey,
    );

    final decodedJson = json.decode(encryptedEnvelope) as Map<String, dynamic>;
    final nonce = base64.decode(decodedJson['nonce'] as String);
    final cipherText = base64.decode(decodedJson['cipher'] as String);
    final macBytes = base64.decode(decodedJson['mac'] as String);

    final decryptedBytes = await AesGcm.with256bits().decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
      secretKey: bravoSharedSecret,
    );

    final decryptedText = utf8.decode(decryptedBytes);
    expect(decryptedText, equals(originalSecretText));
  });

  test('TacticalCoords calculation (distance, bearing, UTM, offset) test', () {
    // Jakarta Monas to Bundaran HI (~2.2 km south)
    const latMonas = -6.175392;
    const lonMonas = 106.827153;
    const latHi = -6.195046;
    const lonHi = 106.823049;

    final dist = TacticalCoords.calculateDistanceMeters(latMonas, lonMonas, latHi, lonHi);
    expect(dist, greaterThan(2000.0));
    expect(dist, lessThan(2500.0));

    final bearing = TacticalCoords.calculateBearing(latMonas, lonMonas, latHi, lonHi);
    // Heading south-southwest (~190°)
    expect(bearing, greaterThan(170.0));
    expect(bearing, lessThan(210.0));

    final cardinal = TacticalCoords.bearingToCardinal(bearing);
    expect(cardinal.contains('S'), isTrue);

    final utmStr = TacticalCoords.toUtmString(latMonas, lonMonas);
    expect(utmStr.contains('48M'), isTrue);

    final offset = TacticalCoords.toMetersOffset(latHi, lonHi, latMonas, lonMonas);
    // Hi is south of Monas -> dy > 0 (down in screen coordinates)
    expect(offset.y, greaterThan(0));
  });

  test('SarWaypoint model serialization and category verification test', () {
    final now = DateTime.now();
    final wp = SarWaypoint(
      id: 'wp-alpha-001',
      name: 'Posko Aju Taktis',
      category: WaypointCategory.camp,
      latitude: -7.2504,
      longitude: 112.7688,
      altitude: 45.0,
      createdAt: now,
      createdBy: 'NODE-ALPH',
      notes: 'Dekat sumber air dan helipad',
    );

    expect(wp.categoryLabel, equals('Posko Aju SAR'));
    expect(wp.categoryIcon, isNotNull);

    // Serialization round trip
    final jsonStr = wp.toJson();
    final parsed = SarWaypoint.fromJson(jsonStr);

    expect(parsed.id, equals('wp-alpha-001'));
    expect(parsed.name, equals('Posko Aju Taktis'));
    expect(parsed.category, equals(WaypointCategory.camp));
    expect(parsed.latitude, closeTo(-7.2504, 0.0001));
    expect(parsed.notes, equals('Dekat sumber air dan helipad'));
  });

  test('Walkie-Talkie Asinkron PTT MessageType.voice payload serialization test', () {
    final now = DateTime.now();
    const mockAudioBase64 = 'AAAAIGZ0eXBtcDQyAAAAAG1wNDJpc29tYXZjMQAAAPxtb292AAAAbG12aGQ=';

    final payloadJson = json.encode({
      'voice_base64': mockAudioBase64,
      'duration_seconds': 6,
      'size_bytes': 18450,
      'codec': 'aac_lc_16k',
    });

    final voiceMsg = MessageModel(
      messageId: 'VOICE-PTT-001',
      senderId: 'SAR-NODE-9',
      senderName: 'Petugas Alfa',
      recipientId: 'BROADCAST',
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 12)),
      messageType: MessageType.voice,
      body: payloadJson,
    );

    expect(voiceMsg.isVoice, isTrue);
    expect(voiceMsg.voiceDurationSeconds, equals(6));
    expect(voiceMsg.voiceBase64Data, equals(mockAudioBase64));

    // Serialization round trip
    final jsonStr = voiceMsg.toJson();
    final parsed = MessageModel.fromJson(jsonStr);

    expect(parsed.messageType, equals(MessageType.voice));
    expect(parsed.isVoice, isTrue);
    expect(parsed.voiceDurationSeconds, equals(6));
    expect(parsed.voiceBase64Data, equals(mockAudioBase64));
  });

  test('LoraModemConfig serialization and bridge simulation test', () async {
    const config = LoraModemConfig(
      frequencyMhz: 915.0,
      spreadingFactor: 10,
      bandwidthKhz: 125,
      txPowerDbm: 20,
    );

    final map = config.toMap();
    expect(map['frequency_mhz'], equals(915.0));
    expect(map['spreading_factor'], equals(10));
    expect(map['bandwidth_khz'], equals(125));
    expect(map['tx_power_dbm'], equals(20));

    final parsedConfig = LoraModemConfig.fromMap(map);
    expect(parsedConfig.frequencyMhz, equals(915.0));
    expect(parsedConfig.spreadingFactor, equals(10));

    final bridge = LoraBridgeService.instance;
    await bridge.connectBridge(LoraBridgeMode.simulatedHardware);

    expect(bridge.isConnected, isTrue);
    expect(bridge.bridgeMode, equals(LoraBridgeMode.simulatedHardware));
    expect(bridge.hardwareInfo.contains('Heltec'), isTrue);

    await bridge.disconnectBridge();
    expect(bridge.isConnected, isFalse);
  });

  test('TacticalAudioService configuration and sound states test', () async {
    final audio = TacticalAudioService.instance;
    await audio.init();

    expect(audio.isSfxEnabled, isTrue);
    expect(audio.isRadarPingEnabled, isTrue);
    expect(audio.isMessageToneEnabled, isTrue);

    await audio.setRadarPing(false);
    expect(audio.isRadarPingEnabled, isFalse);

    await audio.setRadarPing(true);
    expect(audio.isRadarPingEnabled, isTrue);

    await audio.setVibration(false);
    expect(audio.isVibrationEnabled, isFalse);

    await audio.setVibration(true);
    expect(audio.isVibrationEnabled, isTrue);
  });

  test('OfflineMapService Web Mercator tile mathematics and estimation test', () {
    final service = OfflineMapService.instance;

    // Koordinat Jakarta (-6.2088, 106.8456) pada Zoom 12
    const lat = -6.2088;
    const lon = 106.8456;
    const z = 12;

    final tileX = service.lon2tile(lon, z);
    final tileY = service.lat2tile(lat, z);

    expect(tileX, greaterThan(0));
    expect(tileY, greaterThan(0));

    // Reverse tile to coordinates round trip verification
    final revLon = service.tile2lon(tileX, z);
    final revLat = service.tile2lat(tileY, z);

    expect((revLon - lon).abs(), lessThan(1.0));
    expect((revLat - lat).abs(), lessThan(1.0));

    // Estimasi jumlah tile untuk radius 3 km zoom 12-14
    final estTiles = service.estimateTileCount(
      centerLat: lat,
      centerLon: lon,
      radiusKm: 3.0,
      minZoom: 12,
      maxZoom: 14,
    );

    expect(estTiles, greaterThan(0));
    expect(estTiles, lessThan(200));
  });

  test('OfflineMapPack and BreadcrumbPoint model serialization test', () {
    final now = DateTime.now();
    final pack = OfflineMapPack(
      id: 'pack-gunung-lawu-01',
      name: 'Posko Gunung Lawu',
      centerLat: -7.6258,
      centerLon: 111.1925,
      radiusKm: 5.0,
      minZoom: 12,
      maxZoom: 15,
      tileCount: 148,
      sizeBytes: 3200000,
      tileSource: 'opentopo',
      createdAt: now,
    );

    final map = pack.toMap();
    expect(map['id'], equals('pack-gunung-lawu-01'));
    expect(map['radius_km'], equals(5.0));
    expect(pack.formattedSize.contains('MB'), isTrue);

    final parsedPack = OfflineMapPack.fromMap(map);
    expect(parsedPack.name, equals('Posko Gunung Lawu'));
    expect(parsedPack.tileSource, equals('opentopo'));

    // Breadcrumb serialization
    final crumb = BreadcrumbPoint(
      latitude: -7.6260,
      longitude: 111.1930,
      altitude: 1850.5,
      timestamp: now,
    );

    final crumbMap = crumb.toMap();
    expect(crumbMap['latitude'], equals(-7.6260));
    expect(crumbMap['altitude'], equals(1850.5));

    final parsedCrumb = BreadcrumbPoint.fromMap(crumbMap);
    expect(parsedCrumb.latitude, equals(-7.6260));
    expect(parsedCrumb.longitude, equals(111.1930));
  });
}
