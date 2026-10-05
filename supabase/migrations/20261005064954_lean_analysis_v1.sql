-- Lean extends existing loss, cause, recording and Audit truth. No historical units are inferred.
insert into public.permissions(module,action) values
 ('lean','view'),('lean','create'),('lean','edit'),('lean','approve'),('lean_standards','edit') on conflict do nothing;

-- Lean V1 explicitly replaces the frozen seven-cause catalogue with an editable library.
create or replace function private.guard_current_downtime_catalog() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='DELETE' then raise exception 'lean_cause_history';end if;
 if length(btrim(new.name)) not between 1 and 120 or length(coalesce(new.name_ar,''))>120 then raise exception 'lean_invalid';end if;
 if tg_op='UPDATE' and (new.id<>old.id or new.factory_id<>old.factory_id) then raise exception 'lean_invalid';end if;
 return new;
end$$;
create or replace function private.current_downtime_reason(f uuid,reason uuid) returns boolean language sql stable set search_path='' as $$
 select exists(select 1 from public.downtime_reasons where factory_id=f and id=reason)
$$;
revoke insert,update,delete on public.downtime_reasons from anon,authenticated;
do $$declare definition text;begin
 definition:=pg_get_functiondef('private.save_record(uuid,text,uuid,jsonb)'::regprocedure);
 if position('action:=case when record_id is null' in definition)=0 then raise exception 'lean_crud_changed';end if;
 execute replace(definition,'action:=case when record_id is null','if resource=''downtime'' then perform private.require_permission(f,''lean'',''edit'');end if; action:=case when record_id is null');
end$$;
alter table public.downtime_events add column lean_shift_id uuid;
create function private.lean_stop_shift() returns trigger language plpgsql security definer set search_path='' as $$begin
 new.lean_shift_id:=private.resolve_factory_shift(new.factory_id,new.started_at);return new;
end$$;
revoke all on function private.lean_stop_shift() from public,anon,authenticated;
create trigger lean_stop_shift before insert on public.downtime_events for each row execute function private.lean_stop_shift();

create table public.lean_standards (
 id uuid primary key default gen_random_uuid(),factory_id uuid not null,line_id uuid not null,product_id uuid not null,
 running_percent numeric check(running_percent>=0 and running_percent::text not in ('NaN','Infinity','-Infinity')),
 startup_kg numeric check(startup_kg>=0 and startup_kg::text not in ('NaN','Infinity','-Infinity')),
 revision integer not null default 1,created_by uuid references auth.users,created_at timestamptz not null default now(),
 approved_proposal_month date,approved_observed_kg numeric,
 unique(factory_id,id),unique(factory_id,line_id,product_id),
 foreign key(factory_id,line_id) references public.production_lines(factory_id,id),
 foreign key(factory_id,product_id) references public.products(factory_id,id)
);
create table public.lean_startups (
 id uuid primary key,factory_id uuid not null,line_id uuid not null,item_id uuid not null,product_id uuid not null,
 occurred_at timestamptz not null,standard_kg numeric,standard_revision integer,
 created_by uuid not null references auth.users,created_at timestamptz not null default now(),
 unique(factory_id,id),foreign key(factory_id,line_id) references public.production_lines(factory_id,id),
 foreign key(factory_id,item_id) references public.production_orders(factory_id,id),
 foreign key(factory_id,product_id) references public.products(factory_id,id)
);
alter table public.production_entries
 add column original_scrap_kg numeric check(original_scrap_kg>=0),
 add column effective_scrap_kg numeric check(effective_scrap_kg>=0),
 add column original_startup_kg numeric check(original_startup_kg>=0),
 add column effective_startup_kg numeric check(effective_startup_kg>=0),
 add column weight_kg_per_unit numeric check(weight_kg_per_unit>0),
 add column produced_weight_kg numeric check(produced_weight_kg>=0),
 add column lean_startup_id uuid,
 add column running_standard_percent numeric,
 add column scrap_standard_revision integer,
 add foreign key(factory_id,lean_startup_id) references public.lean_startups(factory_id,id);
alter table public.production_entry_corrections
 add column previous_scrap_kg numeric,add column corrected_scrap_kg numeric,
 add column previous_startup_kg numeric,add column corrected_startup_kg numeric;

-- A review is tied to existing physical evidence; a downtime-linked scrap review is one event.
create table public.lean_scrap_events (
 id uuid primary key,factory_id uuid not null,entry_id uuid not null,line_id uuid not null,product_id uuid not null,
 downtime_id uuid,occurred_at timestamptz not null,preliminary_cause_id uuid,
 observation text not null check(length(btrim(observation)) between 3 and 2000),
 response text not null check(length(btrim(response)) between 3 and 2000),
 approved_cause_id uuid,engineering_note text not null default '',reviewed_by uuid references auth.users,reviewed_at timestamptz,
 created_by uuid not null references auth.users,created_at timestamptz not null default now(),revision integer not null default 1,
 unique(factory_id,id),unique(factory_id,entry_id),
 foreign key(factory_id,entry_id) references public.production_entries(factory_id,id),
 foreign key(factory_id,line_id) references public.production_lines(factory_id,id),
 foreign key(factory_id,product_id) references public.products(factory_id,id),
 foreign key(factory_id,downtime_id) references public.downtime_events(factory_id,id),
 foreign key(factory_id,preliminary_cause_id) references public.downtime_reasons(factory_id,id),
 foreign key(factory_id,approved_cause_id) references public.downtime_reasons(factory_id,id),
 check((approved_cause_id is null and reviewed_at is null and reviewed_by is null) or
 (approved_cause_id is not null and reviewed_at is not null and reviewed_by is not null))
);
create table public.lean_problem_settings (
 id uuid primary key default gen_random_uuid(),factory_id uuid not null,mechanism text not null check(mechanism in ('downtime','scrap')),
 machine_id uuid,line_id uuid,product_id uuid,cause_id uuid not null,monitor_only boolean not null default false,
 threshold_percent numeric not null default 10 check(threshold_percent>=0 and threshold_percent<=100),
 revision integer not null default 1,created_by uuid references auth.users,created_at timestamptz not null default now(),
 unique(factory_id,id),
 check((mechanism='downtime' and machine_id is not null and line_id is null and product_id is null)
 or (mechanism='scrap' and machine_id is null and line_id is not null and product_id is not null)),
 foreign key(factory_id,machine_id) references public.work_centers(factory_id,id),
 foreign key(factory_id,line_id) references public.production_lines(factory_id,id),
 foreign key(factory_id,product_id) references public.products(factory_id,id),
 foreign key(factory_id,cause_id) references public.downtime_reasons(factory_id,id)
);
create unique index lean_problem_identity on public.lean_problem_settings(factory_id,mechanism,
 coalesce(machine_id,'00000000-0000-0000-0000-000000000000'::uuid),coalesce(line_id,'00000000-0000-0000-0000-000000000000'::uuid),
 coalesce(product_id,'00000000-0000-0000-0000-000000000000'::uuid),cause_id);
create table public.lean_initiatives (
 id uuid primary key,factory_id uuid not null,problem_id uuid not null,product_id uuid not null,
 title text not null check(length(btrim(title)) between 3 and 200),
 baseline_from timestamptz not null,baseline_to timestamptz not null,baseline_hours numeric check(baseline_hours>0),baseline_evidence jsonb,
 completed_at timestamptz,verified_at timestamptz,verified_by uuid references auth.users,
 outcome text check(outcome in ('IMPROVED','NO_MEANINGFUL_CHANGE','WORSE','INSUFFICIENT_DATA')),
 verification_note text,verification_evidence jsonb,
 revision integer not null default 1,created_by uuid not null references auth.users,created_at timestamptz not null default now(),
 unique(factory_id,id),foreign key(factory_id,problem_id) references public.lean_problem_settings(factory_id,id),
 foreign key(factory_id,product_id) references public.products(factory_id,id),check(baseline_to>baseline_from),
 check((verified_at is null and verified_by is null and outcome is null) or
 (verified_at is not null and verified_by is not null and outcome is not null and completed_at is not null))
);
create unique index lean_one_active_initiative on public.lean_initiatives(factory_id,problem_id) where verified_at is null;
create table public.lean_actions (
 id uuid primary key,factory_id uuid not null,initiative_id uuid not null,
 title text not null check(length(btrim(title)) between 3 and 200),description text not null default '' check(length(description)<=2000),
 action_type text not null check(action_type in ('MAINTENANCE','PROCESS','QUALITY','MATERIAL','TRAINING','SETUP','OTHER')),
 owner_id uuid not null,due_date date not null,status text not null default 'OPEN' check(status in ('OPEN','IN_PROGRESS','COMPLETED','CANCELLED')),
 cancellation_reason text,progress_note text not null default '',revision integer not null default 1,
 created_by uuid not null references auth.users,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(factory_id,id),foreign key(factory_id,initiative_id) references public.lean_initiatives(factory_id,id),
 foreign key(factory_id,owner_id) references public.memberships(factory_id,user_id),
 check(status<>'CANCELLED' or length(btrim(cancellation_reason))>=3)
);
create index lean_actions_initiative on public.lean_actions(factory_id,initiative_id,status);
create table public.lean_action_templates (
 id uuid primary key,factory_id uuid not null,cause_id uuid,title text not null check(length(btrim(title)) between 3 and 200),
 description text not null default '' check(length(description)<=2000),name_ar text not null default '',
 action_type text not null check(action_type in ('MAINTENANCE','PROCESS','QUALITY','MATERIAL','TRAINING','SETUP','OTHER')),
 due_days integer check(due_days between 1 and 3650),archived boolean not null default false,revision integer not null default 1,
 created_by uuid references auth.users,created_at timestamptz not null default now(),unique(factory_id,id),
 foreign key(factory_id,cause_id) references public.downtime_reasons(factory_id,id)
);
create table public.lean_saved_comparisons (
 id uuid primary key,factory_id uuid not null,problem_id uuid not null,product_id uuid not null,cutoff timestamptz not null,
 desired_hours numeric not null check(desired_hours>0),evidence jsonb not null,
 created_by uuid not null references auth.users,created_at timestamptz not null default now(),unique(factory_id,id),
 foreign key(factory_id,problem_id) references public.lean_problem_settings(factory_id,id),
 foreign key(factory_id,product_id) references public.products(factory_id,id)
);
-- Authoritative state checkpoints permit equal-runtime analysis with evaluateFlow. No old history is fabricated.
create table public.lean_runtime_contexts (
 id bigint generated always as identity primary key,factory_id uuid not null references public.factories,
 captured_at timestamptz not null default statement_timestamp(),context jsonb not null
);
create index lean_runtime_factory_time on public.lean_runtime_contexts(factory_id,captured_at,id);
create index lean_scrap_factory_time on public.lean_scrap_events(factory_id,occurred_at,id);

do $$declare tab text;begin
 foreach tab in array array['lean_standards','lean_startups','lean_scrap_events','lean_problem_settings','lean_initiatives','lean_actions','lean_action_templates','lean_saved_comparisons','lean_runtime_contexts'] loop
  execute format('alter table public.%I enable row level security',tab);
  execute format('revoke all on public.%I from anon,authenticated',tab);
  execute format('create policy lean_read on public.%I for select to authenticated using (private.has_permission(factory_id,''lean'',''view''))',tab);
  execute format('grant select on public.%I to authenticated',tab);
  if tab<>'lean_runtime_contexts' then execute format('create trigger lean_audit after insert or update or delete on public.%I for each row execute function private.audit_change()',tab);end if;
 end loop;
end$$;

create function private.capture_lean_runtime(f uuid) returns void language sql security definer set search_path='' as $$
 insert into public.lean_runtime_contexts(factory_id,context) select f,jsonb_build_object(
 'centers',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.work_centers x where x.factory_id=f),
 'stops',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.downtime_events x where x.factory_id=f and x.ended_at is null),
 'transfers',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.production_transfers x where x.factory_id=f and x.ended_at is null),
 'orders',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.production_orders x where x.factory_id=f and x.status='active'),
 'lines',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.production_lines x where x.factory_id=f),
 'shifts',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.production_shifts x where x.factory_id=f),
 'timezone',(select timezone from public.factories where id=f))
$$;
revoke all on function private.capture_lean_runtime(uuid) from public,anon,authenticated;
create function private.lean_runtime_changed() returns trigger language plpgsql security definer set search_path='' as $$begin
 perform private.capture_lean_runtime(coalesce(new.factory_id,old.factory_id));return null;end$$;
revoke all on function private.lean_runtime_changed() from public,anon,authenticated;
create trigger lean_runtime_center after insert or delete or update of status,line_id,archived,dependency_mode,buffer_minutes,impact_scope,order_id,position on public.work_centers for each row execute function private.lean_runtime_changed();
create trigger lean_runtime_order after insert or delete or update of status,actual_start,actual_finish,line_id,product_id on public.production_orders for each row execute function private.lean_runtime_changed();
create trigger lean_runtime_line after insert or delete or update of paused_at,archived on public.production_lines for each row execute function private.lean_runtime_changed();
create trigger lean_runtime_transfer after insert or delete or update of ended_at on public.production_transfers for each row execute function private.lean_runtime_changed();
create trigger lean_runtime_stop after insert or delete or update of ended_at on public.downtime_events for each row execute function private.lean_runtime_changed();
create trigger lean_runtime_shift after insert or delete or update on public.production_shifts for each row execute function private.lean_runtime_changed();
do $$declare f uuid;begin for f in select id from public.factories loop perform private.capture_lean_runtime(f);end loop;end$$;

-- Shared causes stay in the existing approved-cause library, never inferred from operator text.
create function private.seed_lean_defaults(f uuid) returns void language plpgsql security definer set search_path='' as $$declare item record;begin
 for item in select * from (values
 ('Startup / Start-up scrap','بدء التشغيل'),('Changeover / Setup','تغيير المنتج / التجهيز'),('Incorrect machine settings','إعدادات آلة غير صحيحة'),
 ('Temperature too high','درجة حرارة مرتفعة'),('Temperature too low','درجة حرارة منخفضة'),('Unstable temperature','درجة حرارة غير مستقرة'),
 ('Cooling water level low','انخفاض مستوى مياه التبريد'),('Cooling water temperature high','ارتفاع حرارة مياه التبريد'),('Cooling water flow / pressure problem','مشكلة تدفق / ضغط مياه التبريد'),
 ('Material recipe / mixture problem','مشكلة الوصفة / الخليط'),('Wrong material ratio','نسبة مواد غير صحيحة'),('Material contamination','تلوث المواد'),('Material moisture','رطوبة المواد'),
 ('Material feeding problem','مشكلة تغذية المواد'),('Extrusion pressure instability','عدم استقرار ضغط البثق'),('Incorrect line speed','سرعة خط غير صحيحة'),
 ('Die / tooling problem','مشكلة القالب / الأدوات'),('Die blockage','انسداد القالب'),('Tooling wear','تآكل الأدوات'),('Calibration / measurement issue','مشكلة معايرة / قياس'),
 ('Printing defect','عيب الطباعة'),('Cutting defect','عيب القطع'),('Jointing / socketing defect','عيب التوصيل / التوسيع'),('Electrical fluctuation','تذبذب كهربائي'),
 ('Mechanical problem','مشكلة ميكانيكية'),('Raw-material quality problem','مشكلة جودة المواد الخام'),('Incorrect setup','تجهيز غير صحيح'),
 ('Process not followed','عدم اتباع العملية'),('Unknown / under investigation','غير معروف / قيد التحقيق'),('Other','أخرى')) x(en,ar) loop
  insert into public.downtime_reasons(factory_id,name,name_ar) select f,item.en,item.ar where not exists(select 1 from public.downtime_reasons where factory_id=f and lower(btrim(name))=lower(item.en));
 end loop;
 insert into public.permission_package_permissions(factory_id,package_id,module,action)
 select f,p.id,r.module,r.action from public.permission_packages p cross join public.permissions r where p.factory_id=f and
 ((p.template_key='owner' and r.module in ('lean','lean_standards')) or
 (p.template_key in ('production_manager','production_engineer') and ((r.module='lean' and r.action in ('view','create','edit')) or r.module='lean_standards')) or
 (p.template_key in ('planning_engineer','maintenance','warehouse','sales') and r.module='lean' and r.action='view'))
 on conflict(factory_id,package_id,module,action) do nothing;
end$$;
revoke all on function private.seed_lean_defaults(uuid) from public,anon,authenticated;
create function private.seed_factory_lean() returns trigger language plpgsql security definer set search_path='' as $$begin
 perform private.seed_lean_defaults(new.id);perform private.capture_lean_runtime(new.id);return new;end$$;
revoke all on function private.seed_factory_lean() from public,anon,authenticated;
-- Existing package seed executes before this trigger (alphabetic trigger ordering).
create trigger zz_seed_factory_lean after insert on public.factories for each row execute function private.seed_factory_lean();
do $$declare f uuid;begin for f in select id from public.factories loop perform private.seed_lean_defaults(f);end loop;end$$;

-- Existing protected owners cannot receive package assignments. Add the new keys to their
-- existing per-person owner grants so they can administer packages without bypassing ceilings.
insert into public.user_permissions(factory_id,user_id,module,action)
select m.factory_id,m.user_id,p.module,p.action from public.memberships m cross join public.permissions p
where m.is_owner and m.status='approved' and p.module in ('lean','lean_standards') on conflict do nothing;

create table private.lean_command_retries (
 factory_id uuid not null references public.factories,id uuid not null,actor_id uuid not null references auth.users,
 operation text not null,payload jsonb not null,result jsonb not null,created_at timestamptz not null default now(),primary key(factory_id,id)
);
alter table private.lean_command_retries enable row level security;
revoke all on private.lean_command_retries from public,anon,authenticated;

create function private.lean_command(f uuid,r uuid,op text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();saved private.lean_command_retries;result jsonb;target uuid;expected integer;
 action public.lean_actions;initiative public.lean_initiatives;problem public.lean_problem_settings;event public.lean_scrap_events;baseline_start timestamptz;baseline_end timestamptz;
 entry public.production_entries;job public.production_orders;allowed text[];manager boolean;
begin
 if actor is null then raise exception 'permission_denied' using errcode='42501';end if;
 perform private.require_permission(f,'factory','view');
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));
 perform private.require_permission(f,'factory','view');
 if r is null or p is null or jsonb_typeof(p)<>'object' then raise exception 'lean_invalid' using errcode='22023';end if;
 select * into saved from private.lean_command_retries where factory_id=f and id=r;
 if found then
  if saved.actor_id<>actor or saved.operation<>op or saved.payload<>p then raise exception 'lean_conflict' using errcode='40001';end if;
  return saved.result;
 end if;
 allowed:=case op
 when 'cause' then array['id','name','name_ar','parent_id']
 when 'standard' then array['id','line_id','product_id','running_percent','startup_kg','expected_revision','proposal_month']
 when 'template' then array['id','cause_id','title','name_ar','description','action_type','due_days','archived','expected_revision']
 when 'problem' then array['mechanism','machine_id','line_id','product_id','cause_id','monitor_only','threshold_percent','expected_revision']
 when 'initiative' then array['id','problem_id','product_id','title']
 when 'action' then array['id','initiative_id','title','description','action_type','owner_id','due_date','expected_revision']
 when 'progress' then array['id','status','due_date','note','expected_revision']
 when 'cancel_action' then array['id','reason','expected_revision']
 when 'scrap_observation' then array['id','entry_id','occurred_at','preliminary_cause_id','observation','response','downtime_id']
 when 'scrap_review' then array['id','approved_cause_id','note','expected_revision'] end;
 if allowed is null or exists(select 1 from jsonb_object_keys(p) key where not key=any(allowed)) then raise exception 'lean_invalid' using errcode='22023';end if;
 target:=(p->>'id')::uuid;expected:=coalesce((p->>'expected_revision')::integer,0);
 manager:=private.has_permission(f,'lean','edit');
 if op='standard' then perform private.require_permission(f,'lean_standards','edit');
 elsif op='scrap_observation' then perform private.require_permission(f,'orders','edit');
 elsif op='initiative' then perform private.require_permission(f,'lean','create');
 elsif op='progress' then perform private.require_permission(f,'lean','view');
 else perform private.require_permission(f,'lean','edit');end if;

 if op='cause' then
  if target is null or length(btrim(p->>'name')) not between 1 and 120 or length(coalesce(p->>'name_ar',''))>120 then raise exception 'lean_invalid' using errcode='22023';end if;
  if exists(select 1 from public.downtime_reasons where id=target and factory_id<>f) then raise exception 'permission_denied' using errcode='42501';end if;
  insert into public.downtime_reasons(id,factory_id,name,name_ar,parent_id) values(target,f,btrim(p->>'name'),coalesce(p->>'name_ar',''),(p->>'parent_id')::uuid)
  on conflict(id) do update set name=excluded.name,name_ar=excluded.name_ar,parent_id=excluded.parent_id;
 elsif op='standard' then
  if target is null then raise exception 'lean_invalid' using errcode='22023';end if;
  if exists(select 1 from public.lean_standards where factory_id=f and line_id=(p->>'line_id')::uuid and product_id=(p->>'product_id')::uuid and (id<>target or revision<>expected)) then raise exception 'lean_conflict' using errcode='40001';end if;
  if not exists(select 1 from public.lean_standards where id=target and factory_id=f) and expected<>0 then raise exception 'lean_conflict' using errcode='40001';end if;
  insert into public.lean_standards(id,factory_id,line_id,product_id,running_percent,startup_kg,created_by)
  values(target,f,(p->>'line_id')::uuid,(p->>'product_id')::uuid,(p->>'running_percent')::numeric,(p->>'startup_kg')::numeric,actor)
  on conflict(id) do update set running_percent=excluded.running_percent,startup_kg=excluded.startup_kg,revision=lean_standards.revision+1,created_by=actor,created_at=clock_timestamp()
  where lean_standards.factory_id=f and lean_standards.line_id=excluded.line_id and lean_standards.product_id=excluded.product_id and lean_standards.revision=expected;
  if not found then raise exception 'lean_conflict' using errcode='40001';end if;
  if p->>'proposal_month' is not null then
   update public.lean_standards st set approved_proposal_month=(p->>'proposal_month')::date,approved_observed_kg=(select avg(kg) from
    (select s.id,sum(e.effective_startup_kg) kg from public.lean_startups s join public.production_entries e on e.factory_id=f and e.lean_startup_id=s.id
    where s.factory_id=f and s.line_id=st.line_id and s.product_id=st.product_id and date_trunc('month',s.occurred_at at time zone (select timezone from public.factories where id=f))::date=(p->>'proposal_month')::date group by s.id)x) where id=target;
  end if;
 elsif op='template' then
  if target is null or (exists(select 1 from public.lean_action_templates where id=target) and not exists(select 1 from public.lean_action_templates where factory_id=f and id=target and revision=expected)) then raise exception 'lean_conflict' using errcode='40001';end if;
  insert into public.lean_action_templates(id,factory_id,cause_id,title,name_ar,description,action_type,due_days,archived,created_by)
  values(target,f,(p->>'cause_id')::uuid,p->>'title',coalesce(p->>'name_ar',''),coalesce(p->>'description',''),p->>'action_type',(p->>'due_days')::integer,coalesce((p->>'archived')::boolean,false),actor)
  on conflict(id) do update set cause_id=excluded.cause_id,title=excluded.title,name_ar=excluded.name_ar,description=excluded.description,action_type=excluded.action_type,due_days=excluded.due_days,archived=excluded.archived,revision=lean_action_templates.revision+1;
 elsif op='problem' then
  select * into problem from public.lean_problem_settings where factory_id=f and mechanism=p->>'mechanism' and cause_id=(p->>'cause_id')::uuid
  and machine_id is not distinct from (p->>'machine_id')::uuid and line_id is not distinct from (p->>'line_id')::uuid and product_id is not distinct from (p->>'product_id')::uuid;
  if found then
   if problem.revision<>expected then raise exception 'lean_conflict' using errcode='40001';end if;
   update public.lean_problem_settings set monitor_only=coalesce((p->>'monitor_only')::boolean,false),threshold_percent=coalesce((p->>'threshold_percent')::numeric,10),revision=revision+1 where id=problem.id;
   target:=problem.id;
  else
   if expected<>0 then raise exception 'lean_conflict' using errcode='40001';end if;
   insert into public.lean_problem_settings(factory_id,mechanism,machine_id,line_id,product_id,cause_id,monitor_only,threshold_percent,created_by)
   values(f,p->>'mechanism',(p->>'machine_id')::uuid,(p->>'line_id')::uuid,(p->>'product_id')::uuid,(p->>'cause_id')::uuid,coalesce((p->>'monitor_only')::boolean,false),coalesce((p->>'threshold_percent')::numeric,10),actor) returning id into target;
  end if;
 elsif op='initiative' then
  select * into problem from public.lean_problem_settings where factory_id=f and id=(p->>'problem_id')::uuid;
  if not found or target is null or not exists(select 1 from public.products where factory_id=f and id=(p->>'product_id')::uuid) then raise exception 'lean_invalid' using errcode='22023';end if;
  if problem.product_id is not null and problem.product_id<>(p->>'product_id')::uuid then raise exception 'lean_comparison_product' using errcode='22023';end if;
  select min(o.occurred_at),max(o.ended_at) into baseline_start,baseline_end from private.lean_occurrences o where o.factory_id=f and o.mechanism=problem.mechanism and o.cause_id=problem.cause_id
  and o.machine_id is not distinct from problem.machine_id and (problem.mechanism='downtime' or o.line_id=problem.line_id) and o.product_id=(p->>'product_id')::uuid;
  if baseline_start is null or baseline_end<=baseline_start then raise exception 'lean_baseline_missing' using errcode='22023';end if;
  insert into public.lean_initiatives(id,factory_id,problem_id,product_id,title,baseline_from,baseline_to,created_by)
  values(target,f,problem.id,(p->>'product_id')::uuid,p->>'title',baseline_start,baseline_end,actor);
 elsif op in ('action','progress','cancel_action') then
  select * into action from public.lean_actions where factory_id=f and id=target;
  if exists(select 1 from public.lean_actions where id=target and factory_id<>f) then raise exception 'permission_denied' using errcode='42501';end if;
  if found and action.revision<>expected then raise exception 'lean_conflict' using errcode='40001';end if;
  select * into initiative from public.lean_initiatives where factory_id=f and id=coalesce(action.initiative_id,(p->>'initiative_id')::uuid);
  if not found or initiative.verified_at is not null then raise exception 'lean_closed' using errcode='22023';end if;
  if op='action' then
   if target is null or not exists(select 1 from public.memberships where factory_id=f and user_id=(p->>'owner_id')::uuid and status='approved') or p->>'due_date' is null then raise exception 'lean_invalid' using errcode='22023';end if;
   if action.id is not null and (action.initiative_id<>initiative.id or action.status='CANCELLED') then raise exception 'lean_closed' using errcode='22023';end if;
   insert into public.lean_actions(id,factory_id,initiative_id,title,description,action_type,owner_id,due_date,created_by)
   values(target,f,initiative.id,p->>'title',coalesce(p->>'description',''),p->>'action_type',(p->>'owner_id')::uuid,(p->>'due_date')::date,actor)
   on conflict(id) do update set title=excluded.title,description=excluded.description,action_type=excluded.action_type,owner_id=excluded.owner_id,due_date=excluded.due_date,revision=lean_actions.revision+1,updated_at=clock_timestamp();
  else
   if action.id is null then raise exception 'not_found' using errcode='P0002';end if;
   if op='cancel_action' then
   if p->>'reason' is null or length(btrim(p->>'reason')) not between 3 and 2000 then raise exception 'lean_reason_required' using errcode='22023';end if;
    update public.lean_actions set status='CANCELLED',cancellation_reason=p->>'reason',revision=revision+1,updated_at=clock_timestamp() where id=target;
   else
    if not manager and action.owner_id<>actor then raise exception 'permission_denied' using errcode='42501';end if;
    if action.status='CANCELLED' or p->>'status' not in ('OPEN','IN_PROGRESS','COMPLETED') or p->>'due_date' is null or length(coalesce(p->>'note',''))>2000 then raise exception 'lean_invalid' using errcode='22023';end if;
    update public.lean_actions set status=p->>'status',due_date=(p->>'due_date')::date,progress_note=coalesce(p->>'note',''),revision=revision+1,updated_at=clock_timestamp() where id=target;
   end if;
  end if;
  update public.lean_initiatives set completed_at=case when exists(select 1 from public.lean_actions where initiative_id=initiative.id) and
  not exists(select 1 from public.lean_actions where initiative_id=initiative.id and status not in ('COMPLETED','CANCELLED')) then coalesce(completed_at,statement_timestamp()) else null end,revision=revision+1 where id=initiative.id;
 elsif op='scrap_observation' then
  select * into entry from public.production_entries where factory_id=f and id=(p->>'entry_id')::uuid;
  select * into job from public.production_orders where factory_id=f and id=entry.order_id;
  if entry.id is null or entry.effective_scrap_kg is null or entry.line_id is null or target is null or (p->>'occurred_at')::timestamptz>clock_timestamp() or (p->>'occurred_at')::timestamptz<job.actual_start then raise exception 'lean_invalid' using errcode='22023';end if;
  if p->>'downtime_id' is not null and not exists(select 1 from public.downtime_events d where d.factory_id=f and d.id=(p->>'downtime_id')::uuid and d.line_id=entry.line_id and d.order_id=entry.order_id and
  (p->>'occurred_at')::timestamptz between d.started_at and coalesce(d.ended_at,statement_timestamp())) then raise exception 'lean_link_invalid' using errcode='22023';end if;
  insert into public.lean_scrap_events(id,factory_id,entry_id,line_id,product_id,downtime_id,occurred_at,preliminary_cause_id,observation,response,created_by)
  values(target,f,entry.id,entry.line_id,job.product_id,(p->>'downtime_id')::uuid,(p->>'occurred_at')::timestamptz,(p->>'preliminary_cause_id')::uuid,p->>'observation',p->>'response',actor);
 elsif op='scrap_review' then
  select * into event from public.lean_scrap_events where factory_id=f and id=target;
  if not found or event.revision<>expected or (p->>'approved_cause_id')::uuid is null or length(coalesce(p->>'note',''))>2000 then raise exception 'lean_conflict' using errcode='40001';end if;
  if event.downtime_id is not null and not exists(select 1 from public.downtime_events where factory_id=f and id=event.downtime_id and approved_cause_id=(p->>'approved_cause_id')::uuid) then raise exception 'lean_link_cause' using errcode='22023';end if;
  update public.lean_scrap_events set approved_cause_id=(p->>'approved_cause_id')::uuid,engineering_note=coalesce(p->>'note',''),reviewed_by=actor,reviewed_at=clock_timestamp(),revision=revision+1 where id=target;
 end if;
 result:=jsonb_build_object('id',target);
 insert into private.lean_command_retries(factory_id,id,actor_id,operation,payload,result) values(f,r,actor,op,p,result);
 return result;
end$$;
create function public.lean_command(factory uuid,request_id uuid,operation text,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.lean_command(factory,request_id,operation,payload)$$;
revoke all on function private.lean_command(uuid,uuid,text,jsonb),public.lean_command(uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function private.lean_command(uuid,uuid,text,jsonb),public.lean_command(uuid,uuid,text,jsonb) to authenticated;

create function private.record_lean_production(f uuid,p jsonb,r uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare job public.production_orders;prod public.products;standard public.lean_standards;startup public.lean_startups;
 e public.production_entries;entry_id uuid;mass numeric;startup_mass numeric;discarded numeric;weight numeric;total_startup numeric;needs_review boolean:=false;
begin
 perform private.require_permission(f,'orders','edit');perform private.require_permission(f,'orders','view');
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));
 perform private.require_permission(f,'orders','edit');perform private.require_permission(f,'orders','view');
 if p is null or jsonb_typeof(p)<>'object' or exists(select 1 from jsonb_object_keys(p) key where key not in
 ('unit_kind','production_unit','item','technician','good','discarded_quantity','scrap_kg','startup_kg','notes','confirm_overproduction','shift','shift_override_reason','unfinished','remaining_work','input_lot','input_quantity','startup_id','startup_at')) then raise exception 'lean_invalid' using errcode='22023';end if;
 mass:=(p->>'scrap_kg')::numeric;startup_mass:=coalesce((p->>'startup_kg')::numeric,0);discarded:=(p->>'discarded_quantity')::numeric;
 if mass is null or discarded is null or mass<0 or discarded<0 or startup_mass<0 or startup_mass>mass or mass::text in ('NaN','Infinity','-Infinity') or startup_mass::text in ('NaN','Infinity','-Infinity') or coalesce((p->>'good')::numeric,0)+discarded+coalesce((p->>'unfinished')::numeric,0)+mass<=0 then raise exception 'lean_invalid' using errcode='22023';end if;
 select * into job from public.production_orders where factory_id=f and id=(p->>'item')::uuid;
 select * into prod from public.products where factory_id=f and id=job.product_id;
 weight:=case when job.unit='kg' then 1 when job.unit=prod.stock_unit then prod.unit_weight_kg end;
 select * into standard from public.lean_standards where factory_id=f and line_id=job.line_id and product_id=job.product_id;
 if p->>'startup_id' is not null then
  if job.line_id is null or (p->>'startup_at')::timestamptz is null or (p->>'startup_at')::timestamptz<job.actual_start or (p->>'startup_at')::timestamptz>clock_timestamp() then raise exception 'lean_invalid' using errcode='22023';end if;
  select * into startup from public.lean_startups where id=(p->>'startup_id')::uuid;
  if found and (startup.factory_id<>f or startup.item_id<>job.id or startup.line_id<>job.line_id or startup.occurred_at<>(p->>'startup_at')::timestamptz) then raise exception 'lean_conflict' using errcode='40001';end if;
  if not found then
   insert into public.lean_startups(id,factory_id,line_id,item_id,product_id,occurred_at,standard_kg,standard_revision,created_by)
   values((p->>'startup_id')::uuid,f,job.line_id,job.id,job.product_id,(p->>'startup_at')::timestamptz,standard.startup_kg,standard.revision,auth.uid()) returning * into startup;
  end if;
 elsif startup_mass>0 then raise exception 'lean_startup_required' using errcode='22023';end if;
 entry_id:=private.record_production(f,p->>'unit_kind',(p->>'production_unit')::uuid,job.id,(p->>'technician')::uuid,
 (p->>'good')::numeric,discarded,coalesce(p->>'notes',''),coalesce((p->>'confirm_overproduction')::boolean,false),r,
 (p->>'shift')::uuid,p->>'shift_override_reason',coalesce((p->>'unfinished')::numeric,0),coalesce(p->>'remaining_work',''),(p->>'input_lot')::uuid,coalesce((p->>'input_quantity')::numeric,0));
 select * into e from public.production_entries where id=entry_id;
 if e.original_scrap_kg is not null then
  if e.original_scrap_kg<>mass or e.original_startup_kg<>startup_mass or e.lean_startup_id is distinct from startup.id then raise exception 'recording_request_reused' using errcode='22023';end if;
 else
  update public.production_entries set original_scrap_kg=mass,effective_scrap_kg=mass,original_startup_kg=startup_mass,effective_startup_kg=startup_mass,
  weight_kg_per_unit=weight,produced_weight_kg=(effective_good+coalesce(effective_unfinished,0))*weight,lean_startup_id=startup.id,
  running_standard_percent=standard.running_percent,scrap_standard_revision=standard.revision where id=entry_id returning * into e;
 end if;
 return private.lean_scrap_assessment(f,entry_id)||jsonb_build_object('id',entry_id);
end$$;
create function public.record_lean_production(factory uuid,payload jsonb,request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.record_lean_production(factory,payload,request_id)$$;
revoke all on function private.record_lean_production(uuid,jsonb,uuid),public.record_lean_production(uuid,jsonb,uuid) from public,anon,authenticated;
grant execute on function private.record_lean_production(uuid,jsonb,uuid),public.record_lean_production(uuid,jsonb,uuid) to authenticated;

create function private.correct_lean_production(f uuid,p jsonb,r uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare e public.production_entries;correction public.production_entry_corrections;result uuid;mass numeric;startup_mass numeric;
begin
 perform private.require_permission(f,'orders','edit');perform private.require_permission(f,'orders','view');
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));
 perform private.require_permission(f,'orders','edit');perform private.require_permission(f,'orders','view');
 if p is null or jsonb_typeof(p)<>'object' or exists(select 1 from jsonb_object_keys(p) key where key not in
 ('entry','good','discarded_quantity','scrap_kg','startup_kg','reason','confirm_overproduction','shift','change_shift','unfinished','remaining_work')) then raise exception 'lean_invalid' using errcode='22023';end if;
 select * into e from public.production_entries where factory_id=f and id=(p->>'entry')::uuid;
 if not found then raise exception 'not_found' using errcode='P0002';end if;
 mass:=(p->>'scrap_kg')::numeric;startup_mass:=coalesce((p->>'startup_kg')::numeric,0);
 if mass is null or mass<0 or startup_mass<0 or startup_mass>mass or mass::text in ('NaN','Infinity','-Infinity') or startup_mass::text in ('NaN','Infinity','-Infinity') or (startup_mass>0 and e.lean_startup_id is null) then raise exception 'lean_invalid' using errcode='22023';end if;
 select * into correction from public.production_entry_corrections where factory_id=f and request_id=r;
 if found and (correction.corrected_scrap_kg is distinct from mass or correction.corrected_startup_kg is distinct from startup_mass) then raise exception 'recording_request_reused' using errcode='22023';end if;
 result:=private.correct_production(f,e.id,(p->>'good')::numeric,(p->>'discarded_quantity')::numeric,p->>'reason',coalesce((p->>'confirm_overproduction')::boolean,false),r,
 (p->>'shift')::uuid,coalesce((p->>'change_shift')::boolean,false),coalesce((p->>'unfinished')::numeric,0),coalesce(p->>'remaining_work',''));
 if correction.id is null then
  update public.production_entry_corrections set previous_scrap_kg=e.effective_scrap_kg,corrected_scrap_kg=mass,previous_startup_kg=e.effective_startup_kg,corrected_startup_kg=startup_mass where id=result;
  update public.production_entries set effective_scrap_kg=mass,effective_startup_kg=startup_mass,produced_weight_kg=(effective_good+coalesce(effective_unfinished,0))*weight_kg_per_unit where id=e.id;
 end if;
 return result;
end$$;
create function public.correct_lean_production(factory uuid,payload jsonb,request_id uuid) returns uuid language sql security invoker set search_path='' as $$select private.correct_lean_production(factory,payload,request_id)$$;
revoke all on function private.correct_lean_production(uuid,jsonb,uuid),public.correct_lean_production(uuid,jsonb,uuid) from public,anon,authenticated;
grant execute on function private.correct_lean_production(uuid,jsonb,uuid),public.correct_lean_production(uuid,jsonb,uuid) to authenticated;

-- The deprecated mixed-unit write paths cannot create new operator declarations.
revoke execute on function public.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,text,numeric,text,uuid,numeric),
 private.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,text,numeric,text,uuid,numeric),
 public.correct_production_entry(uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,boolean,numeric,text),
 private.correct_production(uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,boolean,numeric,text) from authenticated;
do $$declare fn record;begin
 for fn in select oid::regprocedure signature from pg_proc where pronamespace in ('public'::regnamespace,'private'::regnamespace) and proname in ('record_production','correct_production','correct_production_entry') loop
  execute format('revoke execute on function %s from public,anon,authenticated',fn.signature);
 end loop;
end$$;

create function private.lean_scrap_assessment(f uuid,eid uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('entry_id',e.id,'scrap_kg',e.effective_scrap_kg,'produced_kg',e.produced_weight_kg,
 'running_standard',e.running_standard_percent,'startup_id',s.id,'startup_standard',s.standard_kg,'startup_total',startup.total,
 'needs_review',coalesce((s.standard_kg is not null and startup.total>s.standard_kg) or
 (e.running_standard_percent is not null and e.produced_weight_kg>0 and
 100*(e.effective_scrap_kg-case when s.id is null then 0 when s.standard_kg is null then null else
 least(e.effective_startup_kg,greatest(0,s.standard_kg-startup.previous_total)) end)/e.produced_weight_kg>e.running_standard_percent),false),
 'weight_missing',e.produced_weight_kg is null,'standard_missing',e.running_standard_percent is null or (s.id is not null and s.standard_kg is null))
 from public.production_entries e left join public.lean_startups s on s.id=e.lean_startup_id and s.factory_id=f
 left join lateral(select coalesce(sum(x.effective_startup_kg),0) total,
 coalesce(sum(x.effective_startup_kg) filter(where (x.created_at,x.id)<(e.created_at,e.id)),0) previous_total
 from public.production_entries x where x.factory_id=f and x.lean_startup_id=s.id and (x.created_at,x.id)<=(e.created_at,e.id)) startup on true
 where e.factory_id=f and e.id=eid
$$;
revoke all on function private.lean_scrap_assessment(uuid,uuid) from public,anon,authenticated;

create view private.lean_occurrences as
 select d.factory_id,'downtime'::text mechanism,d.id event_id,d.work_center_id machine_id,d.line_id,
 case when (select count(distinct x->>'product_id') from jsonb_array_elements(coalesce(estimate.result->'assumptions','[]'))x)>1 then null::uuid
 else coalesce(o.product_id,(estimate.result->'assumptions'->0->>'product_id')::uuid) end product_id,d.approved_cause_id cause_id,
 d.started_at occurred_at,d.ended_at,d.lean_shift_id shift_id,
 coalesce(a.actual_loss_minutes,(estimate.result->>'effective_loss_minutes')::numeric) loss_minutes,
 coalesce(a.actual_lost_output_quantity,(estimate.result->>'estimated_lost_output_quantity')::numeric) lost_output,
 coalesce(a.actual_lost_output_unit,estimate.result->>'unit',o.unit) output_unit,
 case when associated.entries>0 then associated.scrap_kg when a.scrap_unit='kg' then a.scrap_quantity end scrap_kg,
 associated.produced_kg,associated.wip_quantity,d.initial_note observation,d.reason_id preliminary_cause_id,d.engineering_note response,
 d.order_id item_id,d.id downtime_id,estimate.result loss_details,
 case when a.actual_loss_minutes is not null then 'ACTUAL' when estimate.id is not null then 'SAVED_ESTIMATE' else 'MISSING' end loss_source
 from public.downtime_events d left join public.production_orders o on o.factory_id=d.factory_id and o.id=d.order_id
 left join public.production_loss_estimates estimate on estimate.factory_id=d.factory_id and estimate.event_id=d.id
 left join public.production_loss_actuals a on a.factory_id=d.factory_id and a.event_id=d.id
 left join lateral(select count(*) entries,sum(e.effective_scrap_kg) scrap_kg,
 case when count(*) filter(where e.produced_weight_kg is null)=0 then sum(e.produced_weight_kg) end produced_kg,
 sum(e.effective_unfinished) wip_quantity from public.lean_scrap_events s join public.production_entries e on e.factory_id=s.factory_id and e.id=s.entry_id
 where s.factory_id=d.factory_id and s.downtime_id=d.id and s.approved_cause_id=d.approved_cause_id) associated on true
 where d.ended_at is not null and d.approved_cause_id is not null and d.approved_at is not null
 union all
 select s.factory_id,'scrap',coalesce(case when e.effective_scrap_kg=e.effective_startup_kg then e.lean_startup_id end,s.id),null::uuid,
 s.line_id,s.product_id,s.approved_cause_id,min(s.occurred_at),max(e.created_at),e.shift_id,
 0::numeric,0::numeric,e.unit,sum(e.effective_scrap_kg),
 case when count(*) filter(where e.produced_weight_kg is null)=0 then sum(e.produced_weight_kg) end,
 sum(e.effective_unfinished),string_agg(s.observation,E'\n'),s.preliminary_cause_id,string_agg(s.response,E'\n'),e.order_id,null::uuid,null::jsonb,'NOT_DOWNTIME'
 from public.lean_scrap_events s join public.production_entries e on e.factory_id=s.factory_id and e.id=s.entry_id
 where s.downtime_id is null and s.approved_cause_id is not null and (private.lean_scrap_assessment(s.factory_id,s.entry_id)->>'needs_review')::boolean
 group by s.factory_id,coalesce(case when e.effective_scrap_kg=e.effective_startup_kg then e.lean_startup_id end,s.id),s.line_id,s.product_id,s.approved_cause_id,e.shift_id,e.unit,s.preliminary_cause_id,e.order_id;
revoke all on private.lean_occurrences from public,anon,authenticated;
-- Draft extension; appended to the single unapplied forward migration before deployment.
do $$declare definition text;begin
 definition:=pg_get_functiondef('private.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,text,numeric,text,uuid,numeric)'::regprocedure);
 if position('good+scrap+coalesce(unfinished,0)<=0' in definition)=0 then raise exception 'lean_worker_changed';end if;
 execute replace(definition,'good+scrap+coalesce(unfinished,0)<=0','good+scrap+coalesce(unfinished,0)<0');
end$$;

-- Retain old non-kg observations, but every newly declared mass is kg.
alter table public.production_entries drop constraint entry_physical_output;
alter table public.production_entries add constraint entry_physical_nonnegative check(produced>=0);
create function private.lean_entry_physical_output() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from public.production_entries where id=new.id and recording_version=2 and
 coalesce(good_quantity,0)+coalesce(scrap_quantity,0)+coalesce(unfinished_quantity,0)+coalesce(original_scrap_kg,0)<=0) then raise exception 'recording_invalid_quantity';end if;return null;
end$$;
revoke all on function private.lean_entry_physical_output() from public,anon,authenticated;
create constraint trigger lean_entry_physical_output after insert on public.production_entries deferrable initially deferred for each row execute function private.lean_entry_physical_output();
create function private.lean_mass_unit_guard() returns trigger language plpgsql set search_path='' as $$begin
 if (new.scrap_quantity is not null or new.shutdown_scrap_quantity is not null or new.restart_scrap_quantity is not null) and new.scrap_unit is distinct from 'kg' and
 (tg_op='INSERT' or new.scrap_quantity is distinct from old.scrap_quantity or new.shutdown_scrap_quantity is distinct from old.shutdown_scrap_quantity or new.restart_scrap_quantity is distinct from old.restart_scrap_quantity or new.scrap_unit is distinct from old.scrap_unit)
 then raise exception 'lean_scrap_kg_only' using errcode='22023';end if;return new;
end$$;
revoke all on function private.lean_mass_unit_guard() from public,anon,authenticated;
create trigger lean_mass_unit_guard before insert or update on public.production_loss_actuals for each row execute function private.lean_mass_unit_guard();

create function private.lean_profile_unit_guard() returns trigger language plpgsql set search_path='' as $$begin
 if new.scrap_unit is distinct from 'kg' and (new.shutdown_scrap_quantity is not null or new.restart_scrap_quantity is not null) and
 (tg_op='INSERT' or new.scrap_unit is distinct from old.scrap_unit or new.shutdown_scrap_quantity is distinct from old.shutdown_scrap_quantity or new.restart_scrap_quantity is distinct from old.restart_scrap_quantity) then raise exception 'lean_scrap_kg_only' using errcode='22023';end if;return new;
end$$;
revoke all on function private.lean_profile_unit_guard() from public,anon,authenticated;
create trigger lean_profile_unit_guard before insert or update on public.production_loss_profiles for each row execute function private.lean_profile_unit_guard();

create function private.lean_read(f uuid,q jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare mode text:=coalesce(q->>'mode','problems');page integer:=coalesce((q->>'page')::integer,1);take integer:=100;
 result jsonb;problem public.lean_problem_settings;from_at timestamptz;to_at timestamptz;
begin
 if mode in ('recording_review','recording_context') then perform private.require_permission(f,'orders','view');else perform private.require_permission(f,'lean','view');end if;
 if q is null or jsonb_typeof(q)<>'object' or page not between 1 and 1000000 or exists(select 1 from jsonb_object_keys(q) k where k not in
 ('mode','page','from','to','line_id','machine_id','product_id','shift_id','cause_id','mechanism','problem_id','initiative_id','item_id','sort','direction','search','recurring','monitor_only','min_scrap','min_frequency')) then raise exception 'lean_invalid' using errcode='22023';end if;
 from_at:=coalesce((q->>'from')::timestamptz,statement_timestamp()-interval '30 days');to_at:=coalesce((q->>'to')::timestamptz,statement_timestamp());
 if to_at<from_at or to_at>statement_timestamp()+interval '1 minute' then raise exception 'lean_invalid' using errcode='22023';end if;
 if mode='recording_context' then
  result:=jsonb_build_object('causes',coalesce((select jsonb_agg(to_jsonb(x)) from (select id,name,name_ar from public.downtime_reasons where factory_id=f order by name,id limit take offset (page-1)*take)x),'[]'),
   'startups',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from public.lean_startups where factory_id=f and item_id=(q->>'item_id')::uuid order by occurred_at desc,id limit take offset (page-1)*take)x),'[]'));
 elsif mode='contexts' then
  with data as (select * from public.lean_runtime_contexts where factory_id=f and captured_at<=to_at and
   (captured_at>=from_at or captured_at=(select max(captured_at) from public.lean_runtime_contexts where factory_id=f and captured_at<from_at)))
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x) order by captured_at,id) from (select * from data order by captured_at,id limit take offset (page-1)*take)x),'[]'),'total',(select count(*) from data),'as_of',to_at) into result;
 elsif mode='entries' then
  with data as(select e.*,o.product_id,
   (select coalesce(jsonb_agg(c->>'id'),'[]') from jsonb_array_elements((select context->'centers' from public.lean_runtime_contexts where factory_id=f and captured_at<=e.created_at order by captured_at desc,id desc limit 1))c where c->>'line_id'=e.line_id::text) machine_ids
   from public.production_entries e join public.production_orders o on o.factory_id=f and o.id=e.order_id where e.factory_id=f and e.created_at>=from_at and e.created_at<to_at and (q->>'product_id' is null or o.product_id=(q->>'product_id')::uuid))
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from data order by created_at,id limit take offset (page-1)*take)x),'[]'),'total',(select count(*) from data)) into result;
 elsif mode='analysis_occurrences' then
  with data as(select * from private.lean_occurrences o where o.factory_id=f and o.occurred_at>=from_at and o.occurred_at<to_at and
   (q->>'line_id' is null or o.line_id=(q->>'line_id')::uuid) and (q->>'machine_id' is null or o.machine_id=(q->>'machine_id')::uuid) and
   (q->>'product_id' is null or o.product_id=(q->>'product_id')::uuid) and (q->>'cause_id' is null or o.cause_id=(q->>'cause_id')::uuid) and
   (q->>'shift_id' is null or o.shift_id=(q->>'shift_id')::uuid))
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from data order by occurred_at,event_id limit take offset (page-1)*take)x),'[]'),'total',(select count(*) from data)) into result;
 elsif mode='library' then
  result:=jsonb_build_object(
   'causes',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from public.downtime_reasons where factory_id=f order by name,id limit take offset (page-1)*take)x),'[]'),
   'templates',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from public.lean_action_templates where factory_id=f order by title,id limit take offset (page-1)*take)x),'[]'),
   'standards',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from public.lean_standards where factory_id=f order by line_id,product_id limit take offset (page-1)*take)x),'[]'),
   'observed_startup',coalesce((select jsonb_agg(to_jsonb(x)) from (select s.line_id,s.product_id,date_trunc('month',s.occurred_at at time zone (select timezone from public.factories where id=f)) observed_month,count(*) startups,avg(e.mass) observed_kg
    from public.lean_startups s join lateral(select sum(effective_startup_kg) mass from public.production_entries where factory_id=f and lean_startup_id=s.id)e on true
    where s.factory_id=f group by s.line_id,s.product_id,date_trunc('month',s.occurred_at at time zone (select timezone from public.factories where id=f)) order by observed_month desc limit take offset (page-1)*take)x),'[]'),
   'people',coalesce((select jsonb_agg(to_jsonb(x)) from (select user_id,display_name from public.memberships where factory_id=f and status='approved' order by display_name limit take offset (page-1)*take)x),'[]'));
 elsif mode='pending' then
  perform private.require_permission(f,'lean','edit');
  with data as (select s.*,e.effective_scrap_kg,e.produced_weight_kg,e.shift_id from public.lean_scrap_events s join public.production_entries e on e.factory_id=f and e.id=s.entry_id where s.factory_id=f and s.reviewed_at is null)
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from data order by occurred_at desc,id limit take offset (page-1)*take)x),'[]'),'total',(select count(*) from data)) into result;
 elsif mode='recording_review' then
  perform private.require_permission(f,'orders','view');
  with data as (select e.id,e.order_id,e.line_id,e.created_at,e.effective_scrap_kg,private.lean_scrap_assessment(f,e.id) assessment from public.production_entries e
   where e.factory_id=f and e.line_id is not null and not exists(select 1 from public.lean_scrap_events s where s.factory_id=f and s.entry_id=e.id)
   and (private.lean_scrap_assessment(f,e.id)->>'needs_review')::boolean)
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from data order by created_at desc,id limit take offset (page-1)*take)x),'[]'),'total',(select count(*) from data)) into result;
 elsif mode in ('detail','occurrences') then
 select * into problem from public.lean_problem_settings where factory_id=f and id=(q->>'problem_id')::uuid;
  if problem.id is null then
   problem.factory_id:=f;problem.mechanism:=q->>'mechanism';problem.machine_id:=(q->>'machine_id')::uuid;problem.line_id:=(q->>'line_id')::uuid;problem.product_id:=(q->>'product_id')::uuid;problem.cause_id:=(q->>'cause_id')::uuid;
   if not exists(select 1 from private.lean_occurrences o where o.factory_id=f and o.mechanism=problem.mechanism and o.machine_id is not distinct from problem.machine_id and o.cause_id=problem.cause_id and (problem.mechanism='downtime' or o.line_id=problem.line_id and o.product_id=problem.product_id)) then raise exception 'not_found' using errcode='P0002';end if;
  end if;
  with data as (select * from private.lean_occurrences o where o.factory_id=f and o.mechanism=problem.mechanism and o.cause_id=problem.cause_id and o.machine_id is not distinct from problem.machine_id and
   (problem.mechanism='downtime' or o.line_id=problem.line_id and o.product_id=problem.product_id) and (q->>'product_id' is null or o.product_id=(q->>'product_id')::uuid or o.product_id is null) and o.occurred_at>=from_at and o.occurred_at<to_at)
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from data order by occurred_at,event_id limit take offset (page-1)*take)x),'[]'),'total',(select count(*) from data),'problem',to_jsonb(problem)) into result;
  if mode='detail' then
   result:=result||jsonb_build_object(
    'recurrence_watch',(select jsonb_build_object('verified_at',i.verified_at,'frequency',count(distinct o.event_id),'recurred',count(distinct o.event_id)>=2) from public.lean_initiatives i left join private.lean_occurrences o on o.factory_id=f and o.mechanism=problem.mechanism and o.cause_id=problem.cause_id and o.machine_id is not distinct from problem.machine_id and (problem.mechanism='downtime' or o.line_id=problem.line_id and o.product_id=problem.product_id) and o.occurred_at>i.verified_at and o.occurred_at<=least(i.verified_at+interval '30 days',statement_timestamp()) where i.id=(select id from public.lean_initiatives where factory_id=f and problem_id=problem.id and outcome='IMPROVED' and verified_at is not null order by verified_at desc,id desc limit 1) group by i.verified_at),
    'initiatives',coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('derived_status',case when x.verified_at is not null then 'VERIFIED' when x.completed_at is not null then 'AWAITING_VERIFICATION' when exists(select 1 from public.lean_actions where factory_id=f and initiative_id=x.id and status<>'OPEN') then 'IN_PROGRESS' else 'OPEN' end)) from
     (select * from public.lean_initiatives where factory_id=f and problem_id=problem.id and (q->>'initiative_id' is null or id=(q->>'initiative_id')::uuid) and (verified_at is null or id in(select id from public.lean_initiatives where factory_id=f and problem_id=problem.id and verified_at is not null order by created_at desc,id limit 25 offset (page-1)*25)))x),'[]'),
    'actions',coalesce((select jsonb_agg(to_jsonb(x)) from (select a.* from public.lean_actions a join public.lean_initiatives i on i.factory_id=f and i.id=a.initiative_id where a.factory_id=f and i.problem_id=problem.id order by a.created_at,a.id limit take offset (page-1)*take)x),'[]'),
    'previous_actions',coalesce((select jsonb_agg(to_jsonb(x)) from (select a.*,i.outcome,i.verified_at,p.machine_id,p.line_id from public.lean_actions a join public.lean_initiatives i on i.factory_id=f and i.id=a.initiative_id join public.lean_problem_settings p on p.factory_id=f and p.id=i.problem_id where a.factory_id=f and p.cause_id=problem.cause_id and i.verified_at is not null order by i.verified_at desc,a.id limit take offset (page-1)*take)x),'[]'),
    'comparisons',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from public.lean_saved_comparisons where factory_id=f and problem_id=problem.id order by created_at desc limit 25 offset (page-1)*25)x),'[]'),
    'history',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from public.audit_logs where factory_id=f and
     (entity_id=problem.id or entity_id in(select id from public.lean_initiatives where factory_id=f and problem_id=problem.id) or entity_id in(select a.id from public.lean_actions a join public.lean_initiatives i on i.factory_id=f and i.id=a.initiative_id where a.factory_id=f and i.problem_id=problem.id)) order by created_at desc,id limit 50 offset (page-1)*50)x),'[]'),
    'sales',case when private.has_permission(f,'sales_orders','view') then coalesce((select jsonb_agg(to_jsonb(x)) from (select so.id,so.code,so.requested_delivery,delivery.info->>'risk' risk,delivery.info->>'estimated_ready' estimated_ready,
      (select jsonb_object_agg(unit,quantity) from (select sl.unit,sum(a.quantity) quantity from public.sales_incoming_allocations a join public.sales_order_lines sl on sl.factory_id=f and sl.id=a.line_id
       where a.factory_id=f and sl.order_id=so.id and a.item_id in(select o.item_id from private.lean_occurrences o where o.factory_id=f and o.mechanism=problem.mechanism and o.machine_id is not distinct from problem.machine_id and o.cause_id=problem.cause_id and (problem.mechanism='downtime' or o.line_id=problem.line_id and o.product_id=problem.product_id)) group by sl.unit)u) affected_quantity
      from public.sales_orders so cross join lateral(select private.sales_order_detail(f,so.id) info)delivery
      where so.factory_id=f and exists(select 1 from public.sales_order_lines sl join public.sales_incoming_allocations a on a.factory_id=f and a.line_id=sl.id where sl.factory_id=f and sl.order_id=so.id and a.item_id in
       (select o.item_id from private.lean_occurrences o where o.factory_id=f and o.mechanism=problem.mechanism and o.machine_id is not distinct from problem.machine_id and o.cause_id=problem.cause_id and (problem.mechanism='downtime' or o.line_id=problem.line_id and o.product_id=problem.product_id)))
       order by so.created_at desc,so.id limit 25 offset (page-1)*25)x),'[]') else null end,
    'maintenance',case when private.has_permission(f,'maintenance','view') then coalesce((select jsonb_agg(to_jsonb(x)) from (select m.* from public.maintenance_requests m where m.factory_id=f and
     (m.work_center_id=problem.machine_id or m.line_id=problem.line_id) order by m.requested_at desc limit 25 offset (page-1)*25)x),'[]') else null end);
  end if;
 elsif mode in ('problems','problem_aggregates') then
  if to_at-from_at>interval '366 days' then raise exception 'lean_invalid' using errcode='22023';end if;
  if coalesce(q->>'sort','loss_minutes') not in ('loss_minutes','scrap_kg','frequency','loss_rate','cause') then raise exception 'lean_invalid' using errcode='22023';end if;
  with source as materialized(select * from private.lean_occurrences o where o.factory_id=f and o.occurred_at>=from_at and o.occurred_at<to_at
   and (q->>'line_id' is null or o.line_id=(q->>'line_id')::uuid) and (q->>'machine_id' is null or o.machine_id=(q->>'machine_id')::uuid)
   and (q->>'product_id' is null or o.product_id=(q->>'product_id')::uuid) and (q->>'shift_id' is null or o.shift_id=(q->>'shift_id')::uuid)
   and (q->>'cause_id' is null or o.cause_id=(q->>'cause_id')::uuid) and (q->>'mechanism' is null or o.mechanism=q->>'mechanism')),
  grouped as (select mechanism,machine_id,case when mechanism='scrap' then line_id end line_id,case when mechanism='scrap' then product_id end product_id,cause_id,
   count(distinct event_id) frequency,sum(loss_minutes) loss_minutes,count(*) filter(where loss_minutes is null) missing_loss,
   sum(scrap_kg) scrap_kg,count(*) filter(where scrap_kg is null) missing_scrap,
   case when count(*) filter(where produced_kg is null)=0 and sum(produced_kg)>0 then 100*sum(scrap_kg)/sum(produced_kg) end scrap_rate,
   array_agg(distinct shift_id) shifts,array_agg(distinct product_id) products,array_agg(distinct line_id) lines,
   min(occurred_at) first_at,max(ended_at) last_at,
   jsonb_build_object('piece',sum(lost_output) filter(where output_unit='piece'),'meter',sum(lost_output) filter(where output_unit='meter'),'kg',sum(lost_output) filter(where output_unit='kg')) lost_output_by_unit,
   jsonb_build_object('piece',sum(wip_quantity) filter(where output_unit='piece'),'meter',sum(wip_quantity) filter(where output_unit='meter'),'kg',sum(wip_quantity) filter(where output_unit='kg')) wip_by_unit
   from source group by mechanism,machine_id,case when mechanism='scrap' then line_id end,case when mechanism='scrap' then product_id end,cause_id),
  data as materialized(select g.*,c.name cause,c.name_ar cause_ar,p.id problem_id,coalesce(p.monitor_only,false) monitor_only,coalesce(p.threshold_percent,10) threshold_percent,coalesce(p.revision,0) revision,
   (select to_jsonb(i) from public.lean_initiatives i where i.factory_id=f and i.problem_id=p.id order by i.created_at desc limit 1) initiative
   from grouped g join public.downtime_reasons c on c.factory_id=f and c.id=g.cause_id left join public.lean_problem_settings p on p.factory_id=f and p.mechanism=g.mechanism and p.cause_id=g.cause_id and p.machine_id is not distinct from g.machine_id and p.line_id is not distinct from g.line_id and p.product_id is not distinct from g.product_id
   where (q->>'search' is null or c.name ilike '%'||(q->>'search')||'%' or c.name_ar ilike '%'||(q->>'search')||'%') and
   (q->>'recurring' is null or g.frequency>=2) and (q->>'monitor_only' is null or coalesce(p.monitor_only,false)=(q->>'monitor_only')::boolean) and g.frequency>=coalesce((q->>'min_frequency')::numeric,0) and coalesce(g.scrap_kg,0)>=coalesce((q->>'min_scrap')::numeric,0))
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x)) from (select data.* from data order by
   case when q->>'sort'='scrap_kg' then scrap_kg when q->>'sort'='frequency' then frequency else loss_minutes end desc nulls last,cause,machine_id,line_id,product_id limit case when mode='problems' then 25 else 100 end offset (page-1)*case when mode='problems' then 25 else 100 end)x),'[]'),
   'total',(select count(*) from data),'summary',(select jsonb_build_object('loss_minutes',sum(loss_minutes),'missing_loss',sum(missing_loss),'recurring',count(*) filter(where frequency>=2),'scrap_kg',sum(scrap_kg)) from data),
   'open_initiatives',(select count(*) from public.lean_initiatives where factory_id=f and verified_at is null),
   'overdue_actions',(select count(*) from public.lean_actions where factory_id=f and status not in ('COMPLETED','CANCELLED') and due_date<current_date),
   'sales_at_risk',case when private.has_permission(f,'sales_orders','view') then (select count(*) from public.sales_orders so where so.factory_id=f and so.status='approved' and private.sales_order_detail(f,so.id)->>'risk' in ('late','at_risk')) end) into result;
 else raise exception 'lean_invalid' using errcode='22023';end if;
 return result||jsonb_build_object('page',page,'page_size',case when mode='problems' then 25 else take end,
 'source_revision',(select revision from private.lean_source_state where factory_id=f));
end$$;
create function public.lean_read(factory uuid,query jsonb) returns jsonb language sql stable security invoker set search_path='' as $$select private.lean_read(factory,query)$$;
revoke all on function private.lean_read(uuid,jsonb),public.lean_read(uuid,jsonb) from public,anon,authenticated;
grant execute on function private.lean_read(uuid,jsonb),public.lean_read(uuid,jsonb) to authenticated;

-- Trusted server calculation supplies evidence. Human confirmation remains a separate deliberate operation.
create function public.store_lean_evidence(factory uuid,actor uuid,operation text,target uuid,expected_revision integer,evidence jsonb,payload jsonb,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare i public.lean_initiatives;p public.lean_problem_settings;old_claim text;result jsonb;saved private.lean_command_retries;
begin
 if auth.role()<>'service_role' or actor is null or evidence is null or jsonb_typeof(evidence)<>'object' then raise exception 'permission_denied' using errcode='42501';end if;
 old_claim:=current_setting('request.jwt.claim.sub',true);perform set_config('request.jwt.claim.sub',actor::text,true);
 perform private.require_permission(factory,'lean','view');perform pg_advisory_xact_lock(hashtextextended(factory::text,0));
 perform private.require_permission(factory,'lean','view');
 if operation='verify' then perform private.require_permission(factory,'lean','approve');end if;
 if operation='baseline' then perform private.require_permission(factory,'lean','create');end if;
 select * into saved from private.lean_command_retries where factory_id=store_lean_evidence.factory and id=request_id;
 if found then
  if saved.actor_id<>actor or saved.operation<>operation or saved.payload<>payload||jsonb_build_object('target',target) then raise exception 'lean_conflict' using errcode='40001';end if;
  perform set_config('request.jwt.claim.sub',coalesce(old_claim,''),true);return saved.result;
 end if;
 perform 1 from private.lean_source_state where factory_id=factory and revision=(evidence->>'source_revision')::bigint for update;
 if not found then raise exception 'lean_conflict' using errcode='40001';end if;
 if operation in ('baseline','verify') then
  select * into i from public.lean_initiatives where factory_id=factory and id=target for update;
  if i.id is null or i.revision<>expected_revision or i.verified_at is not null then raise exception 'lean_conflict' using errcode='40001';end if;
  if evidence->>'product_id' is distinct from i.product_id::text or evidence->>'problem_id' is distinct from i.problem_id::text then raise exception 'lean_comparison_product';end if;
  if operation='baseline' then
   if i.baseline_evidence is not null then raise exception 'lean_baseline_locked';end if;
   perform private.require_permission(factory,'lean','create');
   update public.lean_initiatives set baseline_hours=nullif((evidence->>'runtime_hours')::numeric,0),baseline_evidence=evidence,revision=revision+1 where id=i.id;
  else
   if i.completed_at is null or exists(select 1 from public.lean_actions where factory_id=factory and initiative_id=i.id and status not in ('COMPLETED','CANCELLED')) or i.baseline_evidence is null then raise exception 'lean_incomplete';end if;
   if payload->>'outcome' is null or payload->>'outcome' not in ('IMPROVED','NO_MEANINGFUL_CHANGE','WORSE','INSUFFICIENT_DATA') or payload->>'note' is null or length(btrim(payload->>'note')) not between 3 and 2000 then raise exception 'lean_invalid';end if;
   if not coalesce((evidence->>'complete')::boolean,false) and payload->>'outcome'<>'INSUFFICIENT_DATA' then raise exception 'lean_insufficient_exposure';end if;
   update public.lean_initiatives set verified_at=clock_timestamp(),verified_by=actor,outcome=payload->>'outcome',verification_note=payload->>'note',verification_evidence=evidence,revision=revision+1 where id=i.id;
  end if;
  result:=jsonb_build_object('id',i.id);
 elsif operation='save_comparison' then
  select * into p from public.lean_problem_settings where factory_id=factory and id=target;
  if p.id is null or (p.product_id is not null and p.product_id::text<>evidence->>'product_id') then raise exception 'lean_comparison_product';end if;
  insert into public.lean_saved_comparisons(id,factory_id,problem_id,product_id,cutoff,desired_hours,evidence,created_by)
  values(request_id,factory,p.id,(evidence->>'product_id')::uuid,(payload->>'cutoff')::timestamptz,(payload->>'desired_hours')::numeric,evidence,actor);
  result:=jsonb_build_object('id',request_id);
 else raise exception 'lean_invalid';end if;
 insert into private.lean_command_retries(factory_id,id,actor_id,operation,payload,result) values(factory,request_id,actor,operation,payload||jsonb_build_object('target',target),result);
 perform set_config('request.jwt.claim.sub',coalesce(old_claim,''),true);return result;
end$$;

create function private.lean_timezone_changed() returns trigger language plpgsql security definer set search_path='' as $$begin
 perform private.capture_lean_runtime(new.id);
 insert into private.lean_source_state(factory_id,revision) values(new.id,1) on conflict(factory_id) do update set revision=lean_source_state.revision+1;
 return null;
end$$;
revoke all on function private.lean_timezone_changed() from public,anon,authenticated;
create trigger lean_timezone_changed after update of timezone on public.factories for each row when(old.timezone is distinct from new.timezone) execute function private.lean_timezone_changed();
revoke all on function public.store_lean_evidence(uuid,uuid,text,uuid,integer,jsonb,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.store_lean_evidence(uuid,uuid,text,uuid,integer,jsonb,jsonb,uuid) to service_role;

-- A source revision prevents mixed pages or a correction racing trusted evidence persistence.
create table private.lean_source_state(factory_id uuid primary key references public.factories,revision bigint not null default 0);
alter table private.lean_source_state enable row level security;
revoke all on private.lean_source_state from public,anon,authenticated;
insert into private.lean_source_state(factory_id) select id from public.factories;
create function private.lean_source_changed() returns trigger language plpgsql security definer set search_path='' as $$begin
 insert into private.lean_source_state(factory_id,revision) values(coalesce(new.factory_id,old.factory_id),1) on conflict(factory_id) do update set revision=lean_source_state.revision+1;return null;
end$$;
revoke all on function private.lean_source_changed() from public,anon,authenticated;
do $$declare tab text;begin
 foreach tab in array array['production_entries','production_entry_corrections','production_orders','work_centers','production_lines','production_transfers','downtime_events','production_shifts','production_loss_actuals','production_loss_estimates','lean_scrap_events','lean_startups'] loop
 execute format('create trigger lean_source_changed after insert or update or delete on public.%I for each row execute function private.lean_source_changed()',tab);
 end loop;
end$$;

