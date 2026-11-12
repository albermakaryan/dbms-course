-- ============================================================
-- Lecture 6 — Window Functions
-- YSU, Data Science for Business
--
-- Window functions: OVER, PARTITION BY, ORDER BY inside OVER, ranking
-- (row_number, rank, dense_rank, ntile), top-N per group, lag/lead and
-- first/last/nth_value, frames (ROWS, RANGE, GROUPS), and how windows
-- meet NULLs, joins, FILTER and the star schema -- on the same shop
-- data as Lectures 4 and 5. Most answers can be checked against a
-- number you already know.
--
-- Needs PostgreSQL 11 or later (GROUPS frames and RANGE with an offset,
-- Part 6). Checked on PostgreSQL 14, 16 and 18: identical results.
--
-- Run this whole script at once (from the lecture_6/ folder, so the
-- \copy paths in Part 0 resolve), or run each part separately from
-- steps/00-setup.sql through steps/08-drill.sql (numbered to match
-- the Parts in lecture-06-notes.md). Four statements error ON
-- PURPOSE -- the comments say which. Twenty-five more are WRONG on
-- purpose and run without any error -- the comments say which, and
-- what the right answer is.
-- ============================================================



-- ============================================================
-- Lecture 6 — Part 0: load the data
--
-- The same shop data as Lectures 4 and 5 -- the same five CSV files
-- (byte-identical copies in data/) -- plus Lecture 4's star schema,
-- rebuilt by the same statements. Creates TEN tables:
--
--   customers, employees (with managerID), products   as in Lecture 5
--   orders        one row per ORDER (the header, with orderTotal)
--   order_items   one row per PRODUCT IN AN ORDER (the lines, with lineTotal)
--   dim_date, dim_customer, dim_product, dim_employee, fact_sales
--                 Lecture 4's star: one fact row per order line,
--                 online orders on employee key 0 '(online)'
--
-- 600 orders, 965 lines, Levon and Astghik never ordered, Ergonomic
-- Chair Pro never sold, 181 online orders with no employee, completed
-- revenue 157,078.41. (Lecture 4's flat sales table isn't used in this
-- lecture and isn't loaded.)
--
-- DROPS and recreates the lecture06 database, then connects to it --
-- so start psql in ANOTHER database (psql postgres), not in lecture06:
-- PostgreSQL can't drop the database you are connected to.
--
-- \copy resolves paths relative to where you STARTED psql, so run
-- this from the lecture_6/ folder:    psql postgres
--                                     \i steps/00-setup.sql
-- Safe to re-run: it starts from an empty database every time.
-- ============================================================

-- ---- The database: start from an empty one every time ----
-- (The two commented lines are the gentler alternative: create the
-- database only if it's missing. Postgres has no CREATE DATABASE IF NOT
-- EXISTS, so that SELECT produces the text of a CREATE DATABASE
-- statement only when no lecture06 exists, and \gexec runs it.)
-- SELECT 'CREATE DATABASE lecture06'
-- WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'lecture06')\gexec
DROP DATABASE IF EXISTS lecture06;
CREATE DATABASE lecture06;

\c lecture06

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
    salary       DECIMAL(8,2) NOT NULL CHECK (salary > 0),
    managerID    INT REFERENCES employees(employeeID)   -- who this person reports to; NULL = nobody
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

-- ---- The order header: one row per order ----
CREATE TABLE orders (
    orderID        INT PRIMARY KEY,
    customerID     INT NOT NULL REFERENCES customers(customerID),
    employeeID     INT          REFERENCES employees(employeeID),   -- NULL = online, nobody served it
    orderDate      DATE NOT NULL,
    orderTime      TIME NOT NULL,
    channel        VARCHAR(10) NOT NULL CHECK (channel IN ('in_store', 'online')),
    paymentMethod  VARCHAR(10) NOT NULL CHECK (paymentMethod IN ('cash', 'card', 'transfer')),
    status         VARCHAR(10) NOT NULL CHECK (status IN ('completed', 'returned', 'cancelled')),
    deliveryDate   DATE,
    rating         INT CHECK (rating BETWEEN 1 AND 5),
    orderTotal     DECIMAL(10,2) NOT NULL CHECK (orderTotal >= 0)   -- = sum of the order's lineTotals
);

-- ---- The order lines: one row per product in an order ----
CREATE TABLE order_items (
    orderID      INT NOT NULL REFERENCES orders(orderID),
    productID    INT NOT NULL REFERENCES products(productID),
    quantity     INT NOT NULL CHECK (quantity > 0),
    unitPrice    DECIMAL(8,2) NOT NULL CHECK (unitPrice >= 0),
    discountPct  INT NOT NULL DEFAULT 0 CHECK (discountPct BETWEEN 0 AND 100),
    lineTotal    DECIMAL(10,2) NOT NULL CHECK (lineTotal >= 0),     -- quantity x unitPrice, minus the discount
    PRIMARY KEY (orderID, productID)
);

-- ---- Load. Parents before children -- the foreign keys insist. ----
-- (CSV fallback: replace the five \copy lines with  \i data/all_inserts.sql)
-- An empty field in a CSV (no anniversary, no employee, no rating) becomes NULL.
\copy customers   FROM 'data/customers.csv'   WITH (FORMAT csv, HEADER true)
-- employees.csv has no managerID column, so name the columns it does have.
\copy employees (employeeID, firstName, lastName, email, birthDate, hireDate, position, branch, salary) FROM 'data/employees.csv' WITH (FORMAT csv, HEADER true)
\copy products    FROM 'data/products.csv'    WITH (FORMAT csv, HEADER true)
\copy orders      FROM 'data/orders.csv'      WITH (FORMAT csv, HEADER true)
\copy order_items FROM 'data/order_items.csv' WITH (FORMAT csv, HEADER true)

-- The CSVs carry their own ids, so each SERIAL counter still thinks the
-- next id is 1. Move them past what's loaded, or the first INSERT
-- without an id would collide with row 1.
SELECT setval(pg_get_serial_sequence('customers', 'customerid'), (SELECT max(customerID) FROM customers));
SELECT setval(pg_get_serial_sequence('employees', 'employeeid'), (SELECT max(employeeID) FROM employees));
SELECT setval(pg_get_serial_sequence('products',  'productid'),  (SELECT max(productID)  FROM products));

-- ---- The reporting line (as in Lecture 4) ----
-- Vahe runs the Yerevan Center store and everyone reports up to him.
-- The two other branches have a Senior Sales lead in between.
UPDATE employees SET managerID = 3 WHERE employeeID IN (1, 2, 5, 8);   -- Gor, Ani, Hayk, Marine -> Vahe
UPDATE employees SET managerID = 5 WHERE employeeID IN (4, 6);         -- Nare, Lilit -> Hayk (Yerevan Mall)
UPDATE employees SET managerID = 8 WHERE employeeID = 7;               -- Arman -> Marine (Gyumri)

-- ---- Lecture 4's star schema, the same build (Lecture 4, Part 4) ----
-- Grain of fact_sales: one row per order LINE.
CREATE TABLE dim_date AS
SELECT d::date                        AS dateKey,
       EXTRACT(quarter FROM d)::int   AS quarter,
       EXTRACT(month FROM d)::int     AS month,
       to_char(d, 'Mon')              AS monthName,
       EXTRACT(isodow FROM d)::int    AS dayOfWeek,
       to_char(d, 'Dy')               AS dayName
FROM generate_series(DATE '2024-01-01', DATE '2024-12-31', INTERVAL '1 day') AS d;
ALTER TABLE dim_date ADD PRIMARY KEY (dateKey);

CREATE TABLE dim_customer AS
SELECT customerID                         AS customerKey,
       firstName || ' ' || lastName       AS customerName,
       city,
       EXTRACT(year FROM signupDate)::int AS signupYear
FROM customers;
ALTER TABLE dim_customer ADD PRIMARY KEY (customerKey);

CREATE TABLE dim_product AS
SELECT productID AS productKey, productName, brand, category
FROM products;
ALTER TABLE dim_product ADD PRIMARY KEY (productKey);

CREATE TABLE dim_employee AS
SELECT e.employeeID                                          AS employeeKey,
       e.firstName || ' ' || e.lastName                      AS employeeName,
       e.branch,
       coalesce(m.firstName || ' ' || m.lastName, '(none)')  AS managerName
FROM employees e
LEFT JOIN employees m ON m.employeeID = e.managerID;
-- The unknown member: online orders get employee key 0, never NULL.
INSERT INTO dim_employee VALUES (0, '(online)', 'Online', '(none)');
ALTER TABLE dim_employee ADD PRIMARY KEY (employeeKey);

CREATE TABLE fact_sales AS
SELECT o.orderID,
       i.productID                 AS productKey,
       o.orderDate                 AS dateKey,
       o.customerID                AS customerKey,
       coalesce(o.employeeID, 0)   AS employeeKey,
       o.channel,
       o.status,
       i.quantity,
       i.lineTotal                 AS revenue,
       i.quantity * p.cost         AS cost
FROM orders o
JOIN order_items i ON i.orderID   = o.orderID
JOIN products    p ON p.productID = i.productID;
ALTER TABLE fact_sales
    ADD PRIMARY KEY (orderID, productKey),
    ADD FOREIGN KEY (dateKey)     REFERENCES dim_date,
    ADD FOREIGN KEY (customerKey) REFERENCES dim_customer,
    ADD FOREIGN KEY (productKey)  REFERENCES dim_product,
    ADD FOREIGN KEY (employeeKey) REFERENCES dim_employee;

-- Collect table statistics now instead of waiting for autovacuum. The
-- planner picks join and sort methods from these numbers, and two
-- traps in this lecture (Parts 2.4 and 3.2) show results whose row
-- order or tie-breaking depends on the plan -- with fresh statistics
-- everyone gets the same plan, and the same result, in class.
ANALYZE;

-- Expect 30 / 8 / 37 / 600 / 965, and a 366 / 965 star
SELECT 'customers' AS t, count(*) FROM customers
UNION ALL SELECT 'employees',   count(*) FROM employees
UNION ALL SELECT 'products',    count(*) FROM products
UNION ALL SELECT 'orders',      count(*) FROM orders
UNION ALL SELECT 'order_items', count(*) FROM order_items
UNION ALL SELECT 'dim_date',    count(*) FROM dim_date
UNION ALL SELECT 'fact_sales',  count(*) FROM fact_sales;



-- ============================================================
-- Lecture 6 — Part 1: The problem windows solve
-- Run after steps/00-setup.sql.
--
-- GROUP BY answers "one number per group" -- and throws the rows
-- away to do it. Often you need the group's number AND the row:
-- each order next to its customer's total, each order as a share of
-- all revenue. A window function gives you both.
-- ============================================================

-- ---- 1.1 GROUP BY collapses the rows ----
-- Completed revenue per customer: one row per customer, the orders are gone.
SELECT customerID, sum(orderTotal) AS customer_total
FROM orders
WHERE status = 'completed'
GROUP BY customerID
ORDER BY customerID
LIMIT 3;
-- customerid | customer_total
--          1 |        6651.60
--          2 |        8838.85
--          3 |        4084.22

SELECT count(*) AS completed_orders,
       count(DISTINCT customerID) AS customers
FROM orders
WHERE status = 'completed';
-- completed_orders | customers
--              529 |        28

-- The question: "show each completed order NEXT TO its customer's
-- total." Try to keep the order columns and GROUP BY anyway:
-- Error on purpose:
SELECT orderID, customerID, orderTotal, sum(orderTotal) AS customer_total
FROM orders
WHERE status = 'completed'
GROUP BY customerID;
-- ERROR:  column "orders.orderid" must appear in the GROUP BY clause or be used in an aggregate function

-- ---- 1.2 Before windows: aggregate in a derived table, join it back ----
-- (Lecture 5, 1.4: a table subquery at customer grain, joined back to
-- the orders. Here the join is safe -- one row per customer on the
-- right -- but you have to check that yourself every time.)
SELECT o.orderID, o.customerID, o.orderTotal, t.customer_total
FROM orders o
JOIN (SELECT customerID, sum(orderTotal) AS customer_total
      FROM orders
      WHERE status = 'completed'
      GROUP BY customerID) AS t ON t.customerID = o.customerID
WHERE o.status = 'completed'
ORDER BY o.customerID, o.orderID
LIMIT 3;
-- orderid | customerid | ordertotal | customer_total
--    1018 |          1 |       9.90 |        6651.60
--    1036 |          1 |     184.38 |        6651.60
--    1041 |          1 |     629.10 |        6651.60

-- ...or a correlated subquery in SELECT (Lecture 5, Part 3). Note that
-- the status filter has to be written TWICE, once per query. Forget it
-- inside and the total quietly includes returned and cancelled orders.
SELECT o.orderID, o.customerID, o.orderTotal,
       (SELECT sum(o2.orderTotal)
        FROM orders o2
        WHERE o2.customerID = o.customerID
          AND o2.status = 'completed') AS customer_total
FROM orders o
WHERE o.status = 'completed'
ORDER BY o.customerID, o.orderID
LIMIT 3;
-- orderid | customerid | ordertotal | customer_total
--    1018 |          1 |       9.90 |        6651.60
--    1036 |          1 |     184.38 |        6651.60
--    1041 |          1 |     629.10 |        6651.60

-- ---- 1.3 The window version ----
-- sum(...) OVER (PARTITION BY customerID): "the sum over the rows that
-- share this row's customerID". Every input row stays.
SELECT orderID, customerID, orderTotal,
       sum(orderTotal) OVER (PARTITION BY customerID) AS customer_total
FROM orders
WHERE status = 'completed'
ORDER BY customerID, orderID
LIMIT 3;
-- orderid | customerid | ordertotal | customer_total
--    1018 |          1 |       9.90 |        6651.60
--    1036 |          1 |     184.38 |        6651.60
--    1041 |          1 |     629.10 |        6651.60
-- The same numbers as both older versions -- one query, no join, the
-- filter written once. (Part 7.5 proves all three agree on every row.)

-- ---- 1.4 The invariant: rows in = rows out ----
-- A query whose only "extra" is window functions returns exactly as
-- many rows as its input. Predict it, then check it.
SELECT count(*) AS rows_out
FROM (SELECT orderID,
             sum(orderTotal)   OVER ()                        AS all_orders,
             count(*)          OVER (PARTITION BY customerID) AS customer_orders,
             avg(orderTotal)   OVER (PARTITION BY status)     AS status_avg
      FROM orders) AS w;
-- rows_out
--      600
-- 600 in, 600 out. Three windows, three different groupings, and not
-- one row added or lost.

-- ---- 1.5 Callback: Lecture 4's fan-out (4.10) ----
-- To put each customer's moneySpent next to their orders, Lecture 4
-- JOINED -- and the join copied it onto every order:
SELECT count(*)          AS rows,
       sum(c.moneySpent) AS total_money_spent
FROM customers c
JOIN orders o ON o.customerID = c.customerID;
-- rows | total_money_spent
--  600 |        4386925.27
-- WRONG total: 30 customers became 600 rows, and the sum counted each
-- customer's moneySpent once per order.

-- A window brings a group number TO the rows that are already there.
-- It never adds rows, so there is nothing to multiply:
SELECT count(*)                         AS rows,
       sum(moneySpent)                  AS total_money_spent,
       min(all_customers)               AS window_total
FROM (SELECT moneySpent,
             sum(moneySpent) OVER () AS all_customers
      FROM customers) AS w;
-- rows | total_money_spent | window_total
--   30 |         157078.41 |    157078.41
-- 30 in, 30 out; the total is the known completed revenue.



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



-- ============================================================
-- Lecture 6 — Part 4: Top-N per group
-- Run after Part 3.
--
-- "Each customer's latest order" -- the last time we heard from them.
-- The most common window question at work, and three ways to answer it.
-- ============================================================

-- ---- 4.1 The loud one: a window function in WHERE ----
-- Number each customer's orders newest first, keep number 1:
-- Error on purpose:
SELECT customerID, orderID, orderDate,
       row_number() OVER (PARTITION BY customerID
                          ORDER BY orderDate DESC, orderTime DESC, orderID DESC) AS rn
FROM orders
WHERE rn = 1;
-- ERROR:  column "rn" does not exist

-- Error on purpose -- the function itself, not the alias:
SELECT customerID, orderID, orderDate
FROM orders
WHERE row_number() OVER (PARTITION BY customerID
                         ORDER BY orderDate DESC, orderTime DESC, orderID DESC) = 1;
-- ERROR:  window functions are not allowed in WHERE
-- Both errors are Part 2.5's picture: WHERE runs BEFORE window
-- functions exist. (The first error is the same reason a SELECT alias
-- can't be used in WHERE.) A loud error -- the friendly kind.

-- ---- 4.2 Method 1: row_number() in a CTE, filter outside ----
-- Lecture 5's CTE is the fix: compute the window in one step, filter
-- in the next, where rn is an ordinary column.
WITH ranked AS (
    SELECT customerID, orderID, orderDate, orderTime, orderTotal,
           row_number() OVER (PARTITION BY customerID
                              ORDER BY orderDate DESC, orderTime DESC, orderID DESC) AS rn
    FROM orders
)
SELECT customerID, orderID, orderDate, orderTime, orderTotal
FROM ranked
WHERE rn = 1
ORDER BY customerID;
-- customerid | orderid | orderdate  | ordertime | ordertotal
--          1 |    1591 | 2024-12-27 | 19:27:25  |      89.01
--          2 |    1593 | 2024-12-27 | 20:50:21  |      14.50
--          3 |    1585 | 2024-12-26 | 10:16:01  |      29.70
--          4 |    1567 | 2024-12-19 | 20:54:55  |      18.81
-- ... (28 rows)
-- 28 rows: one per customer WHO HAS ORDERS. Levon and Astghik have no
-- rows in orders, so they have no partition at all.

-- ---- 4.3 Method 2: LEFT JOIN LATERAL ... LIMIT 1 (Lecture 5, 3.5) ----
SELECT c.customerID, latest.orderID, latest.orderDate, latest.orderTime, latest.orderTotal
FROM customers c
LEFT JOIN LATERAL (SELECT o.orderID, o.orderDate, o.orderTime, o.orderTotal
                   FROM orders o
                   WHERE o.customerID = c.customerID
                   ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
                   LIMIT 1) AS latest ON true
ORDER BY c.customerID;
-- customerid | orderid | orderdate  | ordertime | ordertotal
--          1 |    1591 | 2024-12-27 | 19:27:25  |      89.01
--          2 |    1593 | 2024-12-27 | 20:50:21  |      14.50
--          3 |    1585 | 2024-12-26 | 10:16:01  |      29.70
--          4 |    1567 | 2024-12-19 | 20:54:55  |      18.81
-- ... (30 rows)

-- Row count check -- predict it first: 30 customers in.
SELECT count(*) AS rows, count(latest.orderID) AS with_an_order
FROM customers c
LEFT JOIN LATERAL (SELECT o.orderID
                   FROM orders o
                   WHERE o.customerID = c.customerID
                   ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
                   LIMIT 1) AS latest ON true;
-- rows | with_an_order
--   30 |            28

-- The inner JOIN LATERAL drops the customers whose subquery returned
-- nothing -- silently, like any inner join (Lecture 4, 4.2):
SELECT count(*) AS rows
FROM customers c
JOIN LATERAL (SELECT o.orderID
              FROM orders o
              WHERE o.customerID = c.customerID
              ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
              LIMIT 1) AS latest ON true;
-- rows
--   28
-- WRONG for this question: 30 customers in, 28 out. Levon and
-- Astghik are gone, no error. For
-- "when did we last hear from each customer?", the two who never ordered
-- are exactly the ones you need to see. LEFT JOIN LATERAL keeps them.

-- ---- 4.4 Method 3: DISTINCT ON (PostgreSQL only) ----
-- "Keep the first row of each customerID, in this ORDER BY."
SELECT DISTINCT ON (customerID)
       customerID, orderID, orderDate, orderTime, orderTotal
FROM orders
ORDER BY customerID, orderDate DESC, orderTime DESC, orderID DESC;
-- customerid | orderid | orderdate  | ordertime | ordertotal
--          1 |    1591 | 2024-12-27 | 19:27:25  |      89.01
--          2 |    1593 | 2024-12-27 | 20:50:21  |      14.50
--          3 |    1585 | 2024-12-26 | 10:16:01  |      29.70
--          4 |    1567 | 2024-12-19 | 20:54:55  |      18.81
-- ... (28 rows)
-- Shortest of the three -- and not standard SQL. MySQL, SQL Server and
-- SQLite don't have it; the row_number() version works on all of them.

-- Error on purpose: the ORDER BY must START with the DISTINCT ON columns.
SELECT DISTINCT ON (customerID) customerID, orderID, orderDate
FROM orders
ORDER BY orderDate DESC;
-- ERROR:  SELECT DISTINCT ON expressions must match initial ORDER BY expressions

-- The quiet version: the ORDER BY starts right, but says nothing about
-- WHICH row of each customer comes first.
SELECT DISTINCT ON (customerID) customerID, orderID, orderDate
FROM orders
ORDER BY customerID
LIMIT 3;
-- customerid | orderid | orderdate
--          1 |    1071 | 2024-02-28
--          2 |    1560 | 2024-12-18
--          3 |    1389 | 2024-09-27
-- WRONG: "the first row of each customer" in no particular order.
-- Compare with 4.4 above: customer 1's latest order is 1591 on
-- 2024-12-27, not this one. No error.

-- ---- 4.5 Prove the three agree: EXCEPT both ways (Lecture 5, 6.5) ----
-- For each pair of methods, rows in one but not the other. 0 rows in
-- both directions = the same result. (LATERAL's inner join here, so
-- all three cover the same 28 customers.)
WITH m1 AS (
    SELECT customerID, orderID
    FROM (SELECT customerID, orderID,
                 row_number() OVER (PARTITION BY customerID
                                    ORDER BY orderDate DESC, orderTime DESC, orderID DESC) AS rn
          FROM orders) AS r
    WHERE rn = 1
),
m2 AS (
    SELECT c.customerID, l.orderID
    FROM customers c
    JOIN LATERAL (SELECT o.orderID FROM orders o
                  WHERE o.customerID = c.customerID
                  ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
                  LIMIT 1) AS l ON true
),
m3 AS (
    SELECT DISTINCT ON (customerID) customerID, orderID
    FROM orders
    ORDER BY customerID, orderDate DESC, orderTime DESC, orderID DESC
)
SELECT (SELECT count(*) FROM (SELECT * FROM m1 EXCEPT SELECT * FROM m2) x) AS m1_not_m2,
       (SELECT count(*) FROM (SELECT * FROM m2 EXCEPT SELECT * FROM m1) x) AS m2_not_m1,
       (SELECT count(*) FROM (SELECT * FROM m1 EXCEPT SELECT * FROM m3) x) AS m1_not_m3,
       (SELECT count(*) FROM (SELECT * FROM m3 EXCEPT SELECT * FROM m1) x) AS m3_not_m1;
-- m1_not_m2 | m2_not_m1 | m1_not_m3 | m3_not_m1
--         0 |         0 |         0 |         0

-- ---- 4.6 THE TRAP: an incomplete ORDER BY -- inside the window, the
-- LATERAL subquery, or DISTINCT ON ----
-- "Latest order" = ORDER BY orderDate DESC, and nothing else.
-- Two customers placed two orders on their last day: Anna Sargsyan
-- (customer 1: orders 1589 and 1591 on 2024-12-27) and Armen Gevorgyan
-- (customer 12: 1595 and 1596 on 2024-12-28).
WITH m1 AS (
    SELECT customerID, orderID
    FROM (SELECT customerID, orderID,
                 row_number() OVER (PARTITION BY customerID ORDER BY orderDate DESC) AS rn
          FROM orders) AS r
    WHERE rn = 1
),
m2 AS (
    SELECT c.customerID, l.orderID
    FROM customers c
    JOIN LATERAL (SELECT o.orderID FROM orders o
                  WHERE o.customerID = c.customerID
                  ORDER BY o.orderDate DESC
                  LIMIT 1) AS l ON true
),
m3 AS (
    SELECT DISTINCT ON (customerID) customerID, orderID
    FROM orders
    ORDER BY customerID, orderDate DESC
)
SELECT 'row_number' AS method, customerID, orderID FROM m1 WHERE customerID IN (1, 12)
UNION ALL
SELECT 'lateral',              customerID, orderID FROM m2 WHERE customerID IN (1, 12)
UNION ALL
SELECT 'distinct on',          customerID, orderID FROM m3 WHERE customerID IN (1, 12)
ORDER BY customerID, method;
--   method    | customerid | orderid
-- distinct on |          1 |    1591
-- lateral     |          1 |    1589
-- row_number  |          1 |    1591
-- distinct on |         12 |    1595
-- lateral     |         12 |    1595
-- row_number  |         12 |    1595
-- WRONG, in two different ways:
-- * Anna: the methods DISAGREE (1589 vs 1591) -- an EXCEPT check
--   between them would catch it.
-- * Armen: all three AGREE on 1595 -- and all three are wrong. His
--   latest order is 1596 (14:28, after 1595 at 12:06). An EXCEPT check
--   says "0 rows, identical". Agreement only proves something when each
--   method's question has exactly one answer.
-- The fix is 4.2-4.4: orderDate DESC, orderTime DESC, orderID DESC --
-- complete, so the last key is unique.

-- ---- 4.7 Top 2, not top 1 ----
-- DISTINCT ON can only keep ONE row per group. The other two methods
-- just change a number. "Each customer's two most recent orders":
WITH ranked AS (
    SELECT customerID, orderID,
           row_number() OVER (PARTITION BY customerID
                              ORDER BY orderDate DESC, orderTime DESC, orderID DESC) AS rn
    FROM orders
)
SELECT count(*) AS rows, count(DISTINCT customerID) AS customers
FROM ranked
WHERE rn <= 2;
-- rows | customers
--   56 |        28
-- Predict: every customer who ordered has at least 4 orders (Diana),
-- so 28 x 2 = 56.

SELECT count(*) AS rows, count(l.orderID) AS order_rows
FROM customers c
LEFT JOIN LATERAL (SELECT o.orderID FROM orders o
                   WHERE o.customerID = c.customerID
                   ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
                   LIMIT 2) AS l ON true;
-- rows | order_rows
--   58 |         56
-- 56 order rows + 2 NULL-padded rows for Levon and Astghik = 58.



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
-- orderid | orderdate  | ordertotal | previous_order |  change
--    1276 | 2024-07-24 |    1598.00 |                |
--    1307 | 2024-08-10 |    1062.50 |        1598.00 |  -535.50
--    1373 | 2024-09-20 |      24.40 |        1062.50 | -1038.10
--    1577 | 2024-12-23 |     177.00 |          24.40 |   152.60
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
-- firstname |   lastname   | previous_order | came_back_on | days_quiet
-- Lusine    | Avetisyan    | 2024-02-27     | 2024-07-24   |        148
-- Mher      | Sargsyan     | 2024-05-20     | 2024-10-04   |        137
-- Samvel    | Nazaryan     | 2024-05-17     | 2024-09-10   |        116
-- Gayane    | Mnatsakanyan | 2024-03-15     | 2024-06-29   |        106
-- Diana     | Aleksanyan   | 2024-01-19     | 2024-05-03   |        105
-- Diana     | Aleksanyan   | 2024-06-29     | 2024-10-07   |        100
-- Lusine    | Avetisyan    | 2024-09-20     | 2024-12-23   |         94
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
-- orderid | orderdate  | ordertotal | previous_order |  change
--    1276 | 2024-07-24 |    1598.00 |              0 |  1598.00
--    1307 | 2024-08-10 |    1062.50 |        1598.00 |  -535.50
--    1373 | 2024-09-20 |      24.40 |        1062.50 | -1038.10
--    1577 | 2024-12-23 |     177.00 |          24.40 |   152.60
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
-- avg_change_null | changes_null | avg_change_zero | changes_zero
--            1.42 |          501 |           17.23 |          529
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
-- employeeid | month | revenue | prev_month | change
--          4 |     1 |  332.40 |            |
--          4 |     3 |  872.59 |     332.40 | 540.19
--          4 |     4 |  829.34 |     872.59 | -43.25
--          4 |     5 | 1755.93 |     829.34 | 926.59
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
-- report_rows | wrong_month | months_missing
--          88 |           7 |              8
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
-- employeeid | month | revenue | prev_month | change
--          4 |     1 |  332.40 |            |
--          4 |     2 |       0 |     332.40 | -332.40
--          4 |     3 |  872.59 |          0 |  872.59
--          4 |     4 |  829.34 |     872.59 |  -43.25
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
-- report_rows |   total
--          96 | 100222.48

SELECT sum(orderTotal) AS in_store_completed
FROM orders
WHERE status = 'completed' AND employeeID IS NOT NULL;
-- in_store_completed
--          100222.48
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
-- orderid | orderdate  |  status   | next_order | days_to_next
--    1069 | 2024-02-27 | returned  | 2024-07-24 |          148
--    1276 | 2024-07-24 | completed | 2024-08-10 |           17
--    1307 | 2024-08-10 | completed | 2024-09-20 |           41
--    1373 | 2024-09-20 | completed | 2024-12-23 |           94
--    1577 | 2024-12-23 | completed |            |
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
-- returns | followed_by_an_order | avg_days_to_next
--      44 |                   42 |             22.0

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
-- firstname |  lastname   | orderid | returned_order_date
-- Vahan     | Torosyan    |    1590 | 2024-12-27
-- Karen     | Khachatryan |    1587 | 2024-12-27
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
-- orderid | orderdate  | ordertotal | first_order | second_order
--    1276 | 2024-07-24 |    1598.00 |     1598.00 |
--    1307 | 2024-08-10 |    1062.50 |     1598.00 |      1062.50
--    1373 | 2024-09-20 |      24.40 |     1598.00 |      1062.50
--    1577 | 2024-12-23 |     177.00 |     1598.00 |      1062.50
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
-- first_channel | customers | revenue  | revenue_per_customer
-- in_store      |        16 | 93458.77 |              5841.17
-- online        |        12 | 63619.64 |              5301.64
-- Reading the result: 16 customers came in through a store, 12 online.
-- Store-acquired customers spent 5,841.17 each, online-acquired
-- 5,301.64 -- about 9% less, on 28 customers in total. A hint, not a
-- proof. (first_value is safe with the default frame: the frame always
-- starts at the first row. last_value is not -- Part 6.4.)



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
-- orderid | orderdate  | orders_so_far
--    1001 | 2024-01-01 |             1
--    1002 | 2024-01-02 |             3
--    1003 | 2024-01-02 |             3

-- "The top 3 salespeople by completed revenue"
SELECT e.firstName, sum(o.orderTotal) AS revenue,
       rank() OVER (ORDER BY sum(o.orderTotal) DESC) AS revenue_rank
FROM orders o
LEFT JOIN employees e ON e.employeeID = o.employeeID
WHERE o.status = 'completed'
GROUP BY o.employeeID, e.firstName
ORDER BY revenue_rank
LIMIT 3;
-- firstname | revenue  | revenue_rank
--           | 56855.93 |            1
-- Ani       | 23856.98 |            2
-- Gor       | 21081.73 |            3

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
-- month | revenue |  change
--     5 | 1242.99 |
--     7 |   57.70 | -1185.29

-- "Each of Diana's orders next to her latest order"
SELECT customerID, orderID, orderTotal,
       last_value(orderID) OVER (PARTITION BY customerID
                                 ORDER BY orderDate, orderTime, orderID) AS latest_order
FROM orders
WHERE customerID = 27
ORDER BY orderDate;
-- customerid | orderid | ordertotal | latest_order
--         27 |    1024 |     620.00 |         1024
--         27 |    1165 |     349.00 |         1165
--         27 |    1246 |    1780.00 |         1246
--         27 |    1407 |     223.80 |         1407

-- "Each order's share of completed revenue" (the three biggest)
SELECT o.orderID, i.productID,
       round(100 * o.orderTotal / sum(o.orderTotal) OVER (), 3) AS pct_of_revenue
FROM orders o
JOIN order_items i ON i.orderID = o.orderID
WHERE o.status = 'completed'
ORDER BY o.orderTotal DESC, o.orderID, i.productID
LIMIT 3;
-- orderid | productid | pct_of_revenue
--    1158 |         1 |          1.008
--    1363 |         1 |          1.008
--    1385 |         1 |          1.008

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
-- orderid | orderdate  | orders_so_far
--    1001 | 2024-01-01 |             1
--    1002 | 2024-01-02 |             2
--    1003 | 2024-01-02 |             3

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
-- firstname | revenue  | revenue_rank
-- Ani       | 23856.98 |            1
-- Gor       | 21081.73 |            2
-- Hayk      | 19087.41 |            3

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
-- month | revenue |  change
--     5 | 1242.99 |  1223.19
--     6 |       0 | -1242.99
--     7 |   57.70 |    57.70

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
-- customerid | orderid | ordertotal | latest_order
--         27 |    1024 |     620.00 |         1407
--         27 |    1165 |     349.00 |         1407
--         27 |    1246 |    1780.00 |         1407
--         27 |    1407 |     223.80 |         1407

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
-- rows | orders | denominator
--  844 |    529 |   247923.72

-- Fix: the window over orders, one row per order.
SELECT orderID,
       round(100 * orderTotal / sum(orderTotal) OVER (), 3) AS pct_of_revenue
FROM orders
WHERE status = 'completed'
ORDER BY orderTotal DESC, orderID
LIMIT 3;
-- orderid | pct_of_revenue
--    1158 |          1.592
--    1363 |          1.592
--    1385 |          1.592
