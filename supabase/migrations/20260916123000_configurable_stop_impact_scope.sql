-- Clarification: engineers choose whole-line, downstream-only, or no line impact.
alter table public.work_centers add column impact_scope text not null default 'downstream' check(impact_scope in ('whole_line','downstream','none'));
alter table public.downtime_events add column impact_scope_at_start text;
create or replace function private.save_line_layout(f uuid,version integer,layout jsonb) returns void language plpgsql security definer set search_path='' as $$declare x record;begin
 perform private.require_permission(f,'lines','edit');perform private.require_permission(f,'centers','edit');
 perform pg_advisory_xact_lock(hashtextextended(f::text||':structure',0));
 perform 1 from public.factories where id=f and structure_version=version for update;if not found then raise exception 'layout_conflict';end if;
 if jsonb_typeof(layout)<>'array' or jsonb_array_length(layout)<>(select count(*) from public.work_centers where factory_id=f and not archived) or (select count(distinct value->>'id') from jsonb_array_elements(layout))<>jsonb_array_length(layout) then raise exception 'invalid_layout';end if;
 for x in select * from jsonb_to_recordset(layout) as x(id uuid,line_id uuid,position integer,dependency_mode text,buffer_minutes integer,impact_scope text) loop
 if not exists(select 1 from public.work_centers where id=x.id and factory_id=f and not archived) or (x.line_id is not null and not exists(select 1 from public.production_lines where id=x.line_id and factory_id=f and not archived)) or x.position<0 then raise exception 'invalid_layout';end if;
 update public.work_centers set line_id=x.line_id,position=x.position,dependency_mode=case when x.line_id is null then 'independent' else x.dependency_mode end,buffer_minutes=x.buffer_minutes,impact_scope=coalesce(x.impact_scope,'downstream'),updated_at=now() where id=x.id;
 end loop;
 update public.factories set structure_version=structure_version+1 where id=f;
 end$$;
create or replace function private.capture_stop_context() returns trigger language plpgsql security definer set search_path='' as $$declare w public.work_centers;begin
 select * into w from public.work_centers where id=new.work_center_id;
 new.line_id:=w.line_id;new.order_id:=w.order_id;new.impact_scope_at_start:=w.impact_scope;new.blocking_at_start:=w.dependency_mode in ('blocking','buffer') and w.impact_scope<>'none';new.buffer_minutes_at_start:=case when w.dependency_mode='buffer' then w.buffer_minutes else 0 end;new.rate_at_start:=w.production_speed;return new;end$$;
