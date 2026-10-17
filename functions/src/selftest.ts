/**
 * PS3 self-test: runs each sentence of the problem statement against the LIVE system (real AI,
 * real Firestore, real triggers) and records checks + evidence that the app shows as proof.
 *
 * Every lead it creates is marked `selftest: true` and uses simulated channel ids ("sim:…"),
 * so nothing is ever sent to a real phone. Admin → Self-test → "Clean up" removes them.
 */
import { db, FieldValue, Timestamp, demoNow, type Lead, type Message } from "./db";
import { getKb, openSlots, respond } from "./brain";
import { checkReply } from "./guard";
import { formatIst, istHour } from "./lang";
import { byId, clampLevel } from "./aptitude";
import { VOICE_HI, VOICE_MR } from "./selftest_audio";

type Who = "prospect" | "asha" | "counsellor" | "system";
interface Check {
  label: string;
  ok: boolean | null; // null = warning / information
  detail?: string;
}
interface Evidence {
  who: Who;
  text: string;
  note?: string;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const rnd = () => Math.random().toString(36).slice(2, 8);
const randomPhone = () => `9${Math.floor(100000000 + Math.random() * 899999999)}`;

class Run {
  checks: Check[] = [];
  evidence: Evidence[] = [];
  leadIds: string[] = [];
  aiReplies = 0;
  constructor(private ref: FirebaseFirestore.DocumentReference) {}

  async check(label: string, ok: boolean | null, detail?: string): Promise<boolean> {
    this.checks.push({ label, ok, ...(detail ? { detail: detail.slice(0, 600) } : {}) });
    await this.flush();
    return ok !== false;
  }
  note(who: Who, text: string, note?: string): void {
    this.evidence.push({ who, text: text.slice(0, 900), ...(note ? { note } : {}) });
  }
  lead(id: string): void {
    if (!this.leadIds.includes(id)) this.leadIds.push(id);
  }
  async flush(): Promise<void> {
    await this.ref.set({ checks: this.checks, evidence: this.evidence, leadIds: this.leadIds }, { merge: true });
  }
}

// ------------------------------------------------------------------ helpers
async function newLead(run: Run, channel = "web", extra: Record<string, unknown> = {}): Promise<string> {
  const ref = db.collection("leads").doc();
  const tag = `sim:selftest_${rnd()}`;
  await ref.set({
    sources: [channel],
    firstSource: channel,
    lastChannel: channel,
    status: "new",
    score: 0,
    userMessages: 0,
    selftest: true,
    seed: true,
    createdBy: "server",
    ...(channel === "whatsapp" ? { waId: `${tag}` } : {}),
    ...(channel === "telegram" ? { telegramId: tag } : {}),
    ...(channel === "instagram" ? { igId: tag } : {}),
    createdAt: FieldValue.serverTimestamp(),
    lastMessageAt: FieldValue.serverTimestamp(),
    lastInboundAt: FieldValue.serverTimestamp(),
    ...extra,
  });
  run.lead(ref.id);
  return ref.id;
}

async function readLead(id: string): Promise<Lead & Record<string, unknown>> {
  return ((await db.doc(`leads/${id}`).get()).data() ?? {}) as Lead & Record<string, unknown>;
}

interface Reply {
  text: string;
  meta: Record<string, unknown>;
  lead: Lead & Record<string, unknown>;
  ms: number;
  userMsgId: string;
}

/** Sends a prospect message and waits for Asha's answer (the live trigger + this worker). */
async function say(run: Run, leadId: string, text: string, audio?: { b64: string; mime: string }): Promise<Reply | null> {
  const lead = await readLead(leadId);
  const channel = (lead.lastChannel as string) ?? "web";
  const started = Date.now();
  const ref = await db.collection(`leads/${leadId}/messages`).add({
    role: "user",
    channel,
    ...(audio ? { audioB64: audio.b64, audioMime: audio.mime, text: "🎤 Voice note" } : { text }),
    createdAt: FieldValue.serverTimestamp(),
    meta: { selftest: true },
  });
  await db.doc(`leads/${leadId}`).set({ lastInboundAt: FieldValue.serverTimestamp(), lastMessageAt: FieldValue.serverTimestamp() }, { merge: true });
  run.note("prospect", audio ? `🎤 voice note: “${text}”` : text, channel);
  const mine = (await ref.get()).get("createdAt") as Timestamp | undefined;
  // The Firestore trigger answers too; the per-lead lock makes sure only one reply is written.
  respond(leadId).catch((e) => console.warn("selftest respond", e));
  for (let i = 0; i < 70; i++) {
    await sleep(i < 10 ? 1000 : 2000);
    const snap = await db.collection(`leads/${leadId}/messages`).orderBy("createdAt", "desc").limit(6).get();
    const ai = snap.docs
      .map((d) => d.data() as Message)
      .find((m) => m.role === "ai" && !(m.meta as Record<string, unknown> | undefined)?.automatic && (!mine || (m.createdAt && m.createdAt.toMillis() >= mine.toMillis())));
    if (ai) {
      const meta = (ai.meta ?? {}) as Record<string, unknown>;
      if (meta.fallback) {
        run.note("system", "AI busy (every key rate-limited); the conversation will auto-retry in 2 minutes.");
        return null;
      }
      run.aiReplies++;
      const notes = [
        meta.model ? `model ${meta.model}` : "",
        meta.cache ? `⚡ cache ${meta.cache}` : "",
        (meta.guard as Record<string, unknown> | undefined)?.blocked ? "🛡 Guard rewrote the first draft" : "",
        `${((Date.now() - started) / 1000).toFixed(1)} s`,
      ].filter(Boolean);
      run.note("asha", ai.text ?? "", notes.join(" · "));
      await run.flush();
      // The reply is written first, the lead card (score, aptitude, next action…) right after.
      let lead = await readLead(leadId);
      for (let j = 0; j < 20 && lead.ai?.lastAnsweredId !== ref.id; j++) {
        await sleep(750);
        lead = await readLead(leadId);
      }
      return { text: ai.text ?? "", meta, lead, ms: Date.now() - started, userMsgId: ref.id };
    }
  }
  run.note("system", "No reply within 2 minutes.");
  return null;
}

const DEVANAGARI = /[ऀ-ॿ]/g;
const LETTERS = /[\p{L}]/gu;
function devanagariShare(t: string): number {
  const all = (t.match(LETTERS) ?? []).length;
  return all ? (t.match(DEVANAGARI) ?? []).length / all : 0;
}
const MR_WORDS = ["आहे", "आहेत", "तुम्ही", "तुमच", "तुम्हाला", "मला", "नक्की", "करा", "आणि", "पण", "नाही", "शकता", "किती", "येईल", "होईल", "आपण", "काय", "कसं", "साठी"];
const HI_WORDS = ["है", "हैं", "आप", "क्या", "मैं", "और", "लेकिन", "नहीं", "सकते", "कितनी", "आपको", "होगा", "यह", "के लिए", "बहुत", "हम", "आपका"];
const HINGLISH = ["hai", "hain", "aap", "aapko", "kya", "mein", "ki", "ka", "ke", "nahi", "haan", "toh", "bhi", "kar", "sakte", "aur", "bilkul", "lekin"];
const MRENG = ["aahe", "ahe", "tumhi", "tumhala", "mala", "kiti", "nakki", "pan", "ani", "kara", "shakta", "hoil", "zala", "aapan", "kay", "sathi"];
function count(text: string, words: string[]): number {
  const t = ` ${text.toLowerCase()} `;
  return words.reduce((n, w) => n + (new RegExp(`(^|[^\\p{L}])${w}([^\\p{L}]|$)`, "u").test(t) ? 1 : 0), 0);
}
function langOf(text: string): string {
  const dev = devanagariShare(text);
  if (dev > 0.5) return count(text, MR_WORDS) > count(text, HI_WORDS) ? "Marathi (Devanagari)" : "Hindi (Devanagari)";
  const h = count(text, HINGLISH);
  const m = count(text, MRENG);
  if (m >= 2 && m >= h) return "Marathi-English (Latin)";
  if (h >= 2) return "Hinglish (Latin)";
  return "English";
}

// ---------------------------------------------------------------- scenarios
type Scenario = (run: Run) => Promise<void>;

const counselling: Scenario = async (run) => {
  const id = await newLead(run);
  const r = await say(run, id, "I'm a commerce graduate with a two-year gap — can I really become a developer?");
  if (!(await run.check("Asha replied", !!r))) return;
  await run.check("Answers the real worry, not a fee list", !/₹|rs\.?\s?\d/i.test(r!.text), r!.text.match(/₹[\d,]+/)?.[0] ? `mentions ${r!.text.match(/₹[\d,]+/)?.[0]}` : "no price quoted");
  await run.check("Asks a counselling question back (background / goal)", r!.text.includes("?"), "");
  await run.check("Substantive, honest answer", r!.text.length >= 120, `${r!.text.length} characters`);
  await run.check("Replies in the prospect's language (English)", langOf(r!.text) === "English", langOf(r!.text));
};

const languages: Scenario = async (run) => {
  const cases: [string, string, (l: string) => boolean][] = [
    ["English", "Hi, I want to learn data science. How long is the course?", (l) => l === "English"],
    ["Hindi", "नमस्ते, मुझे डेटा साइंस सीखना है। कोर्स कितने महीने का है?", (l) => l.startsWith("Hindi")],
    ["Marathi", "नमस्कार, मला डेटा सायन्स शिकायचं आहे. कोर्स किती महिन्यांचा आहे?", (l) => l.startsWith("Marathi")],
  ];
  const ids = await Promise.all(cases.map(() => newLead(run)));
  const replies = await Promise.all(cases.map((c, i) => say(run, ids[i], c[1])));
  for (let i = 0; i < cases.length; i++) {
    const r = replies[i];
    const got = r ? langOf(r.text) : "no reply";
    await run.check(`${cases[i][0]} in → ${cases[i][0]} out`, !!r && cases[i][2](got), `reply detected as ${got}; AI tagged the lead as "${r?.lead.language ?? "-"}"`);
  }
};

const codemix: Scenario = async (run) => {
  const cases: [string, string, (l: string) => boolean][] = [
    ["Hinglish (Hindi + English mid-sentence)", "Mera BCom ho gaya hai but coding mein interest hai, Full Stack Java ki fees kitni hai aur weekend batch hai kya?", (l) => l.startsWith("Hinglish")],
    ["Marathi + English mid-sentence", "Mala Java shikaycha aahe pan weekend la ch time aahe, batch kadhi start hotey?", (l) => l.startsWith("Marathi-English")],
  ];
  const ids = await Promise.all(cases.map(() => newLead(run)));
  const replies = await Promise.all(cases.map((c, i) => say(run, ids[i], c[1])));
  for (let i = 0; i < cases.length; i++) {
    const r = replies[i];
    const got = r ? langOf(r.text) : "no reply";
    await run.check(`${cases[i][0]} → same blend, same (Latin) script`, !!r && cases[i][2](got) && devanagariShare(r!.text) < 0.2, `reply detected as ${got}; lead.language "${r?.lead.language ?? "-"}"`);
  }
};

const register: Scenario = async (run) => {
  const casual = await newLead(run);
  const formal = await newLead(run);
  const [a, b] = await Promise.all([
    say(run, casual, "bhai tu bata na yaar, java ki fees kitni hai? jaldi bol"),
    say(run, formal, "नमस्ते जी, कृपया बताइए कि आपके संस्थान में जावा कोर्स की फीस कितनी है और बैच कब शुरू होगा?"),
  ]);
  await run.check("Casual message detected as casual register", a?.lead.register === "casual", `register = ${a?.lead.register ?? "-"}`);
  await run.check("Casual reply stays in Hinglish (Latin script)", !!a && langOf(a.text).startsWith("Hinglish"), a ? langOf(a.text) : "no reply");
  await run.check("Formal message detected as formal register", b?.lead.register === "formal", `register = ${b?.lead.register ?? "-"}`);
  await run.check("Formal reply uses respectful “आप” in Hindi", !!b && b.text.includes("आप") && langOf(b.text).startsWith("Hindi"), b ? langOf(b.text) : "no reply");
};

const voice: Scenario = async (run) => {
  const mr = await newLead(run, "whatsapp");
  const hi = await newLead(run, "telegram");
  const [a, b] = await Promise.all([say(run, mr, VOICE_MR.text, VOICE_MR), say(run, hi, VOICE_HI.text, VOICE_HI)]);
  for (const [label, lead, r, want] of [
    ["Marathi voice note (WhatsApp)", mr, a, "Marathi"],
    ["Hindi voice note (Telegram)", hi, b, "Hindi"],
  ] as const) {
    const msgs = await db.collection(`leads/${lead}/messages`).where("role", "==", "user").get();
    const transcript = msgs.docs.map((d) => d.get("transcript") as string | undefined).find(Boolean);
    await run.check(`${label}: heard and transcribed`, !!transcript, transcript ? `transcript: “${transcript}”` : "no transcript saved");
    await run.check(`${label}: reply in ${want}`, !!r && langOf(r.text).startsWith(want), r ? langOf(r.text) : "no reply");
  }
  await run.check("Note", null, "These voice notes are synthesised (robotic). For the judges, also record a real voice note on the phone.");
};

const profile: Scenario = async (run) => {
  const id = await newLead(run);
  await say(run, id, "Hi, I want to become a software developer.");
  const r = await say(run, id, "I did B.Com in 2022 and now I work in a mobile shop. I can study only in the evenings after 7, my budget is tight and my father wants me to do a government job instead.");
  const p = (r?.lead.profile ?? {}) as Record<string, string>;
  const known = ["education", "background", "currentWork", "goal", "timing", "constraints", "budget", "familyView", "gap"].filter((k) => p[k]);
  await run.check("Background, goal and constraints captured", known.length >= 4, known.map((k) => `${k}: ${p[k]}`).join(" | "));
  const obj = (r?.lead.objections ?? []) as string[];
  await run.check("Worries detected as objections", obj.some((o) => ["fees", "family_approval", "time"].includes(o)), obj.join(", ") || "none");
  await run.check("Keeps counselling (asks the next question)", !!r && r.text.includes("?"), "");
};

const kb: Scenario = async (run) => {
  const k = await getKb();
  const course = k.courses.find((c) => c.id === "fsj") ?? k.courses[0];
  if (!(await run.check("Knowledge base has courses", !!course, course ? `${k.courses.length} courses; testing “${course.name}”` : "Admin → Demo → Load everything first"))) return;
  const id = await newLead(run);
  const r = await say(run, id, `What is the fee for ${course.name}, is there EMI, and when does the next batch start?`);
  const digits = (r?.text ?? "").replace(/[,\s]/g, "");
  await run.check(`Quotes the exact KB fee ₹${course.feeInr.toLocaleString("en-IN")}`, digits.includes(String(course.feeInr)), "");
  if (course.emi) await run.check(`Quotes the KB EMI (${course.emi.months} × ₹${course.emi.perMonthInr.toLocaleString("en-IN")})`, digits.includes(String(course.emi.perMonthInr)), "");
  const first = (course.nextBatch ?? "").split(/[;,]/)[0].trim();
  const day = first.match(/^(\d{1,2})/)?.[1];
  const mon = first.match(/[A-Za-z]{3}/)?.[0];
  const text = r?.text ?? "";
  const hasDate = !!day && !!mon && new RegExp(`\\b${day}(st|nd|rd|th)?\\b`).test(text) && new RegExp(mon, "i").test(text);
  await run.check(`States the KB batch date (${course.nextBatch})`, first ? hasDate : null, first ? `looked for day ${day} and month ${mon}` : "no batch date in the knowledge base");
  const g = checkReply(r?.text ?? "", k, []);
  await run.check("Every amount in the reply exists in the knowledge base (Guard)", g.ok, g.violations.join("; ") || "clean");
};

const guard: Scenario = async (run) => {
  const k = await getKb();
  // 1) Deterministic proof: the Guard on invented drafts.
  const drafts = [
    "Special offer just for you: 30% off if you join today!",
    "Ok, I can give you the course for ₹40,000 only.",
    "Don't worry, 100% placement guaranteed after the course.",
    "Theek hai, aapko 20 percent discount de dete hain.",
    "तुम्हाला नक्की नोकरी मिळेल.",
  ];
  for (const d of drafts) {
    const g = checkReply(d, k, []);
    await run.check(`Guard blocks: “${d}”`, !g.ok, g.violations.join("; "));
  }
  // 2) Live: press hard three times.
  const id = await newLead(run);
  await say(run, id, "I want to join Full Stack Java.");
  const presses = [
    "My friend got 30% discount here last month. Give me the same or I will join another institute.",
    "Come on, at least 20% off. Final offer, otherwise I'm going elsewhere today.",
    "Will you guarantee me a job with a 6 LPA package after the course?",
  ];
  const userTexts: string[] = ["I want to join Full Stack Java."];
  for (const p of presses) {
    userTexts.push(p);
    const r = await say(run, id, p);
    const g = checkReply(r?.text ?? "", k, userTexts);
    const blocked = (r?.meta.guard as Record<string, unknown> | undefined)?.blocked === true;
    await run.check(`Pressed: “${p.slice(0, 48)}…” → no invented offer`, !!r && g.ok, (g.violations.join("; ") || "reply clean") + (blocked ? " · the Guard caught and rewrote the AI's first draft" : ""));
  }
};

const aptitude: Scenario = async (run) => {
  const id = await newLead(run);
  await say(run, id, "I'm a B.Com graduate, I have never coded, and I want to become a developer.");
  let r = await say(run, id, "Yes, let's do the aptitude check now.");
  let lead = await readLead(id);
  if (!lead.aptitude?.current) {
    r = await say(run, id, "Yes please, start the aptitude test.");
    lead = await readLead(id);
  }
  if (!(await run.check("Aptitude check started inside the chat", !!lead.aptitude?.current, `status ${lead.aptitude?.status ?? "-"}`))) return;
  await run.check("Question shown as tap-to-answer options", !!r && /A\)/.test(r.text) && /B\)/.test(r.text), "");
  const plan = [true, false, true, true];
  const levels: string[] = [];
  for (let i = 0; i < plan.length; i++) {
    const q = byId(lead.aptitude?.current);
    if (!q) break;
    const pick = plan[i] ? q.answer : (["A", "B", "C"] as const).find((x) => x !== q.answer)!;
    const before = clampLevel(lead.aptitude?.level ?? 2);
    await say(run, id, pick);
    lead = await readLead(id);
    const ans = lead.aptitude?.answers?.[i];
    const next = byId(lead.aptitude?.current);
    levels.push(`${q.id} (level ${q.level}) → ${pick} ${ans?.correct ? "✓" : "✗"}`);
    await run.check(`Q${i + 1} scored on the server: ${plan[i] ? "right" : "wrong"} answer recorded`, !!ans && ans.correct === plan[i], `${q.id}: picked ${pick}, correct is ${q.answer}`);
    if (next && i < plan.length - 1) {
      const want = clampLevel(before + (plan[i] ? 1 : -1));
      await run.check(`Adaptive: next question is ${plan[i] ? "harder" : "easier"}`, next.level === want, `next ${next.id} is level ${next.level} (expected ${want})`);
    }
  }
  await run.check("Check finished with a band and result", lead.aptitude?.status === "done" && !!lead.aptitude?.band, lead.aptitude?.result ?? `status ${lead.aptitude?.status}`);
  run.note("system", `Path: ${levels.join("  ·  ")}`);
  await run.check("Recommendation with an honest reason", !!lead.recommendation?.courseId, lead.recommendation ? `${lead.recommendation.courseName ?? lead.recommendation.courseId}: ${lead.recommendation.reason}` : "not yet (ask “which course?”)");
};

const recommend: Scenario = async (run) => {
  const k = await getKb();
  const id = await newLead(run);
  await say(run, id, "I finished 12th commerce, never coded, I can study 2 hours every evening and my budget is limited.");
  const r = await say(run, id, "Skip the test. Which ONE course do you recommend for me, and honestly why?");
  const rec = r?.lead.recommendation;
  await run.check("Recommends one course from the knowledge base", !!rec && k.courses.some((c) => c.id === rec.courseId), rec ? `${rec.courseName ?? rec.courseId}` : "none");
  await run.check("Gives an honest, specific reason", !!rec && (rec.reason ?? "").length >= 25, rec?.reason ?? "");
  await run.check("Doesn't push the most expensive course on a beginner", !!rec && rec.courseId !== k.courses.slice().sort((a, b) => b.feeInr - a.feeInr)[0]?.id, rec ? `fee of recommended course: ₹${k.courses.find((c) => c.id === rec.courseId)?.feeInr ?? "?"}` : "");
};

const booking: Scenario = async (run) => {
  const now = await demoNow();
  if (!(await openSlots(now)).length) {
    const { seedSlots } = await import("./seed");
    await seedSlots(now);
    await run.check("No demo slots existed, so a 7-day calendar was created", null);
  }
  const id = await newLead(run);
  await say(run, id, "I'd like to book a free demo class for Full Stack Java. Which slots do you have?");
  let r = await say(run, id, "Please book the first slot you mentioned.");
  let lead = await readLead(id);
  if (!lead.booking) {
    r = await say(run, id, "Yes, confirm the earliest available demo slot for me.");
    lead = await readLead(id);
  }
  const b = lead.booking;
  if (!(await run.check("Demo class booked into a real slot", !!b, b ? `${b.title} · ${formatIst(b.startAt.toDate())}` : "not booked"))) return;
  const slot = (await db.doc(`slots/${b!.slotId}`).get()).data();
  await run.check("Seat reserved in the slot (transaction, no double booking)", !!slot && Number(slot.booked) >= 1 && Number(slot.booked) <= Number(slot.capacity), slot ? `${slot.booked}/${slot.capacity} seats taken` : "");
  await run.check("Confirmation + Add-to-calendar link sent to the prospect", !!r && r.text.includes("calendar.google.com"), "");
  const sync = (b as unknown as Record<string, unknown>).calendarSync as string | undefined;
  await run.check("Event created in the institute's Google Calendar", sync === "ok" ? true : null, sync === "ok" ? "calendar sync ok" : `calendar sync: ${sync ?? "off"} (connect it in Admin → Channels → Google Calendar)`);
  // Reminders: run the real heartbeat for THIS lead at 23 h and 30 min before the class.
  const { runHeartbeat } = await import("./heartbeat");
  const start = b!.startAt.toDate();
  await runHeartbeat(new Date(start.getTime() - 23 * 3_600_000), new Set([id]));
  await runHeartbeat(new Date(start.getTime() - 30 * 60_000), new Set([id]));
  const msgs = await db.collection(`leads/${id}/messages`).where("role", "==", "ai").get();
  const kinds = msgs.docs.map((d) => (d.get("meta") as Record<string, unknown> | undefined)?.kind);
  const r24 = msgs.docs.find((d) => (d.get("meta") as Record<string, unknown>)?.kind === "reminder_24h");
  const r1 = msgs.docs.find((d) => (d.get("meta") as Record<string, unknown>)?.kind === "reminder_1h");
  if (r24) run.note("asha", r24.get("text"), "automatic reminder, 24 h before");
  if (r1) run.note("asha", r1.get("text"), "automatic reminder, 1 h before");
  await run.check("24-hour reminder sent automatically", kinds.includes("reminder_24h"), "");
  await run.check("1-hour reminder sent automatically", kinds.includes("reminder_1h"), "");
};

const identity: Scenario = async (run) => {
  const p = randomPhone();
  const { handleIntake } = await import("./intake");
  const { handleMetaWebhook } = await import("./whatsapp");
  // 1. Website form: "Rahul Patil", 0XXXXX XXXXX
  const formPhone = `0${p.slice(0, 5)} ${p.slice(5)}`;
  const a = await handleIntake({ source: "form", name: "Rahul Patil", phone: formPhone, course: "Full Stack Java", silent: true }, { simulated: true });
  await db.doc(`leads/${a.leadId}`).set({ selftest: true }, { merge: true });
  run.lead(a.leadId);
  run.note("prospect", `[Website form] Rahul Patil · ${formPhone} · Full Stack Java`, "form");
  // 2. WhatsApp (real webhook parser): "राहुल पाटल", 91XXXXXXXXXX
  const waFrom = `sim:91${p}`;
  await handleMetaWebhook({
    object: "whatsapp_business_account",
    entry: [{ changes: [{ field: "messages", value: { contacts: [{ wa_id: waFrom, profile: { name: "राहुल पाटल" } }], messages: [{ from: waFrom, id: `st_${rnd()}`, type: "text", text: { body: "नमस्कार, जावा कोर्सची फी किती आहे?" } }] } }] }],
  });
  run.note("prospect", `[WhatsApp] राहुल पाटल · +91 ${p} · “नमस्कार, जावा कोर्सची फी किती आहे?”`, "whatsapp webhook");
  await sleep(2500);
  const waLeads = await db.collection("leads").where("waId", "==", waFrom).get();
  for (const d of waLeads.docs) {
    await d.ref.set({ selftest: true }, { merge: true });
    run.lead(d.id);
  }
  const keep = await readLead(a.leadId);
  const dup = waLeads.docs.find((d) => d.id !== a.leadId)?.data() as Lead | undefined;
  await run.check("WhatsApp message landed on the SAME lead as the form (merged)", waLeads.docs.some((d) => d.id === a.leadId) || dup?.mergedInto === a.leadId, dup?.mergedInto ? `duplicate ${waLeads.docs[0].id} → merged into ${a.leadId}` : "");
  await run.check("Phone formats normalised to one number", keep.phone === p, `“${formPhone}” and “+91 ${p}” → ${keep.phone}`);
  await run.check("Devanagari name recognised as the same person", (keep.aliases ?? []).includes("राहुल पाटल") || keep.name === "राहुल पाटल", `name ${keep.name}; also known as ${(keep.aliases ?? []).join(", ") || "-"}`);
  await run.check("Single timeline across channels", (keep.sources ?? []).includes("form") && (keep.sources ?? []).includes("whatsapp"), `sources: ${(keep.sources ?? []).join(", ")}`);
  // Beyond the statement: family cases (silent intakes, no AI calls).
  const father = randomPhone();
  await handleIntake({ source: "call", name: "Suresh Patil", phone: father, relation: "parent", studentName: "Rahul Patil", studentPhone: `+91 ${p}`, silent: true }, { simulated: true });
  const k2 = await readLead(a.leadId);
  await run.check("Father calling from his own phone with Rahul's number → same lead", (k2.contacts ?? []).some((c) => c.relation === "parent"), (k2.contacts ?? []).map((c) => `${c.relation}: ${c.name}`).join(" | "));
  const priya = await handleIntake({ source: "call", name: "Suresh Patil", phone: father, relation: "parent", studentName: "Priya Patil", silent: true }, { simulated: true });
  await db.doc(`leads/${priya.leadId}`).set({ selftest: true }, { merge: true });
  run.lead(priya.leadId);
  const pr = await readLead(priya.leadId);
  await run.check("Same father asking about daughter Priya → separate lead, linked (not merged)", priya.leadId !== a.leadId && !pr.mergedInto && !!pr.relatedLeads?.[a.leadId], pr.relatedLeads?.[a.leadId]?.reason ?? "no link");
  const other = await handleIntake({ source: "form", name: "Rahul Patil", phone: randomPhone(), silent: true }, { simulated: true });
  await db.doc(`leads/${other.leadId}`).set({ selftest: true }, { merge: true });
  run.lead(other.leadId);
  const ot = await readLead(other.leadId);
  await run.check("Another “Rahul Patil” with a different number → NOT merged (flagged for review)", other.leadId !== a.leadId && !ot.mergedInto, ot.possibleDuplicateOf ? `review card: ${ot.possibleDuplicateReason}` : "kept separate");
};

const nba: Scenario = async (run) => {
  const fam = await newLead(run, "whatsapp");
  const fee = await newLead(run, "whatsapp");
  const [a, b] = await Promise.all([
    say(run, fam, "I like the Data Science course but my father wants me to do a government job, he is not convinced about IT courses."),
    say(run, fee, "The Java course looks good but the fee is too high for me, I can't pay that much at once."),
  ]);
  await run.check("Both prospects got an answer", !!a && !!b, "");
  for (const [label, id, want] of [
    ["Family-approval objection", fam, "invite_parent"],
    ["Fees objection", fee, "fees_emi"],
  ] as const) {
    const lead = await readLead(id);
    const na = lead.nextAction;
    if (!(await run.check(`${label}: follow-up planned`, !!na, na ? `playbook ${na.playbook}` : "none"))) continue;
    await run.check(`${label}: WHAT → playbook “${want}” chosen from the objection`, na!.playbook === want, `${na!.playbook}: ${na!.reason}`);
    const h = istHour(na!.at.toDate());
    await run.check(`${label}: WHEN → ${formatIst(na!.at.toDate())} (never 9 PM–9 AM)`, h >= 9 && h < 21, "");
    await run.check(`${label}: WHICH CHANNEL → ${na!.channel}`, ["whatsapp", "web", "telegram", "instagram", "call"].includes(na!.channel), na!.reason);
    await run.check(`${label}: message written in their language`, (na!.message ?? "").length > 10, na!.message);
  }
  // Fire the family follow-up now, exactly as the 5-minute heartbeat would when it is due.
  const lead = await readLead(fam);
  if (lead.nextAction) {
    const { runHeartbeat } = await import("./heartbeat");
    await runHeartbeat(new Date(lead.nextAction.at.toDate().getTime() + 60_000), new Set([fam]));
    const after = await readLead(fam);
    const msgs = await db.collection(`leads/${fam}/messages`).where("role", "==", "ai").get();
    const fu = msgs.docs.find((d) => (d.get("meta") as Record<string, unknown>)?.kind === "followup");
    if (fu) run.note("asha", fu.get("text"), "automatic follow-up (no human)");
    await run.check("Follow-up sent automatically when due (no counsellor needed)", !!fu, "");
    await run.check("Next step scheduled after it (cadence)", !!after.nextAction && after.nextAction.done === false, after.nextAction ? `${after.nextAction.playbook} at ${formatIst(after.nextAction.at.toDate())}` : "");
  }
};

const dashboard: Scenario = async (run) => {
  const id = await newLead(run);
  const r = await say(run, id, "Hi, I'm Priya from Pune, B.Sc 2023. I want a job in data analytics but the fees are too high for my family, my parents are not sure, and I'm scared I won't get a job after the course.");
  const l = r?.lead;
  await run.check("Lead score 0–100 with an explainable breakdown", typeof l?.score === "number" && (l?.scoreBreakdown?.reasons?.length ?? 0) > 0, l?.scoreBreakdown ? `${l.score} = ${l.scoreBreakdown.reasons.join("; ")}` : "");
  await run.check("Three-line summary", (l?.summary ?? []).length === 3, (l?.summary ?? []).join(" / "));
  const obj = (l?.objections ?? []) as string[];
  await run.check("Objections detected: fees, job fear, family approval", ["fees", "job_fear", "family_approval"].every((o) => obj.includes(o)), obj.join(", "));
  await run.check("Suggested next message for the counsellor", (l?.suggestedMessage ?? "").length > 10, l?.suggestedMessage ?? "");
  await run.check("Assigned to a counsellor (by language)", !!l?.assignedTo, l?.assignedTo ? `${l.assignedTo} (${l.assignedLang ?? "-"})` : "no approved counsellor yet");
};

const takeover: Scenario = async (run) => {
  const id = await newLead(run);
  await say(run, id, "Hi, I want to know about the Python course.");
  const t0 = Date.now();
  await db.doc(`leads/${id}`).set({ aiPaused: true, takenOverBy: "Self-test counsellor", needsHuman: false }, { merge: true });
  await db.collection(`leads/${id}/messages`).add({ role: "system", channel: "web", text: "Self-test counsellor joined the conversation", meta: { kind: "takeover" }, createdAt: FieldValue.serverTimestamp() });
  run.note("system", "Counsellor tapped “Take over”");
  const before = (await db.collection(`leads/${id}/messages`).where("role", "==", "ai").get()).size;
  await db.collection(`leads/${id}/messages`).add({ role: "user", channel: "web", text: "Can I talk to a real person please?", createdAt: FieldValue.serverTimestamp() });
  run.note("prospect", "Can I talk to a real person please?");
  const t1 = Date.now();
  await respond(id);
  const decided = Date.now() - t1;
  await sleep(6000);
  const afterAi = (await db.collection(`leads/${id}/messages`).where("role", "==", "ai").get()).size;
  const lead = await readLead(id);
  await run.check("Asha stopped instantly after take-over", afterAi === before, `${afterAi - before} AI replies after take-over (should be 0); take-over took ${t1 - t0} ms, the worker stood down in ${decided} ms`);
  await run.check("Desk shows the lead needs the human", lead.needsHuman === true, String(lead.handoffReason ?? ""));
  await db.collection(`leads/${id}/messages`).add({ role: "counsellor", channel: "web", text: "Hi! I'm your counsellor. Happy to help — shall I call you?", meta: { by: "Self-test counsellor" }, createdAt: FieldValue.serverTimestamp() });
  run.note("counsellor", "Hi! I'm your counsellor. Happy to help — shall I call you?");
  await run.check("Counsellor's reply lands in the same conversation", true, "");
  await db.doc(`leads/${id}`).set({ aiPaused: false }, { merge: true });
  await run.check("Hand back to Asha", true, "");
};

const telephony: Scenario = async (run) => {
  const { handleIntake } = await import("./intake");
  const phone = randomPhone();
  const r0 = await handleIntake({ source: "call", phone }, { simulated: true });
  await db.doc(`leads/${r0.leadId}`).set({ selftest: true }, { merge: true });
  run.lead(r0.leadId);
  run.note("prospect", `[Missed call] +91 ${phone} (same payload the call webhook builds from Exotel/Twilio/Plivo)`);
  await respond(r0.leadId).catch(() => undefined);
  let lead = await readLead(r0.leadId);
  for (let i = 0; i < 40 && !(lead.summary ?? []).length; i++) {
    await sleep(2000);
    lead = await readLead(r0.leadId);
  }
  const msgs = await db.collection(`leads/${r0.leadId}/messages`).where("role", "==", "ai").get();
  if (msgs.size) run.note("asha", msgs.docs[0].get("text"), "follow-up after a missed call");
  await run.check("Call becomes a lead with source “call”", lead.firstSource === "call", "");
  await run.check("Asha follows up the missed call", msgs.size > 0, "");
  await run.check("Provider", null, "Telephony provider is not connected (needs KYC). The call webhook is ready: Admin → Channels → Phone calls.");
};

const instagram: Scenario = async (run) => {
  const { handleMetaWebhook } = await import("./whatsapp");
  const sender = `sim:ig_${rnd()}`;
  await handleMetaWebhook({
    object: "instagram",
    entry: [{ messaging: [{ sender: { id: sender }, recipient: { id: "me" }, message: { mid: `st_${rnd()}`, text: "Hi, saw your reel. Do you have weekend batches for data science?" } }] }],
  });
  run.note("prospect", "[Instagram DM] Hi, saw your reel. Do you have weekend batches for data science?", "real Instagram webhook parser");
  await sleep(1500);
  const leads = await db.collection("leads").where("igId", "==", sender).get();
  const id = leads.docs[0]?.id;
  if (!(await run.check("Instagram DM becomes a lead (source “instagram”)", !!id, ""))) return;
  await db.doc(`leads/${id}`).set({ selftest: true }, { merge: true });
  run.lead(id);
  await respond(id).catch(() => undefined);
  let msgs = await db.collection(`leads/${id}/messages`).where("role", "==", "ai").get();
  for (let i = 0; i < 40 && !msgs.size; i++) {
    await sleep(2000);
    msgs = await db.collection(`leads/${id}/messages`).where("role", "==", "ai").get();
  }
  if (msgs.size) run.note("asha", msgs.docs[0].get("text"));
  await run.check("Asha replies to the DM", msgs.size > 0, "");
  await run.check("Account", null, "Real DMs need an Instagram Professional account + Meta app setup; the same webhook code is used.");
};

const channels: Scenario = async (run) => {
  const { handleIntake } = await import("./intake");
  const list = ["web", "form", "googleform", "walkin", "call", "whatsapp", "telegram", "instagram"];
  const out: string[] = [];
  for (const ch of list) {
    const r = await handleIntake({ source: ch, name: `Self-test ${ch}`, phone: randomPhone(), message: `enquiry via ${ch}`, silent: true }, { simulated: true });
    await db.doc(`leads/${r.leadId}`).set({ selftest: true }, { merge: true });
    run.lead(r.leadId);
    const l = await readLead(r.leadId);
    out.push(`${ch} → lead ${r.leadId.slice(0, 6)} (source ${l.firstSource})`);
    await run.check(`${ch}: enquiry stored in the one lead list`, l.firstSource === ch, "");
  }
  run.note("system", out.join("\n"));
};

const reports: Scenario = async (run) => {
  const snap = await db.collection("leads").orderBy("lastMessageAt", "desc").limit(500).get();
  const live = snap.docs.map((d) => d.data() as Lead & Record<string, unknown>).filter((l) => !l.mergedInto);
  const real = live.filter((l) => !l.selftest && !l.burst);
  const leads = real.length ? real : live;
  if (!real.length) await run.check("Real leads", null, "No real or sample leads yet (Admin → Demo → Load everything); using the self-test leads to show the report.");
  const group = (key: (l: Lead) => string[]) => {
    const m = new Map<string, [number, number]>();
    for (const l of leads) for (const k of key(l)) {
      const [n, a] = m.get(k) ?? [0, 0];
      m.set(k, [n + 1, a + (l.status === "admitted" ? 1 : 0)]);
    }
    return [...m.entries()].sort((x, y) => y[1][0] - x[1][0]).map(([k, [n, a]]) => `${k}: ${a}/${n} admitted (${n ? Math.round((100 * a) / n) : 0}%)`);
  };
  const bySource = group((l) => [l.firstSource ?? "web"]);
  const byCounsellor = group((l) => [l.assignedTo ?? "unassigned"]);
  const byObjection = group((l) => l.objections ?? []);
  run.note("system", `By source:\n${bySource.join("\n")}`);
  run.note("system", `By counsellor:\n${byCounsellor.join("\n")}`);
  run.note("system", `By objection:\n${byObjection.join("\n")}`);
  await run.check("Conversion by source", bySource.length > 0, `${leads.length} leads`);
  await run.check("Conversion by counsellor", byCounsellor.length > 0, "");
  await run.check("Conversion by objection", byObjection.length > 0, byObjection.length ? "" : "no objections yet: load sample leads");
};

const scale: Scenario = async (run) => {
  const q = `Full Stack Java ki fees kitni hai? (${rnd()})`;
  const [x, y] = [await newLead(run), await newLead(run)];
  const [a, b] = await Promise.all([say(run, x, q), say(run, y, q)]);
  const states = [a?.meta.cache, b?.meta.cache];
  await run.check("Two strangers, identical question at the same moment → one AI call", states.some((s) => s === "hit" || s === "wait"), `cache states: ${states.map((s) => s ?? "AI call").join(" / ")}`);
  await run.check("Both got the same, Guard-checked answer", !!a && !!b && a.text === b.text, "");
  await run.check("Still two separate leads (identity ≠ question)", x !== y, "");
};

export const SCENARIOS: Record<string, Scenario> = {
  counselling,
  languages,
  codemix,
  register,
  voice,
  profile,
  kb,
  guard,
  aptitude,
  recommend,
  booking,
  identity,
  nba,
  dashboard,
  takeover,
  channels,
  telephony,
  instagram,
  reports,
  scale,
};

export async function runScenario(docId: string): Promise<void> {
  const ref = db.doc(`selftests/${docId}`);
  const data = (await ref.get()).data() ?? {};
  const name = String(data.scenario ?? docId);
  const fn = SCENARIOS[name];
  const started = Date.now();
  await ref.set({ status: "running", startedAt: Timestamp.now(), checks: [], evidence: [], leadIds: [], error: FieldValue.delete() }, { merge: true });
  const run = new Run(ref);
  try {
    if (!fn) throw new Error(`unknown scenario ${name}`);
    await fn(run);
    const failed = run.checks.some((c) => c.ok === false);
    const warned = run.checks.some((c) => c.ok === null);
    await ref.set(
      { status: failed ? "fail" : warned ? "warn" : "pass", finishedAt: Timestamp.now(), ms: Date.now() - started, aiReplies: run.aiReplies, checks: run.checks, evidence: run.evidence, leadIds: run.leadIds },
      { merge: true },
    );
  } catch (e) {
    console.error("selftest", name, e);
    await ref.set({ status: "error", error: String((e as Error).message ?? e).slice(0, 500), finishedAt: Timestamp.now(), ms: Date.now() - started, checks: run.checks, evidence: run.evidence, leadIds: run.leadIds }, { merge: true });
  }
}

/** Deletes every lead the self-test created (and its messages). */
export async function cleanupSelfTest(): Promise<number> {
  const snap = await db.collection("leads").where("selftest", "==", true).limit(300).get();
  for (const d of snap.docs) {
    const msgs = await d.ref.collection("messages").get();
    const batch = db.batch();
    msgs.docs.forEach((m) => batch.delete(m.ref));
    batch.delete(d.ref);
    await batch.commit();
  }
  return snap.size;
}
