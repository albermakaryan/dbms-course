-- ============================================================
-- Lecture 5 — Part 2: Subqueries vs. JOINs
-- Run after Part 1.
-- ============================================================

-- ---- 2.1 One question, three queries ----
-- "Which products have never been ordered?" Lecture 4 answered it:
-- productID 35, Ergonomic Chair Pro. Products now live on the order
-- LINES, so every version asks order_items.

-- (a) Lecture 4's anti-join: LEFT JOIN + IS NULL
SELECT p.productID, p.productName
FROM products p
LEFT JOIN order_items i ON i.productID = p.productID
WHERE i.orderID IS NULL;
-- productid | productname
-- 35 | Ergonomic Chair Pro

-- (b) NOT IN
SELECT productID, productName
FROM products
WHERE productID NOT IN (SELECT productID FROM order_items);
-- productid | productname
-- 35 | Ergonomic Chair Pro

-- (c) NOT EXISTS
SELECT p.productID, p.productName
FROM products p
WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.productID = p.productID);
-- productid | productname
-- 35 | Ergonomic Chair Pro

-- Same answer three ways. They agree HERE because order_items.productID
-- is NOT NULL. Now ask a question where the subquery's column can be NULL.

-- ---- 2.2 The NOT IN trap (callback: Lecture 4's anti-join) ----
-- In miniature first. NOT IN (1, 2, NULL) means 5 <> 1 AND 5 <> 2 AND 5 <> NULL,
-- and 5 <> NULL is not true or false -- it's NULL (unknown).
SELECT 5 NOT IN (1, 2)       AS no_null,
       5 NOT IN (1, 2, NULL) AS with_null,
       2 NOT IN (1, 2, NULL) AS match_with_null;
-- no_null | with_null | match_with_null
-- t       |           | f
-- with_null is NULL (psql prints nothing). WHERE NULL keeps no rows.
-- A NOT IN whose list holds a NULL can never be true for anybody.

-- The real question: "Which salespeople have never had an order
-- cancelled?" -- a clean record, worth a bonus.
SELECT e.employeeID, e.firstName, e.lastName
FROM employees e
WHERE e.employeeID NOT IN (SELECT o.employeeID FROM orders o
                           WHERE o.status = 'cancelled');
-- WRONG: 0 rows. No error. "Nobody has a clean record."

-- Why: 5 of the 27 cancelled orders were online -- employeeID NULL.
SELECT count(*) AS cancelled_orders, count(employeeID) AS with_an_employee
FROM orders
WHERE status = 'cancelled';
-- cancelled_orders | with_an_employee
-- 27 |               22
-- One NULL in the list is enough. Here there are five.

-- FIX 1 -- NOT EXISTS asks "is there a matching row?", which is only
-- ever true or false:
SELECT e.employeeID, e.firstName, e.lastName
FROM employees e
WHERE NOT EXISTS (SELECT 1 FROM orders o
                  WHERE o.employeeID = e.employeeID
                    AND o.status = 'cancelled');
-- employeeid | firstname | lastname
-- 5 | Hayk      | Melikyan

-- FIX 2 -- keep NOT IN, but take the NULLs out of the list yourself:
SELECT e.employeeID, e.firstName, e.lastName
FROM employees e
WHERE e.employeeID NOT IN (SELECT o.employeeID FROM orders o
                           WHERE o.status = 'cancelled'
                             AND o.employeeID IS NOT NULL);
-- employeeid | firstname | lastname
-- 5 | Hayk      | Melikyan

-- FIX 3 -- Lecture 4's anti-join, with the status test in ON (Lecture
-- 4's WHERE-vs-ON lesson: in WHERE it would delete the NULL-padded rows):
SELECT e.employeeID, e.firstName, e.lastName
FROM employees e
LEFT JOIN orders o ON o.employeeID = e.employeeID
                  AND o.status = 'cancelled'
WHERE o.orderID IS NULL;
-- employeeid | firstname | lastname
-- 5 | Hayk      | Melikyan

-- ---- 2.3 THE CART FAN-OUT: joining the lines multiplies the header ----
-- One order (header) has one or more lines. Join them, and every header
-- column -- orderTotal included -- is copied onto every line of that
-- order. Same mechanism as Lecture 4's moneySpent fan-out, one level
-- down: order grain joined to line grain.

-- "Completed revenue, and how many units we sold." Units live on the
-- lines, so someone joins them in:
SELECT sum(o.orderTotal) AS revenue,
       sum(i.quantity)   AS units
FROM orders o
JOIN order_items i ON i.orderID = o.orderID
WHERE o.status = 'completed';
-- revenue   | units
-- 247923.72 |  1174
-- WRONG revenue, right units. Nothing errors.

-- CHECK 1 -- the revenue without the join:
SELECT sum(orderTotal) AS revenue
FROM orders
WHERE status = 'completed';
-- revenue
-- 157078.41

-- CHECK 2 -- count before you sum: rows vs. real orders
SELECT count(*)                   AS rows,
       count(DISTINCT o.orderID)  AS orders
FROM orders o
JOIN order_items i ON i.orderID = o.orderID
WHERE o.status = 'completed';
-- rows | orders
-- 844 |    529
-- 844 rows for 529 orders: an order with 3 lines had its total added 3
-- times. That's the 90,845.31 of revenue that doesn't exist.

-- FIX 1 -- sum what lives on the line: lineTotal, not the header's total.
SELECT sum(i.lineTotal) AS revenue,
       sum(i.quantity)  AS units
FROM orders o
JOIN order_items i ON i.orderID = o.orderID
WHERE o.status = 'completed';
-- revenue   | units
-- 157078.41 |  1174

-- FIX 2 -- aggregate the lines per order FIRST (a table subquery, Part
-- 1.4), so there is one row per order before the join:
SELECT sum(o.orderTotal) AS revenue,
       sum(l.units)      AS units
FROM orders o
JOIN (SELECT orderID, sum(quantity) AS units
      FROM order_items
      GROUP BY orderID) AS l ON l.orderID = o.orderID
WHERE o.status = 'completed';
-- revenue   | units
-- 157078.41 |  1174

-- ---- 2.4 Where a subquery is simply the right tool ----
-- "Revenue from orders that include at least one accessory."
-- WRONG: the JOIN version. An order with two accessories (a sleeve AND
-- a mouse) matches twice, so its total is counted twice.
SELECT sum(o.orderTotal) AS revenue, count(*) AS orders
FROM orders o
JOIN order_items i ON i.orderID   = o.orderID
JOIN products    p ON p.productID = i.productID
WHERE o.status = 'completed'
  AND p.category = 'Accessories';
-- revenue  | orders
-- 29810.88 |    155
-- WRONG: 155 isn't a number of orders, it's a number of accessory LINES.

-- RIGHT: EXISTS asks "is there at least one accessory line?" -- each
-- order is kept or not, never repeated (Part 4).
SELECT sum(o.orderTotal) AS revenue, count(*) AS orders
FROM orders o
WHERE o.status = 'completed'
  AND EXISTS (SELECT 1
              FROM order_items i
              JOIN products p ON p.productID = i.productID
              WHERE i.orderID = o.orderID
                AND p.category = 'Accessories');
-- revenue  | orders
-- 25955.91 |    142
-- 142 orders. 13 of them hold two accessories, and the JOIN counted each
-- of those twice -- 3,854.97 of revenue counted twice.
