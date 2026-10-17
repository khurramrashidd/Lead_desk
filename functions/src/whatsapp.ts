/**
 * Meta webhook: WhatsApp Cloud API and Instagram DMs arrive at the same endpoint (metaWebhook).
 * Text and voice notes are stored on the lead; the message trigger makes Asha answer.
 */
import { channelConfig } from "./channels";
import { addInbound, findOrCreateLead } from "./leads";

async function downloadWaMedia(mediaId: string): Promise<{ b64: string; mime: string } | null> {
  const c = await channelConfig();
  const auth = { Authorization: `Bearer ${c.waToken}` };
  const meta = await fetch(`https://graph.facebook.com/${c.graphVersion}/${mediaId}`, { headers: auth });
  if (!meta.ok) return null;
  const info = (await meta.json()) as { url: string; mime_type: string };
  const file = await fetch(info.url, { headers: auth });
  if (!file.ok) return null;
  const buf = Buffer.from(await file.arrayBuffer());
  if (buf.length > 700_000) return null; // keep Firestore documents small
  return { b64: buf.toString("base64"), mime: (info.mime_type || "audio/ogg").split(";")[0].trim() };
}

async function downloadUrl(url: string): Promise<{ b64: string; mime: string } | null> {
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(15_000) });
    if (!res.ok) return null;
    const buf = Buffer.from(await res.arrayBuffer());
    if (buf.length > 700_000) return null;
    return { b64: buf.toString("base64"), mime: (res.headers.get("content-type") || "audio/mp4").split(";")[0].trim() };
  } catch {
    return null;
  }
}

interface WaMessage {
  from: string;
  id: string;
  type: string;
  text?: { body: string };
  audio?: { id: string };
  voice?: { id: string };
  button?: { text: string; payload?: string };
  interactive?: { button_reply?: { id?: string; title: string }; list_reply?: { id?: string; title: string } };
}

async function handleWhatsApp(value: any): Promise<void> {
  const contacts: { wa_id: string; profile?: { name?: string } }[] = value?.contacts ?? [];
  for (const m of (value?.messages ?? []) as WaMessage[]) {
    const profileName = contacts.find((c) => c.wa_id === m.from)?.profile?.name;
    const leadId = await findOrCreateLead({ channel: "whatsapp", name: profileName, phone: m.from, waId: m.from });
    const msg: { id: string; text?: string; audioB64?: string; audioMime?: string; meta: Record<string, unknown> } = {
      id: `wa_${m.id}`,
      meta: { waMessageId: m.id },
    };
    const audio = m.audio ?? m.voice;
    if (m.type === "text" && m.text) msg.text = m.text.body;
    else if (audio) {
      const media = await downloadWaMedia(audio.id);
      if (media) {
        msg.audioB64 = media.b64;
        msg.audioMime = media.mime;
        msg.text = "🎤 Voice note";
      } else msg.text = "(voice note could not be downloaded)";
    } else if (m.button?.text) msg.text = m.button.text;
    else if (m.interactive) {
      // A tapped button / list row: keep its id so the intake questions match it exactly.
      const pick = m.interactive.button_reply ?? m.interactive.list_reply;
      msg.text = pick?.title ?? "(reply)";
      if (pick?.id) msg.meta.choiceId = pick.id;
    }
    else msg.text = `(${m.type} message)`;
    await addInbound(leadId, "whatsapp", msg, { waId: m.from });
  }
}

interface IgMessaging {
  sender?: { id: string };
  recipient?: { id: string };
  message?: { mid: string; text?: string; is_echo?: boolean; attachments?: { type: string; payload?: { url?: string } }[] };
}

async function handleInstagram(entry: any): Promise<void> {
  const c = await channelConfig();
  for (const ev of (entry?.messaging ?? []) as IgMessaging[]) {
    const m = ev.message;
    const from = ev.sender?.id;
    if (!m || !from || m.is_echo || from === c.igUserId) continue; // our own replies echo back
    const leadId = await findOrCreateLead({ channel: "instagram", igId: from, name: "" });
    const msg: { id: string; text?: string; audioB64?: string; audioMime?: string; meta: Record<string, unknown> } = {
      id: `ig_${m.mid}`.replace(/[^\w-]/g, "_").slice(0, 120),
      meta: { igMessageId: m.mid },
    };
    const audio = m.attachments?.find((a) => a.type === "audio");
    if (m.text) msg.text = m.text;
    else if (audio?.payload?.url) {
      const media = await downloadUrl(audio.payload.url);
      if (media) {
        msg.audioB64 = media.b64;
        msg.audioMime = media.mime;
        msg.text = "🎤 Voice note";
      } else msg.text = "(voice note could not be downloaded)";
    } else msg.text = `(${m.attachments?.[0]?.type ?? "unsupported"} message)`;
    await addInbound(leadId, "instagram", msg, { igId: from });
  }
}

/** Handles one webhook POST body from Meta (WhatsApp or Instagram). */
export async function handleMetaWebhook(body: any): Promise<void> {
  if (body?.object === "instagram") {
    for (const entry of body?.entry ?? []) await handleInstagram(entry);
    return;
  }
  for (const entry of body?.entry ?? []) {
    for (const change of entry?.changes ?? []) {
      if (change?.field === "messages" && change?.value?.messages) await handleWhatsApp(change.value);
    }
  }
}
