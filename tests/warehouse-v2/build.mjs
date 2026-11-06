import fs from 'node:fs';import path from 'node:path';import {spawnSync} from 'node:child_process';
import {c,root} from './local.mjs';
const app=path.join(root,process.argv.includes('--complete')?'warehouse-v2-complete-app':process.argv.includes('--release')?'warehouse-v2-release-app':process.argv.includes('--final')?'warehouse-v2-final-app':'warehouse-v2-app');if(fs.existsSync(app))throw Error('Use existing build result; do not overwrite a running bundle');fs.mkdirSync(app);
for(const file of ['package.json','package-lock.json','tsconfig.json','next-env.d.ts','next.config.ts'])if(fs.existsSync(file))fs.copyFileSync(file,path.join(app,file));
fs.copyFileSync(path.join(c.app,'.env.local'),path.join(app,'.env.local'));
fs.cpSync('src',path.join(app,'src'),{recursive:true});if(fs.existsSync('public'))fs.cpSync('public',path.join(app,'public'),{recursive:true});
fs.symlinkSync(path.resolve('node_modules'),path.join(app,'node_modules'),'junction');
for(const args of [['node_modules/typescript/bin/tsc','--noEmit'],['node_modules/next/dist/bin/next','build','--webpack']]){const r=spawnSync(process.execPath,args,{cwd:app,encoding:'utf8',windowsHide:true});fs.mkdirSync(root+'/warehouse-v2',{recursive:true});fs.writeFileSync(root+'/warehouse-v2/'+(args[0].includes('typescript')?'typecheck':'build')+'.txt',r.stdout+r.stderr);if(r.status)throw Error(r.stdout+r.stderr);}
console.log('TypeScript and isolated production build PASS: '+app);
