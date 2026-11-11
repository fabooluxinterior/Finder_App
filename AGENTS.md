# Project rules (Vouby / Finder)

These rules apply to every change in this repository, by any developer or AI
agent, regardless of the feature being built. The same text is in `CLAUDE.md`.

## Non-negotiable: the user database is production data

**Never delete all database data or reset the database to add a feature or a
backend update.** Existing users, profiles, photos, requests/connections,
messages, subscriptions, payments, reports, consents and settings must survive
every update unchanged.

If a change genuinely needs to remove or irreversibly transform existing data,
**stop and ask the owner for explicit approval first** (see "Approval" below).
A general instruction to "implement feature X" is never permission to delete
data.

## Forbidden against production (and in migrations without approval)

- `DROP TABLE`, `DROP COLUMN`, `DROP SCHEMA`, `DROP … CASCADE`
- `TRUNCATE` (temporary tables excepted)
- `DELETE FROM` / `UPDATE` without a narrow `WHERE`
- Recreating an existing table to add columns
- `ALTER COLUMN … TYPE`, renaming tables/columns, changing user ids or auth links
- Replacing existing values with empty/default values
- `supabase db reset` or any reset/seed command against the linked project
- Overwriting or deleting existing credentials/secrets

`tool/check_migrations.py` enforces this in CI for every migration newer than
the baseline. A statement it flags may only be committed with an inline
`-- APPROVED-DESTRUCTIVE: <reason>; approved by <owner> on <date>` marker,
added **after** the owner approved it in writing.

## How to change the database

1. **Inspect first**: read the existing migrations in `supabase/migrations/`,
   the tables, columns, constraints, RLS policies and the app code that uses
   them. Never assume a table is empty.
2. **Add, don't replace**: new nullable columns or columns with safe defaults,
   new tables, new functions. Keep existing RPC signatures; add a new RPC (or a
   versioned one) when a response must change, so older app versions keep
   working.
3. **Version-controlled migrations only**: a new timestamped file in
   `supabase/migrations/`, starting with the header block from
   `docs/MIGRATIONS.md`, ending with its row in `public.schema_change_log`.
   Never edit a migration that has already been applied.
4. **Prove nothing was lost**: `supabase/tests/run.sh` runs the
   upgrade-preservation suite (seeded data, row counts and checksums before and
   after every new migration). For production, follow `docs/MIGRATIONS.md`
   (backup check → `supabase db push` → `tool/verify_migration.sh`).

## New information from existing users

Never invalidate accounts or ask users to re-enter what is already stored.
When a feature needs new user data:

- add the column (nullable),
- register it in `public.profile_requirements` and teach
  `public.requirement_missing()` how to detect it (in the same migration),
- the app shows the "Your profile needs a small update" prompt only to users
  who are actually missing it, opens the editor at that field and saves only
  that field,
- if a feature truly can't work without it, gate **only that feature**
  (`level = 'feature'`, `gated_feature`), never the whole account.

## Secrets and configuration

- Secrets live only in server-side environment variables (Supabase function
  secrets / CI secrets). Never in Flutter/web code, the APK, public tables,
  logs or API responses. Public identifiers (Supabase anon key, Spotify client
  ID) are fine in builds.
- Add new configuration alongside the old; never overwrite an existing secret
  automatically. Report missing configuration as "Not configured" in the admin
  app (`admin-config-status`), never show stored values.
- `.env.example` contains placeholders only.

## Backward compatibility

Existing sessions, profiles, chats, matches, subscriptions, payment history and
uploaded images must keep working, including from older app versions still
installed.

## Approval for high-risk changes

Before removing a column/table, deleting user data, changing identifiers or auth
relationships, overwriting credentials, or any irreversible transformation,
stop and explain to the owner:

1. why the change is required,
2. which tables and records are affected,
3. what information could be lost,
4. whether a safer alternative exists,
5. how backup and recovery would work.

Proceed only after explicit approval.

## The ten principles

1. Inspect before modifying.
2. Add instead of replacing.
3. Preserve existing records.
4. Never reset production data.
5. Never delete existing credentials without approval.
6. Keep existing users and accounts.
7. Ask users to complete genuinely missing information.
8. Preserve existing application functionality.
9. Use version-controlled migrations.
10. Verify the database after every migration.

## Other project conventions

- Security rules from earlier work still apply: no keys in Git or frontend,
  no claims of complete security or unverified E2EE, no server-side decryption
  backdoor.
- Flutter: `export PATH=/opt/flutter/bin:$PATH`; format with `dart format -l 130`.
- SQL tests: `PGURL=postgres://postgres:postgres@localhost:5432/postgres bash supabase/tests/run.sh`.
- Edge function tests: `cd supabase/functions && deno test --allow-read --allow-env _shared/tests/`.
