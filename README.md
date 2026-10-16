# AI Lead Desk — TechSummitTrainers (PS3)

An AI admissions counsellor that answers every enquiry in seconds — text or voice notes in English, Hindi and Marathi — plus a live counsellor dashboard so no lead is ever forgotten.

The app ships with the **client's own website** (SechTummit Trainers, a stand-in brand for the demo) so the problem is solved where it actually happens: the enquiry is answered on the page the student is already looking at.

One Flutter codebase → **Android app + web app**. Firebase for data, Cloud Functions + Gemini for the AI brain.

📐 **Architecture, data model and flow diagrams:** [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
🟢 **WhatsApp setup, step by step:** [docs/WHATSAPP_SETUP.md](docs/WHATSAPP_SETUP.md)

---

## What's inside

```
lib/                      Flutter app (Android + web)
  main.dart               routes: /  /chat  /form  /desk  /walkin  /admin  /demo
  app_theme.dart          design system: colours, type scale, components
  config.dart             hosting URL + owner emails (admin escape hatch)
  screens/site/           the SechTummit Trainers website, with the AI chat docked in it
  screens/demo_hub_screen one page for judges: every entry point + the 3-minute route
  widgets/brand.dart      the logo, drawn in code (same geometry as the app icon)
  screens/chat/           student chat (text + voice notes, no login)
  screens/desk/           counsellor desk: leads, AI insights, take over, activity, reports
  screens/form_screen     website enquiry form -> continues in chat
  screens/walkin_screen   walk-in entry with auto location + IST time
  screens/admin_screen    team approvals, knowledge base editor, demo data, QR codes, time machine
  data/institute.dart     website copy; courses and fees are read from the AI's knowledge base
  screens/auth/           staff sign-in (Google + email, linked), approval gate, account sheet
  data/seed.dart          SAMPLE courses/fees (replace with the sponsor's real data)
functions/                Cloud Functions (TypeScript) — the AI brain
  src/brain.ts            Asha: language mirroring, counselling, aptitude, recommendation, booking
  src/guard.ts            blocks invented fees, discounts and placement promises
  src/identity.ts         phone normalising, Devanagari->Latin, fuzzy name matching
  src/merge.ts            merges the same person across channels into one timeline
  src/heartbeat.ts        every 5 min: demo reminders + next-best-action follow-ups
  src/whatsapp.ts         WhatsApp Cloud API webhook + sending
  src/staff.ts            first staff account / ADMIN_EMAILS become admin, others wait for approval
  src/test/               7 tests (Rahul Patil = राहुल पाटील, Guard, quiet hours)
docs/                     architecture diagrams + WhatsApp guide
deploy.bat                deploy with a longer load timeout (use this, not plain firebase deploy)
firebase.json, firestore.rules (role-based), firestore.indexes.json
```

### Brand
The logo is a speech bubble (every enquiry is a conversation) holding a rising trend line
(conversations that convert), with an AI sparkle. One set of coordinates generates the Android
launcher icon, the adaptive icon, the favicon, the PWA icons and the in-app mark, so the phone
home screen, the browser tab and the app header all show the same thing. No Flutter default
icon is left anywhere.

---

## Setup on Windows (about 45 minutes)

### 1. Create the Flutter project
```bash
flutter create --org com.techsummit --platforms=android,web lead_desk
cd lead_desk
```
Copy everything from this zip **into** `lead_desk` (replace `lib/` completely; keep the generated `android/` and `web/`).

### 2. Add packages
```bash
flutter pub add firebase_core cloud_firestore firebase_auth google_sign_in record path_provider shared_preferences url_launcher intl http geolocator qr_flutter
```

### 3. Firebase console (https://console.firebase.google.com)
1. **Create project** (Google Analytics: off is fine).
2. **Upgrade to Blaze** (bottom-left ⚙ → Usage and billing). Then in Google Cloud Billing → **Budgets & alerts** → create a **₹100** budget alert.
3. **Firestore Database** → Create database (Standard edition / Native mode if asked), location **asia-south1 (Mumbai)**, start in **production mode** (our rules get deployed in step 6).
4. **Authentication** → Get started → Sign-in method → enable **Anonymous** (students), **Email/Password** and **Google** (staff; pick a support email).
5. **Authentication → Settings → User account linking**: keep **Link accounts that use the same email** (this is what merges Google + password for the same Gmail).

### 4. Connect the app to Firebase
```bash
npm install -g firebase-tools
firebase login
dart pub global activate flutterfire_cli
flutterfire configure --project=YOUR-PROJECT-ID --platforms=android,web
firebase use YOUR-PROJECT-ID
```
If `flutterfire` is "not recognized", add `%LOCALAPPDATA%\Pub\Cache\bin` to your PATH and reopen VS Code.

### 5. Android settings
`android/app/build.gradle.kts` → inside `defaultConfig { }` set:
```kotlin
minSdk = 24
```
`android/app/src/main/AndroidManifest.xml` → add above `<application`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```
(Without INTERNET the **release** APK cannot reach Firebase.)

**Google sign-in on Android needs your SHA fingerprints:**
```bash
cd android
gradlew signingReport
cd ..
```
Copy the **SHA1** and **SHA-256** of `Variant: debug` → Firebase Console → Project settings → Your apps → Android app → **Add fingerprint** (add both). Then refresh the config file:
```bash
flutterfire configure --project=YOUR-PROJECT-ID --platforms=android,web
```
Web needs nothing extra (`localhost` and your `web.app` domain are authorised by default).

### 6. Gemini key + deploy the AI brain
1. Get a key at https://aistudio.google.com → **Get API key**.
2. `copy functions\.env.example functions\.env` and paste the key into `GEMINI_API_KEY`. Check the model name list in AI Studio and update `GEMINI_MODEL` if needed. Optionally put your Gmail in `ADMIN_EMAILS` (otherwise the **first** person to sign in on the desk becomes admin — so sign in first yourself).
3. Deploy:
```bash
cd functions
npm install
npm test
cd ..
deploy
```
`deploy` runs **deploy.bat** (project root). It raises Firebase's 10-second load limit to 120 seconds, which slow laptops need; plain `firebase deploy` can fail with *"User code failed to load … Timeout after 10000"*.
`npm test` should show **7 passing**. The first deploy asks to enable some Google APIs — answer **yes**. It takes ~5 minutes.

### 7. Run
```bash
flutter run -d chrome          # web
flutter run                    # phone on USB (USB debugging on)
```
Open **Counsellor Desk** → sign in with Google (you become admin) → **Admin & Demo → Load everything**. Then open **Student Chat** and say hi.

New counsellors: they sign in on the desk, see "Request sent to the admin", and you approve them in **Admin → Team and counsellor requests**.

**Stuck on "Request sent to the admin" as the owner?** On a brand-new project the Firestore trigger
can take a few minutes to go live, so the very first sign-in may be missed. Any of these fixes it:
sign out and sign in again (the trigger now runs on every write, not just the first);
tap **Unlock admin access** on that screen (shown for emails in `kOwnerEmails` in `lib/config.dart`
— keep it the same as `ownerEmails()` in `firestore.rules`); or set `role` to `admin` on your
document in Firebase Console → Firestore → `users`.

### 8. Publish the web app (for the QR codes)
```bash
flutter build web --release
deploy hosting
```
Put the hosting URL into `lib/config.dart` (`kPublicWebUrl`) so the phone app shows the right QR codes.

### 9. Android APK
```bash
flutter build apk --release --split-per-abi
```
Install `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.

### 9b. If the Android build fails on "Could not close incremental caches"
The Flutter pub cache sits on `C:` while this project is on `F:`. Kotlin's incremental compiler
cannot build a relative path across two Windows drives. `android/gradle.properties` already turns
that off (`kotlin.incremental=false`). If it still happens after pulling a new version, run:
```bash
flutter clean
flutter pub get
```

### 10. WhatsApp (optional, after everything else works)
Follow **[docs/WHATSAPP_SETUP.md](docs/WHATSAPP_SETUP.md)** (test number, webhook, permanent token, troubleshooting).

---

## 3-minute demo script

1. **The website (20 s).** Open the site. "This is the institute's own page. A student is reading it at 11 PM. Watch what happens when they have a real question."
2. **Scan and speak (40 s).** A judge scans the QR (Admin → QR codes) and sends a voice note: *"I'm a commerce graduate with a two-year gap — can I really become a developer?"* in Hinglish or Marathi. Asha answers in the same language and tone.
3. **The desk (20 s).** The lead appears live with a score, a three-line summary and the objections detected.
4. **Aptitude → honest recommendation → booking (30 s).** Three or four quick questions, then "start with Python Foundations, not Full Stack yet — here's why", then a real slot and an **Add to Google Calendar** button.
5. **Try to break it (20 s).** "My friend got 30% off — give me the same or I'll join elsewhere." Asha refuses politely and offers only what the website publishes. Show the 🛡 Guard badge, or `npm test` in functions.
6. **One person, one timeline (20 s).** Submit the website form as *Rahul Patil, 098765 43210*; then in chat say *"मी राहुल पाटील, नंबर +91 98765-43210"* → Activity shows **"Same person recognised"** and the timelines merge.
7. **Take over (15 s).** Tap **Take over** on the phone. Asha stops instantly; the human reply lands in the judge's chat.
8. **No lead forgotten (15 s).** ⏩ **Fast-forward 1 day** → reminders and follow-ups fire, each with its reason.
9. **Where admissions come from (10 s).** Reports → conversion by source, counsellor and objection.

`/demo` opens a hub page with all of this, for judges to explore on their own.

Before judging: warm the functions with one test message (the first call after idle is slower), and record a backup demo video.

## Honest limitations (say these if asked)
- Firestore rules are role-based (students see only their own chat; approved counsellors see leads; admins manage courses and team). Student identity is an anonymous session, so clearing the browser starts a new chat.
- **SechTummit Trainers is a stand-in brand.** Courses, fees, hiring-partner names and student stories are sample content for the prototype, all editable in Admin, and labelled as samples on the page itself.
- Voice notes up to ~60 s are stored inside Firestore (no Cloud Storage needed).
- Phone calls through an Indian telephony provider and Instagram DMs (both optional in the statement) are not built; Instagram leads are tracked through a tagged bio link.
- The course data is **sample data**; the sponsor's real courses can be pasted in the Admin screen in a minute.

---

## Third-party components (required by the hackathon terms, point 7)

| Component | Used for | Link |
|---|---|---|
| Flutter SDK & Dart | Android + web app | https://flutter.dev |
| Firebase (Core, Firestore, Auth, Hosting, Cloud Functions) | database, staff + student sign-in, hosting, server code | https://firebase.google.com |
| firebase_core, cloud_firestore, firebase_auth (FlutterFire) | Firebase in Flutter | https://pub.dev/publishers/firebase.google.com |
| Google Gemini API via `@google/genai` | the AI counsellor (text + audio understanding) | https://www.npmjs.com/package/@google/genai |
| firebase-admin, firebase-functions | Cloud Functions runtime | https://www.npmjs.com/package/firebase-functions |
| TypeScript | functions language | https://www.typescriptlang.org |
| record | recording voice notes | https://pub.dev/packages/record |
| path_provider | temporary audio files on Android | https://pub.dev/packages/path_provider |
| google_sign_in | Google sign-in on Android | https://pub.dev/packages/google_sign_in |
| shared_preferences | remembering the chat / counsellor on the device | https://pub.dev/packages/shared_preferences |
| url_launcher | opening calendar links | https://pub.dev/packages/url_launcher |
| intl | IST date and time formatting | https://pub.dev/packages/intl |
| http | reverse-geocoding call | https://pub.dev/packages/http |
| geolocator | walk-in auto location | https://pub.dev/packages/geolocator |
| qr_flutter | channel QR codes | https://pub.dev/packages/qr_flutter |
| BigDataCloud reverse-geocode client API | GPS → city/area | https://www.bigdatacloud.com |
| Meta WhatsApp Cloud API | WhatsApp channel | https://developers.facebook.com/docs/whatsapp |
| Google Calendar event links | "Add to calendar" for demo classes | https://calendar.google.com |

Each component remains under its own licence; see the links.
