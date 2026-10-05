import { NextRequest, NextResponse } from 'next/server';
import { authenticatedClient, authorize, safeError } from '@/services/authorization';
import { parseHistoryQuery } from '@/utils/production-history.mjs';
export async function GET(req: NextRequest) {
  try {
    const context=await authenticatedClient();
    const factory=req.nextUrl.searchParams.get('factory') || '';
    await authorize(factory,'orders','view',context);
    const values=req.nextUrl.searchParams.get('field');
    const args=values ? {factory,field:values,search:req.nextUrl.searchParams.get('search') || '',page:Number(req.nextUrl.searchParams.get('values_page') || 1)} : req.nextUrl.searchParams.get('options')==='1' ? {factory} : {factory,...parseHistoryQuery(req.nextUrl.searchParams)};
    const {data,error}=await context.db.rpc(values ? 'production_history_values' : req.nextUrl.searchParams.get('options')==='1' ? 'production_history_options' : 'production_history',args);
    if(error) throw error;
    if(!values&&req.nextUrl.searchParams.get('options')!=='1'&&data?.rows?.length){
      const {data:mass,error:massError}=await context.db.from('production_entries').select('id,effective_scrap_kg,effective_startup_kg,lean_startup_id,produced_weight_kg,weight_kg_per_unit').eq('factory_id',factory).in('id',data.rows.map((x:{id:string})=>x.id));
      if(massError)throw massError;
      data.rows=data.rows.map((x:{id:string})=>({...x,...mass?.find(y=>y.id===x.id)}));
    }
    return NextResponse.json(data,{headers:{'Cache-Control':'private, no-store'}});
  }catch(error){return NextResponse.json(safeError(error),{status:403});}
}
