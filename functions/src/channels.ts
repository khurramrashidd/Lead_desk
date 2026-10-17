/**
 * Channel credentials and sending: WhatsApp, Telegram, Instagram.
 * Credentials come from Admin → Channels (Firestore config/channels), else functions/.env.
 * Leads created by the built-in simulators carry ids starting with "sim:" and are never
 * sent to a real phone.
 */
import { db, type Lead } from "./db";
import type { ObOption } from "./onboarding";

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
  /** Ask who / name / contact / course before counselling (Admin → Channels). Default on. */
  onboarding: boolean;
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
    onboarding: s.onboarding === undefined ? !/^(off|false|0|no)$/i.test(process.env.ONBOARDING ?? "") : s.onboarding !== false,
  };
  cache = { cfg, at: Date.now() };
  return cfg;
}

export function clearChannelCache(): void {
  cache = null;
}

const isSim = (id?: string) => !id || id.startsWith("sim:");

export interface SendResult {
  ok: boolean;
  error?: string;
}

/** Tappable choices that ride along with a message (intake questions, aptitude A/B/C). */
export interface SendExtras {
  options?: ObOption[];
  /** Telegram: add a "share my number" button. */
  askContact?: boolean;
  lang?: string;
}

function cut(s: string, n: number): string {
  const chars = [...(s ?? "")];
  return chars.length <= n ? s : chars.slice(0, n - 1).join("") + "…";
}

/** The options as a numbered list, for channels without buttons. */
export function withNumberedOptions(text: string, options?: ObOption[]): string {
  if (!options?.length) return text;
  return `${text}\n\n${options.map((o, i) => `${i + 1}. ${o.label}`).join("\n")}`;
}

async function graphError(res: Response): Promise<string> {
  const body = (await res.text()).slice(0, 400);
  try {
    const j = JSON.parse(body) as { error?: { message?: string; code?: number; error_data?: { details?: string } } };
    const e = j.error;
    if (e) return `(#${e.code ?? res.status}) ${e.error_data?.details ?? e.message ?? body}`.slice(0, 240);
  } catch {
    // not JSON
  }
  return `${res.status} ${body}`.slice(0, 240);
}

async function waPost(payload: Record<string, unknown>): Promise<SendResult> {
  const c = await channelConfig();
  if (!c.waToken || !c.waPhoneId) return { ok: false, error: "WhatsApp not connected (Admin → Channels)" };
  try {
    const res = await fetch(`https://graph.facebook.com/${c.graphVersion}/${c.waPhoneId}/messages`, {
      method: "POST",
      headers: { Authorization: `Bearer ${c.waToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({ messaging_product: "whatsapp", recipient_type: "individual", ...payload }),
      signal: AbortSignal.timeout(15_000),
    });
    if (res.ok) return { ok: true };
    const error = await graphError(res);
    console.error("WhatsApp send failed", error);
    return { ok: false, error };
  } catch (e) {
    return { ok: false, error: String((e as Error)?.message ?? e).slice(0, 200) };
  }
}

export async function sendWhatsAppText(toWaId: string, body: string): Promise<SendResult> {
  if (isSim(toWaId)) return { ok: false, error: "simulated" };
  return waPost({ to: toWaId, type: "text", text: { body: body.slice(0, 4000), preview_url: true } });
}

/** Reply buttons (up to 3) or a list (up to 10 rows); plain numbered text if Meta refuses. */
export async function sendWhatsAppChoices(toWaId: string, body: string, options: ObOption[], lang?: string): Promise<SendResult> {
  if (isSim(toWaId)) return { ok: false, error: "simulated" };
  const text = body.slice(0, 1000);
  const interactive =
    options.length <= 3
      ? {
          type: "button",
          body: { text },
          action: { buttons: options.map((o) => ({ type: "reply", reply: { id: o.id.slice(0, 256), title: cut(o.label, 20) } })) },
        }
      : {
          type: "list",
          body: { text },
          action: {
            button: lang === "hi" ? "विकल्प देखें" : lang === "mr" ? "पर्याय पहा" : "See options",
            sections: [
              {
                title: lang === "hi" ? "चुनिए" : lang === "mr" ? "निवडा" : "Choose one",
                rows: options.slice(0, 10).map((o) => ({
                  id: o.id.slice(0, 200),
                  title: cut(o.label, 24),
                  ...(o.description ? { description: cut(o.description, 72) } : {}),
                })),
              },
            ],
          },
        };
  const r = await waPost({ to: toWaId, type: "interactive", interactive });
  if (r.ok || /not connected/.test(r.error ?? "")) return r;
  console.warn("WhatsApp interactive refused, sending text instead:", r.error);
  return sendWhatsAppText(toWaId, withNumberedOptions(body, options));
}

export async function sendTelegram(chatId: string, text: string, extras: SendExtras = {}): Promise<SendResult> {
  if (isSim(chatId)) return { ok: false, error: "simulated" };
  const c = await channelConfig();
  if (!c.telegramBotToken) return { ok: false, error: "Telegram not connected (Admin → Channels)" };
  const rows: Record<string, unknown>[][] = [];
  if (extras.askContact) {
    rows.push([{ text: extras.lang === "hi" ? "📱 मेरा नंबर भेजें" : extras.lang === "mr" ? "📱 माझा नंबर पाठवा" : "📱 Share my number", request_contact: true }]);
  }
  for (const o of extras.options ?? []) rows.push([{ text: o.label }]);
  const reply_markup = rows.length ? { keyboard: rows, one_time_keyboard: true, resize_keyboard: true } : { remove_keyboard: true };
  try {
    const res = await fetch(`https://api.telegram.org/bot${c.telegramBotToken}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ chat_id: chatId, text: text.slice(0, 4000), reply_markup }),
      signal: AbortSignal.timeout(15_000),
    });
    if (res.ok) return { ok: true };
    const error = `${res.status} ${(await res.text()).slice(0, 200)}`;
    console.error("telegram send failed", error);
    return { ok: false, error };
  } catch (e) {
    console.error("telegram send error", e);
    return { ok: false, error: String((e as Error)?.message ?? e).slice(0, 200) };
  }
}

/** Instagram API with Instagram Login: reply to a DM inside the 24 h window. */
export async function sendInstagram(igScopedId: string, text: string): Promise<SendResult> {
  if (isSim(igScopedId)) return { ok: false, error: "simulated" };
  const c = await channelConfig();
  if (!c.igToken) return { ok: false, error: "Instagram not connected (Admin → Channels)" };
  const who = c.igUserId || "me";
  try {
    const res = await fetch(`https://graph.instagram.com/${c.graphVersion}/${who}/messages`, {
      method: "POST",
      headers: { Authorization: `Bearer ${c.igToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({ recipient: { id: igScopedId }, message: { text: text.slice(0, 1000) } }),
      signal: AbortSignal.timeout(15_000),
    });
    if (res.ok) return { ok: true };
    const error = await graphError(res);
    console.error("Instagram send failed", error);
    return { ok: false, error };
  } catch (e) {
    return { ok: false, error: String((e as Error)?.message ?? e).slice(0, 200) };
  }
}

/** Sends [text] to the lead on [channel] if that channel can deliver right now. */
export async function deliverOn(channel: string, lead: Lead, text: string, extras: SendExtras = {}): Promise<{ delivered: boolean; note: string }> {
  const options = extras.options ?? [];
  switch (channel) {
    case "whatsapp": {
      if (!lead.waId) return { delivered: false, note: "no WhatsApp id" };
      if (isSim(lead.waId)) return { delivered: true, note: "simulated WhatsApp" };
      const r = options.length ? await sendWhatsAppChoices(lead.waId, text, options, extras.lang) : await sendWhatsAppText(lead.waId, text);
      return { delivered: r.ok, note: r.error ?? "" };
    }
    case "telegram": {
      if (!lead.telegramId) return { delivered: false, note: "no Telegram chat" };
      if (isSim(lead.telegramId)) return { delivered: true, note: "simulated Telegram" };
      const r = await sendTelegram(lead.telegramId, text, extras);
      return { delivered: r.ok, note: r.error ?? "" };
    }
    case "instagram": {
      if (!lead.igId) return { delivered: false, note: "no Instagram id" };
      if (isSim(lead.igId)) return { delivered: true, note: "simulated Instagram" };
      const r = await sendInstagram(lead.igId, withNumberedOptions(text, options));
      return { delivered: r.ok, note: r.error ?? "" };
    }
    default:
      // web chat, form, walk-in: the message is in the timeline the student's chat is reading
      return { delivered: true, note: "" };
  }
}
