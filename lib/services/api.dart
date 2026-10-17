import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

/// Calls the `api` Cloud Function with the signed-in user's Firebase ID token.
/// (Plain HTTP, so no extra Flutter package is needed.)
class Api {
  Api._();

  static String get projectId => Firebase.app().options.projectId;

  /// https://asia-south1-<project>.cloudfunctions.net
  static String get functionsBase => 'https://asia-south1-$projectId.cloudfunctions.net';

  static String fn(String name) => '$functionsBase/$name';

  static Future<Map<String, dynamic>> call(String route, [Map<String, dynamic> body = const {}]) async {
    final user = FirebaseAuth.instance.currentUser;
    final token = user == null ? null : await user.getIdToken();
    final res = await http
        .post(
          Uri.parse('${fn('api')}/$route'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 120));
    Map<String, dynamic> data;
    try {
      data = (jsonDecode(res.body) as Map).cast<String, dynamic>();
    } catch (_) {
      data = {'ok': false, 'detail': 'HTTP ${res.statusCode}: ${res.body.length > 200 ? res.body.substring(0, 200) : res.body}'};
    }
    if (res.statusCode >= 400 && data['ok'] != false) data['ok'] = false;
    // The app was published before the backend: say so plainly instead of "unknown route".
    if ('${data['detail'] ?? ''}'.startsWith('unknown route')) {
      data['detail'] = 'The server is older than this app. Run "deploy" (backend) on the laptop, then try again.';
    }
    return data;
  }

  /// Like [call] but throws with the server's message when it did not work.
  static Future<Map<String, dynamic>> run(String route, [Map<String, dynamic> body = const {}]) async {
    final d = await call(route, body);
    if (d['ok'] != true) throw ApiException('${d['detail'] ?? 'Request failed'}');
    return d;
  }
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
