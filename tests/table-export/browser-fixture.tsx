// Actual Quality + TableExport components, synthetic local API. No remote connections.
import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
import Quality from '../../src/features/Quality';
import en from '../../src/locales/en.json';
import ar from '../../src/locales/ar.json';
const id = (n: number) => `10000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
function Fixture() {
  const [lang, setLang] = useState<'en' | 'ar'>(new URLSearchParams(location.search).get('language') === 'ar' ? 'ar' : 'en'), [permission, setPermission] = useState(true);
  const d: Record<string, string> = lang === 'ar' ? ar : en;
  return <main style={{ maxWidth: 1320, padding: 16, margin: 'auto' }} dir={lang === 'ar' ? 'rtl' : 'ltr'}>
    <header className="section-head"><div><strong>Offline Table Export verification</strong><p className="muted">Synthetic data · no database connection</p></div><div className="row-actions">
      <button onClick={() => { document.documentElement.lang = lang === 'en' ? 'ar' : 'en'; document.documentElement.dir = lang === 'en' ? 'rtl' : 'ltr'; setLang(lang === 'en' ? 'ar' : 'en'); }}>English / العربية</button>
      <button onClick={() => setPermission(!permission)}>History permission: {permission ? 'on' : 'off'}</button></div></header>
    <Quality lang={lang} t={key => d[key] || key} can={module => module !== 'quality_history' || permission}
      snapshot={{ factory: { id: id(9), name: 'Demo Factory', timezone: 'Asia/Riyadh' }, user: { id: id(8) }, membership: null, permissions: [], tables: {}, supportFactories: [], fetchedAt: 'offline' }}
      command={async () => { throw Error('Offline writes disabled'); }}/>
  </main>;
}
createRoot(document.getElementById('root')!).render(<Fixture/>);
