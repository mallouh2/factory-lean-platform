begin;
-- Extend the existing request identity; existing/manual requests remain untouched.
alter table public.material_requests alter column requested_by drop not null;
alter table public.material_requests add column automatic_requirement_key text;
create unique index material_request_automatic_identity on public.material_requests(factory_id,production_item_id,automatic_requirement_key)where automatic_requirement_key is not null;
create table private.material_preparation_jobs(factory_id uuid not null,item_id uuid not null,warning text,checked_at timestamptz not null default clock_timestamp(),primary key(factory_id,item_id),foreign key(factory_id,item_id)references public.production_orders(factory_id,id));
create table private.material_request_progress(factory_id uuid not null,request_id uuid not null,requirement jsonb not null,reserved numeric not null default 0 check(reserved>=0),issued numeric not null default 0 check(issued>=0),consumed numeric not null default 0 check(consumed>=0 and consumed<=issued),awaiting boolean not null default false,reservation_id uuid references public.inventory_reservations(id),primary key(factory_id,request_id),foreign key(factory_id,request_id)references public.material_requests(factory_id,id));
create table private.material_source_reservations(factory_id uuid not null,request_id uuid not null,source_id uuid not null,quantity numeric not null check(quantity>0),primary key(factory_id,request_id,source_id),foreign key(factory_id,request_id)references public.material_requests(factory_id,id),foreign key(factory_id,source_id)references public.finished_goods_sources(factory_id,id));
create table private.material_preparation_events(id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories(id),request_id uuid references public.material_requests(id),item_id uuid references public.production_orders(id),retry_id uuid not null,actor uuid references auth.users(id),operation text not null,intent jsonb not null,before_state jsonb,after_state jsonb not null,entry_id uuid references public.production_entries(id),created_at timestamptz not null default clock_timestamp(),unique(factory_id,retry_id));
create table private.material_preparation_acknowledgments(factory_id uuid not null,event_id uuid not null references private.material_preparation_events(id),user_id uuid not null references auth.users(id),audience text not null check(audience in('PRODUCTION','WAREHOUSE')),at timestamptz not null default clock_timestamp(),primary key(factory_id,event_id,user_id,audience));
do $$declare t text;begin foreach t in array array['material_preparation_jobs','material_request_progress','material_source_reservations','material_preparation_events','material_preparation_acknowledgments']loop execute format('alter table private.%I enable row level security',t);execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);end loop;end$$;
create trigger immutable before update or delete on private.material_preparation_events for each row execute function private.production_material_config_immutable();
create trigger immutable before update or delete on private.material_preparation_acknowledgments for each row execute function private.production_material_config_immutable();
create or replace function private.source_reserved(f uuid,s uuid,excluding uuid default null)returns numeric language sql stable security definer set search_path='' as $$select coalesce((select sum(quantity)from public.finished_goods_source_reservations where factory_id=f and source_id=s and(excluding is null or sales_line_id<>excluding)),0)+coalesce((select sum(quantity)from private.material_source_reservations where factory_id=f and source_id=s),0)$$;
create function private.material_requirement_inputs(f uuid,i uuid)returns jsonb language plpgsql stable set search_path='' as $$declare o public.production_orders;p public.products;r private.production_input_routes;b public.bom_versions;compound uuid;mass numeric;v jsonb;matches integer;begin
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
 compound:=case when r.mode='COMPOUND_MANUFACTURE'then p.id else p.formula_product_id end;
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
end$$;
create function private.material_progress(f uuid,r uuid)returns jsonb language sql stable set search_path='' as $$select to_jsonb(p)||jsonb_build_object('quantity',m.quantity::text,'unit',m.unit,'item',m.production_item_id,'name',m.item_name,'status',case when p.awaiting then 'AWAITING_RESERVATION'when p.consumed=m.quantity then 'CLOSED'when p.issued=m.quantity then 'ISSUED'when p.issued>0 then 'PARTIALLY_ISSUED'when p.reserved=m.quantity then 'RESERVED'when p.reserved>0 then 'PARTIALLY_RESERVED'else 'REQUESTED'end)from private.material_request_progress p join public.material_requests m on m.factory_id=p.factory_id and m.id=p.request_id where p.factory_id=f and p.request_id=r$$;
create function private.material_event(f uuid,r uuid,i uuid,k uuid,op text,intent jsonb,previous jsonb,entry uuid default null)returns jsonb language plpgsql set search_path='' as $$declare result jsonb;begin result:=private.material_progress(f,r);insert into private.material_preparation_events(factory_id,request_id,item_id,retry_id,actor,operation,intent,before_state,after_state,entry_id)values(f,r,i,k,auth.uid(),op,intent,previous,result,entry);return result;end$$;
-- Caller already owns the structure mutex; do not invert the factory/structure order in a Planning trigger.
create function private.release_material_preparation(f uuid,i uuid)returns void language plpgsql set search_path='' as $$declare m public.material_requests;p private.material_request_progress;begin
 for m in select *from public.material_requests where factory_id=f and production_item_id=i and status not in('CANCELLED','REJECTED')order by id for update loop
 select *into p from private.material_request_progress where factory_id=f and request_id=m.id for update;
 if not found or p.awaiting or p.issued=m.quantity then continue;end if;
 if p.reservation_id is not null then update public.inventory_reservations set released_at=clock_timestamp()where id=p.reservation_id and released_at is null;end if;
 if m.product_id is not null and p.reserved>0 then update public.finished_goods_balances set reserved=reserved-p.reserved where factory_id=f and product_id=m.product_id and unit=m.unit;delete from private.material_source_reservations where factory_id=f and request_id=m.id;end if;
 update private.material_request_progress set reserved=0,reservation_id=null,awaiting=true where factory_id=f and request_id=m.id;update public.material_requests set revision=revision+1 where id=m.id;
 perform private.material_event(f,m.id,i,gen_random_uuid(),'RELEASED','{}',to_jsonb(p));
 end loop;
end$$;
create function private.process_material_preparation(f uuid)returns jsonb language plpgsql set search_path='' as $$declare o public.production_orders;requirements jsonb;x jsonb;m public.material_requests;p private.material_request_progress;key text;manual numeric;need numeric;label text;created integer:=0;warning text;lead_seconds numeric;begin
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));perform pg_advisory_xact_lock(hashtextextended(f::text||':structure',0));select coalesce((select seconds from private.production_material_policy where factory_id=f),21600)into lead_seconds;
 for o in select *from public.production_orders where factory_id=f and status='planned'and actual_start is null and start_time is not null order by id for update loop
 if o.start_time>clock_timestamp()+lead_seconds*interval '1 second'then perform private.release_material_preparation(f,o.id);continue;end if;
 if private.output_work_held(f,o.id)then warning:='output_quality_hold';else requirements:=private.material_requirement_inputs(f,o.id);warning:=requirements->>'warning';end if;
 insert into private.material_preparation_jobs values(f,o.id,warning,clock_timestamp())on conflict(factory_id,item_id)do update set warning=excluded.warning,checked_at=excluded.checked_at;
 if warning is not null or requirements->>'existing_source_work'='true'then continue;end if;
 for x in select value from jsonb_array_elements(requirements->'inputs')loop
 key:=(x->>'kind')||':'||(x->>'id')||':'||(x->>'unit');
 select *into m from public.material_requests where factory_id=f and production_item_id=o.id and automatic_requirement_key=key;
 if found then
 select *into p from private.material_request_progress where factory_id=f and request_id=m.id;
 if p.requirement is distinct from requirements then update private.material_preparation_jobs set warning='material_requirement_review'where factory_id=f and item_id=o.id;continue;end if;
 if p.awaiting then update private.material_request_progress set awaiting=false where factory_id=f and request_id=m.id;update public.material_requests set revision=revision+1 where id=m.id;perform private.material_event(f,m.id,o.id,gen_random_uuid(),'REACTIVATED','{}',to_jsonb(p));end if;continue;
 end if;
 select coalesce(sum(quantity),0)into manual from public.material_requests where factory_id=f and production_item_id=o.id and automatic_requirement_key is null and status not in('CANCELLED','REJECTED')and unit=x->>'unit'and(case when x->>'kind'='material'then material_id=(x->>'id')::uuid else product_id=(x->>'id')::uuid end);
 need:=(x->>'quantity')::numeric-manual;if need<=0 then continue;end if;
 if x->>'kind'='material'then select name into label from public.materials where factory_id=f and id=(x->>'id')::uuid;else select name into label from public.products where factory_id=f and id=(x->>'id')::uuid;end if;
 insert into public.material_requests(factory_id,material_id,product_id,production_item_id,item_name,quantity,unit,note,requested_by,requested_by_name,automatic_requirement_key)values(f,case when x->>'kind'='material'then(x->>'id')::uuid end,case when x->>'kind'='product'then(x->>'id')::uuid end,o.id,label,need,x->>'unit','Automatic stage-specific material preparation',null,'System',key)returning *into m;
 insert into private.material_request_progress(factory_id,request_id,requirement)values(f,m.id,requirements);perform private.material_event(f,m.id,o.id,gen_random_uuid(),'REQUESTED',jsonb_build_object('source','SYSTEM'),null);created:=created+1;
 end loop;
 end loop;
 return jsonb_build_object('created',created);
end$$;
create function private.material_schedule_changed()returns trigger language plpgsql set search_path='' as $$declare seconds numeric;begin
 if new.start_time is not distinct from old.start_time and new.line_id is not distinct from old.line_id and new.status is not distinct from old.status then return new;end if;
 select coalesce((select p.seconds from private.production_material_policy p where p.factory_id=new.factory_id),21600)into seconds;
 if new.status in('completed','cancelled')or(new.status='planned'and(new.start_time is null or new.start_time>clock_timestamp()+seconds*interval '1 second'))then perform private.release_material_preparation(new.factory_id,new.id);end if;return new;
end$$;
create trigger zz_material_schedule_changed after update of start_time,line_id,status on public.production_orders for each row execute function private.material_schedule_changed();
revoke all on function private.material_requirement_inputs(uuid,uuid),private.material_progress(uuid,uuid),private.material_event(uuid,uuid,uuid,uuid,text,jsonb,jsonb,uuid),private.release_material_preparation(uuid,uuid),private.process_material_preparation(uuid),private.material_schedule_changed()from public,anon,authenticated,service_role;
commit;
