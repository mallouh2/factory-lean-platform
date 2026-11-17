-- Durable rejection finality for ambiguous execution retries. No historical backfill.

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
end$function$;

-- Serialize admission outside the exception subtransaction. Persist a rejected
-- UUID as audit evidence so an older delayed request can never later execute it.
create or replace function public.production_execution_submit(factory uuid,item uuid,operation text,reason text,fingerprint text,request_id uuid,output_confirmed boolean default false)returns jsonb
language plpgsql security definer set search_path=''as $$
declare result jsonb;state text;message text;detail text;intent jsonb;c private.production_execution_commands;o public.production_orders;begin
 perform private.require_permission(factory,'orders','view');perform private.require_permission(factory,'orders','edit');
 if request_id is null or operation is null or operation not in('INTERRUPT','RESUME','START_SELECTED')or reason is null or length(reason)>240 or fingerprint is null or fingerprint!~'^[a-f0-9]{64}$'or output_confirmed is null then raise exception 'execution_context_changed'using errcode='22023';end if;
 if current_setting('transaction_isolation')not in('read committed','read uncommitted')then raise exception 'execution_readiness_stale'using errcode='40001';end if;
 intent:=jsonb_build_object('item',item,'operation',operation,'reason',btrim(reason),'fingerprint',fingerprint,'output_confirmed',output_confirmed);
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.maintenance_planning_lock(factory);
 perform private.require_permission(factory,'orders','view');perform private.require_permission(factory,'orders','edit');
 select *into c from private.production_execution_commands where factory_id=factory and production_execution_commands.request_id=production_execution_submit.request_id;
 if found then
  if c.actor<>auth.uid()or c.item_id<>item or c.intent<>intent or c.result is null then raise exception 'execution_command_conflict'using errcode='22023';end if;
  if c.result->>'outcome'='REJECTED'then return c.result;end if;
  return jsonb_build_object('outcome','COMMITTED','request_id',request_id,'data',c.result);
 end if;
 select *into o from public.production_orders where factory_id=factory and id=item for update;if not found then raise exception 'not_found';end if;
 begin
  result:=public.production_execution_action(factory,item,operation,reason,fingerprint,request_id,output_confirmed);
  return jsonb_build_object('outcome','COMMITTED','request_id',request_id,'data',result);
 exception when others then
  get stacked diagnostics state=returned_sqlstate,message=message_text,detail=pg_exception_detail;
  result:=jsonb_build_object('outcome','REJECTED','request_id',request_id,'error',jsonb_build_object('code',state,'message',message,'details',case when message='production_material_not_ready'then detail end));
  insert into private.production_execution_commands(factory_id,request_id,actor,item_id,operation,reason,intent,before_state,result)
  values(factory,request_id,auth.uid(),item,operation,btrim(reason),intent,to_jsonb(o)||jsonb_build_object('execution_rejected',true),result);
  return result;
 end;
end$$;
;

CREATE OR REPLACE FUNCTION public.production_execution_outcome(factory uuid, item uuid, request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c private.production_execution_commands;current_state jsonb;begin
 perform private.require_permission(factory,'orders','view');perform private.require_permission(factory,'orders','edit');
 current_state:=public.production_execution_context(factory,item);
 select *into c from private.production_execution_commands where factory_id=factory and production_execution_commands.request_id=production_execution_outcome.request_id;
 if found then
  if c.actor<>auth.uid()or c.item_id<>item then raise exception 'permission_denied'using errcode='42501';end if;
  if c.result->>'outcome'='REJECTED'then return c.result||jsonb_build_object('intent',c.intent,'current',current_state);end if;
  if c.result is not null then return jsonb_build_object('outcome','COMMITTED','request_id',request_id,'intent',c.intent,'data',c.result,'current',current_state);end if;
 end if;
 -- No visible receipt may mean a transaction is still in flight. Never assert
 -- NOT_APPLIED, and never issue a replacement identity based on this read.
 return jsonb_build_object('outcome','UNKNOWN','request_id',request_id,'current',current_state);
end$function$;
