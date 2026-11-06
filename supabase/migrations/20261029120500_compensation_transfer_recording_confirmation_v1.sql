-- Finish records execution, not completeness of recording. Explicitly check
-- that late-within-shift output has been recorded before moving its allowance.
begin;
do $patch$ declare b text;n text;begin
 b:=pg_get_functiondef('public.plan_production_compensation(uuid,uuid,jsonb,bigint,uuid)'::regprocedure);
 n:='''quantity'',''reason'',''mode'',''allowance_id''';
 if position(n in b)=0 then raise exception 'compensation transfer payload changed';end if;
 b:=replace(b,n,n||',''recording_complete_confirmation''');
 n:='if payload->>''allowance_id'' is not null then';
 if position(n in b)=0 then raise exception 'compensation transfer boundary changed';end if;
 execute replace(b,n,n||' if payload->''recording_complete_confirmation'' is distinct from ''true''::jsonb then raise exception ''output_recording_confirmation'';end if;');
end$patch$;
commit;
