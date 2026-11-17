import {useEffect,useState} from 'react';
import {collectExecutionOrders,executionScheduled} from '@/utils/execution-selection.mjs';
import type {Row} from '@/types';import type {FeatureProps} from './types';
export function useExecutionOrders({snapshot:s,can}:FeatureProps){
 const factory=String(s.factory?.id||''),identity=factory+':'+s.user?.id,allowed=can('factory','view')&&can('orders','view');
 const [retry,setRetry]=useState(0),[state,setState]=useState<{identity:string;rows:Row[]|null;loading:boolean;error:string}>({identity:'',rows:null,loading:false,error:''});
 useEffect(()=>{if(!allowed)return;const controller=new AbortController();setState(old=>({identity,rows:old.identity===identity?old.rows:null,loading:true,error:''}));
  void collectExecutionOrders(async(cursor:unknown)=>{const q=new URLSearchParams({factory,mode:'orders'});if(cursor)q.set('cursor',JSON.stringify(cursor));
   const response=await fetch('/api/production-execution?'+q,{signal:controller.signal,cache:'no-store'}),body=await response.json();if(!response.ok)throw Error(body.error||'dataWarning');return body.data;
  },factory).then((rows:Row[])=>{if(!controller.signal.aborted)setState({identity,rows,loading:false,error:''});}).catch((e:unknown)=>{if(!controller.signal.aborted)setState(old=>({identity,rows:old.identity===identity?old.rows:null,loading:false,error:e instanceof Error?e.message:'dataWarning'}));});
  return()=>controller.abort();
 },[allowed,factory,identity,s.fetchedAt,retry]);
 const visible=allowed&&state.identity===identity?state:{rows:null,loading:allowed,error:''};
 const fallback=(s.tables.production_orders||[]).filter(executionScheduled).sort((a,b)=>Date.parse(String(a.start_time))-Date.parse(String(b.start_time))||String(a.id).localeCompare(String(b.id)));
 return {rows:allowed?(visible.rows||fallback):[],complete:allowed&&visible.rows!==null&&!visible.loading&&!visible.error,loading:visible.loading,error:visible.error,reload:()=>setRetry(n=>n+1)};
}
