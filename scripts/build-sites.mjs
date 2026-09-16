import { existsSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
// Both adapters generate route declarations. Preserve Next's files for the Node workflow.
const files=['next-env.d.ts','.next/types/routes.d.ts'];
const original=new Map(files.map(file=>[file,existsSync(file)?readFileSync(file):null]));
try {
 const result=spawnSync(process.execPath,['node_modules/vite/bin/vite.js','build'],{stdio:'inherit'});
 if(result.status!==0)process.exitCode=result.status || 1;
 else writeFileSync('dist/server/index.js','export { default } from "./index.mjs";\n');
} finally {
 for(const [file,contents] of original){if(contents)writeFileSync(file,contents);else rmSync(file,{force:true});}
}
