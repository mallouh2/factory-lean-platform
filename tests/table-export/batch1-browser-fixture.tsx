// Actual operational components, synthetic read responses, no remote clients or writes.
import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
import ProductionHistory from '../../src/features/ProductionHistory';
import WarehouseInventory from '../../src/features/WarehouseInventory';
import WarehouseReceiving from '../../src/features/WarehouseReceiving';
import en from '../../src/locales/en.json';
import ar from '../../src/locales/ar.json';
const id = (n: number) => `10000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
function Fixture() {
  const [lang, setLang] = useState<'en' | 'ar'>('en'), [view, setView] = useState('production'), [allowed, setAllowed] = useState(true);
  const d: Record<string, string> = lang === 'ar' ? ar : en;
  const props = { lang, t: (key: string) => d[key] || key, can: (_module: string, action?: string) => allowed && (!action || action === 'view'),
    snapshot: { factory: { id: id(9), name: 'Demo Factory', timezone: 'Asia/Riyadh' }, user: { id: id(8) }, membership: null, permissions: [], tables: {
      products: [{ id: id(3), name: 'Pressure pipe', name_ar: 'أنبوب ضغط', code: 'P-25', stage: 'finished', stock_unit: 'meter' }], production_shifts: [],
    }, supportFactories: [], fetchedAt: 'offline' }, command: async () => { throw Error('Offline writes disabled'); } };
  return <main style={{ maxWidth: 1320, padding: 16, margin: 'auto' }} dir={lang === 'ar' ? 'rtl' : 'ltr'}>
    <header className="section-head"><strong>Offline Batch 1 verification</strong><div className="row-actions">
      <button onClick={() => { document.documentElement.lang = lang === 'en' ? 'ar' : 'en'; document.documentElement.dir = lang === 'en' ? 'rtl' : 'ltr'; setLang(lang === 'en' ? 'ar' : 'en'); }}>English / العربية</button>
      <button onClick={() => setAllowed(!allowed)}>View permission: {allowed ? 'on' : 'off'}</button></div></header>
    <nav className="row-actions" aria-label="Fixture views">{['production', 'stock', 'movements'].map(value => <button key={value} onClick={() => setView(value)}>{value}</button>)}</nav>
    {view === 'production' ? <ProductionHistory {...props} onCorrect={() => { throw Error('Offline writes disabled'); }}/>
      : view === 'stock' ? <WarehouseInventory {...props} onChanged={() => {}} onConfigure={() => {}} onReceive={() => {}}/>
      : <WarehouseReceiving {...props} refresh={() => {}} showMaterials={false} materials={[{ id: id(7), name: 'Resin', name_ar: 'راتنج', code: 'R-1', unit: 'kg', inventory_kind: 'RAW_MATERIAL', on_hand: 20, reserved: 5 }]}/>}
  </main>;
}
createRoot(document.getElementById('root')!).render(<Fixture/>);
