-- F20: actual execution destination is separate from the immutable approved plan.
-- Nullable, no backfill, no historical inventory or execution rewrite.
alter table public.production_orders add column actual_line_id uuid;
alter table public.production_orders add constraint production_actual_line_factory foreign key(factory_id,actual_line_id) references public.production_lines(factory_id,id);
drop index public.production_orders_one_active_per_line;
create unique index production_orders_one_active_per_line on public.production_orders(factory_id,(coalesce(actual_line_id,line_id))) where status='active'and coalesce(actual_line_id,line_id)is not null;

create function private.guard_execution_destination()returns trigger language plpgsql security definer set search_path=''as $$begin
 if tg_op='INSERT'then if new.actual_line_id is not null then raise exception 'execution_use_command';end if;return new;end if;
 if private.execution_command_allowed(old.factory_id,old.id,array['TRANSFER_LINE'])then
  if row(new.line_id,new.start_time,new.expected_finish)is distinct from row(old.line_id,old.start_time,old.expected_finish)then raise exception 'execution_plan_immutable';end if;
 elsif row(new.line_id,new.start_time,new.expected_finish)is distinct from row(old.line_id,old.start_time,old.expected_finish)and old.status='planned'then
  -- An explicit authorized Planning revision may choose the next execution route.
  -- Existing Planning guards still validate that change; old runs retain their routes.
  new.actual_line_id:=null;
 elsif new.actual_line_id is distinct from old.actual_line_id then raise exception 'execution_use_command';end if;
 return new;end$$;
create trigger execution_actual_destination before insert or update on public.production_orders for each row execute function private.guard_execution_destination();
revoke all on function private.guard_execution_destination()from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.execution_center_order(f uuid, w uuid, l uuid, independent_order uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    (select t.order_id from public.production_transfers t
      where t.factory_id=f and t.alternative_id=w and t.ended_at is null),
    case when l is not null then
      (select o.id from public.production_orders o
        where o.factory_id=f and coalesce(o.actual_line_id,o.line_id)=l and o.status='active')
    else
      (select o.id from public.production_orders o
        where o.factory_id=f and o.id=independent_order and o.status='active')
    end
  );
$function$
;

CREATE OR REPLACE FUNCTION private.project_center_execution()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
 new.order_id:=private.execution_center_order(new.factory_id,new.id,new.line_id,new.order_id);
 if new.status='running'and not private.machine_has_active_work(new.factory_id,new.id,new.line_id,new.order_id)then
 raise exception 'execution_no_active_work'using errcode='22023';end if;
 if new.status='running'and exists(select 1 from public.production_lines l where l.factory_id=new.factory_id
 and l.id=coalesce((select coalesce(o.actual_line_id,o.line_id) from public.production_orders o where o.factory_id=new.factory_id and o.id=new.order_id),new.line_id)and l.paused_at is not null)then
 raise exception 'line_paused'using errcode='22023';end if;
 return new;end$function$
;

CREATE OR REPLACE FUNCTION private.project_item_execution()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.work_centers;assigned uuid;next_status text;begin
 if old.status is not distinct from new.status then return new;end if;
 perform pg_advisory_xact_lock(hashtextextended(new.factory_id::text||':structure',0));
 for c in select *from public.work_centers where factory_id=new.factory_id
 and(line_id=coalesce(new.actual_line_id,new.line_id) or order_id=new.id)order by id for update loop
 assigned:=private.execution_center_order(c.factory_id,c.id,c.line_id,c.order_id);
 next_status:=c.status;
 if c.status='running'and not private.machine_has_active_work(c.factory_id,c.id,c.line_id,assigned)then next_status:='idle';
 elsif c.status='idle'and not c.archived and private.machine_has_active_work(c.factory_id,c.id,c.line_id,assigned)
 and not exists(select 1 from public.production_lines l where l.factory_id=c.factory_id and l.id=c.line_id and l.paused_at is not null
 and not exists(select 1 from public.production_transfers t where t.factory_id=c.factory_id and t.alternative_id=c.id and t.ended_at is null))
 and not exists(select 1 from public.downtime_events d where d.factory_id=c.factory_id and d.work_center_id=c.id and d.ended_at is null)
 then next_status:='running';end if;
 if(c.order_id,c.status)is distinct from(assigned,next_status)then
 update public.work_centers set order_id=assigned,status=next_status,updated_at=clock_timestamp(),
 last_restart_time=case when next_status='running'and c.status<>'running'then clock_timestamp()else last_restart_time end where id=c.id;
 if c.status<>next_status then insert into public.status_events(factory_id,work_center_id,old_status,new_status,notes,created_by)
 values(c.factory_id,c.id,c.status,next_status,'Execution status synchronization',auth.uid());end if;
 end if;end loop;return new;end$function$
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
      where l.factory_id=factory and l.id=coalesce(target.actual_line_id,target.line_id) and not l.archived) then
    raise exception 'execution_plan_required';
  end if;

  -- Serialize competing starts on this line before reading its queue.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(coalesce(target.actual_line_id,target.line_id)::text,0));
  if exists(select 1 from public.production_orders other
    where other.factory_id=factory and coalesce(other.actual_line_id,other.line_id)=coalesce(target.actual_line_id,target.line_id)
      and other.status='active') then
    raise exception 'execution_line_busy';
  end if;
  select other.id into first_item from public.production_orders other
    where other.factory_id=factory and coalesce(other.actual_line_id,other.line_id)=coalesce(target.actual_line_id,target.line_id)
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
$function$
;

CREATE OR REPLACE FUNCTION private.execution_machine_start_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare check_result jsonb;begin
 if new.status='active'and old.status<>'active'then
 perform pg_advisory_xact_lock(hashtextextended(new.factory_id::text||':structure',0));
 check_result:=private.execution_machine_readiness(new.factory_id,new.id,coalesce(new.actual_line_id,new.line_id),new.product_id);
 if not(check_result->>'ready')::boolean then raise exception 'execution_machine_stopped'using errcode='22023';end if;
 -- No active work existed on this line; a stale idle pause must not survive a new explicit Start.
 update public.production_lines set paused_at=null,pause_reason=null where factory_id=new.factory_id and id=coalesce(new.actual_line_id,new.line_id) and paused_at is not null;
 delete from private.line_pause_auto_idled where factory_id=new.factory_id and line_id=coalesce(new.actual_line_id,new.line_id);
 end if;return new;end$function$
;

CREATE OR REPLACE FUNCTION private.maintenance_execution_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare result jsonb;begin
 if new.status<>'active' or old.status='active' then return new;end if;
 perform private.require_permission(new.factory_id,'orders','edit');
 if current_setting('transaction_isolation') not in ('read committed','read uncommitted') then
 raise exception 'execution_readiness_stale' using errcode='40001';end if;
 perform private.maintenance_planning_lock(new.factory_id);
 perform private.require_permission(new.factory_id,'orders','edit');
 result:=private.maintenance_execution_readiness(new.factory_id,new.id,coalesce(new.actual_line_id,new.line_id),new.product_id);
 if not (result->>'ready')::boolean then raise exception 'execution_physical_not_ready' using errcode='P0001',detail=result::text;end if;
 return new;
end$function$
;

CREATE OR REPLACE FUNCTION private.maintenance_center_execution_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.production_orders;begin
 if new.order_id is not null and (tg_op='INSERT' or old.order_id is distinct from new.order_id or (old.status<>'running' and new.status='running')) then
 select * into o from public.production_orders where factory_id=new.factory_id and id=new.order_id and status='active';
 if found then perform private.maintenance_assert_capacity(new.factory_id,coalesce(o.actual_line_id,o.line_id),o.product_id,new.id,clock_timestamp(),
 case when new.line_id is null then 'infinity'::timestamptz else clock_timestamp()+interval '1 second' end,null,o.id,false);end if;
 end if;return new;
end$function$
;

CREATE OR REPLACE FUNCTION private.maintenance_transfer_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.production_orders;begin
 if new.ended_at is not null then return new;end if;
 perform private.maintenance_planning_lock(new.factory_id);
 select * into o from public.production_orders where factory_id=new.factory_id and id=new.order_id;
 perform private.maintenance_assert_capacity(new.factory_id,coalesce(o.actual_line_id,o.line_id),o.product_id,new.alternative_id,clock_timestamp(),'infinity',null,o.id,false);
 return new;
end$function$
;

CREATE OR REPLACE FUNCTION private.set_line_pause(f uuid, l uuid, paused boolean, reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare idled_ids uuid[]; restored_ids uuid[];
begin
 perform private.require_permission(f,'centers','edit');
 if current_setting('transaction_isolation')not in('read committed','read uncommitted')then raise exception 'execution_readiness_stale'using errcode='40001';end if;
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));perform private.maintenance_planning_lock(f);
 if not exists(select 1 from public.production_orders where factory_id=f and coalesce(actual_line_id,line_id)=l and status='active')then raise exception 'execution_line_idle'using errcode='22023';end if;
 if paused is null or (paused and reason not in
   ('borrow_machine','planned_stop','cleaning','changeover','no_production','other')) then
  raise exception 'invalid_pause_reason';
 end if;
 perform 1 from public.production_lines
 where id=l and factory_id=f and not archived for update;
 if not found then raise exception 'not_found'; end if;

 if paused then
  update public.production_lines
  set paused_at=coalesce(paused_at,now()),pause_reason=reason
  where id=l;

  -- An already borrowed machine belongs to its open transfer, not this line's
  -- physical pause. All other running home machines become available idle.
  with idled as (
   update public.work_centers c
   set status='idle',updated_at=now()
   where c.factory_id=f and c.line_id=l and not c.archived and c.status='running'
     and not exists (
      select 1 from public.production_transfers t
      where t.factory_id=f and t.alternative_id=c.id and t.ended_at is null
   )
   returning c.id
  )
  select coalesce(array_agg(id),'{}'::uuid[]) into idled_ids from idled;

  -- Run this after the UPDATE's status triggers, which clear old markers.
  insert into private.line_pause_auto_idled(factory_id,line_id,work_center_id)
  select f,l,id from unnest(idled_ids) id;
  insert into public.status_events(factory_id,work_center_id,old_status,new_status,created_by)
  select f,id,'running','idle',auth.uid() from unnest(idled_ids) id;
 else
  update public.production_lines
  set paused_at=null,pause_reason=null
  where id=l;

  -- Lock centers before reading their markers. A concurrent manual status
  -- change either finishes first and removes its marker, or follows Resume.
  perform 1 from public.work_centers c
  where c.factory_id=f and c.line_id=l
    and exists (
     select 1 from private.line_pause_auto_idled m
     where m.factory_id=f and m.line_id=l and m.work_center_id=c.id
    )
  order by c.id for update;

  with restored as (
   update public.work_centers c
   set status='running',updated_at=now(),last_restart_time=now()
   where c.factory_id=f and c.line_id=l and not c.archived and c.status='idle'
     and exists (
      select 1 from private.line_pause_auto_idled m
      where m.factory_id=f and m.line_id=l and m.work_center_id=c.id
     )
     and not exists (
      select 1 from public.production_transfers t
      where t.factory_id=f and t.alternative_id=c.id and t.ended_at is null
     )
   returning c.id
  )
  select coalesce(array_agg(id),'{}'::uuid[]) into restored_ids from restored;
  insert into public.status_events(factory_id,work_center_id,old_status,new_status,created_by)
  select f,id,'idle','running',auth.uid() from unnest(restored_ids) id;

  -- A pause is finished even if a machine was borrowed or manually changed.
  delete from private.line_pause_auto_idled where factory_id=f and line_id=l;
 end if;
end$function$
;

CREATE OR REPLACE FUNCTION private.production_recording_units(f uuid)
 RETURNS TABLE(unit_kind text, unit_id uuid, item_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select 'line',l.id,o.id from public.production_lines l
 join public.production_orders o on o.factory_id=l.factory_id and coalesce(o.actual_line_id,o.line_id)=l.id
 where l.factory_id=f and not l.archived and o.status='active' and o.actual_start is not null and o.actual_finish is null and o.unit in ('meter','piece','kg')
 union all
 select 'machine',c.id,o.id from public.work_centers c
 join public.production_orders o on o.factory_id=c.factory_id and
 o.id=private.execution_center_order(c.factory_id,c.id,c.line_id,c.order_id)
 where c.factory_id=f and not c.archived and c.line_id is null and c.dependency_mode='independent'
 and o.status='active' and o.actual_start is not null and o.actual_finish is null
 and not exists(select 1 from public.production_transfers t where t.factory_id=f and t.ended_at is null
   and c.id in(t.original_id,t.alternative_id))
 and exists(select 1 from public.work_center_capabilities cap where cap.factory_id=f and cap.work_center_id=c.id
   and cap.product_id=o.product_id and cap.rate_unit=o.unit and cap.rate>0);
$function$
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
 or p->>'unit_kind' is distinct from 'line' or (p->>'production_unit')::uuid is distinct from coalesce(job.actual_line_id,job.line_id)
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
end$function$
;

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
 k:=case when job.actual_start is not null and job.line_id is not null then encode(sha256(convert_to(jsonb_build_array(1,job.factory_id,job.id,coalesce(job.actual_line_id,job.line_id),to_char(job.actual_start,'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))::text,'UTF8')),'hex') end;
 -- Bind every new recording, including zero-Good Scrap/unfinished declarations.
 -- Item/factory locks serialize admission; exact UUID replay precedes this check.
 select count(*) into evidence_count from public.production_entries where factory_id=job.factory_id and order_id=job.id;
 live:=false;
 if reason is null and job.status='active' then
  live:=exists(select 1 from private.production_recording_units(job.factory_id) u where u.unit_kind='line' and u.unit_id=coalesce(job.actual_line_id,job.line_id) and u.item_id=job.id);
 end if;
 return jsonb_build_object('included',reason is null,'preview_selectable',reason is null,'execution_key',k,
  'policy_late_eligible',reason is null and job.status='completed','active_recording_eligible',coalesce(live,false),
  'late_recording_available',false,'blocked_reason',coalesce(reason,case when job.status='completed' then 'PHASE1_READ_ONLY' when not live then 'ACTIVE_UNIT_UNAVAILABLE' end),
  'resource_evidence',jsonb_build_object('line','PROTECTED_PLAN_EXECUTION','machines','UNKNOWN'),
  'context_hash',encode(sha256(convert_to(jsonb_build_array(1,job.factory_id,job.id,job.product_id,coalesce(job.actual_line_id,job.line_id),job.actual_start,job.actual_finish,job.status,job.unit,job.target_quantity,job.accepted_good_quantity,job.fulfillment_good_quantity,occurrence->>'occurrence_key',live,evidence_count, (select coalesce(sum(quantity),0) from private.production_compensation where factory_id=job.factory_id and item_id=job.id and mode='ACTIVE'),private.compensation_recorded(job.factory_id,job.id),(select coalesce(sum(private.compensation_remaining(job.factory_id,id)),0) from private.production_compensation where factory_id=job.factory_id and item_id=job.id and mode='ACTIVE'))::text,'UTF8')),'hex'));
end$function$
;

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
 join public.production_lines l on l.factory_id=factory and l.id=coalesce((s.o).actual_line_id,(s.o).line_id)
 left join public.production_requests r on r.factory_id=factory and r.id=(s.o).request_id;
 return ctx||jsonb_build_object('contract_version',3,'factory_id',factory,'server_as_of',stamp,'evaluation_as_of',evaluated,'expires_at',occ->'ends_at',
  'dataset_revision',rev,'schedule_revision',schedule_rev,'context',context_key,'can_edit',can_edit,
  'rows',rows,'total',total,'page_size',page_size,'next_cursor',next_page,'complete',next_page is null,'late_recording_available',late_available);
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then raise exception 'shift_work_invalid' using errcode='22023';
end$function$
;

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
 o.line_id:=coalesce(o.actual_line_id,o.line_id);
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
 and not exists(select 1 from public.production_orders x where x.factory_id=factory and coalesce(x.actual_line_id,x.line_id)=o.line_id and x.status='active')
 and o.id=(select x.id from public.production_orders x where x.factory_id=factory and coalesce(x.actual_line_id,x.line_id)=o.line_id and x.status='planned'
 and x.actual_start is null and x.actual_finish is null and x.start_time is not null and x.expected_finish>x.start_time order by x.start_time,x.id limit 1),false));
end$function$
;

CREATE OR REPLACE FUNCTION private.maintenance_occupancy(f uuid, l uuid, p uuid, w uuid, skip_schedule uuid, skip_item uuid, with_production boolean, evaluated timestamp with time zone, range_start timestamp with time zone DEFAULT '-infinity'::timestamp with time zone, range_end timestamp with time zone DEFAULT 'infinity'::timestamp with time zone, record_limit integer DEFAULT NULL::integer)
 RETURNS TABLE(kind text, id uuid, starts timestamp with time zone, ends timestamp with time zone, state text, unknown boolean, sort_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 with scoped as (
 select 'MAINTENANCE'::text kind,s.id,least(s.planned_start,coalesce(s.hold_started_at,s.planned_start),coalesce((select min(d.started_at) from public.maintenance_stop_associations a join public.downtime_events d on d.factory_id=a.factory_id and d.id=a.event_id where a.factory_id=f and a.schedule_id=s.id and a.operation='LINK' and d.ended_at is null and not exists(select 1 from public.maintenance_stop_associations n where n.factory_id=f and n.event_id=a.event_id and n.revision>a.revision)),s.planned_start)) starts,
 case when private.maintenance_active_stop(f,s.id) or s.hold_started_at is not null or s.state='INVALIDATED' or s.planned_end<=evaluated then 'infinity'::timestamptz else s.planned_end end ends,
 s.state,false unknown,s.planned_start sort_at from public.maintenance_schedules s
 where s.factory_id=f and s.id is distinct from skip_schedule and s.state in ('CONFIRMED','INVALIDATED')
 and exists(select 1 from public.maintenance_schedule_resources r left join public.work_centers m on m.factory_id=r.factory_id and m.id=r.machine_id
 where r.factory_id=f and r.schedule_id=s.id and
 ((l is not null and (r.line_id=l or m.line_id=l)) or (w is not null and r.machine_id=w)
 or (p is not null and r.machine_id in(select rs.work_center_id from public.production_routing_steps rs where rs.factory_id=f and rs.product_id=p and rs.kind='work_center'))
 or (l is not null and r.machine_id in(select t.alternative_id from public.production_transfers t join public.production_orders o on o.factory_id=t.factory_id and o.id=t.order_id where t.factory_id=f and t.ended_at is null and (case when o.status='active'then coalesce(o.actual_line_id,o.line_id)else o.line_id end)=l))))
 union all
 select 'PRODUCTION',o.id,
 case when o.status='active' or o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time then '-infinity'::timestamptz else o.start_time end,
 case when o.status='active' or o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time then 'infinity'::timestamptz else o.expected_finish end,
 o.status,(o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time),o.start_time
 from public.production_orders o where with_production and o.factory_id=f and o.id is distinct from skip_item and o.status in ('planned','active')
 and ((l is not null and (case when o.status='active'then coalesce(o.actual_line_id,o.line_id)else o.line_id end)=l) or (w is not null and
 (o.id in(select c.order_id from public.work_centers c where c.factory_id=f and c.id=w)
 or o.product_id in(select rs.product_id from public.production_routing_steps rs where rs.factory_id=f and rs.work_center_id=w and rs.kind='work_center')))))
 select * from scoped where starts<range_end and ends>range_start order by kind,id limit record_limit;
$function$
;

CREATE OR REPLACE FUNCTION public.production_stock_reservation_details(factory uuid, material uuid, page integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 left join public.products p on p.factory_id=o.factory_id and p.id=o.product_id left join public.production_lines l on l.factory_id=o.factory_id and l.id=coalesce(o.actual_line_id,o.line_id)
 where r.factory_id=factory and r.material_id=material)
 select coalesce((select jsonb_agg(x order by updated_at desc,item_id,occurrence_key)from rows where reserved>0 or x->>'status'='active'),'[]'),
 coalesce((select jsonb_agg(x order by updated_at desc,item_id,occurrence_key)from(select *from rows where reserved=0 and x->>'status'<>'active'order by updated_at desc,item_id,occurrence_key limit 30 offset(page-1)*30)h),'[]'),
 (select count(*)from rows where reserved=0 and x->>'status'<>'active')into active_rows,history,history_count;
 return jsonb_build_object('factory',factory,'material',material,'stock',stock,'active',active_rows,'history',history,'page',page,
 'history_total',history_count,'evaluated_at',clock_timestamp());
end$function$
;

CREATE OR REPLACE FUNCTION private.material_requirement_inputs_for_line(f uuid, i uuid, destination uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$declare o public.production_orders;p public.products;r private.production_input_routes;b public.bom_versions;compound uuid;mass numeric;v jsonb;matches integer;begin
 select *into o from public.production_orders where factory_id=f and id=i;select *into p from public.products where factory_id=f and id=o.product_id;
 if o.id is null then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 -- Existing completion/rework owns its source-lot requirement; never explode a recipe again.
 if exists(select 1 from private.manufactured_completion_work where factory_id=f and item_id=i)or o.quality_origin_rejection_id is not null then return jsonb_build_object('existing_source_work',true,'inputs','[]'::jsonb);end if;
 select count(*)into matches from private.production_input_routes x join public.production_routing_steps s on s.id=x.routing_step_id join public.work_centers w on w.id=s.work_center_id where x.factory_id=f and x.product_id=p.id and w.line_id=destination;
 if matches>1 then return jsonb_build_object('warning','material_route_ambiguous');end if;
 if matches=1 then select x.*into r from private.production_input_routes x join public.production_routing_steps s on s.id=x.routing_step_id join public.work_centers w on w.id=s.work_center_id where x.factory_id=f and x.product_id=p.id and w.line_id=destination;else select *into r from private.production_input_routes where factory_id=f and product_id=p.id and scope='00000000-0000-0000-0000-000000000000';end if;
 if r.product_id is null then return jsonb_build_object('warning','material_route_missing');end if;
 if o.unit is distinct from p.stock_unit then return jsonb_build_object('warning','material_unit_missing');end if;
 mass:=case when r.mode='COMPOUND_MANUFACTURE'and p.stock_unit='kg'then o.target_quantity else o.target_quantity*p.unit_weight_kg end;
 if mass is null or mass<=0 or mass::text in('NaN','Infinity','-Infinity')then return jsonb_build_object('warning','material_weight_missing');end if;
 compound:=case when r.mode='COMPOUND_MANUFACTURE'then p.id else p.formula_product_id end;
 if r.mode='COMPOUND_STOCK'then
 if not exists(select 1 from public.products where factory_id=f and id=compound and product_kind='MANUFACTURED_INTERMEDIATE'and stock_unit='kg')then return jsonb_build_object('warning','material_configuration_invalid');end if;
 v:=jsonb_build_array(jsonb_build_object('kind','product','id',compound,'unit','kg','quantity',trim_scale(mass)::text));
 else
 select *into b from public.bom_versions where factory_id=f and product_id=compound and output_unit='kg'order by version desc,created_at desc,id desc limit 1;
 if b.id is null or not exists(select 1 from public.bom_items where factory_id=f and bom_id=b.id)then return jsonb_build_object('warning','material_recipe_missing');end if;
 if exists(select 1 from public.bom_items x join public.materials m on m.id=x.material_id where x.factory_id=f and x.bom_id=b.id and(x.unit<>m.unit or m.inventory_kind<>'RAW_MATERIAL'))then return jsonb_build_object('warning','material_unit_missing');end if;
 select jsonb_agg(jsonb_build_object('kind','material','id',material_id,'unit',unit,'quantity',trim_scale(quantity)::text)order by material_id)into v from(select x.material_id,x.unit,sum(mass*x.quantity/b.batch_quantity*(1+x.waste_allowance))quantity from public.bom_items x where x.factory_id=f and x.bom_id=b.id group by x.material_id,x.unit)q;
 end if;
 return jsonb_build_object('mode',r.mode,'route',r.scope,'route_revision',r.revision,'recipe',b.id,'recipe_version',b.version,'inputs',v);
end$function$
;
create or replace function private.material_requirement_inputs(f uuid,i uuid)returns jsonb language sql stable set search_path=''as $$select private.material_requirement_inputs_for_line(f,i,coalesce(actual_line_id,line_id))from public.production_orders where factory_id=f and id=i$$;

CREATE OR REPLACE FUNCTION private.execution_dispatch_materials_for_line(f uuid, i uuid, destination uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.production_orders;stamp timestamptz:=statement_timestamp();occ jsonb;forecast jsonb;rate numeric;setup integer;finish_at timestamptz;row jsonb;free numeric;own numeric;others numeric;rows jsonb:='[]';ready boolean:=true;m public.materials;req jsonb;n integer;typed integer;fastest numeric;begin
 select *into o from public.production_orders where factory_id=f and id=i;
 req:=private.material_requirement_inputs_for_line(f,i,destination);
 if req->>'existing_source_work'='true'or req->>'mode'='COMPOUND_STOCK'then return private.material_start_readiness_before_stock(f,i);end if;
 occ:=private.resolve_production_occurrence(f,stamp);if occ->>'available'is distinct from 'true'then return jsonb_build_object('ready',false,'reason','recording_shift_unavailable','rows',rows);end if;
 select count(*),count(*)filter(where c.rate_unit=o.unit),min(c.rate),max(c.rate),max(c.setup_minutes)into n,typed,rate,fastest,setup from public.work_centers w join public.work_center_capabilities c on c.factory_id=w.factory_id and c.work_center_id=w.id and c.product_id=o.product_id where w.factory_id=f and w.line_id=destination and not w.archived;
 if n=0 or typed<>n or rate<=0 or rate<>fastest then return jsonb_build_object('ready',false,'reason','planning_missing_rate','rows',rows);end if;
 finish_at:=private.finish_after_working_minutes(f,stamp,greatest(ceil(private.ordinary_output_remaining(f,i)*60/rate)+coalesce(setup,0),1)::integer);
 forecast:=private.production_stock_forecast(f,i,stamp,occ||jsonb_build_object('dispatch_item',i,'dispatch_start',stamp,'dispatch_finish',finish_at,'dispatch_line',destination));
 if forecast->>'warning'is not null or coalesce((forecast->>'expected_output')::numeric,0)<=0 then return jsonb_build_object('ready',false,'reason',coalesce(forecast->>'warning','production_stock_schedule_required'),'rows',rows);end if;
 for row in select value from jsonb_array_elements(forecast->'inputs')loop
  select *into m from public.materials where factory_id=f and id=(row->>'id')::uuid;
  select coalesce(sum(r.reserved)filter(where r.item_id<>i),0),coalesce(sum(r.reserved)filter(where r.item_id=i),0)into others,own
   from private.production_stock_reservations r where r.factory_id=f and r.material_id=m.id and r.occurrence_key=occ#>>'{occurrence,occurrence_key}';
  free:=greatest(private.production_stock_quantity(f,m.id)-private.production_stock_return_pending(f,m.id)-others,0);
  if (row->>'quantity')::numeric>free then ready:=false;end if;
  rows:=rows||jsonb_build_array(jsonb_build_object('id',m.id,'name',m.name,'name_ar',m.name_ar,'unit',m.unit,'required',row->>'quantity','reserved',trim_scale(own)::text,'reserved_other',trim_scale(others)::text,'available_for_order',trim_scale(free)::text,'missing',trim_scale(greatest((row->>'quantity')::numeric-free,0))::text));
 end loop;return jsonb_build_object('ready',ready,'reason',case when not ready then 'production_stock_shortage'end,'rows',rows,'required_output',forecast->>'expected_output','occurrence',forecast->'occurrence');
end$function$
;
create or replace function private.execution_dispatch_materials(f uuid,i uuid)returns jsonb language sql stable security definer set search_path=''as $$select private.execution_dispatch_materials_for_line(f,i,coalesce(actual_line_id,line_id))from public.production_orders where factory_id=f and id=i$$;

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
 o.line_id:=coalesce((resolved->>'dispatch_line')::uuid,o.actual_line_id,o.line_id);
 if o.id is null or o.status not in('planned','active')or o.line_id is null or o.start_time is null or o.expected_finish is null then return jsonb_build_object('warning','production_stock_schedule_required');end if;
 if not private.production_stock_eligible(f,i)then return jsonb_build_object('warning','production_stock_legacy_review');end if;
 if o.execution_interrupted_at is not null and (resolved->>'dispatch_item')is distinct from i::text and not exists(select 1 from private.production_execution_runs r
  where r.factory_id=f and r.item_id=i and r.state='ARMED')then return jsonb_build_object('warning','execution_order_interrupted');end if;
 if resolved is null then resolved:=private.resolve_production_occurrence(f,stamp);end if;if resolved->>'available'is distinct from 'true'then return jsonb_build_object('warning','recording_shift_unavailable');end if;occ:=resolved->'occurrence';
 req:=private.material_requirement_inputs_for_line(f,i,o.line_id);if req->>'warning'is not null then return req;end if;
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
 update private.production_stock_reservations set reserved=0 where factory_id=f and reserved<>0 and not exists(select 1 from public.production_orders held where held.factory_id=f and held.id=production_stock_reservations.item_id and held.status='planned'and private.execution_command_allowed(f,held.id,array['TRANSFER_LINE'])and not exists(select 1 from private.production_execution_runs r where r.factory_id=f and r.item_id=held.id and r.state='ARMED'));
 for o in select id from public.production_orders where factory_id=f and status in('active','planned')and line_id is not null and start_time is not null
 and not(status='planned'and private.execution_command_allowed(f,id,array['TRANSFER_LINE'])and not exists(select 1 from private.production_execution_runs r where r.factory_id=f and r.item_id=production_orders.id and r.state='ARMED'))
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
 end$function$
;

CREATE OR REPLACE FUNCTION private.execution_start_blocker(f uuid, i uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.production_orders;remaining numeric;blocker text;ready jsonb;n integer;typed integer;slowest numeric;fastest numeric;begin
 select *into o from public.production_orders where factory_id=f and id=i;if not found then raise exception 'not_found';end if;
 remaining:=private.ordinary_output_remaining(f,i);
 o.line_id:=coalesce(o.actual_line_id,o.line_id);
 if o.status='planned'and remaining>0 then
  if o.line_id is null or not exists(select 1 from public.production_lines where factory_id=f and id=o.line_id and not archived)then blocker:='execution_plan_required';
  elsif exists(select 1 from private.production_material_policy where factory_id=f and stock_enabled)and not private.production_stock_eligible(f,i)then blocker:='production_stock_legacy_review';
  elsif private.output_work_held(f,i)then blocker:='planningQualityHold';
  elsif exists(select 1 from public.production_orders where factory_id=f and coalesce(actual_line_id,line_id)=o.line_id and status='active'and id<>i)then blocker:='f341ReleaseCurrentFirst';
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
end$function$
;

CREATE OR REPLACE FUNCTION private.execution_bypassed_order(f uuid, i uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select jsonb_build_object('id',q.id,'code',q.code)from public.production_orders q join public.production_orders selected on selected.factory_id=q.factory_id and coalesce(selected.actual_line_id,selected.line_id)=coalesce(q.actual_line_id,q.line_id) and selected.id=i
 where q.factory_id=f and selected.status='planned'and(q.start_time,q.id)<(selected.start_time,selected.id)and q.status='planned'and q.actual_finish is null and q.start_time is not null and q.expected_finish>q.start_time
 and private.execution_dispatch_eligible(f,q.id)order by q.start_time,q.id limit 1
$function$
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
  where w.factory_id=factory and w.line_id=coalesce(o.actual_line_id,o.line_id) and not w.archived;
  if n=0 or typed<>n or rate<=0 or rate<>fastest then raise exception 'planning_missing_rate';end if;
  duration:=ceil(remaining*60/rate)+coalesce(setup,0);
  finish_at:=private.finish_after_working_minutes(factory,stamp,greatest(duration,1));
  insert into private.production_execution_runs(factory_id,item_id,line_id,started_at,state,planned,effective_start,effective_finish,
   start_actor,reason,dispatch_override,request_id,recorded_before)
  values(factory,item,coalesce(o.actual_line_id,o.line_id),stamp,'ARMED',jsonb_build_object('line',o.line_id,'start',o.start_time,'finish',o.expected_finish),
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

CREATE OR REPLACE FUNCTION private.project_execution_run()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c private.production_execution_commands;r private.production_execution_runs;stamp timestamptz;begin
 if new.status is not distinct from old.status then return new;end if;
 select *into c from private.production_execution_commands where factory_id=new.factory_id and item_id=new.id and actor=auth.uid()
 and backend=pg_backend_pid()and transaction_id=txid_current()and result is null order by started_at desc limit 1;
 if new.status='active'and old.status<>'active'then
  stamp:=coalesce(new.execution_started_at,new.actual_start);
  update private.production_execution_runs set state='ACTIVE'where factory_id=new.factory_id and item_id=new.id and state='ARMED'and started_at=stamp;
  if not found then
   insert into private.production_execution_runs(factory_id,item_id,line_id,started_at,state,planned,effective_start,effective_finish,start_actor,recorded_before)
   values(new.factory_id,new.id,coalesce(new.actual_line_id,new.line_id),stamp,'ACTIVE',jsonb_build_object('line',new.line_id,'start',new.start_time,'finish',new.expected_finish),
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
   values(old.factory_id,old.id,coalesce(old.actual_line_id,old.line_id),coalesce(old.execution_started_at,old.actual_start),stamp,
    case when new.status='planned'then 'INTERRUPTED'else 'FINISHED'end,
    jsonb_build_object('line',old.line_id,'start',old.start_time,'finish',old.expected_finish),old.start_time,old.expected_finish,
    null,auth.uid(),c.reason,jsonb_build_object('unknown','PRE_F34_START_SNAPSHOT'),to_jsonb(new));
  end if;
 end if;return new;
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
 'remaining',private.ordinary_output_remaining(factory,item)::text,'reason_required',private.execution_reason_required(factory,item),'bypassed_order',private.execution_bypassed_order(factory,item),'line_transfers',(select coalesce(jsonb_agg(jsonb_build_object('request_id',c.request_id,'actor',c.actor,'reason',c.reason,'started_at',c.started_at,'source_line',c.before_state->'source_line','destination_line',c.before_state->'destination_line','source_machine',c.before_state->'source_machine','alternative_machine',c.before_state->'alternative_machine','source_downtime',c.before_state->'source_downtime','source_run',c.before_state->'source_run')order by c.started_at desc),'[]')from private.production_execution_commands c where c.factory_id=factory and c.item_id=item and c.operation='TRANSFER_LINE'and c.result->>'outcome'is distinct from 'REJECTED'));
end$function$
;

revoke all on function private.material_requirement_inputs_for_line(uuid,uuid,uuid),private.execution_dispatch_materials_for_line(uuid,uuid,uuid)from public,anon,authenticated,service_role;
-- Read-only destination evidence and one atomic protected execution transition.
create function private.line_transfer_readiness(f uuid,i uuid,w uuid,a uuid)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare o public.production_orders;src public.work_centers;dst public.work_centers;line public.production_lines;
 result jsonb;materials jsonb;req jsonb;physical jsonb;capacity jsonb;remaining numeric;rate numeric;fastest numeric;n integer;typed integer;setup integer;finish_at timestamptz;blocked text;begin
 select *into o from public.production_orders where factory_id=f and id=i;
 select *into src from public.work_centers where factory_id=f and id=w;
 select *into dst from public.work_centers where factory_id=f and id=a;
 select *into line from public.production_lines where factory_id=f and id=dst.line_id;
 if o.id is null or src.id is null or dst.id is null then raise exception 'not_found';end if;
 remaining:=private.ordinary_output_remaining(f,i);
 if o.status not in('planned','active')or o.actual_finish is not null or remaining<=0 then blocked:='execution_no_remaining';
 elsif o.line_id is null or o.start_time is null or o.expected_finish<=o.start_time then blocked:='execution_plan_required';
 elsif src.archived or src.line_id is distinct from coalesce(o.actual_line_id,o.line_id)then blocked:='f20SourceChanged';
 elsif src.status<>'stopped'or not exists(select 1 from public.downtime_events where factory_id=f and work_center_id=w and ended_at is null)then blocked:='transferStopRequired';
 elsif not exists(select 1 from public.work_center_alternatives where factory_id=f and work_center_id=w and alternative_id=a)
  or src.category_id is distinct from dst.category_id then blocked:='incompatible_alternative';
 elsif dst.archived or line.id is null or line.archived or dst.line_id=src.line_id then blocked:='f20DestinationLineRequired';
 elsif dst.status<>'idle'or dst.order_id is not null then blocked:='f20DestinationBusy';
 elsif line.paused_at is not null then blocked:='f20DestinationPaused';
 elsif exists(select 1 from public.production_orders where factory_id=f and status='active'and id<>i and coalesce(actual_line_id,line_id)=dst.line_id)
  or exists(select 1 from public.work_centers c where c.factory_id=f and c.line_id=dst.line_id and not c.archived and(c.status='running'or c.order_id is not null and c.order_id<>i))then blocked:='f20DestinationBusy';
 elsif exists(select 1 from public.production_transfers where factory_id=f and ended_at is null and(order_id=i or a in(original_id,alternative_id)or w in(original_id,alternative_id)))then blocked:='execution_end_transfer_first';
 elsif not exists(select 1 from public.work_center_capabilities where factory_id=f and work_center_id=a and product_id=o.product_id and rate>0 and rate_unit=o.unit)then blocked:='planningIncompatibleLine';
 elsif exists(select 1 from public.production_routing_steps r join public.work_centers c on c.factory_id=r.factory_id and c.id=r.work_center_id
  where r.factory_id=f and r.product_id=o.product_id and r.kind='work_center'and c.line_id is distinct from dst.line_id)then blocked:='f20FixedRoute';
 elsif private.output_work_held(f,i)then blocked:='planningQualityHold';
 elsif not private.production_stock_enabled(f)or not private.production_stock_eligible(f,i)then
  blocked:='production_material_not_ready';materials:=private.material_start_readiness(f,i);
 end if;
 if blocked is null then
  req:=private.material_requirement_inputs_for_line(f,i,dst.line_id);
  if req->>'existing_source_work'='true'or req->>'mode'='COMPOUND_STOCK'then blocked:='f20SourceWorkRequired';
  elsif req->>'warning'is not null then blocked:=req->>'warning';end if;
 end if;
 if blocked is null then
  select count(*),count(*)filter(where cap.rate_unit=o.unit),min(cap.rate),max(cap.rate),max(cap.setup_minutes)
  into n,typed,rate,fastest,setup from public.work_centers c join public.work_center_capabilities cap
  on cap.factory_id=c.factory_id and cap.work_center_id=c.id and cap.product_id=o.product_id
  where c.factory_id=f and c.line_id=dst.line_id and not c.archived;
  if n=0 or typed<>n or rate<=0 or rate<>fastest then blocked:='planningMissingRate';end if;
 end if;
 if blocked is null then
  physical:=private.execution_machine_readiness(f,i,dst.line_id,o.product_id);
  if physical->>'ready'is distinct from 'true'then blocked:='execution_machine_stopped';
  else physical:=private.maintenance_execution_readiness(f,i,dst.line_id,o.product_id);
   if physical->>'ready'is distinct from 'true'then blocked:='productionReadiness_'||(physical->>'reason');end if;
  end if;
 end if;
 if blocked is null then
  finish_at:=private.finish_after_working_minutes(f,statement_timestamp(),greatest(ceil(remaining*60/rate)+coalesce(setup,0),1)::integer);
  capacity:=private.maintenance_capacity_conflict(f,dst.line_id,o.product_id,a,statement_timestamp(),finish_at,null,i,false);
  if capacity is not null then blocked:='maintenance_capacity_reserved';end if;
 end if;
 if blocked is null then
  materials:=private.execution_dispatch_materials_for_line(f,i,dst.line_id);
  if materials->>'ready'is distinct from 'true'then blocked:='production_material_not_ready';end if;
 end if;
 return jsonb_build_object('machine',dst.id,'name',dst.name,'name_ar',dst.name_ar,'status',dst.status,
  'line',line.id,'line_name',line.name,'line_name_ar',line.name_ar,'compatible',src.category_id=dst.category_id and exists(
   select 1 from public.work_center_capabilities where factory_id=f and work_center_id=a and product_id=o.product_id and rate>0 and rate_unit=o.unit),
  'ready',blocked is null,'blocker',blocked,'materials',materials,'physical',physical,'maintenance',capacity,'remaining',trim_scale(remaining)::text);
end$$;

create function public.production_line_transfer_options(factory uuid,item uuid,source_machine uuid)returns jsonb
language plpgsql stable security definer set search_path=''as $$declare o public.production_orders;rows jsonb;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'orders','view');
 select *into o from public.production_orders where factory_id=factory and id=item;if not found then raise exception 'not_found';end if;
 if not exists(select 1 from public.work_centers where factory_id=factory and id=source_machine)then raise exception 'not_found';end if;
 select coalesce(jsonb_agg(private.line_transfer_readiness(factory,item,source_machine,c.id)order by c.name,c.id),'[]')into rows
 from public.work_center_alternatives r join public.work_centers c on c.factory_id=r.factory_id and c.id=r.alternative_id
 where r.factory_id=factory and r.work_center_id=source_machine;
 return jsonb_build_object('factory',factory,'item',item,'source_machine',source_machine,'fingerprint',private.execution_fingerprint(factory,item),
 'order',to_jsonb(o),'remaining',private.ordinary_output_remaining(factory,item)::text,'requires_output_confirmation',o.status='active','rows',rows);
end$$;

create function public.production_line_transfer_submit(factory uuid,item uuid,source_machine uuid,alternative_machine uuid,
 reason text,fingerprint text,request_id uuid,output_confirmed boolean default false)returns jsonb
language plpgsql security definer set search_path=''as $$
declare o public.production_orders;c private.production_execution_commands;intent jsonb;response jsonb;readiness jsonb;
 state text;message text;detail text;source_line uuid;destination_line uuid;stop_id uuid;source_run uuid;child_request uuid;begin
 perform private.require_permission(factory,'orders','view');perform private.require_permission(factory,'orders','edit');perform private.require_permission(factory,'centers','edit');
 if current_setting('transaction_isolation')not in('read committed','read uncommitted')then raise exception 'execution_readiness_stale'using errcode='40001';end if;
 if request_id is null or source_machine is null or alternative_machine is null or reason is null or length(reason)>240 or fingerprint is null or fingerprint!~'^[a-f0-9]{64}$'or output_confirmed is null then raise exception 'execution_context_changed'using errcode='22023';end if;
 intent:=jsonb_build_object('item',item,'operation','TRANSFER_LINE','source_machine',source_machine,'alternative_machine',alternative_machine,
  'reason',btrim(reason),'fingerprint',fingerprint,'output_confirmed',output_confirmed);
 -- The same factory/maintenance/structure lock order as normal execution.
 -- Admission locks survive a rejected subtransaction and protect retry finality.
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.maintenance_planning_lock(factory);
 perform pg_advisory_xact_lock(hashtextextended(factory::text||':structure',0));
 select *into c from private.production_execution_commands where factory_id=factory and production_execution_commands.request_id=production_line_transfer_submit.request_id;
 if found then
  if c.actor<>auth.uid()or c.item_id<>item or c.intent<>intent or c.result is null then raise exception 'execution_command_conflict'using errcode='22023';end if;
  if c.result->>'outcome'='REJECTED'then return c.result;end if;
  return jsonb_build_object('outcome','COMMITTED','request_id',request_id,'data',c.result);
 end if;
 select *into o from public.production_orders where factory_id=factory and id=item for update;if not found then raise exception 'not_found';end if;
 perform 1 from public.work_centers where factory_id=factory and id in(source_machine,alternative_machine)order by id for update;
 begin
  if char_length(btrim(reason))<3 then raise exception 'execution_reason_required'using errcode='22023';end if;
  if private.execution_fingerprint(factory,item)is distinct from fingerprint then raise exception 'execution_context_changed'using errcode='40001';end if;
  if o.status='active'and output_confirmed is distinct from true then raise exception 'execution_record_output_first'using errcode='22023';end if;
  perform private.refresh_production_stock(factory);
  readiness:=private.line_transfer_readiness(factory,item,source_machine,alternative_machine);
  if readiness->>'ready'is distinct from 'true'then
   raise exception using message=readiness->>'blocker',errcode='22023',detail=case when readiness->>'blocker'='production_material_not_ready'then(readiness->'materials')::text else readiness::text end;
  end if;
  source_line:=coalesce(o.actual_line_id,o.line_id);destination_line:=(readiness->>'line')::uuid;
  select id into stop_id from public.downtime_events where factory_id=factory and work_center_id=source_machine and ended_at is null;
  select id into source_run from private.production_execution_runs where factory_id=factory and item_id=item and ended_at is null;
  insert into private.production_execution_commands(factory_id,request_id,actor,item_id,operation,reason,intent,before_state)
  values(factory,request_id,auth.uid(),item,'TRANSFER_LINE',btrim(reason),intent,to_jsonb(o)||jsonb_build_object(
   'source_line',source_line,'destination_line',destination_line,'source_machine',source_machine,'alternative_machine',alternative_machine,'source_downtime',stop_id,'source_run',source_run));
  if o.status='active'then
   child_request:=gen_random_uuid();
   perform public.production_execution_action(factory,item,'INTERRUPT',reason,fingerprint,child_request,true);
  end if;
  -- This column never edits line_id, the approved interval or plan revisions.
  update public.production_orders set actual_line_id=destination_line where factory_id=factory and id=item;
  child_request:=gen_random_uuid();
  perform public.production_execution_action(factory,item,case when o.actual_start is null then 'START_SELECTED'else 'RESUME'end,
   reason,private.execution_fingerprint(factory,item),child_request,false);
  response:=public.production_execution_context(factory,item);
  update private.production_execution_commands set result=response where factory_id=factory and production_execution_commands.request_id=production_line_transfer_submit.request_id;
  return jsonb_build_object('outcome','COMMITTED','request_id',request_id,'data',response);
 exception when others then
  get stacked diagnostics state=returned_sqlstate,message=message_text,detail=pg_exception_detail;
  response:=jsonb_build_object('outcome','REJECTED','request_id',request_id,'error',jsonb_build_object('code',state,'message',message,'details',case when message='production_material_not_ready'then detail end));
  insert into private.production_execution_commands(factory_id,request_id,actor,item_id,operation,reason,intent,before_state,result)
  values(factory,request_id,auth.uid(),item,'TRANSFER_LINE',btrim(reason),intent,to_jsonb(o)||jsonb_build_object('execution_rejected',true),response);
  return response;
 end;
end$$;
revoke all on function private.line_transfer_readiness(uuid,uuid,uuid,uuid),public.production_line_transfer_options(uuid,uuid,uuid),
 public.production_line_transfer_submit(uuid,uuid,uuid,uuid,text,text,uuid,boolean)from public,anon,authenticated,service_role;
grant execute on function public.production_line_transfer_options(uuid,uuid,uuid),public.production_line_transfer_submit(uuid,uuid,uuid,uuid,text,text,uuid,boolean)to authenticated;
