# Setting up every enquiry channel (in the order that pays off fastest)

Everything below is entered in the app at **Admin → Channels** or **Admin → AI engine** —
no redeploy needed. Do the functions deploy once first (README, step 3).

| # | What | Time | Cost |
|---|---|---|---|
| 1 | AI keys (Gemini + Groq + OpenRouter) | 5 min | free |
| 2 | Telegram bot | 3 min | free |
| 3 | Google Calendar | 8 min | free |
| 4 | Google Form → leads | 5 min | free |
| 5 | WhatsApp (Meta test number) | 25 min | free |
| 6 | Instagram DMs | 30+ min, needs a Professional account | free |
| 7 | Phone calls (Exotel / Twilio / Plivo) | needs KYC | paid |

Anything you skip still works in the demo through **Desk → 🧪 Simulate**, which sends a
message through exactly the same code path as the real channel.

---

## 1. AI keys (5 min)
1. **Gemini**: https://aistudio.google.com → *Get API key* → copy. Make 2–3 keys from different Google accounts if you can.
2. **Groq**: https://console.groq.com/keys → *Create API Key* (starts with `gsk_`). Also used for free Whisper speech-to-text.
3. **OpenRouter**: https://openrouter.ai/keys → *Create Key* (starts with `sk-or-`). Model `openrouter/free`.
4. App → **Admin → AI engine** → pick provider → paste key → **Test** → **Add to pool**. Put Gemini keys first.
   Live models (Oct 2026): Gemini `gemini-3.6-flash` (default), `gemini-3.8-flash`, `gemini-3.5-flash-lite`;
   Groq `openai/gpt-oss-120b`. Retired names are mapped automatically, but press **Test** on every key:
   a ❌ there is exactly what made Asha "keep typing".
5. Two minutes before judging press **Warm up**. If every key fails, Admin → AI engine shows the reasons
   ("Last time every key failed…") and people still get knowledge-base answers.

You can also put them in `functions\.env` (`GEMINI_API_KEY=key1,key2`, `GROQ_API_KEY=…`, `OPENROUTER_API_KEY=…`) and run `deploy`.

## 2. Telegram (3 min) — the easiest channel for judges
1. In Telegram open **@BotFather** → `/newbot` → name `SechTummit Admissions` → username ending in `bot`.
2. Copy the token → **Admin → Channels → Telegram → paste → Save & connect**. It shows `@yourbot is live · webhook set`.
3. Message the bot from any phone. Asha replies there; the lead appears on the desk with ✈️ Telegram.
4. The website home, ☰ → Contact, the judges' hub (`/demo`) and Admin → Demo already show the Telegram QR
   (`https://t.me/LeadDeskIndiaBot?start=web`). Change the bot in **Admin → Channels → Public links**.

## 3. Google Calendar (8 min) — real demo-class bookings
1. https://console.cloud.google.com → select project **lead-desk-39885** → search **Google Calendar API** → **Enable**.
2. https://calendar.google.com → left panel **Other calendars → +** → **Create new calendar** → name `Demo classes` → Create.
3. App → **Admin → Channels → Google Calendar → Save & test**. It shows **"Share the calendar with: …@developer.gserviceaccount.com"** (copy it).
4. Google Calendar → `Demo classes` → ⋮ **Settings and sharing** → **Share with specific people → Add people** → paste that email → permission **Make changes to events** → Send.
5. Same settings page → **Integrate calendar** → copy **Calendar ID** → paste in the app → **Save & test** → ✅ `Connected to "Demo classes"`.

Every booking now appears in that calendar with the lead's name, phone and language. Students get an Add-to-Calendar link in chat and reminders 24 h and 1 h before.

## 4. Google Form → leads (5 min)
1. Create a Google Form with questions like *Name, Phone, Email, Course, Your question*.
2. Form → ⋮ → **Script editor** (Apps Script) → delete everything → paste the script from **Admin → Channels → Google Forms → Apps Script** (copy button).
3. Left: ⏰ **Triggers → Add trigger** → function `onSubmit` → event source **From form** → event type **On form submit** → Save → allow permissions.
4. Submit the form once → the lead appears on the desk with 🧾 Google Form, and Asha follows up.

Any other tool (Zapier, a landing page) can `POST` JSON to the **Intake URL** with header `x-intake-secret`:
```json
{ "source": "googleform", "name": "Rahul Patil", "phone": "098765 43210", "course": "Full Stack Java", "message": "Weekend batch?" }
```

## 5. WhatsApp (25 min)
1. https://developers.facebook.com → **My Apps → Create App** → use case **Connect with customers through WhatsApp** → create/choose a business portfolio → **Create app**.
2. Left menu **WhatsApp → API Setup**: **Generate access token** (copy), copy the **Phone number ID** (not the number).
3. Under **To**, add your own WhatsApp number (+91…) and verify the code. **Meta's free test number
   (yours: +1 555 199 3241) receives messages from anyone, but replies are delivered only to the up-to-5
   numbers in this "To" list.** On judging day add the judges' numbers here (each gets a code to confirm);
   everyone else: Telegram or the web chat. The desk marks undelivered replies with Meta's reason
   (`#131030 … not in allowed list`).
4. App → **Admin → Channels → WhatsApp**: paste token + phone number ID → **Save & test** (✅ Connected).
5. Meta: **WhatsApp → Configuration → Webhook → Edit**: Callback URL = the **Webhook URL** shown in the app (`…/metaWebhook`), Verify token = the one shown (`leaddesk-verify-123`) → **Verify and save** → **Webhook fields → Manage → messages → Subscribe**.
6. Send "Hi" from your verified phone to the test number → Asha replies.
7. Token expires in ~24 h. For judging day make a permanent one: business.facebook.com → Business settings → **System users** → Add (Admin) → **Assign assets** (your app + WhatsApp account, full control) → **Generate token** with `whatsapp_business_messaging`, `whatsapp_business_management` → paste in Admin.

Rule handled for you: free-form replies are allowed only within 24 h of the student's last message. The follow-up engine moves follow-ups inside that window, and when it is closed it creates a **call task** instead of failing silently.

## 5b. Website QR codes, "Talk on WhatsApp / Telegram", intake questions
- **Admin → Channels → Public links**: WhatsApp number (digits with country code, e.g. `15551993241`),
  the pre-filled message (`Hi Asha 👋`), the Telegram bot (`LeadDeskIndiaBot`) and the Google Form link.
  Saving updates every button and QR code at once (Firestore `config/public`, readable by everyone).
- **Admin → Channels → Intake questions before counselling** (on by default): new WhatsApp, Telegram,
  Instagram and web chats first answer: who is this for → student's name → mobile/email → course list.
  Never asked again for that person; never for sample data, simulators or the self-test.

## 6. Instagram DMs (optional)
Needs an Instagram **Professional** account. In the same Meta app: **Add product → Instagram → API setup with Instagram login** → add your account → **Generate token** → paste token + Instagram user ID in **Admin → Channels → Instagram** → subscribe the same webhook URL to **messages**. In development mode only accounts added as app testers can DM it. For the demo use **🧪 Simulate → Instagram**.

## 7. Phone calls (optional)
Exotel / Twilio / Plivo / Knowlarity: set the missed-call / voicemail / status callback to the **Call webhook** URL shown in Admin → Channels (it includes `?key=`). The caller's number (`From` / `CallFrom`) and any `RecordingUrl` become a 📞 Call lead; Asha transcribes the voicemail and follows up on WhatsApp; the desk gets a call task and a one-tap **Call** button. For the demo use **🧪 Simulate → Phone call**.
