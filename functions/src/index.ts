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
setGlobalOptions({ region: "asia-south1", maxInstances: Number(process.env.MAX_INSTANCES || 100) });

// ------------------------------------------------------------------ scaling
// Every function is a Cloud Run service: it adds instances as traffic grows (up to
// MAX_INSTANCES) and each instance serves many requests at once (concurrency), because the work
// is mostly waiting on the AI and the database. Raise MAX_INSTANCES in functions/.env for real
// traffic; the AI provider quota, not the servers, is the true ceiling, which is why answers
// are cached, bursts are coalesced and failures retry with back-off.
const MAX_INSTANCES = Number(process.env.MAX_INSTANCES || 100);

// Firestore triggers must live in the database's region. If Admin → Channels → Diagnose says
// the database is elsewhere (e.g. nam5), set TRIGGER_REGION in functions/.env (nam5 → us-central1,
// eur3 → europe-west1, otherwise the database region itself) and deploy again.
const TRIGGER_REGION = (process.env.TRIGGER_REGION || "asia-south1").trim();

/**
 * Every new message: prospect → Asha replies; counsellor → delivered on the lead's channel.
 * The webhooks, the app and the 2-minute sweeper do the same thing (see dispatch.ts), so Asha
 * still answers if this trigger is missing or late. Running twice is safe.
 */
export const onMessageCreated = onDocumentCreated(
  { document: "leads/{leadId}/messages/{msgId}", region: TRIGGER_REGION, timeoutSeconds: 300, memory: "512MiB", cpu: 1, concurrency: 40, maxInstances: MAX_INSTANCES },
  async (event) => {
    const msg = event.data?.data() as Message | undefined;
    if (!msg || msg.mergedFrom || msg.seed) return; // copied during a merge, or sample data
    if (msg.role !== "user" && msg.role !== "counsellor") return;
    const { dispatchMessage } = await import("./dispatch");
    await dispatchMessage(event.params.leadId, event.params.msgId, "trigger");
  },
);

/** New lead created by the app (web chat, website form, walk-in): who is it, who handles it? */
export const onLeadCreated = onDocumentCreated({ document: "leads/{leadId}", region: TRIGGER_REGION }, async (event) => {
  const lead = event.data?.data() as Lead | undefined;
  if (!lead || lead.seed || lead.createdBy === "server") return; // server-made leads resolve themselves
  const { resolveIdentity } = await import("./merge");
  const { assignByLanguage } = await import("./assign");
  if (lead.phone || lead.email) await resolveIdentity(event.params.leadId);
  const fresh = (await event.data!.ref.get()).data() as Lead | undefined;
  if (fresh && !fresh.mergedInto && !fresh.assignedUid) {
    await assignByLanguage(event.params.leadId, fresh, fresh.language).catch((e) => console.warn("assign failed", e));
  }
});

/**
 * Every 2 minutes: (1) AI providers were busy → retry those conversations with back-off
 * (2, 4, 8… min); (2) safety net → any prospect still waiting for a first answer gets one.
 */
export const aiRetry = onSchedule({ schedule: "every 2 minutes", timeZone: "Asia/Kolkata", timeoutSeconds: 300, memory: "512MiB" }, async () => {
  const { db, Timestamp, FieldValue } = await import("./db");
  const { respondAndDeliver } = await import("./brain");
  const due = await db.collection("leads").where("ai.retryAt", "<=", Timestamp.now()).limit(25).get();
  await Promise.all(
    due.docs.map(async (d) => {
      await d.ref.set({ ai: { retryAt: FieldValue.delete() } }, { merge: true });
      await respondAndDeliver(d.id).catch((e) => console.warn("retry failed", d.id, e));
    }),
  );
  if (due.size) console.log(`aiRetry: ${due.size} conversations retried`);
  const { sweepUnanswered } = await import("./dispatch");
  const swept = await sweepUnanswered().catch((e) => {
    console.warn("sweep failed", e);
    return 0;
  });
  if (swept) console.log(`aiRetry: answered ${swept} waiting conversations`);
});

/**
 * Meta webhook: WhatsApp Cloud API + Instagram DMs. The message is stored and answered in the
 * same request (no dependence on the Firestore trigger). Every call is noted in
 * config/webhookStatus, so Admin → Channels → Diagnose shows whether Meta is calling at all.
 */
export const metaWebhook = onRequest({ timeoutSeconds: 120, memory: "512MiB" }, async (req, res) => {
  const { channelConfig } = await import("./channels");
  const { noteWebhook, dispatchSafely } = await import("./dispatch");
  if (req.method === "GET") {
    const c = await channelConfig(true);
    const ok = req.query["hub.mode"] === "subscribe" && req.query["hub.verify_token"] === c.waVerifyToken;
    await noteWebhook("meta", { kind: "verify", ok, detail: ok ? "verification accepted" : "verify token did not match Admin → Channels" });
    res.status(ok ? 200 : 403).send(ok ? String(req.query["hub.challenge"] ?? "") : "forbidden");
    return;
  }
  const { handleMetaWebhook, describeMetaBody } = await import("./whatsapp");
  let stored: { leadId: string; msgId: string }[] = [];
  try {
    stored = await handleMetaWebhook(req.body);
    await noteWebhook("meta", { kind: "post", ok: true, detail: describeMetaBody(req.body), stored: stored.length });
  } catch (e) {
    console.error("meta webhook error", e);
    await noteWebhook("meta", { kind: "post", ok: false, detail: `${describeMetaBody(req.body)} → ERROR ${String((e as Error)?.message ?? e).slice(0, 200)}` });
  }
  for (const s of stored) await dispatchSafely(s.leadId, s.msgId, "metaWebhook");
  res.sendStatus(200);
});

/** Telegram bot webhook (set from Admin → Channels → Telegram → Connect). Stores and answers. */
export const telegramWebhook = onRequest({ timeoutSeconds: 120, memory: "512MiB" }, async (req, res) => {
  const { channelConfig } = await import("./channels");
  const { noteWebhook, dispatchSafely } = await import("./dispatch");
  const c = await channelConfig();
  if (req.get("x-telegram-bot-api-secret-token") !== c.telegramSecret) {
    await noteWebhook("telegram", { kind: "post", ok: false, detail: "secret token did not match: press Telegram → Connect again in Admin → Channels" });
    res.sendStatus(403);
    return;
  }
  let stored: { leadId: string; msgId: string } | null = null;
  try {
    const { handleTelegramUpdate } = await import("./telegram");
    stored = await handleTelegramUpdate(req.body);
    await noteWebhook("telegram", { kind: "post", ok: true, detail: stored ? `message stored on lead ${stored.leadId}` : "update without a message" });
  } catch (e) {
    console.error("telegram webhook error", e);
    await noteWebhook("telegram", { kind: "post", ok: false, detail: String((e as Error)?.message ?? e).slice(0, 300) });
  }
  if (stored) await dispatchSafely(stored.leadId, stored.msgId, "telegramWebhook");
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
    const { dispatchSafely } = await import("./dispatch");
    await dispatchSafely(r.leadId, r.msgId, "intakeWebhook");
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
  const { dispatchSafely } = await import("./dispatch");
  await dispatchSafely(r.leadId, r.msgId, "callWebhook");
  res.json({ ok: true, ...r });
});

/**
 * PS3 self-test: the app writes selftests/{scenario} with status "queued"; this runs that
 * scenario against the live system and writes checks + evidence back (Admin → Self-test).
 */
export const onSelfTest = onDocumentWritten({ document: "selftests/{id}", region: TRIGGER_REGION, timeoutSeconds: 540, memory: "512MiB" }, async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!after || after.status !== "queued" || before?.runToken === after.runToken) return;
  const { runScenario } = await import("./selftest");
  await runScenario(event.params.id);
});

/** App actions: admin checks, demo data, simulators, merge, assign, book, call-backs. */
export const api = onRequest({ cors: true, timeoutSeconds: 300, memory: "512MiB", cpu: 1, concurrency: 80 }, async (req, res) => {
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
export const onDemoClock = onDocumentWritten({ document: "config/demo", region: TRIGGER_REGION }, async (event) => {
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
export const onStaffWritten = onDocumentWritten({ document: "users/{uid}", region: TRIGGER_REGION }, async (event) => {
  const after = event.data?.after.data() as { email?: string; name?: string; role?: string } | undefined;
  if (!after) return;
  if (after.role && after.role !== "pending") return;
  const { onNewStaff } = await import("./staff");
  await onNewStaff(event.params.uid, after);
});
