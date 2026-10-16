# AI Lead Desk — TechSummitTrainers (PS3)

An AI admissions counsellor that answers every enquiry in seconds — text or voice notes in English, Hindi and Marathi — plus a live counsellor dashboard so no lead is ever forgotten.

One Flutter codebase → **Android app + web app**. Firebase for data, Cloud Functions + Gemini for the AI brain.

---

## What's inside

```
lib/                      Flutter app (Android + web)
  main.dart               routes: /  /chat  /form  /desk  /walkin  /admin
  screens/chat/           student chat (text + voice notes, no login)
  screens/desk/           counsellor desk: leads, AI insights, take over, activity, reports
  screens/form_screen     website enquiry form -> continues in chat
  screens/walkin_screen   walk-in entry with auto location + IST time
  screens/admin_screen    knowledge base editor, demo data, QR codes, time machine
  data/seed.dart          SAMPLE courses/fees (replace with the sponsor's real data)
functions/                Cloud Functions (TypeScript) — the AI brain
  src/brain.ts            Asha: language mirroring, counselling, aptitude, recommendation, booking
  src/guard.ts            blocks invented fees, discounts and placement promises
  src/identity.ts         phone normalising, Devanagari->Latin, fuzzy name matching
  src/merge.ts            merges the same person across channels into one timeline
  src/heartbeat.ts        every 5 min: demo reminders + next-best-action follow-ups
  src/whatsapp.ts         WhatsApp Cloud API webhook + sending
  src/test/               7 tests (Rahul Patil = राहुल पाटील, Guard, quiet hours)
firebase.json, firestore.rules, firestore.indexes.json
```

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
flutter pub add firebase_core cloud_firestore firebase_auth record path_provider cross_file shared_preferences url_launcher intl http geolocator qr_flutter
```

### 3. Firebase console (https://console.firebase.google.com)
1. **Create project** (Google Analytics: off is fine).
2. **Upgrade to Blaze** (bottom-left ⚙ → Usage and billing). Then in Google Cloud Billing → **Budgets & alerts** → create a **₹100** budget alert.
3. **Firestore Database** → Create database (Standard edition / Native mode if asked), location **asia-south1 (Mumbai)**, start in **production mode** (our rules get deployed in step 6).
4. **Authentication** → Get started → Sign-in method → enable **Anonymous**.

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

### 6. Gemini key + deploy the AI brain
1. Get a key at https://aistudio.google.com → **Get API key**.
2. `copy functions\.env.example functions\.env` and paste the key into `GEMINI_API_KEY`. Check the model name list in AI Studio and update `GEMINI_MODEL` if needed.
3. Deploy:
```bash
cd functions
npm install
npm test
cd ..
firebase deploy --only functions,firestore
```
`npm test` should show **7 passing**. The first deploy asks to enable some Google APIs — answer **yes**. It takes ~5 minutes.

### 7. Run
```bash
flutter run -d chrome          # web
flutter run                    # phone on USB (USB debugging on)
```
Open **Admin & Demo → Load everything**. Then open **Student Chat** and say hi.

### 8. Publish the web app (for the QR codes)
```bash
flutter build web --release
firebase deploy --only hosting
```
Put the hosting URL into `lib/config.dart` (`kPublicWebUrl`) so the phone app shows the right QR codes.

### 9. Android APK
```bash
flutter build apk --release --split-per-abi
```
Install `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.

### 10. WhatsApp (optional, after everything else works)
1. https://developers.facebook.com → Create app → add **WhatsApp** → API Setup.
2. Add your phone(s) as test recipients (max 5). Copy the **temporary access token** → `WA_TOKEN`, and **Phone number ID** → `WA_PHONE_ID` in `functions/.env`. Redeploy functions.
3. Configuration → Webhook: callback URL = the `whatsappWebhook` URL printed by the deploy (looks like `https://asia-south1-YOUR-PROJECT-ID.cloudfunctions.net/whatsappWebhook`), verify token = your `WA_VERIFY_TOKEN`. Subscribe to **messages**.
4. ⚠️ The temporary token expires after 24 hours. Generate a fresh one shortly before judging.

---

## 3-minute demo script

1. **Problem (20 s):** "A student sends a Marathi voice note at 11 pm. Nobody replies till morning — she's gone. TechSummitTrainers' own words."
2. **Scan & speak (40 s):** a judge scans the QR on the projector and sends a voice note, e.g. *"I'm a commerce graduate with a two-year gap — can I really become a developer?"* in Hinglish or Marathi. Asha answers in the same language and tone. The lead appears live on the desk with score, 3-line summary and objections.
3. **Aptitude → honest recommendation → booking (30 s):** 3–4 quick questions, then "start with Python Foundations, not Full Stack yet — here's why", then a real slot and an **Add to Google Calendar** button.
4. **Try to break it (20 s):** "My friend got 30% off — give me too or I'll join elsewhere." Asha refuses politely and offers only listed scholarships/EMI. Every reply passes the 🛡 Guard (show `npm test` or the Activity feed).
5. **Same person, one timeline (20 s):** submit the website form as *Rahul Patil, 098765 43210*; then in chat say *"मी राहुल पाटील, नंबर +91 98765-43210"* → Activity: **"Same person recognised"**, timelines merge.
6. **Take over (15 s):** counsellor taps **Take over** on the phone; the AI stops instantly; the human reply appears in the judge's chat.
7. **No lead forgotten (15 s):** ⏩ **Fast-forward 1 day** → reminders and follow-ups fire with their reasons.
8. **Where admissions come from (10 s):** Reports → conversion by source, counsellor and objection.

Before judging: warm up the functions with one test message (first call after idle is slower), and record a backup demo video.

---

## Honest limitations (say these if asked)
- Security rules allow any signed-in user (hackathon only). Real use needs counsellor logins with roles.
- Voice notes up to ~60 s are stored inside Firestore (no Cloud Storage needed).
- Phone calls through an Indian telephony provider and Instagram DMs (both optional in the statement) are not built; Instagram leads are tracked through a tagged bio link.
- The course data is **sample data**; the sponsor's real courses can be pasted in the Admin screen in a minute.

---

## Third-party components (required by the hackathon terms, point 7)

| Component | Used for | Link |
|---|---|---|
| Flutter SDK & Dart | Android + web app | https://flutter.dev |
| Firebase (Core, Firestore, Auth, Hosting, Cloud Functions) | database, sign-in, hosting, server code | https://firebase.google.com |
| firebase_core, cloud_firestore, firebase_auth (FlutterFire) | Firebase in Flutter | https://pub.dev/publishers/firebase.google.com |
| Google Gemini API via `@google/genai` | the AI counsellor (text + audio understanding) | https://www.npmjs.com/package/@google/genai |
| firebase-admin, firebase-functions | Cloud Functions runtime | https://www.npmjs.com/package/firebase-functions |
| TypeScript | functions language | https://www.typescriptlang.org |
| record | recording voice notes | https://pub.dev/packages/record |
| path_provider, cross_file | temporary audio files | https://pub.dev/packages/path_provider |
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
