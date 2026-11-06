begin;
-- Quality Scrap remains separate from technician Scrap and reviewed Lean cause
-- evidence. Use only the latest authoritative finding, never sum its revisions.
do $patch$declare b text;n text;begin
 b:=pg_get_functiondef('private.quality_read_before_m3c(uuid,jsonb)'::regprocedure);
 n:='select coalesce(sum(r.actual_scrap_kg),0) kg from public.quality_rejections r';
 if position(n in b)=0 then raise exception 'Quality mass projection changed';end if;
 b:=replace(b,n,'select coalesce(private.output_rejected_mass(factory,e.id),0)+coalesce(sum(r.actual_scrap_kg),0) kg from public.quality_rejections r');
 n:='''quality_scrap_kg'',(select coalesce(sum(q.actual_scrap_kg),0)::text';
 if position(n in b)=0 then raise exception 'Quality mass totals changed';end if;
 b:=replace(b,n,'''quality_scrap_kg'',(select (coalesce((select sum(private.output_rejected_mass(factory,d.id)) from data d),0)+coalesce(sum(q.actual_scrap_kg),0))::text');
 execute b;
end$patch$;
commit;
