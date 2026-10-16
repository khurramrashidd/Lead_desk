import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Settings the institute controls from the Admin console: which AI keys to use,
/// and which messaging channels are connected. Both live in Firestore and are
/// read by the Cloud Functions, so nothing needs redeploying to change them.
class OpsService {
  static final _db = FirebaseFirestore.instance;
  // Same region the functions are deployed to.
  static final _fns = FirebaseFunctions.instanceFor(region: 'asia-south1');

  // ------------------------------------------------------------- AI providers
  static DocumentReference<Map<String, dynamic>> get aiDoc => _db.doc('config/ai');
  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchAi() => aiDoc.snapshots();
  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchAiHealth() => _db.doc('config/aiHealth').snapshots();

  static List<AiProvider> providersFrom(Map<String, dynamic>? data) {
    final raw = (data?['providers'] as List?) ?? const [];
    return raw
        .whereType<Map>()
        .map((m) => AiProvider.fromMap(m.cast<String, dynamic>()))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  static Future<void> saveProviders(List<AiProvider> providers, {String? thinking}) async {
    await aiDoc.set({
      'providers': [
        for (var i = 0; i < providers.length; i++) providers[i].copyWith(order: i).toMap(),
      ],
      'thinking': ?thinking,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> saveThinking(String level) =>
      aiDoc.set({'thinking': level, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

  /// One tiny call on that key, so a wrong key is obvious long before judging.
  static Future<({bool ok, int ms, String detail})> testAiKey(String apiKey, String model) async {
    final res = await _fns.httpsCallable('checkAiProvider').call<Map<String, dynamic>>({
      'apiKey': apiKey,
      'model': model,
    });
    final d = res.data;
    return (ok: d['ok'] == true, ms: (d['ms'] as num?)?.toInt() ?? 0, detail: '${d['detail'] ?? ''}');
  }

  /// Wakes the brain so the first real reply is not a cold start.
  static Future<int> warmUp() async {
    final res = await _fns.httpsCallable('warmUp').call<Map<String, dynamic>>();
    return (res.data['providers'] as num?)?.toInt() ?? 0;
  }

  // ----------------------------------------------------------------- channels
  static DocumentReference<Map<String, dynamic>> get channelsDoc => _db.doc('config/channels');
  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchChannels() => channelsDoc.snapshots();

  static Future<void> saveChannels(Map<String, dynamic> values) =>
      channelsDoc.set({...values, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

  static Future<({bool ok, String detail})> testWhatsApp() async {
    final res = await _fns.httpsCallable('checkWhatsApp').call<Map<String, dynamic>>();
    final d = res.data;
    final extra = [d['name'], d['number']].where((e) => e != null && '$e'.isNotEmpty).join(' · ');
    return (ok: d['ok'] == true, detail: '${d['detail'] ?? ''}${extra.isEmpty ? '' : ' — $extra'}');
  }

  static Future<({bool ok, String detail})> testTelegram({String? webhookUrl}) async {
    final res = await _fns.httpsCallable('checkTelegram').call<Map<String, dynamic>>({
      if (webhookUrl != null && webhookUrl.isNotEmpty) 'webhookUrl': webhookUrl,
    });
    final d = res.data;
    return (ok: d['ok'] == true, detail: '${d['detail'] ?? ''}');
  }
}

/// One Gemini key + the model it should use.
class AiProvider {
  AiProvider({
    required this.id,
    required this.label,
    required this.apiKey,
    required this.model,
    this.enabled = true,
    this.order = 0,
  });

  final String id;
  String label;
  String apiKey;
  String model;
  bool enabled;
  int order;

  static const commonModels = [
    'gemini-3.5-flash-lite',
    'gemini-3.8-flash',
    'gemini-3.6-flash',
    'gemini-3.1-flash-lite',
    'gemma-4',
  ];

  factory AiProvider.fromMap(Map<String, dynamic> m) => AiProvider(
        id: m['id'] as String? ?? UniqueKeyish.next(),
        label: m['label'] as String? ?? '',
        apiKey: m['apiKey'] as String? ?? '',
        model: m['model'] as String? ?? commonModels.first,
        enabled: m['enabled'] as bool? ?? true,
        order: (m['order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'apiKey': apiKey,
        'model': model,
        'enabled': enabled,
        'order': order,
      };

  AiProvider copyWith({int? order}) => AiProvider(
        id: id,
        label: label,
        apiKey: apiKey,
        model: model,
        enabled: enabled,
        order: order ?? this.order,
      );

  /// Never show a whole key on screen.
  String get maskedKey {
    if (apiKey.length <= 10) return '••••••';
    return '${apiKey.substring(0, 6)}…${apiKey.substring(apiKey.length - 4)}';
  }
}

/// Tiny id generator so a new provider row has a stable key.
class UniqueKeyish {
  static int _n = 0;
  static String next() => 'k${DateTime.now().millisecondsSinceEpoch}_${_n++}';
}
