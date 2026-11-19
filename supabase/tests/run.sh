#!/usr/bin/env bash
# Runs the migrations against a scratch Postgres with Supabase's auth/storage
# schemas stubbed, then the attack-scenario suites. Every "expect_fail" case
# raises if the action is NOT blocked, so any regression fails the run.
#   PGURL=postgres://postgres:postgres@localhost:5432/postgres supabase/tests/run.sh
set -euo pipefail
cd "$(dirname "$0")/.."
PGURL="${PGURL:-postgres://postgres:postgres@localhost:5432/postgres}"
DBURL="${PGURL%/*}/finder"
psql() { command psql -X -q -v ON_ERROR_STOP=1 "$@"; }

# Migrations up to BASELINE were reviewed and applied before the data-
# preservation rules; the upgrade suite seeds data there and replays the rest.
BASELINE=20261113000001

apply() { psql "$DBURL" < "$1" >/dev/null 2>&1 || psql "$DBURL" < "$1"; }

fresh() {
  psql "$PGURL" < tests/00_supabase_stub.sql >/dev/null 2>&1 || psql "$PGURL" < tests/00_supabase_stub.sql
  for f in migrations/*.sql; do apply "$f"; done
}

# Baseline schema + seeded data + snapshot, then every newer migration.
upgrade() {
  psql "$PGURL" < tests/00_supabase_stub.sql >/dev/null 2>&1 || psql "$PGURL" < tests/00_supabase_stub.sql
  for f in migrations/*.sql; do
    v=$(basename "$f"); v=${v%%_*}
    [[ "$v" > "$BASELINE" ]] || apply "$f"
  done
  psql "$DBURL" -At < tests/upgrade/seed.sql
  for f in migrations/*.sql; do
    v=$(basename "$f"); v=${v%%_*}
    if [[ "$v" > "$BASELINE" ]]; then echo "   applying $(basename "$f") on seeded data"; apply "$f"; fi
  done
}

for suite in tests/[1-9]*_test.sql; do
  if [[ "$suite" == *upgrade* ]]; then upgrade; else fresh; fi
  echo "== $suite"
  psql "$DBURL" -At < "$suite" | grep -v '^00000000-0000-0000-0000-0000000000..|' | grep -v '^$'
done
echo "All SQL security suites passed."
