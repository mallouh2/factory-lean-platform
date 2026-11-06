-- Replacement of reviewed unfinished output does not require a Warehouse receipt.
-- Only demand entitlement changes; existing physical ledgers remain authoritative.
begin;
alter table private.production_compensation_releases drop constraint production_compensation_releases_pkey;
alter table private.production_compensation_releases alter column lot_id drop not null;
alter table private.production_compensation_releases add primary key(factory_id,compensation_id,group_id);

create function private.compensation_group_remaining(f uuid,o uuid,g uuid) returns numeric
language sql stable security definer set search_path='' as $$
 select greatest(coalesce((select (v->>'quantity')::numeric from jsonb_array_elements(private.output_quality(f,o)->'groups')v where v->>'id'=g::text and jsonb_array_length(v->'missing_operations')>0),0)
 -coalesce((select sum((e.result->>'quantity')::numeric) from private.manufactured_output_events e where e.factory_id=f and e.output_id=o and e.operation='DISPOSITION' and e.result->>'group_id'=g::text
 and not exists(select 1 from private.manufactured_completion_work w where w.factory_id=f and w.request_id=e.request_id and not private.output_work_live(f,w.item_id))),0),0)
$$;
revoke all on function private.compensation_group_remaining(uuid,uuid,uuid) from public,anon,authenticated,service_role;

create or replace function private.output_work_allocations(f uuid,l uuid)
returns table(assigned numeric,replaced numeric,stock numeric,reserved numeric) language sql stable security definer set search_path='' as $$
 with w as (select coalesce(sum(quantity) filter(where choice in ('COMPLETE','REPLACE')),0) a,
 coalesce(sum(quantity) filter(where choice='REPLACE'),0) r,coalesce(sum(quantity) filter(where choice='STOCK'),0) s,
 coalesce(sum(quantity-private.output_work_consumed(f,item_id)) filter(where choice<>'REPLACE' and exists(select 1 from public.material_requests mr where mr.factory_id=f and mr.id=material_request_id and mr.status='REQUESTED')),0) v
 from private.manufactured_completion_work where factory_id=f and lot_id=l and private.output_work_live(f,item_id)),
 r as(select coalesce(sum(r.quantity),0) q from private.production_compensation_releases r join private.production_compensation c on c.factory_id=r.factory_id and c.id=r.compensation_id
 where r.factory_id=f and (r.lot_id=l or r.lot_id is null and exists(select 1 from private.manufactured_output_lots m where m.factory_id=f and m.lot_id=l and m.output_id=c.output_id and m.group_id=r.group_id)))
 select w.a+r.q,w.r+r.q,w.s,w.v from w,r
$$;
CREATE OR REPLACE FUNCTION private.production_compensation_state(f uuid, o uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare h private.manufactured_outputs;j public.production_orders;d uuid;v bigint;accepted numeric;pending numeric;awaiting numeric;baseline numeric;
 active_left numeric;assigned numeric;source_used numeric;unassigned numeric;rejected numeric;held boolean;available numeric;begin
 select * into h from private.manufactured_outputs where factory_id=f and id=o;
 if h.id is null then raise exception 'output_not_found';end if;
 d:=private.output_work_demand(f,h.item_id);select * into j from public.production_orders where factory_id=f and id=d;
 select max(revision) into v from private.manufactured_output_events where factory_id=f and output_id=o and operation='QUALITY' and revision>coalesce((select max(revision) from private.manufactured_output_events where factory_id=f and output_id=o and operation='CORRECTION'),0);
 -- Use reviewed/applied quantities. Any unreconciled finding blocks the decision.
 select exists(select 1 from private.manufactured_outputs z join private.output_hold_rows(f) hr on hr.output_id=z.id
 where z.factory_id=f and private.output_work_demand(f,z.item_id)=d) into held;
 select coalesce(sum((g->>'quantity')::numeric),0) into accepted from private.manufactured_outputs z
 cross join lateral jsonb_array_elements(private.output_quality(f,z.id)->'groups') g
 where z.factory_id=f and private.output_work_demand(f,z.item_id)=d and jsonb_array_length(g->'missing_operations')=0;
 select coalesce(sum(greatest(w.quantity-private.compensation_gross(f,w.item_id),0)),0) into pending
 from private.manufactured_completion_work w where w.factory_id=f and w.demand_item_id=d and w.choice<>'STOCK' and private.output_work_live(f,w.item_id);
 select coalesce(sum(private.compensation_remaining(f,c.id)),0) into active_left
 from private.production_compensation c where c.factory_id=f and c.demand_item_id=d and c.mode='ACTIVE';
 select coalesce(sum((g->>'quantity')::numeric),0) into awaiting from private.manufactured_outputs z
 cross join lateral jsonb_array_elements(coalesce((select e.result->'groups' from private.manufactured_output_events e where e.factory_id=f and e.output_id=z.id and e.operation='CORRECTION' order by e.revision desc limit 1),z.recorded_groups)) g
 where z.factory_id=f and private.output_work_demand(f,z.item_id)=d and private.output_finding(f,z.id) is null;
 accepted:=accepted+awaiting;
 baseline:=case when j.status='active' then greatest(j.target_quantity-private.compensation_gross(f,d)+private.compensation_recorded(f,d),0) else 0 end;
 select coalesce(sum(private.compensation_group_remaining(f,o,(g->>'id')::uuid)),0) into unassigned
 from jsonb_array_elements(private.output_quality(f,o)->'groups') g where jsonb_array_length(g->'missing_operations')>0;
 rejected:=coalesce((private.output_quality(f,o)->>'rejected')::numeric,0);
 select coalesce(sum(c.quantity),0) into source_used from private.production_compensation c where c.factory_id=f and c.output_id=o;
 -- Legacy source-backed REPLACE also spends rejection/unfinished coverage.
 select coalesce(sum(w.quantity),0) into assigned from private.manufactured_completion_work w
 where w.factory_id=f and w.output_id=o and w.choice='REPLACE' and w.lot_id is not null and private.output_work_live(f,w.item_id);
 available:=greatest(least(j.target_quantity-accepted-pending-baseline-greatest(active_left,0),greatest(rejected-source_used,0)+greatest(unassigned,0)),0);
 return jsonb_build_object('output_id',o,'demand_item_id',d,'original_target',j.target_quantity::text,'accepted',(accepted-awaiting)::text,'pending_inspection',awaiting::text,
 'received',private.output_demand_received(f,d)::text,'pending_work',pending::text,'active_allowance_remaining',greatest(active_left,0)::text,
 'unfinished_sources',(select coalesce(jsonb_agg(jsonb_build_object('group_id',g->>'id','quantity',g->>'quantity','unassigned',private.compensation_group_remaining(f,o,(g->>'id')::uuid)::text,
 'received',private.output_received(f,o,g->>'id')::text,'stored',(select l.warehouse_quantity::text from private.manufactured_output_lots m join public.unfinished_lots l on l.factory_id=m.factory_id and l.id=m.lot_id where m.factory_id=f and m.output_id=o and m.group_id::text=g->>'id'))),'[]'::jsonb) from jsonb_array_elements(private.output_quality(f,o)->'groups') g where jsonb_array_length(g->'missing_operations')>0),
 'unfinished_unassigned',greatest(unassigned,0)::text,'rejected',rejected::text,'available',case when v is null or held or d is null then '0' else available::text end,
 'quality_revision',v::text,'revision',(select max(revision)::text from private.manufactured_output_events where factory_id=f and output_id=o),
 'transfer_allowance',(select jsonb_build_object('id',c.id,'remaining',private.compensation_remaining(f,c.id)::text) from private.production_compensation c where c.factory_id=f and c.output_id=o and c.mode='ACTIVE' and j.status='completed' and private.compensation_remaining(f,c.id)>0 order by c.created_at,c.id limit 1),'status',j.status,'mode',case when j.status='active' then 'ACTIVE' when j.status='completed' then 'PLANNED' end,
 'blocked_reason',case when v is null then 'output_quality_required' when held then 'output_quality_hold' when j.status not in ('active','completed') then 'output_execution_required' when available<=0 then case when j.target_quantity-accepted-pending-baseline-greatest(active_left,0)<=0 then 'output_demand_covered' else 'output_source_entitlement_unavailable' end end);
end$function$;


CREATE OR REPLACE FUNCTION public.plan_production_compensation(factory uuid, target uuid, payload jsonb, expected_revision bigint, request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare h private.manufactured_outputs;j public.production_orders;s jsonb;c private.production_compensation;intent jsonb;r jsonb;q numeric;mode text;
 left_q numeric;reject_left numeric;v record;take numeric;pr uuid;i uuid;releases jsonb:='[]';gid uuid;why text;quality_evidence jsonb;begin
 perform private.manufactured_output_authorize(factory,'DISPOSITION',expected_revision);perform private.require_permission(factory,'orders','create');
 if current_setting('transaction_isolation')<>'read committed' then raise exception 'recording_isolation' using errcode='40001';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.fulfillment_lock(factory);
 perform pg_advisory_xact_lock(hashtextextended(factory::text||':structure',0));
 perform private.manufactured_output_authorize(factory,'DISPOSITION',expected_revision);perform private.require_permission(factory,'orders','create');
 if not private.manufactured_output_enabled(factory) then raise exception 'recording_disabled';end if;
 if request_id is null or jsonb_typeof(payload) is distinct from 'object' or expected_revision is null or exists(select 1 from jsonb_object_keys(payload) k where k not in ('quantity','reason','mode','allowance_id','recording_complete_confirmation'))
 or (payload ? 'reason' and length(btrim(coalesce(payload->>'reason',''))) not between 3 and 2000) then raise exception 'output_disposition';end if;
 intent:=jsonb_build_object('target',target,'payload',payload,'expected',expected_revision);
 select * into c from private.production_compensation where factory_id=factory and id=request_id;
 if found then if c.created_by<>auth.uid() or (c.intent-'quality_evidence')<>intent then raise exception 'request_conflict' using errcode='40001';end if;return c.result;end if;
 if exists(select 1 from private.manufactured_completion_work w where w.factory_id=factory and w.request_id=plan_production_compensation.request_id) then
 select w.result into r from private.manufactured_completion_work w where w.factory_id=factory and w.request_id=plan_production_compensation.request_id and w.created_by=auth.uid() and (w.intent-'quality_evidence')=jsonb_build_object('target',target,'payload',payload,'expected',expected_revision);
 if r is null then raise exception 'request_conflict' using errcode='40001';end if;return r;end if;
 select * into h from private.manufactured_outputs where factory_id=factory and id=target for update;
 if h.id is null then raise exception 'output_not_found';end if;
 s:=private.production_compensation_state(factory,target);
 if (s->>'revision')::bigint is distinct from expected_revision then raise exception 'output_revision' using errcode='40001';end if;
 -- Source evidence is server-derived after exact replay and revision checks.
 why:=coalesce(nullif(btrim(payload->>'reason'),''),left('Quality finding '||(s->>'quality_revision')||' for '||(select code from public.production_orders where factory_id=factory and id=(s->>'demand_item_id')::uuid)||': '||coalesce(nullif(private.output_quality(factory,h.id)->>'reason',''),'Recoverable unfinished or rejected output requires replacement'),2000));
 quality_evidence:=jsonb_build_object('quality_id',(select id from private.manufactured_output_events where factory_id=factory and output_id=h.id and revision=(s->>'quality_revision')::bigint and operation='QUALITY'),
 'quality_revision',s->>'quality_revision','original_reference',(select code from public.production_orders where factory_id=factory and id=(s->>'demand_item_id')::uuid),
 'quality_reason',private.output_quality(factory,h.id)->>'reason','groups',private.output_quality(factory,h.id)->'groups','rejected',s->>'rejected','decision_type','REPLACE','reason_source',case when payload?'reason' then 'USER' else 'QUALITY' end,'audit_reason',why);
 intent:=intent||jsonb_build_object('quality_evidence',quality_evidence);
 if payload->>'allowance_id' is not null then if payload->'recording_complete_confirmation' is distinct from 'true'::jsonb then raise exception 'output_recording_confirmation';end if;
 select * into c from private.production_compensation where factory_id=factory and id=(payload->>'allowance_id')::uuid;
 select * into j from public.production_orders where factory_id=factory and id=(s->>'demand_item_id')::uuid for update;
 q:=(payload->>'quantity')::numeric;
 if c.id is null or c.output_id<>h.id or c.mode<>'ACTIVE' or j.status<>'completed' or payload->>'mode' is distinct from 'PLANNED'
 or c.quality_revision is distinct from (s->>'quality_revision')::bigint or s->>'blocked_reason'='output_quality_hold'
 or q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity') or q>private.compensation_remaining(factory,c.id) or (h.unit='piece' and q<>trunc(q)) then raise exception 'output_compensation_transfer';end if;
 pr:=public.create_production_request(factory,'Replacement production','high',null,why,jsonb_build_array(jsonb_build_object('product_id',h.product_id,'quantity',q,'unit',h.unit)));
 select po.id into i from public.production_orders po where po.factory_id=factory and po.request_id=pr;
 r:=jsonb_build_object('allowance_id',c.id,'item_id',i,'origin_item_id',j.id,'mode','PLANNED','quantity',q::text,'received','0');
 insert into private.manufactured_completion_work values(factory,i,h.id,null,null,h.item_id,j.id,'REPLACE',q,'[]',null,request_id,intent,r,auth.uid(),clock_timestamp());
 return r;
 end if;
 if s->>'blocked_reason' is not null then raise exception '%',s->>'blocked_reason';end if;
 q:=(payload->>'quantity')::numeric;mode:=payload->>'mode';
 if q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity') or q>(s->>'available')::numeric or (h.unit='piece' and q<>trunc(q)) or (mode is distinct from s->>'mode' and not(mode='PLANNED' and s->>'mode'='ACTIVE')) then raise exception 'output_compensation_quantity';end if;
 select * into j from public.production_orders where factory_id=factory and id=(s->>'demand_item_id')::uuid for update;
 if mode='ACTIVE' then perform private.compensation_capacity(factory,j,q+(s->>'active_allowance_remaining')::numeric);i:=j.id;
 elsif mode='PLANNED' and j.status in ('active','completed') then
 if j.status='active' then
 begin perform private.compensation_capacity(factory,j,q+(s->>'active_allowance_remaining')::numeric);
 exception when raise_exception then if sqlerrm='output_planning_conflict' then gid:=j.id;else raise;end if;end;
 if gid is null then raise exception 'output_active_execution';end if;
 end if;
 pr:=public.create_production_request(factory,'Replacement production','high',null,why,jsonb_build_array(jsonb_build_object('product_id',h.product_id,'quantity',q,'unit',h.unit)));
 select po.id into i from public.production_orders po where po.factory_id=factory and po.request_id=pr;
 else raise exception 'output_execution_required';end if;
 r:=jsonb_build_object('compensation_id',request_id,'item_id',i,'origin_item_id',j.id,'mode',mode,'quantity',q::text,'received','0');
 insert into private.production_compensation values(factory,request_id,h.id,(s->>'quality_revision')::bigint,j.id,i,mode,q,
 case when mode='ACTIVE' then j.actual_start end,case when mode='ACTIVE' then j.line_id end,why,intent,r,auth.uid(),clock_timestamp());
 if mode='PLANNED' then
 insert into private.manufactured_completion_work values(factory,i,h.id,null,null,h.item_id,j.id,'REPLACE',q,'[]',null,request_id,intent,r,auth.uid(),clock_timestamp());
 end if;
 select greatest((s->>'rejected')::numeric-coalesce(sum(quantity),0),0) into reject_left from private.production_compensation where factory_id=factory and output_id=h.id and id<>request_id;
 left_q:=greatest(q-reject_left,0);
 for v in select g.value as classification,(g.value->>'id')::uuid group_id,m.lot_id
 from jsonb_array_elements(private.output_quality(factory,h.id)->'groups') g
 left join private.manufactured_output_lots m on m.factory_id=factory and m.output_id=h.id and m.group_id::text=g.value->>'id'
 where jsonb_array_length(g.value->'missing_operations')>0 order by g.value->>'id' loop
  exit when left_q=0;
  take:=least(left_q,private.compensation_group_remaining(factory,h.id,v.group_id));if take=0 then continue;end if;
  if private.output_group_held(factory,h.id,v.group_id) then raise exception 'output_quality_hold';end if;
  if v.lot_id is not null then
   perform 1 from public.unfinished_lots where factory_id=factory and id=v.lot_id for update;
   if take>(select greatest(l.quantity_available-a.reserved,0) from public.unfinished_lots l cross join lateral private.output_work_allocations(factory,l.id) a where l.factory_id=factory and l.id=v.lot_id) then raise exception 'output_allocation_unavailable';end if;
  end if;
  -- DISPOSITION already supports classified output before physical receiving.
  -- A nullable lot records no receipt, issue, consumption or stock movement.
  perform private.manufactured_output_command(factory,'DISPOSITION',h.id,jsonb_build_object('group_id',v.group_id,'quantity',take::text,'choice','REPLACE','reason',why),
   (select max(revision) from private.manufactured_output_events where factory_id=factory and output_id=h.id),gen_random_uuid());
  insert into private.production_compensation_releases values(factory,request_id,v.lot_id,v.group_id,take);left_q:=left_q-take;
 end loop;
 if left_q<>0 then raise exception 'output_allocation_unavailable';end if;
 perform private.manufactured_output_authorize(factory,'DISPOSITION',expected_revision);perform private.require_permission(factory,'orders','create');
 return r;
end$function$;


-- Existing work readers retain the server-derived reason alongside old user reasons.
do $$declare b text;n text;sig text;begin
 foreach sig in array array['public.manufactured_completion_read(uuid,integer)','public.manufactured_completion_context(uuid,uuid,uuid,integer)']loop
 b:=pg_get_functiondef(sig::regprocedure);n:='w.intent->''payload''->>''reason'' reason';
 if position(n in b)=0 then raise exception 'Completion reason projection changed';end if;
 execute replace(b,n,'coalesce(w.intent->''quality_evidence''->>''audit_reason'',w.intent->''payload''->>''reason'') reason');
 end loop;
end$$;
commit;
