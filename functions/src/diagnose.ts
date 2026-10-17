/**
 * Admin → Channels → Diagnose: one button that says exactly why Asha is quiet or why a channel
 * is not arriving, with the fix for each problem.
 *
 * Checks: Firestore database region vs the functions' region, which functions are deployed
 * (and whether the message trigger is live), the AI pool, Telegram's own view of our webhook,
 * the WhatsApp number + whether the WhatsApp Business Account is subscribed to the app, and the
 * last webhook calls we actually received.
 */
import { GoogleAuth } from "google-auth-library";
import { db } from "./db";

export const FUNCTIONS_REGION = "asia-south1";

export interface Check {
  name: string;
  /** true = fine, false = broken, null = could not tell. */
  ok: boolean | null;
  detail: string;
  fix?: string;
}

let auth: GoogleAuth | null = null;

function projectId(): string {
  return process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || JSON.parse(process.env.FIREBASE_CONFIG ?? "{}").projectId || "";
}

async function gcp(url: string): Promise<{ ok: boolean; status: number; json: Record<string, any> }> {
  if (!auth) auth = new GoogleAuth({ scopes: ["https://www.googleapis.com/auth/cloud-platform"] });
  const client = await auth.getClient();
  const t = await client.getAccessToken();
  const res = await fetch(url, { headers: { Authorization: `Bearer ${t.token}` }, signal: AbortSignal.timeout(15_000) });
  const json = (await res.json().catch(() => ({}))) as Record<string, any>;
  return { ok: res.ok, status: res.status, json };
}

const ago = (ts: any): string => {
  const ms = ts?.toMillis?.();
  if (!ms) return "";
  const min = Math.round((Date.now() - ms) / 60_000);
  return min < 1 ? "just now" : min < 120 ? `${min} min ago` : `${Math.round(min / 60)} h ago`;
};

export function functionsBase(): string {
  return `https://${FUNCTIONS_REGION}-${projectId()}.cloudfunctions.net`;
}

/** Finds the WhatsApp Business Account id the token can manage (saved one first). */
export async function findWabaId(token: string, graph: string, saved?: string): Promise<string> {
  if (saved) return saved;
  try {
    const r = await fetch(`https://graph.facebook.com/${graph}/debug_token?input_token=${encodeURIComponent(token)}&access_token=${encodeURIComponent(token)}`, {
      signal: AbortSignal.timeout(15_000),
    });
    const j = (await r.json()) as { data?: { granular_scopes?: { scope: string; target_ids?: string[] }[] } };
    const scopes = j.data?.granular_scopes ?? [];
    const ids = scopes.find((s) => s.scope === "whatsapp_business_management")?.target_ids ?? scopes.find((s) => s.scope === "whatsapp_business_messaging")?.target_ids ?? [];
    return ids[0] ?? "";
  } catch {
    return "";
  }
}

export async function runDiagnosis(): Promise<Check[]> {
  const checks: Check[] = [];
  const project = projectId();

  // ---- 1. Firestore region ----------------------------------------------------------
  try {
    const r = await gcp(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)`);
    if (r.ok) {
      const loc = String(r.json.locationId ?? "?");
      const trig = (process.env.TRIGGER_REGION || FUNCTIONS_REGION).trim();
      const same = loc === trig || (loc === "nam5" && trig.startsWith("us-")) || (loc === "eur3" && trig.startsWith("europe-"));
      checks.push({
        name: "Firestore database region",
        ok: same,
        detail: `Database (default) is in ${loc}; the Firestore triggers run in ${trig}.`,
        fix: same
          ? undefined
          : `Firestore triggers must run in the database's region. Asha now also answers from the webhooks, the app and a 2-minute sweeper, so chats work anyway. To make the trigger work too, add the line TRIGGER_REGION=${loc === "nam5" ? "us-central1" : loc === "eur3" ? "europe-west1" : loc} to functions\\.env and run deploy again.`,
      });
    } else {
      checks.push({ name: "Firestore database region", ok: null, detail: `Could not read (HTTP ${r.status}: ${JSON.stringify(r.json.error?.message ?? r.json).slice(0, 160)})` });
    }
  } catch (e) {
    checks.push({ name: "Firestore database region", ok: null, detail: `Could not read: ${String((e as Error).message).slice(0, 160)}` });
  }

  // ---- 2. Deployed functions --------------------------------------------------------
  try {
    const r = await gcp(`https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/-/functions?pageSize=100`);
    if (r.ok) {
      const fns = (r.json.functions ?? []) as { name: string; state?: string; stateMessages?: { message?: string }[] }[];
      const byName = new Map(fns.map((f) => [f.name.split("/").pop()!.toLowerCase(), f]));
      const want = ["onMessageCreated", "metaWebhook", "telegramWebhook", "api", "aiRetry", "heartbeat", "sessionCloser", "onLeadCreated", "onStaffWritten"];
      const missing = want.filter((n) => !byName.has(n.toLowerCase()));
      const broken = want.filter((n) => byName.get(n.toLowerCase()) && byName.get(n.toLowerCase())!.state !== "ACTIVE");
      const trig = byName.get("onmessagecreated");
      checks.push({
        name: "Message trigger (onMessageCreated)",
        ok: !!trig && trig.state === "ACTIVE",
        detail: trig ? `${trig.state}${trig.stateMessages?.length ? ` · ${trig.stateMessages.map((m) => m.message).join("; ").slice(0, 200)}` : ""} · ${trig.name.split("/")[3]}` : "NOT DEPLOYED: this is why Asha never answered.",
        fix: trig && trig.state === "ACTIVE" ? undefined : "Run deploy again (first deploys often fail with 'Eventarc Service Agent' permission errors; wait 5 minutes and redeploy). Asha now answers without it anyway.",
      });
      checks.push({
        name: "Cloud Functions deployed",
        ok: !missing.length && !broken.length,
        detail: `${fns.length} found.${missing.length ? ` Missing: ${missing.join(", ")}.` : ""}${broken.length ? ` Not active: ${broken.join(", ")}.` : ""}`,
        fix: missing.length || broken.length ? "Run deploy and read the red error lines at the end of the output." : undefined,
      });
    } else {
      checks.push({ name: "Cloud Functions deployed", ok: null, detail: `Could not list (HTTP ${r.status}). Check in Firebase Console → Functions that onMessageCreated is listed.` });
    }
  } catch (e) {
    checks.push({ name: "Cloud Functions deployed", ok: null, detail: `Could not list: ${String((e as Error).message).slice(0, 160)}` });
  }

  // ---- 3. AI pool -------------------------------------------------------------------
  try {
    const { generateJson, getAiSettings, clearAiCache } = await import("./ai");
    clearAiCache();
    const s = await getAiSettings(true);
    const r = await generateJson<{ ok: boolean }>("Reply with JSON.", [{ role: "user", text: 'Return {"ok": true}' }], { type: "object", properties: { ok: { type: "boolean" } }, required: ["ok"] }, { budgetMs: 40_000 });
    checks.push({ name: "AI engine", ok: true, detail: `${s.providers.length} provider(s); answered with ${r.kind}:${r.model} in ${r.ms} ms.` });
  } catch (e) {
    checks.push({ name: "AI engine", ok: false, detail: String((e as Error).message).slice(0, 400), fix: "Admin → AI engine: add or fix a key (each key's Test button shows the exact error)." });
  }

  const status = (await db.doc("config/webhookStatus").get()).data() ?? {};
  const { channelConfig } = await import("./channels");
  const c = await channelConfig(true);

  // ---- 4. Telegram ------------------------------------------------------------------
  if (!c.telegramBotToken) {
    checks.push({ name: "Telegram", ok: null, detail: "No bot token set." });
  } else {
    try {
      const r = await fetch(`https://api.telegram.org/bot${c.telegramBotToken}/getWebhookInfo`, { signal: AbortSignal.timeout(15_000) });
      const j = (await r.json()) as { ok: boolean; result?: { url?: string; pending_update_count?: number; last_error_message?: string; last_error_date?: number } };
      const info = j.result ?? {};
      const want = `${functionsBase()}/telegramWebhook`;
      const urlOk = info.url === want;
      const recentErr = info.last_error_date && Date.now() / 1000 - info.last_error_date < 3600 ? info.last_error_message : "";
      checks.push({
        name: "Telegram webhook",
        ok: urlOk && !recentErr,
        detail: `Telegram sends to: ${info.url || "(nothing)"} · waiting updates: ${info.pending_update_count ?? 0}${info.last_error_message ? ` · last error: ${info.last_error_message}` : ""}`,
        fix: !urlOk ? "Admin → Channels → Telegram → Connect (sets the webhook to this project)." : recentErr ? "Redeploy, then press Telegram → Connect again." : undefined,
      });
    } catch (e) {
      checks.push({ name: "Telegram webhook", ok: null, detail: String((e as Error).message).slice(0, 200) });
    }
  }
  const tg = status.telegram as Record<string, any> | undefined;
  if (tg) checks.push({ name: "Telegram: last call received", ok: tg.ok !== false, detail: `${ago(tg.at)} · ${tg.detail ?? ""}` });

  // ---- 5. WhatsApp ------------------------------------------------------------------
  if (!c.waToken || !c.waPhoneId) {
    checks.push({ name: "WhatsApp", ok: false, detail: "Token or phone number ID missing.", fix: "Admin → Channels → WhatsApp: paste the access token and the Phone number ID (not the WhatsApp Business Account ID)." });
  } else {
    try {
      const r = await fetch(`https://graph.facebook.com/${c.graphVersion}/${c.waPhoneId}?fields=display_phone_number,verified_name,code_verification_status,quality_rating,platform_type`, {
        headers: { Authorization: `Bearer ${c.waToken}` },
        signal: AbortSignal.timeout(15_000),
      });
      const j = (await r.json()) as Record<string, any>;
      checks.push({
        name: "WhatsApp number + token",
        ok: r.ok,
        detail: r.ok ? `${j.verified_name ?? ""} ${j.display_phone_number ?? ""} (${j.platform_type ?? "?"})` : JSON.stringify(j.error?.message ?? j).slice(0, 240),
        fix: r.ok ? undefined : "Token expired or wrong Phone number ID. Temporary tokens last 24 h: create a permanent System User token (docs/WHATSAPP_SETUP.md).",
      });
      const saved = String(((await db.doc("config/channels").get()).get("waBusinessId") as string | undefined) ?? "");
      const waba = await findWabaId(c.waToken, c.graphVersion, saved);
      if (!waba) {
        checks.push({
          name: "WhatsApp Business Account subscribed to the app",
          ok: null,
          detail: "Could not find the WhatsApp Business Account ID from the token.",
          fix: "Admin → Channels → WhatsApp: paste the WhatsApp Business Account ID and press 'Subscribe webhook'.",
        });
      } else {
        const s = await fetch(`https://graph.facebook.com/${c.graphVersion}/${waba}/subscribed_apps`, { headers: { Authorization: `Bearer ${c.waToken}` }, signal: AbortSignal.timeout(15_000) });
        const sj = (await s.json()) as { data?: { whatsapp_business_api_data?: { name?: string; id?: string }; override_callback_uri?: string }[]; error?: { message?: string } };
        const apps = sj.data ?? [];
        checks.push({
          name: "WhatsApp Business Account subscribed to the app",
          ok: s.ok ? apps.length > 0 : null,
          detail: s.ok
            ? apps.length
              ? `WABA ${waba} → ${apps.map((a) => `${a.whatsapp_business_api_data?.name ?? a.whatsapp_business_api_data?.id ?? "app"}${a.override_callback_uri ? ` (callback ${a.override_callback_uri})` : ""}`).join(", ")}`
              : `WABA ${waba} has NO app subscribed: Meta will never send messages to the webhook.`
            : `WABA ${waba}: ${sj.error?.message ?? s.status}`,
          fix: s.ok && apps.length ? undefined : "Press 'Subscribe webhook' in Admin → Channels → WhatsApp.",
        });
      }
    } catch (e) {
      checks.push({ name: "WhatsApp", ok: null, detail: String((e as Error).message).slice(0, 200) });
    }
  }
  // ---- 6. Where each setting comes from (Admin wins over functions/.env) ----
  try {
    const saved = (await db.doc("config/channels").get()).data() ?? {};
    const rows: string[] = [];
    let stale = 0;
    for (const [k, env, label] of [
      ["waToken", "WA_TOKEN", "WhatsApp token"],
      ["waPhoneId", "WA_PHONE_ID", "WhatsApp phone ID"],
      ["waVerifyToken", "WA_VERIFY_TOKEN", "WhatsApp verify token"],
      ["telegramBotToken", "TELEGRAM_BOT_TOKEN", "Telegram bot token"],
    ] as const) {
      const a = String(saved[k] ?? "").trim();
      const e = (process.env[env] ?? "").trim();
      const from = a ? "Admin" : e ? ".env" : "default/empty";
      const differs = !!a && !!e && a !== e;
      if (differs) stale++;
      rows.push(`${label}: ${from}${differs ? " (functions\\.env has a different, unused value)" : ""}`);
    }
    checks.push({
      name: "Where settings come from",
      ok: stale === 0,
      detail: rows.join(" · "),
      fix: stale ? "Admin → Channels always wins. To avoid confusion, empty those lines in functions\\.env (keep the file) and run deploy." : undefined,
    });
  } catch {
    // informational only
  }
  try {
    const { envProviders } = await import("./ai");
    const health = (await db.doc("config/aiHealth").get()).data() ?? {};
    const env = envProviders();
    if (env.length) {
      const bad = env.filter((p) => (health[p.id] as { ok?: boolean } | undefined)?.ok === false);
      checks.push({
        name: "AI keys in functions\\.env (used after the Admin keys)",
        ok: bad.length ? false : null,
        detail: env.map((p) => `${p.label}: ${(health[p.id] as { ok?: boolean } | undefined)?.ok === false ? "FAILING" : (health[p.id] as { ok?: boolean } | undefined)?.ok ? "ok" : "not used yet"}`).join(" · "),
        fix: bad.length ? "Remove the failing keys from functions\\.env (or replace them) and run deploy. Keys in Admin → AI engine are tried first." : undefined,
      });
    }
  } catch {
    // informational only
  }

  const meta = status.meta as Record<string, any> | undefined;
  checks.push({
    name: "WhatsApp: last call received from Meta",
    ok: meta ? meta.ok !== false : false,
    detail: meta ? `${ago(meta.at)} · ${meta.kind === "verify" ? "verification" : "message POST"} · ${meta.detail ?? ""}` : "Meta has never called metaWebhook since this version was deployed.",
    fix: meta
      ? undefined
      : `Meta App Dashboard → WhatsApp → Configuration → Webhook: Callback URL ${functionsBase()}/metaWebhook, Verify token "${c.waVerifyToken}" → Verify and save → Webhook fields → 'messages' → Subscribe. Then press 'Subscribe webhook' here. Test number: your phone must be in the "To" list.`,
  });
  if (status.lastDispatchError) {
    const e = status.lastDispatchError as Record<string, any>;
    checks.push({ name: "Last answering error", ok: null, detail: `${ago(e.at)} via ${e.via}: ${e.note}` });
  }
  return checks;
}

/**
 * Subscribes the WhatsApp Business Account to the app and points its webhook straight at this
 * project's metaWebhook (a WABA-level override), so no dashboard click can be missed.
 */
export async function subscribeWhatsApp(wabaIdIn?: string): Promise<{ ok: boolean; detail: string; wabaId: string }> {
  const { channelConfig } = await import("./channels");
  const c = await channelConfig(true);
  if (!c.waToken) return { ok: false, detail: "Add the WhatsApp access token first.", wabaId: "" };
  const saved = String(((await db.doc("config/channels").get()).get("waBusinessId") as string | undefined) ?? "");
  const waba = (wabaIdIn ?? "").trim() || (await findWabaId(c.waToken, c.graphVersion, saved));
  if (!waba) return { ok: false, detail: "WhatsApp Business Account ID not found: paste it (Meta → WhatsApp → API Setup, under the phone number).", wabaId: "" };
  await db.doc("config/channels").set({ waBusinessId: waba }, { merge: true });

  const post = async (body: Record<string, string>) => {
    const r = await fetch(`https://graph.facebook.com/${c.graphVersion}/${waba}/subscribed_apps`, {
      method: "POST",
      headers: { Authorization: `Bearer ${c.waToken}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(20_000),
    });
    const j = (await r.json().catch(() => ({}))) as { success?: boolean; error?: { message?: string } };
    return { ok: r.ok && j.success !== false, err: j.error?.message ?? (r.ok ? "" : `HTTP ${r.status}`) };
  };
  const callback = `${functionsBase()}/metaWebhook`;
  const withOverride = await post({ override_callback_uri: callback, verify_token: c.waVerifyToken });
  if (withOverride.ok) return { ok: true, detail: `Subscribed. WABA ${waba} now sends messages to ${callback}.`, wabaId: waba };
  const plain = await post({});
  if (plain.ok) {
    return {
      ok: true,
      detail: `Subscribed WABA ${waba} to the app (callback override refused: ${withOverride.err}). Make sure the app's webhook URL is ${callback} with 'messages' subscribed.`,
      wabaId: waba,
    };
  }
  return { ok: false, detail: `Meta refused: ${plain.err || withOverride.err}`, wabaId: waba };
}
