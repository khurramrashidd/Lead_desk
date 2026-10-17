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
