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
