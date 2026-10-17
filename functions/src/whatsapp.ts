/**
 * Meta webhook: WhatsApp Cloud API and Instagram DMs arrive at the same endpoint (metaWebhook).
 * Text and voice notes are stored on the lead; the message trigger makes Asha answer.
 */
import { channelConfig } from "./channels";
import { addInbound, findOrCreateLead } from "./leads";

async function downloadWaMedia(mediaId: string, maxBytes = 700_000): Promise<{ b64: string; mime: string } | null> {
  const c = await channelConfig();
  const auth = { Authorization: `Bearer ${c.waToken}` };
  const meta = await fetch(`https://graph.facebook.com/${c.graphVersion}/${mediaId}`, { headers: auth });
  if (!meta.ok) return null;
  const info = (await meta.json()) as { url: string; mime_type: string };
  const file = await fetch(info.url, { headers: auth });
  if (!file.ok) return null;
  const buf = Buffer.from(await file.arrayBuffer());
  if (buf.length > maxBytes) return null; // keep Firestore documents small
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
  image?: { id: string; caption?: string; mime_type?: string };
  document?: { id: string; caption?: string; mime_type?: string };
  button?: { text: string; payload?: string };
  interactive?: { button_reply?: { id?: string; title: string }; list_reply?: { id?: string; title: string } };
}

export interface Stored {
  leadId: string;
  msgId: string;
}

async function handleWhatsApp(value: any, out: Stored[]): Promise<void> {
  const contacts: { wa_id: string; profile?: { name?: string } }[] = value?.contacts ?? [];
  for (const m of (value?.messages ?? []) as WaMessage[]) {
    const profileName = contacts.find((c) => c.wa_id === m.from)?.profile?.name;
    const leadId = await findOrCreateLead({ channel: "whatsapp", name: profileName, phone: m.from, waId: m.from });
    const msg: { id: string; text?: string; audioB64?: string; audioMime?: string; imageB64?: string; imageMime?: string; meta: Record<string, unknown> } = {
      id: `wa_${m.id}`,
      meta: { waMessageId: m.id },
    };
    const audio = m.audio ?? m.voice;
    const image = m.image ?? (m.document?.mime_type?.startsWith("image/") ? m.document : undefined);
    if (m.type === "text" && m.text) msg.text = m.text.body;
    else if (image) {
      // A photo, e.g. the payment receipt.
      const media = await downloadWaMedia(image.id);
      if (media) {
        msg.imageB64 = media.b64;
        msg.imageMime = media.mime.startsWith("image/") ? media.mime : "image/jpeg";
        msg.text = image.caption ? `📷 Photo: ${image.caption}` : "📷 Photo";
      } else msg.text = "(photo too large to save: please send a screenshot)";
    }
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
    out.push({ leadId, msgId: await addInbound(leadId, "whatsapp", msg, { waId: m.from }) });
  }
}

interface IgMessaging {
  sender?: { id: string };
  recipient?: { id: string };
  message?: { mid: string; text?: string; is_echo?: boolean; attachments?: { type: string; payload?: { url?: string } }[] };
}

async function handleInstagram(entry: any, out: Stored[]): Promise<void> {
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
    out.push({ leadId, msgId: await addInbound(leadId, "instagram", msg, { igId: from }) });
  }
}

/** What a webhook body contained, for Admin → Channels → Diagnose. */
export function describeMetaBody(body: any): string {
  const parts: string[] = [`object=${body?.object ?? "?"}`];
  for (const entry of body?.entry ?? []) {
    for (const change of entry?.changes ?? []) {
      const v = change?.value ?? {};
      const bits = [
        v.messages?.length ? `${v.messages.length} message(s) from ${v.messages.map((m: WaMessage) => m.from).join(",")}` : "",
        v.statuses?.length ? `${v.statuses.length} status(es): ${v.statuses.map((s: { status?: string }) => s.status).join(",")}` : "",
        v.errors?.length ? `errors: ${JSON.stringify(v.errors).slice(0, 200)}` : "",
      ].filter(Boolean);
      parts.push(`${change?.field ?? "?"}${v.metadata?.phone_number_id ? ` to phone_id ${v.metadata.phone_number_id}` : ""}: ${bits.join("; ") || "no messages"}`);
    }
    if (entry?.messaging?.length) parts.push(`instagram messaging x${entry.messaging.length}`);
  }
  return parts.join(" | ").slice(0, 500);
}

/** Handles one webhook POST body from Meta (WhatsApp or Instagram). Returns the stored messages. */
export async function handleMetaWebhook(body: any): Promise<Stored[]> {
  const out: Stored[] = [];
  if (body?.object === "instagram") {
    for (const entry of body?.entry ?? []) await handleInstagram(entry, out);
    return out;
  }
  for (const entry of body?.entry ?? []) {
    for (const change of entry?.changes ?? []) {
      if (change?.field === "messages" && change?.value?.messages) await handleWhatsApp(change.value, out);
    }
  }
  return out;
}

/** Uploads the UPI QR image and sends it with a caption. */
export async function sendWhatsAppImage(toWaId: string, png: Buffer, caption: string): Promise<{ ok: boolean; error?: string }> {
  const c = await channelConfig();
  if (!c.waToken || !c.waPhoneId) return { ok: false, error: "WhatsApp not connected" };
  const form = new FormData();
  form.append("messaging_product", "whatsapp");
  form.append("type", "image/png");
  form.append("file", new Blob([new Uint8Array(png)], { type: "image/png" }), "upi-qr.png");
  const up = await fetch(`https://graph.facebook.com/${c.graphVersion}/${c.waPhoneId}/media`, {
    method: "POST",
    headers: { Authorization: `Bearer ${c.waToken}` },
    body: form,
    signal: AbortSignal.timeout(20_000),
  });
  const uj = (await up.json().catch(() => ({}))) as { id?: string; error?: { message?: string } };
  if (!up.ok || !uj.id) return { ok: false, error: uj.error?.message ?? `upload ${up.status}` };
  const res = await fetch(`https://graph.facebook.com/${c.graphVersion}/${c.waPhoneId}/messages`, {
    method: "POST",
    headers: { Authorization: `Bearer ${c.waToken}`, "Content-Type": "application/json" },
    body: JSON.stringify({ messaging_product: "whatsapp", to: toWaId, type: "image", image: { id: uj.id, caption: caption.slice(0, 1000) } }),
    signal: AbortSignal.timeout(15_000),
  });
  if (res.ok) return { ok: true };
  return { ok: false, error: (await res.text()).slice(0, 200) };
}
