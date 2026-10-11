-- ============================================================
-- Lecture 5 — Part 6: Set operations: UNION, INTERSECT, EXCEPT
-- Run after Part 5.
--
-- A JOIN puts two tables SIDE BY SIDE: more columns per row.
-- A set operation STACKS two query results: more rows, same columns.
--   q1 UNION q2       rows in q1 or q2, duplicates removed
--   q1 UNION ALL q2   every row of q1, then every row of q2
--   q1 INTERSECT q2   rows in both
--   q1 EXCEPT q2      rows in q1 that are not in q2
-- Both queries must return the same number of columns, with
-- compatible types. ORDER BY / LIMIT at the end apply to the WHOLE
-- result.
-- ============================================================

-- ---- 6.1 UNION ALL vs UNION: stacking two lists ----
-- "One list of everybody: customers and staff." 30 + 8 = 38.
SELECT count(*) AS people
FROM (SELECT firstName, lastName FROM customers
      UNION ALL
      SELECT firstName, lastName FROM employees) AS everyone;
-- people
-- 38

-- UNION removes duplicate ROWS -- and here a row is just a name:
SELECT count(*) AS people
FROM (SELECT firstName, lastName FROM customers
      UNION
      SELECT firstName, lastName FROM employees) AS everyone;
-- people
-- 35

-- Which 3 people vanished? The names that occur twice:
SELECT firstName, lastName, count(*) AS times
FROM (SELECT firstName, lastName FROM customers
      UNION ALL
      SELECT firstName, lastName FROM employees) AS everyone
GROUP BY firstName, lastName
HAVING count(*) > 1
ORDER BY lastName;
-- firstname | lastname     | times
-- Lilit     | Hovhannisyan |     2
-- Hayk      | Melikyan     |     2
-- Anna      | Sargsyan     |     2
-- Two customers named Anna Sargsyan, and the two customer/employee
-- name pairs from Lecture 4 (4.9). UNION merged each pair into one.

-- ---- 6.2 THE TRAP: UNION inside a total ----
-- "Completed revenue = in-store revenue + online revenue." Stack the
-- two sets of order totals and add them up:
SELECT sum(orderTotal) AS revenue, count(*) AS order_totals
FROM (SELECT orderTotal FROM orders WHERE status = 'completed' AND channel = 'in_store'
      UNION
      SELECT orderTotal FROM orders WHERE status = 'completed' AND channel = 'online') AS t;
-- WRONG:
-- revenue   | order_totals
-- 106263.47 |          324
-- The real figure is 157078.41 over 529 completed orders. UNION
-- removed every repeated VALUE: seven completed orders of exactly
-- 249.00 are seven copies of the same row to UNION, so 249.00 was
-- counted once. Nothing errors.

-- FIX: UNION ALL keeps every row.
SELECT sum(orderTotal) AS revenue, count(*) AS order_totals
FROM (SELECT orderTotal FROM orders WHERE status = 'completed' AND channel = 'in_store'
      UNION ALL
      SELECT orderTotal FROM orders WHERE status = 'completed' AND channel = 'online') AS t;
-- revenue   | order_totals
-- 157078.41 |          529
-- Rule of thumb: UNION ALL unless you WANT duplicates removed -- and
-- then say so in a comment.

-- ---- 6.3 Columns are paired by POSITION, not by name ----
-- Error on purpose: different numbers of columns.
SELECT firstName, lastName FROM customers
UNION
SELECT firstName FROM employees;
-- ERROR:  each UNION query must have the same number of columns

-- WRONG, and silent: the same number of columns, in a different order.
SELECT firstName, lastName, 'customer' AS source FROM customers
UNION ALL
SELECT lastName, firstName, 'employee' FROM employees
ORDER BY source DESC, firstName
LIMIT 4;
-- firstname   | lastname | source
-- Avagyan     | Marine   | employee
-- Ghazaryan   | Nare     | employee
-- Grigoryan   | Arman    | employee
-- Harutyunyan | Ani      | employee
-- The first column of the second query went into the first column of
-- the result -- whatever its name. Both are text, so nothing errors.
-- The column names (firstName, lastName) come from the FIRST query.

-- ---- 6.4 INTERSECT: rows in both results ----
-- Lecture 4's question, "who is on both lists?", as INTERSECT:
SELECT firstName, lastName FROM customers
INTERSECT
SELECT firstName, lastName FROM employees
ORDER BY lastName;
-- firstname | lastname
-- Lilit     | Hovhannisyan
-- Hayk      | Melikyan
-- Same answer as Lecture 4's join on names -- and the same mistake:
-- these are four different people (Lecture 4, 4.9). INTERSECT
-- compares VALUES; names are not identifiers.

-- With a real key it's safe: customers who have BOTH returned and
-- cancelled an order. INTERSECT gives the ids; IN looks up the names.
SELECT c.customerID, c.firstName, c.lastName
FROM customers c
WHERE c.customerID IN (SELECT customerID FROM orders WHERE status = 'returned'
                       INTERSECT
                       SELECT customerID FROM orders WHERE status = 'cancelled')
ORDER BY c.customerID;
-- 12 rows, Anna Sargsyan (customerID 1) to Gevorg Kocharyan (28)

-- ---- 6.5 EXCEPT: rows in the first result, not in the second ----
-- Part 2.1's question -- a fourth way:
SELECT productID FROM products
EXCEPT
SELECT productID FROM order_items;
-- productid
-- 35

-- Part 2.2's question, where NOT IN returned nothing:
SELECT employeeID FROM employees
EXCEPT
SELECT employeeID FROM orders WHERE status = 'cancelled';
-- employeeid
-- 5
-- Hayk -- correct. Set operations compare rows the way DISTINCT does:
-- NULL counts as equal to NULL. The 5 NULLs on the right could only
-- remove a NULL from the left, and no employee has a NULL id.

-- EXCEPT returns only the columns you compared. Need names? Use it as
-- a subquery. Customers who never returned anything:
SELECT c.customerID, c.firstName, c.lastName
FROM customers c
WHERE c.customerID IN (SELECT customerID FROM customers
                       EXCEPT
                       SELECT customerID FROM orders WHERE status = 'returned')
ORDER BY c.customerID;
-- 8 rows -- including Levon (24) and Astghik (29), who never ordered
-- at all, so they never returned anything either.

-- ---- 6.6 The ALL versions keep count ----
-- EXCEPT removes every copy; EXCEPT ALL removes one copy per match.
SELECT x FROM (VALUES (1), (1), (2)) AS a(x)
EXCEPT
SELECT x FROM (VALUES (1)) AS b(x);
-- x
-- 2

SELECT x FROM (VALUES (1), (1), (2)) AS a(x)
EXCEPT ALL
SELECT x FROM (VALUES (1)) AS b(x)
ORDER BY x;
-- x
-- 1
-- 2

-- ---- 6.7 ORDER BY / LIMIT for ONE branch need parentheses ----
-- "The biggest completed order in each channel." Without the
-- parentheses, ORDER BY and LIMIT would apply to the whole result.
(SELECT channel, orderID, orderTotal
 FROM orders
 WHERE status = 'completed' AND channel = 'in_store'
 ORDER BY orderTotal DESC, orderID
 LIMIT 1)
UNION ALL
(SELECT channel, orderID, orderTotal
 FROM orders
 WHERE status = 'completed' AND channel = 'online'
 ORDER BY orderTotal DESC, orderID
 LIMIT 1);
-- channel  | orderid | ordertotal
-- in_store |    1385 |    2500.00
-- online   |    1158 |    2500.00
-- (two online orders tie at 2500.00; orderID picks one -- Part 3.5)
--
-- Next: WITH RECURSIVE is a UNION ALL of two queries -- a starting
-- row and a step that is repeated.
