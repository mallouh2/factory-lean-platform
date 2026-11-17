const fs=require('fs'),l=require('./local.cjs'),x=JSON.parse(fs.readFileSync(l.root+'/runtime.json')).context;
const test=`begin;select set_config('request.jwt.claim.sub',${l.q(x.owner)},true);
create temporary table checks(label text);
create function pg_temp.ok(v boolean,n text)returns void language plpgsql as $$begin if v is distinct from true then raise exception 'Assertion failed: %',n;end if;insert into checks values(n);end$$;
create function pg_temp.denied(s text,n text)returns void language plpgsql as $$begin begin execute s;exception when others then if sqlerrm=n or sqlstate=n then insert into checks values('Denied: '||n);return;end if;raise;end;raise exception 'Expected denial: %',n;end$$;
do $$declare c jsonb;f uuid:=${l.q(x.factory)};m uuid;optional uuid;reason uuid;r record;rev integer;event uuid;begin
c:=qa472.make_case('group2-transition',2);m:=(c->>'machine')::uuid;
perform pg_temp.ok((select status='idle'from public.work_centers where id=m),'Prepared machine remains Idle');
perform pg_temp.denied(format('select public.change_status(%L,%L,%L)',f,m,'running'),'execution_no_active_work');
perform pg_temp.denied(format('select public.set_line_pause(%L,%L,true,%L)',f,c->>'line','cleaning'),'execution_line_idle');
perform pg_temp.denied(format('select public.set_line_pause(%L,%L,false)',f,c->>'line'),'execution_line_idle');
insert into public.work_centers(factory_id,line_id,category_id,name,code,status,dependency_mode,impact_scope)
select f,(c->>'line')::uuid,category_id,'Group2 optional','G2-OPTIONAL','idle','non_blocking','none'from public.work_centers where id=m returning id into optional;
for r in select *from public.material_requests where production_item_id=(c->>'item')::uuid loop
perform public.production_material_action(f,'RESERVE',jsonb_build_object('id',r.id,'revision',r.revision,'quantity',r.quantity::text),gen_random_uuid());select revision into rev from public.material_requests where id=r.id;
perform public.production_material_action(f,'ISSUE',jsonb_build_object('id',r.id,'revision',rev,'quantity',r.quantity::text,'physical_confirmation',true),gen_random_uuid());end loop;
select id into reason from public.downtime_reasons where factory_id=f and parent_id is null and private.current_downtime_reason(f,id) limit 1;
event:=public.stop_machine_with_impact(f,m,'unplanned',reason,null,true,'Synthetic pre-start fault');
perform pg_temp.denied(format('select public.start_product_item(%L,%L)',f,c->>'item'),'execution_machine_stopped');
perform pg_temp.ok(not(private.execution_machine_readiness(f,(c->>'item')::uuid,(c->>'line')::uuid,(select product_id from public.production_orders where id=(c->>'item')::uuid))->>'ready')::boolean,'Readiness exposes physical blocker');
perform public.change_status(f,m,'idle');perform public.start_product_item(f,(c->>'item')::uuid);
perform pg_temp.ok((select count(*)=2 from public.work_centers where line_id=(c->>'line')::uuid and status='running'and order_id=(c->>'item')::uuid),'Start atomically assigns and runs participating machines');
perform pg_temp.denied(format('select public.start_product_item(%L,%L)',f,c->>'item'),'execution_already_started');
perform pg_temp.denied(format('select public.stop_machine_with_impact(%L,%L,%L,%L,null,false)',f,m,'unplanned',reason),'machine_impact_conflict');
perform pg_temp.denied(format('select public.stop_machine_with_impact(%L,%L,%L,%L,null,true)',f,optional,'unplanned',reason),'machine_impact_conflict');
event:=public.stop_machine_with_impact(f,optional,'unplanned',reason,null,false,'Synthetic noncritical stop');
perform pg_temp.ok((select not blocking_at_start and order_id=(c->>'item')::uuid from public.downtime_events where id=event),'Noncritical stop captures validated no-impact and actual work');
perform pg_temp.ok((select status='active'from public.production_orders where id=(c->>'item')::uuid),'Noncritical stop does not finish or pause work');
event:=public.stop_machine_with_impact(f,m,'unplanned',reason,null,true,'Synthetic critical stop');
perform pg_temp.ok((select blocking_at_start and impact_scope_at_start='whole_line'from public.downtime_events where id=event),'Critical stop captures validated blocking scope');
perform pg_temp.ok((select status='active'from public.production_orders where id=(c->>'item')::uuid),'Legitimate critical stop preserves active execution identity');
perform public.change_status(f,m,'running');
perform public.set_line_pause(f,(c->>'line')::uuid,true,'cleaning');
perform pg_temp.ok((select status='idle'from public.work_centers where id=m),'Pause idles current running participant');
perform pg_temp.denied(format('select public.change_status(%L,%L,%L)',f,m,'running'),'line_paused');
perform public.set_line_pause(f,(c->>'line')::uuid,false);
perform pg_temp.ok((select status='running'from public.work_centers where id=m),'Resume restores only pause-idled eligible participant');
perform pg_temp.ok((select status='stopped'from public.work_centers where id=optional),'Resume preserves later/legitimate stop');
perform public.finish_product_item(f,(c->>'item')::uuid);
perform pg_temp.ok((select status='idle'and order_id is null from public.work_centers where id=m),'Finish idles and unassigns work with no next active order');
perform pg_temp.ok((select status='stopped'from public.work_centers where id=optional),'Finish preserves legitimate stopped machine');
perform public.change_status(f,optional,'idle');
perform pg_temp.ok(not exists(select 1 from public.downtime_events where work_center_id=optional and ended_at is null),'Ending downtime without work returns Idle');
perform pg_temp.ok((select count(*)=2 from public.status_events where work_center_id=m and notes='Execution status synchronization'),'Automatic transitions retain explicit status audit');
perform pg_temp.ok(not has_function_privilege('anon','public.stop_machine_with_impact(uuid,uuid,text,uuid,text,boolean,text,jsonb)','execute'),'Anonymous cannot use stop confirmation RPC');
perform pg_temp.ok(not has_function_privilege('authenticated','private.reconcile_execution_machine_status(uuid)','execute'),'Client cannot invoke reconciliation helper directly');
end$$;select jsonb_build_object('assertions',count(*),'labels',jsonb_agg(label))from checks;rollback;`;
fs.writeFileSync(l.out+'/integration.sql',test);const result=JSON.parse(l.sql(test).split('\n').filter(x=>x.startsWith('{')).at(-1));l.save('integration-results',result);console.log('PASS '+result.assertions+' focused SQL transition/integrity assertions');


