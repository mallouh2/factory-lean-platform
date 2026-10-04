-- Explicit Warehouse purchasing is separate from unchanged Min/Max replenishment.
-- Optional specifications apply only to known stock identities; free-text purchases retain their specification requirement.
alter table public.purchase_requisitions drop constraint purchase_requisitions_check1;
alter table public.purchase_requisitions add constraint purchase_requisitions_check1 check (
 length(btrim(item_name)) between 1 and 200 and length(btrim(unit)) between 1 and 50
 and length(btrim(details))<=4000
 and (num_nonnulls(material_id,product_id)=1 or length(btrim(details))>=1)
);

create function private.warehouse_inventory_purchase(factory uuid,payload jsonb,request_id uuid) returns uuid
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

create or replace function public.supply_command(factory uuid,action text,payload jsonb,request_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$declare allowed text[];begin
 perform private.require_permission(factory,'factory','view');
 allowed:=case action
  when 'purchase_manual' then array['item_name','quantity','unit','details','notes','source_context']
  when 'purchase_stock' then array['item','quantity','unit','projected','notes']
  when 'purchase_inventory' then array['item','quantity','unit','details']
  when 'purchase_change' then array['id','revision','action','reason','supplier_id']
  when 'receive_purchase' then array['id','revision','reason']
  when 'supplier_save' then array['id','name','primary_contact','phone','email','notes','active','category','relationship','replace_primary']
  when 'material_request' then array['item','item_type','quantity','unit','note','production_item_id']
  when 'material_change' then array['id','revision','action','reason']
  when 'receive_wip' then array['lot','quantity'] when 'acknowledge_good' then array['entry'] end;
 if allowed is null or jsonb_typeof(payload) is distinct from 'object' or request_id is null or octet_length(payload::text)>30000 then raise exception 'supply_invalid';end if;
 if exists(select 1 from jsonb_object_keys(payload) k where not k=any(allowed)) then raise exception 'supply_invalid';end if;
 if action='supplier_save' and (length(coalesce(payload->>'primary_contact',''))>200 or length(coalesce(payload->>'category',''))>120) then raise exception 'supply_invalid';end if;
 if action='purchase_inventory' then return private.warehouse_inventory_purchase(factory,payload,request_id);end if;
 return private.apply_supply_command(factory,action,payload,request_id);
end$$;
revoke all on function public.supply_command(uuid,text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.supply_command(uuid,text,jsonb,uuid) to authenticated;
