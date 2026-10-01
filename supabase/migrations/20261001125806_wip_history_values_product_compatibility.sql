-- Products have no archive column. Preserve their existing schema.
create or replace function public.production_history_values(factory uuid,field text,search text default '',page integer default 1)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 perform private.require_permission(factory,'orders','view');
 if field not in ('request','product','unit','technician','shift') or page is null or page<1 or page>1000000 or length(coalesce(search,''))>120 then raise exception 'history_invalid';end if;
 with value_rows as materialized(
 select r.id::text as id,r.code as name,r.code as name_ar,false as archived from public.production_requests r where r.factory_id=factory and field='request'
 union all select p.id::text,p.name,p.name_ar,false from public.products p where p.factory_id=factory and field='product'
 union all select 'line:'||l.id,l.name,l.name_ar,l.archived from public.production_lines l where l.factory_id=factory and field='unit'
 union all select 'machine:'||c.id,c.name,c.name_ar,c.archived from public.work_centers c where c.factory_id=factory and field='unit' and (c.line_id is null or exists(select 1 from public.production_entries e where e.factory_id=factory and e.work_center_id=c.id))
 union all select m.id::text,m.display_name,m.display_name,false from public.memberships m where m.factory_id=factory and field='technician'
 union all select s.id::text,s.name,s.name_ar,s.archived from public.production_shifts s where s.factory_id=factory and field='shift'),
 matching as materialized(select * from value_rows where strpos(lower(coalesce(name,'')||' '||coalesce(name_ar,'')),lower(coalesce(search,'')))>0),
 paged as(select * from matching order by name,id limit 50 offset (page-1)*50)
 select jsonb_build_object('total',(select count(*) from matching),'rows',(select coalesce(jsonb_agg(to_jsonb(x) order by x.name,x.id),'[]') from paged x)) into result;
 return result;
end$$;
