import 'package:cloud_firestore/cloud_firestore.dart';

import 'api.dart';

/// Settings the institute controls from the Admin console: which AI keys to use and which
/// messaging channels are connected. Both live in Firestore (admin-only) and are read by the
/// Cloud Functions, so nothing needs redeploying to change them.
class OpsService {
  static final _db = FirebaseFirestore.instance;

  // ------------------------------------------------------------- AI providers
  static DocumentReference<Map<String, dynamic>> get aiDoc => _db.doc('config/ai');
  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchAi() => aiDoc.snapshots();
  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchAiHealth() => _db.doc('config/aiHealth').snapshots();

  static List<AiProvider> providersFrom(Map<String, dynamic>? data) {
    final raw = (data?['providers'] as List?) ?? const [];
    return raw.whereType<Map>().map((m) => AiProvider.fromMap(m.cast<String, dynamic>())).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  static Future<void> saveProviders(List<AiProvider> providers, {String? thinking}) async {
    await aiDoc.set({
      'providers': [for (var i = 0; i < providers.length; i++) providers[i].copyWith(order: i).toMap()],
      'thinking': ?thinking,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> saveThinking(String level) =>
      aiDoc.set({'thinking': level, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

  /// One tiny call on that key, so a wrong key is obvious long before judging.
  static Future<({bool ok, int ms, String detail})> testAiKey(String kind, String apiKey, String model) async {
    final d = await Api.call('checkAi', {'kind': kind, 'apiKey': apiKey, 'model': model});
    return (ok: d['ok'] == true, ms: (d['ms'] as num?)?.toInt() ?? 0, detail: '${d['detail'] ?? ''}');
  }

  /// Wakes the brain so the first real reply is not a cold start.
  static Future<String> warmUp() async {
    final d = await Api.run('warmUp');
    return '${d['used'] ?? ''} answered in ${d['ms'] ?? '?'} ms · ${d['providers'] ?? 0} keys in the pool';
  }

  static Future<List<Map<String, dynamic>>> envProviders() async {
    final d = await Api.call('aiProviders');
    return ((d['env'] as List?) ?? const []).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }

  // ----------------------------------------------------------------- channels
  static DocumentReference<Map<String, dynamic>> get channelsDoc => _db.doc('config/channels');
  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchChannels() => channelsDoc.snapshots();

  static Future<void> saveChannels(Map<String, dynamic> values) =>
      channelsDoc.set({...values, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

  static Future<({bool ok, String detail})> testWhatsApp() async {
    final d = await Api.call('checkWhatsApp');
    final extra = [d['name'], d['number']].where((e) => e != null && '$e'.isNotEmpty).join(' · ');
    return (ok: d['ok'] == true, detail: '${d['detail'] ?? ''}${extra.isEmpty ? '' : ' — $extra'}');
  }

  static Future<({bool ok, String detail})> testTelegram({bool setWebhook = true}) async {
    final d = await Api.call('checkTelegram', {'setWebhook': setWebhook});
    return (ok: d['ok'] == true, detail: '${d['detail'] ?? ''}');
  }

  static Future<({bool ok, String detail, String serviceAccount})> testCalendar() async {
    final d = await Api.call('checkCalendar');
    return (ok: d['ok'] == true, detail: '${d['detail'] ?? ''}', serviceAccount: '${d['serviceAccount'] ?? ''}');
  }

  static Future<Map<String, dynamic>> endpoints() => Api.call('endpoints');
}

/// One AI key + the model it should use. kind: gemini | groq | openrouter.
class AiProvider {
  AiProvider({
    required this.id,
    required this.label,
    required this.apiKey,
    required this.model,
    this.kind = 'gemini',
    this.enabled = true,
    this.order = 0,
  });

  final String id;
  String label;
  String apiKey;
  String model;
  String kind;
  bool enabled;
  int order;

  static const kinds = ['gemini', 'groq', 'openrouter'];

  static const modelsFor = {
    // Live models, October 2026 (old names are mapped to these on the server too).
    'gemini': ['gemini-3.6-flash', 'gemini-3.8-flash', 'gemini-3.5-flash-lite', 'gemini-3.1-flash-lite'],
    'groq': ['openai/gpt-oss-120b', 'openai/gpt-oss-20b', 'qwen/qwen3.8-27b'],
    'openrouter': ['openrouter/free'],
  };

  static String guessKind(String key) {
    if (key.startsWith('gsk_')) return 'groq';
    if (key.startsWith('sk-or-')) return 'openrouter';
    return 'gemini';
  }

  factory AiProvider.fromMap(Map<String, dynamic> m) {
    final key = m['apiKey'] as String? ?? '';
    final kind = m['kind'] as String? ?? guessKind(key);
    return AiProvider(
      id: m['id'] as String? ?? UniqueKeyish.next(),
      label: m['label'] as String? ?? '',
      apiKey: key,
      model: m['model'] as String? ?? (modelsFor[kind] ?? modelsFor['gemini']!).first,
      kind: kind,
      enabled: m['enabled'] as bool? ?? true,
      order: (m['order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'apiKey': apiKey,
        'model': model,
        'kind': kind,
        'enabled': enabled,
        'order': order,
      };

  AiProvider copyWith({int? order}) => AiProvider(
        id: id,
        label: label,
        apiKey: apiKey,
        model: model,
        kind: kind,
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
