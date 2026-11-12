-- ============================================================
-- Lecture 6 — Part 6: Frames
-- Run after Part 5.
--
-- The FRAME is the part of the partition that the function sees for
-- the current row. It moves as the current row moves.
--
--   ROWS   BETWEEN 2 PRECEDING AND CURRENT ROW     count physical rows
--   RANGE  BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
--                                                  by VALUE of the ORDER BY:
--                                                  rows with an equal value
--                                                  ("peers") are all in or all out
--   GROUPS BETWEEN 1 PRECEDING AND CURRENT ROW     count groups of peers (PG 11+)
--
--   start/end: UNBOUNDED PRECEDING, n PRECEDING, CURRENT ROW,
--              n FOLLOWING, UNBOUNDED FOLLOWING
--
-- THE DEFAULTS (this is the whole part):
--   no ORDER BY in OVER  -> the frame is the whole partition
--   ORDER BY in OVER     -> RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
-- ============================================================

-- ---- 6.1 No ORDER BY vs ORDER BY: the frame changes ----
SELECT orderID, orderDate, orderTotal,
       sum(orderTotal) OVER (PARTITION BY customerID)                     AS whole_partition,
       sum(orderTotal) OVER (PARTITION BY customerID
                             ORDER BY orderDate, orderTime, orderID)      AS up_to_this_row
FROM orders
WHERE status = 'completed' AND customerID = 5
ORDER BY orderDate;
-- orderid | orderdate  | ordertotal | whole_partition | up_to_this_row
--    1276 | 2024-07-24 |    1598.00 |         2861.90 |        1598.00
--    1307 | 2024-08-10 |    1062.50 |         2861.90 |        2660.50
--    1373 | 2024-09-20 |      24.40 |         2861.90 |        2684.90
--    1577 | 2024-12-23 |     177.00 |         2861.90 |        2861.90
-- Same function, same partition. Adding ORDER BY quietly changed the
-- frame from "all of Lusine's orders" to "her orders up to this one".

-- ---- 6.2 A running total for the year ----
SELECT orderID, orderDate, orderTotal,
       sum(orderTotal) OVER (ORDER BY orderDate) AS running_total
FROM orders
WHERE status = 'completed'
ORDER BY orderDate, orderID
LIMIT 8;
-- orderid | orderdate  | ordertotal | running_total
--    1001 | 2024-01-01 |     211.65 |        211.65
--    1002 | 2024-01-02 |     249.00 |       1207.65
--    1003 | 2024-01-02 |     747.00 |       1207.65
--    1004 | 2024-01-04 |      59.00 |       1305.55
--    1005 | 2024-01-04 |      38.90 |       1305.55
--    1006 | 2024-01-06 |     128.00 |       1433.55
--    1007 | 2024-01-08 |      74.00 |       1894.55
--    1008 | 2024-01-08 |     387.00 |       1894.55
-- WRONG (look closely): orders 1002 and 1003 show the SAME running total,
-- 1207.65 -- and so do 1004/1005 and 1007/1008. Order 1002's total is
-- already counting 1003's 747.00. The default frame is RANGE ... CURRENT
-- ROW, and RANGE includes every PEER of the current row: every order
-- with the same orderDate. The figure looks stalled or duplicated.

-- How much of the column is affected?
SELECT count(*)                     AS rows,
       count(DISTINCT running_total) AS different_running_totals,
       count(DISTINCT orderDate)     AS order_dates
FROM (SELECT orderDate,
             sum(orderTotal) OVER (ORDER BY orderDate) AS running_total
      FROM orders
      WHERE status = 'completed') AS w;
-- rows | different_running_totals | order_dates
--  529 |                      250 |         250
-- 529 rows, 250 different values: one running total per DATE, not per
-- order. 279 rows repeat a neighbour's figure.

-- FIX: say ROWS, and make the order unique with a tie-breaker.
SELECT orderID, orderDate, orderTotal,
       sum(orderTotal) OVER (ORDER BY orderDate, orderID
                             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total
FROM orders
WHERE status = 'completed'
ORDER BY orderDate, orderID
LIMIT 8;
-- orderid | orderdate  | ordertotal | running_total
--    1001 | 2024-01-01 |     211.65 |        211.65
--    1002 | 2024-01-02 |     249.00 |        460.65
--    1003 | 2024-01-02 |     747.00 |       1207.65
--    1004 | 2024-01-04 |      59.00 |       1266.65
--    1005 | 2024-01-04 |      38.90 |       1305.55
--    1006 | 2024-01-06 |     128.00 |       1433.55
--    1007 | 2024-01-08 |      74.00 |       1507.55
--    1008 | 2024-01-08 |     387.00 |       1894.55
-- The rule: if you mean "running", write ROWS -- don't rely on the
-- default. (ROWS without a tie-breaker would number the tied rows in
-- an arbitrary order: Part 3.3 again.)

-- ---- 6.3 Verification: where must a running total end? ----
-- Check 1 -- the last running total is the grand total. Both versions
-- pass this check (at the last date, all peers are in), which is why
-- it can't be the only check.
SELECT max(range_total) AS range_ends_at,
       max(rows_total)  AS rows_ends_at,
       (SELECT sum(orderTotal) FROM orders WHERE status = 'completed') AS completed_revenue
FROM (SELECT sum(orderTotal) OVER (ORDER BY orderDate) AS range_total,
             sum(orderTotal) OVER (ORDER BY orderDate, orderID
                                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS rows_total
      FROM orders
      WHERE status = 'completed') AS w;
-- range_ends_at | rows_ends_at | completed_revenue
--     157078.41 |    157078.41 |         157078.41

-- Check 2 -- per partition: each customer's LAST running total must
-- equal that customer's plain sum. Count the customers where it doesn't.
WITH running AS (
    SELECT customerID, orderTotal,
           sum(orderTotal) OVER (PARTITION BY customerID
                                 ORDER BY orderDate, orderTime, orderID
                                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total,
           row_number() OVER (PARTITION BY customerID
                              ORDER BY orderDate DESC, orderTime DESC, orderID DESC) AS from_the_end
    FROM orders
    WHERE status = 'completed'
)
SELECT count(*) AS customers,
       count(*) FILTER (WHERE r.running_total <> t.total) AS mismatches,
       sum(r.running_total) AS sum_of_last_running_totals
FROM running r
JOIN (SELECT customerID, sum(orderTotal) AS total
      FROM orders WHERE status = 'completed'
      GROUP BY customerID) AS t ON t.customerID = r.customerID
WHERE r.from_the_end = 1;
-- customers | mismatches | sum_of_last_running_totals
--        28 |          0 |                  157078.41
-- 28 customers, 0 mismatches, and the 28 end points add up to the
-- completed revenue.

-- Check 3 -- the one that catches RANGE: a running total of positive
-- amounts must change on EVERY row. Count the rows where it didn't.
SELECT count(*) FILTER (WHERE range_total = prev_range) AS stalled_range,
       count(*) FILTER (WHERE rows_total  = prev_rows)  AS stalled_rows
FROM (SELECT range_total, rows_total,
             lag(range_total) OVER (ORDER BY orderDate, orderID) AS prev_range,
             lag(rows_total)  OVER (ORDER BY orderDate, orderID) AS prev_rows
      FROM (SELECT orderID, orderDate,
                   sum(orderTotal) OVER (ORDER BY orderDate) AS range_total,
                   sum(orderTotal) OVER (ORDER BY orderDate, orderID
                                         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS rows_total
            FROM orders
            WHERE status = 'completed') AS running) AS compared;
-- stalled_range | stalled_rows
--           279 |            0
-- 279 = 529 rows - 250 dates: every row that shares a date with an
-- earlier row "stalls". With ROWS: 0.

-- ---- 6.4 THE TRAP: last_value with the default frame ----
-- "Each order next to the customer's LATEST order total" -- first_value
-- worked in 5.5, so last_value should too:
--
-- New function: last_value(x) -- the value of x on the last row of the
-- window frame. With the default frame, that is the current row -- the
-- trap below.
--
SELECT orderID, orderDate, orderTotal,
       first_value(orderTotal) OVER w AS first_order,
       last_value(orderTotal)  OVER w AS latest_order
FROM orders
WHERE status = 'completed' AND customerID = 5
WINDOW w AS (PARTITION BY customerID ORDER BY orderDate, orderTime, orderID)
ORDER BY orderDate;
-- orderid | orderdate  | ordertotal | first_order | latest_order
--    1276 | 2024-07-24 |    1598.00 |     1598.00 |      1598.00
--    1307 | 2024-08-10 |    1062.50 |     1598.00 |      1062.50
--    1373 | 2024-09-20 |      24.40 |     1598.00 |        24.40
--    1577 | 2024-12-23 |     177.00 |     1598.00 |       177.00
-- WRONG: latest_order is just orderTotal again, on every row. The
-- default frame ends at the CURRENT ROW, so the last row of the frame
-- IS the current row. first_value worked only because the frame
-- starts at the top. A plausible column, no error.

-- FIX: extend the frame to the end of the partition.
SELECT orderID, orderDate, orderTotal,
       first_value(orderTotal) OVER w AS first_order,
       last_value(orderTotal)  OVER w AS latest_order
FROM orders
WHERE status = 'completed' AND customerID = 5
WINDOW w AS (PARTITION BY customerID ORDER BY orderDate, orderTime, orderID
             ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
ORDER BY orderDate;
-- orderid | orderdate  | ordertotal | first_order | latest_order
--    1276 | 2024-07-24 |    1598.00 |     1598.00 |       177.00
--    1307 | 2024-08-10 |    1062.50 |     1598.00 |       177.00
--    1373 | 2024-09-20 |      24.40 |     1598.00 |       177.00
--    1577 | 2024-12-23 |     177.00 |     1598.00 |       177.00
-- (Or: first_value with ORDER BY ... DESC -- "the first of the newest".)

-- **Every kind of frame, on one customer.** Lusine has only 4 orders --
-- too few to see frames differ. Mher Sargsyan (customer 30) has 8
-- completed orders, and two of them on the same day (14 November). We
-- number his orders 1-8 (rn) and, for every row, show WHICH rows each
-- frame contains.
--
-- New function: string_agg(x, ',') -- joins the values of x from all
-- the rows it sees (here: the rows of the frame) into one text,
-- separated by ','. The order inside the list is not guaranteed: read
-- it as a set of rows.
--
-- **Query 1: the ROWS frames -- counted in rows.**
WITH mher AS (
    SELECT orderDate, orderTotal,
           row_number() OVER (ORDER BY orderDate, orderTime, orderID) AS rn
    FROM orders
    WHERE status = 'completed' AND customerID = 30
)
SELECT rn, orderDate, orderTotal,
       string_agg(rn::text, ',') OVER (ORDER BY rn)                                                         AS default_frame,
       string_agg(rn::text, ',') OVER (ORDER BY rn ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING)                AS rows_2p_1p,
       string_agg(rn::text, ',') OVER (ORDER BY rn ROWS BETWEEN 1 PRECEDING AND CURRENT ROW)                AS rows_1p_cur,
       string_agg(rn::text, ',') OVER (ORDER BY rn ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING)                AS rows_1p_1f,
       string_agg(rn::text, ',') OVER (ORDER BY rn ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)        AS rows_cur_unb,
       string_agg(rn::text, ',') OVER (ORDER BY rn ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS rows_all,
       string_agg(rn::text, ',') OVER ()                                                                    AS no_order_by
FROM mher
ORDER BY rn;
-- rn | orderdate  | ordertotal |  default_frame  | rows_2p_1p | rows_1p_cur | rows_1p_1f |  rows_cur_unb   |    rows_all     |   no_order_by
--  1 | 2024-04-18 |      38.80 | 1               |            | 1           | 1,2        | 1,2,3,4,5,6,7,8 | 1,2,3,4,5,6,7,8 | 1,2,3,4,5,6,7,8
--  2 | 2024-05-20 |      19.80 | 1,2             | 1          | 1,2         | 1,2,3      | 2,3,4,5,6,7,8   | 1,2,3,4,5,6,7,8 | 1,2,3,4,5,6,7,8
--  3 | 2024-10-04 |      78.50 | 1,2,3           | 1,2        | 2,3         | 2,3,4      | 3,4,5,6,7,8     | 1,2,3,4,5,6,7,8 | 1,2,3,4,5,6,7,8
--  4 | 2024-11-14 |      55.97 | 1,2,3,4         | 2,3        | 3,4         | 3,4,5      | 4,5,6,7,8       | 1,2,3,4,5,6,7,8 | 1,2,3,4,5,6,7,8
--  5 | 2024-11-14 |    1187.50 | 1,2,3,4,5       | 3,4        | 4,5         | 4,5,6      | 5,6,7,8         | 1,2,3,4,5,6,7,8 | 1,2,3,4,5,6,7,8
--  6 | 2024-12-12 |      80.67 | 1,2,3,4,5,6     | 4,5        | 5,6         | 5,6,7      | 6,7,8           | 1,2,3,4,5,6,7,8 | 1,2,3,4,5,6,7,8
--  7 | 2024-12-17 |     320.00 | 1,2,3,4,5,6,7   | 5,6        | 6,7         | 6,7,8      | 7,8             | 1,2,3,4,5,6,7,8 | 1,2,3,4,5,6,7,8
--  8 | 2024-12-21 |     498.00 | 1,2,3,4,5,6,7,8 | 6,7        | 7,8         | 7,8        | 8               | 1,2,3,4,5,6,7,8 | 1,2,3,4,5,6,7,8
-- | Column | Frame | In words | Row 4 sees |
-- |---|---|---|---|
-- | `default_frame` | ORDER BY, no frame written | from the start up to this row (rn has no ties, so the default RANGE acts like ROWS) | 1,2,3,4 |
-- | `rows_2p_1p` | `ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING` | the two rows before, NOT this one | 2,3 |
-- | `rows_1p_cur` | `ROWS BETWEEN 1 PRECEDING AND CURRENT ROW` | the row before, and this one | 3,4 |
-- | `rows_1p_1f` | `ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING` | one row either side | 3,4,5 |
-- | `rows_cur_unb` | `ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING` | this row to the end | 4,5,6,7,8 |
-- | `rows_all` | `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING` | the whole partition | 1-8 |
-- | `no_order_by` | `OVER ()` | the whole partition: no order, no frame | 1-8 |
--
-- Look at the edges: on row 1, `rows_2p_1p` is empty (NULL -- there
-- are no rows before it), and `rows_1p_1f` is just 1,2. A frame never
-- reaches outside the partition; it simply gets shorter.
--
-- **Query 2: RANGE, GROUPS and EXCLUDE -- what happens with ties.** Now
-- the window is ordered by orderDate only, so rows 4 and 5 (both 14
-- November) are peers. rows_1p is there for comparison.
WITH mher AS (
    SELECT orderDate, orderTotal,
           row_number() OVER (ORDER BY orderDate, orderTime, orderID) AS rn
    FROM orders
    WHERE status = 'completed' AND customerID = 30
)
SELECT rn, orderDate,
       string_agg(rn::text, ',') OVER (ORDER BY rn        ROWS   BETWEEN 1 PRECEDING AND CURRENT ROW) AS rows_1p,
       string_agg(rn::text, ',') OVER (ORDER BY orderDate GROUPS BETWEEN 1 PRECEDING AND CURRENT ROW) AS groups_1p,
       string_agg(rn::text, ',') OVER (ORDER BY orderDate)                                            AS range_default,
       string_agg(rn::text, ',') OVER (ORDER BY orderDate RANGE BETWEEN INTERVAL '30 days' PRECEDING AND CURRENT ROW) AS range_30_days,
       string_agg(rn::text, ',') OVER (ORDER BY orderDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
                                       EXCLUDE CURRENT ROW) AS excl_current_row,
       string_agg(rn::text, ',') OVER (ORDER BY orderDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
                                       EXCLUDE GROUP)       AS excl_group,
       string_agg(rn::text, ',') OVER (ORDER BY orderDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
                                       EXCLUDE TIES)        AS excl_ties
FROM mher
ORDER BY rn;
-- rn | orderdate  | rows_1p | groups_1p |  range_default  | range_30_days | excl_current_row |  excl_group   |    excl_ties
--  1 | 2024-04-18 | 1       | 1         | 1               | 1             | 2,3,4,5,6,7,8    | 2,3,4,5,6,7,8 | 1,2,3,4,5,6,7,8
--  2 | 2024-05-20 | 1,2     | 1,2       | 1,2             | 2             | 1,3,4,5,6,7,8    | 1,3,4,5,6,7,8 | 1,2,3,4,5,6,7,8
--  3 | 2024-10-04 | 2,3     | 2,3       | 1,2,3           | 3             | 1,2,4,5,6,7,8    | 1,2,4,5,6,7,8 | 1,2,3,4,5,6,7,8
--  4 | 2024-11-14 | 3,4     | 3,4,5     | 1,2,3,4,5       | 4,5           | 1,2,3,5,6,7,8    | 1,2,3,6,7,8   | 1,2,3,4,6,7,8
--  5 | 2024-11-14 | 4,5     | 3,4,5     | 1,2,3,4,5       | 4,5           | 1,2,3,4,6,7,8    | 1,2,3,6,7,8   | 1,2,3,5,6,7,8
--  6 | 2024-12-12 | 5,6     | 4,5,6     | 1,2,3,4,5,6     | 4,5,6         | 1,2,3,4,5,7,8    | 1,2,3,4,5,7,8 | 1,2,3,4,5,6,7,8
--  7 | 2024-12-17 | 6,7     | 6,7       | 1,2,3,4,5,6,7   | 6,7           | 1,2,3,4,5,6,8    | 1,2,3,4,5,6,8 | 1,2,3,4,5,6,7,8
--  8 | 2024-12-21 | 7,8     | 7,8       | 1,2,3,4,5,6,7,8 | 6,7,8         | 1,2,3,4,5,6,7    | 1,2,3,4,5,6,7 | 1,2,3,4,5,6,7,8
-- | Column | Frame | In words | Row 4 sees | Row 5 sees |
-- |---|---|---|---|---|
-- | `rows_1p` | `ROWS BETWEEN 1 PRECEDING AND CURRENT ROW` | 1 row back, by position | 3,4 | 4,5 |
-- | `groups_1p` | `GROUPS BETWEEN 1 PRECEDING AND CURRENT ROW` | this DATE and the previous date that has orders | 3,4,5 | 3,4,5 |
-- | `range_default` | ORDER BY orderDate, no frame | up to this row AND its peers | 1-5 | 1-5 |
-- | `range_30_days` | `RANGE BETWEEN INTERVAL '30 days' PRECEDING AND CURRENT ROW` | orders in the 30 days up to this date | 4,5 | 4,5 |
-- | `excl_current_row` | whole partition, `EXCLUDE CURRENT ROW` | everyone except this row | all but 4 | all but 5 |
-- | `excl_group` | whole partition, `EXCLUDE GROUP` | everyone except this row and its peers | 1,2,3,6,7,8 | 1,2,3,6,7,8 |
-- | `excl_ties` | whole partition, `EXCLUDE TIES` | everyone except the peers, but keep this row | all but 5 | all but 4 |
--
-- Rows 4 and 5 are where the modes split: ROWS treats them as two
-- different positions, while GROUPS and RANGE treat them as one date.
-- range_30_days on row 4 drops row 3 (4 October is 41 days earlier),
-- and on row 8 (21 December) it reaches back to 21 November: rows
-- 6,7,8. (EXCLUDE NO OTHERS, the default, excludes nothing.) GROUPS,
-- RANGE with an offset and EXCLUDE need PostgreSQL 11 or later.
--
-- **Query 3: first_value and last_value under three frames.** The
-- functions from the fix above, on Mher's orders. Two named windows
-- build on the first one: `(w_default ROWS ...)` means "w_default, plus
-- this frame".
SELECT orderID, orderDate, orderTotal,
       first_value(orderTotal) OVER w_default AS first_default,
       last_value(orderTotal)  OVER w_default AS last_default,
       first_value(orderTotal) OVER w_near    AS first_near,
       last_value(orderTotal)  OVER w_near    AS last_near,
       first_value(orderTotal) OVER w_all     AS first_all,
       last_value(orderTotal)  OVER w_all     AS last_all
FROM orders
WHERE status = 'completed' AND customerID = 30
WINDOW w_default AS (PARTITION BY customerID ORDER BY orderDate, orderTime, orderID),
       w_near    AS (w_default ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING),
       w_all     AS (w_default ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
ORDER BY orderDate, orderTime;
-- orderid | orderdate  | ordertotal | first_default | last_default | first_near | last_near | first_all | last_all
--    1147 | 2024-04-18 |      38.80 |         38.80 |        38.80 |      38.80 |     19.80 |     38.80 |   498.00
--    1191 | 2024-05-20 |      19.80 |         38.80 |        19.80 |      38.80 |     78.50 |     38.80 |   498.00
--    1403 | 2024-10-04 |      78.50 |         38.80 |        78.50 |      19.80 |     55.97 |     38.80 |   498.00
--    1479 | 2024-11-14 |      55.97 |         38.80 |        55.97 |      78.50 |   1187.50 |     38.80 |   498.00
--    1482 | 2024-11-14 |    1187.50 |         38.80 |      1187.50 |      55.97 |     80.67 |     38.80 |   498.00
--    1544 | 2024-12-12 |      80.67 |         38.80 |        80.67 |    1187.50 |    320.00 |     38.80 |   498.00
--    1558 | 2024-12-17 |     320.00 |         38.80 |       320.00 |      80.67 |    498.00 |     38.80 |   498.00
--    1575 | 2024-12-21 |     498.00 |         38.80 |       498.00 |     320.00 |    498.00 |     38.80 |   498.00
-- | Frame | first_value | last_value |
-- |---|---|---|
-- | default (start to this row) | 38.80 on every row: the frame always starts at the first order | this row's own total: the frame ends here -- the trap |
-- | 1 row either side | the PREVIOUS order's total (on the first row: its own) | the NEXT order's total (on the last row: its own) |
-- | the whole partition | 38.80, the first order | 498.00, the latest order -- the right answer |
--
-- The middle frame turns first_value and last_value into a lag and a
-- lead that never return NULL: at the edges the frame just shrinks, so
-- the "previous" of the first order is the order itself.

-- Across all customers: on how many rows is the default last_value
-- simply the row's own value?
SELECT count(*) AS rows,
       count(*) FILTER (WHERE wrong_latest = orderTotal) AS equals_own_value
FROM (SELECT orderTotal,
             last_value(orderTotal) OVER (PARTITION BY customerID
                                          ORDER BY orderDate, orderTime, orderID) AS wrong_latest
      FROM orders
      WHERE status = 'completed') AS w;
-- rows | equals_own_value
--  529 |              529

-- Real problem: is each customer's latest order bigger than their first?
--
-- Task: are customers trading up (spending more per order over time)
-- or down? Compare each customer's first and latest completed order.
--
-- Solution: first_value and last_value over the FULL partition (the
-- fixed frame above), one row per customer with DISTINCT, then count.
WITH first_and_last AS (
    SELECT DISTINCT customerID,
           first_value(orderTotal) OVER w AS first_order,
           last_value(orderTotal)  OVER w AS latest_order
    FROM orders
    WHERE status = 'completed'
    WINDOW w AS (PARTITION BY customerID ORDER BY orderDate, orderTime, orderID
                 ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
)
SELECT count(*)                                         AS customers,
       count(*) FILTER (WHERE latest_order > first_order) AS traded_up,
       count(*) FILTER (WHERE latest_order < first_order) AS traded_down
FROM first_and_last;
-- customers | traded_up | traded_down
--        28 |        16 |          12
-- Reading the result: 28 customers: 16 traded up, 12 traded down.
-- With the DEFAULT frame, last_value changes on every row, so DISTINCT
-- can't collapse a customer to one row: the same query then reports
-- 510 "customers", 274 trading up and 208 down -- the trap above,
-- inside a real report. Rows in = 28 customers out is the check.

-- ---- 6.5 Moving averages, and THE TRAP at the edges ----
-- Completed revenue per month, with a 3-month moving average.
WITH monthly AS (
    SELECT d.month, sum(f.revenue) AS revenue
    FROM fact_sales f
    JOIN dim_date d ON d.dateKey = f.dateKey
    WHERE f.status = 'completed'
    GROUP BY d.month
)
SELECT month, revenue,
       round(avg(revenue) OVER (ORDER BY month
                                ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS moving_avg_3
FROM monthly
ORDER BY month
LIMIT 4;
-- month | revenue  | moving_avg_3
--     1 |  9902.54 |      9902.54
--     2 |  6907.59 |      8405.07
--     3 |  6682.49 |      7830.87
--     4 | 14855.21 |      9481.76
-- WRONG at the start: January's "3-month average" is January alone,
-- February's is two months. The column header promises 3 months; the
-- first two rows silently use fewer. Plotted, they look like any other
-- point.

-- FIX: count the rows in the same frame, and refuse to average fewer
-- than 3 (or show the count, and let the reader decide).
WITH monthly AS (
    SELECT d.month, sum(f.revenue) AS revenue
    FROM fact_sales f
    JOIN dim_date d ON d.dateKey = f.dateKey
    WHERE f.status = 'completed'
    GROUP BY d.month
)
SELECT month, revenue,
       count(*) OVER w AS months_in_frame,
       CASE WHEN count(*) OVER w = 3
            THEN round(avg(revenue) OVER w, 2) END AS moving_avg_3
FROM monthly
WINDOW w AS (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
ORDER BY month
LIMIT 4;
-- month | revenue  | months_in_frame | moving_avg_3
--     1 |  9902.54 |               1 |
--     2 |  6907.59 |               2 |
--     3 |  6682.49 |               3 |      7830.87
--     4 | 14855.21 |               3 |      9481.76

-- ---- 6.6 ROWS vs RANGE with an offset: "the last 7 days" ----
-- Daily completed revenue. Orders happened on 250 of the 366 days, so
-- "the previous 6 ROWS" is not "the previous 6 DAYS".
WITH daily AS (
    SELECT orderDate, sum(orderTotal) AS revenue
    FROM orders
    WHERE status = 'completed'
    GROUP BY orderDate
)
SELECT orderDate, revenue,
       sum(revenue) OVER (ORDER BY orderDate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS last_7_rows,
       sum(revenue) OVER (ORDER BY orderDate
                          RANGE BETWEEN INTERVAL '6 days' PRECEDING AND CURRENT ROW) AS last_7_days
FROM daily
ORDER BY orderDate
LIMIT 10;
-- orderdate  | revenue | last_7_rows | last_7_days
-- 2024-01-01 |  211.65 |      211.65 |      211.65
-- 2024-01-02 |  996.00 |     1207.65 |     1207.65
-- 2024-01-04 |   97.90 |     1305.55 |     1305.55
-- 2024-01-06 |  128.00 |     1433.55 |     1433.55
-- 2024-01-08 |  461.00 |     1894.55 |     1682.90
-- 2024-01-12 |  449.00 |     2343.55 |     1038.00
-- 2024-01-13 | 1048.00 |     3391.55 |     1958.00
-- 2024-01-15 |  449.00 |     3628.90 |     1946.00
-- 2024-01-16 |  167.05 |     2799.95 |     2113.05
-- 2024-01-17 |    9.90 |     2711.95 |     2122.95
-- WRONG for "the last 7 days" (last_7_rows): from January 8th on, the
-- two columns disagree: 7 rows reach back
-- further than 7 days, because the days with no orders have no rows.
-- Part 5.3's trap in frame form. RANGE with an offset measures
-- distance in the ORDER BY's own unit (here: days).

-- How many of the 250 days get a different answer?
WITH daily AS (
    SELECT orderDate, sum(orderTotal) AS revenue
    FROM orders
    WHERE status = 'completed'
    GROUP BY orderDate
)
SELECT count(*) AS days,
       count(*) FILTER (WHERE last_7_rows <> last_7_days) AS different
FROM (SELECT sum(revenue) OVER (ORDER BY orderDate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS last_7_rows,
             sum(revenue) OVER (ORDER BY orderDate
                                RANGE BETWEEN INTERVAL '6 days' PRECEDING AND CURRENT ROW) AS last_7_days
      FROM daily) AS w;
-- days | different
--  250 |       246

-- Real problem: the best week of the year
--
-- Task: which 7-day period brought in the most completed revenue?
--
-- Solution: daily revenue, then a 7-day window measured in DAYS (RANGE
-- with an interval -- not 7 rows, see above), then the top 3.
WITH daily AS (
    SELECT orderDate, sum(orderTotal) AS revenue
    FROM orders
    WHERE status = 'completed'
    GROUP BY orderDate
),
weekly AS (
    SELECT orderDate,
           sum(revenue) OVER (ORDER BY orderDate
                              RANGE BETWEEN INTERVAL '6 days' PRECEDING AND CURRENT ROW) AS last_7_days
    FROM daily
)
SELECT orderDate - 6 AS week_from, orderDate AS week_to, last_7_days
FROM weekly
ORDER BY last_7_days DESC
LIMIT 3;
-- week_from  |  week_to   | last_7_days
-- 2024-12-05 | 2024-12-11 |     9678.12
-- 2024-12-06 | 2024-12-12 |     8423.21
-- 2024-12-11 | 2024-12-17 |     8390.09
-- Reading the result: 5-11 December, 9,678.12 -- the run-up to the
-- holidays. All three top windows are in December (they overlap:
-- there is one 7-day window ending on each date).

-- ---- 6.7 GROUPS: count peer groups, not rows ----
-- "Revenue on this order date and on the previous date that had
-- orders" -- per ORDER, without first collapsing to days.
SELECT orderID, orderDate, orderTotal,
       sum(orderTotal) OVER (ORDER BY orderDate
                             GROUPS BETWEEN 1 PRECEDING AND CURRENT ROW) AS this_and_previous_date
FROM orders
WHERE status = 'completed'
ORDER BY orderDate, orderID
LIMIT 5;
-- orderid | orderdate  | ordertotal | this_and_previous_date
--    1001 | 2024-01-01 |     211.65 |                 211.65
--    1002 | 2024-01-02 |     249.00 |                1207.65
--    1003 | 2024-01-02 |     747.00 |                1207.65
--    1004 | 2024-01-04 |      59.00 |                1093.90
--    1005 | 2024-01-04 |      38.90 |                1093.90
-- 1002 and 1003 (2024-01-02) both see 2024-01-01 and 2024-01-02:
-- 211.65 + 249.00 + 747.00 = 1207.65. Orders 1004/1005 (2024-01-04) see
-- 01-02 and 01-04. GROUPS needs PostgreSQL 11 or later.
