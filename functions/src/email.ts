/**
 * Free e-mail through the institute's own Gmail account (an "app password", Admin → Channels → Email).
 * Used for the enrolment OTP and the admission confirmation. SMS is deliberately not used (paid).
 */
import { db } from "./db";

export interface EmailConfig {
  user: string;
  pass: string;
  name: string;
}

export async function emailConfig(): Promise<EmailConfig> {
  let s: Record<string, unknown> = {};
  try {
    s = (await db.doc("config/channels").get()).data() ?? {};
  } catch {
    // env only
  }
  const pick = (k: string, env: string) => String(s[k] ?? "").trim() || (process.env[env] ?? "").trim();
  return {
    user: pick("smtpUser", "SMTP_USER"),
    // Gmail shows app passwords in groups of four ("abcd efgh ijkl mnop"); spaces are not part of it.
    pass: pick("smtpPass", "SMTP_PASS").replace(/\s+/g, ""),
    name: pick("smtpName", "SMTP_NAME") || "Admissions",
  };
}

export async function emailReady(): Promise<boolean> {
  const c = await emailConfig();
  return !!(c.user && c.pass);
}

async function transport(c: EmailConfig) {
  const nodemailer = await import("nodemailer");
  return nodemailer.createTransport({ host: "smtp.gmail.com", port: 465, secure: true, auth: { user: c.user, pass: c.pass } });
}

export async function sendEmail(to: string, subject: string, text: string): Promise<{ ok: boolean; error?: string }> {
  const c = await emailConfig();
  if (!c.user || !c.pass) return { ok: false, error: "Email not set up (Admin → Channels → Email)" };
  try {
    const t = await transport(c);
    await t.sendMail({ from: `"${c.name.replace(/"/g, "")}" <${c.user}>`, to, subject, text });
    return { ok: true };
  } catch (e) {
    const error = String((e as Error)?.message ?? e).slice(0, 240);
    console.warn("email failed", error);
    return { ok: false, error };
  }
}

/** Admin → Channels → Email → "Save & test": signs in to Gmail and mails the account itself. */
export async function checkEmail(): Promise<{ ok: boolean; detail: string }> {
  const c = await emailConfig();
  if (!c.user || !c.pass) return { ok: false, detail: "Add the Gmail address and the 16-letter app password first." };
  try {
    const t = await transport(c);
    await t.verify();
    await t.sendMail({ from: `"${c.name}" <${c.user}>`, to: c.user, subject: "AI Lead Desk: email works ✅", text: "Enrolment codes and admission confirmations will be sent from this address." });
    return { ok: true, detail: `Signed in as ${c.user}; a test email was sent to it.` };
  } catch (e) {
    return { ok: false, detail: `Gmail refused: ${String((e as Error)?.message ?? e).slice(0, 200)}. Use an App password (Google Account → Security → 2-Step Verification → App passwords), not your normal password.` };
  }
}
