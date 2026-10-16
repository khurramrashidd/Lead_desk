import 'dart:io';
import 'dart:typed_data';

/// Android: the recorder saved a file in the temp folder.
Future<Uint8List> readRecordedAudio(String path) async {
  final file = File(path);
  final bytes = await file.readAsBytes();
  try {
    await file.delete(); // don't leave voice notes on the phone
  } catch (_) {}
  return bytes;
}
