-- ============================================================
-- Lecture 7 — Part 0: load the data
--
-- Two kinds of tables:
--
-- 1. The same small shop as Lectures 4-6 (byte-identical CSVs in
--    data/, the same statements as Lecture 6's setup), for every
--    question about CORRECTNESS:
--      customers, employees, products, orders, order_items
--      dim_date, dim_customer, dim_product, dim_employee, fact_sales
--    600 orders (529 completed), 965 lines, 30 customers (28 with
--    orders), 8 employees, 37 products, completed revenue 157,078.41.
--
-- 2. Two GENERATED big tables, for every question about SPEED:
--      customers_big   50,000 customers, the same columns as customers
--      orders_big      5,000,000 orders, the same columns as orders
--    600 rows can't teach performance: on a table that small,
--    PostgreSQL rightly reads everything and no index ever helps
--    (Part 1.1 shows it).
--
-- DROPS and recreates the lecture07 database, then connects to it --
-- so start psql in ANOTHER database (psql postgres), not in lecture07.
-- \copy resolves paths relative to where you STARTED psql, so run
-- this from the lecture_7/ folder:    psql postgres
--                                     \i steps/00-setup.sql
-- Takes about 45 seconds on the reference machine (the 5-million-row
-- INSERT is most of it). Needs about 1 GB of disk; the whole lecture,
-- with the partitioned copies of Part 9, peaks at about 2.5 GB.
--
-- Needs PostgreSQL 11 or later (INCLUDE, DEFAULT partitions, primary
-- keys on partitioned tables). The generated data is IDENTICAL on
-- PostgreSQL 15 and later; PostgreSQL 14 has a different random()
-- generator, so the same seed gives different (equally shaped) rows.
-- ============================================================

-- Stop at the first error instead of carrying on with half the data
-- (e.g. a \copy that can't find data/*.csv because psql was started
-- in another folder: the shop tables would stay EMPTY). Switched back
-- off at the end of this script.
\set ON_ERROR_STOP on

-- ---- The database: start from an empty one every time ----
DROP DATABASE IF EXISTS lecture07;
CREATE DATABASE lecture07;

-- ---- Two planner settings, pinned for this database ----
-- So that everyone sees the same plans as the notes:
--  * no parallel query: otherwise big scans get split across worker
--    processes, the plan grows Gather nodes, and timings depend on how
--    many CPU cores your machine has. (The default is 2 workers.)
--  * no JIT compilation: otherwise queries over about 100,000 cost
--    units add a compile step whose time varies from run to run.
-- Both apply to every new connection to lecture07, including the
-- notebook's. Everything else stays at PostgreSQL's defaults
-- (shared_buffers 128MB, work_mem 4MB, random_page_cost 4).
ALTER DATABASE lecture07 SET max_parallel_workers_per_gather = 0;
ALTER DATABASE lecture07 SET jit = off;

\c lecture07

-- ================= 1. The small shop (as Lecture 6) =================
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


-- ================= 2. The big tables =================
-- Built with generate_series and random(). setseed() fixes the
-- sequence random() returns, so every machine (PostgreSQL 15+) gets
-- exactly the same rows.
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
-- No foreign keys: the load stays fast, and Part 5's write-cost
-- measurement is about indexes only. The only index is the primary key.
-- autovacuum is switched OFF for this one table, so that its
-- statistics (Part 3) and visibility map (Part 4) change only when
-- the lecture says so. Never do that to a real table.
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
) WITH (autovacuum_enabled = off);

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

-- ---- customers_big: 50,000 customers, the same columns as customers ----
-- Names from the small shop, an email that is unique per customer,
-- and moneySpent = completed revenue, as in the small customers table.
CREATE TABLE customers_big (
    customerID   INT PRIMARY KEY,
    firstName    VARCHAR(50)  NOT NULL,
    lastName     VARCHAR(50)  NOT NULL,
    email        VARCHAR(100) NOT NULL UNIQUE,
    phone        VARCHAR(20),
    city         VARCHAR(50)  NOT NULL,
    birthDate    DATE,
    signupDate   DATE         NOT NULL,
    anniversary  DATE,
    moneySpent   DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (moneySpent >= 0)
);

INSERT INTO customers_big
SELECT s.id, s.f, s.l,
       lower(s.f) || '.' || lower(s.l) || s.id || '@'
           || (ARRAY['gmail.com', 'mail.ru', 'yandex.ru', 'yahoo.com'])[1 + floor(s.r_mail * 4)::int],
       '+374 ' || (ARRAY['91', '93', '94', '95', '98', '99', '77'])[1 + floor(s.r_op * 7)::int]
           || ' ' || lpad(floor(s.r_num * 1000000)::int::text, 6, '0'),
       CASE WHEN s.r_city < 0.60 THEN 'Yerevan' WHEN s.r_city < 0.80 THEN 'Gyumri'
            WHEN s.r_city < 0.90 THEN 'Vanadzor' ELSE 'Abovyan' END,
       DATE '1960-01-01' + floor(s.r_birth * 16000)::int,
       DATE '2019-01-01' + floor(s.r_signup * 1460)::int,
       NULL,
       coalesce(m.spent, 0)
FROM (SELECT id,
             (ARRAY['Anna', 'Davit', 'Mariam', 'Tigran', 'Lusine', 'Narek', 'Sona', 'Aram', 'Hayk', 'Lilit',
                    'Armen', 'Gayane', 'Vahan', 'Arpine', 'Karen', 'Nane', 'Ruben', 'Tatev', 'Artur', 'Meline',
                    'Suren', 'Ani', 'Levon', 'Hasmik', 'Samvel', 'Diana', 'Gevorg', 'Astghik', 'Mher'])[1 + floor(random() * 29)::int] AS f,
             (ARRAY['Sargsyan', 'Petrosyan', 'Hakobyan', 'Grigoryan', 'Avetisyan', 'Manukyan', 'Karapetyan',
                    'Vardanyan', 'Melikyan', 'Hovhannisyan', 'Gevorgyan', 'Mnatsakanyan', 'Torosyan', 'Simonyan',
                    'Khachatryan', 'Galstyan', 'Asatryan', 'Martirosyan', 'Baghdasaryan', 'Poghosyan',
                    'Hayrapetyan', 'Stepanyan', 'Arakelyan', 'Zakaryan', 'Nazaryan', 'Aleksanyan', 'Kocharyan',
                    'Danielyan'])[1 + floor(random() * 28)::int] AS l,
             random() AS r_mail, random() AS r_op, random() AS r_num, random() AS r_city,
             random() AS r_birth, random() AS r_signup
      FROM generate_series(1, 50000) AS id) AS s
LEFT JOIN (SELECT customerID, sum(orderTotal) AS spent
           FROM orders_big
           WHERE status = 'completed'
           GROUP BY customerID) AS m ON m.customerID = s.id;

-- Statistics for the planner, and the visibility map for index-only
-- scans (Part 4), for every table -- now, not whenever autovacuum
-- gets round to it. Parts 3 and 4 show what happens without them.
VACUUM ANALYZE;

-- Expect 30 / 8 / 37 / 600 / 965, a 366 / 965 star,
-- and 50,000 / 5,000,000 big rows
SELECT 'customers' AS t, count(*) FROM customers
UNION ALL SELECT 'employees',     count(*) FROM employees
UNION ALL SELECT 'products',      count(*) FROM products
UNION ALL SELECT 'orders',        count(*) FROM orders
UNION ALL SELECT 'order_items',   count(*) FROM order_items
UNION ALL SELECT 'dim_date',      count(*) FROM dim_date
UNION ALL SELECT 'fact_sales',    count(*) FROM fact_sales
UNION ALL SELECT 'customers_big', count(*) FROM customers_big
UNION ALL SELECT 'orders_big',    count(*) FROM orders_big;

-- The ground truth from Lectures 4-6: 529 completed orders, 157,078.41
SELECT count(*) AS completed_orders, sum(orderTotal) AS completed_revenue
FROM orders
WHERE status = 'completed';

-- The two pinned settings (0 and off), the PostgreSQL defaults the
-- notes assume for the rest, and your version
SELECT name, setting, unit
FROM pg_settings
WHERE name IN ('server_version', 'max_parallel_workers_per_gather', 'jit',
               'shared_buffers', 'work_mem', 'random_page_cost', 'effective_cache_size')
ORDER BY name;

-- Back to psql's default: the demo's later Parts contain errors on purpose.
\set ON_ERROR_STOP off
