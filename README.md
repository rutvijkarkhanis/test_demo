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

Serve it any way you like — GitHub Pages, Vercel, Netlify, Supabase Hosting, or
locally with `python3 -m http.server`.

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
