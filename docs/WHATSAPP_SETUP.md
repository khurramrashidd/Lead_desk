# WhatsApp setup (Meta WhatsApp Cloud API)

Free test setup: Meta gives you a **test business number** that can message **up to 5 verified phones**. Perfect for the demo (use your own phones).

Do this **after** the Cloud Functions are deployed once (README step 6).

## A. Create the Meta app
1. Go to https://developers.facebook.com and log in with Facebook. If asked, register as a developer (verify your phone/email).
2. **My Apps → Create App**.
3. App name: `AI Lead Desk`, your email → **Next**.
4. Use case: **Connect with customers through WhatsApp** → **Next**.
5. Business portfolio: pick yours or **create one** (any name, e.g. "Lead Desk Demo").
6. Review → **Next** → **Create app** (enter your Facebook password if asked).

## B. Get the test number and token
1. In the app's left menu: **WhatsApp → API Setup** (on the Quickstart page tap **Start using the API**).
2. Choose/create the WhatsApp Business account in the dropdown.
3. Click **Generate access token** → copy it. (This one is **temporary**; see section E for a permanent one.)
4. Under **From**: the test number is selected. Copy its **Phone number ID** (not the phone number itself).
5. Under **To**: add your WhatsApp number with country code (`+91…`) and confirm it with the code Meta sends you. Repeat for up to 5 phones (yours, teammate, demo phone).
6. Click **Send message**. You receive the "hello world" template on WhatsApp.
7. **Reply "Hi" from your phone.** This opens the 24-hour window in which free-form replies are allowed.

## C. Put the values in the project
Edit `functions\.env` (never commit this file):
```
WA_TOKEN=paste-the-access-token
WA_PHONE_ID=paste-the-phone-number-id
WA_VERIFY_TOKEN=leaddesk-verify-123
WA_GRAPH_VERSION=v23.0
```
(or paste the same values in **Admin → Channels → WhatsApp**, no redeploy needed). Deploy with `deploy` (see README).

The webhook URL is **`https://asia-south1-<project-id>.cloudfunctions.net/metaWebhook`**
(for this project: `https://asia-south1-lead-desk-39885.cloudfunctions.net/metaWebhook`). It is also shown,
with a Copy button, in **Admin → Channels → WhatsApp**.

## D. Connect the webhook
1. App Dashboard → **WhatsApp → Configuration**.
2. Under **Webhook** click **Edit**:
   - **Callback URL**: the metaWebhook URL from step C
   - **Verify token**: exactly the same word as `WA_VERIFY_TOKEN` (e.g. `leaddesk-verify-123`)
   - Click **Verify and save**. Meta calls our function; it answers the challenge.
3. Under **Webhook fields** click **Manage** → turn on **messages** → **Done**.
   ⚠️ Without subscribing to **messages** you will receive nothing.
4. **Admin → Channels → WhatsApp → Subscribe webhook.** This links your WhatsApp Business Account to the app
   (`POST /<WABA-ID>/subscribed_apps`) and points it straight at metaWebhook. Without it Meta delivers nothing,
   even when the dashboard says "Verified". The WABA ID is found automatically from the token; if not, copy
   it from **WhatsApp → API Setup** (under the phone number) into the field.
5. **Admin → Channels → Diagnose → Run diagnosis.** "WhatsApp: last call received from Meta" must turn ✅ after you
   send a message. If it still says Meta never called, the problem is on the Meta side (steps D1–D4, the "To" list).

## E. Permanent token (so it doesn't expire during judging)
1. Go to https://business.facebook.com → **Business settings** → **Users → System users** → **Add** → name `leaddesk-bot`, role **Admin**.
2. Select the system user → **Assign assets**:
   - **Apps** → your app → **Manage app** (full control)
   - **WhatsApp accounts** → your WhatsApp Business account → **Manage WhatsApp Business accounts** (full control)
   - **Assign assets**
3. **Generate token** → choose your app → tick **whatsapp_business_messaging**, **whatsapp_business_management** and **business_management** → generate → copy.
4. Put it in `WA_TOKEN` in `functions\.env` → `firebase deploy --only functions`.

## F. Test
1. From a verified phone, send the test number: `Namaskar, mala Java course baddal mahiti havi aahe` or a voice note.
2. Asha replies on WhatsApp in a few seconds.
3. The lead appears on the Counsellor Desk with a 🟢 WhatsApp tag.
4. Tap **Take over** on the desk and type a reply → it arrives on WhatsApp.

## Troubleshooting
| Problem | Fix |
|---|---|
| "Verify and save" fails | Function not deployed, or the verify token differs from `WA_VERIFY_TOKEN` (check spaces). Use the exact URL from the deploy output. |
| Webhook verified but nothing arrives (not even on the desk) | Subscribe to the **messages** field (step D3) **and** press **Subscribe webhook** (step D4). With the test number, your phone must be in the **To** list. Run **Diagnose**. |
| Message on the desk but Asha does not reply | Run **Admin → Channels → Diagnose**: it shows the AI error, a token error (190) or "not in allowed list" (131030). |
| AI reply never reaches WhatsApp | Token expired (error 190) → new token (section E). Or the number is not in the "To" list. |
| Reminder not delivered on WhatsApp | WhatsApp only allows free-form messages within **24 hours** of the student's last message. Outside it the desk flags "send an approved template or call". |
| Voice note says "could not be downloaded" | Token lacks permissions → use the system-user token with the 3 permissions. |

Source: Meta docs — https://developers.facebook.com/docs/whatsapp/cloud-api/get-started/
