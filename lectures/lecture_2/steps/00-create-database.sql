-- ============================================================
-- Lecture 2 — Part 0: create the scratch database
-- Run this BEFORE starting the psql session you'll use for the
-- rest of the lecture. See lecture-02-notes.md, "Before you start".
-- ============================================================

-- From a terminal, connected to any existing database:
--   psql -c "CREATE DATABASE lecture02;"
-- ...or, from inside an existing psql session:
CREATE DATABASE lecture02;
-- Postgres has no "IF NOT EXISTS" for CREATE DATABASE. If you already
-- ran this earlier, it'll error with "database ... already exists" --
-- that's fine, just skip straight to \c lecture02 below.

-- Then reconnect into it:
--   psql lecture02
-- ...or, from inside psql:
\c lecture02

-- From here on, start psql from the lecture_2/ folder (the one
-- containing this steps/ folder and the data/ folder) so the
-- \copy path in 01-01-load.sql resolves correctly.

-- Don't want a separate database at all? Skip this file — psql
-- with no database name connects to whatever default database
-- already exists on your system, and every step below still works.
