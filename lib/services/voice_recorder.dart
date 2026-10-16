import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// A recorded voice note, ready to send.
class VoiceNote {
  VoiceNote(this.base64, this.mime, this.seconds);
  final String base64;
  final String mime;
  final int seconds;
}

/// Records short voice notes on Android and in the browser (web chat via QR).
/// Audio is kept small so it fits inside a Firestore document.
class VoiceRecorder {
  final _rec = AudioRecorder();
  DateTime? _startedAt;
  String _mime = 'audio/webm';
  bool _isWav = false;

  /// Longest note allowed (WAV is big, so it gets less time).
  int get maxSeconds => _isWav ? 20 : 60;

  Future<bool> start() async {
    if (!await _rec.hasPermission()) return false;

    AudioEncoder encoder;
    String path = '';
    if (kIsWeb) {
      if (await _rec.isEncoderSupported(AudioEncoder.opus)) {
        encoder = AudioEncoder.opus; // Chrome, Edge, Firefox
        _mime = 'audio/webm';
      } else if (await _rec.isEncoderSupported(AudioEncoder.aacLc)) {
        encoder = AudioEncoder.aacLc; // Safari
        _mime = 'audio/mp4';
      } else {
        encoder = AudioEncoder.wav;
        _mime = 'audio/wav';
      }
    } else {
      encoder = AudioEncoder.aacLc;
      _mime = 'audio/mp4';
      final dir = await getTemporaryDirectory();
      path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    }
    _isWav = encoder == AudioEncoder.wav;

    await _rec.start(
      RecordConfig(encoder: encoder, bitRate: 32000, sampleRate: 16000, numChannels: 1),
      path: path,
    );
    _startedAt = DateTime.now();
    return true;
  }

  int get elapsedSeconds => _startedAt == null ? 0 : DateTime.now().difference(_startedAt!).inSeconds;

  /// Stops and returns the note, or null if it was too short or too big.
  Future<VoiceNote?> stop() async {
    final secs = elapsedSeconds;
    final path = await _rec.stop();
    _startedAt = null;
    if (path == null || secs < 1) return null;
    final bytes = await XFile(path).readAsBytes();
    if (bytes.length > 700 * 1024) return null; // Firestore documents must stay under 1 MB
    return VoiceNote(base64Encode(bytes), _mime, secs);
  }

  Future<void> cancel() async {
    await _rec.cancel();
    _startedAt = null;
  }

  Future<void> dispose() => _rec.dispose();
}
