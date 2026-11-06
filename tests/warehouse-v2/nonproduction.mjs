import assert from 'node:assert/strict';import fs from 'node:fs';import {sql,c,root,guard,as,quote} from './local.mjs';
if(process.argv.includes('--owner'))throw Error('QA only');
const f=c.context.factory,a=c.context.owner,ws=JSON.parse(sql(`begin;${as(a,`select public.factory_warehouses_read(${quote(f)});`)}rollback;`)).rows,raw=ws.find(w=>w.storage_class==='RAW'),finished=ws.find(w=>w.active&&w.storage_class==='FINISHED');
function query(source,warehouse=raw.id){return `begin;${guard}${as(a,`do $$declare item uuid;retry uuid:=gen_random_uuid();p jsonb;first uuid;second uuid;begin
 item:=public.create_warehouse_material(${quote(f)},'{"name":"Warehouse V2 raw fixture","name_ar":"مادة اختبار","code":"V2-RAW-SQL","unit":"kg","inventory_kind":"RAW_MATERIAL"}',gen_random_uuid());
 p:=jsonb_build_object('item',item,'item_type','material','unit','kg','quantity',2.5,'source',${quote(source)},'reference','V2 isolated fixture','note','','warehouse_id',${quote(warehouse)});
 first:=public.receive_warehouse_stock_at(${quote(f)},p,retry);second:=public.receive_warehouse_stock_at(${quote(f)},p,retry);if first<>second then raise exception 'duplicate_receipt';end if;end$$;`)}reset role;
 do $$begin if (select count(*) from private.stock_receipt_warehouses where factory_id=${quote(f)} and payload->>'reference'='V2 isolated fixture')<>1 or (select sum(quantity) from public.inventory_transactions where factory_id=${quote(f)} and reference='V2 isolated fixture')<>2.5 then raise exception 'stock_conservation';end if;end$$;rollback;`;}
const results=[];for(const source of ['external_receipt','opening_balance']){sql(query(source));results.push(source+': no Quality requirement, original ledger credit once, warehouse bound');}
assert.throws(()=>sql(query('external_receipt',finished.id)),/warehouse_incompatible/);results.push('incompatible raw destination rejected before movement');
assert.throws(()=>sql(query('external_receipt').replaceAll(`request.jwt.claim.sub=${quote(a)}`,`request.jwt.claim.sub=${quote(c.context.viewer)}`)),/permission_denied/);results.push('restricted non-production receipt denied');
console.log({status:'PASS',passed:results.length,results});fs.writeFileSync(root+'/warehouse-v2/nonproduction.json',JSON.stringify({status:'PASS',results},null,2));
