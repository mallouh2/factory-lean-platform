// Only serves a synthetic offline fixture on loopback. No application server starts.
import {createServer} from 'node:http';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {tmpdir} from 'node:os';
import {build} from 'esbuild';
const root=resolve(tmpdir(),'FactoryLean-Quality-UI-20261010');await mkdir(root,{recursive:true});
await build({entryPoints:['tests/quality/browser-fixture.tsx'],bundle:true,platform:'browser',jsx:'automatic',outfile:join(root,'preview.js'),logLevel:'silent'});
await writeFile(join(root,'styles.css'),await readFile('src/app/globals.css'));
const html='<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Offline Quality V1 verification</title><link rel="stylesheet" href="/styles.css"><div id="root"></div><script src="/preview.js"></script></html>';
const server=createServer(async(req,res)=>{
 const file={'/preview.js':'preview.js','/styles.css':'styles.css'}[req.url];
 if(req.url!=='/'&&!file){res.writeHead(404);res.end();return;}
 res.setHeader('Content-Type',file?.endsWith('.js')?'application/javascript':file?'text/css':'text/html');res.setHeader('Cache-Control','no-store');
 res.end(file?await readFile(join(root,file)):html);
});
server.listen(4202,'127.0.0.1',()=>console.log('Offline fixture: http://127.0.0.1:4202/'));
