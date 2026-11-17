begin;
do $$declare x jsonb;f uuid;begin
 select c.x into x from activation_test.contexts c where label='main';f:=(x->>'factory')::uuid;
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 perform activation_test.ok(public.manufactured_output_capability(f)->>'activation_state'='NEVER_ACTIVATED','Default never activated');
 perform activation_test.ok(not private.manufactured_output_enabled(f),'Default disabled');
end$$;
commit;

-- Database operator, never an application/browser endpoint.
select private.set_manufactured_output_activation((select(x->>'factory')::uuid from activation_test.contexts where label='main'),true,0,'Isolated approved clean pilot');

begin;
set local role authenticated;
do $$declare x jsonb;f uuid;p jsonb;r jsonb;output uuid;entry uuid;groups jsonb;fg uuid;wip uuid;key uuid;rev bigint;args jsonb;so uuid;sl uuid;begin
 select c.x into x from activation_test.contexts c where label='main';f:=(x->>'factory')::uuid;
 perform set_config('request.jwt.claim.sub',x->>'owner',true);perform set_config('request.jwt.claim.role','authenticated',true);
 perform activation_test.reject(format('select private.set_manufactured_output_activation(%L,false,1,%L)',f,'Unauthorized application activation'),'42501');
 p:=activation_test.payload(x);key:=gen_random_uuid();r:=public.record_manufactured_output(f,p,key);entry:=(r->>'entry_id')::uuid;
 insert into activation_test.requests values('record','record_manufactured_output',jsonb_build_object('factory',f,'payload',p,'request_id',key),r);
 perform activation_test.ok(r->>'outcome'='COMMITTED','Manufactured recording committed');
 -- Protected public read supplies output identity; no private-table shortcut.
 output:=(public.manufactured_output_read(f,'entry',entry,0)->'rows'->0->>'id')::uuid;
 perform activation_test.ok(output is not null,'Manufactured declaration enrolled');
 insert into activation_test.requests values('output','identity',jsonb_build_object('factory',f,'output',output,'entry',entry),null);
end$$;
commit;

-- Test-owner diagnostics; business changes continue as authenticated actors.
do $$declare f uuid;begin
 select(x->>'factory')::uuid into f from activation_test.contexts where label='main';
 perform activation_test.ok(coalesce((select on_hand from public.finished_goods_balances where factory_id=f),0)=0,'Recording does not credit finished stock');
 perform activation_test.ok(not exists(select 1 from public.unfinished_lots where factory_id=f),'Recording does not create available WIP');
end$$;

begin;set local role authenticated;
do $$declare x jsonb;f uuid;output uuid;p jsonb;r jsonb;groups jsonb;k uuid:=gen_random_uuid();begin
 select c.x into x from activation_test.contexts c where label='main';f:=(x->>'factory')::uuid;
 select(args->>'output')::uuid into output from activation_test.requests where label='output';
 perform set_config('request.jwt.claim.sub',x->>'worker',true);perform set_config('request.jwt.claim.role','authenticated',true);
 groups:=jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity','80','released','80','missing_operations','[]'::jsonb),
 jsonb_build_object('id',gen_random_uuid(),'quantity','15','released','15','missing_operations',jsonb_build_array(x->>'step')));
 p:=jsonb_build_object('groups',groups,'total','100','rejected','5','actual_rejected_kg','2.5','reason','Measured 100; five rejected and fifteen need Printing');
 r:=public.manufactured_output_command(f,'QUALITY',output,p,1,k);
 insert into activation_test.requests values('quality','manufactured_output_command',jsonb_build_object('factory',f,'operation','QUALITY','target',output,'payload',p,'expected_revision',1,'request_id',k),r);
 perform activation_test.ok(r->>'rejected'='5','Quality rejection preserved');
 perform activation_test.ok((r->'groups'->0->>'quantity')is not null,'Quality classification released');
 update activation_test.requests set result=jsonb_build_object('groups',groups,'revision',r->'revision')where label='output';
end$$;commit;

do $$declare f uuid;begin
 select(x->>'factory')::uuid into f from activation_test.contexts where label='main';
 perform activation_test.ok(coalesce((select on_hand from public.finished_goods_balances where factory_id=f),0)=0,'Quality release is not inventory credit');
 perform activation_test.ok((select good_quantity=90 and effective_good=90 and effective_unfinished=10 from public.production_entries where factory_id=f),'Original technician quantities remain preserved');
end$$;

begin;set local role authenticated;
do $$declare x jsonb;f uuid;o uuid;g jsonb;fg uuid;wg uuid;rev bigint;a jsonb;r jsonb;k uuid;so uuid;line uuid;begin
 select c.x into x from activation_test.contexts c where label='main';f:=(x->>'factory')::uuid;
 select(args->>'output')::uuid,result->'groups',(result->>'revision')::bigint into o,g,rev from activation_test.requests where label='output';
 select(value->>'id')::uuid into fg from jsonb_array_elements(g)where jsonb_array_length(value->'missing_operations')=0;
 select(value->>'id')::uuid into wg from jsonb_array_elements(g)where jsonb_array_length(value->'missing_operations')>0;
 perform set_config('request.jwt.claim.sub',x->>'viewer',true);perform set_config('request.jwt.claim.role','authenticated',true);
 perform activation_test.ok(public.manufactured_receiving_context(f,o,0)->>'available'='true','Released output visible to Warehouse');
 a:=jsonb_build_object('group_id',fg,'quantity','30','physical_confirmation',true,'warehouse_id',x->>'finished_warehouse');k:=gen_random_uuid();
 r:=public.receive_manufactured_output(f,o,a,rev,k);
 insert into activation_test.requests values('receipt','receive_manufactured_output',jsonb_build_object('factory',f,'target',o,'payload',a,'expected_revision',rev,'request_id',k),r);
 perform activation_test.ok(public.receive_manufactured_output(f,o,a,rev,k)=r,'Receipt retry returns immutable result');
 rev:=(r->>'revision')::bigint;
 r:=public.receive_manufactured_output(f,o,a||'{"quantity":"50"}',rev,gen_random_uuid());rev:=(r->>'revision')::bigint;
 r:=public.receive_manufactured_output(f,o,jsonb_build_object('group_id',wg,'quantity','15','physical_confirmation',true,'warehouse_id',x->>'unfinished_warehouse'),rev,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 so:=public.create_sales_order(f,jsonb_build_object('lines',jsonb_build_array(jsonb_build_object('product_id',x->>'product','quantity',60,'unit','meter'))),gen_random_uuid());
 perform public.approve_sales_order(f,so,gen_random_uuid());
 -- SQL diagnostics below verify the line before a separate authenticated dispatch.
 insert into activation_test.requests values('sales','order',jsonb_build_object('factory',f,'order',so),null);
end$$;commit;

do $$declare f uuid;so uuid;line uuid;begin
 select(x->>'factory')::uuid into f from activation_test.contexts where label='main';
 perform activation_test.ok((select on_hand=80 and reserved=60 from public.finished_goods_balances where factory_id=f),'Physical receipts credit exactly 80; Sales reserves 60');
 perform activation_test.ok((select quantity_created=15 and quantity_available=15 and warehouse_quantity=15 from public.unfinished_lots where factory_id=f),'Unfinished receipt is 15 WIP, not finished stock');
 select(args->>'order')::uuid into so from activation_test.requests where label='sales';
 select id into line from public.sales_order_lines where order_id=so;
 update activation_test.requests set args=args||jsonb_build_object('line',line)where label='sales';
end$$;

begin;set local role authenticated;
do $$declare x jsonb;a jsonb;begin
 select c.x into x from activation_test.contexts c where label='main';
 perform set_config('request.jwt.claim.sub',x->>'viewer',true);perform set_config('request.jwt.claim.role','authenticated',true);
 select args into a from activation_test.requests where label='sales';
 perform public.dispatch_sales_quantity((a->>'factory')::uuid,(a->>'order')::uuid,(a->>'line')::uuid,25,gen_random_uuid());
end$$;commit;

do $$declare f uuid;begin
 select(x->>'factory')::uuid into f from activation_test.contexts where label='main';
 perform activation_test.ok((select on_hand=55 and reserved=35 from public.finished_goods_balances where factory_id=f),'Pooled partial dispatch: stock55 reserved35');
 perform activation_test.ok((select dispatched_quantity=25 from public.sales_order_lines where factory_id=f),'Dispatched25 without mandatory batch selection');
end$$;
select count(*) as assertions from activation_test.checks;
