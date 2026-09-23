-- Work center categories: process/compatibility families for routable work centers.
-- Same family ONLY makes a center ELIGIBLE to be configured as an alternative;
-- replacement relationships remain explicit work_center_alternatives rows and live
-- transfers remain governed by transfer_production. Server-enforced invariants:
-- configured alternatives share the category, live transfers independently verify
-- the category, category changes cannot strand incompatible relationships, archived
-- families cannot be assigned and cannot be archived while in use. Categories are
-- delivered to clients through factory_snapshot like all other master data.
-- Also removes the explicitly approved dev/test data: the entire test factory
-- «الأصبح للألمنيوم» and the Nova QA/ZZ/WC-MU89 junk work centers.
BEGIN;

-- =====================================================================
-- 1. Work center categories (tenant-scoped master data, module: centers)
-- =====================================================================
create table public.work_center_categories (
  factory_id uuid not null references public.factories,
  id uuid not null default gen_random_uuid(),
  name text not null constraint wcc_valid_name check (length(trim(name)) between 2 and 120),
  name_ar text not null default '',
  icon_key text not null default 'generic' constraint wcc_valid_icon
    check (icon_key in ('mixer','extruder','cooling','printer','cutter','packing','conveyor','inspection','manual','cell','generic','cnc','drill','press','injection')),
  archived boolean not null default false,
  created_at timestamptz not null default now(),
  constraint wcc_id_unique unique (factory_id, id),
  constraint wcc_name_unique unique (factory_id, name)
);
alter table public.work_center_categories enable row level security;
create policy read_authorized on public.work_center_categories for select to authenticated
  using (private.has_permission(factory_id, 'centers', 'view'));
create trigger audit_record after insert or update or delete on public.work_center_categories
  for each row execute function private.audit_change();
grant select on public.work_center_categories to authenticated;
create index wcc_factory on public.work_center_categories(factory_id);

-- =====================================================================
-- 2. Work center reference (nullable during migration; NOT NULL after the gate)
-- =====================================================================
alter table public.work_centers add column category_id uuid;
alter table public.work_centers
  add constraint work_centers_category_fk
  foreign key (factory_id, category_id)
  references public.work_center_categories(factory_id, id);

-- =====================================================================
-- 3. Single default seed helper + privilege hardening
--    Internal owner-only helper (same convention as owner_grants /
--    capture_stop_context): writes carry no auth checks by design, so no
--    application role may execute it. Called only by this migration and by
--    create_factory (security definer, same owner).
-- =====================================================================
create function private.seed_default_work_center_categories(f uuid) returns void
language sql security definer set search_path='' as $$
insert into public.work_center_categories(factory_id, name, name_ar, icon_key)
select f, d.name, d.name_ar, d.icon_key from (values
  ('Mixing',               'خلط',           'mixer'),
  ('Extrusion',            'بثق',           'extruder'),
  ('Cooling',              'تبريد',         'cooling'),
  ('Pulling / Conveying',  'سحب ونقل',      'conveyor'),
  ('Cutting',              'قطع',           'cutter'),
  ('Printing',             'طباعة',         'printer'),
  ('Packing',              'تعبئة وتغليف',  'packing'),
  ('CNC / Machining',      'تشغيل آلي',     'cnc'),
  ('Drilling',             'ثقب',           'drill'),
  ('Press / Forming',      'كبس وتشكيل',    'press'),
  ('Injection Molding',    'قولبة بالحقن',  'injection'),
  ('Inspection',           'فحص',           'inspection'),
  ('Material Handling',    'مناولة المواد', 'conveyor'),
  ('Generic Work Center',  'مركز عمل عام',  'generic')
) as d(name, name_ar, icon_key)
on conflict (factory_id, name) do nothing;
$$;
revoke all on function private.seed_default_work_center_categories(uuid) from public, anon, authenticated;

-- =====================================================================
-- 4. Delete the entire explicitly-approved test factory (approved; no cascades
--     exist in this schema, so tenant rows are removed child-first)
-- =====================================================================
create temp table doomed on commit drop as
select id
from public.factories
where id = '4370f1a3-0579-4b1e-92ab-ea5fb61bf973'::uuid;
delete from public.production_routing_steps where factory_id in (select id from doomed);
delete from public.production_transfers   where factory_id in (select id from doomed);
delete from public.oee_observations       where factory_id in (select id from doomed);
delete from public.production_entries     where factory_id in (select id from doomed);
delete from public.operator_assignments   where factory_id in (select id from doomed);
delete from public.downtime_events        where factory_id in (select id from doomed);
delete from public.status_events          where factory_id in (select id from doomed);
delete from public.work_center_capabilities where factory_id in (select id from doomed);
delete from public.work_center_alternatives where factory_id in (select id from doomed);
update public.work_centers set parent_id = null where factory_id in (select id from doomed);
delete from public.work_centers           where factory_id in (select id from doomed);
delete from public.daily_targets          where factory_id in (select id from doomed);
delete from public.bom_items              where factory_id in (select id from doomed);
delete from public.bom_versions           where factory_id in (select id from doomed);
delete from public.inventory_reservations where factory_id in (select id from doomed);
delete from public.inventory_transactions where factory_id in (select id from doomed);
delete from public.goods_receipts         where factory_id in (select id from doomed);
delete from public.purchase_orders        where factory_id in (select id from doomed);
delete from public.purchase_requisitions  where factory_id in (select id from doomed);
delete from public.cost_estimates         where factory_id in (select id from doomed);
delete from public.improvement_actions    where factory_id in (select id from doomed);
delete from public.materials              where factory_id in (select id from doomed);
delete from public.suppliers              where factory_id in (select id from doomed);
delete from public.production_orders      where factory_id in (select id from doomed);
delete from public.products               where factory_id in (select id from doomed);
delete from public.production_lines       where factory_id in (select id from doomed);
delete from public.areas                  where factory_id in (select id from doomed);
delete from public.downtime_reasons       where factory_id in (select id from doomed);
delete from public.user_permissions       where factory_id in (select id from doomed);
delete from public.support_access         where factory_id in (select id from doomed);
delete from public.memberships            where factory_id in (select id from doomed);
delete from public.role_permissions       where factory_id in (select id from doomed);
delete from public.roles                  where factory_id in (select id from doomed);
delete from public.audit_logs             where factory_id in (select id from doomed);
delete from private.join_codes            where factory_id in (select id from doomed);
delete from private.platform_scopes       where factory_id in (select id from doomed);
-- The factories audit trigger (audit_record → private.audit_change) writes an
-- audit_logs row whose factory_id FK would reference the very row being deleted
-- (audit inserts for the tenant tables above are safe: the factory still exists
-- at that point). Suppress exactly this trigger for only this approved factory
-- deletion and re-enable it immediately; auditing everywhere else is untouched.
alter table public.factories disable trigger audit_record;
delete from public.factories              where id in (select id from doomed);
alter table public.factories enable trigger audit_record;

-- =====================================================================
-- 5. Nova dev/test junk work centers (approved), FK-safe child-first
-- =====================================================================
create temp table junk on commit drop as
select w.id from public.work_centers w
join public.factories f on f.id = w.factory_id
where f.name = 'Nova Plastic Pipes Factory'
  and (w.code like 'QA-%' or w.name like 'ZZ Test%' or w.code = 'WC-MU89WRZE0MSR7B');
delete from public.production_routing_steps where work_center_id in (select id from junk);
delete from public.production_transfers where original_id in (select id from junk) or alternative_id in (select id from junk);
delete from public.oee_observations where work_center_id in (select id from junk);
delete from public.production_entries where work_center_id in (select id from junk);
delete from public.operator_assignments where work_center_id in (select id from junk);
delete from public.downtime_events where work_center_id in (select id from junk) or alternative_id in (select id from junk);
delete from public.status_events where work_center_id in (select id from junk);
delete from public.work_center_capabilities where work_center_id in (select id from junk);
delete from public.work_center_alternatives where work_center_id in (select id from junk) or alternative_id in (select id from junk);
-- The QA junk rows reference ARCHIVED lines (QA-*-L), so any UPDATE to them
-- trips validate_center's invalid_line_area rule. These rows are approved
-- deletion targets in this same block, so suppress exactly that trigger around
-- this one statement and re-enable immediately; Nova's real machines (M-01…M-12)
-- are structurally valid and never pass through the suppressed window.
alter table public.work_centers disable trigger validate_center;
update public.work_centers set parent_id = null where parent_id in (select id from junk);
alter table public.work_centers enable trigger validate_center;
delete from public.work_centers where id in (select id from junk);

-- =====================================================================
-- 6. Seed defaults for every REMAINING factory, then map Nova explicitly
-- =====================================================================
select private.seed_default_work_center_categories(f.id) from public.factories f;
update public.work_centers wc set category_id = c.id
from public.factories f
join public.work_center_categories c on c.factory_id = f.id
where wc.factory_id = f.id
  and f.name = 'Nova Plastic Pipes Factory'
  and (wc.code, c.name) in (
    ('M-01', 'Mixing'),
    ('M-02', 'Extrusion'),
    ('M-03', 'Cooling'),
    ('M-04', 'Pulling / Conveying'),
    ('M-05', 'Cutting'),
    ('M-06', 'Packing'),
    ('M-07', 'Mixing'),
    ('M-08', 'Extrusion'),
    ('M-09', 'Cooling'),
    ('M-10', 'Printing'),
    ('M-11', 'Cutting'),
    ('M-12', 'Packing')
  );

-- =====================================================================
-- 7. Completeness gate — expose, never hide — then make category mandatory
-- =====================================================================
do $$ declare r record; n int; begin
  select count(*) into n from public.work_centers where category_id is null;
  if n > 0 then
    for r in select code, name from public.work_centers where category_id is null loop
      raise notice 'uncategorized: % %', r.code, r.name;
    end loop;
    raise exception 'uncategorized_work_centers:%', n;
  end if;
end$$;
alter table public.work_centers alter column category_id set not null;

-- =====================================================================
-- 8. save_record: + work_center_categories resource (module centers),
--    + centers.category_id, + category lifecycle invariants
-- =====================================================================
create or replace function private.save_record(f uuid,resource text,record_id uuid,p jsonb) returns uuid language plpgsql security definer set search_path='' as $$
 declare table_name text; perm text; allowed text[]; k text; new_category uuid; columns_sql text:=''; values_sql text:=''; update_sql text:=''; result_id uuid; action text; begin
 action:=case when record_id is null then 'create' else 'edit' end;
 perm:=case when resource='products' then 'orders' when resource='work_center_categories' then 'centers' else resource end;
 perform private.require_permission(f,perm,action);
 if coalesce((p->>'archived')::boolean,false) then perform private.require_permission(f,perm,'delete');end if;
 case resource
 when 'factory' then table_name:='areas';allowed:=array['name','name_ar','archived'];
 when 'lines' then table_name:='production_lines';allowed:=array['name','name_ar','code','area_id','archived'];
 when 'centers' then table_name:='work_centers';allowed:=array['name','name_ar','code','type','category_id','parent_id','area_id','line_id','order_id','operator_id','description','notes','production_speed','default_cycle_time','current_cycle_time','planned_capacity','position','archived','start_time','expected_finish'];
 when 'work_center_categories' then table_name:='work_center_categories';allowed:=array['name','name_ar','icon_key','archived'];
 when 'products' then table_name:='products';allowed:=array['name','name_ar','code','unit','category','diameter','length','color','weight','standard_rate','stage'];
 when 'orders' then table_name:='production_orders';allowed:=array['code','product_id','line_id','status','target_quantity','start_time','expected_finish'];
 when 'downtime' then table_name:='downtime_reasons';allowed:=array['name','name_ar','parent_id','requires_description'];
 when 'roles' then
 table_name:='roles';allowed:=array['name','name_ar'];
 else raise exception 'invalid_resource'; end case;
 if jsonb_typeof(p)<>'object' or p='{}'::jsonb then raise exception 'invalid_input'; end if;
 if resource='centers' and p ? 'category_id' then
   if p->>'category_id' is null or not exists(select 1 from public.work_center_categories c where c.factory_id=f and c.id=(p->>'category_id')::uuid and c.archived=false) then raise exception 'invalid_category';end if;
   new_category:=(p->>'category_id')::uuid;
   if record_id is not null and new_category is distinct from (select category_id from public.work_centers where id=record_id and factory_id=f) then
     if exists(select 1 from public.work_center_alternatives r where r.factory_id=f and record_id in (r.work_center_id,r.alternative_id) and exists(
        select 1 from public.work_centers other
        where other.id=case when r.work_center_id=record_id then r.alternative_id else r.work_center_id end
          and other.category_id is distinct from new_category)) then raise exception 'category_alternative_conflict';end if;end if;end if;
 if resource='work_center_categories' and record_id is not null and coalesce((p->>'archived')::boolean,false) then
   if exists(select 1 from public.work_centers w where w.category_id=record_id and w.factory_id=f and w.archived=false) then raise exception 'category_in_use';end if;end if;
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

-- =====================================================================
-- 9. configure_center_links: alternatives must share the work center's category
-- =====================================================================
create or replace function private.configure_center_links(f uuid,w uuid,alternatives uuid[],capabilities jsonb) returns void language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(f,'centers','edit');
 perform 1 from public.work_centers where id=w and factory_id=f and not archived for update;
 if not found then raise exception 'not_found';end if;
 if exists(select 1 from unnest(alternatives) x where x=w or not exists(select 1 from public.work_centers c where c.id=x and c.factory_id=f and not c.archived)) then raise exception 'invalid_alternative';end if;
 if exists(select 1 from unnest(alternatives) x
    join public.work_centers o on o.id=w
    join public.work_centers a on a.id=x
    where o.category_id is distinct from a.category_id) then raise exception 'incompatible_alternative';end if;
 delete from public.work_center_alternatives where factory_id=f and work_center_id=w;
 insert into public.work_center_alternatives(factory_id,work_center_id,alternative_id) select f,w,x from unnest(alternatives) x;
 delete from public.work_center_capabilities where factory_id=f and work_center_id=w;
 insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate) select f,w,x.product_id,x.rate from jsonb_to_recordset(capabilities) x(product_id uuid,rate numeric);
 end$$;

-- =====================================================================
-- 10. transfer_production: independent same-category verification
-- =====================================================================
create or replace function private.transfer_production(f uuid,w uuid,a uuid,n text) returns uuid language plpgsql security definer set search_path='' as $$declare o uuid;d uuid;i uuid;begin
 perform private.require_permission(f,'centers','edit');perform private.require_permission(f,'orders','edit');
 perform pg_advisory_xact_lock(hashtextextended(f::text||':structure',0));
 perform 1 from public.work_centers where factory_id=f and id in (w,a) order by id for update;
 select order_id into o from public.work_centers where id=w and factory_id=f and not archived and status='stopped';
 select id into d from public.downtime_events where work_center_id=w and factory_id=f and ended_at is null;
 if o is null or d is null or not exists(select 1 from public.production_orders where id=o and status='active') then raise exception 'invalid_order';end if;
 if not exists(select 1 from public.work_center_alternatives where factory_id=f and work_center_id=w and alternative_id=a)
    or not exists(select 1 from public.work_centers where id=a and factory_id=f and not archived and status='idle' and (order_id is null or order_id=o))
    or (select category_id from public.work_centers where id=w) is distinct from (select category_id from public.work_centers where id=a)
    then raise exception 'incompatible_alternative';end if;
 insert into public.production_transfers(factory_id,original_id,alternative_id,order_id,downtime_id,reason,created_by) values(f,w,a,o,d,n,auth.uid()) returning id into i;
 update public.work_centers set order_id=o where id=a;
 perform private.change_status(f,a,'running',null,null,n,null,null,null,false);
 update public.downtime_events set alternative_id=a,transferred=true where id=d;
 return i;end$$;

-- =====================================================================
-- 11. create_factory: seed the same defaults for every new factory
-- =====================================================================
create or replace function private.create_factory(n text,tz text,industry text) returns uuid language plpgsql security definer set search_path='' as $$
 declare f uuid; r uuid; v text; begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'verify_email'; end if;
 if not private.is_platform_admin() and exists(select 1 from public.memberships where user_id=auth.uid()) then raise exception 'already_joined'; end if;
 if not exists(select 1 from pg_timezone_names where name=tz) then raise exception 'invalid_timezone'; end if;
 insert into public.factories(name,timezone,industry,created_by) values(n,tz,industry,auth.uid()) returning id into f;
 insert into private.join_codes values(f,'FAC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)));
 foreach v in array array['Factory Owner','Factory Manager','Production Engineer','Planning Engineer','Warehouse Manager','Sales Employee','Quality Engineer','Maintenance Engineer','Safety Officer','Production Supervisor','Technician / Operator','Platform Support Engineer','Custom Role'] loop
 insert into public.roles(factory_id,name) values(f,v) returning id into r;
 if v='Factory Owner' and not private.is_platform_admin() then insert into public.memberships(factory_id,user_id,display_name,role_id,is_owner,status) values(f,auth.uid(),split_part((select email from auth.users where id=auth.uid()),'@',1),r,true,'approved'); end if;
 if v='Factory Manager' then insert into public.role_permissions select f,r,module,action from public.permissions where module not in ('roles','support');
 elsif v in ('Production Engineer','Production Supervisor') then insert into public.role_permissions select f,r,module,action from public.permissions where (action='view' and module in ('dashboard','factory','lines','centers','orders','downtime','reports','employees')) or (action='edit' and module in ('centers','orders','downtime'));
 elsif v='Technician / Operator' then insert into public.role_permissions select f,r,module,action from public.permissions where (action='view' and module in ('dashboard','factory','lines','centers','orders','downtime')) or (action='edit' and module='machine_status'); end if;
 end loop;
 insert into public.downtime_reasons(factory_id,name,name_ar,requires_description)
 select f,x.en,x.ar,x.en='Other' from (values('Mechanical Failure','عطل ميكانيكي'),('Electrical Failure','عطل كهربائي'),('Material Shortage','نقص مواد'),('Operator Unavailable','عدم توفر المشغل'),('Tooling Problem','مشكلة في العِدد'),('Setup / Changeover','إعداد / تغيير المنتج'),('Quality Problem','مشكلة جودة'),('Waiting for Approval','انتظار الموافقة'),('Maintenance','صيانة'),('Cleaning','تنظيف'),('Power Failure','انقطاع الكهرباء'),('Production Planning Delay','تأخير تخطيط الإنتاج'),('Other','أخرى')) x(en,ar);
 perform private.seed_default_work_center_categories(f);
 if private.is_platform_admin() then perform private.open_platform_factory(f);end if;
 return f;
 end$$;

-- =====================================================================
-- 12. factory_snapshot: deliver work_center_categories with the normal tables
-- =====================================================================
create or replace function public.factory_snapshot(factory uuid default null) returns jsonb language plpgsql security invoker set search_path='' as $$
declare m jsonb;f uuid;fac jsonb;tab text;rows jsonb;data jsonb:='{}';limited text[]:='{}';begin
 select to_jsonb(x) into m from public.memberships x where user_id=auth.uid();
 f:=case when private.is_platform_admin() then $1 when m->>'status'='approved' then (m->>'factory_id')::uuid else $1 end;
 if f is not null then
 if private.is_platform_admin() then perform private.open_platform_factory(f);end if;
 perform private.require_permission(f,'factory','view');
 perform private.record_access(f,'READ');
 select to_jsonb(x) into fac from public.factories x where id=f;
 foreach tab in array array['areas','work_center_categories','production_lines','work_centers','products','production_orders','downtime_reasons','status_events','downtime_events','memberships','roles','role_permissions','support_access','audit_logs','oee_observations','production_entries','operator_assignments','work_center_alternatives','work_center_capabilities','daily_targets','user_permissions','production_transfers','production_routing_steps'] loop
 execute format('select coalesce(jsonb_agg(x),''[]'') from (select * from public.%I where factory_id=$1 %s limit 5000) x',tab,case when tab in ('status_events','audit_logs','production_entries','downtime_events') then 'order by created_at desc,id' else '' end) into rows using f;
 data:=data||jsonb_build_object(tab,rows);
 if jsonb_array_length(rows)=5000 then limited:=array_append(limited,tab);end if;
 end loop;
 data:=data||jsonb_build_object('machine_statuses',(select jsonb_agg(x) from public.machine_statuses x where code<>'maintenance'),'permissions',(select jsonb_agg(x) from public.permissions x));
 end if;
 return jsonb_build_object('platformAdmin',private.is_platform_admin(),'factories',case when f is null then private.platform_factories() else '[]'::jsonb end,'factory',fac,'membership',m,'permissions',case when f is null then '{}'::text[] else public.access_matrix(f) end,'tables',data,'supportFactories',(select coalesce(jsonb_agg(x),'[]'::jsonb) from public.support_access x where user_id=auth.uid()),'truncatedTables',limited,'fetchedAt',now());
end$$;

COMMIT;
