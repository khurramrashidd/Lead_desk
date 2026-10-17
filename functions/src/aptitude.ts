/**
 * The in-chat aptitude check, scored on the server.
 *
 * Asha only presents the questions (in the prospect's language) and reacts.
 * Which question comes next, whether an answer was right, the level reached and
 * the final band are all decided HERE from a fixed question bank, so the check is
 * genuinely adaptive and the result can be explained to a judge or a parent.
 *
 * Rules: 4 questions. Start at medium. Right answer -> one level harder,
 * wrong answer -> one level easier. Code-reading questions only for people who
 * have coded before. Points = sum of the levels answered correctly (max 11).
 */
import type { AptitudeState } from "./db";

export type Level = 1 | 2 | 3;

export interface Question {
  id: string;
  level: Level;
  topic: "logic" | "numbers" | "pattern" | "code";
  text: string;
  options: { key: "A" | "B" | "C"; text: string }[];
  answer: "A" | "B" | "C";
}

const q = (id: string, level: Level, topic: Question["topic"], text: string, a: string, b: string, c: string, answer: Question["answer"]): Question => ({
  id,
  level,
  topic,
  text,
  options: [
    { key: "A", text: a },
    { key: "B", text: b },
    { key: "C", text: c },
  ],
  answer,
});

export const QUESTION_BANK: Question[] = [
  // ---- level 1: easy
  q("e1", 1, "numbers", "You read 12 pages a day. How many pages do you read in 5 days?", "50", "60", "72", "B"),
  q("e2", 1, "pattern", "What comes next: 2, 4, 6, 8, ?", "9", "10", "12", "B"),
  q("e3", 1, "logic", "If today is Monday, what day will it be 3 days later?", "Wednesday", "Thursday", "Friday", "B"),
  q("e4", 1, "logic", "Which word is the odd one out: Apple, Mango, Carrot, Banana?", "Mango", "Carrot", "Banana", "B"),
  q("e5", 1, "numbers", "A class has 30 students and 12 are girls. How many are boys?", "18", "16", "20", "A"),
  q("e6", 1, "code", "In most programming languages, what does  x = x + 1  do?", "Compares x with x + 1", "Increases x by 1", "Gives an error", "B"),
  q("e7", 1, "logic", "Riya is taller than Sam. Sam is taller than Ali. Who is the shortest?", "Riya", "Sam", "Ali", "C"),
  // ---- level 2: medium
  q("m1", 2, "pattern", "What comes next: 3, 6, 12, 24, ?", "36", "48", "30", "B"),
  q("m2", 2, "numbers", "A batch has 40 seats and one quarter of them are booked. How many seats are still free?", "10", "30", "20", "B"),
  q("m3", 2, "logic", "All developers are learners. Neha is a developer. So…", "Neha is a learner", "Every learner is a developer", "Neha is not a learner", "A"),
  q("m4", 2, "pattern", "Find the next letter: A, C, E, G, ?", "H", "I", "J", "B"),
  q("m5", 2, "numbers", "A train covers 120 km in 2 hours. At the same speed, how far does it go in 5 hours?", "240 km", "300 km", "360 km", "B"),
  q("m6", 2, "code", "What is printed?  x = 5;  y = x * 2;  print(y - 3)", "7", "10", "13", "A"),
  q("m7", 2, "logic", "A meeting is at 3:00 PM. Priya arrives 45 minutes early. When does she arrive?", "2:15 PM", "2:45 PM", "3:45 PM", "A"),
  q("m8", 2, "pattern", "Which number does not belong: 2, 3, 5, 9, 11?", "2", "9", "11", "B"),
  // ---- level 3: hard
  q("h1", 3, "pattern", "What comes next: 1, 1, 2, 3, 5, 8, ?", "11", "13", "15", "B"),
  q("h2", 3, "logic", "In a code, CAT is written as DBU. How is DOG written?", "EPH", "EPG", "DPH", "A"),
  q("h3", 3, "numbers", "5 machines make 5 parts in 5 minutes. How long do 100 machines take to make 100 parts?", "100 minutes", "5 minutes", "20 minutes", "B"),
  q("h4", 3, "code", "total starts at 0. A loop runs i = 1, 2, 3 and does total = total + i. What is total at the end?", "3", "6", "9", "B"),
  q("h5", 3, "logic", "Four friends sit in a row. Dev is at the far left. Asha is somewhere left of Ben, and Chirag is somewhere right of Ben. Who is at the far right?", "Ben", "Chirag", "Asha", "B"),
  q("h6", 3, "numbers", "The average of 4 numbers is 15. Three of them are 10, 12 and 20. What is the fourth?", "18", "15", "23", "A"),
  q("h7", 3, "pattern", "What comes next: 2, 6, 12, 20, 30, ?", "40", "42", "44", "B"),
  q("h8", 3, "code", "A list holds [4, 8, 15]. Counting positions from 0, what is at position 2?", "8", "15", "4", "B"),
];

export const TOTAL_QUESTIONS = 4;

export function byId(id?: string): Question | undefined {
  return QUESTION_BANK.find((x) => x.id === id);
}

export function emptyAptitude(): AptitudeState {
  return { status: "not_started", asked: [], answers: [], level: 2, correct: 0, points: 0 };
}

export function normalise(a?: Partial<AptitudeState> | null): AptitudeState {
  const base = emptyAptitude();
  if (!a) return base;
  return {
    ...base,
    ...a,
    asked: Array.isArray(a.asked) ? a.asked : [],
    answers: Array.isArray(a.answers) ? a.answers : [],
    level: clampLevel(Number(a.level ?? 2)),
  };
}

/** Has this person written code before? Decides whether code-reading questions are fair. */
export function hasCoded(profile?: Record<string, string>): boolean {
  const exp = (profile?.codingExperience ?? "").toLowerCase().trim();
  if (exp) return !/^(none|no|never|zero|nil|unknown)/.test(exp);
  const edu = `${profile?.education ?? ""} ${profile?.background ?? ""}`.toLowerCase();
  return /\bbca\b|\bmca\b|computer science|b\.?\s?tech.*(cs|it|computer)|b\.?sc.*(cs|it|computer)|\bcse\b/.test(edu);
}

/** The next question at [level] that has not been asked, rotating topics. */
export function pickQuestion(level: Level, asked: string[], allowCode: boolean): Question | undefined {
  const lastTopic = byId(asked[asked.length - 1])?.topic;
  const pool = QUESTION_BANK.filter((x) => !asked.includes(x.id) && (allowCode || x.topic !== "code"));
  const order: Level[] = level === 1 ? [1, 2, 3] : level === 3 ? [3, 2, 1] : [2, 1, 3];
  for (const l of order) {
    const atLevel = pool.filter((x) => x.level === l);
    const fresh = atLevel.find((x) => x.topic !== lastTopic) ?? atLevel[0];
    if (fresh) return fresh;
  }
  return undefined;
}

export function clampLevel(n: number): Level {
  return (n < 1 ? 1 : n > 3 ? 3 : n) as Level;
}

export function bandFor(points: number): NonNullable<AptitudeState["band"]> {
  if (points >= 7) return "strong";
  if (points >= 4) return "intermediate";
  return "beginner";
}

export function resultText(s: AptitudeState): string {
  const band = s.band ?? bandFor(s.points ?? 0);
  const reached = s.answers.length ? Math.max(...s.answers.map((x) => x.level)) : 2;
  const levelName = ["", "easy", "medium", "hard"][reached];
  const advice =
    band === "strong"
      ? "Strong logical reasoning: can start a full-stack or data track directly."
      : band === "intermediate"
        ? "Good foundation: a full-stack track is fine with steady daily practice; a short foundations course first is optional."
        : "Logic needs building: start with a foundations course before a full-stack or data track.";
  return `${s.correct}/${s.answers.length} correct, reached ${levelName} level, ${s.points ?? 0}/11 points (${band}). ${advice}`;
}

/** What Asha may ask next, depending on whether the current answer turns out right or wrong. */
export interface AptitudePlan {
  state: AptitudeState;
  current?: Question;
  first?: Question;
  nextIfCorrect?: Question;
  nextIfWrong?: Question;
  finishesAfterThis: boolean;
  resultIfCorrect?: string;
  resultIfWrong?: string;
}

function simulate(s: AptitudeState, cur: Question, correct: boolean): AptitudeState {
  const answers = [...s.answers, { id: cur.id, picked: correct ? cur.answer : "?", correct, level: cur.level }];
  const points = answers.filter((a) => a.correct).reduce((sum, a) => sum + a.level, 0);
  const done = answers.length >= TOTAL_QUESTIONS;
  const next: AptitudeState = {
    ...s,
    answers,
    correct: answers.filter((a) => a.correct).length,
    points,
    level: clampLevel(s.level + (correct ? 1 : -1)),
    current: undefined,
    status: done ? "done" : "in_progress",
  };
  if (done) {
    next.band = bandFor(points);
    next.result = resultText(next);
  }
  return next;
}

export function plan(raw: Partial<AptitudeState> | undefined, profile?: Record<string, string>): AptitudePlan {
  const s = normalise(raw);
  const allowCode = hasCoded(profile);
  if (s.status === "done" || s.status === "skipped") return { state: s, finishesAfterThis: false };
  const current = byId(s.current);
  if (!current) {
    return { state: s, first: pickQuestion(clampLevel(s.level), s.asked, allowCode), finishesAfterThis: false };
  }
  const ifRight = simulate(s, current, true);
  const ifWrong = simulate(s, current, false);
  const finishes = ifRight.status === "done";
  return {
    state: s,
    current,
    finishesAfterThis: finishes,
    nextIfCorrect: finishes ? undefined : pickQuestion(clampLevel(ifRight.level), [...s.asked], allowCode),
    nextIfWrong: finishes ? undefined : pickQuestion(clampLevel(ifWrong.level), [...s.asked], allowCode),
    resultIfCorrect: finishes ? ifRight.result : undefined,
    resultIfWrong: finishes ? ifWrong.result : undefined,
  };
}

/** Reads "B", "b)", "option b", "(B) 48", "बी", or the option text itself. */
export function readPick(raw: string | undefined, current?: Question): "A" | "B" | "C" | undefined {
  if (!raw) return undefined;
  const t = raw.trim();
  const m = t.match(/^\(?\s*([abcABC])\s*[).:\-]?(\s|$)/) || t.match(/\boption\s*([abc])\b/i) || t.match(/^([abc])$/i);
  if (m) {
    // "A) 10" when A is 9 and B is 10: the value they typed wins over the letter.
    const rest = t.slice(m[0].length).trim().toLowerCase();
    const byText = rest && current?.options.find((o) => o.text.toLowerCase() === rest);
    if (byText) return byText.key;
    return m[1].toUpperCase() as "A" | "B" | "C";
  }
  if (/^(ए|अ)$/.test(t)) return "A";
  if (/^(बी|ब)$/.test(t)) return "B";
  if (/^(सी|क)$/.test(t)) return "C";
  if (current) {
    const hit = current.options.find((o) => o.text.toLowerCase() === t.toLowerCase());
    if (hit) return hit.key;
  }
  return undefined;
}

/**
 * Applies one turn. [picked] is the letter the prospect chose (from the model, double
 * checked by readPick), [shownId] the question Asha put in this reply, [event] whether
 * they agreed to start or asked to stop.
 */
export function advance(
  raw: Partial<AptitudeState> | undefined,
  input: { picked?: string; shownId?: string; event?: string; userText?: string },
  profile?: Record<string, string>,
): { state: AptitudeState; scored?: { id: string; correct: boolean; picked: string } } {
  let s = normalise(raw);
  if (s.status === "done" || s.status === "skipped") return { state: s };
  const ev = (input.event ?? "").toLowerCase();
  if (ev === "skipped" || ev === "declined") return { state: { ...s, status: "skipped", current: undefined } };
  if (ev === "offered" && s.status === "not_started") s = { ...s, status: "offered" };

  let scored: { id: string; correct: boolean; picked: string } | undefined;
  const current = byId(s.current);
  if (current) {
    const picked = readPick(input.userText, current) ?? readPick(input.picked, current);
    if (picked) {
      const correct = picked === current.answer;
      const answers = [...s.answers, { id: current.id, picked, correct, level: current.level }];
      const points = answers.filter((a) => a.correct).reduce((sum, a) => sum + a.level, 0);
      s = {
        ...s,
        answers,
        correct: answers.filter((a) => a.correct).length,
        points,
        level: clampLevel(s.level + (correct ? 1 : -1)),
        current: undefined,
        status: answers.length >= TOTAL_QUESTIONS ? "done" : "in_progress",
      };
      if (s.status === "done") {
        s.band = bandFor(points);
        s.result = resultText(s);
      }
      scored = { id: current.id, correct, picked };
    }
  }

  // Whatever question is now on the prospect's screen is the one we wait for.
  const shown = byId(input.shownId);
  if (s.status !== "done" && shown && !s.answers.some((a) => a.id === shown.id)) {
    s = { ...s, current: shown.id, asked: s.asked.includes(shown.id) ? s.asked : [...s.asked, shown.id], status: "in_progress" };
  } else if (s.status !== "done" && !s.current && (ev === "started" || ev === "start")) {
    const next = pickQuestion(clampLevel(s.level), s.asked, hasCoded(profile));
    if (next) s = { ...s, current: next.id, asked: [...s.asked, next.id], status: "in_progress" };
  }
  return { state: s, scored };
}

export function formatQuestion(x?: Question): string {
  if (!x) return "none";
  return `${x.id} [level ${x.level}] ${x.text}  A) ${x.options[0].text}  B) ${x.options[1].text}  C) ${x.options[2].text}`;
}
