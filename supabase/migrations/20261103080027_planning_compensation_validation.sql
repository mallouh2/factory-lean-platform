begin;
create function private.compensation_conflict(f uuid,j public.production_orders,starts timestamptz,ends timestamptz) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('kind','PRODUCTION','item_id',x.id,'code',x.code,'start',x.start_time,'finish',x.expected_finish)
 from public.production_orders x where x.factory_id=f and x.id<>j.id and x.line_id=j.line_id and
 (x.status='active' or x.status='planned' and x.start_time is not null and x.expected_finish is not null and x.start_time<ends and x.expected_finish>starts)
 order by x.start_time nulls first,x.id limit 1
$$;revoke all on function private.compensation_conflict(uuid,public.production_orders,timestamptz,timestamptz)from public,anon,authenticated;
CREATE OR REPLACE FUNCTION private.compensation_capacity(f uuid, j production_orders, q numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare rate numeric;fast numeric;ends timestamptz;collision jsonb;occ jsonb;e jsonb;ready jsonb;begin
 occ:=private.resolve_production_occurrence(f,clock_timestamp())->'occurrence';
 e:=private.production_recording_eligibility(j,occ,clock_timestamp());
 if e->>'active_recording_eligible' is distinct from 'true' or j.status<>'active' or j.actual_finish is not null then raise exception 'output_active_context';end if;
 ready:=private.maintenance_execution_readiness(f,j.id,j.line_id,j.product_id);
 if ready->>'ready' is distinct from 'true' then raise exception 'output_not_ready';end if;
 select min(c.rate),max(c.rate) into rate,fast from public.work_centers w join public.work_center_capabilities c on c.factory_id=w.factory_id and c.work_center_id=w.id
 where w.factory_id=f and w.line_id=j.line_id and not w.archived and c.product_id=j.product_id and c.rate_unit=j.unit;
 if rate is null or rate<=0 or rate<>fast then raise exception 'output_capacity_unknown';end if;
 ends:=private.finish_after_working_minutes(f,private.next_working_start(f,clock_timestamp()),greatest(ceil((greatest(j.target_quantity-private.compensation_gross(f,j.id)+private.compensation_recorded(f,j.id),0)+q)/rate*60)::integer,1));
 if ends>=(occ->>'ends_at')::timestamptz then raise exception 'output_shift_capacity';end if;
 collision:=private.compensation_conflict(f,j,clock_timestamp(),ends);if collision is not null then raise exception 'output_planning_conflict' using detail=collision::text;end if;
 perform private.maintenance_assert_capacity(f,j.line_id,j.product_id,null,clock_timestamp(),ends,null,j.id,false);
end$function$;
CREATE OR REPLACE FUNCTION public.production_compensation_read(factory uuid, target uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 declare s jsonb;j public.production_orders;why text;collision jsonb;detail_text text;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'orders','view');
 if not private.manufactured_output_enabled(factory) then return jsonb_build_object('available','0','blocked_reason','recording_disabled');end if;
 s:=private.production_compensation_state(factory,target);
 if s->>'mode'='ACTIVE' and (s->>'available')::numeric>0 then
 select * into j from public.production_orders where factory_id=factory and id=(s->>'demand_item_id')::uuid;
 begin perform private.compensation_capacity(factory,j,(s->>'available')::numeric+(s->>'active_allowance_remaining')::numeric);
 exception when raise_exception then why:=sqlerrm;get stacked diagnostics detail_text=PG_EXCEPTION_DETAIL;if why='output_planning_conflict' then collision:=detail_text::jsonb;end if;end;
 end if;
 return s||jsonb_build_object('measurement',private.measurement_makeup_state(factory,target,s))||jsonb_build_object('distribution',private.quality_production_distribution(factory,target,0),
 'stock_work',(select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'item_id',p.id,'code',p.code,'quantity',p.target_quantity::text,'status',p.status,'planned_start',p.start_time,'request_id',p.request_id)order by d.created_at),'[]'::jsonb) from private.quality_production_decisions d join public.production_orders p on p.factory_id=d.factory_id and p.id=(d.result#>>'{stock,item_id}')::uuid where d.factory_id=factory and d.output_id=target))||jsonb_build_object('decisions',(select coalesce(jsonb_agg(jsonb_build_object('quantity',a.quantity::text,'recorded',case when a.mode='ACTIVE' then (select coalesce(sum(e.quantity),0)::text from private.production_compensation_entries e where e.factory_id=factory and e.compensation_id=a.id) else private.compensation_gross(factory,a.item_id)::text end,
 'remaining',case when a.mode='ACTIVE' then private.compensation_remaining(factory,a.id)::text else greatest(a.quantity-private.compensation_gross(factory,a.item_id),0)::text end,'mode',a.mode,'reason',a.reason,'at',a.created_at) order by a.created_at,a.id),'[]'::jsonb) from private.production_compensation a where a.factory_id=factory and a.output_id=target),'active_block',why,'planned_fallback',false,'active_conflict',collision);
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
 q:=(payload->>'quantity')::numeric;mode:=payload->>'mode';if mode='PLANNED' and s->>'mode'='ACTIVE' then raise exception 'output_active_execution' using errcode='40001';end if;
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
 select greatest((s->>'rejected')::numeric-coalesce(sum(quantity),0),0) into reject_left from private.production_compensation where factory_id=factory and output_id=h.id and id<>request_id and source_kind='RECOVERY';
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
CREATE OR REPLACE FUNCTION public.manufactured_planning_work_read(factory uuid, after_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare all_work jsonb; rows jsonb; total integer; begin
 perform private.require_permission(factory,'factory','view');
 perform private.require_permission(factory,'orders','view');
 if not private.manufactured_output_enabled(factory) then
  return jsonb_build_object('available',false,'work','[]'::jsonb,'total',0,'context_hash','disabled','has_more',false);
 end if;
 select coalesce(jsonb_agg(to_jsonb(z) order by z.item_id),'[]'::jsonb) into all_work from (
  select w.item_id,w.choice,(select coalesce(jsonb_agg(jsonb_build_object('id',op,'name',h.operation_snapshot->op->>'name','name_ar',h.operation_snapshot->op->>'name_ar')order by op),'[]')from private.manufactured_outputs h cross join lateral jsonb_array_elements_text(w.operations)op where h.factory_id=w.factory_id and h.id=w.output_id) required_operations,w.origin_item_id,src.code origin_code,w.demand_item_id,d.code demand_code,
   private.output_work_held(factory,w.item_id) held,private.output_work_retired(factory,w.item_id) retired,
   (select coalesce(jsonb_agg(l.id order by l.id),'[]'::jsonb) from public.production_lines l
    where l.factory_id=factory and not l.archived and private.output_work_line(factory,w.item_id,l.id)) capable_lines
  from private.manufactured_completion_work w
  join public.production_orders o on o.factory_id=w.factory_id and o.id=w.item_id
  join public.production_orders src on src.factory_id=w.factory_id and src.id=w.origin_item_id
  left join public.production_orders d on d.factory_id=w.factory_id and d.id=w.demand_item_id
  where w.factory_id=factory and o.status in ('planned','active')
 ) z;
 total:=jsonb_array_length(all_work);
 select coalesce(jsonb_agg(value order by value->>'item_id'),'[]'::jsonb) into rows from (
  select value from jsonb_array_elements(all_work) where after_id is null or (value->>'item_id')::uuid>after_id
  order by (value->>'item_id')::uuid limit 100
 ) page;
 return jsonb_build_object('available',true,'work',rows,'total',total,'context_hash',md5(all_work::text),
  'has_more',exists(select 1 from jsonb_array_elements(all_work) where jsonb_array_length(rows)>0 and (value->>'item_id')::uuid>(rows->-1->>'item_id')::uuid));
end $function$;
notify pgrst,'reload schema';commit;
