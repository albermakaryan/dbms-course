-- ============================================================
-- Lecture 6 — Part 1: The problem windows solve
-- Run after steps/00-setup.sql.
--
-- GROUP BY answers "one number per group" -- and throws the rows
-- away to do it. Often you need the group's number AND the row:
-- each order next to its customer's total, each order as a share of
-- all revenue. A window function gives you both.
-- ============================================================

-- ---- 1.1 GROUP BY collapses the rows ----
-- Completed revenue per customer: one row per customer, the orders are gone.
SELECT customerID, sum(orderTotal) AS customer_total
FROM orders
WHERE status = 'completed'
GROUP BY customerID
ORDER BY customerID
LIMIT 3;
-- =>

SELECT count(*) AS completed_orders,
       count(DISTINCT customerID) AS customers
FROM orders
WHERE status = 'completed';
-- =>

-- The question: "show each completed order NEXT TO its customer's
-- total." Try to keep the order columns and GROUP BY anyway:
-- Error on purpose:
SELECT orderID, customerID, orderTotal, sum(orderTotal) AS customer_total
FROM orders
WHERE status = 'completed'
GROUP BY customerID;
-- =>

-- ---- 1.2 Before windows: aggregate in a derived table, join it back ----
-- (Lecture 5, 1.4: a table subquery at customer grain, joined back to
-- the orders. Here the join is safe -- one row per customer on the
-- right -- but you have to check that yourself every time.)
SELECT o.orderID, o.customerID, o.orderTotal, t.customer_total
FROM orders o
JOIN (SELECT customerID, sum(orderTotal) AS customer_total
      FROM orders
      WHERE status = 'completed'
      GROUP BY customerID) AS t ON t.customerID = o.customerID
WHERE o.status = 'completed'
ORDER BY o.customerID, o.orderID
LIMIT 3;
-- =>

-- ...or a correlated subquery in SELECT (Lecture 5, Part 3). Note that
-- the status filter has to be written TWICE, once per query. Forget it
-- inside and the total quietly includes returned and cancelled orders.
SELECT o.orderID, o.customerID, o.orderTotal,
       (SELECT sum(o2.orderTotal)
        FROM orders o2
        WHERE o2.customerID = o.customerID
          AND o2.status = 'completed') AS customer_total
FROM orders o
WHERE o.status = 'completed'
ORDER BY o.customerID, o.orderID
LIMIT 3;
-- =>

-- ---- 1.3 The window version ----
-- sum(...) OVER (PARTITION BY customerID): "the sum over the rows that
-- share this row's customerID". Every input row stays.
SELECT orderID, customerID, orderTotal,
       sum(orderTotal) OVER (PARTITION BY customerID) AS customer_total
FROM orders
WHERE status = 'completed'
ORDER BY customerID, orderID
LIMIT 3;
-- =>
-- The same numbers as both older versions -- one query, no join, the
-- filter written once. (Part 7.5 proves all three agree on every row.)

-- ---- 1.4 The invariant: rows in = rows out ----
-- A query whose only "extra" is window functions returns exactly as
-- many rows as its input. Predict it, then check it.
SELECT count(*) AS rows_out
FROM (SELECT orderID,
             sum(orderTotal)   OVER ()                        AS all_orders,
             count(*)          OVER (PARTITION BY customerID) AS customer_orders,
             avg(orderTotal)   OVER (PARTITION BY status)     AS status_avg
      FROM orders) AS w;
-- =>
-- 600 in, 600 out. Three windows, three different groupings, and not
-- one row added or lost.

-- ---- 1.5 Callback: Lecture 4's fan-out (4.10) ----
-- To put each customer's moneySpent next to their orders, Lecture 4
-- JOINED -- and the join copied it onto every order:
SELECT count(*)          AS rows,
       sum(c.moneySpent) AS total_money_spent
FROM customers c
JOIN orders o ON o.customerID = c.customerID;
-- =>
-- WRONG total: 30 customers became 600 rows, and the sum counted each
-- customer's moneySpent once per order.

-- A window brings a group number TO the rows that are already there.
-- It never adds rows, so there is nothing to multiply:
SELECT count(*)                         AS rows,
       sum(moneySpent)                  AS total_money_spent,
       min(all_customers)               AS window_total
FROM (SELECT moneySpent,
             sum(moneySpent) OVER () AS all_customers
      FROM customers) AS w;
-- =>
-- 30 in, 30 out; the total is the known completed revenue.
