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
Models: `GEMINI_MODEL=gemini-3.6-flash`, `GROQ_MODEL=openai/gpt-oss-120b` (old names are mapped automatically).

### 2. Every time you get a new zip
Extract it over the project folder, then:
- **If the message says "backend changed"** (like this one): `deploy` once, then `flutter run`.
- **Otherwise:** just `flutter run`. It fetches packages by itself; pick Chrome or your phone from the list.

```bat
deploy
flutter run
```
- `deploy` (= deploy.bat) installs packages, runs the backend tests (**must say `pass 30`**), and deploys the AI brain + Firestore rules. It may ask to enable an API: answer **y**.
- Proof for the judges: Admin → Demo → **Open the self-test** (docs/PROOF.md).
- Test on your phone (app and web): **docs/TESTING.md**.

### 3. After the first deploy (2 minutes)
1. Open the app → footer **Counsellor desk** → sign in with Google (first account = admin).
2. **Admin → Demo → Load everything** (knowledge base, demo/call slots, 30 sample leads).
3. **Admin → AI engine → Warm up.**
4. **Admin → Team**: tick the languages each counsellor speaks (assignment is by language).
5. Connect channels: **docs/SETUP_CHANNELS.md** (Telegram 3 min, Calendar 8 min, Google Form 5 min, WhatsApp 25 min).

### 4. Publish the web app (for QR codes / judges)
```bat
deploy hosting
```
(builds the web app and publishes it)
→ https://lead-desk-39885.web.app

### 5. Android APK
```bat
flutter build apk --release --split-per-abi
```
Install `build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`.

---

## How each "What to Build" requirement is met
See **docs/PROBLEM_STATEMENT_COVERAGE.md** (line by line, honest status), **docs/ARCHITECTURE.md**, and
**docs/SCALE_AND_IDENTITY.md** (millions of enquiries, same question from many people, one admission
asked about by many people, one person asking about many students).

## 3-minute demo
Open `/demo` in the app — the judges' hub with every entry point, the QR codes and the route:
0. Scan the Telegram (or WhatsApp) QR → "Hi" → Asha asks: who is this for → student's name → number/email → course list (buttons) → talks about the course you tap.
1. Website chat (or Telegram / QR): *"I'm a commerce graduate with a two-year gap — can I really become a developer?"* (or a Hinglish/Marathi voice note: listen to it, then send).
2. Accept the aptitude check → 4 adaptive tap-to-answer questions → honest recommendation.
3. Pick a demo slot → event in Google Calendar, reminders scheduled.
4. *"My friend got 30% off, give me the same"* → the Guard refuses; 🛡 badge on the desk.
5. Desk → 🧪 Simulate presets 1 → 2 → 3 (Rahul Patil form → राहुल पाटल WhatsApp → father's call) → one lead.
6. Take over → Asha stops; reply goes out on the lead's channel.
7. ⏩ Jump to tomorrow 11 AM → follow-ups by objection playbook, inside WhatsApp's window, never in quiet hours.
8. Reports → conversion by source, counsellor, objection.

## Honest limitations
- WhatsApp with Meta's free test number (+1 555 199 3241): anyone's message reaches the desk, but Asha's replies are delivered only to the (up to 5) numbers added under Meta → API Setup → "To". Add the judges' numbers there, or let them use Telegram / the web chat. Undelivered replies are flagged on the desk with the reason.
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
| audioplayers | playing a voice note back before sending | https://pub.dev/packages/audioplayers |
| BigDataCloud reverse-geocode client API | GPS → city/area | https://www.bigdatacloud.com |
| Meta WhatsApp Cloud API | WhatsApp channel | https://developers.facebook.com/docs/whatsapp |
| Google Calendar event links | "Add to calendar" for demo classes | https://calendar.google.com |

Each component remains under its own licence; see the links.
