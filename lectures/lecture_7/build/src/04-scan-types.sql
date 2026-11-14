-- ============================================================
-- Lecture 7 — Part 4: Scan types, and what the planner chooses
-- Run after Part 3.
--
-- Four ways to read a table: Seq Scan (all of it, in order), Index
-- Scan (index, then each row), Bitmap Heap Scan (index, collect the
-- pages, then read those pages in order), Index Only Scan (the index
-- alone). The planner picks by SELECTIVITY: what share of the table
-- the query needs -- counted in pages, not just rows.
-- ============================================================

-- Start clean (in case you ran this Part before).
DROP INDEX IF EXISTS orders_big_orderdate_idx, orders_big_status_idx;
DROP TABLE IF EXISTS orders_2025;

-- Two indexes for this Part. (Part 5 looks at what indexes cost.)
CREATE INDEX orders_big_orderdate_idx ON orders_big (orderDate);
CREATE INDEX orders_big_status_idx ON orders_big (status);

-- ---- 4.1 One day: Index Scan ----
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big WHERE orderDate = '2025-06-15';
-- =>
-- 5,180 rows of 5,000,000 (0.1%). Index Scan: find 2025-06-15 in the
-- index, then fetch each row. Look at the page count: about 70 pages
-- for 5,180 rows. orderDate has correlation 1 (Part 3.1): one day's
-- orders sit next to each other on disk, so 5,180 rows share a few
-- dozen pages.

-- ---- 4.2 Cancelled orders: Bitmap Heap Scan ----
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big WHERE status = 'cancelled';
-- =>
-- 159,902 rows (3.2%). Bitmap Index Scan collects every matching row's
-- page into a bitmap; Bitmap Heap Scan then reads those pages once
-- each, in disk order. But read "Heap Blocks: exact=55814": cancelled
-- orders are scattered, so 3% of the ROWS live on 93% of the PAGES
-- (55,814 of 59,739). The index saves almost nothing here.

-- ---- 4.3 Completed orders: Seq Scan, with an index right there ----
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big WHERE status = 'completed';
-- =>
-- 4,600,224 rows (92%). The index on status exists; the planner
-- doesn't use it. Is that a mistake? Take the Seq Scan away and see:
SET enable_seqscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big WHERE status = 'completed';
-- =>
SET enable_bitmapscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big WHERE status = 'completed';
-- =>
RESET enable_seqscan;
RESET enable_bitmapscan;
-- Forced through the index, the same query reads MORE pages (the
-- whole table plus thousands of index pages) and is no faster
-- (Bitmap) or slower (Index Scan). "The index isn't used" was the
-- right decision. When a query needs most of the table, reading the
-- whole table in order is the cheapest way. Don't teach yourself
-- "always add an index"; teach yourself "read the plan".
-- (enable_seqscan = off doesn't forbid anything; it makes the planner
-- treat a Seq Scan as hugely expensive. Use it to test, never in
-- production.)

-- ---- 4.4 Index Only Scan: the answer is in the index ----
-- count(*) for one day needs no column except orderDate -- and
-- orderDate is IN the index:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big WHERE orderDate = '2025-06-15';
-- =>
-- Index Only Scan: the table wasn't read at all. Compare the pages with
-- 4.1 (sum(orderTotal) needed the table): a handful instead of about 70.
-- "Heap Fetches: 0" -- the line to watch, next.

-- ---- 4.5 The visibility map: why Heap Fetches is not always 0 ----
-- An index doesn't know whether the row it points to is visible to
-- your transaction (it might be deleted, or not yet committed). A page
-- marked "all-visible" in the table's visibility map can be trusted
-- without reading it; any other page must be read (a Heap Fetch).
-- VACUUM sets those marks. orders_big was vacuumed in Part 0. A fresh
-- table, just built, hasn't been:
CREATE TABLE orders_2025 WITH (autovacuum_enabled = off) AS
SELECT * FROM orders_big WHERE orderDate >= '2025-01-01';
CREATE INDEX orders_2025_orderdate_idx ON orders_2025 (orderDate);
ANALYZE orders_2025;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_2025 WHERE orderDate = '2025-06-15';
-- =>
-- Still called Index Only Scan, but "Heap Fetches: 5180" -- it went to
-- the table for every row, and the page count shows it.
VACUUM orders_2025;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_2025 WHERE orderDate = '2025-06-15';
-- =>
-- After VACUUM: Heap Fetches 0, a handful of pages. Same plan name,
-- very different work. Read the numbers under the node, not just its
-- name.
DROP TABLE orders_2025;

-- Clean up: leave orders_big with its primary key only.
DROP INDEX orders_big_orderdate_idx, orders_big_status_idx;
