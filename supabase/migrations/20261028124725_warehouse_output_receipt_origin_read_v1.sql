begin;
-- The inactive rollout retains the active Good acknowledgement path. The
-- queue must distinguish it from already physically received new output.
do $$declare b text;n text;begin
 b:=pg_get_functiondef('public.supply_page(uuid,text,integer,jsonb,uuid)'::regprocedure);
 n:='select e.id,e.order_id,o.product_id,p.name,p.name_ar,o.code,e.unit,e.effective_good,e.created_at';
 if position(n in b)=0 then raise exception 'Existing output receipt reader changed';end if;
 execute replace(b,n,n||',exists(select 1 from private.manufactured_outputs h where h.factory_id=e.factory_id and h.entry_id=e.id) manufactured');
end$$;
commit;
