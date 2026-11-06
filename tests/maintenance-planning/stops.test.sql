begin;
create temporary table assertions(label text);
create temporary table prepared(x jsonb);
create function pg_temp.ok(value boolean,label text) returns void language plpgsql as $$begin
 if value is distinct from true then raise exception 'Actual-stop assertion failed: %',label;end if;insert into assertions values(label);end$$;
create function pg_temp.fails(statement text,message text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then
 if sqlerrm=message then insert into assertions values(message);return;end if;raise exception 'Expected %, got %',message,sqlerrm;end;
 raise exception 'Expected rejection %',message;end$$;
create function pg_temp.abort_link() returns trigger language plpgsql as $$begin raise exception 'forced_link_failure';end$$;
do $$declare x jsonb;f uuid;m uuid;r uuid;sid uuid;a timestamptz;begin
 perform quality_test.make_fixture('maintenance-stock-preservation','meter',.35,10,5);
 perform pg_temp.ok(exists(select 1 from public.finished_goods_sources) and exists(select 1 from public.unfinished_lots),
 'nonempty Good/source/WIP conservation fixture uses existing production command');
 x:=mp_test.fixture('actual-stop');f:=(x->>'factory')::uuid;m:=(x->>'machine')::uuid;r:=(x->>'request')::uuid;
 perform pg_temp.ok(not(select enabled from private.maintenance_planning_activation),'gate initially disabled');
 perform pg_temp.ok(jsonb_array_length(public.maintenance_stop_context(f,m)->'eligible')=0,'inactive selector empty');
 update private.maintenance_planning_activation set enabled=true;
 a:=clock_timestamp()+interval '1 second';sid:=mp_test.plan(x,a,a+interval '30 minutes');perform mp_test.command(f,r,'confirm','{}',1,gen_random_uuid());perform public.change_status(f,m,'running');
 perform pg_temp.fails(format('select public.stop_machine_for_maintenance(%L,%L,''planned'',null,''inspection'','''',%L,2,2,gen_random_uuid())',f,m,sid),'maintenance_stop_window');
 insert into prepared values(x||jsonb_build_object('schedule',sid));
end$$;
select pg_sleep(1.1);
do $$declare x jsonb;y jsonb;f uuid;m uuid;r uuid;sid uuid;e uuid;e2 uuid;retry uuid;v uuid;reason uuid;package uuid;
 initial jsonb;after_data jsonb;loss jsonb;started timestamptz;a timestamptz;begin
 x:=(select prepared.x from prepared);f:=(x->>'factory')::uuid;m:=(x->>'machine')::uuid;r:=(x->>'request')::uuid;sid:=(x->>'schedule')::uuid;a:=(select planned_start from public.maintenance_schedules where id=sid);
 select jsonb_build_object('orders',(select jsonb_agg(to_jsonb(o) order by to_jsonb(o)::text) from public.production_orders o where factory_id=f),
 'entries',(select jsonb_agg(to_jsonb(o) order by to_jsonb(o)::text) from public.production_entries o),
 'finished',(select jsonb_agg(to_jsonb(o) order by to_jsonb(o)::text) from public.finished_goods_balances o),
 'sources',(select jsonb_agg(to_jsonb(o) order by to_jsonb(o)::text) from public.finished_goods_sources o),
 'wip',(select jsonb_agg(to_jsonb(o) order by to_jsonb(o)::text) from public.unfinished_lots o),
 'stock',(select jsonb_agg(to_jsonb(o) order by to_jsonb(o)::text) from public.inventory_transactions o where factory_id=f)) into initial;

 perform pg_temp.ok(jsonb_array_length(public.maintenance_stop_context(f,m)->'eligible')=1,'approved exact machine eligible');
 perform pg_temp.fails(format('select public.stop_machine_for_maintenance(%L,%L,''planned'',null,''inspection'','''',%L,1,2,gen_random_uuid())',f,m,sid),'maintenance_stop_conflict');
 perform pg_temp.fails(format('select public.stop_machine_for_maintenance(%L,%L,''planned'',null,''inspection'','''',%L,2,2,gen_random_uuid())',f,x->>'other_machine',sid),'maintenance_stop_scope');
 perform pg_temp.ok((select count(*)=0 from public.downtime_events where factory_id=f),'invalid association creates no physical event');
 create trigger local_forced_link_failure after insert on public.maintenance_stop_associations for each row execute function pg_temp.abort_link();
 retry:=gen_random_uuid();
 perform pg_temp.fails(format('select public.stop_machine_for_maintenance(%L,%L,''planned'',null,''inspection'','''',%L,2,2,%L)',f,m,sid,retry),'forced_link_failure');
 perform pg_temp.ok((select status='running' from public.work_centers where id=m),'failed append rolls physical status back');
 perform pg_temp.ok((select count(*)=0 from public.downtime_events where factory_id=f),'failed append rolls downtime back');
 perform pg_temp.ok(not exists(select 1 from public.maintenance_commands where factory_id=f and request_id=retry),'failed append rolls retry ledger back');
 drop trigger local_forced_link_failure on public.maintenance_stop_associations;
 e:=public.stop_machine_for_maintenance(f,m,'planned',null,'inspection','',sid,2,2,retry);
 perform pg_temp.ok(e=public.stop_machine_for_maintenance(f,m,'planned',null,'inspection','',sid,2,2,retry),'atomic retry returns same physical event');
 perform pg_temp.ok((select count(*)=1 from public.downtime_events where factory_id=f),'one authoritative downtime');
 perform pg_temp.fails(format('select public.stop_machine_for_maintenance(%L,%L,''planned'',null,''inspection'',''Changed retry'',%L,2,2,%L)',f,m,sid,retry),'request_conflict');
 perform pg_temp.ok((select count(*)=1 from public.maintenance_stop_associations where factory_id=f),'retry has one immutable link');
 perform pg_temp.ok((select source='MANUAL' and downtime_id is null from public.maintenance_requests where id=r),'request origin unchanged');
 perform pg_temp.ok((select approval_revision=2 and approval->>'state'='CONFIRMED' and relationship='PLANNED_MAINTENANCE' and jsonb_array_length(resources)=2 from public.maintenance_stop_associations where event_id=e),'frozen approval and machine/line scope');
 perform pg_temp.fails(format('select public.stop_machine_for_maintenance(%L,%L,''planned'',null,''inspection'','''',%L,2,2,gen_random_uuid())',f,m,sid),'status_unchanged');
 perform pg_temp.fails(format('select mp_test.command(%L,%L,''unschedule'',''{"reason":"Open stop"}'',2,gen_random_uuid())',f,r),'maintenance_active_stop');
 perform pg_temp.fails(format('select mp_test.command(%L,%L,''reschedule'',%L,2,gen_random_uuid())',f,r,jsonb_build_object('start',a+interval '2 days','end',a+interval '2 days 30 minutes','reason','Cannot move open stop')),'maintenance_active_stop');
 perform pg_temp.fails(format('select public.change_maintenance_request(%L,%L,''cancel'',''{"cancellation_note":"Open stop"}'',2,gen_random_uuid())',f,r),'maintenance_active_stop');
 perform pg_temp.fails(format('select public.correct_maintenance_stop(%L,%L,%L,2,''UNLINK'',''Open stop'',1,gen_random_uuid())',f,e,sid),'maintenance_active_stop');
 perform pg_temp.ok(private.maintenance_capacity_conflict(f,(x->>'line')::uuid,null,m,a+interval '2 hours',a+interval '3 hours')->>'reason'='maintenance_capacity_reserved','open physical stop extends capacity beyond future approved end');
 perform set_config('request.jwt.claim.sub',x->>'worker',true);
 perform public.change_maintenance_request(f,r,'start','{}',2,gen_random_uuid());
 perform public.change_maintenance_request(f,r,'complete','{"work_note":"Local work done"}',3,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 perform pg_temp.fails(format('select public.change_maintenance_request(%L,%L,''verify'',''{"result":"RESOLVED","verification_note":"Open stop"}'',4,gen_random_uuid())',f,r),'maintenance_active_stop');
 perform public.change_maintenance_request(f,r,'verify','{"result":"REWORK_REQUIRED","verification_note":"Repeat physical inspection"}',4,gen_random_uuid());
 perform public.change_status(f,m,'idle');
 select started_at into started from public.downtime_events where id=e;
 e2:=public.stop_machine_for_maintenance(f,m,'planned',null,'inspection','Second genuine stop',sid,3,5,gen_random_uuid());
 perform pg_temp.ok((select count(*)=2 from public.maintenance_stop_associations where schedule_id=sid),'multiple genuine events per schedule');
 perform public.change_status(f,m,'idle');
 -- Saved evidence is a disposable fixture, never synthesized by the application.
 insert into public.production_loss_estimates(factory_id,event_id,model_version,result,recorded_by) values(f,e,1,'{"status":"READY","fixture":"reviewed"}',(x->>'owner')::uuid);
 select to_jsonb(z) into loss from public.production_loss_estimates z where event_id=e;
 perform pg_temp.fails(format('select public.correct_maintenance_stop(%L,%L,%L,2,''UNLINK'','''',1,gen_random_uuid())',f,e,sid),'maintenance_note');
 retry:=gen_random_uuid();v:=public.correct_maintenance_stop(f,e,sid,2,'UNLINK','Wrong operation association',1,retry);
 perform pg_temp.ok(v=public.correct_maintenance_stop(f,e,sid,2,'UNLINK','Wrong operation association',1,retry),'correction retry appends once');
 perform pg_temp.ok((select operation='UNLINK' and jsonb_array_length(reviewed_evidence)=1 and previous_id is not null from public.maintenance_stop_associations where id=v),'supersession references reviewed estimate and previous link');
 perform pg_temp.ok((select to_jsonb(z)=loss from public.production_loss_estimates z where event_id=e),'historical saved estimate bytes preserved');
 perform pg_temp.ok((select started_at=started and ended_at is not null from public.downtime_events where id=e),'downtime timestamps preserved');
 perform pg_temp.fails(format('update public.maintenance_stop_associations set reason=''Changed'' where id=%L',v),'maintenance_stop_immutable');
 perform pg_temp.fails(format('delete from public.maintenance_stop_associations where id=%L',v),'maintenance_stop_immutable');
 perform pg_temp.ok(jsonb_array_length(public.maintenance_stop_context(f,null,r)->'current')=1,'unlink removes only that current association');
 perform pg_temp.ok((public.maintenance_stop_context(f,null,r)->>'history_total')::integer=3,'all links/unlinks visible in history');
 perform pg_temp.fails(format('select public.correct_maintenance_stop(%L,%L,%L,2,''LINK'',''Stale editor'',1,gen_random_uuid())',f,e,sid),'maintenance_stop_conflict');
 perform public.correct_maintenance_stop(f,e,sid,2,'LINK','Correct closed association',2,gen_random_uuid());
 -- Genuine emergency paths still invalidate readiness, not the physical event.
 insert into public.downtime_reasons(factory_id,name) values(f,'Local breakdown') returning id into reason;
 e:=public.stop_machine_for_maintenance(f,m,'unplanned',reason,null,'Explicit contextual breakdown',sid,3,5,gen_random_uuid());
 perform pg_temp.ok((select state='INVALIDATED' from public.maintenance_schedules where id=sid),'unplanned association preserves emergency invalidation');
 perform pg_temp.ok((select relationship='CONTEXTUAL_UNPLANNED' and approval_revision=2 from public.maintenance_stop_associations where event_id=e),'unplanned stop has contextual relationship, original approval');
 perform public.change_status(f,m,'idle');
 perform set_config('request.jwt.claim.sub',x->>'worker',true);
 perform public.change_maintenance_request(f,r,'complete','{"work_note":"Retested"}',5,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 perform public.change_maintenance_request(f,r,'verify','{"result":"RESOLVED","verification_note":"Independent check"}',6,gen_random_uuid());
 perform pg_temp.ok((select state='RELEASED' from public.maintenance_schedules where id=sid),'closed physical stops allow normal independent release');
 perform pg_temp.ok((select status='idle' from public.work_centers where id=m),'verification never automatically restarts');
 select jsonb_build_object('orders',(select jsonb_agg(to_jsonb(o) order by to_jsonb(o)::text) from public.production_orders o where factory_id=f),
 'entries',(select jsonb_agg(to_jsonb(o) order by to_jsonb(o)::text) from public.production_entries o),
 'finished',(select jsonb_agg(to_jsonb(o) order by to_jsonb(o)::text) from public.finished_goods_balances o),
 'sources',(select jsonb_agg(to_jsonb(o) order by to_jsonb(o)::text) from public.finished_goods_sources o),
 'wip',(select jsonb_agg(to_jsonb(o) order by to_jsonb(o)::text) from public.unfinished_lots o),
 'stock',(select jsonb_agg(to_jsonb(o) order by to_jsonb(o)::text) from public.inventory_transactions o where factory_id=f)) into after_data;
 perform pg_temp.ok(initial=after_data,'Good/Scrap/WIP/inventory and production items unchanged');
 y:=mp_test.fixture('other-stop-factory');e2:=public.stop_machine((y->>'factory')::uuid,(y->>'machine')::uuid,'planned',null,'inspection','Other local factory');perform set_config('request.jwt.claim.sub',x->>'owner',true);
 perform pg_temp.fails(format('select public.correct_maintenance_stop(%L,%L,%L,2,''LINK'',''Wrong factory'',1,gen_random_uuid())',f,e,y->>'request'),'maintenance_missing');
 perform pg_temp.fails(format('select public.correct_maintenance_stop(%L,%L,%L,2,''LINK'',''Cross-factory event'',0,gen_random_uuid())',f,e2,sid),'maintenance_downtime');
 perform pg_temp.fails(format('select public.stop_machine_for_maintenance(%L,%L,''planned'',null,''inspection'','''',%L,2,2,gen_random_uuid())',y->>'factory',m,sid),'permission_denied');
 perform set_config('request.jwt.claim.sub',x->>'viewer',true);
 perform pg_temp.fails(format('select public.correct_maintenance_stop(%L,%L,%L,2,''UNLINK'',''Denied'',1,gen_random_uuid())',f,e,sid),'permission_denied');
 perform pg_temp.fails(format('select public.stop_machine_for_maintenance(%L,%L,''planned'',null,''inspection'','''',%L,3,4,gen_random_uuid())',f,m,sid),'permission_denied');
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 package:=public.save_permission_package(f,gen_random_uuid(),' {"name":"Local stop engineers"}','[{"module":"maintenance","action":"edit"},{"module":"downtime","action":"edit"},{"module":"downtime","action":"view"}]',0);
 perform public.set_member_permission_packages(f,(x->>'viewer')::uuid,array[package],'{}');
 perform set_config('request.jwt.claim.sub',x->>'viewer',true);
 perform public.correct_maintenance_stop(f,e,sid,2,'UNLINK','Package-only engineering authority',1,gen_random_uuid());
 perform pg_temp.ok((select count(*)=0 from public.user_permissions where factory_id=f and user_id=(x->>'viewer')::uuid and action='edit'),'package grants work without direct edit grants');
 perform pg_temp.ok(not has_table_privilege('authenticated','public.maintenance_stop_associations','INSERT'),'ordinary direct ledger inserts forbidden');
 perform pg_temp.ok(not has_function_privilege('authenticated','private.maintenance_append_stop(uuid,uuid,uuid,integer,text,text,uuid)','EXECUTE'),'private append helper not callable');
 update private.maintenance_planning_activation set enabled=false;
end$$;
select count(*)||' actual-stop assertions passed' from assertions;
rollback;
