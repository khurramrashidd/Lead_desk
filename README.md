# AI Lead Desk

**An AI admissions counsellor for coaching institutes. It answers students on the website, Telegram and WhatsApp, gives them course advice, enrols them and collects the fee, all on its own, around the clock.**

🔗 **Live demo:** https://lead-desk-39885.web.app  
📱 **Android app:** [APK link]  
👥 **Team:** [BuntyBubli] · [Khurram Rashid] · [Kinza Zahra]

---

## The problem
Institutes lose students because enquiries come in at night, on different apps and in different languages. Counsellors can't reply to everyone in time, and the details end up spread across chats, notebooks and spreadsheets.

## Our solution
**Asha** is an AI counsellor who replies within seconds on every channel. She takes the student from the first "Hi" all the way to a confirmed admission. The institute's team watches everything on one live desk and steps in only when needed.

## Key features
**For students (website · Telegram · WhatsApp)**
- 🌐 Picks a language first: English, Hindi or Marathi (Hinglish works too); voice notes supported
- 🎯 Honest advice and a short aptitude check that recommends the right course
- 📝 Enrolment form in the chat with input checks, a summary to confirm, and email OTP verification
- 💳 UPI QR payment; the student sends a screenshot of the receipt in the chat
- 🆔 Asks "What's my admission ID or status?" and gets the answer from the records, with an email code when asking from a different channel
- 📅 Books a call or demo and gets automatic reminders
- 🔄 Chat closes on its own after 2 minutes idle; one tap to restart

**For the institute (admin and counsellors)**
- 🔔 Live desk with instant alerts; conversations open in a side panel or a pop-up
- ✅ One-click **Verify & allot** creates the admission ID and sends confirmation on chat, WhatsApp and email
- 📊 Master dashboard: KPIs, charts, the same person merged across channels, registered students with receipts, CSV export
- 🤖 **Ask AI**: ask questions about the data in plain words ("Who paid but isn't verified?")
- 🛡️ Guardrails: no fake discounts or job guarantees; hands over to a human when needed
- 🩺 One-click diagnosis of every channel and service

## How it works
Student message (website / Telegram / WhatsApp)
→ Cloud Function webhook → Firestore
→ Asha (AI) + enrolment and payment flow
→ reply on the same channel + live update on the admin desk

## Tech stack
| Layer | Technology |
|---|---|
| App | Flutter (web + Android) |
| Backend | Firebase Cloud Functions (TypeScript), Firestore, Hosting |
| AI | Google Gemini |
| Channels | Telegram Bot API, WhatsApp Cloud API, web chat |
| Payments and email | UPI QR, Gmail SMTP (OTP and confirmations) |

## Impact
- ⏱️ Replies in seconds, 24×7
- 📈 No enquiry is lost: every channel lands in one place
- 👩‍💼 Counsellors only handle verified payments and the hard cases
