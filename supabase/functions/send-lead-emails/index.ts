// KC PROJECT LEADS — send-lead-emails Edge Function
//
// Sends email to the KC sales owner of a lead. Two modes:
//   { "mode": "assigned", "lead": { table, id, name, assignee, project, status, followup, url } }
//        -> emails just that lead's assignee (used automatically when a lead is assigned)
//   { "mode": "digest" }
//        -> groups every assigned lead by owner and emails each owner their full list
//           (the "Email all leads" button)
//
// Deploy:  supabase functions deploy send-lead-emails --no-verify-jwt
// Secrets: supabase secrets set RESEND_API_KEY=re_xxx EMAIL_FROM="KC Leads <leads@yourdomain.com>"
//          (optional)  supabase secrets set FUNCTION_SECRET=some-long-random-string
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-kc-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const EMAIL_FROM = Deno.env.get("EMAIL_FROM") ?? "KC Leads <onboarding@resend.dev>";
const FUNCTION_SECRET = Deno.env.get("FUNCTION_SECRET") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const db = createClient(SUPABASE_URL, SERVICE_KEY);

function esc(s: unknown): string {
  return String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
}

// name -> email map from team_members
async function teamEmails(): Promise<Record<string, { email: string; role?: string }>> {
  const { data, error } = await db.from("team_members").select("name,email,role,active");
  if (error) throw error;
  const map: Record<string, { email: string; role?: string }> = {};
  (data ?? []).forEach((m: any) => {
    if (m.name && m.email && m.active !== false) map[String(m.name).trim().toLowerCase()] = { email: m.email, role: m.role };
  });
  return map;
}

async function sendEmail(to: string, subject: string, html: string): Promise<void> {
  if (!RESEND_API_KEY) throw new Error("RESEND_API_KEY not set — configure the email provider secret.");
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${RESEND_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: EMAIL_FROM, to: [to], subject, html }),
  });
  if (!res.ok) throw new Error(`Resend ${res.status}: ${await res.text()}`);
}

function shell(title: string, inner: string): string {
  return `<div style="font-family:Jost,Arial,sans-serif;max-width:640px;margin:0 auto;color:#161b24">
    <div style="background:#15607a;color:#fff;padding:16px 20px;border-radius:12px 12px 0 0">
      <div style="font-weight:700;font-size:18px">KC Project Leads</div>
      <div style="opacity:.85;font-size:13px">${esc(title)}</div>
    </div>
    <div style="border:1px solid #e2e6ec;border-top:none;border-radius:0 0 12px 12px;padding:18px 20px">${inner}</div>
  </div>`;
}
function leadRow(l: any): string {
  const cells = [l.name, l.project || "Unlinked", l.status || "", l.followup || ""];
  return `<tr>${cells.map((c) => `<td style="padding:8px 10px;border-bottom:1px solid #eef1f5;font-size:13px">${esc(c)}</td>`).join("")}</tr>`;
}
function leadTable(rows: any[]): string {
  return `<table style="width:100%;border-collapse:collapse;margin-top:8px">
    <thead><tr>${["Lead", "Project", "Status", "Follow-up"].map((h) =>
      `<th style="text-align:left;padding:8px 10px;border-bottom:2px solid #e2e6ec;font-size:11px;text-transform:uppercase;color:#5c6675">${h}</th>`).join("")}</tr></thead>
    <tbody>${rows.map(leadRow).join("")}</tbody></table>`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  if (FUNCTION_SECRET && req.headers.get("x-kc-secret") !== FUNCTION_SECRET) return json({ error: "unauthorized" }, 401);

  let body: any = {};
  try { body = await req.json(); } catch { /* empty body ok */ }
  const mode = body.mode ?? "digest";

  try {
    const emails = await teamEmails();

    // ---- single assignment notification ----
    if (mode === "assigned") {
      const l = body.lead ?? {};
      const who = String(l.assignee ?? "").trim();
      if (!who) return json({ sent: 0, skipped: 1, reason: "no assignee on lead" });
      const rec = emails[who.toLowerCase()];
      if (!rec) return json({ sent: 0, skipped: 1, reason: `no email on file for "${who}" (add it under Team Members)` });
      const inner = `<p style="font-size:14px">Hi ${esc(who)}, a lead has been assigned to you:</p>${leadTable([l])}${
        l.url ? `<p style="margin-top:14px"><a href="${esc(l.url)}" style="color:#15607a">Open the dashboard →</a></p>` : ""
      }`;
      await sendEmail(rec.email, `New lead assigned: ${l.name ?? "lead"}`, shell("A lead was assigned to you", inner));
      return json({ sent: 1, to: rec.email });
    }

    // ---- digest: every assigned lead, grouped by owner ----
    const [fl, dsc, bq] = await Promise.all([
      db.from("field_leads").select("id,site_name,project_id,visit_status,followup_date,assignee"),
      db.from("discussions").select("id,visitor_name,firm_name,project_id,visit_status,followup_date,assignee"),
      db.from("boq_materials").select("id,boq_id,lead_group,project_id,brand_engagement,req_date,assignee"),
    ]);
    for (const r of [fl, dsc, bq]) if (r.error) throw r.error;

    const byOwner: Record<string, any[]> = {};
    const add = (owner: any, lead: any) => {
      const o = String(owner ?? "").trim();
      if (!o) return;
      (byOwner[o] ??= []).push(lead);
    };
    (fl.data ?? []).forEach((r: any) => add(r.assignee, { name: r.site_name, project: r.project_id, status: r.visit_status, followup: r.followup_date }));
    (dsc.data ?? []).forEach((r: any) => add(r.assignee, { name: [r.visitor_name, r.firm_name].filter(Boolean).join(" · "), project: r.project_id, status: r.visit_status, followup: r.followup_date }));
    (bq.data ?? []).forEach((r: any) => add(r.assignee, { name: r.lead_group || r.boq_id, project: r.project_id, status: r.brand_engagement, followup: r.req_date }));

    const results: any[] = [];
    let sent = 0, skipped = 0;
    for (const [owner, leads] of Object.entries(byOwner)) {
      const rec = emails[owner.toLowerCase()];
      if (!rec) { skipped++; results.push({ owner, leads: leads.length, skipped: "no email" }); continue; }
      const inner = `<p style="font-size:14px">Hi ${esc(owner)}, here are the ${leads.length} lead(s) currently assigned to you:</p>${leadTable(leads)}`;
      try {
        await sendEmail(rec.email, `Your KC leads (${leads.length})`, shell("Your assigned leads", inner));
        sent++; results.push({ owner, to: rec.email, leads: leads.length });
      } catch (e) { skipped++; results.push({ owner, error: String((e as Error).message) }); }
    }
    return json({ mode: "digest", owners: Object.keys(byOwner).length, sent, skipped, results });
  } catch (e) {
    return json({ error: String((e as Error).message) }, 500);
  }
});
