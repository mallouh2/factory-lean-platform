-- Phase 4, inactive. Work allocations reference existing orders, lots and
-- requests; physical quantities remain exclusively in the existing ledgers.
begin;
alter table public.production_entries drop constraint recording_v3_shape;
alter table public.production_entries add constraint recording_v3_shape check((
 (attribution_version is null and execution_key is null and original_occurrence_key is null and effective_occurrence_key is null
 and original_period_start is null and original_period_end is null and effective_period_start is null and effective_period_end is null)
 or (attribution_version=1 and request_payload_version=1
 and ((recording_kind in ('ACTIVE_ORDINARY','LATE_ORDINARY') and input_lot_id is null) or (recording_kind='WIP_PROCESSING' and input_lot_id is not null))
 and line_id is not null and execution_key ~ '^[0-9a-f]{64}$' and execution_started_at is not null
 and original_occurrence_key is not null and effective_occurrence_key is not null
 and original_period_start is not null and original_period_end>=original_period_start
 and effective_period_start is not null and effective_period_end>=effective_period_start and time_precision='SHIFT_PERIOD'
 and (recording_kind<>'LATE_ORDINARY' or (execution_finished_at>execution_started_at and original_period_end>original_period_start)))) is true);
alter table private.manufactured_output_lots alter column demand_item_id drop not null;
create table private.manufactured_completion_work(
 factory_id uuid not null,item_id uuid not null,output_id uuid not null,group_id uuid not null,lot_id uuid not null,
 origin_item_id uuid not null,demand_item_id uuid,choice text not null check(choice in ('COMPLETE','REPLACE','STOCK')),
 quantity numeric not null check(quantity>0),operations jsonb not null,material_request_id uuid,
 request_id uuid not null,intent jsonb not null,result jsonb not null,created_by uuid not null references auth.users,
 created_at timestamptz not null default clock_timestamp(),primary key(factory_id,item_id),unique(factory_id,request_id),
 foreign key(factory_id,item_id) references public.production_orders(factory_id,id),
 foreign key(factory_id,origin_item_id) references public.production_orders(factory_id,id),
 foreign key(factory_id,demand_item_id) references public.production_orders(factory_id,id),
 foreign key(factory_id,output_id) references private.manufactured_outputs(factory_id,id),
 foreign key(factory_id,lot_id) references public.unfinished_lots(factory_id,id),
 foreign key(material_request_id) references public.material_requests(id)
);
alter table private.manufactured_completion_work enable row level security;
revoke all on private.manufactured_completion_work from public,anon,authenticated,service_role;
create trigger manufactured_completion_immutable before update or delete on private.manufactured_completion_work for each row execute function private.manufactured_output_immutable();
create index on private.manufactured_completion_work(factory_id,lot_id);
create index on private.manufactured_completion_work(factory_id,demand_item_id);
alter table private.manufactured_output_context drop constraint manufactured_output_context_mode_check;
alter table private.manufactured_output_context add check(mode in ('RECORD','CORRECTION','RECEIPT','RECONCILE','WORK','ISSUE'));

create function private.output_work_demand(f uuid,i uuid) returns uuid language sql stable security definer set search_path='' as $$
 select case when exists(select 1 from private.manufactured_completion_work where factory_id=f and item_id=i)
 then (select demand_item_id from private.manufactured_completion_work where factory_id=f and item_id=i) else i end
$$;
create function private.output_demand_received(f uuid,i uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce(sum(private.output_received(f,h.id,g->>'id')),0)
 from private.manufactured_outputs h cross join lateral jsonb_array_elements(private.output_quality(f,h.id)->'groups') g
 where h.factory_id=f and private.output_work_demand(f,h.item_id)=i and jsonb_array_length(g->'missing_operations')=0
$$;
create function private.output_work_consumed(f uuid,i uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce(sum(input_quantity),0) from public.production_entries where factory_id=f and order_id=i and input_lot_id is not null
$$;
-- Explicit operations use existing configured centers and product rates. OPEN
-- transfers determine the effective center; its permanent line is never changed.
create function private.output_work_line(f uuid,i uuid,l uuid,physical boolean default false) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare w private.manufactured_completion_work;op text;c public.work_centers;effective public.work_centers;h private.manufactured_outputs;begin
 select * into w from private.manufactured_completion_work where factory_id=f and item_id=i;
 if w.item_id is null or w.choice='REPLACE' then return true;end if;
 select * into h from private.manufactured_outputs where factory_id=f and id=w.output_id;
 for op in select jsonb_array_elements_text(w.operations) loop
  select * into c from public.work_centers where factory_id=f and id=(h.operation_snapshot->op->>'work_center_id')::uuid;
  if c.id is null or c.archived or c.line_id is distinct from l then return false;end if;
  select * into effective from public.work_centers where factory_id=f and id=coalesce((select alternative_id from public.production_transfers where factory_id=f and original_id=c.id and ended_at is null),c.id);
  if effective.id is null or effective.archived or effective.category_id is distinct from c.category_id
   or exists(select 1 from public.production_transfers where factory_id=f and alternative_id=c.id and ended_at is null)
   or not exists(select 1 from public.work_center_capabilities where factory_id=f and work_center_id=effective.id and product_id=h.product_id and rate_unit=h.unit and rate>0)
   or (physical and effective.status not in ('idle','running')) then return false;end if;
 end loop;
 return true;
end$$;
create function private.output_work_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare w private.manufactured_completion_work;begin
 select * into w from private.manufactured_completion_work where factory_id=new.factory_id and item_id=new.id;
 if w.item_id is null then return new;end if;
 if new.product_id is distinct from old.product_id or new.unit is distinct from old.unit or new.target_quantity is distinct from old.target_quantity
 or new.replacement_original_item_id is distinct from old.replacement_original_item_id or new.request_id is distinct from old.request_id
 then raise exception 'output_work_identity';end if;
 if new.line_id is not null and not private.output_work_line(new.factory_id,new.id,new.line_id) then raise exception 'output_work_capability';end if;
 if new.status='active' and old.status<>'active' then
  if not private.manufactured_output_enabled(new.factory_id) then raise exception 'recording_disabled';end if;
  if not private.output_work_line(new.factory_id,new.id,new.line_id,true) then raise exception 'output_work_not_ready';end if;
  if w.choice<>'REPLACE' and not exists(select 1 from public.material_requests where factory_id=new.factory_id and id=w.material_request_id and status in ('ISSUED','RECEIVED')) then raise exception 'output_material_not_issued';end if;
 end if;
 if new.status='completed' and old.status<>'completed' and w.choice<>'REPLACE' and private.output_work_consumed(new.factory_id,new.id)<>w.quantity then raise exception 'output_input_remaining';end if;
 return new;
end$$;
create trigger manufactured_completion_guard before update on public.production_orders for each row execute function private.output_work_guard();

create function public.plan_manufactured_completion(factory uuid,target uuid,payload jsonb,expected_revision bigint,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare h private.manufactured_outputs;m private.manufactured_output_lots;l public.unfinished_lots;g jsonb;prior private.manufactured_completion_work;
 q numeric;used numeric;freed numeric;reserved numeric;ops jsonb;choice text;demand uuid;pr uuid;i uuid;mr uuid;result jsonb;intent jsonb;revision bigint;
begin
 perform private.manufactured_output_authorize(factory,'DISPOSITION',expected_revision);perform private.require_permission(factory,'orders','create');
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.fulfillment_lock(factory);
 perform private.manufactured_output_authorize(factory,'DISPOSITION',expected_revision);perform private.require_permission(factory,'orders','create');
 if not private.manufactured_output_enabled(factory) then raise exception 'recording_disabled';end if;
 if request_id is null or jsonb_typeof(payload) is distinct from 'object' or expected_revision is null or octet_length(payload::text)>6000
 or exists(select 1 from jsonb_object_keys(payload) k where k not in ('group_id','quantity','choice','reason','operations'))
 or length(btrim(coalesce(payload->>'reason',''))) not between 3 and 2000 then raise exception 'output_disposition';end if;
 intent:=jsonb_build_object('target',target,'payload',payload,'expected',expected_revision);
 select * into prior from private.manufactured_completion_work where factory_id=factory and manufactured_completion_work.request_id=plan_manufactured_completion.request_id;
 if found then if prior.created_by<>auth.uid() or prior.intent<>intent then raise exception 'request_conflict';end if;return prior.result;end if;
 select * into h from private.manufactured_outputs where factory_id=factory and id=target for update;
 if h.id is null then raise exception 'output_not_found';end if;
 select max(ev.revision) into revision from private.manufactured_output_events ev where ev.output_id=h.id;
 if revision is distinct from expected_revision then raise exception 'output_revision';end if;
 select value into g from jsonb_array_elements(private.output_quality(factory,h.id)->'groups') where value->>'id'=payload->>'group_id';
 select * into m from private.manufactured_output_lots where factory_id=factory and output_id=h.id and group_id::text=payload->>'group_id';
 select * into l from public.unfinished_lots where factory_id=factory and id=m.lot_id for update;
 q:=(payload->>'quantity')::numeric;choice:=payload->>'choice';
 if g is null or l.id is null or jsonb_array_length(g->'missing_operations')=0 or q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity')
 or (h.unit='piece' and q<>trunc(q)) or choice is null or choice not in ('COMPLETE','REPLACE','STOCK') then raise exception 'output_disposition_quantity';end if;
 select coalesce(sum(quantity) filter(where w.choice in ('COMPLETE','REPLACE')),0),coalesce(sum(quantity) filter(where w.choice='REPLACE'),0)-coalesce(sum(quantity) filter(where w.choice='STOCK'),0),
 coalesce(sum(quantity-private.output_work_consumed(factory,item_id)) filter(where w.choice<>'REPLACE' and exists(select 1 from public.material_requests mr where mr.id=w.material_request_id and mr.status='REQUESTED')),0)
 into used,freed,reserved from private.manufactured_completion_work w where w.factory_id=factory and w.lot_id=l.id;
 if m.demand_item_id is null then freed:=l.quantity_created-used-coalesce((select sum(quantity) from private.manufactured_completion_work where factory_id=factory and lot_id=l.id and choice='STOCK'),0);end if;
 if q>l.warehouse_quantity-reserved or (choice='STOCK' and q>freed) or (choice<>'STOCK' and (m.demand_item_id is null or q>l.quantity_created-used)) then raise exception 'output_allocation_unavailable';end if;
 demand:=case when choice='STOCK' then null else m.demand_item_id end;
 if demand is not null and q>(select greatest(target_quantity-private.output_demand_received(factory,demand),0) from public.production_orders where factory_id=factory and id=demand) then raise exception 'output_demand_satisfied';end if;
 ops:=coalesce(payload->'operations','[]'::jsonb);
 if jsonb_typeof(ops)<>'array' or (choice<>'REPLACE' and jsonb_array_length(ops)=0)
 or exists(select 1 from jsonb_array_elements_text(ops) z where not(g->'missing_operations' ? z))
 or (select count(*)<>count(distinct value) from jsonb_array_elements_text(ops)) then raise exception 'output_work_operations';end if;
 select coalesce(jsonb_agg(value order by value),'[]') into ops from jsonb_array_elements_text(ops);
 if choice<>'STOCK' then
  perform private.manufactured_output_command(factory,'DISPOSITION',h.id,payload-'operations',expected_revision,request_id);
 end if;
 pr:=public.create_production_request(factory,case when choice='REPLACE' then 'Replacement production' else 'Complete unfinished production' end,'normal',null,payload->>'reason',
  jsonb_build_array(jsonb_build_object('product_id',h.product_id,'quantity',q,'unit',h.unit)));
 select po.id into i from public.production_orders po where po.factory_id=factory and po.request_id=pr;
 if choice<>'REPLACE' then
  insert into private.manufactured_output_context values(pg_backend_pid(),txid_current(),factory,auth.uid(),h.entry_id,request_id,'WORK');
  mr:=private.apply_supply_command(factory,'material_request',jsonb_build_object('item',l.id,'item_type','lot','unit',h.unit,'quantity',q,'note','Completion input: '||(payload->>'reason'),'production_item_id',i),gen_random_uuid());
  delete from private.manufactured_output_context where backend=pg_backend_pid() and transaction_id=txid_current();
 end if;
 result:=jsonb_build_object('item_id',i,'material_request_id',mr,'choice',choice,'quantity',q::text,'origin_item_id',h.item_id,'demand_item_id',demand);
 insert into private.manufactured_completion_work values(factory,i,h.id,m.group_id,l.id,h.item_id,demand,choice,q,ops,mr,request_id,intent,result,auth.uid(),clock_timestamp());
 perform private.manufactured_output_authorize(factory,'DISPOSITION',expected_revision);perform private.require_permission(factory,'orders','create');
 return result;
end$$;

-- Existing Warehouse request/issue remains the only physical issue. Guard
-- classified lots against free-form requests and unrelated demand allocation.
create function private.output_material_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare w private.manufactured_completion_work;begin
 if new.lot_id is null or not exists(select 1 from private.manufactured_output_lots where factory_id=new.factory_id and lot_id=new.lot_id) then return new;end if;
 if tg_op='INSERT' then
  if not exists(select 1 from private.manufactured_output_context where backend=pg_backend_pid() and transaction_id=txid_current() and factory_id=new.factory_id and actor_id=auth.uid() and mode='WORK') then raise exception 'output_completion_required';end if;
 else
  select * into w from private.manufactured_completion_work where factory_id=new.factory_id and material_request_id=new.id;
  if w.item_id is null or new.lot_id<>w.lot_id or new.production_item_id<>w.item_id or new.quantity<>w.quantity
   or new.status in ('REJECTED','CANCELLED') then raise exception 'output_work_identity';end if;
 end if;
 return new;
end$$;
create trigger manufactured_material_guard before insert or update on public.material_requests for each row execute function private.output_material_guard();

-- Allow exactly the existing issue/consume deltas for the immutable work link.
create or replace function private.output_lot_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare w private.manufactured_completion_work;e public.production_entries;begin
 if not exists(select 1 from private.manufactured_output_lots where factory_id=old.factory_id and lot_id=old.id) then return new;end if;
 if (to_jsonb(new)-'updated_at') is not distinct from (to_jsonb(old)-'updated_at') then return new;end if;
 if exists(select 1 from private.manufactured_output_context where backend=pg_backend_pid() and transaction_id=txid_current() and factory_id=old.factory_id and actor_id=auth.uid() and entry_id=old.source_entry_id and mode in ('RECEIPT','RECONCILE')) then return new;end if;
 select w0.* into w from private.manufactured_completion_work w0 join private.manufactured_output_context c on c.factory_id=w0.factory_id and c.entry_id=old.source_entry_id
 where w0.factory_id=old.factory_id and w0.lot_id=old.id and c.backend=pg_backend_pid() and c.transaction_id=txid_current() and c.actor_id=auth.uid() and c.mode='ISSUE' and c.request_id=w0.material_request_id
 and exists(select 1 from public.material_requests where id=w0.material_request_id and status='REQUESTED');
 if w.item_id is not null and new.warehouse_quantity=old.warehouse_quantity-w.quantity and (to_jsonb(new)-array['updated_at','warehouse_quantity'])=(to_jsonb(old)-array['updated_at','warehouse_quantity']) then return new;end if;
 select p.* into e from public.production_entries p join private.manufactured_output_context c on c.factory_id=p.factory_id and c.request_id=p.request_id
 join private.manufactured_completion_work w0 on w0.factory_id=p.factory_id and w0.item_id=p.order_id and w0.lot_id=old.id
 where p.input_lot_id=old.id and c.backend=pg_backend_pid() and c.transaction_id=txid_current() and c.actor_id=auth.uid() and c.mode='RECORD';
 if e.id is not null and new.quantity_available=old.quantity_available-e.input_quantity and new.quantity_available>=new.warehouse_quantity
 and (to_jsonb(new)-array['updated_at','quantity_available'])=(to_jsonb(old)-array['updated_at','quantity_available']) then return new;end if;
 raise exception 'output_completion_pending';
end$$;

create function private.output_recovery_validate(f uuid,p jsonb) returns void language plpgsql security definer set search_path='' as $$
declare w private.manufactured_completion_work;l public.unfinished_lots;g jsonb;h private.manufactured_outputs;left_ops jsonb;used numeric;q numeric;begin
 select * into w from private.manufactured_completion_work where factory_id=f and item_id=(p->>'item')::uuid;
 if w.item_id is null or w.choice='REPLACE' then if p->>'input_lot' is not null then raise exception 'recording_invalid_context';end if;return;end if;
 if (p->>'input_lot')::uuid is distinct from w.lot_id then raise exception 'output_input_required';end if;
 if not exists(select 1 from public.production_orders where factory_id=f and id=w.item_id and status='active') then raise exception 'output_work_not_ready';end if;
 select * into l from public.unfinished_lots where factory_id=f and id=w.lot_id for update;
 if not exists(select 1 from public.material_requests where factory_id=f and id=w.material_request_id and status in ('ISSUED','RECEIVED')) then raise exception 'output_material_not_issued';end if;
 q:=(p->>'input_quantity')::numeric;used:=private.output_work_consumed(f,w.item_id);
 if q is null or q<=0 or q>w.quantity-used or q>l.quantity_available-l.warehouse_quantity then raise exception 'output_input_quantity';end if;
 if not private.output_work_line(f,w.item_id,(p->>'production_unit')::uuid,true) then raise exception 'output_work_not_ready';end if;
 select * into h from private.manufactured_outputs where factory_id=f and id=w.output_id;
 select value into g from jsonb_array_elements(private.output_quality(f,w.output_id)->'groups') where value->>'id'=w.group_id::text;
 select coalesce(jsonb_agg(value),'[]') into left_ops from jsonb_array_elements_text(g->'missing_operations') where not(w.operations ? value);
 if exists(select 1 from jsonb_array_elements(p->'output_groups') z where not(z->'missing_operations' @> left_ops)) then raise exception 'output_operations_remaining';end if;
end$$;

do $patch$ declare b text;needle text;begin
 b:=pg_get_functiondef('public.supply_command(uuid,text,jsonb,uuid)'::regprocedure);
 b:=replace(b,'return private.apply_supply_command(factory,action,payload,request_id);',E'if action=''material_change'' and exists(select 1 from private.manufactured_completion_work where factory_id=factory and material_request_id=(payload->>''id'')::uuid) then\n perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.fulfillment_lock(factory);\n perform private.require_permission(factory,''factory'',''view'');\n if payload->>''action'' in (''issue'',''reject'',''cancel'') then perform private.require_permission(factory,''warehouse'',''issue'');end if;end if;\n return private.apply_supply_command(factory,action,payload,request_id);');execute b;
 -- Work dedicated to another demand cannot become a competing Sales forecast.
 -- Its receipts convert that original demand's commitments, exactly once.
 b:=pg_get_functiondef('private.allocate_sales_line(uuid,uuid)'::regprocedure);
 b:=replace(b,'where o.factory_id=f and o.product_id=l.product_id',E'where not exists(select 1 from private.manufactured_completion_work w where w.factory_id=f and w.item_id=o.id and w.demand_item_id is not null) and o.factory_id=f and o.product_id=l.product_id');execute b;
 b:=pg_get_functiondef('private.manufactured_output_command(uuid,text,uuid,jsonb,bigint,uuid)'::regprocedure);
 b:=replace(b,'if exists(select 1 from public.unfinished_lots where factory_id=f and source_entry_id=h.entry_id and quantity_available<>quantity_created) then raise exception ''output_reconciliation_required'';end if;','-- The protected work adapter validates exact remaining source allocation.');execute b;
 b:=pg_get_functiondef('private.apply_supply_command(uuid,text,jsonb,uuid)'::regprocedure);
 needle:='update public.unfinished_lots set warehouse_quantity=warehouse_quantity-m.quantity where id=m.lot_id;';
 if position(needle in b)=0 then raise exception 'issue contract changed';end if;
 b:=replace(b,needle,E'if exists(select 1 from private.manufactured_output_lots where factory_id=factory and lot_id=m.lot_id) then\n if not private.manufactured_output_enabled(factory) then raise exception ''recording_disabled'';end if;\n if not exists(select 1 from private.manufactured_completion_work where factory_id=factory and material_request_id=m.id and lot_id=m.lot_id and item_id=m.production_item_id and quantity=m.quantity) then raise exception ''output_completion_required'';end if;\n insert into private.manufactured_output_context values(pg_backend_pid(),txid_current(),factory,auth.uid(),item.source_entry_id,m.id,''ISSUE'');end if;\n'||needle||E'\n delete from private.manufactured_output_context where backend=pg_backend_pid() and transaction_id=txid_current() and mode=''ISSUE'';');execute b;
 b:=pg_get_functiondef('public.record_manufactured_output(uuid,jsonb,uuid)'::regprocedure);
 b:=replace(b,'context:=private.recording_v3_context',E'perform private.output_recovery_validate(factory,payload);\n context:=private.recording_v3_context');execute b;
 b:=pg_get_functiondef('private.recording_request_payload(uuid,jsonb)'::regprocedure);
 b:=replace(b,'or n->>''input_lot'' is not null','or (n->>''input_lot'' is not null and not exists(select 1 from private.manufactured_completion_work where factory_id=f and item_id=(n->>''item'')::uuid and lot_id=(n->>''input_lot'')::uuid and choice<>''REPLACE''))');execute b;
 b:=pg_get_functiondef('private.recording_v3_context(uuid,uuid,jsonb)'::regprocedure);
 b:=replace(b,'case when late then ''LATE_ORDINARY'' else ''ACTIVE_ORDINARY'' end','case when late then ''LATE_ORDINARY'' when p->>''input_lot'' is not null then ''WIP_PROCESSING'' else ''ACTIVE_ORDINARY'' end');execute b;
 b:=pg_get_functiondef('private.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,text,numeric,text,uuid,numeric,jsonb,jsonb)'::regprocedure);
 b:=replace(b,'src.order_id=i and src.unit=job.unit','(src.order_id=i or exists(select 1 from private.manufactured_completion_work where factory_id=f and item_id=i and lot_id=input_lot and choice<>''REPLACE'')) and src.unit=job.unit');
 b:=replace(b,'attribution->>''kind''=''ACTIVE_ORDINARY''','attribution->>''kind'' in (''ACTIVE_ORDINARY'',''WIP_PROCESSING'')');
 b:=replace(b,'if input_lot is null then',E'if exists(select 1 from private.manufactured_completion_work where factory_id=f and item_id=i) and not private.manufactured_output_context_matches(f,null,r,''RECORD'') then raise exception ''output_completion_required'';end if;\n if input_lot is null then');execute b;
 b:=pg_get_functiondef('public.receive_manufactured_output(uuid,uuid,jsonb,bigint,uuid)'::regprocedure);
 b:=replace(b,'''restriction'',g->>''restriction''),h.item_id,payload->>''location'')','''restriction'',g->>''restriction''),private.output_work_demand(factory,h.item_id),payload->>''location'')');
 b:=replace(b,'ia.item_id=h.item_id and ia.quantity>0','ia.item_id in (h.item_id,private.output_work_demand(factory,h.item_id)) and ia.quantity>0');execute b;
end $patch$;

create function public.manufactured_completion_read(factory uuid,page integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare rows jsonb;work jsonb;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'orders','view');
 if not private.manufactured_output_enabled(factory) then return jsonb_build_object('available',false,'rows','[]','work','[]');end if;
 if page is null or page<0 or page>100000 then raise exception 'output_invalid';end if;
 select coalesce(jsonb_agg(to_jsonb(z)),'[]') into rows from (
 select h.id,h.item_id,h.entry_id,h.unit,p.name,p.name_ar,o.code,origin.code demand_code,m.group_id,m.lot_id,m.demand_item_id,m.location,m.classification,h.operation_snapshot operations,
 (select max(revision) from private.manufactured_output_events where output_id=h.id)::text revision,
 l.warehouse_quantity::text stored,l.quantity_available::text physical_remaining,
 (greatest(l.quantity_created-coalesce(a.assigned,0),0))::text unassigned,
 (greatest(case when m.demand_item_id is null then l.quantity_created else coalesce(a.replaced,0) end-coalesce(a.stock,0),0))::text free_for_stock,
 (greatest(l.warehouse_quantity-coalesce(a.reserved,0),0))::text available_to_allocate,
 case when m.demand_item_id is not null then greatest(origin.target_quantity-private.output_demand_received(factory,m.demand_item_id),0)::text end shortage,
 (private.output_quality(factory,h.id)->>'rejected') rejected,
 (select coalesce(jsonb_agg(jsonb_build_object('operation',e.operation,'at',e.created_at,'result',e.result-array['receipt','recording_intent']) order by e.revision),'[]') from private.manufactured_output_events e where e.output_id=h.id and e.operation in ('QUALITY','DISPOSITION')) history
 from private.manufactured_output_lots m join private.manufactured_outputs h on h.factory_id=m.factory_id and h.id=m.output_id
 join public.unfinished_lots l on l.factory_id=m.factory_id and l.id=m.lot_id join public.production_orders o on o.factory_id=h.factory_id and o.id=h.item_id
 join public.products p on p.factory_id=h.factory_id and p.id=h.product_id left join public.production_orders origin on origin.factory_id=m.factory_id and origin.id=m.demand_item_id
 left join lateral(select sum(quantity) filter(where choice in ('COMPLETE','REPLACE')) assigned,sum(quantity) filter(where choice='REPLACE') replaced,sum(quantity) filter(where choice='STOCK') stock,
 sum(quantity-private.output_work_consumed(factory,item_id)) filter(where choice<>'REPLACE' and exists(select 1 from public.material_requests mr where mr.id=material_request_id and mr.status='REQUESTED')) reserved from private.manufactured_completion_work where factory_id=m.factory_id and lot_id=m.lot_id) a on true
 where m.factory_id=factory and l.quantity_available>0 order by h.created_at,h.id,m.group_id limit 50 offset page*50) z;
 select coalesce(jsonb_agg(to_jsonb(z)),'[]') into work from (
 select w.item_id,o.code,o.status,o.line_id,o.start_time,o.expected_finish,w.choice,w.quantity::text,h.unit,w.demand_item_id,d.code demand_code,w.origin_item_id,src.code origin_code,
 w.lot_id,w.operations,h.operation_snapshot operation_names,private.output_work_consumed(factory,w.item_id)::text consumed,
 case when w.demand_item_id is not null then private.output_demand_received(factory,w.demand_item_id)::text end demand_received,
 case when w.demand_item_id is not null then greatest(d.target_quantity-private.output_demand_received(factory,w.demand_item_id),0)::text end demand_shortage,
 (select coalesce(sum(private.output_received(factory,ch.id,g->>'id')),0)::text from private.manufactured_outputs ch cross join lateral jsonb_array_elements(private.output_quality(factory,ch.id)->'groups') g where ch.factory_id=factory and ch.item_id=w.item_id and jsonb_array_length(g->'missing_operations')=0) received_finished,
 mr.status material_status,w.material_request_id,w.created_at,w.created_by,w.intent->'payload'->>'reason' reason,
 (select coalesce(jsonb_agg(l.id),'[]') from public.production_lines l where l.factory_id=factory and not l.archived and private.output_work_line(factory,w.item_id,l.id)) capable_lines
 from private.manufactured_completion_work w join public.production_orders o on o.factory_id=w.factory_id and o.id=w.item_id
 join private.manufactured_outputs h on h.factory_id=w.factory_id and h.id=w.output_id join public.production_orders src on src.factory_id=w.factory_id and src.id=w.origin_item_id
 left join public.production_orders d on d.factory_id=w.factory_id and d.id=w.demand_item_id left join public.material_requests mr on mr.factory_id=w.factory_id and mr.id=w.material_request_id
 where w.factory_id=factory order by w.created_at desc limit 100) z;
 return jsonb_build_object('available',true,'rows',rows,'work',work,'has_more',jsonb_array_length(rows)=50);
end$$;
-- The existing V3 recorder gets authoritative input context alongside its
-- existing operation picker, retaining its durable UUID and status recovery.
do $$declare b text;begin
 b:=pg_get_functiondef('public.manufactured_output_read(uuid,text,uuid,integer)'::regprocedure);
 b:=replace(b,'''operations'',rows);',E'''operations'',rows,''recovery'',(select jsonb_build_object(''lot_id'',w.lot_id,''remaining'',(w.quantity-private.output_work_consumed(factory,w.item_id))::text,''operations'',w.operations,''missing_operations'',m.classification->''missing_operations'',''material_status'',mr.status) from private.manufactured_completion_work w join private.manufactured_output_lots m on m.factory_id=w.factory_id and m.lot_id=w.lot_id left join public.material_requests mr on mr.id=w.material_request_id where w.factory_id=factory and w.item_id=target and w.choice<>''REPLACE''));');execute b;
end$$;
revoke all on function public.manufactured_completion_read(uuid,integer) from public,anon,service_role;
grant execute on function public.manufactured_completion_read(uuid,integer) to authenticated;
revoke all on function private.output_work_demand(uuid,uuid),private.output_demand_received(uuid,uuid),private.output_work_consumed(uuid,uuid),private.output_work_line(uuid,uuid,uuid,boolean),private.output_work_guard(),private.output_material_guard(),private.output_recovery_validate(uuid,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.plan_manufactured_completion(uuid,uuid,jsonb,bigint,uuid) from public,anon,service_role;
grant execute on function public.plan_manufactured_completion(uuid,uuid,jsonb,bigint,uuid) to authenticated;
commit;
