-- The authorized planning RPC invokes these helpers under its own definer role.
-- They should not be directly callable by ordinary API roles.
revoke all on function private.next_working_start(uuid,timestamptz),
  private.finish_after_working_minutes(uuid,timestamptz,integer)
  from public,anon,authenticated;
