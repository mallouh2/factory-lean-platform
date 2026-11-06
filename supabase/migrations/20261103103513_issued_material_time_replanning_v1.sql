begin;
create function private.planning_issued_time_change_safe(f uuid,i uuid)returns boolean language sql stable security definer set search_path='' as $$
select exists(select 1 from public.production_orders o join private.manufactured_completion_work w on w.factory_id=o.factory_id and w.item_id=o.id
join public.material_requests r on r.factory_id=w.factory_id and r.id=w.material_request_id and r.production_item_id=o.id and r.lot_id=w.lot_id
join public.unfinished_lots l on l.factory_id=w.factory_id and l.id=w.lot_id
join public.unfinished_movements m on m.factory_id=r.factory_id and m.id=r.movement_id and m.lot_id=l.id
where o.factory_id=f and o.id=i and o.status='planned'and o.actual_start is null and o.actual_finish is null and o.produced_quantity=0
and not exists(select 1 from public.production_entries e where e.factory_id=f and e.order_id=i)
and not private.output_work_held(f,i)and not private.output_work_retired(f,i)and w.choice='COMPLETE'
and r.status='ISSUED'and r.quantity=w.quantity and m.kind='warehouse_issue'and m.location_delta=-w.quantity
and l.quantity_available-l.warehouse_quantity>=w.quantity and private.output_work_consumed(f,i)=0
and not exists(select 1 from public.material_requests extra where extra.factory_id=f and extra.production_item_id=i and extra.status in('ISSUED','RECEIVED')and extra.id<>r.id))
$$;
do $migration$declare b text;n text;begin
b:=pg_get_functiondef('private.record_plan_revision()'::regprocedure);
n:='if old.planning_ever_scheduled and not private.planning_unstarted_reversible(old.factory_id,old.id) then raise exception ''planning_material_committed'';end if;';
if position(n in b)=0 then raise exception 'Planning history contract changed';end if;
b:=replace(b,n,$new$if old.planning_ever_scheduled and not private.planning_unstarted_reversible(old.factory_id,old.id)
 and not(coalesce(old.line_id is not null and new.line_id=old.line_id and private.planning_issued_time_change_safe(old.factory_id,old.id),false))then
 if private.output_work_held(old.factory_id,old.id)then raise exception 'output_quality_hold';end if;
 if exists(select 1 from public.production_entries where factory_id=old.factory_id and order_id=old.id)then raise exception 'planning_already_started';end if;
 raise exception 'planning_material_custody';end if;$new$);execute b;end$migration$;
revoke all on function private.planning_issued_time_change_safe(uuid,uuid)from public,anon,authenticated;
commit;
