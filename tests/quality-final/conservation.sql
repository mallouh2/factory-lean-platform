begin;
set transaction read only;
do $$declare x record;h private.manufactured_outputs;q jsonb;a numeric;u numeric;r numeric;begin
 if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55500 or current_database()<>'factory_lean_quality_local' then raise exception 'Disposable QA only';end if;
 for x in select c.label,o.* from production_end_test.contexts c join production_orders o on o.id=(c.x->>'item')::uuid where c.label in('qfinal1','qfinal2','qfinal3','qfinal4','qfinal5','qfinal6') loop
  select m.* into strict h from private.manufactured_outputs m where m.item_id=x.id;
  q:=private.output_finding(h.factory_id,h.id);
  select coalesce(sum((g->>'quantity')::numeric)filter(where jsonb_array_length(g->'missing_operations')=0),0),coalesce(sum((g->>'quantity')::numeric)filter(where jsonb_array_length(g->'missing_operations')>0),0)into a,u from jsonb_array_elements(q->'groups')g;
  r:=(q->>'rejected')::numeric;
  if a+u+r<>98 or x.target_quantity<>98 then raise exception 'Conservation %',x.label;end if;
  if (select count(*)from production_entries where order_id=x.id)<>1 or (select effective_scrap_kg from production_entries where order_id=x.id)<>0.5 then raise exception 'Production history changed %',x.label;end if;
  if x.label='qfinal5' then
   if a<>98 or u<>0 or r<>0 or private.production_quality_followup(h.factory_id,h.id)->>'state'<>'NEEDS_ACTION' or(select count(*)from private.production_quality_followup_events where output_id=h.id)<>1 then raise exception 'Follow-up changed quantities or duplicated';end if;
  end if;
  if x.label='qfinal6'and(a<>97 or u<>1 or r<>0)then raise exception 'Recorded classifications lost';end if;
 end loop;
end$$;
rollback;
