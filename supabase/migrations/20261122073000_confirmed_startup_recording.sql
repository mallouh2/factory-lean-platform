-- Confirmed current-shift startup classification uses the existing startup ledger.
alter table public.lean_startups
  add column execution_run_id uuid references private.production_execution_runs(id);
create unique index lean_startups_confirmed_run_time
  on public.lean_startups(factory_id,execution_run_id,occurred_at)
  where execution_run_id is not null;

create function private.recording_startup_windows(f uuid,i uuid) returns jsonb
language sql stable set search_path='' as $$
  with current_shift as (
    select private.resolve_production_occurrence(f,statement_timestamp())->'occurrence' occurrence
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'from',greatest(r.started_at,(s.occurrence->>'starts_at')::timestamptz),
    'to',least(coalesce(r.ended_at,'infinity'),(s.occurrence->>'ends_at')::timestamptz)
  ) order by r.started_at,r.id),'[]'::jsonb)
  from current_shift s
  join public.production_orders o on o.factory_id=f and o.id=i
  join private.production_execution_runs r on r.factory_id=f and r.item_id=i
    and r.line_id=coalesce(o.actual_line_id,o.line_id)
  where o.status in ('active','completed') and s.occurrence is not null
    and r.state in ('ACTIVE','INTERRUPTED','FINISHED')
    and r.started_at<=statement_timestamp()
    and r.started_at<(s.occurrence->>'ends_at')::timestamptz
    and (r.ended_at is null or r.ended_at>(s.occurrence->>'starts_at')::timestamptz)
$$;

create function private.record_confirmed_startup(f uuid,job public.production_orders,l uuid,
  proposed uuid,at_time timestamptz,occ jsonb) returns public.lean_startups
language plpgsql set search_path='' as $$
declare
  startup public.lean_startups;
  run_id uuid;
  standard public.lean_standards;
  matches integer;
begin
  if l is null or l is distinct from coalesce(job.actual_line_id,job.line_id)
    or at_time is null or at_time<job.actual_start or at_time>clock_timestamp()
    or at_time<(occ->>'starts_at')::timestamptz or at_time>=(occ->>'ends_at')::timestamptz
    or (job.actual_finish is not null and at_time>job.actual_finish) then
    raise exception 'lean_startup_execution' using errcode='22023';
  end if;

  select * into startup from public.lean_startups where id=proposed;
  if found then
    if (startup.factory_id,startup.item_id,startup.product_id,startup.line_id,startup.occurred_at)
      is distinct from (f,job.id,job.product_id,l,at_time) then
      raise exception 'lean_conflict' using errcode='40001';
    end if;
    return startup;
  end if;

  -- The original writer already holds the factory and structure locks.
  -- Resolve the actual run and reuse an existing event at the confirmed time.
  select count(*),min(r.id::text)::uuid into matches,run_id
  from private.production_execution_runs r
  where r.factory_id=f and r.item_id=job.id and r.line_id=l
    and r.state in ('ACTIVE','INTERRUPTED','FINISHED')
    and r.started_at<=at_time and (r.ended_at is null or at_time<r.ended_at);
  if matches<>1 then raise exception 'lean_startup_execution' using errcode='22023';end if;

  select count(*) into matches from public.lean_startups s
  where s.factory_id=f and s.item_id=job.id and s.product_id=job.product_id
    and s.line_id=l and s.occurred_at=at_time;
  if matches>1 then raise exception 'lean_conflict' using errcode='40001';end if;
  if matches=1 then
    select * into startup from public.lean_startups s
    where s.factory_id=f and s.item_id=job.id and s.product_id=job.product_id
      and s.line_id=l and s.occurred_at=at_time;
    return startup;
  end if;
  select * into standard from public.lean_standards where factory_id=f and line_id=l and product_id=job.product_id;
  insert into public.lean_startups(id,factory_id,line_id,item_id,product_id,
    occurred_at,standard_kg,standard_revision,created_by,execution_run_id)
  values(proposed,f,l,job.id,job.product_id,at_time,standard.startup_kg,standard.revision,auth.uid(),run_id)
  returning * into startup;
  return startup;
end$$;
revoke all on function private.recording_startup_windows(uuid,uuid),
  private.record_confirmed_startup(uuid,public.production_orders,uuid,uuid,timestamptz,jsonb)
  from public,anon,authenticated,service_role;

-- Extend the existing permission-checked reader and writer without replacing
-- the recording, shift, replay, correction or inventory contracts.
do $migration$
declare
  writer text:=pg_get_functiondef('private.record_lean_production(uuid,jsonb,uuid)'::regprocedure);
  reader text:=pg_get_functiondef('private.lean_read(uuid,jsonb)'::regprocedure);
  writer_marker text:=$marker$ if p->>'startup_id' is not null then$marker$;
  reader_marker text:=$marker$  result:=jsonb_build_object('causes',$marker$;
  standard_marker text:=$marker$line_id=job.line_id and product_id=job.product_id;$marker$;
begin
  if strpos(writer,writer_marker)=0 or strpos(writer,standard_marker)=0 or strpos(reader,reader_marker)=0 then
    raise exception 'confirmed_startup_recording_contract';
  end if;
  writer:=replace(writer,standard_marker,
    $patch$line_id=case when context is not null and p->>'startup_id' is not null
      then coalesce(job.actual_line_id,job.line_id) else job.line_id end and product_id=job.product_id;$patch$);
  writer:=replace(writer,writer_marker,
    $patch$ if context is not null and p->>'startup_id' is not null then
  startup:=private.record_confirmed_startup(f,job,(p->>'production_unit')::uuid,
    (p->>'startup_id')::uuid,(p->>'startup_at')::timestamptz,context->'occurrence');
 elsif p->>'startup_id' is not null then$patch$);
  reader:=replace(reader,reader_marker,
    $patch$  result:=jsonb_build_object('startup_windows',
    private.recording_startup_windows(f,(q->>'item_id')::uuid),'causes',$patch$);
  execute writer;
  execute reader;
end $migration$;
