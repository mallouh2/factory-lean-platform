-- Manual demand keeps the existing explicit per-person orders:create authority.
-- No legacy origin, reason or creator is inferred or backfilled.
alter table public.production_requests drop constraint production_requests_request_type_check;
alter table public.production_requests add constraint production_requests_request_type_check
 check(request_type in ('SALES_PRODUCTION','STOCK_REPLENISHMENT','INTERNAL_PRODUCTION'));
alter table public.production_requests add constraint internal_production_identity_reason
 check(request_type is distinct from 'INTERNAL_PRODUCTION' or
 (requested_by is not null and nullif(btrim(requested_by_name),'') is not null
 and notes ~ '\S' and length(notes)<=2000 and sales_order_line_id is null));

create or replace function private.create_production_request(
 f uuid,request_name text,request_priority text,request_required_by timestamptz,
 request_notes text,request_items jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid; entry jsonb; product uuid; amount numeric; item_unit text;
 seen uuid[] := '{}'; actor_name text; internal_reason text;
begin
 perform private.require_permission(f,'orders','create');
 perform pg_advisory_xact_lock(hashtextextended(f::text||':structure',0));
 if length(btrim(coalesce(request_name,''))) not between 1 and 200 then
  raise exception 'request_name_required';end if;
 if coalesce(request_priority,'normal') not in ('low','normal','high','urgent') then
  raise exception 'invalid_priority';end if;
 internal_reason:=regexp_replace(coalesce(request_notes,''),'^\s+|\s+$','','g');
 if internal_reason='' then raise exception 'internal_reason_required';end if;
 if length(internal_reason)>2000 then raise exception 'invalid_notes';end if;
 if jsonb_typeof(request_items) is distinct from 'array' or jsonb_array_length(request_items) not between 1 and 100 then
  raise exception 'request_items_required';end if;
 select m.display_name into actor_name from public.memberships m
  where m.factory_id=f and m.user_id=auth.uid() and m.status='approved';
 actor_name:=coalesce(nullif(btrim(actor_name),''),(select split_part(u.email,'@',1) from auth.users u where u.id=auth.uid()));
 insert into public.production_requests(factory_id,code,name,requested_by,requested_by_name,priority,required_by,notes,request_type,created_at)
 values(f,'',btrim(request_name),auth.uid(),actor_name,coalesce(request_priority,'normal'),request_required_by,internal_reason,'INTERNAL_PRODUCTION',clock_timestamp())
 returning id into result_id;
 for entry in select value from jsonb_array_elements(request_items) loop
  if jsonb_typeof(entry) is distinct from 'object' or exists(select 1 from jsonb_object_keys(entry) k where k not in ('product_id','quantity','unit')) then
   raise exception 'invalid_request_item';end if;
  product:=nullif(entry->>'product_id','')::uuid;amount:=nullif(entry->>'quantity','')::numeric;item_unit:=entry->>'unit';
  if product is null or not exists(select 1 from public.products p where p.factory_id=f and p.id=product) then
   raise exception 'invalid_request_product';end if;
  if product=any(seen) then raise exception 'duplicate_request_product';end if;
  if amount is null or amount<=0 or amount::text in ('NaN','Infinity','-Infinity') then raise exception 'invalid_request_quantity';end if;
  if item_unit is null or item_unit not in ('meter','piece') then raise exception 'invalid_request_unit';end if;
  seen:=array_append(seen,product);
  insert into public.production_orders(factory_id,request_id,product_id,target_quantity,unit)
   values(f,result_id,product,amount,item_unit);
 end loop;
 return result_id;
end;
$$;
-- Public wrapper retains its six-argument contract; it cannot accept a type or creator.
revoke all on function private.create_production_request(uuid,text,text,timestamptz,text,jsonb) from public,anon,authenticated;

create function private.guard_request_origin() returns trigger language plpgsql set search_path='' as $$begin
 if (new.request_type,new.requested_by,new.requested_by_name,new.created_at,new.sales_order_line_id)
  is distinct from (old.request_type,old.requested_by,old.requested_by_name,old.created_at,old.sales_order_line_id)
  or (old.request_type='INTERNAL_PRODUCTION' and new.notes is distinct from old.notes) then
  raise exception 'request_origin_immutable';end if;
 return new;
end$$;
create trigger guard_request_origin before update on public.production_requests
 for each row execute function private.guard_request_origin();
revoke all on function private.guard_request_origin() from public,anon,authenticated;
