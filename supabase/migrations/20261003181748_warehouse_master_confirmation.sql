-- Catalogue reads never manufacture demand. Warehouse explicitly confirms Min/Max decisions.
alter table public.materials add column minimum_stock numeric, add column maximum_stock numeric,
 add constraint material_stock_limits check (
 (minimum_stock is null or (minimum_stock>=0 and minimum_stock::text not in ('NaN','Infinity','-Infinity')))
 and (maximum_stock is null or (maximum_stock>0 and maximum_stock::text not in ('NaN','Infinity','-Infinity')))
 and (minimum_stock is null or maximum_stock is null or maximum_stock>=minimum_stock));
alter table public.products drop constraint product_stock_configuration;
alter table public.products add constraint product_stock_configuration check (
 (minimum_stock is null or (minimum_stock>=0 and minimum_stock::text not in ('NaN','Infinity','-Infinity')))
 and (maximum_stock is null or (maximum_stock>0 and maximum_stock::text not in ('NaN','Infinity','-Infinity')))
 and (minimum_stock is null or maximum_stock is null or maximum_stock>=minimum_stock)
 and (supply_mode='MAKE_TO_ORDER' or (stock_unit is not null and minimum_stock is not null)));

-- Retained as a compatibility hook for existing Sales/receipt/dispatch/production callers.
-- Detection is read-only. Never create, resize or cancel a confirmed stock request here.
create or replace function private.replenish_finished(f uuid,p uuid) returns void
language plpgsql security definer set search_path='' as $$begin return;end$$;

create or replace function private.fulfillment_production(f uuid,p uuid,u text,q numeric,kind text,l uuid,due timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$declare r uuid;i uuid;begin
 if kind is distinct from 'SALES_PRODUCTION' then raise exception 'warehouse_confirmation_required';end if;
 if not exists(select 1 from public.products where factory_id=f and id=p and supply_source='MANUFACTURED') then raise exception 'fulfillment_source_decision';end if;
 insert into public.production_requests(factory_id,code,name,requested_by,requested_by_name,priority,required_by,request_type,sales_order_line_id)
 values(f,'','Sales production',auth.uid(),(select display_name from public.memberships where factory_id=f and user_id=auth.uid()),
 case when due is not null then 'high' else 'normal' end,due,kind,l) returning id into r;
 insert into public.production_orders(factory_id,request_id,product_id,target_quantity,unit) values(f,r,p,q,u) returning id into i;
 return i;
end$$;

-- Shared batched projection: identical to the existing projected_finished formula.
create function private.finished_inventory_projection(f uuid,excluding uuid default null)
returns table(product_id uuid,unit text,on_hand numeric,reserved numeric,incoming numeric,projected numeric)
language sql stable security definer set search_path='' as $$
 with keys as (
 select p.id product_id,p.stock_unit unit from public.products p where p.factory_id=f and p.stage='finished'
 union select b.product_id,b.unit from public.finished_goods_balances b where b.factory_id=f
 union select o.product_id,o.unit from public.production_orders o where o.factory_id=f and o.status in ('planned','active')
 union select l.product_id,l.unit from public.sales_order_lines l where l.factory_id=f
 ), incoming as (
 select o.product_id,o.unit,sum(o.remaining_quantity) q from public.production_orders o
 where o.factory_id=f and o.status in ('planned','active') and o.id is distinct from excluding group by o.product_id,o.unit
 ), allocations as (
 select a.line_id,sum(a.quantity) q from public.sales_incoming_allocations a where a.factory_id=f group by a.line_id
 ), committed as (
 select l.product_id,l.unit,sum(a.q) q from allocations a join public.sales_order_lines l on l.id=a.line_id group by l.product_id,l.unit
 ), uncovered as (
 select l.product_id,l.unit,sum(greatest(l.quantity-l.dispatched_quantity-coalesce(r.quantity,0)-coalesce(a.q,0),0)) q
 from public.sales_order_lines l join public.sales_orders s on s.id=l.order_id
 left join public.finished_goods_reservations r on r.line_id=l.id left join allocations a on a.line_id=l.id
 where l.factory_id=f and s.status='approved' group by l.product_id,l.unit
 )
 select k.product_id,k.unit,coalesce(b.on_hand,0),coalesce(b.reserved,0),coalesce(i.q,0),
 coalesce(b.on_hand-b.reserved,0)+coalesce(i.q,0)-coalesce(c.q,0)-coalesce(d.q,0)
 from keys k left join public.finished_goods_balances b on b.factory_id=f and b.product_id=k.product_id and b.unit=k.unit
 left join incoming i on i.product_id=k.product_id and i.unit=k.unit
 left join committed c on c.product_id=k.product_id and c.unit=k.unit
 left join uncovered d on d.product_id=k.product_id and d.unit=k.unit;
$$;
create or replace function private.projected_finished(f uuid,p uuid,u text,excluding uuid default null) returns numeric
language sql stable security definer set search_path='' as $$
 select coalesce((select x.projected from private.finished_inventory_projection(f,excluding) x where x.product_id=p and x.unit=u),0);
$$;

create function private.warehouse_inventory_rows(f uuid) returns setof jsonb
language sql stable security definer set search_path='' as $$
 with stock_requests as (
 select distinct o.product_id,o.unit from public.production_orders o join public.production_requests r on r.id=o.request_id
 where o.factory_id=f and o.status in ('planned','active') and r.request_type='STOCK_REPLENISHMENT'
 ), material_stock as (
 select material_id,sum(quantity) q from public.inventory_transactions where factory_id=f group by material_id
 ), material_reserved as (
 select material_id,sum(quantity) q from public.inventory_reservations where factory_id=f and released_at is null group by material_id
 ), base as (
 select p.id,'finished'::text entity,p.name,p.name_ar,p.code,'FINISHED_GOOD'::text item_type,p.supply_source,x.unit,
 x.on_hand,x.reserved,x.on_hand-x.reserved available,x.incoming,x.projected,
 case when x.unit=p.stock_unit then p.minimum_stock end minimum_stock,
 case when x.unit=p.stock_unit then p.maximum_stock end maximum_stock,
 (r.product_id is not null) already_requested
 from public.products p join private.finished_inventory_projection(f) x on x.product_id=p.id
 left join stock_requests r on r.product_id=p.id and r.unit=x.unit
 where p.factory_id=f and p.stage='finished'
 union all
 select m.id,'material',m.name,m.name_ar,m.code,m.inventory_kind,'EXTERNAL',m.unit,
 coalesce(s.q,0),coalesce(r.q,0),coalesce(s.q,0)-coalesce(r.q,0),null::numeric,coalesce(s.q,0)-coalesce(r.q,0),
 m.minimum_stock,m.maximum_stock,false
 from public.materials m left join material_stock s on s.material_id=m.id left join material_reserved r on r.material_id=m.id
 where m.factory_id=f
 ), detected as (
 select b.*,case when minimum_stock is null then 'NOT_CONFIGURED' when projected<=minimum_stock then 'AT_OR_BELOW_MIN' else 'ABOVE_MIN' end minimum_status,
 case when maximum_stock is not null then greatest(maximum_stock-projected,0) end suggested_quantity,
 exists(select 1 from public.fulfillment_commands c where c.factory_id=f and c.operation='warehouse_external'
 and c.result_id=b.id and c.payload->>'unit'=b.unit and (c.payload->>'projected')::numeric=b.projected) external_chosen
 from base b
 )
 select to_jsonb(d)||jsonb_build_object('row_key',entity||':'||id||':'||coalesce(unit,''),
 'replenishment_status',case when already_requested then 'ALREADY_REQUESTED'
 when minimum_status='AT_OR_BELOW_MIN' then case when supply_source='EXTERNAL' or external_chosen then 'EXTERNAL_REQUIRED'
 when supply_source='BOTH' then 'SOURCING_REQUIRED' else 'PRODUCTION_REQUIRED' end
 when incoming>0 then 'INCOMING' else 'OK' end,
 'can_produce',entity='finished' and unit is not null and minimum_status='AT_OR_BELOW_MIN'
 and not already_requested and supply_source in ('MANUFACTURED','BOTH') and (suggested_quantity is null or suggested_quantity>0))
 from detected d;
$$;

create function private.warehouse_filter_matches(row_data jsonb,filters jsonb) returns boolean
language plpgsql immutable set search_path='' as $$
declare k text;v jsonb;n numeric;op text;a numeric;b numeric;matched boolean:=true;begin
 if jsonb_typeof(filters) is distinct from 'object' or octet_length(filters::text)>12000 then raise exception 'fulfillment_invalid';end if;
 for k,v in select * from jsonb_each(filters) loop
 if k in ('name','code') then
  if jsonb_typeof(v)<>'string' or length(v#>>'{}')>200 then raise exception 'fulfillment_invalid';end if;
  if strpos(lower(coalesce(row_data->>k,'')||case when k='name' then ' '||coalesce(row_data->>'name_ar','') else '' end),lower(v#>>'{}'))=0 then matched:=false;end if;
 elsif k in ('item_type','supply_source','unit','minimum_status','replenishment_status') then
  if jsonb_typeof(v)<>'array' or jsonb_array_length(v)>100 then raise exception 'fulfillment_invalid';end if;
  if jsonb_array_length(v)>0 and not v @> jsonb_build_array(coalesce(row_data->>k,'NOT_CONFIGURED')) then matched:=false;end if;
 elsif k in ('on_hand','reserved','available','incoming','projected','minimum_stock','maximum_stock') then
  if jsonb_typeof(v)<>'object' then raise exception 'fulfillment_invalid';end if;
  op:=v->>'op';n:=(row_data->>k)::numeric;
  if op='configured' then if n is null then matched:=false;end if;
  elsif op='not_configured' then if n is not null then matched:=false;end if;
  elsif op='positive' then if n is null or n<=0 then matched:=false;end if;
  else
   if op not in ('eq','gt','lt','range') or op is null or jsonb_typeof(v->'value') is distinct from 'number' then raise exception 'fulfillment_invalid';end if;
   a:=(v->>'value')::numeric;b:=(v->>'to')::numeric;
   if op='range' and (b is null or b<a) then raise exception 'fulfillment_invalid';end if;
   if n is null or (op='eq' and n<>a) or (op='gt' and n<=a) or (op='lt' and n>=a) or (op='range' and (n<a or n>b)) then matched:=false;end if;
  end if;
 else raise exception 'fulfillment_invalid';end if;
 end loop;return matched;
end$$;

create function public.warehouse_inventory(factory uuid,page integer default 1,filters jsonb default '{}',sort text default 'name',direction text default 'asc')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;begin
 perform private.require_permission(factory,'warehouse','view');
 if page is null or page not between 1 and 1000000 or direction not in ('asc','desc') or direction is null
 or sort is null or sort not in ('name','code','item_type','supply_source','unit','on_hand','reserved','available','incoming','projected','minimum_stock','maximum_stock','minimum_status','replenishment_status') then raise exception 'fulfillment_invalid';end if;
 -- Validate filter shape even for an empty catalogue.
 perform private.warehouse_filter_matches('{}',filters);
 with all_rows as materialized(select value r from private.warehouse_inventory_rows(factory) value),
 filtered as materialized(select r from all_rows where private.warehouse_filter_matches(r,filters)),
 ordered as (
 select r,row_number() over(order by
 case when direction='asc' and sort in ('on_hand','reserved','available','incoming','projected','minimum_stock','maximum_stock') then (r->>sort)::numeric end asc nulls last,
 case when direction='desc' and sort in ('on_hand','reserved','available','incoming','projected','minimum_stock','maximum_stock') then (r->>sort)::numeric end desc nulls last,
 case when direction='asc' and sort not in ('on_hand','reserved','available','incoming','projected','minimum_stock','maximum_stock') then lower(r->>sort) end asc nulls last,
 case when direction='desc' and sort not in ('on_hand','reserved','available','incoming','projected','minimum_stock','maximum_stock') then lower(r->>sort) end desc nulls last,
 r->>'row_key') pos from filtered
 )
 select jsonb_build_object('rows',coalesce((select jsonb_agg(r order by pos) from ordered where pos between (page-1)*50+1 and page*50),'[]'),
 'total',(select count(*) from filtered),'units',(select coalesce(jsonb_agg(u),'[]') from(select distinct coalesce(r->>'unit','NOT_CONFIGURED') u from all_rows order by u limit 100)x)) into result;
 return result;
end$$;

-- An unforgeable, protected command ledger proves Warehouse confirmation at insertion.
create function private.guard_confirmed_replenishment() returns trigger
language plpgsql security definer set search_path='' as $$begin
 if new.request_type='STOCK_REPLENISHMENT' and not exists(
 select 1 from public.fulfillment_commands c where c.factory_id=new.factory_id and c.result_id=new.id
 and c.actor_id=new.requested_by and c.operation='warehouse_produce') then raise exception 'warehouse_confirmation_required';end if;
 return new;
end$$;
create trigger stock_confirmation_guard before insert on public.production_requests
 for each row execute function private.guard_confirmed_replenishment();

create function public.confirm_warehouse_replenishment(factory uuid,product uuid,action text,unit text,projected numeric,quantity numeric,request_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare prod public.products;level numeric;q numeric;existing uuid;result uuid;payload jsonb;begin
 perform private.require_permission(factory,'warehouse','edit');
 if request_id is null or action is null or action not in ('produce','external') then raise exception 'fulfillment_invalid';end if;
 payload:=jsonb_build_object('product',product,'action',action,'unit',unit,'projected',projected,'quantity',quantity);
 result:=private.fulfillment_retry(factory,request_id,'warehouse_'||action,payload);if result is not null then return result;end if;
 select * into prod from public.products p where p.factory_id=factory and p.id=product and p.stage='finished' for update;
 if not found or unit is distinct from prod.stock_unit or unit is null or prod.minimum_stock is null then raise exception 'fulfillment_product';end if;
 if (action='produce' and prod.supply_source not in ('MANUFACTURED','BOTH')) or (action='external' and prod.supply_source<>'BOTH') then raise exception 'fulfillment_source_decision';end if;
 select o.request_id into existing from public.production_orders o join public.production_requests r on r.id=o.request_id
 where o.factory_id=factory and o.product_id=product and o.unit=confirm_warehouse_replenishment.unit
 and o.status in ('planned','active') and r.request_type='STOCK_REPLENISHMENT' order by o.created_at,o.id limit 1;
 if existing is not null then
  if action='external' then raise exception 'warehouse_stock_changed';end if;
  insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'warehouse_produce',payload,existing,clock_timestamp());return existing;
 end if;
 level:=private.projected_finished(factory,product,unit);
 if projected is distinct from level or level>prod.minimum_stock then raise exception 'warehouse_stock_changed';end if;
 if action='external' then result:=product;
 else
  q:=case when prod.maximum_stock is not null then prod.maximum_stock-level else quantity end;
  if q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity') or quantity is distinct from q then raise exception 'fulfillment_invalid';end if;
  result:=gen_random_uuid();
 end if;
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'warehouse_'||action,payload,result,clock_timestamp());
 if action='produce' then
  insert into public.production_requests(id,factory_id,code,name,requested_by,requested_by_name,priority,notes,request_type)
  values(result,factory,'','Stock replenishment',auth.uid(),(select display_name from public.memberships where factory_id=factory and user_id=auth.uid()),'low',
  'Warehouse confirmed; projected='||level||'; minimum='||prod.minimum_stock||'; maximum='||coalesce(prod.maximum_stock::text,'not configured')||'; quantity='||q,'STOCK_REPLENISHMENT');
  insert into public.production_orders(factory_id,request_id,product_id,target_quantity,unit) values(factory,result,product,q,unit);
 end if;return result;
end$$;

create function public.configure_warehouse_material(factory uuid,material uuid,minimum numeric,maximum numeric) returns uuid
language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(factory,'warehouse','edit');perform private.fulfillment_lock(factory);
 update public.materials set minimum_stock=minimum,maximum_stock=maximum where factory_id=factory and id=material;
 if not found then raise exception 'fulfillment_product';end if;return material;
end$$;
revoke all on function private.finished_inventory_projection(uuid,uuid),private.warehouse_inventory_rows(uuid),private.warehouse_filter_matches(jsonb,jsonb),private.guard_confirmed_replenishment() from public,anon,authenticated;
revoke all on function public.warehouse_inventory(uuid,integer,jsonb,text,text),public.confirm_warehouse_replenishment(uuid,uuid,text,text,numeric,numeric,uuid),public.configure_warehouse_material(uuid,uuid,numeric,numeric) from public,anon;
grant execute on function public.warehouse_inventory(uuid,integer,jsonb,text,text),public.confirm_warehouse_replenishment(uuid,uuid,text,text,numeric,numeric,uuid),public.configure_warehouse_material(uuid,uuid,numeric,numeric) to authenticated;
