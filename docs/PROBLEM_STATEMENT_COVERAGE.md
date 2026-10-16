# PS3 — AI Lead Desk: what is built, line by line

Every sentence of the sponsor's problem statement, and exactly where it lives in the code.
Status is honest: ✅ built and demoable · 🟡 built with a stated limit · ⬜ not built.

---

## The counsellor

| # | Requirement (sponsor's words) | Status | Where |
|---|---|---|---|
| 1 | "understand text and voice notes in English, Hindi and Marathi" | ✅ | Audio goes straight to Gemini — no separate speech-to-text. `functions/src/brain.ts` (`toContents`, `inlineData`), `lib/services/voice_recorder.dart` |
| 2 | "including mid-sentence switches between them" | ✅ | System prompt rule: *reply in the SAME language blend*. `brain.ts` → `systemPrompt` |
| 3 | "reply in the language **and register** the prospect uses" | ✅ | `register: formal \| casual` is a required field of the model's reply, and the prompt mirrors aap/tum, तुम्ही/तू. `brain.ts` |
| 4 | "ask about background, goals and constraints" | ✅ | `profile` schema: background, education, gap, currentWork, goal, constraints, budget, timing, familyView. Shown in "What we know" on the desk |
| 5 | "answer course, fee and schedule questions **strictly** from a knowledge base the institute controls" | ✅ | `kb/main` in Firestore, edited in **Admin → Knowledge base**. The public website reads the same document, so the site and the AI can never disagree. `lib/data/institute.dart` |
| 6 | "never invent discounts, fees or placement guarantees, **even when pressed**" | ✅ | The **Guard** re-checks every reply: every ₹ amount, every %, every guarantee phrase (English/Hindi/Marathi) must exist in the knowledge base, else the draft is blocked and rewritten. `functions/src/guard.ts` + 6 unit tests |
| 7 | "run a short **adaptive** aptitude check" | ✅ | 4 questions max, one per message, harder after a right answer and easier after a wrong one; state carried in `aptitude`. `brain.ts` |
| 8 | "recommend a program with an honest reason" | ✅ | `recommendation {course_id, reason}`, with an explicit instruction to say when a course is wrong for them today |
| 9 | "book a demo class into a **real** calendar slot" | ✅ | `slots` collection with real capacity, booked inside a Firestore transaction so two people cannot take the last seat. `brain.ts` → booking block |
| 10 | "with reminders" | ✅ | 24 h and 1 h before, sent on the lead's own channel by the 5-minute heartbeat. `functions/src/heartbeat.ts` |

## One person, one lead

| # | Requirement | Status | Where |
|---|---|---|---|
| 11 | «"Rahul Patil" and "राहुल पाटल" with a differently formatted phone number are the same person» | ✅ | Phone normalised to the last 10 digits; Devanagari transliterated; Jaro-Winkler with Indian spelling rules (v/w, sh/s, ee/i). `functions/src/identity.ts` — tested with the sponsor's exact example |
| 12 | "merge them into a single timeline" | ✅ | Messages, sources, objections, contacts and the booking all move onto the older lead. `functions/src/merge.ts`; the student's own chat follows the merge |
| 13 | *Beyond the statement:* the student, a parent and a friend can all enquire about **one** admission | ✅ | A lead has one **student** and many **contacts**. Matching runs on student phone, contact phones and email. Desk shows "Enquiring as parent · student: Pooja". `merge.ts` → `resolveIdentity`, `LeadContact` in `db.ts` |
| 14 | Ambiguous case: one phone, two names | 🟡 | Not auto-merged — flagged as "Possible duplicate" for a counsellor to confirm. Guessing here would be worse than asking |

## Never forgotten

| # | Requirement | Status | Where |
|---|---|---|---|
| 15 | "a next-best-action engine decides **when**" | ✅ | `next_action.in_hours`, pushed out of 9 PM–9 AM IST by `respectQuietHours`. `functions/src/lang.ts` |
| 16 | "**on which channel**" | ✅ | Follows the channel they actually use (WhatsApp → Telegram → web), or flags a human call. `brain.ts` → `preferredChannel` |
| 17 | "**with what message**" | ✅ | A written message in their language, plus a `reason` in English for the counsellor |
| 18 | "based on their behaviour and the objections they have raised" | ✅ | Prompt rule: family approval → invite the parent; fees → EMI or a listed scholarship; booked → check in afterwards |
| 19 | "follow-ups depend on a counselor remembering" (the pain) | ✅ | The 5-minute heartbeat sends them whether or not anyone is logged in. ⏩ **Fast-forward** in the desk demonstrates a day passing in seconds |

## The counsellor's dashboard

| # | Requirement | Status | Where |
|---|---|---|---|
| 20 | "every lead with a score" | ✅ | 0–100 ring, hot/warm/cold. `lib/widgets/lead_widgets.dart` |
| 21 | "a three-line summary" | ✅ | Exactly three lines: who they are / what they want or fear / where we are |
| 22 | "detected objections — fees, job fears, family approval" | ✅ | Eight objection types as chips on the card and in reports |
| 23 | "a suggested next message" | ✅ | One tap sends it as the counsellor, in the prospect's language |
| 24 | "take over any conversation instantly" | ✅ | **Take over** pauses the AI on the next message; **Hand back** resumes it. `Repo.setTakeover` |

## The channels the enquiry arrives on

| # | Channel | Status | Where |
|---|---|---|---|
| 25 | WhatsApp | ✅ | Cloud API webhook, text **and** voice notes, with the 24-hour reply window handled honestly. `functions/src/whatsapp.ts`, `docs/WHATSAPP_SETUP.md` |
| 26 | Website chat | ✅ | Docked into the institute's own site, no login. `lib/screens/site/`, `lib/screens/chat/` |
| 27 | Website form | ✅ | Submitting continues straight into a counselling conversation |
| 28 | Walk-ins | ✅ | Front-desk screen with automatic location and IST timestamp |
| 29 | Phone calls | 🟡 | A counsellor logs the call from any lead ("Log a phone call") and Asha drafts the follow-up. Automated answering through an Indian telephony provider is **not** built — but any IVR can POST to `intakeWebhook` and become a channel |
| 30 | Telegram | ✅ | *Beyond the statement.* Bot webhook, text and voice notes, free to set up from Admin → Channels |
| 31 | Google Forms / IVR / Zapier | ✅ | *Beyond the statement.* One `intakeWebhook` endpoint; Admin hands you the Apps Script to paste |
| 32 | Instagram direct messages | 🟡 | The webhook already parses IG messages, so it works the moment Meta approves `instagram_manage_messages` on a Business account. Until then: a tagged bio link (so the source is still measured) plus "Log an Instagram DM" on the desk |
| 33 | "nobody can say which source actually produces admissions" | ✅ | Reports: conversion by source, by counsellor and by objection |

## The optional extras in the statement

| # | Requirement | Status | Note |
|---|---|---|---|
| 34 | "answer and make phone calls through an Indian telephony provider" | ⬜ | Not built. The hook exists (`intakeWebhook` for inbound, `nextAction.channel == 'call'` for outbound), so a provider like Exotel or Knowlarity is an integration, not a redesign |
| 35 | "capture Instagram direct messages" | 🟡 | See row 32 |
| 36 | "report conversion by source, counselor and objection" | ✅ | All three, on the Reports tab |

## Things we added because the problem demanded them

| | | |
|---|---|---|
| **Talk to a human** | ✅ | When counselling is not enough, the AI (or any page) collects name, phone, email and a one-line brief, and books a real **phone call** or **video meeting** slot with reminders. `lib/screens/site/book_call_sheet.dart` |
| **Several AI keys** | ✅ | Admin lists several free Gemini keys with their own models; they are tried in order, so a rate-limited key never stops a conversation. `functions/src/ai.ts`, Admin → AI engine |
| **Answer speed** | ✅ | Minimal "thinking" by default, a fast model first, and a **Warm up** button for the moments before judging |
| **Role-based access** | ✅ | Students see only their own chat; counsellors need admin approval; API keys are readable by admins only. `firestore.rules` |

---

## Honest limitations

- **SechTummit Trainers is a stand-in brand** for the demo. Courses, fees, hiring-partner names and student stories are sample content, editable in Admin, and labelled as samples on the page.
- Student identity on the web chat is an anonymous Firebase session, so clearing the browser starts a new conversation.
- Voice notes up to ~60 seconds are stored inside the Firestore document, which avoids needing Cloud Storage.
- Outbound telephony is not built (row 34).
