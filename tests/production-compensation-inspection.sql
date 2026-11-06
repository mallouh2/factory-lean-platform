do $$declare x jsonb;f uuid;r jsonb;begin
 select c.x into x from compensation_test.contexts c where label='partial-browser';f:=(x->>'factory')::uuid;perform set_config('request.jwt.claim.sub',x->>'owner',true);
 r:=public.production_compensation_read(f,(x->>'output')::uuid);
 perform compensation_test.ok(r->>'accepted'='48' and r->>'pending_inspection'='2','unreviewed replacement covers potential demand without claiming Quality acceptance');
 perform compensation_test.ok(r->>'received'='0' and r->>'available'='0','pending replacement never credits stock or authorizes duplicate compensation');
 perform compensation_test.ok(jsonb_array_length(r->'decisions')=1 and r#>>'{decisions,0,quantity}'='2' and r#>>'{decisions,0,recorded}'='2' and r#>>'{decisions,0,remaining}'='0','contextual decision history retains spent allowance evidence');
end$$;
select count(*) from compensation_test.checks;
