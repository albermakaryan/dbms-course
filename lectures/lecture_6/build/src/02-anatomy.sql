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
-- =>

-- Check: the shares add up to 100, over all 529 rows.
SELECT count(*) AS rows, round(sum(pct), 2) AS total_pct
FROM (SELECT 100 * orderTotal / sum(orderTotal) OVER () AS pct
      FROM orders
      WHERE status = 'completed') AS w;
-- =>

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
-- =>
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
-- =>

-- The five aggregates all work as window functions:
SELECT orderID, orderTotal,
       count(*)        OVER (PARTITION BY customerID) AS n,
       min(orderTotal) OVER (PARTITION BY customerID) AS smallest,
       max(orderTotal) OVER (PARTITION BY customerID) AS biggest
FROM orders
WHERE status = 'completed' AND customerID = 5
ORDER BY orderDate;
-- =>

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
-- =>
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
-- =>

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
-- =>
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
-- =>
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
-- =>
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
-- =>
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
-- =>
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
-- =>
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
-- =>
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
-- =>
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
-- =>
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
-- =>

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
-- =>
