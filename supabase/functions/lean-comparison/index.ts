// Browser supplies identities/settings only. Evidence is calculated from authenticated, paginated database readers.
import { baselineEvidence, compareEvidence } from '../../../src/utils/lean-comparison.mjs';
declare const Deno:{env:{get(key:string):string|undefined};serve(fn:(req:Request)=>Promise<Response>):void};
const url=Deno.env.get('SUPABASE_URL'),key=Deno.env.get('SUPABASE_ANON_KEY'),service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const uuid=(v:unknown)=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
Deno.serve(async req=>{
 const json=(data:unknown,status=200)=>Response.json(data,{status});
 if(req.method!=='POST')return json({error:'method_not_allowed'},405);
 if(!url||!key||!service)return json({error:'dataWarning'},503);
 try{
  const b=await req.json(),bearer=req.headers.get('Authorization')||'';
  if(!b||Object.keys(b).some(k=>!['factory','operation','problem_id','initiative_id','product_id','cutoff','desired_hours','outcome','note','request_id','expected_revision'].includes(k))||!uuid(b.factory)||!['baseline','preview','verify','manual','save_comparison'].includes(b.operation))return json({error:'leanInvalid'},400);
  const request=async(path:string,body?:unknown,trusted=false)=>{
   const r=await fetch(url+path,{method:body===undefined?'GET':'POST',headers:{apikey:trusted?service!:key!,Authorization:trusted?`Bearer ${service}`:bearer,'Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)})});
   const result=await r.json();if(!r.ok)throw Object.assign(Error(result.message||'dataWarning'),{status:r.status});return result;
  };
  const actor=await request('/auth/v1/user');if(!uuid(actor.id)||!actor.email_confirmed_at)return json({error:'unauthorized'},401);
  const allowed=await request('/rest/v1/rpc/can_access',{factory:b.factory,module:'lean',action:b.operation==='verify'?'approve':b.operation==='baseline'?'create':'view'});
  if(allowed!==true)return json({error:'permissionError'},403);
  const read=(query:Record<string,unknown>)=>request('/rest/v1/rpc/lean_read',{factory:b.factory,query});
  const stamp=new Date().toISOString();
  const detail=await read({mode:'detail',problem_id:b.problem_id,initiative_id:b.initiative_id,from:'1970-01-01T00:00:00Z',to:stamp});
  const source_revision=detail.source_revision;
  const problem=detail.problem,initiative=detail.initiatives?.find((x:{id:string})=>x.id===b.initiative_id);
  const official=['baseline','preview','verify'].includes(b.operation);
  if(official&&(!initiative||b.product_id&&b.product_id!==initiative.product_id))return json({error:'leanComparisonProduct'},400);
  if(['baseline','verify'].includes(b.operation)&&(!Number.isInteger(b.expected_revision)||b.expected_revision!==initiative.revision))return json({error:'leanConflict'},409);
  const product_id=official?initiative.product_id:b.product_id;
  if(!uuid(product_id))return json({error:'leanComparisonProduct'},400);
  const rows=async(mode:string)=>{
   const collected:Record<string,unknown>[]=[];
   for(let page=1;page<=100;page++){
    const data=await read({mode,page,problem_id:problem.id,product_id,from:'1970-01-01T00:00:00Z',to:stamp});
    if(data.source_revision!==source_revision)throw Error('lean_conflict');
    collected.push(...data.rows);if(collected.length>=data.total)return collected;
   }
   throw Error('leanSourceTooLarge');
  };
  const [checkpoints,occurrences,entries]=await Promise.all([rows('contexts'),rows('occurrences'),rows('entries')]);
  let evidence:Record<string,unknown>;
  if(b.operation==='baseline'){
   evidence=baselineEvidence({checkpoints,occurrences,entries,problem,initiative,as_of:stamp});
  }else{
   const baseline=official?initiative.baseline_evidence:null;
   if(official&&(!baseline||!initiative.completed_at))return json({error:'leanIncomplete'},422);
   const desired_hours=official?baseline.runtime_hours==null?null:Number(baseline.runtime_hours):Number(b.desired_hours);
   const cutoff=official?initiative.completed_at:b.cutoff;
   if((desired_hours!==null&&!(desired_hours>0&&desired_hours<=100000))||!Number.isFinite(Date.parse(cutoff))||Date.parse(cutoff)>Date.parse(stamp))return json({error:'leanInvalid'},400);
   evidence=compareEvidence({checkpoints,occurrences,entries,problem,product_id,cutoff,desired_hours,baseline,as_of:stamp});
  }
  evidence.source_revision=source_revision;
  if(['baseline','verify','save_comparison'].includes(b.operation)){
   if(!uuid(b.request_id))return json({error:'leanInvalid'},400);
   const stored=await request('/rest/v1/rpc/store_lean_evidence',{factory:b.factory,actor:actor.id,operation:b.operation,target:b.operation==='save_comparison'?problem.id:initiative.id,expected_revision:b.expected_revision||0,evidence,
    payload:b.operation==='verify'?{outcome:b.outcome,note:b.note}:b.operation==='save_comparison'?{cutoff:b.cutoff,desired_hours:Number(b.desired_hours)}:{},request_id:b.request_id},true);
   return json({...stored,evidence});
  }
  return json({evidence});
 }catch(e){const error=e instanceof Error?e.message:'dataWarning';return json({error:error.startsWith('lean_')?'leanConflict':error==='leanSourceTooLarge'?'leanSourceTooLarge':'dataWarning'},(e as {status?:number}).status===403?403:422);}
});
