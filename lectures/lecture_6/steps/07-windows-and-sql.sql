-- ============================================================
-- Lecture 6 — Part 7: Windows meeting the rest of SQL
-- Run after Part 6.
--
-- NULLs, joins, FILTER, the older alternatives, and the star schema.
-- Every trap from Lectures 4 and 5 is still there -- a window does not
-- protect you from any of them.
-- ============================================================

-- ---- 7.1 THE TRAP: NULL is a partition too ----
-- "Rank our salespeople by number of orders."
SELECT o.employeeID, e.firstName,
       count(*)                              AS orders,
       rank() OVER (ORDER BY count(*) DESC)  AS sales_rank
FROM orders o
LEFT JOIN employees e ON e.employeeID = o.employeeID
GROUP BY o.employeeID, e.firstName
ORDER BY sales_rank
LIMIT 4;
-- employeeid | firstname | orders | sales_rank
--            |           |    181 |          1
--          2 | Ani       |     91 |          2
--          1 | Gor       |     90 |          3
--          5 | Hayk      |     65 |          4
-- WRONG: the "best salesperson", with 181 orders, has no ID and no
-- name -- it's the 181 online orders. GROUP BY and PARTITION BY put all
-- NULLs into ONE group, so "no employee" is ranked as if it were one
-- person, and every real salesperson drops a place. No error.

-- The same thing inside PARTITION BY: "each salesperson's biggest
-- completed order" returns 9 rows for 8 salespeople.
SELECT count(*) AS rows, count(employeeID) AS with_an_employee
FROM (SELECT employeeID,
             row_number() OVER (PARTITION BY employeeID
                                ORDER BY orderTotal DESC, orderID) AS rn
      FROM orders
      WHERE status = 'completed') AS w
WHERE rn = 1;
-- rows | with_an_employee
--    9 |                8
-- WRONG: 9 "salespeople" -- the ninth is the online shop, employeeID
-- NULL.

-- FIX, option A -- the question is about PEOPLE: take the online
-- orders out, on purpose, and say so.
SELECT o.employeeID, e.firstName,
       count(*)                              AS orders,
       rank() OVER (ORDER BY count(*) DESC)  AS sales_rank
FROM orders o
JOIN employees e ON e.employeeID = o.employeeID   -- inner join: online orders excluded deliberately
GROUP BY o.employeeID, e.firstName
ORDER BY sales_rank
LIMIT 4;
-- employeeid | firstname | orders | sales_rank
--          2 | Ani       |     91 |          1
--          1 | Gor       |     90 |          2
--          5 | Hayk      |     65 |          3
--          4 | Nare      |     55 |          4

-- FIX, option B -- the question is about CHANNELS of sale: keep the
-- online orders, but as a labelled row, not a nameless one (the same
-- idea as Lecture 4's '(online)' unknown member in dim_employee).
SELECT coalesce(e.firstName, '(online)') AS sold_by,
       count(*)                              AS orders,
       rank() OVER (ORDER BY count(*) DESC)  AS sales_rank
FROM orders o
LEFT JOIN employees e ON e.employeeID = o.employeeID
GROUP BY o.employeeID, e.firstName
ORDER BY sales_rank
LIMIT 4;
-- sold_by  | orders | sales_rank
-- (online) |    181 |          1
-- Ani      |     91 |          2
-- Gor      |     90 |          3
-- Hayk     |     65 |          4
-- Neither fix is "right" in general. Decide which question you are
-- answering, then write it so the reader can see the decision.

-- ---- 7.2 NULLS FIRST / NULLS LAST inside OVER ----
-- "Each customer's best-rated completed order" -- for a thank-you note.
-- 207 of the 529 completed orders have no rating.
SELECT count(*) FILTER (WHERE rating IS NULL) AS best_is_unrated,
       count(*)                               AS customers
FROM (SELECT customerID, rating,
             row_number() OVER (PARTITION BY customerID
                                ORDER BY rating DESC, orderID) AS rn
      FROM orders
      WHERE status = 'completed') AS w
WHERE rn = 1;
-- best_is_unrated | customers
--              28 |        28
-- WRONG: in PostgreSQL, NULL sorts as larger than any value, so with
-- DESC the unrated orders come FIRST. Every one of the 28 customers
-- has at least one unrated completed order, so for all 28 the "best-
-- rated order" is one they never rated. No error.

-- FIX: say where the NULLs go.
SELECT count(*) FILTER (WHERE rating IS NULL) AS best_is_unrated,
       count(*)                               AS customers
FROM (SELECT customerID, rating,
             row_number() OVER (PARTITION BY customerID
                                ORDER BY rating DESC NULLS LAST, orderID) AS rn
      FROM orders
      WHERE status = 'completed') AS w
WHERE rn = 1;
-- best_is_unrated | customers
--               0 |        28

-- Window aggregates skip NULLs, as plain aggregates do (Lecture 4,
-- 4.6). count(*) vs count(rating) in the same window shows how many
-- ratings an average is built on:
SELECT orderID, rating,
       count(*)      OVER w           AS orders,
       count(rating) OVER w           AS rated,
       round(avg(rating) OVER w, 2)   AS avg_rating
FROM orders
WHERE status = 'completed' AND customerID = 5
WINDOW w AS (PARTITION BY customerID)
ORDER BY orderDate;
-- orderid | rating | orders | rated | avg_rating
--    1276 |      4 |      4 |     3 |       3.67
--    1307 |      3 |      4 |     3 |       3.67
--    1373 |        |      4 |     3 |       3.67
--    1577 |      4 |      4 |     3 |       3.67
-- Lusine's average, 3.67, is built on 3 ratings, not her 4 orders:
-- avg skipped the NULL. count(rating) next to count(*) is how you find
-- out how much an average stands on.

-- ---- 7.3 A window does not repair a fan-out ----
-- Each order LINE next to its customer's completed revenue -- written
-- on the joined lines, with the header's orderTotal:
SELECT o.orderID, i.productID, i.lineTotal, o.orderTotal,
       sum(o.orderTotal) OVER (PARTITION BY o.customerID) AS customer_revenue
FROM orders o
JOIN order_items i ON i.orderID = o.orderID
WHERE o.status = 'completed' AND o.customerID = 5
ORDER BY o.orderDate, i.productID;
-- orderid | productid | linetotal | ordertotal | customer_revenue
--    1276 |        10 |   1598.00 |    1598.00 |          5011.30
--    1307 |        10 |    799.00 |    1062.50 |          5011.30
--    1307 |        24 |     14.50 |    1062.50 |          5011.30
--    1307 |        25 |    249.00 |    1062.50 |          5011.30
--    1373 |        24 |     14.50 |      24.40 |          5011.30
--    1373 |        32 |      9.90 |      24.40 |          5011.30
--    1577 |        28 |    177.00 |     177.00 |          5011.30
-- WRONG: Lusine's completed revenue is 2861.90 (Part 2.2), not
-- 5011.30. Order 1307 has three lines and 1373 has two, so 1307's
-- total was counted three times and 1373's twice -- Lecture 5's cart
-- fan-out (2.3), now inside a window. The window summed exactly the
-- rows it was given; the join had already multiplied them.

-- FIX: sum what lives on the line.
SELECT o.orderID, i.productID, i.lineTotal, o.orderTotal,
       sum(i.lineTotal) OVER (PARTITION BY o.customerID) AS customer_revenue
FROM orders o
JOIN order_items i ON i.orderID = o.orderID
WHERE o.status = 'completed' AND o.customerID = 5
ORDER BY o.orderDate, i.productID;
-- orderid | productid | linetotal | ordertotal | customer_revenue
--    1276 |        10 |   1598.00 |    1598.00 |          2861.90
--    1307 |        10 |    799.00 |    1062.50 |          2861.90
--    1307 |        24 |     14.50 |    1062.50 |          2861.90
--    1307 |        25 |    249.00 |    1062.50 |          2861.90
--    1373 |        24 |     14.50 |      24.40 |          2861.90
--    1373 |        32 |      9.90 |      24.40 |          2861.90
--    1577 |        28 |    177.00 |     177.00 |          2861.90

-- The check, over all customers: rows vs orders, and the total.
SELECT count(*) AS line_rows, count(DISTINCT o.orderID) AS orders,
       sum(o.orderTotal) AS header_total_over_lines,
       sum(i.lineTotal)  AS line_total
FROM orders o
JOIN order_items i ON i.orderID = o.orderID
WHERE o.status = 'completed';
-- line_rows | orders | header_total_over_lines | line_total
--       844 |    529 |               247923.72 |  157078.41
-- 844 rows for 529 orders, and Lecture 5's 247,923.72 again. Count
-- rows against orders BEFORE you put a window on top of a join.

-- ---- 7.4 FILTER with window aggregates ----
-- Lecture 4's FILTER works inside a window too: each of Lusine's
-- orders next to how many of her orders were completed / returned.
SELECT orderID, orderDate, status, orderTotal,
       count(*)        FILTER (WHERE status = 'completed') OVER w AS completed,
       count(*)        FILTER (WHERE status = 'returned')  OVER w AS returned,
       sum(orderTotal) FILTER (WHERE status = 'completed') OVER w AS completed_revenue
FROM orders
WHERE customerID = 5
WINDOW w AS (PARTITION BY customerID)
ORDER BY orderDate;
-- orderid | orderdate  |  status   | ordertotal | completed | returned | completed_revenue
--    1069 | 2024-02-27 | returned  |     387.90 |         4 |        1 |           2861.90
--    1276 | 2024-07-24 | completed |    1598.00 |         4 |        1 |           2861.90
--    1307 | 2024-08-10 | completed |    1062.50 |         4 |        1 |           2861.90
--    1373 | 2024-09-20 | completed |      24.40 |         4 |        1 |           2861.90
--    1577 | 2024-12-23 | completed |     177.00 |         4 |        1 |           2861.90
-- FILTER works on aggregates used as windows (sum, count, avg...), not
-- on row_number, rank, lag and the other window-only functions.

-- Real problem: customers who return a lot
--
-- Task: customer service wants the customers who returned at least 15%
-- of their orders, with the numbers behind it.
--
-- Solution: count(*) FILTER (WHERE status = 'returned') and count(*)
-- over each customer's orders, on every order row; then one row per
-- customer with DISTINCT.
WITH rates AS (
    SELECT customerID,
           count(*) FILTER (WHERE status = 'returned') OVER w AS returned,
           count(*) OVER w                                     AS orders
    FROM orders
    WINDOW w AS (PARTITION BY customerID)
)
SELECT DISTINCT c.firstName, c.lastName, r.returned, r.orders,
       round(100.0 * r.returned / r.orders, 1) AS pct_returned
FROM rates r
JOIN customers c ON c.customerID = r.customerID
WHERE r.returned >= 0.15 * r.orders
ORDER BY pct_returned DESC, c.lastName;
-- firstname |   lastname   | returned | orders | pct_returned
-- Diana     | Aleksanyan   |        1 |      4 |         25.0
-- Arpine    | Simonyan     |        2 |      8 |         25.0
-- Lusine    | Avetisyan    |        1 |      5 |         20.0
-- Narek     | Manukyan     |        5 |     29 |         17.2
-- Gayane    | Mnatsakanyan |        1 |      6 |         16.7
-- Reading the result: 5 customers. Read the counts, not just the
-- percentage: Diana's 25% is 1 return out of 4 orders, Narek's 17.2% is
-- 5 out of 29. A rate built on 4 orders says very little. (A GROUP BY
-- would give the same list; the window version keeps every order row,
-- so the same CTE can also flag each order for review.)

-- ---- 7.5 Window vs self-join vs correlated subquery ----
-- "Completed orders bigger than their customer's average order" --
-- three ways. Each method's result is (orderID, avg rounded to cents).
-- Proof by EXCEPT in both directions, for both pairs.
WITH by_window AS (
    SELECT orderID, round(cust_avg, 2) AS cust_avg
    FROM (SELECT orderID, orderTotal,
                 avg(orderTotal) OVER (PARTITION BY customerID) AS cust_avg
          FROM orders
          WHERE status = 'completed') AS w
    WHERE orderTotal > cust_avg
),
by_join AS (
    SELECT o.orderID, round(a.cust_avg, 2) AS cust_avg
    FROM orders o
    JOIN (SELECT customerID, avg(orderTotal) AS cust_avg
          FROM orders
          WHERE status = 'completed'
          GROUP BY customerID) AS a ON a.customerID = o.customerID
    WHERE o.status = 'completed'
      AND o.orderTotal > a.cust_avg
),
by_subquery AS (
    SELECT o.orderID,
           round((SELECT avg(o2.orderTotal) FROM orders o2
                  WHERE o2.customerID = o.customerID AND o2.status = 'completed'), 2) AS cust_avg
    FROM orders o
    WHERE o.status = 'completed'
      AND o.orderTotal > (SELECT avg(o2.orderTotal) FROM orders o2
                          WHERE o2.customerID = o.customerID AND o2.status = 'completed')
)
SELECT (SELECT count(*) FROM by_window) AS rows_window,
       (SELECT count(*) FROM (SELECT * FROM by_window   EXCEPT SELECT * FROM by_join)     x) AS window_not_join,
       (SELECT count(*) FROM (SELECT * FROM by_join     EXCEPT SELECT * FROM by_window)   x) AS join_not_window,
       (SELECT count(*) FROM (SELECT * FROM by_window   EXCEPT SELECT * FROM by_subquery) x) AS window_not_sub,
       (SELECT count(*) FROM (SELECT * FROM by_subquery EXCEPT SELECT * FROM by_window)   x) AS sub_not_window;
-- rows_window | window_not_join | join_not_window | window_not_sub | sub_not_window
--         172 |               0 |               0 |              0 |              0
-- Same rows, three ways. The window version filters completed orders
-- ONCE; the other two must repeat the status filter in two places,
-- and forgetting one of them is a silent bug of its own.

-- ---- 7.6 Windows on the star schema ----
-- Monthly completed revenue from fact_sales, with a running total
-- across the year. Lecture 4 built the star; dim_date has the months.
SELECT d.month, d.monthName,
       sum(f.revenue) AS revenue,
       sum(sum(f.revenue)) OVER (ORDER BY d.month
                                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_revenue
FROM fact_sales f
JOIN dim_date d ON d.dateKey = f.dateKey
WHERE f.status = 'completed'
GROUP BY d.month, d.monthName
ORDER BY d.month;
-- month | monthname | revenue  | running_revenue
--     1 | Jan       |  9902.54 |         9902.54
--     2 | Feb       |  6907.59 |        16810.13
--     3 | Mar       |  6682.49 |        23492.62
--     4 | Apr       | 14855.21 |        38347.83
--     5 | May       | 14680.07 |        53027.90
--     6 | Jun       |  9687.91 |        62715.81
--     7 | Jul       | 12943.77 |        75659.58
--     8 | Aug       | 12457.07 |        88116.65
--     9 | Sep       | 14748.17 |       102864.82
--    10 | Oct       | 10956.11 |       113820.93
--    11 | Nov       | 15381.65 |       129202.58
--    12 | Dec       | 27875.83 |       157078.41
-- December's running total is 157,078.41 -- the completed revenue.
-- (GROUP BY month first, so there is one row per month and no peers:
-- ROWS and RANGE agree here. Writing ROWS anyway costs nothing.)

-- Rank products inside their category by completed revenue, with each
-- product's share of its category.
SELECT p.category, p.productName,
       sum(f.revenue) AS revenue,
       rank() OVER (PARTITION BY p.category ORDER BY sum(f.revenue) DESC) AS rank_in_category,
       round(100 * sum(f.revenue) / sum(sum(f.revenue)) OVER (PARTITION BY p.category), 1) AS pct_of_category
FROM fact_sales f
JOIN dim_product p ON p.productKey = f.productKey
WHERE f.status = 'completed' AND p.category IN ('Laptops', 'Phones')
GROUP BY p.category, p.productName
ORDER BY p.category, rank_in_category;
-- category |    productname     | revenue  | rank_in_category | pct_of_category
-- Laptops  | ThinkPad X1 Carbon | 26937.50 |                1 |            50.4
-- Laptops  | MacBook Air 13     | 11220.00 |                2 |            21.0
-- Laptops  | ZenBook 14         |  7876.50 |                3 |            14.7
-- Laptops  | Aspire 5           |  7378.00 |                4 |            13.8
-- Phones   | iPhone 15          | 11705.35 |                1 |            45.0
-- Phones   | Galaxy S24         |  7409.40 |                2 |            28.5
-- Phones   | Pixel 8            |  4163.05 |                3 |            16.0
-- Phones   | Redmi Note 13      |  2714.10 |                4 |            10.4

-- Check the star version against the known total: every category's
-- products, every share. The category totals must add up to 157,078.41,
-- and each category's shares to 100.
WITH by_product AS (
    SELECT p.category, p.productKey, sum(f.revenue) AS revenue
    FROM fact_sales f
    JOIN dim_product p ON p.productKey = f.productKey
    WHERE f.status = 'completed'
    GROUP BY p.category, p.productKey
),
shares AS (
    SELECT category, revenue,
           100 * revenue / sum(revenue) OVER (PARTITION BY category) AS pct_of_category
    FROM by_product
)
SELECT count(*) AS products_sold,
       count(DISTINCT category) AS categories,
       sum(revenue) AS total,
       min(round(cat_pct, 6)) AS min_category_pct,
       max(round(cat_pct, 6)) AS max_category_pct
FROM (SELECT category, revenue,
             sum(pct_of_category) OVER (PARTITION BY category) AS cat_pct
      FROM shares) AS s;
-- products_sold | categories |   total   | min_category_pct | max_category_pct
--            36 |         12 | 157078.41 |       100.000000 |       100.000000
-- 36 products in 12 categories -- Ergonomic Chair Pro (Chairs) never
-- sold, so it has no fact rows. Total 157,078.41; every category's
-- shares add up to 100.
