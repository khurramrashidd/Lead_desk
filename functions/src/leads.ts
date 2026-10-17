/** Finds the lead for an inbound enquiry on any channel, or creates one, then resolves identity. */
import { db, FieldValue, type Channel, type Lead, type LeadContact } from "./db";
import { normalizePhone } from "./identity";
import { latinName, resolveIdentity } from "./merge";

export interface InboundPerson {
  channel: Channel;
  name?: string;
  phone?: string;
  email?: string;
  city?: string;
  waId?: string;
  telegramId?: string;
  telegramUsername?: string;
  igId?: string;
  relation?: string; // who is writing: self | parent | sibling | friend …
  studentName?: string;
  studentPhone?: string;
  extra?: Record<string, unknown>;
  simulated?: boolean;
}

async function firstLive(field: string, value: string, op: "==" | "array-contains" = "=="): Promise<string | null> {
  const snap = await db.collection("leads").where(field, op, value).limit(5).get();
  const live = snap.docs.find((d) => !(d.data() as Lead).mergedInto);
  return live ? live.id : null;
}

/** Returns the id of the live lead for this person (after any merge). */
export async function findOrCreateLead(p: InboundPerson): Promise<string> {
  // 1. Same channel identity → same lead.
  if (p.waId) {
    const hit = await firstLive("waId", p.waId);
    if (hit) return hit;
  }
  if (p.telegramId) {
    const hit = await firstLive("telegramId", p.telegramId);
    if (hit) return hit;
  }
  if (p.igId) {
    const hit = await firstLive("igId", p.igId);
    if (hit) return hit;
  }

  const phone = normalizePhone(p.phone);
  const relation = (p.relation ?? "self").toLowerCase();
  const studentPhone = normalizePhone(p.studentPhone) ?? (relation === "self" ? phone : undefined);

  const contact: LeadContact = {
    name: p.name ?? "",
    phone: phone ?? "",
    email: p.email ?? "",
    relation,
    channel: p.channel,
    isPrimary: true,
  };

  const ref = db.collection("leads").doc();
  await ref.set({
    name: p.name ?? "",
    nameLatin: latinName(p.name) ?? "",
    phone: phone ?? "",
    email: (p.email ?? "").trim().toLowerCase(),
    city: p.city ?? "",
    studentName: p.studentName ?? (relation === "self" ? p.name ?? "" : ""),
    studentPhone: studentPhone ?? "",
    contacts: [contact],
    contactPhones: [phone, studentPhone].filter((x): x is string => !!x),
    ...(p.waId ? { waId: p.waId } : {}),
    ...(p.telegramId ? { telegramId: p.telegramId, telegramUsername: p.telegramUsername ?? "" } : {}),
    ...(p.igId ? { igId: p.igId } : {}),
    ...(p.extra && Object.keys(p.extra).length ? { intakeExtra: p.extra } : {}),
    ...(p.simulated ? { simulated: true } : {}),
    sources: [p.channel],
    firstSource: p.channel,
    lastChannel: p.channel,
    status: "new",
    score: 0,
    userMessages: 0,
    createdBy: "server",
    createdAt: FieldValue.serverTimestamp(),
    lastMessageAt: FieldValue.serverTimestamp(),
  });
  await resolveIdentity(ref.id);
  const after = (await ref.get()).data() as Lead;
  return after.mergedInto ?? ref.id;
}

/** Records an inbound message on the lead; the message trigger makes Asha answer it. */
export async function addInbound(
  leadId: string,
  channel: Channel,
  msg: { id?: string; text?: string; audioB64?: string; audioMime?: string; imageB64?: string; imageMime?: string; meta?: Record<string, unknown>; silent?: boolean },
  identity: Partial<Pick<Lead, "waId" | "telegramId" | "igId">> = {},
): Promise<string> {
  const leadRef = db.doc(`leads/${leadId}`);
  await leadRef.set(
    {
      ...identity,
      lastChannel: channel,
      sources: FieldValue.arrayUnion(channel),
      lastInboundAt: FieldValue.serverTimestamp(),
      lastMessageAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  const data: Record<string, unknown> = {
    role: msg.silent ? "system" : "user",
    channel,
    createdAt: FieldValue.serverTimestamp(),
    meta: msg.meta ?? {},
  };
  if (msg.text) data.text = msg.text;
  if (msg.audioB64) {
    data.audioB64 = msg.audioB64;
    data.audioMime = msg.audioMime ?? "audio/ogg";
  }
  if (msg.imageB64) {
    data.imageB64 = msg.imageB64;
    data.imageMime = msg.imageMime ?? "image/jpeg";
  }
  const col = leadRef.collection("messages");
  // Idempotent when the provider gives us a message id (webhooks are retried).
  if (msg.id) {
    await col.doc(msg.id).create(data).catch(() => undefined);
    return msg.id;
  }
  return (await col.add(data)).id;
}
