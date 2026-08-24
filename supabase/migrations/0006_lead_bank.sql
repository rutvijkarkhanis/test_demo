-- KC PROJECT LEADS — migration 0006: the Lead Bank (Lead Register)
--
-- ONE operational register through which every lead moves, WITHOUT ever moving a
-- record out of its original source table. A Field Lead stays a Field Lead; a
-- Discussion stays a Discussion; a BOQ line stays a BOQ line. Each gets a linked
-- Lead Bank row (unique Lead ID) that carries the lifecycle.
--
--   * lead_register — the Lead Bank (one row per source record, linked by source_table+id)
--   * lead_events   — per-lead history / audit trail
--   * make_list     — a new source (empty for now; import when the sheet arrives)
--
-- Triggers keep the Lead Bank in sync as new source rows are added; a one-time
-- backfill links every record that already exists. Source rows are never modified.
-- Run AFTER 0001–0005. Idempotent.

-- ============================================================
-- MAKE LIST source (empty for now)
-- ============================================================
create table if not exists public.make_list (
  id uuid primary key default gen_random_uuid(),
  make_id text,
  project text,
  project_id text,
  category text,
  material text,
  brand_make text,
  notes text,
  source_owner text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
drop trigger if exists trg_make_list_updated on public.make_list;
create trigger trg_make_list_updated before update on public.make_list
  for each row execute function public.set_updated_at();
alter table public.make_list enable row level security;
drop policy if exists "anon_all" on public.make_list;
create policy "anon_all" on public.make_list for all to anon, authenticated using (true) with check (true);
grant all on public.make_list to anon, authenticated;

-- ============================================================
-- LEAD BANK
-- ============================================================
create sequence if not exists public.lead_seq start 1;

create table if not exists public.lead_register (
  id uuid primary key default gen_random_uuid(),
  lead_id text unique default ('LB-' || lpad(nextval('public.lead_seq')::text, 5, '0')),

  -- provenance — the lead keeps its original source forever
  source text,                 -- Field Team | Architect / Designer | KC Reception / Concierge | Project BOQ | Make List
  source_table text,           -- field_leads | discussions | boq_materials | make_list
  source_record_id uuid,       -- the source row's id (never changed)
  source_ref text,             -- human ref from the source (V-###, boq_id, …) when present
  source_owner text,           -- who brought the lead in (Bablu, concierge, Ravi, …)

  -- operational fields
  project_id text,             -- blank when unknown (never forced)
  material_category text,
  construction_stage text,
  brand_make text,
  lead_status text default 'New',
  brand_status text,           -- mirrors the linked brand_opportunity's status
  assigned_to text,
  next_action text,
  next_action_date date,
  last_action text,
  last_action_date date,

  opportunity_id uuid,         -- link to brand_opportunities.id once it's a Material Opportunity

  created_date date default current_date,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),

  unique (source_table, source_record_id)   -- exactly one Lead Bank row per source record
);
drop trigger if exists trg_lead_register_updated on public.lead_register;
create trigger trg_lead_register_updated before update on public.lead_register
  for each row execute function public.set_updated_at();

create index if not exists idx_lr_status on public.lead_register(lead_status);
create index if not exists idx_lr_source on public.lead_register(source);
create index if not exists idx_lr_assignee on public.lead_register(assigned_to);
create index if not exists idx_lr_opp on public.lead_register(opportunity_id);

alter table public.lead_register enable row level security;
drop policy if exists "anon_all" on public.lead_register;
create policy "anon_all" on public.lead_register for all to anon, authenticated using (true) with check (true);
grant all on public.lead_register to anon, authenticated;
grant usage, select on sequence public.lead_seq to anon, authenticated;

-- ============================================================
-- LEAD HISTORY
-- ============================================================
create table if not exists public.lead_events (
  id uuid primary key default gen_random_uuid(),
  lead_id text,                -- lead_register.lead_id
  event_type text,             -- Created | Status Change | Assigned | Opportunity Created | Approved | Sent to Brand | Source Follow-up | Note
  detail text,
  actor text,
  created_at timestamptz default now()
);
create index if not exists idx_le_lead on public.lead_events(lead_id);
alter table public.lead_events enable row level security;
drop policy if exists "anon_all" on public.lead_events;
create policy "anon_all" on public.lead_events for all to anon, authenticated using (true) with check (true);
grant all on public.lead_events to anon, authenticated;

-- ============================================================
-- SYNC LOGIC — link source rows into the Lead Bank (never modifies the source)
-- ============================================================
-- Classify a discussion as Architect/Designer vs Reception/Concierge from visitor_type.
create or replace function public.lr_disc_source(vtype text) returns text as $$
  select case when coalesce($1,'') ilike '%architect%' or coalesce($1,'') ilike '%designer%'
              then 'Architect / Designer' else 'KC Reception / Concierge' end;
$$ language sql immutable;

-- Only accept a real KC project id; junk / blank stays NULL (never forced into a project).
create or replace function public.lr_kc_pid(pid text) returns text as $$
  select case when coalesce($1,'') ~ '^KC-' then $1 else null end;
$$ language sql immutable;

-- Per-source trigger functions
create or replace function public.lr_from_field() returns trigger as $$
begin
  insert into public.lead_register(source,source_table,source_record_id,source_ref,source_owner,
     project_id,material_category,construction_stage,brand_make,assigned_to,lead_status)
  values('Field Team','field_leads',NEW.id,null,NEW.field_exec,
     public.lr_kc_pid(NEW.project_id),NEW.material_needed,NEW.construction_stage,NEW.brands_mentioned,NEW.assignee,
     case when NEW.visit_status='Hot Lead' then 'Qualified' else 'New' end)
  on conflict (source_table,source_record_id) do nothing;
  return NEW;
end $$ language plpgsql;

create or replace function public.lr_from_disc() returns trigger as $$
begin
  insert into public.lead_register(source,source_table,source_record_id,source_ref,source_owner,
     project_id,material_category,construction_stage,brand_make,assigned_to,lead_status)
  values(public.lr_disc_source(NEW.visitor_type),'discussions',NEW.id,NEW.visitor_id,NEW.concierge,
     public.lr_kc_pid(NEW.project_id),NEW.project_types,null,NEW.brands,NEW.assignee,
     case when NEW.visit_status='Qualified Prospect' then 'Qualified' else 'New' end)
  on conflict (source_table,source_record_id) do nothing;
  return NEW;
end $$ language plpgsql;

create or replace function public.lr_from_boq() returns trigger as $$
begin
  insert into public.lead_register(source,source_table,source_record_id,source_ref,source_owner,
     project_id,material_category,construction_stage,brand_make,assigned_to,lead_status)
  values('Project BOQ','boq_materials',NEW.id,NEW.boq_id,coalesce(NEW.assignee,'Ravi'),
     public.lr_kc_pid(NEW.project_id),coalesce(NEW.trade,NEW.lead_group),NEW.mapped_stage,NEW.target_brands,NEW.assignee,'New')
  on conflict (source_table,source_record_id) do nothing;
  return NEW;
end $$ language plpgsql;

create or replace function public.lr_from_make() returns trigger as $$
begin
  insert into public.lead_register(source,source_table,source_record_id,source_ref,source_owner,
     project_id,material_category,construction_stage,brand_make,assigned_to,lead_status)
  values('Make List','make_list',NEW.id,NEW.make_id,NEW.source_owner,
     public.lr_kc_pid(NEW.project_id),coalesce(NEW.category,NEW.material),null,NEW.brand_make,null,'New')
  on conflict (source_table,source_record_id) do nothing;
  return NEW;
end $$ language plpgsql;

drop trigger if exists trg_lr_field on public.field_leads;
create trigger trg_lr_field after insert on public.field_leads for each row execute function public.lr_from_field();
drop trigger if exists trg_lr_disc on public.discussions;
create trigger trg_lr_disc after insert on public.discussions for each row execute function public.lr_from_disc();
drop trigger if exists trg_lr_boq on public.boq_materials;
create trigger trg_lr_boq after insert on public.boq_materials for each row execute function public.lr_from_boq();
drop trigger if exists trg_lr_make on public.make_list;
create trigger trg_lr_make after insert on public.make_list for each row execute function public.lr_from_make();

-- ============================================================
-- ONE-TIME BACKFILL of every existing source record
-- ============================================================
insert into public.lead_register(source,source_table,source_record_id,source_ref,source_owner,
   project_id,material_category,construction_stage,brand_make,assigned_to,lead_status,created_date)
select 'Field Team','field_leads',f.id,null,f.field_exec,
   public.lr_kc_pid(f.project_id),f.material_needed,f.construction_stage,f.brands_mentioned,f.assignee,
   case when f.visit_status='Hot Lead' then 'Qualified' else 'New' end, current_date
from public.field_leads f
on conflict (source_table,source_record_id) do nothing;

insert into public.lead_register(source,source_table,source_record_id,source_ref,source_owner,
   project_id,material_category,construction_stage,brand_make,assigned_to,lead_status,created_date)
select public.lr_disc_source(d.visitor_type),'discussions',d.id,d.visitor_id,d.concierge,
   public.lr_kc_pid(d.project_id),d.project_types,null,d.brands,d.assignee,
   case when d.visit_status='Qualified Prospect' then 'Qualified' else 'New' end, current_date
from public.discussions d
on conflict (source_table,source_record_id) do nothing;

insert into public.lead_register(source,source_table,source_record_id,source_ref,source_owner,
   project_id,material_category,construction_stage,brand_make,assigned_to,lead_status,created_date)
select 'Project BOQ','boq_materials',b.id,b.boq_id,coalesce(b.assignee,'Ravi'),
   public.lr_kc_pid(b.project_id),coalesce(b.trade,b.lead_group),b.mapped_stage,b.target_brands,b.assignee,'New', current_date
from public.boq_materials b
on conflict (source_table,source_record_id) do nothing;

-- Seed a 'Created' history event for any lead that has none yet.
insert into public.lead_events(lead_id,event_type,detail,actor)
select lr.lead_id,'Created','Linked from '||lr.source_table||' ('||lr.source||')','system'
from public.lead_register lr
where not exists (select 1 from public.lead_events le where le.lead_id = lr.lead_id);
