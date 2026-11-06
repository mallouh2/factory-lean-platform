begin;
-- Follow-up evidence is independent of inspection acceptance, stock and ACKs.
create table private.production_quality_followup_events(
 sequence bigint generated always as identity primary key,
 factory_id uuid not null references public.factories(id),output_id uuid not null references private.manufactured_outputs(id),
 quality_revision bigint not null,operation text not null check(operation in('FINDING','START','RESOLVE')),
 state text check(state in('NEEDS_ACTION','IN_PROGRESS','RESOLVED')),payload jsonb not null,
 request_id uuid not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(factory_id,request_id));
alter table private.production_quality_followup_events enable row level security;
revoke all on private.production_quality_followup_events from public,anon,authenticated,service_role;
create trigger production_quality_followup_immutable before update or delete on private.production_quality_followup_events for each row execute function private.manufactured_output_immutable();
create index production_quality_followup_output on private.production_quality_followup_events(factory_id,output_id,quality_revision,sequence desc);

create function private.production_quality_followup(f uuid,o uuid)returns jsonb language plpgsql stable set search_path='' as $$
declare h private.manufactured_outputs;q jsonb;e private.production_quality_followup_events;v bigint;material boolean;meta jsonb;shortage numeric;begin
 select * into h from private.manufactured_outputs where factory_id=f and id=o;
 q:=private.output_finding(f,o);if h.id is null or q is null then return null;end if;
 select max(revision)into v from private.manufactured_output_events where factory_id=f and output_id=o and operation='QUALITY';
 select payload into meta from private.production_quality_followup_events where factory_id=f and output_id=o and quality_revision=v and operation='FINDING';
 material:=private.output_material_difference(h.recorded_groups,q);
 if not material and not coalesce((meta->>'requires_followup')::boolean,false)then
  -- An ordinary subsequent inspection cannot silently resolve an open action.
  select ev.quality_revision,ev.payload into v,meta from private.production_quality_followup_events ev
  where ev.factory_id=f and ev.output_id=o and ev.operation='FINDING'
  and(coalesce((ev.payload->>'requires_followup')::boolean,false)or private.output_material_difference(h.recorded_groups,ev.payload))
  order by ev.sequence desc limit 1;
  if not found then return null;end if;
 end if;
 select * into e from private.production_quality_followup_events where factory_id=f and output_id=o and quality_revision=v order by sequence desc limit 1;
 select greatest(target_quantity-private.output_demand_received(f,h.item_id),0)into shortage from public.production_orders where factory_id=f and id=h.item_id;
 return jsonb_build_object('state',coalesce(e.state,'NEEDS_ACTION'),'status_revision',coalesce(e.sequence,0),'quality_revision',v,
 'observation',meta->>'observation','requested_action',meta->>'requested_action','material_change',material,'remaining_finished_demand',shortage::text,
 'resolution_available',not material or (coalesce(shortage,1)=0 and not exists(select 1 from private.manufactured_outputs z left join private.manufactured_completion_work w on w.factory_id=f and w.item_id=z.item_id where z.factory_id=f and(z.item_id=h.item_id or w.demand_item_id=h.item_id)and private.output_source_held(f,z.entry_id))),'actor',e.created_by,'at',e.created_at,
 'history',(select coalesce(jsonb_agg(jsonb_build_object('state',state,'actor',created_by,'at',created_at,'note',payload->>'note')order by sequence),'[]')from private.production_quality_followup_events where factory_id=f and output_id=o and quality_revision=v));
end$$;
revoke all on function private.production_quality_followup(uuid,uuid)from public,anon,authenticated,service_role;

-- Keep the established public wrapper's authorization/lock/gate order and the
-- original private Quality writer. Extra process observations never enter its
-- quantity, Scrap, reconciliation or disposition payload.
create or replace function public.manufactured_output_command(factory uuid,operation text,target uuid,payload jsonb,expected_revision bigint,request_id uuid)returns jsonb
language plpgsql volatile security definer set search_path='' as $$declare old private.production_quality_followup_events;result jsonb;requested boolean;begin
 if operation not in('QUALITY','ACKNOWLEDGE')or operation is null then raise exception 'output_invalid' using errcode='22023';end if;
 perform private.manufactured_output_authorize(factory,operation,case when operation='QUALITY' then case when exists(select 1 from private.manufactured_output_events ev where ev.factory_id=factory and ev.output_id=target and ev.operation='QUALITY')then 2 else 1 end else expected_revision end);
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));
 if not private.manufactured_output_enabled(factory)then raise exception 'recording_disabled' using errcode='55000';end if;
 if operation='QUALITY' then
  if octet_length(payload::text)>12000 then raise exception 'output_followup_invalid';end if;
  if payload?'requires_followup' and jsonb_typeof(payload->'requires_followup')<>'boolean' then raise exception 'output_followup_invalid';end if;
  requested:=coalesce((payload->>'requires_followup')::boolean,false);
  if requested and(length(btrim(coalesce(payload->>'observation','')))not between 3 and 2000 or length(btrim(coalesce(payload->>'requested_action','')))not between 3 and 2000)then raise exception 'output_followup_invalid';end if;
  select * into old from private.production_quality_followup_events where factory_id=factory and production_quality_followup_events.request_id=manufactured_output_command.request_id;
  if found and(old.operation<>'FINDING'or old.created_by<>auth.uid()or old.output_id<>target or old.payload<>payload)then raise exception 'request_conflict' using errcode='40001';end if;
 end if;
 result:=private.manufactured_output_command(factory,operation,target,payload-array['requires_followup','observation','requested_action'],expected_revision,request_id);
 if operation='QUALITY'and old.sequence is null then
  insert into private.production_quality_followup_events(factory_id,output_id,quality_revision,operation,state,payload,request_id,created_by)
  values(factory,target,(result->>'revision')::bigint,'FINDING','NEEDS_ACTION',payload,request_id,auth.uid());
 end if;
 return result;
end$$;

create function public.production_quality_followup_command(factory uuid,target uuid,operation text,payload jsonb,expected_revision bigint,request_id uuid)returns jsonb
language plpgsql security definer set search_path='' as $$declare s jsonb;e private.production_quality_followup_events;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'orders','edit');
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.fulfillment_lock(factory);
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'orders','edit');
 if not private.manufactured_output_enabled(factory)then raise exception 'recording_disabled'using errcode='55000';end if;
 if request_id is null or expected_revision is null or operation not in('START','RESOLVE')or operation is null or jsonb_typeof(payload)is distinct from 'object' or exists(select 1 from jsonb_object_keys(payload)k where k not in('quality_revision','note'))then raise exception 'output_followup_invalid';end if;
 select * into e from private.production_quality_followup_events where factory_id=factory and production_quality_followup_events.request_id=production_quality_followup_command.request_id;
 if found then
  if e.created_by<>auth.uid()or e.output_id<>target or e.operation<>operation or e.payload-'_expected_revision'<>payload or (e.payload->>'_expected_revision')::bigint is distinct from expected_revision then raise exception 'request_conflict'using errcode='40001';end if;
  return jsonb_build_object('output_id',target,'state',e.state,'status_revision',e.sequence);
 end if;
 perform 1 from private.manufactured_outputs where factory_id=factory and id=target for update;
 s:=private.production_quality_followup(factory,target);
 if s is null or(s->>'quality_revision')::bigint is distinct from(payload->>'quality_revision')::bigint or(s->>'status_revision')::bigint is distinct from expected_revision then raise exception 'output_revision';end if;
 if operation='START'and s->>'state'<>'NEEDS_ACTION' or operation='RESOLVE'and(s->>'state'<>'IN_PROGRESS'or not(s->>'resolution_available')::boolean)then raise exception 'output_followup_blocked';end if;
 if operation='RESOLVE'and length(btrim(coalesce(payload->>'note','')))not between 3 and 2000 then raise exception 'output_reason';end if;
 insert into private.production_quality_followup_events(factory_id,output_id,quality_revision,operation,state,payload,request_id,created_by)
 values(factory,target,(s->>'quality_revision')::bigint,operation,case when operation='START'then 'IN_PROGRESS'else 'RESOLVED'end,payload||jsonb_build_object('_expected_revision',expected_revision),request_id,auth.uid())returning * into e;
 return jsonb_build_object('output_id',target,'state',e.state,'status_revision',e.sequence);
end$$;

create function public.production_quality_followups(factory uuid,page integer default 0,state text default 'outstanding')returns jsonb
language plpgsql security definer set search_path='' as $$declare rows jsonb;total bigint;outstanding bigint;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'orders','view');
 if not private.manufactured_output_enabled(factory)then return jsonb_build_object('available',false,'rows','[]'::jsonb,'outstanding',0);end if;
 if page is null or page not between 0 and 100000 or state is null or state not in('outstanding','NEEDS_ACTION','IN_PROGRESS','RESOLVED')then raise exception 'output_invalid';end if;
 with facts as materialized(select h.*,private.production_quality_followup(factory,h.id)followup from private.manufactured_outputs h where h.factory_id=factory),eligible as(
 select * from facts where followup is not null and(case when state='outstanding'then followup->>'state'<>'RESOLVED'else followup->>'state'=state end)),chosen as(
 select * from eligible order by created_at desc,id offset page*50 limit 50)
 select coalesce((select jsonb_agg((public.manufactured_output_read(factory,'entry',entry_id)->'rows'->0)||jsonb_build_object('followup',followup)order by created_at desc,id)from chosen),'[]'),
 (select count(*)from eligible),(select count(*)from facts where followup is not null and followup->>'state'<>'RESOLVED')into rows,total,outstanding;
 return jsonb_build_object('available',true,'rows',rows,'total',total,'outstanding',outstanding,'has_more',(page+1)*50<total);
end$$;
revoke all on function public.production_quality_followups(uuid,integer,text),public.production_quality_followup_command(uuid,uuid,text,jsonb,bigint,uuid)from public,anon,service_role;
grant execute on function public.production_quality_followups(uuid,integer,text),public.production_quality_followup_command(uuid,uuid,text,jsonb,bigint,uuid)to authenticated;
commit;
