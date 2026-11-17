-- Post-F34.1: explicit outcomes, routine reason rules, read-only execution selection.
-- No historical order, inventory, run or Planning revision backfill.

create function private.execution_reason_required(f uuid,i uuid)returns boolean
language sql stable security definer set search_path=''as $$
 select i is distinct from(select q.id from public.production_orders q join public.production_orders selected on selected.factory_id=q.factory_id and selected.line_id=q.line_id and selected.id=i
 where q.factory_id=f and q.status='planned'and q.actual_finish is null and q.line_id is not null and q.start_time is not null and q.expected_finish>q.start_time
 and private.ordinary_output_remaining(f,q.id)>0 order by q.start_time,q.id limit 1)
$$;
create function private.execution_selection_state(f uuid,i uuid)returns jsonb
language plpgsql stable security definer set search_path=''as $$
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
 return jsonb_build_object('execution_remaining_quantity',remaining::text,'execution_reason_required',case when o.status='planned'then private.execution_reason_required(f,i)else false end,'execution_start_blocker',blocker);
end$$;
revoke all on function private.execution_reason_required(uuid,uuid),private.execution_selection_state(uuid,uuid)from public,anon,authenticated,service_role;

create or replace function public.production_execution_orders(factory uuid,cursor jsonb default null,page_size integer default 100)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare revision text;after_start timestamptz;after_id uuid;rows jsonb;all_rows jsonb;next_cursor jsonb;total integer;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'orders','view');
 if page_size is null or page_size not between 1 and 100 then raise exception 'execution_orders_invalid'using errcode='22023';end if;
 select coalesce(jsonb_agg(to_jsonb(o)||private.execution_selection_state(factory,o.id)||jsonb_build_object('execution_product_name',p.name,'execution_product_name_ar',p.name_ar)order by o.start_time,o.id),'[]')into all_rows
 from public.production_orders o left join public.products p on p.factory_id=o.factory_id and p.id=o.product_id
 where o.factory_id=factory and o.line_id is not null and o.start_time is not null and o.expected_finish>o.start_time;
 total:=jsonb_array_length(all_rows);revision:=encode(sha256(convert_to(all_rows::text,'UTF8')),'hex');
 if cursor is not null then
  if jsonb_typeof(cursor)<>'object'or(select count(*)from jsonb_object_keys(cursor))<>4 or cursor->>'factory'is distinct from factory::text or cursor->>'revision'is distinct from revision or cursor->>'after_start'is null or cursor->>'after_id'is null then raise exception 'execution_orders_changed'using errcode='40001';end if;
  after_start:=(cursor->>'after_start')::timestamptz;after_id:=(cursor->>'after_id')::uuid;
 end if;
 with page as materialized(select o from jsonb_array_elements(all_rows)p(o)where cursor is null or((o->>'start_time')::timestamptz,(o->>'id')::uuid)>(after_start,after_id)order by(o->>'start_time')::timestamptz,(o->>'id')::uuid limit page_size+1),
 selected as materialized(select o from page order by(o->>'start_time')::timestamptz,(o->>'id')::uuid limit page_size)
 select coalesce(jsonb_agg(o order by(o->>'start_time')::timestamptz,(o->>'id')::uuid),'[]'),
 case when(select count(*)from page)>page_size then(select jsonb_build_object('factory',factory,'revision',revision,'after_start',o->>'start_time','after_id',o->>'id')from selected order by(o->>'start_time')::timestamptz desc,(o->>'id')::uuid desc limit 1)end into rows,next_cursor from selected;
 return jsonb_build_object('factory',factory,'revision',revision,'total',total,'rows',rows,'next_cursor',next_cursor,'complete',next_cursor is null);
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then raise exception 'execution_orders_invalid'using errcode='22023';end$$;
;

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
  return c.result;
 end if;
 select *into o from public.production_orders where factory_id=factory and id=item for update;
 if not found then raise exception 'not_found';end if;
 if private.execution_fingerprint(factory,item)is distinct from fingerprint then raise exception 'execution_context_changed'using errcode='40001';end if;
 if(operation='INTERRUPT'or private.execution_reason_required(factory,item))and char_length(btrim(reason))<3 then raise exception 'execution_reason_required'using errcode='22023';end if;
 stamp:=clock_timestamp();
 insert into private.production_execution_commands(factory_id,request_id,actor,item_id,operation,reason,intent,before_state,started_at)
 values(factory,request_id,auth.uid(),item,operation,btrim(reason),intent,to_jsonb(o)||jsonb_build_object('execution_reason_required',operation='INTERRUPT'or private.execution_reason_required(factory,item)),stamp);
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
end$function$
;

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
 'remaining',private.ordinary_output_remaining(factory,item)::text,'reason_required',private.execution_reason_required(factory,item));
end$function$
;

-- A returned rejection proves the protected command subtransaction rolled back.
-- Transport/auth failure is never treated as proof that a write failed.
create function public.production_execution_submit(factory uuid,item uuid,operation text,reason text,fingerprint text,request_id uuid,output_confirmed boolean default false)returns jsonb
language plpgsql security definer set search_path=''as $$
declare result jsonb;state text;message text;detail text;begin
 perform private.require_permission(factory,'orders','view');perform private.require_permission(factory,'orders','edit');
 begin
  result:=public.production_execution_action(factory,item,operation,reason,fingerprint,request_id,output_confirmed);
  return jsonb_build_object('outcome','COMMITTED','request_id',request_id,'data',result);
 exception when others then
  get stacked diagnostics state=returned_sqlstate,message=message_text,detail=pg_exception_detail;
  return jsonb_build_object('outcome','REJECTED','request_id',request_id,'error',jsonb_build_object('code',state,'message',message,'details',case when message='production_material_not_ready'then detail end));
 end;
end$$;
create function public.production_execution_outcome(factory uuid,item uuid,request_id uuid)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare c private.production_execution_commands;current_state jsonb;begin
 perform private.require_permission(factory,'orders','view');perform private.require_permission(factory,'orders','edit');
 current_state:=public.production_execution_context(factory,item);
 select *into c from private.production_execution_commands where factory_id=factory and production_execution_commands.request_id=production_execution_outcome.request_id;
 if found then
  if c.actor<>auth.uid()or c.item_id<>item then raise exception 'permission_denied'using errcode='42501';end if;
  if c.result is not null then return jsonb_build_object('outcome','COMMITTED','request_id',request_id,'intent',c.intent,'data',c.result,'current',current_state);end if;
 end if;
 -- No visible receipt may mean a transaction is still in flight. Never assert
 -- NOT_APPLIED, and never issue a replacement identity based on this read.
 return jsonb_build_object('outcome','UNKNOWN','request_id',request_id,'current',current_state);
end$$;
revoke all on function public.production_execution_submit(uuid,uuid,text,text,text,uuid,boolean),public.production_execution_outcome(uuid,uuid,uuid)from public,anon,service_role;
grant execute on function public.production_execution_submit(uuid,uuid,text,text,text,uuid,boolean),public.production_execution_outcome(uuid,uuid,uuid)to authenticated;

