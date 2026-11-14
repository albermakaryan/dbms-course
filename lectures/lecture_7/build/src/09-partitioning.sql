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
-- =>
SELECT (SELECT count(*) FROM orders_big_part) AS partitioned,
       (SELECT count(*) FROM orders_big)      AS unpartitioned;
-- =>
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
-- =>
-- 36 months, 0 and 0.

-- ---- 9.3 Partition pruning ----
-- June 2025, from both tables (neither has an index on orderDate):
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE orderDate >= '2025-06-01' AND orderDate < '2025-07-01';
-- =>
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big_part
WHERE orderDate >= '2025-06-01' AND orderDate < '2025-07-01';
-- =>
-- One partition in the plan: orders_big_part_2025. 2023 and 2024
-- aren't there at all -- the planner proved from the partition bounds
-- that they can't hold June 2025. About 38% of the pages, same answer.

-- ---- 9.4 THE TRAP: a filter the planner can't prune with ----
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big_part
WHERE extract(year FROM orderDate) = 2025;
-- =>
-- WRONG PLAN: all three partitions (Append with three Seq Scans). The
-- 2023 and 2024 scans return 0 rows -- after reading every page. The
-- bounds are on orderDate, not on extract(year FROM orderDate) (Part
-- 7.1 again). FIX: a range on the key itself.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big_part
WHERE orderDate >= '2025-01-01' AND orderDate < '2026-01-01';
-- =>
-- One partition. And with no filter on orderDate at all -- "Nane's
-- orders" -- every partition, every time:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big_part WHERE customerID = 4242;
-- =>
-- Partitioning by date helps only queries that filter on date.

-- ---- 9.5 THE TRAP: a row with no partition ----
-- An order dated 2026 arrives (or a typo: 2205 instead of 2025).
-- Error on purpose:
INSERT INTO orders_big_part VALUES
    (5000001, 4242, NULL, '2026-01-02', '10:00', 'online', 'card', 'completed', NULL, NULL, 99.00);
-- =>
-- A loud error -- the good kind. The usual "fix" is a DEFAULT
-- partition, which takes every row that fits nowhere else:
CREATE TABLE orders_big_part_default PARTITION OF orders_big_part DEFAULT;
INSERT INTO orders_big_part VALUES
    (5000001, 4242, NULL, '2026-01-02', '10:00', 'online', 'card', 'completed', NULL, NULL, 99.00);
SELECT tableoid::regclass AS partition, orderID, orderDate
FROM orders_big_part
WHERE orderID = 5000001;
-- =>
-- Accepted, silently, into orders_big_part_default. Every wrong date
-- will collect there now, without a word. And when 2026 comes and you
-- add its partition -- error on purpose:
CREATE TABLE orders_big_part_2026 PARTITION OF orders_big_part
    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
-- =>
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
-- =>

-- ---- 9.6 THE TRAP: unique means unique per partition ----
-- orders_big has PRIMARY KEY (orderID). Error on purpose:
ALTER TABLE orders_big_part ADD PRIMARY KEY (orderID);
-- =>
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
-- =>
-- WRONG: two orders numbered 5000001, and the "primary key" allowed
-- it: (5000001, 2025-12-31) and (5000001, 2026-01-02) are different
-- pairs. No error. PostgreSQL has no index that spans partitions, so
-- it can't promise orderID is unique across them. FIX: generate
-- orderIDs from one sequence (an IDENTITY column) so duplicates can't
-- be made -- and check: count(*) = count(DISTINCT orderID).
SELECT count(*) AS rows, count(DISTINCT orderID) AS distinct_ids FROM orders_big_part;
-- =>
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
-- =>

-- One day, where daily partitions should shine:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big_daily WHERE orderDate = '2025-06-15';
-- =>
-- One partition of 1,096, a few dozen pages. Good.
-- Now Nane's orders, no date filter -- daily vs yearly:
EXPLAIN (ANALYZE, BUFFERS, SUMMARY)
SELECT count(*), sum(orderTotal) FROM orders_big_daily WHERE customerID = 4242;
-- =>3,4
EXPLAIN (ANALYZE, BUFFERS, SUMMARY)
SELECT count(*), sum(orderTotal) FROM orders_big_part WHERE customerID = 4242;
-- =>3,4
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
-- =>
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
-- =>
-- 2023 is gone: no rows deleted one by one, no VACUUM needed. This
-- is the main reason large time-based tables are partitioned. (ALTER
-- TABLE ... DETACH PARTITION keeps the old year as a table of its own
-- -- to archive it first.)
SELECT count(*) AS rows_left FROM orders_big_part;
-- =>
-- 1,733,359 + 1,895,177. And orders_big still has its 5,000,000:
SELECT count(*) AS orders_big_rows FROM orders_big;
-- =>

-- ---- 9.9 The same idea, next lectures ----
-- Parquet files and lakehouse tables (next lectures) partition by
-- folder: .../orderDate_year=2025/part-0.parquet. A query engine
-- skips the folders a filter rules out -- the same pruning, with the
-- same trap: filter on the partition column itself, or it reads
-- everything.
DROP TABLE orders_big_part;
