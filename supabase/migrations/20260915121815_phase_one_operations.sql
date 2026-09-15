-- Supabase default privileges can grant TRUNCATE, which is not constrained by RLS.
-- Authentication roles must only read tables and call narrowly guarded commands.
revoke insert, update, delete, truncate, references, trigger on all tables in schema public from anon, authenticated;
alter default privileges in schema public revoke insert, update, delete, truncate, references, trigger on tables from anon, authenticated;
-- The join-code table is intentionally inaccessible through policies; only guarded commands read it.
comment on table private.join_codes is 'Private join codes: deny all direct access; settings-authorized commands only.';
