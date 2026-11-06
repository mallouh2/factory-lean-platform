-- Publish the existing M2 per-factory gate through the protected M1 reader.
-- No activation, posting, permission, execution or historical evidence changes.
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
 -- Publication only: the existing writer still locks/rechecks this gate and live deadline.
 select coalesce((select enabled and schema_contract_version=3 from private.production_recording_v3_activation where factory_id=factory),false)
  and can_edit and coalesce((ctx->>'available')::boolean,false) into late_available;
 context_key:=encode(sha256(convert_to(jsonb_build_array(2,factory,auth.uid(),occ->>'occurrence_key',evaluated,rev,schedule_rev,page_size,can_edit,late_available)::text,'UTF8')),'hex');
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
   'can_record',can_edit and ((s.eligibility->>'active_recording_eligible')::boolean or (late_available and (s.eligibility->>'policy_late_eligible')::boolean)),'recent_entry_scope',jsonb_build_object('item_id',(s.o).id,'line_id',l.id,'occurrence_key',occ->>'occurrence_key'))||s.eligibility||jsonb_build_object(
   'late_recording_available',late_available and (s.eligibility->>'policy_late_eligible')::boolean,
   'blocked_reason',case when (s.eligibility->>'policy_late_eligible')::boolean then case when late_available then null else 'RECORDING_DISABLED' end else s.eligibility->>'blocked_reason' end)
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

