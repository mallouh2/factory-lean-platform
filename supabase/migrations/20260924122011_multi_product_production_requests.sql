-- A request is the business need; existing production_orders remain independently
-- schedulable and executable product items.
create table public.production_requests (
  id uuid primary key default gen_random_uuid(),
  factory_id uuid not null references public.factories(id) on delete cascade,
  code text not null,
  name text not null check (length(btrim(name)) between 1 and 200),
  requested_by uuid references auth.users(id),
  requested_by_name text,
  priority text not null default 'unspecified'
    check (priority in ('unspecified','low','normal','high','urgent')),
  required_by timestamptz,
  notes text not null default '' check (length(notes) <= 2000),
  created_at timestamptz not null default now(),
  unique(factory_id,id),
  unique(factory_id,code)
);

alter table public.production_orders
  add column request_id uuid,
  add column unit text not null default 'unit'
    check (unit in ('meter','piece','unit'));

-- Current development records have no business request name or known requester.
-- Preserve their codes and avoid inventing a person's identity or unit conversion.
insert into public.production_requests(id,factory_id,code,name,created_at)
select o.id,o.factory_id,o.code,o.code,o.created_at
from public.production_orders o;

update public.production_orders o set
  request_id = o.id,
  unit = case
    when lower(p.unit) in ('meter','metre','m') then 'meter'
    when lower(p.unit) in ('piece','pieces','pcs','pc') then 'piece'
    else 'unit'
  end
from public.products p
where p.id=o.product_id and p.factory_id=o.factory_id;

alter table public.production_orders
  alter column request_id set not null,
  add constraint production_order_request_factory_fk
    foreign key(factory_id,request_id) references public.production_requests(factory_id,id),
  add constraint production_request_product_once
    unique(request_id,product_id);

create index production_orders_request_lookup on public.production_orders(factory_id,request_id);

create function private.assign_production_request_code()
returns trigger language plpgsql set search_path='' as $$
declare request_number text;
begin
  loop
    request_number := nextval('private.production_order_number_seq'::regclass)::text;
    new.code := 'PO-' || lpad(request_number,greatest(7,length(request_number)),'0');
    exit when not exists (
      select 1 from public.production_requests r
      where r.factory_id=new.factory_id and r.code=new.code
    );
  end loop;
  return new;
end;
$$;
create trigger assign_production_request_code before insert on public.production_requests
for each row execute function private.assign_production_request_code();

alter table public.production_requests enable row level security;
create policy read_authorized on public.production_requests for select to authenticated
  using(private.has_permission(factory_id,'orders','view'));
grant select on public.production_requests to authenticated;
create trigger audit_record after insert or update or delete on public.production_requests
for each row execute function private.audit_change();

create function private.create_production_request(
  f uuid,request_name text,request_priority text,request_required_by timestamptz,
  request_notes text,request_items jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid; entry jsonb; product uuid; amount numeric; item_unit text;
  seen uuid[] := '{}'; actor_name text;
begin
  perform private.require_permission(f,'orders','create');
  if length(btrim(coalesce(request_name,''))) not between 1 and 200 then
    raise exception 'request_name_required'; end if;
  if coalesce(request_priority,'unspecified') not in ('unspecified','low','normal','high','urgent') then
    raise exception 'invalid_priority'; end if;
  if length(coalesce(request_notes,''))>2000 then raise exception 'invalid_notes'; end if;
  if jsonb_typeof(request_items) is distinct from 'array'
    or jsonb_array_length(request_items) not between 1 and 100 then
    raise exception 'request_items_required'; end if;
  select m.display_name into actor_name from public.memberships m
    where m.factory_id=f and m.user_id=auth.uid() and m.status='approved';
  actor_name := coalesce(actor_name,
    (select split_part(u.email,'@',1) from auth.users u where u.id=auth.uid()));
  insert into public.production_requests(
    factory_id,code,name,requested_by,requested_by_name,priority,required_by,notes
  ) values (
    f,'',btrim(request_name),auth.uid(),actor_name,
    coalesce(request_priority,'unspecified'),request_required_by,coalesce(request_notes,'')
  ) returning id into result_id;
  for entry in select value from jsonb_array_elements(request_items) loop
    if jsonb_typeof(entry) is distinct from 'object' then raise exception 'invalid_request_item'; end if;
    product := nullif(entry->>'product_id','')::uuid;
    amount := nullif(entry->>'quantity','')::numeric;
    item_unit := entry->>'unit';
    if product is null or not exists(
      select 1 from public.products p where p.factory_id=f and p.id=product
    ) then raise exception 'invalid_request_product'; end if;
    if product=any(seen) then raise exception 'duplicate_request_product'; end if;
    if amount is null or amount<=0 then raise exception 'invalid_request_quantity'; end if;
    if item_unit not in ('meter','piece') or item_unit is null then
      raise exception 'invalid_request_unit'; end if;
    seen := array_append(seen,product);
    insert into public.production_orders(factory_id,request_id,product_id,target_quantity,unit)
      values(f,result_id,product,amount,item_unit);
  end loop;
  return result_id;
end;
$$;

create function public.create_production_request(
  factory uuid,request_name text,request_priority text,request_required_by timestamptz,
  request_notes text,request_items jsonb
) returns uuid language sql security invoker set search_path='' as $$
  select private.create_production_request(factory,request_name,request_priority,request_required_by,request_notes,request_items)
$$;
revoke all on function private.create_production_request(uuid,text,text,timestamptz,text,jsonb),
  public.create_production_request(uuid,text,text,timestamptz,text,jsonb) from public,anon;
grant execute on function public.create_production_request(uuid,text,text,timestamptz,text,jsonb) to authenticated;

-- Keep the existing snapshot contract and add the request headers.
create or replace function public.factory_snapshot(factory uuid default null) returns jsonb language plpgsql security invoker set search_path='' as $$
declare m jsonb;f uuid;fac jsonb;tab text;rows jsonb;data jsonb:='{}';limited text[]:='{}';begin
 select to_jsonb(x) into m from public.memberships x where user_id=auth.uid();
 f:=case when private.is_platform_admin() then $1 when m->>'status'='approved' then (m->>'factory_id')::uuid else $1 end;
 if f is not null then
 if private.is_platform_admin() then perform private.open_platform_factory(f);end if;
 perform private.require_permission(f,'factory','view');
 perform private.record_access(f,'READ');
 select to_jsonb(x) into fac from public.factories x where id=f;
 foreach tab in array array['areas','work_center_categories','production_lines','work_centers','products','production_requests','production_orders','downtime_reasons','status_events','downtime_events','memberships','roles','role_permissions','support_access','audit_logs','oee_observations','production_entries','operator_assignments','work_center_alternatives','work_center_capabilities','daily_targets','user_permissions','production_transfers','production_routing_steps'] loop
 execute format('select coalesce(jsonb_agg(x),''[]'') from (select * from public.%I where factory_id=$1 %s limit 5000) x',tab,case when tab in ('status_events','audit_logs','production_entries','downtime_events') then 'order by created_at desc,id' else '' end) into rows using f;
 data:=data||jsonb_build_object(tab,rows);
 if jsonb_array_length(rows)=5000 then limited:=array_append(limited,tab);end if;
 end loop;
 data:=data||jsonb_build_object('machine_statuses',(select jsonb_agg(x) from public.machine_statuses x where code<>'maintenance'),'permissions',(select jsonb_agg(x) from public.permissions x));
 end if;
 return jsonb_build_object('platformAdmin',private.is_platform_admin(),'factories',case when f is null then private.platform_factories() else '[]'::jsonb end,'factory',fac,'membership',m,'permissions',case when f is null then '{}'::text[] else public.access_matrix(f) end,'tables',data,'supportFactories',(select coalesce(jsonb_agg(x),'[]'::jsonb) from public.support_access x where user_id=auth.uid()),'truncatedTables',limited,'fetchedAt',now());
end$$;
