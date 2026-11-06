import fs from'node:fs';import{sql,root,c,guard,quote}from'./local.mjs';
const x=JSON.parse(fs.readFileSync(root+'/acceptance-context.json'));
const profile=sql(`begin;${guard}set local track_functions='all';select set_config('request.jwt.claim.sub',${quote(c.context.owner)},true);
explain(analyze,buffers,format json) select public.record_manufactured_output(${quote(x.factory)},output2_test.payload(${quote(JSON.stringify(x))}::jsonb,1),gen_random_uuid());
select jsonb_agg(to_jsonb(s)) from (select funcname,calls,total_time,self_time from pg_stat_xact_user_functions where calls>0 order by total_time desc limit 25)s;rollback;`);
fs.writeFileSync(root+'/recording-sql-profile.txt',profile);console.log(profile.slice(-4200));
