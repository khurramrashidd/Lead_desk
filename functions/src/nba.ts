/**
 * Next-best-action engine.
 *
 * Rules decide WHEN and ON WHICH CHANNEL, from the lead's behaviour and objections.
 * The AI only writes WHAT to say (in the prospect's own language and register).
 *
 * Playbooks, highest priority first:
 *   closed          admitted / lost → nothing
 *   human_callback  Asha asked for a human → counsellor calls within 15 min (working hours)
 *   pause_call      3 automatic follow-ups unanswered → stop messaging, one human call
 *   post_demo       demo booked → check in 2 h after the class
 *   invite_parent   family approval → invite a parent to the demo (next day)
 *   fees_emi        fees → EMI / listed scholarships (next day)
 *   job_fear        job fear → placement process + a learner story (next day)
 *   flexible_batch  time → weekend / evening batch (next day)
 *   trust_demo      trust → free demo, meet the trainer (next day)
 *   hot_nudge       score ≥ 70 → 2 h      warm_nudge 40–69 → 24 h      cold_revive < 40 → 72 h
 * Every time is moved out of quiet hours (9 PM–9 AM IST).
 */
import { Timestamp, type Lead, type NextAction } from "./db";
import { respectQuietHours } from "./lang";

const HOUR = 3_600_000;

export interface NbaInput {
  lead: Lead;
  now: Date;
  aiMessage: string;
  aiReasonHint?: string;
  handoff?: boolean;
  handoffReason?: string;
}

/** The channel this person can actually be reached on at [at]. */
export function reachableChannel(lead: Lead, at: Date): { channel: string; note: string } {
  const lastIn = lead.lastInboundAt?.toDate?.();
  const inWindow = !!lastIn && at.getTime() - lastIn.getTime() < 24 * HOUR;
  const last = lead.lastChannel;
  const waReal = !!lead.waId && !lead.waId.startsWith("sim:");
  if (last === "telegram" && lead.telegramId) return { channel: "telegram", note: "" };
  if (last === "instagram" && lead.igId) {
    if (inWindow) return { channel: "instagram", note: "" };
    return lead.phone ? { channel: "call", note: "Instagram 24 h window closed" } : { channel: "instagram", note: "Instagram 24 h window closed" };
  }
  if (lead.waId) {
    if (inWindow || !waReal) return { channel: "whatsapp", note: "" };
    return { channel: lead.phone ? "call" : "whatsapp", note: "WhatsApp 24 h window closed: call, or send an approved template" };
  }
  if (lead.telegramId) return { channel: "telegram", note: "" };
  return { channel: "web", note: lead.phone ? "web chat only; phone known for a call" : "" };
}

function play(objections: string[]): { playbook: string; hours: number; why: string } | null {
  const o = new Set(objections);
  if (o.has("family_approval")) return { playbook: "invite_parent", hours: 24, why: "raised family approval → invite a parent to the free demo" };
  if (o.has("fees")) return { playbook: "fees_emi", hours: 24, why: "worried about fees → explain EMI and listed scholarships" };
  if (o.has("job_fear")) return { playbook: "job_fear", hours: 24, why: "afraid of not getting a job → placement process and a learner story" };
  if (o.has("time")) return { playbook: "flexible_batch", hours: 24, why: "short on time → weekend or evening batch" };
  if (o.has("trust")) return { playbook: "trust_demo", hours: 24, why: "not sure about us yet → free demo, meet the trainer" };
  if (o.has("distance")) return { playbook: "online_option", hours: 24, why: "distance → live online batch" };
  return null;
}

export function decideNextAction(input: NbaInput): NextAction | null {
  const { lead, now, aiMessage } = input;
  if (lead.status === "admitted" || lead.status === "lost") return null;

  let playbook: string;
  let at: Date;
  let reason: string;
  let forceCall = false;

  const unanswered = lead.unansweredFollowups ?? 0;
  if (input.handoff) {
    playbook = "human_callback";
    at = new Date(now.getTime() + 0.25 * HOUR);
    reason = `Asha asked for a human: ${input.handoffReason || "question outside the knowledge base"}`;
    forceCall = !!lead.phone;
  } else if (unanswered >= 3) {
    playbook = "pause_call";
    at = new Date(now.getTime() + 24 * HOUR);
    reason = `${unanswered} automatic follow-ups got no reply: stop messaging, one human call, then keep warm or close`;
    forceCall = true;
  } else if (lead.booking?.startAt) {
    const start = lead.booking.startAt.toDate();
    playbook = "post_demo";
    at = start.getTime() > now.getTime() ? new Date(start.getTime() + 3 * HOUR) : new Date(now.getTime() + 2 * HOUR);
    reason = "demo class booked: check in about 2 h after the class and offer admission help";
  } else {
    const p = play(lead.objections ?? []);
    const score = lead.score ?? 0;
    if (p) {
      playbook = p.playbook;
      at = new Date(now.getTime() + p.hours * HOUR);
      reason = `${lead.name || "Prospect"} ${p.why}`;
    } else if (score >= 70) {
      playbook = "hot_nudge";
      at = new Date(now.getTime() + 2 * HOUR);
      reason = `hot lead (score ${score}): nudge towards booking a demo while interest is high`;
    } else if (score >= 40) {
      playbook = "warm_nudge";
      at = new Date(now.getTime() + 24 * HOUR);
      reason = `warm lead (score ${score}): follow up tomorrow with the next step`;
    } else {
      playbook = "cold_revive";
      at = new Date(now.getTime() + 72 * HOUR);
      reason = `cold lead (score ${score}): one gentle check-in in 3 days`;
    }
  }

  at = respectQuietHours(at);
  // Prefer to follow up INSIDE WhatsApp's free 24 h window rather than lose the channel.
  const lastIn = lead.lastInboundAt?.toDate?.();
  if (!forceCall && !input.handoff && lead.waId && !lead.waId.startsWith("sim:") && lastIn) {
    const windowEnd = lastIn.getTime() + 24 * HOUR;
    if (at.getTime() > windowEnd) {
      const pulled = respectQuietHours(new Date(windowEnd - HOUR));
      if (pulled.getTime() < windowEnd && pulled.getTime() > now.getTime() + 0.5 * HOUR) {
        at = pulled;
        reason += " (moved earlier to stay inside WhatsApp's free 24 h window)";
      }
    }
  }
  const reach = reachableChannel(lead, at);
  const channel = forceCall && lead.phone ? "call" : reach.channel;
  if (reach.note && channel !== "call") reason += ` (${reach.note})`;
  if (channel === "call" && reach.note) reason += ` (${reach.note})`;
  if (input.aiReasonHint && !input.handoff) reason += `. AI note: ${input.aiReasonHint}`;

  return {
    at: Timestamp.fromDate(at),
    channel,
    message: aiMessage || "",
    reason,
    playbook,
    done: false,
  };
}
