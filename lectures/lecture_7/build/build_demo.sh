#!/bin/bash
# Regenerate steps/01-10 and lecture-07-demo.sql from
# build/src/*.sql by running every query and pasting psql's real output
# under it. Needs a lecture07 database freshly loaded by steps/00-setup.sql
# (run psql from lecture_7/, not build/, so \copy finds data/); PGP = its
# port (user postgres, password "postgres").
# Usage (from lecture_7/build/):  PGP=5432 ./build_demo.sh
set -e
cd "$(dirname "$0")"
for f in src/[0-9][0-9]-*.sql; do python annotate.py "$f" "../steps/$(basename "$f")"; done
python annotate.py src/lab-key.sql ../steps/lab-key.sql
{ cat demo-header.sql; printf '\n\n\n'; cat ../steps/00-setup.sql; for f in ../steps/0[1-9]-*.sql ../steps/1[0-9]-*.sql; do printf '\n\n\n'; cat "$f"; done; } > ../lecture-07-demo.sql
python build_notebook.py   # checks only (--detailed rewrites lecture-07-notebook.py.bak); lecture-07-notebook.py is edited by hand
