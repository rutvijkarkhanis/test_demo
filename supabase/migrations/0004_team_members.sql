-- KC PROJECT LEADS — migration 0004: team members (for email notifications)
-- Maps a person's name (as used in 'Assigned To') to their email.
-- Fill in the emails from the dashboard: Manage Data -> Team Members.
-- Run AFTER 0001_init.sql. Idempotent.

create table if not exists public.team_members (
  id uuid primary key default gen_random_uuid(),
  name text unique not null,
  email text,
  role text,
  active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
drop trigger if exists trg_team_members_updated on public.team_members;
create trigger trg_team_members_updated before update on public.team_members
  for each row execute function public.set_updated_at();

alter table public.team_members enable row level security;
drop policy if exists "anon_all" on public.team_members;
create policy "anon_all" on public.team_members for all to anon, authenticated using (true) with check (true);
grant all on public.team_members to anon, authenticated;

insert into public.team_members (name, role) values
('Aastha','Onboarding'),
('Abhishek','Onboarding'),
('Ajay','Onboarding'),
('Astha','Sales'),
('Ayush','Sales'),
('Bablu','Field'),
('Daksh','Sales'),
('Dhiraj','Sales'),
('Garima','Sales'),
('Harsh','Sales'),
('Hassan','Onboarding'),
('Hemam','Onboarding'),
('Kanishk','Sales'),
('Keshav','Onboarding'),
('Mahesh','Onboarding'),
('Neeraj','Onboarding'),
('Nikhil','Sales'),
('Pihu','Sales'),
('Pratibha','Sales'),
('Rahul','Sales'),
('Ravi','BOQ'),
('Renu','Sales'),
('Rishiraj','Onboarding'),
('Rishiraj Gill','Onboarding'),
('Roshan','Sales'),
('Shiv','Sales'),
('Simran Pandita','Sales'),
('Simran pandita','Sales'),
('Soham','Sales'),
('Suhana','Sales'),
('Vaishali','Sales')
on conflict (name) do nothing;
