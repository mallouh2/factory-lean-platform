create or replace function private.save_record(f uuid,resource text,record_id uuid,p jsonb) returns uuid language plpgsql security definer set search_path='' as $$
 declare table_name text; allowed text[]; k text; columns_sql text:=''; values_sql text:=''; update_sql text:=''; result_id uuid; action text; begin
 action:=case when record_id is null then 'create' else 'edit' end;
 perform private.require_permission(f,case when resource='products' then 'orders' else resource end,action);
 if coalesce((p->>'archived')::boolean,false) then perform private.require_permission(f,resource,'delete');end if;
 case resource
 when 'factory' then table_name:='areas';allowed:=array['name','name_ar','archived'];
 when 'lines' then table_name:='production_lines';allowed:=array['name','name_ar','code','area_id','archived'];
 when 'centers' then table_name:='work_centers';allowed:=array['name','name_ar','code','type','parent_id','area_id','line_id','order_id','operator_id','description','notes','production_speed','default_cycle_time','current_cycle_time','planned_capacity','position','archived','start_time','expected_finish'];
 when 'products' then table_name:='products';allowed:=array['name','name_ar','code','unit','category','diameter','length','color','weight','standard_rate','stage'];
 when 'orders' then table_name:='production_orders';allowed:=array['code','product_id','line_id','status','target_quantity','start_time','expected_finish'];
 when 'downtime' then table_name:='downtime_reasons';allowed:=array['name','name_ar','parent_id','requires_description'];
 when 'roles' then
 table_name:='roles';allowed:=array['name','name_ar'];
 else raise exception 'invalid_resource'; end case;
 if jsonb_typeof(p)<>'object' or p='{}'::jsonb then raise exception 'invalid_input'; end if;
 for k in select jsonb_object_keys(p) loop
 if not k=any(allowed) then raise exception 'invalid_field'; end if;
 if columns_sql<>'' then columns_sql:=columns_sql||',';values_sql:=values_sql||',';update_sql:=update_sql||',';end if;
 columns_sql:=columns_sql||format('%I',k); values_sql:=values_sql||format('v.%I',k);update_sql:=update_sql||format('%I=v.%I',k,k);
 end loop;
 if record_id is null then
 execute format('insert into public.%I(factory_id,%s) select $1,%s from jsonb_populate_record(null::public.%I,$2) v returning id',table_name,columns_sql,values_sql,table_name) into result_id using f,p;
 else
 execute format('update public.%I t set %s from jsonb_populate_record(null::public.%I,$2) v where t.factory_id=$1 and t.id=$3 returning t.id',table_name,update_sql,table_name) into result_id using f,p,record_id;
 end if;
 if result_id is null then raise exception 'not_found';end if;return result_id;
 end$$;

-- Every platform snapshot is audited, in addition to the explicit scope-opening event.
create or replace function private.record_access(f uuid,operation text) returns void language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(f,'factory','view');
 if operation='EXPORT' then perform private.require_permission(f,'reports','export');end if;
 if operation not in ('READ','EXPORT') then raise exception 'invalid_input';end if;
 if operation='EXPORT' or private.platform_scope(f) or exists(select 1 from public.support_access where factory_id=f and user_id=auth.uid() and (mode='permanent' or (mode='temporary' and expires_at>now()))) then insert into public.audit_logs(factory_id,actor_id,action,entity) values(f,auth.uid(),operation,case when operation='EXPORT' then 'reports' when private.platform_scope(f) then 'platform_access' else 'support_access' end);end if;end$$;
-- Configuration writes outside the builder also invalidate stale drafts.
create function private.bump_structure_version() returns trigger language plpgsql security definer set search_path='' as $$begin
 update public.factories set structure_version=structure_version+1 where id=new.factory_id;return new;end$$;
create trigger bump_structure_version after insert or update of line_id,position,dependency_mode,impact_scope,buffer_minutes,archived on public.work_centers for each row execute function private.bump_structure_version();
revoke all on function private.bump_structure_version() from public,anon,authenticated;
