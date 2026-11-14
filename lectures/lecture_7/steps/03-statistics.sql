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
--    relname    | rows_it_thinks | pages_it_thinks
-- customers_big |          50000 |             820
-- orders_big    |        5000083 |           59739

-- Per column (pg_stats): how many distinct values, the most common
-- values and their share, and how well the column's order matches the
-- order of the rows on disk (correlation: 1 = same order, 0 = none).
SELECT attname, n_distinct, most_common_vals, most_common_freqs, round(correlation::numeric, 3) AS correlation
FROM pg_stats
WHERE tablename = 'orders_big' AND attname IN ('status', 'channel');
-- attname | n_distinct |        most_common_vals        |       most_common_freqs        | correlation
-- channel |          2 | {in_store,online}              | {0.6694667,0.33053333}         |       0.558
-- status  |          3 | {completed,returned,cancelled} | {0.9181333,0.048666667,0.0332} |       0.845
SELECT attname, n_distinct, round(correlation::numeric, 3) AS correlation
FROM pg_stats
WHERE tablename = 'orders_big' AND attname IN ('customerid', 'orderdate', 'orderid');
--  attname   | n_distinct | correlation
-- orderid    |         -1 |       1.000
-- customerid |      47231 |       0.003
-- orderdate  |       1096 |       1.000
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
--                                                          QUERY PLAN
-- Aggregate  (cost=122655.05..122655.06 rows=1 width=8) (actual time=247.775..247.775 rows=1.00 loops=1)
--   Buffers: shared hit=94 read=59645
--   ->  Seq Scan on orders_big  (cost=0.00..122240.04 rows=166003 width=0) (actual time=0.147..243.392 rows=159902.00 loops=1)
--         Filter: ((status)::text = 'cancelled'::text)
--         Rows Removed by Filter: 4840098
--         Buffers: shared hit=94 read=59645
-- Planning:
--   Buffers: shared hit=27 read=3
-- Planning Time: 0.054 ms
-- Execution Time: 247.787 ms
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
--                                                                          QUERY PLAN
-- GroupAggregate  (cost=129088.63..129093.44 rows=4 width=47) (actual time=360.838..383.474 rows=4.00 loops=1)
--   Group Key: c.city
--   Buffers: shared hit=601508 read=60506, temp read=610 written=612
--   ->  Sort  (cost=129088.63..129089.82 rows=476 width=13) (actual time=358.341..368.476 rows=200000.00 loops=1)
--         Sort Key: c.city
--         Sort Method: external merge  Disk: 4880kB
--         Buffers: shared hit=601508 read=60506, temp read=610 written=612
--         ->  Nested Loop  (cost=0.29..129067.46 rows=476 width=13) (actual time=157.314..331.154 rows=200000.00 loops=1)
--               Buffers: shared hit=601505 read=60506
--               ->  Seq Scan on orders_big o  (cost=0.00..126889.09 rows=476 width=10) (actual time=157.284..170.928 rows=200000.00 loops=1)
--                     Filter: (orderdate >= '2026-01-01'::date)
--                     Rows Removed by Filter: 5000000
--                     Buffers: shared hit=2460 read=59551
--               ->  Index Scan using customers_big_pkey on customers_big c  (cost=0.29..4.58 rows=1 width=11) (actual time=0.001..0.001 rows=1.00 loops=200000)
--                     Index Cond: (customerid = o.customerid)
--                     Index Searches: 200000
--                     Buffers: shared hit=599045 read=955
-- Planning:
--   Buffers: shared hit=162 read=9
-- Planning Time: 0.324 ms
-- Execution Time: 384.158 ms
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
--                                                                QUERY PLAN
-- HashAggregate  (cost=131102.01..131102.06 rows=4 width=47) (actual time=218.817..218.821 rows=4.00 loops=1)
--   Group Key: c.city
--   Batches: 1  Memory Usage: 32kB
--   Buffers: shared hit=3630 read=59201
--   ->  Hash Join  (cost=1945.00..129516.35 rows=211421 width=13) (actual time=165.761..197.953 rows=200000.00 loops=1)
--         Hash Cond: (o.customerid = c.customerid)
--         Buffers: shared hit=3630 read=59201
--         ->  Seq Scan on orders_big o  (cost=0.00..127016.33 rows=211421 width=10) (actual time=158.974..169.782 rows=200000.00 loops=1)
--               Filter: (orderdate >= '2026-01-01'::date)
--               Rows Removed by Filter: 5000000
--               Buffers: shared hit=2810 read=59201
--         ->  Hash  (cost=1320.00..1320.00 rows=50000 width=11) (actual time=6.748..6.749 rows=50000.00 loops=1)
--               Buckets: 65536  Batches: 1  Memory Usage: 2681kB
--               Buffers: shared hit=820
--               ->  Seq Scan on customers_big c  (cost=0.00..1320.00 rows=50000 width=11) (actual time=0.007..2.505 rows=50000.00 loops=1)
--                     Buffers: shared hit=820
-- Planning:
--   Buffers: shared hit=38
-- Planning Time: 0.128 ms
-- Execution Time: 218.849 ms
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
--  rows   | last_date
-- 5000000 | 2025-12-31
