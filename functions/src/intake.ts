/**
 * One front door for every channel that is not a live chat, plus the demo simulators.
 *
 * Google Forms (Apps Script), an IVR/telephony provider, Zapier, a landing page, or a
 * counsellor logging a call all POST the same small JSON to intakeWebhook. The lead is created
 * or matched to an existing person, and Asha answers it as if it had arrived on WhatsApp.
 */
import { asChannel, db, type Channel, type Lead } from "./db";
import { normalizePhone } from "./identity";
import { addInbound, findOrCreateLead } from "./leads";

export interface IntakePayload {
  source?: string;
  name?: string;
  phone?: string;
  email?: string;
  city?: string;
  message?: string;
  course?: string;
  /** Who is sending this: self | parent | guardian | sibling | friend | other */
  relation?: string;
  studentName?: string;
  studentPhone?: string;
  /** Any extra form answers, kept on the lead so nothing is lost. */
  extra?: Record<string, unknown>;
  /** true = record it without asking Asha to reply (e.g. logging a finished call). */
  silent?: boolean;
  /** Voice for simulated calls / voice notes. */
  audioB64?: string;
  audioMime?: string;
}

export async function handleIntake(p: IntakePayload, opts: { simulated?: boolean } = {}): Promise<{ leadId: string; channel: Channel; msgId: string }> {
  const channel = asChannel(p.source);
  const phone = normalizePhone(p.phone);
  const sim = opts.simulated;
  const identity: Partial<Pick<Lead, "waId" | "telegramId" | "igId">> = {};
  if (sim && channel === "whatsapp" && phone) identity.waId = `sim:91${phone}`;
  if (sim && channel === "telegram") identity.telegramId = `sim:${phone ?? Date.now()}`;
  if (sim && channel === "instagram") identity.igId = `sim:${(p.name ?? "ig").replace(/\W+/g, "").toLowerCase() || Date.now()}`;

  const leadId = await findOrCreateLead({
    channel,
    name: p.name,
    phone: p.phone,
    email: p.email,
    city: p.city,
    relation: p.relation,
    studentName: p.studentName,
    studentPhone: p.studentPhone,
    extra: { ...(p.extra ?? {}), ...(p.course ? { course: p.course } : {}) },
    simulated: sim,
    ...identity,
  });
  if (p.city) await db.doc(`leads/${leadId}`).set({ city: p.city }, { merge: true });

  const isChat = channel === "whatsapp" || channel === "telegram" || channel === "instagram" || (channel === "web" && !!p.message);
  let text: string;
  if (isChat) {
    text = p.message?.trim() || (p.audioB64 ? "🎤 Voice note" : "Hi");
  } else {
    const who = p.relation && p.relation !== "self" ? `${p.relation} ` : "";
    const lines = [
      p.name ? `${who}${p.name}` : null,
      p.course ? `Interested in: ${p.course}` : null,
      p.studentName ? `Student: ${p.studentName}` : null,
      p.message?.trim() ? p.message.trim() : null,
      ...Object.entries(p.extra ?? {}).map(([k, v]) => `${k}: ${String(v)}`),
    ].filter(Boolean);
    const label = channel === "call" ? (p.audioB64 ? "Voicemail" : "Missed call") : channel === "googleform" ? "Google Form" : channel === "form" ? "Website form" : channel === "walkin" ? "Walk-in" : channel;
    text = `[${label}] ${lines.join(" · ") || "(no details)"}`;
  }
  const msgId = await addInbound(
    leadId,
    channel,
    { text, audioB64: p.audioB64, audioMime: p.audioMime, silent: p.silent, meta: { intake: !isChat, source: p.source ?? channel, ...(sim ? { simulated: true } : {}) } },
    identity,
  );
  return { leadId, channel, msgId };
}
