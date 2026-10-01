-- Unfinished stock is separate from legacy gross/good/scrap counters.
alter table public.production_entries
 add column unfinished_quantity numeric,
 add column effective_unfinished numeric,
 add column remaining_work text,
 add column effective_remaining_work text,
 add column input_lot_id uuid,
 add column input_quantity numeric;
alter table public.production_entry_corrections
 add column previous_unfinished numeric,
 add column corrected_unfinished numeric,
 add column previous_remaining_work text,
 add column corrected_remaining_work text;
alter table public.production_entries drop constraint production_entries_produced_check;
alter table public.production_entries add constraint entry_physical_output check
 (produced>=0 and produced+coalesce(unfinished_quantity,0)>0);
alter table public.production_entries add constraint entry_unfinished_valid check
 (unfinished_quantity is null or (unfinished_quantity>=0 and effective_unfinished>=0
 and (unfinished_quantity=0 or length(trim(remaining_work)) between 3 and 2000)
 and (effective_unfinished=0 or length(trim(effective_remaining_work)) between 3 and 2000)));

create table public.unfinished_lots(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories,
 source_entry_id uuid not null,quantity_created numeric not null check(quantity_created>=0),
 quantity_available numeric not null check(quantity_available>=0 and quantity_available<=quantity_created),
 remaining_work text not null check(length(trim(remaining_work)) between 3 and 2000),
 created_at timestamptz not null,created_by uuid not null references auth.users,
 unique(factory_id,id),unique(factory_id,source_entry_id),
 foreign key(factory_id,source_entry_id) references public.production_entries(factory_id,id)
);
alter table public.production_entries add foreign key(factory_id,input_lot_id) references public.unfinished_lots(factory_id,id);
-- An operation belongs to the lot/source item, never to a second normal line job.
-- It is assigned and recorded atomically, without reservations or scheduling changes.
create table public.unfinished_operations(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null,lot_id uuid not null,
 entry_id uuid not null,quantity numeric not null check(quantity>0),remaining_work text not null,
 line_id uuid,work_center_id uuid,created_at timestamptz not null,created_by uuid not null references auth.users,
 unique(factory_id,entry_id),foreign key(factory_id,lot_id) references public.unfinished_lots(factory_id,id),
 foreign key(factory_id,entry_id) references public.production_entries(factory_id,id),
 foreign key(factory_id,line_id) references public.production_lines(factory_id,id),
 foreign key(factory_id,work_center_id) references public.work_centers(factory_id,id),
 check((line_id is null)<>(work_center_id is null))
);
create table public.unfinished_movements(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null,lot_id uuid not null,
 entry_id uuid not null,correction_id uuid,kind text not null check(kind in ('created','consumed','corrected')),
 quantity numeric not null,created_at timestamptz not null default clock_timestamp(),created_by uuid not null references auth.users,
 foreign key(factory_id,lot_id) references public.unfinished_lots(factory_id,id),
 foreign key(factory_id,entry_id) references public.production_entries(factory_id,id),
 foreign key(correction_id) references public.production_entry_corrections(id)
);
create index on public.unfinished_lots(factory_id,created_at desc,id);
create index on public.unfinished_movements(factory_id,lot_id,created_at,id);
do $$declare tab text;begin
 foreach tab in array array['unfinished_lots','unfinished_operations','unfinished_movements'] loop
 execute format('alter table public.%I enable row level security',tab);
 execute format('revoke all on public.%I from anon,authenticated',tab);
 execute format('grant select on public.%I to authenticated',tab);
 execute format('create policy scoped_read on public.%I for select to authenticated using(private.has_permission(factory_id,''orders'',''view''))',tab);
 execute format('create trigger audit_insert after insert on public.%I for each row execute function private.audit_change()',tab);
 end loop;
end$$;

-- Same factory/product/unit capability, real availability, no borrowed machine bypass.
create function private.unfinished_destinations(f uuid,i uuid)
returns table(unit_kind text,unit_id uuid,item_id uuid) language sql stable security definer set search_path='' as $$
 select 'line',l.id,o.id from public.production_lines l join public.production_orders o on o.factory_id=l.factory_id and o.id=i
 where l.factory_id=f and not l.archived and l.paused_at is null and o.unit in ('meter','piece')
 and o.status in ('active','completed')
 and not exists(select 1 from public.production_orders busy where busy.factory_id=f and busy.line_id=l.id and busy.status='active' and busy.id<>i)
 and exists(select 1 from public.work_centers c join public.work_center_capabilities cap on cap.factory_id=c.factory_id and cap.work_center_id=c.id
 where c.factory_id=f and c.line_id=l.id and not c.archived and c.dependency_mode<>'independent' and c.status in ('idle','running')
 and not exists(select 1 from public.production_transfers tr where tr.factory_id=f and tr.ended_at is null and c.id in(tr.original_id,tr.alternative_id))
 and cap.product_id=o.product_id and cap.rate_unit=o.unit and cap.rate>0)
 union all
 select 'machine',c.id,o.id from public.work_centers c join public.production_orders o on o.factory_id=c.factory_id and o.id=i
 where c.factory_id=f and not c.archived and c.line_id is null and c.dependency_mode='independent'
 and c.status in ('idle','running') and o.status in ('active','completed') and o.unit in ('meter','piece')
 and (private.execution_center_order(f,c.id,c.line_id,c.order_id) is null or private.execution_center_order(f,c.id,c.line_id,c.order_id)=i)
 and not exists(select 1 from public.production_transfers tr where tr.factory_id=f and tr.ended_at is null and c.id in(tr.original_id,tr.alternative_id))
 and exists(select 1 from public.work_center_capabilities cap where cap.factory_id=f and cap.work_center_id=c.id and cap.product_id=o.product_id and cap.rate_unit=o.unit and cap.rate>0);
$$;
revoke all on function private.unfinished_destinations(uuid,uuid) from public,anon,authenticated;

create function public.unfinished_inventory(factory uuid,include_consumed boolean default false,page integer default 1,lot_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 perform private.require_permission(factory,'orders','view');
 if page is null or page<1 or page>1000000 then raise exception 'history_invalid';end if;
 with lots as materialized(
 select lot.*,e.order_id as item_id,e.input_lot_id as parent_lot_id,e.unit,e.line_id,e.work_center_id,o.product_id,
 r.code as request_code,o.code as item_code,p.name as product_name,p.name_ar as product_name_ar,
 coalesce(l.name,c.name) as origin_name,coalesce(l.name_ar,c.name_ar) as origin_name_ar,
 (select coalesce(jsonb_agg(to_jsonb(d)),'[]') from private.unfinished_destinations(factory,e.order_id) d) as destinations,
 (select coalesce(jsonb_agg(to_jsonb(m) order by m.created_at,m.id),'[]') from public.unfinished_movements m where m.factory_id=factory and m.lot_id=lot.id) as movements
 from public.unfinished_lots lot join public.production_entries e on e.factory_id=lot.factory_id and e.id=lot.source_entry_id
 join public.production_orders o on o.factory_id=e.factory_id and o.id=e.order_id
 join public.products p on p.factory_id=o.factory_id and p.id=o.product_id
 left join public.production_requests r on r.factory_id=o.factory_id and r.id=o.request_id
 left join public.production_lines l on l.factory_id=e.factory_id and l.id=e.line_id
 left join public.work_centers c on c.factory_id=e.factory_id and c.id=e.work_center_id
 where lot.factory_id=factory and (lot_id is null or lot.id=lot_id) and (include_consumed or lot.quantity_available>0)),
 paged as(select * from lots order by created_at desc,id limit 50 offset (page-1)*50)
 select jsonb_build_object('total',(select count(*) from lots),'page',page,'rows',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id),'[]') from paged x)) into result;
 return result;
end$$;
revoke all on function public.unfinished_inventory(uuid,boolean,integer,uuid) from public,anon;
grant execute on function public.unfinished_inventory(uuid,boolean,integer,uuid) to authenticated;

create function public.production_history_values(factory uuid,field text,search text default '',page integer default 1)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 perform private.require_permission(factory,'orders','view');
 if field not in ('request','product','unit','technician','shift') or page is null or page<1 or page>1000000 or length(coalesce(search,''))>120 then raise exception 'history_invalid';end if;
 with value_rows as materialized(
 select r.id::text as id,r.code as name,r.code as name_ar,false as archived from public.production_requests r where r.factory_id=factory and field='request'
 union all select p.id::text,p.name,p.name_ar,p.archived from public.products p where p.factory_id=factory and field='product'
 union all select 'line:'||l.id,l.name,l.name_ar,l.archived from public.production_lines l where l.factory_id=factory and field='unit'
 union all select 'machine:'||c.id,c.name,c.name_ar,c.archived from public.work_centers c where c.factory_id=factory and field='unit' and (c.line_id is null or exists(select 1 from public.production_entries e where e.factory_id=factory and e.work_center_id=c.id))
 union all select m.id::text,m.display_name,m.display_name,false from public.memberships m where m.factory_id=factory and field='technician'
 union all select s.id::text,s.name,s.name_ar,s.archived from public.production_shifts s where s.factory_id=factory and field='shift'),
 matching as materialized(select * from value_rows where strpos(lower(coalesce(name,'')||' '||coalesce(name_ar,'')),lower(coalesce(search,'')))>0),
 paged as(select * from matching order by name,id limit 50 offset (page-1)*50)
 select jsonb_build_object('total',(select count(*) from matching),'rows',(select coalesce(jsonb_agg(to_jsonb(x) order by x.name,x.id),'[]') from paged x)) into result;
 return result;
end$$;
revoke all on function public.production_history_values(uuid,text,text,integer) from public,anon;
grant execute on function public.production_history_values(uuid,text,text,integer) to authenticated;
-- Retain the existing reader contract, with bounded initial options.
create or replace function public.production_history_options(factory uuid) returns jsonb
language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(factory,'orders','view');
 return jsonb_build_object('requests',public.production_history_values(factory,'request')->'rows',
 'products',public.production_history_values(factory,'product')->'rows','units',public.production_history_values(factory,'unit')->'rows',
 'technicians',public.production_history_values(factory,'technician')->'rows','shifts',public.production_history_values(factory,'shift')->'rows');
end$$;

-- Replace public signatures; old private helpers cannot bypass the extended ledger.
drop function public.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,text);
drop function public.correct_production_entry(uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,boolean);
do $$declare fn record;begin
 for fn in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname in ('record_production','correct_production') loop
 execute format('revoke all on function %s from authenticated',fn.signature);end loop;
end$$;
create function private.record_production(f uuid,kind text,u uuid,i uuid,technician uuid,good numeric,scrap numeric,
 n text,confirmed boolean,r uuid,shift uuid,override_reason text,unfinished numeric,work_note text,input_lot uuid,consumed numeric)
returns uuid language plpgsql security definer set search_path='' as $$
declare job public.production_orders;previous public.production_entries;result uuid;total numeric;lot public.unfinished_lots;new_lot uuid;
 at_time timestamptz;automatic uuid;selected uuid;mode text;why text:=nullif(trim(override_reason),'');
begin
 perform private.require_permission(f,'orders','edit');
 perform private.require_permission(f,'orders','view');
 if r is null or technician is null or good is null or scrap is null or good<0 or scrap<0 or good+scrap+coalesce(unfinished,0)<=0
   or good::text in ('NaN','Infinity','-Infinity') or scrap::text in ('NaN','Infinity','-Infinity')
   or length(coalesce(n,''))>2000 then raise exception 'recording_invalid_quantity';end if;
 if unfinished is null or unfinished<0 or unfinished::text in ('NaN','Infinity','-Infinity')
 or consumed is null or consumed<0 or consumed::text in ('NaN','Infinity','-Infinity')
 or (unfinished>0 and length(trim(coalesce(work_note,''))) not between 3 and 2000)
 or (input_lot is null and consumed<>0) or (input_lot is not null and consumed<=0)
 then raise exception 'unfinished_invalid';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(f::text||':structure',0));
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(f::text||r::text,0));
 select * into previous from public.production_entries e where e.factory_id=f and e.request_id=r;
 if found then
   if previous.recording_version<>2 or previous.order_id<>i or previous.technician_id<>technician
     or previous.line_id is distinct from (case when kind='line' then u end)
     or previous.work_center_id is distinct from (case when kind='machine' then u end)
     or coalesce(previous.unfinished_quantity,0)<>unfinished or coalesce(previous.remaining_work,'')<>trim(coalesce(work_note,''))
     or previous.input_lot_id is distinct from input_lot or coalesce(previous.input_quantity,0)<>consumed
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
 if not found then raise exception 'recording_invalid_unit';end if;
 if input_lot is null then
   if not exists(select 1 from private.production_recording_units(f) x where x.unit_kind=kind and x.unit_id=u and x.item_id=i) then raise exception 'recording_invalid_unit';end if;
 else
   select * into lot from public.unfinished_lots x where x.factory_id=f and x.id=input_lot for update;
   if not found or not exists(select 1 from public.production_entries src where src.factory_id=f and src.id=lot.source_entry_id and src.order_id=i and src.unit=job.unit)
   then raise exception 'unfinished_invalid_lot';end if;
   if lot.quantity_available<consumed then raise exception 'unfinished_insufficient';end if;
   if consumed<>good+scrap+unfinished then raise exception 'unfinished_conservation';end if;
   if not exists(select 1 from private.unfinished_destinations(f,i) x where x.unit_kind=kind and x.unit_id=u) then raise exception 'recording_invalid_unit';end if;
 end if;
 if not exists(select 1 from public.memberships m where m.factory_id=f and m.id=technician and m.status='approved')
   then raise exception 'invalid_operator';end if;
 total:=job.good_quantity+good;
 if total>job.target_quantity and not coalesce(confirmed,false) then raise exception 'recording_overproduction_confirmation';end if;
 insert into public.production_entries(factory_id,order_id,line_id,work_center_id,technician_id,unit,recording_version,
   produced,rejected,good_quantity,scrap_quantity,effective_good,effective_scrap,notes,created_by,created_at,request_id,
   running_good,remaining_quantity,overproduction_confirmed,shift_id,original_shift_id,
   automatic_shift_id,requested_shift_id,shift_assignment_mode,shift_override_reason,shift_override_by,shift_override_at,unfinished_quantity,effective_unfinished,remaining_work,effective_remaining_work,input_lot_id,input_quantity)
 values(f,i,case when kind='line' then u end,case when kind='machine' then u end,technician,job.unit,2,
   good+scrap,scrap,good,scrap,good,scrap,coalesce(n,''),auth.uid(),at_time,r,total,greatest(job.target_quantity-total,0),coalesce(confirmed,false),selected,selected,
   automatic,shift,mode,why,case when mode='manual' then auth.uid() end,case when mode='manual' then at_time end,unfinished,unfinished,trim(coalesce(work_note,'')),trim(coalesce(work_note,'')),input_lot,consumed)
 returning id into result;
 update public.production_orders set produced_quantity=produced_quantity+good+scrap,rejected_quantity=rejected_quantity+scrap where id=i;
 if input_lot is not null then
   update public.unfinished_lots set quantity_available=quantity_available-consumed where id=input_lot;
   insert into public.unfinished_operations(factory_id,lot_id,entry_id,quantity,remaining_work,line_id,work_center_id,created_at,created_by)
   values(f,input_lot,result,consumed,lot.remaining_work,case when kind='line' then u end,case when kind='machine' then u end,at_time,auth.uid());
   insert into public.unfinished_movements(factory_id,lot_id,entry_id,kind,quantity,created_at,created_by)
   values(f,input_lot,result,'consumed',-consumed,at_time,auth.uid());
 end if;
 if unfinished>0 then
   insert into public.unfinished_lots(factory_id,source_entry_id,quantity_created,quantity_available,remaining_work,created_at,created_by)
   values(f,result,unfinished,unfinished,trim(work_note),at_time,auth.uid()) returning id into new_lot;
   insert into public.unfinished_movements(factory_id,lot_id,entry_id,kind,quantity,created_at,created_by)
   values(f,new_lot,result,'created',unfinished,at_time,auth.uid());
 end if;
 return result;
end$$;

create function public.record_production(factory uuid,unit_kind text,production_unit uuid,item uuid,technician uuid,
 good numeric,scrap numeric,notes text default '',confirm_overproduction boolean default false,
 request_id uuid default gen_random_uuid(),shift uuid default null,shift_override_reason text default null,unfinished numeric default 0,remaining_work text default '',input_lot uuid default null,input_quantity numeric default 0)
returns uuid language sql security invoker set search_path='' as $$
 select private.record_production(factory,unit_kind,production_unit,item,technician,good,scrap,notes,confirm_overproduction,request_id,shift,shift_override_reason,unfinished,remaining_work,input_lot,input_quantity)
$$;

create function private.correct_production(f uuid,e uuid,good numeric,scrap numeric,reason text,confirmed boolean,r uuid,shift uuid,change_shift boolean,unfinished numeric,work_note text)
returns uuid language plpgsql security definer set search_path='' as $$
declare original public.production_entries;job public.production_orders;previous public.production_entry_corrections;result uuid;total numeric;new_shift uuid;lot public.unfinished_lots;delta numeric;new_lot uuid;
begin
 perform private.require_permission(f,'orders','edit');
 perform private.require_permission(f,'orders','view');
 if r is null or good is null or scrap is null or good<0 or scrap<0
   or good::text in ('NaN','Infinity','-Infinity') or scrap::text in ('NaN','Infinity','-Infinity')
   or length(trim(coalesce(reason,''))) not between 3 and 2000 then raise exception 'recording_correction_reason';end if;
 if unfinished is not null and (unfinished<0 or unfinished::text in ('NaN','Infinity','-Infinity') or (unfinished>0 and length(trim(coalesce(work_note,''))) not between 3 and 2000)) then raise exception 'unfinished_invalid';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(f::text||':structure',0));
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(f::text||r::text,0));
 select * into previous from public.production_entry_corrections c where c.factory_id=f and c.request_id=r;
 if found then
   if previous.entry_id<>e or previous.corrected_good<>good or previous.corrected_scrap<>scrap or previous.reason<>reason
     or (unfinished is not null and coalesce(previous.corrected_unfinished,0)<>unfinished)
     or (work_note is not null and previous.corrected_remaining_work is distinct from trim(work_note))
     or previous.shift_changed is distinct from change_shift or (change_shift and previous.corrected_shift_id is distinct from shift) or previous.created_by<>auth.uid() or previous.overproduction_confirmed<>coalesce(confirmed,false) then raise exception 'request_conflict';end if;
   return previous.id;
 end if;
 select * into original from public.production_entries x where x.factory_id=f and x.id=e;
 if not found then raise exception 'invalid_order';end if;
 select * into job from public.production_orders o where o.factory_id=f and o.id=original.order_id for update;
 select * into original from public.production_entries x where x.factory_id=f and x.id=e for update;
 unfinished:=coalesce(unfinished,original.effective_unfinished,0);
 work_note:=coalesce(trim(work_note),original.effective_remaining_work,'');
 if unfinished>0 and (length(work_note) not between 3 and 2000 or original.unit not in ('meter','piece') or original.unit is null) then raise exception 'unfinished_invalid';end if;
 if original.input_lot_id is not null and good+scrap+unfinished<>original.input_quantity then raise exception 'unfinished_conservation';end if;
 select * into lot from public.unfinished_lots x where x.factory_id=f and x.source_entry_id=e for update;
 delta:=unfinished-coalesce(original.effective_unfinished,0);
 if lot.id is not null and lot.quantity_available+delta<0 then raise exception 'unfinished_already_consumed';end if;
 new_shift:=case when change_shift then shift else original.shift_id end;
 if change_shift and new_shift is distinct from original.shift_id then perform private.validate_production_shift(f,new_shift);end if;
 total:=job.good_quantity-original.effective_good+good;
 if total>job.target_quantity and not coalesce(confirmed,false) then raise exception 'recording_overproduction_confirmation';end if;
 insert into public.production_entry_corrections(factory_id,entry_id,previous_good,previous_scrap,corrected_good,corrected_scrap,reason,created_by,request_id,overproduction_confirmed,previous_shift_id,corrected_shift_id,shift_changed,previous_unfinished,corrected_unfinished,previous_remaining_work,corrected_remaining_work)
 values(f,e,original.effective_good,original.effective_scrap,good,scrap,reason,auth.uid(),r,coalesce(confirmed,false),original.shift_id,new_shift,coalesce(change_shift,false),coalesce(original.effective_unfinished,0),unfinished,original.effective_remaining_work,work_note) returning id into result;
 update public.production_orders set produced_quantity=produced_quantity-original.effective_good-original.effective_scrap+good+scrap,
   rejected_quantity=rejected_quantity-original.effective_scrap+scrap where id=job.id;
 update public.production_entries set effective_good=good,effective_scrap=scrap,shift_id=new_shift,effective_unfinished=unfinished,effective_remaining_work=work_note where id=e;
 if lot.id is null and unfinished>0 then
   insert into public.unfinished_lots(factory_id,source_entry_id,quantity_created,quantity_available,remaining_work,created_at,created_by)
   values(f,e,unfinished,unfinished,work_note,clock_timestamp(),auth.uid()) returning id into new_lot;
 elsif lot.id is not null then
   new_lot:=lot.id;
   update public.unfinished_lots set quantity_created=quantity_created+delta,quantity_available=quantity_available+delta,
   remaining_work=case when unfinished>0 then work_note else remaining_work end where id=lot.id;
 end if;
 if new_lot is not null and delta<>0 then
   insert into public.unfinished_movements(factory_id,lot_id,entry_id,correction_id,kind,quantity,created_by)
   values(f,new_lot,e,result,'corrected',delta,auth.uid());
 end if;
 return result;
end$$;
create function public.correct_production_entry(factory uuid,entry uuid,good numeric,scrap numeric,reason text,
 confirm_overproduction boolean default false,request_id uuid default gen_random_uuid(),shift uuid default null,change_shift boolean default false,unfinished numeric default null,remaining_work text default null)
returns uuid language sql security invoker set search_path='' as $$
 select private.correct_production(factory,entry,good,scrap,reason,confirm_overproduction,request_id,shift,change_shift,unfinished,remaining_work)
$$;
revoke all on function private.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,text,numeric,text,uuid,numeric),public.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,text,numeric,text,uuid,numeric),private.correct_production(uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,boolean,numeric,text),public.correct_production_entry(uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,boolean,numeric,text) from public,anon;
grant execute on function private.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,text,numeric,text,uuid,numeric),public.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,text,numeric,text,uuid,numeric),private.correct_production(uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,boolean,numeric,text),public.correct_production_entry(uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,boolean,numeric,text) to authenticated;

create function private.history_values_match(actual text,selection text) returns boolean language sql immutable set search_path='' as $$
 select coalesce(selection,'')='' or coalesce(actual,'unknown')=any(string_to_array(selection,','));
$$;
create function private.history_number_match(value numeric,op text,minimum text,maximum text)
returns boolean language plpgsql immutable set search_path='' as $$begin
 if coalesce(op,'')='' then return true;end if;
 if op not in ('eq','gte','lte','between') or minimum is null or minimum='' or minimum::numeric<0 or minimum::numeric::text in ('NaN','Infinity','-Infinity')
 or (op='between' and (maximum is null or maximum='' or maximum::numeric<minimum::numeric or maximum::numeric::text in ('NaN','Infinity','-Infinity'))) then raise exception 'history_invalid';end if;
 return case op when 'eq' then value=minimum::numeric when 'gte' then value>=minimum::numeric when 'lte' then value<=minimum::numeric else value between minimum::numeric and maximum::numeric end;
end$$;
revoke all on function private.history_values_match(text,text),private.history_number_match(numeric,text,text,text) from public,anon,authenticated;
-- Separate request retry identity from the parent Production Request. Untyped historical output is not aggregated.
create or replace function public.production_history(factory uuid,filters jsonb default '{}',
 sort_key text default 'date',sort_direction text default 'desc',page integer default 1)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; zone text;metric text; begin
 perform private.require_permission(factory,'orders','view');
 if sort_key not in ('date','good','scrap','unfinished','unit','technician','shift') or sort_direction not in ('asc','desc')
 or page is null or page<1 or page>1000000 or jsonb_typeof(filters)<>'object' then raise exception 'history_invalid';end if;
 if filters is null or jsonb_typeof(filters)<>'object' or length(filters::text)>12000 then raise exception 'history_invalid';end if;
 for metric in select unnest(array['good','scrap','unfinished']) loop
   perform private.history_number_match(0,filters->>(metric||'_op'),filters->>(metric||'_min'),filters->>(metric||'_max'));
   if nullif(filters->>(metric||'_op'),'') is not null and coalesce(filters->>'measurement_unit','') not in ('meter','piece') then raise exception 'history_unit_required';end if;
 end loop;
 if nullif(filters->>'from','') is not null and nullif(filters->>'to','') is not null and (filters->>'from')::date>(filters->>'to')::date then raise exception 'history_invalid';end if;
 if coalesce(filters->>'scrap_metric','quantity') not in ('quantity','percentage') or coalesce(filters->>'scrap_scope','row') not in ('row','shift') then raise exception 'history_invalid';end if;
 select timezone into zone from public.factories where id=factory;
 with base as materialized (
 select e.*,100*e.effective_scrap/nullif(e.effective_good+e.effective_scrap+coalesce(e.effective_unfinished,0),0) as scrap_percentage,o.request_id as production_request_id,o.product_id,r.code as request_code,o.code as item_code,
 p.name as product_name,p.name_ar as product_name_ar,
 coalesce(l.name,c.name) as unit_name,coalesce(l.name_ar,c.name_ar) as unit_name_ar,
 case when e.line_id is not null then 'line:'||e.line_id else 'machine:'||e.work_center_id end as unit_key,
 tech.display_name as technician_name,actor.display_name as submitter_name,
 sh.name as shift_name,sh.name_ar as shift_name_ar,
 to_jsonb(o) as history_item,
 exists(select 1 from public.production_entry_corrections x where x.factory_id=factory and x.entry_id=e.id) as corrected
 from public.production_entries e join public.production_orders o on o.id=e.order_id and o.factory_id=e.factory_id
 left join public.production_requests r on r.id=o.request_id and r.factory_id=e.factory_id
 left join public.products p on p.id=o.product_id and p.factory_id=e.factory_id
 left join public.production_lines l on l.id=e.line_id and l.factory_id=e.factory_id
 left join public.work_centers c on c.id=e.work_center_id and c.factory_id=e.factory_id
 left join public.memberships tech on tech.id=e.technician_id and tech.factory_id=e.factory_id
 left join public.memberships actor on actor.user_id=e.created_by and actor.factory_id=e.factory_id
 left join public.production_shifts sh on sh.id=e.shift_id and sh.factory_id=e.factory_id
 where e.factory_id=factory),
 selected as materialized (select * from base b where
 private.history_values_match(b.production_request_id::text,filters->>'request')
 and private.history_values_match(b.product_id::text,filters->>'product')
 and private.history_values_match(b.technician_id::text,filters->>'technician')
 and private.history_values_match(b.unit_key,filters->>'unit')
 and private.history_values_match(b.shift_id::text,filters->>'shift')
 and private.history_values_match(case when b.corrected then 'yes' else 'no' end,nullif(filters->>'corrected','all'))
 and (nullif(filters->>'from','') is null or b.created_at>=((filters->>'from')::date::timestamp at time zone zone))
 and (nullif(filters->>'to','') is null or b.created_at<(((filters->>'to')::date+1)::timestamp at time zone zone))
 and (nullif(filters->>'measurement_unit','') is null or b.unit=filters->>'measurement_unit')
 and private.history_number_match(b.effective_good,filters->>'good_op',filters->>'good_min',filters->>'good_max')
 and private.history_number_match(coalesce(b.effective_unfinished,0),filters->>'unfinished_op',filters->>'unfinished_min',filters->>'unfinished_max')
 and (coalesce(filters->>'scrap','all')<>'has' or b.effective_scrap>0)
 and (nullif(filters->>'minimum_scrap','') is null or b.effective_scrap>=(filters->>'minimum_scrap')::numeric)),
 scoped as materialized (select selected.*,
 100*sum(effective_scrap) over(partition by shift_id,unit)/nullif(sum(effective_good+effective_scrap+coalesce(effective_unfinished,0)) over(partition by shift_id,unit),0) as shift_scrap_percentage
 from selected),
 filtered as materialized(select * from scoped where private.history_number_match(
 case when filters->>'scrap_metric'='percentage' then case when filters->>'scrap_scope'='shift' then shift_scrap_percentage else scrap_percentage end else effective_scrap end,
 filters->>'scrap_op',filters->>'scrap_min',filters->>'scrap_max')),
 ranked as (select *,row_number() over(order by
 case when sort_key='date' and sort_direction='asc' then created_at end asc,
 case when sort_key='date' and sort_direction='desc' then created_at end desc,
 case when sort_key='good' and sort_direction='asc' then effective_good end asc,
 case when sort_key='good' and sort_direction='desc' then effective_good end desc,
 case when sort_key='scrap' and sort_direction='asc' then effective_scrap end asc,
 case when sort_key='scrap' and sort_direction='desc' then effective_scrap end desc,
 case when sort_key='unfinished' and sort_direction='asc' then coalesce(effective_unfinished,0) end asc,
 case when sort_key='unfinished' and sort_direction='desc' then coalesce(effective_unfinished,0) end desc,
 case when sort_key='unit' and sort_direction='asc' then unit_name end asc,
 case when sort_key='unit' and sort_direction='desc' then unit_name end desc,
 case when sort_key='technician' and sort_direction='asc' then technician_name end asc,
 case when sort_key='technician' and sort_direction='desc' then technician_name end desc,
 case when sort_key='shift' and sort_direction='asc' then shift_name end asc,
 case when sort_key='shift' and sort_direction='desc' then shift_name end desc,
 created_at desc,id) as position from filtered),
 totals as (select coalesce(unit,'unknown') as measurement_unit,count(*) as records,
 sum(effective_good) as good,sum(effective_scrap) as scrap,sum(coalesce(effective_unfinished,0)) as unfinished,
 100*sum(effective_scrap)/nullif(sum(effective_good+effective_scrap+coalesce(effective_unfinished,0)),0) as scrap_percentage from filtered where unit in ('meter','piece') group by coalesce(unit,'unknown')),
 shift_totals as (select shift_id,shift_name,shift_name_ar,unit as measurement_unit,count(*) as records,sum(effective_scrap) as scrap,
 sum(effective_good+effective_scrap+coalesce(effective_unfinished,0)) as output,
 100*sum(effective_scrap)/nullif(sum(effective_good+effective_scrap+coalesce(effective_unfinished,0)),0) as scrap_percentage
 from filtered where unit in ('meter','piece') group by shift_id,shift_name,shift_name_ar,unit),
 groups as (select coalesce(unit,'unknown') as measurement_unit,'unit' as kind,unit_key as identity,
 unit_name as name,unit_name_ar as name_ar,sum(effective_scrap) as scrap from filtered group by coalesce(unit,'unknown'),unit_key,unit_name,unit_name_ar
 union all select coalesce(unit,'unknown'),'shift',shift_id::text,shift_name,shift_name_ar,sum(effective_scrap) from filtered group by coalesce(unit,'unknown'),shift_id,shift_name,shift_name_ar
 union all select coalesce(unit,'unknown'),'technician',technician_id::text,technician_name,technician_name,sum(effective_scrap) from filtered group by coalesce(unit,'unknown'),technician_id,technician_name),
 winners as (select *,row_number() over(partition by measurement_unit,kind order by scrap desc,identity nulls last) as rank from groups)
 select jsonb_build_object('total',(select count(*) from filtered),'page',page,'page_size',50,
 'rows',(select coalesce(jsonb_agg(to_jsonb(x) order by x.position),'[]') from
 (select ranked.*,(select coalesce(jsonb_agg(to_jsonb(c) order by c.created_at,c.id),'[]') from
 public.production_entry_corrections c where c.factory_id=factory and c.entry_id=ranked.id) as corrections
 from ranked where position between (page-1)*50+1 and page*50) x),
 'unknown_unit_records',(select count(*) from filtered where unit is null or unit not in ('meter','piece')),
 'totals',(select coalesce(jsonb_agg(to_jsonb(t)),'[]') from totals t),
 'shift_totals',(select coalesce(jsonb_agg(to_jsonb(st)),'[]') from shift_totals st),
 'highest',(select coalesce(jsonb_agg(to_jsonb(w)),'[]') from winners w where rank=1 and scrap>0 and measurement_unit in ('meter','piece'))) into result;
 return result;
end$$;
