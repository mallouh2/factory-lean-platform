-- An approved same-job replacement is the next production purpose, even when
-- the original baseline is only partially recorded. FIFO shares are unit
-- budgets, not invented exact event times or separate physical stock sources.
begin;
do $patch$ declare b text;n text;begin
 b:=pg_get_functiondef('private.compensation_entry_guard()'::regprocedure);
 n:='extra numeric;left_q numeric;';
 if position(n in b)=0 then raise exception 'compensation entry declaration changed';end if;
 b:=replace(b,n,'extra numeric;left_q numeric;budget numeric;');
 n:='extra:=greatest(gross-base,0);left_q:=extra;';
 if position(n in b)=0 then raise exception 'compensation attribution contract changed';end if;
 execute replace(b,n,'select coalesce(sum(private.compensation_remaining(new.factory_id,a.id)),0) into budget from private.production_compensation a where a.factory_id=new.factory_id and a.item_id=j.id and a.mode=''ACTIVE'';
 if gross>base+budget then raise exception ''output_compensation_exceeded'';end if;
 extra:=least(gross,budget);left_q:=extra;');
 b:=pg_get_functiondef('private.production_compensation_state(uuid,uuid)'::regprocedure);
 n:='when available<=0 then ''output_demand_covered''';
 if position(n in b)=0 then raise exception 'compensation coverage reason changed';end if;
 execute replace(b,n,'when available<=0 then case when j.target_quantity-accepted-pending-baseline-greatest(active_left,0)<=0 then ''output_demand_covered'' else ''output_source_entitlement_unavailable'' end');
 b:=pg_get_functiondef('private.production_compensation_state(uuid,uuid)'::regprocedure);
 n:='accepted numeric;pending numeric;';
 if position(n in b)=0 then raise exception 'compensation inspection declaration changed';end if;
 b:=replace(b,n,n||'awaiting numeric;');
 n:='baseline:=case when j.status=''active''';
 if position(n in b)=0 then raise exception 'compensation inspection coverage changed';end if;
 b:=replace(b,n,'select coalesce(sum((g->>''quantity'')::numeric),0) into awaiting from private.manufactured_outputs z
 cross join lateral jsonb_array_elements(coalesce((select e.result->''groups'' from private.manufactured_output_events e where e.factory_id=f and e.output_id=z.id and e.operation=''CORRECTION'' order by e.revision desc limit 1),z.recorded_groups)) g
 where z.factory_id=f and private.output_work_demand(f,z.item_id)=d and private.output_finding(f,z.id) is null;
 accepted:=accepted+awaiting;
 '||n);
 n:='''accepted'',accepted::text,';
 if position(n in b)=0 then raise exception 'compensation inspection presentation changed';end if;
 execute replace(b,n,'''accepted'',(accepted-awaiting)::text,''pending_inspection'',awaiting::text,');
 -- Preserve immutable decisions in the existing contextual drawer, including
 -- spent allowances. Read-only evidence never substitutes for Quality/receipt.
 b:=pg_get_functiondef('public.production_compensation_read(uuid,uuid)'::regprocedure);
 n:='return s||jsonb_build_object(''active_block''';
 if position(n in b)=0 then raise exception 'compensation contextual reader changed';end if;
 execute replace(b,n,'return s||jsonb_build_object(''decisions'',(select coalesce(jsonb_agg(jsonb_build_object(''quantity'',a.quantity::text,''recorded'',case when a.mode=''ACTIVE'' then (select coalesce(sum(e.quantity),0)::text from private.production_compensation_entries e where e.factory_id=factory and e.compensation_id=a.id) else private.compensation_gross(factory,a.item_id)::text end,
 ''remaining'',case when a.mode=''ACTIVE'' then private.compensation_remaining(factory,a.id)::text else greatest(a.quantity-private.compensation_gross(factory,a.item_id),0)::text end,''mode'',a.mode,''reason'',a.reason,''at'',a.created_at) order by a.created_at,a.id),''[]''::jsonb) from private.production_compensation a where a.factory_id=factory and a.output_id=target),''active_block''');
end$patch$;
commit;
