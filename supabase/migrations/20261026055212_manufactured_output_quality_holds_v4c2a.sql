-- Batch 1 only: authoritative findings, applied accounting and scoped holds.
-- No new reconciliation movements, activation or physical undo.
begin;
create index output_pending_quality on private.manufactured_output_events(factory_id,output_id,revision)
 where operation='QUALITY' and result->>'accounting_applied'='false';
create index output_work_hold_dependency on private.manufactured_completion_work(factory_id,output_id,group_id);

create or replace function private.output_quality(f uuid,o uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select result from private.manufactured_output_events where factory_id=f and output_id=o and operation='QUALITY'
 and result->>'accounting_applied' is distinct from 'false'
 and revision>coalesce((select max(revision) from private.manufactured_output_events where factory_id=f and output_id=o and operation='CORRECTION'),0)
 order by revision desc limit 1
$$;
create function private.output_finding(f uuid,o uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select result from private.manufactured_output_events where factory_id=f and output_id=o and operation='QUALITY'
 and revision>coalesce((select max(revision) from private.manufactured_output_events where factory_id=f and output_id=o and operation='CORRECTION'),0)
 order by revision desc limit 1
$$;

-- Immutable pending events are cumulative. A later finding/ACK never clears a
-- prior hold. Child output inherits only an affected source/work dependency.
create function private.output_hold_rows(f uuid)
returns table(output_id uuid,group_id uuid,finished boolean,finding_revision bigint)
language sql stable security definer set search_path='' as $$
 with recursive held(output_id,group_id,finished,finding_revision) as (
 select e.output_id,(g->>'id')::uuid,(g->>'finished')::boolean,e.revision
 from private.manufactured_output_events e cross join lateral jsonb_array_elements(e.result->'holds') g
 where e.factory_id=f and e.operation='QUALITY' and e.result->>'accounting_applied'='false'
 union
 select h.id,(g->>'id')::uuid,jsonb_array_length(g->'missing_operations')=0,r.finding_revision
 from held r join private.manufactured_completion_work w on w.factory_id=f and w.output_id=r.output_id and w.group_id=r.group_id
 join private.manufactured_outputs h on h.factory_id=f and h.item_id=w.item_id
 cross join lateral jsonb_array_elements(coalesce(private.output_quality(f,h.id)->'groups',h.recorded_groups)) g
 ) select * from held
$$;
create function private.output_group_held(f uuid,o uuid,g uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.output_hold_rows(f) where output_id=o and group_id=g)
$$;
create function private.output_work_held(f uuid,i uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.manufactured_completion_work w join private.output_hold_rows(f) r on r.output_id=w.output_id and r.group_id=w.group_id where w.factory_id=f and w.item_id=i)
$$;
create function private.output_source_held(f uuid,e uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.manufactured_outputs h join private.output_hold_rows(f) r on r.output_id=h.id and r.finished where h.factory_id=f and h.entry_id=e)
$$;
create function private.output_pool_held(f uuid,p uuid,u text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.finished_goods_sources s where s.factory_id=f and s.product_id=p and s.unit=u and s.quantity_credited>s.quantity_identified and private.output_source_held(f,s.entry_id))
$$;
-- Actual balances/reservations are never rewritten. Assigned held reservations
-- overlap held stock; subtract only unassigned and usable-source commitments.
create function private.output_stock_free(f uuid,p uuid,u text) returns numeric language sql stable security definer set search_path='' as $$
 select greatest(coalesce((select quantity from private.finished_goods_unattributed where factory_id=f and product_id=p and unit=u),0)*case when private.output_pool_held(f,p,u) then 0 else 1 end
 +coalesce((select sum(s.quantity_available-private.source_reserved(f,s.id)) from public.finished_goods_sources s where s.factory_id=f and s.product_id=p and s.unit=u and not private.output_source_held(f,s.entry_id)),0)
 -greatest(coalesce((select reserved from public.finished_goods_balances where factory_id=f and product_id=p and unit=u),0)
 -coalesce((select sum(r.quantity) from public.finished_goods_source_reservations r join public.finished_goods_sources s on s.factory_id=r.factory_id and s.id=r.source_id where s.factory_id=f and s.product_id=p and s.unit=u),0),0),0)
$$;
create function private.output_accounting(f uuid,o uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('finding_revision',private.output_finding(f,o)->>'revision',
 'applied_revision',private.output_quality(f,o)->>'revision','applied',private.output_quality(f,o),
 'pending',exists(select 1 from private.manufactured_output_events where factory_id=f and output_id=o and operation='QUALITY' and result->>'accounting_applied'='false'),
 'held_groups',coalesce((select jsonb_agg(distinct group_id) from private.output_hold_rows(f) where output_id=o),'[]'),
 'blockers',coalesce(private.output_finding(f,o)->'blockers','[]'))
$$;

create function private.output_apply_or_hold(f uuid,o uuid,groups jsonb,rev bigint,reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare applied jsonb;g jsonb;n jsonb;holds jsonb:='[]';block text;begin
 applied:=private.output_quality(f,o);
 if exists(select 1 from private.manufactured_output_events where factory_id=f and output_id=o and operation='QUALITY' and result->>'accounting_applied'='false')
 then block:='output_pending_reconciliation';
 elsif exists(select 1 from private.manufactured_outputs h where h.factory_id=f and h.id=o and private.output_work_held(f,h.item_id)) then block:='output_parent_held';
 else
  begin
   perform private.output_reconcile(f,o,groups,rev,reason);
  exception when raise_exception then
   -- Only these existing, expected physical blockers become pending. The
   -- exception subtransaction rolls back every attempted compensating write.
   if sqlerrm not in ('output_reconciliation_required','output_stock_unavailable','output_group_identity_change') then raise;end if;
   block:=sqlerrm;
  end;
 end if;
 if block is null then return jsonb_build_object('accounting_applied',true,'applied_quality_revision',rev::text,'reconciliation_pending',false,'holds','[]'::jsonb,'blockers','[]'::jsonb);end if;
 for g in select value from jsonb_array_elements(applied->'groups') loop
  select value into n from jsonb_array_elements(groups) where value->>'id'=g->>'id';
  if n is null or (n->>'quantity')::numeric<(g->>'quantity')::numeric or (n->>'released')::numeric<(g->>'released')::numeric
   or n->'missing_operations' is distinct from g->'missing_operations' or n->>'restriction' is distinct from g->>'restriction' then
   holds:=holds||jsonb_build_array(jsonb_build_object('id',g->>'id','finished',jsonb_array_length(g->'missing_operations')=0,
    'quantity',g->>'quantity','scope','SOURCE_GROUP','reason','quality_reconciliation_pending'));
  end if;
 end loop;
 return jsonb_build_object('accounting_applied',false,'applied_quality_revision',applied->>'revision','reconciliation_pending',true,'holds',holds,'blockers',jsonb_build_array(block));
end$$;

do $patch$ declare b text;needle text;begin
 b:=pg_get_functiondef('private.manufactured_output_command(uuid,text,uuid,jsonb,bigint,uuid)'::regprocedure);
 b:=replace(b,'movement public.finished_goods_movements;','application jsonb;movement public.finished_goods_movements;');
 needle:='if exists(select 1 from private.manufactured_output_events where factory_id=f and output_id=h.id and operation=''DISPOSITION'') then raise exception ''output_reconciliation_required'';end if;';
 if position(needle in b)=0 then raise exception 'Quality disposition contract changed';end if;
 b:=replace(b,needle,'-- Allocation blocks accounting, never an authoritative finding.');
 needle:='perform private.output_reconcile(f,h.id,groups,rev,p->>''reason'');';
 if position(needle in b)=0 then raise exception 'Quality reconciliation contract changed';end if;
 b:=replace(b,needle,'application:=private.output_apply_or_hold(f,h.id,groups,rev,p->>''reason'');');
 needle:='''requires_production_approval'',false);';
 if position(needle in b)=0 then raise exception 'Quality result contract changed';end if;
 b:=replace(b,needle,'''requires_production_approval'',false)||application;');
 needle:='select ev.result into quality from private.manufactured_output_events ev where factory_id=f and output_id=h.id and operation=''QUALITY'' and revision>coalesce((select max(c.revision) from private.manufactured_output_events c where c.output_id=h.id and c.operation=''CORRECTION''),0) order by revision desc limit 1;';
 if position(needle in b)=0 then raise exception 'Applied Quality contract changed';end if;
 b:=replace(b,needle,'quality:=private.output_quality(f,h.id);');
 needle:='elsif op=''DISPOSITION'' then';
 b:=replace(b,needle,needle||' if private.output_group_held(f,h.id,(p->>''group_id'')::uuid) then raise exception ''output_quality_hold'';end if;');
 execute b;
 b:=pg_get_functiondef('private.apply_manufactured_output_correction(uuid,jsonb,uuid)'::regprocedure);
 needle:='perform private.production_correction_authorize(f,true);';
 if position(needle in b)=0 then raise exception 'Correction authority contract changed';end if;
 execute replace(b,needle,needle||' perform private.fulfillment_lock(f); if exists(select 1 from private.manufactured_output_events ev where ev.factory_id=f and ev.output_id=h.id and ev.operation=''QUALITY'' and ev.result->>''accounting_applied''=''false'') or exists(select 1 from private.output_hold_rows(f) hr where hr.output_id=h.id) then raise exception ''output_quality_hold'';end if;');
 -- All guards below serialize against publication through the existing
 -- structure lock. No new reverse lock acquisition (structure -> factory).
 b:=pg_get_functiondef('public.plan_manufactured_completion(uuid,uuid,jsonb,bigint,uuid)'::regprocedure);
 needle:='q:=(payload->>''quantity'')::numeric;choice:=payload->>''choice'';';
 if position(needle in b)=0 then raise exception 'Completion allocation contract changed';end if;
 execute replace(b,needle,'if private.output_group_held(factory,h.id,(payload->>''group_id'')::uuid) then raise exception ''output_quality_hold'';end if;'||needle);
 b:=pg_get_functiondef('private.output_material_guard()'::regprocedure);
 needle:='if tg_op=''INSERT'' then';
 b:=replace(b,needle,'perform private.fulfillment_lock(new.factory_id); if exists(select 1 from private.manufactured_output_lots x where x.factory_id=new.factory_id and x.lot_id=new.lot_id and private.output_group_held(new.factory_id,x.output_id,x.group_id)) and (tg_op=''INSERT'' or new.status in (''ISSUED'',''RECEIVED'')) then raise exception ''output_quality_hold'';end if; '||needle);execute b;
 b:=pg_get_functiondef('private.output_work_guard()'::regprocedure);
 needle:='if w.item_id is null then return new;end if;';
 b:=replace(b,needle,needle||' perform private.fulfillment_lock(new.factory_id); if new.status=''active'' and old.status<>''active'' and private.output_work_held(new.factory_id,new.id) then raise exception ''output_quality_hold'';end if;');execute b;
 b:=pg_get_functiondef('private.output_recovery_validate(uuid,jsonb)'::regprocedure);
 needle:='select * into w from private.manufactured_completion_work';
 if position(needle in b)=0 then raise exception 'Recovery contract changed';end if;
 execute replace(b,needle,'perform private.fulfillment_lock(f); if private.output_work_held(f,(p->>''item'')::uuid) then raise exception ''output_quality_hold'';end if; '||needle);
 b:=pg_get_functiondef('public.receive_manufactured_output(uuid,uuid,jsonb,bigint,uuid)'::regprocedure);
 needle:='qa:=private.output_quality(factory,target);';
 if position(needle in b)=0 then raise exception 'Receipt contract changed';end if;
 execute replace(b,needle,'if private.output_group_held(factory,target,(payload->>''group_id'')::uuid) then raise exception ''output_quality_hold'';end if;'||needle);
 b:=pg_get_functiondef('private.output_lot_guard()'::regprocedure);
 needle:='if (to_jsonb(new)-''updated_at'')';
 if position(needle in b)=0 then raise exception 'Lot guard contract changed';end if;
 execute replace(b,needle,'perform private.fulfillment_lock(new.factory_id); if (new.quantity_available<old.quantity_available or new.warehouse_quantity<old.warehouse_quantity) and exists(select 1 from private.manufactured_output_lots x where x.factory_id=new.factory_id and x.lot_id=new.id and private.output_group_held(new.factory_id,x.output_id,x.group_id)) then raise exception ''output_quality_hold'';end if; '||needle);
 b:=pg_get_functiondef('private.source_assign_reservation(uuid,uuid,jsonb)'::regprocedure);
 needle:='select * into line';b:=replace(b,needle,'perform private.fulfillment_lock(f); '||needle);
 needle:='if src.id is null or src.product_id';
 b:=replace(b,needle,'if private.output_source_held(f,src.entry_id) then raise exception ''output_quality_hold'';end if; '||needle);execute b;
 b:=pg_get_functiondef('private.source_movement()'::regprocedure);
 needle:='if pick->>''source_id'' is null then';
 b:=replace(b,needle,needle||' if private.output_pool_held(new.factory_id,new.product_id,new.unit) then raise exception ''output_quality_hold'';end if;');
 needle:='if src.id is null or src.product_id';
 b:=replace(b,needle,'if private.output_source_held(new.factory_id,src.entry_id) then raise exception ''output_quality_hold'';end if; '||needle);
 needle:='-- Old clients can still use pooled stock, but cannot silently pick an identified batch.';
 if position(needle in b)=0 then raise exception 'Pooled stock contract changed';end if;
 b:=replace(b,needle,needle||E'\n if private.output_pool_held(new.factory_id,new.product_id,new.unit) then raise exception ''output_quality_hold'';end if;');execute b;
 b:=pg_get_functiondef('private.reserve_finished(uuid,uuid,numeric)'::regprocedure);
 needle:='update public.finished_goods_balances set reserved=reserved+q';
 if position(needle in b)=0 then raise exception 'Reservation contract changed';end if;
 execute replace(b,needle,'perform private.fulfillment_lock(f); if q>0 and q>private.output_stock_free(f,ln.product_id,ln.unit) then raise exception ''output_quality_hold'';end if; '||needle);
 b:=pg_get_functiondef('private.allocate_sales_line(uuid,uuid)'::regprocedure);
 needle:='take:=least(need,stock);';
 if position(needle in b)=0 then raise exception 'Sales allocation contract changed';end if;
 execute replace(b,needle,'stock:=least(stock,private.output_stock_free(f,l.product_id,l.unit)); '||needle);
 -- External/opening receipt accounting stays untouched. Its existing optional
 -- auto-reservation must skip held supply rather than abort a valid receipt.
 b:=pg_get_functiondef('private.reserve_received_stock(uuid,uuid,text)'::regprocedure);
 needle:='perform private.reserve_finished(f,l.id,least(need,free));';
 if position(needle in b)=0 then raise exception 'Received stock reservation contract changed';end if;
 execute replace(b,needle,'free:=least(free,private.output_stock_free(f,p,u)); '||needle);
end $patch$;

-- Accounting forecasts exclude held pending receipts/work. Actual received
-- demand and physical balances retain their original immutable movement basis.
do $patch$ declare b text;needle text;begin
 b:=pg_get_functiondef('private.output_pending(uuid,uuid)'::regprocedure);
 needle:='and jsonb_array_length(g->''missing_operations'')=0';
 if position(needle in b)=0 then raise exception 'Pending forecast contract changed';end if;
 execute replace(b,needle,needle||' and not private.output_group_held(f,h.id,(g->>''id'')::uuid)');
 b:=pg_get_functiondef('private.output_future_remaining(uuid,uuid,boolean)'::regprocedure);
 needle:='if own_need is null then return 0;end if;';
 if position(needle in b)=0 then raise exception 'Future forecast contract changed';end if;
 execute replace(b,needle,'if private.output_work_held(f,i) then return 0;end if; '||needle);
 b:=pg_get_functiondef('private.finished_inventory_projection(uuid,uuid)'::regprocedure);
 needle:='coalesce(b.on_hand-b.reserved,0)';
 if position(needle in b)=0 then raise exception 'Stock projection contract changed';end if;
 execute replace(b,needle,'private.output_stock_free(f,k.product_id,k.unit)');
 b:=pg_get_functiondef('public.manufactured_output_read(uuid,text,uuid,integer)'::regprocedure);
 needle:='''quality'',(select ev.result';
 if position(needle in b)=0 then raise exception 'Quality reader contract changed';end if;
 execute replace(b,needle,'''accounting'',private.output_accounting(factory,h.id), '||needle);
 b:=pg_get_functiondef('public.manufactured_receiving_read(uuid,integer)'::regprocedure);
 needle:='''revision'',(select max(revision)';
 if position(needle in b)=0 then raise exception 'Receiving reader contract changed';end if;
 b:=replace(b,needle,'''finding'',private.output_finding(factory,h.id),''accounting'',private.output_accounting(factory,h.id), '||needle);
 b:=replace(b,'''received'',private.output_received', '''held'',private.output_group_held(factory,h.id,(g->>''id'')::uuid),''received'',private.output_received');
 needle:='''quantity'',l.warehouse_quantity::text';
 b:=replace(b,needle,needle||',''held'',private.output_group_held(factory,h.id,m.group_id),''usable'',case when private.output_group_held(factory,h.id,m.group_id) then ''0'' else l.warehouse_quantity::text end');execute b;
 b:=pg_get_functiondef('public.manufactured_completion_read(uuid,integer)'::regprocedure);
 needle:='l.warehouse_quantity::text stored,';
 if position(needle in b)=0 then raise exception 'Completion reader contract changed';end if;
 b:=replace(b,needle,'private.output_accounting(factory,h.id) accounting,private.output_group_held(factory,h.id,m.group_id) held,'||needle);
 needle:='(greatest(l.warehouse_quantity-coalesce(a.reserved,0),0))::text available_to_allocate';
 if position(needle in b)=0 then raise exception 'Completion availability contract changed';end if;
 b:=replace(b,needle,'(case when private.output_group_held(factory,h.id,m.group_id) then 0 else greatest(l.warehouse_quantity-coalesce(a.reserved,0),0) end)::text available_to_allocate');
 needle:='private.output_work_revision_state(factory,w.item_id) decision_revision,';
 if position(needle in b)=0 then raise exception 'Work reader contract changed';end if;
 execute replace(b,needle,needle||'private.output_work_held(factory,w.item_id) held,');
 b:=pg_get_functiondef('public.production_start_readiness(uuid,uuid)'::regprocedure);
 needle:='''evaluated_at'',stamp,''queue_ready''';
 if position(needle in b)=0 then raise exception 'Start readiness reader contract changed';end if;
 execute replace(b,needle,'''quality_hold'',private.output_work_held(factory,item),'||needle);
 b:=pg_get_functiondef('private.warehouse_inventory_rows(uuid)'::regprocedure);
 needle:='coalesce(x.on_hand-x.reserved,0) end available';
 if position(needle in b)=0 then raise exception 'Warehouse availability contract changed';end if;
 execute replace(b,needle,'private.output_stock_free(f,p.id,k.unit) end available');
 b:=pg_get_functiondef('public.warehouse_page(uuid,integer)'::regprocedure);
 needle:='''available'',x.on_hand-x.reserved';
 if position(needle in b)=0 then raise exception 'Warehouse balance reader contract changed';end if;
 execute replace(b,needle,'''available'',private.output_stock_free(factory,x.product_id,x.unit)');
 b:=pg_get_functiondef('public.finished_source_stock(uuid,uuid,text,uuid,uuid,integer,uuid)'::regprocedure);
 needle:='(s.quantity_available-private.source_reserved(factory,s.id,sales_line))::text as selectable';
 if position(needle in b)=0 then raise exception 'Source availability contract changed';end if;
 b:=replace(b,needle,'private.output_source_held(factory,s.entry_id) held,(case when private.output_source_held(factory,s.entry_id) then 0 else s.quantity_available-private.source_reserved(factory,s.id,sales_line) end)::text as selectable');
 execute replace(b,'''unattributed'',coalesce(','''unattributed_held'',private.output_pool_held(factory,product,unit),''unattributed_selectable'',case when private.output_pool_held(factory,product,unit) then ''0'' else coalesce((select quantity::text from private.finished_goods_unattributed where factory_id=factory and product_id=product and finished_goods_unattributed.unit=finished_source_stock.unit),''0'') end,''unattributed'',coalesce(');
end $patch$;

-- New helpers are not an exposed API. Existing authenticated commands retain
-- their exact ACLs and factory/person/package checks. Private RLS unchanged.
do $$declare r record;begin
 for r in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private'
 and p.proname in ('output_finding','output_hold_rows','output_group_held','output_work_held','output_source_held','output_pool_held','output_stock_free','output_accounting','output_apply_or_hold') loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',r.sig);
 end loop;
end$$;
commit;
