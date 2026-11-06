begin;
-- Enrich the existing counted request reader; do not add a second queue.
do $projection$declare ddl text;needle text;replacement text;begin
select pg_get_functiondef('public.supply_page(uuid,text,integer,jsonb,uuid)'::regprocedure)into ddl;
needle:='with data as materialized(select * from public.material_requests where factory_id=factory and (private.has_permission(factory,''warehouse'',''view'') or requested_by=auth.uid()))';
replacement:='with data as materialized(select r.*,private.material_progress(factory,r.id)preparation,(select o.code from public.production_orders o where o.factory_id=factory and o.id=r.production_item_id)code,case when r.lot_id is not null then ''lot''when r.product_id is not null then ''product''else ''material''end item_type from public.material_requests r where r.factory_id=factory and (private.has_permission(factory,''warehouse'',''view'') or r.requested_by=auth.uid()))';
if strpos(ddl,needle)=0 then raise exception 'material_projection_contract_changed';end if;execute replace(ddl,needle,replacement);end$projection$;
commit;
