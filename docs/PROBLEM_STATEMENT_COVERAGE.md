# PS3 — AI Lead Desk: every sentence of "What to Build", and where it lives

✅ built and demoable · 🟡 built, with a stated limit · ⬜ not built

## The AI admissions counsellor

| # | Requirement | Status | How / where |
|---|---|---|---|
| 1 | Holds genuine counselling conversations (not a FAQ bot) | ✅ | System prompt + conversation state: background, goal, constraints, worry behind the question. `functions/src/brain.ts` |
| 2 | Understands **text and voice notes** in English, Hindi, Marathi | ✅ | Gemini hears audio directly. If every Gemini key is rate-limited, Groq **Whisper** transcribes and a free fallback model answers. `ai.ts` → `transcribeWithGroq` |
| 3 | …including **mid-sentence switches** | ✅ | Language detected per message (`en/hi/mr/hinglish/marathi-english/mixed`) and stored on the lead |
| 4 | Replies in the prospect's **language and register** | ✅ | Model must return `language`, `script`, `register`; prompt mirrors aap/tum, तुम्ही/तू, Latin vs Devanagari |
| 5 | Asks about background, goals, constraints | ✅ | `profile` (education, gap, current work, coding experience, goal, constraints, budget, timing, family view) → "What we know" on the desk |
| 6 | Course, fee, schedule answers **strictly from a KB the institute controls** | ✅ | `kb/main` in Firestore, edited in Admin → Knowledge base. **The website reads the same document live**, so site and AI cannot disagree |
| 7 | **Never invents discounts, fees or placement guarantees, even when pressed** | ✅ | The **Guard** checks every reply, the suggested message and every follow-up: each ₹ amount, %, discount word and guarantee phrase (EN/HI/MR) must exist in the KB; else blocked → rewritten → safe fallback. 🛡 shown on the desk. Unit-tested. `guard.ts` |
| 8 | Short **adaptive aptitude check** inside the conversation | ✅ | 23-question bank (logic, numbers, patterns, code reading only for people who have coded), 4 questions, starts medium, right → harder, wrong → easier. **Scored on the server**, not by the model; tap-to-answer chips in chat. `aptitude.ts` + tests |
| 9 | Recommends a program with an **honest reason** | ✅ | One course id from the KB + reason tied to background, constraints and aptitude band; told to say when a big course is wrong today |
| 10 | Books a demo into a **real calendar slot** | ✅ | Slots with capacity, booked in a Firestore transaction (no double booking) **and created as an event in the institute's Google Calendar** (service account, no key file). `calendar.ts` |
| 11 | …with **reminders** | ✅ | 24 h and 1 h before, on the lead's own channel, by the 5-minute heartbeat. `heartbeat.ts` |

## One person, one timeline

| # | Requirement | Status | How / where |
|---|---|---|---|
| 12 | "Rahul Patil" (form) = "राहुल पाटल" (WhatsApp) with a differently formatted phone | ✅ | Phones normalised (`098765 43210`, `+91 98765-43210`, `919876543210` → `9876543210`), Devanagari transliterated, Indian-spelling phonetic key + Jaro-Winkler. Tested with the sponsor's exact spelling. `identity.ts` |
| 13 | Merge into a single timeline | ✅ | Messages, sources, contacts, objections, profile, booking, assignment move to the older lead; the student's open chat follows. `merge.ts` |
| 14 | Ambiguous cases | ✅ | Same phone + different name → "Possible duplicate" card with **Merge / Different people** buttons, never a silent guess |
| 15 | Beyond: parent / friend enquiring for the student | ✅ | One lead per student, every enquirer a contact. A parent or friend who gives the student's number is merged; Asha asks for it |
| 15b | Beyond: one person asking about several students (parent of two, agent, shared family phone) | ✅ | Separate leads, **linked** both ways, never merged; given-name-aware matching so siblings are not merged. docs/SCALE_AND_IDENTITY.md |
| 15d | Beyond: **intake questions** on WhatsApp, Telegram and web chat | ✅ | Who is this for (student / parent / friend) → student's name → mobile or email → course list as buttons → Asha counsels about the chosen course. Instant, no AI cost, EN/HI/MR, never a trap (voice note or repeated question → Asha). The answers feed identity matching, so a parent's and a friend's enquiries join the student's admission. `onboarding.ts` + 6 tests + docs/proof/onboarding_run.txt |
| 15e | Beyond: **every channel from one tap** | ✅ | Website and app: "Talk on WhatsApp / Telegram" buttons and scan-to-chat QR codes (WhatsApp, Telegram, Google Form), links editable in Admin → Channels → Public links |
| 15f | Beyond: **previous records** | ✅ | Desk search by name, any phone format, email, Telegram username or question; each lead shows "Questions asked" and "Earlier records (same phone or email)" with what they asked before |
| 15c | Beyond: burst load / the same question from thousands of people | ✅ | Answer cache + single-flight (1,000 identical → 1 AI call, tested), one reply per person, retries with back-off, autoscaling workers. Admin → Demo → Load test; Reports → Scale & cost |

## No lead forgotten — next-best-action engine

| # | Requirement | Status | How / where |
|---|---|---|---|
| 16 | Decides **when** | ✅ | Rules: hot → 2 h, warm → 24 h, cold → 72 h, objection playbooks next day, after-demo check-in; never 9 PM–9 AM IST |
| 17 | …**on which channel** | ✅ | The channel they actually use; pulled **inside WhatsApp's free 24 h window**; when a window is closed → call task for a human |
| 18 | …**with what message** | ✅ | AI writes it in their language and register; it passes the Guard |
| 19 | Based on **behaviour and objections** | ✅ | Playbooks: family approval → invite a parent to the demo; fees → EMI/listed scholarship; job fear → placement process; time → weekend/evening batch; trust → meet the trainer; 3 unanswered follow-ups → stop and call once. `nba.ts` + tests |
| 20 | Runs without anyone remembering | ✅ | Scheduled every 5 minutes; ⏩ "Jump to tomorrow 11 AM" shows a day passing in seconds. Even a person who stops halfway through the intake questions gets a nudge. If the AI itself is down, the person gets an instant knowledge-base answer and Asha retries automatically |

## Counsellor dashboard

| # | Requirement | Status | How / where |
|---|---|---|---|
| 21 | Every lead with a **score** | ✅ | **Explainable** 0–100: fit, intent, engagement, recency, aptitude, AI read, minus unresolved worries — shown as bars with reasons. `scoring.ts` |
| 22 | **Three-line summary** | ✅ | Who they are / what they want or fear / where we are |
| 23 | **Detected objections** — fees, job fears, family approval… | ✅ | 8 types, chips on cards and reports |
| 24 | **Suggested next message** | ✅ | In their language; one tap sends it on their channel |
| 25 | **Take over any conversation instantly** | ✅ | Asha stops on the next message; the counsellor's reply is delivered on WhatsApp/Telegram/Instagram/web; **Hand back** resumes |
| 26 | Beyond: assignment + alerts | ✅ | Leads assigned **by language** (round-robin among speakers); 🔔 hot-lead alerts for the assigned counsellor; "Mine" filter |

## Channels and reporting (optional items in the statement)

| # | Requirement | Status | Note |
|---|---|---|---|
| 27 | WhatsApp (text + voice notes) | ✅ | Meta Cloud API webhook (`metaWebhook`); setup in docs/SETUP_CHANNELS.md |
| 28 | Website chat + website form + walk-ins | ✅ | Chat docked in the site (EN/हिं/मरा UI), form continues into chat, walk-in counter with GPS + IST |
| 29 | Google Forms / Zapier / landing pages | ✅ | `intakeWebhook` + ready-made Apps Script in Admin |
| 30 | Telegram | ✅ | Free bot, any judge can use it |
| 31 | **Instagram DMs** | 🟡 | Real webhook + send code (`metaWebhook`, Instagram Login API). Needs a Professional account + Meta setup; demoed via the simulator through the same code path |
| 32 | **Answer and make phone calls via an Indian telephony provider** | 🟡 | Provider-agnostic `callWebhook` (Exotel/Twilio/Plivo/Knowlarity callback fields, voicemail recording → transcript → lead → AI follow-up), call tasks + one-tap call on the desk. No provider account connected; demoed via the simulator. Real-time AI voice calls are not built |
| 33 | **Conversion by source, counsellor and objection** | ✅ | Reports tab |

## Honest limitations
- SechTummit Trainers is a stand-in brand; all course data is sample data.
- WhatsApp test numbers reach only verified phones.
- Web-chat students are anonymous sessions (merged by phone/email when they share them).
- Google Calendar sync needs the one-time sharing step; without it bookings still work in Firestore and the desk shows "Calendar sync off".
