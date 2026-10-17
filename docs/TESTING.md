# Test on the phone (app + web) and the laptop

## A. Android app on your phone (`flutter run`)
1. Phone: **Settings → About phone → tap "Build number" 7 times** → back → **Developer options → USB debugging ON**.
2. Connect the USB cable → on the phone tap **Allow** ("Allow USB debugging?", tick "Always allow").
3. Laptop, in the project folder:
   ```bat
   flutter devices
   flutter run
   ```
   `flutter run` lists your phone and Chrome; type the number of the phone. (Or `flutter run -d <phone-id>`.)
4. While it runs: press **r** to reload after a change, **q** to quit.

If Google sign-in on the phone fails ("error 10" / DEVELOPER_ERROR), add the SHA keys once:
```bat
cd android
gradlew signingReport
cd ..
```
Copy SHA1 + SHA-256 of `Variant: debug` → Firebase Console → Project settings → Android app → **Add fingerprint** → download the new `google-services.json` into `android\app\`.

## B. Web app on your phone (what judges will open)
```bat
deploy hosting
```
Open **https://lead-desk-39885.web.app** on the phone → chat with Asha → mic works (HTTPS) → browser menu **Add to Home screen** (installs like an app).

## C. Automatic proof (recommended first)
Laptop: Desk → Admin → Demo → **Open the self-test** → **Run all, one by one** (8–12 min) → **Copy report**.
Every sentence of the problem statement is tested live with evidence. Details: docs/PROOF.md.

## D. Manual test script (two screens: desk on the laptop, chat on the phone)

| # | Do this | Expect |
|---|---|---|
| 1 | Phone: website → **हिं / मरा** switch | Site and chat texts change language |
| 2 | Phone: chat → "I'm a commerce graduate with a two-year gap — can I really become a developer?" | Honest counselling reply in seconds; lead appears live on the laptop desk |
| 3 | Phone: send a **Marathi or Hinglish voice note** | Reply in the same language and tone; transcript visible on the desk |
| 4 | Accept the aptitude check, **tap A/B/C chips** | 4 questions, harder after a right answer; desk shows ✓/✗ per question, band, then a recommendation |
| 5 | Pick a demo slot | Booked; "Add to Google Calendar" button; desk shows reminders + calendar sync |
| 6 | "My friend got 30% off, give me the same" | Polite refusal; 🛡 Guard badge on the desk |
| 7 | Laptop: **Take over** → type a reply | Asha stops; your reply appears on the phone |
| 8 | Laptop: Desk → 🧪 **Simulate** presets **1 → 5** | Rahul + father + friend = **one** lead with 3 contacts; father's daughter Priya = a **second, linked** lead |
| 9 | 🧪 preset **6** twice | Second answer labelled **⚡ instant: same question answered before** |
| 10 | Admin → Demo → **Load test: 30 at once** → Desk → Reports | 30 leads answered; **Scale & cost** shows about 3 AI calls instead of 30 |
| 11 | Desk → ⏩ **Jump to tomorrow 11 AM** | Reminders and objection-based follow-ups fire, each with its reason |
| 12 | Desk → Reports | Conversion by source, counsellor, objection |
| 13 | Send 3 quick messages in a row from the phone | One reply covering all three (desk: "answered 3 messages together") |
