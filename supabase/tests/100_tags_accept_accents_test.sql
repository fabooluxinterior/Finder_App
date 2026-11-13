\set ON_ERROR_STOP 1
create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;

select pg_temp.expect(public.valid_tag_list(array['Cafés', 'Chess', 'Food & drink'], 30), 'accented letters are accepted');
select pg_temp.expect(public.valid_tag_list(array['Malayalam', 'English'], 24), 'plain tags still pass');
select pg_temp.expect(not public.valid_tag_list(array['call 9876543210'], 30), 'digits are still refused');
select pg_temp.expect(not public.valid_tag_list(array['@handle'], 30), 'handles are still refused');
select pg_temp.expect(not public.valid_tag_list(array['x'], 30), 'too short is still refused');
select pg_temp.expect(not public.valid_tag_list(array['Chess', 'chess'], 30), 'duplicates are still refused');
select pg_temp.expect(not public.valid_tag_list(array['a.b.com'], 30), 'links are still refused');
