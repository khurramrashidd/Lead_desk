/**
 * The AI provider pool.
 *
 * The institute can add several Gemini API keys (and a model for each) from the
 * Admin console. We try them in order: if a key is rate-limited, out of free
 * quota, or names a model that does not exist, the next one answers. The key in
 * functions/.env is always kept as the last resort, so the demo never dies
 * because one key ran dry.
 */
import { GoogleGenAI, ThinkingLevel, type Content } from "@google/genai";
import { db, FieldValue } from "./db";

export interface AiProvider {
  id: string;
  label?: string;
  apiKey: string;
  model: string;
  enabled?: boolean;
  order?: number;
}

export interface AiSettings {
  providers: AiProvider[];
  /** How much the model is allowed to "think" before answering. MINIMAL is the fastest. */
  thinking?: "MINIMAL" | "LOW" | "MEDIUM" | "HIGH";
  maxOutputTokens?: number;
}

const DEFAULT_MODEL = process.env.GEMINI_MODEL || "gemini-3.5-flash-lite";
const FALLBACK_MODEL = process.env.GEMINI_FALLBACK_MODEL || "gemini-3.5-flash-lite";

let cache: { settings: AiSettings; at: number } | null = null;
const clients = new Map<string, GoogleGenAI>();

function clientFor(apiKey: string): GoogleGenAI {
  let c = clients.get(apiKey);
  if (!c) {
    c = new GoogleGenAI({ apiKey });
    clients.set(apiKey, c);
  }
  return c;
}

/** Keys from .env, used when the Admin list is empty or everything in it fails. */
function envProviders(): AiProvider[] {
  const key = process.env.GEMINI_API_KEY;
  if (!key) return [];
  const out: AiProvider[] = [{ id: "env", label: "functions/.env", apiKey: key, model: DEFAULT_MODEL, enabled: true, order: 900 }];
  if (FALLBACK_MODEL !== DEFAULT_MODEL) {
    out.push({ id: "env-fallback", label: "functions/.env (backup model)", apiKey: key, model: FALLBACK_MODEL, enabled: true, order: 901 });
  }
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
    .sort((a, b) => (a.order ?? 0) - (b.order ?? 0));

  const settings: AiSettings = {
    providers: [...fromAdmin, ...envProviders()],
    thinking: stored.thinking ?? "MINIMAL",
    maxOutputTokens: stored.maxOutputTokens,
  };
  cache = { settings, at: Date.now() };
  return settings;
}

export interface GenerateResult<T> {
  data: T;
  providerId: string;
  model: string;
  ms: number;
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
  return /api[ _-]?key|not.?found|404|permission|invalid.*model|unsupported/i.test(message);
}

async function noteHealth(providerId: string, model: string, ok: boolean, detail: string, ms: number): Promise<void> {
  try {
    await db.doc("config/aiHealth").set(
      {
        [providerId]: {
          model,
          ok,
          detail: detail.slice(0, 300),
          ms,
          at: FieldValue.serverTimestamp(),
        },
        lastUsed: ok ? providerId : FieldValue.delete(),
      },
      { merge: true },
    );
  } catch {
    // health reporting must never break a reply
  }
}

/**
 * Asks Gemini for JSON matching [schema], walking the provider list until one answers.
 * Throws only when every provider failed.
 */
export async function generateJson<T>(
  system: string,
  contents: Content[],
  schema: Record<string, unknown>,
): Promise<GenerateResult<T>> {
  const settings = await getAiSettings();
  if (settings.providers.length === 0) {
    throw new Error("No Gemini API key configured. Add one in Admin → AI engine, or set GEMINI_API_KEY in functions/.env.");
  }

  const errors: string[] = [];
  for (const p of settings.providers) {
    for (let attempt = 0; attempt < 2; attempt++) {
      const started = Date.now();
      try {
        const res = await clientFor(p.apiKey).models.generateContent({
          model: p.model,
          contents,
          config: {
            systemInstruction: system,
            responseMimeType: "application/json",
            responseJsonSchema: schema,
            thinkingConfig: { thinkingLevel: thinkingLevel(settings) },
            ...(settings.maxOutputTokens ? { maxOutputTokens: settings.maxOutputTokens } : {}),
          },
        });
        const ms = Date.now() - started;
        const data = JSON.parse(res.text ?? "{}") as T;
        void noteHealth(p.id, p.model, true, "ok", ms);
        return { data, providerId: p.id, model: p.model, ms };
      } catch (e) {
        const ms = Date.now() - started;
        const msg = String((e as Error)?.message ?? e);
        errors.push(`${p.label ?? p.id} (${p.model}): ${msg.slice(0, 160)}`);
        console.warn(`Gemini provider ${p.id} [${p.model}] attempt ${attempt + 1} failed in ${ms}ms: ${msg.slice(0, 300)}`);
        void noteHealth(p.id, p.model, false, msg, ms);
        if (isFatal(msg)) break; // move to the next key straight away
        await new Promise((r) => setTimeout(r, 900));
      }
    }
  }
  throw new Error(`All AI providers failed.\n${errors.join("\n")}`);
}

/** Admin "Test" button: one tiny call, so a wrong key is obvious before judging. */
export async function testProvider(apiKey: string, model: string): Promise<{ ok: boolean; ms: number; detail: string }> {
  const started = Date.now();
  try {
    const res = await clientFor(apiKey).models.generateContent({
      model,
      contents: [{ role: "user", parts: [{ text: 'Reply with the JSON {"ok":true} and nothing else.' }] }],
      config: {
        responseMimeType: "application/json",
        thinkingConfig: { thinkingLevel: ThinkingLevel.MINIMAL },
      },
    });
    return { ok: true, ms: Date.now() - started, detail: (res.text ?? "").slice(0, 80) };
  } catch (e) {
    return { ok: false, ms: Date.now() - started, detail: String((e as Error)?.message ?? e).slice(0, 300) };
  }
}

export function clearAiCache(): void {
  cache = null;
}
