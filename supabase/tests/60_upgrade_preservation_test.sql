\set ON_ERROR_STOP 1
-- Runs after every migration newer than the baseline was applied on top of
-- the seeded data (see upgrade/seed.sql and run.sh). Fails if any existing row
-- disappeared or any existing value changed. New columns and new rows are
-- allowed (that's what additive migrations do).
create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;

-- Every old row must still be contained, value for value, in a current row.
create temporary table now_rows (tbl text, data jsonb);
do $$
declare t text;
begin
  for t in select distinct tbl from _upgrade.rows loop
    if to_regclass('public.' || quote_ident(t)) is null then
      raise exception 'CHECK FAILED: table public.% no longer exists', t;
    end if;
    execute format('insert into now_rows select %L, to_jsonb(x) from public.%I x', t, t);
  end loop;
end $$;

select 'lost or changed: ' || o.tbl || ' ' || left(o.data::text, 160)
  from _upgrade.rows o
 where not exists (select 1 from now_rows n where n.tbl = o.tbl and n.data @> o.data);

select pg_temp.expect(not exists (
  select 1 from _upgrade.rows o where not exists (select 1 from now_rows n where n.tbl = o.tbl and n.data @> o.data)),
  'every existing row and value survived the new migrations');
select pg_temp.expect((select count(*) from _upgrade.counts c
                        where (select count(*) from now_rows n where n.tbl = c.tbl) < c.n) = 0,
  'no table lost rows');
select pg_temp.expect((select count(*) from _upgrade.counts) >= 15, 'snapshot covered the user tables');
select pg_temp.expect((select sum(n) from _upgrade.counts where tbl in
  ('profiles','swipes_and_requests','messages','message_envelopes','user_consents','media_objects','reports')) >= 30,
  'snapshot held real user data');
