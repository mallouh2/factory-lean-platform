-- F34.1: independent actual execution; no order/history/backfill writes.

CREATE OR REPLACE FUNCTION private.guard_product_execution()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'INSERT' then
   if new.execution_started_at is not null or new.execution_interrupted_at is not null then raise exception 'execution_use_command';end if;
    if new.status <> 'planned' or new.actual_start is not null
      or new.actual_finish is not null then
      raise exception 'execution_use_command';
    end if;
    return new;
  end if;

  if private.execution_command_allowed(old.factory_id,old.id,array['INTERRUPT','RESUME','START_SELECTED'])
   and row(old.line_id,old.start_time,old.expected_finish)is distinct from row(new.line_id,new.start_time,new.expected_finish)
   then raise exception 'execution_plan_immutable'using errcode='22023';end if;
  if row(old.execution_started_at,old.execution_interrupted_at)is distinct from row(new.execution_started_at,new.execution_interrupted_at)
   and not private.execution_command_allowed(old.factory_id,old.id,array['INTERRUPT','RESUME','START_SELECTED'])then raise exception 'execution_use_command';end if;
  if private.execution_command_allowed(old.factory_id,old.id,array['INTERRUPT'])and old.status='active'and new.status='planned'
   and new.execution_interrupted_at is not null and new.actual_start=old.actual_start and new.actual_finish is null
   and row(new.line_id,new.start_time,new.expected_finish)is not distinct from row(old.line_id,old.start_time,old.expected_finish)then return new;end if;
  if private.execution_command_allowed(old.factory_id,old.id,array['RESUME'])and old.status='planned'and old.execution_interrupted_at is not null
   and new.status='active'and new.actual_start=old.actual_start and new.actual_finish is null and new.execution_started_at>coalesce(old.execution_started_at,old.actual_start)
   and new.execution_interrupted_at is null and new.line_id=old.line_id and row(new.start_time,new.expected_finish)is not distinct from row(old.start_time,old.expected_finish)then return new;end if;
  if (old.status,old.actual_start,old.actual_finish) is not distinct from
     (new.status,new.actual_start,new.actual_finish) then return new; end if;

  -- Keep the pre-existing generic cancellation path for unstarted work.
  if old.status = 'planned' and new.status = 'cancelled'
    and old.actual_start is null and new.actual_start is null
    and old.actual_finish is null and new.actual_finish is null then
    return new;
  end if;

  if (old.line_id,old.start_time,old.expected_finish) is distinct from
     (new.line_id,new.start_time,new.expected_finish) then
    raise exception 'execution_use_command';
  end if;

  if old.status = 'planned' and new.status = 'active'
    and old.actual_start is null and old.actual_finish is null
    and new.actual_start is not null and new.actual_finish is null then
    return new;
  end if;
  if old.status = 'active' and new.status = 'completed'
    and old.actual_start is not null and old.actual_finish is null
    and new.actual_start = old.actual_start and new.actual_finish is not null then
    return new;
  end if;
  raise exception 'execution_use_command';
end;
$function$;

CREATE OR REPLACE FUNCTION public.production_execution_action(factory uuid, item uuid, operation text, reason text, fingerprint text, request_id uuid, output_confirmed boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.production_orders;c private.production_execution_commands;intent jsonb;stamp timestamptz;rate numeric;fastest numeric;
 n integer;typed integer;setup integer;duration integer;remaining numeric;finish_at timestamptz;response jsonb;begin
 perform private.require_permission(factory,'orders','edit');
 if current_setting('transaction_isolation')not in('read committed','read uncommitted')then raise exception 'execution_readiness_stale'using errcode='40001';end if;
 if operation not in('INTERRUPT','RESUME','START_SELECTED')or request_id is null or fingerprint is null or
 reason is null or char_length(btrim(reason))not between 3 and 240 then raise exception 'execution_reason_required'using errcode='22023';end if;
 intent:=jsonb_build_object('item',item,'operation',operation,'reason',btrim(reason),'fingerprint',fingerprint,'output_confirmed',output_confirmed);
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.maintenance_planning_lock(factory);
 select *into c from private.production_execution_commands where factory_id=factory and production_execution_commands.request_id=production_execution_action.request_id;
 if found then
  if c.actor<>auth.uid()or c.intent<>intent or c.result is null then raise exception 'execution_command_conflict'using errcode='22023';end if;
  return c.result;
 end if;
 select *into o from public.production_orders where factory_id=factory and id=item for update;
 if not found then raise exception 'not_found';end if;
 if private.execution_fingerprint(factory,item)is distinct from fingerprint then raise exception 'execution_context_changed'using errcode='40001';end if;
 stamp:=clock_timestamp();
 insert into private.production_execution_commands(factory_id,request_id,actor,item_id,operation,reason,intent,before_state,started_at)
 values(factory,request_id,auth.uid(),item,operation,btrim(reason),intent,to_jsonb(o),stamp);
 if operation='INTERRUPT'then
  if o.status<>'active'or o.actual_start is null or o.actual_finish is not null then raise exception 'execution_not_active'using errcode='22023';end if;
  if output_confirmed is distinct from true then raise exception 'execution_record_output_first'using errcode='22023';end if;
  if private.ordinary_output_remaining(factory,item)<=0 then raise exception 'execution_no_remaining'using errcode='22023';end if;
  if exists(select 1 from public.production_transfers t where t.factory_id=factory and t.order_id=item and t.ended_at is null)
   then raise exception 'execution_end_transfer_first'using errcode='22023';end if;
  -- Release ACTUAL execution only. The approved plan and its revisions are untouched.
  update public.production_orders set status='planned',execution_interrupted_at=stamp
   where factory_id=factory and id=item;
 else
  if o.status<>'planned'or o.actual_finish is not null or
   (operation='RESUME'and o.execution_interrupted_at is null)or
   (operation='START_SELECTED'and(o.actual_start is not null or o.execution_interrupted_at is not null or o.produced_quantity<>0))
   then raise exception 'execution_context_changed'using errcode='40001';end if;
  if o.line_id is null or o.start_time is null or o.expected_finish is null then raise exception 'execution_plan_required'using errcode='22023';end if;
  remaining:=private.ordinary_output_remaining(factory,item);
  if remaining<=0 then raise exception 'execution_no_remaining'using errcode='22023';end if;
  select count(*),count(*)filter(where cap.rate_unit=o.unit),min(cap.rate),max(cap.rate),max(cap.setup_minutes)
  into n,typed,rate,fastest,setup from public.work_centers w join public.work_center_capabilities cap
  on cap.factory_id=w.factory_id and cap.work_center_id=w.id and cap.product_id=o.product_id
  where w.factory_id=factory and w.line_id=o.line_id and not w.archived;
  if n=0 or typed<>n or rate<=0 or rate<>fastest then raise exception 'planning_missing_rate';end if;
  duration:=ceil(remaining*60/rate)+coalesce(setup,0);
  finish_at:=private.finish_after_working_minutes(factory,stamp,greatest(duration,1));
  insert into private.production_execution_runs(factory_id,item_id,line_id,started_at,state,planned,effective_start,effective_finish,
   start_actor,reason,dispatch_override,request_id,recorded_before)
  values(factory,item,o.line_id,stamp,'ARMED',jsonb_build_object('line',o.line_id,'start',o.start_time,'finish',o.expected_finish),
   stamp,finish_at,auth.uid(),btrim(reason),true,request_id,to_jsonb(o));
  -- Original Start owns line serialization and every machine/material/Quality/Maintenance guard.
  perform public.start_product_item(factory,item);
 end if;
 perform private.refresh_production_stock(factory);
 response:=public.production_execution_context(factory,item);
 update private.production_execution_commands set result=response where factory_id=factory
 and production_execution_commands.request_id=production_execution_action.request_id;
 return response;
end$function$;

CREATE OR REPLACE FUNCTION private.production_stock_forecast(f uuid, i uuid, stamp timestamp with time zone, resolved jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.production_orders;occ jsonb;req jsonb;rate numeric;fastest numeric;n integer;typed integer;
 setup integer;start_at timestamptz;end_at timestamptz;minutes numeric:=0;remaining_minutes numeric:=0;cursor_at timestamptz;
 made numeric;output numeric;remaining numeric;rows jsonb;calendar record;closing timestamptz;run private.production_execution_runs;begin
 select *into o from public.production_orders where factory_id=f and id=i;
 if o.id is null or o.status not in('planned','active')or o.line_id is null or o.start_time is null or o.expected_finish is null then return jsonb_build_object('warning','production_stock_schedule_required');end if;
 if not private.production_stock_eligible(f,i)then return jsonb_build_object('warning','production_stock_legacy_review');end if;
 if o.execution_interrupted_at is not null and not exists(select 1 from private.production_execution_runs r
  where r.factory_id=f and r.item_id=i and r.state='ARMED')then return jsonb_build_object('warning','execution_order_interrupted');end if;
 if resolved is null then resolved:=private.resolve_production_occurrence(f,stamp);end if;if resolved->>'available'is distinct from 'true'then return jsonb_build_object('warning','recording_shift_unavailable');end if;occ:=resolved->'occurrence';
 req:=private.material_requirement_inputs(f,i);if req->>'warning'is not null then return req;end if;
 if req->>'existing_source_work'='true'or req->>'mode'='COMPOUND_STOCK'then return jsonb_build_object('warning','production_stock_existing_source','legacy',true);end if;
 select count(*),count(*)filter(where cap.rate_unit=o.unit),min(cap.rate),max(cap.rate),max(cap.setup_minutes)
 into n,typed,rate,fastest,setup from public.work_centers c join public.work_center_capabilities cap
 on cap.factory_id=c.factory_id and cap.work_center_id=c.id and cap.product_id=o.product_id where c.factory_id=f and c.line_id=o.line_id and not c.archived;
 if n=0 or typed<>n or rate<=0 or rate<>fastest then return jsonb_build_object('warning','planning_missing_rate');end if;
 select *into run from private.production_execution_runs where factory_id=f and item_id=i and ended_at is null and dispatch_override;
 if run.id is not null then o.start_time:=run.effective_start;o.expected_finish:=run.effective_finish;end if;
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
 where e.factory_id=f and e.order_id=i and(run.id is null or e.created_at>=run.started_at)and(coalesce(e.effective_occurrence_key,e.original_occurrence_key)=occ->>'occurrence_key'
 or(e.original_occurrence_key is null and e.created_at>=(occ->>'starts_at')::timestamptz and e.created_at<(occ->>'ends_at')::timestamptz));
 remaining:=case when run.id is not null or o.execution_interrupted_at is not null then private.ordinary_output_remaining(f,i)else greatest(o.target_quantity-o.produced_quantity,0)end;
 output:=least(remaining,greatest(minutes*rate/60-made,0),greatest(remaining_minutes*rate/60,0));
 select coalesce(jsonb_agg(x||jsonb_build_object('quantity',trim_scale((x->>'quantity')::numeric*output/o.target_quantity)::text)),'[]')into rows from jsonb_array_elements(req->'inputs')x;
 return jsonb_build_object('occurrence',occ,'expected_output',trim_scale(output)::text,'unit',o.unit,'requirement',req,'inputs',rows,'evaluated_at',stamp);end$function$;

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
 and(execution_interrupted_at is null or exists(select 1 from private.production_execution_runs r where r.factory_id=f and r.item_id=production_orders.id and r.state='ARMED'))
 order by(status='active')desc,exists(select 1 from private.production_execution_runs r where r.factory_id=f and r.item_id=production_orders.id and r.state='ARMED')desc,start_time,id loop
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

CREATE OR REPLACE FUNCTION private.maintenance_production_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare finish_time timestamptz;minutes_required integer;m public.work_centers;begin
 perform private.maintenance_planning_lock(new.factory_id);
 -- Stopping actual work does not create/revise Planning occupancy. Never block
 -- safe release because the preserved historical plan now conflicts with a hold.
 if tg_op='UPDATE'and old.status='active'and new.status='planned'
 and private.execution_command_allowed(new.factory_id,new.id,array['INTERRUPT'])
 and row(old.line_id,old.start_time,old.expected_finish)is not distinct from row(new.line_id,new.start_time,new.expected_finish)then return new;end if;
 if new.status in ('planned','active') and new.line_id is not null then
 perform private.maintenance_assert_capacity(new.factory_id,new.line_id,new.product_id,null,new.start_time,new.expected_finish,null,new.id,false);
 end if;
 if tg_op='UPDATE' and old.status<>'active' and new.status='active' then
 if private.maintenance_capacity_conflict(new.factory_id,new.line_id,new.product_id,null,coalesce(new.execution_started_at,new.actual_start),'infinity',null,new.id,false) is not null then
 select ceil((case when new.execution_started_at is not null then private.ordinary_output_remaining(new.factory_id,new.id)else new.target_quantity end)/min(cap.rate)*60)+max(cap.setup_minutes) into minutes_required
 from public.work_centers c join public.work_center_capabilities cap on cap.factory_id=c.factory_id and cap.work_center_id=c.id
 where c.factory_id=new.factory_id and c.line_id=new.line_id and not c.archived and cap.product_id=new.product_id and cap.rate_unit=new.unit and cap.rate>0;
 -- Conservative intended window, never a claimed actual completion timestamp.
 if minutes_required is null then raise exception 'maintenance_execution_window_unknown';end if;
 finish_time:=private.finish_after_working_minutes(new.factory_id,coalesce(new.execution_started_at,new.actual_start),minutes_required);
 perform private.maintenance_assert_capacity(new.factory_id,new.line_id,new.product_id,null,coalesce(new.execution_started_at,new.actual_start),finish_time,null,new.id,false);
 end if;
 end if;
 return new;
end$function$;

CREATE OR REPLACE FUNCTION public.production_execution_context(factory uuid, item uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.production_orders;h jsonb;begin
 perform private.require_permission(factory,'orders','view');
 select *into o from public.production_orders where factory_id=factory and id=item;
 if not found then raise exception 'not_found';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'line_id',r.line_id,'started_at',r.started_at,'ended_at',r.ended_at,
 'state',r.state,'reason',r.reason,'start_reason',(select c.reason from private.production_execution_commands c where c.factory_id=r.factory_id and c.request_id=r.request_id),'start_actor',r.start_actor,'end_actor',r.end_actor,'planned',r.planned,
 'effective_start',r.effective_start,'effective_finish',r.effective_finish,'recorded_before',r.recorded_before,'recorded_after',r.recorded_after)
 order by r.started_at desc),'[]')into h from private.production_execution_runs r where r.factory_id=factory and r.item_id=item;
 return jsonb_build_object('factory',factory,'item',item,'order',to_jsonb(o),'fingerprint',private.execution_fingerprint(factory,item),'history',h,
 'remaining',private.ordinary_output_remaining(factory,item)::text);
end$function$;

create function public.production_execution_orders(factory uuid,cursor jsonb default null,page_size integer default 100)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare revision text;after_start timestamptz;after_id uuid;rows jsonb;next_cursor jsonb;total integer;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'orders','view');
 if page_size is null or page_size not between 1 and 100 then raise exception 'execution_orders_invalid'using errcode='22023';end if;
 select count(*),encode(sha256(convert_to(coalesce(string_agg(to_jsonb(o)::text,'|'order by o.start_time,o.id),''),'UTF8')),'hex')into total,revision
 from public.production_orders o where factory_id=factory and line_id is not null and start_time is not null and expected_finish>start_time;
 if cursor is not null then
  if jsonb_typeof(cursor)<>'object'or (select count(*)from jsonb_object_keys(cursor))<>4 or cursor->>'factory'is distinct from factory::text
   or cursor->>'revision'is distinct from revision or cursor->>'after_start'is null or cursor->>'after_id'is null then raise exception 'execution_orders_changed'using errcode='40001';end if;
  after_start:=(cursor->>'after_start')::timestamptz;after_id:=(cursor->>'after_id')::uuid;
 end if;
 with page as materialized(select o from public.production_orders o where factory_id=factory and line_id is not null and start_time is not null and expected_finish>start_time
  and(cursor is null or(o.start_time,o.id)>(after_start,after_id))order by o.start_time,o.id limit page_size+1),
 selected as materialized(select o from page order by(o).start_time,(o).id limit page_size)
 select coalesce(jsonb_agg(to_jsonb(s.o)||jsonb_build_object('execution_product_name',p.name,'execution_product_name_ar',p.name_ar)order by(s.o).start_time,(s.o).id),'[]'),
 case when(select count(*)from page)>page_size then(select jsonb_build_object('factory',factory,'revision',revision,'after_start',(o).start_time,'after_id',(o).id)from selected order by(o).start_time desc,(o).id desc limit 1)end
 into rows,next_cursor from selected s left join public.products p on p.factory_id=factory and p.id=(s.o).product_id;
 return jsonb_build_object('factory',factory,'revision',revision,'total',total,'rows',rows,'next_cursor',next_cursor,'complete',next_cursor is null);
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then raise exception 'execution_orders_invalid'using errcode='22023';end$$;
revoke all on function public.production_execution_orders(uuid,jsonb,integer)from public,anon,service_role;
grant execute on function public.production_execution_orders(uuid,jsonb,integer)to authenticated;

