-- Factory-local templates augment existing direct person grants; job titles never authorize.
create table public.permission_packages (
 id uuid primary key default gen_random_uuid(), factory_id uuid not null references public.factories,
 name text not null check(length(btrim(name)) between 1 and 120), name_ar text not null default '' check(length(name_ar)<=120),
 description text not null default '' check(length(description)<=1000), template_key text,
 revision integer not null default 1 check(revision>0), created_by uuid references auth.users,
 created_at timestamptz not null default now(), updated_by uuid references auth.users, updated_at timestamptz not null default now(),
 unique(factory_id,id),unique(factory_id,template_key)
);
create unique index permission_package_names on public.permission_packages(factory_id,lower(btrim(name)));
create table public.permission_package_permissions (
 id uuid primary key default gen_random_uuid(), factory_id uuid not null, package_id uuid not null,
 module text not null,action text not null,created_by uuid references auth.users,created_at timestamptz not null default now(),
 unique(factory_id,package_id,module,action), foreign key(factory_id,package_id) references public.permission_packages(factory_id,id),
 foreign key(module,action) references public.permissions(module,action)
);
create table public.member_permission_packages (
 id uuid primary key default gen_random_uuid(), factory_id uuid not null, user_id uuid not null, package_id uuid not null,
 created_by uuid references auth.users,created_at timestamptz not null default now(),
 unique(factory_id,user_id,package_id),foreign key(factory_id,user_id) references public.memberships(factory_id,user_id),
 foreign key(factory_id,package_id) references public.permission_packages(factory_id,id)
);
create index member_package_definitions on public.member_permission_packages(factory_id,package_id);
alter table public.permission_packages enable row level security;
alter table public.permission_package_permissions enable row level security;
alter table public.member_permission_packages enable row level security;
revoke all on public.permission_packages,public.permission_package_permissions,public.member_permission_packages from anon,authenticated;

create function private.effective_person_permissions(f uuid,u uuid) returns table(module text,action text)
language sql stable security definer set search_path='' as $$
 select p.module,p.action from public.user_permissions p where p.factory_id=f and p.user_id=u
 union
 select p.module,p.action from public.member_permission_packages a
 join public.permission_package_permissions p on p.factory_id=a.factory_id and p.package_id=a.package_id
 where a.factory_id=f and a.user_id=u
$$;
revoke all on function private.effective_person_permissions(uuid,uuid) from public,anon,authenticated;
create or replace function private.has_permission(f uuid,m text,a text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (private.platform_scope(f) or
 (exists(select 1 from private.effective_person_permissions(f,auth.uid()) p where p.module=m and p.action=a)
 and (exists(select 1 from public.memberships u where u.factory_id=f and u.user_id=auth.uid() and u.status='approved')
 or exists(select 1 from public.support_access s where s.factory_id=f and s.user_id=auth.uid()
 and (s.mode='permanent' or (s.mode='temporary' and s.expires_at>now()))))))
$$;
-- Explicit per-person administration and existing live platform scope, never a job-title shortcut.
create policy package_read on public.permission_packages for select to authenticated using
 (private.has_permission(factory_id,'roles','view') or private.has_permission(factory_id,'roles','edit'));
create policy package_contents_read on public.permission_package_permissions for select to authenticated using
 (private.has_permission(factory_id,'roles','view') or private.has_permission(factory_id,'roles','edit'));
create policy package_assignments_read on public.member_permission_packages for select to authenticated using
 (private.has_permission(factory_id,'roles','view') or private.has_permission(factory_id,'roles','edit')
 or (user_id=auth.uid() and private.has_permission(factory_id,'factory','view')));
grant select on public.permission_packages,public.permission_package_permissions,public.member_permission_packages to authenticated;
create trigger audit_permission_packages after insert or update or delete on public.permission_packages for each row execute function private.audit_change();
create trigger audit_package_contents after insert or update or delete on public.permission_package_permissions for each row execute function private.audit_change();
create trigger audit_package_assignments after insert or update or delete on public.member_permission_packages for each row execute function private.audit_change();

create function private.seed_permission_packages(f uuid) returns void language plpgsql security definer set search_path='' as $$
declare item record; p uuid; keys text[];
begin
 for item in select * from (values
 ('owner','Factory Owner / Admin','مالك المصنع / الإدارة',null::text[]),
 ('production_manager','Production Manager','مدير الإنتاج',array['factory:view','dashboard:view','lines:view','centers:view','orders:view','orders:create','orders:edit','machine_status:edit','downtime:view','downtime:edit','maintenance:view','maintenance:create','maintenance:edit','reports:view','reports:export']),
 ('production_engineer','Production Engineer','مهندس الإنتاج',array['factory:view','dashboard:view','lines:view','centers:view','centers:edit','orders:view','orders:edit','machine_status:edit','downtime:view','downtime:edit','maintenance:view','maintenance:create','reports:view']),
 ('planning_engineer','Planning Engineer','مهندس التخطيط',array['factory:view','dashboard:view','lines:view','centers:view','orders:view','orders:edit']),
 ('maintenance','Maintenance','الصيانة',array['factory:view','dashboard:view','lines:view','centers:view','downtime:view','maintenance:view','maintenance:create','maintenance:edit']),
 ('warehouse','Warehouse','المستودع',array['factory:view','dashboard:view','warehouse:view','warehouse:edit','warehouse:issue','orders:view']),
 ('purchasing','Purchasing','المشتريات',array['factory:view','dashboard:view','purchasing:view','purchasing:create','purchasing:edit','suppliers:edit']),
 ('sales','Sales','المبيعات',array['factory:view','dashboard:view','sales_orders:view','sales_orders:create','sales_orders:edit','sales_orders:approve'])
 ) x(key,en,ar,grants) loop
  insert into public.permission_packages(factory_id,name,name_ar,template_key) values(f,item.en,item.ar,item.key)
  on conflict(factory_id,template_key) do nothing returning id into p;
  if p is not null then
   keys:=item.grants;
   insert into public.permission_package_permissions(factory_id,package_id,module,action)
   select f,p,module,action from public.permissions where keys is null or module||':'||action=any(keys);
  end if;
 end loop;
end$$;
revoke all on function private.seed_permission_packages(uuid) from public,anon,authenticated;
create function private.seed_factory_permission_packages() returns trigger language plpgsql security definer set search_path='' as $$
begin perform private.seed_permission_packages(new.id);return new;end$$;
revoke all on function private.seed_factory_permission_packages() from public,anon,authenticated;
create trigger seed_factory_permission_packages after insert on public.factories for each row execute function private.seed_factory_permission_packages();
do $$declare f uuid;begin for f in select id from public.factories loop perform private.seed_permission_packages(f);end loop;end$$;

create function private.save_permission_package(f uuid,p uuid,payload jsonb,grants jsonb,expected integer) returns uuid
language plpgsql security definer set search_path='' as $$
declare current public.permission_packages; names text[]; existing_names text[]; n text; ar text; note text;
begin
 perform private.require_permission(f,'roles','edit');
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));
 if p is null or expected is null or expected<0 or payload is null or jsonb_typeof(payload)<>'object'
 or exists(select 1 from jsonb_object_keys(payload) k where k not in ('name','name_ar','description'))
 or grants is null or jsonb_typeof(grants)<>'array' or jsonb_array_length(grants)>200 then raise exception 'invalid_input' using errcode='22023';end if;
 n:=btrim(payload->>'name');ar:=coalesce(payload->>'name_ar','');note:=coalesce(payload->>'description','');
 if n is null or length(n) not between 1 and 120 or length(ar)>120 or length(note)>1000
 or exists(select 1 from jsonb_array_elements(grants) x where jsonb_typeof(x)<>'object'
 or not(x ? 'module' and x ? 'action') or exists(select 1 from jsonb_object_keys(x) k where k not in ('module','action')))
 or exists(select 1 from jsonb_to_recordset(grants) x(module text,action text)
 where not exists(select 1 from public.permissions d where d.module=x.module and d.action=x.action)) then raise exception 'invalid_input' using errcode='22023';end if;
 if exists(select 1 from jsonb_to_recordset(grants) x(module text,action text) where not private.has_permission(f,x.module,x.action)) then raise exception 'cannot_grant_higher_permissions' using errcode='42501';end if;
 select coalesce(array_agg(distinct x.module||':'||x.action order by x.module||':'||x.action),'{}') into names from jsonb_to_recordset(grants) x(module text,action text);
 select * into current from public.permission_packages where id=p;
 if found then
  if current.factory_id<>f then raise exception 'permission_denied' using errcode='42501';end if;
  select coalesce(array_agg(module||':'||action order by module||':'||action),'{}') into existing_names from public.permission_package_permissions where factory_id=f and package_id=p;
  if current.name=n and current.name_ar=ar and current.description=note and existing_names=names then return p;end if;
  if current.revision<>expected then raise exception 'permission_package_conflict' using errcode='40001';end if;
  update public.permission_packages set name=n,name_ar=ar,description=note,revision=revision+1,updated_by=auth.uid(),updated_at=clock_timestamp() where id=p;
 else
  if expected<>0 then raise exception 'permission_package_conflict' using errcode='40001';end if;
  if (select count(*)>=200 from public.permission_packages where factory_id=f) then raise exception 'invalid_input' using errcode='22023';end if;
  insert into public.permission_packages(id,factory_id,name,name_ar,description,created_by,updated_by) values(p,f,n,ar,note,auth.uid(),auth.uid());
 end if;
 delete from public.permission_package_permissions where factory_id=f and package_id=p and not(module||':'||action=any(names));
 insert into public.permission_package_permissions(factory_id,package_id,module,action,created_by)
 select distinct f,p,x.module,x.action,auth.uid() from jsonb_to_recordset(grants) x(module text,action text) on conflict(factory_id,package_id,module,action) do nothing;
 return p;
end$$;
create function public.save_permission_package(factory uuid,package_id uuid,payload jsonb,permissions jsonb,expected_revision integer) returns uuid
language sql security invoker set search_path='' as $$select private.save_permission_package(factory,package_id,payload,permissions,expected_revision)$$;

create function private.set_member_permission_packages(f uuid,u uuid,packages uuid[],expected uuid[]) returns void
language plpgsql security definer set search_path='' as $$
declare selected uuid[]; previous uuid[];
begin
 perform private.require_permission(f,'roles','edit');
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));
 if packages is null or expected is null or cardinality(packages)>50 or cardinality(expected)>50 or array_position(packages,null) is not null or array_position(expected,null) is not null then raise exception 'invalid_input' using errcode='22023';end if;
 if not exists(select 1 from public.memberships where factory_id=f and user_id=u and not is_owner) then raise exception 'invalid_member' using errcode='22023';end if;
 select coalesce(array_agg(distinct v order by v),'{}') into selected from unnest(packages) v;
 if exists(select 1 from unnest(selected) v where not exists(select 1 from public.permission_packages where factory_id=f and id=v)) then raise exception 'permission_denied' using errcode='42501';end if;
 if exists(select 1 from public.permission_package_permissions where factory_id=f and package_id=any(selected) and not private.has_permission(f,module,action)) then raise exception 'cannot_grant_higher_permissions' using errcode='42501';end if;
 select coalesce(array_agg(package_id order by package_id),'{}') into previous from public.member_permission_packages where factory_id=f and user_id=u;
 if previous=selected then return;end if;
 if previous is distinct from (select coalesce(array_agg(distinct v order by v),'{}') from unnest(expected) v) then raise exception 'permission_package_conflict' using errcode='40001';end if;
 delete from public.member_permission_packages where factory_id=f and user_id=u and not(package_id=any(selected));
 insert into public.member_permission_packages(factory_id,user_id,package_id,created_by) select f,u,v,auth.uid() from unnest(selected) v on conflict(factory_id,user_id,package_id) do nothing;
end$$;
create function public.set_member_permission_packages(factory uuid,person uuid,packages uuid[],expected_packages uuid[]) returns void
language sql security invoker set search_path='' as $$select private.set_member_permission_packages(factory,person,packages,expected_packages)$$;

create function private.approve_member_packages(f uuid,i uuid,r uuid,packages uuid[],expected uuid[]) returns void
language plpgsql security definer set search_path='' as $$declare u uuid;begin
 perform private.require_permission(f,'employees','approve');
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));
 select user_id into u from public.memberships where factory_id=f and id=i and not is_owner;
 if u is null then raise exception 'invalid_member' using errcode='22023';end if;
 perform private.set_member_permission_packages(f,u,packages,expected);
 perform private.manage_member(f,i,r,'approved');
end$$;
create function public.approve_member_packages(factory uuid,id uuid,role uuid,packages uuid[],expected_packages uuid[]) returns void
language sql security invoker set search_path='' as $$select private.approve_member_packages(factory,id,role,packages,expected_packages)$$;

create function private.permission_package_page(f uuid,u uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare manager boolean; result jsonb; assigned uuid[];direct text[];inherited text[];effective text[];
begin
 if auth.uid() is null then raise exception 'permission_denied' using errcode='42501';end if;
 manager:=private.has_permission(f,'roles','view') or private.has_permission(f,'roles','edit');
 if not manager and (u is distinct from auth.uid() or not private.has_permission(f,'factory','view')) then raise exception 'permission_denied' using errcode='42501';end if;
 if u is not null and not exists(select 1 from public.memberships where factory_id=f and user_id=u) then raise exception 'not_found' using errcode='P0002';end if;
 select coalesce(array_agg(package_id order by package_id),'{}') into assigned from public.member_permission_packages where factory_id=f and user_id=u;
 select coalesce(array_agg(module||':'||action order by module||':'||action),'{}') into direct from public.user_permissions where factory_id=f and user_id=u;
 select coalesce(array_agg(distinct module||':'||action order by module||':'||action),'{}') into inherited from public.permission_package_permissions where factory_id=f and package_id=any(assigned);
 select coalesce(array_agg(module||':'||action order by module||':'||action),'{}') into effective from private.effective_person_permissions(f,u);
 select coalesce(jsonb_agg(x order by x.name),'[]') into result from
 (select p.*, (select coalesce(jsonb_agg(d.module||':'||d.action order by d.module,d.action),'[]') from public.permission_package_permissions d where d.factory_id=f and d.package_id=p.id) permissions,
 (select count(*) from public.member_permission_packages a where a.factory_id=f and a.package_id=p.id) assigned_count
 from public.permission_packages p where p.factory_id=f and (manager or p.id=any(assigned)) order by p.name limit 200) x;
 return jsonb_build_object('packages',result,'package_ids',assigned,'direct',direct,'inherited',inherited,'effective',effective,'can_manage',private.has_permission(f,'roles','edit'));
end$$;
create function public.permission_package_page(factory uuid,person uuid default null) returns jsonb language sql stable security invoker set search_path='' as $$select private.permission_package_page(factory,person)$$;

-- Retain unchanged direct rows (and their original actor/time); audit only actual additions/removals.
create or replace function private.set_user_permissions(f uuid,u uuid,grants jsonb) returns void
language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(f,'roles','edit');
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));
 perform private.require_permission(f,'roles','edit');
 if not exists(select 1 from public.memberships where factory_id=f and user_id=u and not is_owner) then raise exception 'invalid_member';end if;
 if grants is null or jsonb_typeof(grants)<>'array' or jsonb_array_length(grants)>200 then raise exception 'invalid_input';end if;
 if exists(select 1 from jsonb_to_recordset(grants) x(module text,action text) where not private.has_permission(f,x.module,x.action)) then raise exception 'cannot_grant_higher_permissions' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(f::text||u::text,0));
 delete from public.user_permissions p where p.factory_id=f and p.user_id=u
 and not exists(select 1 from jsonb_to_recordset(grants) x(module text,action text) where x.module=p.module and x.action=p.action);
 insert into public.user_permissions(factory_id,user_id,module,action,created_by)
 select distinct f,u,x.module,x.action,auth.uid() from jsonb_to_recordset(grants) x(module text,action text)
 on conflict(factory_id,user_id,module,action) do nothing;
end$$;
create function private.set_member_direct_permissions(f uuid,u uuid,grants jsonb,expected text[]) returns void
language plpgsql security definer set search_path='' as $$declare current text[]; desired text[];begin
 perform private.require_permission(f,'roles','edit');
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));
 if grants is null or jsonb_typeof(grants)<>'array' or jsonb_array_length(grants)>200 or expected is null or cardinality(expected)>200 then raise exception 'invalid_input' using errcode='22023';end if;
 select coalesce(array_agg(distinct x.module||':'||x.action order by x.module||':'||x.action),'{}') into desired from jsonb_to_recordset(grants) x(module text,action text);
 select coalesce(array_agg(module||':'||action order by module||':'||action),'{}') into current from public.user_permissions where factory_id=f and user_id=u;
 if current is distinct from desired and current is distinct from (select coalesce(array_agg(distinct v order by v),'{}') from unnest(expected) v) then raise exception 'permission_package_conflict' using errcode='40001';end if;
 perform private.set_user_permissions(f,u,grants);
end$$;
create function public.set_member_direct_permissions(factory uuid,person uuid,permissions jsonb,expected_direct text[]) returns void
language sql security invoker set search_path='' as $$select private.set_member_direct_permissions(factory,person,permissions,expected_direct)$$;
revoke all on function private.set_member_direct_permissions(uuid,uuid,jsonb,text[]),public.set_member_direct_permissions(uuid,uuid,jsonb,text[]) from public,anon,authenticated;
grant execute on function private.set_member_direct_permissions(uuid,uuid,jsonb,text[]),public.set_member_direct_permissions(uuid,uuid,jsonb,text[]) to authenticated;

revoke all on function private.save_permission_package(uuid,uuid,jsonb,jsonb,integer),public.save_permission_package(uuid,uuid,jsonb,jsonb,integer),
 private.set_member_permission_packages(uuid,uuid,uuid[],uuid[]),public.set_member_permission_packages(uuid,uuid,uuid[],uuid[]),
 private.approve_member_packages(uuid,uuid,uuid,uuid[],uuid[]),public.approve_member_packages(uuid,uuid,uuid,uuid[],uuid[]),
 private.permission_package_page(uuid,uuid),public.permission_package_page(uuid,uuid) from public,anon,authenticated;
grant execute on function private.save_permission_package(uuid,uuid,jsonb,jsonb,integer),public.save_permission_package(uuid,uuid,jsonb,jsonb,integer),
 private.set_member_permission_packages(uuid,uuid,uuid[],uuid[]),public.set_member_permission_packages(uuid,uuid,uuid[],uuid[]),
 private.approve_member_packages(uuid,uuid,uuid,uuid[],uuid[]),public.approve_member_packages(uuid,uuid,uuid,uuid[],uuid[]),
 private.permission_package_page(uuid,uuid),public.permission_package_page(uuid,uuid) to authenticated;
