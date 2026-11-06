-- Bounded scale fixture through the existing recording pipeline. No target/rate
-- or schedule edits, no disabled constraints and no inferred observations.
do $$declare x jsonb;f uuid;n integer;h jsonb;v jsonb;seen uuid[]:='{}';revision text;stamp timestamptz;before_digest text;begin
 select t.x into x from m3c_test.context t;f:=(x->>'factory')::uuid;perform set_config('request.jwt.claim.sub',x->>'owner',false);
 for n in 1..205 loop perform public.record_lean_production(f,late_test.payload(x,.125)||'{"scrap_kg":0.001}',gen_random_uuid());end loop;
 stamp:=clock_timestamp();before_digest:=reporting_test.digest();
 for n in 1..3 loop
  h:=public.lean_read(f,jsonb_build_object('mode','entries','from',stamp-interval '1 day','to',stamp,'page',n));
  if n=1 then revision:=h->>'source_revision';end if;
  perform m3c_test.ok(h->>'source_revision'=revision and jsonb_array_length(h->'rows')<=100,'bounded stable consumer page '||n);
  for v in select value from jsonb_array_elements(h->'rows') loop
   if (v->>'id')::uuid=any(seen) then raise exception 'Duplicate consumer entry';end if;seen:=array_append(seen,(v->>'id')::uuid);
  end loop;
 end loop;
 perform m3c_test.ok(cardinality(seen)=(h->>'total')::int and cardinality(seen)>=205,'three consumer pages cover entire population without duplicates or truncation');
 perform m3c_test.ok(reporting_test.digest()=before_digest,'paginated consumer reads preserve full operational state');
end$$;
select set_config('request.jwt.claim.sub',x->>'owner',false),x->>'factory' as factory from m3c_test.context \gset
explain (analyze,buffers,format json) select public.lean_read(:'factory'::uuid,jsonb_build_object('mode','entries','from',clock_timestamp()-interval '1 day','to',clock_timestamp(),'page',1));
explain (analyze,buffers,format json) select * from private.lean_window_occurrences(:'factory'::uuid,clock_timestamp()-interval '1 day',clock_timestamp());
select count(*) as cumulative_consumer_assertions from m3c_test.checks;
