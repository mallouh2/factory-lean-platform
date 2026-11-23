import {verifyRuntime,verifyDatabase,databaseGuard,initializeOwners,functionMetadata,argumentValue} from './local-policy.mjs';
// Test-only Auth/Data API protocol adapter. No application imports or auth overrides.
// Existing SQL grants, RLS and business RPCs execute as the verified fixture user.
import fs from 'node:fs';
import path from 'node:path';
import {tmpdir} from 'node:os';
import {createServer} from 'node:http';
import {spawn} from 'node:child_process';
import {randomBytes,randomUUID,createHmac,timingSafeEqual} from 'node:crypto';
import assert from 'node:assert/strict';
import {createLeanComparisonHandler} from '../../supabase/functions/lean-comparison/handler.mjs';
import {createLossEstimateHandler} from '../../supabase/functions/save-production-loss-estimate/handler.mjs';
const runtimePath=process.argv[2];if(!runtimePath)throw Error('Explicit disposable runtime required');
const config=JSON.parse(fs.readFileSync(runtimePath,'utf8').replace(/^\ufeff/,''));
if(process.env.NODE_ENV==='production'||config.marker!=='FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY'||config.databaseHost!=='127.0.0.1'||config.database!=='factory_lean_quality_local'||!path.resolve(config.root).startsWith(path.resolve(tmpdir())+path.sep))throw Error('Not a disposable local fixture');
const appOrigin=`http://127.0.0.1:${config.applicationPort}`,backendOrigin=`http://127.0.0.1:${config.backendPort}`,key='local-preview-public-not-a-hosted-key';
const env=fs.readFileSync(config.environmentFile||path.join(config.app,'.env.local'),'utf8');if(!env.includes('SUPABASE_URL='+backendOrigin)||/https:\/\//.test(env))throw Error('Application environment is not isolated');
const quote=s=>"'"+String(s).replaceAll("'","''")+"'";
function sql(query){return new Promise((resolve,reject)=>{const child=spawn(path.join(config.bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p',String(config.databasePort),'-U','quality_fixture','-d',config.database,'-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'],{windowsHide:true});let data='',error='';child.stdout.on('data',v=>data+=v);child.stderr.on('data',v=>error+=v);child.on('error',reject);child.on('close',code=>code?reject(Error(error)):resolve(data.trim()));child.stdin.end(query)})}
verifyRuntime(config,env);
verifyDatabase(config,JSON.parse(await sql("select json_build_object('host',inet_server_addr(),'port',inet_server_port(),'database',current_database(),'data',current_setting('data_directory'))")));
const credentialPath=path.join(config.root,'local-credentials.json');
let credentials;if(fs.existsSync(credentialPath))credentials=JSON.parse(fs.readFileSync(credentialPath));else{
 await initializeOwners(sql,config);
 const fixtureContexts=[config.context,...(config.additionalContexts||[])];
 const emails=JSON.parse(await sql(`select json_object_agg(id,email) from auth.users where id in (${fixtureContexts.flatMap(x=>[x.owner,x.worker,x.viewer]).map(quote).join(',')})`));
 credentials={secret:randomBytes(48).toString('hex'),accounts:fixtureContexts.flatMap(x=>['owner','worker','viewer'].map(role=>({role,id:x[role],email:emails[x[role]],password:'Local!'+randomBytes(20).toString('base64url')})))};fs.writeFileSync(credentialPath,JSON.stringify(credentials,null,2));
 fs.writeFileSync(path.join(config.root,'LOCAL-LOGIN.txt'),'Disposable localhost-only fixture accounts. NOT TESTING or Simulation.\n'+credentials.accounts.map(a=>`${a.role}\nEmail: ${a.email}\nPassword: ${a.password}\n`).join('\n'));
}
const sessions=new Map(),refreshTokens=new Map(),counts={auth:0,rpc:0,table:0,denied:0},rpcNames=new Set();
const sign=value=>createHmac('sha256',credentials.secret).update(value).digest('base64url');
function issue(account,session=randomUUID()){
 sessions.set(session,account);const now=Math.floor(Date.now()/1000),head=Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url'),payload=Buffer.from(JSON.stringify({iss:backendOrigin+'/auth/v1',aud:'authenticated',sub:account.id,email:account.email,role:'authenticated',session_id:session,iat:now,exp:now+86400})).toString('base64url'),wire=head+'.'+payload,token=wire+'.'+sign(wire),refresh=randomUUID();refreshTokens.set(refresh,session);
 return {access_token:token,refresh_token:refresh,token_type:'bearer',expires_in:86400,expires_at:now+86400,user:user(account)};
}
function user(a){return{id:a.id,aud:'authenticated',role:'authenticated',email:a.email,email_confirmed_at:'2026-01-01T00:00:00Z',confirmed_at:'2026-01-01T00:00:00Z',created_at:'2026-01-01T00:00:00Z',app_metadata:{provider:'email',providers:['email']},user_metadata:{},identities:[]}}
function authenticated(req){try{const raw=String(req.headers.authorization||'').replace(/^Bearer /,''),[head,payload,signature]=raw.split('.'),want=Buffer.from(sign(head+'.'+payload)),actual=Buffer.from(signature||'');if(want.length!==actual.length||!timingSafeEqual(want,actual))return null;const claims=JSON.parse(Buffer.from(payload,'base64url'));const account=sessions.get(claims.session_id);return account&&claims.exp>Date.now()/1000&&claims.sub===account.id?{account,claims}:null}catch{return null}}
const metadata=new Map();
// Private in-process transport only: this key is never served, persisted, or
// accepted by the HTTP Data API. The existing Edge handler supplies evidence;
// ordinary clients retain their authenticated SQL grants, never service_role.
const leanService=randomBytes(48).toString('hex');
function trustedTransport(name,parameters){return async(input,init)=>{
 const url=new URL(input),headers=new Headers(init.headers);
 assert.equal(url.origin,backendOrigin);
 if(headers.get('authorization')!==`Bearer ${leanService}`)return fetch(input,init);
 assert.equal(url.pathname,`/rest/v1/rpc/${name}`);assert.equal(init.method,'POST');
 const a=JSON.parse(init.body);
 try{
  const data=await sql(`begin;${databaseGuard(config)}set local statement_timeout='30s';set local lock_timeout='10s';do $$begin perform set_config('request.jwt.claim.role','service_role',true);perform set_config('request.jwt.claims','{"role":"service_role"}',true);end$$;set local role service_role;with args as(select ${quote(JSON.stringify(a))}::jsonb a)select to_jsonb(public.${name}(${parameters}))from args;commit;`);
  return new Response(data,{headers:{'Content-Type':'application/json'}});
 }catch(error){
  const match=/ERROR:\s+([A-Z0-9]{5}):\s+([^\r\n]+)/.exec(error.message||'');
  return Response.json({message:match?.[2]||'dataWarning'},{status:match?.[1]==='42501'?403:match?.[1]==='40001'?409:400});
 }
}}
const leanFunctions={
 '/functions/v1/lean-comparison':createLeanComparisonHandler({
  url:backendOrigin,key,service:leanService,
  fetch:trustedTransport('store_lean_evidence',"(a->>'factory')::uuid,(a->>'actor')::uuid,a->>'operation',(a->>'target')::uuid,(a->>'expected_revision')::integer,a->'evidence',a->'payload',(a->>'request_id')::uuid")
 }),
 '/functions/v1/save-production-loss-estimate':createLossEstimateHandler({
  url:backendOrigin,key,service:leanService,
  fetch:trustedTransport('persist_production_loss_estimate',"(a->>'factory')::uuid,(a->>'event')::uuid,(a->>'actor')::uuid,a->'estimate',(a->>'correction')::uuid")
 })
};
async function rpc(name,args,raw,identity,isGet=false){
 // Mirror the existing public Data API exposure. SQL EXECUTE grants and the
 // original authenticated actor remain authoritative; never expose private RPCs.
 if(!metadata.has(name))metadata.set(name,JSON.parse(await sql(functionMetadata(name))));
 if(!metadata.get(name).length)throw Object.assign(Error('Public RPC execution not granted'),{status:403,code:'42501'});
 const signature=metadata.get(name).find(s=>Object.keys(args).every(k=>s.names?.includes(k)));if(!signature)throw Error('No matching original RPC signature: '+name);
 if(isGet&&signature.volatility==='v')throw Object.assign(Error('Mutating RPC requires POST'),{status:405,code:'25006'});
 // PostgREST GET arguments are URL text, including serialized JSON arguments.
 if(isGet){args={...args};for(const k of Object.keys(args)){if(['json','jsonb'].includes(signature.types[signature.names.indexOf(k)]))args[k]=JSON.parse(args[k]);}raw=JSON.stringify(args);}
 const parameters=Object.keys(args).map(k=>{assert.match(k,/^[a-z_]+$/);const type=signature.types[signature.names.indexOf(k)],value=argumentValue(type,k);assert.match(type,/^[a-z .\[\]]+$/);return `"${k}":=(${value})::${type}`});
 return transaction(identity,`with args as(select ${quote(raw)}::jsonb a)select to_jsonb(public."${name}"(${parameters.join(',')}))from args`);
}
// Suppress set_config row output without a platform-specific psql output path.
async function transaction(identity,query){return sql(`begin;${databaseGuard(config)}do $$begin perform set_config('request.jwt.claim.sub',${quote(identity.account.id)},true);perform set_config('request.jwt.claim.role','authenticated',true);perform set_config('request.jwt.claims',${quote(JSON.stringify(identity.claims))},true);end$$;set local role authenticated;${query};commit;`)}
const server=createServer(async(req,res)=>{try{
 assert.equal(req.socket.remoteAddress,'127.0.0.1');const url=new URL(req.url,backendOrigin);res.setHeader('Cache-Control','private, no-store');
 const json=(value,status=200)=>{res.writeHead(status,{'Content-Type':'application/json'});res.end(JSON.stringify(value))};
 if(req.method==='OPTIONS'){res.writeHead(204,{'Access-Control-Allow-Origin':appOrigin,'Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'GET,POST,OPTIONS'});return res.end()}
 if(url.pathname==='/health')return json({fixture:true,host:'127.0.0.1',databasePort:config.databasePort,counts,rpcs:[...rpcNames]});
 if(req.headers.apikey!==key)return json({error:'invalid_api_key'},401);
 let raw='';for await(const chunk of req){raw+=chunk;if(raw.length>100000)throw Error('Bounded request exceeded')}
 const args=raw?JSON.parse(raw):{},identity=authenticated(req);
 if(url.pathname==='/auth/v1/token'&&req.method==='POST'){
  counts.auth++;let account,session;
  if(url.searchParams.get('grant_type')==='password')account=credentials.accounts.find(a=>a.email===args.email&&a.password===args.password);
  if(url.searchParams.get('grant_type')==='refresh_token'){session=refreshTokens.get(args.refresh_token);account=sessions.get(session)}
  return account?json(issue(account,session)):json({code:'invalid_credentials',error_code:'invalid_credentials',msg:'Invalid local fixture credentials'},400);
 }
 if(!identity){counts.denied++;return json({code:'42501',message:'Invalid local fixture session'},401)}
 if(Object.hasOwn(leanFunctions,url.pathname)){
  const result=await leanFunctions[url.pathname](new Request(backendOrigin+url.pathname,{method:req.method,headers:req.headers,...(req.method==='POST'?{body:raw}:{})}));
  res.writeHead(result.status,{'Content-Type':'application/json'});return res.end(await result.text());
 }
 if(url.pathname==='/auth/v1/user'&&req.method==='GET')return json(user(identity.account));
 if(url.pathname==='/auth/v1/logout'&&req.method==='POST'){sessions.delete(identity.claims.session_id);return json({})}
 if(url.pathname.startsWith('/rest/v1/rpc/')){
  const name=url.pathname.split('/').at(-1);assert.match(name,/^[a-z_]+$/);counts.rpc++;rpcNames.add(name);
  const input=req.method==='GET'?Object.fromEntries(url.searchParams):args,body=req.method==='GET'?JSON.stringify(input):raw;
  const data=await rpc(name,input,body,identity,req.method==='GET');res.writeHead(200,{'Content-Type':'application/json'});return res.end(data||'null');
 }
 if(url.pathname.startsWith('/rest/v1/')&&req.method==='GET'){
  counts.table++;const table=url.pathname.split('/').at(-1);assert.match(table,/^[a-z_]+$/);
  const allowed=JSON.parse(await sql(`select coalesce(jsonb_agg(a.attname),'[]')from pg_class c join pg_namespace n on n.oid=c.relnamespace join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped where n.nspname='public' and c.relname=${quote(table)} and c.relkind='r' and has_table_privilege('authenticated',c.oid,'SELECT')`));
  if(!allowed.length)return json({code:'42501',message:'Public table SELECT not granted'},403);
  const ident=name=>{if(!allowed.includes(name))throw Error('Unknown public column');return '"'+name+'"';};
  const selected=url.searchParams.get('select')||'*',columns=selected==='*'?'*':selected.split(',').map(ident).join(',');
  const conditions=[];for(const[k,v]of url.searchParams){if(['select','order','limit','offset'].includes(k))continue;const column=ident(k),operator=v.slice(0,v.indexOf('.')),value=v.slice(v.indexOf('.')+1);
   if(['eq','gte','lte','gt','lt'].includes(operator))conditions.push(column+({eq:'=',gte:'>=',lte:'<=',gt:'>',lt:'<'})[operator]+quote(value));
   else if(operator==='is'&&['null','true','false'].includes(value))conditions.push(column+' is '+value);
   else if(operator==='in'&&/^\([a-f0-9,"-]+\)$/i.test(value))conditions.push(column+' in('+value.slice(1,-1).replaceAll('"','').split(',').map(quote).join(',')+')');
   else throw Error('Unsupported bounded filter');}
  const sort=url.searchParams.get('order')||(table==='production_plan_revisions'?'revision_no.asc':'');
  const order=sort?' order by '+sort.split(',').map(part=>{const [column,direction='asc',nulls]=part.split('.');if(!['asc','desc'].includes(direction)||(nulls&&!['nullsfirst','nullslast'].includes(nulls)))throw Error('Invalid sort');return ident(column)+' '+direction+(nulls?' nulls '+(nulls==='nullsfirst'?'first':'last'):'');}).join(','):'';
  const limit=Number(url.searchParams.get('limit')||5000),offset=Number(url.searchParams.get('offset')||0);if(!Number.isInteger(limit)||limit<1||limit>5000||!Number.isInteger(offset)||offset<0||offset>100000)throw Error('Invalid bounded page');
  const data=await transaction(identity,`select coalesce(jsonb_agg(t),'[]')from(select ${columns} from public."${table}"${conditions.length?' where '+conditions.join(' and '):''}${order} limit ${limit} offset ${offset})t`);
  if(String(req.headers.accept||'').includes('application/vnd.pgrst.object+json')){const rows=JSON.parse(data);if(rows.length!==1)return json({code:'PGRST116',message:'Single row required'},406);return json(rows[0]);}
  res.writeHead(200,{'Content-Type':'application/json'});return res.end(data);
 }
 return json({code:'42501',message:'Unsupported local protocol operation'},403);
 }catch(error){const match=/ERROR:\s+([A-Z0-9]{5}):\s+([^\r\n]+)/.exec(error.message||''),code=error.code||match?.[1]||'P0001',message=match?.[2]||error.message,status=error.status||(['42501'].includes(code)?403:code==='40001'?409:400);counts.denied++;fs.appendFileSync(path.join(config.root,'backend-errors.txt'),JSON.stringify({code,message})+'\n');res.writeHead(status,{'Content-Type':'application/json'});res.end(JSON.stringify({code,message}));}
});
server.listen(config.backendPort,'127.0.0.1',()=>console.log('Test-only Auth/Data adapter ready on '+backendOrigin+'; original SQL permissions/RLS intact.'));
for(const signal of['SIGINT','SIGTERM'])process.on(signal,()=>server.close(()=>process.exit(0)));
