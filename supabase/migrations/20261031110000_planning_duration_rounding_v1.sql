-- Prospective Planning duration only. Preserve saved intervals/history and all guards.
begin;
do $$declare body text;needle text:='ceil(target.target_quantity / slowest * 60)';begin
 body:=pg_get_functiondef('private.plan_product_item_without_maintenance(uuid,uuid,uuid,timestamptz)'::regprocedure);
 if position(needle in body)=0 then raise exception 'Protected Planning duration contract changed';end if;
 execute replace(body,needle,'ceil(target.target_quantity * 60 / slowest)');
end$$;
commit;
