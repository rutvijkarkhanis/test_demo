-- KC PROJECT LEADS — migration 0005: brand opportunity handoff + approval workflow
-- Adds the LEAD → BRAND/CATEGORY OWNER → TEAM-LEAD APPROVAL → EXTERNAL BRAND EMAIL pipeline.
--   * paid_brands        — the paid/onboarded brand master (Brand, Category, KC Brand Sales SPOC)
--   * app_settings        — configurable system settings (₹ threshold, external sender, category team leads)
--   * brand_opportunities — one row per material opportunity, with a strict split between
--                           INTERNAL project data and the SANITIZED, brand-facing opportunity.
-- Run AFTER 0001_init.sql (needs public.set_updated_at()). Idempotent — safe to re-run.

-- ============================================================
-- 1. PAID / ONBOARDED BRAND MASTER
-- ============================================================
create table if not exists public.paid_brands (
  id uuid primary key default gen_random_uuid(),
  brand text unique not null,
  category text,                         -- category / domain (optional; backfilled where known)
  spoc text,                             -- KC Brand Sales SPOC responsible for this brand
  active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
drop trigger if exists trg_paid_brands_updated on public.paid_brands;
create trigger trg_paid_brands_updated before update on public.paid_brands
  for each row execute function public.set_updated_at();

alter table public.paid_brands enable row level security;
drop policy if exists "anon_all" on public.paid_brands;
create policy "anon_all" on public.paid_brands for all to anon, authenticated using (true) with check (true);
grant all on public.paid_brands to anon, authenticated;

-- Paid brand list (de-duplicated; on conflict keeps the SPOC current).
insert into public.paid_brands (brand, spoc) values
('PLANTAG Coatings','Renu'),
('Ritu Bricks','Harsh'),
('Surfex',null),
('Taco','Harsh'),
('Advance Decorative Laminates','Renu'),
('Heritage Laminates','Renu'),
('Midori - The Garden Studio','Harsh'),
('Sunframed','Renu'),
('MARMOLA','Harsh'),
('Viva','Renu'),
('Stonelam','Renu'),
('Syncline Products LLP','Soham'),
('Safelam Laminates','Harsh'),
('Hunter Douglas','Rutvij'),
('Forma','Harsh'),
('Metro Arte Ceramica','Simran'),
('Livin Blinds','Shiv'),
('Karara Mujassme','Harsh'),
('BB Living','Garima'),
('Keetronics','Kanishk'),
('Adona Woods','Pratibha'),
('Mystic Panel and Planks','Vaibhav'),
('Harrison Locks','Renu'),
('Knauf','Renu'),
('Italeno India LLP','Vaibhav'),
('KG Tiles','Renu'),
('Teak & Torch','Vaibhav'),
('Furniture Zone','Vaibhav'),
('STRAWCTURE ECO','Vaibhav'),
('Eurobond','Roshan'),
('OneAir Living','Renu'),
('Universal Quartz','Garima'),
('Morzze','Renu'),
('Kerakoll','Renu'),
('Legend','Renu'),
('Specta','Shiv'),
('The Aangan Living','Vaibhav'),
('Prayag Clay','Vaibhav'),
('Legnoso Art','Shiv'),
('Chair Collective','Manjeet')
on conflict (brand) do update set spoc = excluded.spoc, active = true;

-- Best-effort category backfill from the general brands master (0002), where names match.
update public.paid_brands p
   set category = b.category
  from public.brands b
 where lower(trim(p.brand)) = lower(trim(b.brand))
   and (p.category is null or p.category = '')
   and coalesce(b.category,'') <> '';

-- ============================================================
-- 2. SYSTEM SETTINGS (configurable, not hard-coded)
-- ============================================================
create table if not exists public.app_settings (
  key text primary key,
  value text,
  note text,
  updated_at timestamptz default now()
);
drop trigger if exists trg_app_settings_updated on public.app_settings;
create trigger trg_app_settings_updated before update on public.app_settings
  for each row execute function public.set_updated_at();

alter table public.app_settings enable row level security;
drop policy if exists "anon_all" on public.app_settings;
create policy "anon_all" on public.app_settings for all to anon, authenticated using (true) with check (true);
grant all on public.app_settings to anon, authenticated;

insert into public.app_settings (key, value, note) values
('brand_email_sender','success@knowledgecenter.site','From address for ALL external brand emails (never an individual).'),
('opportunity_threshold_inr','1000000','Max opportunity value (INR) an unlisted brand may receive without onboarding.'),
('opportunity_threshold_label','₹10L','Human label for the threshold, shown in the unpaid-brand message.'),
('currency','INR','Currency for opportunity values.'),
-- Category / domain → team lead (only where defined; blanks stay "TEAM LEAD REQUIRED").
('lead:Building Material / Interior Surfaces','Renu',null),
('lead:MEP','Rutvij',null),
('lead:Hardware','Harsh',null),
('lead:Building Envelope','Roshan',null)
on conflict (key) do nothing;

-- ============================================================
-- 3. BRAND OPPORTUNITIES  (the approval record + audit trail)
-- ============================================================
create sequence if not exists public.opp_seq start 1;

create table if not exists public.brand_opportunities (
  id uuid primary key default gen_random_uuid(),
  opp_id text unique default ('OPP-' || lpad(nextval('public.opp_seq')::text, 4, '0')),

  -- classification / routing
  brand text,
  category text,                         -- category / domain (drives unpaid routing)
  material text,
  paid text,                             -- 'Paid' | 'Unpaid'
  spoc text,                             -- Brand Sales SPOC (paid brands)
  team_lead text,                        -- Category team lead (unpaid brands)
  assigned_to text,                      -- individual currently working the opportunity
  approver text,                         -- who must approve before external send

  -- workflow state (see status list in the app)
  status text default 'New',
  approval_status text default 'Pending',-- Pending | Approved | Rejected | On Hold | Needs More Information
  approved_date date,
  sent_date date,
  sender text default 'success@knowledgecenter.site',
  email_status text default 'Not Sent',  -- Not Sent | Sent | Failed
  brand_response text,
  next_action text,
  followup_date date,

  -- SANITIZED, brand-facing opportunity (safe to send externally)
  brand_email text,                      -- recipient at the brand
  project_type text,
  stage_band text,                       -- broad construction stage
  requirement text,                      -- broad requirement
  quantity text,                         -- optional; blank => "to be confirmed"
  approx_value numeric,                  -- approximate opportunity value (INR)
  timing text,                           -- general requirement timing
  sanitized_notes text,                  -- any other NON-identifying info for the brand

  -- INTERNAL ONLY — never included in the external email (information firewall)
  project_id text,                       -- link back to the internal project (KC-00x)
  source_boq_id text,                    -- optional link to a boq_materials row
  internal_notes text,

  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
drop trigger if exists trg_brand_opportunities_updated on public.brand_opportunities;
create trigger trg_brand_opportunities_updated before update on public.brand_opportunities
  for each row execute function public.set_updated_at();

create index if not exists idx_opp_status on public.brand_opportunities(status);
create index if not exists idx_opp_approver on public.brand_opportunities(approver);
create index if not exists idx_opp_assigned on public.brand_opportunities(assigned_to);

alter table public.brand_opportunities enable row level security;
drop policy if exists "anon_all" on public.brand_opportunities;
create policy "anon_all" on public.brand_opportunities for all to anon, authenticated using (true) with check (true);
grant all on public.brand_opportunities to anon, authenticated;
grant usage, select on sequence public.opp_seq to anon, authenticated;

-- ============================================================
-- 4. TEAM MEMBERS referenced by routing that 0004 may not have
--    (team leads + members named in the handoff rules)
-- ============================================================
insert into public.team_members (name, role) values
('Rutvij','Team Lead'),
('Vaibhav','Team Lead'),
('Meenu','Sales'),
('Priyanka','Sales'),
('Manjeet','Sales'),
('Kanishk','Sales'),
('Nikhil','Sales'),
('Daksh','Sales'),
('Simran','Sales')
on conflict (name) do nothing;
