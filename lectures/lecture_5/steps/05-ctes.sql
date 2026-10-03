-- ============================================================
-- Lecture 5 — Part 5: From subqueries to CTEs
-- Run after Part 4.
-- ============================================================

-- ---- 5.1 The same derived table, with a name ----
-- Part 1.4, rewritten. Read it top to bottom instead of inside out.
WITH per_customer AS (
    SELECT customerID, count(*) AS order_count
    FROM orders
    GROUP BY customerID
)
SELECT c.firstName, c.lastName, pc.order_count
FROM per_customer pc
JOIN customers c ON c.customerID = pc.customerID
WHERE pc.order_count >= 40
ORDER BY pc.order_count DESC;
-- firstname | lastname    | order_count
-- Davit     | Petrosyan   |          52
-- Armen     | Gevorgyan   |          48
-- Karen     | Khachatryan |          41
-- Aram      | Vardanyan   |          40
-- Same 4 rows as Part 1.4.

-- ---- 5.2 Several CTEs; a later one reads an earlier one ----
-- "Customers who order more often than the average customer"
WITH per_customer AS (
    SELECT customerID, count(*) AS order_count
    FROM orders
    GROUP BY customerID
),
overall AS (
    SELECT avg(order_count) AS avg_count
    FROM per_customer                       -- reads the CTE above
)
SELECT c.firstName, c.lastName, pc.order_count,
       round(ov.avg_count, 2) AS avg_count
FROM per_customer pc
CROSS JOIN overall ov                       -- one row, so no fan-out
JOIN customers c ON c.customerID = pc.customerID
WHERE pc.order_count > ov.avg_count
ORDER BY pc.order_count DESC;
-- 12 rows, Davit 52 down to Tigran Grigoryan 22; avg_count 21.43 on
-- every row (Part 1.4's number).

-- ---- 5.3 THE TRAP: fan-out in CTE clothing (callback: Lecture 4, 4.10) ----
-- "For each city: completed orders, and average spend per customer."
-- customer_spend is one row per customer (customer grain). Joining it
-- to orders (order grain) copies each customer's 'spent' onto every one
-- of their orders.
--
-- This is the same bug as Lecture 4's SUM(customers.moneySpent) fan-out
-- -- CTEs don't prevent it, they just make the mistake easier to not
-- notice because the query reads so cleanly.
WITH customer_spend AS (
    SELECT customerID, sum(orderTotal) AS spent
    FROM orders
    WHERE status = 'completed'
    GROUP BY customerID
)
SELECT c.city,
       count(o.orderID)        AS orders,
       round(avg(cs.spent), 2) AS avg_customer_spend
FROM customers c
JOIN customer_spend cs ON cs.customerID = c.customerID
JOIN orders o          ON o.customerID  = c.customerID
                      AND o.status = 'completed'
GROUP BY c.city
ORDER BY avg_customer_spend DESC;
-- WRONG (orders column is right; the average is not):
-- city     | orders | avg_customer_spend
-- Abovyan  |     29 |            8507.37
-- Gyumri   |    181 |            7908.41
-- Yerevan  |    280 |            7063.81
-- Vanadzor |     39 |            5976.08
-- Every number is believable. That's the problem.

-- CHECK 1 -- add the spend back up. It must be 157078.41 (Part 2.3).
WITH customer_spend AS (
    SELECT customerID, sum(orderTotal) AS spent
    FROM orders
    WHERE status = 'completed'
    GROUP BY customerID
)
SELECT sum(cs.spent)                  AS total_spend,
       count(*)                       AS rows,
       count(DISTINCT cs.customerID)  AS customers
FROM customer_spend cs
JOIN orders o ON o.customerID = cs.customerID
             AND o.status = 'completed';
-- total_spend | rows | customers
-- 3889069.12 |  529 |        28
-- 529 rows for 28 customers: each customer's total was counted once
-- per completed order. The average was weighted the same way, toward
-- the customers with the most orders.

-- FIX -- keep everything at customer grain: count the orders in the
-- CTE too, and never join back to orders.
WITH customer_spend AS (
    SELECT customerID,
           count(*)        AS orders,
           sum(orderTotal) AS spent
    FROM orders
    WHERE status = 'completed'
    GROUP BY customerID
)
SELECT c.city,
       sum(cs.orders)          AS orders,
       round(avg(cs.spent), 2) AS avg_customer_spend
FROM customers c
JOIN customer_spend cs ON cs.customerID = c.customerID
GROUP BY c.city
ORDER BY avg_customer_spend DESC;
-- city     | orders | avg_customer_spend
-- Gyumri   |    181 |            6714.16
-- Abovyan  |     29 |            6136.27
-- Yerevan  |    280 |            5189.36
-- Vanadzor |     39 |            4793.83
-- Different winner: Gyumri, not Abovyan.

-- CHECK 2 -- the fixed CTE adds up to the known total:
WITH customer_spend AS (
    SELECT customerID, sum(orderTotal) AS spent
    FROM orders
    WHERE status = 'completed'
    GROUP BY customerID
)
SELECT sum(spent) AS total_spend, count(*) AS customers
FROM customer_spend;
-- total_spend | customers
-- 157078.41 |        28

-- ---- 5.4 The trap: ORDER BY inside the CTE ----
-- "Top 5 customers by spend". The sorting is done -- inside the CTE.
WITH top_spenders AS (
    SELECT customerID, sum(orderTotal) AS spent
    FROM orders
    WHERE status = 'completed'
    GROUP BY customerID
    ORDER BY spent DESC
)
SELECT c.firstName, c.lastName, t.spent
FROM top_spenders t
JOIN customers c ON c.customerID = t.customerID
LIMIT 5;
-- WRONG (PostgreSQL 16 on this data):
-- firstname | lastname  | spent
-- Anna      | Sargsyan  | 6651.60
-- Davit     | Petrosyan | 8838.85
-- Mariam    | Hakobyan  | 4084.22
-- Tigran    | Grigoryan | 5762.87
-- Lusine    | Avetisyan | 2861.90
-- These are customers 1-5 in customerID order. The join re-read the
-- rows in its own order, and LIMIT took the first five of THAT.
-- Read the spent column: it isn't even descending.

-- FIX -- ORDER BY belongs to the query whose output you look at:
WITH top_spenders AS (
    SELECT customerID, sum(orderTotal) AS spent
    FROM orders
    WHERE status = 'completed'
    GROUP BY customerID
)
SELECT c.firstName, c.lastName, t.spent
FROM top_spenders t
JOIN customers c ON c.customerID = t.customerID
ORDER BY t.spent DESC
LIMIT 5;
-- firstname | lastname     | spent
-- Aram      | Vardanyan    | 14625.38
-- Artur     | Baghdasaryan | 11235.95
-- Armen     | Gevorgyan    | 10028.09
-- Lilit     | Hovhannisyan |  9410.64
-- Vahan     | Torosyan     |  8925.87
-- Not one name in common with the wrong list.
