#!/usr/bin/env bash
# Before/after check for a production migration (see docs/MIGRATIONS.md).
#
#   export DATABASE_URL='postgresql://…'   # Supabase → Settings → Database
#   tool/verify_migration.sh before         # saves counts + checksums
#   supabase db push
#   tool/verify_migration.sh after          # compares; exit 1 on any difference
#
# For every public table it records the row count and an md5 over the rows,
# restricted to the columns that existed *before* (new columns are expected
# and ignored). Read-only: it never writes to the database.
# The snapshot holds no personal data (counts, column names, hashes only).
# Run it in a quiet window: users editing profiles during the push also change
# checksums, so investigate any difference before assuming data loss.
set -euo pipefail
: "${DATABASE_URL:?set DATABASE_URL to the database connection string}"
mode="${1:-}"
dir="${SNAPSHOT_DIR:-.migration-snapshot}"
mkdir -p "$dir"
# Read-only session: this script can't modify the database.
q() { PGOPTIONS='-c default_transaction_read_only=on' psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -At -F $'\t' -c "$1"; }

measure() { # table, comma-separated columns -> "count<TAB>md5"
  local t="$1" cols="$2" sel
  sel=$(echo "$cols" | sed 's/[^,][^,]*/"&"/g')
  q "select count(*), md5(coalesce(string_agg(r::text, chr(10) order by r::text), ''))
       from (select $sel from public.\"$t\") r"
}

case "$mode" in
  before)
    : > "$dir/before.tsv"
    while IFS=$'\t' read -r t cols; do
      printf '%s\t%s\t%s\n' "$t" "$cols" "$(measure "$t" "$cols")" >> "$dir/before.tsv"
    done < <(q "select table_name, string_agg(column_name, ',' order by ordinal_position)
                  from information_schema.columns where table_schema = 'public'
                   and table_name in (select tablename from pg_tables where schemaname = 'public')
                 group by table_name order by table_name")
    echo "Saved $(wc -l < "$dir/before.tsv") tables to $dir/before.tsv"
    ;;
  after)
    [[ -f "$dir/before.tsv" ]] || { echo "Run '$0 before' first." >&2; exit 2; }
    fail=0
    while IFS=$'\t' read -r t cols n0 h0; do
      if [[ -z "$(q "select to_regclass('public.\"$t\"')")" ]]; then
        echo "MISSING TABLE  $t (had $n0 rows)"; fail=1; continue
      fi
      if ! res=$(measure "$t" "$cols" 2>/dev/null); then
        echo "COLUMN REMOVED $t (columns before: $cols)"; fail=1; continue
      fi
      n1=${res%%$'\t'*}; h1=${res##*$'\t'}
      if [[ "$n1" -lt "$n0" ]]; then echo "ROWS LOST      $t: $n0 -> $n1"; fail=1
      elif [[ "$n1" -eq "$n0" && "$h1" != "$h0" ]]; then echo "VALUES CHANGED $t ($n0 rows)"; fail=1
      elif [[ "$n1" -gt "$n0" ]]; then echo "ok (+$((n1 - n0)) new rows) $t"
      else echo "ok             $t ($n0 rows)"; fi
    done < "$dir/before.tsv"
    if [[ $fail -eq 0 ]]; then echo "All existing data preserved."; else echo "Differences found — investigate before continuing." >&2; fi
    exit $fail
    ;;
  *) echo "usage: $0 before|after" >&2; exit 2 ;;
esac
