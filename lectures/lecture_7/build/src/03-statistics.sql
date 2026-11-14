-- ============================================================
-- Lecture 7 — Part 3: Statistics and estimates
-- Run after Part 1.
--
-- The planner never looks at the data while planning. It picks a plan
-- from STATISTICS: a small summary of each table that ANALYZE builds
-- from a random sample of rows. Wrong statistics, wrong plan -- and
-- no error.
-- ============================================================

-- ---- 3.1 What the planner knows ----
-- Table size (pg_class), as of the last VACUUM or ANALYZE:
SELECT relname, reltuples::bigint AS rows_it_thinks, relpages AS pages_it_thinks
FROM pg_class
WHERE relname IN ('orders_big', 'customers_big');
-- =>

-- Per column (pg_stats): how many distinct values, the most common
-- values and their share, and how well the column's order matches the
-- order of the rows on disk (correlation: 1 = same order, 0 = none).
SELECT attname, n_distinct, most_common_vals, most_common_freqs, round(correlation::numeric, 3) AS correlation
FROM pg_stats
WHERE tablename = 'orders_big' AND attname IN ('status', 'channel');
-- =>
SELECT attname, n_distinct, round(correlation::numeric, 3) AS correlation
FROM pg_stats
WHERE tablename = 'orders_big' AND attname IN ('customerid', 'orderdate', 'orderid');
-- =>
-- status: three values, about 92 / 5 / 3 percent. customerID: about
-- 48,000 distinct values, so "one customer" means about 104 rows, and
-- it has nothing to do with where a row sits on disk (correlation
-- about 0). orderDate and orderID: correlation 1 -- the rows were
-- written in date order. Part 4 shows why that matters.
-- The numbers come from a random sample (30,000 rows here), so yours
-- differ a little in the last digits. A negative n_distinct means "a
-- fraction of the rows": -1 = every row is different.

-- ---- 3.2 Estimated vs actual ----
EXPLAIN ANALYZE
SELECT count(*) FROM orders_big WHERE status = 'cancelled';
-- =>
-- Estimated vs actual rows on the Seq Scan: close, because status is
-- in the most-common-values list. When estimates are this close, the
-- plan is chosen on true numbers.

-- ---- 3.3 THE TRAP: a bulk load without ANALYZE ----
-- January 2026 arrives: 200,000 new orders, loaded in one go.
-- (autovacuum is off for orders_big -- see Part 0 -- so nothing will
-- quietly ANALYZE it for us. In real life, autovacuum would get to it
-- eventually; your query might run before it does.)
SELECT setseed(0.7);
INSERT INTO orders_big
SELECT 5000000 + i,
       c + (c - 1) / 24,
       CASE WHEN online THEN NULL ELSE 1 + floor(random() * 8)::int END,
       DATE '2026-01-01' + floor(random() * 31)::int,
       TIME '08:00' + floor(random() * 50400) * INTERVAL '1 second',
       CASE WHEN online THEN 'online' ELSE 'in_store' END,
       'card',
       'completed',
       NULL,
       NULL,
       round((15 + 2500 * random() ^ 3)::numeric, 2)
FROM (SELECT i, 1 + floor(random() * 48000)::int AS c, random() < 0.33 AS online
      FROM generate_series(1, 200000) AS i) AS s;

-- The first report on the new month: January's orders by city.
-- Predict, then run: how many rows will the planner EXPECT for
-- orderDate >= '2026-01-01'?
EXPLAIN ANALYZE
SELECT c.city, count(*) AS orders, sum(o.orderTotal) AS revenue
FROM orders_big o
JOIN customers_big c ON c.customerID = o.customerID
WHERE o.orderDate >= '2026-01-01'
GROUP BY c.city;
-- =>
-- WRONG PLAN, right answer. Read the Seq Scan line: the planner
-- expected a few hundred January rows; there are 200,000. Its
-- statistics end on 2025-12-31 -- it has never seen 2026. Everything
-- above that node was chosen for a few hundred rows:
-- * Nested Loop: for EACH January order, look up its customer through
--   the primary key -- 200,000 separate lookups (loops=200000)
-- * Sort to group by city, with "external merge Disk": the sort was
--   sized for a few hundred rows and spilled to a temporary file
-- No error, and the result is correct. It's just the wrong plan.

-- ---- 3.4 FIX: ANALYZE, then the same query ----
ANALYZE orders_big;
EXPLAIN ANALYZE
SELECT c.city, count(*) AS orders, sum(o.orderTotal) AS revenue
FROM orders_big o
JOIN customers_big c ON c.customerID = o.customerID
WHERE o.orderDate >= '2026-01-01'
GROUP BY c.city;
-- =>
-- Now the estimate is about 200,000 and the plan changes shape:
-- * Hash Join: read the 50,000 customers ONCE into a hash table in
--   memory, then match each January order against it
-- * HashAggregate: group in memory, 4 groups, no disk
-- Same four rows. Compare the Buffers lines: the nested loop touched
-- about ten times as many pages. (Median timings: notes, Part 3.)

-- ---- 3.5 The rule of thumb ----
-- In any slow plan, look first for the node where estimated rows and
-- actual rows differ by a factor of 10 or more -- usually the lowest
-- such node. Every decision above it was made for the wrong number.
-- After a bulk load or a big UPDATE / DELETE: run ANALYZE.

-- Put orders_big back to its 5,000,000 rows for the rest of the lecture.
DELETE FROM orders_big WHERE orderID > 5000000;
VACUUM ANALYZE orders_big;
SELECT count(*) AS rows, max(orderDate) AS last_date FROM orders_big;
-- =>
