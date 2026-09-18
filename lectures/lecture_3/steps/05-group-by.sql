-- ============================================================
-- Lecture 3 — Part 5: GROUP BY and HAVING
-- Run after Part 4.
-- ============================================================

-- ---- One row per group ----
SELECT productCategory, count(*) AS orders, sum(orderTotal) AS revenue
FROM sales
WHERE status = 'completed'
GROUP BY productCategory
ORDER BY revenue DESC;

-- ---- The rule: every SELECT column is grouped or aggregated ----
SELECT productCategory, productName, count(*)
FROM sales
GROUP BY productCategory;
-- ERROR: column "sales.productname" must appear in the GROUP BY clause
--        or be used in an aggregate function

-- ---- Several grouping columns: one row per combination that occurs ----
SELECT productCategory, productBrand, count(*) AS orders, sum(orderTotal) AS revenue
FROM sales
WHERE status = 'completed'
GROUP BY productCategory, productBrand
ORDER BY productCategory, revenue DESC;

SELECT channel, paymentMethod, count(*) AS orders
FROM sales
GROUP BY channel, paymentMethod
ORDER BY channel, paymentMethod;

-- ---- Group by an expression ----
SELECT EXTRACT(MONTH FROM orderDate) AS month, count(*) AS orders, sum(orderTotal) AS revenue
FROM sales
WHERE status = 'completed'
GROUP BY month            -- Postgres lets you use the alias here
ORDER BY month;

SELECT EXTRACT(DOW FROM orderDate) AS dow, to_char(orderDate, 'Dy') AS weekday, count(*) AS orders
FROM sales
GROUP BY dow, weekday
ORDER BY dow;
-- No 0 (Sunday). The shop is closed.

SELECT EXTRACT(HOUR FROM orderTime) AS hour, count(*) AS orders
FROM sales
WHERE channel = 'online'
GROUP BY hour
ORDER BY orders DESC
LIMIT 5;

SELECT split_part(email, '@', 2) AS domain, count(*) AS customers
FROM customers
GROUP BY domain
ORDER BY customers DESC;

-- ---- Group by a CASE: buckets ----
SELECT CASE
           WHEN orderTotal >= 1000 THEN 'large'
           WHEN orderTotal >= 100  THEN 'medium'
           ELSE                         'small'
       END AS size,
       count(*) AS orders, sum(orderTotal) AS revenue
FROM sales
WHERE status = 'completed'
GROUP BY size
ORDER BY min(orderTotal);     -- ORDER BY may use an aggregate that isn't in SELECT

-- ---- NULL is a group of its own ----
SELECT employeeLastName, count(*) AS orders
FROM sales
GROUP BY employeeLastName
ORDER BY orders DESC;
-- The blank row: 181 online orders, no salesperson.

SELECT rating, count(*) AS orders
FROM sales
GROUP BY rating
ORDER BY rating;
-- NULL sorts last: 278 unrated.

-- ---- What you group by decides what a "customer" is ----
SELECT customerFirstName, customerLastName, count(*) AS orders, sum(orderTotal) AS spent
FROM sales
WHERE customerLastName = 'Sargsyan'
GROUP BY customerFirstName, customerLastName;
-- 2 rows. "Anna Sargsyan: 37 orders." There is no such person.

SELECT customerFirstName, customerLastName, customerEmail, count(*) AS orders, sum(orderTotal) AS spent
FROM sales
WHERE customerLastName = 'Sargsyan'
GROUP BY customerFirstName, customerLastName, customerEmail;
-- 3 rows. Group by something that identifies a person, not a name.

-- ---- A real report: in-store performance ----
SELECT employeeFirstName || ' ' || employeeLastName AS employee,
       employeeBranch,
       count(*)                  AS orders,
       sum(orderTotal)           AS revenue,
       round(avg(orderTotal), 2) AS avg_ticket
FROM sales
WHERE status = 'completed' AND channel = 'in_store'
GROUP BY employee, employeeBranch
ORDER BY revenue DESC;

-- ---- HAVING: a WHERE for groups ----
SELECT customerEmail, count(*) AS orders, sum(orderTotal) AS spent
FROM sales
WHERE status = 'completed'
GROUP BY customerEmail
HAVING sum(orderTotal) > 8000
ORDER BY spent DESC;

-- Ratings you can trust: at least 10 votes
SELECT productName, count(rating) AS votes, round(avg(rating), 2) AS avg_rating
FROM sales
GROUP BY productName
HAVING count(rating) >= 10
ORDER BY avg_rating DESC, votes DESC;

-- WHERE can't do HAVING's job -- it runs before any group exists:
SELECT productCategory, count(*)
FROM sales
WHERE count(*) > 50
GROUP BY productCategory;
-- ERROR: aggregate functions are not allowed in WHERE

-- And HAVING can't see a SELECT alias -- it runs before SELECT:
SELECT productCategory, sum(orderTotal) AS revenue
FROM sales
GROUP BY productCategory
HAVING revenue > 10000;
-- ERROR: column "revenue" does not exist
-- Repeat the expression:
SELECT productCategory, sum(orderTotal) AS revenue
FROM sales
GROUP BY productCategory
HAVING sum(orderTotal) > 10000
ORDER BY revenue DESC;

-- ---- Everything at once ----
-- Second-half brands with at least 10 sales, by margin.
SELECT productBrand,
       count(*)                                      AS orders,
       sum(orderTotal)                               AS revenue,
       sum(quantity * (productPrice - productCost))  AS margin
FROM sales
WHERE status = 'completed' AND orderDate >= '2024-07-01'
GROUP BY productBrand
HAVING count(*) >= 10
ORDER BY margin DESC
LIMIT 5;

-- Return rate per category
SELECT productCategory,
       count(*)                                     AS orders,
       count(*) FILTER (WHERE status = 'returned')  AS returned,
       round(100.0 * count(*) FILTER (WHERE status = 'returned') / count(*), 1) AS return_pct
FROM sales
GROUP BY productCategory
ORDER BY return_pct DESC;

-- FROM -> WHERE -> GROUP BY -> HAVING -> SELECT -> DISTINCT -> ORDER BY -> LIMIT
-- You write SELECT first. It runs fifth. Every error in this file is that fact.
--
-- "Query-generated data" comes in two kinds, born at two different steps:
--   aggregates  (sum, count, ...)  are computed at GROUP BY, step 3.
--                HAVING sees them -- even ones SELECT never outputs.
--   aliases     (AS revenue)        are invented at SELECT, step 5.
--                HAVING can't see them; ORDER BY can.
-- Proof, both on the same grouping:
SELECT productCategory FROM sales GROUP BY productCategory HAVING sum(orderTotal) > 10000;   -- works: 5 rows
SELECT productCategory, sum(orderTotal) AS revenue FROM sales GROUP BY productCategory HAVING revenue > 10000;
-- ERROR: column "revenue" does not exist
