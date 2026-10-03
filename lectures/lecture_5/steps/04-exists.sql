-- ============================================================
-- Lecture 5 — Part 4: EXISTS / NOT EXISTS
-- Run after Part 3.
-- ============================================================

-- ---- 4.1 "Is there at least one?" ----
SELECT count(*) AS customers_who_ordered
FROM customers c
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customerID = c.customerID);
-- customers_who_ordered
-- 28

SELECT c.customerID, c.firstName, c.lastName
FROM customers c
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.customerID = c.customerID);
-- customerid | firstname | lastname
-- 24 | Levon     | Arakelyan
-- 29 | Astghik   | Danielyan

-- What the subquery SELECTs doesn't matter -- not even NULL.
-- EXISTS only asks whether a row came back.
SELECT count(*) AS customers_who_ordered
FROM customers c
WHERE EXISTS (SELECT NULL FROM orders o WHERE o.customerID = c.customerID);
-- customers_who_ordered
-- 28

-- Employees who manage at least one person (one row each, no GROUP BY)
SELECT m.firstName, m.lastName, m.position
FROM employees m
WHERE EXISTS (SELECT 1 FROM employees r WHERE r.managerID = m.employeeID)
ORDER BY m.employeeID;
-- firstname | lastname | position
-- Vahe      | Sahakyan | Store Manager
-- Hayk      | Melikyan | Senior Sales
-- Marine    | Avagyan  | Senior Sales

-- ---- 4.2 No NULL trap ----
-- Part 2's NOT EXISTS found Hayk even though 5 cancelled orders have
-- employeeID NULL: o.employeeID = e.employeeID is NULL for those rows,
-- so they don't count as a match, and EXISTS itself is only ever
-- true or false.

-- ---- 4.3 The trap: the correlation you forgot ----
-- "Which customers gave us a 1-star rating?" (apology email list)
-- RIGHT:
SELECT c.customerID, c.firstName, c.lastName
FROM customers c
WHERE EXISTS (SELECT 1 FROM orders o
              WHERE o.customerID = c.customerID
                AND o.rating = 1)
ORDER BY c.customerID;
-- customerid | firstname | lastname
-- 4 | Tigran    | Grigoryan
-- 6 | Narek     | Manukyan
-- 14 | Vahan     | Torosyan
-- 25 | Hasmik    | Zakaryan

-- WRONG: the line that ties the subquery to c is missing.
SELECT count(*) AS customers
FROM customers c
WHERE EXISTS (SELECT 1 FROM orders o
              WHERE o.rating = 1);
-- WRONG: 30. The subquery no longer mentions c, so it gives the same
-- answer for every customer: "does ANY 1-star order exist?" Yes. All
-- 30 customers pass -- including Levon and Astghik, who never ordered.

-- WRONG, the way it happens in real code: the correlation is THERE,
-- but unqualified. Inside the subquery, customerID means
-- orders.customerID on both sides, so this compares a column to itself.
SELECT count(*) AS customers
FROM customers c
WHERE EXISTS (SELECT 1 FROM orders
              WHERE customerID = customerID
                AND rating = 1);
-- WRONG: 30, same as above.

-- The same rule, nastier: a column that isn't in the subquery's table
-- at all. orders has no productID any more (it moved to order_items),
-- so inside this subquery "productID" can only mean the OUTER
-- products.productID. No error -- the query compares each product with
-- itself, once per order:
SELECT count(*) AS never_ordered
FROM products
WHERE productID NOT IN (SELECT productID FROM orders);
-- WRONG: 0 -- and Ergonomic Chair Pro has never been ordered.
-- Qualify every column in a subquery (o.productID would have errored:
-- column o.productid does not exist), and the mistake becomes loud.

-- With NOT EXISTS the same slip goes the other way.
-- "Customers who have never given us 1 star" -- WRONG:
SELECT count(*) AS customers
FROM customers c
WHERE NOT EXISTS (SELECT 1 FROM orders o
                  WHERE o.rating = 1);
-- WRONG: 0

-- RIGHT:
SELECT count(*) AS customers
FROM customers c
WHERE NOT EXISTS (SELECT 1 FROM orders o
                  WHERE o.customerID = c.customerID
                    AND o.rating = 1);
-- customers
-- 26
-- Check: 4 + 26 = 30. All or nothing (30 or 0) is the tell.
