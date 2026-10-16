import 'package:flutter/foundation.dart';

/// Your Firebase Hosting address. Change this after `firebase deploy --only hosting`.
/// Used for QR codes when the app runs on a phone (on the web we use the current address).
const kPublicWebUrl = 'https://YOUR-PROJECT-ID.web.app';

String publicBaseUrl() => kIsWeb ? Uri.base.origin : kPublicWebUrl;

/// Link a prospect opens. `src` tells the reports where the lead came from.
String chatLink(String src) => '${publicBaseUrl()}/#/chat?src=$src';
String formLink(String src) => '${publicBaseUrl()}/#/form?src=$src';
