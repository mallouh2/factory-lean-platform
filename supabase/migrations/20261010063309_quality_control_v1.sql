-- Quality disposition is additional acceptance truth; gross declarations stay intact.
begin;
insert into public.permissions(module,action) values ('quality','view'),('quality','create'),('quality','edit'),
 ('quality_history','view'),('quality_reasons','edit') on conflict do nothing;
create table public.quality_reasons (
 id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories,
 name text not null check(length(btrim(name)) between 1 and 120),name_ar text not null default '' check(length(name_ar)<=120),
 active boolean not null default true,is_other boolean not null default false,check(not is_other or active),
 created_at timestamptz not null default clock_timestamp(),unique(factory_id,id)
);
create unique index quality_reason_name on public.quality_reasons(factory_id,(lower(btrim(name))));
create unique index quality_reason_ar on public.quality_reasons(factory_id,(lower(btrim(name_ar)))) where btrim(name_ar)<>'';
create function private.seed_quality_reasons() returns trigger language plpgsql security definer set search_path='' as $$begin
 insert into public.quality_reasons(factory_id,name,name_ar,is_other) select new.id,name,name_ar,other from (values
 ('Dimensional defect','عيب في الأبعاد',false),('Surface defect','عيب في السطح',false),('Color mismatch','اختلاف اللون',false),
 ('Material contamination','تلوث المادة',false),('Incorrect weight/thickness','وزن أو سماكة غير صحيحة',false),
 ('Printing defect','عيب في الطباعة',false),('Cutting defect','عيب في القطع',false),('Deformation/damage','تشوه أو تلف',false),('Other','أخرى',true))r(name,name_ar,other);
 return new;
end$$;
create trigger quality_factory_reasons after insert on public.factories for each row execute function private.seed_quality_reasons();
insert into public.quality_reasons(factory_id,name,name_ar,is_other) select f.id,r.* from public.factories f cross join (values
 ('Dimensional defect','عيب في الأبعاد',false),('Surface defect','عيب في السطح',false),('Color mismatch','اختلاف اللون',false),
 ('Material contamination','تلوث المادة',false),('Incorrect weight/thickness','وزن أو سماكة غير صحيحة',false),
 ('Printing defect','عيب في الطباعة',false),('Cutting defect','عيب في القطع',false),('Deformation/damage','تشوه أو تلف',false),('Other','أخرى',true))r;

create table public.quality_rejections (
 id uuid primary key default gen_random_uuid(),factory_id uuid not null,source_id uuid not null,entry_id uuid not null,item_id uuid not null,
 product_id uuid not null,unit text not null check(unit in ('meter','piece')),quantity numeric not null check(quantity>0 and quantity::text not in ('NaN','Infinity','-Infinity')),
 disposition text not null check(disposition in ('SCRAP','REWORK')),reason_id uuid not null,reason text not null,reason_ar text not null,description text,
 physical_label text not null,line_id uuid,work_center_id uuid,shift_id uuid,shift_name text,shift_name_ar text,shift_date date,
 weight_kg_per_unit numeric,default_scrap_kg numeric,actual_scrap_kg numeric,weight_overridden boolean not null,note text not null,
 stock_movement_id uuid not null,
 lot_id uuid,created_by uuid not null references auth.users,created_at timestamptz not null default clock_timestamp(),
 unique(factory_id,id),check(unit<>'piece' or quantity=trunc(quantity)),
 check((disposition='SCRAP' and actual_scrap_kg is not null and actual_scrap_kg>0 and actual_scrap_kg::text not in ('NaN','Infinity','-Infinity')) or (disposition='REWORK' and actual_scrap_kg is null)),
 foreign key(factory_id,source_id) references public.finished_goods_sources(factory_id,id),
 foreign key(factory_id,entry_id) references public.production_entries(factory_id,id),
 foreign key(factory_id,item_id) references public.production_orders(factory_id,id),
 foreign key(factory_id,product_id) references public.products(factory_id,id),
 foreign key(factory_id,reason_id) references public.quality_reasons(factory_id,id),
 foreign key(factory_id,stock_movement_id) references public.finished_goods_movements(factory_id,id) deferrable initially deferred
);
create table public.quality_reversals (
 id uuid primary key default gen_random_uuid(),factory_id uuid not null,rejection_id uuid not null,reason text not null check(length(btrim(reason)) between 3 and 2000),
 stock_movement_id uuid not null,created_by uuid not null references auth.users,
 created_at timestamptz not null default clock_timestamp(),unique(factory_id,rejection_id),
 foreign key(factory_id,rejection_id) references public.quality_rejections(factory_id,id),
 foreign key(factory_id,stock_movement_id) references public.finished_goods_movements(factory_id,id)
);
create table public.quality_notifications (
 id uuid primary key,factory_id uuid not null,status text not null default 'OPEN' check(status in ('OPEN','ACKNOWLEDGED','RESOLVED')),
 acknowledged_by uuid references auth.users,acknowledged_at timestamptz,resolved_by uuid references auth.users,resolved_at timestamptz,
 foreign key(factory_id,id) references public.quality_rejections(factory_id,id)
);
alter table public.unfinished_lots add column quality_rejection_id uuid,add column reserved_quality_rejection_id uuid,
 add foreign key(factory_id,quality_rejection_id) references public.quality_rejections(factory_id,id),
 add foreign key(factory_id,reserved_quality_rejection_id) references public.quality_rejections(factory_id,id);
alter table public.unfinished_lots drop constraint unfinished_lots_factory_id_source_entry_id_key;
create unique index unfinished_normal_entry on public.unfinished_lots(factory_id,source_entry_id) where quality_rejection_id is null;
create unique index unfinished_quality_origin on public.unfinished_lots(factory_id,quality_rejection_id) where quality_rejection_id is not null;
alter table public.quality_rejections add foreign key(factory_id,lot_id) references public.unfinished_lots(factory_id,id) deferrable initially deferred;
alter table public.unfinished_movements drop constraint unfinished_movements_kind_check;
alter table public.unfinished_movements add constraint unfinished_movements_kind_check check(kind in ('created','consumed','corrected','warehouse_receipt','warehouse_issue','quality_rejection','quality_reversal'));
alter table public.finished_goods_movements drop constraint finished_goods_movements_kind_check;
alter table public.finished_goods_movements add constraint finished_goods_movements_kind_check check(kind in
 ('production_receipt','production_correction','reservation','release','dispatch','adjustment','opening_balance','external_receipt','material_issue','quality_rejection','quality_reversal'));
alter table public.production_orders add column quality_rejected_quantity numeric not null default 0,
 add column replacement_good_quantity numeric not null default 0,
 add column replacement_original_item_id uuid,add column quality_origin_rejection_id uuid,
 add foreign key(factory_id,replacement_original_item_id) references public.production_orders(factory_id,id),
 add foreign key(factory_id,quality_origin_rejection_id) references public.quality_rejections(factory_id,id),
 add column accepted_good_quantity numeric generated always as (produced_quantity-rejected_quantity-quality_rejected_quantity) stored,
 add column fulfillment_good_quantity numeric generated always as (produced_quantity-rejected_quantity-quality_rejected_quantity+replacement_good_quantity) stored,
 add column accepted_remaining_quantity numeric generated always as (greatest(target_quantity-produced_quantity+rejected_quantity+quality_rejected_quantity-replacement_good_quantity,0)) stored,
 add constraint accepted_good_nonnegative check(accepted_good_quantity>=0 and quality_rejected_quantity>=0 and replacement_good_quantity>=0);
create table public.quality_rework_records (
 factory_id uuid not null,entry_id uuid not null,rejection_id uuid not null,discarded_quantity numeric not null,
 weight_kg_per_unit numeric,default_scrap_kg numeric,actual_scrap_kg numeric not null,weight_overridden boolean not null,
 created_by uuid not null references auth.users,created_at timestamptz not null default clock_timestamp(),primary key(factory_id,entry_id),
 foreign key(factory_id,entry_id) references public.production_entries(factory_id,id),foreign key(factory_id,rejection_id) references public.quality_rejections(factory_id,id)
);
create index on public.quality_rejections(factory_id,entry_id,created_at);
create index on public.production_orders(factory_id,replacement_original_item_id);

-- Derived counters cannot be set by a generic write or a browser-supplied total.
create function private.quality_order_totals() returns trigger language plpgsql security definer set search_path='' as $$begin
 new.quality_rejected_quantity:=coalesce((select sum(q.quantity) from public.quality_rejections q where q.factory_id=new.factory_id and q.item_id=new.id
  and not exists(select 1 from public.quality_reversals v where v.factory_id=q.factory_id and v.rejection_id=q.id)),0);
 new.replacement_good_quantity:=coalesce((select sum(o.fulfillment_good_quantity) from public.production_orders o where o.factory_id=new.factory_id and o.replacement_original_item_id=new.id),0);
 return new;
end$$;
create trigger quality_order_totals before insert or update on public.production_orders for each row execute function private.quality_order_totals();
create function private.quality_refresh_acceptance() returns trigger language plpgsql security definer set search_path='' as $$
declare i uuid;begin
 if tg_table_name='production_orders' then
  if new.replacement_original_item_id is null then return new;end if;i:=new.replacement_original_item_id;
 elsif tg_table_name='quality_reversals' then select item_id into i from public.quality_rejections where factory_id=new.factory_id and id=new.rejection_id;
 else i:=new.item_id;end if;
 update public.production_orders set quality_rejected_quantity=quality_rejected_quantity where factory_id=new.factory_id and id=i;
 return new;
end$$;
create trigger quality_refresh_acceptance after insert on public.quality_rejections for each row execute function private.quality_refresh_acceptance();
create trigger quality_reverse_acceptance after insert on public.quality_reversals for each row execute function private.quality_refresh_acceptance();
create trigger quality_replace_acceptance after insert or update of produced_quantity,rejected_quantity,quality_rejected_quantity,replacement_good_quantity on public.production_orders for each row execute function private.quality_refresh_acceptance();

create function private.quality_reserved_lot() returns trigger language plpgsql security definer set search_path='' as $$
declare e public.production_entries;origin uuid;i uuid;begin
 select * into e from public.production_entries where factory_id=new.factory_id and id=new.source_entry_id;
 select reserved_quality_rejection_id into origin from public.unfinished_lots where factory_id=new.factory_id and id=e.input_lot_id;
 new.reserved_quality_rejection_id:=coalesce(new.quality_rejection_id,origin,new.reserved_quality_rejection_id);
 if new.reserved_quality_rejection_id is not null then
  select item_id into i from public.quality_rejections where factory_id=new.factory_id and id=new.reserved_quality_rejection_id;
  if i is distinct from e.order_id then raise exception 'quality_reserved';end if;
 end if;return new;
end$$;
create trigger quality_reserved_lot before insert or update on public.unfinished_lots for each row execute function private.quality_reserved_lot();
create function private.quality_material_request() returns trigger language plpgsql security definer set search_path='' as $$
declare origin uuid;i uuid;u text;begin
 select reserved_quality_rejection_id into origin from public.unfinished_lots where factory_id=new.factory_id and id=new.lot_id;
 if origin is not null then
  select item_id into i from public.quality_rejections where factory_id=new.factory_id and id=origin;
  if i is distinct from new.production_item_id then raise exception 'quality_reserved';end if;
  select e.unit into u from public.unfinished_lots l join public.production_entries e on e.factory_id=l.factory_id and e.id=l.source_entry_id where l.factory_id=new.factory_id and l.id=new.lot_id;
  if u='piece' and new.quantity<>trunc(new.quantity) then raise exception 'quality_quantity';end if;
 end if;return new;
end$$;
create trigger quality_material_request before insert or update on public.material_requests for each row execute function private.quality_material_request();
create function private.quality_entry_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare origin uuid;minimum_good numeric;begin
 if tg_op='UPDATE' then
  select coalesce(sum(q.quantity),0) into minimum_good from public.quality_rejections q where q.factory_id=new.factory_id and q.entry_id=new.id
   and not exists(select 1 from public.quality_reversals v where v.factory_id=q.factory_id and v.rejection_id=q.id);
  if new.effective_good<minimum_good then raise exception 'quality_unavailable';end if;
 end if;
 select reserved_quality_rejection_id into origin from public.unfinished_lots where factory_id=new.factory_id and id=new.input_lot_id;
 if origin is not null then
  if new.unit='piece' and (new.effective_good<>trunc(new.effective_good) or new.effective_scrap<>trunc(new.effective_scrap) or coalesce(new.effective_unfinished,0)<>trunc(coalesce(new.effective_unfinished,0))) then raise exception 'quality_quantity';end if;
 end if;return new;
end$$;
create trigger quality_entry_guard before insert or update on public.production_entries for each row execute function private.quality_entry_guard();
-- The existing Lean correction writes units first, then KG in the same transaction.
-- Check the final row, not a queued intermediate NEW image; no invalid mass may commit.
create function private.quality_entry_weight() returns trigger language plpgsql security definer set search_path='' as $$
declare e public.production_entries;begin
 select * into e from public.production_entries where factory_id=new.factory_id and id=new.id;
 if e.effective_scrap>0 and exists(select 1 from public.unfinished_lots l where l.factory_id=e.factory_id and l.id=e.input_lot_id and l.reserved_quality_rejection_id is not null)
  and (e.effective_scrap_kg is null or e.effective_scrap_kg<=0 or e.effective_scrap_kg::text in ('NaN','Infinity','-Infinity')) then raise exception 'quality_weight';end if;
 return null;
end$$;
create constraint trigger quality_entry_weight_check after insert or update on public.production_entries
 deferrable initially deferred for each row execute function private.quality_entry_weight();
create function private.quality_rework_record() returns trigger language plpgsql security definer set search_path='' as $$
declare origin uuid;begin
 select reserved_quality_rejection_id into origin from public.unfinished_lots where factory_id=new.factory_id and id=new.input_lot_id;
 if origin is not null and new.original_scrap_kg is not null then
  insert into public.quality_rework_records(factory_id,entry_id,rejection_id,discarded_quantity,weight_kg_per_unit,default_scrap_kg,actual_scrap_kg,weight_overridden,created_by)
  values(new.factory_id,new.id,origin,new.effective_scrap,new.weight_kg_per_unit,new.effective_scrap*new.weight_kg_per_unit,new.effective_scrap_kg,
   new.effective_scrap_kg is distinct from new.effective_scrap*new.weight_kg_per_unit,new.created_by) on conflict do nothing;
 end if;return new;
end$$;
create trigger quality_rework_record after insert or update on public.production_entries for each row execute function private.quality_rework_record();

-- Exclusive future output: a linked corrective subtree covers the parent's remaining
-- acceptance gap. Its physical work contributes once, including nested replacements.
create function private.quality_production_remaining(f uuid,i uuid,subtree boolean default false) returns numeric
language plpgsql stable security definer set search_path='' as $$
declare own_need numeric;children_need numeric;begin
 select case when status in ('planned','active') then accepted_remaining_quantity else 0 end into own_need
 from public.production_orders where factory_id=f and id=i;
 if own_need is null then return 0;end if;
 select coalesce(sum(private.quality_production_remaining(f,o.id,true)),0) into children_need
 from public.production_orders o where o.factory_id=f and o.replacement_original_item_id=i;
 return case when subtree then greatest(own_need,children_need) else greatest(own_need-children_need,0) end;
end$$;

-- Move outstanding Sales promises to the new work that now covers them. No receipt,
-- stock reservation, Sales total, received quantity or historical release is invented.
create function private.quality_replacement_commitments(f uuid,child uuid) returns void
language plpgsql security definer set search_path='' as $$
declare parent uuid;capacity numeric;excess numeric;take numeric;a record;begin
 select replacement_original_item_id into parent from public.production_orders where factory_id=f and id=child;
 capacity:=private.quality_production_remaining(f,child)-(select coalesce(sum(quantity),0) from public.sales_incoming_allocations where factory_id=f and item_id=child);
 while parent is not null and capacity>0 loop
  excess:=(select coalesce(sum(quantity),0) from public.sales_incoming_allocations where factory_id=f and item_id=parent)-private.quality_production_remaining(f,parent);
  for a in select * from public.sales_incoming_allocations where factory_id=f and item_id=parent and quantity>0 order by created_at,id for update loop
   take:=least(excess,capacity,a.quantity);exit when take<=0;
   update public.sales_incoming_allocations set quantity=quantity-take where factory_id=f and id=a.id;
   insert into public.sales_incoming_allocations(factory_id,line_id,item_id,quantity) values(f,a.line_id,child,take)
    on conflict(factory_id,line_id,item_id) do update set quantity=public.sales_incoming_allocations.quantity+excluded.quantity;
   excess:=excess-take;capacity:=capacity-take;
  end loop;
  select replacement_original_item_id into parent from public.production_orders where factory_id=f and id=parent;
 end loop;
end$$;

-- Preserve existing workers and all their authorization, retry, scheduling and conservation checks.
-- Fail closed if a worker's expected contract changes before this migration is applied.
do $$declare body text;fn record;begin
 body:=pg_get_functiondef('private.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,text,numeric,text,uuid,numeric)'::regprocedure);
 if position('total:=job.good_quantity+good;' in body)=0 then raise exception 'quality_record_worker_changed';end if;
 execute replace(body,'total:=job.good_quantity+good;','total:=job.fulfillment_good_quantity+good;');
 body:=pg_get_functiondef('private.correct_production(uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,boolean,numeric,text)'::regprocedure);
 if position('x.source_entry_id=e for update' in body)=0 or position('total:=job.good_quantity-original.effective_good+good;' in body)=0 then raise exception 'quality_correction_worker_changed';end if;
 body:=replace(body,'x.source_entry_id=e for update','x.source_entry_id=e and x.quality_rejection_id is null for update');
 execute replace(body,'total:=job.good_quantity-original.effective_good+good;','total:=job.fulfillment_good_quantity-original.effective_good+good;');
 for fn in select oid,prosrc from pg_proc where pronamespace in ('private'::regnamespace,'public'::regnamespace)
  and proname in ('finished_inventory_projection','projected_finished','allocate_sales_line','sales_order_detail','warehouse_inventory_rows','warehouse_page','fulfillment_preview','replenish_finished','production_fulfillment','warehouse_fulfillment','sales_fulfillment','fulfillment_guidance') loop
  body:=pg_get_functiondef(fn.oid);
  body:=replace(body,'o.remaining_quantity','private.quality_production_remaining('||(select quote_ident(proargnames[1]) from pg_proc where oid=fn.oid)||',o.id)');
  body:=replace(body,'candidate.remaining_quantity','private.quality_production_remaining('||(select quote_ident(proargnames[1]) from pg_proc where oid=fn.oid)||',candidate.id)');
  body:=replace(body,'allocation.remaining_quantity','private.quality_production_remaining('||(select quote_ident(proargnames[1]) from pg_proc where oid=fn.oid)||',allocation.id)');
  body:=replace(body,'a.remaining_quantity','private.quality_production_remaining('||(select quote_ident(proargnames[1]) from pg_proc where oid=fn.oid)||',a.id)');
  if body<>pg_get_functiondef(fn.oid) then execute body;end if;
 end loop;
end$$;

create function private.quality_gap(f uuid,q uuid) returns numeric language sql stable security definer set search_path='' as $$
 select case when exists(select 1 from public.quality_reversals where factory_id=f and rejection_id=q) then 0 else least(o.accepted_remaining_quantity,greatest(r.quantity
 -coalesce((select sum(e.effective_good) from public.production_entries e join public.unfinished_lots l on l.factory_id=e.factory_id and l.id=e.input_lot_id where e.factory_id=f and l.reserved_quality_rejection_id=q),0)
 -coalesce((select sum(child.fulfillment_good_quantity) from public.production_orders child where child.factory_id=f and child.quality_origin_rejection_id=q),0),0)) end
 from public.quality_rejections r join public.production_orders o on o.factory_id=f and o.id=r.item_id where r.factory_id=f and r.id=q
$$;
create function private.quality_replacement_root(f uuid,i uuid) returns uuid language sql stable security definer set search_path='' as $$
 with recursive chain as (select id,replacement_original_item_id from public.production_orders where factory_id=f and id=i
 union all select p.id,p.replacement_original_item_id from public.production_orders p join chain c on p.id=c.replacement_original_item_id where p.factory_id=f)
 select id from chain where replacement_original_item_id is null
$$;

create function public.quality_command(factory uuid,operation text,payload jsonb,request_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare src public.finished_goods_sources;e public.production_entries;item public.production_orders;p public.products;
 reason public.quality_reasons;q public.quality_rejections;lot public.unfinished_lots;old uuid;result uuid;
 amount numeric;mass numeric;weight numeric;default_mass numeric;movement uuid;new_lot_id uuid;custom text;reason_name text;req uuid;pending numeric;root_id uuid;root_remaining numeric;allowed text[];
begin
 perform private.require_permission(factory,'factory','view');
 if jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>30000 then raise exception 'quality_quantity';end if;
 allowed:=case operation when 'reject' then array['source','quantity','reason','disposition','actual_scrap_kg','description','approve_reason','note','physically_identified']
  when 'reverse' then array['rejection','physically_present','reason'] when 'reason' then array['id','name','name_ar','active']
  when 'acknowledge' then array['rejection'] when 'resolve' then array['rejection'] when 'request_rework' then array['rejection','lot','quantity'] when 'replacement' then array['rejection','quantity'] end;
 if allowed is null or exists(select 1 from jsonb_object_keys(payload)k where not(k=any(allowed))) then raise exception 'quality_quantity';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));
 perform private.fulfillment_lock(factory);
 perform private.require_permission(factory,'factory','view');
 if operation='reject' then perform private.require_permission(factory,'quality','view');perform private.require_permission(factory,'quality','create');
 elsif operation='reverse' then perform private.require_permission(factory,'quality','view');perform private.require_permission(factory,'quality','edit');
 elsif operation='reason' then perform private.require_permission(factory,'quality','view');perform private.require_permission(factory,'quality_reasons','edit');
 elsif operation in ('acknowledge','resolve','request_rework') then perform private.require_permission(factory,'orders','view');perform private.require_permission(factory,'orders','edit');
 elsif operation='replacement' then perform private.require_permission(factory,'orders','view');perform private.require_permission(factory,'orders','create');
 else raise exception 'quality_quantity';end if;
 old:=private.fulfillment_retry(factory,request_id,'quality_'||operation,payload);if old is not null then return old;end if;
 if operation='reject' then
  select * into src from public.finished_goods_sources where factory_id=factory and id=(payload->>'source')::uuid for update;
  amount:=(payload->>'quantity')::numeric;mass:=(payload->>'actual_scrap_kg')::numeric;
  if src.id is null or src.physical_label is null or src.unit not in ('meter','piece') or payload->>'physically_identified' is distinct from 'true' then raise exception 'quality_unavailable';end if;
  select * into e from public.production_entries where factory_id=factory and id=src.entry_id for update;
  select * into item from public.production_orders where factory_id=factory and id=src.item_id for update;
  select * into p from public.products where factory_id=factory and id=src.product_id;
  if amount is null or amount<=0 or amount::text in ('NaN','Infinity','-Infinity') or (src.unit='piece' and amount<>trunc(amount)) then raise exception 'quality_quantity';end if;
  if amount>src.quantity_available-private.source_reserved(factory,src.id) or amount>e.effective_good-coalesce((select sum(r.quantity) from public.quality_rejections r where r.factory_id=factory and r.entry_id=e.id and not exists(select 1 from public.quality_reversals v where v.factory_id=factory and v.rejection_id=r.id)),0)
   or amount>(select on_hand-reserved from public.finished_goods_balances where factory_id=factory and product_id=src.product_id and unit=src.unit) then raise exception 'quality_unavailable';end if;
  select * into reason from public.quality_reasons where factory_id=factory and id=(payload->>'reason')::uuid and active;
  if reason.id is null or payload->>'disposition' not in ('SCRAP','REWORK') or payload->>'disposition' is null or length(coalesce(payload->>'note',''))>2000 then raise exception 'quality_reason';end if;
  custom:=nullif(btrim(payload->>'description'),'');
  if reason.is_other and length(coalesce(custom,'')) not between 3 and 120 then raise exception 'quality_reason';end if;
  if coalesce((payload->>'approve_reason')::boolean,false) then
   if not reason.is_other then raise exception 'quality_reason';end if;
   perform private.require_permission(factory,'quality_reasons','edit');
   if exists(select 1 from public.quality_reasons r where r.factory_id=factory and (lower(btrim(r.name))=lower(custom) or lower(btrim(r.name_ar))=lower(custom))) then raise exception 'quality_duplicate_reason';end if;
   insert into public.quality_reasons(factory_id,name) values(factory,custom);
  end if;
  weight:=case when p.stock_unit=src.unit then p.unit_weight_kg end;
  default_mass:=case when payload->>'disposition'='SCRAP' then amount*weight end;
  if payload->>'disposition'='SCRAP' and (mass is null or mass<=0 or mass::text in ('NaN','Infinity','-Infinity')) then raise exception 'quality_weight';end if;
  if payload->>'disposition'='REWORK' and mass is not null then raise exception 'quality_weight';end if;
  result:=gen_random_uuid();movement:=gen_random_uuid();if payload->>'disposition'='REWORK' then new_lot_id:=gen_random_uuid();end if;
  insert into public.quality_rejections(id,factory_id,source_id,entry_id,item_id,product_id,unit,quantity,disposition,reason_id,reason,reason_ar,description,
   physical_label,line_id,work_center_id,shift_id,shift_name,shift_name_ar,shift_date,weight_kg_per_unit,default_scrap_kg,actual_scrap_kg,weight_overridden,note,stock_movement_id,lot_id,created_by)
  values(result,factory,src.id,e.id,item.id,p.id,src.unit,amount,payload->>'disposition',reason.id,reason.name,reason.name_ar,custom,
   src.physical_label,src.line_id,src.work_center_id,src.shift_id,src.shift_name,src.shift_name_ar,src.shift_date,weight,default_mass,mass,
   payload->>'disposition'='SCRAP' and mass is distinct from default_mass,coalesce(payload->>'note',''),movement,new_lot_id,auth.uid());
  perform private.source_begin_pick(factory,'quality_rejection',p.id,src.unit,e.id,jsonb_build_array(jsonb_build_object('source_id',src.id,'quantity',amount::text)));
  update public.finished_goods_balances set on_hand=on_hand-amount where factory_id=factory and product_id=p.id and unit=src.unit;
  insert into public.finished_goods_movements(id,factory_id,product_id,unit,kind,stock_delta,entry_id,reason,created_by) values(movement,factory,p.id,src.unit,'quality_rejection',-amount,e.id,result::text,auth.uid());
  perform private.source_end_pick();
  if new_lot_id is not null then
   insert into public.unfinished_lots(id,factory_id,source_entry_id,quantity_created,quantity_available,warehouse_quantity,remaining_work,created_at,created_by,quality_rejection_id)
   values(new_lot_id,factory,e.id,amount,amount,amount,'Quality rework: '||coalesce(custom,reason.name),clock_timestamp(),auth.uid(),result);
   insert into public.unfinished_movements(factory_id,lot_id,entry_id,kind,quantity,location_delta,created_by) values(factory,new_lot_id,e.id,'quality_rejection',amount,amount,auth.uid());
  end if;
  insert into public.quality_notifications(id,factory_id) values(result,factory);
 elsif operation='reason' then
  reason_name:=btrim(payload->>'name');
  if length(coalesce(reason_name,'')) not between 1 and 120 or length(coalesce(payload->>'name_ar',''))>120 then raise exception 'quality_reason';end if;
  if exists(select 1 from public.quality_reasons r where r.factory_id=factory and r.id is distinct from (payload->>'id')::uuid and
   (lower(btrim(r.name))=lower(reason_name) or (btrim(coalesce(payload->>'name_ar',''))<>'' and lower(btrim(r.name_ar))=lower(btrim(payload->>'name_ar'))))) then raise exception 'quality_duplicate_reason';end if;
  if payload->>'id' is null then
   insert into public.quality_reasons(factory_id,name,name_ar) values(factory,reason_name,coalesce(payload->>'name_ar','')) returning id into result;
  else
   if exists(select 1 from public.quality_reasons where factory_id=factory and id=(payload->>'id')::uuid and is_other) and payload->>'active'='false' then raise exception 'quality_reason';end if;
   update public.quality_reasons set name=reason_name,name_ar=coalesce(payload->>'name_ar',''),active=coalesce((payload->>'active')::boolean,true)
    where factory_id=factory and id=(payload->>'id')::uuid returning id into result;
   if result is null then raise exception 'quality_reason';end if;
  end if;
 else
  select * into q from public.quality_rejections where factory_id=factory and id=(payload->>'rejection')::uuid for update;
  if q.id is null then raise exception 'quality_unavailable';end if;
  if operation='reverse' then
   if payload->>'physically_present' is distinct from 'true' or length(btrim(coalesce(payload->>'reason',''))) not between 3 and 2000
   or exists(select 1 from public.quality_reversals where factory_id=factory and rejection_id=q.id)
   or exists(select 1 from public.production_orders where factory_id=factory and quality_origin_rejection_id=q.id)
   then raise exception 'quality_reversal_unavailable';end if;
   if q.lot_id is not null then
    select * into lot from public.unfinished_lots where factory_id=factory and id=q.lot_id for update;
    if lot.quantity_available<>q.quantity or lot.warehouse_quantity<>q.quantity or exists(select 1 from public.material_requests where factory_id=factory and lot_id=lot.id and status in ('REQUESTED','ISSUED','RECEIVED')) then raise exception 'quality_reversal_unavailable';end if;
    update public.unfinished_lots set quantity_available=0,warehouse_quantity=0 where id=lot.id;
    insert into public.unfinished_movements(factory_id,lot_id,entry_id,kind,quantity,location_delta,created_by) values(factory,lot.id,q.entry_id,'quality_reversal',-q.quantity,-q.quantity,auth.uid());
   end if;
   movement:=gen_random_uuid();update public.finished_goods_balances set on_hand=on_hand+q.quantity where factory_id=factory and product_id=q.product_id and unit=q.unit;
   insert into public.finished_goods_movements(id,factory_id,product_id,unit,kind,stock_delta,entry_id,reason,created_by) values(movement,factory,q.product_id,q.unit,'quality_reversal',q.quantity,q.entry_id,payload->>'reason',auth.uid());
   update private.finished_goods_unattributed set quantity=quantity-q.quantity where factory_id=factory and product_id=q.product_id and unit=q.unit;
   update public.finished_goods_sources set quantity_available=quantity_available+q.quantity where factory_id=factory and id=q.source_id;
   insert into public.quality_reversals(factory_id,rejection_id,reason,stock_movement_id,created_by) values(factory,q.id,payload->>'reason',movement,auth.uid()) returning id into result;
   perform private.reserve_received_stock(factory,q.product_id,q.unit);
   update public.quality_notifications set status='RESOLVED',resolved_by=auth.uid(),resolved_at=clock_timestamp() where factory_id=factory and id=q.id;
  elsif operation in ('acknowledge','resolve') then
   if operation='resolve' and private.quality_gap(factory,q.id)>0 then raise exception 'quality_shortfall';end if;
   update public.quality_notifications set status=case when operation='resolve' then 'RESOLVED' when status='OPEN' then 'ACKNOWLEDGED' else status end,
    acknowledged_by=coalesce(acknowledged_by,auth.uid()),acknowledged_at=coalesce(acknowledged_at,clock_timestamp()),
    resolved_by=case when operation='resolve' then auth.uid() else resolved_by end,resolved_at=case when operation='resolve' then clock_timestamp() else resolved_at end where factory_id=factory and id=q.id;
   result:=q.id;
  elsif operation='request_rework' then
   select * into lot from public.unfinished_lots where factory_id=factory and id=(payload->>'lot')::uuid and reserved_quality_rejection_id=q.id for update;
   amount:=(payload->>'quantity')::numeric;
   select coalesce(sum(quantity),0) into pending from public.material_requests where factory_id=factory and lot_id=lot.id and status='REQUESTED';
   if lot.id is null or amount is null or amount<=0 or amount>lot.warehouse_quantity-pending or (q.unit='piece' and amount<>trunc(amount)) then raise exception 'quality_unavailable';end if;
   result:=public.supply_command(factory,'material_request',jsonb_build_object('item',lot.id,'item_type','lot','unit',q.unit,'quantity',amount,'production_item_id',q.item_id,'note','Reserved Quality rework'),gen_random_uuid());
  elsif operation='replacement' then
   select * into item from public.production_orders where factory_id=factory and id=q.item_id for update;
   root_id:=private.quality_replacement_root(factory,item.id);
   select accepted_remaining_quantity into root_remaining from public.production_orders where factory_id=factory and id=root_id;
   -- A nested corrective item may cover its own already-counted active gap, but
   -- cannot duplicate recovery promised by another branch of the same root.
   select root_remaining-coalesce(sum(private.quality_production_remaining(factory,o.id,true)),0)
    +case when item.id=root_id then 0 else private.quality_production_remaining(factory,item.id) end into root_remaining
   from public.production_orders o where o.factory_id=factory and o.replacement_original_item_id=root_id;
   select coalesce(sum(private.quality_production_remaining(factory,o.id,true)),0) into pending from public.production_orders o where o.factory_id=factory and o.replacement_original_item_id=item.id;
   amount:=(payload->>'quantity')::numeric;
   if amount is null or amount<=0 or amount>least(root_remaining,private.quality_gap(factory,q.id)-(select coalesce(sum(private.quality_production_remaining(factory,o.id,true)),0) from public.production_orders o where o.factory_id=factory and o.quality_origin_rejection_id=q.id),item.accepted_remaining_quantity-pending)
    or amount::text in ('NaN','Infinity','-Infinity') or (q.unit='piece' and amount<>trunc(amount)) then raise exception 'quality_shortfall';end if;
   req:=public.create_production_request(factory,'Quality replacement','normal',null,'Quality rejection corrective production',jsonb_build_array(jsonb_build_object('product_id',q.product_id,'quantity',amount,'unit',q.unit)));
   select id into result from public.production_orders where factory_id=factory and production_orders.request_id=req;
   update public.production_orders set replacement_original_item_id=q.item_id,quality_origin_rejection_id=q.id where factory_id=factory and id=result;
   perform private.quality_replacement_commitments(factory,result);
  end if;
 end if;
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'quality_'||operation,payload,result,clock_timestamp());return result;
end$$;

create function private.quality_detail(f uuid,q uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select to_jsonb(r)||jsonb_build_object('quantity',r.quantity::text,'default_scrap_kg',r.default_scrap_kg::text,'actual_scrap_kg',r.actual_scrap_kg::text,
  'request_code',pr.code,'item_code',o.code,'product_name',p.name,'product_name_ar',p.name_ar,'product_code',p.code,'line_name',coalesce(l.name,c.name),'line_name_ar',coalesce(l.name_ar,c.name_ar),
  'shortfall',private.quality_gap(f,r.id)::text,'actor_name',(select display_name from public.memberships where factory_id=f and user_id=r.created_by),'notification',to_jsonb(n),'reversal',(select to_jsonb(v) from public.quality_reversals v where v.factory_id=f and v.rejection_id=r.id),
  'lots',coalesce((select jsonb_agg(to_jsonb(lot)||jsonb_build_object('quantity_available',lot.quantity_available::text,'warehouse_quantity',lot.warehouse_quantity::text)) from public.unfinished_lots lot where lot.factory_id=f and lot.reserved_quality_rejection_id=r.id),'[]'),
  'rework',coalesce((select jsonb_agg(jsonb_build_object('created_at',e.created_at,'good',e.effective_good::text,'discarded_quantity',e.effective_scrap::text,'scrap_kg',e.effective_scrap_kg::text,'unfinished',e.effective_unfinished::text) order by e.created_at,e.id)
   from public.production_entries e join public.unfinished_lots lot on lot.factory_id=e.factory_id and lot.id=e.input_lot_id where e.factory_id=f and lot.reserved_quality_rejection_id=r.id),'[]'))
 from public.quality_rejections r join public.production_orders o on o.factory_id=f and o.id=r.item_id join public.products p on p.factory_id=f and p.id=r.product_id
 left join public.production_requests pr on pr.factory_id=f and pr.id=o.request_id left join public.production_lines l on l.factory_id=f and l.id=r.line_id
 left join public.work_centers c on c.factory_id=f and c.id=r.work_center_id left join public.quality_notifications n on n.factory_id=f and n.id=r.id where r.factory_id=f and r.id=q
$$;
create function public.quality_read(factory uuid,query jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare mode text:=coalesce(query->>'mode','board');page integer:=coalesce((query->>'page')::integer,1);result jsonb;begin
 if jsonb_typeof(query) is distinct from 'object' or page not between 1 and 1000000 or octet_length(query::text)>5000 then raise exception 'quality_quantity';end if;
 if mode='notifications' then perform private.require_permission(factory,'orders','view');
 elsif mode='detail' then
  if not (private.has_permission(factory,'quality_history','view') or private.has_permission(factory,'orders','view')) then raise exception 'permission_denied' using errcode='42501';end if;
  result:=private.quality_detail(factory,(query->>'rejection')::uuid);if result is null then raise exception 'not_found' using errcode='P0002';end if;return result;
 elsif mode='history' then perform private.require_permission(factory,'quality_history','view');
 else perform private.require_permission(factory,'quality','view');end if;
 if mode='filters' then return jsonb_build_object(
  'products',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,name,name_ar from public.products where factory_id=factory order by name,id limit 5000)x),'[]'),
  'lines',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,name,name_ar from public.production_lines where factory_id=factory order by name,id limit 5000)x),'[]'),
  'shifts',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,name,name_ar from public.production_shifts where factory_id=factory order by name,id limit 5000)x),'[]'));
 elsif mode='reasons' then
  if length(coalesce(query->>'search',''))>120 then raise exception 'quality_reason';end if;
  if query->>'active_only'='true' then
   with matches as materialized(select * from public.quality_reasons where factory_id=factory and active and not is_other
    and (strpos(lower(name),lower(btrim(coalesce(query->>'search',''))))>0 or strpos(lower(name_ar),lower(btrim(coalesce(query->>'search',''))))>0)),
   choices as (select * from matches order by name,id limit 100 offset (page-1)*100),
   selectable as (select * from choices union select * from public.quality_reasons where factory_id=factory and active and (is_other or id=(query->>'selected')::uuid))
   select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x) order by is_other,name,id) from selectable x),'[]'),'total',(select count(*) from matches),'page_size',100) into result;
   return result;
  end if;
  return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from public.quality_reasons where factory_id=factory order by is_other,name,id limit 100 offset (page-1)*100)x),'[]'));
 elsif mode in ('notifications','history') then
  with data as materialized(select q.id,q.created_at from public.quality_rejections q join public.quality_notifications n on n.factory_id=q.factory_id and n.id=q.id
   where q.factory_id=factory and (query->>'entry' is null or q.entry_id=(query->>'entry')::uuid)
   and (mode<>'notifications' or n.status<>'RESOLVED'))
  select jsonb_build_object('rows',coalesce((select jsonb_agg(private.quality_detail(factory,x.id)) from (select * from data order by created_at desc,id limit 50 offset (page-1)*50)x),'[]'),'total',(select count(*) from data)) into result;
 elsif mode='board' then
  with data as materialized(select e.id,e.order_id as item_id,e.unit,e.created_at,e.good_quantity::text as recorded_good,e.effective_good::text as current_good,
   coalesce((select sum(q.quantity) from public.quality_rejections q where q.factory_id=factory and q.entry_id=e.id and not exists(select 1 from public.quality_reversals v where v.factory_id=factory and v.rejection_id=q.id)),0) as rejected,
   s.id as source_id,s.physical_label,s.shift_id,s.shift_name,s.shift_name_ar,s.shift_date,s.factory_timezone,
   least(coalesce(s.quantity_available-private.source_reserved(factory,s.id),0),coalesce(b.on_hand-b.reserved,0))::text as eligible,
   o.code as item_code,pr.code as request_code,p.name as product_name,p.name_ar as product_name_ar,p.code as product_code,
   (case when p.stock_unit=e.unit then p.unit_weight_kg end)::text as weight_kg_per_unit,e.line_id,coalesce(l.name,c.name) as line_name,coalesce(l.name_ar,c.name_ar) as line_name_ar
   from public.production_entries e join public.production_orders o on o.factory_id=factory and o.id=e.order_id join public.products p on p.factory_id=factory and p.id=o.product_id
   left join public.production_requests pr on pr.factory_id=factory and pr.id=o.request_id left join public.finished_goods_sources s on s.factory_id=factory and s.entry_id=e.id
   left join public.finished_goods_balances b on b.factory_id=factory and b.product_id=o.product_id and b.unit=e.unit
   left join public.production_lines l on l.factory_id=factory and l.id=e.line_id left join public.work_centers c on c.factory_id=factory and c.id=e.work_center_id
   where e.factory_id=factory and e.unit in ('meter','piece') and e.effective_good>0
   and (query->>'entry' is null or e.id=(query->>'entry')::uuid)
   and (query->>'date' is null or s.shift_date=(query->>'date')::date) and (query->>'shift' is null or s.shift_id=(query->>'shift')::uuid)
   and (query->>'line' is null or e.line_id=(query->>'line')::uuid) and (query->>'product' is null or p.id=(query->>'product')::uuid)
   and (query->>'order' is null or pr.code ilike '%'||(query->>'order')||'%' or o.code ilike '%'||(query->>'order')||'%'))
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('rejected',x.rejected::text,'accepted',(x.current_good::numeric-x.rejected)::text)) from (select * from data order by created_at desc,id limit 50 offset (page-1)*50)x),'[]'),'total',(select count(*) from data),
   'quality_scrap_kg',(select coalesce(sum(q.actual_scrap_kg),0)::text from public.quality_rejections q join data d on d.id=q.entry_id where q.factory_id=factory and q.disposition='SCRAP' and not exists(select 1 from public.quality_reversals v where v.factory_id=factory and v.rejection_id=q.id))) into result;
 else raise exception 'quality_quantity';end if;
 return result||jsonb_build_object('page',page,'page_size',50);
end$$;
do $$declare tab text;begin
 foreach tab in array array['quality_reasons','quality_rejections','quality_reversals','quality_notifications','quality_rework_records'] loop
  execute format('alter table public.%I enable row level security',tab);execute format('revoke all on public.%I from public,anon,authenticated',tab);
  execute format('create trigger quality_audit after insert or update or delete on public.%I for each row execute function private.audit_change()',tab);
 end loop;
end$$;
revoke all on function private.seed_quality_reasons(),private.quality_order_totals(),private.quality_refresh_acceptance(),private.quality_reserved_lot(),private.quality_material_request(),
 private.quality_entry_guard(),private.quality_entry_weight(),private.quality_production_remaining(uuid,uuid,boolean),private.quality_replacement_commitments(uuid,uuid),private.quality_rework_record(),private.quality_gap(uuid,uuid),private.quality_replacement_root(uuid,uuid),private.quality_detail(uuid,uuid),public.quality_command(uuid,text,jsonb,uuid),public.quality_read(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.quality_command(uuid,text,jsonb,uuid),public.quality_read(uuid,jsonb) to authenticated;
commit;
