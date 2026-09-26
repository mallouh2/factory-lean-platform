-- Own membership is already visible in factory_snapshot, even when role
-- administration labels are restricted by RLS.
alter table public.memberships
  add column job_title text,
  add column job_title_ar text;
