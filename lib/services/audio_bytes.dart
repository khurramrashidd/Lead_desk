/// Reads a finished voice recording as bytes.
/// Android gives a file path; the browser gives a temporary blob URL.
library;

export 'audio_bytes_io.dart' if (dart.library.js_interop) 'audio_bytes_web.dart';
