import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

if (getApps().length === 0) initializeApp();

export const db = getFirestore();
export { FieldValue, Timestamp };

export type Channel = "web" | "whatsapp" | "form" | "walkin" | "call" | "instagram";
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
}

export interface Lead {
  name?: string;
  nameLatin?: string;
  aliases?: string[];
  phone?: string;
  email?: string;
  sources?: Channel[];
  firstSource?: Channel;
  lastChannel?: Channel;
  waId?: string;
  city?: string;
  language?: string;
  script?: string;
  register?: string;
  profile?: Record<string, string>;
  objections?: string[];
  score?: number;
  temperature?: string;
  summary?: string[];
  suggestedMessage?: string;
  nextAction?: { at: Timestamp; channel: string; message: string; reason: string; done: boolean };
  aptitude?: Record<string, unknown>;
  recommendation?: { courseId: string; reason: string };
  booking?: {
    slotId: string;
    startAt: Timestamp;
    title: string;
    calendarUrl: string;
    reminded24?: boolean;
    reminded1?: boolean;
  };
  aiPaused?: boolean;
  assignedTo?: string;
  status?: string;
  mergedInto?: string;
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
