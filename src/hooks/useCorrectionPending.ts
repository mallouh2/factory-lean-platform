import {useHistoryData} from './useHistoryData';

export function useCorrectionPending(factory:string,actor:string,allowed:boolean,revision:string){
 const url=factory&&actor&&allowed?'/api/production-corrections?'+new URLSearchParams({factory,pending_count:'1'}):null;
 const read=useHistoryData<{total:number}>(url,revision,actor+'|'+factory);
 const count=read.data?.total;
 return !read.loading&&!read.error&&typeof count==='number'&&Number.isSafeInteger(count)&&count>0?count:null;
}
