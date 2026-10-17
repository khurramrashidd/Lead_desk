/** Finds the same person across channels and merges them into one timeline. */
import { db, FieldValue, logEvent, type Lead } from "./db";
import { decideLeadMatch, hasDevanagari, normalizePhone, phoneticKey, transliterate, type LeadIdentity } from "./identity";
import { bumpStat } from "./stats";

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
  if (!keep.studentPhone && dup.studentPhone) patch.studentPhone = dup.studentPhone;
  if (dup.relatedLeads || keep.relatedLeads?.[dupId]) {
    const rel = { ...(dup.relatedLeads ?? {}), ...(keep.relatedLeads ?? {}) };
    delete rel[keepId];
    delete rel[dupId];
    patch.relatedLeads = rel;
  }
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
  const relatedPatch = patch.relatedLeads as Record<string, unknown> | undefined;
  delete patch.relatedLeads;
  batch.set(keepRef, patch, { merge: true });
  if (relatedPatch) batch.update(keepRef, { relatedLeads: relatedPatch });
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

  // Normalise what we store, so every later lookup is a cheap equality query.
  const phone = normalizePhone(lead.phone);
  const studentPhone = normalizePhone(lead.studentPhone);
  const allPhones = Array.from(
    new Set([phone, studentPhone, ...(lead.contactPhones ?? []).map((p) => normalizePhone(p))].filter((p): p is string => !!p && p.length === 10)),
  );
  const studentName = lead.studentName || ((lead.contacts?.[0]?.relation ?? "self") === "self" ? lead.name : undefined);
  const studentKey = studentName ? phoneticKey(studentName) : "";
  const patch: Record<string, unknown> = {};
  if (phone && phone !== lead.phone) patch.phone = phone;
  if (studentPhone && studentPhone !== lead.studentPhone) patch.studentPhone = studentPhone;
  if (allPhones.length && allPhones.some((p) => !(lead.contactPhones ?? []).includes(p))) patch.contactPhones = allPhones;
  const latin = latinName(lead.name);
  if (latin && latin !== lead.nameLatin) patch.nameLatin = latin;
  if (studentKey && studentKey !== lead.studentKey) patch.studentKey = studentKey;
  if (lead.email && lead.email !== lead.email.trim().toLowerCase()) patch.email = lead.email.trim().toLowerCase();
  if (Object.keys(patch).length) await ref.set(patch, { merge: true });

  // Candidates: anyone sharing ANY phone (writer, student or contact), the same email, or the
  // same student name (phonetic key, any script). Three indexed queries, no table scans.
  const candidates = new Map<string, Lead>();
  const add = (snap: FirebaseFirestore.QuerySnapshot) => snap.docs.forEach((d) => candidates.set(d.id, d.data() as Lead));
  if (allPhones.length) {
    add(await db.collection("leads").where("contactPhones", "array-contains-any", allPhones.slice(0, 30)).limit(20).get());
    if (phone) add(await db.collection("leads").where("phone", "==", phone).limit(10).get()); // older leads without contactPhones
  }
  if (lead.email) add(await db.collection("leads").where("email", "==", lead.email.trim().toLowerCase()).limit(10).get());
  if (studentKey && studentKey.length >= 5) add(await db.collection("leads").where("studentKey", "==", studentKey).limit(10).get());
  candidates.delete(leadId);

  const me: LeadIdentity = {
    name: lead.name,
    phone: phone ?? lead.phone,
    email: lead.email,
    relation: lead.contacts?.[0]?.relation,
    studentName: lead.studentName,
    studentPhone: studentPhone ?? lead.studentPhone,
    contactPhones: allPhones,
    city: lead.city,
  };
  const notDup = new Set((lead as Lead & { notDuplicateOf?: string[] }).notDuplicateOf ?? []);

  for (const [otherId, other] of candidates) {
    if (other.mergedInto || !!other.seed !== !!lead.seed) continue;
    const m = decideLeadMatch(me, {
      name: other.name,
      phone: other.phone,
      email: other.email,
      relation: other.contacts?.[0]?.relation,
      studentName: other.studentName,
      studentPhone: other.studentPhone,
      contactPhones: other.contactPhones,
      city: other.city,
    });
    if (m.decision === "merge" && !notDup.has(otherId)) {
      // keep the older lead so its history stays first
      const leadTime = lead.createdAt?.toMillis() ?? Date.now();
      const otherTime = other.createdAt?.toMillis() ?? Date.now();
      const [keep, dup] = otherTime <= leadTime ? [otherId, leadId] : [leadId, otherId];
      await mergeLeads(keep, dup, m.reason, m.similarity);
      await bumpStat("merges");
      return;
    }
    if (m.decision === "related") {
      // Same family / shared phone, different students: two admissions, linked both ways.
      const at = FieldValue.serverTimestamp();
      await ref.set({ relatedLeads: { [otherId]: { name: other.studentName || other.name || "", reason: m.reason, at } } }, { merge: true });
      await db.doc(`leads/${otherId}`).set({ relatedLeads: { [leadId]: { name: lead.studentName || lead.name || "", reason: m.reason, at } } }, { merge: true });
      await logEvent("related", leadId, { otherId, reason: m.reason });
      await bumpStat("linked");
      continue;
    }
    if (m.decision === "review" && !notDup.has(otherId)) {
      await ref.set({ possibleDuplicateOf: otherId, possibleDuplicateReason: m.reason }, { merge: true });
      await logEvent("possible_duplicate", leadId, { otherId, reason: m.reason, similarity: m.similarity });
    }
  }
}
