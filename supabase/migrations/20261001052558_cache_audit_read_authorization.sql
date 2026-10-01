-- factory_snapshot reads up to 5,000 audit rows. Evaluate the existing
-- per-person permission once per factory per statement, not once per row.
-- This private lookup delegates every decision to the unchanged authorizer.
create function private.audit_read_factories()
returns uuid[] language sql stable security definer set search_path='' as $$
 select coalesce(array_agg(f.id), '{}'::uuid[])
 from public.factories f
 where auth.uid() is not null
   and private.has_permission(f.id, 'audit', 'view');
$$;
revoke all on function private.audit_read_factories() from public, anon;
grant execute on function private.audit_read_factories() to authenticated;

alter policy read_authorized on public.audit_logs
using (factory_id = any ((select private.audit_read_factories())::uuid[]));
