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
import { formatIst, googleCalendarUrl, normaliseQuestion, t } from "./lang";
import { resolveIdentity } from "./merge";
import { advance, byId, formatQuestion, plan } from "./aptitude";
import { computeScore } from "./scoring";
import { decideNextAction } from "./nba";
import { createCalendarEvent } from "./calendar";
import { assignByLanguage, hotLeadAlert } from "./assign";
import { deliverOn } from "./channels";
import { normalizePhone } from "./identity";
import { bumpStat } from "./stats";
import { singleFlight } from "./cache";

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
  aptitude: { event: string; picked?: string; shown_id?: string };
  recommendation?: { course_id: string; reason: string };
  book_slot_id?: string;
  kb_refs?: string[];
  handoff: boolean;
  handoff_reason?: string;
}

function aptitudeBlock(lead: Lead): string {
  const p = plan(lead.aptitude, lead.profile);
  const s = p.state;
  const lines: string[] = [`status: ${s.status}, answered ${s.answers.length}/4, correct ${s.correct}`];
  if (s.status === "done") {
    lines.push(`RESULT (already shared): ${s.result}. Use it for the recommendation; do not run the check again.`);
  } else if (s.status === "skipped") {
    lines.push("They declined the check. Do not offer it again unless they ask.");
  } else if (!p.current) {
    lines.push(
      "When you know their background and goal (usually after 2-3 exchanges) and they have not declined, OFFER a quick 4-question aptitude check (about 2 minutes) and set aptitude.event=\"offered\".",
      "If the prospect agrees in their latest message, ask exactly FIRST_QUESTION now, set aptitude.event=\"started\" and aptitude.shown_id to its id.",
      `FIRST_QUESTION: ${formatQuestion(p.first)}`,
    );
  } else {
    lines.push(
      `CURRENT_QUESTION (waiting for their answer): ${formatQuestion(p.current)} — correct answer: ${p.current.answer}`,
      "If their latest message answers it: set aptitude.event=\"answered\" and aptitude.picked to the letter they chose (A/B/C; map an option's text or number to its letter).",
      "React in a few words: if right, praise briefly; if wrong, kindly give the right answer with a one-line why. Never shame.",
    );
    if (p.finishesAfterThis) {
      lines.push(
        "This was the LAST question. After reacting, share the result in their language:",
        `  if their answer is right → ${p.resultIfCorrect}`,
        `  if their answer is wrong → ${p.resultIfWrong}`,
        "then move on to your honest course recommendation. Set aptitude.shown_id to empty.",
      );
    } else {
      lines.push(
        `Then ask the next question: if right → NEXT_IF_CORRECT, if wrong → NEXT_IF_WRONG, and set aptitude.shown_id to the id you asked.`,
        `NEXT_IF_CORRECT: ${formatQuestion(p.nextIfCorrect)}`,
        `NEXT_IF_WRONG: ${formatQuestion(p.nextIfWrong)}`,
      );
    }
    lines.push("If they want to stop, set aptitude.event=\"skipped\". If they ask something else first, answer briefly and repeat CURRENT_QUESTION (shown_id = its id).");
  }
  lines.push("Present a question as the question on one line, then each option on its own line as \"A) …\", \"B) …\", \"C) …\", translated into their language with numbers kept as digits.");
  return lines.join("\n");
}

function leadState(lead: Lead): Record<string, unknown> {
  return {
    name: lead.name,
    phoneKnown: !!lead.phone,
    city: lead.city,
    relation: lead.contacts?.[0]?.relation,
    studentName: lead.studentName,
    profile: lead.profile,
    objections: lead.objections,
    recommendation: lead.recommendation,
    booking: lead.booking ? { title: lead.booking.title, when: formatIst(lead.booking.startAt.toDate()) } : null,
    channelsUsed: lead.sources,
  };
}

function systemPrompt(kb: KnowledgeBase, slots: Slot[], lead: Lead, channel: string, now: Date): string {
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
${aptitudeBlock(lead)}

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

LEAD_STATE_SO_FAR:
${JSON.stringify(state)}`;
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
  reply: string;
  channel: string;
}

// ------------------------------------------------------------------ answer cache
// The same first question from thousands of different people ("Full Stack Java ki fees kitni
// hai?", "hi") is answered by the AI ONCE; everyone else gets that answer in milliseconds.
// The key includes everything the model saw (question, channel, lead state, knowledge-base
// version, open slots), so a cached answer is exactly what the model would have said.
// If 1,000 identical questions arrive in the same second, one worker asks the AI and the rest
// wait for its answer (single-flight), instead of 1,000 AI calls.
const PROMPT_VERSION = "v8";

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
    if (["whatsapp", "telegram", "instagram"].includes(r.channel)) await deliverOn(r.channel, lead, r.reply);
  }
  return results.length;
}

/** Answers every prospect message that has not been answered yet, in one reply. */
export async function counsel(leadId: string): Promise<BrainResult | null> {
  const leadRef = db.doc(`leads/${leadId}`);
  const lead = ((await leadRef.get()).data() ?? {}) as Lead;
  if (lead.mergedInto) return null;

  const now = await demoNow();
  const [kb, slots, histSnap] = await Promise.all([
    getKb(),
    openSlots(now),
    leadRef.collection("messages").orderBy("createdAt", "desc").limit(24).get(),
  ]);
  const docs = histSnap.docs.slice().reverse();
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

  const system = systemPrompt(kb, slots, lead, msg.channel, now);
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
        JSON.stringify([PROMPT_VERSION, msg.channel, kbVersion, slots.slice(0, 5).map((s) => s.id), leadState(lead), lead.aptitude?.status ?? "", normaliseQuestion(text)]),
      );
      const r = await singleFlight<Thought>(key, () => think(leadId, system, turns, kb, userTexts), (v) => !v.out.book_slot_id && !v.out.handoff);
      thought = r.value;
      cacheState = r.state;
      if (r.state !== "miss") await bumpStat(r.state === "hit" ? "cacheHits" : "cacheWaits");
    } else {
      thought = await think(leadId, system, turns, kb, userTexts);
    }
  } catch (e) {
    console.error("AI failed", e);
    // Never lost: an instant acknowledgement once, then automatic retries with back-off.
    const retries = (lead.ai?.retries ?? 0) + 1;
    if (retries === 1) {
      await leadRef.collection("messages").add({ role: "ai", channel: msg.channel, text: t("busy", lead.language), createdAt: FieldValue.serverTimestamp(), meta: { fallback: true } });
    }
    const waitMin = Math.min(30, 2 ** retries);
    await leadRef.set(
      {
        needsHuman: retries >= 3,
        handoffReason: retries >= 3 ? "AI busy for a while: please reply from the desk" : "",
        lastMessageAt: FieldValue.serverTimestamp(),
        ai: retries <= 6 ? { retries, retryAt: Timestamp.fromMillis(Date.now() + waitMin * 60_000) } : { retries, retryAt: FieldValue.delete() },
      },
      { merge: true },
    );
    await bumpStat("aiFailures");
    return retries === 1 ? { reply: t("busy", lead.language), channel: msg.channel } : null;
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
  if (apt.scored) await logEvent("aptitude_answer", leadId, { ...apt.scored, level: byId(apt.scored.id)?.level });
  if (apt.state.status === "done" && lead.aptitude?.status !== "done") await logEvent("aptitude_done", leadId, { result: apt.state.result, band: apt.state.band });
  const shownQuestion = apt.state.current && apt.state.current !== lead.aptitude?.current ? byId(apt.state.current) : undefined;

  // ---- Booking ----
  let replyText = out.reply;
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

  // ---- Write the reply ----
  await leadRef.collection("messages").add({
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
    ai: { lastAnsweredId: latestDoc.id, retries: 0, retryAt: FieldValue.delete() },
  };
  if (recommendation) update.recommendation = recommendation;
  if (booking) update.booking = booking;

  // ---- Who is this? (writer, student, extra phones) ----
  let identityChanged = false;
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
  return { reply: replyText, channel: msg.channel };
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
