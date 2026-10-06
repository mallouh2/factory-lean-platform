-- Read-only acceptance of the rebuilt dataset. Run inside the runner's guarded transaction.
create temp table demo_verification(label text) on commit drop;
create function pg_temp.verify_demo(ok boolean,label text) returns void language plpgsql as $$begin
 if ok is distinct from true then raise exception 'DEMO verification: %',label;end if;
 insert into demo_verification values(label);end$$;
do $$declare f uuid:='bab9b5da-d78d-4be7-b6d4-bb6afc388c3a';s uuid;p uuid;begin
 perform pg_temp.verify_demo((select count(*)=6 from public.products where factory_id=f),'six fresh Products');
 perform pg_temp.verify_demo((select count(*)=5 from public.materials where factory_id=f),'five fresh materials');
 perform pg_temp.verify_demo((select count(*)=3 from public.bom_items where factory_id=f) and (select sum(quantity)=1 from public.bom_items where factory_id=f),'one explicit 80/18/2 recipe');
 perform pg_temp.verify_demo((select count(*)=3 from public.products where factory_id=f and code in ('P-032','P-050','P-063') and unit_weight_kg=case code when 'P-032' then .30 when 'P-050' then .60 else .95 end),'pipe weight snapshots');
 perform pg_temp.verify_demo(not exists(select 1 from public.work_center_capabilities k join public.products p on p.id=k.product_id join public.work_centers c on c.id=k.work_center_id where k.factory_id=f and p.code='P-063' and c.line_id='a0c244e3-9d87-52d9-8b12-1a278f6e86d6'),'P-063 restricted to LINE 2');
 perform pg_temp.verify_demo((select count(*)=22 from public.sales_orders where factory_id=f),'17 historical and five current Sales orders');
 select id into s from public.sales_orders where factory_id=f and customer_reference='DEMO-S1 fully available';
 perform pg_temp.verify_demo((select sum(r.quantity)=300 from public.finished_goods_reservations r join public.sales_order_lines l on l.id=r.line_id where l.order_id=s) and not exists(select 1 from public.production_requests r join public.sales_order_lines l on l.id=r.sales_order_line_id where l.order_id=s),'S1 all Finished reserve / no Production');
 select id into s from public.sales_orders where factory_id=f and customer_reference='DEMO-S2 partial stock';
 perform pg_temp.verify_demo((select sum(r.quantity)=400 from public.finished_goods_reservations r join public.sales_order_lines l on l.id=r.line_id where l.order_id=s),'S2 exactly400 reserved');
 perform pg_temp.verify_demo((select o.target_quantity=600 and o.start_time is null and o.actual_start is null from public.production_orders o join public.production_requests r on r.id=o.request_id join public.sales_order_lines l on l.id=r.sales_order_line_id where l.order_id=s),'S2 exactly600 Needs Planning');
 select id into s from public.sales_orders where factory_id=f and customer_reference='DEMO-S3 full shortage';
 perform pg_temp.verify_demo((select o.target_quantity=200 and o.start_time is null and o.actual_start is null from public.production_orders o join public.production_requests r on r.id=o.request_id join public.sales_order_lines l on l.id=r.sales_order_line_id where l.order_id=s),'S3 full200 Needs Planning');
 perform pg_temp.verify_demo((select count(*)=16 and count(distinct line_id)=2 and max(actual_finish)-min(actual_start)>interval '26 days' from public.production_orders where factory_id=f and status='completed'),'16 completed jobs across both lines and month');
 perform pg_temp.verify_demo((select count(*)=1 from public.production_orders where factory_id=f and status='active'),'one current active job');
 perform pg_temp.verify_demo((select count(*)=1 from public.production_orders where factory_id=f and planning_locked_at is not null),'one locked future job');
 perform pg_temp.verify_demo((select count(*)>=2 from public.production_plan_revisions where factory_id=f and event='replanned' and reason_code='material_delay'),'historical and current reasoned replan');
 perform pg_temp.verify_demo(not exists(select 1 from public.production_orders where factory_id=f and status='active' group by line_id having count(*)>1),'one active item per line');
 perform pg_temp.verify_demo((select count(*)=32 and max(created_at)-min(created_at)>interval '26 days' from public.production_entries where factory_id=f),'32 historical declarations span month');
 perform pg_temp.verify_demo(not exists(select 1 from public.production_entries where factory_id=f and produced_weight_kg is distinct from (effective_good+effective_unfinished)*weight_kg_per_unit),'mass denominator Good + newly recorded WIP');
 perform pg_temp.verify_demo((select input_quantity=100 and effective_good=60 and effective_scrap=5 and effective_unfinished=35 and effective_scrap_kg=5 from public.production_entries where factory_id=f and input_lot_id is not null),'WIP conservation separate from Scrap kg');
 perform pg_temp.verify_demo((select sum(quantity_available)=35 and sum(warehouse_quantity)=20 from public.unfinished_lots where factory_id=f),'35 WIP total /20stored /15floor');
 perform pg_temp.verify_demo(not exists(select 1 from public.finished_goods_balances b where b.factory_id=f and
 b.on_hand<>(select coalesce(sum(stock_delta),0) from public.finished_goods_movements m where m.factory_id=f and m.product_id=b.product_id and m.unit=b.unit)),'Finished On Hand reconciles ledger');
 perform pg_temp.verify_demo(not exists(select 1 from public.finished_goods_balances b where b.factory_id=f and
 b.reserved<>(select coalesce(sum(r.quantity),0) from public.finished_goods_reservations r join public.sales_order_lines l on l.id=r.line_id where r.factory_id=f and l.product_id=b.product_id and l.unit=b.unit)),'Finished Reserved reconciles reservations');
 perform pg_temp.verify_demo(not exists(select 1 from public.production_entries e where e.factory_id=f and e.effective_good<>(select received_good from public.finished_goods_entry_receipts where entry_id=e.id)),'each Good credited once');
 perform pg_temp.verify_demo((select count(*)=1 from public.production_receipt_acknowledgments where factory_id=f),'historical Good acknowledgment');
 perform pg_temp.verify_demo(not exists(select 1 from public.finished_goods_movements m join public.sales_order_lines l on l.id=m.sales_line_id join public.sales_orders s on s.id=l.order_id where s.customer_reference like 'DEMO-H%' and m.created_at>(select max(actual_finish) from public.production_orders where factory_id=f and status='completed')),'historical reservations / dispatch retain historical times');
 perform pg_temp.verify_demo((select count(*)=1 from public.material_requests where factory_id=f and status='REQUESTED') and (select count(*)=1 from public.material_requests where factory_id=f and status='ISSUED') and (select count(*)=3 from public.material_requests where factory_id=f and status='RECEIVED'),'material Requested / Issued / Received');
 perform pg_temp.verify_demo((select sum(quantity)=2056 from public.inventory_transactions t join public.materials m on m.id=t.material_id where t.factory_id=f and m.code='RM-HDPE'),'resin2056kg reconciled');
 perform pg_temp.verify_demo((select sum(quantity)=62.6 from public.inventory_transactions t join public.materials m on m.id=t.material_id where t.factory_id=f and m.code='RM-CACO3'),'calcium62.6kg reconciled');
 perform pg_temp.verify_demo((select sum(quantity)=46.4 from public.inventory_transactions t join public.materials m on m.id=t.material_id where t.factory_id=f and m.code='RM-BLACK'),'masterbatch46.4kg reconciled');
 perform pg_temp.verify_demo((select count(*)=11 and count(distinct status)=8 from public.purchase_requisitions where factory_id=f),'all8 Purchasing states across11 requests');
 perform pg_temp.verify_demo((select count(*)=1 from public.purchase_requisitions where factory_id=f and status='RECEIVED' and material_id is not null and receipt_movement_id is not null) and
 (select count(*)=1 from public.purchase_requisitions where factory_id=f and status='RECEIVED' and material_id is null and product_id is null and receipt_movement_id is null),'stock vs direct receipts');
 perform pg_temp.verify_demo((select count(*)=2 from public.suppliers where factory_id=f) and (select count(*)=1 from public.purchase_requisitions where factory_id=f and supplier_text='Demo on-site calibration workshop' and supplier_id is null),'two suppliers / request-local typed supplier');
 perform pg_temp.verify_demo((select count(*)=8 and count(distinct status)=6 and count(distinct source)=2 from public.maintenance_requests where factory_id=f),'Maintenance six states and both origins');
 perform pg_temp.verify_demo((select count(*)=1 from public.maintenance_requests where factory_id=f and verification_result='REWORK_REQUIRED' and status='IN_PROGRESS'),'failed verification retained');
 perform pg_temp.verify_demo(exists(select 1 from public.maintenance_requests where factory_id=f and source='DOWNTIME' and status='VERIFIED') and exists(select 1 from public.maintenance_requests where factory_id=f and source='MANUAL' and status='COMPLETED' and completed_at<current_date-interval '10 days'),'historical manual and downtime-linked completed work');
 perform pg_temp.verify_demo((select count(*)=21 from public.production_loss_estimates where factory_id=f and result->>'readiness'='READY'),'21 complete derived loss estimates');
 perform pg_temp.verify_demo((select (e.result->>'raw_stop_minutes')::numeric=20 and (e.result->>'effective_loss_minutes')::numeric=4 from public.production_loss_estimates e join public.downtime_events d on d.id=e.event_id where e.factory_id=f and d.notes like 'DEMO-D2 alternative mitigation%'),'20 physical minutes /4 effective loss with alternative');
 perform pg_temp.verify_demo((select count(*)=1 from public.production_transfers where factory_id=f and ended_at is null) and (select line_id='b932f276-8b3b-5c0f-99ee-ea75062f938f' from public.work_centers where id='301cf73f-2cdf-5bf9-ab4d-1154fec16340'),'OPEN transfer preserves borrower permanent line');
 perform pg_temp.verify_demo((select count(*)=6 and count(*) filter(where verified_at is not null)=4 and count(distinct outcome)=4 from public.lean_initiatives where factory_id=f),'six initiatives /four explicit outcomes');
 perform pg_temp.verify_demo((select count(*)=12 and count(*) filter(where status='CANCELLED' and cancellation_reason is not null)=1 from public.lean_actions where factory_id=f),'12 actions /reasoned cancellation');
 perform pg_temp.verify_demo(not exists(select 1 from public.lean_actions a join public.lean_initiatives i on i.id=a.initiative_id where a.factory_id=f and a.status='COMPLETED' and a.created_at>i.completed_at),'historical actions precede initiative completion');
 perform pg_temp.verify_demo((select count(*)=1 from public.lean_saved_comparisons where factory_id=f),'independent manual comparison');
 perform pg_temp.verify_demo((select count(*)>=2 from private.lean_occurrences o join public.lean_problem_settings p on p.factory_id=o.factory_id and p.mechanism=o.mechanism and p.machine_id=o.machine_id and p.cause_id=o.cause_id join public.lean_initiatives i on i.problem_id=p.id where o.factory_id=f and i.outcome='IMPROVED' and o.occurred_at>i.verified_at and o.occurred_at<=i.verified_at+interval '30 days'),'recurrence after Improved');
 perform pg_temp.verify_demo((select count(*)=1 from public.lean_scrap_events where factory_id=f and reviewed_at is null),'cause pending stays outside formal recurrence');
 perform pg_temp.verify_demo(not exists(select 1 from public.production_requests where factory_id=f and request_type='STOCK_REPLENISHMENT'),'no automatic Min/Max Production');
 perform pg_temp.verify_demo(not exists(select 1 from public.audit_logs where factory_id=f and actor_id is null),'fresh relevant audit actors');
end$$;
select jsonb_build_object('checks',(select count(*) from demo_verification),
 'counts',jsonb_build_object('products',(select count(*) from public.products),'materials',(select count(*) from public.materials),
 'sales',(select count(*) from public.sales_orders),'product_items',(select count(*) from public.production_orders),'production_entries',(select count(*) from public.production_entries),
 'material_requests',(select count(*) from public.material_requests),'purchases',(select count(*) from public.purchase_requisitions),'maintenance',(select count(*) from public.maintenance_requests),
 'downtime',(select count(*) from public.downtime_events),'saved_loss',(select count(*) from public.production_loss_estimates),'initiatives',(select count(*) from public.lean_initiatives),
 'actions',(select count(*) from public.lean_actions),'audit',(select count(*) from public.audit_logs)),
 'history',(select jsonb_build_object('from',min(actual_start),'to',max(actual_finish)) from public.production_orders where status='completed'),
 'warehouse',(select jsonb_agg(value) from private.warehouse_inventory_rows('bab9b5da-d78d-4be7-b6d4-bb6afc388c3a') value)) as verified;
