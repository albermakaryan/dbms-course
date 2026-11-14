-- ============================================================
-- Lecture 7 — Lab solution key (INSTRUCTOR ONLY -- not lectured,
-- not in lecture-07-demo.sql or the notebook)
-- Run after Part 10, on the lecture07 database: orders_big has its
-- primary key only. Each task removes what it creates.
-- ============================================================

-- ---- Lab 1: read a plan ----
-- One order by its number: which node, how many pages, Index Cond or Filter?
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_big WHERE orderID = 4242424;
--                                                           QUERY PLAN
-- Index Scan using orders_big_pkey on orders_big  (cost=0.43..8.45 rows=1 width=60) (actual time=0.044..0.044 rows=1.00 loops=1)
--   Index Cond: (orderid = 4242424)
--   Index Searches: 1
--   Buffers: shared read=4
-- Planning:
--   Buffers: shared hit=92
-- Planning Time: 0.209 ms
-- Execution Time: 0.080 ms
-- Index Scan using orders_big_pkey, Index Cond on orderid, 4 pages
-- (3 index levels + 1 table page), 1 row estimated and 1 actual.

-- ---- Lab 2: find the estimate gap, then close it ----
-- "Sunday orders" (isodow 7):
EXPLAIN ANALYZE
SELECT count(*) FROM orders_big WHERE extract(isodow FROM orderDate) = 7;
--                                                         QUERY PLAN
-- Aggregate  (cost=134803.27..134803.28 rows=1 width=8) (actual time=496.757..496.758 rows=1.00 loops=1)
--   Buffers: shared hit=14898 read=44841
--   ->  Seq Scan on orders_big  (cost=0.00..134740.77 rows=25001 width=0) (actual time=2.686..477.875 rows=714670.00 loops=1)
--         Filter: (EXTRACT(isodow FROM orderdate) = '7'::numeric)
--         Rows Removed by Filter: 4285330
--         Buffers: shared hit=14898 read=44841
-- Planning:
--   Buffers: shared hit=9
-- Planning Time: 0.033 ms
-- Execution Time: 496.773 ms
-- Estimated 25,000 (the fixed 0.5% guess for an expression with no
-- statistics), actual about 714,000. An expression index makes ANALYZE
-- collect statistics on the expression -- even if the index itself is
-- never used for this query:
CREATE INDEX orders_big_isodow_idx ON orders_big ((extract(isodow FROM orderDate)));
ANALYZE orders_big;
EXPLAIN ANALYZE
SELECT count(*) FROM orders_big WHERE extract(isodow FROM orderDate) = 7;
--                                                                      QUERY PLAN
-- Aggregate  (cost=86303.86..86303.87 rows=1 width=8) (actual time=87.726..87.727 rows=1.00 loops=1)
--   Buffers: shared hit=2046 read=8595 written=7150
--   ->  Bitmap Heap Scan on orders_big  (cost=13737.24..84471.34 rows=733007 width=0) (actual time=17.491..69.888 rows=714670.00 loops=1)
--         Recheck Cond: (EXTRACT(isodow FROM orderdate) = '7'::numeric)
--         Heap Blocks: exact=8685
--         Buffers: shared hit=2046 read=8595 written=7150
--         ->  Bitmap Index Scan on orders_big_isodow_idx  (cost=0.00..13553.99 rows=733007 width=0) (actual time=16.731..16.732 rows=714670.00 loops=1)
--               Index Cond: (EXTRACT(isodow FROM orderdate) = '7'::numeric)
--               Index Searches: 1
--               Buffers: shared read=1956 written=550
-- Planning:
--   Buffers: shared hit=19 read=2
-- Planning Time: 0.108 ms
-- Execution Time: 87.742 ms
-- Now the estimate is close to the actual count. (An alternative
-- without an index, PostgreSQL 14+: CREATE STATISTICS on the expression.)
DROP INDEX orders_big_isodow_idx;
ANALYZE orders_big;

-- ---- Lab 3: an index for "customer 777's 20 latest orders" ----
EXPLAIN (ANALYZE, BUFFERS)
SELECT orderID, orderDate, orderTotal FROM orders_big
WHERE customerID = 777 ORDER BY orderDate DESC, orderID DESC LIMIT 20;
--                                                          QUERY PLAN
-- Limit  (cost=122243.95..122244.00 rows=20 width=14) (actual time=135.539..135.542 rows=20.00 loops=1)
--   Buffers: shared hit=14340 read=45399
--   ->  Sort  (cost=122243.95..122244.21 rows=106 width=14) (actual time=135.538..135.539 rows=20.00 loops=1)
--         Sort Key: orderdate DESC, orderid DESC
--         Sort Method: top-N heapsort  Memory: 26kB
--         Buffers: shared hit=14340 read=45399
--         ->  Seq Scan on orders_big  (cost=0.00..122241.12 rows=106 width=14) (actual time=0.366..135.509 rows=111.00 loops=1)
--               Filter: (customerid = 777)
--               Rows Removed by Filter: 4999889
--               Buffers: shared hit=14340 read=45399
-- Planning:
--   Buffers: shared hit=42 read=1
-- Planning Time: 0.107 ms
-- Execution Time: 135.558 ms
CREATE INDEX orders_big_cust_recent_idx ON orders_big (customerID, orderDate DESC, orderID DESC);
EXPLAIN (ANALYZE, BUFFERS)
SELECT orderID, orderDate, orderTotal FROM orders_big
WHERE customerID = 777 ORDER BY orderDate DESC, orderID DESC LIMIT 20;
--                                                                      QUERY PLAN
-- Limit  (cost=0.43..81.54 rows=20 width=14) (actual time=0.013..0.044 rows=20.00 loops=1)
--   Buffers: shared hit=12 read=11
--   ->  Index Scan using orders_big_cust_recent_idx on orders_big  (cost=0.43..430.29 rows=106 width=14) (actual time=0.012..0.042 rows=20.00 loops=1)
--         Index Cond: (customerid = 777)
--         Index Searches: 1
--         Buffers: shared hit=12 read=11
-- Planning:
--   Buffers: shared hit=21 read=1 dirtied=1
-- Planning Time: 0.084 ms
-- Execution Time: 0.051 ms
-- Expected: Limit over an Index Scan with Index Cond on customerid,
-- no Sort node, a few dozen pages instead of the whole table.
DROP INDEX orders_big_cust_recent_idx;

-- ---- Lab 4: a partial index for the cancellations desk ----
-- "Cancelled orders over 1,000 in December 2025":
CREATE INDEX orders_big_cancelled_idx ON orders_big (orderDate) WHERE status = 'cancelled';
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE status = 'cancelled' AND orderDate >= '2025-12-01' AND orderTotal > 1000;
--                                                                      QUERY PLAN
-- Aggregate  (cost=201.19..201.20 rows=1 width=40) (actual time=1.700..1.700 rows=1.00 loops=1)
--   Buffers: shared hit=1817 read=46
--   ->  Index Scan using orders_big_cancelled_idx on orders_big  (cost=0.29..194.05 rows=1427 width=6) (actual time=0.013..1.608 rows=1477.00 loops=1)
--         Index Cond: (orderdate >= '2025-12-01'::date)
--         Filter: (ordertotal > '1000'::numeric)
--         Rows Removed by Filter: 3891
--         Index Searches: 1
--         Buffers: shared hit=1817 read=46
-- Planning:
--   Buffers: shared hit=73 read=4
-- Planning Time: 0.182 ms
-- Execution Time: 1.715 ms
-- Used: Index Cond on orderdate, Filter on ordertotal (not in the index).
SELECT pg_size_pretty(pg_relation_size('orders_big_cancelled_idx')) AS size;
--  size
-- 1104 kB
DROP INDEX orders_big_cancelled_idx;

-- ---- Lab 5: three slow queries -- fix each, prove the answer didn't change ----
CREATE INDEX orders_big_orderdate_idx ON orders_big (orderDate);
CREATE INDEX orders_big_customerid_idx ON orders_big (customerID);
-- (a) a function on the column
EXPLAIN SELECT count(*) FROM orders_big WHERE orderDate + 7 > '2025-12-31';
--                                                   QUERY PLAN
-- Aggregate  (cost=121338.64..121338.65 rows=1 width=8)
--   ->  Index Only Scan using orders_big_orderdate_idx on orders_big  (cost=0.43..117171.83 rows=1666723 width=0)
--         Filter: ((orderdate + 7) > '2025-12-31'::date)
EXPLAIN SELECT count(*) FROM orders_big WHERE orderDate > DATE '2025-12-31' - 7;
--                                                 QUERY PLAN
-- Aggregate  (cost=869.51..869.52 rows=1 width=8)
--   ->  Index Only Scan using orders_big_orderdate_idx on orders_big  (cost=0.43..776.88 rows=37054 width=0)
--         Index Cond: (orderdate > '2025-12-24'::date)
SELECT (SELECT count(*) FROM orders_big WHERE orderDate + 7 > '2025-12-31') AS slow,
       (SELECT count(*) FROM orders_big WHERE orderDate > DATE '2025-12-31' - 7) AS fast;
-- slow  | fast
-- 37549 | 37549
-- (b) a cast on the column
EXPLAIN SELECT count(*) FROM orders_big WHERE customerID::numeric = 777;
--                                                   QUERY PLAN
-- Aggregate  (cost=117506.34..117506.35 rows=1 width=8)
--   ->  Index Only Scan using orders_big_customerid_idx on orders_big  (cost=0.43..117443.83 rows=25001 width=0)
--         Filter: ((customerid)::numeric = '777'::numeric)
EXPLAIN SELECT count(*) FROM orders_big WHERE customerID = 777;
--                                               QUERY PLAN
-- Aggregate  (cost=6.55..6.56 rows=1 width=8)
--   ->  Index Only Scan using orders_big_customerid_idx on orders_big  (cost=0.43..6.29 rows=106 width=0)
--         Index Cond: (customerid = 777)
-- (c) OR on two columns, one without an index -> UNION, checked with
-- EXCEPT ALL both ways and counts
SELECT (SELECT count(*) FROM (
            SELECT orderID FROM orders_big WHERE customerID = 777 OR orderDate = '2025-12-31'
            EXCEPT ALL
            (SELECT orderID FROM orders_big WHERE customerID = 777
             UNION
             SELECT orderID FROM orders_big WHERE orderDate = '2025-12-31')) a) AS or_not_union,
       (SELECT count(*) FROM (
            (SELECT orderID FROM orders_big WHERE customerID = 777
             UNION
             SELECT orderID FROM orders_big WHERE orderDate = '2025-12-31')
            EXCEPT ALL
            SELECT orderID FROM orders_big WHERE customerID = 777 OR orderDate = '2025-12-31') b) AS union_not_or;
-- or_not_union | union_not_or
--            0 |            0
DROP INDEX orders_big_orderdate_idx, orders_big_customerid_idx;

-- ---- Lab 6: measure write cost yourself ----
-- 500,000 rows into an empty copy, with 0 and with 3 indexes; three
-- runs each (BEGIN ... ROLLBACK keeps the copy empty). Report medians.
CREATE TABLE orders_load (LIKE orders_big) WITH (autovacuum_enabled = off);
BEGIN;
EXPLAIN (ANALYZE, COSTS OFF)
INSERT INTO orders_load SELECT * FROM orders_big WHERE orderID <= 500000;
--                                               QUERY PLAN
-- Insert on orders_load (actual time=279.789..279.790 rows=0.00 loops=1)
--   Buffers: shared hit=512510 read=6791 dirtied=5976 written=7261
--   ->  Index Scan using orders_big_pkey on orders_big (actual time=0.021..63.268 rows=500000.00 loops=1)
--         Index Cond: (orderid <= 500000)
--         Index Searches: 1
--         Buffers: shared hit=557 read=6791 written=711
-- Planning:
--   Buffers: shared hit=34
-- Planning Time: 0.171 ms
-- Execution Time: 279.812 ms
ROLLBACK;
CREATE INDEX ON orders_load (customerID);
CREATE INDEX ON orders_load (orderDate);
CREATE INDEX ON orders_load (status);
BEGIN;
EXPLAIN (ANALYZE, COSTS OFF)
INSERT INTO orders_load SELECT * FROM orders_big WHERE orderID <= 500000;
--                                               QUERY PLAN
-- Insert on orders_load (actual time=1390.394..1390.394 rows=0.00 loops=1)
--   Buffers: shared hit=3881849 read=4655 dirtied=7488 written=7881
--   ->  Index Scan using orders_big_pkey on orders_big (actual time=0.007..61.629 rows=500000.00 loops=1)
--         Index Cond: (orderid <= 500000)
--         Index Searches: 1
--         Buffers: shared hit=2696 read=4652 written=11
-- Planning Time: 0.069 ms
-- Execution Time: 1390.413 ms
ROLLBACK;
-- Expected: the Insert node's time grows several times with three
-- indexes. (Students repeat each BEGIN ... ROLLBACK block 3 times.)
DROP TABLE orders_load;

-- ---- Lab 7: LIST partitioning by channel ----
CREATE TABLE orders_by_channel (LIKE orders_big) PARTITION BY LIST (channel);
CREATE TABLE orders_by_channel_online   PARTITION OF orders_by_channel FOR VALUES IN ('online');
CREATE TABLE orders_by_channel_in_store PARTITION OF orders_by_channel FOR VALUES IN ('in_store');
INSERT INTO orders_by_channel SELECT * FROM orders_big;
ANALYZE orders_by_channel;
EXPLAIN SELECT count(*) FROM orders_by_channel WHERE channel = 'online';
--                                                QUERY PLAN
-- Aggregate  (cost=45105.30..45105.31 rows=1 width=8)
--   ->  Seq Scan on orders_by_channel_online orders_by_channel  (cost=0.00..40980.25 rows=1650020 width=0)
--         Filter: ((channel)::text = 'online'::text)
EXPLAIN SELECT count(*) FROM orders_by_channel WHERE orderDate >= '2025-12-01';
--                                                    QUERY PLAN
-- Aggregate  (cost=123511.35..123511.36 rows=1 width=8)
--   ->  Append  (cost=0.00..123100.60 rows=164298 width=0)
--         ->  Seq Scan on orders_by_channel_in_store orders_by_channel_1  (cost=0.00..81298.86 rows=111626 width=0)
--               Filter: (orderdate >= '2025-12-01'::date)
--         ->  Seq Scan on orders_by_channel_online orders_by_channel_2  (cost=0.00..40980.25 rows=52672 width=0)
--               Filter: (orderdate >= '2025-12-01'::date)
-- Pruned to one partition for channel; both partitions for a date
-- filter. Correctness: per-partition counts add up to 5,000,000.
SELECT tableoid::regclass AS partition, count(*) FROM orders_by_channel GROUP BY tableoid ORDER BY 1;
--         partition          |  count
-- orders_by_channel_online   | 1650020
-- orders_by_channel_in_store | 3349980
DROP TABLE orders_by_channel;

-- ---- Lab 8: which index is never used? ----
-- Two indexes, a small workload, then pg_stat_user_indexes (Part 10.2).
CREATE INDEX orders_big_rating_idx ON orders_big (rating);
CREATE INDEX orders_big_customerid_idx ON orders_big (customerID);
SELECT count(*) FROM orders_big WHERE customerID = 777;
-- count
--   111
SELECT count(*) FROM orders_big WHERE customerID = 778;
-- count
--   104
-- The ratings dashboard counts good ratings, treating "no rating" as 0:
SELECT count(*) AS good_ratings, round(avg(orderTotal), 2) AS avg_total
FROM orders_big WHERE coalesce(rating, 0) >= 4;
-- good_ratings | avg_total
--       800452 |    640.55
SELECT pg_sleep(1.5);
SELECT indexrelname AS index, idx_scan AS times_used
FROM pg_stat_user_indexes
WHERE indexrelname IN ('orders_big_rating_idx', 'orders_big_customerid_idx')
ORDER BY indexrelname;
--           index           | times_used
-- orders_big_customerid_idx |          2
-- orders_big_rating_idx     |          0
-- Expected: customerID used, rating 0 -- coalesce() on the column
-- (Part 7.1). Fix: WHERE rating >= 4 gives the same count (NULL >= 4
-- is never true, and coalesce turned NULL into 0, which isn't >= 4 either).
SELECT count(*) AS good_ratings, round(avg(orderTotal), 2) AS avg_total
FROM orders_big WHERE rating >= 4;
-- good_ratings | avg_total
--       800452 |    640.55
-- Note for grading: idx_scan also counts FULL scans of an index (an
-- Index Only Scan with a Filter, Part 7.2), so "used" in this view
-- doesn't always mean "searched". With only count(*), the coalesce
-- version is answered by reading the whole rating index (idx_scan 1).
DROP INDEX orders_big_rating_idx, orders_big_customerid_idx;
