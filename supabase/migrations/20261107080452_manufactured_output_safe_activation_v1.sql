-- Explicit operator activation. Deployment alone never changes posting policy.
begin;

create table private.manufactured_output_activation (
 factory_id uuid primary key references public.factories(id),
 enabled boolean not null default false,
 first_activated_at timestamptz,
 revision bigint not null default 0 check(revision>=0),
 changed_at timestamptz not null default clock_timestamp(),
 changed_by uuid references auth.users(id),
 operator_role text not null default current_user,
 reason text not null default '',
 check(not enabled or first_activated_at is not null)
);
alter table private.manufactured_output_activation enable row level security;
revoke all on private.manufactured_output_activation from public,anon,authenticated,service_role;

create function private.output_activation_history_guard() returns trigger
language plpgsql set search_path='' as $$begin
 if tg_op='DELETE' or (old.first_activated_at is not null and new.first_activated_at is distinct from old.first_activated_at)
 then raise exception 'output_activation_history_immutable' using errcode='23514';end if;
 return new;
end$$;
create trigger preserve_first_activation before update or delete on private.manufactured_output_activation
for each row execute function private.output_activation_history_guard();

-- No application role is granted execution. Invoke manually as the migration
-- owner/operator, only after separately authorized factory readiness review.
create function private.set_manufactured_output_activation(factory uuid,enable boolean,expected_revision bigint,reason text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare a private.manufactured_output_activation;before_state jsonb;begin
 if current_setting('transaction_isolation')<>'read committed' then raise exception 'output_isolation' using errcode='40001';end if;
 if enable is null or expected_revision is null or expected_revision<0 or length(btrim(coalesce(reason,''))) not between 3 and 2000
 then raise exception 'output_activation_invalid' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));
 perform pg_advisory_xact_lock(hashtextextended(factory::text||':structure',0));
 if not exists(select 1 from public.factories where id=factory) then raise exception 'output_not_found' using errcode='22023';end if;
 insert into private.manufactured_output_activation(factory_id) values(factory) on conflict do nothing;
 select * into a from private.manufactured_output_activation where factory_id=factory for update;
 if a.revision<>expected_revision then raise exception 'output_activation_changed' using errcode='40001';end if;
 if enable and exists(select 1 from public.unfinished_lots where factory_id=factory and manufactured_group_id is null and quantity_available>0)
 then raise exception 'output_carryover_unsupported' using errcode='23514';end if;
 before_state:=to_jsonb(a);
 update private.manufactured_output_activation set enabled=enable,
 first_activated_at=case when enable then coalesce(a.first_activated_at,clock_timestamp()) else a.first_activated_at end,
 revision=a.revision+1,changed_at=clock_timestamp(),changed_by=auth.uid(),operator_role=current_user,reason=btrim(set_manufactured_output_activation.reason)
 where factory_id=factory returning * into a;
 insert into public.audit_logs(factory_id,actor_id,action,entity,entity_id,old_data,new_data)
 values(factory,auth.uid(),'ACTIVATION','manufactured_output_activation',factory,before_state,to_jsonb(a));
 return jsonb_build_object('enabled',a.enabled,'revision',a.revision,'first_activated_at',a.first_activated_at);
end$$;

create or replace function private.manufactured_output_enabled(f uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce((select enabled from private.manufactured_output_activation where factory_id=f),false)
$$;
create function private.manufactured_output_readable(f uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.manufactured_output_activation where factory_id=f and first_activated_at is not null)
$$;
create function private.output_activation_status(f uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('write_enabled',private.manufactured_output_enabled(f),'activation_state',
 case when private.manufactured_output_enabled(f) then 'ENABLED' when private.manufactured_output_readable(f) then 'PAUSED' else 'NEVER_ACTIVATED' end)
$$;
create or replace function public.manufactured_output_capability(factory uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$begin
 perform private.require_permission(factory,'factory','view');
 return private.output_activation_status(factory)||jsonb_build_object('available',private.manufactured_output_enabled(factory),
 'schema_version',1,'scope','MANUFACTURED_OUTPUT_ONLY');
end$$;

-- One storage boundary for fresh manufactured facts. Existing RPC retry checks
-- run unchanged, with current actor/intent authorization, before these writes.
create function private.output_activation_write_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare f uuid;begin
 if current_setting('transaction_isolation')<>'read committed' then raise exception 'output_isolation' using errcode='40001';end if;
 if tg_op='DELETE' then f:=old.factory_id;else f:=new.factory_id;end if;
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));
 perform pg_advisory_xact_lock(hashtextextended(f::text||':structure',0));
 perform 1 from private.manufactured_output_activation where factory_id=f for share;
 if not private.manufactured_output_enabled(f) then raise exception 'output_paused' using errcode='55000';end if;
 if tg_op='DELETE' then return old;end if;return new;
end$$;
do $$declare t text;begin
 foreach t in array array['manufactured_output_context','manufactured_outputs','manufactured_output_events',
 'manufactured_output_lots','manufactured_output_adjustments','manufactured_completion_work',
 'production_quality_followup_events','production_compensation','production_compensation_entries',
 'production_compensation_releases','quality_production_decisions'] loop
 execute format('create trigger activation_write_guard before insert or update or delete on private.%I for each row execute function private.output_activation_write_guard()',t);
 end loop;
end$$;

-- Fresh legacy inserts cannot switch posting policy after the first activation.
-- Existing entry updates/corrections and committed legacy retries are untouched.
create function private.output_recording_admission_guard() returns trigger
language plpgsql security definer set search_path='' as $$begin
 if (greatest(coalesce(new.good_quantity,0),coalesce(new.produced-new.rejected,0))>0 or coalesce(new.unfinished_quantity,0)>0)
 and current_setting('transaction_isolation')<>'read committed'
 then raise exception 'output_isolation' using errcode='40001';end if;
 perform pg_advisory_xact_lock(hashtextextended(new.factory_id::text,0));
 perform pg_advisory_xact_lock(hashtextextended(new.factory_id::text||':structure',0));
 if private.manufactured_output_readable(new.factory_id) and new.input_lot_id is not null
 and exists(select 1 from public.unfinished_lots where factory_id=new.factory_id and id=new.input_lot_id and manufactured_group_id is null)
 then raise exception 'output_carryover_unsupported' using errcode='23514';end if;
 if private.manufactured_output_readable(new.factory_id)
 and (greatest(coalesce(new.good_quantity,0),coalesce(new.produced-new.rejected,0))>0 or coalesce(new.unfinished_quantity,0)>0)
 and not private.manufactured_output_context_matches(new.factory_id,new.id,new.request_id,'RECORD')
 then raise exception 'output_enrollment_required' using errcode='55000';end if;
 return new;
end$$;
create trigger output_admission before insert on public.production_entries
for each row execute function private.output_recording_admission_guard();

-- Keep the established factory -> structure order even for direct legacy RPCs.
do $$declare b text;n text:=' perform private.require_permission(f,''orders'',''edit'');';begin
 b:=pg_get_functiondef('private.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,text,numeric,text,uuid,numeric,jsonb,jsonb)'::regprocedure);
 if position(n in b)=0 then raise exception 'output_admission_contract_changed';end if;
 execute replace(b,n,n||E'\n perform pg_advisory_xact_lock(hashtextextended(f::text,0));\n perform private.require_permission(f,''orders'',''edit'');');
end$$;

-- Allow the original protected RPCs to reach their immutable retry lookups when
-- paused. Fresh changes still fail atomically at the shared write guard above.
do $$declare s text;b text;begin
 foreach s in array array[
 'public.record_manufactured_output(uuid,jsonb,uuid)',
 'public.manufactured_output_command(uuid,text,uuid,jsonb,bigint,uuid)',
 'public.receive_manufactured_output(uuid,uuid,jsonb,bigint,uuid)',
 'public.reconcile_manufactured_output(uuid,uuid,uuid,jsonb,bigint,uuid)',
 'public.plan_manufactured_completion(uuid,uuid,jsonb,bigint,uuid)',
 'public.revise_manufactured_completion(uuid,uuid,jsonb,bigint,uuid)',
 'public.plan_production_compensation(uuid,uuid,jsonb,bigint,uuid)',
 'public.plan_quality_production(uuid,uuid,jsonb,bigint,uuid)',
 'public.plan_measurement_makeup(uuid,uuid,jsonb,bigint,uuid)',
 'private.apply_manufactured_output_correction(uuid,jsonb,uuid)'] loop
 b:=pg_get_functiondef(s::regprocedure);
 if position('private.manufactured_output_enabled(' in b)=0 then raise exception 'output_activation_contract_changed: %',s;end if;
 execute replace(b,'private.manufactured_output_enabled(','private.manufactured_output_readable(');
 end loop;
end$$;

-- Read-only history stays visible while paused. Options never offer legacy
-- fallback once the factory crossed the accounting boundary.
do $$declare s text;b text;begin
 foreach s in array array['public.manufactured_output_read(uuid,text,uuid,integer)',
 'public.manufactured_receiving_read(uuid,integer)','public.manufactured_receiving_context(uuid,uuid,integer)'] loop
 b:=pg_get_functiondef(s::regprocedure);
 if position('private.manufactured_output_enabled(' in b)=0 then raise exception 'output_reader_contract_changed: %',s;end if;
 b:=replace(b,'private.manufactured_output_enabled(','private.manufactured_output_readable(');
 b:=replace(b,'''available'',true',E'''write_enabled'',private.manufactured_output_enabled(factory),''activation_state'',private.output_activation_status(factory)->>''activation_state'',''available'',true');
 if s='public.manufactured_output_read(uuid,text,uuid,integer)' then
 b:=replace(b,' if mode=''options'' then',E' if mode=''options'' and not private.manufactured_output_enabled(factory) then return private.output_activation_status(factory)||jsonb_build_object(''available'',false,''rows'',''[]''::jsonb);end if;\n if mode=''options'' then');
 b:=replace(b,'''can_inspect'',is_quality and','''can_inspect'',private.manufactured_output_enabled(factory) and is_quality and');
 end if;
 execute b;
 end loop;
end$$;

revoke all on function private.set_manufactured_output_activation(uuid,boolean,bigint,text),
private.output_activation_history_guard(),private.manufactured_output_enabled(uuid),
private.manufactured_output_readable(uuid),private.output_activation_status(uuid),
private.output_activation_write_guard(),private.output_recording_admission_guard()
from public,anon,authenticated,service_role;
revoke all on function public.manufactured_output_capability(uuid) from public,anon,service_role;
grant execute on function public.manufactured_output_capability(uuid) to authenticated;
commit;
