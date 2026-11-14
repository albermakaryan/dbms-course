-- ============================================================
-- Lecture 7 — Performance: EXPLAIN, Indexing, Partitioning
-- YSU, Data Science for Business
--
-- Reading plans (EXPLAIN, ANALYZE, BUFFERS), how a table is stored on
-- disk (files, pages, row addresses), statistics and estimates, scan
-- types and selectivity, B-tree indexes and what they cost,
-- composite / partial / covering / expression indexes, the traps that
-- make an index go unused, plans for Lecture 5's and 6's alternatives,
-- partitioning, and when to do none of it. Correctness questions use
-- the small shop data of Lectures 4-6; speed questions use two
-- generated tables, orders_big (5,000,000 rows) and customers_big
-- (50,000).
--
-- Needs PostgreSQL 11 or later (13 or later for Part 2.6), and a
-- superuser for Part 2 (pageinspect, pg_ls_dir). Reference output below: PostgreSQL 18
-- (18.6) on a laptop (Intel i7-13700H, NVMe disk), with the settings
-- pinned in Part 0 (no parallel query, no JIT). Checked on 14, 16 and
-- 18: see lecture-07-notes.md for what differs.
--
-- TIMINGS ARE FROM ONE RUN ON ONE MACHINE. Yours will differ. Compare
-- plan shape (node names, Index Cond vs Filter), estimated vs actual
-- rows, and Buffers -- those carry over between machines. Medians of
-- three runs are in the notes.
--
-- Run this whole script at once (from the lecture_7/ folder, so the
-- \copy paths in Part 0 resolve; about 4 minutes), or each part
-- separately: steps/00-setup.sql, then steps/01-... to steps/10-...
-- in order (numbered to match the Parts in lecture-07-notes.md).
-- Each Part removes the indexes and tables it creates, so orders_big
-- goes into every Part with its primary key only. Errors on purpose
-- are marked in the comments.
-- ============================================================



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



-- ============================================================
-- Lecture 7 — Part 1: Reading a plan
-- Run after Part 0 (steps/00-setup.sql).
--
-- Every SQL statement is turned into a PLAN before it runs: which
-- tables to read, how (all of it, or through an index), in what
-- order, and how to join them. EXPLAIN shows that plan. Everything
-- in this lecture is read from plans.
-- ============================================================

-- ---- 1.1 Why 600 rows can't teach this ----
-- "All orders of customer 5" on the small orders table -- first with
-- no index, then with one:
DROP INDEX IF EXISTS orders_customerid_idx;
EXPLAIN ANALYZE
SELECT * FROM orders WHERE customerID = 5;
--                                             QUERY PLAN
-- Seq Scan on orders  (cost=0.00..15.50 rows=5 width=60) (actual time=0.009..0.027 rows=5.00 loops=1)
--   Filter: (customerid = 5)
--   Rows Removed by Filter: 595
--   Buffers: shared hit=8
-- Planning:
--   Buffers: shared hit=84 read=1 written=1
-- Planning Time: 0.157 ms
-- Execution Time: 0.061 ms
CREATE INDEX orders_customerid_idx ON orders (customerID);
EXPLAIN ANALYZE
SELECT * FROM orders WHERE customerID = 5;
--                                                           QUERY PLAN
-- Bitmap Heap Scan on orders  (cost=4.19..11.77 rows=5 width=60) (actual time=0.010..0.011 rows=5.00 loops=1)
--   Recheck Cond: (customerid = 5)
--   Heap Blocks: exact=4
--   Buffers: shared hit=4 read=1 written=1
--   ->  Bitmap Index Scan on orders_customerid_idx  (cost=0.00..4.19 rows=5 width=0) (actual time=0.007..0.008 rows=5.00 loops=1)
--         Index Cond: (customerid = 5)
--         Index Searches: 1
--         Buffers: shared read=1 written=1
-- Planning:
--   Buffers: shared hit=20 read=1 written=1
-- Planning Time: 0.067 ms
-- Execution Time: 0.019 ms
-- The second plan uses the index (Bitmap Heap Scan, which 1.4 and
-- Part 4 explain) -- and it doesn't matter: both plans finish in a
-- few hundredths of a millisecond. The whole table is 8 pages of
-- 8 kB:
SELECT pg_relation_size('orders') / 8192 AS pages,
       pg_size_pretty(pg_relation_size('orders')) AS size;
-- pages | size
--     8 | 64 kB
-- On 600 rows every plan is instant, so there is nothing to measure
-- and nothing to learn about speed.
DROP INDEX orders_customerid_idx;

-- So the rest of the lecture uses the generated tables: the same
-- columns, 5 million orders and 50,000 customers.
SELECT 'orders_big' AS t, count(*) AS rows,
       pg_size_pretty(pg_table_size('orders_big')) AS size,
       pg_relation_size('orders_big') / 8192 AS pages
FROM orders_big
UNION ALL
SELECT 'customers_big', count(*),
       pg_size_pretty(pg_table_size('customers_big')),
       pg_relation_size('customers_big') / 8192
FROM customers_big;
--       t       |  rows   |  size   | pages
-- orders_big    | 5000000 | 467 MB  | 59739
-- customers_big |   50000 | 6592 kB |   820

-- ---- 1.2 EXPLAIN: the plan, without running the query ----
-- "All orders of customer 4242" (Nane Simonyan, Yerevan).
EXPLAIN
SELECT * FROM orders_big WHERE customerID = 4242;
--                            QUERY PLAN
-- Seq Scan on orders_big  (cost=0.00..122240.04 rows=106 width=60)
--   Filter: (customerid = 4242)
-- One step (a NODE): Seq Scan on orders_big -- read every row, keep
-- the ones that pass the Filter. The numbers in brackets are the
-- planner's ESTIMATES; nothing has run yet:
--   cost=0.00..122240   cost to the first row .. cost to the last
--                       row, in the planner's own units (reading
--                       one page in sequence = 1.0), not in ms
--   rows=106            how many rows it expects this node to return
--   width=60            average size of one row, in bytes
-- (Your last digits may differ: the estimates come from a random
-- sample -- Part 3.)
-- Costs are for comparing different plans for the SAME query. They
-- are not times.

-- ---- 1.3 EXPLAIN ANALYZE: run it and measure ----
EXPLAIN ANALYZE
SELECT * FROM orders_big WHERE customerID = 4242;
--                                                    QUERY PLAN
-- Seq Scan on orders_big  (cost=0.00..122240.04 rows=106 width=60) (actual time=1.832..129.864 rows=97.00 loops=1)
--   Filter: (customerid = 4242)
--   Rows Removed by Filter: 4999903
--   Buffers: shared hit=14089 read=45650 written=7
-- Planning Time: 0.010 ms
-- Execution Time: 129.874 ms
-- Now every node also says what really happened:
--   actual time=first..last   ms until its first row .. until its last row
--   rows=97.00                rows it really returned (estimate: about 106)
--   loops=1                   how many times the node ran
-- "Rows Removed by Filter: 4999903": it read five million rows to
-- return 97. Execution Time is the whole query, in ms -- on THIS
-- machine, this time.
-- PostgreSQL 18 prints Buffers here automatically (1.4); before 18
-- you have to ask for them.

-- ---- 1.4 BUFFERS: how many pages it touched ----
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_big WHERE customerID = 4242;
--                                                    QUERY PLAN
-- Seq Scan on orders_big  (cost=0.00..122240.04 rows=106 width=60) (actual time=1.576..130.367 rows=97.00 loops=1)
--   Filter: (customerid = 4242)
--   Rows Removed by Filter: 4999903
--   Buffers: shared hit=14183 read=45556
-- Planning Time: 0.037 ms
-- Execution Time: 130.383 ms
-- Data lives in 8 kB pages. "shared hit" = pages found in PostgreSQL's
-- own memory cache (shared_buffers); "read" = pages it had to ask the
-- operating system for (from the OS file cache, or the disk). hit +
-- read = 59,739 here: every page of the table, to find 97 rows. Page
-- counts don't depend on how fast your laptop is, so they're the
-- number to compare between two plans.

-- ---- 1.5 Read a plan inside out ----
-- "Nane's orders per status, most first":
EXPLAIN ANALYZE
SELECT status, count(*) AS orders, sum(orderTotal) AS total
FROM orders_big
WHERE customerID = 4242
GROUP BY status
ORDER BY orders DESC;
--                                                             QUERY PLAN
-- Sort  (cost=122244.72..122244.73 rows=3 width=49) (actual time=132.200..132.201 rows=3.00 loops=1)
--   Sort Key: (count(*)) DESC
--   Sort Method: quicksort  Memory: 25kB
--   Buffers: shared hit=14283 read=45462
--   ->  GroupAggregate  (cost=122243.60..122244.70 rows=3 width=49) (actual time=132.173..132.185 rows=3.00 loops=1)
--         Group Key: status
--         Buffers: shared hit=14280 read=45462
--         ->  Sort  (cost=122243.60..122243.87 rows=106 width=15) (actual time=132.159..132.162 rows=97.00 loops=1)
--               Sort Key: status
--               Sort Method: quicksort  Memory: 28kB
--               Buffers: shared hit=14280 read=45462
--               ->  Seq Scan on orders_big  (cost=0.00..122240.04 rows=106 width=15) (actual time=1.661..132.125 rows=97.00 loops=1)
--                     Filter: (customerid = 4242)
--                     Rows Removed by Filter: 4999903
--                     Buffers: shared hit=14277 read=45462
-- Planning:
--   Buffers: shared hit=44 read=4
-- Planning Time: 0.119 ms
-- Execution Time: 132.223 ms
-- Read from the most indented node outwards. The Seq Scan runs first
-- and hands its 97 rows up to a Sort (by status), which hands them,
-- sorted, to the GroupAggregate (GROUP BY: 3 groups, one after the
-- other), which hands 3 rows up to the last Sort (ORDER BY orders
-- DESC). Each "->" is a node feeding the one above it. A node's actual
-- time INCLUDES the time of the nodes under it: nearly all of this
-- query's time is the scan at the bottom.

-- ---- 1.6 The hazard: EXPLAIN ANALYZE really runs the statement ----
-- On a scratch copy of the small orders table:
CREATE TEMP TABLE orders_copy AS SELECT * FROM orders;
SELECT count(*) AS rows_before FROM orders_copy;
-- rows_before
--         600
-- "Just checking the plan of a DELETE":
EXPLAIN ANALYZE
DELETE FROM orders_copy WHERE status = 'cancelled';
--                                                   QUERY PLAN
-- Delete on orders_copy  (cost=0.00..15.25 rows=0 width=0) (actual time=0.038..0.039 rows=0.00 loops=1)
--   Buffers: local hit=35
--   ->  Seq Scan on orders_copy  (cost=0.00..15.25 rows=2 width=6) (actual time=0.004..0.033 rows=27.00 loops=1)
--         Filter: ((status)::text = 'cancelled'::text)
--         Rows Removed by Filter: 573
--         Buffers: local hit=8
-- Planning Time: 0.015 ms
-- Execution Time: 0.046 ms
SELECT count(*) AS rows_after FROM orders_copy;
-- rows_after
--        573
-- WRONG: 27 rows are gone. ANALYZE means "run it": the DELETE really
-- happened. On a real table, that's a real delete. No warning.

-- FIX: run it inside a transaction and roll it back.
BEGIN;
EXPLAIN ANALYZE
DELETE FROM orders_copy WHERE status = 'returned';
--                                                   QUERY PLAN
-- Delete on orders_copy  (cost=0.00..15.25 rows=0 width=0) (actual time=0.036..0.036 rows=0.00 loops=1)
--   Buffers: local hit=52
--   ->  Seq Scan on orders_copy  (cost=0.00..15.25 rows=2 width=6) (actual time=0.004..0.029 rows=44.00 loops=1)
--         Filter: ((status)::text = 'returned'::text)
--         Rows Removed by Filter: 529
--         Buffers: local hit=8
-- Planning Time: 0.012 ms
-- Execution Time: 0.041 ms
ROLLBACK;
SELECT count(*) AS rows_after_rollback FROM orders_copy;
-- rows_after_rollback
--                 573
-- The plan and the timings are real; the 44 deleted rows came back.
-- The same goes for INSERT and UPDATE: always BEGIN ... ROLLBACK
-- around EXPLAIN ANALYZE of anything that writes. (Plain EXPLAIN,
-- without ANALYZE, never runs anything.)
DROP TABLE orders_copy;

-- ---- 1.7 Cold and warm: run it three times ----
-- A range of 10,000 orders through the primary key. Predict, then
-- run: will the three runs be the same?
EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(orderTotal) FROM orders_big WHERE orderID BETWEEN 2500001 AND 2510000;
--                                                                  QUERY PLAN
-- Aggregate  (cost=492.19..492.19 rows=1 width=32) (actual time=1.696..1.697 rows=1.00 loops=1)
--   Buffers: shared read=150
--   ->  Index Scan using orders_big_pkey on orders_big  (cost=0.43..465.43 rows=10700 width=6) (actual time=0.018..0.983 rows=10000.00 loops=1)
--         Index Cond: ((orderid >= 2500001) AND (orderid <= 2510000))
--         Index Searches: 1
--         Buffers: shared read=150
-- Planning:
--   Buffers: shared hit=10
-- Planning Time: 0.034 ms
-- Execution Time: 1.705 ms
EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(orderTotal) FROM orders_big WHERE orderID BETWEEN 2500001 AND 2510000;
--                                                                  QUERY PLAN
-- Aggregate  (cost=492.19..492.19 rows=1 width=32) (actual time=1.293..1.294 rows=1.00 loops=1)
--   Buffers: shared hit=150
--   ->  Index Scan using orders_big_pkey on orders_big  (cost=0.43..465.43 rows=10700 width=6) (actual time=0.006..0.602 rows=10000.00 loops=1)
--         Index Cond: ((orderid >= 2500001) AND (orderid <= 2510000))
--         Index Searches: 1
--         Buffers: shared hit=150
-- Planning Time: 0.038 ms
-- Execution Time: 1.303 ms
EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(orderTotal) FROM orders_big WHERE orderID BETWEEN 2500001 AND 2510000;
--                                                                  QUERY PLAN
-- Aggregate  (cost=492.19..492.19 rows=1 width=32) (actual time=1.296..1.296 rows=1.00 loops=1)
--   Buffers: shared hit=150
--   ->  Index Scan using orders_big_pkey on orders_big  (cost=0.43..465.43 rows=10700 width=6) (actual time=0.004..0.593 rows=10000.00 loops=1)
--         Index Cond: ((orderid >= 2500001) AND (orderid <= 2510000))
--         Index Searches: 1
--         Buffers: shared hit=150
-- Planning Time: 0.013 ms
-- Execution Time: 1.301 ms
-- Same plan, same 10,000 rows, same number of pages. On a fresh
-- database the FIRST run has "read=" (the pages weren't in
-- PostgreSQL's cache yet) and is slower; runs 2 and 3 have only
-- "hit=". If you ran this before, all three are warm. That's why one
-- timing proves nothing: run three times, and compare plan shape and
-- page counts before milliseconds.

-- The big Seq Scan, three times:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big WHERE customerID = 4242;
--                                                      QUERY PLAN
-- Aggregate  (cost=122240.30..122240.31 rows=1 width=8) (actual time=128.797..128.798 rows=1.00 loops=1)
--   Buffers: shared hit=14488 read=45251 written=14
--   ->  Seq Scan on orders_big  (cost=0.00..122240.04 rows=106 width=0) (actual time=1.852..128.785 rows=97.00 loops=1)
--         Filter: (customerid = 4242)
--         Rows Removed by Filter: 4999903
--         Buffers: shared hit=14488 read=45251 written=14
-- Planning Time: 0.022 ms
-- Execution Time: 128.809 ms
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big WHERE customerID = 4242;
--                                                      QUERY PLAN
-- Aggregate  (cost=122240.30..122240.31 rows=1 width=8) (actual time=132.561..132.562 rows=1.00 loops=1)
--   Buffers: shared hit=14576 read=45163 written=22
--   ->  Seq Scan on orders_big  (cost=0.00..122240.04 rows=106 width=0) (actual time=1.947..132.548 rows=97.00 loops=1)
--         Filter: (customerid = 4242)
--         Rows Removed by Filter: 4999903
--         Buffers: shared hit=14576 read=45163 written=22
-- Planning Time: 0.038 ms
-- Execution Time: 132.577 ms
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big WHERE customerID = 4242;
--                                                      QUERY PLAN
-- Aggregate  (cost=122240.30..122240.31 rows=1 width=8) (actual time=130.321..130.322 rows=1.00 loops=1)
--   Buffers: shared hit=14670 read=45069 written=78
--   ->  Seq Scan on orders_big  (cost=0.00..122240.04 rows=106 width=0) (actual time=2.231..130.306 rows=97.00 loops=1)
--         Filter: (customerid = 4242)
--         Rows Removed by Filter: 4999903
--         Buffers: shared hit=14670 read=45069 written=78
-- Planning Time: 0.040 ms
-- Execution Time: 130.337 ms
-- Surprise: it never gets warm. Every run has tens of thousands of
-- "read" pages. A table bigger than a quarter of shared_buffers
-- (128 MB by default) is scanned through a small ring of buffers, so
-- that one big scan can't push everything else out of the cache. The
-- pages come from the operating system's file cache instead, which
-- is why it's still fast. Your hit/read split will differ from the
-- notes; the total (59,739 pages) won't.



-- ============================================================
-- Lecture 7 — Part 2: How a table is stored on disk
-- Run after Part 1.
--
-- Part 1 counted pages. This Part opens them. A table is a file; the
-- file is a row of 8 kB pages; every row sits in one page, at an
-- address (page, slot). Everything later in this lecture -- why a
-- Seq Scan reads every page, what an index stores, why 3% of the rows
-- can be 93% of the pages, why VACUUM matters -- follows from that.
-- (pageinspect and pg_ls_dir need a superuser: the postgres user of
-- our Docker setup is one.)
-- ============================================================

-- Start clean (in case you ran this Part before).
DROP TABLE IF EXISTS storage_demo, orders_2023;

-- ---- 2.1 A table is a file ----
-- Where does orders_big live? The server's data directory, then the
-- path of the table's file inside it:
SELECT current_setting('data_directory') AS data_directory,
       pg_relation_filepath('orders_big') AS file;
--        data_directory         |       file
-- /var/lib/postgresql/18/docker | base/16675/16852
-- base/<number of the database>/<number of the table's file>. Your
-- numbers will differ; they are just names. The file isn't alone --
-- list everything in that folder whose name starts with it:
SELECT f AS file,
       pg_size_pretty((pg_stat_file(dir || '/' || f)).size) AS size,
       (pg_stat_file(dir || '/' || f)).size AS bytes
FROM (SELECT regexp_replace(pg_relation_filepath('orders_big'), '/[^/]+$', '') AS dir,
             regexp_replace(pg_relation_filepath('orders_big'), '^.*/', '') AS node) p,
     pg_ls_dir(p.dir) AS f
WHERE f = node OR starts_with(f, node || '_') OR starts_with(f, node || '.')
ORDER BY f;
--   file    |  size  |   bytes
-- 16852     | 467 MB | 489381888
-- 16852_fsm | 136 kB |    139264
-- 16852_vm  | 16 kB  |     16384
-- Three files: the table itself (467 MB, every row), its free space
-- map (_fsm: which pages have room for a new row) and its visibility
-- map (_vm: which pages VACUUM has marked "all-visible" -- Part 4.5
-- uses it). A table over 1 GB continues in a second file, <name>.1,
-- then .2, and so on.
-- You can look at the same file from outside PostgreSQL. In a
-- terminal (pg = the container from start_postgres.sh; paste YOUR
-- path from the first query):
--     docker exec pg ls -l /var/lib/postgresql/18/docker/base/16384/16561*
-- An ordinary file of 489,381,888 bytes. 2.5 reads bytes from it.

-- ---- 2.2 A file is a row of 8 kB pages ----
SELECT current_setting('block_size') AS page_bytes,
       pg_relation_size('orders_big') AS file_bytes,
       pg_relation_size('orders_big') / current_setting('block_size')::int AS pages,
       round(count(*) / (pg_relation_size('orders_big') / 8192.0), 1) AS rows_per_page
FROM orders_big;
-- page_bytes | file_bytes | pages | rows_per_page
-- 8192       |  489381888 | 59739 |          83.7
-- 489,381,888 bytes = 59,739 pages x 8,192 bytes, exactly. PostgreSQL
-- never reads or writes less than a page: to get one row, it reads
-- the whole 8 kB page the row is on. That's why the plans in this
-- lecture count pages ("Buffers"), not rows. About 84 orders fit on a
-- page.

-- ---- 2.3 Every row has an address: ctid ----
-- Every table has a hidden column, ctid = (page number, slot in the
-- page). Pages are numbered from 0:
SELECT ctid, orderID, orderDate, customerID, status, orderTotal
FROM orders_big
WHERE orderID IN (1, 2, 3, 83, 84, 85, 86, 4890168)
ORDER BY orderID;
--    ctid    | orderid | orderdate  | customerid |  status   | ordertotal
-- (0,1)      |       1 | 2023-01-01 |      37147 | returned  |     476.82
-- (0,2)      |       2 | 2023-01-01 |      48472 | completed |     186.88
-- (0,3)      |       3 | 2023-01-01 |      15856 | completed |      36.88
-- (0,83)     |      83 | 2023-01-01 |      29372 | completed |     490.46
-- (0,84)     |      84 | 2023-01-01 |      43564 | completed |     657.51
-- (1,1)      |      85 | 2023-01-01 |      31986 | returned  |     333.24
-- (1,2)      |      86 | 2023-01-01 |      34116 | completed |     287.49
-- (58425,79) | 4890168 | 2025-12-11 |       4242 | completed |    1768.13
-- The rows were inserted in orderID order, so they fill page 0 (84
-- rows), then page 1, and so on. Nane's order 4890168 is in slot 79
-- of page 58,425.

-- With an address, PostgreSQL can go straight to a row.
-- Predict, then run: how many pages does this read?
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_big WHERE ctid = '(58425,79)';
--                                               QUERY PLAN
-- Tid Scan on orders_big  (cost=0.00..4.01 rows=1 width=60) (actual time=0.001..0.002 rows=1.00 loops=1)
--   TID Cond: (ctid = '(58425,79)'::tid)
--   Buffers: shared hit=1
-- Planning:
--   Buffers: shared hit=25
-- Planning Time: 0.034 ms
-- Execution Time: 0.005 ms
-- Tid Scan, 1 page ("shared hit=1"). Every index lookup ends exactly
-- like this: the index gives an address, the table page is read (2.6).
-- Don't keep ctids in your own tables, though: a row gets a new one
-- when it is updated (2.8).

-- Pages, not rows, are what a query pays for. Nane's 97 orders and one
-- day's 5,180 orders -- on how many different pages?
SELECT 'Nane (customer 4242)' AS rows_of, count(*) AS rows,
       count(DISTINCT (ctid::text::point)[0]) AS pages
FROM orders_big WHERE customerID = 4242
UNION ALL
SELECT 'one day (2025-06-15)', count(*),
       count(DISTINCT (ctid::text::point)[0])
FROM orders_big WHERE orderDate = '2025-06-15';
--       rows_of        | rows | pages
-- Nane (customer 4242) |   97 |    97
-- one day (2025-06-15) | 5180 |    63
-- Nane's 97 orders are on 97 different pages: she ordered on 97
-- different days, and orders are stored in the order they arrived.
-- One day's 5,180 orders are on 63 pages, side by side. 50 times the
-- rows on fewer pages. Parts 3 and 4 come back to this ("correlation",
-- and why 3% of the rows can be 93% of the pages).
-- ((ctid::text::point)[0] is a trick to pull the page number out of
-- the ctid.)

-- ---- 2.4 Inside one page ----
-- The pageinspect extension (part of PostgreSQL) shows a page as it is
-- on disk.
CREATE EXTENSION IF NOT EXISTS pageinspect;
-- The page header of orders_big's page 0:
SELECT lower, upper, special, pagesize, upper - lower AS free_bytes
FROM page_header(get_raw_page('orders_big', 0));
-- lower | upper | special | pagesize | free_bytes
--   360 |   408 |    8192 |     8192 |         48
-- And its slots: where each row starts in the page (lp_off), how many
-- bytes it has (lp_len), and its address:
SELECT lp AS slot, lp_off AS starts_at_byte, lp_len AS bytes, t_ctid
FROM heap_page_items(get_raw_page('orders_big', 0))
ORDER BY lp;
-- slot | starts_at_byte | bytes | t_ctid
--    1 |           8104 |    86 | (0,1)
--    2 |           8008 |    91 | (0,2)
--    3 |           7912 |    91 | (0,3)
--    4 |           7816 |    95 | (0,4)
-- ...   (78 more lines)
--   83 |            504 |    87 | (0,83)
--   84 |            408 |    91 | (0,84)
-- A page is filled from both ends:
--     | header 24 B | slot 1 | slot 2 | ... | slot 84 | free | row 84 | ... | row 2 | row 1 |
--     0                                  lower=360   upper=408                       8192
-- Slots (4 bytes each) grow from the front: 24 + 84 x 4 = 360 = lower.
-- Rows grow from the back: row 1 starts at byte 8104, row 84 at 408 =
-- upper. 48 bytes are left in the middle, too few for another order,
-- so order 85 went to page 1.
-- Pages are numbered 0 to 59,738. Error on purpose:
SELECT * FROM page_header(get_raw_page('orders_big', 59739));
-- ERROR:  block number 59739 is out of range for relation "orders_big"

-- ---- 2.5 The bytes of one row ----
-- Order 1 is slot 1 of page 0. Its columns, as stored:
SELECT a.attname AS column_name, encode(u.v, 'hex') AS bytes_on_disk
FROM heap_page_item_attrs(get_raw_page('orders_big', 0), 'orders_big') h,
     unnest(h.t_attrs) WITH ORDINALITY AS u(v, n)
JOIN pg_attribute a ON a.attrelid = 'orders_big'::regclass AND a.attnum = u.n
WHERE h.lp = 1
ORDER BY u.n;
--  column_name  |   bytes_on_disk
-- orderid       | 01000000
-- customerid    | 1b910000
-- employeeid    | 01000000
-- orderdate     | d1200000
-- ordertime     | 805a083709000000
-- channel       | 13696e5f73746f7265
-- paymentmethod | 0b63617264
-- status        | 1372657475726e6564
-- deliverydate  |
-- rating        |
-- ordertotal    | 0f0081dc010820
SELECT * FROM orders_big WHERE orderID = 1;
-- orderid | customerid | employeeid | orderdate  | ordertime | channel  | paymentmethod |  status  | deliverydate | rating | ordertotal
--       1 |      37147 |          1 | 2023-01-01 | 10:59:38  | in_store | card          | returned |              |        |     476.82
-- Read them side by side. orderid 01000000 is 1, written lowest byte
-- first. customerid 1b910000 is 0x911b = 37147. orderdate d1200000 is
-- 0x20d1 = 8401: a date is stored as days since 2000-01-01:
SELECT DATE '2000-01-01' + 8401 AS day_8401;
--  day_8401
-- 2023-01-01
-- status is the text 'returned' (72 65 74 75 72 6e 65 64), after one
-- length byte. deliverydate and rating are empty: a NULL takes no
-- bytes at all, only one bit in the row's header. Every row starts
-- with that header (23 bytes: which transaction wrote the row, which
-- one deleted it, and so on; plus the NULL bits when a column is NULL
-- -- 32 bytes for order 1), then its columns, one after another.
-- The same bytes are in the file. In a terminal (your path from 2.1):
--     docker exec pg od -A d -t x1 -j 8136 -N 16 /var/lib/postgresql/18/docker/base/16384/16561
--     0008136 01 00 00 00 1b 91 00 00 01 00 00 00 d1 20 00 00
-- Byte 8,136 of the file (row 1 starts at 8,104, plus its 32-byte
-- header): order 1, customer 37147, employee 1, and 2023-01-01. (Run CHECKPOINT first if the file looks older than the
-- table: PostgreSQL writes changed pages to the file a little later.)

-- ---- 2.6 An index entry is a key and an address ----
-- The primary key's index is a file of pages too. Its page 1 holds the
-- smallest orderIDs:
SELECT itemoffset AS entry, data AS key_bytes, htid AS row_address
FROM bt_page_items('orders_big_pkey', 1)
WHERE itemoffset BETWEEN 2 AND 5;
-- entry |        key_bytes        | row_address
--     2 | 01 00 00 00 00 00 00 00 | (0,1)
--     3 | 02 00 00 00 00 00 00 00 | (0,2)
--     4 | 03 00 00 00 00 00 00 00 | (0,3)
--     5 | 04 00 00 00 00 00 00 00 | (0,4)
-- Key 1 (01 00 00 00, padded to 8 bytes) -> row (0,1); key 2 -> (0,2).
-- An index is sorted keys, each with the address of its row. A lookup
-- finds the key in the index, then reads the table page at the
-- address: 2.3's Tid Scan, behind every Index Scan in Part 4.
-- (Entry 1 of an index page is a boundary marker for searching, not a
-- row; that's why we start at 2.)

-- ---- 2.7 Rows, not columns: why one column costs the whole table ----
-- A row's columns are stored together, one row after another. So what
-- does it take to add up ONE column?
SELECT pg_size_pretty(sum(pg_column_size(orderTotal))) AS ordertotal_bytes,
       pg_size_pretty(pg_relation_size('orders_big')) AS table_bytes
FROM orders_big;
-- ordertotal_bytes | table_bytes
-- 33 MB            | 467 MB
EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(orderTotal) FROM orders_big;
--                                                           QUERY PLAN
-- Aggregate  (cost=122240.04..122240.05 rows=1 width=32) (actual time=550.006..550.007 rows=1.00 loops=1)
--   Buffers: shared hit=15142 read=44597
--   ->  Seq Scan on orders_big  (cost=0.00..109739.83 rows=5000083 width=6) (actual time=0.006..149.522 rows=5000000.00 loops=1)
--         Buffers: shared hit=15142 read=44597
-- Planning:
--   Buffers: shared hit=9
-- Planning Time: 0.076 ms
-- Execution Time: 550.036 ms
-- The orderTotal values take 33 MB. To add them up, PostgreSQL read
-- all 59,739 pages, 467 MB: every column of every row, because the
-- totals are spread across every page. That is the right layout for
-- "show me order 4890168" (one page, all its columns) and the wrong one
-- for "sum one column over 5 million rows". Columnar formats (Parquet,
-- DuckDB -- the next lectures) store each column separately, so the
-- sum reads only the totals.

-- ---- 2.8 UPDATE writes a new row; the old one stays ----
-- A three-row table, so the whole thing fits on one page:
CREATE TABLE storage_demo (id int, name text, city text, total numeric(10,2));
INSERT INTO storage_demo VALUES
    (1, 'Nane Simonyan', 'Yerevan', 120.50),
    (2, 'Aram Petrosyan', 'Gyumri', 75.00),
    (3, 'Ani Hakobyan', 'Vanadzor', 9.99);
SELECT lp AS slot, lp_off AS starts_at_byte, lp_len AS bytes,
       encode(t_data, 'escape') AS row_bytes
FROM heap_page_items(get_raw_page('storage_demo', 0));
-- slot | starts_at_byte | bytes |                                 row_bytes
--    1 |           8128 |    57 | \x01\000\000\000\x1DNane Simonyan\x11Yerevan\x0F\000\201x\000\210\x13
--    2 |           8072 |    55 | \x02\000\000\000\x1FAram Petrosyan\x0FGyumri\x0B\000\201K\000
--    3 |           8008 |    57 | \x03\000\000\000\x1BAni Hakobyan\x13Vanadzor\x0F\000\201        \000\254&
-- The names and cities are readable inside the raw bytes; the numbers
-- around them are the id, the length bytes and the total. A row really
-- is just its columns, side by side.
-- xmin and xmax are two more hidden columns: the transaction that wrote
-- this version of the row, and the one that replaced or deleted it (0 =
-- nobody yet). Your transaction numbers will differ.
SELECT ctid, xmin, xmax, * FROM storage_demo;
-- ctid  | xmin | xmax | id |      name      |   city   | total
-- (0,1) |  975 |    0 |  1 | Nane Simonyan  | Yerevan  | 120.50
-- (0,2) |  975 |    0 |  2 | Aram Petrosyan | Gyumri   |  75.00
-- (0,3) |  975 |    0 |  3 | Ani Hakobyan   | Vanadzor |   9.99
UPDATE storage_demo SET total = 130.00 WHERE id = 1;
SELECT ctid, xmin, xmax, * FROM storage_demo;
-- ctid  | xmin | xmax | id |      name      |   city   | total
-- (0,2) |  975 |    0 |  2 | Aram Petrosyan | Gyumri   |  75.00
-- (0,3) |  975 |    0 |  3 | Ani Hakobyan   | Vanadzor |   9.99
-- (0,4) |  976 |    0 |  1 | Nane Simonyan  | Yerevan  | 130.00
-- Nane's row moved: (0,1) became (0,4). And without ORDER BY, she now
-- comes last -- the rows come back in the order they sit on the page.
-- What's in slot 1 now?
SELECT lp AS slot, t_xmin, t_xmax, t_ctid AS newer_version_at,
       encode(t_data, 'escape') AS row_bytes
FROM heap_page_items(get_raw_page('storage_demo', 0));
-- slot | t_xmin | t_xmax | newer_version_at |                                 row_bytes
--    1 |    975 |    976 | (0,4)            | \x01\000\000\000\x1DNane Simonyan\x11Yerevan\x0F\000\201x\000\210\x13
--    2 |    975 |      0 | (0,2)            | \x02\000\000\000\x1FAram Petrosyan\x0FGyumri\x0B\000\201K\000
--    3 |    975 |      0 | (0,3)            | \x03\000\000\000\x1BAni Hakobyan\x13Vanadzor\x0F\000\201        \000\254&
--    4 |    976 |      0 | (0,4)            | \x01\000\000\000\x1DNane Simonyan\x11Yerevan\x0B\000\201\202\000
-- Slot 1 still holds the OLD row (compare its last bytes, the total,
-- with slot 4's), marked "replaced by transaction t_xmax, newer
-- version at (0,4)". UPDATE never
-- overwrites a row: it writes a new version and marks the old one.
-- That's how other transactions can keep reading the old version while
-- yours is still running. DELETE only marks the row:
DELETE FROM storage_demo WHERE id = 3;
SELECT lp AS slot, t_xmin, t_xmax, t_ctid
FROM heap_page_items(get_raw_page('storage_demo', 0));
-- slot | t_xmin | t_xmax | t_ctid
--    1 |    975 |    976 | (0,4)
--    2 |    975 |      0 | (0,2)
--    3 |    975 |    977 | (0,3)
--    4 |    976 |      0 | (0,4)
-- Slot 3 is still there, with an xmax. The space of dead row versions
-- is freed only by VACUUM:
VACUUM storage_demo;
SELECT lp AS slot,
       CASE lp_flags WHEN 0 THEN 'free' WHEN 1 THEN 'row'
                     WHEN 2 THEN 'points to slot ' || lp_off WHEN 3 THEN 'dead' END AS slot_is,
       lp_off AS starts_at_byte, t_ctid
FROM heap_page_items(get_raw_page('storage_demo', 0));
-- slot |     slot_is      | starts_at_byte | t_ctid
--    1 | points to slot 4 |              4 |
--    2 | row              |           8136 | (0,2)
--    3 | free             |              0 |
--    4 | row              |           8080 | (0,4)
-- Slot 3 is free again; slot 1 now only forwards to slot 4 (an index
-- might still hold Nane's old address); the two live rows moved to the
-- end of the page, together.
DROP TABLE storage_demo;

-- ---- 2.9 The trap: deleting rows doesn't shrink the file ----
-- A copy of 2023 (1,371,464 orders) to experiment on:
CREATE TABLE orders_2023 AS
SELECT * FROM orders_big WHERE orderDate < '2024-01-01';
SELECT count(*) AS rows, pg_size_pretty(pg_relation_size('orders_2023')) AS size,
       pg_relation_size('orders_2023') / 8192 AS pages
FROM orders_2023;
--  rows   |  size  | pages
-- 1371464 | 128 MB | 16390
-- "Archive" January to November: delete 90% of the rows.
DELETE FROM orders_2023 WHERE orderDate < '2023-12-01';
SELECT count(*) AS rows, pg_size_pretty(pg_relation_size('orders_2023')) AS size,
       pg_relation_size('orders_2023') / 8192 AS pages
FROM orders_2023;
--  rows  |  size  | pages
-- 135984 | 128 MB | 16390
-- WRONG: "we deleted 90% of the rows, so the table is 10 times
-- smaller." 135,984 rows, and the file is still 128 MB: every deleted
-- row is still there, marked (2.8). A full scan still reads every page:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_2023;
--                                                         QUERY PLAN
-- Aggregate  (cost=24994.75..24994.76 rows=1 width=8) (actual time=10.754..10.754 rows=1.00 loops=1)
--   Buffers: shared hit=16261 read=129 written=1
--   ->  Seq Scan on orders_2023  (cost=0.00..23273.80 rows=688380 width=0) (actual time=2.993..7.507 rows=135984.00 loops=1)
--         Buffers: shared hit=16261 read=129 written=1
-- Planning Time: 0.044 ms
-- Execution Time: 10.773 ms
-- VACUUM removes the dead rows:
VACUUM orders_2023;
SELECT count(*) AS rows, pg_size_pretty(pg_relation_size('orders_2023')) AS size,
       pg_relation_size('orders_2023') / 8192 AS pages
FROM orders_2023;
--  rows  |  size  | pages
-- 135984 | 128 MB | 16390
-- Still 128 MB. VACUUM makes the space reusable INSIDE the table; it
-- doesn't give it back to the disk (only empty pages at the very end
-- of the file are cut off, and here the kept December rows are at the
-- end). The space isn't lost: new rows fill it. Three months of 2024
-- go in, and the file doesn't grow by a single page:
INSERT INTO orders_2023
SELECT * FROM orders_big WHERE orderDate >= '2024-01-01' AND orderDate < '2024-04-01';
SELECT count(*) AS rows, pg_size_pretty(pg_relation_size('orders_2023')) AS size,
       pg_relation_size('orders_2023') / 8192 AS pages
FROM orders_2023;
--  rows  |  size  | pages
-- 546555 | 128 MB | 16390
-- FIX, if you need the disk space back: VACUUM FULL writes the live
-- rows into a NEW file and deletes the old one.
SELECT pg_relation_filepath('orders_2023') AS file_before;
--   file_before
-- base/16675/16951
VACUUM FULL orders_2023;
SELECT count(*) AS rows, pg_size_pretty(pg_relation_size('orders_2023')) AS size,
       pg_relation_size('orders_2023') / 8192 AS pages,
       pg_relation_filepath('orders_2023') AS file_after
FROM orders_2023;
--  rows  | size  | pages |    file_after
-- 546555 | 51 MB |  6530 | base/16675/16954
-- 51 MB, and a different file name. The price: VACUUM FULL locks the
-- table completely (no reads, no writes) while it copies, and needs
-- room for both copies on disk. If you delete old data by date every
-- month, the better answer is partitions you can DROP (Part 9.8).
DROP TABLE orders_2023;

-- Clean up.
DROP EXTENSION pageinspect;



-- ============================================================
-- Lecture 7 — Part 3: Statistics and estimates
-- Run after Part 1.
--
-- The planner never looks at the data while planning. It picks a plan
-- from STATISTICS: a small summary of each table that ANALYZE builds
-- from a random sample of rows. Wrong statistics, wrong plan -- and
-- no error.
-- ============================================================

-- ---- 3.1 What the planner knows ----
-- Table size (pg_class), as of the last VACUUM or ANALYZE:
SELECT relname, reltuples::bigint AS rows_it_thinks, relpages AS pages_it_thinks
FROM pg_class
WHERE relname IN ('orders_big', 'customers_big');
--    relname    | rows_it_thinks | pages_it_thinks
-- customers_big |          50000 |             820
-- orders_big    |        5000083 |           59739

-- Per column (pg_stats): how many distinct values, the most common
-- values and their share, and how well the column's order matches the
-- order of the rows on disk (correlation: 1 = same order, 0 = none).
SELECT attname, n_distinct, most_common_vals, most_common_freqs, round(correlation::numeric, 3) AS correlation
FROM pg_stats
WHERE tablename = 'orders_big' AND attname IN ('status', 'channel');
-- attname | n_distinct |        most_common_vals        |       most_common_freqs        | correlation
-- channel |          2 | {in_store,online}              | {0.6694667,0.33053333}         |       0.558
-- status  |          3 | {completed,returned,cancelled} | {0.9181333,0.048666667,0.0332} |       0.845
SELECT attname, n_distinct, round(correlation::numeric, 3) AS correlation
FROM pg_stats
WHERE tablename = 'orders_big' AND attname IN ('customerid', 'orderdate', 'orderid');
--  attname   | n_distinct | correlation
-- orderid    |         -1 |       1.000
-- customerid |      47231 |       0.003
-- orderdate  |       1096 |       1.000
-- status: three values, about 92 / 5 / 3 percent. customerID: about
-- 48,000 distinct values, so "one customer" means about 104 rows, and
-- it has nothing to do with where a row sits on disk (correlation
-- about 0). orderDate and orderID: correlation 1 -- the rows were
-- written in date order. Part 4 shows why that matters.
-- The numbers come from a random sample (30,000 rows here), so yours
-- differ a little in the last digits. A negative n_distinct means "a
-- fraction of the rows": -1 = every row is different.

-- ---- 3.2 Estimated vs actual ----
EXPLAIN ANALYZE
SELECT count(*) FROM orders_big WHERE status = 'cancelled';
--                                                          QUERY PLAN
-- Aggregate  (cost=122655.05..122655.06 rows=1 width=8) (actual time=247.775..247.775 rows=1.00 loops=1)
--   Buffers: shared hit=94 read=59645
--   ->  Seq Scan on orders_big  (cost=0.00..122240.04 rows=166003 width=0) (actual time=0.147..243.392 rows=159902.00 loops=1)
--         Filter: ((status)::text = 'cancelled'::text)
--         Rows Removed by Filter: 4840098
--         Buffers: shared hit=94 read=59645
-- Planning:
--   Buffers: shared hit=27 read=3
-- Planning Time: 0.054 ms
-- Execution Time: 247.787 ms
-- Estimated vs actual rows on the Seq Scan: close, because status is
-- in the most-common-values list. When estimates are this close, the
-- plan is chosen on true numbers.

-- ---- 3.3 THE TRAP: a bulk load without ANALYZE ----
-- January 2026 arrives: 200,000 new orders, loaded in one go.
-- (autovacuum is off for orders_big -- see Part 0 -- so nothing will
-- quietly ANALYZE it for us. In real life, autovacuum would get to it
-- eventually; your query might run before it does.)
SELECT setseed(0.7);
INSERT INTO orders_big
SELECT 5000000 + i,
       c + (c - 1) / 24,
       CASE WHEN online THEN NULL ELSE 1 + floor(random() * 8)::int END,
       DATE '2026-01-01' + floor(random() * 31)::int,
       TIME '08:00' + floor(random() * 50400) * INTERVAL '1 second',
       CASE WHEN online THEN 'online' ELSE 'in_store' END,
       'card',
       'completed',
       NULL,
       NULL,
       round((15 + 2500 * random() ^ 3)::numeric, 2)
FROM (SELECT i, 1 + floor(random() * 48000)::int AS c, random() < 0.33 AS online
      FROM generate_series(1, 200000) AS i) AS s;

-- The first report on the new month: January's orders by city.
-- Predict, then run: how many rows will the planner EXPECT for
-- orderDate >= '2026-01-01'?
EXPLAIN ANALYZE
SELECT c.city, count(*) AS orders, sum(o.orderTotal) AS revenue
FROM orders_big o
JOIN customers_big c ON c.customerID = o.customerID
WHERE o.orderDate >= '2026-01-01'
GROUP BY c.city;
--                                                                          QUERY PLAN
-- GroupAggregate  (cost=129088.63..129093.44 rows=4 width=47) (actual time=360.838..383.474 rows=4.00 loops=1)
--   Group Key: c.city
--   Buffers: shared hit=601508 read=60506, temp read=610 written=612
--   ->  Sort  (cost=129088.63..129089.82 rows=476 width=13) (actual time=358.341..368.476 rows=200000.00 loops=1)
--         Sort Key: c.city
--         Sort Method: external merge  Disk: 4880kB
--         Buffers: shared hit=601508 read=60506, temp read=610 written=612
--         ->  Nested Loop  (cost=0.29..129067.46 rows=476 width=13) (actual time=157.314..331.154 rows=200000.00 loops=1)
--               Buffers: shared hit=601505 read=60506
--               ->  Seq Scan on orders_big o  (cost=0.00..126889.09 rows=476 width=10) (actual time=157.284..170.928 rows=200000.00 loops=1)
--                     Filter: (orderdate >= '2026-01-01'::date)
--                     Rows Removed by Filter: 5000000
--                     Buffers: shared hit=2460 read=59551
--               ->  Index Scan using customers_big_pkey on customers_big c  (cost=0.29..4.58 rows=1 width=11) (actual time=0.001..0.001 rows=1.00 loops=200000)
--                     Index Cond: (customerid = o.customerid)
--                     Index Searches: 200000
--                     Buffers: shared hit=599045 read=955
-- Planning:
--   Buffers: shared hit=162 read=9
-- Planning Time: 0.324 ms
-- Execution Time: 384.158 ms
-- WRONG PLAN, right answer. Read the Seq Scan line: the planner
-- expected a few hundred January rows; there are 200,000. Its
-- statistics end on 2025-12-31 -- it has never seen 2026. Everything
-- above that node was chosen for a few hundred rows:
-- * Nested Loop: for EACH January order, look up its customer through
--   the primary key -- 200,000 separate lookups (loops=200000)
-- * Sort to group by city, with "external merge Disk": the sort was
--   sized for a few hundred rows and spilled to a temporary file
-- No error, and the result is correct. It's just the wrong plan.

-- ---- 3.4 FIX: ANALYZE, then the same query ----
ANALYZE orders_big;
EXPLAIN ANALYZE
SELECT c.city, count(*) AS orders, sum(o.orderTotal) AS revenue
FROM orders_big o
JOIN customers_big c ON c.customerID = o.customerID
WHERE o.orderDate >= '2026-01-01'
GROUP BY c.city;
--                                                                QUERY PLAN
-- HashAggregate  (cost=131102.01..131102.06 rows=4 width=47) (actual time=218.817..218.821 rows=4.00 loops=1)
--   Group Key: c.city
--   Batches: 1  Memory Usage: 32kB
--   Buffers: shared hit=3630 read=59201
--   ->  Hash Join  (cost=1945.00..129516.35 rows=211421 width=13) (actual time=165.761..197.953 rows=200000.00 loops=1)
--         Hash Cond: (o.customerid = c.customerid)
--         Buffers: shared hit=3630 read=59201
--         ->  Seq Scan on orders_big o  (cost=0.00..127016.33 rows=211421 width=10) (actual time=158.974..169.782 rows=200000.00 loops=1)
--               Filter: (orderdate >= '2026-01-01'::date)
--               Rows Removed by Filter: 5000000
--               Buffers: shared hit=2810 read=59201
--         ->  Hash  (cost=1320.00..1320.00 rows=50000 width=11) (actual time=6.748..6.749 rows=50000.00 loops=1)
--               Buckets: 65536  Batches: 1  Memory Usage: 2681kB
--               Buffers: shared hit=820
--               ->  Seq Scan on customers_big c  (cost=0.00..1320.00 rows=50000 width=11) (actual time=0.007..2.505 rows=50000.00 loops=1)
--                     Buffers: shared hit=820
-- Planning:
--   Buffers: shared hit=38
-- Planning Time: 0.128 ms
-- Execution Time: 218.849 ms
-- Now the estimate is about 200,000 and the plan changes shape:
-- * Hash Join: read the 50,000 customers ONCE into a hash table in
--   memory, then match each January order against it
-- * HashAggregate: group in memory, 4 groups, no disk
-- Same four rows. Compare the Buffers lines: the nested loop touched
-- about ten times as many pages. (Median timings: notes, Part 3.)

-- ---- 3.5 The rule of thumb ----
-- In any slow plan, look first for the node where estimated rows and
-- actual rows differ by a factor of 10 or more -- usually the lowest
-- such node. Every decision above it was made for the wrong number.
-- After a bulk load or a big UPDATE / DELETE: run ANALYZE.

-- Put orders_big back to its 5,000,000 rows for the rest of the lecture.
DELETE FROM orders_big WHERE orderID > 5000000;
VACUUM ANALYZE orders_big;
SELECT count(*) AS rows, max(orderDate) AS last_date FROM orders_big;
--  rows   | last_date
-- 5000000 | 2025-12-31



-- ============================================================
-- Lecture 7 — Part 4: Scan types, and what the planner chooses
-- Run after Part 3.
--
-- Four ways to read a table: Seq Scan (all of it, in order), Index
-- Scan (index, then each row), Bitmap Heap Scan (index, collect the
-- pages, then read those pages in order), Index Only Scan (the index
-- alone). The planner picks by SELECTIVITY: what share of the table
-- the query needs -- counted in pages, not just rows.
-- ============================================================

-- Start clean (in case you ran this Part before).
DROP INDEX IF EXISTS orders_big_orderdate_idx, orders_big_status_idx;
DROP TABLE IF EXISTS orders_2025;

-- Two indexes for this Part. (Part 5 looks at what indexes cost.)
CREATE INDEX orders_big_orderdate_idx ON orders_big (orderDate);
CREATE INDEX orders_big_status_idx ON orders_big (status);

-- ---- 4.1 One day: Index Scan ----
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big WHERE orderDate = '2025-06-15';
--                                                                      QUERY PLAN
-- Aggregate  (cost=171.59..171.60 rows=1 width=40) (actual time=0.861..0.862 rows=1.00 loops=1)
--   Buffers: shared read=70
--   ->  Index Scan using orders_big_orderdate_idx on orders_big  (cost=0.43..149.56 rows=4407 width=6) (actual time=0.018..0.481 rows=5180.00 loops=1)
--         Index Cond: (orderdate = '2025-06-15'::date)
--         Index Searches: 1
--         Buffers: shared read=70
-- Planning:
--   Buffers: shared hit=70 read=2
-- Planning Time: 0.176 ms
-- Execution Time: 0.892 ms
-- 5,180 rows of 5,000,000 (0.1%). Index Scan: find 2025-06-15 in the
-- index, then fetch each row. Look at the page count: about 70 pages
-- for 5,180 rows. orderDate has correlation 1 (Part 3.1): one day's
-- orders sit next to each other on disk, so 5,180 rows share a few
-- dozen pages.

-- ---- 4.2 Cancelled orders: Bitmap Heap Scan ----
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big WHERE status = 'cancelled';
--                                                                     QUERY PLAN
-- Aggregate  (cost=64423.60..64423.61 rows=1 width=40) (actual time=82.858..82.860 rows=1.00 loops=1)
--   Buffers: shared read=55953 written=611
--   ->  Bitmap Heap Scan on orders_big  (cost=1829.04..63607.73 rows=163175 width=6) (actual time=13.171..69.774 rows=159902.00 loops=1)
--         Recheck Cond: ((status)::text = 'cancelled'::text)
--         Heap Blocks: exact=55814
--         Buffers: shared read=55953 written=611
--         ->  Bitmap Index Scan on orders_big_status_idx  (cost=0.00..1788.24 rows=163175 width=0) (actual time=7.397..7.398 rows=159902.00 loops=1)
--               Index Cond: ((status)::text = 'cancelled'::text)
--               Index Searches: 1
--               Buffers: shared read=139
-- Planning:
--   Buffers: shared hit=16
-- Planning Time: 0.040 ms
-- Execution Time: 82.872 ms
-- 159,902 rows (3.2%). Bitmap Index Scan collects every matching row's
-- page into a bitmap; Bitmap Heap Scan then reads those pages once
-- each, in disk order. But read "Heap Blocks: exact=55814": cancelled
-- orders are scattered, so 3% of the ROWS live on 93% of the PAGES
-- (55,814 of 59,739). The index saves almost nothing here.

-- ---- 4.3 Completed orders: Seq Scan, with an index right there ----
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big WHERE status = 'completed';
--                                                           QUERY PLAN
-- Aggregate  (cost=145186.88..145186.89 rows=1 width=40) (actual time=615.978..615.978 rows=1.00 loops=1)
--   Buffers: shared hit=15385 read=44354
--   ->  Seq Scan on orders_big  (cost=0.00..122242.33 rows=4588911 width=6) (actual time=0.064..332.083 rows=4600224.00 loops=1)
--         Filter: ((status)::text = 'completed'::text)
--         Rows Removed by Filter: 399776
--         Buffers: shared hit=15385 read=44354
-- Planning Time: 0.050 ms
-- Execution Time: 616.001 ms
-- 4,600,224 rows (92%). The index on status exists; the planner
-- doesn't use it. Is that a mistake? Take the Seq Scan away and see:
SET enable_seqscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big WHERE status = 'completed';
--                                                                       QUERY PLAN
-- Aggregate  (cost=191409.44..191409.45 rows=1 width=40) (actual time=643.916..643.917 rows=1.00 loops=1)
--   Buffers: shared read=63674 written=1
--   ->  Bitmap Heap Scan on orders_big  (cost=51364.49..168464.88 rows=4588911 width=6) (actual time=62.422..285.050 rows=4600224.00 loops=1)
--         Recheck Cond: ((status)::text = 'completed'::text)
--         Heap Blocks: exact=59739
--         Buffers: shared read=63674 written=1
--         ->  Bitmap Index Scan on orders_big_status_idx  (cost=0.00..50217.26 rows=4588911 width=0) (actual time=55.846..55.846 rows=4600224.00 loops=1)
--               Index Cond: ((status)::text = 'completed'::text)
--               Index Searches: 1
--               Buffers: shared read=3935 written=1
-- Planning Time: 0.058 ms
-- Execution Time: 643.937 ms
SET enable_bitmapscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big WHERE status = 'completed';
--                                                                          QUERY PLAN
-- Aggregate  (cost=227281.28..227281.29 rows=1 width=40) (actual time=756.330..756.331 rows=1.00 loops=1)
--   Buffers: shared read=63674
--   ->  Index Scan using orders_big_status_idx on orders_big  (cost=0.43..204336.72 rows=4588911 width=6) (actual time=0.034..398.836 rows=4600224.00 loops=1)
--         Index Cond: ((status)::text = 'completed'::text)
--         Index Searches: 1
--         Buffers: shared read=63674
-- Planning Time: 0.051 ms
-- Execution Time: 756.348 ms
RESET enable_seqscan;
RESET enable_bitmapscan;
-- Forced through the index, the same query reads MORE pages (the
-- whole table plus thousands of index pages) and is no faster
-- (Bitmap) or slower (Index Scan). "The index isn't used" was the
-- right decision. When a query needs most of the table, reading the
-- whole table in order is the cheapest way. Don't teach yourself
-- "always add an index"; teach yourself "read the plan".
-- (enable_seqscan = off doesn't forbid anything; it makes the planner
-- treat a Seq Scan as hugely expensive. Use it to test, never in
-- production.)

-- ---- 4.4 Index Only Scan: the answer is in the index ----
-- count(*) for one day needs no column except orderDate -- and
-- orderDate is IN the index:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big WHERE orderDate = '2025-06-15';
--                                                                        QUERY PLAN
-- Aggregate  (cost=104.57..104.58 rows=1 width=8) (actual time=0.355..0.355 rows=1.00 loops=1)
--   Buffers: shared read=8
--   ->  Index Only Scan using orders_big_orderdate_idx on orders_big  (cost=0.43..93.56 rows=4407 width=0) (actual time=0.049..0.224 rows=5180.00 loops=1)
--         Index Cond: (orderdate = '2025-06-15'::date)
--         Heap Fetches: 0
--         Index Searches: 1
--         Buffers: shared read=8
-- Planning Time: 0.047 ms
-- Execution Time: 0.367 ms
-- Index Only Scan: the table wasn't read at all. Compare the pages with
-- 4.1 (sum(orderTotal) needed the table): a handful instead of about 70.
-- "Heap Fetches: 0" -- the line to watch, next.

-- ---- 4.5 The visibility map: why Heap Fetches is not always 0 ----
-- An index doesn't know whether the row it points to is visible to
-- your transaction (it might be deleted, or not yet committed). A page
-- marked "all-visible" in the table's visibility map can be trusted
-- without reading it; any other page must be read (a Heap Fetch).
-- VACUUM sets those marks. orders_big was vacuumed in Part 0. A fresh
-- table, just built, hasn't been:
CREATE TABLE orders_2025 WITH (autovacuum_enabled = off) AS
SELECT * FROM orders_big WHERE orderDate >= '2025-01-01';
CREATE INDEX orders_2025_orderdate_idx ON orders_2025 (orderDate);
ANALYZE orders_2025;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_2025 WHERE orderDate = '2025-06-15';
--                                                                         QUERY PLAN
-- Aggregate  (cost=188.79..188.80 rows=1 width=8) (actual time=0.579..0.579 rows=1.00 loops=1)
--   Buffers: shared hit=63 read=7
--   ->  Index Only Scan using orders_2025_orderdate_idx on orders_2025  (cost=0.43..175.87 rows=5168 width=0) (actual time=0.020..0.452 rows=5180.00 loops=1)
--         Index Cond: (orderdate = '2025-06-15'::date)
--         Heap Fetches: 5180
--         Index Searches: 1
--         Buffers: shared hit=63 read=7
-- Planning:
--   Buffers: shared hit=7 read=1
-- Planning Time: 0.087 ms
-- Execution Time: 0.592 ms
-- Still called Index Only Scan, but "Heap Fetches: 5180" -- it went to
-- the table for every row, and the page count shows it.
VACUUM orders_2025;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_2025 WHERE orderDate = '2025-06-15';
--                                                                         QUERY PLAN
-- Aggregate  (cost=127.79..127.80 rows=1 width=8) (actual time=0.304..0.305 rows=1.00 loops=1)
--   Buffers: shared hit=8
--   ->  Index Only Scan using orders_2025_orderdate_idx on orders_2025  (cost=0.43..114.87 rows=5168 width=0) (actual time=0.008..0.174 rows=5180.00 loops=1)
--         Index Cond: (orderdate = '2025-06-15'::date)
--         Heap Fetches: 0
--         Index Searches: 1
--         Buffers: shared hit=8
-- Planning:
--   Buffers: shared hit=4
-- Planning Time: 0.062 ms
-- Execution Time: 0.317 ms
-- After VACUUM: Heap Fetches 0, a handful of pages. Same plan name,
-- very different work. Read the numbers under the node, not just its
-- name.
DROP TABLE orders_2025;

-- Clean up: leave orders_big with its primary key only.
DROP INDEX orders_big_orderdate_idx, orders_big_status_idx;



-- ============================================================
-- Lecture 7 — Part 5: B-tree indexes, and what they cost
-- Run after Part 4.
--
-- CREATE INDEX builds a B-tree: the column's values in sorted order,
-- each with the address of its row. Finding one value takes a few
-- page reads, however big the table. The price: disk space, and extra
-- work on every INSERT, UPDATE and DELETE.
-- ============================================================

-- Start clean (in case you ran this Part before).
DROP INDEX IF EXISTS orders_big_customerid_idx, orders_big_ordertotal_idx;
DROP TABLE IF EXISTS orders_load;

-- ---- 5.1 Before: customer 4242 without an index (Part 1) ----
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_big WHERE customerID = 4242;
--                                                    QUERY PLAN
-- Seq Scan on orders_big  (cost=0.00..122242.33 rows=106 width=60) (actual time=1.943..132.068 rows=97.00 loops=1)
--   Filter: (customerid = 4242)
--   Rows Removed by Filter: 4999903
--   Buffers: shared read=59739
-- Planning:
--   Buffers: shared hit=78 read=10 dirtied=1
-- Planning Time: 0.243 ms
-- Execution Time: 132.108 ms

-- ---- 5.2 After: CREATE INDEX ----
CREATE INDEX orders_big_customerid_idx ON orders_big (customerID);
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_big WHERE customerID = 4242;
--                                                               QUERY PLAN
-- Bitmap Heap Scan on orders_big  (cost=5.25..417.18 rows=106 width=60) (actual time=0.072..0.328 rows=97.00 loops=1)
--   Recheck Cond: (customerid = 4242)
--   Heap Blocks: exact=97
--   Buffers: shared read=100
--   ->  Bitmap Index Scan on orders_big_customerid_idx  (cost=0.00..5.23 rows=106 width=0) (actual time=0.019..0.019 rows=97.00 loops=1)
--         Index Cond: (customerid = 4242)
--         Index Searches: 1
--         Buffers: shared read=3
-- Planning:
--   Buffers: shared hit=18 read=2
-- Planning Time: 0.116 ms
-- Execution Time: 0.346 ms
-- Bitmap Index Scan: 3 index pages (root, branch, leaf) find the 97
-- row addresses; Bitmap Heap Scan reads the 97 pages they're on
-- ("Heap Blocks: exact=97" -- Nane's orders are spread out, one per
-- page). About 100 pages instead of 59,739, and hundreds of times
-- faster (notes, Part 5, for the median of three runs). Same 97 rows.

-- ---- 5.3 What it costs: space ----
SELECT c.relname AS name,
       CASE c.relkind WHEN 'r' THEN 'table' ELSE 'index' END AS kind,
       pg_size_pretty(pg_relation_size(c.oid)) AS size
FROM pg_class c
WHERE c.relname IN ('orders_big', 'orders_big_pkey', 'orders_big_customerid_idx')
ORDER BY pg_relation_size(c.oid) DESC;
--           name            | kind  |  size
-- orders_big                | table | 467 MB
-- orders_big_pkey           | index | 111 MB
-- orders_big_customerid_idx | index | 34 MB
-- The primary key (5 million different orderIDs) is a quarter of the
-- table's size. The customerID index is a third of the primary key:
-- since PostgreSQL 13 a B-tree stores a repeated value once with a
-- list of its rows (deduplication), and each customer repeats about
-- 104 times.

-- ---- 5.4 What it costs: every write ----
-- Load the same 1,000,000 orders into an empty table three times:
-- with no index, with one, with five. (A copy, orders_load, so that
-- orders_big stays as it is. Times: notes Part 5, median of three.)
CREATE TABLE orders_load (LIKE orders_big) WITH (autovacuum_enabled = off);

EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO orders_load SELECT * FROM orders_big WHERE orderID <= 1000000;
--                                                                      QUERY PLAN
-- Insert on orders_load  (cost=0.43..39996.24 rows=0 width=0) (actual time=662.274..662.275 rows=0.00 loops=1)
--   Buffers: shared hit=1023940 read=14669 dirtied=11951 written=11955
--   ->  Index Scan using orders_big_pkey on orders_big  (cost=0.43..39996.24 rows=978846 width=60) (actual time=0.018..144.692 rows=1000000.00 loops=1)
--         Index Cond: (orderid <= 1000000)
--         Index Searches: 1
--         Buffers: shared hit=26 read=14669 written=2
-- Planning:
--   Buffers: shared hit=15
-- Planning Time: 0.040 ms
-- Execution Time: 662.288 ms
TRUNCATE orders_load;

CREATE INDEX ON orders_load (customerID);
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO orders_load SELECT * FROM orders_big WHERE orderID <= 1000000;
--                                                                      QUERY PLAN
-- Insert on orders_load  (cost=0.43..39996.24 rows=0 width=0) (actual time=1698.532..1698.532 rows=0.00 loops=1)
--   Buffers: shared hit=3818714 read=14684 dirtied=13144 written=13146
--   ->  Index Scan using orders_big_pkey on orders_big  (cost=0.43..39996.24 rows=978846 width=60) (actual time=0.022..124.935 rows=1000000.00 loops=1)
--         Index Cond: (orderid <= 1000000)
--         Index Searches: 1
--         Buffers: shared hit=12 read=14683 written=1
-- Planning Time: 0.047 ms
-- Execution Time: 1698.546 ms
TRUNCATE orders_load;

CREATE INDEX ON orders_load (orderDate);
CREATE INDEX ON orders_load (status);
CREATE INDEX ON orders_load (employeeID);
CREATE INDEX ON orders_load (orderTotal);
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO orders_load SELECT * FROM orders_big WHERE orderID <= 1000000;
--                                                                      QUERY PLAN
-- Insert on orders_load  (cost=0.43..39996.24 rows=0 width=0) (actual time=5206.853..5206.853 rows=0.00 loops=1)
--   Buffers: shared hit=13463096 read=14688 dirtied=19420 written=25093
--   ->  Index Scan using orders_big_pkey on orders_big  (cost=0.43..39996.24 rows=978846 width=60) (actual time=0.020..146.214 rows=1000000.00 loops=1)
--         Index Cond: (orderid <= 1000000)
--         Index Searches: 1
--         Buffers: shared hit=12 read=14683 written=2381
-- Planning Time: 0.045 ms
-- Execution Time: 5206.872 ms
-- The same million rows each time. Compare the Buffers line of the
-- ModifyTable node ("Insert on orders_load"): every index is another
-- structure to update for every row, in another place on disk.
SELECT c.relname AS name, pg_size_pretty(pg_relation_size(c.oid)) AS size
FROM pg_class c
JOIN pg_index i ON i.indexrelid = c.oid
WHERE i.indrelid = 'orders_load'::regclass
UNION ALL
SELECT 'orders_load (the table)', pg_size_pretty(pg_relation_size('orders_load'))
ORDER BY name;
--            name            |  size
-- orders_load (the table)    | 93 MB
-- orders_load_customerid_idx | 9544 kB
-- orders_load_employeeid_idx | 6336 kB
-- orders_load_orderdate_idx  | 7480 kB
-- orders_load_ordertotal_idx | 29 MB
-- orders_load_status_idx     | 6368 kB
-- Five indexes are about as big as the table they index.
DROP TABLE orders_load;

-- ---- 5.5 ORDER BY ... LIMIT: an index is already sorted ----
-- "The ten biggest orders ever":
EXPLAIN (ANALYZE, BUFFERS)
SELECT orderID, orderDate, orderTotal FROM orders_big ORDER BY orderTotal DESC, orderID LIMIT 10;
--                                                              QUERY PLAN
-- Limit  (cost=217795.61..217795.64 rows=10 width=14) (actual time=664.185..664.187 rows=10.00 loops=1)
--   Buffers: shared hit=2595 read=57144
--   ->  Sort  (cost=217795.61..230296.28 rows=5000266 width=14) (actual time=664.184..664.185 rows=10.00 loops=1)
--         Sort Key: ordertotal DESC, orderid
--         Sort Method: top-N heapsort  Memory: 25kB
--         Buffers: shared hit=2595 read=57144
--         ->  Seq Scan on orders_big  (cost=0.00..109741.66 rows=5000266 width=14) (actual time=0.212..315.601 rows=5000000.00 loops=1)
--               Buffers: shared hit=2595 read=57144
-- Planning:
--   Buffers: shared hit=8 read=4
-- Planning Time: 0.063 ms
-- Execution Time: 664.197 ms
-- Without an index on orderTotal: read all 5 million rows, keep the
-- top 10 in memory ("top-N heapsort").
CREATE INDEX orders_big_ordertotal_idx ON orders_big (orderTotal DESC, orderID);
EXPLAIN (ANALYZE, BUFFERS)
SELECT orderID, orderDate, orderTotal FROM orders_big ORDER BY orderTotal DESC, orderID LIMIT 10;
--                                                                         QUERY PLAN
-- Limit  (cost=0.43..1.21 rows=10 width=14) (actual time=0.017..0.044 rows=10.00 loops=1)
--   Buffers: shared hit=1 read=12
--   ->  Index Scan using orders_big_ordertotal_idx on orders_big  (cost=0.43..390972.41 rows=5000266 width=14) (actual time=0.016..0.043 rows=10.00 loops=1)
--         Index Searches: 1
--         Buffers: shared hit=1 read=12
-- Planning:
--   Buffers: shared hit=18 read=1 dirtied=1
-- Planning Time: 0.111 ms
-- Execution Time: 0.052 ms
-- With it: no Sort node at all. Walk the index from the top, stop
-- after 10 rows. A handful of pages instead of the whole table.

-- ---- 5.6 JOIN: an index on the join column ----
-- Customer service looks Nane up by email and lists her latest orders:
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.orderID, o.orderDate, o.status, o.orderTotal
FROM customers_big c
JOIN orders_big o ON o.customerID = c.customerID
WHERE c.email = 'nane.simonyan4242@mail.ru'
ORDER BY o.orderDate DESC
LIMIT 5;
--                                                                          QUERY PLAN
-- Limit  (cost=428.34..428.35 rows=5 width=23) (actual time=0.290..0.291 rows=5.00 loops=1)
--   Buffers: shared hit=3 read=101
--   ->  Sort  (cost=428.34..428.59 rows=100 width=23) (actual time=0.289..0.290 rows=5.00 loops=1)
--         Sort Key: o.orderdate DESC
--         Sort Method: top-N heapsort  Memory: 25kB
--         Buffers: shared hit=3 read=101
--         ->  Nested Loop  (cost=5.67..426.68 rows=100 width=23) (actual time=0.080..0.274 rows=97.00 loops=1)
--               Buffers: shared hit=3 read=101
--               ->  Index Scan using customers_big_email_key on customers_big c  (cost=0.41..8.43 rows=1 width=4) (actual time=0.016..0.017 rows=1.00 loops=1)
--                     Index Cond: ((email)::text = 'nane.simonyan4242@mail.ru'::text)
--                     Index Searches: 1
--                     Buffers: shared read=4
--               ->  Bitmap Heap Scan on orders_big o  (cost=5.25..417.18 rows=106 width=27) (actual time=0.062..0.247 rows=97.00 loops=1)
--                     Recheck Cond: (c.customerid = customerid)
--                     Heap Blocks: exact=97
--                     Buffers: shared hit=3 read=97
--                     ->  Bitmap Index Scan on orders_big_customerid_idx  (cost=0.00..5.23 rows=106 width=0) (actual time=0.009..0.009 rows=97.00 loops=1)
--                           Index Cond: (customerid = c.customerid)
--                           Index Searches: 1
--                           Buffers: shared hit=1 read=2
-- Planning:
--   Buffers: shared hit=77 read=15
-- Planning Time: 0.224 ms
-- Execution Time: 0.306 ms
-- Two indexes in one plan: the UNIQUE constraint on email (a
-- constraint is enforced by an index) finds 1 customer; the customerID
-- index finds her 97 orders. Nested Loop = "for each row on the
-- outside (1 customer), look up the inside (her orders)" -- cheap when
-- the outside is small and the inside has an index. (Part 8.4: the
-- other join methods.)

-- ---- 5.7 GROUP BY: sometimes ----
EXPLAIN (ANALYZE, BUFFERS)
SELECT customerID, count(*) AS orders FROM orders_big GROUP BY customerID;
--                                                                              QUERY PLAN
-- GroupAggregate  (cost=0.43..117919.12 rows=47337 width=12) (actual time=0.019..372.422 rows=48000.00 loops=1)
--   Group Key: customerid
--   Buffers: shared hit=96004 read=4340
--   ->  Index Only Scan using orders_big_customerid_idx on orders_big  (cost=0.43..92444.42 rows=5000266 width=4) (actual time=0.004..193.435 rows=5000000.00 loops=1)
--         Heap Fetches: 0
--         Index Searches: 1
--         Buffers: shared hit=96004 read=4340
-- Planning:
--   Buffers: shared hit=1 read=2
-- Planning Time: 0.029 ms
-- Execution Time: 373.435 ms
-- The planner reads the customerID index from start to end (Index Only
-- Scan) and gets the rows already grouped together, so GroupAggregate
-- needs no sort and no hash table. Without the index it would hash
-- all 5 million rows -- see the next query. Neither is dramatic: both
-- read everything. "Sometimes" is the honest word for GROUP BY.
SET enable_indexscan = off;
SET enable_indexonlyscan = off;
SET enable_bitmapscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT customerID, count(*) AS orders FROM orders_big GROUP BY customerID;
--                                                           QUERY PLAN
-- HashAggregate  (cost=134742.99..135216.36 rows=47337 width=12) (actual time=628.783..631.392 rows=48000.00 loops=1)
--   Group Key: customerid
--   Batches: 1  Memory Usage: 3097kB
--   Buffers: shared hit=2981 read=56758
--   ->  Seq Scan on orders_big  (cost=0.00..109741.66 rows=5000266 width=4) (actual time=0.060..158.754 rows=5000000.00 loops=1)
--         Buffers: shared hit=2981 read=56758
-- Planning Time: 0.052 ms
-- Execution Time: 632.595 ms
RESET enable_indexscan;
RESET enable_indexonlyscan;
RESET enable_bitmapscan;

-- Clean up: leave orders_big with its primary key only.
DROP INDEX orders_big_customerid_idx, orders_big_ordertotal_idx;



-- ============================================================
-- Lecture 7 — Part 6: Composite, partial, covering and expression indexes
-- Run after Part 5.
--
-- Four ways to make an index fit the query: several columns, only
-- some rows, extra columns carried along, or a computed value.
-- ============================================================

-- Start clean (in case you ran this Part before).
DROP INDEX IF EXISTS orders_big_cust_date_idx, orders_big_orderdate_idx,
                     orders_big_returned_idx, orders_big_customerid_idx,
                     orders_big_cust_incl_idx, customers_big_lower_email_idx;

-- ---- 6.1 Composite index: column order matters ----
-- Sorted by customerID first, and by orderDate within each customer --
-- like a phone book sorted by last name, then first name.
CREATE INDEX orders_big_cust_date_idx ON orders_big (customerID, orderDate);

-- (a) The first column alone:
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_big WHERE customerID = 4242;
--                                                              QUERY PLAN
-- Bitmap Heap Scan on orders_big  (cost=5.25..417.18 rows=106 width=60) (actual time=0.023..0.078 rows=97.00 loops=1)
--   Recheck Cond: (customerid = 4242)
--   Heap Blocks: exact=97
--   Buffers: shared hit=97 read=3
--   ->  Bitmap Index Scan on orders_big_cust_date_idx  (cost=0.00..5.23 rows=106 width=0) (actual time=0.014..0.014 rows=97.00 loops=1)
--         Index Cond: (customerid = 4242)
--         Index Searches: 1
--         Buffers: shared read=3
-- Planning:
--   Buffers: shared hit=67 read=9 dirtied=1
-- Planning Time: 0.180 ms
-- Execution Time: 0.103 ms
-- (b) Both columns:
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_big WHERE customerID = 4242 AND orderDate >= '2025-01-01';
--                                                              QUERY PLAN
-- Bitmap Heap Scan on orders_big  (cost=4.84..162.34 rows=40 width=60) (actual time=0.008..0.022 rows=43.00 loops=1)
--   Recheck Cond: ((customerid = 4242) AND (orderdate >= '2025-01-01'::date))
--   Heap Blocks: exact=43
--   Buffers: shared hit=46
--   ->  Bitmap Index Scan on orders_big_cust_date_idx  (cost=0.00..4.83 rows=40 width=0) (actual time=0.004..0.004 rows=43.00 loops=1)
--         Index Cond: ((customerid = 4242) AND (orderdate >= '2025-01-01'::date))
--         Index Searches: 1
--         Buffers: shared hit=3
-- Planning:
--   Buffers: shared hit=8
-- Planning Time: 0.027 ms
-- Execution Time: 0.026 ms
-- (a) and (b): 3 index pages each. In (b) BOTH conditions are in the
-- Index Cond, so only 43 table pages are read instead of 97.

-- (c) The second column alone. Predict, then run:
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_big WHERE orderDate = '2025-12-01';
--                                                                   QUERY PLAN
-- Bitmap Heap Scan on orders_big  (cost=91827.53..105484.66 rows=4407 width=60) (actual time=79.193..79.599 rows=5341.00 loops=1)
--   Recheck Cond: (orderdate = '2025-12-01'::date)
--   Heap Blocks: exact=64
--   Buffers: shared hit=8 read=13595
--   ->  Bitmap Index Scan on orders_big_cust_date_idx  (cost=0.00..91826.43 rows=4407 width=0) (actual time=79.053..79.053 rows=5341.00 loops=1)
--         Index Cond: (orderdate = '2025-12-01'::date)
--         Index Searches: 1
--         Buffers: shared hit=8 read=13531
-- Planning:
--   Buffers: shared hit=6
-- Planning Time: 0.016 ms
-- Execution Time: 79.711 ms
-- The plan NAMES the index, with orderDate in the Index Cond -- but
-- look at the Bitmap Index Scan's buffers: about 13,500 pages, the
-- WHOLE index. A phone book sorted by last name can't jump to every
-- "Anna"; you have to read every page. It's cheaper than reading the
-- table, so the planner does it, but it is not a lookup.
-- A real index on orderDate, for comparison:
CREATE INDEX orders_big_orderdate_idx ON orders_big (orderDate);
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_big WHERE orderDate = '2025-12-01';
--                                                                   QUERY PLAN
-- Index Scan using orders_big_orderdate_idx on orders_big  (cost=0.43..149.56 rows=4407 width=60) (actual time=0.013..0.348 rows=5341.00 loops=1)
--   Index Cond: (orderdate = '2025-12-01'::date)
--   Index Searches: 1
--   Buffers: shared hit=64 read=7
-- Planning:
--   Buffers: shared hit=18 read=1
-- Planning Time: 0.094 ms
-- Execution Time: 0.451 ms
-- A few dozen pages. The rule: a composite index helps a query that
-- filters on its FIRST column (or first few, from the left). A query
-- on a later column alone needs its own index.
-- (PostgreSQL 18 adds "skip scan", which can jump through a composite
-- index when the first column has few distinct values. With 48,000
-- customers it doesn't pay off here -- "Index Searches: 1" means one
-- pass through the index.)
DROP INDEX orders_big_cust_date_idx, orders_big_orderdate_idx;

-- ---- 6.2 Partial index: only the rows you ask about ----
-- The returns team asks every day about recent returns. Index only the
-- returned orders:
CREATE INDEX orders_big_returned_idx ON orders_big (orderDate) WHERE status = 'returned';
SELECT pg_size_pretty(pg_relation_size('orders_big_returned_idx')) AS partial_index_size;
-- partial_index_size
-- 1672 kB
-- About 1.7 MB. A full index on orderDate is about 34 MB (Part 4).
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE status = 'returned' AND orderDate >= '2025-12-01';
--                                                                     QUERY PLAN
-- Aggregate  (cost=306.56..306.56 rows=1 width=40) (actual time=4.680..4.681 rows=1.00 loops=1)
--   Buffers: shared hit=901 read=1064
--   ->  Index Scan using orders_big_returned_idx on orders_big  (cost=0.29..266.72 rows=7967 width=6) (actual time=0.009..3.998 rows=8062.00 loops=1)
--         Index Cond: (orderdate >= '2025-12-01'::date)
--         Index Searches: 1
--         Buffers: shared hit=901 read=1064
-- Planning:
--   Buffers: shared hit=22 read=4
-- Planning Time: 0.104 ms
-- Execution Time: 4.695 ms
-- Used: the query's WHERE contains the index's WHERE exactly.

-- The same team asks for returns AND cancellations:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE status IN ('returned', 'cancelled') AND orderDate >= '2025-12-01';
--                                                          QUERY PLAN
-- Aggregate  (cost=134809.02..134809.03 rows=1 width=40) (actual time=335.662..335.663 rows=1.00 loops=1)
--   Buffers: shared hit=4600 read=55139
--   ->  Seq Scan on orders_big  (cost=0.00..134742.99 rows=13206 width=6) (actual time=323.079..334.710 rows=13430.00 loops=1)
--         Filter: (((status)::text = ANY ('{returned,cancelled}'::text[])) AND (orderdate >= '2025-12-01'::date))
--         Rows Removed by Filter: 4986570
--         Buffers: shared hit=4600 read=55139
-- Planning:
--   Buffers: shared hit=53 read=1
-- Planning Time: 0.144 ms
-- Execution Time: 335.675 ms
-- Not used: the index holds no cancelled orders, so it can't answer.
-- Seq Scan of the whole table. Correct, but slow, and silent.

-- A colleague "rewrites the same filter":
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE status <> 'completed' AND status <> 'cancelled' AND orderDate >= '2025-12-01';
--                                                               QUERY PLAN
-- Aggregate  (cost=147307.53..147307.54 rows=1 width=40) (actual time=252.685..252.686 rows=1.00 loops=1)
--   Buffers: shared hit=4694 read=55045
--   ->  Seq Scan on orders_big  (cost=0.00..147243.66 rows=12775 width=6) (actual time=243.804..252.120 rows=8062.00 loops=1)
--         Filter: (((status)::text <> 'completed'::text) AND ((status)::text <> 'cancelled'::text) AND (orderdate >= '2025-12-01'::date))
--         Rows Removed by Filter: 4991938
--         Buffers: shared hit=4694 read=55045
-- Planning:
--   Buffers: shared hit=5
-- Planning Time: 0.079 ms
-- Execution Time: 252.700 ms
-- Not used either -- even though, with the CHECK constraint, "not
-- completed and not cancelled" can only mean returned. The planner
-- uses a partial index only when it can PROVE, from the query's WHERE
-- alone, that every row the query needs is in the index -- and it
-- doesn't reason through CHECK constraints for that. Write the
-- condition the index was built with.
DROP INDEX orders_big_returned_idx;

-- ---- 6.3 Covering index (INCLUDE): carry the columns you read ----
-- Nane's lifetime spending:
CREATE INDEX orders_big_customerid_idx ON orders_big (customerID);
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big WHERE customerID = 4242;
--                                                                  QUERY PLAN
-- Aggregate  (cost=417.72..417.73 rows=1 width=40) (actual time=0.092..0.092 rows=1.00 loops=1)
--   Buffers: shared hit=97 read=3
--   ->  Bitmap Heap Scan on orders_big  (cost=5.25..417.18 rows=106 width=6) (actual time=0.022..0.077 rows=97.00 loops=1)
--         Recheck Cond: (customerid = 4242)
--         Heap Blocks: exact=97
--         Buffers: shared hit=97 read=3
--         ->  Bitmap Index Scan on orders_big_customerid_idx  (cost=0.00..5.23 rows=106 width=0) (actual time=0.012..0.012 rows=97.00 loops=1)
--               Index Cond: (customerid = 4242)
--               Index Searches: 1
--               Buffers: shared read=3
-- Planning:
--   Buffers: shared hit=16 read=1
-- Planning Time: 0.092 ms
-- Execution Time: 0.106 ms
-- 3 index pages, then 97 table pages -- only to read orderTotal.
-- Carry orderTotal inside the index:
CREATE INDEX orders_big_cust_incl_idx ON orders_big (customerID) INCLUDE (orderTotal);
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big WHERE customerID = 4242;
--                                                                      QUERY PLAN
-- Aggregate  (cost=6.82..6.83 rows=1 width=40) (actual time=0.031..0.031 rows=1.00 loops=1)
--   Buffers: shared hit=2 read=3
--   ->  Index Only Scan using orders_big_cust_incl_idx on orders_big  (cost=0.43..6.29 rows=106 width=6) (actual time=0.015..0.021 rows=97.00 loops=1)
--         Index Cond: (customerid = 4242)
--         Heap Fetches: 0
--         Index Searches: 1
--         Buffers: shared hit=2 read=3
-- Planning:
--   Buffers: shared hit=18 read=1
-- Planning Time: 0.100 ms
-- Execution Time: 0.044 ms
-- Index Only Scan, Heap Fetches 0: about 5 pages instead of 100.
-- INCLUDE columns are stored in the index but not sorted on, so they
-- can't be searched -- only read. The price:
SELECT relname AS index, pg_size_pretty(pg_relation_size(oid)) AS size
FROM pg_class
WHERE relname IN ('orders_big_customerid_idx', 'orders_big_cust_incl_idx');
--           index           |  size
-- orders_big_customerid_idx | 34 MB
-- orders_big_cust_incl_idx  | 150 MB
-- More than four times bigger. With INCLUDE columns, every row needs
-- its own index entry (no deduplication -- 5.3), plus the orderTotal.
-- INCLUDE needs PostgreSQL 11 or later.
DROP INDEX orders_big_customerid_idx, orders_big_cust_incl_idx;

-- ---- 6.4 Expression index: index a computed value ----
-- At login, a customer types "Nane.Simonyan4242@Mail.ru". Emails are
-- stored in lower case, so the app compares lower case to lower case:
EXPLAIN (ANALYZE, BUFFERS)
SELECT customerID, firstName, lastName FROM customers_big
WHERE lower(email) = lower('Nane.Simonyan4242@Mail.ru');
--                                                   QUERY PLAN
-- Seq Scan on customers_big  (cost=0.00..1570.00 rows=250 width=20) (actual time=1.041..10.324 rows=1.00 loops=1)
--   Filter: (lower((email)::text) = 'nane.simonyan4242@mail.ru'::text)
--   Rows Removed by Filter: 49999
--   Buffers: shared hit=1 read=819
-- Planning:
--   Buffers: shared hit=37
-- Planning Time: 0.086 ms
-- Execution Time: 10.330 ms
-- Seq Scan over all 50,000 customers -- although email has a UNIQUE
-- index. That index holds email, not lower(email). Index the
-- expression itself:
CREATE INDEX customers_big_lower_email_idx ON customers_big (lower(email));
ANALYZE customers_big;
EXPLAIN (ANALYZE, BUFFERS)
SELECT customerID, firstName, lastName FROM customers_big
WHERE lower(email) = lower('Nane.Simonyan4242@Mail.ru');
--                                                                   QUERY PLAN
-- Index Scan using customers_big_lower_email_idx on customers_big  (cost=0.41..8.43 rows=1 width=20) (actual time=0.014..0.014 rows=1.00 loops=1)
--   Index Cond: (lower((email)::text) = 'nane.simonyan4242@mail.ru'::text)
--   Index Searches: 1
--   Buffers: shared hit=1 read=3
-- Planning:
--   Buffers: shared hit=16 read=1
-- Planning Time: 0.089 ms
-- Execution Time: 0.022 ms
-- Index Scan: a few pages. The query must use the SAME expression as
-- the index, written the same way. ANALYZE after creating an
-- expression index also gathers statistics on the expression's values.
DROP INDEX customers_big_lower_email_idx;
ANALYZE customers_big;



-- ============================================================
-- Lecture 7 — Part 7: Traps -- the index exists but is not used
-- Run after Part 6.
--
-- Each trap returns the right rows, slowly, with a perfectly good
-- index sitting next to it. The plan is the only place it shows.
-- One reading skill for this whole Part: an index condition the index
-- can SEARCH appears as "Index Cond:". A condition checked row by row
-- appears as "Filter:" -- even when the node's name says "Index".
-- ============================================================

-- Start clean (in case you ran this Part before).
DROP INDEX IF EXISTS orders_big_orderdate_idx, orders_big_customerid_idx,
                     orders_big_month_idx, orders_big_deliverydate_idx,
                     customers_big_email_pattern_idx;
DROP TABLE IF EXISTS r_or_seq, r_or_index, r_union_all;
CREATE INDEX orders_big_orderdate_idx ON orders_big (orderDate);
CREATE INDEX orders_big_customerid_idx ON orders_big (customerID);

-- ---- 7.1 A function on the indexed column ----
-- "Revenue in June 2025", written the way people say it:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE date_trunc('month', orderDate) = '2025-06-01';
--                                                               QUERY PLAN
-- Aggregate  (cost=147368.66..147368.67 rows=1 width=40) (actual time=555.922..555.923 rows=1.00 loops=1)
--   Buffers: shared hit=5540 read=54199
--   ->  Seq Scan on orders_big  (cost=0.00..147243.66 rows=25001 width=6) (actual time=418.942..543.696 rows=155419.00 loops=1)
--         Filter: (date_trunc('month'::text, (orderdate)::timestamp with time zone) = '2025-06-01 00:00:00+00'::timestamp with time zone)
--         Rows Removed by Filter: 4844581
--         Buffers: shared hit=5540 read=54199
-- Planning:
--   Buffers: shared hit=62 read=2
-- Planning Time: 0.145 ms
-- Execution Time: 555.952 ms
-- WRONG PLAN: Seq Scan, the orderDate index unused. The index is
-- sorted by orderDate; it knows nothing about date_trunc(orderDate).
-- Note the estimate too: the planner has no statistics on the
-- expression, so it guesses a fixed share (0.5%) of the table --
-- 25,000 against 155,419 real rows.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE extract(year FROM orderDate) = 2025 AND extract(month FROM orderDate) = 6;
--                                                         QUERY PLAN
-- Aggregate  (cost=159744.95..159744.96 rows=1 width=40) (actual time=562.900..562.901 rows=1.00 loops=1)
--   Buffers: shared hit=5634 read=54105
--   ->  Seq Scan on orders_big  (cost=0.00..159744.32 rows=125 width=6) (actual time=378.828..550.393 rows=155419.00 loops=1)
--         Filter: ((EXTRACT(year FROM orderdate) = '2025'::numeric) AND (EXTRACT(month FROM orderdate) = '6'::numeric))
--         Rows Removed by Filter: 4844581
--         Buffers: shared hit=5634 read=54105
-- Planning:
--   Buffers: shared hit=6
-- Planning Time: 0.051 ms
-- Execution Time: 562.914 ms
-- Same problem, and a worse guess (0.5% of 0.5%: about 125 rows).

-- FIX 1: say it as a range on the column itself.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE orderDate >= '2025-06-01' AND orderDate < '2025-07-01';
--                                                                         QUERY PLAN
-- Aggregate  (cost=6208.16..6208.17 rows=1 width=40) (actual time=25.514..25.514 rows=1.00 loops=1)
--   Buffers: shared hit=2 read=1993
--   ->  Index Scan using orders_big_orderdate_idx on orders_big  (cost=0.43..5440.01 rows=153629 width=6) (actual time=0.026..13.713 rows=155419.00 loops=1)
--         Index Cond: ((orderdate >= '2025-06-01'::date) AND (orderdate < '2025-07-01'::date))
--         Index Searches: 1
--         Buffers: shared hit=2 read=1993
-- Planning:
--   Buffers: shared hit=49
-- Planning Time: 0.126 ms
-- Execution Time: 25.530 ms
-- Index Scan, estimate close to the 155,419 real rows, and the same
-- answer. Use ">= first day AND < first day of NEXT month": it is
-- right for dates and for timestamps (BETWEEN ... '2025-06-30' would
-- lose June 30 after midnight on a timestamp column).

-- FIX 2: index the expression (Part 6.4). Error on purpose:
CREATE INDEX orders_big_month_idx ON orders_big (date_trunc('month', orderDate));
-- ERROR:  functions in index expression must be marked IMMUTABLE
-- An index may only use IMMUTABLE functions: same input, same output,
-- forever. date_trunc on a date first turns it into a timestamp WITH
-- time zone (look at the Filter in the first plan above), and that
-- result depends on the session's time zone setting. Cast to a plain
-- timestamp, and it's immutable:
CREATE INDEX orders_big_month_idx ON orders_big (date_trunc('month', orderDate::timestamp));
ANALYZE orders_big;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE date_trunc('month', orderDate::timestamp) = '2025-06-01';
--                                                                      QUERY PLAN
-- Aggregate  (cost=5811.12..5811.13 rows=1 width=40) (actual time=20.550..20.551 rows=1.00 loops=1)
--   Buffers: shared hit=1858 read=133
--   ->  Index Scan using orders_big_month_idx on orders_big  (cost=0.43..5043.63 rows=153497 width=6) (actual time=0.014..9.153 rows=155419.00 loops=1)
--         Index Cond: (date_trunc('month'::text, (orderdate)::timestamp without time zone) = '2025-06-01 00:00:00'::timestamp without time zone)
--         Index Searches: 1
--         Buffers: shared hit=1858 read=133
-- Planning:
--   Buffers: shared hit=44 read=1
-- Planning Time: 0.126 ms
-- Execution Time: 20.565 ms
-- Works -- for queries written with exactly this expression. FIX 1
-- needs no new index and works for any range; prefer it.
DROP INDEX orders_big_month_idx;

-- ---- 7.2 A type mismatch ----
-- The app passes the customer number as a decimal:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big WHERE customerID = 4242.0;
--                                                                           QUERY PLAN
-- Aggregate  (cost=117501.11..117501.12 rows=1 width=8) (actual time=303.448..303.449 rows=1.00 loops=1)
--   Buffers: shared hit=96000 read=4344
--   ->  Index Only Scan using orders_big_customerid_idx on orders_big  (cost=0.43..117438.61 rows=25000 width=0) (actual time=23.881..303.441 rows=97.00 loops=1)
--         Filter: ((customerid)::numeric = 4242.0)
--         Rows Removed by Filter: 4999903
--         Heap Fetches: 0
--         Index Searches: 1
--         Buffers: shared hit=96000 read=4344
-- Planning:
--   Buffers: shared hit=8
-- Planning Time: 0.040 ms
-- Execution Time: 303.459 ms
-- WRONG PLAN. The node is "Index Only Scan using
-- orders_big_customerid_idx" -- but there is no Index Cond, only a
-- Filter: (customerid)::numeric = 4242.0. To compare an integer with
-- a numeric, PostgreSQL converts the COLUMN, every row of it, and the
-- index on the integer can't be searched. It reads all 5 million
-- index entries (Rows Removed by Filter) to find 97.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big WHERE customerID = '4242';
--                                                                      QUERY PLAN
-- Aggregate  (cost=6.53..6.54 rows=1 width=8) (actual time=0.025..0.026 rows=1.00 loops=1)
--   Buffers: shared hit=4 read=1
--   ->  Index Only Scan using orders_big_customerid_idx on orders_big  (cost=0.43..6.27 rows=105 width=0) (actual time=0.014..0.021 rows=97.00 loops=1)
--         Index Cond: (customerid = 4242)
--         Heap Fetches: 0
--         Index Searches: 1
--         Buffers: shared hit=4 read=1
-- Planning:
--   Buffers: shared hit=5
-- Planning Time: 0.056 ms
-- Execution Time: 0.035 ms
-- A quoted literal is fine: '4242' has no type yet, so it becomes an
-- integer, and the Index Cond is back.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big WHERE customerID::text = '4242';
--                                                                           QUERY PLAN
-- Aggregate  (cost=130000.88..130000.89 rows=1 width=8) (actual time=257.492..257.493 rows=1.00 loops=1)
--   Buffers: shared hit=100344
--   ->  Index Only Scan using orders_big_customerid_idx on orders_big  (cost=0.43..129938.38 rows=25000 width=0) (actual time=24.053..257.484 rows=97.00 loops=1)
--         Filter: ((customerid)::text = '4242'::text)
--         Rows Removed by Filter: 4999903
--         Heap Fetches: 0
--         Index Searches: 1
--         Buffers: shared hit=100344
-- Planning:
--   Buffers: shared hit=14
-- Planning Time: 0.037 ms
-- Execution Time: 257.504 ms
-- WRONG PLAN again: a cast on the column is a function on the column
-- (7.1). FIX: make the VALUE the column's type -- 4242, or
-- CAST(:param AS int) -- never cast the column.

-- ---- 7.3 LIKE: 'text%' and '%text' ----
-- A search box: the user has typed the start of an email address.
EXPLAIN (ANALYZE, BUFFERS)
SELECT customerID, email FROM customers_big WHERE email LIKE 'nane.simonyan4242%';
--                                                  QUERY PLAN
-- Seq Scan on customers_big  (cost=0.00..1445.00 rows=5 width=34) (actual time=0.216..2.185 rows=1.00 loops=1)
--   Filter: ((email)::text ~~ 'nane.simonyan4242%'::text)
--   Rows Removed by Filter: 49999
--   Buffers: shared hit=820
-- Planning:
--   Buffers: shared hit=34 read=6
-- Planning Time: 0.126 ms
-- Execution Time: 2.192 ms
-- Seq Scan, although email has a UNIQUE index. The database sorts text
-- by language rules (its collation): your database's is shown by the
-- next query. Under those rules the index's order can't be used for
-- LIKE.
SELECT datcollate FROM pg_database WHERE datname = current_database();
-- datcollate
-- en_US.utf8
-- FIX: an index built with the "pattern" operator class, which sorts
-- character by character. (If your datcollate is C, the plain index
-- already works and you'll see an Index Scan above.)
CREATE INDEX customers_big_email_pattern_idx ON customers_big (email varchar_pattern_ops);
EXPLAIN (ANALYZE, BUFFERS)
SELECT customerID, email FROM customers_big WHERE email LIKE 'nane.simonyan4242%';
--                                                                    QUERY PLAN
-- Index Scan using customers_big_email_pattern_idx on customers_big  (cost=0.41..8.44 rows=5 width=34) (actual time=0.015..0.015 rows=1.00 loops=1)
--   Index Cond: (((email)::text ~>=~ 'nane.simonyan4242'::text) AND ((email)::text ~<~ 'nane.simonyan4243'::text))
--   Filter: ((email)::text ~~ 'nane.simonyan4242%'::text)
--   Index Searches: 1
--   Buffers: shared hit=1 read=3
-- Planning:
--   Buffers: shared hit=59 read=1
-- Planning Time: 0.139 ms
-- Execution Time: 0.024 ms
-- Index Cond: email >= 'nane.simonyan4242' AND email < 'nane.simonyan4243'
-- -- a prefix is a range of the sorted index.
-- The other end of the string:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM customers_big WHERE email LIKE '%@yahoo.com';
--                                                        QUERY PLAN
-- Aggregate  (cost=1472.78..1472.79 rows=1 width=8) (actual time=4.231..4.231 rows=1.00 loops=1)
--   Buffers: shared hit=820
--   ->  Seq Scan on customers_big  (cost=0.00..1445.00 rows=11111 width=0) (actual time=0.004..3.929 rows=12576.00 loops=1)
--         Filter: ((email)::text ~~ '%@yahoo.com'::text)
--         Rows Removed by Filter: 37424
--         Buffers: shared hit=820
-- Planning Time: 0.026 ms
-- Execution Time: 4.238 ms
-- Seq Scan, with any B-tree. A leading wildcard has no place to start
-- in a sorted list, like looking up every surname ending in "-yan" in
-- a phone book. (Searches inside text need a different index type --
-- the pg_trgm extension, beyond this lecture.)
DROP INDEX customers_big_email_pattern_idx;

-- ---- 7.4 OR across different columns ----
-- Customer service: "Nane's orders, or anything delivered on 14
-- December 2025" (the day her last order arrived).
EXPLAIN (ANALYZE, BUFFERS)
SELECT orderID, customerID, deliveryDate FROM orders_big
WHERE customerID = 4242 OR deliveryDate = '2025-12-14';
--                                                     QUERY PLAN
-- Seq Scan on orders_big  (cost=0.00..134737.64 rows=1458 width=12) (actual time=2.898..220.200 rows=1749.00 loops=1)
--   Filter: ((customerid = 4242) OR (deliverydate = '2025-12-14'::date))
--   Rows Removed by Filter: 4998251
--   Buffers: shared hit=8028 read=51711
-- Planning:
--   Buffers: shared hit=6
-- Planning Time: 0.030 ms
-- Execution Time: 220.250 ms
-- WRONG PLAN: Seq Scan. customerID has an index; deliveryDate has
-- none. One index can't answer an OR: a row with deliveryDate
-- 2025-12-14 might be anywhere, so the whole table must be read anyway.
-- Save this answer before changing anything (7.6 compares it):
CREATE TEMP TABLE r_or_seq AS
SELECT orderID, customerID, deliveryDate FROM orders_big
WHERE customerID = 4242 OR deliveryDate = '2025-12-14';

-- FIX A: index the other column too.
CREATE INDEX orders_big_deliverydate_idx ON orders_big (deliveryDate);
EXPLAIN (ANALYZE, BUFFERS)
SELECT orderID, customerID, deliveryDate FROM orders_big
WHERE customerID = 4242 OR deliveryDate = '2025-12-14';
--                                                                     QUERY PLAN
-- Bitmap Heap Scan on orders_big  (cost=24.53..5138.99 rows=1458 width=12) (actual time=0.088..0.478 rows=1749.00 loops=1)
--   Recheck Cond: ((customerid = 4242) OR (deliverydate = '2025-12-14'::date))
--   Heap Blocks: exact=414
--   Buffers: shared hit=417 read=5
--   ->  BitmapOr  (cost=24.53..24.53 rows=1458 width=0) (actual time=0.059..0.060 rows=0.00 loops=1)
--         Buffers: shared hit=3 read=5
--         ->  Bitmap Index Scan on orders_big_customerid_idx  (cost=0.00..5.22 rows=105 width=0) (actual time=0.008..0.009 rows=97.00 loops=1)
--               Index Cond: (customerid = 4242)
--               Index Searches: 1
--               Buffers: shared hit=3
--         ->  Bitmap Index Scan on orders_big_deliverydate_idx  (cost=0.00..18.58 rows=1353 width=0) (actual time=0.050..0.050 rows=1653.00 loops=1)
--               Index Cond: (deliverydate = '2025-12-14'::date)
--               Index Searches: 1
--               Buffers: shared read=5
-- Planning:
--   Buffers: shared hit=18 read=1
-- Planning Time: 0.134 ms
-- Execution Time: 0.520 ms
-- BitmapOr: two bitmap index scans, one per column, combined into one
-- set of pages.
CREATE TEMP TABLE r_or_index AS
SELECT orderID, customerID, deliveryDate FROM orders_big
WHERE customerID = 4242 OR deliveryDate = '2025-12-14';

-- FIX B, the usual advice: split the OR into two queries, one per
-- column, glued with UNION -- each half can use its own index:
EXPLAIN (ANALYZE, BUFFERS)
SELECT orderID, customerID, deliveryDate FROM orders_big WHERE customerID = 4242
UNION
SELECT orderID, customerID, deliveryDate FROM orders_big WHERE deliveryDate = '2025-12-14';
--                                                                                 QUERY PLAN
-- HashAggregate  (cost=483.77..498.35 rows=1458 width=12) (actual time=0.594..0.676 rows=1749.00 loops=1)
--   Group Key: orders_big.orderid, orders_big.customerid, orders_big.deliverydate
--   Batches: 1  Memory Usage: 121kB
--   Buffers: shared hit=423
--   ->  Append  (cost=5.25..472.84 rows=1458 width=12) (actual time=0.016..0.393 rows=1750.00 loops=1)
--         Buffers: shared hit=423
--         ->  Bitmap Heap Scan on orders_big  (cost=5.25..413.35 rows=105 width=12) (actual time=0.016..0.045 rows=97.00 loops=1)
--               Recheck Cond: (customerid = 4242)
--               Heap Blocks: exact=97
--               Buffers: shared hit=100
--               ->  Bitmap Index Scan on orders_big_customerid_idx  (cost=0.00..5.22 rows=105 width=0) (actual time=0.006..0.006 rows=97.00 loops=1)
--                     Index Cond: (customerid = 4242)
--                     Index Searches: 1
--                     Buffers: shared hit=3
--         ->  Index Scan using orders_big_deliverydate_idx on orders_big orders_big_1  (cost=0.43..52.19 rows=1353 width=12) (actual time=0.009..0.287 rows=1653.00 loops=1)
--               Index Cond: (deliverydate = '2025-12-14'::date)
--               Index Searches: 1
--               Buffers: shared hit=323
-- Planning:
--   Buffers: shared hit=11
-- Planning Time: 0.073 ms
-- Execution Time: 0.744 ms
-- Two index scans, appended, then duplicates removed (HashAggregate).
-- A colleague writes UNION ALL instead, "because it skips the
-- duplicate removal, so it's faster":
CREATE TEMP TABLE r_union_all AS
SELECT orderID, customerID, deliveryDate FROM orders_big WHERE customerID = 4242
UNION ALL
SELECT orderID, customerID, deliveryDate FROM orders_big WHERE deliveryDate = '2025-12-14';

-- ---- 7.5 Low selectivity (Part 4, again) ----
-- An index on status would not change Part 4.3's verdict: 92% of the
-- rows means read the table. That one isn't a trap; it's the planner
-- being right.

-- ---- 7.6 An index changes speed, never results. Prove it. ----
-- Before the index (Seq Scan) vs after it (BitmapOr), EXCEPT both ways,
-- with the row counts:
SELECT (SELECT count(*) FROM r_or_seq)   AS rows_seq_scan,
       (SELECT count(*) FROM r_or_index) AS rows_bitmap_or,
       (SELECT count(*) FROM (SELECT * FROM r_or_seq EXCEPT SELECT * FROM r_or_index) a) AS seq_not_index,
       (SELECT count(*) FROM (SELECT * FROM r_or_index EXCEPT SELECT * FROM r_or_seq) b) AS index_not_seq;
-- rows_seq_scan | rows_bitmap_or | seq_not_index | index_not_seq
--          1749 |           1749 |             0 |             0
-- 0 and 0, same count: the index changed the plan, not the answer.

-- Now the UNION ALL "optimization", checked the same way:
SELECT (SELECT count(*) FROM r_or_seq)    AS rows_or,
       (SELECT count(*) FROM r_union_all) AS rows_union_all,
       (SELECT count(*) FROM (SELECT * FROM r_or_seq EXCEPT SELECT * FROM r_union_all) a) AS or_not_union,
       (SELECT count(*) FROM (SELECT * FROM r_union_all EXCEPT SELECT * FROM r_or_seq) b) AS union_not_or;
-- rows_or | rows_union_all | or_not_union | union_not_or
--    1749 |           1750 |            0 |            0
-- EXCEPT says 0 and 0 -- but the counts differ by one. Order 4890168
-- is Nane's AND was delivered on 2025-12-14, so UNION ALL lists it
-- twice. EXCEPT compares SETS (Lecture 5, Part 6): duplicates vanish
-- before comparing, so it can't see this. EXCEPT ALL can:
SELECT orderID, customerID, deliveryDate FROM r_union_all
EXCEPT ALL
SELECT orderID, customerID, deliveryDate FROM r_or_seq;
-- orderid | customerid | deliverydate
-- 4890168 |       4242 | 2025-12-14
-- WRONG "optimization": it changed the answer (revenue summed over it
-- would count that order twice). FIX: UNION, which removes duplicate
-- rows -- or check every rewrite with EXCEPT ALL both ways AND
-- matching row counts.
SELECT count(*) AS rows_union FROM (
    SELECT orderID, customerID, deliveryDate FROM orders_big WHERE customerID = 4242
    UNION
    SELECT orderID, customerID, deliveryDate FROM orders_big WHERE deliveryDate = '2025-12-14'
) u;
-- rows_union
--       1749

-- The same proof on ground truth you already know -- the small
-- orders table, with its index forced (Part 1.1's planner would never
-- use it on 8 pages):
CREATE INDEX orders_status_idx ON orders (status);
SET enable_seqscan = off;
EXPLAIN
SELECT sum(orderTotal) FROM orders WHERE status = 'completed';
--                                       QUERY PLAN
-- Aggregate  (cost=28.19..28.20 rows=1 width=32)
--   ->  Bitmap Heap Scan on orders  (cost=12.25..26.86 rows=529 width=6)
--         Recheck Cond: ((status)::text = 'completed'::text)
--         ->  Bitmap Index Scan on orders_status_idx  (cost=0.00..12.12 rows=529 width=0)
--               Index Cond: ((status)::text = 'completed'::text)
SELECT sum(orderTotal) AS completed_revenue FROM orders WHERE status = 'completed';
-- completed_revenue
--         157078.41
RESET enable_seqscan;
DROP INDEX orders_status_idx;
-- 157,078.41 through the index -- the number from Lectures 4, 5 and 6.

-- Clean up: leave orders_big with its primary key only.
DROP INDEX orders_big_orderdate_idx, orders_big_customerid_idx, orders_big_deliverydate_idx;
DROP TABLE r_or_seq, r_or_index, r_union_all;



-- ============================================================
-- Lecture 7 — Part 8: Callbacks -- checking earlier claims with plans
-- Run after Part 7.
--
-- Lectures 5 and 6 compared ways to write the same question on
-- correctness. Now: what does each one cost on 5 million rows?
-- Whatever the plans say, including the surprises.
-- ============================================================

-- Start clean (in case you ran this Part before).
DROP INDEX IF EXISTS orders_big_cust_latest_idx, orders_big_customerid_idx;
DROP TABLE IF EXISTS latest_sorted, latest_lateral;

-- ---- 8.1 NOT IN vs NOT EXISTS: correctness first (Lecture 5, 2.2) ----
-- "Salespeople who never had an order cancelled", on the small shop:
SELECT e.employeeID, e.firstName, e.lastName
FROM employees e
WHERE e.employeeID NOT IN (SELECT o.employeeID FROM orders o
                           WHERE o.status = 'cancelled');
-- employeeid | firstname | lastname
-- (0 rows)
SELECT e.employeeID, e.firstName, e.lastName
FROM employees e
WHERE NOT EXISTS (SELECT 1 FROM orders o
                  WHERE o.employeeID = e.employeeID AND o.status = 'cancelled');
-- employeeid | firstname | lastname
--          5 | Hayk      | Melikyan
-- Lecture 5's result, unchanged: NOT IN returns nothing because 5 of
-- the cancelled orders have a NULL employeeID; NOT EXISTS finds Hayk.
-- That is the main reason to choose NOT EXISTS. Now the speed.

-- ---- 8.2 What the planner turns them into ----
-- "Customers who never cancelled an order", on 50,000 customers and
-- 159,902 cancelled orders (customerID is NOT NULL, so all three
-- forms give the same answer here):
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM customers_big c
WHERE NOT EXISTS (SELECT 1 FROM orders_big o
                  WHERE o.customerID = c.customerID AND o.status = 'cancelled');
--                                                                               QUERY PLAN
-- Aggregate  (cost=126335.08..126335.09 rows=1 width=8) (actual time=288.018..288.021 rows=1.00 loops=1)
--   Buffers: shared hit=8408 read=51470
--   ->  Hash Right Anti Join  (cost=1931.29..126329.01 rows=2425 width=0) (actual time=287.147..287.909 rows=3751.00 loops=1)
--         Hash Cond: (o.customerid = c.customerid)
--         Buffers: shared hit=8408 read=51470
--         ->  Seq Scan on orders_big o  (cost=0.00..122237.86 rows=163497 width=4) (actual time=0.077..263.187 rows=159902.00 loops=1)
--               Filter: ((status)::text = 'cancelled'::text)
--               Rows Removed by Filter: 4840098
--               Buffers: shared hit=8404 read=51335
--         ->  Hash  (cost=1306.29..1306.29 rows=50000 width=4) (actual time=5.711..5.712 rows=50000.00 loops=1)
--               Buckets: 65536  Batches: 1  Memory Usage: 2270kB
--               Buffers: shared hit=4 read=135
--               ->  Index Only Scan using customers_big_pkey on customers_big c  (cost=0.29..1306.29 rows=50000 width=4) (actual time=0.012..2.870 rows=50000.00 loops=1)
--                     Heap Fetches: 0
--                     Index Searches: 1
--                     Buffers: shared hit=4 read=135
-- Planning:
--   Buffers: shared hit=75
-- Planning Time: 0.119 ms
-- Execution Time: 288.103 ms
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM customers_big c
LEFT JOIN orders_big o ON o.customerID = c.customerID AND o.status = 'cancelled'
WHERE o.customerID IS NULL;
--                                                                               QUERY PLAN
-- Aggregate  (cost=126335.08..126335.09 rows=1 width=8) (actual time=295.412..295.414 rows=1.00 loops=1)
--   Buffers: shared hit=8637 read=51241
--   ->  Hash Right Anti Join  (cost=1931.29..126329.01 rows=2425 width=0) (actual time=294.488..295.303 rows=3751.00 loops=1)
--         Hash Cond: (o.customerid = c.customerid)
--         Buffers: shared hit=8637 read=51241
--         ->  Seq Scan on orders_big o  (cost=0.00..122237.86 rows=163497 width=4) (actual time=0.043..268.464 rows=159902.00 loops=1)
--               Filter: ((status)::text = 'cancelled'::text)
--               Rows Removed by Filter: 4840098
--               Buffers: shared hit=8498 read=51241
--         ->  Hash  (cost=1306.29..1306.29 rows=50000 width=4) (actual time=4.894..4.895 rows=50000.00 loops=1)
--               Buckets: 65536  Batches: 1  Memory Usage: 2270kB
--               Buffers: shared hit=139
--               ->  Index Only Scan using customers_big_pkey on customers_big c  (cost=0.29..1306.29 rows=50000 width=4) (actual time=0.008..2.545 rows=50000.00 loops=1)
--                     Heap Fetches: 0
--                     Index Searches: 1
--                     Buffers: shared hit=139
-- Planning:
--   Buffers: shared hit=6
-- Planning Time: 0.108 ms
-- Execution Time: 295.437 ms
-- The SAME plan for both: a Hash Anti Join ("Hash Right Anti Join" on
-- PostgreSQL 16+: the hash table is built on the smaller side, the
-- customers). The planner rewrote NOT EXISTS and LEFT JOIN ... IS NULL
-- into one anti-join. How you write it doesn't matter to it.
-- (On PostgreSQL 14, the next query takes minutes: run
-- SET hash_mem_multiplier = 2.0 first, or skip it. Notes, Part 8.3.)
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM customers_big c
WHERE c.customerID NOT IN (SELECT o.customerID FROM orders_big o
                           WHERE o.status = 'cancelled');
--                                                                              QUERY PLAN
-- Aggregate  (cost=124140.39..124140.40 rows=1 width=8) (actual time=299.157..299.158 rows=1.00 loops=1)
--   Buffers: shared hit=8731 read=51147
--   ->  Index Only Scan using customers_big_pkey on customers_big c  (cost=122646.89..124077.89 rows=25000 width=0) (actual time=292.395..299.042 rows=3751.00 loops=1)
--         Filter: (NOT (ANY (customerid = (hashed SubPlan 1).col1)))
--         Rows Removed by Filter: 46249
--         Heap Fetches: 0
--         Index Searches: 1
--         Buffers: shared hit=8731 read=51147
--         SubPlan 1
--           ->  Seq Scan on orders_big o  (cost=0.00..122237.86 rows=163497 width=4) (actual time=0.166..260.541 rows=159902.00 loops=1)
--                 Filter: ((status)::text = 'cancelled'::text)
--                 Rows Removed by Filter: 4840098
--                 Buffers: shared hit=8592 read=51147
-- Planning Time: 0.066 ms
-- Execution Time: 299.310 ms
-- NOT IN is NOT turned into an anti-join (because of what NOT IN does
-- with NULLs, the planner can't). It runs the subquery once, keeps
-- its 159,902 values in a hash table in memory ("hashed SubPlan"),
-- and checks each customer against it. About as fast -- this time.

-- ---- 8.3 When NOT IN falls off a cliff ----
-- "Customers with no order in the second half of 2025" -- a churn
-- list. The subquery now returns about 970,000 rows: too many for the
-- hash table in work_mem (4 MB). Plain EXPLAIN, nothing runs:
EXPLAIN
SELECT count(*) FROM customers_big c
WHERE c.customerID NOT IN (SELECT o.customerID FROM orders_big o
                           WHERE o.orderDate >= '2025-07-01');
--                                        QUERY PLAN
-- Aggregate  (cost=3332822070.00..3332822070.01 rows=1 width=8)
--   ->  Seq Scan on customers_big c  (cost=0.00..3332822007.50 rows=25000 width=0)
--         Filter: (NOT (ANY (customerid = (SubPlan 1).col1)))
--         SubPlan 1
--           ->  Materialize  (cost=0.00..130885.50 rows=970928 width=4)
--                 ->  Seq Scan on orders_big o  (cost=0.00..122237.86 rows=970928 width=4)
--                       Filter: (orderdate >= '2025-07-01'::date)
-- "SubPlan" without "hashed": for EACH of the 50,000 customers, scan
-- the stored list of ~970,000 values until a match. Read the top
-- cost: over 3 billion. The NOT EXISTS version:
EXPLAIN
SELECT count(*) FROM customers_big c
WHERE NOT EXISTS (SELECT 1 FROM orders_big o
                  WHERE o.customerID = c.customerID AND o.orderDate >= '2025-07-01');
--                                                       QUERY PLAN
-- Aggregate  (cost=137001.60..137001.61 rows=1 width=8)
--   ->  Hash Right Anti Join  (cost=1931.29..136995.54 rows=2425 width=0)
--         Hash Cond: (o.customerid = c.customerid)
--         ->  Seq Scan on orders_big o  (cost=0.00..122237.86 rows=970928 width=4)
--               Filter: (orderdate >= '2025-07-01'::date)
--         ->  Hash  (cost=1306.29..1306.29 rows=50000 width=4)
--               ->  Index Only Scan using customers_big_pkey on customers_big c  (cost=0.29..1306.29 rows=50000 width=4)
-- About 137,000: over 20,000 times cheaper, by the planner's own
-- estimate. Don't run the NOT IN on all 50,000 customers -- it takes
-- minutes. On the first 100 customers only:
EXPLAIN ANALYZE
SELECT count(*) FROM customers_big c
WHERE c.customerID <= 100
  AND c.customerID NOT IN (SELECT o.customerID FROM orders_big o
                           WHERE o.orderDate >= '2025-07-01');
--                                                                         QUERY PLAN
-- Aggregate  (cost=6465678.24..6465678.25 rows=1 width=8) (actual time=781.279..781.280 rows=1.00 loops=1)
--   Buffers: shared hit=8689 read=51053, temp read=12639 written=1662
--   ->  Index Only Scan using customers_big_pkey on customers_big c  (cost=0.29..6465678.12 rows=48 width=0) (actual time=387.773..781.271 rows=4.00 loops=1)
--         Index Cond: (customerid <= 100)
--         Filter: (NOT (ANY (customerid = (SubPlan 1).col1)))
--         Rows Removed by Filter: 96
--         Heap Fetches: 0
--         Index Searches: 1
--         Buffers: shared hit=8689 read=51053, temp read=12639 written=1662
--         SubPlan 1
--           ->  Materialize  (cost=0.00..130885.50 rows=970928 width=4) (actual time=1.368..5.189 rows=83378.62 loops=100)
--                 Storage: Disk  Maximum Storage: 13292kB
--                 Buffers: shared hit=8686 read=51053, temp read=12639 written=1662
--                 ->  Seq Scan on orders_big o  (cost=0.00..122237.86 rows=970928 width=4) (actual time=136.713..191.597 rows=972188.00 loops=1)
--                       Filter: (orderdate >= '2025-07-01'::date)
--                       Rows Removed by Filter: 4027812
--                       Buffers: shared hit=8686 read=51053
-- Planning:
--   Buffers: shared hit=3
-- Planning Time: 0.037 ms
-- Execution Time: 782.526 ms
EXPLAIN ANALYZE
SELECT count(*) FROM customers_big c
WHERE NOT EXISTS (SELECT 1 FROM orders_big o
                  WHERE o.customerID = c.customerID AND o.orderDate >= '2025-07-01');
--                                                                               QUERY PLAN
-- Aggregate  (cost=137001.60..137001.61 rows=1 width=8) (actual time=247.446..247.448 rows=1.00 loops=1)
--   Buffers: shared hit=8919 read=50959
--   ->  Hash Right Anti Join  (cost=1931.29..136995.54 rows=2425 width=0) (actual time=246.846..247.387 rows=2000.00 loops=1)
--         Hash Cond: (o.customerid = c.customerid)
--         Buffers: shared hit=8919 read=50959
--         ->  Seq Scan on orders_big o  (cost=0.00..122237.86 rows=970928 width=4) (actual time=128.081..174.736 rows=972188.00 loops=1)
--               Filter: (orderdate >= '2025-07-01'::date)
--               Rows Removed by Filter: 4027812
--               Buffers: shared hit=8780 read=50959
--         ->  Hash  (cost=1306.29..1306.29 rows=50000 width=4) (actual time=4.600..4.601 rows=50000.00 loops=1)
--               Buckets: 65536  Batches: 1  Memory Usage: 2270kB
--               Buffers: shared hit=139
--               ->  Index Only Scan using customers_big_pkey on customers_big c  (cost=0.29..1306.29 rows=50000 width=4) (actual time=0.007..2.440 rows=50000.00 loops=1)
--                     Heap Fetches: 0
--                     Index Searches: 1
--                     Buffers: shared hit=139
-- Planning:
--   Buffers: shared hit=6
-- Planning Time: 0.107 ms
-- Execution Time: 247.469 ms
-- NOT EXISTS answers for ALL 50,000 customers in less time than NOT IN
-- needs for 100. Check the answer: 2,000 -- exactly the 2,000
-- customers who never ordered at all (Part 0: every 25th). Everyone
-- who ever ordered also ordered in late 2025.
-- Same data, same answer (no NULLs here) -- only the plan differs,
-- and only because of how the query was written. Two reasons now to
-- write NOT EXISTS: NULLs, and this cliff.

-- ---- 8.4 Top-N per group (Lecture 6, Part 4) ----
-- "Each customer's latest order", three ways. No index on customerID
-- yet. Method 1, row_number() in a CTE:
EXPLAIN (ANALYZE, BUFFERS)
WITH ranked AS (
    SELECT customerID, orderID, orderTotal,
           row_number() OVER (PARTITION BY customerID
                              ORDER BY orderDate DESC, orderID DESC) AS rn
    FROM orders_big
)
SELECT count(*), sum(orderTotal) FROM ranked WHERE rn = 1;
--                                                                    QUERY PLAN
-- Aggregate  (cost=1046265.54..1046265.55 rows=1 width=40) (actual time=1912.303..1912.304 rows=1.00 loops=1)
--   Buffers: shared hit=8880 read=50865, temp read=35432 written=35511
--   ->  Subquery Scan on ranked  (cost=871143.75..1046140.54 rows=25000 width=6) (actual time=1467.833..1909.453 rows=48000.00 loops=1)
--         Filter: (ranked.rn = 1)
--         Buffers: shared hit=8880 read=50865, temp read=35432 written=35511
--         ->  WindowAgg  (cost=871143.75..983641.68 rows=4999909 width=26) (actual time=1467.832..1907.196 rows=48000.00 loops=1)
--               Window: w1 AS (PARTITION BY orders_big.customerid ORDER BY orders_big.orderdate, orders_big.orderid ROWS UNBOUNDED PRECEDING)
--               Run Condition: (row_number() OVER w1 <= 1)
--               Storage: Memory  Maximum Storage: 17kB
--               Buffers: shared hit=8880 read=50865, temp read=35432 written=35511
--               ->  Sort  (cost=871143.72..883643.50 rows=4999909 width=18) (actual time=1467.824..1738.702 rows=5000000.00 loops=1)
--                     Sort Key: orders_big.customerid, orders_big.orderdate DESC, orders_big.orderid DESC
--                     Sort Method: external merge  Disk: 141760kB
--                     Buffers: shared hit=8880 read=50865, temp read=35432 written=35511
--                     ->  Seq Scan on orders_big  (cost=0.00..109738.09 rows=4999909 width=18) (actual time=0.140..313.628 rows=5000000.00 loops=1)
--                           Buffers: shared hit=8874 read=50865
-- Planning:
--   Buffers: shared hit=43
-- Planning Time: 0.093 ms
-- Execution Time: 1925.375 ms
-- Sort all 5 million rows by customer and date (on disk: "external
-- merge"), then number them. ("Run Condition", PostgreSQL 15+: the
-- WindowAgg stops numbering a customer after row 1.)
-- Method 3, DISTINCT ON -- the same sort, then keep the first per
-- customer. Saved, to compare with LATERAL below:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal)
FROM (SELECT DISTINCT ON (customerID) customerID, orderID, orderTotal
      FROM orders_big
      ORDER BY customerID, orderDate DESC, orderID DESC) AS t;
--                                                                 QUERY PLAN
-- Aggregate  (cost=896856.90..896856.91 rows=1 width=40) (actual time=2271.270..2271.272 rows=1.00 loops=1)
--   Buffers: shared hit=8968 read=50771, temp read=36712 written=36791
--   ->  Unique  (cost=871143.72..896143.27 rows=47575 width=18) (actual time=1703.650..2268.246 rows=48000.00 loops=1)
--         Buffers: shared hit=8968 read=50771, temp read=36712 written=36791
--         ->  Sort  (cost=871143.72..883643.50 rows=4999909 width=18) (actual time=1703.649..2115.676 rows=5000000.00 loops=1)
--               Sort Key: orders_big.customerid, orders_big.orderdate DESC, orders_big.orderid DESC
--               Sort Method: external merge  Disk: 146880kB
--               Buffers: shared hit=8968 read=50771, temp read=36712 written=36791
--               ->  Seq Scan on orders_big  (cost=0.00..109738.09 rows=4999909 width=18) (actual time=0.087..318.506 rows=5000000.00 loops=1)
--                     Buffers: shared hit=8968 read=50771
-- Planning Time: 0.047 ms
-- Execution Time: 2286.327 ms
CREATE TEMP TABLE latest_sorted AS
SELECT DISTINCT ON (customerID) customerID, orderID, orderTotal
FROM orders_big
ORDER BY customerID, orderDate DESC, orderID DESC;
-- Method 2, LATERAL ... LIMIT 1 -- plain EXPLAIN only:
EXPLAIN
SELECT count(*), sum(l.orderTotal)
FROM customers_big c
JOIN LATERAL (SELECT o.orderID, o.orderTotal
              FROM orders_big o
              WHERE o.customerID = c.customerID
              ORDER BY o.orderDate DESC, o.orderID DESC
              LIMIT 1) AS l ON true;
--                                                    QUERY PLAN
-- Aggregate  (cost=6111922056.29..6111922056.30 rows=1 width=40)
--   ->  Nested Loop  (cost=122238.68..6111921806.29 rows=50000 width=6)
--         ->  Index Only Scan using customers_big_pkey on customers_big c  (cost=0.29..1306.29 rows=50000 width=4)
--         ->  Limit  (cost=122238.39..122238.39 rows=1 width=14)
--               ->  Sort  (cost=122238.39..122238.65 rows=105 width=14)
--                     Sort Key: o.orderdate DESC, o.orderid DESC
--                     ->  Seq Scan on orders_big o  (cost=0.00..122237.86 rows=105 width=14)
--                           Filter: (customerid = c.customerid)
-- WITHOUT an index, LATERAL means: for each of 50,000 customers, scan
-- all 5 million orders. Cost: billions. Never run that.

-- Now an index that matches the question exactly: by customer, newest
-- first.
CREATE INDEX orders_big_cust_latest_idx ON orders_big (customerID, orderDate DESC, orderID DESC);
ANALYZE orders_big;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(l.orderTotal)
FROM customers_big c
JOIN LATERAL (SELECT o.orderID, o.orderTotal
              FROM orders_big o
              WHERE o.customerID = c.customerID
              ORDER BY o.orderDate DESC, o.orderID DESC
              LIMIT 1) AS l ON true;
--                                                                              QUERY PLAN
-- Aggregate  (cost=226978.31..226978.32 rows=1 width=40) (actual time=149.405..149.406 rows=1.00 loops=1)
--   Buffers: shared hit=178185 read=19954 written=36
--   ->  Nested Loop  (cost=0.72..226728.31 rows=50000 width=6) (actual time=0.024..146.318 rows=48000.00 loops=1)
--         Buffers: shared hit=178185 read=19954 written=36
--         ->  Index Only Scan using customers_big_pkey on customers_big c  (cost=0.29..1306.29 rows=50000 width=4) (actual time=0.009..2.920 rows=50000.00 loops=1)
--               Heap Fetches: 0
--               Index Searches: 1
--               Buffers: shared hit=139
--         ->  Limit  (cost=0.43..4.49 rows=1 width=14) (actual time=0.003..0.003 rows=0.96 loops=50000)
--               Buffers: shared hit=178046 read=19954 written=36
--               ->  Index Scan using orders_big_cust_latest_idx on orders_big o  (cost=0.43..422.25 rows=104 width=14) (actual time=0.003..0.003 rows=0.96 loops=50000)
--                     Index Cond: (customerid = c.customerid)
--                     Index Searches: 50000
--                     Buffers: shared hit=178046 read=19954 written=36
-- Planning:
--   Buffers: shared hit=29 read=1
-- Planning Time: 0.135 ms
-- Execution Time: 149.420 ms
-- 50,000 short index lookups, each stopping after one row (Limit,
-- loops=50000). The fastest of the three by far -- WITH this index.
CREATE TEMP TABLE latest_lateral AS
SELECT c.customerID, l.orderID, l.orderTotal
FROM customers_big c
JOIN LATERAL (SELECT o.orderID, o.orderTotal
              FROM orders_big o
              WHERE o.customerID = c.customerID
              ORDER BY o.orderDate DESC, o.orderID DESC
              LIMIT 1) AS l ON true;

-- The SURPRISE: the same index, given to DISTINCT ON.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal)
FROM (SELECT DISTINCT ON (customerID) customerID, orderID, orderTotal
      FROM orders_big
      ORDER BY customerID, orderDate DESC, orderID DESC) AS t;
--                                                                                QUERY PLAN
-- Aggregate  (cost=404091.48..404091.49 rows=1 width=40) (actual time=9775.743..9775.744 rows=1.00 loops=1)
--   Buffers: shared hit=1344170 read=3670546 written=1
--   ->  Unique  (cost=0.43..403370.44 rows=48069 width=18) (actual time=0.016..9767.333 rows=48000.00 loops=1)
--         Buffers: shared hit=1344170 read=3670546 written=1
--         ->  Index Scan using orders_big_cust_latest_idx on orders_big  (cost=0.43..390870.59 rows=4999941 width=18) (actual time=0.015..9615.212 rows=5000000.00 loops=1)
--               Index Searches: 1
--               Buffers: shared hit=1344170 read=3670546 written=1
-- Planning Time: 0.057 ms
-- Execution Time: 9775.768 ms
-- SLOWER than without the index. The planner dropped the Sort and
-- walks the whole index instead -- in customer order, so it jumps to
-- a different table page for almost every one of the 5 million rows.
-- Compare the Buffers line with the DISTINCT ON above: about 5
-- million page visits against about 60,000 pages plus a sort on disk.
-- The planner expected those pages to be in memory
-- (effective_cache_size says 4 GB); PostgreSQL's own cache is 128 MB.
-- row_number() gets the same plan:
EXPLAIN
WITH ranked AS (
    SELECT customerID, orderID, orderTotal,
           row_number() OVER (PARTITION BY customerID
                              ORDER BY orderDate DESC, orderID DESC) AS rn
    FROM orders_big
)
SELECT count(*), sum(orderTotal) FROM ranked WHERE rn = 1;
--                                                                 QUERY PLAN
-- Aggregate  (cost=553493.67..553493.68 rows=1 width=40)
--   ->  Subquery Scan on ranked  (cost=0.53..553368.67 rows=25000 width=6)
--         Filter: (ranked.rn = 1)
--         ->  WindowAgg  (cost=0.53..490869.41 rows=4999941 width=26)
--               Window: w1 AS (PARTITION BY orders_big.customerid ORDER BY orders_big.orderdate, orders_big.orderid ROWS UNBOUNDED PRECEDING)
--               Run Condition: (row_number() OVER w1 <= 1)
--               ->  Index Scan using orders_big_cust_latest_idx on orders_big  (cost=0.43..390870.59 rows=4999941 width=18)
-- So "which method is fastest" has no answer without "with which
-- index": LATERAL needs the index and is excellent with it; the
-- whole-table methods do better with a sort. Measure on your data.

-- Same answer, whatever the plan? LATERAL (with index) vs DISTINCT ON
-- (saved before the index), EXCEPT both ways:
SELECT (SELECT count(*) FROM latest_sorted)  AS rows_sorted,
       (SELECT count(*) FROM latest_lateral) AS rows_lateral,
       (SELECT count(*) FROM (SELECT * FROM latest_sorted EXCEPT SELECT * FROM latest_lateral) a) AS sorted_not_lateral,
       (SELECT count(*) FROM (SELECT * FROM latest_lateral EXCEPT SELECT * FROM latest_sorted) b) AS lateral_not_sorted;
-- rows_sorted | rows_lateral | sorted_not_lateral | lateral_not_sorted
--       48000 |        48000 |                  0 |                  0
-- 48,000 each (the inner JOIN LATERAL drops the 2,000 customers with
-- no orders, Lecture 6, 4.3), 0 and 0.
DROP INDEX orders_big_cust_latest_idx;
DROP TABLE latest_sorted, latest_lateral;

-- ---- 8.5 Join methods, in brief ----
CREATE INDEX orders_big_customerid_idx ON orders_big (customerID);
ANALYZE orders_big;

-- Nested Loop: few rows outside, an index inside.
EXPLAIN ANALYZE
SELECT o.orderID, o.orderTotal, c.city
FROM orders_big o
JOIN customers_big c ON c.customerID = o.customerID
WHERE o.orderID BETWEEN 1000001 AND 1000010;
--                                                                  QUERY PLAN
-- Nested Loop  (cost=0.72..91.71 rows=10 width=17) (actual time=0.025..0.080 rows=10.00 loops=1)
--   Buffers: shared hit=11 read=23
--   ->  Index Scan using orders_big_pkey on orders_big o  (cost=0.43..8.63 rows=10 width=14) (actual time=0.015..0.016 rows=10.00 loops=1)
--         Index Cond: ((orderid >= 1000001) AND (orderid <= 1000010))
--         Index Searches: 1
--         Buffers: shared read=4
--   ->  Index Scan using customers_big_pkey on customers_big c  (cost=0.29..8.31 rows=1 width=11) (actual time=0.006..0.006 rows=1.00 loops=10)
--         Index Cond: (customerid = o.customerid)
--         Index Searches: 10
--         Buffers: shared hit=11 read=19
-- Planning:
--   Buffers: shared hit=41 read=14
-- Planning Time: 0.218 ms
-- Execution Time: 0.092 ms
-- 10 orders; for each, one primary-key lookup in customers_big
-- (loops=10).

-- Hash Join: many rows, no useful order. Build a hash table on the
-- smaller side, stream the bigger one past it.
EXPLAIN ANALYZE
SELECT c.city, count(*) AS cancelled_orders
FROM orders_big o
JOIN customers_big c ON c.customerID = o.customerID
WHERE o.status = 'cancelled'
GROUP BY c.city;
--                                                                QUERY PLAN
-- HashAggregate  (cost=125368.98..125369.02 rows=4 width=15) (actual time=320.817..320.820 rows=4.00 loops=1)
--   Group Key: c.city
--   Batches: 1  Memory Usage: 32kB
--   Buffers: shared hit=15314 read=45245
--   ->  Hash Join  (cost=1945.00..124592.30 rows=155335 width=7) (actual time=7.288..306.405 rows=159902.00 loops=1)
--         Hash Cond: (o.customerid = c.customerid)
--         Buffers: shared hit=15314 read=45245
--         ->  Seq Scan on orders_big o  (cost=0.00..122239.51 rows=155335 width=4) (actual time=0.006..268.277 rows=159902.00 loops=1)
--               Filter: ((status)::text = 'cancelled'::text)
--               Rows Removed by Filter: 4840098
--               Buffers: shared hit=15304 read=44435
--         ->  Hash  (cost=1320.00..1320.00 rows=50000 width=11) (actual time=7.253..7.254 rows=50000.00 loops=1)
--               Buckets: 65536  Batches: 1  Memory Usage: 2681kB
--               Buffers: shared hit=10 read=810
--               ->  Seq Scan on customers_big c  (cost=0.00..1320.00 rows=50000 width=11) (actual time=0.141..3.525 rows=50000.00 loops=1)
--                     Buffers: shared hit=10 read=810
-- Planning:
--   Buffers: shared hit=17
-- Planning Time: 0.082 ms
-- Execution Time: 320.845 ms

-- Merge Join: both sides already sorted on the join key -- here both
-- come out of an index in customerID order -- so walk them side by
-- side, like merging two sorted lists.
EXPLAIN ANALYZE
SELECT c.customerID, c.city, t.orders
FROM customers_big c
JOIN (SELECT customerID, count(*) AS orders FROM orders_big GROUP BY customerID) AS t
  ON t.customerID = c.customerID
ORDER BY c.customerID;
--                                                                                 QUERY PLAN
-- Merge Join  (cost=0.72..121240.76 rows=47545 width=19) (actual time=0.028..372.609 rows=48000.00 loops=1)
--   Merge Cond: (c.customerid = orders_big.customerid)
--   Buffers: shared hit=96838 read=4466
--   ->  Index Scan using customers_big_pkey on customers_big c  (cost=0.29..2129.29 rows=50000 width=11) (actual time=0.006..4.450 rows=50000.00 loops=1)
--         Index Searches: 1
--         Buffers: shared hit=834 read=126
--   ->  GroupAggregate  (cost=0.43..117916.70 rows=47545 width=12) (actual time=0.019..361.569 rows=48000.00 loops=1)
--         Group Key: orders_big.customerid
--         Buffers: shared hit=96004 read=4340
--         ->  Index Only Scan using orders_big_customerid_idx on orders_big  (cost=0.43..92441.05 rows=5000041 width=4) (actual time=0.006..189.455 rows=5000000.00 loops=1)
--               Heap Fetches: 0
--               Index Searches: 1
--               Buffers: shared hit=96004 read=4340
-- Planning Time: 0.097 ms
-- Execution Time: 373.641 ms
-- You don't choose the join method; the planner does, from the
-- estimated row counts (Part 3) and the indexes available. Read which
-- one it picked, and check its row estimates.

-- Clean up: leave orders_big with its primary key only.
DROP INDEX orders_big_customerid_idx;



-- ============================================================
-- Lecture 7 — Part 9: Partitioning
-- Run after Part 8.
--
-- A partitioned table is ONE table to your queries, stored as several
-- physical tables (partitions), each holding the rows for one range or
-- list of values of the PARTITION KEY. Here: one partition per year of
-- orderDate. Queries see one table; the planner skips the partitions a
-- query can't need ("partition pruning").
-- ============================================================

-- Start clean (in case you ran this Part before).
DROP TABLE IF EXISTS orders_big_part, orders_big_daily;

-- ---- 9.1 Build it: same columns, same rows, by year ----
-- PARTITION BY RANGE (orderDate): each partition takes a range of
-- dates, FROM inclusive TO exclusive. (Two other kinds: PARTITION BY
-- LIST (channel) -- one partition per listed value; PARTITION BY HASH
-- (customerID) -- rows spread evenly over N partitions by a hash of
-- the key.)
CREATE TABLE orders_big_part (LIKE orders_big INCLUDING DEFAULTS INCLUDING CONSTRAINTS)
    PARTITION BY RANGE (orderDate);
CREATE TABLE orders_big_part_2023 PARTITION OF orders_big_part
    FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');
CREATE TABLE orders_big_part_2024 PARTITION OF orders_big_part
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE orders_big_part_2025 PARTITION OF orders_big_part
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');

-- Insert into the parent; each row goes to its partition by itself.
INSERT INTO orders_big_part SELECT * FROM orders_big;
VACUUM ANALYZE orders_big_part;

-- Where did the rows go? tableoid is the physical table a row lives in.
SELECT tableoid::regclass AS partition, count(*) AS rows
FROM orders_big_part
GROUP BY tableoid
ORDER BY partition;
--      partition       |  rows
-- orders_big_part_2023 | 1371464
-- orders_big_part_2024 | 1733359
-- orders_big_part_2025 | 1895177
SELECT (SELECT count(*) FROM orders_big_part) AS partitioned,
       (SELECT count(*) FROM orders_big)      AS unpartitioned;
-- partitioned | unpartitioned
--     5000000 |       5000000
-- 1,371,464 + 1,733,359 + 1,895,177 = 5,000,000.

-- ---- 9.2 Same data? Prove it before trusting it ----
-- Month by month, orders and revenue from both tables, EXCEPT both ways:
WITH a AS (SELECT date_trunc('month', orderDate) AS month, count(*) AS n, sum(orderTotal) AS revenue
           FROM orders_big GROUP BY 1),
     b AS (SELECT date_trunc('month', orderDate) AS month, count(*) AS n, sum(orderTotal) AS revenue
           FROM orders_big_part GROUP BY 1)
SELECT (SELECT count(*) FROM a) AS months,
       (SELECT count(*) FROM (SELECT * FROM a EXCEPT SELECT * FROM b) x) AS big_not_part,
       (SELECT count(*) FROM (SELECT * FROM b EXCEPT SELECT * FROM a) y) AS part_not_big;
-- months | big_not_part | part_not_big
--     36 |            0 |            0
-- 36 months, 0 and 0.

-- ---- 9.3 Partition pruning ----
-- June 2025, from both tables (neither has an index on orderDate):
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big
WHERE orderDate >= '2025-06-01' AND orderDate < '2025-07-01';
--                                                           QUERY PLAN
-- Aggregate  (cost=135467.47..135467.48 rows=1 width=40) (actual time=186.128..186.129 rows=1.00 loops=1)
--   Buffers: shared hit=188 read=59551 written=20
--   ->  Seq Scan on orders_big  (cost=0.00..134739.61 rows=145570 width=6) (actual time=138.048..174.889 rows=155419.00 loops=1)
--         Filter: ((orderdate >= '2025-06-01'::date) AND (orderdate < '2025-07-01'::date))
--         Rows Removed by Filter: 4844581
--         Buffers: shared hit=188 read=59551 written=20
-- Planning:
--   Buffers: shared hit=3
-- Planning Time: 0.062 ms
-- Execution Time: 186.145 ms
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big_part
WHERE orderDate >= '2025-06-01' AND orderDate < '2025-07-01';
--                                                                      QUERY PLAN
-- Aggregate  (cost=51832.98..51832.99 rows=1 width=40) (actual time=83.022..83.023 rows=1.00 loops=1)
--   Buffers: shared hit=15342 read=7301
--   ->  Seq Scan on orders_big_part_2025 orders_big_part  (cost=0.00..51070.65 rows=152464 width=6) (actual time=33.904..74.987 rows=155419.00 loops=1)
--         Filter: ((orderdate >= '2025-06-01'::date) AND (orderdate < '2025-07-01'::date))
--         Rows Removed by Filter: 1739758
--         Buffers: shared hit=15342 read=7301
-- Planning:
--   Buffers: shared hit=18 read=2
-- Planning Time: 0.174 ms
-- Execution Time: 83.040 ms
-- One partition in the plan: orders_big_part_2025. 2023 and 2024
-- aren't there at all -- the planner proved from the partition bounds
-- that they can't hold June 2025. About 38% of the pages, same answer.

-- ---- 9.4 THE TRAP: a filter the planner can't prune with ----
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big_part
WHERE extract(year FROM orderDate) = 2025;
--                                                                          QUERY PLAN
-- Aggregate  (cost=134989.00..134989.01 rows=1 width=40) (actual time=680.679..680.684 rows=1.00 loops=1)
--   Buffers: shared hit=15723 read=44016 written=5
--   ->  Append  (cost=0.00..134864.00 rows=25000 width=6) (actual time=271.545..583.674 rows=1895177.00 loops=1)
--         Buffers: shared hit=15723 read=44016 written=5
--         ->  Seq Scan on orders_big_part_2023 orders_big_part_1  (cost=0.00..36956.96 rows=6857 width=6) (actual time=119.229..119.230 rows=0.00 loops=1)
--               Filter: (EXTRACT(year FROM orderdate) = '2025'::numeric)
--               Rows Removed by Filter: 1371464
--               Buffers: shared hit=185 read=16200 written=5
--         ->  Seq Scan on orders_big_part_2024 orders_big_part_2  (cost=0.00..46711.38 rows=8667 width=6) (actual time=152.289..152.290 rows=0.00 loops=1)
--               Filter: (EXTRACT(year FROM orderdate) = '2025'::numeric)
--               Rows Removed by Filter: 1733359
--               Buffers: shared hit=188 read=20523
--         ->  Seq Scan on orders_big_part_2025 orders_big_part_3  (cost=0.00..51070.65 rows=9476 width=6) (actual time=0.023..246.265 rows=1895177.00 loops=1)
--               Filter: (EXTRACT(year FROM orderdate) = '2025'::numeric)
--               Buffers: shared hit=15350 read=7293
-- Planning Time: 0.137 ms
-- Execution Time: 680.707 ms
-- WRONG PLAN: all three partitions (Append with three Seq Scans). The
-- 2023 and 2024 scans return 0 rows -- after reading every page. The
-- bounds are on orderDate, not on extract(year FROM orderDate) (Part
-- 7.1 again). FIX: a range on the key itself.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big_part
WHERE orderDate >= '2025-01-01' AND orderDate < '2026-01-01';
--                                                                       QUERY PLAN
-- Aggregate  (cost=60544.69..60544.70 rows=1 width=40) (actual time=252.787..252.788 rows=1.00 loops=1)
--   Buffers: shared hit=15444 read=7199 written=2
--   ->  Seq Scan on orders_big_part_2025 orders_big_part  (cost=0.00..51070.65 rows=1894807 width=6) (actual time=0.291..153.631 rows=1895177.00 loops=1)
--         Filter: ((orderdate >= '2025-01-01'::date) AND (orderdate < '2026-01-01'::date))
--         Buffers: shared hit=15444 read=7199 written=2
-- Planning Time: 0.182 ms
-- Execution Time: 252.805 ms
-- One partition. And with no filter on orderDate at all -- "Nane's
-- orders" -- every partition, every time:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_big_part WHERE customerID = 4242;
--                                                                      QUERY PLAN
-- Aggregate  (cost=122239.79..122239.80 rows=1 width=8) (actual time=142.261..142.262 rows=1.00 loops=1)
--   Buffers: shared hit=15914 read=43825
--   ->  Append  (cost=0.00..122239.52 rows=105 width=0) (actual time=2.517..142.245 rows=97.00 loops=1)
--         Buffers: shared hit=15914 read=43825
--         ->  Seq Scan on orders_big_part_2023 orders_big_part_1  (cost=0.00..33528.30 rows=29 width=0) (actual time=2.516..39.619 rows=17.00 loops=1)
--               Filter: (customerid = 4242)
--               Rows Removed by Filter: 1371447
--               Buffers: shared hit=188 read=16197
--         ->  Seq Scan on orders_big_part_2024 orders_big_part_2  (cost=0.00..42377.99 rows=36 width=0) (actual time=0.744..49.153 rows=37.00 loops=1)
--               Filter: (customerid = 4242)
--               Rows Removed by Filter: 1733322
--               Buffers: shared hit=188 read=20523
--         ->  Seq Scan on orders_big_part_2025 orders_big_part_3  (cost=0.00..46332.71 rows=40 width=0) (actual time=2.566..53.459 rows=43.00 loops=1)
--               Filter: (customerid = 4242)
--               Rows Removed by Filter: 1895134
--               Buffers: shared hit=15538 read=7105
-- Planning:
--   Buffers: shared hit=8 read=1 dirtied=1
-- Planning Time: 0.260 ms
-- Execution Time: 142.281 ms
-- Partitioning by date helps only queries that filter on date.

-- ---- 9.5 THE TRAP: a row with no partition ----
-- An order dated 2026 arrives (or a typo: 2205 instead of 2025).
-- Error on purpose:
INSERT INTO orders_big_part VALUES
    (5000001, 4242, NULL, '2026-01-02', '10:00', 'online', 'card', 'completed', NULL, NULL, 99.00);
-- ERROR:  no partition of relation "orders_big_part" found for row
-- DETAIL:  Partition key of the failing row contains (orderdate) = (2026-01-02).
-- A loud error -- the good kind. The usual "fix" is a DEFAULT
-- partition, which takes every row that fits nowhere else:
CREATE TABLE orders_big_part_default PARTITION OF orders_big_part DEFAULT;
INSERT INTO orders_big_part VALUES
    (5000001, 4242, NULL, '2026-01-02', '10:00', 'online', 'card', 'completed', NULL, NULL, 99.00);
SELECT tableoid::regclass AS partition, orderID, orderDate
FROM orders_big_part
WHERE orderID = 5000001;
--        partition        | orderid | orderdate
-- orders_big_part_default | 5000001 | 2026-01-02
-- Accepted, silently, into orders_big_part_default. Every wrong date
-- will collect there now, without a word. And when 2026 comes and you
-- add its partition -- error on purpose:
CREATE TABLE orders_big_part_2026 PARTITION OF orders_big_part
    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
-- ERROR:  updated partition constraint for default partition "orders_big_part_default" would be violated by some row
-- The default partition already holds a 2026 row, so the new partition
-- can't be created. FIX: create partitions BEFORE their data arrives,
-- and keep the default partition empty (count it in a daily check).
-- To repair this one: take the row out, add the partition, put it back.
DELETE FROM orders_big_part WHERE orderID = 5000001;
CREATE TABLE orders_big_part_2026 PARTITION OF orders_big_part
    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
INSERT INTO orders_big_part VALUES
    (5000001, 4242, NULL, '2026-01-02', '10:00', 'online', 'card', 'completed', NULL, NULL, 99.00);
SELECT tableoid::regclass AS partition, orderID, orderDate
FROM orders_big_part
WHERE orderID = 5000001;
--      partition       | orderid | orderdate
-- orders_big_part_2026 | 5000001 | 2026-01-02

-- ---- 9.6 THE TRAP: unique means unique per partition ----
-- orders_big has PRIMARY KEY (orderID). Error on purpose:
ALTER TABLE orders_big_part ADD PRIMARY KEY (orderID);
-- ERROR:  unique constraint on partitioned table must include all partitioning columns
-- DETAIL:  PRIMARY KEY constraint on table "orders_big_part" lacks column "orderdate" which is part of the partition key.
-- Each partition can check uniqueness only inside itself, so a unique
-- constraint must contain the partition key. The accepted version:
ALTER TABLE orders_big_part ADD PRIMARY KEY (orderID, orderDate);
-- Now the same orderID with a different date. Predict, then run:
INSERT INTO orders_big_part VALUES
    (5000001, 4242, NULL, '2025-12-31', '10:00', 'online', 'card', 'completed', NULL, NULL, 99.00);
SELECT tableoid::regclass AS partition, orderID, orderDate
FROM orders_big_part
WHERE orderID = 5000001
ORDER BY orderDate;
--      partition       | orderid | orderdate
-- orders_big_part_2025 | 5000001 | 2025-12-31
-- orders_big_part_2026 | 5000001 | 2026-01-02
-- WRONG: two orders numbered 5000001, and the "primary key" allowed
-- it: (5000001, 2025-12-31) and (5000001, 2026-01-02) are different
-- pairs. No error. PostgreSQL has no index that spans partitions, so
-- it can't promise orderID is unique across them. FIX: generate
-- orderIDs from one sequence (an IDENTITY column) so duplicates can't
-- be made -- and check: count(*) = count(DISTINCT orderID).
SELECT count(*) AS rows, count(DISTINCT orderID) AS distinct_ids FROM orders_big_part;
--  rows   | distinct_ids
-- 5000002 |      5000001
DELETE FROM orders_big_part WHERE orderID = 5000001;
DROP TABLE orders_big_part_2026, orders_big_part_default;

-- ---- 9.7 Too many tiny partitions ----
-- The same 5 million rows, one partition PER DAY: 1,096 partitions.
CREATE TABLE orders_big_daily (LIKE orders_big) PARTITION BY RANGE (orderDate);
DO $$
DECLARE d date;
BEGIN
    FOR d IN SELECT generate_series(DATE '2023-01-01', DATE '2025-12-31', INTERVAL '1 day')::date LOOP
        EXECUTE format('CREATE TABLE orders_big_daily_%s PARTITION OF orders_big_daily FOR VALUES FROM (%L) TO (%L)',
                       to_char(d, 'YYYYMMDD'), d, d + 1);
    END LOOP;
END $$;
INSERT INTO orders_big_daily SELECT * FROM orders_big;
VACUUM ANALYZE orders_big_daily;
SELECT count(*) AS partitions FROM pg_inherits WHERE inhparent = 'orders_big_daily'::regclass;
-- partitions
--       1096

-- One day, where daily partitions should shine:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(orderTotal) FROM orders_big_daily WHERE orderDate = '2025-06-15';
--                                                                     QUERY PLAN
-- Aggregate  (cost=152.65..152.66 rows=1 width=40) (actual time=0.662..0.662 rows=1.00 loops=1)
--   Buffers: shared hit=58 read=4
--   ->  Seq Scan on orders_big_daily_20250615 orders_big_daily  (cost=0.00..126.75 rows=5180 width=6) (actual time=0.064..0.427 rows=5180.00 loops=1)
--         Filter: (orderdate = '2025-06-15'::date)
--         Buffers: shared hit=58 read=4
-- Planning:
--   Buffers: shared hit=42 read=10
-- Planning Time: 1.497 ms
-- Execution Time: 0.675 ms
-- One partition of 1,096, a few dozen pages. Good.
-- Now Nane's orders, no date filter -- daily vs yearly:
EXPLAIN (ANALYZE, BUFFERS, SUMMARY)
SELECT count(*), sum(orderTotal) FROM orders_big_daily WHERE customerID = 4242;
--                                                                        QUERY PLAN
-- Aggregate  (cost=122775.01..122775.02 rows=1 width=40) (actual time=260.008..260.134 rows=1.00 loops=1)
--   Buffers: shared read=60264 written=11758
--   ->  Append  (cost=0.00..122769.51 rows=1101 width=6) (actual time=4.209..260.067 rows=97.00 loops=1)
-- ...   (4385 more lines)
-- Planning:
--   Buffers: shared hit=8768 dirtied=748
-- Planning Time: 12.810 ms
-- Execution Time: 261.375 ms
EXPLAIN (ANALYZE, BUFFERS, SUMMARY)
SELECT count(*), sum(orderTotal) FROM orders_big_part WHERE customerID = 4242;
--                                                                      QUERY PLAN
-- Aggregate  (cost=122242.10..122242.11 rows=1 width=40) (actual time=128.483..128.486 rows=1.00 loops=1)
--   Buffers: shared read=59740 dirtied=1
--   ->  Append  (cost=0.00..122241.57 rows=105 width=6) (actual time=1.761..128.463 rows=97.00 loops=1)
-- ...   (13 more lines)
-- Planning:
--   Buffers: shared hit=139 read=32 dirtied=2
-- Planning Time: 0.403 ms
-- Execution Time: 128.506 ms
-- With 1,096 partitions, a query that can't prune plans 1,096 scans
-- (the plan is thousands of lines long) and runs them one after
-- another. Planning Time and Execution Time are both several times
-- the yearly table's (notes Part 9 for the medians). What we measured,
-- not a law: here, daily partitions made the one-day query faster and
-- the query without a date filter slower. Choose partitions that match how you
-- filter, and keep their number modest.
DROP TABLE orders_big_daily;

-- ---- 9.8 Deleting old data: DROP a partition ----
-- "Delete everything from 2023" on the plain table -- measured inside
-- a transaction that we roll back (Part 1.6), so nothing is lost:
BEGIN;
EXPLAIN (ANALYZE, BUFFERS)
DELETE FROM orders_big WHERE orderDate < '2024-01-01';
--                                                           QUERY PLAN
-- Delete on orders_big  (cost=0.00..122239.51 rows=0 width=0) (actual time=625.643..625.643 rows=0.00 loops=1)
--   Buffers: shared hit=1387848 read=59740 dirtied=16386 written=2616
--   ->  Seq Scan on orders_big  (cost=0.00..122239.51 rows=1384928 width=6) (actual time=8.776..232.446 rows=1371464.00 loops=1)
--         Filter: (orderdate < '2024-01-01'::date)
--         Rows Removed by Filter: 3628536
--         Buffers: shared read=59739 written=2616
-- Planning:
--   Buffers: shared hit=87 read=8
-- Planning Time: 0.129 ms
-- Execution Time: 625.706 ms
ROLLBACK;
-- 1,371,464 rows deleted one by one: every page of 2023 is visited
-- and changed, and a real DELETE leaves dead rows for VACUUM to clean
-- up afterwards. Even rolled back, it left work behind: the deleted
-- rows' pages lost their "all-visible" mark (Part 4.5), so we VACUUM
-- to put orders_big back the way it was. ROLLBACK undoes the data,
-- not the work.
VACUUM orders_big;
-- On the partitioned table, the same deletion is a catalog change:
DROP TABLE orders_big_part_2023;
SELECT tableoid::regclass AS partition, count(*) AS rows
FROM orders_big_part
GROUP BY tableoid
ORDER BY partition;
--      partition       |  rows
-- orders_big_part_2024 | 1733359
-- orders_big_part_2025 | 1895177
-- 2023 is gone: no rows deleted one by one, no VACUUM needed. This
-- is the main reason large time-based tables are partitioned. (ALTER
-- TABLE ... DETACH PARTITION keeps the old year as a table of its own
-- -- to archive it first.)
SELECT count(*) AS rows_left FROM orders_big_part;
-- rows_left
--   3628536
-- 1,733,359 + 1,895,177. And orders_big still has its 5,000,000:
SELECT count(*) AS orders_big_rows FROM orders_big;
-- orders_big_rows
--         5000000

-- ---- 9.9 The same idea, next lectures ----
-- Parquet files and lakehouse tables (next lectures) partition by
-- folder: .../orderDate_year=2025/part-0.parquet. A query engine
-- skips the folders a filter rules out -- the same pruning, with the
-- same trap: filter on the partition column itself, or it reads
-- everything.
DROP TABLE orders_big_part;



-- ============================================================
-- Lecture 7 — Part 10: The decision rule
-- Run after Part 9.
--
-- Index, partition, or neither? The rule itself is in the notes
-- (Part 10.1). One check belongs here, because it's the silent failure
-- nobody looks for: an index that exists, takes space, slows every
-- write -- and is never used.
-- ============================================================

-- Start clean (in case you ran this Part before).
DROP INDEX IF EXISTS orders_big_orderdate_idx;

-- ---- 10.2 The index nobody uses ----
-- Someone adds an index "for the monthly report":
CREATE INDEX orders_big_orderdate_idx ON orders_big (orderDate);
ANALYZE orders_big;
-- The report, as the reporting tool writes it -- for two months:
SELECT count(*) AS orders, sum(orderTotal) AS revenue
FROM orders_big WHERE date_trunc('month', orderDate) = '2025-11-01';
-- orders |   revenue
-- 159799 | 102460853.62
SELECT count(*) AS orders, sum(orderTotal) AS revenue
FROM orders_big WHERE date_trunc('month', orderDate) = '2025-12-01';
-- orders |   revenue
-- 165962 | 106307167.25
-- Part 7.1's trap: a function on the column, so a Seq Scan, every
-- month. The index is never touched -- and nothing tells you.

-- PostgreSQL counts every use of every index, in pg_stat_user_indexes.
-- (A statement's counts reach the view up to a second after it ends;
-- the pause makes sure they're in.)
SELECT pg_sleep(1.5);
SELECT indexrelname AS index, idx_scan AS times_used,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE indexrelname = 'orders_big_orderdate_idx';
--          index           | times_used | size
-- orders_big_orderdate_idx |          0 | 34 MB
-- Used 0 times, 34 MB, and every INSERT pays for it (Part 5.4).

-- Fix the report (Part 7.1, FIX 1) and look again:
SELECT count(*) AS orders, sum(orderTotal) AS revenue
FROM orders_big WHERE orderDate >= '2025-12-01' AND orderDate < '2026-01-01';
-- orders |   revenue
-- 165962 | 106307167.25
SELECT pg_sleep(1.5);
SELECT indexrelname AS index, idx_scan AS times_used,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE indexrelname = 'orders_big_orderdate_idx';
--          index           | times_used | size
-- orders_big_orderdate_idx |          2 | 34 MB
-- Same December numbers, and now the index is used. On a real
-- database, look at this view after a few weeks of normal traffic. An
-- index still at 0 means either the queries can't use it (fix them) or
-- nobody needs it (drop it) -- but never drop the index behind a
-- PRIMARY KEY or UNIQUE constraint: it enforces a rule even if no
-- query reads it. The counts start from the last statistics reset
-- (pg_stat_reset), not from the beginning of time.
SELECT indexrelname AS index, idx_scan AS times_used,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE relname IN ('orders_big', 'customers_big')
ORDER BY indexrelname;
--          index           | times_used |  size
-- customers_big_email_key  |          1 | 3224 kB
-- customers_big_pkey       |     200039 | 1112 kB
-- orders_big_orderdate_idx |          2 | 34 MB
-- orders_big_pkey          |         11 | 111 MB
-- (All indexes on the two big tables. The primary keys' counts depend
-- on everything you ran before, so yours will differ.)
DROP INDEX orders_big_orderdate_idx;
