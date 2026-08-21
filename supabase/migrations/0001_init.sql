-- KC PROJECT LEADS — Supabase schema
-- Open portal: anon role has full read/write. See README for the security trade-off.
-- Run this in the Supabase SQL Editor (or `supabase db push`) BEFORE seed.sql.

create extension if not exists "pgcrypto";

-- Reusable updated_at trigger
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

-- =========================================================
-- projects (the 3 formal projects + stage-intelligence layer)
-- =========================================================
create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  project_id text unique not null,
  name text,
  status text,
  actual_stage text,
  stage_start_date date,
  projected_stage text,
  next_stage text,
  next_stage_date text,
  material_inferred_stage text,
  earliest_material_stage text,
  latest_material_stage text,
  current_material_signal text,
  stage_confidence text,
  completion_timeline text,
  source text,
  assignee text,
  next_review_date date,
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- =========================================================
-- project_stages (per-project construction stage timeline)
-- =========================================================
create table if not exists public.project_stages (
  id uuid primary key default gen_random_uuid(),
  project_id text,
  stage_name text,
  stage_status text,
  expected_start date,
  expected_end text,
  materials_boq text,
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- =========================================================
-- field_leads (112 field site visits)
-- =========================================================
create table if not exists public.field_leads (
  id uuid primary key default gen_random_uuid(),
  visit_ts text,
  field_exec text,
  site_name text,
  site_type text,
  address text,
  construction_stage text,
  completion_timeline text,
  met_who text,
  person_name text,
  contact_number text,
  known_names text,
  discussed text,
  reaction text,
  brands_mentioned text,
  material_needed text,
  project_id text,
  visit_status text,
  followup_date date,
  assignee text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- =========================================================
-- discussions (64 architect / designer / visitor records)
-- =========================================================
create table if not exists public.discussions (
  id uuid primary key default gen_random_uuid(),
  disc_ts text,
  concierge text,
  visitor_name text,
  firm_name text,
  visitor_type text,
  designation text,
  project_types text,
  project_details text,
  brands text,
  likelihood text,
  notes text,
  contact_number text,
  shared_with_brand text,
  visitor_id text,
  project_id text,
  visit_status text,
  followup_date date,
  assignee text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- =========================================================
-- boq_materials (249 BOQ line items across 17 lead groups)
-- =========================================================
create table if not exists public.boq_materials (
  id uuid primary key default gen_random_uuid(),
  boq_parent_id text,
  boq_id text,
  project_name text,
  trade text,
  lead_group text,
  spec_detail text,
  subitems_merged text,
  total_qty text,
  unit text,
  status text,
  target_brands text,
  opportunity_type text,
  kc_score text,
  priority text,
  notes text,
  project_id text,
  brand_engagement text,
  req_date date,
  assignee text,
  mapped_stage text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- =========================================================
-- duplicates (potential duplicate field sites to review)
-- =========================================================
create table if not exists public.duplicates (
  id uuid primary key default gen_random_uuid(),
  dup_id text,
  site_name text,
  dates_visited text,
  contact_persons text,
  interest_levels text,
  location text,
  field_exec text,
  confidence text,
  recommendation text,
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- updated_at triggers
do $$
declare t text;
begin
  foreach t in array array['projects','project_stages','field_leads','discussions','boq_materials','duplicates'] loop
    execute format('drop trigger if exists trg_%1$s_updated on public.%1$s;', t);
    execute format('create trigger trg_%1$s_updated before update on public.%1$s
                    for each row execute function public.set_updated_at();', t);
  end loop;
end $$;

-- helpful indexes
create index if not exists idx_field_project on public.field_leads(project_id);
create index if not exists idx_field_followup on public.field_leads(followup_date);
create index if not exists idx_disc_project on public.discussions(project_id);
create index if not exists idx_disc_followup on public.discussions(followup_date);
create index if not exists idx_boq_project on public.boq_materials(project_id);
create index if not exists idx_boq_parent on public.boq_materials(boq_parent_id);
create index if not exists idx_boq_req on public.boq_materials(req_date);
create index if not exists idx_stages_project on public.project_stages(project_id);

-- =========================================================
-- Row Level Security — OPEN PORTAL
-- anon (unauthenticated) gets full read + write on every table.
-- WARNING: anyone with the anon key can read and modify all data,
-- including customer names and phone numbers. See README.
-- =========================================================
do $$
declare t text;
begin
  foreach t in array array['projects','project_stages','field_leads','discussions','boq_materials','duplicates'] loop
    execute format('alter table public.%I enable row level security;', t);
    execute format('drop policy if exists "anon_all" on public.%I;', t);
    execute format($f$create policy "anon_all" on public.%I
                     for all to anon, authenticated using (true) with check (true);$f$, t);
  end loop;
end $$;
