/** Staff access: who becomes admin automatically, and logging new counsellor requests. */
import { db, FieldValue, logEvent } from "./db";

function adminEmails(): string[] {
  return (process.env.ADMIN_EMAILS ?? "")
    .split(/[,;\s]+/)
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
}

export interface StaffRecord {
  email?: string;
  name?: string;
  role?: string;
}

/**
 * Runs on every write to users/{uid} while the person is still "pending".
 *
 * - Email listed in ADMIN_EMAILS -> admin.
 * - No admin exists yet (first staff sign-in) -> admin, so the project is never locked out.
 * - Everyone else stays pending until an admin approves them on the Admin page.
 *
 * It listens to writes rather than creates only, because a brand-new project's Firestore
 * trigger can take a few minutes to go live: anyone who signed in during that window would
 * stay stuck on "pending" for ever. Signing in again now fixes it by itself.
 */
export async function onNewStaff(uid: string, data: StaffRecord): Promise<void> {
  if (data.role && data.role !== "pending") return; // already decided; also stops a write loop

  const email = (data.email ?? "").toLowerCase().trim();
  const listed = !!email && adminEmails().includes(email);

  let makeAdmin = listed;
  if (!makeAdmin) {
    const anyAdmin = await db.collection("users").where("role", "==", "admin").limit(1).get();
    makeAdmin = anyAdmin.empty;
  }

  if (makeAdmin) {
    await db.doc(`users/${uid}`).set(
      { role: "admin", roleChangedBy: listed ? "ADMIN_EMAILS" : "first staff account", roleChangedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
    await logEvent("staff_admin", null, { uid, email, name: data.name ?? "", reason: listed ? "listed in ADMIN_EMAILS" : "first staff account" });
    console.log(`Promoted ${email || uid} to admin (${listed ? "ADMIN_EMAILS" : "first staff account"})`);
    return;
  }

  await logEvent("staff_request", null, { uid, email, name: data.name ?? "" });
}
