-- ============================================================
-- Lecture 6 — Part 8: Verification drill
-- Run after Part 7. Five queries that run, look fine, and are wrong.
-- For each one: which check from the notes catches it?
-- ============================================================

-- "Orders placed so far this year, order by order"
SELECT orderID, orderDate,
       count(*) OVER (ORDER BY orderDate) AS orders_so_far
FROM orders
ORDER BY orderDate, orderID
LIMIT 3;
-- =>

-- "The top 3 salespeople by completed revenue"
SELECT e.firstName, sum(o.orderTotal) AS revenue,
       rank() OVER (ORDER BY sum(o.orderTotal) DESC) AS revenue_rank
FROM orders o
LEFT JOIN employees e ON e.employeeID = o.employeeID
WHERE o.status = 'completed'
GROUP BY o.employeeID, e.firstName
ORDER BY revenue_rank
LIMIT 3;
-- =>

-- "Arman's month-over-month change, May to July"
WITH monthly AS (
    SELECT extract(month FROM orderDate)::int AS month, sum(orderTotal) AS revenue
    FROM orders
    WHERE status = 'completed' AND employeeID = 7
    GROUP BY 1
)
SELECT month, revenue, revenue - lag(revenue) OVER (ORDER BY month) AS change
FROM monthly
WHERE month BETWEEN 5 AND 7
ORDER BY month;
-- =>

-- "Each of Diana's orders next to her latest order"
SELECT customerID, orderID, orderTotal,
       last_value(orderID) OVER (PARTITION BY customerID
                                 ORDER BY orderDate, orderTime, orderID) AS latest_order
FROM orders
WHERE customerID = 27
ORDER BY orderDate;
-- =>

-- "Each order's share of completed revenue" (the three biggest)
SELECT o.orderID, i.productID,
       round(100 * o.orderTotal / sum(o.orderTotal) OVER (), 3) AS pct_of_revenue
FROM orders o
JOIN order_items i ON i.orderID = o.orderID
WHERE o.status = 'completed'
ORDER BY o.orderTotal DESC, o.orderID, i.productID
LIMIT 3;
-- =>

-- ---- Answers ----
-- 1. The default RANGE frame: orders 1002 and 1003 share a date, so
--    both count each other. Check: a running count must go up by
--    exactly 1 per row. Fix: ROWS + a tie-breaker.
SELECT orderID, orderDate,
       count(*) OVER (ORDER BY orderDate, orderID
                      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS orders_so_far
FROM orders
ORDER BY orderDate, orderID
LIMIT 3;
-- =>

-- 2. The NULL partition: the "salesperson" with no name is the online
--    shop. Check: a ranking of people should have names. Fix: exclude
--    the NULLs on purpose (or label them, if the question is channels).
SELECT e.firstName, sum(o.orderTotal) AS revenue,
       rank() OVER (ORDER BY sum(o.orderTotal) DESC) AS revenue_rank
FROM orders o
JOIN employees e ON e.employeeID = o.employeeID
WHERE o.status = 'completed'
GROUP BY o.employeeID, e.firstName
ORDER BY revenue_rank
LIMIT 3;
-- =>

-- 3. lag across a missing month: Arman sold nothing in June, so July
--    is compared with May. And the WHERE ran before lag (Part 2.5), so
--    even May's lag lost April. Check: lag the month too. Fix: a full
--    calendar, LEFT JOIN, and filter the months AFTER the window.
WITH monthly AS (
    SELECT extract(month FROM orderDate)::int AS month, sum(orderTotal) AS revenue
    FROM orders
    WHERE status = 'completed' AND employeeID = 7
    GROUP BY 1
),
full_months AS (
    SELECT m.month, coalesce(mo.revenue, 0) AS revenue
    FROM (SELECT DISTINCT month FROM dim_date) AS m
    LEFT JOIN monthly mo ON mo.month = m.month
),
compared AS (
    SELECT month, revenue, revenue - lag(revenue) OVER (ORDER BY month) AS change
    FROM full_months
)
SELECT month, revenue, change
FROM compared
WHERE month BETWEEN 5 AND 7
ORDER BY month;
-- =>

-- 4. last_value with the default frame returns the current row. Check:
--    a "latest" column that changes on every row isn't the latest.
--    Fix: a frame to UNBOUNDED FOLLOWING.
SELECT customerID, orderID, orderTotal,
       last_value(orderID) OVER (PARTITION BY customerID
                                 ORDER BY orderDate, orderTime, orderID
                                 ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS latest_order
FROM orders
WHERE customerID = 27
ORDER BY orderDate;
-- =>

-- 5. A window over a fan-out: the join made one row per LINE, so the
--    denominator is every header total summed once per line, and a
--    3-line order is listed 3 times. Every share comes out too small
--    (order 1158: 1.008% instead of 1.592%). The shares still add up
--    to 100, so that check can't see it. Compare the row count and the
--    denominator with what you know: 529 orders, 157,078.41.
SELECT count(*) AS rows, count(DISTINCT o.orderID) AS orders,
       min(denominator) AS denominator
FROM (SELECT o.orderID, sum(o.orderTotal) OVER () AS denominator
      FROM orders o
      JOIN order_items i ON i.orderID = o.orderID
      WHERE o.status = 'completed') AS o;
-- =>

-- Fix: the window over orders, one row per order.
SELECT orderID,
       round(100 * orderTotal / sum(orderTotal) OVER (), 3) AS pct_of_revenue
FROM orders
WHERE status = 'completed'
ORDER BY orderTotal DESC, orderID
LIMIT 3;
-- =>
