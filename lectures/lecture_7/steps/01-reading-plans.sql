-- ============================================================
-- Lecture 7 — Part 1: Reading a plan
-- Run after Part 0 (steps/00-setup.sql).
--
-- Every SQL statement is turned into a PLAN before it runs: which
-- tables to read, how (all of it, or through an index), in what
-- order, and how to join them. EXPLAIN shows that plan. Everything
-- in this lecture is read from plans.
-- ============================================================

-- ---- 1.1 Why 600 rows can't teach this ----
-- "All orders of customer 5" on the small orders table -- first with
-- no index, then with one:
DROP INDEX IF EXISTS orders_customerid_idx;
EXPLAIN ANALYZE
SELECT * FROM orders WHERE customerID = 5;
--                                             QUERY PLAN
-- Seq Scan on orders  (cost=0.00..15.50 rows=5 width=60) (actual time=0.009..0.027 rows=5.00 loops=1)
--   Filter: (customerid = 5)
--   Rows Removed by Filter: 595
--   Buffers: shared hit=8
-- Planning:
--   Buffers: shared hit=84 read=1 written=1
-- Planning Time: 0.157 ms
-- Execution Time: 0.061 ms
CREATE INDEX orders_customerid_idx ON orders (customerID);
EXPLAIN ANALYZE
SELECT * FROM orders WHERE customerID = 5;
--                                                           QUERY PLAN
-- Bitmap Heap Scan on orders  (cost=4.19..11.77 rows=5 width=60) (actual time=0.010..0.011 rows=5.00 loops=1)
--   Recheck Cond: (customerid = 5)
--   Heap Blocks: exact=4
--   Buffers: shared hit=4 read=1 written=1
--   ->  Bitmap Index Scan on orders_customerid_idx  (cost=0.00..4.19 rows=5 width=0) (actual time=0.007..0.008 rows=5.00 loops=1)
--         Index Cond: (customerid = 5)
--         Index Searches: 1
--         Buffers: shared read=1 written=1
-- Planning:
--   Buffers: shared hit=20 read=1 written=1
-- Planning Time: 0.067 ms
-- Execution Time: 0.019 ms
-- The second plan uses the index (Bitmap Heap Scan, which 1.4 and
-- Part 4 explain) -- and it doesn't matter: both plans finish in a
-- few hundredths of a millisecond. The whole table is 8 pages of
-- 8 kB:
SELECT pg_relation_size('orders') / 8192 AS pages,
       pg_size_pretty(pg_relation_size('orders')) AS size;
-- pages | size
--     8 | 64 kB
-- On 600 rows every plan is instant, so there is nothing to measure
-- and nothing to learn about speed.
DROP INDEX orders_customerid_idx;

-- So the rest of the lecture uses the generated tables: the same
-- columns, 5 million orders and 50,000 customers.
SELECT 'orders_big' AS t, count(*) AS rows,
       pg_size_pretty(pg_table_size('orders_big')) AS size,
       pg_relation_size('orders_big') / 8192 AS pages
FROM orders_big
UNION ALL
SELECT 'customers_big', count(*),
       pg_size_pretty(pg_table_size('customers_big')),
       pg_relation_size('customers_big') / 8192
FROM customers_big;
--       t       |  rows   |  size   | pages
-- orders_big    | 5000000 | 467 MB  | 59739
-- customers_big |   50000 | 6592 kB |   820

-- ---- 1.2 EXPLAIN: the plan, without running the query ----
-- "All orders of customer 4242" (Nane Simonyan, Yerevan).
EXPLAIN
SELECT * FROM orders_big WHERE customerID = 4242;
--                            QUERY PLAN
-- Seq Scan on orders_big  (cost=0.00..122240.04 rows=106 width=60)
--   Filter: (customerid = 4242)
-- One step (a NODE): Seq Scan on orders_big -- read every row, keep
-- the ones that pass the Filter. The numbers in brackets are the
-- planner's ESTIMATES; nothing has run yet:
--   cost=0.00..122240   cost to the first row .. cost to the last
--                       row, in the planner's own units (reading
--                       one page in sequence = 1.0), not in ms
--   rows=106            how many rows it expects this node to return
--   width=60            average size of one row, in bytes
-- (Your last digits may differ: the estimates come from a random
-- sample -- Part 3.)
-- Costs are for comparing different plans for the SAME query. They
-- are not times.

-- ---- 1.3 EXPLAIN ANALYZE: run it and measure ----
EXPLAIN ANALYZE
SELECT * FROM orders_big WHERE customerID = 4242;
--                                                    QUERY PLAN
-- Seq Scan on orders_big  (cost=0.00..122240.04 rows=106 width=60) (actual time=1.832..129.864 rows=97.00 loops=1)
--   Filter: (customerid = 4242)
--   Rows Removed by Filter: 4999903
--   Buffers: shared hit=14089 read=45650 written=7
-- Planning Time: 0.010 ms
-- Execution Time: 129.874 ms
-- Now every node also says what really happened:
--   actual time=first..last   ms until its first row .. until its last row
--   rows=97.00                rows it really returned (estimate: about 106)
--   loops=1                   how many times the node ran
-- "Rows Removed by Filter: 4999903": it read five million rows to
-- return 97. Execution Time is the whole query, in ms -- on THIS
-- machine, this time.
-- PostgreSQL 18 prints Buffers here automatically (1.4); before 18
-- you have to ask for them.

-- ---- 1.4 BUFFERS: how many pages it touched ----
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_big WHERE customerID = 4242;
--                                                    QUERY PLAN
-- Seq Scan on orders_big  (cost=0.00..122240.04 rows=106 width=60) (actual time=1.576..130.367 rows=97.00 loops=1)
--   Filter: (customerid = 4242)
--   Rows Removed by Filter: 4999903
--   Buffers: shared hit=14183 read=45556
-- Planning Time: 0.037 ms
-- Execution Time: 130.383 ms
-- Data lives in 8 kB pages. "shared hit" = pages found in PostgreSQL's
-- own memory cache (shared_buffers); "read" = pages it had to ask the
-- operating system for (from the OS file cache, or the disk). hit +
-- read = 59,739 here: every page of the table, to find 97 rows. Page
-- counts don't depend on how fast your laptop is, so they're the
-- number to compare between two plans.

-- ---- 1.5 Read a plan inside out ----
-- "Nane's orders per status, most first":
EXPLAIN ANALYZE
SELECT status, count(*) AS orders, sum(orderTotal) AS total
FROM orders_big
WHERE customerID = 4242
GROUP BY status
ORDER BY orders DESC;
--                                                             QUERY PLAN
-- Sort  (cost=122244.72..122244.73 rows=3 width=49) (actual time=132.200..132.201 rows=3.00 loops=1)
--   Sort Key: (count(*)) DESC
--   Sort Method: quicksort  Memory: 25kB
--   Buffers: shared hit=14283 read=45462
--   ->  GroupAggregate  (cost=122243.60..122244.70 rows=3 width=49) (actual time=132.173..132.185 rows=3.00 loops=1)
--         Group Key: status
--         Buffers: shared hit=14280 read=45462
--         ->  Sort  (cost=122243.60..122243.87 rows=106 width=15) (actual time=132.159..132.162 rows=97.00 loops=1)
--               Sort Key: status
--               Sort Method: quicksort  Memory: 28kB
--               Buffers: shared hit=14280 read=45462
--               ->  Seq Scan on orders_big  (cost=0.00..122240.04 rows=106 width=15) (actual time=1.661..132.125 rows=97.00 loops=1)
--                     Filter: (customerid = 4242)
--                     Rows Removed by Filter: 4999903
--                     Buffers: shared hit=14277 read=45462
-- Planning:
--   Buffers: shared hit=44 read=4
-- Planning Time: 0.119 ms
-- Execution Time: 132.223 ms
-- Read from the most indented node outwards. The Seq Scan runs first
-- and hands its 97 rows up to a Sort (by status), which hands them,
-- sorted, to the GroupAggregate (GROUP BY: 3 groups, one after the
-- other), which hands 3 rows up to the last Sort (ORDER BY orders
-- DESC). Each "->" is a node feeding the one above it. A node's actual
-- time INCLUDES the time of the nodes under it: nearly all of this
-- query's time is the scan at the bottom.

-- ---- 1.6 The hazard: EXPLAIN ANALYZE really runs the statement ----
-- On a scratch copy of the small orders table:
CREATE TEMP TABLE orders_copy AS SELECT * FROM orders;
SELECT count(*) AS rows_before FROM orders_copy;
-- rows_before
--         600
-- "Just checking the plan of a DELETE":
EXPLAIN ANALYZE
DELETE FROM orders_copy WHERE status = 'cancelled';
--                                                   QUERY PLAN
-- Delete on orders_copy  (cost=0.00..15.25 rows=0 width=0) (actual time=0.038..0.039 rows=0.00 loops=1)
--   Buffers: local hit=35
--   ->  Seq Scan on orders_copy  (cost=0.00..15.25 rows=2 width=6) (actual time=0.004..0.033 rows=27.00 loops=1)
--         Filter: ((status)::text = 'cancelled'::text)
--         Rows Removed by Filter: 573
--         Buffers: local hit=8
-- Planning Time: 0.015 ms
-- Execution Time: 0.046 ms
SELECT count(*) AS rows_after FROM orders_copy;
-- rows_after
--        573
-- WRONG: 27 rows are gone. ANALYZE means "run it": the DELETE really
-- happened. On a real table, that's a real delete. No warning.

-- FIX: run it inside a transaction and roll it back.
BEGIN;
EXPLAIN ANALYZE
DELETE FROM orders_copy WHERE status = 'returned';
--                                                   QUERY PLAN
-- Delete on orders_copy  (cost=0.00..15.25 rows=0 width=0) (actual time=0.036..0.036 rows=0.00 loops=1)
--   Buffers: local hit=52
--   ->  Seq Scan on orders_copy  (cost=0.00..15.25 rows=2 width=6) (actual time=0.004..0.029 rows=44.00 loops=1)
--         Filter: ((status)::text = 'returned'::text)
--         Rows Removed by Filter: 529
--         Buffers: local hit=8
-- Planning Time: 0.012 ms
-- Execution Time: 0.041 ms
ROLLBACK;
SELECT count(*) AS rows_after_rollback FROM orders_copy;
-- rows_after_rollback
--                 573
-- The plan and the timings are real; the 44 deleted rows came back.
-- The same goes for INSERT and UPDATE: always BEGIN ... ROLLBACK
-- around EXPLAIN ANALYZE of anything that writes. (Plain EXPLAIN,
-- without ANALYZE, never runs anything.)
DROP TABLE orders_copy;

-- ---- 1.7 Cold and warm: run it three times ----
-- A range of 10,000 orders through the primary key. Predict, then
-- run: will the three runs be the same?
EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(orderTotal) FROM orders_big WHERE orderID BETWEEN 2500001 AND 2510000;
--                                                                  QUERY PLAN
-- Aggregate  (cost=492.19..492.19 rows=1 width=32) (actual time=1.696..1.697 rows=1.00 loops=1)
--   Buffers: shared read=150
--   ->  Index Scan using orders_big_pkey on orders_big  (cost=0.43..465.43 rows=10700 width=6) (actual time=0.018..0.983 rows=10000.00 loops=1)
--         Index Cond: ((orderid >= 2500001) AND (orderid <= 2510000))
--         Index Searches: 1
--         Buffers: shared read=150
-- Planning:
--   Buffers: shared hit=10
-- Planning Time: 0.034 ms
-- Execution Time: 1.705 ms
EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(orderTotal) FROM orders_big WHERE orderID BETWEEN 2500001 AND 2510000;
--                                                                  QUERY PLAN
-- Aggregate  (cost=492.19..492.19 rows=1 width=32) (actual time=1.293..1.294 rows=1.00 loops=1)
--   Buffers: shared hit=150
--   ->  Index Scan using orders_big_pkey on orders_big  (cost=0.43..465.43 rows=10700 width=6) (actual time=0.006..0.602 rows=10000.00 loops=1)
--         Index Cond: ((orderid >= 2500001) AND (orderid <= 2510000))
--         Index Searches: 1
--         Buffers: shared hit=150
-- Planning Time: 0.038 ms
-- Execution Time: 1.303 ms
EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(orderTotal) FROM orders_big WHERE orderID BETWEEN 2500001 AND 2510000;
--                                                                  QUERY PLAN
-- Aggregate  (cost=492.19..492.19 rows=1 width=32) (actual time=1.296..1.296 rows=1.00 loops=1)
--   Buffers: shared hit=150
--   ->  Index Scan using orders_big_pkey on orders_big  (cost=0.43..465.43 rows=10700 width=6) (actual time=0.004..0.593 rows=10000.00 loops=1)
--         Index Cond: ((orderid >= 2500001) AND (orderid <= 2510000))
--         Index Searches: 1
--         Buffers: shared hit=150
-- Planning Time: 0.013 ms
-- Execution Time: 1.301 ms
-- Same plan, same 10,000 rows, same number of pages. On a fresh
-- database the FIRST run has "read=" (the pages weren't in
-- PostgreSQL's cache yet) and is slower; runs 2 and 3 have only
-- "hit=". If you ran this before, all three are warm. That's why one
-- timing proves nothing: run three times, and compare plan shape and
-- page counts before milliseconds.

-- The big Seq Scan, three times:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big WHERE customerID = 4242;
--                                                      QUERY PLAN
-- Aggregate  (cost=122240.30..122240.31 rows=1 width=8) (actual time=128.797..128.798 rows=1.00 loops=1)
--   Buffers: shared hit=14488 read=45251 written=14
--   ->  Seq Scan on orders_big  (cost=0.00..122240.04 rows=106 width=0) (actual time=1.852..128.785 rows=97.00 loops=1)
--         Filter: (customerid = 4242)
--         Rows Removed by Filter: 4999903
--         Buffers: shared hit=14488 read=45251 written=14
-- Planning Time: 0.022 ms
-- Execution Time: 128.809 ms
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big WHERE customerID = 4242;
--                                                      QUERY PLAN
-- Aggregate  (cost=122240.30..122240.31 rows=1 width=8) (actual time=132.561..132.562 rows=1.00 loops=1)
--   Buffers: shared hit=14576 read=45163 written=22
--   ->  Seq Scan on orders_big  (cost=0.00..122240.04 rows=106 width=0) (actual time=1.947..132.548 rows=97.00 loops=1)
--         Filter: (customerid = 4242)
--         Rows Removed by Filter: 4999903
--         Buffers: shared hit=14576 read=45163 written=22
-- Planning Time: 0.038 ms
-- Execution Time: 132.577 ms
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big WHERE customerID = 4242;
--                                                      QUERY PLAN
-- Aggregate  (cost=122240.30..122240.31 rows=1 width=8) (actual time=130.321..130.322 rows=1.00 loops=1)
--   Buffers: shared hit=14670 read=45069 written=78
--   ->  Seq Scan on orders_big  (cost=0.00..122240.04 rows=106 width=0) (actual time=2.231..130.306 rows=97.00 loops=1)
--         Filter: (customerid = 4242)
--         Rows Removed by Filter: 4999903
--         Buffers: shared hit=14670 read=45069 written=78
-- Planning Time: 0.040 ms
-- Execution Time: 130.337 ms
-- Surprise: it never gets warm. Every run has tens of thousands of
-- "read" pages. A table bigger than a quarter of shared_buffers
-- (128 MB by default) is scanned through a small ring of buffers, so
-- that one big scan can't push everything else out of the cache. The
-- pages come from the operating system's file cache instead, which
-- is why it's still fast. Your hit/read split will differ from the
-- notes; the total (59,739 pages) won't.
