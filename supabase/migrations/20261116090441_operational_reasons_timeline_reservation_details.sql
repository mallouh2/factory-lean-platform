-- F38/F42/F35: current assignment reasons, executable priority and read-only booking evidence.
-- No historical row, stock balance, custody, run or Planning revision backfill.
-- A reassignment keeps its replanned event, while a wholly unassigned BEFORE tuple
-- needs no invented reason. Assigned modifications/unschedules still require one.
alter table public.production_plan_revisions drop constraint production_plan_revisions_check;
alter table public.production_plan_revisions add constraint production_plan_revisions_check check(
 event not in('replanned','unscheduled')or reason_code is not null or
 (event='replanned'and before_line_id is null and before_start is null and before_finish is null and after_line_id is not null and after_start is not null and after_finish is not null));
CREATE OR REPLACE FUNCTION private.record_plan_revision()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  reason text := nullif(current_setting('app.plan_reason',true),'');
  note text := nullif(btrim(current_setting('app.plan_note',true)),'');
  kind text;
  actor_name text;
  next_revision integer;
begin
  if (old.line_id,old.start_time,old.expected_finish) is not distinct from
     (new.line_id,new.start_time,new.expected_finish) then return new; end if;
  if (private.planning_change_state(old.factory_id,old.id)->>'exception_required')::boolean and not private.execution_command_allowed(old.factory_id,old.id,array['INTERRUPT'])and not exists(
 select 1 from private.planning_change_commands c where c.factory_id=old.factory_id and c.item_id=old.id and c.actor=auth.uid()and c.transaction_id=txid_current()
 and c.request_id::text=current_setting('app.planning_change_request',true)and c.result is null and c.fingerprint=private.planning_change_state(old.factory_id,old.id)->>'fingerprint')then raise exception 'planning_confirmation_required';end if;
 if old.planning_locked_at is not null and not private.execution_command_allowed(old.factory_id,old.id,array['INTERRUPT'])then raise exception 'planning_locked'; end if;
  if not private.execution_command_allowed(old.factory_id,old.id,array['INTERRUPT'])and(old.status<>'planned'or old.actual_finish is not null
    or old.execution_interrupted_at is null and(old.produced_quantity>0 or old.actual_start is not null))then
    raise exception 'planning_already_started';
  end if;
  if old.planning_ever_scheduled and old.execution_interrupted_at is null and not private.execution_command_allowed(old.factory_id,old.id,array['INTERRUPT'])
 and not((new.line_id is null or old.line_id is null and new.line_id=private.recorded_custody_line(old.factory_id,old.id))and old.status='planned'and old.actual_start is null and old.actual_finish is null and old.produced_quantity=0
  and not exists(select 1 from public.production_entries e where e.factory_id=old.factory_id and e.order_id=old.id))
 and not private.planning_unstarted_reversible(old.factory_id,old.id)
 and not(coalesce(old.line_id is not null and new.line_id=old.line_id and private.planning_issued_time_change_safe(old.factory_id,old.id),false))then
 if private.output_work_held(old.factory_id,old.id)then raise exception 'output_quality_hold';end if;
 if exists(select 1 from public.production_entries where factory_id=old.factory_id and order_id=old.id)then raise exception 'planning_already_started';end if;
 if private.output_work_consumed(old.factory_id,old.id)>0 then raise exception 'planning_material_consumed';end if;raise exception 'planning_material_custody';end if; if old.line_id is null then
    kind := case when old.planning_ever_scheduled then 'replanned' else 'initial' end;
    reason := null; note := null;
  else
    if reason not in ('priority_change','customer_request','machine_unavailable','maintenance',
      'material_delay','capacity_conflict','quality_issue','management_decision','other')
      or reason is null or (reason='other' and note is null) then
      raise exception 'planning_reason_required';
    end if;
    kind := case when new.line_id is null then 'unscheduled' else 'replanned' end;
  end if;
  if (new.line_id is null and (new.start_time is not null or new.expected_finish is not null)) or
     (new.line_id is not null and (new.start_time is null or new.expected_finish is null)) then
    raise exception 'planning_invalid_start';
  end if;
  if old.line_id is not null and new.line_id is null and exists(select 1 from public.material_requests m join private.material_request_progress p
   on p.factory_id=m.factory_id and p.request_id=m.id where m.factory_id=old.factory_id and m.production_item_id=old.id and p.issued>0)then
   insert into private.production_custody_origins(factory_id,item_id,recorded_line_id,actor,evidence)
   values(old.factory_id,old.id,old.line_id,auth.uid(),jsonb_build_object('basis','RECORDED_PRE_RELEASE_LINE','order',to_jsonb(old)))on conflict do nothing;end if;
  if new.line_id is not null then new.planning_ever_scheduled := true; end if;
  select display_name into actor_name from public.memberships
    where factory_id=old.factory_id and user_id=auth.uid();
  select coalesce(max(revision_no),0)+1 into next_revision
    from public.production_plan_revisions
    where factory_id=old.factory_id and item_id=old.id;
  insert into public.production_plan_revisions
    (factory_id,item_id,revision_no,event,before_line_id,before_start,before_finish,
      after_line_id,after_start,after_finish,reason_code,reason_note,changed_by,changed_by_name)
  values (old.factory_id,old.id,next_revision,kind,old.line_id,old.start_time,old.expected_finish,
    new.line_id,new.start_time,new.expected_finish,case when kind='initial' then null else reason end,
    case when kind='initial' then null else note end,auth.uid(),actor_name);
  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION private.execution_start_blocker(f uuid, i uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.production_orders;remaining numeric;blocker text;ready jsonb;n integer;typed integer;slowest numeric;fastest numeric;begin
 select *into o from public.production_orders where factory_id=f and id=i;if not found then raise exception 'not_found';end if;
 remaining:=private.ordinary_output_remaining(f,i);
 if o.status='planned'and remaining>0 then
  if o.line_id is null or not exists(select 1 from public.production_lines where factory_id=f and id=o.line_id and not archived)then blocker:='execution_plan_required';
  elsif exists(select 1 from private.production_material_policy where factory_id=f and stock_enabled)and not private.production_stock_eligible(f,i)then blocker:='production_stock_legacy_review';
  elsif private.output_work_held(f,i)then blocker:='planningQualityHold';
  elsif exists(select 1 from public.production_orders where factory_id=f and line_id=o.line_id and status='active'and id<>i)then blocker:='f341ReleaseCurrentFirst';
  else
   select count(*),count(*)filter(where c.rate_unit=o.unit),min(c.rate),max(c.rate)into n,typed,slowest,fastest
   from public.work_centers w join public.work_center_capabilities c on c.factory_id=w.factory_id and c.work_center_id=w.id and c.product_id=o.product_id where w.factory_id=f and w.line_id=o.line_id and not w.archived;
   if n=0 or n<>typed or slowest<=0 or slowest<>fastest then blocker:='planningMissingRate';
   else
    ready:=private.maintenance_execution_readiness(f,i,o.line_id,o.product_id);
    if ready->>'ready'='false'then blocker:='productionReadiness_'||(ready->>'reason');
    elsif private.execution_machine_readiness(f,i,o.line_id,o.product_id)->>'ready'='false'then blocker:='execution_machine_stopped';end if;
   end if;
  end if;
 end if;
 return blocker;
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
 if o.execution_interrupted_at is not null and (resolved->>'dispatch_item')is distinct from i::text and not exists(select 1 from private.production_execution_runs r
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
 if resolved->>'dispatch_item'=i::text then
 o.start_time:=(resolved->>'dispatch_start')::timestamptz;o.expected_finish:=(resolved->>'dispatch_finish')::timestamptz;
 end if;
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
 if resolved->>'dispatch_item'=i::text then made:=0;end if;
 remaining:=case when run.id is not null or o.execution_interrupted_at is not null then private.ordinary_output_remaining(f,i)else greatest(o.target_quantity-o.produced_quantity,0)end;
 output:=least(remaining,greatest(minutes*rate/60-made,0),greatest(remaining_minutes*rate/60,0));
 select coalesce(jsonb_agg(x||jsonb_build_object('quantity',trim_scale((x->>'quantity')::numeric*output/o.target_quantity)::text)),'[]')into rows from jsonb_array_elements(req->'inputs')x;
 return jsonb_build_object('occurrence',occ,'expected_output',trim_scale(output)::text,'unit',o.unit,'requirement',req,'inputs',rows,'evaluated_at',stamp);end$function$;

create function private.execution_dispatch_materials(f uuid,i uuid)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare o public.production_orders;stamp timestamptz:=statement_timestamp();occ jsonb;forecast jsonb;rate numeric;setup integer;finish_at timestamptz;row jsonb;free numeric;own numeric;others numeric;rows jsonb:='[]';ready boolean:=true;m public.materials;begin
 select *into o from public.production_orders where factory_id=f and id=i;
 occ:=private.resolve_production_occurrence(f,stamp);if occ->>'available'is distinct from 'true'then return jsonb_build_object('ready',false,'reason','recording_shift_unavailable','rows',rows);end if;
 select min(c.rate),max(c.setup_minutes)into rate,setup from public.work_centers w join public.work_center_capabilities c on c.factory_id=w.factory_id and c.work_center_id=w.id and c.product_id=o.product_id where w.factory_id=f and w.line_id=o.line_id and not w.archived;
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
end$$;
create function private.execution_dispatch_eligible(f uuid,i uuid)returns boolean
language plpgsql stable security definer set search_path=''as $$
declare o public.production_orders;begin
 select *into o from public.production_orders where factory_id=f and id=i;
 if o.id is null or o.status<>'planned'or o.actual_finish is not null or o.start_time is null or o.expected_finish<=o.start_time or private.ordinary_output_remaining(f,i)<=0 then return false;end if;
 if private.execution_start_blocker(f,i)is not null then return false;end if;
 if not private.production_stock_enabled(f)then return coalesce((private.material_start_readiness_before_stock(f,i)->>'ready')::boolean,false);end if;
 return coalesce((private.execution_dispatch_materials(f,i)->>'ready')::boolean,false);
end$$;
create function private.execution_bypassed_order(f uuid,i uuid)returns jsonb
language sql stable security definer set search_path=''as $$
 select jsonb_build_object('id',q.id,'code',q.code)from public.production_orders q join public.production_orders selected on selected.factory_id=q.factory_id and selected.line_id=q.line_id and selected.id=i
 where q.factory_id=f and selected.status='planned'and(q.start_time,q.id)<(selected.start_time,selected.id)and q.status='planned'and q.actual_finish is null and q.start_time is not null and q.expected_finish>q.start_time
 and private.execution_dispatch_eligible(f,q.id)order by q.start_time,q.id limit 1
$$;
create or replace function private.execution_reason_required(f uuid,i uuid)returns boolean
language sql stable security definer set search_path=''as $$select private.execution_bypassed_order(f,i)is not null$$;
create or replace function private.execution_selection_state(f uuid,i uuid)returns jsonb
language sql stable security definer set search_path=''as $$
 select jsonb_build_object('execution_remaining_quantity',private.ordinary_output_remaining(f,i)::text,'execution_reason_required',b is not null,'execution_bypassed_order',b,'execution_start_blocker',private.execution_start_blocker(f,i))from(select private.execution_bypassed_order(f,i)b)s
$$;
revoke all on function private.execution_start_blocker(uuid,uuid),private.execution_dispatch_materials(uuid,uuid),private.execution_dispatch_eligible(uuid,uuid),private.execution_bypassed_order(uuid,uuid)from public,anon,authenticated,service_role;
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
 'start_variance_seconds',extract(epoch from(r.started_at-(r.planned->>'start')::timestamptz))::text,'end_variance_seconds',case when r.ended_at is not null then extract(epoch from(r.ended_at-(r.planned->>'finish')::timestamptz))::text end,'state',r.state,'reason',r.reason,'start_reason',(select c.reason from private.production_execution_commands c where c.factory_id=r.factory_id and c.request_id=r.request_id),'start_actor',r.start_actor,'end_actor',r.end_actor,'planned',r.planned,
 'effective_start',r.effective_start,'effective_finish',r.effective_finish,'recorded_before',r.recorded_before,'recorded_after',r.recorded_after)
 order by r.started_at desc),'[]')into h from private.production_execution_runs r where r.factory_id=factory and r.item_id=item;
 return jsonb_build_object('factory',factory,'item',item,'order',to_jsonb(o),'fingerprint',private.execution_fingerprint(factory,item),'history',h,
 'remaining',private.ordinary_output_remaining(factory,item)::text,'reason_required',private.execution_reason_required(factory,item),'bypassed_order',private.execution_bypassed_order(factory,item));
end$function$;
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
 reason is null or char_length(btrim(reason))>240 or char_length(btrim(reason))between 1 and 2 then raise exception 'execution_reason_required'using errcode='22023';end if;
 intent:=jsonb_build_object('item',item,'operation',operation,'reason',btrim(reason),'fingerprint',fingerprint,'output_confirmed',output_confirmed);
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.maintenance_planning_lock(factory);
 select *into c from private.production_execution_commands where factory_id=factory and production_execution_commands.request_id=production_execution_action.request_id;
 if found then
  if c.actor<>auth.uid()or c.intent<>intent or c.result is null then raise exception 'execution_command_conflict'using errcode='22023';end if;
  if c.result->>'outcome'='REJECTED'then raise exception using message=c.result#>>'{error,message}',errcode=c.result#>>'{error,code}',detail=coalesce(c.result#>>'{error,details}','');end if;
  return c.result;
 end if;
 select *into o from public.production_orders where factory_id=factory and id=item for update;
 if not found then raise exception 'not_found';end if;
 if private.execution_fingerprint(factory,item)is distinct from fingerprint then raise exception 'execution_context_changed'using errcode='40001';end if;
 if operation in('RESUME','START_SELECTED')then perform private.refresh_production_stock(factory);end if;
 if(operation='INTERRUPT'or private.execution_reason_required(factory,item))and char_length(btrim(reason))<3 then raise exception 'execution_reason_required'using errcode='22023';end if;
 stamp:=clock_timestamp();
 insert into private.production_execution_commands(factory_id,request_id,actor,item_id,operation,reason,intent,before_state,started_at)
 values(factory,request_id,auth.uid(),item,operation,btrim(reason),intent,to_jsonb(o)||jsonb_build_object('execution_reason_required',operation='INTERRUPT'or private.execution_reason_required(factory,item),'bypassed_order',private.execution_bypassed_order(factory,item)),stamp);
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
  if private.production_stock_enabled(factory)and private.production_stock_eligible(factory,item)then
   response:=private.execution_dispatch_materials(factory,item);
   if response->>'ready'is distinct from 'true'then raise exception 'production_material_not_ready'using errcode='22023',detail=response::text;end if;
  end if;
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
create function public.production_stock_reservation_details(factory uuid,material uuid,page integer default 1)returns jsonb
language plpgsql security definer set search_path=''as $$
declare occ jsonb;stock jsonb;active_rows jsonb;history jsonb;history_count integer;begin
 perform private.require_permission(factory,'factory','view');
 if not private.has_permission(factory,'orders','view')then perform private.require_permission(factory,'warehouse','view');end if;
 if page is null or page not between 1 and 10000 then raise exception 'material_invalid'using errcode='22023';end if;
 if not exists(select 1 from public.materials where factory_id=factory and id=material and inventory_kind='RAW_MATERIAL'and unit='kg')then raise exception 'not_found';end if;
 -- Same locked derived projection as the stock screen. Never posts a physical movement.
 perform private.refresh_production_stock(factory);occ:=private.resolve_production_occurrence(factory,clock_timestamp());
 if exists(select 1 from private.production_stock_reservations r where r.factory_id=factory and r.reserved>0 and r.occurrence_key is distinct from occ#>>'{occurrence,occurrence_key}')then
  perform private.refresh_production_stock(factory);occ:=private.resolve_production_occurrence(factory,clock_timestamp());
  if exists(select 1 from private.production_stock_reservations r where r.factory_id=factory and r.reserved>0 and r.occurrence_key is distinct from occ#>>'{occurrence,occurrence_key}')then raise exception 'material_changed'using errcode='40001';end if;
 end if;
 select jsonb_build_object('id',m.id,'name',m.name,'name_ar',m.name_ar,'unit',m.unit,
 'physical',trim_scale(private.production_stock_quantity(factory,material))::text,
 'order_reserved',trim_scale(coalesce((select sum(r.reserved)from private.production_stock_reservations r where r.factory_id=factory and r.material_id=material),0))::text,
 'return_pending',trim_scale(private.production_stock_return_pending(factory,material))::text,
 'reserved',trim_scale(private.production_stock_return_pending(factory,material)+coalesce((select sum(r.reserved)from private.production_stock_reservations r where r.factory_id=factory and r.material_id=material),0))::text,
 'available',trim_scale(private.production_stock_quantity(factory,material)-private.production_stock_return_pending(factory,material)-coalesce((select sum(r.reserved)from private.production_stock_reservations r where r.factory_id=factory and r.material_id=material),0))::text)into stock from public.materials m where m.factory_id=factory and m.id=material;
 with rows as(select jsonb_build_object('item_id',r.item_id,'code',o.code,'product',p.name,'product_ar',p.name_ar,'line',l.name,'line_ar',l.name_ar,
 'shift',r.evidence#>>'{occurrence,name}','shift_ar',r.evidence#>>'{occurrence,name_ar}','shift_start',r.evidence#>>'{occurrence,starts_at}','shift_end',r.evidence#>>'{occurrence,ends_at}',
 'required',trim_scale(r.required)::text,'reserved',trim_scale(r.reserved)::text,'updated_at',r.updated_at,
 'status',case when r.occurrence_key=occ#>>'{occurrence,occurrence_key}'and r.required>0 and o.status in('planned','active')and o.execution_interrupted_at is null
 and o.line_id is not null and o.start_time is not null and o.expected_finish>o.start_time and private.production_stock_eligible(factory,o.id)then 'active'
 when r.occurrence_key is distinct from occ#>>'{occurrence,occurrence_key}'or r.reserved>0 or r.required>0 then 'stale'else 'historical'end)x,r.updated_at,r.item_id,r.occurrence_key,r.reserved
 from private.production_stock_reservations r join public.production_orders o on o.factory_id=r.factory_id and o.id=r.item_id
 left join public.products p on p.factory_id=o.factory_id and p.id=o.product_id left join public.production_lines l on l.factory_id=o.factory_id and l.id=o.line_id
 where r.factory_id=factory and r.material_id=material)
 select coalesce((select jsonb_agg(x order by updated_at desc,item_id,occurrence_key)from rows where reserved>0 or x->>'status'='active'),'[]'),
 coalesce((select jsonb_agg(x order by updated_at desc,item_id,occurrence_key)from(select *from rows where reserved=0 and x->>'status'<>'active'order by updated_at desc,item_id,occurrence_key limit 30 offset(page-1)*30)h),'[]'),
 (select count(*)from rows where reserved=0 and x->>'status'<>'active')into active_rows,history,history_count;
 return jsonb_build_object('factory',factory,'material',material,'stock',stock,'active',active_rows,'history',history,'page',page,
 'history_total',history_count,'evaluated_at',clock_timestamp());
end$$;
revoke all on function public.production_stock_reservation_details(uuid,uuid,integer)from public,anon;
grant execute on function public.production_stock_reservation_details(uuid,uuid,integer)to authenticated,service_role;
