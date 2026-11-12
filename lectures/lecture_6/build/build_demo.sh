#!/bin/bash
# Regenerate steps/01-08 and lecture-06-demo.sql from build/src/*.sql by
# running every query and pasting psql's real output under it, then
# rebuild the notebook. Needs a lecture06 database loaded by
# steps/00-setup.sql (run psql from lecture_6/, not build/, so \copy finds
# data/); PGP = its port (password "postgres", user postgres).
# Usage (from lecture_6/build/):  PGP=5432 ./build_demo.sh
set -e
cd "$(dirname "$0")"
for f in src/0*.sql; do python annotate.py "$f" "../steps/$(basename "$f")"; done
{ cat demo-header.sql; for f in ../steps/0*.sql; do printf '\n\n\n'; cat "$f"; done; } > ../lecture-06-demo.sql
python build_notebook.py
