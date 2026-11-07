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

fresh() {
  psql "$PGURL" < tests/00_supabase_stub.sql >/dev/null 2>&1 || psql "$PGURL" < tests/00_supabase_stub.sql
  for f in migrations/*.sql; do psql "$DBURL" < "$f" >/dev/null 2>&1 || psql "$DBURL" < "$f"; done
}

for suite in tests/[1-9]*_test.sql; do
  fresh
  echo "== $suite"
  psql "$DBURL" -At < "$suite" | grep -v '^00000000-0000-0000-0000-0000000000..|' | grep -v '^$'
done
echo "All SQL security suites passed."
