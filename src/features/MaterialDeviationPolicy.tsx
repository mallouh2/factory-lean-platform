import {useEffect,useRef,useState} from 'react';
import {decimalCompare} from '@/utils/quality-quantities.mjs';
import type {FeatureProps} from './types';

export default function MaterialDeviationPolicy({props}:{props:FeatureProps}){
 const {snapshot:s,t,can}=props,factory=String(s.factory?.id||''),[value,setValue]=useState(''),[original,setOriginal]=useState(''),[error,setError]=useState(''),[busy,setBusy]=useState(false),[saved,setSaved]=useState(false),attempt=useRef<{value:string;id:string}|null>(null);
 useEffect(()=>{const a=new AbortController();fetch('/api/production-materials?'+new URLSearchParams({factory,policy:'1'}),{signal:a.signal,cache:'no-store'}).then(async r=>{const b=await r.json();if(!r.ok)throw Error(b.error||'dataWarning');setValue(b.data.deviation_percent);setOriginal(b.data.deviation_percent);}).catch(e=>{if(e.name!=='AbortError')setError(e.message);});return()=>a.abort();},[factory]);
 const valid=(decimalCompare(value,'0')??-1)>=0&&(decimalCompare(value,'1000')??1)<=0;
 if(!can('warehouse','edit'))return null;
 return <details className="material-preparation"><summary>{t('materialDeviationPolicy')}</summary><p>{t('materialDeviationPolicyHelp')}</p><form onSubmit={async e=>{e.preventDefault();if(!valid||busy)return;if(attempt.current?.value!==value)attempt.current={value,id:crypto.randomUUID()};setBusy(true);setError('');setSaved(false);try{const r=await fetch('/api/production-materials',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({factory,operation:'DEVIATION',payload:{percent:value},request_id:attempt.current.id})}),b=await r.json();if(!r.ok)throw Error(b.error||'dataWarning');attempt.current=null;setOriginal(value);setSaved(true);}catch(e){setError(e instanceof Error?e.message:'dataWarning');}finally{setBusy(false);}}}>
  <label>{t('materialDeviationPercent')}<input type="number" step="any" min="0" max="1000" inputMode="decimal" required value={value} disabled={busy} onChange={e=>{setValue(e.target.value);setSaved(false);}}/></label><button disabled={busy||!valid||value===original}>{t('save')}</button>
 </form>{saved&&<p role="status">{t('saved')}</p>}{error&&<p role="alert">{t(error)}</p>}</details>;
}
