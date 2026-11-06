-- M3A reporting foundation only. No writer/UI/activation integration.
begin;

-- Storage support for future period observations. The existing command still
-- writes EXACT events; no command whitelist or write behavior changes in 3A.
alter table public.lean_scrap_events
 add column time_precision text not null default 'EXACT',
 add column occurrence_key text,
 add column period_start timestamptz,add column period_end timestamptz,
 add foreign key(factory_id,occurrence_key) references private.production_shift_occurrences(factory_id,occurrence_key),
 add constraint scrap_observation_precision check((
 (time_precision='EXACT' and occurred_at is not null and occurrence_key is null and period_start is null and period_end is null)
 or (time_precision='SHIFT_PERIOD' and occurred_at is null and occurrence_key is not null
 and period_start is not null and period_end>=period_start and downtime_id is null)) is true);
alter table public.lean_scrap_events alter column occurred_at drop not null;
create function private.production_observation_period_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare e public.production_entries;begin
 if tg_op='UPDATE' and row(new.factory_id,new.entry_id,new.line_id,new.product_id,new.time_precision,new.occurrence_key,new.period_start,new.period_end)
 is distinct from row(old.factory_id,old.entry_id,old.line_id,old.product_id,old.time_precision,old.occurrence_key,old.period_start,old.period_end)
 then raise exception 'reporting_observation_origin_immutable' using errcode='23514';end if;
 if tg_op='INSERT' and new.time_precision='SHIFT_PERIOD' then
  select * into e from public.production_entries where factory_id=new.factory_id and id=new.entry_id;
  if e.attribution_version is distinct from 1 or e.effective_occurrence_key is distinct from new.occurrence_key
   or e.effective_period_start is distinct from new.period_start or e.effective_period_end is distinct from new.period_end
   or e.line_id is distinct from new.line_id or not exists(select 1 from public.production_orders o where o.factory_id=e.factory_id and o.id=e.order_id and o.product_id=new.product_id)
  then raise exception 'reporting_observation_period_invalid' using errcode='23514';end if;
 end if;
 return new;
end$$;
revoke all on function private.production_observation_period_guard() from public,anon,authenticated;
create trigger production_observation_period_guard before insert or update on public.lean_scrap_events
 for each row execute function private.production_observation_period_guard();

-- Existing entries already own all production facts. This nonmaterialized private
-- projection is shared by history and dated summaries; it is not a stock ledger.
create view private.production_reporting_entries as
select e.*,o.request_id production_request_id,o.product_id,o.code item_code,r.code request_code,
 p.code product_code,p.name product_name,p.name_ar product_name_ar,
 l.name line_name,l.name_ar line_name_ar,tech.display_name technician_name,actor.display_name submitter_name,
 to_jsonb(origin) original_occurrence,to_jsonb(effective) effective_occurrence,
 s.id observation_id,s.time_precision observation_precision,s.occurred_at observation_at,
 s.occurrence_key observation_occurrence_key,s.period_start observation_period_start,s.period_end observation_period_end,
 s.reviewed_at scrap_reviewed_at,
 case when s.id is null then 'UNOBSERVED' when s.reviewed_at is null then 'PENDING' else 'REVIEWED' end scrap_review_status,
 case when s.reviewed_at is not null and s.approved_cause_id is not null then e.effective_scrap_kg end reviewed_scrap_kg,
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
revoke all on private.production_reporting_entries from public,anon,authenticated;

-- Existing production_history is the public contract. Preserve its exact legacy
-- implementation as a private delegate; only explicit reporting_version=3 opts in.
alter function public.production_history(uuid,jsonb,text,text,integer) set schema private;
alter function private.production_history(uuid,jsonb,text,text,integer) rename to production_history_before_m3a;
revoke all on function private.production_history_before_m3a(uuid,jsonb,text,text,integer) from public,anon,authenticated;

-- A single protected read engine supplies paged entries, dated summaries and
-- separately paged correction audits. Nothing is materialized by reading.
create function private.production_reporting_history(f uuid,q jsonb) returns jsonb
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
   'input_lot_id',input_lot_id,'observation',jsonb_build_object('id',observation_id,'status',scrap_review_status,'precision',observation_precision,
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
revoke all on function private.production_reporting_history(uuid,jsonb) from public,anon,authenticated;
create function public.production_history(factory uuid,filters jsonb default '{}',sort_key text default 'date',sort_direction text default 'desc',page integer default 1)
returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 perform private.require_permission(factory,'orders','view');
 if filters ? 'reporting_version' then
  if page is distinct from 1 or sort_key is distinct from 'date' or sort_direction is distinct from 'desc' then raise exception 'reporting_invalid' using errcode='22023';end if;
  return private.production_reporting_history(factory,filters);
 end if;
 return private.production_history_before_m3a(factory,filters,sort_key,sort_direction,page);
end$$;
revoke all on function public.production_history(uuid,jsonb,text,text,integer) from public,anon,authenticated;
grant execute on function public.production_history(uuid,jsonb,text,text,integer) to authenticated;
-- Phase 3C consumers/observation commands remain incomplete. Leave FALSE/0;
-- marking schema 3 ready here would falsely certify those deferred dependencies.
commit;
