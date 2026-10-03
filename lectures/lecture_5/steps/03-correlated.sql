-- ============================================================
-- Lecture 5 — Part 3: Correlated vs. non-correlated subqueries
-- Run after Part 2.
-- ============================================================

-- ---- 3.1 Non-correlated: the subquery runs on its own ----
-- Part 1's (SELECT avg(price) FROM products) -- select just the
-- subquery and run it: you get 280.10. One value, computed once.

-- ---- 3.2 Correlated: the subquery mentions the outer row ----
-- "Products priced above THEIR OWN category's average"
SELECT p.productName, p.category, p.price
FROM products p
WHERE p.price > (SELECT avg(p2.price)
                 FROM products p2
                 WHERE p2.category = p.category)
ORDER BY p.category, p.price DESC;
-- 19 rows -- compare 12 against the overall average in Part 1.
-- (Chairs has one product, which can't beat its own average.)

-- Error on purpose: the subquery alone has no p to look at.
SELECT avg(p2.price) FROM products p2 WHERE p2.category = p.category;
-- ERROR:  missing FROM-clause entry for table "p"

-- ---- 3.3 Each customer against their own history ----
-- "Customers whose most recent order was bigger than their average order"
SELECT c.firstName, c.lastName, o.orderID, o.orderDate, o.orderTotal,
       (SELECT round(avg(o3.orderTotal), 2)
        FROM orders o3 WHERE o3.customerID = o.customerID) AS their_avg
FROM orders o
JOIN customers c ON c.customerID = o.customerID
WHERE o.orderID = (SELECT o2.orderID FROM orders o2
                   WHERE o2.customerID = o.customerID
                   ORDER BY o2.orderDate DESC, o2.orderTime DESC
                   LIMIT 1)
  AND o.orderTotal > (SELECT avg(o3.orderTotal)
                      FROM orders o3 WHERE o3.customerID = o.customerID)
ORDER BY o.orderTotal DESC;
-- 10 rows. Top three:
-- firstname | lastname     | orderid | orderdate  | ordertotal | their_avg
-- Artur     | Baghdasaryan |    1588 | 2024-12-27 |    1358.30 |    355.32
-- Narek     | Manukyan     |    1557 | 2024-12-17 |    1250.00 |    288.34
-- Vahan     | Torosyan     |    1590 | 2024-12-27 |     926.00 |    422.16
-- (all orders, any status; 28 customers have a last order, 10 qualify)

-- ---- 3.4 Same shape as a self-join (callback: Lecture 4, 4.8) ----
-- "Who was hired before their own manager?"
-- Lecture 4's tool, the self-join:
SELECT e.firstName, e.hireDate, m.firstName AS manager, m.hireDate AS manager_hired
FROM employees e
JOIN employees m ON m.employeeID = e.managerID
WHERE e.hireDate < m.hireDate;
-- firstname | hiredate   | manager | manager_hired
-- Marine    | 2016-08-01 | Vahe    | 2017-02-01

-- The correlated subquery: fetch "my manager's hire date" per row.
SELECT e.firstName, e.hireDate
FROM employees e
WHERE e.hireDate < (SELECT m.hireDate
                    FROM employees m
                    WHERE m.employeeID = e.managerID);
-- firstname | hiredate
-- Marine    | 2016-08-01

-- Where they differ: a correlated subquery in SELECT keeps every outer
-- row. Lecture 4's self-join + GROUP BY counted direct reports for 3
-- managers; this lists all 8 people, with 0 for the rest.
SELECT e.firstName || ' ' || e.lastName AS employee,
       (SELECT m.firstName || ' ' || m.lastName
        FROM employees m WHERE m.employeeID = e.managerID) AS manager,
       (SELECT count(*)
        FROM employees r WHERE r.managerID = e.employeeID) AS direct_reports
FROM employees e
ORDER BY direct_reports DESC, e.employeeID;
-- employee           | manager        | direct_reports
-- Vahe Sahakyan      |                |              4
-- Hayk Melikyan      | Vahe Sahakyan  |              2
-- Marine Avagyan     | Vahe Sahakyan  |              1
-- Gor Mkrtchyan      | Vahe Sahakyan  |              0
-- Ani Harutyunyan    | Vahe Sahakyan  |              0
-- Nare Ghazaryan     | Hayk Melikyan  |              0
-- Lilit Hovhannisyan | Hayk Melikyan  |              0
-- Arman Grigoryan    | Marine Avagyan |              0
-- Vahe's manager is NULL: the subquery found no row, so it's NULL --
-- like a LEFT JOIN, not like an inner join.

-- ---- 3.5 LATERAL: a correlated subquery in FROM ----
-- A correlated subquery in SELECT returns ONE value. "Each customer's
-- latest order -- its id, date, channel and total" needs four.
-- Error on purpose:
SELECT c.firstName,
       (SELECT o.orderID, o.orderTotal
        FROM orders o
        WHERE o.customerID = c.customerID
        ORDER BY o.orderDate DESC, o.orderTime DESC
        LIMIT 1) AS latest
FROM customers c;
-- ERROR:  subquery must return only one column

-- A subquery in FROM can return many columns -- but on its own it
-- can't see c. Error on purpose:
SELECT c.firstName, latest.orderID
FROM customers c
JOIN (SELECT o.orderID
      FROM orders o
      WHERE o.customerID = c.customerID
      ORDER BY o.orderDate DESC, o.orderTime DESC
      LIMIT 1) AS latest ON true;
-- ERROR:  invalid reference to FROM-clause entry for table "c"
-- PostgreSQL 16 and later add:
-- HINT:  To reference that table, you must mark this subquery with LATERAL.

-- LATERAL: the subquery in FROM runs once per customer row, and may
-- use that row's columns. ON true: the matching is already done inside.
SELECT c.firstName, c.lastName,
       latest.orderID, latest.orderDate, latest.channel, latest.orderTotal
FROM customers c
JOIN LATERAL (SELECT o.orderID, o.orderDate, o.channel, o.orderTotal
              FROM orders o
              WHERE o.customerID = c.customerID
              ORDER BY o.orderDate DESC, o.orderTime DESC
              LIMIT 1) AS latest ON true
ORDER BY latest.orderTotal DESC;
-- 28 rows, one per customer who has ordered. Top three:
-- firstname | lastname     | orderid | orderdate  | channel  | ordertotal
-- Artur     | Baghdasaryan |    1588 | 2024-12-27 | in_store |    1358.30
-- Narek     | Manukyan     |    1557 | 2024-12-17 | in_store |    1250.00
-- Vahan     | Torosyan     |    1590 | 2024-12-27 | in_store |     926.00
-- (3.3 found these last orders with a subquery in WHERE; LATERAL
-- brings back every column of them in one join)

-- ---- Top N per group: each customer's 3 biggest orders ----
-- Several ROWS per customer -- no scalar subquery can do that.
-- orderID breaks ties: Suren has two orders of 449.00 tied for 3rd
-- place, and without it which one you get is up to the plan.
SELECT c.firstName, c.lastName, top3.orderID, top3.orderTotal
FROM customers c
LEFT JOIN LATERAL (SELECT o.orderID, o.orderTotal
                   FROM orders o
                   WHERE o.customerID = c.customerID
                   ORDER BY o.orderTotal DESC, o.orderID
                   LIMIT 3) AS top3 ON true
WHERE c.customerID IN (2, 24, 27)
ORDER BY c.customerID, top3.orderTotal DESC;
-- firstname | lastname   | orderid | ordertotal
-- Davit     | Petrosyan  |    1527 |    1000.00
-- Davit     | Petrosyan  |    1523 |     904.99
-- Davit     | Petrosyan  |    1573 |     747.89
-- Levon     | Arakelyan  |         |
-- Diana     | Aleksanyan |    1246 |    1780.00
-- Diana     | Aleksanyan |    1024 |     620.00
-- Diana     | Aleksanyan |    1165 |     349.00

-- Check the row count: you can predict it. Every customer who ordered
-- has at least 3 orders (fewest: Diana, 4), so 28 x 3 = 84.
SELECT count(*) AS rows, count(top3.orderID) AS orders
FROM customers c
JOIN LATERAL (SELECT o.orderID
              FROM orders o
              WHERE o.customerID = c.customerID
              ORDER BY o.orderTotal DESC, o.orderID
              LIMIT 3) AS top3 ON true;
-- rows | orders
-- 84 |     84

-- JOIN LATERAL behaves like an inner join: Levon and Astghik, with no
-- orders, silently disappear. LEFT JOIN LATERAL keeps them:
SELECT count(*) AS rows, count(top3.orderID) AS orders
FROM customers c
LEFT JOIN LATERAL (SELECT o.orderID
                   FROM orders o
                   WHERE o.customerID = c.customerID
                   ORDER BY o.orderTotal DESC, o.orderID
                   LIMIT 3) AS top3 ON true;
-- rows | orders
-- 86 |     84
-- 86 = 84 + 2 NULL-padded rows: Lecture 4's count(*) vs count(column).
