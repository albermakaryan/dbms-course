-- ============================================================
-- Lecture 4 — Joins, step 15: GROUP BY column order doesn't matter
-- Notes: Part 4.14 — clearing up a common misconception
-- Run after steps/00-setup.sql. Read-only: safe to re-run.
--
-- A group is defined by the COMBINATION of values in the listed
-- columns. The order you list them in changes nothing.
-- ============================================================


-- ---- 1. Revenue per city and category, grouped city first ----
SELECT c.city, p.category, sum(i.lineTotal) AS revenue
FROM orders o
JOIN customers   c ON c.customerID = o.customerID
JOIN order_items i ON i.orderID    = o.orderID
JOIN products    p ON p.productID  = i.productID
GROUP BY c.city, p.category
ORDER BY c.city, p.category;


-- ---- 2. Prove it: subtract the category-first version ----
SELECT c.city, p.category, sum(i.lineTotal) AS revenue
FROM orders o
JOIN customers   c ON c.customerID = o.customerID
JOIN order_items i ON i.orderID    = o.orderID
JOIN products    p ON p.productID  = i.productID
GROUP BY c.city, p.category
EXCEPT
SELECT c.city, p.category, sum(i.lineTotal) AS revenue
FROM orders o
JOIN customers   c ON c.customerID = o.customerID
JOIN order_items i ON i.orderID    = o.orderID
JOIN products    p ON p.productID  = i.productID
GROUP BY p.category, c.city;
-- An empty result means: the same groups, the same totals.
-- (The same EXCEPT trick as step 14 — a check you can reuse anywhere.)


-- ---- Where to look instead ----
-- The order of the OUTPUT rows is decided by ORDER BY, never by
-- GROUP BY. And if a total looks wrong, GROUP BY column order is not
-- the place to look — check for a fan-out first (step 11).
