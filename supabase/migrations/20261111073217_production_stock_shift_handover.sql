-- Forward-only shared Production Stock. No historical inventory backfill.
alter table private.production_material_policy add column stock_enabled boolean not null default false,
 add column stock_activated_at timestamptz;
create table private.production_supply_requests(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories(id),
 code text not null unique,occurrence jsonb not null,note text not null default '',revision integer not null default 1,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),unique(factory_id,id));
create sequence private.production_supply_number;
create table private.production_supply_rows(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null,request_id uuid not null,material_id uuid not null,
 quantity numeric not null check(quantity>0 and quantity::text not in('NaN','Infinity','-Infinity')),
 delivered numeric not null default 0 check(delivered>=0 and delivered<=quantity),unit text not null,
 unique(factory_id,request_id,material_id),foreign key(factory_id,request_id)references private.production_supply_requests(factory_id,id),
 foreign key(factory_id,material_id)references public.materials(factory_id,id));
create table private.production_stock_movements(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories(id),material_id uuid not null,
 quantity numeric not null check(quantity<>0 and quantity::text not in('NaN','Infinity','-Infinity')),
 kind text not null check(kind in('DELIVERY','CONSUMPTION','CORRECTION','RETURN','ADJUSTMENT')),
 reference uuid not null,entry_id uuid references public.production_entries(id),evidence jsonb not null,
 actor uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 foreign key(factory_id,material_id)references public.materials(factory_id,id));
create index production_stock_material on private.production_stock_movements(factory_id,material_id);
create table private.production_stock_reservations(
 factory_id uuid not null,item_id uuid not null,occurrence_key text not null,material_id uuid not null,
 required numeric not null check(required>=0),reserved numeric not null check(reserved>=0 and reserved<=required),
 expected_output numeric not null check(expected_output>=0),evidence jsonb not null,updated_at timestamptz not null default clock_timestamp(),
 primary key(factory_id,item_id,occurrence_key,material_id),foreign key(factory_id,item_id)references public.production_orders(factory_id,id),
 foreign key(factory_id,material_id)references public.materials(factory_id,id));
create table private.production_stock_consumption(
 factory_id uuid not null,entry_id uuid not null,material_id uuid not null,quantity numeric not null check(quantity>=0),
 factor numeric not null check(factor>0),evidence jsonb not null,primary key(factory_id,entry_id,material_id),
 foreign key(factory_id,entry_id)references public.production_entries(factory_id,id),
 foreign key(factory_id,material_id)references public.materials(factory_id,id));
create table private.production_stock_orders(factory_id uuid not null,item_id uuid not null,admitted_at timestamptz not null default clock_timestamp(),
 primary key(factory_id,item_id),foreign key(factory_id,item_id)references public.production_orders(factory_id,id));
create table private.production_stock_commands(
 factory_id uuid not null references public.factories(id),retry_id uuid not null,actor uuid not null references auth.users(id),
 intent jsonb not null,result jsonb not null,created_at timestamptz not null default clock_timestamp(),primary key(factory_id,retry_id));
create table private.production_stock_events(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories(id),operation text not null,
 reference uuid,actor uuid references auth.users(id),evidence jsonb not null,created_at timestamptz not null default clock_timestamp());
create table private.production_shift_handovers(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories(id),occurrence jsonb not null,
 counts jsonb not null,note text not null,actor uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp());
create table private.production_shift_notes(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories(id),occurrence jsonb not null,
 body text not null check(length(btrim(body))between 1 and 2000),follow_up boolean not null,
 line_id uuid,machine_id uuid,item_id uuid,maintenance_request_id uuid,
 actor uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),unique(factory_id,id),
 foreign key(factory_id,line_id)references public.production_lines(factory_id,id),
 foreign key(factory_id,machine_id)references public.work_centers(factory_id,id),
 foreign key(factory_id,item_id)references public.production_orders(factory_id,id),
 foreign key(factory_id,maintenance_request_id)references public.maintenance_requests(factory_id,id));
create table private.production_shift_note_events(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null,note_id uuid not null,
 operation text not null check(operation in('ACK','RESOLVE')),body text not null default '',actor uuid not null references auth.users(id),
 created_at timestamptz not null default clock_timestamp(),foreign key(factory_id,note_id)references private.production_shift_notes(factory_id,id));
create function private.production_stock_immutable()returns trigger language plpgsql set search_path=''as $$begin raise exception 'immutable_production_stock';end$$;
revoke all on function private.production_stock_immutable()from public,anon,authenticated,service_role;
do $$declare t text;begin foreach t in array array['production_supply_requests','production_supply_rows','production_stock_movements',
 'production_stock_reservations','production_stock_consumption','production_stock_commands','production_stock_events','production_shift_handovers',
 'production_shift_notes','production_shift_note_events','production_stock_orders']loop
 execute format('alter table private.%I enable row level security',t);
 execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
 if t not in('production_supply_requests','production_supply_rows','production_stock_reservations','production_stock_consumption')then
 execute format('create trigger immutable before update or delete on private.%I for each row execute function private.production_stock_immutable()',t);end if;
 end loop;end$$;
revoke all on sequence private.production_supply_number from public,anon,authenticated,service_role;

create function private.production_stock_enabled(f uuid)returns boolean language sql stable security definer set search_path=''as $$
 select coalesce((select stock_enabled from private.production_material_policy where factory_id=f),false)$$;
revoke all on function private.production_stock_enabled(uuid)from public,anon,authenticated,service_role;

create function private.production_stock_quantity(f uuid,m uuid)returns numeric language sql stable security definer set search_path=''as $$
 select coalesce(sum(quantity),0)from private.production_stock_movements where factory_id=f and material_id=m$$;
revoke all on function private.production_stock_quantity(uuid,uuid)from public,anon,authenticated,service_role;

-- Current reservation refreshes use the original shared structure lock only.
-- Never acquire factory-after-structure from an existing Planning trigger.
create function private.production_stock_lock(f uuid)returns void language plpgsql security definer set search_path=''as $$begin
 if current_setting('transaction_isolation')not in('read committed','read uncommitted')then raise exception 'material_changed'using errcode='40001';end if;
 perform private.maintenance_planning_lock(f);end$$;
revoke all on function private.production_stock_lock(uuid)from public,anon,authenticated,service_role;

create function private.production_stock_eligible(f uuid,i uuid)returns boolean language sql stable security definer set search_path=''as $$
 select exists(select 1 from public.production_orders o,private.production_material_policy p where o.factory_id=f and o.id=i and p.factory_id=f
 and p.stock_enabled and not exists(select 1 from public.material_requests m join private.material_request_progress r on r.factory_id=m.factory_id and r.request_id=m.id
 where m.factory_id=f and m.production_item_id=i and(r.issued>0 or r.reserved>0))
 and(o.created_at>=p.stock_activated_at or exists(select 1 from private.production_stock_orders s where s.factory_id=f and s.item_id=i)
 or not exists(select 1 from public.production_entries e where e.factory_id=f and e.order_id=i)))$$;
revoke all on function private.production_stock_eligible(uuid,uuid)from public,anon,authenticated,service_role;

create function private.production_stock_forecast(f uuid,i uuid,stamp timestamptz)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare o public.production_orders;occ jsonb;resolved jsonb;req jsonb;rate numeric;fastest numeric;n integer;typed integer;
 setup integer;start_at timestamptz;end_at timestamptz;minutes numeric:=0;remaining_minutes numeric:=0;cursor_at timestamptz;
 made numeric;output numeric;remaining numeric;rows jsonb;calendar record;closing timestamptz;begin
 select *into o from public.production_orders where factory_id=f and id=i;
 if o.id is null or o.status not in('planned','active')or o.line_id is null or o.start_time is null or o.expected_finish is null then return jsonb_build_object('warning','production_stock_schedule_required');end if;
 if not private.production_stock_eligible(f,i)then return jsonb_build_object('warning','production_stock_legacy_review');end if;
 resolved:=private.resolve_production_occurrence(f,stamp);if resolved->>'available'is distinct from 'true'then return jsonb_build_object('warning','recording_shift_unavailable');end if;occ:=resolved->'occurrence';
 req:=private.material_requirement_inputs(f,i);if req->>'warning'is not null then return req;end if;
 if req->>'existing_source_work'='true'or req->>'mode'='COMPOUND_STOCK'then return jsonb_build_object('warning','production_stock_existing_source','legacy',true);end if;
 select count(*),count(*)filter(where cap.rate_unit=o.unit),min(cap.rate),max(cap.rate),max(cap.setup_minutes)
 into n,typed,rate,fastest,setup from public.work_centers c join public.work_center_capabilities cap
 on cap.factory_id=c.factory_id and cap.work_center_id=c.id and cap.product_id=o.product_id where c.factory_id=f and c.line_id=o.line_id and not c.archived;
 if n=0 or typed<>n or rate<=0 or rate<>fastest then return jsonb_build_object('warning','planning_missing_rate');end if;
 start_at:=greatest(o.start_time,(occ->>'starts_at')::timestamptz);end_at:=least(o.expected_finish,(occ->>'ends_at')::timestamptz);
 -- Use the original Planning calendar resolver and its daily closing boundary.
 -- Segment the current shift at those boundaries; never iterate minute by minute.
 select timezone,working_days_mask,workday_end into calendar from public.factories where id=f;
 cursor_at:=start_at;
 while cursor_at<end_at loop
 cursor_at:=private.next_working_start(f,cursor_at);exit when cursor_at>=end_at;
 closing:=case when calendar.working_days_mask is null then end_at else least(end_at,(((cursor_at at time zone calendar.timezone)::date)+calendar.workday_end)at time zone calendar.timezone)end;
 minutes:=minutes+extract(epoch from closing-cursor_at)/60;
 remaining_minutes:=remaining_minutes+greatest(extract(epoch from closing-greatest(cursor_at,stamp))/60,0);
 cursor_at:=closing+interval '1 minute';end loop;
 if o.start_time>=(occ->>'starts_at')::timestamptz then
 remaining_minutes:=greatest(remaining_minutes-greatest(coalesce(setup,0)-(minutes-remaining_minutes),0),0);
 minutes:=greatest(minutes-coalesce(setup,0),0);end if;
 select coalesce(sum(e.effective_good+coalesce(e.effective_unfinished,0)),0)into made from public.production_entries e
 where e.factory_id=f and e.order_id=i and(coalesce(e.effective_occurrence_key,e.original_occurrence_key)=occ->>'occurrence_key'
 or(e.original_occurrence_key is null and e.created_at>=(occ->>'starts_at')::timestamptz and e.created_at<(occ->>'ends_at')::timestamptz));
 remaining:=greatest(o.target_quantity-o.produced_quantity,0);
 output:=least(remaining,greatest(minutes*rate/60-made,0),greatest(remaining_minutes*rate/60,0));
 select coalesce(jsonb_agg(x||jsonb_build_object('quantity',trim_scale((x->>'quantity')::numeric*output/o.target_quantity)::text)),'[]')into rows from jsonb_array_elements(req->'inputs')x;
 return jsonb_build_object('occurrence',occ,'expected_output',trim_scale(output)::text,'unit',o.unit,'requirement',req,'inputs',rows,'evaluated_at',stamp);end$$;
revoke all on function private.production_stock_forecast(uuid,uuid,timestamptz)from public,anon,authenticated,service_role;

create function private.refresh_production_stock(f uuid)returns void language plpgsql security definer set search_path=''as $$
declare o record;forecast jsonb;x jsonb;needed numeric;free numeric;booked numeric;begin
 if not private.production_stock_enabled(f)then return;end if;perform private.production_stock_lock(f);
 update private.production_stock_reservations set reserved=0 where factory_id=f and reserved<>0;
 for o in select id from public.production_orders where factory_id=f and status in('active','planned')and line_id is not null and start_time is not null
 order by(status='active')desc,start_time,id loop
 forecast:=private.production_stock_forecast(f,o.id,clock_timestamp());if forecast->>'warning'is not null then continue;end if;
 insert into private.production_stock_orders(factory_id,item_id)values(f,o.id)on conflict do nothing;
 for x in select value from jsonb_array_elements(forecast->'inputs')loop
 needed:=(x->>'quantity')::numeric;
 free:=greatest(private.production_stock_quantity(f,(x->>'id')::uuid)-private.production_stock_return_pending(f,(x->>'id')::uuid)-coalesce((select sum(reserved)from private.production_stock_reservations where factory_id=f and material_id=(x->>'id')::uuid),0),0);
 booked:=least(needed,free);
 insert into private.production_stock_reservations(factory_id,item_id,occurrence_key,material_id,required,reserved,expected_output,evidence)
 values(f,o.id,forecast#>>'{occurrence,occurrence_key}',(x->>'id')::uuid,needed,booked,(forecast->>'expected_output')::numeric,forecast)
 on conflict(factory_id,item_id,occurrence_key,material_id)do update set required=excluded.required,reserved=excluded.reserved,expected_output=excluded.expected_output,evidence=excluded.evidence,updated_at=clock_timestamp();
 end loop;end loop;
 -- Reservations are a derived current projection; physical postings, confirmed
 -- requests and handover snapshots retain audit without logging every clock tick.
 end$$;
revoke all on function private.refresh_production_stock(uuid)from public,anon,authenticated,service_role;

create function private.production_stock_readiness(f uuid,i uuid)returns jsonb language plpgsql stable security definer set search_path=''as $$
declare forecast jsonb;rows jsonb;ready boolean;begin
 forecast:=private.production_stock_forecast(f,i,clock_timestamp());
 if forecast->>'warning'is not null then return jsonb_build_object('ready',false,'scope','PRODUCTION_STOCK_SHIFT','reason',forecast->>'warning','rows','[]'::jsonb);end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',r.material_id,'name',m.name,'name_ar',m.name_ar,'unit',m.unit,
 'required',trim_scale(r.required)::text,'production_held',trim_scale(r.reserved)::text,'missing',trim_scale(r.required-r.reserved)::text)order by m.name),'[]'),
 coalesce(bool_and(r.required=r.reserved),false)into rows,ready from private.production_stock_reservations r join public.materials m on m.factory_id=r.factory_id and m.id=r.material_id
 where r.factory_id=f and r.item_id=i and r.occurrence_key=forecast#>>'{occurrence,occurrence_key}';
 ready:=ready and(forecast->>'expected_output')::numeric>0;
 return jsonb_build_object('ready',ready,'scope','PRODUCTION_STOCK_SHIFT','reason',case when(forecast->>'expected_output')::numeric<=0 then 'production_stock_no_shift_output'when not ready then 'production_stock_shortage'end,
 'required_output',forecast->>'expected_output','unit',forecast->>'unit','occurrence',forecast->'occurrence','rows',rows);end$$;
revoke all on function private.production_stock_readiness(uuid,uuid)from public,anon,authenticated,service_role;

create function private.production_stock_revision(f uuid)returns text language sql stable security definer set search_path=''as $$
 select encode(sha256(convert_to(coalesce(jsonb_agg(jsonb_build_object('id',m.id,'quantity',private.production_stock_quantity(f,m.id))order by m.id),'[]')::text,'UTF8')),'hex')
 from public.materials m where m.factory_id=f and m.inventory_kind='RAW_MATERIAL'and m.unit='kg'$$;
revoke all on function private.production_stock_revision(uuid)from public,anon,authenticated,service_role;
create function public.production_stock_work(factory uuid,notes_page integer default 1,handover_page integer default 1)returns jsonb language plpgsql security definer set search_path=''as $$
declare stocks jsonb;requests jsonb;notes jsonb;handovers jsonb;occ jsonb;begin
 perform private.require_permission(factory,'factory','view');
 if notes_page not between 1 and 10000 or handover_page not between 1 and 10000 or notes_page is null or handover_page is null then raise exception 'material_invalid'using errcode='22023';end if;
 if not private.has_permission(factory,'orders','view')then perform private.require_permission(factory,'warehouse','view');end if;
 perform private.refresh_production_stock(factory);occ:=private.resolve_production_occurrence(factory,clock_timestamp());
 select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'name',m.name,'name_ar',m.name_ar,'unit',m.unit,
 'physical',trim_scale(private.production_stock_quantity(factory,m.id))::text,
 'reserved',trim_scale(private.production_stock_return_pending(factory,m.id)+coalesce((select sum(reserved)from private.production_stock_reservations where factory_id=factory and material_id=m.id),0))::text,
 'available',trim_scale(private.production_stock_quantity(factory,m.id)-private.production_stock_return_pending(factory,m.id)-coalesce((select sum(reserved)from private.production_stock_reservations where factory_id=factory and material_id=m.id),0))::text)order by m.name),'[]')into stocks
 from public.materials m where m.factory_id=factory and m.inventory_kind='RAW_MATERIAL'and m.unit='kg';
 select coalesce(jsonb_agg(x order by x->>'created_at'desc),'[]')into requests from(
 select to_jsonb(h)||jsonb_build_object('rows',(select jsonb_agg(to_jsonb(r)||jsonb_build_object('name',m.name,'name_ar',m.name_ar,'quantity',trim_scale(r.quantity)::text,'delivered',trim_scale(r.delivered)::text)order by m.name)
 from private.production_supply_rows r join public.materials m on m.factory_id=r.factory_id and m.id=r.material_id where r.factory_id=factory and r.request_id=h.id))x
 from private.production_supply_requests h where h.factory_id=factory order by h.created_at desc limit 100)t;
 select coalesce(jsonb_agg(x order by((x->>'follow_up')::boolean and not(x->>'resolved')::boolean)desc,x->>'created_at'desc),'[]')into notes from(
 select to_jsonb(n)||jsonb_build_object('acknowledgments',(select coalesce(jsonb_agg(e),'[]')from private.production_shift_note_events e where e.factory_id=factory and e.note_id=n.id),
 'resolved',exists(select 1 from private.production_shift_note_events e where e.factory_id=factory and e.note_id=n.id and e.operation='RESOLVE'))x
 from private.production_shift_notes n where n.factory_id=factory order by(n.follow_up and not exists(select 1 from private.production_shift_note_events e where e.factory_id=factory and e.note_id=n.id and e.operation='RESOLVE'))desc,n.created_at desc,n.id limit 50 offset(notes_page-1)*50)t;
 select coalesce(jsonb_agg(h order by created_at desc),'[]')into handovers from(select *from private.production_shift_handovers where factory_id=factory order by created_at desc,id limit 30 offset(handover_page-1)*30)h;
 return jsonb_build_object('enabled',private.production_stock_enabled(factory),'occurrence',occ,'stocks',stocks,'requests',requests,
 'notes',case when private.has_permission(factory,'orders','view')then notes else '[]'::jsonb end,
 'handovers',case when private.has_permission(factory,'orders','view')then handovers else '[]'::jsonb end,'stock_revision',private.production_stock_revision(factory),
 'maintenance_choices',case when private.has_permission(factory,'maintenance','view')then(select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'label',coalesce(to_jsonb(r)->>'code','')||' '||coalesce(to_jsonb(r)->>'summary',to_jsonb(r)->>'description',''))order by r.created_at desc),'[]')from public.maintenance_requests r where r.factory_id=factory)else '[]'::jsonb end,
 'notes_total',(select count(*)from private.production_shift_notes where factory_id=factory),'handovers_total',(select count(*)from private.production_shift_handovers where factory_id=factory),
 'reservations',(select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('code',o.code,'name',m.name,'unit',m.unit,'required',trim_scale(r.required)::text,'reserved',trim_scale(r.reserved)::text,'expected_output',trim_scale(r.expected_output)::text)order by o.code,m.name),'[]')from private.production_stock_reservations r join public.production_orders o on o.factory_id=r.factory_id and o.id=r.item_id join public.materials m on m.factory_id=r.factory_id and m.id=r.material_id where r.factory_id=factory and r.occurrence_key=occ#>>'{occurrence,occurrence_key}'and r.required>0),
 'deviation_percent',coalesce((select deviation_percent::text from private.production_material_policy where factory_id=factory),'0'),
 'legacy_custody',(select coalesce(sum(greatest(p.issued-p.consumed-(private.material_return_balance(factory,m.id)->>'returned')::numeric,0)),0)::text
 from public.material_requests m join private.material_request_progress p on p.factory_id=m.factory_id and p.request_id=m.id where m.factory_id=factory and m.material_id is not null and m.unit='kg'));end$$;
revoke all on function public.production_stock_work(uuid,integer,integer)from public,anon,authenticated,service_role;
grant execute on function public.production_stock_work(uuid,integer,integer)to authenticated;

create function public.production_stock_action(factory uuid,operation text,payload jsonb,request_id uuid)returns jsonb
language plpgsql security definer set search_path=''as $$
#variable_conflict use_variable
declare old private.production_stock_commands;intent jsonb:=jsonb_build_object('operation',operation,'payload',payload);result jsonb;
 occ jsonb;h private.production_supply_requests;r private.production_supply_rows;m public.materials;x jsonb;q numeric;
 id uuid:=gen_random_uuid();warehouse numeric;reserved numeric;expected numeric;delta numeric;percent numeric;threshold numeric;counts jsonb:='[]';
 significant boolean:=false;body text;ref uuid;begin
 perform private.require_permission(factory,'factory','view');
 if operation='DELIVER'then perform private.require_permission(factory,'warehouse','issue');perform private.require_permission(factory,'warehouse','view');
 elsif operation='ADJUST'then perform private.require_permission(factory,'warehouse','edit');perform private.require_permission(factory,'warehouse','view');
 elsif operation='ENABLE'then if not private.is_owner(factory)then raise exception 'permission_denied'using errcode='42501';end if;
 else perform private.require_permission(factory,'orders','view');perform private.require_permission(factory,'orders','edit');end if;
 if request_id is null or payload is null or jsonb_typeof(payload)<>'object'or octet_length(payload::text)>32000 then raise exception 'material_invalid'using errcode='22023';end if;
 perform private.production_stock_lock(factory);
 perform private.require_permission(factory,'factory','view');
 if operation='DELIVER'then perform private.require_permission(factory,'warehouse','issue');perform private.require_permission(factory,'warehouse','view');
 elsif operation='ADJUST'then perform private.require_permission(factory,'warehouse','edit');perform private.require_permission(factory,'warehouse','view');
 elsif operation='ENABLE'then if not private.is_owner(factory)then raise exception 'permission_denied'using errcode='42501';end if;
 else perform private.require_permission(factory,'orders','view');perform private.require_permission(factory,'orders','edit');end if;

 select *into old from private.production_stock_commands where factory_id=factory and retry_id=request_id;
 if found then if old.actor<>auth.uid()or old.intent<>intent then raise exception 'request_conflict'using errcode='40001';end if;return old.result;end if;
 if operation='ENABLE'then
 if payload<>'{}'::jsonb then raise exception 'material_invalid'using errcode='22023';end if;
 if exists(select 1 from public.production_orders o where o.factory_id=factory and o.status='active')then raise exception 'production_stock_legacy_review'using errcode='22023';end if;
 insert into private.production_material_policy(factory_id,seconds,stock_enabled,stock_activated_at)values(factory,21600,true,clock_timestamp())
 on conflict(factory_id)do update set stock_enabled=true,stock_activated_at=coalesce(production_material_policy.stock_activated_at,clock_timestamp());result:=jsonb_build_object('enabled',true);
 else
 if not private.production_stock_enabled(factory)then raise exception 'production_stock_disabled'using errcode='22023';end if;
 occ:=private.resolve_production_occurrence(factory,clock_timestamp());
 if operation in('REQUEST','HANDOVER','NOTE')and occ->>'available'is distinct from 'true'then raise exception 'recording_shift_unavailable'using errcode='22023';end if;
 perform private.refresh_production_stock(factory);
 if exists(select 1 from jsonb_object_keys(payload)k where k<>all(case operation
 when 'REQUEST'then array['rows','note']when 'DELIVER'then array['id','revision','rows','physical_confirmation']
 when 'ADJUST'then array['material','quantity','reason','physical_confirmation']when 'HANDOVER'then array['stock_revision','counts','note']
 when 'NOTE'then array['body','follow_up','line','machine','item','maintenance']when 'ACK'then array['id']when 'RESOLVE'then array['id','note']else array[]::text[]end))then raise exception 'material_invalid'using errcode='22023';end if;
 if operation='REQUEST'then
 if jsonb_typeof(payload->'rows')is distinct from 'array'or jsonb_array_length(payload->'rows')not between 1 and 40
 or length(coalesce(payload->>'note',''))>2000 then raise exception 'material_invalid'using errcode='22023';end if;
 if(select count(distinct d.value->>'material')from jsonb_array_elements(payload->'rows')d(value))<>jsonb_array_length(payload->'rows')then raise exception 'material_invalid'using errcode='22023';end if;
 insert into private.production_supply_requests(id,factory_id,code,occurrence,note,created_by)
 values(id,factory,'PSR-'||lpad(nextval('private.production_supply_number')::text,7,'0'),occ->'occurrence',coalesce(payload->>'note',''),auth.uid());
 for x in select value from jsonb_array_elements(payload->'rows')loop
 select *into m from public.materials where factory_id=factory and materials.id=(x->>'material')::uuid and inventory_kind='RAW_MATERIAL'and unit='kg';
 if m.id is null or coalesce(x->>'quantity','')!~'^[0-9]+([.][0-9]+)?$'then raise exception 'material_invalid'using errcode='22023';end if;
 q:=(x->>'quantity')::numeric;if q<=0 then raise exception 'material_quantity'using errcode='22023';end if;
 insert into private.production_supply_rows(factory_id,request_id,material_id,quantity,unit)values(factory,id,m.id,q,m.unit);
 end loop;result:=jsonb_build_object('id',id,'code',(select code from private.production_supply_requests where production_supply_requests.id=id));
 elsif operation='DELIVER'then
 if payload->'physical_confirmation'is distinct from 'true'::jsonb or jsonb_typeof(payload->'rows')is distinct from 'array'
 or jsonb_array_length(payload->'rows')not between 1 and 40 then raise exception 'material_invalid'using errcode='22023';end if;
 select *into h from private.production_supply_requests where factory_id=factory and production_supply_requests.id=(payload->>'id')::uuid for update;
 if h.id is null or h.revision is distinct from(payload->>'revision')::integer then raise exception 'material_changed'using errcode='40001';end if;
 if(select count(distinct d.value->>'id')from jsonb_array_elements(payload->'rows')d(value))<>jsonb_array_length(payload->'rows')then raise exception 'material_invalid'using errcode='22023';end if;
 for x in select value from jsonb_array_elements(payload->'rows')loop
 select *into r from private.production_supply_rows where factory_id=factory and production_supply_rows.id=(x->>'id')::uuid and production_supply_rows.request_id=h.id for update;
 if r.id is null or coalesce(x->>'quantity','')!~'^[0-9]+([.][0-9]+)?$'then raise exception 'material_invalid'using errcode='22023';end if;q:=(x->>'quantity')::numeric;
 if q<=0 or q>r.quantity-r.delivered then raise exception 'material_quantity'using errcode='22023';end if;
 select coalesce(sum(quantity),0)into warehouse from public.inventory_transactions where factory_id=factory and material_id=r.material_id;
 select coalesce(sum(quantity),0)into reserved from public.inventory_reservations where factory_id=factory and material_id=r.material_id and released_at is null;
 if warehouse-reserved<q then raise exception 'material_shortage'using errcode='22023';end if;
 insert into public.inventory_transactions(factory_id,material_id,quantity,kind,unit,reference,note,created_by)values(factory,r.material_id,-q,'material_issue',r.unit,h.id::text,'Independent delivery to Production Stock',auth.uid());
 insert into private.production_stock_movements(factory_id,material_id,quantity,kind,reference,evidence,actor)
 values(factory,r.material_id,q,'DELIVERY',h.id,jsonb_build_object('request',h.code,'row',r.id,'physical_confirmation',true),auth.uid());
 update private.production_supply_rows set delivered=delivered+q where production_supply_rows.id=r.id;
 end loop;update private.production_supply_requests set revision=revision+1 where production_supply_requests.id=h.id;
 result:=jsonb_build_object('id',h.id,'request',(select to_jsonb(z)||jsonb_build_object('rows',(select jsonb_agg(to_jsonb(rr)||jsonb_build_object('name',mm.name,'name_ar',mm.name_ar,'quantity',trim_scale(rr.quantity)::text,'delivered',trim_scale(rr.delivered)::text)order by mm.name)from private.production_supply_rows rr join public.materials mm on mm.factory_id=rr.factory_id and mm.id=rr.material_id where rr.factory_id=factory and rr.request_id=h.id))from private.production_supply_requests z where z.id=h.id));
 elsif operation='ADJUST'then
 body:=btrim(coalesce(payload->>'reason',''));if length(body)not between 3 and 2000 or coalesce(payload->>'quantity','')!~'^-?[0-9]+([.][0-9]+)?$'then raise exception 'material_reconciliation_reason'using errcode='22023';end if;
 select *into m from public.materials where factory_id=factory and materials.id=(payload->>'material')::uuid and inventory_kind='RAW_MATERIAL'and unit='kg';q:=(payload->>'quantity')::numeric;
 if m.id is null or q=0 or payload->'physical_confirmation'is distinct from 'true'::jsonb or private.production_stock_quantity(factory,m.id)+q<private.production_stock_return_pending(factory,m.id)+coalesce((select sum(reserved)from private.production_stock_reservations where factory_id=factory and material_id=m.id),0)then raise exception 'material_quantity'using errcode='22023';end if;
 insert into private.production_stock_movements(factory_id,material_id,quantity,kind,reference,evidence,actor)values(factory,m.id,q,'ADJUSTMENT',request_id,jsonb_build_object('reason',body,'before',private.production_stock_quantity(factory,m.id)),auth.uid());result:=jsonb_build_object('id',request_id);
 elsif operation='HANDOVER'then
 if payload->>'stock_revision'is distinct from private.production_stock_revision(factory)then raise exception 'production_stock_count_changed'using errcode='40001';end if;
 if jsonb_typeof(payload->'counts')is distinct from 'array'or jsonb_array_length(payload->'counts')>500 then raise exception 'material_invalid'using errcode='22023';end if;
 if(select count(distinct d.value->>'material')from jsonb_array_elements(payload->'counts')d(value))<>jsonb_array_length(payload->'counts')then raise exception 'material_invalid'using errcode='22023';end if;
 if exists(select 1 from public.materials mm where mm.factory_id=factory and mm.inventory_kind='RAW_MATERIAL'and mm.unit='kg'
 and not exists(select 1 from jsonb_array_elements(payload->'counts')d(value) where(d.value->>'material')::uuid=mm.id))then raise exception 'production_stock_count_required'using errcode='22023';end if;
 threshold:=coalesce((select deviation_percent from private.production_material_policy where factory_id=factory),0);
 for x in select value from jsonb_array_elements(payload->'counts')loop
 select *into m from public.materials where factory_id=factory and materials.id=(x->>'material')::uuid and inventory_kind='RAW_MATERIAL'and unit='kg';
 if m.id is null or coalesce(x->>'quantity','')!~'^[0-9]+([.][0-9]+)?$'then raise exception 'material_quantity'using errcode='22023';end if;q:=(x->>'quantity')::numeric;
 expected:=private.production_stock_quantity(factory,m.id);delta:=q-expected;percent:=case when expected<>0 then delta/expected*100 end;
 significant:=significant or delta<>0 and(expected=0 or abs(percent)>threshold);
 select coalesce(sum(reserved),0)+private.production_stock_return_pending(factory,m.id)into reserved from private.production_stock_reservations where factory_id=factory and material_id=m.id;
 counts:=counts||jsonb_build_array(jsonb_build_object('material',m.id,'name',m.name,'unit',m.unit,'expected',expected::text,'reserved',reserved::text,'unreserved',(expected-reserved)::text,'actual',q::text,'difference',delta::text,'percent',percent::text,'significant',delta<>0 and(expected=0 or abs(percent)>threshold)));
 end loop;body:=btrim(coalesce(payload->>'note',''));if length(body)>2000 or significant and length(body)<3 then raise exception 'production_stock_investigation_required'using errcode='22023';end if;
 insert into private.production_shift_handovers(id,factory_id,occurrence,counts,note,actor)values(id,factory,occ->'occurrence',counts,body,auth.uid());result:=jsonb_build_object('id',id,'counts',counts,'stock_adjusted',false);
 elsif operation='NOTE'then
 if nullif(payload->>'maintenance','')is not null then perform private.require_permission(factory,'maintenance','view');end if;
 body:=btrim(coalesce(payload->>'body',''));if length(body)not between 1 and 2000 or jsonb_typeof(payload->'follow_up')is distinct from 'boolean'then raise exception 'material_invalid'using errcode='22023';end if;
 insert into private.production_shift_notes(id,factory_id,occurrence,body,follow_up,line_id,machine_id,item_id,maintenance_request_id,actor)
 values(id,factory,occ->'occurrence',body,(payload->>'follow_up')::boolean,nullif(payload->>'line','')::uuid,nullif(payload->>'machine','')::uuid,nullif(payload->>'item','')::uuid,nullif(payload->>'maintenance','')::uuid,auth.uid());result:=jsonb_build_object('id',id);
 elsif operation in('ACK','RESOLVE')then
 ref:=(payload->>'id')::uuid;if not exists(select 1 from private.production_shift_notes where factory_id=factory and production_shift_notes.id=ref)then raise exception 'not_found'using errcode='22023';end if;
 body:=btrim(coalesce(payload->>'note',''));if length(body)>2000 or operation='RESOLVE'and length(body)<3 then raise exception 'production_stock_investigation_required'using errcode='22023';end if;
 if operation='RESOLVE'and exists(select 1 from private.production_shift_note_events where factory_id=factory and note_id=ref and production_shift_note_events.operation='RESOLVE')then raise exception 'material_changed'using errcode='40001';end if;
 if operation<>'ACK'or not exists(select 1 from private.production_shift_note_events where factory_id=factory and note_id=ref and actor=auth.uid()and production_shift_note_events.operation='ACK')then
 insert into private.production_shift_note_events(factory_id,note_id,operation,body,actor)values(factory,ref,operation,body,auth.uid());end if;result:=jsonb_build_object('id',ref);
 else raise exception 'material_invalid'using errcode='22023';end if;
 perform private.refresh_production_stock(factory);end if;
 insert into private.production_stock_commands values(factory,request_id,auth.uid(),intent,result,clock_timestamp());
 insert into private.production_stock_events(factory_id,operation,reference,actor,evidence)values(factory,operation,request_id,auth.uid(),jsonb_build_object('intent',intent,'result',result));
 return result;end$$;
revoke all on function public.production_stock_action(uuid,text,jsonb,uuid)from public,anon,authenticated,service_role;
grant execute on function public.production_stock_action(uuid,text,jsonb,uuid)to authenticated;

create function private.account_production_stock()returns trigger language plpgsql security definer set search_path=''as $$
declare job public.production_orders;req jsonb;b public.bom_versions;r record;prior private.production_stock_consumption;
 mass numeric;weight numeric;desired numeric;change numeric;others numeric;stamp timestamptz;begin
 if not private.production_stock_enabled(new.factory_id)then return new;end if;
 perform private.production_stock_lock(new.factory_id);
 select *into job from public.production_orders where factory_id=new.factory_id and id=new.order_id;
 if not exists(select 1 from private.production_stock_consumption where factory_id=new.factory_id and entry_id=new.id)then
 req:=private.material_requirement_inputs(new.factory_id,job.id);
 if req->>'existing_source_work'='true'or req->>'mode'='COMPOUND_STOCK'then return new;end if;
 end if;
 if not private.production_stock_eligible(new.factory_id,job.id)and not exists(select 1 from private.production_stock_consumption where factory_id=new.factory_id and entry_id=new.id)then
 -- Existing entries remain historical. A new late record against unreconciled
 -- legacy custody cannot silently draw from unrelated shared stock.
 if tg_op='INSERT'then raise exception 'production_stock_legacy_review'using errcode='22023';end if;return new;end if;
 -- Frozen accounting evidence survives later recipe/routing edits.
 if not exists(select 1 from private.production_stock_consumption where factory_id=new.factory_id and entry_id=new.id)then
 req:=private.material_requirement_inputs(new.factory_id,job.id);
 if req->>'existing_source_work'='true'or req->>'mode'='COMPOUND_STOCK'then return new;end if;
 if new.input_lot_id is not null then raise exception 'production_stock_legacy_review'using errcode='22023';end if;
 if req->>'warning'is not null then raise exception 'production_stock_recipe_review'using errcode='22023';end if;
 end if;
 perform private.refresh_production_stock(new.factory_id);
 select (evidence->>'weight')::numeric into weight from private.production_stock_consumption where factory_id=new.factory_id and entry_id=new.id limit 1;
 weight:=coalesce(weight,new.weight_kg_per_unit,(select case when stock_unit='kg'then 1 else unit_weight_kg end from public.products where factory_id=new.factory_id and id=job.product_id));
 if weight is null or weight<=0 then raise exception 'material_weight_missing'using errcode='22023';end if;
 -- Startup mass is already a subset of effective_scrap_kg. Discarded unit
 -- counts do not add the same Scrap mass a second time.
 mass:=(new.effective_good+coalesce(new.effective_unfinished,0))*weight+coalesce(new.effective_scrap_kg,0);
 if mass<0 then raise exception 'material_quantity'using errcode='22023';end if;
 if not exists(select 1 from private.production_stock_consumption where factory_id=new.factory_id and entry_id=new.id)then
 select *into b from public.bom_versions where factory_id=new.factory_id and id=(req->>'recipe')::uuid;
 if b.id is null then raise exception 'material_recipe_missing'using errcode='22023';end if;
 if exists(select 1 from public.bom_items bi join public.materials m on m.factory_id=bi.factory_id and m.id=bi.material_id where bi.factory_id=new.factory_id and bi.bom_id=b.id and(m.unit<>'kg'or bi.unit<>'kg'))then raise exception 'material_unit_missing'using errcode='22023';end if;
 insert into private.production_stock_consumption(factory_id,entry_id,material_id,quantity,factor,evidence)
 select new.factory_id,new.id,bi.material_id,0,sum(bi.quantity/b.batch_quantity),
 jsonb_build_object('recipe',b.id,'version',b.version,'weight',weight,'actual_scrap_replaces_allowance',true,'requirement',req)
 from public.bom_items bi where bi.factory_id=new.factory_id and bi.bom_id=b.id group by bi.material_id;
 end if;
 for prior in select *from private.production_stock_consumption where factory_id=new.factory_id and entry_id=new.id order by material_id for update loop
 desired:=mass*prior.factor;change:=desired-prior.quantity;if change=0 then continue;end if;
 select coalesce(sum(reserved),0)into others from private.production_stock_reservations where factory_id=new.factory_id and material_id=prior.material_id and item_id<>job.id;
 if change>0 and private.production_stock_quantity(new.factory_id,prior.material_id)-others-private.production_stock_return_pending(new.factory_id,prior.material_id)<change then raise exception 'production_stock_shortage'using errcode='22023';end if;
 insert into private.production_stock_movements(factory_id,material_id,quantity,kind,reference,entry_id,evidence,actor)
 values(new.factory_id,prior.material_id,-change,case when tg_op='INSERT'then 'CONSUMPTION'else 'CORRECTION'end,new.id,new.id,
 jsonb_build_object('before',prior.quantity,'after',desired,'mass',mass,'basis',prior.evidence),coalesce(auth.uid(),new.created_by));
 update private.production_stock_consumption set quantity=desired where factory_id=new.factory_id and entry_id=new.id and material_id=prior.material_id;
 end loop;
 perform private.refresh_production_stock(new.factory_id);return new;end$$;
revoke all on function private.account_production_stock()from public,anon,authenticated,service_role;
create trigger production_stock_consumption after insert or update of effective_good,effective_unfinished,effective_scrap_kg,weight_kg_per_unit
on public.production_entries for each row execute function private.account_production_stock();

-- Independent existing raw returns keep their IDs/audit and gain a shared-stock
-- source without fabricating legacy per-order provenance.
alter table private.material_returns alter column source_line_id drop not null;
alter table private.material_returns add column stock_source boolean not null default false;
alter table private.material_returns add constraint material_return_source_valid check(
 (stock_source and source_line_id is null)or(not stock_source and source_line_id is not null));
create function private.production_stock_return_pending(f uuid,m uuid)returns numeric language sql stable security definer set search_path=''as $$
 select coalesce(sum(requested-received),0)from private.material_returns where factory_id=f and material_id=m and stock_source and status in('REQUESTED','PARTIALLY_RECEIVED')$$;
revoke all on function private.production_stock_return_pending(uuid,uuid)from public,anon,authenticated,service_role;

alter function public.material_return_action(uuid,text,jsonb,uuid)rename to material_return_action_before_stock;
alter function public.material_return_action_before_stock(uuid,text,jsonb,uuid)set schema private;
revoke all on function private.material_return_action_before_stock(uuid,text,jsonb,uuid)from public,anon,authenticated,service_role;
create function public.material_return_action(factory uuid,operation text,payload jsonb,request_id uuid)returns jsonb
language plpgsql security definer set search_path=''as $$
#variable_conflict use_variable
declare h private.material_returns;old private.material_return_events;intent jsonb:=jsonb_build_object('operation',operation,'payload',payload);
 q numeric;free numeric;before_value jsonb;result jsonb;move uuid;m public.materials;begin
 perform private.require_permission(factory,'factory','view');
 if not(operation='CREATE'and payload->>'line'=factory::text)and not exists(select 1 from private.material_returns where factory_id=factory and material_returns.id=(payload->>'id')::uuid and stock_source)then
 return private.material_return_action_before_stock(factory,operation,payload,request_id);end if;
 if operation='RECEIVE'then perform private.require_permission(factory,'warehouse','view');perform private.require_permission(factory,'warehouse','issue');
 else perform private.require_permission(factory,'orders','view');perform private.require_permission(factory,'orders','edit');end if;
 if request_id is null or payload is null or jsonb_typeof(payload)<>'object'or length(coalesce(payload->>'note',''))>2000 or octet_length(payload::text)>8000 then raise exception 'material_invalid'using errcode='22023';end if;
 perform private.production_stock_lock(factory);select *into old from private.material_return_events where factory_id=factory and retry_id=request_id;
 if found then if old.actor<>auth.uid()or old.intent<>intent then raise exception 'request_conflict'using errcode='40001';end if;return old.after_state;end if;
 if operation in('CREATE','RECEIVE')then if coalesce(payload->>'quantity','')!~'^[0-9]+([.][0-9]+)?$'then raise exception 'material_quantity'using errcode='22023';end if;q:=(payload->>'quantity')::numeric;if q<=0 then raise exception 'material_quantity'using errcode='22023';end if;end if;
 if operation='CREATE'then
 if not private.production_stock_enabled(factory)or not exists(select 1 from public.factory_warehouses where factory_id=factory and id=(payload->>'warehouse')::uuid and storage_class='RAW'and active)then raise exception 'material_return_scope'using errcode='22023';end if;
 select *into m from public.materials where factory_id=factory and id=(payload->>'material')::uuid and inventory_kind='RAW_MATERIAL'and unit='kg';
 perform private.refresh_production_stock(factory);
 free:=private.production_stock_quantity(factory,m.id)-private.production_stock_return_pending(factory,m.id)-coalesce((select sum(reserved)from private.production_stock_reservations where factory_id=factory and material_id=m.id),0);
 if m.id is null or q>free then raise exception 'material_return_unavailable'using errcode='22023';end if;
 insert into private.material_returns(factory_id,material_id,unit,warehouse_id,requested,note,created_by,stock_source)
 values(factory,m.id,m.unit,(payload->>'warehouse')::uuid,q,coalesce(payload->>'note',''),auth.uid(),true)returning *into h;
 else
 select *into h from private.material_returns where factory_id=factory and id=(payload->>'id')::uuid and stock_source for update;
 if h.revision is distinct from(payload->>'revision')::integer then raise exception 'material_changed'using errcode='40001';end if;
 if h.status not in('REQUESTED','PARTIALLY_RECEIVED')then raise exception 'material_return_closed'using errcode='22023';end if;
 before_value:=private.material_return_snapshot(factory,h.id);
 if operation='CANCEL'then
 if h.created_by<>auth.uid()then raise exception 'permission_denied'using errcode='42501';end if;
 if length(btrim(coalesce(payload->>'note','')))<3 then raise exception 'material_return_reason'using errcode='22023';end if;
 update private.material_returns set status='CANCELLED',revision=revision+1 where id=h.id;
 elsif operation='RECEIVE'then
 if payload->'physical_confirmation'is distinct from 'true'::jsonb or q>h.requested-h.received or private.production_stock_quantity(factory,h.material_id)<q
 or not exists(select 1 from public.factory_warehouses where factory_id=factory and id=h.warehouse_id and storage_class='RAW'and active)then raise exception 'material_quantity'using errcode='22023';end if;
 move:=gen_random_uuid();insert into public.inventory_transactions(id,factory_id,material_id,quantity,kind,unit,reference,note,created_by)
 values(move,factory,h.material_id,q,'material_return',h.unit,h.id::text,'Independent return from shared Production Stock',auth.uid());
 insert into private.production_stock_movements(factory_id,material_id,quantity,kind,reference,evidence,actor)
 values(factory,h.material_id,-q,'RETURN',h.id,jsonb_build_object('movement',move),auth.uid());
 update private.material_returns set received=received+q,status=case when received+q=requested then 'RECEIVED'else 'PARTIALLY_RECEIVED'end,revision=revision+1 where id=h.id;
 else raise exception 'material_invalid'using errcode='22023';end if;end if;
 result:=private.material_return_snapshot(factory,h.id);
 insert into private.material_return_events(factory_id,return_id,retry_id,actor,operation,intent,before_state,after_state,movement_id)
 values(factory,h.id,request_id,auth.uid(),operation,intent,before_value,result,move);
 perform private.refresh_production_stock(factory);return result;end$$;
revoke all on function public.material_return_action(uuid,text,jsonb,uuid)from public,anon,authenticated,service_role;
grant execute on function public.material_return_action(uuid,text,jsonb,uuid)to authenticated;




create function public.production_stock_requests(factory uuid,page integer default 1)returns jsonb language plpgsql security definer set search_path=''as $$
declare rows jsonb;total bigint;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'warehouse','view');
 if page is null or page not between 1 and 10000 then raise exception 'material_invalid'using errcode='22023';end if;
 select count(*)into total from private.production_supply_requests h where h.factory_id=factory and exists(select 1 from private.production_supply_rows r where r.factory_id=factory and r.request_id=h.id and r.delivered<r.quantity);
 select coalesce(jsonb_agg(x order by x->>'created_at',x->>'id'),'[]')into rows from(
 select to_jsonb(h)||jsonb_build_object('rows',(select jsonb_agg(to_jsonb(r)||jsonb_build_object('name',m.name,'name_ar',m.name_ar,'quantity',trim_scale(r.quantity)::text,'delivered',trim_scale(r.delivered)::text)order by m.name)
 from private.production_supply_rows r join public.materials m on m.factory_id=r.factory_id and m.id=r.material_id where r.factory_id=factory and r.request_id=h.id))x
 from private.production_supply_requests h where h.factory_id=factory and exists(select 1 from private.production_supply_rows r where r.factory_id=factory and r.request_id=h.id and r.delivered<r.quantity)
 order by h.created_at,h.id limit 50 offset(page-1)*50)t;
 return jsonb_build_object('rows',rows,'total',total);end$$;
revoke all on function public.production_stock_requests(uuid,integer)from public,anon,authenticated,service_role;
grant execute on function public.production_stock_requests(uuid,integer)to authenticated;

-- Existing context mutations refresh their derived reservations in the same
-- transaction. Shift rollover is additionally resolved on every admission/write.
create function private.refresh_production_stock_context()returns trigger language plpgsql security definer set search_path=''as $$begin
 perform private.refresh_production_stock(coalesce(new.factory_id,old.factory_id));return null;end$$;
revoke all on function private.refresh_production_stock_context()from public,anon,authenticated,service_role;
create trigger production_stock_schedule after insert or update of status,line_id,start_time,expected_finish,target_quantity,product_id on public.production_orders
for each row execute function private.refresh_production_stock_context();
create trigger production_stock_shift after insert on private.production_shift_schedule_revisions for each row execute function private.refresh_production_stock_context();
create trigger production_stock_route after insert or update or delete on private.production_input_routes for each row execute function private.refresh_production_stock_context();
create trigger production_stock_bom after insert or update or delete on public.bom_items for each row execute function private.refresh_production_stock_context();
create trigger production_stock_product after update of unit_weight_kg,formula_product_id on public.products for each row execute function private.refresh_production_stock_context();
create trigger production_stock_capability after insert or update or delete on public.work_center_capabilities for each row execute function private.refresh_production_stock_context();



-- Existing contract adapters.
alter function private.material_start_readiness(uuid,uuid)rename to material_start_readiness_before_stock;
revoke all on function private.material_start_readiness_before_stock(uuid,uuid)from public,anon,authenticated,service_role;
create function private.material_start_readiness(f uuid,i uuid)returns jsonb language plpgsql stable security definer set search_path=''as $$declare req jsonb;begin
if not private.production_stock_enabled(f)then return private.material_start_readiness_before_stock(f,i);end if;
req:=private.material_requirement_inputs(f,i);if req->>'existing_source_work'='true'or req->>'mode'='COMPOUND_STOCK'then return private.material_start_readiness_before_stock(f,i);end if;
return private.production_stock_readiness(f,i);end$$;
revoke all on function private.material_start_readiness(uuid,uuid)from public,anon,authenticated,service_role;
alter function public.material_return_context(uuid)rename to material_return_context_before_stock;
alter function public.material_return_context_before_stock(uuid)set schema private;
revoke all on function private.material_return_context_before_stock(uuid)from public,anon,authenticated,service_role;
create function public.material_return_context(factory uuid)returns jsonb language plpgsql security definer set search_path=''as $$declare legacy jsonb;extra jsonb;begin
legacy:=private.material_return_context_before_stock(factory);perform private.refresh_production_stock(factory);
select coalesce(jsonb_agg(jsonb_build_object('material',m.id,'name',m.name,'name_ar',m.name_ar,'unit',m.unit,'line',factory,'line_name','Production Stock','line_name_ar','مخزون الإنتاج',
'available',trim_scale(private.production_stock_quantity(factory,m.id)-private.production_stock_return_pending(factory,m.id)-coalesce((select sum(reserved)from private.production_stock_reservations where factory_id=factory and material_id=m.id),0))::text)),'[]')into extra
from public.materials m where m.factory_id=factory and m.inventory_kind='RAW_MATERIAL'and m.unit='kg'and private.production_stock_enabled(factory)
and private.production_stock_quantity(factory,m.id)-private.production_stock_return_pending(factory,m.id)-coalesce((select sum(reserved)from private.production_stock_reservations where factory_id=factory and material_id=m.id),0)>0;
return legacy||jsonb_build_object('rows',(legacy->'rows')||extra);end$$;
revoke all on function public.material_return_context(uuid)from public,anon,authenticated,service_role;grant execute on function public.material_return_context(uuid)to authenticated;
CREATE OR REPLACE FUNCTION private.material_return_snapshot(f uuid, r uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select to_jsonb(h)||jsonb_build_object('name',m.name,'name_ar',m.name_ar,'source_name',case when h.stock_source then 'Production Stock'else l.name end,'source_name_ar',case when h.stock_source then 'مخزون الإنتاج'else l.name_ar end,'warehouse_name',w.name,'warehouse_name_ar',w.name_ar,
 'outstanding',trim_scale(case when h.status='CANCELLED'then 0 else h.requested-h.received end)::text,
 'allocations',(select coalesce(jsonb_agg(jsonb_build_object('request',a.material_request_id,'item',o.id,'code',o.code,'issued_at',mr.issued_at,'quantity',trim_scale(a.quantity)::text,'received',trim_scale(a.received)::text)order by o.code,a.material_request_id),'[]')from private.material_return_allocations a join public.material_requests mr on mr.factory_id=a.factory_id and mr.id=a.material_request_id join public.production_orders o on o.factory_id=mr.factory_id and o.id=mr.production_item_id where a.factory_id=f and a.return_id=r))
 from private.material_returns h join public.materials m on m.factory_id=h.factory_id and m.id=h.material_id left join public.production_lines l on l.factory_id=h.factory_id and l.id=h.source_line_id join public.factory_warehouses w on w.factory_id=h.factory_id and w.id=h.warehouse_id where h.factory_id=f and h.id=r
$function$;
CREATE OR REPLACE FUNCTION private.material_start_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare readiness jsonb;begin
 if new.status='active'and(old.status is distinct from 'active'or old.actual_start is null and new.actual_start is not null)then
 if current_setting('transaction_isolation') not in('read committed','read uncommitted')then raise exception 'execution_readiness_stale'using errcode='40001';end if;
 perform private.require_permission(new.factory_id,'orders','edit');
 perform pg_advisory_xact_lock(hashtextextended(new.factory_id::text,0));perform private.maintenance_planning_lock(new.factory_id);
 if row(new.product_id,new.unit,new.target_quantity,new.request_id)is distinct from row(old.product_id,old.unit,old.target_quantity,old.request_id)then raise exception 'execution_use_command';end if;
 perform private.refresh_production_stock(new.factory_id);
 readiness:=private.material_start_readiness(new.factory_id,new.id);
 if not coalesce((readiness->>'ready')::boolean,false)then raise exception 'production_material_not_ready'using errcode='22023',detail=readiness::text;end if;
 end if;return new;end$function$;
CREATE OR REPLACE FUNCTION public.production_start_readiness(factory uuid, item uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.production_orders;physical jsonb;hold jsonb;blocker jsonb;stamp timestamptz;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'orders','view');perform private.refresh_production_stock(factory);
 select * into o from public.production_orders where factory_id=factory and id=item;
 if not found then raise exception 'not_found' using errcode='P0002';end if;
 physical:=private.maintenance_execution_readiness(factory,o.id,o.line_id,o.product_id);
 if coalesce((physical->>'ready')::boolean,true)then physical:=private.execution_machine_readiness(factory,o.id,o.line_id,o.product_id);end if;
 stamp:=clock_timestamp();
 -- This is current maintenance occupancy, not a new duration/calendar engine.
 -- The original Start trigger still checks both plan and intended execution span.
 hold:=private.maintenance_capacity_conflict(factory,o.line_id,o.product_id,null,stamp,stamp+interval '1 microsecond',null,o.id,false);
 if hold is not null then
 select jsonb_build_object('reason','MAINTENANCE_HOLD','machine',jsonb_build_object('id',c.id,'code',c.code,'name',c.name,'name_ar',c.name_ar,'status',c.status))
 into blocker from public.maintenance_schedule_resources r join public.work_centers c on c.factory_id=r.factory_id and c.id=r.machine_id
 where r.factory_id=factory and r.schedule_id=(hold->>'schedule')::uuid and r.resource_kind='MACHINE' order by c.id limit 1;
 end if;
 return jsonb_build_object('factory',factory,'item',item,'physical',physical,'materials',private.material_start_readiness(factory,item),'maintenance_block',blocker,
 'quality_hold',private.output_work_held(factory,item),'evaluated_at',stamp,'queue_ready',coalesce(o.status='planned' and o.actual_start is null and o.actual_finish is null
 and o.start_time is not null and o.expected_finish>o.start_time
 and not exists(select 1 from public.production_orders x where x.factory_id=factory and x.line_id=o.line_id and x.status='active')
 and o.id=(select x.id from public.production_orders x where x.factory_id=factory and x.line_id=o.line_id and x.status='planned'
 and x.actual_start is null and x.actual_finish is null and x.start_time is not null and x.expected_finish>x.start_time order by x.start_time,x.id limit 1),false));
end$function$;
CREATE OR REPLACE FUNCTION private.reconcile_material_item(f uuid, i uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare o public.production_orders;requirements jsonb;x jsonb;m public.material_requests;p private.material_request_progress;key text;manual numeric;need numeric;label text;created integer:=0;warning text;lead_seconds numeric;
begin
 if private.production_stock_enabled(f)and private.production_stock_eligible(f,i)and coalesce(private.material_requirement_inputs(f,i)->>'mode','')not in('COMPOUND_STOCK')then return 0;end if;
 select *into o from public.production_orders where factory_id=f and id=i for update;if not found then return 0;end if;
 select coalesce((select seconds from private.production_material_policy where factory_id=f),21600)into lead_seconds;
 if o.status in('completed','cancelled')or(o.status='planned'and(o.start_time is null or o.start_time>clock_timestamp()+lead_seconds*interval '1 second'))then perform private.release_material_preparation(f,i);insert into private.material_preparation_jobs values(f,i,null,clock_timestamp())on conflict(factory_id,item_id)do update set warning=null,checked_at=excluded.checked_at;return 0;end if;
 if o.status='active'and o.actual_start is not null and o.actual_finish is null then
 requirements:=private.material_requirement_inputs(f,i);warning:=requirements->>'warning';
 if private.output_work_held(f,i)then warning:='output_quality_hold';end if;
 if exists(select 1 from public.material_requests r join private.material_request_progress mp on mp.factory_id=r.factory_id and mp.request_id=r.id where r.factory_id=f and r.production_item_id=i and r.automatic_requirement_key is not null and r.status not in('CANCELLED','REJECTED')and mp.requirement is distinct from requirements)then warning:='material_requirement_review';end if;
 insert into private.material_preparation_jobs values(f,i,warning,clock_timestamp())on conflict(factory_id,item_id)do update set warning=excluded.warning,checked_at=excluded.checked_at;
 if warning is not null then return 0;end if;
 for m in select r.*from public.material_requests r join private.material_request_progress mp on mp.factory_id=r.factory_id and mp.request_id=r.id where r.factory_id=f and r.production_item_id=i and r.status not in('CANCELLED','REJECTED')and mp.awaiting loop
 select *into p from private.material_request_progress where factory_id=f and request_id=m.id;update private.material_request_progress set awaiting=false where factory_id=f and request_id=m.id;update public.material_requests set revision=revision+1 where id=m.id;perform private.material_event(f,m.id,i,gen_random_uuid(),'REACTIVATED','{}',to_jsonb(p));end loop;
 return 0;end if;
 if o.status<>'planned'or o.actual_start is not null then return 0;end if;
 for m in select r.*from public.material_requests r join private.material_request_progress mp on mp.factory_id=r.factory_id and mp.request_id=r.id where r.factory_id=f and r.production_item_id=i and r.automatic_requirement_key is null and r.status not in('CANCELLED','REJECTED')and mp.awaiting loop
 select *into p from private.material_request_progress where factory_id=f and request_id=m.id;update private.material_request_progress set awaiting=false where factory_id=f and request_id=m.id;update public.material_requests set revision=revision+1 where id=m.id;perform private.material_event(f,m.id,i,gen_random_uuid(),'REACTIVATED','{}',to_jsonb(p));end loop;
 requirements:=private.material_requirement_inputs(f,i);warning:=requirements->>'warning';if private.output_work_held(f,i)then warning:='output_quality_hold';end if;
 -- Validate the whole stage before creating any part of a requirement.
 if warning is null and requirements->>'existing_source_work'is distinct from 'true'then
 for m in select *from public.material_requests where factory_id=f and production_item_id=i and automatic_requirement_key is not null loop
 select *into p from private.material_request_progress where factory_id=f and request_id=m.id;
 if p.requirement is distinct from requirements or m.status in('CANCELLED','REJECTED')then warning:='material_requirement_review';exit;end if;
 end loop;
 for x in select value from jsonb_array_elements(requirements->'inputs')loop
 key:=(x->>'kind')||':'||(x->>'id')||':'||(x->>'unit');
 select coalesce(sum(quantity),0)into manual from public.material_requests where factory_id=f and production_item_id=i and automatic_requirement_key is null and status not in('CANCELLED','REJECTED')and unit=x->>'unit'and(case when x->>'kind'='material'then material_id=(x->>'id')::uuid else product_id=(x->>'id')::uuid end);
 select *into m from public.material_requests where factory_id=f and production_item_id=i and automatic_requirement_key=key;
 if manual>(x->>'quantity')::numeric or(m.id is not null and m.quantity+manual<>(x->>'quantity')::numeric)then warning:='material_requirement_review';end if;
 end loop;end if;
 insert into private.material_preparation_jobs values(f,i,warning,clock_timestamp())on conflict(factory_id,item_id)do update set warning=excluded.warning,checked_at=excluded.checked_at;
 if warning is not null or requirements->>'existing_source_work'='true'then return 0;end if;
 for x in select value from jsonb_array_elements(requirements->'inputs')loop
 key:=(x->>'kind')||':'||(x->>'id')||':'||(x->>'unit');select *into m from public.material_requests where factory_id=f and production_item_id=i and automatic_requirement_key=key;
 if found then select *into p from private.material_request_progress where factory_id=f and request_id=m.id;if p.awaiting then
 update private.material_request_progress set awaiting=false where factory_id=f and request_id=m.id;update public.material_requests set revision=revision+1 where id=m.id;perform private.material_event(f,m.id,i,gen_random_uuid(),'REACTIVATED','{}',to_jsonb(p));end if;continue;end if;
 select coalesce(sum(quantity),0)into manual from public.material_requests where factory_id=f and production_item_id=i and automatic_requirement_key is null and status not in('CANCELLED','REJECTED')and unit=x->>'unit'and(case when x->>'kind'='material'then material_id=(x->>'id')::uuid else product_id=(x->>'id')::uuid end);
 need:=(x->>'quantity')::numeric-manual;if need<=0 then continue;end if;
 if x->>'kind'='material'then select name into label from public.materials where factory_id=f and id=(x->>'id')::uuid;else select name into label from public.products where factory_id=f and id=(x->>'id')::uuid;end if;
 insert into public.material_requests(factory_id,material_id,product_id,production_item_id,item_name,quantity,unit,note,requested_by,requested_by_name,automatic_requirement_key)values(f,case when x->>'kind'='material'then(x->>'id')::uuid end,case when x->>'kind'='product'then(x->>'id')::uuid end,i,label,need,x->>'unit','Automatic stage-specific material preparation',null,'System',key)returning *into m;
 insert into private.material_request_progress(factory_id,request_id,requirement)values(f,m.id,requirements);perform private.material_event(f,m.id,i,gen_random_uuid(),'REQUESTED',jsonb_build_object('source','SYSTEM'),null);created:=created+1;
 end loop;return created;end$function$;
CREATE OR REPLACE FUNCTION private.process_material_preparation(f uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$declare i uuid;n integer:=0;begin
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));perform pg_advisory_xact_lock(hashtextextended(f::text||':structure',0));
 perform private.refresh_production_stock(f);
 for i in select o.id from public.production_orders o left join private.material_preparation_jobs j on j.factory_id=o.factory_id and j.item_id=o.id where o.factory_id=f and o.status='planned'and o.actual_start is null and o.start_time is not null order by j.checked_at nulls first,o.id limit 200 loop n:=n+private.reconcile_material_item(f,i);end loop;return jsonb_build_object('created',n);end$function$;
