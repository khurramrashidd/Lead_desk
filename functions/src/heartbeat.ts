/**
 * Runs every 5 minutes on Google's servers (and instantly when the demo
 * "Fast-forward" button moves the clock). Sends demo reminders and fires
 * next-best-action follow-ups so no lead is ever forgotten.
 */
import { db, FieldValue, Timestamp, logEvent, type Lead } from "./db";
import { formatIst, t } from "./lang";
import { sendWhatsAppText } from "./whatsapp";

const HOUR = 3_600_000;

async function deliver(leadId: string, lead: Lead, text: string, kind: string, now: Date): Promise<void> {
  const channel = lead.waId ? "whatsapp" : lead.lastChannel ?? "web";
  let delivered = channel !== "whatsapp";
  let note = "";
  if (channel === "whatsapp" && lead.waId) {
    const lastIn = lead.lastInboundAt?.toDate();
    const windowOpen = !!lastIn && now.getTime() - lastIn.getTime() < 24 * HOUR;
    if (windowOpen) delivered = await sendWhatsAppText(lead.waId, text);
    else note = "WhatsApp 24h window closed: send an approved template or call";
  }
  await db.collection(`leads/${leadId}/messages`).add({
    role: "ai",
    channel,
    text,
    createdAt: FieldValue.serverTimestamp(),
    meta: { kind, automatic: true, delivered, note, simulatedAt: Timestamp.fromDate(now) },
  });
  await db.doc(`leads/${leadId}`).set(
    { lastMessageAt: FieldValue.serverTimestamp(), ...(note ? { needsHuman: true, handoffReason: note } : {}) },
    { merge: true },
  );
}

export async function runHeartbeat(now: Date): Promise<{ reminders: number; followups: number }> {
  let reminders = 0;
  let followups = 0;

  // ---- Demo-class reminders: 24 hours and 1 hour before ----
  const soon = await db
    .collection("leads")
    .where("booking.startAt", ">", Timestamp.fromDate(now))
    .where("booking.startAt", "<=", Timestamp.fromDate(new Date(now.getTime() + 24 * HOUR)))
    .limit(100)
    .get();
  for (const d of soon.docs) {
    const lead = d.data() as Lead;
    const b = lead.booking;
    if (!b || lead.mergedInto) continue;
    const msLeft = b.startAt.toMillis() - now.getTime();
    const vars = { title: b.title, when: formatIst(b.startAt.toDate()) };
    if (msLeft <= HOUR && !b.reminded1) {
      await deliver(d.id, lead, t("remind1", lead.language, vars), "reminder_1h", now);
      await d.ref.set({ booking: { reminded1: true, reminded24: true } }, { merge: true });
      await logEvent("reminder", d.id, { kind: "1h", title: b.title });
      reminders++;
    } else if (msLeft > HOUR && !b.reminded24) {
      await deliver(d.id, lead, t("remind24", lead.language, vars), "reminder_24h", now);
      await d.ref.set({ booking: { reminded24: true } }, { merge: true });
      await logEvent("reminder", d.id, { kind: "24h", title: b.title });
      reminders++;
    }
  }

  // ---- Next-best-action follow-ups that are due ----
  const due = await db.collection("leads").where("nextAction.at", "<=", Timestamp.fromDate(now)).limit(100).get();
  for (const d of due.docs) {
    const lead = d.data() as Lead;
    const na = lead.nextAction;
    if (!na || na.done || lead.mergedInto || lead.aiPaused) continue;
    if (lead.status === "admitted" || lead.status === "lost") continue;
    if (na.channel === "call") {
      await d.ref.set({ needsHuman: true, handoffReason: `Call now: ${na.reason}`, nextAction: { done: true } }, { merge: true });
      await logEvent("followup", d.id, { channel: "call", reason: na.reason });
    } else if (na.message) {
      await deliver(d.id, lead, na.message, "followup", now);
      await d.ref.set({ nextAction: { done: true }, followupsSent: FieldValue.increment(1) }, { merge: true });
      await logEvent("followup", d.id, { channel: na.channel, reason: na.reason, message: na.message });
    }
    followups++;
  }
  return { reminders, followups };
}
