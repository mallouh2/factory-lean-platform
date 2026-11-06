begin;
-- Comparison ignores group UUIDs, release entitlements, notes and operation order.
-- It does not change any persisted source or inspection evidence.
create function private.output_material_difference(original jsonb,finding jsonb) returns boolean
language sql immutable set search_path='' as $$
 select finding is not null and (
  coalesce((finding->>'rejected')::numeric,0)<>0 or
  (select coalesce(jsonb_agg(jsonb_build_array(ops,q) order by ops),'[]') from (
   select ops,sum((g->>'quantity')::numeric) q from jsonb_array_elements(original)g
   cross join lateral (select coalesce(jsonb_agg(v order by v),'[]') ops from jsonb_array_elements_text(g->'missing_operations')v)t group by ops)s)
  is distinct from
  (select coalesce(jsonb_agg(jsonb_build_array(ops,q) order by ops),'[]') from (
   select ops,sum((g->>'quantity')::numeric) q from jsonb_array_elements(finding->'groups')g
   cross join lateral (select coalesce(jsonb_agg(v order by v),'[]') ops from jsonb_array_elements_text(g->'missing_operations')v)t group by ops)s)
 )
$$;
create function private.output_operation_labels(f uuid,ops jsonb) returns jsonb
language sql stable set search_path='' as $$
 select coalesce(jsonb_object_agg(k,v||jsonb_build_object('name',coalesce(nullif(cat.name,''),v->>'name'),'name_ar',coalesce(nullif(cat.name_ar,''),v->>'name_ar'))),'{}')
 from jsonb_each(ops)t(k,v)
 left join public.work_centers c on c.factory_id=f and c.id=(v->>'work_center_id')::uuid
 left join public.work_center_categories cat on cat.factory_id=f and cat.id=c.category_id
$$;
do $migration$
declare b text;needle text;begin
 b:=pg_get_functiondef('private.manufactured_output_command(uuid,text,uuid,jsonb,bigint,uuid)'::regprocedure);
 needle:='k not in (''groups'',''rejected'',''reason'')';
 if position(needle in b)=0 then raise exception 'Quality payload contract changed';end if;
 b:=replace(b,needle,'k not in (''groups'',''rejected'',''reason'',''total'')');
 needle:='or q+rejected<>h.quantity';
 if position(needle in b)=0 then raise exception 'Quality conservation contract changed';end if;
 b:=replace(b,needle,'or q+rejected<>coalesce((p->>''total'')::numeric,h.quantity) or coalesce((p->>''total'')::numeric,h.quantity)<0 or coalesce(p->>''total'',''0'') in (''NaN'',''Infinity'',''-Infinity'')');
 needle:='''original'',h.recorded_groups,''source'',h.source_snapshot';
 if position(needle in b)=0 then raise exception 'Quality evidence contract changed';end if;
 b:=replace(b,needle,'''total'',trim_scale(q+rejected)::text,''material_difference'',private.output_material_difference(h.recorded_groups,jsonb_build_object(''groups'',groups,''rejected'',rejected)),''original'',h.recorded_groups,''source'',h.source_snapshot');
 execute b;
 b:=pg_get_functiondef('public.manufactured_output_read(uuid,text,uuid,integer)'::regprocedure);
 b:=replace(b,'''operations'',h.operation_snapshot','''operations'',private.output_operation_labels(factory,h.operation_snapshot)');
 b:=replace(b,'jsonb_build_object(''id'',s.id,''name'',c.name,''name_ar'',c.name_ar)','jsonb_build_object(''id'',s.id,''name'',coalesce(nullif(cat.name,''''),c.name),''name_ar'',coalesce(nullif(cat.name_ar,''''),c.name_ar))');
 b:=replace(b,'where o.factory_id=factory and o.id=target','left join public.work_center_categories cat on cat.factory_id=c.factory_id and cat.id=c.category_id where o.factory_id=factory and o.id=target');
 needle:='and (mode<>''notifications'' or exists(select 1 from private.manufactured_output_events ev where ev.output_id=h.id and ev.operation=''QUALITY''))';
 if position(needle in b)=0 then raise exception 'Quality pagination contract changed';end if;
 b:=replace(b,needle,'and (mode<>''notifications'' or private.output_material_difference(h.recorded_groups,private.output_finding(factory,h.id))) and (mode<>''quality'' or target is not null or private.output_finding(factory,h.id) is null)');
 -- Old matching inspections remain immutable history, without noisy unread flags.
 b:=replace(b,'''unread'',exists(','''unread'',private.output_material_difference(h.recorded_groups,private.output_finding(factory,h.id)) and exists(');
 execute b;
end$migration$;
revoke all on function private.output_material_difference(jsonb,jsonb),private.output_operation_labels(uuid,jsonb) from public,anon,authenticated,service_role;
commit;
