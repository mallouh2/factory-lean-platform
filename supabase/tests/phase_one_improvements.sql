-- Acceptance fixture: all changes roll back; no changes to real factory records.
begin;
insert into auth.users(id,email,email_confirmed_at) values
('42000000-0000-4000-8000-000000000001','improvement-owner@example.test',now()),
('42000000-0000-4000-8000-000000000002','improvement-a@example.test',now()),
('42000000-0000-4000-8000-000000000003','improvement-b@example.test',now());
select set_config('request.jwt.claim.sub','42000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select set_config('test.factory',public.create_factory('Improvement acceptance','Asia/Qatar','Testing')::text,true);
select set_config('test.line',public.save_record(current_setting('test.factory')::uuid,'lines',null,'{"name":"Test line","code":"TEST"}')::text,true);
select set_config('test.product',public.save_record(current_setting('test.factory')::uuid,'products',null,'{"name":"Intermediate test","code":"TEST-P","stage":"semi_finished"}')::text,true);
select set_config('test.order',public.save_record(current_setting('test.factory')::uuid,'orders',null,jsonb_build_object('code','TEST-O','product_id',current_setting('test.product'),'target_quantity',100,'status','active'))::text,true);
select set_config('test.original',public.save_record(current_setting('test.factory')::uuid,'centers',null,jsonb_build_object('name','Original machine','code','ORIG','order_id',current_setting('test.order'),'production_speed',120))::text,true);
select set_config('test.alternative',public.save_record(current_setting('test.factory')::uuid,'centers',null,'{"name":"Alternative machine","code":"ALT"}')::text,true);
select set_config('test.reason',(select id::text from public.downtime_reasons where factory_id=current_setting('test.factory')::uuid and name='Mechanical Failure'),true);
select public.save_line_layout(current_setting('test.factory')::uuid,(select structure_version from public.factories where id=current_setting('test.factory')::uuid),jsonb_build_array(jsonb_build_object('id',current_setting('test.original'),'line_id',current_setting('test.line'),'position',0,'dependency_mode','blocking','impact_scope','whole_line','buffer_minutes',0),jsonb_build_object('id',current_setting('test.alternative'),'line_id',null,'position',0,'dependency_mode','independent','impact_scope','none','buffer_minutes',0)));
select public.configure_center_links(current_setting('test.factory')::uuid,current_setting('test.original')::uuid,array[current_setting('test.alternative')::uuid],'[]');
select public.change_status(current_setting('test.factory')::uuid,current_setting('test.original')::uuid,'running');
select public.change_status(current_setting('test.factory')::uuid,current_setting('test.original')::uuid,'stopped',current_setting('test.reason')::uuid,notes=>'Pump failure');
select public.transfer_production(current_setting('test.factory')::uuid,current_setting('test.original')::uuid,current_setting('test.alternative')::uuid,'Use spare cooling machine');
do $$begin
 if (select status from public.work_centers where id=current_setting('test.alternative')::uuid)<>'running' then raise exception 'Alternative not running';end if;
 if not exists(select 1 from public.downtime_events where work_center_id=current_setting('test.original')::uuid and impact_scope_at_start='whole_line' and blocking_at_start and order_id=current_setting('test.order')::uuid) then raise exception 'Context not preserved';end if;
 begin perform public.save_line_layout(current_setting('test.factory')::uuid,0,'[]');raise exception 'Stale layout accepted';exception when others then if sqlerrm<>'layout_conflict' then raise;end if;end;
 begin perform public.change_status(current_setting('test.factory')::uuid,current_setting('test.alternative')::uuid,'maintenance',current_setting('test.reason')::uuid);raise exception 'Maintenance state accepted';exception when others then if sqlerrm<>'maintenance_is_stop_reason' then raise;end if;end;
end$$;
select public.change_status(current_setting('test.factory')::uuid,current_setting('test.alternative')::uuid,'stopped',current_setting('test.reason')::uuid,notes=>'Alternative interrupted');
do $$begin if not exists(select 1 from public.production_transfers where original_id=current_setting('test.original')::uuid and ended_at is not null and original_returned_at is null) then raise exception 'Alternative interruption not recorded';end if;end$$;
select public.change_status(current_setting('test.factory')::uuid,current_setting('test.original')::uuid,'running');
do $$begin
 if not exists(select 1 from public.production_transfers where original_id=current_setting('test.original')::uuid and original_returned_at is not null and ended_at is not null) then raise exception 'Transfer history not closed';end if;
 if (select count(*) from public.status_events where work_center_id=current_setting('test.original')::uuid)<>3 then raise exception 'Status history lost';end if;
 if not exists(select 1 from public.audit_logs where entity='production_transfers' and action='INSERT') then raise exception 'Transfer audit missing';end if;
end$$;
reset role;
insert into public.memberships(factory_id,user_id,display_name,role_id,status) select current_setting('test.factory')::uuid,u.id,u.name,r.id,'approved' from (values('42000000-0000-4000-8000-000000000002'::uuid,'Engineer A'),('42000000-0000-4000-8000-000000000003'::uuid,'Engineer B')) u(id,name) join public.roles r on r.factory_id=current_setting('test.factory')::uuid and r.name='Production Engineer';
set local role authenticated;
select public.set_user_permissions(current_setting('test.factory')::uuid,'42000000-0000-4000-8000-000000000002','[{"module":"factory","action":"view"},{"module":"centers","action":"view"},{"module":"centers","action":"edit"}]');
select public.set_user_permissions(current_setting('test.factory')::uuid,'42000000-0000-4000-8000-000000000003','[{"module":"factory","action":"view"}]');
reset role;
select set_config('request.jwt.claim.sub','42000000-0000-4000-8000-000000000002',true);
set local role authenticated;
do $$begin
 if not public.can_access(current_setting('test.factory')::uuid,'centers','edit') then raise exception 'Person A missing grant';end if;
 if exists(select 1 from public.work_centers where factory_id<>current_setting('test.factory')::uuid) then raise exception 'Cross tenant read';end if;
 begin perform public.open_platform_factory(current_setting('test.factory')::uuid);raise exception 'Employee elevated to platform';exception when insufficient_privilege then null;end;
end$$;
reset role;
select set_config('request.jwt.claim.sub','42000000-0000-4000-8000-000000000003',true);
set local role authenticated;
do $$begin
 if public.can_access(current_setting('test.factory')::uuid,'centers','view') then raise exception 'Job title granted access';end if;
 if exists(select 1 from public.work_centers) then raise exception 'Unpermitted machine read';end if;
end$$;
reset role;
select set_config('request.jwt.claim.sub','c94a7c99-7833-51da-aa7c-1edd2592ce71',true);
set local role authenticated;
do $$begin if not (public.factory_snapshot()->>'platformAdmin')::boolean then raise exception 'Demo admin is not platform admin';end if;end$$;
select public.open_platform_factory(current_setting('test.factory')::uuid);
do $$begin if public.factory_snapshot(current_setting('test.factory')::uuid)->'factory'->>'name'<>'Improvement acceptance' then raise exception 'Platform could not open second factory';end if;end$$;
select set_config('test.platform_factory',public.create_factory('Platform-created factory','UTC','Test')::text,true);
do $$begin if not public.can_access(current_setting('test.platform_factory')::uuid,'centers','create') then raise exception 'Platform cannot configure new factory';end if;end$$;
reset role;
select set_config('request.jwt.claim.sub','42000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $$begin
 if public.can_access(current_setting('test.platform_factory')::uuid,'centers','view') then raise exception 'Factory admin crossed tenant';end if;
 if exists(select 1 from public.factories where id=current_setting('test.platform_factory')::uuid) then raise exception 'Factory admin read foreign factory';end if;
end$$;
rollback;
select 'PASS: factory, line, machine layout, scope, transfer, return, audit, person permissions, platform creation and tenant isolation' as result;
