-- Inactive manufactured-output foundation. No current writer, inventory trigger,
-- permission assignment, receipt path or activation setting is replaced.
-- Private primitives require a future protected recording/posting adapter.
begin;

create table private.manufactured_outputs (
 id uuid primary key default gen_random_uuid(), factory_id uuid not null,
 entry_id uuid not null, item_id uuid not null, product_id uuid not null, unit text not null,
 posting_version text not null default 'RECEIPT_V1' check(posting_version='RECEIPT_V1'),
 source_snapshot jsonb not null, operation_snapshot jsonb not null, recorded_groups jsonb not null,
 quantity numeric not null check(quantity>0 and quantity::text not in ('NaN','Infinity','-Infinity')),
 created_by uuid not null references auth.users, created_at timestamptz not null default clock_timestamp(),
 unique(factory_id,id), unique(factory_id,entry_id),
 foreign key(factory_id,entry_id) references public.production_entries(factory_id,id),
 foreign key(factory_id,item_id) references public.production_orders(factory_id,id),
 foreign key(factory_id,product_id) references public.products(factory_id,id)
);
create table private.manufactured_output_events (
 id uuid primary key default gen_random_uuid(), factory_id uuid not null, output_id uuid not null,
 request_id uuid not null, revision bigint not null check(revision>0),
 operation text not null check(operation in ('DECLARE','QUALITY','RECEIPT','DISPOSITION','ACKNOWLEDGE')),
 intent jsonb not null, result jsonb not null,
 finished_movement_id uuid references public.finished_goods_movements(id),
 unfinished_movement_id uuid references public.unfinished_movements(id),
 created_by uuid not null references auth.users, created_at timestamptz not null default clock_timestamp(),
 unique(factory_id,request_id), unique(factory_id,output_id,revision),
 unique(finished_movement_id), unique(unfinished_movement_id),
 foreign key(factory_id,output_id) references private.manufactured_outputs(factory_id,id),
 check((operation='RECEIPT' and num_nonnulls(finished_movement_id,unfinished_movement_id)=1)
    or (operation<>'RECEIPT' and num_nonnulls(finished_movement_id,unfinished_movement_id)=0))
);
alter table private.manufactured_outputs enable row level security;
alter table private.manufactured_output_events enable row level security;
revoke all on private.manufactured_outputs,private.manufactured_output_events from public,anon,authenticated,service_role;

create function private.manufactured_output_immutable() returns trigger language plpgsql set search_path='' as $$begin
 raise exception 'manufactured_output_immutable' using errcode='23514';
end$$;
create trigger immutable before update or delete on private.manufactured_outputs for each row execute function private.manufactured_output_immutable();
create trigger immutable before update or delete on private.manufactured_output_events for each row execute function private.manufactured_output_immutable();

create function private.manufactured_output_authorize(f uuid,op text,expected bigint) returns void
 language plpgsql volatile security definer set search_path='' as $$begin
 if auth.uid() is null then raise exception 'permission_denied' using errcode='42501';end if;
 perform private.require_permission(f,'factory','view');
 if not ((private.is_platform_admin() and exists(select 1 from private.platform_scopes where factory_id=f and user_id=auth.uid() and expires_at>clock_timestamp()))
 or exists(select 1 from public.memberships where factory_id=f and user_id=auth.uid() and status='approved')
 or exists(select 1 from public.support_access where factory_id=f and user_id=auth.uid() and (mode='permanent' or (mode='temporary' and expires_at>clock_timestamp()))))
 then raise exception 'permission_denied' using errcode='42501';end if;
 if op='QUALITY' then
  perform private.require_permission(f,'quality','view');
  perform private.require_permission(f,'quality',case when expected>1 then 'edit' else 'create' end);
 elsif op='RECEIPT' then perform private.require_permission(f,'warehouse','edit');
 elsif op in ('DECLARE','DISPOSITION') then
  perform private.require_permission(f,'orders','view');perform private.require_permission(f,'orders','edit');
 elsif op='ACKNOWLEDGE' then perform private.require_permission(f,'orders','view');
 else raise exception 'output_invalid';end if;
end$$;

-- Operations are configured work-center step identities, not a computed route.
-- Freeze names/context at declaration; do not infer operations from capabilities.
create function private.manufactured_output_groups(groups jsonb,operations jsonb,u text,release_allowed boolean) returns jsonb
 language plpgsql immutable set search_path='' as $$
declare g jsonb;v jsonb;ids uuid[];result jsonb:='[]';q numeric;released numeric;seen uuid[]:='{}';gid uuid;begin
 if groups is null or jsonb_typeof(groups)<>'array' or jsonb_array_length(groups)>100 then raise exception 'output_groups';end if;
 for g in select value from jsonb_array_elements(groups) loop
  if jsonb_typeof(g)<>'object' or not g ?& array['id','quantity','missing_operations']
   or exists(select 1 from jsonb_object_keys(g) k where k not in ('id','quantity','missing_operations','released','restriction'))
   or jsonb_typeof(g->'missing_operations')<>'array' or jsonb_array_length(g->'missing_operations')>100 then raise exception 'output_groups';end if;
  gid:=(g->>'id')::uuid;q:=(g->>'quantity')::numeric;released:=coalesce((g->>'released')::numeric,0);
  if gid is null or gid=any(seen) or q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity')
   or released<0 or released>q or released::text in ('NaN','Infinity','-Infinity')
   or (not release_allowed and released<>0) or (u='piece' and (q<>trunc(q) or released<>trunc(released)))
   or length(coalesce(g->>'restriction',''))>1000 then raise exception 'output_quantity';end if;
  seen:=array_append(seen,gid);
  select coalesce(array_agg(value::uuid order by value::uuid),'{}') into ids from jsonb_array_elements_text(g->'missing_operations');
  if cardinality(ids)<>(select count(distinct x) from unnest(ids) x)
   or exists(select 1 from unnest(ids) x where not operations ? x::text) then raise exception 'output_operations';end if;
  v:=jsonb_build_object('id',gid,'quantity',trim_scale(q)::text,'released',trim_scale(released)::text,
   'missing_operations',to_jsonb(ids),'restriction',coalesce(g->>'restriction',''));
  result:=result||jsonb_build_array(v);
 end loop;
 select coalesce(jsonb_agg(value order by value->>'id'),'[]') into result from jsonb_array_elements(result);
 return result;
end$$;

-- A stable source fingerprint includes corrections and prior Quality rejection.
-- Existing approved corrections remain unchanged for every unmarked legacy entry.
create function private.manufactured_output_source_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from private.manufactured_outputs where factory_id=old.factory_id and entry_id=old.id)
 and (to_jsonb(new)-array['updated_at']) is distinct from (to_jsonb(old)-array['updated_at']) then
  raise exception 'output_reconciliation_required' using errcode='23514';
 end if;return new;
end$$;
create trigger manufactured_output_source_guard before update on public.production_entries
 for each row execute function private.manufactured_output_source_guard();

-- Internal transaction primitive. DECLARE can ONLY adopt an entry inserted in
-- this transaction with no existing stock credit/location receipt. Ordinary
-- recording still credits Good, so cannot accidentally opt in to RECEIPT_V1.
-- RECEIPT binds a movement already posted in THE SAME TRANSACTION by a future
-- protected adapter. It never credits another ledger or claims a pending intent
-- is a receipt. The adapter must obtain factory/structure locks BEFORE posting.
create function private.manufactured_output_command(f uuid,op text,target uuid,p jsonb,expected bigint,retry uuid) returns jsonb
 language plpgsql volatile security definer set search_path='' as $$
declare h private.manufactured_outputs;previous private.manufactured_output_events;e public.production_entries;o public.production_orders;
 rev bigint;intent jsonb;result jsonb;groups jsonb;operations jsonb;g jsonb;quality jsonb;rejected numeric;q numeric;used numeric;total numeric;
 movement public.finished_goods_movements;wip public.unfinished_movements;lot public.unfinished_lots;movement_id uuid;wip_id uuid;record_id uuid;
begin
 if current_setting('transaction_isolation')<>'read committed' then raise exception 'output_isolation';end if;
 if f is null or target is null or retry is null or expected is null or expected<0 or p is null or jsonb_typeof(p)<>'object' or octet_length(p::text)>60000 then raise exception 'output_invalid';end if;
 perform private.manufactured_output_authorize(f,op,expected);
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));
 perform pg_advisory_xact_lock(hashtextextended(f::text||':structure',0));
 perform private.manufactured_output_authorize(f,op,expected);
 intent:=jsonb_build_object('operation',op,'target',target,'payload',p,'expected',expected);
 select * into previous from private.manufactured_output_events where factory_id=f and request_id=retry;
 if found then
  if previous.created_by<>auth.uid() or previous.intent<>intent then raise exception 'request_conflict';end if;
  return previous.result;
 end if;
 if op='DECLARE' then
  if expected<>0 or not p ? 'groups' or exists(select 1 from jsonb_object_keys(p) k where k<>'groups') then raise exception 'output_invalid';end if;
  select * into e from public.production_entries where factory_id=f and id=target for update;
  if not found then raise exception 'output_not_found';end if;
  if e.created_at<transaction_timestamp() or not exists(select 1 from public.production_entries where id=e.id and xmin::text=pg_current_xact_id()::text)
   or exists(select 1 from public.finished_goods_movements where factory_id=f and entry_id=e.id and stock_delta<>0)
   or exists(select 1 from public.finished_goods_entry_receipts where factory_id=f and entry_id=e.id and received_good<>0)
   or exists(select 1 from public.unfinished_lots where factory_id=f and source_entry_id=e.id and (warehouse_quantity<>0 or quantity_available<>quantity_created))
   or exists(select 1 from public.quality_rejections where factory_id=f and entry_id=e.id)
   or exists(select 1 from public.production_entry_corrections where factory_id=f and entry_id=e.id)
   then raise exception 'output_legacy_or_used';end if;
  select * into o from public.production_orders where factory_id=f and id=e.order_id;
  if o.product_id is null or e.unit not in ('meter','piece','kg') then raise exception 'output_identity';end if;
  select coalesce(jsonb_object_agg(s.id::text,jsonb_build_object('work_center_id',s.work_center_id,'name',c.name,'name_ar',c.name_ar)),'{}') into operations
   from public.production_routing_steps s join public.work_centers c on c.factory_id=s.factory_id and c.id=s.work_center_id
   where s.factory_id=f and s.product_id=o.product_id and s.kind='work_center';
  groups:=private.manufactured_output_groups(p->'groups',operations,e.unit,false);
  select coalesce(sum((value->>'quantity')::numeric),0) into q from jsonb_array_elements(groups) where jsonb_array_length(value->'missing_operations')=0;
  select coalesce(sum((value->>'quantity')::numeric),0) into total from jsonb_array_elements(groups);
  if q is distinct from e.effective_good or total-q<>coalesce(e.effective_unfinished,0) or total<=0 then raise exception 'output_conservation';end if;
  insert into private.manufactured_outputs(factory_id,entry_id,item_id,product_id,unit,source_snapshot,operation_snapshot,recorded_groups,quantity,created_by)
   values(f,e.id,o.id,o.product_id,e.unit,private.production_correction_values(f,e.id)||jsonb_build_object('technician_id',e.technician_id,'recorded_at',e.created_at),operations,groups,total,auth.uid()) returning * into h;
  rev:=1;result:=jsonb_build_object('output_id',h.id,'revision',rev,'posting_version',h.posting_version,'groups',groups);
 else
  select * into h from private.manufactured_outputs where factory_id=f and id=target for update;
  if not found then raise exception 'output_not_found';end if;
  if (h.source_snapshot-array['technician_id','recorded_at']) is distinct from private.production_correction_values(f,h.entry_id) then raise exception 'output_reinspection_required';end if;
  select max(revision) into rev from private.manufactured_output_events where factory_id=f and output_id=h.id;
  if rev is distinct from expected then raise exception 'output_revision';end if;
  select ev.result into quality from private.manufactured_output_events ev where factory_id=f and output_id=h.id and operation='QUALITY' order by revision desc limit 1;
  rev:=rev+1;
  if op='QUALITY' then
   if not p ?& array['groups','rejected','reason'] or exists(select 1 from jsonb_object_keys(p) k where k not in ('groups','rejected','reason')) or length(btrim(coalesce(p->>'reason','')))<3 or length(p->>'reason')>2000 then raise exception 'output_reason';end if;
   -- Reconciliation after receipt or allocation is deliberately not guessed.
   if exists(select 1 from private.manufactured_output_events where factory_id=f and output_id=h.id and operation in ('RECEIPT','DISPOSITION')) then raise exception 'output_reconciliation_required';end if;
   groups:=private.manufactured_output_groups(p->'groups',h.operation_snapshot,h.unit,true);rejected:=(p->>'rejected')::numeric;
   select coalesce(sum((value->>'quantity')::numeric),0) into q from jsonb_array_elements(groups);
   if rejected is null or rejected<0 or rejected::text in ('NaN','Infinity','-Infinity') or q+rejected<>h.quantity or (h.unit='piece' and rejected<>trunc(rejected)) then raise exception 'output_conservation';end if;
   result:=jsonb_build_object('output_id',h.id,'revision',rev,'groups',groups,'rejected',trim_scale(rejected)::text,
    'original',h.recorded_groups,'source',h.source_snapshot,'reason',p->>'reason','requires_production_approval',false);
  elsif op='RECEIPT' then
   if not p ?& array['group_id','quantity','movement_id','physical_confirmation','location'] or exists(select 1 from jsonb_object_keys(p) k where k not in ('group_id','quantity','movement_id','physical_confirmation','location'))
    or p->'physical_confirmation' is distinct from 'true'::jsonb or length(btrim(coalesce(p->>'location','')))<1 or length(p->>'location')>200 then raise exception 'output_physical_confirmation';end if;
   if quality is null then raise exception 'output_quality_required';end if;
   select value into g from jsonb_array_elements(quality->'groups') where value->>'id'=p->>'group_id';
   q:=(p->>'quantity')::numeric;
   select coalesce(sum((ev.result->>'quantity')::numeric),0) into used from private.manufactured_output_events ev where factory_id=f and output_id=h.id and operation='RECEIPT' and ev.result->>'group_id'=p->>'group_id';
   if g is null or q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity') or used+q>(g->>'released')::numeric or (h.unit='piece' and q<>trunc(q)) then raise exception 'output_receipt_quantity';end if;
   if jsonb_array_length(g->'missing_operations')=0 then
    select * into movement from public.finished_goods_movements where factory_id=f and id=(p->>'movement_id')::uuid and xmin::text=pg_current_xact_id()::text;
    if not found or movement.product_id<>h.product_id or movement.unit<>h.unit or movement.entry_id is distinct from h.entry_id or movement.stock_delta<>q
     or movement.reserved_delta<>0 or movement.kind<>'production_receipt' or movement.created_by is distinct from auth.uid() or movement.created_at<h.created_at then raise exception 'output_receipt_movement';end if;
    movement_id:=movement.id;
   else
    select * into wip from public.unfinished_movements where factory_id=f and id=(p->>'movement_id')::uuid and xmin::text=pg_current_xact_id()::text;
    if not found or wip.entry_id<>h.entry_id or wip.kind<>'warehouse_receipt' or wip.quantity<>0 or wip.location_delta<>q
     or wip.created_by is distinct from auth.uid() or wip.created_at<h.created_at then raise exception 'output_receipt_movement';end if;
    select * into lot from public.unfinished_lots where factory_id=f and id=wip.lot_id;
    if lot.source_entry_id<>h.entry_id or lot.warehouse_quantity<used+q or exists(select 1 from private.manufactured_output_events ev where factory_id=f and operation='RECEIPT'
     and ev.result->>'lot_id'=lot.id::text and (output_id<>h.id or ev.result->>'group_id'<>p->>'group_id')) then raise exception 'output_lot_classification';end if;
    wip_id:=wip.id;
   end if;
   result:=jsonb_build_object('output_id',h.id,'revision',rev,'group_id',g->>'id','quantity',trim_scale(q)::text,'lot_id',lot.id,
    'movement_id',coalesce(movement_id,wip_id),'location',p->>'location','remaining_released',trim_scale((g->>'released')::numeric-used-q)::text);
  elsif op='DISPOSITION' then
   if exists(select 1 from public.unfinished_lots where factory_id=f and source_entry_id=h.entry_id and quantity_available<>quantity_created) then raise exception 'output_reconciliation_required';end if;
   if not p ?& array['group_id','quantity','choice','reason'] or exists(select 1 from jsonb_object_keys(p) k where k not in ('group_id','quantity','choice','reason'))
    or p->>'choice' is null or p->>'choice' not in ('COMPLETE','REPLACE') or length(btrim(coalesce(p->>'reason','')))<3 or length(p->>'reason')>2000 then raise exception 'output_disposition';end if;
   select value into g from jsonb_array_elements(quality->'groups') where value->>'id'=p->>'group_id';q:=(p->>'quantity')::numeric;
   select coalesce(sum((ev.result->>'quantity')::numeric),0) into used from private.manufactured_output_events ev where factory_id=f and output_id=h.id and operation='DISPOSITION' and ev.result->>'group_id'=p->>'group_id';
   if g is null or jsonb_array_length(g->'missing_operations')=0 or q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity') or used+q>(g->>'quantity')::numeric or (h.unit='piece' and q<>trunc(q)) then raise exception 'output_disposition_quantity';end if;
   result:=jsonb_build_object('output_id',h.id,'revision',rev,'group_id',g->>'id','quantity',trim_scale(q)::text,'choice',p->>'choice',
    'origin_item_id',h.item_id,'demand_item_id',case when p->>'choice'='COMPLETE' then h.item_id end,'released_from_demand',p->>'choice'='REPLACE','reason',p->>'reason');
  elsif op='ACKNOWLEDGE' then
   if not p ? 'quality_revision' or exists(select 1 from jsonb_object_keys(p) k where k<>'quality_revision') or not exists(select 1 from private.manufactured_output_events where factory_id=f and output_id=h.id and operation='QUALITY' and revision=(p->>'quality_revision')::bigint) then raise exception 'output_notification';end if;
   result:=jsonb_build_object('output_id',h.id,'revision',rev,'quality_revision',p->>'quality_revision','acknowledged',true);
  else raise exception 'output_invalid';end if;
 end if;
 perform private.manufactured_output_authorize(f,op,expected);
 insert into private.manufactured_output_events(factory_id,output_id,request_id,revision,operation,intent,result,finished_movement_id,unfinished_movement_id,created_by)
  values(f,h.id,retry,rev,op,intent,result,movement_id,wip_id,auth.uid()) returning id into record_id;
 return result;
end$$;

-- There is deliberately no user-facing command or toggle. A future migration
-- must integrate production posting, corrections, sources, WIP and Sales before
-- a callable writer/activation can exist. All non-production receipts unchanged.
create function public.manufactured_output_capability(factory uuid) returns jsonb
 language plpgsql stable security definer set search_path='' as $$begin
 perform private.require_permission(factory,'factory','view');
 return jsonb_build_object('available',false,'schema_version',1,'reason','production_posting_not_integrated','scope','MANUFACTURED_OUTPUT_ONLY');
end$$;
revoke all on function public.manufactured_output_capability(uuid) from public,anon,service_role;
grant execute on function public.manufactured_output_capability(uuid) to authenticated;
revoke all on function private.manufactured_output_immutable(),private.manufactured_output_authorize(uuid,text,bigint),
 private.manufactured_output_groups(jsonb,jsonb,text,boolean),private.manufactured_output_source_guard(),
 private.manufactured_output_command(uuid,text,uuid,jsonb,bigint,uuid) from public,anon,authenticated,service_role;
commit;
