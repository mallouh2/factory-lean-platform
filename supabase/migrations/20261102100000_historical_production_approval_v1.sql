-- Inactive historical reporting approval. No existing activation or data changes.
begin;
create table private.historical_recording_activation(factory_id uuid primary key references public.factories(id),enabled boolean not null default false);
create table private.historical_recording_requests(
 id uuid primary key,factory_id uuid not null references public.factories(id),submitted_by uuid not null references auth.users(id),
 item_id uuid not null,occurrence jsonb not null,context_hash text not null,payload jsonb not null,supersedes uuid references private.historical_recording_requests(id),
 submitted_at timestamptz not null default clock_timestamp(),foreign key(factory_id,item_id) references public.production_orders(factory_id,id));
create table private.historical_recording_decisions(
 request_id uuid primary key references private.historical_recording_requests(id),decision text not null check(decision in('APPROVED','REJECTED')),
 decided_by uuid not null references auth.users(id),decided_at timestamptz not null default clock_timestamp(),command_id uuid not null unique,receipt jsonb);
create table private.historical_recording_admission(transaction_id bigint primary key,request_id uuid not null references private.historical_recording_requests(id),approver uuid not null);
alter table private.historical_recording_activation enable row level security;
alter table private.historical_recording_requests enable row level security;
alter table private.historical_recording_decisions enable row level security;
alter table private.historical_recording_admission enable row level security;
create function private.historical_recording_immutable() returns trigger language plpgsql set search_path='' as $$begin raise exception 'historical_immutable' using errcode='23514';end$$;
create trigger historical_request_immutable before update or delete on private.historical_recording_requests for each row execute function private.historical_recording_immutable();
create trigger historical_decision_immutable before update or delete on private.historical_recording_decisions for each row execute function private.historical_recording_immutable();

-- Reuse the frozen execution/plan/context evidence calculation. Only the
-- current-clock-in-occurrence requirement differs for an engineer review.
do $migration$declare definition text;begin
 definition:=pg_get_functiondef('private.production_recording_eligibility(public.production_orders,jsonb,timestamptz)'::regprocedure);
 if position('evaluated<(occurrence->>''starts_at'')' in definition)=0 then raise exception 'historical_eligibility_contract';end if;
 definition:=replace(definition,'private.production_recording_eligibility(','private.historical_recording_eligibility(');
 definition:=replace(definition,' or evaluated<(occurrence->>''starts_at'')::timestamptz or evaluated>=(occurrence->>''ends_at'')::timestamptz','');
 execute definition;
end$migration$;

create function private.historical_recording_occurrences(f uuid,day date default null) returns setof jsonb language plpgsql stable security definer set search_path='' as $$
declare r private.production_shift_schedule_revisions;s jsonb;o jsonb;resolved jsonb;d date;today date;begin
 select (clock_timestamp() at time zone timezone)::date into today from public.factories where id=f;
 if day is not null and (day>today or day<today-366) then raise exception 'historical_date' using errcode='22023';end if;
 for d in select generate_series(coalesce(day,today-7),coalesce(day,today),'1 day')::date loop
  for r in select * from private.production_shift_schedule_revisions where factory_id=f loop
   for s in select value from jsonb_array_elements(r.definitions) where not(value->>'archived')::boolean and value->>'start_time' is not null loop
    begin o:=private.shift_occurrence_descriptor(r,s,d);exception when sqlstate '22023' then continue;end;
    if (o->>'ends_at')::timestamptz>clock_timestamp() or (o->>'starts_at')::timestamptz<r.effective_from then continue;end if;
    resolved:=private.resolve_production_occurrence(f,(o->>'starts_at')::timestamptz+interval '1 microsecond');
    if resolved->>'available'='true' and resolved#>>'{occurrence,occurrence_key}'=o->>'occurrence_key' then return next o;end if;
   end loop;
  end loop;
 end loop;
end$$;

create function public.historical_production_read(factory uuid,day date default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare enabled boolean;choices jsonb;requests jsonb;approver boolean;begin
 perform private.require_permission(factory,'orders','view');
 select a.enabled into enabled from private.historical_recording_activation a where factory_id=factory;
 if enabled is distinct from true or not private.manufactured_output_enabled(factory) then return jsonb_build_object('factory_id',factory,'available',false,'choices','[]'::jsonb,'requests','[]'::jsonb);end if;
 approver:=private.has_permission(factory,'orders','approve');
 select coalesce(jsonb_agg(row order by row#>>'{occurrence,ends_at}' desc),'[]'::jsonb) into choices from(
  select jsonb_build_object('occurrence',o,'work',jsonb_agg(jsonb_build_object('item',j.id,'code',j.code,'product',p.name,'product_ar',p.name_ar,'unit',j.unit,'remaining',greatest(j.target_quantity-j.fulfillment_good_quantity,0)::text,'line',j.line_id,'line_name',l.name,'actual_start',j.actual_start,'actual_finish',j.actual_finish,'eligibility',e))) row
  from (select distinct v as o from private.historical_recording_occurrences(factory,day)v)occ
  join public.production_orders j on j.factory_id=factory and j.actual_start<(o->>'ends_at')::timestamptz and coalesce(j.actual_finish,clock_timestamp())>(o->>'starts_at')::timestamptz
  join public.products p on p.factory_id=factory and p.id=j.product_id join public.production_lines l on l.factory_id=factory and l.id=j.line_id
  cross join lateral private.historical_recording_eligibility(j,o,clock_timestamp()) e
  where e->>'included'='true' and not exists(select 1 from private.manufactured_completion_work w where w.factory_id=factory and w.item_id=j.id and w.choice='COMPLETE') group by o
 )a;
 select coalesce(jsonb_agg(row order by submitted_at desc),'[]'::jsonb) into requests from(
  select r.submitted_at,jsonb_build_object('id',r.id,'factory_id',r.factory_id,'submitted_by',r.submitted_by,'operator',m.display_name,'item',r.item_id,'code',j.code,'product',p.name,'unit',j.unit,'occurrence',r.occurrence,'payload',r.payload,'submitted_at',r.submitted_at,'state',coalesce(d.decision,'PENDING'),'receipt',d.receipt,'can_approve',approver and r.submitted_by<>auth.uid() and d.request_id is null) row
  from private.historical_recording_requests r join public.production_orders j on j.factory_id=factory and j.id=r.item_id
  join public.products p on p.factory_id=factory and p.id=j.product_id join public.memberships m on m.factory_id=factory and m.user_id=r.submitted_by
  left join private.historical_recording_decisions d on d.request_id=r.id where r.factory_id=factory and (r.submitted_by=auth.uid() or approver) order by r.submitted_at desc limit 100
 )a;
 return jsonb_build_object('factory_id',factory,'available',true,'choices',choices,'requests',requests);
end$$;

-- Internal transaction capability: no client flag, GUC or selected technician
-- can grant historical admission. The command below alone inserts this row.
create function private.historical_admitted(f uuid,r uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.historical_recording_admission a join private.historical_recording_requests h on h.id=a.request_id
 where a.transaction_id=txid_current() and a.approver=auth.uid() and h.factory_id=f and h.id=r)
$$;
alter function private.recording_v3_context(uuid,uuid,jsonb) rename to current_recording_v3_context;
create function private.recording_v3_context(f uuid,i uuid,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare h private.historical_recording_requests;j public.production_orders;e jsonb;begin
 select r.* into h from private.historical_recording_admission a join private.historical_recording_requests r on r.id=a.request_id
 where a.transaction_id=txid_current() and a.approver=auth.uid() and r.factory_id=f and r.item_id=i;
 if not found then return private.current_recording_v3_context(f,i,p);end if;
 perform private.recording_v3_authorize(f);perform private.require_permission(f,'orders','approve');
 if h.submitted_by=auth.uid() or p is distinct from private.recording_request_payload(f,h.payload-'output_groups')->'payload' then raise exception 'permission_denied' using errcode='42501';end if;
 select * into j from public.production_orders where factory_id=f and id=i for update;
 e:=private.historical_recording_eligibility(j,h.occurrence,clock_timestamp());
 if e->>'included' is distinct from 'true' or e->>'context_hash' is distinct from h.context_hash then raise exception 'recording_stale_context' using errcode='40001';end if;
 perform private.materialize_production_occurrence(f,h.occurrence);
 return jsonb_build_object('occurrence',h.occurrence,'eligibility',e,'kind',case when j.actual_finish is null then 'ACTIVE_ORDINARY' else 'LATE_ORDINARY' end,'start',j.actual_start,'finish',j.actual_finish,
 'period_start',greatest(j.actual_start,(h.occurrence->>'starts_at')::timestamptz),'period_end',least(coalesce(j.actual_finish,clock_timestamp()),(h.occurrence->>'ends_at')::timestamptz),'payload',p);
end$$;

-- Preserve all ordinary deadlines and receipt checks. Only a protected
-- approval transaction, or its immutable saved decision, admits past periods.
do $migration$declare definition text;begin
 definition:=pg_get_functiondef('private.record_lean_production(uuid,jsonb,uuid)'::regprocedure);
 if position('if context is not null and (stamp<' in definition)=0 or position('if context is not null and clock_timestamp()>=' in definition)=0 then raise exception 'historical_writer_contract';end if;
 definition:=replace(definition,'if context is not null and (stamp<','if context is not null and not private.historical_admitted(f,r) and (stamp<');
 definition:=replace(definition,'if context is not null and clock_timestamp()>=','if context is not null and not private.historical_admitted(f,r) and clock_timestamp()>=');execute definition;

 definition:=pg_get_functiondef('public.record_manufactured_output(uuid,jsonb,uuid)'::regprocedure);
 if position('if clock_timestamp()>=(context#>>' in definition)=0 then raise exception 'historical_output_contract';end if;
 definition:=replace(definition,'if clock_timestamp()>=(context#>>','if not private.historical_admitted(factory,request_id) and clock_timestamp()>=(context#>>');execute definition;

 definition:=pg_get_functiondef((select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='record_production' and p.pronargs=18));
 if position('if attribution->>''kind'' is distinct from ''LATE_ORDINARY''' in definition)=0 then raise exception 'historical_stock_worker_contract';end if;
 definition:=replace(definition,'if attribution->>''kind'' is distinct from ''LATE_ORDINARY''','if not private.historical_admitted(f,r) and attribution->>''kind'' is distinct from ''LATE_ORDINARY''');execute definition;
 definition:=pg_get_functiondef('private.recording_receipt_finalized()'::regprocedure);
 if position('or e.accepted_at<o.starts_at or e.accepted_at>=o.ends_at' in definition)=0 then raise exception 'historical_receipt_contract';end if;
 definition:=replace(definition,'or e.accepted_at<o.starts_at or e.accepted_at>=o.ends_at',
 'or ((e.accepted_at<o.starts_at or e.accepted_at>=o.ends_at) and not private.historical_admitted(e.factory_id,e.request_id) and not exists(select 1 from private.historical_recording_requests h join private.historical_recording_decisions d on d.request_id=h.id where h.factory_id=e.factory_id and h.id=e.request_id and d.decision=''APPROVED'' and d.receipt->>''entry_id''=e.id::text))');execute definition;
end$migration$;

create function public.historical_production_command(factory uuid,operation text,payload jsonb,request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare h private.historical_recording_requests;decision_record private.historical_recording_decisions;j public.production_orders;o jsonb;e jsonb;p jsonb;previous uuid;enabled boolean;receipt jsonb;groups jsonb;operations jsonb;begin
 if request_id is null or operation not in('SUBMIT','APPROVE','REJECT') or payload is null or jsonb_typeof(payload)<>'object' or octet_length(payload::text)>16384 then raise exception 'historical_invalid' using errcode='22023';end if;
 perform private.recording_v3_authorize(factory);
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform pg_advisory_xact_lock(hashtextextended(factory::text||':structure',0));
 select a.enabled into enabled from private.historical_recording_activation a where factory_id=factory for share;
 if enabled is distinct from true then raise exception 'historical_disabled' using errcode='42501';end if;
 perform private.recording_v3_authorize(factory);
 if operation='SUBMIT' then
  if exists(select 1 from jsonb_object_keys(payload) k where k not in('occurrence_key','business_date','measurement','supersedes')) or jsonb_typeof(payload->'measurement') is distinct from 'object' then raise exception 'historical_invalid' using errcode='22023';end if;
  p:=payload->'measurement';
  select * into h from private.historical_recording_requests where id=request_id;
  if found then
   if h.factory_id<>factory or h.submitted_by<>auth.uid() or h.payload is distinct from p or h.occurrence->>'occurrence_key' is distinct from payload->>'occurrence_key' or h.supersedes is distinct from (payload->>'supersedes')::uuid then raise exception 'request_conflict' using errcode='40001';end if;
   return jsonb_build_object('id',h.id,'factory_id',factory,'state',coalesce((select decision from private.historical_recording_decisions where private.historical_recording_decisions.request_id=h.id),'PENDING'));
  end if;
  select * into j from public.production_orders where factory_id=factory and id=(p->>'item')::uuid for update;
  if not found then raise exception 'permission_denied' using errcode='42501';end if;
  -- Historical recovery consumption needs separately proven historical issue
  -- eligibility. Do not reinterpret today's issued material as past input.
  if exists(select 1 from private.manufactured_completion_work w where w.factory_id=factory and w.item_id=j.id and w.choice='COMPLETE') or p->>'input_lot' is not null or coalesce((p->>'input_quantity')::numeric,0)<>0 or p->>'startup_id' is not null then raise exception 'historical_source_unverified' using errcode='22023';end if;
  select v into o from private.historical_recording_occurrences(factory,(payload->>'business_date')::date)v where v->>'occurrence_key'=payload->>'occurrence_key' limit 1;
  if o is null then raise exception 'historical_occurrence' using errcode='22023';end if;
  e:=private.historical_recording_eligibility(j,o,clock_timestamp());
  if e->>'included' is distinct from 'true' or p->>'unit_kind' is distinct from 'line' or p->>'production_unit' is distinct from j.line_id::text
  or not exists(select 1 from public.memberships where factory_id=factory and user_id=auth.uid() and id=(p->>'technician')::uuid and status='approved') then raise exception 'permission_denied' using errcode='42501';end if;
  perform private.recording_request_payload(factory,p-'output_groups');
  select coalesce(jsonb_object_agg(id::text,to_jsonb(s)),'{}') into operations from public.production_routing_steps s where s.factory_id=factory and s.product_id=j.product_id;
  groups:=private.manufactured_output_groups(p->'output_groups',operations,j.unit,false);
  if coalesce((select sum((g->>'quantity')::numeric) from jsonb_array_elements(groups)g where jsonb_array_length(g->'missing_operations')=0),0)<>coalesce((p->>'good')::numeric,0)
  or coalesce((select sum((g->>'quantity')::numeric) from jsonb_array_elements(groups)g where jsonb_array_length(g->'missing_operations')>0),0)<>coalesce((p->>'unfinished')::numeric,0)
  or coalesce((p->>'discarded_quantity')::numeric,0)<>0 then raise exception 'output_quantity' using errcode='22023';end if;
  if p#>>'{recording_context,execution_key}' is distinct from e->>'execution_key' or p#>>'{recording_context,context_hash}' is distinct from e->>'context_hash' or p#>>'{recording_context,occurrence_key}' is distinct from o->>'occurrence_key' then raise exception 'recording_stale_context' using errcode='40001';end if;
  if j.fulfillment_good_quantity+coalesce((p->>'good')::numeric,0)>j.target_quantity and not coalesce((p->>'confirm_overproduction')::boolean,false) then raise exception 'recording_overproduction_confirmation' using errcode='22023';end if;
  if coalesce((p->>'good')::numeric,0)+coalesce((p->>'unfinished')::numeric,0)+coalesce((p->>'scrap_kg')::numeric,0)<=0 then raise exception 'historical_invalid' using errcode='22023';end if;
  if exists(select 1 from private.historical_recording_requests r where r.factory_id=factory and r.item_id=j.id and r.submitted_by=auth.uid() and r.occurrence->>'occurrence_key'=o->>'occurrence_key' and not exists(select 1 from private.historical_recording_decisions d where d.request_id=r.id)) then raise exception 'historical_pending' using errcode='40001';end if;
  previous:=(payload->>'supersedes')::uuid;
  if previous is not null and not exists(select 1 from private.historical_recording_requests r join private.historical_recording_decisions d on d.request_id=r.id where r.id=previous and r.factory_id=factory and r.submitted_by=auth.uid() and r.item_id=j.id and d.decision='REJECTED') then raise exception 'historical_revision' using errcode='22023';end if;
  insert into private.historical_recording_requests(id,factory_id,submitted_by,item_id,occurrence,context_hash,payload,supersedes) values(request_id,factory,auth.uid(),j.id,o,e->>'context_hash',p,previous);
  return jsonb_build_object('id',request_id,'factory_id',factory,'state','PENDING');
 end if;
 perform private.require_permission(factory,'orders','approve');
 if exists(select 1 from jsonb_object_keys(payload) k where k<>'id') then raise exception 'historical_invalid' using errcode='22023';end if;
 select * into h from private.historical_recording_requests where id=(historical_production_command.payload->>'id')::uuid and factory_id=factory for update;
 if not found or h.submitted_by=auth.uid() then raise exception 'permission_denied' using errcode='42501';end if;
 select * into decision_record from private.historical_recording_decisions where private.historical_recording_decisions.request_id=h.id;
 if found then
  if decision_record.command_id=request_id and decision_record.decided_by=auth.uid() and decision_record.decision=(case operation when 'APPROVE' then 'APPROVED' else 'REJECTED' end) then return jsonb_build_object('id',h.id,'factory_id',factory,'state',decision_record.decision,'receipt',decision_record.receipt);end if;
  raise exception 'historical_decided' using errcode='40001';
 end if;
 if operation='APPROVE' then
  select * into j from public.production_orders where factory_id=factory and id=h.item_id for update;
  if not private.has_permission(factory,'orders','edit') or not exists(select 1 from private.effective_person_permissions(factory,h.submitted_by) where module='orders' and action='edit') or not exists(select 1 from public.memberships where factory_id=factory and user_id=h.submitted_by and status='approved') then raise exception 'permission_denied' using errcode='42501';end if;
  e:=private.historical_recording_eligibility(j,h.occurrence,clock_timestamp());
  if e->>'included' is distinct from 'true' or e->>'context_hash' is distinct from h.context_hash then raise exception 'recording_stale_context' using errcode='40001';end if;
  insert into private.historical_recording_admission values(txid_current(),h.id,auth.uid());
  if jsonb_array_length(h.payload->'output_groups')=0 then
   -- Measured Scrap only has no storable output to declare or receive.
   receipt:=public.record_lean_production(factory,h.payload-'output_groups',h.id);
  else receipt:=public.record_manufactured_output(factory,h.payload,h.id);end if;
 end if;
 insert into private.historical_recording_decisions values(h.id,case operation when 'APPROVE' then 'APPROVED' else 'REJECTED' end,auth.uid(),clock_timestamp(),request_id,receipt);
 delete from private.historical_recording_admission where transaction_id=txid_current();
 return jsonb_build_object('id',h.id,'factory_id',factory,'state',case operation when 'APPROVE' then 'APPROVED' else 'REJECTED' end,'receipt',receipt);
end$$;
revoke all on private.historical_recording_activation,private.historical_recording_requests,private.historical_recording_decisions,private.historical_recording_admission from anon,authenticated;
revoke all on function private.historical_recording_immutable(),private.historical_recording_eligibility(public.production_orders,jsonb,timestamptz),private.historical_recording_occurrences(uuid,date),private.historical_admitted(uuid,uuid),private.recording_v3_context(uuid,uuid,jsonb),private.current_recording_v3_context(uuid,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.historical_production_read(uuid,date),public.historical_production_command(uuid,text,jsonb,uuid) from public,anon;
grant execute on function public.historical_production_read(uuid,date),public.historical_production_command(uuid,text,jsonb,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
