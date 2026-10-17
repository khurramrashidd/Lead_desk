/**
 * Asha, the AI admissions counsellor. One brain for every channel, so the same person
 * always gets the same answer.
 *
 * Division of labour:
 *   the model   → understands text/voice in EN/HI/MR, mirrors language and register, counsels,
 *                 writes the reply, the 3-line summary and the follow-up message.
 *   the server  → the Guard (no invented fees/discounts/guarantees), aptitude scoring, the lead
 *                 score, next-best-action timing and channel, slot booking + Google Calendar.
 */
import { createHash } from "node:crypto";
import { db, FieldValue, Timestamp, demoNow, logEvent, type AiLock, type AptitudeState, type KnowledgeBase, type Lead, type Message, type Slot } from "./db";
import { generateJson, type Turn } from "./ai";
import { checkReply } from "./guard";
import { formatIst, googleCalendarUrl, normaliseQuestion, respectQuietHours, t } from "./lang";
import { latinName, resolveIdentity } from "./merge";
import { advanceOnboarding, nudgeText, onboardingBrief, type ObOption, type OnboardingState } from "./onboarding";
import { offlineAnswer } from "./offline";
import { advance, byId, formatQuestion, plan, readPick, type Question } from "./aptitude";
import { computeScore } from "./scoring";
import { decideNextAction } from "./nba";
import { createCalendarEvent } from "./calendar";
import { assignByLanguage, hotLeadAlert } from "./assign";
import { channelConfig, deliverOn } from "./channels";
import { normalizePhone } from "./identity";
import { bumpStat } from "./stats";
import { singleFlight } from "./cache";
import { flowGate, ft, qrPng, touchSession, type ChatSession, type Enrollment } from "./flow";

let kbCache: { kb: KnowledgeBase; at: number } | null = null;
/** Hash of the knowledge base: any edit in Admin changes it and invalidates cached answers. */
let kbVersion = "";
export async function getKb(): Promise<KnowledgeBase> {
  if (kbCache && Date.now() - kbCache.at < 30_000) return kbCache.kb;
  const snap = await db.doc("kb/main").get();
  const kb = (snap.data() as KnowledgeBase | undefined) ?? { instituteName: "SechTummit Trainers", city: "Pune", courses: [] };
  delete (kb as unknown as Record<string, unknown>).updatedAt;
  kbVersion = createHash("sha256").update(JSON.stringify(kb)).digest("hex").slice(0, 16);
  kbCache = { kb, at: Date.now() };
  return kb;
}

export async function openSlots(now: Date, kind: "demo" | "call" | "meet" | "any" = "demo"): Promise<Slot[]> {
  const snap = await db.collection("slots").where("startAt", ">", Timestamp.fromDate(now)).orderBy("startAt").limit(40).get();
  return snap.docs
    .map((d) => ({ id: d.id, ...(d.data() as Omit<Slot, "id">) }))
    .filter((s) => s.booked < s.capacity && (kind === "any" || (s.kind ?? "demo") === kind))
    .slice(0, 12);
}

const OBJECTIONS = ["fees", "job_fear", "family_approval", "time", "distance", "language", "trust", "other"];

const RESPONSE_SCHEMA = {
  type: "object",
  properties: {
    transcript: { type: "string", description: "Verbatim transcript of the latest voice note in its original language and script. Empty if no audio." },
    language: { type: "string", enum: ["en", "hi", "mr", "hinglish", "marathi-english", "mixed"] },
    script: { type: "string", enum: ["latin", "devanagari", "mixed"] },
    register: { type: "string", enum: ["formal", "casual"] },
    reply: { type: "string", description: "The message to send to the prospect." },
    name: { type: "string" },
    phone: { type: "string" },
    email: { type: "string" },
    city: { type: "string" },
    relation: { type: "string", enum: ["self", "parent", "guardian", "sibling", "friend", "other", "unknown"], description: "Who is writing, relative to the student." },
    student_name: { type: "string", description: "The student's name if someone else (e.g. a parent or friend) is writing." },
    student_phone: { type: "string", description: "The student's own mobile number if the person writing shares it." },
    profile: {
      type: "object",
      properties: {
        background: { type: "string" },
        education: { type: "string" },
        gap: { type: "string" },
        currentWork: { type: "string" },
        codingExperience: { type: "string", description: "none / beginner / some / professional" },
        goal: { type: "string" },
        constraints: { type: "string" },
        budget: { type: "string" },
        timing: { type: "string" },
        familyView: { type: "string" },
      },
    },
    objections: { type: "array", items: { type: "string", enum: OBJECTIONS } },
    intent_score: { type: "integer", description: "0-100: your read of how likely they are to join soon." },
    summary: { type: "array", items: { type: "string" }, description: "Exactly 3 short English lines for the counsellor." },
    suggested_message: { type: "string", description: "Next message a human counsellor could send, in the prospect's language and register." },
    next_action: {
      type: "object",
      properties: {
        message: { type: "string", description: "Follow-up to send if they go quiet, in their language and register, addressing their main objection." },
        reason_hint: { type: "string", description: "One short English line: why that follow-up." },
      },
      required: ["message"],
    },
    aptitude: {
      type: "object",
      properties: {
        event: { type: "string", enum: ["none", "offered", "started", "answered", "skipped"] },
        picked: { type: "string", description: "A, B or C if the latest message answers CURRENT_QUESTION, else empty." },
        shown_id: { type: "string", description: "Id of the aptitude question you ask in this reply, else empty." },
        question_block: { type: "string", description: "The aptitude question you ask (translated): question line, then A) / B) / C) lines. Empty if none." },
      },
      required: ["event"],
    },
    recommendation: {
      type: "object",
      properties: { course_id: { type: "string" }, reason: { type: "string", description: "Honest reason in English for the counsellor." } },
    },
    book_slot_id: { type: "string", description: "Slot id from AVAILABLE_SLOTS when the prospect clearly picked a slot, else empty." },
    kb_refs: { type: "array", items: { type: "string" } },
    handoff: { type: "boolean" },
    handoff_reason: { type: "string" },
  },
  required: ["language", "script", "register", "reply", "objections", "intent_score", "summary", "suggested_message", "next_action", "aptitude", "handoff"],
};

interface BrainOut {
  transcript?: string;
  language: string;
  script: string;
  register: string;
  reply: string;
  name?: string;
  phone?: string;
  email?: string;
  city?: string;
  relation?: string;
  student_name?: string;
  student_phone?: string;
  profile?: Record<string, string>;
  objections: string[];
  intent_score: number;
  summary: string[];
  suggested_message: string;
  next_action: { message: string; reason_hint?: string };
  aptitude: { event: string; picked?: string; shown_id?: string; question_block?: string };
  recommendation?: { course_id: string; reason: string };
  book_slot_id?: string;
  kb_refs?: string[];
  handoff: boolean;
  handoff_reason?: string;
}

function aptitudeBlock(lead: Lead, latestText = ""): string {
  const p = plan(lead.aptitude, lead.profile);
  const s = p.state;
  const lines: string[] = [`status: ${s.status}, answered ${s.answers.length}/4, correct ${s.correct}`];
  lines.push(
    "RULES: the questions come ONLY from this block (never invent a quiz, riddle or sequence question of your own, before, during or after the check).",
    "Do NOT write the aptitude question or its A/B/C options in \"reply\". Put the question you ask in \"question_block\" instead: the question translated into their language on one line, then \"A) …\", \"B) …\", \"C) …\" each on its own line (numbers as digits). The system shows it under your reply with tap buttons. In \"reply\" just react and lead in (e.g. \"Next one 👇\").",
  );
  if (s.status === "done") {
    lines.push(`RESULT (already shared): ${s.result}. Use it for the recommendation; do not run the check again. question_block must be empty.`);
  } else if (s.status === "skipped") {
    lines.push("They declined the check. Do not offer it again unless they ask. question_block must be empty.");
  } else if (!p.current) {
    lines.push(
      "When you know their background and goal (usually after 2-3 exchanges) and they have not declined, OFFER a quick 4-question aptitude check (about 2 minutes) and set aptitude.event=\"offered\".",
      "If the prospect agrees in their latest message, set aptitude.event=\"started\", aptitude.shown_id to FIRST_QUESTION's id and put FIRST_QUESTION in question_block.",
      `FIRST_QUESTION: ${formatQuestion(p.first)}`,
    );
  } else {
    const cur = p.current;
    const pick = readPick(latestText, cur);
    lines.push(`CURRENT_QUESTION (on their screen, waiting for an answer): ${formatQuestion(cur)}`);
    if (pick) {
      // Scored HERE, before the model speaks, so Asha can never call a right answer wrong.
      const correct = pick === cur.answer;
      const opt = (k: string) => cur.options.find((o) => o.key === k)?.text ?? "";
      lines.push(
        `THEIR ANSWER (already checked by the system, do not re-judge): ${pick}) ${opt(pick)} → ${correct ? "CORRECT" : "WRONG"}. ${correct ? "Praise briefly." : `Kindly say the right answer is ${cur.answer}) ${opt(cur.answer)} with a one-line why.`}`,
        `Set aptitude.event="answered" and aptitude.picked="${pick}".`,
      );
      const next = correct ? p.nextIfCorrect : p.nextIfWrong;
      if (p.finishesAfterThis) {
        lines.push(
          "This was the LAST question. After reacting, share the result in their language:",
          `  ${correct ? p.resultIfCorrect : p.resultIfWrong}`,
          "then move on to your honest course recommendation. aptitude.shown_id and question_block empty.",
        );
      } else if (next) {
        lines.push(`Then ask NEXT_QUESTION: put it in question_block and set aptitude.shown_id="${next.id}".`, `NEXT_QUESTION: ${formatQuestion(next)}`);
      }
    } else {
      lines.push(
        `Correct answer: ${cur.answer}. If their latest message answers it in words, set aptitude.event="answered" and aptitude.picked to the letter (A/B/C) they meant, react (right → brief praise; wrong → kindly give the right answer), then ask: if right → NEXT_IF_CORRECT, if wrong → NEXT_IF_WRONG (in question_block, shown_id = its id).`,
        p.finishesAfterThis
          ? `This is the LAST question: after reacting share the result (right → ${p.resultIfCorrect} / wrong → ${p.resultIfWrong}) and recommend a course; question_block empty.`
          : `NEXT_IF_CORRECT: ${formatQuestion(p.nextIfCorrect)}\nNEXT_IF_WRONG: ${formatQuestion(p.nextIfWrong)}`,
        "If they ask something else first, answer briefly; the system shows CURRENT_QUESTION again (shown_id = its id, question_block = it). If they want to stop, set aptitude.event=\"skipped\".",
      );
    }
  }
  return lines.join("\n");
}

/** The question as plain text, used when the model's own version is missing or does not match. */
function plainQuestion(q: Question): string {
  return `${q.text}\n${q.options.map((o) => `${o.key}) ${o.text}`).join("\n")}`;
}

/** The model's translated block is only trusted if it really is THIS question (same letters, same numbers). */
function blockMatches(block: string, q: Question): boolean {
  const b = (block ?? "").trim();
  if (!b) return false;
  for (const o of q.options) {
    const line = b.split("\n").find((l) => new RegExp(`^\\s*\\(?${o.key}\\)`).test(l));
    if (!line) return false;
    const digits = o.text.match(/\d+/g);
    if (digits && !digits.every((d) => line.includes(d))) return false;
  }
  const stemDigits = q.text.match(/\d+/g) ?? [];
  return stemDigits.every((d) => b.includes(d));
}

/** True when the reply's verdict says the opposite of the server's scoring. */
export function verdictConflicts(reply: string, correct: boolean): boolean {
  const r = reply.toLowerCase();
  const saysWrong = /\b(oops|wrong|incorrect|not quite|not correct|right answer (was|is)|correct answer (was|is)|galat)\b|गलत|चूक|सही जवाब (था|है)/.test(r);
  const saysRight = /^\W*(✅\s*)?(correct|right|that's right|that is right|well done|great|sahi|bilkul|सही|बरोबर|शाबास)\b/.test(r);
  return correct ? saysWrong : saysRight && !saysWrong;
}

/** Removes any quiz the model wrote into the reply itself (option lines and the question line above them). */
export function stripQuiz(reply: string, q?: Question): string {
  const lines = reply.split("\n");
  const isOpt = (l: string) => /^\s*\(?[A-Ca-c]\)\s*\S/.test(l);
  const optLines = lines.filter(isOpt).length;
  const seq = q ? (q.text.match(/\d+/g) ?? []) : [];
  const seqRe = seq.length >= 3 ? new RegExp(seq.slice(0, 3).join("\\D{1,4}")) : null;
  const out: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    if (optLines >= 2 && isOpt(l)) continue;
    const quizLine =
      (optLines >= 2 && l.includes("?") && i + 1 < lines.length && isOpt(lines[i + 1])) ||
      (seqRe !== null && seqRe.test(l)) ||
      (!!q && l.toLowerCase().includes(q.text.toLowerCase().slice(0, 28)));
    if (quizLine) {
      // Keep the sentences before the question ("Great work! Next one: What comes next…?" → "Great work!").
      const sentences = l.split(/(?<=[.!।])\s+/);
      const keep: string[] = [];
      for (const x of sentences) {
        if (x.includes("?") || (seqRe !== null && seqRe.test(x)) || /\d+\s*,\s*\d+\s*,\s*\d+/.test(x)) break;
        keep.push(x);
      }
      if (keep.length) out.push(keep.join(" "));
      continue;
    }
    out.push(l);
  }
  return out.join("\n").replace(/\n{3,}/g, "\n\n").trim();
}

function leadState(lead: Lead): Record<string, unknown> {
  return {
    name: lead.name,
    phoneKnown: !!lead.phone,
    city: lead.city,
    relation: lead.contacts?.[0]?.relation,
    studentName: lead.studentName,
    studentContactKnown: !!(lead.studentPhone || lead.studentEmail),
    interestedCourse: lead.interestCourseId,
    profile: lead.profile,
    objections: lead.objections,
    recommendation: lead.recommendation,
    booking: lead.booking ? { title: lead.booking.title, when: formatIst(lead.booking.startAt.toDate()) } : null,
    channelsUsed: lead.sources,
  };
}

function systemPrompt(kb: KnowledgeBase, slots: Slot[], lead: Lead, channel: string, now: Date, intake = "", latestText = ""): string {
  const slotList = slots.map((s) => ({ id: s.id, title: s.title, course: s.courseId ?? "", when: formatIst(s.startAt.toDate()), mode: s.mode, seatsLeft: s.capacity - s.booked }));
  const state = leadState(lead);
  return `You are Asha, the admissions counsellor of ${kb.instituteName}, a tech training institute in ${kb.city}. You are chatting on ${channel}. Current time: ${formatIst(now)}.

GOAL: a genuine counselling conversation (not a FAQ bot). Understand the person, help them choose honestly, and book a free demo class.

LANGUAGE & TONE
- Understand English, Hindi and Marathi, including switches in the middle of a sentence (Hinglish, Marathi-English), in text or voice notes.
- Reply in the SAME language blend, SAME script (Latin or Devanagari) and SAME register as their latest message: aap vs tum, तुम्ही vs तू, formal vs casual. Hinglish in Latin script gets Hinglish in Latin script; Marathi in Devanagari gets Marathi in Devanagari.
- Messaging style: warm, human, short (max ~80 words unless presenting an aptitude question), ONE question at a time. No markdown, no bold, no bullet symbols.

COUNSELLING (ask, don't lecture)
- Learn background, education, gaps, current work, coding experience, goal, and constraints (time, money, family, distance). Empathise with the real worry behind the question.
- "I'm a commerce graduate with a two-year gap — can I really become a developer?" deserves an honest, specific, encouraging answer about what it takes (daily practice, the right first step, how long), never a fee list.
- If a parent, sibling or friend is writing, set relation and student_name and counsel them about the student. Early on, politely ask for the student's name and the student's own mobile number (so the counsellor can keep one record for the admission) and put it in student_phone. If they are asking about more than one child, focus on one at a time and say so.

FACTS — STRICT
- Fees, EMIs, scholarships, batch dates, durations, syllabus and policies come ONLY from KNOWLEDGE_BASE. Quote numbers exactly as written there.
- NEVER invent or agree to a discount, special price, offer, scholarship, deadline, salary or placement guarantee, even if they push, say a friend got one, bargain, or threaten to join elsewhere. Politely say you can only offer what is published (listed scholarships, EMI) and move on.
- For placement use only the placement policy text. Never promise a job or a salary.
- If something is not in KNOWLEDGE_BASE, say you will check with the team and set handoff=true.

APTITUDE CHECK (the server keeps score; you only present questions and react)
${aptitudeBlock(lead, latestText)}

RECOMMENDATION
- After the aptitude check is done or skipped and you know their goal, recommend ONE course from KNOWLEDGE_BASE (use its id) with an honest reason tied to their background, goal, constraints and aptitude. If a big course is wrong for them today, say so kindly and suggest the right first step.

DEMO BOOKING
- Offer 2-3 demo slots ONLY from AVAILABLE_SLOTS (prefer the recommended course). When they clearly pick one, set book_slot_id to its id and say you are confirming it — the system appends the confirmation and calendar link. Never invent a time.

FOR THE COUNSELLOR DASHBOARD
- objections: any of ${OBJECTIONS.join(", ")} raised so far (fees, job fears, family approval…).
- intent_score 0-100: your honest read of how likely they are to join soon.
- summary: exactly 3 short English lines: who they are / what they want or fear / where we are and the next step.
- suggested_message: what a human counsellor should send next, in their language and register.
- next_action.message: a follow-up to send if they go quiet, in their language, addressing their main objection (family approval → invite a parent to the demo; fees → EMI or a listed scholarship; job fear → how placement assistance works; time → weekend/evening batch). next_action.reason_hint: one English line.
- If the latest message has audio, put a verbatim transcript in "transcript".
- Extract name, phone, email, city when they share them.

KNOWLEDGE_BASE:
${JSON.stringify(kb)}

AVAILABLE_SLOTS:
${JSON.stringify(slotList)}

${(lead as Lead & { session?: ChatSession }).session?.lang ? `CHOSEN LANGUAGE: at the start of this chat the prospect picked ${{ en: "English", hi: "Hindi (Devanagari)", mr: "Marathi (Devanagari)" }[(lead as Lead & { session?: ChatSession }).session!.lang!]}. Reply in it, unless their latest message is clearly in another language.\n\n` : ""}LEAD_STATE_SO_FAR:
${JSON.stringify(state)}${intake ? `\n\nINTAKE ANSWERS (asked by the system just before this reply):\n${intake}` : ""}`;
}

/** History → model turns. Voice notes the model has not heard yet go in as audio (newest 3). */
function toTurns(history: Message[], unanswered: Set<number>): Turn[] {
  const audioIdx = new Set(
    history
      .map((m, i) => ({ m, i }))
      .filter(({ m, i }) => m.role === "user" && m.audioB64 && !m.transcript && unanswered.has(i))
      .map(({ i }) => i)
      .slice(-3),
  );
  const turns: Turn[] = [];
  history.forEach((m, i) => {
    const role: Turn["role"] = m.role === "user" ? "user" : "model";
    if (audioIdx.has(i)) {
      turns.push({ role, text: m.text && !m.text.startsWith("🎤") ? m.text : "(voice note)", audio: { b64: m.audioB64!, mime: m.audioMime || "audio/webm" } });
      return;
    }
    let text = m.transcript ? `(voice note) ${m.transcript}` : m.text || (m.audioB64 ? "(voice note)" : "");
    if (m.role === "counsellor") text = `[Human counsellor]: ${text}`;
    if (m.role === "system") text = `[Automatic note]: ${text}`;
    if (text) turns.push({ role, text });
  });
  return turns;
}

export interface BrainResult {
  /** A UPI payment QR to send as an image on WhatsApp / Telegram (the web chat draws it). */
  qr?: { link: string };
  reply: string;
  channel: string;
  /** Tappable choices (intake questions, aptitude A/B/C): buttons on WhatsApp, a keyboard on Telegram. */
  options?: ObOption[];
  askContact?: boolean;
  lang?: string;
  /** The stored message, so a failed delivery can be marked on it. */
  msgId?: string;
}

// ------------------------------------------------------------------ answer cache
// The same first question from thousands of different people ("Full Stack Java ki fees kitni
// hai?", "hi") is answered by the AI ONCE; everyone else gets that answer in milliseconds.
// The key includes everything the model saw (question, channel, lead state, knowledge-base
// version, open slots), so a cached answer is exactly what the model would have said.
// If 1,000 identical questions arrive in the same second, one worker asks the AI and the rest
// wait for its answer (single-flight), instead of 1,000 AI calls.
const PROMPT_VERSION = "v10";

function sha(s: string): string {
  return createHash("sha256").update(s).digest("hex").slice(0, 40);
}

interface Thought {
  out: BrainOut;
  provider: string;
  blockedDraft: string | null;
  violations: string[];
}

/** Ask the AI pool, then run the Guard (and one rewrite if it blocked something). */
async function think(leadId: string, system: string, turns: Turn[], kb: KnowledgeBase, userTexts: string[]): Promise<Thought> {
  const r = await generateJson<BrainOut>(system, turns, RESPONSE_SCHEMA);
  let out = r.data;
  const provider = `${r.kind}:${r.model}`;
  if (r.transcript && !out.transcript) out.transcript = r.transcript;
  out.reply = (out.reply ?? "").trim() || t("busy", out.language);
  out.objections = (out.objections ?? []).filter((o) => OBJECTIONS.includes(o));
  const texts = out.transcript ? [...userTexts, out.transcript] : userTexts;

  let guard = checkReply(out.reply, kb, texts);
  let blockedDraft: string | null = null;
  if (!guard.ok) {
    blockedDraft = out.reply;
    await logEvent("guard_block", leadId, { draft: out.reply, violations: guard.violations });
    await bumpStat("guardBlocks");
    const retry: Turn[] = [
      ...turns.map((x) => ({ ...x })),
      { role: "model", text: out.reply },
      {
        role: "user",
        text: `[SYSTEM CHECK — not from the prospect] Your draft was blocked: ${guard.violations.join("; ")}. Rewrite the reply using ONLY knowledge-base facts, politely declining anything not listed. Same language, script and register. Keep any aptitude question you were asking.`,
      },
    ];
    try {
      const second = (await generateJson<BrainOut>(system, retry, RESPONSE_SCHEMA)).data;
      const g2 = checkReply(second.reply ?? "", kb, texts);
      if (g2.ok && second.reply) out = { ...out, ...second, transcript: out.transcript };
      else out.reply = t("safeFallback", out.language);
      guard = g2;
    } catch {
      out.reply = t("safeFallback", out.language);
    }
  }
  // The suggested message and the follow-up are sent later, so they pass the Guard too.
  if (out.suggested_message && !checkReply(out.suggested_message, kb, texts).ok) out.suggested_message = "";
  if (out.next_action?.message && !checkReply(out.next_action.message, kb, texts).ok) out.next_action.message = t("nudge", out.language);
  return { out, provider, blockedDraft, violations: guard.violations };
}

// --------------------------------------------------------------- per-lead worker
// One AI reply per lead at a time. If someone sends three messages in five seconds, the first
// trigger answers and the other two only raise a "pending" flag; the worker then answers all
// of them together in one reply. Duplicate deliveries of the same event are ignored.
const LOCK_MS = 150_000;

export async function respond(leadId: string): Promise<BrainResult[]> {
  const ref = db.doc(`leads/${leadId}`);
  const got = await db.runTransaction(async (tx) => {
    const ai = ((await tx.get(ref)).get("ai") ?? {}) as AiLock;
    const busy = ai.busy && ai.since && Date.now() - ai.since.toMillis() < LOCK_MS;
    if (busy) {
      tx.set(ref, { ai: { pending: true } }, { merge: true });
      return false;
    }
    tx.set(ref, { ai: { busy: true, since: Timestamp.now(), pending: false } }, { merge: true });
    return true;
  });
  if (!got) {
    await bumpStat("coalesced");
    return [];
  }
  const results: BrainResult[] = [];
  try {
    for (let round = 0; round < 4; round++) {
      const r = await counsel(leadId);
      if (r) results.push(r);
      const again = await db.runTransaction(async (tx) => {
        const ai = ((await tx.get(ref)).get("ai") ?? {}) as AiLock;
        if (ai.pending && round < 3) {
          tx.set(ref, { ai: { pending: false, since: Timestamp.now() } }, { merge: true });
          return true;
        }
        tx.set(ref, { ai: { busy: false, pending: false } }, { merge: true });
        return false;
      });
      if (!again) break;
    }
  } catch (e) {
    await ref.set({ ai: { busy: false } }, { merge: true });
    throw e;
  }
  return results;
}

/** respond() + send each reply out on the lead's own channel. */
export async function respondAndDeliver(leadId: string): Promise<number> {
  const results = await respond(leadId);
  if (!results.length) return 0;
  const lead = (await db.doc(`leads/${leadId}`).get()).data() as Lead | undefined;
  if (!lead) return 0;
  for (const r of results) {
    if (!["whatsapp", "telegram", "instagram"].includes(r.channel)) continue;
    let d: { delivered: boolean; note: string } | null = null;
    if (r.qr && (r.channel === "telegram" || r.channel === "whatsapp")) {
      // The payment QR goes out as an image with the instructions as its caption.
      try {
        const png = await qrPng(r.qr.link);
        const sent =
          r.channel === "telegram"
            ? lead.telegramId && !lead.telegramId.startsWith("sim:") ? await (await import("./telegram")).sendTelegramPhoto(lead.telegramId, png, r.reply) : { ok: false, error: "no Telegram chat" }
            : lead.waId && !lead.waId.startsWith("sim:") ? await (await import("./whatsapp")).sendWhatsAppImage(lead.waId, png, r.reply) : { ok: false, error: "no WhatsApp id" };
        if (sent.ok) d = { delivered: true, note: "" };
        else console.warn("QR image not sent, falling back to text", sent.error);
      } catch (e) {
        console.warn("QR image failed, falling back to text", e);
      }
    }
    d ??= await deliverOn(r.channel, lead, r.reply, { options: r.options, askContact: r.askContact, lang: r.lang });
    if (!d.delivered && r.msgId) {
      // Visible on the desk: e.g. "(#131030) Recipient phone number not in allowed list".
      await db
        .doc(`leads/${leadId}/messages/${r.msgId}`)
        .set({ meta: { delivered: false, note: d.note || "send failed" } }, { merge: true })
        .catch(() => undefined);
      await db.doc(`leads/${leadId}`).set({ deliveryIssue: { channel: r.channel, note: (d.note || "send failed").slice(0, 240), at: FieldValue.serverTimestamp() } }, { merge: true });
    } else if (d.delivered && lead.deliveryIssue) {
      await db.doc(`leads/${leadId}`).set({ deliveryIssue: FieldValue.delete() }, { merge: true });
    }
  }
  await touchSession(leadId).catch((e) => console.warn("session clock", e));
  return results.length;
}

/** Answers every prospect message that has not been answered yet, in one reply. */
export async function counsel(leadId: string, depth = 0): Promise<BrainResult | null> {
  const leadRef = db.doc(`leads/${leadId}`);
  const lead = ((await leadRef.get()).data() ?? {}) as Lead;
  if (lead.mergedInto) return null;

  const now = await demoNow();
  const [kb, slots, histSnap] = await Promise.all([
    getKb(),
    openSlots(now),
    leadRef.collection("messages").orderBy("createdAt", "desc").limit(24).get(),
  ]);
  // The current chat session only: a restart or an auto-closed chat starts a clean slate, and
  // the language question and its answer are not part of the conversation.
  const sessionStart = (lead as Lead & { session?: ChatSession }).session?.startedAt?.toMillis?.() ?? 0;
  const docs = histSnap.docs
    .slice()
    .reverse()
    .filter((d) => {
      const m = d.data() as Message;
      if (((m.meta ?? {}) as Record<string, unknown>).sessionControl) return false;
      const at = m.createdAt?.toMillis?.();
      return !sessionStart || at === undefined || at >= sessionStart;
    });
  const history = docs.map((d) => d.data() as Message);

  // What has not been answered yet: prospect messages after the last real reply.
  let lastReply = -1;
  history.forEach((m, i) => {
    const meta = (m.meta ?? {}) as Record<string, unknown>;
    if (m.role === "counsellor" || (m.role === "ai" && !meta.fallback && !meta.automatic)) lastReply = i;
  });
  const unansweredIdx = history.map((m, i) => (m.role === "user" && i > lastReply ? i : -1)).filter((i) => i >= 0);
  if (!unansweredIdx.length) return null;
  const latestIdx = unansweredIdx[unansweredIdx.length - 1];
  const latestDoc = docs[latestIdx];
  const msg = history[latestIdx];
  if (lead.ai?.lastAnsweredId === latestDoc.id) return null; // duplicate trigger

  const fresh = unansweredIdx.map((i) => history[i]);
  const counters: Record<string, unknown> = {
    userMessages: FieldValue.increment(fresh.length),
    unansweredFollowups: 0,
    ...(fresh.some((m) => m.audioB64) ? { voiceNotes: FieldValue.increment(fresh.filter((m) => m.audioB64).length) } : {}),
  };
  if (lead.aiPaused) {
    await leadRef.set(
      { ...counters, needsHuman: true, handoffReason: "Counsellor has taken over: reply from the desk", ai: { lastAnsweredId: latestDoc.id } },
      { merge: true },
    );
    return null;
  }

  // ---- Language first, restart, enrolment + payment receipt (no AI needed) ----
  const gate = await flowGate({ leadId, lead, msg, msgId: latestDoc.id, kb });
  if (gate?.skip) return null;
  if (gate?.rerun) return depth < 2 ? counsel(leadId, depth + 1) : null;
  if (gate?.reply) {
    await leadRef.set({ lastMessageAt: FieldValue.serverTimestamp(), lastChannel: msg.channel }, { merge: true });
    return { reply: gate.reply.text, channel: gate.reply.channel, options: gate.reply.options, lang: gate.reply.lang, msgId: gate.reply.msgId, qr: gate.reply.qr, askContact: gate.reply.askContact };
  }

  // ---- Intake questions (who / name / contact / course) before counselling ----
  let intake = "";
  let identityFromIntake = false;
  const meta = (msg.meta ?? {}) as Record<string, unknown>;
  if (await onboardingApplies(lead, msg, history, lastReply)) {
    const r = advanceOnboarding(lead.onboarding ?? null, {
      text: msg.text && !msg.text.startsWith("🎤") ? msg.text : "",
      choiceId: typeof meta.choiceId === "string" ? meta.choiceId : undefined,
      isVoice: !!msg.audioB64,
      phoneKnown: msg.channel === "whatsapp" && !!lead.phone,
      langHint: String((lead as Lead & { session?: ChatSession }).session?.lang ?? meta.uiLang ?? meta.langHint ?? lead.uiLang ?? lead.language ?? ""),
      introShown: msg.channel === "web",
      courses: kb.courses,
      instituteName: kb.instituteName,
    });
    // Earlier unanswered questions in the same burst are kept for Asha.
    if (!r.state.firstQuestion) {
      const earlier = fresh.slice(0, -1).map((m) => m.text ?? "").find((x) => x.length > 8 && !x.startsWith("["));
      if (earlier) r.state.firstQuestion = earlier.slice(0, 400);
    }
    const patch = intakePatch(lead, r.state, msg.channel);
    identityFromIntake = patch.identityChanged;
    Object.assign(lead, patch.local);
    if (r.reply) {
      const ref = await leadRef.collection("messages").add({
        role: "ai",
        channel: msg.channel,
        text: r.reply.text,
        createdAt: FieldValue.serverTimestamp(),
        meta: {
          kind: "onboarding",
          step: r.state.step,
          options: r.reply.options.map((o) => o.label),
          choices: r.reply.options,
          ...(r.reply.askContact ? { askContact: true } : {}),
          ...(fresh.length > 1 ? { answeredTogether: fresh.length } : {}),
        },
      });
      const nudgeAt = respectQuietHours(new Date(now.getTime() + 2 * 3_600_000));
      await leadRef.set(
        {
          ...counters,
          ...patch.write,
          status: !lead.status || lead.status === "new" ? "engaged" : lead.status,
          lastMessageAt: FieldValue.serverTimestamp(),
          lastInboundAt: Timestamp.fromDate(now),
          lastChannel: msg.channel,
          // Nobody is forgotten: if they stop halfway, Asha nudges them later.
          nextAction: {
            at: Timestamp.fromDate(nudgeAt),
            channel: msg.channel,
            message: nudgeText(r.state.lang),
            reason: "stopped answering the intake questions",
            playbook: "intake_nudge",
            done: false,
          },
          summary: intakeSummary(lead, r.state),
          ai: { lastAnsweredId: latestDoc.id, retries: 0, retryAt: FieldValue.delete(), lastError: FieldValue.delete() },
        },
        { merge: true },
      );
      await bumpStat("intakeSteps");
      if (identityFromIntake) await resolveIdentity(leadId);
      if (lead.uiLang === undefined && typeof meta.uiLang === "string") await leadRef.set({ uiLang: meta.uiLang }, { merge: true });
      return { reply: r.reply.text, channel: msg.channel, options: r.reply.options, askContact: r.reply.askContact, lang: r.state.lang, msgId: ref.id };
    }
    // Intake finished (or handed over): Asha answers this message with what was learnt.
    await leadRef.set({ ...patch.write }, { merge: true });
  }
  if (lead.onboarding?.step === "done" && !lead.onboarding.briefed) intake = onboardingBrief(lead.onboarding, kb.courses);

  const system = systemPrompt(kb, slots, lead, msg.channel, now, intake, msg.text && !msg.text.startsWith("🎤") ? msg.text : "");
  const turns = toTurns(history, new Set(unansweredIdx));
  const userTexts = history.filter((m) => m.role === "user").map((m) => m.text || m.transcript || "");

  // Cache only a stranger's very first text question (same input → same answer).
  const priorUser = history.some((m, i) => m.role === "user" && i <= lastReply);
  const text = (msg.text ?? "").trim();
  const cacheable =
    fresh.length === 1 && !priorUser && !msg.audioB64 && !!text && text.length <= 240 && !text.startsWith("[") && !history.some((m) => m.role === "counsellor");

  let thought: Thought;
  let cacheState: "hit" | "wait" | "miss" | "off" = "off";
  try {
    if (cacheable) {
      const key = sha(
        JSON.stringify([PROMPT_VERSION, msg.channel, (lead as Lead & { session?: ChatSession }).session?.lang ?? "", kbVersion, slots.slice(0, 5).map((s) => s.id), leadState(lead), lead.aptitude?.status ?? "", normaliseQuestion(text)]),
      );
      const r = await singleFlight<Thought>(key, () => think(leadId, system, turns, kb, userTexts), (v) => !v.out.book_slot_id && !v.out.handoff);
      thought = r.value;
      cacheState = r.state;
      if (r.state !== "miss") await bumpStat(r.state === "hit" ? "cacheHits" : "cacheWaits");
    } else {
      thought = await think(leadId, system, turns, kb, userTexts);
    }
  } catch (e) {
    const why = String((e as Error)?.message ?? e);
    console.error("AI failed", why);
    // Never lost: an instant answer from the knowledge base once, then automatic retries with
    // back-off (2, 4, 8… min) until the AI is back. The fallback is not counted as a reply, so
    // the retry still answers properly.
    const retries = (lead.ai?.retries ?? 0) + 1;
    const lang = lead.language ?? lead.onboarding?.lang ?? lead.uiLang;
    const quick = text && !msg.audioB64 ? offlineAnswer(kb, [lead.onboarding?.firstQuestion ?? "", text].join(" "), lang, slots) : t("busy", lang);
    let quickId: string | undefined;
    if (retries === 1) {
      const ref = await leadRef.collection("messages").add({
        role: "ai",
        channel: msg.channel,
        text: quick,
        createdAt: FieldValue.serverTimestamp(),
        meta: { fallback: true, offline: true, why: why.slice(0, 300) },
      });
      quickId = ref.id;
    }
    const waitMin = Math.min(30, 2 ** retries);
    await leadRef.set(
      {
        ...(retries === 1 ? counters : {}),
        needsHuman: retries >= 3,
        handoffReason: retries >= 3 ? "AI unavailable for a while: please reply from the desk" : "",
        lastMessageAt: FieldValue.serverTimestamp(),
        ai: {
          retries,
          lastError: why.slice(0, 300),
          retryAt: retries <= 6 ? Timestamp.fromMillis(Date.now() + waitMin * 60_000) : FieldValue.delete(),
        },
      },
      { merge: true },
    );
    await bumpStat("aiFailures");
    if (identityFromIntake) await resolveIdentity(leadId).catch(() => undefined);
    return retries === 1 ? { reply: quick, channel: msg.channel, msgId: quickId } : null;
  }
  let out: BrainOut = JSON.parse(JSON.stringify(thought.out)) as BrainOut;
  const blockedDraft = thought.blockedDraft;
  if (cacheState === "hit" || cacheState === "wait") {
    // Paranoia: a cached answer still has to pass today's Guard.
    if (!checkReply(out.reply, kb, userTexts).ok) out = { ...out, reply: t("safeFallback", out.language) };
  }
  const followup = out.next_action?.message ?? "";

  // ---- Voice note transcript (on the newest unanswered voice note) ----
  if (out.transcript) {
    const lastVoice = [...unansweredIdx].reverse().find((i) => history[i].audioB64 && !history[i].transcript);
    if (lastVoice !== undefined) await docs[lastVoice].ref.set({ transcript: out.transcript, language: out.language }, { merge: true });
  }

  // ---- Aptitude (scored here, not by the model) ----
  const apt = advance(
    lead.aptitude,
    { picked: out.aptitude?.picked, shownId: out.aptitude?.shown_id, event: out.aptitude?.event, userText: msg.text },
    { ...(lead.profile ?? {}), ...(out.profile ?? {}) },
  );
  // The prompt told the model exactly which question to ask next (NEXT_IF_CORRECT / NEXT_IF_WRONG /
  // FIRST_QUESTION). If it forgot to report shown_id, the server still knows what is on screen.
  if (apt.state.status !== "done" && apt.state.status !== "skipped" && !byId(out.aptitude?.shown_id)) {
    const p = plan(lead.aptitude, lead.profile);
    const expected = apt.scored ? (apt.scored.correct ? p.nextIfCorrect : p.nextIfWrong) : !apt.state.current && (out.aptitude?.event === "started") ? p.first : undefined;
    if (expected && !apt.state.answers.some((x) => x.id === expected.id)) {
      apt.state = { ...apt.state, status: "in_progress", current: expected.id, asked: apt.state.asked.includes(expected.id) ? apt.state.asked : [...apt.state.asked, expected.id] };
    }
  }
  if (apt.scored) await logEvent("aptitude_answer", leadId, { ...apt.scored, level: byId(apt.scored.id)?.level });
  if (apt.state.status === "done" && lead.aptitude?.status !== "done") await logEvent("aptitude_done", leadId, { result: apt.state.result, band: apt.state.band });
  // While a question is waiting for an answer it is ALWAYS shown under the reply, from the
  // server's own bank, so the text and the tap buttons can never disagree with the scoring.
  const shownQuestion = apt.state.status === "in_progress" && apt.state.current ? byId(apt.state.current) : undefined;

  // ---- Booking ----
  let replyText = stripQuiz(out.reply, shownQuestion);
  if (apt.scored && verdictConflicts(replyText, apt.scored.correct)) {
    // The model contradicted the server's scoring: the server's verdict wins.
    const q = byId(apt.scored.id);
    const right = q?.options.find((o) => o.key === q.answer);
    replyText = apt.scored.correct ? t("aptRight", out.language) : t("aptWrong", out.language, { answer: right ? `${right.key}) ${right.text}` : "" });
  }
  if (!replyText) replyText = shownQuestion ? t("aptNext", out.language) : out.reply;
  if (shownQuestion) {
    const block = out.aptitude?.question_block ?? "";
    replyText = `${replyText}\n\n${blockMatches(block, shownQuestion) ? block.trim() : plainQuestion(shownQuestion)}`;
  }
  let booking: Lead["booking"] | undefined;
  if (out.book_slot_id && out.book_slot_id !== lead.booking?.slotId) {
    booking = await bookSlot(leadId, lead, out.book_slot_id, kb, out.language).catch((e) => {
      if ((e as Error).message === "full") replyText += "\n\n" + t("slotFull", out.language);
      return undefined;
    });
    if (booking) {
      replyText += "\n\n" + t("booked", out.language, { title: booking.title, when: formatIst(booking.startAt.toDate()), url: booking.calendarUrl });
    }
  }

  // ---- "Enroll now" once a course has been recommended ----
  const enr = (lead as Lead & { enrollment?: Enrollment }).enrollment;
  const recommended = out.recommendation?.course_id || lead.recommendation?.courseId;
  const enrollOptions =
    !shownQuestion && recommended && (!enr || ["rejected", "choosing_course", "cancelled"].includes(enr.status)) && !lead.simulated && !lead.selftest && !lead.burst && !lead.seed
      ? [{ id: "enroll:yes", label: ft("enrollBtn", out.language) }]
      : [];

  // ---- Write the reply ----
  const replyRef = await leadRef.collection("messages").add({
    role: "ai",
    channel: msg.channel,
    text: replyText,
    createdAt: FieldValue.serverTimestamp(),
    meta: {
      kbRefs: out.kb_refs ?? [],
      guard: blockedDraft ? { blocked: true, draft: blockedDraft, violations: thought.violations } : { blocked: false },
      model: thought.provider,
      ...(cacheState !== "off" && cacheState !== "miss" ? { cache: cacheState } : {}),
      ...(fresh.length > 1 ? { answeredTogether: fresh.length } : {}),
      ...(shownQuestion ? { kind: "aptitude", qid: shownQuestion.id, options: shownQuestion.options.map((o) => `${o.key}) ${o.text}`) } : {}),
      ...(enrollOptions.length ? { options: enrollOptions.map((o) => o.label), choices: enrollOptions } : {}),
    },
  });
  await bumpStat("replies");
  if (fresh.length > 1) await bumpStat("batched", fresh.length - 1);

  // ---- Update the lead card (scores and next action computed on the server) ----
  const profile = { ...(lead.profile ?? {}) };
  for (const [k, v] of Object.entries(out.profile ?? {})) if (typeof v === "string" && v.trim()) profile[k] = v.trim();
  const objections = Array.from(new Set([...(lead.objections ?? []), ...(out.objections ?? [])]));
  const recommendation = out.recommendation?.course_id
    ? {
        courseId: out.recommendation.course_id,
        courseName: kb.courses.find((c) => c.id === out.recommendation!.course_id)?.name ?? out.recommendation.course_id,
        reason: out.recommendation.reason ?? "",
      }
    : lead.recommendation;
  const status = booking ? "demo_booked" : !lead.status || lead.status === "new" ? "engaged" : lead.status;

  const merged: Lead = {
    ...lead,
    profile,
    objections,
    recommendation,
    aptitude: apt.state,
    booking: booking ?? lead.booking,
    status,
    language: out.language,
    phone: lead.phone || out.phone,
    userMessages: (lead.userMessages ?? 0) + fresh.length,
    voiceNotes: (lead.voiceNotes ?? 0) + fresh.filter((m) => m.audioB64).length,
    lastInboundAt: Timestamp.fromDate(now),
    lastChannel: msg.channel,
    unansweredFollowups: 0,
    aiScore: out.intent_score,
    summary: (out.summary ?? []).slice(0, 3),
  };
  const sc = computeScore({ lead: merged, aiScore: out.intent_score, userTexts, now });
  merged.score = sc.score;
  const na = decideNextAction({
    lead: merged,
    now,
    aiMessage: followup || t("nudge", out.language),
    aiReasonHint: out.next_action?.reason_hint,
    handoff: !!out.handoff,
    handoffReason: out.handoff_reason,
  });

  const update: Record<string, unknown> = {
    ...counters,
    language: out.language,
    script: out.script,
    register: out.register,
    profile,
    objections,
    score: sc.score,
    temperature: sc.temperature,
    scoreBreakdown: sc.breakdown,
    aiScore: Math.max(0, Math.min(100, Math.round(out.intent_score ?? 0))),
    summary: (out.summary ?? []).slice(0, 3),
    suggestedMessage: out.suggested_message ?? "",
    aptitude: stripUndefined(apt.state),
    nextAction: na ?? FieldValue.delete(),
    needsHuman: !!out.handoff,
    handoffReason: out.handoff_reason ?? "",
    lastMessageAt: FieldValue.serverTimestamp(),
    status,
    guardBlocks: FieldValue.increment(blockedDraft && cacheState === "off" ? 1 : 0),
    ai: { lastAnsweredId: latestDoc.id, retries: 0, retryAt: FieldValue.delete(), lastError: FieldValue.delete() },
    recentQuestions: recentQuestions(lead, fresh, now),
  };
  if (intake && lead.onboarding) update.onboarding = { briefed: true };
  if (lead.onboarding?.courseId && !lead.recommendation && !recommendation) update.interestCourseId = lead.onboarding.courseId;
  if (recommendation) update.recommendation = recommendation;
  if (booking) update.booking = booking;

  // ---- Who is this? (writer, student, extra phones) ----
  let identityChanged = identityFromIntake;
  const newPhones: string[] = [];
  if (out.name && !lead.name) {
    update.name = out.name;
    identityChanged = true;
  }
  if (out.phone && !lead.phone) {
    update.phone = out.phone;
    newPhones.push(out.phone);
    identityChanged = true;
  }
  if (out.email && !lead.email) {
    update.email = out.email.trim().toLowerCase();
    identityChanged = true;
  }
  if (out.city && !lead.city) update.city = out.city;
  if (out.relation && out.relation !== "unknown" && out.relation !== "self" && !(lead.contacts ?? []).some((c) => c.relation === out.relation)) {
    const contacts = [...(lead.contacts ?? [])];
    if (contacts.length && contacts[0].relation === "self" && !lead.studentName) contacts[0] = { ...contacts[0], relation: out.relation };
    else contacts.push({ name: out.name ?? lead.name ?? "", phone: out.phone ?? lead.phone ?? "", relation: out.relation, channel: msg.channel });
    update.contacts = contacts;
    identityChanged = true;
  }
  if (out.student_name && !lead.studentName) {
    update.studentName = out.student_name;
    identityChanged = true;
  }
  if (out.student_phone && !lead.studentPhone) {
    update.studentPhone = out.student_phone;
    newPhones.push(out.student_phone);
    identityChanged = true;
  }
  if (newPhones.length) update.contactPhones = FieldValue.arrayUnion(...newPhones.map((p) => normalizePhone(p) ?? p));
  await leadRef.set(update, { merge: true });

  // ---- Assignment by language + hot-lead alert ----
  try {
    await assignByLanguage(leadId, { ...lead, ...merged }, out.language);
    if (sc.temperature === "hot" && !lead.hotAlerted) {
      const freshLead = (await leadRef.get()).data() as Lead;
      await hotLeadAlert(leadId, freshLead, sc.score);
      await leadRef.set({ hotAlerted: true }, { merge: true });
    }
  } catch (e) {
    console.warn("assignment/alert failed", e);
  }

  if (identityChanged) await resolveIdentity(leadId);
  return {
    reply: replyText,
    channel: msg.channel,
    msgId: replyRef.id,
    lang: out.language,
    ...(shownQuestion ? { options: shownQuestion.options.map((o) => ({ id: `apt:${o.key}`, label: `${o.key}) ${o.text}` })) } : {}),
    ...(enrollOptions.length ? { options: enrollOptions } : {}),
  };
}

const CHAT_CHANNELS = new Set(["web", "whatsapp", "telegram", "instagram"]);
const NOT_CHAT_SOURCES = new Set(["form", "googleform", "walkin", "call"]);

/**
 * The intake questions run for a brand-new chat enquiry (and until they are finished).
 * Never for sample data, self-tests, load tests, simulators, form/call/walk-in leads, or a
 * conversation someone has already replied to. Admin → Channels can switch them off.
 */
async function onboardingApplies(lead: Lead, msg: Message, history: Message[], lastReply: number): Promise<boolean> {
  if (lead.onboarding) return lead.onboarding.step !== "done";
  if (!CHAT_CHANNELS.has(msg.channel)) return false;
  if (lead.simulated || lead.selftest || lead.burst || lead.seed || lead.aiPaused) return false;
  if (lead.firstSource && NOT_CHAT_SOURCES.has(lead.firstSource)) return false;
  if (lastReply >= 0 || (lead.aptitude && lead.aptitude.status !== "not_started")) return false;
  if (history.some((m) => m.role === "user" && ((m.meta ?? {}) as Record<string, unknown>).intake)) return false;
  return (await channelConfig()).onboarding;
}

/** Turns intake answers into lead fields (who is writing, the student, contacts). */
function intakePatch(lead: Lead, st: OnboardingState, channel: string): { write: Record<string, unknown>; local: Partial<Lead>; identityChanged: boolean } {
  const write: Record<string, unknown> = { onboarding: JSON.parse(JSON.stringify(st)) };
  const local: Partial<Lead> = { onboarding: st };
  let identityChanged = false;
  const prev = lead.onboarding;
  const contacts = [...(lead.contacts ?? [])];

  if (st.relation && st.relation !== prev?.relation) {
    if (contacts.length) contacts[0] = { ...contacts[0], relation: st.relation };
    else contacts.push({ name: lead.name ?? "", phone: lead.phone ?? "", relation: st.relation, channel, isPrimary: true });
    write.contacts = contacts;
    local.contacts = contacts;
    identityChanged = true;
  }
  if (st.studentName && st.studentName !== prev?.studentName) {
    write.studentName = st.studentName;
    local.studentName = st.studentName;
    if (st.relation === "self") {
      // The typed name beats a WhatsApp/Telegram profile name ("Rahul ❤️", "Papa").
      const aliases = new Set(lead.aliases ?? []);
      if (lead.name && lead.name !== st.studentName) aliases.add(lead.name);
      write.name = st.studentName;
      write.nameLatin = latinName(st.studentName) ?? st.studentName;
      write.aliases = Array.from(aliases);
      local.name = st.studentName;
      if (contacts.length) {
        contacts[0] = { ...contacts[0], name: st.studentName };
        write.contacts = contacts;
        local.contacts = contacts;
      }
    }
    identityChanged = true;
  }
  const phones: string[] = [];
  if (st.phone && st.phone !== prev?.phone) {
    write.studentPhone = st.phone;
    local.studentPhone = st.phone;
    phones.push(st.phone);
    if (st.relation === "self" && !lead.phone) {
      write.phone = st.phone;
      local.phone = st.phone;
    }
    identityChanged = true;
  }
  if (st.email && st.email !== prev?.email) {
    if (st.relation === "self" && !lead.email) {
      write.email = st.email;
      local.email = st.email;
    } else {
      write.studentEmail = st.email;
      local.studentEmail = st.email;
    }
    identityChanged = true;
  }
  if (phones.length) write.contactPhones = FieldValue.arrayUnion(...phones);
  if (st.courseId && st.courseId !== prev?.courseId) {
    write.interestCourseId = st.courseId;
    local.interestCourseId = st.courseId;
  }
  return { write, local, identityChanged };
}

/** A 3-line card summary while the intake is still running (the AI writes it afterwards). */
function intakeSummary(lead: Lead, st: OnboardingState): string[] {
  const who = st.relation === "self" ? "Student writing" : st.relation ? `${st.relation[0].toUpperCase()}${st.relation.slice(1)} writing` : "Not told who is writing yet";
  return [
    `${who}${st.studentName ? ` · student ${st.studentName}` : ""}${st.phone || st.email ? " · contact saved" : ""}`,
    st.firstQuestion ? `First asked: "${st.firstQuestion.slice(0, 90)}"` : `New ${lead.lastChannel ?? "chat"} enquiry`,
    `Intake: answering question "${st.step}"`,
  ];
}

/** Keeps the latest 6 things this person asked, for the desk card and search. */
function recentQuestions(lead: Lead, fresh: Message[], now: Date): { text: string; at: Timestamp; channel: string }[] {
  const add = fresh
    .map((m) => ({ text: (m.transcript || m.text || "").trim(), channel: m.channel }))
    .filter((q) => q.text.length > 2 && !q.text.startsWith("[") && !q.text.startsWith("🎤"))
    .map((q) => ({ text: q.text.slice(0, 160), at: Timestamp.fromDate(now), channel: q.channel }));
  const first = lead.onboarding?.firstQuestion;
  const extra = first && !(lead.recentQuestions ?? []).some((q) => q.text === first.slice(0, 160)) ? [{ text: first.slice(0, 160), at: Timestamp.fromDate(now), channel: lead.lastChannel ?? "web" }] : [];
  return [...(lead.recentQuestions ?? []), ...extra, ...add].slice(-6);
}

function stripUndefined(s: AptitudeState): Record<string, unknown> {
  return JSON.parse(JSON.stringify(s)) as Record<string, unknown>;
}

/** Books [slotId] for the lead (moving any earlier booking) and mirrors it to Google Calendar. */
export async function bookSlot(leadId: string, lead: Lead, slotId: string, kb: KnowledgeBase, language?: string): Promise<NonNullable<Lead["booking"]>> {
  const slotRef = db.doc(`slots/${slotId}`);
  const booking = await db.runTransaction(async (tx) => {
    const s = await tx.get(slotRef);
    if (!s.exists) throw new Error("no-slot");
    const slot = s.data() as Omit<Slot, "id">;
    if (slot.booked >= slot.capacity) throw new Error("full");
    tx.update(slotRef, { booked: FieldValue.increment(1) });
    if (lead.booking?.slotId && lead.booking.slotId !== s.id) tx.update(db.doc(`slots/${lead.booking.slotId}`), { booked: FieldValue.increment(-1) });
    const start = slot.startAt.toDate();
    const url = googleCalendarUrl(`Demo class: ${slot.title}`, start, slot.durationMin, `${kb.instituteName} free demo class`, kb.address ?? kb.city);
    return {
      slotId: s.id,
      startAt: slot.startAt,
      title: slot.title,
      calendarUrl: url,
      durationMin: slot.durationMin,
      mode: slot.mode,
      reminded24: false,
      reminded1: false,
    };
  });
  let calendar: { calendarEventId?: string; calendarEventLink?: string; calendarSync: string } = { calendarSync: "off" };
  try {
    const ev = await createCalendarEvent({
      summary: `Demo: ${booking.title} — ${lead.name || "prospect"}`,
      description: [
        `Lead: ${lead.name || "(no name yet)"}${lead.phone ? ` · +91 ${lead.phone}` : ""}`,
        `Language: ${language ?? lead.language ?? "-"}`,
        `Mode: ${booking.mode}`,
        lead.recommendation ? `Recommended: ${lead.recommendation.courseName ?? lead.recommendation.courseId}` : "",
        `Booked by Asha (AI Lead Desk). Lead id: ${leadId}`,
      ]
        .filter(Boolean)
        .join("\n"),
      start: booking.startAt.toDate(),
      durationMin: booking.durationMin ?? 60,
      location: kb.address ?? kb.city,
    });
    if (ev) calendar = { calendarEventId: ev.eventId, calendarEventLink: ev.htmlLink, calendarSync: "ok" };
  } catch (e) {
    console.warn("calendar sync failed", e);
    calendar = { calendarSync: `failed: ${String((e as Error).message).slice(0, 120)}` };
  }
  const full = { ...booking, ...calendar };
  await logEvent("booking", leadId, { slotId: full.slotId, title: full.title, calendar: calendar.calendarSync });
  return full as NonNullable<Lead["booking"]>;
}
