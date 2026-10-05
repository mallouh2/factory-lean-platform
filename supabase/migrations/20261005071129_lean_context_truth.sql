-- Preserve operator observations and qualified review separately; reuse read-only Sales truth once per page.
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
 case when a.actual_loss_minutes is not null then 'ACTUAL' when estimate.id is not null then 'SAVED_ESTIMATE' else 'MISSING' end loss_source,d.engineering_note approved_note,d.approved_at reviewed_at
 from public.downtime_events d left join public.production_orders o on o.factory_id=d.factory_id and o.id=d.order_id
 left join public.production_loss_estimates estimate on estimate.factory_id=d.factory_id and estimate.event_id=d.id
 left join public.production_loss_actuals a on a.factory_id=d.factory_id and a.event_id=d.id
 left join lateral(select count(*) entries,sum(e.effective_scrap_kg) scrap_kg,
 case when count(*) filter(where e.produced_weight_kg is null)=0 then sum(e.produced_weight_kg) end produced_kg,
 sum(e.effective_unfinished) wip_quantity from public.lean_scrap_events s join public.production_entries e on e.factory_id=s.factory_id and e.id=s.entry_id
 where s.factory_id=d.factory_id and s.downtime_id=d.id and s.approved_cause_id=d.approved_cause_id) associated on true
 where d.ended_at is not null and d.approved_cause_id is not null and d.approved_at is not null
 union all
 select s.factory_id,'scrap',coalesce(case when e.effective_scrap_kg=e.effective_startup_kg then e.lean_startup_id end,s.id),null::uuid,
 s.line_id,s.product_id,s.approved_cause_id,min(s.occurred_at),max(e.created_at),e.shift_id,
 0::numeric,0::numeric,e.unit,sum(e.effective_scrap_kg),
 case when count(*) filter(where e.produced_weight_kg is null)=0 then sum(e.produced_weight_kg) end,
 sum(e.effective_unfinished),string_agg(s.observation,E'\n'),s.preliminary_cause_id,string_agg(s.response,E'\n'),e.order_id,null::uuid,null::jsonb,'NOT_DOWNTIME',string_agg(s.engineering_note,E'\n'),max(s.reviewed_at)
 from public.lean_scrap_events s join public.production_entries e on e.factory_id=s.factory_id and e.id=s.entry_id
 where s.downtime_id is null and s.approved_cause_id is not null and (private.lean_scrap_assessment(s.factory_id,s.entry_id)->>'needs_review')::boolean
 group by s.factory_id,coalesce(case when e.effective_scrap_kg=e.effective_startup_kg then e.lean_startup_id end,s.id),s.line_id,s.product_id,s.approved_cause_id,e.shift_id,e.unit,s.preliminary_cause_id,e.order_id;

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
  with data as(select e.*,o.product_id,
   (select coalesce(jsonb_agg(c->>'id'),'[]') from jsonb_array_elements((select context->'centers' from public.lean_runtime_contexts where factory_id=f and captured_at<=e.created_at order by captured_at desc,id desc limit 1))c where c->>'line_id'=e.line_id::text) machine_ids
   from public.production_entries e join public.production_orders o on o.factory_id=f and o.id=e.order_id where e.factory_id=f and e.created_at>=from_at and e.created_at<to_at and (q->>'product_id' is null or o.product_id=(q->>'product_id')::uuid))
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from data order by created_at,id limit take offset (page-1)*take)x),'[]'),'total',(select count(*) from data)) into result;
 elsif mode='analysis_occurrences' then
  with data as(select * from private.lean_occurrences o where o.factory_id=f and o.occurred_at>=from_at and o.occurred_at<to_at and
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
  with data as (select s.*,e.effective_scrap_kg,e.produced_weight_kg,e.shift_id from public.lean_scrap_events s join public.production_entries e on e.factory_id=f and e.id=s.entry_id where s.factory_id=f and s.reviewed_at is null)
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from data order by occurred_at desc,id limit take offset (page-1)*take)x),'[]'),'total',(select count(*) from data)) into result;
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
  with data as (select * from private.lean_occurrences o where o.factory_id=f and o.mechanism=problem.mechanism and o.cause_id=problem.cause_id and o.machine_id is not distinct from problem.machine_id and
   (problem.mechanism='downtime' or o.line_id=problem.line_id and o.product_id=problem.product_id) and (q->>'product_id' is null or o.product_id=(q->>'product_id')::uuid or o.product_id is null) and o.occurred_at>=from_at and o.occurred_at<to_at)
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from data order by occurred_at,event_id limit take offset (page-1)*take)x),'[]'),'total',(select count(*) from data),'problem',to_jsonb(problem)) into result;
  if mode='detail' then
   result:=result||jsonb_build_object(
    'recurrence_watch',(select jsonb_build_object('verified_at',i.verified_at,'frequency',count(distinct o.event_id),'recurred',count(distinct o.event_id)>=2) from public.lean_initiatives i left join private.lean_occurrences o on o.factory_id=f and o.mechanism=problem.mechanism and o.cause_id=problem.cause_id and o.machine_id is not distinct from problem.machine_id and (problem.mechanism='downtime' or o.line_id=problem.line_id and o.product_id=problem.product_id) and o.occurred_at>i.verified_at and o.occurred_at<=least(i.verified_at+interval '30 days',statement_timestamp()) where i.id=(select id from public.lean_initiatives where factory_id=f and problem_id=problem.id and outcome='IMPROVED' and verified_at is not null order by verified_at desc,id desc limit 1) group by i.verified_at),
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
  with source as materialized(select * from private.lean_occurrences o where o.factory_id=f and o.occurred_at>=from_at and o.occurred_at<to_at
   and (q->>'line_id' is null or o.line_id=(q->>'line_id')::uuid) and (q->>'machine_id' is null or o.machine_id=(q->>'machine_id')::uuid)
   and (q->>'product_id' is null or o.product_id=(q->>'product_id')::uuid) and (q->>'shift_id' is null or o.shift_id=(q->>'shift_id')::uuid)
   and (q->>'cause_id' is null or o.cause_id=(q->>'cause_id')::uuid) and (q->>'mechanism' is null or o.mechanism=q->>'mechanism')),
  customer_context as materialized(select so.id,private.sales_order_detail(f,so.id)->>'risk' risk from public.sales_orders so where so.factory_id=f and private.has_permission(f,'sales_orders','view')),
  grouped as (select mechanism,machine_id,case when mechanism='scrap' then line_id end line_id,case when mechanism='scrap' then product_id end product_id,cause_id,
   count(distinct event_id) frequency,sum(loss_minutes) loss_minutes,count(*) filter(where loss_minutes is null) missing_loss,
   sum(scrap_kg) scrap_kg,count(*) filter(where scrap_kg is null) missing_scrap,
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
   (q->>'recurring' is null or g.frequency>=2) and (q->>'monitor_only' is null or coalesce(p.monitor_only,false)=(q->>'monitor_only')::boolean) and g.frequency>=coalesce((q->>'min_frequency')::numeric,0) and coalesce(g.scrap_kg,0)>=coalesce((q->>'min_scrap')::numeric,0))
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x)) from (select data.* from data order by
   case when q->>'sort'='scrap_kg' then scrap_kg when q->>'sort'='frequency' then frequency else loss_minutes end desc nulls last,cause,machine_id,line_id,product_id limit case when mode='problems' then 25 else 100 end offset (page-1)*case when mode='problems' then 25 else 100 end)x),'[]'),
   'total',(select count(*) from data),'summary',(select jsonb_build_object('loss_minutes',sum(loss_minutes),'missing_loss',sum(missing_loss),'recurring',count(*) filter(where frequency>=2),'scrap_kg',sum(scrap_kg)) from data),
   'open_initiatives',(select count(*) from public.lean_initiatives where factory_id=f and verified_at is null),
   'overdue_actions',(select count(*) from public.lean_actions where factory_id=f and status not in ('COMPLETED','CANCELLED') and due_date<current_date),
   'sales_at_risk',case when private.has_permission(f,'sales_orders','view') then (select count(*) from customer_context where risk in ('late','at_risk')) end) into result;
 else raise exception 'lean_invalid' using errcode='22023';end if;
 return result||jsonb_build_object('page',page,'page_size',case when mode='problems' then 25 else take end,
 'source_revision',(select revision from private.lean_source_state where factory_id=f));
end$$;

create trigger lean_source_changed after insert or update or delete on public.lean_problem_settings for each row execute function private.lean_source_changed();
create trigger lean_source_changed after insert or update or delete on public.downtime_reasons for each row execute function private.lean_source_changed();
