-- ============================================================
-- Lecture 7 — Part 6: Composite, partial, covering and expression indexes
-- Run after Part 5.
--
-- Four ways to make an index fit the query: several columns, only
-- some rows, extra columns carried along, or a computed value.
-- ============================================================

-- Start clean (in case you ran this Part before).
DROP INDEX IF EXISTS orders_big_cust_date_idx, orders_big_orderdate_idx,
                     orders_big_returned_idx, orders_big_customerid_idx,
                     orders_big_cust_incl_idx, customers_big_lower_email_idx;

-- ---- 6.1 Composite index: column order matters ----
-- Sorted by customerID first, and by orderDate within each customer --
-- like a phone book sorted by last name, then first name.
CREATE INDEX orders_big_cust_date_idx ON orders_big (customerID, orderDate);

-- (a) The first column alone:
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_big WHERE customerID = 4242;
--                                                              QUERY PLAN
-- Bitmap Heap Scan on orders_big  (cost=5.25..417.18 rows=106 width=60) (actual time=0.023..0.078 rows=97.00 loops=1)
--   Recheck Cond: (customerid = 4242)
--   Heap Blocks: exact=97
--   Buffers: shared hit=97 read=3
--   ->  Bitmap Index Scan on orders_big_cust_date_idx  (cost=0.00..5.23 rows=106 width=0) (actual time=0.014..0.014 rows=97.00 loops=1)
--         Index Cond: (customerid = 4242)
--         Index Searches: 1
--         Buffers: shared read=3
-- Planning:
--   Buffers: shared hit=67 read=9 dirtied=1
-- Planning Time: 0.180 ms
-- Execution Time: 0.103 ms
-- (b) Both columns:
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_big WHERE customerID = 4242 AND orderDate >= '2025-01-01';
--                                                              QUERY PLAN
-- Bitmap Heap Scan on orders_big  (cost=4.84..162.34 rows=40 width=60) (actual time=0.008..0.022 rows=43.00 loops=1)
--   Recheck Cond: ((customerid = 4242) AND (orderdate >= '2025-01-01'::date))
--   Heap Blocks: exact=43
--   Buffers: shared hit=46
--   ->  Bitmap Index Scan on orders_big_cust_date_idx  (cost=0.00..4.83 rows=40 width=0) (actual time=0.004..0.004 rows=43.00 loops=1)
--         Index Cond: ((customerid = 4242) AND (orderdate >= '2025-01-01'::date))
--         Index Searches: 1
--         Buffers: shared hit=3
-- Planning:
--   Buffers: shared hit=8
-- Planning Time: 0.027 ms
-- Execution Time: 0.026 ms
-- (a) and (b): 3 index pages each. In (b) BOTH conditions are in the
-- Index Cond, so only 43 table pages are read instead of 97.

-- (c) The second column alone. Predict, then run:
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_big WHERE orderDate = '2025-12-01';
--                                                                   QUERY PLAN
-- Bitmap Heap Scan on orders_big  (cost=91827.53..105484.66 rows=4407 width=60) (actual time=79.193..79.599 rows=5341.00 loops=1)
--   Recheck Cond: (orderdate = '2025-12-01'::date)
--   Heap Blocks: exact=64
--   Buffers: shared hit=8 read=13595
--   ->  Bitmap Index Scan on orders_big_cust_date_idx  (cost=0.00..91826.43 rows=4407 width=0) (actual time=79.053..79.053 rows=5341.00 loops=1)
--         Index Cond: (orderdate = '2025-12-01'::date)
--         Index Searches: 1
--         Buffers: shared hit=8 read=13531
-- Planning:
--   Buffers: shared hit=6
-- Planning Time: 0.016 ms
-- Execution Time: 79.711 ms
-- The plan NAMES the index, with orderDate in the Index Cond -- but
-- look at the Bitmap Index Scan's buffers: about 13,500 pages, the
-- WHOLE index. A phone book sorted by last name can't jump to every
-- "Anna"; you have to read every page. It's cheaper than reading the
-- table, so the planner does it, but it is not a lookup.
-- A real index on orderDate, for comparison:
CREATE INDEX orders_big_orderdate_idx ON orders_big (orderDate);
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_big WHERE orderDate = '2025-12-01';
--                                                                   QUERY PLAN
-- Index Scan using orders_big_orderdate_idx on orders_big  (cost=0.43..149.56 rows=4407 width=60) (actual time=0.013..0.348 rows=5341.00 loops=1)
--   Index Cond: (orderdate = '2025-12-01'::date)
--   Index Searches: 1
--   Buffers: shared hit=64 read=7
-- Planning:
--   Buffers: shared hit=18 read=1
-- Planning Time: 0.094 ms
-- Execution Time: 0.451 ms
-- A few dozen pages. The rule: a composite index helps a query that
-- filters on its FIRST column (or first few, from the left). A query
-- on a later column alone needs its own index.
-- (PostgreSQL 18 adds "skip scan", which can jump through a composite
-- index when the first column has few distinct values. With 48,000
-- customers it doesn't pay off here -- "Index Searches: 1" means one
-- pass through the index.)
DROP INDEX orders_big_cust_date_idx, orders_big_orderdate_idx;

-- ---- 6.2 Partial index: only the rows you ask about ----
-- The returns team asks every day about recent returns. Index only the
-- returned orders:
CREATE INDEX orders_big_returned_idx ON orders_big (orderDate) WHERE status = 'returned';
SELECT pg_size_pretty(pg_relation_size('orders_big_returned_idx')) AS partial_index_size;
-- partial_index_size
-- 1672 kB
-- About 1.7 MB. A full index on orderDate is about 34 MB (Part 4).
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE status = 'returned' AND orderDate >= '2025-12-01';
--                                                                     QUERY PLAN
-- Aggregate  (cost=306.56..306.56 rows=1 width=40) (actual time=4.680..4.681 rows=1.00 loops=1)
--   Buffers: shared hit=901 read=1064
--   ->  Index Scan using orders_big_returned_idx on orders_big  (cost=0.29..266.72 rows=7967 width=6) (actual time=0.009..3.998 rows=8062.00 loops=1)
--         Index Cond: (orderdate >= '2025-12-01'::date)
--         Index Searches: 1
--         Buffers: shared hit=901 read=1064
-- Planning:
--   Buffers: shared hit=22 read=4
-- Planning Time: 0.104 ms
-- Execution Time: 4.695 ms
-- Used: the query's WHERE contains the index's WHERE exactly.

-- The same team asks for returns AND cancellations:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE status IN ('returned', 'cancelled') AND orderDate >= '2025-12-01';
--                                                          QUERY PLAN
-- Aggregate  (cost=134809.02..134809.03 rows=1 width=40) (actual time=335.662..335.663 rows=1.00 loops=1)
--   Buffers: shared hit=4600 read=55139
--   ->  Seq Scan on orders_big  (cost=0.00..134742.99 rows=13206 width=6) (actual time=323.079..334.710 rows=13430.00 loops=1)
--         Filter: (((status)::text = ANY ('{returned,cancelled}'::text[])) AND (orderdate >= '2025-12-01'::date))
--         Rows Removed by Filter: 4986570
--         Buffers: shared hit=4600 read=55139
-- Planning:
--   Buffers: shared hit=53 read=1
-- Planning Time: 0.144 ms
-- Execution Time: 335.675 ms
-- Not used: the index holds no cancelled orders, so it can't answer.
-- Seq Scan of the whole table. Correct, but slow, and silent.

-- A colleague "rewrites the same filter":
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE status <> 'completed' AND status <> 'cancelled' AND orderDate >= '2025-12-01';
--                                                               QUERY PLAN
-- Aggregate  (cost=147307.53..147307.54 rows=1 width=40) (actual time=252.685..252.686 rows=1.00 loops=1)
--   Buffers: shared hit=4694 read=55045
--   ->  Seq Scan on orders_big  (cost=0.00..147243.66 rows=12775 width=6) (actual time=243.804..252.120 rows=8062.00 loops=1)
--         Filter: (((status)::text <> 'completed'::text) AND ((status)::text <> 'cancelled'::text) AND (orderdate >= '2025-12-01'::date))
--         Rows Removed by Filter: 4991938
--         Buffers: shared hit=4694 read=55045
-- Planning:
--   Buffers: shared hit=5
-- Planning Time: 0.079 ms
-- Execution Time: 252.700 ms
-- Not used either -- even though, with the CHECK constraint, "not
-- completed and not cancelled" can only mean returned. The planner
-- uses a partial index only when it can PROVE, from the query's WHERE
-- alone, that every row the query needs is in the index -- and it
-- doesn't reason through CHECK constraints for that. Write the
-- condition the index was built with.
DROP INDEX orders_big_returned_idx;

-- ---- 6.3 Covering index (INCLUDE): carry the columns you read ----
-- Nane's lifetime spending:
CREATE INDEX orders_big_customerid_idx ON orders_big (customerID);
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big WHERE customerID = 4242;
--                                                                  QUERY PLAN
-- Aggregate  (cost=417.72..417.73 rows=1 width=40) (actual time=0.092..0.092 rows=1.00 loops=1)
--   Buffers: shared hit=97 read=3
--   ->  Bitmap Heap Scan on orders_big  (cost=5.25..417.18 rows=106 width=6) (actual time=0.022..0.077 rows=97.00 loops=1)
--         Recheck Cond: (customerid = 4242)
--         Heap Blocks: exact=97
--         Buffers: shared hit=97 read=3
--         ->  Bitmap Index Scan on orders_big_customerid_idx  (cost=0.00..5.23 rows=106 width=0) (actual time=0.012..0.012 rows=97.00 loops=1)
--               Index Cond: (customerid = 4242)
--               Index Searches: 1
--               Buffers: shared read=3
-- Planning:
--   Buffers: shared hit=16 read=1
-- Planning Time: 0.092 ms
-- Execution Time: 0.106 ms
-- 3 index pages, then 97 table pages -- only to read orderTotal.
-- Carry orderTotal inside the index:
CREATE INDEX orders_big_cust_incl_idx ON orders_big (customerID) INCLUDE (orderTotal);
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big WHERE customerID = 4242;
--                                                                      QUERY PLAN
-- Aggregate  (cost=6.82..6.83 rows=1 width=40) (actual time=0.031..0.031 rows=1.00 loops=1)
--   Buffers: shared hit=2 read=3
--   ->  Index Only Scan using orders_big_cust_incl_idx on orders_big  (cost=0.43..6.29 rows=106 width=6) (actual time=0.015..0.021 rows=97.00 loops=1)
--         Index Cond: (customerid = 4242)
--         Heap Fetches: 0
--         Index Searches: 1
--         Buffers: shared hit=2 read=3
-- Planning:
--   Buffers: shared hit=18 read=1
-- Planning Time: 0.100 ms
-- Execution Time: 0.044 ms
-- Index Only Scan, Heap Fetches 0: about 5 pages instead of 100.
-- INCLUDE columns are stored in the index but not sorted on, so they
-- can't be searched -- only read. The price:
SELECT relname AS index, pg_size_pretty(pg_relation_size(oid)) AS size
FROM pg_class
WHERE relname IN ('orders_big_customerid_idx', 'orders_big_cust_incl_idx');
--           index           |  size
-- orders_big_customerid_idx | 34 MB
-- orders_big_cust_incl_idx  | 150 MB
-- More than four times bigger. With INCLUDE columns, every row needs
-- its own index entry (no deduplication -- 5.3), plus the orderTotal.
-- INCLUDE needs PostgreSQL 11 or later.
DROP INDEX orders_big_customerid_idx, orders_big_cust_incl_idx;

-- ---- 6.4 Expression index: index a computed value ----
-- At login, a customer types "Nane.Simonyan4242@Mail.ru". Emails are
-- stored in lower case, so the app compares lower case to lower case:
EXPLAIN (ANALYZE, BUFFERS)
SELECT customerID, firstName, lastName FROM customers_big
WHERE lower(email) = lower('Nane.Simonyan4242@Mail.ru');
--                                                   QUERY PLAN
-- Seq Scan on customers_big  (cost=0.00..1570.00 rows=250 width=20) (actual time=1.041..10.324 rows=1.00 loops=1)
--   Filter: (lower((email)::text) = 'nane.simonyan4242@mail.ru'::text)
--   Rows Removed by Filter: 49999
--   Buffers: shared hit=1 read=819
-- Planning:
--   Buffers: shared hit=37
-- Planning Time: 0.086 ms
-- Execution Time: 10.330 ms
-- Seq Scan over all 50,000 customers -- although email has a UNIQUE
-- index. That index holds email, not lower(email). Index the
-- expression itself:
CREATE INDEX customers_big_lower_email_idx ON customers_big (lower(email));
ANALYZE customers_big;
EXPLAIN (ANALYZE, BUFFERS)
SELECT customerID, firstName, lastName FROM customers_big
WHERE lower(email) = lower('Nane.Simonyan4242@Mail.ru');
--                                                                   QUERY PLAN
-- Index Scan using customers_big_lower_email_idx on customers_big  (cost=0.41..8.43 rows=1 width=20) (actual time=0.014..0.014 rows=1.00 loops=1)
--   Index Cond: (lower((email)::text) = 'nane.simonyan4242@mail.ru'::text)
--   Index Searches: 1
--   Buffers: shared hit=1 read=3
-- Planning:
--   Buffers: shared hit=16 read=1
-- Planning Time: 0.089 ms
-- Execution Time: 0.022 ms
-- Index Scan: a few pages. The query must use the SAME expression as
-- the index, written the same way. ANALYZE after creating an
-- expression index also gathers statistics on the expression's values.
DROP INDEX customers_big_lower_email_idx;
ANALYZE customers_big;
