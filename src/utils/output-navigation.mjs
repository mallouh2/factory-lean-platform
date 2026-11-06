const uuid=v=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
export function outputDestinationAllowed(d,factory,can){
 if(!d||!uuid(factory)||d.factory!==factory)return false;
 if(['production','quality'].includes(d.view))return uuid(d.entry)&&can(d.view==='quality'?'quality':'orders','view');
 if(d.view==='warehouse')return uuid(d.output)&&can('warehouse','view');
 if(d.view==='planning')return uuid(d.output)&&(d.work===undefined||uuid(d.work))&&can('orders','view');
 return d.view==='order'&&uuid(d.item)&&can('orders','view');
}
export function outputRelatedTargets(factory,record){
 return [
  {factory,view:'production',entry:record.entry_id},
  {factory,view:'quality',entry:record.entry_id},
  {factory,view:'warehouse',output:record.output_id},
  {factory,view:'planning',output:record.output_id,...(record.work_id?{work:record.work_id}:{})},
  {factory,view:'order',item:record.item_id}
 ];
}
