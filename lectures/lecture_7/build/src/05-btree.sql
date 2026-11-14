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
-- =>

-- ---- 5.2 After: CREATE INDEX ----
CREATE INDEX orders_big_customerid_idx ON orders_big (customerID);
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_big WHERE customerID = 4242;
-- =>
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
-- =>
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
-- =>
TRUNCATE orders_load;

CREATE INDEX ON orders_load (customerID);
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO orders_load SELECT * FROM orders_big WHERE orderID <= 1000000;
-- =>
TRUNCATE orders_load;

CREATE INDEX ON orders_load (orderDate);
CREATE INDEX ON orders_load (status);
CREATE INDEX ON orders_load (employeeID);
CREATE INDEX ON orders_load (orderTotal);
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO orders_load SELECT * FROM orders_big WHERE orderID <= 1000000;
-- =>
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
-- =>
-- Five indexes are about as big as the table they index.
DROP TABLE orders_load;

-- ---- 5.5 ORDER BY ... LIMIT: an index is already sorted ----
-- "The ten biggest orders ever":
EXPLAIN (ANALYZE, BUFFERS)
SELECT orderID, orderDate, orderTotal FROM orders_big ORDER BY orderTotal DESC, orderID LIMIT 10;
-- =>
-- Without an index on orderTotal: read all 5 million rows, keep the
-- top 10 in memory ("top-N heapsort").
CREATE INDEX orders_big_ordertotal_idx ON orders_big (orderTotal DESC, orderID);
EXPLAIN (ANALYZE, BUFFERS)
SELECT orderID, orderDate, orderTotal FROM orders_big ORDER BY orderTotal DESC, orderID LIMIT 10;
-- =>
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
-- =>
-- Two indexes in one plan: the UNIQUE constraint on email (a
-- constraint is enforced by an index) finds 1 customer; the customerID
-- index finds her 97 orders. Nested Loop = "for each row on the
-- outside (1 customer), look up the inside (her orders)" -- cheap when
-- the outside is small and the inside has an index. (Part 8.4: the
-- other join methods.)

-- ---- 5.7 GROUP BY: sometimes ----
EXPLAIN (ANALYZE, BUFFERS)
SELECT customerID, count(*) AS orders FROM orders_big GROUP BY customerID;
-- =>
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
-- =>
RESET enable_indexscan;
RESET enable_indexonlyscan;
RESET enable_bitmapscan;

-- Clean up: leave orders_big with its primary key only.
DROP INDEX orders_big_customerid_idx, orders_big_ordertotal_idx;
