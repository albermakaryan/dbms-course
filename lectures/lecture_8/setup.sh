#!/usr/bin/env bash
# Lecture 8 — Part 0: create the lecture08 database and write files/.
#
#   ./setup.sh                      (from the lecture_8/ folder, or anywhere)
#
# Uses LECTURE08_DSN, the same connection string as the notebook
# (default postgresql://postgres:postgres@localhost:5432/lecture08).
# 1. psql runs steps/00-setup.sql, connected to the server's "postgres"
#    database: it DROPS and recreates lecture08 (about 45 seconds).
# 2. Python runs steps/00-make-files.py: the CSV and Parquet files in
#    files/ (about 15 seconds).
# Needs psql on your PATH. The notebook's setup button runs this script.
set -euo pipefail
cd "$(dirname "$0")"

DSN="${LECTURE08_DSN:-postgresql://postgres:postgres@localhost:5432/lecture08}"
ADMIN_DSN="${DSN%/*}/postgres"     # same server, the "postgres" database
PYTHON="${PYTHON:-python3}"

echo "== 1/2 creating lecture08 (psql steps/00-setup.sql)"
psql "$ADMIN_DSN" -X -q -v ON_ERROR_STOP=1 -f steps/00-setup.sql

echo "== 2/2 writing files/ (steps/00-make-files.py)"
LECTURE08_DSN="$DSN" "$PYTHON" steps/00-make-files.py

echo "== done"
