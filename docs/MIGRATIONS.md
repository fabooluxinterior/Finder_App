# Database migration runbook

Every production database change follows these phases. The rules behind them
are in `CLAUDE.md`. In short: add, never delete or reset; prove nothing was lost.

## Phase 1: Inspection

- [ ] Read the migrations that created or last changed the tables you touch
      (`grep -n "<table>" supabase/migrations/*.sql`).
- [ ] List the columns, constraints, indexes, triggers and RLS policies involved.
- [ ] Find the app and edge-function code that reads or writes them
      (`grep -rn "<column>" lib supabase/functions`).
- [ ] Assume every table holds real user data.

## Phase 2: Backup and recovery

The code can't check backups. Confirm them in the Supabase dashboard before
any risky change:

- [ ] **Database → Backups**: daily backups enabled; note the latest backup time.
- [ ] Point-in-time recovery (paid add-on), if enabled: note the earliest
      restore point.
- [ ] For a high-risk change, also take an extra export:
      `supabase db dump --linked -f backup-$(date +%Y%m%d%H%M).sql` and
      `supabase db dump --linked --data-only -f data-$(date +%Y%m%d%H%M).sql`.
      Store them privately; they contain personal data.
- [ ] Write the recovery plan in the migration header.

Don't run a high-risk migration if this preparation is missing.

## Phase 3: Planning (migration header)

Create `supabase/migrations/<yyyymmddhhmmss>_<name>.sql`. Start it with this
header. `tool/check_migrations.py` fails CI without it.

```sql
-- migration-id: 20261120000000_example
-- description: What this adds and why, in one or two lines.
-- tables: public.profiles (new column), public.example (new table)
-- columns-added: profiles.example_field (text, nullable)
-- backward-compat: Additive only; existing RPCs unchanged; old app versions unaffected.
-- recovery: Additive, so no data to restore; the new column can be ignored by older code.
-- user-data: optional | none | feature:<feature> | required  (see profile_requirements)
```

End the file with its change-log row:

```sql
insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261120000000_example', 'What this adds', array['public.profiles'], array['profiles.example_field'])
on conflict (migration_id) do nothing;
```

If users must provide new information, register it in the same migration
(see "New user information" below).

## Phase 4: Safe execution

1. Run locally: `PGURL=postgres://postgres:postgres@localhost:5432/postgres bash supabase/tests/run.sh`.
   This includes the **upgrade-preservation** suite. It seeds data at the
   baseline, applies every newer migration, and fails if any row count or
   checksum changed.
2. Push to the branch. CI runs `tool/check_migrations.py` and the same suites.
3. Production:

```bash
export DATABASE_URL='postgresql://…'          # Supabase → Settings → Database (session pooler)
tool/verify_migration.sh before                # snapshot of counts + checksums
supabase db push                               # applies only new migrations, in order, each in a transaction
tool/verify_migration.sh after                 # compares with the snapshot; non-zero exit on any difference
```

**Never** run `supabase db reset` against the linked project.

Stop and investigate if the push or the comparison reports anything unexpected.
Don't "fix" it by clearing data.

## Phase 5: Verification

`tool/verify_migration.sh after` compares, per table, the row count and an md5
of the ordered primary keys and key values for:

- profiles
- profile_private
- swipes_and_requests (requests and connections)
- messages
- media_objects
- user_consents
- profile_dob
- music_accounts
- reports
- staff_roles
- subscription status (`profiles.is_premium`)

Then check by hand:

- [ ] The admin app's **Database & Data Migration** page shows the new
      migration as applied, with no errors.
- [ ] Sign in with an existing test account: profile, photos, chats and
      requests are all there.
- [ ] The new feature works, and RLS policies are in place
      (`select * from pg_policies where tablename = '<table>'`).

## Phase 6: New user information

To ask existing users for something new, without blocking their account:

```sql
alter table public.profiles add column if not exists profession_detail text;   -- nullable

insert into public.profile_requirements (key, label, description, form, level, gated_feature, introduced_by)
values ('profession_detail', 'Work details', 'Tell people a bit more about your work.', 'basics', 'optional', null,
        '20261120000000_example')
on conflict (key) do nothing;

-- Teach requirement_missing() the new key: copy the current definition from the
-- latest migration that changed it, and add one line:
--   when 'profession_detail' then coalesce(btrim(p.profession_detail), '') = ''
```

The app then:

- shows the update prompt only to users missing that field,
- opens the editor at it,
- saves only that field.

The admin app shows how many users are affected, completed or pending, and can
send a reminder.

Levels:

- `optional`: dismissible; never blocks anything.
- `feature`: blocks only `gated_feature`, through a check in that feature's RPC.
- `required`: prompt can't be dismissed. Still never locks the account;
  combine it with `feature` gating if a feature depends on it.

## Phase 7: Final report

```
Migration completed: <migration-id>
Tables modified:     …
Columns added:       …
New configuration:   … (secrets set with `supabase secrets set`, shown as Configured in admin)
Records preserved:   verify_migration.sh → all tables identical (counts + checksums)
Users needing info:  <n> (admin → Database & Data Migration)
Validation:          SQL suites ✓  app smoke test ✓
Warnings:            …
```

## Approval for destructive changes

If a change needs any statement `tool/check_migrations.py` flags, stop. Send the
owner:

- why it's needed,
- which tables and rows are affected,
- what could be lost,
- the safer alternative,
- the backup and recovery plan.

Only after written approval, add
`-- APPROVED-DESTRUCTIVE: <reason>; approved by <owner> on <date>` on the line
above the statement.
