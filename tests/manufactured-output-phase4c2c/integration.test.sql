-- Called only by the disposable loopback preview preparation.
begin;
truncate late_test.checks;
do $$declare x jsonb;f uuid;a jsonb;r jsonb;w jsonb;begin
 x:=output4cb_test.context('Reader finished reconciliation');f:=(x->>'factory')::uuid;
 a:=public.manufactured_receiving_read(f)#>'{rows,0,reconciliation_action}';
 perform late_test.ok(a->>'available'='true' and a->>'quantity'='5' and a->>'mode'='FINISHED_TO_UNFINISHED','finished candidate is existing exact protected specification');
 perform late_test.ok(a#>>'{sources,0,id}'=x->>'source','only physically identified actual source returned');
 perform output4cb_test.apply(x);
 perform late_test.ok(public.manufactured_receiving_read(f)#>'{rows,0,reconciliation_action}'='null'::jsonb,'no second physical adjustment offered after apply');
 x:=output4cb2_test.context('Reader allocated reconciliation');f:=(x->>'factory')::uuid;
 a:=public.manufactured_receiving_read(f)#>'{rows,0,reconciliation_action}';
 perform late_test.ok(a->>'available'='false' and a->>'blocker'='output_allocation_retirement_required','Planning retirement required, not simulated in UI');
 perform output4b_test.revise(x,x->'work');
 a:=public.manufactured_receiving_read(f)#>'{rows,0,reconciliation_action}';
 perform late_test.ok(a->>'available'='true' and a->>'quantity'='4' and a->>'source_lot_id'=x->>'lot' and a->>'source_location'=x->>'source_location','unfinished source/location/amount supplied by protected contracts');
 perform set_config('request.jwt.claim.sub',x->>'worker',true);
 begin perform public.manufactured_receiving_read(f);raise exception 'reader unexpectedly allowed';exception when insufficient_privilege then null;end;
 perform late_test.ok(true,'Warehouse read permission enforced');
 perform late_test.ok(not has_function_privilege('authenticated','private.output_reconciliation_action(uuid,uuid)','execute'),'private read helper not independently executable');
end$$;
table late_test.checks;
rollback;
