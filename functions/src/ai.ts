/**
 * The AI provider pool: Gemini first, then free fallbacks (Groq, OpenRouter).
 *
 * Providers come from two places and are tried in order until one answers:
 *   1. Admin → AI engine (Firestore config/ai), so keys can be added without redeploying.
 *   2. functions/.env: GEMINI_API_KEY (comma-separated for several keys), GROQ_API_KEY,
 *      OPENROUTER_API_KEY.
 *
 * Gemini hears voice notes directly. For Groq/OpenRouter the voice note is first transcribed
 * with Groq Whisper (free), so a voice note still works if every Gemini key is rate-limited.
 */
import { GoogleGenAI, ThinkingLevel, type Content, type Part } from "@google/genai";
import { db, FieldValue } from "./db";
import { bumpStat } from "./stats";

export type ProviderKind = "gemini" | "groq" | "openrouter";

export interface AiProvider {
  id: string;
  label?: string;
  kind?: ProviderKind;
  apiKey: string;
  model: string;
  enabled?: boolean;
  order?: number;
}

export interface AiSettings {
  providers: AiProvider[];
  thinking?: "MINIMAL" | "LOW" | "MEDIUM" | "HIGH";
  maxOutputTokens?: number;
}

/** One turn of the conversation in a provider-neutral shape. */
export interface Turn {
  role: "user" | "model";
  text: string;
  audio?: { b64: string; mime: string };
}

/**
 * Model names change: Google retired the 2.0 models and never shipped "gemini-3.5-flash";
 * Groq shut down llama-3.3-70b-versatile and llama-3.1-8b-instant for free accounts on
 * 16 Aug 2026. Old names saved in Admin or in functions/.env are mapped to a live model here,
 * so a stale setting can never silence Asha again.
 */
export const MODEL_FIXES: Record<string, string> = {
  "gemini-3.5-flash": "gemini-3.6-flash",
  "gemini-3.7-flash": "gemini-3.6-flash",
  "gemini-3-flash": "gemini-3.6-flash",
  "gemini-2.0-flash": "gemini-3.6-flash",
  "gemini-2.0-flash-lite": "gemini-3.5-flash-lite",
  "gemini-1.5-flash": "gemini-3.6-flash",
  "gemini-3-pro-preview": "gemini-3.6-flash",
  "gemini-3.1-flash-lite-preview": "gemini-3.1-flash-lite",
  "llama-3.3-70b-versatile": "openai/gpt-oss-120b",
  "llama-3.1-8b-instant": "openai/gpt-oss-20b",
  "llama3-70b-8192": "openai/gpt-oss-120b",
  "llama3-8b-8192": "openai/gpt-oss-20b",
  "meta-llama/llama-4-scout-17b-16e-instruct": "openai/gpt-oss-120b",
  "meta-llama/llama-4-maverick-17b-128e-instruct": "openai/gpt-oss-120b",
  "qwen/qwen3-32b": "openai/gpt-oss-120b",
  "qwen/qwen3.6-27b": "qwen/qwen3.8-27b",
  "moonshotai/kimi-k2-instruct": "openai/gpt-oss-120b",
  "moonshotai/kimi-k2-instruct-0905": "openai/gpt-oss-120b",
  "gemma2-9b-it": "openai/gpt-oss-20b",
};

export function fixModel(model: string): string {
  const m = (model ?? "").trim();
  return MODEL_FIXES[m] ?? m;
}

/** Gemini models tried, in order, with the same key when the chosen one is missing or out of quota. */
export const GEMINI_BACKUP_MODELS = ["gemini-3.6-flash", "gemini-3.5-flash-lite", "gemini-3.8-flash", "gemini-3.1-flash-lite"];

const GEMINI_MODEL = fixModel(process.env.GEMINI_MODEL || "gemini-3.6-flash");
const GEMINI_FALLBACK_MODEL = fixModel(process.env.GEMINI_FALLBACK_MODEL || "gemini-3.5-flash-lite");
const GROQ_MODEL = fixModel(process.env.GROQ_MODEL || "openai/gpt-oss-120b");
const GROQ_STT_MODEL = (process.env.GROQ_STT_MODEL || "whisper-large-v3").trim();
const OPENROUTER_MODEL = fixModel(process.env.OPENROUTER_MODEL || "openrouter/free");
/** One provider call never waits longer than this. */
const CALL_TIMEOUT_MS = 28_000;
/** A whole reply (every provider and model together) gives up after this, so the chat never hangs. */
export const DEFAULT_BUDGET_MS = 75_000;

let cache: { settings: AiSettings; at: number } | null = null;
const geminiClients = new Map<string, GoogleGenAI>();

function gemini(apiKey: string): GoogleGenAI {
  let c = geminiClients.get(apiKey);
  if (!c) {
    c = new GoogleGenAI({ apiKey });
    geminiClients.set(apiKey, c);
  }
  return c;
}

function splitKeys(v?: string): string[] {
  return (v ?? "")
    .split(/[,\s]+/)
    .map((k) => k.trim())
    .filter((k) => k && !k.startsWith("paste-"));
}

function kindOf(p: AiProvider): ProviderKind {
  // The key's own prefix wins: a Groq key saved under "Gemini" by mistake still works.
  const key = (p.apiKey ?? "").trim();
  if (key.startsWith("gsk_")) return "groq";
  if (key.startsWith("sk-or-")) return "openrouter";
  if (key.startsWith("AIza")) return "gemini";
  if (p.kind) return p.kind;
  return "gemini";
}

/** Keys from functions/.env, always kept as the last resort. */
export function envProviders(): AiProvider[] {
  const out: AiProvider[] = [];
  let order = 900;
  splitKeys(process.env.GEMINI_API_KEY).forEach((key, i) => {
    out.push({ id: `env-gemini-${i}`, label: `Gemini key ${i + 1} (.env)`, kind: "gemini", apiKey: key, model: GEMINI_MODEL, order: order++ });
  });
  splitKeys(process.env.GROQ_API_KEY).forEach((key, i) => {
    out.push({ id: `env-groq-${i}`, label: `Groq key ${i + 1} (.env)`, kind: "groq", apiKey: key, model: GROQ_MODEL, order: order++ });
  });
  if (GEMINI_FALLBACK_MODEL && GEMINI_FALLBACK_MODEL !== GEMINI_MODEL) {
    splitKeys(process.env.GEMINI_API_KEY).forEach((key, i) => {
      out.push({ id: `env-gemini-lite-${i}`, label: `Gemini key ${i + 1} · lite (.env)`, kind: "gemini", apiKey: key, model: GEMINI_FALLBACK_MODEL, order: order++ });
    });
  }
  splitKeys(process.env.OPENROUTER_API_KEY).forEach((key, i) => {
    out.push({ id: `env-openrouter-${i}`, label: `OpenRouter key ${i + 1} (.env)`, kind: "openrouter", apiKey: key, model: OPENROUTER_MODEL, order: order++ });
  });
  return out;
}

export async function getAiSettings(force = false): Promise<AiSettings> {
  if (!force && cache && Date.now() - cache.at < 30_000) return cache.settings;
  let stored: Partial<AiSettings> = {};
  try {
    const snap = await db.doc("config/ai").get();
    stored = (snap.data() as Partial<AiSettings> | undefined) ?? {};
  } catch (e) {
    console.warn("could not read config/ai", e);
  }
  const fromAdmin = (stored.providers ?? [])
    .filter((p) => p && p.apiKey && p.model && p.enabled !== false)
    .map((p) => ({ ...p, apiKey: String(p.apiKey).trim(), model: fixModel(p.model), kind: kindOf(p) }))
    .sort((a, b) => (a.order ?? 0) - (b.order ?? 0));
  const settings: AiSettings = {
    providers: [...fromAdmin, ...envProviders()],
    thinking: stored.thinking ?? "MINIMAL",
    maxOutputTokens: stored.maxOutputTokens,
  };
  cache = { settings, at: Date.now() };
  return settings;
}

export function clearAiCache(): void {
  cache = null;
}

/** Some models refuse MINIMAL thinking (gemini-3.8-flash, Pro, 2.5): they get LOW instead. */
export function supportsMinimalThinking(model: string): boolean {
  return /flash-lite|gemini-3\.6-flash|gemini-3-flash-preview|gemini-3\.5-flash(?!-lite)/.test(model) && !/pro|gemini-2\.|gemini-3\.8|gemini-4/.test(model);
}

function thinkingLevel(s: AiSettings, model = ""): ThinkingLevel {
  if ((s.thinking ?? "MINIMAL") === "MINIMAL" && model && !supportsMinimalThinking(model)) return ThinkingLevel.LOW;
  switch (s.thinking) {
    case "LOW":
      return ThinkingLevel.LOW;
    case "MEDIUM":
      return ThinkingLevel.MEDIUM;
    case "HIGH":
      return ThinkingLevel.HIGH;
    default:
      return ThinkingLevel.MINIMAL;
  }
}

/** A failure we should not retry on the same key and model (bad key, missing model). */
function isFatal(message: string): boolean {
  return /api[ _-]?key|not.?found|404|401|403|permission|invalid.*model|unsupported|not supported|decommission|deprecat|no longer|does not exist|model_not_found|413|too large/i.test(message);
}

/** The key itself is wrong: no other model will work with it either. */
function isKeyProblem(message: string): boolean {
  return /api[ _-]?key (not valid|invalid|expired)|API_KEY_INVALID|invalid api key|incorrect api key|unauthori[sz]ed|\b401\b/i.test(message);
}

/** Worth trying the next model with the same key (missing model, quota, overload). */
function tryOtherModel(message: string): boolean {
  return /not.?found|404|403|permission|billing|free tier|not available|429|quota|exhausted|rate|overloaded|503|unavailable|unsupported|not supported|deprecat|no longer|timed out/i.test(message);
}

function withTimeout<T>(p: Promise<T>, ms: number, what: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error(`${what} timed out after ${ms} ms`)), ms);
    p.then(
      (v) => {
        clearTimeout(t);
        resolve(v);
      },
      (e) => {
        clearTimeout(t);
        reject(e);
      },
    );
  });
}

/** Accepts plain JSON, JSON inside ``` fences, or JSON with chatter around it. */
export function parseJsonLoose<T>(text: string): T {
  const t = (text ?? "").trim();
  try {
    return JSON.parse(t) as T;
  } catch {
    // fall through
  }
  const fenced = t.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fenced) {
    try {
      return JSON.parse(fenced[1]) as T;
    } catch {
      // fall through
    }
  }
  const start = t.indexOf("{");
  const end = t.lastIndexOf("}");
  if (start >= 0 && end > start) return JSON.parse(t.slice(start, end + 1)) as T;
  throw new Error(`model did not return JSON: ${t.slice(0, 120)}`);
}

// One Firestore document takes about one sustained write per second, so under load each
// instance reports a provider's health at most once a minute (or when it flips ok <-> failing).
const lastHealth = new Map<string, { ok: boolean; at: number }>();

async function noteHealth(p: AiProvider, ok: boolean, detail: string, ms: number): Promise<void> {
  const prev = lastHealth.get(p.id);
  if (prev && prev.ok === ok && Date.now() - prev.at < 60_000) return;
  lastHealth.set(p.id, { ok, at: Date.now() });
  try {
    await db.doc("config/aiHealth").set(
      {
        [p.id]: { label: p.label ?? p.id, kind: kindOf(p), model: p.model, ok, detail: detail.slice(0, 300), ms, at: FieldValue.serverTimestamp() },
        ...(ok ? { lastUsed: p.id, lastFailure: FieldValue.delete() } : {}),
      },
      { merge: true },
    );
  } catch {
    // health reporting must never break a reply
  }
}

// ------------------------------------------------------------------ Gemini
function toGeminiContents(turns: Turn[]): Content[] {
  const contents: Content[] = [];
  for (const t of turns) {
    const parts: Part[] = [];
    if (t.audio) parts.push({ inlineData: { mimeType: t.audio.mime || "audio/webm", data: t.audio.b64 } });
    if (t.text) parts.push({ text: t.text });
    if (!parts.length) continue;
    const prev = contents[contents.length - 1];
    if (prev && prev.role === t.role) prev.parts = [...(prev.parts ?? []), ...parts];
    else contents.push({ role: t.role, parts });
  }
  if (contents.length && contents[0].role === "model") contents.unshift({ role: "user", parts: [{ text: "(prospect opened the chat)" }] });
  return contents;
}

async function callGemini(
  p: AiProvider,
  s: AiSettings,
  system: string,
  turns: Turn[],
  schema: Record<string, unknown>,
  timeoutMs = CALL_TIMEOUT_MS,
): Promise<string> {
  const run = (withThinking: boolean) =>
    withTimeout(
      gemini(p.apiKey).models.generateContent({
        model: p.model,
        contents: toGeminiContents(turns),
        config: {
          systemInstruction: system,
          responseMimeType: "application/json",
          responseJsonSchema: schema,
          ...(withThinking ? { thinkingConfig: { thinkingLevel: thinkingLevel(s, p.model) } } : {}),
          ...(s.maxOutputTokens ? { maxOutputTokens: s.maxOutputTokens } : {}),
        },
      }),
      timeoutMs,
      `Gemini ${p.model}`,
    );
  try {
    return (await run(true)).text ?? "";
  } catch (e) {
    // A model that does not accept this thinking setting: ask again without it.
    if (/thinking/i.test(String((e as Error)?.message ?? e))) return (await run(false)).text ?? "";
    throw e;
  }
}

// ------------------------------------------------- OpenAI-compatible (Groq, OpenRouter)
const BASE: Record<Exclude<ProviderKind, "gemini">, string> = {
  groq: "https://api.groq.com/openai/v1",
  openrouter: "https://openrouter.ai/api/v1",
};

async function callOpenAiCompatible(
  p: AiProvider,
  system: string,
  turns: Turn[],
  schema: Record<string, unknown>,
  timeoutMs = CALL_TIMEOUT_MS,
): Promise<string> {
  const kind = kindOf(p) as Exclude<ProviderKind, "gemini">;
  const messages = [
    {
      role: "system",
      content:
        `${system}\n\nOUTPUT FORMAT: reply with ONE JSON object only (no markdown, no prose) that matches this JSON Schema:\n` +
        JSON.stringify(schema),
    },
    ...mergeTurns(turns).map((t) => ({ role: t.role === "model" ? "assistant" : "user", content: t.text || "(empty)" })),
  ];
  const res = await fetch(`${BASE[kind]}/chat/completions`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${p.apiKey}`,
      "Content-Type": "application/json",
      ...(kind === "openrouter" ? { "HTTP-Referer": "https://lead-desk.web.app", "X-Title": "AI Lead Desk" } : {}),
    },
    body: JSON.stringify({
      model: p.model,
      messages,
      temperature: 0.4,
      response_format: { type: "json_object" },
      // gpt-oss models think before answering; keep it short so the chat stays fast.
      ...(/gpt-oss/.test(p.model) ? { reasoning_effort: "low" } : {}),
    }),
    signal: AbortSignal.timeout(timeoutMs),
  }).catch((e: unknown) => {
    const m = String((e as Error)?.message ?? e);
    throw new Error(/abort|timeout/i.test(m) ? `${kind} ${p.model} timed out after ${timeoutMs} ms` : m);
  });
  const body = await res.text();
  if (!res.ok) throw new Error(`${kind} ${res.status}: ${body.slice(0, 300)}`);
  const json = JSON.parse(body) as { choices?: { message?: { content?: string } }[] };
  return json.choices?.[0]?.message?.content ?? "";
}

function mergeTurns(turns: Turn[]): Turn[] {
  const out: Turn[] = [];
  for (const t of turns) {
    const prev = out[out.length - 1];
    if (prev && prev.role === t.role) prev.text = `${prev.text}\n${t.text}`;
    else out.push({ role: t.role, text: t.text });
  }
  if (out.length && out[0].role === "model") out.unshift({ role: "user", text: "(prospect opened the chat)" });
  return out;
}

function extFor(mime: string): string {
  if (mime.includes("ogg") || mime.includes("opus")) return "ogg";
  if (mime.includes("mp4") || mime.includes("m4a") || mime.includes("aac")) return "m4a";
  if (mime.includes("mpeg") || mime.includes("mp3")) return "mp3";
  if (mime.includes("wav")) return "wav";
  return "webm";
}

/** Free speech-to-text with Groq Whisper. Returns "" when no Groq key is configured. */
export async function transcribeWithGroq(audio: { b64: string; mime: string }, providers?: AiProvider[]): Promise<string> {
  const list = providers ?? (await getAiSettings()).providers;
  const keys = Array.from(new Set(list.filter((p) => kindOf(p) === "groq").map((p) => p.apiKey)));
  for (const key of keys) {
    try {
      const form = new FormData();
      const bytes = Buffer.from(audio.b64, "base64");
      form.append("file", new Blob([bytes], { type: audio.mime || "audio/webm" }), `voice.${extFor(audio.mime || "")}`);
      form.append("model", GROQ_STT_MODEL);
      form.append("response_format", "json");
      const res = await fetch(`${BASE.groq}/audio/transcriptions`, {
        method: "POST",
        headers: { Authorization: `Bearer ${key}` },
        body: form,
        signal: AbortSignal.timeout(30_000),
      });
      if (!res.ok) {
        console.warn("groq whisper failed", res.status, (await res.text()).slice(0, 200));
        continue;
      }
      const j = (await res.json()) as { text?: string };
      if (j.text?.trim()) return j.text.trim();
    } catch (e) {
      console.warn("groq whisper error", e);
    }
  }
  return "";
}

export interface GenerateResult<T> {
  data: T;
  providerId: string;
  kind: ProviderKind;
  model: string;
  ms: number;
  /** Set when a non-Gemini provider answered a voice note via Whisper. */
  transcript?: string;
}

/**
 * Asks the pool for JSON matching [schema]. Throws only when every provider failed or the
 * time budget ran out (the caller then answers from the knowledge base and retries later).
 * The last turn may carry audio.
 *
 * Order: every provider as configured. A Gemini key whose model is missing, out of quota or
 * overloaded is tried again with the next live Gemini model (GEMINI_BACKUP_MODELS) before
 * moving on; a key that is itself invalid is skipped for every model.
 */
export async function generateJson<T>(
  system: string,
  turns: Turn[],
  schema: Record<string, unknown>,
  opts: { budgetMs?: number } = {},
): Promise<GenerateResult<T>> {
  const settings = await getAiSettings();
  if (settings.providers.length === 0) {
    const msg = "No AI key configured. Add one in Admin → AI engine, or set GEMINI_API_KEY / GROQ_API_KEY in functions/.env.";
    void noteFailure([msg]);
    throw new Error(msg);
  }
  const deadline = Date.now() + (opts.budgetMs ?? DEFAULT_BUDGET_MS);
  const errors: string[] = [];
  const deadKeys = new Set<string>();
  const tried = new Set<string>();
  // Keys whose own model failed for a model reason (missing, quota, overload): try their backups.
  const tryOtherModelFor = new Set<string>();
  let transcribed: { text: string; turns: Turn[] } | null = null;

  // Expand each Gemini key into its model chain.
  const plan: AiProvider[] = [];
  for (const p of settings.providers) {
    plan.push(p);
    if (kindOf(p) === "gemini") {
      for (const m of GEMINI_BACKUP_MODELS) {
        if (m !== p.model) plan.push({ ...p, id: `${p.id}~${m}`, label: `${p.label ?? p.id} → ${m}`, model: m, order: (p.order ?? 0) + 0.5 });
      }
    }
  }

  for (const p of plan) {
    const kind = kindOf(p);
    const pairKey = `${kind}|${p.apiKey}|${p.model}`;
    if (deadKeys.has(p.apiKey) || tried.has(pairKey)) continue;
    // Backup models of a key are only worth it when the key's own model failed for a model reason.
    if (p.id.includes("~") && !tryOtherModelFor.has(p.apiKey)) continue;
    tried.add(pairKey);
    const left = deadline - Date.now();
    if (left < 4_000) {
      errors.push("time budget used up");
      break;
    }
    let useTurns = turns;
    let transcript: string | undefined;
    if (kind !== "gemini" && turns.some((t) => t.audio)) {
      // Text-only provider: hear the voice note with Whisper first (once).
      if (!transcribed) {
        // Every unanswered voice note is transcribed once (Groq Whisper, free).
        const texts = await Promise.all(turns.map((t) => (t.audio ? transcribeWithGroq(t.audio, settings.providers) : Promise.resolve(""))));
        transcribed = {
          text: [...texts].reverse().find((x) => x) ?? "",
          turns: turns.map((t, i) =>
            t.audio ? { role: t.role, text: texts[i] ? `(voice note) ${texts[i]}` : "(voice note — could not be transcribed, ask them to type)" } : t,
          ),
        };
      }
      useTurns = transcribed.turns;
      transcript = transcribed.text || undefined;
    }
    for (let attempt = 0; attempt < 2; attempt++) {
      const started = Date.now();
      const timeout = Math.max(3_000, Math.min(CALL_TIMEOUT_MS, deadline - Date.now() - 1_000));
      try {
        const raw =
          kind === "gemini"
            ? await callGemini(p, settings, system, useTurns, schema, timeout)
            : await callOpenAiCompatible(p, system, useTurns, schema, timeout);
        const data = parseJsonLoose<T>(raw);
        const ms = Date.now() - started;
        void noteHealth(p, true, "ok", ms);
        void bumpStat("aiCalls");
        return { data, providerId: p.id, kind, model: p.model, ms, transcript };
      } catch (e) {
        const ms = Date.now() - started;
        const msg = String((e as Error)?.message ?? e);
        errors.push(`${p.label ?? p.id} (${p.model}): ${msg.slice(0, 160)}`);
        console.warn(`AI provider ${p.id} [${p.model}] attempt ${attempt + 1} failed in ${ms}ms: ${msg.slice(0, 300)}`);
        void noteHealth(p, false, msg, ms);
        if (isKeyProblem(msg)) {
          deadKeys.add(p.apiKey);
          break;
        }
        if (kind === "gemini" && tryOtherModel(msg)) tryOtherModelFor.add(p.apiKey);
        if (isFatal(msg) || /timed out|429|quota|exhausted/i.test(msg) || deadline - Date.now() < 6_000) break;
        await new Promise((r) => setTimeout(r, 600));
      }
    }
  }
  void noteFailure(errors);
  throw new Error(`All AI providers failed.\n${errors.join("\n")}`);
}

/** The latest complete failure, shown in Admin → AI engine and on the desk. */
async function noteFailure(errors: string[]): Promise<void> {
  try {
    await db.doc("config/aiHealth").set(
      { lastFailure: { at: FieldValue.serverTimestamp(), errors: errors.slice(-8).map((e) => e.slice(0, 220)) } },
      { merge: true },
    );
  } catch {
    // never break a reply
  }
}

/** Admin "Test" button: one tiny call, so a wrong key is obvious before judging. */
export async function testProvider(kind: ProviderKind, apiKey: string, model: string): Promise<{ ok: boolean; ms: number; detail: string }> {
  const started = Date.now();
  const schema = { type: "object", properties: { ok: { type: "boolean" } }, required: ["ok"] };
  const p: AiProvider = { id: "test", kind, apiKey: apiKey.trim(), model: fixModel(model) };
  try {
    const raw =
      kind === "gemini"
        ? await callGemini(p, { providers: [], thinking: "MINIMAL" }, "Reply with JSON.", [{ role: "user", text: 'Return {"ok": true}' }], schema)
        : await callOpenAiCompatible(p, "Reply with JSON.", [{ role: "user", text: 'Return {"ok": true}' }], schema);
    return { ok: true, ms: Date.now() - started, detail: `${p.model}: ${raw.slice(0, 60)}` };
  } catch (e) {
    return { ok: false, ms: Date.now() - started, detail: String((e as Error)?.message ?? e).slice(0, 300) };
  }
}
