/**
 * "What is my admission ID / payment status / batch / demo time?" answered from the real records,
 * never guessed by the AI.
 *
 * In the chat the student enrolled from (or one merged into it): answered straight away.
 * From any other chat: the student types the registered email, we email a 6-digit code, and the
 * answer is given only after the code is typed back.
 */
import { db, FieldValue, type Lead } from "./db";
import { formatIst } from "./lang";
import { checkOtp, sendOtp, validEmail, type FormState } from "./enroll_form";

type L3 = [string, string, string];
const T: Record<string, L3> = {
  title: ["Here are your details:", "आपकी जानकारी:", "तुमची माहिती:"],
  admission: ["🆔 Admission ID", "🆔 एडमिशन ID", "🆔 प्रवेश ID"],
  payment: ["💳 Payment", "💳 पेमेंट", "💳 पेमेंट"],
  course: ["🎓 Course", "🎓 कोर्स", "🎓 कोर्स"],
  demo: ["📅 Demo class", "📅 डेमो क्लास", "📅 डेमो क्लास"],
  call: ["📞 Counsellor call", "📞 काउंसलर कॉल", "📞 काउन्सेलर कॉल"],
  nothing: [
    "I don't see an enrolment, payment or booking yet. Tap ✅ Enroll now when you are ready, or ask me anything about the courses.",
    "अभी तक कोई एनरोलमेंट, पेमेंट या बुकिंग नहीं दिख रही। तैयार हों तो ✅ एनरोल करें, या कोर्स के बारे में कुछ भी पूछें।",
    "अजून कोणताही प्रवेश, पेमेंट किंवा बुकिंग दिसत नाही. तयार असाल तर ✅ प्रवेश घ्या, किंवा कोर्सबद्दल काहीही विचारा.",
  ],
  askEmail: [
    "To keep your details private, please type the email you used when enrolling. We will email you a 6-digit code.",
    "आपकी जानकारी सुरक्षित रखने के लिए, एनरोलमेंट वाला ईमेल लिखें। हम 6 अंकों का कोड भेजेंगे।",
    "तुमची माहिती सुरक्षित ठेवण्यासाठी, प्रवेशावेळी दिलेला ईमेल लिहा. आम्ही 6 अंकी कोड पाठवू.",
  ],
  noMatch: [
    "I couldn't find an enrolment with that email. Please check it, or type cancel.",
    "उस ईमेल से कोई एनरोलमेंट नहीं मिला। कृपया जाँचें, या cancel लिखें।",
    "त्या ईमेलने कोणताही प्रवेश सापडला नाही. कृपया तपासा, किंवा cancel लिहा.",
  ],
  codeSent: [
    "We sent a 6-digit code to {email}. Please type it here.",
    "हमने {email} पर 6 अंकों का कोड भेजा है। कृपया यहाँ लिखें।",
    "आम्ही {email} वर 6 अंकी कोड पाठवला आहे. कृपया इथे लिहा.",
  ],
  noEmail: [
    "Please ask from the same chat you enrolled from, or contact the institute: email codes are not set up yet.",
    "कृपया उसी चैट से पूछें जिससे एनरोल किया था, या संस्थान से संपर्क करें।",
    "कृपया ज्या चॅटमधून प्रवेश घेतला तिथूनच विचारा, किंवा संस्थेशी संपर्क करा.",
  ],
  wrong: ["That code is not right. Please try again, or type cancel.", "कोड सही नहीं है। फिर कोशिश करें, या cancel लिखें।", "कोड बरोबर नाही. पुन्हा प्रयत्न करा, किंवा cancel लिहा."],
  cancelled: ["OK. Ask me anything else. 🙂", "ठीक है। कुछ और पूछिए। 🙂", "ठीक आहे. आणखी काही विचारा. 🙂"],
  verified: ["✅ Verified: you are enrolled", "✅ वेरिफाइड: एडमिशन पक्का", "✅ व्हेरिफाइड: प्रवेश निश्चित"],
  receipt: ["🕒 Receipt received: confirmation within 24 hours", "🕒 रसीद मिल गई: 24 घंटे में कन्फर्मेशन", "🕒 पावती मिळाली: 24 तासांत कन्फर्मेशन"],
  awaiting: ["⏳ QR sent: waiting for your payment receipt", "⏳ QR भेजा गया: आपकी रसीद का इंतज़ार", "⏳ QR पाठवला: तुमच्या पावतीची वाट"],
  rejected: ["❌ Not verified yet: our counsellor will call you", "❌ अभी वेरिफाई नहीं: काउंसलर कॉल करेंगे", "❌ अजून व्हेरिफाय नाही: काउन्सेलर कॉल करतील"],
  form: ["📝 Enrolment form not finished", "📝 एनरोलमेंट फॉर्म अधूरा", "📝 प्रवेश अर्ज अपूर्ण"],
};

const ix = (l?: string) => (l === "hi" || l === "hinglish" ? 1 : l === "mr" || l === "marathi-english" ? 2 : 0);
const st = (k: string, l?: string, v: Record<string, string> = {}) => {
  let s = T[k][ix(l)];
  for (const [a, b] of Object.entries(v)) s = s.split(`{${a}}`).join(b);
  return s;
};

/** "admission id", "my payment status", "mera batch kab hai", "माझा प्रवेश" … */
export function isStatusQuestion(text: string): boolean {
  const t = text.toLowerCase();
  return (
    /admission\s*(id|no\b|number|status|confirm)|enrol+ment\s*(id|no\b|number|status)|application status|registration (id|status)|\bmy (admission|enrol+ment|registration|status|payment|receipt|course|batch|booking|demo|call)\b|payment status|(is|was) my payment|\bmer[ai] (admission|enrol+ment|payment|course|batch|demo|booking|id)\b|\bmaz[ai] (admission|payment|course|batch)\b/.test(t) ||
    /(मेरा|मेरी) (एडमिशन|कोर्स|बैच|पेमेंट|डेमो|आईडी)|एडमिशन (आईडी|id)|(माझा|माझी|माझे) (प्रवेश|कोर्स|बॅच|पेमेंट|डेमो)|प्रवेश (आयडी|id)/.test(text)
  );
}

type Rec = Lead & { enrollment?: Record<string, any>; admissionId?: string; callback?: Record<string, any> };

/** The student's status as chat text (null when there is nothing to report). */
export function statusText(r: Rec, lang?: string): string | null {
  const lines: string[] = [];
  const e = r.enrollment ?? {};
  const f = (e.form ?? {}) as Record<string, string>;
  const admissionId = r.admissionId ?? e.admissionId;
  if (admissionId) lines.push(`${st("admission", lang)}: ${admissionId}`);
  const pay: Record<string, string> = { verified: "verified", receipt_received: "receipt", awaiting_receipt: "awaiting", rejected: "rejected", form: "form", confirm: "form", otp: "form" };
  if (pay[e.status]) lines.push(`${st("payment", lang)}: ${st(pay[e.status], lang)}${e.amount ? ` (₹${e.amount})` : ""}`);
  const course = e.status === "verified" ? e.courseName ?? f.course : f.course ?? e.courseName;
  if (course) lines.push(`${st("course", lang)}: ${[course, f.mode, f.batch, f.start].filter(Boolean).join(" · ")}`);
  if (r.booking?.startAt) lines.push(`${st("demo", lang)}: ${r.booking.title} · ${formatIst(r.booking.startAt.toDate())}`);
  if (r.callback?.startAt?.toDate) lines.push(`${st("call", lang)}: ${formatIst(r.callback.startAt.toDate())}`);
  return lines.length ? `${st("title", lang)}\n\n${lines.join("\n")}` : null;
}

export interface StatusLookup {
  step: "email" | "otp";
  email?: string;
  targetLeadId?: string;
  otp?: FormState["otp"];
}

/** The newest lead that enrolled with this email (verified ones first). */
async function findByEmail(email: string): Promise<string | null> {
  const s = await db.collection("students").where("email", "==", email).limit(5).get();
  if (!s.empty) return String(s.docs[0].get("leadId"));
  const l = await db.collection("leads").where("enrollment.form.email", "==", email).limit(5).get();
  return l.empty ? null : l.docs[0].id;
}

export interface StatusReply {
  text: string;
  lookup?: StatusLookup | null;
}

/**
 * One turn of the status conversation. Returns null when the message is not about the status
 * (and no lookup is running).
 */
export async function statusTurn(leadId: string, lead: Rec & { statusLookup?: StatusLookup }, text: string, lang?: string): Promise<StatusReply | null> {
  const look = lead.statusLookup;
  if (look) {
    if (/^(❌\s*)?(cancel|stop|रद्द|रद्द करा)$/i.test(text.trim())) return { text: st("cancelled", lang), lookup: null };
    if (look.step === "email") {
      const email = validEmail(text);
      if (!email) return { text: st("askEmail", lang), lookup: look };
      const target = await findByEmail(email);
      if (!target) return { text: st("noMatch", lang), lookup: look };
      if (target === leadId) return { text: statusText(lead, lang) ?? st("nothing", lang), lookup: null };
      const r = await sendOtp(leadId, email, lang);
      if (!r.ok) return { text: st("noEmail", lang), lookup: null };
      return { text: st("codeSent", lang, { email }), lookup: { step: "otp", email, targetLeadId: target, otp: r.otp } };
    }
    if (look.step === "otp") {
      const c = checkOtp(leadId, look.otp, text);
      if (c !== "ok") {
        const attempts = (look.otp?.attempts ?? 0) + 1;
        if (attempts >= 5 || c === "expired") return { text: st("cancelled", lang), lookup: null };
        return { text: st("wrong", lang), lookup: { ...look, otp: look.otp ? { ...look.otp, attempts } : undefined } };
      }
      const target = (await db.doc(`leads/${look.targetLeadId}`).get()).data() as Rec | undefined;
      return { text: (target && statusText(target, lang)) ?? st("nothing", lang), lookup: null };
    }
  }
  if (!isStatusQuestion(text)) return null;
  // Same chat (or a lead merged into this one): straight answer.
  const own = statusText(lead, lang);
  if (own) return { text: own, lookup: null };
  const { emailReady } = await import("./email");
  if (!(await emailReady())) return { text: st("nothing", lang), lookup: null };
  return { text: st("askEmail", lang), lookup: { step: "email" } };
}

export async function saveLookup(leadId: string, lookup: StatusLookup | null | undefined): Promise<void> {
  if (lookup === undefined) return;
  await db.doc(`leads/${leadId}`).set({ statusLookup: lookup === null ? FieldValue.delete() : JSON.parse(JSON.stringify(lookup)) }, { merge: true });
}
