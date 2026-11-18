-- F45: compose existing product/BOM/capability contracts; no historical backfill.
alter table public.products add column weight_basis text check(weight_basis in('STOCK_UNIT','PIECE'));

create function private.product_configuration_fingerprint(f uuid,p uuid)returns text language sql stable security definer set search_path=''as $$
select encode(sha256(convert_to(jsonb_build_array(
 (select to_jsonb(x)from public.products x where factory_id=f and id=p),
 (select jsonb_agg(to_jsonb(b)order by id)from public.bom_versions b where factory_id=f and product_id in(p,(select formula_product_id from public.products where factory_id=f and id=p))),
 (select jsonb_agg(to_jsonb(c)order by work_center_id,product_id)from public.work_center_capabilities c where factory_id=f and product_id=p),
 (select jsonb_agg(to_jsonb(r)order by scope)from private.production_input_routes r where factory_id=f and product_id=p),
 (select jsonb_agg(jsonb_build_array(id,line_id,category_id,archived)order by id)from public.work_centers where factory_id=f),
 (select jsonb_agg(jsonb_build_array(id,archived)order by id)from public.production_lines where factory_id=f)
)::text,'UTF8')),'hex')$$;
revoke all on function private.product_configuration_fingerprint(uuid,uuid)from public,anon,authenticated,service_role;

create function public.product_configuration_context(factory uuid,product uuid default null,request_id uuid default null)returns jsonb language plpgsql stable security definer set search_path=''as $$
#variable_conflict use_column
declare p public.products;receipt public.fulfillment_commands;begin
 perform private.require_permission(factory,'orders','view');
 if request_id is not null then
  select *into receipt from public.fulfillment_commands c where c.factory_id=factory and c.request_id=product_configuration_context.request_id and c.actor_id=auth.uid()and operation='product_configuration';
  return jsonb_build_object('receipt',case when receipt.request_id is not null then jsonb_build_object('request_id',receipt.request_id,'intent',receipt.payload,'id',receipt.result_id)end);
 end if;
 if product is not null then select *into p from public.products where factory_id=factory and id=product;if not found then raise exception 'not_found';end if;end if;
 return jsonb_build_object('factory',factory,'product',to_jsonb(p),'fingerprint',private.product_configuration_fingerprint(factory,product),
 'recipe',(select to_jsonb(b)||jsonb_build_object('components',(select jsonb_agg(to_jsonb(i)order by material_id)from public.bom_items i where i.factory_id=factory and i.bom_id=b.id))from public.bom_versions b where factory_id=factory and product_id=coalesce(p.formula_product_id,p.length_parent_id,p.id)and output_unit='kg'order by version desc,created_at desc,id desc limit 1),
 'recipes',(select coalesce(jsonb_agg(to_jsonb(x)order by name,id),'[]')from(select p.id,p.name,p.name_ar,p.code,b.version from public.products p join lateral(select version from public.bom_versions where factory_id=factory and product_id=p.id and output_unit='kg'order by version desc limit 1)b on true where p.factory_id=factory and p.product_kind='MANUFACTURED_INTERMEDIATE'and p.stock_unit='kg')x),
 'materials',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'name_ar',name_ar,'unit',unit)order by name,id),'[]')from public.materials where factory_id=factory and unit='kg'and inventory_kind='RAW_MATERIAL'),
 'lines',(select coalesce(jsonb_agg(to_jsonb(x)order by name,id),'[]')from(select id,name,name_ar,code from public.production_lines where factory_id=factory and not archived)x),
 'machines',(select coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,'name_ar',w.name_ar,'line_id',w.line_id,'category_id',w.category_id,'category',c.name,'dependency_mode',w.dependency_mode)order by w.position,w.name,w.id),'[]')from public.work_centers w left join public.work_center_categories c on c.factory_id=w.factory_id and c.id=w.category_id where w.factory_id=factory and not w.archived and w.line_id is not null and w.type='machine'),
 'capabilities',(select coalesce(jsonb_agg(to_jsonb(c)order by work_center_id),'[]')from public.work_center_capabilities c where factory_id=factory and product_id=p.id),
 'input_mode',(select mode from private.production_input_routes where factory_id=factory and product_id=p.id and scope='00000000-0000-0000-0000-000000000000'),
 'stage_routes',exists(select 1 from private.production_input_routes where factory_id=factory and product_id=p.id and routing_step_id is not null),
 'shared',exists(select 1 from public.products where factory_id=factory and formula_product_id=p.id),
 'historical_weight',exists(select 1 from public.production_entries e join public.production_orders o on o.factory_id=e.factory_id and o.id=e.order_id where o.factory_id=factory and o.product_id=p.id)or exists(select 1 from public.finished_goods_movements where factory_id=factory and product_id=p.id));
end$$;
revoke all on function public.product_configuration_context(uuid,uuid,uuid)from public,anon,service_role;
grant execute on function public.product_configuration_context(uuid,uuid,uuid)to authenticated;

create function public.save_product_configuration(factory uuid,product uuid,payload jsonb,recipe jsonb,lines jsonb,fingerprint text,request_id uuid)returns uuid language plpgsql security definer set search_path=''as $$
#variable_conflict use_variable
declare prior uuid;intent jsonb;old public.products;id uuid;part jsonb;parts jsonb;mat uuid;amount numeric;waste numeric;seen uuid[]:='{}';bom uuid;version integer;formula uuid;reuse boolean;mode text;line jsonb;center uuid;centers uuid[];w record;caps jsonb;basis text;weight numeric;unit_weight numeric;length numeric;body jsonb;changed boolean;begin
 perform private.require_permission(factory,'orders',case when product is null then 'create'else 'edit'end);
 if request_id is null or jsonb_typeof(payload)is distinct from 'object'or jsonb_typeof(recipe)is distinct from 'object'or(lines is not null and jsonb_typeof(lines)<>'array')or fingerprint!~'^[a-f0-9]{64}$'or fingerprint is null or octet_length(payload::text||recipe::text||coalesce(lines::text,''))>100000 then raise exception 'f45Invalid';end if;
 if exists(select 1 from jsonb_object_keys(payload)k where k not in('name','name_ar','code','category','unit','diameter','length','color','weight','standard_rate','stage','product_kind','stock_unit','unit_weight_kg','weight_basis'))or exists(select 1 from jsonb_object_keys(recipe)k where k not in('mode','formula','components','reuse','name','input_mode'))then raise exception 'f45Invalid';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.maintenance_planning_lock(factory);perform private.fulfillment_lock(factory);
 perform private.require_permission(factory,'orders',case when product is null then 'create'else 'edit'end);
 intent:=jsonb_build_object('product',product,'payload',payload,'recipe',recipe,'lines',lines,'fingerprint',fingerprint);
 prior:=private.fulfillment_retry(factory,request_id,'product_configuration',intent);if prior is not null then return prior;end if;
 if private.product_configuration_fingerprint(factory,product)is distinct from fingerprint then raise exception 'f45Changed'using errcode='40001';end if;
 if product is not null then select *into old from public.products where factory_id=factory and products.id=product for update;if not found then raise exception 'not_found';end if;end if;
 body:=payload-'weight_basis';basis:=payload->>'weight_basis';weight:=(payload->>'weight')::numeric;length:=(payload->>'length')::numeric;
 if basis is not null then
  if basis not in('STOCK_UNIT','PIECE')or weight is null or weight<=0 or weight::text in('NaN','Infinity','-Infinity')or payload->>'stock_unit'is null then raise exception 'f45Weight';end if;
  if payload->>'stock_unit'='kg'then unit_weight:=1;
  elsif basis='PIECE'and payload->>'stock_unit'='meter'then if length is null or length<=0 or length::text in('NaN','Infinity','-Infinity')then raise exception 'f45Length';end if;unit_weight:=weight/length;
  elsif payload->>'stock_unit'in('meter','piece')then unit_weight:=weight;
  else raise exception 'f45Weight';end if;
  body:=jsonb_set(body,'{unit_weight_kg}',to_jsonb(unit_weight));
 end if;
 if old.length_parent_id is not null and (basis is distinct from old.weight_basis or (body->>'unit_weight_kg')::numeric is distinct from old.unit_weight_kg or recipe->>'mode'<>'KEEP'or lines is not null)then raise exception 'f45Inherited';end if;
 if old.unit_weight_kg is not null and (body->>'unit_weight_kg')::numeric is distinct from old.unit_weight_kg and(exists(select 1 from public.production_entries e join public.production_orders o on o.id=e.order_id where o.factory_id=factory and o.product_id=product)or exists(select 1 from public.finished_goods_movements where factory_id=factory and product_id=product))then raise exception 'f45HistoricalWeight';end if;
 mode:=recipe->>'mode';if mode is null or mode not in('KEEP','DRAFT','EXISTING','INLINE')then raise exception 'f45Invalid';end if;
 changed:=mode<>'KEEP'or (body->>'unit_weight_kg')::numeric is distinct from old.unit_weight_kg or body->>'stock_unit'is distinct from old.stock_unit or body->>'unit'is distinct from old.unit;
 if product is not null and changed and exists(select 1 from public.production_orders o join public.products p on p.id=o.product_id where o.factory_id=factory and(p.id=product or p.formula_product_id=product)and(o.status='active'or o.status='planned'and exists(select 1 from public.production_entries where factory_id=factory and order_id=o.id)))then raise exception 'f45ActiveDefinition';end if;
 if mode='KEEP'then formula:=old.formula_product_id;
 elsif mode='EXISTING'then formula:=(recipe->>'formula')::uuid;if formula is null or not exists(select 1 from public.products p join public.bom_versions b on b.factory_id=p.factory_id and b.product_id=p.id where p.factory_id=factory and p.id=formula and p.product_kind='MANUFACTURED_INTERMEDIATE'and p.stock_unit='kg'and b.output_unit='kg')then raise exception 'f45RecipeInvalid';end if;
 else formula:=null;end if;
 if mode='DRAFT'and product is not null and(exists(select 1 from public.bom_versions where factory_id=factory and product_id=product)or old.formula_product_id is not null)then raise exception 'f45RecipeKeep';end if;
 if mode='INLINE'and old.product_kind='MANUFACTURED_INTERMEDIATE'and exists(select 1 from public.products where factory_id=factory and formula_product_id=product)then raise exception 'f45SharedRecipe';end if;
 if formula is not null and((body->>'unit_weight_kg')::numeric is null or body->>'stock_unit'is null)then raise exception 'f45Weight';end if;
 if formula is not null then body:=jsonb_set(body,'{formula_product_id}',to_jsonb(formula));else body:=body||jsonb_build_object('formula_product_id',null);end if;
 if nullif(btrim(body->>'code'),'')is null then
  if product is not null then body:=jsonb_set(body,'{code}',to_jsonb(old.code));else
   loop body:=jsonb_set(body,'{code}',to_jsonb('PRD-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12))));exit when not exists(select 1 from public.products where factory_id=factory and code=body->>'code');end loop;
  end if;
 end if;
 if exists(select 1 from public.products where factory_id=factory and products.id is distinct from product and code=body->>'code')then raise exception 'f45CodeUsed'using errcode='23505';end if;
 id:=public.define_manufactured_product(factory,product,body,null,gen_random_uuid());
 update public.products set weight_basis=basis where factory_id=factory and products.id=id;
 if mode='INLINE'then
  parts:=recipe->'components';reuse:=coalesce((recipe->>'reuse')::boolean,false);
  if jsonb_typeof(parts)is distinct from 'array'or jsonb_array_length(parts)not between 1 and 100 then raise exception 'f45RecipeInvalid';end if;
  if reuse and payload->>'product_kind'='MANUFACTURED_INTERMEDIATE'then raise exception 'f45RecipeInvalid';end if;
  if reuse then
   formula:=public.define_manufactured_product(factory,null,jsonb_build_object('name',coalesce(nullif(btrim(recipe->>'name'),''),left(payload->>'name',100)||' recipe'),'name_ar','','code','RCP-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),'unit','kg','stock_unit','kg','product_kind','MANUFACTURED_INTERMEDIATE','stage','finished','unit_weight_kg',1),null,gen_random_uuid());
   update public.products set formula_product_id=formula where factory_id=factory and products.id=id;
  else formula:=id;end if;
  select coalesce(max(b.version),0)+1 into version from public.bom_versions b where b.factory_id=factory and b.product_id=formula;
  insert into public.bom_versions(factory_id,product_id,version,batch_quantity,output_unit,created_by)values(factory,formula,version,1,'kg',auth.uid())returning bom_versions.id into bom;
  for part in select value from jsonb_array_elements(parts)loop
   if jsonb_typeof(part)<>'object'or exists(select 1 from jsonb_object_keys(part)k where k not in('material_id','quantity','unit','waste_allowance'))then raise exception 'f45RecipeInvalid';end if;
   mat:=(part->>'material_id')::uuid;amount:=(part->>'quantity')::numeric;waste:=coalesce((part->>'waste_allowance')::numeric,0);
   if mat is null or mat=any(seen)or amount is null or amount<=0 or amount::text in('NaN','Infinity','-Infinity')or part->>'unit'is distinct from 'kg'or waste<0 or waste::text in('NaN','Infinity','-Infinity')or not exists(select 1 from public.materials where factory_id=factory and materials.id=mat and unit='kg'and inventory_kind='RAW_MATERIAL')then raise exception 'f45RecipeInvalid';end if;
   seen:=array_append(seen,mat);insert into public.bom_items(factory_id,bom_id,material_id,quantity,unit,waste_allowance)values(factory,bom,mat,amount,'kg',waste);
  end loop;
 end if;
 if mode in('INLINE','EXISTING')and payload->>'stock_unit'is not null and (body->>'unit_weight_kg')::numeric>0 then
  perform public.configure_production_materials(factory,'ROUTE',jsonb_build_object('product',id,'mode',coalesce(nullif(recipe->>'input_mode',''),case when payload->>'product_kind'='MANUFACTURED_INTERMEDIATE'then 'COMPOUND_MANUFACTURE'else 'DIRECT_RAW'end)),gen_random_uuid());
 elsif nullif(recipe->>'input_mode','')is not null then perform public.configure_production_materials(factory,'ROUTE',jsonb_build_object('product',id,'mode',recipe->>'input_mode'),gen_random_uuid());end if;
 if lines is not null then
  perform private.require_permission(factory,'centers','edit');
  if old.length_parent_id is not null then raise exception 'f45Inherited';end if;
  if exists(select 1 from jsonb_array_elements(lines)r where jsonb_typeof(r)<>'object'or exists(select 1 from jsonb_object_keys(r)k where k not in('line','rate','machines')))or(select count(*)<>count(distinct x->>'line')from jsonb_array_elements(lines)x)then raise exception 'f45Line';end if;
  centers:='{}';
  for line in select value from jsonb_array_elements(lines)loop
   if not exists(select 1 from public.production_lines where factory_id=factory and production_lines.id=(line->>'line')::uuid and not archived)or jsonb_typeof(line->'machines')is distinct from 'array'or jsonb_array_length(line->'machines')=0 or(line->>'rate')::numeric is null or(line->>'rate')::numeric<=0 or(line->>'rate')::numeric::text in('NaN','Infinity','-Infinity')or payload->>'unit'not in('meter','piece','kg')then raise exception 'f45Line';end if;
   for center in select value::text::uuid from jsonb_array_elements_text(line->'machines')loop
    if center=any(centers)or not exists(select 1 from public.work_centers where factory_id=factory and work_centers.id=center and line_id=(line->>'line')::uuid and category_id is not null and not archived and type='machine')then raise exception 'f45Line';end if;centers:=array_append(centers,center);
   end loop;
  end loop;
  -- Existing machine writer owns validation, inherited cut-length capabilities and audit.
  for w in select c.*from public.work_centers c where c.factory_id=factory and(c.id=any(centers)or exists(select 1 from public.work_center_capabilities cap where cap.factory_id=factory and cap.work_center_id=c.id and cap.product_id=id and c.line_id is not null))order by c.id for update loop
   if exists(select 1 from public.production_orders o join public.work_center_capabilities cap on cap.factory_id=o.factory_id and cap.product_id=o.product_id and cap.work_center_id=w.id where o.factory_id=factory and o.product_id=id and o.status='active'and coalesce(o.actual_line_id,o.line_id)=w.line_id and(not(w.id=any(centers))or cap.rate_unit is distinct from payload->>'unit'or cap.rate is distinct from(select(value->>'rate')::numeric from jsonb_array_elements(lines)where value->>'line'=w.line_id::text)))then raise exception 'f45ActiveCapability';end if;
   select coalesce(jsonb_agg(to_jsonb(cap)-'factory_id'-'work_center_id'order by product_id),'[]')into caps from public.work_center_capabilities cap join public.products p on p.factory_id=cap.factory_id and p.id=cap.product_id where cap.factory_id=factory and cap.work_center_id=w.id and cap.product_id<>id and p.length_parent_id is null;
   if w.id=any(centers)then select value into line from jsonb_array_elements(lines)where value->>'line'=w.line_id::text;
    caps:=caps||jsonb_build_array(jsonb_build_object('product_id',id,'rate',(line->>'rate')::numeric,'rate_unit',payload->>'unit','setup_minutes',coalesce((select setup_minutes from public.work_center_capabilities where factory_id=factory and work_center_id=w.id and product_id=id),0)));
   end if;
   perform public.configure_center_capabilities(factory,w.id,caps);
  end loop;
 end if;
 perform private.refresh_production_stock(factory);
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'product_configuration',intent,id,clock_timestamp());return id;
end$$;
revoke all on function public.save_product_configuration(uuid,uuid,jsonb,jsonb,jsonb,text,uuid)from public,anon,service_role;
grant execute on function public.save_product_configuration(uuid,uuid,jsonb,jsonb,jsonb,text,uuid)to authenticated;

CREATE OR REPLACE FUNCTION public.product_requirements(factory uuid, product uuid, quantity numeric, unit text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$declare p public.products;compound uuid;b public.bom_versions;amount numeric;begin
 perform private.require_permission(factory,'orders','view');
 select * into p from public.products where factory_id=factory and id=product;
 if not found or quantity is null or quantity<=0 or quantity::text in ('NaN','Infinity','-Infinity') or unit is distinct from p.stock_unit then raise exception 'supply_invalid';end if;
 compound:=case when p.product_kind='MANUFACTURED_INTERMEDIATE' then p.id else coalesce(p.formula_product_id,p.length_parent_id,p.id) end;
 amount:=case when p.product_kind='MANUFACTURED_INTERMEDIATE' and unit='kg' then quantity else quantity*p.unit_weight_kg end;
 select * into b from public.bom_versions where factory_id=factory and product_id=compound and output_unit='kg' order by version desc,created_at desc,id desc limit 1;
 return jsonb_build_object('theoretical',true,'compound_id',compound,'compound_quantity_kg',amount,'formula_version',b.version,
 'raw_materials',case when b.id is null or amount is null then null else (select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'name',m.name,'name_ar',m.name_ar,'unit',i.unit,'quantity',amount*i.quantity/b.batch_quantity)),'[]') from public.bom_items i join public.materials m on m.id=i.material_id where i.factory_id=factory and i.bom_id=b.id) end);
end$function$
;

CREATE OR REPLACE FUNCTION private.material_requirement_inputs(f uuid, i uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$declare o public.production_orders;p public.products;r private.production_input_routes;b public.bom_versions;compound uuid;mass numeric;v jsonb;matches integer;begin
 select *into o from public.production_orders where factory_id=f and id=i;select *into p from public.products where factory_id=f and id=o.product_id;
 if o.id is null then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 -- Existing completion/rework owns its source-lot requirement; never explode a recipe again.
 if exists(select 1 from private.manufactured_completion_work where factory_id=f and item_id=i)or o.quality_origin_rejection_id is not null then return jsonb_build_object('existing_source_work',true,'inputs','[]'::jsonb);end if;
 select count(*)into matches from private.production_input_routes x join public.production_routing_steps s on s.id=x.routing_step_id join public.work_centers w on w.id=s.work_center_id where x.factory_id=f and x.product_id=p.id and w.line_id=o.line_id;
 if matches>1 then return jsonb_build_object('warning','material_route_ambiguous');end if;
 if matches=1 then select x.*into r from private.production_input_routes x join public.production_routing_steps s on s.id=x.routing_step_id join public.work_centers w on w.id=s.work_center_id where x.factory_id=f and x.product_id=p.id and w.line_id=o.line_id;else select *into r from private.production_input_routes where factory_id=f and product_id=p.id and scope='00000000-0000-0000-0000-000000000000';end if;
 if r.product_id is null then return jsonb_build_object('warning','material_route_missing');end if;
 if o.unit is distinct from p.stock_unit then return jsonb_build_object('warning','material_unit_missing');end if;
 mass:=case when r.mode='COMPOUND_MANUFACTURE'and p.stock_unit='kg'then o.target_quantity else o.target_quantity*p.unit_weight_kg end;
 if mass is null or mass<=0 or mass::text in('NaN','Infinity','-Infinity')then return jsonb_build_object('warning','material_weight_missing');end if;
 compound:=case when r.mode='COMPOUND_MANUFACTURE'then p.id else coalesce(p.formula_product_id,p.length_parent_id,p.id) end;
 if r.mode='COMPOUND_STOCK'then
 if not exists(select 1 from public.products where factory_id=f and id=compound and product_kind='MANUFACTURED_INTERMEDIATE'and stock_unit='kg')then return jsonb_build_object('warning','material_configuration_invalid');end if;
 v:=jsonb_build_array(jsonb_build_object('kind','product','id',compound,'unit','kg','quantity',trim_scale(mass)::text));
 else
 select *into b from public.bom_versions where factory_id=f and product_id=compound and output_unit='kg'order by version desc,created_at desc,id desc limit 1;
 if b.id is null or not exists(select 1 from public.bom_items where factory_id=f and bom_id=b.id)then return jsonb_build_object('warning','material_recipe_missing');end if;
 if exists(select 1 from public.bom_items x join public.materials m on m.id=x.material_id where x.factory_id=f and x.bom_id=b.id and(x.unit<>m.unit or m.inventory_kind<>'RAW_MATERIAL'))then return jsonb_build_object('warning','material_unit_missing');end if;
 select jsonb_agg(jsonb_build_object('kind','material','id',material_id,'unit',unit,'quantity',trim_scale(quantity)::text)order by material_id)into v from(select x.material_id,x.unit,sum(mass*x.quantity/b.batch_quantity*(1+x.waste_allowance))quantity from public.bom_items x where x.factory_id=f and x.bom_id=b.id group by x.material_id,x.unit)q;
 end if;
 return jsonb_build_object('mode',r.mode,'route',r.scope,'route_revision',r.revision,'recipe',b.id,'recipe_version',b.version,'inputs',v);
end$function$
;

CREATE OR REPLACE FUNCTION public.configure_production_materials(factory uuid, operation text, payload jsonb, request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare prior private.production_material_config_events;intent jsonb;before_value jsonb;result jsonb;p public.products;step uuid;v_scope uuid;seconds numeric;begin
 if operation='DEVIATION'then perform private.require_permission(factory,'warehouse','edit');else perform private.require_permission(factory,'orders','edit');end if;
 if request_id is null or payload is null or jsonb_typeof(payload)<>'object'or octet_length(payload::text)>4000 then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform pg_advisory_xact_lock(hashtextextended(factory::text||':structure',0));if operation='DEVIATION'then perform private.require_permission(factory,'warehouse','edit');else perform private.require_permission(factory,'orders','edit');end if;intent:=jsonb_build_object('operation',operation,'payload',payload);
 select *into prior from private.production_material_config_events e where e.factory_id=factory and e.request_id=configure_production_materials.request_id;
 if found then if prior.actor<>auth.uid()or prior.intent<>intent then raise exception 'request_conflict'using errcode='40001';end if;return prior.after_value;end if;
 if operation='DEVIATION'then
 if(select count(*)from jsonb_object_keys(payload))<>1 or jsonb_typeof(payload->'percent')is distinct from 'string'or payload->>'percent'!~'^[0-9]+([.][0-9]+)?$'or(payload->>'percent')::numeric>1000 then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 select to_jsonb(v)into before_value from private.production_material_policy v where factory_id=factory;
 insert into private.production_material_policy(factory_id,seconds,deviation_percent)values(factory,21600,(payload->>'percent')::numeric)on conflict(factory_id)do update set deviation_percent=excluded.deviation_percent,revision=production_material_policy.revision+1;result:=jsonb_build_object('deviation_percent',payload->>'percent');
 elsif operation='WINDOW'then
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
 if payload->>'mode'='COMPOUND_MANUFACTURE'and(p.product_kind<>'MANUFACTURED_INTERMEDIATE'or p.stock_unit<>'kg')or payload->>'mode'in('COMPOUND_STOCK','DIRECT_RAW')and((payload->>'mode'='COMPOUND_STOCK'and p.formula_product_id is null)or p.unit_weight_kg is null or p.unit_weight_kg<=0)then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 if payload->>'mode'in('DIRECT_RAW','COMPOUND_MANUFACTURE')and not exists(select 1 from public.bom_versions where factory_id=factory and product_id=case when payload->>'mode'='COMPOUND_MANUFACTURE'then p.id else coalesce(p.formula_product_id,p.length_parent_id,p.id) end and output_unit='kg')then raise exception 'material_recipe_missing'using errcode='22023';end if;
 select to_jsonb(r)into before_value from private.production_input_routes r where r.factory_id=factory and r.product_id=p.id and r.scope=v_scope;
 insert into private.production_input_routes values(factory,p.id,v_scope,step,payload->>'mode',1,auth.uid(),clock_timestamp())on conflict(factory_id,product_id,scope)do update set mode=excluded.mode,revision=production_input_routes.revision+1,updated_by=auth.uid(),updated_at=clock_timestamp();
 select to_jsonb(r)into result from private.production_input_routes r where r.factory_id=factory and r.product_id=p.id and r.scope=v_scope;
 else raise exception 'material_configuration_invalid'using errcode='22023';end if;
 insert into private.production_material_config_events values(factory,request_id,auth.uid(),operation,intent,before_value,result,clock_timestamp());return result;
end$function$
;

CREATE OR REPLACE FUNCTION private.guard_formula_identity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
 perform private.fulfillment_lock(new.factory_id);
 if row(new.product_kind,new.stock_unit)is distinct from row(old.product_kind,old.stock_unit)
  and (exists(select 1 from public.products p where p.factory_id=old.factory_id and p.formula_product_id=old.id)
   or exists(select 1 from public.bom_versions b where b.factory_id=old.factory_id and b.product_id=old.id and b.output_unit='kg')) then raise exception 'supply_state';end if;
 return new;
end$function$
;
