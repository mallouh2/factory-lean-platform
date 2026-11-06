do $$declare x jsonb;f uuid;c jsonb;begin
 select b.x into x from shift_test.baseline b;f:=(x->>'factory')::uuid;
 if shift_test.digest(f) is distinct from (select digest from shift_test.baseline) then raise exception 'M1 modified operational baseline';end if;
 c:=private.resolve_production_occurrence(f,clock_timestamp());
 if c->>'reason'<>'OCCURRENCE_NOT_READY' then raise exception 'Initial capture falsely certifies underway shift: %',c;end if;
 if current_setting('shift_test.install_mode',true)='fresh' then
  if not exists(select 1 from private.production_shift_schedule_revisions where factory_id=f and revision_no=1 and source='BASELINE_CAPTURE' and definitions='[]')
   or not exists(select 1 from private.production_shift_schedule_revisions where factory_id=f and source='SHIFT_CONFIGURATION')
  then raise exception 'Fresh install did not initialize new factory/configuration';end if;
  raise notice 'PASS empty-database M1 install; new factory seeded; elapsed shift remains unverified';
 else
  if not exists(select 1 from private.production_shift_schedule_revisions where factory_id=f and effective_from>recorded_at and source='BASELINE_CAPTURE') then raise exception 'Prospective fence absent';end if;
  raise notice 'PASS baseline preserved; active legacy shift fenced prospectively';
 end if;
end$$;
create table shift_test.assertions(label text primary key);
create function shift_test.ok(value boolean,label text) returns void language plpgsql security definer as $$begin
 if value is distinct from true then raise exception 'M1 assertion: %',label;end if;
 insert into shift_test.assertions values(label);end$$;
create function shift_test.fails(statement text,expected text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then
  if sqlerrm=expected or sqlstate=expected then return;end if;raise exception 'Expected %, got % (%)',expected,sqlerrm,sqlstate;
 end;raise exception 'Expected rejection %',expected;end$$;
grant usage on schema shift_test to authenticated;
grant execute on function shift_test.ok(boolean,text),shift_test.fails(text,text) to authenticated;
