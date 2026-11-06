/** Reject incomplete or changing page sets; never classify only the newest100 jobs. */
export async function collectPlanningWork(fetchPage) {
 const work=[];let after=null,hash=null,total=null;
 for(;;){
  const page=await fetchPage(after);
  if(!page||typeof page.available!=='boolean'||!Array.isArray(page.work)||page.work.length>100||!Number.isSafeInteger(page.total)||page.total<0||typeof page.context_hash!=='string'||typeof page.has_more!=='boolean')throw Error('dataWarning');
  if(hash!==null&&(page.context_hash!==hash||page.total!==total))throw Error('recordingContextChanged');
  hash=page.context_hash;total=page.total;
  if(!page.available&&(page.work.length||page.has_more||total))throw Error('dataWarning');
  for(const row of page.work){
   if(typeof row.item_id!=='string'||(after!==null&&row.item_id<=after)||!['COMPLETE','REPLACE','STOCK'].includes(row.choice)||typeof row.held!=='boolean'||typeof row.retired!=='boolean'||!Array.isArray(row.capable_lines))throw Error('dataWarning');
   work.push(row);after=row.item_id;
  }
  if(work.length>total||page.has_more&&!page.work.length)throw Error('dataWarning');
  if(!page.has_more){if(work.length!==total)throw Error('dataWarning');return work;}
 }
}
