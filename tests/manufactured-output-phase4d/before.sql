-- Disposable fixture proof that drill-through does not change protected writers.
create table public.local_drillthrough_writer_hashes as
select p.oid,p.oid::regprocedure::text signature,md5(pg_get_functiondef(p.oid)) hash
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in
('record_manufactured_output','manufactured_output_command','reconcile_manufactured_output','receive_manufactured_output','plan_manufactured_completion','revise_manufactured_completion','start_product_item','finish_product_item','source_stock_command','supply_command');
