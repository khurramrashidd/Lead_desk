/**
 * Runs every 5 minutes on Google's servers (and instantly when the demo "Fast-forward" button
 * moves the clock). Sends demo reminders and fires next-best-action follow-ups, so no lead
 * depends on a counsellor remembering.
 */
import { db, FieldValue, Timestamp, logEvent, type Lead } from "./db";
import { deliverOn } from "./channels";
import { formatIst, t } from "./lang";
import { decideNextAction, reachableChannel } from "./nba";

const HOUR = 3_600_000;

async function deliver(leadId: string, lead: Lead, text: string, kind: string, now: Date, wanted?: string): Promise<boolean> {
  const reach = reachableChannel(lead, now);
  const channel = wanted && wanted !== "call" ? wanted : reach.channel === "call" ? lead.lastChannel ?? "web" : reach.channel;
  let delivered = false;
  let note = reach.note;
  if (reach.channel === "call") {
    note = reach.note || "needs a phone call";
  } else {
    const r = await deliverOn(channel, lead, text);
    delivered = r.delivered;
    note = r.note || note;
  }
  await db.collection(`leads/${leadId}/messages`).add({
    role: "ai",
    channel,
    text,
    createdAt: FieldValue.serverTimestamp(),
    meta: { kind, automatic: true, delivered, note, simulatedAt: Timestamp.fromDate(now) },
  });
  await db.doc(`leads/${leadId}`).set(
    { lastMessageAt: FieldValue.serverTimestamp(), ...(delivered ? {} : { needsHuman: true, handoffReason: `${kind}: ${note || "could not deliver automatically"}` }) },
    { merge: true },
  );
  return delivered;
}

export async function runHeartbeat(now: Date): Promise<{ reminders: number; followups: number; calls: number }> {
  let reminders = 0;
  let followups = 0;
  let calls = 0;

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
      await d.ref.set(
        { needsHuman: true, handoffReason: `📞 Call now — ${na.reason}`, nextAction: { done: true }, callTask: { at: na.at, reason: na.reason, script: na.message } },
        { merge: true },
      );
      await logEvent("followup", d.id, { channel: "call", playbook: na.playbook, reason: na.reason });
      calls++;
      continue;
    }
    const delivered = await deliver(d.id, lead, na.message || t("nudge", lead.language), "followup", now, na.channel);
    const unanswered = (lead.unansweredFollowups ?? 0) + 1;
    // Cadence: decide the step after this one with the same rules.
    const next = decideNextAction({
      lead: { ...lead, unansweredFollowups: unanswered, followupsSent: (lead.followupsSent ?? 0) + 1 },
      now,
      aiMessage: t("nudge", lead.language),
    });
    await d.ref.set(
      {
        nextAction: next ?? { done: true },
        followupsSent: FieldValue.increment(1),
        unansweredFollowups: unanswered,
        lastFollowup: { at: Timestamp.fromDate(now), playbook: na.playbook, channel: na.channel, delivered },
      },
      { merge: true },
    );
    await logEvent("followup", d.id, { channel: na.channel, playbook: na.playbook, reason: na.reason, message: na.message, delivered });
    followups++;
  }
  return { reminders, followups, calls };
}
