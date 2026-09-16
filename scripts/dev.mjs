// Preserve Next.js locally; the supervised Sites preview forwards Vite-specific flags.
import {spawn} from 'node:child_process';
const args=process.argv.slice(2), preview=args.includes('--strictPort');
const child=spawn(process.execPath, preview?['node_modules/vite/bin/vite.js',...args]:['node_modules/next/dist/bin/next','dev','--hostname','0.0.0.0',...args],{stdio:'inherit',env:process.env});
for(const signal of ['SIGTERM','SIGINT']) process.on(signal,()=>child.kill(signal));
child.on('exit',code=>process.exit(code??1));
