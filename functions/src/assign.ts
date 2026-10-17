/**
 * Lead assignment by language.
 * Each counsellor lists the languages they counsel in (Admin → Team). A Marathi lead goes to a
 * Marathi-speaking counsellor, round-robin among them; if nobody speaks it, round-robin over
 * everyone approved. Hot leads raise an alert for the assigned counsellor.
 */
import { db, FieldValue, logEvent, type Lead } from "./db";
import { pickLang } from "./lang";

interface Staff {
  uid: string;
  name: string;
  role: string;
  languages: string[];
}

async function staff(): Promise<Staff[]> {
  const snap = await db.collection("users").where("role", "in", ["counsellor", "admin"]).limit(50).get();
  return snap.docs.map((d) => {
    const x = d.data();
    const langs = Array.isArray(x.languages) && x.languages.length ? (x.languages as string[]) : ["en"];
    return { uid: d.id, name: String(x.name || x.email || "Counsellor"), role: String(x.role), languages: langs.map((l) => l.toLowerCase()) };
  });
}

/** Assigns (or re-assigns when the language becomes known) and returns the counsellor name. */
export async function assignByLanguage(leadId: string, lead: Lead, language?: string): Promise<string | null> {
  const lang = pickLang(language ?? lead.language);
  if (lead.assignedUid && lead.assignedLang === lang) return lead.assignedTo ?? null;
  if (lead.assignedUid && lead.assignedManually) return lead.assignedTo ?? null;
  const all = await staff();
  if (!all.length) return null;
  // Counsellors first; admins only when no counsellor speaks the language.
  const speakers = all.filter((s) => s.languages.includes(lang));
  const counsellors = speakers.filter((s) => s.role === "counsellor");
  const pool = counsellors.length ? counsellors : speakers.length ? speakers : all;
  if (lead.assignedUid && pool.some((s) => s.uid === lead.assignedUid)) {
    await db.doc(`leads/${leadId}`).set({ assignedLang: lang }, { merge: true });
    return lead.assignedTo ?? null;
  }
  // Stateless spread: hash of the lead id picks the counsellor, so there is no shared counter
  // document to fight over when thousands of leads arrive at once.
  let h = 0;
  for (const ch of leadId) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  const pick = pool[h % pool.length];
  await db.doc(`leads/${leadId}`).set({ assignedUid: pick.uid, assignedTo: pick.name, assignedLang: lang, assignedAt: FieldValue.serverTimestamp() }, { merge: true });
  await logEvent("assigned", leadId, { to: pick.name, uid: pick.uid, language: lang, reason: speakers.length ? `speaks ${lang}` : "no counsellor for this language: round-robin" });
  return pick.name;
}

export async function hotLeadAlert(leadId: string, lead: Lead, score: number): Promise<void> {
  await db.collection("alerts").add({
    uid: lead.assignedUid ?? null,
    leadId,
    title: `🔥 Hot lead: ${lead.name || "New enquiry"} (${score})`,
    body: (lead.summary ?? []).slice(0, 2).join(" · "),
    read: false,
    at: FieldValue.serverTimestamp(),
  });
  await logEvent("hot_lead", leadId, { score, to: lead.assignedTo ?? "" });
}
