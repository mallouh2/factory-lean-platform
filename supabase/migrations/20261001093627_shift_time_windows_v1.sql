-- Shift windows use factory-local wall time, inclusive start / exclusive end.
-- Existing identity-only shifts remain untimed; historical entries are never inferred.
create extension if not exists btree_gist with schema extensions;
alter table public.production_shifts add column start_time time, add column end_time time,
 add constraint production_shift_times_valid check (
 (start_time is null and end_time is null) or
 (start_time is not null and end_time is not null and start_time<>end_time
 and start_time<time '24:00' and end_time<time '24:00'));

-- One representation for containment AND overlap, including the two halves of night shifts.
create function private.production_shift_window(a time,b time) returns nummultirange
language sql immutable set search_path='' as $$
 select case when a is null or b is null then '{}'::nummultirange
 when a<b then nummultirange(numrange(extract(epoch from a),extract(epoch from b),'[)'))
 else nummultirange(numrange(extract(epoch from a),86400,'[)'),numrange(0,extract(epoch from b),'[)')) end
$$;
-- Exclusion constraints also reject concurrent conflicting writes, independent of transaction snapshots.
alter table public.production_shifts add constraint production_shift_no_overlap
 exclude using gist (factory_id extensions.gist_uuid_ops with =,
 (private.production_shift_window(start_time,end_time)) with &&) where (not archived);

create function private.resolve_factory_shift(f uuid,at_time timestamptz) returns uuid
language sql stable security definer set search_path='' as $$
 select s.id from public.factories x join public.production_shifts s on s.factory_id=x.id
 where x.id=f and not s.archived and private.production_shift_window(s.start_time,s.end_time)
 @> extract(epoch from (at_time at time zone x.timezone)::time)
$$;

create function public.production_shift_context(factory uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare at_time timestamptz:=clock_timestamp();zone text;begin
 if not (private.has_permission(factory,'orders','view') or private.has_permission(factory,'settings','view'))
 then raise exception 'permission_denied';end if;
 select timezone into zone from public.factories where id=factory;
 return jsonb_build_object('timestamp',at_time,'timezone',zone,
 'local_time',to_char(at_time at time zone zone,'HH24:MI'),
 'shift_id',private.resolve_factory_shift(factory,at_time),
 'active_count',(select count(*) from public.production_shifts where factory_id=factory and not archived));
end$$;

drop function public.configure_production_shift(uuid,text,text,uuid,boolean);
create function public.configure_production_shift(factory uuid,name text,name_ar text,
 start_time time,end_time time,id uuid default null,archived boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;legacy_archive boolean;begin
 perform private.require_permission(factory,'settings','edit');
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(factory::text||':structure',0));
 if length(trim(coalesce(name,''))) not between 1 and 120 or length(trim(coalesce(name_ar,''))) not between 1 and 120
 or archived is null then raise exception 'shift_invalid';end if;
 -- An existing untimed shift may be archived without inventing its schedule.
 select $7 and s.start_time is null and s.end_time is null into legacy_archive
 from public.production_shifts s where s.factory_id=$1 and s.id=$6;
 if not (coalesce(legacy_archive,false) and $4 is null and $5 is null) and
 ($4 is null or $5 is null or $4=$5 or $4>=time '24:00' or $5>=time '24:00')
 then raise exception 'shift_window_invalid';end if;
 if id is null then
 insert into public.production_shifts(factory_id,name,name_ar,start_time,end_time,archived,created_by)
 values($1,trim($2),trim($3),$4,$5,$7,auth.uid()) returning production_shifts.id into result;
 else update public.production_shifts s set name=trim($2),name_ar=trim($3),start_time=$4,end_time=$5,archived=$7
 where s.factory_id=$1 and s.id=$6 returning s.id into result;
 if result is null then raise exception 'shift_invalid';end if;end if;
 return result;
exception when exclusion_violation then raise exception 'shift_overlap';
end$$;

alter table public.production_entries
 add column automatic_shift_id uuid,
 add column requested_shift_id uuid,
 add column shift_assignment_mode text check(shift_assignment_mode in ('automatic','manual','unconfigured')),
 add column shift_override_reason text,
 add column shift_override_by uuid references auth.users,
 add column shift_override_at timestamptz,
 add foreign key(factory_id,automatic_shift_id) references public.production_shifts(factory_id,id),
 add foreign key(factory_id,requested_shift_id) references public.production_shifts(factory_id,id);

-- Replace the public signature; retire the old private write path so it cannot bypass attribution.
drop function public.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid);
revoke execute on function private.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid) from authenticated;

create function private.record_production(f uuid,kind text,u uuid,i uuid,technician uuid,good numeric,scrap numeric,
 n text,confirmed boolean,r uuid,shift uuid,override_reason text)
returns uuid language plpgsql security definer set search_path='' as $$
declare job public.production_orders;previous public.production_entries;result uuid;total numeric;
 at_time timestamptz;automatic uuid;selected uuid;mode text;why text:=nullif(trim(override_reason),'');
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
     or (case when previous.shift_assignment_mode is null then previous.original_shift_id else previous.requested_shift_id end) is distinct from shift
     or previous.shift_override_reason is distinct from why
     or previous.created_by<>auth.uid() or previous.overproduction_confirmed<>coalesce(confirmed,false)
     then raise exception 'request_conflict';end if;
   return previous.id;
 end if;
 -- Capture once, after locks: this exact timestamp is persisted and used for attribution.
 at_time:=clock_timestamp();automatic:=private.resolve_factory_shift(f,at_time);
 selected:=coalesce(shift,automatic);mode:='automatic';
 if shift is not null then
   perform private.validate_production_shift(f,shift);
   if shift is distinct from automatic or why is not null then
     if length(coalesce(why,'')) not between 3 and 2000 then raise exception 'shift_override_reason';end if;
     mode:='manual';
   end if;
 elsif why is not null then raise exception 'shift_override_reason';
 elsif automatic is null then
   if exists(select 1 from public.production_shifts where factory_id=f and not archived)
   then raise exception 'shift_no_match';end if;
   mode:='unconfigured';
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
   running_good,remaining_quantity,overproduction_confirmed,shift_id,original_shift_id,
   automatic_shift_id,requested_shift_id,shift_assignment_mode,shift_override_reason,shift_override_by,shift_override_at)
 values(f,i,case when kind='line' then u end,case when kind='machine' then u end,technician,job.unit,2,
   good+scrap,scrap,good,scrap,good,scrap,coalesce(n,''),auth.uid(),at_time,r,total,greatest(job.target_quantity-total,0),coalesce(confirmed,false),selected,selected,
   automatic,shift,mode,why,case when mode='manual' then auth.uid() end,case when mode='manual' then at_time end)
 returning id into result;
 update public.production_orders set produced_quantity=produced_quantity+good+scrap,rejected_quantity=rejected_quantity+scrap where id=i;
 return result;
end$$;

create function public.record_production(factory uuid,unit_kind text,production_unit uuid,item uuid,technician uuid,
 good numeric,scrap numeric,notes text default '',confirm_overproduction boolean default false,
 request_id uuid default gen_random_uuid(),shift uuid default null,shift_override_reason text default null)
returns uuid language sql security invoker set search_path='' as $$
 select private.record_production(factory,unit_kind,production_unit,item,technician,good,scrap,notes,confirm_overproduction,request_id,shift,shift_override_reason)
$$;
revoke all on function private.production_shift_window(time,time),private.resolve_factory_shift(uuid,timestamptz),
 public.production_shift_context(uuid),public.configure_production_shift(uuid,text,text,time,time,uuid,boolean),
 private.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,text),
 public.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,text) from public,anon;
revoke all on function private.production_shift_window(time,time),private.resolve_factory_shift(uuid,timestamptz) from authenticated;
grant execute on function public.production_shift_context(uuid),public.configure_production_shift(uuid,text,text,time,time,uuid,boolean),
 private.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,text),
 public.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,text) to authenticated;
