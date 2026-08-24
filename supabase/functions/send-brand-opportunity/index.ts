// KC PROJECT LEADS — send-brand-opportunity Edge Function
//
// Sends the ONE external, brand-facing email for an approved opportunity.
//
//   { "mode": "send",   "id": "<brand_opportunities.id>" }   // send the external email (gated)
//   { "mode": "preview","id": "<brand_opportunities.id>" }   // return the exact email body, send nothing
//
// Hard rules enforced here (server-side, independent of the browser):
//   1. INFORMATION FIREWALL — this function selects ONLY sanitized, brand-safe columns from
//      brand_opportunities. It never reads project_id, source_boq_id, internal_notes or any
//      contact/architect/location field, so they cannot leak into the email even if asked.
//   2. APPROVAL GATE — it refuses to send unless approval_status = 'Approved'.
//   3. FIXED SENDER — the From address comes from app_settings.brand_email_sender
//      (success@knowledgecenter.site); individual employees cannot change it.
//
// Deploy:  supabase functions deploy send-brand-opportunity --no-verify-jwt
// Secrets: supabase secrets set RESEND_API_KEY=re_xxx
//          (optional) supabase secrets set FUNCTION_SECRET=some-long-random-string
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
const FUNCTION_SECRET = Deno.env.get("FUNCTION_SECRET") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const db = createClient(SUPABASE_URL, SERVICE_KEY);

// The ONLY columns this function is ever allowed to read. Deliberately excludes every
// internal / identifying field (project_id, source_boq_id, internal_notes, contacts, …).
const SANITIZED_COLS =
  "id,opp_id,brand,category,material,paid,approval_status,brand_email," +
  "project_type,stage_band,requirement,quantity,approx_value,timing,sanitized_notes";

function esc(s: unknown): string {
  return String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
}

async function settings(): Promise<Record<string, string>> {
  const { data } = await db.from("app_settings").select("key,value");
  const m: Record<string, string> = {};
  (data ?? []).forEach((r: any) => { m[r.key] = r.value; });
  return m;
}

async function sendEmail(from: string, to: string, subject: string, html: string): Promise<void> {
  if (!RESEND_API_KEY) throw new Error("RESEND_API_KEY not set — configure the email provider secret.");
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${RESEND_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from, to: [to], subject, html }),
  });
  if (!res.ok) throw new Error(`Resend ${res.status}: ${await res.text()}`);
}

function money(v: unknown, currency: string): string {
  const n = Number(v);
  if (!v || isNaN(n)) return "";
  try { return new Intl.NumberFormat("en-IN", { style: "currency", currency, maximumFractionDigits: 0 }).format(n); }
  catch { return `${currency} ${n}`; }
}

// Build the sanitized email from brand-safe fields only.
function buildEmail(o: any, s: Record<string, string>) {
  const cat = o.category || "the requested";
  const paid = String(o.paid || "").toLowerCase() === "paid";
  const threshold = s["opportunity_threshold_label"] || "₹10L";
  const currency = s["currency"] || "INR";

  const lead = paid
    ? `We have an active project requirement in the <b>${esc(cat)}</b> category where we would like to explore introducing your brand.`
    : `We have an active project requirement in the <b>${esc(cat)}</b> category. KC currently facilitates project opportunities primarily for onboarded brands. We can offer an initial opportunity of up to <b>${esc(threshold)}</b> without onboarding; opportunities beyond this threshold require the brand to come on board with KC.`;

  // Only non-identifying rows. Quantity is optional.
  const rows: [string, string][] = [];
  if (o.project_type) rows.push(["Project type", o.project_type]);
  if (o.stage_band) rows.push(["Construction stage", o.stage_band]);
  if (o.category) rows.push(["Category", o.category]);
  if (o.material) rows.push(["Material", o.material]);
  if (o.requirement) rows.push(["Requirement", o.requirement]);
  rows.push(["Requirement quantity", o.quantity ? String(o.quantity) : "To be confirmed."]);
  const val = money(o.approx_value, currency);
  if (val) rows.push(["Approximate opportunity value", val]);
  if (o.timing) rows.push(["Requirement timing", o.timing]);
  if (o.sanitized_notes) rows.push(["Notes", o.sanitized_notes]);

  const table = `<table style="width:100%;border-collapse:collapse;margin-top:10px">${rows.map(([k, v]) =>
    `<tr><td style="padding:7px 10px;border-bottom:1px solid #eef1f5;font-size:12px;color:#5c6675;width:42%">${esc(k)}</td>` +
    `<td style="padding:7px 10px;border-bottom:1px solid #eef1f5;font-size:13px;color:#161b24">${esc(v)}</td></tr>`).join("")}</table>`;

  const html = `<div style="font-family:Jost,Arial,sans-serif;max-width:640px;margin:0 auto;color:#161b24">
    <div style="background:#15607a;color:#fff;padding:16px 20px;border-radius:12px 12px 0 0">
      <div style="font-weight:700;font-size:18px">KC — Project Opportunity</div>
      <div style="opacity:.85;font-size:13px">Reference ${esc(o.opp_id || "")}</div>
    </div>
    <div style="border:1px solid #e2e6ec;border-top:none;border-radius:0 0 12px 12px;padding:18px 20px">
      <p style="font-size:14px;line-height:1.55">Hello,</p>
      <p style="font-size:14px;line-height:1.55">${lead}</p>
      ${table}
      <p style="font-size:13px;line-height:1.55;margin-top:14px;color:#5c6675">If this opportunity is of interest, reply to this email and our team will share the next steps.</p>
      <p style="font-size:13px;line-height:1.55;margin-top:10px">Warm regards,<br>KC Project Leads Team</p>
    </div></div>`;

  const subject = `KC project opportunity — ${o.category || "material requirement"} (${o.opp_id || "OPP"})`;
  return { subject, html };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  if (FUNCTION_SECRET && req.headers.get("x-kc-secret") !== FUNCTION_SECRET) return json({ error: "unauthorized" }, 401);

  let body: any = {};
  try { body = await req.json(); } catch { /* empty body ok */ }
  const mode = body.mode ?? "send";
  const id = body.id;
  if (!id) return json({ error: "missing opportunity id" }, 400);

  try {
    // Read ONLY sanitized columns — the information firewall.
    const { data: o, error } = await db.from("brand_opportunities").select(SANITIZED_COLS).eq("id", id).maybeSingle();
    if (error) throw error;
    if (!o) return json({ error: "opportunity not found" }, 404);

    const s = await settings();
    const from = s["brand_email_sender"] || "success@knowledgecenter.site";
    const { subject, html } = buildEmail(o, s);

    if (mode === "preview") {
      return json({ preview: true, from, to: o.brand_email || null, subject, html });
    }

    // APPROVAL GATE — never send without an approval on record.
    if (String(o.approval_status || "").toLowerCase() !== "approved") {
      return json({ error: "not approved — the opportunity must be Approved before the external email can be sent." }, 409);
    }
    if (!o.brand_email) {
      return json({ error: "no brand email on the opportunity — add the brand's recipient address first." }, 400);
    }

    try {
      await sendEmail(from, o.brand_email, subject, html);
    } catch (e) {
      // Record the failure honestly; do NOT mark as sent.
      await db.from("brand_opportunities").update({ email_status: "Failed" }).eq("id", id);
      return json({ error: `send failed: ${(e as Error).message}`, email_status: "Failed" }, 502);
    }

    const today = new Date().toISOString().slice(0, 10);
    await db.from("brand_opportunities")
      .update({ email_status: "Sent", sent_date: today, status: "Sent to Brand", sender: from })
      .eq("id", id);

    return json({ sent: 1, to: o.brand_email, from, subject, email_status: "Sent" });
  } catch (e) {
    return json({ error: String((e as Error).message) }, 500);
  }
});
