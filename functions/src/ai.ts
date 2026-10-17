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

const GEMINI_MODEL = (process.env.GEMINI_MODEL || "gemini-3.5-flash").trim();
const GEMINI_FALLBACK_MODEL = (process.env.GEMINI_FALLBACK_MODEL || "gemini-3.5-flash-lite").trim();
const GROQ_MODEL = (process.env.GROQ_MODEL || "llama-3.3-70b-versatile").trim();
const GROQ_STT_MODEL = (process.env.GROQ_STT_MODEL || "whisper-large-v3").trim();
const OPENROUTER_MODEL = (process.env.OPENROUTER_MODEL || "openrouter/free").trim();
const CALL_TIMEOUT_MS = 45_000;

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
  if (p.kind) return p.kind;
  if (p.apiKey.startsWith("gsk_")) return "groq";
  if (p.apiKey.startsWith("sk-or-")) return "openrouter";
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
    .map((p) => ({ ...p, kind: kindOf(p) }))
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

function thinkingLevel(s: AiSettings): ThinkingLevel {
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

/** A failure we should not retry on the same key (bad key, missing model). */
function isFatal(message: string): boolean {
  return /api[ _-]?key|not.?found|404|401|403|permission|invalid.*model|unsupported|decommission/i.test(message);
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
        ...(ok ? { lastUsed: p.id } : {}),
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

async function callGemini(p: AiProvider, s: AiSettings, system: string, turns: Turn[], schema: Record<string, unknown>): Promise<string> {
  const res = await withTimeout(
    gemini(p.apiKey).models.generateContent({
      model: p.model,
      contents: toGeminiContents(turns),
      config: {
        systemInstruction: system,
        responseMimeType: "application/json",
        responseJsonSchema: schema,
        thinkingConfig: { thinkingLevel: thinkingLevel(s) },
        ...(s.maxOutputTokens ? { maxOutputTokens: s.maxOutputTokens } : {}),
      },
    }),
    CALL_TIMEOUT_MS,
    `Gemini ${p.model}`,
  );
  return res.text ?? "";
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
    body: JSON.stringify({ model: p.model, messages, temperature: 0.4, response_format: { type: "json_object" } }),
    signal: AbortSignal.timeout(CALL_TIMEOUT_MS),
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
 * Asks the pool for JSON matching [schema]. Throws only when every provider failed.
 * The last turn may carry audio.
 */
export async function generateJson<T>(system: string, turns: Turn[], schema: Record<string, unknown>): Promise<GenerateResult<T>> {
  const settings = await getAiSettings();
  if (settings.providers.length === 0) {
    throw new Error("No AI key configured. Add one in Admin → AI engine, or set GEMINI_API_KEY / GROQ_API_KEY in functions/.env.");
  }
  const errors: string[] = [];
  let transcribed: { text: string; turns: Turn[] } | null = null;

  for (const p of settings.providers) {
    const kind = kindOf(p);
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
      try {
        const raw = kind === "gemini" ? await callGemini(p, settings, system, useTurns, schema) : await callOpenAiCompatible(p, system, useTurns, schema);
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
        if (isFatal(msg) || /timed out/.test(msg)) break;
        await new Promise((r) => setTimeout(r, 700));
      }
    }
  }
  throw new Error(`All AI providers failed.\n${errors.join("\n")}`);
}

/** Admin "Test" button: one tiny call, so a wrong key is obvious before judging. */
export async function testProvider(kind: ProviderKind, apiKey: string, model: string): Promise<{ ok: boolean; ms: number; detail: string }> {
  const started = Date.now();
  const schema = { type: "object", properties: { ok: { type: "boolean" } }, required: ["ok"] };
  const p: AiProvider = { id: "test", kind, apiKey, model };
  try {
    const raw =
      kind === "gemini"
        ? await callGemini(p, { providers: [], thinking: "MINIMAL" }, "Reply with JSON.", [{ role: "user", text: 'Return {"ok": true}' }], schema)
        : await callOpenAiCompatible(p, "Reply with JSON.", [{ role: "user", text: 'Return {"ok": true}' }], schema);
    return { ok: true, ms: Date.now() - started, detail: raw.slice(0, 80) };
  } catch (e) {
    return { ok: false, ms: Date.now() - started, detail: String((e as Error)?.message ?? e).slice(0, 300) };
  }
}
