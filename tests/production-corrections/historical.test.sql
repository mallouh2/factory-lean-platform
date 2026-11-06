do $$declare c public.production_entry_corrections;p jsonb;before text;request_count bigint;begin
 select h.* into c from public.production_entry_corrections h join correction_test.historical b on b.id=h.id order by h.created_at limit 1;
 if c.id is null then return;end if;
 perform set_config('request.jwt.claim.sub',c.created_by::text,false);
 p:=jsonb_build_object('entry',c.entry_id,'good',c.corrected_good::text,'discarded_quantity',c.corrected_scrap::text,'scrap_kg',c.corrected_scrap_kg::text,
 'startup_kg',coalesce(c.corrected_startup_kg,0)::text,'reason',c.reason,'confirm_overproduction',c.overproduction_confirmed,'change_shift',c.shift_changed,
 'shift',c.corrected_shift_id,'unfinished',coalesce(c.corrected_unfinished,0)::text,'remaining_work',coalesce(c.corrected_remaining_work,''));
 if c.shift_changed and c.corrected_occurrence_key is not null then p:=p||jsonb_build_object('corrected_occurrence_key',c.corrected_occurrence_key);end if;
 before:=correction_test.operational();select count(*) into request_count from private.production_correction_requests;
 perform correction_test.ok(public.correct_lean_production(c.factory_id,p,c.request_id)=c.id,'pre-policy correction replay retains original UUID/result');
 perform correction_test.ok(before=correction_test.operational() and request_count=(select count(*) from private.production_correction_requests),'historical replay invents no approval or operational evidence');
end$$;
