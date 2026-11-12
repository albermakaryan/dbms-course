-- ============================================================
-- Lecture 6 — Part 5: Looking sideways -- lag, lead, first_value, nth_value
-- Run after Part 4.
--
-- Functions that read a value from ANOTHER row of the window.
-- (last_value has a trap of its own -- Part 6.)
-- ============================================================

-- ---- 5.1 Order over order: lag ----
-- Lusine's completed orders, each next to the one before it.
--
-- New function: lag(x) -- the value of x from the PREVIOUS row of the
-- window, in its ORDER BY. NULL when there is no previous row.
--
SELECT orderID, orderDate, orderTotal,
       lag(orderTotal) OVER w                AS previous_order,
       orderTotal - lag(orderTotal) OVER w   AS change
FROM orders
WHERE status = 'completed' AND customerID = 5
WINDOW w AS (PARTITION BY customerID ORDER BY orderDate, orderTime, orderID)
ORDER BY orderDate;
-- =>
-- The first row of every partition has no previous row: lag gives NULL,
-- and so does the change. That NULL is honest -- "there was nothing to
-- compare with."

-- Real problem: customers who went quiet
--
-- Task: customer service wants every time a customer went more than 90
-- days without ordering, and came back -- who, the gap, and when they
-- returned.
--
-- Solution: lag(orderDate) per customer gives the previous order's
-- date; subtracting gives the gap in days. Keep the gaps over 90.
WITH gaps AS (
    SELECT c.firstName, c.lastName, o.orderDate AS came_back_on,
           lag(o.orderDate) OVER w              AS previous_order,
           o.orderDate - lag(o.orderDate) OVER w AS days_quiet
    FROM orders o
    JOIN customers c ON c.customerID = o.customerID
    WINDOW w AS (PARTITION BY o.customerID ORDER BY o.orderDate, o.orderTime, o.orderID)
)
SELECT firstName, lastName, previous_order, came_back_on, days_quiet
FROM gaps
WHERE days_quiet > 90
ORDER BY days_quiet DESC;
-- =>
-- Reading the result: 7 quiet periods, 5 customers -- Lusine and Diana
-- twice each. The longest is Lusine's 148 days (5.4 below shows it from
-- the other side, with lead). Each customer's first order has no gap
-- (lag is NULL), so it can't be counted by mistake.

-- ---- 5.2 The default argument, and when it lies ----
--
-- New function: lag(x, n, d) -- the value of x from n rows back. When
-- there is no such row, d instead of NULL.
--
-- lag(x, 1, 0) fills the gap with 0. Looks tidier:
SELECT orderID, orderDate, orderTotal,
       lag(orderTotal, 1, 0) OVER w                AS previous_order,
       orderTotal - lag(orderTotal, 1, 0) OVER w   AS change
FROM orders
WHERE status = 'completed' AND customerID = 5
WINDOW w AS (PARTITION BY customerID ORDER BY orderDate, orderTime, orderID)
ORDER BY orderDate;
-- =>
-- WRONG: Lusine's first order is now a "jump" of +1598.00 -- from an order
-- that never existed.

-- Across all customers: "how much does an order change from the one
-- before, on average?"
SELECT round(avg(change_null), 2)  AS avg_change_null,
       count(change_null)          AS changes_null,
       round(avg(change_zero), 2)  AS avg_change_zero,
       count(change_zero)          AS changes_zero
FROM (SELECT orderTotal - lag(orderTotal)       OVER w AS change_null,
             orderTotal - lag(orderTotal, 1, 0) OVER w AS change_zero
      FROM orders
      WHERE status = 'completed'
      WINDOW w AS (PARTITION BY customerID ORDER BY orderDate, orderTime, orderID)) AS x;
-- =>
-- WRONG with the default: 17.23 instead of 1.42 -- twelve times the
-- real figure. 529 completed orders, 28 customers: 501 real changes,
-- plus 28 fake ones (every customer's first order counted as growth
-- from 0). avg skips NULLs, so the honest NULL kept them out; the 0
-- put them in. A default is right only when it is TRUE ("no previous
-- order" = 0 previous orders). For "previous amount" it isn't.

-- ---- 5.3 THE TRAP: lag gives the previous ROW, not the previous MONTH ----
-- "Each salesperson's completed revenue per month, and the change from
-- the month before."
WITH monthly AS (
    SELECT employeeID,
           extract(month FROM orderDate)::int AS month,
           sum(orderTotal) AS revenue
    FROM orders
    WHERE status = 'completed' AND employeeID IS NOT NULL
    GROUP BY employeeID, extract(month FROM orderDate)
)
SELECT employeeID, month, revenue,
       lag(revenue) OVER (PARTITION BY employeeID ORDER BY month) AS prev_month,
       revenue - lag(revenue) OVER (PARTITION BY employeeID ORDER BY month) AS change
FROM monthly
WHERE employeeID = 4
ORDER BY month
LIMIT 4;
-- =>
-- WRONG: Nare (employee 4) sold nothing in February -- there is no
-- February row. So March's "prev_month" is JANUARY's revenue, and
-- February's drop to 0 doesn't appear at all. A plausible table, no
-- error.

-- How many rows of the full report compare with the wrong month? lag
-- the month number too, and count the rows where it isn't month - 1.
WITH monthly AS (
    SELECT employeeID,
           extract(month FROM orderDate)::int AS month,
           sum(orderTotal) AS revenue
    FROM orders
    WHERE status = 'completed' AND employeeID IS NOT NULL
    GROUP BY employeeID, extract(month FROM orderDate)
),
compared AS (
    SELECT employeeID, month,
           lag(month) OVER (PARTITION BY employeeID ORDER BY month) AS compared_with
    FROM monthly
)
SELECT count(*) AS report_rows,
       count(*) FILTER (WHERE compared_with <> month - 1) AS wrong_month,
       12 * 8 - count(*) AS months_missing
FROM compared;
-- =>
-- 88 rows instead of 8 x 12 = 96: 8 salesperson-months had no
-- completed order and simply aren't there, and 7 rows silently compare
-- with the month two months back (Vahe's November, Nare's March,
-- Lilit's April, Arman's July and September, Marine's March and
-- October). Nothing in the output marks them.

-- FIX: build the complete calendar first -- every employee x every
-- month -- then LEFT JOIN the sales to it (Lecture 4: the side you must
-- not lose goes on the left). Missing months become real rows with 0.
WITH monthly AS (
    SELECT employeeID,
           extract(month FROM orderDate)::int AS month,
           sum(orderTotal) AS revenue
    FROM orders
    WHERE status = 'completed' AND employeeID IS NOT NULL
    GROUP BY employeeID, extract(month FROM orderDate)
),
calendar AS (
    SELECT e.employeeID, m.month
    FROM employees e
    CROSS JOIN (SELECT DISTINCT month FROM dim_date) AS m
),
full_months AS (
    SELECT cal.employeeID, cal.month, coalesce(mo.revenue, 0) AS revenue
    FROM calendar cal
    LEFT JOIN monthly mo ON mo.employeeID = cal.employeeID AND mo.month = cal.month
)
SELECT employeeID, month, revenue,
       lag(revenue) OVER (PARTITION BY employeeID ORDER BY month) AS prev_month,
       revenue - lag(revenue) OVER (PARTITION BY employeeID ORDER BY month) AS change
FROM full_months
WHERE employeeID = 4
ORDER BY month
LIMIT 4;
-- =>
-- February is back with 0, and March is compared with February. Here 0
-- IS the truth ("sold nothing that month"), unlike 5.2's fake 0.

-- Check the fixed report: 96 rows, and the zeros added nothing -- its
-- total is still the in-store completed revenue.
WITH monthly AS (
    SELECT employeeID,
           extract(month FROM orderDate)::int AS month,
           sum(orderTotal) AS revenue
    FROM orders
    WHERE status = 'completed' AND employeeID IS NOT NULL
    GROUP BY employeeID, extract(month FROM orderDate)
),
calendar AS (
    SELECT e.employeeID, m.month
    FROM employees e
    CROSS JOIN (SELECT DISTINCT month FROM dim_date) AS m
)
SELECT count(*) AS report_rows, sum(coalesce(mo.revenue, 0)) AS total
FROM calendar cal
LEFT JOIN monthly mo ON mo.employeeID = cal.employeeID AND mo.month = cal.month;
-- =>

SELECT sum(orderTotal) AS in_store_completed
FROM orders
WHERE status = 'completed' AND employeeID IS NOT NULL;
-- =>
-- 100,222.48 -- the number Lecture 4's inner join gave for "completed
-- revenue" (4.2): the online orders are left out on purpose this time.

-- ---- 5.4 lead: looking forward ----
-- Days from each of Lusine's orders to her next one (any status).
--
-- New function: lead(x) -- the same as lag, looking forward: x from
-- the NEXT row of the window. Also takes n and a default.
--
SELECT orderID, orderDate, status,
       lead(orderDate) OVER w             AS next_order,
       lead(orderDate) OVER w - orderDate AS days_to_next
FROM orders
WHERE customerID = 5
WINDOW w AS (PARTITION BY customerID ORDER BY orderDate, orderTime, orderID)
ORDER BY orderDate;
-- =>
-- The LAST row gets NULL from lead -- no next order (yet).

-- Real problem: did customers come back after a return?
--
-- Task: after a customer returns an order, do they order again? For
-- all returned orders: how many were followed by another order, after
-- how many days on average, and who has not ordered since?
--
-- Solution: lead() over each customer's orders gives the next order's
-- date; then look only at the rows that are returns.
WITH next_orders AS (
    SELECT o.customerID, o.orderID, o.orderDate, o.status,
           lead(o.orderDate) OVER (PARTITION BY o.customerID
                                   ORDER BY o.orderDate, o.orderTime, o.orderID) AS next_order
    FROM orders o
)
SELECT count(*)                              AS returns,
       count(next_order)                     AS followed_by_an_order,
       round(avg(next_order - orderDate), 1) AS avg_days_to_next
FROM next_orders
WHERE status = 'returned';
-- =>

WITH next_orders AS (
    SELECT o.customerID, o.orderID, o.orderDate, o.status,
           lead(o.orderDate) OVER (PARTITION BY o.customerID
                                   ORDER BY o.orderDate, o.orderTime, o.orderID) AS next_order
    FROM orders o
)
SELECT c.firstName, c.lastName, n.orderID, n.orderDate AS returned_order_date
FROM next_orders n
JOIN customers c ON c.customerID = n.customerID
WHERE n.status = 'returned' AND n.next_order IS NULL;
-- =>
-- Reading the result: 42 of 44 returns were followed by another order,
-- after 22 days on average. The other two, Vahan and Karen, returned
-- orders on 2024-12-27 -- and the data ends on 2024-12-31. "No next
-- order" means "not yet", not "lost". Check the dates before you call
-- a NULL from lead a lost customer.

-- ---- 5.5 first_value and nth_value ----
-- Each of Lusine's completed orders next to her FIRST completed order
-- and her SECOND one.
--
-- New function: first_value(x) -- the value of x on the first row of
-- the window frame.
--
-- New function: nth_value(x, n) -- the value of x on the n-th row of
-- the window frame; NULL if the frame has fewer than n rows so far.
--
SELECT orderID, orderDate, orderTotal,
       first_value(orderTotal) OVER w  AS first_order,
       nth_value(orderTotal, 2) OVER w AS second_order
FROM orders
WHERE status = 'completed' AND customerID = 5
WINDOW w AS (PARTITION BY customerID ORDER BY orderDate, orderTime, orderID)
ORDER BY orderDate;
-- =>
-- first_value is the same on every row. But second_order is NULL on the
-- first row -- even though the second order exists. These functions
-- see only the window FRAME, and by default the frame ends at the
-- current row: on row 1, there is no row 2 yet. That default is the
-- subject of Part 6.

-- Real problem: which channel brings better customers?
--
-- Task: marketing pays for in-store promotions and for online ads. Do
-- customers whose FIRST order was online turn out more or less
-- valuable than customers who first bought in a store?
--
-- Solution: first_value(channel) per customer gives the channel of
-- their first order (their "acquisition channel"); then group by it.
WITH acquired AS (
    SELECT customerID, status, orderTotal,
           first_value(channel) OVER (PARTITION BY customerID
                                      ORDER BY orderDate, orderTime, orderID) AS first_channel
    FROM orders
)
SELECT first_channel,
       count(DISTINCT customerID) AS customers,
       sum(orderTotal) FILTER (WHERE status = 'completed') AS revenue,
       round(sum(orderTotal) FILTER (WHERE status = 'completed')
             / count(DISTINCT customerID), 2) AS revenue_per_customer
FROM acquired
GROUP BY first_channel
ORDER BY first_channel;
-- =>
-- Reading the result: 16 customers came in through a store, 12 online.
-- Store-acquired customers spent 5,841.17 each, online-acquired
-- 5,301.64 -- about 9% less, on 28 customers in total. A hint, not a
-- proof. (first_value is safe with the default frame: the frame always
-- starts at the first row. last_value is not -- Part 6.4.)
