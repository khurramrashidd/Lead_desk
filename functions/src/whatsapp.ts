/** WhatsApp Cloud API: receive text and voice notes, send replies. */
import { db, FieldValue, type Lead } from "./db";
import { normalizePhone } from "./identity";
import { latinName, resolveIdentity } from "./merge";

const GRAPH = `https://graph.facebook.com/${process.env.WA_GRAPH_VERSION || "v23.0"}`;

export function whatsappConfigured(): boolean {
  return !!(process.env.WA_TOKEN && process.env.WA_PHONE_ID);
}

export async function sendWhatsAppText(toWaId: string, body: string): Promise<boolean> {
  if (!whatsappConfigured()) return false;
  const res = await fetch(`${GRAPH}/${process.env.WA_PHONE_ID}/messages`, {
    method: "POST",
    headers: { Authorization: `Bearer ${process.env.WA_TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify({ messaging_product: "whatsapp", to: toWaId, type: "text", text: { body: body.slice(0, 4000) } }),
  });
  if (!res.ok) console.error("WhatsApp send failed", res.status, await res.text());
  return res.ok;
}

async function downloadMedia(mediaId: string): Promise<{ b64: string; mime: string } | null> {
  const auth = { Authorization: `Bearer ${process.env.WA_TOKEN}` };
  const meta = await fetch(`${GRAPH}/${mediaId}`, { headers: auth });
  if (!meta.ok) return null;
  const info = (await meta.json()) as { url: string; mime_type: string };
  const file = await fetch(info.url, { headers: auth });
  if (!file.ok) return null;
  const buf = Buffer.from(await file.arrayBuffer());
  if (buf.length > 700_000) return null; // keep Firestore documents small
  return { b64: buf.toString("base64"), mime: (info.mime_type || "audio/ogg").split(";")[0].trim() };
}

interface WaMessage {
  from: string;
  id: string;
  type: string;
  text?: { body: string };
  audio?: { id: string };
}

/** Finds the lead for this WhatsApp number (any phone format) or creates one. */
async function leadForWhatsApp(waId: string, profileName?: string): Promise<string> {
  const byWa = await db.collection("leads").where("waId", "==", waId).limit(5).get();
  const live = byWa.docs.find((d) => !(d.data() as Lead).mergedInto);
  if (live) return live.id;

  const ref = db.collection("leads").doc();
  await ref.set({
    name: profileName ?? "",
    nameLatin: latinName(profileName) ?? "",
    phone: normalizePhone(waId) ?? waId,
    waId,
    sources: ["whatsapp"],
    firstSource: "whatsapp",
    lastChannel: "whatsapp",
    status: "new",
    score: 0,
    createdAt: FieldValue.serverTimestamp(),
    lastMessageAt: FieldValue.serverTimestamp(),
  });
  // Rahul Patil from the web form + राहुल पाटील on WhatsApp -> one person
  await resolveIdentity(ref.id);
  const after = (await ref.get()).data() as Lead;
  return after.mergedInto ?? ref.id;
}

/** Handles one webhook POST body from Meta. */
export async function handleWebhook(body: any): Promise<void> {
  for (const entry of body?.entry ?? []) {
    for (const change of entry?.changes ?? []) {
      const value = change?.value;
      const contacts: { wa_id: string; profile?: { name?: string } }[] = value?.contacts ?? [];
      for (const m of (value?.messages ?? []) as WaMessage[]) {
        const profileName = contacts.find((c) => c.wa_id === m.from)?.profile?.name;
        const leadId = await leadForWhatsApp(m.from, profileName);
        const leadRef = db.doc(`leads/${leadId}`);

        const msg: Record<string, unknown> = {
          role: "user",
          channel: "whatsapp",
          createdAt: FieldValue.serverTimestamp(),
          meta: { waMessageId: m.id },
        };
        if (m.type === "text" && m.text) msg.text = m.text.body;
        else if (m.type === "audio" && m.audio) {
          const media = await downloadMedia(m.audio.id);
          if (media) {
            msg.audioB64 = media.b64;
            msg.audioMime = media.mime;
          } else msg.text = "(voice note could not be downloaded)";
        } else msg.text = `(${m.type} message)`;

        await leadRef.set(
          {
            waId: m.from,
            lastChannel: "whatsapp",
            sources: FieldValue.arrayUnion("whatsapp"),
            lastInboundAt: FieldValue.serverTimestamp(),
            lastMessageAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        // idempotent: Meta can retry the same webhook
        await leadRef.collection("messages").doc(`wa_${m.id}`).create(msg).catch(() => undefined);
      }
    }
  }
}
