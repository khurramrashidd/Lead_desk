import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'api.dart';

/// All Firestore reads and writes in one place.
class Repo {
  static final db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get leads => db.collection('leads');
  static CollectionReference<Map<String, dynamic>> messages(String leadId) => leads.doc(leadId).collection('messages');

  /// Live list of leads for the counsellor desk (merged duplicates hidden).
  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchLeads() {
    return leads
        .orderBy('lastMessageAt', descending: true)
        .limit(200)
        .snapshots()
        .map((s) => s.docs.where((d) => d.data()['mergedInto'] == null).toList());
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchLead(String id) => leads.doc(id).snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchMessages(String leadId) =>
      messages(leadId).orderBy('createdAt').limitToLast(200).snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchEvents() =>
      db.collection('events').orderBy('at', descending: true).limit(60).snapshots();

  /// The knowledge base the AI quotes from — the website reads the very same document.
  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchKb() => db.doc('kb/main').snapshots();

  /// Open slots with free seats, soonest first. kind: demo | call | meet (null = all).
  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchSlots([String? kind]) => db
      .collection('slots')
      .where('startAt', isGreaterThan: Timestamp.fromDate(DateTime.now()))
      .orderBy('startAt')
      .limit(80)
      .snapshots()
      .map((s) => s.docs.where((d) {
            final x = d.data();
            final k = (x['kind'] as String?) ?? 'demo';
            final free = ((x['capacity'] as num?)?.toInt() ?? 0) - ((x['booked'] as num?)?.toInt() ?? 0);
            return free > 0 && (kind == null || k == kind);
          }).toList());

  /// Hot-lead alerts for this counsellor (sorted on the device, so no composite index is needed).
  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchAlerts(String uid) => db
      .collection('alerts')
      .where('uid', isEqualTo: uid)
      .limit(30)
      .snapshots()
      .map((s) => s.docs.toList()
        ..sort((a, b) {
          final ta = a.data()['at'] as Timestamp?;
          final tb = b.data()['at'] as Timestamp?;
          return (tb?.millisecondsSinceEpoch ?? 0).compareTo(ta?.millisecondsSinceEpoch ?? 0);
        }));

  static Future<void> markAlertRead(String id) => db.doc('alerts/$id').update({'read': true});

  /// Creates a lead and returns its id.
  static Future<String> createLead({
    required String source,
    String? name,
    String? phone,
    String? email,
    String? city,
    double? lat,
    double? lng,
    String? assignedTo,
    String status = 'new',
    Map<String, dynamic> extra = const {},
  }) async {
    final ref = leads.doc();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final data = <String, dynamic>{
      'sources': [source],
      'firstSource': source,
      'lastChannel': source == 'whatsapp' ? 'whatsapp' : (source == 'walkin' || source == 'form' ? source : 'web'),
      'status': status,
      'score': 0,
      'userMessages': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessageAt': FieldValue.serverTimestamp(),
      ...extra,
    };
    // Firestore rules: a student can read only leads that list their uid here.
    if (uid != null) data['viewerUids'] = [uid];
    if (name != null && name.isNotEmpty) data['name'] = name;
    if (phone != null && phone.isNotEmpty) data['phone'] = phone;
    if (email != null && email.isNotEmpty) data['email'] = email.trim().toLowerCase();
    if (city != null && city.isNotEmpty) data['city'] = city;
    if (lat != null) data['lat'] = lat;
    if (lng != null) data['lng'] = lng;
    if (assignedTo != null) data['assignedTo'] = assignedTo;
    await ref.set(data);
    return ref.id;
  }

  /// A message from the prospect. The AI counsellor replies automatically (Cloud Function).
  static Future<void> sendProspectMessage(
    String leadId, {
    String? text,
    String? audioB64,
    String? audioMime,
    String? imageB64,
    String? imageMime,
    String channel = 'web',
    Map<String, dynamic>? meta,
  }) async {
    await leads.doc(leadId).set({
      'lastInboundAt': FieldValue.serverTimestamp(),
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastChannel': channel,
    }, SetOptions(merge: true));
    final msg = <String, dynamic>{
      'role': 'user',
      'channel': channel,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (text != null) msg['text'] = text;
    if (audioB64 != null) msg['audioB64'] = audioB64;
    if (audioMime != null) msg['audioMime'] = audioMime;
    if (imageB64 != null) msg['imageB64'] = imageB64;
    if (imageMime != null) msg['imageMime'] = imageMime;
    if (meta != null && meta.isNotEmpty) msg['meta'] = meta;
    final ref = await messages(leadId).add(msg);
    _dispatch(leadId, ref.id);
  }

  /// Asks the backend to answer [msgId] now (Asha's reply, or delivering a counsellor's
  /// message on WhatsApp/Telegram). The Firestore trigger does the same; doing it from here
  /// too means a reply never depends on that trigger alone. Safe to run twice.
  /// Not awaited: the reply arrives through the live message stream.
  static void _dispatch(String leadId, String msgId) {
    unawaited(Api.call('dispatch', {'leadId': leadId, 'msgId': msgId}).then<void>((_) {}, onError: (Object _) {}));
  }

  /// A message typed by a human counsellor. Delivered on the lead's own channel by the backend.
  static Future<void> sendCounsellorMessage(String leadId, String text, {required String channel, required String me}) async {
    final ref = await messages(leadId).add({
      'role': 'counsellor',
      'channel': channel,
      'text': text,
      'meta': {'by': me},
      'createdAt': FieldValue.serverTimestamp(),
    });
    await leads.doc(leadId).set({
      'lastMessageAt': FieldValue.serverTimestamp(),
      'needsHuman': false,
    }, SetOptions(merge: true));
    _dispatch(leadId, ref.id);
  }

  /// The channel a counsellor's reply should go out on.
  static String replyChannel(Map<String, dynamic> lead) {
    final last = lead['lastChannel'] as String?;
    if (last == 'telegram' && lead['telegramId'] != null) return 'telegram';
    if (last == 'instagram' && lead['igId'] != null) return 'instagram';
    if (lead['waId'] != null) return 'whatsapp';
    if (lead['telegramId'] != null) return 'telegram';
    return 'web';
  }

  static Future<void> setTakeover(String leadId, bool humanTakesOver, String me) async {
    final patch = <String, dynamic>{'aiPaused': humanTakesOver};
    if (humanTakesOver) {
      patch['takenOverBy'] = me;
      patch['needsHuman'] = false;
    }
    await leads.doc(leadId).set(patch, SetOptions(merge: true));
    await messages(leadId).add({
      'role': 'system',
      'channel': 'web',
      'text': humanTakesOver ? '$me joined the conversation' : 'Asha (AI) is back on this conversation',
      'meta': {'kind': 'takeover'},
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> setStatus(String leadId, String status) =>
      leads.doc(leadId).set({'status': status, 'statusChangedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

  /// Logs a phone call / Instagram DM / visit a counsellor handled outside the app.
  static Future<void> logTouch(String leadId, {required String channel, required String note, required String me}) async {
    await messages(leadId).add({
      'role': 'system',
      'channel': channel,
      'text': '$me logged a ${channel == 'call' ? 'phone call' : channel}: $note',
      'meta': {'kind': 'log', 'by': me},
      'createdAt': FieldValue.serverTimestamp(),
    });
    await leads.doc(leadId).set({
      'sources': FieldValue.arrayUnion([channel]),
      'lastMessageAt': FieldValue.serverTimestamp(),
      'needsHuman': false,
      'callTask': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  // ------------------------------------------------------------ server actions
  static Future<void> merge(String keepId, String dupId) => Api.run('merge', {'keepId': keepId, 'dupId': dupId});
  static Future<void> dismissDuplicate(String leadId, String otherId) =>
      Api.run('dismissDuplicate', {'leadId': leadId, 'otherId': otherId});
  static Future<void> assign(String leadId, String uid) => Api.run('assign', {'leadId': leadId, 'uid': uid});
  static Future<void> book(String leadId, String slotId) => Api.run('book', {'leadId': leadId, 'slotId': slotId});

  /// Website "Restart": the next message starts a fresh chat.
  static Future<void> restartChat(String leadId) => Api.run('restartChat', {'leadId': leadId});

  /// Admin: payment receipt checked → allot the course (approve) or reject.
  static Future<String> verifyEnrollment(String leadId, {required bool approve, String? courseId, String? note}) async {
    final d = await Api.run('verifyEnrollment', {
      'leadId': leadId,
      'approve': approve,
      'courseId': ?courseId,
      'note': ?note,
    });
    return '${d['detail'] ?? 'Done'}';
  }

  /// The stored receipt photo of an enrolment.
  static Future<Map<String, dynamic>?> message(String leadId, String msgId) async =>
      (await messages(leadId).doc(msgId).get()).data();

  /// Admin → Overview → Enrollment payments (public: the student's chat shows the QR).
  static Stream<Map<String, dynamic>> watchPayment() => db
      .doc('config/public')
      .snapshots()
      .map((s) => ((s.data()?['payment'] as Map?) ?? const {}).cast<String, dynamic>());

  static Future<void> savePayment({required String upiId, required String payee, required int amount}) => db
      .doc('config/public')
      .set({'payment': {'upiId': upiId.trim(), 'payee': payee.trim(), 'amount': amount}}, SetOptions(merge: true));

  /// Sends this lead's 24 h and 1 h reminders (demo class and/or call) right now.
  static Future<String> testReminders(String leadId) async {
    final d = await Api.call('testReminders', {'leadId': leadId});
    return '${d['ok'] == true ? '✅' : 'ℹ️'} ${d['detail'] ?? ''}';
  }
  static Future<Map<String, dynamic>> seed(String what) => Api.run('seed', {'what': what});
  static Future<Map<String, dynamic>> clearSeed() => Api.run('clearSeed');

  /// Load test: N anonymous website visitors write at the same moment.
  static Future<Map<String, dynamic>> burst(int count) => Api.run('burst', {'count': count});
  static Future<Map<String, dynamic>> resetStats() => Api.run('resetStats');

  /// Scale counters, spread over 10 shards (one Firestore document takes ~1 write/second).
  static Stream<Map<String, num>> watchStats() => db.collection('stats').snapshots().map((s) {
        final total = <String, num>{};
        for (final d in s.docs) {
          d.data().forEach((k, v) {
            if (v is num) total[k] = (total[k] ?? 0) + v;
          });
        }
        return total;
      });

  /// Demo simulator: an enquiry exactly as if it arrived on WhatsApp / Instagram / a call…
  static Future<Map<String, dynamic>> simulate({
    required String channel,
    String? name,
    String? phone,
    String? message,
    String? relation,
    String? studentName,
    String? studentPhone,
  }) =>
      Api.run('simulate', {
        'channel': channel,
        'name': ?name,
        'phone': ?phone,
        'message': ?message,
        'relation': ?relation,
        'studentName': ?studentName,
        'studentPhone': ?studentPhone,
      });

  /// "Talk to a human": name / phone / email / brief → lead + a real call or video-meeting slot.
  static Future<Map<String, dynamic>> requestCallback({
    required String name,
    required String phone,
    required String email,
    required String brief,
    required String kind,
    required String source,
    String? slotId,
    String relation = 'self',
    String? studentName,
  }) =>
      Api.run('callback', {
        'name': name,
        'phone': phone,
        'email': email,
        'brief': brief,
        'kind': kind,
        'source': source,
        'slotId': ?slotId,
        'relation': relation,
        'studentName': ?studentName,
      });

  /// Demo "time machine": moves the server clock forward and runs reminders/follow-ups now.
  static Future<void> fastForward({required int hours}) async {
    final ref = db.doc('config/demo');
    await db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final current = (snap.data()?['clockOffsetMinutes'] as num?)?.toInt() ?? 0;
      tx.set(ref, {
        'clockOffsetMinutes': hours == 0 ? 0 : current + hours * 60,
        'runNowAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  /// Demo: jump the server clock to 11:00 AM IST on the next day, when follow-ups are allowed
  /// (they never go out between 9 PM and 9 AM), so pressing it always shows them firing.
  static Future<void> jumpToTomorrowMorning() async {
    final ref = db.doc('config/demo');
    await db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final current = (snap.data()?['clockOffsetMinutes'] as num?)?.toInt() ?? 0;
      final demoNowUtc = DateTime.now().toUtc().add(Duration(minutes: current));
      final ist = demoNowUtc.add(const Duration(hours: 5, minutes: 30));
      final targetIst = DateTime.utc(ist.year, ist.month, ist.day + 1, 11);
      final targetUtc = targetIst.subtract(const Duration(hours: 5, minutes: 30));
      final offset = targetUtc.difference(DateTime.now().toUtc()).inMinutes;
      tx.set(ref, {'clockOffsetMinutes': offset, 'runNowAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    });
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchDemoConfig() => db.doc('config/demo').snapshots();
}
