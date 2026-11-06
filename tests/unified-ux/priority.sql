-- Future completion decisions only; fixtures exercise real protected creation.
do $$declare x jsonb;w jsonb;f uuid;begin
 x:=output4_test.context('unified-high-completion');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'COMPLETE',10);
 perform ux_test.ok((select r.priority='high' from public.production_orders o join public.production_requests r on r.id=o.request_id where o.id=(w->>'item_id')::uuid),'completion shortage defaults high');
 x:=output4_test.context('unified-high-replacement');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'REPLACE',10);
 perform ux_test.ok((select r.priority='high' from public.production_orders o join public.production_requests r on r.id=o.request_id where o.id=(w->>'item_id')::uuid),'replacement shortage defaults high');
 x:=x||'{"revision":5}';w:=output4_test.decision(x,'STOCK',10);
 perform ux_test.ok((select r.priority='normal' from public.production_orders o join public.production_requests r on r.id=o.request_id where o.id=(w->>'item_id')::uuid),'stock-only recovery remains normal');
end$$;
