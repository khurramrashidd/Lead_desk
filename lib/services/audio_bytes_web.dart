import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Web: the recorder returned a blob: URL that only this tab can read.
Future<Uint8List> readRecordedAudio(String blobUrl) async {
  final res = await http.get(Uri.parse(blobUrl));
  return res.bodyBytes;
}
