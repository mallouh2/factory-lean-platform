import type {FeatureProps,OutputDestination} from './types';
import {outputDestinationAllowed,outputRelatedTargets} from '@/utils/output-navigation.mjs';
export default function OutputRecordLinks({props,record,omit}:{props:FeatureProps;record:{entry_id?:string;output_id?:string;item_id?:string;work_id?:string};omit?:OutputDestination['view']}){
 const f=String(props.snapshot.factory?.id||''),ar=props.lang==='ar';
 if(!props.onOutputRelated)return null;
 const words={production:['Production details','تفاصيل الإنتاج'],quality:['Quality inspection','فحص الجودة'],warehouse:['Production receipt','استلام الإنتاج'],planning:['Recovery / replacement work','أعمال الإكمال / التعويض'],order:['Original Production Order','أمر الإنتاج الأصلي']};
 const targets=(outputRelatedTargets(f,record) as OutputDestination[]).filter(d=>d.view!==omit&&outputDestinationAllowed(d,f,props.can));
 if(!targets.length)return null;
 return <nav className="output-record-links" aria-label={ar?'السجلات المرتبطة':'Related records'}>{targets.map((d:OutputDestination)=><button type="button" key={d.view} onClick={()=>props.onOutputRelated?.(d)}>{words[d.view][ar?1:0]}</button>)}</nav>;
}
