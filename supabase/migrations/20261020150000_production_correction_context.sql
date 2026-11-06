-- Phase 4C needs the complete existing exact snapshot before a request exists.
begin;
create function public.production_correction_context(factory uuid,entry uuid)
returns jsonb language plpgsql stable security definer set search_path='' set timezone='UTC' as $$
declare result jsonb;
begin
 perform private.production_correction_authorize(factory,false);
 select private.production_correction_values(factory,e.id)||jsonb_build_object(
 'id',e.id,'factory_id',factory,'input_lot_id',e.input_lot_id,'input_quantity',e.input_quantity::text,
 'product_name',e.product_name,'product_name_ar',e.product_name_ar,'request_code',e.request_code,'item_code',e.item_code)
 into result from private.production_reporting_entries e where e.factory_id=factory and e.id=entry;
 if result is null then raise exception 'correction_not_found' using errcode='P0002';end if;
 return result;
end$$;
revoke all on function public.production_correction_context(uuid,uuid) from public,anon;
grant execute on function public.production_correction_context(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
