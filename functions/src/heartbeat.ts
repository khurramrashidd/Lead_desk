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

type Which = "24h" | "1h";

/** "today" or "tomorrow" in IST, in the lead's language. */
function dayWord(start: Date, now: Date, language?: string): string {
  const ist = (d: Date) => new Date(d.getTime() + 330 * 60_000).toISOString().slice(0, 10);
  return t(ist(start) === ist(now) ? "today" : "tomorrow", language);
}

/** One reminder for a demo class ("booking") or a counsellor call / video meeting ("callback"). */
export async function sendReminder(leadId: string, lead: Lead, what: "booking" | "callback", which: Which, now: Date): Promise<boolean> {
  const ref = db.doc(`leads/${leadId}`);
  if (what === "booking") {
    const b = lead.booking;
    if (!b) return false;
    const vars = { title: b.title, when: formatIst(b.startAt.toDate()), day: dayWord(b.startAt.toDate(), now, lead.language) };
    await deliver(leadId, lead, t(which === "1h" ? "remind1" : "remind24", lead.language, vars), which === "1h" ? "reminder_1h" : "reminder_24h", now);
    await ref.set({ booking: which === "1h" ? { reminded1: true, reminded24: true } : { reminded24: true } }, { merge: true });
    await logEvent("reminder", leadId, { kind: which, title: b.title });
    return true;
  }
  const c = (lead as Lead & { callback?: CallbackBooking }).callback;
  if (!c?.startAt) return false;
  const vars = { kind: t(c.kind === "meet" ? "meetKind" : "callKind", lead.language), when: formatIst(c.startAt.toDate()), day: dayWord(c.startAt.toDate(), now, lead.language) };
  await deliver(leadId, lead, t(which === "1h" ? "remindCall1" : "remindCall24", lead.language, vars), which === "1h" ? "call_reminder_1h" : "call_reminder_24h", now);
  await ref.set({ callback: which === "1h" ? { reminded1: true, reminded24: true } : { reminded24: true } }, { merge: true });
  await logEvent("reminder", leadId, { kind: `call ${which}`, title: c.title ?? "call" });
  return true;
}

interface CallbackBooking {
  kind?: string;
  title?: string;
  startAt?: Timestamp;
  reminded24?: boolean;
  reminded1?: boolean;
}

/**
 * Desk → "Test reminders now": sends the 24-hour and the 1-hour reminder for this lead's demo
 * class and/or call straight away, so a booking can be checked without waiting a day.
 */
export async function remindNow(leadId: string): Promise<{ sent: string[] }> {
  const sent: string[] = [];
  const now = new Date();
  for (const what of ["booking", "callback"] as const) {
    for (const which of ["24h", "1h"] as const) {
      const lead = (await db.doc(`leads/${leadId}`).get()).data() as Lead | undefined;
      if (lead && (await sendReminder(leadId, lead, what, which, now))) sent.push(`${what === "booking" ? "demo" : "call"} ${which}`);
    }
  }
  return { sent };
}

/**
 * [only]: limit the run to these leads (the self-test uses it to fast-forward ONE lead's clock
 * without touching anybody else).
 */
export async function runHeartbeat(now: Date, only?: Set<string>): Promise<{ reminders: number; followups: number; calls: number }> {
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
    if (only && !only.has(d.id)) continue;
    const lead = d.data() as Lead;
    const b = lead.booking;
    if (!b || lead.mergedInto) continue;
    const msLeft = b.startAt.toMillis() - now.getTime();
    if (msLeft <= HOUR && !b.reminded1) {
      if (await sendReminder(d.id, lead, "booking", "1h", now)) reminders++;
    } else if (msLeft > HOUR && !b.reminded24) {
      if (await sendReminder(d.id, lead, "booking", "24h", now)) reminders++;
    }
  }

  // ---- Counsellor call / video-meeting reminders ("Talk to a human"): same rule ----
  const calls24 = await db
    .collection("leads")
    .where("callback.startAt", ">", Timestamp.fromDate(now))
    .where("callback.startAt", "<=", Timestamp.fromDate(new Date(now.getTime() + 24 * HOUR)))
    .limit(100)
    .get();
  for (const d of calls24.docs) {
    if (only && !only.has(d.id)) continue;
    const lead = d.data() as Lead & { callback?: CallbackBooking };
    const c = lead.callback;
    if (!c?.startAt || lead.mergedInto) continue;
    const msLeft = c.startAt.toMillis() - now.getTime();
    if (msLeft <= HOUR && !c.reminded1) {
      if (await sendReminder(d.id, lead, "callback", "1h", now)) reminders++;
    } else if (msLeft > HOUR && !c.reminded24) {
      if (await sendReminder(d.id, lead, "callback", "24h", now)) reminders++;
    }
  }

  // ---- Next-best-action follow-ups that are due ----
  const due = await db.collection("leads").where("nextAction.at", "<=", Timestamp.fromDate(now)).limit(100).get();
  for (const d of due.docs) {
    if (only && !only.has(d.id)) continue;
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
  // ---- Housekeeping: drop cached answers older than a day ----
  if (only) return { reminders, followups, calls };
  // ---- Keep a week of demo / call slots open (no "create slots" button needed) ----
  try {
    const far = await db.collection("slots").where("startAt", ">", Timestamp.fromDate(new Date(now.getTime() + 5 * 24 * HOUR))).limit(1).get();
    if (far.empty) {
      const { seedSlots } = await import("./seed");
      await seedSlots(now);
    }
  } catch (e) {
    console.warn("slot top-up failed", e);
  }
  try {
    const old = await db.collection("aiCache").where("at", "<", Timestamp.fromMillis(Date.now() - 24 * HOUR)).limit(300).get();
    if (!old.empty) {
      const batch = db.batch();
      old.docs.forEach((x) => batch.delete(x.ref));
      await batch.commit();
    }
  } catch (e) {
    console.warn("cache cleanup failed", e);
  }
  return { reminders, followups, calls };
}
