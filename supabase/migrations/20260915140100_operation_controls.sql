-- Separate touch controls from engineering configuration; roles remain configurable data.
insert into public.permissions(module,action) select 'machine_status',a from unnest(array['view','create','edit','delete','approve','export']) a;
insert into public.role_permissions select r.factory_id,r.id,'machine_status','edit' from public.roles r where r.name='Technician / Operator';
delete from public.role_permissions p using public.roles r where p.role_id=r.id and r.name='Technician / Operator' and p.module='centers' and p.action='edit';
create or replace function private.change_status(f uuid,w uuid,s text,reason uuid,sub_reason uuid,n text,eta timestamptz,responsible uuid,alternative uuid,transferred boolean) returns void language plpgsql security definer set search_path='' as $$
 declare old_s text; down boolean; begin
 if not private.has_permission(f,'centers','edit') then perform private.require_permission(f,'machine_status','edit');end if;
 if length(coalesce(n,''))>2000 then raise exception 'invalid_notes';end if;
 if responsible is not null and not exists(select 1 from public.memberships where id=responsible and factory_id=f and status='approved') then raise exception 'invalid_responsible';end if;
 if alternative=w or (alternative is not null and not exists(select 1 from public.work_centers where id=alternative and factory_id=f and not archived)) then raise exception 'invalid_alternative';end if;
 select status into old_s from public.work_centers where id=w and factory_id=f and not archived for update;
 if not found then raise exception 'not_found'; end if;
 if old_s=s then raise exception 'status_unchanged'; end if;
 select is_downtime into down from public.machine_statuses where code=s;
 if not found then raise exception 'invalid_status'; end if;
 if down then
 if reason is null or not exists(select 1 from public.downtime_reasons where id=reason and factory_id=f and parent_id is null) then raise exception 'reason_required'; end if;
 if exists(select 1 from public.downtime_reasons where id=reason and requires_description) and length(trim(coalesce(n,'')))<3 then raise exception 'description_required'; end if;
 if sub_reason is not null and not exists(select 1 from public.downtime_reasons where id=sub_reason and parent_id=reason and factory_id=f) then raise exception 'invalid_sub_reason'; end if;
 if eta is not null and eta<now() then raise exception 'invalid_restart_time'; end if;
 if transferred and (alternative is null or alternative=w) then raise exception 'alternative_required'; end if;
 end if;
 update public.downtime_events set ended_at=now() where factory_id=f and work_center_id=w and ended_at is null;
 insert into public.status_events(factory_id,work_center_id,old_status,new_status,reason_id,notes,created_by) values(f,w,old_s,s,reason,coalesce(n,''),auth.uid());
 if down then insert into public.downtime_events(factory_id,work_center_id,reason_id,sub_reason_id,notes,expected_restart,responsible_id,alternative_id,transferred,created_by) values(f,w,reason,sub_reason,coalesce(n,''),eta,responsible,alternative,transferred,auth.uid()); end if;
 update public.work_centers set status=s,updated_at=now(),last_restart_time=case when s='running' then now() else last_restart_time end where id=w;
 end$$;
create or replace function private.create_factory(n text,tz text,industry text) returns uuid language plpgsql security definer set search_path='' as $$
 declare f uuid; r uuid; v text; begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'verify_email'; end if;
 if exists(select 1 from public.memberships where user_id=auth.uid()) then raise exception 'already_joined'; end if;
 if not exists(select 1 from pg_timezone_names where name=tz) then raise exception 'invalid_timezone'; end if;
 insert into public.factories(name,timezone,industry,created_by) values(n,tz,industry,auth.uid()) returning id into f;
 insert into private.join_codes values(f,'FAC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)));
 foreach v in array array['Factory Owner','Factory Manager','Production Engineer','Planning Engineer','Warehouse Manager','Sales Employee','Quality Engineer','Maintenance Engineer','Safety Officer','Production Supervisor','Technician / Operator','Platform Support Engineer','Custom Role'] loop
 insert into public.roles(factory_id,name) values(f,v) returning id into r;
 if v='Factory Owner' then insert into public.memberships(factory_id,user_id,display_name,role_id,is_owner,status) values(f,auth.uid(),split_part((select email from auth.users where id=auth.uid()),'@',1),r,true,'approved'); end if;
 if v='Factory Manager' then insert into public.role_permissions select f,r,module,action from public.permissions where module not in ('roles','support');
 elsif v in ('Production Engineer','Production Supervisor') then insert into public.role_permissions select f,r,module,action from public.permissions where (action='view' and module in ('dashboard','factory','lines','centers','orders','downtime','reports','employees')) or (action='edit' and module in ('centers','orders','downtime'));
 elsif v='Technician / Operator' then insert into public.role_permissions select f,r,module,action from public.permissions where (action='view' and module in ('dashboard','factory','lines','centers','orders','downtime')) or (action='edit' and module='machine_status'); end if;
 end loop;
 insert into public.downtime_reasons(factory_id,name,name_ar,requires_description)
 select f,x.en,x.ar,x.en='Other' from (values('Mechanical Failure','عطل ميكانيكي'),('Electrical Failure','عطل كهربائي'),('Material Shortage','نقص مواد'),('Operator Unavailable','عدم توفر المشغل'),('Tooling Problem','مشكلة في العِدد'),('Setup / Changeover','إعداد / تغيير المنتج'),('Quality Problem','مشكلة جودة'),('Waiting for Approval','انتظار الموافقة'),('Maintenance','صيانة'),('Cleaning','تنظيف'),('Power Failure','انقطاع الكهرباء'),('Production Planning Delay','تأخير تخطيط الإنتاج'),('Other','أخرى')) x(en,ar);
 return f;
 end$$;

create function private.translate_default_role() returns trigger language plpgsql set search_path='' as $$begin
 if new.name_ar='' then new.name_ar:=case new.name when 'Factory Owner' then 'مالك المصنع' when 'Factory Manager' then 'مدير المصنع' when 'Production Engineer' then 'مهندس الإنتاج' when 'Planning Engineer' then 'مهندس التخطيط' when 'Warehouse Manager' then 'مدير المستودع' when 'Sales Employee' then 'موظف المبيعات' when 'Quality Engineer' then 'مهندس الجودة' when 'Maintenance Engineer' then 'مهندس الصيانة' when 'Safety Officer' then 'مسؤول السلامة' when 'Production Supervisor' then 'مشرف الإنتاج' when 'Technician / Operator' then 'فني / مشغل' when 'Platform Support Engineer' then 'مهندس دعم المنصة' when 'Custom Role' then 'دور مخصص' else '' end;end if;
 return new;end$$;
create trigger translate_default_role before insert on public.roles for each row execute function private.translate_default_role();

create table public.daily_targets(id uuid primary key default gen_random_uuid(),factory_id uuid not null,order_id uuid not null,day date not null,target numeric not null check(target>0),created_at timestamptz not null default now(),created_by uuid references auth.users,unique(factory_id,order_id,day),foreign key(factory_id,order_id) references public.production_orders(factory_id,id));
alter table public.daily_targets enable row level security;
grant select on public.daily_targets to authenticated;
create policy read_daily_targets on public.daily_targets for select to authenticated using(private.has_permission(factory_id,'orders','view'));
create trigger audit_daily_targets after insert or update on public.daily_targets for each row execute function private.audit_change();
create function private.set_daily_target(f uuid,o uuid,d date,q numeric) returns void language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(f,'orders','edit');
 if d is null or q is null then raise exception 'invalid_input';end if;
 insert into public.daily_targets(factory_id,order_id,day,target,created_by) values(f,o,d,q,auth.uid()) on conflict(factory_id,order_id,day) do update set target=excluded.target;
 end$$;
create function public.set_daily_target(factory uuid,production_order uuid,day date,target numeric) returns void language sql security invoker set search_path='' as $$select private.set_daily_target(factory,production_order,day,target)$$;

-- One scoped round trip, RLS still applies to every table. No privileged service key is used.
create function public.factory_snapshot(factory uuid default null) returns jsonb language plpgsql security invoker set search_path='' as $$
declare m jsonb;f uuid;fac jsonb;tab text;rows jsonb;data jsonb:='{}';limited text[]:='{}';begin
 select to_jsonb(x) into m from public.memberships x where user_id=auth.uid();
 f:=case when m->>'status'='approved' then (m->>'factory_id')::uuid else $1 end;
 if f is not null then
 perform private.require_permission(f,'factory','view');
 perform private.record_access(f,'READ');
 select to_jsonb(x) into fac from public.factories x where id=f;
 foreach tab in array array['areas','production_lines','work_centers','products','production_orders','downtime_reasons','status_events','downtime_events','memberships','roles','role_permissions','support_access','audit_logs','oee_observations','production_entries','operator_assignments','work_center_alternatives','daily_targets'] loop
 execute format('select coalesce(jsonb_agg(x),''[]'') from (select * from public.%I where factory_id=$1 %s limit 5000) x',tab,case when tab in ('status_events','audit_logs','production_entries','downtime_events') then 'order by created_at desc,id' else '' end) into rows using f;
 data:=data||jsonb_build_object(tab,rows);
 if jsonb_array_length(rows)=5000 then limited:=array_append(limited,tab);end if;
 end loop;
 data:=data||jsonb_build_object('machine_statuses',(select jsonb_agg(x) from public.machine_statuses x),'permissions',(select jsonb_agg(x) from public.permissions x));
 end if;
 return jsonb_build_object('factory',fac,'membership',m,'permissions',case when f is null then '{}'::text[] else public.access_matrix(f) end,'tables',data,'supportFactories',(select coalesce(jsonb_agg(x),'[]') from public.support_access x where user_id=auth.uid()),'truncatedTables',limited,'fetchedAt',now());
end$$;
revoke all on function private.translate_default_role(),private.set_daily_target(uuid,uuid,date,numeric),public.set_daily_target(uuid,uuid,date,numeric),public.factory_snapshot(uuid) from public,anon;
grant execute on function private.set_daily_target(uuid,uuid,date,numeric),public.set_daily_target(uuid,uuid,date,numeric),public.factory_snapshot(uuid) to authenticated;
revoke insert,update,delete,truncate,references,trigger on public.daily_targets from authenticated,anon;
-- Index referencing columns on future relationships as well as live modules.
do $$declare r record;begin
 for r in select distinct tc.table_name,kcu.column_name from information_schema.table_constraints tc join information_schema.key_column_usage kcu on tc.constraint_name=kcu.constraint_name and tc.table_schema=kcu.table_schema where tc.constraint_type='FOREIGN KEY' and tc.table_schema='public' loop
 execute format('create index if not exists %I on public.%I(%I)',left(r.table_name||'_'||r.column_name||'_idx',63),r.table_name,r.column_name);
 end loop;
end$$;
