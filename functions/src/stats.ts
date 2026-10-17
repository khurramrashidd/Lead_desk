/**
 * Distributed counters for the "Scale & cost" card. A single Firestore document sustains about
 * one write per second, so every counter is spread over 10 shards and summed by the reader.
 */
import { db, FieldValue } from "./db";

const SHARDS = 10;

export async function bumpStat(field: string, by = 1): Promise<void> {
  try {
    const shard = Math.floor(Math.random() * SHARDS);
    await db.doc(`stats/s${shard}`).set({ [field]: FieldValue.increment(by) }, { merge: true });
  } catch {
    // statistics must never break a reply
  }
}
