import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Staff sign-in: Google or email + password, linked into ONE account.
///
/// How accounts merge (same Firebase user id, same data):
/// * Signed up with a Gmail + password, later "Continue with Google" with the same Gmail
///   -> Firebase treats Google as the trusted owner of Gmail addresses and signs into the
///   SAME account. (Verify the email first so the password keeps working too.)
/// * Signed up with Google, later tries "Create account" with the same email
///   -> we ask them to continue with Google once, then attach the password to that account.
/// * Any account can link the other method later from the Account sheet.
///
/// Students never sign in: the chat uses an anonymous session.
class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static bool _googleReady = false;

  static User? get user => _auth.currentUser;
  static bool get isStaff => user != null && !user!.isAnonymous;

  /// Name shown on the desk ("Priya") – display name, else the part before @.
  static String get displayName {
    final u = user;
    if (u == null) return 'Counsellor';
    final n = u.displayName?.trim() ?? '';
    if (n.isNotEmpty) return n;
    final e = u.email ?? '';
    return e.contains('@') ? e.split('@').first : 'Counsellor';
  }

  static List<String> get providers => user?.providerData.map((p) => p.providerId).toList() ?? const [];
  static bool get hasGoogle => providers.contains('google.com');
  static bool get hasPassword => providers.contains('password');

  // ---------------- Google ----------------

  static Future<void> _ensureGoogle() async {
    if (_googleReady) return;
    // On Android the web client id comes from google-services.json automatically.
    await GoogleSignIn.instance.initialize();
    _googleReady = true;
  }

  /// Android: Google account picker -> ID token -> Firebase credential.
  static Future<OAuthCredential> _googleCredentialOnAndroid() async {
    await _ensureGoogle();
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(code: 'missing-id-token', message: 'Google did not return an ID token. Check the SHA-1 in Firebase.');
    }
    return GoogleAuthProvider.credential(idToken: idToken);
  }

  static Future<UserCredential> signInWithGoogle() async {
    final UserCredential result;
    if (kIsWeb) {
      result = await _auth.signInWithPopup(GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'}));
    } else {
      result = await _auth.signInWithCredential(await _googleCredentialOnAndroid());
    }
    await saveProfile();
    return result;
  }

  /// Adds Google to the signed-in (email) account.
  static Future<void> linkGoogle() async {
    final u = user!;
    if (kIsWeb) {
      await u.linkWithPopup(GoogleAuthProvider());
    } else {
      await u.linkWithCredential(await _googleCredentialOnAndroid());
    }
    await u.reload();
    await saveProfile();
  }

  // ---------------- Email + password ----------------

  static Future<UserCredential> signUpWithEmail({required String name, required String email, required String password}) async {
    final result = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    await result.user!.updateDisplayName(name.trim());
    // Verified emails keep their password when the same Gmail later signs in with Google.
    await result.user!.sendEmailVerification();
    await result.user!.reload();
    await saveProfile(nameOverride: name.trim());
    return result;
  }

  static Future<UserCredential> signInWithEmail(String email, String password) async {
    final result = await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
    await saveProfile();
    return result;
  }

  /// Adds a password to the signed-in (Google) account, so both methods open the same account.
  static Future<void> linkPassword(String password) async {
    final u = user!;
    final email = u.email;
    if (email == null) throw FirebaseAuthException(code: 'no-email', message: 'This account has no email address.');
    await u.linkWithCredential(EmailAuthProvider.credential(email: email, password: password));
    await u.reload();
    await saveProfile();
  }

  /// When Google sign-in finds an existing password account (non-Gmail addresses):
  /// sign in with the password, then attach the pending Google credential.
  static Future<void> signInWithPasswordAndLink(String email, String password, AuthCredential pending) async {
    final result = await _auth.signInWithEmailAndPassword(email: email, password: password);
    await result.user!.linkWithCredential(pending);
    await result.user!.reload();
    await saveProfile();
  }

  static Future<void> resetPassword(String email) => _auth.sendPasswordResetEmail(email: email.trim());

  static Future<void> resendVerification() async {
    await user?.sendEmailVerification();
  }

  static Future<void> signOut() async {
    await _auth.signOut();
    if (!kIsWeb && _googleReady) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    // Keep an anonymous session so the student chat on this device still works.
    await _auth.signInAnonymously();
  }

  // ---------------- Profile in Firestore ----------------

  /// users/{uid}: name, email, photo, linked sign-in methods and ROLE.
  /// New staff start as "pending" until an admin approves them on the Admin page.
  /// The very first staff account (or an email in ADMIN_EMAILS) becomes admin automatically
  /// (Cloud Function `onStaffCreated`).
  static Future<void> saveProfile({String? nameOverride}) async {
    final u = user;
    if (u == null || u.isAnonymous) return;
    final ref = FirebaseFirestore.instance.collection('users').doc(u.uid);
    final profile = <String, dynamic>{
      'name': nameOverride ?? displayName,
      'email': u.email,
      'photoUrl': u.photoURL,
      'providers': providers,
      'emailVerified': u.emailVerified,
      'lastLoginAt': FieldValue.serverTimestamp(),
    };
    // Transaction: never overwrite a role that an admin (or the server) already set.
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        tx.set(ref, {...profile, 'role': 'pending', 'requestedAt': FieldValue.serverTimestamp()});
      } else {
        tx.update(ref, profile);
      }
    });
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchMyRecord() =>
      FirebaseFirestore.instance.collection('users').doc(user!.uid).snapshots();

  /// Plain-English messages for the errors people actually hit.
  static String friendlyError(Object e) {
    if (e is GoogleSignInException) {
      if (e.code == GoogleSignInExceptionCode.canceled) return 'Google sign-in was cancelled.';
      return 'Google sign-in failed (${e.code.name}). On Android, check that your SHA-1 is added in Firebase.';
    }
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-credential':
        case 'wrong-password':
        case 'user-not-found':
          return 'Email or password is wrong. If you created this account with Google, use "Continue with Google".';
        case 'email-already-in-use':
          return 'This email already has an account.';
        case 'weak-password':
          return 'Use at least 6 characters for the password.';
        case 'invalid-email':
          return 'That email address does not look right.';
        case 'popup-closed-by-user':
        case 'cancelled-popup-request':
          return 'Google sign-in was cancelled.';
        case 'popup-blocked':
          return 'The browser blocked the Google pop-up. Allow pop-ups for this site and try again.';
        case 'credential-already-in-use':
          return 'That Google account is already used by another Lead Desk account.';
        case 'provider-already-linked':
          return 'This sign-in method is already linked.';
        case 'requires-recent-login':
          return 'For safety, sign out and sign in again, then retry.';
        case 'too-many-requests':
          return 'Too many attempts. Wait a minute and try again.';
        case 'network-request-failed':
          return 'No internet connection.';
        default:
          return e.message ?? e.code;
      }
    }
    return e.toString();
  }
}
