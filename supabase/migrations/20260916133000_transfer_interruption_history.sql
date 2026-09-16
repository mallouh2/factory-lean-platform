-- End mitigation when its alternative stops; record the original's eventual return separately.
create or replace function private.finish_transfer() returns trigger language plpgsql security definer set search_path='' as $$begin
 if old.status='running' and new.status<>'running' then
 update public.production_transfers set ended_at=now() where alternative_id=new.id and ended_at is null;
 end if;
 if new.status='running' and old.status<>'running' then
 update public.production_transfers set original_returned_at=now(),ended_at=coalesce(ended_at,now()) where original_id=new.id and original_returned_at is null;
 end if;
 return new;end$$;
-- Record the state normalization as an event without rewriting earlier maintenance history.
insert into public.status_events(factory_id,work_center_id,old_status,new_status,notes)
select distinct a.factory_id,a.entity_id,'maintenance','stopped','Maintenance normalized to stop reason; historical events retained.'
from public.audit_logs a where a.entity='work_centers' and a.old_data->>'status'='maintenance' and a.new_data->>'status'='stopped'
and not exists(select 1 from public.status_events e where e.work_center_id=a.entity_id and e.old_status='maintenance' and e.new_status='stopped');
