begin;
-- Extend the existing protected reader only. ACK state remains actor-bound
-- immutable evidence; opening a list performs no acknowledgement command.
do $migration$declare b text;n text;begin
 b:=pg_get_functiondef('public.manufactured_output_read(uuid,text,uuid,integer)'::regprocedure);
 n:='return jsonb_build_object(''available'',true,''rows'',rows,''page'',page,''has_more'',jsonb_array_length(rows)=50);';
 if position(n in b)=0 then raise exception 'Manufactured notification read contract changed';end if;
 b:=replace(b,n,$replacement$
 if mode='notifications' then
  with notices as materialized (
   select h.id,private.output_notification_revision(factory,h.id) notification_revision
   from private.manufactured_outputs h where h.factory_id=factory
   and private.output_material_difference(h.recorded_groups,private.output_finding(factory,h.id))
  ) select jsonb_build_object('total',count(*),'unread_count',count(*)filter(where notification_revision is not null
   and not exists(select 1 from private.manufactured_output_events a where a.factory_id=factory and a.output_id=notices.id
    and a.operation='ACKNOWLEDGE' and a.created_by=auth.uid() and (a.result->>'quality_revision')::bigint>=notification_revision)))into result from notices;
  return result||jsonb_build_object('available',true,'rows',rows,'page',page,'has_more',jsonb_array_length(rows)=50);
 end if;
 return jsonb_build_object('available',true,'rows',rows,'page',page,'has_more',jsonb_array_length(rows)=50);
 $replacement$);
 execute b;
end$migration$;
commit;
