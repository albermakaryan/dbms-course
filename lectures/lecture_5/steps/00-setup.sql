-- ============================================================
-- Lecture 5 — Part 0: load the data
--
-- Lecture 4's shop, with one change: an order can now hold SEVERAL
-- products, the way a real shopping cart does. Creates FIVE tables:
--
--   customers    \
--   employees     |  the same as Lecture 4 (employees with the same
--   products     /   managerID reporting line)
--   orders        one row per ORDER -- the header: who bought, when,
--                 where, status, and the order's total. No product
--                 columns any more.
--   order_items   one row per PRODUCT IN AN ORDER -- the lines: which
--                 product, how many, at what price. Primary key
--                 (orderID, productID): a product appears once per order.
--
-- The data comes from generate_data.py: every Lecture 4 order keeps its
-- product as its first line, and 235 of the 600 orders got 1-3 more
-- lines (965 lines in all). orderTotal is the sum of the order's lines,
-- so totals and revenue are higher than in Lecture 4. Everything else
-- you know still holds: 600 orders, Levon and Astghik never ordered,
-- Ergonomic Chair Pro never sold, 181 online orders with no employee.
-- (Lecture 4's flat sales table isn't needed and isn't loaded.)
--
-- Creates the lecture05 database too, if it doesn't exist yet, and
-- connects to it -- so you can start psql in ANY database:
--
-- \copy resolves paths relative to where you STARTED psql, so run
-- this from the lecture_5/ folder:    psql postgres
--                                     \i steps/00-setup.sql
-- Safe to re-run: drops and recreates every table, including Lecture
-- 4's tables if they're in the same database.
-- ============================================================

-- ---- The database: create it only if it's missing ----
-- Postgres has no CREATE DATABASE IF NOT EXISTS. Instead, this SELECT
-- produces the text of a CREATE DATABASE statement only when no
-- database called lecture05 exists, and \gexec runs whatever text the
-- SELECT produced: one statement the first time, nothing after that.
-- SELECT 'CREATE DATABASE lecture05'
-- WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'lecture05')\gexec
DROP DATABASE IF EXISTS lecture05;
CREATE DATABASE lecture05;

\c lecture05

-- Also drops Lecture 4's tables (sales, the star schema), in case
-- you're reusing that database, so this stays the reset button.
DROP TABLE IF EXISTS fact_sales, dim_date, dim_customer, dim_product, dim_employee,
                     order_items, sales, orders, customers, employees, products;

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

-- Collect table statistics now instead of waiting for autovacuum. The
-- planner picks join methods from these numbers, and Part 5.4 shows a
-- result whose row ORDER depends on the join method -- with fresh
-- statistics everyone gets the same plan, and the same wrong order.
ANALYZE;

-- Expect 30 / 8 / 37 / 600 / 965
SELECT 'customers' AS t, count(*) FROM customers
UNION ALL SELECT 'employees',   count(*) FROM employees
UNION ALL SELECT 'products',    count(*) FROM products
UNION ALL SELECT 'orders',      count(*) FROM orders
UNION ALL SELECT 'order_items', count(*) FROM order_items;
