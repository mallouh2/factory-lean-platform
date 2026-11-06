-- Read-only exact-record navigation. No writer, posting, permission or gate change.
begin;
do $$declare b text;needle text;begin
 b:=pg_get_functiondef('public.manufactured_output_read(uuid,text,uuid,integer)'::regprocedure);
 needle:='where h.factory_id=factory and (mode<>''entry'' or h.entry_id=target)';
 if position(needle in b)=0 then raise exception 'Output entry filter changed';end if;
 execute replace(b,needle,needle||' and (target is null or h.entry_id=target)');

 b:=pg_get_functiondef('public.manufactured_receiving_read(uuid,integer)'::regprocedure);
 needle:='''held'',private.output_group_held(factory,h.id,(g->>''id'')::uuid)';
 if position(needle in b)=0 then raise exception 'Receiving group contract changed';end if;
 b:=replace(b,needle,'''stored'',(select l.warehouse_quantity::text from private.manufactured_output_lots m join public.unfinished_lots l on l.factory_id=m.factory_id and l.id=m.lot_id where m.factory_id=factory and m.output_id=h.id and m.group_id::text=g->>''id''),
 ''on_floor'',(select (l.quantity_available-l.warehouse_quantity)::text from private.manufactured_output_lots m join public.unfinished_lots l on l.factory_id=m.factory_id and l.id=m.lot_id where m.factory_id=factory and m.output_id=h.id and m.group_id::text=g->>''id''), '||needle);
 execute b;
 needle:='CREATE OR REPLACE FUNCTION public.manufactured_receiving_read(factory uuid, page integer DEFAULT 0)';
 if position(needle in b)=0 then raise exception 'Receiving signature changed';end if;
 b:=replace(b,needle,'CREATE OR REPLACE FUNCTION public.manufactured_receiving_context(factory uuid, target uuid, page integer DEFAULT 0)');
 b:=replace(b,'where h.factory_id=factory and qa is not null','where h.factory_id=factory and h.id=target and qa is not null');
 b:=replace(b,'where m.factory_id=factory and l.warehouse_quantity>0','where m.factory_id=factory and m.output_id=target and l.warehouse_quantity>0');
 execute b;

 b:=pg_get_functiondef('public.manufactured_completion_read(uuid,integer)'::regprocedure);
 needle:='select w.item_id,o.code';
 if position(needle in b)=0 then raise exception 'Completion work identity changed';end if;
 b:=replace(b,needle,'select w.output_id,h.entry_id,w.item_id,o.code');execute b;
 needle:='CREATE OR REPLACE FUNCTION public.manufactured_completion_read(factory uuid, page integer DEFAULT 0)';
 if position(needle in b)=0 then raise exception 'Completion signature changed';end if;
 b:=replace(b,needle,'CREATE OR REPLACE FUNCTION public.manufactured_completion_context(factory uuid, target uuid, work_id uuid DEFAULT NULL::uuid, page integer DEFAULT 0)');
 b:=replace(b,'where m.factory_id=factory and l.quantity_available>0','where m.factory_id=factory and h.id=target and l.quantity_available>0');
 b:=replace(b,'where w.factory_id=factory order by w.created_at desc limit 100','where w.factory_id=factory and w.output_id=target and (work_id is null or w.item_id=work_id) order by w.created_at desc limit 100 offset page*100');
 needle:='''has_more'',jsonb_array_length(rows)=50';
 if position(needle in b)=0 then raise exception 'Completion result changed';end if;
 b:=replace(b,needle,'''has_more'',jsonb_array_length(rows)=50 or jsonb_array_length(work)=100,
 ''summary'',(select jsonb_build_object(''item_id'',o.id,''code'',o.code,''unit'',h.unit,''target'',o.target_quantity::text,''received'',private.output_demand_received(factory,o.id)::text,''remaining'',greatest(o.target_quantity-private.output_demand_received(factory,o.id),0)::text)
 from private.manufactured_outputs h join public.production_orders o on o.factory_id=h.factory_id and o.id=private.output_work_demand(factory,h.item_id) where h.factory_id=factory and h.id=target)');
 execute b;

 b:=pg_get_functiondef('public.finished_source_stock(uuid,uuid,text,uuid,uuid,integer,uuid)'::regprocedure);
 needle:='select s.*,s.quantity_credited';
 if position(needle in b)=0 then raise exception 'Source reader identity changed';end if;
 execute replace(b,needle,'select s.*,(select h.id from private.manufactured_outputs h where h.factory_id=s.factory_id and h.entry_id=s.entry_id) manufactured_output_id,s.quantity_credited');
end$$;

-- Original order context for the existing Production Orders view, independent
-- of the limited factory snapshot. Orders view does not grant edit authority.
create function public.manufactured_output_order_read(factory uuid,target uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare o public.production_orders;result jsonb;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'orders','view');
 if not private.manufactured_output_enabled(factory) then return jsonb_build_object('available',false);end if;
 select * into o from public.production_orders where factory_id=factory and id=target;
 if o.id is null or not (exists(select 1 from private.manufactured_outputs h where h.factory_id=factory and h.item_id=o.id) or exists(select 1 from private.manufactured_completion_work w where w.factory_id=factory and w.item_id=o.id)) then return jsonb_build_object('available',true,'item',null);end if;
 return jsonb_build_object('available',true,'item',to_jsonb(o),'request',(select to_jsonb(r) from public.production_requests r where r.factory_id=factory and r.id=o.request_id),
 'product',(select jsonb_build_object('id',p.id,'name',p.name,'name_ar',p.name_ar,'code',p.code,'stock_unit',p.stock_unit) from public.products p where p.factory_id=factory and p.id=o.product_id));
end$$;
revoke all on function public.manufactured_receiving_context(uuid,uuid,integer),public.manufactured_completion_context(uuid,uuid,uuid,integer),public.manufactured_output_order_read(uuid,uuid) from public,anon,service_role;
grant execute on function public.manufactured_receiving_context(uuid,uuid,integer),public.manufactured_completion_context(uuid,uuid,uuid,integer),public.manufactured_output_order_read(uuid,uuid) to authenticated;
commit;
