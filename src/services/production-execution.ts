import type {Row} from '@/types';
export async function hydrateInterruptedOrders(db:{rpc:(name:string,args:Record<string,unknown>)=>PromiseLike<{data:any;error:any}>},factory:string,orders:Row[]){
 if(!orders.some(o=>o.execution_interrupted_at))return orders;
 const {data,error}=await db.rpc('production_execution_remaining',{factory});if(error)throw error;
 return orders.map(o=>o.execution_interrupted_at?{...o,execution_remaining_quantity:data?.[String(o.id)]}:o);
}
