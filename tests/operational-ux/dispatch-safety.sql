do $$declare label text;x jsonb;f uuid;r jsonb;h uuid;g uuid;p jsonb;so uuid;ln uuid;source uuid;before_count bigint;begin
 foreach label in array array['held','identified'] loop
  x:=late_test.new_context('pool-'||label,3600,false);f:=(x->>'factory')::uuid;perform set_config('request.jwt.claim.sub',x->>'owner',false);g:=gen_random_uuid();
  r:=public.record_manufactured_output(f,late_test.payload(x,3)||jsonb_build_object('output_groups',jsonb_build_array(jsonb_build_object('id',g,'quantity','3','missing_operations','[]'::jsonb))),gen_random_uuid());
  select id into h from private.manufactured_outputs where entry_id=(r->>'entry_id')::uuid;
  p:=jsonb_build_object('groups',jsonb_build_array(jsonb_build_object('id',g,'quantity','3','released','3','missing_operations','[]'::jsonb)),'rejected','0','reason','Matches three physical meters');
  perform public.manufactured_output_command(f,'QUALITY',h,p,1,gen_random_uuid());
  perform public.receive_manufactured_output(f,h,jsonb_build_object('group_id',g,'quantity','3','location','Local test bay','physical_confirmation',true),2,gen_random_uuid());
  so:=public.create_sales_order(f,jsonb_build_object('requested_delivery',clock_timestamp()+interval '4 days','lines',jsonb_build_array(jsonb_build_object('product_id',x->>'product','quantity',1,'unit','meter'))),gen_random_uuid());perform public.approve_sales_order(f,so,gen_random_uuid());select id into ln from public.sales_order_lines where order_id=so;
  if label='held' then
   -- Explicit measured fixture evidence, separate from the rejected meter.
   p:=jsonb_build_object('groups',jsonb_build_array(jsonb_build_object('id',g,'quantity','2','released','2','missing_operations','[]'::jsonb)),'rejected','1','actual_rejected_kg','0.5','reason','One received meter found damaged; separately weighed 0.5 KG');
   perform public.manufactured_output_command(f,'QUALITY',h,p,3,gen_random_uuid());
   perform ux_test.ok(private.output_pool_held(f,(x->>'product')::uuid,'meter'),'unidentified held receipt blocks ambiguous pool');
  else
   select id into source from public.finished_goods_sources where factory_id=f;
   perform public.source_stock_command(f,'identify',jsonb_build_object('source',source,'quantity','3','label','Kept separate physical bundle','physically_identified',true,'note','Controlled labeled fixture'),'[]',gen_random_uuid());
   perform public.source_stock_command(f,'reserve',jsonb_build_object('sales_line_id',ln),jsonb_build_array(jsonb_build_object('source_id',source,'quantity','1')),gen_random_uuid());
  end if;
  select count(*) into before_count from public.finished_goods_movements where factory_id=f;
  perform late_test.fails(format('select public.dispatch_sales_quantity(%L,%L,%L,1,%L)',f,so,ln,gen_random_uuid()),'pooled_dispatch_unavailable');
  perform ux_test.ok((select on_hand=3 and reserved=1 from public.finished_goods_balances where factory_id=f)and(select count(*)=before_count from public.finished_goods_movements where factory_id=f),label||' rejected without stock/reservation mutation');
 end loop;
end$$;
