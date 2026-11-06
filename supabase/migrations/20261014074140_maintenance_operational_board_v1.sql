-- Read-only Phase5E projection. No activation, writer, Preview/Gaps or Loss changes.
create function private.planning_operational_rows(f uuid,a timestamptz,b timestamptz,l uuid,w uuid,domain text,at_time timestamptz)
returns table(kind text,id uuid,payload jsonb,uncertain boolean)
language sql stable security definer set search_path='' as $$
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
 'id',o.id,'lineIds',jsonb_build_array(o.line_id),'start',case when o.status='active' or o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time then null else o.start_time end,
 'finish',case when o.status='active' or o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time then null else o.expected_finish end,'reserved',true) else null end) payload,
 (o.status='active' and o.line_id is null or o.status='planned' and o.line_id is not null and (o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time)) uncertain
 from public.production_orders o join public.production_requests r on r.factory_id=f and r.id=o.request_id
 where domain='all' and o.factory_id=f and o.status<>'cancelled' and
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
$$;
revoke all on function private.planning_operational_rows(uuid,timestamptz,timestamptz,uuid,uuid,text,timestamptz) from public,anon,authenticated;

create function public.planning_operational_board(factory uuid,range_start timestamptz,range_end timestamptz,
 line_id uuid default null,machine uuid default null,domain text default 'all',page_size integer default 100,
 after_kind text default null,after_id uuid default null,expected_hash text default null,evaluated_at timestamptz default null)
returns jsonb language plpgsql stable security definer set search_path='' set timezone='UTC' as $$
declare stamp timestamptz:=coalesce(evaluated_at,statement_timestamp());expiry timestamptz;records jsonb;chosen jsonb;total integer;fingerprint text;more boolean;uncertain boolean;last_row jsonb;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'maintenance','view');
 if domain='all' then perform private.require_permission(factory,'orders','view');end if;
 if range_start is null or range_end is null or not isfinite(range_start) or not isfinite(range_end) or range_end<=range_start or range_end-range_start>interval '31 days'
 or domain is null or domain not in ('all','maintenance') or page_size is null or page_size not between 1 and 100
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
end$$;
revoke all on function public.planning_operational_board(uuid,timestamptz,timestamptz,uuid,uuid,text,integer,text,uuid,text,timestamptz) from public,anon;
grant execute on function public.planning_operational_board(uuid,timestamptz,timestamptz,uuid,uuid,text,integer,text,uuid,text,timestamptz) to authenticated;
