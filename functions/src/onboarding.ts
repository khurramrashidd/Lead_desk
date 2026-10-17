/**
 * Intake questions before counselling, on WhatsApp, Telegram, Instagram and the web chat:
 *
 *   1. Who is this enquiry for?      → I'm the student / I'm a parent / For a friend
 *   2. The student's name
 *   3. The student's mobile number or email (skipped when WhatsApp already gave us the number)
 *   4. The course list               → tap a course (Asha then talks about it) or "help me choose"
 *
 * Every step is a button on WhatsApp, a keyboard on Telegram and a chip on the web, and also
 * accepts typed answers (1/2/3, "papa", "मी पालक आहे", a phone number…). Nothing here calls the
 * AI, so the answers are instant and free. A voice note, a question typed twice, or a pick that
 * matches no course hands the conversation straight to Asha, so nobody is ever stuck in a form.
 *
 * Pure functions only: brain.ts reads the lead, calls [advanceOnboarding] and writes the result.
 */
import type { Course } from "./db";
import { normalizePhone } from "./identity";

export type ObLang = "en" | "hi" | "mr";
export type ObStep = "relation" | "name" | "contact" | "course" | "done";
export type ObRelation = "self" | "parent" | "sibling" | "friend" | "guardian";

export interface OnboardingState {
  step: ObStep;
  lang: ObLang;
  relation?: ObRelation;
  studentName?: string;
  phone?: string;
  email?: string;
  firstQuestion?: string;
  misses?: number;
  courseId?: string;
  wantsHelp?: boolean;
  outcome?: "completed" | "skipped" | "voice";
  /** Asha has already been told the intake answers (so the "talk about this course" hint is used once). */
  briefed?: boolean;
}

export interface ObOption {
  id: string;
  label: string;
  description?: string;
}

export interface ObReply {
  text: string;
  options: ObOption[];
  /** Telegram: show a "share my number" button. */
  askContact?: boolean;
}

export interface ObInput {
  text: string;
  /** Id of the WhatsApp button / list row that was tapped, if any. */
  choiceId?: string;
  isVoice?: boolean;
  /** The channel already gave us the writer's phone (WhatsApp). */
  phoneKnown?: boolean;
  /** Language picked on the website, or Telegram's language_code. */
  langHint?: string;
  /** The web chat already shows Asha's greeting, so the first reply skips the introduction. */
  introShown?: boolean;
  courses: Pick<Course, "id" | "name" | "durationWeeks" | "feeInr">[];
  instituteName: string;
}

export interface ObResult {
  state: OnboardingState;
  /** Scripted message to send now; absent when Asha (the AI) should answer this message. */
  reply?: ObReply;
}

// ------------------------------------------------------------------- texts
type Texts = Record<ObLang, string>;

const T = {
  intro: {
    en: "Hi! I'm Asha, admissions counsellor at {inst} 👋\nTo guide you properly: who is this enquiry for?",
    hi: "नमस्ते! मैं आशा हूँ, {inst} की एडमिशन काउंसलर 👋\nसही सलाह देने के लिए बताइए: यह पूछताछ किसके लिए है?",
    mr: "नमस्कार! मी आशा, {inst} ची प्रवेश समुपदेशक 👋\nयोग्य सल्ला देण्यासाठी सांगा: ही चौकशी कोणासाठी आहे?",
  },
  introQ: {
    en: "Hi! I'm Asha, admissions counsellor at {inst} 👋 I'll answer your question in a moment.\nFirst, who is this enquiry for?",
    hi: "नमस्ते! मैं आशा हूँ, {inst} की एडमिशन काउंसलर 👋 आपके सवाल का जवाब अभी देती हूँ।\nपहले बताइए, यह पूछताछ किसके लिए है?",
    mr: "नमस्कार! मी आशा, {inst} ची प्रवेश समुपदेशक 👋 तुमच्या प्रश्नाचं उत्तर लगेच देते.\nआधी सांगा, ही चौकशी कोणासाठी आहे?",
  },
  askWhoShort: {
    en: "Happy to help with that! 🙂 First, who is this enquiry for?",
    hi: "ज़रूर मदद करूँगी! 🙂 पहले बताइए, यह पूछताछ किसके लिए है?",
    mr: "नक्की मदत करते! 🙂 आधी सांगा, ही चौकशी कोणासाठी आहे?",
  },
  askWho: { en: "Who is this enquiry for?", hi: "यह पूछताछ किसके लिए है?", mr: "ही चौकशी कोणासाठी आहे?" },
  hello: {
    en: "Hi! I'm Asha, admissions counsellor at {inst} 👋",
    hi: "नमस्ते! मैं आशा हूँ, {inst} की एडमिशन काउंसलर 👋",
    mr: "नमस्कार! मी आशा, {inst} ची प्रवेश समुपदेशक 👋",
  },
  willAnswer: {
    en: "I'll answer your question in a moment.",
    hi: "आपके सवाल का जवाब अभी देती हूँ।",
    mr: "तुमच्या प्रश्नाचं उत्तर लगेच देते.",
  },
  relationAgain: {
    en: "Please tap one option below 👇 (or type 1, 2 or 3)",
    hi: "कृपया नीचे से एक विकल्प चुनिए 👇 (या 1, 2, 3 लिखिए)",
    mr: "कृपया खालीलपैकी एक पर्याय निवडा 👇 (किंवा 1, 2, 3 लिहा)",
  },
  nameSelf: { en: "Great! What's your name?", hi: "बढ़िया! आपका नाम क्या है?", mr: "छान! तुमचं नाव काय?" },
  nameParent: { en: "Thank you! What's the student's name?", hi: "धन्यवाद! स्टूडेंट का नाम क्या है?", mr: "धन्यवाद! विद्यार्थ्याचं नाव काय?" },
  nameFriend: {
    en: "Nice of you to help! What's your friend's name?",
    hi: "मदद करने के लिए शुक्रिया! आपके दोस्त का नाम क्या है?",
    mr: "मदत करताय, छान! तुमच्या मित्राचं नाव काय?",
  },
  nameAgain: {
    en: "Sorry, I didn't catch the name. Just the name, please 🙂",
    hi: "माफ़ कीजिए, नाम समझ नहीं आया। बस नाम लिख दीजिए 🙂",
    mr: "माफ करा, नाव समजलं नाही. फक्त नाव लिहा 🙂",
  },
  contactSelf: {
    en: "Thanks, {name}! Your mobile number or email, so our counsellor can keep your record? (or tap Skip)",
    hi: "धन्यवाद, {name}! आपका मोबाइल नंबर या ईमेल बता दीजिए, ताकि काउंसलर आपका रिकॉर्ड रख सकें (या Skip दबाइए)",
    mr: "धन्यवाद, {name}! तुमचा मोबाईल नंबर किंवा ईमेल सांगा, म्हणजे समुपदेशक तुमची नोंद ठेवू शकतील (किंवा Skip दाबा)",
  },
  contactOther: {
    en: "Thanks! {student}'s mobile number or email? It keeps one record for the admission, even if {student} writes to us later. (or tap Skip)",
    hi: "धन्यवाद! {student} का मोबाइल नंबर या ईमेल? इससे एडमिशन का एक ही रिकॉर्ड रहेगा, भले {student} बाद में खुद लिखें (या Skip दबाइए)",
    mr: "धन्यवाद! {student} चा मोबाईल नंबर किंवा ईमेल? त्यामुळे प्रवेशाची एकच नोंद राहील, {student} नंतर स्वतः लिहिलं तरी (किंवा Skip दाबा)",
  },
  contactAgain: {
    en: "That doesn't look like a 10-digit mobile number or an email. Please try again, or tap Skip.",
    hi: "यह 10 अंकों का मोबाइल नंबर या ईमेल नहीं लग रहा। फिर से लिखिए या Skip दबाइए।",
    mr: "हा 10 अंकी मोबाईल नंबर किंवा ईमेल वाटत नाही. पुन्हा लिहा किंवा Skip दाबा.",
  },
  courses: {
    en: "Got it ✅ Here are our courses 👇 Pick one and I'll tell you about it, or just ask me anything.",
    hi: "नोट कर लिया ✅ ये रहे हमारे कोर्स 👇 कोई एक चुनिए, मैं उसके बारे में बताती हूँ, या कुछ भी पूछिए।",
    mr: "नोंद केली ✅ हे आमचे कोर्सेस 👇 एक निवडा, मी त्याबद्दल सांगते, किंवा काहीही विचारा.",
  },
  nudge: {
    en: "Hi! Still there? Tap an option above or just type your question. I'm here to help 🙂",
    hi: "नमस्ते! क्या आप अभी भी हैं? ऊपर कोई विकल्प चुनिए या अपना सवाल लिखिए। मैं मदद के लिए यहाँ हूँ 🙂",
    mr: "नमस्कार! अजून आहात का? वरचा एखादा पर्याय निवडा किंवा तुमचा प्रश्न लिहा. मी मदतीसाठी इथे आहे 🙂",
  },
} satisfies Record<string, Texts>;

const RELATION_LABELS: Record<ObLang, Record<"self" | "parent" | "friend", string>> = {
  en: { self: "I'm the student", parent: "I'm a parent", friend: "For a friend" },
  hi: { self: "मैं स्टूडेंट हूँ", parent: "मैं पैरेंट हूँ", friend: "दोस्त के लिए" },
  mr: { self: "मी विद्यार्थी आहे", parent: "मी पालक आहे", friend: "मित्रासाठी" },
};
const SKIP: Texts = { en: "Skip", hi: "Skip करें", mr: "Skip करा" };
const HELP: Texts = { en: "Not sure, help me choose", hi: "पता नहीं, चुनने में मदद", mr: "माहीत नाही, मदत करा" };

function fill(s: string, vars: Record<string, string>): string {
  let out = s;
  for (const [k, v] of Object.entries(vars)) out = out.split(`{${k}}`).join(v);
  return out;
}

export function nudgeText(lang?: string): string {
  return T.nudge[asLang(lang)];
}

export function relationOptions(lang: ObLang): ObOption[] {
  const l = RELATION_LABELS[lang];
  return [
    { id: "rel:self", label: l.self },
    { id: "rel:parent", label: l.parent },
    { id: "rel:friend", label: l.friend },
  ];
}

function rupees(n?: number): string {
  if (typeof n !== "number") return "";
  return "₹" + n.toLocaleString("en-IN");
}

export function courseOptions(lang: ObLang, courses: ObInput["courses"]): ObOption[] {
  const list = courses.slice(0, 9).map((c) => ({
    id: `course:${c.id}`,
    label: c.name,
    description: [c.durationWeeks ? `${c.durationWeeks} weeks` : "", rupees(c.feeInr)].filter(Boolean).join(" · "),
  }));
  return [...list, { id: "course:help", label: HELP[lang] }];
}

// ---------------------------------------------------------------- language
export function asLang(l?: string): ObLang {
  const s = (l ?? "").toLowerCase();
  if (s.startsWith("mr") || s.includes("marathi")) return "mr";
  if (s.startsWith("hi") || s.includes("hindi")) return "hi";
  return "en";
}

/** Hindi or Marathi for Devanagari text; undefined for Latin text (the caller's hint decides). */
export function detectLang(text: string): ObLang | undefined {
  if (!/[ऀ-ॿ]/.test(text ?? "")) return undefined;
  const count = (re: RegExp) => (text.match(re) ?? []).length;
  const mr = count(/आहे|आहेत|आहात|मला|माझ|तुम्ही|तुमच|काय|कसं|करायच|नाही|हवं|पाहिजे|आम्ही|मुलगा|मुलगी|मित्रा|पालक|विद्यार्थी|स्वतः|किती|सांगा|च्या|ची |चा |चे /g);
  const hi = count(/है|हैं|हूँ|हूं|मुझे|मेरा|मेरी|मेरे|आप|क्या|कैसे|करना|नहीं|चाहिए|मैं|हम |बेटा|बेटी|दोस्त|पैरेंट|स्टूडेंट|कितनी|बताइए|का |की |के /g);
  return mr > hi ? "mr" : "hi";
}

// ---------------------------------------------------------------- parsing
const DEV_DIGITS = "०१२३४५६७८९";
function asciiDigits(s: string): string {
  return [...s].map((c) => (DEV_DIGITS.includes(c) ? String(DEV_DIGITS.indexOf(c)) : c)).join("");
}

function clean(s: string): string {
  return asciiDigits((s ?? "").normalize("NFKC")).toLowerCase().replace(/[^\p{L}\p{M}\p{N}@.+\s]/gu, " ").replace(/\s+/g, " ").trim();
}

const GREETING = /^(hi+|hello+|hey+|hii+|helo|namaste|namaskar|namasté|नमस्ते|नमस्कार|start|hola|good (morning|afternoon|evening)|hi asha|hello asha|asha)$/i;

export function isGreeting(text: string): boolean {
  return GREETING.test(clean(text)) || clean(text).length === 0;
}

/** A typed question rather than an answer to our question. */
export function looksLikeQuestion(text: string): boolean {
  const t = (text ?? "").trim();
  if (!t) return false;
  const words = t.split(/\s+/).length;
  return /[?？]/.test(t) || words >= 6 || /\b(fees?|course|batch|placement|job|emi|demo|kitni|kya|kaise|how|what|when|which|can i|is it)\b/i.test(t) || /फीस|कोर्स|बैच|किती|कितनी|क्या|काय|कसं|कैसे/.test(t);
}

export function parseRelation(text: string, choiceId?: string): ObRelation | undefined {
  if (choiceId?.startsWith("rel:")) {
    const r = choiceId.slice(4);
    if (r === "self" || r === "parent" || r === "friend") return r;
  }
  const t = clean(text);
  if (!t) return undefined;
  if (/^(1|1\.|one|a)$/.test(t)) return "self";
  if (/^(2|2\.|two|b)$/.test(t)) return "parent";
  if (/^(3|3\.|three|c)$/.test(t)) return "friend";
  for (const lang of ["en", "hi", "mr"] as ObLang[]) {
    const l = RELATION_LABELS[lang];
    if (t === clean(l.self)) return "self";
    if (t === clean(l.parent)) return "parent";
    if (t === clean(l.friend)) return "friend";
  }
  if (/\b(friend|dost|mitra|buddy|colleague)\b|दोस्त|मित्र|मैत्रीण|सहेली/.test(t)) return "friend";
  if (/\b(brother|sister|bhai|bhaiya|didi|behen|bahan|cousin)\b|भाई|बहन|भाऊ|बहीण|दीदी|ताई|दादा/.test(t)) return "sibling";
  if (/\b(uncle|aunt|aunty|guardian|mama|kaka|chacha|relative)\b|चाचा|मामा|काका|पालकत्व|गार्डियन/.test(t)) return "guardian";
  if (/\b(parent|parents|father|mother|dad|daddy|mom|mommy|mummy|mum|papa|pappa|son|daughter|my child|my kid|beta|beti|ladka|ladki)\b|पैरेंट|पालक|पिता|पापा|माता|मम्मी|मां|माँ|बेटा|बेटी|बेटे|बच्चे|बच्चा|मुलगा|मुलगी|मुलासाठी|मुलीसाठी|मुलाला|मुलीला|मुलाचं|मुलीचं|मुलाचे|मुलीचे|आई|वडील|बाबा/.test(t)) return "parent";
  if (/^(me|myself|self|mine|i am|i m|im)$/.test(t)) return "self";
  if (/\b(myself|i am the student|i m the student|im the student|i am a student|i m a student|student|for me|for myself|khud|apne liye|mere liye)\b|^मैं$|^मी$|खुद|स्वयं|मेरे लिए|मी स्वतः|स्वतः|माझ्यासाठी|विद्यार्थी|स्टूडेंट/.test(t)) return "self";
  return undefined;
}

const NAME_PREFIX =
  /^(my name is|my name's|name is|name|i am|i'm|im|this is|it's|its|he is|she is|his name is|her name is|student name is|student is|mera naam|mera nam|naam|मेरा नाम|नाम|माझं नाव|माझे नाव|माझ नाव|नाव|उसका नाम|त्याचं नाव|तिचं नाव|मी)(\s*[:\-]\s*|\s+)/i;
const NAME_SUFFIX = /\s+(hai|he|है|हैं|आहे|aahe|here|ji|जी)$/i;

/** "my name is rahul patil" → "Rahul Patil"; undefined when it is not a name. */
export function parseName(text: string): string | undefined {
  let t = (text ?? "").normalize("NFKC").replace(/[.!,;🙂😊🙏]+$/u, "").trim();
  if (!t || t.length > 60 || /[?@\d०-९]/.test(t)) return undefined;
  for (let i = 0; i < 2; i++) t = t.replace(NAME_PREFIX, "").replace(NAME_SUFFIX, "").trim();
  if (!t) return undefined;
  const words = t.split(/\s+/);
  if (words.length > 4) return undefined;
  if (!/^[\p{L}\p{M}][\p{L}\p{M}.' -]*$/u.test(t)) return undefined;
  if (isGreeting(t) || parseSkip(t) || /^(yes|no|ok|okay|haan|ha|nahi|student|parent|friend)$/i.test(t)) return undefined;
  return /[a-z]/i.test(t) ? words.map((w) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()).join(" ") : t;
}

export function parseSkip(text: string, choiceId?: string): boolean {
  if (choiceId === "skip") return true;
  const t = clean(text);
  return /^(skip|skip karen|skip करें|skip करा|later|baad me|baad mein|no|nahi|nako|not now|na)$/.test(t) || /^(नहीं|बाद में|नको|नंतर|स्किप)/.test(t);
}

export function parseContact(text: string): { phone?: string; email?: string } {
  const raw = asciiDigits(text ?? "");
  const email = raw.match(/[\w.+-]+@[\w-]+(\.[\w-]+)+/)?.[0]?.toLowerCase();
  const digits = raw.replace(/[^\d+]/g, "");
  const phone = digits.replace(/\D/g, "").length >= 10 ? normalizePhone(raw.match(/[+\d][\d\s-]{8,}\d/)?.[0] ?? digits) : undefined;
  return { ...(phone && phone.length === 10 ? { phone } : {}), ...(email ? { email } : {}) };
}

function tokens(s: string): string[] {
  return clean(s)
    .split(" ")
    .filter((w) => w.length >= 2 && !["and", "with", "the", "course", "developer", "full", "stack", "कोर्स"].includes(w));
}

const COURSE_HINTS: [RegExp, string[]][] = [
  [/java|जावा/, ["java", "fsj"]],
  [/python|पायथन/, ["python", "py"]],
  [/mern|javascript|react|node|js\b/, ["mern", "javascript"]],
  [/data|ml\b|machine|ai\b|डेटा/, ["data", "ds"]],
  [/devops|cloud|aws|docker/, ["devops", "cloud"]],
  [/test|qa\b|selenium/, ["test", "qa"]],
];

/** Course picked by tap (id), number, or name/keywords. "help" when they want help choosing. */
export function parseCourse(text: string, courses: ObInput["courses"], choiceId?: string): string | "help" | undefined {
  if (choiceId?.startsWith("course:")) return choiceId.slice(7);
  const t = clean(text);
  if (!t) return undefined;
  if (Object.values(HELP).some((h) => clean(h) === t) || /\b(help|not sure|confused|suggest|pata nahi)\b|मदद|मदत|माहीत नाही|पता नहीं/.test(t)) return "help";
  const n = Number(t.replace(/\.$/, ""));
  if (Number.isInteger(n) && n >= 1 && n <= courses.length) return courses[n - 1].id;
  for (const c of courses) if (clean(c.name) === t || clean(c.name).startsWith(t) && t.length >= 6) return c.id;
  let best: { id: string; score: number } | undefined;
  for (const c of courses) {
    const nameTokens = new Set([...tokens(c.name), c.id.toLowerCase()]);
    let score = tokens(t).filter((w) => nameTokens.has(w)).length;
    for (const [re, hints] of COURSE_HINTS) if (re.test(t) && hints.some((h) => nameTokens.has(h) || clean(c.name).includes(h))) score += 1;
    if (score > (best?.score ?? 0)) best = { id: c.id, score };
  }
  return best?.id;
}

// ------------------------------------------------------------------ steps
function askRelation(s: OnboardingState, inst: string, withQuestion: boolean, again = false, introShown = false): ObReply {
  let text: string;
  if (again) text = T.relationAgain[s.lang];
  else if (introShown) text = (withQuestion ? T.askWhoShort : T.askWho)[s.lang];
  else text = fill((withQuestion ? T.introQ : T.intro)[s.lang], { inst });
  return { text, options: relationOptions(s.lang) };
}

function askName(s: OnboardingState): ObReply {
  const key = s.relation === "self" ? "nameSelf" : s.relation === "friend" ? "nameFriend" : "nameParent";
  return { text: T[key][s.lang], options: [] };
}

function askContact(s: OnboardingState): ObReply {
  const name = s.studentName ?? "";
  const text =
    s.relation === "self"
      ? fill(T.contactSelf[s.lang], { name: name || "🙂" }).replace(", 🙂!", "!")
      : fill(T.contactOther[s.lang], { student: name || (s.lang === "en" ? "the student" : s.lang === "hi" ? "स्टूडेंट" : "विद्यार्थी") });
  return { text, options: [{ id: "skip", label: SKIP[s.lang] }], askContact: s.relation === "self" };
}

function askCourse(s: OnboardingState, input: ObInput): ObReply {
  return { text: T.courses[s.lang], options: courseOptions(s.lang, input.courses) };
}

/** After the name: ask for a contact unless the channel already gave us the student's number. */
function afterName(s: OnboardingState, input: ObInput): ObResult {
  if (s.relation === "self" && input.phoneKnown) {
    s.step = "course";
    return { state: s, reply: askCourse(s, input) };
  }
  s.step = "contact";
  s.misses = 0;
  return { state: s, reply: askContact(s) };
}

function handOff(s: OnboardingState, outcome: OnboardingState["outcome"]): ObResult {
  return { state: { ...s, step: "done", outcome } };
}

/**
 * One step of the intake. [state] is null for a brand-new conversation.
 * Returns the new state and either a scripted reply or (no reply) "let Asha answer".
 */
export function advanceOnboarding(state: OnboardingState | null | undefined, input: ObInput): ObResult {
  const text = (input.text ?? "").trim();
  const detected = detectLang(text);

  if (!state) {
    const s: OnboardingState = { step: "relation", lang: detected ?? asLang(input.langHint), misses: 0 };
    if (input.isVoice) return handOff(s, "voice");
    const rel = parseRelation(text, input.choiceId);
    const question = !isGreeting(text) && text.length > 2 && (looksLikeQuestion(text) || !rel) ? text.slice(0, 400) : undefined;
    if (question) s.firstQuestion = question;
    if (rel) {
      // "My son wants to learn Java…" already tells us who is writing: go straight to the name.
      s.relation = rel;
      s.step = "name";
      const ask = askName(s);
      if (!input.introShown) {
        const hello = fill(T.hello[s.lang], { inst: input.instituteName });
        ask.text = [hello, question ? T.willAnswer[s.lang] : "", ask.text].filter(Boolean).join(" ");
      }
      return { state: s, reply: ask };
    }
    return { state: s, reply: askRelation(s, input.instituteName, !!question, false, input.introShown) };
  }

  const s: OnboardingState = { ...state, lang: detected ?? state.lang };
  if (s.step === "done") return { state: s };
  if (input.isVoice) return handOff(s, "voice");

  switch (s.step) {
    case "relation": {
      const rel = parseRelation(text, input.choiceId);
      if (rel) {
        s.relation = rel;
        s.step = "name";
        s.misses = 0;
        return { state: s, reply: askName(s) };
      }
      s.misses = (s.misses ?? 0) + 1;
      if (!s.firstQuestion && looksLikeQuestion(text)) s.firstQuestion = text.slice(0, 400);
      if (s.misses >= 2) return handOff(s, "skipped");
      return { state: s, reply: askRelation(s, input.instituteName, false, true) };
    }
    case "name": {
      const c = parseContact(text);
      if (c.phone || c.email) {
        // They gave the number first: keep it and still ask for the name.
        s.phone = s.phone ?? c.phone;
        s.email = s.email ?? c.email;
      }
      const name = c.phone || c.email ? undefined : parseName(text);
      if (name) {
        s.studentName = name;
        if (s.phone || s.email) {
          s.step = "course";
          return { state: s, reply: askCourse(s, input) };
        }
        return afterName(s, input);
      }
      s.misses = (s.misses ?? 0) + 1;
      if (!s.firstQuestion && looksLikeQuestion(text)) s.firstQuestion = text.slice(0, 400);
      if (s.misses >= 2) {
        if (looksLikeQuestion(text)) return handOff(s, "skipped");
        return afterName(s, input);
      }
      return { state: s, reply: { text: T.nameAgain[s.lang], options: [] } };
    }
    case "contact": {
      if (parseSkip(text, input.choiceId)) {
        s.step = "course";
        return { state: s, reply: askCourse(s, input) };
      }
      const c = parseContact(text);
      if (c.phone || c.email) {
        s.phone = c.phone ?? s.phone;
        s.email = c.email ?? s.email;
        s.step = "course";
        return { state: s, reply: askCourse(s, input) };
      }
      s.misses = (s.misses ?? 0) + 1;
      if (looksLikeQuestion(text)) {
        if (!s.firstQuestion) s.firstQuestion = text.slice(0, 400);
        return handOff(s, "skipped");
      }
      if (s.misses >= 2) {
        s.step = "course";
        return { state: s, reply: askCourse(s, input) };
      }
      return { state: s, reply: { text: T.contactAgain[s.lang], options: [{ id: "skip", label: SKIP[s.lang] }], askContact: s.relation === "self" } };
    }
    case "course": {
      const pick = parseCourse(text, input.courses, input.choiceId);
      if (pick === "help") return handOff({ ...s, wantsHelp: true }, "completed");
      if (pick && input.courses.some((c) => c.id === pick)) return handOff({ ...s, courseId: pick }, "completed");
      // Anything else (a question, a course we don't run): Asha takes it from here.
      return handOff(s, "completed");
    }
  }
  return { state: s };
}

/** Lines for the AI's system prompt once the intake is finished. */
export function onboardingBrief(s: OnboardingState | undefined, courses: Pick<Course, "id" | "name">[]): string {
  if (!s || s.step !== "done") return "";
  const course = s.courseId ? courses.find((c) => c.id === s.courseId) : undefined;
  const who = s.relation === "self" ? "the student themself" : s.relation ? `a ${s.relation} of the student` : "unknown";
  const lines = [
    `Writer: ${who}.${s.studentName ? ` Student's name: ${s.studentName}.` : ""}${s.phone || s.email ? " The student's contact is saved." : ""}`,
    "Do NOT ask again who the enquiry is for, the student's name, or their contact details.",
  ];
  if (course) {
    lines.push(
      `They picked the course "${course.name}" (id ${course.id}) from the list. In this reply, tell them about THAT course from KNOWLEDGE_BASE in 3-4 short lines (what they will learn, duration, fee and EMI exactly as listed, next batch), then ask ONE question about ${s.relation === "self" ? "their" : "the student's"} background to check it is the right fit.`,
    );
  } else if (s.wantsHelp) {
    lines.push("They are not sure which course fits. Start counselling: ask about background, education and goal, one question at a time.");
  } else if (s.outcome === "completed") {
    lines.push("They typed something instead of picking a course: answer it. If they named a course we do not run, say so kindly and suggest the closest course from KNOWLEDGE_BASE.");
  }
  if (s.firstQuestion) lines.push(`Their FIRST message, before the intake questions, was: "${s.firstQuestion}". Answer it in this reply too.`);
  return lines.join("\n");
}
