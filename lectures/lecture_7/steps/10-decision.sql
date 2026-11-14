-- ============================================================
-- Lecture 7 — Part 10: The decision rule
-- Run after Part 9.
--
-- Index, partition, or neither? The rule itself is in the notes
-- (Part 10.1). One check belongs here, because it's the silent failure
-- nobody looks for: an index that exists, takes space, slows every
-- write -- and is never used.
-- ============================================================

-- Start clean (in case you ran this Part before).
DROP INDEX IF EXISTS orders_big_orderdate_idx;

-- ---- 10.2 The index nobody uses ----
-- Someone adds an index "for the monthly report":
CREATE INDEX orders_big_orderdate_idx ON orders_big (orderDate);
ANALYZE orders_big;
-- The report, as the reporting tool writes it -- for two months:
SELECT count(*) AS orders, sum(orderTotal) AS revenue
FROM orders_big WHERE date_trunc('month', orderDate) = '2025-11-01';
-- orders |   revenue
-- 159799 | 102460853.62
SELECT count(*) AS orders, sum(orderTotal) AS revenue
FROM orders_big WHERE date_trunc('month', orderDate) = '2025-12-01';
-- orders |   revenue
-- 165962 | 106307167.25
-- Part 7.1's trap: a function on the column, so a Seq Scan, every
-- month. The index is never touched -- and nothing tells you.

-- PostgreSQL counts every use of every index, in pg_stat_user_indexes.
-- (A statement's counts reach the view up to a second after it ends;
-- the pause makes sure they're in.)
SELECT pg_sleep(1.5);
SELECT indexrelname AS index, idx_scan AS times_used,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE indexrelname = 'orders_big_orderdate_idx';
--          index           | times_used | size
-- orders_big_orderdate_idx |          0 | 34 MB
-- Used 0 times, 34 MB, and every INSERT pays for it (Part 5.4).

-- Fix the report (Part 7.1, FIX 1) and look again:
SELECT count(*) AS orders, sum(orderTotal) AS revenue
FROM orders_big WHERE orderDate >= '2025-12-01' AND orderDate < '2026-01-01';
-- orders |   revenue
-- 165962 | 106307167.25
SELECT pg_sleep(1.5);
SELECT indexrelname AS index, idx_scan AS times_used,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE indexrelname = 'orders_big_orderdate_idx';
--          index           | times_used | size
-- orders_big_orderdate_idx |          2 | 34 MB
-- Same December numbers, and now the index is used. On a real
-- database, look at this view after a few weeks of normal traffic. An
-- index still at 0 means either the queries can't use it (fix them) or
-- nobody needs it (drop it) -- but never drop the index behind a
-- PRIMARY KEY or UNIQUE constraint: it enforces a rule even if no
-- query reads it. The counts start from the last statistics reset
-- (pg_stat_reset), not from the beginning of time.
SELECT indexrelname AS index, idx_scan AS times_used,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE relname IN ('orders_big', 'customers_big')
ORDER BY indexrelname;
--          index           | times_used |  size
-- customers_big_email_key  |          1 | 3224 kB
-- customers_big_pkey       |     200039 | 1112 kB
-- orders_big_orderdate_idx |          2 | 34 MB
-- orders_big_pkey          |         11 | 111 MB
-- (All indexes on the two big tables. The primary keys' counts depend
-- on everything you ran before, so yours will differ.)
DROP INDEX orders_big_orderdate_idx;
