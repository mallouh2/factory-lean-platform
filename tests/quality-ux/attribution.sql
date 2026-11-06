begin;
create function pg_temp.ok(v boolean,label text)returns void language plpgsql as $$begin if v is distinct from true then raise exception 'FAIL %',label;end if;raise notice 'PASS %',label;end$$;
do $$declare x jsonb;f uuid;page jsonb;p jsonb;begin
 select c.x into x from local_preview.context c;f:=(x->>'factory')::uuid;perform set_config('request.jwt.claim.sub',x->>'owner',true);perform set_config('request.jwt.claim.role','authenticated',true);
 page:=public.quality_read(f,jsonb_build_object('mode','board','shift',x->>'shift'));
 perform pg_temp.ok(jsonb_array_length(page->'rows')=2,'effective shift filter before pagination');
 page:=public.quality_read(f,jsonb_build_object('mode','board','date',(select business_date::text from private.production_shift_occurrences where factory_id=f limit 1)));
 perform pg_temp.ok(jsonb_array_length(page->'rows')=2,'verified production date filter before pagination');
 perform pg_temp.ok(jsonb_array_length(public.quality_read(f,jsonb_build_object('mode','board','shift',gen_random_uuid()))->'rows')=0,'other dated shift does not leak into result');
 perform public.source_stock_command(f,'correct',jsonb_build_object('entry',x->>'quality_entry','good',474,'confirm_overproduction',true,'discarded_quantity',0,'scrap_kg',0,'startup_kg',0,'unfinished',0,'remaining_work','','reason','Verified corrected production quantity'),jsonb_build_array(jsonb_build_object('source_id',(select id from public.finished_goods_sources where entry_id=(x->>'quality_entry')::uuid),'quantity','1')),gen_random_uuid());
 perform pg_temp.ok(public.quality_read(f,jsonb_build_object('mode','board','entry',x->>'quality_entry'))#>>'{rows,0,shift_quantity,quantity}'='499','shift production uses approved effective Good after correction');
 p:=late_test.payload(x,1)-'recording_context';p:=p||'{"confirm_overproduction":true}';
 perform public.record_lean_production(f,p,gen_random_uuid());
 page:=public.quality_read(f,jsonb_build_object('mode','board','entry',x->>'quality_entry'));
 perform pg_temp.ok(page#>>'{rows,0,shift_quantity,complete}'='false' and page#>'{rows,0,shift_quantity,quantity}'='null'::jsonb,'mixed unknown attribution never becomes a fabricated complete shift total');
end$$;
rollback;
