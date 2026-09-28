-- Generic order edits may update unplanned item details, but scheduling remains
-- owned by plan_product_item / revise_product_plan. The existing table policies
-- grant authenticated users SELECT only; save_record is the generic write RPC.
create or replace function private.save_record(f uuid,resource text,record_id uuid,p jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare
  table_name text; perm text; allowed text[]; k text; new_category uuid;
  columns_sql text:=''; values_sql text:=''; update_sql text:='';
  result_id uuid; action text; previous_order public.production_orders%rowtype;
  product_changed boolean; quantity_changed boolean;
begin
  action:=case when record_id is null then 'create' else 'edit' end;
  perm:=case when resource='products' then 'orders'
    when resource='work_center_categories' then 'centers' else resource end;
  perform private.require_permission(f,perm,action);
  if coalesce((p->>'archived')::boolean,false) then
    perform private.require_permission(f,perm,'delete');
  end if;
  case resource
    when 'factory' then table_name:='areas';allowed:=array['name','name_ar','archived'];
    when 'lines' then table_name:='production_lines';allowed:=array['name','name_ar','code','area_id','archived'];
    when 'centers' then table_name:='work_centers';allowed:=array['name','name_ar','code','type','category_id','parent_id','area_id','line_id','order_id','operator_id','description','notes','production_speed','default_cycle_time','current_cycle_time','planned_capacity','position','archived','start_time','expected_finish'];
    when 'work_center_categories' then table_name:='work_center_categories';allowed:=array['name','name_ar','icon_key','archived'];
    when 'products' then table_name:='products';allowed:=array['name','name_ar','code','unit','category','diameter','length','color','weight','standard_rate','stage'];
    when 'orders' then table_name:='production_orders';allowed:=array['code','product_id','line_id','status','target_quantity','start_time','expected_finish'];
    when 'downtime' then table_name:='downtime_reasons';allowed:=array['name','name_ar','parent_id','requires_description'];
    when 'roles' then table_name:='roles';allowed:=array['name','name_ar'];
    else raise exception 'invalid_resource';
  end case;
  if jsonb_typeof(p)<>'object' or p='{}'::jsonb then raise exception 'invalid_input'; end if;
  if resource='centers' and p ? 'category_id' then
    if p->>'category_id' is null or not exists(
      select 1 from public.work_center_categories c
      where c.factory_id=f and c.id=(p->>'category_id')::uuid and c.archived=false
    ) then raise exception 'invalid_category'; end if;
    new_category:=(p->>'category_id')::uuid;
    if record_id is not null and new_category is distinct from (
      select category_id from public.work_centers where id=record_id and factory_id=f
    ) then
      if exists(
        select 1 from public.work_center_alternatives r
        where r.factory_id=f and record_id in (r.work_center_id,r.alternative_id)
          and exists(
            select 1 from public.work_centers other
            where other.id=case when r.work_center_id=record_id
              then r.alternative_id else r.work_center_id end
              and other.category_id is distinct from new_category
          )
      ) then raise exception 'category_alternative_conflict'; end if;
    end if;
  end if;
  if resource='work_center_categories' and record_id is not null
    and coalesce((p->>'archived')::boolean,false) then
    if exists(select 1 from public.work_centers w
      where w.category_id=record_id and w.factory_id=f and w.archived=false)
    then raise exception 'category_in_use'; end if;
  end if;

  if resource='orders' then
    if record_id is null then
      if nullif(p->>'line_id','') is not null
        or nullif(p->>'start_time','') is not null
        or nullif(p->>'expected_finish','') is not null
      then raise exception 'planning_use_plan_command'; end if;
    else
      select * into previous_order from public.production_orders
        where factory_id=f and id=record_id for update;
      if not found then raise exception 'not_found'; end if;
      if (p ? 'line_id' and (p->>'line_id')::uuid is distinct from previous_order.line_id)
        or (p ? 'start_time' and (p->>'start_time')::timestamptz is distinct from previous_order.start_time)
        or (p ? 'expected_finish' and (p->>'expected_finish')::timestamptz is distinct from previous_order.expected_finish)
      then raise exception 'planning_use_plan_command'; end if;

      product_changed:=p ? 'product_id'
        and (p->>'product_id')::uuid is distinct from previous_order.product_id;
      quantity_changed:=p ? 'target_quantity'
        and (p->>'target_quantity')::numeric is distinct from previous_order.target_quantity;
      if (product_changed or quantity_changed) and (
        previous_order.line_id is not null or previous_order.start_time is not null
        or previous_order.expected_finish is not null
        or previous_order.planning_ever_scheduled
        or previous_order.planning_locked_at is not null
        or previous_order.status<>'planned' or previous_order.produced_quantity>0
        or coalesce(p->>'status',previous_order.status)<>'planned'
      ) then raise exception 'planning_use_plan_command'; end if;

      -- A cancelled/completed item retains its stored times. Re-enabling it
      -- through a generic status edit could create a new overlap.
      if p ? 'status' and previous_order.status not in ('planned','active')
        and p->>'status' in ('planned','active')
        and (previous_order.line_id is not null or previous_order.start_time is not null
          or previous_order.expected_finish is not null)
      then raise exception 'planning_use_plan_command'; end if;
    end if;
  end if;

  for k in select jsonb_object_keys(p) loop
    if not k=any(allowed) then raise exception 'invalid_field'; end if;
    if columns_sql<>'' then
      columns_sql:=columns_sql||',';values_sql:=values_sql||',';update_sql:=update_sql||',';
    end if;
    columns_sql:=columns_sql||format('%I',k);
    values_sql:=values_sql||format('v.%I',k);
    update_sql:=update_sql||format('%I=v.%I',k,k);
  end loop;
  if record_id is null then
    execute format('insert into public.%I(factory_id,%s) select $1,%s from jsonb_populate_record(null::public.%I,$2) v returning id',table_name,columns_sql,values_sql,table_name)
      into result_id using f,p;
  else
    execute format('update public.%I t set %s from jsonb_populate_record(null::public.%I,$2) v where t.factory_id=$1 and t.id=$3 returning t.id',table_name,update_sql,table_name)
      into result_id using f,p,record_id;
  end if;
  if result_id is null then raise exception 'not_found'; end if;
  return result_id;
end;
$$;
