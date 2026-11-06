-- Local reader phase. No activation update or protected command-signature change.
create function private.maintenance_occupancy(f uuid,l uuid,p uuid,w uuid,
 skip_schedule uuid,skip_item uuid,with_production boolean,evaluated timestamptz,
 range_start timestamptz default '-infinity',range_end timestamptz default 'infinity',record_limit integer default null)
 returns table(kind text,id uuid,starts timestamptz,ends timestamptz,state text,unknown boolean,sort_at timestamptz)
 language sql stable security definer set search_path='' as $$
 with scoped as (
 select 'MAINTENANCE'::text kind,s.id,least(s.planned_start,coalesce(s.hold_started_at,s.planned_start)) starts,
 case when s.hold_started_at is not null or s.state='INVALIDATED' or s.planned_end<=evaluated then 'infinity'::timestamptz else s.planned_end end ends,
 s.state,false unknown,s.planned_start sort_at from public.maintenance_schedules s
 where s.factory_id=f and s.id is distinct from skip_schedule and s.state in ('CONFIRMED','INVALIDATED')
 and exists(select 1 from public.maintenance_schedule_resources r left join public.work_centers m on m.factory_id=r.factory_id and m.id=r.machine_id
 where r.factory_id=f and r.schedule_id=s.id and
 ((l is not null and (r.line_id=l or m.line_id=l)) or (w is not null and r.machine_id=w)
 or (p is not null and r.machine_id in(select rs.work_center_id from public.production_routing_steps rs where rs.factory_id=f and rs.product_id=p and rs.kind='work_center'))
 or (l is not null and r.machine_id in(select t.alternative_id from public.production_transfers t join public.production_orders o on o.factory_id=t.factory_id and o.id=t.order_id where t.factory_id=f and t.ended_at is null and o.line_id=l))))
 union all
 select 'PRODUCTION',o.id,
 case when o.status='active' or o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time then '-infinity'::timestamptz else o.start_time end,
 case when o.status='active' or o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time then 'infinity'::timestamptz else o.expected_finish end,
 o.status,(o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time),o.start_time
 from public.production_orders o where with_production and o.factory_id=f and o.id is distinct from skip_item and o.status in ('planned','active')
 and ((l is not null and o.line_id=l) or (w is not null and
 (o.id in(select c.order_id from public.work_centers c where c.factory_id=f and c.id=w)
 or o.product_id in(select rs.product_id from public.production_routing_steps rs where rs.factory_id=f and rs.work_center_id=w and rs.kind='work_center')))))
 select * from scoped where starts<range_end and ends>range_start order by kind,id limit record_limit;
$$;

-- Existing callers retain first-maintenance-before-production precedence and exact reason keys.
create or replace function private.maintenance_capacity_conflict(f uuid,l uuid,p uuid,w uuid,starts timestamptz,ends timestamptz,
 skip_schedule uuid default null,skip_item uuid default null,with_production boolean default true)
 returns jsonb language plpgsql stable security definer set search_path='' as $$
declare issue record;begin
 if starts is null or ends is null or ends<=starts then return jsonb_build_object('reason','maintenance_unknown_window');end if;
 select * into issue from private.maintenance_occupancy(f,l,p,w,skip_schedule,skip_item,with_production,clock_timestamp(),maintenance_capacity_conflict.starts,maintenance_capacity_conflict.ends) o
 where o.starts<maintenance_capacity_conflict.ends and o.ends>maintenance_capacity_conflict.starts order by case when o.kind='MAINTENANCE' then 0 else 1 end,
 case when o.kind='MAINTENANCE' then o.sort_at end,o.id limit 1;
 if not found then return null;end if;
 return case when issue.kind='MAINTENANCE' then jsonb_build_object('reason','maintenance_capacity_reserved','schedule',issue.id)
 else jsonb_build_object('reason','maintenance_production_conflict','item',issue.id) end;
end$$;

create function private.maintenance_reader_context(f uuid,rid uuid,request_revision integer,schedule_revision integer,
 range_start timestamptz,range_end timestamptz,evaluated timestamptz)
 returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.maintenance_requests;s public.maintenance_schedules;m public.work_centers;fac public.factories;
 occupancy jsonb;config jsonb;scope jsonb;eligible boolean;uncertain boolean;transfer_open boolean;configuration_valid boolean;begin
 perform private.require_permission(f,'factory','view');perform private.require_permission(f,'maintenance','view');perform private.require_permission(f,'orders','view');
 if request_revision is null or request_revision<1 or schedule_revision is null or schedule_revision<0 then raise exception 'maintenance_invalid' using errcode='22023';end if;
 select * into r from public.maintenance_requests where factory_id=f and id=rid;
 if not found then raise exception 'maintenance_missing' using errcode='P0002';end if;
 select * into s from public.maintenance_schedules where factory_id=f and maintenance_request_id=r.id;
 if r.revision<>request_revision or coalesce(s.revision,0)<>schedule_revision then raise exception 'maintenance_preview_stale' using errcode='40001';end if;
 select * into m from public.work_centers where factory_id=f and id=r.work_center_id;
 select * into fac from public.factories where id=f;
 configuration_valid:=m.id is not null and not m.archived and m.category_id is not null and
 ((m.line_id is null and m.dependency_mode='independent') or exists(select 1 from public.production_lines where factory_id=f and id=m.line_id and not archived));
 eligible:=r.maintenance_kind='PLANNED' and r.estimated_duration_minutes>0 and r.status in ('OPEN','ASSIGNED') and s.hold_started_at is null;
 transfer_open:=exists(select 1 from public.production_transfers t where t.factory_id=f and t.ended_at is null and
 (t.original_id=m.id or t.alternative_id=m.id or t.original_id in(select id from public.work_centers where factory_id=f and line_id=m.line_id)));
 uncertain:=not configuration_valid or (m.status='running' and m.order_id is null) or
 (m.line_id is null and exists(select 1 from public.production_orders o join public.work_center_capabilities c on c.factory_id=o.factory_id and c.product_id=o.product_id
 where o.factory_id=f and c.work_center_id=m.id and o.status in ('planned','active') and o.id is distinct from m.order_id and
 not exists(select 1 from public.production_routing_steps rs where rs.factory_id=f and rs.product_id=o.product_id and rs.kind='work_center' and rs.work_center_id=m.id)));
 select coalesce(jsonb_agg(to_jsonb(o) order by o.kind,o.id),'[]') into occupancy from
 (select * from private.maintenance_occupancy(f,m.line_id,null,m.id,s.id,null,true,evaluated,range_start,range_end,10001))o;
 uncertain:=uncertain or exists(select 1 from jsonb_array_elements(occupancy) x where (x->>'unknown')::boolean);
 config:=jsonb_build_object('machine',private.maintenance_machine_evidence(f,m.id),'calendar',jsonb_build_object('timezone',fac.timezone,'days',fac.working_days_mask,'start',fac.workday_start,'end',fac.workday_end),
 'physical',m.status,'assignment',m.order_id,'transfer_open',transfer_open,'uncertain',uncertain);
 scope:=jsonb_build_object('machine_id',m.id,'line_id',m.line_id,'kind',case when m.line_id is null then 'MACHINE' else 'WHOLE_LINE' end,
 'dependency',m.dependency_mode,'buffer_credit',false,'alternative_credit',false);
 return jsonb_build_object('evaluated_at',evaluated,'timezone',fac.timezone,'request_id',r.id,'request_code',r.code,
 'request_revision',r.revision,'schedule_id',s.id,'schedule_revision',coalesce(s.revision,0),'duration_minutes',r.estimated_duration_minutes,
 'eligible',coalesce(eligible,false),'scope',scope,'configuration_hash',md5(config::text),
 'context_hash',md5(jsonb_build_object('config',config,'request',to_jsonb(r),'schedule',to_jsonb(s),'occupancy',occupancy,'from',range_start,'until',range_end)::text),
 'physical_readiness',case when not configuration_valid then 'UNKNOWN' when m.status in ('idle','stopped','offline') then 'READY_NOW' else 'NOT_READY_NOW' end,
 'unknown',coalesce(uncertain,true),'transfer_open',transfer_open,'occupancy_complete',jsonb_array_length(occupancy)<=10000,
 'calendar_mode','ELAPSED_MAINTENANCE_STORED_PRODUCTION_WINDOWS','binding',false,
 'activation_enabled',(select enabled from private.maintenance_planning_activation where singleton),'confirmation_available',false,'occupancy',occupancy);
end$$;

create function public.maintenance_planning_preview(factory uuid,maintenance_request uuid,candidate_start timestamptz,candidate_end timestamptz,
 expected_request_revision integer,expected_schedule_revision integer,expected_context_hash text default null)
 returns jsonb language plpgsql stable security definer set search_path='' as $$
declare ctx jsonb;finish timestamptz;duration integer;issues jsonb;result text;evaluated timestamptz:=statement_timestamp();begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'maintenance','view');perform private.require_permission(factory,'orders','view');
 if candidate_start is null or not isfinite(candidate_start) or candidate_start<evaluated or (candidate_end is not null and not isfinite(candidate_end)) then raise exception 'maintenance_invalid' using errcode='22023';end if;
 select estimated_duration_minutes into duration from public.maintenance_requests where factory_id=factory and id=maintenance_request;
 -- Unknown duration has no invented default end. The bounded internal range only gathers context.
 finish:=coalesce(candidate_end,case when duration is not null then candidate_start+make_interval(mins=>duration) else candidate_start+interval '31 days' end);
 if finish<=candidate_start or (duration is not null and finish<candidate_start+make_interval(mins=>duration)) then raise exception 'maintenance_invalid' using errcode='22023';end if;
 ctx:=private.maintenance_reader_context(factory,maintenance_request,expected_request_revision,expected_schedule_revision,candidate_start,finish,evaluated);
 if expected_context_hash is not null and expected_context_hash is distinct from ctx->>'context_hash' then raise exception 'maintenance_preview_stale' using errcode='40001';end if;
 select coalesce(jsonb_agg(jsonb_build_object('code',case when o.kind='MAINTENANCE' then 'maintenanceCapacityReserved' else 'maintenanceProductionConflict' end,
 'kind',o.kind,'reference_id',o.id,'state',o.state,'start',o.starts,'end',o.ends,'unknown_end',not isfinite(o.ends),'unknown_window',o.unknown) order by o.kind,o.id),'[]') into issues
 from (select * from jsonb_to_recordset(ctx->'occupancy') as x(kind text,id uuid,starts timestamptz,ends timestamptz,state text,unknown boolean) limit 50)o;
 result:=case when not (ctx->>'occupancy_complete')::boolean then 'INCOMPLETE' when (ctx->>'unknown')::boolean or duration is null then 'UNKNOWN'
 when (ctx->>'transfer_open')::boolean or jsonb_array_length(ctx->'occupancy')>0 then 'BLOCKED' else 'CLEAR' end;
 return (ctx-'occupancy')||jsonb_build_object('start',candidate_start,'end',case when duration is null and candidate_end is null then null else finish end,'slack_minutes',case when duration is not null then extract(epoch from finish-candidate_start)/60-duration end,
 'capacity',result,'conflicts',issues,'conflicts_complete',jsonb_array_length(ctx->'occupancy')<=50,
 'conditions',jsonb_build_object('configuration_or_routing_unknown',(ctx->>'unknown')::boolean,'open_transfer',(ctx->>'transfer_open')::boolean,'duration_unknown',duration is null));
end$$;

create function public.maintenance_planning_gaps(factory uuid,maintenance_request uuid,search_start timestamptz,search_end timestamptz,
 expected_request_revision integer,expected_schedule_revision integer,window_minutes integer default null,result_limit integer default 10,
 after_start timestamptz default null,expected_context_hash text default null)
 returns jsonb language plpgsql stable security definer set search_path='' as $$
declare ctx jsonb;duration integer;minutes integer;evaluated timestamptz:=statement_timestamp();candidates jsonb;result text;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'maintenance','view');perform private.require_permission(factory,'orders','view');
 if search_start is null or search_end is null or not isfinite(search_start) or not isfinite(search_end) or search_start<evaluated or search_end<=search_start
 or search_end-search_start>interval '31 days' or result_limit is null or result_limit not between 1 and 20
 or (after_start is not null and (not isfinite(after_start) or after_start<search_start or after_start>=search_end or expected_context_hash is null))
 then raise exception 'maintenance_invalid' using errcode='22023';end if;
 ctx:=private.maintenance_reader_context(factory,maintenance_request,expected_request_revision,expected_schedule_revision,search_start,search_end,evaluated);
 if expected_context_hash is not null and expected_context_hash is distinct from ctx->>'context_hash' then raise exception 'maintenance_preview_stale' using errcode='40001';end if;
 duration:=(ctx->>'duration_minutes')::integer;minutes:=coalesce(window_minutes,duration);
 if window_minutes is not null and (window_minutes<1 or (duration is not null and window_minutes<duration)) then raise exception 'maintenance_invalid' using errcode='22023';end if;
 result:=case when not (ctx->>'occupancy_complete')::boolean then 'INCOMPLETE' when (ctx->>'unknown')::boolean or duration is null then 'UNKNOWN'
 when not (ctx->>'eligible')::boolean or (ctx->>'transfer_open')::boolean then 'BLOCKED' else 'CLEAR' end;
 candidates:='[]';
 if result='CLEAR' then
 -- Sweep sorted interval boundaries once. A running maximum merges nested/overlapping intervals.
 with occupied as materialized(select greatest(search_start,starts) a,least(search_end,ends) b from
 jsonb_to_recordset(ctx->'occupancy') x(starts timestamptz,ends timestamptz)),
 boundaries as(select search_start a,search_start b union all select a,b from occupied union all select search_end,search_end),
 swept as(select a,b,max(b) over(order by a,b rows between unbounded preceding and 1 preceding) previous_end from boundaries),
 gaps as(select greatest(search_start,previous_end) a,a b from swept where previous_end is not null and a>previous_end),
 eligible_gaps as(select a,b,a+make_interval(mins=>minutes) finish from gaps where b-a>=make_interval(mins=>minutes) and (after_start is null or a>after_start)
 order by a,b limit result_limit+1)
 select coalesce(jsonb_agg(jsonb_build_object('start',a,'end',finish,'gap_end',b) order by a,b),'[]') into candidates from eligible_gaps;
 if jsonb_array_length(candidates)=0 then result:='BLOCKED';end if;
 end if;
 return (ctx-'occupancy')||jsonb_build_object('capacity',result,'search_start',search_start,'search_end',search_end,'window_minutes',minutes,
 'suggestions',case when jsonb_array_length(candidates)>result_limit then candidates-(jsonb_array_length(candidates)-1) else candidates end,
 'has_more',jsonb_array_length(candidates)>result_limit,'next_after_start',case when jsonb_array_length(candidates)>result_limit then candidates->(result_limit-1)->>'start' end,
 'suggestions_complete',jsonb_array_length(candidates)<=result_limit,'blocker_count',jsonb_array_length(ctx->'occupancy'),
 'blockers',(select coalesce(jsonb_agg(jsonb_build_object('code',case when x.kind='MAINTENANCE' then 'maintenanceCapacityReserved' else 'maintenanceProductionConflict' end,
 'kind',x.kind,'reference_id',x.id,'state',x.state,'start',x.starts,'end',x.ends,'unknown_window',x.unknown)),'[]') from
 (select * from jsonb_to_recordset(ctx->'occupancy') y(kind text,id uuid,state text,starts timestamptz,ends timestamptz,unknown boolean) limit 20)x),
 'blockers_complete',jsonb_array_length(ctx->'occupancy')<=20,
 'conditions',jsonb_build_object('configuration_or_routing_unknown',(ctx->>'unknown')::boolean,'open_transfer',(ctx->>'transfer_open')::boolean,'duration_unknown',duration is null));
end$$;

create function public.maintenance_planning_history(factory uuid,maintenance_request uuid,page_size integer default 25,
 before_revision integer default null,through_revision integer default null) returns jsonb
 language plpgsql stable security definer set search_path='' as $$
declare sid uuid;high integer;rows jsonb;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'maintenance','view');
 if page_size is null or page_size not between 1 and 50 or (before_revision is not null and before_revision<1) or (through_revision is not null and through_revision<0)
 then raise exception 'maintenance_invalid' using errcode='22023';end if;
 if not exists(select 1 from public.maintenance_requests where factory_id=factory and id=maintenance_request) then raise exception 'maintenance_missing' using errcode='P0002';end if;
 select id into sid from public.maintenance_schedules where factory_id=factory and maintenance_request_id=maintenance_request;
 select coalesce(max(revision),0) into high from public.maintenance_schedule_revisions where factory_id=factory and schedule_id=sid;
 if through_revision is not null and through_revision>high then raise exception 'maintenance_invalid' using errcode='22023';end if;
 high:=coalesce(through_revision,high);
 select coalesce(jsonb_agg(to_jsonb(x) order by x.revision desc),'[]') into rows from (
 select h.revision,h.event,h.reason,h.actor_id,h.actor_name,h.changed_at,
 jsonb_build_object('start',h.before_data->'planned_start','end',h.before_data->'planned_end','state',h.before_data->'state') before_window,
 jsonb_build_object('start',h.after_data->'planned_start','end',h.after_data->'planned_end','state',h.after_data->'state') after_window,
 private.maintenance_history_scope(h.resources) after_resources,
 case when h.revision=1 and h.before_data is null then '[]'::jsonb when prev.after_data=h.before_data then private.maintenance_history_scope(prev.resources) end before_resources,
 case when h.revision=1 and h.before_data is null then 'NO_PREVIOUS_SCHEDULE' when prev.after_data=h.before_data then 'ADJACENT_RECORDED' else 'NOT_RECORDED' end before_evidence,
 h.before_data->'hold_started_at' before_hold,h.after_data->'hold_started_at' after_hold,h.after_data->'released_at' released_at
 from (select * from public.maintenance_schedule_revisions where factory_id=factory and schedule_id=sid and revision<=high and (before_revision is null or revision<before_revision)
 order by revision desc limit page_size+1) h left join public.maintenance_schedule_revisions prev on prev.factory_id=h.factory_id and prev.schedule_id=h.schedule_id and prev.revision=h.revision-1
 )x;
 return jsonb_build_object('request_id',maintenance_request,'schedule_id',sid,'through_revision',high,'rows',case when jsonb_array_length(rows)>page_size then rows-(jsonb_array_length(rows)-1) else rows end,
 'has_more',jsonb_array_length(rows)>page_size,'next_before_revision',case when jsonb_array_length(rows)>page_size then rows->(page_size-1)->'revision' end);
end$$;

-- Whitelist recorded topology/impact; do not disclose raw capability, alternative or Auth payloads.
create function private.maintenance_history_scope(recorded jsonb) returns jsonb language sql immutable set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('kind',x->'resource_kind','machine_id',x->'machine_id','line_id',x->'line_id','impact_reason',x->'impact_reason',
 'machine_evidence',(x->'evidence')->'machine') order by x->>'resource_kind',x->>'machine_id',x->>'line_id'),'[]') from jsonb_array_elements(recorded) x;
$$;

revoke all on function private.maintenance_occupancy(uuid,uuid,uuid,uuid,uuid,uuid,boolean,timestamptz,timestamptz,timestamptz,integer),
 private.maintenance_reader_context(uuid,uuid,integer,integer,timestamptz,timestamptz,timestamptz),private.maintenance_history_scope(jsonb) from public,anon,authenticated;
revoke all on function public.maintenance_planning_preview(uuid,uuid,timestamptz,timestamptz,integer,integer,text),
 public.maintenance_planning_gaps(uuid,uuid,timestamptz,timestamptz,integer,integer,integer,integer,timestamptz,text),
 public.maintenance_planning_history(uuid,uuid,integer,integer,integer) from public,anon,authenticated;
grant execute on function public.maintenance_planning_preview(uuid,uuid,timestamptz,timestamptz,integer,integer,text),
 public.maintenance_planning_gaps(uuid,uuid,timestamptz,timestamptz,integer,integer,integer,integer,timestamptz,text),
 public.maintenance_planning_history(uuid,uuid,integer,integer,integer) to authenticated;

-- Additive capability metadata; old calls/page limits/data/grants remain compatible.
create or replace function public.maintenance_planning_read(factory uuid,page integer default 1) returns jsonb
 language plpgsql stable security definer set search_path='' as $$begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'maintenance','view');
 if page not between 1 and 100000 then raise exception 'maintenance_invalid';end if;
 return jsonb_build_object('active',(select enabled from private.maintenance_planning_activation where singleton),
 'activation_reason',(select reason from private.maintenance_planning_activation where singleton),
 'preview_available',private.has_permission(factory,'orders','view'),'history_available',true,
 'total',(select count(*) from public.maintenance_schedules where factory_id=factory),
 'rows',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select s.*,r.code,r.work_center_id,
 coalesce((select jsonb_agg(to_jsonb(res)) from public.maintenance_schedule_resources res where res.schedule_id=s.id),'[]') resources,
 (s.state in ('CONFIRMED','INVALIDATED') and s.hold_started_at is null and clock_timestamp()>s.planned_end) missed_window,
 (s.hold_started_at is not null and s.state<>'RELEASED') actual_hold,
 (s.hold_started_at is not null and s.state<>'RELEASED' and clock_timestamp()>s.planned_end) overrun
 from public.maintenance_schedules s join public.maintenance_requests r on r.factory_id=s.factory_id and r.id=s.maintenance_request_id
 where s.factory_id=factory order by s.planned_start,s.id limit 50 offset (page-1)*50)x));
end$$;
