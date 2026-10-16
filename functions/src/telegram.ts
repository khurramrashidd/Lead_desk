/**
 * Telegram channel. Free, instant, and a judge can join it from the QR on screen.
 * The bot token is set in Admin → Channels (or TELEGRAM_BOT_TOKEN in .env).
 */
import { db, FieldValue, type Lead } from "./db";
import { latinName, resolveIdentity } from "./merge";
import { normalizePhone } from "./identity";

let cached: { token: string; at: number } | null = null;

export async function telegramToken(): Promise<string> {
  if (cached && Date.now() - cached.at < 30_000) return cached.token;
  let token = process.env.TELEGRAM_BOT_TOKEN ?? "";
  try {
    const snap = await db.doc("config/channels").get();
    token = (snap.get("telegramBotToken") as string | undefined)?.trim() || token;
  } catch {
    // fall back to the env value
  }
  cached = { token, at: Date.now() };
  return token;
}

export function clearTelegramCache(): void {
  cached = null;
}

async function api(method: string, body: unknown): Promise<Record<string, unknown>> {
  const token = await telegramToken();
  if (!token) throw new Error("No Telegram bot token set (Admin → Channels).");
  const res = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const json = (await res.json()) as Record<string, unknown>;
  if (!json.ok) throw new Error(`Telegram ${method} failed: ${JSON.stringify(json).slice(0, 300)}`);
  return json;
}

export async function sendTelegram(chatId: string, text: string): Promise<boolean> {
  try {
    await api("sendMessage", { chat_id: chatId, text: text.slice(0, 4000) });
    return true;
  } catch (e) {
    console.error("telegram send failed", e);
    return false;
  }
}

/** Points Telegram at our webhook. Called from the Admin console. */
export async function setTelegramWebhook(url: string, secret: string): Promise<Record<string, unknown>> {
  return api("setWebhook", {
    url,
    secret_token: secret,
    allowed_updates: ["message"],
    drop_pending_updates: true,
  });
}

export async function telegramBotInfo(): Promise<Record<string, unknown>> {
  const token = await telegramToken();
  if (!token) throw new Error("No Telegram bot token set.");
  const res = await fetch(`https://api.telegram.org/bot${token}/getMe`);
  const json = (await res.json()) as Record<string, unknown>;
  if (!json.ok) throw new Error(`Telegram getMe failed: ${JSON.stringify(json).slice(0, 300)}`);
  return json.result as Record<string, unknown>;
}

async function downloadVoice(fileId: string): Promise<{ b64: string; mime: string } | null> {
  const token = await telegramToken();
  const metaRes = await fetch(`https://api.telegram.org/bot${token}/getFile?file_id=${fileId}`);
  const meta = (await metaRes.json()) as { ok: boolean; result?: { file_path?: string } };
  if (!meta.ok || !meta.result?.file_path) return null;
  const fileRes = await fetch(`https://api.telegram.org/file/bot${token}/${meta.result.file_path}`);
  if (!fileRes.ok) return null;
  const buf = Buffer.from(await fileRes.arrayBuffer());
  if (buf.length > 700_000) return null; // keep the Firestore document under 1 MB
  const mime = meta.result.file_path.endsWith(".oga") || meta.result.file_path.endsWith(".ogg")
    ? "audio/ogg"
    : "audio/mpeg";
  return { b64: buf.toString("base64"), mime };
}

async function leadForTelegram(chatId: string, from: { first_name?: string; last_name?: string; username?: string }): Promise<string> {
  const existing = await db.collection("leads").where("telegramId", "==", chatId).limit(5).get();
  const live = existing.docs.find((d) => !(d.data() as Lead).mergedInto);
  if (live) return live.id;

  const name = [from.first_name, from.last_name].filter(Boolean).join(" ").trim();
  const ref = db.collection("leads").doc();
  await ref.set({
    name,
    nameLatin: latinName(name) ?? "",
    studentName: name,
    telegramId: chatId,
    telegramUsername: from.username ?? "",
    contacts: [{ name, relation: "self", channel: "telegram", isPrimary: true }],
    contactPhones: [],
    sources: ["telegram"],
    firstSource: "telegram",
    lastChannel: "telegram",
    status: "new",
    score: 0,
    createdAt: FieldValue.serverTimestamp(),
    lastMessageAt: FieldValue.serverTimestamp(),
  });
  await resolveIdentity(ref.id);
  const after = (await ref.get()).data() as Lead;
  return after.mergedInto ?? ref.id;
}

interface TgMessage {
  message_id: number;
  chat: { id: number };
  from?: { first_name?: string; last_name?: string; username?: string };
  text?: string;
  caption?: string;
  voice?: { file_id: string };
  audio?: { file_id: string };
  contact?: { phone_number?: string; first_name?: string };
}

/** Handles one Telegram update. */
export async function handleTelegramUpdate(body: { message?: TgMessage }): Promise<void> {
  const m = body?.message;
  if (!m?.chat?.id) return;
  const chatId = String(m.chat.id);
  const leadId = await leadForTelegram(chatId, m.from ?? {});
  const leadRef = db.doc(`leads/${leadId}`);

  const msg: Record<string, unknown> = {
    role: "user",
    channel: "telegram",
    createdAt: FieldValue.serverTimestamp(),
    meta: { telegramMessageId: m.message_id },
  };

  if (m.voice || m.audio) {
    const media = await downloadVoice((m.voice ?? m.audio)!.file_id);
    if (media) {
      msg.audioB64 = media.b64;
      msg.audioMime = media.mime;
      msg.text = m.caption ?? "🎤 Voice note";
    } else {
      msg.text = "(voice note could not be downloaded)";
    }
  } else if (m.contact?.phone_number) {
    const phone = normalizePhone(m.contact.phone_number);
    msg.text = `My number is ${phone ?? m.contact.phone_number}`;
    if (phone) {
      await leadRef.set({ phone, contactPhones: FieldValue.arrayUnion(phone) }, { merge: true });
    }
  } else {
    msg.text = m.text ?? m.caption ?? "(unsupported message)";
  }

  await leadRef.set(
    {
      telegramId: chatId,
      lastChannel: "telegram",
      sources: FieldValue.arrayUnion("telegram"),
      lastInboundAt: FieldValue.serverTimestamp(),
      lastMessageAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  // Idempotent: Telegram retries an update it thinks failed.
  await leadRef.collection("messages").doc(`tg_${m.message_id}`).create(msg).catch(() => undefined);
}
