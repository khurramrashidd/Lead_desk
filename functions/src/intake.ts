/**
 * One front door for every channel that is not a live chat.
 *
 * Google Forms, an IVR/telephony provider, Zapier, a landing page, or a
 * counsellor logging a phone call all post the same small JSON here. The lead
 * is created (or matched to an existing one), and Asha answers it exactly as if
 * it had arrived on WhatsApp.
 */
import { db, FieldValue, type Channel, type Lead, type LeadContact } from "./db";
import { normalizePhone } from "./identity";
import { latinName, resolveIdentity } from "./merge";

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
  /** Any extra Google Form answers — kept on the lead so nothing is lost. */
  extra?: Record<string, unknown>;
  /** true = record it without asking Asha to reply (for logging a finished phone call). */
  silent?: boolean;
}

const ALLOWED: Channel[] = ["web", "whatsapp", "telegram", "form", "googleform", "walkin", "call", "instagram"];

function asChannel(source?: string): Channel {
  const s = (source ?? "").toLowerCase().trim();
  if (ALLOWED.includes(s as Channel)) return s as Channel;
  if (s.includes("google")) return "googleform";
  if (s.includes("insta")) return "instagram";
  if (s.includes("telegram")) return "telegram";
  if (s.includes("whats")) return "whatsapp";
  if (s.includes("call") || s.includes("phone") || s.includes("ivr")) return "call";
  if (s.includes("walk") || s.includes("counter") || s.includes("office")) return "walkin";
  if (s.includes("form")) return "form";
  return "web";
}

/** Finds an existing lead for this phone/email, else creates one. */
async function findOrCreateLead(p: IntakePayload, channel: Channel): Promise<string> {
  const phone = normalizePhone(p.phone);
  const studentPhone = normalizePhone(p.studentPhone) ?? (p.relation && p.relation !== "self" ? undefined : phone);

  if (phone) {
    for (const field of ["phone", "studentPhone"] as const) {
      const hit = await db.collection("leads").where(field, "==", phone).limit(5).get();
      const live = hit.docs.find((d) => !(d.data() as Lead).mergedInto);
      if (live) return live.id;
    }
    const byContact = await db.collection("leads").where("contactPhones", "array-contains", phone).limit(5).get();
    const liveContact = byContact.docs.find((d) => !(d.data() as Lead).mergedInto);
    if (liveContact) return liveContact.id;
  }

  const contact: LeadContact = {
    name: p.name ?? "",
    phone: phone ?? "",
    email: p.email ?? "",
    relation: p.relation ?? "self",
    channel,
    isPrimary: true,
  };

  const ref = db.collection("leads").doc();
  await ref.set({
    name: p.name ?? "",
    nameLatin: latinName(p.name) ?? "",
    phone: phone ?? "",
    email: p.email ?? "",
    city: p.city ?? "",
    studentName: p.studentName ?? (p.relation && p.relation !== "self" ? "" : p.name ?? ""),
    studentPhone: studentPhone ?? "",
    contacts: [contact],
    contactPhones: [phone, studentPhone].filter(Boolean),
    sources: [channel],
    firstSource: channel,
    lastChannel: channel,
    status: "new",
    score: 0,
    ...(p.course ? { courseInterest: p.course } : {}),
    ...(p.extra && Object.keys(p.extra).length ? { intakeExtra: p.extra } : {}),
    createdAt: FieldValue.serverTimestamp(),
    lastMessageAt: FieldValue.serverTimestamp(),
  });
  await resolveIdentity(ref.id);
  const after = (await ref.get()).data() as Lead;
  return after.mergedInto ?? ref.id;
}

/** Writes the enquiry and lets the normal message trigger do the rest. */
export async function handleIntake(p: IntakePayload): Promise<{ leadId: string; channel: Channel }> {
  const channel = asChannel(p.source);
  const leadId = await findOrCreateLead(p, channel);
  const leadRef = db.doc(`leads/${leadId}`);

  const lines = [
    p.name ? `${p.relation && p.relation !== 'self' ? `${p.relation} ` : ''}${p.name}` : null,
    p.course ? `Interested in: ${p.course}` : null,
    p.studentName ? `Student: ${p.studentName}` : null,
    p.message?.trim() ? p.message.trim() : null,
    ...Object.entries(p.extra ?? {}).map(([k, v]) => `${k}: ${v}`),
  ].filter(Boolean);

  await leadRef.set(
    {
      lastChannel: channel,
      sources: FieldValue.arrayUnion(channel),
      lastInboundAt: FieldValue.serverTimestamp(),
      lastMessageAt: FieldValue.serverTimestamp(),
      ...(p.city ? { city: p.city } : {}),
    },
    { merge: true },
  );

  await leadRef.collection("messages").add({
    role: p.silent ? "system" : "user",
    channel,
    text: `[${channel} enquiry] ${lines.join(' · ')}`,
    createdAt: FieldValue.serverTimestamp(),
    meta: { intake: true, source: p.source ?? channel },
  });

  return { leadId, channel };
}
