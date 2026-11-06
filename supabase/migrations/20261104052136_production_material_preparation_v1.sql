begin;
-- Forward-only foundation. No stock movements, scheduling or gate activation.
create table private.production_material_policy(factory_id uuid primary key references public.factories(id),seconds numeric not null check(seconds>0 and seconds<=31536000),revision bigint not null default 1);
create table private.production_input_routes(factory_id uuid not null,product_id uuid not null,scope uuid not null default '00000000-0000-0000-0000-000000000000',routing_step_id uuid references public.production_routing_steps(id),mode text not null check(mode in('COMPOUND_STOCK','DIRECT_RAW','COMPOUND_MANUFACTURE')),revision bigint not null default 1,updated_by uuid not null references auth.users(id),updated_at timestamptz not null default clock_timestamp(),primary key(factory_id,product_id,scope),foreign key(factory_id,product_id)references public.products(factory_id,id),check(scope=coalesce(routing_step_id,'00000000-0000-0000-0000-000000000000'::uuid)));
create table private.production_material_config_events(factory_id uuid not null references public.factories(id),request_id uuid not null,actor uuid not null references auth.users(id),operation text not null,intent jsonb not null,before_value jsonb,after_value jsonb not null,at timestamptz not null default clock_timestamp(),primary key(factory_id,request_id));
alter table private.production_material_policy enable row level security;alter table private.production_input_routes enable row level security;alter table private.production_material_config_events enable row level security;
revoke all on private.production_material_policy,private.production_input_routes,private.production_material_config_events from public,anon,authenticated,service_role;
create function private.production_material_config_immutable() returns trigger language plpgsql set search_path='' as $$begin raise exception 'material_audit_immutable' using errcode='42501';end$$;
create trigger immutable before update or delete on private.production_material_config_events for each row execute function private.production_material_config_immutable();
revoke all on function private.production_material_config_immutable()from public,anon,authenticated,service_role;
create function public.production_material_configuration(factory uuid,product uuid default null)returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 perform private.require_permission(factory,'orders','view');
 if product is not null and not exists(select 1 from public.products where factory_id=factory and id=product)then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 return jsonb_build_object('hours',trim_scale(coalesce((select seconds from private.production_material_policy where factory_id=factory),21600)/3600)::text,'seconds',coalesce((select seconds from private.production_material_policy where factory_id=factory),21600)::text,'routes',(select coalesce(jsonb_agg(to_jsonb(r)order by r.product_id,r.scope),'[]')from private.production_input_routes r where r.factory_id=factory and(product is null or r.product_id=product)));
end$$;
create function public.configure_production_materials(factory uuid,operation text,payload jsonb,request_id uuid)returns jsonb language plpgsql security definer set search_path='' as $$declare prior private.production_material_config_events;intent jsonb;before_value jsonb;result jsonb;p public.products;step uuid;v_scope uuid;seconds numeric;begin
 perform private.require_permission(factory,'orders','edit');
 if request_id is null or payload is null or jsonb_typeof(payload)<>'object'or octet_length(payload::text)>4000 then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform pg_advisory_xact_lock(hashtextextended(factory::text||':structure',0));perform private.require_permission(factory,'orders','edit');intent:=jsonb_build_object('operation',operation,'payload',payload);
 select *into prior from private.production_material_config_events e where e.factory_id=factory and e.request_id=configure_production_materials.request_id;
 if found then if prior.actor<>auth.uid()or prior.intent<>intent then raise exception 'request_conflict'using errcode='40001';end if;return prior.after_value;end if;
 if operation='WINDOW'then
 if(select count(*)from jsonb_object_keys(payload))<>1 or not(payload?'hours')or jsonb_typeof(payload->'hours')<>'string'or payload->>'hours'!~'^[0-9]{1,5}([.][0-9]{1,6})?$'then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 seconds:=(payload->>'hours')::numeric*3600;if seconds<=0 or seconds>31536000 then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 select to_jsonb(v)into before_value from private.production_material_policy v where factory_id=factory;
 insert into private.production_material_policy values(factory,seconds,1)on conflict(factory_id)do update set seconds=excluded.seconds,revision=production_material_policy.revision+1;
 result:=jsonb_build_object('hours',trim_scale(seconds/3600)::text,'seconds',trim_scale(seconds)::text);
 elsif operation='ROUTE'then
 if exists(select 1 from jsonb_object_keys(payload)k where k not in('product','routing_step','mode'))or not(payload?&array['product','mode'])or payload->>'mode'not in('COMPOUND_STOCK','DIRECT_RAW','COMPOUND_MANUFACTURE')or payload->>'mode'is null then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 select *into p from public.products where factory_id=factory and id=(payload->>'product')::uuid;if not found then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 step:=(payload->>'routing_step')::uuid;v_scope:=coalesce(step,'00000000-0000-0000-0000-000000000000'::uuid);
 if step is not null and not exists(select 1 from public.production_routing_steps where id=step and factory_id=factory and product_id=p.id)then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 if payload->>'mode'='COMPOUND_MANUFACTURE'and(p.product_kind<>'MANUFACTURED_INTERMEDIATE'or p.stock_unit<>'kg')or payload->>'mode'in('COMPOUND_STOCK','DIRECT_RAW')and(p.formula_product_id is null or p.unit_weight_kg is null or p.unit_weight_kg<=0)then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 if payload->>'mode'in('DIRECT_RAW','COMPOUND_MANUFACTURE')and not exists(select 1 from public.bom_versions where factory_id=factory and product_id=case when payload->>'mode'='COMPOUND_MANUFACTURE'then p.id else p.formula_product_id end and output_unit='kg')then raise exception 'material_recipe_missing'using errcode='22023';end if;
 select to_jsonb(r)into before_value from private.production_input_routes r where r.factory_id=factory and r.product_id=p.id and r.scope=v_scope;
 insert into private.production_input_routes values(factory,p.id,v_scope,step,payload->>'mode',1,auth.uid(),clock_timestamp())on conflict(factory_id,product_id,scope)do update set mode=excluded.mode,revision=production_input_routes.revision+1,updated_by=auth.uid(),updated_at=clock_timestamp();
 select to_jsonb(r)into result from private.production_input_routes r where r.factory_id=factory and r.product_id=p.id and r.scope=v_scope;
 else raise exception 'material_configuration_invalid'using errcode='22023';end if;
 insert into private.production_material_config_events values(factory,request_id,auth.uid(),operation,intent,before_value,result,clock_timestamp());return result;
end$$;
revoke all on function public.production_material_configuration(uuid,uuid),public.configure_production_materials(uuid,text,jsonb,uuid)from public,anon,authenticated,service_role;
grant execute on function public.production_material_configuration(uuid,uuid),public.configure_production_materials(uuid,text,jsonb,uuid)to authenticated;
commit;
