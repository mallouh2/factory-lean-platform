// Explicit TESTING maintenance tool. Never imported by application/build code.
import fs from 'node:fs/promises';
import process from 'node:process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { calculateProductionLoss } from '../src/utils/production-loss-impact.mjs';
import { baselineEvidence, compareEvidence } from '../src/utils/lean-comparison.mjs';

export const TARGET = Object.freeze({ ref: 'silmfbpjyepalnggwulp', name: 'factory-lean-testing',
  cluster: '7678069749886157684', factory: 'bab9b5da-d78d-4be7-b6d4-bb6afc388c3a',
  schema: '8bfe6bc171665333961d6bfdb09de6ac', actor: 'd699a3ac-fab0-4faf-b958-f3902bc357ba',
  leanActor: 'c94a7c99-7833-51da-aa7c-1edd2592ce71' });
export const CONFIG_TABLES = ['machine_statuses','permissions','role_permissions','roles','support_access',
  'areas','memberships','work_center_alternatives','production_lines','user_permissions','work_centers',
  'factories','downtime_reasons','production_shifts','work_center_categories','permission_packages',
  'permission_package_permissions','member_permission_packages'];
export const CLEANUP = ['supplier_category_links','purchase_request_events','cost_estimates','goods_receipts',
  'operator_assignments','inventory_reservations','improvement_actions','material_requests','status_events',
  'production_receipt_acknowledgments','oee_observations','daily_targets','bom_items','lean_standards',
  'work_center_capabilities','lean_scrap_events','lean_actions','lean_action_templates','lean_saved_comparisons',
  'lean_runtime_contexts','production_routing_steps','production_transfers','production_plan_revisions',
  'downtime_classification_corrections','production_loss_profiles','finished_goods_movements',
  'production_loss_context_snapshots','production_loss_recovery_rates','production_loss_estimates',
  'finished_goods_entry_receipts','fulfillment_commands','production_loss_actuals','unfinished_movements',
  'unfinished_operations','finished_goods_balances','finished_goods_reservations','sales_incoming_allocations',
  'maintenance_commands','inventory_transactions','private.lean_command_retries','private.line_pause_auto_idled',
  'production_entry_corrections','supplier_categories','purchase_orders','bom_versions','lean_initiatives',
  'unfinished_lots','maintenance_requests','purchase_requisitions','lean_problem_settings','downtime_events',
  'production_entries','suppliers','lean_startups','materials','production_orders','production_requests',
  'sales_order_lines','products','sales_orders','audit_logs'];
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const literal = value => value == null ? 'null' : "'" + String(value).replaceAll("'", "''") + "'";
const json = value => literal(JSON.stringify(value)) + '::jsonb';
export function requireTarget(target) {
  if (target !== 'testing') throw new Error('Only the explicit testing target is supported. Localhost shares TESTING.');
  return TARGET;
}
export function validateDay(day) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || new Date(day+'T00:00:00Z').toISOString().slice(0,10)!==day)
    throw new Error('Invalid demo day');
  return day;
}
export const schemaSQL = `select md5(string_agg(definition,E'\\n' order by definition)) as schema_digest from (
 select pg_get_functiondef(p.oid) definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and p.prokind='f'
 union all select n.nspname||'.'||c.relname||':'||pg_get_constraintdef(con.oid) from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private')
 union all select schemaname||'.'||tablename||':'||indexdef from pg_indexes where schemaname in ('public','private')
 union all select n.nspname||'.'||c.relname||':'||pg_get_triggerdef(t.oid) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private') and not t.tgisinternal
 union all select to_jsonb(p)::text from pg_policies p where schemaname in ('public','private')
 union all select to_jsonb(x)::text from information_schema.columns x where table_schema in ('public','private')
 union all select to_jsonb(x)::text from information_schema.role_table_grants x where table_schema in ('public','private')) d`;
export function guardSQL() {
  return `do $guard$ begin
 if (select system_identifier::text from pg_control_system())<>${literal(TARGET.cluster)} then raise exception 'NOT THE PINNED TESTING CLUSTER';end if;
 if (select count(*) from supabase_migrations.schema_migrations)<>79 or not exists(select 1 from supabase_migrations.schema_migrations where version='20261005072541') then raise exception 'Migration baseline changed';end if;
 if not exists(select 1 from public.factories where id=${literal(TARGET.factory)} and is_demo and timezone='Asia/Qatar') or (select count(*) from public.factories)<>1 then raise exception 'Unexpected factory target';end if;
 if (${schemaSQL})<>${literal(TARGET.schema)} then raise exception 'Schema changed; review before reset';end if;
 end $guard$;`;
}
export async function seedSQL(day, { rollback = false } = {}) {
  validateDay(day);
  const template = await fs.readFile(path.join(root,'supabase/seeds/manual_acceptance.sql'),'utf8');
  const deletes = CLEANUP.map(table => {
    const qualified = table.includes('.') ? table : 'public.'+table;
    const clear = table==='production_orders' ? `update public.work_centers set order_id=null,operator_id=null where factory_id=${literal(TARGET.factory)};\n` : '';
    return clear+`delete from ${qualified} where factory_id=${literal(TARGET.factory)};`;
  }).join('\n');
  return template.replaceAll('__GUARD__',guardSQL()).replaceAll('__DELETES__',deletes)
    .replaceAll('__DAY__',literal(day)).replaceAll('__END__',rollback?'rollback;':'commit;');
}
export function lossSQL(inputs) {
  let statements = '';
  for (const { event, samples } of inputs) {
    const estimate = calculateProductionLoss(event,samples,null,Date.now());
    if (estimate.readiness!=='READY') throw new Error(`Incomplete fixture loss ${event.notes}: ${estimate.missing.join(', ')}`);
    statements += `select public.persist_production_loss_estimate(${literal(TARGET.factory)},${literal(event.id)},${literal(TARGET.actor)},${json(estimate)},null);\n`;
  }
  return `begin;${guardSQL()} select set_config('request.jwt.claim.role','service_role',true);select set_config('request.jwt.claim.sub',${literal(TARGET.actor)},true);${statements} commit;`;
}
export function evidenceSQL({checkpoints,entries,occurrences,initiatives,problems,source_revision,as_of}) {
  const statements = [], checks = [];
  for (const initiative of initiatives) {
    const historicalVerification = initiative.completed_at&&!initiative.title.includes('DEMO-I8') ? new Date(Date.parse(initiative.completed_at)+10*86400000).toISOString() : as_of;
    const comparisonAsOf = initiative.title.includes('DEMO-I2')||initiative.title.includes('DEMO-I4')?as_of:historicalVerification;
    const problem = problems.find(p=>p.id===initiative.problem_id);
    const scoped = occurrences.filter(o=>o.mechanism===problem.mechanism&&o.cause_id===problem.cause_id&&
      (problem.mechanism==='downtime'?o.machine_id===problem.machine_id:o.line_id===problem.line_id&&o.product_id===problem.product_id));
    const baseline = baselineEvidence({checkpoints,entries,occurrences:scoped,problem,initiative,as_of:comparisonAsOf});
    baseline.source_revision = source_revision;
    statements.push(`select public.store_lean_evidence(${literal(TARGET.factory)},${literal(TARGET.leanActor)},'baseline',${literal(initiative.id)},${initiative.revision},${json(baseline)},'{}',gen_random_uuid());`);
    if (!initiative.title.includes('DEMO-I4')&&!initiative.title.includes('DEMO-I2')) {
      const evidence = compareEvidence({checkpoints,entries,occurrences:scoped,problem,product_id:initiative.product_id,
        cutoff:initiative.completed_at,desired_hours:baseline.runtime_hours,baseline,as_of:comparisonAsOf});
      evidence.source_revision=source_revision;
      const outcome=initiative.title.includes('DEMO-I5')?'IMPROVED':initiative.title.includes('DEMO-I6')?'NO_MEANINGFUL_CHANGE':initiative.title.includes('DEMO-I7')?'WORSE':'INSUFFICIENT_DATA';
      if (outcome!=='INSUFFICIENT_DATA'&&!evidence.complete) throw new Error('Incomplete comparison '+initiative.title);
      const note='DEMO historical fixture: simulated human '+outcome+'. Inspect the separate calculated dimensions; this is not a real factory benefit claim.';
      statements.push(`select public.store_lean_evidence(${literal(TARGET.factory)},${literal(TARGET.leanActor)},'verify',${literal(initiative.id)},${initiative.revision+1},${json(evidence)},${json({outcome,note})},gen_random_uuid());`);
      statements.push(`update public.lean_initiatives set verified_at=${literal(historicalVerification)} where id=${literal(initiative.id)};`);
      if(outcome==='IMPROVED') {
        const manual=compareEvidence({checkpoints,entries,occurrences:scoped,problem,product_id:initiative.product_id,cutoff:initiative.completed_at,desired_hours:2,as_of});
        manual.source_revision=source_revision;
        statements.push(`select public.store_lean_evidence(${literal(TARGET.factory)},${literal(TARGET.leanActor)},'save_comparison',${literal(problem.id)},0,${json(manual)},${json({cutoff:initiative.completed_at,desired_hours:2})},gen_random_uuid());`);
      }
      checks.push({title:initiative.title,outcome,complete:evidence.complete,changes:evidence.changes});
    }
  }
  return {sql:`begin;${guardSQL()} select set_config('request.jwt.claim.role','service_role',true);select set_config('request.jwt.claim.sub',${literal(TARGET.leanActor)},true);${statements.join('\n')} commit;`,checks};
}
export const sourceSQL = `select jsonb_build_object(
 'checkpoints',(select coalesce(jsonb_agg(to_jsonb(x) order by captured_at,id),'[]') from public.lean_runtime_contexts x where factory_id='${TARGET.factory}'),
 'entries',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select e.*,o.product_id,(select jsonb_agg(c->>'id') from jsonb_array_elements((select context->'centers' from public.lean_runtime_contexts where factory_id=e.factory_id and captured_at<=e.created_at order by captured_at desc,id desc limit 1))c where c->>'line_id'=e.line_id::text) machine_ids from public.production_entries e join public.production_orders o on o.id=e.order_id where e.factory_id='${TARGET.factory}')x),
 'occurrences',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from private.lean_occurrences x where factory_id='${TARGET.factory}'),
 'initiatives',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.lean_initiatives x where factory_id='${TARGET.factory}' and baseline_evidence is null),
 'problems',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.lean_problem_settings x where factory_id='${TARGET.factory}'),
 'source_revision',(select revision from private.lean_source_state where factory_id='${TARGET.factory}'), 'as_of',clock_timestamp()) as sources`;
export const lossInputSQL = `select jsonb_agg(jsonb_build_object('event',to_jsonb(d),'samples',(select jsonb_agg(to_jsonb(s) order by captured_at,id) from public.production_loss_context_snapshots s where s.event_id=d.id))) as inputs from public.downtime_events d where factory_id='${TARGET.factory}' and ended_at is not null and not exists(select 1 from public.production_loss_estimates e where e.event_id=d.id)`;

export async function runDemo(query,day) {
  await query(await seedSQL(day,{rollback:true})); // Full constraint and preservation dry run.
  await query(await seedSQL(day));
  const inputs=(await query(lossInputSQL))[0].inputs||[];
  await query(lossSQL(inputs));
  const sources=(await query(sourceSQL))[0].sources;
  const evidence=evidenceSQL(sources);
  await query(evidence.sql);
  const verification=await fs.readFile(path.join(root,'supabase/seeds/manual_acceptance_verify.sql'),'utf8');
  const result=await query(`begin;${guardSQL()}${verification}commit;`);
  return {day,verification:result,comparisons:evidence.checks};
}

async function main() {
  const args=process.argv.slice(2);
  if(args.length!==4||args[0]!=='--target'||args[2]!=='--day') throw new Error('Usage: node scripts/demo-reset.mjs --target testing --day YYYY-MM-DD');
  requireTarget(args[1]);const day=validateDay(args[3]);
  if(execFileSync('git',['branch','--show-current'],{cwd:root,encoding:'utf8'}).trim()!=='development') throw new Error('Expected development branch');
  const token=process.env.SUPABASE_ACCESS_TOKEN;
  if(!token) throw new Error('Set SUPABASE_ACCESS_TOKEN in this shell. Never put it in source or public environment variables.');
  const request=async(route,body)=>{
    const response=await fetch('https://api.supabase.com/v1/projects/'+TARGET.ref+route,{method:body?'POST':'GET',redirect:'error',
      headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
    if(!response.ok)throw new Error(`TESTING management request failed (${response.status}); no automatic retry.`);
    return response.json();
  };
  const project=await request('');
  if((project.id||project.ref)!==TARGET.ref||project.name!==TARGET.name)throw new Error('Project identity mismatch');
  const manifest=JSON.parse(await fs.readFile(path.join(root,'supabase/seeds/manual_acceptance_migrations.json'),'utf8'));
  for(const [name,hash] of Object.entries(manifest)) {
    const actual=createHash('sha256').update(await fs.readFile(path.join(root,'supabase/migrations',name))).digest('hex');
    if(actual!==hash)throw new Error('Applied migration bytes changed: '+name);
  }
  const localFiles=(await fs.readdir(path.join(root,'supabase/migrations'))).filter(x=>x.endsWith('.sql'));
  if(localFiles.length!==79)throw new Error('Migration count changed');
  const query=sql=>request('/database/query',{query:sql});
  const remote=await query('select version,name from supabase_migrations.schema_migrations order by version');
  if(remote.length!==79||remote.some(r=>!localFiles.includes(r.version+'_'+r.name+'.sql')))throw new Error('Local/TESTING migration names differ');
  console.log(JSON.stringify(await runDemo(query,day),null,2));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) main().catch(error=>{
  console.error(error.message);process.exitCode=1;
});
