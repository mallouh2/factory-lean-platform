-- Requests without a deliberate priority use Normal in this development dataset.
update public.production_requests set priority='normal' where priority='unspecified';
alter table public.production_requests alter column priority set default 'normal';
alter table public.production_requests drop constraint production_requests_priority_check;
alter table public.production_requests add constraint production_requests_priority_check
  check (priority in ('low','normal','high','urgent'));

create or replace function private.create_production_request(
  f uuid,request_name text,request_priority text,request_required_by timestamptz,
  request_notes text,request_items jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid; entry jsonb; product uuid; amount numeric; item_unit text;
  seen uuid[] := '{}'; actor_name text;
begin
  perform private.require_permission(f,'orders','create');
  if length(btrim(coalesce(request_name,''))) not between 1 and 200 then
    raise exception 'request_name_required'; end if;
  if coalesce(request_priority,'normal') not in ('low','normal','high','urgent') then
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
    coalesce(request_priority,'normal'),request_required_by,coalesce(request_notes,'')
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
