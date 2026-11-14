-- ============================================================
-- Lecture 7 — Part 8: Callbacks -- checking earlier claims with plans
-- Run after Part 7.
--
-- Lectures 5 and 6 compared ways to write the same question on
-- correctness. Now: what does each one cost on 5 million rows?
-- Whatever the plans say, including the surprises.
-- ============================================================

-- Start clean (in case you ran this Part before).
DROP INDEX IF EXISTS orders_big_cust_latest_idx, orders_big_customerid_idx;
DROP TABLE IF EXISTS latest_sorted, latest_lateral;

-- ---- 8.1 NOT IN vs NOT EXISTS: correctness first (Lecture 5, 2.2) ----
-- "Salespeople who never had an order cancelled", on the small shop:
SELECT e.employeeID, e.firstName, e.lastName
FROM employees e
WHERE e.employeeID NOT IN (SELECT o.employeeID FROM orders o
                           WHERE o.status = 'cancelled');
-- employeeid | firstname | lastname
-- (0 rows)
SELECT e.employeeID, e.firstName, e.lastName
FROM employees e
WHERE NOT EXISTS (SELECT 1 FROM orders o
                  WHERE o.employeeID = e.employeeID AND o.status = 'cancelled');
-- employeeid | firstname | lastname
--          5 | Hayk      | Melikyan
-- Lecture 5's result, unchanged: NOT IN returns nothing because 5 of
-- the cancelled orders have a NULL employeeID; NOT EXISTS finds Hayk.
-- That is the main reason to choose NOT EXISTS. Now the speed.

-- ---- 8.2 What the planner turns them into ----
-- "Customers who never cancelled an order", on 50,000 customers and
-- 159,902 cancelled orders (customerID is NOT NULL, so all three
-- forms give the same answer here):
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM customers_big c
WHERE NOT EXISTS (SELECT 1 FROM orders_big o
                  WHERE o.customerID = c.customerID AND o.status = 'cancelled');
--                                                                               QUERY PLAN
-- Aggregate  (cost=126335.08..126335.09 rows=1 width=8) (actual time=288.018..288.021 rows=1.00 loops=1)
--   Buffers: shared hit=8408 read=51470
--   ->  Hash Right Anti Join  (cost=1931.29..126329.01 rows=2425 width=0) (actual time=287.147..287.909 rows=3751.00 loops=1)
--         Hash Cond: (o.customerid = c.customerid)
--         Buffers: shared hit=8408 read=51470
--         ->  Seq Scan on orders_big o  (cost=0.00..122237.86 rows=163497 width=4) (actual time=0.077..263.187 rows=159902.00 loops=1)
--               Filter: ((status)::text = 'cancelled'::text)
--               Rows Removed by Filter: 4840098
--               Buffers: shared hit=8404 read=51335
--         ->  Hash  (cost=1306.29..1306.29 rows=50000 width=4) (actual time=5.711..5.712 rows=50000.00 loops=1)
--               Buckets: 65536  Batches: 1  Memory Usage: 2270kB
--               Buffers: shared hit=4 read=135
--               ->  Index Only Scan using customers_big_pkey on customers_big c  (cost=0.29..1306.29 rows=50000 width=4) (actual time=0.012..2.870 rows=50000.00 loops=1)
--                     Heap Fetches: 0
--                     Index Searches: 1
--                     Buffers: shared hit=4 read=135
-- Planning:
--   Buffers: shared hit=75
-- Planning Time: 0.119 ms
-- Execution Time: 288.103 ms
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM customers_big c
LEFT JOIN orders_big o ON o.customerID = c.customerID AND o.status = 'cancelled'
WHERE o.customerID IS NULL;
--                                                                               QUERY PLAN
-- Aggregate  (cost=126335.08..126335.09 rows=1 width=8) (actual time=295.412..295.414 rows=1.00 loops=1)
--   Buffers: shared hit=8637 read=51241
--   ->  Hash Right Anti Join  (cost=1931.29..126329.01 rows=2425 width=0) (actual time=294.488..295.303 rows=3751.00 loops=1)
--         Hash Cond: (o.customerid = c.customerid)
--         Buffers: shared hit=8637 read=51241
--         ->  Seq Scan on orders_big o  (cost=0.00..122237.86 rows=163497 width=4) (actual time=0.043..268.464 rows=159902.00 loops=1)
--               Filter: ((status)::text = 'cancelled'::text)
--               Rows Removed by Filter: 4840098
--               Buffers: shared hit=8498 read=51241
--         ->  Hash  (cost=1306.29..1306.29 rows=50000 width=4) (actual time=4.894..4.895 rows=50000.00 loops=1)
--               Buckets: 65536  Batches: 1  Memory Usage: 2270kB
--               Buffers: shared hit=139
--               ->  Index Only Scan using customers_big_pkey on customers_big c  (cost=0.29..1306.29 rows=50000 width=4) (actual time=0.008..2.545 rows=50000.00 loops=1)
--                     Heap Fetches: 0
--                     Index Searches: 1
--                     Buffers: shared hit=139
-- Planning:
--   Buffers: shared hit=6
-- Planning Time: 0.108 ms
-- Execution Time: 295.437 ms
-- The SAME plan for both: a Hash Anti Join ("Hash Right Anti Join" on
-- PostgreSQL 16+: the hash table is built on the smaller side, the
-- customers). The planner rewrote NOT EXISTS and LEFT JOIN ... IS NULL
-- into one anti-join. How you write it doesn't matter to it.
-- (On PostgreSQL 14, the next query takes minutes: run
-- SET hash_mem_multiplier = 2.0 first, or skip it. Notes, Part 8.3.)
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM customers_big c
WHERE c.customerID NOT IN (SELECT o.customerID FROM orders_big o
                           WHERE o.status = 'cancelled');
--                                                                              QUERY PLAN
-- Aggregate  (cost=124140.39..124140.40 rows=1 width=8) (actual time=299.157..299.158 rows=1.00 loops=1)
--   Buffers: shared hit=8731 read=51147
--   ->  Index Only Scan using customers_big_pkey on customers_big c  (cost=122646.89..124077.89 rows=25000 width=0) (actual time=292.395..299.042 rows=3751.00 loops=1)
--         Filter: (NOT (ANY (customerid = (hashed SubPlan 1).col1)))
--         Rows Removed by Filter: 46249
--         Heap Fetches: 0
--         Index Searches: 1
--         Buffers: shared hit=8731 read=51147
--         SubPlan 1
--           ->  Seq Scan on orders_big o  (cost=0.00..122237.86 rows=163497 width=4) (actual time=0.166..260.541 rows=159902.00 loops=1)
--                 Filter: ((status)::text = 'cancelled'::text)
--                 Rows Removed by Filter: 4840098
--                 Buffers: shared hit=8592 read=51147
-- Planning Time: 0.066 ms
-- Execution Time: 299.310 ms
-- NOT IN is NOT turned into an anti-join (because of what NOT IN does
-- with NULLs, the planner can't). It runs the subquery once, keeps
-- its 159,902 values in a hash table in memory ("hashed SubPlan"),
-- and checks each customer against it. About as fast -- this time.

-- ---- 8.3 When NOT IN falls off a cliff ----
-- "Customers with no order in the second half of 2025" -- a churn
-- list. The subquery now returns about 970,000 rows: too many for the
-- hash table in work_mem (4 MB). Plain EXPLAIN, nothing runs:
EXPLAIN
SELECT count(*) FROM customers_big c
WHERE c.customerID NOT IN (SELECT o.customerID FROM orders_big o
                           WHERE o.orderDate >= '2025-07-01');
--                                        QUERY PLAN
-- Aggregate  (cost=3332822070.00..3332822070.01 rows=1 width=8)
--   ->  Seq Scan on customers_big c  (cost=0.00..3332822007.50 rows=25000 width=0)
--         Filter: (NOT (ANY (customerid = (SubPlan 1).col1)))
--         SubPlan 1
--           ->  Materialize  (cost=0.00..130885.50 rows=970928 width=4)
--                 ->  Seq Scan on orders_big o  (cost=0.00..122237.86 rows=970928 width=4)
--                       Filter: (orderdate >= '2025-07-01'::date)
-- "SubPlan" without "hashed": for EACH of the 50,000 customers, scan
-- the stored list of ~970,000 values until a match. Read the top
-- cost: over 3 billion. The NOT EXISTS version:
EXPLAIN
SELECT count(*) FROM customers_big c
WHERE NOT EXISTS (SELECT 1 FROM orders_big o
                  WHERE o.customerID = c.customerID AND o.orderDate >= '2025-07-01');
--                                                       QUERY PLAN
-- Aggregate  (cost=137001.60..137001.61 rows=1 width=8)
--   ->  Hash Right Anti Join  (cost=1931.29..136995.54 rows=2425 width=0)
--         Hash Cond: (o.customerid = c.customerid)
--         ->  Seq Scan on orders_big o  (cost=0.00..122237.86 rows=970928 width=4)
--               Filter: (orderdate >= '2025-07-01'::date)
--         ->  Hash  (cost=1306.29..1306.29 rows=50000 width=4)
--               ->  Index Only Scan using customers_big_pkey on customers_big c  (cost=0.29..1306.29 rows=50000 width=4)
-- About 137,000: over 20,000 times cheaper, by the planner's own
-- estimate. Don't run the NOT IN on all 50,000 customers -- it takes
-- minutes. On the first 100 customers only:
EXPLAIN ANALYZE
SELECT count(*) FROM customers_big c
WHERE c.customerID <= 100
  AND c.customerID NOT IN (SELECT o.customerID FROM orders_big o
                           WHERE o.orderDate >= '2025-07-01');
--                                                                         QUERY PLAN
-- Aggregate  (cost=6465678.24..6465678.25 rows=1 width=8) (actual time=781.279..781.280 rows=1.00 loops=1)
--   Buffers: shared hit=8689 read=51053, temp read=12639 written=1662
--   ->  Index Only Scan using customers_big_pkey on customers_big c  (cost=0.29..6465678.12 rows=48 width=0) (actual time=387.773..781.271 rows=4.00 loops=1)
--         Index Cond: (customerid <= 100)
--         Filter: (NOT (ANY (customerid = (SubPlan 1).col1)))
--         Rows Removed by Filter: 96
--         Heap Fetches: 0
--         Index Searches: 1
--         Buffers: shared hit=8689 read=51053, temp read=12639 written=1662
--         SubPlan 1
--           ->  Materialize  (cost=0.00..130885.50 rows=970928 width=4) (actual time=1.368..5.189 rows=83378.62 loops=100)
--                 Storage: Disk  Maximum Storage: 13292kB
--                 Buffers: shared hit=8686 read=51053, temp read=12639 written=1662
--                 ->  Seq Scan on orders_big o  (cost=0.00..122237.86 rows=970928 width=4) (actual time=136.713..191.597 rows=972188.00 loops=1)
--                       Filter: (orderdate >= '2025-07-01'::date)
--                       Rows Removed by Filter: 4027812
--                       Buffers: shared hit=8686 read=51053
-- Planning:
--   Buffers: shared hit=3
-- Planning Time: 0.037 ms
-- Execution Time: 782.526 ms
EXPLAIN ANALYZE
SELECT count(*) FROM customers_big c
WHERE NOT EXISTS (SELECT 1 FROM orders_big o
                  WHERE o.customerID = c.customerID AND o.orderDate >= '2025-07-01');
--                                                                               QUERY PLAN
-- Aggregate  (cost=137001.60..137001.61 rows=1 width=8) (actual time=247.446..247.448 rows=1.00 loops=1)
--   Buffers: shared hit=8919 read=50959
--   ->  Hash Right Anti Join  (cost=1931.29..136995.54 rows=2425 width=0) (actual time=246.846..247.387 rows=2000.00 loops=1)
--         Hash Cond: (o.customerid = c.customerid)
--         Buffers: shared hit=8919 read=50959
--         ->  Seq Scan on orders_big o  (cost=0.00..122237.86 rows=970928 width=4) (actual time=128.081..174.736 rows=972188.00 loops=1)
--               Filter: (orderdate >= '2025-07-01'::date)
--               Rows Removed by Filter: 4027812
--               Buffers: shared hit=8780 read=50959
--         ->  Hash  (cost=1306.29..1306.29 rows=50000 width=4) (actual time=4.600..4.601 rows=50000.00 loops=1)
--               Buckets: 65536  Batches: 1  Memory Usage: 2270kB
--               Buffers: shared hit=139
--               ->  Index Only Scan using customers_big_pkey on customers_big c  (cost=0.29..1306.29 rows=50000 width=4) (actual time=0.007..2.440 rows=50000.00 loops=1)
--                     Heap Fetches: 0
--                     Index Searches: 1
--                     Buffers: shared hit=139
-- Planning:
--   Buffers: shared hit=6
-- Planning Time: 0.107 ms
-- Execution Time: 247.469 ms
-- NOT EXISTS answers for ALL 50,000 customers in less time than NOT IN
-- needs for 100. Check the answer: 2,000 -- exactly the 2,000
-- customers who never ordered at all (Part 0: every 25th). Everyone
-- who ever ordered also ordered in late 2025.
-- Same data, same answer (no NULLs here) -- only the plan differs,
-- and only because of how the query was written. Two reasons now to
-- write NOT EXISTS: NULLs, and this cliff.

-- ---- 8.4 Top-N per group (Lecture 6, Part 4) ----
-- "Each customer's latest order", three ways. No index on customerID
-- yet. Method 1, row_number() in a CTE:
EXPLAIN (ANALYZE, BUFFERS)
WITH ranked AS (
    SELECT customerID, orderID, orderTotal,
           row_number() OVER (PARTITION BY customerID
                              ORDER BY orderDate DESC, orderID DESC) AS rn
    FROM orders_big
)
SELECT count(*), sum(orderTotal) FROM ranked WHERE rn = 1;
--                                                                    QUERY PLAN
-- Aggregate  (cost=1046265.54..1046265.55 rows=1 width=40) (actual time=1912.303..1912.304 rows=1.00 loops=1)
--   Buffers: shared hit=8880 read=50865, temp read=35432 written=35511
--   ->  Subquery Scan on ranked  (cost=871143.75..1046140.54 rows=25000 width=6) (actual time=1467.833..1909.453 rows=48000.00 loops=1)
--         Filter: (ranked.rn = 1)
--         Buffers: shared hit=8880 read=50865, temp read=35432 written=35511
--         ->  WindowAgg  (cost=871143.75..983641.68 rows=4999909 width=26) (actual time=1467.832..1907.196 rows=48000.00 loops=1)
--               Window: w1 AS (PARTITION BY orders_big.customerid ORDER BY orders_big.orderdate, orders_big.orderid ROWS UNBOUNDED PRECEDING)
--               Run Condition: (row_number() OVER w1 <= 1)
--               Storage: Memory  Maximum Storage: 17kB
--               Buffers: shared hit=8880 read=50865, temp read=35432 written=35511
--               ->  Sort  (cost=871143.72..883643.50 rows=4999909 width=18) (actual time=1467.824..1738.702 rows=5000000.00 loops=1)
--                     Sort Key: orders_big.customerid, orders_big.orderdate DESC, orders_big.orderid DESC
--                     Sort Method: external merge  Disk: 141760kB
--                     Buffers: shared hit=8880 read=50865, temp read=35432 written=35511
--                     ->  Seq Scan on orders_big  (cost=0.00..109738.09 rows=4999909 width=18) (actual time=0.140..313.628 rows=5000000.00 loops=1)
--                           Buffers: shared hit=8874 read=50865
-- Planning:
--   Buffers: shared hit=43
-- Planning Time: 0.093 ms
-- Execution Time: 1925.375 ms
-- Sort all 5 million rows by customer and date (on disk: "external
-- merge"), then number them. ("Run Condition", PostgreSQL 15+: the
-- WindowAgg stops numbering a customer after row 1.)
-- Method 3, DISTINCT ON -- the same sort, then keep the first per
-- customer. Saved, to compare with LATERAL below:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal)
FROM (SELECT DISTINCT ON (customerID) customerID, orderID, orderTotal
      FROM orders_big
      ORDER BY customerID, orderDate DESC, orderID DESC) AS t;
--                                                                 QUERY PLAN
-- Aggregate  (cost=896856.90..896856.91 rows=1 width=40) (actual time=2271.270..2271.272 rows=1.00 loops=1)
--   Buffers: shared hit=8968 read=50771, temp read=36712 written=36791
--   ->  Unique  (cost=871143.72..896143.27 rows=47575 width=18) (actual time=1703.650..2268.246 rows=48000.00 loops=1)
--         Buffers: shared hit=8968 read=50771, temp read=36712 written=36791
--         ->  Sort  (cost=871143.72..883643.50 rows=4999909 width=18) (actual time=1703.649..2115.676 rows=5000000.00 loops=1)
--               Sort Key: orders_big.customerid, orders_big.orderdate DESC, orders_big.orderid DESC
--               Sort Method: external merge  Disk: 146880kB
--               Buffers: shared hit=8968 read=50771, temp read=36712 written=36791
--               ->  Seq Scan on orders_big  (cost=0.00..109738.09 rows=4999909 width=18) (actual time=0.087..318.506 rows=5000000.00 loops=1)
--                     Buffers: shared hit=8968 read=50771
-- Planning Time: 0.047 ms
-- Execution Time: 2286.327 ms
CREATE TEMP TABLE latest_sorted AS
SELECT DISTINCT ON (customerID) customerID, orderID, orderTotal
FROM orders_big
ORDER BY customerID, orderDate DESC, orderID DESC;
-- Method 2, LATERAL ... LIMIT 1 -- plain EXPLAIN only:
EXPLAIN
SELECT count(*), sum(l.orderTotal)
FROM customers_big c
JOIN LATERAL (SELECT o.orderID, o.orderTotal
              FROM orders_big o
              WHERE o.customerID = c.customerID
              ORDER BY o.orderDate DESC, o.orderID DESC
              LIMIT 1) AS l ON true;
--                                                    QUERY PLAN
-- Aggregate  (cost=6111922056.29..6111922056.30 rows=1 width=40)
--   ->  Nested Loop  (cost=122238.68..6111921806.29 rows=50000 width=6)
--         ->  Index Only Scan using customers_big_pkey on customers_big c  (cost=0.29..1306.29 rows=50000 width=4)
--         ->  Limit  (cost=122238.39..122238.39 rows=1 width=14)
--               ->  Sort  (cost=122238.39..122238.65 rows=105 width=14)
--                     Sort Key: o.orderdate DESC, o.orderid DESC
--                     ->  Seq Scan on orders_big o  (cost=0.00..122237.86 rows=105 width=14)
--                           Filter: (customerid = c.customerid)
-- WITHOUT an index, LATERAL means: for each of 50,000 customers, scan
-- all 5 million orders. Cost: billions. Never run that.

-- Now an index that matches the question exactly: by customer, newest
-- first.
CREATE INDEX orders_big_cust_latest_idx ON orders_big (customerID, orderDate DESC, orderID DESC);
ANALYZE orders_big;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(l.orderTotal)
FROM customers_big c
JOIN LATERAL (SELECT o.orderID, o.orderTotal
              FROM orders_big o
              WHERE o.customerID = c.customerID
              ORDER BY o.orderDate DESC, o.orderID DESC
              LIMIT 1) AS l ON true;
--                                                                              QUERY PLAN
-- Aggregate  (cost=226978.31..226978.32 rows=1 width=40) (actual time=149.405..149.406 rows=1.00 loops=1)
--   Buffers: shared hit=178185 read=19954 written=36
--   ->  Nested Loop  (cost=0.72..226728.31 rows=50000 width=6) (actual time=0.024..146.318 rows=48000.00 loops=1)
--         Buffers: shared hit=178185 read=19954 written=36
--         ->  Index Only Scan using customers_big_pkey on customers_big c  (cost=0.29..1306.29 rows=50000 width=4) (actual time=0.009..2.920 rows=50000.00 loops=1)
--               Heap Fetches: 0
--               Index Searches: 1
--               Buffers: shared hit=139
--         ->  Limit  (cost=0.43..4.49 rows=1 width=14) (actual time=0.003..0.003 rows=0.96 loops=50000)
--               Buffers: shared hit=178046 read=19954 written=36
--               ->  Index Scan using orders_big_cust_latest_idx on orders_big o  (cost=0.43..422.25 rows=104 width=14) (actual time=0.003..0.003 rows=0.96 loops=50000)
--                     Index Cond: (customerid = c.customerid)
--                     Index Searches: 50000
--                     Buffers: shared hit=178046 read=19954 written=36
-- Planning:
--   Buffers: shared hit=29 read=1
-- Planning Time: 0.135 ms
-- Execution Time: 149.420 ms
-- 50,000 short index lookups, each stopping after one row (Limit,
-- loops=50000). The fastest of the three by far -- WITH this index.
CREATE TEMP TABLE latest_lateral AS
SELECT c.customerID, l.orderID, l.orderTotal
FROM customers_big c
JOIN LATERAL (SELECT o.orderID, o.orderTotal
              FROM orders_big o
              WHERE o.customerID = c.customerID
              ORDER BY o.orderDate DESC, o.orderID DESC
              LIMIT 1) AS l ON true;

-- The SURPRISE: the same index, given to DISTINCT ON.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal)
FROM (SELECT DISTINCT ON (customerID) customerID, orderID, orderTotal
      FROM orders_big
      ORDER BY customerID, orderDate DESC, orderID DESC) AS t;
--                                                                                QUERY PLAN
-- Aggregate  (cost=404091.48..404091.49 rows=1 width=40) (actual time=9775.743..9775.744 rows=1.00 loops=1)
--   Buffers: shared hit=1344170 read=3670546 written=1
--   ->  Unique  (cost=0.43..403370.44 rows=48069 width=18) (actual time=0.016..9767.333 rows=48000.00 loops=1)
--         Buffers: shared hit=1344170 read=3670546 written=1
--         ->  Index Scan using orders_big_cust_latest_idx on orders_big  (cost=0.43..390870.59 rows=4999941 width=18) (actual time=0.015..9615.212 rows=5000000.00 loops=1)
--               Index Searches: 1
--               Buffers: shared hit=1344170 read=3670546 written=1
-- Planning Time: 0.057 ms
-- Execution Time: 9775.768 ms
-- SLOWER than without the index. The planner dropped the Sort and
-- walks the whole index instead -- in customer order, so it jumps to
-- a different table page for almost every one of the 5 million rows.
-- Compare the Buffers line with the DISTINCT ON above: about 5
-- million page visits against about 60,000 pages plus a sort on disk.
-- The planner expected those pages to be in memory
-- (effective_cache_size says 4 GB); PostgreSQL's own cache is 128 MB.
-- row_number() gets the same plan:
EXPLAIN
WITH ranked AS (
    SELECT customerID, orderID, orderTotal,
           row_number() OVER (PARTITION BY customerID
                              ORDER BY orderDate DESC, orderID DESC) AS rn
    FROM orders_big
)
SELECT count(*), sum(orderTotal) FROM ranked WHERE rn = 1;
--                                                                 QUERY PLAN
-- Aggregate  (cost=553493.67..553493.68 rows=1 width=40)
--   ->  Subquery Scan on ranked  (cost=0.53..553368.67 rows=25000 width=6)
--         Filter: (ranked.rn = 1)
--         ->  WindowAgg  (cost=0.53..490869.41 rows=4999941 width=26)
--               Window: w1 AS (PARTITION BY orders_big.customerid ORDER BY orders_big.orderdate, orders_big.orderid ROWS UNBOUNDED PRECEDING)
--               Run Condition: (row_number() OVER w1 <= 1)
--               ->  Index Scan using orders_big_cust_latest_idx on orders_big  (cost=0.43..390870.59 rows=4999941 width=18)
-- So "which method is fastest" has no answer without "with which
-- index": LATERAL needs the index and is excellent with it; the
-- whole-table methods do better with a sort. Measure on your data.

-- Same answer, whatever the plan? LATERAL (with index) vs DISTINCT ON
-- (saved before the index), EXCEPT both ways:
SELECT (SELECT count(*) FROM latest_sorted)  AS rows_sorted,
       (SELECT count(*) FROM latest_lateral) AS rows_lateral,
       (SELECT count(*) FROM (SELECT * FROM latest_sorted EXCEPT SELECT * FROM latest_lateral) a) AS sorted_not_lateral,
       (SELECT count(*) FROM (SELECT * FROM latest_lateral EXCEPT SELECT * FROM latest_sorted) b) AS lateral_not_sorted;
-- rows_sorted | rows_lateral | sorted_not_lateral | lateral_not_sorted
--       48000 |        48000 |                  0 |                  0
-- 48,000 each (the inner JOIN LATERAL drops the 2,000 customers with
-- no orders, Lecture 6, 4.3), 0 and 0.
DROP INDEX orders_big_cust_latest_idx;
DROP TABLE latest_sorted, latest_lateral;

-- ---- 8.5 Join methods, in brief ----
CREATE INDEX orders_big_customerid_idx ON orders_big (customerID);
ANALYZE orders_big;

-- Nested Loop: few rows outside, an index inside.
EXPLAIN ANALYZE
SELECT o.orderID, o.orderTotal, c.city
FROM orders_big o
JOIN customers_big c ON c.customerID = o.customerID
WHERE o.orderID BETWEEN 1000001 AND 1000010;
--                                                                  QUERY PLAN
-- Nested Loop  (cost=0.72..91.71 rows=10 width=17) (actual time=0.025..0.080 rows=10.00 loops=1)
--   Buffers: shared hit=11 read=23
--   ->  Index Scan using orders_big_pkey on orders_big o  (cost=0.43..8.63 rows=10 width=14) (actual time=0.015..0.016 rows=10.00 loops=1)
--         Index Cond: ((orderid >= 1000001) AND (orderid <= 1000010))
--         Index Searches: 1
--         Buffers: shared read=4
--   ->  Index Scan using customers_big_pkey on customers_big c  (cost=0.29..8.31 rows=1 width=11) (actual time=0.006..0.006 rows=1.00 loops=10)
--         Index Cond: (customerid = o.customerid)
--         Index Searches: 10
--         Buffers: shared hit=11 read=19
-- Planning:
--   Buffers: shared hit=41 read=14
-- Planning Time: 0.218 ms
-- Execution Time: 0.092 ms
-- 10 orders; for each, one primary-key lookup in customers_big
-- (loops=10).

-- Hash Join: many rows, no useful order. Build a hash table on the
-- smaller side, stream the bigger one past it.
EXPLAIN ANALYZE
SELECT c.city, count(*) AS cancelled_orders
FROM orders_big o
JOIN customers_big c ON c.customerID = o.customerID
WHERE o.status = 'cancelled'
GROUP BY c.city;
--                                                                QUERY PLAN
-- HashAggregate  (cost=125368.98..125369.02 rows=4 width=15) (actual time=320.817..320.820 rows=4.00 loops=1)
--   Group Key: c.city
--   Batches: 1  Memory Usage: 32kB
--   Buffers: shared hit=15314 read=45245
--   ->  Hash Join  (cost=1945.00..124592.30 rows=155335 width=7) (actual time=7.288..306.405 rows=159902.00 loops=1)
--         Hash Cond: (o.customerid = c.customerid)
--         Buffers: shared hit=15314 read=45245
--         ->  Seq Scan on orders_big o  (cost=0.00..122239.51 rows=155335 width=4) (actual time=0.006..268.277 rows=159902.00 loops=1)
--               Filter: ((status)::text = 'cancelled'::text)
--               Rows Removed by Filter: 4840098
--               Buffers: shared hit=15304 read=44435
--         ->  Hash  (cost=1320.00..1320.00 rows=50000 width=11) (actual time=7.253..7.254 rows=50000.00 loops=1)
--               Buckets: 65536  Batches: 1  Memory Usage: 2681kB
--               Buffers: shared hit=10 read=810
--               ->  Seq Scan on customers_big c  (cost=0.00..1320.00 rows=50000 width=11) (actual time=0.141..3.525 rows=50000.00 loops=1)
--                     Buffers: shared hit=10 read=810
-- Planning:
--   Buffers: shared hit=17
-- Planning Time: 0.082 ms
-- Execution Time: 320.845 ms

-- Merge Join: both sides already sorted on the join key -- here both
-- come out of an index in customerID order -- so walk them side by
-- side, like merging two sorted lists.
EXPLAIN ANALYZE
SELECT c.customerID, c.city, t.orders
FROM customers_big c
JOIN (SELECT customerID, count(*) AS orders FROM orders_big GROUP BY customerID) AS t
  ON t.customerID = c.customerID
ORDER BY c.customerID;
--                                                                                 QUERY PLAN
-- Merge Join  (cost=0.72..121240.76 rows=47545 width=19) (actual time=0.028..372.609 rows=48000.00 loops=1)
--   Merge Cond: (c.customerid = orders_big.customerid)
--   Buffers: shared hit=96838 read=4466
--   ->  Index Scan using customers_big_pkey on customers_big c  (cost=0.29..2129.29 rows=50000 width=11) (actual time=0.006..4.450 rows=50000.00 loops=1)
--         Index Searches: 1
--         Buffers: shared hit=834 read=126
--   ->  GroupAggregate  (cost=0.43..117916.70 rows=47545 width=12) (actual time=0.019..361.569 rows=48000.00 loops=1)
--         Group Key: orders_big.customerid
--         Buffers: shared hit=96004 read=4340
--         ->  Index Only Scan using orders_big_customerid_idx on orders_big  (cost=0.43..92441.05 rows=5000041 width=4) (actual time=0.006..189.455 rows=5000000.00 loops=1)
--               Heap Fetches: 0
--               Index Searches: 1
--               Buffers: shared hit=96004 read=4340
-- Planning Time: 0.097 ms
-- Execution Time: 373.641 ms
-- You don't choose the join method; the planner does, from the
-- estimated row counts (Part 3) and the indexes available. Read which
-- one it picked, and check its row estimates.

-- Clean up: leave orders_big with its primary key only.
DROP INDEX orders_big_customerid_idx;
