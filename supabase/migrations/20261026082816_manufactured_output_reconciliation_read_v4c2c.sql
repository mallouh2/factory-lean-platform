-- Read-only presentation of the existing protected reconciliation specification.
-- The command always revalidates under its existing locks; this is not authority.
begin;
create function private.output_reconciliation_action(f uuid,o uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare a jsonb;spec jsonb;h private.manufactured_outputs;sources jsonb;location text;begin
 perform private.require_permission(f,'factory','view');perform private.require_permission(f,'warehouse','view');
 a:=private.output_accounting(f,o);
 if not private.manufactured_output_enabled(f) or not private.has_permission(f,'warehouse','edit') or a->>'stage'<>'PENDING' then return null;end if;
 select * into h from private.manufactured_outputs where factory_id=f and id=o;
 if h.id is null then raise exception 'output_not_found';end if;
 begin spec:=private.output_reconciliation_spec(f,o,(a->>'finding_id')::uuid);
 exception when raise_exception then
  if sqlerrm !~ '^output_[a-z_]+$' then raise;end if;
  return jsonb_build_object('available',false,'blocker',sqlerrm);
 end;
 if coalesce(spec->>'mode','FINISHED_TO_UNFINISHED')='FINISHED_TO_UNFINISHED' then
  select coalesce(jsonb_agg(to_jsonb(x)),'[]') into sources from (
   select s.id,s.physical_label,(s.quantity_available-private.source_reserved(f,s.id))::text available
   from public.finished_goods_sources s where s.factory_id=f and s.entry_id=h.entry_id and s.product_id=h.product_id and s.unit=h.unit
   and s.physical_label is not null and s.quantity_available-private.source_reserved(f,s.id)>=(spec->>'quantity')::numeric
   and exists(select 1 from public.finished_goods_balances b where b.factory_id=f and b.product_id=h.product_id and b.unit=h.unit and b.on_hand-b.reserved>=(spec->>'quantity')::numeric)
   order by s.id limit 50) x;
  if sources='[]'::jsonb then return jsonb_build_object('available',false,'blocker','output_stock_unavailable');end if;
 elsif spec->>'mode'='UNFINISHED_RECLASS' then
  select m.location into location from private.manufactured_output_lots m where m.factory_id=f and m.output_id=o and m.lot_id=(spec->>'source_lot_id')::uuid;
 end if;
 return spec||jsonb_build_object('available',true,'mode',coalesce(spec->>'mode','FINISHED_TO_UNFINISHED'),'sources',sources,'source_location',location);
end$$;
revoke all on function private.output_reconciliation_action(uuid,uuid) from public,anon,authenticated,service_role;
do $$declare b text;needle text:='''finding'',private.output_finding(factory,h.id)';begin
 b:=pg_get_functiondef('public.manufactured_receiving_read(uuid,integer)'::regprocedure);
 if position(needle in b)=0 then raise exception 'Receiving finding contract changed';end if;
 execute replace(b,needle,'''reconciliation_action'',private.output_reconciliation_action(factory,h.id), '||needle);
end$$;
commit;
