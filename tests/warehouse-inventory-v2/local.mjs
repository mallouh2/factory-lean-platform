import fs from 'node:fs';import {verifyRuntime} from '../production-recording-full-app/local-policy.mjs';
import {sql,c,root,owner,guard,as,quote} from '../warehouse-v2/local.mjs';
export {sql,c,root,owner,guard,as,quote};
verifyRuntime(c,fs.readFileSync(c.app+'/.env.local','utf8'));
export const dir=root+'/warehouse-inventory-v2';fs.mkdirSync(dir,{recursive:true});
if(process.argv.includes('--install-context')){const m=fs.readFileSync('supabase/migrations/20261101115302_warehouse_inventory_context_v2.sql','utf8');sql(m.replace('begin;',()=>`begin;${guard}`));console.log('Read-only inventory context installed on verified localhost '+c.databasePort);}
