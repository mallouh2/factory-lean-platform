begin;
-- The direct receipt and the queue must resolve the same authoritative operation
-- names as Quality and stored WIP. Only display metadata changes; keep the
-- original protected scopes, signatures, grants and receipt arithmetic.
do $migration$declare signature text;b text;needle text;begin
 foreach signature in array array['public.manufactured_receiving_context(uuid,uuid,integer)','public.manufactured_receiving_read(uuid,integer)']loop
  b:=pg_get_functiondef(signature::regprocedure);
  needle:='''operations'',h.operation_snapshot';
  if position(needle in b)=0 or position('h.operation_snapshot operations' in b)=0 then raise exception 'Warehouse receipt read contract changed';end if;
  b:=replace(b,needle,'''operations'',private.output_operation_labels(factory,h.operation_snapshot)');
  b:=replace(b,'h.operation_snapshot operations','private.output_operation_labels(factory,h.operation_snapshot) operations');
  execute b;
 end loop;
end$migration$;
commit;
