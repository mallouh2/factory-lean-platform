begin;
-- Store measured rejection evidence in the existing immutable finding, never
-- in the stock-backed legacy rejection writer or technician's Scrap fields.
create function private.output_rejection_mass(p jsonb,rejected numeric) returns numeric
language plpgsql immutable set search_path='' as $$declare kg numeric;begin
 kg:=(p->>'actual_rejected_kg')::numeric;
 if rejected>0 and (kg is null or kg<=0 or kg::text in ('NaN','Infinity','-Infinity')) then raise exception 'output_measured_weight';end if;
 if rejected=0 and coalesce(kg,0)<>0 then raise exception 'output_measured_weight';end if;
 return coalesce(kg,0);
end$$;
do $patch$declare b text;n text;begin
 b:=pg_get_functiondef('private.manufactured_output_command(uuid,text,uuid,jsonb,bigint,uuid)'::regprocedure);
 n:='k not in (''groups'',''rejected'',''reason'',''total'')';
 if position(n in b)=0 then raise exception 'Quality payload contract changed';end if;
 b:=replace(b,n,'k not in (''groups'',''rejected'',''reason'',''total'',''actual_rejected_kg'')');
 n:='''total'',trim_scale(q+rejected)::text';
 if position(n in b)=0 then raise exception 'Quality evidence contract changed';end if;
 b:=replace(b,n,'''actual_rejected_kg'',private.output_rejection_mass(p,rejected)::text,''total'',trim_scale(q+rejected)::text');
 execute b;
 b:=pg_get_functiondef('public.manufactured_output_read(uuid,text,uuid,integer)'::regprocedure);
 b:=replace(b,'''product_name'',p.name','''product_id'',h.product_id,''created_at'',h.created_at,''product_name'',p.name');
 execute b;
end$patch$;
create function private.output_rejected_mass(f uuid,e uuid) returns numeric
language sql stable set search_path='' as $$
 select coalesce((private.output_finding(f,h.id)->>'actual_rejected_kg')::numeric,0)
 from private.manufactured_outputs h where h.factory_id=f and h.entry_id=e
$$;
revoke all on function private.output_rejection_mass(jsonb,numeric),private.output_rejected_mass(uuid,uuid) from public,anon,authenticated,service_role;
-- No activation, stock movement, automatic conversion or saved Loss rewrite.
commit;
