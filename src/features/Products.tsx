import { useRef, useState } from 'react';
import type { FeatureProps } from './types';
import type { Row } from '@/types';
import { Dialog, Field, localName } from '@/components/ui';
import { useSupply, type SupplyRow } from './useSupply';
type Component = { key:string; material_id:string; quantity:string };
export default function Products(props: FeatureProps) {
  const { snapshot:s, t, lang, can, command }=props;
  const [search,setSearch]=useState(''),[editing,setEditing]=useState<Row|null>(null),[kind,setKind]=useState('FINISHED_PRODUCT');
  const [components,setComponents]=useState<Component[]>([]),[changeFormula,setChangeFormula]=useState(false);
  const [busy,setBusy]=useState(false),[error,setError]=useState('');
  const [preview,setPreview]=useState<Row|null>(null),[quantity,setQuantity]=useState('1');
  const retry=useRef<{key:string;id:string}|null>(null),submitting=useRef(false);
  const raw=useSupply(s,'formulas',{...(editing?.id?{selected:String(editing.id)}:{})},!!editing);
  const requirements=useSupply<{theoretical:boolean;compound_quantity_kg:number|null;formula_version:number|null;raw_materials:SupplyRow[]|null}>(s,'requirements',
    {selected:String(preview?.id||''),quantity,unit:String(preview?.stock_unit||'')},!!preview&&Number(quantity)>0&&!!preview.stock_unit);
  const fields=['name','name_ar','code','category','unit','diameter','length','color','weight','standard_rate'];
  const numeric=['diameter','length','weight','standard_rate'];
  const rows=s.tables.products.filter(row=>(localName(row,lang)+' '+row.code).toLowerCase().includes(search.toLowerCase()));
  const open=(row:Row)=>{setEditing(row);setKind(String(row.product_kind||'FINISHED_PRODUCT'));setComponents([]);setChangeFormula(false);setError('');};
  async function save(event:React.FormEvent<HTMLFormElement>) {
    event.preventDefault();if(submitting.current||!editing)return;
    const form=new FormData(event.currentTarget);
    const payload:Record<string,unknown>=Object.fromEntries(fields.map(key=>[key,numeric.includes(key)?(form.get(key)===''?null:Number(form.get(key))):String(form.get(key)||'')]));
    Object.assign(payload,{stage:editing.stage||'finished',product_kind:kind,stock_unit:kind==='MANUFACTURED_INTERMEDIATE'?'kg':form.get('stock_unit')||null,
      formula_product_id:kind==='MANUFACTURED_INTERMEDIATE'?null:form.get('formula_product_id')||null,unit_weight_kg:form.get('unit_weight_kg')?Number(form.get('unit_weight_kg')):null});
    if(kind==='MANUFACTURED_INTERMEDIATE')payload.unit='kg';
    const recipe=changeFormula?components.map(({material_id,quantity})=>({material_id,quantity:Number(quantity),unit:'kg'})):null;
    const args={factory:s.factory?.id,product:editing.id||null,payload,components:recipe};
    const key=JSON.stringify(args);if(retry.current?.key!==key)retry.current={key,id:crypto.randomUUID()};
    submitting.current=true;setBusy(true);setError('');
    try{await command('define_manufactured_product',{...args,request_id:retry.current.id});retry.current=null;setEditing(null);}
    catch(cause){setError(cause instanceof Error?cause.message:'error');}
    finally{submitting.current=false;setBusy(false);}
  }
  return <section className="panel supply-page" dir={lang==='ar'?'rtl':'ltr'}>
    <header className="section-head"><input aria-label={t('search')} placeholder={t('search')} value={search} onChange={e=>setSearch(e.target.value)}/>{can('orders','create')&&<button className="primary" onClick={()=>open({})}>{t('addProduct')}</button>}</header>
    {!rows.length&&<p className="empty">{t('noProductsYet')}</p>}
    <div className="supply-directory">{rows.map(row=><article key={String(row.id)}><strong>{localName(row,lang)}</strong><p><bdi>{String(row.code)}</bdi> · {t(String(row.product_kind||'FINISHED_PRODUCT'))} · {row.stock_unit?t(String(row.stock_unit)):t('inventoryNotConfigured')}</p>
      <div className="row-actions">{can('orders','edit')&&<button onClick={()=>open(row)}>{t('edit')}</button>}{(row.formula_product_id||row.product_kind==='MANUFACTURED_INTERMEDIATE')&&<button disabled={!row.stock_unit} onClick={()=>{setPreview(row);setQuantity('1');}}>{t('recipeRequirements')}</button>}</div></article>)}</div>
    {editing&&<Dialog title={t(editing.id?'editProduct':'addProduct')} t={t} onClose={()=>{if(!busy)setEditing(null);}}>
      <form onSubmit={save}><fieldset disabled={busy} className="form-grid">
        <Field label={t('inventoryType')}><select value={kind} onChange={e=>setKind(e.target.value)}>{['FINISHED_PRODUCT','MANUFACTURED_INTERMEDIATE'].map(value=><option key={value} value={value}>{t(value)}</option>)}</select></Field>
        {fields.filter(key=>kind!=='MANUFACTURED_INTERMEDIATE'||key!=='unit').map(key=><Field key={key} label={t(key)}><input name={key} required={['name','code','unit'].includes(key)} type={numeric.includes(key)?'number':'text'} step={numeric.includes(key)?'any':undefined} defaultValue={String(editing[key]??'')}/></Field>)}
        {kind==='FINISHED_PRODUCT'?<>
          <Field label={t('stockUnit')}><select name="stock_unit" defaultValue={String(editing.stock_unit||'')}><option value="">{t('inventoryNotConfigured')}</option>{['meter','piece'].map(value=><option key={value} value={value}>{t(value)}</option>)}</select></Field>
          <Field label={t('recipeCompound')}><select name="formula_product_id" defaultValue={String(editing.formula_product_id||'')}><option value="">{t('recipeNoFormula')}</option>{s.tables.products.filter(row=>row.product_kind==='MANUFACTURED_INTERMEDIATE'&&row.stock_unit==='kg').map(row=><option key={String(row.id)} value={String(row.id)}>{localName(row,lang)}</option>)}</select></Field>
          <Field label={t('recipeUnitWeight')}><input name="unit_weight_kg" type="number" step="any" min="0.000001" defaultValue={String(editing.unit_weight_kg||'')}/></Field>
        </>:<>
          <p>{t('recipeBasis')}</p>{raw.data?.selected&&<p>{t('recipeVersion')}: {String(raw.data.selected.version)}</p>}
          <label><input type="checkbox" checked={changeFormula} onChange={e=>{setChangeFormula(e.target.checked);if(e.target.checked&&!components.length){const saved=raw.data?.selected?.components as SupplyRow[]|undefined;setComponents(saved?.length?saved.map(row=>({key:crypto.randomUUID(),material_id:String(row.material_id),quantity:String(row.quantity)})):[{key:crypto.randomUUID(),material_id:'',quantity:''}]);}}}/>{t('recipeEdit')}</label>
          {changeFormula&&<div className="recipe-components">{components.map((row,index)=><div className="row-actions" key={row.key}>
            <Field label={t('rawMaterial')}><select required value={row.material_id} onChange={e=>setComponents(old=>old.map(part=>part.key===row.key?{...part,material_id:e.target.value}:part))}><option value="">{t('select')}</option>{raw.data?.rows.map(material=><option key={String(material.id)} value={String(material.id)}>{String(lang==='ar'?material.name_ar||material.name:material.name)}</option>)}</select></Field>
            <Field label={t('quantity')+' (kg)'}><input type="number" min="0.000001" step="any" required value={row.quantity} onChange={e=>setComponents(old=>old.map(part=>part.key===row.key?{...part,quantity:e.target.value}:part))}/></Field>
            <button type="button" aria-label={t('remove')+' '+(index+1)} onClick={()=>setComponents(old=>old.filter(part=>part.key!==row.key))}>{t('remove')}</button>
          </div>)}<button type="button" onClick={()=>setComponents(old=>[...old,{key:crypto.randomUUID(),material_id:'',quantity:''}])}>{t('recipeAddMaterial')}</button></div>}
        </>}
        {(error||raw.error)&&<p role="alert">{t(error||raw.error)}</p>}<button className="primary" disabled={busy||(changeFormula&&!components.length)}>{t('save')}</button>
      </fieldset></form></Dialog>}
    {preview&&<Dialog title={t('recipeRequirements')} t={t} onClose={()=>setPreview(null)}><strong>{localName(preview,lang)}</strong>
      <Field label={t('quantity')+' ('+t(String(preview.stock_unit))+')'}><input type="number" step="any" min="0.000001" value={quantity} onChange={e=>setQuantity(e.target.value)}/></Field>
      <p>{t('recipeTheoretical')}</p>{requirements.busy&&<p role="status">{t('loading')}</p>}{requirements.error&&<p role="alert">{t(requirements.error)}</p>}
      {requirements.data?.raw_materials?<><p>{t('recipeCompound')}: {requirements.data.compound_quantity_kg} kg · {t('recipeVersion')}: {requirements.data.formula_version}</p>
        <ul>{requirements.data.raw_materials.map(row=><li key={String(row.id)}>{String(lang==='ar'?row.name_ar||row.name:row.name)}: {Number(row.quantity).toLocaleString(lang)} kg</li>)}</ul></>:!requirements.busy&&<p>{t('recipeMissing')}</p>}
    </Dialog>}
  </section>;
}
