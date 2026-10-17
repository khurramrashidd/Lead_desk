/**
 * One HTTPS endpoint for the app's admin and desk actions (no extra Flutter packages needed:
 * the app calls it with plain HTTP and its Firebase ID token).
 *
 *   POST /api/<route>   Authorization: Bearer <Firebase ID token>
 */
import type { Request, Response } from "firebase-functions/v2/https";
import { getAuth } from "firebase-admin/auth";
import { db, FieldValue, Timestamp, demoNow, logEvent, type Lead } from "./db";

type Who = { uid: string; role: string; name: string; anonymous: boolean };

async function who(req: Request): Promise<Who | null> {
  const h = req.headers.authorization ?? "";
  const m = h.match(/^Bearer (.+)$/);
  if (!m) return null;
  try {
    const tok = await getAuth().verifyIdToken(m[1]);
    const anonymous = tok.firebase?.sign_in_provider === "anonymous";
    if (anonymous) return { uid: tok.uid, role: "student", name: "", anonymous };
    const u = (await db.doc(`users/${tok.uid}`).get()).data() ?? {};
    return { uid: tok.uid, role: String(u.role ?? "pending"), name: String(u.name ?? tok.email ?? "Counsellor"), anonymous };
  } catch {
    return null;
  }
}

const isStaff = (w: Who | null) => !!w && (w.role === "admin" || w.role === "counsellor");
const isAdmin = (w: Who | null) => !!w && w.role === "admin";

function functionsBase(req: Request): string {
  const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || JSON.parse(process.env.FIREBASE_CONFIG ?? "{}").projectId;
  return `https://asia-south1-${project}.cloudfunctions.net`;
}

export async function handleApi(req: Request, res: Response): Promise<void> {
  const route = (req.path || "/").replace(/^\/+/, "").replace(/^api\/?/, "").split("/")[0];
  const body = (typeof req.body === "object" && req.body) || {};
  const w = await who(req);
  const deny = (msg = "not allowed"): void => {
    res.status(403).json({ ok: false, detail: msg });
  };

  try {
    switch (route) {
      // ------------------------------------------------------------- AI
      case "checkAi": {
        if (!isAdmin(w)) return deny();
        const { testProvider } = await import("./ai");
        res.json(await testProvider(body.kind ?? "gemini", String(body.apiKey ?? ""), String(body.model ?? "")));
        return;
      }
      case "warmUp": {
        if (!isStaff(w)) return deny();
        const { generateJson, getAiSettings, clearAiCache } = await import("./ai");
        clearAiCache();
        const s = await getAiSettings(true);
        const started = Date.now();
        const r = await generateJson<{ ok: boolean }>("Reply with JSON.", [{ role: "user", text: 'Return {"ok": true}' }], {
          type: "object",
          properties: { ok: { type: "boolean" } },
          required: ["ok"],
        });
        res.json({ ok: true, providers: s.providers.length, used: `${r.kind}:${r.model}`, ms: Date.now() - started });
        return;
      }
      case "aiProviders": {
        if (!isAdmin(w)) return deny();
        const { envProviders } = await import("./ai");
        res.json({ ok: true, env: envProviders().map((p) => ({ id: p.id, label: p.label, kind: p.kind, model: p.model })) });
        return;
      }
      // ------------------------------------------------------- channels
      case "checkWhatsApp": {
        if (!isAdmin(w)) return deny();
        const { channelConfig } = await import("./channels");
        const c = await channelConfig(true);
        if (!c.waToken || !c.waPhoneId) {
          res.json({ ok: false, detail: "Add the WhatsApp token and phone number ID first." });
          return;
        }
        const r = await fetch(`https://graph.facebook.com/${c.graphVersion}/${c.waPhoneId}?fields=display_phone_number,verified_name`, {
          headers: { Authorization: `Bearer ${c.waToken}` },
        });
        const j = (await r.json()) as Record<string, unknown>;
        res.json({ ok: r.ok, detail: r.ok ? "Connected" : JSON.stringify(j).slice(0, 300), name: j.verified_name ?? "", number: j.display_phone_number ?? "", webhook: `${functionsBase(req)}/metaWebhook`, verifyToken: c.waVerifyToken });
        return;
      }
      case "checkTelegram": {
        if (!isAdmin(w)) return deny();
        const { telegramBotInfo, setTelegramWebhook } = await import("./telegram");
        const { clearChannelCache } = await import("./channels");
        clearChannelCache();
        const info = await telegramBotInfo();
        let hook = "";
        if (body.setWebhook !== false) {
          await setTelegramWebhook(`${functionsBase(req)}/telegramWebhook`);
          hook = " · webhook set";
        }
        res.json({ ok: true, detail: `@${info.username ?? "bot"} is live${hook}`, username: info.username ?? "" });
        return;
      }
      case "checkCalendar": {
        if (!isAdmin(w)) return deny();
        const { checkCalendar, clearCalendarCache } = await import("./calendar");
        clearCalendarCache();
        res.json(await checkCalendar());
        return;
      }
      case "endpoints": {
        if (!isStaff(w)) return deny();
        const { channelConfig } = await import("./channels");
        const c = await channelConfig(true);
        const base = functionsBase(req);
        res.json({
          ok: true,
          metaWebhook: `${base}/metaWebhook`,
          telegramWebhook: `${base}/telegramWebhook`,
          intakeWebhook: `${base}/intakeWebhook`,
          callWebhook: `${base}/callWebhook`,
          ...(isAdmin(w) ? { verifyToken: c.waVerifyToken, intakeSecret: c.intakeSecret } : {}),
        });
        return;
      }
      // ----------------------------------------------------------- demo
      case "seed": {
        if (!isAdmin(w)) return deny();
        const seed = await import("./seed");
        const now = await demoNow();
        const what = String(body.what ?? "all");
        const out: Record<string, number> = {};
        if (what === "all" || what === "kb") {
          await seed.seedKb();
          out.kb = 1;
        }
        if (what === "all" || what === "slots") out.slots = await seed.seedSlots(now);
        if (what === "all" || what === "leads") out.leads = await seed.seedLeads(now);
        res.json({ ok: true, ...out });
        return;
      }
      case "clearSeed": {
        if (!isAdmin(w)) return deny();
        const { clearSeed } = await import("./seed");
        res.json({ ok: true, removed: await clearSeed() });
        return;
      }
      case "simulate": {
        if (!isStaff(w)) return deny();
        const { handleIntake } = await import("./intake");
        const r = await handleIntake(
          {
            source: String(body.channel ?? "whatsapp"),
            name: body.name,
            phone: body.phone,
            email: body.email,
            message: body.message,
            relation: body.relation,
            studentName: body.studentName,
            course: body.course,
            audioB64: body.audioB64,
            audioMime: body.audioMime,
          },
          { simulated: true },
        );
        await logEvent("simulated", r.leadId, { channel: r.channel, by: w!.name });
        res.json({ ok: true, ...r });
        return;
      }
      // ----------------------------------------------------------- desk
      case "merge": {
        if (!isStaff(w)) return deny();
        const { mergeLeads } = await import("./merge");
        const keep = String(body.keepId ?? "");
        const dup = String(body.dupId ?? "");
        if (!keep || !dup) { res.status(400).json({ ok: false, detail: "keepId and dupId required" }); return; }
        await mergeLeads(keep, dup, `confirmed by ${w!.name}`, 1);
        res.json({ ok: true });
        return;
      }
      case "dismissDuplicate": {
        if (!isStaff(w)) return deny();
        await db.doc(`leads/${String(body.leadId)}`).set({ possibleDuplicateOf: FieldValue.delete(), possibleDuplicateReason: FieldValue.delete(), notDuplicateOf: FieldValue.arrayUnion(String(body.otherId ?? "")) }, { merge: true });
        res.json({ ok: true });
        return;
      }
      case "assign": {
        if (!isStaff(w)) return deny();
        const u = (await db.doc(`users/${String(body.uid)}`).get()).data();
        if (!u) { res.status(404).json({ ok: false, detail: "no such counsellor" }); return; }
        await db.doc(`leads/${String(body.leadId)}`).set({ assignedUid: String(body.uid), assignedTo: String(u.name ?? u.email ?? "Counsellor"), assignedManually: true }, { merge: true });
        await logEvent("assigned", String(body.leadId), { to: u.name ?? "", by: w!.name, reason: "manual" });
        res.json({ ok: true });
        return;
      }
      case "book": {
        if (!isStaff(w)) return deny();
        const { bookSlot, getKb } = await import("./brain");
        const leadId = String(body.leadId);
        const lead = (await db.doc(`leads/${leadId}`).get()).data() as Lead;
        const b = await bookSlot(leadId, lead, String(body.slotId), await getKb(), lead.language);
        await db.doc(`leads/${leadId}`).set({ booking: b, status: "demo_booked" }, { merge: true });
        res.json({ ok: true, calendarUrl: b.calendarUrl });
        return;
      }
      case "callback": {
        // "Talk to a human" from the website: any visitor (anonymous session) may ask.
        if (!w) return deny("sign-in required");
        const out = await requestCallback(body, w);
        res.json({ ok: true, ...out });
        return;
      }
      default:
        res.status(404).json({ ok: false, detail: `unknown route "${route}"` });
    }
  } catch (e) {
    console.error(`api ${route} failed`, e);
    res.status(500).json({ ok: false, detail: String((e as Error)?.message ?? e).slice(0, 400) });
  }
}

/** Name, phone, email and a brief → a lead + a booked call / video-meeting slot. */
async function requestCallback(body: Record<string, unknown>, w: Who): Promise<Record<string, unknown>> {
  const { findOrCreateLead, addInbound } = await import("./leads");
  const { formatIst, t } = await import("./lang");
  const kind = String(body.kind ?? "call") === "meet" ? "meet" : "call";
  const leadId = await findOrCreateLead({
    channel: (String(body.source ?? "web") === "form" ? "form" : "web"),
    name: String(body.name ?? ""),
    phone: String(body.phone ?? ""),
    email: String(body.email ?? ""),
    relation: String(body.relation ?? "self"),
    studentName: body.studentName ? String(body.studentName) : undefined,
  });
  const ref = db.doc(`leads/${leadId}`);
  await ref.set({ viewerUids: FieldValue.arrayUnion(w.uid) }, { merge: true });
  let when = "";
  let booking: Record<string, unknown> | null = null;
  if (body.slotId) {
    const slotRef = db.doc(`slots/${String(body.slotId)}`);
    booking = await db.runTransaction(async (tx) => {
      const s = await tx.get(slotRef);
      if (!s.exists) throw new Error("That slot no longer exists.");
      const d = s.data()!;
      if (Number(d.booked ?? 0) >= Number(d.capacity ?? 1)) throw new Error("That slot just filled up. Please pick another.");
      tx.update(slotRef, { booked: FieldValue.increment(1) });
      return { slotId: s.id, kind, startAt: d.startAt as Timestamp, title: String(d.title ?? "Counsellor call"), durationMin: Number(d.durationMin ?? 20) };
    });
    when = formatIst((booking.startAt as Timestamp).toDate());
    try {
      const { createCalendarEvent } = await import("./calendar");
      const ev = await createCalendarEvent({
        summary: `${kind === "meet" ? "Video meeting" : "Call"}: ${String(body.name ?? "prospect")}`,
        description: `Phone: ${String(body.phone ?? "")}\nEmail: ${String(body.email ?? "")}\nBrief: ${String(body.brief ?? "")}\nLead id: ${leadId}`,
        start: (booking.startAt as Timestamp).toDate(),
        durationMin: Number(booking.durationMin ?? 20),
      });
      if (ev) booking = { ...booking, calendarEventId: ev.eventId, calendarEventLink: ev.htmlLink };
    } catch (e) {
      console.warn("callback calendar sync failed", e);
    }
  }
  await ref.set(
    {
      callback: { requested: true, kind, brief: String(body.brief ?? ""), at: FieldValue.serverTimestamp(), ...(booking ?? {}) },
      needsHuman: true,
      handoffReason: `${kind === "meet" ? "Video meeting" : "Call-back"} requested${when ? ` for ${when}` : ""}: ${String(body.brief ?? "").slice(0, 120)}`,
    },
    { merge: true },
  );
  await addInbound(leadId, "web", {
    text: `[Talk to a human] ${kind === "meet" ? "Video meeting" : "Phone call"}${when ? ` · ${when}` : " · call me back"} · ${String(body.brief ?? "")}`,
    meta: { intake: true, callback: true },
    silent: true,
  });
  await logEvent("callback", leadId, { kind, when, name: body.name ?? "" });
  return { leadId, when, message: when ? t("callBooked", "en", { kind: kind === "meet" ? "meet" : "call", when }) : "" };
}
