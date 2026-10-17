/**
 * Identity resolution: "Rahul Patil" (form, 098765-43210) and
 * "राहुल पाटील" (WhatsApp, 919876543210) are the same person.
 *
 * 1. Normalise phones to the last 10 digits.
 * 2. Transliterate Devanagari names to Latin letters.
 * 3. Build a phonetic key with Indian spelling rules (aa/a, ee/i, w/v, sh/s, th/t …).
 * 4. Compare with Jaro-Winkler and decide: merge, review, or none.
 */

const INDEPENDENT_VOWELS: Record<string, string> = {
  "अ": "a", "आ": "aa", "इ": "i", "ई": "ii", "उ": "u", "ऊ": "uu", "ऋ": "ri",
  "ए": "e", "ऐ": "ai", "ओ": "o", "औ": "au", "ऑ": "o", "ऍ": "e",
};
const MATRAS: Record<string, string> = {
  "ा": "aa", "ि": "i", "ी": "ii", "ु": "u", "ू": "uu", "ृ": "ri",
  "े": "e", "ै": "ai", "ो": "o", "ौ": "au", "ॉ": "o", "ॅ": "e",
};
const CONSONANTS: Record<string, string> = {
  "क": "k", "ख": "kh", "ग": "g", "घ": "gh", "ङ": "n",
  "च": "ch", "छ": "chh", "ज": "j", "झ": "jh", "ञ": "n",
  "ट": "t", "ठ": "th", "ड": "d", "ढ": "dh", "ण": "n",
  "त": "t", "थ": "th", "द": "d", "ध": "dh", "न": "n",
  "प": "p", "फ": "ph", "ब": "b", "भ": "bh", "म": "m",
  "य": "y", "र": "r", "ल": "l", "ळ": "l", "व": "v",
  "श": "sh", "ष": "sh", "स": "s", "ह": "h",
};
const VIRAMA = "्";
const NUKTA = "़";
const SIGNS: Record<string, string> = { "ं": "n", "ँ": "n", "ः": "h" };
const DIGITS = "०१२३४५६७८९";

export function hasDevanagari(s: string): boolean {
  return /[ऀ-ॿ]/.test(s);
}

/** राहुल पाटील -> "raahul paatiil" (simple, good enough for matching). */
export function transliterate(input: string): string {
  const chars = [...input.normalize("NFC")];
  let out = "";
  let pendingSchwa = false; // inherent 'a' waiting to see what follows

  const flushSchwa = (wordEnds: boolean) => {
    if (pendingSchwa && !wordEnds) out += "a";
    pendingSchwa = false;
  };

  for (let i = 0; i < chars.length; i++) {
    const c = chars[i];
    if (c === NUKTA) continue;
    if (CONSONANTS[c] !== undefined) {
      flushSchwa(false);
      out += CONSONANTS[c];
      pendingSchwa = true;
    } else if (MATRAS[c] !== undefined) {
      pendingSchwa = false;
      out += MATRAS[c];
    } else if (c === VIRAMA) {
      pendingSchwa = false;
    } else if (INDEPENDENT_VOWELS[c] !== undefined) {
      flushSchwa(false);
      out += INDEPENDENT_VOWELS[c];
    } else if (SIGNS[c] !== undefined) {
      flushSchwa(false);
      out += SIGNS[c];
    } else if (DIGITS.includes(c)) {
      flushSchwa(true);
      out += String(DIGITS.indexOf(c));
    } else {
      // space, punctuation or Latin text: a word boundary drops the final schwa
      const boundary = !/[a-zA-Z]/.test(c);
      flushSchwa(boundary);
      out += c;
    }
  }
  flushSchwa(true);
  return out.toLowerCase();
}

/** Spelling-insensitive key for Indian names. */
export function phoneticKey(name: string): string {
  let s = hasDevanagari(name) ? transliterate(name) : name.toLowerCase();
  s = s.replace(/[^a-z\s]/g, " ");
  const tokens = s.split(/\s+/).filter(Boolean).map((w) => {
    let k = w;
    k = k.replace(/chh/g, "c").replace(/ch/g, "c");
    k = k.replace(/sh/g, "s").replace(/ph/g, "f");
    k = k.replace(/([kgtdbjp])h/g, "$1");
    k = k.replace(/w/g, "v").replace(/z/g, "j").replace(/q/g, "k").replace(/ck/g, "k").replace(/x/g, "ks");
    k = k.replace(/ee|ii/g, "i").replace(/oo|uu/g, "u").replace(/aa/g, "a");
    k = k.replace(/(.)\1+/g, "$1");
    if (k.length > 2) k = k.replace(/a$/, "");
    return k;
  });
  return tokens.join(" ");
}

export function jaroWinkler(a: string, b: string): number {
  if (a === b) return 1;
  if (!a.length || !b.length) return 0;
  const range = Math.max(0, Math.floor(Math.max(a.length, b.length) / 2) - 1);
  const aM = new Array<boolean>(a.length).fill(false);
  const bM = new Array<boolean>(b.length).fill(false);
  let matches = 0;
  for (let i = 0; i < a.length; i++) {
    const lo = Math.max(0, i - range);
    const hi = Math.min(i + range + 1, b.length);
    for (let j = lo; j < hi; j++) {
      if (bM[j] || a[i] !== b[j]) continue;
      aM[i] = bM[j] = true;
      matches++;
      break;
    }
  }
  if (!matches) return 0;
  let trans = 0;
  let k = 0;
  for (let i = 0; i < a.length; i++) {
    if (!aM[i]) continue;
    while (!bM[k]) k++;
    if (a[i] !== b[k]) trans++;
    k++;
  }
  const m = matches;
  const jaro = (m / a.length + m / b.length + (m - trans / 2) / m) / 3;
  let prefix = 0;
  while (prefix < 4 && a[prefix] === b[prefix]) prefix++;
  return jaro + prefix * 0.1 * (1 - jaro);
}

/** 0..1, tolerant of script, spelling and word order. */
export function nameSimilarity(a?: string, b?: string): number {
  if (!a || !b) return 0;
  const ka = phoneticKey(a);
  const kb = phoneticKey(b);
  if (!ka || !kb) return 0;
  const sorted = (k: string) => k.split(" ").sort().join(" ");
  const full = jaroWinkler(ka, kb);
  const unordered = jaroWinkler(sorted(ka), sorted(kb));
  // one side has only a first name: compare first tokens
  const ta = ka.split(" ");
  const tb = kb.split(" ");
  const firstOnly = ta.length === 1 || tb.length === 1 ? jaroWinkler(ta[0], tb[0]) * 0.95 : 0;
  return Math.max(full, unordered, firstOnly);
}

/**
 * Person-level similarity: the GIVEN name decides, the surname can only confirm.
 * nameSimilarity("Priya Patil", "Rahul Patil") is high because the strings look alike;
 * personSimilarity is low, because they are two siblings, not one person.
 * Handles any script, spelling variants, middle names and "Patil Rahul" word order.
 */
export function personSimilarity(a?: string, b?: string): number {
  if (!a || !b) return 0;
  const ta = phoneticKey(a).split(" ").filter(Boolean);
  const tb = phoneticKey(b).split(" ").filter(Boolean);
  if (!ta.length || !tb.length) return 0;
  if (ta.length === 1 || tb.length === 1) {
    const one = ta.length === 1 ? ta[0] : tb[0];
    const other = ta.length === 1 ? tb : ta;
    if (ta.length === 1 && tb.length === 1) return jaroWinkler(ta[0], tb[0]);
    return jaroWinkler(one, other[0]) * 0.95; // only a first name on one side
  }
  const aF = ta[0], aL = ta[ta.length - 1], bF = tb[0], bL = tb[tb.length - 1];
  const straight = Math.min(jaroWinkler(aF, bF), jaroWinkler(aL, bL));
  const swapped = Math.min(jaroWinkler(aF, bL), jaroWinkler(aL, bF));
  return Math.max(straight, swapped);
}

/** "+91 98765-43210", "098765 43210", "919876543210" -> "9876543210" */
export function normalizePhone(raw?: string): string | undefined {
  if (!raw) return undefined;
  const ascii = [...raw].map((c) => (DIGITS.includes(c) ? String(DIGITS.indexOf(c)) : c)).join("");
  let d = ascii.replace(/\D/g, "");
  if (d.length === 12 && d.startsWith("91")) d = d.slice(2);
  else if (d.length === 11 && d.startsWith("0")) d = d.slice(1);
  else if (d.length === 13 && d.startsWith("091")) d = d.slice(3);
  return d.length >= 10 ? d.slice(-10) : d || undefined;
}

export type MatchDecision = "merge" | "review" | "none";

export interface PersonLike {
  name?: string;
  phone?: string;
  email?: string;
  city?: string;
}

export function decideMatch(a: PersonLike, b: PersonLike): { decision: MatchDecision; similarity: number; reason: string } {
  const pa = normalizePhone(a.phone);
  const pb = normalizePhone(b.phone);
  const sim = personSimilarity(a.name, b.name);
  const phoneEq = !!pa && pa === pb;
  const emailEq = !!a.email && !!b.email && a.email.trim().toLowerCase() === b.email.trim().toLowerCase();

  if (phoneEq && (sim >= 0.85 || !a.name || !b.name)) {
    return { decision: "merge", similarity: sim, reason: "same phone number, matching name" };
  }
  if (phoneEq) {
    return { decision: "review", similarity: sim, reason: "same phone, different name (maybe a parent's phone)" };
  }
  if (emailEq) return { decision: "merge", similarity: sim, reason: "same email" };
  if (sim >= 0.93 && a.city && b.city && a.city.toLowerCase() === b.city.toLowerCase()) {
    return { decision: "review", similarity: sim, reason: "very similar name in the same city" };
  }
  return { decision: "none", similarity: sim, reason: "" };
}

// ---------------------------------------------------------------------------------------
// Admission-level matching: one STUDENT can be asked about by several people (themselves,
// a parent, a friend) from several accounts, and one PERSON (a parent, an agent) can ask
// about several students. We merge only on a hard key (phone / email) AND a compatible
// student; a shared phone with clearly different students becomes a LINK, never a merge;
// a name alone is only ever a suggestion for a counsellor.
// ---------------------------------------------------------------------------------------

export interface LeadIdentity {
  name?: string; // who is writing
  phone?: string;
  email?: string;
  relation?: string; // self | parent | friend | sibling | guardian | other
  studentName?: string;
  studentPhone?: string;
  contactPhones?: string[];
  city?: string;
}

export type LeadDecision = "merge" | "related" | "review" | "none";

function studentNameOf(x: LeadIdentity): string | undefined {
  if (x.studentName && x.studentName.trim()) return x.studentName;
  const rel = (x.relation ?? "self").toLowerCase();
  return rel === "self" || rel === "unknown" ? x.name : undefined;
}

function phonesOf(x: LeadIdentity): Set<string> {
  return new Set(
    [x.phone, x.studentPhone, ...(x.contactPhones ?? [])]
      .map((p) => normalizePhone(p))
      .filter((p): p is string => !!p && p.length === 10),
  );
}

export function decideLeadMatch(a: LeadIdentity, b: LeadIdentity): { decision: LeadDecision; similarity: number; reason: string } {
  const pa = phonesOf(a);
  const pb = phonesOf(b);
  const shared = [...pa].filter((p) => pb.has(p));
  const emailEq = !!a.email && !!b.email && a.email.trim().toLowerCase() === b.email.trim().toLowerCase();
  const sa = studentNameOf(a);
  const sb = studentNameOf(b);
  const studentSim = personSimilarity(sa, sb);
  const writerSim = personSimilarity(a.name, b.name);

  if (shared.length || emailEq) {
    const key = shared.length ? "same phone" : "same email";
    if (sa && sb) {
      if (studentSim >= 0.85) return { decision: "merge", similarity: studentSim, reason: `${key}, same student` };
      if (studentSim < 0.7) {
        return { decision: "related", similarity: studentSim, reason: `${key}, different students (family member or shared phone)` };
      }
      return { decision: "review", similarity: studentSim, reason: `${key}, similar but not identical student names` };
    }
    // Student unknown on at least one side: decide on who is writing.
    if (!a.name || !b.name || writerSim >= 0.85) {
      return { decision: "merge", similarity: writerSim, reason: `${key}, same person writing` };
    }
    if (writerSim < 0.7) return { decision: "review", similarity: writerSim, reason: `${key}, different names (maybe a parent's phone)` };
    return { decision: "review", similarity: writerSim, reason: `${key}, similar names` };
  }

  // No hard key: a matching student name is only a suggestion, never an automatic merge.
  if (sa && sb && studentSim >= 0.93) {
    const sameCity = !!a.city && !!b.city && a.city.trim().toLowerCase() === b.city.trim().toLowerCase();
    return { decision: "review", similarity: studentSim, reason: `same student name${sameCity ? " in the same city" : ""}, no shared phone yet` };
  }
  return { decision: "none", similarity: Math.max(studentSim, writerSim), reason: "" };
}
