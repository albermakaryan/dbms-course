-- ============================================================
-- Lecture 4 — Joins, step 2: INNER JOIN keeps only pairs that match
-- Notes: Part 4.2
-- Run after steps/00-setup.sql. Read-only: safe to re-run.
--
-- A INNER JOIN B ON condition = from all possible pairs, keep only the
-- ones where the condition is true. A row on either side with no
-- partner at all simply disappears: no error, no placeholder, gone.
-- ============================================================


-- ---- 1. Each JOIN adds one more lookup ----
-- A join's result is a table, and you can join that to the next table.
SELECT o.orderID, o.orderDate,
       c.firstName || ' ' || c.lastName AS customer,
       p.productName, p.category,
       o.orderTotal
FROM orders o
JOIN customers c ON c.customerID = o.customerID
JOIN products  p ON p.productID  = o.productID
ORDER BY o.orderID
LIMIT 5;

SELECT count(*)
FROM orders o
JOIN customers c ON c.customerID = o.customerID
JOIN products  p ON p.productID  = o.productID;


-- ---- 2. Add employees: where did 181 orders go? ----
-- Guess first: there are 600 orders. How many rows now?
SELECT count(*)
FROM orders o
JOIN customers c ON c.customerID = o.customerID
JOIN products  p ON p.productID  = o.productID
JOIN employees e ON e.employeeID = o.employeeID;

-- The missing 181 are exactly the online orders. Their employeeID is
-- NULL, and NULL equals nothing, so they can't satisfy
-- o.employeeID = e.employeeID for ANY employee. An inner join drops
-- every row that can't find a partner.
SELECT count(*) FILTER (WHERE employeeID IS NULL) AS online_orders,
       count(*)                                   AS all_orders
FROM orders;

-- Drill this until it's automatic:
--   An inner join doesn't complain when rows don't match —
--   it just quietly leaves them out.


-- ---- 3. Why that matters: a real sum over the wrong rows ----
-- "Completed revenue, with the salesperson's name." Someone joined
-- employees just to have the names:
SELECT sum(o.orderTotal) AS revenue
FROM orders o
JOIN employees e ON e.employeeID = o.employeeID
WHERE o.status = 'completed';

-- The same question without the join:
SELECT sum(orderTotal) AS revenue
FROM orders
WHERE status = 'completed';
-- 93,534.71 is a real sum, correctly computed — over a silently
-- incomplete set of rows. 52,400.41 of web-shop revenue vanished.
-- That's not a bug in PostgreSQL; it's the definition of inner join.
-- It's just invisible unless you go looking. Step 5 shows the fix.
