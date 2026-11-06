-- Ordinary same-shift reporting remains open after execution Finish.
-- No activation, historical migration edit, execution change or posting rewrite.
begin;
create or replace function private.production_recording_eligibility(job public.production_orders,occurrence jsonb,evaluated timestamptz)
returns jsonb language plpgsql stable security definer set search_path='' set timezone='UTC' as $$
declare reason text;k text;planned_line uuid;live boolean;evidence_count bigint;begin
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
 k:=case when job.actual_start is not null and job.line_id is not null then encode(sha256(convert_to(jsonb_build_array(1,job.factory_id,job.id,job.line_id,to_char(job.actual_start,'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))::text,'UTF8')),'hex') end;
 -- Bind every new recording, including zero-Good Scrap/unfinished declarations.
 -- Item/factory locks serialize admission; exact UUID replay precedes this check.
 select count(*) into evidence_count from public.production_entries where factory_id=job.factory_id and order_id=job.id;
 live:=false;
 if reason is null and job.status='active' then
  live:=exists(select 1 from private.production_recording_units(job.factory_id) u where u.unit_kind='line' and u.unit_id=job.line_id and u.item_id=job.id);
 end if;
 return jsonb_build_object('included',reason is null,'preview_selectable',reason is null,'execution_key',k,
  'policy_late_eligible',reason is null and job.status='completed','active_recording_eligible',coalesce(live,false),
  'late_recording_available',false,'blocked_reason',coalesce(reason,case when job.status='completed' then 'PHASE1_READ_ONLY' when not live then 'ACTIVE_UNIT_UNAVAILABLE' end),
  'resource_evidence',jsonb_build_object('line','PROTECTED_PLAN_EXECUTION','machines','UNKNOWN'),
  'context_hash',encode(sha256(convert_to(jsonb_build_array(1,job.factory_id,job.id,job.product_id,job.line_id,job.actual_start,job.actual_finish,job.status,job.unit,job.target_quantity,job.accepted_good_quantity,job.fulfillment_good_quantity,occurrence->>'occurrence_key',live,evidence_count)::text,'UTF8')),'hex'));
end$$;


create or replace function private.recording_v3_context(f uuid,i uuid,p jsonb) returns jsonb language plpgsql volatile security definer set search_path='' set timezone='UTC' as $$
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
 stamp:=clock_timestamp();resolved:=private.resolve_production_occurrence(f,stamp);occ:=resolved->'occurrence';
 if resolved->>'available' is distinct from 'true' then raise exception 'recording_shift_unavailable' using errcode='22023';end if;
 eligible:=private.production_recording_eligibility(job,occ,stamp);
 if eligible->>'included' is distinct from 'true' or (not late and eligible->>'active_recording_eligible' is distinct from 'true')
 or p#>>'{recording_context,execution_key}' is distinct from eligible->>'execution_key'
 or p#>>'{recording_context,occurrence_key}' is distinct from occ->>'occurrence_key'
 or p#>>'{recording_context,context_hash}' is distinct from eligible->>'context_hash'
 or p->>'unit_kind' is distinct from 'line' or (p->>'production_unit')::uuid is distinct from job.line_id
 then raise exception 'recording_stale_context' using errcode='40001';end if;
 if job.actual_start<(occ->>'starts_at')::timestamptz and p#>>'{recording_context,current_shift_quantity_confirmed}' is distinct from 'true'
 then raise exception 'recording_shift_declaration' using errcode='22023';end if;
 if p->>'shift' is not null and (p->>'shift')::uuid is distinct from (occ->>'shift_id')::uuid or p->>'shift_override_reason' is not null
 then raise exception 'recording_invalid_context' using errcode='22023';end if;
 if p->>'startup_at' is not null and ((p->>'startup_at')::timestamptz<greatest(job.actual_start,(occ->>'starts_at')::timestamptz)
 or (p->>'startup_at')::timestamptz>coalesce(job.actual_finish,stamp)) then raise exception 'lean_invalid' using errcode='22023';end if;
 perform private.materialize_production_occurrence(f,occ);
 return jsonb_build_object('occurrence',occ,'eligibility',eligible,'kind',case when late then 'LATE_ORDINARY' else 'ACTIVE_ORDINARY' end,
 'start',job.actual_start,'finish',job.actual_finish,'period_start',greatest(job.actual_start,(occ->>'starts_at')::timestamptz),
 'period_end',least(coalesce(job.actual_finish,stamp),(occ->>'ends_at')::timestamptz),'payload',p);
end$$;


create or replace function public.production_shift_work(factory uuid,cursor jsonb default null,page_size integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' set timezone='UTC' as $$
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
   'line_id',l.id,'line_name',l.name,'line_name_ar',l.name_ar,'actual_start',(s.o).actual_start,'actual_finish',(s.o).actual_finish,'status',(s.o).status,
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
 join public.production_lines l on l.factory_id=factory and l.id=(s.o).line_id
 left join public.production_requests r on r.factory_id=factory and r.id=(s.o).request_id;
 return ctx||jsonb_build_object('contract_version',3,'factory_id',factory,'server_as_of',stamp,'evaluation_as_of',evaluated,'expires_at',occ->'ends_at',
  'dataset_revision',rev,'schedule_revision',schedule_rev,'context',context_key,'can_edit',can_edit,
  'rows',rows,'total',total,'page_size',page_size,'next_cursor',next_page,'complete',next_page is null,'late_recording_available',late_available);
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then raise exception 'shift_work_invalid' using errcode='22023';
end$$;
-- Existing invoker grants remain unchanged. Helpers stay private.
revoke all on function private.production_recording_eligibility(public.production_orders,jsonb,timestamptz),private.recording_v3_context(uuid,uuid,jsonb) from public,anon,authenticated;
commit;
