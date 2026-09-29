-- Run on TESTING after the V1 migration. Every fixture is rolled back.
begin;

create function pg_temp.expect_downtime_error(statement text, expected text)
returns void language plpgsql as $$
begin
  begin
    execute statement;
  exception when others then
    if sqlerrm=expected then return; end if;
    raise exception 'expected %, got %',expected,sqlerrm;
  end;
  raise exception 'expected % but command succeeded',expected;
end;
$$;

do $verify$
declare
  f uuid; actor uuid; category uuid; existing_item uuid;
  line_a uuid; line_b uuid; source_id uuid; downstream_id uuid; borrowed_id uuid;
  initial_reason uuid; other_reason uuid; legacy_reason uuid; first_event uuid; borrowed_event uuid;
  reviewed_event uuid; switch_event uuid; transfer_source_event uuid;
  retro_event uuid; transfer_id uuid;
  started timestamptz; ended timestamptz; entered timestamptz;
  prefix text := 'DTV1-'||substr(replace(gen_random_uuid()::text,'-',''),1,12);
begin
  select m.factory_id,m.user_id into f,actor
  from public.memberships m join public.factories fac on fac.id=m.factory_id
  where fac.is_demo and m.status='approved' and m.is_owner limit 1;
  if f is null then raise exception 'TESTING demo owner unavailable'; end if;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  if not private.has_permission(f,'machine_status','edit')
    or not private.has_permission(f,'downtime','edit') then
    raise exception 'TESTING owner downtime permissions unavailable'; end if;
  select id into category from public.work_center_categories
    where factory_id=f and not archived order by name limit 1;
  select id into existing_item from public.production_orders
    where factory_id=f order by created_at limit 1;
  if category is null or existing_item is null then
    raise exception 'TESTING category or product item unavailable'; end if;
  select id into initial_reason from public.downtime_reasons
    where factory_id=f and name='Mechanical Failure' and parent_id is null limit 1;
  select id into other_reason from public.downtime_reasons
    where factory_id=f and name='Electrical Failure' and parent_id is null limit 1;
  select id into legacy_reason from public.downtime_reasons
    where factory_id=f and name='Planned Maintenance' and parent_id is null limit 1;
  if initial_reason is null or other_reason is null then
    raise exception 'TESTING top-level reasons unavailable'; end if;
  if (select count(*) from public.downtime_reasons
      where factory_id=f and parent_id is null and name in
        ('Mechanical Failure','Electrical Failure','Material Shortage',
         'Quality Problem','Setup / Changeover','Utilities','Other'))<>7 then
    raise exception 'current seven-category catalog incomplete'; end if;
  if exists(select 1 from public.downtime_reasons where factory_id=f
    and name='Other' and parent_id is null and requires_description) then
    raise exception 'Other still requires a detailed note'; end if;
  perform pg_temp.expect_downtime_error(format(
    'insert into public.downtime_reasons(factory_id,name) values(%L::uuid,%L)',
    f,'Old duplicate category'),'downtime_catalog_fixed');
  perform pg_temp.expect_downtime_error(format(
    'update public.downtime_reasons set name=%L where id=%L::uuid',
    'Renamed category',initial_reason),'downtime_catalog_fixed');
  if legacy_reason is not null then
    perform pg_temp.expect_downtime_error(format(
      'delete from public.downtime_reasons where id=%L::uuid',legacy_reason),
      'downtime_catalog_fixed');
  end if;

  insert into public.production_lines(factory_id,name,code)
    values(f,prefix||' source line',prefix||'-L1') returning id into line_a;
  insert into public.production_lines(factory_id,name,code)
    values(f,prefix||' borrowed line',prefix||'-L2') returning id into line_b;
  insert into public.work_centers(factory_id,name,code,category_id,line_id,status,
    dependency_mode,impact_scope,position)
    values(f,prefix||' source',prefix||'-SRC',category,line_a,'running',
      'blocking','downstream',0) returning id into source_id;
  insert into public.work_centers(factory_id,name,code,category_id,line_id,status,
    dependency_mode,position)
    values(f,prefix||' downstream',prefix||'-DST',category,line_a,'running',
      'non_blocking',1) returning id into downstream_id;
  insert into public.work_centers(factory_id,name,code,category_id,line_id,status,
    dependency_mode,position)
    values(f,prefix||' borrowed',prefix||'-ALT',category,line_b,'running',
      'independent',0) returning id into borrowed_id;

  perform pg_temp.expect_downtime_error(format(
    'select public.change_status(%L::uuid,%L::uuid,%L)',
    f,source_id,'stopped'),'reason_required');
  if (select status from public.work_centers where id=source_id)<>'running'
    or exists(select 1 from public.downtime_events where work_center_id=source_id) then
    raise exception 'missing reason changed machine or created downtime'; end if;
  if legacy_reason is not null then
    perform pg_temp.expect_downtime_error(format(
      'select public.change_status(%L::uuid,%L::uuid,%L,%L::uuid)',
      f,source_id,'stopped',legacy_reason),'reason_required');
  end if;
  perform public.change_status(f,source_id,'stopped',initial_reason,null,'Belt slipped');
  select id,started_at into first_event,started from public.downtime_events
    where factory_id=f and work_center_id=source_id and ended_at is null;
  if first_event is null or started is null or not exists(
    select 1 from public.downtime_events where id=first_event and reason_id=initial_reason
      and initial_entered_at is not null and initial_note='Belt slipped'
      and initial_entered_by=actor and entered_by=actor
      and line_id=line_a and impact_scope_at_start='downstream'
      and blocking_at_start=true) then
    raise exception 'initial stop reason, note, audit or context failed'; end if;
  if (select status from public.work_centers where id=source_id)<>'stopped' then
    raise exception 'physical machine state did not stop'; end if;
  if exists(select 1 from public.downtime_events
    where work_center_id=downstream_id) then
    raise exception 'downstream machine received duplicate downtime'; end if;
  perform pg_temp.expect_downtime_error(format(
    'insert into public.downtime_events(factory_id,work_center_id,created_by) values(%L::uuid,%L::uuid,%L::uuid)',
    f,source_id,actor),'duplicate key value violates unique constraint "one_open_downtime"');

  select initial_entered_at into entered from public.downtime_events where id=first_event;
  perform pg_temp.expect_downtime_error(format(
    'select public.set_downtime_initial(%L::uuid,%L::uuid,%L::uuid,%L)',
    f,first_event,other_reason,'changed'),'downtime_initial_locked');
  perform pg_temp.expect_downtime_error(format(
    'update public.downtime_events set reason_id=%L::uuid where id=%L::uuid',
    other_reason,first_event),'downtime_initial_locked');

  perform public.change_status(f,source_id,'setup',initial_reason);
  select id into switch_event from public.downtime_events
    where work_center_id=source_id and ended_at is null;
  if not exists(select 1 from public.downtime_events earlier
    join public.downtime_events later on later.id=switch_event
    where earlier.id=first_event and earlier.ended_at<=later.started_at) then
    raise exception 'downtime status switch produced overlapping intervals'; end if;
  perform public.change_status(f,source_id,'running');
  select ended_at into ended from public.downtime_events where id=first_event;
  if ended is null or ended<started or
    (select status from public.work_centers where id=source_id)<>'running' then
    raise exception 'resume did not end downtime'; end if;
  perform public.approve_downtime_cause(f,first_event,initial_reason,'Confirmed belt issue');
  if not exists(select 1 from public.downtime_events where id=first_event
    and reason_id=initial_reason and initial_entered_at=entered
    and approved_cause_id=initial_reason and approved_by=actor
    and approved_at is not null and engineering_note='Confirmed belt issue') then
    raise exception 'approve-as-observed audit failed'; end if;
  perform pg_temp.expect_downtime_error(format(
    'update public.downtime_events set reason_id=%L::uuid where id=%L::uuid',
    other_reason,first_event),'downtime_initial_locked');
  perform pg_temp.expect_downtime_error(format(
    'select public.approve_downtime_cause(%L::uuid,%L::uuid,%L::uuid,%L)',
    f,first_event,other_reason,'revised'),'downtime_not_reviewable');

  perform public.change_status(f,source_id,'stopped',initial_reason);
  select id into reviewed_event from public.downtime_events
    where work_center_id=source_id and ended_at is null;
  if not exists(select 1 from public.downtime_events where id=reviewed_event
    and reason_id=initial_reason and initial_note='') then
    raise exception 'optional detailed reason did not remain optional'; end if;
  perform public.change_status(f,source_id,'running');
  perform public.approve_downtime_cause(f,reviewed_event,other_reason,'Electrical issue');
  if not exists(select 1 from public.downtime_events where id=reviewed_event
    and reason_id=initial_reason and initial_note=''
    and approved_cause_id=other_reason and engineering_note='Electrical issue') then
    raise exception 'corrected cause overwrote initial observation'; end if;

  perform public.change_status(f,source_id,'stopped',initial_reason);
  select id into transfer_source_event from public.downtime_events
    where work_center_id=source_id and ended_at is null;
  insert into public.production_transfers(factory_id,original_id,alternative_id,
    order_id,downtime_id,reason,created_by)
    values(f,source_id,borrowed_id,existing_item,transfer_source_event,
      'V1 fixture transfer',actor)
    returning id into transfer_id;
  perform public.change_status(f,borrowed_id,'stopped',other_reason);
  select id into borrowed_event from public.downtime_events
    where work_center_id=borrowed_id and ended_at is null;
  if borrowed_event is null or not exists(select 1 from public.downtime_events
    where id=borrowed_event and line_id=line_a and order_id=existing_item)
    or not exists(select 1 from public.production_transfers
      where id=transfer_id and ended_at is null)
    or (select line_id from public.work_centers where id=borrowed_id)<>line_b then
    raise exception 'borrowed stop changed transfer or permanent line'; end if;

  perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
  perform pg_temp.expect_downtime_error(format(
    'select public.change_status(%L::uuid,%L::uuid,%L,%L::uuid)',
    f,downstream_id,'stopped',initial_reason),'permission_denied');
  perform pg_temp.expect_downtime_error(format(
    'select public.set_downtime_initial(%L::uuid,%L::uuid,%L::uuid,%L)',
    f,borrowed_event,initial_reason,''),'permission_denied');
  perform pg_temp.expect_downtime_error(format(
    'select public.approve_downtime_cause(%L::uuid,%L::uuid,%L::uuid,%L)',
    f,borrowed_event,other_reason,''),'permission_denied');
  perform pg_temp.expect_downtime_error(format(
    'select public.record_missed_downtime(%L::uuid,%L::uuid,now()-interval ''3 days'',now()-interval ''2 days'')',
    f,source_id),'permission_denied');
  perform set_config('request.jwt.claim.sub',actor::text,true);

  retro_event:=public.record_missed_downtime(f,source_id,
    now()-interval '3 days',now()-interval '2 days',initial_reason,'Missed shift note');
  if not exists(select 1 from public.downtime_events where id=retro_event
    and retroactive and entered_by=actor and created_by=actor
    and reason_id=initial_reason and initial_entered_by=actor
    and initial_entered_at is not null and ended_at is not null
    and line_id is null and order_id is null)
    or (select status from public.work_centers where id=source_id)<>'stopped' then
    raise exception 'retroactive entry or audit failed'; end if;
  perform pg_temp.expect_downtime_error(format(
    'select public.record_missed_downtime(%L::uuid,%L::uuid,now()-interval ''60 hours'',now()-interval ''36 hours'')',
    f,source_id),'downtime_overlap');
  perform pg_temp.expect_downtime_error(format(
    'select public.record_missed_downtime(%L::uuid,%L::uuid,now()-interval ''1 hour'',now()+interval ''1 hour'')',
    f,downstream_id),'downtime_invalid_interval');
end;
$verify$;

rollback;
