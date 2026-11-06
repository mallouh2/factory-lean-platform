begin;
-- Physical stored stock only. Never infer operations from remaining_work text.
-- Unknown provenance stays separate; canonical operation IDs and restrictions
-- define compatibility, not a display name or a storage location.
create or replace function public.warehouse_stored_unfinished(factory uuid,page integer default 1) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare result jsonb;begin
 perform private.require_permission(factory,'warehouse','view');
 if page not between 1 and 1000000 then raise exception 'invalid_input';end if;
 with lots as materialized (
  select p.id product_id,p.name,p.name_ar,e.unit,l.id lot_id,l.warehouse_quantity,
   case when l.reserved_quality_rejection_id is not null then l.warehouse_quantity else a.reserved end reserved,
   l.reserved_quality_rejection_id is not null quality_reserved,private.output_source_held(factory,l.source_entry_id) held,
   coalesce(m.classification->>'restriction','') restriction,
   coalesce(ops.operations,'[]'::jsonb) operations,
   m.lot_id is not null and jsonb_array_length(coalesce(ops.operations,'[]'::jsonb))>0 and coalesce(ops.resolved,false) classification_available
  from public.unfinished_lots l join public.production_entries e on e.factory_id=factory and e.id=l.source_entry_id
  join public.production_orders o on o.factory_id=factory and o.id=e.order_id
  join public.products p on p.factory_id=factory and p.id=o.product_id
  left join private.manufactured_output_lots m on m.factory_id=factory and m.lot_id=l.id
  left join private.manufactured_outputs h on h.factory_id=factory and h.id=m.output_id
  cross join lateral private.output_work_allocations(factory,l.id) a
  left join lateral (
   select jsonb_agg(jsonb_build_object('id',id,'name',labels->id->>'name','name_ar',labels->id->>'name_ar')order by id) operations,
    bool_and(nullif(labels->id->>'name','')is not null) resolved
   from (select distinct value id from jsonb_array_elements_text(coalesce(m.classification->'missing_operations','[]'::jsonb))) ids
   cross join lateral(select private.output_operation_labels(factory,h.operation_snapshot)labels)labelled
  )ops on true
  where l.factory_id=factory and l.warehouse_quantity>0
 ),grouped as (
  select product_id,name,name_ar,unit,operations,restriction,held,quality_reserved,classification_available,
   case when classification_available then null else lot_id end unresolved_source,
   sum(warehouse_quantity)on_hand,sum(reserved)reserved,sum(case when held then 0 else warehouse_quantity-reserved end)available
  from lots group by product_id,name,name_ar,unit,operations,restriction,held,quality_reserved,classification_available,case when classification_available then null else lot_id end
 ),rows as (
  select md5(jsonb_build_array(product_id,unit,operations,restriction,held,quality_reserved,unresolved_source)::text)row_key,
   product_id,name,name_ar,unit,'UNFINISHED'::text item_type,operations missing_operations,restriction,classification_available,
   trim_scale(on_hand)::text on_hand,trim_scale(reserved)::text reserved,trim_scale(available)::text available,held,quality_reserved
  from grouped
 )select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(r))from(select * from rows order by name,product_id,unit,row_key offset(page-1)*50 limit 50)r),'[]'::jsonb),
  'total',(select count(*)from rows),'classification_unavailable',(select count(*)from rows where not classification_available))into result;
 return result;
end$$;
-- CREATE OR REPLACE preserves the existing authenticated-only execution grant.
commit;
