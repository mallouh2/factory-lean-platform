-- Read-only post-browser conservation check in the disposable fixture only.
begin read only;
do $$declare f uuid;n integer;g numeric;k numeric;w numeric;b numeric;s numeric;m numeric;begin
 if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable localhost required';end if;
 select (x->>'factory')::uuid into f from local_preview.context;
 select count(*),sum(good_quantity),sum(effective_scrap_kg),sum(unfinished_quantity) into n,g,k,w from public.production_entries where factory_id=f;
 if n<2 or g<>25+(n-1)*1.25 or k<>0.75+(n-1)*0.05 or w<>2 then raise exception 'Unexpected browser output quantities';end if;
 select sum(on_hand) into b from public.finished_goods_balances where factory_id=f;
 select sum(quantity_credited) into s from public.finished_goods_sources where factory_id=f;
 select sum(stock_delta) into m from public.finished_goods_movements where factory_id=f;
 if g<>b or b<>s or s<>m then raise exception 'Good/source/ledger conservation failure';end if;
 if exists(select 1 from public.finished_goods_balances where factory_id=f and (on_hand<0 or reserved<>0)) then raise exception 'Unexpected reservation or negative balance';end if;
 if exists(select 1 from public.finished_goods_sources where factory_id=f and (quantity_identified<>0 or quantity_available<>0 or physical_label is not null))then raise exception 'Invented physical identification';end if;
 if exists(select 1 from public.production_entries where factory_id=f and (request_receipt is null or request_receipt->>'entry_id'<>id::text or original_occurrence_key is null))then raise exception 'Missing immutable receipt/source attribution';end if;
 if exists(select request_id from public.production_entries where factory_id=f group by request_id having count(*)>1)then raise exception 'Duplicate UUID posting';end if;
 if exists(select 1 from private.production_recording_v3_activation where enabled or schema_contract_version<>0) or exists(select 1 from private.maintenance_planning_activation where enabled)then raise exception 'Activation changed';end if;
 raise notice 'PASS: quantities; ledger; sources; reservations; identification; immutable receipts; source occurrence; UUID uniqueness; disabled gates';
end$$;
select jsonb_build_object('entries',count(*),'good',sum(good_quantity)::text,'scrap_kg',sum(effective_scrap_kg)::text,'wip',sum(unfinished_quantity)::text) from public.production_entries where factory_id=(select (x->>'factory')::uuid from local_preview.context);
rollback;
