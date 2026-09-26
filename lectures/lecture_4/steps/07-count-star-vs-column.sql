-- ============================================================
-- Lecture 4 — Joins, step 7: count(*) vs count(column)
-- Notes: Part 4.6
-- Run after steps/00-setup.sql. Read-only: safe to re-run.
--
-- count(*)       counts rows that exist.
-- count(column)  counts rows where that column is NOT NULL.
-- After a LEFT JOIN the two should diverge exactly at the unmatched
-- rows. Run both, every time, right after writing an outer join.
-- ============================================================


-- ---- 1. Orders per customer, fewest first — with count(*) ----
SELECT c.firstName, c.lastName, count(*) AS orders
FROM customers c
LEFT JOIN orders o ON o.customerID = c.customerID
GROUP BY c.customerID, c.firstName, c.lastName
ORDER BY orders, c.lastName
LIMIT 4;
-- The LEFT JOIN gave Levon one row, full of NULLs. count(*) counts it.


-- ---- 2. The same query with count(o.orderID) ----
SELECT c.firstName, c.lastName, count(o.orderID) AS orders
FROM customers c
LEFT JOIN orders o ON o.customerID = c.customerID
GROUP BY c.customerID, c.firstName, c.lastName
ORDER BY orders, c.lastName
LIMIT 4;


-- ---- 3. The reflex: both counts side by side ----
SELECT count(*)          AS joined_rows,
       count(o.orderID)  AS real_matches
FROM customers c
LEFT JOIN orders o ON o.customerID = c.customerID;
-- The two counts should differ by exactly the number of unmatched
-- customers from step 6. If the gap isn't the number you expect,
-- something about the join is wrong — find out before trusting
-- anything built on top of it.
