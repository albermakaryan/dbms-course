-- ============================================================
-- Lecture 2 — From One File to Four Tables
-- YSU, Data Science for Business
--
-- Building the exact schema from the Lecture 1 slide:
--   Customers(customerID, firstName, lastName, birthDate, moneySpent, anniversary)
--   Employees(employeeID, firstName, lastName, birthDate)
--   Products (productID, category, price)
--   Orders   (orderID, customerID, employeeID, productID, orderTotal, orderDate)
--
-- Run this whole script at once, or run each part separately from
-- steps/00-create-database.sql through steps/09-alter-and-drop.sql
-- (numbered to match the Parts in lecture-02-notes.md).
-- ============================================================


-- ------------------------------------------------------------
-- STEP 0.  One wide, flat file.  42 rows, 13 columns.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sales_raw (
    orderID              INT,
    orderDate            DATE,
    customerFirstName    VARCHAR(50),
    customerLastName     VARCHAR(50),
    customerBirthDate    DATE,
    customerMoneySpent   DECIMAL(10,2),
    customerAnniversary  DATE,
    employeeFirstName    VARCHAR(50),
    employeeLastName     VARCHAR(50),
    employeeBirthDate    DATE,
    productCategory      VARCHAR(100),
    productPrice         DECIMAL(8,2),
    orderTotal           DECIMAL(10,2)
);

-- Safe to re-run: clear out any previous load first.
TRUNCATE TABLE sales_raw;

-- \copy runs on YOUR machine (psql).  COPY runs on the server.
-- Path is relative to wherever you started psql -- run it from
-- the lecture_2/ folder (the one containing this script).
\copy sales_raw FROM 'data/sales_flat.csv' WITH (FORMAT csv, HEADER true);

SELECT * FROM sales_raw ORDER BY orderDate, orderID LIMIT 10;


-- ------------------------------------------------------------
-- STEP 1.  Find the problem.  (Ask the room BEFORE running.)
-- ------------------------------------------------------------
SELECT count(*)                         AS total_rows     FROM sales_raw;  -- 42
SELECT count(DISTINCT customerLastName) AS real_customers FROM sales_raw;  -- 8
SELECT count(DISTINCT productCategory)  AS real_products  FROM sales_raw;  -- 6

-- 42 rows, but 8 customers.  Davit's birth date is stored eight times.

SELECT customerFirstName, customerLastName, count(*) AS times_stored
FROM sales_raw
GROUP BY customerFirstName, customerLastName
ORDER BY times_stored DESC;

-- What goes wrong:
--   * a wrong birth date -> fix EVERY copy            (update anomaly)
--   * miss one copy      -> two "truths"              (INCONSISTENCY)
--   * new category, no sales yet -> nowhere to put it (insertion anomaly)
--   * delete the last order in a category -> category gone (deletion anomaly)


-- ------------------------------------------------------------
-- STEP 2.  Design.  One table per real-world THING.
-- ------------------------------------------------------------
-- Customers, Employees, Products are ENTITIES.  An Order is an EVENT.
--
-- Question for the room: what identifies a customer?
--   no email, no phone -- only names and a birth date.
--   firstName?                     no
--   firstName + lastName?          two people can share a name
--   firstName + lastName + birth?  probably unique -> COMPOSITE NATURAL KEY
--   ...but fragile: 3 columns to carry everywhere, any typo breaks the link.
-- So we invent customerID: a SURROGATE key.  One integer.  Never changes.


-- ------------------------------------------------------------
-- STEP 3.  CREATE the tables (DDL).
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS customers (
    customerID   SERIAL PRIMARY KEY,
    firstName    VARCHAR(50) NOT NULL,
    lastName     VARCHAR(50) NOT NULL,
    birthDate    DATE,
    moneySpent   DECIMAL(10,2) DEFAULT 0 CHECK (moneySpent >= 0),
    anniversary  DATE
);

CREATE TABLE IF NOT EXISTS employees (
    employeeID   SERIAL PRIMARY KEY,
    firstName    VARCHAR(50) NOT NULL,
    lastName     VARCHAR(50) NOT NULL,
    birthDate    DATE
);

CREATE TABLE IF NOT EXISTS products (
    productID    SERIAL PRIMARY KEY,
    category     VARCHAR(100) NOT NULL UNIQUE,
    price        DECIMAL(8,2) NOT NULL CHECK (price >= 0)
);

CREATE TABLE IF NOT EXISTS orders (
    orderID      INT PRIMARY KEY,
    customerID   INT NOT NULL REFERENCES customers(customerID),
    employeeID   INT NOT NULL REFERENCES employees(employeeID),
    productID    INT NOT NULL REFERENCES products(productID),
    orderTotal   DECIMAL(10,2) NOT NULL CHECK (orderTotal >= 0),
    orderDate    DATE NOT NULL
);

-- Note what is NOT in orders: no names, no category text, no price.
-- Only references.  REFERENCES = foreign key = referential integrity.
-- This is the schema slide's "Business Impact" line, made real.


-- ------------------------------------------------------------
-- STEP 4.  Fill them (DML).  Parents first, children last.
-- ------------------------------------------------------------
-- Safe to re-run: clear out any previous run of this step first.
TRUNCATE TABLE orders, customers, employees, products RESTART IDENTITY;

INSERT INTO customers (firstName, lastName, birthDate, moneySpent, anniversary)
SELECT DISTINCT customerFirstName, customerLastName, customerBirthDate,
                customerMoneySpent, customerAnniversary
FROM sales_raw;

INSERT INTO employees (firstName, lastName, birthDate)
SELECT DISTINCT employeeFirstName, employeeLastName, employeeBirthDate
FROM sales_raw;

INSERT INTO products (category, price)
SELECT DISTINCT productCategory, productPrice
FROM sales_raw;

-- Orders: translate names/categories into the new id numbers.
-- The customer join needs all THREE natural-key columns.
INSERT INTO orders (orderID, customerID, employeeID, productID, orderTotal, orderDate)
SELECT r.orderID, c.customerID, e.employeeID, p.productID, r.orderTotal, r.orderDate
FROM sales_raw r
JOIN customers c ON c.firstName = r.customerFirstName
                AND c.lastName  = r.customerLastName
                AND c.birthDate = r.customerBirthDate
JOIN employees e ON e.firstName = r.employeeFirstName
                AND e.lastName  = r.employeeLastName
                AND e.birthDate = r.employeeBirthDate
JOIN products  p ON p.category  = r.productCategory;

-- Expect 42 / 8 / 4 / 6 / 42
SELECT 'sales_raw' AS t, count(*) FROM sales_raw
UNION ALL SELECT 'customers', count(*) FROM customers
UNION ALL SELECT 'employees', count(*) FROM employees
UNION ALL SELECT 'products',  count(*) FROM products
UNION ALL SELECT 'orders',    count(*) FROM orders;


-- ------------------------------------------------------------
-- STEP 5.  Basic queries (DQL).
-- ------------------------------------------------------------
SELECT * FROM customers;

SELECT firstName, lastName, birthDate FROM customers;

SELECT * FROM customers WHERE birthDate < '1990-01-01';

SELECT * FROM products  WHERE price > 100;

SELECT * FROM products  ORDER BY price DESC;

SELECT * FROM orders    ORDER BY orderDate DESC LIMIT 5;

SELECT * FROM customers WHERE moneySpent > 3000 AND birthDate < '1995-01-01';

SELECT DISTINCT category FROM products;


-- ------------------------------------------------------------
-- STEP 6.  THE PAYOFF — put it back together.  42 rows.
-- ------------------------------------------------------------
SELECT o.orderID,
       o.orderDate,
       c.firstName || ' ' || c.lastName AS customer,
       p.category,
       p.price,
       o.orderTotal,
       e.firstName || ' ' || e.lastName AS soldBy
FROM orders o
JOIN customers c ON c.customerID = o.customerID
JOIN products  p ON p.productID  = o.productID
JOIN employees e ON e.employeeID = o.employeeID
ORDER BY o.orderDate, o.orderID;

-- Optional: is the STORED moneySpent still true?
SELECT c.firstName, c.lastName,
       c.moneySpent      AS stored,
       SUM(o.orderTotal) AS computed
FROM customers c
JOIN orders o ON o.customerID = c.customerID
GROUP BY c.customerID, c.firstName, c.lastName, c.moneySpent
ORDER BY c.customerID;
-- They match today.  What happens the first time someone forgets to update it?


-- ------------------------------------------------------------
-- STEP 7.  Watch the database say NO.
-- ------------------------------------------------------------
INSERT INTO orders VALUES (9999, 999, 1, 1, 100.00, '2024-08-15');
-- ERROR: violates foreign key constraint  (no customer 999)

INSERT INTO products (category, price) VALUES ('Broken', -50);
-- ERROR: violates check constraint "products_price_check"

INSERT INTO products (category, price) VALUES ('Laptops', 999.00);
-- ERROR: duplicate key value violates unique constraint

-- A spreadsheet would have accepted all three, silently.


-- ------------------------------------------------------------
-- STEP 8.  ALTER and DROP -- evolving and retiring a schema.
-- ------------------------------------------------------------

-- ---- ALTER TABLE: add a column, the wrong way then the right way ----
ALTER TABLE orders ADD COLUMN saleChannel VARCHAR(20);
SELECT count(*) FROM orders WHERE saleChannel IS NULL;   -- 42

ALTER TABLE orders ALTER COLUMN saleChannel SET NOT NULL;
-- ERROR: column "salechannel" of relation "orders" contains null values

UPDATE orders SET saleChannel = 'in_store' WHERE saleChannel IS NULL;
ALTER TABLE orders ALTER COLUMN saleChannel SET NOT NULL;

ALTER TABLE orders RENAME COLUMN saleChannel TO channel;
ALTER TABLE customers ALTER COLUMN firstName TYPE VARCHAR(100);
ALTER TABLE customers ALTER COLUMN firstName TYPE VARCHAR(50);  -- shrink back; fits since no name is > 50 chars

ALTER TABLE orders ADD CONSTRAINT channel_known
    CHECK (channel IN ('in_store', 'online'));

UPDATE orders SET channel = 'carrier_pigeon'
WHERE orderID = (SELECT orderID FROM orders LIMIT 1);
-- ERROR: new row for relation "orders" violates check constraint "channel_known"

ALTER TABLE orders DROP CONSTRAINT channel_known;
ALTER TABLE orders DROP COLUMN channel;
-- orders is back to exactly the 6 columns from STEP 3.


-- ---- DELETE vs TRUNCATE vs DROP TABLE: all three respect foreign keys ----
DELETE FROM products WHERE productID = 1;
-- ERROR: update or delete on table "products" violates foreign key
--        constraint "orders_productid_fkey" on table "orders"

TRUNCATE products;
-- ERROR: cannot truncate a table referenced in a foreign key constraint
-- HINT:  Truncate table "orders" at the same time, or use TRUNCATE ... CASCADE.

DROP TABLE products;
-- ERROR: cannot drop table products because other objects depend on it
-- HINT:  Use DROP ... CASCADE to drop the dependent objects too.

DROP TABLE IF EXISTS not_a_real_table;
-- NOTICE: table "not_a_real_table" does not exist, skipping


-- ---- What CASCADE actually does -- try it on a disposable pair,
-- not the real schema. It drops the dependent CONSTRAINT, not the
-- dependent table or its rows. ----
CREATE TABLE scratch_categories (name VARCHAR(50) PRIMARY KEY);
CREATE TABLE scratch_items (
    id  SERIAL PRIMARY KEY,
    cat VARCHAR(50) REFERENCES scratch_categories(name)
);

DROP TABLE scratch_categories CASCADE;
-- NOTICE: drop cascades to constraint scratch_items_cat_fkey on table scratch_items

\d scratch_items
DROP TABLE scratch_items;

-- Confirm the real schema ends up unchanged (column added/removed and
-- firstName's width widened/shrunk both net to zero):
SELECT 'products' AS t, count(*) FROM products
UNION ALL SELECT 'orders', count(*) FROM orders;
-- Expected: 6 / 42 -- unchanged since STEP 4.
