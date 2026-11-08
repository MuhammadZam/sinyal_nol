import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceRecordingResult {
  final String base64Audio;
  final int durationSeconds;
  final int sizeBytes;
  final String localFilePath;

  const VoiceRecordingResult({
    required this.base64Audio,
    required this.durationSeconds,
    required this.sizeBytes,
    required this.localFilePath,
  });

  String toPayloadJson() {
    return json.encode({
      'voice_base64': base64Audio,
      'duration_seconds': durationSeconds,
      'size_bytes': sizeBytes,
      'codec': 'aac_lc_16k',
    });
  }
}

class VoiceService {
  static final VoiceService instance = VoiceService._init();
  VoiceService._init();

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  bool _isRecording = false;
  DateTime? _recordStartTime;
  String? _currentRecordingPath;

  String? _currentlyPlayingMessageId;
  StreamSubscription? _playerStateSub;

  final ValueNotifier<String?> playingMessageIdNotifier = ValueNotifier<String?>(null);

  bool get isRecording => _isRecording;

  /// Memulai perekaman PTT suara ultra-kompresi (16kHz Mono AAC ~16kbps)
  Future<bool> startRecording() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        debugPrint('[VoiceService] Izin mikrofon belum diberikan');
        return false;
      }

      final dir = await getTemporaryDirectory();
      final filePath = p.join(dir.path, 'ptt_${DateTime.now().millisecondsSinceEpoch}.m4a');
      _currentRecordingPath = filePath;

      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 16000, // 16 kbps ultra-hemat data mesh (~2 KB per detik!)
        sampleRate: 16000,
        numChannels: 1, // Mono
      );

      await _recorder.start(config, path: filePath);
      _isRecording = true;
      _recordStartTime = DateTime.now();
      return true;
    } catch (e) {
      debugPrint('[VoiceService] Gagal merekam audio: $e');
      _isRecording = false;
      return false;
    }
  }

  /// Menghentikan perekaman dan mengembalikan payload Base64 terkompresi
  Future<VoiceRecordingResult?> stopRecording() async {
    if (!_isRecording) return null;

    try {
      final path = await _recorder.stop();
      _isRecording = false;
      final durationSec = _recordStartTime != null
          ? DateTime.now().difference(_recordStartTime!).inSeconds.clamp(1, 60)
          : 1;

      final targetPath = path ?? _currentRecordingPath;
      if (targetPath == null) return null;

      final file = File(targetPath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final base64Str = base64.encode(bytes);

      return VoiceRecordingResult(
        base64Audio: base64Str,
        durationSeconds: durationSec,
        sizeBytes: bytes.length,
        localFilePath: targetPath,
      );
    } catch (e) {
      debugPrint('[VoiceService] Gagal menghentikan rekaman: $e');
      _isRecording = false;
      return null;
    }
  }

  /// Membatalkan rekaman yang sedang berjalan
  Future<void> cancelRecording() async {
    if (_isRecording) {
      await _recorder.cancel();
      _isRecording = false;
      _currentRecordingPath = null;
    }
  }

  /// Memutar pesan suara dari data Base64
  Future<void> playVoiceMessage(String messageId, String base64Audio) async {
    try {
      if (_currentlyPlayingMessageId == messageId) {
        // Toggle stop
        await stopPlayback();
        return;
      }

      await _player.stop();

      final bytes = base64.decode(base64Audio);
      final dir = await getTemporaryDirectory();
      final tempFile = File(p.join(dir.path, 'play_${messageId.hashCode}.m4a'));
      await tempFile.writeAsBytes(bytes);

      _currentlyPlayingMessageId = messageId;
      playingMessageIdNotifier.value = messageId;

      _playerStateSub?.cancel();
      _playerStateSub = _player.onPlayerComplete.listen((_) {
        _currentlyPlayingMessageId = null;
        playingMessageIdNotifier.value = null;
      });

      await _player.play(DeviceFileSource(tempFile.path));
    } catch (e) {
      debugPrint('[VoiceService] Gagal memutar audio: $e');
      _currentlyPlayingMessageId = null;
      playingMessageIdNotifier.value = null;
    }
  }

  Future<void> stopPlayback() async {
    await _player.stop();
    _currentlyPlayingMessageId = null;
    playingMessageIdNotifier.value = null;
  }

  void dispose() {
    _recorder.dispose();
    _player.dispose();
    _playerStateSub?.cancel();
  }
}
