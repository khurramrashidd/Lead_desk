import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

if (getApps().length === 0) initializeApp();

export const db = getFirestore();
export { FieldValue, Timestamp };

/** Every place an enquiry can arrive from. */
export type Channel =
  | "web"
  | "whatsapp"
  | "telegram"
  | "instagram"
  | "form"
  | "googleform"
  | "walkin"
  | "call";

export const CHANNELS: Channel[] = ["web", "whatsapp", "telegram", "instagram", "form", "googleform", "walkin", "call"];

export type Role = "user" | "ai" | "counsellor" | "system";

export interface Course {
  id: string;
  name: string;
  durationWeeks: number;
  mode: string;
  feeInr: number;
  emi?: { months: number; perMonthInr: number };
  prerequisites?: string;
  idealFor?: string;
  outcomes?: string;
  nextBatch?: string;
}

export interface KnowledgeBase {
  instituteName: string;
  city: string;
  address?: string;
  courses: Course[];
  scholarships?: { id: string; name: string; rule: string; percentOff?: number; amountOffInr?: number }[];
  policies?: Record<string, string>;
  faqs?: { q: string; a: string }[];
}

export interface Slot {
  id: string;
  courseId?: string;
  title: string;
  startAt: Timestamp;
  durationMin: number;
  mode: string;
  capacity: number;
  booked: number;
  kind?: "demo" | "call" | "meet";
}

/** One person who enquired about this admission: the student, a parent, a friend. */
export interface LeadContact {
  name: string;
  phone?: string;
  email?: string;
  relation: string; // self | parent | guardian | sibling | friend | other
  channel: Channel | string;
  isPrimary?: boolean;
}

export interface AptitudeState {
  status: "not_started" | "offered" | "in_progress" | "done" | "skipped";
  asked: string[]; // question ids in order
  answers: { id: string; picked: string; correct: boolean; level: number }[];
  current?: string; // question id waiting for an answer
  level: number; // 1 easy, 2 medium, 3 hard
  correct: number;
  points?: number; // difficulty-weighted
  band?: "beginner" | "intermediate" | "strong";
  result?: string;
}

export interface ScoreBreakdown {
  fit: number;
  intent: number;
  engagement: number;
  recency: number;
  aptitude: number;
  aiRead: number;
  objections: number; // negative
  reasons: string[];
}

export interface NextAction {
  at: Timestamp;
  channel: string;
  message: string;
  reason: string;
  playbook: string;
  done: boolean;
}

export interface Lead {
  name?: string;
  nameLatin?: string;
  aliases?: string[];
  viewerUids?: string[];
  phone?: string;
  email?: string;
  studentName?: string;
  studentPhone?: string;
  contacts?: LeadContact[];
  contactPhones?: string[];
  sources?: Channel[];
  firstSource?: Channel;
  lastChannel?: Channel;
  waId?: string;
  telegramId?: string;
  igId?: string;
  city?: string;
  language?: string;
  script?: string;
  register?: string;
  profile?: Record<string, string>;
  objections?: string[];
  score?: number;
  scoreBreakdown?: ScoreBreakdown;
  aiScore?: number;
  temperature?: string;
  summary?: string[];
  suggestedMessage?: string;
  nextAction?: NextAction;
  aptitude?: AptitudeState;
  recommendation?: { courseId: string; courseName?: string; reason: string };
  booking?: {
    slotId: string;
    startAt: Timestamp;
    title: string;
    calendarUrl: string;
    calendarEventId?: string;
    calendarEventLink?: string;
    meetLink?: string;
    reminded24?: boolean;
    reminded1?: boolean;
  };
  aiPaused?: boolean;
  assignedTo?: string;
  assignedUid?: string;
  assignedLang?: string;
  assignedManually?: boolean;
  possibleDuplicateOf?: string;
  simulated?: boolean;
  handoffReason?: string;
  hotAlerted?: boolean;
  status?: string;
  mergedInto?: string;
  needsHuman?: boolean;
  followupsSent?: number;
  unansweredFollowups?: number;
  userMessages?: number;
  voiceNotes?: number;
  seed?: boolean;
  lastInboundAt?: Timestamp;
  lastMessageAt?: Timestamp;
  createdAt?: Timestamp;
}

export interface Message {
  role: Role;
  channel: Channel;
  text?: string;
  transcript?: string;
  audioB64?: string;
  audioMime?: string;
  createdAt?: Timestamp;
  meta?: Record<string, unknown>;
  seed?: boolean;
  mergedFrom?: string;
}

/** Demo clock: lets the "Fast-forward" button move time without waiting. */
export async function demoNow(): Promise<Date> {
  const snap = await db.doc("config/demo").get();
  const offsetMin = (snap.get("clockOffsetMinutes") as number | undefined) ?? 0;
  return new Date(Date.now() + offsetMin * 60_000);
}

export async function logEvent(type: string, leadId: string | null, data: Record<string, unknown>): Promise<void> {
  await db.collection("events").add({ type, leadId, data, at: FieldValue.serverTimestamp() });
}

export function asChannel(source?: string): Channel {
  const s = (source ?? "").toLowerCase().trim();
  if ((CHANNELS as string[]).includes(s)) return s as Channel;
  if (s.includes("google")) return "googleform";
  if (s.includes("insta") || s === "ig") return "instagram";
  if (s.includes("telegram") || s === "tg") return "telegram";
  if (s.includes("whats") || s === "wa") return "whatsapp";
  if (s.includes("call") || s.includes("phone") || s.includes("ivr")) return "call";
  if (s.includes("walk") || s.includes("counter") || s.includes("office")) return "walkin";
  if (s.includes("form")) return "form";
  return "web";
}
