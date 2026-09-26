-- ============================================================
-- Lecture 4 — Joins, step 6: the anti-join — "which X have no Y?"
-- Notes: Part 4.5 (anti-join)
-- Run after steps/00-setup.sql. Read-only: safe to re-run.
--
-- The single most useful LEFT JOIN pattern:
--     LEFT JOIN  +  WHERE right.key IS NULL
-- A real match would fill the right-hand columns. If they are NULL,
-- the left-hand row had nothing to match.
-- ============================================================


-- ---- 1. Customers who never ordered ----
SELECT c.customerID, c.firstName, c.lastName, c.signupDate
FROM customers c
LEFT JOIN orders o ON o.customerID = c.customerID
WHERE o.orderID IS NULL;


-- ---- 2. Products never ordered ----
SELECT p.productID, p.productName, p.category, p.stockQuantity
FROM products p
LEFT JOIN orders o ON o.productID = p.productID
WHERE o.orderID IS NULL;


-- ---- 3. Why test the right table's KEY? ----
-- o.orderID is orders' primary key: in a real row it can never be
-- NULL. So "o.orderID IS NULL" can only mean "no row matched".
-- Testing a column that CAN be NULL in real rows (say o.rating) would
-- also catch orders that simply have no rating — wrong answer:
SELECT count(*)
FROM customers c
LEFT JOIN orders o ON o.customerID = c.customerID
WHERE o.rating IS NULL;


-- ---- Teach it as a named pattern ----
-- "Which X have no Y" comes up constantly: customers with no orders,
-- products never sold, employees with no reports. The flat sales
-- table could never answer these — a table of sales only contains
-- things that sold.
