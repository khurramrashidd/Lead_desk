/**
 * Single-flight answer cache on Firestore.
 *
 * When many identical requests arrive together, exactly one caller (the "leader", who wins a
 * create() on the cache document) runs [produce]; the others poll the document and reuse the
 * leader's answer. Answers stay valid for [ttlMs]. Works across every server instance, because
 * the coordination lives in the database, not in memory.
 */
import { Timestamp } from "firebase-admin/firestore";

/** The small part of the Firestore API we use, so tests can pass an in-memory fake. */
export interface MiniDb {
  doc(path: string): MiniRef;
  runTransaction<T>(fn: (tx: MiniTx) => Promise<T>): Promise<T>;
}
export interface MiniRef {
  create(data: Record<string, unknown>): Promise<unknown>;
  get(): Promise<{ data(): Record<string, unknown> | undefined }>;
  set(data: Record<string, unknown>): Promise<unknown>;
}
export interface MiniTx {
  get(ref: MiniRef): Promise<{ data(): Record<string, unknown> | undefined }>;
  set(ref: MiniRef, data: Record<string, unknown>): unknown;
}

export type FlightState = "hit" | "wait" | "miss";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const ageMs = (d?: Record<string, unknown>) => (d?.at ? Date.now() - (d.at as Timestamp).toMillis() : Infinity);

export async function singleFlight<T>(
  key: string,
  produce: () => Promise<T>,
  storable: (v: T) => boolean = () => true,
  opts: { ttlMs?: number; pollMs?: number; maxPolls?: number; db?: MiniDb } = {},
): Promise<{ value: T; state: FlightState }> {
  const ttl = opts.ttlMs ?? 3 * 3_600_000;
  const pollMs = opts.pollMs ?? 500;
  const maxPolls = opts.maxPolls ?? 40;
  const db: MiniDb = opts.db ?? ((await import("./db")).db as unknown as MiniDb);
  const ref = db.doc(`aiCache/${key}`);
  const fresh = (d?: Record<string, unknown>) => !!d && d.status === "ready" && ageMs(d) < ttl;

  let leader = false;
  try {
    await ref.create({ status: "pending", at: Timestamp.now() });
    leader = true;
  } catch {
    leader = false;
  }
  if (!leader) {
    for (let i = 0; i < maxPolls && !leader; i++) {
      const d = (await ref.get()).data();
      if (fresh(d)) return { value: d!.value as T, state: i === 0 ? "hit" : "wait" };
      // The leader's answer was personal (e.g. a booking): everyone answers for themselves.
      if (d?.status === "nocache" && ageMs(d) < 60_000) return { value: await produce(), state: "miss" };
      const stale = !d || d.status === "failed" || d.status === "ready" || d.status === "nocache" || ageMs(d) > 30_000;
      if (stale) {
        leader = await db.runTransaction(async (tx) => {
          const cur = (await tx.get(ref)).data();
          if (fresh(cur) || (cur?.status === "pending" && ageMs(cur) <= 30_000)) return false;
          tx.set(ref, { status: "pending", at: Timestamp.now() });
          return true;
        });
        if (leader) break;
      }
      await sleep(pollMs);
    }
    if (!leader) return { value: await produce(), state: "miss" }; // waited long enough: answer directly
  }
  try {
    const value = await produce();
    if (storable(value)) await ref.set({ status: "ready", at: Timestamp.now(), value: JSON.parse(JSON.stringify(value)) });
    else await ref.set({ status: "nocache", at: Timestamp.now() });
    return { value, state: "miss" };
  } catch (e) {
    await ref.set({ status: "failed", at: Timestamp.now() }).catch(() => undefined);
    throw e;
  }
}
