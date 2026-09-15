-- Operational completion: immutable output ledger, assignment history and reusable guards.
create table public.production_entries (
 id uuid primary key default gen_random_uuid(),factory_id uuid not null,order_id uuid not null,work_center_id uuid not null,
 produced numeric not null check(produced>0),rejected numeric not null default 0 check(rejected>=0 and rejected<=produced),
 notes text not null default '',created_at timestamptz not null default now(),created_by uuid references auth.users,
 foreign key(factory_id,order_id) references public.production_orders(factory_id,id),foreign key(factory_id,work_center_id) references public.work_centers(factory_id,id)
);
create table public.operator_assignments(id uuid primary key default gen_random_uuid(),factory_id uuid not null,work_center_id uuid not null,operator_id uuid,started_at timestamptz not null default now(),ended_at timestamptz,created_by uuid references auth.users,foreign key(factory_id,work_center_id) references public.work_centers(factory_id,id),foreign key(factory_id,operator_id) references public.memberships(factory_id,id));
create unique index one_active_assignment on public.operator_assignments(work_center_id) where ended_at is null;
alter table public.work_centers add column parent_id uuid;
alter table public.work_centers add foreign key(factory_id,parent_id) references public.work_centers(factory_id,id);
alter table public.work_centers add check(parent_id is null or parent_id<>id);
create function private.validate_structure() returns trigger language plpgsql security definer set search_path='' as $$begin
 if TG_TABLE_NAME='work_centers' then
 if new.parent_id is not null and exists(with recursive ancestors as(select id,parent_id from public.work_centers where id=new.parent_id union all select c.id,c.parent_id from public.work_centers c join ancestors a on c.id=a.parent_id) select 1 from ancestors where id=new.id) then raise exception 'invalid_hierarchy';end if;
 if new.line_id is not null and not exists(select 1 from public.production_lines l where l.id=new.line_id and not l.archived and (new.area_id is null or l.area_id=new.area_id)) then raise exception 'invalid_line_area';end if;
 if new.operator_id is not null and not exists(select 1 from public.memberships where id=new.operator_id and status='approved') then raise exception 'invalid_operator';end if;
 if new.archived and (new.status not in ('idle','offline') or exists(select 1 from public.downtime_events where work_center_id=new.id and ended_at is null) or exists(select 1 from public.work_centers where parent_id=new.id and not archived)) then raise exception 'active_record';end if;
 elsif TG_TABLE_NAME='production_lines' and new.archived and exists(select 1 from public.work_centers where line_id=new.id and not archived) then raise exception 'active_record';
 elsif TG_TABLE_NAME='areas' and new.archived and (exists(select 1 from public.production_lines where area_id=new.id and not archived) or exists(select 1 from public.work_centers where area_id=new.id and not archived)) then raise exception 'active_record';end if;
 return new;end$$;
create trigger validate_center before insert or update on public.work_centers for each row execute function private.validate_structure();
create trigger validate_line before update on public.production_lines for each row execute function private.validate_structure();
create trigger validate_area before update on public.areas for each row execute function private.validate_structure();
create function private.assignment_history() returns trigger language plpgsql security definer set search_path='' as $$begin
 if TG_OP='INSERT' or new.operator_id is distinct from old.operator_id then
 update public.operator_assignments set ended_at=now() where work_center_id=new.id and ended_at is null;
 if new.operator_id is not null then insert into public.operator_assignments(factory_id,work_center_id,operator_id,created_by) values(new.factory_id,new.id,new.operator_id,auth.uid());end if;
 end if;return new;end$$;
create trigger record_assignment after insert or update on public.work_centers for each row execute function private.assignment_history();
create function private.record_output(f uuid,w uuid,o uuid,produced numeric,rejected numeric,n text) returns void language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(f,'orders','edit');
 perform 1 from public.work_centers where id=w and factory_id=f and not archived and order_id=o for update;
 if not found then raise exception 'invalid_order';end if;
 perform 1 from public.production_orders where id=o and factory_id=f and status='active' for update;
 if not found then raise exception 'invalid_order';end if;
 insert into public.production_entries(factory_id,order_id,work_center_id,produced,rejected,notes,created_by) values(f,o,w,produced,rejected,coalesce(n,''),auth.uid());
 update public.production_orders set produced_quantity=produced_quantity+produced,rejected_quantity=rejected_quantity+rejected where id=o;
 end$$;
create function public.record_output(factory uuid,work_center uuid,production_order uuid,produced numeric,rejected numeric default 0,notes text default '') returns void language sql security invoker set search_path='' as $$select private.record_output(factory,work_center,production_order,produced,rejected,notes)$$;

-- Future modules are relational foundations only; application has no write commands for them yet.
create table public.materials(id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories,name text not null,name_ar text not null default '',code text not null,unit text not null,created_at timestamptz not null default now(),unique(factory_id,id),unique(factory_id,code));
create table public.inventory_transactions(id uuid primary key default gen_random_uuid(),factory_id uuid not null,material_id uuid not null,quantity numeric not null check(quantity<>0),kind text not null check(kind in ('purchase_receipt','material_consumption','production_output','sales_reservation','sales_delivery','warehouse_transfer','adjustment','scrap')),created_at timestamptz not null default now(),created_by uuid references auth.users,foreign key(factory_id,material_id) references public.materials(factory_id,id));
create table public.inventory_reservations(id uuid primary key default gen_random_uuid(),factory_id uuid not null,material_id uuid not null,order_id uuid,quantity numeric not null check(quantity>0),released_at timestamptz,foreign key(factory_id,material_id) references public.materials(factory_id,id),foreign key(factory_id,order_id) references public.production_orders(factory_id,id));
create table public.bom_versions(id uuid primary key default gen_random_uuid(),factory_id uuid not null,product_id uuid not null,version integer not null check(version>0),batch_quantity numeric not null check(batch_quantity>0),created_at timestamptz not null default now(),unique(factory_id,id),foreign key(factory_id,product_id) references public.products(factory_id,id));
create table public.bom_items(id uuid primary key default gen_random_uuid(),factory_id uuid not null,bom_id uuid not null,material_id uuid not null,quantity numeric not null check(quantity>0),unit text not null,waste_allowance numeric not null default 0 check(waste_allowance between 0 and 1),foreign key(factory_id,bom_id) references public.bom_versions(factory_id,id),foreign key(factory_id,material_id) references public.materials(factory_id,id));
create table public.cost_estimates(id uuid primary key default gen_random_uuid(),factory_id uuid not null,product_id uuid not null,version integer not null,currency text not null,raw_material numeric not null default 0,labor numeric not null default 0,machine_time numeric not null default 0,energy numeric not null default 0,packaging numeric not null default 0,waste numeric not null default 0,overhead numeric not null default 0,created_at timestamptz not null default now(),foreign key(factory_id,product_id) references public.products(factory_id,id));
create table public.suppliers(id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories,name text not null,created_at timestamptz not null default now(),unique(factory_id,id));
create table public.purchase_requisitions(id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories,material_id uuid,quantity numeric check(quantity>0),created_at timestamptz not null default now(),unique(factory_id,id),foreign key(factory_id,material_id) references public.materials(factory_id,id));
create table public.purchase_orders(id uuid primary key default gen_random_uuid(),factory_id uuid not null,supplier_id uuid not null,requisition_id uuid,created_at timestamptz not null default now(),unique(factory_id,id),foreign key(factory_id,supplier_id) references public.suppliers(factory_id,id),foreign key(factory_id,requisition_id) references public.purchase_requisitions(factory_id,id));
create table public.goods_receipts(id uuid primary key default gen_random_uuid(),factory_id uuid not null,purchase_order_id uuid not null,material_id uuid not null,quantity numeric not null check(quantity>0),unit_cost numeric not null check(unit_cost>=0),created_at timestamptz not null default now(),foreign key(factory_id,purchase_order_id) references public.purchase_orders(factory_id,id),foreign key(factory_id,material_id) references public.materials(factory_id,id));
create table public.improvement_actions(id uuid primary key default gen_random_uuid(),factory_id uuid not null,downtime_id uuid not null,problem text not null,root_cause text,corrective_action text,responsible_id uuid,due_date date,verification text,result text,created_at timestamptz not null default now(),foreign key(factory_id,downtime_id) references public.downtime_events(factory_id,id),foreign key(factory_id,responsible_id) references public.memberships(factory_id,id));

do $$declare t text;m text;begin
 foreach t in array array['production_entries','operator_assignments','materials','inventory_transactions','inventory_reservations','bom_versions','bom_items','cost_estimates','suppliers','purchase_requisitions','purchase_orders','goods_receipts','improvement_actions'] loop
 execute format('alter table public.%I enable row level security',t);
 m:=case when t='production_entries' then 'orders' when t='operator_assignments' then 'centers' else 'factory' end;
 execute format('create policy scoped_read on public.%I for select to authenticated using(private.has_permission(factory_id,%L,''view''))',t,m);
 execute format('grant select on public.%I to authenticated',t);
 execute format('create index on public.%I(factory_id)',t);
 if t in ('production_entries','operator_assignments','inventory_transactions') then execute format('create trigger audit_insert after insert on public.%I for each row execute function private.audit_change()',t);end if;
 end loop;end$$;

-- Rate limiting persists failed join attempts because validation returns a result, not a rollback.
create table private.join_attempts(user_id uuid not null,created_at timestamptz not null default now());
create index on private.join_attempts(user_id,created_at);
alter table private.join_attempts enable row level security;
create function private.request_membership(code text,display_name text) returns jsonb language plpgsql security definer set search_path='' as $$declare f uuid;begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'verify_email';end if;
 perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
 if (select count(*) from private.join_attempts where user_id=auth.uid() and created_at>now()-interval '1 hour')>=10 then return '{"error":"rate_limited"}'::jsonb;end if;
 insert into private.join_attempts(user_id) values(auth.uid());
 select j.factory_id into f from private.join_codes j where j.code=upper(trim(request_membership.code));
 if f is null or length(trim(display_name)) not between 2 and 100 then return '{"error":"invalid_join_code"}'::jsonb;end if;
 if exists(select 1 from public.memberships where user_id=auth.uid()) then return '{"error":"already_joined"}'::jsonb;end if;
 insert into public.memberships(factory_id,user_id,display_name) values(f,auth.uid(),trim(display_name));return '{"ok":true}'::jsonb;end$$;
create function public.request_membership(code text,display_name text) returns jsonb language sql security invoker set search_path='' as $$select private.request_membership(code,display_name)$$;
revoke execute on function private.join_factory(text,text),public.join_factory(text,text) from authenticated;

-- Delegation cannot grant a permission the acting manager does not possess.
create or replace function private.set_permissions(f uuid,r uuid,p jsonb) returns void language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(f,'roles','edit');
 if not exists(select 1 from public.roles where id=r and factory_id=f) then raise exception 'not_found';end if;
 if not private.is_owner(f) and exists(select 1 from jsonb_to_recordset(p) x(module text,action text) where not private.has_permission(f,x.module,x.action)) then raise exception 'cannot_grant_higher_permissions';end if;
 delete from public.role_permissions where role_id=r and factory_id=f;
 insert into public.role_permissions(factory_id,role_id,module,action) select f,r,x.module,x.action from jsonb_to_recordset(p) x(module text,action text);end$$;
create function private.record_access(f uuid,operation text) returns void language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(f,'factory','view');
 if operation='EXPORT' then perform private.require_permission(f,'reports','export');end if;
 if operation not in ('READ','EXPORT') then raise exception 'invalid_input';end if;
 if operation='EXPORT' or exists(select 1 from public.support_access where factory_id=f and user_id=auth.uid() and (mode='permanent' or (mode='temporary' and expires_at>now()))) then insert into public.audit_logs(factory_id,actor_id,action,entity) values(f,auth.uid(),operation,case when operation='EXPORT' then 'reports' else 'support_access' end);end if;end$$;
create function public.record_access(factory uuid,operation text) returns void language sql security invoker set search_path='' as $$select private.record_access(factory,operation)$$;
-- Managers assigning memberships can read role labels without receiving role-edit permission.
create policy membership_role_labels on public.roles for select to authenticated using(private.has_permission(factory_id,'employees','approve'));
revoke insert,update,delete,truncate,references,trigger on all tables in schema public from anon,authenticated;
revoke all on function private.validate_structure(),private.assignment_history(),private.record_output(uuid,uuid,uuid,numeric,numeric,text),private.request_membership(text,text),private.record_access(uuid,text) from public,anon;
revoke all on function public.record_output(uuid,uuid,uuid,numeric,numeric,text),public.request_membership(text,text),public.record_access(uuid,text) from public,anon;
grant execute on function private.record_output(uuid,uuid,uuid,numeric,numeric,text),private.request_membership(text,text),private.record_access(uuid,text),public.record_output(uuid,uuid,uuid,numeric,numeric,text),public.request_membership(text,text),public.record_access(uuid,text) to authenticated;

create or replace function private.save_record(f uuid,resource text,record_id uuid,p jsonb) returns uuid language plpgsql security definer set search_path='' as $$
 declare table_name text; allowed text[]; k text; columns_sql text:=''; values_sql text:=''; update_sql text:=''; result_id uuid; action text; begin
 action:=case when record_id is null then 'create' else 'edit' end;
 perform private.require_permission(f,case when resource='products' then 'orders' else resource end,action);
 if coalesce((p->>'archived')::boolean,false) then perform private.require_permission(f,resource,'delete');end if;
 case resource
 when 'factory' then table_name:='areas';allowed:=array['name','name_ar','archived'];
 when 'lines' then table_name:='production_lines';allowed:=array['name','name_ar','code','area_id','archived'];
 when 'centers' then table_name:='work_centers';allowed:=array['name','name_ar','code','type','parent_id','area_id','line_id','order_id','operator_id','description','notes','production_speed','default_cycle_time','current_cycle_time','planned_capacity','position','archived','start_time','expected_finish'];
 when 'products' then table_name:='products';allowed:=array['name','name_ar','code','unit','category','diameter','length','color','weight','standard_rate'];
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
