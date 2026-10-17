/**
 * One place that acts on a new message, whoever noticed it first:
 *   - the Firestore trigger (onMessageCreated),
 *   - the Telegram / WhatsApp / Instagram webhooks, right after they store the message,
 *   - the app (api/dispatch) right after the web chat or a counsellor writes one,
 *   - the 2-minute sweeper (aiRetry), for anything all of the above missed.
 *
 * Asha therefore answers even when the Firestore trigger is not deployed or not firing
 * (Eventarc permissions, database region). Running it twice is safe:
 *   prospect message  → respond() holds a per-lead lock and remembers the last answered id;
 *   counsellor message → the message is claimed in a transaction before it is sent.
 */
import { db, FieldValue, Timestamp, type Lead, type Message } from "./db";

export interface DispatchResult {
  ok: boolean;
  kind: "reply" | "deliver" | "skip";
  replies?: number;
  note?: string;
}

export async function dispatchMessage(leadId: string, msgId: string, via: string): Promise<DispatchResult> {
  const msgRef = db.doc(`leads/${leadId}/messages/${msgId}`);
  const snap = await msgRef.get();
  const msg = snap.data() as (Message & { dispatchedAt?: unknown }) | undefined;
  if (!msg) return { ok: false, kind: "skip", note: "message not found" };
  if (msg.mergedFrom || msg.seed) return { ok: true, kind: "skip", note: "merge copy or sample data" };

  if (msg.role === "counsellor") {
    // Claim it first, so a human's reply is never sent twice.
    const claimed = await db.runTransaction(async (tx) => {
      const s = await tx.get(msgRef);
      if (!s.exists || s.get("dispatchedAt")) return false;
      tx.update(msgRef, { dispatchedAt: FieldValue.serverTimestamp(), dispatchedVia: via });
      return true;
    });
    if (!claimed) return { ok: true, kind: "skip", note: "already delivered" };
    const lead = (await db.doc(`leads/${leadId}`).get()).data() as Lead | undefined;
    if (!lead || !msg.text || !["whatsapp", "telegram", "instagram"].includes(msg.channel)) {
      return { ok: true, kind: "deliver", note: "shown in the web chat" };
    }
    const { deliverOn } = await import("./channels");
    const r = await deliverOn(msg.channel, lead, msg.text);
    if (!r.delivered) await msgRef.set({ meta: { delivered: false, note: r.note || "send failed" } }, { merge: true });
    return { ok: r.delivered, kind: "deliver", note: r.note };
  }
  if (msg.role !== "user") return { ok: true, kind: "skip", note: `role ${msg.role}` };

  // If this enquiry was just merged into an older lead (same person), answer there.
  let target = leadId;
  const current = (await db.doc(`leads/${leadId}`).get()).data() as Lead | undefined;
  if (current?.mergedInto) {
    target = current.mergedInto;
    const copy = db.doc(`leads/${target}/messages/${msgId}`);
    if (!(await copy.get()).exists) await copy.set({ ...msg, mergedFrom: leadId });
  }
  const { respondAndDeliver } = await import("./brain");
  const replies = await respondAndDeliver(target);
  return { ok: true, kind: "reply", replies };
}

/** Same as dispatchMessage, but never throws (webhooks must still answer 200). */
export async function dispatchSafely(leadId: string, msgId: string, via: string): Promise<DispatchResult> {
  try {
    return await dispatchMessage(leadId, msgId, via);
  } catch (e) {
    const note = String((e as Error)?.message ?? e).slice(0, 300);
    console.error(`dispatch ${leadId}/${msgId} via ${via} failed`, e);
    await db
      .doc("config/webhookStatus")
      .set({ lastDispatchError: { leadId, msgId, via, note, at: FieldValue.serverTimestamp() } }, { merge: true })
      .catch(() => undefined);
    return { ok: false, kind: "skip", note };
  }
}

/**
 * Safety net, run every 2 minutes: a prospect whose latest message has had no answer for a
 * while gets one now. Covers a missing trigger, a webhook that timed out, a closed browser.
 */
export async function sweepUnanswered(now = Date.now()): Promise<number> {
  const since = Timestamp.fromMillis(now - 6 * 3_600_000);
  const snap = await db.collection("leads").where("lastInboundAt", ">=", since).orderBy("lastInboundAt", "desc").limit(40).get();
  let fixed = 0;
  for (const d of snap.docs) {
    const lead = d.data() as Lead;
    if (lead.mergedInto || lead.aiPaused || lead.seed) continue;
    if (lead.ai?.busy && lead.ai.since && now - lead.ai.since.toMillis() < 150_000) continue;
    if (lead.ai?.retryAt) continue; // aiRetry owns this one
    const last = await d.ref.collection("messages").orderBy("createdAt", "desc").limit(1).get();
    const m = last.docs[0];
    if (!m) continue;
    const data = m.data() as Message;
    if (data.role !== "user" || lead.ai?.lastAnsweredId === m.id) continue;
    const at = data.createdAt?.toMillis?.() ?? now;
    if (now - at < 45_000) continue; // give the live paths a chance first
    const r = await dispatchSafely(d.id, m.id, "sweeper");
    if (r.ok) fixed++;
  }
  return fixed;
}

/** Remembers the latest webhook calls, so Admin → Channels → Diagnose can show them. */
export async function noteWebhook(source: "meta" | "telegram", data: Record<string, unknown>): Promise<void> {
  try {
    await db.doc("config/webhookStatus").set({ [source]: { ...data, at: FieldValue.serverTimestamp() } }, { merge: true });
  } catch {
    // never break a webhook
  }
}
