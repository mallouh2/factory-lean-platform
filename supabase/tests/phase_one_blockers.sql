-- Focused Phase 1 checks. All fixture records are rolled back.
begin;
insert into auth.users(id,email,email_confirmed_at)
values ('43000000-0000-4000-8000-000000000001','phase-one-blockers@example.test',now());
select set_config('request.jwt.claim.sub','43000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select set_config('test.factory',public.create_factory('Phase 1 blockers','UTC','Testing')::text,true);
select set_config('test.category',(select id::text from public.work_center_categories where factory_id=current_setting('test.factory')::uuid and name='Generic Work Center'),true);
select set_config('test.line_a',public.save_record(current_setting('test.factory')::uuid,'lines',null,'{"name":"Source line","code":"SOURCE"}')::text,true);
select set_config('test.line_b',public.save_record(current_setting('test.factory')::uuid,'lines',null,'{"name":"Spare line","code":"SPARE"}')::text,true);
select set_config('test.product',public.save_record(current_setting('test.factory')::uuid,'products',null,'{"name":"Test product","code":"PHASE1-P","stage":"semi_finished"}')::text,true);
select set_config('test.order',public.save_record(current_setting('test.factory')::uuid,'orders',null,jsonb_build_object('code','PHASE1-O','product_id',current_setting('test.product'),'target_quantity',100,'status','active'))::text,true);
select set_config('test.original',public.save_record(current_setting('test.factory')::uuid,'centers',null,jsonb_build_object('name','Original','code','ORIG','line_id',current_setting('test.line_a'),'category_id',current_setting('test.category'),'order_id',current_setting('test.order')))::text,true);
select set_config('test.alternative',public.save_record(current_setting('test.factory')::uuid,'centers',null,jsonb_build_object('name','Alternative','code','ALT','line_id',current_setting('test.line_b'),'category_id',current_setting('test.category')))::text,true);
select set_config('test.reason',(select id::text from public.downtime_reasons where factory_id=current_setting('test.factory')::uuid and name='Mechanical Failure'),true);
select public.configure_center_capabilities(current_setting('test.factory')::uuid,current_setting('test.original')::uuid,jsonb_build_array(jsonb_build_object('product_id',current_setting('test.product'),'rate',123)));
-- A newer capability value must survive an alternative edit made from an older snapshot.
select public.configure_center_capabilities(current_setting('test.factory')::uuid,current_setting('test.original')::uuid,jsonb_build_array(jsonb_build_object('product_id',current_setting('test.product'),'rate',456)));
select public.configure_center_alternatives(current_setting('test.factory')::uuid,current_setting('test.original')::uuid,array[current_setting('test.alternative')::uuid]);
do $$begin
 if (select rate from public.work_center_capabilities where work_center_id=current_setting('test.original')::uuid and product_id=current_setting('test.product')::uuid)<>456 then raise exception 'Alternative save changed capabilities';end if;
 if not exists(select 1 from public.work_center_alternatives a join public.work_centers o on o.id=a.work_center_id join public.work_centers x on x.id=a.alternative_id where a.work_center_id=current_setting('test.original')::uuid and a.alternative_id=current_setting('test.alternative')::uuid and o.line_id<>x.line_id) then raise exception 'Cross-line alternative missing';end if;
end$$;
select public.change_status(current_setting('test.factory')::uuid,current_setting('test.original')::uuid,'running');
select public.change_status(current_setting('test.factory')::uuid,current_setting('test.original')::uuid,'stopped',current_setting('test.reason')::uuid,notes=>'Original failed');
select public.transfer_production(current_setting('test.factory')::uuid,current_setting('test.original')::uuid,current_setting('test.alternative')::uuid,'Use cross-line spare');
select public.change_status(current_setting('test.factory')::uuid,current_setting('test.alternative')::uuid,'stopped',current_setting('test.reason')::uuid,notes=>'Spare stopped');
do $$begin
 if not exists(select 1 from public.production_transfers where original_id=current_setting('test.original')::uuid and alternative_id=current_setting('test.alternative')::uuid and ended_at is null and original_returned_at is null) then raise exception 'Alternative stop ended transfer';end if;
 if not exists(select 1 from public.work_centers where id=current_setting('test.alternative')::uuid and status='stopped') then raise exception 'Spare physical stop lost';end if;
 if not exists(select 1 from public.work_center_alternatives where work_center_id=current_setting('test.original')::uuid and alternative_id=current_setting('test.alternative')::uuid) then raise exception 'Alternative relationship lost';end if;
end$$;
select public.change_status(current_setting('test.factory')::uuid,current_setting('test.original')::uuid,'running');
do $$begin
 if not exists(select 1 from public.production_transfers where original_id=current_setting('test.original')::uuid and ended_at is not null and original_returned_at is not null) then raise exception 'Original return failed to close transfer';end if;
 if (select rate from public.work_center_capabilities where work_center_id=current_setting('test.original')::uuid and product_id=current_setting('test.product')::uuid)<>456 then raise exception 'Capability changed after transfer';end if;
end$$;
rollback;
select 'PASS: alternative stop preserves transfer; original return closes it; alternative save preserves capabilities and supports cross-line relationship' as result;
