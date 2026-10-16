import 'package:cloud_firestore/cloud_firestore.dart';

/// All Firestore reads and writes in one place.
class Repo {
  static final db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get leads => db.collection('leads');
  static CollectionReference<Map<String, dynamic>> messages(String leadId) =>
      leads.doc(leadId).collection('messages');

  /// Live list of leads for the counsellor desk (merged duplicates hidden).
  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchLeads() {
    return leads
        .orderBy('lastMessageAt', descending: true)
        .limit(150)
        .snapshots()
        .map((s) => s.docs.where((d) => d.data()['mergedInto'] == null).toList());
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchLead(String id) => leads.doc(id).snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchMessages(String leadId) =>
      messages(leadId).orderBy('createdAt').limitToLast(200).snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchEvents() =>
      db.collection('events').orderBy('at', descending: true).limit(40).snapshots();

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
    await ref.set({
      if (name != null && name.isNotEmpty) 'name': name,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (email != null && email.isNotEmpty) 'email': email,
      if (city != null && city.isNotEmpty) 'city': city,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (assignedTo != null) 'assignedTo': assignedTo,
      'sources': [source],
      'firstSource': source,
      'lastChannel': source == 'whatsapp' ? 'whatsapp' : 'web',
      'status': status,
      'score': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessageAt': FieldValue.serverTimestamp(),
      ...extra,
    });
    return ref.id;
  }

  /// A message from the prospect. The AI counsellor replies automatically (Cloud Function).
  static Future<void> sendProspectMessage(
    String leadId, {
    String? text,
    String? audioB64,
    String? audioMime,
    String channel = 'web',
  }) async {
    await leads.doc(leadId).set({
      'lastInboundAt': FieldValue.serverTimestamp(),
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastChannel': channel,
    }, SetOptions(merge: true));
    await messages(leadId).add({
      'role': 'user',
      'channel': channel,
      if (text != null) 'text': text,
      if (audioB64 != null) 'audioB64': audioB64,
      if (audioMime != null) 'audioMime': audioMime,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// A message typed by a human counsellor (after taking over).
  static Future<void> sendCounsellorMessage(String leadId, String text, {required String channel, required String me}) async {
    await messages(leadId).add({
      'role': 'counsellor',
      'channel': channel,
      'text': text,
      'meta': {'by': me},
      'createdAt': FieldValue.serverTimestamp(),
    });
    await leads.doc(leadId).set({
      'lastMessageAt': FieldValue.serverTimestamp(),
      'needsHuman': false,
      'assignedTo': me,
    }, SetOptions(merge: true));
  }

  static Future<void> setTakeover(String leadId, bool humanTakesOver, String me) async {
    await leads.doc(leadId).set({
      'aiPaused': humanTakesOver,
      if (humanTakesOver) 'assignedTo': me,
      if (humanTakesOver) 'needsHuman': false,
    }, SetOptions(merge: true));
    await messages(leadId).add({
      'role': 'system',
      'channel': 'web',
      'text': humanTakesOver ? '$me joined the conversation' : 'Asha (AI) is back on this conversation',
      'meta': {'kind': 'takeover'},
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> setStatus(String leadId, String status) =>
      leads.doc(leadId).set({'status': status}, SetOptions(merge: true));

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

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchDemoConfig() => db.doc('config/demo').snapshots();
}
