-- Local correction-policy foundation. Does not activate recording or Maintenance.
begin;

-- orders:approve already exists and has no other production command consumer.
-- Engineering packages provision stored grants; titles never authorize requests.
create or replace function private.seed_permission_packages(f uuid) returns void language plpgsql security definer set search_path='' as $$
declare item record;p uuid;keys text[];begin
 for item in select * from (values
 ('owner','Factory Owner / Admin','مالك المصنع / الإدارة',null::text[]),
 ('production_manager','Production Manager','مدير الإنتاج',array['factory:view','dashboard:view','lines:view','centers:view','orders:view','orders:create','orders:edit','machine_status:edit','downtime:view','downtime:edit','maintenance:view','maintenance:create','maintenance:edit','reports:view','reports:export']),
 ('production_engineer','Production Engineer','مهندس الإنتاج',array['factory:view','dashboard:view','lines:view','centers:view','centers:edit','orders:view','orders:edit','orders:approve','machine_status:edit','downtime:view','downtime:edit','maintenance:view','maintenance:create','reports:view']),
 ('quality_engineer','Quality Engineer','مهندس الجودة',array['factory:view','orders:view','orders:approve']),
 ('planning_engineer','Planning Engineer','مهندس التخطيط',array['factory:view','dashboard:view','lines:view','centers:view','orders:view','orders:edit']),
 ('maintenance','Maintenance','الصيانة',array['factory:view','dashboard:view','lines:view','centers:view','downtime:view','maintenance:view','maintenance:create','maintenance:edit']),
 ('warehouse','Warehouse','المستودع',array['factory:view','dashboard:view','warehouse:view','warehouse:edit','warehouse:issue','orders:view']),
 ('purchasing','Purchasing','المشتريات',array['factory:view','dashboard:view','purchasing:view','purchasing:create','purchasing:edit','suppliers:edit']),
 ('sales','Sales','المبيعات',array['factory:view','dashboard:view','sales_orders:view','sales_orders:create','sales_orders:edit','sales_orders:approve'])
 )x(key,en,ar,grants) loop
  insert into public.permission_packages(factory_id,name,name_ar,template_key) values(f,item.en,item.ar,item.key)
  on conflict(factory_id,template_key) do nothing returning id into p;
  if p is not null then
   keys:=item.grants;
   insert into public.permission_package_permissions(factory_id,package_id,module,action)
   select f,p,module,action from public.permissions where keys is null or module||':'||action=any(keys);
  end if;
 end loop;
end$$;
-- One-time policy default for existing engineering packages. Later revocation
-- is never reapplied by seeding; direct grants and assignments are untouched.
insert into public.permission_package_permissions(factory_id,package_id,module,action)
 select factory_id,id,'orders','approve' from public.permission_packages where template_key='production_engineer'
 on conflict(factory_id,package_id,module,action) do nothing;
do $$declare f uuid;begin for f in select id from public.factories loop perform private.seed_permission_packages(f);end loop;end$$;

create table private.production_correction_requests(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories,
 submission_id uuid not null,entry_id uuid not null,
 base_values jsonb not null,proposed jsonb not null,allocations jsonb not null,
 requested_by uuid not null references auth.users,requested_at timestamptz not null default clock_timestamp(),
 legacy boolean not null default false,status text not null default 'PENDING' check(status in ('PENDING','APPROVED','REJECTED')),
 revision integer not null default 1,reviewed_by uuid references auth.users,reviewed_at timestamptz,
 rejection_reason text,correction_id uuid references public.production_entry_corrections,applied_values jsonb,
 unique(factory_id,submission_id),unique(factory_id,id),
 foreign key(factory_id,entry_id) references public.production_entries(factory_id,id),
 check((length(btrim(proposed->>'reason')) between 3 and 2000) is true),
 check(((status='PENDING' and revision=1 and reviewed_by is null and reviewed_at is null and rejection_reason is null and correction_id is null and applied_values is null)
 or (status='APPROVED' and revision=2 and reviewed_by is not null and reviewed_at>=requested_at and rejection_reason is null and correction_id is not null and applied_values is not null)
 or (status='REJECTED' and revision=2 and reviewed_by is not null and reviewed_at>=requested_at and length(btrim(rejection_reason)) between 3 and 2000 and correction_id is null and applied_values is null)) is true)
);
create index on private.production_correction_requests(factory_id,requested_at,id);
create index on private.production_correction_requests(factory_id,entry_id);
create index on private.production_correction_requests(factory_id,status,requested_at,id);
create unique index on private.production_correction_requests(correction_id) where correction_id is not null;
alter table private.production_correction_requests enable row level security;
revoke all on private.production_correction_requests from public,anon,authenticated;

create function private.production_correction_authorize(f uuid,approval boolean) returns void language plpgsql volatile security definer set search_path='' as $$
declare stamp timestamptz:=clock_timestamp();begin
 perform private.require_permission(f,'orders','view');
 if approval then perform private.require_permission(f,'orders','approve');
 elsif not(private.has_permission(f,'orders','edit') or private.has_permission(f,'orders','approve')) then raise exception 'permission_denied' using errcode='42501';end if;
 if not ((private.is_platform_admin() and exists(select 1 from private.platform_scopes where factory_id=f and user_id=auth.uid() and expires_at>stamp))
 or (exists(select 1 from public.memberships where factory_id=f and user_id=auth.uid() and status='approved')
 or exists(select 1 from public.support_access where factory_id=f and user_id=auth.uid() and (mode='permanent' or (mode='temporary' and expires_at>stamp))))
 and exists(select 1 from private.effective_person_permissions(f,auth.uid()) where module='orders' and action='view')
 and exists(select 1 from private.effective_person_permissions(f,auth.uid()) where module='orders' and (action='approve' or (not approval and action='edit'))))
 then raise exception 'permission_denied' using errcode='42501';end if;
end$$;

create function private.production_correction_values(f uuid,i uuid) returns jsonb language sql stable security definer set search_path='' set timezone='UTC' as $$
 select jsonb_build_object('entry_id',e.id,'item_id',e.order_id,'request_id',e.production_request_id,'product_id',e.product_id,'line_id',e.line_id,'unit',e.unit,
 'original_good',e.good_quantity::text,'original_scrap_kg',e.original_scrap_kg::text,'original_wip',e.unfinished_quantity::text,
 'original_occurrence_key',e.original_occurrence_key,'good',e.effective_good::text,'discarded_quantity',e.effective_scrap::text,
 'scrap_kg',e.effective_scrap_kg::text,'startup_kg',e.effective_startup_kg::text,'unfinished',e.effective_unfinished::text,
 'remaining_work',e.effective_remaining_work,'shift',e.shift_id,'occurrence_key',e.effective_occurrence_key,
 'period_start',e.effective_period_start,'period_end',e.effective_period_end,
 'correction_revision',(select count(*)::text from public.production_entry_corrections c where c.factory_id=f and c.entry_id=e.id),
 'quality_rejected',e.quality_rejected::text)
 from private.production_reporting_entries e where e.factory_id=f and e.id=i
$$;

create function private.production_correction_payload(p jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
declare k text;n numeric;result jsonb;begin
 if p is null or jsonb_typeof(p)<>'object' or octet_length(p::text)>12000
 or exists(select 1 from jsonb_object_keys(p) as keys(key) where keys.key not in ('entry','good','discarded_quantity','scrap_kg','startup_kg','reason','confirm_overproduction','shift','change_shift','unfinished','remaining_work','corrected_occurrence_key'))
 or jsonb_typeof(p->'reason') is distinct from 'string' or length(btrim(p->>'reason')) not between 3 and 2000
 then raise exception 'correction_invalid' using errcode='22023';end if;
 result:=jsonb_build_object('entry',(p->>'entry')::uuid,'reason',p->>'reason','startup_kg','0','unfinished','0','remaining_work',coalesce(p->>'remaining_work',''),
 'confirm_overproduction',coalesce((p->>'confirm_overproduction')::boolean,false),'change_shift',coalesce((p->>'change_shift')::boolean,false),'shift',(p->>'shift')::uuid);
 if result->>'entry' is null or length(result->>'remaining_work')>2000 then raise exception 'correction_invalid' using errcode='22023';end if;
 foreach k in array array['good','discarded_quantity','scrap_kg','startup_kg','unfinished'] loop
  n:=coalesce((p->>k)::numeric,case when k in ('startup_kg','unfinished') then 0 end);
  if n is null or n<0 or n::text in ('NaN','Infinity','-Infinity') then raise exception 'correction_invalid' using errcode='22023';end if;
  result:=result||jsonb_build_object(k,trim_scale(n)::text);
 end loop;
 if (result->>'startup_kg')::numeric>(result->>'scrap_kg')::numeric then raise exception 'correction_invalid' using errcode='22023';end if;
 if p ? 'corrected_occurrence_key' then
  if coalesce(p->>'corrected_occurrence_key','') !~ '^[0-9a-f]{64}$' then raise exception 'correction_invalid' using errcode='22023';end if;
  result:=result||jsonb_build_object('corrected_occurrence_key',p->>'corrected_occurrence_key');
 end if;
 return result;
exception when invalid_text_representation or numeric_value_out_of_range then raise exception 'correction_invalid' using errcode='22023';
end$$;

create function private.production_correction_allocations(a jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
declare v jsonb;q numeric;result jsonb:='[]';begin
 if a is null or jsonb_typeof(a)<>'array' or jsonb_array_length(a)>100 or octet_length(a::text)>18000 then raise exception 'correction_invalid' using errcode='22023';end if;
 for v in select * from jsonb_array_elements(a) loop
  if jsonb_typeof(v)<>'object' or not(v ?& array['source_id','quantity']) or exists(select 1 from jsonb_object_keys(v)k where k not in ('source_id','quantity')) then raise exception 'correction_invalid' using errcode='22023';end if;
  q:=(v->>'quantity')::numeric;
  if q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity') then raise exception 'correction_invalid' using errcode='22023';end if;
  result:=result||jsonb_build_array(jsonb_build_object('source_id',(v->>'source_id')::uuid,'quantity',trim_scale(q)::text));
 end loop;
 return result;
exception when invalid_text_representation or numeric_value_out_of_range then raise exception 'correction_invalid' using errcode='22023';
end$$;

create function private.production_correction_request_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' or old.status<>'PENDING' or new.status not in ('APPROVED','REJECTED')
 or (to_jsonb(new)-array['status','revision','reviewed_by','reviewed_at','rejection_reason','correction_id','applied_values'])
 is distinct from (to_jsonb(old)-array['status','revision','reviewed_by','reviewed_at','rejection_reason','correction_id','applied_values'])
 or new.reviewed_by is distinct from auth.uid() then raise exception 'correction_audit_immutable' using errcode='23514';end if;
 if new.status='APPROVED' and not exists(select 1 from public.production_entry_corrections c where c.id=new.correction_id and c.factory_id=new.factory_id
 and c.entry_id=new.entry_id and c.created_by=new.reviewed_by and c.reason=new.proposed->>'reason')
 then raise exception 'correction_audit_invalid' using errcode='23514';end if;
 return new;
end$$;
create trigger correction_request_guard before update or delete on private.production_correction_requests for each row execute function private.production_correction_request_guard();
create trigger correction_request_audit after insert or update on private.production_correction_requests for each row execute function private.audit_change();
create function private.production_correction_ledger_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from private.production_correction_requests r where r.correction_id=old.id and r.status='APPROVED')
 then raise exception 'correction_audit_immutable' using errcode='23514';end if;
 if tg_op='DELETE' then return old;end if;return new;
end$$;
create trigger correction_approved_ledger_guard before update or delete on public.production_entry_corrections for each row execute function private.production_correction_ledger_guard();

create function private.apply_production_correction_request(f uuid,i uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare row private.production_correction_requests;current_values jsonb;result uuid;started_pick boolean:=false;begin
 perform private.production_correction_authorize(f,true);
 select * into row from private.production_correction_requests where factory_id=f and id=i for update;
 if row.id is null then raise exception 'not_found' using errcode='P0002';end if;
 if row.status='APPROVED' then return row.correction_id;end if;
 if row.status<>'PENDING' then raise exception 'correction_conflict' using errcode='40001';end if;
 current_values:=private.production_correction_values(f,row.entry_id);
 if current_values is distinct from row.base_values then raise exception 'correction_stale' using errcode='40001';end if;
 if not row.legacy and (row.proposed->>'good')::numeric<(current_values->>'good')::numeric then
  perform private.source_begin_pick(f,'production_correction',(current_values->>'product_id')::uuid,current_values->>'unit',row.entry_id,row.allocations);started_pick:=true;
 end if;
 result:=private.apply_approved_production_correction(f,row.proposed,row.submission_id);
 if started_pick then perform private.source_end_pick();end if;
 set constraints public.lean_entry_physical_output,public.quality_entry_weight_check,public.source_balance_conservation,public.source_receipt_conservation,public.recording_receipt_finalized immediate;
 set constraints public.lean_entry_physical_output,public.quality_entry_weight_check,public.source_balance_conservation,public.source_receipt_conservation,public.recording_receipt_finalized deferred;
 perform private.production_correction_authorize(f,true);
 update private.production_correction_requests set status='APPROVED',revision=2,reviewed_by=auth.uid(),reviewed_at=clock_timestamp(),
 correction_id=result,applied_values=private.production_correction_values(f,row.entry_id) where id=i;
 return result;
end$$;

create function private.submit_production_correction(f uuid,p jsonb,a jsonb,r uuid,expected bigint,legacy boolean default false) returns uuid
language plpgsql security definer set search_path='' as $$
declare q jsonb:=private.production_correction_payload(p);picks jsonb:=private.production_correction_allocations(a);intent jsonb;
 old uuid;result uuid;base jsonb;approve boolean;historical uuid;begin
 if current_setting('transaction_isolation')<>'read committed' then raise exception 'correction_isolation' using errcode='22023';end if;
 if r is null or (not legacy and (expected is null or expected<0)) then raise exception 'correction_invalid' using errcode='22023';end if;
 perform private.production_correction_authorize(f,legacy);
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));
 perform pg_advisory_xact_lock(hashtextextended(f::text||':structure',0));
 perform private.production_correction_authorize(f,legacy);
 intent:=jsonb_build_object('payload',q,'allocations',picks,'expected_revision',expected,'legacy',legacy);
 old:=private.fulfillment_retry(f,r,'production_correction_submit',intent);
 if old is not null then return old;end if;
 -- Pre-policy committed corrections remain historical facts, without inventing
 -- retrospective approval evidence. The original worker validates exact retry.
 select id into historical from public.production_entry_corrections where factory_id=f and request_id=r;
 if historical is not null then
  if not legacy then raise exception 'correction_conflict' using errcode='40001';end if;
  perform private.apply_approved_production_correction(f,q,r);
  perform private.production_correction_authorize(f,true);
  return null;
 end if;
 base:=private.production_correction_values(f,(q->>'entry')::uuid);
 if base is null then raise exception 'not_found' using errcode='P0002';end if;
 if not legacy and (base->>'correction_revision')::bigint<>expected then raise exception 'correction_stale' using errcode='40001';end if;
 if not legacy and ((q->>'good')::numeric<(base->>'good')::numeric) is distinct from (jsonb_array_length(picks)>0)
 then raise exception 'source_selection_required' using errcode='22023';end if;
 if not legacy and jsonb_array_length(picks)>0 and (select sum((v->>'quantity')::numeric) from jsonb_array_elements(picks)v)<>(base->>'good')::numeric-(q->>'good')::numeric
 then raise exception 'source_quantity' using errcode='22023';end if;
 insert into private.production_correction_requests(factory_id,submission_id,entry_id,base_values,proposed,allocations,requested_by,legacy)
 values(f,r,(q->>'entry')::uuid,base,q,picks,auth.uid(),legacy) returning id into result;
 approve:=private.has_permission(f,'orders','approve');
 if approve then perform private.apply_production_correction_request(f,result);end if;
 insert into public.fulfillment_commands values(f,r,auth.uid(),'production_correction_submit',intent,result,clock_timestamp());
 perform private.production_correction_authorize(f,legacy or approve);
 return result;
end$$;

-- Existing UUID-returning callers cannot render PENDING. Fail closed rather
-- than report a technician proposal as saved; future UI uses the new contract.
create or replace function private.correct_lean_production(f uuid,p jsonb,r uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;correction uuid;picks jsonb:='[]';begin
 select c.picks into picks from private.finished_goods_pick_context c where c.backend=pg_backend_pid() and c.transaction_id=txid_current()
 and c.factory_id=f and c.actor_id=auth.uid() and c.kind='production_correction' and c.entry_id=(p->>'entry')::uuid;
 result:=private.submit_production_correction(f,p,coalesce(picks,'[]'),r,null,true);
 if result is null then select id into correction from public.production_entry_corrections where factory_id=f and request_id=r;
 else select correction_id into correction from private.production_correction_requests where factory_id=f and id=result;end if;
 return correction;
end$$;
create or replace function public.correct_lean_production(factory uuid,payload jsonb,request_id uuid) returns uuid language sql security invoker set search_path='' as $$select private.correct_lean_production(factory,payload,request_id)$$;

create function public.production_correction_command(factory uuid,operation text,payload jsonb,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare row private.production_correction_requests;target uuid;old uuid;intent jsonb;reason text;begin
 if current_setting('transaction_isolation')<>'read committed' or request_id is null or payload is null or jsonb_typeof(payload)<>'object' or octet_length(payload::text)>30000
 or operation not in ('submit','approve','reject') then raise exception 'correction_invalid' using errcode='22023';end if;
 if operation='submit' then
  if not(payload ? 'expected_revision') or jsonb_typeof(payload->'expected_revision') not in ('number','string') or (payload->>'expected_revision') !~ '^[0-9]+$'
  then raise exception 'correction_invalid' using errcode='22023';end if;
  target:=private.submit_production_correction(factory,payload-array['allocations','expected_revision'],coalesce(payload->'allocations','[]'),request_id,(payload->>'expected_revision')::bigint,false);
 else
  if exists(select 1 from jsonb_object_keys(payload)k where k not in ('id','reason')) or not(payload ? 'id') or (operation='approve' and payload ? 'reason') then raise exception 'correction_invalid' using errcode='22023';end if;
  reason:=payload->>'reason';
  if operation='reject' and (jsonb_typeof(payload->'reason') is distinct from 'string' or length(btrim(reason)) not between 3 and 2000) then raise exception 'correction_invalid' using errcode='22023';end if;
  perform private.production_correction_authorize(factory,true);
  perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform pg_advisory_xact_lock(hashtextextended(factory::text||':structure',0));
  perform private.production_correction_authorize(factory,true);
  intent:=jsonb_build_object('operation',operation,'payload',payload);
  old:=private.fulfillment_retry(factory,request_id,'production_correction_decide',intent);
  target:=coalesce(old,(payload->>'id')::uuid);
  select * into row from private.production_correction_requests where factory_id=factory and production_correction_requests.id=target for update;
  if row.id is null then raise exception 'not_found' using errcode='P0002';end if;
  if old is null then
   if operation='approve' then perform private.apply_production_correction_request(factory,target);
   elsif row.status='PENDING' then
    update private.production_correction_requests set status='REJECTED',revision=2,reviewed_by=auth.uid(),reviewed_at=clock_timestamp(),rejection_reason=reason where production_correction_requests.id=target;
   elsif row.status<>'REJECTED' or row.rejection_reason is distinct from reason then raise exception 'correction_conflict' using errcode='40001';end if;
   insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'production_correction_decide',intent,target,clock_timestamp());
  end if;
  perform private.production_correction_authorize(factory,true);
 end if;
 select * into row from private.production_correction_requests where factory_id=factory and production_correction_requests.id=target;
 return jsonb_build_object('contract_version',1,'id',row.id,'entry_id',row.entry_id,'status',row.status,'correction_id',row.correction_id,
 'requested_by',row.requested_by,'requested_at',row.requested_at,'reviewed_by',row.reviewed_by,'reviewed_at',row.reviewed_at,'revision',row.revision,
 'original_values',row.base_values,'proposed',row.proposed,'applied_values',row.applied_values,'rejection_reason',row.rejection_reason);
exception when invalid_text_representation or numeric_value_out_of_range then raise exception 'correction_invalid' using errcode='22023';
end$$;

create function public.production_correction_read(factory uuid,query jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path='' set timezone='UTC' as $$
declare size integer:=coalesce((query->>'page_size')::integer,50);c jsonb:=query->'cursor';fp text;rev text;after_at timestamptz;after_id uuid;reviewer boolean;result jsonb;begin
 perform private.require_permission(factory,'orders','view');reviewer:=private.has_permission(factory,'orders','approve');
 if query is null or jsonb_typeof(query)<>'object' or octet_length(query::text)>6000 or size not between 1 and 100
 or exists(select 1 from jsonb_object_keys(query)k where k not in ('id','request_id','entry','status','page_size','cursor'))
 or (query ? 'status' and query->>'status' not in ('PENDING','APPROVED','REJECTED')) then raise exception 'correction_invalid' using errcode='22023';end if;
 perform (query->>'id')::uuid,(query->>'request_id')::uuid,(query->>'entry')::uuid;
 select count(*)::text||':'||coalesce(sum(revision),0)::text||':'||coalesce((select revision::text from private.lean_source_state where factory_id=factory),'0') into rev
 from private.production_correction_requests where factory_id=factory;
 fp:=encode(sha256(convert_to(jsonb_build_array(factory,auth.uid(),query-'cursor',reviewer)::text,'UTF8')),'hex');
 if c is not null then
  if jsonb_typeof(c)<>'object' or not(c ?& array['version','factory','actor','query_hash','revision','after_at','after_id'])
  or (select count(*) from jsonb_object_keys(c))<>7 or c->>'version' is distinct from '1' or c->>'factory' is distinct from factory::text
  or c->>'actor' is distinct from auth.uid()::text or c->>'query_hash' is distinct from fp or c->>'revision' is distinct from rev
  then raise exception 'correction_stale_cursor' using errcode='40001';end if;
  after_at:=(c->>'after_at')::timestamptz;after_id:=(c->>'after_id')::uuid;
  if after_at is null or after_id is null then raise exception 'correction_invalid' using errcode='22023';end if;
 end if;
 with selected as materialized(select r.* from private.production_correction_requests r where r.factory_id=factory and (reviewer or r.requested_by=auth.uid())
 and (not(query ? 'id') or r.id=(query->>'id')::uuid) and (not(query ? 'request_id') or r.submission_id=(query->>'request_id')::uuid)
 and (not(query ? 'entry') or r.entry_id=(query->>'entry')::uuid) and (not(query ? 'status') or r.status=query->>'status')),
 page as materialized(select * from selected where after_at is null or (requested_at,id)>(after_at,after_id) order by requested_at,id limit size+1),
 visible as materialized(select * from page order by requested_at,id limit size)
 select jsonb_build_object('contract_version',1,'factory_id',factory,'total',(select count(*) from selected),'page_size',size,'complete',(select count(*)<=size from page),
 'rows',coalesce((select jsonb_agg((to_jsonb(v)-'base_values')||jsonb_build_object('original_values',v.base_values,'current_values',private.production_correction_values(factory,v.entry_id)) order by requested_at,id) from visible v),'[]'),
 'next_cursor',case when (select count(*)>size from page) then (select jsonb_build_object('version',1,'factory',factory,'actor',auth.uid(),'query_hash',fp,'revision',rev,'after_at',requested_at,'after_id',id) from visible order by requested_at desc,id desc limit 1) end) into result;
 return result;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then raise exception 'correction_invalid' using errcode='22023';
end$$;

revoke all on function private.seed_permission_packages(uuid),private.production_correction_authorize(uuid,boolean),private.production_correction_values(uuid,uuid),
 private.production_correction_payload(jsonb),private.production_correction_allocations(jsonb),private.production_correction_request_guard(),private.production_correction_ledger_guard(),
 private.apply_production_correction_request(uuid,uuid),private.submit_production_correction(uuid,jsonb,jsonb,uuid,bigint,boolean),
 public.production_correction_command(uuid,text,jsonb,uuid),public.production_correction_read(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.production_correction_command(uuid,text,jsonb,uuid),public.production_correction_read(uuid,jsonb) to authenticated;

-- Existing quantity and M2 attribution workers follow verbatim, changing only
-- their correction-specific authorization from Orders edit to Orders approve.
-- Their arithmetic, source/Quality guards, reasons and posting are unchanged.
CREATE OR REPLACE FUNCTION private.correct_production(f uuid, e uuid, good numeric, scrap numeric, reason text, confirmed boolean, r uuid, shift uuid, change_shift boolean, unfinished numeric, work_note text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare original public.production_entries;job public.production_orders;previous public.production_entry_corrections;result uuid;total numeric;new_shift uuid;lot public.unfinished_lots;delta numeric;new_lot uuid;
begin
 perform private.require_permission(f,'orders','approve');
 perform private.require_permission(f,'orders','view');
 if r is null or good is null or scrap is null or good<0 or scrap<0
   or good::text in ('NaN','Infinity','-Infinity') or scrap::text in ('NaN','Infinity','-Infinity')
   or length(trim(coalesce(reason,''))) not between 3 and 2000 then raise exception 'recording_correction_reason';end if;
 if unfinished is not null and (unfinished<0 or unfinished::text in ('NaN','Infinity','-Infinity') or (unfinished>0 and length(trim(coalesce(work_note,''))) not between 3 and 2000)) then raise exception 'unfinished_invalid';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(f::text||':structure',0));
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(f::text||r::text,0));
 select * into previous from public.production_entry_corrections c where c.factory_id=f and c.request_id=r;
 if found then
   if previous.entry_id<>e or previous.corrected_good<>good or previous.corrected_scrap<>scrap or previous.reason<>reason
     or (unfinished is not null and coalesce(previous.corrected_unfinished,0)<>unfinished)
     or (work_note is not null and previous.corrected_remaining_work is distinct from trim(work_note))
     or previous.shift_changed is distinct from change_shift or (change_shift and previous.corrected_shift_id is distinct from shift) or previous.created_by<>auth.uid() or previous.overproduction_confirmed<>coalesce(confirmed,false) then raise exception 'request_conflict';end if;
   return previous.id;
 end if;
 select * into original from public.production_entries x where x.factory_id=f and x.id=e;
 if not found then raise exception 'invalid_order';end if;
 select * into job from public.production_orders o where o.factory_id=f and o.id=original.order_id for update;
 select * into original from public.production_entries x where x.factory_id=f and x.id=e for update;
 unfinished:=coalesce(unfinished,original.effective_unfinished,0);
 work_note:=coalesce(trim(work_note),original.effective_remaining_work,'');
 if unfinished>0 and (length(work_note) not between 3 and 2000 or original.unit not in ('meter','piece','kg') or original.unit is null) then raise exception 'unfinished_invalid';end if;
 if original.input_lot_id is not null and good+scrap+unfinished<>original.input_quantity then raise exception 'unfinished_conservation';end if;
 select * into lot from public.unfinished_lots x where x.factory_id=f and x.source_entry_id=e and x.quality_rejection_id is null for update;
 delta:=unfinished-coalesce(original.effective_unfinished,0);
 if lot.id is not null and lot.quantity_available+delta<lot.warehouse_quantity then raise exception 'unfinished_already_consumed';end if;
 new_shift:=case when change_shift then shift else original.shift_id end;
 if change_shift and new_shift is distinct from original.shift_id then perform private.validate_production_shift(f,new_shift);end if;
 total:=job.fulfillment_good_quantity-original.effective_good+good;
 if total>job.target_quantity and not coalesce(confirmed,false) then raise exception 'recording_overproduction_confirmation';end if;
 insert into public.production_entry_corrections(factory_id,entry_id,previous_good,previous_scrap,corrected_good,corrected_scrap,reason,created_by,request_id,overproduction_confirmed,previous_shift_id,corrected_shift_id,shift_changed,previous_unfinished,corrected_unfinished,previous_remaining_work,corrected_remaining_work)
 values(f,e,original.effective_good,original.effective_scrap,good,scrap,reason,auth.uid(),r,coalesce(confirmed,false),original.shift_id,new_shift,coalesce(change_shift,false),coalesce(original.effective_unfinished,0),unfinished,original.effective_remaining_work,work_note) returning id into result;
 update public.production_orders set produced_quantity=produced_quantity-original.effective_good-original.effective_scrap+good+scrap,
   rejected_quantity=rejected_quantity-original.effective_scrap+scrap where id=job.id;
 update public.production_entries set effective_good=good,effective_scrap=scrap,shift_id=new_shift,effective_unfinished=unfinished,effective_remaining_work=work_note where id=e;
 if lot.id is null and unfinished>0 then
   insert into public.unfinished_lots(factory_id,source_entry_id,quantity_created,quantity_available,remaining_work,created_at,created_by)
   values(f,e,unfinished,unfinished,work_note,clock_timestamp(),auth.uid()) returning id into new_lot;
 elsif lot.id is not null then
   new_lot:=lot.id;
   update public.unfinished_lots set quantity_created=quantity_created+delta,quantity_available=quantity_available+delta,
   remaining_work=case when unfinished>0 then work_note else remaining_work end where id=lot.id;
 end if;
 if new_lot is not null and delta<>0 then
   insert into public.unfinished_movements(factory_id,lot_id,entry_id,correction_id,kind,quantity,created_by)
   values(f,new_lot,e,result,'corrected',delta,auth.uid());
 end if;
 return result;
end$function$;

CREATE OR REPLACE FUNCTION private.apply_approved_production_correction(f uuid, p jsonb, r uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare e public.production_entries;correction public.production_entry_corrections;result uuid;mass numeric;startup_mass numeric;target private.production_shift_occurrences;period_start timestamptz;period_end timestamptz;job public.production_orders;
begin
 perform private.require_permission(f,'orders','approve');perform private.require_permission(f,'orders','view');
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));
 perform private.require_permission(f,'orders','approve');perform private.require_permission(f,'orders','view');
 if p is null or jsonb_typeof(p)<>'object' or exists(select 1 from jsonb_object_keys(p) key where key not in
 ('entry','good','discarded_quantity','scrap_kg','startup_kg','reason','confirm_overproduction','shift','change_shift','unfinished','remaining_work','corrected_occurrence_key')) then raise exception 'lean_invalid' using errcode='22023';end if;
 select * into e from public.production_entries where factory_id=f and id=(p->>'entry')::uuid;
 if not found then raise exception 'not_found' using errcode='P0002';end if;
 if e.attribution_version=1 and coalesce((p->>'change_shift')::boolean,false) then
  select * into target from private.production_shift_occurrences where factory_id=f and occurrence_key=p->>'corrected_occurrence_key';
  select * into job from public.production_orders where factory_id=f and id=e.order_id;
  period_start:=greatest(e.execution_started_at,target.starts_at);
  period_end:=least(coalesce(job.actual_finish,e.created_at),e.created_at,target.ends_at);
  if target.occurrence_key is null or target.shift_id is distinct from (p->>'shift')::uuid or period_end<=period_start
  then raise exception 'recording_dated_correction_required' using errcode='22023';end if;
 elsif p ? 'corrected_occurrence_key' then raise exception 'recording_dated_correction_invalid' using errcode='22023';end if;
 mass:=(p->>'scrap_kg')::numeric;startup_mass:=coalesce((p->>'startup_kg')::numeric,0);
 if mass is null or mass<0 or startup_mass<0 or startup_mass>mass or mass::text in ('NaN','Infinity','-Infinity') or startup_mass::text in ('NaN','Infinity','-Infinity') or (startup_mass>0 and e.lean_startup_id is null) then raise exception 'lean_invalid' using errcode='22023';end if;
 select * into correction from public.production_entry_corrections where factory_id=f and request_id=r;
 if found and (correction.corrected_scrap_kg is distinct from mass or correction.corrected_startup_kg is distinct from startup_mass) then raise exception 'recording_request_reused' using errcode='22023';end if;
 if correction.id is not null and e.attribution_version=1 and correction.corrected_occurrence_key is distinct from coalesce(target.occurrence_key,e.effective_occurrence_key)
 then raise exception 'request_conflict' using errcode='40001';end if;
 result:=private.correct_production(f,e.id,(p->>'good')::numeric,(p->>'discarded_quantity')::numeric,p->>'reason',coalesce((p->>'confirm_overproduction')::boolean,false),r,
 (p->>'shift')::uuid,coalesce((p->>'change_shift')::boolean,false),coalesce((p->>'unfinished')::numeric,0),coalesce(p->>'remaining_work',''));
 if correction.id is null then
  update public.production_entry_corrections set previous_scrap_kg=e.effective_scrap_kg,corrected_scrap_kg=mass,previous_startup_kg=e.effective_startup_kg,corrected_startup_kg=startup_mass where id=result;
  update public.production_entries set effective_scrap_kg=mass,effective_startup_kg=startup_mass,produced_weight_kg=(effective_good+coalesce(effective_unfinished,0))*weight_kg_per_unit where id=e.id;
 end if;
 if correction.id is null and e.attribution_version=1 then
  update public.production_entry_corrections set previous_occurrence_key=e.effective_occurrence_key,
   corrected_occurrence_key=coalesce(target.occurrence_key,e.effective_occurrence_key),previous_period_start=e.effective_period_start,previous_period_end=e.effective_period_end,
   corrected_period_start=coalesce(period_start,e.effective_period_start),corrected_period_end=coalesce(period_end,e.effective_period_end),
   attribution_changed=target.occurrence_key is not null and target.occurrence_key is distinct from e.effective_occurrence_key where id=result;
  update public.production_entries set effective_occurrence_key=coalesce(target.occurrence_key,e.effective_occurrence_key),
   effective_period_start=coalesce(period_start,e.effective_period_start),effective_period_end=coalesce(period_end,e.effective_period_end) where id=e.id;
 end if;
 return result;
end$function$;
revoke all on function private.apply_approved_production_correction(uuid,jsonb,uuid) from public,anon,authenticated;

commit;
