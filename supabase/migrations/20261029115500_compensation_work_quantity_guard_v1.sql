-- A planned replacement's explicit entitlement is not an unrestricted ordinary
-- overproduction job. Retain its normal execution/Quality/receipt workflow.
begin;
do $patch$ declare b text;n text;begin
 b:=pg_get_functiondef('private.compensation_work_validate(uuid,uuid)'::regprocedure);
 n:='end if;'||chr(10)||'end';
 if position(n in b)=0 then raise exception 'compensation work validation changed';end if;
 execute replace(b,n,'end if;
 if c.id is not null and private.compensation_gross(f,i)>(select w.quantity from private.manufactured_completion_work w where w.factory_id=f and w.item_id=i) then raise exception ''output_compensation_exceeded'';end if;
 end');
end$patch$;
commit;
