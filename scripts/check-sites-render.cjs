// Exercise the packaged Worker entrypoints, including Vinext's dynamic SSR import.
const {Miniflare}=require('miniflare');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve('dist/server');
const paths=fs.readdirSync(root,{recursive:true}).filter(p=>/\.(mjs|js)$/.test(p)).map(p=>path.join(root,p));
const entry=path.join(root,'index.js');
const modules=[entry,...paths.filter(p=>p!==entry)].map(p=>({type:'ESModule',path:p}));
const runtime=new Miniflare({modules,modulesRoot:root,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],host:'127.0.0.1',port:0,inspectorPort:0});
(async()=>{try{const r=await runtime.dispatchFetch('https://factory.test/');const body=await r.text();assert.equal(r.status,200,body.slice(0,300));assert.ok(body.includes('Factory'),'Factory page rendered');console.log('PASS: packaged Worker renders factory login with HTTP 200');}catch(e){console.error(e.message);process.exitCode=1}finally{await runtime.dispose()}})();
