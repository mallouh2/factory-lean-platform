-- Read-only My Requests filter, applied before total and keyset pagination.
-- Existing factory/person authorization, cursor binding and writer contracts are unchanged.
begin;
create or replace function public.production_correction_read(factory uuid,query jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path='' set timezone='UTC' as $$
declare size integer:=coalesce((query->>'page_size')::integer,50);c jsonb:=query->'cursor';fp text;rev text;after_at timestamptz;after_id uuid;reviewer boolean;result jsonb;begin
 perform private.require_permission(factory,'orders','view');reviewer:=private.has_permission(factory,'orders','approve');
 if query is null or jsonb_typeof(query)<>'object' or octet_length(query::text)>6000 or size not between 1 and 100
 or exists(select 1 from jsonb_object_keys(query)k where k not in ('id','request_id','entry','status','page_size','cursor','mine'))
 or (query ? 'mine' and jsonb_typeof(query->'mine') is distinct from 'boolean')
 or (query ? 'status' and query->>'status' not in ('PENDING','APPROVED','REJECTED')) then raise exception 'correction_invalid' using errcode='22023';end if;
 perform (query->>'id')::uuid,(query->>'request_id')::uuid,(query->>'entry')::uuid;
 select count(*)::text||':'||coalesce(sum(revision),0)::text||':'||coalesce((select revision::text from private.lean_source_state where factory_id=factory),'0') into rev
 from private.production_correction_requests where factory_id=factory;
 fp:=encode(sha256(convert_to(jsonb_build_array(factory,auth.uid(),query-'cursor',reviewer)::text,'UTF8')),'hex');
 if c is not null then
  if jsonb_typeof(c)<>'object' or not(c ?& array['version','factory','actor','query_hash','revision','after_at','after_id'])
  or (select count(*) from jsonb_object_keys(c))<>7 or c->>'version' is distinct from '1' or c->>'factory' is distinct from factory::text
  or c->>'actor' is distinct from auth.uid()::text or c->>'query_hash' is distinct from fp or c->>'revision' is distinct from rev
  then raise exception 'correction_stale_cursor' using errcode='40001';end if;
  after_at:=(c->>'after_at')::timestamptz;after_id:=(c->>'after_id')::uuid;
  if after_at is null or after_id is null then raise exception 'correction_invalid' using errcode='22023';end if;
 end if;
 with selected as materialized(select r.* from private.production_correction_requests r where r.factory_id=factory and (reviewer or r.requested_by=auth.uid())
 and (not coalesce((query->>'mine')::boolean,false) or r.requested_by=auth.uid())
 and (not(query ? 'id') or r.id=(query->>'id')::uuid) and (not(query ? 'request_id') or r.submission_id=(query->>'request_id')::uuid)
 and (not(query ? 'entry') or r.entry_id=(query->>'entry')::uuid) and (not(query ? 'status') or r.status=query->>'status')),
 page as materialized(select * from selected where after_at is null or (requested_at,id)>(after_at,after_id) order by requested_at,id limit size+1),
 visible as materialized(select * from page order by requested_at,id limit size)
 select jsonb_build_object('contract_version',1,'factory_id',factory,'total',(select count(*) from selected),'page_size',size,'complete',(select count(*)<=size from page),
 'rows',coalesce((select jsonb_agg((to_jsonb(v)-'base_values')||jsonb_build_object('original_values',v.base_values,'current_values',private.production_correction_values(factory,v.entry_id)) order by requested_at,id) from visible v),'[]'),
 'next_cursor',case when (select count(*)>size from page) then (select jsonb_build_object('version',1,'factory',factory,'actor',auth.uid(),'query_hash',fp,'revision',rev,'after_at',requested_at,'after_id',id) from visible order by requested_at desc,id desc limit 1) end) into result;
 return result;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then raise exception 'correction_invalid' using errcode='22023';
end$$;
revoke all on function public.production_correction_read(uuid,jsonb) from public,anon;
grant execute on function public.production_correction_read(uuid,jsonb) to authenticated;
commit;
