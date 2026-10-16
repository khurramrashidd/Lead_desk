import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class PlaceInfo {
  PlaceInfo(this.lat, this.lng, this.city, this.area);
  final double lat;
  final double lng;
  final String city;
  final String area;

  String get label => area.isNotEmpty && area != city ? '$area, $city' : city;
}

/// Auto location for walk-ins: GPS -> city/area (works on Android and web, no API key).
class LocationService {
  static Future<PlaceInfo?> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;

    final pos = await Geolocator.getCurrentPosition();
    var city = '';
    var area = '';
    try {
      final uri = Uri.parse(
        'https://api.bigdatacloud.net/data/reverse-geocode-client'
        '?latitude=${pos.latitude}&longitude=${pos.longitude}&localityLanguage=en',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        city = (j['city'] as String?)?.trim() ?? '';
        area = (j['locality'] as String?)?.trim() ?? '';
        if (city.isEmpty) city = (j['principalSubdivision'] as String?) ?? '';
      }
    } catch (_) {
      // offline: keep coordinates only
    }
    return PlaceInfo(pos.latitude, pos.longitude, city, area);
  }
}
