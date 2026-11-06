begin;
create table private.planning_change_policy(factory_id uuid primary key references public.factories(id),seconds numeric not null check(seconds>0 and seconds<=31536000),revision bigint not null default 1);
create table private.planning_policy_events(factory_id uuid not null references public.factories(id),request_id uuid not null,actor uuid not null,before_seconds numeric not null,after_seconds numeric not null,at timestamptz not null default clock_timestamp(),primary key(factory_id,request_id));
create table private.planning_change_commands(factory_id uuid not null references public.factories(id),request_id uuid not null,actor uuid not null,item_id uuid not null,intent jsonb not null,fingerprint text not null,result jsonb,transaction_id bigint not null default txid_current(),at timestamptz not null default clock_timestamp(),primary key(factory_id,request_id));
alter table private.planning_change_policy enable row level security;
alter table private.planning_policy_events enable row level security;
alter table private.planning_change_commands enable row level security;
revoke all on private.planning_change_policy,private.planning_policy_events,private.planning_change_commands from public,anon,authenticated;
create function public.planning_warning_policy_read(factory uuid)returns jsonb language plpgsql stable security definer set search_path='' as $$declare seconds numeric;begin
perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'orders','view');
select p.seconds into seconds from private.planning_change_policy p where factory_id=factory;
return jsonb_build_object('hours',(coalesce(seconds,21600)/3600)::text,'seconds',coalesce(seconds,21600)::text);end$$;
create function public.configure_planning_warning(factory uuid,hours text,request_id uuid)returns jsonb language plpgsql security definer set search_path='' as $$declare v numeric;before_seconds numeric;old private.planning_policy_events;begin
perform private.require_permission(factory,'orders','edit');perform private.maintenance_planning_lock(factory);perform private.require_permission(factory,'orders','edit');
if request_id is null or hours is null or hours!~'^[0-9]{1,5}(\.[0-9]{1,6})?$' then raise exception 'planning_policy_invalid';end if;v:=hours::numeric*3600;
if v<=0 or v>31536000 then raise exception 'planning_policy_invalid';end if;
select *into old from private.planning_policy_events p where p.factory_id=factory and p.request_id=configure_planning_warning.request_id;
if found then if old.actor<>auth.uid()or old.after_seconds<>v then raise exception 'request_conflict'using errcode='40001';end if;return jsonb_build_object('hours',(v/3600)::text);end if;
select coalesce((select p.seconds from private.planning_change_policy p where p.factory_id=factory),21600)into before_seconds;
insert into private.planning_change_policy values(factory,v,1)on conflict(factory_id)do update set seconds=excluded.seconds,revision=planning_change_policy.revision+1;
insert into private.planning_policy_events values(factory,request_id,auth.uid(),before_seconds,v,clock_timestamp());return jsonb_build_object('hours',(v/3600)::text);end$$;
create function private.planning_change_state(f uuid,i uuid)returns jsonb language plpgsql stable security definer set search_path='' as $$declare o public.production_orders;material jsonb;seconds numeric;prep boolean;begin
select *into o from public.production_orders where factory_id=f and id=i;if not found then raise exception 'planning_item_missing';end if;
select coalesce(jsonb_agg(jsonb_build_object('id',id,'revision',revision,'status',status,'quantity',quantity::text,'unit',unit,'lot_id',lot_id)order by id),'[]')into material from public.material_requests where factory_id=f and production_item_id=i and status not in('CANCELLED','REJECTED');
select coalesce((select p.seconds from private.planning_change_policy p where p.factory_id=f),21600)into seconds;
prep:=exists(select 1 from jsonb_array_elements(material)m where m->>'status'in('ISSUED','RECEIVED'))or exists(select 1 from private.manufactured_completion_work w where factory_id=f and item_id=i and lot_id is not null);
return jsonb_build_object('item',i,'code',o.code,'line',o.line_id,'start',o.start_time,'finish',o.expected_finish,'status',o.status,'materials',material,'prepared',prep,'seconds',seconds::text,
'exception_required',o.start_time is not null and(prep or o.start_time-clock_timestamp()<=(seconds::text||' seconds')::interval),
'fingerprint',md5(jsonb_build_object('order',to_jsonb(o),'materials',material,'seconds',seconds,'hold',private.output_work_held(f,i))::text));end$$;
create function public.planning_change_context(factory uuid,item uuid)returns jsonb language plpgsql stable security definer set search_path='' as $$begin
perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'orders','view');return private.planning_change_state(factory,item);end$$;
create function public.revise_product_plan_confirmed(factory uuid,item uuid,target_line uuid,planned_start timestamptz,reason_code text,reason_note text,expected_fingerprint text,exception_confirmed boolean,request_id uuid)returns jsonb language plpgsql security definer set search_path='' as $$declare state jsonb;intent jsonb;prior private.planning_change_commands;r jsonb;begin
perform private.require_permission(factory,'orders','edit');perform private.maintenance_planning_lock(factory);perform private.require_permission(factory,'orders','edit');
if current_setting('transaction_isolation')<>'read committed' then raise exception 'planning_changed'using errcode='40001';end if;
if request_id is null then raise exception 'planning_confirmation_required';end if;
intent:=jsonb_build_object('item',item,'line',target_line,'start',planned_start,'reason_code',reason_code,'reason_note',reason_note,'fingerprint',expected_fingerprint,'confirmed',exception_confirmed);
select *into prior from private.planning_change_commands p where p.factory_id=factory and p.request_id=revise_product_plan_confirmed.request_id;
if found then if prior.actor<>auth.uid()or prior.intent<>intent then raise exception 'request_conflict'using errcode='40001';end if;return prior.result;end if;
perform 1 from public.production_orders where factory_id=factory and id=item for update;
state:=private.planning_change_state(factory,item);
if state->>'fingerprint'is distinct from expected_fingerprint then raise exception 'planning_changed'using errcode='40001';end if;
if(state->>'exception_required')::boolean and(exception_confirmed is distinct from true or nullif(btrim(reason_note),'')is null)then raise exception 'planning_confirmation_required';end if;
insert into private.planning_change_commands(factory_id,request_id,actor,item_id,intent,fingerprint)values(factory,request_id,auth.uid(),item,intent,expected_fingerprint);
perform set_config('app.planning_change_request',request_id::text,true);
perform public.revise_product_plan(factory,item,target_line,planned_start,reason_code,reason_note);
r:=jsonb_build_object('item',item,'request_id',request_id,'exceptional',(state->>'exception_required')::boolean,'revision',(select max(revision_no)from public.production_plan_revisions where factory_id=factory and item_id=item));
update private.planning_change_commands p set result=r where p.factory_id=factory and p.request_id=revise_product_plan_confirmed.request_id;return r;end$$;
-- Extend the existing history trigger, keeping its immutable before/after audit.
do $migration$declare b text;n text;begin
b:=pg_get_functiondef('private.record_plan_revision()'::regprocedure);
n:='if old.planning_locked_at is not null then';if position(n in b)=0 then raise exception 'Planning trigger changed';end if;
b:=replace(b,n,$new$if (private.planning_change_state(old.factory_id,old.id)->>'exception_required')::boolean and not exists(
 select 1 from private.planning_change_commands c where c.factory_id=old.factory_id and c.item_id=old.id and c.actor=auth.uid()and c.transaction_id=txid_current()
 and c.request_id::text=current_setting('app.planning_change_request',true)and c.result is null and c.fingerprint=private.planning_change_state(old.factory_id,old.id)->>'fingerprint')then raise exception 'planning_confirmation_required';end if;
 if old.planning_locked_at is not null then$new$);execute b;end$migration$;
revoke all on function private.planning_change_state(uuid,uuid)from public,anon,authenticated;
revoke all on function public.planning_warning_policy_read(uuid),public.configure_planning_warning(uuid,text,uuid),public.planning_change_context(uuid,uuid),public.revise_product_plan_confirmed(uuid,uuid,uuid,timestamptz,text,text,text,boolean,uuid)from public,anon;
grant execute on function public.planning_warning_policy_read(uuid),public.configure_planning_warning(uuid,text,uuid),public.planning_change_context(uuid,uuid),public.revise_product_plan_confirmed(uuid,uuid,uuid,timestamptz,text,text,text,boolean,uuid)to authenticated;
commit;
