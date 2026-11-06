-- Phase 3C only: current consumer truth, not recording/stock/activation changes.
begin;

-- A review remains an immutable historical decision; later corrections require
-- a new existing Scrap review before their quantities qualify as reviewed input.
create function private.production_scrap_review_current(f uuid,e uuid,reviewed timestamptz)
returns boolean language sql stable security definer set search_path='' as $$
 select reviewed is not null and not exists(select 1 from public.production_entry_corrections c
 where c.factory_id=f and c.entry_id=e and c.created_at>reviewed)
$$;

-- Shared containment rule. Recorded time only scopes UNKNOWN evidence; it never
-- becomes the physical time, and a period is never prorated at a window boundary.
create function private.production_period_scope(precision_kind text,point_at timestamptz,a timestamptz,b timestamptz,recorded timestamptz,lo timestamptz,hi timestamptz)
returns text language sql immutable set search_path='' as $$
 select case when precision_kind='EXACT' and point_at is not null then case when point_at>=lo and point_at<hi then 'CONTAINED' else 'OUTSIDE' end
 when precision_kind='SHIFT_PERIOD' and a is not null and b is not null and b>=a then
 case when a=b then case when a>=lo and a<hi then 'CONTAINED' else 'OUTSIDE' end
 when a>=hi or b<=lo then 'OUTSIDE' when a>=lo and b<=hi then 'CONTAINED' else 'PARTIAL' end
 else case when recorded>=lo and recorded<hi then 'UNKNOWN' else 'OUTSIDE' end end
$$;

-- The sole new writer form is explicitly required by Phase0 M3. Exact calls and
-- other commands delegate below, with the approved initiative bounds amendment.
-- No caller-supplied period.
alter function private.lean_command(uuid,uuid,text,jsonb) rename to lean_command_before_m3c;
revoke all on function private.lean_command_before_m3c(uuid,uuid,text,jsonb) from public,anon,authenticated;
create function private.lean_command(f uuid,r uuid,op text,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare e public.production_entries;o public.production_orders;saved private.lean_command_retries;result jsonb;begin
 if op<>'scrap_observation' or not(p ? 'time_precision') then return private.lean_command_before_m3c(f,r,op,p);end if;
 if current_setting('transaction_isolation')<>'read committed' or r is null or p is null or jsonb_typeof(p)<>'object' or octet_length(p::text)>10000
 or p->>'time_precision' is distinct from 'SHIFT_PERIOD'
 or exists(select 1 from jsonb_object_keys(p)k where k not in ('id','entry_id','time_precision','preliminary_cause_id','observation','response'))
 or (length(btrim(p->>'observation')) between 3 and 2000) is distinct from true
 or (length(btrim(p->>'response')) between 3 and 2000) is distinct from true or p->>'id' is null or p->>'preliminary_cause_id' is null
 then raise exception 'lean_invalid' using errcode='22023';end if;
 perform private.require_permission(f,'factory','view');perform private.require_permission(f,'orders','edit');
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));
 perform pg_advisory_xact_lock(hashtextextended(f::text||':structure',0));
 perform private.require_permission(f,'factory','view');perform private.require_permission(f,'orders','edit');
 select * into saved from private.lean_command_retries where factory_id=f and id=r;
 if found then
  if saved.actor_id<>auth.uid() or saved.operation<>op or saved.payload<>p then raise exception 'lean_conflict' using errcode='40001';end if;
  return saved.result;
 end if;
 select * into e from public.production_entries where factory_id=f and id=(p->>'entry_id')::uuid for share;
 select * into o from public.production_orders where factory_id=f and id=e.order_id;
 if e.id is null or e.attribution_version is distinct from 1 or e.time_precision is distinct from 'SHIFT_PERIOD'
 or e.effective_occurrence_key is null or e.effective_period_start is null or e.effective_period_end is null or e.effective_scrap_kg is null or e.line_id is null
 then raise exception 'reporting_observation_period_invalid' using errcode='22023';end if;
 insert into public.lean_scrap_events(id,factory_id,entry_id,line_id,product_id,occurred_at,time_precision,occurrence_key,period_start,period_end,
 preliminary_cause_id,observation,response,created_by)
 values((p->>'id')::uuid,f,e.id,e.line_id,o.product_id,null,'SHIFT_PERIOD',e.effective_occurrence_key,e.effective_period_start,e.effective_period_end,
 (p->>'preliminary_cause_id')::uuid,p->>'observation',p->>'response',auth.uid());
 result:=jsonb_build_object('id',(p->>'id')::uuid);
 insert into private.lean_command_retries(factory_id,id,actor_id,operation,payload,result) values(f,r,auth.uid(),op,p,result);
 perform private.require_permission(f,'factory','view');perform private.require_permission(f,'orders','edit');return result;
end$$;
revoke all on function private.lean_command(uuid,uuid,text,jsonb) from public,anon;
grant execute on function private.lean_command(uuid,uuid,text,jsonb) to authenticated;

-- Existing M3A column order/types are preserved; only reviewed eligibility changes.
create or replace view private.production_reporting_entries as
select e.*,o.request_id production_request_id,o.product_id,o.code item_code,r.code request_code,
 p.code product_code,p.name product_name,p.name_ar product_name_ar,
 l.name line_name,l.name_ar line_name_ar,tech.display_name technician_name,actor.display_name submitter_name,
 to_jsonb(origin) original_occurrence,to_jsonb(effective) effective_occurrence,
 s.id observation_id,s.time_precision observation_precision,s.occurred_at observation_at,
 s.occurrence_key observation_occurrence_key,s.period_start observation_period_start,s.period_end observation_period_end,
 s.reviewed_at scrap_reviewed_at,
 case when s.id is null then 'UNOBSERVED' when s.reviewed_at is null then 'PENDING' else 'REVIEWED' end scrap_review_status,
 case when s.approved_cause_id is not null and private.production_scrap_review_current(e.factory_id,e.id,s.reviewed_at) then e.effective_scrap_kg end reviewed_scrap_kg,
 coalesce(q.quantity,0) quality_rejected,e.effective_good-coalesce(q.quantity,0) accepted_good,
 o.actual_start current_execution_start,o.actual_finish current_execution_finish,o.status current_item_status
from public.production_entries e
join public.production_orders o on o.factory_id=e.factory_id and o.id=e.order_id
left join public.production_requests r on r.factory_id=o.factory_id and r.id=o.request_id
left join public.products p on p.factory_id=o.factory_id and p.id=o.product_id
left join public.production_lines l on l.factory_id=e.factory_id and l.id=e.line_id
left join public.memberships tech on tech.factory_id=e.factory_id and tech.id=e.technician_id
left join public.memberships actor on actor.factory_id=e.factory_id and actor.user_id=e.created_by
left join private.production_shift_occurrences origin on origin.factory_id=e.factory_id and origin.occurrence_key=e.original_occurrence_key
left join private.production_shift_occurrences effective on effective.factory_id=e.factory_id and effective.occurrence_key=e.effective_occurrence_key
left join public.lean_scrap_events s on s.factory_id=e.factory_id and s.entry_id=e.id
left join lateral(select sum(x.quantity) quantity from public.quality_rejections x where x.factory_id=e.factory_id and x.entry_id=e.id
 and not exists(select 1 from public.quality_reversals v where v.factory_id=x.factory_id and v.rejection_id=x.id))q on true;

create or replace view private.lean_occurrences as
 select d.factory_id,'downtime'::text mechanism,d.id event_id,d.work_center_id machine_id,d.line_id,
 case when (select count(distinct x->>'product_id') from jsonb_array_elements(coalesce(estimate.result->'assumptions','[]'))x)>1 then null::uuid
 else coalesce(o.product_id,(estimate.result->'assumptions'->0->>'product_id')::uuid) end product_id,d.approved_cause_id cause_id,
 d.started_at occurred_at,d.ended_at,d.lean_shift_id shift_id,
 coalesce(a.actual_loss_minutes,(estimate.result->>'effective_loss_minutes')::numeric) loss_minutes,
 coalesce(a.actual_lost_output_quantity,(estimate.result->>'estimated_lost_output_quantity')::numeric) lost_output,
 coalesce(a.actual_lost_output_unit,estimate.result->>'unit',o.unit) output_unit,
 case when associated.entries>0 then associated.scrap_kg when a.scrap_unit='kg' then a.scrap_quantity end scrap_kg,
 associated.produced_kg,associated.wip_quantity,d.initial_note observation,d.reason_id preliminary_cause_id,null::text response,
 d.order_id item_id,d.id downtime_id,estimate.result loss_details,
 case when a.actual_loss_minutes is not null then 'ACTUAL' when estimate.id is not null then 'SAVED_ESTIMATE' else 'MISSING' end loss_source,d.engineering_note approved_note,d.approved_at reviewed_at,
'EXACT'::text time_precision,null::timestamptz period_start,null::timestamptz period_end,null::text occurrence_key,d.created_at recorded_at,
2::integer evidence_version,true review_current,'CONTAINED'::text allocation_status,null::jsonb observation_provenance
 from public.downtime_events d left join public.production_orders o on o.factory_id=d.factory_id and o.id=d.order_id
 left join public.production_loss_estimates estimate on estimate.factory_id=d.factory_id and estimate.event_id=d.id
 left join public.production_loss_actuals a on a.factory_id=d.factory_id and a.event_id=d.id
 left join lateral(select count(*) entries,case when bool_and(private.production_scrap_review_current(s.factory_id,s.entry_id,s.reviewed_at)) then sum(e.effective_scrap_kg) end scrap_kg,
 case when count(*) filter(where e.produced_weight_kg is null)=0 then sum(e.produced_weight_kg) end produced_kg,
 sum(e.effective_unfinished) wip_quantity from public.lean_scrap_events s join public.production_entries e on e.factory_id=s.factory_id and e.id=s.entry_id
 where s.factory_id=d.factory_id and s.downtime_id=d.id and s.approved_cause_id=d.approved_cause_id) associated on true
 where d.ended_at is not null and d.approved_cause_id is not null and d.approved_at is not null
 union all
 select s.factory_id,'scrap',coalesce(case when e.effective_scrap_kg=e.effective_startup_kg then e.lean_startup_id end,s.id),null::uuid,
 s.line_id,s.product_id,s.approved_cause_id,case when bool_and(s.time_precision='EXACT') then min(s.occurred_at) end,max(e.created_at),e.shift_id,
 0::numeric,0::numeric,e.unit,
 case when bool_and(private.production_scrap_review_current(s.factory_id,s.entry_id,s.reviewed_at)) then sum(e.effective_scrap_kg) end,
 case when bool_and(private.production_scrap_review_current(s.factory_id,s.entry_id,s.reviewed_at)) and count(*) filter(where e.produced_weight_kg is null)=0 then sum(e.produced_weight_kg) end,
 case when bool_and(private.production_scrap_review_current(s.factory_id,s.entry_id,s.reviewed_at)) then sum(e.effective_unfinished) end,
 string_agg(s.observation,E'\n'),s.preliminary_cause_id,string_agg(s.response,E'\n'),e.order_id,null::uuid,null::jsonb,'NOT_DOWNTIME',
 string_agg(s.engineering_note,E'\n'),max(s.reviewed_at),
 case when bool_and(s.time_precision='EXACT') then 'EXACT' else 'SHIFT_PERIOD' end,
 case when not bool_and(s.time_precision='EXACT') then min(case when s.time_precision='SHIFT_PERIOD' then e.effective_period_start else s.occurred_at end) end,
 case when not bool_and(s.time_precision='EXACT') then max(case when s.time_precision='SHIFT_PERIOD' then e.effective_period_end else s.occurred_at end) end,
 case when count(distinct e.effective_occurrence_key)=1 then min(e.effective_occurrence_key) end,
 max(e.created_at),2,bool_and(private.production_scrap_review_current(s.factory_id,s.entry_id,s.reviewed_at)),'CONTAINED',
 jsonb_agg(jsonb_build_object('observation_id',s.id,'entry_id',e.id,'precision',s.time_precision,'occurred_at',s.occurred_at,
 'observed_occurrence_key',s.occurrence_key,'observed_period_start',s.period_start,'observed_period_end',s.period_end,
 'effective_occurrence_key',e.effective_occurrence_key,'effective_period_start',e.effective_period_start,'effective_period_end',e.effective_period_end,
 'reviewed_at',s.reviewed_at,'reviewed_by',s.reviewed_by,'review_revision',s.revision,
 'current_review',private.production_scrap_review_current(s.factory_id,s.entry_id,s.reviewed_at)) order by s.id)
 from public.lean_scrap_events s join public.production_entries e on e.factory_id=s.factory_id and e.id=s.entry_id
 where s.downtime_id is null and s.approved_cause_id is not null and
 ((private.lean_scrap_assessment(s.factory_id,s.entry_id)->>'needs_review')::boolean or not private.production_scrap_review_current(s.factory_id,s.entry_id,s.reviewed_at))
 group by s.factory_id,coalesce(case when e.effective_scrap_kg=e.effective_startup_kg then e.lean_startup_id end,s.id),s.line_id,s.product_id,s.approved_cause_id,e.shift_id,e.unit,s.preliminary_cause_id,e.order_id;

-- One scope adapter for the existing Lean reader. Only selected scalar amounts
-- become unknown on a partial period; source identity and declared evidence stay.
create function private.lean_window_occurrences(f uuid,lo timestamptz,hi timestamptz) returns setof private.lean_occurrences
language sql stable security definer set search_path='' as $$
 select jsonb_populate_record(null::private.lean_occurrences,to_jsonb(o)||jsonb_build_object('allocation_status',scope.state,
 'scrap_kg',case when scope.state='CONTAINED' and o.review_current then o.scrap_kg end,
 'produced_kg',case when scope.state='CONTAINED' and o.review_current then o.produced_kg end,
 'wip_quantity',case when scope.state='CONTAINED' and o.review_current then o.wip_quantity end))
 from private.lean_occurrences o cross join lateral(select private.production_period_scope(o.time_precision,o.occurred_at,o.period_start,o.period_end,o.recorded_at,lo,hi) state)scope
 where o.factory_id=f and scope.state<>'OUTSIDE'
$$;
revoke all on function private.production_scrap_review_current(uuid,uuid,timestamptz),private.production_period_scope(text,timestamptz,timestamptz,timestamptz,timestamptz,timestamptz,timestamptz),private.lean_window_occurrences(uuid,timestamptz,timestamptz)
 from public,anon,authenticated;

-- Separately owner-approved local compatibility: only the existing initiative
-- baseline bounds/current Scrap review predicate change; all other command
-- authorization, retries, actions, verification and persistence stay verbatim.
create or replace function private.lean_command_before_m3c(f uuid,r uuid,op text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();saved private.lean_command_retries;result jsonb;target uuid;expected integer;
 action public.lean_actions;initiative public.lean_initiatives;problem public.lean_problem_settings;event public.lean_scrap_events;baseline_start timestamptz;baseline_end timestamptz;
 entry public.production_entries;job public.production_orders;allowed text[];manager boolean;
begin
 if actor is null then raise exception 'permission_denied' using errcode='42501';end if;
 perform private.require_permission(f,'factory','view');
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));
 perform private.require_permission(f,'factory','view');
 if r is null or p is null or jsonb_typeof(p)<>'object' then raise exception 'lean_invalid' using errcode='22023';end if;
 select * into saved from private.lean_command_retries where factory_id=f and id=r;
 if found then
  if saved.actor_id<>actor or saved.operation<>op or saved.payload<>p then raise exception 'lean_conflict' using errcode='40001';end if;
  return saved.result;
 end if;
 allowed:=case op
 when 'cause' then array['id','name','name_ar','parent_id']
 when 'standard' then array['id','line_id','product_id','running_percent','startup_kg','expected_revision','proposal_month']
 when 'template' then array['id','cause_id','title','name_ar','description','action_type','due_days','archived','expected_revision']
 when 'problem' then array['mechanism','machine_id','line_id','product_id','cause_id','monitor_only','threshold_percent','expected_revision']
 when 'initiative' then array['id','problem_id','product_id','title']
 when 'action' then array['id','initiative_id','title','description','action_type','owner_id','due_date','expected_revision']
 when 'progress' then array['id','status','due_date','note','expected_revision']
 when 'cancel_action' then array['id','reason','expected_revision']
 when 'scrap_observation' then array['id','entry_id','occurred_at','preliminary_cause_id','observation','response','downtime_id']
 when 'scrap_review' then array['id','approved_cause_id','note','expected_revision'] end;
 if allowed is null or exists(select 1 from jsonb_object_keys(p) key where not key=any(allowed)) then raise exception 'lean_invalid' using errcode='22023';end if;
 target:=(p->>'id')::uuid;expected:=coalesce((p->>'expected_revision')::integer,0);
 manager:=private.has_permission(f,'lean','edit');
 if op='standard' then perform private.require_permission(f,'lean_standards','edit');
 elsif op='scrap_observation' then perform private.require_permission(f,'orders','edit');
 elsif op='initiative' then perform private.require_permission(f,'lean','create');
 elsif op='problem' and not manager then
  perform private.require_permission(f,'lean','create');
  if expected<>0 or coalesce((p->>'monitor_only')::boolean,false) or coalesce((p->>'threshold_percent')::numeric,10)<>10 then raise exception 'permission_denied' using errcode='42501';end if;
 elsif op='progress' then perform private.require_permission(f,'lean','view');
 else perform private.require_permission(f,'lean','edit');end if;

 if op='cause' then
  if target is null or length(btrim(p->>'name')) not between 1 and 120 or length(coalesce(p->>'name_ar',''))>120 then raise exception 'lean_invalid' using errcode='22023';end if;
  if exists(select 1 from public.downtime_reasons where id=target and factory_id<>f) then raise exception 'permission_denied' using errcode='42501';end if;
  insert into public.downtime_reasons(id,factory_id,name,name_ar,parent_id) values(target,f,btrim(p->>'name'),coalesce(p->>'name_ar',''),(p->>'parent_id')::uuid)
  on conflict(id) do update set name=excluded.name,name_ar=excluded.name_ar,parent_id=excluded.parent_id;
 elsif op='standard' then
  if target is null then raise exception 'lean_invalid' using errcode='22023';end if;
  if exists(select 1 from public.lean_standards where factory_id=f and line_id=(p->>'line_id')::uuid and product_id=(p->>'product_id')::uuid and (id<>target or revision<>expected)) then raise exception 'lean_conflict' using errcode='40001';end if;
  if not exists(select 1 from public.lean_standards where id=target and factory_id=f) and expected<>0 then raise exception 'lean_conflict' using errcode='40001';end if;
  insert into public.lean_standards(id,factory_id,line_id,product_id,running_percent,startup_kg,created_by)
  values(target,f,(p->>'line_id')::uuid,(p->>'product_id')::uuid,(p->>'running_percent')::numeric,(p->>'startup_kg')::numeric,actor)
  on conflict(id) do update set running_percent=excluded.running_percent,startup_kg=excluded.startup_kg,revision=lean_standards.revision+1,created_by=actor,created_at=clock_timestamp()
  where lean_standards.factory_id=f and lean_standards.line_id=excluded.line_id and lean_standards.product_id=excluded.product_id and lean_standards.revision=expected;
  if not found then raise exception 'lean_conflict' using errcode='40001';end if;
  if p->>'proposal_month' is not null then
   update public.lean_standards st set approved_proposal_month=(p->>'proposal_month')::date,approved_observed_kg=(select avg(kg) from
    (select s.id,sum(e.effective_startup_kg) kg from public.lean_startups s join public.production_entries e on e.factory_id=f and e.lean_startup_id=s.id
    where s.factory_id=f and s.line_id=st.line_id and s.product_id=st.product_id and date_trunc('month',s.occurred_at at time zone (select timezone from public.factories where id=f))::date=(p->>'proposal_month')::date group by s.id)x) where id=target;
  end if;
 elsif op='template' then
  if target is null or (exists(select 1 from public.lean_action_templates where id=target) and not exists(select 1 from public.lean_action_templates where factory_id=f and id=target and revision=expected)) then raise exception 'lean_conflict' using errcode='40001';end if;
  insert into public.lean_action_templates(id,factory_id,cause_id,title,name_ar,description,action_type,due_days,archived,created_by)
  values(target,f,(p->>'cause_id')::uuid,p->>'title',coalesce(p->>'name_ar',''),coalesce(p->>'description',''),p->>'action_type',(p->>'due_days')::integer,coalesce((p->>'archived')::boolean,false),actor)
  on conflict(id) do update set cause_id=excluded.cause_id,title=excluded.title,name_ar=excluded.name_ar,description=excluded.description,action_type=excluded.action_type,due_days=excluded.due_days,archived=excluded.archived,revision=lean_action_templates.revision+1;
 elsif op='problem' then
  select * into problem from public.lean_problem_settings where factory_id=f and mechanism=p->>'mechanism' and cause_id=(p->>'cause_id')::uuid
  and machine_id is not distinct from (p->>'machine_id')::uuid and line_id is not distinct from (p->>'line_id')::uuid and product_id is not distinct from (p->>'product_id')::uuid;
  if found then
   if manager then
   if problem.revision<>expected then raise exception 'lean_conflict' using errcode='40001';end if;
   update public.lean_problem_settings set monitor_only=coalesce((p->>'monitor_only')::boolean,false),threshold_percent=coalesce((p->>'threshold_percent')::numeric,10),revision=revision+1 where id=problem.id;
   end if;
   target:=problem.id;
  else
   if expected<>0 then raise exception 'lean_conflict' using errcode='40001';end if;
   insert into public.lean_problem_settings(factory_id,mechanism,machine_id,line_id,product_id,cause_id,monitor_only,threshold_percent,created_by)
   values(f,p->>'mechanism',(p->>'machine_id')::uuid,(p->>'line_id')::uuid,(p->>'product_id')::uuid,(p->>'cause_id')::uuid,coalesce((p->>'monitor_only')::boolean,false),coalesce((p->>'threshold_percent')::numeric,10),actor) returning id into target;
  end if;
 elsif op='initiative' then
  select * into problem from public.lean_problem_settings where factory_id=f and id=(p->>'problem_id')::uuid;
  if not found or target is null or not exists(select 1 from public.products where factory_id=f and id=(p->>'product_id')::uuid) then raise exception 'lean_invalid' using errcode='22023';end if;
  if problem.product_id is not null and problem.product_id<>(p->>'product_id')::uuid then raise exception 'lean_comparison_product' using errcode='22023';end if;
  select min(case when o.time_precision='SHIFT_PERIOD' then o.period_start else o.occurred_at end),max(case when o.time_precision='SHIFT_PERIOD' then o.period_end else greatest(o.ended_at,o.occurred_at) end) into baseline_start,baseline_end from private.lean_occurrences o where o.factory_id=f and o.mechanism=problem.mechanism and o.cause_id=problem.cause_id
  and o.machine_id is not distinct from problem.machine_id and (problem.mechanism='downtime' or o.line_id=problem.line_id) and o.product_id=(p->>'product_id')::uuid and (o.mechanism<>'scrap' or o.review_current);
  if baseline_start is null or baseline_end<=baseline_start then raise exception 'lean_baseline_missing' using errcode='22023';end if;
  insert into public.lean_initiatives(id,factory_id,problem_id,product_id,title,baseline_from,baseline_to,created_by)
  values(target,f,problem.id,(p->>'product_id')::uuid,p->>'title',baseline_start,baseline_end,actor);
 elsif op in ('action','progress','cancel_action') then
  select * into action from public.lean_actions where factory_id=f and id=target;
  if exists(select 1 from public.lean_actions where id=target and factory_id<>f) then raise exception 'permission_denied' using errcode='42501';end if;
  if found and action.revision<>expected then raise exception 'lean_conflict' using errcode='40001';end if;
  select * into initiative from public.lean_initiatives where factory_id=f and id=coalesce(action.initiative_id,(p->>'initiative_id')::uuid);
  if not found or initiative.verified_at is not null then raise exception 'lean_closed' using errcode='22023';end if;
  if op='action' then
   if target is null or not exists(select 1 from public.memberships where factory_id=f and user_id=(p->>'owner_id')::uuid and status='approved') or p->>'due_date' is null then raise exception 'lean_invalid' using errcode='22023';end if;
   if action.id is not null and (action.initiative_id<>initiative.id or action.status='CANCELLED') then raise exception 'lean_closed' using errcode='22023';end if;
   insert into public.lean_actions(id,factory_id,initiative_id,title,description,action_type,owner_id,due_date,created_by)
   values(target,f,initiative.id,p->>'title',coalesce(p->>'description',''),p->>'action_type',(p->>'owner_id')::uuid,(p->>'due_date')::date,actor)
   on conflict(id) do update set title=excluded.title,description=excluded.description,action_type=excluded.action_type,owner_id=excluded.owner_id,due_date=excluded.due_date,revision=lean_actions.revision+1,updated_at=clock_timestamp();
  else
   if action.id is null then raise exception 'not_found' using errcode='P0002';end if;
   if op='cancel_action' then
   if p->>'reason' is null or length(btrim(p->>'reason')) not between 3 and 2000 then raise exception 'lean_reason_required' using errcode='22023';end if;
    update public.lean_actions set status='CANCELLED',cancellation_reason=p->>'reason',revision=revision+1,updated_at=clock_timestamp() where id=target;
   else
    if not manager and action.owner_id<>actor then raise exception 'permission_denied' using errcode='42501';end if;
    if action.status='CANCELLED' or p->>'status' not in ('OPEN','IN_PROGRESS','COMPLETED') or p->>'due_date' is null or length(coalesce(p->>'note',''))>2000 then raise exception 'lean_invalid' using errcode='22023';end if;
    update public.lean_actions set status=p->>'status',due_date=(p->>'due_date')::date,progress_note=coalesce(p->>'note',''),revision=revision+1,updated_at=clock_timestamp() where id=target;
   end if;
  end if;
  update public.lean_initiatives set completed_at=case when exists(select 1 from public.lean_actions where initiative_id=initiative.id) and
  not exists(select 1 from public.lean_actions where initiative_id=initiative.id and status not in ('COMPLETED','CANCELLED')) then coalesce(completed_at,statement_timestamp()) else null end,revision=revision+1 where id=initiative.id;
 elsif op='scrap_observation' then
  select * into entry from public.production_entries where factory_id=f and id=(p->>'entry_id')::uuid;
  select * into job from public.production_orders where factory_id=f and id=entry.order_id;
  if entry.id is null or entry.effective_scrap_kg is null or entry.line_id is null or target is null or (p->>'occurred_at')::timestamptz>clock_timestamp() or (p->>'occurred_at')::timestamptz<job.actual_start then raise exception 'lean_invalid' using errcode='22023';end if;
  if p->>'downtime_id' is not null and not exists(select 1 from public.downtime_events d where d.factory_id=f and d.id=(p->>'downtime_id')::uuid and d.line_id=entry.line_id and d.order_id=entry.order_id and
  (p->>'occurred_at')::timestamptz between d.started_at and coalesce(d.ended_at,statement_timestamp())) then raise exception 'lean_link_invalid' using errcode='22023';end if;
  insert into public.lean_scrap_events(id,factory_id,entry_id,line_id,product_id,downtime_id,occurred_at,preliminary_cause_id,observation,response,created_by)
  values(target,f,entry.id,entry.line_id,job.product_id,(p->>'downtime_id')::uuid,(p->>'occurred_at')::timestamptz,(p->>'preliminary_cause_id')::uuid,p->>'observation',p->>'response',actor);
 elsif op='scrap_review' then
  select * into event from public.lean_scrap_events where factory_id=f and id=target;
  if not found or event.revision<>expected or (p->>'approved_cause_id')::uuid is null or length(coalesce(p->>'note',''))>2000 then raise exception 'lean_conflict' using errcode='40001';end if;
  if event.downtime_id is not null and not exists(select 1 from public.downtime_events where factory_id=f and id=event.downtime_id and approved_cause_id=(p->>'approved_cause_id')::uuid) then raise exception 'lean_link_cause' using errcode='22023';end if;
  update public.lean_scrap_events set approved_cause_id=(p->>'approved_cause_id')::uuid,engineering_note=coalesce(p->>'note',''),reviewed_by=actor,reviewed_at=clock_timestamp(),revision=revision+1 where id=target;
 end if;
 result:=jsonb_build_object('id',target);
 insert into private.lean_command_retries(factory_id,id,actor_id,operation,payload,result) values(f,r,actor,op,p,result);
 return result;
end$$;

-- Existing Lean reader with shared scope integration.
create or replace function private.lean_read(f uuid,q jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare mode text:=coalesce(q->>'mode','problems');page integer:=coalesce((q->>'page')::integer,1);take integer:=100;
 result jsonb;problem public.lean_problem_settings;from_at timestamptz;to_at timestamptz;
begin
 if mode in ('recording_review','recording_context') then perform private.require_permission(f,'orders','view');else perform private.require_permission(f,'lean','view');end if;
 if q is null or jsonb_typeof(q)<>'object' or page not between 1 and 1000000 or exists(select 1 from jsonb_object_keys(q) k where k not in
 ('mode','page','from','to','line_id','machine_id','product_id','shift_id','cause_id','mechanism','problem_id','initiative_id','item_id','sort','direction','search','recurring','monitor_only','min_scrap','min_frequency')) then raise exception 'lean_invalid' using errcode='22023';end if;
 from_at:=coalesce((q->>'from')::timestamptz,statement_timestamp()-interval '30 days');to_at:=coalesce((q->>'to')::timestamptz,statement_timestamp());
 if to_at<from_at or to_at>statement_timestamp()+interval '1 minute' then raise exception 'lean_invalid' using errcode='22023';end if;
 if mode='recording_context' then
  result:=jsonb_build_object('causes',coalesce((select jsonb_agg(to_jsonb(x)) from (select id,name,name_ar from public.downtime_reasons where factory_id=f order by name,id limit take offset (page-1)*take)x),'[]'),
   'startups',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from public.lean_startups where factory_id=f and item_id=(q->>'item_id')::uuid order by occurred_at desc,id limit take offset (page-1)*take)x),'[]'));
 elsif mode='contexts' then
  with data as (select * from public.lean_runtime_contexts where factory_id=f and captured_at<=to_at and
   (captured_at>=from_at or captured_at=(select max(captured_at) from public.lean_runtime_contexts where factory_id=f and captured_at<from_at)))
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x) order by captured_at,id) from (select * from data order by captured_at,id limit take offset (page-1)*take)x),'[]'),'total',(select count(*) from data),'as_of',to_at) into result;
 elsif mode='entries' then
  with data as(select e.*,o.product_id,2 evidence_version,coalesce(e.time_precision,'UNKNOWN') production_precision,
 private.production_scrap_review_current(e.factory_id,e.id,e.scrap_reviewed_at) review_current,
 private.production_period_scope(coalesce(e.time_precision,'UNKNOWN'),null,e.effective_period_start,e.effective_period_end,e.created_at,from_at,to_at) allocation_status,
   case when e.attribution_version=1 then '[]'::jsonb else (select coalesce(jsonb_agg(c->>'id'),'[]') from jsonb_array_elements((select context->'centers' from public.lean_runtime_contexts where factory_id=f and captured_at<=e.created_at order by captured_at desc,id desc limit 1))c where c->>'line_id'=e.line_id::text) end machine_ids
   from private.production_reporting_entries e join public.production_orders o on o.factory_id=f and o.id=e.order_id where e.factory_id=f and private.production_period_scope(coalesce(e.time_precision,'UNKNOWN'),null,e.effective_period_start,e.effective_period_end,e.created_at,from_at,to_at)<>'OUTSIDE' and (q->>'product_id' is null or o.product_id=(q->>'product_id')::uuid))
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from data order by created_at,id limit take offset (page-1)*take)x),'[]'),'total',(select count(*) from data)) into result;
 elsif mode='analysis_occurrences' then
  with data as(select * from private.lean_window_occurrences(f,from_at,to_at) o where o.factory_id=f and
   (q->>'line_id' is null or o.line_id=(q->>'line_id')::uuid) and (q->>'machine_id' is null or o.machine_id=(q->>'machine_id')::uuid) and
   (q->>'product_id' is null or o.product_id=(q->>'product_id')::uuid) and (q->>'cause_id' is null or o.cause_id=(q->>'cause_id')::uuid) and
   (q->>'shift_id' is null or o.shift_id=(q->>'shift_id')::uuid))
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from data order by occurred_at,event_id limit take offset (page-1)*take)x),'[]'),'total',(select count(*) from data)) into result;
 elsif mode='library' then
  result:=jsonb_build_object(
   'causes',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from public.downtime_reasons where factory_id=f order by name,id limit take offset (page-1)*take)x),'[]'),
   'templates',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from public.lean_action_templates where factory_id=f order by title,id limit take offset (page-1)*take)x),'[]'),
   'standards',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from public.lean_standards where factory_id=f order by line_id,product_id limit take offset (page-1)*take)x),'[]'),
   'observed_startup',coalesce((select jsonb_agg(to_jsonb(x)) from (select s.line_id,s.product_id,date_trunc('month',s.occurred_at at time zone (select timezone from public.factories where id=f)) observed_month,count(*) startups,avg(e.mass) observed_kg
    from public.lean_startups s join lateral(select sum(effective_startup_kg) mass from public.production_entries where factory_id=f and lean_startup_id=s.id)e on true
    where s.factory_id=f group by s.line_id,s.product_id,date_trunc('month',s.occurred_at at time zone (select timezone from public.factories where id=f)) order by observed_month desc limit take offset (page-1)*take)x),'[]'),
   'people',coalesce((select jsonb_agg(to_jsonb(x)) from (select user_id,display_name from public.memberships where factory_id=f and status='approved' order by display_name limit take offset (page-1)*take)x),'[]'));
 elsif mode='pending' then
  perform private.require_permission(f,'lean','edit');
  with data as (select s.*,e.effective_scrap_kg,e.produced_weight_kg,e.shift_id,private.production_scrap_review_current(s.factory_id,s.entry_id,s.reviewed_at) review_current from public.lean_scrap_events s join public.production_entries e on e.factory_id=f and e.id=s.entry_id where s.factory_id=f and (s.reviewed_at is null or not private.production_scrap_review_current(s.factory_id,s.entry_id,s.reviewed_at)))
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from data order by coalesce(occurred_at,period_start,created_at) desc,id limit take offset (page-1)*take)x),'[]'),'total',(select count(*) from data)) into result;
 elsif mode='recording_review' then
  perform private.require_permission(f,'orders','view');
  with data as (select e.id,e.order_id,e.line_id,e.created_at,e.effective_scrap_kg,private.lean_scrap_assessment(f,e.id) assessment from public.production_entries e
   where e.factory_id=f and e.line_id is not null and not exists(select 1 from public.lean_scrap_events s where s.factory_id=f and s.entry_id=e.id)
   and (private.lean_scrap_assessment(f,e.id)->>'needs_review')::boolean)
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from data order by created_at desc,id limit take offset (page-1)*take)x),'[]'),'total',(select count(*) from data)) into result;
 elsif mode in ('detail','occurrences') then
 select * into problem from public.lean_problem_settings where factory_id=f and id=(q->>'problem_id')::uuid;
  if problem.id is null then
   problem.factory_id:=f;problem.mechanism:=q->>'mechanism';problem.machine_id:=(q->>'machine_id')::uuid;problem.line_id:=(q->>'line_id')::uuid;problem.product_id:=(q->>'product_id')::uuid;problem.cause_id:=(q->>'cause_id')::uuid;
   if not exists(select 1 from private.lean_occurrences o where o.factory_id=f and o.mechanism=problem.mechanism and o.machine_id is not distinct from problem.machine_id and o.cause_id=problem.cause_id and (problem.mechanism='downtime' or o.line_id=problem.line_id and o.product_id=problem.product_id)) then raise exception 'not_found' using errcode='P0002';end if;
  end if;
  with data as (select * from private.lean_window_occurrences(f,from_at,to_at) o where o.factory_id=f and o.mechanism=problem.mechanism and o.cause_id=problem.cause_id and o.machine_id is not distinct from problem.machine_id and
   (problem.mechanism='downtime' or o.line_id=problem.line_id and o.product_id=problem.product_id) and (q->>'product_id' is null or o.product_id=(q->>'product_id')::uuid or o.product_id is null)  )
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from data order by occurred_at,event_id limit take offset (page-1)*take)x),'[]'),'total',(select count(*) from data),'problem',to_jsonb(problem)) into result;
  if mode='detail' then
   result:=result||jsonb_build_object(
    'recurrence_watch',(select jsonb_build_object('verified_at',i.verified_at,'frequency',case when bool_and(o.review_current and private.production_period_scope(o.time_precision,o.occurred_at,o.period_start,o.period_end,o.recorded_at,i.verified_at,least(i.verified_at+interval '30 days',statement_timestamp()))='CONTAINED') then count(distinct o.event_id) end,'recurred',case when count(o.event_id)=0 then false when bool_and(o.review_current and private.production_period_scope(o.time_precision,o.occurred_at,o.period_start,o.period_end,o.recorded_at,i.verified_at,least(i.verified_at+interval '30 days',statement_timestamp()))='CONTAINED') then count(distinct o.event_id)>=2 end) from public.lean_initiatives i left join private.lean_occurrences o on o.factory_id=f and o.mechanism=problem.mechanism and o.cause_id=problem.cause_id and o.machine_id is not distinct from problem.machine_id and (problem.mechanism='downtime' or o.line_id=problem.line_id and o.product_id=problem.product_id) and private.production_period_scope(o.time_precision,o.occurred_at,o.period_start,o.period_end,o.recorded_at,i.verified_at,least(i.verified_at+interval '30 days',statement_timestamp()))<>'OUTSIDE' where i.id=(select id from public.lean_initiatives where factory_id=f and problem_id=problem.id and outcome='IMPROVED' and verified_at is not null order by verified_at desc,id desc limit 1) group by i.verified_at),
    'initiatives',coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('derived_status',case when x.verified_at is not null then 'VERIFIED' when x.completed_at is not null then 'AWAITING_VERIFICATION' when exists(select 1 from public.lean_actions where factory_id=f and initiative_id=x.id and status<>'OPEN') then 'IN_PROGRESS' else 'OPEN' end)) from
     (select * from public.lean_initiatives where factory_id=f and problem_id=problem.id and (q->>'initiative_id' is null or id=(q->>'initiative_id')::uuid) and (verified_at is null or id in(select id from public.lean_initiatives where factory_id=f and problem_id=problem.id and verified_at is not null order by created_at desc,id limit 25 offset (page-1)*25)))x),'[]'),
    'actions',coalesce((select jsonb_agg(to_jsonb(x)) from (select a.* from public.lean_actions a join public.lean_initiatives i on i.factory_id=f and i.id=a.initiative_id where a.factory_id=f and i.problem_id=problem.id order by a.created_at,a.id limit take offset (page-1)*take)x),'[]'),
    'previous_actions',coalesce((select jsonb_agg(to_jsonb(x)) from (select a.*,i.outcome,i.verified_at,p.machine_id,p.line_id from public.lean_actions a join public.lean_initiatives i on i.factory_id=f and i.id=a.initiative_id join public.lean_problem_settings p on p.factory_id=f and p.id=i.problem_id where a.factory_id=f and p.cause_id=problem.cause_id and i.verified_at is not null order by i.verified_at desc,a.id limit take offset (page-1)*take)x),'[]'),
    'comparisons',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from public.lean_saved_comparisons where factory_id=f and problem_id=problem.id order by created_at desc limit 25 offset (page-1)*25)x),'[]'),
    'history',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from public.audit_logs where factory_id=f and
     (entity_id=problem.id or entity_id in(select id from public.lean_initiatives where factory_id=f and problem_id=problem.id) or entity_id in(select a.id from public.lean_actions a join public.lean_initiatives i on i.factory_id=f and i.id=a.initiative_id where a.factory_id=f and i.problem_id=problem.id)) order by created_at desc,id limit 50 offset (page-1)*50)x),'[]'),
    'sales',case when private.has_permission(f,'sales_orders','view') then coalesce((select jsonb_agg(to_jsonb(x)) from (select so.id,so.code,so.requested_delivery,delivery.info->>'risk' risk,delivery.info->>'estimated_ready' estimated_ready,
      (select jsonb_object_agg(unit,quantity) from (select sl.unit,sum(a.quantity) quantity from public.sales_incoming_allocations a join public.sales_order_lines sl on sl.factory_id=f and sl.id=a.line_id
       where a.factory_id=f and sl.order_id=so.id and a.item_id in(select o.item_id from private.lean_occurrences o where o.factory_id=f and o.mechanism=problem.mechanism and o.machine_id is not distinct from problem.machine_id and o.cause_id=problem.cause_id and (problem.mechanism='downtime' or o.line_id=problem.line_id and o.product_id=problem.product_id)) group by sl.unit)u) affected_quantity
      from public.sales_orders so cross join lateral(select private.sales_order_detail(f,so.id) info)delivery
      where so.factory_id=f and exists(select 1 from public.sales_order_lines sl join public.sales_incoming_allocations a on a.factory_id=f and a.line_id=sl.id where sl.factory_id=f and sl.order_id=so.id and a.item_id in
       (select o.item_id from private.lean_occurrences o where o.factory_id=f and o.mechanism=problem.mechanism and o.machine_id is not distinct from problem.machine_id and o.cause_id=problem.cause_id and (problem.mechanism='downtime' or o.line_id=problem.line_id and o.product_id=problem.product_id)))
       order by so.created_at desc,so.id limit 25 offset (page-1)*25)x),'[]') else null end,
    'maintenance',case when private.has_permission(f,'maintenance','view') then coalesce((select jsonb_agg(to_jsonb(x)) from (select m.* from public.maintenance_requests m where m.factory_id=f and
     (m.work_center_id=problem.machine_id or m.line_id=problem.line_id) order by m.requested_at desc limit 25 offset (page-1)*25)x),'[]') else null end);
  end if;
 elsif mode in ('problems','problem_aggregates') then
  if to_at-from_at>interval '366 days' then raise exception 'lean_invalid' using errcode='22023';end if;
  if coalesce(q->>'sort','loss_minutes') not in ('loss_minutes','scrap_kg','frequency','loss_rate','cause') then raise exception 'lean_invalid' using errcode='22023';end if;
  with source as materialized(select * from private.lean_window_occurrences(f,from_at,to_at) o where o.factory_id=f
   and (q->>'line_id' is null or o.line_id=(q->>'line_id')::uuid) and (q->>'machine_id' is null or o.machine_id=(q->>'machine_id')::uuid)
   and (q->>'product_id' is null or o.product_id=(q->>'product_id')::uuid) and (q->>'shift_id' is null or o.shift_id=(q->>'shift_id')::uuid)
   and (q->>'cause_id' is null or o.cause_id=(q->>'cause_id')::uuid) and (q->>'mechanism' is null or o.mechanism=q->>'mechanism')),
  customer_context as materialized(select so.id,private.sales_order_detail(f,so.id)->>'risk' risk from public.sales_orders so where so.factory_id=f and private.has_permission(f,'sales_orders','view')),
  grouped as (select mechanism,machine_id,case when mechanism='scrap' then line_id end line_id,case when mechanism='scrap' then product_id end product_id,cause_id,
   case when bool_and(allocation_status='CONTAINED' and review_current) then count(distinct event_id) end frequency,sum(loss_minutes) loss_minutes,count(*) filter(where loss_minutes is null) missing_loss,
   case when count(*) filter(where scrap_kg is null)=0 then sum(scrap_kg) end scrap_kg,count(*) filter(where scrap_kg is null) missing_scrap,
   case when count(*) filter(where produced_kg is null)=0 and sum(produced_kg)>0 then 100*sum(scrap_kg)/sum(produced_kg) end scrap_rate,
   array_agg(distinct shift_id) shifts,array_agg(distinct product_id) products,array_agg(distinct line_id) lines,
   min(occurred_at) first_at,max(ended_at) last_at,
   jsonb_build_object('piece',sum(lost_output) filter(where output_unit='piece'),'meter',sum(lost_output) filter(where output_unit='meter'),'kg',sum(lost_output) filter(where output_unit='kg')) lost_output_by_unit,
   jsonb_build_object('piece',sum(wip_quantity) filter(where output_unit='piece'),'meter',sum(wip_quantity) filter(where output_unit='meter'),'kg',sum(wip_quantity) filter(where output_unit='kg')) wip_by_unit
   from source group by mechanism,machine_id,case when mechanism='scrap' then line_id end,case when mechanism='scrap' then product_id end,cause_id),
  data as materialized(select g.*,c.name cause,c.name_ar cause_ar,p.id problem_id,coalesce(p.monitor_only,false) monitor_only,coalesce(p.threshold_percent,10) threshold_percent,coalesce(p.revision,0) revision,
   case when private.has_permission(f,'sales_orders','view') then (select coalesce(bool_or(sc.risk in ('late','at_risk')),false) from customer_context sc join public.sales_order_lines sl on sl.factory_id=f and sl.order_id=sc.id join public.sales_incoming_allocations a on a.factory_id=f and a.line_id=sl.id join source o on o.item_id=a.item_id and o.mechanism=g.mechanism and o.machine_id is not distinct from g.machine_id and o.cause_id=g.cause_id and (g.mechanism='downtime' or o.line_id=g.line_id and o.product_id=g.product_id)) end customer_risk,
   (select to_jsonb(i) from public.lean_initiatives i where i.factory_id=f and i.problem_id=p.id order by i.created_at desc limit 1) initiative
   from grouped g join public.downtime_reasons c on c.factory_id=f and c.id=g.cause_id left join public.lean_problem_settings p on p.factory_id=f and p.mechanism=g.mechanism and p.cause_id=g.cause_id and p.machine_id is not distinct from g.machine_id and p.line_id is not distinct from g.line_id and p.product_id is not distinct from g.product_id
   where (q->>'search' is null or c.name ilike '%'||(q->>'search')||'%' or c.name_ar ilike '%'||(q->>'search')||'%') and
   (q->>'recurring' is null or g.frequency>=2) and (q->>'monitor_only' is null or coalesce(p.monitor_only,false)=(q->>'monitor_only')::boolean) and (q->>'min_frequency' is null or g.frequency>=(q->>'min_frequency')::numeric) and coalesce(g.scrap_kg,0)>=coalesce((q->>'min_scrap')::numeric,0))
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x)) from (select data.* from data order by
   case when q->>'sort'='scrap_kg' then scrap_kg when q->>'sort'='frequency' then frequency else loss_minutes end desc nulls last,cause,machine_id,line_id,product_id limit case when mode='problems' then 25 else 100 end offset (page-1)*case when mode='problems' then 25 else 100 end)x),'[]'),
   'total',(select count(*) from data),'summary',(select jsonb_build_object('loss_minutes',sum(loss_minutes),'missing_loss',sum(missing_loss),'recurring',count(*) filter(where frequency>=2),'scrap_kg',case when count(*) filter(where scrap_kg is null)=0 then sum(scrap_kg) end) from data),
   'open_initiatives',(select count(*) from public.lean_initiatives where factory_id=f and verified_at is null),
   'overdue_actions',(select count(*) from public.lean_actions where factory_id=f and status not in ('COMPLETED','CANCELLED') and due_date<current_date),
   'sales_at_risk',case when private.has_permission(f,'sales_orders','view') then (select count(*) from customer_context where risk in ('late','at_risk')) end) into result;
 else raise exception 'lean_invalid' using errcode='22023';end if;
 return result||jsonb_build_object('evidence_version',2,'time_basis','production','page',page,'page_size',case when mode='problems' then 25 else take end,
 'source_revision',(select revision from private.lean_source_state where factory_id=f));
end$$;


-- Existing V3 reporting response adds a review-current fact; prior keys retained.
create or replace function private.production_reporting_history(f uuid,q jsonb) returns jsonb
language plpgsql stable security definer set search_path='' set timezone='UTC' as $$
declare basis text:=coalesce(q->>'time_basis','recorded');mode text:=coalesce(q->>'mode','entries');
 zone text;a timestamptz;b timestamptz;take integer:=coalesce((q->>'page_size')::integer,50);
 rev bigint;fingerprint text;cursor jsonb:=q->'cursor';after_key text;result jsonb;lean boolean;
begin
 perform private.require_permission(f,'orders','view');
 if q is null or jsonb_typeof(q)<>'object' or octet_length(q::text)>12000 or q->>'reporting_version' is distinct from '3'
 or basis not in ('recorded','production') or mode not in ('entries','summary','corrections') or take not between 1 and 100
 or exists(select 1 from jsonb_object_keys(q) k where k not in ('reporting_version','time_basis','mode','from','to','from_at','to_at','product','line','entry','occurrence','page_size','cursor'))
 or (q ? 'from' and q ? 'from_at') or (q ? 'to' and q ? 'to_at')
 or ((q ?| array['from','to']) and (q ?| array['from_at','to_at']))
 then raise exception 'reporting_invalid' using errcode='22023';end if;
 if mode='corrections' and not(q ? 'entry') then raise exception 'reporting_entry_required' using errcode='22023';end if;
 -- Cast all IDs before the query, so malformed inputs never become empty results.
 perform (q->>'product')::uuid,(q->>'line')::uuid,(q->>'entry')::uuid;
 if q ? 'occurrence' and coalesce(q->>'occurrence','') !~ '^[0-9a-f]{64}$' then raise exception 'reporting_invalid' using errcode='22023';end if;
 select timezone into zone from public.factories where id=f;
 if (q ? 'from_at' and coalesce(q->>'from_at','') !~ '(Z|[+-][0-9]{2}:[0-9]{2})$')
 or (q ? 'to_at' and coalesce(q->>'to_at','') !~ '(Z|[+-][0-9]{2}:[0-9]{2})$') then raise exception 'reporting_invalid' using errcode='22023';end if;
 a:=coalesce((q->>'from_at')::timestamptz,(q->>'from')::date::timestamp at time zone zone,(cursor->>'from_at')::timestamptz,statement_timestamp()-interval '30 days');
 b:=coalesce((q->>'to_at')::timestamptz,((q->>'to')::date+1)::timestamp at time zone zone,(cursor->>'to_at')::timestamptz,statement_timestamp());
 if not isfinite(a) or not isfinite(b) or b<=a or b-a>interval '366 days' then raise exception 'reporting_range' using errcode='22023';end if;
 select coalesce(revision,0) into rev from private.lean_source_state where factory_id=f;rev:=coalesce(rev,0);
 fingerprint:=encode(sha256(convert_to(jsonb_build_array(1,f,q-'cursor',a,b)::text,'UTF8')),'hex');
 if cursor is not null and cursor<>'null'::jsonb then
  if jsonb_typeof(cursor)<>'object' or octet_length(cursor::text)>3000
   or not(cursor ?& array['version','factory','query_hash','source_revision','after','from_at','to_at'])
   or (select count(*) from jsonb_object_keys(cursor))<>7 or cursor->>'version' is distinct from '1'
   or cursor->>'factory' is distinct from f::text or cursor->>'query_hash' is distinct from fingerprint
   or cursor->>'source_revision' is distinct from rev::text or coalesce(cursor->>'after','')='' or length(cursor->>'after')>1000
  then raise exception 'reporting_stale_cursor' using errcode='40001';end if;
  after_key:=cursor->>'after';
 end if;
 lean:=private.has_permission(f,'lean','view');
 with selected as materialized(
  select e.*,
   (basis='recorded' or (e.effective_occurrence_key is not null and ((q ? 'from' or q ? 'to') or (e.effective_period_start>=a and e.effective_period_end<=b)))) allocated,
   to_char(e.created_at,'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')||':'||e.id::text entry_key
  from private.production_reporting_entries e where e.factory_id=f
   and (not(q ? 'product') or e.product_id=(q->>'product')::uuid)
   and (not(q ? 'line') or e.line_id=(q->>'line')::uuid)
   and (not(q ? 'entry') or e.id=(q->>'entry')::uuid)
   and (not(q ? 'occurrence') or e.effective_occurrence_key=q->>'occurrence')
   and case when basis='recorded' or e.effective_occurrence_key is null then e.created_at>=a and e.created_at<b
    when q ? 'from' or q ? 'to' then
     (not(q ? 'from') or (e.effective_occurrence->>'business_date')::date>=(q->>'from')::date)
     and (not(q ? 'to') or (e.effective_occurrence->>'business_date')::date<=(q->>'to')::date)
    else (e.effective_period_start<b and e.effective_period_end>a)
     or (e.effective_period_start=e.effective_period_end and e.effective_period_start>=a and e.effective_period_start<b) end
 ), entry_rows as (
  select entry_key row_key,jsonb_build_object('id',id,'factory_id',factory_id,'request_id',production_request_id,'request_code',request_code,
   'item_id',order_id,'item_code',item_code,'product_id',product_id,'product_code',product_code,'product_name',product_name,'product_name_ar',product_name_ar,
   'line_id',line_id,'line_name',line_name,'line_name_ar',line_name_ar,'work_center_id',work_center_id,'unit',unit,
   'recorded_at',created_at,'recorded_by',created_by,'submitter_name',submitter_name,'technician_id',technician_id,'technician_name',technician_name,
   'recording_kind',recording_kind,'execution_key',execution_key,
   'execution_start',execution_started_at,'execution_finish',execution_finished_at,'execution_evidence',case when attribution_version=1 then 'PROTECTED_PLAN_EXECUTION' else 'UNKNOWN' end,
   'current_item_status',current_item_status,'current_execution_start',current_execution_start,'current_execution_finish',current_execution_finish,
   'original_occurrence',original_occurrence,'effective_occurrence',effective_occurrence,
   'original_period',jsonb_build_object('start',original_period_start,'end',original_period_end),
   'effective_period',jsonb_build_object('start',effective_period_start,'end',effective_period_end),
   'time_precision',coalesce(time_precision,'UNKNOWN'),'allocation_known',allocated,'weight_basis',coalesce(weight_basis,'UNKNOWN'),
   'standard_basis',coalesce(standard_basis,'UNKNOWN'),'weight_kg_per_unit',weight_kg_per_unit::text,'shift_quantity_confirmed',attribution_declaration)
   ||jsonb_build_object('original_good',good_quantity::text,'good',effective_good::text,'accepted_good',accepted_good::text,'quality_rejected',quality_rejected::text,
   'original_scrap_kg',original_scrap_kg::text,'scrap_kg',effective_scrap_kg::text,'original_discarded_quantity',scrap_quantity::text,'discarded_quantity',effective_scrap::text,
   'original_wip',unfinished_quantity::text,'wip',effective_unfinished::text,'produced_weight_kg',produced_weight_kg::text,
   'scrap_rate',case when allocated and produced_weight_kg>0 and weight_basis in ('RECORDING_CONFIG','VERIFIED_HISTORICAL') then (100*effective_scrap_kg/produced_weight_kg)::text end,
   'scrap_rate_basis',coalesce(weight_basis,'UNKNOWN'),
   'source_id',(select id from public.finished_goods_sources s where s.factory_id=f and s.entry_id=selected.id),
   'input_lot_id',input_lot_id,'observation',jsonb_build_object('id',observation_id,'status',scrap_review_status,'precision',observation_precision,'review_current',private.production_scrap_review_current(f,id,scrap_reviewed_at),
    'occurred_at',observation_at,'occurrence_key',observation_occurrence_key,'period_start',observation_period_start,'period_end',observation_period_end),
   'lean_evidence',case when lean then jsonb_build_object('version',2,'time_basis',basis,'reviewed_scrap_kg',reviewed_scrap_kg::text,
    'allocation_known',allocated,'weight_basis',coalesce(weight_basis,'UNKNOWN'),'comparison_status','NOT_CALCULATED') end,
   'correction_count',(select count(*) from public.production_entry_corrections c where c.factory_id=f and c.entry_id=selected.id)) body
  from selected where mode='entries'
 ), groups as (
  select jsonb_build_array(effective_occurrence_key,product_id,line_id,unit)::text row_key,
   jsonb_build_object('occurrence_key',effective_occurrence_key,'occurrence',effective_occurrence,'product_id',product_id,
   'line_id',line_id,'unit',unit,'records',count(*),'attribution_complete',bool_and(effective_occurrence_key is not null),
   'allocation_complete',bool_and(allocated),'unit_known',bool_and(coalesce(unit in ('meter','piece','kg'),false)),
   'good',case when bool_and(allocated) and bool_and(coalesce(unit in ('meter','piece','kg'),false)) then sum(effective_good)::text end,
   'accepted_good',case when bool_and(allocated) and bool_and(coalesce(unit in ('meter','piece','kg'),false)) then sum(accepted_good)::text end,
   'declared_good',case when bool_and(coalesce(unit in ('meter','piece','kg'),false)) then sum(effective_good)::text end,
   'unallocated_good',case when bool_and(coalesce(unit in ('meter','piece','kg'),false)) then coalesce(sum(effective_good) filter(where not allocated),0)::text end,
   'declared_scrap_kg',sum(effective_scrap_kg)::text,'unallocated_scrap_kg',coalesce(sum(effective_scrap_kg) filter(where not allocated),0)::text,
   'scrap_kg',case when bool_and(allocated) and count(*) filter(where effective_scrap_kg is null)=0 then sum(effective_scrap_kg)::text end,
   'unknown_scrap_records',count(*) filter(where effective_scrap_kg is null),'unknown_attribution_records',count(*) filter(where effective_occurrence_key is null),
   'wip',case when bool_and(coalesce(unit in ('meter','piece','kg'),false)) then sum(effective_unfinished)::text end,'reviewed_scrap_kg',case when lean and bool_and(allocated) then sum(reviewed_scrap_kg)::text end,
   'scrap_rate_basis',case when count(distinct coalesce(weight_basis,'UNKNOWN'))=1 then min(coalesce(weight_basis,'UNKNOWN')) else 'MIXED' end,
   'scrap_rate',case when bool_and(allocated) and count(*) filter(where produced_weight_kg is null or effective_scrap_kg is null or coalesce(weight_basis,'UNKNOWN') not in ('RECORDING_CONFIG','VERIFIED_HISTORICAL'))=0 and sum(produced_weight_kg)>0
    then (100*sum(effective_scrap_kg)/sum(produced_weight_kg))::text end) body
  from selected where mode='summary' group by effective_occurrence_key,effective_occurrence,product_id,line_id,unit
 ), audits as (
  select to_char(c.created_at,'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')||':'||c.id::text row_key,to_jsonb(c) body
  from public.production_entry_corrections c where mode='corrections' and c.factory_id=f and c.entry_id=(q->>'entry')::uuid
  and exists(select 1 from selected s where s.id=c.entry_id)
 ), all_rows as materialized(select entry_key row_key,null::jsonb body from selected where mode='entries' union all select * from groups union all select * from audits),
 remaining as (select * from all_rows where after_key is null or row_key>after_key),
 paged as materialized(select * from remaining order by row_key limit take+1),
 visible as (select * from paged order by row_key limit take),
 output_rows as (select v.row_key,e.body from visible v join entry_rows e using(row_key) where mode='entries'
  union all select row_key,body from visible where mode<>'entries')
 select jsonb_build_object('contract_version',3,'evidence_contract_version',2,'factory_id',f,'mode',mode,'time_basis',basis,
  'from_at',a,'to_at',b,'unknown_scope','RECORDED_WINDOW','source_revision',rev,
  'total',(select count(*) from all_rows),'page_size',take,'complete',(select count(*)<=take from paged),
  'attribution_complete',coalesce((select bool_and(effective_occurrence_key is not null) from selected),true),
  'allocation_complete',coalesce((select bool_and(allocated) from selected),true),
  'unknown_attribution_records',(select count(*) from selected where effective_occurrence_key is null),
  'rows',coalesce((select jsonb_agg(body order by row_key) from output_rows),'[]'),
  'next_cursor',case when (select count(*)>take from paged) then jsonb_build_object('version',1,'factory',f,'query_hash',fingerprint,
    'source_revision',rev,'after',(select max(row_key) from visible),'from_at',a,'to_at',b) end) into result;
 return result;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range
 then raise exception 'reporting_invalid' using errcode='22023';
end$$;

-- Quality remains its existing source/accepted/standards reader. Add provenance
-- on its bounded board page only; do not expose Lean review to Quality-only users.
alter function public.quality_read(uuid,jsonb) set schema private;
alter function private.quality_read(uuid,jsonb) rename to quality_read_before_m3c;
revoke all on function private.quality_read_before_m3c(uuid,jsonb) from public,anon,authenticated;
create function public.quality_read(factory uuid,query jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;begin
 result:=private.quality_read_before_m3c(factory,query);
 if coalesce(query->>'mode','board')='board' then
  select result||jsonb_build_object('rows',coalesce(jsonb_agg(row.value||jsonb_build_object(
   'production_attribution',jsonb_build_object('version',3,'recorded_at',e.created_at,'precision',coalesce(e.time_precision,'UNKNOWN'),
    'original_occurrence',e.original_occurrence,'effective_occurrence',e.effective_occurrence,
    'period_start',e.effective_period_start,'period_end',e.effective_period_end),
   'scrap_evidence',case when private.has_permission(factory,'lean','view') then jsonb_build_object('version',2,'observation_id',e.observation_id,
    'reviewed_at',e.scrap_reviewed_at,'review_current',private.production_scrap_review_current(factory,e.id,e.scrap_reviewed_at),
    'status',case when e.observation_id is null then 'UNOBSERVED' when e.scrap_reviewed_at is null then 'PENDING'
      when private.production_scrap_review_current(factory,e.id,e.scrap_reviewed_at) then 'REVIEWED' else 'EVIDENCE_CHANGED_AFTER_REVIEW' end,
    'reviewed_scrap_kg',e.reviewed_scrap_kg::text) end) order by row.ordinality),'[]')) into result
  from jsonb_array_elements(result->'rows') with ordinality row(value,ordinality)
  join private.production_reporting_entries e on e.factory_id=factory and e.id=(row.value->>'id')::uuid;
 end if;
 return result;
end$$;
revoke all on function public.quality_read(uuid,jsonb) from public,anon;
grant execute on function public.quality_read(uuid,jsonb) to authenticated;
-- No schema-readiness or activation update: later acceptance/UI remain pending.
commit;
