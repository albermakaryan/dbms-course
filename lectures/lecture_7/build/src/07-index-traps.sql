-- ============================================================
-- Lecture 7 — Part 7: Traps -- the index exists but is not used
-- Run after Part 6.
--
-- Each trap returns the right rows, slowly, with a perfectly good
-- index sitting next to it. The plan is the only place it shows.
-- One reading skill for this whole Part: an index condition the index
-- can SEARCH appears as "Index Cond:". A condition checked row by row
-- appears as "Filter:" -- even when the node's name says "Index".
-- ============================================================

-- Start clean (in case you ran this Part before).
DROP INDEX IF EXISTS orders_big_orderdate_idx, orders_big_customerid_idx,
                     orders_big_month_idx, orders_big_deliverydate_idx,
                     customers_big_email_pattern_idx;
DROP TABLE IF EXISTS r_or_seq, r_or_index, r_union_all;
CREATE INDEX orders_big_orderdate_idx ON orders_big (orderDate);
CREATE INDEX orders_big_customerid_idx ON orders_big (customerID);

-- ---- 7.1 A function on the indexed column ----
-- "Revenue in June 2025", written the way people say it:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE date_trunc('month', orderDate) = '2025-06-01';
-- =>
-- WRONG PLAN: Seq Scan, the orderDate index unused. The index is
-- sorted by orderDate; it knows nothing about date_trunc(orderDate).
-- Note the estimate too: the planner has no statistics on the
-- expression, so it guesses a fixed share (0.5%) of the table --
-- 25,000 against 155,419 real rows.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE extract(year FROM orderDate) = 2025 AND extract(month FROM orderDate) = 6;
-- =>
-- Same problem, and a worse guess (0.5% of 0.5%: about 125 rows).

-- FIX 1: say it as a range on the column itself.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE orderDate >= '2025-06-01' AND orderDate < '2025-07-01';
-- =>
-- Index Scan, estimate close to the 155,419 real rows, and the same
-- answer. Use ">= first day AND < first day of NEXT month": it is
-- right for dates and for timestamps (BETWEEN ... '2025-06-30' would
-- lose June 30 after midnight on a timestamp column).

-- FIX 2: index the expression (Part 6.4). Error on purpose:
CREATE INDEX orders_big_month_idx ON orders_big (date_trunc('month', orderDate));
-- =>
-- An index may only use IMMUTABLE functions: same input, same output,
-- forever. date_trunc on a date first turns it into a timestamp WITH
-- time zone (look at the Filter in the first plan above), and that
-- result depends on the session's time zone setting. Cast to a plain
-- timestamp, and it's immutable:
CREATE INDEX orders_big_month_idx ON orders_big (date_trunc('month', orderDate::timestamp));
ANALYZE orders_big;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE date_trunc('month', orderDate::timestamp) = '2025-06-01';
-- =>
-- Works -- for queries written with exactly this expression. FIX 1
-- needs no new index and works for any range; prefer it.
DROP INDEX orders_big_month_idx;

-- ---- 7.2 A type mismatch ----
-- The app passes the customer number as a decimal:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big WHERE customerID = 4242.0;
-- =>
-- WRONG PLAN. The node is "Index Only Scan using
-- orders_big_customerid_idx" -- but there is no Index Cond, only a
-- Filter: (customerid)::numeric = 4242.0. To compare an integer with
-- a numeric, PostgreSQL converts the COLUMN, every row of it, and the
-- index on the integer can't be searched. It reads all 5 million
-- index entries (Rows Removed by Filter) to find 97.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big WHERE customerID = '4242';
-- =>
-- A quoted literal is fine: '4242' has no type yet, so it becomes an
-- integer, and the Index Cond is back.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big WHERE customerID::text = '4242';
-- =>
-- WRONG PLAN again: a cast on the column is a function on the column
-- (7.1). FIX: make the VALUE the column's type -- 4242, or
-- CAST(:param AS int) -- never cast the column.

-- ---- 7.3 LIKE: 'text%' and '%text' ----
-- A search box: the user has typed the start of an email address.
EXPLAIN (ANALYZE, BUFFERS)
SELECT customerID, email FROM customers_big WHERE email LIKE 'nane.simonyan4242%';
-- =>
-- Seq Scan, although email has a UNIQUE index. The database sorts text
-- by language rules (its collation): your database's is shown by the
-- next query. Under those rules the index's order can't be used for
-- LIKE.
SELECT datcollate FROM pg_database WHERE datname = current_database();
-- =>
-- FIX: an index built with the "pattern" operator class, which sorts
-- character by character. (If your datcollate is C, the plain index
-- already works and you'll see an Index Scan above.)
CREATE INDEX customers_big_email_pattern_idx ON customers_big (email varchar_pattern_ops);
EXPLAIN (ANALYZE, BUFFERS)
SELECT customerID, email FROM customers_big WHERE email LIKE 'nane.simonyan4242%';
-- =>
-- Index Cond: email >= 'nane.simonyan4242' AND email < 'nane.simonyan4243'
-- -- a prefix is a range of the sorted index.
-- The other end of the string:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM customers_big WHERE email LIKE '%@yahoo.com';
-- =>
-- Seq Scan, with any B-tree. A leading wildcard has no place to start
-- in a sorted list, like looking up every surname ending in "-yan" in
-- a phone book. (Searches inside text need a different index type --
-- the pg_trgm extension, beyond this lecture.)
DROP INDEX customers_big_email_pattern_idx;

-- ---- 7.4 OR across different columns ----
-- Customer service: "Nane's orders, or anything delivered on 14
-- December 2025" (the day her last order arrived).
EXPLAIN (ANALYZE, BUFFERS)
SELECT orderID, customerID, deliveryDate FROM orders_big
WHERE customerID = 4242 OR deliveryDate = '2025-12-14';
-- =>
-- WRONG PLAN: Seq Scan. customerID has an index; deliveryDate has
-- none. One index can't answer an OR: a row with deliveryDate
-- 2025-12-14 might be anywhere, so the whole table must be read anyway.
-- Save this answer before changing anything (7.6 compares it):
CREATE TEMP TABLE r_or_seq AS
SELECT orderID, customerID, deliveryDate FROM orders_big
WHERE customerID = 4242 OR deliveryDate = '2025-12-14';

-- FIX A: index the other column too.
CREATE INDEX orders_big_deliverydate_idx ON orders_big (deliveryDate);
EXPLAIN (ANALYZE, BUFFERS)
SELECT orderID, customerID, deliveryDate FROM orders_big
WHERE customerID = 4242 OR deliveryDate = '2025-12-14';
-- =>
-- BitmapOr: two bitmap index scans, one per column, combined into one
-- set of pages.
CREATE TEMP TABLE r_or_index AS
SELECT orderID, customerID, deliveryDate FROM orders_big
WHERE customerID = 4242 OR deliveryDate = '2025-12-14';

-- FIX B, the usual advice: split the OR into two queries, one per
-- column, glued with UNION -- each half can use its own index:
EXPLAIN (ANALYZE, BUFFERS)
SELECT orderID, customerID, deliveryDate FROM orders_big WHERE customerID = 4242
UNION
SELECT orderID, customerID, deliveryDate FROM orders_big WHERE deliveryDate = '2025-12-14';
-- =>
-- Two index scans, appended, then duplicates removed (HashAggregate).
-- A colleague writes UNION ALL instead, "because it skips the
-- duplicate removal, so it's faster":
CREATE TEMP TABLE r_union_all AS
SELECT orderID, customerID, deliveryDate FROM orders_big WHERE customerID = 4242
UNION ALL
SELECT orderID, customerID, deliveryDate FROM orders_big WHERE deliveryDate = '2025-12-14';

-- ---- 7.5 Low selectivity (Part 4, again) ----
-- An index on status would not change Part 4.3's verdict: 92% of the
-- rows means read the table. That one isn't a trap; it's the planner
-- being right.

-- ---- 7.6 An index changes speed, never results. Prove it. ----
-- Before the index (Seq Scan) vs after it (BitmapOr), EXCEPT both ways,
-- with the row counts:
SELECT (SELECT count(*) FROM r_or_seq)   AS rows_seq_scan,
       (SELECT count(*) FROM r_or_index) AS rows_bitmap_or,
       (SELECT count(*) FROM (SELECT * FROM r_or_seq EXCEPT SELECT * FROM r_or_index) a) AS seq_not_index,
       (SELECT count(*) FROM (SELECT * FROM r_or_index EXCEPT SELECT * FROM r_or_seq) b) AS index_not_seq;
-- =>
-- 0 and 0, same count: the index changed the plan, not the answer.

-- Now the UNION ALL "optimization", checked the same way:
SELECT (SELECT count(*) FROM r_or_seq)    AS rows_or,
       (SELECT count(*) FROM r_union_all) AS rows_union_all,
       (SELECT count(*) FROM (SELECT * FROM r_or_seq EXCEPT SELECT * FROM r_union_all) a) AS or_not_union,
       (SELECT count(*) FROM (SELECT * FROM r_union_all EXCEPT SELECT * FROM r_or_seq) b) AS union_not_or;
-- =>
-- EXCEPT says 0 and 0 -- but the counts differ by one. Order 4890168
-- is Nane's AND was delivered on 2025-12-14, so UNION ALL lists it
-- twice. EXCEPT compares SETS (Lecture 5, Part 6): duplicates vanish
-- before comparing, so it can't see this. EXCEPT ALL can:
SELECT orderID, customerID, deliveryDate FROM r_union_all
EXCEPT ALL
SELECT orderID, customerID, deliveryDate FROM r_or_seq;
-- =>
-- WRONG "optimization": it changed the answer (revenue summed over it
-- would count that order twice). FIX: UNION, which removes duplicate
-- rows -- or check every rewrite with EXCEPT ALL both ways AND
-- matching row counts.
SELECT count(*) AS rows_union FROM (
    SELECT orderID, customerID, deliveryDate FROM orders_big WHERE customerID = 4242
    UNION
    SELECT orderID, customerID, deliveryDate FROM orders_big WHERE deliveryDate = '2025-12-14'
) u;
-- =>

-- The same proof on ground truth you already know -- the small
-- orders table, with its index forced (Part 1.1's planner would never
-- use it on 8 pages):
CREATE INDEX orders_status_idx ON orders (status);
SET enable_seqscan = off;
EXPLAIN
SELECT sum(orderTotal) FROM orders WHERE status = 'completed';
-- =>
SELECT sum(orderTotal) AS completed_revenue FROM orders WHERE status = 'completed';
-- =>
RESET enable_seqscan;
DROP INDEX orders_status_idx;
-- 157,078.41 through the index -- the number from Lectures 4, 5 and 6.

-- Clean up: leave orders_big with its primary key only.
DROP INDEX orders_big_orderdate_idx, orders_big_customerid_idx, orders_big_deliverydate_idx;
DROP TABLE r_or_seq, r_or_index, r_union_all;
