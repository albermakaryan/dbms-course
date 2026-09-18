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
