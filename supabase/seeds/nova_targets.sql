-- Repeatable non-production enrichment. Never run on real factory data.
begin;
insert into public.daily_targets(factory_id,order_id,day,target,created_by)
select o.factory_id,o.id,(now() at time zone f.timezone)::date,o.target_quantity,f.created_by from public.production_orders o join public.factories f on f.id=o.factory_id where f.is_demo and f.name='Nova Plastic Pipes Factory' and o.status='active' on conflict(factory_id,order_id,day) do nothing;
insert into public.downtime_reasons(factory_id,parent_id,name,name_ar)
select r.factory_id,r.id,'Bearing failure','تلف المحمل' from public.downtime_reasons r join public.factories f on f.id=r.factory_id where f.is_demo and f.name='Nova Plastic Pipes Factory' and r.name='Mechanical Failure' and not exists(select 1 from public.downtime_reasons x where x.parent_id=r.id and x.name='Bearing failure');
commit;
