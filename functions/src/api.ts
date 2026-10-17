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
      // -------------------------------------------------- answering
      case "dispatch": {
        // The app calls this right after writing a message, so Asha answers (and a
        // counsellor's reply goes out) even when the Firestore trigger is not firing.
        if (!w) return deny("sign-in required");
        const leadId = String(body.leadId ?? "");
        const msgId = String(body.msgId ?? "");
        if (!leadId || !msgId) {
          res.status(400).json({ ok: false, detail: "leadId and msgId required" });
          return;
        }
        if (!isStaff(w)) {
          const lead = (await db.doc(`leads/${leadId}`).get()).data() as Lead | undefined;
          if (!lead?.viewerUids?.includes(w.uid)) return deny();
        }
        const { dispatchSafely } = await import("./dispatch");
        res.json({ ...(await dispatchSafely(leadId, msgId, w.anonymous ? "app:web-chat" : "app:desk")) });
        return;
      }
      case "restartChat": {
        // Website "Restart": the next message starts a fresh chat (the page asks the language).
        if (!w) return deny("sign-in required");
        const leadId = String(body.leadId ?? "");
        if (!isStaff(w)) {
          const lead = (await db.doc(`leads/${leadId}`).get()).data() as Lead | undefined;
          if (!lead?.viewerUids?.includes(w.uid)) return deny();
        }
        const { restartSession } = await import("./flow");
        await restartSession(leadId);
        res.json({ ok: true });
        return;
      }
      case "verifyEnrollment": {
        // Admin checked the payment receipt: allot the course (or reject) and tell the student.
        if (!isAdmin(w)) return deny("only an admin can verify payments");
        const { verifyEnrollment } = await import("./flow");
        res.json(await verifyEnrollment(String(body.leadId ?? ""), body.approve !== false, w!.name, body.courseId ? String(body.courseId) : undefined, body.note ? String(body.note) : undefined));
        return;
      }
      case "testReminders": {
        // Desk → lead → "Test reminders now": the 24 h and 1 h reminders go out immediately.
        if (!isStaff(w)) return deny();
        const { remindNow } = await import("./heartbeat");
        const r = await remindNow(String(body.leadId ?? ""));
        res.json({ ok: r.sent.length > 0, detail: r.sent.length ? `Sent: ${r.sent.join(", ")}` : "This lead has no demo class or call booked yet.", ...r });
        return;
      }
      case "diagnose": {
        if (!isAdmin(w)) return deny();
        const { runDiagnosis } = await import("./diagnose");
        const checks = await runDiagnosis();
        res.json({ ok: true, checks });
        return;
      }
      case "subscribeWhatsApp": {
        if (!isAdmin(w)) return deny();
        const { subscribeWhatsApp } = await import("./diagnose");
        const { clearChannelCache } = await import("./channels");
        clearChannelCache();
        res.json(await subscribeWhatsApp(body.wabaId ? String(body.wabaId) : undefined));
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
      case "checkEmail": {
        if (!isAdmin(w)) return deny();
        const { checkEmail } = await import("./email");
        res.json(await checkEmail());
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
            studentPhone: body.studentPhone,
            course: body.course,
            audioB64: body.audioB64,
            audioMime: body.audioMime,
          },
          { simulated: true },
        );
        await logEvent("simulated", r.leadId, { channel: r.channel, by: w!.name });
        const { dispatchSafely } = await import("./dispatch");
        await dispatchSafely(r.leadId, r.msgId, "simulator");
        res.json({ ok: true, ...r });
        return;
      }
      case "burst": {
        // Load test: N anonymous website visitors write at the same moment. Most of them ask
        // the same few questions, which is what real traffic looks like.
        if (!isAdmin(w)) return deny();
        const n = Math.max(3, Math.min(200, Number(body.count ?? 30)));
        const questions: string[] = Array.isArray(body.questions) && body.questions.length
          ? body.questions.map(String)
          : [
              "Full Stack Java ki fees kitni hai?",
              "I'm a commerce graduate with a two-year gap — can I really become a developer?",
              "मला डेटा सायन्स शिकायचं आहे, कोर्स किती महिन्यांचा आहे?",
            ];
        const started = Date.now();
        const made: { leadId: string; msgId: string }[] = [];
        await Promise.all(
          Array.from({ length: n }, async (_, i) => {
            const ref = db.collection("leads").doc();
            await ref.set({
              sources: ["web"],
              firstSource: "web",
              lastChannel: "web",
              status: "new",
              score: 0,
              userMessages: 0,
              seed: true,
              burst: true,
              createdBy: "server",
              createdAt: FieldValue.serverTimestamp(),
              lastMessageAt: FieldValue.serverTimestamp(),
              lastInboundAt: FieldValue.serverTimestamp(),
            });
            const m = await ref.collection("messages").add({ role: "user", channel: "web", text: questions[i % questions.length], createdAt: FieldValue.serverTimestamp(), meta: { burst: true } });
            made.push({ leadId: ref.id, msgId: m.id });
          }),
        );
        // Answer them here too (the trigger does the same; the per-lead lock keeps one reply each).
        const { dispatchSafely } = await import("./dispatch");
        await Promise.all(made.map((x) => dispatchSafely(x.leadId, x.msgId, "loadtest")));
        await logEvent("burst", null, { count: n, distinct: questions.length, by: w!.name });
        res.json({ ok: true, created: n, distinct: questions.length, ms: Date.now() - started });
        return;
      }
      case "selftestCleanup": {
        if (!isAdmin(w)) return deny();
        const { cleanupSelfTest } = await import("./selftest");
        const removed = await cleanupSelfTest();
        const runs = await db.collection("selftests").get();
        const batch = db.batch();
        runs.docs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
        res.json({ ok: true, removed });
        return;
      }
      case "resetStats": {
        if (!isAdmin(w)) return deny();
        const shards = await db.collection("stats").get();
        const batch = db.batch();
        shards.docs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
        res.json({ ok: true });
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
