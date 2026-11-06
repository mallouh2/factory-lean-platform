-- Add source-authoritative display metadata to the existing protected reader.
-- No recording, receipt, scheduling, permissions or activation changes.
begin;
do $$declare body text;needle text:='''operations'',rows,''replacement_allowance''';begin
 select pg_get_functiondef('public.manufactured_output_read(uuid,text,uuid,integer)'::regprocedure) into body;
 if position(needle in body)=0 then raise exception 'Recording options contract changed';end if;
 execute replace(body,needle,'''operations'',rows,''work_kind'',(select w.choice from private.manufactured_completion_work w where w.factory_id=factory and w.item_id=target),''replacement_allowance''');
end$$;
comment on function public.manufactured_output_read(uuid,text,uuid,integer) is 'Protected output reader; recording options include the authoritative nullable completion/replacement/stock work choice.';
commit;
