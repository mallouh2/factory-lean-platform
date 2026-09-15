-- Phase 1: all operational writes go through authenticated, audited commands.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;
create table public.factories (
 id uuid primary key default gen_random_uuid(), name text not null check(length(name) between 2 and 120),
 industry text not null default '', timezone text not null default 'Asia/Qatar', logo_path text,
 is_demo boolean not null default false, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), created_by uuid references auth.users
);
create table public.roles (
 id uuid primary key default gen_random_uuid(), factory_id uuid not null references public.factories,
 name text not null, name_ar text not null default '', created_at timestamptz not null default now(), unique(factory_id,id), unique(factory_id,name)
);
create table public.permissions(module text not null, action text not null check(action in ('view','create','edit','delete','approve','export')), primary key(module,action));
insert into public.permissions select m,a from unnest(array['dashboard','factory','lines','centers','orders','downtime','reports','employees','roles','settings','support','audit']) m cross join unnest(array['view','create','edit','delete','approve','export']) a;
create table public.role_permissions (
 factory_id uuid not null references public.factories, role_id uuid not null, module text not null, action text not null,
 primary key(role_id,module,action), foreign key(factory_id,role_id) references public.roles(factory_id,id), foreign key(module,action) references public.permissions
);
create table public.memberships (
 id uuid primary key default gen_random_uuid(), factory_id uuid not null references public.factories, user_id uuid not null references auth.users,
 display_name text not null, role_id uuid, is_owner boolean not null default false, status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(user_id), unique(factory_id,id), unique(factory_id,user_id),
 foreign key(factory_id,role_id) references public.roles(factory_id,id)
);
create table private.join_codes(factory_id uuid primary key references public.factories, code text not null unique);
create table public.support_access (
 id uuid primary key default gen_random_uuid(), factory_id uuid not null references public.factories, user_id uuid not null references auth.users,
 role_id uuid not null, mode text not null check(mode in ('disabled','temporary','permanent')), expires_at timestamptz,
 created_at timestamptz not null default now(), unique(factory_id,user_id), foreign key(factory_id,role_id) references public.roles(factory_id,id),
 check(mode <> 'temporary' or expires_at is not null)
);
create table public.areas(id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories,name text not null,name_ar text not null default '',archived boolean not null default false,created_at timestamptz not null default now(),unique(factory_id,id));
create table public.production_lines(id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories,area_id uuid,name text not null,name_ar text not null default '',code text not null,archived boolean not null default false,created_at timestamptz not null default now(),unique(factory_id,id),unique(factory_id,code),foreign key(factory_id,area_id) references public.areas(factory_id,id));
create table public.products(id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories,name text not null,name_ar text not null default '',code text not null,unit text not null default 'unit',category text,diameter numeric,length numeric,color text,weight numeric,standard_rate numeric check(standard_rate>0),created_at timestamptz not null default now(),unique(factory_id,id),unique(factory_id,code));
create table public.production_orders(id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories,product_id uuid not null,line_id uuid,code text not null,status text not null default 'planned' check(status in ('planned','active','completed','cancelled')),target_quantity numeric not null check(target_quantity>0),produced_quantity numeric not null default 0 check(produced_quantity>=0),rejected_quantity numeric not null default 0 check(rejected_quantity>=0 and rejected_quantity<=produced_quantity),start_time timestamptz,expected_finish timestamptz,created_at timestamptz not null default now(),unique(factory_id,id),unique(factory_id,code),foreign key(factory_id,product_id) references public.products(factory_id,id),foreign key(factory_id,line_id) references public.production_lines(factory_id,id));
create table public.machine_statuses(code text primary key,name text not null,name_ar text not null,is_downtime boolean not null,color text not null);
insert into public.machine_statuses values ('running','Running','قيد التشغيل',false,'green'),('stopped','Stopped','متوقف',true,'red'),('setup','Setup / Changeover','إعداد / تغيير المنتج',true,'yellow'),('idle','Idle','بانتظار العمل',false,'blue'),('maintenance','Maintenance','صيانة',true,'orange'),('offline','Offline','خارج الخدمة',false,'gray');
create table public.work_centers(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories,area_id uuid,line_id uuid,
 name text not null,name_ar text not null default '',code text not null,type text not null default 'machine' check(type in ('machine','manual_station','assembly_table','packing_station','inspection_station','other')),
 description text not null default '',status text not null default 'idle' references public.machine_statuses,order_id uuid,operator_id uuid,
 start_time timestamptz,expected_finish timestamptz,production_speed numeric check(production_speed>0),default_cycle_time numeric check(default_cycle_time>0),current_cycle_time numeric check(current_cycle_time>0),planned_capacity numeric check(planned_capacity>=0),last_restart_time timestamptz,notes text not null default '',image_path text,position integer not null default 0,archived boolean not null default false,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),created_by uuid references auth.users,
 unique(factory_id,id),unique(factory_id,code),foreign key(factory_id,area_id) references public.areas(factory_id,id),foreign key(factory_id,line_id) references public.production_lines(factory_id,id),foreign key(factory_id,order_id) references public.production_orders(factory_id,id),foreign key(factory_id,operator_id) references public.memberships(factory_id,id)
);
create table public.work_center_capabilities(factory_id uuid not null,work_center_id uuid not null,product_id uuid not null,rate numeric not null check(rate>0),primary key(work_center_id,product_id),foreign key(factory_id,work_center_id) references public.work_centers(factory_id,id),foreign key(factory_id,product_id) references public.products(factory_id,id));
create table public.work_center_alternatives(factory_id uuid not null,work_center_id uuid not null,alternative_id uuid not null,primary key(work_center_id,alternative_id),check(work_center_id<>alternative_id),foreign key(factory_id,work_center_id) references public.work_centers(factory_id,id),foreign key(factory_id,alternative_id) references public.work_centers(factory_id,id));
create table public.downtime_reasons(id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories,parent_id uuid,name text not null,name_ar text not null default '',requires_description boolean not null default false,created_at timestamptz not null default now(),unique(factory_id,id),foreign key(factory_id,parent_id) references public.downtime_reasons(factory_id,id));
create table public.status_events(id uuid primary key default gen_random_uuid(),factory_id uuid not null,work_center_id uuid not null,old_status text references public.machine_statuses,new_status text not null references public.machine_statuses,reason_id uuid,notes text not null default '',created_at timestamptz not null default now(),created_by uuid references auth.users,foreign key(factory_id,work_center_id) references public.work_centers(factory_id,id),foreign key(factory_id,reason_id) references public.downtime_reasons(factory_id,id));
create table public.downtime_events(id uuid primary key default gen_random_uuid(),factory_id uuid not null,work_center_id uuid not null,reason_id uuid not null,sub_reason_id uuid,started_at timestamptz not null default now(),ended_at timestamptz,expected_restart timestamptz,responsible_id uuid,alternative_id uuid,transferred boolean not null default false,notes text not null default '',created_by uuid references auth.users,created_at timestamptz not null default now(),unique(factory_id,id),check(ended_at is null or ended_at>=started_at),foreign key(factory_id,work_center_id) references public.work_centers(factory_id,id),foreign key(factory_id,reason_id) references public.downtime_reasons(factory_id,id),foreign key(factory_id,sub_reason_id) references public.downtime_reasons(factory_id,id),foreign key(factory_id,responsible_id) references public.memberships(factory_id,id),foreign key(factory_id,alternative_id) references public.work_centers(factory_id,id));
create unique index one_open_downtime on public.downtime_events(work_center_id) where ended_at is null;
create table public.audit_logs(id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories,actor_id uuid references auth.users,action text not null,entity text not null,entity_id uuid,old_data jsonb,new_data jsonb,created_at timestamptz not null default now());
-- No OEE estimate until complete, validated shift observations are available.
create table public.oee_observations(id uuid primary key default gen_random_uuid(),factory_id uuid not null,work_center_id uuid not null,started_at timestamptz not null,ended_at timestamptz not null,planned_seconds numeric check(planned_seconds>0),run_seconds numeric check(run_seconds>=0 and run_seconds<=planned_seconds),ideal_cycle_seconds numeric check(ideal_cycle_seconds>0),total_count numeric check(total_count>=0),good_count numeric check(good_count>=0 and good_count<=total_count),check(ended_at>started_at),foreign key(factory_id,work_center_id) references public.work_centers(factory_id,id));

create function private.has_permission(f uuid,m text,a text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (exists(select 1 from public.memberships u where u.factory_id=f and u.user_id=auth.uid() and u.status='approved' and (u.is_owner or exists(select 1 from public.role_permissions p where p.role_id=u.role_id and p.module=m and p.action=a)))
 or exists(select 1 from public.support_access s join public.role_permissions p on p.role_id=s.role_id where s.factory_id=f and s.user_id=auth.uid() and (s.mode='permanent' or (s.mode='temporary' and s.expires_at>now())) and p.module=m and p.action=a));
$$;
create function private.require_permission(f uuid,m text,a text) returns void language plpgsql security definer set search_path='' as $$begin if not private.has_permission(f,m,a) then raise exception 'permission_denied' using errcode='42501'; end if; end$$;
create function private.is_owner(f uuid) returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and exists(select 1 from public.memberships where factory_id=f and user_id=auth.uid() and status='approved' and is_owner)$$;
create function public.can_access(factory uuid,module text,action text) returns boolean language sql stable security invoker set search_path='' as $$select private.has_permission(factory,module,action)$$;

create function private.audit_change() returns trigger language plpgsql security definer set search_path='' as $$
 declare r jsonb; f uuid; begin
 r:=case when TG_OP='DELETE' then to_jsonb(old) else to_jsonb(new) end;
 f:=case when TG_TABLE_NAME='factories' then (r->>'id')::uuid else (r->>'factory_id')::uuid end;
 insert into public.audit_logs(factory_id,actor_id,action,entity,entity_id,old_data,new_data) values(f,auth.uid(),TG_OP,TG_TABLE_NAME,(r->>'id')::uuid,case when TG_OP<>'INSERT' then to_jsonb(old) end,case when TG_OP<>'DELETE' then to_jsonb(new) end);
 return case when TG_OP='DELETE' then old else new end;
 end$$;

do $$declare t text; m text; begin
 foreach t in array array['factories','roles','role_permissions','memberships','support_access','areas','production_lines','products','production_orders','work_centers','work_center_capabilities','work_center_alternatives','downtime_reasons','status_events','downtime_events','audit_logs','oee_observations'] loop
 execute format('alter table public.%I enable row level security',t);
 m:=case when t='factories' then 'factory' when t in ('areas') then 'factory' when t='production_lines' then 'lines' when t in ('work_centers','work_center_capabilities','work_center_alternatives','status_events') then 'centers' when t in ('products','production_orders') then 'orders' when t in ('downtime_events','downtime_reasons') then 'downtime' when t in ('roles','role_permissions') then 'roles' when t='memberships' then 'employees' when t='support_access' then 'support' when t='audit_logs' then 'audit' else 'reports' end;
 execute format('create policy read_authorized on public.%I for select to authenticated using(private.has_permission(%I,%L,''view''))',t,case when t='factories' then 'id' else 'factory_id' end,m);
 if t not in ('audit_logs','status_events','work_center_capabilities','work_center_alternatives','oee_observations') then execute format('create trigger audit_record after insert or update or delete on public.%I for each row execute function private.audit_change()',t); end if;
 execute format('grant select on public.%I to authenticated',t);
 end loop;
end$$;
create policy own_membership on public.memberships for select to authenticated using(user_id=(select auth.uid()));
alter table public.permissions enable row level security;
alter table public.machine_statuses enable row level security;
create policy authenticated_read on public.permissions for select to authenticated using(true);
create policy authenticated_read on public.machine_statuses for select to authenticated using(true);
grant select on public.permissions,public.machine_statuses to authenticated;
alter table private.join_codes enable row level security;

create function private.create_factory(n text,tz text,industry text) returns uuid language plpgsql security definer set search_path='' as $$
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
 elsif v='Technician / Operator' then insert into public.role_permissions select f,r,module,action from public.permissions where (action='view' and module in ('dashboard','factory','lines','centers','orders','downtime')) or (action='edit' and module='centers'); end if;
 end loop;
 insert into public.downtime_reasons(factory_id,name,name_ar,requires_description)
 select f,x.en,x.ar,x.en='Other' from (values('Mechanical Failure','عطل ميكانيكي'),('Electrical Failure','عطل كهربائي'),('Material Shortage','نقص مواد'),('Operator Unavailable','عدم توفر المشغل'),('Tooling Problem','مشكلة في العِدد'),('Setup / Changeover','إعداد / تغيير المنتج'),('Quality Problem','مشكلة جودة'),('Waiting for Approval','انتظار الموافقة'),('Maintenance','صيانة'),('Cleaning','تنظيف'),('Power Failure','انقطاع الكهرباء'),('Production Planning Delay','تأخير تخطيط الإنتاج'),('Other','أخرى')) x(en,ar);
 return f;
 end$$;
create function public.create_factory(name text,timezone text,industry text) returns uuid language sql security invoker set search_path='' as $$select private.create_factory(name,timezone,industry)$$;
create function private.join_factory(code text,display_name text) returns void language plpgsql security definer set search_path='' as $$declare f uuid;begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'verify_email'; end if;
 if length(trim(display_name)) not between 2 and 100 then raise exception 'invalid_name'; end if;
 select factory_id into f from private.join_codes j where j.code=upper(trim(join_factory.code));
 if f is null then raise exception 'invalid_join_code'; end if;
 insert into public.memberships(factory_id,user_id,display_name) values(f,auth.uid(),display_name);
 end$$;
create function public.join_factory(code text,display_name text) returns void language sql security invoker set search_path='' as $$select private.join_factory(code,display_name)$$;
create function private.manage_member(f uuid,i uuid,r uuid,s text) returns void language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(f,'employees','approve');
 if s not in ('approved','rejected') or exists(select 1 from public.memberships where id=i and is_owner) then raise exception 'invalid_membership_change'; end if;
 if not private.is_owner(f) and exists(select 1 from public.role_permissions p where p.role_id=r and not private.has_permission(f,p.module,p.action)) then raise exception 'cannot_grant_higher_permissions'; end if;
 if s='approved' and r is null then raise exception 'role_required'; end if;
 update public.memberships set status=s,role_id=r,updated_at=now() where id=i and factory_id=f;
 if not found then raise exception 'not_found'; end if;
 end$$;
create function public.manage_member(factory uuid,id uuid,role uuid,status text) returns void language sql security invoker set search_path='' as $$select private.manage_member(factory,id,role,status)$$;
create function private.join_code(f uuid,regenerate boolean) returns text language plpgsql security definer set search_path='' as $$declare c text;begin
 perform private.require_permission(f,'settings','edit');
 if regenerate then update private.join_codes set code='FAC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)) where factory_id=f;
 insert into public.audit_logs(factory_id,actor_id,action,entity) values(f,auth.uid(),'REGENERATE','join_code'); end if;
 select code into c from private.join_codes where factory_id=f; return c;
 end$$;
create function public.get_join_code(factory uuid,regenerate boolean default false) returns text language sql security invoker set search_path='' as $$select private.join_code(factory,regenerate)$$;

create function private.change_status(f uuid,w uuid,s text,reason uuid,sub_reason uuid,n text,eta timestamptz,responsible uuid,alternative uuid,transferred boolean) returns void language plpgsql security definer set search_path='' as $$
 declare old_s text; down boolean; begin
 perform private.require_permission(f,'centers','edit');
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
create function public.change_status(factory uuid,work_center uuid,status text,reason uuid default null,sub_reason uuid default null,notes text default '',expected_restart timestamptz default null,responsible uuid default null,alternative uuid default null,transferred boolean default false) returns void language sql security invoker set search_path='' as $$select private.change_status(factory,work_center,status,reason,sub_reason,notes,expected_restart,responsible,alternative,transferred)$$;

-- Explicit resource and column allowlists prevent mass assignment of factory IDs or audit fields.
create function private.save_record(f uuid,resource text,record_id uuid,p jsonb) returns uuid language plpgsql security definer set search_path='' as $$
 declare table_name text; allowed text[]; k text; columns_sql text:=''; values_sql text:=''; update_sql text:=''; result_id uuid; action text; begin
 action:=case when record_id is null then 'create' else 'edit' end;
 perform private.require_permission(f,resource,action);
 case resource
 when 'factory' then table_name:='areas';allowed:=array['name','name_ar','archived'];
 when 'lines' then table_name:='production_lines';allowed:=array['name','name_ar','code','area_id','archived'];
 when 'centers' then table_name:='work_centers';allowed:=array['name','name_ar','code','type','area_id','line_id','order_id','operator_id','description','notes','production_speed','default_cycle_time','current_cycle_time','planned_capacity','position','archived','start_time','expected_finish'];
 when 'orders' then table_name:='production_orders';allowed:=array['code','product_id','line_id','status','target_quantity','produced_quantity','rejected_quantity','start_time','expected_finish'];
 when 'downtime' then table_name:='downtime_reasons';allowed:=array['name','name_ar','parent_id','requires_description'];
 when 'roles' then
 if not private.is_owner(f) then raise exception 'owner_required'; end if;
 table_name:='roles';allowed:=array['name','name_ar'];
 else raise exception 'invalid_resource'; end case;
 if jsonb_typeof(p)<>'object' or p='{}'::jsonb then raise exception 'invalid_input'; end if;
 for k in select jsonb_object_keys(p) loop
 if not k=any(allowed) then raise exception 'invalid_field'; end if;
 if columns_sql<>'' then columns_sql:=columns_sql||',';values_sql:=values_sql||',';update_sql:=update_sql||',';end if;
 columns_sql:=columns_sql||format('%I',k); values_sql:=values_sql||format('v.%I',k);update_sql:=update_sql||format('%I=v.%I',k,k);
 end loop;
 if record_id is null then
 execute format('insert into public.%I(factory_id,%s) select $1,%s from jsonb_populate_record(null::public.%I,$2) v returning id',table_name,columns_sql,values_sql,table_name) into result_id using f,p;
 else
 execute format('update public.%I t set %s from jsonb_populate_record(null::public.%I,$2) v where t.factory_id=$1 and t.id=$3 returning t.id',table_name,update_sql,table_name) into result_id using f,p,record_id;
 end if;
 if result_id is null then raise exception 'not_found';end if;return result_id;
 end$$;
create function public.save_record(factory uuid,resource text,id uuid,payload jsonb) returns uuid language sql security invoker set search_path='' as $$select private.save_record(factory,resource,id,payload)$$;
create function private.update_settings(f uuid,n text,tz text,logo text) returns void language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(f,'settings','edit');
 if not exists(select 1 from pg_timezone_names where name=tz) then raise exception 'invalid_timezone';end if;
 if logo is not null and split_part(logo,'/',1)<>f::text then raise exception 'invalid_logo';end if;
 update public.factories set name=n,timezone=tz,logo_path=logo,updated_at=now() where id=f;
 end$$;
create function public.update_settings(factory uuid,name text,timezone text,logo text default null) returns void language sql security invoker set search_path='' as $$select private.update_settings(factory,name,timezone,logo)$$;
create function private.set_permissions(f uuid,r uuid,p jsonb) returns void language plpgsql security definer set search_path='' as $$begin
 if not private.is_owner(f) then raise exception 'owner_required';end if;
 if not exists(select 1 from public.roles where id=r and factory_id=f) then raise exception 'not_found';end if;
 delete from public.role_permissions where role_id=r and factory_id=f;
 insert into public.role_permissions(factory_id,role_id,module,action) select f,r,x.module,x.action from jsonb_to_recordset(p) x(module text,action text);
 end$$;
create function public.set_permissions(factory uuid,role uuid,permissions jsonb) returns void language sql security invoker set search_path='' as $$select private.set_permissions(factory,role,permissions)$$;
create function private.set_support(f uuid,u uuid,r uuid,mode text,expiry timestamptz) returns void language plpgsql security definer set search_path='' as $$begin
 if not private.is_owner(f) then raise exception 'owner_required';end if;
 if mode='temporary' and (expiry is null or expiry<=now()) then raise exception 'invalid_expiry';end if;
 insert into public.support_access(factory_id,user_id,role_id,mode,expires_at) values(f,u,r,mode,expiry) on conflict(factory_id,user_id) do update set role_id=excluded.role_id,mode=excluded.mode,expires_at=excluded.expires_at;
 end$$;
create function public.set_support(factory uuid,user_id uuid,role uuid,mode text,expires_at timestamptz default null) returns void language sql security invoker set search_path='' as $$select private.set_support(factory,user_id,role,mode,expires_at)$$;

-- Internal functions have no anonymous execution privileges.
revoke all on all functions in schema private from public,anon;
grant execute on all functions in schema private to authenticated;
revoke all on function private.audit_change() from authenticated;
revoke all on all functions in schema public from public,anon;
grant execute on function public.can_access(uuid,text,text),public.create_factory(text,text,text),public.join_factory(text,text),public.manage_member(uuid,uuid,uuid,text),public.get_join_code(uuid,boolean),public.change_status(uuid,uuid,text,uuid,uuid,text,timestamptz,uuid,uuid,boolean),public.save_record(uuid,text,uuid,jsonb),public.update_settings(uuid,text,text,text),public.set_permissions(uuid,uuid,jsonb),public.set_support(uuid,uuid,uuid,text,timestamptz) to authenticated;

create index membership_factory_status on public.memberships(factory_id,status);
create index status_events_timeline on public.status_events(factory_id,work_center_id,created_at desc);
create index downtime_period on public.downtime_events(factory_id,started_at);
create index audit_timeline on public.audit_logs(factory_id,created_at desc);
create index centers_line on public.work_centers(factory_id,line_id);
create index support_lookup on public.support_access(user_id,factory_id,expires_at);

do $$declare r record;begin
 for r in select table_name,column_name from information_schema.columns where table_schema='public' and (column_name like '%_id') and table_name not in ('permissions','machine_statuses') loop
 execute format('create index if not exists %I on public.%I(%I)',left(r.table_name||'_'||r.column_name||'_idx',63),r.table_name,r.column_name);
 end loop;
end$$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('factory-logos','factory-logos',false,2097152,array['image/png','image/jpeg','image/webp']);
create policy logo_read on storage.objects for select to authenticated using(bucket_id='factory-logos' and private.has_permission((storage.foldername(name))[1]::uuid,'factory','view'));
create policy logo_create on storage.objects for insert to authenticated with check(bucket_id='factory-logos' and private.has_permission((storage.foldername(name))[1]::uuid,'settings','edit'));
-- One server round trip returns the effective permission matrix.
create function public.access_matrix(factory uuid) returns text[] language sql stable security invoker set search_path='' as $$select coalesce(array_agg(module||':'||action),'{}'::text[]) from public.permissions where private.has_permission(factory,module,action)$$;
revoke all on function public.access_matrix(uuid) from public,anon;
grant execute on function public.access_matrix(uuid) to authenticated;
create policy own_support_grants on public.support_access for select to authenticated using(user_id=(select auth.uid()));
