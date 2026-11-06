// Disposable protocol/fixture policy only. Never imported by application code.
import assert from 'node:assert/strict';
import path from 'node:path';
import {tmpdir} from 'node:os';
export const quote=s=>"'"+String(s).replaceAll("'","''")+"'";
export function verifyRuntime(c,env,nodeEnv=process.env.NODE_ENV){
 assert.notEqual(nodeEnv,'production');assert.equal(c.marker,'FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY');
 assert.equal(c.databaseHost,'127.0.0.1');assert.equal(c.database,'factory_lean_quality_local');
 assert.ok(path.resolve(c.root).startsWith(path.resolve(tmpdir())+path.sep));
 for(const p of [c.databasePort,c.backendPort,c.applicationPort])assert.ok(Number.isInteger(p)&&p>1024&&p<65536);
 assert.equal(new Set([c.databasePort,c.backendPort,c.applicationPort]).size,3);
 assert.ok(!/https:\/\//.test(env));
 for(const key of ['SUPABASE_URL','NEXT_PUBLIC_SUPABASE_URL'])assert.match(env,new RegExp('(?:^|\\n)'+key+'=http://127\\.0\\.0\\.1:'+c.backendPort+'(?:\\r?\\n|$)'));
}
export function verifyDatabase(c,actual){
 assert.equal(actual.host,'127.0.0.1');assert.equal(actual.port,c.databasePort);assert.equal(actual.database,c.database);
 assert.equal(path.resolve(actual.data).toLowerCase(),path.resolve(c.root,'data').toLowerCase());
}
// Rechecked inside each writing transaction, before changing to the authenticated
// SQL role. A loopback proxy to a hosted server cannot satisfy the data-dir check.
export function databaseGuard(c){
 return `do $$begin if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>${c.databasePort} or current_database()<>${quote(c.database)} or lower(replace(current_setting('data_directory'),chr(92),'/'))<>${quote(path.resolve(c.root,'data').replaceAll('\\','/').toLowerCase())} then raise exception 'Disposable local target changed';end if;end$$;`;
}
export async function initializeOwners(sql,c){
 assert.notEqual(process.env.NODE_ENV,'production');assert.equal(c.marker,'FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY');
 assert.equal(c.databaseHost,'127.0.0.1');assert.equal(c.database,'factory_lean_quality_local');
 assert.ok(path.resolve(c.root).startsWith(path.resolve(tmpdir())+path.sep));assert.ok(Number.isInteger(c.databasePort));
 // Explicit first-time fixture initialization only. Never on each login/request:
 // deliberate permission revocation must remain effective in an existing fixture.
 const owners=[c.context,...(c.additionalContexts||[])];
 for(const x of owners){
  assert.match(x.owner,/^[a-f0-9-]{36}$/i);assert.match(x.factory,/^[a-f0-9-]{36}$/i);
  await sql(`begin;${databaseGuard(c)}do $$begin if not exists(select 1 from public.memberships where factory_id=${quote(x.factory)}::uuid and user_id=${quote(x.owner)}::uuid and is_owner and status='approved') then raise exception 'Designated local owner membership invalid';end if;end$$;
   insert into public.user_permissions(factory_id,user_id,module,action)
   select ${quote(x.factory)}::uuid,${quote(x.owner)}::uuid,module,action from public.permissions on conflict(factory_id,user_id,module,action) do nothing;commit;`);
 }
}
export const functionMetadata=name=>`select coalesce(jsonb_agg(jsonb_build_object('names',p.proargnames,'volatility',p.provolatile,'types',(select jsonb_agg(t::regtype::text)from unnest(p.proargtypes::oid[])t))),'[]')from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=${quote(name)} and p.prokind='f' and p.prorettype<>'trigger'::regtype and has_function_privilege('authenticated',p.oid,'EXECUTE')`;
export function argumentValue(type,key){
 if(type.endsWith('[]'))return `case when a->${quote(key)} is null or a->${quote(key)}='null'::jsonb then null else array(select jsonb_array_elements_text(a->${quote(key)})) end`;
 return type==='jsonb'||type==='json'?`nullif(a->${quote(key)},'null'::jsonb)`:`a->>${quote(key)}`;
}
