-- Disposable local baseline, before M1: prove initial capture does not certify history.
do $$begin if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Local only';end if;end$$;
create schema shift_test;
create table shift_test.baseline(x jsonb,digest text);
create function shift_test.digest(f uuid) returns text language sql as $$
 select md5(jsonb_build_array(
 (select coalesce(jsonb_agg(to_jsonb(t) order by id),'[]') from public.production_orders t where factory_id=f),
 (select coalesce(jsonb_agg(to_jsonb(t) order by id),'[]') from public.production_entries t where factory_id=f),
 (select coalesce(jsonb_agg(to_jsonb(t) order by product_id,unit),'[]') from public.finished_goods_balances t where factory_id=f),
 (select coalesce(jsonb_agg(to_jsonb(t) order by id),'[]') from public.work_centers t where factory_id=f),
 (select coalesce(jsonb_agg(to_jsonb(t) order by id),'[]') from public.unfinished_lots t where factory_id=f),
 (select coalesce(jsonb_agg(to_jsonb(t) order by id),'[]') from public.maintenance_requests t where factory_id=f)
 )::text)
$$;
do $$declare x jsonb;f uuid;s timestamptz;begin
 x:=mp_test.fixture('m1-upgrade');f:=(x->>'factory')::uuid;s:=clock_timestamp();
 update public.factories set timezone='UTC' where id=f;
 perform public.configure_production_shift(f,'Underway baseline','وردية قائمة',(s-interval '1 hour')::time,(s+interval '1 hour')::time);
 insert into shift_test.baseline values(x,shift_test.digest(f));
end$$;
