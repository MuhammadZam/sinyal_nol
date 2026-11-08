import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TacticalAudioService {
  static final TacticalAudioService instance = TacticalAudioService._init();
  TacticalAudioService._init();

  final AudioPlayer _sfxPlayer = AudioPlayer();
  final AudioPlayer _alertPlayer = AudioPlayer();

  bool _isSfxEnabled = true;
  bool _isAutoSquawkEnabled = true;
  bool _isRogerBeepEnabled = true;
  bool _isRadarPingEnabled = true;
  bool _isMessageToneEnabled = true;
  bool _isVibrationEnabled = true;

  bool get isSfxEnabled => _isSfxEnabled;
  bool get isAutoSquawkEnabled => _isAutoSquawkEnabled;
  bool get isRogerBeepEnabled => _isRogerBeepEnabled;
  bool get isRadarPingEnabled => _isRadarPingEnabled;
  bool get isMessageToneEnabled => _isMessageToneEnabled;
  bool get isVibrationEnabled => _isVibrationEnabled;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isSfxEnabled = prefs.getBool('is_sfx_enabled') ?? true;
    _isAutoSquawkEnabled = prefs.getBool('is_auto_squawk_enabled') ?? true;
    _isRogerBeepEnabled = prefs.getBool('is_roger_beep_enabled') ?? true;
    _isRadarPingEnabled = prefs.getBool('is_radar_ping_enabled') ?? true;
    _isMessageToneEnabled = prefs.getBool('is_message_tone_enabled') ?? true;
    _isVibrationEnabled = prefs.getBool('is_vibration_enabled') ?? true;
  }

  Future<void> setSfxEnabled(bool value) async {
    _isSfxEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_sfx_enabled', value);
  }

  Future<void> setAutoSquawk(bool value) async {
    _isAutoSquawkEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_auto_squawk_enabled', value);
  }

  Future<void> setRogerBeep(bool value) async {
    _isRogerBeepEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_roger_beep_enabled', value);
  }

  Future<void> setRadarPing(bool value) async {
    _isRadarPingEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_radar_ping_enabled', value);
  }

  Future<void> setMessageTone(bool value) async {
    _isMessageToneEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_message_tone_enabled', value);
  }

  Future<void> setVibration(bool value) async {
    _isVibrationEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_vibration_enabled', value);
  }

  // --- Suara Peristiwa Taktis ---

  /// 1. Suara Sonar Ping saat ada Node/Rekan baru masuk ke dalam Radar jangkauan
  Future<void> playNodeConnectedSonar() async {
    if (_isVibrationEnabled) {
      HapticFeedback.mediumImpact();
    }
    if (!_isSfxEnabled || !_isRadarPingEnabled) return;

    try {
      final wav = _generateSonarPingWav();
      await _sfxPlayer.play(BytesSource(wav));
    } catch (e) {
      debugPrint('[TacticalAudio] Sonar error: $e');
    }
  }

  /// 2. Suara Notifikasi Pesan Masuk (Text / Info Taktis Baru)
  Future<void> playIncomingMessageTone() async {
    if (_isVibrationEnabled) {
      HapticFeedback.lightImpact();
    }
    if (!_isSfxEnabled || !_isMessageToneEnabled) return;

    try {
      final wav = _generateMessageChirpWav();
      await _sfxPlayer.play(BytesSource(wav));
    } catch (e) {
      debugPrint('[TacticalAudio] Msg tone error: $e');
    }
  }

  /// 3. Suara Alarm Darurat SOS (High-Priority Pulsed Siren)
  Future<void> playSosAlert() async {
    if (_isVibrationEnabled) {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 150), () => HapticFeedback.heavyImpact());
    }
    if (!_isSfxEnabled) return;

    try {
      final wav = _generateSosSirenWav();
      await _alertPlayer.play(BytesSource(wav));
    } catch (e) {
      debugPrint('[TacticalAudio] SOS alert error: $e');
    }
  }

  /// 4. Suara Waypoint / Posisi Peta Diperbarui
  Future<void> playWaypointTone() async {
    if (_isVibrationEnabled) {
      HapticFeedback.selectionClick();
    }
    if (!_isSfxEnabled) return;

    try {
      final wav = _generateWaypointHarmonicWav();
      await _sfxPlayer.play(BytesSource(wav));
    } catch (e) {
      debugPrint('[TacticalAudio] Waypoint tone error: $e');
    }
  }

  /// 5. Suara Mic Keying Click saat tombol PTT ditekan
  Future<void> playPttKeyClick() async {
    if (_isVibrationEnabled) {
      HapticFeedback.selectionClick();
    }
    if (!_isSfxEnabled) return;

    try {
      final wav = _generateToneWav(frequency: 1800, durationMs: 35, volume: 0.4);
      await _sfxPlayer.play(BytesSource(wav));
    } catch (e) {
      debugPrint('[TacticalAudio] Sfx error: $e');
    }
  }

  /// 6. Suara Roger Beep khas radio militer / Quindar saat PTT selesai
  Future<void> playRogerBeep() async {
    if (!_isSfxEnabled || !_isRogerBeepEnabled) return;
    try {
      final wav = _generateTwoToneRogerBeep();
      await _sfxPlayer.play(BytesSource(wav));
    } catch (e) {
      debugPrint('[TacticalAudio] Sfx error: $e');
    }
  }

  /// 7. Suara Derau Radio (Squelch Burst) saat ada transmisi suara Walkie-Talkie masuk
  Future<void> playIncomingSquawk() async {
    if (!_isSfxEnabled) return;
    try {
      final wav = _generateNoiseSquelchWav(durationMs: 110);
      await _sfxPlayer.play(BytesSource(wav));
    } catch (e) {
      debugPrint('[TacticalAudio] Sfx error: $e');
    }
  }

  // --- Algoritma Generator Audio PCM (In-Memory Synthesizer) ---

  /// Generator Sonar Radar Ping (880 Hz -> 1320 Hz dengan Exponential Decay)
  Uint8List _generateSonarPingWav() {
    const sampleRate = 22050;
    const duration = 0.22; // 220 ms
    final totalSamples = (duration * sampleRate).toInt();
    final pcm = Int16List(totalSamples);

    for (int i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      final decay = math.exp(-t * 9.0); // Smooth sonar decay
      // Pitch slide dari 880 Hz ke 1320 Hz
      final freq = 880.0 + (440.0 * (i / totalSamples));
      final sample = (math.sin(2 * math.pi * freq * t) * 28000 * decay).toInt();
      pcm[i] = sample;
    }

    return _createWavHeader(pcm, sampleRate);
  }

  /// Generator Chirp Notifikasi Pesan Masuk (Dual-Tone Chirp 950 Hz -> 1250 Hz)
  Uint8List _generateMessageChirpWav() {
    const sampleRate = 22050;
    const tone1Dur = 0.045; // 45ms
    const gapDur = 0.020;   // 20ms
    const tone2Dur = 0.060; // 60ms
    final totalSamples = ((tone1Dur + gapDur + tone2Dur) * sampleRate).toInt();
    final pcm = Int16List(totalSamples);

    final t1Samples = (tone1Dur * sampleRate).toInt();
    final gapSamples = (gapDur * sampleRate).toInt();

    // Tone 1: 950 Hz
    for (int i = 0; i < t1Samples; i++) {
      final t = i / sampleRate;
      final decay = 1.0 - (i / t1Samples * 0.3);
      pcm[i] = (math.sin(2 * math.pi * 950 * t) * 22000 * decay).toInt();
    }

    // Gap: Silence
    for (int i = t1Samples; i < t1Samples + gapSamples; i++) {
      pcm[i] = 0;
    }

    // Tone 2: 1250 Hz
    final t2Start = t1Samples + gapSamples;
    for (int i = t2Start; i < totalSamples; i++) {
      final t = (i - t2Start) / sampleRate;
      final decay = 1.0 - ((i - t2Start) / (totalSamples - t2Start) * 0.4);
      pcm[i] = (math.sin(2 * math.pi * 1250 * t) * 24000 * decay).toInt();
    }

    return _createWavHeader(pcm, sampleRate);
  }

  /// Generator Alarm SOS Darurat (3 Rapid Alternating Pulses: 850 Hz / 1400 Hz)
  Uint8List _generateSosSirenWav() {
    const sampleRate = 22050;
    const pulseDur = 0.09; // 90ms per pulse
    const totalPulses = 4;
    final totalSamples = (pulseDur * totalPulses * sampleRate).toInt();
    final pcm = Int16List(totalSamples);
    final pulseSamples = (pulseDur * sampleRate).toInt();

    for (int p = 0; p < totalPulses; p++) {
      final freq = (p % 2 == 0) ? 850.0 : 1400.0;
      final offset = p * pulseSamples;
      for (int i = 0; i < pulseSamples; i++) {
        final t = i / sampleRate;
        final envelope = math.sin(math.pi * (i / pulseSamples)); // Bell envelope
        pcm[offset + i] = (math.sin(2 * math.pi * freq * t) * 30000 * envelope).toInt();
      }
    }

    return _createWavHeader(pcm, sampleRate);
  }

  /// Generator Akor Harmonik Waypoint Peta (Triad 523Hz -> 659Hz -> 784Hz)
  Uint8List _generateWaypointHarmonicWav() {
    const sampleRate = 22050;
    const noteDur = 0.055; // 55ms
    final totalSamples = (noteDur * 3 * sampleRate).toInt();
    final pcm = Int16List(totalSamples);
    final noteSamples = (noteDur * sampleRate).toInt();

    final freqs = [523.25, 659.25, 783.99]; // C5, E5, G5
    for (int n = 0; n < 3; n++) {
      final offset = n * noteSamples;
      for (int i = 0; i < noteSamples; i++) {
        final t = i / sampleRate;
        final decay = 1.0 - (i / noteSamples * 0.4);
        pcm[offset + i] = (math.sin(2 * math.pi * freqs[n] * t) * 20000 * decay).toInt();
      }
    }

    return _createWavHeader(pcm, sampleRate);
  }

  /// Generator 2-Tone Roger Beep (1200 Hz -> 1800 Hz)
  Uint8List _generateTwoToneRogerBeep() {
    const sampleRate = 22050;
    const tone1Duration = 0.075;
    const tone2Duration = 0.075;
    final totalSamples = ((tone1Duration + tone2Duration) * sampleRate).toInt();
    final pcm = Int16List(totalSamples);
    final tone1Samples = (tone1Duration * sampleRate).toInt();

    // Nada 1: 1200 Hz
    for (int i = 0; i < tone1Samples; i++) {
      final t = i / sampleRate;
      pcm[i] = (math.sin(2 * math.pi * 1200 * t) * 18000).toInt();
    }

    // Nada 2: 1800 Hz
    for (int i = tone1Samples; i < totalSamples; i++) {
      final t = (i - tone1Samples) / sampleRate;
      pcm[i] = (math.sin(2 * math.pi * 1800 * t) * 18000).toInt();
    }

    return _createWavHeader(pcm, sampleRate);
  }

  /// Generator Nada Tunggal
  Uint8List _generateToneWav({required double frequency, required int durationMs, double volume = 0.5}) {
    const sampleRate = 22050;
    final totalSamples = ((durationMs / 1000.0) * sampleRate).toInt();
    final pcm = Int16List(totalSamples);

    for (int i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      pcm[i] = (math.sin(2 * math.pi * frequency * t) * 32767 * volume).toInt();
    }

    return _createWavHeader(pcm, sampleRate);
  }

  /// Generator Derau Radio Squelch
  Uint8List _generateNoiseSquelchWav({required int durationMs}) {
    const sampleRate = 22050;
    final totalSamples = ((durationMs / 1000.0) * sampleRate).toInt();
    final pcm = Int16List(totalSamples);
    final random = math.Random();

    for (int i = 0; i < totalSamples; i++) {
      final decay = 1.0 - (i / totalSamples);
      final rawNoise = (random.nextDouble() * 2.0 - 1.0);
      pcm[i] = (rawNoise * 14000 * decay).toInt();
    }

    return _createWavHeader(pcm, sampleRate);
  }

  /// Header Standar RIFF/WAVE (16-bit Mono PCM)
  Uint8List _createWavHeader(Int16List pcmData, int sampleRate) {
    final byteData = ByteData(44 + pcmData.lengthInBytes);

    // "RIFF"
    byteData.setUint8(0, 0x52);
    byteData.setUint8(1, 0x49);
    byteData.setUint8(2, 0x46);
    byteData.setUint8(3, 0x46);
    byteData.setUint32(4, 36 + pcmData.lengthInBytes, Endian.little);
    // "WAVE"
    byteData.setUint8(8, 0x57);
    byteData.setUint8(9, 0x41);
    byteData.setUint8(10, 0x56);
    byteData.setUint8(11, 0x45);
    // "fmt "
    byteData.setUint8(12, 0x66);
    byteData.setUint8(13, 0x6D);
    byteData.setUint8(14, 0x74);
    byteData.setUint8(15, 0x20);
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little);
    byteData.setUint16(22, 1, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little);
    byteData.setUint16(32, 2, Endian.little);
    byteData.setUint16(34, 16, Endian.little);
    // "data"
    byteData.setUint8(36, 0x64);
    byteData.setUint8(37, 0x61);
    byteData.setUint8(38, 0x74);
    byteData.setUint8(39, 0x61);
    byteData.setUint32(40, pcmData.lengthInBytes, Endian.little);

    final result = byteData.buffer.asUint8List();
    final pcmBytes = pcmData.buffer.asUint8List();
    result.setRange(44, 44 + pcmData.lengthInBytes, pcmBytes);

    return result;
  }

  void dispose() {
    _sfxPlayer.dispose();
    _alertPlayer.dispose();
  }
}
