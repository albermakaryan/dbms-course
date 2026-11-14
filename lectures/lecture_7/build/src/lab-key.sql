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
-- =>
-- Index Scan using orders_big_pkey, Index Cond on orderid, 4 pages
-- (3 index levels + 1 table page), 1 row estimated and 1 actual.

-- ---- Lab 2: find the estimate gap, then close it ----
-- "Sunday orders" (isodow 7):
EXPLAIN ANALYZE
SELECT count(*) FROM orders_big WHERE extract(isodow FROM orderDate) = 7;
-- =>
-- Estimated 25,000 (the fixed 0.5% guess for an expression with no
-- statistics), actual about 714,000. An expression index makes ANALYZE
-- collect statistics on the expression -- even if the index itself is
-- never used for this query:
CREATE INDEX orders_big_isodow_idx ON orders_big ((extract(isodow FROM orderDate)));
ANALYZE orders_big;
EXPLAIN ANALYZE
SELECT count(*) FROM orders_big WHERE extract(isodow FROM orderDate) = 7;
-- =>
-- Now the estimate is close to the actual count. (An alternative
-- without an index, PostgreSQL 14+: CREATE STATISTICS on the expression.)
DROP INDEX orders_big_isodow_idx;
ANALYZE orders_big;

-- ---- Lab 3: an index for "customer 777's 20 latest orders" ----
EXPLAIN (ANALYZE, BUFFERS)
SELECT orderID, orderDate, orderTotal FROM orders_big
WHERE customerID = 777 ORDER BY orderDate DESC, orderID DESC LIMIT 20;
-- =>
CREATE INDEX orders_big_cust_recent_idx ON orders_big (customerID, orderDate DESC, orderID DESC);
EXPLAIN (ANALYZE, BUFFERS)
SELECT orderID, orderDate, orderTotal FROM orders_big
WHERE customerID = 777 ORDER BY orderDate DESC, orderID DESC LIMIT 20;
-- =>
-- Expected: Limit over an Index Scan with Index Cond on customerid,
-- no Sort node, a few dozen pages instead of the whole table.
DROP INDEX orders_big_cust_recent_idx;

-- ---- Lab 4: a partial index for the cancellations desk ----
-- "Cancelled orders over 1,000 in December 2025":
CREATE INDEX orders_big_cancelled_idx ON orders_big (orderDate) WHERE status = 'cancelled';
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE status = 'cancelled' AND orderDate >= '2025-12-01' AND orderTotal > 1000;
-- =>
-- Used: Index Cond on orderdate, Filter on ordertotal (not in the index).
SELECT pg_size_pretty(pg_relation_size('orders_big_cancelled_idx')) AS size;
-- =>
DROP INDEX orders_big_cancelled_idx;

-- ---- Lab 5: three slow queries -- fix each, prove the answer didn't change ----
CREATE INDEX orders_big_orderdate_idx ON orders_big (orderDate);
CREATE INDEX orders_big_customerid_idx ON orders_big (customerID);
-- (a) a function on the column
EXPLAIN SELECT count(*) FROM orders_big WHERE orderDate + 7 > '2025-12-31';
-- =>
EXPLAIN SELECT count(*) FROM orders_big WHERE orderDate > DATE '2025-12-31' - 7;
-- =>
SELECT (SELECT count(*) FROM orders_big WHERE orderDate + 7 > '2025-12-31') AS slow,
       (SELECT count(*) FROM orders_big WHERE orderDate > DATE '2025-12-31' - 7) AS fast;
-- =>
-- (b) a cast on the column
EXPLAIN SELECT count(*) FROM orders_big WHERE customerID::numeric = 777;
-- =>
EXPLAIN SELECT count(*) FROM orders_big WHERE customerID = 777;
-- =>
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
-- =>
DROP INDEX orders_big_orderdate_idx, orders_big_customerid_idx;

-- ---- Lab 6: measure write cost yourself ----
-- 500,000 rows into an empty copy, with 0 and with 3 indexes; three
-- runs each (BEGIN ... ROLLBACK keeps the copy empty). Report medians.
CREATE TABLE orders_load (LIKE orders_big) WITH (autovacuum_enabled = off);
BEGIN;
EXPLAIN (ANALYZE, COSTS OFF)
INSERT INTO orders_load SELECT * FROM orders_big WHERE orderID <= 500000;
-- =>
ROLLBACK;
CREATE INDEX ON orders_load (customerID);
CREATE INDEX ON orders_load (orderDate);
CREATE INDEX ON orders_load (status);
BEGIN;
EXPLAIN (ANALYZE, COSTS OFF)
INSERT INTO orders_load SELECT * FROM orders_big WHERE orderID <= 500000;
-- =>
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
-- =>
EXPLAIN SELECT count(*) FROM orders_by_channel WHERE orderDate >= '2025-12-01';
-- =>
-- Pruned to one partition for channel; both partitions for a date
-- filter. Correctness: per-partition counts add up to 5,000,000.
SELECT tableoid::regclass AS partition, count(*) FROM orders_by_channel GROUP BY tableoid ORDER BY 1;
-- =>
DROP TABLE orders_by_channel;

-- ---- Lab 8: which index is never used? ----
-- Two indexes, a small workload, then pg_stat_user_indexes (Part 10.2).
CREATE INDEX orders_big_rating_idx ON orders_big (rating);
CREATE INDEX orders_big_customerid_idx ON orders_big (customerID);
SELECT count(*) FROM orders_big WHERE customerID = 777;
-- =>
SELECT count(*) FROM orders_big WHERE customerID = 778;
-- =>
-- The ratings dashboard counts good ratings, treating "no rating" as 0:
SELECT count(*) AS good_ratings, round(avg(orderTotal), 2) AS avg_total
FROM orders_big WHERE coalesce(rating, 0) >= 4;
-- =>
SELECT pg_sleep(1.5);
SELECT indexrelname AS index, idx_scan AS times_used
FROM pg_stat_user_indexes
WHERE indexrelname IN ('orders_big_rating_idx', 'orders_big_customerid_idx')
ORDER BY indexrelname;
-- =>
-- Expected: customerID used, rating 0 -- coalesce() on the column
-- (Part 7.1). Fix: WHERE rating >= 4 gives the same count (NULL >= 4
-- is never true, and coalesce turned NULL into 0, which isn't >= 4 either).
SELECT count(*) AS good_ratings, round(avg(orderTotal), 2) AS avg_total
FROM orders_big WHERE rating >= 4;
-- =>
-- Note for grading: idx_scan also counts FULL scans of an index (an
-- Index Only Scan with a Filter, Part 7.2), so "used" in this view
-- doesn't always mean "searched". With only count(*), the coalesce
-- version is answered by reading the whole rating index (idx_scan 1).
DROP INDEX orders_big_rating_idx, orders_big_customerid_idx;
