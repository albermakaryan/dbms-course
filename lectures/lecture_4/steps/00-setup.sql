-- ============================================================
-- Lecture 4 — Part 0: load the data
--
-- Exactly Lecture 3's data -- same 600 sales, same CSV files, copied
-- into this folder so the lecture stands on its own. Creates FIVE
-- tables and fills them from data/*.csv:
--
--   sales      the flat file -- one row per sale, 29 columns
--   customers  \
--   employees   |  the same 600 sales, normalized. Last lecture you
--   products    |  mostly queried the flat file. This lecture you
--   orders     /   put these four back together yourself.
--
-- One addition: employees.managerID, who each person reports to.
-- The CSV doesn't have it; three UPDATEs at the bottom fill it in.
--
-- \copy resolves paths relative to where you STARTED psql, so run
-- this from the lecture_4/ folder:    psql lecture04
--                                     \i steps/00-setup.sql
-- Safe to re-run: drops and recreates everything, including the
-- tables the notes build along the way.
-- ============================================================

-- Also drops the tables this lecture's notes create (order_items in
-- Part 2, the star schema in Part 6), so this stays the reset button.
DROP TABLE IF EXISTS fact_sales, dim_date, dim_customer, dim_product, dim_employee,
                     order_items, sales, orders, customers, employees, products;

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
    salary       DECIMAL(8,2) NOT NULL CHECK (salary > 0),
    managerID    INT REFERENCES employees(employeeID)   -- NEW: who this person reports to; NULL = nobody
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
-- (CSV fallback: replace the five \copy lines with  \i data/all_inserts.sql)
-- An empty field in a CSV (no anniversary, no employee, no rating) becomes NULL.
\copy sales     FROM 'data/sales_flat.csv' WITH (FORMAT csv, HEADER true)
\copy customers FROM 'data/customers.csv'  WITH (FORMAT csv, HEADER true)
-- employees.csv has no managerID column, so name the columns it does have.
\copy employees (employeeID, firstName, lastName, email, birthDate, hireDate, position, branch, salary) FROM 'data/employees.csv' WITH (FORMAT csv, HEADER true)
\copy products  FROM 'data/products.csv'   WITH (FORMAT csv, HEADER true)
\copy orders    FROM 'data/orders.csv'     WITH (FORMAT csv, HEADER true)

-- The CSVs carry their own ids, so each SERIAL counter still thinks the
-- next id is 1. Move them past what's loaded, or the first INSERT
-- without an id would collide with row 1.
SELECT setval(pg_get_serial_sequence('customers', 'customerid'), (SELECT max(customerID) FROM customers));
SELECT setval(pg_get_serial_sequence('employees', 'employeeid'), (SELECT max(employeeID) FROM employees));
SELECT setval(pg_get_serial_sequence('products',  'productid'),  (SELECT max(productID)  FROM products));

-- ---- New this lecture: the reporting line ----
-- Vahe runs the Yerevan Center store and everyone reports up to him.
-- The two other branches have a Senior Sales lead in between.
UPDATE employees SET managerID = 3 WHERE employeeID IN (1, 2, 5, 8);   -- Gor, Ani, Hayk, Marine -> Vahe
UPDATE employees SET managerID = 5 WHERE employeeID IN (4, 6);         -- Nare, Lilit -> Hayk (Yerevan Mall)
UPDATE employees SET managerID = 8 WHERE employeeID = 7;               -- Arman -> Marine (Gyumri)

-- Expect 600 / 30 / 8 / 37 / 600
SELECT 'sales' AS t, count(*) FROM sales
UNION ALL SELECT 'customers', count(*) FROM customers
UNION ALL SELECT 'employees', count(*) FROM employees
UNION ALL SELECT 'products',  count(*) FROM products
UNION ALL SELECT 'orders',    count(*) FROM orders;
