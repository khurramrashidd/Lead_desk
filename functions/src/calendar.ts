/**
 * Real Google Calendar bookings.
 *
 * No key file needed: the Cloud Functions service account calls the Calendar API.
 * Setup (once, see docs/SETUP_CHANNELS.md):
 *   1. Google Cloud console → enable "Google Calendar API" for this Firebase project.
 *   2. Google Calendar → your "Demo classes" calendar → Settings → Share with specific people →
 *      add the service-account email shown in Admin → Channels → Calendar, with
 *      "Make changes to events".
 *   3. Paste that calendar's Calendar ID in Admin → Channels → Calendar (or CALENDAR_ID in .env).
 *
 * If anything is missing the booking still succeeds in Firestore and the student still gets an
 * Add-to-calendar link; the desk shows that the calendar sync is off.
 */
import { GoogleAuth } from "google-auth-library";
import { db } from "./db";

const SCOPE = "https://www.googleapis.com/auth/calendar";
let auth: GoogleAuth | null = null;
let idCache: { id: string; at: number } | null = null;

function getAuth(): GoogleAuth {
  if (!auth) auth = new GoogleAuth({ scopes: [SCOPE] });
  return auth;
}

export async function calendarId(): Promise<string> {
  if (idCache && Date.now() - idCache.at < 30_000) return idCache.id;
  let id = (process.env.CALENDAR_ID ?? "").trim();
  try {
    const snap = await db.doc("config/channels").get();
    id = ((snap.get("calendarId") as string | undefined) ?? "").trim() || id;
  } catch {
    // keep env value
  }
  idCache = { id, at: Date.now() };
  return id;
}

export function clearCalendarCache(): void {
  idCache = null;
}

async function token(): Promise<string> {
  const client = await getAuth().getClient();
  const t = await client.getAccessToken();
  if (!t.token) throw new Error("no access token for the Calendar API");
  return t.token;
}

export async function serviceAccountEmail(): Promise<string> {
  try {
    const c = await getAuth().getCredentials();
    return c.client_email ?? "";
  } catch (e) {
    return `unknown (${String((e as Error).message).slice(0, 80)})`;
  }
}

export interface CalendarEvent {
  eventId: string;
  htmlLink: string;
}

export async function createCalendarEvent(input: {
  summary: string;
  description: string;
  start: Date;
  durationMin: number;
  location?: string;
}): Promise<CalendarEvent | null> {
  const id = await calendarId();
  if (!id) return null;
  const end = new Date(input.start.getTime() + input.durationMin * 60_000);
  const res = await fetch(`https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(id)}/events`, {
    method: "POST",
    headers: { Authorization: `Bearer ${await token()}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      summary: input.summary,
      description: input.description,
      location: input.location ?? "",
      start: { dateTime: input.start.toISOString(), timeZone: "Asia/Kolkata" },
      end: { dateTime: end.toISOString(), timeZone: "Asia/Kolkata" },
      reminders: { useDefault: false, overrides: [{ method: "popup", minutes: 60 }] },
    }),
    signal: AbortSignal.timeout(15_000),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`Calendar ${res.status}: ${text.slice(0, 300)}`);
  const json = JSON.parse(text) as { id: string; htmlLink: string };
  return { eventId: json.id, htmlLink: json.htmlLink };
}

export async function deleteCalendarEvent(eventId: string): Promise<void> {
  const id = await calendarId();
  if (!id || !eventId) return;
  await fetch(`https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(id)}/events/${encodeURIComponent(eventId)}`, {
    method: "DELETE",
    headers: { Authorization: `Bearer ${await token()}` },
    signal: AbortSignal.timeout(15_000),
  }).catch(() => undefined);
}

/** Admin "Test calendar" button. */
export async function checkCalendar(): Promise<{ ok: boolean; detail: string; serviceAccount: string; calendarId: string }> {
  const sa = await serviceAccountEmail();
  const id = await calendarId();
  if (!id) return { ok: false, detail: "No Calendar ID set yet.", serviceAccount: sa, calendarId: "" };
  try {
    const res = await fetch(`https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(id)}`, {
      headers: { Authorization: `Bearer ${await token()}` },
      signal: AbortSignal.timeout(15_000),
    });
    const text = await res.text();
    if (!res.ok) {
      const hint =
        res.status === 404
          ? "Calendar not found: share it with the service account (Make changes to events) and check the ID."
          : res.status === 403
            ? "Calendar API not enabled for this project, or the calendar is not shared with the service account."
            : "";
      return { ok: false, detail: `${res.status} ${hint} ${text.slice(0, 160)}`.trim(), serviceAccount: sa, calendarId: id };
    }
    const j = JSON.parse(text) as { summary?: string; timeZone?: string };
    return { ok: true, detail: `Connected to "${j.summary ?? id}" (${j.timeZone ?? ""})`, serviceAccount: sa, calendarId: id };
  } catch (e) {
    return { ok: false, detail: String((e as Error).message).slice(0, 300), serviceAccount: sa, calendarId: id };
  }
}
