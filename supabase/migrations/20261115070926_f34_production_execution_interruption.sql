-- F34: new execution metadata is null for all historical records.
alter table public.production_orders add column execution_started_at timestamptz,
 add column execution_interrupted_at timestamptz;
alter table public.production_orders add constraint execution_current_run_time
 check(execution_started_at is null or actual_start is not null and execution_started_at>=actual_start);
alter table public.production_orders add constraint execution_interrupted_state
 check(execution_interrupted_at is null or status='planned'and actual_start is not null and actual_finish is null);

create table private.production_execution_commands(
 factory_id uuid not null,request_id uuid not null,actor uuid not null references auth.users(id),
 item_id uuid not null,operation text not null,reason text not null,intent jsonb not null,
 before_state jsonb not null,result jsonb,started_at timestamptz not null default clock_timestamp(),
 backend integer not null default pg_backend_pid(),transaction_id bigint not null default txid_current(),
 primary key(factory_id,request_id),foreign key(factory_id,item_id)references public.production_orders(factory_id,id)
);
create table private.production_execution_runs(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null,item_id uuid not null,line_id uuid not null,
 started_at timestamptz not null,ended_at timestamptz,state text not null check(state in('ARMED','ACTIVE','INTERRUPTED','FINISHED')),
 planned jsonb not null,effective_start timestamptz not null,effective_finish timestamptz not null,
 start_actor uuid references auth.users(id),end_actor uuid references auth.users(id),reason text,
 dispatch_override boolean not null default false,
 request_id uuid,recorded_before jsonb not null,recorded_after jsonb,
 foreign key(factory_id,item_id)references public.production_orders(factory_id,id),
 foreign key(factory_id,line_id)references public.production_lines(factory_id,id),
 check(effective_finish>effective_start),check(ended_at is null or ended_at>=started_at),
 check((state in('ARMED','ACTIVE'))=(ended_at is null)),unique(factory_id,item_id,started_at)
);
create unique index production_execution_one_open_run on private.production_execution_runs(factory_id,item_id)where ended_at is null;
create table private.production_custody_origins(
 factory_id uuid not null,item_id uuid not null,recorded_line_id uuid not null,
 captured_at timestamptz not null default clock_timestamp(),actor uuid not null references auth.users(id),
 evidence jsonb not null,primary key(factory_id,item_id),
 foreign key(factory_id,item_id)references public.production_orders(factory_id,id),
 foreign key(factory_id,recorded_line_id)references public.production_lines(factory_id,id)
);
alter table private.production_execution_commands enable row level security;
alter table private.production_execution_runs enable row level security;
alter table private.production_custody_origins enable row level security;
revoke all on private.production_execution_commands,private.production_execution_runs,private.production_custody_origins from public,anon,authenticated,service_role;

create function private.execution_command_allowed(f uuid,i uuid,actions text[])returns boolean
language sql stable security definer set search_path=''as $$
 select exists(select 1 from private.production_execution_commands c where c.factory_id=f and c.item_id=i
 and c.actor=auth.uid()and c.backend=pg_backend_pid()and c.transaction_id=txid_current()
 and c.operation=any(actions)and c.result is null)
$$;
create function private.recorded_custody_line(f uuid,i uuid)returns uuid
language sql stable security definer set search_path=''as $$
 select coalesce((select recorded_line_id from private.production_custody_origins where factory_id=f and item_id=i),
 (select line_id from public.production_orders where factory_id=f and id=i))
$$;
create function private.execution_fact_immutable()returns trigger language plpgsql set search_path=''as $$
begin raise exception 'execution_history_immutable'using errcode='22023';end$$;
create trigger production_custody_origin_immutable before update or delete on private.production_custody_origins
for each row execute function private.execution_fact_immutable();
revoke all on function private.execution_command_allowed(uuid,uuid,text[]),private.recorded_custody_line(uuid,uuid),
private.execution_fact_immutable()from public,anon,authenticated,service_role;


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

  if row(old.execution_started_at,old.execution_interrupted_at)is distinct from row(new.execution_started_at,new.execution_interrupted_at)
   and not private.execution_command_allowed(old.factory_id,old.id,array['INTERRUPT','RESUME','START_SELECTED'])then raise exception 'execution_use_command';end if;
  if private.execution_command_allowed(old.factory_id,old.id,array['INTERRUPT'])and old.status='active'and new.status='planned'
   and new.execution_interrupted_at is not null and new.actual_start=old.actual_start and new.actual_finish is null
   and new.line_id is null and new.start_time is null and new.expected_finish is null then return new;end if;
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
$function$
;

CREATE OR REPLACE FUNCTION private.plan_product_item_without_maintenance(f uuid, item uuid, target_line uuid, planned_start timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  target public.production_orders%rowtype;
  matches integer;
  typed_matches integer;
  slowest numeric;
  fastest numeric;
  shortest_setup integer;
  longest_setup integer;
  minutes_required numeric;
  effective_start timestamptz;
  planned_finish timestamptz;
begin
  perform private.require_permission(f,'orders','edit');
  select * into target from public.production_orders
    where factory_id=f and id=item for update;
  if not found then raise exception 'not_found'; end if;
  if target.status<>'planned' or target.actual_finish is not null or
   (target.execution_interrupted_at is null and(target.produced_quantity>0 or target.actual_start is not null)) then
    raise exception 'planning_already_started'; end if;
  if target_line is null and planned_start is null then
    update public.production_orders set line_id=null,start_time=null,expected_finish=null
      where factory_id=f and id=item;
    return item;
  end if;
  if target_line is null or planned_start is null or planned_start<now()-interval '1 minute' then
    raise exception 'planning_invalid_start'; end if;
  perform 1 from public.production_lines
    where factory_id=f and id=target_line and not archived for update;
  if not found then raise exception 'planning_incompatible_line'; end if;
  select count(*),count(*) filter (where cap.rate_unit=target.unit),
    min(cap.rate) filter (where cap.rate_unit=target.unit),
    max(cap.rate) filter (where cap.rate_unit=target.unit),
    min(cap.setup_minutes),max(cap.setup_minutes)
    into matches,typed_matches,slowest,fastest,shortest_setup,longest_setup
  from public.work_centers center
  join public.work_center_capabilities cap
    on cap.factory_id=center.factory_id and cap.work_center_id=center.id
      and cap.product_id=target.product_id
  where center.factory_id=f and center.line_id=target_line and not center.archived;
  if matches=0 then raise exception 'planning_incompatible_line'; end if;
  if target.unit not in ('meter','piece','kg') or typed_matches<>matches then
    raise exception 'planning_missing_rate'; end if;
  if slowest<>fastest then raise exception 'planning_ambiguous_rate'; end if;
  if shortest_setup<>longest_setup then raise exception 'planning_ambiguous_setup'; end if;
  minutes_required:=ceil((case when target.execution_interrupted_at is not null then private.ordinary_output_remaining(f,item)else target.target_quantity end) * 60 / slowest)+shortest_setup;
  if minutes_required<1 or minutes_required>5256000 then
    raise exception 'planning_invalid_quantity'; end if;
  effective_start:=private.next_working_start(f,planned_start);
  planned_finish:=private.finish_after_working_minutes(f,effective_start,minutes_required::integer);
  if exists(
    select 1 from public.production_orders other
    where other.factory_id=f and other.id<>item and other.line_id=target_line
      and other.status in ('planned','active') and
      (other.start_time is null or other.expected_finish is null)
  ) then raise exception 'planning_unknown_block'; end if;
  if exists(
    select 1 from public.production_orders other
    where other.factory_id=f and other.id<>item and other.line_id=target_line
      and other.status in ('planned','active')
      and effective_start<other.expected_finish and planned_finish>other.start_time
  ) then raise exception 'planning_overlap'; end if;
  update public.production_orders set
    line_id=target_line,start_time=effective_start,expected_finish=planned_finish
    where factory_id=f and id=item;
  return item;
end;
$function$
;

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
 if private.output_work_consumed(old.factory_id,old.id)>0 then raise exception 'planning_material_consumed';end if;raise exception 'planning_material_custody';end if; if not old.planning_ever_scheduled then
    kind := 'initial';
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
$function$
;

CREATE OR REPLACE FUNCTION private.material_line_custody_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$begin
 if new.line_id is distinct from old.line_id and new.line_id is not null and new.line_id is distinct from private.recorded_custody_line(old.factory_id,old.id)and exists(select 1 from private.material_request_progress p join public.material_requests m on m.factory_id=p.factory_id and m.id=p.request_id where p.factory_id=new.factory_id and m.production_item_id=new.id and(p.reserved>0 or p.issued>0))then raise exception 'planning_material_return_required'using errcode='22023';end if;return new;end$function$
;

CREATE OR REPLACE FUNCTION private.material_return_context_before_stock(factory uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$declare rows jsonb;warehouses jsonb;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'orders','view');
 select coalesce(jsonb_agg(x order by x->>'name',x->>'line_name'),'[]')into rows from(
 select jsonb_build_object('material',m.id,'name',m.name,'name_ar',m.name_ar,'unit',m.unit,'line',l.id,'line_name',l.name,'line_name_ar',l.name_ar,'available',trim_scale(sum(private.material_unused(factory,r.id)))::text)x
 from public.material_requests r join private.material_request_progress p on p.factory_id=r.factory_id and p.request_id=r.id join public.materials m on m.factory_id=r.factory_id and m.id=r.material_id join public.production_orders o on o.factory_id=r.factory_id and o.id=r.production_item_id join public.production_lines l on l.factory_id=o.factory_id and l.id=private.recorded_custody_line(o.factory_id,o.id)
 where r.factory_id=factory and m.inventory_kind='RAW_MATERIAL'and m.unit=r.unit and not private.output_work_held(factory,o.id)and private.material_unused(factory,r.id)>0 group by m.id,l.id)t;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'name_ar',name_ar)order by name,id),'[]')into warehouses from public.factory_warehouses where factory_id=factory and storage_class='RAW'and active;
 return jsonb_build_object('rows',rows,'warehouses',warehouses);end$function$
;

CREATE OR REPLACE FUNCTION private.material_return_action_before_stock(factory uuid, operation text, payload jsonb, request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare h private.material_returns;old private.material_return_events;intent jsonb:=jsonb_build_object('operation',operation,'payload',payload);before_value jsonb;result jsonb;r record;q numeric;remain numeric;take numeric;v_unit text;mat uuid;line uuid;warehouse uuid;move uuid;begin
 perform private.require_permission(factory,'factory','view');
 if operation='RECEIVE'then perform private.require_permission(factory,'warehouse','issue');perform private.require_permission(factory,'warehouse','view');else perform private.require_permission(factory,'orders','edit');perform private.require_permission(factory,'orders','view');end if;
 if operation is null or operation not in('CREATE','RECEIVE','CANCEL')or request_id is null or payload is null or jsonb_typeof(payload)<>'object'or octet_length(payload::text)>8000 then raise exception 'material_invalid'using errcode='22023';end if;
 if current_setting('transaction_isolation')not in('read committed','read uncommitted')then raise exception 'material_changed'using errcode='40001';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform pg_advisory_xact_lock(hashtextextended(factory::text||':structure',0));
 select *into old from private.material_return_events e where e.factory_id=factory and e.retry_id=material_return_action_before_stock.request_id;
 if found then if old.actor is distinct from auth.uid()or old.intent<>intent then raise exception 'request_conflict'using errcode='40001';end if;return old.after_state;end if;
 if length(coalesce(payload->>'note',''))>2000 then raise exception 'material_invalid'using errcode='22023';end if;
 if operation in('CREATE','RECEIVE')then if jsonb_typeof(payload->'quantity')is distinct from 'string'or payload->>'quantity'!~'^[0-9]+([.][0-9]+)?$'then raise exception 'material_quantity'using errcode='22023';end if;q:=(payload->>'quantity')::numeric;if q<=0 then raise exception 'material_quantity'using errcode='22023';end if;end if;
 if operation='CREATE'then
 if exists(select 1 from jsonb_object_keys(payload)k where k not in('material','line','warehouse','quantity','note'))then raise exception 'material_invalid'using errcode='22023';end if;
 mat:=(payload->>'material')::uuid;line:=(payload->>'line')::uuid;warehouse:=(payload->>'warehouse')::uuid;
 select m.unit into v_unit from public.materials m where m.factory_id=factory and m.id=mat and m.inventory_kind='RAW_MATERIAL';
 if v_unit is null or not exists(select 1 from public.production_lines where factory_id=factory and id=line)or not exists(select 1 from public.factory_warehouses where factory_id=factory and id=warehouse and storage_class='RAW'and active)then raise exception 'material_return_scope'using errcode='22023';end if;
 insert into private.material_returns(factory_id,material_id,unit,source_line_id,warehouse_id,requested,note,created_by)values(factory,mat,v_unit,line,warehouse,q,coalesce(payload->>'note',''),auth.uid())returning *into h;remain:=q;
 for r in select m.id,private.material_unused(factory,m.id)available from public.material_requests m join private.material_request_progress p on p.factory_id=m.factory_id and p.request_id=m.id join public.production_orders o on o.factory_id=m.factory_id and o.id=m.production_item_id where m.factory_id=factory and m.material_id=mat and m.unit=v_unit and private.recorded_custody_line(o.factory_id,o.id)=line and not private.output_work_held(factory,o.id)and private.material_unused(factory,m.id)>0 order by m.issued_at,m.id for update of p loop
 take:=least(remain,r.available);if take>0 then insert into private.material_return_allocations values(factory,h.id,r.id,take,0);remain:=remain-take;end if;exit when remain=0;end loop;
 if remain<>0 then raise exception 'material_return_unavailable'using errcode='22023';end if;
 else
 if exists(select 1 from jsonb_object_keys(payload)k where k not in('id','revision','quantity','physical_confirmation','note'))then raise exception 'material_invalid'using errcode='22023';end if;
 select *into h from private.material_returns where factory_id=factory and id=(payload->>'id')::uuid for update;
 if not found then raise exception 'material_invalid'using errcode='22023';end if;
 if h.revision is distinct from(payload->>'revision')::integer then raise exception 'material_changed'using errcode='40001';end if;
 if h.status not in('REQUESTED','PARTIALLY_RECEIVED')then raise exception 'material_return_closed'using errcode='22023';end if;
 before_value:=private.material_return_snapshot(factory,h.id);
 if operation='CANCEL'then
 if h.created_by<>auth.uid()then raise exception 'permission_denied'using errcode='42501';end if;
 if length(btrim(coalesce(payload->>'note','')))<3 then raise exception 'material_return_reason'using errcode='22023';end if;
 update private.material_returns set status='CANCELLED',revision=revision+1 where factory_id=factory and id=h.id;
 else
 if payload->'physical_confirmation'is distinct from 'true'::jsonb or q>h.requested-h.received then raise exception 'material_quantity'using errcode='22023';end if;
 if not exists(select 1 from public.factory_warehouses where factory_id=factory and id=h.warehouse_id and storage_class='RAW'and active)then raise exception 'material_return_scope'using errcode='22023';end if;
 remain:=q;
 for r in select a.*,p.issued,p.consumed,m.production_item_id from private.material_return_allocations a join private.material_request_progress p on p.factory_id=a.factory_id and p.request_id=a.material_request_id join public.material_requests m on m.factory_id=a.factory_id and m.id=a.material_request_id where a.factory_id=factory and a.return_id=h.id order by a.material_request_id for update of a,p loop
 take:=least(remain,r.quantity-r.received);if take>0 then
 if private.output_work_held(factory,r.production_item_id)or r.issued-r.consumed-(private.material_return_balance(factory,r.material_request_id)->>'returned')::numeric<take then raise exception 'material_return_unavailable'using errcode='22023';end if;
 update private.material_return_allocations set received=received+take where factory_id=factory and return_id=h.id and material_request_id=r.material_request_id;remain:=remain-take;end if;exit when remain=0;end loop;
 if remain<>0 then raise exception 'material_return_unavailable'using errcode='22023';end if;
 move:=gen_random_uuid();insert into public.inventory_transactions(id,factory_id,material_id,quantity,kind,unit,reference,note,created_by)values(move,factory,h.material_id,q,'material_return',h.unit,h.id::text,'Independent raw material return '||h.code,auth.uid());
 update private.material_returns set received=received+q,status=case when received+q=requested then 'RECEIVED'else 'PARTIALLY_RECEIVED'end,revision=revision+1 where factory_id=factory and id=h.id;
 end if;end if;
 result:=private.material_return_snapshot(factory,h.id);
 insert into private.material_return_events(factory_id,return_id,retry_id,actor,operation,intent,before_state,after_state,movement_id)values(factory,h.id,request_id,auth.uid(),operation,intent,before_value,result,move);
 return result;end$function$
;

CREATE OR REPLACE FUNCTION private.start_product_item_before_readiness(factory uuid, item uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  target public.production_orders%rowtype;
  first_item uuid;
begin
  perform private.require_permission(factory,'orders','edit');
  -- Lock before item/center rows, shared with transfer and layout operations.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(factory::text||':structure',0));
  select * into target from public.production_orders
    where factory_id= factory and id=item for update;
  if not found then raise exception 'not_found'; end if;
  if target.status<>'planned'or target.actual_finish is not null or
  ((target.actual_start is not null or target.produced_quantity>0)and not(target.execution_interrupted_at is not null and private.execution_command_allowed(factory,item,array['RESUME']))) then
    raise exception 'execution_already_started';
  end if;
  if target.line_id is null or target.start_time is null
    or target.expected_finish is null or target.expected_finish <= target.start_time
    or not exists(select 1 from public.production_lines l
      where l.factory_id=factory and l.id=target.line_id and not l.archived) then
    raise exception 'execution_plan_required';
  end if;

  -- Serialize competing starts on this line before reading its queue.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(target.line_id::text,0));
  if exists(select 1 from public.production_orders other
    where other.factory_id=factory and other.line_id=target.line_id
      and other.status='active') then
    raise exception 'execution_line_busy';
  end if;
  select other.id into first_item from public.production_orders other
    where other.factory_id=factory and other.line_id=target.line_id
      and other.status='planned' and other.actual_start is null
      and other.actual_finish is null and other.start_time is not null
      and other.expected_finish > other.start_time
    order by other.start_time,other.id limit 1;
  if first_item is distinct from item and not private.execution_command_allowed(factory,item,array['RESUME','START_SELECTED'])then
    raise exception 'execution_out_of_sequence';
  end if;

  update public.production_orders set status='active',
    actual_start=coalesce(target.actual_start,(select started_at from private.production_execution_runs where factory_id=factory and item_id=item and state='ARMED'),pg_catalog.clock_timestamp()),
    execution_started_at=case when private.execution_command_allowed(factory,item,array['RESUME','START_SELECTED'])then(select started_at from private.production_execution_runs where factory_id=factory and item_id=item and state='ARMED')else null end,
    execution_interrupted_at=null
    where factory_id=factory and id=item;
  return item;
end;
$function$;

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
 return jsonb_build_object('occurrence',occ,'expected_output',trim_scale(output)::text,'unit',o.unit,'requirement',req,'inputs',rows,'evaluated_at',stamp);end$function$
;

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

CREATE OR REPLACE FUNCTION private.production_recording_eligibility(job production_orders, occurrence jsonb, evaluated timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET "TimeZone" TO 'UTC'
AS $function$
declare reason text;k text;planned_line uuid;live boolean;evidence_count bigint;begin
 job.actual_start:=coalesce(job.execution_started_at,job.actual_start);
 if evaluated is null or not isfinite(evaluated) or evaluated<(occurrence->>'starts_at')::timestamptz or evaluated>=(occurrence->>'ends_at')::timestamptz then reason:='OUTSIDE_CURRENT_SHIFT';
 elsif job.factory_id is distinct from (occurrence->>'factory_id')::uuid or job.line_id is null or not exists(select 1 from public.production_lines where factory_id=job.factory_id and id=job.line_id) then reason:='EXECUTED_LINE_UNVERIFIED';
 elsif job.actual_start is null then reason:='ACTUAL_START_MISSING';
 elsif job.actual_start>evaluated or (job.actual_finish is not null and job.actual_finish>evaluated) then reason:='EXECUTION_IN_FUTURE';
 elsif (job.status='active' and job.actual_finish is not null) or (job.status='completed' and (job.actual_finish is null or job.actual_finish<=job.actual_start)) or job.status not in ('active','completed') then reason:='EXECUTION_STATE_INVALID';
 elsif job.actual_start>=(occurrence->>'ends_at')::timestamptz or (job.actual_finish is not null and job.actual_finish<=(occurrence->>'starts_at')::timestamptz) then reason:='OUTSIDE_CURRENT_SHIFT';
 else
  select after_line_id into planned_line from public.production_plan_revisions where factory_id=job.factory_id and item_id=job.id and changed_at<=job.actual_start order by revision_no desc limit 1;
  if not job.planning_ever_scheduled or planned_line is distinct from job.line_id or exists(
   select 1 from public.production_plan_revisions where factory_id=job.factory_id and item_id=job.id and changed_at>job.actual_start and after_line_id is distinct from job.line_id)
  then reason:='EXECUTED_LINE_UNVERIFIED';end if;
 end if;
 k:=case when job.actual_start is not null and job.line_id is not null then encode(sha256(convert_to(jsonb_build_array(1,job.factory_id,job.id,job.line_id,to_char(job.actual_start,'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))::text,'UTF8')),'hex') end;
 -- Bind every new recording, including zero-Good Scrap/unfinished declarations.
 -- Item/factory locks serialize admission; exact UUID replay precedes this check.
 select count(*) into evidence_count from public.production_entries where factory_id=job.factory_id and order_id=job.id;
 live:=false;
 if reason is null and job.status='active' then
  live:=exists(select 1 from private.production_recording_units(job.factory_id) u where u.unit_kind='line' and u.unit_id=job.line_id and u.item_id=job.id);
 end if;
 return jsonb_build_object('included',reason is null,'preview_selectable',reason is null,'execution_key',k,
  'policy_late_eligible',reason is null and job.status='completed','active_recording_eligible',coalesce(live,false),
  'late_recording_available',false,'blocked_reason',coalesce(reason,case when job.status='completed' then 'PHASE1_READ_ONLY' when not live then 'ACTIVE_UNIT_UNAVAILABLE' end),
  'resource_evidence',jsonb_build_object('line','PROTECTED_PLAN_EXECUTION','machines','UNKNOWN'),
  'context_hash',encode(sha256(convert_to(jsonb_build_array(1,job.factory_id,job.id,job.product_id,job.line_id,job.actual_start,job.actual_finish,job.status,job.unit,job.target_quantity,job.accepted_good_quantity,job.fulfillment_good_quantity,occurrence->>'occurrence_key',live,evidence_count, (select coalesce(sum(quantity),0) from private.production_compensation where factory_id=job.factory_id and item_id=job.id and mode='ACTIVE'),private.compensation_recorded(job.factory_id,job.id),(select coalesce(sum(private.compensation_remaining(job.factory_id,id)),0) from private.production_compensation where factory_id=job.factory_id and item_id=job.id and mode='ACTIVE'))::text,'UTF8')),'hex'));
end$function$
;

CREATE OR REPLACE FUNCTION private.current_recording_v3_context(f uuid, i uuid, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET "TimeZone" TO 'UTC'
AS $function$
declare job public.production_orders;resolved jsonb;occ jsonb;eligible jsonb;stamp timestamptz;late boolean;gate private.production_recording_v3_activation;begin
 if current_setting('transaction_isolation')<>'read committed' then raise exception 'recording_isolation' using errcode='40001';end if;
 perform private.recording_v3_authorize(f);
 select * into job from public.production_orders where factory_id=f and id=i;
 if not found then raise exception 'recording_stale_context' using errcode='40001';end if;
 late:=job.status='completed';
 if late then
  select * into gate from private.production_recording_v3_activation where factory_id=f for share;
  -- A completed execution may be reported only in the authoritative OPEN
  -- occurrence in which it ran. This does not activate after-shift recording.
  -- Keep the existing gate-row-before-item lock order; no gate value is changed.
 end if;
 select * into job from public.production_orders where factory_id=f and id=i for update;
 job.actual_start:=coalesce(job.execution_started_at,job.actual_start);
 stamp:=clock_timestamp();resolved:=private.resolve_production_occurrence(f,stamp);occ:=resolved->'occurrence';
 if resolved->>'available' is distinct from 'true' then raise exception 'recording_shift_unavailable' using errcode='22023';end if;
 eligible:=private.production_recording_eligibility(job,occ,stamp);
 if eligible->>'included' is distinct from 'true' or (not late and eligible->>'active_recording_eligible' is distinct from 'true')
 or p#>>'{recording_context,execution_key}' is distinct from eligible->>'execution_key'
 or p#>>'{recording_context,occurrence_key}' is distinct from occ->>'occurrence_key'
 or p#>>'{recording_context,context_hash}' is distinct from eligible->>'context_hash'
 or p->>'unit_kind' is distinct from 'line' or (p->>'production_unit')::uuid is distinct from job.line_id
 then raise exception 'recording_stale_context' using errcode='40001';end if;
 if job.actual_start<(occ->>'starts_at')::timestamptz and p#>>'{recording_context,current_shift_quantity_confirmed}' is distinct from 'true'
 then raise exception 'recording_shift_declaration' using errcode='22023';end if;
 if p->>'shift' is not null and (p->>'shift')::uuid is distinct from (occ->>'shift_id')::uuid or p->>'shift_override_reason' is not null
 then raise exception 'recording_invalid_context' using errcode='22023';end if;
 if p->>'startup_at' is not null and ((p->>'startup_at')::timestamptz<greatest(job.actual_start,(occ->>'starts_at')::timestamptz)
 or (p->>'startup_at')::timestamptz>coalesce(job.actual_finish,stamp)) then raise exception 'lean_invalid' using errcode='22023';end if;
 perform private.materialize_production_occurrence(f,occ);
 return jsonb_build_object('occurrence',occ,'eligibility',eligible,'kind',case when p->>'input_lot' is not null then 'WIP_PROCESSING' when late then 'LATE_ORDINARY' else 'ACTIVE_ORDINARY' end,
 'start',job.actual_start,'finish',job.actual_finish,'period_start',greatest(job.actual_start,(occ->>'starts_at')::timestamptz),
 'period_end',least(coalesce(job.actual_finish,stamp),(occ->>'ends_at')::timestamptz),'payload',p);
end$function$;

CREATE OR REPLACE FUNCTION private.historical_recording_eligibility(job production_orders, occurrence jsonb, evaluated timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET "TimeZone" TO 'UTC'
AS $function$
declare reason text;k text;planned_line uuid;live boolean;evidence_count bigint;begin
 job.actual_start:=coalesce(job.execution_started_at,job.actual_start);
 if evaluated is null or not isfinite(evaluated) then reason:='OUTSIDE_CURRENT_SHIFT';
 elsif job.factory_id is distinct from (occurrence->>'factory_id')::uuid or job.line_id is null or not exists(select 1 from public.production_lines where factory_id=job.factory_id and id=job.line_id) then reason:='EXECUTED_LINE_UNVERIFIED';
 elsif job.actual_start is null then reason:='ACTUAL_START_MISSING';
 elsif job.actual_start>evaluated or (job.actual_finish is not null and job.actual_finish>evaluated) then reason:='EXECUTION_IN_FUTURE';
 elsif (job.status='active' and job.actual_finish is not null) or (job.status='completed' and (job.actual_finish is null or job.actual_finish<=job.actual_start)) or job.status not in ('active','completed') then reason:='EXECUTION_STATE_INVALID';
 elsif job.actual_start>=(occurrence->>'ends_at')::timestamptz or (job.actual_finish is not null and job.actual_finish<=(occurrence->>'starts_at')::timestamptz) then reason:='OUTSIDE_CURRENT_SHIFT';
 else
  select after_line_id into planned_line from public.production_plan_revisions where factory_id=job.factory_id and item_id=job.id and changed_at<=job.actual_start order by revision_no desc limit 1;
  if not job.planning_ever_scheduled or planned_line is distinct from job.line_id or exists(
   select 1 from public.production_plan_revisions where factory_id=job.factory_id and item_id=job.id and changed_at>job.actual_start and after_line_id is distinct from job.line_id)
  then reason:='EXECUTED_LINE_UNVERIFIED';end if;
 end if;
 k:=case when job.actual_start is not null and job.line_id is not null then encode(sha256(convert_to(jsonb_build_array(1,job.factory_id,job.id,job.line_id,to_char(job.actual_start,'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))::text,'UTF8')),'hex') end;
 -- Bind every new recording, including zero-Good Scrap/unfinished declarations.
 -- Item/factory locks serialize admission; exact UUID replay precedes this check.
 select count(*) into evidence_count from public.production_entries where factory_id=job.factory_id and order_id=job.id;
 live:=false;
 if reason is null and job.status='active' then
  live:=exists(select 1 from private.production_recording_units(job.factory_id) u where u.unit_kind='line' and u.unit_id=job.line_id and u.item_id=job.id);
 end if;
 return jsonb_build_object('included',reason is null,'preview_selectable',reason is null,'execution_key',k,
  'policy_late_eligible',reason is null and job.status='completed','active_recording_eligible',coalesce(live,false),
  'late_recording_available',false,'blocked_reason',coalesce(reason,case when job.status='completed' then 'PHASE1_READ_ONLY' when not live then 'ACTIVE_UNIT_UNAVAILABLE' end),
  'resource_evidence',jsonb_build_object('line','PROTECTED_PLAN_EXECUTION','machines','UNKNOWN'),
  'context_hash',encode(sha256(convert_to(jsonb_build_array(1,job.factory_id,job.id,job.product_id,job.line_id,job.actual_start,job.actual_finish,job.status,job.unit,job.target_quantity,job.accepted_good_quantity,job.fulfillment_good_quantity,occurrence->>'occurrence_key',live,evidence_count, (select coalesce(sum(quantity),0) from private.production_compensation where factory_id=job.factory_id and item_id=job.id and mode='ACTIVE'),private.compensation_recorded(job.factory_id,job.id),(select coalesce(sum(private.compensation_remaining(job.factory_id,id)),0) from private.production_compensation where factory_id=job.factory_id and item_id=job.id and mode='ACTIVE'))::text,'UTF8')),'hex'));
end$function$;

CREATE OR REPLACE FUNCTION private.recording_v3_context(f uuid, i uuid, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare h private.historical_recording_requests;j public.production_orders;e jsonb;begin
 select r.* into h from private.historical_recording_admission a join private.historical_recording_requests r on r.id=a.request_id
 where a.transaction_id=txid_current() and a.approver=auth.uid() and r.factory_id=f and r.item_id=i;
 if not found then return private.current_recording_v3_context(f,i,p);end if;
 perform private.recording_v3_authorize(f);perform private.require_permission(f,'orders','approve');
 if (h.submitted_by=auth.uid()and not exists(select 1 from private.historical_auto_approval_audit a where a.request_id=h.id and a.factory_id=f and a.authority_user_id=auth.uid()and a.transaction_id=txid_current())) or p is distinct from private.recording_request_payload(f,h.payload-'output_groups')->'payload' then raise exception 'permission_denied' using errcode='42501';end if;
 select * into j from public.production_orders where factory_id=f and id=i for update;
 j.actual_start:=coalesce(j.execution_started_at,j.actual_start);
 e:=private.historical_recording_eligibility(j,h.occurrence,clock_timestamp());
 if e->>'included' is distinct from 'true' or e->>'context_hash' is distinct from h.context_hash then raise exception 'recording_stale_context' using errcode='40001';end if;
 perform private.materialize_production_occurrence(f,h.occurrence);
 return jsonb_build_object('occurrence',h.occurrence,'eligibility',e,'kind',case when j.actual_finish is null then 'ACTIVE_ORDINARY' else 'LATE_ORDINARY' end,'start',j.actual_start,'finish',j.actual_finish,
 'period_start',greatest(j.actual_start,(h.occurrence->>'starts_at')::timestamptz),'period_end',least(coalesce(j.actual_finish,clock_timestamp()),(h.occurrence->>'ends_at')::timestamptz),'payload',p);
end$function$;

CREATE OR REPLACE FUNCTION public.historical_production_read(factory uuid, day date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare enabled boolean;choices jsonb;requests jsonb;approver boolean;begin
 perform private.require_permission(factory,'orders','view');
 select a.enabled into enabled from private.historical_recording_activation a where factory_id=factory;
 if enabled is distinct from true or not private.manufactured_output_enabled(factory) then return jsonb_build_object('factory_id',factory,'available',false,'choices','[]'::jsonb,'requests','[]'::jsonb);end if;
 approver:=private.has_permission(factory,'orders','approve');
 select coalesce(jsonb_agg(row order by row#>>'{occurrence,ends_at}' desc),'[]'::jsonb) into choices from(
  select jsonb_build_object('occurrence',o,'work',jsonb_agg(jsonb_build_object('item',j.id,'code',j.code,'product',p.name,'product_ar',p.name_ar,'unit',j.unit,'remaining',greatest(j.target_quantity-j.fulfillment_good_quantity,0)::text,'line',j.line_id,'line_name',l.name,'actual_start',coalesce(j.execution_started_at,j.actual_start),'actual_finish',j.actual_finish,'eligibility',e))) row
  from (select distinct v as o from private.historical_recording_occurrences(factory,day)v)occ
  join public.production_orders j on j.factory_id=factory and j.actual_start<(o->>'ends_at')::timestamptz and coalesce(j.actual_finish,clock_timestamp())>(o->>'starts_at')::timestamptz
  join public.products p on p.factory_id=factory and p.id=j.product_id join public.production_lines l on l.factory_id=factory and l.id=j.line_id
  cross join lateral private.historical_recording_eligibility(j,o,clock_timestamp()) e
  where e->>'included'='true' and not exists(select 1 from private.manufactured_completion_work w where w.factory_id=factory and w.item_id=j.id and w.choice='COMPLETE') group by o
 )a;
 select coalesce(jsonb_agg(row order by submitted_at desc),'[]'::jsonb) into requests from(
  select r.submitted_at,jsonb_build_object('id',r.id,'factory_id',r.factory_id,'submitted_by',r.submitted_by,'operator',m.display_name,'item',r.item_id,'code',j.code,'product',p.name,'unit',j.unit,'occurrence',r.occurrence,'payload',r.payload,'submitted_at',r.submitted_at,'state',coalesce(d.decision,'PENDING'),'receipt',d.receipt,'can_approve',approver and r.submitted_by<>auth.uid() and d.request_id is null) row
  from private.historical_recording_requests r join public.production_orders j on j.factory_id=factory and j.id=r.item_id
  join public.products p on p.factory_id=factory and p.id=j.product_id join public.memberships m on m.factory_id=factory and m.user_id=r.submitted_by
  left join private.historical_recording_decisions d on d.request_id=r.id where r.factory_id=factory and (r.submitted_by=auth.uid() or approver) order by r.submitted_at desc limit 100
 )a;
 return jsonb_build_object('factory_id',factory,'available',true,'choices',choices,'requests',requests);
end$function$;

CREATE OR REPLACE FUNCTION public.production_shift_work(factory uuid, cursor jsonb DEFAULT NULL::jsonb, page_size integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET "TimeZone" TO 'UTC'
AS $function$
declare stamp timestamptz:=clock_timestamp();evaluated timestamptz;ctx jsonb;occ jsonb;rev bigint;schedule_rev bigint;
 context_key text;rows jsonb;total bigint;next_page jsonb;can_edit boolean;late_available boolean;begin
 perform private.require_permission(factory,'orders','view');
 if page_size is null or page_size not between 1 and 100 or (cursor is not null and (jsonb_typeof(cursor)<>'object' or octet_length(cursor::text)>3000 or
  not (cursor ?& array['version','factory','occurrence','as_of','revision','schedule_revision','page_size','context','last_state','last_start','last_id']) or
  exists(select 1 from jsonb_object_keys(cursor) k where k not in ('version','factory','occurrence','as_of','revision','schedule_revision','page_size','context','last_state','last_start','last_id'))))
 then raise exception 'shift_work_invalid' using errcode='22023';end if;
 ctx:=private.resolve_production_occurrence(factory,stamp);occ:=ctx->'occurrence';
 select coalesce(revision,0) into rev from private.lean_source_state where factory_id=factory;rev:=coalesce(rev,0);
 select coalesce(max(revision_no),0) into schedule_rev from private.production_shift_schedule_revisions where factory_id=factory;
 if cursor is not null then
  if cursor->>'factory' is distinct from factory::text or cursor->>'version' is distinct from '1' or cursor->>'page_size' is distinct from page_size::text
   or cursor->>'occurrence' is distinct from occ->>'occurrence_key' or cursor->>'revision' is distinct from rev::text or cursor->>'schedule_revision' is distinct from schedule_rev::text
   or coalesce(cursor->>'last_state','') not in ('0','1') or cursor->>'last_start' is null or cursor->>'last_id' is null
  then raise exception 'shift_work_stale' using errcode='40001';end if;
  evaluated:=(cursor->>'as_of')::timestamptz;
  if evaluated is null or not isfinite(evaluated) or evaluated>stamp or evaluated<(occ->>'starts_at')::timestamptz
  then raise exception 'shift_work_invalid' using errcode='22023';end if;
 else evaluated:=stamp;end if;
 can_edit:=private.has_permission(factory,'orders','edit');
 -- Preserve the old late-mode publication. Same-shift admission independently
 -- locks execution and rechecks the authoritative live occurrence/deadline.
 select coalesce((select enabled and schema_contract_version=3 from private.production_recording_v3_activation where factory_id=factory),false)
  and can_edit and coalesce((ctx->>'available')::boolean,false) into late_available;
 context_key:=encode(sha256(convert_to(jsonb_build_array(3,factory,auth.uid(),occ->>'occurrence_key',evaluated,rev,schedule_rev,page_size,can_edit,late_available)::text,'UTF8')),'hex');
 if cursor is not null and cursor->>'context' is distinct from context_key then raise exception 'shift_work_stale' using errcode='40001';end if;
 if (ctx->>'available')::boolean is not true then return ctx||jsonb_build_object('contract_version',3,'factory_id',factory,'server_as_of',stamp,'evaluation_as_of',evaluated,
  'rows','[]'::jsonb,'total',0,'page_size',page_size,'complete',true,'next_cursor',null,'can_edit',can_edit,'late_recording_available',false);end if;
 with candidates as materialized (
  select o,private.production_recording_eligibility(o,occ,evaluated) eligibility,
   case when o.status='active' then 0 else 1 end state_rank
  from public.production_orders o where o.factory_id=factory and o.line_id is not null and o.status in ('active','completed')
   and o.actual_start<=evaluated and o.actual_start<(occ->>'ends_at')::timestamptz
   and (o.actual_finish is null or o.actual_finish>(occ->>'starts_at')::timestamptz)
 ),included as materialized(select * from candidates where (eligibility->>'included')::boolean),
 remaining as (select * from included where cursor is null or
  (state_rank,-extract(epoch from (o).actual_start),(o).id)>((cursor->>'last_state')::integer,-extract(epoch from (cursor->>'last_start')::timestamptz),(cursor->>'last_id')::uuid)),
 page as materialized(select * from remaining order by state_rank,(o).actual_start desc,(o).id limit page_size+1),
 selected as (select * from page order by state_rank,(o).actual_start desc,(o).id limit page_size)
 select (select count(*) from included),coalesce(jsonb_agg(
  jsonb_build_object('item_id',(s.o).id,'item_code',(s.o).code,'request_id',r.id,'request_code',r.code,
   'product_id',p.id,'product_name',p.name,'product_name_ar',p.name_ar,'unit',(s.o).unit,
   'line_id',l.id,'line_name',l.name,'line_name_ar',l.name_ar,'actual_start',coalesce((s.o).execution_started_at,(s.o).actual_start),'actual_finish',(s.o).actual_finish,'status',(s.o).status,
   'accepted_good',(s.o).accepted_good_quantity,'fulfillment_good',(s.o).fulfillment_good_quantity,'remaining_quantity',(s.o).accepted_remaining_quantity,
   'can_record',can_edit and ((s.eligibility->>'active_recording_eligible')::boolean or (s.eligibility->>'policy_late_eligible')::boolean),'recent_entry_scope',jsonb_build_object('item_id',(s.o).id,'line_id',l.id,'occurrence_key',occ->>'occurrence_key'))||s.eligibility||jsonb_build_object(
   'same_shift_recording_available',can_edit and (s.eligibility->>'policy_late_eligible')::boolean,
   'late_recording_available',late_available and (s.eligibility->>'policy_late_eligible')::boolean,
   'blocked_reason',case when (s.eligibility->>'policy_late_eligible')::boolean then null else s.eligibility->>'blocked_reason' end)
  order by s.state_rank,(s.o).actual_start desc,(s.o).id),'[]'),
  case when (select count(*) from page)>page_size then (select jsonb_build_object('version',1,'factory',factory,'occurrence',occ->>'occurrence_key','as_of',evaluated,
   'revision',rev,'schedule_revision',schedule_rev,'page_size',page_size,'context',context_key,'last_state',state_rank,'last_start',(o).actual_start,'last_id',(o).id)
   from selected order by state_rank desc,(o).actual_start,(o).id desc limit 1) end
 into total,rows,next_page from selected s
 join public.products p on p.factory_id=factory and p.id=(s.o).product_id
 join public.production_lines l on l.factory_id=factory and l.id=(s.o).line_id
 left join public.production_requests r on r.factory_id=factory and r.id=(s.o).request_id;
 return ctx||jsonb_build_object('contract_version',3,'factory_id',factory,'server_as_of',stamp,'evaluation_as_of',evaluated,'expires_at',occ->'ends_at',
  'dataset_revision',rev,'schedule_revision',schedule_rev,'context',context_key,'can_edit',can_edit,
  'rows',rows,'total',total,'page_size',page_size,'next_cursor',next_page,'complete',next_page is null,'late_recording_available',late_available);
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then raise exception 'shift_work_invalid' using errcode='22023';
end$function$
;

CREATE OR REPLACE FUNCTION public.production_recording_progress(factory uuid, item uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare j public.production_orders;modern boolean;begin
 perform private.require_permission(factory,'orders','view');select * into j from public.production_orders where factory_id=factory and id=item;
 if not found then raise exception 'not_found' using errcode='P0002';end if;
 modern:=exists(select 1 from private.manufactured_outputs where factory_id=factory and item_id=item) or exists(select 1 from private.manufactured_completion_work where factory_id=factory and item_id=item);
 return jsonb_build_object('id',j.id,'factory_id',factory,'code',j.code,'unit',j.unit,'status',j.status,'actual_start',coalesce(j.execution_started_at,j.actual_start),'actual_finish',j.actual_finish,'request_id',j.request_id,
 'target_quantity',j.target_quantity::text,'good_quantity',j.good_quantity::text,'quality_measurement_delta',j.quality_measurement_delta::text,'quality_output_good_delta',j.quality_output_good_delta::text,
 'produced_good',case when modern then j.fulfillment_good_quantity::text else j.good_quantity::text end,'ordinary_remaining',(case when j.status='completed' then least(private.ordinary_output_remaining(factory,item),j.accepted_remaining_quantity) else private.ordinary_output_remaining(factory,item) end)::text,'remaining_demand',j.accepted_remaining_quantity::text,
 'makeup_committed',exists(select 1 from private.production_compensation c join private.manufactured_outputs h on h.factory_id=c.factory_id and h.id=c.output_id where c.factory_id=factory and h.item_id=item and c.source_kind='MEASUREMENT'),
 'replacement_original_item_id',j.replacement_original_item_id,'quality_origin_rejection_id',j.quality_origin_rejection_id,
 'request_type',(select request_type from public.production_requests where factory_id=factory and id=j.request_id));
end$function$
;

CREATE OR REPLACE FUNCTION private.maintenance_production_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare finish_time timestamptz;minutes_required integer;m public.work_centers;begin
 perform private.maintenance_planning_lock(new.factory_id);
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

-- Current-run identity is additional metadata; original actual_start is immutable.
drop trigger guard_product_execution_update on public.production_orders;
create trigger guard_product_execution_update before update of status,actual_start,actual_finish,execution_started_at,execution_interrupted_at
 on public.production_orders for each row execute function private.guard_product_execution();

create function private.execution_fingerprint(f uuid,i uuid)returns text language sql stable security definer set search_path=''as $$
 select encode(sha256(convert_to(to_jsonb(o)::text,'UTF8')),'hex')from public.production_orders o where factory_id=f and id=i
$$;
create function public.production_execution_context(factory uuid,item uuid)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare o public.production_orders;h jsonb;begin
 perform private.require_permission(factory,'orders','view');
 select *into o from public.production_orders where factory_id=factory and id=item;
 if not found then raise exception 'not_found';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'line_id',r.line_id,'started_at',r.started_at,'ended_at',r.ended_at,
 'state',r.state,'reason',r.reason,'start_actor',r.start_actor,'end_actor',r.end_actor,'planned',r.planned,
 'effective_start',r.effective_start,'effective_finish',r.effective_finish,'recorded_before',r.recorded_before,'recorded_after',r.recorded_after)
 order by r.started_at desc),'[]')into h from private.production_execution_runs r where r.factory_id=factory and r.item_id=item;
 return jsonb_build_object('factory',factory,'item',item,'order',to_jsonb(o),'fingerprint',private.execution_fingerprint(factory,item),'history',h,
 'remaining',private.ordinary_output_remaining(factory,item)::text);
end$$;
create function public.production_execution_remaining(factory uuid)returns jsonb language plpgsql stable security definer set search_path=''as $$
begin perform private.require_permission(factory,'orders','view');return(select coalesce(jsonb_object_agg(o.id,private.ordinary_output_remaining(factory,o.id)::text),'{}')
from public.production_orders o where factory_id=factory and execution_interrupted_at is not null);end$$;
revoke all on function public.production_execution_remaining(uuid)from public,anon,service_role;
grant execute on function public.production_execution_remaining(uuid)to authenticated;

create function private.execution_run_history_guard()returns trigger language plpgsql set search_path=''as $$
begin
 if tg_op='DELETE'or old.ended_at is not null then raise exception 'execution_history_immutable';end if;
 if row(new.factory_id,new.item_id,new.line_id,new.started_at,new.planned,new.effective_start,new.effective_finish,new.start_actor,new.dispatch_override,new.request_id,new.recorded_before)
 is distinct from row(old.factory_id,old.item_id,old.line_id,old.started_at,old.planned,old.effective_start,old.effective_finish,old.start_actor,old.dispatch_override,old.request_id,old.recorded_before)
 then raise exception 'execution_history_immutable';end if;
 return new;
end$$;
create trigger production_execution_run_history before update or delete on private.production_execution_runs
for each row execute function private.execution_run_history_guard();

create function private.project_execution_run()returns trigger language plpgsql security definer set search_path=''as $$
declare c private.production_execution_commands;r private.production_execution_runs;stamp timestamptz;begin
 if new.status is not distinct from old.status then return new;end if;
 select *into c from private.production_execution_commands where factory_id=new.factory_id and item_id=new.id and actor=auth.uid()
 and backend=pg_backend_pid()and transaction_id=txid_current()and result is null order by started_at desc limit 1;
 if new.status='active'and old.status<>'active'then
  stamp:=coalesce(new.execution_started_at,new.actual_start);
  update private.production_execution_runs set state='ACTIVE'where factory_id=new.factory_id and item_id=new.id and state='ARMED'and started_at=stamp;
  if not found then
   insert into private.production_execution_runs(factory_id,item_id,line_id,started_at,state,planned,effective_start,effective_finish,start_actor,recorded_before)
   values(new.factory_id,new.id,new.line_id,stamp,'ACTIVE',jsonb_build_object('line',new.line_id,'start',new.start_time,'finish',new.expected_finish),
   new.start_time,new.expected_finish,auth.uid(),to_jsonb(old));
  end if;
 elsif old.status='active'and new.status in('planned','completed')then
  stamp:=case when new.status='planned'then new.execution_interrupted_at else new.actual_finish end;
  update private.production_execution_runs set state=case when new.status='planned'then 'INTERRUPTED'else 'FINISHED'end,
   ended_at=stamp,end_actor=auth.uid(),reason=c.reason,recorded_after=to_jsonb(new)
   where factory_id=new.factory_id and item_id=new.id and ended_at is null;
  if not found then
   -- Existing active work has no provable original actor/count snapshot. Keep that unknown.
   insert into private.production_execution_runs(factory_id,item_id,line_id,started_at,ended_at,state,planned,effective_start,effective_finish,
    start_actor,end_actor,reason,recorded_before,recorded_after)
   values(old.factory_id,old.id,old.line_id,coalesce(old.execution_started_at,old.actual_start),stamp,
    case when new.status='planned'then 'INTERRUPTED'else 'FINISHED'end,
    jsonb_build_object('line',old.line_id,'start',old.start_time,'finish',old.expected_finish),old.start_time,old.expected_finish,
    null,auth.uid(),c.reason,jsonb_build_object('unknown','PRE_F34_START_SNAPSHOT'),to_jsonb(new));
  end if;
 end if;return new;
end$$;
-- Before stock schedule projection; an armed dispatch window remains available to BEFORE guards.
create trigger execution_run_history after update of status on public.production_orders for each row execute function private.project_execution_run();

create function public.production_execution_action(factory uuid,item uuid,operation text,reason text,fingerprint text,request_id uuid,output_confirmed boolean default false)
returns jsonb language plpgsql security definer set search_path=''as $$
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
  perform set_config('app.plan_reason','priority_change',true);perform set_config('app.plan_note',btrim(reason),true);
  update public.production_orders set status='planned',execution_interrupted_at=stamp,line_id=null,start_time=null,expected_finish=null
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
end$$;

revoke all on function private.execution_fingerprint(uuid,uuid),private.execution_run_history_guard(),private.project_execution_run()from public,anon,authenticated,service_role;
revoke all on function public.production_execution_context(uuid,uuid),public.production_execution_action(uuid,uuid,text,text,text,uuid,boolean)from public,anon,service_role;
grant execute on function public.production_execution_context(uuid,uuid),public.production_execution_action(uuid,uuid,text,text,text,uuid,boolean)to authenticated;


CREATE OR REPLACE FUNCTION private.finish_product_item_before_interruption(factory uuid, item uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare target public.production_orders%rowtype;
begin
  perform private.require_permission(factory,'orders','edit');
 if current_setting('transaction_isolation')not in('read committed','read uncommitted')then raise exception 'execution_readiness_stale'using errcode='40001';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));
  -- Lock before item/center rows, shared with transfer and layout operations.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(factory::text||':structure',0));
  select * into target from public.production_orders
    where factory_id=factory and id=item for update;
  if not found then raise exception 'not_found'; end if;
  if target.status <> 'active' or target.actual_start is null
    or target.actual_finish is not null then
    raise exception 'execution_not_running';
  end if;
  update public.production_orders set status='completed',
    actual_finish=pg_catalog.clock_timestamp()
    where factory_id=factory and id=item;
  return item;
end;
$function$
;

create or replace function public.finish_product_item(factory uuid,item uuid)returns uuid language plpgsql security definer set search_path=''as $$
begin perform private.require_permission(factory,'orders','edit');
perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.maintenance_planning_lock(factory);
if exists(select 1 from public.production_orders where factory_id=factory and id=item and execution_started_at is not null)then raise exception 'execution_context_changed'using errcode='40001';end if;
return private.finish_product_item_before_interruption(factory,item);end$$;
create function public.finish_product_item(factory uuid,item uuid,expected_actual_start timestamptz)returns uuid language plpgsql security definer set search_path=''as $$
declare o public.production_orders;begin perform private.require_permission(factory,'orders','edit');
perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.maintenance_planning_lock(factory);
select *into o from public.production_orders where factory_id=factory and id=item for update;
if expected_actual_start is null or expected_actual_start is distinct from coalesce(o.execution_started_at,o.actual_start)then raise exception 'execution_context_changed'using errcode='40001';end if;
return private.finish_product_item_before_interruption(factory,item);end$$;
revoke all on function private.finish_product_item_before_interruption(uuid,uuid)from public,anon,authenticated,service_role;
revoke all on function public.finish_product_item(uuid,uuid,timestamptz)from public,anon,service_role;
grant execute on function public.finish_product_item(uuid,uuid,timestamptz)to authenticated;