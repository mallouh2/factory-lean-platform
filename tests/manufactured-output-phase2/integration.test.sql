do $$declare x jsonb;f uuid;p jsonb;r uuid:=gen_random_uuid();receipt jsonb;h private.manufactured_outputs;q jsonb;groups jsonb;before_count bigint;k uuid;proposal jsonb;correction jsonb;begin
 select a.x into x from output2_test.fixture a;f:=(x->>'factory')::uuid;
 perform set_config('request.jwt.claim.sub',x->>'owner',false);
 p:=output2_test.payload(x,90,10);
 receipt:=public.record_manufactured_output(f,p,r);
 select * into h from private.manufactured_outputs where factory_id=f and entry_id=(receipt->>'entry_id')::uuid;
 perform late_test.ok(h.quantity=100 and jsonb_array_length(h.recorded_groups)=3,'90 finished + 6/4 unordered unfinished groups');
 perform late_test.ok(not exists(select 1 from public.finished_goods_movements where entry_id=h.entry_id),'no premature stock movement');
 perform late_test.ok(not exists(select 1 from public.unfinished_lots where source_entry_id=h.entry_id),'no unclassified legacy WIP availability');
 perform late_test.ok(public.record_manufactured_output(f,p,r)->>'entry_id'=h.entry_id::text,'same UUID recovers exact recording');
 perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',f,jsonb_set(p,'{output_groups,0,quantity}','"89"'),r),'request_conflict');
 perform late_test.ok((public.manufactured_output_read(f,'status',r)->>'outcome')='COMMITTED','lost response recovery');
 perform late_test.ok((select effective_good=90 and effective_unfinished=10 and original_occurrence_key is not null from public.production_entries where id=h.entry_id),'original shift and quantities frozen');
 select jsonb_agg(value||jsonb_build_object('released',(value->>'quantity'))) into groups from jsonb_array_elements(h.recorded_groups);
 k:=gen_random_uuid();q:=public.manufactured_output_command(f,'QUALITY',h.id,jsonb_build_object('groups',groups,'rejected','0','reason','All inspected'),1,k);
 perform late_test.ok(q->>'revision'='2' and q->>'requires_production_approval'='false','Quality authoritative full release');
 perform late_test.ok(public.manufactured_output_command(f,'QUALITY',h.id,jsonb_build_object('groups',groups,'rejected','0','reason','All inspected'),1,k)=q,'Quality UUID replay');
 perform late_test.fails(format('select public.manufactured_output_command(%L,''QUALITY'',%L,%L,1,%L)',f,h.id,jsonb_build_object('groups',groups,'rejected','0','reason','stale'),gen_random_uuid()),'output_revision');
 perform late_test.ok((public.manufactured_output_read(f,'notifications')->'rows'->0->>'unread')='true','Production notification unread');
 perform public.manufactured_output_command(f,'ACKNOWLEDGE',h.id,'{"quality_revision":2}',2,gen_random_uuid());
 perform late_test.ok((public.manufactured_output_read(f,'notifications')->'rows'->0->>'unread')='false','acknowledge without approval or task completion');
 groups:=jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity','85','released','40','missing_operations','[]'::jsonb),jsonb_build_object('id',gen_random_uuid(),'quantity','10','released','0','missing_operations',jsonb_build_array(x->>'step1')));
 q:=public.manufactured_output_command(f,'QUALITY',h.id,jsonb_build_object('groups',groups,'rejected','5','reason','Damaged material'),3,gen_random_uuid());
 perform late_test.ok(q->>'rejected'='5','partial release and nonrecoverable rejection');
 perform late_test.ok(not exists(select 1 from public.finished_goods_movements where entry_id=h.entry_id),'pre-receipt rejection does not debit stock');
 perform late_test.ok((select good_quantity=90 and effective_good=90 from public.production_entries where id=h.entry_id),'Quality preserves technician entry');
 proposal:=jsonb_build_object('entry',h.entry_id,'good','89','discarded_quantity','0','scrap_kg','0','startup_kg','0','unfinished','10','remaining_work','Complete selected operations','reason','Technician quantity correction','confirm_overproduction',true,'change_shift',false,'expected_revision',0,'allocations','[]'::jsonb);
 correction:=public.production_correction_command(f,'submit',proposal,gen_random_uuid());
 perform late_test.ok((select effective_good=89 from public.production_entries where id=h.entry_id),'existing approved pre-stock correction');
 perform late_test.ok((public.manufactured_output_read(f,'entry',h.entry_id)->'rows'->0->'quality')='null'::jsonb,'correction invalidates old Quality release for reinspection');
 perform late_test.ok((select count(*)=2 from private.manufactured_output_events where output_id=h.id and operation='QUALITY'),'previous Quality decisions immutable');
 perform late_test.ok(not exists(select 1 from public.finished_goods_movements where entry_id=h.entry_id),'correction never manufactures stock');
 perform late_test.ok(not exists(select 1 from private.manufactured_output_context),'transaction context removed');
end$$;
do $$declare x jsonb;f uuid;p jsonb;k uuid;before_count bigint;receipt jsonb;amount numeric;begin
 select a.x into x from output2_test.fixture a;f:=(x->>'factory')::uuid;perform set_config('request.jwt.claim.sub',x->>'owner',false);
 foreach amount in array array[100::numeric,90::numeric,0.1234567890123456789] loop
  p:=output2_test.payload(x,amount,case when amount=90 then 10 when amount<1 then 0.0000000000000000001 else 0 end);
  receipt:=public.record_manufactured_output(f,p,gen_random_uuid());
  perform late_test.ok((select effective_good=(p->>'good')::numeric from public.production_entries where id=(receipt->>'entry_id')::uuid),'exact recording variant');
 end loop;
 p:=output2_test.payload(x,90,10);p:=jsonb_set(p,'{output_groups,1,missing_operations}',jsonb_build_array(x->>'step1',x->>'step1'));
 select count(*) into before_count from public.production_entries where factory_id=f;
 perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',f,p,gen_random_uuid()),'output_operations');
 perform late_test.ok((select count(*) from public.production_entries where factory_id=f)=before_count,'invalid classification rolls recording back');
 perform set_config('request.jwt.claim.sub',x->>'viewer',false);
 perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',f,p,gen_random_uuid()),'42501');
 perform late_test.fails(format('select public.manufactured_output_command(%L,''QUALITY'',%L,''{}'',1,%L)',f,gen_random_uuid(),gen_random_uuid()),'42501');
end$$;
do $$declare x jsonb;f uuid;h private.manufactured_outputs;p jsonb;r jsonb;q jsonb;begin
 select a.x into x from output2_test.fixture a;f:=(x->>'factory')::uuid;
 select * into h from private.manufactured_outputs where factory_id=f and quantity=100 and jsonb_array_length(recorded_groups)=1 limit 1;
 insert into public.user_permissions(factory_id,user_id,module,action) values(f,(x->>'worker')::uuid,'orders','view'),(f,(x->>'worker')::uuid,'orders','edit');
 p:=jsonb_build_object('entry',h.entry_id,'good','99','discarded_quantity','0','scrap_kg','0','startup_kg','0','unfinished','0','remaining_work','','reason','Count correction pending approval','confirm_overproduction',true,'expected_revision',0,'allocations','[]'::jsonb);
 perform set_config('request.jwt.claim.sub',x->>'worker',false);r:=public.production_correction_command(f,'submit',p,gen_random_uuid());
 perform late_test.ok(r->>'status'='PENDING','technician correction stays pending');
 perform late_test.ok((select effective_good=100 from public.production_entries where id=h.entry_id),'pending correction leaves physical output unchanged');
 perform set_config('request.jwt.claim.sub',x->>'owner',false);
 q:=public.manufactured_output_command(f,'QUALITY',h.id,jsonb_build_object('groups',h.recorded_groups,'rejected','0','reason','Inspect while correction is pending'),1,gen_random_uuid());
 perform late_test.fails(format('select public.production_correction_command(%L,''approve'',%L,%L)',f,jsonb_build_object('id',r->>'id'),gen_random_uuid()),'correction_stale');
 perform late_test.ok((select effective_good=100 from public.production_entries where id=h.entry_id),'stale approval cannot overwrite Quality');
end$$;
-- One deterministic legacy operation confirms the still-active path, without
-- reconciling or preserving any pre-existing synthetic balances.
create temporary table legacy_context as select late_test.new_context('legacy-posting-check',3600,false) x;
do $$declare x jsonb;p jsonb;r jsonb;begin
 select l.x into x from legacy_context l;perform set_config('request.jwt.claim.sub',x->>'owner',false);p:=late_test.payload(x,2)||jsonb_build_object('unfinished',4,'remaining_work','Finish printing');
 r:=public.record_lean_production((x->>'factory')::uuid,p,gen_random_uuid());
 perform late_test.ok((select sum(stock_delta)=2 from public.finished_goods_movements where entry_id=(r->>'entry_id')::uuid),'legacy active recording still credits stock once');
 perform late_test.ok(not exists(select 1 from private.manufactured_outputs where entry_id=(r->>'entry_id')::uuid),'legacy entry is not enrolled or backfilled');
end$$;
do $$declare x jsonb;p jsonb;r jsonb;lot uuid;begin
 select l.x into x from legacy_context l;perform set_config('request.jwt.claim.sub',x->>'owner',false);
 select id into lot from public.unfinished_lots where factory_id=(x->>'factory')::uuid;
 p:=output2_test.payload(x,4)||jsonb_build_object('input_lot',lot,'input_quantity',4);
 -- M2 explicitly excludes input-lot processing from ordinary shift recording.
 -- Do not convert legacy synthetic WIP or bypass that contract in Phase 2.
 perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',x->>'factory',p,gen_random_uuid()),'recording_invalid_context');
 perform late_test.ok((select quantity_available=4 from public.unfinished_lots where id=lot),'unsupported ordinary input binding does not consume an existing lot');
 perform late_test.ok((select sum(stock_delta)=2 from public.finished_goods_movements where factory_id=(x->>'factory')::uuid),'unsupported input binding creates no duplicate credit');
end$$;
create temporary table deadline_context as select late_test.new_context('output-deadline',4,false) x;
create function output2_test.delay_declaration() returns trigger language plpgsql as $$begin
 if new.operation='DECLARE' then perform pg_sleep(5);end if;return new;
end$$;
create trigger output2_deadline_delay before insert on private.manufactured_output_events for each row execute function output2_test.delay_declaration();
do $$declare x jsonb;p jsonb;begin
 select d.x into x from deadline_context d;perform set_config('request.jwt.claim.sub',x->>'owner',false);p:=output2_test.payload(x,1);
 perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',x->>'factory',p,gen_random_uuid()),'recording_shift_expired');
 perform late_test.ok(not exists(select 1 from public.production_entries where factory_id=(x->>'factory')::uuid),'enrollment crossing deadline rolls the whole recording back');
end$$;
drop trigger output2_deadline_delay on private.manufactured_output_events;
select count(*) as assertions from late_test.checks;
