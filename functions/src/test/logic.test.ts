import { test } from "node:test";
import assert from "node:assert/strict";
import { decideMatch, nameSimilarity, normalizePhone, phoneticKey, transliterate } from "../identity";
import { checkReply, findNumbers } from "../guard";
import { respectQuietHours, istHour, formatIst } from "../lang";
import type { KnowledgeBase } from "../db";

test("sponsor example: Rahul Patil (form) = राहुल पाटील (WhatsApp)", () => {
  assert.equal(normalizePhone("098765 43210"), "9876543210");
  assert.equal(normalizePhone("+91 98765-43210"), "9876543210");
  assert.equal(normalizePhone("919876543210"), "9876543210");
  assert.equal(transliterate("राहुल पाटील"), "raahul paatiil");
  assert.equal(phoneticKey("राहुल पाटील"), phoneticKey("Rahul Patil"));
  const d = decideMatch({ name: "Rahul Patil", phone: "098765 43210" }, { name: "राहुल पाटील", phone: "919876543210" });
  assert.equal(d.decision, "merge");
});

test("spelling variants match", () => {
  for (const [a, b] of [
    ["Sneha Kulkarni", "स्नेहा कुलकर्णी"],
    ["Priya Deshmukh", "Priyaa Deshmukh"],
    ["Vaibhav Joshi", "Waibhav Joshi"],
    ["Rakesh Shinde", "राकेश शिंदे"],
    ["Patil Rahul", "Rahul Patil"],
  ]) {
    assert.ok(nameSimilarity(a, b) >= 0.85, `${a} vs ${b} = ${nameSimilarity(a, b)}`);
  }
  assert.ok(nameSimilarity("Rahul Patil", "Sunita Kale") < 0.6);
});

test("same phone, different person -> review, not merge", () => {
  const d = decideMatch({ name: "Rahul Patil", phone: "9876543210" }, { name: "Sunita Kale", phone: "+919876543210" });
  assert.equal(d.decision, "review");
});

const kb: KnowledgeBase = {
  instituteName: "TechSummitTrainers",
  city: "Pune",
  courses: [{ id: "fsj", name: "Full Stack Java", durationWeeks: 24, mode: "hybrid", feeInr: 65000, emi: { months: 6, perMonthInr: 11000 } }],
  scholarships: [{ id: "early", name: "Early Bird", rule: "Pay full fee before batch start", amountOffInr: 5000 }],
  policies: { placement: "Placement assistance: resume reviews, mock interviews and referrals. We do not guarantee jobs." },
};

test("guard passes knowledge-base facts", () => {
  const r = checkReply("Full Stack Java fee ₹65,000, or 6 EMIs of ₹11,000. With Early Bird it is ₹60,000.", kb);
  assert.ok(r.ok, r.violations.join(" | "));
  assert.ok(checkReply("हम नौकरी की गारंटी नहीं देते, लेकिन placement assistance मिलता है।", kb).ok);
  assert.ok(checkReply("Sorry, I can't offer ₹40,000.", kb, ["my friend got it for 40000"]).ok);
});

test("guard blocks invented discounts and guarantees", () => {
  assert.equal(checkReply("Special for you: ₹50,000 only!", kb).ok, false);
  assert.equal(checkReply("You get 20% off if you join today.", kb).ok, false);
  assert.equal(checkReply("100% placement guaranteed!", kb).ok, false);
  assert.equal(checkReply("तुम्हाला नक्की नोकरी मिळेल.", kb).ok, false);
  assert.equal(checkReply("Ok, I will give you a discount.", kb).ok, false);
  assert.equal(checkReply("Theek hai, 45k mein de dete hain.", kb).ok, false);
});

test("guard ignores years, durations and times", () => {
  assert.equal(findNumbers("Batch starts 3 Nov 2026 at 11:00, 24 weeks").length, 0);
  assert.equal(findNumbers("A train covers 120 km in 2 hours, 5 years later").length, 0, "'covers'/'years' are not Rs");
  assert.equal(findNumbers("Rs 45,000 or Rs. 5000").length, 2);
});

test("quiet hours push follow-ups to 10 AM IST", () => {
  const lateNight = new Date("2026-10-16T17:30:00Z"); // 11:00 PM IST
  const moved = respectQuietHours(lateNight);
  assert.equal(istHour(moved), 10);
  assert.match(formatIst(moved), /Sat, 17 Oct · 10:00 AM IST/);
  const afternoon = new Date("2026-10-16T08:30:00Z"); // 2:00 PM IST
  assert.equal(respectQuietHours(afternoon).getTime(), afternoon.getTime());
});

// ---------------------------------------------------------------- v7 additions
import { advance, plan, readPick, QUESTION_BANK, bandFor } from "../aptitude";
import { computeScore } from "../scoring";
import { decideNextAction } from "../nba";
import { parseJsonLoose } from "../ai";
import { Timestamp } from "firebase-admin/firestore";
import type { Lead } from "../db";

test("sponsor's exact spelling: राहुल पाटल (no matra) still matches Rahul Patil", () => {
  const d = decideMatch({ name: "Rahul Patil", phone: "098765 43210" }, { name: "राहुल पाटल", phone: "+91 98765-43210" });
  assert.equal(d.decision, "merge", `similarity ${d.similarity}`);
});

test("aptitude bank: every question has 3 options and a valid answer", () => {
  const ids = new Set<string>();
  for (const q of QUESTION_BANK) {
    assert.equal(q.options.length, 3);
    assert.ok(["A", "B", "C"].includes(q.answer));
    assert.ok(!ids.has(q.id));
    ids.add(q.id);
    // no money-like numbers that the Guard would block
    assert.ok(checkReply(`${q.text} A) ${q.options[0].text} B) ${q.options[1].text} C) ${q.options[2].text}`, kb).ok, q.id);
  }
});

test("aptitude is adaptive and scored on the server", () => {
  let s = advance(undefined, { event: "started" }).state;
  assert.equal(s.status, "in_progress");
  const first = QUESTION_BANK.find((q) => q.id === s.current)!;
  assert.equal(first.level, 2, "starts at medium");
  // answer right → next offered question is harder
  const p = plan(s);
  assert.equal(p.nextIfCorrect!.level, 3);
  assert.equal(p.nextIfWrong!.level, 1);
  const r = advance(s, { userText: first.answer, shownId: p.nextIfCorrect!.id });
  assert.equal(r.scored!.correct, true);
  s = r.state;
  assert.equal(s.level, 3);
  assert.equal(s.current, p.nextIfCorrect!.id);
  // a wrong answer is caught even if the model claims otherwise
  const cur = QUESTION_BANK.find((q) => q.id === s.current)!;
  const wrong = (["A", "B", "C"] as const).find((k) => k !== cur.answer)!;
  const r2 = advance(s, { picked: cur.answer, userText: wrong });
  assert.equal(r2.scored!.correct, false, "server trusts the prospect's own letter");
  assert.equal(readPick("(b) 48"), "B");
  assert.equal(readPick("option c"), "C");
  assert.equal(bandFor(8), "strong");
  assert.equal(bandFor(2), "beginner");
});

test("aptitude finishes after 4 answers with a band", () => {
  let s = advance(undefined, { event: "started" }).state;
  for (let i = 0; i < 4; i++) {
    const cur = QUESTION_BANK.find((q) => q.id === s.current)!;
    const nxt = plan(s).nextIfCorrect;
    s = advance(s, { userText: cur.answer, shownId: nxt?.id }).state;
  }
  assert.equal(s.status, "done");
  assert.equal(s.correct, 4);
  assert.equal(s.band, "strong");
});

const now = new Date("2026-10-16T08:30:00Z"); // 2 PM IST
const recent = Timestamp.fromDate(new Date(now.getTime() - 10 * 60_000));

test("score is explainable and objections lower it", () => {
  const base: Lead = { phone: "9876543210", profile: { education: "B.Com", goal: "developer" }, lastInboundAt: recent, userMessages: 4, objections: [] };
  const a = computeScore({ lead: base, aiScore: 70, userTexts: ["fees kitni hai?"], now });
  const b = computeScore({ lead: { ...base, objections: ["fees", "family_approval"] }, aiScore: 70, userTexts: ["fees kitni hai?"], now });
  assert.ok(a.score > b.score);
  assert.ok(a.breakdown.reasons.length >= 3);
  const booked = computeScore({ lead: { ...base, booking: { slotId: "x", startAt: recent, title: "t", calendarUrl: "" } }, aiScore: 70, userTexts: [], now });
  assert.equal(booked.breakdown.intent, 25);
});

test("next-best-action: objection playbooks, quiet hours, 24h window", () => {
  const lead: Lead = { name: "Pooja", objections: ["family_approval"], waId: "919890098900", lastChannel: "whatsapp", lastInboundAt: recent, score: 55 };
  const na = decideNextAction({ lead, now, aiMessage: "Babanna demo la gheun ya" })!;
  assert.equal(na.playbook, "invite_parent");
  const h = new Date(na.at.toDate().getTime() + 330 * 60_000).getUTCHours();
  assert.ok(h >= 9 && h < 21, "never in quiet hours");
  assert.equal(na.channel, "whatsapp", "pulled inside the 24 h window");
  assert.ok(na.at.toDate().getTime() < recent.toDate().getTime() + 24 * 3_600_000);
  const lateLead = { ...lead, phone: "9890098900", lastInboundAt: Timestamp.fromDate(new Date(now.getTime() - 23.8 * 3_600_000)) };
  assert.equal(decideNextAction({ lead: lateLead, now, aiMessage: "x" })!.channel, "call", "window already closing → call");
  const hot = decideNextAction({ lead: { ...lead, objections: [], score: 80 }, now, aiMessage: "x" })!;
  assert.equal(hot.playbook, "hot_nudge");
  assert.equal(hot.channel, "whatsapp", "within the 24 h window");
  const quiet = decideNextAction({ lead: { ...lead, unansweredFollowups: 3 }, now, aiMessage: "x" })!;
  assert.equal(quiet.playbook, "pause_call");
  assert.equal(decideNextAction({ lead: { ...lead, status: "admitted" }, now, aiMessage: "x" }), null);
});

test("loose JSON parsing for free fallback models", () => {
  assert.deepEqual(parseJsonLoose('```json\n{"a":1}\n```'), { a: 1 });
  assert.deepEqual(parseJsonLoose('Sure! {"a":2} hope that helps'), { a: 2 });
});

// ---------------------------------------------------------------- scale + identity
import { decideLeadMatch, personSimilarity } from "../identity";
import { normaliseQuestion } from "../lang";

test("same question, different wording of case/punctuation/digits → one cache key", () => {
  assert.equal(normaliseQuestion("Full Stack Java ki FEES kitni hai??"), normaliseQuestion("full stack java ki fees kitni hai"));
  assert.equal(normaliseQuestion("फी किती आहे? ३ महिने"), normaliseQuestion("फी किती आहे 3 महिने"));
  assert.notEqual(normaliseQuestion("Java fees?"), normaliseQuestion("Python fees?"));
});

test("siblings are not the same person", () => {
  assert.ok(personSimilarity("Priya Patil", "Rahul Patil") < 0.7);
  assert.ok(personSimilarity("Rahul Patil", "Rohit Patil") < 0.85);
  assert.ok(personSimilarity("Rahul Patil", "राहुल पाटल") >= 0.85);
  assert.ok(personSimilarity("Patil Rahul", "Rahul Patil") >= 0.85);
  assert.ok(personSimilarity("Rahul Suresh Patil", "Rahul Patil") >= 0.85);
});

const rahulSelf = { name: "Rahul Patil", phone: "098765 43210", relation: "self" };

test("one admission, many enquirers: father and friend with the student's number → merge", () => {
  const father = { name: "Suresh Patil", phone: "9822012345", relation: "parent", studentName: "Rahul Patil", studentPhone: "+91 98765-43210" };
  assert.equal(decideLeadMatch(father, rahulSelf).decision, "merge");
  const friend = { name: "Amit", phone: "9811100011", relation: "friend", studentName: "राहुल पाटील", studentPhone: "919876543210" };
  assert.equal(decideLeadMatch(friend, rahulSelf).decision, "merge");
  // the student himself on WhatsApp, Devanagari name, other phone format
  assert.equal(decideLeadMatch({ name: "राहुल पाटल", phone: "919876543210" }, rahulSelf).decision, "merge");
});

test("one parent, two children → two admissions, linked, never merged", () => {
  const forRahul = { name: "Suresh Patil", phone: "9822012345", relation: "parent", studentName: "Rahul Patil", contactPhones: ["9822012345", "9876543210"] };
  const forPriya = { name: "Suresh Patil", phone: "9822012345", relation: "parent", studentName: "Priya Patil" };
  assert.equal(decideLeadMatch(forPriya, forRahul).decision, "related");
  // siblings sharing one family phone, each writing for themselves
  assert.equal(decideLeadMatch({ name: "Priya Patil", phone: "9822012345" }, { name: "Rahul Patil", phone: "9822012345" }).decision, "related");
});

test("a name alone never merges (many people are called Rahul Patil)", () => {
  const d = decideLeadMatch({ name: "Suresh Patil", phone: "9822012345", relation: "parent", studentName: "Rahul Patil" }, rahulSelf);
  assert.equal(d.decision, "review");
  assert.equal(decideLeadMatch({ name: "Sneha Joshi", phone: "9000000001" }, rahulSelf).decision, "none");
});

// ------------------------------------------------- single-flight under a burst
import { singleFlight, type MiniDb } from "../cache";

function fakeDb(): MiniDb {
  const store = new Map<string, Record<string, unknown>>();
  const tick = () => new Promise((r) => setImmediate(r));
  const ref = (path: string) => ({
    async create(d: Record<string, unknown>) {
      await tick();
      if (store.has(path)) throw new Error("ALREADY_EXISTS");
      store.set(path, d);
    },
    async get() {
      await tick();
      const v = store.get(path);
      return { data: () => (v ? { ...v } : undefined) };
    },
    async set(d: Record<string, unknown>) {
      await tick();
      store.set(path, d);
    },
    path,
  });
  let chain: Promise<unknown> = Promise.resolve();
  return {
    doc: ref,
    runTransaction<T>(fn: (tx: never) => Promise<T>): Promise<T> {
      // serialise transactions like Firestore would
      const run = chain.then(() =>
        fn({ get: (r: { get: () => unknown }) => r.get(), set: (r: { path: string }, d: Record<string, unknown>) => store.set(r.path, d) } as never),
      );
      chain = run.catch(() => undefined);
      return run;
    },
  } as unknown as MiniDb;
}

test("1,000 identical questions at once → the AI is asked once", async () => {
  const db = fakeDb();
  let calls = 0;
  const produce = async () => {
    calls++;
    await new Promise((r) => setTimeout(r, 30));
    return { reply: "Full Stack Java is ₹65,000" };
  };
  const results = await Promise.all(Array.from({ length: 1000 }, () => singleFlight("k1", produce, () => true, { db, pollMs: 5 })));
  assert.equal(calls, 1);
  assert.ok(results.every((r) => r.value.reply === "Full Stack Java is ₹65,000"));
  assert.equal(results.filter((r) => r.state === "miss").length, 1);
  // a later visitor gets an instant cache hit
  const later = await singleFlight("k1", produce, () => true, { db, pollMs: 5 });
  assert.equal(later.state, "hit");
  assert.equal(calls, 1);
});

test("a personal answer (booking) is never reused for someone else", async () => {
  const db = fakeDb();
  let calls = 0;
  const produce = async () => {
    calls++;
    await new Promise((r) => setTimeout(r, 20));
    return { booked: true };
  };
  await Promise.all(Array.from({ length: 5 }, () => singleFlight("k2", produce, (v) => !v.booked, { db, pollMs: 5 })));
  assert.equal(calls, 5);
});

test("if the AI fails, the next caller takes over instead of waiting forever", async () => {
  const db = fakeDb();
  let calls = 0;
  await assert.rejects(singleFlight("k3", async () => { calls++; throw new Error("429"); }, () => true, { db, pollMs: 5 }));
  const r = await singleFlight("k3", async () => { calls++; return { ok: 1 }; }, () => true, { db, pollMs: 5 });
  assert.equal(r.value.ok, 1);
  assert.equal(calls, 2);
});

// ------------------------------------------------------------ intake questions
import { advanceOnboarding, parseContact, parseCourse, parseName, parseRelation, detectLang, relationOptions, courseOptions, onboardingBrief } from "../onboarding";
import { fixModel, supportsMinimalThinking } from "../ai";
import { offlineAnswer, offlineIntent } from "../offline";

const COURSES = [
  { id: "py", name: "Python Foundations", durationWeeks: 6, feeInr: 12000 },
  { id: "fsj", name: "Full Stack Java Developer", durationWeeks: 24, feeInr: 65000 },
  { id: "mern", name: "MERN Full Stack (JavaScript)", durationWeeks: 20, feeInr: 55000 },
  { id: "ds", name: "Data Science & AI with Python", durationWeeks: 24, feeInr: 75000 },
];
const base = { courses: COURSES, instituteName: "SechTummit Trainers" };

test("intake: who is writing, in three languages, typed or tapped", () => {
  assert.equal(parseRelation("I'm the student"), "self");
  assert.equal(parseRelation("", "rel:parent"), "parent");
  assert.equal(parseRelation("2"), "parent");
  assert.equal(parseRelation("my son"), "parent");
  assert.equal(parseRelation("मैं पैरेंट हूँ"), "parent");
  assert.equal(parseRelation("मी पालक आहे"), "parent");
  assert.equal(parseRelation("मी विद्यार्थी आहे"), "self");
  assert.equal(parseRelation("मित्रासाठी"), "friend");
  assert.equal(parseRelation("for my dost"), "friend");
  assert.equal(parseRelation("my sister"), "sibling");
  assert.equal(parseRelation("what are the fees"), undefined);
});

test("intake: names, contacts and course picks are parsed safely", () => {
  assert.equal(parseName("my name is rahul patil"), "Rahul Patil");
  assert.equal(parseName("Imran Shaikh"), "Imran Shaikh"); // "Im" is not a prefix here
  assert.equal(parseName("मेरा नाम राहुल है"), "राहुल");
  assert.equal(parseName("मी स्नेहा आहे"), "स्नेहा");
  assert.equal(parseName("what is the fee?"), undefined);
  assert.equal(parseName("9876543210"), undefined);
  assert.deepEqual(parseContact("his number is +91 98765-43210"), { phone: "9876543210" });
  assert.deepEqual(parseContact("Rahul.P@Gmail.com"), { email: "rahul.p@gmail.com" });
  assert.deepEqual(parseContact("९८७६५४३२१०"), { phone: "9876543210" });
  assert.deepEqual(parseContact("tomorrow"), {});
  assert.equal(parseCourse("", COURSES, "course:fsj"), "fsj");
  assert.equal(parseCourse("2", COURSES), "fsj");
  assert.equal(parseCourse("java", COURSES), "fsj");
  assert.equal(parseCourse("Python Foundations", COURSES), "py");
  assert.equal(parseCourse("Not sure, help me choose", COURSES), "help");
  assert.equal(parseCourse("blockchain", COURSES), undefined);
  assert.equal(detectLang("मला फी किती आहे ते सांगा"), "mr");
  assert.equal(detectLang("मुझे फीस कितनी है बताइए"), "hi");
  assert.equal(detectLang("hello"), undefined);
});

test("intake: WhatsApp buttons fit Meta's limits (3 buttons ≤ 20 chars, list rows ≤ 24)", () => {
  for (const l of ["en", "hi", "mr"] as const) {
    const opts = relationOptions(l);
    assert.equal(opts.length, 3);
    for (const o of opts) assert.ok([...o.label].length <= 20, `${o.label} too long`);
    const c = courseOptions(l, COURSES);
    assert.ok(c.length <= 10);
    assert.equal(c[c.length - 1].id, "course:help");
    assert.ok([...c[c.length - 1].label].length <= 24);
  }
});

test("intake: parent on WhatsApp → name → phone → course → Asha talks about that course", () => {
  let r = advanceOnboarding(null, { ...base, text: "Hi", phoneKnown: true });
  assert.equal(r.state.step, "relation");
  assert.match(r.reply!.text, /who is this enquiry for/i);
  assert.equal(r.reply!.options.length, 3);
  r = advanceOnboarding(r.state, { ...base, text: "I'm a parent", choiceId: "rel:parent", phoneKnown: true });
  assert.equal(r.state.relation, "parent");
  assert.match(r.reply!.text, /student's name/);
  r = advanceOnboarding(r.state, { ...base, text: "Rahul Patil", phoneKnown: true });
  assert.equal(r.state.studentName, "Rahul Patil");
  assert.equal(r.state.step, "contact"); // the parent's number is not the student's
  r = advanceOnboarding(r.state, { ...base, text: "98765 43210", phoneKnown: true });
  assert.equal(r.state.phone, "9876543210");
  assert.equal(r.state.step, "course");
  assert.equal(r.reply!.options.length, COURSES.length + 1);
  r = advanceOnboarding(r.state, { ...base, text: "Full Stack Java Develope", choiceId: "course:fsj", phoneKnown: true });
  assert.equal(r.reply, undefined); // Asha answers now
  assert.equal(r.state.step, "done");
  assert.equal(r.state.courseId, "fsj");
  const brief = onboardingBrief(r.state, COURSES);
  assert.match(brief, /Full Stack Java Developer/);
  assert.match(brief, /Do NOT ask again/);
});

test("intake: a student on WhatsApp skips the phone step; a question first is kept for Asha", () => {
  let r = advanceOnboarding(null, { ...base, text: "Full stack java ki fees kitni hai?", phoneKnown: true });
  assert.equal(r.state.firstQuestion, "Full stack java ki fees kitni hai?");
  assert.match(r.reply!.text, /answer your question/);
  r = advanceOnboarding(r.state, { ...base, text: "1", phoneKnown: true });
  r = advanceOnboarding(r.state, { ...base, text: "I am Sneha", phoneKnown: true });
  assert.equal(r.state.studentName, "Sneha");
  assert.equal(r.state.step, "course");
  r = advanceOnboarding(r.state, { ...base, text: "help me choose", phoneKnown: true });
  assert.equal(r.state.wantsHelp, true);
  assert.match(onboardingBrief(r.state, COURSES), /fees kitni hai/);
});

test("intake: never a trap — voice notes and repeated questions go straight to Asha", () => {
  const v = advanceOnboarding(null, { ...base, text: "", isVoice: true });
  assert.equal(v.state.step, "done");
  assert.equal(v.reply, undefined);
  let r = advanceOnboarding(null, { ...base, text: "hello" });
  r = advanceOnboarding(r.state, { ...base, text: "just tell me" });
  assert.ok(r.reply); // asked again once
  r = advanceOnboarding(r.state, { ...base, text: "why do you need this?" });
  assert.equal(r.state.step, "done");
  // web chat: Asha's greeting is already on screen, so no second introduction
  const w = advanceOnboarding(null, { ...base, text: "What is the fee?", introShown: true, langHint: "hi" });
  assert.doesNotMatch(w.reply!.text, /मैं आशा हूँ/);
  assert.equal(w.state.lang, "hi");
  // Marathi first message → Marathi questions
  const m = advanceOnboarding(null, { ...base, text: "माझ्या मुलासाठी कोर्स हवा आहे" });
  assert.equal(m.state.lang, "mr");
  assert.equal(m.state.relation, "parent");
  assert.match(m.reply!.text, /विद्यार्थ्याचं नाव/);
});

test("retired model names are mapped to live ones", () => {
  assert.equal(fixModel("gemini-3.5-flash"), "gemini-3.6-flash");
  assert.equal(fixModel("llama-3.3-70b-versatile"), "openai/gpt-oss-120b");
  assert.equal(fixModel("gemini-3.8-flash"), "gemini-3.8-flash");
  assert.equal(supportsMinimalThinking("gemini-3.6-flash"), true);
  assert.equal(supportsMinimalThinking("gemini-3.5-flash-lite"), true);
  assert.equal(supportsMinimalThinking("gemini-3.8-flash"), false);
});

test("AI down: Asha still answers from the knowledge base", () => {
  const kb = { instituteName: "X", city: "Pune", courses: [{ id: "fsj", name: "Full Stack Java Developer", durationWeeks: 24, mode: "Hybrid", feeInr: 65000, emi: { months: 6, perMonthInr: 11000 }, nextBatch: "3 Nov 2026" }] } as KnowledgeBase;
  assert.equal(offlineIntent("Full Stack Java ki fees kitni hai?"), "fees");
  const a = offlineAnswer(kb, "Full Stack Java ki fees kitni hai?", "hinglish");
  assert.match(a, /₹65,000/);
  assert.match(a, /6 × ₹11,000/);
  assert.ok(checkReply(a, kb, ["fees?"]).ok, "offline answer must pass the Guard");
  assert.match(offlineAnswer(kb, "batch kab start hogi", "en"), /3 Nov 2026/);
});

test("aptitude: typed value beats a mismatched letter; quiz text the model invents is removed", async () => {
  const { byId, readPick } = await import("../aptitude");
  const { stripQuiz } = await import("../brain");
  const q = byId("e2")!; // 2, 4, 6, 8 → B) 10
  assert.equal(readPick("A) 10", q), "B");
  assert.equal(readPick("B) 10", q), "B");
  assert.equal(readPick("10", q), "B");
  assert.equal(readPick("a", q), "A");
  const cleaned = stripQuiz("Oops, try again.\nWhat comes next: 2, 4, 6, 8, ?\nA) 9\nB) 10\nC) 12", q);
  assert.equal(cleaned, "Oops, try again.");
  assert.equal(stripQuiz("Would you like a demo on Mon 11 AM?"), "Would you like a demo on Mon 11 AM?");
});

test("chat flow: language picks, restart words, enroll words, UPI link", async () => {
  const { parseLang, isRestart, looksLikeEnroll, looksLikePaid, upiLink, guessLang } = await import("../flow");
  assert.equal(parseLang("हिंदी"), "hi");
  assert.equal(parseLang("Marathi"), "mr");
  assert.equal(parseLang("1"), "en");
  assert.equal(parseLang("x", "lang:mr"), "mr");
  assert.equal(parseLang("tell me fees"), undefined);
  assert.equal(guessLang("मला जावा शिकायचं आहे"), "mr");
  assert.equal(guessLang("fees kitni hai"), "hi");
  assert.ok(isRestart("Restart") && isRestart("/start") && isRestart("पुन्हा सुरू"));
  assert.ok(!isRestart("restart my career in IT"));
  assert.ok(looksLikeEnroll("✅ Enroll now") && looksLikeEnroll("", "enroll:yes") && looksLikeEnroll("✅ अभी एनरोल करें"));
  assert.ok(!looksLikeEnroll("what is the enrollment process?"));
  assert.ok(looksLikePaid("payment done"));
  assert.equal(
    upiLink({ upiId: "inst@okhdfc", payee: "Sech Tummit", amount: 10 }, "Registration Java"),
    "upi://pay?pa=inst%40okhdfc&pn=Sech%20Tummit&am=10.00&cu=INR&tn=Registration%20Java",
  );
});

test("enrolment form: compulsory fields are validated", async () => {
  const { validate, parseDob, validMobile, validEmail, bothModes } = await import("../enroll_form");
  const kb: KnowledgeBase = { instituteName: "S", city: "Pune", courses: [{ id: "fsj", name: "Full Stack Java Developer", durationWeeks: 24, mode: "hybrid", feeInr: 65000 }] };
  const st = { form: { phone: "9876543210" } };
  assert.equal(validMobile("+91 98765-43210"), "9876543210");
  assert.equal(validMobile("12345"), undefined);
  assert.equal(validMobile("5876543210"), undefined);
  assert.equal(validEmail(" Neha@Gmail.com "), "neha@gmail.com");
  assert.equal(validEmail("neha@gmail"), undefined);
  assert.equal(parseDob("5/8/2004"), "05-08-2004");
  assert.equal(parseDob("31-02-2004"), undefined);
  assert.equal(parseDob("01-01-2024"), undefined); // too young
  assert.equal(validate("name", "Neha Joshi", undefined, st, kb, "en").value, "Neha Joshi");
  assert.equal(validate("name", "नेहा जोशी", undefined, st, kb, "hi").value, "नेहा जोशी");
  assert.equal(validate("name", "12345", undefined, st, kb, "en").error, "bad_name");
  assert.equal(validate("whatsapp", "", "form:same", st, kb, "en").value, "9876543210");
  assert.equal(validate("address", "Pune", undefined, st, kb, "en").error, "bad_text");
  assert.equal(validate("course", "", "form:course:fsj", st, kb, "en").courseId, "fsj");
  assert.equal(validate("batch", "शाम", undefined, st, kb, "hi").value, "Evening");
  assert.ok(bothModes("hybrid") && bothModes("Online + classroom") && !bothModes("online"));
});
