-- An open transfer is the assignment, even when its alternative stops.
create or replace function private.finish_transfer() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.status='running' and old.status<>'running' then
  update public.production_transfers
  set original_returned_at=now(),ended_at=now()
  where original_id=new.id and ended_at is null;
 end if;
 return new;
end$$;

-- Alternative and capability edits are separate factory-scoped operations.
create function private.configure_center_alternatives(f uuid,w uuid,alternatives uuid[]) returns void language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(f,'centers','edit');
 perform 1 from public.work_centers where id=w and factory_id=f and not archived for update;
 if not found then raise exception 'not_found';end if;
 if alternatives is null then raise exception 'invalid_alternative';end if;
 if exists(select 1 from unnest(alternatives) x where x=w or not exists(select 1 from public.work_centers c where c.id=x and c.factory_id=f and not c.archived)) then raise exception 'invalid_alternative';end if;
 if exists(select 1 from unnest(alternatives) x
    join public.work_centers o on o.id=w
    join public.work_centers a on a.id=x
    where o.category_id is distinct from a.category_id) then raise exception 'incompatible_alternative';end if;
 delete from public.work_center_alternatives where factory_id=f and work_center_id=w;
 insert into public.work_center_alternatives(factory_id,work_center_id,alternative_id)
 select f,w,x from unnest(alternatives) x;
end$$;

create function public.configure_center_alternatives(factory uuid,work_center uuid,alternatives uuid[]) returns void language sql security invoker set search_path='' as $$select private.configure_center_alternatives(factory,work_center,alternatives)$$;

create function private.configure_center_capabilities(f uuid,w uuid,capabilities jsonb) returns void language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(f,'centers','edit');
 perform 1 from public.work_centers where id=w and factory_id=f and not archived for update;
 if not found then raise exception 'not_found';end if;
 if capabilities is null or jsonb_typeof(capabilities)<>'array' then raise exception 'invalid_capabilities';end if;
 delete from public.work_center_capabilities where factory_id=f and work_center_id=w;
 insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate)
 select f,w,x.product_id,x.rate from jsonb_to_recordset(capabilities) x(product_id uuid,rate numeric);
end$$;

create function public.configure_center_capabilities(factory uuid,work_center uuid,capabilities jsonb) returns void language sql security invoker set search_path='' as $$select private.configure_center_capabilities(factory,work_center,capabilities)$$;

revoke all on function private.configure_center_alternatives(uuid,uuid,uuid[]),public.configure_center_alternatives(uuid,uuid,uuid[]),private.configure_center_capabilities(uuid,uuid,jsonb),public.configure_center_capabilities(uuid,uuid,jsonb) from public,anon;
grant execute on function private.configure_center_alternatives(uuid,uuid,uuid[]),public.configure_center_alternatives(uuid,uuid,uuid[]),private.configure_center_capabilities(uuid,uuid,jsonb),public.configure_center_capabilities(uuid,uuid,jsonb) to authenticated;

drop function public.configure_center_links(uuid,uuid,uuid[],jsonb);
drop function private.configure_center_links(uuid,uuid,uuid[],jsonb);
