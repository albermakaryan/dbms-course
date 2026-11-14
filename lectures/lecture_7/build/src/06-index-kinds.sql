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
-- =>
-- (b) Both columns:
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_big WHERE customerID = 4242 AND orderDate >= '2025-01-01';
-- =>
-- (a) and (b): 3 index pages each. In (b) BOTH conditions are in the
-- Index Cond, so only 43 table pages are read instead of 97.

-- (c) The second column alone. Predict, then run:
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_big WHERE orderDate = '2025-12-01';
-- =>
-- The plan NAMES the index, with orderDate in the Index Cond -- but
-- look at the Bitmap Index Scan's buffers: about 13,500 pages, the
-- WHOLE index. A phone book sorted by last name can't jump to every
-- "Anna"; you have to read every page. It's cheaper than reading the
-- table, so the planner does it, but it is not a lookup.
-- A real index on orderDate, for comparison:
CREATE INDEX orders_big_orderdate_idx ON orders_big (orderDate);
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_big WHERE orderDate = '2025-12-01';
-- =>
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
-- =>
-- About 1.7 MB. A full index on orderDate is about 34 MB (Part 4).
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE status = 'returned' AND orderDate >= '2025-12-01';
-- =>
-- Used: the query's WHERE contains the index's WHERE exactly.

-- The same team asks for returns AND cancellations:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE status IN ('returned', 'cancelled') AND orderDate >= '2025-12-01';
-- =>
-- Not used: the index holds no cancelled orders, so it can't answer.
-- Seq Scan of the whole table. Correct, but slow, and silent.

-- A colleague "rewrites the same filter":
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE status <> 'completed' AND status <> 'cancelled' AND orderDate >= '2025-12-01';
-- =>
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
-- =>
-- 3 index pages, then 97 table pages -- only to read orderTotal.
-- Carry orderTotal inside the index:
CREATE INDEX orders_big_cust_incl_idx ON orders_big (customerID) INCLUDE (orderTotal);
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big WHERE customerID = 4242;
-- =>
-- Index Only Scan, Heap Fetches 0: about 5 pages instead of 100.
-- INCLUDE columns are stored in the index but not sorted on, so they
-- can't be searched -- only read. The price:
SELECT relname AS index, pg_size_pretty(pg_relation_size(oid)) AS size
FROM pg_class
WHERE relname IN ('orders_big_customerid_idx', 'orders_big_cust_incl_idx');
-- =>
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
-- =>
-- Seq Scan over all 50,000 customers -- although email has a UNIQUE
-- index. That index holds email, not lower(email). Index the
-- expression itself:
CREATE INDEX customers_big_lower_email_idx ON customers_big (lower(email));
ANALYZE customers_big;
EXPLAIN (ANALYZE, BUFFERS)
SELECT customerID, firstName, lastName FROM customers_big
WHERE lower(email) = lower('Nane.Simonyan4242@Mail.ru');
-- =>
-- Index Scan: a few pages. The query must use the SAME expression as
-- the index, written the same way. ANALYZE after creating an
-- expression index also gathers statistics on the expression's values.
DROP INDEX customers_big_lower_email_idx;
ANALYZE customers_big;
