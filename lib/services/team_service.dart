import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth_service.dart';

/// Staff roles stored in users/{uid}.role
class Roles {
  static const pending = 'pending';
  static const counsellor = 'counsellor';
  static const admin = 'admin';
  static const rejected = 'rejected';

  static bool canUseDesk(String? r) => r == counsellor || r == admin;
}

/// Admin side of the approval flow: see requests, approve, reject, change roles.
class TeamService {
  static final _users = FirebaseFirestore.instance.collection('users');

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchPending() =>
      _users.where('role', isEqualTo: Roles.pending).snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchTeam() =>
      _users.where('role', whereIn: [Roles.counsellor, Roles.admin]).snapshots();

  static Future<void> setRole(String uid, String role) => _users.doc(uid).update({
        'role': role,
        'roleChangedBy': AuthService.user?.email ?? AuthService.displayName,
        'roleChangedAt': FieldValue.serverTimestamp(),
      });

  static Future<void> approve(String uid) => setRole(uid, Roles.counsellor);
  static Future<void> reject(String uid) => setRole(uid, Roles.rejected);

  /// Escape hatch for the project owner: the Firestore rules allow an email in
  /// ownerEmails() to set its OWN role to admin. Used when the automatic
  /// promotion never ran (a new project's trigger can take minutes to go live).
  static Future<void> claimOwnerAdmin() async {
    final uid = AuthService.user?.uid;
    if (uid == null) throw StateError('Not signed in');
    await _users.doc(uid).set({
      'role': Roles.admin,
      'roleChangedBy': 'owner unlock',
      'roleChangedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
