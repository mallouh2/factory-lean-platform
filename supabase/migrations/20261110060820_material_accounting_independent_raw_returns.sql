-- Group 1B: independent physical returns and Warehouse-owned raw accounting.
create sequence private.material_return_number_seq;
create table private.material_returns(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories(id),
 code text not null unique default('MRR-'||lpad(nextval('private.material_return_number_seq')::text,7,'0')),
 material_id uuid not null,unit text not null,source_line_id uuid not null,warehouse_id uuid not null,
 requested numeric not null check(requested>0 and requested::text not in('NaN','Infinity','-Infinity')),
 received numeric not null default 0 check(received>=0 and received<=requested),
 status text not null default 'REQUESTED'check(status in('REQUESTED','PARTIALLY_RECEIVED','RECEIVED','CANCELLED')),
 revision integer not null default 1 check(revision>0),note text not null default ''check(length(note)<=2000),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(factory_id,id),foreign key(factory_id,material_id)references public.materials(factory_id,id),
 foreign key(factory_id,source_line_id)references public.production_lines(factory_id,id),
 foreign key(factory_id,warehouse_id)references public.factory_warehouses(factory_id,id)
);
create table private.material_return_allocations(
 factory_id uuid not null,return_id uuid not null,material_request_id uuid not null,
 quantity numeric not null check(quantity>0 and quantity::text not in('NaN','Infinity','-Infinity')),
 received numeric not null default 0 check(received>=0 and received<=quantity),
 primary key(factory_id,return_id,material_request_id),
 foreign key(factory_id,return_id)references private.material_returns(factory_id,id),
 foreign key(factory_id,material_request_id)references public.material_requests(factory_id,id)
);
create index material_return_origin on private.material_return_allocations(factory_id,material_request_id);
create index material_return_queue on private.material_returns(factory_id,created_at desc,id);
create table private.material_return_events(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null,return_id uuid not null,
 retry_id uuid not null,actor uuid not null references auth.users(id),operation text not null,
 intent jsonb not null,before_state jsonb,after_state jsonb not null,movement_id uuid,
 created_at timestamptz not null default clock_timestamp(),unique(factory_id,retry_id),
 foreign key(factory_id,return_id)references private.material_returns(factory_id,id)
);
alter table private.material_returns enable row level security;
alter table private.material_return_allocations enable row level security;
alter table private.material_return_events enable row level security;
revoke all on private.material_returns,private.material_return_allocations,private.material_return_events from public,anon,authenticated,service_role;
revoke all on sequence private.material_return_number_seq from public,anon,authenticated,service_role;
create function private.material_return_event_immutable()returns trigger language plpgsql set search_path=''as $$begin raise exception 'immutable_material_return_event';end$$;
revoke all on function private.material_return_event_immutable()from public,anon,authenticated,service_role;
create trigger material_return_event_immutable before update or delete on private.material_return_events for each row execute function private.material_return_event_immutable();

-- An absent policy warns on every variance; no arbitrary percentage is assumed.
alter table private.production_material_policy add column deviation_percent numeric not null default 0 check(deviation_percent>=0 and deviation_percent<=1000 and deviation_percent::text not in('NaN','Infinity','-Infinity'));
create function private.material_return_balance(f uuid,r uuid)returns jsonb language sql stable set search_path=''as $$
 select jsonb_build_object('returned',coalesce(sum(a.received),0),'pending',coalesce(sum(case when h.status in('REQUESTED','PARTIALLY_RECEIVED')then a.quantity-a.received else 0 end),0))
 from private.material_return_allocations a join private.material_returns h on h.factory_id=a.factory_id and h.id=a.return_id where a.factory_id=f and a.material_request_id=r
$$;
revoke all on function private.material_return_balance(uuid,uuid)from public,anon,authenticated,service_role;
create function private.material_unused(f uuid,r uuid)returns numeric language sql stable set search_path=''as $$
 select greatest(p.issued-p.consumed-(b->>'returned')::numeric-(b->>'pending')::numeric,0)
 from private.material_request_progress p cross join lateral(select private.material_return_balance(f,r)b)z where p.factory_id=f and p.request_id=r
$$;
revoke all on function private.material_unused(uuid,uuid)from public,anon,authenticated,service_role;
create function private.material_return_snapshot(f uuid,r uuid)returns jsonb language sql stable set search_path=''as $$
 select to_jsonb(h)||jsonb_build_object('name',m.name,'name_ar',m.name_ar,'source_name',l.name,'source_name_ar',l.name_ar,'warehouse_name',w.name,'warehouse_name_ar',w.name_ar,
 'outstanding',trim_scale(case when h.status='CANCELLED'then 0 else h.requested-h.received end)::text,
 'allocations',(select coalesce(jsonb_agg(jsonb_build_object('request',a.material_request_id,'item',o.id,'code',o.code,'issued_at',mr.issued_at,'quantity',trim_scale(a.quantity)::text,'received',trim_scale(a.received)::text)order by o.code,a.material_request_id),'[]')from private.material_return_allocations a join public.material_requests mr on mr.factory_id=a.factory_id and mr.id=a.material_request_id join public.production_orders o on o.factory_id=mr.factory_id and o.id=mr.production_item_id where a.factory_id=f and a.return_id=r))
 from private.material_returns h join public.materials m on m.factory_id=h.factory_id and m.id=h.material_id join public.production_lines l on l.factory_id=h.factory_id and l.id=h.source_line_id join public.factory_warehouses w on w.factory_id=h.factory_id and w.id=h.warehouse_id where h.factory_id=f and h.id=r
$$;
revoke all on function private.material_return_snapshot(uuid,uuid)from public,anon,authenticated,service_role;

create function public.material_return_context(factory uuid)returns jsonb language plpgsql stable security definer set search_path=''as $$declare rows jsonb;warehouses jsonb;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'orders','view');
 select coalesce(jsonb_agg(x order by x->>'name',x->>'line_name'),'[]')into rows from(
 select jsonb_build_object('material',m.id,'name',m.name,'name_ar',m.name_ar,'unit',m.unit,'line',l.id,'line_name',l.name,'line_name_ar',l.name_ar,'available',trim_scale(sum(private.material_unused(factory,r.id)))::text)x
 from public.material_requests r join private.material_request_progress p on p.factory_id=r.factory_id and p.request_id=r.id join public.materials m on m.factory_id=r.factory_id and m.id=r.material_id join public.production_orders o on o.factory_id=r.factory_id and o.id=r.production_item_id join public.production_lines l on l.factory_id=o.factory_id and l.id=o.line_id
 where r.factory_id=factory and m.inventory_kind='RAW_MATERIAL'and m.unit=r.unit and not private.output_work_held(factory,o.id)and private.material_unused(factory,r.id)>0 group by m.id,l.id)t;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'name_ar',name_ar)order by name,id),'[]')into warehouses from public.factory_warehouses where factory_id=factory and storage_class='RAW'and active;
 return jsonb_build_object('rows',rows,'warehouses',warehouses);end$$;
revoke all on function public.material_return_context(uuid)from public,anon,service_role;grant execute on function public.material_return_context(uuid)to authenticated;

create function public.material_return_work(factory uuid,audience text,page integer default 1,request uuid default null)returns jsonb language plpgsql stable security definer set search_path=''as $$declare rows jsonb;n integer;begin
 perform private.require_permission(factory,'factory','view');if audience='WAREHOUSE'then perform private.require_permission(factory,'warehouse','view');elsif audience='PRODUCTION'then perform private.require_permission(factory,'orders','view');else raise exception 'permission_denied'using errcode='42501';end if;
 if page is null or page<1 or page>200 then raise exception 'material_invalid'using errcode='22023';end if;
 select count(*)into n from private.material_returns where factory_id=factory and(request is null or id=request);
 select coalesce(jsonb_agg(private.material_return_snapshot(factory,id)||case when request is not null then jsonb_build_object('events',(select coalesce(jsonb_agg(e),'[]')from(select h.operation,h.created_at,h.intent->'payload'->>'quantity'quantity,coalesce((select display_name from public.memberships where factory_id=factory and user_id=h.actor),'')actor from private.material_return_events h where h.factory_id=factory and h.return_id=t.id order by h.created_at,h.id limit 1000)e))else '{}'::jsonb end order by created_at desc,id),'[]')into rows from(select id,created_at from private.material_returns where factory_id=factory and(request is null or id=request)order by created_at desc,id limit 50 offset(page-1)*50)t;
 return jsonb_build_object('rows',rows,'total',n,'page',page);end$$;
revoke all on function public.material_return_work(uuid,text,integer,uuid)from public,anon,service_role;grant execute on function public.material_return_work(uuid,text,integer,uuid)to authenticated;

create function public.material_return_action(factory uuid,operation text,payload jsonb,request_id uuid)returns jsonb language plpgsql security definer set search_path=''as $$
declare h private.material_returns;old private.material_return_events;intent jsonb:=jsonb_build_object('operation',operation,'payload',payload);before_value jsonb;result jsonb;r record;q numeric;remain numeric;take numeric;v_unit text;mat uuid;line uuid;warehouse uuid;move uuid;begin
 perform private.require_permission(factory,'factory','view');
 if operation='RECEIVE'then perform private.require_permission(factory,'warehouse','issue');perform private.require_permission(factory,'warehouse','view');else perform private.require_permission(factory,'orders','edit');perform private.require_permission(factory,'orders','view');end if;
 if operation is null or operation not in('CREATE','RECEIVE','CANCEL')or request_id is null or payload is null or jsonb_typeof(payload)<>'object'or octet_length(payload::text)>8000 then raise exception 'material_invalid'using errcode='22023';end if;
 if current_setting('transaction_isolation')not in('read committed','read uncommitted')then raise exception 'material_changed'using errcode='40001';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform pg_advisory_xact_lock(hashtextextended(factory::text||':structure',0));
 select *into old from private.material_return_events e where e.factory_id=factory and e.retry_id=material_return_action.request_id;
 if found then if old.actor is distinct from auth.uid()or old.intent<>intent then raise exception 'request_conflict'using errcode='40001';end if;return old.after_state;end if;
 if length(coalesce(payload->>'note',''))>2000 then raise exception 'material_invalid'using errcode='22023';end if;
 if operation in('CREATE','RECEIVE')then if jsonb_typeof(payload->'quantity')is distinct from 'string'or payload->>'quantity'!~'^[0-9]+([.][0-9]+)?$'then raise exception 'material_quantity'using errcode='22023';end if;q:=(payload->>'quantity')::numeric;if q<=0 then raise exception 'material_quantity'using errcode='22023';end if;end if;
 if operation='CREATE'then
 if exists(select 1 from jsonb_object_keys(payload)k where k not in('material','line','warehouse','quantity','note'))then raise exception 'material_invalid'using errcode='22023';end if;
 mat:=(payload->>'material')::uuid;line:=(payload->>'line')::uuid;warehouse:=(payload->>'warehouse')::uuid;
 select m.unit into v_unit from public.materials m where m.factory_id=factory and m.id=mat and m.inventory_kind='RAW_MATERIAL';
 if v_unit is null or not exists(select 1 from public.production_lines where factory_id=factory and id=line)or not exists(select 1 from public.factory_warehouses where factory_id=factory and id=warehouse and storage_class='RAW'and active)then raise exception 'material_return_scope'using errcode='22023';end if;
 insert into private.material_returns(factory_id,material_id,unit,source_line_id,warehouse_id,requested,note,created_by)values(factory,mat,v_unit,line,warehouse,q,coalesce(payload->>'note',''),auth.uid())returning *into h;remain:=q;
 for r in select m.id,private.material_unused(factory,m.id)available from public.material_requests m join private.material_request_progress p on p.factory_id=m.factory_id and p.request_id=m.id join public.production_orders o on o.factory_id=m.factory_id and o.id=m.production_item_id where m.factory_id=factory and m.material_id=mat and m.unit=v_unit and o.line_id=line and not private.output_work_held(factory,o.id)and private.material_unused(factory,m.id)>0 order by m.issued_at,m.id for update of p loop
 take:=least(remain,r.available);if take>0 then insert into private.material_return_allocations values(factory,h.id,r.id,take,0);remain:=remain-take;end if;exit when remain=0;end loop;
 if remain<>0 then raise exception 'material_return_unavailable'using errcode='22023';end if;
 else
 if exists(select 1 from jsonb_object_keys(payload)k where k not in('id','revision','quantity','physical_confirmation','note'))then raise exception 'material_invalid'using errcode='22023';end if;
 select *into h from private.material_returns where factory_id=factory and id=(payload->>'id')::uuid for update;
 if not found then raise exception 'material_invalid'using errcode='22023';end if;
 if h.revision is distinct from(payload->>'revision')::integer then raise exception 'material_changed'using errcode='40001';end if;
 if h.status not in('REQUESTED','PARTIALLY_RECEIVED')then raise exception 'material_return_closed'using errcode='22023';end if;
 before_value:=private.material_return_snapshot(factory,h.id);
 if operation='CANCEL'then
 if h.created_by<>auth.uid()then raise exception 'permission_denied'using errcode='42501';end if;
 if length(btrim(coalesce(payload->>'note','')))<3 then raise exception 'material_return_reason'using errcode='22023';end if;
 update private.material_returns set status='CANCELLED',revision=revision+1 where factory_id=factory and id=h.id;
 else
 if payload->'physical_confirmation'is distinct from 'true'::jsonb or q>h.requested-h.received then raise exception 'material_quantity'using errcode='22023';end if;
 if not exists(select 1 from public.factory_warehouses where factory_id=factory and id=h.warehouse_id and storage_class='RAW'and active)then raise exception 'material_return_scope'using errcode='22023';end if;
 remain:=q;
 for r in select a.*,p.issued,p.consumed,m.production_item_id from private.material_return_allocations a join private.material_request_progress p on p.factory_id=a.factory_id and p.request_id=a.material_request_id join public.material_requests m on m.factory_id=a.factory_id and m.id=a.material_request_id where a.factory_id=factory and a.return_id=h.id order by a.material_request_id for update of a,p loop
 take:=least(remain,r.quantity-r.received);if take>0 then
 if private.output_work_held(factory,r.production_item_id)or r.issued-r.consumed-(private.material_return_balance(factory,r.material_request_id)->>'returned')::numeric<take then raise exception 'material_return_unavailable'using errcode='22023';end if;
 update private.material_return_allocations set received=received+take where factory_id=factory and return_id=h.id and material_request_id=r.material_request_id;remain:=remain-take;end if;exit when remain=0;end loop;
 if remain<>0 then raise exception 'material_return_unavailable'using errcode='22023';end if;
 move:=gen_random_uuid();insert into public.inventory_transactions(id,factory_id,material_id,quantity,kind,unit,reference,note,created_by)values(move,factory,h.material_id,q,'material_return',h.unit,h.id::text,'Independent raw material return '||h.code,auth.uid());
 update private.material_returns set received=received+q,status=case when received+q=requested then 'RECEIVED'else 'PARTIALLY_RECEIVED'end,revision=revision+1 where factory_id=factory and id=h.id;
 end if;end if;
 result:=private.material_return_snapshot(factory,h.id);
 insert into private.material_return_events(factory_id,return_id,retry_id,actor,operation,intent,before_state,after_state,movement_id)values(factory,h.id,request_id,auth.uid(),operation,intent,before_value,result,move);
 return result;end$$;
revoke all on function public.material_return_action(uuid,text,jsonb,uuid)from public,anon,service_role;grant execute on function public.material_return_action(uuid,text,jsonb,uuid)to authenticated;





create or replace function public.material_accounting_policy(factory uuid)returns jsonb language plpgsql stable security definer set search_path=''as $$begin perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'warehouse','view');return jsonb_build_object('deviation_percent',coalesce((select trim_scale(deviation_percent)::text from private.production_material_policy where factory_id=factory),'0'));end$$;
revoke all on function public.material_accounting_policy(uuid)from public,anon,service_role;grant execute on function public.material_accounting_policy(uuid)to authenticated;

-- Existing command/read projections, with the original protected posting contracts.
CREATE OR REPLACE FUNCTION private.material_progress(f uuid, r uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$select to_jsonb(p)||jsonb_build_object('returned',b->>'returned','return_pending',b->>'pending','production_held',trim_scale(greatest(p.issued-p.consumed-(b->>'returned')::numeric,0))::text,'deviation_percent',coalesce((select trim_scale(deviation_percent)::text from private.production_material_policy where factory_id=f),'0'),'revision',m.revision,'quantity',m.quantity::text,'unit',m.unit,'item',m.production_item_id,'name',m.item_name,'status',case when p.awaiting then 'AWAITING_RESERVATION'when p.issued>=m.quantity then 'ISSUED'when p.issued>0 then 'PARTIALLY_ISSUED'when p.reserved>=m.quantity then 'RESERVED'when p.reserved>0 then 'PARTIALLY_RESERVED'else 'REQUESTED'end)from private.material_request_progress p join public.material_requests m on m.factory_id=p.factory_id and m.id=p.request_id cross join lateral(select private.material_return_balance(f,r)b)z where p.factory_id=f and p.request_id=r$function$

;
CREATE OR REPLACE FUNCTION private.material_action_context(f uuid, r uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare m public.material_requests;o public.production_orders;p private.material_request_progress;held numeric;available numeric;reserved numeric;pending numeric;issue numeric;reason text;state text;lead_seconds numeric;returned numeric;return_pending numeric;deviation numeric;due boolean;recheck boolean:=false;begin
 select *into m from public.material_requests where factory_id=f and id=r;
 if not found then raise exception 'material_invalid'using errcode='22023';end if;
 select *into o from public.production_orders where factory_id=f and id=m.production_item_id;
 select *into p from private.material_request_progress where factory_id=f and request_id=r;
 returned:=(private.material_return_balance(f,r)->>'returned')::numeric;return_pending:=(private.material_return_balance(f,r)->>'pending')::numeric;deviation:=coalesce((select deviation_percent from private.production_material_policy where factory_id=f),0);held:=greatest(coalesce(p.issued,0)-coalesce(p.consumed,0)-returned,0);reserved:=coalesce(p.reserved,0);pending:=greatest(m.quantity-coalesce(p.issued,0)+returned-reserved,0);
 if m.material_id is not null then
 select coalesce(sum(quantity),0)into available from public.inventory_transactions where factory_id=f and material_id=m.material_id;
 issue:=least(reserved,available);
 if reserved>0 and not exists(select 1 from public.inventory_reservations z where z.id=p.reservation_id and z.factory_id=f and z.material_id=m.material_id and z.order_id=m.production_item_id and z.released_at is null and z.quantity=reserved)then issue:=0;reason:='material_custody_review';end if;
 available:=greatest(available-(select coalesce(sum(quantity),0)from public.inventory_reservations where factory_id=f and material_id=m.material_id and released_at is null),0);
 else select greatest(coalesce(b.on_hand-b.reserved,0),0)into available from public.finished_goods_balances b where factory_id=f and product_id=m.product_id and unit=m.unit;issue:=reserved;end if;
 available:=coalesce(available,0);
 select coalesce((select seconds from private.production_material_policy where factory_id=f),21600)into lead_seconds;
 due:=o.status='active'or(o.status='planned'and o.start_time is not null and o.start_time<=clock_timestamp()+lead_seconds*interval '1 second');
 state:=coalesce(private.material_progress(f,r)->>'status',m.status);
 if m.status in('CANCELLED','REJECTED')then state:=m.status;reason:='material_request_closed';
 elsif o.status in('completed','cancelled')then state:=case when coalesce(p.issued,0)<m.quantity or held>0 then 'CLOSED_REVIEW'else 'CLOSED'end;reason:=case when state='CLOSED_REVIEW'then 'material_order_reconciliation'else 'material_order_closed'end;
 elsif o.start_time is null or o.line_id is null then reason:='material_plan_required';
 elsif not due then state:='AWAITING_RESERVATION';reason:='material_outside_window';
 elsif exists(select 1 from private.material_preparation_jobs where factory_id=f and item_id=o.id and warning is not null)and m.automatic_requirement_key is not null then reason:=(select warning from private.material_preparation_jobs where factory_id=f and item_id=o.id);
 elsif coalesce(p.awaiting,false)then state:='REQUESTED';reason:='material_recheck_required';recheck:=true;
 end if;
 if private.output_work_held(f,o.id)then reason:='output_quality_hold';recheck:=false;end if;
 return jsonb_build_object('state',state,'reason',reason,'order_status',o.status,'production_held',trim_scale(held)::text,'returned',trim_scale(returned)::text,'return_pending',trim_scale(return_pending)::text,'deviation_percent',trim_scale(deviation)::text,'outstanding',trim_scale(greatest(m.quantity-coalesce(p.issued,0)+returned,0))::text,'suggested',jsonb_build_object('RESERVE',trim_scale(case when reason is null then least(pending,available)else 0 end)::text,'ISSUE',trim_scale(case when reason is null then least(greatest(issue,0),greatest(m.quantity-coalesce(p.issued,0)+returned,0))else 0 end)::text),'can_recheck',recheck,
 'eligible',jsonb_build_object('RESERVE',trim_scale(case when reason is null then case when m.material_id is not null then available else least(pending,available)end else 0 end)::text,'ISSUE',trim_scale(case when reason is null then greatest(issue,0)else 0 end)::text,'RELEASE',trim_scale(reserved)::text,'RETURN',trim_scale(case when m.material_id is null then held else 0 end)::text,'CONSUME',trim_scale(case when o.status='active'then greatest(held-return_pending,0)else 0 end)::text,'RECONCILE',trim_scale(greatest(coalesce(p.issued,0)-returned-return_pending,0))::text));
end$function$

;
CREATE OR REPLACE FUNCTION private.material_start_readiness(f uuid, i uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare o public.production_orders;req jsonb;x jsonb;rows jsonb:='[]';held numeric;missing numeric;ready boolean:=true;reason text;name text;name_ar text;begin
 select *into o from public.production_orders where factory_id=f and id=i;if not found then raise exception 'not_found'using errcode='P0002';end if;
 req:=private.material_requirement_inputs(f,i);reason:=req->>'warning';
 -- Existing completion/rework source-lot safeguards own these inputs; do not explode raw recipe twice.
 if req->>'existing_source_work'='true'then return jsonb_build_object('ready',true,'reason',null,'scope','EXISTING_SOURCE_WORK','rows',rows);end if;
 if reason is not null then return jsonb_build_object('ready',false,'reason',reason,'rows',rows);end if;
 if exists(select 1 from public.material_requests m join private.material_request_progress p on p.factory_id=m.factory_id and p.request_id=m.id where m.factory_id=f and m.production_item_id=i and m.automatic_requirement_key is not null and m.status not in('CANCELLED','REJECTED')and p.requirement is distinct from req)then return jsonb_build_object('ready',false,'reason','material_requirement_review','rows',rows);end if;
 for x in select value from jsonb_array_elements(req->'inputs')loop
 select coalesce(sum(greatest(p.issued-p.consumed-(private.material_return_balance(f,m.id)->>'returned')::numeric-(private.material_return_balance(f,m.id)->>'pending')::numeric,0)),0)into held from public.material_requests m join private.material_request_progress p on p.factory_id=m.factory_id and p.request_id=m.id where m.factory_id=f and m.production_item_id=i and m.status not in('CANCELLED','REJECTED')and m.unit=x->>'unit'and(case when x->>'kind'='material'then m.material_id=(x->>'id')::uuid else m.product_id=(x->>'id')::uuid end);
 missing:=greatest((x->>'quantity')::numeric-held,0);ready:=ready and missing=0;
 if x->>'kind'='material'then select m.name,m.name_ar into name,name_ar from public.materials m where m.factory_id=f and m.id=(x->>'id')::uuid;else select p.name,p.name_ar into name,name_ar from public.products p where p.factory_id=f and p.id=(x->>'id')::uuid;end if;
 rows:=rows||jsonb_build_array(jsonb_build_object('id',x->>'id','kind',x->>'kind','name',name,'name_ar',name_ar,'required',x->>'quantity','production_held',trim_scale(held)::text,'missing',trim_scale(missing)::text,'unit',x->>'unit'));
 end loop;
 return jsonb_build_object('ready',ready,'reason',case when not ready then 'material_handover_required'end,'required_output',o.target_quantity::text,'unit',o.unit,'recipe',req->'recipe','recipe_version',req->'recipe_version','rows',rows);
end$function$

;
CREATE OR REPLACE FUNCTION public.production_material_action(factory uuid, operation text, payload jsonb, request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare m public.material_requests;p private.material_request_progress;prior private.material_preparation_events;intent jsonb:=jsonb_build_object('operation',operation,'payload',payload);previous jsonb;q numeric;context jsonb;available numeric;result jsonb;move uuid;pick jsonb;total numeric;source public.finished_goods_sources;qty numeric;entry uuid;begin
 perform private.require_permission(factory,'factory','view');
 if operation in('CONSUME','RECONCILE')then perform private.require_permission(factory,'warehouse','edit');perform private.require_permission(factory,'warehouse','view');else perform private.require_permission(factory,'warehouse','issue');end if;
 if operation is null or request_id is null or payload is null or jsonb_typeof(payload)<>'object'or octet_length(payload::text)>16000 or operation not in('RESERVE','ISSUE','CONSUME','RETURN','RELEASE','RECHECK','RECONCILE')or exists(select 1 from jsonb_object_keys(payload)k where k not in('id','revision','quantity','allocations','entry','physical_confirmation','reason'))then raise exception 'material_invalid'using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform pg_advisory_xact_lock(hashtextextended(factory::text||':structure',0));
 select *into prior from private.material_preparation_events where factory_id=factory and retry_id=production_material_action.request_id;
 if found then if prior.actor is distinct from auth.uid()or prior.intent<>intent then raise exception 'request_conflict'using errcode='40001';end if;return prior.after_state;end if;
 select *into m from public.material_requests where factory_id=factory and id=(payload->>'id')::uuid for update;
 if m.id is null or m.production_item_id is null or m.lot_id is not null or m.status in('CANCELLED','REJECTED')then raise exception 'material_invalid'using errcode='22023';end if;
 if m.revision is distinct from(payload->>'revision')::int then raise exception 'material_changed'using errcode='40001';end if;
 select *into p from private.material_request_progress where factory_id=factory and material_request_progress.request_id=m.id for update;
 if not found then if m.status<>'REQUESTED'then raise exception 'material_custody_review'using errcode='22023';end if;insert into private.material_request_progress(factory_id,request_id,requirement)values(factory,m.id,jsonb_build_object('manual',true));select *into p from private.material_request_progress where factory_id=factory and material_request_progress.request_id=m.id;end if;
 if operation='RETURN'and m.material_id is not null then raise exception 'material_use_return_request'using errcode='22023';end if;
 if private.output_work_held(factory,m.production_item_id)then raise exception 'output_quality_hold'using errcode='22023';end if;
 if operation='RECHECK'then
 previous:=private.material_progress(factory,m.id);context:=private.material_action_context(factory,m.id);
 if not coalesce((context->>'can_recheck')::boolean,false)then raise exception 'material_preparation_unavailable'using errcode='22023';end if;
 perform private.reconcile_material_item(factory,m.production_item_id);context:=private.material_action_context(factory,m.id);
 if context->>'reason'is not null then raise exception 'material_preparation_unavailable'using errcode='22023';end if;
 return private.material_event(factory,m.id,m.production_item_id,request_id,operation,intent,previous);end if;
 if operation in('RESERVE','ISSUE')then perform private.reconcile_material_item(factory,m.production_item_id);select *into m from public.material_requests where factory_id=factory and id=m.id;select *into p from private.material_request_progress where factory_id=factory and material_request_progress.request_id=m.id;if m.revision is distinct from(payload->>'revision')::int then raise exception 'material_changed'using errcode='40001';end if;end if;
 if operation in('RESERVE','ISSUE')and(p.awaiting or(m.automatic_requirement_key is not null and exists(select 1 from private.material_preparation_jobs where factory_id=factory and item_id=m.production_item_id and warning is not null)))then raise exception 'material_preparation_unavailable'using errcode='22023';end if;
 if jsonb_typeof(payload->'quantity')is distinct from 'string'or payload->>'quantity'!~'^[0-9]+([.][0-9]+)?$'then raise exception 'material_invalid'using errcode='22023';end if;q:=(payload->>'quantity')::numeric;
 if q<0 or(q=0 and operation<>'RECONCILE')or q::text in('NaN','Infinity','-Infinity')then raise exception 'material_invalid'using errcode='22023';end if;
 context:=private.material_action_context(factory,m.id);
 if operation in('RESERVE','ISSUE')and context->>'reason'is not null then raise exception 'material_preparation_unavailable'using errcode='22023';end if;
 if q>coalesce((context->'eligible'->>operation)::numeric,0)then raise exception 'material_quantity'using errcode='22023';end if;
 if operation in('CONSUME','RECONCILE')and length(btrim(coalesce(payload->>'reason','')))<3 then raise exception 'material_reconciliation_reason'using errcode='22023';end if;
 if operation in('RESERVE','ISSUE')and m.material_id is not null and q>greatest(m.quantity-p.issued+(context->>'returned')::numeric-case when operation='RESERVE'then p.reserved else 0 end,0)*(1+(context->>'deviation_percent')::numeric/100)and length(btrim(coalesce(payload->>'reason','')))<3 then raise exception 'material_deviation_reason'using errcode='22023';end if;
 previous:=private.material_progress(factory,m.id);
 if m.product_id is not null then
 if jsonb_typeof(payload->'allocations')is distinct from 'array'or jsonb_array_length(payload->'allocations')>100 or jsonb_array_length(payload->'allocations')=0 then raise exception 'source_identity'using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(payload->'allocations')x where jsonb_typeof(x)<>'object'or exists(select 1 from jsonb_object_keys(x)k where k not in('source_id','quantity'))or x->>'source_id'is null or jsonb_typeof(x->'quantity')<>'string'or x->>'quantity'!~'^[0-9]+([.][0-9]+)?$'or(x->>'quantity')::numeric<=0)or(select count(distinct x->>'source_id')<>count(*)from jsonb_array_elements(payload->'allocations')x)then raise exception 'source_identity'using errcode='22023';end if;
 select sum((x->>'quantity')::numeric)into total from jsonb_array_elements(payload->'allocations')x;if total<>q then raise exception 'source_quantity'using errcode='22023';end if;
 end if;
 if m.product_id is not null and operation<>'RETURN'and exists(select 1 from jsonb_array_elements(payload->'allocations')a join public.finished_goods_sources s on s.factory_id=factory and s.id=(a->>'source_id')::uuid join private.manufactured_outputs o on o.factory_id=factory and o.entry_id=s.entry_id join private.output_hold_rows(factory)h on h.output_id=o.id and h.finished)then raise exception 'output_quality_hold'using errcode='22023';end if;
 if operation='RESERVE'then
 if m.material_id is null and q>m.quantity-p.issued-p.reserved then raise exception 'material_quantity'using errcode='22023';end if;
 if m.material_id is not null then
 select coalesce(sum(quantity),0)-(select coalesce(sum(quantity),0)from public.inventory_reservations where factory_id=factory and material_id=m.material_id and released_at is null)into available from public.inventory_transactions where factory_id=factory and material_id=m.material_id;
 if available<q then raise exception 'material_shortage'using errcode='22023';end if;
 if p.reservation_id is null then insert into public.inventory_reservations(factory_id,material_id,order_id,quantity)values(factory,m.material_id,m.production_item_id,q)returning id into p.reservation_id;else update public.inventory_reservations set quantity=quantity+q where id=p.reservation_id and released_at is null;if not found then raise exception 'material_changed'using errcode='40001';end if;end if;
 else
 select on_hand-reserved into available from public.finished_goods_balances where factory_id=factory and product_id=m.product_id and unit=m.unit for update;if coalesce(available,0)<q then raise exception 'material_shortage'using errcode='22023';end if;
 for pick in select value from jsonb_array_elements(payload->'allocations')loop select *into source from public.finished_goods_sources where factory_id=factory and id=(pick->>'source_id')::uuid for update;qty:=(pick->>'quantity')::numeric;
 if source.id is null or source.product_id<>m.product_id or source.unit<>m.unit or source.physical_label is null or source.quantity_available-private.source_reserved(factory,source.id)<qty then raise exception 'source_unavailable'using errcode='22023';end if;
 insert into private.material_source_reservations values(factory,m.id,source.id,qty)on conflict on constraint material_source_reservations_pkey do update set quantity=material_source_reservations.quantity+excluded.quantity;
 end loop;update public.finished_goods_balances set reserved=reserved+q where factory_id=factory and product_id=m.product_id and unit=m.unit;
 end if;
 update private.material_request_progress set reserved=reserved+q,reservation_id=p.reservation_id where factory_id=factory and material_request_progress.request_id=m.id;
 elsif operation='ISSUE'then
 if payload->'physical_confirmation'is distinct from 'true'::jsonb or q>p.reserved then raise exception 'material_quantity'using errcode='22023';end if;move:=gen_random_uuid();
 if m.material_id is not null then
 if p.reservation_id is null then raise exception 'material_changed'using errcode='40001';end if;
 if q=p.reserved then update public.inventory_reservations set released_at=clock_timestamp()where id=p.reservation_id and released_at is null;p.reservation_id:=null;else update public.inventory_reservations set quantity=quantity-q where id=p.reservation_id and released_at is null;end if;
 insert into public.inventory_transactions(id,factory_id,material_id,quantity,kind,unit,reference,note,created_by)values(move,factory,m.material_id,-q,'material_issue',m.unit,m.id::text,'Measured physical material handover',auth.uid());
 else
 for pick in select value from jsonb_array_elements(payload->'allocations')loop qty:=(pick->>'quantity')::numeric;update private.material_source_reservations set quantity=quantity-qty where factory_id=factory and material_source_reservations.request_id=m.id and source_id=(pick->>'source_id')::uuid and quantity>qty;
 if not found then delete from private.material_source_reservations where factory_id=factory and material_source_reservations.request_id=m.id and source_id=(pick->>'source_id')::uuid and quantity=qty;if not found then raise exception 'source_unavailable'using errcode='22023';end if;end if;
 insert into private.material_source_custody values(factory,m.id,(pick->>'source_id')::uuid,qty,0)on conflict on constraint material_source_custody_pkey do update set quantity=material_source_custody.quantity+excluded.quantity;
 end loop;
 perform private.source_begin_pick(factory,'material_issue',m.product_id,m.unit,null,payload->'allocations');update public.finished_goods_balances set reserved=reserved-q,on_hand=on_hand-q where factory_id=factory and product_id=m.product_id and unit=m.unit;
 insert into public.finished_goods_movements(id,factory_id,product_id,unit,kind,stock_delta,reason,external_reference,created_by)values(move,factory,m.product_id,m.unit,'material_issue',-q,'Measured physical material handover',m.id::text,auth.uid());perform private.source_end_pick();
 end if;
 update private.material_request_progress set reserved=reserved-q,issued=issued+q,reservation_id=p.reservation_id,last_movement=move where factory_id=factory and material_request_progress.request_id=m.id;
 update public.material_requests set status='ISSUED',issued_by=auth.uid(),issued_at=clock_timestamp(),movement_id=move where id=m.id;
 elsif operation='RELEASE'then
 if length(btrim(coalesce(payload->>'reason','')))<3 or q>p.reserved then raise exception 'material_quantity'using errcode='22023';end if;
 if m.material_id is not null then
 if q=p.reserved then update public.inventory_reservations set released_at=clock_timestamp()where id=p.reservation_id and released_at is null;p.reservation_id:=null;else update public.inventory_reservations set quantity=quantity-q where id=p.reservation_id and released_at is null;end if;if not found then raise exception 'material_changed'using errcode='40001';end if;
 else
 for pick in select value from jsonb_array_elements(payload->'allocations')loop qty:=(pick->>'quantity')::numeric;update private.material_source_reservations set quantity=quantity-qty where factory_id=factory and material_source_reservations.request_id=m.id and source_id=(pick->>'source_id')::uuid and quantity>qty;
 if not found then delete from private.material_source_reservations where factory_id=factory and material_source_reservations.request_id=m.id and source_id=(pick->>'source_id')::uuid and quantity=qty;if not found then raise exception 'source_unavailable'using errcode='22023';end if;end if;end loop;update public.finished_goods_balances set reserved=reserved-q where factory_id=factory and product_id=m.product_id and unit=m.unit;
 end if;update private.material_request_progress set reserved=reserved-q,reservation_id=p.reservation_id where factory_id=factory and material_request_progress.request_id=m.id;
 elsif operation='RECONCILE'then
 if m.material_id is null then raise exception 'material_invalid'using errcode='22023';end if;
 update private.material_request_progress set consumed=q where factory_id=factory and material_request_progress.request_id=m.id;
 elsif operation='CONSUME'then
 entry:=(payload->>'entry')::uuid;if q>p.issued-p.consumed or not exists(select 1 from public.production_orders where factory_id=factory and id=m.production_item_id and status='active'and actual_start is not null)or(entry is not null and not exists(select 1 from public.production_entries where factory_id=factory and id=entry and order_id=m.production_item_id and created_at>=m.issued_at))then raise exception 'material_quantity'using errcode='22023';end if;
 if m.product_id is not null then for pick in select value from jsonb_array_elements(payload->'allocations')loop qty:=(pick->>'quantity')::numeric;update private.material_source_custody set consumed=consumed+qty where factory_id=factory and material_source_custody.request_id=m.id and source_id=(pick->>'source_id')::uuid and quantity-consumed>=qty;if not found then raise exception 'source_unavailable'using errcode='22023';end if;end loop;end if;
 update private.material_request_progress set consumed=consumed+q where factory_id=factory and material_request_progress.request_id=m.id;
 elsif operation='RETURN'then
 if payload->'physical_confirmation'is distinct from 'true'::jsonb or length(btrim(coalesce(payload->>'reason','')))<3 or q>p.issued-p.consumed then raise exception 'material_quantity'using errcode='22023';end if;move:=gen_random_uuid();
 if m.material_id is not null then insert into public.inventory_transactions(id,factory_id,material_id,quantity,kind,unit,reference,note,created_by)values(move,factory,m.material_id,q,'material_return',m.unit,m.id::text,payload->>'reason',auth.uid());
 else
 for pick in select value from jsonb_array_elements(payload->'allocations')loop qty:=(pick->>'quantity')::numeric;update private.material_source_custody set quantity=quantity-qty where factory_id=factory and material_source_custody.request_id=m.id and source_id=(pick->>'source_id')::uuid and quantity-consumed>=qty;if not found then raise exception 'source_unavailable'using errcode='22023';end if;update public.finished_goods_sources set quantity_available=quantity_available+qty where factory_id=factory and id=(pick->>'source_id')::uuid;end loop;
 perform private.source_begin_pick(factory,'material_return',m.product_id,m.unit,null,payload->'allocations');update public.finished_goods_balances set on_hand=on_hand+q where factory_id=factory and product_id=m.product_id and unit=m.unit;
 insert into public.finished_goods_movements(id,factory_id,product_id,unit,kind,stock_delta,reason,external_reference,created_by)values(move,factory,m.product_id,m.unit,'material_return',q,payload->>'reason',m.id::text,auth.uid());perform private.source_end_pick();
 end if;
 update private.material_request_progress set issued=issued-q,last_movement=move where factory_id=factory and material_request_progress.request_id=m.id;update public.material_requests set status=case when p.issued-q>0 then 'ISSUED'else 'REQUESTED'end where id=m.id;
 end if;
 update public.material_requests set revision=revision+1 where id=m.id;result:=private.material_event(factory,m.id,m.production_item_id,request_id,operation,intent,previous,entry);
 return result;
end$function$

;
CREATE OR REPLACE FUNCTION public.production_material_work(factory uuid, audience text, item uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$declare rows jsonb;warnings jsonb;begin
 perform private.material_audience(factory,audience);if item is not null and not exists(select 1 from public.production_orders where factory_id=factory and id=item)then raise exception 'material_invalid'using errcode='22023';end if;
 select coalesce(jsonb_agg((jsonb_build_object('id',m.id,'item',m.production_item_id,'code',o.code,'name',m.item_name,'quantity',trim_scale(m.quantity)::text,'unit',m.unit,'material',m.material_id,'product',m.product_id,'revision',m.revision,'managed',p.request_id is not null,'automatic',m.automatic_requirement_key is not null,'reserved',trim_scale(coalesce(p.reserved,0))::text,'returned',private.material_return_balance(factory,m.id)->>'returned','return_pending',private.material_return_balance(factory,m.id)->>'pending','issued',trim_scale(coalesce(p.issued,case when m.status in('ISSUED','RECEIVED')then m.quantity else 0 end))::text,'consumed',trim_scale(coalesce(p.consumed,0))::text,'awaiting',coalesce(p.awaiting,false),'state',coalesce(private.material_progress(factory,m.id)->>'status',m.status),'available',case when m.material_id is not null then trim_scale((select coalesce(sum(t.quantity),0)from public.inventory_transactions t where t.factory_id=factory and t.material_id=m.material_id)-(select coalesce(sum(r.quantity),0)from public.inventory_reservations r where r.factory_id=factory and r.material_id=m.material_id and r.released_at is null))::text else(select trim_scale(b.on_hand-b.reserved)::text from public.finished_goods_balances b where b.factory_id=factory and b.product_id=m.product_id and b.unit=m.unit)end,'reservations',(select coalesce(jsonb_agg(jsonb_build_object('source_id',r.source_id,'label',z.physical_label,'quantity',trim_scale(r.quantity)::text)order by r.source_id),'[]')from private.material_source_reservations r join public.finished_goods_sources z on z.factory_id=r.factory_id and z.id=r.source_id where r.factory_id=factory and r.request_id=m.id),'custody',(select coalesce(jsonb_agg(jsonb_build_object('source_id',r.source_id,'label',z.physical_label,'quantity',trim_scale(r.quantity-r.consumed)::text)order by r.source_id),'[]')from private.material_source_custody r join public.finished_goods_sources z on z.factory_id=r.factory_id and z.id=r.source_id where r.factory_id=factory and r.request_id=m.id)) || private.material_action_context(factory,m.id)) order by o.code,m.id),'[]')into rows from public.material_requests m join public.production_orders o on o.factory_id=m.factory_id and o.id=m.production_item_id left join private.material_request_progress p on p.factory_id=m.factory_id and p.request_id=m.id where m.factory_id=factory and m.lot_id is null and m.status not in('CANCELLED','REJECTED')and(item is null or m.production_item_id=item);
 select coalesce(jsonb_agg(jsonb_build_object('item',j.item_id,'code',o.code,'product',p.name,'warning',j.warning)order by o.code),'[]')into warnings from private.material_preparation_jobs j join public.production_orders o on o.factory_id=j.factory_id and o.id=j.item_id join public.products p on p.factory_id=o.factory_id and p.id=o.product_id where j.factory_id=factory and j.warning is not null and(item is null or j.item_id=item)and o.status='planned';return jsonb_build_object('rows',rows,'warnings',warnings);end$function$

;
CREATE OR REPLACE FUNCTION public.configure_production_materials(factory uuid, operation text, payload jsonb, request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare prior private.production_material_config_events;intent jsonb;before_value jsonb;result jsonb;p public.products;step uuid;v_scope uuid;seconds numeric;begin
 if operation='DEVIATION'then perform private.require_permission(factory,'warehouse','edit');else perform private.require_permission(factory,'orders','edit');end if;
 if request_id is null or payload is null or jsonb_typeof(payload)<>'object'or octet_length(payload::text)>4000 then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform pg_advisory_xact_lock(hashtextextended(factory::text||':structure',0));if operation='DEVIATION'then perform private.require_permission(factory,'warehouse','edit');else perform private.require_permission(factory,'orders','edit');end if;intent:=jsonb_build_object('operation',operation,'payload',payload);
 select *into prior from private.production_material_config_events e where e.factory_id=factory and e.request_id=configure_production_materials.request_id;
 if found then if prior.actor<>auth.uid()or prior.intent<>intent then raise exception 'request_conflict'using errcode='40001';end if;return prior.after_value;end if;
 if operation='DEVIATION'then
 if(select count(*)from jsonb_object_keys(payload))<>1 or jsonb_typeof(payload->'percent')is distinct from 'string'or payload->>'percent'!~'^[0-9]+([.][0-9]+)?$'or(payload->>'percent')::numeric>1000 then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 select to_jsonb(v)into before_value from private.production_material_policy v where factory_id=factory;
 insert into private.production_material_policy(factory_id,seconds,deviation_percent)values(factory,21600,(payload->>'percent')::numeric)on conflict(factory_id)do update set deviation_percent=excluded.deviation_percent,revision=production_material_policy.revision+1;result:=jsonb_build_object('deviation_percent',payload->>'percent');
 elsif operation='WINDOW'then
 if(select count(*)from jsonb_object_keys(payload))<>1 or not(payload?'hours')or jsonb_typeof(payload->'hours')<>'string'or payload->>'hours'!~'^[0-9]{1,5}([.][0-9]{1,6})?$'then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 seconds:=(payload->>'hours')::numeric*3600;if seconds<=0 or seconds>31536000 then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 select to_jsonb(v)into before_value from private.production_material_policy v where factory_id=factory;
 insert into private.production_material_policy values(factory,seconds,1)on conflict(factory_id)do update set seconds=excluded.seconds,revision=production_material_policy.revision+1;
 result:=jsonb_build_object('hours',trim_scale(seconds/3600)::text,'seconds',trim_scale(seconds)::text);
 elsif operation='ROUTE'then
 if exists(select 1 from jsonb_object_keys(payload)k where k not in('product','routing_step','mode'))or not(payload?&array['product','mode'])or payload->>'mode'not in('COMPOUND_STOCK','DIRECT_RAW','COMPOUND_MANUFACTURE')or payload->>'mode'is null then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 select *into p from public.products where factory_id=factory and id=(payload->>'product')::uuid;if not found then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 step:=(payload->>'routing_step')::uuid;v_scope:=coalesce(step,'00000000-0000-0000-0000-000000000000'::uuid);
 if step is not null and not exists(select 1 from public.production_routing_steps where id=step and factory_id=factory and product_id=p.id)then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 if payload->>'mode'='COMPOUND_MANUFACTURE'and(p.product_kind<>'MANUFACTURED_INTERMEDIATE'or p.stock_unit<>'kg')or payload->>'mode'in('COMPOUND_STOCK','DIRECT_RAW')and(p.formula_product_id is null or p.unit_weight_kg is null or p.unit_weight_kg<=0)then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 if payload->>'mode'in('DIRECT_RAW','COMPOUND_MANUFACTURE')and not exists(select 1 from public.bom_versions where factory_id=factory and product_id=case when payload->>'mode'='COMPOUND_MANUFACTURE'then p.id else p.formula_product_id end and output_unit='kg')then raise exception 'material_recipe_missing'using errcode='22023';end if;
 select to_jsonb(r)into before_value from private.production_input_routes r where r.factory_id=factory and r.product_id=p.id and r.scope=v_scope;
 insert into private.production_input_routes values(factory,p.id,v_scope,step,payload->>'mode',1,auth.uid(),clock_timestamp())on conflict(factory_id,product_id,scope)do update set mode=excluded.mode,revision=production_input_routes.revision+1,updated_by=auth.uid(),updated_at=clock_timestamp();
 select to_jsonb(r)into result from private.production_input_routes r where r.factory_id=factory and r.product_id=p.id and r.scope=v_scope;
 else raise exception 'material_configuration_invalid'using errcode='22023';end if;
 insert into private.production_material_config_events values(factory,request_id,auth.uid(),operation,intent,before_value,result,clock_timestamp());return result;
end$function$

;
CREATE OR REPLACE FUNCTION private.apply_supply_command(factory uuid, action text, payload jsonb, request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result uuid;old uuid;r public.purchase_requisitions;m public.material_requests;v jsonb;row_data jsonb;
 target uuid;mat uuid;prod uuid;lot uuid;u text;label text;q numeric;actor_name text;next_status text;reason text;category uuid;supplier uuid;item record;begin
 perform private.require_permission(factory,'factory','view');
 if jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>30000 then raise exception 'supply_invalid';end if;
 -- Authorization precedes retry reads as well as all writes.
 if action in ('purchase_stock','receive_purchase','receive_wip','acknowledge_good') then perform private.require_permission(factory,'warehouse','edit');
 elsif action='purchase_manual' then perform private.require_permission(factory,'purchasing','create');
 elsif action='purchase_change' then
  if payload->>'action' not in ('clarify','receive_direct','cancel_own') then perform private.require_permission(factory,'purchasing','edit');end if;
 elsif action='supplier_save' then perform private.require_permission(factory,'suppliers','edit');
 elsif action='material_request' then perform private.require_permission(factory,'orders','edit');
 elsif action='material_change' then
  if payload->>'action' in ('issue','reject','cancel') then perform private.require_permission(factory,'warehouse','issue');end if;
 else raise exception 'supply_invalid';end if;
 if action='acknowledge_good' and exists(select 1 from private.manufactured_outputs where factory_id=factory and entry_id=(payload->>'entry')::uuid) then raise exception 'output_quantity_receipt_required';end if;
 if action='receive_wip' and exists(select 1 from private.manufactured_output_lots where factory_id=factory and lot_id=(payload->>'lot')::uuid) then raise exception 'output_quantity_receipt_required';end if;
 old:=private.fulfillment_retry(factory,request_id,'supply_'||action,payload);if old is not null then return old;end if;
 actor_name:=coalesce((select display_name from public.memberships where factory_id=factory and user_id=auth.uid() and status='approved'),'');
 if action in ('purchase_stock','purchase_manual') then
  q:=(payload->>'quantity')::numeric;u:=btrim(payload->>'unit');
  if q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity') then raise exception 'supply_invalid';end if;
  if action='purchase_stock' then
   target:=(payload->>'item')::uuid;
   select value into row_data from private.warehouse_inventory_rows(factory) value where value->>'id'=target::text and value->>'unit'=u;
   if row_data is null or row_data->>'supply_source' not in ('EXTERNAL','BOTH') then raise exception 'supply_invalid';end if;
   mat:=case when row_data->>'entity'='material' then target end;prod:=case when row_data->>'entity'='finished' then target end;
   select * into r from public.purchase_requisitions pr where pr.factory_id=factory and pr.unit=u and (pr.material_id=mat or pr.product_id=prod) and pr.status not in ('RECEIVED','REJECTED','CANCELLED');
   if found then result:=r.id;
   else
    if row_data->>'minimum_status'<>'AT_OR_BELOW_MIN' or (payload->>'projected')::numeric is distinct from (row_data->>'projected')::numeric
      or (row_data->>'already_requested')::boolean then raise exception 'warehouse_stock_changed';end if;
    insert into public.purchase_requisitions(factory_id,material_id,product_id,item_name,quantity,unit,details,notes,source_context,requested_by,requested_by_name,stock_context)
    values(factory,mat,prod,row_data->>'name',q,u,'Stock replenishment',coalesce(payload->>'notes',''),'Warehouse',auth.uid(),actor_name,row_data) returning id into result;
    perform private.supply_event(factory,result,'');
   end if;
  else
   if coalesce(length(btrim(payload->>'item_name')),0) not between 1 and 200 or coalesce(length(btrim(payload->>'details')),0) not between 1 and 4000
     or coalesce(length(u),0) not between 1 and 50 or coalesce(length(btrim(payload->>'source_context')),0) not between 1 and 120 then raise exception 'supply_invalid';end if;
   insert into public.purchase_requisitions(factory_id,item_name,quantity,unit,details,notes,source_context,requested_by,requested_by_name)
   values(factory,btrim(payload->>'item_name'),q,u,btrim(payload->>'details'),coalesce(payload->>'notes',''),btrim(payload->>'source_context'),auth.uid(),actor_name) returning id into result;
   perform private.supply_event(factory,result,'');
  end if;
 elsif action in ('purchase_change','receive_purchase') then
  select * into r from public.purchase_requisitions pr where pr.factory_id=factory and pr.id=(payload->>'id')::uuid for update;
  if not found then raise exception 'supply_invalid';end if;
  if r.revision is distinct from (payload->>'revision')::integer then raise exception 'supply_conflict';end if;
  if r.status in ('RECEIVED','REJECTED','CANCELLED') then raise exception 'supply_state';end if;
  result:=r.id;reason:=btrim(coalesce(payload->>'reason',''));next_status:=payload->>'action';
  if action='receive_purchase' then
   if r.status<>'READY_FOR_RECEIPT' or num_nonnulls(r.material_id,r.product_id)<>1 then raise exception 'supply_state';end if;
   -- The existing External Receipt command remains the only inventory receiving path.
   target:=public.receive_warehouse_stock(factory,coalesce(r.material_id,r.product_id),case when r.material_id is not null then 'material' else 'finished' end,r.unit,r.quantity,'external_receipt',r.code,reason,gen_random_uuid());
   update public.purchase_requisitions set receipt_movement_id=target,received_by=auth.uid(),received_at=clock_timestamp() where id=r.id;
   next_status:='RECEIVED';
  elsif next_status='receive_direct' then
   if r.requested_by<>auth.uid() or r.status<>'READY_FOR_RECEIPT' or num_nonnulls(r.material_id,r.product_id)<>0 then raise exception 'supply_state';end if;
   update public.purchase_requisitions set received_by=auth.uid(),received_at=clock_timestamp() where id=r.id;next_status:='RECEIVED';
  elsif next_status='clarify' then
   if r.requested_by<>auth.uid() or r.status<>'NEEDS_CLARIFICATION' or length(reason) not between 1 and 4000 then raise exception 'supply_reason';end if;
   next_status:='REQUESTED';
  elsif next_status='cancel_own' then
   if r.requested_by<>auth.uid() or r.status not in ('REQUESTED','UNDER_REVIEW','NEEDS_CLARIFICATION') then raise exception 'supply_state';end if;
   if length(reason) not between 1 and 4000 then raise exception 'supply_reason';end if;next_status:='CANCELLED';
  elsif next_status='supplier' then
   if r.status not in ('REQUESTED','UNDER_REVIEW','NEEDS_CLARIFICATION') then raise exception 'supply_state';end if;
   supplier:=nullif(payload->>'supplier_id','')::uuid;label:=btrim(coalesce(payload->>'supplier_text',''));
   if supplier is not null and label<>'' then raise exception 'supply_invalid';end if;
   if supplier is null then
    if length(label) not between 1 and 200 then raise exception 'supply_invalid';end if;
    select id into supplier from public.suppliers where factory_id=factory and lower(btrim(name))=lower(label);
   end if;
   if supplier is not null then
    if not exists(select 1 from public.suppliers where factory_id=factory and id=supplier and active) then raise exception 'supply_invalid';end if;
    label:='';
   end if;
   update public.purchase_requisitions set supplier_id=supplier,supplier_text=label where id=r.id;next_status:=r.status;
  else
   if next_status in ('NEEDS_CLARIFICATION','REJECTED','CANCELLED') and length(reason) not between 1 and 4000 then raise exception 'supply_reason';end if;
   if not ((next_status='UNDER_REVIEW' and r.status='REQUESTED') or (next_status='ORDERED' and r.status='UNDER_REVIEW' and (r.supplier_id is not null or r.supplier_text<>''))
    or (next_status='READY_FOR_RECEIPT' and r.status='ORDERED') or (next_status in ('NEEDS_CLARIFICATION','REJECTED') and r.status in ('REQUESTED','UNDER_REVIEW'))
    or next_status='CANCELLED') then raise exception 'supply_state';end if;
  end if;
  update public.purchase_requisitions set status=next_status,revision=revision+1,purchasing_note=case when reason<>'' then reason else purchasing_note end where id=r.id;
  perform private.supply_event(factory,r.id,reason);
 elsif action='supplier_save' then
  if coalesce(length(btrim(payload->>'name')),0) not between 1 and 200 or length(coalesce(payload->>'phone',''))>100 or length(coalesce(payload->>'email',''))>200 or length(coalesce(payload->>'notes',''))>4000 then raise exception 'supply_invalid';end if;
  result:=coalesce((payload->>'id')::uuid,gen_random_uuid());
  if payload->>'id' is not null then
   update public.suppliers set name=btrim(payload->>'name'),primary_contact=coalesce(payload->>'primary_contact',''),phone=coalesce(payload->>'phone',''),email=coalesce(payload->>'email',''),notes=coalesce(payload->>'notes',''),active=coalesce((payload->>'active')::boolean,true) where factory_id=factory and id=result;
   if not found then raise exception 'supply_invalid';end if;
  else insert into public.suppliers(id,factory_id,name,primary_contact,phone,email,notes,active) values(result,factory,btrim(payload->>'name'),coalesce(payload->>'primary_contact',''),coalesce(payload->>'phone',''),coalesce(payload->>'email',''),coalesce(payload->>'notes',''),coalesce((payload->>'active')::boolean,true)) on conflict (factory_id,(lower(btrim(name)))) do update set name=public.suppliers.name returning id into result;end if;
  if nullif(btrim(payload->>'category'),'') is not null then
   insert into public.supplier_categories(factory_id,name) values(factory,btrim(payload->>'category')) on conflict(factory_id,name) do update set name=excluded.name returning id into category;
   if payload->>'relationship'='PRIMARY' and exists(select 1 from public.supplier_category_links where factory_id=factory and category_id=category and supplier_id<>result and relationship='PRIMARY') then
    if coalesce((payload->>'replace_primary')::boolean,false) is not true then raise exception 'supply_conflict';end if;
    update public.supplier_category_links set relationship='ALTERNATIVE' where factory_id=factory and category_id=category and relationship='PRIMARY';
   end if;
   insert into public.supplier_category_links values(factory,result,category,coalesce(payload->>'relationship','ALTERNATIVE')) on conflict(factory_id,supplier_id,category_id) do update set relationship=excluded.relationship;
  end if;
 elsif action='material_request' then
  target:=(payload->>'item')::uuid;u:=payload->>'unit';q:=(payload->>'quantity')::numeric;
  if payload->>'item_type'='lot' then
   select o.unit,p.name into u,label from public.unfinished_lots l join public.production_entries e on e.id=l.source_entry_id join public.production_orders o on o.id=e.order_id join public.products p on p.id=o.product_id where l.factory_id=factory and l.id=target and l.warehouse_quantity>0;
   lot:=target;
  else
   select value into row_data from private.warehouse_inventory_rows(factory) value where value->>'id'=target::text and value->>'unit'=u;
   if row_data->>'entity'='material' then mat:=target;else prod:=target;end if;label:=row_data->>'name';
  end if;
  if label is null or u is distinct from payload->>'unit' or q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity') or length(coalesce(payload->>'note',''))>2000 then raise exception 'supply_invalid';end if;
  insert into public.material_requests(factory_id,material_id,product_id,lot_id,production_item_id,item_name,quantity,unit,note,requested_by,requested_by_name)
  values(factory,mat,prod,lot,(payload->>'production_item_id')::uuid,label,q,u,coalesce(payload->>'note',''),auth.uid(),actor_name) returning id into result;
 elsif action='material_change' then
  select * into m from public.material_requests mr where mr.factory_id=factory and mr.id=(payload->>'id')::uuid for update;
  if not found then raise exception 'supply_invalid';end if;
  if m.revision is distinct from (payload->>'revision')::integer then raise exception 'supply_conflict';end if;
  result:=m.id;reason:=btrim(coalesce(payload->>'reason',''));
  if payload->>'action'='receive' then
   if m.status<>'ISSUED' or m.requested_by<>auth.uid() then raise exception 'supply_state';end if;
   update public.material_requests set status='RECEIVED',received_by=auth.uid(),received_at=clock_timestamp(),revision=revision+1 where id=m.id;
  elsif payload->>'action' in ('reject','cancel') then
   if m.status<>'REQUESTED' then raise exception 'supply_state';end if;
   if length(reason) not between 1 and 2000 then raise exception 'supply_reason';end if;
   update public.material_requests set status=case when payload->>'action'='reject' then 'REJECTED' else 'CANCELLED' end,reason=btrim(coalesce(payload->>'reason','')),revision=revision+1 where id=m.id;
  elsif payload->>'action'='issue' then
   if m.status<>'REQUESTED' then raise exception 'supply_state';end if;target:=gen_random_uuid();
   if m.lot_id is not null then
    select * into item from public.unfinished_lots where factory_id=factory and id=m.lot_id for update;
    if item.warehouse_quantity<m.quantity then raise exception 'supply_insufficient';end if;
    if exists(select 1 from private.manufactured_output_lots where factory_id=factory and lot_id=m.lot_id) then
 if not private.manufactured_output_enabled(factory) then raise exception 'recording_disabled';end if;
 if not exists(select 1 from private.manufactured_completion_work where factory_id=factory and material_request_id=m.id and lot_id=m.lot_id and item_id=m.production_item_id and quantity=m.quantity) then raise exception 'output_completion_required';end if;
 insert into private.manufactured_output_context values(pg_backend_pid(),txid_current(),factory,auth.uid(),item.source_entry_id,m.id,'ISSUE');end if;
update public.unfinished_lots set warehouse_quantity=warehouse_quantity-m.quantity where id=m.lot_id;
 delete from private.manufactured_output_context where backend=pg_backend_pid() and transaction_id=txid_current() and mode='ISSUE';
    insert into public.unfinished_movements(id,factory_id,lot_id,entry_id,kind,quantity,location_delta,created_by) values(target,factory,m.lot_id,item.source_entry_id,'warehouse_issue',0,-m.quantity,auth.uid());
   elsif m.material_id is not null then
    if not exists(select 1 from public.materials where factory_id=factory and id=m.material_id and unit=m.unit) then raise exception 'supply_invalid';end if;
    select coalesce(sum(quantity),0)-(select coalesce(sum(quantity),0) from public.inventory_reservations where factory_id=factory and material_id=m.material_id and released_at is null) into q from public.inventory_transactions where factory_id=factory and material_id=m.material_id;
    if q<m.quantity then raise exception 'supply_insufficient';end if;
    raise exception 'material_use_preparation_workflow'using errcode='22023';
   else
    select on_hand-reserved into q from public.finished_goods_balances where factory_id=factory and product_id=m.product_id and unit=m.unit for update;
    if coalesce(q,0)<m.quantity then raise exception 'supply_insufficient';end if;
    update public.finished_goods_balances set on_hand=on_hand-m.quantity where factory_id=factory and product_id=m.product_id and unit=m.unit;
    insert into public.finished_goods_movements(id,factory_id,product_id,unit,kind,stock_delta,reason,external_reference,created_by) values(target,factory,m.product_id,m.unit,'material_issue',-m.quantity,'Production material issue',m.id::text,auth.uid());
   end if;
   update public.material_requests set status='ISSUED',issued_by=auth.uid(),issued_at=clock_timestamp(),movement_id=target,revision=revision+1 where id=m.id;
  else raise exception 'supply_invalid';end if;
 elsif action='receive_wip' then
  target:=(payload->>'lot')::uuid;q:=(payload->>'quantity')::numeric;
  select * into item from public.unfinished_lots where factory_id=factory and id=target for update;
  if not found or q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity') or q>item.quantity_available-item.warehouse_quantity then raise exception 'supply_insufficient';end if;
  update public.unfinished_lots set warehouse_quantity=warehouse_quantity+q where id=target;
  result:=gen_random_uuid();insert into public.unfinished_movements(id,factory_id,lot_id,entry_id,kind,quantity,location_delta,created_by) values(result,factory,target,item.source_entry_id,'warehouse_receipt',0,q,auth.uid());
 elsif action='acknowledge_good' then
  target:=(payload->>'entry')::uuid;
  if not exists(select 1 from public.finished_goods_entry_receipts where factory_id=factory and entry_id=target and received_good>0) then raise exception 'supply_state';end if;
  insert into public.production_receipt_acknowledgments values(factory,target,auth.uid(),clock_timestamp()) on conflict do nothing;result:=target;
 end if;
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'supply_'||action,payload,result,clock_timestamp());return result;
end$function$
;
