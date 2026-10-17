# Proving every sentence of "What to Build"

**Live proof (use this for the judges):** Admin → Demo → **Open the self-test** (or `/selftest`).

- Each test talks to the real AI and the real database.
- Each records ✅/❌ checks plus the actual conversation as evidence.
- Each links to the leads it created, so you can open them on the desk.

Run the tests one by one, or press **Run all, one by one** (about 8–12 minutes on free keys). Then press **Copy report** to get a Markdown report for the submission.

**Code-path proof (already done):** `docs/proof/offline_pipeline_run.txt`.
- All 20 tests were run against an in-memory database with a scripted AI: 15 pass and 5 warn, all expected (listed under the table).
- Backend unit tests: `npm test` → **30 passing**.
- Intake questions (web, real WhatsApp webhook parser, real Telegram update parser) and an AI outage:
  `docs/proof/onboarding_run.txt` → **23/23 checks**.
- The "Asha keeps typing" fix (retired model names, per-model thinking level, same-key fallback):
  `docs/proof/model_fallback_run.txt`.

| # | Sentence in the problem statement | How the system does it | How the test proves it |
|---|---|---|---|
| 1 | "holds genuine counselling conversations" | The prompt makes Asha counsel, not answer FAQs: empathise with the worry behind the question, ask one question at a time, and remember the lead state. | Sends the sponsor's exact "commerce graduate with a two-year gap" question. The reply must not be a fee list, must ask a question back and must be a real answer. |
| 2 | "text … in English, Hindi and Marathi" | Gemini understands all three. The model reports the language it saw, and the reply mirrors it. | Three prospects, one per language; each reply must come back in the same language. |
| 3 | "including mid-sentence switches" | The prompt requires the same blend and the same script. | Hinglish and Marathi-English messages; the replies must stay mixed and in Latin script. |
| 4 | "reply in the language **and register**" | The model returns `register`; the prompt mirrors aap/tum and तुम्ही/तू. | A casual and a formal message: register detected correctly, and the formal reply uses "आप". |
| 5 | "voice notes" | Audio goes straight to Gemini. If Gemini is busy, Groq Whisper transcribes it for the fallback models. The transcript is saved on the message. | A Marathi voice note (WhatsApp) and a Hindi one (Telegram): transcript saved, reply in the same language. |
| 6 | "ask about background, goals and constraints" | The lead `profile` (education, gap, work, goal, timing, budget, family view) is filled in as the chat goes. | The details must appear in the profile and as objections. |
| 7 | "answer course, fee and schedule questions strictly from a knowledge base the institute controls" | `kb/main` is edited in Admin; the website reads the same document. | The reply must quote the exact fee, EMI and batch date from the KB. |
| 8 | "never invent discounts, fees or placement guarantees, even when pressed" | The **Guard** checks every number, percentage, discount word and guarantee phrase (EN/HI/MR) against the KB. It blocks the draft, the AI rewrites once, else a safe reply is sent. | 5 invented drafts are blocked; then Asha is pressed 3 times and every reply passes. The desk shows 🛡 when a draft was rewritten. |
| 9 | "short adaptive aptitude check" | 23-question bank, 4 questions. Right answer → harder, wrong → easier. Scored **on the server**, with tap-to-answer chips. | Answers right, wrong, right, right; checks each score and that the next question goes up or down a level. |
| 10 | "recommend a program with an honest reason" | One KB course plus a reason tied to background, constraints and aptitude. | A beginner gets one KB course with a specific reason, not the most expensive one. |
| 11 | "book a demo class into a real calendar slot with reminders" | Seat booked in a Firestore transaction and created as a Google Calendar event. The heartbeat sends reminders 24 h and 1 h before. | Books by chat, checks the seat count, then runs the real heartbeat for that lead at T-23 h and T-30 min: both reminders fire. |
| 12 | "Rahul Patil (form) = राहुल पाटल (WhatsApp, other phone format) → one timeline" | Phones normalised; Devanagari transliterated; given-name-aware matching. | Form, then the **real WhatsApp webhook parser** → merged. Also checked: father and friend → same lead; daughter → linked lead; another Rahul Patil → not merged. |
| 13 | "next-best-action: when, which channel, what message, from behaviour and objections" | Rules pick the playbook and time (never 9 PM–9 AM, inside WhatsApp's 24 h window). The AI writes the message. | Family-approval vs fees objection → different playbooks; then the follow-up fires on its own. |
| 14 | "dashboard: score, three-line summary, objections, suggested message" | Score shown with its breakdown; 3 summary lines; objection chips; suggested message; assignment by language. | A lead with fees + job fear + family approval must show all of these. |
| 15 | "take over any conversation instantly" | `aiPaused`: the AI worker stands down on the next message, the desk flags the lead for the human, and the counsellor's reply is delivered on the lead's channel. | After take-over, a new message gets **no** AI reply; the counsellor's reply lands in the chat. |
| 16 | "keeps every enquiry in one place" | All channels write to the same `leads` collection. | One enquiry per channel (8 channels) → all in one list, each with its source. |
| 17 | (optional) telephony | Provider-agnostic `callWebhook` turns a missed call or voicemail into a lead and a follow-up. | Simulated: no provider account yet. |
| 18 | (optional) Instagram DMs | `metaWebhook` parses Instagram messaging. | The real parser is fed an IG payload → lead + reply. |
| 19 | (optional) "conversion by source, counsellor and objection" | Reports tab. | Computes all three. |
| 20 | Beyond: scale | Answer cache + single-flight + one reply per person + retries. | Two strangers send the same question at once → one AI call. |

**Expected ⚠️ warnings:**
- **Voice:** the test voice notes are synthetic; also record a real one on the phone.
- **Booking:** "Calendar sync off" until Google Calendar is connected (docs/SETUP_CHANNELS.md §3).
- **Telephony and Instagram:** accounts are not connected.
- **Reports:** no sample leads yet; use Admin → Demo → Load everything.
