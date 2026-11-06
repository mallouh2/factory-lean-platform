begin;
create function private.output_material_signature(groups jsonb,rejected numeric) returns jsonb
language sql immutable set search_path='' as $$
 select jsonb_build_array(rejected,(select coalesce(jsonb_agg(jsonb_build_array(ops,q) order by ops),'[]') from (
 select ops,sum((g->>'quantity')::numeric) q from jsonb_array_elements(groups)g cross join lateral
 (select coalesce(jsonb_agg(v order by v),'[]') ops from jsonb_array_elements_text(g->'missing_operations')v)t group by ops)s))
$$;
create function private.output_notification_revision(f uuid,o uuid) returns bigint
language sql stable set search_path='' as $$
 select max(e.revision) from private.manufactured_output_events e
 where e.factory_id=f and e.output_id=o and e.operation='QUALITY' and
 coalesce((e.result->>'notify_production')::boolean,
 private.output_material_signature(e.result->'groups',(e.result->>'rejected')::numeric) is distinct from
 coalesce((select private.output_material_signature(p.result->'groups',(p.result->>'rejected')::numeric)
 from private.manufactured_output_events p where p.factory_id=f and p.output_id=o and p.operation='QUALITY' and p.revision<e.revision order by p.revision desc limit 1),
 (select private.output_material_signature(h.recorded_groups,0)from private.manufactured_outputs h where h.factory_id=f and h.id=o)))
$$;
do $migration$declare b text;n text;begin
 b:=pg_get_functiondef('private.manufactured_output_command(uuid,text,uuid,jsonb,bigint,uuid)'::regprocedure);
 n:='''total'',trim_scale(q+rejected)::text';
 if position(n in b)=0 then raise exception 'Quality evidence contract changed';end if;
 b:=replace(b,n,'''notify_production'',private.output_material_difference(h.recorded_groups,jsonb_build_object(''groups'',groups,''rejected'',rejected)) and (quality is null or private.output_material_signature(groups,rejected) is distinct from private.output_material_signature(quality->''groups'',(quality->>''rejected'')::numeric)),''total'',trim_scale(q+rejected)::text');execute b;
 b:=pg_get_functiondef('public.manufactured_output_read(uuid,text,uuid,integer)'::regprocedure);
 n:='(select max(revision) from private.manufactured_output_events ev where ev.output_id=h.id and ev.operation=''QUALITY'')';
 if position(n in b)=0 then raise exception 'Notification revision contract changed';end if;
 b:=replace(b,n,'private.output_notification_revision(factory,h.id)');
 b:=replace(b,'q.operation=''QUALITY'' and not exists','q.operation=''QUALITY'' and q.revision=private.output_notification_revision(factory,h.id) and not exists');execute b;
end$migration$;
revoke all on function private.output_material_signature(jsonb,numeric),private.output_notification_revision(uuid,uuid) from public,anon,authenticated,service_role;
commit;
