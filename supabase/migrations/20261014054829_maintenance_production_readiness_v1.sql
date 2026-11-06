-- Local Phase 5C. Preparation may use IDLE; do not require running effective flow.
-- Resource/OPEN ownership are the existing Planning and execution contracts.
create function private.maintenance_execution_readiness(f uuid,i uuid,l uuid,p uuid) returns jsonb
 language plpgsql stable security definer set search_path='' as $$
declare serviced public.work_centers;effective public.work_centers;incoming public.production_transfers;
 outgoing public.production_transfers;own_required boolean;borrow_required boolean;first_machine jsonb;machine jsonb;why text;begin
 for serviced in select distinct c.* from public.maintenance_schedules s
 join public.maintenance_schedule_resources r on r.factory_id=s.factory_id and r.schedule_id=s.id and r.resource_kind='MACHINE'
 join public.work_centers c on c.factory_id=r.factory_id and c.id=r.machine_id
 where s.factory_id=f and s.state='RELEASED' order by c.id loop
 own_required:=exists(select 1 from public.production_routing_steps rs where rs.factory_id=f and rs.product_id=p
 and rs.kind='work_center' and rs.work_center_id=serviced.id) or
 (not serviced.archived and serviced.line_id=l and serviced.dependency_mode in ('blocking','buffer') and serviced.impact_scope<>'none');
 select * into incoming from public.production_transfers t where t.factory_id=f and t.alternative_id=serviced.id and t.ended_at is null;
 borrow_required:=incoming.id is not null and exists(select 1 from public.work_centers original where original.factory_id=f
 and original.id=incoming.original_id and not original.archived and
 ((original.line_id=l and original.dependency_mode in ('blocking','buffer') and original.impact_scope<>'none')
 or exists(select 1 from public.production_routing_steps rs where rs.factory_id=f and rs.product_id=p and rs.kind='work_center' and rs.work_center_id=original.id)));
 if not coalesce(own_required,false) and not coalesce(borrow_required,false) then continue;end if;
 effective:=serviced;why:=null;
 -- The existing current association uses highest event revision, not timestamps.
 if exists(select 1 from public.maintenance_stop_associations a join public.maintenance_schedules s
 on s.factory_id=a.factory_id and s.id=a.schedule_id join public.downtime_events d on d.factory_id=a.factory_id and d.id=a.event_id
 where a.factory_id=f and s.state='RELEASED' and d.work_center_id=serviced.id and d.ended_at is null and a.operation='LINK'
 and not exists(select 1 from public.maintenance_stop_associations n where n.factory_id=f and n.event_id=a.event_id and n.revision>a.revision)) then
 why:='OPEN_LINKED_STOP';
 elsif incoming.id is not null and private.execution_center_order(f,serviced.id,serviced.line_id,serviced.order_id) is distinct from i then why:='TRANSFER_OWNERSHIP';
 elsif own_required then
 select * into outgoing from public.production_transfers t where t.factory_id=f and t.original_id=serviced.id and t.ended_at is null;
 if outgoing.id is not null then
 if outgoing.order_id is distinct from i then why:='TRANSFER_OWNERSHIP';else
 select * into effective from public.work_centers c where c.factory_id=f and c.id=outgoing.alternative_id;
 if effective.id is null or effective.category_id is distinct from serviced.category_id then why:='MACHINE_UNAVAILABLE';end if;
 end if;end if;
 end if;
 if why is null then
 if effective.archived then why:='MACHINE_UNAVAILABLE';
 elsif effective.status not in ('idle','running') or effective.status is null then why:='PHYSICAL_STATUS';end if;
 end if;
 machine:=jsonb_build_object('id',coalesce(effective.id,serviced.id),'code',coalesce(effective.code,serviced.code),
 'name',coalesce(effective.name,serviced.name),'name_ar',coalesce(effective.name_ar,serviced.name_ar),'status',effective.status);
 first_machine:=coalesce(first_machine,machine);
 if why is not null then return jsonb_build_object('applicable',true,'ready',false,'reason',why,'machine',machine);end if;
 end loop;
 return jsonb_build_object('applicable',first_machine is not null,'ready',true,'reason',null,'machine',first_machine);
end$$;

-- Preserve the original command's queue/line/planning/execution semantics, while
-- refreshing actor authority after the established structure lock wait.
alter function public.start_product_item(uuid,uuid) rename to start_product_item_before_readiness;
alter function public.start_product_item_before_readiness(uuid,uuid) set schema private;
revoke all on function private.start_product_item_before_readiness(uuid,uuid) from public,anon,authenticated;
create function public.start_product_item(factory uuid,item uuid) returns uuid
 language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(factory,'orders','edit');
 if current_setting('transaction_isolation') not in ('read committed','read uncommitted') then
 raise exception 'execution_readiness_stale' using errcode='40001';end if;
 perform private.maintenance_planning_lock(factory);
 perform private.require_permission(factory,'orders','edit');
 return private.start_product_item_before_readiness(factory,item);
end$$;

-- Also protects a transition through any other authorized writer. Ordinary
-- planning and finishing never run this check, and it makes no physical writes.
create function private.maintenance_execution_guard() returns trigger
 language plpgsql security definer set search_path='' as $$declare result jsonb;begin
 if new.status<>'active' or old.status='active' then return new;end if;
 perform private.require_permission(new.factory_id,'orders','edit');
 if current_setting('transaction_isolation') not in ('read committed','read uncommitted') then
 raise exception 'execution_readiness_stale' using errcode='40001';end if;
 perform private.maintenance_planning_lock(new.factory_id);
 perform private.require_permission(new.factory_id,'orders','edit');
 result:=private.maintenance_execution_readiness(new.factory_id,new.id,new.line_id,new.product_id);
 if not (result->>'ready')::boolean then raise exception 'execution_physical_not_ready' using errcode='P0001',detail=result::text;end if;
 return new;
end$$;
create trigger maintenance_start_readiness before update of status on public.production_orders
 for each row execute function private.maintenance_execution_guard();

create function public.production_start_readiness(factory uuid,item uuid) returns jsonb
 language plpgsql stable security definer set search_path='' as $$
declare o public.production_orders;physical jsonb;hold jsonb;blocker jsonb;stamp timestamptz;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'orders','view');
 select * into o from public.production_orders where factory_id=factory and id=item;
 if not found then raise exception 'not_found' using errcode='P0002';end if;
 physical:=private.maintenance_execution_readiness(factory,o.id,o.line_id,o.product_id);
 stamp:=clock_timestamp();
 -- This is current maintenance occupancy, not a new duration/calendar engine.
 -- The original Start trigger still checks both plan and intended execution span.
 hold:=private.maintenance_capacity_conflict(factory,o.line_id,o.product_id,null,stamp,stamp+interval '1 microsecond',null,o.id,false);
 if hold is not null then
 select jsonb_build_object('reason','MAINTENANCE_HOLD','machine',jsonb_build_object('id',c.id,'code',c.code,'name',c.name,'name_ar',c.name_ar,'status',c.status))
 into blocker from public.maintenance_schedule_resources r join public.work_centers c on c.factory_id=r.factory_id and c.id=r.machine_id
 where r.factory_id=factory and r.schedule_id=(hold->>'schedule')::uuid and r.resource_kind='MACHINE' order by c.id limit 1;
 end if;
 return jsonb_build_object('factory',factory,'item',item,'physical',physical,'maintenance_block',blocker,
 'evaluated_at',stamp,'queue_ready',coalesce(o.status='planned' and o.actual_start is null and o.actual_finish is null
 and o.start_time is not null and o.expected_finish>o.start_time
 and not exists(select 1 from public.production_orders x where x.factory_id=factory and x.line_id=o.line_id and x.status='active')
 and o.id=(select x.id from public.production_orders x where x.factory_id=factory and x.line_id=o.line_id and x.status='planned'
 and x.actual_start is null and x.actual_finish is null and x.start_time is not null and x.expected_finish>x.start_time order by x.start_time,x.id limit 1),false));
end$$;
revoke all on function private.maintenance_execution_readiness(uuid,uuid,uuid,uuid),private.maintenance_execution_guard() from public,anon,authenticated;
revoke all on function public.start_product_item(uuid,uuid),public.production_start_readiness(uuid,uuid) from public,anon,authenticated;
grant execute on function public.start_product_item(uuid,uuid),public.production_start_readiness(uuid,uuid) to authenticated;
