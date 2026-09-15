-- Support data reads must run through an auditable read-write RPC transaction.
-- Direct REST GET runs read-only: PostgreSQL rejects it if a support read needs an audit entry.
-- Normal factory membership reads keep the ordinary RLS path.
create table private.support_read_receipts(transaction_id xid8 not null,factory_id uuid not null,actor_id uuid not null,entity text not null,created_at timestamptz not null default now(),primary key(transaction_id,factory_id,actor_id,entity));
alter table private.support_read_receipts enable row level security;
create function private.audit_support_read(f uuid,t text) returns boolean language plpgsql security definer set search_path='' as $$declare tx xid8;begin
 if auth.uid() is null then return false;end if;
 if exists(select 1 from public.memberships where factory_id=f and user_id=auth.uid() and status='approved') then return true;end if;
 if not exists(select 1 from public.support_access where factory_id=f and user_id=auth.uid() and (mode='permanent' or (mode='temporary' and expires_at>now()))) then return true;end if;
 tx:=pg_current_xact_id();
 if exists(select 1 from private.support_read_receipts where transaction_id=tx and factory_id=f and actor_id=auth.uid() and entity=t) then return true;end if;
 insert into private.support_read_receipts(transaction_id,factory_id,actor_id,entity) values(tx,f,auth.uid(),t) on conflict do nothing;
 if found then insert into public.audit_logs(factory_id,actor_id,action,entity) values(f,auth.uid(),'READ',t);end if;
 return true;end$$;
revoke all on function private.audit_support_read(uuid,text) from public,anon;
grant execute on function private.audit_support_read(uuid,text) to authenticated;
do $$declare t record;begin
 for t in select table_name from information_schema.columns where table_schema='public' and column_name='factory_id' loop
 execute format('create policy audited_support_reads on public.%I as restrictive for select to authenticated using(private.audit_support_read(factory_id,%L))',t.table_name,t.table_name);
 end loop;
end$$;
create policy audited_support_reads on public.factories as restrictive for select to authenticated using(private.audit_support_read(id,'factories'));
create policy audited_support_logo on storage.objects as restrictive for select to authenticated using(bucket_id<>'factory-logos' or private.audit_support_read((storage.foldername(name))[1]::uuid,'factory_logo'));

create function public.downtime_export_data(factory uuid,from_time timestamptz,to_time timestamptz) returns jsonb language plpgsql security invoker set search_path='' as $$begin
 perform private.require_permission(factory,'reports','export');
 perform private.require_permission(factory,'downtime','view');
 if from_time is null or to_time is null or to_time<=from_time or to_time-from_time>interval '366 days' then raise exception 'invalid_period';end if;
 perform private.record_access(factory,'EXPORT');
 return jsonb_build_object('events',(select coalesce(jsonb_agg(x),'[]') from (select * from public.downtime_events where factory_id=factory and started_at<to_time and (ended_at is null or ended_at>from_time) order by started_at,id limit 20001) x),'centers',(select coalesce(jsonb_agg(x),'[]') from (select id,name,name_ar,line_id,area_id from public.work_centers where factory_id=factory limit 5001) x),'reasons',(select coalesce(jsonb_agg(x),'[]') from (select id,name,name_ar from public.downtime_reasons where factory_id=factory limit 5001) x));
end$$;
revoke all on function public.downtime_export_data(uuid,timestamptz,timestamptz) from public,anon;
grant execute on function public.downtime_export_data(uuid,timestamptz,timestamptz) to authenticated;
