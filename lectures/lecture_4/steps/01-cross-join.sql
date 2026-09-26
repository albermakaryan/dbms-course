-- ============================================================
-- Lecture 4 — Joins, step 1: CROSS JOIN, and the one idea
-- Notes: Part 4.0 and 4.1
-- Run after steps/00-setup.sql. Read-only: safe to re-run.
--
-- THE ONE IDEA, before any syntax:
--   A join is: pair every row of A with every row of B,
--   then keep the pairs you want.
--
-- Every join type in this lecture is a variation on two questions:
-- which pairs do we keep, and what do we do with the rows that found
-- no pair? CROSS JOIN is the starting point: it keeps ALL the pairs.
-- ============================================================


-- ---- 1. Every pair: the whole Cartesian product ----
-- Guess first: orders has 600 rows, customers has 30. How many rows?
SELECT count(*) FROM orders CROSS JOIN customers;
-- No order belongs to 30 customers. Almost every one of these pairs is
-- nonsense. That's the point: this is the raw material every other
-- join is carved out of.


-- ---- 2. CROSS JOIN is not a special case ----
-- PostgreSQL defines  A CROSS JOIN B  as exactly  A INNER JOIN B ON TRUE:
-- a join whose condition can never fail. The old comma syntax is the
-- same thing again. All three return the same count:
SELECT count(*) FROM orders INNER JOIN customers ON TRUE;
SELECT count(*) FROM orders, customers;


-- ---- 3. Zoom in: 3 orders × 3 customers = 9 pairs ----
-- The same product, small enough to read. Orders 1001-1003 were placed
-- by customers 2, 26 and 6, so take exactly those three customers.
SELECT o.orderID,
       o.customerID AS "order says",
       c.customerID AS "customer row",
       c.firstName, c.lastName
FROM orders o CROSS JOIN customers c
WHERE o.orderID IN (1001, 1002, 1003)
  AND c.customerID IN (2, 6, 26)
ORDER BY o.orderID, c.customerID;
-- Ask the room: which pairs are true? The ones where the number the
-- order holds equals the customer's id.


-- ---- 4. Keep only the pairs you want: add the matching condition ----
SELECT o.orderID,
       o.customerID AS "order says",
       c.customerID AS "customer row",
       c.firstName, c.lastName
FROM orders o CROSS JOIN customers c
WHERE o.orderID IN (1001, 1002, 1003)
  AND c.customerID IN (2, 6, 26)
  AND o.customerID = c.customerID
ORDER BY o.orderID;
-- That IS a join: every pair, filtered down to the pairs whose values
-- match. Nothing more mysterious than that.


-- ---- 5. The same result, written as JOIN ... ON ----
-- ON puts the matching condition next to the table it's about.
-- JOIN on its own means INNER JOIN.
SELECT o.orderID, c.firstName, c.lastName, o.orderTotal
FROM orders o
JOIN customers c ON c.customerID = o.customerID
WHERE o.orderID IN (1001, 1002, 1003)
ORDER BY o.orderID;
-- Does PostgreSQL really build 18,000 pairs and throw most away? No:
-- the planner picks a nested-loop, merge or hash join by estimated
-- cost. But every plan returns exactly what the slow "every pair, then
-- filter" method would. Think the slow way; let the database do the
-- fast one.
