-- Forward validation correction. Applied domain migration remains byte-for-byte unchanged.
alter function public.supply_command(uuid,text,jsonb,uuid) set schema private;
alter function private.supply_command(uuid,text,jsonb,uuid) rename to apply_supply_command;
revoke all on function private.apply_supply_command(uuid,text,jsonb,uuid) from public,anon,authenticated;
create function public.supply_command(factory uuid,action text,payload jsonb,request_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$declare allowed text[];begin
 perform private.require_permission(factory,'factory','view');
 allowed:=case action
  when 'purchase_manual' then array['item_name','quantity','unit','details','notes','source_context']
  when 'purchase_stock' then array['item','quantity','unit','projected','notes']
  when 'purchase_change' then array['id','revision','action','reason','supplier_id']
  when 'receive_purchase' then array['id','revision','reason']
  when 'supplier_save' then array['id','name','primary_contact','phone','email','notes','active','category','relationship','replace_primary']
  when 'material_request' then array['item','item_type','quantity','unit','note','production_item_id']
  when 'material_change' then array['id','revision','action','reason']
  when 'receive_wip' then array['lot','quantity'] when 'acknowledge_good' then array['entry'] end;
 if allowed is null or jsonb_typeof(payload) is distinct from 'object' or request_id is null then raise exception 'supply_invalid';end if;
 if exists(select 1 from jsonb_object_keys(payload) k where not k=any(allowed)) then raise exception 'supply_invalid';end if;
 if action='supplier_save' and (length(coalesce(payload->>'primary_contact',''))>200 or length(coalesce(payload->>'category',''))>120) then raise exception 'supply_invalid';end if;
 return private.apply_supply_command(factory,action,payload,request_id);
end$$;
revoke all on function public.supply_command(uuid,text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.supply_command(uuid,text,jsonb,uuid) to authenticated;

alter function public.define_manufactured_product(uuid,uuid,jsonb,jsonb,uuid) set schema private;
alter function private.define_manufactured_product(uuid,uuid,jsonb,jsonb,uuid) rename to apply_product_definition;
revoke all on function private.apply_product_definition(uuid,uuid,jsonb,jsonb,uuid) from public,anon,authenticated;
create function public.define_manufactured_product(factory uuid,product uuid,payload jsonb,components jsonb,request_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(factory,'orders',case when product is null then 'create' else 'edit' end);
 if jsonb_typeof(payload) is distinct from 'object' or request_id is null
  or (payload->>'product_kind'='MANUFACTURED_INTERMEDIATE' and payload->>'formula_product_id' is not null)
  or (components is not null and jsonb_typeof(components) is distinct from 'array') then raise exception 'supply_invalid';end if;
 if components is not null and exists(select 1 from jsonb_array_elements(components) c where jsonb_typeof(c)<>'object' or exists(select 1 from jsonb_object_keys(c) k where k not in ('material_id','quantity','unit'))) then raise exception 'supply_invalid';end if;
 return private.apply_product_definition(factory,product,payload,components,request_id);
end$$;
revoke all on function public.define_manufactured_product(uuid,uuid,jsonb,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.define_manufactured_product(uuid,uuid,jsonb,jsonb,uuid) to authenticated;

create function private.guard_formula_identity() returns trigger language plpgsql security definer set search_path='' as $$begin
 perform private.fulfillment_lock(new.factory_id);
 if (new.product_kind is distinct from 'MANUFACTURED_INTERMEDIATE' or new.stock_unit is distinct from 'kg')
  and (exists(select 1 from public.products p where p.factory_id=old.factory_id and p.formula_product_id=old.id)
   or exists(select 1 from public.bom_versions b where b.factory_id=old.factory_id and b.product_id=old.id and b.output_unit='kg')) then raise exception 'supply_state';end if;
 return new;
end$$;
create trigger product_formula_identity before update of product_kind,stock_unit on public.products for each row execute function private.guard_formula_identity();
revoke all on function private.guard_formula_identity() from public,anon,authenticated;
