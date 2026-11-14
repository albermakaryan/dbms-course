-- ============================================================
-- Lecture 7 — Part 9: Partitioning
-- Run after Part 8.
--
-- A partitioned table is ONE table to your queries, stored as several
-- physical tables (partitions), each holding the rows for one range or
-- list of values of the PARTITION KEY. Here: one partition per year of
-- orderDate. Queries see one table; the planner skips the partitions a
-- query can't need ("partition pruning").
-- ============================================================

-- Start clean (in case you ran this Part before).
DROP TABLE IF EXISTS orders_big_part, orders_big_daily;

-- ---- 9.1 Build it: same columns, same rows, by year ----
-- PARTITION BY RANGE (orderDate): each partition takes a range of
-- dates, FROM inclusive TO exclusive. (Two other kinds: PARTITION BY
-- LIST (channel) -- one partition per listed value; PARTITION BY HASH
-- (customerID) -- rows spread evenly over N partitions by a hash of
-- the key.)
CREATE TABLE orders_big_part (LIKE orders_big INCLUDING DEFAULTS INCLUDING CONSTRAINTS)
    PARTITION BY RANGE (orderDate);
CREATE TABLE orders_big_part_2023 PARTITION OF orders_big_part
    FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');
CREATE TABLE orders_big_part_2024 PARTITION OF orders_big_part
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE orders_big_part_2025 PARTITION OF orders_big_part
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');

-- Insert into the parent; each row goes to its partition by itself.
INSERT INTO orders_big_part SELECT * FROM orders_big;
VACUUM ANALYZE orders_big_part;

-- Where did the rows go? tableoid is the physical table a row lives in.
SELECT tableoid::regclass AS partition, count(*) AS rows
FROM orders_big_part
GROUP BY tableoid
ORDER BY partition;
--      partition       |  rows
-- orders_big_part_2023 | 1371464
-- orders_big_part_2024 | 1733359
-- orders_big_part_2025 | 1895177
SELECT (SELECT count(*) FROM orders_big_part) AS partitioned,
       (SELECT count(*) FROM orders_big)      AS unpartitioned;
-- partitioned | unpartitioned
--     5000000 |       5000000
-- 1,371,464 + 1,733,359 + 1,895,177 = 5,000,000.

-- ---- 9.2 Same data? Prove it before trusting it ----
-- Month by month, orders and revenue from both tables, EXCEPT both ways:
WITH a AS (SELECT date_trunc('month', orderDate) AS month, count(*) AS n, sum(orderTotal) AS revenue
           FROM orders_big GROUP BY 1),
     b AS (SELECT date_trunc('month', orderDate) AS month, count(*) AS n, sum(orderTotal) AS revenue
           FROM orders_big_part GROUP BY 1)
SELECT (SELECT count(*) FROM a) AS months,
       (SELECT count(*) FROM (SELECT * FROM a EXCEPT SELECT * FROM b) x) AS big_not_part,
       (SELECT count(*) FROM (SELECT * FROM b EXCEPT SELECT * FROM a) y) AS part_not_big;
-- months | big_not_part | part_not_big
--     36 |            0 |            0
-- 36 months, 0 and 0.

-- ---- 9.3 Partition pruning ----
-- June 2025, from both tables (neither has an index on orderDate):
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE orderDate >= '2025-06-01' AND orderDate < '2025-07-01';
--                                                           QUERY PLAN
-- Aggregate  (cost=135467.47..135467.48 rows=1 width=40) (actual time=186.128..186.129 rows=1.00 loops=1)
--   Buffers: shared hit=188 read=59551 written=20
--   ->  Seq Scan on orders_big  (cost=0.00..134739.61 rows=145570 width=6) (actual time=138.048..174.889 rows=155419.00 loops=1)
--         Filter: ((orderdate >= '2025-06-01'::date) AND (orderdate < '2025-07-01'::date))
--         Rows Removed by Filter: 4844581
--         Buffers: shared hit=188 read=59551 written=20
-- Planning:
--   Buffers: shared hit=3
-- Planning Time: 0.062 ms
-- Execution Time: 186.145 ms
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big_part
WHERE orderDate >= '2025-06-01' AND orderDate < '2025-07-01';
--                                                                      QUERY PLAN
-- Aggregate  (cost=51832.98..51832.99 rows=1 width=40) (actual time=83.022..83.023 rows=1.00 loops=1)
--   Buffers: shared hit=15342 read=7301
--   ->  Seq Scan on orders_big_part_2025 orders_big_part  (cost=0.00..51070.65 rows=152464 width=6) (actual time=33.904..74.987 rows=155419.00 loops=1)
--         Filter: ((orderdate >= '2025-06-01'::date) AND (orderdate < '2025-07-01'::date))
--         Rows Removed by Filter: 1739758
--         Buffers: shared hit=15342 read=7301
-- Planning:
--   Buffers: shared hit=18 read=2
-- Planning Time: 0.174 ms
-- Execution Time: 83.040 ms
-- One partition in the plan: orders_big_part_2025. 2023 and 2024
-- aren't there at all -- the planner proved from the partition bounds
-- that they can't hold June 2025. About 38% of the pages, same answer.

-- ---- 9.4 THE TRAP: a filter the planner can't prune with ----
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big_part
WHERE extract(year FROM orderDate) = 2025;
--                                                                          QUERY PLAN
-- Aggregate  (cost=134989.00..134989.01 rows=1 width=40) (actual time=680.679..680.684 rows=1.00 loops=1)
--   Buffers: shared hit=15723 read=44016 written=5
--   ->  Append  (cost=0.00..134864.00 rows=25000 width=6) (actual time=271.545..583.674 rows=1895177.00 loops=1)
--         Buffers: shared hit=15723 read=44016 written=5
--         ->  Seq Scan on orders_big_part_2023 orders_big_part_1  (cost=0.00..36956.96 rows=6857 width=6) (actual time=119.229..119.230 rows=0.00 loops=1)
--               Filter: (EXTRACT(year FROM orderdate) = '2025'::numeric)
--               Rows Removed by Filter: 1371464
--               Buffers: shared hit=185 read=16200 written=5
--         ->  Seq Scan on orders_big_part_2024 orders_big_part_2  (cost=0.00..46711.38 rows=8667 width=6) (actual time=152.289..152.290 rows=0.00 loops=1)
--               Filter: (EXTRACT(year FROM orderdate) = '2025'::numeric)
--               Rows Removed by Filter: 1733359
--               Buffers: shared hit=188 read=20523
--         ->  Seq Scan on orders_big_part_2025 orders_big_part_3  (cost=0.00..51070.65 rows=9476 width=6) (actual time=0.023..246.265 rows=1895177.00 loops=1)
--               Filter: (EXTRACT(year FROM orderdate) = '2025'::numeric)
--               Buffers: shared hit=15350 read=7293
-- Planning Time: 0.137 ms
-- Execution Time: 680.707 ms
-- WRONG PLAN: all three partitions (Append with three Seq Scans). The
-- 2023 and 2024 scans return 0 rows -- after reading every page. The
-- bounds are on orderDate, not on extract(year FROM orderDate) (Part
-- 7.1 again). FIX: a range on the key itself.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big_part
WHERE orderDate >= '2025-01-01' AND orderDate < '2026-01-01';
--                                                                       QUERY PLAN
-- Aggregate  (cost=60544.69..60544.70 rows=1 width=40) (actual time=252.787..252.788 rows=1.00 loops=1)
--   Buffers: shared hit=15444 read=7199 written=2
--   ->  Seq Scan on orders_big_part_2025 orders_big_part  (cost=0.00..51070.65 rows=1894807 width=6) (actual time=0.291..153.631 rows=1895177.00 loops=1)
--         Filter: ((orderdate >= '2025-01-01'::date) AND (orderdate < '2026-01-01'::date))
--         Buffers: shared hit=15444 read=7199 written=2
-- Planning Time: 0.182 ms
-- Execution Time: 252.805 ms
-- One partition. And with no filter on orderDate at all -- "Nane's
-- orders" -- every partition, every time:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big_part WHERE customerID = 4242;
--                                                                      QUERY PLAN
-- Aggregate  (cost=122239.79..122239.80 rows=1 width=8) (actual time=142.261..142.262 rows=1.00 loops=1)
--   Buffers: shared hit=15914 read=43825
--   ->  Append  (cost=0.00..122239.52 rows=105 width=0) (actual time=2.517..142.245 rows=97.00 loops=1)
--         Buffers: shared hit=15914 read=43825
--         ->  Seq Scan on orders_big_part_2023 orders_big_part_1  (cost=0.00..33528.30 rows=29 width=0) (actual time=2.516..39.619 rows=17.00 loops=1)
--               Filter: (customerid = 4242)
--               Rows Removed by Filter: 1371447
--               Buffers: shared hit=188 read=16197
--         ->  Seq Scan on orders_big_part_2024 orders_big_part_2  (cost=0.00..42377.99 rows=36 width=0) (actual time=0.744..49.153 rows=37.00 loops=1)
--               Filter: (customerid = 4242)
--               Rows Removed by Filter: 1733322
--               Buffers: shared hit=188 read=20523
--         ->  Seq Scan on orders_big_part_2025 orders_big_part_3  (cost=0.00..46332.71 rows=40 width=0) (actual time=2.566..53.459 rows=43.00 loops=1)
--               Filter: (customerid = 4242)
--               Rows Removed by Filter: 1895134
--               Buffers: shared hit=15538 read=7105
-- Planning:
--   Buffers: shared hit=8 read=1 dirtied=1
-- Planning Time: 0.260 ms
-- Execution Time: 142.281 ms
-- Partitioning by date helps only queries that filter on date.

-- ---- 9.5 THE TRAP: a row with no partition ----
-- An order dated 2026 arrives (or a typo: 2205 instead of 2025).
-- Error on purpose:
INSERT INTO orders_big_part VALUES
    (5000001, 4242, NULL, '2026-01-02', '10:00', 'online', 'card', 'completed', NULL, NULL, 99.00);
-- ERROR:  no partition of relation "orders_big_part" found for row
-- DETAIL:  Partition key of the failing row contains (orderdate) = (2026-01-02).
-- A loud error -- the good kind. The usual "fix" is a DEFAULT
-- partition, which takes every row that fits nowhere else:
CREATE TABLE orders_big_part_default PARTITION OF orders_big_part DEFAULT;
INSERT INTO orders_big_part VALUES
    (5000001, 4242, NULL, '2026-01-02', '10:00', 'online', 'card', 'completed', NULL, NULL, 99.00);
SELECT tableoid::regclass AS partition, orderID, orderDate
FROM orders_big_part
WHERE orderID = 5000001;
--        partition        | orderid | orderdate
-- orders_big_part_default | 5000001 | 2026-01-02
-- Accepted, silently, into orders_big_part_default. Every wrong date
-- will collect there now, without a word. And when 2026 comes and you
-- add its partition -- error on purpose:
CREATE TABLE orders_big_part_2026 PARTITION OF orders_big_part
    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
-- ERROR:  updated partition constraint for default partition "orders_big_part_default" would be violated by some row
-- The default partition already holds a 2026 row, so the new partition
-- can't be created. FIX: create partitions BEFORE their data arrives,
-- and keep the default partition empty (count it in a daily check).
-- To repair this one: take the row out, add the partition, put it back.
DELETE FROM orders_big_part WHERE orderID = 5000001;
CREATE TABLE orders_big_part_2026 PARTITION OF orders_big_part
    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
INSERT INTO orders_big_part VALUES
    (5000001, 4242, NULL, '2026-01-02', '10:00', 'online', 'card', 'completed', NULL, NULL, 99.00);
SELECT tableoid::regclass AS partition, orderID, orderDate
FROM orders_big_part
WHERE orderID = 5000001;
--      partition       | orderid | orderdate
-- orders_big_part_2026 | 5000001 | 2026-01-02

-- ---- 9.6 THE TRAP: unique means unique per partition ----
-- orders_big has PRIMARY KEY (orderID). Error on purpose:
ALTER TABLE orders_big_part ADD PRIMARY KEY (orderID);
-- ERROR:  unique constraint on partitioned table must include all partitioning columns
-- DETAIL:  PRIMARY KEY constraint on table "orders_big_part" lacks column "orderdate" which is part of the partition key.
-- Each partition can check uniqueness only inside itself, so a unique
-- constraint must contain the partition key. The accepted version:
ALTER TABLE orders_big_part ADD PRIMARY KEY (orderID, orderDate);
-- Now the same orderID with a different date. Predict, then run:
INSERT INTO orders_big_part VALUES
    (5000001, 4242, NULL, '2025-12-31', '10:00', 'online', 'card', 'completed', NULL, NULL, 99.00);
SELECT tableoid::regclass AS partition, orderID, orderDate
FROM orders_big_part
WHERE orderID = 5000001
ORDER BY orderDate;
--      partition       | orderid | orderdate
-- orders_big_part_2025 | 5000001 | 2025-12-31
-- orders_big_part_2026 | 5000001 | 2026-01-02
-- WRONG: two orders numbered 5000001, and the "primary key" allowed
-- it: (5000001, 2025-12-31) and (5000001, 2026-01-02) are different
-- pairs. No error. PostgreSQL has no index that spans partitions, so
-- it can't promise orderID is unique across them. FIX: generate
-- orderIDs from one sequence (an IDENTITY column) so duplicates can't
-- be made -- and check: count(*) = count(DISTINCT orderID).
SELECT count(*) AS rows, count(DISTINCT orderID) AS distinct_ids FROM orders_big_part;
--  rows   | distinct_ids
-- 5000002 |      5000001
DELETE FROM orders_big_part WHERE orderID = 5000001;
DROP TABLE orders_big_part_2026, orders_big_part_default;

-- ---- 9.7 Too many tiny partitions ----
-- The same 5 million rows, one partition PER DAY: 1,096 partitions.
CREATE TABLE orders_big_daily (LIKE orders_big) PARTITION BY RANGE (orderDate);
DO $$
DECLARE d date;
BEGIN
    FOR d IN SELECT generate_series(DATE '2023-01-01', DATE '2025-12-31', INTERVAL '1 day')::date LOOP
        EXECUTE format('CREATE TABLE orders_big_daily_%s PARTITION OF orders_big_daily FOR VALUES FROM (%L) TO (%L)',
                       to_char(d, 'YYYYMMDD'), d, d + 1);
    END LOOP;
END $$;
INSERT INTO orders_big_daily SELECT * FROM orders_big;
VACUUM ANALYZE orders_big_daily;
SELECT count(*) AS partitions FROM pg_inherits WHERE inhparent = 'orders_big_daily'::regclass;
-- partitions
--       1096

-- One day, where daily partitions should shine:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big_daily WHERE orderDate = '2025-06-15';
--                                                                     QUERY PLAN
-- Aggregate  (cost=152.65..152.66 rows=1 width=40) (actual time=0.662..0.662 rows=1.00 loops=1)
--   Buffers: shared hit=58 read=4
--   ->  Seq Scan on orders_big_daily_20250615 orders_big_daily  (cost=0.00..126.75 rows=5180 width=6) (actual time=0.064..0.427 rows=5180.00 loops=1)
--         Filter: (orderdate = '2025-06-15'::date)
--         Buffers: shared hit=58 read=4
-- Planning:
--   Buffers: shared hit=42 read=10
-- Planning Time: 1.497 ms
-- Execution Time: 0.675 ms
-- One partition of 1,096, a few dozen pages. Good.
-- Now Nane's orders, no date filter -- daily vs yearly:
EXPLAIN (ANALYZE, BUFFERS, SUMMARY)
SELECT count(*), sum(orderTotal) FROM orders_big_daily WHERE customerID = 4242;
--                                                                        QUERY PLAN
-- Aggregate  (cost=122775.01..122775.02 rows=1 width=40) (actual time=260.008..260.134 rows=1.00 loops=1)
--   Buffers: shared read=60264 written=11758
--   ->  Append  (cost=0.00..122769.51 rows=1101 width=6) (actual time=4.209..260.067 rows=97.00 loops=1)
-- ...   (4385 more lines)
-- Planning:
--   Buffers: shared hit=8768 dirtied=748
-- Planning Time: 12.810 ms
-- Execution Time: 261.375 ms
EXPLAIN (ANALYZE, BUFFERS, SUMMARY)
SELECT count(*), sum(orderTotal) FROM orders_big_part WHERE customerID = 4242;
--                                                                      QUERY PLAN
-- Aggregate  (cost=122242.10..122242.11 rows=1 width=40) (actual time=128.483..128.486 rows=1.00 loops=1)
--   Buffers: shared read=59740 dirtied=1
--   ->  Append  (cost=0.00..122241.57 rows=105 width=6) (actual time=1.761..128.463 rows=97.00 loops=1)
-- ...   (13 more lines)
-- Planning:
--   Buffers: shared hit=139 read=32 dirtied=2
-- Planning Time: 0.403 ms
-- Execution Time: 128.506 ms
-- With 1,096 partitions, a query that can't prune plans 1,096 scans
-- (the plan is thousands of lines long) and runs them one after
-- another. Planning Time and Execution Time are both several times
-- the yearly table's (notes Part 9 for the medians). What we measured,
-- not a law: here, daily partitions made the one-day query faster and
-- the query without a date filter slower. Choose partitions that match how you
-- filter, and keep their number modest.
DROP TABLE orders_big_daily;

-- ---- 9.8 Deleting old data: DROP a partition ----
-- "Delete everything from 2023" on the plain table -- measured inside
-- a transaction that we roll back (Part 1.6), so nothing is lost:
BEGIN;
EXPLAIN (ANALYZE, BUFFERS)
DELETE FROM orders_big WHERE orderDate < '2024-01-01';
--                                                           QUERY PLAN
-- Delete on orders_big  (cost=0.00..122239.51 rows=0 width=0) (actual time=625.643..625.643 rows=0.00 loops=1)
--   Buffers: shared hit=1387848 read=59740 dirtied=16386 written=2616
--   ->  Seq Scan on orders_big  (cost=0.00..122239.51 rows=1384928 width=6) (actual time=8.776..232.446 rows=1371464.00 loops=1)
--         Filter: (orderdate < '2024-01-01'::date)
--         Rows Removed by Filter: 3628536
--         Buffers: shared read=59739 written=2616
-- Planning:
--   Buffers: shared hit=87 read=8
-- Planning Time: 0.129 ms
-- Execution Time: 625.706 ms
ROLLBACK;
-- 1,371,464 rows deleted one by one: every page of 2023 is visited
-- and changed, and a real DELETE leaves dead rows for VACUUM to clean
-- up afterwards. Even rolled back, it left work behind: the deleted
-- rows' pages lost their "all-visible" mark (Part 4.5), so we VACUUM
-- to put orders_big back the way it was. ROLLBACK undoes the data,
-- not the work.
VACUUM orders_big;
-- On the partitioned table, the same deletion is a catalog change:
DROP TABLE orders_big_part_2023;
SELECT tableoid::regclass AS partition, count(*) AS rows
FROM orders_big_part
GROUP BY tableoid
ORDER BY partition;
--      partition       |  rows
-- orders_big_part_2024 | 1733359
-- orders_big_part_2025 | 1895177
-- 2023 is gone: no rows deleted one by one, no VACUUM needed. This
-- is the main reason large time-based tables are partitioned. (ALTER
-- TABLE ... DETACH PARTITION keeps the old year as a table of its own
-- -- to archive it first.)
SELECT count(*) AS rows_left FROM orders_big_part;
-- rows_left
--   3628536
-- 1,733,359 + 1,895,177. And orders_big still has its 5,000,000:
SELECT count(*) AS orders_big_rows FROM orders_big;
-- orders_big_rows
--         5000000

-- ---- 9.9 The same idea, next lectures ----
-- Parquet files and lakehouse tables (next lectures) partition by
-- folder: .../orderDate_year=2025/part-0.parquet. A query engine
-- skips the folders a filter rules out -- the same pruning, with the
-- same trap: filter on the partition column itself, or it reads
-- everything.
DROP TABLE orders_big_part;
