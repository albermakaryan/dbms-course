-- ============================================================
-- Lecture 7 — Part 7: Traps -- the index exists but is not used
-- Run after Part 6.
--
-- Each trap returns the right rows, slowly, with a perfectly good
-- index sitting next to it. The plan is the only place it shows.
-- One reading skill for this whole Part: an index condition the index
-- can SEARCH appears as "Index Cond:". A condition checked row by row
-- appears as "Filter:" -- even when the node's name says "Index".
-- ============================================================

-- Start clean (in case you ran this Part before).
DROP INDEX IF EXISTS orders_big_orderdate_idx, orders_big_customerid_idx,
                     orders_big_month_idx, orders_big_deliverydate_idx,
                     customers_big_email_pattern_idx;
DROP TABLE IF EXISTS r_or_seq, r_or_index, r_union_all;
CREATE INDEX orders_big_orderdate_idx ON orders_big (orderDate);
CREATE INDEX orders_big_customerid_idx ON orders_big (customerID);

-- ---- 7.1 A function on the indexed column ----
-- "Revenue in June 2025", written the way people say it:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE date_trunc('month', orderDate) = '2025-06-01';
--                                                               QUERY PLAN
-- Aggregate  (cost=147368.66..147368.67 rows=1 width=40) (actual time=555.922..555.923 rows=1.00 loops=1)
--   Buffers: shared hit=5540 read=54199
--   ->  Seq Scan on orders_big  (cost=0.00..147243.66 rows=25001 width=6) (actual time=418.942..543.696 rows=155419.00 loops=1)
--         Filter: (date_trunc('month'::text, (orderdate)::timestamp with time zone) = '2025-06-01 00:00:00+00'::timestamp with time zone)
--         Rows Removed by Filter: 4844581
--         Buffers: shared hit=5540 read=54199
-- Planning:
--   Buffers: shared hit=62 read=2
-- Planning Time: 0.145 ms
-- Execution Time: 555.952 ms
-- WRONG PLAN: Seq Scan, the orderDate index unused. The index is
-- sorted by orderDate; it knows nothing about date_trunc(orderDate).
-- Note the estimate too: the planner has no statistics on the
-- expression, so it guesses a fixed share (0.5%) of the table --
-- 25,000 against 155,419 real rows.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE extract(year FROM orderDate) = 2025 AND extract(month FROM orderDate) = 6;
--                                                         QUERY PLAN
-- Aggregate  (cost=159744.95..159744.96 rows=1 width=40) (actual time=562.900..562.901 rows=1.00 loops=1)
--   Buffers: shared hit=5634 read=54105
--   ->  Seq Scan on orders_big  (cost=0.00..159744.32 rows=125 width=6) (actual time=378.828..550.393 rows=155419.00 loops=1)
--         Filter: ((EXTRACT(year FROM orderdate) = '2025'::numeric) AND (EXTRACT(month FROM orderdate) = '6'::numeric))
--         Rows Removed by Filter: 4844581
--         Buffers: shared hit=5634 read=54105
-- Planning:
--   Buffers: shared hit=6
-- Planning Time: 0.051 ms
-- Execution Time: 562.914 ms
-- Same problem, and a worse guess (0.5% of 0.5%: about 125 rows).

-- FIX 1: say it as a range on the column itself.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE orderDate >= '2025-06-01' AND orderDate < '2025-07-01';
--                                                                         QUERY PLAN
-- Aggregate  (cost=6208.16..6208.17 rows=1 width=40) (actual time=25.514..25.514 rows=1.00 loops=1)
--   Buffers: shared hit=2 read=1993
--   ->  Index Scan using orders_big_orderdate_idx on orders_big  (cost=0.43..5440.01 rows=153629 width=6) (actual time=0.026..13.713 rows=155419.00 loops=1)
--         Index Cond: ((orderdate >= '2025-06-01'::date) AND (orderdate < '2025-07-01'::date))
--         Index Searches: 1
--         Buffers: shared hit=2 read=1993
-- Planning:
--   Buffers: shared hit=49
-- Planning Time: 0.126 ms
-- Execution Time: 25.530 ms
-- Index Scan, estimate close to the 155,419 real rows, and the same
-- answer. Use ">= first day AND < first day of NEXT month": it is
-- right for dates and for timestamps (BETWEEN ... '2025-06-30' would
-- lose June 30 after midnight on a timestamp column).

-- FIX 2: index the expression (Part 6.4). Error on purpose:
CREATE INDEX orders_big_month_idx ON orders_big (date_trunc('month', orderDate));
-- ERROR:  functions in index expression must be marked IMMUTABLE
-- An index may only use IMMUTABLE functions: same input, same output,
-- forever. date_trunc on a date first turns it into a timestamp WITH
-- time zone (look at the Filter in the first plan above), and that
-- result depends on the session's time zone setting. Cast to a plain
-- timestamp, and it's immutable:
CREATE INDEX orders_big_month_idx ON orders_big (date_trunc('month', orderDate::timestamp));
ANALYZE orders_big;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE date_trunc('month', orderDate::timestamp) = '2025-06-01';
--                                                                      QUERY PLAN
-- Aggregate  (cost=5811.12..5811.13 rows=1 width=40) (actual time=20.550..20.551 rows=1.00 loops=1)
--   Buffers: shared hit=1858 read=133
--   ->  Index Scan using orders_big_month_idx on orders_big  (cost=0.43..5043.63 rows=153497 width=6) (actual time=0.014..9.153 rows=155419.00 loops=1)
--         Index Cond: (date_trunc('month'::text, (orderdate)::timestamp without time zone) = '2025-06-01 00:00:00'::timestamp without time zone)
--         Index Searches: 1
--         Buffers: shared hit=1858 read=133
-- Planning:
--   Buffers: shared hit=44 read=1
-- Planning Time: 0.126 ms
-- Execution Time: 20.565 ms
-- Works -- for queries written with exactly this expression. FIX 1
-- needs no new index and works for any range; prefer it.
DROP INDEX orders_big_month_idx;

-- ---- 7.2 A type mismatch ----
-- The app passes the customer number as a decimal:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big WHERE customerID = 4242.0;
--                                                                           QUERY PLAN
-- Aggregate  (cost=117501.11..117501.12 rows=1 width=8) (actual time=303.448..303.449 rows=1.00 loops=1)
--   Buffers: shared hit=96000 read=4344
--   ->  Index Only Scan using orders_big_customerid_idx on orders_big  (cost=0.43..117438.61 rows=25000 width=0) (actual time=23.881..303.441 rows=97.00 loops=1)
--         Filter: ((customerid)::numeric = 4242.0)
--         Rows Removed by Filter: 4999903
--         Heap Fetches: 0
--         Index Searches: 1
--         Buffers: shared hit=96000 read=4344
-- Planning:
--   Buffers: shared hit=8
-- Planning Time: 0.040 ms
-- Execution Time: 303.459 ms
-- WRONG PLAN. The node is "Index Only Scan using
-- orders_big_customerid_idx" -- but there is no Index Cond, only a
-- Filter: (customerid)::numeric = 4242.0. To compare an integer with
-- a numeric, PostgreSQL converts the COLUMN, every row of it, and the
-- index on the integer can't be searched. It reads all 5 million
-- index entries (Rows Removed by Filter) to find 97.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big WHERE customerID = '4242';
--                                                                      QUERY PLAN
-- Aggregate  (cost=6.53..6.54 rows=1 width=8) (actual time=0.025..0.026 rows=1.00 loops=1)
--   Buffers: shared hit=4 read=1
--   ->  Index Only Scan using orders_big_customerid_idx on orders_big  (cost=0.43..6.27 rows=105 width=0) (actual time=0.014..0.021 rows=97.00 loops=1)
--         Index Cond: (customerid = 4242)
--         Heap Fetches: 0
--         Index Searches: 1
--         Buffers: shared hit=4 read=1
-- Planning:
--   Buffers: shared hit=5
-- Planning Time: 0.056 ms
-- Execution Time: 0.035 ms
-- A quoted literal is fine: '4242' has no type yet, so it becomes an
-- integer, and the Index Cond is back.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big WHERE customerID::text = '4242';
--                                                                           QUERY PLAN
-- Aggregate  (cost=130000.88..130000.89 rows=1 width=8) (actual time=257.492..257.493 rows=1.00 loops=1)
--   Buffers: shared hit=100344
--   ->  Index Only Scan using orders_big_customerid_idx on orders_big  (cost=0.43..129938.38 rows=25000 width=0) (actual time=24.053..257.484 rows=97.00 loops=1)
--         Filter: ((customerid)::text = '4242'::text)
--         Rows Removed by Filter: 4999903
--         Heap Fetches: 0
--         Index Searches: 1
--         Buffers: shared hit=100344
-- Planning:
--   Buffers: shared hit=14
-- Planning Time: 0.037 ms
-- Execution Time: 257.504 ms
-- WRONG PLAN again: a cast on the column is a function on the column
-- (7.1). FIX: make the VALUE the column's type -- 4242, or
-- CAST(:param AS int) -- never cast the column.

-- ---- 7.3 LIKE: 'text%' and '%text' ----
-- A search box: the user has typed the start of an email address.
EXPLAIN (ANALYZE, BUFFERS)
SELECT customerID, email FROM customers_big WHERE email LIKE 'nane.simonyan4242%';
--                                                  QUERY PLAN
-- Seq Scan on customers_big  (cost=0.00..1445.00 rows=5 width=34) (actual time=0.216..2.185 rows=1.00 loops=1)
--   Filter: ((email)::text ~~ 'nane.simonyan4242%'::text)
--   Rows Removed by Filter: 49999
--   Buffers: shared hit=820
-- Planning:
--   Buffers: shared hit=34 read=6
-- Planning Time: 0.126 ms
-- Execution Time: 2.192 ms
-- Seq Scan, although email has a UNIQUE index. The database sorts text
-- by language rules (its collation): your database's is shown by the
-- next query. Under those rules the index's order can't be used for
-- LIKE.
SELECT datcollate FROM pg_database WHERE datname = current_database();
-- datcollate
-- en_US.utf8
-- FIX: an index built with the "pattern" operator class, which sorts
-- character by character. (If your datcollate is C, the plain index
-- already works and you'll see an Index Scan above.)
CREATE INDEX customers_big_email_pattern_idx ON customers_big (email varchar_pattern_ops);
EXPLAIN (ANALYZE, BUFFERS)
SELECT customerID, email FROM customers_big WHERE email LIKE 'nane.simonyan4242%';
--                                                                    QUERY PLAN
-- Index Scan using customers_big_email_pattern_idx on customers_big  (cost=0.41..8.44 rows=5 width=34) (actual time=0.015..0.015 rows=1.00 loops=1)
--   Index Cond: (((email)::text ~>=~ 'nane.simonyan4242'::text) AND ((email)::text ~<~ 'nane.simonyan4243'::text))
--   Filter: ((email)::text ~~ 'nane.simonyan4242%'::text)
--   Index Searches: 1
--   Buffers: shared hit=1 read=3
-- Planning:
--   Buffers: shared hit=59 read=1
-- Planning Time: 0.139 ms
-- Execution Time: 0.024 ms
-- Index Cond: email >= 'nane.simonyan4242' AND email < 'nane.simonyan4243'
-- -- a prefix is a range of the sorted index.
-- The other end of the string:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM customers_big WHERE email LIKE '%@yahoo.com';
--                                                        QUERY PLAN
-- Aggregate  (cost=1472.78..1472.79 rows=1 width=8) (actual time=4.231..4.231 rows=1.00 loops=1)
--   Buffers: shared hit=820
--   ->  Seq Scan on customers_big  (cost=0.00..1445.00 rows=11111 width=0) (actual time=0.004..3.929 rows=12576.00 loops=1)
--         Filter: ((email)::text ~~ '%@yahoo.com'::text)
--         Rows Removed by Filter: 37424
--         Buffers: shared hit=820
-- Planning Time: 0.026 ms
-- Execution Time: 4.238 ms
-- Seq Scan, with any B-tree. A leading wildcard has no place to start
-- in a sorted list, like looking up every surname ending in "-yan" in
-- a phone book. (Searches inside text need a different index type --
-- the pg_trgm extension, beyond this lecture.)
DROP INDEX customers_big_email_pattern_idx;

-- ---- 7.4 OR across different columns ----
-- Customer service: "Nane's orders, or anything delivered on 14
-- December 2025" (the day her last order arrived).
EXPLAIN (ANALYZE, BUFFERS)
SELECT orderID, customerID, deliveryDate FROM orders_big
WHERE customerID = 4242 OR deliveryDate = '2025-12-14';
--                                                     QUERY PLAN
-- Seq Scan on orders_big  (cost=0.00..134737.64 rows=1458 width=12) (actual time=2.898..220.200 rows=1749.00 loops=1)
--   Filter: ((customerid = 4242) OR (deliverydate = '2025-12-14'::date))
--   Rows Removed by Filter: 4998251
--   Buffers: shared hit=8028 read=51711
-- Planning:
--   Buffers: shared hit=6
-- Planning Time: 0.030 ms
-- Execution Time: 220.250 ms
-- WRONG PLAN: Seq Scan. customerID has an index; deliveryDate has
-- none. One index can't answer an OR: a row with deliveryDate
-- 2025-12-14 might be anywhere, so the whole table must be read anyway.
-- Save this answer before changing anything (7.6 compares it):
CREATE TEMP TABLE r_or_seq AS
SELECT orderID, customerID, deliveryDate FROM orders_big
WHERE customerID = 4242 OR deliveryDate = '2025-12-14';

-- FIX A: index the other column too.
CREATE INDEX orders_big_deliverydate_idx ON orders_big (deliveryDate);
EXPLAIN (ANALYZE, BUFFERS)
SELECT orderID, customerID, deliveryDate FROM orders_big
WHERE customerID = 4242 OR deliveryDate = '2025-12-14';
--                                                                     QUERY PLAN
-- Bitmap Heap Scan on orders_big  (cost=24.53..5138.99 rows=1458 width=12) (actual time=0.088..0.478 rows=1749.00 loops=1)
--   Recheck Cond: ((customerid = 4242) OR (deliverydate = '2025-12-14'::date))
--   Heap Blocks: exact=414
--   Buffers: shared hit=417 read=5
--   ->  BitmapOr  (cost=24.53..24.53 rows=1458 width=0) (actual time=0.059..0.060 rows=0.00 loops=1)
--         Buffers: shared hit=3 read=5
--         ->  Bitmap Index Scan on orders_big_customerid_idx  (cost=0.00..5.22 rows=105 width=0) (actual time=0.008..0.009 rows=97.00 loops=1)
--               Index Cond: (customerid = 4242)
--               Index Searches: 1
--               Buffers: shared hit=3
--         ->  Bitmap Index Scan on orders_big_deliverydate_idx  (cost=0.00..18.58 rows=1353 width=0) (actual time=0.050..0.050 rows=1653.00 loops=1)
--               Index Cond: (deliverydate = '2025-12-14'::date)
--               Index Searches: 1
--               Buffers: shared read=5
-- Planning:
--   Buffers: shared hit=18 read=1
-- Planning Time: 0.134 ms
-- Execution Time: 0.520 ms
-- BitmapOr: two bitmap index scans, one per column, combined into one
-- set of pages.
CREATE TEMP TABLE r_or_index AS
SELECT orderID, customerID, deliveryDate FROM orders_big
WHERE customerID = 4242 OR deliveryDate = '2025-12-14';

-- FIX B, the usual advice: split the OR into two queries, one per
-- column, glued with UNION -- each half can use its own index:
EXPLAIN (ANALYZE, BUFFERS)
SELECT orderID, customerID, deliveryDate FROM orders_big WHERE customerID = 4242
UNION
SELECT orderID, customerID, deliveryDate FROM orders_big WHERE deliveryDate = '2025-12-14';
--                                                                                 QUERY PLAN
-- HashAggregate  (cost=483.77..498.35 rows=1458 width=12) (actual time=0.594..0.676 rows=1749.00 loops=1)
--   Group Key: orders_big.orderid, orders_big.customerid, orders_big.deliverydate
--   Batches: 1  Memory Usage: 121kB
--   Buffers: shared hit=423
--   ->  Append  (cost=5.25..472.84 rows=1458 width=12) (actual time=0.016..0.393 rows=1750.00 loops=1)
--         Buffers: shared hit=423
--         ->  Bitmap Heap Scan on orders_big  (cost=5.25..413.35 rows=105 width=12) (actual time=0.016..0.045 rows=97.00 loops=1)
--               Recheck Cond: (customerid = 4242)
--               Heap Blocks: exact=97
--               Buffers: shared hit=100
--               ->  Bitmap Index Scan on orders_big_customerid_idx  (cost=0.00..5.22 rows=105 width=0) (actual time=0.006..0.006 rows=97.00 loops=1)
--                     Index Cond: (customerid = 4242)
--                     Index Searches: 1
--                     Buffers: shared hit=3
--         ->  Index Scan using orders_big_deliverydate_idx on orders_big orders_big_1  (cost=0.43..52.19 rows=1353 width=12) (actual time=0.009..0.287 rows=1653.00 loops=1)
--               Index Cond: (deliverydate = '2025-12-14'::date)
--               Index Searches: 1
--               Buffers: shared hit=323
-- Planning:
--   Buffers: shared hit=11
-- Planning Time: 0.073 ms
-- Execution Time: 0.744 ms
-- Two index scans, appended, then duplicates removed (HashAggregate).
-- A colleague writes UNION ALL instead, "because it skips the
-- duplicate removal, so it's faster":
CREATE TEMP TABLE r_union_all AS
SELECT orderID, customerID, deliveryDate FROM orders_big WHERE customerID = 4242
UNION ALL
SELECT orderID, customerID, deliveryDate FROM orders_big WHERE deliveryDate = '2025-12-14';

-- ---- 7.5 Low selectivity (Part 4, again) ----
-- An index on status would not change Part 4.3's verdict: 92% of the
-- rows means read the table. That one isn't a trap; it's the planner
-- being right.

-- ---- 7.6 An index changes speed, never results. Prove it. ----
-- Before the index (Seq Scan) vs after it (BitmapOr), EXCEPT both ways,
-- with the row counts:
SELECT (SELECT count(*) FROM r_or_seq)   AS rows_seq_scan,
       (SELECT count(*) FROM r_or_index) AS rows_bitmap_or,
       (SELECT count(*) FROM (SELECT * FROM r_or_seq EXCEPT SELECT * FROM r_or_index) a) AS seq_not_index,
       (SELECT count(*) FROM (SELECT * FROM r_or_index EXCEPT SELECT * FROM r_or_seq) b) AS index_not_seq;
-- rows_seq_scan | rows_bitmap_or | seq_not_index | index_not_seq
--          1749 |           1749 |             0 |             0
-- 0 and 0, same count: the index changed the plan, not the answer.

-- Now the UNION ALL "optimization", checked the same way:
SELECT (SELECT count(*) FROM r_or_seq)    AS rows_or,
       (SELECT count(*) FROM r_union_all) AS rows_union_all,
       (SELECT count(*) FROM (SELECT * FROM r_or_seq EXCEPT SELECT * FROM r_union_all) a) AS or_not_union,
       (SELECT count(*) FROM (SELECT * FROM r_union_all EXCEPT SELECT * FROM r_or_seq) b) AS union_not_or;
-- rows_or | rows_union_all | or_not_union | union_not_or
--    1749 |           1750 |            0 |            0
-- EXCEPT says 0 and 0 -- but the counts differ by one. Order 4890168
-- is Nane's AND was delivered on 2025-12-14, so UNION ALL lists it
-- twice. EXCEPT compares SETS (Lecture 5, Part 6): duplicates vanish
-- before comparing, so it can't see this. EXCEPT ALL can:
SELECT orderID, customerID, deliveryDate FROM r_union_all
EXCEPT ALL
SELECT orderID, customerID, deliveryDate FROM r_or_seq;
-- orderid | customerid | deliverydate
-- 4890168 |       4242 | 2025-12-14
-- WRONG "optimization": it changed the answer (revenue summed over it
-- would count that order twice). FIX: UNION, which removes duplicate
-- rows -- or check every rewrite with EXCEPT ALL both ways AND
-- matching row counts.
SELECT count(*) AS rows_union FROM (
    SELECT orderID, customerID, deliveryDate FROM orders_big WHERE customerID = 4242
    UNION
    SELECT orderID, customerID, deliveryDate FROM orders_big WHERE deliveryDate = '2025-12-14'
) u;
-- rows_union
--       1749

-- The same proof on ground truth you already know -- the small
-- orders table, with its index forced (Part 1.1's planner would never
-- use it on 8 pages):
CREATE INDEX orders_status_idx ON orders (status);
SET enable_seqscan = off;
EXPLAIN
SELECT sum(orderTotal) FROM orders WHERE status = 'completed';
--                                       QUERY PLAN
-- Aggregate  (cost=28.19..28.20 rows=1 width=32)
--   ->  Bitmap Heap Scan on orders  (cost=12.25..26.86 rows=529 width=6)
--         Recheck Cond: ((status)::text = 'completed'::text)
--         ->  Bitmap Index Scan on orders_status_idx  (cost=0.00..12.12 rows=529 width=0)
--               Index Cond: ((status)::text = 'completed'::text)
SELECT sum(orderTotal) AS completed_revenue FROM orders WHERE status = 'completed';
-- completed_revenue
--         157078.41
RESET enable_seqscan;
DROP INDEX orders_status_idx;
-- 157,078.41 through the index -- the number from Lectures 4, 5 and 6.

-- Clean up: leave orders_big with its primary key only.
DROP INDEX orders_big_orderdate_idx, orders_big_customerid_idx, orders_big_deliverydate_idx;
DROP TABLE r_or_seq, r_or_index, r_union_all;
