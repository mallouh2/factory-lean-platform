-- TESTING only: fixture changes, temporary history and permission removals roll back.
begin;
do $test$
declare actor uuid; f uuid; foreign_factory uuid; selected_event uuid; first jsonb;
 second jsonb; expected jsonb; result jsonb; record jsonb; contexts jsonb:='[]';
 p integer; oldest uuid; total bigint; tab text; before_context jsonb;
begin
 select m.user_id,m.factory_id into actor,f from public.memberships m
 where m.status='approved' and exists(select 1 from public.user_permissions u
   where u.user_id=m.user_id and u.factory_id=m.factory_id and u.module='audit' and u.action='view')
 and exists(select 1 from public.user_permissions u where u.user_id=m.user_id and u.factory_id=m.factory_id
   and u.module='downtime' and u.action='view')
 and not exists(select 1 from private.platform_admins a where a.user_id=m.user_id and a.enabled)
 and not exists(select 1 from public.support_access a where a.user_id=m.user_id)
 order by m.created_at limit 1;
 if actor is null then raise exception 'existing fully authorized factory user required';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 select count(*) into total from public.audit_logs where factory_id=f;
 select id into oldest from public.audit_logs where factory_id=f order by created_at,id desc limit 1;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id),'[]') into expected
 from (select * from public.audit_logs where factory_id=f order by created_at desc,id limit 50)x;
 execute 'set local role authenticated';
 first:=public.audit_history(f,'',1);second:=public.audit_history(f,'',2);
 if first->'rows' is distinct from expected or (first->>'total')::bigint<>total
   or jsonb_array_length(first->'rows')<>least(50,total) then raise exception 'audit first page/count/content changed';end if;
 if exists(select 1 from jsonb_array_elements(first->'rows')a join jsonb_array_elements(second->'rows')b
   on a->>'id'=b->>'id')then raise exception 'audit page overlap';end if;
 result:=public.audit_history(f,oldest::text,1);
 if (result->>'total')::bigint<>1 or result->'rows'->0->>'id'<>oldest::text then
   raise exception 'audit full-history search failed beyond old cap';end if;
 result:=public.audit_history(f,'',greatest(1,ceil(total/50.0)::integer));
 if not exists(select 1 from jsonb_array_elements(result->'rows')r where r->>'id'=oldest::text)
   then raise exception 'audit oldest record unreachable by pagination';end if;
 result:=public.audit_history(f,'__NO_MATCH_FOR_QA_HISTORY__',1);
 if result->>'total'<>'0' or result->'rows'<>'[]'::jsonb then raise exception 'audit empty query';end if;
 execute 'reset role';

 select d.id into selected_event from public.downtime_events d where d.factory_id=f and d.ended_at is not null
   and exists(select 1 from public.production_loss_context_snapshots c where c.event_id=d.id)
 order by d.ended_at desc,d.id limit 1;
 if selected_event is null then raise exception 'existing closed event with captured context required';end if;
 select to_jsonb(c) into before_context from public.production_loss_context_snapshots c
   where c.event_id=selected_event order by captured_at,id limit 1;
 -- More than a context page, without changing an existing immutable snapshot.
 insert into public.production_loss_context_snapshots(factory_id,event_id,captured_at,context)
 select c.factory_id,c.event_id,c.captured_at,c.context from
   (select * from public.production_loss_context_snapshots where event_id=selected_event
     order by id limit 1)c cross join generate_series(1,60);
 select coalesce(jsonb_agg(to_jsonb(c) order by c.captured_at,c.id),'[]') into expected
 from public.production_loss_context_snapshots c where c.factory_id=f and c.event_id=selected_event;
 execute 'set local role authenticated';
 result:=public.production_loss_history(f,'contexts',selected_event,1);
 for p in 1..(result->>'pages')::integer loop
   contexts:=contexts||(public.production_loss_history(f,'contexts',selected_event,p)->'rows');
 end loop;
 if contexts is distinct from expected then raise exception 'event contexts pagination/order/fields changed';end if;
 record:=public.production_loss_history(f,'detail',selected_event);
 if record->'event'->>'id'<>selected_event::text then raise exception 'selected event mismatch';end if;
 result:=public.production_loss_history(f,'events',null,1);
 if exists(select 1 from jsonb_array_elements(result->'rows')r
   where r->>'factory_id'<>f::text or r->>'ended_at' is null) then raise exception 'loss event scope';end if;
 execute 'reset role';
 select jsonb_build_object('event',to_jsonb(d),
   'actual',(select to_jsonb(a) from public.production_loss_actuals a where a.factory_id=f and a.event_id=d.id),
   'saved',(select to_jsonb(e) from public.production_loss_estimates e where e.factory_id=f and e.event_id=d.id),
   'correction',(select to_jsonb(c) from public.downtime_classification_corrections c
     where c.factory_id=f and c.event_id=d.id order by c.corrected_at desc,c.id desc limit 1)) into expected
   from public.downtime_events d where d.id=selected_event;
 if record is distinct from expected then raise exception 'loss event/actual/saved/correction fields changed';end if;
 select coalesce(jsonb_agg(jsonb_build_object('event',to_jsonb(d),'actual',to_jsonb(a),
   'saved',(select to_jsonb(e) from public.production_loss_estimates e where e.factory_id=f and e.event_id=d.id),
   'correction',(select to_jsonb(c) from public.downtime_classification_corrections c
     where c.factory_id=f and c.event_id=d.id order by c.corrected_at desc,c.id desc limit 1))
   order by d.ended_at desc,d.id),'[]') into expected
   from public.downtime_events d join public.production_loss_actuals a on a.factory_id=d.factory_id and a.event_id=d.id
   where d.factory_id=f and d.ended_at is not null and d.id<>selected_event
     and d.work_center_id=(record->'event'->>'work_center_id')::uuid;
 execute 'set local role authenticated';
 result:=public.production_loss_history(f,'observations',selected_event,1);
 contexts:='[]';
 for p in 1..(result->>'pages')::integer loop
   contexts:=contexts||(public.production_loss_history(f,'observations',selected_event,p)->'rows');
 end loop;
 if contexts is distinct from expected then raise exception 'calibration observation scope/fields changed';end if;
 execute 'reset role';
 select to_jsonb(c) into result from public.production_loss_context_snapshots c
   where c.id=(before_context->>'id')::bigint;
 if result is distinct from before_context then raise exception 'immutable existing context changed';end if;

 insert into public.factories(name)values('QA lazy history isolation')returning id into foreign_factory;
 execute 'set local role authenticated';
 begin perform public.audit_history(foreign_factory);raise exception 'foreign audit allowed';
 exception when insufficient_privilege then null;end;
 begin perform public.production_loss_history(foreign_factory);raise exception 'foreign loss allowed';
 exception when insufficient_privilege then null;end;
 begin perform public.production_loss_history(f,'detail',gen_random_uuid());raise exception 'missing event accepted';
 exception when no_data_found then null;end;
 execute 'reset role';
 -- A retained owner/admin title cannot replace a missing personal history grant.
 delete from public.user_permissions where user_id=actor and factory_id=f and module in('audit','downtime')and action='view';
 execute 'set local role authenticated';
 begin perform public.audit_history(f);raise exception 'absent person audit grant accepted';
 exception when insufficient_privilege then null;end;
 begin perform public.production_loss_history(f);raise exception 'absent person loss grant accepted';
 exception when insufficient_privilege then null;end;
 execute 'reset role';
 for tab in values('public.audit_history(uuid,text,integer)'),
   ('public.production_loss_history(uuid,text,uuid,integer)')loop
   if has_function_privilege('anon',tab,'execute')or
     (select prosecdef from pg_proc where oid=tab::regprocedure)then raise exception 'history invoker/anonymous boundary changed';end if;
 end loop;
end;
$test$;
rollback;
