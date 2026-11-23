// Both Edge and the guarded local adapter use the same authoritative handler.
import { createLossEstimateHandler } from "./handler.mjs";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

Deno.serve(createLossEstimateHandler({
  url: Deno.env.get("SUPABASE_URL"),
  key: Deno.env.get("SUPABASE_ANON_KEY"),
  service: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
}));
