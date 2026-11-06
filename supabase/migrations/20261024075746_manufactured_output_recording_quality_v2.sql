-- Phase 2: callable only in disposable fixtures which replace the disabled
-- predicate. No activation setting, stock receipt or scheduling command.
begin;
create function private.manufactured_output_enabled(f uuid) returns boolean
 language sql stable set search_path='' as $$select false$$;
create table private.manufactured_output_context (
 backend integer not null, transaction_id bigint not null, factory_id uuid not null,
 actor_id uuid not null, entry_id uuid, request_id uuid not null, mode text not null check(mode in ('RECORD','CORRECTION')),
 primary key(backend,transaction_id)
);
alter table private.manufactured_output_context enable row level security;
revoke all on private.manufactured_output_context from public,anon,authenticated,service_role;
create function private.manufactured_output_context_matches(f uuid,e uuid,r uuid,mode text) returns boolean
 language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.manufactured_output_context c where c.backend=pg_backend_pid()
 and c.transaction_id=txid_current() and c.factory_id=f and c.actor_id=auth.uid() and c.mode=$4
 and (($4='RECORD' and c.request_id=r) or ($4='CORRECTION' and c.entry_id=e)))
$$;

-- The existing writer still performs execution, shift, permission and physical
-- quantity validation. Only the two output-posting hooks are excluded inside
-- the protected new adapter. An enrollment failure rolls the entire call back.
do $patch$
declare body text;old text;begin
 body:=pg_get_functiondef('private.capture_finished_good()'::regprocedure);
 old:='begin';
 if position(old in body)=0 then raise exception 'capture contract changed';end if;
 body:=overlay(body placing E'begin\n if private.manufactured_output_context_matches(new.factory_id,new.id,new.request_id,''RECORD'') or private.manufactured_output_context_matches(new.factory_id,new.id,new.request_id,''CORRECTION'') then return new;end if;'
 from position(old in body) for length(old));execute body;
 body:=pg_get_functiondef('private.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,text,numeric,text,uuid,numeric,jsonb,jsonb)'::regprocedure);
 old:='if unfinished>0 then';
 if (length(body)-length(replace(body,old,'')))/length(old)<>1 then raise exception 'record WIP contract changed';end if;
 execute replace(body,old,'if unfinished>0 and not private.manufactured_output_context_matches(f,result,r,''RECORD'') then');
end $patch$;

create function public.record_manufactured_output(factory uuid,payload jsonb,request_id uuid) returns jsonb
 language plpgsql volatile security definer set search_path='' as $$
declare prior private.manufactured_output_events;entry public.production_entries;receipt jsonb;intent jsonb;declared jsonb;context jsonb;begin
 perform private.recording_v3_authorize(factory);
 if not private.manufactured_output_enabled(factory) then raise exception 'recording_disabled' using errcode='55000';end if;
 if current_setting('transaction_isolation')<>'read committed' or request_id is null or payload is null or jsonb_typeof(payload)<>'object'
 or not payload ?& array['output_groups','recording_context'] or octet_length(payload::text)>60000 then raise exception 'output_invalid' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));
 perform pg_advisory_xact_lock(hashtextextended(factory::text||':structure',0));
 perform private.recording_v3_authorize(factory);
 if not private.manufactured_output_enabled(factory) then raise exception 'recording_disabled' using errcode='55000';end if;
 intent:=jsonb_build_object('payload',payload);
 select ev.* into prior from private.manufactured_output_events ev where ev.factory_id=factory and ev.request_id=record_manufactured_output.request_id;
 if found then
  if prior.operation<>'DECLARE' or prior.created_by<>auth.uid() or prior.result->'recording_intent' is distinct from intent then raise exception 'request_conflict' using errcode='40001';end if;
  return prior.result->'receipt'||jsonb_build_object('replayed',true);
 end if;
 if exists(select 1 from public.production_entries e where e.factory_id=factory and e.request_id=record_manufactured_output.request_id) then raise exception 'request_conflict' using errcode='40001';end if;
 context:=private.recording_v3_context(factory,(payload->>'item')::uuid,private.recording_request_payload(factory,payload-'output_groups')->'payload');
 insert into private.manufactured_output_context values(pg_backend_pid(),txid_current(),factory,auth.uid(),null,request_id,'RECORD');
 receipt:=private.record_lean_production(factory,payload-'output_groups',request_id);
 select * into entry from public.production_entries where factory_id=factory and id=(receipt->>'entry_id')::uuid;
 if entry.id is null then raise exception 'output_invalid' using errcode='22023';end if;
 declared:=private.manufactured_output_command(factory,'DECLARE',entry.id,jsonb_build_object('groups',payload->'output_groups','recording_intent',intent,'receipt',receipt),0,request_id);
 delete from private.manufactured_output_context where backend=pg_backend_pid() and transaction_id=txid_current();
 perform private.recording_v3_authorize(factory);
 if clock_timestamp()>=(context#>>'{occurrence,ends_at}')::timestamptz then raise exception 'recording_shift_expired' using errcode='22023';end if;
 return receipt;
end$$;

-- Persist the full new intent with the immutable declaration, not by rewriting
-- an accepted V3 receipt. Replay compares both scalar and group intent.
do $patch$
declare body text;old text;begin
 body:=pg_get_functiondef('private.manufactured_output_command(uuid,text,uuid,jsonb,bigint,uuid)'::regprocedure);
 old:='where k<>''groups''';
 if position(old in body)=0 then raise exception 'declaration contract changed';end if;
 body:=replace(body,old,'where k not in (''groups'',''recording_intent'',''receipt'')');
 -- An exception-safe caller may own a subtransaction xmin. The private adapter
 -- context is equally strict and cannot adopt an existing entry (UUID checked
 -- before context creation). No session-variable or client-controlled bypass.
 old:='or not exists(select 1 from public.production_entries where id=e.id and xmin::text=pg_current_xact_id()::text)';
 if position(old in body)=0 then raise exception 'declaration transaction contract changed';end if;
 body:=replace(body,old,'or (not exists(select 1 from public.production_entries where id=e.id and xmin::text=pg_current_xact_id()::text) and not private.manufactured_output_context_matches(f,e.id,e.request_id,''RECORD''))');
 old:='rev:=1;result:=jsonb_build_object';
 body:=replace(body,old,'rev:=1;result:=jsonb_build_object');
 old:='''groups'',groups);';
 if position(old in body)=0 then raise exception 'declaration result changed';end if;
 body:=replace(body,old,'''groups'',groups,''recording_intent'',p->''recording_intent'',''receipt'',p->''receipt'');');
 execute body;
end $patch$;

create function public.manufactured_output_command(factory uuid,operation text,target uuid,payload jsonb,expected_revision bigint,request_id uuid) returns jsonb
 language plpgsql volatile security definer set search_path='' as $$begin
 if operation not in ('QUALITY','ACKNOWLEDGE') or operation is null then raise exception 'output_invalid' using errcode='22023';end if;
 perform private.manufactured_output_authorize(factory,operation,case when operation='QUALITY' then case when exists(select 1 from private.manufactured_output_events ev where ev.factory_id=factory and ev.output_id=target and ev.operation='QUALITY') then 2 else 1 end else expected_revision end);
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));
 if not private.manufactured_output_enabled(factory) then raise exception 'recording_disabled' using errcode='55000';end if;
 return private.manufactured_output_command(factory,operation,target,payload,expected_revision,request_id);
end$$;

-- Read original and inspected results separately; never claim that release is
-- stock. Notifications are the immutable Quality events plus per-person ACKs.
create function public.manufactured_output_read(factory uuid,mode text default 'list',target uuid default null,page integer default 0) returns jsonb
 language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;rows jsonb;is_quality boolean;begin
 perform private.require_permission(factory,'factory','view');
 is_quality:=private.has_permission(factory,'quality','view');
 if mode='quality' then perform private.require_permission(factory,'quality','view');
 else perform private.require_permission(factory,'orders','view');end if;
 if not private.manufactured_output_enabled(factory) then return jsonb_build_object('available',false,'rows','[]'::jsonb);end if;
 if mode not in ('list','quality','notifications','entry','options','status') or page<0 or page>100000 then raise exception 'output_invalid' using errcode='22023';end if;
 if mode='status' then
  perform private.recording_v3_authorize(factory);
  select ev.result->'receipt' into result from private.manufactured_output_events ev where ev.factory_id=factory and ev.request_id=target and ev.operation='DECLARE' and ev.created_by=auth.uid();
  return jsonb_build_object('contract_version',3,'outcome',case when result is null then 'UNKNOWN' else 'COMMITTED' end,'receipt',result);
 end if;
 if mode='options' then
  select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',c.name,'name_ar',c.name_ar) order by s.id),'[]') into rows
   from public.production_orders o join public.production_routing_steps s on s.factory_id=o.factory_id and s.product_id=o.product_id and s.kind='work_center'
   join public.work_centers c on c.factory_id=s.factory_id and c.id=s.work_center_id where o.factory_id=factory and o.id=target;
  return jsonb_build_object('available',true,'operations',rows);
 end if;
 select coalesce(jsonb_agg(x.row order by x.created_at desc,x.id),'[]') into rows from (
 select h.id,h.created_at,jsonb_build_object('id',h.id,'entry_id',h.entry_id,'item_id',h.item_id,'product_id',h.product_id,'unit',h.unit,
 'product_name',pr.name,'product_name_ar',pr.name_ar,'request_code',e.request_code,'item_code',e.item_code,'line_name',e.line_name,'shift_name',e.effective_occurrence->>'name','original',h.recorded_groups,'source',h.source_snapshot,'operations',h.operation_snapshot,
 'revision',(select max(revision) from private.manufactured_output_events ev where ev.output_id=h.id),
 'notification_revision',(select max(revision) from private.manufactured_output_events ev where ev.output_id=h.id and ev.operation='QUALITY'),
 'quality',(select ev.result from private.manufactured_output_events ev where ev.output_id=h.id and ev.operation='QUALITY' order by revision desc limit 1),
 'history',(select coalesce(jsonb_agg(jsonb_build_object('operation',ev.operation,'revision',ev.revision,'result',ev.result-array['receipt','recording_intent'],
 'actor',ev.created_by,'at',ev.created_at) order by ev.revision),'[]') from private.manufactured_output_events ev where ev.output_id=h.id and ev.operation in ('QUALITY','CORRECTION')),
 'unread',exists(select 1 from private.manufactured_output_events q where q.output_id=h.id and q.operation='QUALITY' and not exists(select 1 from private.manufactured_output_events a where a.output_id=h.id and a.operation='ACKNOWLEDGE' and a.created_by=auth.uid() and (a.result->>'quality_revision')::bigint>=q.revision)),
 'can_inspect',is_quality and private.has_permission(factory,'quality',case when exists(select 1 from private.manufactured_output_events ev where ev.output_id=h.id and ev.operation='QUALITY') then 'edit' else 'create' end)) row
 from private.manufactured_outputs h join public.products pr on pr.factory_id=h.factory_id and pr.id=h.product_id
 join private.production_reporting_entries e on e.factory_id=h.factory_id and e.id=h.entry_id
 where h.factory_id=factory and (mode<>'entry' or h.entry_id=target)
 and (mode<>'notifications' or exists(select 1 from private.manufactured_output_events ev where ev.output_id=h.id and ev.operation='QUALITY'))
 order by h.created_at desc,h.id limit 50 offset page*50) x;
 return jsonb_build_object('available',true,'rows',rows,'page',page,'has_more',jsonb_array_length(rows)=50);
end$$;

-- Existing correction approval remains the only authority to change physical
-- recorded amounts. Phase 2 supports Good/KG/context corrections, but leaves
-- unfinished group resizing and post-receipt reconciliation fail closed.
alter table private.manufactured_output_events drop constraint manufactured_output_events_operation_check;
alter table private.manufactured_output_events add constraint manufactured_output_events_operation_check check(operation in ('DECLARE','QUALITY','RECEIPT','DISPOSITION','ACKNOWLEDGE','CORRECTION'));
create function private.manufactured_output_correction_values(f uuid,e uuid) returns jsonb
 language sql stable security definer set search_path='' as $$
 select private.production_correction_values(f,e)||coalesce((select jsonb_build_object('output_revision',(select max(revision) from private.manufactured_output_events ev where ev.output_id=h.id)) from private.manufactured_outputs h where h.factory_id=f and h.entry_id=e),'{}'::jsonb)
$$;
create function private.apply_manufactured_output_correction(f uuid,p jsonb,r uuid) returns uuid
 language plpgsql volatile security definer set search_path='' as $$
declare h private.manufactured_outputs;result uuid;groups jsonb;g jsonb;rev bigint;values jsonb;begin
 select * into h from private.manufactured_outputs where factory_id=f and entry_id=(p->>'entry')::uuid;
 if h.id is null then return private.apply_approved_production_correction(f,p,r);end if;
 perform private.production_correction_authorize(f,true);
 if not private.manufactured_output_enabled(f) then raise exception 'recording_disabled' using errcode='55000';end if;
 if exists(select 1 from private.manufactured_output_events where output_id=h.id and operation in ('RECEIPT','DISPOSITION')) then raise exception 'output_reconciliation_required' using errcode='23514';end if;
 values:=private.production_correction_values(f,h.entry_id);
 if coalesce((p->>'unfinished')::numeric,0)<>(values->>'unfinished')::numeric or coalesce(p->>'remaining_work','')<>coalesce(values->>'remaining_work','') then raise exception 'output_group_correction_deferred' using errcode='23514';end if;
 insert into private.manufactured_output_context values(pg_backend_pid(),txid_current(),f,auth.uid(),h.entry_id,r,'CORRECTION');
 result:=private.apply_approved_production_correction(f,p,r);
 delete from private.manufactured_output_context where backend=pg_backend_pid() and transaction_id=txid_current();
 select coalesce(jsonb_agg(value),'[]') into groups from jsonb_array_elements(h.recorded_groups) where jsonb_array_length(value->'missing_operations')>0;
 if (p->>'good')::numeric>0 then
  select value into g from jsonb_array_elements(h.recorded_groups) where jsonb_array_length(value->'missing_operations')=0 limit 1;
  groups:=groups||jsonb_build_array(jsonb_build_object('id',coalesce(g->>'id',gen_random_uuid()::text),'quantity',trim_scale((p->>'good')::numeric)::text,'released','0','restriction','','missing_operations','[]'::jsonb));
 end if;
 select max(revision)+1 into rev from private.manufactured_output_events where output_id=h.id;
 values:=private.production_correction_values(f,h.entry_id)||jsonb_build_object('technician_id',h.source_snapshot->'technician_id','recorded_at',h.source_snapshot->'recorded_at');
 insert into private.manufactured_output_events(factory_id,output_id,request_id,revision,operation,intent,result,created_by)
 values(f,h.id,r,rev,'CORRECTION',p,jsonb_build_object('output_id',h.id,'revision',rev,'correction_id',result,'groups',groups,'source',values,
 'quantity',trim_scale((values->>'good')::numeric+(values->>'unfinished')::numeric)::text,'reason',p->>'reason','requires_reinspection',true),auth.uid());
 return result;
end$$;
do $patch$
declare body text;old text;sig text;begin
 body:=pg_get_functiondef('private.manufactured_output_source_guard()'::regprocedure);
 body:=replace(body,'and (to_jsonb(new)',E'and not private.manufactured_output_context_matches(old.factory_id,old.id,old.request_id,''CORRECTION'')\n and (to_jsonb(new)');execute body;
 body:=pg_get_functiondef('private.correct_production(uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,boolean,numeric,text)'::regprocedure);
 old:='if lot.id is null and unfinished>0 then';
 if position(old in body)=0 then raise exception 'correction WIP contract changed';end if;
 execute replace(body,old,'if lot.id is null and unfinished>0 and not private.manufactured_output_context_matches(f,e,r,''CORRECTION'') then');
 foreach sig in array array['private.apply_production_correction_request(uuid,uuid)','private.submit_production_correction(uuid,jsonb,jsonb,uuid,bigint,boolean)'] loop
  body:=pg_get_functiondef(sig::regprocedure);
  body:=replace(body,'private.production_correction_values(', 'private.manufactured_output_correction_values(');
  body:=replace(body,'result:=private.apply_approved_production_correction(f,row.proposed,row.submission_id);','result:=private.apply_manufactured_output_correction(f,row.proposed,row.submission_id);');
  body:=replace(body,'if not row.legacy and (row.proposed', 'if not row.legacy and not current_values ? ''output_revision'' and (row.proposed');
  body:=replace(body,'if not legacy and ((q->>','if not legacy and not base ? ''output_revision'' and ((q->>');
  body:=replace(body,'insert into private.production_correction_requests(',E'if base ? ''output_revision'' and jsonb_array_length(picks)>0 then raise exception ''output_no_stock'' using errcode=''23514'';end if;\n insert into private.production_correction_requests(');
  execute body;
 end loop;
 body:=pg_get_functiondef('public.production_correction_context(uuid,uuid)'::regprocedure);
 body:=replace(body,'''id'',e.id,','''output_pre_receipt'',exists(select 1 from private.manufactured_outputs h where h.factory_id=factory and h.entry_id=e.id),''id'',e.id,');execute body;
 body:=pg_get_functiondef('private.manufactured_output_command(uuid,text,uuid,jsonb,bigint,uuid)'::regprocedure);
 body:=replace(body,'private.manufactured_output_authorize(f,op,expected)', 'private.manufactured_output_authorize(f,op,case when op=''QUALITY'' then case when exists(select 1 from private.manufactured_output_events where factory_id=f and output_id=target and operation=''QUALITY'') then 2 else 1 end else expected end)');
 old:='if (h.source_snapshot-array';
 body:=replace(body,old,E'select ev.result into result from private.manufactured_output_events ev where ev.output_id=h.id and ev.operation=''CORRECTION'' order by revision desc limit 1;\n if result is not null then h.source_snapshot:=result->''source'';h.quantity:=(result->>''quantity'')::numeric;end if;\n if (h.source_snapshot-array');
 body:=replace(body,'and operation=''QUALITY'' order by revision desc limit 1;', 'and operation=''QUALITY'' and revision>coalesce((select max(c.revision) from private.manufactured_output_events c where c.output_id=h.id and c.operation=''CORRECTION''),0) order by revision desc limit 1;');execute body;
 -- The reader also invalidates release after a physical correction; the earlier
 -- decision remains in immutable history and is never represented as current.
 body:=pg_get_functiondef('public.manufactured_output_read(uuid,text,uuid,integer)'::regprocedure);
 body:=replace(body,'and ev.operation=''QUALITY'' order by revision desc limit 1)', 'and ev.operation=''QUALITY'' and revision>coalesce((select max(c.revision) from private.manufactured_output_events c where c.output_id=h.id and c.operation=''CORRECTION''),0) order by revision desc limit 1)');
 body:=replace(body,'''original'',h.recorded_groups,','''recorded'',coalesce((select ev.result->''groups'' from private.manufactured_output_events ev where ev.output_id=h.id and ev.operation=''CORRECTION'' order by revision desc limit 1),h.recorded_groups),''original'',h.recorded_groups,');execute body;
end $patch$;
revoke all on function private.manufactured_output_correction_values(uuid,uuid),private.apply_manufactured_output_correction(uuid,jsonb,uuid) from public,anon,authenticated,service_role;
revoke all on function private.manufactured_output_enabled(uuid),private.manufactured_output_context_matches(uuid,uuid,uuid,text) from public,anon,authenticated,service_role;
revoke all on function public.record_manufactured_output(uuid,jsonb,uuid),public.manufactured_output_command(uuid,text,uuid,jsonb,bigint,uuid),public.manufactured_output_read(uuid,text,uuid,integer) from public,anon,service_role;
grant execute on function public.record_manufactured_output(uuid,jsonb,uuid),public.manufactured_output_command(uuid,text,uuid,jsonb,bigint,uuid),public.manufactured_output_read(uuid,text,uuid,integer) to authenticated;
commit;
