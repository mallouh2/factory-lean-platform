do $$begin if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55498 or current_database()<>'factory_lean_quality_local' then raise exception 'Disposable local database required';end if;end$$;
create schema if not exists wh_final_test;
create table if not exists wh_final_test.checks(label text);
create or replace function wh_final_test.ok(value boolean,label text)returns void language plpgsql as $$begin if value is distinct from true then raise exception 'FAIL %',label;end if;insert into wh_final_test.checks values(label);end$$;
create table if not exists wh_final_test.context(x jsonb);
do $$declare x jsonb;f uuid;w jsonb;r jsonb;g jsonb;rev bigint;request uuid:=gen_random_uuid();begin
 x:=output4_test.context('warehouse-final-readers',true);f:=(x->>'factory')::uuid;insert into wh_final_test.context values(x);
 r:=public.manufactured_output_read(f,'notifications');perform wh_final_test.ok(r->>'unread_count'='0' and r->>'total'='0','matching Quality approval has no alert');
 r:=public.warehouse_stored_unfinished(f);perform wh_final_test.ok(r#>>'{rows,0,on_hand}'='10' and r#>>'{rows,0,classification_available}'='true' and jsonb_array_length(r#>'{rows,0,missing_operations}')=2,'WIP classification resolves real configured operations');
 perform wh_final_test.ok(r#>>'{rows,0,available}'='10','stored WIP remains separate and available before allocation');
 w:=output4_test.decision(x,'COMPLETE',10);r:=public.warehouse_stored_unfinished(f);perform wh_final_test.ok(r#>>'{rows,0,reserved}'='10' and r#>>'{rows,0,available}'='0','fully allocated WIP is not made available');
 g:=private.output_finding(f,(x->>'output')::uuid)->'groups';select jsonb_agg(case when jsonb_array_length(v->'missing_operations')=0 then v||'{"quantity":"89","released":"89"}'::jsonb else v end)into g from jsonb_array_elements(g)v;
 select max(revision)into rev from private.manufactured_output_events where output_id=(x->>'output')::uuid;
 perform public.manufactured_output_command(f,'QUALITY',(x->>'output')::uuid,jsonb_build_object('groups',g,'total','100','rejected','1','actual_rejected_kg','.5','reason','Actual observed damage; retain protected stock hold'),rev,request);
 r:=public.manufactured_output_read(f,'notifications');perform wh_final_test.ok(r->>'unread_count'='1','material change produces one unread alert');
 perform public.manufactured_output_read(f,'notifications');perform wh_final_test.ok(not exists(select 1 from private.manufactured_output_events where factory_id=f and operation='ACKNOWLEDGE'),'opening notification list performs no ACK');
 select max(revision)into rev from private.manufactured_output_events where output_id=(x->>'output')::uuid;request:=gen_random_uuid();
 perform public.manufactured_output_command(f,'ACKNOWLEDGE',(x->>'output')::uuid,jsonb_build_object('quality_revision',private.output_notification_revision(f,(x->>'output')::uuid)),rev,request);
 perform public.manufactured_output_command(f,'ACKNOWLEDGE',(x->>'output')::uuid,jsonb_build_object('quality_revision',private.output_notification_revision(f,(x->>'output')::uuid)),rev,request);
 r:=public.manufactured_output_read(f,'notifications');perform wh_final_test.ok(r->>'unread_count'='0' and (select count(*)=1 from private.manufactured_output_events where factory_id=f and operation='ACKNOWLEDGE'),'one actor acknowledgement is idempotent');
 -- Configure only this newly generated disposable unit-test person. No preview
 -- account or existing factory grant is changed by this fixture setup.
 insert into public.user_permissions(factory_id,user_id,module,action)values(f,(x->>'viewer')::uuid,'orders','view');
 perform set_config('request.jwt.claim.sub',x->>'viewer',false);r:=public.manufactured_output_read(f,'notifications');perform wh_final_test.ok(r->>'unread_count'='1','another user retains independent unread state');
 perform late_test.fails(format('select public.warehouse_stored_unfinished(%L)',f),'permission_denied');
 perform set_config('request.jwt.claim.sub',x->>'owner',false);r:=public.warehouse_stored_unfinished(f);perform wh_final_test.ok(r#>>'{rows,0,on_hand}'='10' and r#>>'{rows,0,available}'='0' and r#>>'{rows,0,held}'='true','Quality held WIP has zero eligible availability without erasing stock');
 perform wh_final_test.ok((select effective_good=90 from public.production_entries where id=(select entry_id from private.manufactured_outputs where id=(x->>'output')::uuid)),'reader/ACK never rewrites original Good');
end$$;
select count(*) new_reader_assertions from wh_final_test.checks;
