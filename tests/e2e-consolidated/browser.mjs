import fs from'node:fs';import{createRequire}from'node:module';import{root,c}from'./local.mjs';
export const x=JSON.parse(fs.readFileSync(root+'/acceptance-context.json'));
export const {chromium}=createRequire(import.meta.url)('C:/Users/Temp/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
export async function login(page,role='owner',view='planning'){
 const a=JSON.parse(fs.readFileSync(root+'/local-credentials.json')).accounts.find(a=>a.id===c.context[role]);
 await page.route('**/*',r=>new URL(r.request().url()).origin==='http://127.0.0.1:4242'?r.continue():r.abort());
 await page.goto('http://127.0.0.1:4242/?view='+view);await page.locator('input[name=email]').fill(a.email);await page.locator('input[name=password]').fill(a.password);await page.locator('form button.primary').click();await page.locator('.app-shell').waitFor({timeout:60000});
}
