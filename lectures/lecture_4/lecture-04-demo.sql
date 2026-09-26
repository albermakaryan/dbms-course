-- ============================================================
-- Lecture 4 — Putting the Tables Back Together
-- YSU, Data Science for Business
--
-- Data models, schema types (OLTP vs OLAP, star, snowflake), and
-- JOIN in detail: inner, left, right, full, cross, self, anti-joins,
-- and the traps -- on Lecture 3's data.
--
-- Run this whole script at once (from the lecture_4/ folder, so the
-- \copy paths in Part 0 resolve), or run each part separately from
-- steps/00-setup.sql through steps/07-drill.sql (numbered to match
-- the Parts in lecture-04-notes.md). Three statements error ON
-- PURPOSE -- the comments say which.
-- ============================================================



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



-- ============================================================
-- Lecture 4 — Part 1: Data models
-- Run after steps/00-setup.sql.
-- ============================================================

-- ---- Three levels of the same model ----
\d orders

-- ---- See it: a row is almost a document ----
SELECT jsonb_pretty(to_jsonb(c)) FROM customers c WHERE customerID = 2;
-- a JSON document -- see the notes



-- ============================================================
-- Lecture 4 — Part 2: Schema types
-- Run after Part 1. Creates order_items (safe to re-run).
-- ============================================================

-- ---- The fix Lecture 2 deferred: order_items ----
DROP TABLE IF EXISTS order_items;

CREATE TABLE order_items (
    orderID      INT NOT NULL REFERENCES orders(orderID),
    productID    INT NOT NULL REFERENCES products(productID),
    quantity     INT NOT NULL CHECK (quantity > 0),
    unitPrice    DECIMAL(8,2) NOT NULL CHECK (unitPrice >= 0),
    discountPct  INT NOT NULL DEFAULT 0 CHECK (discountPct BETWEEN 0 AND 100),
    PRIMARY KEY (orderID, productID)
);

INSERT INTO order_items (orderID, productID, quantity, unitPrice, discountPct)
SELECT orderID, productID, quantity, unitPrice, discountPct
FROM orders;
-- INSERT 0 600

SELECT count(*) AS orders_with_several_lines
FROM (SELECT orderID FROM order_items GROUP BY orderID HAVING count(*) > 1) AS t;
-- orders_with_several_lines
-- 0



-- ============================================================
-- Lecture 4 — Part 3: JOIN: the idea
-- Run after Part 2 -- reads order_items.
-- ============================================================

-- ---- Where the names went ----
SELECT orderID, customerID, productID, orderTotal
FROM orders
ORDER BY orderID
LIMIT 3;
-- 3 rows -- see the notes

-- ---- Step 1: every combination ----
SELECT count(*) FROM orders CROSS JOIN customers;
-- count
-- 18000

SELECT o.orderID, o.customerID AS "order says", c.customerID AS "customer row",
       c.firstName, c.lastName
FROM orders o CROSS JOIN customers c
WHERE o.orderID IN (1001, 1002, 1003)
  AND c.customerID IN (2, 6, 26)
ORDER BY o.orderID, c.customerID;
-- 9 rows -- see the notes

-- ---- Step 2: keep the pairs that match ----
SELECT o.orderID, o.customerID AS "order says", c.customerID AS "customer row",
       c.firstName, c.lastName
FROM orders o CROSS JOIN customers c
WHERE o.orderID IN (1001, 1002, 1003)
  AND c.customerID IN (2, 6, 26)
  AND o.customerID = c.customerID
ORDER BY o.orderID;
-- 3 rows -- see the notes

SELECT o.orderID, c.firstName, c.lastName, o.orderTotal
FROM orders o
JOIN customers c ON c.customerID = o.customerID
WHERE o.orderID IN (1001, 1002, 1003)
ORDER BY o.orderID;
-- 3 rows -- see the notes

-- ---- Aliases, and whose column is it? ----
SELECT orders.orderID, customers.firstName, orders.orderTotal
FROM orders
JOIN customers ON customers.customerID = orders.customerID
WHERE orders.orderID = 1001;

-- Error on purpose:
SELECT orderID, customerID, firstName
FROM orders
JOIN customers ON customers.customerID = orders.customerID
WHERE orderID = 1001;
-- ERROR:  column reference "customerid" is ambiguous

-- Error on purpose:
SELECT orders.orderID
FROM orders o
WHERE o.orderID = 1001;
-- ERROR:  invalid reference to FROM-clause entry for table "orders"
-- HINT:  Perhaps you meant to reference the table alias "o".

-- ---- USING: when the key has the same name on both sides ----
SELECT customerID, c.firstName, o.orderID
FROM orders o
JOIN customers c USING (customerID)
WHERE o.orderID = 1001;
-- customerid | firstname | orderid
-- 2 | Davit     |    1001

-- ---- NATURAL JOIN: don't ----
SELECT count(*) FROM orders NATURAL JOIN sales;
-- count
-- 97

-- ---- More than two tables ----
SELECT o.orderID, o.orderDate,
       c.firstName || ' ' || c.lastName AS customer,
       p.productName, p.category,
       o.orderTotal
FROM orders o
JOIN customers c ON c.customerID = o.customerID
JOIN products  p ON p.productID  = o.productID
ORDER BY o.orderID
LIMIT 5;
-- 5 rows -- see the notes

SELECT o.orderID, p.productName, i.quantity, i.unitPrice
FROM orders o
JOIN order_items i ON i.orderID   = o.orderID
JOIN products    p ON p.productID = i.productID
WHERE o.orderID IN (1001, 1002, 1003)
ORDER BY o.orderID;
-- 3 rows -- see the notes

-- ---- Now you can ask the normalized tables anything ----
SELECT c.city,
       count(DISTINCT c.customerID) AS customers,
       count(*)                     AS orders,
       sum(o.orderTotal)            AS revenue
FROM orders o
JOIN customers c ON c.customerID = o.customerID
WHERE o.status = 'completed'
GROUP BY c.city
ORDER BY revenue DESC;
-- 4 rows -- see the notes



-- ============================================================
-- Lecture 4 — Part 4: Outer joins: keeping the rows that don't match
-- Run after Part 3.
-- ============================================================

-- ---- Where did 181 orders go? ----
SELECT count(*)
FROM orders o
JOIN customers c ON c.customerID = o.customerID
JOIN products  p ON p.productID  = o.productID
JOIN employees e ON e.employeeID = o.employeeID;
-- count
-- 419

SELECT sum(o.orderTotal) AS revenue
FROM orders o
JOIN employees e ON e.employeeID = o.employeeID
WHERE o.status = 'completed';
-- revenue
-- 93534.71

-- ---- LEFT JOIN: keep every row on the left ----
SELECT o.orderID, o.channel, e.firstName, e.branch
FROM orders o
LEFT JOIN employees e ON e.employeeID = o.employeeID
WHERE o.orderID BETWEEN 1001 AND 1008
ORDER BY o.orderID;
-- 8 rows -- see the notes

SELECT count(*)
FROM orders o
LEFT JOIN employees e ON e.employeeID = o.employeeID;
-- count
-- 600

SELECT coalesce(e.branch, 'Online') AS branch,
       count(*)                     AS orders,
       sum(o.orderTotal)            AS revenue
FROM orders o
LEFT JOIN employees e ON e.employeeID = o.employeeID
WHERE o.status = 'completed'
GROUP BY coalesce(e.branch, 'Online')
ORDER BY revenue DESC;
-- 4 rows -- see the notes

-- ---- Who never bought? The anti-join ----
SELECT count(*)
FROM customers c
LEFT JOIN orders o ON o.customerID = c.customerID;
-- count
-- 602

SELECT c.customerID, c.firstName, c.lastName, c.signupDate
FROM customers c
LEFT JOIN orders o ON o.customerID = c.customerID
WHERE o.orderID IS NULL;
-- customerid | firstname | lastname  | signupdate
-- 24 | Levon     | Arakelyan | 2023-11-01
-- 29 | Astghik   | Danielyan | 2022-10-23

SELECT p.productID, p.productName, p.category, p.stockQuantity
FROM products p
LEFT JOIN orders o ON o.productID = p.productID
WHERE o.orderID IS NULL;
-- productid |     productname     | category | stockquantity
-- 35 | Ergonomic Chair Pro | Chairs   |             6

-- ---- count(*) counts the empty match ----
SELECT c.firstName, c.lastName, count(*) AS orders
FROM customers c
LEFT JOIN orders o ON o.customerID = c.customerID
GROUP BY c.customerID, c.firstName, c.lastName
ORDER BY orders, c.lastName
LIMIT 4;
-- 4 rows -- see the notes

SELECT c.firstName, c.lastName, count(o.orderID) AS orders
FROM customers c
LEFT JOIN orders o ON o.customerID = c.customerID
GROUP BY c.customerID, c.firstName, c.lastName
ORDER BY orders, c.lastName
LIMIT 4;
-- 4 rows -- see the notes

-- ---- The trap: a WHERE that undoes the LEFT JOIN ----
SELECT p.category, count(o.orderID) AS orders, sum(o.orderTotal) AS revenue
FROM products p
LEFT JOIN orders o ON o.productID = p.productID
GROUP BY p.category
ORDER BY revenue DESC NULLS LAST;
-- 13 rows -- see the notes

SELECT p.category, count(o.orderID) AS orders, sum(o.orderTotal) AS revenue
FROM products p
LEFT JOIN orders o ON o.productID = p.productID
WHERE o.status = 'completed'
GROUP BY p.category
ORDER BY revenue DESC NULLS LAST;
-- 12 rows -- see the notes

SELECT p.category, count(o.orderID) AS orders, coalesce(sum(o.orderTotal), 0) AS revenue
FROM products p
LEFT JOIN orders o ON o.productID = p.productID
                  AND o.status = 'completed'
GROUP BY p.category
ORDER BY revenue DESC;
-- 13 rows -- see the notes

SELECT count(*) AS rows, count(o.orderID) AS matched
FROM customers c
LEFT JOIN orders o ON o.customerID = c.customerID
                  AND c.city = 'Gyumri';
-- rows | matched
-- 233 |     210

-- ---- RIGHT JOIN: the same thing, backwards ----
SELECT count(*) FROM orders o RIGHT JOIN customers c ON c.customerID = o.customerID;
-- count
-- 602

-- ---- FULL OUTER JOIN: keep both sides ----
SELECT CASE WHEN e.employeeID IS NULL THEN 'customer only'
            WHEN c.customerID IS NULL THEN 'employee only'
            ELSE 'on both lists' END AS status,
       count(*) AS people
FROM customers c
FULL JOIN employees e ON e.firstName = c.firstName AND e.lastName = c.lastName
GROUP BY 1
ORDER BY 1;
-- 3 rows -- see the notes

-- ---- Proof: the four tables *are* the flat file ----
SELECT o.orderID, o.orderDate, o.orderTime, o.channel, o.status, o.paymentMethod,
       o.quantity, o.unitPrice, o.discountPct, o.orderTotal, o.deliveryDate, o.rating,
       c.firstName, c.lastName, c.email, c.city, c.birthDate, c.signupDate,
       c.anniversary, c.moneySpent,
       e.firstName, e.lastName, e.position, e.branch,
       p.productName, p.category, p.brand, p.price, p.cost
FROM orders o
JOIN      customers c ON c.customerID = o.customerID
JOIN      products  p ON p.productID  = o.productID
LEFT JOIN employees e ON e.employeeID = o.employeeID
EXCEPT
SELECT * FROM sales;
-- 0 rows



-- ============================================================
-- Lecture 4 — Part 5: More joins, more traps
-- Run after Part 4.
-- ============================================================

-- ---- Self-join: a table joined to itself ----
-- Error on purpose:
SELECT employees.firstName, employees.firstName
FROM employees
JOIN employees ON employees.employeeID = employees.managerID;
-- ERROR:  table name "employees" specified more than once

SELECT e.firstName || ' ' || e.lastName AS employee,
       e.position,
       m.firstName || ' ' || m.lastName AS manager
FROM employees e
LEFT JOIN employees m ON m.employeeID = e.managerID
ORDER BY m.employeeID NULLS FIRST, e.employeeID;
-- 8 rows -- see the notes

SELECT e.firstName AS employee, m.firstName AS manager, mm.firstName AS managers_manager
FROM employees e
LEFT JOIN employees m  ON m.employeeID  = e.managerID
LEFT JOIN employees mm ON mm.employeeID = m.managerID
WHERE e.branch <> 'Yerevan Center';
-- 5 rows -- see the notes

SELECT m.firstName || ' ' || m.lastName AS manager, count(e.employeeID) AS direct_reports
FROM employees m
JOIN employees e ON e.managerID = m.employeeID
GROUP BY m.employeeID, m.firstName, m.lastName
ORDER BY direct_reports DESC;
-- 3 rows -- see the notes

-- ---- Joining on the wrong thing ----
SELECT c.firstName, c.lastName,
       c.birthDate AS customer_born, e.birthDate AS employee_born,
       c.city      AS customer_city, e.branch    AS employee_branch
FROM customers c
JOIN employees e ON e.firstName = c.firstName AND e.lastName = c.lastName;
-- firstname |   lastname   | customer_born | employee_born | customer_city | employee_branch
-- Hayk      | Melikyan     | 1993-03-30    | 1985-02-11    | Vanadzor      | Yerevan Mall
-- Lilit     | Hovhannisyan | 1990-06-14    | 1998-07-07    | Abovyan       | Yerevan Mall

SELECT count(*)
FROM sales s
JOIN customers c ON c.firstName = s.customerFirstName
                AND c.lastName  = s.customerLastName;
-- count
-- 637

-- ---- Fan-out: the join that inflates your sums ----
SELECT sum(c.moneySpent) AS total_customer_spend
FROM customers c
JOIN orders o ON o.customerID = c.customerID;
-- total_customer_spend
-- 4079958.38

SELECT count(*) AS rows, count(DISTINCT c.customerID) AS customers
FROM customers c
JOIN orders o ON o.customerID = c.customerID;
-- rows | customers
-- 600 |        28

-- ---- Stored vs computed: is moneySpent still right? ----
SELECT c.customerID, c.firstName, c.lastName,
       c.moneySpent                     AS stored,
       coalesce(sum(o.orderTotal), 0)   AS computed
FROM customers c
LEFT JOIN orders o ON o.customerID = c.customerID
                  AND o.status = 'completed'
GROUP BY c.customerID, c.firstName, c.lastName, c.moneySpent
HAVING c.moneySpent <> coalesce(sum(o.orderTotal), 0);
-- customerid | firstname | lastname | stored | computed

-- ---- A document is a join you saved ----
SELECT jsonb_pretty(
         jsonb_build_object(
           'customer', c.firstName || ' ' || c.lastName,
           'city',     c.city,
           'orders',   jsonb_agg(jsonb_build_object(
                           'orderID', o.orderID,
                           'date',    o.orderDate,
                           'product', p.productName,
                           'status',  o.status,
                           'total',   o.orderTotal)
                         ORDER BY o.orderDate)))
FROM customers c
JOIN orders   o ON o.customerID = c.customerID
JOIN products p ON p.productID  = o.productID
WHERE c.customerID = 27
GROUP BY c.customerID, c.firstName, c.lastName, c.city;
-- a JSON document -- see the notes

-- ---- ON can be any condition ----
SELECT b.band, count(*) AS orders, sum(o.orderTotal) AS revenue
FROM orders o
JOIN (VALUES ('1. under 50',  0,    50),
             ('2. 50 - 299',  50,   300),
             ('3. 300 - 999', 300,  1000),
             ('4. 1000+',     1000, 100000)) AS b(band, low, high)
  ON o.orderTotal >= b.low AND o.orderTotal < b.high
WHERE o.status = 'completed'
GROUP BY b.band
ORDER BY b.band;
-- 4 rows -- see the notes



-- ============================================================
-- Lecture 4 — Part 6: Build a star
-- Run after Part 5. Creates the star schema (safe to re-run).
-- ============================================================

DROP TABLE IF EXISTS fact_sales, dim_date, dim_customer, dim_product, dim_employee;

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
SELECT customerID                        AS customerKey,
       firstName || ' ' || lastName      AS customerName,
       city,
       EXTRACT(year FROM signupDate)::int AS signupYear
FROM customers;

CREATE TABLE dim_product AS
SELECT productID AS productKey, productName, brand, category
FROM products;

ALTER TABLE dim_customer ADD PRIMARY KEY (customerKey);
ALTER TABLE dim_product  ADD PRIMARY KEY (productKey);

CREATE TABLE dim_employee AS
SELECT e.employeeID                                          AS employeeKey,
       e.firstName || ' ' || e.lastName                      AS employeeName,
       e.branch,
       coalesce(m.firstName || ' ' || m.lastName, '(none)')  AS managerName
FROM employees e
LEFT JOIN employees m ON m.employeeID = e.managerID;

INSERT INTO dim_employee VALUES (0, '(online)', 'Online', '(none)');

ALTER TABLE dim_employee ADD PRIMARY KEY (employeeKey);

CREATE TABLE fact_sales AS
SELECT o.orderID,
       o.orderDate                 AS dateKey,
       o.customerID                AS customerKey,
       o.productID                 AS productKey,
       coalesce(o.employeeID, 0)   AS employeeKey,
       o.channel,
       o.status,
       o.quantity,
       o.orderTotal                AS revenue,
       o.quantity * p.cost         AS cost
FROM orders o
JOIN products p ON p.productID = o.productID;

ALTER TABLE fact_sales
    ADD PRIMARY KEY (orderID),
    ADD FOREIGN KEY (dateKey)     REFERENCES dim_date,
    ADD FOREIGN KEY (customerKey) REFERENCES dim_customer,
    ADD FOREIGN KEY (productKey)  REFERENCES dim_product,
    ADD FOREIGN KEY (employeeKey) REFERENCES dim_employee;

SELECT count(*) AS facts, sum(revenue) FILTER (WHERE status = 'completed') AS revenue
FROM fact_sales;
-- facts |  revenue
-- 600 | 145935.12

SELECT e.branch,
       sum(f.revenue) FILTER (WHERE d.quarter = 1) AS q1,
       sum(f.revenue) FILTER (WHERE d.quarter = 2) AS q2,
       sum(f.revenue) FILTER (WHERE d.quarter = 3) AS q3,
       sum(f.revenue) FILTER (WHERE d.quarter = 4) AS q4,
       sum(f.revenue)                              AS total
FROM fact_sales f
JOIN dim_date     d ON d.dateKey     = f.dateKey
JOIN dim_employee e ON e.employeeKey = f.employeeKey
WHERE f.status = 'completed'
GROUP BY e.branch
ORDER BY total DESC;
-- 4 rows -- see the notes

SELECT p.category,
       sum(f.revenue - f.cost) FILTER (WHERE d.dayName = 'Sat') AS sat_margin,
       sum(f.revenue - f.cost)                                  AS year_margin
FROM fact_sales f
JOIN dim_date    d ON d.dateKey    = f.dateKey
JOIN dim_product p ON p.productKey = f.productKey
WHERE f.status = 'completed'
GROUP BY p.category
ORDER BY year_margin DESC
LIMIT 5;
-- 5 rows -- see the notes



-- ============================================================
-- Lecture 4 — Part 7: Verification drill
-- Run after Part 6.
-- ============================================================

SELECT sum(o.orderTotal) AS revenue
FROM orders o
JOIN employees e ON e.employeeID = o.employeeID
WHERE o.status = 'completed';
-- 93534.71

SELECT c.firstName, c.lastName, count(*) AS orders
FROM customers c
LEFT JOIN orders o ON o.customerID = c.customerID
GROUP BY c.customerID, c.firstName, c.lastName
HAVING count(*) <= 5
ORDER BY orders, c.lastName;
-- Levon 1, Astghik 1, Diana 4, Lusine 5

SELECT p.category, coalesce(sum(o.orderTotal), 0) AS revenue
FROM products p
LEFT JOIN orders o ON o.productID = p.productID
WHERE o.status = 'completed'
GROUP BY p.category;
-- 12 rows

SELECT round(avg(c.moneySpent), 2) AS avg_spend
FROM customers c
JOIN orders o ON o.customerID = c.customerID
WHERE o.orderDate BETWEEN '2024-12-01' AND '2024-12-31';
-- 6821.14

-- ---- Answers ----
SELECT p.category, coalesce(sum(o.orderTotal), 0) AS revenue
FROM products p
LEFT JOIN orders o ON o.productID = p.productID AND o.status = 'completed'
GROUP BY p.category;
-- 13 rows, Chairs 0

SELECT round(avg(moneySpent), 2) AS avg_spend, count(*) AS customers
FROM customers
WHERE customerID IN (SELECT customerID FROM orders
                     WHERE orderDate BETWEEN '2024-12-01' AND '2024-12-31');
-- avg_spend | customers
-- 5448.88 |        26
