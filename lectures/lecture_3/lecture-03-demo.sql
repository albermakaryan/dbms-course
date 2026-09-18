-- ============================================================
-- Lecture 3 — Asking Questions of One Table
-- YSU, Data Science for Business
--
-- SELECT, WHERE, ORDER BY, DISTINCT, aggregates, GROUP BY, HAVING --
-- on the shop's data one year on: a 600-row flat sales file and the
-- four normalized tables it splits into. One table at a time;
-- combining tables is Lecture 4.
--
-- Run this whole script at once (from the lecture_3/ folder, so the
-- \copy paths in Part 0 resolve), or run each part separately from
-- steps/00-setup.sql through steps/06-drill.sql (numbered to match
-- the Parts in lecture-03-notes.md). Five statements error ON
-- PURPOSE -- the comments say which.
-- ============================================================



-- ============================================================
-- Lecture 3 — Part 0: load the data
--
-- The shop from Lectures 1-2, one year later. Same four tables, but
-- the business grew and every table picked up columns. Creates FIVE
-- tables and fills them from data/*.csv:
--
--   sales      the flat file -- one row per sale with EVERYTHING on
--              it: 29 columns, 600 rows. Same idea as Lecture 2's
--              sales_raw, a year of data instead of a month.
--   customers  \
--   employees   |  the same 600 sales, split the way Lecture 2 split
--   products    |  them. Same facts, no repetition.
--   orders     /
--
-- Both shapes hold exactly the same facts. Today you query whichever
-- answers the question with less typing -- mostly the flat one,
-- because it has the names on it. Next lecture puts the four back
-- together.
--
-- \copy resolves paths relative to where you STARTED psql, so run
-- this from the lecture_3/ folder:    psql lecture03
--                                     \i steps/00-setup.sql
-- Safe to re-run: drops and recreates everything.
-- CSVs not reachable? Run everything above the "Load" line, then
--   \i data/all_inserts.sql
-- ============================================================

DROP TABLE IF EXISTS sales, orders, customers, employees, products;

-- ---- The flat file: one wide table, one row per sale ----
CREATE TABLE sales (
    orderID              INT,
    orderDate            DATE,
    orderTime            TIME,
    channel              VARCHAR(10),      -- in_store / online
    status               VARCHAR(10),      -- completed / returned / cancelled
    paymentMethod        VARCHAR(10),      -- cash / card / transfer
    quantity             INT,
    unitPrice            DECIMAL(8,2),
    discountPct          INT,
    orderTotal           DECIMAL(10,2),
    deliveryDate         DATE,             -- online orders only
    rating               INT,              -- 1-5, when the customer bothered
    customerFirstName    VARCHAR(50),
    customerLastName     VARCHAR(50),
    customerEmail        VARCHAR(100),
    customerCity         VARCHAR(50),
    customerBirthDate    DATE,
    customerSignupDate   DATE,
    customerAnniversary  DATE,
    customerMoneySpent   DECIMAL(10,2),
    employeeFirstName    VARCHAR(50),      -- empty for online orders
    employeeLastName     VARCHAR(50),
    employeePosition     VARCHAR(30),
    employeeBranch       VARCHAR(50),
    productName          VARCHAR(100),
    productCategory      VARCHAR(50),
    productBrand         VARCHAR(50),
    productPrice         DECIMAL(8,2),
    productCost          DECIMAL(8,2)
);

-- ---- The four normalized tables ----
CREATE TABLE customers (
    customerID   SERIAL PRIMARY KEY,
    firstName    VARCHAR(50)  NOT NULL,
    lastName     VARCHAR(50)  NOT NULL,
    email        VARCHAR(100) NOT NULL UNIQUE,
    phone        VARCHAR(20),
    city         VARCHAR(50)  NOT NULL,
    birthDate    DATE,
    signupDate   DATE         NOT NULL,
    anniversary  DATE,
    moneySpent   DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (moneySpent >= 0)
);

CREATE TABLE employees (
    employeeID   SERIAL PRIMARY KEY,
    firstName    VARCHAR(50)  NOT NULL,
    lastName     VARCHAR(50)  NOT NULL,
    email        VARCHAR(100) NOT NULL UNIQUE,
    birthDate    DATE,
    hireDate     DATE         NOT NULL,
    position     VARCHAR(30)  NOT NULL,
    branch       VARCHAR(50)  NOT NULL,
    salary       DECIMAL(8,2) NOT NULL CHECK (salary > 0)
);

CREATE TABLE products (
    productID      SERIAL PRIMARY KEY,
    productName    VARCHAR(100) NOT NULL,
    category       VARCHAR(50)  NOT NULL,
    brand          VARCHAR(50)  NOT NULL,
    price          DECIMAL(8,2) NOT NULL CHECK (price >= 0),
    cost           DECIMAL(8,2) NOT NULL CHECK (cost  >= 0),
    stockQuantity  INT          NOT NULL DEFAULT 0 CHECK (stockQuantity >= 0),
    isActive       BOOLEAN      NOT NULL DEFAULT TRUE,
    UNIQUE (productName, brand)
);

CREATE TABLE orders (
    orderID        INT PRIMARY KEY,
    customerID     INT NOT NULL REFERENCES customers(customerID),
    employeeID     INT          REFERENCES employees(employeeID),   -- NULL = online, nobody served it
    productID      INT NOT NULL REFERENCES products(productID),
    quantity       INT NOT NULL CHECK (quantity > 0),
    unitPrice      DECIMAL(8,2) NOT NULL CHECK (unitPrice >= 0),
    discountPct    INT NOT NULL DEFAULT 0 CHECK (discountPct BETWEEN 0 AND 100),
    orderTotal     DECIMAL(10,2) NOT NULL CHECK (orderTotal >= 0),
    orderDate      DATE NOT NULL,
    orderTime      TIME NOT NULL,
    channel        VARCHAR(10) NOT NULL CHECK (channel IN ('in_store', 'online')),
    paymentMethod  VARCHAR(10) NOT NULL CHECK (paymentMethod IN ('cash', 'card', 'transfer')),
    status         VARCHAR(10) NOT NULL CHECK (status IN ('completed', 'returned', 'cancelled')),
    deliveryDate   DATE,
    rating         INT CHECK (rating BETWEEN 1 AND 5)
);

-- ---- Load. Parents before orders -- the foreign keys insist. ----
-- An empty field in a CSV (no anniversary, no employee, no rating) becomes NULL.
\copy sales     FROM 'data/sales_flat.csv' WITH (FORMAT csv, HEADER true)
\copy customers FROM 'data/customers.csv'  WITH (FORMAT csv, HEADER true)
\copy employees FROM 'data/employees.csv'  WITH (FORMAT csv, HEADER true)
\copy products  FROM 'data/products.csv'   WITH (FORMAT csv, HEADER true)
\copy orders    FROM 'data/orders.csv'     WITH (FORMAT csv, HEADER true)

-- The CSVs carry their own ids, so each SERIAL counter still thinks the
-- next id is 1. Move them past what's loaded, or the first INSERT
-- without an id would collide with row 1.
SELECT setval(pg_get_serial_sequence('customers', 'customerid'), (SELECT max(customerID) FROM customers));
SELECT setval(pg_get_serial_sequence('employees', 'employeeid'), (SELECT max(employeeID) FROM employees));
SELECT setval(pg_get_serial_sequence('products',  'productid'),  (SELECT max(productID)  FROM products));

-- Expect 600 / 30 / 8 / 37 / 600
SELECT 'sales' AS t, count(*) FROM sales
UNION ALL SELECT 'customers', count(*) FROM customers
UNION ALL SELECT 'employees', count(*) FROM employees
UNION ALL SELECT 'products',  count(*) FROM products
UNION ALL SELECT 'orders',    count(*) FROM orders;


-- ============================================================
-- Lecture 3 — Part 1: SELECT is a list of expressions
-- Run after steps/00-setup.sql. Expected results in the comments
-- came from running this against Postgres 16.
-- ============================================================

-- ---- What's in here? ----
SELECT count(*) FROM sales;          -- 600

SELECT * FROM sales LIMIT 3;         -- 29 columns. Unreadable. Don't do this.

-- psql trick for ONE wide row: \x flips to one-column-per-line display
\x
SELECT * FROM sales LIMIT 1;
\x

-- Or just ask what the columns are:
\d sales

-- ---- Choose columns. Always. ----
SELECT orderID, orderDate, productName, orderTotal
FROM sales
LIMIT 5;

-- ---- Columns can be expressions ----
-- Arithmetic on numbers; AS names the result.
SELECT orderID, quantity, unitPrice, discountPct, orderTotal,
       quantity * unitPrice               AS list_total,
       quantity * unitPrice - orderTotal  AS discount_given
FROM sales
LIMIT 5;

-- The products table: what does the shop make on each item?
SELECT productName, price, cost,
       price - cost                              AS margin,
       round((price - cost) / price * 100, 1)    AS margin_pct
FROM products
LIMIT 5;

-- AS is optional, but an alias with a space or capitals needs double quotes.
SELECT productName, round(price * 1.2, 2) AS "Price incl. VAT" FROM products LIMIT 3;

-- ---- Text ----
SELECT customerFirstName || ' ' || customerLastName AS customer,   -- || glues text
       upper(customerCity)                          AS city,
       length(customerEmail)                        AS email_length
FROM sales
LIMIT 5;

SELECT email,
       split_part(email, '@', 2) AS domain,     -- piece 2 when split at '@'
       lower(firstName)          AS handle
FROM customers
LIMIT 5;

-- ---- Dates and times ----
SELECT orderDate,
       EXTRACT(YEAR  FROM orderDate)  AS yr,
       EXTRACT(MONTH FROM orderDate)  AS mon,
       to_char(orderDate, 'Mon')      AS mon_name,
       to_char(orderDate, 'Dy')       AS weekday,
       orderTime,
       EXTRACT(HOUR FROM orderTime)   AS hr
FROM sales
LIMIT 5;

-- Date minus date = a number of days.
SELECT orderID, orderDate, deliveryDate,
       deliveryDate - orderDate AS days_to_deliver
FROM sales
WHERE channel = 'online'
LIMIT 5;

-- age() gives an interval; EXTRACT pulls the years out of it.
-- Pinned to a fixed date so your output matches this file.
SELECT firstName, lastName, birthDate,
       age(DATE '2024-12-31', birthDate)                     AS age_at_year_end,
       EXTRACT(YEAR FROM age(DATE '2024-12-31', birthDate))  AS years
FROM customers
LIMIT 5;

-- Today's date is a function. This one's output depends on when you run it.
SELECT CURRENT_DATE, CURRENT_DATE - DATE '2024-01-01' AS days_since_new_year;

-- ---- CASE WHEN: a value that depends on a condition ----
SELECT orderID, orderTotal,
       CASE
           WHEN orderTotal >= 1000 THEN 'large'
           WHEN orderTotal >= 100  THEN 'medium'
           ELSE                         'small'
       END AS size
FROM sales
LIMIT 8;

-- Conditions are checked top to bottom; the first true one wins.
SELECT firstName, lastName, moneySpent,
       CASE
           WHEN moneySpent >= 10000 THEN 'Gold'
           WHEN moneySpent >= 3000  THEN 'Silver'
           ELSE                          'Bronze'
       END AS tier
FROM customers
LIMIT 8;

-- Without ELSE, anything that matches nothing becomes NULL.
SELECT orderID, rating,
       CASE WHEN rating >= 4 THEN 'happy' WHEN rating <= 2 THEN 'unhappy' END AS mood
FROM sales
LIMIT 8;

-- ---- One rule to remember ----
-- An alias is invented by SELECT. Nothing that runs BEFORE SELECT can
-- see it -- and WHERE runs before SELECT (Part 2).


-- ============================================================
-- Lecture 3 — Part 2: WHERE, properly
-- Run after Part 1.
-- ============================================================

-- ---- Equality. Text is case-sensitive. ----
SELECT orderID, productName, orderTotal FROM sales WHERE productCategory = 'Laptops' LIMIT 5;

SELECT count(*) FROM sales WHERE productCategory = 'Laptops';    -- 51
SELECT count(*) FROM sales WHERE productCategory = 'laptops';    -- 0. Not an error. Zero rows.

-- ---- Comparison ----
SELECT count(*) FROM sales WHERE status <> 'completed';          -- 71  (<> means "not equal"; != also works)
SELECT count(*) FROM sales WHERE orderTotal >= 1000;             -- 34
SELECT count(*) FROM sales WHERE orderDate >= '2024-12-01';      -- 86  (dates compare like numbers)

-- ---- BETWEEN is inclusive on both ends ----
SELECT count(*) FROM sales WHERE orderTotal BETWEEN 100 AND 200;                        -- 88
SELECT count(*) FROM sales WHERE orderDate  BETWEEN '2024-12-01' AND '2024-12-31';      -- 86

-- ---- IN: any of these ----
SELECT count(*) FROM sales WHERE productCategory IN ('Laptops', 'Phones', 'Tablets');   -- 126

SELECT productName, brand, price
FROM products
WHERE brand IN ('Apple', 'Samsung')
ORDER BY price DESC;

-- ---- LIKE: patterns. % = anything, _ = exactly one character ----
SELECT DISTINCT customerLastName FROM sales WHERE customerLastName LIKE 'S%';   -- starts with S
SELECT count(*) FROM sales WHERE customerEmail LIKE '%@gmail.com';              -- 378
SELECT firstName, lastName FROM customers WHERE firstName LIKE 'A__';           -- exactly three letters

-- LIKE is case-sensitive too. ILIKE isn't.
SELECT productName FROM products WHERE productName LIKE  '%usb%';    -- 0 rows
SELECT productName FROM products WHERE productName ILIKE '%usb%';    -- 3 rows

-- ---- AND, OR, NOT ----
SELECT count(*) FROM sales WHERE channel = 'online' AND status = 'completed';   -- 164
SELECT count(*) FROM sales WHERE NOT status = 'completed';                       -- 71, same as <>
SELECT count(*) FROM sales WHERE productCategory NOT IN ('Cables', 'Accessories');   -- 416

-- ---- The precedence trap: AND binds tighter than OR ----
-- "Laptops or phones, over 1000"?
SELECT count(*) FROM sales
WHERE productCategory = 'Laptops' OR productCategory = 'Phones' AND orderTotal > 1000;
-- 55

-- That was read as:  Laptops  OR  (Phones AND > 1000).  Every laptop got in.
SELECT count(*) FROM sales
WHERE productCategory = 'Laptops' OR (productCategory = 'Phones' AND orderTotal > 1000);
-- 55 -- identical. This is what you wrote, whether you meant it or not.

-- What you meant:
SELECT count(*) FROM sales
WHERE (productCategory = 'Laptops' OR productCategory = 'Phones') AND orderTotal > 1000;
-- 33

-- Rule: the moment AND and OR share a WHERE, put parentheses. Every time.

-- ---- A BOOLEAN column is already a condition ----
SELECT productName FROM products WHERE NOT isActive;    -- K380: discontinued
SELECT count(*)    FROM products WHERE isActive;        -- 36

-- ---- NULL ----
SELECT firstName, lastName, anniversary FROM customers WHERE anniversary = NULL;
-- 0 rows. NOT an error. Nothing is "= NULL" -- not even NULL.

SELECT firstName, lastName FROM customers WHERE anniversary IS NULL;        -- 7 rows
SELECT count(*)            FROM customers WHERE anniversary IS NOT NULL;    -- 23

-- Online orders have no salesperson:
SELECT count(*) FROM sales WHERE employeeLastName IS NULL;                   -- 181

-- A comparison with NULL is neither true nor false, so WHERE drops the row.
-- deliveryDate is NULL for every in-store order, so only online ones can pass:
SELECT count(*) FROM sales WHERE deliveryDate - orderDate > 3;               -- 93

-- ---- Conditions on expressions ----
SELECT count(*) FROM sales WHERE EXTRACT(MONTH FROM orderDate) = 12;         -- 86
SELECT count(*) FROM sales WHERE quantity * unitPrice - orderTotal > 100;    -- 10: discounts over 100

-- ---- The alias rule, proven ----
SELECT orderID, quantity * unitPrice AS list_total
FROM sales
WHERE list_total > 2000;
-- ERROR: column "list_total" does not exist
-- WHERE runs BEFORE SELECT invents the alias. Repeat the expression:
SELECT orderID, quantity * unitPrice AS list_total
FROM sales
WHERE quantity * unitPrice > 2000;


-- ============================================================
-- Lecture 3 — Part 3: ORDER BY, LIMIT, OFFSET
-- Run after Part 2.
-- ============================================================

-- ---- ASC is the default ----
SELECT productName, price FROM products ORDER BY price;
SELECT productName, price FROM products ORDER BY price DESC LIMIT 5;

-- ---- Several columns: the second breaks ties in the first ----
SELECT productName, category, price
FROM products
ORDER BY category, price DESC;

-- Text sorts alphabetically. Watch the two Annas land next to each other.
SELECT lastName, firstName, city, birthDate
FROM customers
ORDER BY lastName, firstName;

-- ---- Sort by an expression, an alias, or a position ----
SELECT productName, price - cost AS margin
FROM products
ORDER BY margin DESC                      -- alias works here: ORDER BY runs AFTER SELECT
LIMIT 5;

SELECT productName, price, cost
FROM products
ORDER BY (price - cost) / price DESC      -- an expression that isn't even in SELECT
LIMIT 5;

SELECT productName, price FROM products ORDER BY 2 DESC LIMIT 3;   -- "column 2". Works. Fragile.

-- ---- NULLs sort as if they were bigger than everything ----
SELECT firstName, lastName, anniversary FROM customers ORDER BY anniversary;        -- NULLs at the END
SELECT firstName, lastName, anniversary FROM customers ORDER BY anniversary DESC;   -- NULLs FIRST
SELECT firstName, lastName, anniversary FROM customers ORDER BY anniversary DESC NULLS LAST;

-- ---- LIMIT without ORDER BY is not "the first five" ----
SELECT orderID, orderDate FROM sales LIMIT 5;
-- Whatever five rows the database happened to reach first. Not the
-- earliest, not the smallest ids. Different next week, maybe.

SELECT orderID, orderDate, orderTime FROM sales ORDER BY orderDate, orderTime LIMIT 5;
-- 1001..1005: the actual first five sales of the year.

-- ---- Ties: say how to break them, or the database decides ----
SELECT orderID, orderTotal FROM sales ORDER BY orderTotal DESC LIMIT 3;
-- three orders at 2500.00 -- fine, all three fit. Now ask for two:
SELECT orderID, orderTotal FROM sales ORDER BY orderTotal DESC LIMIT 2;
-- WHICH two? Unspecified. Add a tiebreaker:
SELECT orderID, orderTotal FROM sales ORDER BY orderTotal DESC, orderID LIMIT 2;

-- ---- OFFSET: skip some, then take some ----
SELECT orderID, orderTotal FROM sales ORDER BY orderTotal DESC, orderID LIMIT 5 OFFSET 5;   -- ranks 6-10

-- ---- Putting it together: top five December sales ----
SELECT orderID, orderDate, customerLastName, productName, orderTotal
FROM sales
WHERE EXTRACT(MONTH FROM orderDate) = 12 AND status = 'completed'
ORDER BY orderTotal DESC, orderID
LIMIT 5;


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


-- ============================================================
-- Lecture 3 — Part 6: verification drill
-- Run after Part 5. The shop owner asked an AI assistant for four
-- numbers. Every query runs without error and returns a plausible
-- answer. Every one is wrong. Have a theory for each BEFORE reading
-- the answers at the bottom.
-- ============================================================

-- Q1. "Total revenue for 2024."
SELECT sum(orderTotal) AS revenue FROM sales;
-- 164092.05

-- Q2. "How much has the average customer spent with us, lifetime?"
SELECT round(avg(customerMoneySpent), 2) AS avg_customer_spend FROM sales;
-- 6799.93

-- Q3. "How many different customers bought something in December?"
SELECT count(DISTINCT customerLastName) AS december_customers
FROM sales
WHERE orderDate BETWEEN '2024-12-01' AND '2024-12-31';
-- 24

-- Q4. "What share of our orders are laptops?"
SELECT sum(CASE WHEN productCategory = 'Laptops' THEN 1 ELSE 0 END) / count(*) AS laptop_share
FROM sales;
-- 0


-- ============================================================
-- Answers. Don't scroll here until you have a theory for all four.
-- ============================================================

-- Q1 -- status. 71 of the 600 rows are returned or cancelled orders.
-- Their totals are in the table; they are not revenue.
SELECT sum(orderTotal) AS revenue FROM sales WHERE status = 'completed';   -- 145935.12
-- Overstated by 18,156.93. Every "revenue" query this year needs that WHERE.

-- Q2 -- grain. The flat file repeats a customer's lifetime total on
-- EVERY one of their orders. Aram Vardanyan's 13,544.72 is in there 40
-- times; Diana Aleksanyan's 2,327.00 four times. That's an average of ORDERS
-- weighted by how much people buy, not an average of customers.
SELECT round(avg(moneySpent), 2) FROM customers;                        -- 4864.50 (all 30)
SELECT round(avg(moneySpent), 2) FROM customers WHERE moneySpent > 0;   -- 5211.97 (the 28 who bought)
-- Which of those two is "right" is a business decision; 6799.93 is
-- neither. Before you avg() anything: one row per WHAT?

-- Q3 -- identity. Three different Sargsyans, two of them named Anna.
-- A surname is not a person; neither is a name.
SELECT count(DISTINCT customerEmail) AS december_customers
FROM sales
WHERE orderDate BETWEEN '2024-12-01' AND '2024-12-31';                 -- 26
-- count(DISTINCT x) counts distinct x. Make x something that
-- identifies what you're counting.

-- Q4 -- integer division. Both sides are whole numbers, so 51 / 600
-- is 0 with the remainder thrown away. Make one side a decimal:
SELECT round(100.0 * sum(CASE WHEN productCategory = 'Laptops' THEN 1 ELSE 0 END) / count(*), 1)
       AS laptop_pct
FROM sales;                                                            -- 8.5
-- 0 looked like "no laptops". 51 laptops were sold.

-- Business impact, one sentence each -- the format you'll use all semester:
--   Q1: 2024 revenue is overstated by 18,156.93; returns and
--       cancellations were booked as sales.
--   Q2: the average customer is worth 4,864, not 6,800 -- a marketing
--       budget sized on 6,800 overspends by 40%.
--   Q3: two December customers went uncounted, and any surname shared
--       by two people will be miscounted the same way every month.
--   Q4: the laptop share reads as zero; a buyer trusting it would stop
--       stocking the shop's biggest revenue category.
