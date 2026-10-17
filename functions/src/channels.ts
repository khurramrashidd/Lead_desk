/**
 * Channel credentials and sending: WhatsApp, Telegram, Instagram.
 * Credentials come from Admin → Channels (Firestore config/channels), else functions/.env.
 * Leads created by the built-in simulators carry ids starting with "sim:" and are never
 * sent to a real phone.
 */
import { db, type Lead } from "./db";

export interface ChannelConfig {
  waToken: string;
  waPhoneId: string;
  waVerifyToken: string;
  graphVersion: string;
  telegramBotToken: string;
  telegramSecret: string;
  igToken: string;
  igUserId: string;
  intakeSecret: string;
}

let cache: { cfg: ChannelConfig; at: number } | null = null;

export async function channelConfig(force = false): Promise<ChannelConfig> {
  if (!force && cache && Date.now() - cache.at < 30_000) return cache.cfg;
  let s: Record<string, unknown> = {};
  try {
    s = (await db.doc("config/channels").get()).data() ?? {};
  } catch {
    // env only
  }
  const pick = (k: string, env: string, def = "") => (String(s[k] ?? "").trim() || (process.env[env] ?? "").trim() || def);
  const cfg: ChannelConfig = {
    waToken: pick("waToken", "WA_TOKEN"),
    waPhoneId: pick("waPhoneId", "WA_PHONE_ID"),
    waVerifyToken: pick("waVerifyToken", "WA_VERIFY_TOKEN", "leaddesk-verify-123"),
    graphVersion: pick("graphVersion", "WA_GRAPH_VERSION", "v23.0"),
    telegramBotToken: pick("telegramBotToken", "TELEGRAM_BOT_TOKEN"),
    telegramSecret: pick("telegramSecret", "TELEGRAM_SECRET", "leaddesk-tg-secret"),
    igToken: pick("igToken", "IG_TOKEN"),
    igUserId: pick("igUserId", "IG_USER_ID"),
    intakeSecret: pick("intakeSecret", "INTAKE_SECRET", "leaddesk-intake-123"),
  };
  cache = { cfg, at: Date.now() };
  return cfg;
}

export function clearChannelCache(): void {
  cache = null;
}

const isSim = (id?: string) => !id || id.startsWith("sim:");

export async function sendWhatsAppText(toWaId: string, body: string): Promise<boolean> {
  if (isSim(toWaId)) return false;
  const c = await channelConfig();
  if (!c.waToken || !c.waPhoneId) return false;
  const res = await fetch(`https://graph.facebook.com/${c.graphVersion}/${c.waPhoneId}/messages`, {
    method: "POST",
    headers: { Authorization: `Bearer ${c.waToken}`, "Content-Type": "application/json" },
    body: JSON.stringify({ messaging_product: "whatsapp", to: toWaId, type: "text", text: { body: body.slice(0, 4000) } }),
    signal: AbortSignal.timeout(15_000),
  });
  if (!res.ok) console.error("WhatsApp send failed", res.status, (await res.text()).slice(0, 300));
  return res.ok;
}

export async function sendTelegram(chatId: string, text: string): Promise<boolean> {
  if (isSim(chatId)) return false;
  const c = await channelConfig();
  if (!c.telegramBotToken) return false;
  try {
    const res = await fetch(`https://api.telegram.org/bot${c.telegramBotToken}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ chat_id: chatId, text: text.slice(0, 4000), disable_web_page_preview: false }),
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) console.error("telegram send failed", res.status, (await res.text()).slice(0, 300));
    return res.ok;
  } catch (e) {
    console.error("telegram send error", e);
    return false;
  }
}

/** Instagram API with Instagram Login: reply to a DM inside the 24 h window. */
export async function sendInstagram(igScopedId: string, text: string): Promise<boolean> {
  if (isSim(igScopedId)) return false;
  const c = await channelConfig();
  if (!c.igToken) return false;
  const who = c.igUserId || "me";
  const res = await fetch(`https://graph.instagram.com/${c.graphVersion}/${who}/messages`, {
    method: "POST",
    headers: { Authorization: `Bearer ${c.igToken}`, "Content-Type": "application/json" },
    body: JSON.stringify({ recipient: { id: igScopedId }, message: { text: text.slice(0, 1000) } }),
    signal: AbortSignal.timeout(15_000),
  });
  if (!res.ok) console.error("Instagram send failed", res.status, (await res.text()).slice(0, 300));
  return res.ok;
}

/** Sends [text] to the lead on [channel] if that channel can deliver right now. */
export async function deliverOn(channel: string, lead: Lead, text: string): Promise<{ delivered: boolean; note: string }> {
  switch (channel) {
    case "whatsapp":
      if (!lead.waId) return { delivered: false, note: "no WhatsApp id" };
      if (isSim(lead.waId)) return { delivered: true, note: "simulated WhatsApp" };
      return { delivered: await sendWhatsAppText(lead.waId, text), note: "" };
    case "telegram":
      if (!lead.telegramId) return { delivered: false, note: "no Telegram chat" };
      if (isSim(lead.telegramId)) return { delivered: true, note: "simulated Telegram" };
      return { delivered: await sendTelegram(lead.telegramId, text), note: "" };
    case "instagram":
      if (!lead.igId) return { delivered: false, note: "no Instagram id" };
      if (isSim(lead.igId)) return { delivered: true, note: "simulated Instagram" };
      return { delivered: await sendInstagram(lead.igId, text), note: "" };
    default:
      // web chat, form, walk-in: the message is in the timeline the student's chat is reading
      return { delivered: true, note: "" };
  }
}
