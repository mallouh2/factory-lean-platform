-- Receipt destinations, not a second inventory ledger or per-warehouse balances.
begin;
create table public.factory_warehouses (
 id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories,
 name text not null check(length(btrim(name)) between 1 and 200),
 name_ar text not null default '' check(length(name_ar)<=200),
 storage_class text not null check(storage_class in ('RAW','FINISHED','SEMI_FINISHED')),
 active boolean not null default true,revision bigint not null default 1 check(revision>0),
 created_at timestamptz not null default clock_timestamp(),created_by uuid not null references auth.users,
 updated_at timestamptz not null default clock_timestamp(),updated_by uuid not null references auth.users,
 unique(factory_id,id)
);
create unique index factory_warehouses_name on public.factory_warehouses(factory_id,lower(btrim(name)));
alter table public.factory_warehouses enable row level security;
revoke all on public.factory_warehouses from public,anon,authenticated,service_role;
create table private.warehouse_commands (
 factory_id uuid not null references public.factories,request_id uuid not null,actor_id uuid not null references auth.users,
 intent jsonb not null,result jsonb not null,created_at timestamptz not null default clock_timestamp(),primary key(factory_id,request_id)
);
create table private.receipt_warehouses (
 factory_id uuid not null,request_id uuid not null,warehouse_id uuid not null,
 output_id uuid not null,group_id uuid not null,entry_id uuid not null,
 quantity numeric not null check(quantity>0),unit text not null,movement_id uuid not null,
 storage_class text not null check(storage_class in ('FINISHED','SEMI_FINISHED')),
 name_snapshot text not null,name_ar_snapshot text not null,
 actor_id uuid not null references auth.users,created_at timestamptz not null default clock_timestamp(),
 primary key(factory_id,request_id),unique(factory_id,movement_id),
 foreign key(factory_id,warehouse_id) references public.factory_warehouses(factory_id,id),
 foreign key(factory_id,output_id) references private.manufactured_outputs(factory_id,id),
 foreign key(factory_id,entry_id) references public.production_entries(factory_id,id)
);
alter table private.warehouse_commands enable row level security;
alter table private.receipt_warehouses enable row level security;
revoke all on private.warehouse_commands,private.receipt_warehouses from public,anon,authenticated,service_role;
create trigger immutable before update or delete on private.warehouse_commands for each row execute function private.manufactured_output_immutable();
create trigger immutable before update or delete on private.receipt_warehouses for each row execute function private.manufactured_output_immutable();

-- NONPRODUCTION RECEIPT DESTINATIONS: existing external/opening ledger unchanged.
create table private.stock_receipt_warehouses (
 factory_id uuid not null,request_id uuid not null,warehouse_id uuid not null,
 actor_id uuid not null references auth.users,payload jsonb not null,movement_id uuid not null,
 storage_class text not null,name_snapshot text not null,name_ar_snapshot text not null,
 created_at timestamptz not null default clock_timestamp(),primary key(factory_id,request_id),unique(factory_id,movement_id),
 foreign key(factory_id,warehouse_id) references public.factory_warehouses(factory_id,id),
 foreign key(factory_id,request_id) references public.fulfillment_commands(factory_id,request_id)
);
alter table private.stock_receipt_warehouses enable row level security;
revoke all on private.stock_receipt_warehouses from public,anon,authenticated,service_role;
create trigger immutable before update or delete on private.stock_receipt_warehouses for each row execute function private.manufactured_output_immutable();
create function public.receive_warehouse_stock_at(factory uuid,payload jsonb,request_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare old private.stock_receipt_warehouses;w public.factory_warehouses;result uuid;category text;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'warehouse','edit');
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.fulfillment_lock(factory);
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'warehouse','edit');
 if request_id is null or payload is null or jsonb_typeof(payload)<>'object' or octet_length(payload::text)>5000 or not payload ?& array['item','item_type','unit','quantity','source','reference','note','warehouse_id']
  or exists(select 1 from jsonb_object_keys(payload)k where k not in ('item','item_type','unit','quantity','source','reference','note','warehouse_id')) then raise exception 'warehouse_invalid';end if;
 select * into old from private.stock_receipt_warehouses r where r.factory_id=factory and r.request_id=receive_warehouse_stock_at.request_id;
 if found then
  if old.actor_id<>auth.uid() or old.payload is distinct from payload then raise exception 'request_conflict';end if;
  return old.movement_id;
 end if;
 -- Never attach a warehouse retrospectively to an older pooled receipt.
 if exists(select 1 from public.fulfillment_commands c where c.factory_id=factory and c.request_id=receive_warehouse_stock_at.request_id) then raise exception 'request_conflict';end if;
 if payload->>'item_type'='finished' then category:='FINISHED';
 elsif payload->>'item_type'='material' then
  select case when inventory_kind='SEMI_FINISHED' then 'SEMI_FINISHED' else 'RAW' end into category from public.materials where factory_id=factory and id=(payload->>'item')::uuid;
 else raise exception 'warehouse_invalid';end if;
 select * into w from public.factory_warehouses where factory_id=factory and id=(payload->>'warehouse_id')::uuid and active for share;
 if category is null or w.id is null or w.storage_class<>category then raise exception 'warehouse_incompatible';end if;
 result:=public.receive_warehouse_stock(factory,(payload->>'item')::uuid,payload->>'item_type',payload->>'unit',(payload->>'quantity')::numeric,payload->>'source',payload->>'reference',payload->>'note',request_id);
 insert into private.stock_receipt_warehouses(factory_id,request_id,warehouse_id,actor_id,payload,movement_id,storage_class,name_snapshot,name_ar_snapshot)
  values(factory,request_id,w.id,auth.uid(),payload,result,w.storage_class,w.name,w.name_ar);
 perform private.require_permission(factory,'warehouse','edit');return result;
end$$;
revoke all on function public.receive_warehouse_stock_at(uuid,jsonb,uuid) from public,anon,authenticated,service_role;
grant execute on function public.receive_warehouse_stock_at(uuid,jsonb,uuid) to authenticated;
-- END NONPRODUCTION RECEIPT DESTINATIONS

create function public.factory_warehouses_read(factory uuid) returns jsonb
 language plpgsql stable security definer set search_path='' as $$begin
 perform private.require_permission(factory,'factory','view');
 if not (private.has_permission(factory,'warehouse','view') or private.has_permission(factory,'settings','edit')) then raise exception 'permission_denied' using errcode='42501';end if;
 return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(w)||jsonb_build_object('used',exists(select 1 from private.receipt_warehouses r where r.factory_id=factory and r.warehouse_id=w.id) or exists(select 1 from private.stock_receipt_warehouses r where r.factory_id=factory and r.warehouse_id=w.id)) order by w.created_at,w.id) from public.factory_warehouses w where w.factory_id=factory),'[]'::jsonb),
 'can_manage',private.has_permission(factory,'settings','edit'));
end$$;

create function public.factory_warehouse_command(factory uuid,operation text,target uuid,payload jsonb,expected_revision bigint,request_id uuid) returns jsonb
 language plpgsql security definer set search_path='' as $$
declare prior private.warehouse_commands;w public.factory_warehouses;intent jsonb;result jsonb;d record;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'settings','edit');
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'settings','edit');
 if request_id is null or operation not in ('CREATE','UPDATE','DEFAULTS') or operation is null or payload is null or jsonb_typeof(payload)<>'object' or octet_length(payload::text)>4000 then raise exception 'warehouse_invalid';end if;
 intent:=jsonb_build_object('operation',operation,'target',target,'payload',payload,'expected_revision',expected_revision);
 select * into prior from private.warehouse_commands c where c.factory_id=factory and c.request_id=factory_warehouse_command.request_id;
 if found then
  if prior.actor_id<>auth.uid() or prior.intent is distinct from intent then raise exception 'request_conflict';end if;
  return prior.result;
 end if;
 if operation='DEFAULTS' then
  if target is not null or expected_revision is not null or payload<>'{}'::jsonb then raise exception 'warehouse_invalid';end if;
  for d in select * from (values ('RAW','Raw Materials Warehouse','مستودع المواد الخام'),('FINISHED','Finished Goods Warehouse','مستودع المنتجات الجاهزة'),('SEMI_FINISHED','Semi-Finished / Unfinished Goods Warehouse','مستودع المنتجات نصف الجاهزة')) x(class,name,name_ar) loop
   if not exists(select 1 from public.factory_warehouses where factory_id=factory and storage_class=d.class) then
    insert into public.factory_warehouses(factory_id,name,name_ar,storage_class,created_by,updated_by) values(factory,d.name,d.name_ar,d.class,auth.uid(),auth.uid());
   end if;
  end loop;
  result:=public.factory_warehouses_read(factory);
 else
  if exists(select 1 from jsonb_object_keys(payload) k where k not in ('name','name_ar','storage_class','active')) or not payload ?& array['name','name_ar','storage_class','active']
   or jsonb_typeof(payload->'name')<>'string' or jsonb_typeof(payload->'name_ar')<>'string' or length(btrim(payload->>'name')) not between 1 and 200 or length(payload->>'name_ar')>200
   or payload->>'storage_class' not in ('RAW','FINISHED','SEMI_FINISHED') or jsonb_typeof(payload->'active')<>'boolean' then raise exception 'warehouse_invalid';end if;
  if operation='CREATE' then
   if target is not null or expected_revision is not null then raise exception 'warehouse_invalid';end if;
   insert into public.factory_warehouses(factory_id,name,name_ar,storage_class,active,created_by,updated_by)
    values(factory,btrim(payload->>'name'),btrim(payload->>'name_ar'),payload->>'storage_class',(payload->>'active')::boolean,auth.uid(),auth.uid()) returning * into w;
  else
   select * into w from public.factory_warehouses where factory_id=factory and id=target for update;
   if w.id is null then raise exception 'permission_denied' using errcode='42501';end if;
   if expected_revision is null or w.revision<>expected_revision then raise exception 'warehouse_revision';end if;
   if w.storage_class<>payload->>'storage_class' and (exists(select 1 from private.receipt_warehouses where factory_id=factory and warehouse_id=w.id) or exists(select 1 from private.stock_receipt_warehouses where factory_id=factory and warehouse_id=w.id)) then raise exception 'warehouse_class_in_use';end if;
   update public.factory_warehouses set name=btrim(payload->>'name'),name_ar=btrim(payload->>'name_ar'),storage_class=payload->>'storage_class',active=(payload->>'active')::boolean,revision=revision+1,updated_by=auth.uid(),updated_at=clock_timestamp()
    where factory_id=factory and id=w.id returning * into w;
  end if;
  result:=to_jsonb(w);
 end if;
 insert into private.warehouse_commands values(factory,request_id,auth.uid(),intent,result,clock_timestamp());
 perform private.require_permission(factory,'settings','edit');return result;
end$$;

-- Extend the current protected transaction in place. Do not expose an older
-- callable receipt implementation. Existing UUID recovery is checked first.
do $patch$ declare body text;original text;begin
 body:=pg_get_functiondef('public.receive_manufactured_output(uuid,uuid,jsonb,bigint,uuid)'::regprocedure);original:=body;
 if position('client_receipt' in body)=0 or position('output_lot_classification' in body)=0 then raise exception 'warehouse_receipt_contract_changed';end if;
 body:=replace(body,'rev bigint;begin','rev bigint;wh public.factory_warehouses;receipt_location text;begin');
 body:=replace(body,'''physical_confirmation'',''location'',''note''','''physical_confirmation'',''location'',''note'',''warehouse_id''');
 body:=replace(body,' or length(btrim(coalesce(payload->>''location'',''''))) not between 1 and 200','');
 body:=replace(body,' insert into private.manufactured_output_context',E' select * into wh from public.factory_warehouses where factory_id=factory and id=(payload->>''warehouse_id'')::uuid and active for share;\n if wh.id is null or wh.storage_class<>(case when jsonb_array_length(g->''missing_operations'')=0 then ''FINISHED'' else ''SEMI_FINISHED'' end) then raise exception ''output_warehouse'';end if;\n -- Historical lot labels are not rewritten or presented as warehouse balances.\n select location into receipt_location from private.manufactured_output_lots where factory_id=factory and output_id=target and group_id::text=g->>''id'';\n receipt_location:=coalesce(receipt_location,wh.name);\n insert into private.manufactured_output_context');
 body:=replace(body,$s$payload->>'location'$s$,'receipt_location');
 body:=replace(body,$s$binding:=(payload-'note')$s$,$s$binding:=(payload-'note'-'warehouse_id')||jsonb_build_object('location',receipt_location)$s$);
 body:=replace(body,' delete from private.manufactured_output_context',E' insert into private.receipt_warehouses(factory_id,request_id,warehouse_id,output_id,group_id,entry_id,quantity,unit,movement_id,storage_class,name_snapshot,name_ar_snapshot,actor_id) values(factory,request_id,wh.id,target,(g->>''id'')::uuid,h.entry_id,q,h.unit,m,wh.storage_class,wh.name,wh.name_ar,auth.uid());\n delete from private.manufactured_output_context');
 if body=original or position('wh public.factory_warehouses' in body)=0 or position('insert into private.receipt_warehouses' in body)=0 then raise exception 'warehouse_receipt_patch_failed';end if;
 execute body;
end $patch$;

-- WAREHOUSE RECEIPT READERS
create function private.receipt_destination(f uuid,retry uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',warehouse_id,'name',name_snapshot,'name_ar',name_ar_snapshot,'storage_class',storage_class)
 from private.receipt_warehouses where factory_id=f and request_id=retry
$$;
revoke all on function private.receipt_destination(uuid,uuid) from public,anon,authenticated,service_role;
do $read$ declare body text;fn text;needle text:='''location'',result->>''location''';begin
 foreach fn in array array['public.manufactured_receiving_read(uuid,integer)','public.manufactured_receiving_context(uuid,uuid,integer)'] loop
  body:=pg_get_functiondef(fn::regprocedure);
  if position(needle in body)=0 then raise exception 'warehouse_reader_contract_changed';end if;
  execute replace(body,needle,needle||',''warehouse'',private.receipt_destination(factory,request_id)');
 end loop;
end $read$;

revoke all on function public.factory_warehouses_read(uuid),public.factory_warehouse_command(uuid,text,uuid,jsonb,bigint,uuid) from public,anon,authenticated,service_role;
grant execute on function public.factory_warehouses_read(uuid),public.factory_warehouse_command(uuid,text,uuid,jsonb,bigint,uuid) to authenticated;
-- Existing receiving RPC grants, source/ledger guards and shipped gates unchanged.
notify pgrst,'reload schema';
commit;
