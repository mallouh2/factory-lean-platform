create table correction_test.context(x jsonb);
create function correction_test.operational() returns text language plpgsql stable as $$
declare tab text;part text;result text:='';begin
 foreach tab in array array['production_orders','production_entries','production_entry_corrections','finished_goods_balances','finished_goods_sources','finished_goods_movements','finished_goods_entry_receipts','finished_goods_reservations','finished_goods_source_reservations','sales_incoming_allocations','quality_rejections','quality_notifications','unfinished_lots','unfinished_movements','lean_scrap_events','lean_saved_comparisons','production_loss_estimates','downtime_events','production_transfers','maintenance_schedules'] loop
  execute format('select md5(coalesce(string_agg(to_jsonb(t)::text,''|'' order by to_jsonb(t)::text),'''')) from public.%I t',tab) into part;result:=result||tab||part;
 end loop;return md5(result);end$$;
create function correction_test.payload(x jsonb,e uuid,g numeric,kg numeric default .25,wip numeric default 0) returns jsonb language sql stable as $$
 select jsonb_build_object('entry',e,'good',g::text,'discarded_quantity','0','scrap_kg',kg::text,'unfinished',wip::text,'remaining_work',case when wip>0 then 'Final processing remains' else '' end,
 'reason','Measured again after checking the record','expected_revision',(select count(*) from public.production_entry_corrections where factory_id=(x->>'factory')::uuid and entry_id=e),
 'allocations',case when g<(select effective_good from public.production_entries where id=e) then jsonb_build_array(jsonb_build_object('source_id',null,'quantity',((select effective_good from public.production_entries where id=e)-g)::text)) else '[]'::jsonb end)
$$;
do $$declare x jsonb;e uuid;e2 uuid;pkg uuid;foreign_context jsonb;foreign_entry uuid;foreign_request jsonb;begin
 x:=late_test.new_context('correction-policy',3600,false);perform set_config('request.jwt.claim.sub',x->>'owner',false);
 e:=(public.record_lean_production((x->>'factory')::uuid,late_test.payload(x,10)||'{"unfinished":2,"remaining_work":"Final processing remains","scrap_kg":0.25}',gen_random_uuid())->>'id')::uuid;
 e2:=(public.record_lean_production((x->>'factory')::uuid,late_test.payload(x,5)||'{"scrap_kg":0.25}',gen_random_uuid())->>'id')::uuid;
 insert into public.user_permissions(factory_id,user_id,module,action) values((x->>'factory')::uuid,(x->>'worker')::uuid,'orders','view'),((x->>'factory')::uuid,(x->>'worker')::uuid,'orders','edit') on conflict do nothing;
 select id into pkg from public.permission_packages where factory_id=(x->>'factory')::uuid and template_key='quality_engineer';
 perform public.set_member_permission_packages((x->>'factory')::uuid,(x->>'viewer')::uuid,array[pkg],array[]::uuid[]);
 foreign_context:=late_test.new_context('correction-foreign',3600,false);
 perform set_config('request.jwt.claim.sub',foreign_context->>'owner',false);
 foreign_entry:=(public.record_lean_production((foreign_context->>'factory')::uuid,late_test.payload(foreign_context,1)||'{"scrap_kg":0.25}',gen_random_uuid())->>'id')::uuid;
 foreign_request:=public.production_correction_command((foreign_context->>'factory')::uuid,'submit',correction_test.payload(foreign_context,foreign_entry,1,.25,0),gen_random_uuid());
 insert into correction_test.context values(x||jsonb_build_object('entry',e,'other_entry',e2,'engineer',x->>'viewer','package',pkg,'foreign_factory',foreign_context->>'factory','foreign_request',foreign_request->>'id'));
end$$;
