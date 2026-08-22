-- KC PROJECT LEADS — migration 0003: requirement basis on BOQ / material leads
-- Lets a work requirement be broken into component leads (tile, adhesive, grout,
-- spacer, …) each marked how the quantity was arrived at.
-- Run AFTER 0001_init.sql. Idempotent.

alter table public.boq_materials add column if not exists basis text;   -- Assumed | Derived | Actual
