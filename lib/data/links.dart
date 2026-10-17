import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Where "Talk on WhatsApp", "Talk on Telegram" and the website QR codes lead.
///
/// Stored in Firestore `config/public` (anyone can read it, only an admin can change it in
/// Admin → Channels → Public links). The defaults below work before that document exists.
class PublicLinks {
  const PublicLinks({
    required this.whatsappNumber,
    required this.telegramBot,
    required this.formUrl,
    this.whatsappText = 'Hi Asha 👋',
  });

  /// WhatsApp number connected to the Cloud API, digits only with the country code.
  final String whatsappNumber;

  /// Telegram bot username without the @.
  final String telegramBot;

  /// Google Form (enquiry form) link.
  final String formUrl;

  /// The message WhatsApp pre-fills, so one tap on Send starts the chat.
  final String whatsappText;

  static const defaults = PublicLinks(
    whatsappNumber: '15551993241',
    telegramBot: 'LeadDeskIndiaBot',
    formUrl: 'https://forms.gle/BxrdQwUzQM8w5ch18',
  );

  /// Kept up to date by [watch]; widgets that only need the current value read this.
  static final current = ValueNotifier<PublicLinks>(defaults);

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  static String _bot(String s) {
    var b = s.trim();
    b = b.replaceFirst(RegExp(r'^(https?://)?(www\.)?(t\.me|telegram\.me)/', caseSensitive: false), '');
    b = b.replaceFirst('@', '');
    return b.split(RegExp(r'[/?]')).first;
  }

  factory PublicLinks.from(Map<String, dynamic>? d) {
    if (d == null) return defaults;
    final wa = _digits('${d['whatsappNumber'] ?? ''}');
    final tg = _bot('${d['telegramBot'] ?? ''}');
    final form = '${d['formUrl'] ?? ''}'.trim();
    final text = '${d['whatsappText'] ?? ''}'.trim();
    return PublicLinks(
      whatsappNumber: wa.length >= 8 ? wa : defaults.whatsappNumber,
      telegramBot: tg.isNotEmpty ? tg : defaults.telegramBot,
      formUrl: form.startsWith('http') ? form : defaults.formUrl,
      whatsappText: text.isNotEmpty ? text : defaults.whatsappText,
    );
  }

  Map<String, dynamic> toMap() => {
        'whatsappNumber': whatsappNumber,
        'telegramBot': telegramBot,
        'formUrl': formUrl,
        'whatsappText': whatsappText,
      };

  String get whatsappUrl => 'https://wa.me/$whatsappNumber?text=${Uri.encodeComponent(whatsappText)}';
  String get telegramUrl => 'https://t.me/$telegramBot?start=web';

  /// "+1 555 199 3241" / "+91 98765 43210" for display.
  String get whatsappDisplay {
    final d = whatsappNumber;
    if (d.length == 11 && d.startsWith('1')) return '+1 ${d.substring(1, 4)} ${d.substring(4, 7)} ${d.substring(7)}';
    if (d.length == 12 && d.startsWith('91')) return '+91 ${d.substring(2, 7)} ${d.substring(7)}';
    return '+$d';
  }

  static DocumentReference<Map<String, dynamic>> get _doc => FirebaseFirestore.instance.doc('config/public');

  /// Starts listening once (called from main); later reads use [current].
  static void watch() {
    _doc.snapshots().listen(
      (s) => current.value = PublicLinks.from(s.data()),
      onError: (Object e) => debugPrint('public links not readable yet: $e'),
    );
  }

  static Future<void> save(PublicLinks l) => _doc.set(l.toMap(), SetOptions(merge: true));
}
