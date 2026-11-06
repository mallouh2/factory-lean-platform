-- Read-only Planning metadata, independent of the legacy source-decision pages.
-- No stock, scheduling, permission or activation behavior is changed.
begin;
create function public.manufactured_planning_work_read(factory uuid, after_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare all_work jsonb; rows jsonb; total integer; begin
 perform private.require_permission(factory,'factory','view');
 perform private.require_permission(factory,'orders','view');
 if not private.manufactured_output_enabled(factory) then
  return jsonb_build_object('available',false,'work','[]'::jsonb,'total',0,'context_hash','disabled','has_more',false);
 end if;
 select coalesce(jsonb_agg(to_jsonb(z) order by z.item_id),'[]'::jsonb) into all_work from (
  select w.item_id,w.choice,w.origin_item_id,src.code origin_code,w.demand_item_id,d.code demand_code,
   private.output_work_held(factory,w.item_id) held,private.output_work_retired(factory,w.item_id) retired,
   (select coalesce(jsonb_agg(l.id order by l.id),'[]'::jsonb) from public.production_lines l
    where l.factory_id=factory and not l.archived and private.output_work_line(factory,w.item_id,l.id)) capable_lines
  from private.manufactured_completion_work w
  join public.production_orders o on o.factory_id=w.factory_id and o.id=w.item_id
  join public.production_orders src on src.factory_id=w.factory_id and src.id=w.origin_item_id
  left join public.production_orders d on d.factory_id=w.factory_id and d.id=w.demand_item_id
  where w.factory_id=factory and o.status in ('planned','active')
 ) z;
 total:=jsonb_array_length(all_work);
 select coalesce(jsonb_agg(value order by value->>'item_id'),'[]'::jsonb) into rows from (
  select value from jsonb_array_elements(all_work) where after_id is null or (value->>'item_id')::uuid>after_id
  order by (value->>'item_id')::uuid limit 100
 ) page;
 return jsonb_build_object('available',true,'work',rows,'total',total,'context_hash',md5(all_work::text),
  'has_more',exists(select 1 from jsonb_array_elements(all_work) where jsonb_array_length(rows)>0 and (value->>'item_id')::uuid>(rows->-1->>'item_id')::uuid));
end $$;
revoke all on function public.manufactured_planning_work_read(uuid,uuid) from public,anon,service_role;
grant execute on function public.manufactured_planning_work_read(uuid,uuid) to authenticated;
comment on function public.manufactured_planning_work_read(uuid,uuid) is 'Protected active manufactured-work metadata for unified Planning; read-only, keyset-paginated and context-checked.';
notify pgrst,'reload schema';
commit;
