import {useState}from'react';
import {Field}from'./ui';
import type{Language,Translate}from'@/types';
import data from'@/data/factory-timezones.json';
// Selection affects timezone metadata only; no saved schedule instant is converted here.
export default function FactoryTimezone({lang,t,initialZone=''}:{lang:Language;t:Translate;initialZone?:string}){
 const[country,setCountry]=useState(''),[zone,setZone]=useState(initialZone);
 const countries=data.countries as Record<string,{zone:string;region:string}[]>,names=new Intl.DisplayNames([lang],{type:'region'}),options=country?countries[country]:initialZone?[{zone:initialZone,region:initialZone}]:[];
 return <div className="form-grid"><Field label={t('factoryCountry')}><select required={!initialZone} value={country} onChange={e=>{const code=e.target.value;setCountry(code);const zones=countries[code]||[];setZone(zones.length===1?zones[0].zone:'');}}><option value="">{t('select')}</option>{Object.keys(countries).sort((a,b)=>(names.of(a)||a).localeCompare(names.of(b)||b,lang)).map(code=><option key={code} value={code}>{names.of(code)||code}</option>)}</select></Field>
 <Field label={t('factoryCityTimezone')}><select name="timezone" required value={zone} onChange={e=>setZone(e.target.value)}><option value="">{t('select')}</option>{options.map(x=><option key={x.zone} value={x.zone}>{x.region} · {x.zone}</option>)}</select></Field></div>;
}
