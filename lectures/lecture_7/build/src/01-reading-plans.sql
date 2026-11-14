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
-- =>
CREATE INDEX orders_customerid_idx ON orders (customerID);
EXPLAIN ANALYZE
SELECT * FROM orders WHERE customerID = 5;
-- =>
-- The second plan uses the index (Bitmap Heap Scan, which 1.4 and
-- Part 4 explain) -- and it doesn't matter: both plans finish in a
-- few hundredths of a millisecond. The whole table is 8 pages of
-- 8 kB:
SELECT pg_relation_size('orders') / 8192 AS pages,
       pg_size_pretty(pg_relation_size('orders')) AS size;
-- =>
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
-- =>

-- ---- 1.2 EXPLAIN: the plan, without running the query ----
-- "All orders of customer 4242" (Nane Simonyan, Yerevan).
EXPLAIN
SELECT * FROM orders_big WHERE customerID = 4242;
-- =>
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
-- =>
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
-- =>
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
-- =>
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
-- =>
-- "Just checking the plan of a DELETE":
EXPLAIN ANALYZE
DELETE FROM orders_copy WHERE status = 'cancelled';
-- =>
SELECT count(*) AS rows_after FROM orders_copy;
-- =>
-- WRONG: 27 rows are gone. ANALYZE means "run it": the DELETE really
-- happened. On a real table, that's a real delete. No warning.

-- FIX: run it inside a transaction and roll it back.
BEGIN;
EXPLAIN ANALYZE
DELETE FROM orders_copy WHERE status = 'returned';
-- =>
ROLLBACK;
SELECT count(*) AS rows_after_rollback FROM orders_copy;
-- =>
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
-- =>
EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(orderTotal) FROM orders_big WHERE orderID BETWEEN 2500001 AND 2510000;
-- =>
EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(orderTotal) FROM orders_big WHERE orderID BETWEEN 2500001 AND 2510000;
-- =>
-- Same plan, same 10,000 rows, same number of pages. On a fresh
-- database the FIRST run has "read=" (the pages weren't in
-- PostgreSQL's cache yet) and is slower; runs 2 and 3 have only
-- "hit=". If you ran this before, all three are warm. That's why one
-- timing proves nothing: run three times, and compare plan shape and
-- page counts before milliseconds.

-- The big Seq Scan, three times:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big WHERE customerID = 4242;
-- =>
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big WHERE customerID = 4242;
-- =>
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big WHERE customerID = 4242;
-- =>
-- Surprise: it never gets warm. Every run has tens of thousands of
-- "read" pages. A table bigger than a quarter of shared_buffers
-- (128 MB by default) is scanned through a small ring of buffers, so
-- that one big scan can't push everything else out of the cache. The
-- pages come from the operating system's file cache instead, which
-- is why it's still fast. Your hit/read split will differ from the
-- notes; the total (59,739 pages) won't.
