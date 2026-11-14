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
--                                                                      QUERY PLAN
-- Aggregate  (cost=171.59..171.60 rows=1 width=40) (actual time=0.861..0.862 rows=1.00 loops=1)
--   Buffers: shared read=70
--   ->  Index Scan using orders_big_orderdate_idx on orders_big  (cost=0.43..149.56 rows=4407 width=6) (actual time=0.018..0.481 rows=5180.00 loops=1)
--         Index Cond: (orderdate = '2025-06-15'::date)
--         Index Searches: 1
--         Buffers: shared read=70
-- Planning:
--   Buffers: shared hit=70 read=2
-- Planning Time: 0.176 ms
-- Execution Time: 0.892 ms
-- 5,180 rows of 5,000,000 (0.1%). Index Scan: find 2025-06-15 in the
-- index, then fetch each row. Look at the page count: about 70 pages
-- for 5,180 rows. orderDate has correlation 1 (Part 3.1): one day's
-- orders sit next to each other on disk, so 5,180 rows share a few
-- dozen pages.

-- ---- 4.2 Cancelled orders: Bitmap Heap Scan ----
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big WHERE status = 'cancelled';
--                                                                     QUERY PLAN
-- Aggregate  (cost=64423.60..64423.61 rows=1 width=40) (actual time=82.858..82.860 rows=1.00 loops=1)
--   Buffers: shared read=55953 written=611
--   ->  Bitmap Heap Scan on orders_big  (cost=1829.04..63607.73 rows=163175 width=6) (actual time=13.171..69.774 rows=159902.00 loops=1)
--         Recheck Cond: ((status)::text = 'cancelled'::text)
--         Heap Blocks: exact=55814
--         Buffers: shared read=55953 written=611
--         ->  Bitmap Index Scan on orders_big_status_idx  (cost=0.00..1788.24 rows=163175 width=0) (actual time=7.397..7.398 rows=159902.00 loops=1)
--               Index Cond: ((status)::text = 'cancelled'::text)
--               Index Searches: 1
--               Buffers: shared read=139
-- Planning:
--   Buffers: shared hit=16
-- Planning Time: 0.040 ms
-- Execution Time: 82.872 ms
-- 159,902 rows (3.2%). Bitmap Index Scan collects every matching row's
-- page into a bitmap; Bitmap Heap Scan then reads those pages once
-- each, in disk order. But read "Heap Blocks: exact=55814": cancelled
-- orders are scattered, so 3% of the ROWS live on 93% of the PAGES
-- (55,814 of 59,739). The index saves almost nothing here.

-- ---- 4.3 Completed orders: Seq Scan, with an index right there ----
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big WHERE status = 'completed';
--                                                           QUERY PLAN
-- Aggregate  (cost=145186.88..145186.89 rows=1 width=40) (actual time=615.978..615.978 rows=1.00 loops=1)
--   Buffers: shared hit=15385 read=44354
--   ->  Seq Scan on orders_big  (cost=0.00..122242.33 rows=4588911 width=6) (actual time=0.064..332.083 rows=4600224.00 loops=1)
--         Filter: ((status)::text = 'completed'::text)
--         Rows Removed by Filter: 399776
--         Buffers: shared hit=15385 read=44354
-- Planning Time: 0.050 ms
-- Execution Time: 616.001 ms
-- 4,600,224 rows (92%). The index on status exists; the planner
-- doesn't use it. Is that a mistake? Take the Seq Scan away and see:
SET enable_seqscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big WHERE status = 'completed';
--                                                                       QUERY PLAN
-- Aggregate  (cost=191409.44..191409.45 rows=1 width=40) (actual time=643.916..643.917 rows=1.00 loops=1)
--   Buffers: shared read=63674 written=1
--   ->  Bitmap Heap Scan on orders_big  (cost=51364.49..168464.88 rows=4588911 width=6) (actual time=62.422..285.050 rows=4600224.00 loops=1)
--         Recheck Cond: ((status)::text = 'completed'::text)
--         Heap Blocks: exact=59739
--         Buffers: shared read=63674 written=1
--         ->  Bitmap Index Scan on orders_big_status_idx  (cost=0.00..50217.26 rows=4588911 width=0) (actual time=55.846..55.846 rows=4600224.00 loops=1)
--               Index Cond: ((status)::text = 'completed'::text)
--               Index Searches: 1
--               Buffers: shared read=3935 written=1
-- Planning Time: 0.058 ms
-- Execution Time: 643.937 ms
SET enable_bitmapscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big WHERE status = 'completed';
--                                                                          QUERY PLAN
-- Aggregate  (cost=227281.28..227281.29 rows=1 width=40) (actual time=756.330..756.331 rows=1.00 loops=1)
--   Buffers: shared read=63674
--   ->  Index Scan using orders_big_status_idx on orders_big  (cost=0.43..204336.72 rows=4588911 width=6) (actual time=0.034..398.836 rows=4600224.00 loops=1)
--         Index Cond: ((status)::text = 'completed'::text)
--         Index Searches: 1
--         Buffers: shared read=63674
-- Planning Time: 0.051 ms
-- Execution Time: 756.348 ms
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
--                                                                        QUERY PLAN
-- Aggregate  (cost=104.57..104.58 rows=1 width=8) (actual time=0.355..0.355 rows=1.00 loops=1)
--   Buffers: shared read=8
--   ->  Index Only Scan using orders_big_orderdate_idx on orders_big  (cost=0.43..93.56 rows=4407 width=0) (actual time=0.049..0.224 rows=5180.00 loops=1)
--         Index Cond: (orderdate = '2025-06-15'::date)
--         Heap Fetches: 0
--         Index Searches: 1
--         Buffers: shared read=8
-- Planning Time: 0.047 ms
-- Execution Time: 0.367 ms
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
--                                                                         QUERY PLAN
-- Aggregate  (cost=188.79..188.80 rows=1 width=8) (actual time=0.579..0.579 rows=1.00 loops=1)
--   Buffers: shared hit=63 read=7
--   ->  Index Only Scan using orders_2025_orderdate_idx on orders_2025  (cost=0.43..175.87 rows=5168 width=0) (actual time=0.020..0.452 rows=5180.00 loops=1)
--         Index Cond: (orderdate = '2025-06-15'::date)
--         Heap Fetches: 5180
--         Index Searches: 1
--         Buffers: shared hit=63 read=7
-- Planning:
--   Buffers: shared hit=7 read=1
-- Planning Time: 0.087 ms
-- Execution Time: 0.592 ms
-- Still called Index Only Scan, but "Heap Fetches: 5180" -- it went to
-- the table for every row, and the page count shows it.
VACUUM orders_2025;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_2025 WHERE orderDate = '2025-06-15';
--                                                                         QUERY PLAN
-- Aggregate  (cost=127.79..127.80 rows=1 width=8) (actual time=0.304..0.305 rows=1.00 loops=1)
--   Buffers: shared hit=8
--   ->  Index Only Scan using orders_2025_orderdate_idx on orders_2025  (cost=0.43..114.87 rows=5168 width=0) (actual time=0.008..0.174 rows=5180.00 loops=1)
--         Index Cond: (orderdate = '2025-06-15'::date)
--         Heap Fetches: 0
--         Index Searches: 1
--         Buffers: shared hit=8
-- Planning:
--   Buffers: shared hit=4
-- Planning Time: 0.062 ms
-- Execution Time: 0.317 ms
-- After VACUUM: Heap Fetches 0, a handful of pages. Same plan name,
-- very different work. Read the numbers under the node, not just its
-- name.
DROP TABLE orders_2025;

-- Clean up: leave orders_big with its primary key only.
DROP INDEX orders_big_orderdate_idx, orders_big_status_idx;
