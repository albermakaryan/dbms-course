-- ============================================================
-- Lecture 7 — Part 5: B-tree indexes, and what they cost
-- Run after Part 4.
--
-- CREATE INDEX builds a B-tree: the column's values in sorted order,
-- each with the address of its row. Finding one value takes a few
-- page reads, however big the table. The price: disk space, and extra
-- work on every INSERT, UPDATE and DELETE.
-- ============================================================

-- Start clean (in case you ran this Part before).
DROP INDEX IF EXISTS orders_big_customerid_idx, orders_big_ordertotal_idx;
DROP TABLE IF EXISTS orders_load;

-- ---- 5.1 Before: customer 4242 without an index (Part 1) ----
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_big WHERE customerID = 4242;
--                                                    QUERY PLAN
-- Seq Scan on orders_big  (cost=0.00..122242.33 rows=106 width=60) (actual time=1.943..132.068 rows=97.00 loops=1)
--   Filter: (customerid = 4242)
--   Rows Removed by Filter: 4999903
--   Buffers: shared read=59739
-- Planning:
--   Buffers: shared hit=78 read=10 dirtied=1
-- Planning Time: 0.243 ms
-- Execution Time: 132.108 ms

-- ---- 5.2 After: CREATE INDEX ----
CREATE INDEX orders_big_customerid_idx ON orders_big (customerID);
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_big WHERE customerID = 4242;
--                                                               QUERY PLAN
-- Bitmap Heap Scan on orders_big  (cost=5.25..417.18 rows=106 width=60) (actual time=0.072..0.328 rows=97.00 loops=1)
--   Recheck Cond: (customerid = 4242)
--   Heap Blocks: exact=97
--   Buffers: shared read=100
--   ->  Bitmap Index Scan on orders_big_customerid_idx  (cost=0.00..5.23 rows=106 width=0) (actual time=0.019..0.019 rows=97.00 loops=1)
--         Index Cond: (customerid = 4242)
--         Index Searches: 1
--         Buffers: shared read=3
-- Planning:
--   Buffers: shared hit=18 read=2
-- Planning Time: 0.116 ms
-- Execution Time: 0.346 ms
-- Bitmap Index Scan: 3 index pages (root, branch, leaf) find the 97
-- row addresses; Bitmap Heap Scan reads the 97 pages they're on
-- ("Heap Blocks: exact=97" -- Nane's orders are spread out, one per
-- page). About 100 pages instead of 59,739, and hundreds of times
-- faster (notes, Part 5, for the median of three runs). Same 97 rows.

-- ---- 5.3 What it costs: space ----
SELECT c.relname AS name,
       CASE c.relkind WHEN 'r' THEN 'table' ELSE 'index' END AS kind,
       pg_size_pretty(pg_relation_size(c.oid)) AS size
FROM pg_class c
WHERE c.relname IN ('orders_big', 'orders_big_pkey', 'orders_big_customerid_idx')
ORDER BY pg_relation_size(c.oid) DESC;
--           name            | kind  |  size
-- orders_big                | table | 467 MB
-- orders_big_pkey           | index | 111 MB
-- orders_big_customerid_idx | index | 34 MB
-- The primary key (5 million different orderIDs) is a quarter of the
-- table's size. The customerID index is a third of the primary key:
-- since PostgreSQL 13 a B-tree stores a repeated value once with a
-- list of its rows (deduplication), and each customer repeats about
-- 104 times.

-- ---- 5.4 What it costs: every write ----
-- Load the same 1,000,000 orders into an empty table three times:
-- with no index, with one, with five. (A copy, orders_load, so that
-- orders_big stays as it is. Times: notes Part 5, median of three.)
CREATE TABLE orders_load (LIKE orders_big) WITH (autovacuum_enabled = off);

EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO orders_load SELECT * FROM orders_big WHERE orderID <= 1000000;
--                                                                      QUERY PLAN
-- Insert on orders_load  (cost=0.43..39996.24 rows=0 width=0) (actual time=662.274..662.275 rows=0.00 loops=1)
--   Buffers: shared hit=1023940 read=14669 dirtied=11951 written=11955
--   ->  Index Scan using orders_big_pkey on orders_big  (cost=0.43..39996.24 rows=978846 width=60) (actual time=0.018..144.692 rows=1000000.00 loops=1)
--         Index Cond: (orderid <= 1000000)
--         Index Searches: 1
--         Buffers: shared hit=26 read=14669 written=2
-- Planning:
--   Buffers: shared hit=15
-- Planning Time: 0.040 ms
-- Execution Time: 662.288 ms
TRUNCATE orders_load;

CREATE INDEX ON orders_load (customerID);
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO orders_load SELECT * FROM orders_big WHERE orderID <= 1000000;
--                                                                      QUERY PLAN
-- Insert on orders_load  (cost=0.43..39996.24 rows=0 width=0) (actual time=1698.532..1698.532 rows=0.00 loops=1)
--   Buffers: shared hit=3818714 read=14684 dirtied=13144 written=13146
--   ->  Index Scan using orders_big_pkey on orders_big  (cost=0.43..39996.24 rows=978846 width=60) (actual time=0.022..124.935 rows=1000000.00 loops=1)
--         Index Cond: (orderid <= 1000000)
--         Index Searches: 1
--         Buffers: shared hit=12 read=14683 written=1
-- Planning Time: 0.047 ms
-- Execution Time: 1698.546 ms
TRUNCATE orders_load;

CREATE INDEX ON orders_load (orderDate);
CREATE INDEX ON orders_load (status);
CREATE INDEX ON orders_load (employeeID);
CREATE INDEX ON orders_load (orderTotal);
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO orders_load SELECT * FROM orders_big WHERE orderID <= 1000000;
--                                                                      QUERY PLAN
-- Insert on orders_load  (cost=0.43..39996.24 rows=0 width=0) (actual time=5206.853..5206.853 rows=0.00 loops=1)
--   Buffers: shared hit=13463096 read=14688 dirtied=19420 written=25093
--   ->  Index Scan using orders_big_pkey on orders_big  (cost=0.43..39996.24 rows=978846 width=60) (actual time=0.020..146.214 rows=1000000.00 loops=1)
--         Index Cond: (orderid <= 1000000)
--         Index Searches: 1
--         Buffers: shared hit=12 read=14683 written=2381
-- Planning Time: 0.045 ms
-- Execution Time: 5206.872 ms
-- The same million rows each time. Compare the Buffers line of the
-- ModifyTable node ("Insert on orders_load"): every index is another
-- structure to update for every row, in another place on disk.
SELECT c.relname AS name, pg_size_pretty(pg_relation_size(c.oid)) AS size
FROM pg_class c
JOIN pg_index i ON i.indexrelid = c.oid
WHERE i.indrelid = 'orders_load'::regclass
UNION ALL
SELECT 'orders_load (the table)', pg_size_pretty(pg_relation_size('orders_load'))
ORDER BY name;
--            name            |  size
-- orders_load (the table)    | 93 MB
-- orders_load_customerid_idx | 9544 kB
-- orders_load_employeeid_idx | 6336 kB
-- orders_load_orderdate_idx  | 7480 kB
-- orders_load_ordertotal_idx | 29 MB
-- orders_load_status_idx     | 6368 kB
-- Five indexes are about as big as the table they index.
DROP TABLE orders_load;

-- ---- 5.5 ORDER BY ... LIMIT: an index is already sorted ----
-- "The ten biggest orders ever":
EXPLAIN (ANALYZE, BUFFERS)
SELECT orderID, orderDate, orderTotal FROM orders_big ORDER BY orderTotal DESC, orderID LIMIT 10;
--                                                              QUERY PLAN
-- Limit  (cost=217795.61..217795.64 rows=10 width=14) (actual time=664.185..664.187 rows=10.00 loops=1)
--   Buffers: shared hit=2595 read=57144
--   ->  Sort  (cost=217795.61..230296.28 rows=5000266 width=14) (actual time=664.184..664.185 rows=10.00 loops=1)
--         Sort Key: ordertotal DESC, orderid
--         Sort Method: top-N heapsort  Memory: 25kB
--         Buffers: shared hit=2595 read=57144
--         ->  Seq Scan on orders_big  (cost=0.00..109741.66 rows=5000266 width=14) (actual time=0.212..315.601 rows=5000000.00 loops=1)
--               Buffers: shared hit=2595 read=57144
-- Planning:
--   Buffers: shared hit=8 read=4
-- Planning Time: 0.063 ms
-- Execution Time: 664.197 ms
-- Without an index on orderTotal: read all 5 million rows, keep the
-- top 10 in memory ("top-N heapsort").
CREATE INDEX orders_big_ordertotal_idx ON orders_big (orderTotal DESC, orderID);
EXPLAIN (ANALYZE, BUFFERS)
SELECT orderID, orderDate, orderTotal FROM orders_big ORDER BY orderTotal DESC, orderID LIMIT 10;
--                                                                         QUERY PLAN
-- Limit  (cost=0.43..1.21 rows=10 width=14) (actual time=0.017..0.044 rows=10.00 loops=1)
--   Buffers: shared hit=1 read=12
--   ->  Index Scan using orders_big_ordertotal_idx on orders_big  (cost=0.43..390972.41 rows=5000266 width=14) (actual time=0.016..0.043 rows=10.00 loops=1)
--         Index Searches: 1
--         Buffers: shared hit=1 read=12
-- Planning:
--   Buffers: shared hit=18 read=1 dirtied=1
-- Planning Time: 0.111 ms
-- Execution Time: 0.052 ms
-- With it: no Sort node at all. Walk the index from the top, stop
-- after 10 rows. A handful of pages instead of the whole table.

-- ---- 5.6 JOIN: an index on the join column ----
-- Customer service looks Nane up by email and lists her latest orders:
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.orderID, o.orderDate, o.status, o.orderTotal
FROM customers_big c
JOIN orders_big o ON o.customerID = c.customerID
WHERE c.email = 'nane.simonyan4242@mail.ru'
ORDER BY o.orderDate DESC
LIMIT 5;
--                                                                          QUERY PLAN
-- Limit  (cost=428.34..428.35 rows=5 width=23) (actual time=0.290..0.291 rows=5.00 loops=1)
--   Buffers: shared hit=3 read=101
--   ->  Sort  (cost=428.34..428.59 rows=100 width=23) (actual time=0.289..0.290 rows=5.00 loops=1)
--         Sort Key: o.orderdate DESC
--         Sort Method: top-N heapsort  Memory: 25kB
--         Buffers: shared hit=3 read=101
--         ->  Nested Loop  (cost=5.67..426.68 rows=100 width=23) (actual time=0.080..0.274 rows=97.00 loops=1)
--               Buffers: shared hit=3 read=101
--               ->  Index Scan using customers_big_email_key on customers_big c  (cost=0.41..8.43 rows=1 width=4) (actual time=0.016..0.017 rows=1.00 loops=1)
--                     Index Cond: ((email)::text = 'nane.simonyan4242@mail.ru'::text)
--                     Index Searches: 1
--                     Buffers: shared read=4
--               ->  Bitmap Heap Scan on orders_big o  (cost=5.25..417.18 rows=106 width=27) (actual time=0.062..0.247 rows=97.00 loops=1)
--                     Recheck Cond: (c.customerid = customerid)
--                     Heap Blocks: exact=97
--                     Buffers: shared hit=3 read=97
--                     ->  Bitmap Index Scan on orders_big_customerid_idx  (cost=0.00..5.23 rows=106 width=0) (actual time=0.009..0.009 rows=97.00 loops=1)
--                           Index Cond: (customerid = c.customerid)
--                           Index Searches: 1
--                           Buffers: shared hit=1 read=2
-- Planning:
--   Buffers: shared hit=77 read=15
-- Planning Time: 0.224 ms
-- Execution Time: 0.306 ms
-- Two indexes in one plan: the UNIQUE constraint on email (a
-- constraint is enforced by an index) finds 1 customer; the customerID
-- index finds her 97 orders. Nested Loop = "for each row on the
-- outside (1 customer), look up the inside (her orders)" -- cheap when
-- the outside is small and the inside has an index. (Part 8.4: the
-- other join methods.)

-- ---- 5.7 GROUP BY: sometimes ----
EXPLAIN (ANALYZE, BUFFERS)
SELECT customerID, count(*) AS orders FROM orders_big GROUP BY customerID;
--                                                                              QUERY PLAN
-- GroupAggregate  (cost=0.43..117919.12 rows=47337 width=12) (actual time=0.019..372.422 rows=48000.00 loops=1)
--   Group Key: customerid
--   Buffers: shared hit=96004 read=4340
--   ->  Index Only Scan using orders_big_customerid_idx on orders_big  (cost=0.43..92444.42 rows=5000266 width=4) (actual time=0.004..193.435 rows=5000000.00 loops=1)
--         Heap Fetches: 0
--         Index Searches: 1
--         Buffers: shared hit=96004 read=4340
-- Planning:
--   Buffers: shared hit=1 read=2
-- Planning Time: 0.029 ms
-- Execution Time: 373.435 ms
-- The planner reads the customerID index from start to end (Index Only
-- Scan) and gets the rows already grouped together, so GroupAggregate
-- needs no sort and no hash table. Without the index it would hash
-- all 5 million rows -- see the next query. Neither is dramatic: both
-- read everything. "Sometimes" is the honest word for GROUP BY.
SET enable_indexscan = off;
SET enable_indexonlyscan = off;
SET enable_bitmapscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT customerID, count(*) AS orders FROM orders_big GROUP BY customerID;
--                                                           QUERY PLAN
-- HashAggregate  (cost=134742.99..135216.36 rows=47337 width=12) (actual time=628.783..631.392 rows=48000.00 loops=1)
--   Group Key: customerid
--   Batches: 1  Memory Usage: 3097kB
--   Buffers: shared hit=2981 read=56758
--   ->  Seq Scan on orders_big  (cost=0.00..109741.66 rows=5000266 width=4) (actual time=0.060..158.754 rows=5000000.00 loops=1)
--         Buffers: shared hit=2981 read=56758
-- Planning Time: 0.052 ms
-- Execution Time: 632.595 ms
RESET enable_indexscan;
RESET enable_indexonlyscan;
RESET enable_bitmapscan;

-- Clean up: leave orders_big with its primary key only.
DROP INDEX orders_big_customerid_idx, orders_big_ordertotal_idx;
