-- Executed only through local.mjs after database/data-directory verification.
begin;
do $$declare x jsonb;f uuid;h private.manufactured_outputs;r jsonb;p jsonb;q jsonb;groups jsonb;k uuid;begin
select a.x into x from public.local_e2e_context a;f:=(x->>'factory')::uuid;perform set_config('request.jwt.claim.sub',x->>'owner',true);
-- Recording error: 60 recorded, 58 physically measured, zero rejection.
r:=public.record_manufactured_output(f,output2_test.payload(x,60),gen_random_uuid());select * into h from private.manufactured_outputs where entry_id=(r->>'entry_id')::uuid;
groups:=jsonb_build_array(h.recorded_groups->0||jsonb_build_object('quantity','58','released','58'));
p:=jsonb_build_object('total','58','groups',groups,'rejected','0','actual_rejected_kg','0','reason','Physical total measured at 58 meters');k:=gen_random_uuid();
q:=public.manufactured_output_command(f,'QUALITY',h.id,p,1,k);
perform late_test.ok(q->>'total'='58' and q->>'rejected'='0','corrected total does not invent rejection');
perform late_test.ok((select good_quantity=60 and effective_good=60 from public.production_entries where id=h.entry_id),'technician original preserved');
perform late_test.ok(public.manufactured_output_command(f,'QUALITY',h.id,p,1,k)=q,'Quality exact UUID replay');
perform late_test.ok(not exists(select 1 from public.finished_goods_movements where entry_id=h.entry_id),'inspection never credits stock');
perform late_test.fails(format('select public.manufactured_output_command(%L,''QUALITY'',%L,%L,%s,%L)',f,h.id,p,1,gen_random_uuid()),'output_revision');
-- Actual physical rejection: 60 measured, 58 accepted, 2 rejected with measured KG.
r:=public.record_manufactured_output(f,output2_test.payload(x,60),gen_random_uuid());select * into h from private.manufactured_outputs where entry_id=(r->>'entry_id')::uuid;
groups:=jsonb_build_array(h.recorded_groups->0||jsonb_build_object('quantity','58','released','58'));
p:=jsonb_build_object('total','60','groups',groups,'rejected','2','actual_rejected_kg','0.8','reason','Two meters physically rejected; measured weight 0.8 KG');
q:=public.manufactured_output_command(f,'QUALITY',h.id,p,1,gen_random_uuid());
perform late_test.ok(q->>'total'='60' and q->>'rejected'='2' and q->>'actual_rejected_kg'='0.8','actual rejection separate from total correction');
perform late_test.ok(not exists(select 1 from public.finished_goods_movements where entry_id=h.entry_id),'no pre-receipt stock credit');
perform set_config('request.jwt.claim.sub',x->>'viewer',true);
perform late_test.fails(format('select public.manufactured_output_command(%L,''QUALITY'',%L,%L,%s,%L)',f,h.id,p,1,gen_random_uuid()),'42501');
end$$;
select count(*) as checks from late_test.checks;
rollback;
