-- Inactive manufactured-output extension. Decisions are entitlements, never stock.
begin;
alter table private.manufactured_completion_work alter column group_id drop not null;
alter table private.manufactured_completion_work alter column lot_id drop not null;
alter table private.manufactured_completion_work add check
 ((group_id is not null and lot_id is not null) or (choice='REPLACE' and group_id is null and lot_id is null));

create table private.production_compensation (
 factory_id uuid not null,id uuid not null,output_id uuid not null,quality_revision bigint not null,
 demand_item_id uuid not null,item_id uuid not null,mode text not null check(mode in ('ACTIVE','PLANNED')),
 quantity numeric not null check(quantity>0 and quantity::text not in ('NaN','Infinity','-Infinity')),
 execution_start timestamptz,line_id uuid,reason text not null check(length(btrim(reason)) between 3 and 2000),
 intent jsonb not null,result jsonb not null,created_by uuid not null references auth.users,
 created_at timestamptz not null default clock_timestamp(),primary key(factory_id,id),
 foreign key(factory_id,output_id) references private.manufactured_outputs(factory_id,id),
 foreign key(factory_id,demand_item_id) references public.production_orders(factory_id,id),
 foreign key(factory_id,item_id) references public.production_orders(factory_id,id),
 check(mode<>'ACTIVE' or (execution_start is not null and line_id is not null and item_id=demand_item_id))
);
create index on private.production_compensation(factory_id,demand_item_id);
create index on private.production_compensation(factory_id,output_id);
create table private.production_compensation_entries (
 factory_id uuid not null,compensation_id uuid not null,entry_id uuid not null references public.production_entries,
 quantity numeric not null check(quantity>0),primary key(factory_id,compensation_id,entry_id),
 foreign key(factory_id,compensation_id) references private.production_compensation(factory_id,id)
);
-- Released demand entitlement only: no change to physical quantity/location.
create table private.production_compensation_releases (
 factory_id uuid not null,compensation_id uuid not null,lot_id uuid not null,group_id uuid not null,
 quantity numeric not null check(quantity>0),primary key(factory_id,compensation_id,lot_id),
 foreign key(factory_id,compensation_id) references private.production_compensation(factory_id,id),
 foreign key(factory_id,lot_id) references public.unfinished_lots(factory_id,id)
);
alter table private.production_compensation enable row level security;
alter table private.production_compensation_entries enable row level security;
alter table private.production_compensation_releases enable row level security;
revoke all on private.production_compensation,private.production_compensation_entries,private.production_compensation_releases from public,anon,authenticated,service_role;
create trigger compensation_immutable before update or delete on private.production_compensation for each row execute function private.manufactured_output_immutable();
create trigger compensation_entries_immutable before update or delete on private.production_compensation_entries for each row execute function private.manufactured_output_immutable();
create trigger compensation_releases_immutable before update or delete on private.production_compensation_releases for each row execute function private.manufactured_output_immutable();

create function private.compensation_recorded(f uuid,i uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce(sum(e.quantity),0) from private.production_compensation_entries e join private.production_compensation c
 on c.factory_id=e.factory_id and c.id=e.compensation_id where c.factory_id=f and c.item_id=i and c.mode='ACTIVE'
$$;
create function private.compensation_gross(f uuid,i uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce(sum(e.effective_good+e.effective_scrap+coalesce(e.effective_unfinished,0)),0)
 from public.production_entries e where e.factory_id=f and e.order_id=i
$$;

-- Unused active entitlement can move, explicitly, into the existing planned-work
-- contract after execution ends. No second allowance or source release is made.
create function private.compensation_remaining(f uuid,k uuid) returns numeric language sql stable security definer set search_path='' as $$
 select c.quantity-(select coalesce(sum(quantity),0) from private.production_compensation_entries e where e.factory_id=f and e.compensation_id=k)
 -(select coalesce(sum(quantity),0) from private.manufactured_completion_work w where w.factory_id=f and w.intent->'payload'->>'allowance_id'=k::text and private.output_work_live(f,w.item_id))
 from private.production_compensation c where c.factory_id=f and c.id=k
$$;

-- Existing allocation reader remains the single source of unfinished entitlement.
create or replace function private.output_work_allocations(f uuid,l uuid)
returns table(assigned numeric,replaced numeric,stock numeric,reserved numeric) language sql stable security definer set search_path='' as $$
 with w as (select coalesce(sum(quantity) filter(where choice in ('COMPLETE','REPLACE')),0) a,
 coalesce(sum(quantity) filter(where choice='REPLACE'),0) r,coalesce(sum(quantity) filter(where choice='STOCK'),0) s,
 coalesce(sum(quantity-private.output_work_consumed(f,item_id)) filter(where choice<>'REPLACE' and exists(select 1 from public.material_requests mr where mr.factory_id=f and mr.id=material_request_id and mr.status='REQUESTED')),0) v
 from private.manufactured_completion_work where factory_id=f and lot_id=l and private.output_work_live(f,item_id)),
 r as(select coalesce(sum(quantity),0) q from private.production_compensation_releases where factory_id=f and lot_id=l)
 select w.a+r.q,w.r+r.q,w.s,w.v from w,r
$$;

create function private.production_compensation_state(f uuid,o uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare h private.manufactured_outputs;j public.production_orders;d uuid;v bigint;accepted numeric;pending numeric;baseline numeric;
 active_left numeric;assigned numeric;source_used numeric;unassigned numeric;rejected numeric;held boolean;available numeric;begin
 select * into h from private.manufactured_outputs where factory_id=f and id=o;
 if h.id is null then raise exception 'output_not_found';end if;
 d:=private.output_work_demand(f,h.item_id);select * into j from public.production_orders where factory_id=f and id=d;
 select max(revision) into v from private.manufactured_output_events where factory_id=f and output_id=o and operation='QUALITY' and revision>coalesce((select max(revision) from private.manufactured_output_events where factory_id=f and output_id=o and operation='CORRECTION'),0);
 -- Use reviewed/applied quantities. Any unreconciled finding blocks the decision.
 select exists(select 1 from private.manufactured_outputs z join private.output_hold_rows(f) hr on hr.output_id=z.id
 where z.factory_id=f and private.output_work_demand(f,z.item_id)=d) into held;
 select coalesce(sum((g->>'quantity')::numeric),0) into accepted from private.manufactured_outputs z
 cross join lateral jsonb_array_elements(private.output_quality(f,z.id)->'groups') g
 where z.factory_id=f and private.output_work_demand(f,z.item_id)=d and jsonb_array_length(g->'missing_operations')=0;
 select coalesce(sum(greatest(w.quantity-private.compensation_gross(f,w.item_id),0)),0) into pending
 from private.manufactured_completion_work w where w.factory_id=f and w.demand_item_id=d and w.choice<>'STOCK' and private.output_work_live(f,w.item_id);
 select coalesce(sum(private.compensation_remaining(f,c.id)),0) into active_left
 from private.production_compensation c where c.factory_id=f and c.demand_item_id=d and c.mode='ACTIVE';
 baseline:=case when j.status='active' then greatest(j.target_quantity-private.compensation_gross(f,d)+private.compensation_recorded(f,d),0) else 0 end;
 select coalesce(sum((g->>'quantity')::numeric-a.assigned),0) into unassigned
 from private.manufactured_output_lots m cross join lateral private.output_work_allocations(f,m.lot_id) a
 join lateral jsonb_array_elements(private.output_quality(f,o)->'groups') g on g->>'id'=m.group_id::text
 where m.factory_id=f and m.output_id=o and m.demand_item_id=d;
 rejected:=coalesce((private.output_quality(f,o)->>'rejected')::numeric,0);
 select coalesce(sum(c.quantity),0) into source_used from private.production_compensation c where c.factory_id=f and c.output_id=o;
 -- Legacy source-backed REPLACE also spends rejection/unfinished coverage.
 select coalesce(sum(w.quantity),0) into assigned from private.manufactured_completion_work w
 where w.factory_id=f and w.output_id=o and w.choice='REPLACE' and w.lot_id is not null and private.output_work_live(f,w.item_id);
 available:=greatest(least(j.target_quantity-accepted-pending-baseline-greatest(active_left,0),greatest(rejected-source_used,0)+greatest(unassigned,0)),0);
 return jsonb_build_object('output_id',o,'demand_item_id',d,'original_target',j.target_quantity::text,'accepted',accepted::text,
 'received',private.output_demand_received(f,d)::text,'pending_work',pending::text,'active_allowance_remaining',greatest(active_left,0)::text,
 'unfinished_unassigned',greatest(unassigned,0)::text,'rejected',rejected::text,'available',case when v is null or held or d is null then '0' else available::text end,
 'quality_revision',v::text,'revision',(select max(revision)::text from private.manufactured_output_events where factory_id=f and output_id=o),
 'transfer_allowance',(select jsonb_build_object('id',c.id,'remaining',private.compensation_remaining(f,c.id)::text) from private.production_compensation c where c.factory_id=f and c.output_id=o and c.mode='ACTIVE' and j.status='completed' and private.compensation_remaining(f,c.id)>0 order by c.created_at,c.id limit 1),'status',j.status,'mode',case when j.status='active' then 'ACTIVE' when j.status='completed' then 'PLANNED' end,
 'blocked_reason',case when v is null then 'output_quality_required' when held then 'output_quality_hold' when j.status not in ('active','completed') then 'output_execution_required' when available<=0 then 'output_demand_covered' end);
end$$;

create function public.production_compensation_read(factory uuid,target uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
 declare s jsonb;j public.production_orders;why text;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'orders','view');
 if not private.manufactured_output_enabled(factory) then return jsonb_build_object('available','0','blocked_reason','recording_disabled');end if;
 s:=private.production_compensation_state(factory,target);
 if s->>'mode'='ACTIVE' and (s->>'available')::numeric>0 then
 select * into j from public.production_orders where factory_id=factory and id=(s->>'demand_item_id')::uuid;
 begin perform private.compensation_capacity(factory,j,(s->>'available')::numeric+(s->>'active_allowance_remaining')::numeric);
 exception when raise_exception then why:=sqlerrm;end;
 end if;
 return s||jsonb_build_object('active_block',why,'planned_fallback',coalesce(why='output_planning_conflict',false));
end$$;

-- Capacity is checked against the existing planning calendar/rates and protected
-- resource model. No saved schedule or actual execution timestamp is changed.
create function private.compensation_capacity(f uuid,j public.production_orders,q numeric) returns void
language plpgsql security definer set search_path='' as $$
declare rate numeric;fast numeric;ends timestamptz;occ jsonb;e jsonb;ready jsonb;begin
 occ:=private.resolve_production_occurrence(f,clock_timestamp())->'occurrence';
 e:=private.production_recording_eligibility(j,occ,clock_timestamp());
 if e->>'active_recording_eligible' is distinct from 'true' or j.status<>'active' or j.actual_finish is not null then raise exception 'output_active_context';end if;
 ready:=private.maintenance_execution_readiness(f,j.id,j.line_id,j.product_id);
 if ready->>'ready' is distinct from 'true' then raise exception 'output_not_ready';end if;
 select min(c.rate),max(c.rate) into rate,fast from public.work_centers w join public.work_center_capabilities c on c.factory_id=w.factory_id and c.work_center_id=w.id
 where w.factory_id=f and w.line_id=j.line_id and not w.archived and c.product_id=j.product_id and c.rate_unit=j.unit;
 if rate is null or rate<=0 or rate<>fast then raise exception 'output_capacity_unknown';end if;
 ends:=private.finish_after_working_minutes(f,private.next_working_start(f,clock_timestamp()),greatest(ceil(q/rate*60)::integer,1));
 if ends>=(occ->>'ends_at')::timestamptz then raise exception 'output_shift_capacity';end if;
 if exists(select 1 from public.production_orders x where x.factory_id=f and x.id<>j.id and x.line_id=j.line_id and x.status in ('active','planned')
 and (x.status='active' or x.start_time is null or x.expected_finish is null or x.start_time<ends)) then raise exception 'output_planning_conflict';end if;
 perform private.maintenance_assert_capacity(f,j.line_id,j.product_id,null,clock_timestamp(),ends,null,j.id,false);
end$$;

create function public.plan_production_compensation(factory uuid,target uuid,payload jsonb,expected_revision bigint,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare h private.manufactured_outputs;j public.production_orders;s jsonb;c private.production_compensation;intent jsonb;r jsonb;q numeric;mode text;
 left_q numeric;reject_left numeric;v record;take numeric;pr uuid;i uuid;releases jsonb:='[]';gid uuid;begin
 perform private.manufactured_output_authorize(factory,'DISPOSITION',expected_revision);perform private.require_permission(factory,'orders','create');
 if current_setting('transaction_isolation')<>'read committed' then raise exception 'recording_isolation' using errcode='40001';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.fulfillment_lock(factory);
 perform pg_advisory_xact_lock(hashtextextended(factory::text||':structure',0));
 perform private.manufactured_output_authorize(factory,'DISPOSITION',expected_revision);perform private.require_permission(factory,'orders','create');
 if not private.manufactured_output_enabled(factory) then raise exception 'recording_disabled';end if;
 if request_id is null or jsonb_typeof(payload) is distinct from 'object' or expected_revision is null or exists(select 1 from jsonb_object_keys(payload) k where k not in ('quantity','reason','mode','allowance_id'))
 or length(btrim(coalesce(payload->>'reason',''))) not between 3 and 2000 then raise exception 'output_disposition';end if;
 intent:=jsonb_build_object('target',target,'payload',payload,'expected',expected_revision);
 select * into c from private.production_compensation where factory_id=factory and id=request_id;
 if found then if c.created_by<>auth.uid() or c.intent<>intent then raise exception 'request_conflict' using errcode='40001';end if;return c.result;end if;
 if exists(select 1 from private.manufactured_completion_work w where w.factory_id=factory and w.request_id=plan_production_compensation.request_id) then
 select w.result into r from private.manufactured_completion_work w where w.factory_id=factory and w.request_id=plan_production_compensation.request_id and w.created_by=auth.uid() and w.intent=jsonb_build_object('target',target,'payload',payload,'expected',expected_revision);
 if r is null then raise exception 'request_conflict' using errcode='40001';end if;return r;end if;
 select * into h from private.manufactured_outputs where factory_id=factory and id=target for update;
 if h.id is null then raise exception 'output_not_found';end if;
 s:=private.production_compensation_state(factory,target);
 if (s->>'revision')::bigint is distinct from expected_revision then raise exception 'output_revision' using errcode='40001';end if;
 if payload->>'allowance_id' is not null then
 select * into c from private.production_compensation where factory_id=factory and id=(payload->>'allowance_id')::uuid;
 select * into j from public.production_orders where factory_id=factory and id=(s->>'demand_item_id')::uuid for update;
 q:=(payload->>'quantity')::numeric;
 if c.id is null or c.output_id<>h.id or c.mode<>'ACTIVE' or j.status<>'completed' or payload->>'mode' is distinct from 'PLANNED'
 or c.quality_revision is distinct from (s->>'quality_revision')::bigint or s->>'blocked_reason'='output_quality_hold'
 or q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity') or q>private.compensation_remaining(factory,c.id) or (h.unit='piece' and q<>trunc(q)) then raise exception 'output_compensation_transfer';end if;
 pr:=public.create_production_request(factory,'Replacement production','high',null,payload->>'reason',jsonb_build_array(jsonb_build_object('product_id',h.product_id,'quantity',q,'unit',h.unit)));
 select po.id into i from public.production_orders po where po.factory_id=factory and po.request_id=pr;
 r:=jsonb_build_object('allowance_id',c.id,'item_id',i,'origin_item_id',j.id,'mode','PLANNED','quantity',q::text,'received','0');
 insert into private.manufactured_completion_work values(factory,i,h.id,null,null,h.item_id,j.id,'REPLACE',q,'[]',null,request_id,intent,r,auth.uid(),clock_timestamp());
 return r;
 end if;
 if s->>'blocked_reason' is not null then raise exception '%',s->>'blocked_reason';end if;
 q:=(payload->>'quantity')::numeric;mode:=payload->>'mode';
 if q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity') or q>(s->>'available')::numeric or (h.unit='piece' and q<>trunc(q)) or (mode is distinct from s->>'mode' and not(mode='PLANNED' and s->>'mode'='ACTIVE')) then raise exception 'output_compensation_quantity';end if;
 select * into j from public.production_orders where factory_id=factory and id=(s->>'demand_item_id')::uuid for update;
 if mode='ACTIVE' then perform private.compensation_capacity(factory,j,q+(s->>'active_allowance_remaining')::numeric);i:=j.id;
 elsif mode='PLANNED' and j.status in ('active','completed') then
 if j.status='active' then
 begin perform private.compensation_capacity(factory,j,q+(s->>'active_allowance_remaining')::numeric);
 exception when raise_exception then if sqlerrm='output_planning_conflict' then gid:=j.id;else raise;end if;end;
 if gid is null then raise exception 'output_active_execution';end if;
 end if;
 pr:=public.create_production_request(factory,'Replacement production','high',null,payload->>'reason',jsonb_build_array(jsonb_build_object('product_id',h.product_id,'quantity',q,'unit',h.unit)));
 select po.id into i from public.production_orders po where po.factory_id=factory and po.request_id=pr;
 else raise exception 'output_execution_required';end if;
 r:=jsonb_build_object('compensation_id',request_id,'item_id',i,'origin_item_id',j.id,'mode',mode,'quantity',q::text,'received','0');
 insert into private.production_compensation values(factory,request_id,h.id,(s->>'quality_revision')::bigint,j.id,i,mode,q,
 case when mode='ACTIVE' then j.actual_start end,case when mode='ACTIVE' then j.line_id end,payload->>'reason',intent,r,auth.uid(),clock_timestamp());
 if mode='PLANNED' then
 insert into private.manufactured_completion_work values(factory,i,h.id,null,null,h.item_id,j.id,'REPLACE',q,'[]',null,request_id,intent,r,auth.uid(),clock_timestamp());
 end if;
 select greatest((s->>'rejected')::numeric-coalesce(sum(quantity),0),0) into reject_left from private.production_compensation where factory_id=factory and output_id=h.id and id<>request_id;
 left_q:=greatest(q-reject_left,0);
 for v in select m.*,l.quantity_created,l.warehouse_quantity,a.assigned,a.reserved from private.manufactured_output_lots m
 join public.unfinished_lots l on l.factory_id=m.factory_id and l.id=m.lot_id
 cross join lateral private.output_work_allocations(factory,m.lot_id) a
 where m.factory_id=factory and m.output_id=h.id and m.demand_item_id=j.id order by m.lot_id for update of l loop
  exit when left_q=0;take:=least(left_q,greatest(v.quantity_created-v.assigned,0));if take=0 then continue;end if;
  if private.output_group_held(factory,h.id,v.group_id) or take>v.warehouse_quantity-v.reserved then raise exception 'output_allocation_unavailable';end if;
  -- Existing DISPOSITION is the release authority; audit references are retained.
  perform private.manufactured_output_command(factory,'DISPOSITION',h.id,jsonb_build_object('group_id',v.group_id,'quantity',take::text,'choice','REPLACE','reason',payload->>'reason'),
   (select max(revision) from private.manufactured_output_events where factory_id=factory and output_id=h.id),gen_random_uuid());
  insert into private.production_compensation_releases values(factory,request_id,v.lot_id,v.group_id,take);left_q:=left_q-take;
 end loop;
 if left_q<>0 then raise exception 'output_allocation_unavailable';end if;
 perform private.manufactured_output_authorize(factory,'DISPOSITION',expected_revision);perform private.require_permission(factory,'orders','create');
 return r;
end$$;

-- Planned replacement and unused-allowance transfers retain the exact finding.
-- A later correction/review must not silently authorize obsolete work.
create function private.compensation_work_validate(f uuid,i uuid) returns void language plpgsql stable security definer set search_path='' as $$
declare c private.production_compensation;begin
 select a.* into c from private.production_compensation a where a.factory_id=f and
 ((a.item_id=i and a.mode='PLANNED') or exists(select 1 from private.manufactured_completion_work w where w.factory_id=f and w.item_id=i and w.intent->'payload'->>'allowance_id'=a.id::text));
 if c.id is not null and (c.quality_revision is distinct from (private.output_finding(f,c.output_id)->>'revision')::bigint or private.production_compensation_state(f,c.output_id)->>'blocked_reason'='output_quality_hold') then raise exception 'output_compensation_stale';end if;
end$$;

-- Every extra entry spends immutable allowance shares, under the same factory
-- and execution locks as V3. This adds no output, Scrap or inventory movements.
create function private.compensation_entry_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare c private.production_compensation;j public.production_orders;gross numeric;base numeric;extra numeric;left_q numeric;take numeric;begin
 if tg_op='INSERT' then perform private.compensation_work_validate(new.factory_id,new.order_id);end if;
 if not exists(select 1 from private.production_compensation where factory_id=new.factory_id and item_id=new.order_id and mode='ACTIVE') then
 if tg_op='INSERT' and private.manufactured_output_context_matches(new.factory_id,new.id,new.request_id,'RECORD')
 and private.compensation_gross(new.factory_id,new.order_id)>(select target_quantity from public.production_orders where id=new.order_id)
 and exists(select 1 from private.manufactured_outputs h where h.factory_id=new.factory_id and h.item_id=new.order_id and exists(select 1 from private.manufactured_output_events e where e.output_id=h.id and e.operation='QUALITY')
 and (coalesce((private.output_quality(new.factory_id,h.id)->>'rejected')::numeric,0)>0 or exists(select 1 from jsonb_array_elements(private.output_quality(new.factory_id,h.id)->'groups') g where jsonb_array_length(g->'missing_operations')>0)))
 then raise exception 'output_compensation_required';end if;return new;end if;
 if tg_op='UPDATE' then
 if private.manufactured_output_context_matches(new.factory_id,new.id,new.request_id,'RECORD') and (new.effective_good,new.effective_scrap,new.effective_unfinished,new.order_id,new.line_id,new.input_lot_id,new.input_quantity) is not distinct from (old.effective_good,old.effective_scrap,old.effective_unfinished,old.order_id,old.line_id,old.input_lot_id,old.input_quantity) then return new;end if;
 if (to_jsonb(new)-array['notes']) is distinct from (to_jsonb(old)-array['notes']) then raise exception 'output_compensation_immutable';end if;return new;end if;
 if not private.manufactured_output_context_matches(new.factory_id,new.id,new.request_id,'RECORD') then raise exception 'output_compensation_recording_required';end if;
 select * into j from public.production_orders where factory_id=new.factory_id and id=new.order_id;
 gross:=new.effective_good+new.effective_scrap+coalesce(new.effective_unfinished,0);
 base:=greatest(j.target_quantity-(private.compensation_gross(new.factory_id,j.id)-gross-private.compensation_recorded(new.factory_id,j.id)),0);
 extra:=greatest(gross-base,0);left_q:=extra;
 for c in select * from private.production_compensation where factory_id=new.factory_id and item_id=j.id and mode='ACTIVE' order by created_at,id loop
  exit when left_q=0;
  take:=least(left_q,private.compensation_remaining(c.factory_id,c.id));
  if take<=0 then continue;end if;
  if j.status not in ('active','completed') or (j.status='completed' and (new.recording_kind<>'LATE_ORDINARY' or new.execution_finished_at is distinct from j.actual_finish or new.effective_period_end>j.actual_finish)) or j.actual_start is distinct from c.execution_start or j.line_id is distinct from c.line_id
  or c.quality_revision is distinct from (private.output_finding(c.factory_id,c.output_id)->>'revision')::bigint
  or private.production_compensation_state(c.factory_id,c.output_id)->>'blocked_reason'='output_quality_hold' then raise exception 'output_compensation_stale';end if;
  if j.status='active' then perform private.compensation_capacity(c.factory_id,j,left_q);end if;
  insert into private.production_compensation_entries values(c.factory_id,c.id,new.id,take);left_q:=left_q-take;
 end loop;
 if left_q<>0 then raise exception 'output_compensation_exceeded';end if;
 return new;
end$$;
create trigger compensation_entry_attribution after insert on public.production_entries for each row execute function private.compensation_entry_guard();
create trigger compensation_entry_amendment before update on public.production_entries for each row execute function private.compensation_entry_guard();

-- The original requirement and execution identity cannot be rewritten by generic
-- order edits once compensation has referenced them.
create function private.compensation_order_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='active' then perform private.compensation_work_validate(new.factory_id,new.id);end if;
 if exists(select 1 from private.production_compensation where factory_id=old.factory_id and demand_item_id=old.id) then
 if (new.target_quantity,new.product_id,new.unit,new.request_id,new.actual_start) is distinct from (old.target_quantity,old.product_id,old.unit,old.request_id,old.actual_start)
 or (old.actual_finish is not null and new.actual_finish is distinct from old.actual_finish)
 or (old.status='completed' and new.status<>'completed') then raise exception 'output_compensation_identity';end if;
 end if;return new;
end$$;
create trigger compensation_order_identity before update on public.production_orders for each row execute function private.compensation_order_guard();

-- Bind active entitlement changes to the existing V3 fingerprint. No new writer
-- or retry protocol. Existing receipt recovery remains byte-compatible.
do $patch$ declare b text;n text;begin
 b:=pg_get_functiondef('private.production_recording_eligibility(public.production_orders,jsonb,timestamptz)'::regprocedure);
 n:='occurrence->>''occurrence_key'',live,evidence_count';
 if position(n in b)=0 then raise exception 'recording fingerprint changed';end if;
 execute replace(b,n,n||', (select coalesce(sum(quantity),0) from private.production_compensation where factory_id=job.factory_id and item_id=job.id and mode=''ACTIVE''),private.compensation_recorded(job.factory_id,job.id),(select coalesce(sum(private.compensation_remaining(job.factory_id,id)),0) from private.production_compensation where factory_id=job.factory_id and item_id=job.id and mode=''ACTIVE'')');
 b:=pg_get_functiondef('private.recording_v3_context(uuid,uuid,jsonb)'::regprocedure);
 n:='case when late then ''LATE_ORDINARY'' else ''ACTIVE_ORDINARY'' end';
 if position(n in b)=0 then raise exception 'same-shift recovery classification changed';end if;
 execute replace(b,n,'case when p->>''input_lot'' is not null then ''WIP_PROCESSING'' when late then ''LATE_ORDINARY'' else ''ACTIVE_ORDINARY'' end');
 b:=pg_get_functiondef('public.manufactured_output_read(uuid,text,uuid,integer)'::regprocedure);
 n:='''operations'',rows,''recovery''';
 if position(n in b)=0 then raise exception 'recording options changed';end if;
 execute replace(b,n,'''operations'',rows,''replacement_allowance'',(select coalesce(sum(private.compensation_remaining(factory,ac.id)),0) from private.production_compensation ac where ac.factory_id=factory and ac.item_id=target and ac.mode=''ACTIVE'')::text,''recovery''');
 -- An audited allowance replaces the generic overproduction checkbox only
 -- inside the protected output adapter. The entry trigger still enforces every
 -- unit, source revision, execution and allowance limit atomically.
 b:=pg_get_functiondef('private.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,text,numeric,text,uuid,numeric,jsonb,jsonb)'::regprocedure);
 n:='if total>job.target_quantity and not coalesce(confirmed,false) then';
 if position(n in b)=0 then raise exception 'recording quantity guard changed';end if;
 execute replace(b,n,'if total>job.target_quantity and not coalesce(confirmed,false) and not (private.manufactured_output_context_matches(f,null,r,''RECORD'') and exists(select 1 from private.production_compensation ac where ac.factory_id=f and ac.item_id=i and ac.mode=''ACTIVE'')) then');
 -- Source-backed completion/replacement cannot reserve coverage twice.
 b:=pg_get_functiondef('public.plan_manufactured_completion(uuid,uuid,jsonb,bigint,uuid)'::regprocedure);
 n:='ops:=coalesce(payload->''operations'',''[]''::jsonb);';
 if position(n in b)=0 then raise exception 'completion decision changed';end if;
 execute replace(b,n,'if choice<>''STOCK'' and q>(private.production_compensation_state(factory,target)->>''available'')::numeric then raise exception ''output_demand_covered'';end if;'||n);
end$patch$;
revoke all on function private.compensation_remaining(uuid,uuid),private.compensation_recorded(uuid,uuid),private.compensation_gross(uuid,uuid),private.production_compensation_state(uuid,uuid),private.compensation_capacity(uuid,public.production_orders,numeric),private.compensation_entry_guard(),private.compensation_order_guard(),private.compensation_work_validate(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function public.production_compensation_read(uuid,uuid),public.plan_production_compensation(uuid,uuid,jsonb,bigint,uuid) from public,anon,service_role;
grant execute on function public.production_compensation_read(uuid,uuid),public.plan_production_compensation(uuid,uuid,jsonb,bigint,uuid) to authenticated;
commit;
