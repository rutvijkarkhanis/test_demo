# KC Project Leads — Operations Portal

An interactive, Supabase-backed portal for the **KC PROJECT LEADS** operation.
The dashboard (projects with stage-intelligence, a live follow-up calendar, BOQ
materials, field leads, discussions, unlinked leads) now reads and writes its
data live from a Supabase Postgres database, with full create / edit / delete on
every table from the browser.

`index.html` is a single self-contained page — no build step. It loads the
Supabase client from a CDN and connects with your project URL + anon key.

> **Note:** this page must be opened from a normal web context (a static host or
> `file://` / local server). It cannot run inside a Claude Artifact, because the
> Artifact sandbox blocks network calls to Supabase.

## 1. Create the database

In your Supabase project, open **SQL Editor** and run, in order:

1. [`supabase/migrations/0001_init.sql`](supabase/migrations/0001_init.sql) — creates the six tables, indexes, an `updated_at` trigger, and Row Level Security policies.
2. [`supabase/seed.sql`](supabase/seed.sql) — loads the workbook snapshot (3 projects, 20 stages, 112 field leads, 64 discussions, 249 BOQ items, 3 duplicate reviews).

(Or with the Supabase CLI: `supabase db push` then `psql "$DATABASE_URL" -f supabase/seed.sql`.)

## 2. Run the portal

Open `index.html` and either:

- **Use the connect screen** — paste your **Project URL** and **anon public key**
  (Supabase → Project Settings → API). They're stored only in your browser
  (localStorage). Use the database icon in the top bar to change them later.
- **Or auto-connect** — fill in `config.js` with the same two values and commit
  it; the page connects for everyone automatically.

Serve it any way you like — GitHub Pages, Vercel, Netlify, or locally with
`python3 -m http.server`.

## Deploy to GitHub Pages (automated)

A workflow at `.github/workflows/deploy-pages.yml` publishes `index.html` +
`config.js` to GitHub Pages on every push to the working branch.

One-time setup (repo owner):

1. **Settings → Pages → Build and deployment → Source = "GitHub Actions".**
2. Push to the branch (or run the workflow manually from the **Actions** tab).
   The run prints the live URL — typically `https://<user>.github.io/<repo>/`.
3. **Auto-connect (optional):** fill `url` and `anonKey` in `config.js` and commit,
   so the live site connects for everyone without the setup screen. The anon key
   is public and this is an open portal, so committing it exposes nothing new. If
   you leave `config.js` blank, visitors just paste the URL + key once on the
   connect screen (stored in their browser).

Notes:
- GitHub Pages must be available for the repo (public repos, or private repos on
  a paid plan).
- Supabase itself has **no static-site hosting** product — it hosts your database
  and API (already "up"), not the web page. Host the page on Pages/Vercel/Netlify
  and point it at Supabase. (You *can* serve the file from a public Supabase
  Storage bucket, but Pages is simpler and gives a nicer URL.)

## Tables

| Table | Rows | What it holds |
| --- | --- | --- |
| `projects` | 3 | The formal projects + the stage-intelligence layer (actual / projected / material-inferred stage, confidence). |
| `project_stages` | 20 | Per-project construction stage timeline. |
| `field_leads` | 112 | Field site visits. |
| `discussions` | 64 | Architect / designer / visitor discussions. |
| `boq_materials` | 249 | BOQ line items (17 lead groups) with brand-engagement status. |
| `duplicates` | 3 | Potential duplicate sites to review. |

## Editing

- **Inline:** each project card, field lead, discussion and BOQ material has an
  edit (✎) button; each section has an **＋ Add** button.
- **Manage Data tab:** a generic grid over *all six tables* — pick a table,
  search, then add / edit / delete any row. This is where you edit stages and
  duplicates.
- Changes save straight to Supabase and the dashboard (KPIs, calendar, stage
  rails) recomputes. If Realtime is enabled for the tables, edits by other users
  appear automatically; otherwise they show on the next reload.

## Email notifications (sales team)

The portal can email the sales owner of a lead — automatically when a lead is
assigned, and on demand for everyone at once. Email is sent by a **Supabase Edge
Function** (`supabase/functions/send-lead-emails`), never from the browser, so the
provider key stays server-side.

**Setup (one time):**

1. **Team emails** — run `supabase/migrations/0004_team_members.sql`, then fill in
   each person's email in the dashboard: **Manage Data → Team Members**. The
   `name` must match the value used in **Assigned To** (that's how a lead is routed).
2. **Email provider** — the function uses [Resend](https://resend.com). Create a
   key and a verified sender domain, then:
   ```
   supabase secrets set RESEND_API_KEY=re_xxx EMAIL_FROM="KC Leads <leads@yourdomain.com>"
   supabase functions deploy send-lead-emails --no-verify-jwt
   ```
   (Prefer SMTP/Gmail instead of Resend? Ask — it's a small change to `sendEmail()`.)
3. **Turn it on** — open the ⛁ settings (top bar) and tick **"Email the sales owner
   when a lead is assigned."** (Stored per browser.)

**Using it:**

- **On assignment** — set/great a lead's *Assigned To* and save; that owner is emailed.
- **Send all at once** — **All Leads → "Email all leads"** groups every assigned lead
  by owner and emails each their list. Owners with no email on file are skipped
  (the toast tells you how many).

**Notes:** in this open-portal setup anyone with the page can trigger the function.
To lock it down, set a `FUNCTION_SECRET` secret and send it as the `x-kc-secret`
header (the function already checks it). For assignments made *outside* the
dashboard (bulk SQL, etc.), add a Supabase **Database Webhook** on the lead tables
pointing at the function instead of relying on the in-app trigger.

## Brand opportunity handoff & approval workflow

The **Brand Opportunities** tab runs the full handoff:

```
LEAD  →  BRAND / CATEGORY OWNER  →  TEAM-LEAD APPROVAL  →  EXTERNAL BRAND EMAIL
```

**Routing** (automatic on create — you can override any field):

- **Paid / onboarded brand** (found in the `paid_brands` master) → assigned to that brand's
  **KC Brand Sales SPOC**, who is also the approver.
- **Unlisted / unpaid brand** → routed to the **Category Team Lead** for its domain
  (Building Material / Interior Surfaces → Renu · MEP → Rutvij · Hardware → Harsh ·
  Building Envelope → Roshan). Furniture and Kitchen & Bathroom have no defined lead, so they
  are marked **TEAM LEAD REQUIRED** rather than mis-assigned. The team lead then assigns a member.

**Approval gate — no external email is ever sent until an approver clicks _Approve & Send_.**
Actions on each opportunity: _Submit for approval_, _Approve & Send_, _Reject_, _Hold_,
_Request info_, and _Preview email_. Statuses run New → Assigned → Awaiting Approval → Approved
→ Sent to Brand → Brand Interested/… with a full audit trail (approver, approved/sent dates,
sender, email status, brand response, next action, follow-up).

**Information firewall.** The external email is built **server-side** by the
`send-brand-opportunity` Edge Function, which reads **only** the sanitized, brand-safe columns
(project type, broad stage, category, material, broad requirement, approximate value, timing,
optional quantity). It never reads project name, location, address, architect / contractor /
site-engineer / client / contact names or numbers, or maps — so they cannot leak. Quantity is
optional; when blank the email says "Requirement quantity to be confirmed." The function also
**re-checks `approval_status = 'Approved'`** before sending, and records `Sent` / `Failed`
honestly (a failure is never marked Sent).

**Sender.** All external brand emails go out from **`success@knowledgecenter.site`**
(configurable in `app_settings`, not per-employee). The `₹10L` no-onboarding threshold in the
unlisted-brand message is a configurable setting too — never hard-coded.

**Setup (one time):**

1. Run [`supabase/migrations/0005_brand_opportunities.sql`](supabase/migrations/0005_brand_opportunities.sql)
   — creates `paid_brands` (seeded), `app_settings` (seeded), and `brand_opportunities`.
2. Deploy the external-email function and set the provider key (server-side, e.g. Replit/Supabase secrets):
   ```
   supabase secrets set RESEND_API_KEY=re_xxx
   supabase functions deploy send-brand-opportunity --no-verify-jwt
   ```
3. Adjust settings if needed under **Manage Data → Settings** (sender, threshold, category leads),
   and the paid list under **Manage Data → Paid Brands**.

**First test (do this before any real brand emails):** create one opportunity for a paid brand
(e.g. Knauf), confirm it routes to that SPOC, submit and _Approve & Send_, then check
`brand_opportunities` — `email_status = Sent`, `sender = success@knowledgecenter.site`. Use
**Preview email** first to confirm no project-identifying information appears. Point `EMAIL_FROM`
at a sandbox recipient of your own until you're satisfied.

## ⚠️ Security — this is an "open portal"

As requested, the RLS policies grant the **`anon` role full read + write** on
every table. That means **anyone who can open the page (and therefore has the
anon key) can read and modify all records — including customer names and phone
numbers.** This is fine for a private/internal link, but before sharing it
widely you should consider locking it down:

- Require sign-in (Supabase Auth) and restrict policies to `authenticated`, or
- Keep public read but require auth to write, or
- Put the page behind access control (host auth / VPN / password).

To harden later, edit the policies in `0001_init.sql` (replace the `anon_all`
policies) and re-run them. The rest of the app is unchanged.

## Regenerating the seed

`supabase/seed.sql` is a snapshot of the original workbook. Re-export the sheets
to the same column layout and regenerate the `insert` statements to refresh it;
the live source of truth after go-live is the database itself.
