import {useEffect,useRef,useState} from 'react';

type Intent={operation:string;payload:Record<string,unknown>;request_id:string};
// Keep an uncertain physical command until the same server-bound intent is
// replayed. A refresh or changed form must not turn it into a second posting.
export function useProductionStockCommand(factory:string,actor:string){
 const key='factoryLean:productionStock:'+actor+':'+factory,lock=useRef(false);
 const [busy,setBusy]=useState(false),[error,setError]=useState(''),[pending,setPending]=useState<Intent|null>(null),[ready,setReady]=useState(false);
 useEffect(()=>{setReady(false);try{const raw=sessionStorage.getItem(key);setPending(raw?JSON.parse(raw):null);setReady(true)}catch{setError('pcStorageError')}},[key]);
 async function post(intent:Intent){
  if(lock.current||!ready)return null;lock.current=true;setBusy(true);setError('');
  try{
   sessionStorage.setItem(key,JSON.stringify(intent));setPending(intent);
   const r=await fetch('/api/production-stock',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({factory,...intent}),signal:AbortSignal.timeout(25000)}),b=await r.json();
   // A protected business rejection proves there was no posting. Authorization, transport and
   // server failures retain the original identity for safe result recovery.
   if(r.ok||[400,404,409,422].includes(r.status)){sessionStorage.removeItem(key);setPending(null)}
   if(!r.ok)throw Error(b.error||'dataWarning');return b.data;
  }catch(e){setError(e instanceof Error?e.message:'dataWarning');return null}finally{lock.current=false;setBusy(false)}
 }
 return{busy,error,pending,ready,recover:async()=>{
  try{const raw=sessionStorage.getItem(key);return raw?post(JSON.parse(raw)):null}catch{setError('pcStorageError');return null}
 },run:async(operation:string,payload:Record<string,unknown>)=>{
  try{const raw=sessionStorage.getItem(key),old:Intent|null=raw?JSON.parse(raw):null;
   if(old&&(old.operation!==operation||JSON.stringify(old.payload)!==JSON.stringify(payload))){setPending(old);setError('psUncertain');return null}
   return post(old||{operation,payload,request_id:crypto.randomUUID()});
  }catch{setError('pcStorageError');return null}
 }};
}
