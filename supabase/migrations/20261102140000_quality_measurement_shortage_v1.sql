-- Measurement error is unproduced ordinary work, never a rejected/WIP allowance.
begin;
do $$begin if current_setting('server_version_num')::integer<170000 then raise exception 'Measurement progress requires PostgreSQL 17 generated-expression support';end if;end$$;
alter table public.production_orders add column quality_measurement_delta numeric not null default 0
 check(quality_measurement_delta::text not in('NaN','Infinity','-Infinity'));
alter table public.production_orders add column quality_output_good_delta numeric not null default 0 check(quality_output_good_delta::text not in('NaN','Infinity','-Infinity'));
alter table private.production_compensation add column source_kind text not null default 'RECOVERY'
 check(source_kind in('RECOVERY','MEASUREMENT')),
 add constraint measurement_makeup_planned_only check(source_kind<>'MEASUREMENT' or mode='PLANNED');

create function private.output_measurement_delta(f uuid,i uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce(sum(e.effective_good+coalesce(e.effective_unfinished,0)-coalesce((q->>'total')::numeric,
 (select coalesce(sum((g->>'quantity')::numeric),0) from jsonb_array_elements(q->'groups')g)+coalesce((q->>'rejected')::numeric,0))),0)
 from private.manufactured_outputs h join public.production_entries e on e.factory_id=f and e.id=h.entry_id
 cross join lateral private.output_quality(f,h.id)q
 where h.factory_id=f and h.item_id=i and e.input_lot_id is null and q is not null
$$;

create function private.output_good_delta(f uuid,i uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce(sum(e.effective_good-(select coalesce(sum((g->>'quantity')::numeric),0) from jsonb_array_elements(q->'groups')g where jsonb_array_length(g->'missing_operations')=0)),0)
 from private.manufactured_outputs h join public.production_entries e on e.factory_id=f and e.id=h.entry_id cross join lateral private.output_quality(f,h.id)q
 where h.factory_id=f and h.item_id=i and q is not null
$$;

create function private.ordinary_output_remaining(f uuid,i uuid) returns numeric language plpgsql stable security definer set search_path='' as $$
declare j public.production_orders;extra numeric;begin
 select * into j from public.production_orders where factory_id=f and id=i;if not found then return 0;end if;
 if not exists(select 1 from private.manufactured_outputs where factory_id=f and item_id=i) and not exists(select 1 from private.manufactured_completion_work where factory_id=f and item_id=i) then return greatest(j.target_quantity-j.good_quantity,0);end if;
 select coalesce(sum(private.compensation_remaining(f,c.id)),0) into extra from private.production_compensation c where c.factory_id=f and c.item_id=i and c.mode='ACTIVE';
 return greatest(j.target_quantity-private.compensation_gross(f,i)+private.compensation_recorded(f,i),0)+extra;
end$$;

-- Original technician/production quantities remain immutable. Only the derived
-- accepted progress has a separately named, signed measurement adjustment.
alter table public.production_orders alter column accepted_good_quantity set expression as
 (produced_quantity-rejected_quantity-quality_rejected_quantity-quality_output_good_delta);
alter table public.production_orders alter column fulfillment_good_quantity set expression as
 (produced_quantity-rejected_quantity-quality_rejected_quantity-quality_output_good_delta+replacement_good_quantity);
alter table public.production_orders alter column accepted_remaining_quantity set expression as
 (greatest(target_quantity-produced_quantity+rejected_quantity+quality_rejected_quantity+quality_output_good_delta-replacement_good_quantity,0));

do $migration$declare d text;begin
 d:=pg_get_functiondef('private.quality_order_totals()'::regprocedure);
 if position('return new;' in d)=0 then raise exception 'measurement_order_contract';end if;
 execute replace(d,'return new;','new.quality_measurement_delta:=private.output_measurement_delta(new.factory_id,new.id);new.quality_output_good_delta:=private.output_good_delta(new.factory_id,new.id);return new;');
end$migration$;
drop trigger quality_replace_acceptance on public.production_orders;
create trigger quality_replace_acceptance after insert or update of produced_quantity,rejected_quantity,quality_rejected_quantity,replacement_good_quantity,quality_measurement_delta,quality_output_good_delta
 on public.production_orders for each row execute function private.quality_refresh_acceptance();

create function private.project_quality_measurement() returns trigger language plpgsql security definer set search_path='' as $$
declare i uuid;delta numeric;goods numeric;begin
 select item_id into i from private.manufactured_outputs where factory_id=new.factory_id and id=new.output_id;
 delta:=private.output_measurement_delta(new.factory_id,i);goods:=private.output_good_delta(new.factory_id,i);
 update public.production_orders set quality_measurement_delta=delta,quality_output_good_delta=goods where factory_id=new.factory_id and id=i and (quality_measurement_delta is distinct from delta or quality_output_good_delta is distinct from goods);
 return new;
end$$;
create trigger project_quality_measurement after insert on private.manufactured_output_events for each row
 when(new.operation in('QUALITY','RECONCILE','CORRECTION')) execute function private.project_quality_measurement();

create or replace function private.compensation_gross(f uuid,i uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce((select sum(e.effective_good+e.effective_scrap+coalesce(e.effective_unfinished,0)) from public.production_entries e where e.factory_id=f and e.order_id=i),0)
 -coalesce((select quality_measurement_delta from public.production_orders where factory_id=f and id=i),0)
$$;

create or replace function private.output_future_remaining(f uuid,i uuid,subtree boolean default false) returns numeric language plpgsql stable security definer set search_path='' as $$
declare j public.production_orders;own_need numeric;children_need numeric;modern boolean;begin
 select * into j from public.production_orders where factory_id=f and id=i;if not found or private.output_work_held(f,i) then return 0;end if;
 modern:=exists(select 1 from private.manufactured_outputs where factory_id=f and item_id=i) or exists(select 1 from private.manufactured_completion_work where factory_id=f and item_id=i);
 own_need:=case when j.status not in('planned','active') then 0 when modern then private.ordinary_output_remaining(f,i) else j.accepted_remaining_quantity end;
 select coalesce(sum(private.output_future_remaining(f,o.id,true)),0) into children_need from public.production_orders o where o.factory_id=f and o.replacement_original_item_id=i;
 if modern then return case when subtree then own_need+children_need else own_need end;end if;
 return case when subtree then greatest(own_need,children_need) else greatest(own_need-children_need,0) end;
end$$;

-- Keep RECOVERY and MEASUREMENT entitlements disjoint. Existing material group
-- allocations stay unchanged; measurement make-up allocates no lot or KG.
do $migration$declare d text;needle text;begin
 d:=pg_get_functiondef('private.production_compensation_state(uuid,uuid)'::regprocedure);
 needle:='where c.factory_id=f and c.output_id=o;';
 if position(needle in d)=0 then raise exception 'measurement_source_contract';end if;
 d:=replace(d,needle,'where c.factory_id=f and c.output_id=o and c.source_kind=''RECOVERY'';');
 needle:='and private.output_work_live(f,w.item_id);';
 if position(needle in d)=0 then raise exception 'measurement_pending_contract';end if;
 d:=replace(d,needle,'and private.output_work_live(f,w.item_id) and not exists(select 1 from public.production_orders z where z.factory_id=f and z.id=w.item_id and z.status=''completed'' and z.quality_measurement_delta>0);');
 if position('''pending_work'',pending::text' in d)=0 then raise exception 'measurement_baseline_contract';end if;
 d:=replace(d,'''pending_work'',pending::text','''pending_work'',pending::text,''ordinary_remaining'',baseline::text');execute d;
 d:=pg_get_functiondef('private.quality_production_distribution(uuid,uuid,numeric)'::regprocedure);
 needle:='where factory_id=f and output_id=o)';if position(needle in d)=0 then raise exception 'measurement_distribution_contract';end if;
 execute replace(d,needle,'where factory_id=f and output_id=o and source_kind=''RECOVERY'')');
 d:=pg_get_functiondef('public.plan_production_compensation(uuid,uuid,jsonb,bigint,uuid)'::regprocedure);
 needle:='where factory_id=factory and output_id=h.id and id<>request_id;';if position(needle in d)=0 then raise exception 'measurement_recovery_writer_contract';end if;
 execute replace(d,needle,'where factory_id=factory and output_id=h.id and id<>request_id and source_kind=''RECOVERY'';');
end$migration$;

create function private.measurement_makeup_state(f uuid,o uuid,context jsonb default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare h private.manufactured_outputs;e public.production_entries;j public.production_orders;q jsonb;s jsonb;delta numeric;allocated numeric;uncovered numeric;available numeric;why text;begin
 select * into h from private.manufactured_outputs where factory_id=f and id=o;
 if h.id is null then raise exception 'output_not_found';end if;
 select * into e from public.production_entries where factory_id=f and id=h.entry_id;
 select * into j from public.production_orders where factory_id=f and id=h.item_id;
 q:=private.output_quality(f,o);s:=coalesce(context,private.production_compensation_state(f,o));
 delta:=case when q is null then 0 else greatest(e.effective_good+coalesce(e.effective_unfinished,0)-coalesce((q->>'total')::numeric,
 (select coalesce(sum((g->>'quantity')::numeric),0) from jsonb_array_elements(q->'groups')g)+coalesce((q->>'rejected')::numeric,0)),0) end;
 select coalesce(sum(c.quantity),0) into allocated from private.production_compensation c where c.factory_id=f and c.output_id=o and c.source_kind='MEASUREMENT';
 uncovered:=greatest((s->>'original_target')::numeric-(s->>'accepted')::numeric-(s->>'pending_inspection')::numeric-(s->>'pending_work')::numeric-(s->>'active_allowance_remaining')::numeric-(s->>'ordinary_remaining')::numeric,0);
 why:=case when q is null then 'output_quality_required' when e.input_lot_id is not null then 'output_measurement_input_reconciliation'
 when s->>'blocked_reason'='output_quality_hold' then 'output_quality_hold' when j.status='active' then 'CONTINUE_ORIGINAL'
 when j.status<>'completed' then 'output_execution_required' when delta<=allocated or uncovered<=0 then 'output_demand_covered' end;
 available:=case when why is null then least(greatest(delta-allocated,0),uncovered) else 0 end;
 return jsonb_build_object('source_shortage',coalesce(delta,0)::text,'allocated',allocated::text,'available',coalesce(available,0)::text,
 'ordinary_remaining',private.ordinary_output_remaining(f,h.item_id)::text,'source_status',j.status,'source_item_id',j.id,'demand_item_id',s->>'demand_item_id','blocked_reason',why,
 'work',(select coalesce(jsonb_agg(jsonb_build_object('item_id',c.item_id,'code',p.code,'quantity',c.quantity::text,'status',p.status)order by c.created_at,c.id),'[]') from private.production_compensation c join public.production_orders p on p.factory_id=f and p.id=c.item_id where c.factory_id=f and c.output_id=o and c.source_kind='MEASUREMENT'));
end$$;

create function public.plan_measurement_makeup(factory uuid,target uuid,payload jsonb,expected_revision bigint,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare h private.manufactured_outputs;j public.production_orders;c private.production_compensation;s jsonb;m jsonb;q numeric;pr uuid;i uuid;r jsonb;intent jsonb;why text;begin
 perform private.manufactured_output_authorize(factory,'DISPOSITION',expected_revision);
 perform private.require_permission(factory,'orders','create');perform private.require_permission(factory,'orders','approve');
 if current_setting('transaction_isolation')<>'read committed' then raise exception 'recording_isolation' using errcode='40001';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.fulfillment_lock(factory);perform pg_advisory_xact_lock(hashtextextended(factory::text||':structure',0));
 perform private.manufactured_output_authorize(factory,'DISPOSITION',expected_revision);perform private.require_permission(factory,'orders','create');perform private.require_permission(factory,'orders','approve');
 if not private.manufactured_output_enabled(factory) then raise exception 'recording_disabled';end if;
 if request_id is null or jsonb_typeof(payload) is distinct from 'object' or exists(select 1 from jsonb_object_keys(payload) k where k not in('quantity','recording_complete_confirmation')) or payload->'recording_complete_confirmation' is distinct from 'true'::jsonb then raise exception 'output_recording_confirmation' using errcode='22023';end if;
 intent:=jsonb_build_object('target',target,'payload',payload,'expected',expected_revision,'source_kind','MEASUREMENT');
 select * into c from private.production_compensation where factory_id=factory and id=request_id;
 if found then if c.created_by<>auth.uid() or c.source_kind<>'MEASUREMENT' or c.intent<>intent then raise exception 'request_conflict' using errcode='40001';end if;return c.result;end if;
 select * into h from private.manufactured_outputs where factory_id=factory and id=target for update;
 if h.id is null then raise exception 'output_not_found';end if;
 select * into j from public.production_orders where factory_id=factory and id=h.item_id for update;
 s:=private.production_compensation_state(factory,target);m:=private.measurement_makeup_state(factory,target,s);
 if (s->>'revision')::bigint is distinct from expected_revision then raise exception 'output_revision' using errcode='40001';end if;
 q:=(payload->>'quantity')::numeric;
 if j.status<>'completed' or m->>'blocked_reason' is not null or q is null or q<=0 or q::text in('NaN','Infinity','-Infinity') or q>(m->>'available')::numeric or (h.unit='piece' and q<>trunc(q)) then raise exception 'output_measurement_unavailable' using errcode='40001';end if;
 why:=left('Quality measurement correction for '||j.code||': '||coalesce(private.output_quality(factory,target)->>'reason','Verified actual output'),2000);
 pr:=public.create_production_request(factory,'Measurement make-up production','high',null,why,jsonb_build_array(jsonb_build_object('product_id',h.product_id,'quantity',q,'unit',h.unit)));
 select p.id into i from public.production_orders p where p.factory_id=factory and p.request_id=pr;
 update public.production_orders set replacement_original_item_id=j.id where factory_id=factory and id=i;
 r:=jsonb_build_object('compensation_id',request_id,'item_id',i,'code',(select code from public.production_orders where id=i),'origin_item_id',j.id,'mode','PLANNED','quantity',q::text,'source_kind','MEASUREMENT');
 insert into private.production_compensation(factory_id,id,output_id,quality_revision,demand_item_id,item_id,mode,quantity,execution_start,line_id,reason,intent,result,created_by,created_at,source_kind)
 values(factory,request_id,h.id,(s->>'quality_revision')::bigint,(s->>'demand_item_id')::uuid,i,'PLANNED',q,null,null,why,intent,r,auth.uid(),clock_timestamp(),'MEASUREMENT');
 insert into private.manufactured_completion_work values(factory,i,h.id,null,null,h.item_id,(s->>'demand_item_id')::uuid,'REPLACE',q,'[]',null,request_id,intent,r,auth.uid(),clock_timestamp());
 return r;
end$$;

create function private.measurement_recording_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.effective_good+coalesce(new.effective_unfinished,0)>0 and exists(select 1 from private.production_compensation c join private.manufactured_outputs h on h.factory_id=c.factory_id and h.id=c.output_id
 where c.factory_id=new.factory_id and h.item_id=new.order_id and c.source_kind='MEASUREMENT') then raise exception 'output_measurement_work_committed' using errcode='40001';end if;
 return new;
end$$;
create trigger measurement_recording_guard before insert on public.production_entries for each row execute function private.measurement_recording_guard();

do $migration$declare d text;needle text;begin
 d:=pg_get_functiondef('public.production_compensation_read(uuid,uuid)'::regprocedure);
 needle:='return s||jsonb_build_object(';if position(needle in d)=0 then raise exception 'measurement_reader_contract';end if;
 execute replace(d,needle,'return s||jsonb_build_object(''measurement'',private.measurement_makeup_state(factory,target,s))||jsonb_build_object(');
end$migration$;
create function public.production_recording_progress(factory uuid,item uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare j public.production_orders;modern boolean;begin
 perform private.require_permission(factory,'orders','view');select * into j from public.production_orders where factory_id=factory and id=item;
 if not found then raise exception 'not_found' using errcode='P0002';end if;
 modern:=exists(select 1 from private.manufactured_outputs where factory_id=factory and item_id=item) or exists(select 1 from private.manufactured_completion_work where factory_id=factory and item_id=item);
 return jsonb_build_object('id',j.id,'factory_id',factory,'code',j.code,'unit',j.unit,'status',j.status,'actual_start',j.actual_start,'actual_finish',j.actual_finish,'request_id',j.request_id,
 'target_quantity',j.target_quantity::text,'good_quantity',j.good_quantity::text,'quality_measurement_delta',j.quality_measurement_delta::text,'quality_output_good_delta',j.quality_output_good_delta::text,
 'produced_good',case when modern then j.fulfillment_good_quantity::text else j.good_quantity::text end,'ordinary_remaining',(case when j.status='completed' then least(private.ordinary_output_remaining(factory,item),j.accepted_remaining_quantity) else private.ordinary_output_remaining(factory,item) end)::text,'remaining_demand',j.accepted_remaining_quantity::text,
 'makeup_committed',exists(select 1 from private.production_compensation c join private.manufactured_outputs h on h.factory_id=c.factory_id and h.id=c.output_id where c.factory_id=factory and h.item_id=item and c.source_kind='MEASUREMENT'),
 'replacement_original_item_id',j.replacement_original_item_id,'quality_origin_rejection_id',j.quality_origin_rejection_id,
 'request_type',(select request_type from public.production_requests where factory_id=factory and id=j.request_id));
end$$;

revoke all on function private.output_measurement_delta(uuid,uuid),private.output_good_delta(uuid,uuid),private.ordinary_output_remaining(uuid,uuid),private.project_quality_measurement(),private.measurement_makeup_state(uuid,uuid,jsonb),private.measurement_recording_guard() from public,anon,authenticated;
revoke all on function public.production_recording_progress(uuid,uuid),public.plan_measurement_makeup(uuid,uuid,jsonb,bigint,uuid) from public,anon;
grant execute on function public.production_recording_progress(uuid,uuid),public.plan_measurement_makeup(uuid,uuid,jsonb,bigint,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
