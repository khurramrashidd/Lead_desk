# Changelog

Newest first. Earlier history is in the git log.

## 17 Oct 2026 (4) — Asha answers on every channel even without the Firestore trigger (backend + app changed: run `deploy` and `deploy hosting`)

**Symptoms fixed:** Asha never answered (web chat, Telegram) although every AI key tested fine; Telegram messages
showed on the desk with no reply; WhatsApp messages did not even reach the desk.

**Root cause:** every reply depended on one Firestore trigger (`onMessageCreated`). When it is not deployed or
not firing (first-deploy Eventarc permission errors, or a database outside `asia-south1`), nothing answers, not
even the intake questions that need no AI. WhatsApp: Meta was not calling `metaWebhook` at all (WhatsApp Business
Account not subscribed to the app / "messages" field not subscribed); the old guide also named the wrong URL.

- New `dispatch.ts`: one idempotent "act on this message" used by the trigger **and** by
  - the Telegram / WhatsApp / Instagram webhooks (store → answer in the same request),
  - the app (`api/dispatch` right after the web chat or a counsellor writes a message),
  - the simulator, intake and call webhooks, the load test,
  - a sweeper in `aiRetry` (every 2 min) for any prospect still waiting.
  Running twice never double-answers (per-lead lock) and a counsellor's reply is claimed before sending.
- **Admin → Channels → Diagnose**: database region vs trigger region, whether `onMessageCreated` is deployed and
  active, a live AI call, Telegram's own webhook status, WhatsApp token + WABA subscription, and the last calls
  Meta / Telegram actually made (`config/webhookStatus`), each with its fix.
- **Admin → Channels → WhatsApp → Subscribe webhook** (`api/subscribeWhatsApp`): subscribes the WABA to the app
  and points it at `metaWebhook`. New field: WhatsApp Business Account ID (found from the token when empty).
- `TRIGGER_REGION` in `functions/.env` moves the Firestore triggers next to the database if Diagnose says so.
- Offline end-to-end (in-memory Firestore, no trigger): Telegram intake, WhatsApp AI reply, late trigger and
  webhook retries without duplicates, counsellor reply sent once, sweeper, `api/dispatch` auth: 18/18.

## 17 Oct 2026 (3) — final round: intake questions, QR codes, light site, voice preview (backend changed: run `deploy`)

- **"Asha keeps typing" fixed at the root.** Google never shipped `gemini-3.5-flash` (live models today:
  `gemini-3.6-flash`, `gemini-3.8-flash`, `gemini-3.5-flash-lite`), and Groq shut down
  `llama-3.3-70b-versatile` for free accounts on 16 Aug 2026. Both were our defaults. Now:
  - retired model names (in Admin or `.env`) are mapped to live ones automatically;
  - each Gemini key falls back through the other live Gemini models before the next provider;
  - thinking level is set per model (3.8 Flash refuses "minimal");
  - one reply never waits more than 75 s in total;
  - if every provider fails, the person gets an **instant answer from the knowledge base**
    (fees, courses, batches, placement, demo slots), the AI retries automatically, and the desk shows why
    (red banner + "Asha could not reach the AI" card + Admin → AI engine "last failure").
  - The chat never shows endless "typing…": after 25 s "taking longer", after 75 s other ways to reach us.
- **Intake questions on WhatsApp, Telegram and the web chat** (Admin → Channels switch, default on):
  who is this for (student / parent / friend) → student's name → mobile or email (skipped when WhatsApp
  already gave the number) → the course list → Asha talks about the chosen course (or counsels if none fits).
  Buttons on WhatsApp (reply buttons + list), a keyboard on Telegram (with "share my number"), chips on the
  web; typed answers in English, हिंदी and मराठी work too. A question asked first is kept and answered after
  the intake; a voice note goes straight to Asha. Nobody gets stuck: two misses hand over to Asha.
  Someone who stops halfway gets a nudge 2 hours later (never at night).
- **QR codes + "Talk on WhatsApp / Telegram"** on the website home, the ☰ menu, the Contact page, the chat
  menu, the judges' hub and Admin → Demo. Links are editable in **Admin → Channels → Public links**
  (defaults: WhatsApp +1 555 199 3241, @LeadDeskIndiaBot, the Google Form).
- **Website redesigned**: light by default (no dark sections until you switch to dark mode), a short home
  (headline, Asha/WhatsApp/Telegram buttons, scan-to-chat, courses), everything else as pages in the ☰ menu;
  the top bar is always visible and tappable on phones.
- **Voice notes: listen before sending** (record → stop → play/pause → send or delete).
- **Desk**: search by name, any phone format, email, Telegram username or the questions asked; each lead shows
  "Questions asked", "Intake answers" and **"Earlier records (same phone or email)"** with what they asked;
  undelivered WhatsApp/Telegram replies are flagged with the reason (e.g. Meta test-number allow list).
- Identity also matches the student's email given by a parent.
- Tests: 30 backend unit tests; offline end-to-end run of the intake on web, WhatsApp and Telegram plus an AI
  outage: 23/23 checks (docs/proof/onboarding_run.txt). The 20 self-test scenarios still pass offline.
- New Flutter package: `audioplayers` (voice preview). `flutter run` fetches it automatically.

## 17 Oct 2026 (2) — PS3 self-test with proof; deploy.bat fix (backend changed: run `deploy`)

- **Fixed:** `deploy` failed with "Could not read package.json" (npm on Windows ignores `--prefix` for
  `install`). It now runs npm inside the functions folder.
- **PS3 self-test** (Admin → Demo → Open the self-test, route `/selftest`): 20 live tests, one per
  sentence of "What to Build". Each records pass/fail checks and the real conversation as evidence;
  tests can be run one by one or all in order, and the Markdown report can be copied.
  Backend: `functions/src/selftest.ts`, trigger `onSelfTest`.
- **Aptitude is sturdier:** if the AI forgets to report which question it asked, the server
  still knows (it told the AI which one to ask), so scoring never stalls.
- **Time machine:** "Jump to tomorrow 11 AM" always shows follow-ups firing (they never go out 9 PM–9 AM).
- The heartbeat can run for selected leads only (used by the self-test).
- docs/PROOF.md, docs/proof/offline_pipeline_run.txt (all 20 tests on an in-memory database + scripted AI).

## 17 Oct 2026 — scale, same-question cache, family-aware identity (backend changed: run `deploy`)

- **Answer cache + single-flight**: identical first questions from different strangers are answered by the
  AI once; a burst of 1,000 identical questions makes 1 AI call (unit-tested). The cache key covers question,
  channel, lead state, knowledge-base version and open slots.
- **One reply per person at a time**: rapid messages are answered together; duplicate triggers ignored.
- **Never lost**: AI busy → instant acknowledgement + automatic retries with back-off (`aiRetry`, every 2 min).
- **Scaling**: message worker runs 40 conversations per instance, up to `MAX_INSTANCES` (default 100);
  no hot documents (sharded counters, throttled health, hash-based assignment); `onLeadIdentityChanged` removed
  (one function call fewer per lead write).
- **Identity**: one lead per student with every enquirer as a contact. A parent or friend who gives the
  student's number is merged; the same parent asking about another child becomes a second, *linked* lead.
  Siblings are no longer merged (given-name-aware `personSimilarity`). A name alone never merges.
- **App**: simulator presets 1–6 (father, friend, second child, cache), Admin → Demo → Load test,
  Reports → Scale & cost, linked-enquiries card, ⚡ cached / batched labels, call button works on Android.
- `deploy` now installs, tests and deploys in one go; `deploy hosting` also builds the web app.
- Docs: SCALE_AND_IDENTITY.md, TESTING.md. Tests: 22 passing.

## v7 — fixed build, server-side intelligence, real calendar, fresh UI

**Why it would not run before:** 38 unresolved git merge-conflict blocks were committed in four
Flutter files (site, sections, demo hub, site widgets), and the last commit was only half applied
(missing `Repo.requestCallback`, `cloud_functions` not in pubspec, Cloud Functions failing to compile
on `LeadContact`/`telegram`/`googleform`, callables never exported). All fixed; `npm test` → 14 passing.

**Backend**
- AI pool: Gemini keys first, then free **Groq** and **OpenRouter**; Groq Whisper transcribes voice notes for text-only fallbacks.
- **Aptitude check scored on the server** from a question bank (adaptive levels, bands, tap-to-answer).
- **Explainable lead score** (rules + AI read) with reasons.
- **Next-best-action engine** with objection playbooks, quiet hours, WhatsApp 24 h window, cadence and call tasks.
- **Google Calendar** events for every booking (service account, no key file).
- **Assignment by language** + hot-lead alerts.
- One `api` HTTPS function for admin/desk actions (no extra Flutter packages), `metaWebhook` (WhatsApp + Instagram),
  `telegramWebhook`, `intakeWebhook` (Google Forms), `callWebhook` (telephony), channel simulators, 30 sample leads.
- Guard false positive fixed ("covers 120 km" was read as Rs 120); Guard now also checks suggested messages and follow-ups.
- Firestore rules: API keys and channel tokens readable by admins only.

**App**
- Fresh design: ink + teal + coral palette, Plus Jakarta Sans, rebuilt website.
- Website and chat in **English / हिंदी / मराठी**; website reads the live knowledge base.
- Desk: score breakdown, aptitude answers, duplicate merge buttons, call tasks, re-assign, contacts, booking for a lead, logging calls/DMs, 🧪 simulator, 🔔 alerts, "Mine" filter.
- Admin in tabs: Demo, Team (languages), AI engine (Gemini/Groq/OpenRouter), Channels (WhatsApp, Telegram, Instagram, Calendar, Google Form script, telephony), Knowledge base.

## v6 — build fixes + a guard so this class of bug cannot ship again

**Fixed (this is what was stopping `flutter run`):**

- `lib/screens/desk/lead_detail.dart` — the "Callback requested" card had escaped
  interpolation (`\${...}` instead of `${...}`), which the Dart front-end read as a
  literal backslash. One broken card produced 25 analyzer errors and failed
  `assembleDebug`. The card is now built from five named local variables, which is
  also easier to read.
- `lib/screens/admin/channels_panel.dart` — removed an unused `cloud_firestore` import.
- `lib/services/ops_service.dart` — `'thinking': ?thinking` (null-aware element).
- `lib/widgets/lead_widgets.dart` — `?trailing` (null-aware element).

`flutter analyze` is expected to report **0 issues**.

**Added — `tools/` (run before every build):**

| Script | Catches |
|---|---|
| `tools/check_dart.py` | missing or wrong imports, symbols used from a file that is not imported, unbalanced brackets, escaped interpolation |
| `tools/lint_dart.py` | unused `package:` / `dart:` imports, `use_null_aware_elements`, escaped interpolation, `const` wrapping a runtime value |

```bat
python tools\check_dart.py .
python tools\lint_dart.py .
```

Both are plain Python, no packages needed. They are a pre-flight check, not a
replacement for `flutter analyze`.

## v5 — speed, many AI keys, every channel, booking a human, UI pass

- **AI provider pool** (`functions/src/ai.ts`) — several Gemini keys, each with its
  own model name, managed from **Admin → AI engine**. Tried in order, one retry each,
  fatal errors (bad key, unknown model) skipped immediately, health written to
  `config/aiHealth`. A rate-limited key no longer stops a conversation.
- **Faster replies** — minimal thinking by default, the fastest model first, a
  **Warm up** button for the minutes before judging.
- **Channels** — WhatsApp (token and phone ID testable from **Admin → Channels**),
  Instagram DMs, Telegram, the website chat, the website form, Google Forms via
  `intakeWebhook`, and the walk-in counter.
- **One lead, many people** — the student, a parent and a friend enquiring on
  different channels resolve to a single business lead with a contact list.
- **Talk to a human** — when counselling is not enough, name / phone / email / brief
  are captured and a phone call or Google Meet slot is booked, with reminders.
- **UI** — the hero now runs under the top nav (no more white-on-white header), the
  nav is solid and blurred once scrolled, the chat launcher clears the phone's home
  indicator, light mode is the default with a dark toggle.
