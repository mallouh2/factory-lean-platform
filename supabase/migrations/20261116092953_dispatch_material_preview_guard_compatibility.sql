-- Preserve original source/compound admission and actionable rate guards during read-only dispatch forecasting.
-- No historical migration or operational row changes.
CREATE OR REPLACE FUNCTION private.execution_dispatch_materials(f uuid, i uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.production_orders;stamp timestamptz:=statement_timestamp();occ jsonb;forecast jsonb;rate numeric;setup integer;finish_at timestamptz;row jsonb;free numeric;own numeric;others numeric;rows jsonb:='[]';ready boolean:=true;m public.materials;req jsonb;n integer;typed integer;fastest numeric;begin
 select *into o from public.production_orders where factory_id=f and id=i;
 req:=private.material_requirement_inputs(f,i);
 if req->>'existing_source_work'='true'or req->>'mode'='COMPOUND_STOCK'then return private.material_start_readiness_before_stock(f,i);end if;
 occ:=private.resolve_production_occurrence(f,stamp);if occ->>'available'is distinct from 'true'then return jsonb_build_object('ready',false,'reason','recording_shift_unavailable','rows',rows);end if;
 select count(*),count(*)filter(where c.rate_unit=o.unit),min(c.rate),max(c.rate),max(c.setup_minutes)into n,typed,rate,fastest,setup from public.work_centers w join public.work_center_capabilities c on c.factory_id=w.factory_id and c.work_center_id=w.id and c.product_id=o.product_id where w.factory_id=f and w.line_id=o.line_id and not w.archived;
 if n=0 or typed<>n or rate<=0 or rate<>fastest then return jsonb_build_object('ready',false,'reason','planning_missing_rate','rows',rows);end if;
 finish_at:=private.finish_after_working_minutes(f,stamp,greatest(ceil(private.ordinary_output_remaining(f,i)*60/rate)+coalesce(setup,0),1)::integer);
 forecast:=private.production_stock_forecast(f,i,stamp,occ||jsonb_build_object('dispatch_item',i,'dispatch_start',stamp,'dispatch_finish',finish_at));
 if forecast->>'warning'is not null or coalesce((forecast->>'expected_output')::numeric,0)<=0 then return jsonb_build_object('ready',false,'reason',coalesce(forecast->>'warning','production_stock_schedule_required'),'rows',rows);end if;
 for row in select value from jsonb_array_elements(forecast->'inputs')loop
  select *into m from public.materials where factory_id=f and id=(row->>'id')::uuid;
  select coalesce(sum(r.reserved)filter(where r.item_id<>i),0),coalesce(sum(r.reserved)filter(where r.item_id=i),0)into others,own
   from private.production_stock_reservations r where r.factory_id=f and r.material_id=m.id and r.occurrence_key=occ#>>'{occurrence,occurrence_key}';
  free:=greatest(private.production_stock_quantity(f,m.id)-private.production_stock_return_pending(f,m.id)-others,0);
  if (row->>'quantity')::numeric>free then ready:=false;end if;
  rows:=rows||jsonb_build_array(jsonb_build_object('id',m.id,'name',m.name,'name_ar',m.name_ar,'unit',m.unit,'required',row->>'quantity','reserved',trim_scale(own)::text,'reserved_other',trim_scale(others)::text,'available_for_order',trim_scale(free)::text,'missing',trim_scale(greatest((row->>'quantity')::numeric-free,0))::text));
 end loop;return jsonb_build_object('ready',ready,'reason',case when not ready then 'production_stock_shortage'end,'rows',rows,'required_output',forecast->>'expected_output','occurrence',forecast->'occurrence');
end$function$;
