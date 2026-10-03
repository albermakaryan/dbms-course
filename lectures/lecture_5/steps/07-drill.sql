-- ============================================================
-- Lecture 5 — Part 7: Verification drill
-- Run after Part 6. Four queries that run, look fine, and are wrong.
-- For each one: which check from the notes catches it?
-- ============================================================

SELECT e.firstName
FROM employees e
WHERE e.employeeID NOT IN (SELECT employeeID FROM orders WHERE rating = 1);
-- "Salespeople who never got a 1-star rating": 0 rows

SELECT count(*) AS returners
FROM customers c
WHERE EXISTS (SELECT 1 FROM orders WHERE customerID = customerID AND status = 'returned');
-- "Customers who returned something": 30

WITH customer_orders AS (
    SELECT customerID, count(*) AS order_count
    FROM orders
    GROUP BY customerID
)
SELECT sum(co.order_count) AS total_orders
FROM customer_orders co
JOIN orders o ON o.customerID = co.customerID;
-- "Total orders": 17778

WITH ranked AS (
    SELECT productID, count(*) AS times_ordered
    FROM order_items
    GROUP BY productID
    ORDER BY times_ordered DESC
)
SELECT p.productName, r.times_ordered
FROM ranked r
JOIN products p ON p.productID = r.productID
LIMIT 3;
-- "Top 3 products": ThinkPad X1 Carbon 19, Laptop Sleeve 14 27, MX Keys 37

-- ---- Answers ----
-- 1. NOT IN + NULL: the 1-star list holds the online order's NULL.
SELECT count(*) AS one_star, count(employeeID) AS with_an_employee
FROM orders WHERE rating = 1;
-- one_star | with_an_employee
-- 5 |                4

SELECT e.firstName
FROM employees e
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.employeeID = e.employeeID AND o.rating = 1)
ORDER BY e.employeeID;
-- 5 rows: Ani, Nare, Hayk, Lilit, Marine

-- 2. Missing correlation: 30 includes Levon and Astghik, who never ordered.
SELECT count(*) AS returners
FROM customers c
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customerID = c.customerID AND o.status = 'returned');
-- returners
-- 22

-- 3. Fan-out: you know the total is 600.
SELECT count(*) AS total_orders FROM orders;
-- 600

-- 4. ORDER BY in the CTE: the times_ordered column isn't descending.
SELECT p.productName, count(*) AS times_ordered
FROM order_items i
JOIN products p ON p.productID = i.productID
GROUP BY p.productID, p.productName
ORDER BY times_ordered DESC, p.productName
LIMIT 3;
-- productname       | times_ordered
-- USB-C Cable 1m    |           128
-- HDMI 2.1 Cable 2m |            85
-- USB Flash 128GB   |            82
