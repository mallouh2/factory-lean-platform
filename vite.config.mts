// Optional Sites deployment adapter. The existing Next.js/Node build remains unchanged.
import vinext from 'vinext';
import { defineConfig } from 'vite';
import { sites } from './build/sites-vite-plugin';
export default defineConfig(async () => {
  process.env.CLOUDFLARE_CF_FETCH_ENABLED = 'false';
  process.env.WRANGLER_SEND_METRICS = 'false';
  process.env.WRANGLER_WRITE_LOGS = 'false';
  const { cloudflare } = await import('@cloudflare/vite-plugin');
  return {
    server: {host:'0.0.0.0',allowedHosts:['terminal.local']},
    plugins: [vinext(), sites({mockAuth:false}), cloudflare({
      viteEnvironment:{name:'rsc',childEnvironments:['ssr']},
      inspectorPort:false,
      config:{name:'factory-lean-preview',main:'vinext/server/fetch-handler',compatibility_date:'2026-05-15',compatibility_flags:['nodejs_compat']},
    })],
  };
});
