-- ============================================================
-- Lecture 3 — Part 4: DISTINCT and aggregates
-- Run after Part 3.
-- ============================================================

-- ---- DISTINCT: each value once ----
SELECT DISTINCT productCategory FROM sales ORDER BY 1;           -- 12 categories sold
SELECT DISTINCT category        FROM products ORDER BY 1;        -- 13 exist. Chairs never sold.
SELECT DISTINCT channel, paymentMethod FROM sales ORDER BY 1, 2; -- 5 combinations: online never pays cash

-- ---- count(*) vs count(column) vs count(DISTINCT column) ----
SELECT count(*)               AS rows,
       count(rating)          AS rated,            -- non-NULL ratings only
       count(DISTINCT rating) AS distinct_ratings
FROM sales;
-- 600 | 322 | 5

SELECT count(*) AS orders, count(employeeLastName) AS served_in_store FROM sales;
-- 600 | 419

-- How many customers bought this year? Depends what "a customer" is.
SELECT count(DISTINCT customerLastName)                          AS surnames,
       count(DISTINCT (customerFirstName, customerLastName))     AS names,
       count(DISTINCT customerEmail)                             AS people
FROM sales;
-- 26 | 27 | 28  -- three Sargsyans; two of them are both Anna.

SELECT count(*) FROM customers;   -- 30. Two never bought -- the flat file has no row for them.

-- ---- sum, avg, min, max ----
SELECT sum(orderTotal)           AS gross,
       round(avg(orderTotal), 2) AS avg_order,
       min(orderTotal)           AS smallest,
       max(orderTotal)           AS largest
FROM sales;
-- 164092.05 | 273.49 | 8.42 | 2500.00

-- Aggregates + WHERE: the aggregate only sees the rows that survive WHERE.
SELECT sum(orderTotal) AS revenue FROM sales WHERE status = 'completed';    -- 145935.12
SELECT round(avg(orderTotal), 2) FROM sales WHERE productCategory = 'Laptops';

-- ---- Aggregates ignore NULL ----
SELECT round(avg(rating), 2) AS avg_rating, count(rating) AS votes, count(*) AS orders FROM sales;
-- 4.23 | 322 | 600  -- the average is over 322 votes, not 600 orders

SELECT avg(rating) FROM sales WHERE status = 'cancelled';
-- blank: NULL. No cancelled order was ever rated, and avg of nothing is NULL, not 0.

SELECT coalesce(avg(rating), 0) AS avg_rating FROM sales WHERE status = 'cancelled';   -- 0

-- ---- min / max work on dates and text too ----
SELECT min(orderDate) AS first_sale, max(orderDate) AS last_sale,
       max(orderDate) - min(orderDate) AS span_days
FROM sales;

SELECT min(customerLastName), max(customerLastName) FROM sales;   -- alphabetical ends

-- ---- Aggregates over expressions ----
SELECT sum(quantity)                             AS units_sold,
       sum(quantity * unitPrice)                 AS list_value,
       sum(quantity * unitPrice - orderTotal)    AS discounts_given,
       sum(orderTotal)                           AS revenue
FROM sales
WHERE status = 'completed';

SELECT sum(quantity * (productPrice - productCost)) AS gross_margin
FROM sales
WHERE status = 'completed';

-- ---- A share is an average of a CASE ----
SELECT sum(CASE WHEN channel = 'online' THEN 1 ELSE 0 END) AS online_orders,
       count(*)                                            AS all_orders,
       round(100.0 * sum(CASE WHEN channel = 'online' THEN 1 ELSE 0 END) / count(*), 1) AS online_pct
FROM sales;
-- 181 | 600 | 30.2

-- Postgres shorthand for the same idea: FILTER
SELECT count(*) FILTER (WHERE status = 'returned') AS returned,
       count(*)                                    AS total
FROM sales;
-- 44 | 600

-- ---- One number per WHAT? ----
SELECT productCategory, sum(orderTotal) FROM sales;
-- ERROR: column "sales.productcategory" must appear in the GROUP BY clause
--        or be used in an aggregate function
-- sum() collapses 600 rows into one. productCategory has 600 values.
-- Which one goes in the one row? Postgres won't guess. Part 5.
