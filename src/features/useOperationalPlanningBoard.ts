import {useEffect,useState} from 'react';
import {collectOperationalBoard} from '@/utils/planning-operational-board.mjs';
import type {FeatureProps} from './types';
import type {MaintenancePlanningBoard} from './maintenance-planning-types';
import type {Row} from '@/types';
export type OperationalBoard=MaintenancePlanningBoard & {orders:Row[];production_requests:Row[];reservations:any[];
 completeness:'COMPLETE'|'INCOMPLETE';reason:string|null;total:number|null;loaded:number;valid_until:string};
export function useOperationalPlanningBoard(props:FeatureProps,from:number,until:number,line='',domain:'all'|'maintenance'|'production_plan'='all') {
 const {snapshot:s,can}=props;
 const allowed=can('factory','view')&&can('maintenance','view')&&(domain==='maintenance'||can('orders','view'));
 const factory=String(s.factory?.id||''),identity=JSON.stringify([factory,from,until,line,domain,s.user?.id]);
 const [retry,setRetry]=useState(0),[state,setState]=useState<{identity:string;data:OperationalBoard|null;loading:boolean;error:string}>({identity:'',data:null,loading:false,error:''});
 useEffect(()=>{
  if(!allowed)return;
  const controller=new AbortController();let expiry:ReturnType<typeof setTimeout>|undefined;
  const scope={factory,range_start:new Date(from).toISOString(),range_end:new Date(until).toISOString(),line_id:line||null,machine:null,domain};
  setState(old=>({identity,data:old.identity===identity?old.data:null,loading:true,error:''}));
  void collectOperationalBoard(async(cursor:Record<string,unknown>)=>{
   const q=new URLSearchParams({factory,view:'operational',start:scope.range_start,end:scope.range_end,domain,...line?{line}:{}});
   const names:Record<string,string>={after_kind:'after_kind',after_id:'after_id',expected_hash:'context_hash',evaluated_at:'evaluated_at'};
   for(const [key,value] of Object.entries(cursor))q.set(names[key],String(value));
   const response=await fetch('/api/maintenance-planning?'+q,{signal:controller.signal,cache:'no-store'}),body=await response.json();
   if(!response.ok)throw Error(body.error||'mpBoardError');return body;
  },scope,(partial:OperationalBoard)=>{if(!controller.signal.aborted)setState(old=>({identity,data:old.identity===identity&&old.data?.completeness==='COMPLETE'?old.data:partial,loading:true,error:''}));}).then((data:OperationalBoard)=>{
   if(controller.signal.aborted)return;setState({identity,data,loading:false,error:''});
   expiry=setTimeout(()=>setRetry(v=>v+1),Math.max(1,Date.parse(data.valid_until)-Date.now()));
  }).catch((cause:unknown)=>{if(!controller.signal.aborted)setState(old=>({identity,data:cause instanceof Error&&['permissionError','unauthorized'].includes(cause.message)?null:old.identity===identity?old.data:null,loading:false,error:cause instanceof Error?cause.message:'mpBoardError'}));});
  return ()=>{controller.abort();if(expiry)clearTimeout(expiry);};
 },[allowed,identity,factory,from,until,line,domain,s.fetchedAt,retry]);
 const visible=allowed&&state.identity===identity?state:{data:null,loading:allowed,error:allowed?'':'permissionError'};
 const complete=Boolean(visible.data?.completeness==='COMPLETE'&&!visible.loading&&!visible.error&&Date.now()<Date.parse(visible.data.valid_until));
 return {...visible,complete,reload:()=>{setState(old=>({...old,loading:true,error:''}));setRetry(v=>v+1);}};
}
