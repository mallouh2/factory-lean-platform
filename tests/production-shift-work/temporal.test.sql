begin;
-- Fixed historical instants are pure-helper fixtures, not backdated application writes.
do $$declare x jsonb;f uuid;r private.production_shift_schedule_revisions;s jsonb;t jsonb;d jsonb;n uuid;m uuid;
 z timestamptz;boundary timestamptz;original jsonb;rev bigint;begin
 x:=mp_test.fixture('temporal');f:=(x->>'factory')::uuid;
 select * into r from private.production_shift_schedule_revisions where factory_id=f;
 r.timezone:='UTC';r.effective_from:='2026-01-01Z';
 s:=jsonb_build_object('id',gen_random_uuid(),'name','Day','name_ar','نهار','archived',false,'start_time','06:00','end_time','14:00');
 d:=private.shift_occurrence_descriptor(r,s,'2026-10-18');
 perform shift_test.ok(d->>'starts_at'='2026-10-18T06:00:00+00:00' and d->>'ends_at'='2026-10-18T14:00:00+00:00','normal daytime descriptor');
 s:=s||'{"start_time":"22:00","end_time":"06:00"}';
 d:=private.shift_occurrence_descriptor(r,s,'2026-10-18');
 perform shift_test.ok(d->>'business_date'='2026-10-18' and (d->>'ends_at')::timestamptz='2026-10-19 06:00Z','overnight single business date');
 perform shift_test.ok(d=private.shift_occurrence_descriptor(r,s,'2026-10-18'),'stable deterministic identity');
 r.timezone:='America/New_York';
 d:=private.shift_occurrence_descriptor(r,s,'2026-03-07');
 perform shift_test.ok((d->>'ends_at')::timestamptz-(d->>'starts_at')::timestamptz=interval '7 hours','DST spring seven-hour occurrence');
 d:=private.shift_occurrence_descriptor(r,s,'2026-10-31');
 perform shift_test.ok((d->>'ends_at')::timestamptz-(d->>'starts_at')::timestamptz=interval '9 hours','DST autumn nine-hour occurrence');
 perform shift_test.fails($q$select private.shift_boundary_utc('2026-03-08 02:30','America/New_York')$q$,'shift_boundary_nonexistent');
 perform shift_test.fails($q$select private.shift_boundary_utc('2026-11-01 01:30','America/New_York')$q$,'shift_boundary_ambiguous');
 perform shift_test.ok(private.shift_boundary_utc('2026-10-18 06:00','Asia/Qatar')='2026-10-18 03:00Z','factory timezone boundary');

 -- Controlled revision history for resolver boundary tests, isolated local owner only.
 insert into public.factories(name,timezone) values('Fixed resolver history','UTC') returning id into f;
 insert into public.production_shifts(factory_id,name,name_ar,start_time,end_time,created_by) values(f,'Day','نهار','06:00','14:00',auth.uid()) returning id into n;
 insert into public.production_shifts(factory_id,name,name_ar,start_time,end_time,created_by) values(f,'Night','ليل','22:00','06:00',auth.uid()) returning id into m;
 s:=jsonb_build_object('id',n,'name','Day','name_ar','نهار','archived',false,'start_time','06:00','end_time','14:00');
 t:=jsonb_build_object('id',m,'name','Night','name_ar','ليل','archived',false,'start_time','22:00','end_time','06:00');
 insert into private.production_shift_schedule_revisions(factory_id,revision_no,recorded_at,source,effective_from,timezone,definitions,definition_hash)
 values(f,2,'2025-01-01Z','BASELINE_CAPTURE','2025-01-01Z','UTC',jsonb_build_array(s,t),repeat('1',64)) returning * into r;
 d:=private.resolve_production_occurrence(f,'2025-10-18 06:00Z');
 perform shift_test.ok((d->>'available')::boolean and d#>>'{occurrence,shift_id}'=n::text,'exact start included');
 perform shift_test.ok(private.resolve_production_occurrence(f,'2025-10-18 14:00Z')->>'reason'='SCHEDULE_GAP','exact end excluded genuine gap');
 perform shift_test.ok(private.resolve_production_occurrence(f,'2025-10-19 02:00Z')#>>'{occurrence,business_date}'='2025-10-18','overnight resolver after midnight');
 d:=private.resolve_production_occurrence(f,'2025-10-18 23:00Z')->'occurrence';
 perform private.materialize_production_occurrence(f,d);perform private.materialize_production_occurrence(f,d);
 perform shift_test.ok((select count(*)=1 from private.production_shift_occurrences where factory_id=f),'materialization full-descriptor idempotency');
 perform shift_test.ok(private.resolve_production_occurrence(f,'2025-10-19 02:00Z')->'occurrence'=d,'reader reuses persisted UTC bounds and identity');
 r.timezone:='Invalid/Test';
 perform shift_test.ok(private.shift_occurrence_descriptor(r,t,'2025-10-18')=d,'persisted descriptor precedes timezone-rule reinterpretation');
 r.timezone:='UTC';
 perform shift_test.fails(format('select private.materialize_production_occurrence(%L,%L)',f,d||'{"name":"Forged"}'),'40001');
 perform shift_test.fails(format('update private.production_shift_occurrences set name=%L where factory_id=%L','Changed',f),'shift_history_immutable');
 perform shift_test.fails(format('delete from private.production_shift_schedule_revisions where factory_id=%L',f),'shift_history_immutable');
 perform shift_test.fails(format('insert into private.production_shift_occurrences select factory_id,%L,schedule_revision_id,shift_id,business_date+1,timezone,name,name_ar,starts_at,ends_at,identity_version,materialized_at from private.production_shift_occurrences where factory_id=%L',repeat('b',64),f),'23P01');
 -- Adjacent schedule revision, then archive/reactivate the night shift at future boundaries.
 insert into private.production_shift_schedule_revisions(factory_id,revision_no,predecessor_id,recorded_at,source,effective_from,timezone,definitions,definition_hash)
 values(f,3,r.id,'2025-01-02Z','SHIFT_CONFIGURATION','2025-10-19 06:00Z','UTC',jsonb_build_array(s,t||'{"archived":true}'),repeat('2',64));
 perform shift_test.ok((private.resolve_production_occurrence(f,'2025-10-19 05:59Z')->>'available')::boolean,'pending change preserves underway old night');
 perform shift_test.ok(private.resolve_production_occurrence(f,'2025-10-19 23:00Z')->>'reason'='SCHEDULE_GAP','archival applies prospectively');
 insert into private.production_shift_schedule_revisions(factory_id,revision_no,recorded_at,source,effective_from,timezone,definitions,definition_hash)
 values(f,4,'2025-01-03Z','SHIFT_CONFIGURATION','2025-10-20 06:00Z','UTC',jsonb_build_array(s,t),repeat('3',64));
 perform shift_test.ok((private.resolve_production_occurrence(f,'2025-10-20 23:00Z')->>'available')::boolean,'reactivation future occurrence');
 -- Multiple changes share a future boundary; highest ordinal full snapshot wins.
 insert into private.production_shift_schedule_revisions(factory_id,revision_no,recorded_at,source,effective_from,timezone,definitions,definition_hash)
 values(f,5,'2025-01-04Z','TIMEZONE_CONFIGURATION','2025-10-20 06:00Z','Asia/Qatar',jsonb_build_array(s||'{"name":"Latest"}',t),repeat('4',64));
 d:=private.resolve_production_occurrence(f,'2025-10-20 06:01Z');
 perform shift_test.ok(d->>'reason'='OCCURRENCE_NOT_READY','timezone transition never clips already-started new shift');
 perform shift_test.ok(private.resolve_production_occurrence(f,'2025-10-21 04:00Z')#>>'{occurrence,name}'='Latest','latest pending revision wins with frozen timezone');
 insert into private.production_shift_schedule_revisions(factory_id,revision_no,recorded_at,source,effective_from,timezone,definitions,definition_hash)
 values(f,6,'2025-01-05Z','SHIFT_CONFIGURATION','2025-10-22Z','UTC',jsonb_build_array(s,s||jsonb_build_object('id',m,'name','Overlap')),repeat('5',64));
 perform shift_test.ok(private.resolve_production_occurrence(f,'2025-10-23 07:00Z')->>'reason'='SHIFT_OVERLAP','ambiguous full configuration fails closed');

 -- Actual protected configuration path. New short shift begins after capture fence.
 x:=mp_test.fixture('prospective');f:=(x->>'factory')::uuid;
 perform private.update_settings(f,'Prospective test','UTC',null);
 z:=clock_timestamp()+interval '1 second';
 n:=public.configure_production_shift(f,'Short shift','وردية',z::time,(z+interval '1 hour')::time);
 perform pg_sleep(1.1);
 original:=private.resolve_production_occurrence(f,clock_timestamp())->'occurrence';
 perform shift_test.ok(original is not null,'first full verified occurrence becomes ready');
 boundary:=(original->>'ends_at')::timestamptz;
 perform public.configure_production_shift(f,'Renamed','معدلة',z::time,(z+interval '1 hour')::time,n);
 perform shift_test.ok(private.resolve_production_occurrence(f,clock_timestamp())->'occurrence'=original,'rename preserves underway descriptor');
 perform public.configure_production_shift(f,'Renamed twice','معدلة مرتين',z::time,(z+interval '1 hour')::time,n);
 select max(revision_no) into rev from private.production_shift_schedule_revisions where factory_id=f;
 perform shift_test.ok((select effective_from=boundary from private.production_shift_schedule_revisions where factory_id=f and revision_no=rev),'multiple pending changes retain prospective boundary');
 perform public.configure_production_shift(f,'Renamed twice','معدلة مرتين',z::time,(z+interval '1 hour')::time,n);
 perform shift_test.ok((select max(revision_no)=rev from private.production_shift_schedule_revisions where factory_id=f),'identical config adds no revision');
 perform public.configure_production_shift(f,'Renamed twice','معدلة مرتين',z::time,(z+interval '1 hour')::time,n,true);
 perform shift_test.ok(private.resolve_production_occurrence(f,clock_timestamp())->'occurrence'=original,'archival cannot invalidate current occurrence');
 perform private.update_settings(f,'Prospective test','Asia/Qatar',null);
 perform shift_test.ok(private.resolve_production_occurrence(f,clock_timestamp())->'occurrence'=original,'timezone change preserves underway occurrence');
 perform public.configure_production_shift(f,'Reactivated','مفعلة',z::time,(z+interval '1 hour')::time,n,false);
 perform shift_test.fails(format('select public.configure_production_shift(%L,%L,%L,%L,%L)',f,'Overlap','تداخل',z::time,(z+interval '30 minutes')::time),'shift_overlap');
 select * into r from private.production_shift_schedule_revisions where factory_id=f order by revision_no desc limit 1;
 select value into s from jsonb_array_elements(r.definitions) where value->>'id'=n::text;
 d:=private.shift_occurrence_descriptor(r,s,(r.effective_from at time zone r.timezone)::date+1);
 perform private.materialize_production_occurrence(f,d);
 perform shift_test.fails(format('select public.configure_production_shift(%L,%L,%L,%L,%L,%L)',f,'Frozen future conflict','تعارض',z::time,(z+interval '1 hour')::time,n),'shift_transition_frozen');
 perform shift_test.ok((select count(*)=1 from private.production_shift_occurrences where factory_id=f),'configuration cannot redefine a materialized future occurrence');
end$$;
select count(*)||' temporal assertions passed' from shift_test.assertions;
rollback;
