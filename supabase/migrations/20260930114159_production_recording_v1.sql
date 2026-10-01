-- Preserve the legacy gross/rejected ledger. Good output alone completes demand.
alter table public.production_orders
  add column good_quantity numeric generated always as (produced_quantity-rejected_quantity) stored,
  add column remaining_quantity numeric generated always as (greatest(target_quantity-produced_quantity+rejected_quantity,0)) stored,
  add column overproduction_quantity numeric generated always as (greatest(produced_quantity-rejected_quantity-target_quantity,0)) stored;
alter table public.production_entries
  alter column work_center_id drop not null,
  add column line_id uuid,
  add column technician_id uuid,
  add column unit text,
  add column recording_version integer not null default 1,
  add column good_quantity numeric,
  add column scrap_quantity numeric,
  add column effective_good numeric,
  add column effective_scrap numeric,
  add column running_good numeric,
  add column remaining_quantity numeric,
  add column overproduction_confirmed boolean not null default false,
  add constraint entry_line_fk foreign key(factory_id,line_id) references public.production_lines(factory_id,id),
  add constraint entry_technician_fk foreign key(factory_id,technician_id) references public.memberships(factory_id,id),
  add constraint entry_factory_id_unique unique(factory_id,id);
-- These quantities follow the old API's explicit gross/rejected semantics;
-- originals and timestamps/actors are not changed or invented.
update public.production_entries e set good_quantity=e.produced-e.rejected,
  scrap_quantity=e.rejected,effective_good=e.produced-e.rejected,effective_scrap=e.rejected,
  unit=o.unit from public.production_orders o where o.id=e.order_id;
alter table public.production_entries
  alter column good_quantity set not null, alter column scrap_quantity set not null,
  alter column effective_good set not null, alter column effective_scrap set not null,
  add constraint entry_recording_quantities check(good_quantity>=0 and scrap_quantity>=0 and effective_good>=0 and effective_scrap>=0),
  add constraint entry_recording_unit check(recording_version=1 or
    (recording_version=2 and technician_id is not null and unit in ('meter','piece') and
      ((line_id is not null and work_center_id is null) or (line_id is null and work_center_id is not null))));

create table public.production_entry_corrections(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null,
 entry_id uuid not null,previous_good numeric not null,previous_scrap numeric not null,
 corrected_good numeric not null check(corrected_good>=0),corrected_scrap numeric not null check(corrected_scrap>=0),
 reason text not null check(length(trim(reason)) between 3 and 2000),
 created_by uuid not null references auth.users,created_at timestamptz not null default clock_timestamp(),
 request_id uuid not null,overproduction_confirmed boolean not null default false,
 unique(factory_id,request_id),foreign key(factory_id,entry_id) references public.production_entries(factory_id,id)
);
alter table public.production_entry_corrections enable row level security;
create policy scoped_read on public.production_entry_corrections for select to authenticated
 using(private.has_permission(factory_id,'orders','view'));
grant select on public.production_entry_corrections to authenticated;
create index on public.production_entry_corrections(factory_id,entry_id,created_at);
create trigger audit_insert after insert on public.production_entry_corrections for each row execute function private.audit_change();

-- Shared eligibility query: UI consumes this RPC rather than rebuilding rules.
create function private.production_recording_units(f uuid)
returns table(unit_kind text,unit_id uuid,item_id uuid) language sql stable security definer set search_path='' as $$
 select 'line',l.id,o.id from public.production_lines l
 join public.production_orders o on o.factory_id=l.factory_id and o.line_id=l.id
 where l.factory_id=f and not l.archived and o.status='active' and o.actual_start is not null and o.actual_finish is null and o.unit in ('meter','piece')
 union all
 select 'machine',c.id,o.id from public.work_centers c
 join public.production_orders o on o.factory_id=c.factory_id and
 o.id=private.execution_center_order(c.factory_id,c.id,c.line_id,c.order_id)
 where c.factory_id=f and not c.archived and c.line_id is null and c.dependency_mode='independent'
 and o.status='active' and o.actual_start is not null and o.actual_finish is null
 and not exists(select 1 from public.production_transfers t where t.factory_id=f and t.ended_at is null
   and c.id in(t.original_id,t.alternative_id))
 and exists(select 1 from public.work_center_capabilities cap where cap.factory_id=f and cap.work_center_id=c.id
   and cap.product_id=o.product_id and cap.rate_unit=o.unit and cap.rate>0);
$$;
create function public.production_recording_units(factory uuid)
returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(factory,'orders','view');
 return jsonb_build_object('units',(select coalesce(jsonb_agg(to_jsonb(u)),'[]'::jsonb) from private.production_recording_units(factory) u),
 'technicians',(select coalesce(jsonb_agg(to_jsonb(m)),'[]'::jsonb) from
   (select id,display_name,user_id from public.memberships where factory_id=factory and status='approved') m));
end$$;

create function private.record_production(f uuid,kind text,u uuid,i uuid,technician uuid,good numeric,scrap numeric,n text,confirmed boolean,r uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare job public.production_orders;previous public.production_entries;result uuid;total numeric;
begin
 perform private.require_permission(f,'orders','edit');
 perform private.require_permission(f,'orders','view');
 if r is null or technician is null or good is null or scrap is null or good<0 or scrap<0 or good+scrap<=0
   or good::text in ('NaN','Infinity','-Infinity') or scrap::text in ('NaN','Infinity','-Infinity')
   or length(coalesce(n,''))>2000 then raise exception 'recording_invalid_quantity';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(f::text||':structure',0));
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(f::text||r::text,0));
 select * into previous from public.production_entries e where e.factory_id=f and e.request_id=r;
 if found then
   if previous.recording_version<>2 or previous.order_id<>i or previous.technician_id<>technician
     or previous.line_id is distinct from (case when kind='line' then u end)
     or previous.work_center_id is distinct from (case when kind='machine' then u end)
     or previous.good_quantity<>good or previous.scrap_quantity<>scrap or previous.notes<>coalesce(n,'')
     or previous.created_by<>auth.uid() or previous.overproduction_confirmed<>coalesce(confirmed,false)
     then raise exception 'request_conflict';end if;
   return previous.id;
 end if;
 select * into job from public.production_orders o where o.factory_id=f and o.id=i for update;
 if not found or not exists(select 1 from private.production_recording_units(f) x
   where x.unit_kind=kind and x.unit_id=u and x.item_id=i) then raise exception 'recording_invalid_unit';end if;
 if not exists(select 1 from public.memberships m where m.factory_id=f and m.id=technician and m.status='approved')
   then raise exception 'invalid_operator';end if;
 total:=job.good_quantity+good;
 if total>job.target_quantity and not coalesce(confirmed,false) then raise exception 'recording_overproduction_confirmation';end if;
 insert into public.production_entries(factory_id,order_id,line_id,work_center_id,technician_id,unit,recording_version,
   produced,rejected,good_quantity,scrap_quantity,effective_good,effective_scrap,notes,created_by,created_at,request_id,
   running_good,remaining_quantity,overproduction_confirmed)
 values(f,i,case when kind='line' then u end,case when kind='machine' then u end,technician,job.unit,2,
   good+scrap,scrap,good,scrap,good,scrap,coalesce(n,''),auth.uid(),clock_timestamp(),r,total,greatest(job.target_quantity-total,0),coalesce(confirmed,false))
 returning id into result;
 update public.production_orders set produced_quantity=produced_quantity+good+scrap,rejected_quantity=rejected_quantity+scrap where id=i;
 return result;
end$$;
create function public.record_production(factory uuid,unit_kind text,production_unit uuid,item uuid,technician uuid,
 good numeric,scrap numeric,notes text default '',confirm_overproduction boolean default false,request_id uuid default gen_random_uuid())
returns uuid language sql security invoker set search_path='' as $$
 select private.record_production(factory,unit_kind,production_unit,item,technician,good,scrap,notes,confirm_overproduction,request_id)
$$;

create function private.correct_production(f uuid,e uuid,good numeric,scrap numeric,reason text,confirmed boolean,r uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare original public.production_entries;job public.production_orders;previous public.production_entry_corrections;result uuid;total numeric;
begin
 perform private.require_permission(f,'orders','edit');
 perform private.require_permission(f,'orders','view');
 if r is null or good is null or scrap is null or good<0 or scrap<0
   or good::text in ('NaN','Infinity','-Infinity') or scrap::text in ('NaN','Infinity','-Infinity')
   or length(trim(coalesce(reason,''))) not between 3 and 2000 then raise exception 'recording_correction_reason';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(f::text||':structure',0));
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(f::text||r::text,0));
 select * into previous from public.production_entry_corrections c where c.factory_id=f and c.request_id=r;
 if found then
   if previous.entry_id<>e or previous.corrected_good<>good or previous.corrected_scrap<>scrap or previous.reason<>reason
     or previous.created_by<>auth.uid() or previous.overproduction_confirmed<>coalesce(confirmed,false) then raise exception 'request_conflict';end if;
   return previous.id;
 end if;
 select * into original from public.production_entries x where x.factory_id=f and x.id=e;
 if not found then raise exception 'invalid_order';end if;
 select * into job from public.production_orders o where o.factory_id=f and o.id=original.order_id for update;
 select * into original from public.production_entries x where x.factory_id=f and x.id=e for update;
 total:=job.good_quantity-original.effective_good+good;
 if total>job.target_quantity and not coalesce(confirmed,false) then raise exception 'recording_overproduction_confirmation';end if;
 insert into public.production_entry_corrections(factory_id,entry_id,previous_good,previous_scrap,corrected_good,corrected_scrap,reason,created_by,request_id,overproduction_confirmed)
 values(f,e,original.effective_good,original.effective_scrap,good,scrap,reason,auth.uid(),r,coalesce(confirmed,false)) returning id into result;
 update public.production_orders set produced_quantity=produced_quantity-original.effective_good-original.effective_scrap+good+scrap,
   rejected_quantity=rejected_quantity-original.effective_scrap+scrap where id=job.id;
 update public.production_entries set effective_good=good,effective_scrap=scrap where id=e;
 return result;
end$$;
create function public.correct_production_entry(factory uuid,entry uuid,good numeric,scrap numeric,reason text,
 confirm_overproduction boolean default false,request_id uuid default gen_random_uuid())
returns uuid language sql security invoker set search_path='' as $$
 select private.correct_production(factory,entry,good,scrap,reason,confirm_overproduction,request_id)
$$;

-- Remove the former machine-based write path, including private callable helper.
revoke execute on function public.record_output(uuid,uuid,uuid,numeric,numeric,text,uuid),
 private.record_output_once(uuid,uuid,uuid,numeric,numeric,text,uuid) from authenticated;
revoke all on function private.production_recording_units(uuid) from public,anon,authenticated;
revoke all on function public.production_recording_units(uuid),
 private.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid),
 public.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid),
 private.correct_production(uuid,uuid,numeric,numeric,text,boolean,uuid),
 public.correct_production_entry(uuid,uuid,numeric,numeric,text,boolean,uuid) from public,anon;
grant execute on function public.production_recording_units(uuid),
 private.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid),
 public.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid),
 private.correct_production(uuid,uuid,numeric,numeric,text,boolean,uuid),
 public.correct_production_entry(uuid,uuid,numeric,numeric,text,boolean,uuid) to authenticated;
