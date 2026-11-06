import {useEffect,useState} from 'react';
import {collectPlanningWork} from '@/utils/planning-work-reader.mjs';
import type {FeatureProps} from './types';
export type PlanningWork={item_id:string;choice:'COMPLETE'|'REPLACE'|'STOCK';origin_item_id:string;origin_code:string;demand_item_id:string|null;demand_code:string|null;held:boolean;retired:boolean;required_operations?:{id:string;name:string;name_ar?:string}[];capable_lines:string[]};
export function usePlanningWork({snapshot:s,can}:Pick<FeatureProps,'snapshot'|'can'>){
 const factory=String(s.factory?.id||''),allowed=can('orders','view'),identity=JSON.stringify([factory,s.user.id]);
 const [retry,setRetry]=useState(0);
 const [state,setState]=useState<{identity:string;data:PlanningWork[];loading:boolean;error:string}>({identity:'',data:[],loading:true,error:''});
 useEffect(()=>{
  if(!allowed)return;const controller=new AbortController();
  setState(old=>({identity,data:old.identity===identity?old.data:[],loading:true,error:''}));
  void collectPlanningWork(async(after:string|null)=>{
   const q=new URLSearchParams({factory,mode:'planning',...(after?{after}:{})});
   const response=await fetch('/api/manufactured-output?'+q,{cache:'no-store',signal:controller.signal}),body=await response.json();
   if(!response.ok)throw Error(body.error||'dataWarning');return body;
  }).then((data:PlanningWork[])=>{if(!controller.signal.aborted)setState({identity,data,loading:false,error:''});})
   .catch((error:Error)=>{if(!controller.signal.aborted)setState(old=>({identity,data:old.identity===identity&&!['permissionError','unauthorized'].includes(error.message)?old.data:[],loading:false,error:error.message}));});
  return()=>controller.abort();
 },[identity,factory,allowed,s.fetchedAt,retry]);
 const visible=allowed&&state.identity===identity?state:{data:[],loading:allowed,error:allowed?'':'permissionError'};
 return {...visible,complete:allowed&&!visible.loading&&!visible.error,reload:()=>setRetry(n=>n+1)};
}
