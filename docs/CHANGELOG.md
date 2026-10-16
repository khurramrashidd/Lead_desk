# Changelog

Newest first. Earlier history is in the git log.

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
