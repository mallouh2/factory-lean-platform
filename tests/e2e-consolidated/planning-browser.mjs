import fs from'node:fs';import assert from'node:assert/strict';import{chromium,login,x}from'./browser.mjs';import{root,sql,quote}from'./local.mjs';
const b=await chromium.launch({channel:'msedge',headless:true}),p=await b.newPage({viewport:{width:1440,height:1000}});p.setDefaultTimeout(60000);const evidence=[];fs.mkdirSync(root+'/screenshots',{recursive:true});
try{await login(p);await p.getByRole('button',{name:'Next',exact:true}).click();
 const code=sql(`select code from public.production_orders where id=${quote(x.short)}`),source=p.locator('button').filter({hasText:code}).first();
 const actualSource=source;
 const lane=p.locator(`[data-line-id="${x.schedule_line}"] .planning-lane-track`);await lane.scrollIntoViewIfNeeded();const r=await lane.boundingBox(),data=await p.evaluateHandle(()=>new DataTransfer());
 await actualSource.dispatchEvent('dragstart',{dataTransfer:data,clientX:20});await lane.dispatchEvent('dragover',{dataTransfer:data,clientX:r.x+r.width*.4});
 await p.locator('.planning-pointer-ghost').waitFor();const preview=await p.locator('.planning-pointer-ghost').evaluate(el=>({start:el.getAttribute('data-preview-start'),finish:el.getAttribute('data-preview-finish'),width:el.getBoundingClientRect().width}));assert.equal(Number(preview.finish)-Number(preview.start),60000);assert.ok(preview.width<2);await p.screenshot({path:root+'/screenshots/planning-short-preview.png'});
 await lane.dispatchEvent('drop',{dataTransfer:data,clientX:r.x+r.width*.4});await p.waitForFunction(()=>!document.querySelector('.planning-pointer-ghost'));await p.waitForTimeout(1500);
 const saved=JSON.parse(sql(`select json_build_object('start',extract(epoch from start_time)*1000,'finish',extract(epoch from expected_finish)*1000) from public.production_orders where id=${quote(x.short)}`));assert.equal(Number(saved.start),Number(preview.start));assert.equal(Number(saved.finish),Number(preview.finish));evidence.push({preview,saved});
 // Open the other small fixture through the ordinary scheduling drawer.
 const longCode=sql(`select code from public.production_orders where id=${quote(x.long)}`);await p.locator('button').filter({hasText:longCode}).first().click();await p.getByRole('dialog').waitFor();const dialog=p.getByRole('dialog');
 console.log((await dialog.innerText()).slice(0,1700));await p.screenshot({path:root+'/screenshots/planning-drawer-en.png'});
 const before=await dialog.evaluate(el=>({height:el.getBoundingClientRect().height,scroll:el.scrollTop,inputs:[...el.querySelectorAll('input,select')].map(x=>x.value)}));
 for(let i=0;i<2;i++){const response=p.waitForResponse(r=>r.url().includes('/api/data')&&r.request().method()==='GET',{timeout:45000});await response;await p.waitForTimeout(1200);const after=await dialog.evaluate(el=>({height:el.getBoundingClientRect().height,scroll:el.scrollTop,inputs:[...el.querySelectorAll('input,select')].map(x=>x.value)}));assert.deepEqual(after,before);evidence.push({cycle:i+1,stable:true});}
 fs.writeFileSync(root+'/planning-browser.json',JSON.stringify(evidence,null,2));console.log(evidence);
}finally{await b.close()}
