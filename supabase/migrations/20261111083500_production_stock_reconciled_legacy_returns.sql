-- Allow a previously empty planned order after all of its unused legacy custody
-- has been physically returned through the original audited return workflow.
-- Historical consumption or production still requires explicit reconciliation.
-- No balance, request, transaction, entry or order is rewritten/backfilled.
create or replace function private.production_stock_eligible(f uuid,i uuid)returns boolean
language sql stable security definer set search_path=''as $$
 select exists(select 1 from public.production_orders o,private.production_material_policy p
 where o.factory_id=f and o.id=i and p.factory_id=f and p.stock_enabled
 and not exists(select 1 from public.material_requests m
 join private.material_request_progress r on r.factory_id=m.factory_id and r.request_id=m.id
 where m.factory_id=f and m.production_item_id=i and
 (r.reserved>0 or r.consumed>0 or r.issued>coalesce((private.material_return_balance(f,m.id)->>'returned')::numeric,0)))
 and(o.created_at>=p.stock_activated_at
 or exists(select 1 from private.production_stock_orders s where s.factory_id=f and s.item_id=i)
 or not exists(select 1 from public.production_entries e where e.factory_id=f and e.order_id=i)))
$$;
revoke all on function private.production_stock_eligible(uuid,uuid)from public,anon,authenticated,service_role;

-- Preserve the original legacy return worker after its compatibility rename.
CREATE OR REPLACE FUNCTION private.material_return_action_before_stock(factory uuid, operation text, payload jsonb, request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare h private.material_returns;old private.material_return_events;intent jsonb:=jsonb_build_object('operation',operation,'payload',payload);before_value jsonb;result jsonb;r record;q numeric;remain numeric;take numeric;v_unit text;mat uuid;line uuid;warehouse uuid;move uuid;begin
 perform private.require_permission(factory,'factory','view');
 if operation='RECEIVE'then perform private.require_permission(factory,'warehouse','issue');perform private.require_permission(factory,'warehouse','view');else perform private.require_permission(factory,'orders','edit');perform private.require_permission(factory,'orders','view');end if;
 if operation is null or operation not in('CREATE','RECEIVE','CANCEL')or request_id is null or payload is null or jsonb_typeof(payload)<>'object'or octet_length(payload::text)>8000 then raise exception 'material_invalid'using errcode='22023';end if;
 if current_setting('transaction_isolation')not in('read committed','read uncommitted')then raise exception 'material_changed'using errcode='40001';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform pg_advisory_xact_lock(hashtextextended(factory::text||':structure',0));
 select *into old from private.material_return_events e where e.factory_id=factory and e.retry_id=material_return_action_before_stock.request_id;
 if found then if old.actor is distinct from auth.uid()or old.intent<>intent then raise exception 'request_conflict'using errcode='40001';end if;return old.after_state;end if;
 if length(coalesce(payload->>'note',''))>2000 then raise exception 'material_invalid'using errcode='22023';end if;
 if operation in('CREATE','RECEIVE')then if jsonb_typeof(payload->'quantity')is distinct from 'string'or payload->>'quantity'!~'^[0-9]+([.][0-9]+)?$'then raise exception 'material_quantity'using errcode='22023';end if;q:=(payload->>'quantity')::numeric;if q<=0 then raise exception 'material_quantity'using errcode='22023';end if;end if;
 if operation='CREATE'then
 if exists(select 1 from jsonb_object_keys(payload)k where k not in('material','line','warehouse','quantity','note'))then raise exception 'material_invalid'using errcode='22023';end if;
 mat:=(payload->>'material')::uuid;line:=(payload->>'line')::uuid;warehouse:=(payload->>'warehouse')::uuid;
 select m.unit into v_unit from public.materials m where m.factory_id=factory and m.id=mat and m.inventory_kind='RAW_MATERIAL';
 if v_unit is null or not exists(select 1 from public.production_lines where factory_id=factory and id=line)or not exists(select 1 from public.factory_warehouses where factory_id=factory and id=warehouse and storage_class='RAW'and active)then raise exception 'material_return_scope'using errcode='22023';end if;
 insert into private.material_returns(factory_id,material_id,unit,source_line_id,warehouse_id,requested,note,created_by)values(factory,mat,v_unit,line,warehouse,q,coalesce(payload->>'note',''),auth.uid())returning *into h;remain:=q;
 for r in select m.id,private.material_unused(factory,m.id)available from public.material_requests m join private.material_request_progress p on p.factory_id=m.factory_id and p.request_id=m.id join public.production_orders o on o.factory_id=m.factory_id and o.id=m.production_item_id where m.factory_id=factory and m.material_id=mat and m.unit=v_unit and o.line_id=line and not private.output_work_held(factory,o.id)and private.material_unused(factory,m.id)>0 order by m.issued_at,m.id for update of p loop
 take:=least(remain,r.available);if take>0 then insert into private.material_return_allocations values(factory,h.id,r.id,take,0);remain:=remain-take;end if;exit when remain=0;end loop;
 if remain<>0 then raise exception 'material_return_unavailable'using errcode='22023';end if;
 else
 if exists(select 1 from jsonb_object_keys(payload)k where k not in('id','revision','quantity','physical_confirmation','note'))then raise exception 'material_invalid'using errcode='22023';end if;
 select *into h from private.material_returns where factory_id=factory and id=(payload->>'id')::uuid for update;
 if not found then raise exception 'material_invalid'using errcode='22023';end if;
 if h.revision is distinct from(payload->>'revision')::integer then raise exception 'material_changed'using errcode='40001';end if;
 if h.status not in('REQUESTED','PARTIALLY_RECEIVED')then raise exception 'material_return_closed'using errcode='22023';end if;
 before_value:=private.material_return_snapshot(factory,h.id);
 if operation='CANCEL'then
 if h.created_by<>auth.uid()then raise exception 'permission_denied'using errcode='42501';end if;
 if length(btrim(coalesce(payload->>'note','')))<3 then raise exception 'material_return_reason'using errcode='22023';end if;
 update private.material_returns set status='CANCELLED',revision=revision+1 where factory_id=factory and id=h.id;
 else
 if payload->'physical_confirmation'is distinct from 'true'::jsonb or q>h.requested-h.received then raise exception 'material_quantity'using errcode='22023';end if;
 if not exists(select 1 from public.factory_warehouses where factory_id=factory and id=h.warehouse_id and storage_class='RAW'and active)then raise exception 'material_return_scope'using errcode='22023';end if;
 remain:=q;
 for r in select a.*,p.issued,p.consumed,m.production_item_id from private.material_return_allocations a join private.material_request_progress p on p.factory_id=a.factory_id and p.request_id=a.material_request_id join public.material_requests m on m.factory_id=a.factory_id and m.id=a.material_request_id where a.factory_id=factory and a.return_id=h.id order by a.material_request_id for update of a,p loop
 take:=least(remain,r.quantity-r.received);if take>0 then
 if private.output_work_held(factory,r.production_item_id)or r.issued-r.consumed-(private.material_return_balance(factory,r.material_request_id)->>'returned')::numeric<take then raise exception 'material_return_unavailable'using errcode='22023';end if;
 update private.material_return_allocations set received=received+take where factory_id=factory and return_id=h.id and material_request_id=r.material_request_id;remain:=remain-take;end if;exit when remain=0;end loop;
 if remain<>0 then raise exception 'material_return_unavailable'using errcode='22023';end if;
 move:=gen_random_uuid();insert into public.inventory_transactions(id,factory_id,material_id,quantity,kind,unit,reference,note,created_by)values(move,factory,h.material_id,q,'material_return',h.unit,h.id::text,'Independent raw material return '||h.code,auth.uid());
 update private.material_returns set received=received+q,status=case when received+q=requested then 'RECEIVED'else 'PARTIALLY_RECEIVED'end,revision=revision+1 where factory_id=factory and id=h.id;
 end if;end if;
 result:=private.material_return_snapshot(factory,h.id);
 insert into private.material_return_events(factory_id,return_id,retry_id,actor,operation,intent,before_state,after_state,movement_id)values(factory,h.id,request_id,auth.uid(),operation,intent,before_value,result,move);
 return result;end$function$
;
revoke all on function private.material_return_action_before_stock(uuid,text,jsonb,uuid)from public,anon,authenticated,service_role;
