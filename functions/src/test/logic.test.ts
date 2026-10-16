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
});

test("quiet hours push follow-ups to 10 AM IST", () => {
  const lateNight = new Date("2026-10-16T17:30:00Z"); // 11:00 PM IST
  const moved = respectQuietHours(lateNight);
  assert.equal(istHour(moved), 10);
  assert.match(formatIst(moved), /Sat, 17 Oct · 10:00 AM IST/);
  const afternoon = new Date("2026-10-16T08:30:00Z"); // 2:00 PM IST
  assert.equal(respectQuietHours(afternoon).getTime(), afternoon.getTime());
});
