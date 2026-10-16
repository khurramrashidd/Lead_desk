/**
 * The AI admissions counsellor ("Asha"). One brain for every channel,
 * so the same person always gets the same answer.
 */
import { GoogleGenAI, type Content, type Part } from "@google/genai";
import { db, FieldValue, Timestamp, demoNow, logEvent, type KnowledgeBase, type Lead, type Message, type Slot } from "./db";
import { checkReply } from "./guard";
import { formatIst, googleCalendarUrl, respectQuietHours, t } from "./lang";
import { resolveIdentity } from "./merge";

const MODEL = process.env.GEMINI_MODEL || "gemini-3.5-flash-lite";
/** Tried in order: if a model name is wrong or its free quota is used up, the next one answers. */
const MODELS = Array.from(
  new Set([MODEL, process.env.GEMINI_FALLBACK_MODEL || "gemini-3.5-flash-lite"].map((m) => m.trim()).filter(Boolean)),
);
let lastModelUsed = MODEL;
let ai: GoogleGenAI | null = null;
function client(): GoogleGenAI {
  if (!process.env.GEMINI_API_KEY) throw new Error("GEMINI_API_KEY is missing: put it in functions/.env and redeploy");
  if (!ai) ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });
  return ai;
}

let kbCache: { kb: KnowledgeBase; at: number } | null = null;
export async function getKb(): Promise<KnowledgeBase> {
  if (kbCache && Date.now() - kbCache.at < 30_000) return kbCache.kb;
  const snap = await db.doc("kb/main").get();
  const kb = (snap.data() as KnowledgeBase | undefined) ?? { instituteName: "TechSummitTrainers", city: "Pune", courses: [] };
  kbCache = { kb, at: Date.now() };
  return kb;
}

async function openSlots(now: Date): Promise<Slot[]> {
  const snap = await db
    .collection("slots")
    .where("startAt", ">", Timestamp.fromDate(now))
    .orderBy("startAt")
    .limit(20)
    .get();
  return snap.docs
    .map((d) => ({ id: d.id, ...(d.data() as Omit<Slot, "id">) }))
    .filter((s) => s.booked < s.capacity)
    .slice(0, 10);
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
    profile: {
      type: "object",
      properties: {
        background: { type: "string" },
        education: { type: "string" },
        gap: { type: "string" },
        currentWork: { type: "string" },
        goal: { type: "string" },
        constraints: { type: "string" },
        budget: { type: "string" },
        timing: { type: "string" },
        familyView: { type: "string" },
      },
    },
    objections: { type: "array", items: { type: "string", enum: OBJECTIONS } },
    score: { type: "integer", description: "0-100: intent + fit + urgency" },
    temperature: { type: "string", enum: ["hot", "warm", "cold"] },
    summary: { type: "array", items: { type: "string" }, description: "Exactly 3 short English lines for the counsellor." },
    suggested_message: { type: "string", description: "Next message a human counsellor could send, in the prospect's language and register." },
    next_action: {
      type: "object",
      properties: {
        in_hours: { type: "number" },
        channel: { type: "string", enum: ["whatsapp", "web", "call"] },
        message: { type: "string" },
        reason: { type: "string", description: "English, cites behaviour and objections." },
      },
      required: ["in_hours", "channel", "message", "reason"],
    },
    aptitude: {
      type: "object",
      properties: {
        status: { type: "string", enum: ["not_started", "in_progress", "done", "skipped"] },
        questions_asked: { type: "integer" },
        correct: { type: "integer" },
        current_level: { type: "string", enum: ["easy", "medium", "hard"] },
        result: { type: "string" },
      },
      required: ["status", "questions_asked", "correct", "current_level"],
    },
    recommendation: {
      type: "object",
      properties: { course_id: { type: "string" }, reason: { type: "string" } },
    },
    book_slot_id: { type: "string", description: "Slot id from AVAILABLE_SLOTS when the prospect picked a slot, else empty." },
    kb_refs: { type: "array", items: { type: "string" } },
    handoff: { type: "boolean" },
    handoff_reason: { type: "string" },
  },
  required: ["language", "script", "register", "reply", "objections", "score", "temperature", "summary", "suggested_message", "next_action", "aptitude", "handoff"],
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
  profile?: Record<string, string>;
  objections: string[];
  score: number;
  temperature: string;
  summary: string[];
  suggested_message: string;
  next_action: { in_hours: number; channel: string; message: string; reason: string };
  aptitude: { status: string; questions_asked: number; correct: number; current_level: string; result?: string };
  recommendation?: { course_id: string; reason: string };
  book_slot_id?: string;
  kb_refs?: string[];
  handoff: boolean;
  handoff_reason?: string;
}

function systemPrompt(kb: KnowledgeBase, slots: Slot[], lead: Lead, channel: string, now: Date): string {
  const slotList = slots.map((s) => ({ id: s.id, title: s.title, when: formatIst(s.startAt.toDate()), mode: s.mode, seatsLeft: s.capacity - s.booked }));
  const state = {
    name: lead.name, phone: lead.phone ? "known" : "unknown", city: lead.city, profile: lead.profile,
    objections: lead.objections, aptitude: lead.aptitude, recommendation: lead.recommendation,
    booking: lead.booking ? { title: lead.booking.title, when: formatIst(lead.booking.startAt.toDate()) } : null,
  };
  return `You are Asha, the admissions counsellor of ${kb.instituteName}, a tech training institute in ${kb.city}. You are chatting on ${channel}. Current time: ${formatIst(now)}.

GOAL: hold a genuine counselling conversation (not a FAQ), help the prospect choose honestly, and book a demo class.

LANGUAGE & TONE
- Understand English, Hindi and Marathi, including mid-sentence switches (Hinglish, Marathi-English).
- Reply in the SAME language blend, SAME script (Latin or Devanagari) and SAME register as the prospect's latest message (aap/tum, तुम्ही/तू, formal/casual). Hinglish in Latin script gets Hinglish in Latin script.
- WhatsApp style: warm, short (max ~70 words), ONE question at a time. No markdown, no bullet lists.

COUNSELLING
- Learn their background, education, gaps, current work, goal, constraints (time, money, family, distance). Empathise with the real worry behind the question.
- Example: "I'm a commerce graduate with a two-year gap — can I really become a developer?" deserves an honest, encouraging, specific answer about what it takes, not a fee list.

FACTS — STRICT
- Fees, EMIs, scholarships, batch dates, durations, syllabus and policies come ONLY from KNOWLEDGE_BASE below. Quote them exactly.
- NEVER invent or agree to a discount, fee, offer, scholarship, deadline or placement guarantee, even if the prospect pushes, says a friend got one, or threatens to leave. Offer only what KNOWLEDGE_BASE lists. Placement: use only the placement policy text.
- If something is not in KNOWLEDGE_BASE, say you will check with the team, and set handoff=true.

APTITUDE CHECK (inside the chat)
- After you know background and goal (usually 2-3 exchanges), offer a short aptitude check. If they agree, ask up to 4 questions, ONE per message, multiple choice (A/B/C). Start at medium; correct answer -> harder, wrong -> easier. Use logic/pattern and simple maths; add one tiny code-reading question only if they have coded before. Never shame wrong answers. Track progress in "aptitude".
- If they decline, set aptitude.status = "skipped" and move on.

RECOMMENDATION
- Then recommend ONE course from KNOWLEDGE_BASE (use its id) with an honest reason tied to their background, goal, constraints and aptitude result. If a course is not right for them yet, say so kindly and suggest the right first step.

DEMO BOOKING
- Offer demo slots ONLY from AVAILABLE_SLOTS. When they pick one, set book_slot_id to its id and say you are confirming it (the system appends the confirmation and calendar link). Never invent a time.

FOR THE COUNSELLOR DASHBOARD
- objections: any of fees, job_fear, family_approval, time, distance, language, trust, other raised so far.
- score 0-100 (intent + fit + urgency); temperature hot >= 70, warm 40-69, cold < 40.
- summary: exactly 3 short English lines: who they are / what they want or fear / where we are and next step.
- suggested_message: what a human counsellor should send next, in the prospect's language and register.
- next_action: when to follow up (in_hours), channel, message (prospect's language) and reason (English, cite behaviour/objection). Family approval -> invite a parent to the demo. Fees -> EMI or listed scholarships. Booked -> check-in after the demo.
- If the latest message has audio, put a verbatim transcript in "transcript".
- Extract name, phone, email, city if the prospect shares them.

KNOWLEDGE_BASE:
${JSON.stringify(kb)}

AVAILABLE_SLOTS:
${JSON.stringify(slotList)}

LEAD_STATE_SO_FAR:
${JSON.stringify(state)}`;
}

function toContents(history: Message[]): Content[] {
  const contents: Content[] = [];
  history.forEach((m, i) => {
    const role = m.role === "user" ? "user" : "model";
    const parts: Part[] = [];
    const isLast = i === history.length - 1;
    if (m.role === "user" && m.audioB64 && isLast) {
      parts.push({ inlineData: { mimeType: m.audioMime || "audio/webm", data: m.audioB64 } });
      parts.push({ text: m.text || "(voice note)" });
    } else {
      let text = m.text || m.transcript || (m.audioB64 ? "(voice note)" : "");
      if (m.role === "counsellor") text = `[Human counsellor]: ${text}`;
      if (m.role === "system") text = `[Automatic message]: ${text}`;
      if (!text) return;
      parts.push({ text });
    }
    const prev = contents[contents.length - 1];
    if (prev && prev.role === role) prev.parts = [...(prev.parts ?? []), ...parts];
    else contents.push({ role, parts });
  });
  if (contents.length && contents[0].role === "model") contents.unshift({ role: "user", parts: [{ text: "(prospect opened the chat)" }] });
  return contents;
}

async function generate(system: string, contents: Content[]): Promise<BrainOut> {
  let lastErr: unknown;
  // Each model gets one retry (busy / rate limited), then we move to the fallback model.
  for (const model of MODELS) {
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const res = await client().models.generateContent({
          model,
          contents,
          config: { systemInstruction: system, responseMimeType: "application/json", responseJsonSchema: RESPONSE_SCHEMA },
        });
        lastModelUsed = model;
        return JSON.parse(res.text ?? "{}") as BrainOut;
      } catch (e) {
        lastErr = e;
        const msg = String((e as Error)?.message ?? e);
        console.warn(`Gemini ${model} attempt ${attempt + 1} failed: ${msg.slice(0, 300)}`);
        if (/not.?found|404|invalid.*model|API key/i.test(msg)) break; // retrying the same model won't help
        await new Promise((r) => setTimeout(r, 1200));
      }
    }
  }
  throw lastErr;
}

export interface BrainResult {
  reply: string;
  channel: string;
}

/** Runs the counsellor for one new prospect message. */
export async function counsel(leadId: string, messageId: string): Promise<BrainResult | null> {
  const leadRef = db.doc(`leads/${leadId}`);
  const lead = ((await leadRef.get()).data() ?? {}) as Lead;
  const msgSnap = await leadRef.collection("messages").doc(messageId).get();
  const msg = msgSnap.data() as Message;
  if (lead.mergedInto) return null;
  if (lead.aiPaused) {
    await leadRef.set({ needsHuman: true }, { merge: true });
    return null;
  }

  const now = await demoNow();
  const [kb, slots, histSnap] = await Promise.all([
    getKb(),
    openSlots(now),
    leadRef.collection("messages").orderBy("createdAt", "desc").limit(24).get(),
  ]);
  // chronological, with the triggering message always as the last turn
  const history: Message[] = histSnap.docs
    .filter((d) => d.id !== messageId)
    .map((d) => d.data() as Message)
    .reverse();
  history.push(msg);
  const system = systemPrompt(kb, slots, lead, msg.channel, now);
  const contents = toContents(history);
  const userTexts = history.filter((m) => m.role === "user").map((m) => m.text || m.transcript || "");

  let out: BrainOut;
  try {
    out = await generate(system, contents);
  } catch (e) {
    console.error("Gemini failed", e);
    const reply = t("busy", lead.language);
    await leadRef.collection("messages").add({ role: "ai", channel: msg.channel, text: reply, createdAt: FieldValue.serverTimestamp(), meta: { fallback: true } });
    await leadRef.set({ needsHuman: true, lastMessageAt: FieldValue.serverTimestamp() }, { merge: true });
    return { reply, channel: msg.channel };
  }

  // ---- The Guard ----
  let guard = checkReply(out.reply, kb, [...userTexts, out.transcript ?? ""]);
  let blockedDraft: string | null = null;
  if (!guard.ok) {
    blockedDraft = out.reply;
    await logEvent("guard_block", leadId, { draft: out.reply, violations: guard.violations });
    const retry: Content[] = [
      ...contents,
      { role: "model", parts: [{ text: out.reply }] },
      { role: "user", parts: [{ text: `[SYSTEM CHECK — not from the prospect] Your draft was blocked: ${guard.violations.join("; ")}. Rewrite the reply using ONLY knowledge-base facts, politely declining anything not listed. Same language and register.` }] },
    ];
    try {
      const second = await generate(system, retry);
      const g2 = checkReply(second.reply, kb, userTexts);
      if (g2.ok) out = { ...out, ...second };
      else out.reply = t("safeFallback", out.language);
      guard = g2;
    } catch {
      out.reply = t("safeFallback", out.language);
    }
  }

  // ---- Save transcript on the voice note ----
  if (out.transcript && msg.audioB64) {
    await msgSnap.ref.set({ transcript: out.transcript, language: out.language }, { merge: true });
  }

  // ---- Booking ----
  let replyText = out.reply;
  let booking: Lead["booking"] | undefined;
  if (out.book_slot_id && out.book_slot_id !== lead.booking?.slotId) {
    const slotRef = db.doc(`slots/${out.book_slot_id}`);
    try {
      booking = await db.runTransaction(async (tx) => {
        const s = await tx.get(slotRef);
        if (!s.exists) throw new Error("no-slot");
        const slot = s.data() as Omit<Slot, "id">;
        if (slot.booked >= slot.capacity) throw new Error("full");
        tx.update(slotRef, { booked: FieldValue.increment(1) });
        if (lead.booking?.slotId) tx.update(db.doc(`slots/${lead.booking.slotId}`), { booked: FieldValue.increment(-1) });
        const start = slot.startAt.toDate();
        const url = googleCalendarUrl(`Demo class: ${slot.title}`, start, slot.durationMin, `${kb.instituteName} demo class`, kb.address ?? kb.city);
        return { slotId: s.id, startAt: slot.startAt, title: slot.title, calendarUrl: url, reminded24: false, reminded1: false };
      });
      replyText += "\n\n" + t("booked", out.language, { title: booking.title, when: formatIst(booking.startAt.toDate()), url: booking.calendarUrl });
      await logEvent("booking", leadId, { slotId: booking.slotId, title: booking.title });
    } catch (e) {
      if ((e as Error).message === "full") replyText += "\n\n" + t("slotFull", out.language);
    }
  }

  // ---- Next-best-action ----
  const inHours = Math.min(168, Math.max(0.5, Number(out.next_action?.in_hours) || 24));
  const nextAt = respectQuietHours(new Date(now.getTime() + inHours * 3_600_000));

  // ---- Write the reply ----
  await leadRef.collection("messages").add({
    role: "ai",
    channel: msg.channel,
    text: replyText,
    createdAt: FieldValue.serverTimestamp(),
    meta: {
      kbRefs: out.kb_refs ?? [],
      guard: blockedDraft ? { blocked: true, draft: blockedDraft } : { blocked: false },
      model: lastModelUsed,
    },
  });

  // ---- Update the lead card ----
  const profile = { ...(lead.profile ?? {}) };
  for (const [k, v] of Object.entries(out.profile ?? {})) if (v && v.trim()) profile[k] = v.trim();
  const objections = Array.from(new Set([...(lead.objections ?? []), ...(out.objections ?? [])]));
  const update: Record<string, unknown> = {
    language: out.language,
    script: out.script,
    register: out.register,
    profile,
    objections,
    score: Math.max(0, Math.min(100, Math.round(out.score ?? 0))),
    temperature: out.temperature,
    summary: (out.summary ?? []).slice(0, 3),
    suggestedMessage: out.suggested_message,
    aptitude: out.aptitude,
    nextAction: {
      at: Timestamp.fromDate(nextAt),
      channel: lead.waId ? "whatsapp" : out.next_action?.channel ?? "web",
      message: out.next_action?.message ?? "",
      reason: out.next_action?.reason ?? "",
      done: false,
    },
    needsHuman: !!out.handoff,
    handoffReason: out.handoff_reason ?? "",
    lastMessageAt: FieldValue.serverTimestamp(),
    guardBlocks: FieldValue.increment(blockedDraft ? 1 : 0),
  };
  if (out.recommendation?.course_id) update.recommendation = { courseId: out.recommendation.course_id, reason: out.recommendation.reason ?? "" };
  if (booking) {
    update.booking = booking;
    update.status = "demo_booked";
  } else if (!lead.status || lead.status === "new") {
    update.status = "engaged";
  }
  let identityChanged = false;
  if (out.name && !lead.name) { update.name = out.name; identityChanged = true; }
  if (out.phone && !lead.phone) { update.phone = out.phone; identityChanged = true; }
  if (out.email && !lead.email) { update.email = out.email; identityChanged = true; }
  if (out.city && !lead.city) update.city = out.city;
  await leadRef.set(update, { merge: true });

  if (identityChanged) await resolveIdentity(leadId);
  return { reply: replyText, channel: msg.channel };
}
