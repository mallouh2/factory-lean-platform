-- Preserve existing compound-only kg stock ownership in manual purchases.
create or replace function private.warehouse_inventory_purchase(factory uuid,payload jsonb,request_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid;old uuid;target uuid;mat uuid;prod uuid;u text;configured text;label text;kind text;q numeric;
 actor_name text;context jsonb;specification text;
begin
 perform private.require_permission(factory,'factory','view');
 perform private.require_permission(factory,'warehouse','edit');
 old:=private.fulfillment_retry(factory,request_id,'supply_purchase_inventory',payload);
 if old is not null then return old;end if;
 target:=(payload->>'item')::uuid;
 select m.id,m.name,m.unit into mat,label,configured from public.materials m where m.factory_id=factory and m.id=target;
 if not found then
  select p.id,p.name,p.stock_unit,p.product_kind into prod,label,configured,kind
   from public.products p where p.factory_id=factory and p.id=target and p.stage='finished';
  if not found then raise exception 'supply_invalid';end if;
 end if;
 u:=coalesce(nullif(btrim(payload->>'unit'),''),configured,'piece');
 q:=(payload->>'quantity')::numeric;specification:=btrim(coalesce(payload->>'details',''));
 if q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity') or length(specification)>4000
  or (configured is not null and u<>configured)
  or (configured is null and (u not in ('piece','meter','kg') or (kind='MANUFACTURED_INTERMEDIATE' and u<>'kg')))
  or (prod is not null and kind <> 'MANUFACTURED_INTERMEDIATE' and u='kg')
  or length(u) not between 1 and 50 then raise exception 'supply_invalid';end if;
 if exists(select 1 from public.purchase_requisitions r where r.factory_id=factory and r.unit=u
  and (r.material_id=mat or r.product_id=prod) and r.status not in ('RECEIVED','REJECTED','CANCELLED')) then raise exception 'supply_duplicate';end if;
 actor_name:=coalesce((select display_name from public.memberships where factory_id=factory and user_id=auth.uid() and status='approved'),'');
 select value into context from private.warehouse_inventory_rows(factory) value where value->>'id'=target::text;
 insert into public.purchase_requisitions(factory_id,material_id,product_id,item_name,quantity,unit,details,source_context,requested_by,requested_by_name,stock_context)
  values(factory,mat,prod,label,q,u,specification,'Warehouse',auth.uid(),actor_name,coalesce(context,'{}'::jsonb)||jsonb_build_object('manual_purchase',true)) returning id into result;
 perform private.supply_event(factory,result,'');
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'supply_purchase_inventory',payload,result,clock_timestamp());
 return result;
end$$;
revoke all on function private.warehouse_inventory_purchase(uuid,jsonb,uuid) from public,anon,authenticated;

