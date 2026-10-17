/**
 * Conversation rules that run BEFORE Asha's AI, without any AI call:
 *
 *   Sessions   every chat starts by choosing a language (English / हिंदी / मराठी); a chat with no
 *              reply for 2 minutes after Asha's last message is closed ("send any message to start
 *              again"); "restart" (or /start, or the Restart button on the website) starts fresh.
 *   Enrolment  "Enroll now" (button shown after a course recommendation) → the admin's UPI QR for
 *              the registration fee → the student sends a photo of the receipt → thank-you, chat
 *              closed → an admin verifies it and allots the course (api verifyEnrollment).
 */
import { db, FieldValue, Timestamp, logEvent, type KnowledgeBase, type Lead, type Message } from "./db";
import type { ObOption } from "./onboarding";
import {
  askFor,
  bothModes,
  checkOtp,
  confirmOptions,
  defaultsFrom,
  editOptions,
  FIELDS,
  GROUPS,
  groupFromText,
  isCancel,
  isConfirm,
  isEdit,
  nextAdmissionId,
  sendOtp,
  summaryText,
  tt,
  validate,
  type Field,
  type FormState,
} from "./enroll_form";

export type Lang = "en" | "hi" | "mr";

export interface ChatSession {
  status?: "new" | "active" | "closed";
  lang?: Lang;
  startedAt?: Timestamp;
  awaitingLang?: boolean;
  /** The message the language question was asked for (so a duplicate run does not answer it early). */
  promptedFor?: string;
  expiresAt?: Timestamp;
  closedAt?: Timestamp;
  closedReason?: string;
}

export interface Enrollment extends FormState {
  status: "form" | "confirm" | "otp" | "cancelled" | "choosing_course" | "awaiting_details" | "awaiting_receipt" | "receipt_received" | "verified" | "rejected";
  courseId?: string;
  courseName?: string;
  amount?: number;
  upiId?: string;
  payee?: string;
  startedAt?: Timestamp;
  receiptMsgId?: string;
  receiptAt?: Timestamp;
  verifiedBy?: string;
  verifiedAt?: Timestamp;
  note?: string;
}

export const SESSION_CHANNELS = new Set(["web", "whatsapp", "telegram", "instagram"]);
/** Closed this long after Asha's last reply when the prospect does not answer. */
export const IDLE_MS = 2 * 60_000;
/** Paying takes longer: while a receipt is awaited the chat stays open this long. */
export const RECEIPT_IDLE_MS = 15 * 60_000;
/** Filling the enrolment form (address, email code…) takes longer too. */
export const FORM_IDLE_MS = 10 * 60_000;
const FORM_STATES = ["form", "confirm", "otp"];
/** Images are stored inline on the message, so they must stay well under Firestore's 1 MB. */
export const MAX_IMAGE_BYTES = 700_000;

const TXT: Record<string, Record<Lang, string>> = {
  pickLang: {
    en: "Hi! 👋 Please choose your language.\nनमस्ते! अपनी भाषा चुनें।\nनमस्कार! तुमची भाषा निवडा.",
    hi: "Hi! 👋 Please choose your language.\nनमस्ते! अपनी भाषा चुनें।\nनमस्कार! तुमची भाषा निवडा.",
    mr: "Hi! 👋 Please choose your language.\nनमस्ते! अपनी भाषा चुनें।\nनमस्कार! तुमची भाषा निवडा.",
  },
  closed: {
    en: "⏳ This chat was closed because there was no reply for 2 minutes. Send any message to start again.",
    hi: "⏳ 2 मिनट तक कोई जवाब न आने से यह चैट बंद हो गई है। फिर से शुरू करने के लिए कोई भी मैसेज भेजें।",
    mr: "⏳ 2 मिनिटं उत्तर न आल्याने ही चॅट बंद झाली आहे. पुन्हा सुरू करण्यासाठी कोणताही मेसेज पाठवा.",
  },
  enrollBtn: { en: "✅ Enroll now", hi: "✅ अभी एनरोल करें", mr: "✅ आत्ता प्रवेश घ्या" },
  pickCourse: {
    en: "Great! Which course would you like to enroll in?",
    hi: "बढ़िया! आप किस कोर्स में एनरोल करना चाहते हैं?",
    mr: "छान! तुम्हाला कोणत्या कोर्सला प्रवेश घ्यायचा आहे?",
  },
  pay: {
    en: "Great choice! 🎓 To reserve your seat in {course}, please pay the registration fee of ₹{amount}.\n\nUPI ID: {upi}\nName: {payee}\n\nScan the QR code with any UPI app (GPay, PhonePe, Paytm), then send a photo or screenshot of the payment receipt here.",
    hi: "बढ़िया चुनाव! 🎓 {course} में अपनी सीट पक्की करने के लिए ₹{amount} रजिस्ट्रेशन फीस भरें।\n\nUPI ID: {upi}\nनाम: {payee}\n\nकिसी भी UPI ऐप (GPay, PhonePe, Paytm) से QR कोड स्कैन करें, फिर पेमेंट रसीद की फोटो या स्क्रीनशॉट यहीं भेजें।",
    mr: "छान निवड! 🎓 {course} मधली तुमची जागा पक्की करण्यासाठी ₹{amount} नोंदणी फी भरा.\n\nUPI ID: {upi}\nनाव: {payee}\n\nकोणत्याही UPI ॲपने (GPay, PhonePe, Paytm) QR कोड स्कॅन करा, मग पेमेंटच्या पावतीचा फोटो किंवा स्क्रीनशॉट इथेच पाठवा.",
  },
  noUpi: {
    en: "Great choice! 🎓 Our counsellor will share the payment details with you shortly.",
    hi: "बढ़िया चुनाव! 🎓 हमारे काउंसलर जल्द ही आपको पेमेंट की जानकारी भेजेंगे।",
    mr: "छान निवड! 🎓 आमचे काउन्सेलर लवकरच तुम्हाला पेमेंटची माहिती पाठवतील.",
  },
  sendReceipt: {
    en: "Thanks! Please send a photo or screenshot of the payment receipt here so we can confirm it.",
    hi: "धन्यवाद! कन्फर्म करने के लिए पेमेंट रसीद की फोटो या स्क्रीनशॉट यहीं भेजें।",
    mr: "धन्यवाद! कन्फर्म करण्यासाठी पेमेंटच्या पावतीचा फोटो किंवा स्क्रीनशॉट इथेच पाठवा.",
  },
  thanks: {
    en: "🙏 Thank you! We have received your payment receipt. You will get a confirmation within 24 hours.\n\nThis chat is now closed. Send any message to start a new one.",
    hi: "🙏 धन्यवाद! आपकी पेमेंट रसीद मिल गई है। 24 घंटे के अंदर आपको कन्फर्मेशन मिल जाएगा।\n\nयह चैट अब बंद है। नई चैट शुरू करने के लिए कोई भी मैसेज भेजें।",
    mr: "🙏 धन्यवाद! तुमची पेमेंट पावती मिळाली आहे. 24 तासांच्या आत तुम्हाला कन्फर्मेशन मिळेल.\n\nही चॅट आता बंद आहे. नवीन चॅट सुरू करण्यासाठी कोणताही मेसेज पाठवा.",
  },
  verified: {
    en: "🎉 Your payment of ₹{amount} is verified. You are enrolled in {course}! Our team will share the batch details with you soon.",
    hi: "🎉 आपका ₹{amount} का पेमेंट वेरिफाई हो गया। आप {course} में एनरोल हो गए हैं! हमारी टीम जल्द ही बैच की जानकारी भेजेगी।",
    mr: "🎉 तुमचं ₹{amount} चं पेमेंट व्हेरिफाय झालं. तुमचा {course} मध्ये प्रवेश निश्चित झाला! आमची टीम लवकरच बॅचची माहिती पाठवेल.",
  },
  rejected: {
    en: "We could not verify your payment receipt yet. Our counsellor will contact you shortly to help.",
    hi: "हम अभी आपकी पेमेंट रसीद वेरिफाई नहीं कर पाए। हमारे काउंसलर जल्द ही आपसे संपर्क करेंगे।",
    mr: "आम्ही अजून तुमची पेमेंट पावती व्हेरिफाय करू शकलो नाही. आमचे काउन्सेलर लवकरच तुमच्याशी संपर्क करतील.",
  },
};

export function ft(key: keyof typeof TXT, lang: string | undefined, vars: Record<string, string | number> = {}): string {
  const l: Lang = lang === "hi" || lang === "mr" ? lang : lang === "hinglish" ? "hi" : lang === "marathi-english" ? "mr" : "en";
  let s = TXT[key][l];
  for (const [k, v] of Object.entries(vars)) s = s.split(`{${k}}`).join(String(v));
  return s;
}

export const LANG_OPTIONS: ObOption[] = [
  { id: "lang:en", label: "English" },
  { id: "lang:hi", label: "हिंदी" },
  { id: "lang:mr", label: "मराठी" },
];

/** "restart", "/start", "start again", "फिर से शुरू", "पुन्हा सुरू" … */
export function isRestart(text: string): boolean {
  const t = text.trim().toLowerCase();
  return /^\/?(restart|reset|start again|start over|new chat|start)$/.test(t) || /^(फिर से शुरू|दोबारा शुरू|रीस्टार्ट|पुन्हा सुरू|परत सुरू)/.test(t);
}

export function parseLang(text: string, choiceId?: string): Lang | undefined {
  if (choiceId?.startsWith("lang:")) {
    const l = choiceId.slice(5);
    if (l === "en" || l === "hi" || l === "mr") return l;
  }
  const t = text.trim().toLowerCase();
  if (/^(1|en|eng|english|इंग्लिश|इंग्रजी)$/.test(t)) return "en";
  if (/^(2|hi|hindi|हिंदी|हिन्दी)$/.test(t)) return "hi";
  if (/^(3|mr|marathi|मराठी)$/.test(t)) return "mr";
  return undefined;
}

export function guessLang(text: string, hint?: string): Lang {
  if (/[ऀ-ॿ]/.test(text)) return hint === "mr" || /(आहे|मला|तुम्ही|काय|नाही)/.test(text) ? "mr" : "hi";
  if (/\b(kya|hai|kitni|mujhe|chahiye|aap)\b/i.test(text)) return "hi";
  if (/\b(aahe|mala|kay|tumhi|pahije)\b/i.test(text)) return "mr";
  return "en";
}

export function looksLikeEnroll(text: string, choiceId?: string): boolean {
  if (choiceId === "enroll:yes") return true;
  const t = text.trim().toLowerCase();
  return (
    /^(✅\s*)?(enrol+|enrol+ now|i want to enrol+|enrol+ me|join now|i want to join|admission)$/.test(t) ||
    /^✅\s*(अभी एनरोल करें|आत्ता प्रवेश घ्या)$/.test(text.trim()) ||
    /\b(enrol+ (now|me)|want to enrol+|admission (lena|chahiye|confirm)|join karna hai)\b/.test(t)
  );
}

export function looksLikePaid(text: string): boolean {
  return /\b(paid|payment (done|kiya|ho gaya|kar diya)|done|transferred|bhej diya|sent|pay kiya)\b/i.test(text) || /(भेज दिया|कर दिया|भरले|भरला|पाठवले)/.test(text);
}

export interface PaymentConfig {
  upiId: string;
  payee: string;
  amount: number;
}

/** Admin → Overview → Enrollment payments (config/public.payment). Default fee ₹10 for demos. */
export async function paymentConfig(): Promise<PaymentConfig> {
  const p = ((await db.doc("config/public").get()).get("payment") ?? {}) as Partial<PaymentConfig>;
  const amount = Math.round(Number(p.amount ?? 10));
  return { upiId: String(p.upiId ?? "").trim(), payee: String(p.payee ?? "").trim() || "Admissions", amount: amount > 0 ? amount : 10 };
}

export function upiLink(cfg: PaymentConfig, note: string): string {
  const q = new URLSearchParams({ pa: cfg.upiId, pn: cfg.payee, am: cfg.amount.toFixed(2), cu: "INR", tn: note.slice(0, 50) });
  return `upi://pay?${q.toString().replace(/\+/g, "%20")}`;
}

export async function qrPng(text: string): Promise<Buffer> {
  const QR = await import("qrcode");
  return QR.toBuffer(text, { type: "png", width: 640, margin: 2, errorCorrectionLevel: "M" });
}

/** What the gate decided. */
export interface GateResult {
  /** Reply to send (already stored on the lead). */
  reply?: { text: string; channel: string; options?: ObOption[]; lang?: string; msgId?: string; qr?: { link: string }; askContact?: boolean };
  /** Run Asha again: the session changed which messages count. */
  rerun?: boolean;
  /** Do nothing now (a duplicate run while waiting for the language answer). */
  skip?: boolean;
}

export interface GateInput {
  leadId: string;
  lead: Lead & { session?: ChatSession; enrollment?: Enrollment };
  msg: Message;
  msgId: string;
  kb: KnowledgeBase;
}

const leadLang = (lead: Lead & { session?: ChatSession }): string | undefined => lead.session?.lang ?? lead.language ?? lead.uiLang;

async function say(
  leadId: string,
  channel: string,
  text: string,
  meta: Record<string, unknown>,
  options: ObOption[] = [],
): Promise<string> {
  const ref = await db.collection(`leads/${leadId}/messages`).add({
    role: "ai",
    channel,
    text,
    createdAt: FieldValue.serverTimestamp(),
    meta: { ...meta, ...(options.length ? { options: options.map((o) => o.label), choices: options } : {}) },
  });
  return ref.id;
}

/** The session / enrolment rules for one incoming prospect message. null = let Asha answer. */
export async function flowGate(g: GateInput): Promise<GateResult | null> {
  const { leadId, lead, msg, msgId } = g;
  if (!SESSION_CHANNELS.has(msg.channel)) return null;
  if (lead.selftest || lead.burst || lead.seed || lead.simulated) return null;
  const ref = db.doc(`leads/${leadId}`);
  const msgRef = db.doc(`leads/${leadId}/messages/${msgId}`);
  const meta = (msg.meta ?? {}) as Record<string, unknown>;
  const text = (msg.text ?? "").trim();
  const choiceId = typeof meta.choiceId === "string" ? meta.choiceId : undefined;
  const session = lead.session ?? {};
  const enrollment = lead.enrollment;
  const hasImage = !!(msg as Message & { imageB64?: string }).imageB64;

  // ---- 1. A receipt photo while one is expected: always accepted, whatever the session ----
  if (hasImage && enrollment?.status === "awaiting_receipt") {
    const lang = leadLang(lead);
    await msgRef.set({ text: "🧾 Payment receipt", meta: { receipt: true } }, { merge: true });
    const replyId = await say(leadId, msg.channel, ft("thanks", lang), { kind: "payment_thanks", sessionEnd: true });
    await ref.set(
      {
        enrollment: { status: "receipt_received", receiptMsgId: msgId, receiptAt: FieldValue.serverTimestamp() },
        needsHuman: true,
        handoffReason: `💳 Verify payment: ₹${enrollment.amount ?? ""} for ${enrollment.courseName ?? "a course"}`,
        status: "payment_review",
        session: { status: "closed", closedAt: FieldValue.serverTimestamp(), closedReason: "receipt", expiresAt: FieldValue.delete(), awaitingLang: false },
        ai: { lastAnsweredId: msgId },
        lastMessageAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await alertAdmins(leadId, `💳 Payment receipt: ${lead.name || lead.studentName || "a student"}`, `₹${enrollment.amount ?? ""} · ${enrollment.courseName ?? ""} · verify and allot the course`);
    await logEvent("payment_receipt", leadId, { amount: enrollment.amount, course: enrollment.courseName });
    return { reply: { text: ft("thanks", lang), channel: msg.channel, lang, msgId: replyId } };
  }

  // ---- 2. Restart: "restart", /start, … → fresh session, language first ----
  if ((isRestart(text) || meta.start === true) && session.promptedFor !== msgId) {
    // Kept as a plain "Hi", so once the language is picked Asha greets them in it.
    await msgRef.set({ text: "Hi", meta: { restart: true, originalText: text } }, { merge: true });
    const replyId = await say(leadId, msg.channel, ft("pickLang", "en"), { kind: "language", sessionControl: true, automatic: true }, LANG_OPTIONS);
    if (enrollment && [...FORM_STATES, "choosing_course"].includes(enrollment.status)) {
      await ref.set({ enrollment: { status: "cancelled", step: FieldValue.delete(), otp: FieldValue.delete() } }, { merge: true });
    }
    await ref.set(
      {
        session: {
          status: "active",
          startedAt: Timestamp.fromMillis((msg.createdAt?.toMillis?.() ?? Date.now()) - 1),
          awaitingLang: true,
          promptedFor: msgId,
          lang: FieldValue.delete(),
          closedAt: FieldValue.delete(),
          closedReason: FieldValue.delete(),
        },
      },
      { merge: true },
    );
    return { reply: { text: ft("pickLang", "en"), channel: msg.channel, options: LANG_OPTIONS, msgId: replyId } };
  }

  // ---- 3. No live session (first message ever, after a restart, or after auto-close) ----
  if (session.status !== "active") {
    const startedAt = session.status === "new" && session.startedAt ? session.startedAt : Timestamp.fromMillis((msg.createdAt?.toMillis?.() ?? Date.now()) - 1);
    const uiLang = typeof meta.uiLang === "string" ? parseLang(meta.uiLang) ?? (["en", "hi", "mr"].includes(meta.uiLang) ? (meta.uiLang as Lang) : undefined) : undefined;
    if (uiLang) {
      // The website asks the language itself before the first message.
      await ref.set({ uiLang, session: { status: "active", lang: uiLang, startedAt, awaitingLang: false, closedAt: FieldValue.delete(), closedReason: FieldValue.delete() } }, { merge: true });
      return { rerun: true };
    }
    const replyId = await say(leadId, msg.channel, ft("pickLang", "en"), { kind: "language", sessionControl: true, automatic: true }, LANG_OPTIONS);
    await ref.set(
      { session: { status: "active", startedAt, awaitingLang: true, promptedFor: msgId, lang: FieldValue.delete(), closedAt: FieldValue.delete(), closedReason: FieldValue.delete() } },
      { merge: true },
    );
    return { reply: { text: ft("pickLang", "en"), channel: msg.channel, options: LANG_OPTIONS, msgId: replyId } };
  }

  // ---- 4. Waiting for the language ----
  if (session.awaitingLang) {
    if (session.promptedFor === msgId) return { skip: true };
    const picked = parseLang(text, choiceId);
    const lang = picked ?? guessLang(text, typeof meta.langHint === "string" ? meta.langHint : undefined);
    if (picked) await msgRef.set({ meta: { sessionControl: true } }, { merge: true });
    await ref.set({ uiLang: lang, session: { lang, awaitingLang: false } }, { merge: true });
    return { rerun: true };
  }

  const lang = leadLang(lead);

  // ---- 5. Enrolment: form → summary → email code → UPI QR ----
  if (enrollment && FORM_STATES.includes(enrollment.status)) return formStep(g, enrollment, text, choiceId, lang);
  const enrolled = enrollment && ["receipt_received", "verified"].includes(enrollment.status);
  if (!enrolled && looksLikeEnroll(text, choiceId)) return startForm(g, enrollment, lang);
  if (enrollment?.status === "awaiting_receipt" && !hasImage && looksLikePaid(text)) {
    const replyId = await say(leadId, msg.channel, ft("sendReceipt", lang), { kind: "payment_reminder" });
    await ref.set({ ai: { lastAnsweredId: msgId } }, { merge: true });
    return { reply: { text: ft("sendReceipt", lang), channel: msg.channel, lang, msgId: replyId } };
  }
  return null;
}

/** Writes the reply, records the state and answers this message. */
async function formReply(
  g: GateInput,
  text: string,
  options: ObOption[],
  enrollment: Record<string, unknown>,
  lang?: string,
  extra: { askContact?: boolean; kind?: string } = {},
): Promise<GateResult> {
  const ref = db.doc(`leads/${g.leadId}`);
  const replyId = await say(g.leadId, g.msg.channel, text, { kind: extra.kind ?? "enroll_form" }, options);
  await ref.set({ enrollment, ai: { lastAnsweredId: g.msgId }, lastMessageAt: FieldValue.serverTimestamp() }, { merge: true });
  return { reply: { text, channel: g.msg.channel, options, lang, msgId: replyId, askContact: extra.askContact } };
}

function formDefaults(g: GateInput, prev?: Enrollment): Partial<Record<Field, string>> {
  const d = { ...defaultsFrom(g.lead), ...(prev?.form ?? {}) } as Partial<Record<Field, string>>;
  const courseId = g.lead.recommendation?.courseId ?? g.lead.interestCourseId ?? g.lead.onboarding?.courseId;
  const rec = g.kb.courses.find((c) => c.id === courseId);
  if (rec && !d.course) d.course = rec.name;
  return d;
}

/** "Enroll now": the form starts (earlier answers, if any, are offered as one-tap defaults). */
async function startForm(g: GateInput, prev: Enrollment | undefined, lang?: string): Promise<GateResult> {
  const st: FormState = { form: {}, step: FIELDS[0], queue: FIELDS.slice(1) as Field[], editing: false };
  const q = askFor(FIELDS[0], st, g.kb, lang, formDefaults(g, prev));
  await logEvent("enroll_form_started", g.leadId, {});
  return formReply(
    g,
    `${tt("intro", lang, { n: FIELDS.length })}\n\n${q.text}`,
    q.options,
    { status: "form", step: st.step, queue: st.queue, editing: false, form: {}, startedAt: FieldValue.serverTimestamp(), emailVerified: false, otp: FieldValue.delete() },
    lang,
    { askContact: q.askContact },
  );
}

async function formStep(g: GateInput, e: Enrollment, text: string, choiceId: string | undefined, lang?: string): Promise<GateResult> {
  const st: FormState = { form: { ...(e.form ?? {}) }, step: e.step, queue: [...(e.queue ?? [])], editing: !!e.editing, otp: e.otp };
  const defaults = formDefaults(g, e);
  if (isCancel(text, choiceId)) {
    return formReply(g, tt("cancelled", lang), [], { status: "cancelled", step: FieldValue.delete(), otp: FieldValue.delete() }, lang);
  }

  if (st.step === "confirm") {
    if (isConfirm(text, choiceId)) return afterConfirm(g, st, lang);
    if (isEdit(text, choiceId)) return formReply(g, tt("editWhat", lang), editOptions(lang), { status: "confirm", step: "editmenu" }, lang);
    return formReply(g, summaryText(st, lang), confirmOptions(lang), { status: "confirm", step: "confirm" }, lang);
  }

  if (st.step === "editmenu") {
    const group = groupFromText(text, choiceId);
    if (!group) return formReply(g, tt("editWhat", lang), editOptions(lang), { status: "confirm", step: "editmenu" }, lang);
    const [first, ...rest] = GROUPS[group];
    const q = askFor(first, st, g.kb, lang, defaults);
    return formReply(g, q.text, q.options, { status: "form", step: first, queue: rest, editing: true }, lang, { askContact: q.askContact });
  }

  if (st.step === "otp") {
    if (choiceId === "otp:email" || /change email|ईमेल बदल/i.test(text)) {
      const q = askFor("email", st, g.kb, lang, defaults);
      return formReply(g, q.text, q.options, { status: "form", step: "email", queue: [], editing: true, otp: FieldValue.delete() }, lang);
    }
    if (choiceId === "otp:resend" || /resend|फिर भेज|पुन्हा पाठव/i.test(text)) return afterConfirm(g, st, lang);
    const r = checkOtp(g.leadId, st.otp, text);
    const otpOptions = [
      { id: "otp:resend", label: tt("resend", lang) },
      { id: "otp:email", label: tt("changeEmail", lang) },
      { id: "form:cancel", label: tt("cancel", lang) },
    ];
    if (r === "ok") {
      await db.doc(`leads/${g.leadId}`).set({ enrollment: { emailVerified: true, otp: FieldValue.delete() } }, { merge: true });
      return startPayment(g, st.form.courseId ?? "", st.form.course ?? "", lang, tt("otpOk", lang));
    }
    if (r === "expired" || r === "none") return formReply(g, tt("otpExpired", lang), otpOptions, { status: "otp", step: "otp" }, lang);
    const attempts = (st.otp?.attempts ?? 0) + 1;
    if (attempts >= 5) return formReply(g, tt("otpExpired", lang), otpOptions, { status: "otp", step: "otp", otp: FieldValue.delete() }, lang);
    return formReply(g, tt("otpWrong", lang), otpOptions, { status: "otp", step: "otp", otp: { attempts } }, lang);
  }

  // ---- one form field ----
  const step = (st.step ?? FIELDS[0]) as Field;
  const v = validate(step, text, choiceId, st, g.kb, lang);
  if (v.error) {
    const q = askFor(step, st, g.kb, lang, defaults);
    return formReply(g, `${tt(v.error, lang)}\n\n${q.text}`, q.options, { status: "form", step }, lang, { askContact: q.askContact });
  }
  st.form[step] = v.value!;
  const patch: Record<string, unknown> = { [step]: v.value };
  if (step === "course" && v.courseId) {
    st.form.courseId = v.courseId;
    patch.courseId = v.courseId;
  }
  // Next question; mode is only asked when the chosen course runs both online and in class.
  let next = st.queue?.shift();
  while (next === "mode") {
    const course = g.kb.courses.find((c) => c.id === st.form.courseId);
    if (course && bothModes(course.mode)) break;
    const mode = /online/i.test(course?.mode ?? "") ? "Online" : "Classroom";
    st.form.mode = mode;
    patch.mode = mode;
    next = st.queue?.shift();
  }
  if (next) {
    const q = askFor(next, st, g.kb, lang, defaults);
    return formReply(g, q.text, q.options, { status: "form", step: next, queue: st.queue ?? [], form: patch }, lang, { askContact: q.askContact });
  }
  return formReply(g, summaryText(st, lang), confirmOptions(lang), { status: "confirm", step: "confirm", queue: [], editing: false, form: patch }, lang);
}

/** Details confirmed: email code (when Gmail is set up), else straight to the QR. */
async function afterConfirm(g: GateInput, st: FormState, lang?: string): Promise<GateResult> {
  const { emailReady } = await import("./email");
  const email = st.form.email ?? "";
  if (!(await emailReady())) {
    await db.doc(`leads/${g.leadId}`).set({ enrollment: { emailVerified: false, note: "email code skipped: Gmail not set up" } }, { merge: true });
    return startPayment(g, st.form.courseId ?? "", st.form.course ?? "", lang);
  }
  const r = await sendOtp(g.leadId, email, lang);
  const options = [
    { id: "otp:resend", label: tt("resend", lang) },
    { id: "otp:email", label: tt("changeEmail", lang) },
    { id: "form:cancel", label: tt("cancel", lang) },
  ];
  if (!r.ok) return formReply(g, tt("otpFail", lang, { email }), options, { status: "otp", step: "otp", otp: FieldValue.delete() }, lang);
  return formReply(g, tt("otpSent", lang, { email }), options, { status: "otp", step: "otp", otp: r.otp }, lang);
}

async function startPayment(g: GateInput, courseId: string, courseName: string, lang?: string, prefix = ""): Promise<GateResult> {
  const { leadId, msg, msgId } = g;
  const ref = db.doc(`leads/${leadId}`);
  const cfg = await paymentConfig();
  if (!cfg.upiId) {
    const replyId = await say(leadId, msg.channel, ft("noUpi", lang), { kind: "payment_pending" });
    await ref.set(
      {
        enrollment: { status: "awaiting_details", step: FieldValue.delete(), courseId, courseName, amount: cfg.amount },
        needsHuman: true,
        handoffReason: "💳 Wants to enroll, but no UPI ID is set (Admin → Overview → Enrollment payments)",
        ai: { lastAnsweredId: msgId },
      },
      { merge: true },
    );
    return { reply: { text: ft("noUpi", lang), channel: msg.channel, lang, msgId: replyId } };
  }
  const link = upiLink(cfg, `Registration ${courseName}`);
  const text = `${prefix ? `${prefix}\n\n` : ""}${ft("pay", lang, { course: courseName, amount: cfg.amount, upi: cfg.upiId, payee: cfg.payee })}`;
  const replyId = await say(leadId, msg.channel, text, { kind: "payment_qr", upiLink: link, upiId: cfg.upiId, payee: cfg.payee, amount: cfg.amount, course: courseName });
  await ref.set(
    {
      enrollment: { status: "awaiting_receipt", step: FieldValue.delete(), courseId, courseName, amount: cfg.amount, upiId: cfg.upiId, payee: cfg.payee, qrAt: FieldValue.serverTimestamp() },
      interestCourseId: courseId,
      ai: { lastAnsweredId: msgId },
    },
    { merge: true },
  );
  await logEvent("enroll_started", leadId, { course: courseName, amount: cfg.amount });
  return { reply: { text, channel: msg.channel, lang, msgId: replyId, qr: { link } } };
}

/** One alert per admin (alerts are read per user on the desk). */
export async function alertAdmins(leadId: string, title: string, body: string): Promise<void> {
  try {
    const admins = await db.collection("users").where("role", "==", "admin").limit(10).get();
    await Promise.all(admins.docs.map((u) => db.collection("alerts").add({ uid: u.id, leadId, title, body, read: false, at: FieldValue.serverTimestamp() })));
  } catch (e) {
    console.warn("admin alert failed", e);
  }
}

/** After every bot reply: the 2-minute clock (15 minutes while a receipt is awaited) restarts. */
export async function touchSession(leadId: string): Promise<void> {
  const ref = db.doc(`leads/${leadId}`);
  const lead = (await ref.get()).data() as (Lead & { session?: ChatSession; enrollment?: Enrollment }) | undefined;
  if (!lead?.session || lead.session.status !== "active" || lead.aiPaused) return;
  const es = lead.enrollment?.status ?? "";
  const ms = es === "awaiting_receipt" ? RECEIPT_IDLE_MS : FORM_STATES.includes(es) ? FORM_IDLE_MS : IDLE_MS;
  await ref.set({ session: { expiresAt: Timestamp.fromMillis(Date.now() + ms) } }, { merge: true });
}

/** Every minute: close chats whose clock ran out (the last word was Asha's). */
export async function closeIdleSessions(now = Date.now()): Promise<number> {
  const due = await db.collection("leads").where("session.expiresAt", "<=", Timestamp.fromMillis(now)).limit(50).get();
  let closed = 0;
  for (const d of due.docs) {
    const lead = d.data() as Lead & { session?: ChatSession; enrollment?: Enrollment };
    const s = lead.session;
    if (!s || s.status !== "active" || lead.aiPaused || lead.mergedInto) {
      await d.ref.set({ session: { expiresAt: FieldValue.delete() } }, { merge: true });
      continue;
    }
    if (lead.ai?.busy && lead.ai.since && now - lead.ai.since.toMillis() < 150_000) continue;
    const last = (await d.ref.collection("messages").orderBy("createdAt", "desc").limit(1).get()).docs[0]?.data() as Message | undefined;
    if (last?.role === "user") continue; // the prospect is waiting for us, not the other way round
    const channel = lead.lastChannel ?? "web";
    const text = ft("closed", s.lang ?? lead.language);
    await d.ref.collection("messages").add({ role: "ai", channel, text, createdAt: FieldValue.serverTimestamp(), meta: { kind: "session_closed", automatic: true, sessionControl: true } });
    await d.ref.set({ session: { status: "closed", closedAt: FieldValue.serverTimestamp(), closedReason: "idle", expiresAt: FieldValue.delete(), awaitingLang: false } }, { merge: true });
    if (channel !== "web") {
      const { deliverOn } = await import("./channels");
      await deliverOn(channel, lead, text).catch((e) => console.warn("close message not delivered", e));
    }
    closed++;
  }
  return closed;
}

/** Website "Restart" button: the next message starts a new session (the page asks the language). */
export async function restartSession(leadId: string): Promise<void> {
  await db.doc(`leads/${leadId}`).set(
    {
      session: {
        status: "new",
        startedAt: Timestamp.now(),
        awaitingLang: false,
        lang: FieldValue.delete(),
        promptedFor: FieldValue.delete(),
        expiresAt: FieldValue.delete(),
        closedAt: FieldValue.delete(),
        closedReason: FieldValue.delete(),
      },
    },
    { merge: true },
  );
}

/**
 * Admin: payment checked → course allotted (the student's choice is pre-selected; the admin may
 * pick any course) → admission ID (ADM-2026-0001) + a record in "Registered students", and the
 * student is told on their chat channel, by email and on their WhatsApp number (SMS is paid: not used).
 */
export async function verifyEnrollment(leadId: string, approve: boolean, by: string, courseId?: string, note?: string): Promise<{ ok: boolean; detail: string; admissionId?: string }> {
  const ref = db.doc(`leads/${leadId}`);
  const lead = (await ref.get()).data() as (Lead & { enrollment?: Enrollment; admissionId?: string }) | undefined;
  if (!lead?.enrollment) return { ok: false, detail: "This lead has no enrolment." };
  const e = lead.enrollment;
  const f = e.form ?? {};
  const kb = ((await db.doc("kb/main").get()).data() ?? { courses: [] }) as KnowledgeBase;
  const course = kb.courses.find((c) => c.id === (courseId || f.courseId || e.courseId));
  const courseName = course?.name ?? f.course ?? e.courseName ?? "the course";
  const lang = lead.language ?? lead.uiLang;

  let admissionId = lead.admissionId;
  if (approve && !admissionId) admissionId = await nextAdmissionId();
  const details = [
    f.mode ? `Mode: ${f.mode}` : "",
    f.batch ? `Batch: ${f.batch}` : "",
    f.start ? `Start: ${f.start}` : "",
  ].filter(Boolean).join(" · ");
  const text = approve
    ? `${ft("verified", lang, { amount: e.amount ?? "", course: courseName })}\n\n🆔 Admission ID: ${admissionId}${details ? `\n${details}` : ""}`
    : ft("rejected", lang);

  await ref.set(
    {
      enrollment: {
        status: approve ? "verified" : "rejected",
        verifiedBy: by,
        verifiedAt: FieldValue.serverTimestamp(),
        ...(approve ? { courseId: course?.id ?? e.courseId ?? "", courseName, admissionId } : {}),
        ...(note ? { note } : {}),
      },
      ...(approve
        ? { status: "admitted", admissionId, enrolledCourseId: course?.id ?? e.courseId ?? "", enrolledCourseName: courseName, needsHuman: false, handoffReason: "" }
        : { needsHuman: true, handoffReason: `💳 Payment not verified${note ? `: ${note}` : ""}: call the student` }),
      lastMessageAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  if (approve && admissionId) {
    // The registered-students register (Master dashboard → Registered students).
    await db.doc(`students/${admissionId}`).set(
      {
        admissionId,
        leadId,
        name: f.name ?? lead.studentName ?? lead.name ?? "",
        phone: f.phone ?? lead.phone ?? "",
        whatsapp: f.whatsapp ?? "",
        email: f.email ?? lead.email ?? "",
        emailVerified: !!e.emailVerified,
        dob: f.dob ?? "",
        city: f.city ?? lead.city ?? "",
        qualification: f.qualification ?? "",
        address: f.address ?? "",
        guardianName: f.guardianName ?? "",
        guardianPhone: f.guardianPhone ?? "",
        courseId: course?.id ?? e.courseId ?? "",
        courseName,
        studentChoice: f.course ?? e.courseName ?? "",
        mode: f.mode ?? "",
        batch: f.batch ?? "",
        startMonth: f.start ?? "",
        amount: e.amount ?? 0,
        channel: lead.lastChannel ?? "web",
        allottedBy: by,
        allottedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  // ---- Tell the student everywhere that is free ----
  const sentTo: string[] = [];
  const failed: string[] = [];
  const channel = lead.lastChannel ?? "web";
  let delivered = true;
  let deliveryNote = "";
  if (channel !== "web") {
    const { deliverOn } = await import("./channels");
    const r = await deliverOn(channel, lead, text);
    delivered = r.delivered;
    deliveryNote = r.note;
    (r.delivered ? sentTo : failed).push(channel);
  } else sentTo.push("web chat");
  await ref.collection("messages").add({
    role: "ai",
    channel,
    text,
    createdAt: FieldValue.serverTimestamp(),
    meta: { kind: approve ? "enrollment_verified" : "enrollment_rejected", automatic: true, by, delivered, ...(deliveryNote ? { note: deliveryNote } : {}) },
  });
  if (approve) {
    const wa = f.whatsapp;
    if (wa && !(channel === "whatsapp" && lead.waId?.endsWith(wa))) {
      const { sendWhatsAppText } = await import("./channels");
      const r = await sendWhatsAppText(`91${wa}`, text);
      (r.ok ? sentTo : failed).push(`WhatsApp +91 ${wa}`);
    }
    if (f.email) {
      const { sendEmail } = await import("./email");
      const r = await sendEmail(f.email, `Admission confirmed: ${admissionId}`, `${text.replace(/[🎉🆔]/gu, "").trim()}\n\nName: ${f.name ?? ""}\nCourse: ${courseName}`);
      (r.ok ? sentTo : failed).push(`email ${f.email}`);
    }
  }
  await logEvent(approve ? "enrolled" : "payment_rejected", leadId, { course: courseName, by, amount: e.amount, admissionId: admissionId ?? "", sentTo, failed });
  return {
    ok: true,
    admissionId,
    detail: approve
      ? `Admission ${admissionId}: ${courseName}. Sent to ${sentTo.join(", ") || "nobody"}${failed.length ? `; not delivered: ${failed.join(", ")}` : ""}.`
      : "Marked not verified; the student was told.",
  };
}
