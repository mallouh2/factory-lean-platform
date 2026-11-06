do $$begin if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55498 then raise exception 'Disposable local only';end if;end$$;
do $$declare x jsonb;f uuid;h uuid;g jsonb;p jsonb;s jsonb;r jsonb;k uuid;n bigint;foreign_factory uuid;begin
 x:=late_test.new_context('quality-actions-held',14400,false);f:=(x->>'factory')::uuid;
 r:=public.record_manufactured_output(f,output2_test.payload(x,90,0),gen_random_uuid());select id,recorded_groups into h,g from private.manufactured_outputs where entry_id=(r->>'entry_id')::uuid;
 select jsonb_agg(v||jsonb_build_object('quantity','89','released','89'))into g from jsonb_array_elements(g)v;
 perform public.manufactured_output_command(f,'QUALITY',h,jsonb_build_object('groups',g,'rejected','1','total','90','actual_rejected_kg','.5','reason','One meter measured damaged'),1,gen_random_uuid());
 s:=private.production_quality_followup(f,h);k:=gen_random_uuid();p:=jsonb_build_object('quality_revision',s->'quality_revision','note','Investigating shortage');
 r:=public.production_quality_followup_command(f,h,'START',p,(s->>'status_revision')::bigint,k);
 perform late_test.fails(format('select public.production_quality_followup_command(%L,%L,%L,%L,%s,%L)',f,h,'START',p,(s->>'status_revision')::bigint+1,k),'request_conflict');
 s:=private.production_quality_followup(f,h);n:=(select count(*)from private.production_quality_followup_events where factory_id=f);
 perform late_test.fails(format('select public.production_quality_followup_command(%L,%L,%L,%L,%s,%L)',f,h,'RESOLVE',jsonb_build_object('quality_revision',s->'quality_revision','note','Created a replacement job is not actual fulfillment'),s->>'status_revision',gen_random_uuid()),'output_followup_blocked');
 perform qa_actions.ok(private.production_quality_followup(f,h)->>'state'='IN_PROGRESS'and(select count(*)=n from private.production_quality_followup_events where factory_id=f),'unfulfilled material shortage cannot be cosmetically resolved');
 perform late_test.fails(format('update private.production_quality_followup_events set state=%L where factory_id=%L','RESOLVED',f),'manufactured_output_immutable');
 select factory_id into foreign_factory from private.manufactured_outputs where factory_id<>f limit 1;
 perform late_test.fails(format('select public.production_quality_followups(%L)',foreign_factory),'permission_denied');
 perform qa_actions.ok(not exists(select 1 from public.finished_goods_balances where factory_id=f and on_hand<>0)and not exists(select 1 from public.finished_goods_movements where factory_id=f),'denials preserve actual inventory');
end$$;
