begin;
-- Reuse committed Planning revisions and command receipts as notification evidence.
create table private.planning_change_acknowledgments(factory_id uuid not null,request_id uuid not null,user_id uuid not null,audience text not null check(audience in('PRODUCTION','WAREHOUSE')),at timestamptz not null default clock_timestamp(),primary key(factory_id,request_id,user_id,audience),foreign key(factory_id,request_id)references private.planning_change_commands(factory_id,request_id));
alter table private.planning_change_acknowledgments enable row level security;
revoke all on private.planning_change_acknowledgments from public,anon,authenticated;
do $migration$declare b text;begin
b:=pg_get_functiondef('public.revise_product_plan_confirmed'::regproc);
b:=replace(b,'state:=private.planning_change_state(factory,item);','state:=private.planning_change_state(factory,item)||jsonb_build_object(''before_revision'',(select coalesce(max(revision_no),0)from public.production_plan_revisions where factory_id=factory and item_id=item));');
b:=replace(b,'update private.planning_change_commands p set result=r','r:=r||jsonb_build_object(''prepared'',state->''prepared'',''preparation'',state->''materials'',''changed'',(r->>''revision'')::bigint>(state->>''before_revision'')::bigint);update private.planning_change_commands p set result=r');execute b;
end$migration$;
create function public.planning_changes_read(factory uuid,audience text)returns jsonb language plpgsql stable security definer set search_path='' as $$declare rows jsonb;begin
perform private.require_permission(factory,'factory','view');
if audience='PRODUCTION'then perform private.require_permission(factory,'orders','view');perform private.require_permission(factory,'lines','view');elsif audience='WAREHOUSE'then perform private.require_permission(factory,'warehouse','view');else raise exception 'permission_denied'using errcode='42501';end if;
select coalesce(jsonb_agg(to_jsonb(n)order by n.changed_at desc,n.request_id),'[]')into rows from(
select c.request_id,o.code,r.before_line_id,r.after_line_id,r.before_start,r.before_finish,r.after_start,r.after_finish,r.reason_code,r.reason_note,r.changed_by,r.changed_by_name,r.changed_at,c.result->'prepared'prepared,c.result->'preparation'preparation
from private.planning_change_commands c join public.production_plan_revisions r on r.factory_id=c.factory_id and r.item_id=c.item_id and r.revision_no=(c.result->>'revision')::integer
join public.production_orders o on o.factory_id=c.factory_id and o.id=c.item_id
where c.factory_id=factory and c.result->>'exceptional'='true'and c.result->>'changed'='true'
and(audience='PRODUCTION'or c.result->>'prepared'='true')and not exists(select 1 from private.planning_change_acknowledgments a where a.factory_id=c.factory_id and a.request_id=c.request_id and a.user_id=auth.uid()and a.audience=planning_changes_read.audience)
)n;return jsonb_build_object('rows',rows);end$$;
create function public.acknowledge_planning_change(factory uuid,request_id uuid,audience text)returns jsonb language plpgsql security definer set search_path='' as $$declare available jsonb;begin
available:=public.planning_changes_read(factory,audience);
if exists(select 1 from private.planning_change_acknowledgments a where a.factory_id=factory and a.request_id=acknowledge_planning_change.request_id and a.user_id=auth.uid()and a.audience=acknowledge_planning_change.audience)then return jsonb_build_object('acknowledged',true);end if;
if not exists(select 1 from jsonb_array_elements(available->'rows')r where r->>'request_id'=acknowledge_planning_change.request_id::text)then raise exception 'permission_denied'using errcode='42501';end if;
insert into private.planning_change_acknowledgments values(factory,request_id,auth.uid(),audience,clock_timestamp())on conflict do nothing;return jsonb_build_object('acknowledged',true);end$$;
revoke all on function public.planning_changes_read(uuid,text),public.acknowledge_planning_change(uuid,uuid,text)from public,anon;
grant execute on function public.planning_changes_read(uuid,text),public.acknowledge_planning_change(uuid,uuid,text)to authenticated;
commit;
