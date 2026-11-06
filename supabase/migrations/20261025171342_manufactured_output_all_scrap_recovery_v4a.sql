-- Zero usable output is a legitimate source-bound recovery result. Keep the
-- original entry, consumed input, measured KG and immutable declaration/receipt.
-- No output group, Warehouse receipt, stock credit or demand release is invented.
begin;

alter table private.manufactured_outputs drop constraint manufactured_outputs_quantity_check;
alter table private.manufactured_outputs add constraint manufactured_outputs_quantity_check check (
 (quantity::text not in ('NaN','Infinity','-Infinity') and
  (quantity>0 or (quantity=0 and recorded_groups='[]'::jsonb
   and (source_snapshot->>'good')::numeric=0
   and (source_snapshot->>'unfinished')::numeric=0
   and (source_snapshot->>'discarded_quantity')::numeric>0
   and (source_snapshot->>'scrap_kg')::numeric>0
   and (source_snapshot->>'scrap_kg')::numeric::text not in ('NaN','Infinity','-Infinity')))) is true
);

do $patch$ declare body text;needle text;replacement text;begin
 body:=pg_get_functiondef('private.output_recovery_validate(uuid,jsonb)'::regprocedure);
 needle:='q:=(p->>''input_quantity'')::numeric;used:=private.output_work_consumed(f,w.item_id);';
 if (length(body)-length(replace(body,needle,'')))/length(needle)<>1 then raise exception 'recovery validation contract changed';end if;
 replacement:=needle||E'\n if (p->>''good'')::numeric=0 and coalesce((p->>''unfinished'')::numeric,0)=0 then\n'
 ||E'  if p->''output_groups'' is distinct from ''[]''::jsonb or q is distinct from (p->>''discarded_quantity'')::numeric\n'
 ||E'   or (p->>''scrap_kg'')::numeric is null or (p->>''scrap_kg'')::numeric<=0\n'
 ||E'   or (p->>''scrap_kg'')::numeric::text in (''NaN'',''Infinity'',''-Infinity'') then\n'
 ||E'   raise exception ''lean_invalid'' using errcode=''22023'';end if;\n end if;';
 execute replace(body,needle,replacement);

 body:=pg_get_functiondef('private.manufactured_output_command(uuid,text,uuid,jsonb,bigint,uuid)'::regprocedure);
 needle:='if q is distinct from e.effective_good or total-q<>coalesce(e.effective_unfinished,0) or total<=0 then raise exception ''output_conservation'';end if;';
 if (length(body)-length(replace(body,needle,'')))/length(needle)<>1 then raise exception 'output declaration contract changed';end if;
 replacement:=E'if q is distinct from e.effective_good or total-q<>coalesce(e.effective_unfinished,0) or total<0\n'
 ||E' or (total=0 and not coalesce((e.input_quantity>0 and e.input_quantity=e.effective_scrap\n'
 ||E' and e.effective_scrap_kg>0 and e.effective_scrap_kg::text not in (''NaN'',''Infinity'',''-Infinity'')\n'
 ||E' and private.manufactured_output_context_matches(f,e.id,e.request_id,''RECORD'')\n'
 ||E' and exists(select 1 from private.manufactured_completion_work w join public.material_requests mr\n'
 ||E' on mr.factory_id=w.factory_id and mr.id=w.material_request_id\n'
 ||E' where w.factory_id=f and w.item_id=e.order_id and w.choice<>''REPLACE'' and w.lot_id=e.input_lot_id\n'
 ||E' and mr.lot_id=w.lot_id and mr.production_item_id=w.item_id and mr.status in (''ISSUED'',''RECEIVED''))),false))\n'
 ||E' then raise exception ''output_conservation'';end if;';
 execute replace(body,needle,replacement);
end $patch$;

-- Existing ACLs, lock order, activation predicates, receipts and stock hooks
-- are retained by CREATE OR REPLACE of only the two existing protected bodies.
commit;
