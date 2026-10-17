/**
 * The enrolment form, asked one question at a time inside the chat (the same on WhatsApp,
 * Telegram and the website): every field is compulsory and checked, then the student reviews a
 * summary (Confirm / Edit), then an email code (OTP) is verified, and only then the UPI QR is shown.
 */
import { createHash, randomInt } from "node:crypto";
import { db, FieldValue, type KnowledgeBase, type Lead } from "./db";
import { normalizePhone } from "./identity";
import type { ObOption } from "./onboarding";

export type Lang = "en" | "hi" | "mr";

export const FIELDS = [
  "name",
  "phone",
  "whatsapp",
  "email",
  "dob",
  "city",
  "qualification",
  "address",
  "guardianName",
  "guardianPhone",
  "course",
  "mode",
  "batch",
  "start",
] as const;
export type Field = (typeof FIELDS)[number];

/** Edit menu groups (WhatsApp lists take at most 10 rows). */
export const GROUPS: Record<string, Field[]> = {
  name: ["name"],
  phone: ["phone"],
  whatsapp: ["whatsapp"],
  email: ["email"],
  dob: ["dob"],
  city: ["city"],
  qualification: ["qualification"],
  address: ["address"],
  guardian: ["guardianName", "guardianPhone"],
  prefs: ["course", "mode", "batch", "start"],
};

export interface FormState {
  form: Partial<Record<Field, string>> & { courseId?: string };
  step?: Field | "confirm" | "editmenu" | "otp";
  queue?: Field[];
  editing?: boolean;
  otp?: { hash: string; expiresAt: number; attempts: number; to: string };
  emailVerified?: boolean;
}

type L3 = [string, string, string];
const T: Record<string, L3> = {
  name: ["Student's full name?", "स्टूडेंट का पूरा नाम?", "विद्यार्थ्याचं पूर्ण नाव?"],
  phone: ["Student's mobile number (10 digits)?", "स्टूडेंट का मोबाइल नंबर (10 अंक)?", "विद्यार्थ्याचा मोबाइल नंबर (10 अंक)?"],
  whatsapp: ["WhatsApp number?", "WhatsApp नंबर?", "WhatsApp नंबर?"],
  email: ["Email address? (we will send a verification code)", "ईमेल पता? (हम वेरिफिकेशन कोड भेजेंगे)", "ईमेल पत्ता? (आम्ही व्हेरिफिकेशन कोड पाठवू)"],
  dob: ["Date of birth (DD-MM-YYYY)?", "जन्म तिथि (DD-MM-YYYY)?", "जन्मतारीख (DD-MM-YYYY)?"],
  city: ["City?", "शहर?", "शहर?"],
  qualification: ["Highest qualification (and year)?", "सबसे ऊँची पढ़ाई (और साल)?", "सर्वोच्च शिक्षण (आणि वर्ष)?"],
  address: ["Full postal address?", "पूरा पता?", "पूर्ण पत्ता?"],
  guardianName: ["Parent / guardian's name?", "माता-पिता / अभिभावक का नाम?", "पालकांचं नाव?"],
  guardianPhone: ["Parent / guardian's mobile number?", "माता-पिता / अभिभावक का मोबाइल नंबर?", "पालकांचा मोबाइल नंबर?"],
  course: ["Which course do you want to join?", "आप कौन सा कोर्स जॉइन करना चाहते हैं?", "कोणत्या कोर्सला प्रवेश घ्यायचा आहे?"],
  mode: ["Online or classroom?", "ऑनलाइन या क्लासरूम?", "ऑनलाइन की क्लासरूम?"],
  batch: ["Preferred batch time?", "कौन सा बैच टाइम?", "कोणती बॅच वेळ?"],
  start: ["When would you like to start?", "कब से शुरू करना चाहेंगे?", "कधीपासून सुरू करायचं?"],
  intro: [
    "Great! 🎓 Let's fill your enrolment form ({n} quick questions, all required). You can type ❌ cancel any time.",
    "बढ़िया! 🎓 चलिए एनरोलमेंट फॉर्म भरते हैं ({n} छोटे सवाल, सभी ज़रूरी)। कभी भी ❌ cancel लिख सकते हैं।",
    "छान! 🎓 चला प्रवेश अर्ज भरूया ({n} छोटे प्रश्न, सर्व आवश्यक). कधीही ❌ cancel लिहू शकता.",
  ],
  bad_name: ["Please type the full name (letters only).", "कृपया पूरा नाम लिखें (सिर्फ़ अक्षर)।", "कृपया पूर्ण नाव लिहा (फक्त अक्षरं)."],
  bad_phone: ["That doesn't look like a 10-digit Indian mobile number.", "यह 10 अंकों का भारतीय मोबाइल नंबर नहीं लगता।", "हा 10 अंकी भारतीय मोबाइल नंबर वाटत नाही."],
  bad_email: ["That email doesn't look right. Example: name@gmail.com", "यह ईमेल सही नहीं लगता। जैसे: name@gmail.com", "हा ईमेल बरोबर वाटत नाही. उदा: name@gmail.com"],
  bad_dob: ["Please write the date like 15-08-2004.", "कृपया तारीख ऐसे लिखें: 15-08-2004", "कृपया तारीख अशी लिहा: 15-08-2004"],
  bad_text: ["Please write a little more.", "कृपया थोड़ा और लिखें।", "कृपया थोडं अधिक लिहा."],
  bad_choice: ["Please tap one of the options.", "कृपया कोई एक विकल्प चुनें।", "कृपया एक पर्याय निवडा."],
  summary: ["Please check your details:", "कृपया अपनी जानकारी जाँच लें:", "कृपया तुमची माहिती तपासा:"],
  confirm: ["✅ Confirm", "✅ कन्फर्म करें", "✅ कन्फर्म करा"],
  edit: ["✏️ Edit", "✏️ बदलें", "✏️ बदला"],
  editWhat: ["What would you like to change?", "क्या बदलना है?", "काय बदलायचं आहे?"],
  cancel: ["❌ Cancel", "❌ रद्द करें", "❌ रद्द करा"],
  cancelled: [
    "Enrolment cancelled. You can tap Enroll again any time. 🙂",
    "एनरोलमेंट रद्द कर दिया गया। आप कभी भी फिर से एनरोल कर सकते हैं। 🙂",
    "प्रवेश प्रक्रिया रद्द केली. तुम्ही कधीही पुन्हा प्रवेश घेऊ शकता. 🙂",
  ],
  otpSent: [
    "We sent a 6-digit code to {email}. Please type it here (valid for 10 minutes).",
    "हमने {email} पर 6 अंकों का कोड भेजा है। कृपया यहाँ लिखें (10 मिनट तक मान्य)।",
    "आम्ही {email} वर 6 अंकी कोड पाठवला आहे. कृपया इथे लिहा (10 मिनिटं वैध).",
  ],
  otpFail: [
    "We could not send an email to {email}. Please check the address.",
    "{email} पर ईमेल नहीं भेज पाए। कृपया पता जाँचें।",
    "{email} वर ईमेल पाठवता आला नाही. कृपया पत्ता तपासा.",
  ],
  otpWrong: ["That code is not right. Please try again.", "कोड सही नहीं है। फिर से कोशिश करें।", "कोड बरोबर नाही. पुन्हा प्रयत्न करा."],
  otpExpired: ["That code has expired. Tap Resend code.", "कोड की समय-सीमा खत्म हो गई। Resend code दबाएँ।", "कोडची मुदत संपली. Resend code दाबा."],
  otpOk: ["✅ Email verified.", "✅ ईमेल वेरिफाई हो गया।", "✅ ईमेल व्हेरिफाय झाला."],
  resend: ["🔁 Resend code", "🔁 कोड फिर भेजें", "🔁 कोड पुन्हा पाठवा"],
  changeEmail: ["✏️ Change email", "✏️ ईमेल बदलें", "✏️ ईमेल बदला"],
  same: ["Same as mobile", "मोबाइल जैसा ही", "मोबाइलसारखाच"],
  online: ["Online", "ऑनलाइन", "ऑनलाइन"],
  classroom: ["Classroom", "क्लासरूम", "क्लासरूम"],
  morning: ["Morning", "सुबह", "सकाळ"],
  evening: ["Evening", "शाम", "संध्याकाळ"],
  weekend: ["Weekend", "वीकेंड", "वीकेंड"],
  thisMonth: ["This month", "इसी महीने", "याच महिन्यात"],
  nextMonth: ["Next month", "अगले महीने", "पुढच्या महिन्यात"],
  later: ["Later", "बाद में", "नंतर"],
  step: ["({i}/{n})", "({i}/{n})", "({i}/{n})"],
};

const LABEL: Record<Field, L3> = {
  name: ["Name", "नाम", "नाव"],
  phone: ["Mobile", "मोबाइल", "मोबाइल"],
  whatsapp: ["WhatsApp", "WhatsApp", "WhatsApp"],
  email: ["Email", "ईमेल", "ईमेल"],
  dob: ["Date of birth", "जन्म तिथि", "जन्मतारीख"],
  city: ["City", "शहर", "शहर"],
  qualification: ["Qualification", "पढ़ाई", "शिक्षण"],
  address: ["Address", "पता", "पत्ता"],
  guardianName: ["Parent / guardian", "अभिभावक", "पालक"],
  guardianPhone: ["Parent's mobile", "अभिभावक का मोबाइल", "पालकांचा मोबाइल"],
  course: ["Course", "कोर्स", "कोर्स"],
  mode: ["Mode", "मोड", "पद्धत"],
  batch: ["Batch", "बैच", "बॅच"],
  start: ["Start", "शुरुआत", "सुरुवात"],
};

const GROUP_LABEL: Record<string, L3> = {
  name: LABEL.name,
  phone: LABEL.phone,
  whatsapp: LABEL.whatsapp,
  email: LABEL.email,
  dob: LABEL.dob,
  city: LABEL.city,
  qualification: LABEL.qualification,
  address: LABEL.address,
  guardian: ["Parent details", "अभिभावक की जानकारी", "पालकांची माहिती"],
  prefs: ["Course & batch", "कोर्स और बैच", "कोर्स व बॅच"],
};

const ix = (l?: string) => (l === "hi" || l === "hinglish" ? 1 : l === "mr" || l === "marathi-english" ? 2 : 0);
export const tt = (k: string, l?: string, vars: Record<string, string | number> = {}) => {
  let s = T[k][ix(l)];
  for (const [a, b] of Object.entries(vars)) s = s.split(`{${a}}`).join(String(b));
  return s;
};

const QUALIFICATIONS = ["10th", "12th", "Diploma", "Graduate (BA / BCom / BSc)", "BE / BTech / BCA", "Post-graduate"];

/** True when the course can be done both online and in the classroom. */
export function bothModes(courseMode?: string): boolean {
  const m = (courseMode ?? "").toLowerCase();
  return /hybrid|both|online.*(class|offline)|(class|offline).*online/.test(m);
}

function monthName(offset: number): string {
  const d = new Date(Date.now() + 330 * 60_000);
  d.setUTCDate(1);
  d.setUTCMonth(d.getUTCMonth() + offset);
  return d.toLocaleString("en-IN", { month: "short", year: "numeric", timeZone: "UTC" });
}

export function parseDob(text: string): string | undefined {
  const m = text.trim().match(/^(\d{1,2})[-/. ](\d{1,2})[-/. ](\d{4})$/);
  if (!m) return undefined;
  const [d, mo, y] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const dt = new Date(Date.UTC(y, mo - 1, d));
  if (dt.getUTCDate() !== d || dt.getUTCMonth() !== mo - 1) return undefined;
  const age = (Date.now() - dt.getTime()) / (365.25 * 86_400_000);
  if (age < 12 || age > 70) return undefined;
  return `${String(d).padStart(2, "0")}-${String(mo).padStart(2, "0")}-${y}`;
}

export function validEmail(s: string): string | undefined {
  const e = s.trim().toLowerCase();
  return /^[^\s@]+@[^\s@]+\.[a-z]{2,}$/.test(e) ? e : undefined;
}

export function validMobile(s: string): string | undefined {
  const p = normalizePhone(s);
  return p && /^[6-9]\d{9}$/.test(p) ? p : undefined;
}

/** The question for [step]: text + tappable options (prefilled value first). */
export function askFor(step: Field, st: FormState, kb: KnowledgeBase, lang: string | undefined, defaults: Partial<Record<Field, string>>): { text: string; options: ObOption[]; askContact?: boolean } {
  const n = FIELDS.length;
  const i = FIELDS.indexOf(step) + 1;
  const text = `${tt(step, lang)} ${tt("step", lang, { i, n })}`;
  const options: ObOption[] = [];
  const prev = st.form[step] ?? defaults[step];
  const cancel = { id: "form:cancel", label: tt("cancel", lang) };
  switch (step) {
    case "whatsapp":
      if (st.form.phone) options.push({ id: "form:same", label: tt("same", lang) });
      break;
    case "qualification":
      for (const q of QUALIFICATIONS) options.push({ id: `form:v:${q}`, label: q });
      break;
    case "course":
      for (const c of kb.courses.slice(0, 9)) options.push({ id: `form:course:${c.id}`, label: c.name });
      break;
    case "mode":
      options.push({ id: "form:v:Online", label: tt("online", lang) }, { id: "form:v:Classroom", label: tt("classroom", lang) });
      break;
    case "batch":
      options.push(
        { id: "form:v:Morning", label: tt("morning", lang) },
        { id: "form:v:Evening", label: tt("evening", lang) },
        { id: "form:v:Weekend", label: tt("weekend", lang) },
      );
      break;
    case "start":
      options.push(
        { id: `form:v:${monthName(0)}`, label: `${tt("thisMonth", lang)} (${monthName(0)})` },
        { id: `form:v:${monthName(1)}`, label: `${tt("nextMonth", lang)} (${monthName(1)})` },
        { id: "form:v:Later", label: tt("later", lang) },
      );
      break;
  }
  // A value we already know goes first, so a tap is enough.
  if (prev && !["course", "mode", "batch", "start", "qualification"].includes(step)) options.unshift({ id: `form:v:${prev}`, label: prev });
  if (step === "course" && prev) {
    const idx = options.findIndex((o) => o.label === prev);
    if (idx > 0) options.unshift(...options.splice(idx, 1));
  }
  if (options.length < 10) options.push(cancel);
  return { text, options: options.slice(0, 10), askContact: step === "phone" };
}

/** Checks one answer. Returns the stored value, or the key of the error message. */
export function validate(step: Field, raw: string, choiceId: string | undefined, st: FormState, kb: KnowledgeBase, lang: string | undefined): { value?: string; courseId?: string; error?: string } {
  const picked = choiceId?.startsWith("form:v:") ? choiceId.slice(7) : undefined;
  const text = (picked ?? raw).trim();
  switch (step) {
    case "name":
    case "guardianName": {
      const ok = text.length >= 2 && text.length <= 60 && /^[\p{L}\p{M} .'-]+$/u.test(text) && /\p{L}/u.test(text);
      return ok ? { value: text.replace(/\s+/g, " ") } : { error: "bad_name" };
    }
    case "phone":
    case "guardianPhone": {
      const p = validMobile(text);
      return p ? { value: p } : { error: "bad_phone" };
    }
    case "whatsapp": {
      if (choiceId === "form:same" || new RegExp(`^${tt("same", lang)}$`, "i").test(text) || /^same/i.test(text)) return st.form.phone ? { value: st.form.phone } : { error: "bad_phone" };
      const p = validMobile(text);
      return p ? { value: p } : { error: "bad_phone" };
    }
    case "email": {
      const e = validEmail(text);
      return e ? { value: e } : { error: "bad_email" };
    }
    case "dob": {
      const d = parseDob(text);
      return d ? { value: d } : { error: "bad_dob" };
    }
    case "city":
      return text.length >= 2 && text.length <= 50 ? { value: text } : { error: "bad_text" };
    case "qualification":
      return text.length >= 2 && text.length <= 80 ? { value: text } : { error: "bad_text" };
    case "address":
      return text.length >= 10 && text.length <= 300 ? { value: text } : { error: "bad_text" };
    case "course": {
      const id = choiceId?.startsWith("form:course:") ? choiceId.slice(12) : undefined;
      const t = text.toLowerCase();
      const c = kb.courses.find((x) => x.id === id) ?? kb.courses.find((x) => x.name.toLowerCase() === t) ?? kb.courses.find((x) => t.length > 3 && x.name.toLowerCase().includes(t));
      return c ? { value: c.name, courseId: c.id } : { error: "bad_choice" };
    }
    case "mode": {
      const t = text.toLowerCase();
      if (/online|ऑनलाइन/.test(t)) return { value: "Online" };
      if (/class|offline|क्लास/.test(t)) return { value: "Classroom" };
      return { error: "bad_choice" };
    }
    case "batch": {
      const t = text.toLowerCase();
      if (/morning|सुबह|सकाळ/.test(t)) return { value: "Morning" };
      if (/evening|शाम|संध्याकाळ/.test(t)) return { value: "Evening" };
      if (/weekend|वीकेंड|शनि|रवि/.test(t)) return { value: "Weekend" };
      return { error: "bad_choice" };
    }
    case "start": {
      if (picked) return { value: picked };
      const t = text.toLowerCase();
      if (/this|इसी|याच/.test(t)) return { value: monthName(0) };
      if (/next|अगले|पुढ/.test(t)) return { value: monthName(1) };
      if (/later|बाद|नंतर/.test(t)) return { value: "Later" };
      return { error: "bad_choice" };
    }
  }
}

export function summaryText(st: FormState, lang?: string): string {
  const rows = FIELDS.filter((f) => st.form[f]).map((f) => `${LABEL[f][ix(lang)]}: ${st.form[f]}`);
  return `${tt("summary", lang)}\n\n${rows.join("\n")}`;
}

export function confirmOptions(lang?: string): ObOption[] {
  return [
    { id: "form:confirm", label: tt("confirm", lang) },
    { id: "form:edit", label: tt("edit", lang) },
    { id: "form:cancel", label: tt("cancel", lang) },
  ];
}

export function editOptions(lang?: string): ObOption[] {
  return Object.keys(GROUPS).map((g) => ({ id: `form:group:${g}`, label: GROUP_LABEL[g][ix(lang)] }));
}

export function groupFromText(text: string, choiceId?: string): string | undefined {
  if (choiceId?.startsWith("form:group:")) return choiceId.slice(11);
  const t = text.trim().toLowerCase();
  return Object.keys(GROUPS).find((g) => GROUP_LABEL[g].some((l) => l.toLowerCase() === t));
}

export function isCancel(text: string, choiceId?: string): boolean {
  return choiceId === "form:cancel" || /^(❌\s*)?(cancel|stop|रद्द करें|रद्द करा|रद्द)$/i.test(text.trim());
}

export function isConfirm(text: string, choiceId?: string): boolean {
  return choiceId === "form:confirm" || /^(✅\s*)?(confirm|yes|ok|okay|correct|haan|ha|कन्फर्म करें|कन्फर्म करा|हाँ|हो)$/i.test(text.trim());
}

export function isEdit(text: string, choiceId?: string): boolean {
  return choiceId === "form:edit" || /^(✏️\s*)?(edit|change|बदलें|बदला)$/i.test(text.trim());
}

/** Known details used as one-tap defaults. */
export function defaultsFrom(lead: Lead): Partial<Record<Field, string>> {
  const d: Partial<Record<Field, string>> = {};
  const name = lead.studentName || lead.name;
  if (name && /\p{L}/u.test(name)) d.name = name;
  const phone = validMobile(lead.studentPhone || lead.phone || "");
  if (phone) d.phone = phone;
  const wa = lead.waId ? validMobile(lead.waId) : undefined;
  if (wa) d.whatsapp = wa;
  const email = validEmail(lead.studentEmail || lead.email || "");
  if (email) d.email = email;
  if (lead.city) d.city = lead.city;
  return d;
}

// ------------------------------------------------------------------ OTP
const hash = (leadId: string, code: string) => createHash("sha256").update(`${leadId}:${code}`).digest("hex");

export async function sendOtp(leadId: string, email: string, lang?: string): Promise<{ ok: boolean; error?: string; otp?: FormState["otp"] }> {
  const { sendEmail } = await import("./email");
  const code = String(randomInt(100000, 1000000));
  const subject = lang === "hi" ? "आपका एनरोलमेंट कोड" : lang === "mr" ? "तुमचा प्रवेश कोड" : "Your enrolment code";
  const r = await sendEmail(email, `${subject}: ${code}`, `${subject}: ${code}\n\nValid for 10 minutes. If you did not ask for this, please ignore this email.`);
  if (!r.ok) return { ok: false, error: r.error };
  return { ok: true, otp: { hash: hash(leadId, code), expiresAt: Date.now() + 10 * 60_000, attempts: 0, to: email } };
}

export function checkOtp(leadId: string, otp: FormState["otp"], text: string): "ok" | "wrong" | "expired" | "none" {
  const code = text.replace(/\D/g, "");
  if (!otp) return "none";
  if (Date.now() > otp.expiresAt) return "expired";
  if (code.length !== 6) return "wrong";
  return hash(leadId, code) === otp.hash ? "ok" : "wrong";
}

/** Next admission number for this year, e.g. ADM-2026-0001 (transaction, never repeats). */
export async function nextAdmissionId(): Promise<string> {
  const year = new Date(Date.now() + 330 * 60_000).getUTCFullYear();
  const ref = db.doc("config/counters");
  const n = await db.runTransaction(async (tx) => {
    const cur = Number(((await tx.get(ref)).get(`admission${year}`) as number | undefined) ?? 0) + 1;
    tx.set(ref, { [`admission${year}`]: cur, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    return cur;
  });
  return `ADM-${year}-${String(n).padStart(4, "0")}`;
}
