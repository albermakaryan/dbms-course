-- ============================================================
-- Lecture 8 — Part 0, step 1: the PostgreSQL side
--
-- Two kinds of tables, both as in Lecture 7:
--   * the small shop (byte-identical CSVs in data/):
--       customers, employees, products, orders, order_items
--     600 orders (529 completed), completed revenue 157,078.41
--   * orders_big: 5,000,000 generated orders, Lecture 7's generator
--     with the same seed, so the same rows on PostgreSQL 15 and later
--
-- DROPS and recreates the lecture08 database, so start psql in
-- ANOTHER database. Run it from the lecture_8/ folder:
--     psql postgres
--     \i steps/00-setup.sql
-- About 40 seconds. Then run steps/00-make-files.py (Python), which
-- writes the CSV and Parquet files the rest of the lecture reads.
-- ./setup.sh (or the notebook's setup button) runs both.
-- ============================================================

\set ON_ERROR_STOP on

-- WITH (FORCE): disconnect anyone still connected to lecture08 (the
-- notebook, a psql terminal) instead of failing. PostgreSQL 13+.
DROP DATABASE IF EXISTS lecture08 WITH (FORCE);
CREATE DATABASE lecture08;
\c lecture08

-- ================= 1. The small shop (as Lectures 4-7) =================
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

-- ================= 2. The big table =================
-- setseed() fixes the sequence random() returns, so every machine
-- (PostgreSQL 15+) gets exactly the same rows.
SELECT setseed(0.42);

-- ---- orders_big: 5,000,000 orders, the same columns as orders ----
-- * orderID 1..5,000,000, in date order (like a real order counter)
-- * orderDate: 2023-01-01 .. 2025-12-31, three years, growing a bit
--   each year (1.37M, 1.73M, 1.90M orders)
-- * customerID: 48,000 customers order, about 104 orders each; every
--   25th customer (25, 50, ..., 50,000) never orders
-- * status: about 92% completed, 4.8% returned, 3.2% cancelled
-- * channel: a third online, and online orders have NO employee
--   (employeeID NULL), as in the small data
-- No foreign keys, so the load stays fast.
CREATE TABLE orders_big (
    orderID        INT PRIMARY KEY,
    customerID     INT NOT NULL,
    employeeID     INT,                       -- NULL = online, nobody served it
    orderDate      DATE NOT NULL,
    orderTime      TIME NOT NULL,
    channel        VARCHAR(10) NOT NULL CHECK (channel IN ('in_store', 'online')),
    paymentMethod  VARCHAR(10) NOT NULL CHECK (paymentMethod IN ('cash', 'card', 'transfer')),
    status         VARCHAR(10) NOT NULL CHECK (status IN ('completed', 'returned', 'cancelled')),
    deliveryDate   DATE,
    rating         INT CHECK (rating BETWEEN 1 AND 5),
    orderTotal     DECIMAL(10,2) NOT NULL CHECK (orderTotal >= 0)
);

INSERT INTO orders_big
SELECT i,
       c + (c - 1) / 24,                                   -- skips every 25th customer
       CASE WHEN online THEN NULL ELSE 1 + floor(r_emp * 8)::int END,
       d,
       TIME '08:00' + floor(r_time * 50400) * INTERVAL '1 second',
       CASE WHEN online THEN 'online' ELSE 'in_store' END,
       CASE WHEN online THEN (CASE WHEN r_pay < 0.85 THEN 'card' ELSE 'transfer' END)
            ELSE (CASE WHEN r_pay < 0.48 THEN 'cash' WHEN r_pay < 0.92 THEN 'card' ELSE 'transfer' END)
       END,
       st,
       CASE WHEN online AND st = 'completed' THEN d + 1 + floor(r_del * 5)::int END,
       CASE WHEN r_rate < 0.40 THEN 1 + floor(r_star * 5)::int END,
       round((15 + 2500 * r_amt ^ 3)::numeric, 2)
FROM (SELECT i,
             1 + floor(random() * 48000)::int AS c,
             DATE '2023-01-01' + floor(1096 * ((i - 0.5) / 5000000.0) ^ 0.85)::int AS d,
             random() < 0.33 AS online,
             CASE WHEN random() < 0.92 THEN 'completed'
                  WHEN random() < 0.6  THEN 'returned'
                  ELSE 'cancelled' END AS st,
             random() AS r_emp, random() AS r_time, random() AS r_pay, random() AS r_del,
             random() AS r_rate, random() AS r_star, random() AS r_amt
      FROM generate_series(1, 5000000) AS i) AS s;

VACUUM ANALYZE;

-- Expect 30 / 8 / 37 / 600 / 965 and 5,000,000
SELECT 'customers' AS t, count(*) FROM customers
UNION ALL SELECT 'employees',   count(*) FROM employees
UNION ALL SELECT 'products',    count(*) FROM products
UNION ALL SELECT 'orders',      count(*) FROM orders
UNION ALL SELECT 'order_items', count(*) FROM order_items
UNION ALL SELECT 'orders_big',  count(*) FROM orders_big;

-- The ground truth: 529 completed orders, 157,078.41
SELECT count(*) AS completed_orders, sum(orderTotal) AS completed_revenue
FROM orders
WHERE status = 'completed';

-- The big table's ground truth (Lecture 7): orders per year
-- 1,371,464 / 1,733,359 / 1,895,177, and the total of every order
SELECT extract(year FROM orderDate) AS year, count(*) AS orders
FROM orders_big
GROUP BY 1
ORDER BY 1;

SELECT count(*) AS orders, sum(orderTotal) AS total
FROM orders_big;

-- Its size on disk, for Part 2's comparison. pg_size_pretty prints
-- 467 MB and 107 MB: it counts 1 MB = 1,048,576 bytes. Lecture 8
-- counts 1 MB = 1,000,000 bytes, as DuckDB and file sizes do:
-- table 489 MB, primary-key index 112 MB.
SELECT pg_size_pretty(pg_relation_size('orders_big'))  AS table_size,
       round(pg_relation_size('orders_big') / 1e6)    AS table_mb,
       pg_size_pretty(pg_indexes_size('orders_big'))   AS index_size,
       round(pg_indexes_size('orders_big') / 1e6)     AS index_mb;

\set ON_ERROR_STOP off
