-- Protect production counts when a client retries after a network interruption.
alter table public.production_entries add column request_id uuid not null default gen_random_uuid();
create unique index production_entry_request on public.production_entries(factory_id,request_id);
drop function public.record_output(uuid,uuid,uuid,numeric,numeric,text);
create function private.record_output_once(f uuid,w uuid,o uuid,produced numeric,rejected numeric,n text,request_id uuid) returns void language plpgsql security definer set search_path='' as $$declare previous public.production_entries;begin
 perform private.require_permission(f,'orders','edit');
 if request_id is null then raise exception 'invalid_request';end if;
 perform pg_advisory_xact_lock(hashtextextended(f::text||request_id::text,0));
 select * into previous from public.production_entries e where e.factory_id=f and e.request_id=record_output_once.request_id;
 if found then
 if previous.work_center_id<>w or previous.order_id<>o or previous.produced<>produced or previous.rejected<>rejected or previous.notes<>coalesce(n,'') then raise exception 'request_conflict';end if;
 return;
 end if;
 perform 1 from public.work_centers where id=w and factory_id=f and not archived and order_id=o for update;
 if not found then raise exception 'invalid_order';end if;
 perform 1 from public.production_orders where id=o and factory_id=f and status='active' for update;
 if not found then raise exception 'invalid_order';end if;
 insert into public.production_entries(factory_id,order_id,work_center_id,produced,rejected,notes,created_by,request_id) values(f,o,w,produced,rejected,coalesce(n,''),auth.uid(),request_id);
 update public.production_orders set produced_quantity=produced_quantity+produced,rejected_quantity=rejected_quantity+rejected where id=o;
 end$$;
create function public.record_output(factory uuid,work_center uuid,production_order uuid,produced numeric,rejected numeric default 0,notes text default '',request_id uuid default gen_random_uuid()) returns void language sql security invoker set search_path='' as $$select private.record_output_once(factory,work_center,production_order,produced,rejected,notes,request_id)$$;
revoke execute on function private.record_output(uuid,uuid,uuid,numeric,numeric,text) from authenticated;
revoke all on function public.record_output(uuid,uuid,uuid,numeric,numeric,text,uuid),private.record_output_once(uuid,uuid,uuid,numeric,numeric,text,uuid) from public,anon;
grant execute on function public.record_output(uuid,uuid,uuid,numeric,numeric,text,uuid),private.record_output_once(uuid,uuid,uuid,numeric,numeric,text,uuid) to authenticated;

-- Validate text on the database boundary, including callers bypassing the application.
do $$declare t text;begin
 foreach t in array array['areas','production_lines','work_centers','products','roles','downtime_reasons'] loop
 execute format('alter table public.%I add constraint %I check(length(trim(name)) between 2 and 120 and length(name_ar)<=120)',t,t||'_valid_name');
 end loop;
 foreach t in array array['production_lines','work_centers','products','production_orders'] loop
 execute format('alter table public.%I add constraint %I check(length(trim(code)) between 1 and 40)',t,t||'_valid_code');
 end loop;
end$$;
alter table public.production_entries add constraint production_notes_length check(length(notes)<=2000);
alter table public.production_orders add constraint ordered_production_times check(start_time is null or expected_finish is null or expected_finish>=start_time);

-- Hierarchies are configured serially per factory, so concurrent updates cannot create cycles.
create function private.lock_structure() returns trigger language plpgsql set search_path='' as $$begin
 perform pg_advisory_xact_lock(hashtextextended(new.factory_id::text||':structure',0));
 return new;end$$;
create trigger a_lock_structure before insert or update on public.work_centers for each row execute function private.lock_structure();
create function private.validate_reason_parent() returns trigger language plpgsql set search_path='' as $$begin
 perform pg_advisory_xact_lock(hashtextextended(new.factory_id::text||':reasons',0));
 if new.parent_id=new.id or exists(with recursive parents as (select id,parent_id from public.downtime_reasons where id=new.parent_id and factory_id=new.factory_id union all select d.id,d.parent_id from public.downtime_reasons d join parents p on d.id=p.parent_id where d.factory_id=new.factory_id)select 1 from parents where id=new.id) then raise exception 'reason_cycle';end if;
 return new;end$$;
create trigger validate_reason_parent before insert or update on public.downtime_reasons for each row execute function private.validate_reason_parent();
revoke all on function private.lock_structure(),private.validate_reason_parent() from public,anon;
