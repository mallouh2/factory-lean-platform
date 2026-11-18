import ProductEditor from './ProductEditor';
import {ProductMaterialRoute} from './MaterialPreparation';
import { useState } from 'react';
import type { FeatureProps } from './types';
import type { Row } from '@/types';
import { Dialog, Field, localName } from '@/components/ui';
import { useSupply, type SupplyRow } from './useSupply';
export default function Products(props: FeatureProps) {
  const { snapshot:s, t, lang, can }=props;
  const [routeProduct,setRouteProduct]=useState('');
  const [search,setSearch]=useState(''),[editing,setEditing]=useState<Row|null>(null);
  const [preview,setPreview]=useState<Row|null>(null),[quantity,setQuantity]=useState('1');
  const requirements=useSupply<{theoretical:boolean;compound_quantity_kg:number|null;formula_version:number|null;raw_materials:SupplyRow[]|null}>(s,'requirements',
    {selected:String(preview?.id||''),quantity,unit:String(preview?.stock_unit||'')},!!preview&&Number(quantity)>0&&!!preview.stock_unit);
  const rows=s.tables.products.filter(row=>(localName(row,lang)+' '+row.code).toLowerCase().includes(search.toLowerCase()));
  const open=(row:Row)=>{setEditing(row);};
  return <section className="panel supply-page" dir={lang==='ar'?'rtl':'ltr'}>
    <header className="section-head"><input aria-label={t('search')} placeholder={t('search')} value={search} onChange={e=>setSearch(e.target.value)}/>{can('orders','create')&&<button className="primary" onClick={()=>open({})}>{t('addProduct')}</button>}</header>
    {!rows.length&&<p className="empty">{t('noProductsYet')}</p>}
    <div className="supply-directory">{rows.map(row=><article key={String(row.id)}><strong>{localName(row,lang)}</strong><p><bdi>{String(row.code)}</bdi> · {t(String(row.product_kind||'FINISHED_PRODUCT'))} · {row.stock_unit?t(String(row.stock_unit)):t('inventoryNotConfigured')}</p>
      <div className="row-actions">{can('orders','edit')&&<button onClick={()=>setRouteProduct(String(row.id))}>{t('materialPhysicalInputs')}</button>}{can('orders','edit')&&<button onClick={()=>open(row)}>{t('edit')}</button>}{row.stock_unit&&<button disabled={!row.stock_unit} onClick={()=>{setPreview(row);setQuantity('1');}}>{t('recipeRequirements')}</button>}</div></article>)}</div>
    {routeProduct&&<ProductMaterialRoute props={props} product={routeProduct} onClose={()=>setRouteProduct('')}/>}
    {editing&&<ProductEditor props={props} product={editing} onClose={()=>setEditing(null)} onSaved={()=>setEditing(null)}/> }
    {preview&&<Dialog title={t('recipeRequirements')} t={t} onClose={()=>setPreview(null)}><strong>{localName(preview,lang)}</strong>
      <Field label={t('quantity')+' ('+t(String(preview.stock_unit))+')'}><input type="number" step="any" min="0.000001" value={quantity} onChange={e=>setQuantity(e.target.value)}/></Field>
      <p>{t('recipeTheoretical')}</p>{requirements.busy&&<p role="status">{t('loading')}</p>}{requirements.error&&<p role="alert">{t(requirements.error)}</p>}
      {requirements.data?.raw_materials?<><p>{t('recipeCompound')}: {requirements.data.compound_quantity_kg} kg · {t('recipeVersion')}: {requirements.data.formula_version}</p>
        <ul>{requirements.data.raw_materials.map(row=><li key={String(row.id)}>{String(lang==='ar'?row.name_ar||row.name:row.name)}: {Number(row.quantity).toLocaleString(lang)} kg</li>)}</ul></>:!requirements.busy&&<p>{t('recipeMissing')}</p>}
    </Dialog>}
  </section>;
}
