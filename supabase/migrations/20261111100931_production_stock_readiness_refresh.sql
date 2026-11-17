-- Preserve the existing atomic reservation engine and legacy-custody admission.
-- Explain why verified shared stock cannot yet be assigned to a legacy order.
create or replace function private.production_stock_readiness(f uuid,i uuid)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare forecast jsonb;rows jsonb;ready boolean;legacy jsonb;begin
 forecast:=private.production_stock_forecast(f,i,clock_timestamp());
 if forecast->>'warning'is not null then
  if forecast->>'warning'='production_stock_legacy_review'then
   select coalesce(jsonb_agg(jsonb_build_object('name',m.item_name,'name_ar',coalesce(mat.name_ar,''),'unit',m.unit,
    'held',trim_scale(greatest(p.issued-p.consumed-coalesce((private.material_return_balance(f,m.id)->>'returned')::numeric,0),0))::text,
    'reserved',trim_scale(p.reserved)::text,'consumed',trim_scale(p.consumed)::text)order by m.item_name),'[]')into legacy
   from public.material_requests m join private.material_request_progress p on p.factory_id=m.factory_id and p.request_id=m.id
   left join public.materials mat on mat.factory_id=m.factory_id and mat.id=m.material_id
   where m.factory_id=f and m.production_item_id=i and(p.reserved>0 or p.consumed>0 or
    p.issued>coalesce((private.material_return_balance(f,m.id)->>'returned')::numeric,0));
  end if;
  return jsonb_build_object('ready',false,'scope','PRODUCTION_STOCK_SHIFT','reason',forecast->>'warning','rows','[]'::jsonb,
   'legacy',coalesce(legacy,'[]'));
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',r.material_id,'name',m.name,'name_ar',m.name_ar,'unit',m.unit,
  'required',trim_scale(r.required)::text,'production_held',trim_scale(r.reserved)::text,'missing',trim_scale(r.required-r.reserved)::text)order by m.name),'[]'),
  coalesce(bool_and(r.required=r.reserved),false)into rows,ready
 from private.production_stock_reservations r join public.materials m on m.factory_id=r.factory_id and m.id=r.material_id
 where r.factory_id=f and r.item_id=i and r.occurrence_key=forecast#>>'{occurrence,occurrence_key}';
 ready:=ready and(forecast->>'expected_output')::numeric>0;
 return jsonb_build_object('ready',ready,'scope','PRODUCTION_STOCK_SHIFT',
  'reason',case when(forecast->>'expected_output')::numeric<=0 then 'production_stock_no_shift_output'when not ready then 'production_stock_shortage'end,
  'required_output',forecast->>'expected_output','unit',forecast->>'unit','occurrence',forecast->'occurrence','rows',rows);
end$$;
revoke all on function private.production_stock_readiness(uuid,uuid)from public,anon,authenticated,service_role;

-- Resolve the authoritative current shift once under the allocation lock. Reuse
-- the existing forecast arithmetic for every order; never cache across batches.
CREATE OR REPLACE FUNCTION private.production_stock_forecast(f uuid, i uuid, stamp timestamp with time zone, resolved jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.production_orders;occ jsonb;req jsonb;rate numeric;fastest numeric;n integer;typed integer;
 setup integer;start_at timestamptz;end_at timestamptz;minutes numeric:=0;remaining_minutes numeric:=0;cursor_at timestamptz;
 made numeric;output numeric;remaining numeric;rows jsonb;calendar record;closing timestamptz;begin
 select *into o from public.production_orders where factory_id=f and id=i;
 if o.id is null or o.status not in('planned','active')or o.line_id is null or o.start_time is null or o.expected_finish is null then return jsonb_build_object('warning','production_stock_schedule_required');end if;
 if not private.production_stock_eligible(f,i)then return jsonb_build_object('warning','production_stock_legacy_review');end if;
 if resolved is null then resolved:=private.resolve_production_occurrence(f,stamp);end if;if resolved->>'available'is distinct from 'true'then return jsonb_build_object('warning','recording_shift_unavailable');end if;occ:=resolved->'occurrence';
 req:=private.material_requirement_inputs(f,i);if req->>'warning'is not null then return req;end if;
 if req->>'existing_source_work'='true'or req->>'mode'='COMPOUND_STOCK'then return jsonb_build_object('warning','production_stock_existing_source','legacy',true);end if;
 select count(*),count(*)filter(where cap.rate_unit=o.unit),min(cap.rate),max(cap.rate),max(cap.setup_minutes)
 into n,typed,rate,fastest,setup from public.work_centers c join public.work_center_capabilities cap
 on cap.factory_id=c.factory_id and cap.work_center_id=c.id and cap.product_id=o.product_id where c.factory_id=f and c.line_id=o.line_id and not c.archived;
 if n=0 or typed<>n or rate<=0 or rate<>fastest then return jsonb_build_object('warning','planning_missing_rate');end if;
 start_at:=greatest(o.start_time,(occ->>'starts_at')::timestamptz);end_at:=least(o.expected_finish,(occ->>'ends_at')::timestamptz);
 -- Use the original Planning calendar resolver and its daily closing boundary.
 -- Segment the current shift at those boundaries; never iterate minute by minute.
 select timezone,working_days_mask,workday_end into calendar from public.factories where id=f;
 cursor_at:=start_at;
 while cursor_at<end_at loop
 cursor_at:=private.next_working_start(f,cursor_at);exit when cursor_at>=end_at;
 closing:=case when calendar.working_days_mask is null then end_at else least(end_at,(((cursor_at at time zone calendar.timezone)::date)+calendar.workday_end)at time zone calendar.timezone)end;
 minutes:=minutes+extract(epoch from closing-cursor_at)/60;
 remaining_minutes:=remaining_minutes+greatest(extract(epoch from closing-greatest(cursor_at,stamp))/60,0);
 cursor_at:=closing+interval '1 minute';end loop;
 if o.start_time>=(occ->>'starts_at')::timestamptz then
 remaining_minutes:=greatest(remaining_minutes-greatest(coalesce(setup,0)-(minutes-remaining_minutes),0),0);
 minutes:=greatest(minutes-coalesce(setup,0),0);end if;
 select coalesce(sum(e.effective_good+coalesce(e.effective_unfinished,0)),0)into made from public.production_entries e
 where e.factory_id=f and e.order_id=i and(coalesce(e.effective_occurrence_key,e.original_occurrence_key)=occ->>'occurrence_key'
 or(e.original_occurrence_key is null and e.created_at>=(occ->>'starts_at')::timestamptz and e.created_at<(occ->>'ends_at')::timestamptz));
 remaining:=greatest(o.target_quantity-o.produced_quantity,0);
 output:=least(remaining,greatest(minutes*rate/60-made,0),greatest(remaining_minutes*rate/60,0));
 select coalesce(jsonb_agg(x||jsonb_build_object('quantity',trim_scale((x->>'quantity')::numeric*output/o.target_quantity)::text)),'[]')into rows from jsonb_array_elements(req->'inputs')x;
 return jsonb_build_object('occurrence',occ,'expected_output',trim_scale(output)::text,'unit',o.unit,'requirement',req,'inputs',rows,'evaluated_at',stamp);end$function$;
revoke all on function private.production_stock_forecast(uuid,uuid,timestamptz,jsonb)from public,anon,authenticated,service_role;
create or replace function private.production_stock_forecast(f uuid,i uuid,stamp timestamptz)returns jsonb
language sql stable security definer set search_path=''as $$
 select private.production_stock_forecast(f,i,stamp,null::jsonb)
$$;
revoke all on function private.production_stock_forecast(uuid,uuid,timestamptz)from public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION private.refresh_production_stock(f uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o record;forecast jsonb;resolved jsonb;stamp timestamptz;x jsonb;needed numeric;free numeric;booked numeric;begin
 if not private.production_stock_enabled(f)then return;end if;perform private.production_stock_lock(f);
 update private.production_stock_reservations set reserved=0 where factory_id=f and reserved<>0;
 for o in select id from public.production_orders where factory_id=f and status in('active','planned')and line_id is not null and start_time is not null
 order by(status='active')desc,start_time,id loop
 if not private.production_stock_eligible(f,o.id)then continue;end if;
 if resolved is null then stamp:=clock_timestamp();resolved:=private.resolve_production_occurrence(f,stamp);end if;
 forecast:=private.production_stock_forecast(f,o.id,stamp,resolved);if forecast->>'warning'is not null then continue;end if;
 insert into private.production_stock_orders(factory_id,item_id)values(f,o.id)on conflict do nothing;
 for x in select value from jsonb_array_elements(forecast->'inputs')loop
 needed:=(x->>'quantity')::numeric;
 free:=greatest(private.production_stock_quantity(f,(x->>'id')::uuid)-private.production_stock_return_pending(f,(x->>'id')::uuid)-coalesce((select sum(reserved)from private.production_stock_reservations where factory_id=f and material_id=(x->>'id')::uuid),0),0);
 booked:=least(needed,free);
 insert into private.production_stock_reservations(factory_id,item_id,occurrence_key,material_id,required,reserved,expected_output,evidence)
 values(f,o.id,forecast#>>'{occurrence,occurrence_key}',(x->>'id')::uuid,needed,booked,(forecast->>'expected_output')::numeric,forecast)
 on conflict(factory_id,item_id,occurrence_key,material_id)do update set required=excluded.required,reserved=excluded.reserved,expected_output=excluded.expected_output,evidence=excluded.evidence,updated_at=clock_timestamp();
 end loop;end loop;
 -- Reservations are a derived current projection; physical postings, confirmed
 -- requests and handover snapshots retain audit without logging every clock tick.
 end$function$;
revoke all on function private.refresh_production_stock(uuid)from public,anon,authenticated,service_role;

-- A shift may open between the locked batch and its advisory/admission read.
-- Rebuild once in that new occurrence rather than returning an empty shortage.
CREATE OR REPLACE FUNCTION private.material_start_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare readiness jsonb;begin
 if new.status='active'and(old.status is distinct from 'active'or old.actual_start is null and new.actual_start is not null)then
 if current_setting('transaction_isolation') not in('read committed','read uncommitted')then raise exception 'execution_readiness_stale'using errcode='40001';end if;
 perform private.require_permission(new.factory_id,'orders','edit');
 perform pg_advisory_xact_lock(hashtextextended(new.factory_id::text,0));perform private.maintenance_planning_lock(new.factory_id);
 if row(new.product_id,new.unit,new.target_quantity,new.request_id)is distinct from row(old.product_id,old.unit,old.target_quantity,old.request_id)then raise exception 'execution_use_command';end if;
 perform private.refresh_production_stock(new.factory_id);
 readiness:=private.material_start_readiness(new.factory_id,new.id);
 if readiness->>'scope'='PRODUCTION_STOCK_SHIFT'and coalesce((readiness->>'required_output')::numeric,0)>0 and jsonb_array_length(readiness->'rows')=0 then
 perform private.refresh_production_stock(new.factory_id);readiness:=private.material_start_readiness(new.factory_id,new.id);end if;
 if not coalesce((readiness->>'ready')::boolean,false)then raise exception 'production_material_not_ready'using errcode='22023',detail=readiness::text;end if;
 end if;return new;end$function$;
CREATE OR REPLACE FUNCTION public.production_start_readiness(factory uuid, item uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.production_orders;physical jsonb;hold jsonb;blocker jsonb;stamp timestamptz;materials jsonb;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'orders','view');perform private.refresh_production_stock(factory);
 select * into o from public.production_orders where factory_id=factory and id=item;
 if not found then raise exception 'not_found' using errcode='P0002';end if;
 physical:=private.maintenance_execution_readiness(factory,o.id,o.line_id,o.product_id);
 if coalesce((physical->>'ready')::boolean,true)then physical:=private.execution_machine_readiness(factory,o.id,o.line_id,o.product_id);end if;
 stamp:=clock_timestamp();
 -- This is current maintenance occupancy, not a new duration/calendar engine.
 -- The original Start trigger still checks both plan and intended execution span.
 hold:=private.maintenance_capacity_conflict(factory,o.line_id,o.product_id,null,stamp,stamp+interval '1 microsecond',null,o.id,false);
 if hold is not null then
 select jsonb_build_object('reason','MAINTENANCE_HOLD','machine',jsonb_build_object('id',c.id,'code',c.code,'name',c.name,'name_ar',c.name_ar,'status',c.status))
 into blocker from public.maintenance_schedule_resources r join public.work_centers c on c.factory_id=r.factory_id and c.id=r.machine_id
 where r.factory_id=factory and r.schedule_id=(hold->>'schedule')::uuid and r.resource_kind='MACHINE' order by c.id limit 1;
 end if;
 materials:=private.material_start_readiness(factory,item);
 if materials->>'scope'='PRODUCTION_STOCK_SHIFT'and coalesce((materials->>'required_output')::numeric,0)>0 and jsonb_array_length(materials->'rows')=0 then
 perform private.refresh_production_stock(factory);materials:=private.material_start_readiness(factory,item);end if;
 return jsonb_build_object('factory',factory,'item',item,'physical',physical,'materials',materials,'maintenance_block',blocker,
 'quality_hold',private.output_work_held(factory,item),'evaluated_at',stamp,'queue_ready',coalesce(o.status='planned' and o.actual_start is null and o.actual_finish is null
 and o.start_time is not null and o.expected_finish>o.start_time
 and not exists(select 1 from public.production_orders x where x.factory_id=factory and x.line_id=o.line_id and x.status='active')
 and o.id=(select x.id from public.production_orders x where x.factory_id=factory and x.line_id=o.line_id and x.status='planned'
 and x.actual_start is null and x.actual_finish is null and x.start_time is not null and x.expected_finish>x.start_time order by x.start_time,x.id limit 1),false));
end$function$;
