# AI Lead Desk — PS3 (stand-in brand: SechTummit Trainers)

An AI admissions counsellor that holds real counselling conversations — text or voice notes in
English, हिंदी and मराठी, even mixed — keeps every enquiry from every channel in one timeline, and
makes sure no lead is ever forgotten. Plus a live counsellor desk with explainable scores, three-line
summaries, objections, the next best action and one-tap take-over.

**Stack:** Flutter (web + Android) · Firebase (Firestore, Auth, Hosting, Cloud Functions, Mumbai) ·
Gemini with free Groq/OpenRouter fallbacks · Google Calendar · WhatsApp / Telegram / Instagram / Google Forms / telephony webhooks.

> SechTummit Trainers is a **stand-in brand**. Courses, fees, partners and stories are SAMPLE data,
> editable in Admin → Knowledge base, and labelled as samples on the site.

---

## Run it (Windows, from the project folder)

### 1. First time only
```bat
npm install -g firebase-tools
firebase login
firebase use lead-desk-39885
copy functions\.env.example functions\.env
```
Open `functions\.env` and paste at least one `GEMINI_API_KEY` (free: https://aistudio.google.com).
Add `GROQ_API_KEY` / `OPENROUTER_API_KEY` too if you have them (free fallbacks).

### 2. Every time you get a new zip
```bat
flutter clean
flutter pub get
cd functions && npm install && npm test && cd ..
deploy
flutter run -d chrome
```
- `npm test` must show **14 passing** (identity merge, Guard, aptitude, scoring, follow-ups).
- `deploy` (= deploy.bat) deploys the AI brain + Firestore rules. It may ask to enable APIs → **y**.
  It also removes the old `whatsappWebhook` function (replaced by `metaWebhook`).
- Phone: `flutter run` with the phone on USB.

### 3. After the first deploy (2 minutes)
1. Open the app → footer **Counsellor desk** → sign in with Google (first account = admin).
2. **Admin → Demo → Load everything** (knowledge base, demo/call slots, 30 sample leads).
3. **Admin → AI engine → Warm up.**
4. **Admin → Team**: tick the languages each counsellor speaks (assignment is by language).
5. Connect channels: **docs/SETUP_CHANNELS.md** (Telegram 3 min, Calendar 8 min, Google Form 5 min, WhatsApp 25 min).

### 4. Publish the web app (for QR codes / judges)
```bat
flutter build web --release
deploy hosting
```
→ https://lead-desk-39885.web.app

### 5. Android APK
```bat
flutter build apk --release --split-per-abi
```
Install `build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`.

---

## How each "What to Build" requirement is met
See **docs/PROBLEM_STATEMENT_COVERAGE.md** (line by line, honest status) and **docs/ARCHITECTURE.md**.

## 3-minute demo
Open `/demo` in the app — the judges' hub with every entry point and the route:
1. Website chat (or Telegram / QR): *"I'm a commerce graduate with a two-year gap — can I really become a developer?"* (or a Hinglish/Marathi voice note).
2. Accept the aptitude check → 4 adaptive tap-to-answer questions → honest recommendation.
3. Pick a demo slot → event in Google Calendar, reminders scheduled.
4. *"My friend got 30% off, give me the same"* → the Guard refuses; 🛡 badge on the desk.
5. Desk → 🧪 Simulate presets 1 → 2 → 3 (Rahul Patil form → राहुल पाटल WhatsApp → father's call) → one lead.
6. Take over → Asha stops; reply goes out on the lead's channel.
7. ⏩ +1 day → follow-ups by objection playbook, inside WhatsApp's window, never in quiet hours.
8. Reports → conversion by source, counsellor, objection.

## Honest limitations
- WhatsApp test numbers only reach a few verified phones; judges use Telegram / web chat / the simulator.
- Instagram DMs need a Professional account + Meta app review for public users; demo uses the simulator (same code path).
- Telephony is provider-ready (generic call webhook) but no provider account is connected; demo uses the simulator.
- Students on web chat are anonymous Firebase sessions; clearing the browser starts a new chat (the same person is still merged when they share a phone number).
- Voice notes up to ~60 s are stored inside Firestore (no Cloud Storage needed).

---

## Third-party components (required by the hackathon terms, point 7)

| Component | Used for | Link |
|---|---|---|
| Flutter SDK & Dart | Android + web app | https://flutter.dev |
| Firebase (Core, Firestore, Auth, Hosting, Cloud Functions) | database, staff + student sign-in, hosting, server code | https://firebase.google.com |
| firebase_core, cloud_firestore, firebase_auth (FlutterFire) | Firebase in Flutter | https://pub.dev/publishers/firebase.google.com |
| Google Gemini API via `@google/genai` | the AI counsellor (text + audio understanding) | https://www.npmjs.com/package/@google/genai |
| Groq API (Llama, Whisper) | free fallback model + speech-to-text | https://console.groq.com |
| OpenRouter | free fallback models | https://openrouter.ai |
| google-auth-library | Google Calendar API calls from Cloud Functions | https://www.npmjs.com/package/google-auth-library |
| Google Calendar API | real demo-class bookings | https://developers.google.com/calendar |
| Telegram Bot API | Telegram channel | https://core.telegram.org/bots/api |
| Plus Jakarta Sans (OFL-1.1) | app font, bundled in assets/fonts | https://fonts.google.com/specimen/Plus+Jakarta+Sans |
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
