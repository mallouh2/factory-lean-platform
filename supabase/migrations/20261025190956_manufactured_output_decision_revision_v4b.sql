-- Pre-issue decision revision only. Physical history, source genealogy and gates
-- remain unchanged. Supersession is an append-only retirement plus new work.
begin;
alter table private.manufactured_output_events drop constraint manufactured_output_events_operation_check;
alter table private.manufactured_output_events add check(operation in ('DECLARE','QUALITY','RECEIPT','DISPOSITION','ACKNOWLEDGE','CORRECTION','RETIRE'));
alter table private.manufactured_output_events add check(operation<>'RETIRE' or
 (result ?& array['item_id','action','reason','before'] and result->>'action' in ('CANCEL','CHANGE') and length(btrim(result->>'reason')) between 3 and 2000));
create unique index manufactured_work_retirement on private.manufactured_output_events(factory_id,(result->>'item_id')) where operation='RETIRE';
alter table private.manufactured_output_context drop constraint manufactured_output_context_mode_check;
alter table private.manufactured_output_context add check(mode in ('RECORD','CORRECTION','RECEIPT','RECONCILE','WORK','ISSUE','REVISION'));

create function private.output_work_retired(f uuid,i uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.manufactured_output_events where factory_id=f and operation='RETIRE' and result->>'item_id'=i::text)
$$;
create function private.output_work_revising(f uuid,i uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.manufactured_output_context where backend=pg_backend_pid() and transaction_id=txid_current() and factory_id=f and actor_id=auth.uid() and mode='REVISION' and request_id=i)
$$;
-- The transaction-private retiring work is excluded while the existing creation
-- primitive validates its successor. The final immutable event replaces context.
create function private.output_work_live(f uuid,i uuid) returns boolean language sql stable security definer set search_path='' as $$
 select not private.output_work_retired(f,i) and not private.output_work_revising(f,i)
$$;
create function private.output_work_allocations(f uuid,l uuid)
returns table(assigned numeric,replaced numeric,stock numeric,reserved numeric) language sql stable security definer set search_path='' as $$
 select coalesce(sum(quantity) filter(where choice in ('COMPLETE','REPLACE')),0),
 coalesce(sum(quantity) filter(where choice='REPLACE'),0),coalesce(sum(quantity) filter(where choice='STOCK'),0),
 coalesce(sum(quantity-private.output_work_consumed(f,item_id)) filter(where choice<>'REPLACE' and exists(select 1 from public.material_requests mr where mr.factory_id=f and mr.id=material_request_id and mr.status='REQUESTED')),0)
 from private.manufactured_completion_work where factory_id=f and lot_id=l and private.output_work_live(f,item_id)
$$;

-- One eligibility/state contract for the command and the Planning reader.
create function private.output_work_revision_state(f uuid,i uuid) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare w private.manufactured_completion_work;o public.production_orders;m public.material_requests;l public.unfinished_lots;b text;state jsonb;can_cancel boolean;begin
 select * into w from private.manufactured_completion_work where factory_id=f and item_id=i;
 if w.item_id is null then raise exception 'output_not_found';end if;
 select * into o from public.production_orders where factory_id=f and id=i;
 select * into m from public.material_requests where factory_id=f and id=w.material_request_id;
 select * into l from public.unfinished_lots where factory_id=f and id=w.lot_id;
 state:=jsonb_build_object('plan_revision',(select coalesce(max(revision_no),0)::text from public.production_plan_revisions where factory_id=f and item_id=i),
 'material_revision',m.revision::text,'line_id',o.line_id,'start',o.start_time,'finish',o.expected_finish,'locked',o.planning_locked_at,
 'locked_by',o.planning_locked_by,'status',o.status,'actual_start',o.actual_start,'actual_finish',o.actual_finish);
 b:=case
 when private.output_work_retired(f,i) then 'output_work_retired'
 when w.choice='STOCK' then 'output_revision_choice'
 when o.status<>'planned' or o.actual_start is not null or o.actual_finish is not null then 'output_work_started'
 when exists(select 1 from public.production_entries where factory_id=f and order_id=i)
   or exists(select 1 from private.manufactured_outputs where factory_id=f and item_id=i) then 'output_work_has_output'
 when w.material_request_id is not null and (m.id is null or m.status<>'REQUESTED' or m.movement_id is not null or m.issued_at is not null or m.received_at is not null
   or exists(select 1 from public.unfinished_movements where factory_id=f and id=m.movement_id and kind='warehouse_issue')
   or exists(select 1 from public.fulfillment_commands where factory_id=f and operation='supply_material_change' and payload->>'id'=m.id::text and payload->>'action'='issue')) then 'output_material_issued'
 when o.planning_locked_at is not null then 'planning_locked'
 when o.start_time is not null and o.start_time<=now() then 'planning_already_started'
 when exists(select 1 from public.sales_incoming_allocations where factory_id=f and item_id=i and quantity>0) then 'output_work_committed'
 when w.choice='REPLACE' and exists(select 1 from private.manufactured_completion_work where factory_id=f and lot_id=w.lot_id and choice='STOCK' and private.output_work_live(f,item_id)) then 'output_work_dependent'
 when w.choice='REPLACE' and (l.id is null or l.warehouse_quantity<w.quantity+(select reserved from private.output_work_allocations(f,w.lot_id))) then 'output_allocation_unavailable'
 end;
 if b is null and not private.manufactured_output_enabled(f) then b:='recording_disabled';end if;
 if b is null and not(private.has_permission(f,'orders','view') and private.has_permission(f,'orders','edit')) then b:='output_revision_permission';end if;
 if b is null and w.material_request_id is not null and not private.has_permission(f,'warehouse','issue') then b:='output_warehouse_permission';end if;
 can_cancel:=b is null;
 return jsonb_build_object('state',state,'cancel_available',can_cancel,'change_available',can_cancel and private.has_permission(f,'orders','create'),
 'cancel_block',b,'change_block',coalesce(b,case when not private.has_permission(f,'orders','create') then 'output_revision_permission' end),
 'revision',(select max(revision)::text from private.manufactured_output_events where factory_id=f and output_id=w.output_id),
 'missing_operations',(select value->'missing_operations' from jsonb_array_elements(private.output_quality(f,w.output_id)->'groups') where value->>'id'=w.group_id::text),
 'retirement',(select result from private.manufactured_output_events where factory_id=f and operation='RETIRE' and result->>'item_id'=i::text));
end$$;

-- Preserve the existing writer/reader and V3 contracts with checked, exact patches.
do $patch$ declare b text;needle text;replacement text;begin
 b:=pg_get_functiondef('public.plan_manufactured_completion(uuid,uuid,jsonb,bigint,uuid)'::regprocedure);
 b:=replace(b,'q numeric;used numeric;', 'revision_context boolean:=false;q numeric;used numeric;');
 needle:='select coalesce(sum(quantity) filter(where w.choice in (''COMPLETE'',''REPLACE'')),0),coalesce(sum(quantity) filter(where w.choice=''REPLACE''),0)-coalesce(sum(quantity) filter(where w.choice=''STOCK''),0),
 coalesce(sum(quantity-private.output_work_consumed(factory,item_id)) filter(where w.choice<>''REPLACE'' and exists(select 1 from public.material_requests mr where mr.id=w.material_request_id and mr.status=''REQUESTED'')),0)
 into used,freed,reserved from private.manufactured_completion_work w where w.factory_id=factory and w.lot_id=l.id;';
 if position(needle in b)=0 then raise exception 'allocation contract changed';end if;
 b:=replace(b,needle,'select assigned,replaced-stock,a.reserved into used,freed,reserved from private.output_work_allocations(factory,l.id) a;');
 needle:='(select sum(quantity) from private.manufactured_completion_work where factory_id=factory and lot_id=l.id and choice=''STOCK'')';
 if position(needle in b)=0 then raise exception 'stock allocation contract changed';end if;
 b:=replace(b,needle,'(select stock from private.output_work_allocations(factory,l.id))');
 needle:='insert into private.manufactured_output_context values(pg_backend_pid(),txid_current(),factory,auth.uid(),h.entry_id,request_id,''WORK'');';
 if position(needle in b)=0 then raise exception 'work context changed';end if;
 b:=replace(b,needle,'revision_context:=exists(select 1 from private.manufactured_output_context where backend=pg_backend_pid() and transaction_id=txid_current() and factory_id=factory and actor_id=auth.uid() and mode=''REVISION''); if revision_context then update private.manufactured_output_context set mode=''WORK'' where backend=pg_backend_pid() and transaction_id=txid_current();else '||needle||' end if;');
 needle:='delete from private.manufactured_output_context where backend=pg_backend_pid() and transaction_id=txid_current();';
 if position(needle in b)=0 then raise exception 'work context cleanup changed';end if;
 execute replace(b,needle,'if revision_context then update private.manufactured_output_context set mode=''REVISION'' where backend=pg_backend_pid() and transaction_id=txid_current();else '||needle||' end if;');
 b:=pg_get_functiondef('private.manufactured_output_command(uuid,text,uuid,jsonb,bigint,uuid)'::regprocedure);
 needle:='and operation=''DISPOSITION'' and ev.result->>''group_id''=p->>''group_id'';';
 if position(needle in b)=0 then raise exception 'disposition contract changed';end if;
 execute replace(b,needle,'and operation=''DISPOSITION'' and ev.result->>''group_id''=p->>''group_id'' and not exists(select 1 from private.manufactured_completion_work w where w.factory_id=f and w.request_id=ev.request_id and not private.output_work_live(f,w.item_id));');
 b:=pg_get_functiondef('public.manufactured_completion_read(uuid,integer)'::regprocedure);
 needle:='left join lateral(select sum(quantity) filter(where choice in (''COMPLETE'',''REPLACE'')) assigned,sum(quantity) filter(where choice=''REPLACE'') replaced,sum(quantity) filter(where choice=''STOCK'') stock,
 sum(quantity-private.output_work_consumed(factory,item_id)) filter(where choice<>''REPLACE'' and exists(select 1 from public.material_requests mr where mr.id=material_request_id and mr.status=''REQUESTED'')) reserved from private.manufactured_completion_work where factory_id=m.factory_id and lot_id=m.lot_id) a on true';
 if position(needle in b)=0 then raise exception 'allocation reader contract changed';end if;
 b:=replace(b,needle,'left join lateral private.output_work_allocations(m.factory_id,m.lot_id) a on true');
 needle:='mr.status material_status,w.material_request_id,w.created_at,w.created_by,w.intent->''payload''->>''reason'' reason,';
 if position(needle in b)=0 then raise exception 'work reader contract changed';end if;
 execute replace(b,needle,needle||' private.output_work_revision_state(factory,w.item_id) decision_revision,');
 b:=pg_get_functiondef('private.output_work_guard()'::regprocedure);
 needle:='if w.item_id is null then return new;end if;';
 if position(needle in b)=0 then raise exception 'work guard changed';end if;
 execute replace(b,needle,needle||E'\n if private.output_work_retired(new.factory_id,new.id) then raise exception ''output_work_retired'';end if;\n if new.status=''cancelled'' and old.status<>''cancelled'' and not private.output_work_revising(new.factory_id,new.id) then raise exception ''output_revision_required'';end if;');
 b:=pg_get_functiondef('private.output_material_guard()'::regprocedure);
 needle:='else
  select * into w from private.manufactured_completion_work where factory_id=new.factory_id and material_request_id=new.id;';
 if position(needle in b)=0 then raise exception 'material guard changed';end if;
 replacement:=needle||E'\n  if private.output_work_retired(new.factory_id,w.item_id) then raise exception ''output_work_retired'';end if;\n  if w.item_id is not null and private.output_work_revising(new.factory_id,w.item_id) and old.status=''REQUESTED'' and new.status=''CANCELLED'' and old.movement_id is null and old.issued_at is null\n   and (to_jsonb(new)-array[''status'',''reason'',''revision''])=(to_jsonb(old)-array[''status'',''reason'',''revision'']) and new.revision=old.revision+1 then return new;end if;';
 execute replace(b,needle,replacement);
 b:=pg_get_functiondef('private.output_recovery_validate(uuid,jsonb)'::regprocedure);
 needle:='if w.item_id is null or w.choice=''REPLACE'' then';
 if position(needle in b)=0 then raise exception 'recovery guard changed';end if;
 execute replace(b,needle,'if w.item_id is not null and not private.output_work_live(f,w.item_id) then raise exception ''output_work_retired'';end if; '||needle);
 -- The newly exercised existing cancellation branch has a variable/column name
 -- collision. Repeat its exact payload normalization; retain the supply command.
 b:=pg_get_functiondef('private.apply_supply_command(uuid,text,jsonb,uuid)'::regprocedure);
 needle:='end,reason=reason,revision=revision+1 where id=m.id;';
 if position(needle in b)=0 then raise exception 'material cancellation contract changed';end if;
 execute replace(b,needle,'end,reason=btrim(coalesce(payload->>''reason'','''')),revision=revision+1 where id=m.id;');
end $patch$;

create function private.output_work_delete_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from private.manufactured_completion_work where factory_id=old.factory_id and (item_id=old.id or material_request_id=old.id)) then raise exception 'manufactured_output_immutable';end if;return old;
end$$;
create trigger manufactured_work_no_delete before delete on public.production_orders for each row execute function private.output_work_delete_guard();
create trigger manufactured_material_no_delete before delete on public.material_requests for each row execute function private.output_work_delete_guard();

create function public.revise_manufactured_completion(factory uuid,target uuid,payload jsonb,expected_revision bigint,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare w private.manufactured_completion_work;h private.manufactured_outputs;m public.material_requests;o public.production_orders;
 prior private.manufactured_output_events;state jsonb;before_state jsonb;intent jsonb;result jsonb;successor jsonb;rev bigint;why text;ops jsonb;begin
 if current_setting('transaction_isolation')<>'read committed' then raise exception 'output_isolation';end if;
 perform private.manufactured_output_authorize(factory,'DISPOSITION',expected_revision);
 if target is null or request_id is null or expected_revision is null or expected_revision<1 or jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>6000
 or not payload ?& array['action','reason','expected_state'] or payload->>'action' not in ('CANCEL','CHANGE') or payload->>'action' is null
 or exists(select 1 from jsonb_object_keys(payload) k where k not in ('action','reason','expected_state','choice','operations'))
 or length(btrim(coalesce(payload->>'reason',''))) not between 3 and 2000 or jsonb_typeof(payload->'expected_state') is distinct from 'object' then raise exception 'output_revision_invalid';end if;
 if payload->>'action'='CHANGE' then perform private.require_permission(factory,'orders','create');end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.fulfillment_lock(factory);
 perform private.manufactured_output_authorize(factory,'DISPOSITION',expected_revision);
 if payload->>'action'='CHANGE' then perform private.require_permission(factory,'orders','create');end if;
 if not private.manufactured_output_enabled(factory) then raise exception 'recording_disabled';end if;
 intent:=jsonb_build_object('operation','REVISE_WORK','target',target,'payload',payload,'expected',expected_revision);
 select * into w from private.manufactured_completion_work where factory_id=factory and item_id=target;
 if w.item_id is null then raise exception 'output_not_found';end if;
 if w.material_request_id is not null then perform private.require_permission(factory,'warehouse','issue');end if;
 select * into prior from private.manufactured_output_events ev where ev.factory_id=factory and ev.request_id=revise_manufactured_completion.request_id;
 if found then if prior.created_by<>auth.uid() or prior.intent<>intent then raise exception 'request_conflict';end if;return prior.result;end if;
 select * into h from private.manufactured_outputs where factory_id=factory and id=w.output_id for update;
 perform 1 from public.unfinished_lots where factory_id=factory and id=w.lot_id for update;
 select * into o from public.production_orders where factory_id=factory and id=target for update;
 select * into m from public.material_requests where factory_id=factory and id=w.material_request_id for update;
 state:=private.output_work_revision_state(factory,target);
 if state->>'cancel_block' is not null then raise exception '%',state->>'cancel_block';end if;
 if state->>'revision' is distinct from expected_revision::text or state->'state' is distinct from payload->'expected_state' then raise exception 'output_revision';end if;
 if payload->>'action'='CHANGE' and (payload->>'choice' is null or payload->>'choice' not in ('COMPLETE','REPLACE') or payload->>'choice'=w.choice) then raise exception 'output_revision_choice';end if;
 if payload->>'action'='CANCEL' and (payload ? 'choice' or payload ? 'operations') then raise exception 'output_revision_invalid';end if;
 before_state:=jsonb_build_object('work',to_jsonb(w)-array['intent','result'],'production',to_jsonb(o),'material',case when m.id is not null then to_jsonb(m) end,'state',state->'state');
 why:=btrim(payload->>'reason');
 -- A context row can only be created by this protected command; it is never a
 -- client flag. Existing guards still police every Planning and supply update.
 insert into private.manufactured_output_context values(pg_backend_pid(),txid_current(),factory,auth.uid(),h.entry_id,target,'REVISION');
 if o.line_id is not null or o.start_time is not null or o.expected_finish is not null then
  perform public.revise_product_plan(factory,target,null,null,'management_decision',left(why,240));
 end if;
 if m.id is not null then
  perform public.supply_command(factory,'material_change',jsonb_build_object('id',m.id,'revision',m.revision,'action','cancel','reason',why),gen_random_uuid());
 end if;
 update public.production_orders set status='cancelled' where factory_id=factory and id=target;
 if payload->>'action'='CHANGE' then
  ops:=case when payload->>'choice'='REPLACE' then '[]'::jsonb else payload->'operations' end;
  if ops is null or jsonb_typeof(ops)<>'array' then raise exception 'output_work_operations';end if;
  successor:=public.plan_manufactured_completion(factory,h.id,jsonb_build_object('group_id',w.group_id,'quantity',w.quantity::text,'choice',payload->>'choice','operations',ops,'reason',why),expected_revision,gen_random_uuid());
 end if;
 select max(revision)+1 into rev from private.manufactured_output_events where factory_id=factory and output_id=h.id;
 result:=jsonb_build_object('item_id',target,'action',payload->>'action','successor',successor,'revision',rev::text,'reason',why,'before',before_state);
 perform private.manufactured_output_authorize(factory,'DISPOSITION',expected_revision);
 if payload->>'action'='CHANGE' then perform private.require_permission(factory,'orders','create');end if;
 if m.id is not null then perform private.require_permission(factory,'warehouse','issue');end if;
 insert into private.manufactured_output_events(factory_id,output_id,request_id,revision,operation,intent,result,created_by)
 values(factory,h.id,request_id,rev,'RETIRE',intent,result,auth.uid());
 delete from private.manufactured_output_context where backend=pg_backend_pid() and transaction_id=txid_current() and mode='REVISION';
 return result;
end$$;
revoke all on function private.output_work_retired(uuid,uuid),private.output_work_revising(uuid,uuid),private.output_work_live(uuid,uuid),private.output_work_allocations(uuid,uuid),private.output_work_revision_state(uuid,uuid),private.output_work_delete_guard() from public,anon,authenticated,service_role;
revoke all on function public.revise_manufactured_completion(uuid,uuid,jsonb,bigint,uuid) from public,anon,service_role;
grant execute on function public.revise_manufactured_completion(uuid,uuid,jsonb,bigint,uuid) to authenticated;
commit;
