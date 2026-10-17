/** IST helpers and short system messages in English, Hindi and Marathi. */

const IST_OFFSET_MS = 330 * 60_000;
const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** "Sat, 18 Oct · 11:00 AM IST" */
export function formatIst(d: Date): string {
  const t = new Date(d.getTime() + IST_OFFSET_MS);
  const h24 = t.getUTCHours();
  const h12 = h24 % 12 === 0 ? 12 : h24 % 12;
  const mm = String(t.getUTCMinutes()).padStart(2, "0");
  const ampm = h24 < 12 ? "AM" : "PM";
  return `${DAYS[t.getUTCDay()]}, ${t.getUTCDate()} ${MONTHS[t.getUTCMonth()]} · ${h12}:${mm} ${ampm} IST`;
}

/** Hour of day (0-23) in IST. */
export function istHour(d: Date): number {
  return new Date(d.getTime() + IST_OFFSET_MS).getUTCHours();
}

/**
 * Follow-ups never land between 9 PM and 9 AM IST.
 * Anything scheduled in quiet hours moves to 10 AM IST.
 */
export function respectQuietHours(d: Date): Date {
  const h = istHour(d);
  if (h >= 9 && h < 21) return d;
  const t = new Date(d.getTime() + IST_OFFSET_MS);
  if (h >= 21) t.setUTCDate(t.getUTCDate() + 1);
  t.setUTCHours(10, 0, 0, 0);
  return new Date(t.getTime() - IST_OFFSET_MS);
}

function gcalStamp(d: Date): string {
  return d.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
}

export function googleCalendarUrl(title: string, start: Date, durationMin: number, details: string, location: string): string {
  const end = new Date(start.getTime() + durationMin * 60_000);
  const p = new URLSearchParams({
    action: "TEMPLATE",
    text: title,
    dates: `${gcalStamp(start)}/${gcalStamp(end)}`,
    details,
    location,
    ctz: "Asia/Kolkata",
  });
  return `https://calendar.google.com/calendar/render?${p.toString()}`;
}

type Lang = "en" | "hi" | "mr";

export function pickLang(language?: string): Lang {
  const l = (language ?? "").toLowerCase();
  if (l.startsWith("mr") || l.includes("marathi")) return "mr";
  if (l.startsWith("hi") || l.includes("hindi") || l.includes("hinglish")) return "hi";
  return "en";
}

const T: Record<string, Record<Lang, string>> = {
  booked: {
    en: "✅ Demo class booked: {title}, {when}. Add it to your calendar: {url}",
    hi: "✅ आपकी डेमो क्लास बुक हो गई: {title}, {when}. कैलेंडर में जोड़ें: {url}",
    mr: "✅ तुमचा डेमो क्लास बुक झाला: {title}, {when}. कॅलेंडरमध्ये जोडा: {url}",
  },
  slotFull: {
    en: "Sorry, that slot just filled up. Could you pick another time?",
    hi: "माफ़ कीजिए, वह स्लॉट अभी भर गया। क्या आप कोई और समय चुनेंगे?",
    mr: "माफ करा, तो स्लॉट आत्ताच भरला. दुसरी वेळ निवडाल का?",
  },
  remind24: {
    en: "⏰ Reminder: your demo class {title} is tomorrow, {when}. Reply here if you need to change it.",
    hi: "⏰ याद दिला दें: आपकी डेमो क्लास {title} कल है, {when}. बदलना हो तो यहीं बताइए।",
    mr: "⏰ आठवण: तुमचा डेमो क्लास {title} उद्या आहे, {when}. बदल हवा असल्यास इथेच कळवा.",
  },
  remind1: {
    en: "⏰ Your demo class {title} starts in 1 hour ({when}). See you there!",
    hi: "⏰ आपकी डेमो क्लास {title} 1 घंटे में शुरू होगी ({when}). मिलते हैं!",
    mr: "⏰ तुमचा डेमो क्लास {title} 1 तासात सुरू होईल ({when}). भेटूया!",
  },
  safeFallback: {
    en: "I want to give you only accurate information, so I'll have our counsellor confirm this for you shortly. Meanwhile, is there anything else about the course I can help with?",
    hi: "मैं आपको सिर्फ़ सही जानकारी देना चाहती हूँ, इसलिए हमारे काउंसलर जल्द ही यह कन्फ़र्म करेंगे। तब तक कोर्स के बारे में और कुछ पूछना है?",
    mr: "मला तुम्हाला फक्त अचूक माहितीच द्यायची आहे, म्हणून आमचे काउन्सेलर लवकरच हे कन्फर्म करतील. तोपर्यंत कोर्सबद्दल अजून काही विचारायचं आहे का?",
  },
  nudge: {
    en: "Hi! Just checking in — do you have any questions about the course or the free demo class? I'm happy to help.",
    hi: "नमस्ते! बस पूछना था — कोर्स या फ्री डेमो क्लास के बारे में कोई सवाल है? मैं मदद के लिए यहाँ हूँ।",
    mr: "नमस्कार! फक्त विचारायचं होतं — कोर्स किंवा मोफत डेमो क्लासबद्दल काही प्रश्न आहेत का? मी मदत करायला इथे आहे.",
  },
  callBooked: {
    en: "✅ Booked: a counsellor will {kind} you on {when}. You'll get a reminder before it.",
    hi: "✅ बुक हो गया: हमारे काउंसलर {when} पर आपको {kind} करेंगे। पहले रिमाइंडर मिलेगा।",
    mr: "✅ बुक झालं: आमचे काउन्सेलर {when} ला तुम्हाला {kind} करतील. आधी आठवण मिळेल.",
  },
  busy: {
    en: "Thanks for your message! Our counsellor will reply in a few minutes.",
    hi: "आपके मैसेज के लिए धन्यवाद! हमारे काउंसलर कुछ ही मिनट में जवाब देंगे।",
    mr: "तुमच्या मेसेजबद्दल धन्यवाद! आमचे काउन्सेलर काही मिनिटांत उत्तर देतील.",
  },
};

export function t(key: keyof typeof T, language: string | undefined, vars: Record<string, string> = {}): string {
  let s = T[key][pickLang(language)];
  for (const [k, v] of Object.entries(vars)) s = s.split(`{${k}}`).join(v);
  return s;
}
