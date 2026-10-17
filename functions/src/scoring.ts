/**
 * Explainable lead score (0–100). Every point has a reason the counsellor can read.
 *
 *   fit         0–20  what we know about them matches a course (education, goal, timing, budget)
 *   intent      0–25  demo booked, phone shared, asked about fees/batches/admission
 *   engagement  0–15  messages sent, voice notes, more than one channel
 *   recency     0–15  how recently they wrote
 *   aptitude    0–10  result of the in-chat check
 *   aiRead      0–15  the AI's own read of intent from the conversation
 *   objections  0 to -12  unresolved worries (fees, family approval, job fear …)
 */
import type { Lead, ScoreBreakdown } from "./db";

const HOUR = 3_600_000;
const INTENT_WORDS =
  /fee|fees|price|cost|emi|batch|join|admission|enrol|enroll|demo|seat|start|kab|kitni|kitna|kitne|शुल्क|फी|फीस|प्रवेश|ॲडमिशन|एडमिशन|बॅच|बैच|डेमो|कधी|कब/i;

export interface ScoreInput {
  lead: Lead;
  aiScore?: number;
  userTexts: string[];
  now: Date;
}

export function computeScore({ lead, aiScore, userTexts, now }: ScoreInput): { score: number; temperature: "hot" | "warm" | "cold"; breakdown: ScoreBreakdown } {
  const reasons: string[] = [];
  const p = lead.profile ?? {};
  const has = (k: string) => typeof p[k] === "string" && p[k].trim().length > 0;

  // ---- fit
  let fit = 0;
  if (has("education") || has("background")) fit += 6;
  if (has("goal")) fit += 6;
  if (has("timing") || has("constraints")) fit += 4;
  if (has("budget") || has("familyView")) fit += 4;
  if (fit) reasons.push(`+${fit} fit: background/goal/constraints known`);

  // ---- intent
  let intent = 0;
  if (lead.booking) {
    intent = 25;
    reasons.push("+25 intent: demo class booked");
  } else {
    if (lead.phone) intent += 6;
    if (lead.recommendation?.courseId) intent += 6;
    if (userTexts.some((t) => INTENT_WORDS.test(t))) intent += 8;
    if (lead.status === "engaged") intent += 2;
    intent = Math.min(20, intent);
    if (intent) reasons.push(`+${intent} intent: ${[lead.phone ? "phone shared" : "", lead.recommendation ? "has a recommendation" : "", userTexts.some((t) => INTENT_WORDS.test(t)) ? "asked about fees/batch/admission" : ""].filter(Boolean).join(", ") || "engaged"}`);
  }
  if (lead.status === "admitted") {
    intent = 25;
  }

  // ---- engagement
  const msgs = lead.userMessages ?? userTexts.length;
  let engagement = Math.min(10, msgs * 2);
  if ((lead.voiceNotes ?? 0) > 0) engagement += 3;
  if ((lead.sources?.length ?? 0) > 1) engagement += 2;
  engagement = Math.min(15, engagement);
  if (engagement) reasons.push(`+${engagement} engagement: ${msgs} message(s)${(lead.voiceNotes ?? 0) > 0 ? ", voice notes" : ""}${(lead.sources?.length ?? 0) > 1 ? ", several channels" : ""}`);

  // ---- recency
  const last = lead.lastInboundAt?.toDate?.() ?? lead.lastMessageAt?.toDate?.();
  let recency = 0;
  if (last) {
    const age = now.getTime() - last.getTime();
    recency = age < HOUR ? 15 : age < 24 * HOUR ? 10 : age < 72 * HOUR ? 5 : 0;
    if (recency) reasons.push(`+${recency} recency: last wrote ${age < HOUR ? "within the hour" : age < 24 * HOUR ? "today" : "in the last 3 days"}`);
  }

  // ---- aptitude
  let aptitude = 0;
  const a = lead.aptitude;
  if (a?.status === "done") {
    aptitude = a.band === "strong" ? 10 : a.band === "intermediate" ? 7 : 4;
    reasons.push(`+${aptitude} aptitude: ${a.band}`);
  } else if (a?.status === "in_progress") {
    aptitude = 3;
    reasons.push("+3 aptitude: check in progress");
  }

  // ---- the AI's own read
  const aiRead = Math.round(Math.max(0, Math.min(100, aiScore ?? lead.aiScore ?? 0)) * 0.15);
  if (aiRead) reasons.push(`+${aiRead} AI read of intent (${aiScore ?? lead.aiScore}/100)`);

  // ---- objections
  const objs = (lead.objections ?? []).filter((o) => o !== "other");
  let objections = -Math.min(12, objs.length * 4);
  if (lead.booking && objections < 0) objections = Math.round(objections / 2);
  if (objections) reasons.push(`${objections} unresolved worries: ${objs.join(", ")}`);

  let score = fit + intent + engagement + recency + aptitude + aiRead + objections;
  if (lead.status === "admitted") score = Math.max(score, 90);
  if (lead.status === "lost") score = Math.min(score, 15);
  score = Math.max(0, Math.min(100, Math.round(score)));
  const temperature = score >= 70 ? "hot" : score >= 40 ? "warm" : "cold";
  return { score, temperature, breakdown: { fit, intent, engagement, recency, aptitude, aiRead, objections, reasons } };
}
