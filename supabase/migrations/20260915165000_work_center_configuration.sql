-- Complete work-center configuration without implementing advanced planning.
alter table public.work_centers drop constraint work_centers_type_check;
alter table public.work_centers add constraint work_centers_type_check check(type in ('machine','manual_station','assembly_table','packing_station','inspection_station','production_cell','other'));
create trigger audit_capabilities after insert or update or delete on public.work_center_capabilities for each row execute function private.audit_change();
create trigger audit_alternatives after insert or update or delete on public.work_center_alternatives for each row execute function private.audit_change();
create function private.configure_center_links(f uuid,w uuid,alternatives uuid[],capabilities jsonb) returns void language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(f,'centers','edit');
 perform 1 from public.work_centers where id=w and factory_id=f and not archived for update;
 if not found then raise exception 'not_found';end if;
 if exists(select 1 from unnest(alternatives) x where x=w or not exists(select 1 from public.work_centers c where c.id=x and c.factory_id=f and not c.archived)) then raise exception 'invalid_alternative';end if;
 delete from public.work_center_alternatives where factory_id=f and work_center_id=w;
 insert into public.work_center_alternatives(factory_id,work_center_id,alternative_id) select f,w,x from unnest(alternatives) x;
 delete from public.work_center_capabilities where factory_id=f and work_center_id=w;
 insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate) select f,w,x.product_id,x.rate from jsonb_to_recordset(capabilities) x(product_id uuid,rate numeric);
 end$$;
create function public.configure_center_links(factory uuid,work_center uuid,alternatives uuid[],capabilities jsonb) returns void language sql security invoker set search_path='' as $$select private.configure_center_links(factory,work_center,alternatives,capabilities)$$;
create function private.update_downtime(f uuid,i uuid,eta timestamptz,n text,responsible uuid,alternative uuid,transferred boolean) returns void language plpgsql security definer set search_path='' as $$begin
 if not private.has_permission(f,'downtime','edit') then perform private.require_permission(f,'machine_status','edit');end if;
 if eta is not null and eta<now() then raise exception 'invalid_restart_time';end if;
 if length(coalesce(n,''))>2000 then raise exception 'invalid_notes';end if;
 if responsible is not null and not exists(select 1 from public.memberships where id=responsible and factory_id=f and status='approved') then raise exception 'invalid_responsible';end if;
 if transferred and alternative is null then raise exception 'alternative_required';end if;
 if exists(select 1 from public.downtime_events d join public.downtime_reasons r on r.id=d.reason_id where d.id=i and d.factory_id=f and r.requires_description) and length(trim(coalesce(n,'')))<3 then raise exception 'description_required';end if;
 if alternative is not null and (not exists(select 1 from public.work_centers where id=alternative and factory_id=f and not archived) or exists(select 1 from public.downtime_events where id=i and work_center_id=alternative)) then raise exception 'invalid_alternative';end if;
 update public.downtime_events set expected_restart=eta,notes=coalesce(n,''),responsible_id=responsible,alternative_id=alternative,transferred=update_downtime.transferred where id=i and factory_id=f and ended_at is null;
 if not found then raise exception 'not_found';end if;
 end$$;
create function public.update_downtime(factory uuid,id uuid,expected_restart timestamptz,notes text,responsible uuid default null,alternative uuid default null,transferred boolean default false) returns void language sql security invoker set search_path='' as $$select private.update_downtime(factory,id,expected_restart,notes,responsible,alternative,transferred)$$;
create function private.support_by_email(f uuid,email text,r uuid,mode text,expiry timestamptz) returns void language plpgsql security definer set search_path='' as $$declare u uuid;begin
 if not private.is_owner(f) then raise exception 'owner_required' using errcode='42501';end if;
 select id into u from auth.users where lower(auth.users.email)=lower(trim(support_by_email.email)) and email_confirmed_at is not null;
 if u is null then raise exception 'support_account_not_found';end if;
 perform private.set_support(f,u,r,mode,expiry);
 end$$;
create function public.set_support_by_email(factory uuid,email text,role uuid,mode text,expires_at timestamptz default null) returns void language sql security invoker set search_path='' as $$select private.support_by_email(factory,email,role,mode,expires_at)$$;
revoke all on function private.configure_center_links(uuid,uuid,uuid[],jsonb),public.configure_center_links(uuid,uuid,uuid[],jsonb),private.update_downtime(uuid,uuid,timestamptz,text,uuid,uuid,boolean),public.update_downtime(uuid,uuid,timestamptz,text,uuid,uuid,boolean),private.support_by_email(uuid,text,uuid,text,timestamptz),public.set_support_by_email(uuid,text,uuid,text,timestamptz) from public,anon;
grant execute on function private.configure_center_links(uuid,uuid,uuid[],jsonb),public.configure_center_links(uuid,uuid,uuid[],jsonb),private.update_downtime(uuid,uuid,timestamptz,text,uuid,uuid,boolean),public.update_downtime(uuid,uuid,timestamptz,text,uuid,uuid,boolean),private.support_by_email(uuid,text,uuid,text,timestamptz),public.set_support_by_email(uuid,text,uuid,text,timestamptz) to authenticated;

create or replace function public.factory_snapshot(factory uuid default null) returns jsonb language plpgsql security invoker set search_path='' as $$
declare m jsonb;f uuid;fac jsonb;tab text;rows jsonb;data jsonb:='{}';limited text[]:='{}';begin
 select to_jsonb(x) into m from public.memberships x where user_id=auth.uid();
 f:=case when m->>'status'='approved' then (m->>'factory_id')::uuid else $1 end;
 if f is not null then
 perform private.require_permission(f,'factory','view');
 perform private.record_access(f,'READ');
 select to_jsonb(x) into fac from public.factories x where id=f;
 foreach tab in array array['areas','production_lines','work_centers','products','production_orders','downtime_reasons','status_events','downtime_events','memberships','roles','role_permissions','support_access','audit_logs','oee_observations','production_entries','operator_assignments','work_center_alternatives','work_center_capabilities','daily_targets'] loop
 execute format('select coalesce(jsonb_agg(x),''[]'') from (select * from public.%I where factory_id=$1 %s limit 5000) x',tab,case when tab in ('status_events','audit_logs','production_entries','downtime_events') then 'order by created_at desc,id' else '' end) into rows using f;
 data:=data||jsonb_build_object(tab,rows);
 if jsonb_array_length(rows)=5000 then limited:=array_append(limited,tab);end if;
 end loop;
 data:=data||jsonb_build_object('machine_statuses',(select jsonb_agg(x) from public.machine_statuses x),'permissions',(select jsonb_agg(x) from public.permissions x));
 end if;
 return jsonb_build_object('factory',fac,'membership',m,'permissions',case when f is null then '{}'::text[] else public.access_matrix(f) end,'tables',data,'supportFactories',(select coalesce(jsonb_agg(x),'[]') from public.support_access x where user_id=auth.uid()),'truncatedTables',limited,'fetchedAt',now());
end$$;
