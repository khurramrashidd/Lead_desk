/**
 * The Guard: every AI reply is checked before it is sent.
 * Fees, EMIs, discounts, percentages and placement promises must come
 * from the institute's knowledge base. Anything invented is blocked.
 */
import type { KnowledgeBase } from "./db";

const DEV_DIGITS = "०१२३४५६७८९";
const NEGATION = /\b(no|not|don't|dont|doesn't|cannot|can't|never|won't|unable)\b|नहीं|नही|नाही|नसते|नाहीत|मत(?=[\s.,!?]|$)|शक्य नाही/i;
const GUARANTEE =
  /guarantee|guaranteed|assured job|assured placement|100\s*%\s*(placement|job)|sure[- ]shot job|पक्की नौकरी|नौकरी पक्की|गारंटी|हमखास|नक्की नोकरी|खात्रीशीर नोकरी/i;
const DISCOUNT = /discount|concession|\bwaiver\b|छूट|डिस्काउंट|सवलत|सूट/i;
const CURRENCY_BEFORE = /(₹|rs\.?|inr|रु\.?)\s*$/i;
const CURRENCY_AFTER = /^\s*(\/-|rupees|rupee|₹|रुपये|रुपए|रुपया)/i;
const PERCENT_AFTER = /^\s*(%|percent|per cent|प्रतिशत|टक्के)/i;

export interface GuardResult {
  ok: boolean;
  violations: string[];
}

function toAscii(s: string): string {
  return [...s].map((c) => (DEV_DIGITS.includes(c) ? String(DEV_DIGITS.indexOf(c)) : c)).join("");
}

/** All numbers in the knowledge base, plus totals and post-scholarship fees. */
export function allowedNumbers(kb: KnowledgeBase): { money: Set<number>; percent: Set<number> } {
  const money = new Set<number>();
  const percent = new Set<number>();
  const json = JSON.stringify(kb);
  for (const m of json.matchAll(/\d+(\.\d+)?/g)) money.add(Number(m[0]));
  for (const c of kb.courses) {
    if (c.emi) money.add(c.emi.months * c.emi.perMonthInr);
    for (const s of kb.scholarships ?? []) {
      if (s.amountOffInr) money.add(c.feeInr - s.amountOffInr);
      if (s.percentOff) money.add(Math.round(c.feeInr * (1 - s.percentOff / 100)));
    }
  }
  for (const s of kb.scholarships ?? []) if (s.percentOff) percent.add(s.percentOff);
  for (const m of json.matchAll(/(\d+(\.\d+)?)\s*%/g)) percent.add(Number(m[1]));
  return { money, percent };
}

interface FoundNumber {
  value: number;
  kind: "money" | "percent";
  raw: string;
}

/** Finds money-like and percentage numbers: ₹45,000 · 45k · 1.2 lakh · 45 हजार · 10% */
export function findNumbers(sentence: string): FoundNumber[] {
  const s = toAscii(sentence);
  const out: FoundNumber[] = [];
  const re = /(\d[\d,]*(\.\d+)?)\s*(k\b|thousand|हजार|हज़ार|lakh|lac|लाख)?/gi;
  for (const m of s.matchAll(re)) {
    const idx = m.index ?? 0;
    let value = Number(m[1].replace(/,/g, ""));
    const unit = (m[3] ?? "").toLowerCase();
    if (unit === "k" || unit === "thousand" || unit === "हजार" || unit === "हज़ार") value *= 1000;
    if (unit === "lakh" || unit === "lac" || unit === "लाख") value *= 100000;
    const before = s.slice(Math.max(0, idx - 5), idx);
    const after = s.slice(idx + m[0].length, idx + m[0].length + 10);
    if (PERCENT_AFTER.test(after)) {
      out.push({ value, kind: "percent", raw: m[0] });
    } else if (CURRENCY_BEFORE.test(before) || CURRENCY_AFTER.test(after) || unit || value >= 1000) {
      // ignore years like 2026 and phone-like long numbers
      if (!unit && value >= 1900 && value <= 2100 && !CURRENCY_BEFORE.test(before)) continue;
      if (String(Math.trunc(value)).length >= 8) continue;
      out.push({ value, kind: "money", raw: m[0] });
    }
  }
  return out;
}

export function checkReply(reply: string, kb: KnowledgeBase, userTexts: string[] = []): GuardResult {
  const { money, percent } = allowedNumbers(kb);
  const userNums = new Set<number>(userTexts.flatMap((t) => findNumbers(t).map((n) => n.value)));
  const scholarshipNames = (kb.scholarships ?? []).map((s) => s.name.toLowerCase());
  const violations: string[] = [];
  const sentences = reply.split(/(?<=[.!?।\n])\s+/);

  for (const sentence of sentences) {
    const negated = NEGATION.test(sentence);
    for (const n of findNumbers(sentence)) {
      const known = n.kind === "money" ? money.has(n.value) : percent.has(n.value);
      if (known) continue;
      if (userNums.has(n.value) && negated) continue; // repeating the prospect's number to refuse it
      violations.push(n.kind === "money" ? `amount not in knowledge base: ${n.raw}` : `percentage not in knowledge base: ${n.raw}`);
    }
    if (GUARANTEE.test(sentence) && !negated) {
      violations.push(`placement or job promise: "${sentence.trim().slice(0, 80)}"`);
    }
    if (DISCOUNT.test(sentence) && !negated) {
      const lower = sentence.toLowerCase();
      const mentionsListed = scholarshipNames.some((n) => lower.includes(n)) || /emi|scholarship|स्कॉलरशिप|शिष्यवृत्ती/i.test(sentence);
      if (!mentionsListed) violations.push(`unlisted discount offered: "${sentence.trim().slice(0, 80)}"`);
    }
  }
  return { ok: violations.length === 0, violations };
}
