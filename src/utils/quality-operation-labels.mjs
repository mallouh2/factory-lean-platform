// Distinct routing-step IDs stay distinct. Never infer sequence from array order.
export function qualityOperationLabels(operations,steps,centers,lang){
 const name=o=>lang==='ar'?o.name_ar||o.name:o.name;
 const labels=operations.map(o=>{const same=operations.filter(x=>name(x)===name(o)).length>1;
  const step=steps.find(x=>x.id===o.id),center=centers.find(x=>x.id===(o.work_center_id||step?.work_center_id));
  const detail=[step?.position!=null?(lang==='ar'?'الخطوة ':'Step ')+step.position:null,center?(lang==='ar'?center.name_ar||center.name:center.name):null].filter(Boolean);
  return {...o,label:same?name(o)+' · '+(detail.length?detail.join(' · '):'ID '+o.id.slice(-8)):name(o)};
 });
 return labels.map(o=>labels.filter(x=>x.label===o.label).length>1?{...o,label:o.label+' · ID '+o.id}:o);
}
