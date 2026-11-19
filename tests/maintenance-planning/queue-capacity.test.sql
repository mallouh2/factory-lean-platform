-- Existing integrated local cluster only; all synthetic rows and history roll back.
begin;
do $$declare x jsonb;f uuid;i uuid;m uuid;l uuid;a timestamptz:=now()+interval '3 days';b timestamptz;begin
 x:=mp_test.fixture('group4-queue-capacity');f:=(x->>'factory')::uuid;i:=(x->>'item')::uuid;m:=(x->>'machine')::uuid;l:=(x->>'line')::uuid;
 insert into public.production_routing_steps(factory_id,product_id,kind,work_center_id,position)values(f,(x->>'product')::uuid,'work_center',m,1);
 if exists(select 1 from private.maintenance_occupancy(f,l,null,m,null,null,true,now())where id=i)then raise exception 'Unscheduled route claimed equipment';end if;
 if private.maintenance_capacity_conflict(f,l,null,m,a,a+interval '1 hour')is not null then raise exception 'Queue falsely blocks capacity';end if;
 perform public.plan_product_item(f,i,l,a);select expected_finish into b from public.production_orders where id=i;
 if private.maintenance_capacity_conflict(f,l,null,m,a,b)is null then raise exception 'Planned overlap lost';end if;
 if private.maintenance_capacity_conflict(f,l,null,m,b,b+interval '1 hour')is not null then raise exception 'Half-open boundary lost';end if;
 if not exists(select 1 from private.maintenance_occupancy(f,l,null,m,null,null,true,now())where id=i and starts=a and ends=b and not unknown)then raise exception 'Finite planned interval changed';end if;
 raise notice '5 maintenance queue capacity assertions passed';
end$$;
rollback;
