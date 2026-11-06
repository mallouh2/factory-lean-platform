begin;
truncate late_test.checks;
do $$declare x jsonb;f uuid;a uuid;w uuid;v uuid;view jsonb;choice jsonb;work jsonb;p jsonb;body jsonb;r uuid:=gen_random_uuid();k uuid:=gen_random_uuid();result jsonb;before_count bigint;member uuid;own_request uuid;pkg uuid;other_factory uuid;begin
select a.x into x from public.local_e2e_context a;f:=(x->>'factory')::uuid;a:=(x->>'owner')::uuid;w:=(x->>'worker')::uuid;v:=(x->>'viewer')::uuid;
perform set_config('request.jwt.claim.sub',a::text,true);
perform late_test.ok(public.historical_production_read(f)->>'available'='false','historical gate defaults false');
perform late_test.fails(format('select public.historical_production_command(%L,''SUBMIT'',''{}'',%L)',f,r),'42501');
-- Transient permission fixture, rolled back with the entire test. Existing
-- owner and original runtime permissions are never changed.
insert into public.user_permissions(factory_id,user_id,module,action) values(f,w,'orders','view'),(f,w,'orders','edit');
delete from public.user_permissions where factory_id=f and user_id=w and module='orders' and action='edit';
insert into public.permission_packages(factory_id,name) values(f,'Consolidated historical fixture') returning id into pkg;
insert into public.permission_package_permissions(factory_id,package_id,module,action) values(f,pkg,'orders','edit');
insert into public.member_permission_packages(factory_id,user_id,package_id) values(f,w,pkg);
perform late_test.ok(not has_table_privilege('authenticated','private.historical_recording_admission','INSERT'),'no client can mint internal approval capability');
insert into private.historical_recording_activation values(f,true) on conflict(factory_id) do update set enabled=true;
perform set_config('request.jwt.claim.sub',w::text,true);view:=public.historical_production_read(f);select o,j into choice,work from jsonb_array_elements(view->'choices')o cross join lateral jsonb_array_elements(o->'work')j where private.ordinary_output_remaining(f,(j->>'item')::uuid)>5 order by o#>>'{occurrence,ends_at}' desc limit 1;
perform late_test.ok(choice is not null and work is not null,'real persisted previous occurrence and overlapping work');
select id into member from public.memberships where factory_id=f and user_id=w;
p:=jsonb_build_object('unit_kind','line','production_unit',work->>'line','item',work->>'item','technician',member,'good',1,'scrap_kg',0,'discarded_quantity',0,'unfinished',0,'confirm_overproduction',true,
'output_groups',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity','1','missing_operations','[]'::jsonb)),
'recording_context',jsonb_build_object('version',3,'execution_key',work#>>'{eligibility,execution_key}','context_hash',work#>>'{eligibility,context_hash}','occurrence_key',choice#>>'{occurrence,occurrence_key}','current_shift_quantity_confirmed',true));
body:=jsonb_build_object('business_date',choice#>>'{occurrence,business_date}','occurrence_key',choice#>>'{occurrence,occurrence_key}','measurement',p);
select count(*) into before_count from public.production_entries where factory_id=f;
result:=public.historical_production_command(f,'SUBMIT',body,r);
perform late_test.ok(result->>'state'='PENDING','operator submission pending engineer approval');
perform late_test.ok((select count(*) from public.production_entries where factory_id=f)=before_count,'pending creates no official output or stock');
perform late_test.ok(public.historical_production_command(f,'SUBMIT',body,r)=result,'pending UUID replay');
perform late_test.fails(format('select public.historical_production_command(%L,''SUBMIT'',%L,%L)',f,body,gen_random_uuid()),'40001');
perform late_test.fails(format('select public.historical_production_command(%L,''APPROVE'',%L,%L)',f,jsonb_build_object('id',r),k),'42501');
perform set_config('request.jwt.claim.sub',a::text,true);
own_request:=gen_random_uuid();perform public.historical_production_command(f,'SUBMIT',jsonb_set(body,'{measurement,technician}',to_jsonb((select id from public.memberships where factory_id=f and user_id=a))),own_request);
perform late_test.fails(format('select public.historical_production_command(%L,''APPROVE'',%L,%L)',f,jsonb_build_object('id',own_request),gen_random_uuid()),'42501');
result:=public.historical_production_command(f,'APPROVE',jsonb_build_object('id',r),k);
perform late_test.ok(result->>'state'='APPROVED','independent effective approve permission admits historical writer');
perform late_test.ok((select count(*) from public.production_entries where factory_id=f)=before_count+1,'approval creates one entry');
perform late_test.ok(public.historical_production_command(f,'APPROVE',jsonb_build_object('id',r),k)=result,'approval UUID idempotent');
perform late_test.ok((select count(*) from public.production_entries where factory_id=f)=before_count+1,'no duplicate Good on replay');
perform late_test.ok((select original_occurrence_key=choice#>>'{occurrence,occurrence_key}' and technician_id=member and time_precision='SHIFT_PERIOD' from public.production_entries where request_id=r),'operator and period lineage without exact event invention');
perform late_test.ok(not exists(select 1 from public.finished_goods_movements where entry_id=(result#>>'{receipt,entry_id}')::uuid),'no stock credit before Quality and receipt');
perform late_test.ok(not exists(select 1 from private.historical_recording_admission),'transaction capability removed');
perform late_test.fails(format('update private.historical_recording_requests set payload=''{}'' where id=%L',r),'23514');
-- Ordinary completed-shift submission is still denied with the same payload.
perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',f,p,gen_random_uuid()),'40001');

insert into public.user_permissions(factory_id,user_id,module,action) values(f,w,'orders','approve');perform set_config('request.jwt.claim.sub',w::text,true);
perform late_test.fails(format('select public.historical_production_command(%L,''APPROVE'',%L,%L)',f,jsonb_build_object('id',own_request),gen_random_uuid()),'40001');
-- Rejection preserves evidence; corrected resubmission uses a new immutable ID.
perform set_config('request.jwt.claim.sub',w::text,true);
view:=public.historical_production_read(f);select value into work from jsonb_array_elements((select o->'work' from jsonb_array_elements(view->'choices')o where o#>>'{occurrence,occurrence_key}'=body->>'occurrence_key')) where value->>'item'=p->>'item';
p:=jsonb_set(p,'{recording_context,context_hash}',work#>'{eligibility,context_hash}');p:=jsonb_set(p,'{output_groups,0,id}',to_jsonb(gen_random_uuid()));
body:=jsonb_set(body,'{measurement}',p);r:=gen_random_uuid();perform public.historical_production_command(f,'SUBMIT',body,r);
perform set_config('request.jwt.claim.sub',a::text,true);perform public.historical_production_command(f,'REJECT',jsonb_build_object('id',r),gen_random_uuid());
perform late_test.ok((select count(*) from public.production_entries where factory_id=f)=before_count+1,'rejection adds no official production');
perform set_config('request.jwt.claim.sub',w::text,true);body:=body||jsonb_build_object('supersedes',r);r:=gen_random_uuid();perform public.historical_production_command(f,'SUBMIT',body,r);
perform late_test.ok((select supersedes is not null from private.historical_recording_requests where id=r),'safe new-UUID correction linked to rejected request');
perform late_test.fails(format('select public.historical_production_command(%L,''SUBMIT'',%L,%L)',f,jsonb_set(body,'{measurement,technician}',to_jsonb((select id from public.memberships where factory_id=f and user_id=a))),gen_random_uuid()),'42501');
update private.historical_recording_activation set enabled=false where factory_id=f;perform set_config('request.jwt.claim.sub',a::text,true);
perform late_test.fails(format('select public.historical_production_command(%L,''APPROVE'',%L,%L)',f,jsonb_build_object('id',r),gen_random_uuid()),'42501');
update private.historical_recording_activation set enabled=true where factory_id=f;
perform set_config('request.jwt.claim.sub',v::text,true);
select id into other_factory from public.factories where id<>f limit 1;
if other_factory is null then raise exception 'Cross-factory fixture missing';end if;
perform late_test.fails(format('select public.historical_production_read(%L)',other_factory),'42501');

perform late_test.ok(jsonb_array_length(public.historical_production_read(f)->'requests')=0,'view-only reader cannot disclose another operator request');perform late_test.fails(format('select public.historical_production_command(%L,''SUBMIT'',%L,%L)',f,body,gen_random_uuid()),'42501');
end$$;
do $$declare x jsonb;f uuid;a uuid;w uuid;r record;d jsonb;o jsonb;j jsonb;p jsonb;k uuid:=gen_random_uuid();member uuid;receipt jsonb;begin
select c.x into x from public.local_e2e_context c;f:=(x->>'factory')::uuid;a:=(x->>'owner')::uuid;w:=(x->>'worker')::uuid;
for r in select h.id,h.submitted_by from private.historical_recording_requests h where h.factory_id=f and not exists(select 1 from private.historical_recording_decisions d where d.request_id=h.id) loop perform set_config('request.jwt.claim.sub',case when r.submitted_by=a then w else a end::text,true);perform public.historical_production_command(f,'REJECT',jsonb_build_object('id',r.id),gen_random_uuid());end loop;
perform set_config('request.jwt.claim.sub',w::text,true);d:=public.historical_production_read(f);o:=d->'choices'->0;j:=o->'work'->0;select id into member from public.memberships where factory_id=f and user_id=w;
p:=jsonb_build_object('unit_kind','line','production_unit',j->>'line','item',j->>'item','technician',member,'good',0,'unfinished',0,'scrap_kg',1.25,'discarded_quantity',0,'output_groups','[]'::jsonb,'recording_context',jsonb_build_object('version',3,'execution_key',j#>>'{eligibility,execution_key}','context_hash',j#>>'{eligibility,context_hash}','occurrence_key',o#>>'{occurrence,occurrence_key}','current_shift_quantity_confirmed',true));
perform public.historical_production_command(f,'SUBMIT',jsonb_build_object('business_date',o#>>'{occurrence,business_date}','occurrence_key',o#>>'{occurrence,occurrence_key}','measurement',p),k);
perform set_config('request.jwt.claim.sub',a::text,true);receipt:=public.historical_production_command(f,'APPROVE',jsonb_build_object('id',k),gen_random_uuid());
perform late_test.ok((select good_quantity=0 and original_scrap_kg=1.25 and effective_scrap_kg=1.25 from public.production_entries where request_id=k),'measured historical Scrap-only uses existing KG ledger once');
perform late_test.ok(not exists(select 1 from public.finished_goods_movements where entry_id=(receipt#>>'{receipt,entry_id}')::uuid),'Scrap-only has no stock movement');
perform late_test.ok(not exists(select 1 from private.manufactured_outputs where entry_id=(receipt#>>'{receipt,entry_id}')::uuid),'no fabricated storable output from Scrap-only');
end$$;
select count(*) as checks from late_test.checks;
rollback;
