begin;
do $$begin if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55499 or current_database()<>'factory_lean_quality_local' then raise exception 'Disposable local QA only';end if;end$$;
do $$declare x jsonb;f uuid;p uuid;l uuid;pr uuid;i uuid;stamp timestamptz;v record;actual numeric;begin
 select c.x into x from planning_drawer_test.context c;f:=(x->>'factory')::uuid;p:=(x#>>'{printing,product}')::uuid;l:=(x#>>'{printing,line}')::uuid;
 perform set_config('request.jwt.claim.sub',x->>'owner',true);stamp:=date_trunc('day',clock_timestamp())+interval '2 days 09:00';
 for v in select * from(values(10::numeric,2),(10.1::numeric,3),(0.1::numeric,2),(20::numeric,3))a(quantity,minutes)loop
 pr:=public.create_production_request(f,'Rounding boundary','normal',null,'Exact prospective duration',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',v.quantity,'unit','meter')));
 select id into i from public.production_orders where request_id=pr;
 perform public.plan_product_item(f,i,l,stamp);
 select extract(epoch from(expected_finish-start_time))/60 into actual from public.production_orders where id=i;
 if actual<>v.minutes then raise exception 'Duration %: expected %, got %',v.quantity,v.minutes,actual;end if;
 raise notice 'PASS protected scheduling duration quantity=% minutes=%',v.quantity,actual;stamp:=stamp+interval '1 hour';
 end loop;
 -- Earlier successful schedule remains immutable history, not silently recomputed.
 select extract(epoch from(expected_finish-start_time))/60 into actual from public.production_orders where id=(x#>>'{extrusion,item}')::uuid;
 if actual<>3 then raise exception 'Existing saved interval was rewritten';end if;
 raise notice 'PASS earlier saved3min interval retained';
 -- A rollback-only confirmed reservation fixture tests the unchanged SQL blocker.
 -- No activation gate is changed, and no reservation survives this test.
 stamp:=date_trunc('day',clock_timestamp())+interval '2 days 15:00';
 pr:=public.create_maintenance_request(f,jsonb_build_object('work_center_id',x#>>'{printing,machine}','title','Rollback-only capacity fixture','priority','NORMAL','maintenance_kind','PLANNED','estimated_duration_minutes',10),gen_random_uuid());
 insert into public.maintenance_schedules(factory_id,maintenance_request_id,state,planned_start,planned_end,confirmed_by,confirmed_at)
 values(f,pr,'CONFIRMED',stamp,stamp+interval '10 minutes',auth.uid(),clock_timestamp())returning id into i;
 insert into public.maintenance_schedule_resources(factory_id,schedule_id,resource_kind,line_id,impact_reason,evidence)values(f,i,'LINE',l,'Rollback-only configured line capacity','{}'::jsonb);
 pr:=public.create_production_request(f,'Blocked local scheduling','normal',null,'Maintenance overlap regression',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',10,'unit','meter')));
 select id into i from public.production_orders where request_id=pr;
 begin perform public.plan_product_item(f,i,l,stamp);raise exception 'Expected protected capacity rejection';exception when others then if sqlerrm<>'maintenance_capacity_reserved' then raise;end if;end;
 if exists(select 1 from public.production_orders where id=i and line_id is not null)then raise exception 'Rejected schedule persisted';end if;
 raise notice 'PASS maintenance reservation remains a protected SQL blocker/no persisted schedule';
end$$;
rollback;
