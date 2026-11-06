do $$begin if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable localhost only';end if;end$$;
create schema acceptance_test;
create table acceptance_test.checks(label text);
create function acceptance_test.ok(v boolean,label text) returns void language plpgsql as $$begin
 if v is distinct from true then raise exception 'FAIL %',label;end if;insert into acceptance_test.checks values(label);
end$$;
create table acceptance_test.legacy(x jsonb);
create table acceptance_test.historical(kind text,id uuid,data jsonb);
