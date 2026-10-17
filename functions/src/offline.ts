/**
 * When every AI provider is down or out of quota, Asha still answers instantly from the
 * knowledge base (fees, courses, batches, placement, demo slots) instead of leaving the
 * person looking at "typing…". The real AI answer follows automatically when a provider is
 * back (the message stays "unanswered" for the retry worker).
 *
 * Only knowledge-base facts are quoted, so the Guard has nothing to block.
 */
import type { KnowledgeBase, Slot } from "./db";
import { formatIst, pickLang } from "./lang";

type L = "en" | "hi" | "mr";

const H: Record<string, Record<L, string>> = {
  fees: { en: "Here are the fees from our published list:", hi: "हमारी प्रकाशित सूची के अनुसार फीस:", mr: "आमच्या प्रकाशित यादीनुसार फी:" },
  courses: { en: "These are our courses:", hi: "ये हमारे कोर्स हैं:", mr: "हे आमचे कोर्सेस आहेत:" },
  batches: { en: "Next batches:", hi: "अगले बैच:", mr: "पुढच्या बॅचेस:" },
  placement: { en: "About placement:", hi: "प्लेसमेंट के बारे में:", mr: "प्लेसमेंटबद्दल:" },
  demo: { en: "Free demo classes you can pick:", hi: "फ्री डेमो क्लास, जो आप चुन सकते हैं:", mr: "मोफत डेमो क्लास, जे तुम्ही निवडू शकता:" },
  tail: {
    en: "I'll be back with a detailed answer in a few minutes, and a counsellor can also call you.",
    hi: "कुछ ही मिनट में मैं पूरा जवाब दूँगी, और काउंसलर आपको कॉल भी कर सकते हैं।",
    mr: "काही मिनिटांत मी सविस्तर उत्तर देते, आणि समुपदेशक तुम्हाला कॉलही करू शकतात.",
  },
  intro: {
    en: "Thanks for your message! While I get you a detailed answer:",
    hi: "आपके मैसेज के लिए धन्यवाद! पूरा जवाब तैयार होने तक:",
    mr: "तुमच्या मेसेजबद्दल धन्यवाद! सविस्तर उत्तर तयार होईपर्यंत:",
  },
  weeks: { en: "weeks", hi: "हफ़्ते", mr: "आठवडे" },
  emi: { en: "EMI", hi: "EMI", mr: "EMI" },
};

function inr(n?: number): string {
  return typeof n === "number" ? "₹" + n.toLocaleString("en-IN") : "";
}

function matchCourses(kb: KnowledgeBase, text: string) {
  const t = (text ?? "").toLowerCase();
  const hits = kb.courses.filter((c) => {
    const words = `${c.name} ${c.id}`.toLowerCase().split(/[^a-z0-9]+/).filter((w) => w.length >= 3 && !["full", "stack", "developer", "with", "and"].includes(w));
    return words.some((w) => t.includes(w)) || (/जावा/.test(t) && /java/i.test(c.name)) || (/पायथन/.test(t) && /python/i.test(c.name));
  });
  return hits.length ? hits : kb.courses;
}

export type OfflineIntent = "fees" | "courses" | "batches" | "placement" | "demo";

export function offlineIntent(text: string): OfflineIntent {
  const t = (text ?? "").toLowerCase();
  if (/fee|fees|cost|price|kitni|kitna|emi|installment|फीस|फी |फी$|शुल्क|किती|कितनी|पैसे/.test(t)) return "fees";
  if (/placement|job|salary|naukri|नौकरी|नोकरी|प्लेसमेंट|जॉब/.test(t)) return "placement";
  if (/demo|book|visit|डेमो|बुक/.test(t)) return "demo";
  if (/batch|start|timing|schedule|kab|when|बैच|बॅच|कब|केव्हा|कधी/.test(t)) return "batches";
  return "courses";
}

/** A short, factual reply built only from the knowledge base. */
export function offlineAnswer(kb: KnowledgeBase, text: string, language: string | undefined, slots: Slot[] = []): string {
  const l = pickLang(language) as L;
  const intent = offlineIntent(text);
  const courses = intent === "courses" ? kb.courses : matchCourses(kb, text);
  let body: string[] = [];
  switch (intent) {
    case "fees":
      body = courses.map((c) => `• ${c.name}: ${inr(c.feeInr)}${c.emi ? ` (${H.emi[l]} ${c.emi.months} × ${inr(c.emi.perMonthInr)})` : ""}`);
      break;
    case "batches":
      body = courses.map((c) => `• ${c.name}: ${c.nextBatch ?? "-"}`);
      break;
    case "placement":
      body = [kb.policies?.placement ?? kb.policies?.placements ?? ""].filter(Boolean);
      if (!body.length) body = kb.courses.map((c) => `• ${c.name}: ${c.outcomes ?? ""}`);
      break;
    case "demo": {
      const demos = slots.filter((s) => (s.kind ?? "demo") === "demo").slice(0, 3);
      body = demos.length ? demos.map((s) => `• ${s.title}: ${formatIst(s.startAt.toDate())}`) : kb.courses.map((c) => `• ${c.name}: ${c.nextBatch ?? "-"}`);
      break;
    }
    default:
      body = kb.courses.map((c) => `• ${c.name} (${c.durationWeeks} ${H.weeks[l]}, ${inr(c.feeInr)})`);
  }
  return [H.intro[l], H[intent][l], ...body.slice(0, 8), "", H.tail[l]].join("\n").trim();
}
