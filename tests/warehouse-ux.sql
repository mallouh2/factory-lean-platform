-- Disposable localhost only; all commands and audit effects roll back.
begin;
do $$begin
 if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55480 or current_database()<>'factory_lean_quality_local' then raise exception 'Disposable Warehouse test only';end if;
end$$;
select set_config('request.jwt.claim.sub',(select c.x->>'owner' from local_preview.context c),true) is not null;
select set_config('request.jwt.claim.role','authenticated',true) is not null;
create temporary table warehouse_ux_context as select c.x from local_preview.context c;
grant select on warehouse_ux_context to authenticated;
set local role authenticated;
do $$declare x jsonb;f uuid;entry uuid;product uuid;retry uuid;first_result uuid;second_result uuid;before_row jsonb;after_row jsonb;before_source jsonb;mat uuid;begin
 select c.x into x from warehouse_ux_context c;f:=(x->>'factory')::uuid;entry:=(x->>'quality_entry')::uuid;product:=(x->>'product')::uuid;
 select value into before_row from jsonb_array_elements(public.warehouse_inventory(f,1,jsonb_build_object('code','MP'))->'rows')where value->>'id'=product::text;
 before_source:=public.finished_source_stock(f,product,'meter',null,entry);
 retry:=gen_random_uuid();first_result:=public.supply_command(f,'acknowledge_good',jsonb_build_object('entry',entry),retry);
 second_result:=public.supply_command(f,'acknowledge_good',jsonb_build_object('entry',entry),retry);
 if first_result is distinct from second_result then raise exception 'Acknowledgment retry result changed';end if;
 select value into after_row from jsonb_array_elements(public.warehouse_inventory(f,1,jsonb_build_object('code','MP'))->'rows')where value->>'id'=product::text;
 if after_row is distinct from before_row or public.finished_source_stock(f,product,'meter',null,entry) is distinct from before_source then raise exception 'Acknowledgment changed inventory/source';end if;
 raise notice 'PASS acknowledgment and retry never credit stock or sources twice';
 if not exists(select 1 from jsonb_array_elements(public.supply_page(f,'outputs')->'rows')v where v->>'id'=entry::text and (v->>'acknowledged')::boolean) then raise exception 'Acknowledged identifiable stock disappeared';end if;
 raise notice 'PASS physical identification remains separate and reachable after acknowledgment';
 mat:=public.create_warehouse_material(f,jsonb_build_object('name','Warehouse UX resin','code','WV-'||gen_random_uuid(),'unit','kg','inventory_kind','RAW_MATERIAL'),gen_random_uuid());
 select value into before_row from jsonb_array_elements(public.warehouse_inventory(f,1,jsonb_build_object('item_type',jsonb_build_array('RAW_MATERIAL')))->'rows')where value->>'id'=mat::text;
 if before_row->>'on_hand'<>'0' or before_row->>'unit'<>'kg' then raise exception 'Zero material missing or unit wrong';end if;
 raise notice 'PASS zero stock remains visible with its own configured unit';
 retry:=gen_random_uuid();first_result:=public.receive_warehouse_stock(f,mat,'material','kg',10,'external_receipt','LOCAL-WV','',retry);
 second_result:=public.receive_warehouse_stock(f,mat,'material','kg',10,'external_receipt','LOCAL-WV','',retry);
 select value into after_row from jsonb_array_elements(public.warehouse_inventory(f,1,jsonb_build_object('item_type',jsonb_build_array('RAW_MATERIAL')))->'rows')where value->>'id'=mat::text;
 if first_result is distinct from second_result or after_row->>'on_hand'<>'10' or after_row->>'reserved'<>'0' or after_row->>'available'<>'10' or after_row->>'unit'<>'kg' then raise exception 'Receipt stock/reservation conservation';end if;
 raise notice 'PASS existing external receipt retry credits exactly once with correct unit';
end$$;
rollback;
