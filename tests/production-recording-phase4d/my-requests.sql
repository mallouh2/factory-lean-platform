\set ON_ERROR_STOP on
do $$declare x jsonb;f uuid;e uuid;i integer;v jsonb;p jsonb;first_page jsonb;second_page jsonb;all_page jsonb;stock numeric;begin
 x:=late_test.new_context('phase4d-pagination',3600,false);f:=(x->>'factory')::uuid;
 perform set_config('request.jwt.claim.sub',x->>'owner',false);
 e:=(public.record_lean_production(f,late_test.payload(x,5),gen_random_uuid())->>'id')::uuid;
 insert into public.user_permissions(factory_id,user_id,module,action) values(f,(x->>'worker')::uuid,'orders','view'),(f,(x->>'worker')::uuid,'orders','edit');
 x:=x||jsonb_build_object('foreign_factory',(select t.x->>'foreign_factory' from correction_test.context t));
 select on_hand into stock from public.finished_goods_balances where factory_id=f;
 perform set_config('request.jwt.claim.sub',x->>'worker',false);
 for i in 1..105 loop
  p:=correction_test.payload(x,e,(select effective_good from public.production_entries where id=e),.4,0);
  perform public.production_correction_command(f,'submit',p,gen_random_uuid());
 end loop;
 perform set_config('request.jwt.claim.sub',x->>'owner',false);
 for i in 1..3 loop
  p:=correction_test.payload(x,e,(select effective_good from public.production_entries where id=e),.4,0);
  perform public.production_correction_command(f,'submit',p,gen_random_uuid());
 end loop;
 all_page:=public.production_correction_read(f,'{"page_size":50}');
 perform correction_test.ok(not exists(select 1 from jsonb_array_elements(all_page->'rows')r where r->>'requested_by'=x->>'owner'),'reproduced: own records beyond other users first fifty');
 first_page:=public.production_correction_read(f,'{"mine":true,"page_size":2}');
 perform correction_test.ok(first_page->>'total'='3' and jsonb_array_length(first_page->'rows')=2 and first_page->>'complete'='false','My Requests filters before total and bounded pagination');
 perform correction_test.ok(not exists(select 1 from jsonb_array_elements(first_page->'rows')r where r->>'requested_by'<>x->>'owner'),'approver sees only own requests in mine scope');
 second_page:=public.production_correction_read(f,jsonb_build_object('mine',true,'page_size',2,'cursor',first_page->'next_cursor'));
 perform correction_test.ok(second_page->>'complete'='true' and jsonb_array_length(second_page->'rows')=1 and second_page#>>'{rows,0,id}'<>first_page#>>'{rows,0,id}' and second_page#>>'{rows,0,id}'<>first_page#>>'{rows,1,id}','My Requests next page has remaining own row without duplicates');
 perform correction_test.fails(format('select public.production_correction_read(%L,%L)',f,jsonb_build_object('page_size',2,'cursor',first_page->'next_cursor')),'40001');
 perform correction_test.fails(format('select public.production_correction_read(%L,%L)',f,'{"mine":"true"}'),'22023');
 perform correction_test.fails(format('select public.production_correction_read(%L,%L)',f,'{"mine":null}'),'22023');
 perform correction_test.fails(format('select public.production_correction_read(%L,%L)',f,jsonb_build_object('mine',true,'requested_by',x->>'worker')),'22023');
 perform set_config('request.jwt.claim.sub',x->>'worker',false);
 v:=public.production_correction_read(f,'{"mine":true,"page_size":100}');
 perform correction_test.ok(not exists(select 1 from jsonb_array_elements(v->'rows')r where r->>'requested_by'<>x->>'worker'),'ordinary submitter remains own-scoped');
 perform correction_test.fails(format('select public.production_correction_read(%L,%L)',x->>'foreign_factory','{"mine":true}'),'42501');
 perform correction_test.ok((select on_hand=stock from public.finished_goods_balances where factory_id=f),'pagination fixture creates no Good/stock change');
 perform correction_test.ok(not has_function_privilege('anon','public.production_correction_read(uuid,jsonb)','execute'),'new filter preserves anonymous RPC denial');
end$$;
