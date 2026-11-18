-- Planning alone uses approved intervals. Maintenance actual occupancy remains unchanged.
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
      and other.status='planned' and
      (other.start_time is null or other.expected_finish is null or other.expected_finish<=other.start_time)
  ) then raise exception 'planning_unknown_block'; end if;
  if exists(
    select 1 from public.production_orders other
    where other.factory_id=f and other.id<>item and other.line_id=target_line
      and other.status in ('planned','active')
      and (other.status='planned' or other.expected_finish>other.start_time)
      and effective_start<other.expected_finish and planned_finish>other.start_time
  ) then raise exception 'planning_overlap'; end if;
  update public.production_orders set
    line_id=target_line,start_time=effective_start,expected_finish=planned_finish
    where factory_id=f and id=item;
  return item;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.planning_operational_rows(f uuid, a timestamp with time zone, b timestamp with time zone, l uuid, w uuid, domain text, at_time timestamp with time zone)
 RETURNS TABLE(kind text, id uuid, payload jsonb, uncertain boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 with event_scope as materialized (
 select d.* from public.downtime_events d where d.factory_id=f and
 (d.ended_at is null or (d.started_at<b and d.ended_at>a))
 ), links as materialized (
 select assoc.schedule_id,d.id event_id,d.work_center_id,d.started_at,d.ended_at,assoc.id association_id,assoc.revision,assoc.approval_revision,assoc.approval->>'planned_start' approved_start,assoc.approval->>'planned_end' approved_end,row_number() over(partition by assoc.schedule_id order by case when d.started_at<b and coalesce(d.ended_at,'infinity')>a then 0 else 1 end,d.started_at,d.id) ordinal
 from event_scope d join public.maintenance_stop_associations assoc on assoc.factory_id=f and assoc.event_id=d.id
 where assoc.operation='LINK' and not exists(select 1 from public.maintenance_stop_associations n
 where n.factory_id=f and n.event_id=assoc.event_id and n.revision>assoc.revision)
 ), stop_groups as (
 select schedule_id,min(started_at) filter(where ended_at is null) open_start,
 count(*) filter(where started_at<b and coalesce(ended_at,'infinity')>a) stop_count,
 coalesce(jsonb_agg(jsonb_build_object('id',event_id,'work_center_id',work_center_id,'started_at',started_at,'ended_at',ended_at,
 'association_id',association_id,'association_revision',revision,'approval_revision',approval_revision,'approved_start',approved_start,'approved_end',approved_end) order by started_at,event_id)
 filter(where ordinal<=100 and started_at<b and coalesce(ended_at,'infinity')>a),'[]') stops from links group by schedule_id
 ), candidates as materialized (
 select s.*,g.open_start,coalesce(g.stop_count,0) stop_count,coalesce(g.stops,'[]') stops,
 least(s.planned_start,coalesce(s.hold_started_at,s.planned_start),coalesce(g.open_start,s.planned_start)) effective_start,
 case when s.state='RELEASED' then coalesce(s.released_at,s.planned_end)
 when s.state in ('CONFIRMED','INVALIDATED') and (s.hold_started_at is not null or g.open_start is not null or s.state='INVALIDATED' or s.planned_end<=at_time)
 then 'infinity'::timestamptz else s.planned_end end effective_end
 from public.maintenance_schedules s left join stop_groups g on g.schedule_id=s.id
 where s.factory_id=f and ((s.planned_start<b and s.planned_end>a) or
 (s.state in ('CONFIRMED','INVALIDATED') and (s.hold_started_at is not null or g.open_start is not null or s.state='INVALIDATED' or s.planned_end<=at_time))
 or coalesce(g.stop_count,0)>0 or (s.released_at>a and s.planned_start<b))
 ), resource_rows as materialized (
 select c.id schedule_id,r.resource_kind,r.machine_id,r.line_id,r.impact_reason,m.line_id current_line
 from candidates c join public.maintenance_schedule_resources r on r.factory_id=f and r.schedule_id=c.id
 left join public.work_centers m on m.factory_id=f and m.id=r.machine_id
 ), line_scope as (
 select schedule_id,line_id from resource_rows where line_id is not null
 union select schedule_id,current_line from resource_rows where current_line is not null
 union select c.id,m.line_id from candidates c join public.maintenance_requests r on r.factory_id=f and r.id=c.maintenance_request_id
 join public.work_centers m on m.factory_id=f and m.id=r.work_center_id where m.line_id is not null and not exists(select 1 from resource_rows rr where rr.schedule_id=c.id)
 union select r.schedule_id,o.line_id from resource_rows r join public.production_transfers t on t.factory_id=f and t.alternative_id=r.machine_id and t.ended_at is null
 join public.production_orders o on o.factory_id=f and o.id=t.order_id where o.line_id is not null
 ), machine_scope as (
 select schedule_id,machine_id from resource_rows where machine_id is not null
 union select c.id,r.work_center_id from candidates c join public.maintenance_requests r on r.factory_id=f and r.id=c.maintenance_request_id
 ), line_groups as (select schedule_id,jsonb_agg(line_id order by line_id) line_ids from line_scope group by schedule_id),
 machine_groups as (select schedule_id,jsonb_agg(machine_id order by machine_id) machine_ids from machine_scope group by schedule_id),
 product_groups as (select rr.schedule_id,jsonb_agg(distinct rs.product_id order by rs.product_id) product_ids from resource_rows rr join public.production_routing_steps rs on rs.factory_id=f and rs.kind='work_center' and rs.work_center_id=rr.machine_id group by rr.schedule_id),
 resource_groups as (select rr.schedule_id,jsonb_agg(jsonb_build_object('resource_kind',rr.resource_kind,'machine_id',rr.machine_id,'line_id',rr.line_id,'impact_reason',rr.impact_reason) order by rr.resource_kind,rr.machine_id,rr.line_id) resources from resource_rows rr group by rr.schedule_id),
 groups as (
 select c.id,coalesce(lg.line_ids,'[]') line_ids,coalesce(mg.machine_ids,'[]') machine_ids,coalesce(pg.product_ids,'[]') product_ids,coalesce(rg.resources,'[]') resources
 from candidates c left join line_groups lg on lg.schedule_id=c.id left join machine_groups mg on mg.schedule_id=c.id
 left join product_groups pg on pg.schedule_id=c.id left join resource_groups rg on rg.schedule_id=c.id
 ), maintenance as (
 select 'MAINTENANCE'::text kind,c.id,jsonb_build_object('schedule',to_jsonb(c)-'open_start'-'stop_count'-'stops'-'effective_start'-'effective_end'||
 jsonb_build_object('work_center_id',r.work_center_id,'code',r.code,'machine_code',m.code,'machine_name',m.name,'machine_name_ar',m.name_ar,'resources',g.resources,'line_ids',g.line_ids,'machine_ids',g.machine_ids,
 'actual_stops',case when c.stop_count<=100 then c.stops else '[]'::jsonb end,
 'actual_hold',c.state in ('CONFIRMED','INVALIDATED') and (c.hold_started_at is not null or c.open_start is not null),'overrun',c.state in ('CONFIRMED','INVALIDATED') and (c.hold_started_at is not null or c.open_start is not null) and c.planned_end<at_time,
 'missed_window',c.state='CONFIRMED' and c.hold_started_at is null and c.open_start is null and c.planned_end<=at_time,
 'occupancy',jsonb_build_object('id',c.id,'lineIds',g.line_ids,'machineIds',g.machine_ids,'productIds',g.product_ids,
 'start',c.effective_start,'finish',case when isfinite(c.effective_end) then c.effective_end end,'continues',not isfinite(c.effective_end),'reserved',c.state in ('CONFIRMED','INVALIDATED'))),
 'request',to_jsonb(r)||jsonb_build_object('machine_code',m.code,'machine_name',m.name,'machine_name_ar',m.name_ar)) payload,
 (c.stop_count>100 or c.state='RELEASED' and c.open_start is not null or (c.state in ('CONFIRMED','INVALIDATED') and not exists(select 1 from jsonb_array_elements(g.resources) resource where resource->>'resource_kind'='MACHINE' and resource->>'machine_id'=r.work_center_id::text))) uncertain
 from candidates c join groups g on g.id=c.id join public.maintenance_requests r on r.factory_id=f and r.id=c.maintenance_request_id
 join public.work_centers m on m.factory_id=f and m.id=r.work_center_id
 where ((c.effective_start<b and c.effective_end>a) or (c.planned_start<b and c.planned_end>a) or c.stop_count>0)
 and (l is null or g.line_ids ? l::text or jsonb_array_length(g.line_ids)=0 or c.state='PROPOSED' and m.line_id=l)
 and (w is null or g.machine_ids ? w::text)
 ), production as (
 select 'PRODUCTION'::text kind,o.id,jsonb_build_object('order',to_jsonb(o),'request',to_jsonb(r),
 'occupancy',case when o.status in ('planned','active') and o.line_id is not null then jsonb_build_object(
 'id',o.id,'lineIds',jsonb_build_array(o.line_id),'start',case when domain<>'production_plan'and o.status='active' or o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time then null else o.start_time end,
 'finish',case when domain<>'production_plan'and o.status='active' or o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time then null else o.expected_finish end,'reserved',true) else null end) payload,
 (domain<>'production_plan'and o.status='active' and o.line_id is null or o.status='planned' and o.line_id is not null and (o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time)) uncertain
 from public.production_orders o join public.production_requests r on r.factory_id=f and r.id=o.request_id
 where domain in('all','production_plan') and o.factory_id=f and o.status<>'cancelled' and
 (o.status='active' or o.status='planned' and (o.line_id is null or o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time) or o.start_time<b and o.expected_finish>a)
 and (l is null or o.line_id=l or o.line_id is null) and (w is null or
 o.id in(select m.order_id from public.work_centers m where m.factory_id=f and m.id=w) or
 o.product_id in(select rs.product_id from public.production_routing_steps rs where rs.factory_id=f and rs.work_center_id=w and rs.kind='work_center') or
 o.line_id in(select m.line_id from public.work_centers m where m.factory_id=f and m.id=w and m.line_id is not null))
 ), needs as (
 select 'REQUEST'::text kind,r.id,jsonb_build_object('request',to_jsonb(r)||jsonb_build_object('machine_code',m.code,'machine_name',m.name,'machine_name_ar',m.name_ar)) payload,false uncertain
 from public.maintenance_requests r join public.work_centers m on m.factory_id=f and m.id=r.work_center_id
 where r.factory_id=f and r.status in ('OPEN','ASSIGNED','IN_PROGRESS')
 and not exists(select 1 from public.maintenance_schedules s where s.factory_id=f and s.maintenance_request_id=r.id and s.state in ('PROPOSED','CONFIRMED','INVALIDATED','RELEASED'))
 and (l is null or m.line_id=l or m.line_id is null) and (w is null or m.id=w)
 ) select * from maintenance union all select * from production union all select * from needs;
$function$
;
CREATE OR REPLACE FUNCTION public.planning_operational_board(factory uuid, range_start timestamp with time zone, range_end timestamp with time zone, line_id uuid DEFAULT NULL::uuid, machine uuid DEFAULT NULL::uuid, domain text DEFAULT 'all'::text, page_size integer DEFAULT 100, after_kind text DEFAULT NULL::text, after_id uuid DEFAULT NULL::uuid, expected_hash text DEFAULT NULL::text, evaluated_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET "TimeZone" TO 'UTC'
AS $function$
declare stamp timestamptz:=coalesce(evaluated_at,statement_timestamp());expiry timestamptz;records jsonb;chosen jsonb;total integer;fingerprint text;more boolean;uncertain boolean;last_row jsonb;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'maintenance','view');
 if domain in('all','production_plan') then perform private.require_permission(factory,'orders','view');end if;
 if range_start is null or range_end is null or not isfinite(range_start) or not isfinite(range_end) or range_end<=range_start or range_end-range_start>interval '31 days'
 or domain is null or domain not in ('all','maintenance','production_plan') or page_size is null or page_size not between 1 and 100
 or (after_kind is null)<>(after_id is null) or (after_id is null)<>(expected_hash is null) or (after_id is null)<>(evaluated_at is null)
 or after_kind is not null and after_kind not in ('PRODUCTION','MAINTENANCE','REQUEST') or expected_hash is not null and expected_hash!~'^[a-f0-9]{64}$' then raise exception 'maintenance_invalid' using errcode='22023';end if;
 if line_id is not null and not exists(select 1 from public.production_lines where factory_id=factory and id=line_id) or machine is not null and not exists(select 1 from public.work_centers where factory_id=factory and id=machine) then raise exception 'maintenance_missing' using errcode='P0002';end if;
 if stamp>statement_timestamp() or stamp<statement_timestamp()-interval '60 seconds' then raise exception 'maintenance_board_changed' using errcode='40001';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.kind,x.id),'[]'),coalesce(bool_or(x.uncertain),false) into records,uncertain from (
 select * from private.planning_operational_rows(factory,range_start,range_end,line_id,machine,domain,stamp) order by kind,id limit 10001)x;
 total:=jsonb_array_length(records);
 expiry:=least(stamp+interval '60 seconds',coalesce((select min((r->'payload'->'schedule'->>'planned_end')::timestamptz) from jsonb_array_elements(records) r
 where r->'payload'->'schedule'->>'state'='CONFIRMED' and (r->'payload'->'schedule'->>'planned_end')::timestamptz>stamp),stamp+interval '60 seconds'));
 fingerprint:=encode(sha256(convert_to(jsonb_build_object('factory',factory,'start',range_start,'end',range_end,'line',line_id,'machine',machine,'domain',domain,'evaluated_at',stamp,'records',records)::text,'UTF8')),'hex');
 if expected_hash is not null and (expected_hash<>fingerprint or statement_timestamp()>=expiry or not exists(select 1 from jsonb_array_elements(records) r where r->>'kind'=after_kind and r->>'id'=after_id::text)) then raise exception 'maintenance_board_changed' using errcode='40001';end if;
 if total>10000 then return jsonb_build_object('factory',factory,'start',range_start,'end',range_end,'line',line_id,'machine',machine,'domain',domain,
 'completeness','INCOMPLETE','scope_complete',false,'reason','SCOPE_LIMIT','rows','[]'::jsonb,'total',null,'has_more',false,'evaluated_at',stamp,'valid_until',expiry,'context_hash',fingerprint);end if;
 select coalesce(jsonb_agg(x.r order by x.r->>'kind',x.r->>'id'),'[]') into chosen from (
 select r from jsonb_array_elements(records) r where after_id is null or (r->>'kind',r->>'id')>(after_kind,after_id::text)
 order by r->>'kind',r->>'id' limit page_size)x;
 last_row:=chosen->(jsonb_array_length(chosen)-1);
 more:=exists(select 1 from jsonb_array_elements(records) r where (r->>'kind',r->>'id')>(last_row->>'kind',last_row->>'id'));
 return jsonb_build_object('factory',factory,'start',range_start,'end',range_end,'line',line_id,'machine',machine,'domain',domain,
 'completeness',case when uncertain or total>jsonb_array_length(chosen) then 'INCOMPLETE' else 'COMPLETE' end,'scope_complete',not uncertain,
 'reason',case when uncertain then 'UNKNOWN_OCCUPANCY' when total>jsonb_array_length(chosen) then 'PAGES_PENDING' end,
 'rows',chosen,'total',total,'has_more',more,'next',case when more then jsonb_build_object('kind',last_row->>'kind','id',last_row->>'id') end,
 'evaluated_at',stamp,'valid_until',expiry,'context_hash',fingerprint,'active',(select enabled from private.maintenance_planning_activation where singleton),
 'preview_available',true,'history_available',true);
end$function$
;
-- F46: actual delays are evidence, never an implicit Planning reservation or execution stop.
create table private.production_delay_policy(
 factory_id uuid primary key references public.factories(id),
 grace_minutes integer not null check(grace_minutes>=0),
 revision bigint not null default 1,
 updated_by uuid not null references auth.users(id),updated_at timestamptz not null default clock_timestamp()
);
create table private.production_delay_events(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories(id),
 item_id uuid not null,episode text not null check(episode~'^[a-f0-9]{64}$'),
 plan_revision integer not null,planned_finish timestamptz not null,
 actual_line_id uuid,reason text not null check(char_length(btrim(reason))between 3 and 500),
 estimated_finish timestamptz check(estimated_finish is null or isfinite(estimated_finish)),
 grace_minutes integer not null check(grace_minutes>=0),delay_seconds numeric not null check(delay_seconds>=0),
 order_snapshot jsonb not null,actor uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 foreign key(factory_id,item_id)references public.production_orders(factory_id,id),
 foreign key(factory_id,actual_line_id)references public.production_lines(factory_id,id)
);
create index production_delay_episode_history on private.production_delay_events(factory_id,item_id,episode,created_at desc,id desc);
alter table private.production_delay_policy enable row level security;
alter table private.production_delay_events enable row level security;
revoke all on private.production_delay_policy,private.production_delay_events from public,anon,authenticated,service_role;
create trigger production_delay_policy_audit after insert or update or delete on private.production_delay_policy for each row execute function private.audit_change();
create function private.guard_production_delay_history()returns trigger language plpgsql set search_path=''as $$begin raise exception 'f46HistoryImmutable';end$$;
revoke all on function private.guard_production_delay_history()from public,anon,authenticated,service_role;
create trigger production_delay_history_immutable before update or delete on private.production_delay_events for each row execute function private.guard_production_delay_history();

create function private.production_delay_state(f uuid,i uuid)returns jsonb language plpgsql stable security definer set search_path=''as $$
declare o public.production_orders;e private.production_delay_events;v_episode text;rev integer;grace integer;revision bigint;begin
 select *into o from public.production_orders where factory_id=f and id=i;if not found then raise exception 'not_found';end if;
 select coalesce(max(revision_no),0)into rev from public.production_plan_revisions where factory_id=f and item_id=i;
 select grace_minutes,p.revision into grace,revision from private.production_delay_policy p where factory_id=f;grace:=coalesce(grace,15);revision:=coalesce(revision,0);
 v_episode:=encode(sha256(convert_to(jsonb_build_array(i,rev,o.line_id,o.start_time,o.expected_finish)::text,'UTF8')),'hex');
 select *into e from private.production_delay_events where factory_id=f and item_id=i and production_delay_events.episode=v_episode order by created_at desc,id desc limit 1;
 return jsonb_build_object('item',i,'code',o.code,'status',o.status,'actual_finish',o.actual_finish,'actual_start',o.actual_start,
 'planned_line',o.line_id,'actual_line',coalesce(o.actual_line_id,o.line_id),'planned_start',o.start_time,'planned_finish',o.expected_finish,
 'plan_revision',rev,'episode',v_episode,'grace_minutes',grace,
 'delay_seconds',case when o.status='active'and o.actual_finish is null and o.expected_finish is not null then greatest(floor(extract(epoch from(statement_timestamp()-o.expected_finish))),0)::text end,
 'pending',o.status='active'and o.actual_finish is null and o.expected_finish is not null and statement_timestamp()>=o.expected_finish+grace*interval '1 minute'and e.id is null,
 'last',case when e.id is not null then to_jsonb(e)||jsonb_build_object('actor_name',(select display_name from public.memberships where factory_id=f and user_id=e.actor),'delay_seconds',e.delay_seconds::text)end,
 'fingerprint',encode(sha256(convert_to(jsonb_build_array(i,o.status,o.actual_finish,o.actual_start,coalesce(o.actual_line_id,o.line_id),v_episode,e.id,grace,revision)::text,'UTF8')),'hex'));
end$$;
revoke all on function private.production_delay_state(uuid,uuid)from public,anon,authenticated,service_role;

create function public.production_delay_read(factory uuid,item uuid default null,request_id uuid default null)returns jsonb language plpgsql stable security definer set search_path=''as $$
declare rows jsonb;history jsonb;total bigint;grace integer;receipt public.fulfillment_commands;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'orders','view');
 if item is not null and request_id is not null then raise exception 'f46Invalid';end if;
 select grace_minutes into grace from private.production_delay_policy where factory_id=factory;grace:=coalesce(grace,15);
 if request_id is not null then
  select *into receipt from public.fulfillment_commands c where c.factory_id=factory and c.request_id=production_delay_read.request_id and c.actor_id=auth.uid()and c.operation in('production_delay_reason','production_delay_policy');
  return jsonb_build_object('receipt',case when receipt.request_id is not null then jsonb_build_object('request_id',receipt.request_id,'intent',receipt.payload,'id',receipt.result_id)end);
 elsif item is not null then
  select count(*)into total from private.production_delay_events where factory_id=factory and item_id=item;
  select coalesce(jsonb_agg(to_jsonb(e)||jsonb_build_object('actor_name',(select display_name from public.memberships where factory_id=factory and user_id=e.actor))order by e.created_at desc,e.id desc),'[]')into history from(select *from private.production_delay_events where factory_id=factory and item_id=item order by created_at desc,id desc limit 20)e;
  return private.production_delay_state(factory,item)||jsonb_build_object('factory',factory,'history',history,'history_total',total);
 end if;
 select coalesce(jsonb_agg(private.production_delay_state(factory,o.id)order by o.expected_finish nulls last,o.id),'[]')into rows from public.production_orders o where o.factory_id=factory and o.status='active'and o.actual_finish is null;
 return jsonb_build_object('factory',factory,'grace_minutes',grace,'evaluated_at',statement_timestamp(),'rows',rows);
end$$;
revoke all on function public.production_delay_read(uuid,uuid,uuid)from public,anon,service_role;
grant execute on function public.production_delay_read(uuid,uuid,uuid)to authenticated;

create function public.production_delay_command(factory uuid,operation text,payload jsonb,request_id uuid)returns uuid language plpgsql security definer set search_path=''as $$
declare prior uuid;intent jsonb;state jsonb;o public.production_orders;id uuid;eta timestamptz;grace integer;begin
 perform private.require_permission(factory,'orders','view');
 if operation='REASON'then perform private.require_permission(factory,'orders','edit');elsif operation='POLICY'then perform private.require_permission(factory,'factory','edit');else raise exception 'f46Invalid';end if;
 if request_id is null or jsonb_typeof(payload)is distinct from 'object'or octet_length(payload::text)>5000 then raise exception 'f46Invalid';end if;
 if current_setting('transaction_isolation')<>'read committed'then raise exception 'f46Changed'using errcode='40001';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.fulfillment_lock(factory);
 perform private.require_permission(factory,case when operation='POLICY'then 'factory'else 'orders'end,'edit');
 intent:=jsonb_build_object('operation',operation,'payload',payload);
 prior:=private.fulfillment_retry(factory,request_id,case when operation='REASON'then 'production_delay_reason'else 'production_delay_policy'end,intent);if prior is not null then return prior;end if;
 if operation='POLICY'then
  if(select count(*)from jsonb_object_keys(payload))<>1 or not(payload?'grace_minutes')or jsonb_typeof(payload->'grace_minutes')<>'number'or(payload->>'grace_minutes')!~'^[0-9]+$'then raise exception 'f46Invalid';end if;
  grace:=(payload->>'grace_minutes')::integer;
  insert into private.production_delay_policy(factory_id,grace_minutes,updated_by)values(factory,grace,auth.uid())on conflict(factory_id)do update set grace_minutes=excluded.grace_minutes,revision=production_delay_policy.revision+1,updated_by=auth.uid(),updated_at=clock_timestamp();id:=factory;
 else
  if exists(select 1 from jsonb_object_keys(payload)k where k not in('item','reason','estimated_finish','fingerprint'))or not(payload?&array['item','reason','estimated_finish','fingerprint'])or payload->>'fingerprint'!~'^[a-f0-9]{64}$'or payload->>'fingerprint'is null or jsonb_typeof(payload->'reason')is distinct from 'string'or char_length(btrim(payload->>'reason'))not between 3 and 500 or payload->>'reason'is null then raise exception 'f46ReasonRequired';end if;
  select *into o from public.production_orders where factory_id=factory and production_orders.id=(payload->>'item')::uuid for update;if not found then raise exception 'not_found';end if;
  state:=private.production_delay_state(factory,o.id);
  if state->>'fingerprint'is distinct from payload->>'fingerprint'then raise exception 'f46Changed'using errcode='40001';end if;
  if o.status<>'active'or o.actual_finish is not null or o.expected_finish is null or not isfinite(o.expected_finish)or statement_timestamp()<=o.expected_finish then raise exception 'f46NotDelayed';end if;
  eta:=(payload->>'estimated_finish')::timestamptz;if eta is not null and(not isfinite(eta)or eta<=statement_timestamp())then raise exception 'f46EstimateFuture';end if;
  insert into private.production_delay_events(factory_id,item_id,episode,plan_revision,planned_finish,actual_line_id,reason,estimated_finish,grace_minutes,delay_seconds,order_snapshot,actor)
  values(factory,o.id,state->>'episode',(state->>'plan_revision')::integer,o.expected_finish,coalesce(o.actual_line_id,o.line_id),btrim(payload->>'reason'),eta,(state->>'grace_minutes')::integer,extract(epoch from(statement_timestamp()-o.expected_finish)),to_jsonb(o),auth.uid())returning production_delay_events.id into id;
 end if;
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),case when operation='REASON'then 'production_delay_reason'else 'production_delay_policy'end,intent,id,clock_timestamp());return id;
end$$;
revoke all on function public.production_delay_command(uuid,text,jsonb,uuid)from public,anon,service_role;
grant execute on function public.production_delay_command(uuid,text,jsonb,uuid)to authenticated;
