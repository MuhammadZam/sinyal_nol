import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Layanan Kriptografi End-to-End (E2EE) Taktis
/// Menggunakan Curve25519 (X25519) untuk pertukaran kunci Diffie-Hellman asimetris
/// dan AES-256-GCM (Authenticated Encryption with Associated Data) untuk kerahasiaan & integritas.
class EncryptionService {
  static final EncryptionService instance = EncryptionService._internal();
  factory EncryptionService() => instance;
  EncryptionService._internal();

  final _keyExchangeAlgorithm = X25519();
  final _cipherAlgorithm = AesGcm.with256bits();

  SimpleKeyPair? _myKeyPair;
  SimplePublicKey? _myPublicKey;
  String _myPublicKeyBase64 = '';

  // Cache kunci publik milik peer perangkat lain (PeerID -> Public Key Base64)
  final Map<String, String> _peerPublicKeys = {};

  // Daftar peer yang telah terverifikasi secara manual (misal via scan QR code)
  final Set<String> _verifiedPeers = {};

  bool get isInitialized => _myKeyPair != null;
  String get myPublicKeyBase64 => _myPublicKeyBase64;

  /// Inisialisasi pasangan kunci kriptografis lokal
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final storedPrivKey = prefs.getString('e2ee_x25519_private_key');
    final storedPubKey = prefs.getString('e2ee_x25519_public_key');

    if (storedPrivKey != null && storedPubKey != null) {
      final privBytes = base64.decode(storedPrivKey);
      final pubBytes = base64.decode(storedPubKey);

      _myPublicKey = SimplePublicKey(pubBytes, type: KeyPairType.x25519);
      _myKeyPair = SimpleKeyPairData(
        privBytes,
        publicKey: _myPublicKey!,
        type: KeyPairType.x25519,
      );
      _myPublicKeyBase64 = storedPubKey;
    } else {
      // Buat pasangan kunci baru jika belum pernah dibuat
      _myKeyPair = await _keyExchangeAlgorithm.newKeyPair();
      _myPublicKey = await _myKeyPair!.extractPublicKey();

      final privData = await _myKeyPair!.extract();
      final privBytes = privData.bytes;
      final pubBytes = _myPublicKey!.bytes;

      _myPublicKeyBase64 = base64.encode(pubBytes);
      await prefs.setString('e2ee_x25519_private_key', base64.encode(privBytes));
      await prefs.setString('e2ee_x25519_public_key', _myPublicKeyBase64);
    }
  }

  /// Mendaftarkan kunci publik milik peer lain
  void registerPeerPublicKey(String peerId, String publicKeyBase64, {bool isVerified = false}) {
    if (publicKeyBase64.isNotEmpty) {
      _peerPublicKeys[peerId] = publicKeyBase64;
      if (isVerified) {
        _verifiedPeers.add(peerId);
      }
    }
  }

  /// Menandai peer sebagai terverifikasi fisik
  void markPeerVerified(String peerId) {
    _verifiedPeers.add(peerId);
  }

  /// Memeriksa apakah kita memiliki kunci publik dari peer tertentu
  bool hasPeerKey(String? peerId) {
    if (peerId == null || peerId.isEmpty || peerId == 'BROADCAST') return false;
    return _peerPublicKeys.containsKey(peerId);
  }

  /// Memeriksa apakah peer tersebut telah diverifikasi identitasnya
  bool isPeerVerified(String? peerId) {
    if (peerId == null) return false;
    return _verifiedPeers.contains(peerId);
  }

  String? getPeerPublicKey(String peerId) => _peerPublicKeys[peerId];

  /// Enkripsi pesan langsung (Direct Message) untuk peer tujuan
  /// Menghasilkan amplop JSON terenkripsi AES-256-GCM
  Future<String> encryptForPeer({
    required String peerId,
    required String plaintext,
  }) async {
    if (!hasPeerKey(peerId) || _myKeyPair == null) {
      // Fallback: Jika peer belum memiliki kunci publik, jangan enkripsi (atau biarkan plaintext)
      return plaintext;
    }

    try {
      final peerKeyBase64 = _peerPublicKeys[peerId]!;
      final peerKeyBytes = base64.decode(peerKeyBase64);
      final remotePubKey = SimplePublicKey(peerKeyBytes, type: KeyPairType.x25519);

      // 1. Turunkan Secret Bersama (Shared Secret) melalui Diffie-Hellman
      final sharedSecretKey = await _keyExchangeAlgorithm.sharedSecretKey(
        keyPair: _myKeyPair!,
        remotePublicKey: remotePubKey,
      );

      // 2. Enkripsi teks menggunakan AES-256-GCM
      final secretBox = await _cipherAlgorithm.encrypt(
        utf8.encode(plaintext),
        secretKey: sharedSecretKey,
      );

      // 3. Kemas ke dalam envelope JSON yang aman
      final envelope = {
        'e2ee': 1,
        'nonce': base64.encode(secretBox.nonce),
        'cipher': base64.encode(secretBox.cipherText),
        'mac': base64.encode(secretBox.mac.bytes),
      };

      return json.encode(envelope);
    } catch (_) {
      // Jika terjadi kegagalan kalkulasi kriptografi, kembalikan teks asli
      return plaintext;
    }
  }

  /// Dekripsi pesan masuk dari pengirim
  /// Hanya node yang memiliki private key yang cocok yang dapat membaca pesan ini
  Future<String> decryptFromPeer({
    required String senderPeerId,
    required String payload,
  }) async {
    if (!payload.startsWith('{') || _myKeyPair == null) {
      return payload; // Bukan payload JSON terenkripsi
    }

    try {
      final decoded = json.decode(payload);
      if (decoded is! Map<String, dynamic> || decoded['e2ee'] != 1) {
        return payload; // Bukan format enkripsi E2EE SinyalNol
      }

      if (!hasPeerKey(senderPeerId)) {
        return '[Pesan Terenkripsi E2EE - Kunci Publik Pengirim Belum Ditemukan]';
      }

      final peerKeyBase64 = _peerPublicKeys[senderPeerId]!;
      final peerKeyBytes = base64.decode(peerKeyBase64);
      final remotePubKey = SimplePublicKey(peerKeyBytes, type: KeyPairType.x25519);

      // 1. Turunkan Secret Bersama yang identik
      final sharedSecretKey = await _keyExchangeAlgorithm.sharedSecretKey(
        keyPair: _myKeyPair!,
        remotePublicKey: remotePubKey,
      );

      final nonce = base64.decode(decoded['nonce'] as String);
      final cipherText = base64.decode(decoded['cipher'] as String);
      final macBytes = base64.decode(decoded['mac'] as String);

      final secretBox = SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(macBytes),
      );

      // 2. Dekripsi dan otentikasi tag MAC
      final clearBytes = await _cipherAlgorithm.decrypt(
        secretBox,
        secretKey: sharedSecretKey,
      );

      return utf8.decode(clearBytes);
    } catch (_) {
      return '[Gagal Mendekripsi Pesan: Kunci Tidak Cocok atau Data Dimanipulasi]';
    }
  }

  /// Helper untuk mengecek apakah string adalah envelope terenkripsi
  bool isEncryptedPayload(String body) {
    if (!body.startsWith('{')) return false;
    try {
      final decoded = json.decode(body);
      return decoded is Map<String, dynamic> && decoded['e2ee'] == 1;
    } catch (_) {
      return false;
    }
  }
}
