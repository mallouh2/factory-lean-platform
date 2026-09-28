-- The public RPC is executable by authenticated users, but its private helper
-- is intentionally not. Run the narrow wrapper as its owner so it can invoke
-- that helper; the helper still checks the caller's orders:create grant and
-- factory membership before writing either request or product item rows.
alter function public.create_production_request(
  uuid, text, text, timestamptz, text, jsonb
) security definer;

-- Keep name resolution fixed for the owner-privileged wrapper. Its body uses
-- the schema-qualified private.create_production_request reference.
alter function public.create_production_request(
  uuid, text, text, timestamptz, text, jsonb
) set search_path = '';
