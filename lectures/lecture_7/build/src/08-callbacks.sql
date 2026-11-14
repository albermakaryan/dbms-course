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
-- =>
SELECT e.employeeID, e.firstName, e.lastName
FROM employees e
WHERE NOT EXISTS (SELECT 1 FROM orders o
                  WHERE o.employeeID = e.employeeID AND o.status = 'cancelled');
-- =>
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
-- =>
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM customers_big c
LEFT JOIN orders_big o ON o.customerID = c.customerID AND o.status = 'cancelled'
WHERE o.customerID IS NULL;
-- =>
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
-- =>
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
-- =>
-- "SubPlan" without "hashed": for EACH of the 50,000 customers, scan
-- the stored list of ~970,000 values until a match. Read the top
-- cost: over 3 billion. The NOT EXISTS version:
EXPLAIN
SELECT count(*) FROM customers_big c
WHERE NOT EXISTS (SELECT 1 FROM orders_big o
                  WHERE o.customerID = c.customerID AND o.orderDate >= '2025-07-01');
-- =>
-- About 137,000: over 20,000 times cheaper, by the planner's own
-- estimate. Don't run the NOT IN on all 50,000 customers -- it takes
-- minutes. On the first 100 customers only:
EXPLAIN ANALYZE
SELECT count(*) FROM customers_big c
WHERE c.customerID <= 100
  AND c.customerID NOT IN (SELECT o.customerID FROM orders_big o
                           WHERE o.orderDate >= '2025-07-01');
-- =>
EXPLAIN ANALYZE
SELECT count(*) FROM customers_big c
WHERE NOT EXISTS (SELECT 1 FROM orders_big o
                  WHERE o.customerID = c.customerID AND o.orderDate >= '2025-07-01');
-- =>
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
-- =>
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
-- =>
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
-- =>
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
-- =>
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
-- =>
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
-- =>
-- So "which method is fastest" has no answer without "with which
-- index": LATERAL needs the index and is excellent with it; the
-- whole-table methods do better with a sort. Measure on your data.

-- Same answer, whatever the plan? LATERAL (with index) vs DISTINCT ON
-- (saved before the index), EXCEPT both ways:
SELECT (SELECT count(*) FROM latest_sorted)  AS rows_sorted,
       (SELECT count(*) FROM latest_lateral) AS rows_lateral,
       (SELECT count(*) FROM (SELECT * FROM latest_sorted EXCEPT SELECT * FROM latest_lateral) a) AS sorted_not_lateral,
       (SELECT count(*) FROM (SELECT * FROM latest_lateral EXCEPT SELECT * FROM latest_sorted) b) AS lateral_not_sorted;
-- =>
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
-- =>
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
-- =>

-- Merge Join: both sides already sorted on the join key -- here both
-- come out of an index in customerID order -- so walk them side by
-- side, like merging two sorted lists.
EXPLAIN ANALYZE
SELECT c.customerID, c.city, t.orders
FROM customers_big c
JOIN (SELECT customerID, count(*) AS orders FROM orders_big GROUP BY customerID) AS t
  ON t.customerID = c.customerID
ORDER BY c.customerID;
-- =>
-- You don't choose the join method; the planner does, from the
-- estimated row counts (Part 3) and the indexes available. Read which
-- one it picked, and check its row estimates.

-- Clean up: leave orders_big with its primary key only.
DROP INDEX orders_big_customerid_idx;
