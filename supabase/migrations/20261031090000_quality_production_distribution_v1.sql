-- One atomic, actor-bound decision; reuses replacement and internal stock requests.
begin;
create table private.quality_production_decisions(
 factory_id uuid not null references public.factories(id), id uuid not null,
 output_id uuid not null, created_by uuid not null, created_at timestamptz not null default clock_timestamp(),
 intent jsonb not null, evidence jsonb not null, result jsonb not null, primary key(factory_id,id)
);
alter table private.quality_production_decisions enable row level security;
revoke all on private.quality_production_decisions from public,anon,authenticated,service_role;
create trigger quality_production_decision_immutable before update or delete on private.quality_production_decisions
 for each row execute function private.manufactured_output_immutable();

-- Match the existing rejection-first writer, including earlier allocations.
create function private.quality_production_distribution(f uuid,o uuid,q numeric) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare s jsonb;a numeric;r numeric;u numeric;begin
 s:=private.production_compensation_state(f,o);a:=(s->>'available')::numeric;
 r:=least(a,greatest((s->>'rejected')::numeric-coalesce((select sum(quantity) from private.production_compensation where factory_id=f and output_id=o),0),0));
 u:=a-r;
 return jsonb_build_object('eligible',a::text,'rejected_available',r::text,'unfinished_available',u::text,
 'rejected',least(q,r)::text,'unfinished',least(greatest(q-r,0),u)::text,'stock',greatest(q-a,0)::text,'uncovered',greatest(a-q,0)::text);
end$$;
revoke all on function private.quality_production_distribution(uuid,uuid,numeric) from public,anon,authenticated,service_role;

create function public.plan_quality_production(factory uuid,target uuid,payload jsonb,expected_revision bigint,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare old private.quality_production_decisions;h private.manufactured_outputs;s jsonb;dist jsonb;intent jsonb;replacement jsonb;
 total numeric;rep numeric;extra numeric;pr uuid;item uuid;why text;answer jsonb;begin
 perform private.manufactured_output_authorize(factory,'DISPOSITION',expected_revision);perform private.require_permission(factory,'orders','create');
 if current_setting('transaction_isolation')<>'read committed' then raise exception 'recording_isolation' using errcode='40001';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.fulfillment_lock(factory);
 perform pg_advisory_xact_lock(hashtextextended(factory::text||':structure',0));
 perform private.manufactured_output_authorize(factory,'DISPOSITION',expected_revision);perform private.require_permission(factory,'orders','create');
 if not private.manufactured_output_enabled(factory) then raise exception 'recording_disabled';end if;
 if request_id is null or target is null or expected_revision is null or jsonb_typeof(payload) is distinct from 'object'
 or exists(select 1 from jsonb_object_keys(payload) k where k not in('quantity','mode'))
 or jsonb_typeof(payload->'quantity') is distinct from 'string' or length(payload->>'quantity')>128 then raise exception 'output_disposition';end if;
 intent:=jsonb_build_object('target',target,'payload',payload,'expected',expected_revision);
 select * into old from private.quality_production_decisions where factory_id=factory and id=request_id;
 if found then if old.created_by<>auth.uid() or old.intent<>intent then raise exception 'request_conflict' using errcode='40001';end if;return old.result;end if;
 -- Do not reinterpret a UUID previously submitted to another protected workflow.
 if exists(select 1 from private.production_compensation where factory_id=factory and id=request_id)
 or exists(select 1 from private.manufactured_completion_work where factory_id=factory and manufactured_completion_work.request_id=plan_quality_production.request_id)
 then raise exception 'request_conflict' using errcode='40001';end if;
 select * into h from private.manufactured_outputs where factory_id=factory and id=target for update;
 if h.id is null then raise exception 'output_not_found';end if;
 s:=private.production_compensation_state(factory,target);
 if (s->>'revision')::bigint is distinct from expected_revision then raise exception 'output_revision' using errcode='40001';end if;
 if s->>'blocked_reason' is not null then raise exception '%',s->>'blocked_reason';end if;
 -- Moving an ended allowance is a separate existing, explicitly confirmed operation.
 if s->'transfer_allowance'<>'null'::jsonb then raise exception 'output_recording_confirmation';end if;
 total:=(payload->>'quantity')::numeric;
 if total is null or total<=0 or total::text in('NaN','Infinity','-Infinity') or(h.unit='piece' and total<>trunc(total)) then raise exception 'output_compensation_quantity';end if;
 dist:=private.quality_production_distribution(factory,target,total);rep:=least(total,(s->>'available')::numeric);extra:=(dist->>'stock')::numeric;
 -- Existing writer retains source holds/physical eligibility, capacity, shift and revision guards.
 replacement:=public.plan_production_compensation(factory,target,jsonb_build_object('quantity',rep::text,'mode',payload->>'mode'),expected_revision,request_id);
 why:=left('Additional stock production after Quality finding '||(s->>'quality_revision')||' on '||
 (select code from public.production_orders where factory_id=factory and id=h.item_id)||': '||coalesce(private.output_quality(factory,target)->>'reason','Reviewed production output'),2000);
 if extra>0 then
  pr:=public.create_production_request(factory,'Additional stock production','normal',null,why,
   jsonb_build_array(jsonb_build_object('product_id',h.product_id,'quantity',extra::text,'unit',h.unit)));
  select po.id into item from public.production_orders po where po.factory_id=factory and po.request_id=pr;
 end if;
 answer:=jsonb_build_object('decision_id',request_id,'total',total::text,'distribution',dist,'replacement',replacement,
 'stock',case when pr is not null then jsonb_build_object('request_id',pr,'item_id',item,'quantity',extra::text,'unit',h.unit) end);
 insert into private.quality_production_decisions(factory_id,id,output_id,created_by,intent,evidence,result)
 values(factory,request_id,target,auth.uid(),intent,jsonb_build_object('quality_revision',s->>'quality_revision','quality',private.output_quality(factory,target),'original_item',h.item_id,'unit',h.unit),answer);
 perform private.manufactured_output_authorize(factory,'DISPOSITION',expected_revision);perform private.require_permission(factory,'orders','create');
 return answer;
end$$;
revoke all on function public.plan_quality_production(uuid,uuid,jsonb,bigint,uuid) from public,anon,service_role;
grant execute on function public.plan_quality_production(uuid,uuid,jsonb,bigint,uuid) to authenticated;

-- Preserve existing capacity/fallback reader and add protected split/work metadata.
do $$declare b text;needle text;begin
 b:=pg_get_functiondef('public.production_compensation_read(uuid,uuid)'::regprocedure);
 needle:='return s||jsonb_build_object(''decisions'',';
 if position(needle in b)=0 then raise exception 'Compensation reader changed';end if;
 execute replace(b,needle,'return s||jsonb_build_object(''distribution'',private.quality_production_distribution(factory,target,0),
 ''stock_work'',(select coalesce(jsonb_agg(jsonb_build_object(''id'',d.id,''item_id'',p.id,''code'',p.code,''quantity'',p.target_quantity::text,''status'',p.status,''planned_start'',p.start_time,''request_id'',p.request_id)order by d.created_at),''[]''::jsonb) from private.quality_production_decisions d join public.production_orders p on p.factory_id=d.factory_id and p.id=(d.result#>>''{stock,item_id}'')::uuid where d.factory_id=factory and d.output_id=target))||jsonb_build_object(''decisions'',');
end$$;
commit;
