-- Phase 1 improvement: additive person grants and explicitly scoped platform administration.
create table private.platform_admins(user_id uuid primary key references auth.users, enabled boolean not null default true, created_at timestamptz not null default now());
create table private.platform_scopes(user_id uuid references auth.users, factory_id uuid references public.factories, expires_at timestamptz not null, primary key(user_id,factory_id));
alter table private.platform_admins enable row level security;
alter table private.platform_scopes enable row level security;
-- Explicit development bootstrap only: no password, metadata-based elevation, or public promotion endpoint.
insert into private.platform_admins(user_id) select u.id from auth.users u join public.memberships m on m.user_id=u.id join public.factories f on f.id=m.factory_id where u.email='admin@nova.example.test' and f.is_demo and m.is_owner;
create function private.is_platform_admin() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from private.platform_admins where user_id=auth.uid() and enabled)$$;
create function private.platform_scope(f uuid) returns boolean language sql stable security definer set search_path='' as $$select private.is_platform_admin() and exists(select 1 from private.platform_scopes where user_id=auth.uid() and factory_id=f and expires_at>now())$$;
create table public.user_permissions(factory_id uuid not null references public.factories,user_id uuid not null references auth.users,module text not null,action text not null,created_at timestamptz not null default now(),created_by uuid references auth.users,primary key(factory_id,user_id,module,action),foreign key(module,action) references public.permissions);
-- Snapshot existing access once. Future job title/template edits do not change people's access.
insert into public.user_permissions(factory_id,user_id,module,action) select m.factory_id,m.user_id,p.module,p.action from public.memberships m join public.role_permissions p on p.role_id=m.role_id union select m.factory_id,m.user_id,p.module,p.action from public.memberships m cross join public.permissions p where m.is_owner union select s.factory_id,s.user_id,p.module,p.action from public.support_access s join public.role_permissions p on p.role_id=s.role_id on conflict do nothing;
create or replace function private.has_permission(f uuid,m text,a text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (private.platform_scope(f) or (exists(select 1 from public.user_permissions p where p.factory_id=f and p.user_id=auth.uid() and p.module=m and p.action=a) and (exists(select 1 from public.memberships u where u.factory_id=f and u.user_id=auth.uid() and u.status='approved') or exists(select 1 from public.support_access s where s.factory_id=f and s.user_id=auth.uid() and (s.mode='permanent' or (s.mode='temporary' and s.expires_at>now()))))));$$;
create or replace function private.is_owner(f uuid) returns boolean language sql stable security definer set search_path='' as $$select private.platform_scope(f) or exists(select 1 from public.memberships where factory_id=f and user_id=auth.uid() and status='approved' and is_owner)$$;
alter table public.user_permissions enable row level security;
create policy read_person_grants on public.user_permissions for select to authenticated using(private.has_permission(factory_id,'roles','view') or (user_id=auth.uid() and private.has_permission(factory_id,'factory','view')));
grant select on public.user_permissions to authenticated;
revoke insert,update,delete,truncate on public.user_permissions from authenticated,anon;
create trigger audit_person_grants after insert or delete on public.user_permissions for each row execute function private.audit_change();
create function private.set_user_permissions(f uuid,u uuid,grants jsonb) returns void language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(f,'roles','edit');
 if not exists(select 1 from public.memberships where factory_id=f and user_id=u and not is_owner) then raise exception 'invalid_member';end if;
 if jsonb_typeof(grants)<>'array' or jsonb_array_length(grants)>200 then raise exception 'invalid_input';end if;
 if exists(select 1 from jsonb_to_recordset(grants) x(module text,action text) where not private.has_permission(f,x.module,x.action)) then raise exception 'cannot_grant_higher_permissions';end if;
 perform pg_advisory_xact_lock(hashtextextended(f::text||u::text,0));
 delete from public.user_permissions where factory_id=f and user_id=u;
 insert into public.user_permissions(factory_id,user_id,module,action,created_by) select distinct f,u,x.module,x.action,auth.uid() from jsonb_to_recordset(grants) x(module text,action text);
 end$$;
create function public.set_user_permissions(factory uuid,person uuid,permissions jsonb) returns void language sql security invoker set search_path='' as $$select private.set_user_permissions(factory,person,permissions)$$;
-- Owners receive explicit grants at creation; approving employees does not silently apply job templates.
create function private.owner_grants() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.is_owner then insert into public.user_permissions(factory_id,user_id,module,action) select new.factory_id,new.user_id,module,action from public.permissions on conflict do nothing;end if;return new;end$$;
create trigger owner_grants after insert on public.memberships for each row execute function private.owner_grants();
-- Support access is an explicit grant action: snapshot the selected template at grant time.
create function private.support_grants() returns trigger language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from public.memberships where factory_id=new.factory_id and user_id=new.user_id) then
 delete from public.user_permissions where factory_id=new.factory_id and user_id=new.user_id;
 insert into public.user_permissions(factory_id,user_id,module,action,created_by) select new.factory_id,new.user_id,module,action,auth.uid() from public.role_permissions where role_id=new.role_id;
 end if;return new;end$$;
create trigger support_person_grants after insert or update on public.support_access for each row execute function private.support_grants();
create function private.open_platform_factory(f uuid) returns void language plpgsql security definer set search_path='' as $$begin
 if not private.is_platform_admin() then raise exception 'permission_denied' using errcode='42501';end if;
 insert into private.platform_scopes values(auth.uid(),f,now()+interval '30 minutes') on conflict(user_id,factory_id) do update set expires_at=excluded.expires_at;
 insert into public.audit_logs(factory_id,actor_id,action,entity,entity_id) values(f,auth.uid(),'PLATFORM_ACCESS','factories',f);
 end$$;
create function public.open_platform_factory(factory uuid) returns void language sql security invoker set search_path='' as $$select private.open_platform_factory(factory)$$;
create function private.platform_factories() returns jsonb language plpgsql security definer set search_path='' as $$begin
 if not private.is_platform_admin() then return '[]'::jsonb;end if;
 insert into public.audit_logs(factory_id,actor_id,action,entity,entity_id) select id,auth.uid(),'PLATFORM_LIST','factories',id from public.factories;
 return (select coalesce(jsonb_agg(x),'[]') from (select f.*, 'active' as status,(select count(*) from public.memberships where factory_id=f.id and status='approved') as users,(select count(*) from public.production_lines where factory_id=f.id and not archived) as lines,(select count(*) from public.work_centers where factory_id=f.id and not archived) as machines,(select max(created_at) from public.audit_logs where factory_id=f.id and action not in ('PLATFORM_LIST','PLATFORM_ACCESS','READ')) as last_activity from public.factories f order by name) x);
 end$$;
create or replace function private.create_factory(n text,tz text,industry text) returns uuid language plpgsql security definer set search_path='' as $$
 declare f uuid; r uuid; v text; begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'verify_email'; end if;
 if not private.is_platform_admin() and exists(select 1 from public.memberships where user_id=auth.uid()) then raise exception 'already_joined'; end if;
 if not exists(select 1 from pg_timezone_names where name=tz) then raise exception 'invalid_timezone'; end if;
 insert into public.factories(name,timezone,industry,created_by) values(n,tz,industry,auth.uid()) returning id into f;
 insert into private.join_codes values(f,'FAC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)));
 foreach v in array array['Factory Owner','Factory Manager','Production Engineer','Planning Engineer','Warehouse Manager','Sales Employee','Quality Engineer','Maintenance Engineer','Safety Officer','Production Supervisor','Technician / Operator','Platform Support Engineer','Custom Role'] loop
 insert into public.roles(factory_id,name) values(f,v) returning id into r;
 if v='Factory Owner' and not private.is_platform_admin() then insert into public.memberships(factory_id,user_id,display_name,role_id,is_owner,status) values(f,auth.uid(),split_part((select email from auth.users where id=auth.uid()),'@',1),r,true,'approved'); end if;
 if v='Factory Manager' then insert into public.role_permissions select f,r,module,action from public.permissions where module not in ('roles','support');
 elsif v in ('Production Engineer','Production Supervisor') then insert into public.role_permissions select f,r,module,action from public.permissions where (action='view' and module in ('dashboard','factory','lines','centers','orders','downtime','reports','employees')) or (action='edit' and module in ('centers','orders','downtime'));
 elsif v='Technician / Operator' then insert into public.role_permissions select f,r,module,action from public.permissions where (action='view' and module in ('dashboard','factory','lines','centers','orders','downtime')) or (action='edit' and module='machine_status'); end if;
 end loop;
 insert into public.downtime_reasons(factory_id,name,name_ar,requires_description)
 select f,x.en,x.ar,x.en='Other' from (values('Mechanical Failure','عطل ميكانيكي'),('Electrical Failure','عطل كهربائي'),('Material Shortage','نقص مواد'),('Operator Unavailable','عدم توفر المشغل'),('Tooling Problem','مشكلة في العِدد'),('Setup / Changeover','إعداد / تغيير المنتج'),('Quality Problem','مشكلة جودة'),('Waiting for Approval','انتظار الموافقة'),('Maintenance','صيانة'),('Cleaning','تنظيف'),('Power Failure','انقطاع الكهرباء'),('Production Planning Delay','تأخير تخطيط الإنتاج'),('Other','أخرى')) x(en,ar);
 if private.is_platform_admin() then perform private.open_platform_factory(f);end if;
 return f;
 end$$;


-- Operational topology is independent of historical events and machine identity.
alter table public.work_centers add column dependency_mode text not null default 'non_blocking' check(dependency_mode in ('blocking','non_blocking','independent','buffer')),
 add column buffer_minutes integer not null default 0 check(buffer_minutes between 0 and 10080);
alter table public.factories add column structure_version integer not null default 0,
 add column impact_blocking_weight numeric not null default 2 check(impact_blocking_weight>=1),
 add column impact_frequency_minutes numeric not null default 5 check(impact_frequency_minutes>=0);
alter table public.products add column stage text not null default 'finished' check(stage in ('raw','wip','semi_finished','finished'));
create table public.production_routing_steps(id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories,product_id uuid not null,position integer not null,kind text not null check(kind in ('line','work_center','warehouse','wip')),line_id uuid,work_center_id uuid,output_product_id uuid,created_at timestamptz not null default now(),foreign key(factory_id,product_id) references public.products(factory_id,id),foreign key(factory_id,output_product_id) references public.products(factory_id,id),foreign key(factory_id,line_id) references public.production_lines(factory_id,id),foreign key(factory_id,work_center_id) references public.work_centers(factory_id,id),unique(product_id,position),check((kind='line' and line_id is not null and work_center_id is null) or (kind='work_center' and work_center_id is not null and line_id is null) or (kind in ('warehouse','wip') and line_id is null and work_center_id is null)));
alter table public.downtime_events add column line_id uuid,add column order_id uuid,add column blocking_at_start boolean,add column rate_at_start numeric,add column buffer_minutes_at_start integer;
alter table public.downtime_events add foreign key(factory_id,line_id) references public.production_lines(factory_id,id),add foreign key(factory_id,order_id) references public.production_orders(factory_id,id);
-- Unknown historical impact remains unknown: do not invent past blocking/rate data.
create function private.capture_stop_context() returns trigger language plpgsql security definer set search_path='' as $$declare w public.work_centers;begin
 select * into w from public.work_centers where id=new.work_center_id;
 new.line_id:=w.line_id;new.order_id:=w.order_id;new.blocking_at_start:=w.dependency_mode in ('blocking','buffer');new.buffer_minutes_at_start:=case when w.dependency_mode='buffer' then w.buffer_minutes else 0 end;new.rate_at_start:=w.production_speed;return new;end$$;
create trigger capture_stop_context before insert on public.downtime_events for each row execute function private.capture_stop_context();
create table public.production_transfers(id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories,original_id uuid not null,alternative_id uuid not null,order_id uuid not null,downtime_id uuid not null,reason text not null check(length(trim(reason)) between 3 and 2000),created_at timestamptz not null default now(),created_by uuid not null references auth.users,original_returned_at timestamptz,ended_at timestamptz,check(original_id<>alternative_id),foreign key(factory_id,original_id) references public.work_centers(factory_id,id),foreign key(factory_id,alternative_id) references public.work_centers(factory_id,id),foreign key(factory_id,order_id) references public.production_orders(factory_id,id),foreign key(factory_id,downtime_id) references public.downtime_events(factory_id,id));
create unique index one_active_transfer on public.production_transfers(original_id) where ended_at is null;
create unique index one_active_transfer_target on public.production_transfers(alternative_id) where ended_at is null;
create function private.transfer_production(f uuid,w uuid,a uuid,n text) returns uuid language plpgsql security definer set search_path='' as $$declare o uuid;d uuid;i uuid;begin
 perform private.require_permission(f,'centers','edit');perform private.require_permission(f,'orders','edit');
 perform pg_advisory_xact_lock(hashtextextended(f::text||':structure',0));
 perform 1 from public.work_centers where factory_id=f and id in (w,a) order by id for update;
 select order_id into o from public.work_centers where id=w and factory_id=f and not archived and status='stopped';
 select id into d from public.downtime_events where work_center_id=w and factory_id=f and ended_at is null;
 if o is null or d is null or not exists(select 1 from public.production_orders where id=o and status='active') then raise exception 'invalid_order';end if;
 if not exists(select 1 from public.work_center_alternatives where factory_id=f and work_center_id=w and alternative_id=a) or not exists(select 1 from public.work_centers where id=a and factory_id=f and not archived and status='idle' and (order_id is null or order_id=o)) then raise exception 'invalid_alternative';end if;
 insert into public.production_transfers(factory_id,original_id,alternative_id,order_id,downtime_id,reason,created_by) values(f,w,a,o,d,n,auth.uid()) returning id into i;
 update public.work_centers set order_id=o where id=a;
 perform private.change_status(f,a,'running',null,null,n,null,null,null,false);
 update public.downtime_events set alternative_id=a,transferred=true where id=d;
 return i;end$$;
create function public.transfer_production(factory uuid,work_center uuid,alternative uuid,reason text) returns uuid language sql security invoker set search_path='' as $$select private.transfer_production(factory,work_center,alternative,reason)$$;
-- A resumed original closes the transfer; the alternative's real state is never silently overwritten.
create function private.finish_transfer() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.status='running' and old.status<>'running' then update public.production_transfers set original_returned_at=now(),ended_at=now() where original_id=new.id and ended_at is null;end if;return new;end$$;
create trigger finish_transfer after update of status on public.work_centers for each row execute function private.finish_transfer();
create function private.save_line_layout(f uuid,version integer,layout jsonb) returns void language plpgsql security definer set search_path='' as $$declare x record;begin
 perform private.require_permission(f,'lines','edit');perform private.require_permission(f,'centers','edit');
 perform pg_advisory_xact_lock(hashtextextended(f::text||':structure',0));
 perform 1 from public.factories where id=f and structure_version=version for update;if not found then raise exception 'layout_conflict';end if;
 if jsonb_typeof(layout)<>'array' or jsonb_array_length(layout)<>(select count(*) from public.work_centers where factory_id=f and not archived) or (select count(distinct value->>'id') from jsonb_array_elements(layout))<>jsonb_array_length(layout) then raise exception 'invalid_layout';end if;
 for x in select * from jsonb_to_recordset(layout) as x(id uuid,line_id uuid,position integer,dependency_mode text,buffer_minutes integer) loop
 if not exists(select 1 from public.work_centers where id=x.id and factory_id=f and not archived) or (x.line_id is not null and not exists(select 1 from public.production_lines where id=x.line_id and factory_id=f and not archived)) or x.position<0 then raise exception 'invalid_layout';end if;
 update public.work_centers set line_id=x.line_id,position=x.position,dependency_mode=case when x.line_id is null then 'independent' else x.dependency_mode end,buffer_minutes=x.buffer_minutes,updated_at=now() where id=x.id;
 end loop;
 update public.factories set structure_version=structure_version+1 where id=f;
 end$$;
create function public.save_line_layout(factory uuid,version integer,layout jsonb) returns void language sql security invoker set search_path='' as $$select private.save_line_layout(factory,version,layout)$$;
-- Keep legacy history readable, but stop accepting maintenance as a new operational state.
update public.work_centers set status='stopped' where status='maintenance';
create function private.simple_operational_state() returns trigger language plpgsql set search_path='' as $$begin if new.status='maintenance' then raise exception 'maintenance_is_stop_reason';end if;return new;end$$;
create trigger simple_operational_state before insert or update of status on public.work_centers for each row execute function private.simple_operational_state();
insert into public.downtime_reasons(factory_id,name,name_ar) select f.id,'Planned Maintenance','صيانة مخططة' from public.factories f where not exists(select 1 from public.downtime_reasons r where r.factory_id=f.id and r.name='Planned Maintenance');
-- Legacy transferred checkbox is no longer proof that an operational transfer occurred.
create or replace function private.change_status(f uuid,w uuid,s text,reason uuid,sub_reason uuid,n text,eta timestamptz,responsible uuid,alternative uuid,transferred boolean) returns void language plpgsql security definer set search_path='' as $$
 declare old_s text; down boolean; begin
 if transferred then raise exception 'use_transfer_command';end if;
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
create or replace function private.update_downtime(f uuid,i uuid,eta timestamptz,n text,responsible uuid,alternative uuid,transferred boolean) returns void language plpgsql security definer set search_path='' as $$begin
 if transferred then raise exception 'use_transfer_command';end if;
 if not private.has_permission(f,'downtime','edit') then perform private.require_permission(f,'machine_status','edit');end if;
 if eta is not null and eta<now() then raise exception 'invalid_restart_time';end if;
 if length(coalesce(n,''))>2000 then raise exception 'invalid_notes';end if;
 if responsible is not null and not exists(select 1 from public.memberships where id=responsible and factory_id=f and status='approved') then raise exception 'invalid_responsible';end if;
 if transferred and alternative is null then raise exception 'alternative_required';end if;
 if exists(select 1 from public.downtime_events d join public.downtime_reasons r on r.id=d.reason_id where d.id=i and d.factory_id=f and r.requires_description) and length(trim(coalesce(n,'')))<3 then raise exception 'description_required';end if;
 if alternative is not null and (not exists(select 1 from public.work_centers where id=alternative and factory_id=f and not archived) or exists(select 1 from public.downtime_events where id=i and work_center_id=alternative)) then raise exception 'invalid_alternative';end if;
 update public.downtime_events set expected_restart=eta,notes=coalesce(n,''),responsible_id=responsible,alternative_id=alternative where id=i and factory_id=f and ended_at is null;
 if not found then raise exception 'not_found';end if;
 end$$;

do $$declare t text;m text;begin
 foreach t in array array['production_transfers','production_routing_steps'] loop
 m:=case when t='production_transfers' then 'centers' else 'orders' end;
 execute format('alter table public.%I enable row level security',t);
 execute format('create policy scoped_read on public.%I for select to authenticated using(private.has_permission(factory_id,%L,''view''))',t,m);
 execute format('grant select on public.%I to authenticated',t);
 execute format('revoke insert,update,delete,truncate on public.%I from authenticated,anon',t);
 execute format('create trigger audit_record after insert or update or delete on public.%I for each row execute function private.audit_change()',t);
 execute format('create index on public.%I(factory_id)',t);
 end loop;end$$;
create or replace function public.factory_snapshot(factory uuid default null) returns jsonb language plpgsql security invoker set search_path='' as $$
declare m jsonb;f uuid;fac jsonb;tab text;rows jsonb;data jsonb:='{}';limited text[]:='{}';begin
 select to_jsonb(x) into m from public.memberships x where user_id=auth.uid();
 f:=case when private.is_platform_admin() then $1 when m->>'status'='approved' then (m->>'factory_id')::uuid else $1 end;
 if f is not null then
 perform private.require_permission(f,'factory','view');
 perform private.record_access(f,'READ');
 select to_jsonb(x) into fac from public.factories x where id=f;
 foreach tab in array array['areas','production_lines','work_centers','products','production_orders','downtime_reasons','status_events','downtime_events','memberships','roles','role_permissions','support_access','audit_logs','oee_observations','production_entries','operator_assignments','work_center_alternatives','work_center_capabilities','daily_targets','user_permissions','production_transfers','production_routing_steps'] loop
 execute format('select coalesce(jsonb_agg(x),''[]'') from (select * from public.%I where factory_id=$1 %s limit 5000) x',tab,case when tab in ('status_events','audit_logs','production_entries','downtime_events') then 'order by created_at desc,id' else '' end) into rows using f;
 data:=data||jsonb_build_object(tab,rows);
 if jsonb_array_length(rows)=5000 then limited:=array_append(limited,tab);end if;
 end loop;
 data:=data||jsonb_build_object('machine_statuses',(select jsonb_agg(x) from public.machine_statuses x where code<>'maintenance'),'permissions',(select jsonb_agg(x) from public.permissions x));
 end if;
 return jsonb_build_object('platformAdmin',private.is_platform_admin(),'factories',case when f is null then private.platform_factories() else '[]'::jsonb end,'factory',fac,'membership',m,'permissions',case when f is null then '{}'::text[] else public.access_matrix(f) end,'tables',data,'supportFactories',(select coalesce(jsonb_agg(x),'[]') from public.support_access x where user_id=auth.uid()),'truncatedTables',limited,'fetchedAt',now());
end$$;

do $$declare r record;begin
 for r in select p.oid::regprocedure as signature,p.proname,n.nspname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('private','public') and p.proname in ('is_platform_admin','platform_scope','set_user_permissions','owner_grants','support_grants','open_platform_factory','platform_factories','capture_stop_context','transfer_production','finish_transfer','save_line_layout','simple_operational_state') loop
 execute format('revoke all on function %s from public,anon,authenticated',r.signature);
 if r.proname not in ('owner_grants','support_grants','capture_stop_context','finish_transfer','simple_operational_state') then execute format('grant execute on function %s to authenticated',r.signature);end if;
 end loop;end$$;
