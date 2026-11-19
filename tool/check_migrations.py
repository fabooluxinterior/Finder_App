#!/usr/bin/env python3
"""Fails if a new migration could delete or overwrite existing data.

Scans supabase/migrations/*.sql newer than BASELINE (migrations up to the
baseline were reviewed and are already applied; they're never edited).

Flagged unless the line (or one of the 3 lines above it) carries
  -- APPROVED-DESTRUCTIVE: <reason>; approved by <owner> on <date>
which may only be added after the owner's explicit approval (see CLAUDE.md):

  DROP TABLE / DROP COLUMN / DROP SCHEMA / DROP ... CASCADE / DROP TYPE
  TRUNCATE (except temp tables created in the same file)
  DELETE FROM ... without WHERE, UPDATE <table> SET ... without WHERE
  ALTER COLUMN ... TYPE, RENAME (table or column)
  ADD COLUMN ... NOT NULL without DEFAULT

Each new migration also needs the header block from docs/MIGRATIONS.md and
its own row in public.schema_change_log.

Usage: tool/check_migrations.py [files...]   (default: all new migrations)
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MIGRATIONS = ROOT / "supabase" / "migrations"
BASELINE = "20261113000001"
MARKER = re.compile(r"--\s*APPROVED-DESTRUCTIVE:\s*\S.*approved by\s+\S+", re.I)
HEADER_KEYS = ("migration-id", "description", "tables", "backward-compat", "recovery")


def blank_comments(sql: str) -> str:
    """Replaces -- comments and quoted strings with spaces (keeps offsets)."""
    out = list(sql)
    i, n = 0, len(sql)
    while i < n:
        if sql.startswith("--", i):
            j = sql.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = " "
            i = j
        elif sql[i] == "'":
            j = i + 1
            while j < n:
                if sql[j] == "'" and (j + 1 >= n or sql[j + 1] != "'"):
                    break
                j += 2 if sql[j] == "'" else 1
            for k in range(i + 1, min(j, n)):
                if out[k] != "\n":
                    out[k] = " "
            i = j + 1
        else:
            i += 1
    return "".join(out)


RULES = [
    ("DROP TABLE", re.compile(r"\bdrop\s+table\b", re.I)),
    ("DROP COLUMN", re.compile(r"\bdrop\s+column\b", re.I)),
    ("DROP SCHEMA", re.compile(r"\bdrop\s+schema\b", re.I)),
    ("DROP TYPE", re.compile(r"\bdrop\s+type\b", re.I)),
    ("DROP ... CASCADE", re.compile(r"\bdrop\s+\w+(\s+if\s+exists)?\s+[^;]*?\bcascade\b", re.I)),
    ("ALTER COLUMN TYPE", re.compile(r"\balter\s+column\s+\S+\s+(set\s+data\s+)?type\b", re.I)),
    ("RENAME", re.compile(r"\brename\s+(column\s+|constraint\s+)?\S+\s+to\b|\brename\s+to\b", re.I)),
]


def check(path: pathlib.Path) -> list[str]:
    text = path.read_text()
    lines = text.splitlines()
    code = blank_comments(text)
    problems: list[str] = []

    def line_of(offset: int) -> int:
        return text.count("\n", 0, offset) + 1

    def approved(line: int) -> bool:
        return any(MARKER.search(lines[k - 1]) for k in range(max(1, line - 3), line + 1))

    def flag(offset: int, what: str) -> None:
        ln = line_of(offset)
        if not approved(ln):
            problems.append(f"{path.name}:{ln}: {what} (destructive; needs owner approval, see CLAUDE.md)")

    for what, rx in RULES:
        for m in rx.finditer(code):
            flag(m.start(), what)

    temp_tables = {m.group(2).lower() for m in re.finditer(
        r"\bcreate\s+(temp|temporary)\s+table\s+(?:if\s+not\s+exists\s+)?([\w.]+)", code, re.I)}
    for m in re.finditer(r"\btruncate\s+(?:table\s+)?([\w.]+)", code, re.I):
        stmt_start = max(code.rfind(";", 0, m.start()), 0)
        if re.search(r"\b(grant|revoke)\b", code[stmt_start:m.start()], re.I):
            continue  # a privilege list, not a TRUNCATE statement
        if m.group(1).lower() not in temp_tables:
            flag(m.start(), f"TRUNCATE {m.group(1)}")

    # Statement-level checks (split on ';' — good enough for plain SQL and
    # for statements inside function bodies, which also end with ';').
    pos = 0
    for stmt in code.split(";"):
        start = pos
        pos += len(stmt) + 1
        s = stmt
        m = re.search(r"\bdelete\s+from\s+[\w.\"]+", s, re.I)
        if m and not re.search(r"\bwhere\b", s[m.end():], re.I):
            flag(start + m.start(), "DELETE without WHERE")
        m = re.search(r"\bupdate\s+(only\s+)?[\w.\"]+\s+(as\s+\w+\s+|\w+\s+)?set\b", s, re.I)
        if m and not re.search(r"\bwhere\b", s[m.end():], re.I):
            flag(start + m.start(), "UPDATE without WHERE")
        for m in re.finditer(r"\badd\s+column\b(.*?)(?=,\s*add\s+column\b|$)", s, re.I | re.S):
            clause = m.group(1)
            if re.search(r"\bnot\s+null\b", clause, re.I) and not re.search(r"\bdefault\b", clause, re.I):
                flag(start + m.start(), "ADD COLUMN NOT NULL without DEFAULT")

    head = "\n".join(lines[:40]).lower()
    for key in HEADER_KEYS:
        if not re.search(rf"^--\s*{key}\s*:", head, re.M):
            problems.append(f"{path.name}: missing header '-- {key}:' (see docs/MIGRATIONS.md)")
    m = re.search(r"^--\s*migration-id\s*:\s*(\S+)", head, re.M)
    if m and m.group(1) != path.stem:
        problems.append(f"{path.name}: migration-id '{m.group(1)}' doesn't match the file name")
    if not re.search(rf"schema_change_log[\s\S]*'{re.escape(path.stem)}'", text):
        problems.append(f"{path.name}: no schema_change_log row for '{path.stem}'")
    return problems


def main(argv: list[str]) -> int:
    files = [pathlib.Path(a) for a in argv] if argv else sorted(
        p for p in MIGRATIONS.glob("*.sql") if p.stem.split("_")[0] > BASELINE)
    problems = [p for f in files for p in check(f)]
    for p in problems:
        print(p)
    print(f"checked {len(files)} migration(s): {'FAILED' if problems else 'ok'}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
