-- Inactive B1: one fully received finished share -> one separately released
-- unfinished handoff. No allocated group changes, physical undo or new ledger.
begin;
alter table private.manufactured_output_events drop constraint manufactured_output_events_operation_check;
alter table private.manufactured_output_events add check(operation in ('DECLARE','QUALITY','RECEIPT','DISPOSITION','ACKNOWLEDGE','CORRECTION','RETIRE','RECONCILE'));
alter table private.manufactured_output_events drop constraint manufactured_output_events_check;
alter table private.manufactured_output_events add check(
 (operation='RECEIPT' and num_nonnulls(finished_movement_id,unfinished_movement_id)=1)
 or (operation='RECONCILE' and finished_movement_id is not null and unfinished_movement_id is null)
 or (operation not in ('RECEIPT','RECONCILE') and num_nonnulls(finished_movement_id,unfinished_movement_id)=0));
alter table private.manufactured_output_events add check(operation<>'RECONCILE' or
 (result ?& array['finding_id','finding_revision','from_group','handoff_group','quantity','resolved_groups'] and (result->>'quantity')::numeric>0 and finished_movement_id is not null));
create unique index output_finding_reconciled_once on private.manufactured_output_events(factory_id,(result->>'finding_id')) where operation='RECONCILE';
alter table private.manufactured_output_context drop constraint manufactured_output_context_mode_check;
alter table private.manufactured_output_context add check(mode in ('RECORD','CORRECTION','RECEIPT','RECONCILE','WORK','ISSUE','REVISION','APPLY_FINDING'));

create function private.output_finding_pending(f uuid,finding uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.manufactured_output_events e where e.factory_id=f and e.id=finding and e.operation='QUALITY' and e.result->>'accounting_applied'='false'
 and (not exists(select 1 from private.manufactured_output_events r where r.factory_id=f and r.operation='RECONCILE' and r.result->>'finding_id'=e.id::text)
 or exists(select 1 from private.manufactured_output_events r where r.factory_id=f and r.operation='RECONCILE' and r.result->>'finding_id'=e.id::text
 and private.output_received(f,r.output_id,r.result->>'handoff_group')<(r.result->>'quantity')::numeric)))
$$;
create or replace function private.output_quality(f uuid,o uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select q from (
 select e.revision,e.result q,e.revision finding_revision from private.manufactured_output_events e where e.factory_id=f and e.output_id=o and e.operation='QUALITY' and e.result->>'accounting_applied' is distinct from 'false'
 union all
 select r.revision,e.result||jsonb_build_object('accounting_applied',true,'applied_quality_revision',e.revision::text,
 'reconciliation_pending',private.output_finding_pending(f,e.id),'application_stage',case when private.output_finding_pending(f,e.id) then 'WITHDRAWN_AWAITING_RECEIPT' else 'RECONCILED' end),e.revision
 from private.manufactured_output_events r join private.manufactured_output_events e on e.factory_id=r.factory_id and e.id=(r.result->>'finding_id')::uuid and e.output_id=r.output_id and e.operation='QUALITY'
 where r.factory_id=f and r.output_id=o and r.operation='RECONCILE'
 ) applied where finding_revision>coalesce((select max(revision) from private.manufactured_output_events where factory_id=f and output_id=o and operation='CORRECTION'),0)
 order by revision desc limit 1
$$;

create or replace function private.output_hold_rows(f uuid)
returns table(output_id uuid,group_id uuid,finished boolean,finding_revision bigint)
language sql stable security definer set search_path='' as $$
 with recursive seeds as (
 select e.output_id,(g->>'id')::uuid group_id,(g->>'finished')::boolean finished,e.revision finding_revision
 from private.manufactured_output_events e cross join lateral jsonb_array_elements(e.result->'holds') g
 where e.factory_id=f and e.operation='QUALITY' and e.result->>'accounting_applied'='false'
 and not exists(select 1 from private.manufactured_output_events r where r.factory_id=f and r.operation='RECONCILE'
 and r.result->>'finding_id'=e.id::text and r.result->'resolved_groups' ? (g->>'id'))
 union
 select r.output_id,(r.result->>'handoff_group')::uuid,false,(r.result->>'finding_revision')::bigint
 from private.manufactured_output_events r where r.factory_id=f and r.operation='RECONCILE'
 and private.output_received(f,r.output_id,r.result->>'handoff_group')<(r.result->>'quantity')::numeric
 ), held(output_id,group_id,finished,finding_revision) as (
 select * from seeds
 union
 select h.id,(g->>'id')::uuid,jsonb_array_length(g->'missing_operations')=0,r.finding_revision
 from held r join private.manufactured_completion_work w on w.factory_id=f and w.output_id=r.output_id and w.group_id=r.group_id
 join private.manufactured_outputs h on h.factory_id=f and h.item_id=w.item_id
 cross join lateral jsonb_array_elements(coalesce(private.output_quality(f,h.id)->'groups',h.recorded_groups)) g
 ) select * from held
$$;

-- A deliberately narrow delta validator. Whole, unchanged old groups retain
-- their identities/allocations; only one finished group decreases, exactly
-- matching one new, fully released, unfinished group. Other cases stay held.
create function private.output_reconciliation_spec(f uuid,o uuid,finding uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare h private.manufactured_outputs;e private.manufactured_output_events;applied jsonb;oldg jsonb;g jsonb;added jsonb;from_group jsonb;amount numeric;changed integer:=0;begin
 select * into h from private.manufactured_outputs where factory_id=f and id=o;
 select * into e from private.manufactured_output_events where factory_id=f and output_id=o and id=finding and operation='QUALITY';
 if h.id is null or e.id is null then raise exception 'output_not_found';end if;
 if private.output_finding(f,o)->>'revision' is distinct from e.revision::text then raise exception 'output_finding_stale';end if;
 if exists(select 1 from private.manufactured_output_events r where r.factory_id=f and r.operation='RECONCILE' and r.result->>'finding_id'=finding::text) then raise exception 'output_reconciliation_applied';end if;
 if e.result->>'accounting_applied' is distinct from 'false' then raise exception 'output_reconciliation_not_pending';end if;
 if exists(select 1 from private.manufactured_output_events other where other.factory_id=f and other.output_id=o and other.id<>finding and other.operation='QUALITY' and private.output_finding_pending(f,other.id)) then raise exception 'output_reconciliation_multiple_findings';end if;
 if private.output_work_held(f,h.item_id) then raise exception 'output_parent_held';end if;
 if ((e.result->'source')-array['technician_id','recorded_at']) is distinct from private.production_correction_values(f,h.entry_id) then raise exception 'output_reinspection_required';end if;
 applied:=private.output_quality(f,o);
 if applied is null or applied->>'rejected' is distinct from e.result->>'rejected' then raise exception 'output_reconciliation_scope';end if;
 for oldg in select value from jsonb_array_elements(applied->'groups') loop
  select value into g from jsonb_array_elements(e.result->'groups') where value->>'id'=oldg->>'id';
  if g=oldg then continue;end if;
  if g is null and jsonb_array_length(oldg->'missing_operations')=0 then g:=oldg||'{"quantity":"0","released":"0"}'::jsonb;end if;
  if g is null or jsonb_array_length(oldg->'missing_operations')<>0 or g->'missing_operations'<>oldg->'missing_operations'
   or g->>'restriction' is distinct from oldg->>'restriction' then raise exception 'output_reconciliation_allocation_scope';end if;
  if (oldg->>'released')::numeric<>(oldg->>'quantity')::numeric or private.output_received(f,o,oldg->>'id')<>(oldg->>'quantity')::numeric
   or (g->>'released')::numeric<>(g->>'quantity')::numeric or (g->>'quantity')::numeric>=(oldg->>'quantity')::numeric then raise exception 'output_reconciliation_receipt_scope';end if;
  changed:=changed+1;from_group:=oldg;amount:=(oldg->>'quantity')::numeric-(g->>'quantity')::numeric;
 end loop;
 if changed<>1 or (select count(*) from jsonb_array_elements(e.result->'groups') n where not exists(select 1 from jsonb_array_elements(applied->'groups') a where a->>'id'=n->>'id'))<>1 then raise exception 'output_reconciliation_scope';end if;
 select value into added from jsonb_array_elements(e.result->'groups') n(value) where not exists(select 1 from jsonb_array_elements(applied->'groups') a where a->>'id'=n.value->>'id');
 if jsonb_array_length(added->'missing_operations')=0 or (added->>'quantity')::numeric<>amount then raise exception 'output_reconciliation_scope';end if;
 if (added->>'released')::numeric<>amount then raise exception 'output_reconciliation_release_required';end if;
 if exists(select 1 from private.manufactured_output_lots where factory_id=f and output_id=o and group_id::text=added->>'id') or private.output_received(f,o,added->>'id')<>0 then raise exception 'output_reconciliation_receipt_scope';end if;
 return jsonb_build_object('finding_id',finding,'finding_revision',e.revision::text,'previous_applied_revision',applied->>'revision',
 'from_group',from_group->>'id','handoff_group',added->>'id','quantity',trim_scale(amount)::text,'resolved_groups',jsonb_build_array(from_group->>'id'));
end$$;

create function private.output_reconcile_context(f uuid,o uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.manufactured_output_context c join private.manufactured_output_events e on e.factory_id=c.factory_id and e.id=c.request_id and e.operation='QUALITY'
 join private.manufactured_outputs h on h.factory_id=e.factory_id and h.id=e.output_id and h.entry_id=c.entry_id
 where c.backend=pg_backend_pid() and c.transaction_id=txid_current() and c.factory_id=f and c.actor_id=auth.uid() and c.mode='APPLY_FINDING' and h.id=o)
$$;
create function private.output_reconcile_pick_allowed(f uuid,entry uuid,kind text,delta numeric,source uuid) returns boolean
language plpgsql stable security definer set search_path='' as $$declare c private.manufactured_output_context;o uuid;spec jsonb;begin
 select * into c from private.manufactured_output_context where backend=pg_backend_pid() and transaction_id=txid_current() and factory_id=f and actor_id=auth.uid() and entry_id=entry and mode='APPLY_FINDING';
 if c.backend is null or kind<>'quality_rejection' then return false;end if;
 select id into o from private.manufactured_outputs where factory_id=f and entry_id=entry;
 if not private.output_reconcile_context(f,o) or not exists(select 1 from public.finished_goods_sources where factory_id=f and id=source and entry_id=entry) then return false;end if;
 spec:=private.output_reconciliation_spec(f,o,c.request_id);
 return delta=-(spec->>'quantity')::numeric;
end$$;

create function public.reconcile_manufactured_output(factory uuid,target uuid,finding uuid,payload jsonb,expected_revision bigint,request_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare h private.manufactured_outputs;e private.manufactured_output_events;prior private.manufactured_output_events;src public.finished_goods_sources;
 spec jsonb;intent jsonb;result jsonb;rev bigint;m uuid;amount numeric;begin
 if current_setting('transaction_isolation')<>'read committed' then raise exception 'output_isolation';end if;
 perform private.manufactured_output_authorize(factory,'RECEIPT',expected_revision);perform private.require_permission(factory,'warehouse','view');
 if target is null or finding is null or request_id is null or expected_revision is null or expected_revision<1 or jsonb_typeof(payload) is distinct from 'object'
 or not payload ?& array['source_id','physical_confirmation','reason'] or exists(select 1 from jsonb_object_keys(payload) k where k not in ('source_id','physical_confirmation','reason'))
 or payload->'physical_confirmation' is distinct from 'true'::jsonb or length(btrim(coalesce(payload->>'reason',''))) not between 3 and 2000 then raise exception 'output_physical_confirmation';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.fulfillment_lock(factory);
 perform private.manufactured_output_authorize(factory,'RECEIPT',expected_revision);perform private.require_permission(factory,'warehouse','view');
 if not private.manufactured_output_enabled(factory) then raise exception 'recording_disabled';end if;
 intent:=jsonb_build_object('target',target,'finding_id',finding,'payload',payload,'expected',expected_revision);
 select * into prior from private.manufactured_output_events ev where ev.factory_id=factory and ev.request_id=reconcile_manufactured_output.request_id;
 if found then if prior.operation<>'RECONCILE' or prior.created_by<>auth.uid() or prior.intent<>intent then raise exception 'request_conflict';end if;return prior.result;end if;
 select * into h from private.manufactured_outputs where factory_id=factory and id=target for update;
 if h.id is null then raise exception 'output_not_found';end if;
 select max(revision) into rev from private.manufactured_output_events where factory_id=factory and output_id=target;
 if rev<>expected_revision then raise exception 'output_revision';end if;
 select * into e from private.manufactured_output_events where factory_id=factory and output_id=target and id=finding and operation='QUALITY';
 if e.id is null then raise exception 'output_not_found';end if;
 if request_id in (e.request_id,e.id) then raise exception 'request_conflict';end if;
 spec:=private.output_reconciliation_spec(factory,target,finding);amount:=(spec->>'quantity')::numeric;
 select * into src from public.finished_goods_sources where factory_id=factory and id=(payload->>'source_id')::uuid and entry_id=h.entry_id for update;
 perform 1 from public.unfinished_lots l join private.manufactured_output_lots x on x.factory_id=l.factory_id and x.lot_id=l.id where x.factory_id=factory and x.output_id=target order by l.id for update of l;
 perform 1 from public.production_orders where factory_id=factory and id=h.item_id for update;
 if src.id is null or src.physical_label is null or src.product_id<>h.product_id or src.unit<>h.unit
 or src.quantity_available-private.source_reserved(factory,src.id)<amount or not exists(select 1 from public.finished_goods_balances where factory_id=factory and product_id=h.product_id and unit=h.unit and on_hand-reserved>=amount) then raise exception 'output_stock_unavailable';end if;
 insert into private.manufactured_output_context values(pg_backend_pid(),txid_current(),factory,auth.uid(),h.entry_id,finding,'APPLY_FINDING');
 perform private.output_reconcile(factory,target,e.result->'groups',e.revision,btrim(payload->>'reason'));
 select finished_movement_id into m from private.manufactured_output_adjustments where factory_id=factory and output_id=target and quality_revision=e.revision and group_id::text=spec->>'from_group' and quantity=amount;
 if m is null then raise exception 'output_reconciliation_movement';end if;
 result:=spec||jsonb_build_object('output_id',target,'revision',(rev+1)::text,'stage','WITHDRAWN_AWAITING_RECEIPT','source_id',src.id,'finished_movement_id',m,'reason',btrim(payload->>'reason'));
 perform private.manufactured_output_authorize(factory,'RECEIPT',expected_revision);perform private.require_permission(factory,'warehouse','view');
 insert into private.manufactured_output_events(factory_id,output_id,request_id,revision,operation,intent,result,finished_movement_id,created_by)
 values(factory,target,request_id,rev+1,'RECONCILE',intent,result,m,auth.uid());
 delete from private.manufactured_output_context where backend=pg_backend_pid() and transaction_id=txid_current() and mode='APPLY_FINDING';
 return result;
end$$;

create function private.output_handoff_receivable(f uuid,o uuid,g uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.manufactured_output_events r join private.manufactured_outputs h on h.factory_id=r.factory_id and h.id=r.output_id
 where r.factory_id=f and r.output_id=o and r.operation='RECONCILE' and r.result->>'handoff_group'=g::text
 and private.output_finding(f,o)->>'revision'=r.result->>'finding_revision' and not private.output_work_held(f,h.item_id)
 and private.output_received(f,o,g::text)<(r.result->>'quantity')::numeric)
$$;

create or replace function private.output_accounting(f uuid,o uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare e private.manufactured_output_events;r private.manufactured_output_events;pending boolean;remaining numeric;begin
 select * into e from private.manufactured_output_events where factory_id=f and output_id=o and operation='QUALITY' and revision=(private.output_finding(f,o)->>'revision')::bigint;
 select * into r from private.manufactured_output_events where factory_id=f and output_id=o and operation='RECONCILE' and result->>'finding_id'=e.id::text;
 pending:=exists(select 1 from private.manufactured_output_events ev where ev.factory_id=f and ev.output_id=o and ev.operation='QUALITY' and private.output_finding_pending(f,ev.id));
 if r.id is not null then remaining:=(r.result->>'quantity')::numeric-private.output_received(f,o,r.result->>'handoff_group');end if;
 return jsonb_build_object('finding_id',e.id,'finding_revision',e.revision::text,'applied_revision',private.output_quality(f,o)->>'revision','applied',private.output_quality(f,o),
 'pending',pending,'stage',case when r.id is not null then case when remaining>0 then 'AWAITING_RECEIPT' else 'RECONCILED' end when pending then 'PENDING' else 'APPLIED' end,
 'remaining_handoff',remaining::text,'reconciliation',case when r.id is not null then r.result||jsonb_build_object('id',r.id,'request_id',r.request_id,'actor',r.created_by,'at',r.created_at) end,
 'handoffs',coalesce((select jsonb_agg(a.result||jsonb_build_object('id',a.id,'received',private.output_received(f,o,a.result->>'handoff_group')::text,
 'remaining',((a.result->>'quantity')::numeric-private.output_received(f,o,a.result->>'handoff_group'))::text) order by a.revision) from private.manufactured_output_events a where a.factory_id=f and a.output_id=o and a.operation='RECONCILE'),'[]'),
 'held_groups',coalesce((select jsonb_agg(distinct group_id) from private.output_hold_rows(f) where output_id=o),'[]'),
 'blockers',case when r.id is not null then case when remaining>0 then jsonb_build_array('output_handoff_pending') else '[]'::jsonb end when pending then coalesce(e.result->'blockers','[]') else '[]'::jsonb end);
end$$;

do $patch$ declare b text;needle text;begin
 b:=pg_get_functiondef('private.output_reconcile(uuid,uuid,jsonb,bigint,text)'::regprocedure);
 needle:='if exists(select 1 from private.manufactured_output_events where output_id=o and operation=''DISPOSITION'') then';
 if position(needle in b)=0 then raise exception 'Reconciliation disposition contract changed';end if;
 execute replace(b,needle,'if exists(select 1 from private.manufactured_output_events where output_id=o and operation=''DISPOSITION'') and not private.output_reconcile_context(f,o) then');
 b:=pg_get_functiondef('private.source_movement()'::regprocedure);
 needle:='if private.output_source_held(new.factory_id,src.entry_id) then';
 if position(needle in b)=0 then raise exception 'Source hold contract changed';end if;
 execute replace(b,needle,'if private.output_source_held(new.factory_id,src.entry_id) and not private.output_reconcile_pick_allowed(new.factory_id,new.entry_id,new.kind,new.stock_delta,src.id) then');
 b:=pg_get_functiondef('private.output_apply_or_hold(uuid,uuid,jsonb,bigint,text)'::regprocedure);
 needle:='and operation=''QUALITY'' and result->>''accounting_applied''=''false'')';
 if position(needle in b)=0 then raise exception 'Pending finding contract changed';end if;
 execute replace(b,needle,'and operation=''QUALITY'' and result->>''accounting_applied''=''false'' and private.output_finding_pending(f,id))');
 b:=pg_get_functiondef('public.receive_manufactured_output(uuid,uuid,jsonb,bigint,uuid)'::regprocedure);
 needle:='if private.output_group_held(factory,target,(payload->>''group_id'')::uuid) then';
 if position(needle in b)=0 then raise exception 'Receipt hold contract changed';end if;
 execute replace(b,needle,'if private.output_group_held(factory,target,(payload->>''group_id'')::uuid) and not private.output_handoff_receivable(factory,target,(payload->>''group_id'')::uuid) then');
 b:=pg_get_functiondef('private.manufactured_output_command(uuid,text,uuid,jsonb,bigint,uuid)'::regprocedure);
 needle:='''remaining_released'',trim_scale((g->>''released'')::numeric-used-q)::text);';
 if position(needle in b)=0 then raise exception 'Receipt evidence contract changed';end if;
 execute replace(b,needle,'''remaining_released'',trim_scale((g->>''released'')::numeric-used-q)::text)||coalesce((select jsonb_build_object(''reconciliation_id'',r.id,''finding_id'',r.result->>''finding_id'') from private.manufactured_output_events r where r.factory_id=f and r.output_id=h.id and r.operation=''RECONCILE'' and r.result->>''handoff_group''=g->>''id''),''{}''::jsonb);');
end $patch$;

revoke all on function private.output_finding_pending(uuid,uuid),private.output_reconciliation_spec(uuid,uuid,uuid),private.output_reconcile_context(uuid,uuid),private.output_reconcile_pick_allowed(uuid,uuid,text,numeric,uuid),private.output_handoff_receivable(uuid,uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function public.reconcile_manufactured_output(uuid,uuid,uuid,jsonb,bigint,uuid) from public,anon,service_role;
grant execute on function public.reconcile_manufactured_output(uuid,uuid,uuid,jsonb,bigint,uuid) to authenticated;
commit;
