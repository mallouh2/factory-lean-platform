-- Local Phase5D. No activation, historical updates, inventory or costing writes.
create function private.production_loss_maintenance_evidence(f uuid,e uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare d public.downtime_events;a public.maintenance_stop_associations;h public.maintenance_schedule_revisions;
 c uuid;valid boolean:=false;begin
 select * into d from public.downtime_events where factory_id=f and id=e;
 if not found then raise exception 'history_event_not_found' using errcode='P0002';end if;
 select id into c from public.downtime_classification_corrections where factory_id=f and event_id=e order by corrected_at desc,id desc limit 1;
 select * into a from public.maintenance_stop_associations where factory_id=f and event_id=e order by revision desc limit 1;
 if a.operation='LINK' then
 select * into h from public.maintenance_schedule_revisions where factory_id=f and schedule_id=a.schedule_id and revision=a.approval_revision and event in ('confirm','reschedule');
 valid:=h.id is not null and h.after_data=a.approval and h.resources=a.resources
 and a.approval->>'confirmed_by' is not null and a.approval->>'confirmed_at' is not null
 and exists(select 1 from jsonb_array_elements(a.resources) r where r->>'resource_kind'='MACHINE' and r->>'machine_id'=d.work_center_id::text);
 end if;
 return jsonb_build_object('policy_version',1,'event_id',e,'machine_id',d.work_center_id,
 'classification_revision',c,'association_id',a.id,'association_revision',coalesce(a.revision,0),
 'operation',coalesce(a.operation,'NONE'),'schedule_id',a.schedule_id,'relationship',a.relationship,
 'approval_revision',a.approval_revision,'approval',a.approval,'resources',a.resources,
 'approved_start',a.approval->>'planned_start','approved_end',a.approval->>'planned_end','valid',coalesce(valid,false));
end$$;
revoke all on function private.production_loss_maintenance_evidence(uuid,uuid) from public,anon,authenticated;

create function public.production_loss_maintenance_context(factory uuid,event uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare evidence jsonb;s public.production_loss_estimates;state text;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'downtime','view');
 evidence:=private.production_loss_maintenance_evidence(factory,event);
 select * into s from public.production_loss_estimates where factory_id=factory and event_id=event;
 state:=case when s.id is null then 'UNREVIEWED'
 when s.result->>'maintenance_policy_version' is distinct from '1' or not(s.result ? 'maintenance_context') then 'EVIDENCE_COMPARISON_UNKNOWN'
 when s.result->'maintenance_context' is distinct from evidence then 'EVIDENCE_CHANGED_AFTER_REVIEW' else 'CURRENT' end;
 return jsonb_build_object('evidence',evidence,'review_state',state);
end$$;
revoke all on function public.production_loss_maintenance_context(uuid,uuid) from public,anon;
grant execute on function public.production_loss_maintenance_context(uuid,uuid) to authenticated;

-- One bounded, factory-scoped source bundle, taken in one statement snapshot.
-- Full association tables are never exposed to the browser or calculation service.
create function private.production_loss_inputs(f uuid,e uuid) returns jsonb
language plpgsql stable security definer set search_path='' set timezone='UTC' as $$
declare d public.downtime_events;payload jsonb;begin
 select * into d from public.downtime_events where factory_id=f and id=e and ended_at is not null and loss_model_version=1;
 if not found then raise exception 'downtime_not_reviewable';end if;
 if (select count(*)>10000 from public.production_loss_context_snapshots where factory_id=f and event_id=e)
 or (select count(*)>10000 from public.production_loss_actuals a join public.downtime_events x on x.factory_id=a.factory_id and x.id=a.event_id where a.factory_id=f and x.work_center_id=d.work_center_id) then
 raise exception 'loss_estimate_incomplete';end if;
 payload:=jsonb_build_object('event',to_jsonb(d),'maintenance',private.production_loss_maintenance_evidence(f,e),
 'samples',(select coalesce(jsonb_agg(to_jsonb(s) order by s.captured_at,s.id),'[]') from public.production_loss_context_snapshots s where s.factory_id=f and s.event_id=e),
 'correction',(select to_jsonb(c) from public.downtime_classification_corrections c where c.factory_id=f and c.event_id=e order by c.corrected_at desc,c.id desc limit 1),
 'actual',(select to_jsonb(a) from public.production_loss_actuals a where a.factory_id=f and a.event_id=e),
 'observations',(select coalesce(jsonb_agg(jsonb_build_object('event',to_jsonb(x),'actual',to_jsonb(a),'saved',to_jsonb(s)) order by x.id),'[]')
 from public.downtime_events x join public.production_loss_actuals a on a.factory_id=x.factory_id and a.event_id=x.id
 join public.production_loss_estimates s on s.factory_id=x.factory_id and s.event_id=x.id
 where x.factory_id=f and x.work_center_id=d.work_center_id and x.id<>e and x.ended_at is not null));
 return payload||jsonb_build_object('input_hash',encode(sha256(convert_to(payload::text,'UTF8')),'hex'));
end$$;
revoke all on function private.production_loss_inputs(uuid,uuid) from public,anon,authenticated;
create function public.production_loss_review_inputs(factory uuid,event uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'downtime','edit');
 if exists(select 1 from public.production_loss_estimates where factory_id=factory and event_id=event) then raise exception 'loss_estimate_locked';end if;
 return private.production_loss_inputs(factory,event);
end$$;
revoke all on function public.production_loss_review_inputs(uuid,uuid) from public,anon;
grant execute on function public.production_loss_review_inputs(uuid,uuid) to authenticated;

create or replace function public.persist_production_loss_estimate(factory uuid,event uuid,actor uuid,estimate jsonb,correction uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare input jsonb;s public.production_loss_estimates;v uuid;stamp timestamptz;begin
 -- service_role-only entry point: actor is obtained from a verified user JWT.
 if actor is null then raise exception 'permission_denied' using errcode='42501';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'downtime','edit');
 if current_setting('transaction_isolation') not in ('read committed','read uncommitted') then raise exception 'loss_estimate_context_mismatch' using errcode='40001';end if;
 perform private.maintenance_planning_lock(factory);
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'downtime','edit');
 -- Serialize existing closed-event approval/metadata writers that use the event row lock.
 perform 1 from public.downtime_events where factory_id=factory and id=event for update;
 select * into s from public.production_loss_estimates where factory_id=factory and event_id=event;
 -- Identical actor/input retries return the same immutable result, even if later evidence changed.
 if s.id is not null then
 if s.recorded_by=actor and s.result->>'input_hash'=estimate->>'input_hash' and
 (s.result-'calculated_at')=(estimate-'calculated_at'-'actual_scrap_quantity'-'actual_recovery_minutes') then return s.id;end if;
 raise exception 'loss_estimate_locked';end if;
 input:=private.production_loss_inputs(factory,event);
 if input->>'input_hash' is distinct from estimate->>'input_hash' or
 input->'maintenance' is distinct from estimate->'maintenance_context' or
 (input->'correction'->>'id')::uuid is distinct from correction then
 raise exception 'loss_estimate_context_mismatch' using errcode='40001';end if;
 if jsonb_typeof(estimate) is distinct from 'object' or estimate->>'readiness' is distinct from 'READY'
 or estimate->>'model_version' is distinct from '1' or estimate->>'maintenance_policy_version' is distinct from '1'
 or jsonb_typeof(estimate->'assumptions') is distinct from 'array' or jsonb_typeof(estimate->'missing') is distinct from 'array'
 or jsonb_array_length(estimate->'missing')<>0 then raise exception 'loss_estimate_incomplete';end if;
 if jsonb_array_length(estimate->'assumptions')=0 and not coalesce((
 estimate->'maintenance_context'->>'relationship'='PLANNED_MAINTENANCE' and estimate->'maintenance_context'->>'valid'='true'
 and jsonb_typeof(estimate->'maintenance_segments')='array' and jsonb_array_length(estimate->'maintenance_segments')>0
 and estimate->>'effective_loss_minutes'='0' and estimate->>'estimated_lost_output_quantity'='0'),false) then raise exception 'loss_estimate_incomplete';end if;
 if exists(select 1 from jsonb_array_elements((estimate->'assumptions')||coalesce(estimate->'maintenance_segments','[]')) a where not exists(select 1 from public.production_loss_context_snapshots ctx where ctx.factory_id=factory and ctx.event_id=event and ctx.id=(a->>'context_snapshot_id')::bigint)) then
 raise exception 'loss_estimate_context_mismatch' using errcode='40001';end if;
 stamp:=clock_timestamp();
 insert into public.production_loss_estimates(factory_id,event_id,model_version,result,calculated_at,recorded_by)
 values(factory,event,1,jsonb_set(estimate-'actual_scrap_quantity'-'actual_recovery_minutes','{calculated_at}',to_jsonb(stamp)),stamp,actor) returning id into v;
 return v;
end$$;
revoke all on function public.persist_production_loss_estimate(uuid,uuid,uuid,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.persist_production_loss_estimate(uuid,uuid,uuid,jsonb,uuid) to service_role;

create function private.loss_estimate_immutable() returns trigger language plpgsql set search_path='' as $$begin raise exception 'loss_estimate_locked';end$$;
create trigger loss_estimate_immutable before update or delete on public.production_loss_estimates for each row execute function private.loss_estimate_immutable();
revoke all on function private.loss_estimate_immutable() from public,anon,authenticated;

-- Classification and actuals participate in the same structure-first lock.
alter function public.correct_downtime_classification(uuid,uuid,text,uuid,text,text) rename to correct_downtime_classification_before_loss;
alter function public.correct_downtime_classification_before_loss(uuid,uuid,text,uuid,text,text) set schema private;
revoke all on function private.correct_downtime_classification_before_loss(uuid,uuid,text,uuid,text,text) from public,anon,authenticated;
create function public.correct_downtime_classification(factory uuid,event uuid,nature text,reason uuid,activity text,note text) returns uuid
language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(factory,'downtime','edit');
 if current_setting('transaction_isolation') not in ('read committed','read uncommitted') then raise exception 'loss_estimate_context_mismatch' using errcode='40001';end if;
 perform private.maintenance_planning_lock(factory);perform private.require_permission(factory,'downtime','edit');
 return private.correct_downtime_classification_before_loss(factory,event,nature,reason,activity,note);
end$$;
revoke all on function public.correct_downtime_classification(uuid,uuid,text,uuid,text,text) from public,anon;
grant execute on function public.correct_downtime_classification(uuid,uuid,text,uuid,text,text) to authenticated;
alter function public.record_production_loss_actuals(uuid,uuid,numeric,text,numeric,numeric,numeric,numeric,numeric,text) rename to record_production_loss_actuals_before_loss;
alter function public.record_production_loss_actuals_before_loss(uuid,uuid,numeric,text,numeric,numeric,numeric,numeric,numeric,text) set schema private;
revoke all on function private.record_production_loss_actuals_before_loss(uuid,uuid,numeric,text,numeric,numeric,numeric,numeric,numeric,text) from public,anon,authenticated;
create function public.record_production_loss_actuals(factory uuid,event uuid,scrap_quantity numeric,scrap_unit text,recovery_minutes numeric,shutdown_scrap numeric,restart_scrap numeric,actual_loss_minutes numeric,actual_lost_output_quantity numeric,actual_lost_output_unit text) returns uuid
language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(factory,'downtime','edit');
 if current_setting('transaction_isolation') not in ('read committed','read uncommitted') then raise exception 'loss_estimate_context_mismatch' using errcode='40001';end if;
 perform private.maintenance_planning_lock(factory);perform private.require_permission(factory,'downtime','edit');
 return private.record_production_loss_actuals_before_loss(factory,event,scrap_quantity,scrap_unit,recovery_minutes,shutdown_scrap,restart_scrap,actual_loss_minutes,actual_lost_output_quantity,actual_lost_output_unit);
end$$;
revoke all on function public.record_production_loss_actuals(uuid,uuid,numeric,text,numeric,numeric,numeric,numeric,numeric,text) from public,anon;
grant execute on function public.record_production_loss_actuals(uuid,uuid,numeric,text,numeric,numeric,numeric,numeric,numeric,text) to authenticated;

-- Capture completeness/routing only for new snapshots; old samples are never updated.
create or replace function private.capture_production_loss_context(f uuid,at_time timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare event_row record; context_value jsonb;
begin
  if f is null or at_time is null then return; end if;
  for event_row in select id from public.downtime_events
    where factory_id=f and not retroactive and started_at<=at_time
      and (ended_at is null or ended_at>=at_time) loop
    select jsonb_build_object(
      'maintenance_loss_context_version',1,'demand_complete',true,
      'routing_steps',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.production_routing_steps x where x.factory_id=f),
      'centers',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
        from public.work_centers x where x.factory_id=f),
      'stops',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
        from public.downtime_events x where x.factory_id=f and x.ended_at is null),
      'transfers',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
        from public.production_transfers x where x.factory_id=f and x.ended_at is null),
      'orders',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
        from public.production_orders x where x.factory_id=f and x.status<>'cancelled'),
      'products',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
        from public.products x where x.factory_id=f),
      'capabilities',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
        from public.work_center_capabilities x where x.factory_id=f),
      'alternatives',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
        from public.work_center_alternatives x where x.factory_id=f),
      'profiles',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
        from public.production_loss_profiles x where x.factory_id=f),
      'recovery_rates',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
        from public.production_loss_recovery_rates x where x.factory_id=f),
      'lines',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
        from public.production_lines x where x.factory_id=f)
    ) into context_value;
    insert into public.production_loss_context_snapshots
      (factory_id,event_id,captured_at,context)
      values(f,event_row.id,at_time,context_value);
  end loop;
end;
$$;

-- Explicit historical early-start linkage requires real overlap, never adjusted approval boundaries.
create or replace function private.maintenance_append_stop(f uuid,e uuid,sid uuid,approval_rev integer,op text,note text,retry uuid)
 returns uuid language plpgsql security definer set search_path='' as $$
declare d public.downtime_events;s public.maintenance_schedules;h public.maintenance_schedule_revisions;
 previous public.maintenance_stop_associations;v uuid;reviewed jsonb;begin
 select * into d from public.downtime_events where factory_id=f and id=e;
 if not found then raise exception 'maintenance_downtime';end if;
 if d.stop_nature not in ('planned','unplanned') then raise exception 'maintenance_stop_scope';end if;
 select * into s from public.maintenance_schedules where factory_id=f and id=sid;
 if not found then raise exception 'maintenance_missing';end if;
 select * into previous from public.maintenance_stop_associations where factory_id=f and event_id=e order by revision desc limit 1;
 if op='UNLINK' then
 if previous.id is null or previous.operation<>'LINK' or previous.schedule_id<>sid then raise exception 'maintenance_stop_conflict';end if;
 h.after_data:=previous.approval;h.resources:=previous.resources;h.revision:=previous.approval_revision;
 else
 select * into h from public.maintenance_schedule_revisions where factory_id=f and schedule_id=sid
 and revision=approval_rev and event in ('confirm','reschedule');
 if not found or not exists(select 1 from jsonb_array_elements(h.resources) r
 where r->>'resource_kind'='MACHINE' and r->>'machine_id'=d.work_center_id::text) then raise exception 'maintenance_stop_scope';end if;
 if d.started_at>=(h.after_data->>'planned_end')::timestamptz or coalesce(d.ended_at,'infinity')<=(h.after_data->>'planned_start')::timestamptz then
 raise exception 'maintenance_stop_window';end if;
 -- An open historical event cannot acquire an unrelated old/released reservation.
 if d.ended_at is null and (s.state not in ('CONFIRMED','INVALIDATED') or
 (s.planned_start,s.planned_end) is distinct from ((h.after_data->>'planned_start')::timestamptz,(h.after_data->>'planned_end')::timestamptz)) then
 raise exception 'maintenance_stop_scope';end if;
 end if;
 if coalesce(length(btrim(note)),0) not between 1 and 4000 then raise exception 'maintenance_note';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'calculated_at',x.calculated_at,'model_version',x.model_version,
 'result_hash',md5(x.result::text))),'[]') into reviewed from public.production_loss_estimates x where x.factory_id=f and x.event_id=e;
 insert into public.maintenance_stop_associations(factory_id,event_id,revision,operation,schedule_id,previous_id,approval_revision,
 approval,resources,relationship,actor_id,actor_name,reason,request_id,reviewed_evidence)
 values(f,e,coalesce(previous.revision,0)+1,op,sid,previous.id,h.revision,h.after_data,h.resources,
 case when d.stop_nature='planned' then 'PLANNED_MAINTENANCE' else 'CONTEXTUAL_UNPLANNED' end,auth.uid(),
 (select display_name from public.memberships where factory_id=f and user_id=auth.uid()),note,retry,reviewed) returning id into v;
 return v;
end$$;


-- New routing transitions use the same immutable event-context recorder.
create trigger loss_context_routing after insert or update or delete on public.production_routing_steps
 for each row execute function private.capture_production_loss_change();
