-- ============================================================
-- Lecture 6 — Part 2: Anatomy of OVER()
-- Run after Part 1.
--
--   function(...) OVER (PARTITION BY ...   which rows belong together
--                       ORDER BY ...       in what order, inside each group
--                       frame)             which of those rows this row sees
--
-- Built up one piece at a time. Frames get Part 6 to themselves.
-- ============================================================

-- ---- 2.1 OVER () -- the whole result is one window ----
-- Each completed order as a share of completed revenue.
SELECT orderID, orderTotal,
       sum(orderTotal) OVER ()                                   AS all_completed,
       round(100 * orderTotal / sum(orderTotal) OVER (), 2)      AS pct_of_revenue
FROM orders
WHERE status = 'completed'
ORDER BY orderTotal DESC, orderID
LIMIT 5;
-- orderid | ordertotal | all_completed | pct_of_revenue
--    1158 |    2500.00 |     157078.41 |           1.59
--    1363 |    2500.00 |     157078.41 |           1.59
--    1385 |    2500.00 |     157078.41 |           1.59
--    1314 |    2375.00 |     157078.41 |           1.51
--    1542 |    1870.00 |     157078.41 |           1.19

-- Check: the shares add up to 100, over all 529 rows.
SELECT count(*) AS rows, round(sum(pct), 2) AS total_pct
FROM (SELECT 100 * orderTotal / sum(orderTotal) OVER () AS pct
      FROM orders
      WHERE status = 'completed') AS w;
-- rows | total_pct
--  529 |    100.00

-- Real problem: which single orders matter for the whole year?
--
-- Task: Finance wants every completed order that on its own brought in
-- more than 1% of the year's completed revenue -- how many there are,
-- and how much of the year they make up together.
--
-- Solution: compute each order's share with sum() OVER () in a derived
-- table, then filter on the share outside (filtering on a window needs
-- a subquery -- Part 4.1 explains why).
SELECT count(*)                AS big_orders,
       sum(orderTotal)         AS their_revenue,
       round(sum(pct), 2)      AS pct_of_year
FROM (SELECT orderTotal,
             100 * orderTotal / sum(orderTotal) OVER () AS pct
      FROM orders
      WHERE status = 'completed') AS shares
WHERE pct > 1;
-- big_orders | their_revenue | pct_of_year
--          9 |      18412.00 |       11.72
-- Reading the result: 9 of the 529 completed orders -- under 2% of the
-- orders -- bring in 11.72% of the year's revenue.

-- ---- 2.2 PARTITION BY -- one window per group ----
-- Lusine Avetisyan (customerID 5): each completed order next to her
-- total, her average, and how far the order is from that average.
SELECT orderID, orderDate, orderTotal,
       sum(orderTotal) OVER (PARTITION BY customerID)                         AS her_total,
       round(100 * orderTotal / sum(orderTotal) OVER (PARTITION BY customerID), 1) AS pct_of_her_total,
       round(avg(orderTotal) OVER (PARTITION BY customerID), 2)               AS her_avg,
       round(orderTotal - avg(orderTotal) OVER (PARTITION BY customerID), 2)  AS diff_from_avg
FROM orders
WHERE status = 'completed' AND customerID = 5
ORDER BY orderDate;
-- orderid | orderdate  | ordertotal | her_total | pct_of_her_total | her_avg | diff_from_avg
--    1276 | 2024-07-24 |    1598.00 |   2861.90 |             55.8 |  715.48 |        882.53
--    1307 | 2024-08-10 |    1062.50 |   2861.90 |             37.1 |  715.48 |        347.03
--    1373 | 2024-09-20 |      24.40 |   2861.90 |              0.9 |  715.48 |       -691.08
--    1577 | 2024-12-23 |     177.00 |   2861.90 |              6.2 |  715.48 |       -538.48

-- The five aggregates all work as window functions:
SELECT orderID, orderTotal,
       count(*)        OVER (PARTITION BY customerID) AS n,
       min(orderTotal) OVER (PARTITION BY customerID) AS smallest,
       max(orderTotal) OVER (PARTITION BY customerID) AS biggest
FROM orders
WHERE status = 'completed' AND customerID = 5
ORDER BY orderDate;
-- orderid | ordertotal | n | smallest | biggest
--    1276 |    1598.00 | 4 |    24.40 | 1598.00
--    1307 |    1062.50 | 4 |    24.40 | 1598.00
--    1373 |      24.40 | 4 |    24.40 | 1598.00
--    1577 |     177.00 | 4 |    24.40 | 1598.00

-- Real problem: customers who depend on one big purchase
--
-- Task: Marketing wants the customers for whom a single order is more
-- than half of everything they spent with us -- "one-off buyers" who
-- need a reason to come back.
--
-- Solution: each order's share of ITS customer's total, with PARTITION
-- BY customerID; keep the orders above 50%.
SELECT c.firstName, c.lastName, s.orderID, s.orderTotal, s.customer_total,
       round(100 * s.orderTotal / s.customer_total, 1) AS pct_of_customer
FROM (SELECT customerID, orderID, orderTotal,
             sum(orderTotal) OVER (PARTITION BY customerID) AS customer_total
      FROM orders
      WHERE status = 'completed') AS s
JOIN customers c ON c.customerID = s.customerID
WHERE s.orderTotal > 0.5 * s.customer_total
ORDER BY pct_of_customer DESC;
-- firstname |   lastname   | orderid | ordertotal | customer_total | pct_of_customer
-- Diana     | Aleksanyan   |    1246 |    1780.00 |        2352.80 |            75.7
-- Gayane    | Mnatsakanyan |    1363 |    2500.00 |        3742.99 |            66.8
-- Lusine    | Avetisyan    |    1276 |    1598.00 |        2861.90 |            55.8
-- Mher      | Sargsyan     |    1482 |    1187.50 |        2279.24 |            52.1
-- Reading the result: 4 customers. Lusine is one of them -- her order
-- 1276 is the 55.8% from the example above.

-- ---- 2.3 ORDER BY inside OVER -- an order within each window ----
-- Add ORDER BY and sum() becomes a RUNNING sum: each row sees the rows
-- up to itself. (Why "up to itself" is the default, and where that
-- default bites, is Part 6.)
SELECT orderID, orderDate, orderTotal,
       sum(orderTotal) OVER (PARTITION BY customerID
                             ORDER BY orderDate, orderID) AS running_total
FROM orders
WHERE status = 'completed' AND customerID = 5
ORDER BY orderDate;
-- orderid | orderdate  | ordertotal | running_total
--    1276 | 2024-07-24 |    1598.00 |       1598.00
--    1307 | 2024-08-10 |    1062.50 |       2660.50
--    1373 | 2024-09-20 |      24.40 |       2684.90
--    1577 | 2024-12-23 |     177.00 |       2861.90

-- **Why ", orderID" in the window's ORDER BY?** Lusine never ordered
-- twice on one day, so for her it changes nothing. Davit (customer 2)
-- did, four times. Here are his orders around 12 November, with the
-- running total computed both ways. (The date filter is OUTSIDE, in a
-- subquery, so both totals still count from January -- a WHERE on the
-- dates would restart them. Part 2.5 explains why.)
SELECT orderID, orderDate, orderTime, orderTotal, by_date_only, by_date_and_id
FROM (SELECT orderID, orderDate, orderTime, orderTotal,
             sum(orderTotal) OVER (PARTITION BY customerID
                                   ORDER BY orderDate)          AS by_date_only,
             sum(orderTotal) OVER (PARTITION BY customerID
                                   ORDER BY orderDate, orderID) AS by_date_and_id
      FROM orders
      WHERE status = 'completed' AND customerID = 2) AS running
WHERE orderDate BETWEEN '2024-11-11' AND '2024-11-13'
ORDER BY orderDate, orderID;
-- orderid | orderdate  | ordertime | ordertotal | by_date_only | by_date_and_id
--    1466 | 2024-11-12 | 06:34:35  |      25.50 |      5607.71 |        5551.47
--    1467 | 2024-11-12 | 12:44:14  |      38.00 |      5607.71 |        5589.47
--    1471 | 2024-11-12 | 18:05:39  |      18.24 |      5607.71 |        5607.71
-- **ORDER BY orderDate only:** Davit's three orders on 12 November all
-- show the same 5607.71. Rows with an equal ORDER BY value are "peers",
-- and the default frame takes all peers at once -- so order 1466's
-- "running total" already includes 1467 and 1471, which came later
-- that day. The total looks stuck for three rows.
--
-- **ORDER BY orderDate, orderID:** no two rows share a position any
-- more, so each row adds only itself: 5551.47, 5589.47, 5607.71. The
-- day still ends on 5607.71 -- only the rows in between change.
--
-- How much of Davit's history is affected?
SELECT count(*)                                              AS orders,
       count(*) FILTER (WHERE by_date_only <> by_date_and_id) AS different_running_total
FROM (SELECT sum(orderTotal) OVER (PARTITION BY customerID
                                   ORDER BY orderDate)          AS by_date_only,
             sum(orderTotal) OVER (PARTITION BY customerID
                                   ORDER BY orderDate, orderID) AS by_date_and_id
      FROM orders
      WHERE status = 'completed' AND customerID = 2) AS running;
-- orders | different_running_total
--     43 |                       5
-- 5 of his 43 completed orders: the earlier orders on each day with
-- more than one order. The rest match, which is why the tie-breaker
-- seems to "make no difference" until a day with two orders comes
-- along. The rule: add a unique column (orderID) at the end of a
-- window's ORDER BY whenever the order can have ties. orderTime is the
-- more meaningful choice within a day; orderID guarantees uniqueness.
-- Part 6.2 shows the same effect on the whole year's running total.

-- Real problem: when did each customer reach Gold status?
--
-- Task: the loyalty programme makes a customer "Gold" on the day their
-- completed spending, added up order by order, first reaches 5,000.
-- For each customer who got there: on which date?
--
-- Solution: a running total per customer (PARTITION BY customerID,
-- ORDER BY date, time, id); then, per customer, the first date where it
-- is 5,000 or more. (The ORDER BY is unique -- no ties -- so the
-- default frame is safe here; Part 6 explains why that matters.)
WITH running AS (
    SELECT customerID, orderDate,
           sum(orderTotal) OVER (PARTITION BY customerID
                                 ORDER BY orderDate, orderTime, orderID) AS spent_so_far
    FROM orders
    WHERE status = 'completed'
)
SELECT c.firstName, c.lastName, min(r.orderDate) AS gold_since
FROM running r
JOIN customers c ON c.customerID = r.customerID
WHERE r.spent_so_far >= 5000
GROUP BY c.customerID, c.firstName, c.lastName
ORDER BY gold_since;
-- firstname |   lastname   | gold_since
-- Aram      | Vardanyan    | 2024-04-26
-- Karen     | Khachatryan  | 2024-06-12
-- Artur     | Baghdasaryan | 2024-06-12
-- Hasmik    | Zakaryan     | 2024-08-13
-- Vahan     | Torosyan     | 2024-08-14
-- Lilit     | Hovhannisyan | 2024-09-23
-- Armen     | Gevorgyan    | 2024-10-02
-- Davit     | Petrosyan    | 2024-10-04
-- Gevorg    | Kocharyan    | 2024-11-07
-- Ruben     | Asatryan     | 2024-11-08
-- Sona      | Karapetyan   | 2024-11-12
-- Anna      | Sargsyan     | 2024-11-14
-- Tigran    | Grigoryan    | 2024-11-14
-- Narek     | Manukyan     | 2024-11-22
-- Reading the result: 14 of the 28 customers reached Gold during the
-- year, the first on 2024-04-26 and the last on 2024-11-22.

-- ---- 2.4 THE TRAP: ORDER BY inside OVER is not the query's ORDER BY ----
-- "The first five completed orders of the year, numbered."
-- No outer ORDER BY -- the window is already ordered by date...
--
-- New function: row_number() -- numbers the rows of each window 1, 2,
-- 3 ... in the order of the window's ORDER BY. Every row gets a
-- different number, even rows that tie, and which of two tied rows
-- comes first is not guaranteed.
--
SELECT orderID, orderDate, orderTotal,
       row_number() OVER (ORDER BY orderDate, orderID) AS nr
FROM orders
WHERE status = 'completed'
LIMIT 5;
-- orderid | orderdate  | ordertotal | nr
--    1001 | 2024-01-01 |     211.65 |  1
--    1002 | 2024-01-02 |     249.00 |  2
--    1003 | 2024-01-02 |     747.00 |  3
--    1004 | 2024-01-04 |      59.00 |  4
--    1005 | 2024-01-04 |      38.90 |  5
-- Looks right -- by luck. To number the rows, PostgreSQL sorted them by
-- date, and nothing came after the sort to change their order.

-- A colleague adds one column: how big is each order, compared with
-- all the others? Same WHERE, same window for nr, same LIMIT.
--
-- New function: rank() -- the row's position in the window's ORDER BY.
-- Tied rows share a position, and the positions after a tie are
-- skipped: 1, 2, 2, 4.
--
SELECT orderID, orderDate, orderTotal,
       rank()       OVER (ORDER BY orderTotal DESC)  AS size_rank,
       row_number() OVER (ORDER BY orderDate, orderID) AS nr
FROM orders
WHERE status = 'completed'
LIMIT 5;
-- orderid | orderdate  | ordertotal | size_rank | nr
--    1385 | 2024-09-26 |    2500.00 |         1 | 341
--    1158 | 2024-04-26 |    2500.00 |         1 | 135
--    1363 | 2024-09-13 |    2500.00 |         1 | 321
--    1314 | 2024-08-13 |    2375.00 |         4 | 276
--    1542 | 2024-12-11 |    1870.00 |         5 | 481
-- WRONG: these are not the first five orders of the year (look at nr
-- and orderDate). The rows now come out in whichever order the LAST
-- window sort left them -- here, by size. No error.

-- FIX: the order you see is decided by the query's own ORDER BY, and
-- nothing else.
SELECT orderID, orderDate, orderTotal,
       rank()       OVER (ORDER BY orderTotal DESC)  AS size_rank,
       row_number() OVER (ORDER BY orderDate, orderID) AS nr
FROM orders
WHERE status = 'completed'
ORDER BY nr
LIMIT 5;
-- orderid | orderdate  | ordertotal | size_rank | nr
--    1001 | 2024-01-01 |     211.65 |       204 |  1
--    1002 | 2024-01-02 |     249.00 |       184 |  2
--    1003 | 2024-01-02 |     747.00 |        63 |  3
--    1004 | 2024-01-04 |      59.00 |       390 |  4
--    1005 | 2024-01-04 |      38.90 |       429 |  5
-- The same family as Lecture 5's "I sorted it in the CTE" (5.4): an
-- ORDER BY anywhere but the end of the outer query sorts something,
-- but not your output.

-- ---- 2.5 When do window functions run? ----
--   FROM -> WHERE -> GROUP BY -> HAVING -> WINDOW FUNCTIONS
--        -> SELECT list -> DISTINCT -> ORDER BY -> LIMIT
-- A window sees only the rows that survived WHERE (and GROUP BY).

-- "What share of all completed revenue did Lusine's orders bring in?"
SELECT orderID, orderTotal,
       round(100 * orderTotal / sum(orderTotal) OVER (), 2) AS pct_of_revenue
FROM orders
WHERE status = 'completed' AND customerID = 5
ORDER BY orderDate;
-- orderid | ordertotal | pct_of_revenue
--    1276 |    1598.00 |          55.84
--    1307 |    1062.50 |          37.13
--    1373 |      24.40 |           0.85
--    1577 |     177.00 |           6.18
-- WRONG: the shares add up to 100 -- these are shares of LUSINE'S
-- revenue. WHERE removed everyone else before the window ran, so
-- sum() OVER () only saw her 4 orders. No error.

-- FIX: compute the window over all completed orders first, filter
-- after (a derived table, Lecture 5 1.4; Part 4 explains why this is
-- THE pattern):
SELECT orderID, orderTotal, pct_of_revenue
FROM (SELECT orderID, customerID, orderDate, orderTotal,
             round(100 * orderTotal / sum(orderTotal) OVER (), 2) AS pct_of_revenue
      FROM orders
      WHERE status = 'completed') AS w
WHERE customerID = 5
ORDER BY orderDate;
-- orderid | ordertotal | pct_of_revenue
--    1276 |    1598.00 |           1.02
--    1307 |    1062.50 |           0.68
--    1373 |      24.40 |           0.02
--    1577 |     177.00 |           0.11
-- Together 1.82% of completed revenue (2,861.90 of 157,078.41).

-- ---- 2.6 Windows over aggregates ----
-- Windows run AFTER GROUP BY, so they can work on the groups:
-- rank customers by their completed revenue, with their share.
SELECT customerID,
       sum(orderTotal)                                  AS revenue,
       rank() OVER (ORDER BY sum(orderTotal) DESC)      AS revenue_rank,
       round(100 * sum(orderTotal) / sum(sum(orderTotal)) OVER (), 1) AS pct_of_all
FROM orders
WHERE status = 'completed'
GROUP BY customerID
ORDER BY revenue_rank
LIMIT 5;
-- customerid | revenue  | revenue_rank | pct_of_all
--          8 | 14625.38 |            1 |        9.3
--         20 | 11235.95 |            2 |        7.2
--         12 | 10028.09 |            3 |        6.4
--         10 |  9410.64 |            4 |        6.0
--         14 |  8925.87 |            5 |        5.7
-- sum(sum(orderTotal)) OVER () reads strangely but is legal: the inner
-- sum is the GROUP BY aggregate (one per customer), the outer sum adds
-- those 28 group totals up across the window. Readable alternative:
-- aggregate in a CTE first, window over the CTE in the outer query.
WITH per_customer AS (
    SELECT customerID, sum(orderTotal) AS revenue
    FROM orders
    WHERE status = 'completed'
    GROUP BY customerID
)
SELECT customerID, revenue,
       rank() OVER (ORDER BY revenue DESC)                  AS revenue_rank,
       round(100 * revenue / sum(revenue) OVER (), 1)       AS pct_of_all
FROM per_customer
ORDER BY revenue_rank
LIMIT 5;
-- customerid | revenue  | revenue_rank | pct_of_all
--          8 | 14625.38 |            1 |        9.3
--         20 | 11235.95 |            2 |        7.2
--         12 | 10028.09 |            3 |        6.4
--         10 |  9410.64 |            4 |        6.0
--         14 |  8925.87 |            5 |        5.7

-- ---- 2.7 Named windows ----
-- Four functions over the same window: write the window once.
SELECT orderID, orderTotal,
       count(*)                  OVER w AS n,
       sum(orderTotal)           OVER w AS her_total,
       round(avg(orderTotal) OVER w, 2) AS her_avg,
       max(orderTotal)           OVER w AS biggest
FROM orders
WHERE status = 'completed' AND customerID = 5
WINDOW w AS (PARTITION BY customerID)
ORDER BY orderDate;
-- orderid | ordertotal | n | her_total | her_avg | biggest
--    1276 |    1598.00 | 4 |   2861.90 |  715.48 | 1598.00
--    1307 |    1062.50 | 4 |   2861.90 |  715.48 | 1598.00
--    1373 |      24.40 | 4 |   2861.90 |  715.48 | 1598.00
--    1577 |     177.00 | 4 |   2861.90 |  715.48 | 1598.00
