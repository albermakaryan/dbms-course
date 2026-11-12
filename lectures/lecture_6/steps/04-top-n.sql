-- ============================================================
-- Lecture 6 — Part 4: Top-N per group
-- Run after Part 3.
--
-- "Each customer's latest order" -- the last time we heard from them.
-- The most common window question at work, and three ways to answer it.
-- ============================================================

-- ---- 4.1 The loud one: a window function in WHERE ----
-- Number each customer's orders newest first, keep number 1:
-- Error on purpose:
SELECT customerID, orderID, orderDate,
       row_number() OVER (PARTITION BY customerID
                          ORDER BY orderDate DESC, orderTime DESC, orderID DESC) AS rn
FROM orders
WHERE rn = 1;
-- ERROR:  column "rn" does not exist

-- Error on purpose -- the function itself, not the alias:
SELECT customerID, orderID, orderDate
FROM orders
WHERE row_number() OVER (PARTITION BY customerID
                         ORDER BY orderDate DESC, orderTime DESC, orderID DESC) = 1;
-- ERROR:  window functions are not allowed in WHERE
-- Both errors are Part 2.5's picture: WHERE runs BEFORE window
-- functions exist. (The first error is the same reason a SELECT alias
-- can't be used in WHERE.) A loud error -- the friendly kind.

-- ---- 4.2 Method 1: row_number() in a CTE, filter outside ----
-- Lecture 5's CTE is the fix: compute the window in one step, filter
-- in the next, where rn is an ordinary column.
WITH ranked AS (
    SELECT customerID, orderID, orderDate, orderTime, orderTotal,
           row_number() OVER (PARTITION BY customerID
                              ORDER BY orderDate DESC, orderTime DESC, orderID DESC) AS rn
    FROM orders
)
SELECT customerID, orderID, orderDate, orderTime, orderTotal
FROM ranked
WHERE rn = 1
ORDER BY customerID;
-- customerid | orderid | orderdate  | ordertime | ordertotal
--          1 |    1591 | 2024-12-27 | 19:27:25  |      89.01
--          2 |    1593 | 2024-12-27 | 20:50:21  |      14.50
--          3 |    1585 | 2024-12-26 | 10:16:01  |      29.70
--          4 |    1567 | 2024-12-19 | 20:54:55  |      18.81
-- ... (28 rows)
-- 28 rows: one per customer WHO HAS ORDERS. Levon and Astghik have no
-- rows in orders, so they have no partition at all.

-- ---- 4.3 Method 2: LEFT JOIN LATERAL ... LIMIT 1 (Lecture 5, 3.5) ----
SELECT c.customerID, latest.orderID, latest.orderDate, latest.orderTime, latest.orderTotal
FROM customers c
LEFT JOIN LATERAL (SELECT o.orderID, o.orderDate, o.orderTime, o.orderTotal
                   FROM orders o
                   WHERE o.customerID = c.customerID
                   ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
                   LIMIT 1) AS latest ON true
ORDER BY c.customerID;
-- customerid | orderid | orderdate  | ordertime | ordertotal
--          1 |    1591 | 2024-12-27 | 19:27:25  |      89.01
--          2 |    1593 | 2024-12-27 | 20:50:21  |      14.50
--          3 |    1585 | 2024-12-26 | 10:16:01  |      29.70
--          4 |    1567 | 2024-12-19 | 20:54:55  |      18.81
-- ... (30 rows)

-- Row count check -- predict it first: 30 customers in.
SELECT count(*) AS rows, count(latest.orderID) AS with_an_order
FROM customers c
LEFT JOIN LATERAL (SELECT o.orderID
                   FROM orders o
                   WHERE o.customerID = c.customerID
                   ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
                   LIMIT 1) AS latest ON true;
-- rows | with_an_order
--   30 |            28

-- The inner JOIN LATERAL drops the customers whose subquery returned
-- nothing -- silently, like any inner join (Lecture 4, 4.2):
SELECT count(*) AS rows
FROM customers c
JOIN LATERAL (SELECT o.orderID
              FROM orders o
              WHERE o.customerID = c.customerID
              ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
              LIMIT 1) AS latest ON true;
-- rows
--   28
-- WRONG for this question: 30 customers in, 28 out. Levon and
-- Astghik are gone, no error. For
-- "when did we last hear from each customer?", the two who never ordered
-- are exactly the ones you need to see. LEFT JOIN LATERAL keeps them.

-- ---- 4.4 Method 3: DISTINCT ON (PostgreSQL only) ----
-- "Keep the first row of each customerID, in this ORDER BY."
SELECT DISTINCT ON (customerID)
       customerID, orderID, orderDate, orderTime, orderTotal
FROM orders
ORDER BY customerID, orderDate DESC, orderTime DESC, orderID DESC;
-- customerid | orderid | orderdate  | ordertime | ordertotal
--          1 |    1591 | 2024-12-27 | 19:27:25  |      89.01
--          2 |    1593 | 2024-12-27 | 20:50:21  |      14.50
--          3 |    1585 | 2024-12-26 | 10:16:01  |      29.70
--          4 |    1567 | 2024-12-19 | 20:54:55  |      18.81
-- ... (28 rows)
-- Shortest of the three -- and not standard SQL. MySQL, SQL Server and
-- SQLite don't have it; the row_number() version works on all of them.

-- Error on purpose: the ORDER BY must START with the DISTINCT ON columns.
SELECT DISTINCT ON (customerID) customerID, orderID, orderDate
FROM orders
ORDER BY orderDate DESC;
-- ERROR:  SELECT DISTINCT ON expressions must match initial ORDER BY expressions

-- The quiet version: the ORDER BY starts right, but says nothing about
-- WHICH row of each customer comes first.
SELECT DISTINCT ON (customerID) customerID, orderID, orderDate
FROM orders
ORDER BY customerID
LIMIT 3;
-- customerid | orderid | orderdate
--          1 |    1071 | 2024-02-28
--          2 |    1560 | 2024-12-18
--          3 |    1389 | 2024-09-27
-- WRONG: "the first row of each customer" in no particular order.
-- Compare with 4.4 above: customer 1's latest order is 1591 on
-- 2024-12-27, not this one. No error.

-- ---- 4.5 Prove the three agree: EXCEPT both ways (Lecture 5, 6.5) ----
-- For each pair of methods, rows in one but not the other. 0 rows in
-- both directions = the same result. (LATERAL's inner join here, so
-- all three cover the same 28 customers.)
WITH m1 AS (
    SELECT customerID, orderID
    FROM (SELECT customerID, orderID,
                 row_number() OVER (PARTITION BY customerID
                                    ORDER BY orderDate DESC, orderTime DESC, orderID DESC) AS rn
          FROM orders) AS r
    WHERE rn = 1
),
m2 AS (
    SELECT c.customerID, l.orderID
    FROM customers c
    JOIN LATERAL (SELECT o.orderID FROM orders o
                  WHERE o.customerID = c.customerID
                  ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
                  LIMIT 1) AS l ON true
),
m3 AS (
    SELECT DISTINCT ON (customerID) customerID, orderID
    FROM orders
    ORDER BY customerID, orderDate DESC, orderTime DESC, orderID DESC
)
SELECT (SELECT count(*) FROM (SELECT * FROM m1 EXCEPT SELECT * FROM m2) x) AS m1_not_m2,
       (SELECT count(*) FROM (SELECT * FROM m2 EXCEPT SELECT * FROM m1) x) AS m2_not_m1,
       (SELECT count(*) FROM (SELECT * FROM m1 EXCEPT SELECT * FROM m3) x) AS m1_not_m3,
       (SELECT count(*) FROM (SELECT * FROM m3 EXCEPT SELECT * FROM m1) x) AS m3_not_m1;
-- m1_not_m2 | m2_not_m1 | m1_not_m3 | m3_not_m1
--         0 |         0 |         0 |         0

-- ---- 4.6 THE TRAP: an incomplete ORDER BY -- inside the window, the
-- LATERAL subquery, or DISTINCT ON ----
-- "Latest order" = ORDER BY orderDate DESC, and nothing else.
-- Two customers placed two orders on their last day: Anna Sargsyan
-- (customer 1: orders 1589 and 1591 on 2024-12-27) and Armen Gevorgyan
-- (customer 12: 1595 and 1596 on 2024-12-28).
WITH m1 AS (
    SELECT customerID, orderID
    FROM (SELECT customerID, orderID,
                 row_number() OVER (PARTITION BY customerID ORDER BY orderDate DESC) AS rn
          FROM orders) AS r
    WHERE rn = 1
),
m2 AS (
    SELECT c.customerID, l.orderID
    FROM customers c
    JOIN LATERAL (SELECT o.orderID FROM orders o
                  WHERE o.customerID = c.customerID
                  ORDER BY o.orderDate DESC
                  LIMIT 1) AS l ON true
),
m3 AS (
    SELECT DISTINCT ON (customerID) customerID, orderID
    FROM orders
    ORDER BY customerID, orderDate DESC
)
SELECT 'row_number' AS method, customerID, orderID FROM m1 WHERE customerID IN (1, 12)
UNION ALL
SELECT 'lateral',              customerID, orderID FROM m2 WHERE customerID IN (1, 12)
UNION ALL
SELECT 'distinct on',          customerID, orderID FROM m3 WHERE customerID IN (1, 12)
ORDER BY customerID, method;
--   method    | customerid | orderid
-- distinct on |          1 |    1591
-- lateral     |          1 |    1589
-- row_number  |          1 |    1591
-- distinct on |         12 |    1595
-- lateral     |         12 |    1595
-- row_number  |         12 |    1595
-- WRONG, in two different ways:
-- * Anna: the methods DISAGREE (1589 vs 1591) -- an EXCEPT check
--   between them would catch it.
-- * Armen: all three AGREE on 1595 -- and all three are wrong. His
--   latest order is 1596 (14:28, after 1595 at 12:06). An EXCEPT check
--   says "0 rows, identical". Agreement only proves something when each
--   method's question has exactly one answer.
-- The fix is 4.2-4.4: orderDate DESC, orderTime DESC, orderID DESC --
-- complete, so the last key is unique.

-- ---- 4.7 Top 2, not top 1 ----
-- DISTINCT ON can only keep ONE row per group. The other two methods
-- just change a number. "Each customer's two most recent orders":
WITH ranked AS (
    SELECT customerID, orderID,
           row_number() OVER (PARTITION BY customerID
                              ORDER BY orderDate DESC, orderTime DESC, orderID DESC) AS rn
    FROM orders
)
SELECT count(*) AS rows, count(DISTINCT customerID) AS customers
FROM ranked
WHERE rn <= 2;
-- rows | customers
--   56 |        28
-- Predict: every customer who ordered has at least 4 orders (Diana),
-- so 28 x 2 = 56.

SELECT count(*) AS rows, count(l.orderID) AS order_rows
FROM customers c
LEFT JOIN LATERAL (SELECT o.orderID FROM orders o
                   WHERE o.customerID = c.customerID
                   ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
                   LIMIT 2) AS l ON true;
-- rows | order_rows
--   58 |         56
-- 56 order rows + 2 NULL-padded rows for Levon and Astghik = 58.
