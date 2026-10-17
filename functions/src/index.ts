/**
 * Cloud Functions entry point.
 *
 * Deploying from a slow laptop: the Firebase CLI loads this file to discover the functions and
 * gives up after 10 seconds by default. So this file only imports firebase-functions; our own
 * code is loaded INSIDE the handlers with `await import(...)`. Use deploy.bat (it also raises
 * the limit).
 */
import { setGlobalOptions } from "firebase-functions/v2/options";
import { onDocumentCreated, onDocumentWritten } from "firebase-functions/v2/firestore";
import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import type { Lead, Message } from "./db";

// Mumbai — same region as the Firestore database.
setGlobalOptions({ region: "asia-south1", maxInstances: 10 });

/** Every new message: prospect → Asha replies; counsellor → forwarded to their channel. */
export const onMessageCreated = onDocumentCreated(
  { document: "leads/{leadId}/messages/{msgId}", timeoutSeconds: 120, memory: "512MiB" },
  async (event) => {
    const msg = event.data?.data() as Message | undefined;
    if (!msg || msg.mergedFrom || msg.seed) return; // copied during a merge, or sample data
    const { leadId, msgId } = event.params;
    const { db } = await import("./db");
    const { deliverOn } = await import("./channels");

    if (msg.role === "counsellor") {
      const lead = (await db.doc(`leads/${leadId}`).get()).data() as Lead | undefined;
      if (lead && msg.text && ["whatsapp", "telegram", "instagram"].includes(msg.channel)) {
        const r = await deliverOn(msg.channel, lead, msg.text);
        if (!r.delivered) await event.data?.ref.set({ meta: { delivered: false, note: r.note || "send failed" } }, { merge: true });
      }
      return;
    }
    if (msg.role !== "user") return;

    // If this enquiry was just merged into an older lead (same person), answer there.
    let target = leadId;
    const current = (await db.doc(`leads/${leadId}`).get()).data() as Lead | undefined;
    if (current?.mergedInto) {
      target = current.mergedInto;
      const copy = db.doc(`leads/${target}/messages/${msgId}`);
      if (!(await copy.get()).exists) await copy.set({ ...msg, mergedFrom: leadId });
    }

    const { counsel } = await import("./brain");
    const result = await counsel(target, msgId);
    if (result && ["whatsapp", "telegram", "instagram"].includes(result.channel)) {
      const lead = (await db.doc(`leads/${target}`).get()).data() as Lead | undefined;
      if (lead) await deliverOn(result.channel, lead, result.reply);
    }
  },
);

/** New lead from a form, walk-in or web chat: check if we already know this person. */
export const onLeadCreated = onDocumentCreated("leads/{leadId}", async (event) => {
  const lead = event.data?.data() as Lead | undefined;
  if (!lead || lead.seed) return;
  const { resolveIdentity } = await import("./merge");
  const { assignByLanguage } = await import("./assign");
  if (lead.phone || lead.email) await resolveIdentity(event.params.leadId);
  const fresh = (await event.data!.ref.get()).data() as Lead | undefined;
  if (fresh && !fresh.mergedInto && !fresh.assignedUid) {
    await assignByLanguage(event.params.leadId, fresh, fresh.language).catch((e) => console.warn("assign failed", e));
  }
});

/** Name, phone or email added later (e.g. typed into the web chat). */
export const onLeadIdentityChanged = onDocumentWritten("leads/{leadId}", async (event) => {
  const before = event.data?.before.data() as Lead | undefined;
  const after = event.data?.after.data() as Lead | undefined;
  if (!before || !after || after.mergedInto || after.seed) return;
  const { normalizePhone } = await import("./identity");
  const changed =
    (normalizePhone(before.phone) ?? "") !== (normalizePhone(after.phone) ?? "") ||
    (before.email ?? "") !== (after.email ?? "") ||
    (before.name ?? "") !== (after.name ?? "");
  if (!changed || (!after.phone && !after.email)) return;
  const { resolveIdentity } = await import("./merge");
  await resolveIdentity(event.params.leadId);
});

/** Meta webhook: WhatsApp Cloud API + Instagram DMs. */
export const metaWebhook = onRequest(async (req, res) => {
  const { channelConfig } = await import("./channels");
  if (req.method === "GET") {
    const c = await channelConfig(true);
    const ok = req.query["hub.mode"] === "subscribe" && req.query["hub.verify_token"] === c.waVerifyToken;
    res.status(ok ? 200 : 403).send(ok ? String(req.query["hub.challenge"] ?? "") : "forbidden");
    return;
  }
  try {
    const { handleMetaWebhook } = await import("./whatsapp");
    await handleMetaWebhook(req.body);
  } catch (e) {
    console.error("meta webhook error", e);
  }
  res.sendStatus(200);
});

/** Telegram bot webhook (set from Admin → Channels → Telegram → Connect). */
export const telegramWebhook = onRequest(async (req, res) => {
  const { channelConfig } = await import("./channels");
  const c = await channelConfig();
  if (req.get("x-telegram-bot-api-secret-token") !== c.telegramSecret) {
    res.sendStatus(403);
    return;
  }
  try {
    const { handleTelegramUpdate } = await import("./telegram");
    await handleTelegramUpdate(req.body);
  } catch (e) {
    console.error("telegram webhook error", e);
  }
  res.sendStatus(200);
});

/** Google Forms / Zapier / landing pages / IVR: POST JSON with header x-intake-secret. */
export const intakeWebhook = onRequest({ cors: true }, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("POST JSON here");
    return;
  }
  const { channelConfig } = await import("./channels");
  const c = await channelConfig();
  const secret = req.get("x-intake-secret") ?? String(req.query.key ?? "");
  if (secret !== c.intakeSecret) {
    res.status(403).json({ ok: false, detail: "bad secret" });
    return;
  }
  try {
    const { handleIntake } = await import("./intake");
    const r = await handleIntake(req.body ?? {});
    res.json({ ok: true, ...r });
  } catch (e) {
    console.error("intake error", e);
    res.status(500).json({ ok: false, detail: String((e as Error).message) });
  }
});

/**
 * Telephony (provider-agnostic): Exotel / Twilio / Plivo / Knowlarity status or voicemail
 * callbacks. Reads the caller from From / CallFrom / caller / phone and an optional
 * RecordingUrl, and turns it into a "call" enquiry that Asha follows up.
 */
export const callWebhook = onRequest({ cors: true }, async (req, res) => {
  const { channelConfig } = await import("./channels");
  const c = await channelConfig();
  const secret = req.get("x-intake-secret") ?? String(req.query.key ?? "");
  if (secret !== c.intakeSecret) {
    res.status(403).send("bad secret");
    return;
  }
  const b = { ...(req.query as Record<string, unknown>), ...((req.body as Record<string, unknown>) ?? {}) };
  const phone = String(b.From ?? b.CallFrom ?? b.caller ?? b.from ?? b.phone ?? "");
  const rec = String(b.RecordingUrl ?? b.recording_url ?? b.RecordUrl ?? "");
  let audio: { b64: string; mime: string } | null = null;
  if (rec.startsWith("http")) {
    try {
      const r = await fetch(rec, { signal: AbortSignal.timeout(15_000) });
      const buf = Buffer.from(await r.arrayBuffer());
      if (r.ok && buf.length < 700_000) audio = { b64: buf.toString("base64"), mime: (r.headers.get("content-type") || "audio/mpeg").split(";")[0] };
    } catch (e) {
      console.warn("recording download failed", e);
    }
  }
  const { handleIntake } = await import("./intake");
  const r = await handleIntake({ source: "call", phone, name: String(b.name ?? ""), message: String(b.message ?? ""), audioB64: audio?.b64, audioMime: audio?.mime });
  res.json({ ok: true, ...r });
});

/** App actions: admin checks, demo data, simulators, merge, assign, book, call-backs. */
export const api = onRequest({ cors: true, timeoutSeconds: 300, memory: "512MiB" }, async (req, res) => {
  const { handleApi } = await import("./api");
  await handleApi(req, res);
});

/** Every 5 minutes: reminders + follow-ups. */
export const heartbeat = onSchedule({ schedule: "every 5 minutes", timeZone: "Asia/Kolkata" }, async () => {
  const { demoNow } = await import("./db");
  const { runHeartbeat } = await import("./heartbeat");
  const r = await runHeartbeat(await demoNow());
  console.log("heartbeat", r);
});

/** Demo "Fast-forward" button writes config/demo → run the heartbeat instantly. */
export const onDemoClock = onDocumentWritten("config/demo", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!after || before?.runNowAt?.isEqual?.(after.runNowAt)) return;
  const { db, demoNow } = await import("./db");
  const { runHeartbeat } = await import("./heartbeat");
  const r = await runHeartbeat(await demoNow());
  await db.doc("config/demo").set({ lastRun: `${r.reminders} reminders, ${r.followups} follow-ups, ${r.calls} call tasks` }, { merge: true });
});

/**
 * Staff sign-in: the first account (or any email in ADMIN_EMAILS) becomes admin, everyone else
 * waits for approval. Listens to writes, so a person who signed in before this went live is
 * promoted on their next sign-in.
 */
export const onStaffWritten = onDocumentWritten("users/{uid}", async (event) => {
  const after = event.data?.after.data() as { email?: string; name?: string; role?: string } | undefined;
  if (!after) return;
  if (after.role && after.role !== "pending") return;
  const { onNewStaff } = await import("./staff");
  await onNewStaff(event.params.uid, after);
});
