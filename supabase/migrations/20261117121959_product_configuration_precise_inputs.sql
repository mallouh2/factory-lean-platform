-- F45: retain exact legacy decimal inputs and original recipe batch bases. No row backfill.
CREATE OR REPLACE FUNCTION public.product_configuration_context(factory uuid, product uuid DEFAULT NULL::uuid, request_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare p public.products;receipt public.fulfillment_commands;begin
 perform private.require_permission(factory,'orders','view');
 if request_id is not null then
  select *into receipt from public.fulfillment_commands c where c.factory_id=factory and c.request_id=product_configuration_context.request_id and c.actor_id=auth.uid()and operation='product_configuration';
  return jsonb_build_object('receipt',case when receipt.request_id is not null then jsonb_build_object('request_id',receipt.request_id,'intent',receipt.payload,'id',receipt.result_id)end);
 end if;
 if product is not null then select *into p from public.products where factory_id=factory and id=product;if not found then raise exception 'not_found';end if;end if;
 return jsonb_build_object('factory',factory,'product',case when p.id is null then null else to_jsonb(p)||jsonb_build_object('weight',p.weight::text,'length',p.length::text,'diameter',p.diameter::text,'standard_rate',p.standard_rate::text,'unit_weight_kg',p.unit_weight_kg::text)end,'fingerprint',private.product_configuration_fingerprint(factory,product),
 'recipe',(select to_jsonb(b)||jsonb_build_object('batch_quantity',b.batch_quantity::text,'components',(select jsonb_agg(to_jsonb(i)||jsonb_build_object('quantity',i.quantity::text,'waste_allowance',i.waste_allowance::text)order by material_id)from public.bom_items i where i.factory_id=factory and i.bom_id=b.id))from public.bom_versions b where factory_id=factory and product_id=coalesce(p.formula_product_id,p.length_parent_id,p.id)and output_unit='kg'order by version desc,created_at desc,id desc limit 1),
 'recipes',(select coalesce(jsonb_agg(to_jsonb(x)order by name,id),'[]')from(select p.id,p.name,p.name_ar,p.code,b.version from public.products p join lateral(select version from public.bom_versions where factory_id=factory and product_id=p.id and output_unit='kg'order by version desc limit 1)b on true where p.factory_id=factory and p.product_kind='MANUFACTURED_INTERMEDIATE'and p.stock_unit='kg')x),
 'materials',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'name_ar',name_ar,'unit',unit)order by name,id),'[]')from public.materials where factory_id=factory and unit='kg'and inventory_kind='RAW_MATERIAL'),
 'lines',(select coalesce(jsonb_agg(to_jsonb(x)order by name,id),'[]')from(select id,name,name_ar,code from public.production_lines where factory_id=factory and not archived)x),
 'machines',(select coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,'name_ar',w.name_ar,'line_id',w.line_id,'category_id',w.category_id,'category',c.name,'dependency_mode',w.dependency_mode)order by w.position,w.name,w.id),'[]')from public.work_centers w left join public.work_center_categories c on c.factory_id=w.factory_id and c.id=w.category_id where w.factory_id=factory and not w.archived and w.line_id is not null and w.type='machine'),
 'capabilities',(select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('rate',c.rate::text)order by work_center_id),'[]')from public.work_center_capabilities c where factory_id=factory and product_id=p.id),
 'input_mode',(select mode from private.production_input_routes where factory_id=factory and product_id=p.id and scope='00000000-0000-0000-0000-000000000000'),
 'stage_routes',exists(select 1 from private.production_input_routes where factory_id=factory and product_id=p.id and routing_step_id is not null),
 'shared',exists(select 1 from public.products where factory_id=factory and formula_product_id=p.id),
 'historical_weight',exists(select 1 from public.production_entries e join public.production_orders o on o.factory_id=e.factory_id and o.id=e.order_id where o.factory_id=factory and o.product_id=p.id)or exists(select 1 from public.finished_goods_movements where factory_id=factory and product_id=p.id));
end$function$;
CREATE OR REPLACE FUNCTION public.save_product_configuration(factory uuid, product uuid, payload jsonb, recipe jsonb, lines jsonb, fingerprint text, request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_variable
declare prior uuid;intent jsonb;old public.products;id uuid;part jsonb;parts jsonb;mat uuid;amount numeric;waste numeric;seen uuid[]:='{}';bom uuid;recipe_batch numeric;version integer;formula uuid;reuse boolean;mode text;line jsonb;center uuid;centers uuid[];w record;caps jsonb;basis text;weight numeric;unit_weight numeric;length numeric;body jsonb;changed boolean;begin
 perform private.require_permission(factory,'orders',case when product is null then 'create'else 'edit'end);
 if request_id is null or jsonb_typeof(payload)is distinct from 'object'or jsonb_typeof(recipe)is distinct from 'object'or(lines is not null and jsonb_typeof(lines)<>'array')or fingerprint!~'^[a-f0-9]{64}$'or fingerprint is null or octet_length(payload::text||recipe::text||coalesce(lines::text,''))>100000 then raise exception 'f45Invalid';end if;
 if exists(select 1 from jsonb_object_keys(payload)k where k not in('name','name_ar','code','category','unit','diameter','length','color','weight','standard_rate','stage','product_kind','stock_unit','unit_weight_kg','weight_basis'))or exists(select 1 from jsonb_object_keys(recipe)k where k not in('mode','formula','components','reuse','name','input_mode','batch_quantity'))then raise exception 'f45Invalid';end if;
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
  parts:=recipe->'components';recipe_batch:=coalesce((recipe->>'batch_quantity')::numeric,1);if recipe_batch<=0 or recipe_batch::text in('NaN','Infinity','-Infinity')then raise exception 'f45RecipeInvalid';end if;reuse:=coalesce((recipe->>'reuse')::boolean,false);
  if jsonb_typeof(parts)is distinct from 'array'or jsonb_array_length(parts)not between 1 and 100 then raise exception 'f45RecipeInvalid';end if;
  if reuse and payload->>'product_kind'='MANUFACTURED_INTERMEDIATE'then raise exception 'f45RecipeInvalid';end if;
  if reuse then
   formula:=public.define_manufactured_product(factory,null,jsonb_build_object('name',coalesce(nullif(btrim(recipe->>'name'),''),left(payload->>'name',100)||' recipe'),'name_ar','','code','RCP-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),'unit','kg','stock_unit','kg','product_kind','MANUFACTURED_INTERMEDIATE','stage','finished','unit_weight_kg',1),null,gen_random_uuid());
   update public.products set formula_product_id=formula where factory_id=factory and products.id=id;
  else formula:=id;end if;
  select coalesce(max(b.version),0)+1 into version from public.bom_versions b where b.factory_id=factory and b.product_id=formula;
  insert into public.bom_versions(factory_id,product_id,version,batch_quantity,output_unit,created_by)values(factory,formula,version,recipe_batch,'kg',auth.uid())returning bom_versions.id into bom;
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
end$function$;
CREATE OR REPLACE FUNCTION public.supply_page(factory uuid, mode text, page integer DEFAULT 1, filters jsonb DEFAULT '{}'::jsonb, selected uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$declare result jsonb;broad boolean;rows_data jsonb;total integer;details jsonb;begin
 perform private.require_permission(factory,'factory','view');
 if page is null or page not between 1 and 1000000 or jsonb_typeof(filters) is distinct from 'object' or octet_length(filters::text)>12000
  or exists(select 1 from jsonb_each(filters) k where k.key not in ('search','status','source_context','code','item_name','requested_by_name') or (k.key<>'status' and jsonb_typeof(k.value)<>'string') or (k.key='status' and jsonb_typeof(k.value)<>'array')) then raise exception 'supply_invalid';end if;
 if filters ? 'status' and exists(select 1 from jsonb_array_elements(filters->'status') x where jsonb_typeof(x)<>'string' or x#>>'{}' not in ('REQUESTED','UNDER_REVIEW','NEEDS_CLARIFICATION','ORDERED','READY_FOR_RECEIPT','RECEIVED','REJECTED','CANCELLED')) then raise exception 'supply_invalid';end if;
 if mode in ('purchases','mine','stock_purchases') then
  broad:=mode='stock_purchases' or (mode='purchases' and private.has_permission(factory,'purchasing','view'));
  if mode='stock_purchases' then perform private.require_permission(factory,'warehouse','view');end if;
  if mode='purchases' and not broad then raise exception 'permission_denied' using errcode='42501';end if;
  with data as materialized(select r.*,coalesce((select name from public.suppliers where factory_id=factory and id=r.supplier_id),nullif(r.supplier_text,'')) supplier_name from public.purchase_requisitions r where r.factory_id=factory and (broad or r.requested_by=auth.uid())
   and (mode<>'stock_purchases' or r.material_id is not null or r.product_id is not null or (r.source_context='Warehouse' and r.requested_by=auth.uid()))
   and (coalesce(filters->>'search','')='' or lower(r.item_name||' '||r.code||' '||r.requested_by_name||' '||r.source_context) like '%'||lower(filters->>'search')||'%')
   and (coalesce(jsonb_array_length(filters->'status'),0)=0 or filters->'status' @> jsonb_build_array(r.status))
   and (coalesce(filters->>'source_context','')='' or strpos(lower(r.source_context),lower(filters->>'source_context'))>0)
   and (coalesce(filters->>'code','')='' or strpos(lower(r.code),lower(filters->>'code'))>0)
   and (coalesce(filters->>'item_name','')='' or strpos(lower(r.item_name),lower(filters->>'item_name'))>0)
   and (coalesce(filters->>'requested_by_name','')='' or strpos(lower(r.requested_by_name),lower(filters->>'requested_by_name'))>0))
  select (select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from data order by created_at desc,id limit 50 offset (page-1)*50)x),(select count(*) from data) into rows_data,total;
  if selected is not null then
   select to_jsonb(r)||jsonb_build_object('supplier_name',coalesce((select name from public.suppliers where factory_id=factory and id=r.supplier_id),nullif(r.supplier_text,'')),'history',(select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at,e.id),'[]') from public.purchase_request_events e where not exists(select 1 from private.manufactured_outputs h where h.factory_id=e.factory_id and h.entry_id=e.id) and e.factory_id=factory and e.request_id=r.id)) into details
   from public.purchase_requisitions r where r.factory_id=factory and r.id=selected and (broad or r.requested_by=auth.uid()) and (mode<>'stock_purchases' or r.material_id is not null or r.product_id is not null or (r.source_context='Warehouse' and r.requested_by=auth.uid()));
  end if;
 elsif mode='suppliers' then
  if not private.has_permission(factory,'purchasing','view') and not private.has_permission(factory,'purchasing','edit') then perform private.require_permission(factory,'suppliers','edit');end if;
  select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('categories',(select coalesce(jsonb_agg(jsonb_build_object('name',c.name,'relationship',l.relationship)),'[]') from public.supplier_category_links l join public.supplier_categories c on c.id=l.category_id where l.factory_id=factory and l.supplier_id=x.id))),'[]') into rows_data
  from (select * from public.suppliers where factory_id=factory and strpos(lower(name),lower(coalesce(filters->>'search','')))>0 order by name,id limit 50 offset (page-1)*50)x;
  select count(*) into total from public.suppliers where factory_id=factory and strpos(lower(name),lower(coalesce(filters->>'search','')))>0;
 elsif mode='materials' then
  if not private.has_permission(factory,'warehouse','view') then perform private.require_permission(factory,'orders','view');end if;
  with data as materialized(select r.*,private.material_progress(factory,r.id)preparation,(select o.code from public.production_orders o where o.factory_id=factory and o.id=r.production_item_id)code,case when r.lot_id is not null then 'lot'when r.product_id is not null then 'product'else 'material'end item_type from public.material_requests r where r.factory_id=factory and (private.has_permission(factory,'warehouse','view') or r.requested_by=auth.uid()))
  select (select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select * from data order by created_at desc,id limit 50 offset (page-1)*50)x),(select count(*) from data) into rows_data,total;
 elsif mode in ('catalogue','lots','outputs','formulas') then
  if not private.has_permission(factory,'warehouse','view') then perform private.require_permission(factory,'orders','view');end if;
  if mode='catalogue' then
   with data as materialized(select value r from private.warehouse_inventory_rows(factory) value where coalesce(filters->>'search','')='' or strpos(lower(concat_ws(' ',value->>'name',value->>'name_ar',value->>'code')),lower(filters->>'search'))>0)
   select (select coalesce(jsonb_agg(r),'[]') from(select r from data order by r->>'name',r->>'id' limit 50 offset (page-1)*50)x),(select count(*) from data) into rows_data,total;
  elsif mode='lots' then
   with data as materialized(select l.*,p.id product_id,p.name,p.name_ar,e.unit,o.code item_code,o.request_id,
    (select code from public.production_requests where id=o.request_id) request_code,
    l.quantity_available-l.warehouse_quantity floor_quantity,
    (select coalesce(jsonb_agg(to_jsonb(m)||jsonb_build_object('actor_name',coalesce((select display_name from public.memberships where factory_id=factory and user_id=m.created_by),'')) order by m.created_at,m.id),'[]') from public.unfinished_movements m where m.factory_id=factory and m.lot_id=l.id) movements
    from public.unfinished_lots l join public.production_entries e on e.id=l.source_entry_id join public.production_orders o on o.id=e.order_id join public.products p on p.id=o.product_id
    where l.factory_id=factory and l.quantity_available>0 and (selected is null or p.id=selected))
   select (select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select * from data order by created_at,id limit 50 offset (page-1)*50)x),(select count(*) from data) into rows_data,total;
  elsif mode='outputs' then
   with data as materialized(select e.id,e.order_id,o.product_id,p.name,p.name_ar,o.code,e.unit,e.effective_good,e.created_at,exists(select 1 from private.manufactured_outputs h where h.factory_id=e.factory_id and h.entry_id=e.id) manufactured,exists(select 1 from public.production_receipt_acknowledgments where factory_id=factory and entry_id=e.id) acknowledged
    from public.production_entries e join public.production_orders o on o.id=e.order_id join public.products p on p.id=o.product_id
    where not exists(select 1 from private.manufactured_outputs h where h.factory_id=e.factory_id and h.entry_id=e.id) and e.factory_id=factory and e.effective_good>0 and exists(select 1 from public.finished_goods_entry_receipts where factory_id=factory and entry_id=e.id and received_good>0)
     and (not exists(select 1 from public.production_receipt_acknowledgments where factory_id=factory and entry_id=e.id) or exists(select 1 from public.finished_goods_sources s where s.factory_id=factory and s.entry_id=e.id and (s.quantity_credited>s.quantity_identified or s.quantity_available>0))))
   select (select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select * from data order by created_at,id limit 50 offset (page-1)*50)x),(select count(*) from data) into rows_data,total;
  else
   perform private.require_permission(factory,'orders','view');
   select coalesce(jsonb_agg(to_jsonb(m)),'[]') into rows_data from (select * from public.materials where factory_id=factory and unit='kg' and inventory_kind='RAW_MATERIAL' order by name,id limit 500)m;
   total:=jsonb_array_length(rows_data);
   if selected is not null then select to_jsonb(b)||jsonb_build_object('batch_quantity',b.batch_quantity::text,'components',(select jsonb_agg(to_jsonb(i)||jsonb_build_object('quantity',i.quantity::text,'waste_allowance',i.waste_allowance::text)) from public.bom_items i where i.factory_id=factory and i.bom_id=b.id)) into details from public.bom_versions b where b.factory_id=factory and b.product_id=selected and b.output_unit='kg' order by version desc,created_at desc,id desc limit 1;end if;
  end if;
 else raise exception 'supply_invalid';end if;
 return jsonb_build_object('rows',rows_data,'total',total,'selected',details);
end$function$;
