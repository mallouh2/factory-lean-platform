-- Inactive B2. Existing Phase4B whole-decision cancellation remains a separate
-- authorized transaction. One fully stored unfinished source may then be
-- withdrawn/reclassified through existing adjustment and confirmed receipts.
begin;
create function private.output_handoffs(p jsonb) returns jsonb language sql immutable set search_path='' as $$
 select coalesce(p->'handoffs',case when p->>'handoff_group' is not null and (p->>'quantity')::numeric>0 then
 jsonb_build_array(jsonb_build_object('group_id',p->>'handoff_group','quantity',p->>'quantity','finished',false)) else '[]'::jsonb end)
$$;
-- Progress is immutable receipt evidence, never net stock after subsequent
-- amendments. Later withdrawals must not reopen an already received handoff.
create function private.output_handoff_received(f uuid,r uuid,g uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce(sum((e.result->>'quantity')::numeric),0) from private.manufactured_output_events e
 where e.factory_id=f and e.operation='RECEIPT' and e.result->>'reconciliation_id'=r::text and e.result->>'group_id'=g::text
$$;
create or replace function private.output_finding_pending(f uuid,finding uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.manufactured_output_events e where e.factory_id=f and e.id=finding and e.operation='QUALITY' and e.result->>'accounting_applied'='false'
 and (not exists(select 1 from private.manufactured_output_events r where r.factory_id=f and r.operation='RECONCILE' and r.result->>'finding_id'=e.id::text)
 or exists(select 1 from private.manufactured_output_events r cross join lateral jsonb_array_elements(private.output_handoffs(r.result)) g
 where r.factory_id=f and r.operation='RECONCILE' and r.result->>'finding_id'=e.id::text
 and private.output_handoff_received(f,r.id,(g->>'group_id')::uuid)<(g->>'quantity')::numeric)))
$$;
create or replace function private.output_hold_rows(f uuid)
returns table(output_id uuid,group_id uuid,finished boolean,finding_revision bigint)
language sql stable security definer set search_path='' as $$
 with recursive seeds as (
 select e.output_id,(g->>'id')::uuid group_id,(g->>'finished')::boolean finished,e.revision finding_revision
 from private.manufactured_output_events e cross join lateral jsonb_array_elements(e.result->'holds') g
 where e.factory_id=f and e.operation='QUALITY' and e.result->>'accounting_applied'='false'
 and not exists(select 1 from private.manufactured_output_events r where r.factory_id=f and r.operation='RECONCILE' and r.result->>'finding_id'=e.id::text
 and r.result->'resolved_groups' ? (g->>'id') and (coalesce(r.result->>'mode','FINISHED_TO_UNFINISHED')<>'UNFINISHED_RECLASS' or not private.output_finding_pending(f,e.id)))
 union
 select r.output_id,(g->>'group_id')::uuid,false,(r.result->>'finding_revision')::bigint
 from private.manufactured_output_events r cross join lateral jsonb_array_elements(private.output_handoffs(r.result)) g
 where r.factory_id=f and r.operation='RECONCILE' and coalesce((g->>'finished')::boolean,false)=false
 and private.output_finding_pending(f,(r.result->>'finding_id')::uuid)
 ),held(output_id,group_id,finished,finding_revision) as (
 select * from seeds union
 select h.id,(g->>'id')::uuid,jsonb_array_length(g->'missing_operations')=0,r.finding_revision
 from held r join private.manufactured_completion_work w on w.factory_id=f and w.output_id=r.output_id and w.group_id=r.group_id
 join private.manufactured_outputs h on h.factory_id=f and h.item_id=w.item_id
 cross join lateral jsonb_array_elements(coalesce(private.output_quality(f,h.id)->'groups',h.recorded_groups)) g
 ) select * from held
$$;

-- Returns NULL for the unchanged B1 finished-source branch. No source mapping
-- is guessed: one old unfinished group decreases/disappears, and its exact
-- released quantity is retained or handed to explicit corrected groups.
create function private.output_unfinished_spec(f uuid,o uuid,finding uuid,applied jsonb,qa jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare oldg jsonb;g jsonb;source_group jsonb;targets jsonb:='[]';amount numeric;retained numeric;old_count integer:=0;total numeric:=0;lot uuid;begin
 if applied->'groups'=qa->'groups' then return jsonb_build_object('mode','UNCHANGED','quantity','0','from_group',null,'handoff_group',null,'resolved_groups','[]'::jsonb,'handoffs','[]'::jsonb);end if;
 for oldg in select value from jsonb_array_elements(applied->'groups') loop
  select value into g from jsonb_array_elements(qa->'groups') where value->>'id'=oldg->>'id';
  if jsonb_array_length(oldg->'missing_operations')>0 and g is distinct from oldg then old_count:=old_count+1;source_group:=oldg;end if;
 end loop;
 if old_count=0 then return null;end if;
 if old_count<>1 then raise exception 'output_reconciliation_multiple_sources';end if;
 if (source_group->>'released')::numeric<>(source_group->>'quantity')::numeric or private.output_received(f,o,source_group->>'id')<>(source_group->>'quantity')::numeric then raise exception 'output_reconciliation_receipt_scope';end if;
 select value into g from jsonb_array_elements(qa->'groups') where value->>'id'=source_group->>'id';
 if g is not null and (g->'missing_operations' is distinct from source_group->'missing_operations' or g->>'restriction' is distinct from source_group->>'restriction') then raise exception 'output_reconciliation_new_identity_required';end if;
 retained:=coalesce((g->>'quantity')::numeric,0);
 if retained>=(source_group->>'quantity')::numeric then raise exception 'output_reconciliation_allocation_scope';end if;
 if g is not null and (g->>'released')::numeric<>retained then raise exception 'output_reconciliation_release_required';end if;
 amount:=(source_group->>'quantity')::numeric-retained;
 for g in select value from jsonb_array_elements(qa->'groups') loop
  if g->>'id'=source_group->>'id' then continue;end if;
  select value into oldg from jsonb_array_elements(applied->'groups') where value->>'id'=g->>'id';
  if oldg=g then continue;end if;
  if oldg is not null and (jsonb_array_length(oldg->'missing_operations')<>0 or g->'missing_operations'<>oldg->'missing_operations'
   or g->>'restriction' is distinct from oldg->>'restriction' or (g->>'quantity')::numeric<=(oldg->>'quantity')::numeric) then raise exception 'output_reconciliation_mixed_sources';end if;
  if (g->>'released')::numeric<>(g->>'quantity')::numeric then raise exception 'output_reconciliation_release_required';end if;
  targets:=targets||jsonb_build_array(jsonb_build_object('group_id',g->>'id','quantity',trim_scale((g->>'quantity')::numeric-coalesce((oldg->>'quantity')::numeric,0))::text,'finished',jsonb_array_length(g->'missing_operations')=0));
  total:=total+(g->>'quantity')::numeric-coalesce((oldg->>'quantity')::numeric,0);
 end loop;
 if total<>amount or jsonb_array_length(targets)=0 or exists(select 1 from jsonb_array_elements(applied->'groups') a where a->>'id'<>source_group->>'id' and not exists(select 1 from jsonb_array_elements(qa->'groups') n where n->>'id'=a->>'id')) then raise exception 'output_reconciliation_scope';end if;
 select lot_id into lot from private.manufactured_output_lots where factory_id=f and output_id=o and group_id::text=source_group->>'id';
 if lot is null then raise exception 'output_stock_unavailable';end if;
 if exists(select 1 from private.manufactured_completion_work w where w.factory_id=f and w.lot_id=lot and private.output_work_live(f,w.item_id))
 or exists(select 1 from private.manufactured_output_events e where e.factory_id=f and e.output_id=o and e.operation='DISPOSITION' and e.result->>'group_id'=source_group->>'id'
 and not exists(select 1 from private.manufactured_completion_work w where w.factory_id=f and w.request_id=e.request_id and private.output_work_retired(f,w.item_id))) then raise exception 'output_allocation_retirement_required';end if;
 if exists(select 1 from public.material_requests where factory_id=f and lot_id=lot and status not in ('CANCELLED','REJECTED')) then raise exception 'output_material_committed';end if;
 if not exists(select 1 from public.unfinished_lots l where l.factory_id=f and l.id=lot and l.quantity_created=(source_group->>'quantity')::numeric
 and l.quantity_available=l.quantity_created and l.warehouse_quantity=l.quantity_created) then raise exception 'output_stock_unavailable';end if;
 return jsonb_build_object('mode','UNFINISHED_RECLASS','source_lot_id',lot,'from_group',source_group->>'id','retained_quantity',retained::text,
 'quantity',trim_scale(amount)::text,'handoff_group',targets->0->>'group_id','handoffs',targets,'resolved_groups',jsonb_build_array(source_group->>'id'));
end$$;

-- Keep B1's common authorizations/revisions/dependency checks and its original
-- validator. Insert the unfinished branch after those common checks only.
do $patch$ declare b text;needle text;begin
 b:=pg_get_functiondef('private.output_reconciliation_spec(uuid,uuid,uuid)'::regprocedure);
 b:=replace(b,'applied jsonb;','extra jsonb;applied jsonb;');
 needle:='for oldg in select value from jsonb_array_elements(applied->''groups'') loop';
 if position(needle in b)=0 then raise exception 'B1 spec contract changed';end if;
 execute replace(b,needle,'extra:=private.output_unfinished_spec(f,o,finding,applied,e.result); if extra is not null then return extra||jsonb_build_object(''finding_id'',finding,''finding_revision'',e.revision::text,''previous_applied_revision'',applied->>''revision'');end if; '||needle);
end $patch$;

create function private.output_reconcile_lot_allowed(oldrow public.unfinished_lots,newrow public.unfinished_lots) returns boolean
language plpgsql stable security definer set search_path='' as $$declare c private.manufactured_output_context;o uuid;s jsonb;q numeric;begin
 select * into c from private.manufactured_output_context where backend=pg_backend_pid() and transaction_id=txid_current() and factory_id=oldrow.factory_id and entry_id=oldrow.source_entry_id and actor_id=auth.uid() and mode='APPLY_FINDING';
 if c.backend is null then return false;end if;
 select id into o from private.manufactured_outputs where factory_id=oldrow.factory_id and entry_id=oldrow.source_entry_id;
 s:=private.output_reconciliation_spec(oldrow.factory_id,o,c.request_id);q:=(s->>'quantity')::numeric;
 return s->>'mode'='UNFINISHED_RECLASS' and s->>'source_lot_id'=oldrow.id::text
 and newrow.quantity_available=oldrow.quantity_available-q and newrow.quantity_created=oldrow.quantity_created-q and newrow.warehouse_quantity=oldrow.warehouse_quantity-q
 and (to_jsonb(newrow)-array['updated_at','quantity_available','quantity_created','warehouse_quantity'])=(to_jsonb(oldrow)-array['updated_at','quantity_available','quantity_created','warehouse_quantity']);
end$$;

-- Add the unfinished movement/zero-movement event shapes; keep all other
-- operation, receipt, retirement, uniqueness and immutability constraints.
do $$declare r record;n integer:=0;begin
 for r in select conname from pg_constraint where conrelid='private.manufactured_output_events'::regclass and contype='c'
 and pg_get_constraintdef(oid) like '%RECONCILE%' and pg_get_constraintdef(oid) like '%finished_movement_id%' loop
 execute format('alter table private.manufactured_output_events drop constraint %I',r.conname);n:=n+1;end loop;
 if n<>2 then raise exception 'Reconciliation event constraint contract changed';end if;
end$$;
alter table private.manufactured_output_events add constraint output_event_movements check(
 (operation='RECEIPT' and num_nonnulls(finished_movement_id,unfinished_movement_id)=1)
 or (operation='RECONCILE' and case coalesce(result->>'mode','FINISHED_TO_UNFINISHED') when 'UNCHANGED' then num_nonnulls(finished_movement_id,unfinished_movement_id)=0
 when 'UNFINISHED_RECLASS' then unfinished_movement_id is not null and finished_movement_id is null else finished_movement_id is not null and unfinished_movement_id is null end)
 or (operation not in ('RECEIPT','RECONCILE') and num_nonnulls(finished_movement_id,unfinished_movement_id)=0));
alter table private.manufactured_output_events add constraint output_reconciliation_evidence check(operation<>'RECONCILE' or coalesce(
 result ?& array['finding_id','finding_revision','from_group','handoff_group','quantity','resolved_groups']
 and case when result->>'mode'='UNCHANGED' then (result->>'quantity')::numeric=0 and private.output_handoffs(result)='[]'::jsonb
 else (result->>'quantity')::numeric>0 and jsonb_array_length(private.output_handoffs(result))>0 end,false));

do $patch$ declare b text;needle text;begin
 b:=pg_get_functiondef('private.output_reconcile(uuid,uuid,jsonb,bigint,text)'::regprocedure);
 needle:='insert into private.manufactured_output_context values(pg_backend_pid(),txid_current(),f,auth.uid(),h.entry_id,gen_random_uuid(),''RECONCILE'');';
 if position(needle in b)=0 then raise exception 'Stored reconciliation context changed';end if;
 b:=replace(b,needle,'if not private.output_reconcile_context(f,o) then '||needle||' end if;');
 needle:='delete from private.manufactured_output_context where backend=pg_backend_pid() and transaction_id=txid_current();';
 if position(needle in b)=0 then raise exception 'Stored reconciliation cleanup changed';end if;
 execute replace(b,needle,'if not private.output_reconcile_context(f,o) then '||needle||' end if;');
 b:=pg_get_functiondef('private.output_lot_guard()'::regprocedure);
 needle:='if (to_jsonb(new)-''updated_at'')';
 -- Must run before the existing negative-delta hold check, which remains intact.
 needle:='perform private.fulfillment_lock(new.factory_id);';
 if position(needle in b)=0 then raise exception 'Held lot contract changed';end if;
 execute replace(b,needle,needle||' if private.output_reconcile_lot_allowed(old,new) then return new;end if;');
 b:=pg_get_functiondef('public.reconcile_manufactured_output(uuid,uuid,uuid,jsonb,bigint,uuid)'::regprocedure);
 b:=replace(b,'spec jsonb;','wm uuid;mode text;source_lot public.unfinished_lots;spec jsonb;');
 needle:='or not payload ?& array[''source_id'',''physical_confirmation'',''reason''] or exists(select 1 from jsonb_object_keys(payload) k where k not in (''source_id'',''physical_confirmation'',''reason''))
 or payload->''physical_confirmation'' is distinct from ''true''::jsonb or length';
 if position(needle in b)=0 then raise exception 'Reconciliation payload contract changed';end if;
 b:=replace(b,needle,'or not payload ? ''reason'' or exists(select 1 from jsonb_object_keys(payload) k where k not in (''source_id'',''source_lot_id'',''source_location'',''identification_note'',''physical_confirmation'',''reason'')) or length');
 needle:='select * into src from public.finished_goods_sources where factory_id=factory and id=(payload->>''source_id'')::uuid and entry_id=h.entry_id for update;';
 if position(needle in b)=0 then raise exception 'Reconciliation source contract changed';end if;
 b:=replace(b,needle,'mode:=coalesce(spec->>''mode'',''FINISHED_TO_UNFINISHED''); if mode=''FINISHED_TO_UNFINISHED'' then
 if payload ? ''source_lot_id'' or payload ? ''source_location'' or payload ? ''identification_note'' or payload->''physical_confirmation'' is distinct from ''true''::jsonb then raise exception ''output_physical_confirmation'';end if;
 '||needle||'
 elsif mode=''UNFINISHED_RECLASS'' then
 if payload ? ''source_id'' or payload->''physical_confirmation'' is distinct from ''true''::jsonb or length(btrim(coalesce(payload->>''identification_note'',''''))) not between 3 and 1000 then raise exception ''output_source_identification_required'';end if;
 select lot.* into source_lot from public.unfinished_lots lot join private.manufactured_output_lots x on x.factory_id=lot.factory_id and x.lot_id=lot.id
 where lot.factory_id=factory and lot.id=(payload->>''source_lot_id'')::uuid and x.output_id=target and lot.id::text=spec->>''source_lot_id'' and x.location=payload->>''source_location'' for update of lot;
 if source_lot.id is null or source_lot.quantity_available<>source_lot.quantity_created or source_lot.warehouse_quantity<>source_lot.quantity_created or source_lot.warehouse_quantity<amount then raise exception ''output_stock_unavailable'';end if;
 elsif mode=''UNCHANGED'' then if payload-''reason''<>''{}''::jsonb then raise exception ''output_physical_confirmation'';end if;
 else raise exception ''output_reconciliation_scope'';end if;');
 needle:='if src.id is null or src.physical_label is null';
 b:=replace(b,needle,'if mode=''FINISHED_TO_UNFINISHED'' and (src.id is null or src.physical_label is null');
 needle:='and on_hand-reserved>=amount) then raise exception ''output_stock_unavailable'';end if;';
 if position(needle in b)=0 then raise exception 'Finished availability contract changed';end if;
 b:=replace(b,needle,'and on_hand-reserved>=amount)) then raise exception ''output_stock_unavailable'';end if;');
 needle:='perform private.output_reconcile(factory,target,e.result->''groups'',e.revision,btrim(payload->>''reason''));';
 b:=replace(b,needle,'if mode<>''UNCHANGED'' then '||needle||' end if;');
 needle:='if m is null then raise exception ''output_reconciliation_movement'';end if;';
 if position(needle in b)=0 then raise exception 'Movement evidence contract changed';end if;
 b:=replace(b,needle,'if mode=''UNFINISHED_RECLASS'' then select unfinished_movement_id into wm from private.manufactured_output_adjustments where factory_id=factory and output_id=target and quality_revision=e.revision and group_id::text=spec->>''from_group'' and quantity=amount;end if;
 if (mode=''FINISHED_TO_UNFINISHED'' and m is null) or (mode=''UNFINISHED_RECLASS'' and wm is null) then raise exception ''output_reconciliation_movement'';end if;');
 b:=replace(b,'''stage'',''WITHDRAWN_AWAITING_RECEIPT''','''stage'',case when mode=''UNCHANGED'' then ''RECONCILED'' else ''WITHDRAWN_AWAITING_RECEIPT'' end');
 b:=replace(b,'''finished_movement_id'',m,','''unfinished_movement_id'',wm,''finished_movement_id'',m,');
 b:=replace(b,'intent,result,finished_movement_id,created_by)','intent,result,finished_movement_id,unfinished_movement_id,created_by)');
 b:=replace(b,'''RECONCILE'',intent,result,m,auth.uid())','''RECONCILE'',intent,result,m,wm,auth.uid())');
 b:=replace(b,'delete from private.manufactured_output_context where backend=pg_backend_pid() and transaction_id=txid_current() and mode=''APPLY_FINDING'';',
 'delete from private.manufactured_output_context c where c.backend=pg_backend_pid() and c.transaction_id=txid_current() and c.mode=''APPLY_FINDING'';');execute b;
end $patch$;

create function private.output_handoff_pending(f uuid,o uuid,g uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.manufactured_output_events r cross join lateral jsonb_array_elements(private.output_handoffs(r.result)) h
 where r.factory_id=f and r.output_id=o and r.operation='RECONCILE' and h->>'group_id'=g::text
 and private.output_handoff_received(f,r.id,g)<(h->>'quantity')::numeric)
$$;
create or replace function private.output_handoff_receivable(f uuid,o uuid,g uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.manufactured_output_events r join private.manufactured_outputs h on h.factory_id=r.factory_id and h.id=r.output_id
 cross join lateral jsonb_array_elements(private.output_handoffs(r.result)) target
 where r.factory_id=f and r.output_id=o and r.operation='RECONCILE' and target->>'group_id'=g::text
 and private.output_finding(f,o)->>'revision'=r.result->>'finding_revision' and not private.output_work_held(f,h.item_id)
 and private.output_handoff_received(f,r.id,g)<(target->>'quantity')::numeric)
$$;
do $patch$ declare b text;needle text;begin
 b:=pg_get_functiondef('public.receive_manufactured_output(uuid,uuid,jsonb,bigint,uuid)'::regprocedure);
 needle:='if private.output_group_held(factory,target,(payload->>''group_id'')::uuid) and not';
 if position(needle in b)=0 then raise exception 'Handoff receipt guard changed';end if;
 execute replace(b,needle,'if (private.output_group_held(factory,target,(payload->>''group_id'')::uuid) or private.output_handoff_pending(factory,target,(payload->>''group_id'')::uuid)) and not');
 b:=pg_get_functiondef('private.manufactured_output_command(uuid,text,uuid,jsonb,bigint,uuid)'::regprocedure);
 needle:='r.result->>''handoff_group''=g->>''id''';
 if position(needle in b)=0 then raise exception 'Handoff evidence link changed';end if;
 execute replace(b,needle,'r.result->>''finding_revision''=private.output_finding(f,h.id)->>''revision'' and exists(select 1 from jsonb_array_elements(private.output_handoffs(r.result)) hand where hand->>''group_id''=g->>''id'' and private.output_handoff_received(f,r.id,(g->>''id'')::uuid)<(hand->>''quantity'')::numeric)');
end $patch$;

-- Read-only continuation exposes Phase4B's actual eligibility/state, not a
-- second cancellation engine. Planning details still require Orders view.
create function private.output_affected_allocations(f uuid,o uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('item_id',w.item_id,'choice',w.choice,'quantity',w.quantity::text,'decision_revision',private.output_work_revision_state(f,w.item_id)) order by w.created_at),'[]')
 from private.manufactured_completion_work w where w.factory_id=f and w.output_id=o and private.output_work_live(f,w.item_id) and private.output_work_held(f,w.item_id) and private.has_permission(f,'orders','view')
$$;
create or replace function private.output_accounting(f uuid,o uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare e private.manufactured_output_events;r private.manufactured_output_events;pending boolean;remaining numeric;begin
 select * into e from private.manufactured_output_events where factory_id=f and output_id=o and operation='QUALITY' and revision=(private.output_finding(f,o)->>'revision')::bigint;
 select * into r from private.manufactured_output_events where factory_id=f and output_id=o and operation='RECONCILE' and result->>'finding_id'=e.id::text;
 pending:=exists(select 1 from private.manufactured_output_events ev where ev.factory_id=f and ev.output_id=o and ev.operation='QUALITY' and private.output_finding_pending(f,ev.id));
 if r.id is not null then select coalesce(sum((g->>'quantity')::numeric-private.output_handoff_received(f,r.id,(g->>'group_id')::uuid)),0) into remaining from jsonb_array_elements(private.output_handoffs(r.result)) g;end if;
 return jsonb_build_object('finding_id',e.id,'finding_revision',e.revision::text,'applied_revision',private.output_quality(f,o)->>'revision','applied',private.output_quality(f,o),'pending',pending,
 'stage',case when r.id is not null then case when remaining>0 then 'AWAITING_RECEIPT' else 'RECONCILED' end when pending then 'PENDING' else 'APPLIED' end,
 'remaining_handoff',remaining::text,'reconciliation',case when r.id is not null then r.result||jsonb_build_object('id',r.id,'request_id',r.request_id,'actor',r.created_by,'at',r.created_at) end,
 'handoffs',coalesce((select jsonb_agg(a.result||jsonb_build_object('id',a.id,'received',private.output_handoff_received(f,a.id,(g->>'group_id')::uuid)::text,
 'remaining',((g->>'quantity')::numeric-private.output_handoff_received(f,a.id,(g->>'group_id')::uuid))::text,'group_id',g->>'group_id') order by a.revision,g->>'group_id')
 from private.manufactured_output_events a cross join lateral jsonb_array_elements(private.output_handoffs(a.result)) g where a.factory_id=f and a.output_id=o and a.operation='RECONCILE'),'[]'),
 'affected_allocations',private.output_affected_allocations(f,o),
 'held_groups',coalesce((select jsonb_agg(distinct group_id) from private.output_hold_rows(f) where output_id=o),'[]'),
 'blockers',case when r.id is not null then case when remaining>0 then jsonb_build_array('output_handoff_pending') else '[]'::jsonb end when pending then coalesce(e.result->'blockers','[]') else '[]'::jsonb end);
end$$;
revoke all on function private.output_handoffs(jsonb),private.output_handoff_received(uuid,uuid,uuid),private.output_unfinished_spec(uuid,uuid,uuid,jsonb,jsonb),private.output_reconcile_lot_allowed(public.unfinished_lots,public.unfinished_lots),private.output_handoff_pending(uuid,uuid,uuid),private.output_affected_allocations(uuid,uuid) from public,anon,authenticated,service_role;
commit;
