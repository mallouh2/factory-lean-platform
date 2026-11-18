// The same authenticated evidence handler serves hosted Edge and the guarded local adapter.
import {createLeanComparisonHandler} from './handler.mjs';
declare const Deno:{env:{get(key:string):string|undefined};serve(fn:(req:Request)=>Promise<Response>):void};
Deno.serve(createLeanComparisonHandler({url:Deno.env.get('SUPABASE_URL'),key:Deno.env.get('SUPABASE_ANON_KEY'),service:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}));
