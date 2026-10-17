/**
 * Telegram channel. Free, instant, and any judge can message the bot from their own phone.
 * The bot token is set in Admin → Channels (or TELEGRAM_BOT_TOKEN in functions/.env).
 */
import { db, FieldValue } from "./db";
import { channelConfig } from "./channels";
import { normalizePhone } from "./identity";
import { addInbound, findOrCreateLead } from "./leads";

async function api(method: string, body: unknown): Promise<Record<string, unknown>> {
  const c = await channelConfig(true);
  if (!c.telegramBotToken) throw new Error("No Telegram bot token set (Admin → Channels).");
  const res = await fetch(`https://api.telegram.org/bot${c.telegramBotToken}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(15_000),
  });
  const json = (await res.json()) as Record<string, unknown>;
  if (!json.ok) throw new Error(`Telegram ${method} failed: ${JSON.stringify(json).slice(0, 300)}`);
  return json;
}

/** Points Telegram at our webhook. Called from the Admin console. */
export async function setTelegramWebhook(url: string): Promise<Record<string, unknown>> {
  const c = await channelConfig(true);
  return api("setWebhook", { url, secret_token: c.telegramSecret, allowed_updates: ["message"], drop_pending_updates: true });
}

export async function telegramBotInfo(): Promise<Record<string, unknown>> {
  const json = await api("getMe", {});
  return json.result as Record<string, unknown>;
}

/** Downloads a Telegram file (voice note or photo) up to [maxBytes]. */
async function downloadFile(fileId: string, maxBytes = 700_000): Promise<{ b64: string; mime: string } | null> {
  const c = await channelConfig();
  const metaRes = await fetch(`https://api.telegram.org/bot${c.telegramBotToken}/getFile?file_id=${encodeURIComponent(fileId)}`);
  const meta = (await metaRes.json()) as { ok: boolean; result?: { file_path?: string } };
  if (!meta.ok || !meta.result?.file_path) return null;
  const fileRes = await fetch(`https://api.telegram.org/file/bot${c.telegramBotToken}/${meta.result.file_path}`);
  if (!fileRes.ok) return null;
  const buf = Buffer.from(await fileRes.arrayBuffer());
  if (buf.length > maxBytes) return null;
  const path = meta.result.file_path.toLowerCase();
  const mime = path.endsWith(".oga") || path.endsWith(".ogg")
    ? "audio/ogg"
    : path.endsWith(".m4a")
      ? "audio/mp4"
      : path.endsWith(".jpg") || path.endsWith(".jpeg")
        ? "image/jpeg"
        : path.endsWith(".png")
          ? "image/png"
          : path.endsWith(".webp")
            ? "image/webp"
            : "audio/mpeg";
  return { b64: buf.toString("base64"), mime };
}

/** Sends a photo (the UPI QR code) with a caption. */
export async function sendTelegramPhoto(chatId: string, png: Buffer, caption: string): Promise<{ ok: boolean; error?: string }> {
  const c = await channelConfig();
  if (!c.telegramBotToken) return { ok: false, error: "Telegram not connected" };
  const form = new FormData();
  form.append("chat_id", chatId);
  form.append("caption", caption.slice(0, 1000));
  form.append("reply_markup", JSON.stringify({ remove_keyboard: true }));
  form.append("photo", new Blob([new Uint8Array(png)], { type: "image/png" }), "upi-qr.png");
  const res = await fetch(`https://api.telegram.org/bot${c.telegramBotToken}/sendPhoto`, { method: "POST", body: form, signal: AbortSignal.timeout(20_000) });
  if (res.ok) return { ok: true };
  return { ok: false, error: `${res.status} ${(await res.text()).slice(0, 200)}` };
}

interface TgMessage {
  message_id: number;
  chat: { id: number };
  from?: { first_name?: string; last_name?: string; username?: string; language_code?: string };
  text?: string;
  caption?: string;
  voice?: { file_id: string };
  photo?: { file_id: string; file_size?: number; width?: number }[];
  document?: { file_id: string; mime_type?: string; file_size?: number };
  audio?: { file_id: string };
  contact?: { phone_number?: string; first_name?: string };
}

/** Handles one Telegram update. */
export async function handleTelegramUpdate(body: { message?: TgMessage }): Promise<{ leadId: string; msgId: string } | null> {
  const m = body?.message;
  if (!m?.chat?.id) return null;
  const chatId = String(m.chat.id);
  const name = [m.from?.first_name, m.from?.last_name].filter(Boolean).join(" ").trim();
  const leadId = await findOrCreateLead({ channel: "telegram", telegramId: chatId, telegramUsername: m.from?.username, name });

  const msg: { id: string; text?: string; audioB64?: string; audioMime?: string; imageB64?: string; imageMime?: string; meta: Record<string, unknown> } = {
    id: `tg_${chatId}_${m.message_id}`,
    meta: { telegramMessageId: m.message_id, ...(m.from?.language_code ? { langHint: m.from.language_code } : {}) },
  };
  const imageDoc = m.document?.mime_type?.startsWith("image/") ? m.document : undefined;
  if (m.text?.startsWith("/start")) {
    // From the website QR / "Talk on Telegram" button (t.me/<bot>?start=web): a fresh chat.
    msg.text = "Hi";
    msg.meta.start = true;
  } else if (m.photo?.length || imageDoc) {
    // A photo, e.g. the payment receipt: the largest size that fits.
    const sizes = [...(m.photo ?? [])].sort((a, b) => (b.file_size ?? 0) - (a.file_size ?? 0));
    const pick = imageDoc ?? sizes.find((p) => (p.file_size ?? 0) <= 700_000) ?? sizes[sizes.length - 1];
    const media = pick ? await downloadFile(pick.file_id) : null;
    if (media) {
      msg.imageB64 = media.b64;
      msg.imageMime = media.mime.startsWith("image/") ? media.mime : "image/jpeg";
      msg.text = m.caption ? `📷 Photo: ${m.caption}` : "📷 Photo";
    } else msg.text = "(photo too large to save: please send a screenshot)";
  } else if (m.voice || m.audio) {
    const media = await downloadFile((m.voice ?? m.audio)!.file_id);
    if (media) {
      msg.audioB64 = media.b64;
      msg.audioMime = media.mime;
      msg.text = m.caption ?? "🎤 Voice note";
    } else msg.text = "(voice note could not be downloaded)";
  } else if (m.contact?.phone_number) {
    const phone = normalizePhone(m.contact.phone_number);
    msg.text = `My number is ${phone ?? m.contact.phone_number}`;
    if (phone) await db.doc(`leads/${leadId}`).set({ phone, contactPhones: FieldValue.arrayUnion(phone) }, { merge: true });
  } else {
    msg.text = m.text ?? m.caption ?? "(unsupported message)";
  }
  const msgId = await addInbound(leadId, "telegram", msg, { telegramId: chatId });
  return { leadId, msgId };
}
