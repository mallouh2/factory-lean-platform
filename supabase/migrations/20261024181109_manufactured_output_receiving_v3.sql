-- Inactive Phase 3. Inventory remains in the existing ledgers; these tables
-- bind immutable handoff/audit facts and classifications to those movements.
begin;
alter table public.unfinished_lots add column manufactured_group_id uuid;
drop index public.unfinished_normal_entry;
create unique index unfinished_normal_entry on public.unfinished_lots(factory_id,source_entry_id) where quality_rejection_id is null and manufactured_group_id is null;
create unique index unfinished_manufactured_group on public.unfinished_lots(factory_id,source_entry_id,manufactured_group_id) where manufactured_group_id is not null;
create table private.manufactured_output_lots(
 factory_id uuid not null,output_id uuid not null,group_id uuid not null,lot_id uuid not null,
 classification jsonb not null,demand_item_id uuid not null,location text not null,
 primary key(factory_id,output_id,group_id),unique(factory_id,lot_id),
 foreign key(factory_id,output_id) references private.manufactured_outputs(factory_id,id),
 foreign key(factory_id,lot_id) references public.unfinished_lots(factory_id,id),
 foreign key(factory_id,demand_item_id) references public.production_orders(factory_id,id)
);
create table private.manufactured_output_adjustments(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null,output_id uuid not null,
 quality_revision bigint not null,group_id uuid not null,quantity numeric not null check(quantity>0),
 finished_movement_id uuid,unfinished_movement_id uuid,reason text not null,
 created_by uuid not null references auth.users,created_at timestamptz not null default clock_timestamp(),
 check(num_nonnulls(finished_movement_id,unfinished_movement_id)=1),
 foreign key(factory_id,output_id) references private.manufactured_outputs(factory_id,id),
 foreign key(factory_id,finished_movement_id) references public.finished_goods_movements(factory_id,id),
 foreign key(unfinished_movement_id) references public.unfinished_movements(id)
);
alter table private.manufactured_output_lots enable row level security;
alter table private.manufactured_output_adjustments enable row level security;
revoke all on private.manufactured_output_lots,private.manufactured_output_adjustments from public,anon,authenticated,service_role;
create trigger output_lot_metadata_immutable before update or delete on private.manufactured_output_lots for each row execute function private.manufactured_output_immutable();
create trigger output_adjustment_immutable before update or delete on private.manufactured_output_adjustments for each row execute function private.manufactured_output_immutable();
create index on private.manufactured_output_adjustments(factory_id,output_id,group_id);
alter table private.manufactured_output_context drop constraint manufactured_output_context_mode_check;
alter table private.manufactured_output_context add check(mode in ('RECORD','CORRECTION','RECEIPT','RECONCILE'));

create function private.output_received(f uuid,o uuid,g text) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce((select sum((result->>'quantity')::numeric) from private.manufactured_output_events where factory_id=f and output_id=o and operation='RECEIPT' and result->>'group_id'=g),0)
 -coalesce((select sum(quantity) from private.manufactured_output_adjustments where factory_id=f and output_id=o and group_id::text=g),0)
$$;
create function private.output_quality(f uuid,o uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select result from private.manufactured_output_events where factory_id=f and output_id=o and operation='QUALITY'
 and revision>coalesce((select max(revision) from private.manufactured_output_events where factory_id=f and output_id=o and operation='CORRECTION'),0) order by revision desc limit 1
$$;
create function private.output_pending(f uuid,i uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce(sum((g->>'quantity')::numeric-private.output_received(f,h.id,g->>'id')),0)
 from private.manufactured_outputs h cross join lateral jsonb_array_elements(coalesce(private.output_quality(f,h.id)->'groups',
 (select result->'groups' from private.manufactured_output_events where output_id=h.id and operation='CORRECTION' order by revision desc limit 1),h.recorded_groups)) g
 where h.factory_id=f and h.item_id=i and jsonb_array_length(g->'missing_operations')=0
$$;

-- Safe stock withdrawal is part of the same Quality amendment. Unidentified
-- pooled stock cannot prove this source is still present: fail closed until
-- normal physical identification, never guess a source from aggregate stock.
create function private.output_reconcile(f uuid,o uuid,groups jsonb,rev bigint,reason text) returns void
 language plpgsql security definer set search_path='' as $$
declare h private.manufactured_outputs;oldg jsonb;newg jsonb;used numeric;keep numeric;amount numeric;
 src public.finished_goods_sources;l public.unfinished_lots;m uuid;wm uuid;begin
 select * into h from private.manufactured_outputs where factory_id=f and id=o;
 if exists(select 1 from private.manufactured_output_events where output_id=o and operation='DISPOSITION') then raise exception 'output_reconciliation_required';end if;
 for oldg in select value from jsonb_array_elements(private.output_quality(f,o)->'groups') loop
  used:=private.output_received(f,o,oldg->>'id');if used=0 then continue;end if;
  select value into newg from jsonb_array_elements(groups) where value->>'id'=oldg->>'id';
  if newg is not null and (newg->'missing_operations' is distinct from oldg->'missing_operations' or newg->>'restriction' is distinct from oldg->>'restriction') then raise exception 'output_group_identity_change';end if;
  keep:=case when newg->'missing_operations'=oldg->'missing_operations' and newg->>'restriction'=oldg->>'restriction' then least(used,(newg->>'released')::numeric) else 0 end;
  amount:=used-coalesce(keep,0);if amount=0 then continue;end if;m:=null;wm:=null;
  if jsonb_array_length(oldg->'missing_operations')=0 then
   select * into src from public.finished_goods_sources where factory_id=f and entry_id=h.entry_id for update;
   if src.id is null or src.quantity_available-private.source_reserved(f,src.id)<amount
    or not exists(select 1 from public.finished_goods_balances where factory_id=f and product_id=h.product_id and unit=h.unit and on_hand-reserved>=amount)
    then raise exception 'output_stock_unavailable';end if;
   perform private.source_begin_pick(f,'quality_rejection',h.product_id,h.unit,h.entry_id,jsonb_build_array(jsonb_build_object('source_id',src.id,'quantity',amount)));
   update public.finished_goods_balances set on_hand=on_hand-amount where factory_id=f and product_id=h.product_id and unit=h.unit;
   insert into public.finished_goods_movements(factory_id,product_id,unit,kind,stock_delta,entry_id,reason,created_by)
    values(f,h.product_id,h.unit,'quality_rejection',-amount,h.entry_id,reason,auth.uid()) returning id into m;
   perform private.source_end_pick();
  else
   select lot.* into l from public.unfinished_lots lot join private.manufactured_output_lots x on x.factory_id=lot.factory_id and x.lot_id=lot.id
    where x.factory_id=f and x.output_id=o and x.group_id::text=oldg->>'id' for update of lot;
   if l.id is null or l.quantity_available<>l.quantity_created or l.warehouse_quantity<amount
    or exists(select 1 from public.material_requests where factory_id=f and lot_id=l.id and status not in ('REJECTED','CANCELLED')) then raise exception 'output_stock_unavailable';end if;
   insert into private.manufactured_output_context values(pg_backend_pid(),txid_current(),f,auth.uid(),h.entry_id,gen_random_uuid(),'RECONCILE');
   update public.unfinished_lots set quantity_created=quantity_created-amount,quantity_available=quantity_available-amount,warehouse_quantity=warehouse_quantity-amount where id=l.id;
   insert into public.unfinished_movements(factory_id,lot_id,entry_id,kind,quantity,location_delta,created_by)
    values(f,l.id,h.entry_id,'quality_rejection',-amount,-amount,auth.uid()) returning id into wm;
   delete from private.manufactured_output_context where backend=pg_backend_pid() and transaction_id=txid_current();
  end if;
  insert into private.manufactured_output_adjustments(factory_id,output_id,quality_revision,group_id,quantity,finished_movement_id,unfinished_movement_id,reason,created_by)
   values(f,o,rev,(oldg->>'id')::uuid,amount,m,wm,reason,auth.uid());
 end loop;
end$$;

create function public.receive_manufactured_output(factory uuid,target uuid,payload jsonb,expected_revision bigint,request_id uuid) returns jsonb
 language plpgsql security definer set search_path='' as $$
declare h private.manufactured_outputs;prior private.manufactured_output_events;q numeric;g jsonb;qa jsonb;m uuid;l public.unfinished_lots;
 result jsonb;binding jsonb;leftover numeric;take numeric;a record;rev bigint;begin
 perform private.manufactured_output_authorize(factory,'RECEIPT',expected_revision);
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.fulfillment_lock(factory);
 perform private.manufactured_output_authorize(factory,'RECEIPT',expected_revision);
 if not private.manufactured_output_enabled(factory) then raise exception 'recording_disabled' using errcode='55000';end if;
 if request_id is null or payload is null or jsonb_typeof(payload)<>'object' or octet_length(payload::text)>4000 or expected_revision is null
 or exists(select 1 from jsonb_object_keys(payload) k where k not in ('group_id','quantity','physical_confirmation','location','note'))
 or payload->'physical_confirmation' is distinct from 'true'::jsonb or length(btrim(coalesce(payload->>'location',''))) not between 1 and 200
 or length(coalesce(payload->>'note',''))>2000 then raise exception 'output_physical_confirmation';end if;
 select * into prior from private.manufactured_output_events where factory_id=factory and manufactured_output_events.request_id=receive_manufactured_output.request_id;
 if found then
  if prior.operation<>'RECEIPT' or prior.created_by<>auth.uid() or prior.output_id<>target or prior.intent->'payload'->'client_receipt' is distinct from payload or (prior.intent->>'expected')::bigint<>expected_revision then raise exception 'request_conflict';end if;
  return prior.result;
 end if;
 select * into h from private.manufactured_outputs where factory_id=factory and id=target for update;
 if h.id is null then raise exception 'output_not_found';end if;
 select max(revision) into rev from private.manufactured_output_events where output_id=h.id;
 if rev<>expected_revision then raise exception 'output_revision';end if;
 qa:=private.output_quality(factory,target);if qa is null then raise exception 'output_quality_required';end if;
 select value into g from jsonb_array_elements(qa->'groups') where value->>'id'=payload->>'group_id';q:=(payload->>'quantity')::numeric;
 if g is null or q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity') or q+private.output_received(factory,target,g->>'id')>(g->>'released')::numeric or (h.unit='piece' and q<>trunc(q)) then raise exception 'output_receipt_quantity';end if;
 insert into private.manufactured_output_context values(pg_backend_pid(),txid_current(),factory,auth.uid(),h.entry_id,request_id,'RECEIPT');
 if jsonb_array_length(g->'missing_operations')=0 then
  perform private.finished_balance(factory,h.product_id,h.unit);
  update public.finished_goods_balances set on_hand=on_hand+q where factory_id=factory and product_id=h.product_id and unit=h.unit;
  insert into public.finished_goods_movements(factory_id,product_id,unit,kind,stock_delta,entry_id,created_by)
   values(factory,h.product_id,h.unit,'production_receipt',q,h.entry_id,auth.uid()) returning id into m;
 else
  select lot.* into l from public.unfinished_lots lot join private.manufactured_output_lots x on x.factory_id=lot.factory_id and x.lot_id=lot.id
   where x.factory_id=factory and x.output_id=target and x.group_id::text=g->>'id' for update of lot;
  if l.id is null then
   insert into public.unfinished_lots(factory_id,source_entry_id,manufactured_group_id,quantity_created,quantity_available,warehouse_quantity,remaining_work,created_at,created_by)
    values(factory,h.entry_id,(g->>'id')::uuid,q,q,q,'Quality released: '||(g->'missing_operations')::text||' '||coalesce(g->>'restriction',''),clock_timestamp(),auth.uid()) returning * into l;
   insert into private.manufactured_output_lots values(factory,target,(g->>'id')::uuid,l.id,jsonb_build_object('missing_operations',g->'missing_operations','restriction',g->>'restriction'),h.item_id,payload->>'location');
  else
   if not exists(select 1 from private.manufactured_output_lots where factory_id=factory and lot_id=l.id and location=payload->>'location' and classification=jsonb_build_object('missing_operations',g->'missing_operations','restriction',g->>'restriction')) then raise exception 'output_lot_classification';end if;
   update public.unfinished_lots set quantity_created=quantity_created+q,quantity_available=quantity_available+q,warehouse_quantity=warehouse_quantity+q where id=l.id;
  end if;
  insert into public.unfinished_movements(factory_id,lot_id,entry_id,kind,quantity,location_delta,created_by)
   values(factory,l.id,h.entry_id,'warehouse_receipt',0,q,auth.uid()) returning id into m;
 end if;
 binding:=(payload-'note')||jsonb_build_object('movement_id',m,'client_receipt',payload);
 result:=private.manufactured_output_command(factory,'RECEIPT',target,binding,expected_revision,request_id);
 delete from private.manufactured_output_context where backend=pg_backend_pid() and transaction_id=txid_current();
 if jsonb_array_length(g->'missing_operations')=0 then
  leftover:=q;
  for a in select ia.id,ia.line_id,ia.quantity from public.sales_incoming_allocations ia join public.sales_order_lines sl on sl.id=ia.line_id join public.sales_orders so on so.id=sl.order_id
   where ia.factory_id=factory and ia.item_id=h.item_id and ia.quantity>0 and so.status='approved' order by so.created_at,ia.id for update of ia loop
   take:=least(leftover,a.quantity);exit when take<=0;
   perform private.reserve_finished(factory,a.line_id,take);
   update public.sales_incoming_allocations set quantity=quantity-take,received_quantity=received_quantity+take where id=a.id;leftover:=leftover-take;
  end loop;
  perform private.reserve_received_stock(factory,h.product_id,h.unit);
 end if;
 perform private.manufactured_output_authorize(factory,'RECEIPT',expected_revision);
 return result;
end$$;

-- Group-bound storage cannot enter old unclassified issue/processing paths.
-- Phase 4 must supply explicit demand-preserving completion allocation.
create function private.output_lot_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from private.manufactured_output_lots where factory_id=old.factory_id and lot_id=old.id)
 and (to_jsonb(new)-'updated_at') is distinct from (to_jsonb(old)-'updated_at')
 and not exists(select 1 from private.manufactured_output_context where backend=pg_backend_pid() and transaction_id=txid_current() and factory_id=old.factory_id and actor_id=auth.uid() and entry_id=old.source_entry_id and mode in ('RECEIPT','RECONCILE')) then raise exception 'output_completion_pending';end if;return new;
end$$;
create trigger manufactured_output_lot_guard before update on public.unfinished_lots for each row execute function private.output_lot_guard();
create function private.output_legacy_quality_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from private.manufactured_outputs where factory_id=new.factory_id and entry_id=new.entry_id) then raise exception 'output_use_quality_determination';end if;return new;
end$$;
create trigger manufactured_output_legacy_quality_guard before insert on public.quality_rejections for each row execute function private.output_legacy_quality_guard();

-- Replacement netting applies only to future execution. Physical output already
-- produced but awaiting receipt is additional supply, including completed jobs.
create function private.output_future_remaining(f uuid,i uuid,subtree boolean default false) returns numeric
language plpgsql stable security definer set search_path='' as $$
declare own_need numeric;children_need numeric;begin
 select case when status in ('planned','active') then accepted_remaining_quantity else 0 end into own_need
 from public.production_orders where factory_id=f and id=i;
 if own_need is null then return 0;end if;
 if exists(select 1 from private.manufactured_outputs where factory_id=f and item_id=i) then
  own_need:=greatest(own_need-coalesce((select sum(e.effective_unfinished) from private.manufactured_outputs h
   join public.production_entries e on e.id=h.entry_id where h.factory_id=f and h.item_id=i),0),0);
 end if;
 select coalesce(sum(private.output_future_remaining(f,o.id,true)),0) into children_need
 from public.production_orders o where o.factory_id=f and o.replacement_original_item_id=i;
 return case when subtree then greatest(own_need,children_need) else greatest(own_need-children_need,0) end;
end$$;
create or replace function private.quality_production_remaining(f uuid,i uuid,subtree boolean default false) returns numeric
language plpgsql stable security definer set search_path='' as $$
declare pending numeric;begin
 if subtree then
  with recursive items as (
   select id from public.production_orders where factory_id=f and id=i
   union all select o.id from public.production_orders o join items p on o.replacement_original_item_id=p.id where o.factory_id=f
  ) select coalesce(sum(private.output_pending(f,id)),0) into pending from items;
 else pending:=private.output_pending(f,i);end if;
 return private.output_future_remaining(f,i,subtree)+pending;
end$$;
revoke all on function private.output_future_remaining(uuid,uuid,boolean) from public,anon,authenticated,service_role;
do $patch$ declare body text;fn record;begin
 for fn in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('private','public') and p.proname in ('finished_inventory_projection','allocate_sales_line','warehouse_inventory_rows','warehouse_page','fulfillment_preview','replenish_finished','production_fulfillment','warehouse_fulfillment','sales_fulfillment','fulfillment_guidance') loop
  body:=pg_get_functiondef(fn.oid);
  body:=replace(body,'o.status in (''planned'',''active'')','(o.status in (''planned'',''active'') or private.output_pending(o.factory_id,o.id)>0)');execute body;
 end loop;
 -- Do not let recording shrink commitments before receiving converts them.
 body:=pg_get_functiondef('private.guard_sales_production_commitment()'::regprocedure);
 body:=replace(body,'greatest(new.target_quantity-(new.produced_quantity-new.rejected_quantity),0)<committed',E'(greatest(new.target_quantity-(new.produced_quantity-new.rejected_quantity),0)<committed and not (new.target_quantity is not distinct from old.target_quantity and exists(select 1 from private.manufactured_outputs where factory_id=new.factory_id and item_id=new.id)) and not exists(select 1 from private.manufactured_output_context where backend=pg_backend_pid() and transaction_id=txid_current() and factory_id=new.factory_id and actor_id=auth.uid() and mode=''RECORD''))');execute body;
 -- Enrolled sources can never fall back into legacy immediate credit on update.
 body:=pg_get_functiondef('private.capture_finished_good()'::regprocedure);
 body:=replace(body,'select * into job',E'if exists(select 1 from private.manufactured_outputs where factory_id=new.factory_id and entry_id=new.id) then return new;end if;\n select * into job');execute body;
 -- Extend the Phase 1 primitive, preserving its authorization/revision/replay.
 body:=pg_get_functiondef('private.manufactured_output_command(uuid,text,uuid,jsonb,bigint,uuid)'::regprocedure);
 body:=replace(body,'''physical_confirmation'',''location''))','''physical_confirmation'',''location'',''client_receipt''))');
 body:=replace(body,'select coalesce(sum((ev.result->>''quantity'')::numeric),0) into used from private.manufactured_output_events ev where factory_id=f and output_id=h.id and operation=''RECEIPT'' and ev.result->>''group_id''=p->>''group_id'';','used:=private.output_received(f,h.id,p->>''group_id'');');
 body:=replace(body,'and xmin::text=pg_current_xact_id()::text;', 'and (xmin::text=pg_current_xact_id()::text or exists(select 1 from private.manufactured_output_context where backend=pg_backend_pid() and transaction_id=txid_current() and factory_id=f and actor_id=auth.uid() and entry_id=h.entry_id and mode=''RECEIPT''));');
 body:=replace(body,'if exists(select 1 from private.manufactured_output_events where factory_id=f and output_id=h.id and operation in (''RECEIPT'',''DISPOSITION'')) then raise exception ''output_reconciliation_required'';end if;','if exists(select 1 from private.manufactured_output_events where factory_id=f and output_id=h.id and operation=''DISPOSITION'') then raise exception ''output_reconciliation_required'';end if;');
 body:=replace(body,'result:=jsonb_build_object(''output_id'',h.id,''revision'',rev,''groups'',groups,''rejected''',E'perform private.output_reconcile(f,h.id,groups,rev,p->>''reason'');\n   result:=jsonb_build_object(''output_id'',h.id,''revision'',rev,''groups'',groups,''rejected''');execute body;
 -- Old boolean acknowledgment and floor-WIP receiving cannot target this path.
 body:=pg_get_functiondef('private.apply_supply_command(uuid,text,jsonb,uuid)'::regprocedure);
 body:=replace(body,'old:=private.fulfillment_retry',E'if action=''acknowledge_good'' and exists(select 1 from private.manufactured_outputs where factory_id=factory and entry_id=(payload->>''entry'')::uuid) then raise exception ''output_quantity_receipt_required'';end if;\n if action=''receive_wip'' and exists(select 1 from private.manufactured_output_lots where factory_id=factory and lot_id=(payload->>''lot'')::uuid) then raise exception ''output_quantity_receipt_required'';end if;\n old:=private.fulfillment_retry');execute body;
 -- Avoid legacy acknowledgment UI for deferred-credit entries.
 body:=pg_get_functiondef('public.supply_page(uuid,text,integer,jsonb,uuid)'::regprocedure);
 body:=replace(body,'where e.factory_id=factory', 'where not exists(select 1 from private.manufactured_outputs h where h.factory_id=e.factory_id and h.entry_id=e.id) and e.factory_id=factory');execute body;
end $patch$;

create function public.manufactured_receiving_read(factory uuid,page integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare rows jsonb;pools jsonb;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'warehouse','view');
 if not private.manufactured_output_enabled(factory) then return jsonb_build_object('available',false,'rows','[]'::jsonb);end if;
 if page is null or page<0 or page>100000 then raise exception 'output_invalid';end if;
 select coalesce(jsonb_agg(x.row order by x.created_at desc,x.id),'[]') into rows from (
 select h.id,h.created_at,jsonb_build_object('id',h.id,'entry_id',h.entry_id,'item_id',h.item_id,'product_id',h.product_id,'unit',h.unit,'product_name',p.name,'product_name_ar',p.name_ar,
 'order',e.request_code,'line',e.line_name,'shift',e.effective_occurrence->>'name','date',e.created_at,'operations',h.operation_snapshot,'recorded',h.quantity,
 'revision',(select max(revision) from private.manufactured_output_events where output_id=h.id),'rejected',qa->>'rejected',
 'groups',(select coalesce(jsonb_agg(g||jsonb_build_object('received',private.output_received(factory,h.id,g->>'id')::text,'remaining',((g->>'released')::numeric-private.output_received(factory,h.id,g->>'id'))::text)),'[]') from jsonb_array_elements(qa->'groups') g),
 'receipts',(select coalesce(jsonb_agg(jsonb_build_object('quantity',result->>'quantity','group_id',result->>'group_id','location',result->>'location','note',intent->'payload'->'client_receipt'->>'note','at',created_at,'actor',created_by) order by revision),'[]') from private.manufactured_output_events where output_id=h.id and operation='RECEIPT'),
 'adjustments',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from private.manufactured_output_adjustments a where output_id=h.id)) row
 from private.manufactured_outputs h join public.products p on p.factory_id=h.factory_id and p.id=h.product_id join private.production_reporting_entries e on e.factory_id=h.factory_id and e.id=h.entry_id
 cross join lateral (select private.output_quality(factory,h.id) qa) q where h.factory_id=factory and qa is not null order by h.created_at desc,h.id limit 50 offset page*50) x;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into pools from (
 select h.product_id,p.name,p.name_ar,h.unit,h.operation_snapshot operations,m.classification,m.location,sum(l.warehouse_quantity)::text quantity,
 jsonb_agg(jsonb_build_object('lot_id',l.id,'item_id',m.demand_item_id,'output_id',h.id,'quantity',l.warehouse_quantity::text)) sources
 from private.manufactured_output_lots m join public.unfinished_lots l on l.factory_id=m.factory_id and l.id=m.lot_id
 join private.manufactured_outputs h on h.factory_id=m.factory_id and h.id=m.output_id join public.products p on p.factory_id=h.factory_id and p.id=h.product_id
 where m.factory_id=factory and l.warehouse_quantity>0 group by h.product_id,p.name,p.name_ar,h.unit,h.operation_snapshot,m.classification,m.location) x;
 return jsonb_build_object('available',true,'rows',rows,'pools',pools,'has_more',jsonb_array_length(rows)=50);
end$$;
revoke all on function private.output_received(uuid,uuid,text),private.output_quality(uuid,uuid),private.output_pending(uuid,uuid),private.output_reconcile(uuid,uuid,jsonb,bigint,text),private.output_lot_guard(),private.output_legacy_quality_guard() from public,anon,authenticated,service_role;
revoke all on function public.receive_manufactured_output(uuid,uuid,jsonb,bigint,uuid),public.manufactured_receiving_read(uuid,integer) from public,anon,service_role;
grant execute on function public.receive_manufactured_output(uuid,uuid,jsonb,bigint,uuid),public.manufactured_receiving_read(uuid,integer) to authenticated;
commit;
