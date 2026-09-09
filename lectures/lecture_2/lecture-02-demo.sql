-- ============================================================
-- Lecture 2 — From One File to Four Tables
-- YSU, Data Science for Business
--
-- Building the exact schema from the Lecture 1 slide:
--   Customers(customerID, firstName, lastName, birthDate, moneySpent, anniversary)
--   Employees(employeeID, firstName, lastName, birthDate)
--   Products (productID, category, price)
--   Orders   (orderID, customerID, employeeID, productID, orderTotal, orderDate)
-- ============================================================


-- ------------------------------------------------------------
-- STEP 0.  One wide, flat file.  42 rows, 13 columns.
-- ------------------------------------------------------------
CREATE TABLE sales_raw (
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

-- \copy runs on YOUR machine (psql).  COPY runs on the server.
\copy sales_raw FROM 'sales_flat.csv' WITH (FORMAT csv, HEADER true);

SELECT * FROM sales_raw ORDER BY orderDate, orderID LIMIT 10;


-- ------------------------------------------------------------
-- STEP 1.  Find the problem.  (Ask the room BEFORE running.)
-- ------------------------------------------------------------
SELECT count(*)                         AS total_rows     FROM sales_raw;  -- 42
SELECT count(DISTINCT customerLastName) AS real_customers FROM sales_raw;  -- 8
SELECT count(DISTINCT productCategory)  AS real_products  FROM sales_raw;  -- 6

-- 42 rows, but 8 customers.  Anna's birth date is stored six times.

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
CREATE TABLE customers (
    customerID   SERIAL PRIMARY KEY,
    firstName    VARCHAR(50) NOT NULL,
    lastName     VARCHAR(50) NOT NULL,
    birthDate    DATE,
    moneySpent   DECIMAL(10,2) DEFAULT 0 CHECK (moneySpent >= 0),
    anniversary  DATE
);

CREATE TABLE employees (
    employeeID   SERIAL PRIMARY KEY,
    firstName    VARCHAR(50) NOT NULL,
    lastName     VARCHAR(50) NOT NULL,
    birthDate    DATE
);

CREATE TABLE products (
    productID    SERIAL PRIMARY KEY,
    category     VARCHAR(100) NOT NULL UNIQUE,
    price        DECIMAL(8,2) NOT NULL CHECK (price >= 0)
);

CREATE TABLE orders (
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
