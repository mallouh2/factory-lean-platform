begin;
create table private.historical_auto_approval_audit(request_id uuid primary key references private.historical_recording_requests(id),factory_id uuid not null references public.factories(id),authority_user_id uuid not null,membership_id uuid not null references public.memberships(id),authority_permission text not null check(authority_permission='orders:approve'),mechanism text not null default 'SUBMIT_AUTO_APPROVAL'check(mechanism='SUBMIT_AUTO_APPROVAL'),transaction_id bigint not null,at timestamptz not null default clock_timestamp());
alter table private.historical_auto_approval_audit enable row level security;
revoke all on private.historical_auto_approval_audit from public,anon,authenticated;
create function private.historical_auto_approval_immutable()returns trigger language plpgsql set search_path='' as $$begin raise exception 'immutable_audit';end$$;
revoke all on function private.historical_auto_approval_immutable()from public,anon,authenticated;
create trigger historical_auto_approval_immutable before update or delete on private.historical_auto_approval_audit for each row execute function private.historical_auto_approval_immutable();
CREATE OR REPLACE FUNCTION public.historical_production_command(factory uuid, operation text, payload jsonb, request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
   return jsonb_build_object('id',h.id,'factory_id',factory,'state',coalesce((select decision from private.historical_recording_decisions where private.historical_recording_decisions.request_id=h.id),'PENDING'),'receipt',(select d.receipt from private.historical_recording_decisions d where d.request_id=h.id),'approval_mechanism',case when exists(select 1 from private.historical_auto_approval_audit a where a.request_id=h.id)then 'SUBMIT_AUTO_APPROVAL'else 'INDEPENDENT' end);
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
  if private.has_permission(factory,'orders','approve') then
insert into private.historical_auto_approval_audit(request_id,factory_id,authority_user_id,membership_id,authority_permission,transaction_id)
select request_id,factory,auth.uid(),m.id,'orders:approve',txid_current()from public.memberships m where m.factory_id=factory and m.user_id=auth.uid()and m.status='approved';
if not found then raise exception 'permission_denied'using errcode='42501';end if;
return public.historical_production_command(factory,'APPROVE',jsonb_build_object('id',request_id),request_id);
end if;
return jsonb_build_object('id',request_id,'factory_id',factory,'state','PENDING');
 end if;
 perform private.require_permission(factory,'orders','approve');
 if exists(select 1 from jsonb_object_keys(payload) k where k<>'id') then raise exception 'historical_invalid' using errcode='22023';end if;
 select * into h from private.historical_recording_requests where id=(historical_production_command.payload->>'id')::uuid and factory_id=factory for update;
 if not found or(h.submitted_by=auth.uid()and not exists(select 1 from private.historical_auto_approval_audit a where a.request_id=h.id and a.factory_id=factory and a.authority_user_id=auth.uid()and a.transaction_id=txid_current()))then raise exception 'permission_denied'using errcode='42501';end if;
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
 return jsonb_build_object('id',h.id,'factory_id',factory,'state',case operation when 'APPROVE' then 'APPROVED' else 'REJECTED' end,'receipt',receipt,'approval_mechanism',case when exists(select 1 from private.historical_auto_approval_audit a where a.request_id=h.id)then 'SUBMIT_AUTO_APPROVAL'else 'INDEPENDENT' end);
end$function$;
CREATE OR REPLACE FUNCTION private.recording_v3_context(f uuid, i uuid, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare h private.historical_recording_requests;j public.production_orders;e jsonb;begin
 select r.* into h from private.historical_recording_admission a join private.historical_recording_requests r on r.id=a.request_id
 where a.transaction_id=txid_current() and a.approver=auth.uid() and r.factory_id=f and r.item_id=i;
 if not found then return private.current_recording_v3_context(f,i,p);end if;
 perform private.recording_v3_authorize(f);perform private.require_permission(f,'orders','approve');
 if (h.submitted_by=auth.uid()and not exists(select 1 from private.historical_auto_approval_audit a where a.request_id=h.id and a.factory_id=f and a.authority_user_id=auth.uid()and a.transaction_id=txid_current())) or p is distinct from private.recording_request_payload(f,h.payload-'output_groups')->'payload' then raise exception 'permission_denied' using errcode='42501';end if;
 select * into j from public.production_orders where factory_id=f and id=i for update;
 e:=private.historical_recording_eligibility(j,h.occurrence,clock_timestamp());
 if e->>'included' is distinct from 'true' or e->>'context_hash' is distinct from h.context_hash then raise exception 'recording_stale_context' using errcode='40001';end if;
 perform private.materialize_production_occurrence(f,h.occurrence);
 return jsonb_build_object('occurrence',h.occurrence,'eligibility',e,'kind',case when j.actual_finish is null then 'ACTIVE_ORDINARY' else 'LATE_ORDINARY' end,'start',j.actual_start,'finish',j.actual_finish,
 'period_start',greatest(j.actual_start,(h.occurrence->>'starts_at')::timestamptz),'period_end',least(coalesce(j.actual_finish,clock_timestamp()),(h.occurrence->>'ends_at')::timestamptz),'payload',p);
end$function$;
notify pgrst,'reload schema';commit;
