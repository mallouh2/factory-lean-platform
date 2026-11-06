do $$declare x jsonb;f uuid;p uuid;r uuid;meter uuid;piece uuid;other jsonb;result jsonb;s jsonb;q jsonb;begin
 select t.x into x from reporting_test.context t;f:=(x->>'factory')::uuid;perform set_config('request.jwt.claim.sub',x->>'owner',false);
 insert into public.products(factory_id,name,name_ar,code,unit,stock_unit,unit_weight_kg) values(f,'Local connector','وصلة','M3PC','piece','piece',1.5) returning id into p;
 perform public.configure_center_capabilities(f,(x->>'machine')::uuid,jsonb_build_array(
  jsonb_build_object('product_id',x->>'product','rate',6000,'rate_unit','meter','setup_minutes',0),
  jsonb_build_object('product_id',p,'rate',6000,'rate_unit','piece','setup_minutes',0)));
 perform public.configure_center_capabilities(f,(x->>'other_machine')::uuid,jsonb_build_array(jsonb_build_object('product_id',x->>'product','rate',6000,'rate_unit','meter','setup_minutes',0)));
 r:=public.create_production_request(f,'M3A distinct items','normal',null,'Local multiple-unit reporting',jsonb_build_array(
  jsonb_build_object('product_id',x->>'product','quantity',100,'unit','meter'),jsonb_build_object('product_id',p,'quantity',20,'unit','piece')));
 select id into meter from public.production_orders where request_id=r and product_id=(x->>'product')::uuid;
 select id into piece from public.production_orders where request_id=r and product_id=p;
 perform public.plan_product_item(f,meter,(x->>'other_line')::uuid,date_trunc('day',clock_timestamp())+interval '3 days 1 hour');
 perform public.plan_product_item(f,piece,(x->>'line')::uuid,date_trunc('day',clock_timestamp())+interval '3 days 1 hour');
 perform public.start_product_item(f,meter);perform public.start_product_item(f,piece);
 other:=x||jsonb_build_object('item',meter,'line',x->>'other_line');
 perform public.record_lean_production(f,late_test.payload(other,1.23456789)||'{"scrap_kg":0.000000123456789}',gen_random_uuid());
 other:=x||jsonb_build_object('item',piece,'product',p);
 perform public.record_lean_production(f,late_test.payload(other,2)||'{"scrap_kg":0.125}',gen_random_uuid());
 q:=jsonb_build_object('reporting_version',3,'to_at',clock_timestamp());
 s:=public.production_history(f,q||'{"mode":"summary","time_basis":"production"}');
 perform reporting_test.ok((select count(distinct v->>'line_id')=2 from jsonb_array_elements(s->'rows')v where v->>'product_id'=x->>'product'),'same Product on two lines stays distinct');
 perform reporting_test.ok((select count(distinct v->>'unit')=2 from jsonb_array_elements(s->'rows')v),'Meter and Piece never aggregate together');
 result:=public.production_history(f,q||jsonb_build_object('product',p));
 perform reporting_test.ok(result->>'total'='1' and result#>>'{rows,0,good}'='2' and result#>>'{rows,0,unit}'='piece','Product filter preserves configured Piece quantities');
 perform reporting_test.ok(result#>>'{rows,0,request_id}'=r::text and result#>>'{rows,0,item_id}'=piece::text,'request and item identities distinct');
 perform reporting_test.ok(result#>>'{rows,0,line_name_ar}' is not null and result#>>'{rows,0,product_name_ar}'='وصلة','bilingual identities retained');
 result:=public.production_history(f,q||jsonb_build_object('line',x->>'other_line'));
 perform reporting_test.ok(result->>'total'='1' and (result#>>'{rows,0,scrap_kg}')::numeric=.000000123456789,'line-only entry and KG precision');
 result:=public.record_lean_production(f,late_test.payload(other,0.000001)-'recording_context'||'{"scrap_kg":0.000000001}',gen_random_uuid());
 update reporting_test.context ctx set x=ctx.x||jsonb_build_object('legacy',result->>'id');
 result:=public.production_history(f,jsonb_build_object('reporting_version',3,'entry',result->>'id','to_at',clock_timestamp()));
 perform reporting_test.ok(result#>>'{rows,0,time_precision}'='UNKNOWN' and result#>>'{rows,0,scrap_rate}' is null,'legacy processing lacks dated/weight proof for a physical rate');
 -- Exact clocks and independent source tracing use the normal unchanged pipeline.
 perform public.finish_product_item(f,meter);perform public.finish_product_item(f,piece);
end$$;
select count(*) as cumulative_assertions from reporting_test.checks;
