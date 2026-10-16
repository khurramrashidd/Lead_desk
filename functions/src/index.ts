/**
 * Cloud Functions entry point.
 *
 * Deploying from a slow laptop: the Firebase CLI loads this file to discover the functions
 * and gives up after 10 seconds by default. So this file only imports `firebase-functions`,
 * and our own code (Gemini SDK, brain, merge...) is loaded INSIDE the handlers with
 * `await import(...)`. Use deploy.bat in the project root: it also raises that limit.
 */
import { setGlobalOptions } from "firebase-functions/v2/options";
import { onDocumentCreated, onDocumentWritten } from "firebase-functions/v2/firestore";
import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import type { Lead, Message } from "./db";

// Mumbai — same region as the Firestore database.
setGlobalOptions({ region: "asia-south1", maxInstances: 10 });

/** Every new message: prospect -> AI counsellor reply; counsellor on WhatsApp -> forward. */
export const onMessageCreated = onDocumentCreated(
  { document: "leads/{leadId}/messages/{msgId}", timeoutSeconds: 120, memory: "512MiB" },
  async (event) => {
    const msg = event.data?.data() as (Message & { mergedFrom?: string }) | undefined;
    if (!msg || msg.mergedFrom) return; // copied during a merge, already handled
    const { leadId, msgId } = event.params;
    const { db } = await import("./db");
    const { sendWhatsAppText } = await import("./whatsapp");

    if (msg.role === "counsellor" && msg.channel === "whatsapp") {
      const lead = (await db.doc(`leads/${leadId}`).get()).data() as Lead | undefined;
      if (lead?.waId && msg.text) await sendWhatsAppText(lead.waId, msg.text);
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
    if (result && result.channel === "whatsapp") {
      const lead = (await db.doc(`leads/${target}`).get()).data() as Lead | undefined;
      if (lead?.waId) await sendWhatsAppText(lead.waId, result.reply);
    }
  },
);

/** New lead from a form, walk-in or web chat: check if we already know this person. */
export const onLeadCreated = onDocumentCreated("leads/{leadId}", async (event) => {
  const lead = event.data?.data() as Lead | undefined;
  if (!lead || lead.firstSource === "whatsapp") return; // WhatsApp intake resolves itself
  if (!lead.phone && !lead.email) return;
  const { resolveIdentity } = await import("./merge");
  await resolveIdentity(event.params.leadId);
});

/** Name or phone added later (e.g. typed into the web chat). */
export const onLeadIdentityChanged = onDocumentWritten("leads/{leadId}", async (event) => {
  const before = event.data?.before.data() as Lead | undefined;
  const after = event.data?.after.data() as Lead | undefined;
  if (!before || !after || after.mergedInto) return;
  const { normalizePhone } = await import("./identity");
  const changed =
    (normalizePhone(before.phone) ?? "") !== (normalizePhone(after.phone) ?? "") || (before.email ?? "") !== (after.email ?? "");
  if (!changed || (!after.phone && !after.email)) return;
  const { resolveIdentity } = await import("./merge");
  await resolveIdentity(event.params.leadId);
});

/** Meta WhatsApp Cloud API webhook. */
export const whatsappWebhook = onRequest(async (req, res) => {
  if (req.method === "GET") {
    const ok = req.query["hub.mode"] === "subscribe" && req.query["hub.verify_token"] === process.env.WA_VERIFY_TOKEN;
    res.status(ok ? 200 : 403).send(ok ? String(req.query["hub.challenge"] ?? "") : "forbidden");
    return;
  }
  try {
    const { handleWebhook } = await import("./whatsapp");
    await handleWebhook(req.body);
  } catch (e) {
    console.error("webhook error", e);
  }
  res.sendStatus(200);
});

/** Every 5 minutes: reminders + follow-ups. */
export const heartbeat = onSchedule({ schedule: "every 5 minutes", timeZone: "Asia/Kolkata" }, async () => {
  const { demoNow } = await import("./db");
  const { runHeartbeat } = await import("./heartbeat");
  const r = await runHeartbeat(await demoNow());
  console.log("heartbeat", r);
});

/** Demo "Fast-forward" button writes config/demo -> run the heartbeat instantly. */
export const onDemoClock = onDocumentWritten("config/demo", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!after || before?.runNowAt?.isEqual?.(after.runNowAt)) return;
  const { db, demoNow } = await import("./db");
  const { runHeartbeat } = await import("./heartbeat");
  const r = await runHeartbeat(await demoNow());
  await db.doc("config/demo").set({ lastRun: r }, { merge: true });
});

/**
 * Staff sign-in: the first account (or any email in ADMIN_EMAILS) becomes admin,
 * everyone else waits for approval. Listens to writes, not just creates, so a person
 * who signed in before this trigger went live is promoted on their next sign-in.
 */
export const onStaffWritten = onDocumentWritten("users/{uid}", async (event) => {
  const after = event.data?.after.data() as { email?: string; name?: string; role?: string } | undefined;
  if (!after) return; // deleted
  if (after.role && after.role !== "pending") return; // nothing to decide
  const { onNewStaff } = await import("./staff");
  await onNewStaff(event.params.uid, after);
});
