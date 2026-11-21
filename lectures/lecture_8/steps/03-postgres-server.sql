-- ============================================================
-- Lecture 8 — Part 3, first half: PostgreSQL is a server
-- psql, connected to lecture08 (psql lecture08). Before 3.3, open a
-- SECOND terminal and connect there too, so the server has two clients.
-- pg_ls_dir and pg_stat_file need a superuser (the Docker setup's
-- postgres user is one).
-- ============================================================

-- ---- 3.1 Where the server keeps its data ----
-- One folder on the server's disk, the "data directory":
SHOW data_directory;
--         data_directory
-- /var/lib/postgresql/18/docker
SELECT name FROM pg_ls_dir('.') AS name ORDER BY name;
--         name
-- base
-- global
-- pg_commit_ts
-- pg_dynshmem
-- pg_hba.conf
-- pg_ident.conf
-- pg_logical
-- pg_multixact
-- pg_notify
-- pg_replslot
-- pg_serial
-- pg_snapshots
-- pg_stat
-- pg_stat_tmp
-- pg_subtrans
-- pg_tblspc
-- pg_twophase
-- PG_VERSION
-- pg_wal
-- pg_xact
-- postgresql.auto.conf
-- postgresql.conf
-- postmaster.opts
-- postmaster.pid
-- base: one folder per database; global: tables shared by all
-- databases (the list of databases itself); pg_wal: the write-ahead
-- log, every change is logged here before the table files change,
-- so after a crash the server can recover;
-- postgresql.conf: the settings; pg_hba.conf: who may connect from
-- where. You never open these files: only the server does.

-- ---- 3.2 One database, hundreds of files ----
SELECT count(*) AS files,
       pg_size_pretty(sum((pg_stat_file(d.dir || '/' || f)).size)) AS size
FROM (SELECT 'base/' || oid AS dir FROM pg_database WHERE datname = current_database()) AS d,
     pg_ls_dir(d.dir) AS f;
-- files |  size
--   337 | 582 MB
-- lecture08 alone: 337 files. Every table and every index is its own
-- file, plus PostgreSQL's own catalog tables:
SELECT pg_relation_filepath('orders_big')      AS table_file,
       pg_relation_filepath('orders_big_pkey') AS index_file;
--    table_file    |    index_file
-- base/16384/16502 | base/16384/16518
-- (Numbers, not names: yours will differ. Lecture 7, Part 2 opened
-- the first one.) To copy a database you
-- ask the server to export it (pg_dump); you don't copy its files.

-- ---- 3.3 One process per connection ----
-- Every connected client gets its own server process. The server
-- also runs its own background processes:
SELECT pid, backend_type, application_name
FROM pg_stat_activity
ORDER BY backend_type, pid;
-- pid |         backend_type         | application_name
--  75 | autovacuum launcher          |
--  72 | background writer            |
--  71 | checkpointer                 |
--  95 | client backend               | psql
--  96 | client backend               | psql
--  68 | io worker                    |
--  69 | io worker                    |
--  70 | io worker                    |
--  76 | logical replication launcher |
--  74 | walwriter                    |
-- Two "client backend" rows: your two psql terminals, each served by
-- its own process (pid). The other eight are the server's own
-- background processes (writing the log, saving changed pages,
-- starting autovacuum, ...): they run whether anyone is connected or not.
