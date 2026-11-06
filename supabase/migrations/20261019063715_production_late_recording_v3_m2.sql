-- Production Recording V3 M2: additive, inactive writer/recovery contract.
-- No historical attribution backfill; no activation or machine/execution changes.
begin;
create table private.production_recording_v3_activation(
 factory_id uuid primary key references public.factories,
 enabled boolean not null default false, schema_contract_version smallint not null default 0,
 updated_at timestamptz not null default clock_timestamp(),updated_by uuid references auth.users
);
alter table private.production_recording_v3_activation enable row level security;
revoke all on private.production_recording_v3_activation from public,anon,authenticated;
insert into private.production_recording_v3_activation(factory_id) select id from public.factories;
create function private.seed_recording_v3_activation() returns trigger language plpgsql security definer set search_path='' as $$
begin insert into private.production_recording_v3_activation(factory_id) values(new.id);return new;end$$;
create trigger zzzz_seed_recording_v3_activation after insert on public.factories for each row execute function private.seed_recording_v3_activation();

alter table public.production_entries
 add column attribution_version smallint,add column recording_kind text,
 add column execution_key text,add column execution_started_at timestamptz,add column execution_finished_at timestamptz,
 add column original_occurrence_key text,add column effective_occurrence_key text,
 add column original_period_start timestamptz,add column original_period_end timestamptz,
 add column effective_period_start timestamptz,add column effective_period_end timestamptz,
 add column time_precision text,add column resource_evidence jsonb,add column attribution_declaration boolean,
 add column request_payload_version smallint,add column request_payload jsonb,
 add column accepted_at timestamptz,add column request_receipt jsonb,
 add column weight_basis text,add column standard_basis text,
 add foreign key(factory_id,original_occurrence_key) references private.production_shift_occurrences(factory_id,occurrence_key),
 add foreign key(factory_id,effective_occurrence_key) references private.production_shift_occurrences(factory_id,occurrence_key),
 add constraint recording_v3_shape check ((
 (attribution_version is null and execution_key is null and original_occurrence_key is null and effective_occurrence_key is null
  and original_period_start is null and original_period_end is null and effective_period_start is null and effective_period_end is null)
 or (attribution_version=1 and request_payload_version=1 and recording_kind in ('ACTIVE_ORDINARY','LATE_ORDINARY') and input_lot_id is null
  and line_id is not null and execution_key ~ '^[0-9a-f]{64}$' and execution_started_at is not null
  and original_occurrence_key is not null and effective_occurrence_key is not null
  and original_period_start is not null and original_period_end>=original_period_start
  and effective_period_start is not null and effective_period_end>=effective_period_start and time_precision='SHIFT_PERIOD'
  and (recording_kind<>'LATE_ORDINARY' or (execution_finished_at>execution_started_at and original_period_end>original_period_start)))) is true)
 ,add constraint recording_payload_shape check((request_payload_version is null or
 (request_payload_version=1 and jsonb_typeof(request_payload)='object' and octet_length(request_payload::text)<=16384)) is true);
create index on public.production_entries(factory_id,effective_occurrence_key,created_at,id) where attribution_version=1;
alter table public.production_entry_corrections
 add column previous_occurrence_key text,add column corrected_occurrence_key text,
 add column previous_period_start timestamptz,add column previous_period_end timestamptz,
 add column corrected_period_start timestamptz,add column corrected_period_end timestamptz,
 add column attribution_changed boolean not null default false,
 add foreign key(factory_id,previous_occurrence_key) references private.production_shift_occurrences(factory_id,occurrence_key),
 add foreign key(factory_id,corrected_occurrence_key) references private.production_shift_occurrences(factory_id,occurrence_key);
alter table public.finished_goods_sources add column origin_occurrence_key text,add column origin_execution_key text,
 add foreign key(factory_id,origin_occurrence_key) references private.production_shift_occurrences(factory_id,occurrence_key);

-- Reuse the effective permission catalogue, supplement only its transaction-now expiry branch.
create function private.recording_v3_authorize(f uuid) returns void language plpgsql volatile security definer set search_path='' as $$
declare stamp timestamptz:=clock_timestamp();begin
 perform private.require_permission(f,'orders','view');perform private.require_permission(f,'orders','edit');
 if not ((private.is_platform_admin() and exists(select 1 from private.platform_scopes where factory_id=f and user_id=auth.uid() and expires_at>stamp))
 or (exists(select 1 from public.memberships where factory_id=f and user_id=auth.uid() and status='approved')
 or exists(select 1 from public.support_access where factory_id=f and user_id=auth.uid() and (mode='permanent' or (mode='temporary' and expires_at>stamp))))
 and exists(select 1 from private.effective_person_permissions(f,auth.uid()) where module='orders' and action='view')
 and exists(select 1 from private.effective_person_permissions(f,auth.uid()) where module='orders' and action='edit'))
 then raise exception 'permission_denied' using errcode='42501';end if;
end$$;
create function private.recording_canonical_value(v jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
declare result jsonb;begin
 case jsonb_typeof(v)
 when 'number' then return to_jsonb(trim_scale((v#>>'{}')::numeric));
 when 'object' then select coalesce(jsonb_object_agg(key,private.recording_canonical_value(value)),'{}') into result from jsonb_each(v);return result;
 when 'array' then select coalesce(jsonb_agg(private.recording_canonical_value(value) order by ordinality),'[]') into result from jsonb_array_elements(v) with ordinality;return result;
 else return v;end case;
end$$;
create function private.recording_request_payload(f uuid,p jsonb) returns jsonb language plpgsql stable set search_path='' set timezone='UTC' as $$
declare k text;v jsonb;n jsonb;ctx jsonb;begin
 if p is null or jsonb_typeof(p)<>'object' or octet_length(p::text)>16384 or exists(select 1 from jsonb_object_keys(p) as keys(key) where keys.key not in
 ('unit_kind','production_unit','item','technician','good','discarded_quantity','scrap_kg','startup_kg','notes','confirm_overproduction','shift','shift_override_reason','unfinished','remaining_work','input_lot','input_quantity','startup_id','startup_at','recording_context'))
 then raise exception 'recording_invalid_payload' using errcode='22023';end if;
 n:=jsonb_build_object('startup_kg',0,'notes','','confirm_overproduction',false,'shift',null,'shift_override_reason',null,'unfinished',0,'remaining_work','','input_lot',null,'input_quantity',0,'startup_id',null,'startup_at',null)||p;
 foreach k in array array['startup_kg','unfinished','input_quantity','notes','remaining_work','confirm_overproduction'] loop
  if n->k='null'::jsonb then n:=jsonb_set(n,array[k],case when k in ('notes','remaining_work') then '""'::jsonb when k='confirm_overproduction' then 'false'::jsonb else '0'::jsonb end);end if;
 end loop;
 foreach k in array array['production_unit','item','technician','shift','input_lot','startup_id'] loop
  if n->>k is not null then n:=jsonb_set(n,array[k],to_jsonb((n->>k)::uuid));end if;
 end loop;
 foreach k in array array['good','discarded_quantity','scrap_kg','startup_kg','unfinished','input_quantity'] loop
  if jsonb_typeof(n->k) is distinct from 'number' or (n->>k)::numeric<0 or (n->>k)::numeric::text in ('NaN','Infinity','-Infinity')
  then raise exception 'recording_invalid_payload' using errcode='22023';end if;
 end loop;
 if jsonb_typeof(n->'confirm_overproduction')<>'boolean' or jsonb_typeof(n->'notes')<>'string' or jsonb_typeof(n->'remaining_work')<>'string'
 then raise exception 'recording_invalid_payload' using errcode='22023';end if;
 n:=jsonb_set(n,'{remaining_work}',to_jsonb(btrim(n->>'remaining_work')));
 n:=jsonb_set(n,'{shift_override_reason}',coalesce(to_jsonb(nullif(btrim(n->>'shift_override_reason'),'')),'null'));
 if n->>'startup_at' is not null then
  if n->>'startup_at' !~ '(Z|[+-][0-9]{2}:[0-9]{2})$' or not isfinite((n->>'startup_at')::timestamptz) then raise exception 'recording_invalid_payload' using errcode='22023';end if;
  n:=jsonb_set(n,'{startup_at}',to_jsonb(to_char((n->>'startup_at')::timestamptz,'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));
 end if;
 if p ? 'recording_context' then
  ctx:=p->'recording_context';
  if jsonb_typeof(ctx)<>'object' or not (ctx ?& array['version','execution_key','occurrence_key','context_hash','current_shift_quantity_confirmed'])
  or (select count(*) from jsonb_object_keys(ctx))<>5 or ctx->'version'<>'3'::jsonb
  or jsonb_typeof(ctx->'current_shift_quantity_confirmed')<>'boolean'
  or coalesce(ctx->>'execution_key','') !~ '^[0-9a-f]{64}$' or coalesce(ctx->>'occurrence_key','') !~ '^[0-9a-f]{64}$'
  or coalesce(ctx->>'context_hash','') !~ '^[0-9a-f]{64}$' or n->>'input_lot' is not null
  then raise exception 'recording_invalid_context' using errcode='22023';end if;
 end if;
 return private.recording_canonical_value(jsonb_build_object('version',1,'actor',auth.uid(),'factory',f,'command','record_lean_production','payload',n));
end$$;

-- Called only after factory/structure/request serialization, never trust client classification.
create function private.recording_v3_context(f uuid,i uuid,p jsonb) returns jsonb language plpgsql volatile security definer set search_path='' set timezone='UTC' as $$
declare job public.production_orders;resolved jsonb;occ jsonb;eligible jsonb;stamp timestamptz;late boolean;gate private.production_recording_v3_activation;begin
 if current_setting('transaction_isolation')<>'read committed' then raise exception 'recording_isolation' using errcode='40001';end if;
 perform private.recording_v3_authorize(f);
 select * into job from public.production_orders where factory_id=f and id=i;
 if not found then raise exception 'recording_stale_context' using errcode='40001';end if;
 late:=job.status='completed';
 if late then
  select * into gate from private.production_recording_v3_activation where factory_id=f for share;
  if gate.enabled is distinct from true or gate.schema_contract_version is distinct from 3 then raise exception 'recording_disabled' using errcode='55000';end if;
 end if;
 select * into job from public.production_orders where factory_id=f and id=i for update;
 stamp:=clock_timestamp();resolved:=private.resolve_production_occurrence(f,stamp);occ:=resolved->'occurrence';
 if resolved->>'available' is distinct from 'true' then raise exception 'recording_shift_unavailable' using errcode='22023';end if;
 eligible:=private.production_recording_eligibility(job,occ,stamp);
 if eligible->>'included' is distinct from 'true' or (not late and eligible->>'active_recording_eligible' is distinct from 'true')
 or p#>>'{recording_context,execution_key}' is distinct from eligible->>'execution_key'
 or p#>>'{recording_context,occurrence_key}' is distinct from occ->>'occurrence_key'
 or p#>>'{recording_context,context_hash}' is distinct from eligible->>'context_hash'
 or p->>'unit_kind' is distinct from 'line' or (p->>'production_unit')::uuid is distinct from job.line_id
 then raise exception 'recording_stale_context' using errcode='40001';end if;
 if job.actual_start<(occ->>'starts_at')::timestamptz and p#>>'{recording_context,current_shift_quantity_confirmed}' is distinct from 'true'
 then raise exception 'recording_shift_declaration' using errcode='22023';end if;
 if p->>'shift' is not null and (p->>'shift')::uuid is distinct from (occ->>'shift_id')::uuid or p->>'shift_override_reason' is not null
 then raise exception 'recording_invalid_context' using errcode='22023';end if;
 if p->>'startup_at' is not null and ((p->>'startup_at')::timestamptz<greatest(job.actual_start,(occ->>'starts_at')::timestamptz)
 or (p->>'startup_at')::timestamptz>coalesce(job.actual_finish,stamp)) then raise exception 'lean_invalid' using errcode='22023';end if;
 perform private.materialize_production_occurrence(f,occ);
 return jsonb_build_object('occurrence',occ,'eligibility',eligible,'kind',case when late then 'LATE_ORDINARY' else 'ACTIVE_ORDINARY' end,
 'start',job.actual_start,'finish',job.actual_finish,'period_start',greatest(job.actual_start,(occ->>'starts_at')::timestamptz),
 'period_end',least(coalesce(job.actual_finish,stamp),(occ->>'ends_at')::timestamptz),'payload',p);
end$$;
-- Verify the exact inherited worker before replacing it with one shared body.
do $guard$ begin
 if (select prosrc from pg_proc where oid='private.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,text,numeric,text,uuid,numeric)'::regprocedure)
 is distinct from $inherited$
declare job public.production_orders;previous public.production_entries;result uuid;total numeric;lot public.unfinished_lots;new_lot uuid;
 at_time timestamptz;automatic uuid;selected uuid;mode text;why text:=nullif(trim(override_reason),'');
begin
 perform private.require_permission(f,'orders','edit');
 perform private.require_permission(f,'orders','view');
 if r is null or technician is null or good is null or scrap is null or good<0 or scrap<0 or good+scrap+coalesce(unfinished,0)<0
   or good::text in ('NaN','Infinity','-Infinity') or scrap::text in ('NaN','Infinity','-Infinity')
   or length(coalesce(n,''))>2000 then raise exception 'recording_invalid_quantity';end if;
 if unfinished is null or unfinished<0 or unfinished::text in ('NaN','Infinity','-Infinity')
 or consumed is null or consumed<0 or consumed::text in ('NaN','Infinity','-Infinity')
 or (unfinished>0 and length(trim(coalesce(work_note,''))) not between 3 and 2000)
 or (input_lot is null and consumed<>0) or (input_lot is not null and consumed<=0)
 then raise exception 'unfinished_invalid';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(f::text||':structure',0));
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(f::text||r::text,0));
 select * into previous from public.production_entries e where e.factory_id=f and e.request_id=r;
 if found then
   if previous.recording_version<>2 or previous.order_id<>i or previous.technician_id<>technician
     or previous.line_id is distinct from (case when kind='line' then u end)
     or previous.work_center_id is distinct from (case when kind='machine' then u end)
     or coalesce(previous.unfinished_quantity,0)<>unfinished or coalesce(previous.remaining_work,'')<>trim(coalesce(work_note,''))
     or previous.input_lot_id is distinct from input_lot or coalesce(previous.input_quantity,0)<>consumed
     or previous.good_quantity<>good or previous.scrap_quantity<>scrap or previous.notes<>coalesce(n,'')
     or (case when previous.shift_assignment_mode is null then previous.original_shift_id else previous.requested_shift_id end) is distinct from shift
     or previous.shift_override_reason is distinct from why
     or previous.created_by<>auth.uid() or previous.overproduction_confirmed<>coalesce(confirmed,false)
     then raise exception 'request_conflict';end if;
   return previous.id;
 end if;
 -- Capture once, after locks: this exact timestamp is persisted and used for attribution.
 at_time:=clock_timestamp();automatic:=private.resolve_factory_shift(f,at_time);
 selected:=coalesce(shift,automatic);mode:='automatic';
 if shift is not null then
   perform private.validate_production_shift(f,shift);
   if shift is distinct from automatic or why is not null then
     if length(coalesce(why,'')) not between 3 and 2000 then raise exception 'shift_override_reason';end if;
     mode:='manual';
   end if;
 elsif why is not null then raise exception 'shift_override_reason';
 elsif automatic is null then
   if exists(select 1 from public.production_shifts where factory_id=f and not archived)
   then raise exception 'shift_no_match';end if;
   mode:='unconfigured';
 end if;
 select * into job from public.production_orders o where o.factory_id=f and o.id=i for update;
 if not found then raise exception 'recording_invalid_unit';end if;
 if input_lot is null then
   if not exists(select 1 from private.production_recording_units(f) x where x.unit_kind=kind and x.unit_id=u and x.item_id=i) then raise exception 'recording_invalid_unit';end if;
 else
   select * into lot from public.unfinished_lots x where x.factory_id=f and x.id=input_lot for update;
   if not found or not exists(select 1 from public.production_entries src where src.factory_id=f and src.id=lot.source_entry_id and src.order_id=i and src.unit=job.unit)
   then raise exception 'unfinished_invalid_lot';end if;
   if lot.quantity_available<consumed then raise exception 'unfinished_insufficient';end if;
   if consumed<>good+scrap+unfinished then raise exception 'unfinished_conservation';end if;
   if not exists(select 1 from private.unfinished_destinations(f,i) x where x.unit_kind=kind and x.unit_id=u) then raise exception 'recording_invalid_unit';end if;
 end if;
 if not exists(select 1 from public.memberships m where m.factory_id=f and m.id=technician and m.status='approved')
   then raise exception 'invalid_operator';end if;
 total:=job.fulfillment_good_quantity+good;
 if total>job.target_quantity and not coalesce(confirmed,false) then raise exception 'recording_overproduction_confirmation';end if;
 insert into public.production_entries(factory_id,order_id,line_id,work_center_id,technician_id,unit,recording_version,
   produced,rejected,good_quantity,scrap_quantity,effective_good,effective_scrap,notes,created_by,created_at,request_id,
   running_good,remaining_quantity,overproduction_confirmed,shift_id,original_shift_id,
   automatic_shift_id,requested_shift_id,shift_assignment_mode,shift_override_reason,shift_override_by,shift_override_at,unfinished_quantity,effective_unfinished,remaining_work,effective_remaining_work,input_lot_id,input_quantity)
 values(f,i,case when kind='line' then u end,case when kind='machine' then u end,technician,job.unit,2,
   good+scrap,scrap,good,scrap,good,scrap,coalesce(n,''),auth.uid(),at_time,r,total,greatest(job.target_quantity-total,0),coalesce(confirmed,false),selected,selected,
   automatic,shift,mode,why,case when mode='manual' then auth.uid() end,case when mode='manual' then at_time end,unfinished,unfinished,trim(coalesce(work_note,'')),trim(coalesce(work_note,'')),input_lot,consumed)
 returning id into result;
 update public.production_orders set produced_quantity=produced_quantity+good+scrap,rejected_quantity=rejected_quantity+scrap where id=i;
 if input_lot is not null then
   update public.unfinished_lots set quantity_available=quantity_available-consumed where id=input_lot;
   insert into public.unfinished_operations(factory_id,lot_id,entry_id,quantity,remaining_work,line_id,work_center_id,created_at,created_by)
   values(f,input_lot,result,consumed,lot.remaining_work,case when kind='line' then u end,case when kind='machine' then u end,at_time,auth.uid());
   insert into public.unfinished_movements(factory_id,lot_id,entry_id,kind,quantity,created_at,created_by)
   values(f,input_lot,result,'consumed',-consumed,at_time,auth.uid());
 end if;
 if unfinished>0 then
   insert into public.unfinished_lots(factory_id,source_entry_id,quantity_created,quantity_available,remaining_work,created_at,created_by)
   values(f,result,unfinished,unfinished,trim(work_note),at_time,auth.uid()) returning id into new_lot;
   insert into public.unfinished_movements(factory_id,lot_id,entry_id,kind,quantity,created_at,created_by)
   values(f,new_lot,result,'created',unfinished,at_time,auth.uid());
 end if;
 return result;
end$inherited$ then raise exception 'recording_worker_contract_changed';end if;
end $guard$;
create function private.record_production(f uuid,kind text,u uuid,i uuid,technician uuid,good numeric,scrap numeric,
 n text,confirmed boolean,r uuid,shift uuid,override_reason text,unfinished numeric,work_note text,input_lot uuid,consumed numeric,attribution jsonb,receipt_payload jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare job public.production_orders;previous public.production_entries;result uuid;total numeric;lot public.unfinished_lots;new_lot uuid;
 at_time timestamptz;automatic uuid;selected uuid;mode text;why text:=nullif(trim(override_reason),'');
begin
 perform private.require_permission(f,'orders','edit');
 perform private.require_permission(f,'orders','view');
 if r is null or technician is null or good is null or scrap is null or good<0 or scrap<0 or good+scrap+coalesce(unfinished,0)<0
   or good::text in ('NaN','Infinity','-Infinity') or scrap::text in ('NaN','Infinity','-Infinity')
   or length(coalesce(n,''))>2000 then raise exception 'recording_invalid_quantity';end if;
 if unfinished is null or unfinished<0 or unfinished::text in ('NaN','Infinity','-Infinity')
 or consumed is null or consumed<0 or consumed::text in ('NaN','Infinity','-Infinity')
 or (unfinished>0 and length(trim(coalesce(work_note,''))) not between 3 and 2000)
 or (input_lot is null and consumed<>0) or (input_lot is not null and consumed<=0)
 then raise exception 'unfinished_invalid';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(f::text||':structure',0));
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(f::text||r::text,0));
 select * into previous from public.production_entries e where e.factory_id=f and e.request_id=r;
 if found then
   if previous.recording_version<>2 or previous.order_id<>i or previous.technician_id<>technician
     or previous.line_id is distinct from (case when kind='line' then u end)
     or previous.work_center_id is distinct from (case when kind='machine' then u end)
     or coalesce(previous.unfinished_quantity,0)<>unfinished or coalesce(previous.remaining_work,'')<>trim(coalesce(work_note,''))
     or previous.input_lot_id is distinct from input_lot or coalesce(previous.input_quantity,0)<>consumed
     or previous.good_quantity<>good or previous.scrap_quantity<>scrap or previous.notes<>coalesce(n,'')
     or (case when previous.shift_assignment_mode is null then previous.original_shift_id else previous.requested_shift_id end) is distinct from shift
     or previous.shift_override_reason is distinct from why
     or previous.created_by<>auth.uid() or previous.overproduction_confirmed<>coalesce(confirmed,false)
     then raise exception 'request_conflict';end if;
   return previous.id;
 end if;
 -- Capture once, after locks: this exact timestamp is persisted and used for attribution.
 at_time:=clock_timestamp();automatic:=case when attribution is not null then (attribution#>>'{occurrence,shift_id}')::uuid else private.resolve_factory_shift(f,at_time) end;
 selected:=coalesce(shift,automatic);mode:='automatic';
 if attribution is null and shift is not null then
   perform private.validate_production_shift(f,shift);
   if shift is distinct from automatic or why is not null then
     if length(coalesce(why,'')) not between 3 and 2000 then raise exception 'shift_override_reason';end if;
     mode:='manual';
   end if;
 elsif why is not null then raise exception 'shift_override_reason';
 elsif automatic is null then
   if exists(select 1 from public.production_shifts where factory_id=f and not archived)
   then raise exception 'shift_no_match';end if;
   mode:='unconfigured';
 end if;
 select * into job from public.production_orders o where o.factory_id=f and o.id=i for update;
 if not found then raise exception 'recording_invalid_unit';end if;
 if input_lot is null then
   if attribution->>'kind' is distinct from 'LATE_ORDINARY' and not exists(select 1 from private.production_recording_units(f) x where x.unit_kind=kind and x.unit_id=u and x.item_id=i) then raise exception 'recording_invalid_unit';end if;
 else
   select * into lot from public.unfinished_lots x where x.factory_id=f and x.id=input_lot for update;
   if not found or not exists(select 1 from public.production_entries src where src.factory_id=f and src.id=lot.source_entry_id and src.order_id=i and src.unit=job.unit)
   then raise exception 'unfinished_invalid_lot';end if;
   if lot.quantity_available<consumed then raise exception 'unfinished_insufficient';end if;
   if consumed<>good+scrap+unfinished then raise exception 'unfinished_conservation';end if;
   if not exists(select 1 from private.unfinished_destinations(f,i) x where x.unit_kind=kind and x.unit_id=u) then raise exception 'recording_invalid_unit';end if;
 end if;
 if not exists(select 1 from public.memberships m where m.factory_id=f and m.id=technician and m.status='approved')
   then raise exception 'invalid_operator';end if;
 total:=job.fulfillment_good_quantity+good;
 if total>job.target_quantity and not coalesce(confirmed,false) then raise exception 'recording_overproduction_confirmation';end if;
 insert into public.production_entries(factory_id,order_id,line_id,work_center_id,technician_id,unit,recording_version,
   produced,rejected,good_quantity,scrap_quantity,effective_good,effective_scrap,notes,created_by,created_at,request_id,
   running_good,remaining_quantity,overproduction_confirmed,shift_id,original_shift_id,
   automatic_shift_id,requested_shift_id,shift_assignment_mode,shift_override_reason,shift_override_by,shift_override_at,unfinished_quantity,effective_unfinished,remaining_work,effective_remaining_work,input_lot_id,input_quantity,
 attribution_version,recording_kind,execution_key,execution_started_at,execution_finished_at,original_occurrence_key,effective_occurrence_key,
 original_period_start,original_period_end,effective_period_start,effective_period_end,time_precision,resource_evidence,attribution_declaration,request_payload_version,request_payload,weight_basis,standard_basis)
 values(f,i,case when kind='line' then u end,case when kind='machine' then u end,technician,job.unit,2,
   good+scrap,scrap,good,scrap,good,scrap,coalesce(n,''),auth.uid(),at_time,r,total,greatest(job.target_quantity-total,0),coalesce(confirmed,false),selected,selected,
   automatic,shift,mode,why,case when mode='manual' then auth.uid() end,case when mode='manual' then at_time end,unfinished,unfinished,trim(coalesce(work_note,'')),trim(coalesce(work_note,'')),input_lot,consumed,
 case when attribution is not null then 1 end,case when attribution is not null then attribution->>'kind' when input_lot is not null then 'WIP_PROCESSING' end,
 attribution#>>'{eligibility,execution_key}',(attribution->>'start')::timestamptz,(attribution->>'finish')::timestamptz,
 attribution#>>'{occurrence,occurrence_key}',attribution#>>'{occurrence,occurrence_key}',
 (attribution->>'period_start')::timestamptz,case when attribution->>'kind'='ACTIVE_ORDINARY' then least(at_time,(attribution#>>'{occurrence,ends_at}')::timestamptz) else (attribution->>'period_end')::timestamptz end,
 (attribution->>'period_start')::timestamptz,case when attribution->>'kind'='ACTIVE_ORDINARY' then least(at_time,(attribution#>>'{occurrence,ends_at}')::timestamptz) else (attribution->>'period_end')::timestamptz end,
 case when attribution is not null then 'SHIFT_PERIOD' end,attribution#>'{eligibility,resource_evidence}',(attribution#>>'{payload,recording_context,current_shift_quantity_confirmed}')::boolean,
 case when receipt_payload is not null then 1 end,receipt_payload,attribution->>'weight_basis',attribution->>'standard_basis')
 returning id into result;
 update public.production_orders set produced_quantity=produced_quantity+good+scrap,rejected_quantity=rejected_quantity+scrap where id=i;
 if input_lot is not null then
   update public.unfinished_lots set quantity_available=quantity_available-consumed where id=input_lot;
   insert into public.unfinished_operations(factory_id,lot_id,entry_id,quantity,remaining_work,line_id,work_center_id,created_at,created_by)
   values(f,input_lot,result,consumed,lot.remaining_work,case when kind='line' then u end,case when kind='machine' then u end,at_time,auth.uid());
   insert into public.unfinished_movements(factory_id,lot_id,entry_id,kind,quantity,created_at,created_by)
   values(f,input_lot,result,'consumed',-consumed,at_time,auth.uid());
 end if;
 if unfinished>0 then
   insert into public.unfinished_lots(factory_id,source_entry_id,quantity_created,quantity_available,remaining_work,created_at,created_by)
   values(f,result,unfinished,unfinished,trim(work_note),at_time,auth.uid()) returning id into new_lot;
   insert into public.unfinished_movements(factory_id,lot_id,entry_id,kind,quantity,created_at,created_by)
   values(f,new_lot,result,'created',unfinished,at_time,auth.uid());
 end if;
 return result;
end$$;

create or replace function private.record_production(f uuid,kind text,u uuid,i uuid,technician uuid,good numeric,scrap numeric,n text,confirmed boolean,r uuid,shift uuid,override_reason text,unfinished numeric,work_note text,input_lot uuid,consumed numeric)
returns uuid language sql security definer set search_path='' as $$
 select private.record_production(f,kind,u,i,technician,good,scrap,n,confirmed,r,shift,override_reason,unfinished,work_note,input_lot,consumed,null,null)
$$;

create or replace function private.record_lean_production(f uuid,p jsonb,r uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare job public.production_orders;prod public.products;standard public.lean_standards;startup public.lean_startups;
 e public.production_entries;entry_id uuid;mass numeric;startup_mass numeric;discarded numeric;weight numeric;total_startup numeric;needs_review boolean:=false;canonical jsonb;context jsonb;receipt jsonb;stamp timestamptz;
begin
 perform private.require_permission(f,'orders','edit');perform private.require_permission(f,'orders','view');
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));
 perform private.require_permission(f,'orders','edit');perform private.require_permission(f,'orders','view');
 if r is null then raise exception 'recording_invalid_payload' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended(f::text||':structure',0));
 perform pg_advisory_xact_lock(hashtextextended(f::text||r::text,0));
 perform private.recording_v3_authorize(f);
 canonical:=private.recording_request_payload(f,p);
 select * into e from public.production_entries where factory_id=f and request_id=r;
 if found and e.request_payload_version=1 then
  if e.created_by is distinct from auth.uid() or e.request_payload is distinct from canonical then raise exception 'request_conflict' using errcode='40001';end if;
  return e.request_receipt||jsonb_build_object('replayed',true);
 elsif found and p ? 'recording_context' then raise exception 'request_conflict' using errcode='40001';end if;
 -- Legacy payloads retain the existing worker contract. New receipts cover WIP too.
 if p ? 'recording_context' then
  context:=private.recording_v3_context(f,(p->>'item')::uuid,canonical->'payload');
 end if;
 mass:=(p->>'scrap_kg')::numeric;startup_mass:=coalesce((p->>'startup_kg')::numeric,0);discarded:=(p->>'discarded_quantity')::numeric;
 if mass is null or discarded is null or mass<0 or discarded<0 or startup_mass<0 or startup_mass>mass or mass::text in ('NaN','Infinity','-Infinity') or startup_mass::text in ('NaN','Infinity','-Infinity') or coalesce((p->>'good')::numeric,0)+discarded+coalesce((p->>'unfinished')::numeric,0)+mass<=0 then raise exception 'lean_invalid' using errcode='22023';end if;
 select * into job from public.production_orders where factory_id=f and id=(p->>'item')::uuid;
 select * into prod from public.products where factory_id=f and id=job.product_id;
 weight:=case when job.unit='kg' then 1 when job.unit=prod.stock_unit then prod.unit_weight_kg end;
 select * into standard from public.lean_standards where factory_id=f and line_id=job.line_id and product_id=job.product_id;
 if context is not null then context:=context||jsonb_build_object('weight_basis',case when weight is null then 'UNKNOWN' else 'RECORDING_CONFIG' end,
 'standard_basis',case when standard.id is null then 'UNKNOWN' else 'RECORDING_CONFIG' end);end if;
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
 (p->>'shift')::uuid,p->>'shift_override_reason',coalesce((p->>'unfinished')::numeric,0),coalesce(p->>'remaining_work',''),(p->>'input_lot')::uuid,coalesce((p->>'input_quantity')::numeric,0),context,case when e.id is null then canonical end);
 select * into e from public.production_entries where id=entry_id;
 if e.original_scrap_kg is not null then
  if e.original_scrap_kg<>mass or e.original_startup_kg<>startup_mass or e.lean_startup_id is distinct from startup.id then raise exception 'recording_request_reused' using errcode='22023';end if;
 else
  update public.production_entries set original_scrap_kg=mass,effective_scrap_kg=mass,original_startup_kg=startup_mass,effective_startup_kg=startup_mass,
  weight_kg_per_unit=weight,produced_weight_kg=(effective_good+coalesce(effective_unfinished,0))*weight,lean_startup_id=startup.id,
  running_standard_percent=standard.running_percent,scrap_standard_revision=standard.revision where id=entry_id returning * into e;
 end if;
 if e.request_payload_version is null then
  -- Pre-M2 committed legacy requests keep their original replay behavior.
  return private.lean_scrap_assessment(f,entry_id)||jsonb_build_object('id',entry_id);
 end if;
 -- Validate the final KG/stock/source state before the final admission guard.
 set constraints public.lean_entry_physical_output,public.quality_entry_weight_check,public.source_balance_conservation,public.source_receipt_conservation immediate;
 perform private.recording_v3_authorize(f);stamp:=clock_timestamp();
 if context is not null and (stamp<(context#>>'{occurrence,starts_at}')::timestamptz or stamp>=(context#>>'{occurrence,ends_at}')::timestamptz)
 then raise exception 'recording_shift_expired' using errcode='22023';end if;
 receipt:=private.lean_scrap_assessment(f,entry_id)||jsonb_build_object('id',entry_id,'entry_id',entry_id,'request_id',r,
 'contract_version',3,'outcome','COMMITTED','replayed',false,'recorded_at',e.created_at,'accepted_at',stamp,
 'original_payload',canonical->'payload','payload_identity',encode(sha256(convert_to(canonical::text,'UTF8')),'hex'),
 'recording_kind',e.recording_kind,'occurrence_key',e.original_occurrence_key);
 update public.production_entries set accepted_at=stamp,request_receipt=receipt where id=entry_id;
 set constraints public.recording_receipt_finalized immediate;
 -- No subsequent business writes. Recheck after triggers/final constraints, not client time.
 perform private.recording_v3_authorize(f);
 if context is not null and clock_timestamp()>=(context#>>'{occurrence,ends_at}')::timestamptz then raise exception 'recording_shift_expired' using errcode='22023';end if;
 set constraints public.lean_entry_physical_output,public.quality_entry_weight_check,public.source_balance_conservation,public.source_receipt_conservation,public.recording_receipt_finalized deferred;
 return receipt;
end$$;

-- Preserve source arithmetic; copy frozen origin during INSERT rather than today's shift.
create or replace function private.source_movement() returns trigger language plpgsql security definer set search_path='' as $$
declare ctx private.finished_goods_pick_context;src public.finished_goods_sources;e public.production_entries;o public.production_orders;
 pick jsonb;pos integer; amount numeric;used numeric;total numeric:=0;needed numeric;pending numeric;released numeric;r record;
begin
 perform private.fulfillment_lock(new.factory_id);
 insert into private.finished_goods_unattributed values(new.factory_id,new.product_id,new.unit,0) on conflict do nothing;
 if new.stock_delta>0 then
  update private.finished_goods_unattributed set quantity=quantity+new.stock_delta where factory_id=new.factory_id and product_id=new.product_id and unit=new.unit;
  if new.entry_id is not null and new.kind in ('production_receipt','production_correction') then
   select * into e from public.production_entries where factory_id=new.factory_id and id=new.entry_id;
   select * into o from public.production_orders where factory_id=new.factory_id and id=e.order_id;
   if o.product_id is distinct from new.product_id or e.unit is distinct from new.unit then raise exception 'source_identity';end if;
   insert into public.finished_goods_sources(factory_id,entry_id,item_id,product_id,unit,line_id,work_center_id,shift_id,recorded_at,quantity_credited,shift_name,shift_name_ar,shift_date,factory_timezone,origin_occurrence_key,origin_execution_key)
   values(new.factory_id,e.id,o.id,o.product_id,e.unit,e.line_id,e.work_center_id,e.original_shift_id,e.created_at,new.stock_delta,
    case when e.attribution_version=1 then (select name from private.production_shift_occurrences where factory_id=e.factory_id and occurrence_key=e.original_occurrence_key) else (select name from public.production_shifts where factory_id=e.factory_id and id=e.original_shift_id) end,
    case when e.attribution_version=1 then (select name_ar from private.production_shift_occurrences where factory_id=e.factory_id and occurrence_key=e.original_occurrence_key) else (select name_ar from public.production_shifts where factory_id=e.factory_id and id=e.original_shift_id) end,
    case when e.attribution_version=1 then (select business_date from private.production_shift_occurrences where factory_id=e.factory_id and occurrence_key=e.original_occurrence_key) else private.source_shift_date(e.factory_id,e.original_shift_id,e.created_at) end,
    case when e.attribution_version=1 then (select timezone from private.production_shift_occurrences where factory_id=e.factory_id and occurrence_key=e.original_occurrence_key) else (select timezone from public.factories where id=e.factory_id) end,e.original_occurrence_key,e.execution_key)
   on conflict(factory_id,entry_id) do update set quantity_credited=public.finished_goods_sources.quantity_credited+excluded.quantity_credited;
  end if;
 elsif new.stock_delta<0 then
  needed:=-new.stock_delta;
  select * into ctx from private.finished_goods_pick_context where backend=pg_backend_pid() and transaction_id=txid_current();
  if found then
   if ctx.factory_id<>new.factory_id or ctx.actor_id is distinct from auth.uid() or ctx.kind<>new.kind
   or (ctx.product_id is not null and ctx.product_id<>new.product_id) or (ctx.unit is not null and ctx.unit<>new.unit)
   or (ctx.entry_id is not null and ctx.entry_id is distinct from new.entry_id) then raise exception 'source_identity';end if;
   for pick,pos in select value,ordinality::integer from jsonb_array_elements(ctx.picks) with ordinality loop
    if new.kind='dispatch' and (pick->>'sales_line_id')::uuid is distinct from new.sales_line_id then continue;end if;
    select coalesce(quantity,0) into used from private.finished_goods_pick_usage where backend=pg_backend_pid() and transaction_id=txid_current() and position=pos;
    amount:=(pick->>'quantity')::numeric-coalesce(used,0);
    if amount<=0 then continue;end if;
    if amount>needed-total then raise exception 'source_quantity';end if;
    if pick->>'source_id' is null then
     update private.finished_goods_unattributed set quantity=quantity-amount where factory_id=new.factory_id and product_id=new.product_id and unit=new.unit and quantity>=amount;
     if not found then raise exception 'source_unavailable';end if;
    else
     select * into src from public.finished_goods_sources where factory_id=new.factory_id and id=(pick->>'source_id')::uuid for update;
     if src.id is null or src.product_id<>new.product_id or src.unit<>new.unit or src.physical_label is null
     or src.quantity_available-private.source_reserved(new.factory_id,src.id)<amount then raise exception 'source_unavailable';end if;
     if new.kind in ('production_correction','quality_rejection') and src.entry_id is distinct from new.entry_id then raise exception 'source_identity';end if;
     update public.finished_goods_sources set quantity_available=quantity_available-amount,
      quantity_identified=quantity_identified-case when new.kind='production_correction' then amount else 0 end where id=src.id;
    end if;
    insert into public.finished_goods_source_allocations(factory_id,movement_id,source_id,quantity) values(new.factory_id,new.id,(pick->>'source_id')::uuid,amount);
    insert into private.finished_goods_pick_usage values(pg_backend_pid(),txid_current(),pos,amount)
     on conflict(backend,transaction_id,position) do update set quantity=private.finished_goods_pick_usage.quantity+excluded.quantity;
    total:=total+amount;
   end loop;
   if total<>needed then raise exception 'source_quantity';end if;
  else
   -- Old clients can still use pooled stock, but cannot silently pick an identified batch.
   update private.finished_goods_unattributed set quantity=quantity-needed where factory_id=new.factory_id and product_id=new.product_id and unit=new.unit and quantity>=needed;
   if not found then raise exception 'source_selection_required';end if;
   insert into public.finished_goods_source_allocations(factory_id,movement_id,quantity) values(new.factory_id,new.id,needed);
  end if;
  if new.kind='production_correction' then
   if exists(select 1 from public.finished_goods_sources where factory_id=new.factory_id and entry_id=new.entry_id) then
    update public.finished_goods_sources set quantity_credited=greatest(quantity_credited-needed,0)
     where factory_id=new.factory_id and entry_id=new.entry_id and greatest(quantity_credited-needed,0)>=quantity_identified;
    if not found then raise exception 'source_correction_unavailable';end if;
   end if;
  end if;
 end if;
 if new.reserved_delta<0 then
  -- Release unallocated commitments first; release identified assignments only as needed.
  select coalesce(sum(quantity),0) into pending from public.finished_goods_source_reservations where factory_id=new.factory_id and sales_line_id=new.sales_line_id;
  select greatest(pending-coalesce(quantity,0),0) into released from public.finished_goods_reservations where factory_id=new.factory_id and line_id=new.sales_line_id;
  released:=coalesce(released,pending);
  for r in select * from public.finished_goods_source_reservations where factory_id=new.factory_id and sales_line_id=new.sales_line_id order by source_id for update loop
   amount:=least(released,r.quantity);exit when amount<=0;
   if amount=r.quantity then delete from public.finished_goods_source_reservations where factory_id=r.factory_id and sales_line_id=r.sales_line_id and source_id=r.source_id;
   else update public.finished_goods_source_reservations set quantity=quantity-amount where factory_id=r.factory_id and sales_line_id=r.sales_line_id and source_id=r.source_id;end if;
   released:=released-amount;
  end loop;
 end if;
 return new;
end$$;

create or replace function private.correct_lean_production(f uuid,p jsonb,r uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare e public.production_entries;correction public.production_entry_corrections;result uuid;mass numeric;startup_mass numeric;target private.production_shift_occurrences;period_start timestamptz;period_end timestamptz;job public.production_orders;
begin
 perform private.require_permission(f,'orders','edit');perform private.require_permission(f,'orders','view');
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));
 perform private.require_permission(f,'orders','edit');perform private.require_permission(f,'orders','view');
 if p is null or jsonb_typeof(p)<>'object' or exists(select 1 from jsonb_object_keys(p) key where key not in
 ('entry','good','discarded_quantity','scrap_kg','startup_kg','reason','confirm_overproduction','shift','change_shift','unfinished','remaining_work','corrected_occurrence_key')) then raise exception 'lean_invalid' using errcode='22023';end if;
 select * into e from public.production_entries where factory_id=f and id=(p->>'entry')::uuid;
 if not found then raise exception 'not_found' using errcode='P0002';end if;
 if e.attribution_version=1 and coalesce((p->>'change_shift')::boolean,false) then
  select * into target from private.production_shift_occurrences where factory_id=f and occurrence_key=p->>'corrected_occurrence_key';
  select * into job from public.production_orders where factory_id=f and id=e.order_id;
  period_start:=greatest(e.execution_started_at,target.starts_at);
  period_end:=least(coalesce(job.actual_finish,e.created_at),e.created_at,target.ends_at);
  if target.occurrence_key is null or target.shift_id is distinct from (p->>'shift')::uuid or period_end<=period_start
  then raise exception 'recording_dated_correction_required' using errcode='22023';end if;
 elsif p ? 'corrected_occurrence_key' then raise exception 'recording_dated_correction_invalid' using errcode='22023';end if;
 mass:=(p->>'scrap_kg')::numeric;startup_mass:=coalesce((p->>'startup_kg')::numeric,0);
 if mass is null or mass<0 or startup_mass<0 or startup_mass>mass or mass::text in ('NaN','Infinity','-Infinity') or startup_mass::text in ('NaN','Infinity','-Infinity') or (startup_mass>0 and e.lean_startup_id is null) then raise exception 'lean_invalid' using errcode='22023';end if;
 select * into correction from public.production_entry_corrections where factory_id=f and request_id=r;
 if found and (correction.corrected_scrap_kg is distinct from mass or correction.corrected_startup_kg is distinct from startup_mass) then raise exception 'recording_request_reused' using errcode='22023';end if;
 if correction.id is not null and e.attribution_version=1 and correction.corrected_occurrence_key is distinct from coalesce(target.occurrence_key,e.effective_occurrence_key)
 then raise exception 'request_conflict' using errcode='40001';end if;
 result:=private.correct_production(f,e.id,(p->>'good')::numeric,(p->>'discarded_quantity')::numeric,p->>'reason',coalesce((p->>'confirm_overproduction')::boolean,false),r,
 (p->>'shift')::uuid,coalesce((p->>'change_shift')::boolean,false),coalesce((p->>'unfinished')::numeric,0),coalesce(p->>'remaining_work',''));
 if correction.id is null then
  update public.production_entry_corrections set previous_scrap_kg=e.effective_scrap_kg,corrected_scrap_kg=mass,previous_startup_kg=e.effective_startup_kg,corrected_startup_kg=startup_mass where id=result;
  update public.production_entries set effective_scrap_kg=mass,effective_startup_kg=startup_mass,produced_weight_kg=(effective_good+coalesce(effective_unfinished,0))*weight_kg_per_unit where id=e.id;
 end if;
 if correction.id is null and e.attribution_version=1 then
  update public.production_entry_corrections set previous_occurrence_key=e.effective_occurrence_key,
   corrected_occurrence_key=coalesce(target.occurrence_key,e.effective_occurrence_key),previous_period_start=e.effective_period_start,previous_period_end=e.effective_period_end,
   corrected_period_start=coalesce(period_start,e.effective_period_start),corrected_period_end=coalesce(period_end,e.effective_period_end),
   attribution_changed=target.occurrence_key is not null and target.occurrence_key is distinct from e.effective_occurrence_key where id=result;
  update public.production_entries set effective_occurrence_key=coalesce(target.occurrence_key,e.effective_occurrence_key),
   effective_period_start=coalesce(period_start,e.effective_period_start),effective_period_end=coalesce(period_end,e.effective_period_end) where id=e.id;
 end if;
 return result;
end$$;

create or replace function public.source_stock_command(factory uuid,operation text,payload jsonb,allocations jsonb,request_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare old uuid;result uuid;p jsonb:=jsonb_build_object('payload',payload,'allocations',allocations);
 src public.finished_goods_sources;q numeric;label text;line record;stock public.material_requests;e public.production_entries;item public.production_orders;allowed text[];
begin
 perform private.require_permission(factory,'factory','view');
 if payload is null or jsonb_typeof(payload)<>'object' or octet_length(p::text)>30000 then raise exception 'source_quantity';end if;
 if jsonb_typeof(allocations) is distinct from 'array' or jsonb_array_length(allocations)>100 or request_id is null then raise exception 'source_quantity';end if;
 allowed:=case operation when 'identify' then array['source','quantity','label','physically_identified','note'] when 'mix' then array['source','quantity','physically_identified','note']
  when 'reserve' then array['sales_line_id'] when 'dispatch' then array['sales_order','line'] when 'adjust' then array['product','unit','quantity','reason']
  when 'issue' then array['id','revision','reason'] when 'correct' then array['entry','good','discarded_quantity','scrap_kg','startup_kg','reason','confirm_overproduction','shift','change_shift','unfinished','remaining_work','corrected_occurrence_key'] end;
 if allowed is null or exists(select 1 from jsonb_object_keys(payload)k where not(k=any(allowed))) then raise exception 'source_quantity';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));
 perform private.fulfillment_lock(factory);
 perform private.require_permission(factory,'factory','view');
 if operation in ('identify','mix','adjust') then perform private.require_permission(factory,'warehouse','edit');
 elsif operation in ('dispatch','issue','reserve') then perform private.require_permission(factory,'warehouse','issue');
 elsif operation='correct' then perform private.require_permission(factory,'orders','edit');perform private.require_permission(factory,'orders','view');
 else raise exception 'source_quantity';end if;
 old:=private.fulfillment_retry(factory,request_id,'source_'||operation,p);if old is not null then return old;end if;
 if operation in ('identify','mix') then
  select * into src from public.finished_goods_sources where factory_id=factory and id=(payload->>'source')::uuid for update;
  q:=(payload->>'quantity')::numeric;label:=btrim(payload->>'label');
  if src.id is null or q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity') or payload->>'physically_identified' is distinct from 'true'
  or length(coalesce(payload->>'note',''))>2000 then raise exception 'source_identity';end if;
  if operation='identify' then
   if length(coalesce(label,'')) not between 1 and 200 or (src.physical_label is not null and src.physical_label<>label)
   or q>src.quantity_credited-src.quantity_identified then raise exception 'source_identity';end if;
   update private.finished_goods_unattributed set quantity=quantity-q where factory_id=factory and product_id=src.product_id and unit=src.unit and quantity>=q;
   if not found then raise exception 'source_unavailable';end if;
   update public.finished_goods_sources set quantity_identified=quantity_identified+q,quantity_available=quantity_available+q,
    physical_label=label,identified_by=auth.uid(),identified_at=clock_timestamp() where id=src.id;
  else
   if q>src.quantity_available-private.source_reserved(factory,src.id) then raise exception 'source_committed';end if;
   label:=src.physical_label;
   update public.finished_goods_sources set quantity_available=quantity_available-q where id=src.id;
   update private.finished_goods_unattributed set quantity=quantity+q where factory_id=factory and product_id=src.product_id and unit=src.unit;
  end if;
  insert into public.finished_goods_identification_events(factory_id,source_id,quantity,physical_label,note,created_by)
   values(factory,src.id,case when operation='identify' then q else -q end,label,coalesce(payload->>'note',''),auth.uid()) returning id into result;
 elsif operation='reserve' then
  perform private.source_assign_reservation(factory,(payload->>'sales_line_id')::uuid,allocations);result:=(payload->>'sales_line_id')::uuid;
 elsif operation='dispatch' then
  if jsonb_typeof(allocations) is distinct from 'array' or exists(select 1 from jsonb_array_elements(allocations)a
   where not exists(select 1 from public.sales_order_lines l where l.factory_id=factory and l.order_id=(payload->>'sales_order')::uuid and l.id=(a->>'sales_line_id')::uuid
    and (payload->>'line' is null or l.id=(payload->>'line')::uuid))) then raise exception 'source_identity';end if;
  for line in select l.id from public.sales_order_lines l where l.factory_id=factory and l.order_id=(payload->>'sales_order')::uuid
   and l.dispatched_quantity<l.quantity and (payload->>'line' is null or l.id=(payload->>'line')::uuid) order by l.id loop
   perform private.source_assign_reservation(factory,line.id,(select coalesce(jsonb_agg(a),'[]') from jsonb_array_elements(allocations)a where a->>'sales_line_id'=line.id::text));
  end loop;
  perform private.source_begin_pick(factory,'dispatch',null,null,null,allocations);
  result:=public.dispatch_sales_order(factory,(payload->>'sales_order')::uuid,(payload->>'line')::uuid,gen_random_uuid());
  perform private.source_end_pick();
 elsif operation='adjust' then
  if (payload->>'quantity')::numeric>=0 then raise exception 'source_quantity';end if;
  perform private.source_begin_pick(factory,'adjustment',(payload->>'product')::uuid,payload->>'unit',null,allocations);
  result:=public.adjust_finished_stock(factory,(payload->>'product')::uuid,payload->>'unit',(payload->>'quantity')::numeric,payload->>'reason',gen_random_uuid());
  perform private.source_end_pick();
 elsif operation='issue' then
  select * into stock from public.material_requests where factory_id=factory and id=(payload->>'id')::uuid;
  if stock.product_id is null then raise exception 'source_identity';end if;
  perform private.source_begin_pick(factory,'material_issue',stock.product_id,stock.unit,null,allocations);
  result:=public.supply_command(factory,'material_change',payload||jsonb_build_object('action','issue'),gen_random_uuid());
  perform private.source_end_pick();
 elsif operation='correct' then
  select * into e from public.production_entries where factory_id=factory and id=(payload->>'entry')::uuid;
  select * into item from public.production_orders where factory_id=factory and id=e.order_id;
  if (payload->>'good')::numeric>=e.effective_good then raise exception 'source_quantity';end if;
  perform private.source_begin_pick(factory,'production_correction',item.product_id,e.unit,e.id,allocations);
  result:=public.correct_lean_production(factory,payload,gen_random_uuid());perform private.source_end_pick();
 end if;
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'source_'||operation,p,result,clock_timestamp());return result;
end$$;

create or replace function private.maintenance_recording_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare p uuid;stamp timestamptz;context jsonb;begin
 perform private.maintenance_planning_lock(new.factory_id);stamp:=clock_timestamp();
 if new.recording_kind='LATE_ORDINARY' then
  context:=private.recording_v3_context(new.factory_id,new.order_id,new.request_payload->'payload');
  if new.input_lot_id is not null or context->>'kind'<>'LATE_ORDINARY'
   or new.execution_key is distinct from context#>>'{eligibility,execution_key}'
   or new.original_occurrence_key is distinct from context#>>'{occurrence,occurrence_key}'
   or new.original_period_start is distinct from (context->>'period_start')::timestamptz
   or new.original_period_end is distinct from (context->>'period_end')::timestamptz
  then raise exception 'recording_invalid_context' using errcode='22023';end if;
  return new;
 end if;
 select product_id into p from public.production_orders where factory_id=new.factory_id and id=new.order_id;
 perform private.maintenance_assert_capacity(new.factory_id,new.line_id,p,new.work_center_id,stamp,stamp+interval '1 microsecond',null,new.order_id,false);
 return new;
end$$;

create function private.recording_source_immutable() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='DELETE' then raise exception 'recording_source_immutable' using errcode='22023';end if;
 if row(new.origin_occurrence_key,new.origin_execution_key,new.shift_id,new.shift_name,new.shift_name_ar,new.shift_date,new.factory_timezone)
 is distinct from row(old.origin_occurrence_key,old.origin_execution_key,old.shift_id,old.shift_name,old.shift_name_ar,old.shift_date,old.factory_timezone)
 then raise exception 'recording_source_immutable' using errcode='22023';end if;return new;end$$;
create trigger recording_source_immutable before update or delete on public.finished_goods_sources for each row
 when(old.origin_occurrence_key is not null) execute function private.recording_source_immutable();
create function private.recording_correction_immutable() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='DELETE' then raise exception 'recording_correction_immutable' using errcode='22023';end if;
 if row(new.previous_occurrence_key,new.corrected_occurrence_key,new.previous_period_start,new.previous_period_end,new.corrected_period_start,new.corrected_period_end,new.attribution_changed)
 is distinct from row(old.previous_occurrence_key,old.corrected_occurrence_key,old.previous_period_start,old.previous_period_end,old.corrected_period_start,old.corrected_period_end,old.attribution_changed)
 then raise exception 'recording_correction_immutable' using errcode='22023';end if;return new;end$$;
create trigger recording_correction_immutable before update or delete on public.production_entry_corrections for each row
 when(old.previous_occurrence_key is not null) execute function private.recording_correction_immutable();
create function private.recording_entry_immutable() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' then raise exception 'recording_receipt_immutable' using errcode='22023';end if;
 if row(new.order_id,new.line_id,new.work_center_id,new.unit,new.technician_id,new.original_shift_id,new.automatic_shift_id,new.requested_shift_id,
 new.shift_assignment_mode,new.shift_override_reason,new.good_quantity,new.scrap_quantity,new.unfinished_quantity,new.remaining_work,new.notes)
 is distinct from row(old.order_id,old.line_id,old.work_center_id,old.unit,old.technician_id,old.original_shift_id,old.automatic_shift_id,old.requested_shift_id,
 old.shift_assignment_mode,old.shift_override_reason,old.good_quantity,old.scrap_quantity,old.unfinished_quantity,old.remaining_work,old.notes)
 or (old.original_scrap_kg is not null and row(new.original_scrap_kg,new.original_startup_kg) is distinct from row(old.original_scrap_kg,old.original_startup_kg))
 then raise exception 'recording_origin_immutable' using errcode='22023';end if;
 if row(new.attribution_version,new.recording_kind,new.execution_key,new.execution_started_at,new.execution_finished_at,
 new.original_occurrence_key,new.original_period_start,new.original_period_end,new.time_precision,new.resource_evidence,new.attribution_declaration,
 new.request_payload_version,new.request_payload,new.created_at,new.created_by,new.request_id,new.weight_basis,new.standard_basis)
 is distinct from row(old.attribution_version,old.recording_kind,old.execution_key,old.execution_started_at,old.execution_finished_at,
 old.original_occurrence_key,old.original_period_start,old.original_period_end,old.time_precision,old.resource_evidence,old.attribution_declaration,
 old.request_payload_version,old.request_payload,old.created_at,old.created_by,old.request_id,old.weight_basis,old.standard_basis)
 then raise exception 'recording_origin_immutable' using errcode='22023';end if;
 if (old.accepted_at is not null or old.request_receipt is not null) and row(new.accepted_at,new.request_receipt) is distinct from row(old.accepted_at,old.request_receipt)
 then raise exception 'recording_receipt_immutable' using errcode='22023';end if;
 if row(new.effective_occurrence_key,new.effective_period_start,new.effective_period_end) is distinct from row(old.effective_occurrence_key,old.effective_period_start,old.effective_period_end)
 and not exists(select 1 from public.production_entry_corrections c where c.factory_id=new.factory_id and c.entry_id=new.id and c.created_by=auth.uid()
 and c.previous_occurrence_key=old.effective_occurrence_key and c.corrected_occurrence_key=new.effective_occurrence_key
 and c.previous_period_start=old.effective_period_start and c.previous_period_end=old.effective_period_end
 and c.corrected_period_start=new.effective_period_start and c.corrected_period_end=new.effective_period_end)
 then raise exception 'recording_attribution_audit_required' using errcode='22023';end if;
 return new;
end$$;
create trigger recording_entry_immutable before update or delete on public.production_entries for each row
 when(old.request_payload_version is not null or old.attribution_version is not null) execute function private.recording_entry_immutable();
create function private.recording_receipt_finalized() returns trigger language plpgsql security definer set search_path='' as $$
declare e public.production_entries;o private.production_shift_occurrences;begin
 select * into e from public.production_entries where id=new.id;
 if e.request_payload_version is not null and (e.accepted_at is null or e.request_receipt is null or e.accepted_at<e.created_at
 or e.request_payload->>'actor' is distinct from e.created_by::text or e.request_payload->>'factory' is distinct from e.factory_id::text
 or e.request_receipt->>'entry_id' is distinct from e.id::text or e.request_receipt->>'request_id' is distinct from e.request_id::text
 or e.request_receipt->>'outcome' is distinct from 'COMMITTED' or (e.request_receipt->>'accepted_at')::timestamptz is distinct from e.accepted_at)
 then raise exception 'recording_receipt_unfinished' using errcode='23514';end if;
 if e.attribution_version=1 then
  select * into o from private.production_shift_occurrences where factory_id=e.factory_id and occurrence_key=e.original_occurrence_key;
  if e.original_period_start<o.starts_at or e.original_period_end>o.ends_at or e.original_period_start<e.execution_started_at
   or e.original_period_end>coalesce(e.execution_finished_at,e.created_at)
   or e.accepted_at<o.starts_at or e.accepted_at>=o.ends_at
  then raise exception 'recording_period_invalid' using errcode='23514';end if;
 end if;return null;
end$$;
create constraint trigger recording_receipt_finalized after insert or update on public.production_entries
 deferrable initially deferred for each row execute function private.recording_receipt_finalized();

create function public.production_recording_request_status(factory uuid,request_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare e public.production_entries;begin
 perform private.recording_v3_authorize(factory);
 if request_id is null then raise exception 'recording_invalid_payload' using errcode='22023';end if;
 select * into e from public.production_entries where factory_id=factory and production_entries.request_id=production_recording_request_status.request_id and created_by=auth.uid();
 if not found or e.request_payload_version is null then return jsonb_build_object('contract_version',3,'outcome','UNKNOWN','request_id',request_id);end if;
 return jsonb_build_object('contract_version',3,'outcome','COMMITTED','receipt',e.request_receipt,
 'current',jsonb_build_object('good',e.effective_good,'discarded_quantity',e.effective_scrap,'unfinished',e.effective_unfinished,
 'scrap_kg',e.effective_scrap_kg,'startup_kg',e.effective_startup_kg,'occurrence_key',e.effective_occurrence_key,
 'correction_id',(select id from public.production_entry_corrections where factory_id=factory and entry_id=e.id order by created_at desc,id desc limit 1)));
end$$;
-- Default PUBLIC execute is removed from every added helper, including the worker overload.
do $$declare fn record;begin
 for fn in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='private' and (p.proname like 'recording_%' or p.proname in ('seed_recording_v3_activation','record_production')) loop
 execute format('revoke all on function %s from public,anon,authenticated',fn.signature);end loop;
end$$;
revoke all on function public.production_recording_request_status(uuid,uuid) from public,anon,authenticated;
grant execute on function public.production_recording_request_status(uuid,uuid) to authenticated;
commit;
