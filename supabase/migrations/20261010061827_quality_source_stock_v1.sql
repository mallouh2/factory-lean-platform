-- Add source accounting to the existing finished ledger. Historical stock is unknown.
-- No receipt provenance is backfilled and physical acknowledgement never credits stock twice.
begin;
create table public.finished_goods_sources (
 id uuid primary key default gen_random_uuid(), factory_id uuid not null,
 entry_id uuid not null, item_id uuid not null, product_id uuid not null, unit text not null,
 line_id uuid, work_center_id uuid, shift_id uuid, recorded_at timestamptz not null,
 shift_name text,shift_name_ar text,shift_date date,factory_timezone text not null,
 quantity_credited numeric not null check(quantity_credited>=0),
 quantity_identified numeric not null default 0 check(quantity_identified>=0),
 quantity_available numeric not null default 0 check(quantity_available>=0 and quantity_available<=quantity_identified),
 physical_label text check(length(btrim(physical_label)) between 1 and 200),
 identified_by uuid references auth.users, identified_at timestamptz,
 unique(factory_id,id), unique(factory_id,entry_id),
 check(quantity_identified<=quantity_credited),
 check(quantity_available=0 or physical_label is not null),
 foreign key(factory_id,entry_id) references public.production_entries(factory_id,id),
 foreign key(factory_id,item_id) references public.production_orders(factory_id,id),
 foreign key(factory_id,product_id) references public.products(factory_id,id)
);
create table private.finished_goods_unattributed (
 factory_id uuid not null, product_id uuid not null, unit text not null,
 quantity numeric not null check(quantity>=0), primary key(factory_id,product_id,unit),
 foreign key(factory_id,product_id) references public.products(factory_id,id)
);
insert into private.finished_goods_unattributed select factory_id,product_id,unit,on_hand from public.finished_goods_balances;
alter table public.finished_goods_movements add unique(factory_id,id);
create table public.finished_goods_source_allocations (
 id uuid primary key default gen_random_uuid(), factory_id uuid not null,
 movement_id uuid not null,
 source_id uuid, quantity numeric not null check(quantity>0),
 foreign key(factory_id,source_id) references public.finished_goods_sources(factory_id,id),
 foreign key(factory_id,movement_id) references public.finished_goods_movements(factory_id,id)
);
create table public.finished_goods_source_reservations (
 factory_id uuid not null, sales_line_id uuid not null, source_id uuid not null,
 quantity numeric not null check(quantity>0), primary key(factory_id,sales_line_id,source_id),
 foreign key(factory_id,sales_line_id) references public.sales_order_lines(factory_id,id),
 foreign key(factory_id,source_id) references public.finished_goods_sources(factory_id,id)
);
create table public.finished_goods_identification_events (
 id uuid primary key default gen_random_uuid(),factory_id uuid not null,source_id uuid not null,
 quantity numeric not null check(quantity<>0),physical_label text not null,
 note text not null,created_by uuid not null references auth.users,created_at timestamptz not null default clock_timestamp(),
 foreign key(factory_id,source_id) references public.finished_goods_sources(factory_id,id)
);
-- Only protected functions can populate this transaction-local authorization context.
create table private.finished_goods_pick_context (
 backend integer not null, transaction_id bigint not null,factory_id uuid not null,actor_id uuid not null,
 kind text not null,product_id uuid,unit text,entry_id uuid,picks jsonb not null,
 primary key(backend,transaction_id)
);
create table private.finished_goods_pick_usage (
 backend integer not null,transaction_id bigint not null,position integer not null,
 quantity numeric not null,primary key(backend,transaction_id,position)
);
create index on public.finished_goods_sources(factory_id,product_id,unit);
create index on public.finished_goods_source_allocations(factory_id,source_id);

create function private.source_shift_date(f uuid,s uuid,at_time timestamptz) returns date
language sql stable security definer set search_path='' as $$
 select case when sh.start_time<sh.end_time and (at_time at time zone fac.timezone)::time>=sh.start_time and (at_time at time zone fac.timezone)::time<sh.end_time
 then (at_time at time zone fac.timezone)::date
 when sh.start_time>sh.end_time and (at_time at time zone fac.timezone)::time>=sh.start_time then (at_time at time zone fac.timezone)::date
 when sh.start_time>sh.end_time and (at_time at time zone fac.timezone)::time<sh.end_time then (at_time at time zone fac.timezone)::date-1 end
 from public.factories fac join public.production_shifts sh on sh.factory_id=fac.id and sh.id=s where fac.id=f
$$;

create function private.source_reserved(f uuid,s uuid,excluding uuid default null) returns numeric
language sql stable security definer set search_path='' as $$
 select coalesce(sum(quantity),0) from public.finished_goods_source_reservations
 where factory_id=f and source_id=s and (excluding is null or sales_line_id<>excluding)
$$;
create function private.source_conservation() returns trigger language plpgsql security definer set search_path='' as $$
declare f uuid; p uuid; u text; balance numeric; attributed numeric;unknown numeric;begin
 f:=new.factory_id;p:=new.product_id;u:=new.unit;
 select on_hand into balance from public.finished_goods_balances where factory_id=f and product_id=p and unit=u;
 select coalesce(sum(quantity_available),0) into attributed from public.finished_goods_sources where factory_id=f and product_id=p and unit=u;
 select coalesce(quantity,0) into unknown from private.finished_goods_unattributed where factory_id=f and product_id=p and unit=u;
 if coalesce(balance,0)<>attributed+coalesce(unknown,0) then raise exception 'source_conservation';end if;
 if exists(select 1 from public.finished_goods_sources s where s.factory_id=f and s.product_id=p and s.unit=u
 and private.source_reserved(f,s.id)>s.quantity_available) then raise exception 'source_committed';end if;
 if exists(select 1 from public.finished_goods_source_reservations sr join public.sales_order_lines l on l.factory_id=sr.factory_id and l.id=sr.sales_line_id
 where sr.factory_id=f and l.product_id=p and l.unit=u group by sr.sales_line_id
 having sum(sr.quantity)>(select coalesce(r.quantity,0) from public.finished_goods_reservations r where r.factory_id=f and r.line_id=sr.sales_line_id)) then raise exception 'source_committed';end if;
 return null;
end$$;
create constraint trigger source_balance_conservation after insert or update on public.finished_goods_balances
 deferrable initially deferred for each row execute function private.source_conservation();
create constraint trigger source_receipt_conservation after insert or update on public.finished_goods_sources
 deferrable initially deferred for each row execute function private.source_conservation();

create function private.source_movement() returns trigger language plpgsql security definer set search_path='' as $$
declare ctx private.finished_goods_pick_context;src public.finished_goods_sources;e public.production_entries;o public.production_orders;
 pick jsonb;pos integer; amount numeric;used numeric;total numeric:=0;needed numeric;pending numeric;released numeric;r record;
begin
 perform private.fulfillment_lock(new.factory_id);
 insert into private.finished_goods_unattributed values(new.factory_id,new.product_id,new.unit,0) on conflict do nothing;
 if new.stock_delta>0 then
  update private.finished_goods_unattributed set quantity=quantity+new.stock_delta where factory_id=new.factory_id and product_id=new.product_id and unit=new.unit;
  if new.entry_id is not null and new.kind in ('production_receipt','production_correction') then
   select * into e from public.production_entries where factory_id=new.factory_id and id=new.entry_id;
   select * into o from public.production_orders where factory_id=new.factory_id and id=e.order_id;
   if o.product_id is distinct from new.product_id or e.unit is distinct from new.unit then raise exception 'source_identity';end if;
   insert into public.finished_goods_sources(factory_id,entry_id,item_id,product_id,unit,line_id,work_center_id,shift_id,recorded_at,quantity_credited,shift_name,shift_name_ar,shift_date,factory_timezone)
   values(new.factory_id,e.id,o.id,o.product_id,e.unit,e.line_id,e.work_center_id,e.original_shift_id,e.created_at,new.stock_delta,
    (select name from public.production_shifts where factory_id=e.factory_id and id=e.original_shift_id),
    (select name_ar from public.production_shifts where factory_id=e.factory_id and id=e.original_shift_id),
    private.source_shift_date(e.factory_id,e.original_shift_id,e.created_at),(select timezone from public.factories where id=e.factory_id))
   on conflict(factory_id,entry_id) do update set quantity_credited=public.finished_goods_sources.quantity_credited+excluded.quantity_credited;
  end if;
 elsif new.stock_delta<0 then
  needed:=-new.stock_delta;
  select * into ctx from private.finished_goods_pick_context where backend=pg_backend_pid() and transaction_id=txid_current();
  if found then
   if ctx.factory_id<>new.factory_id or ctx.actor_id is distinct from auth.uid() or ctx.kind<>new.kind
   or (ctx.product_id is not null and ctx.product_id<>new.product_id) or (ctx.unit is not null and ctx.unit<>new.unit)
   or (ctx.entry_id is not null and ctx.entry_id is distinct from new.entry_id) then raise exception 'source_identity';end if;
   for pick,pos in select value,ordinality::integer from jsonb_array_elements(ctx.picks) with ordinality loop
    if new.kind='dispatch' and (pick->>'sales_line_id')::uuid is distinct from new.sales_line_id then continue;end if;
    select coalesce(quantity,0) into used from private.finished_goods_pick_usage where backend=pg_backend_pid() and transaction_id=txid_current() and position=pos;
    amount:=(pick->>'quantity')::numeric-coalesce(used,0);
    if amount<=0 then continue;end if;
    if amount>needed-total then raise exception 'source_quantity';end if;
    if pick->>'source_id' is null then
     update private.finished_goods_unattributed set quantity=quantity-amount where factory_id=new.factory_id and product_id=new.product_id and unit=new.unit and quantity>=amount;
     if not found then raise exception 'source_unavailable';end if;
    else
     select * into src from public.finished_goods_sources where factory_id=new.factory_id and id=(pick->>'source_id')::uuid for update;
     if src.id is null or src.product_id<>new.product_id or src.unit<>new.unit or src.physical_label is null
     or src.quantity_available-private.source_reserved(new.factory_id,src.id)<amount then raise exception 'source_unavailable';end if;
     if new.kind in ('production_correction','quality_rejection') and src.entry_id is distinct from new.entry_id then raise exception 'source_identity';end if;
     update public.finished_goods_sources set quantity_available=quantity_available-amount,
      quantity_identified=quantity_identified-case when new.kind='production_correction' then amount else 0 end where id=src.id;
    end if;
    insert into public.finished_goods_source_allocations(factory_id,movement_id,source_id,quantity) values(new.factory_id,new.id,(pick->>'source_id')::uuid,amount);
    insert into private.finished_goods_pick_usage values(pg_backend_pid(),txid_current(),pos,amount)
     on conflict(backend,transaction_id,position) do update set quantity=private.finished_goods_pick_usage.quantity+excluded.quantity;
    total:=total+amount;
   end loop;
   if total<>needed then raise exception 'source_quantity';end if;
  else
   -- Old clients can still use pooled stock, but cannot silently pick an identified batch.
   update private.finished_goods_unattributed set quantity=quantity-needed where factory_id=new.factory_id and product_id=new.product_id and unit=new.unit and quantity>=needed;
   if not found then raise exception 'source_selection_required';end if;
   insert into public.finished_goods_source_allocations(factory_id,movement_id,quantity) values(new.factory_id,new.id,needed);
  end if;
  if new.kind='production_correction' then
   if exists(select 1 from public.finished_goods_sources where factory_id=new.factory_id and entry_id=new.entry_id) then
    update public.finished_goods_sources set quantity_credited=greatest(quantity_credited-needed,0)
     where factory_id=new.factory_id and entry_id=new.entry_id and greatest(quantity_credited-needed,0)>=quantity_identified;
    if not found then raise exception 'source_correction_unavailable';end if;
   end if;
  end if;
 end if;
 if new.reserved_delta<0 then
  -- Release unallocated commitments first; release identified assignments only as needed.
  select coalesce(sum(quantity),0) into pending from public.finished_goods_source_reservations where factory_id=new.factory_id and sales_line_id=new.sales_line_id;
  select greatest(pending-coalesce(quantity,0),0) into released from public.finished_goods_reservations where factory_id=new.factory_id and line_id=new.sales_line_id;
  released:=coalesce(released,pending);
  for r in select * from public.finished_goods_source_reservations where factory_id=new.factory_id and sales_line_id=new.sales_line_id order by source_id for update loop
   amount:=least(released,r.quantity);exit when amount<=0;
   if amount=r.quantity then delete from public.finished_goods_source_reservations where factory_id=r.factory_id and sales_line_id=r.sales_line_id and source_id=r.source_id;
   else update public.finished_goods_source_reservations set quantity=quantity-amount where factory_id=r.factory_id and sales_line_id=r.sales_line_id and source_id=r.source_id;end if;
   released:=released-amount;
  end loop;
 end if;
 return new;
end$$;
create trigger source_movement after insert on public.finished_goods_movements for each row execute function private.source_movement();

create function private.source_begin_pick(f uuid,kind text,p uuid,u text,e uuid,picks jsonb) returns void
language plpgsql security definer set search_path='' as $$begin
 if jsonb_typeof(picks) is distinct from 'array' or jsonb_array_length(picks)>100 then raise exception 'source_quantity';end if;
 if exists(select 1 from jsonb_array_elements(picks)x where jsonb_typeof(x)<>'object' or (x->>'quantity')::numeric is null
 or (x->>'quantity')::numeric<=0 or (x->>'quantity')::numeric::text in ('NaN','Infinity','-Infinity')
 or exists(select 1 from jsonb_object_keys(x)k where k not in ('source_id','quantity','sales_line_id'))) then raise exception 'source_quantity';end if;
 insert into private.finished_goods_pick_context values(pg_backend_pid(),txid_current(),f,auth.uid(),kind,p,u,e,picks);
end$$;
create function private.source_end_pick() returns void language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from private.finished_goods_pick_context c cross join lateral jsonb_array_elements(c.picks) with ordinality p(value,position)
 left join private.finished_goods_pick_usage u on u.backend=c.backend and u.transaction_id=c.transaction_id and u.position=p.position
 where c.backend=pg_backend_pid() and c.transaction_id=txid_current() and coalesce(u.quantity,0)<>(p.value->>'quantity')::numeric) then raise exception 'source_quantity';end if;
 delete from private.finished_goods_pick_usage where backend=pg_backend_pid() and transaction_id=txid_current();
 delete from private.finished_goods_pick_context where backend=pg_backend_pid() and transaction_id=txid_current();
end$$;

create function private.source_assign_reservation(f uuid,l uuid,picks jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare line public.sales_order_lines;reserved numeric;total numeric;pick jsonb;src public.finished_goods_sources;q numeric;begin
 select * into line from public.sales_order_lines where factory_id=f and id=l for update;
 select quantity into reserved from public.finished_goods_reservations where factory_id=f and line_id=l for update;
 if line.id is null or reserved is null or jsonb_typeof(picks) is distinct from 'array' then raise exception 'source_committed';end if;
 select coalesce(sum((x->>'quantity')::numeric),0) into total from jsonb_array_elements(picks)x;
 if total>reserved then raise exception 'source_committed';end if;
 delete from public.finished_goods_source_reservations where factory_id=f and sales_line_id=l;
 for pick in select value from jsonb_array_elements(picks) loop
  q:=(pick->>'quantity')::numeric;
  if q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity') then raise exception 'source_quantity';end if;
  if pick->>'source_id' is null then continue;end if;
  select * into src from public.finished_goods_sources where factory_id=f and id=(pick->>'source_id')::uuid for update;
  if src.id is null or src.product_id<>line.product_id or src.unit<>line.unit or src.physical_label is null
  or src.quantity_available-private.source_reserved(f,src.id)<q then raise exception 'source_unavailable';end if;
  insert into public.finished_goods_source_reservations values(f,l,src.id,q)
   on conflict(factory_id,sales_line_id,source_id) do update set quantity=public.finished_goods_source_reservations.quantity+excluded.quantity;
 end loop;
end$$;

create function public.source_stock_command(factory uuid,operation text,payload jsonb,allocations jsonb,request_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare old uuid;result uuid;p jsonb:=jsonb_build_object('payload',payload,'allocations',allocations);
 src public.finished_goods_sources;q numeric;label text;line record;stock public.material_requests;e public.production_entries;item public.production_orders;allowed text[];
begin
 perform private.require_permission(factory,'factory','view');
 if payload is null or jsonb_typeof(payload)<>'object' or octet_length(p::text)>30000 then raise exception 'source_quantity';end if;
 if jsonb_typeof(allocations) is distinct from 'array' or jsonb_array_length(allocations)>100 or request_id is null then raise exception 'source_quantity';end if;
 allowed:=case operation when 'identify' then array['source','quantity','label','physically_identified','note'] when 'mix' then array['source','quantity','physically_identified','note']
  when 'reserve' then array['sales_line_id'] when 'dispatch' then array['sales_order','line'] when 'adjust' then array['product','unit','quantity','reason']
  when 'issue' then array['id','revision','reason'] when 'correct' then array['entry','good','discarded_quantity','scrap_kg','startup_kg','reason','confirm_overproduction','shift','change_shift','unfinished','remaining_work'] end;
 if allowed is null or exists(select 1 from jsonb_object_keys(payload)k where not(k=any(allowed))) then raise exception 'source_quantity';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));
 perform private.fulfillment_lock(factory);
 perform private.require_permission(factory,'factory','view');
 if operation in ('identify','mix','adjust') then perform private.require_permission(factory,'warehouse','edit');
 elsif operation in ('dispatch','issue','reserve') then perform private.require_permission(factory,'warehouse','issue');
 elsif operation='correct' then perform private.require_permission(factory,'orders','edit');perform private.require_permission(factory,'orders','view');
 else raise exception 'source_quantity';end if;
 old:=private.fulfillment_retry(factory,request_id,'source_'||operation,p);if old is not null then return old;end if;
 if operation in ('identify','mix') then
  select * into src from public.finished_goods_sources where factory_id=factory and id=(payload->>'source')::uuid for update;
  q:=(payload->>'quantity')::numeric;label:=btrim(payload->>'label');
  if src.id is null or q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity') or payload->>'physically_identified' is distinct from 'true'
  or length(coalesce(payload->>'note',''))>2000 then raise exception 'source_identity';end if;
  if operation='identify' then
   if length(coalesce(label,'')) not between 1 and 200 or (src.physical_label is not null and src.physical_label<>label)
   or q>src.quantity_credited-src.quantity_identified then raise exception 'source_identity';end if;
   update private.finished_goods_unattributed set quantity=quantity-q where factory_id=factory and product_id=src.product_id and unit=src.unit and quantity>=q;
   if not found then raise exception 'source_unavailable';end if;
   update public.finished_goods_sources set quantity_identified=quantity_identified+q,quantity_available=quantity_available+q,
    physical_label=label,identified_by=auth.uid(),identified_at=clock_timestamp() where id=src.id;
  else
   if q>src.quantity_available-private.source_reserved(factory,src.id) then raise exception 'source_committed';end if;
   label:=src.physical_label;
   update public.finished_goods_sources set quantity_available=quantity_available-q where id=src.id;
   update private.finished_goods_unattributed set quantity=quantity+q where factory_id=factory and product_id=src.product_id and unit=src.unit;
  end if;
  insert into public.finished_goods_identification_events(factory_id,source_id,quantity,physical_label,note,created_by)
   values(factory,src.id,case when operation='identify' then q else -q end,label,coalesce(payload->>'note',''),auth.uid()) returning id into result;
 elsif operation='reserve' then
  perform private.source_assign_reservation(factory,(payload->>'sales_line_id')::uuid,allocations);result:=(payload->>'sales_line_id')::uuid;
 elsif operation='dispatch' then
  if jsonb_typeof(allocations) is distinct from 'array' or exists(select 1 from jsonb_array_elements(allocations)a
   where not exists(select 1 from public.sales_order_lines l where l.factory_id=factory and l.order_id=(payload->>'sales_order')::uuid and l.id=(a->>'sales_line_id')::uuid
    and (payload->>'line' is null or l.id=(payload->>'line')::uuid))) then raise exception 'source_identity';end if;
  for line in select l.id from public.sales_order_lines l where l.factory_id=factory and l.order_id=(payload->>'sales_order')::uuid
   and l.dispatched_quantity<l.quantity and (payload->>'line' is null or l.id=(payload->>'line')::uuid) order by l.id loop
   perform private.source_assign_reservation(factory,line.id,(select coalesce(jsonb_agg(a),'[]') from jsonb_array_elements(allocations)a where a->>'sales_line_id'=line.id::text));
  end loop;
  perform private.source_begin_pick(factory,'dispatch',null,null,null,allocations);
  result:=public.dispatch_sales_order(factory,(payload->>'sales_order')::uuid,(payload->>'line')::uuid,gen_random_uuid());
  perform private.source_end_pick();
 elsif operation='adjust' then
  if (payload->>'quantity')::numeric>=0 then raise exception 'source_quantity';end if;
  perform private.source_begin_pick(factory,'adjustment',(payload->>'product')::uuid,payload->>'unit',null,allocations);
  result:=public.adjust_finished_stock(factory,(payload->>'product')::uuid,payload->>'unit',(payload->>'quantity')::numeric,payload->>'reason',gen_random_uuid());
  perform private.source_end_pick();
 elsif operation='issue' then
  select * into stock from public.material_requests where factory_id=factory and id=(payload->>'id')::uuid;
  if stock.product_id is null then raise exception 'source_identity';end if;
  perform private.source_begin_pick(factory,'material_issue',stock.product_id,stock.unit,null,allocations);
  result:=public.supply_command(factory,'material_change',payload||jsonb_build_object('action','issue'),gen_random_uuid());
  perform private.source_end_pick();
 elsif operation='correct' then
  select * into e from public.production_entries where factory_id=factory and id=(payload->>'entry')::uuid;
  select * into item from public.production_orders where factory_id=factory and id=e.order_id;
  if (payload->>'good')::numeric>=e.effective_good then raise exception 'source_quantity';end if;
  perform private.source_begin_pick(factory,'production_correction',item.product_id,e.unit,e.id,allocations);
  result:=public.correct_lean_production(factory,payload,gen_random_uuid());perform private.source_end_pick();
 end if;
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'source_'||operation,p,result,clock_timestamp());return result;
end$$;

create function public.finished_source_stock(factory uuid,product uuid,unit text,sales_line uuid default null,entry uuid default null,page integer default 1,material_request uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$begin
 if not(private.has_permission(factory,'warehouse','view') or private.has_permission(factory,'orders','view') or private.has_permission(factory,'quality','view')) then raise exception 'permission_denied' using errcode='42501';end if;
 if page is null or page not between 1 and 1000000 then raise exception 'source_quantity';end if;
 if sales_line is not null and not exists(select 1 from public.sales_order_lines where factory_id=factory and id=sales_line and product_id=product and sales_order_lines.unit=finished_source_stock.unit) then raise exception 'source_identity';end if;
 if material_request is not null and not exists(select 1 from public.material_requests m where m.factory_id=factory and m.id=material_request and m.product_id=product and m.unit=finished_source_stock.unit) then raise exception 'source_identity';end if;
 return jsonb_build_object('required_quantity',coalesce((select (quantity-dispatched_quantity)::text from public.sales_order_lines where factory_id=factory and id=sales_line),(select quantity::text from public.material_requests where factory_id=factory and id=material_request)),
  'page',page,'total',(select count(*) from public.finished_goods_sources s where s.factory_id=factory and s.product_id=product and s.unit=finished_source_stock.unit and (entry is null and s.quantity_available>0 or s.entry_id=entry)),
  'unattributed',coalesce((select quantity::text from private.finished_goods_unattributed where factory_id=factory and product_id=product and finished_goods_unattributed.unit=finished_source_stock.unit),'0'),
  'rows',coalesce((select jsonb_agg(to_jsonb(x)) from (select s.*,s.quantity_credited::text as credited,s.quantity_available::text as available,
   private.source_reserved(factory,s.id,sales_line)::text as committed,(s.quantity_available-private.source_reserved(factory,s.id,sales_line))::text as selectable,
   (s.quantity_credited-s.quantity_identified)::text as identifiable
   from public.finished_goods_sources s where s.factory_id=factory and s.product_id=product and s.unit=finished_source_stock.unit and (entry is null and s.quantity_available>0 or s.entry_id=entry) order by s.recorded_at,s.id limit 50 offset (page-1)*50)x),'[]'));
end$$;
do $$declare tab text;begin
 foreach tab in array array['finished_goods_sources','finished_goods_source_allocations','finished_goods_source_reservations','finished_goods_identification_events'] loop
  execute format('alter table public.%I enable row level security',tab);
  execute format('revoke all on public.%I from public,anon,authenticated',tab);
  execute format('create trigger source_audit after insert or update or delete on public.%I for each row execute function private.audit_change()',tab);
 end loop;
end$$;
revoke all on function private.source_shift_date(uuid,uuid,timestamptz),private.source_reserved(uuid,uuid,uuid),private.source_conservation(),private.source_movement(),
 private.source_begin_pick(uuid,text,uuid,text,uuid,jsonb),private.source_end_pick(),private.source_assign_reservation(uuid,uuid,jsonb),
 public.source_stock_command(uuid,text,jsonb,jsonb,uuid),public.finished_source_stock(uuid,uuid,text,uuid,uuid,integer,uuid) from public,anon,authenticated;
grant execute on function public.source_stock_command(uuid,text,jsonb,jsonb,uuid),public.finished_source_stock(uuid,uuid,text,uuid,uuid,integer,uuid) to authenticated;
revoke all on private.finished_goods_unattributed,private.finished_goods_pick_context,private.finished_goods_pick_usage from public,anon,authenticated;
-- Keep physically unlabelled receipts accessible after their no-credit acknowledgment.
do $$declare body text;begin
 body:=pg_get_functiondef('public.supply_page(uuid,text,integer,jsonb,uuid)'::regprocedure);
 if position('o.code,e.unit,e.effective_good,e.created_at' in body)=0 or position('and not exists(select 1 from public.production_receipt_acknowledgments where factory_id=factory and entry_id=e.id)' in body)=0 then raise exception 'source_output_reader_changed';end if;
 body:=replace(body,'o.code,e.unit,e.effective_good,e.created_at','o.code,e.unit,e.effective_good,e.created_at,exists(select 1 from public.production_receipt_acknowledgments where factory_id=factory and entry_id=e.id) acknowledged');
 body:=replace(body,'and not exists(select 1 from public.production_receipt_acknowledgments where factory_id=factory and entry_id=e.id)',
 'and (not exists(select 1 from public.production_receipt_acknowledgments where factory_id=factory and entry_id=e.id) or exists(select 1 from public.finished_goods_sources s where s.factory_id=factory and s.entry_id=e.id and (s.quantity_credited>s.quantity_identified or s.quantity_available>0)))');
 execute body;
end$$;
commit;
