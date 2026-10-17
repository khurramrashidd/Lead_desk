/**
 * Master dashboard → "Ask AI": the admin asks a question in plain words ("how many enrolled in
 * Java this week?", "who paid but is not verified?") and the AI answers from the live data:
 * every lead (merged duplicates hidden) and every registered student, sent as compact rows.
 */
import { db, type Lead } from "./db";
import { formatIst } from "./lang";

const ts = (v: unknown): string => {
  const d = (v as { toDate?: () => Date } | undefined)?.toDate?.();
  return d ? formatIst(d) : "";
};

export async function askData(question: string): Promise<{ answer: string; rows?: string[][] }> {
  const q = question.trim().slice(0, 500);
  if (!q) return { answer: "Type a question first." };
  const [leadsSnap, studentsSnap] = await Promise.all([
    db.collection("leads").orderBy("lastMessageAt", "desc").limit(400).get(),
    db.collection("students").orderBy("allottedAt", "desc").limit(300).get(),
  ]);
  const leads = leadsSnap.docs
    .map((d) => ({ id: d.id, ...(d.data() as Lead & Record<string, any>) }))
    .filter((l) => !l.mergedInto && !l.burst && !l.selftest);
  const leadRows = leads.map((l) => {
    const e = ((l as Record<string, any>).enrollment ?? {}) as Record<string, any>;
    const f = (e.form ?? {}) as Record<string, string>;
    return [
      l.id.slice(0, 6),
      f.name || l.studentName || l.name || "",
      f.phone || l.phone || "",
      f.email || l.email || "",
      (l.sources ?? []).join("+"),
      (l.contacts ?? []).map((c) => c.relation).join("+"),
      l.status ?? "",
      String(l.score ?? ""),
      l.temperature ?? "",
      e.status ?? "",
      e.courseName ?? f.course ?? l.recommendation?.courseName ?? l.interestCourseId ?? "",
      f.batch ?? "",
      l.booking?.startAt ? ts(l.booking.startAt) : "",
      ts(l.createdAt),
      ts(l.lastMessageAt),
      l.needsHuman ? "needs-human" : "",
      (l.objections ?? []).join("+"),
      l.seed ? "sample" : "",
    ].join(" | ");
  });
  const studentRows = studentsSnap.docs.map((d) => {
    const s = d.data();
    return [s.admissionId, s.name, s.phone, s.email, s.courseName, s.mode, s.batch, s.startMonth, s.city, s.amount, ts(s.allottedAt), s.allottedBy].join(" | ");
  });

  const system = `You are the data analyst for an institute's admissions desk. Answer the admin's question using ONLY the data below.
Be exact: count rows, do not estimate. If the data cannot answer it, say what is missing. Keep the answer short (max ~120 words).
If a list or table helps, also return it in "rows" (first row = headers, at most 30 rows). Today is ${formatIst(new Date())}.

LEADS (one row per enquiry; columns: id | name | phone | email | channels | who enquired | status | score | temperature | enrolment status | course | batch | demo booked at | first contact | last activity | flags | objections | sample-data):
${leadRows.join("\n")}

REGISTERED STUDENTS (columns: admission id | name | phone | email | course | mode | batch | start | city | fee paid | allotted on | allotted by):
${studentRows.join("\n") || "(none yet)"}

Enrolment status values: form/confirm/otp = filling the form; awaiting_receipt = QR sent; receipt_received = paid, waiting for admin; verified = admitted; rejected = payment not verified.`;
  const { generateJson } = await import("./ai");
  const r = await generateJson<{ answer: string; rows?: string[][] }>(
    system,
    [{ role: "user", text: q }],
    {
      type: "object",
      properties: {
        answer: { type: "string" },
        rows: { type: "array", items: { type: "array", items: { type: "string" } } },
      },
      required: ["answer"],
    },
    { budgetMs: 60_000 },
  );
  const rows = Array.isArray(r.data.rows) ? r.data.rows.slice(0, 31).map((row) => (Array.isArray(row) ? row.map((c) => String(c ?? "")) : [])) : undefined;
  return { answer: String(r.data.answer ?? "").trim() || "No answer.", rows: rows?.length ? rows : undefined };
}
