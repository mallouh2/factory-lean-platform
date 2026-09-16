-- Testing project silmfbpjyepalnggwulp only. Restore fixtures after interrupted HTTP tests.
-- Uses the same audited application commands; preserves all operational history.
begin;
select set_config('request.jwt.claim.sub','c94a7c99-7833-51da-aa7c-1edd2592ce71',true);
set local role authenticated;
do $$declare f uuid:='bab9b5da-d78d-4be7-b6d4-bb6afc388c3a';manager_role uuid;r record;begin
 if not exists(select 1 from public.factories where id=f and is_demo) then raise exception 'Testing demo factory required';end if;
 select id into manager_role from public.roles where factory_id=f and name='Factory Manager';
 perform public.manage_member(f,'c83a705c-ff0d-585d-9f55-e3edbe9c2bdf',manager_role,'approved');
 perform public.set_support_by_email(f,'support@nova.example.test',manager_role,'disabled',null);
 for r in select * from public.work_centers where factory_id=f and code like 'QA-%' and type<>'production_cell' and not archived loop
  if r.status<>'idle' then perform public.change_status(f,r.id,'idle');end if;
  if r.order_id is not null then perform public.save_record(f,'orders',r.order_id,'{"status":"completed"}');end if;
  perform public.save_record(f,'centers',r.id,'{"archived":true}');
 end loop;
 for r in select id from public.work_centers where factory_id=f and code like 'QA-%' and type='production_cell' and not archived loop
  perform public.save_record(f,'centers',r.id,'{"archived":true}');
 end loop;
 for r in select id from public.production_lines where factory_id=f and code like 'QA-%' and not archived loop
  perform public.save_record(f,'lines',r.id,'{"archived":true}');
 end loop;
 for r in select id from public.areas where factory_id=f and name like 'QA-%' and not archived loop
  perform public.save_record(f,'factory',r.id,'{"archived":true}');
 end loop;
end$$;
commit;
select 'PASS: test manager restored, support disabled, QA hierarchy archived with history retained' as result;
