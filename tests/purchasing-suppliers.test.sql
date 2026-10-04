-- TESTING only: all fixtures, grants and support-scope isolation roll back.
begin;
create temporary table purchasing_checks(label text);
create function pg_temp.check_purchase(ok boolean,label text) returns void language plpgsql as $$begin
 if ok is distinct from true then raise exception 'Purchasing: %',label;end if;
 insert into purchasing_checks values(label);
end$$;
create function pg_temp.fail_purchase(statement text,expected text,label text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then
  if sqlerrm<>expected then raise exception 'Purchasing % expected %, got %',label,expected,sqlerrm;end if;
  insert into purchasing_checks values(label);return;
 end;raise exception 'Purchasing % expected failure',label;
end$$;
create function pg_temp.purchase_call(f uuid,a text,p jsonb) returns uuid language sql as $$select public.supply_command(f,a,p,gen_random_uuid())$$;
create function pg_temp.purchase_change(f uuid,r uuid,a text,reason text default '') returns uuid language sql as $$
 select pg_temp.purchase_call(f,'purchase_change',jsonb_build_object('id',r,'revision',(select revision from public.purchase_requisitions where id=r),'action',a,'reason',reason));
$$;
do $test$
declare f uuid;actor uuid;other uuid;r uuid;s uuid;new_s uuid;token uuid;p jsonb;x jsonb;n bigint;links bigint;before_stock text;state text;label text;
begin
 select m.factory_id,m.user_id into f,actor from public.memberships m join public.factories fac on fac.id=m.factory_id where fac.is_demo and m.is_owner and m.status='approved' limit 1;
 select user_id into other from public.memberships where factory_id=f and user_id<>actor and status='approved' limit 1;
 if actor is null or other is null then raise exception 'Existing TESTING people required';end if;
 update private.platform_scopes set expires_at=now() where factory_id=f and user_id in(actor,other);
 perform set_config('request.jwt.claim.sub',actor::text,true);
 insert into public.user_permissions(factory_id,user_id,module,action) select f,actor,module,action from public.permissions where module in('purchasing','suppliers') on conflict do nothing;
 insert into public.user_permissions values(f,other,'factory','view') on conflict do nothing;
 select md5(coalesce(jsonb_agg(to_jsonb(i) order by id)::text,'')) into before_stock from public.inventory_transactions i;
 label:='Supplier QA '||gen_random_uuid();
 s:=pg_temp.purchase_call(f,'supplier_save',jsonb_build_object('name',label,'phone','555123','notes','Permanent contact','active',true));
 select count(*) into n from public.suppliers;select count(*) into links from public.supplier_category_links;
 perform pg_temp.check_purchase((select phone='555123' and notes='Permanent contact' from public.suppliers where id=s),'authorized simple supplier creation');
 foreach state in array array[label,lower(label),'  '||upper(label)||'  '] loop
  new_s:=pg_temp.purchase_call(f,'supplier_save',jsonb_build_object('name',state,'phone','different','active',true));
  perform pg_temp.check_purchase(new_s=s,'normalized duplicate returns existing supplier');
 end loop;
 perform pg_temp.check_purchase((select count(*)=n from public.suppliers),'duplicate creates no extra directory record');
 perform pg_temp.check_purchase((select phone='555123' from public.suppliers where id=s),'duplicate does not overwrite existing contacts');
 perform pg_temp.check_purchase((select count(*)=links from public.supplier_category_links),'quick create has no category relationships');
 r:=pg_temp.purchase_call(f,'purchase_manual',jsonb_build_object('item_name','QA supplier test part','quantity',2,'unit','piece','details','Fixture part','source_context','Maintenance'));
 perform pg_temp.purchase_change(f,r,'UNDER_REVIEW');
 foreach state in array array['REJECTED','NEEDS_CLARIFICATION','CANCELLED'] loop
  perform pg_temp.fail_purchase(format('select pg_temp.purchase_change(%L,%L,%L)',f,r,state),'supply_reason','empty protected explanation denied');
 end loop;
 perform pg_temp.check_purchase((select status='UNDER_REVIEW' from public.purchase_requisitions where id=r),'empty explanations preserve state');
 token:=gen_random_uuid();p:=jsonb_build_object('id',r,'revision',(select revision from public.purchase_requisitions where id=r),'action','supplier','supplier_text','  Request-only Al Noor  ');
 perform public.supply_command(f,'purchase_change',p,token);perform public.supply_command(f,'purchase_change',p,token);
 perform pg_temp.check_purchase((select supplier_id is null and supplier_text='Request-only Al Noor' from public.purchase_requisitions where id=r),'temporary supplier stored only on request');
 perform pg_temp.check_purchase((select count(*)=n from public.suppliers),'temporary name creates no directory record');
 perform pg_temp.check_purchase((select count(*)=links from public.supplier_category_links),'temporary name creates no category/primary links');
 perform pg_temp.check_purchase((select count(*)=1 from public.purchase_request_events where request_id=r and supplier_name='Request-only Al Noor'),'temporary supplier history once on retry');
 x:=public.supply_page(f,'purchases',1,'{}',r);perform pg_temp.check_purchase(x->'selected'->>'supplier_name'='Request-only Al Noor','reader displays temporary supplier');
 perform pg_temp.purchase_change(f,r,'ORDERED');perform pg_temp.purchase_change(f,r,'READY_FOR_RECEIPT');perform pg_temp.purchase_change(f,r,'receive_direct');
 perform pg_temp.check_purchase((select status='RECEIVED' from public.purchase_requisitions where id=r),'temporary supplier permits normal order/direct receipt');
 perform pg_temp.check_purchase((select md5(coalesce(jsonb_agg(to_jsonb(i) order by id)::text,''))=before_stock from public.inventory_transactions i),'temporary direct workflow has no stock movement');
 r:=pg_temp.purchase_call(f,'purchase_manual',jsonb_build_object('item_name','QA existing supplier part','quantity',1,'unit','piece','details','Fixture part','source_context','Production'));
 p:=jsonb_build_object('id',r,'revision',1,'action','supplier','supplier_text','  '||lower(label)||'  ');
 perform pg_temp.purchase_call(f,'purchase_change',p);
 perform pg_temp.check_purchase((select supplier_id=s and supplier_text='' from public.purchase_requisitions where id=r),'normalized typed existing supplier keeps real ID');
 perform pg_temp.check_purchase((select supplier_id=s and supplier_name=label from public.purchase_request_events where request_id=r order by created_at desc,id desc limit 1),'saved supplier ID/name retained in audit');
 p:=jsonb_build_object('id',r,'revision',(select revision from public.purchase_requisitions where id=r),'action','supplier','supplier_id',s,'supplier_text','conflicting');
 perform pg_temp.fail_purchase(format('select pg_temp.purchase_call(%L,%L,%L::jsonb)',f,'purchase_change',p),'supply_invalid','cannot forge mixed supplier identities');
 foreach state in array array['',repeat('x',201)] loop
  p:=jsonb_build_object('id',r,'revision',(select revision from public.purchase_requisitions where id=r),'action','supplier','supplier_text',state);
  perform pg_temp.fail_purchase(format('select pg_temp.purchase_call(%L,%L,%L::jsonb)',f,'purchase_change',p),'supply_invalid','invalid temporary name denied');
 end loop;
 delete from public.user_permissions where factory_id=f and user_id=actor and module='suppliers';
 p:=jsonb_build_object('name','Unauthorized permanent supplier');
 perform pg_temp.fail_purchase(format('select pg_temp.purchase_call(%L,%L,%L::jsonb)',f,'supplier_save',p),'permission_denied','buyer without supplier edit cannot create permanent supplier');
 p:=jsonb_build_object('id',r,'revision',(select revision from public.purchase_requisitions where id=r),'action','supplier','supplier_text','Buyer request-local supplier');
 perform pg_temp.purchase_call(f,'purchase_change',p);
 perform pg_temp.check_purchase((select supplier_text='Buyer request-local supplier' from public.purchase_requisitions where id=r),'Purchasing edit independent of supplier edit');
 perform set_config('request.jwt.claim.sub',other::text,true);
 delete from public.user_permissions where factory_id=f and user_id=other and module in('purchasing','suppliers');
 foreach state in array array['REJECTED','NEEDS_CLARIFICATION','CANCELLED','supplier'] loop
  perform pg_temp.fail_purchase(format('select pg_temp.purchase_change(%L,%L,%L,%L)',f,r,state,'Forged reason'),'permission_denied','requester cannot manage Purchasing actions');
 end loop;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 perform pg_temp.purchase_change(f,r,'NEEDS_CLARIFICATION','Specify the required grade.');
 perform pg_temp.check_purchase((select purchasing_note='Specify the required grade.' and status='NEEDS_CLARIFICATION' from public.purchase_requisitions where id=r),'valid clarification remains protected and audited');
 perform pg_temp.purchase_change(f,r,'clarify','Grade B');perform pg_temp.purchase_change(f,r,'REJECTED','Grade not available.');
 perform pg_temp.check_purchase((select status='REJECTED' and purchasing_note='Grade not available.' from public.purchase_requisitions where id=r),'valid rejection remains protected and audited');
 set constraints all immediate;
end$test$;
select format('Purchasing contextual suppliers: %s assertions passed; fixtures rolled back',count(*)) result from purchasing_checks;
rollback;
