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
-- Every order has exactly one customer, so this keeps one row per order:
SELECT count(*)
FROM orders o
JOIN customers c ON c.customerID = o.customerID;


-- ---- 2. Joining the LINES changes what a row is ----
-- Products don't live on the order any more: an order can hold several,
-- one row each in order_items. To see them, go through the lines:
-- orders -> order_items -> products.
SELECT o.orderID, o.orderDate,
       c.firstName || ' ' || c.lastName AS customer,
       p.productName, i.quantity, i.lineTotal,
       o.orderTotal
FROM orders o
JOIN customers   c ON c.customerID = o.customerID
JOIN order_items i ON i.orderID    = o.orderID
JOIN products    p ON p.productID  = i.productID
WHERE o.orderID IN (1001, 1009)
ORDER BY o.orderID, p.productName;
-- Order 1001 has one line; order 1009 has three. Look at orderTotal:
-- 1009's whole total sits on EVERY one of its lines, while lineTotal is
-- each line's own share. Remember that for step 11.

-- Guess first: there are 600 orders. How many rows does the full join give?
SELECT count(*)
FROM orders o
JOIN customers   c ON c.customerID = o.customerID
JOIN order_items i ON i.orderID    = o.orderID
JOIN products    p ON p.productID  = i.productID;
-- Nothing was lost: one row per LINE. Every join answers "one row per
-- what?", and joining a one-to-many table changes the answer.


-- ---- 3. Add employees: where did 181 orders go? ----
-- Back to one row per order. Guess first: how many rows now?
SELECT count(*)
FROM orders o
JOIN customers c ON c.customerID = o.customerID
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


-- ---- 4. Why that matters: a real sum over the wrong rows ----
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
-- 100,222.48 is a real sum, correctly computed — over a silently
-- incomplete set of rows. 56,855.93 of web-shop revenue vanished.
-- That's not a bug in PostgreSQL; it's the definition of inner join.
-- It's just invisible unless you go looking. Step 5 shows the fix.
