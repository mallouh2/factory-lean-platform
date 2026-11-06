begin;
-- Complete the preserved pending candidates without changing their bytes.
-- Match canonical factory -> structure -> item locking before checking custody.
create or replace function private.planning_change_state(f uuid,i uuid)returns jsonb language plpgsql stable security definer set search_path='' as $$
declare o public.production_orders;material jsonb;material_evidence jsonb;source_evidence jsonb;seconds numeric;policy_revision bigint;issued boolean;allocated boolean;prep boolean;at_time timestamptz:=clock_timestamp();consumed numeric;held boolean;begin
select *into o from public.production_orders where factory_id=f and id=i;if not found then raise exception 'planning_item_missing';end if;
select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'revision',r.revision,'status',r.status,'quantity',r.quantity::text,'unit',r.unit,'lot_id',r.lot_id)order by r.id),'[]'),coalesce(jsonb_agg(to_jsonb(r)order by r.id),'[]')into material,material_evidence from public.material_requests r where r.factory_id=f and r.production_item_id=i and r.status not in('CANCELLED','REJECTED');
select coalesce(jsonb_agg(jsonb_build_object('allocation',to_jsonb(w),'lot',to_jsonb(l))order by w.item_id),'[]')into source_evidence from private.manufactured_completion_work w left join public.unfinished_lots l on l.factory_id=w.factory_id and l.id=w.lot_id where w.factory_id=f and w.item_id=i;
select p.seconds,p.revision into seconds,policy_revision from private.planning_change_policy p where p.factory_id=f;seconds:=coalesce(seconds,21600);policy_revision:=coalesce(policy_revision,0);
consumed:=private.output_work_consumed(f,i);held:=private.output_work_held(f,i);
issued:=exists(select 1 from jsonb_array_elements(material)m where m->>'status'in('ISSUED','RECEIVED'));
allocated:=exists(select 1 from private.manufactured_completion_work w join public.material_requests r on r.factory_id=w.factory_id and r.id=w.material_request_id where w.factory_id=f and w.item_id=i and w.choice in('COMPLETE','STOCK')and w.lot_id is not null and r.status='REQUESTED'and w.quantity>consumed and private.output_work_live(f,i));prep:=issued or allocated;
return jsonb_build_object('item',i,'code',o.code,'line',o.line_id,'start',o.start_time,'finish',o.expected_finish,'status',o.status,'materials',material,'prepared',prep,'issued',issued,'allocated',allocated,'consumed',consumed::text,'held',held,'issued_time_change_safe',private.planning_issued_time_change_safe(f,i),'seconds',seconds::text,'policy_revision',policy_revision,'remaining_seconds',case when o.start_time is not null then floor(extract(epoch from(o.start_time-at_time)))::text else null end,
'exception_required',o.start_time is not null and(prep or o.start_time-at_time<=(seconds::text||' seconds')::interval),
'fingerprint',md5(jsonb_build_object('order',to_jsonb(o),'materials',material_evidence,'source',source_evidence,'seconds',seconds,'policy_revision',policy_revision,'consumed',consumed,'hold',held)::text));end$$;
CREATE OR REPLACE FUNCTION public.revise_product_plan_confirmed(factory uuid, item uuid, target_line uuid, planned_start timestamp with time zone, reason_code text, reason_note text, expected_fingerprint text, exception_confirmed boolean, request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare state jsonb;intent jsonb;prior private.planning_change_commands;r jsonb;begin
perform private.require_permission(factory,'orders','edit');perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.maintenance_planning_lock(factory);perform private.require_permission(factory,'orders','edit');
if current_setting('transaction_isolation')<>'read committed' then raise exception 'planning_changed'using errcode='40001';end if;
if request_id is null then raise exception 'planning_confirmation_required';end if;
intent:=jsonb_build_object('item',item,'line',target_line,'start',planned_start,'reason_code',reason_code,'reason_note',reason_note,'fingerprint',expected_fingerprint,'confirmed',exception_confirmed);
select *into prior from private.planning_change_commands p where p.factory_id=factory and p.request_id=revise_product_plan_confirmed.request_id;
if found then if prior.actor<>auth.uid()or prior.intent<>intent then raise exception 'request_conflict'using errcode='40001';end if;return prior.result;end if;
perform 1 from public.production_orders where factory_id=factory and id=item for update;
state:=private.planning_change_state(factory,item)||jsonb_build_object('before_revision',(select coalesce(max(revision_no),0)from public.production_plan_revisions where factory_id=factory and item_id=item));
if state->>'fingerprint'is distinct from expected_fingerprint then raise exception 'planning_changed'using errcode='40001';end if;
if(state->>'exception_required')::boolean and(exception_confirmed is distinct from true or coalesce(length(btrim(reason_note)),0)<3)then raise exception 'planning_confirmation_required';end if;
insert into private.planning_change_commands(factory_id,request_id,actor,item_id,intent,fingerprint)values(factory,request_id,auth.uid(),item,intent,expected_fingerprint);
perform set_config('app.planning_change_request',request_id::text,true);
perform public.revise_product_plan(factory,item,target_line,planned_start,reason_code,reason_note);
r:=jsonb_build_object('item',item,'request_id',request_id,'exceptional',(state->>'exception_required')::boolean,'revision',(select max(revision_no)from public.production_plan_revisions where factory_id=factory and item_id=item));
r:=r||jsonb_build_object('prepared',state->'prepared','preparation',state->'materials','changed',(r->>'revision')::bigint>(state->>'before_revision')::bigint);update private.planning_change_commands p set result=r where p.factory_id=factory and p.request_id=revise_product_plan_confirmed.request_id;return r;end$function$;
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
  if (private.planning_change_state(old.factory_id,old.id)->>'exception_required')::boolean and not exists(
 select 1 from private.planning_change_commands c where c.factory_id=old.factory_id and c.item_id=old.id and c.actor=auth.uid()and c.transaction_id=txid_current()
 and c.request_id::text=current_setting('app.planning_change_request',true)and c.result is null and c.fingerprint=private.planning_change_state(old.factory_id,old.id)->>'fingerprint')then raise exception 'planning_confirmation_required';end if;
 if old.planning_locked_at is not null then raise exception 'planning_locked'; end if;
  if old.status <> 'planned' or old.produced_quantity > 0 or
    old.actual_start is not null or old.actual_finish is not null then
    raise exception 'planning_already_started';
  end if;
  if old.planning_ever_scheduled and not private.planning_unstarted_reversible(old.factory_id,old.id)
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
commit;
