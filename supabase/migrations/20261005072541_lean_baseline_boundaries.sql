-- Preserve the final occurrence in baseline bounds; create-only grants can materialize default identities without managing settings.
create or replace function private.lean_command(f uuid,r uuid,op text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
  select min(o.occurred_at),max(greatest(o.ended_at,o.occurred_at)) into baseline_start,baseline_end from private.lean_occurrences o where o.factory_id=f and o.mechanism=problem.mechanism and o.cause_id=problem.cause_id
  and o.machine_id is not distinct from problem.machine_id and (problem.mechanism='downtime' or o.line_id=problem.line_id) and o.product_id=(p->>'product_id')::uuid;
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
