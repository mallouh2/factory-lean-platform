import { NextRequest, NextResponse } from "next/server";
import { authorize, verifyOrigin, safeError } from "@/services/authorization";
import { csvCell, downtimeMinutes, reportPeriod } from "@/utils/manufacturing.mjs";
import en from "@/locales/en.json";
import ar from "@/locales/ar.json";
export async function POST(req: NextRequest) {
  try {
    verifyOrigin(req);
    const p = await req.json();
    const {db}=await authorize(p.factory,"reports","export");
    const {data:allowed}=await db.rpc("can_access",{factory:p.factory,module:"downtime",action:"view"});
    if(!allowed) throw new Error("permission_denied");
    const {data:factory,error}=await db.from("factories").select("timezone").eq("id",p.factory).single();
    if(error) throw error;
    if(!["today","yesterday","week","month","custom"].includes(p.period))throw new Error("invalid_input");
    if(p.period==="custom"&&(!p.from||!p.to||p.to<p.from))throw new Error("invalid_input");
    const range=reportPeriod(p.period,factory.timezone,new Date(),p.from,p.to);
    if(Date.parse(range.to)-Date.parse(range.from)>366*86400000) throw new Error("invalid_input");
    const [{data:centers,error:ce},{data:reasons,error:re}]=await Promise.all([
      db.from("work_centers").select("id,name,name_ar,line_id,area_id").eq("factory_id",p.factory),
      db.from("downtime_reasons").select("id,name,name_ar").eq("factory_id",p.factory)
    ]);
    if(ce||re)throw ce||re;
    const filtered=centers!.filter(c=>(!p.area||p.area==="all"||c.area_id===p.area)&&(!p.line||p.line==="all"||c.line_id===p.line)&&(!p.machine||p.machine==="all"||c.id===p.machine));
    const dictionary=p.lang==="ar"?ar:en;
    const label=(r: {name:string;name_ar:string}|undefined)=>r?((p.lang==="ar"&&r.name_ar)||r.name):"";
    const rows:unknown[][]=[[dictionary.centers,dictionary.reason,dictionary.subReason,dictionary.started,dictionary.ended,dictionary.duration]];
    for(let offset=0;offset<20000;offset+=1000){
      const {data,error}=await db.from("downtime_events").select("*").eq("factory_id",p.factory).lt("started_at",range.to).or(`ended_at.is.null,ended_at.gt.${range.from}`).order("started_at").order("id").range(offset,offset+999);
      if(error)throw error;
      for(const event of data){const center=filtered.find(c=>c.id===event.work_center_id);if(!center||(p.reason&&p.reason!=="all"&&![event.reason_id,event.sub_reason_id].includes(p.reason)))continue;
        rows.push([label(center),label(reasons!.find(r=>r.id===event.reason_id)),label(reasons!.find(r=>r.id===event.sub_reason_id)),event.started_at,event.ended_at,downtimeMinutes(event,range.from,range.to).toFixed(2)]);
      }
      if(data.length<1000)break;
      if(offset===19000)return NextResponse.json({error:"exportLimit"},{status:400});
    }
    const {error:ae}=await db.rpc("record_access",{factory:p.factory,operation:"EXPORT"});if(ae)throw ae;
    return new NextResponse("\uFEFF"+rows.map(r=>r.map(csvCell).join(",")).join("\r\n"),{headers:{"Content-Type":"text/csv; charset=utf-8","Content-Disposition":'attachment; filename="downtime-report.csv"',"Cache-Control":"private, no-store"}});
  }catch(e){return NextResponse.json(safeError(e),{status:400})}
}
