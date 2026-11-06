import {exactJsonNumbers} from './exact-json.mjs';
// Keep existing integer UI/revision contracts while retaining exact quantities.
const integers=new Set(['version','evidence_version','revision','page','page_size','total','frequency','missing_loss','missing_scrap']);
export function decodeConsumerJson(text){
 const convert=value=>Array.isArray(value)?value.map(convert):value&&typeof value==='object'?Object.fromEntries(Object.entries(value).map(([key,item])=>{
  if(integers.has(key)&&typeof item==='string'&&/^\d+$/.test(item)){
   const n=Number(item);if(!Number.isSafeInteger(n))throw {code:'CONSUMER_CONTRACT'};return [key,n];
  }
  return [key,convert(item)];
 })):value;
 return convert(JSON.parse(exactJsonNumbers(text)));
}
export function consumerFetch(fetcher=globalThis.fetch){
 return async(input,init)=>{
  const url=new URL(typeof input==='string'?input:input instanceof URL?input.href:input.url),response=await fetcher(input,init);
  if(!response.ok||!url.pathname.endsWith('/rest/v1/rpc/lean_read'))return response;
  const body=JSON.stringify(decodeConsumerJson(await response.text())),headers=new Headers(response.headers);
  headers.delete('content-length');headers.delete('content-encoding');
  return new Response(body,{status:response.status,statusText:response.statusText,headers});
 };
}
