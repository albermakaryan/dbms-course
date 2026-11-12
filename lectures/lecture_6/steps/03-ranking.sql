-- ============================================================
-- Lecture 6 — Part 3: Ranking functions
-- Run after Part 2.
--
--   row_number()  1, 2, 3, 4 ...  ties get DIFFERENT numbers (who gets which? arbitrary)
--   rank()        1, 2, 2, 4 ...  ties share a number, then a gap
--   dense_rank()  1, 2, 2, 3 ...  ties share a number, no gap
--
-- All of them need ORDER BY inside OVER: a rank is a position in an order.
-- ============================================================

-- ---- 3.0 Six rows first ----
-- Before the real data: six made-up rows, two pairs of ties (ids 2 and
-- 3 both scored 85; ids 4 and 5 both 70). Every ranking function,
-- score from high to low. Two windows: `w` orders by score only, so
-- rank and friends can SEE the ties; `wt` adds id as a tie-breaker for
-- row_number and ntile, which always split ties -- so the split is
-- predictable instead of up to PostgreSQL.
--
-- New function: dense_rank() -- like rank(), but nothing is skipped
-- after a tie: 1, 2, 2, 3. It counts distinct values.
--
-- New function: ntile(n) -- deals the rows of each window, in order,
-- into n buckets numbered 1 to n, as equal in size as possible.
--
-- New function: percent_rank() -- the row's relative position, from 0
-- (first) to 1 (last): (rank - 1) / (rows - 1).
--
-- New function: cume_dist() -- the share of the window's rows that
-- come at or before this row, ties included: from 1/N to 1.
--
SELECT id, score,
       row_number()  OVER wt AS row_number,
       rank()        OVER w  AS rank,
       dense_rank()  OVER w  AS dense_rank,
       ntile(3)      OVER wt AS ntile_3,
       round((percent_rank() OVER w)::numeric, 3) AS percent_rank,
       round((cume_dist()    OVER w)::numeric, 3) AS cume_dist
FROM (VALUES (1, 90), (2, 85), (3, 85), (4, 70), (5, 70), (6, 60)) AS t(id, score)
WINDOW w  AS (ORDER BY score DESC),
       wt AS (ORDER BY score DESC, id)
ORDER BY id;
-- id | score | row_number | rank | dense_rank | ntile_3 | percent_rank | cume_dist
--  1 |    90 |          1 |    1 |          1 |       1 |        0.000 |     0.167
--  2 |    85 |          2 |    2 |          2 |       1 |        0.200 |     0.500
--  3 |    85 |          3 |    2 |          2 |       2 |        0.200 |     0.500
--  4 |    70 |          4 |    4 |          3 |       2 |        0.600 |     0.833
--  5 |    70 |          5 |    4 |          3 |       3 |        0.600 |     0.833
--  6 |    60 |          6 |    6 |          4 |       3 |        1.000 |     1.000
-- **How each number is computed -- the three ranks:**
--
-- | id | score | row_number: count the rows in order | rank: 1 + rows with a HIGHER score | dense_rank: 1 + DISTINCT higher scores |
-- |---|---|---|---|---|
-- | 1 | 90 | 1 | 1 + 0 = **1** | 1 + 0 = **1** |
-- | 2 | 85 | 2 | 1 + 1 (id 1) = **2** | 1 + 1 (90) = **2** |
-- | 3 | 85 | 3 -- tied with id 2; only the id puts it second | 1 + 1 (id 1) = **2** | 1 + 1 (90) = **2** |
-- | 4 | 70 | 4 | 1 + 3 (ids 1, 2, 3) = **4** | 1 + 2 (90, 85) = **3** |
-- | 5 | 70 | 5 | 1 + 3 (ids 1, 2, 3) = **4** | 1 + 2 (90, 85) = **3** |
-- | 6 | 60 | 6 | 1 + 5 (ids 1-5) = **6** | 1 + 3 (90, 85, 70) = **4** |
--
-- rank skips 3 and 5: two rows share 2nd place, so the next row is 4th.
-- dense_rank never skips: it numbers the distinct scores 90, 85, 70,
-- 60 as 1, 2, 3, 4.
--
-- **How each number is computed -- the distribution functions:**
--
-- | id | ntile(3): 6 rows into 3 buckets of 2, in order | percent_rank = (rank - 1) / (6 - 1) | cume_dist = rows with a score >= this one / 6 |
-- |---|---|---|---|
-- | 1 | 1 | (1 - 1) / 5 = **0.000** | 1 / 6 = **0.167** |
-- | 2 | 1 | (2 - 1) / 5 = **0.200** | 3 / 6 = **0.500** |
-- | 3 | **2** -- its tie partner id 2 is in bucket 1 | (2 - 1) / 5 = **0.200** | 3 / 6 = **0.500** |
-- | 4 | 2 | (4 - 1) / 5 = **0.600** | 5 / 6 = **0.833** |
-- | 5 | **3** -- its tie partner id 4 is in bucket 2 | (4 - 1) / 5 = **0.600** | 5 / 6 = **0.833** |
-- | 6 | 3 | (6 - 1) / 5 = **1.000** | 6 / 6 = **1.000** |
--
-- ntile, like row_number, cuts wherever the count says, even through a
-- tie. percent_rank and cume_dist give tied rows the same value.

-- PARTITION BY restarts the numbering in each group. The same six rows,
-- split into group A (ids 1-3) and group B (ids 4-6):
SELECT grp, id, score,
       rank() OVER (ORDER BY score DESC)                   AS rank_overall,
       rank() OVER (PARTITION BY grp ORDER BY score DESC)  AS rank_in_group
FROM (VALUES ('A', 1, 90), ('A', 2, 85), ('A', 3, 85),
             ('B', 4, 70), ('B', 5, 70), ('B', 6, 60)) AS t(grp, id, score)
ORDER BY grp, id;
-- grp | id | score | rank_overall | rank_in_group
-- A   |  1 |    90 |            1 |             1
-- A   |  2 |    85 |            2 |             2
-- A   |  3 |    85 |            2 |             2
-- B   |  4 |    70 |            4 |             1
-- B   |  5 |    70 |            4 |             1
-- B   |  6 |    60 |            6 |             3
-- | id | rank_overall | rank_in_group | Why |
-- |---|---|---|---|
-- | 4 | 4 | **1** | overall, three rows score higher; inside group B, none do |
-- | 6 | 6 | **3** | inside group B, only ids 4 and 5 score higher: 1 + 2 = 3 |
--
-- **What a tie-breaker does to rank.** The same rank(), but over `wt`
-- (score, then id):
SELECT id, score,
       rank() OVER (ORDER BY score DESC)     AS rank_by_score,
       rank() OVER (ORDER BY score DESC, id) AS rank_by_score_and_id
FROM (VALUES (1, 90), (2, 85), (3, 85), (4, 70), (5, 70), (6, 60)) AS t(id, score)
ORDER BY id;
-- id | score | rank_by_score | rank_by_score_and_id
--  1 |    90 |             1 |                    1
--  2 |    85 |             2 |                    2
--  3 |    85 |             2 |                    3
--  4 |    70 |             4 |                    4
--  5 |    70 |             4 |                    5
--  6 |    60 |             6 |                    6
-- With the id added, no two rows are equal on (score, id) any more, so
-- there are no ties left to share a place: rank becomes 1, 2, 3, 4, 5,
-- 6 -- exactly row_number. A tie-breaker is right for row_number and
-- ntile (to make the split predictable) and wrong for rank and
-- dense_rank, whose whole job is to show ties. Part 3.3 shows what
-- happens to row_number WITHOUT a tie-breaker, on the real data.

-- ---- 3.1 The three ranks side by side, on real ties ----
-- The customer league table by number of orders -- all 30 customers,
-- so Lecture 4's LEFT JOIN keeps the two with none.
SELECT c.customerID, c.firstName, c.lastName,
       count(o.orderID)                                AS orders,
       row_number() OVER (ORDER BY count(o.orderID) DESC) AS row_number,
       rank()       OVER (ORDER BY count(o.orderID) DESC) AS rank,
       dense_rank() OVER (ORDER BY count(o.orderID) DESC) AS dense_rank
FROM customers c
LEFT JOIN orders o ON o.customerID = c.customerID
GROUP BY c.customerID, c.firstName, c.lastName
ORDER BY orders DESC, c.customerID;
-- customerid | firstname |   lastname   | orders | row_number | rank | dense_rank
--          2 | Davit     | Petrosyan    |     52 |          1 |    1 |          1
--         12 | Armen     | Gevorgyan    |     48 |          2 |    2 |          2
--         16 | Karen     | Khachatryan  |     41 |          3 |    3 |          3
--          8 | Aram      | Vardanyan    |     40 |          4 |    4 |          4
--         20 | Artur     | Baghdasaryan |     37 |          5 |    5 |          5
--         28 | Gevorg    | Kocharyan    |     34 |          6 |    6 |          6
--         18 | Ruben     | Asatryan     |     30 |          7 |    7 |          7
--          6 | Narek     | Manukyan     |     29 |          8 |    8 |          8
--         10 | Lilit     | Hovhannisyan |     29 |          9 |    8 |          8
--          1 | Anna      | Sargsyan     |     28 |         10 |   10 |          9
--         14 | Vahan     | Torosyan     |     24 |         11 |   11 |         10
--          4 | Tigran    | Grigoryan    |     22 |         12 |   12 |         11
--          7 | Sona      | Karapetyan   |     20 |         13 |   13 |         12
--         25 | Hasmik    | Zakaryan     |     19 |         14 |   14 |         13
--         19 | Tatev     | Martirosyan  |     17 |         15 |   15 |         14
--          3 | Mariam    | Hakobyan     |     16 |         16 |   16 |         15
--          9 | Hayk      | Melikyan     |     16 |         17 |   16 |         15
--         22 | Suren     | Hayrapetyan  |     15 |         18 |   18 |         16
--         26 | Samvel    | Nazaryan     |     12 |         19 |   19 |         17
--         17 | Nane      | Galstyan     |     11 |         20 |   20 |         18
--         21 | Meline    | Poghosyan    |     10 |         21 |   21 |         19
--         23 | Ani       | Stepanyan    |     10 |         22 |   21 |         19
--         11 | Anna      | Sargsyan     |      9 |         23 |   23 |         20
--         15 | Arpine    | Simonyan     |      8 |         24 |   24 |         21
--         30 | Mher      | Sargsyan     |      8 |         25 |   24 |         21
--         13 | Gayane    | Mnatsakanyan |      6 |         26 |   26 |         22
--          5 | Lusine    | Avetisyan    |      5 |         27 |   27 |         23
--         27 | Diana     | Aleksanyan   |      4 |         28 |   28 |         24
--         24 | Levon     | Arakelyan    |      0 |         29 |   29 |         25
--         29 | Astghik   | Danielyan    |      0 |         30 |   29 |         25
-- Real ties: Narek and Lilit (29), Mariam and Hayk (16), Meline and Ani
-- (10), Arpine and Mher (8), Levon and Astghik (0). Look at rows 8-10:
-- row_number 8, 9, 10; rank 8, 8, 10; dense_rank 8, 8, 9.

-- Real problem: salesperson of the month
--
-- Task: each month, the salesperson with the highest completed revenue
-- gets a bonus. If two people tie, both get it. Who won each month, and
-- who won most often?
--
-- Solution: revenue per salesperson per month (GROUP BY), then rank()
-- inside each month (PARTITION BY month), keep rank 1. rank, not
-- row_number: a tie must give two winners, not one picked at random.
WITH monthly AS (
    SELECT extract(month FROM o.orderDate)::int AS month,
           e.firstName,
           sum(o.orderTotal) AS revenue
    FROM orders o
    JOIN employees e ON e.employeeID = o.employeeID
    WHERE o.status = 'completed'
    GROUP BY extract(month FROM o.orderDate), e.employeeID, e.firstName
),
ranked AS (
    SELECT month, firstName, revenue,
           rank() OVER (PARTITION BY month ORDER BY revenue DESC) AS place
    FROM monthly
)
SELECT month, firstName, revenue
FROM ranked
WHERE place = 1
ORDER BY month;
-- month | firstname | revenue
--     1 | Ani       | 3358.45
--     2 | Hayk      | 1481.09
--     3 | Vahe      | 1269.91
--     4 | Gor       | 3449.79
--     5 | Ani       | 3464.42
--     6 | Ani       | 2596.30
--     7 | Gor       | 3791.24
--     8 | Ani       | 2994.20
--     9 | Hayk      | 2946.92
--    10 | Arman     | 2201.80
--    11 | Ani       | 3215.90
--    12 | Hayk      | 7187.47
-- Reading the result: 12 months, 12 winners -- no month had a tie.
-- Ani won 5 months, Hayk 3, Gor 2, Vahe and Arman 1 each. (The online
-- orders are left out on purpose: the bonus is for people. Part 7.1.)

-- ---- 3.2 ntile, percent_rank, cume_dist ----
-- Quartiles of the same table: ntile(4) deals 30 customers into 4
-- buckets of 8, 8, 7, 7, in order.
SELECT c.firstName, c.lastName,
       count(o.orderID)                                          AS orders,
       ntile(4)       OVER (ORDER BY count(o.orderID) DESC)      AS quartile,
       round(percent_rank() OVER (ORDER BY count(o.orderID) DESC)::numeric, 3) AS percent_rank,
       round(cume_dist()    OVER (ORDER BY count(o.orderID) DESC)::numeric, 3) AS cume_dist
FROM customers c
LEFT JOIN orders o ON o.customerID = c.customerID
GROUP BY c.customerID, c.firstName, c.lastName
ORDER BY orders DESC, c.customerID
LIMIT 10;
-- firstname |   lastname   | orders | quartile | percent_rank | cume_dist
-- Davit     | Petrosyan    |     52 |        1 |        0.000 |     0.033
-- Armen     | Gevorgyan    |     48 |        1 |        0.034 |     0.067
-- Karen     | Khachatryan  |     41 |        1 |        0.069 |     0.100
-- Aram      | Vardanyan    |     40 |        1 |        0.103 |     0.133
-- Artur     | Baghdasaryan |     37 |        1 |        0.138 |     0.167
-- Gevorg    | Kocharyan    |     34 |        1 |        0.172 |     0.200
-- Ruben     | Asatryan     |     30 |        1 |        0.207 |     0.233
-- Narek     | Manukyan     |     29 |        1 |        0.241 |     0.300
-- Lilit     | Hovhannisyan |     29 |        2 |        0.241 |     0.300
-- Anna      | Sargsyan     |     28 |        2 |        0.310 |     0.333
-- WRONG, if quartiles are meant to group equal customers: Narek and
-- Lilit placed the same 29 orders and land in DIFFERENT
-- quartiles: the bucket boundary falls between rows 8 and 9, and ntile,
-- like row_number, splits a tie wherever it falls. percent_rank and
-- cume_dist treat ties as equals (both 29s get the same value).

-- Real problem: four customer tiers for a campaign
--
-- Task: split the customers who bought something into 4 equal-sized
-- tiers by completed spending, so each tier gets its own offer. For
-- each tier: how many customers, their spending range, and their
-- revenue.
--
-- Solution: spending per customer, ntile(4) over it, then GROUP BY tier.
WITH spending AS (
    SELECT customerID, sum(orderTotal) AS spent
    FROM orders
    WHERE status = 'completed'
    GROUP BY customerID
),
tiers AS (
    SELECT spent, ntile(4) OVER (ORDER BY spent DESC, customerID) AS tier
    FROM spending
)
SELECT tier, count(*) AS customers, min(spent) AS lowest, max(spent) AS highest,
       sum(spent) AS revenue
FROM tiers
GROUP BY tier
ORDER BY tier;
-- tier | customers | lowest  | highest  | revenue
--    1 |         7 | 7994.26 | 14625.38 | 71059.04
--    2 |         7 | 5762.87 |  7506.06 | 44821.02
--    3 |         7 | 2861.90 |  4103.40 | 25802.84
--    4 |         7 | 1332.00 |  2841.56 | 15395.51
-- Reading the result: 28 customers, 7 per tier. Tier 1 alone brings in
-- 71,059.04 -- 45% of the 157,078.41. (No two customers spent exactly
-- the same, so no tie is split here; the customerID tie-breaker is
-- there in case one ever is.)

-- Real problem: the 80/20 check on products
--
-- Task: "20% of our products bring 80% of our revenue" -- is that true
-- here? Which products make up the top 20% by revenue, and how much
-- do they bring in?
--
-- Solution: revenue per product (from Lecture 4's star), cume_dist()
-- over it from the top; the top 20% are the rows with cume_dist <= 0.2.
WITH product_revenue AS (
    SELECT p.productName, sum(f.revenue) AS revenue
    FROM fact_sales f
    JOIN dim_product p ON p.productKey = f.productKey
    WHERE f.status = 'completed'
    GROUP BY p.productKey, p.productName
),
placed AS (
    SELECT productName, revenue,
           cume_dist() OVER (ORDER BY revenue DESC) AS share_at_or_above
    FROM product_revenue
)
SELECT productName, revenue, round(share_at_or_above::numeric, 3) AS cume_dist
FROM placed
WHERE share_at_or_above <= 0.2
ORDER BY revenue DESC;
--    productname     | revenue  | cume_dist
-- ThinkPad X1 Carbon | 26937.50 |     0.028
-- iPhone 15          | 11705.35 |     0.056
-- MacBook Air 13     | 11220.00 |     0.083
-- AirPods Pro        |  8316.60 |     0.111
-- ZenBook 14         |  7876.50 |     0.139
-- Galaxy S24         |  7409.40 |     0.167
-- Aspire 5           |  7378.00 |     0.194

SELECT sum(revenue) AS top_20pct_revenue,
       round(100 * sum(revenue)
             / (SELECT sum(revenue) FROM fact_sales WHERE status = 'completed'), 1) AS pct_of_revenue
FROM (SELECT sum(f.revenue) AS revenue,
             cume_dist() OVER (ORDER BY sum(f.revenue) DESC) AS share_at_or_above
      FROM fact_sales f
      WHERE f.status = 'completed'
      GROUP BY f.productKey) AS placed
WHERE share_at_or_above <= 0.2;
-- top_20pct_revenue | pct_of_revenue
--          80843.35 |           51.5
-- Reading the result: 7 of the 36 products that sold -- 20% -- bring
-- in 80,843.35, 51.5% of revenue. Not 80/20 here; more like 20/50.

-- ---- 3.3 THE TRAP: row_number() on ties is arbitrary ----
-- "A loyalty gift for our top 8 customers by number of orders."
-- (Filtering on a window needs a subquery -- Part 4 explains why.)
-- Analyst A counts from orders, then looks up the names:
SELECT x.nr, c.firstName, c.lastName, x.orders
FROM (SELECT customerID, count(*) AS orders,
             row_number() OVER (ORDER BY count(*) DESC) AS nr
      FROM orders
      GROUP BY customerID) AS x
JOIN customers c ON c.customerID = x.customerID
WHERE x.nr BETWEEN 7 AND 9
ORDER BY x.nr;
-- nr | firstname |   lastname   | orders
--  7 | Ruben     | Asatryan     |     30
--  8 | Lilit     | Hovhannisyan |     29
--  9 | Narek     | Manukyan     |     29

-- Analyst B starts from customers, as Lecture 4 taught:
SELECT nr, firstName, lastName, orders
FROM (SELECT c.firstName, c.lastName, count(o.orderID) AS orders,
             row_number() OVER (ORDER BY count(o.orderID) DESC) AS nr
      FROM customers c
      LEFT JOIN orders o ON o.customerID = c.customerID
      GROUP BY c.customerID, c.firstName, c.lastName) AS x
WHERE nr BETWEEN 7 AND 9
ORDER BY nr;
-- nr | firstname |   lastname   | orders
--  7 | Ruben     | Asatryan     |     30
--  8 | Narek     | Manukyan     |     29
--  9 | Lilit     | Hovhannisyan |     29
-- WRONG, and you can't tell from either result alone: same question,
-- same window, two different 8th customers. Lilit gets the gift in A,
-- Narek in B. Both have 29 orders; row_number had to put one of them
-- first and took whichever its sort met first -- which depends on the
-- plan, not on anything in the query. No error, no warning.
--
-- Same family as the LIMIT 1 tie trap from the Chinook lab: whenever
-- "the first N" cuts through a tie, the cut is arbitrary.

-- FIX 1: make the order complete -- a tie-breaker that is unique
-- (a key). Now every run, every plan, picks the same 8th customer:
SELECT nr, firstName, lastName, orders
FROM (SELECT c.firstName, c.lastName, count(o.orderID) AS orders,
             row_number() OVER (ORDER BY count(o.orderID) DESC, c.customerID) AS nr
      FROM customers c
      LEFT JOIN orders o ON o.customerID = c.customerID
      GROUP BY c.customerID, c.firstName, c.lastName) AS x
WHERE nr BETWEEN 7 AND 9
ORDER BY nr;
-- nr | firstname |   lastname   | orders
--  7 | Ruben     | Asatryan     |     30
--  8 | Narek     | Manukyan     |     29
--  9 | Lilit     | Hovhannisyan |     29
-- Deterministic -- but "lower customerID wins" is a business rule now.
-- Say it out loud, or pick a tie-breaker that means something (revenue).

-- FIX 2: don't hide the tie. rank() <= 8 gives everyone who is tied
-- for 8th place -- 9 customers, and the decision goes back to a human.
SELECT count(*) AS customers
FROM (SELECT count(o.orderID) AS orders,
             rank() OVER (ORDER BY count(o.orderID) DESC) AS rnk
      FROM customers c
      LEFT JOIN orders o ON o.customerID = c.customerID
      GROUP BY c.customerID) AS x
WHERE rnk <= 8;
-- customers
--         9

-- ---- 3.4 Gaps or no gaps: which one answers "top 2"? ----
-- "The two best-selling products in each category get the front shelf."
-- Times ordered = order lines per product (Ergonomic Chair Pro: 0).
WITH sold AS (
    SELECT p.category, p.productName, count(i.orderID) AS times_ordered
    FROM products p
    LEFT JOIN order_items i ON i.productID = p.productID
    GROUP BY p.productID, p.category, p.productName
)
SELECT category, productName, times_ordered,
       row_number() OVER w AS row_number,
       rank()       OVER w AS rank,
       dense_rank() OVER w AS dense_rank
FROM sold
WHERE category IN ('Audio', 'Monitors', 'Phones', 'Storage')
WINDOW w AS (PARTITION BY category ORDER BY times_ordered DESC)
ORDER BY category, times_ordered DESC, productName;
-- category |     productname     | times_ordered | row_number | rank | dense_rank
-- Audio    | AirPods Pro         |            28 |          1 |    1 |          1
-- Audio    | Soundcore Q30       |            28 |          2 |    1 |          1
-- Audio    | Flip 6              |            27 |          3 |    3 |          2
-- Audio    | WH-1000XM5          |            12 |          4 |    4 |          3
-- Monitors | UltraSharp 27       |            19 |          1 |    1 |          1
-- Monitors | Odyssey G5 32       |            10 |          3 |    2 |          2
-- Monitors | ProArt 24           |            10 |          2 |    2 |          2
-- Phones   | iPhone 15           |            14 |          1 |    1 |          1
-- Phones   | Galaxy S24          |            11 |          3 |    2 |          2
-- Phones   | Redmi Note 13       |            11 |          2 |    2 |          2
-- Phones   | Pixel 8             |             8 |          4 |    4 |          3
-- Storage  | USB Flash 128GB     |            82 |          1 |    1 |          1
-- Storage  | Expansion HDD 2TB   |            28 |          3 |    2 |          2
-- Storage  | Portable SSD T7 1TB |            28 |          2 |    2 |          2

-- How many products does each version put on the "top 2" shelf?
WITH sold AS (
    SELECT p.category, p.productName, count(i.orderID) AS times_ordered
    FROM products p
    LEFT JOIN order_items i ON i.productID = p.productID
    GROUP BY p.productID, p.category, p.productName
),
ranked AS (
    SELECT category,
           row_number() OVER w AS rn,
           rank()       OVER w AS rnk,
           dense_rank() OVER w AS drnk
    FROM sold
    WINDOW w AS (PARTITION BY category ORDER BY times_ordered DESC)
)
SELECT count(*) FILTER (WHERE rn   <= 2) AS by_row_number,
       count(*) FILTER (WHERE rnk  <= 2) AS by_rank,
       count(*) FILTER (WHERE drnk <= 2) AS by_dense_rank,
       count(DISTINCT category)          AS categories
FROM ranked;
-- by_row_number | by_rank | by_dense_rank | categories
--            25 |      28 |            29 |         13
-- 13 categories, one of them (Chairs) with a single product: "exactly
-- 2 per category" would be 25. row_number gives 25 -- by dropping a
-- tied product at random. rank gives 28: Monitors, Phones and Storage
-- each have a tie for 2nd place. dense_rank gives 29: on top of those,
-- Audio's two products tied at 28 are both "1st", so Flip 6 (27) is
-- "2nd". dense_rank <= N answers "the top N DISTINCT VALUES", not
-- "the top N products" -- it can return more rows even with no tie
-- at the cut.
