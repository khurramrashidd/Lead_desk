/** Finds the same person across channels and merges them into one timeline. */
import { db, FieldValue, logEvent, type Lead } from "./db";
import { decideMatch, hasDevanagari, nameSimilarity, normalizePhone, transliterate } from "./identity";

function titleCase(s: string): string {
  return s.replace(/\b\w/g, (c) => c.toUpperCase());
}

/** Readable Latin form of a name, e.g. "राहुल पाटील" -> "Rahul Patil". */
export function latinName(name?: string): string | undefined {
  if (!name) return undefined;
  if (!hasDevanagari(name)) return name;
  return titleCase(transliterate(name).replace(/aa/g, "a").replace(/ii/g, "i").replace(/uu/g, "u"));
}

/** Moves everything from `dupId` into `keepId`. */
export async function mergeLeads(keepId: string, dupId: string, reason: string, similarity: number): Promise<void> {
  if (keepId === dupId) return;
  const keepRef = db.doc(`leads/${keepId}`);
  const dupRef = db.doc(`leads/${dupId}`);
  const [keepSnap, dupSnap] = await Promise.all([keepRef.get(), dupRef.get()]);
  const keep = keepSnap.data() as Lead;
  const dup = dupSnap.data() as Lead;
  if (!keep || !dup || dup.mergedInto) return;

  const msgs = await dupRef.collection("messages").get();
  const batch = db.batch();
  for (const m of msgs.docs) batch.set(keepRef.collection("messages").doc(m.id), { ...m.data(), mergedFrom: dupId });

  const aliases = new Set([...(keep.aliases ?? []), ...(dup.aliases ?? [])]);
  if (dup.name && dup.name !== keep.name) aliases.add(dup.name);
  const sources = Array.from(new Set([...(keep.sources ?? []), ...(dup.sources ?? [])]));
  const objections = Array.from(new Set([...(keep.objections ?? []), ...(dup.objections ?? [])]));
  // The student's chat follows the merge, so they must be able to read the kept lead.
  const viewerUids = Array.from(new Set([...(keep.viewerUids ?? []), ...(dup.viewerUids ?? [])]));

  const patch: Record<string, unknown> = {
    aliases: Array.from(aliases),
    sources,
    objections,
    viewerUids,
    mergedFromIds: FieldValue.arrayUnion(dupId),
  };
  if (!keep.name && dup.name) patch.name = dup.name;
  if (!keep.phone && dup.phone) patch.phone = dup.phone;
  if (!keep.email && dup.email) patch.email = dup.email;
  if (!keep.waId && dup.waId) patch.waId = dup.waId;
  if (!keep.telegramId && dup.telegramId) patch.telegramId = dup.telegramId;
  if (!keep.igId && dup.igId) patch.igId = dup.igId;
  if (!keep.studentName && dup.studentName) patch.studentName = dup.studentName;
  if (!keep.assignedUid && dup.assignedUid) {
    patch.assignedUid = dup.assignedUid;
    patch.assignedTo = dup.assignedTo ?? "";
  }
  const contacts = [...(keep.contacts ?? [])];
  for (const c of dup.contacts ?? []) {
    const same = contacts.some((k) => (k.phone && k.phone === c.phone) || (k.name && k.name === c.name && k.relation === c.relation));
    if (!same) contacts.push({ ...c, isPrimary: false });
  }
  patch.contacts = contacts;
  patch.contactPhones = Array.from(new Set([...(keep.contactPhones ?? []), ...(dup.contactPhones ?? [])].filter(Boolean)));
  patch.userMessages = (keep.userMessages ?? 0) + (dup.userMessages ?? 0);
  if (dup.aptitude && (!keep.aptitude || keep.aptitude.status === "not_started")) patch.aptitude = dup.aptitude;
  if (dup.recommendation && !keep.recommendation) patch.recommendation = dup.recommendation;
  if (dup.profile) patch.profile = { ...(dup.profile ?? {}), ...(keep.profile ?? {}) };
  if (!keep.city && dup.city) patch.city = dup.city;
  if (!keep.booking && dup.booking) patch.booking = dup.booking;
  if ((dup.score ?? 0) > (keep.score ?? 0)) {
    patch.score = dup.score;
    patch.temperature = dup.temperature;
    patch.summary = dup.summary;
    patch.suggestedMessage = dup.suggestedMessage;
  }
  if (dup.lastChannel) patch.lastChannel = dup.lastChannel;
  batch.set(keepRef, patch, { merge: true });
  batch.set(dupRef, { mergedInto: keepId, possibleDuplicateOf: FieldValue.delete() }, { merge: true });
  batch.set(keepRef, { possibleDuplicateOf: FieldValue.delete(), possibleDuplicateReason: FieldValue.delete() }, { merge: true });
  await batch.commit();

  await logEvent("merge", keepId, {
    kept: { id: keepId, name: keep.name ?? "", phone: keep.phone ?? "", source: keep.firstSource ?? "" },
    merged: { id: dupId, name: dup.name ?? "", phone: dup.phone ?? "", source: dup.firstSource ?? "" },
    reason,
    similarity: Math.round(similarity * 100) / 100,
  });
}

/**
 * Looks for other leads that are the same person.
 * Same phone (any format) + similar name in any script -> merge.
 * Same phone, different name -> flag for review (maybe a parent's phone).
 */
export async function resolveIdentity(leadId: string): Promise<void> {
  const ref = db.doc(`leads/${leadId}`);
  const lead = (await ref.get()).data() as Lead | undefined;
  if (!lead || lead.mergedInto) return;

  const phone = normalizePhone(lead.phone);
  const patch: Record<string, unknown> = {};
  if (phone && phone !== lead.phone) patch.phone = phone;
  const latin = latinName(lead.name);
  if (latin && latin !== lead.nameLatin) patch.nameLatin = latin;
  if (Object.keys(patch).length) await ref.set(patch, { merge: true });

  const candidates = new Map<string, Lead>();
  if (phone) {
    const byPhone = await db.collection("leads").where("phone", "==", phone).limit(10).get();
    byPhone.docs.forEach((d) => candidates.set(d.id, d.data() as Lead));
  }
  if (phone) {
    for (const field of ["studentPhone", "contactPhones"] as const) {
      const q = field === "contactPhones"
        ? db.collection("leads").where(field, "array-contains", phone)
        : db.collection("leads").where(field, "==", phone);
      const snap = await q.limit(10).get();
      snap.docs.forEach((d) => candidates.set(d.id, d.data() as Lead));
    }
  }
  if (lead.email) {
    const byEmail = await db.collection("leads").where("email", "==", lead.email).limit(10).get();
    byEmail.docs.forEach((d) => candidates.set(d.id, d.data() as Lead));
  }
  candidates.delete(leadId);

  for (const [otherId, other] of candidates) {
    if (other.mergedInto || !!other.seed !== !!lead.seed) continue;
    let m = decideMatch({ ...lead, phone: phone ?? lead.phone }, other);
    const otherPhones = new Set([other.studentPhone, ...(other.contactPhones ?? [])].filter(Boolean) as string[]);
    if (m.decision === "none" && phone && otherPhones.has(phone)) {
      // Same number as the student or a parent/friend already on that admission.
      const names = [other.name, other.studentName, ...(other.contacts ?? []).map((c) => c.name)].filter(Boolean) as string[];
      const best = names.reduce((mx, n) => Math.max(mx, nameSimilarity(lead.name, n)), 0);
      m = !lead.name || best >= 0.8
        ? { decision: "merge", similarity: best, reason: "same phone as a contact on this admission" }
        : { decision: "review", similarity: best, reason: "same phone as a contact on another lead, different name" };
    }
    if (m.decision === "merge") {
      // keep the older lead so its history stays first
      const leadTime = lead.createdAt?.toMillis() ?? Date.now();
      const otherTime = other.createdAt?.toMillis() ?? Date.now();
      const [keep, dup] = otherTime <= leadTime ? [otherId, leadId] : [leadId, otherId];
      await mergeLeads(keep, dup, m.reason, m.similarity);
      return;
    }
    if (m.decision === "review") {
      await ref.set({ possibleDuplicateOf: otherId, possibleDuplicateReason: m.reason }, { merge: true });
      await logEvent("possible_duplicate", leadId, { otherId, reason: m.reason, similarity: m.similarity });
    }
  }
}
