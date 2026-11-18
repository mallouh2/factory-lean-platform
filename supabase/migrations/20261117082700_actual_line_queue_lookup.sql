-- F20: scope queue work before expensive physical/material eligibility checks.
create index production_orders_actual_queue on public.production_orders(factory_id,(coalesce(actual_line_id,line_id)),start_time,id)
where status='planned'and actual_finish is null;

create or replace function private.execution_bypassed_order(f uuid,i uuid)returns jsonb
language plpgsql stable security definer set search_path=''as $$declare selected public.production_orders;q record;begin
 select *into selected from public.production_orders where factory_id=f and id=i;
 if selected.id is null or selected.status<>'planned'then return null;end if;
 for q in select id,code from public.production_orders where factory_id=f
  and coalesce(actual_line_id,line_id)=coalesce(selected.actual_line_id,selected.line_id)
  and status='planned'and actual_finish is null and start_time is not null and expected_finish>start_time
  and(start_time,id)<(selected.start_time,selected.id)order by start_time,id loop
  if private.execution_dispatch_eligible(f,q.id)then return jsonb_build_object('id',q.id,'code',q.code);end if;
 end loop;return null;end$$;
