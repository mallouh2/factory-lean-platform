begin;
create function private.planning_unstarted_reversible(f uuid,i uuid) returns boolean
language sql stable set search_path='' as $$
 select exists(select 1 from public.production_orders o where o.factory_id=f and o.id=i and o.status='planned'
 and o.actual_start is null and o.actual_finish is null and o.produced_quantity=0
 and not exists(select 1 from public.production_entries e where e.factory_id=f and e.order_id=i)
 and not exists(select 1 from public.material_requests r where r.factory_id=f and r.production_item_id=i and r.status in ('ISSUED','RECEIVED'))
 and not private.output_work_held(f,i))
$$;
do $migration$declare b text;n text;begin
 b:=pg_get_functiondef('private.record_plan_revision()'::regprocedure);
 n:='if old.status <> ''planned'' or old.produced_quantity > 0 or';
 if position(n in b)=0 or position('(old.start_time is not null and old.start_time <= now())' in b)=0 then raise exception 'Replanning trigger contract changed';end if;
 b:=replace(b,n,'if old.status <> ''planned'' or old.produced_quantity > 0 or');
 b:=replace(b,'(old.start_time is not null and old.start_time <= now())','old.actual_start is not null or old.actual_finish is not null');
 n:='if not old.planning_ever_scheduled then';
 b:=replace(b,n,'if old.planning_ever_scheduled and not private.planning_unstarted_reversible(old.factory_id,old.id) then raise exception ''planning_material_committed'';end if; '||n);
 execute b;
 b:=pg_get_functiondef('private.plan_product_item_without_maintenance(uuid,uuid,uuid,timestamptz)'::regprocedure);
 n:='if target.status<>''planned'' or target.produced_quantity>0 then';
 if position(n in b)=0 then raise exception 'Protected Planning command changed';end if;
 b:=replace(b,n,'if target.status<>''planned'' or target.produced_quantity>0 or target.actual_start is not null or target.actual_finish is not null then');
 -- Existing protected wrapper acquires factory/structure locks before item locks.
 -- The history trigger rechecks material/execution state for all real revisions.
 execute b;
end$migration$;
revoke all on function private.planning_unstarted_reversible(uuid,uuid) from public,anon,authenticated,service_role;
commit;
