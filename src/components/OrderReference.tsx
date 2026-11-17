import {createContext,useContext,useEffect,useMemo,useState,type ReactNode} from 'react';
import type {Snapshot} from '@/types';
type Identity={id:string;code:string;customer:string|null;description:string|null;sales_code:string|null};
const OrderIdentities=createContext<Map<string,Identity>>(new Map());
export function OrderIdentityProvider({snapshot,enabled,children}:{snapshot:Snapshot;enabled:boolean;children:ReactNode}){
 const scope=String(snapshot.factory?.id||'')+':'+snapshot.user.id;
 const [result,setResult]=useState<{scope:string;rows:Identity[]}|null>(null);
 useEffect(()=>{if(!enabled)return;const abort=new AbortController();fetch('/api/fulfillment?'+new URLSearchParams({factory:String(snapshot.factory?.id||''),mode:'identities'}),{signal:abort.signal,cache:'no-store'}).then(async response=>{if(!response.ok)throw Error('identity_unavailable');return response.json();}).then(data=>{if(!abort.signal.aborted&&Array.isArray(data.rows))setResult({scope,rows:data.rows});}).catch(()=>{if(!abort.signal.aborted)setResult(null);});return()=>abort.abort();},[scope,snapshot.factory?.id,snapshot.fetchedAt,enabled]);
 const value=useMemo(()=>{const map=new Map<string,Identity>();if(enabled&&result?.scope===scope)for(const row of result.rows){map.set(row.id,row);map.set(row.code,row);}return map;},[enabled,result,scope]);
 return <OrderIdentities.Provider value={value}>{children}</OrderIdentities.Provider>;
}
export default function OrderReference({reference,item,detailsOnly=false,description=false}:{reference?:unknown;item?:unknown;detailsOnly?:boolean;description?:boolean}){
 const identities=useContext(OrderIdentities),code=String(reference||''),row=identities.get(String(item||''))||identities.get(code);
 return <span className="order-reference">{!detailsOnly&&code&&<bdi dir="ltr">{code}</bdi>}{row?.sales_code&&row.sales_code!==code&&<bdi dir="ltr">{row.sales_code}</bdi>}{row?.customer&&<span dir="auto">{row.customer}</span>}{description&&row?.description&&<span dir="auto">{row.description}</span>}</span>;
}
