import 'package:flutter/foundation.dart';

/// Your Firebase Hosting address. Used for the QR codes when the app runs on a
/// phone; on the web we use whatever address the browser is already on.
const kPublicWebUrl = 'https://lead-desk-39885.web.app';

/// Project owner(s). If the automatic "first staff account becomes admin" step
/// ever misses (a brand-new project's Firestore trigger can take a few minutes
/// to go live), these people can unlock admin for themselves from the waiting
/// screen. Keep this list identical to ownerEmails() in firestore.rules.
const kOwnerEmails = <String>['khurramrashid0786@gmail.com'];

bool isOwnerEmail(String? email) =>
    email != null && kOwnerEmails.contains(email.trim().toLowerCase());

String publicBaseUrl() => kIsWeb ? Uri.base.origin : kPublicWebUrl;

/// A link a prospect opens. `src` tells the reports where the lead came from.
String chatLink(String src) => '${publicBaseUrl()}/#/chat?src=$src';
String formLink(String src) => '${publicBaseUrl()}/#/form?src=$src';
String siteLink() => publicBaseUrl();

/// Shown in the Admin title bar: if you do not see this after `deploy hosting`, the browser is
/// still showing the old version (press Ctrl+Shift+R).
const kBuildLabel = 'build r7 · 17 Oct';
