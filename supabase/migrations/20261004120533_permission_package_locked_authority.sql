-- Recheck authority after serialization: access may have been revoked while waiting.
create or replace function private.save_permission_package(f uuid,p uuid,payload jsonb,grants jsonb,expected integer) returns uuid
language plpgsql security definer set search_path='' as $$
declare current public.permission_packages; names text[]; existing_names text[]; n text; ar text; note text;
begin
 perform private.require_permission(f,'roles','edit');
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));
 perform private.require_permission(f,'roles','edit');
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

create or replace function private.set_member_permission_packages(f uuid,u uuid,packages uuid[],expected uuid[]) returns void
language plpgsql security definer set search_path='' as $$
declare selected uuid[]; previous uuid[];
begin
 perform private.require_permission(f,'roles','edit');
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));
 perform private.require_permission(f,'roles','edit');
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
