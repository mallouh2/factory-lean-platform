do $$begin if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55498 then raise exception 'Disposable local only';end if;end$$;
do $$declare x jsonb;f uuid;o uuid;g jsonb;r jsonb;k uuid:=gen_random_uuid();v bigint;w uuid;p jsonb;begin
 x:=output4_test.context('quality-action-completion');f:=(x->>'factory')::uuid;o:=(x->>'output')::uuid;
 select value into g from jsonb_array_elements(private.output_quality(f,o)->'groups')where jsonb_array_length(value->'missing_operations')>0 limit 1;
 select max(revision)into v from private.manufactured_output_events where output_id=o;
 p:=jsonb_build_object('group_id',g->>'id','quantity','4','choice','COMPLETE','operations',g->'missing_operations','reason','Complete four stored meters for the outstanding order');
 r:=public.plan_manufactured_completion(f,o,p,v,k);w:=(r->>'item_id')::uuid;
 perform public.plan_manufactured_completion(f,o,p,v,k);
 perform qa_actions.ok((select count(*)=1 from private.manufactured_completion_work where factory_id=f and request_id=k),'completion replay creates one source-bound work item');
 perform qa_actions.ok((select mr.status='REQUESTED'and mr.quantity=4 from public.material_requests mr where id=(r->>'material_request_id')::uuid),'completion requires actual Warehouse issue');
 perform qa_actions.ok((select po.line_id is null and po.actual_start is null and pr.priority='high'from public.production_orders po join public.production_requests pr on pr.id=po.request_id where po.id=w),'completion enters normal unscheduled HIGH Planning queue');
 perform qa_actions.ok((select on_hand=90 from public.finished_goods_balances where factory_id=f)and private.output_demand_received(f,(x->>'item')::uuid)=90,'creating completion does not create finished stock or fulfill shortage');
end$$;
