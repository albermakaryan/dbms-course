-- ============================================================
-- Lecture 5 — Subqueries → CTEs
-- YSU, Data Science for Business
--
-- Subqueries in every shape (scalar, column, row, table), subqueries
-- vs. joins, correlated subqueries, LATERAL, EXISTS, CTEs, and a first
-- look at WITH RECURSIVE -- on Lecture 4's shop, now with real
-- multi-product orders: an order header (orders) and its lines
-- (order_items). The customers, staff, products and the 600 orders are
-- the ones you know from Lecture 4, so most answers can be checked
-- against a number you already know.
--
-- Run this whole script at once (from the lecture_5/ folder, so the
-- \copy paths in Part 0 resolve), or run each part separately from
-- steps/00-setup.sql through steps/07-drill.sql (numbered to match
-- the Parts in lecture-05-notes.md). Five statements error ON
-- PURPOSE -- the comments say which. Thirteen more are WRONG on
-- purpose and run without any error -- the comments say which, and
-- what the right answer is.
-- ============================================================



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
SELECT 'CREATE DATABASE lecture05'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'lecture05')\gexec

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



-- ============================================================
-- Lecture 5 — Part 1: Subqueries: the basic shapes
-- Run after steps/00-setup.sql.
--
-- A subquery is a SELECT inside another statement, in parentheses.
-- What it is allowed to return depends on where you put it:
--   one value          scalar subquery   WHERE price > (...)
--   one column, rows   column subquery   WHERE id IN (...), = ANY, > ALL
--   one row, columns   row subquery      WHERE (a, b) = (...)
--   a whole table      table subquery    FROM (...) AS t
-- ============================================================

-- ---- 1.1 Scalar subquery: one value ----
SELECT round(avg(price), 2) AS avg_price FROM products;
-- avg_price
-- 280.10

SELECT productName, category, price
FROM products
WHERE price > (SELECT avg(price) FROM products)
ORDER BY price DESC;
-- 12 rows: ThinkPad X1 Carbon 1250.00 down to WH-1000XM5 299.00
-- (4 Laptops, 3 Phones, 2 Tablets, 2 Monitors, 1 Audio)

-- A scalar subquery works anywhere a single value does -- here in
-- SELECT, as the denominator of a share. Revenue PER CATEGORY has to
-- come from the lines (order_items) -- one order can hold products from
-- several categories. The total comes from the order headers; the two
-- agree, because orderTotal is the sum of the order's lineTotals.
SELECT p.category,
       sum(i.lineTotal) AS revenue,
       round(100 * sum(i.lineTotal)
                 / (SELECT sum(orderTotal) FROM orders WHERE status = 'completed'), 1) AS pct_of_total
FROM order_items i
JOIN orders   o ON o.orderID   = i.orderID
JOIN products p ON p.productID = i.productID
WHERE o.status = 'completed'
GROUP BY p.category
ORDER BY revenue DESC
LIMIT 3;
-- category | revenue  | pct_of_total
-- Laptops  | 53412.00 |         34.0
-- Phones   | 25991.90 |         16.5
-- Audio    | 19038.90 |         12.1

-- Error on purpose: "one value" is a promise. Four phones break it.
SELECT productName, price
FROM products
WHERE price > (SELECT price FROM products WHERE category = 'Phones');
-- ERROR:  more than one row returned by a subquery used as an expression

-- No error, no rows: a scalar subquery that finds NOTHING becomes NULL,
-- and price > NULL is never true. (There is no 'iPhone 16' in products.)
SELECT productName, price
FROM products
WHERE price > (SELECT price FROM products WHERE productName = 'iPhone 16');
-- 0 rows -- silently. Too many rows is an error; zero rows is not.

-- ---- 1.2 Column subquery: IN, ANY, ALL ----
-- You already wrote one: the answer to Lecture 4's drill.
SELECT count(*) AS customers
FROM customers
WHERE customerID IN (SELECT customerID FROM orders
                     WHERE orderDate BETWEEN '2024-12-01' AND '2024-12-31');
-- customers
-- 26

-- The JOIN version of "customers who ordered in December" counts rows,
-- not customers: one row per December order.
SELECT count(*) AS rows
FROM customers c
JOIN orders o ON o.customerID = c.customerID
WHERE o.orderDate BETWEEN '2024-12-01' AND '2024-12-31';
-- rows
-- 86
-- IN only asks "is this customer on the list?" -- each customer comes
-- out once, however many times they appear in the list.

-- = ANY is IN under another name:
SELECT count(*) AS customers
FROM customers
WHERE customerID = ANY (SELECT customerID FROM orders
                        WHERE orderDate BETWEEN '2024-12-01' AND '2024-12-31');
-- customers
-- 26

-- > ALL: more expensive than EVERY phone (the dearest is 799.00)
SELECT productName, category, price
FROM products
WHERE price > ALL (SELECT price FROM products WHERE category = 'Phones')
ORDER BY price DESC;
-- productname        | category | price
-- ThinkPad X1 Carbon | Laptops  | 1250.00
-- MacBook Air 13     | Laptops  | 1100.00
-- ZenBook 14         | Laptops  |  890.00

-- > ANY: more expensive than AT LEAST ONE phone (the cheapest is 249.00)
SELECT count(*) AS products
FROM products
WHERE price > ANY (SELECT price FROM products WHERE category = 'Phones');
-- products
-- 13

-- ---- 1.3 Row subquery: one row, several columns (rare) ----
-- Every order placed by the same customer ON THE SAME DAY as order 1595
SELECT orderID, customerID, orderDate, orderTime, orderTotal
FROM orders
WHERE (customerID, orderDate) = (SELECT customerID, orderDate
                                 FROM orders WHERE orderID = 1595)
ORDER BY orderID;
-- orderid | customerid | orderdate  | ordertime | ordertotal
-- 1595 |         12 | 2024-12-28 | 12:06:08  |     258.00
-- 1596 |         12 | 2024-12-28 | 14:28:24  |      98.90
-- (Armen Gevorgyan, twice on the same day)

-- ---- 1.4 Table subquery: a derived table in FROM ----
-- "How many orders does a customer place, on average?" needs an
-- aggregate of an aggregate.
-- Error on purpose:
SELECT avg(count(*)) FROM orders GROUP BY customerID;
-- ERROR:  aggregate function calls cannot be nested

-- Count per customer first, in a subquery; average the result outside.
SELECT round(avg(order_count), 2) AS avg_orders_per_customer,
       count(*)                   AS customers
FROM (SELECT customerID, count(*) AS order_count
      FROM orders
      GROUP BY customerID) AS per_customer;
-- avg_orders_per_customer | customers
-- 21.43 |        28
-- 28 customers, not 30: Levon and Astghik have no orders, so they're
-- not in the derived table. 21.43 = 600 / 28. Per customer on the
-- books it would be 600 / 30 = 20.00 -- know which one you mean.

-- Filter on the derived table like on any table:
SELECT c.firstName, c.lastName, pc.order_count
FROM (SELECT customerID, count(*) AS order_count
      FROM orders
      GROUP BY customerID) AS pc
JOIN customers c ON c.customerID = pc.customerID
WHERE pc.order_count >= 40
ORDER BY pc.order_count DESC;
-- firstname | lastname    | order_count
-- Davit     | Petrosyan   |          52
-- Armen     | Gevorgyan   |          48
-- Karen     | Khachatryan |          41
-- Aram      | Vardanyan   |          40



-- ============================================================
-- Lecture 5 — Part 2: Subqueries vs. JOINs
-- Run after Part 1.
-- ============================================================

-- ---- 2.1 One question, three queries ----
-- "Which products have never been ordered?" Lecture 4 answered it:
-- productID 35, Ergonomic Chair Pro. Products now live on the order
-- LINES, so every version asks order_items.

-- (a) Lecture 4's anti-join: LEFT JOIN + IS NULL
SELECT p.productID, p.productName
FROM products p
LEFT JOIN order_items i ON i.productID = p.productID
WHERE i.orderID IS NULL;
-- productid | productname
-- 35 | Ergonomic Chair Pro

-- (b) NOT IN
SELECT productID, productName
FROM products
WHERE productID NOT IN (SELECT productID FROM order_items);
-- productid | productname
-- 35 | Ergonomic Chair Pro

-- (c) NOT EXISTS
SELECT p.productID, p.productName
FROM products p
WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.productID = p.productID);
-- productid | productname
-- 35 | Ergonomic Chair Pro

-- Same answer three ways. They agree HERE because order_items.productID
-- is NOT NULL. Now ask a question where the subquery's column can be NULL.

-- ---- 2.2 The NOT IN trap (callback: Lecture 4's anti-join) ----
-- In miniature first. NOT IN (1, 2, NULL) means 5 <> 1 AND 5 <> 2 AND 5 <> NULL,
-- and 5 <> NULL is not true or false -- it's NULL (unknown).
SELECT 5 NOT IN (1, 2)       AS no_null,
       5 NOT IN (1, 2, NULL) AS with_null,
       2 NOT IN (1, 2, NULL) AS match_with_null;
-- no_null | with_null | match_with_null
-- t       |           | f
-- with_null is NULL (psql prints nothing). WHERE NULL keeps no rows.
-- A NOT IN whose list holds a NULL can never be true for anybody.

-- The real question: "Which salespeople have never had an order
-- cancelled?" -- a clean record, worth a bonus.
SELECT e.employeeID, e.firstName, e.lastName
FROM employees e
WHERE e.employeeID NOT IN (SELECT o.employeeID FROM orders o
                           WHERE o.status = 'cancelled');
-- WRONG: 0 rows. No error. "Nobody has a clean record."

-- Why: 5 of the 27 cancelled orders were online -- employeeID NULL.
SELECT count(*) AS cancelled_orders, count(employeeID) AS with_an_employee
FROM orders
WHERE status = 'cancelled';
-- cancelled_orders | with_an_employee
-- 27 |               22
-- One NULL in the list is enough. Here there are five.

-- FIX 1 -- NOT EXISTS asks "is there a matching row?", which is only
-- ever true or false:
SELECT e.employeeID, e.firstName, e.lastName
FROM employees e
WHERE NOT EXISTS (SELECT 1 FROM orders o
                  WHERE o.employeeID = e.employeeID
                    AND o.status = 'cancelled');
-- employeeid | firstname | lastname
-- 5 | Hayk      | Melikyan

-- FIX 2 -- keep NOT IN, but take the NULLs out of the list yourself:
SELECT e.employeeID, e.firstName, e.lastName
FROM employees e
WHERE e.employeeID NOT IN (SELECT o.employeeID FROM orders o
                           WHERE o.status = 'cancelled'
                             AND o.employeeID IS NOT NULL);
-- employeeid | firstname | lastname
-- 5 | Hayk      | Melikyan

-- FIX 3 -- Lecture 4's anti-join, with the status test in ON (Lecture
-- 4's WHERE-vs-ON lesson: in WHERE it would delete the NULL-padded rows):
SELECT e.employeeID, e.firstName, e.lastName
FROM employees e
LEFT JOIN orders o ON o.employeeID = e.employeeID
                  AND o.status = 'cancelled'
WHERE o.orderID IS NULL;
-- employeeid | firstname | lastname
-- 5 | Hayk      | Melikyan

-- ---- 2.3 THE CART FAN-OUT: joining the lines multiplies the header ----
-- One order (header) has one or more lines. Join them, and every header
-- column -- orderTotal included -- is copied onto every line of that
-- order. Same mechanism as Lecture 4's moneySpent fan-out, one level
-- down: order grain joined to line grain.

-- "Completed revenue, and how many units we sold." Units live on the
-- lines, so someone joins them in:
SELECT sum(o.orderTotal) AS revenue,
       sum(i.quantity)   AS units
FROM orders o
JOIN order_items i ON i.orderID = o.orderID
WHERE o.status = 'completed';
-- revenue   | units
-- 247923.72 |  1174
-- WRONG revenue, right units. Nothing errors.

-- CHECK 1 -- the revenue without the join:
SELECT sum(orderTotal) AS revenue
FROM orders
WHERE status = 'completed';
-- revenue
-- 157078.41

-- CHECK 2 -- count before you sum: rows vs. real orders
SELECT count(*)                   AS rows,
       count(DISTINCT o.orderID)  AS orders
FROM orders o
JOIN order_items i ON i.orderID = o.orderID
WHERE o.status = 'completed';
-- rows | orders
-- 844 |    529
-- 844 rows for 529 orders: an order with 3 lines had its total added 3
-- times. That's the 90,845.31 of revenue that doesn't exist.

-- FIX 1 -- sum what lives on the line: lineTotal, not the header's total.
SELECT sum(i.lineTotal) AS revenue,
       sum(i.quantity)  AS units
FROM orders o
JOIN order_items i ON i.orderID = o.orderID
WHERE o.status = 'completed';
-- revenue   | units
-- 157078.41 |  1174

-- FIX 2 -- aggregate the lines per order FIRST (a table subquery, Part
-- 1.4), so there is one row per order before the join:
SELECT sum(o.orderTotal) AS revenue,
       sum(l.units)      AS units
FROM orders o
JOIN (SELECT orderID, sum(quantity) AS units
      FROM order_items
      GROUP BY orderID) AS l ON l.orderID = o.orderID
WHERE o.status = 'completed';
-- revenue   | units
-- 157078.41 |  1174

-- ---- 2.4 Where a subquery is simply the right tool ----
-- "Revenue from orders that include at least one accessory."
-- WRONG: the JOIN version. An order with two accessories (a sleeve AND
-- a mouse) matches twice, so its total is counted twice.
SELECT sum(o.orderTotal) AS revenue, count(*) AS orders
FROM orders o
JOIN order_items i ON i.orderID   = o.orderID
JOIN products    p ON p.productID = i.productID
WHERE o.status = 'completed'
  AND p.category = 'Accessories';
-- revenue  | orders
-- 29810.88 |    155
-- WRONG: 155 isn't a number of orders, it's a number of accessory LINES.

-- RIGHT: EXISTS asks "is there at least one accessory line?" -- each
-- order is kept or not, never repeated (Part 4).
SELECT sum(o.orderTotal) AS revenue, count(*) AS orders
FROM orders o
WHERE o.status = 'completed'
  AND EXISTS (SELECT 1
              FROM order_items i
              JOIN products p ON p.productID = i.productID
              WHERE i.orderID = o.orderID
                AND p.category = 'Accessories');
-- revenue  | orders
-- 25955.91 |    142
-- 142 orders. 13 of them hold two accessories, and the JOIN counted each
-- of those twice -- 3,854.97 of revenue counted twice.



-- ============================================================
-- Lecture 5 — Part 3: Correlated vs. non-correlated subqueries
-- Run after Part 2.
-- ============================================================

-- ---- 3.1 Non-correlated: the subquery runs on its own ----
-- Part 1's (SELECT avg(price) FROM products) -- select just the
-- subquery and run it: you get 280.10. One value, computed once.

-- ---- 3.2 Correlated: the subquery mentions the outer row ----
-- "Products priced above THEIR OWN category's average"
SELECT p.productName, p.category, p.price
FROM products p
WHERE p.price > (SELECT avg(p2.price)
                 FROM products p2
                 WHERE p2.category = p.category)
ORDER BY p.category, p.price DESC;
-- 19 rows -- compare 12 against the overall average in Part 1.
-- (Chairs has one product, which can't beat its own average.)

-- Error on purpose: the subquery alone has no p to look at.
SELECT avg(p2.price) FROM products p2 WHERE p2.category = p.category;
-- ERROR:  missing FROM-clause entry for table "p"

-- ---- 3.3 Each customer against their own history ----
-- "Customers whose most recent order was bigger than their average order"
SELECT c.firstName, c.lastName, o.orderID, o.orderDate, o.orderTotal,
       (SELECT round(avg(o3.orderTotal), 2)
        FROM orders o3 WHERE o3.customerID = o.customerID) AS their_avg
FROM orders o
JOIN customers c ON c.customerID = o.customerID
WHERE o.orderID = (SELECT o2.orderID FROM orders o2
                   WHERE o2.customerID = o.customerID
                   ORDER BY o2.orderDate DESC, o2.orderTime DESC
                   LIMIT 1)
  AND o.orderTotal > (SELECT avg(o3.orderTotal)
                      FROM orders o3 WHERE o3.customerID = o.customerID)
ORDER BY o.orderTotal DESC;
-- 10 rows. Top three:
-- firstname | lastname     | orderid | orderdate  | ordertotal | their_avg
-- Artur     | Baghdasaryan |    1588 | 2024-12-27 |    1358.30 |    355.32
-- Narek     | Manukyan     |    1557 | 2024-12-17 |    1250.00 |    288.34
-- Vahan     | Torosyan     |    1590 | 2024-12-27 |     926.00 |    422.16
-- (all orders, any status; 28 customers have a last order, 10 qualify)

-- ---- 3.4 Same shape as a self-join (callback: Lecture 4, 4.8) ----
-- "Who was hired before their own manager?"
-- Lecture 4's tool, the self-join:
SELECT e.firstName, e.hireDate, m.firstName AS manager, m.hireDate AS manager_hired
FROM employees e
JOIN employees m ON m.employeeID = e.managerID
WHERE e.hireDate < m.hireDate;
-- firstname | hiredate   | manager | manager_hired
-- Marine    | 2016-08-01 | Vahe    | 2017-02-01

-- The correlated subquery: fetch "my manager's hire date" per row.
SELECT e.firstName, e.hireDate
FROM employees e
WHERE e.hireDate < (SELECT m.hireDate
                    FROM employees m
                    WHERE m.employeeID = e.managerID);
-- firstname | hiredate
-- Marine    | 2016-08-01

-- Where they differ: a correlated subquery in SELECT keeps every outer
-- row. Lecture 4's self-join + GROUP BY counted direct reports for 3
-- managers; this lists all 8 people, with 0 for the rest.
SELECT e.firstName || ' ' || e.lastName AS employee,
       (SELECT m.firstName || ' ' || m.lastName
        FROM employees m WHERE m.employeeID = e.managerID) AS manager,
       (SELECT count(*)
        FROM employees r WHERE r.managerID = e.employeeID) AS direct_reports
FROM employees e
ORDER BY direct_reports DESC, e.employeeID;
-- employee           | manager        | direct_reports
-- Vahe Sahakyan      |                |              4
-- Hayk Melikyan      | Vahe Sahakyan  |              2
-- Marine Avagyan     | Vahe Sahakyan  |              1
-- Gor Mkrtchyan      | Vahe Sahakyan  |              0
-- Ani Harutyunyan    | Vahe Sahakyan  |              0
-- Nare Ghazaryan     | Hayk Melikyan  |              0
-- Lilit Hovhannisyan | Hayk Melikyan  |              0
-- Arman Grigoryan    | Marine Avagyan |              0
-- Vahe's manager is NULL: the subquery found no row, so it's NULL --
-- like a LEFT JOIN, not like an inner join.

-- ---- 3.5 LATERAL: a correlated subquery in FROM ----
-- A correlated subquery in SELECT returns ONE value. "Each customer's
-- latest order -- its id, date, channel and total" needs four.
-- Error on purpose:
SELECT c.firstName,
       (SELECT o.orderID, o.orderTotal
        FROM orders o
        WHERE o.customerID = c.customerID
        ORDER BY o.orderDate DESC, o.orderTime DESC
        LIMIT 1) AS latest
FROM customers c;
-- ERROR:  subquery must return only one column

-- A subquery in FROM can return many columns -- but on its own it
-- can't see c. Error on purpose:
SELECT c.firstName, latest.orderID
FROM customers c
JOIN (SELECT o.orderID
      FROM orders o
      WHERE o.customerID = c.customerID
      ORDER BY o.orderDate DESC, o.orderTime DESC
      LIMIT 1) AS latest ON true;
-- ERROR:  invalid reference to FROM-clause entry for table "c"
-- PostgreSQL 16 and later add:
-- HINT:  To reference that table, you must mark this subquery with LATERAL.

-- LATERAL: the subquery in FROM runs once per customer row, and may
-- use that row's columns. ON true: the matching is already done inside.
SELECT c.firstName, c.lastName,
       latest.orderID, latest.orderDate, latest.channel, latest.orderTotal
FROM customers c
JOIN LATERAL (SELECT o.orderID, o.orderDate, o.channel, o.orderTotal
              FROM orders o
              WHERE o.customerID = c.customerID
              ORDER BY o.orderDate DESC, o.orderTime DESC
              LIMIT 1) AS latest ON true
ORDER BY latest.orderTotal DESC;
-- 28 rows, one per customer who has ordered. Top three:
-- firstname | lastname     | orderid | orderdate  | channel  | ordertotal
-- Artur     | Baghdasaryan |    1588 | 2024-12-27 | in_store |    1358.30
-- Narek     | Manukyan     |    1557 | 2024-12-17 | in_store |    1250.00
-- Vahan     | Torosyan     |    1590 | 2024-12-27 | in_store |     926.00
-- (3.3 found these last orders with a subquery in WHERE; LATERAL
-- brings back every column of them in one join)

-- ---- Top N per group: each customer's 3 biggest orders ----
-- Several ROWS per customer -- no scalar subquery can do that.
-- orderID breaks ties: Suren has two orders of 449.00 tied for 3rd
-- place, and without it which one you get is up to the plan.
SELECT c.firstName, c.lastName, top3.orderID, top3.orderTotal
FROM customers c
LEFT JOIN LATERAL (SELECT o.orderID, o.orderTotal
                   FROM orders o
                   WHERE o.customerID = c.customerID
                   ORDER BY o.orderTotal DESC, o.orderID
                   LIMIT 3) AS top3 ON true
WHERE c.customerID IN (2, 24, 27)
ORDER BY c.customerID, top3.orderTotal DESC;
-- firstname | lastname   | orderid | ordertotal
-- Davit     | Petrosyan  |    1527 |    1000.00
-- Davit     | Petrosyan  |    1523 |     904.99
-- Davit     | Petrosyan  |    1573 |     747.89
-- Levon     | Arakelyan  |         |
-- Diana     | Aleksanyan |    1246 |    1780.00
-- Diana     | Aleksanyan |    1024 |     620.00
-- Diana     | Aleksanyan |    1165 |     349.00

-- Check the row count: you can predict it. Every customer who ordered
-- has at least 3 orders (fewest: Diana, 4), so 28 x 3 = 84.
SELECT count(*) AS rows, count(top3.orderID) AS orders
FROM customers c
JOIN LATERAL (SELECT o.orderID
              FROM orders o
              WHERE o.customerID = c.customerID
              ORDER BY o.orderTotal DESC, o.orderID
              LIMIT 3) AS top3 ON true;
-- rows | orders
-- 84 |     84

-- JOIN LATERAL behaves like an inner join: Levon and Astghik, with no
-- orders, silently disappear. LEFT JOIN LATERAL keeps them:
SELECT count(*) AS rows, count(top3.orderID) AS orders
FROM customers c
LEFT JOIN LATERAL (SELECT o.orderID
                   FROM orders o
                   WHERE o.customerID = c.customerID
                   ORDER BY o.orderTotal DESC, o.orderID
                   LIMIT 3) AS top3 ON true;
-- rows | orders
-- 86 |     84
-- 86 = 84 + 2 NULL-padded rows: Lecture 4's count(*) vs count(column).



-- ============================================================
-- Lecture 5 — Part 4: EXISTS / NOT EXISTS
-- Run after Part 3.
-- ============================================================

-- ---- 4.1 "Is there at least one?" ----
SELECT count(*) AS customers_who_ordered
FROM customers c
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customerID = c.customerID);
-- customers_who_ordered
-- 28

SELECT c.customerID, c.firstName, c.lastName
FROM customers c
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.customerID = c.customerID);
-- customerid | firstname | lastname
-- 24 | Levon     | Arakelyan
-- 29 | Astghik   | Danielyan

-- What the subquery SELECTs doesn't matter -- not even NULL.
-- EXISTS only asks whether a row came back.
SELECT count(*) AS customers_who_ordered
FROM customers c
WHERE EXISTS (SELECT NULL FROM orders o WHERE o.customerID = c.customerID);
-- customers_who_ordered
-- 28

-- Employees who manage at least one person (one row each, no GROUP BY)
SELECT m.firstName, m.lastName, m.position
FROM employees m
WHERE EXISTS (SELECT 1 FROM employees r WHERE r.managerID = m.employeeID)
ORDER BY m.employeeID;
-- firstname | lastname | position
-- Vahe      | Sahakyan | Store Manager
-- Hayk      | Melikyan | Senior Sales
-- Marine    | Avagyan  | Senior Sales

-- ---- 4.2 No NULL trap ----
-- Part 2's NOT EXISTS found Hayk even though 5 cancelled orders have
-- employeeID NULL: o.employeeID = e.employeeID is NULL for those rows,
-- so they don't count as a match, and EXISTS itself is only ever
-- true or false.

-- ---- 4.3 The trap: the correlation you forgot ----
-- "Which customers gave us a 1-star rating?" (apology email list)
-- RIGHT:
SELECT c.customerID, c.firstName, c.lastName
FROM customers c
WHERE EXISTS (SELECT 1 FROM orders o
              WHERE o.customerID = c.customerID
                AND o.rating = 1)
ORDER BY c.customerID;
-- customerid | firstname | lastname
-- 4 | Tigran    | Grigoryan
-- 6 | Narek     | Manukyan
-- 14 | Vahan     | Torosyan
-- 25 | Hasmik    | Zakaryan

-- WRONG: the line that ties the subquery to c is missing.
SELECT count(*) AS customers
FROM customers c
WHERE EXISTS (SELECT 1 FROM orders o
              WHERE o.rating = 1);
-- WRONG: 30. The subquery no longer mentions c, so it gives the same
-- answer for every customer: "does ANY 1-star order exist?" Yes. All
-- 30 customers pass -- including Levon and Astghik, who never ordered.

-- WRONG, the way it happens in real code: the correlation is THERE,
-- but unqualified. Inside the subquery, customerID means
-- orders.customerID on both sides, so this compares a column to itself.
SELECT count(*) AS customers
FROM customers c
WHERE EXISTS (SELECT 1 FROM orders
              WHERE customerID = customerID
                AND rating = 1);
-- WRONG: 30, same as above.

-- The same rule, nastier: a column that isn't in the subquery's table
-- at all. orders has no productID any more (it moved to order_items),
-- so inside this subquery "productID" can only mean the OUTER
-- products.productID. No error -- the query compares each product with
-- itself, once per order:
SELECT count(*) AS never_ordered
FROM products
WHERE productID NOT IN (SELECT productID FROM orders);
-- WRONG: 0 -- and Ergonomic Chair Pro has never been ordered.
-- Qualify every column in a subquery (o.productID would have errored:
-- column o.productid does not exist), and the mistake becomes loud.

-- With NOT EXISTS the same slip goes the other way.
-- "Customers who have never given us 1 star" -- WRONG:
SELECT count(*) AS customers
FROM customers c
WHERE NOT EXISTS (SELECT 1 FROM orders o
                  WHERE o.rating = 1);
-- WRONG: 0

-- RIGHT:
SELECT count(*) AS customers
FROM customers c
WHERE NOT EXISTS (SELECT 1 FROM orders o
                  WHERE o.customerID = c.customerID
                    AND o.rating = 1);
-- customers
-- 26
-- Check: 4 + 26 = 30. All or nothing (30 or 0) is the tell.



-- ============================================================
-- Lecture 5 — Part 5: From subqueries to CTEs
-- Run after Part 4.
-- ============================================================

-- ---- 5.1 The same derived table, with a name ----
-- Part 1.4, rewritten. Read it top to bottom instead of inside out.
WITH per_customer AS (
    SELECT customerID, count(*) AS order_count
    FROM orders
    GROUP BY customerID
)
SELECT c.firstName, c.lastName, pc.order_count
FROM per_customer pc
JOIN customers c ON c.customerID = pc.customerID
WHERE pc.order_count >= 40
ORDER BY pc.order_count DESC;
-- firstname | lastname    | order_count
-- Davit     | Petrosyan   |          52
-- Armen     | Gevorgyan   |          48
-- Karen     | Khachatryan |          41
-- Aram      | Vardanyan   |          40
-- Same 4 rows as Part 1.4.

-- ---- 5.2 Several CTEs; a later one reads an earlier one ----
-- "Customers who order more often than the average customer"
WITH per_customer AS (
    SELECT customerID, count(*) AS order_count
    FROM orders
    GROUP BY customerID
),
overall AS (
    SELECT avg(order_count) AS avg_count
    FROM per_customer                       -- reads the CTE above
)
SELECT c.firstName, c.lastName, pc.order_count,
       round(ov.avg_count, 2) AS avg_count
FROM per_customer pc
CROSS JOIN overall ov                       -- one row, so no fan-out
JOIN customers c ON c.customerID = pc.customerID
WHERE pc.order_count > ov.avg_count
ORDER BY pc.order_count DESC;
-- 12 rows, Davit 52 down to Tigran Grigoryan 22; avg_count 21.43 on
-- every row (Part 1.4's number).

-- ---- 5.3 THE TRAP: fan-out in CTE clothing (callback: Lecture 4, 4.10) ----
-- "For each city: completed orders, and average spend per customer."
-- customer_spend is one row per customer (customer grain). Joining it
-- to orders (order grain) copies each customer's 'spent' onto every one
-- of their orders.
--
-- This is the same bug as Lecture 4's SUM(customers.moneySpent) fan-out
-- -- CTEs don't prevent it, they just make the mistake easier to not
-- notice because the query reads so cleanly.
WITH customer_spend AS (
    SELECT customerID, sum(orderTotal) AS spent
    FROM orders
    WHERE status = 'completed'
    GROUP BY customerID
)
SELECT c.city,
       count(o.orderID)        AS orders,
       round(avg(cs.spent), 2) AS avg_customer_spend
FROM customers c
JOIN customer_spend cs ON cs.customerID = c.customerID
JOIN orders o          ON o.customerID  = c.customerID
                      AND o.status = 'completed'
GROUP BY c.city
ORDER BY avg_customer_spend DESC;
-- WRONG (orders column is right; the average is not):
-- city     | orders | avg_customer_spend
-- Abovyan  |     29 |            8507.37
-- Gyumri   |    181 |            7908.41
-- Yerevan  |    280 |            7063.81
-- Vanadzor |     39 |            5976.08
-- Every number is believable. That's the problem.

-- CHECK 1 -- add the spend back up. It must be 157078.41 (Part 2.3).
WITH customer_spend AS (
    SELECT customerID, sum(orderTotal) AS spent
    FROM orders
    WHERE status = 'completed'
    GROUP BY customerID
)
SELECT sum(cs.spent)                  AS total_spend,
       count(*)                       AS rows,
       count(DISTINCT cs.customerID)  AS customers
FROM customer_spend cs
JOIN orders o ON o.customerID = cs.customerID
             AND o.status = 'completed';
-- total_spend | rows | customers
-- 3889069.12 |  529 |        28
-- 529 rows for 28 customers: each customer's total was counted once
-- per completed order. The average was weighted the same way, toward
-- the customers with the most orders.

-- FIX -- keep everything at customer grain: count the orders in the
-- CTE too, and never join back to orders.
WITH customer_spend AS (
    SELECT customerID,
           count(*)        AS orders,
           sum(orderTotal) AS spent
    FROM orders
    WHERE status = 'completed'
    GROUP BY customerID
)
SELECT c.city,
       sum(cs.orders)          AS orders,
       round(avg(cs.spent), 2) AS avg_customer_spend
FROM customers c
JOIN customer_spend cs ON cs.customerID = c.customerID
GROUP BY c.city
ORDER BY avg_customer_spend DESC;
-- city     | orders | avg_customer_spend
-- Gyumri   |    181 |            6714.16
-- Abovyan  |     29 |            6136.27
-- Yerevan  |    280 |            5189.36
-- Vanadzor |     39 |            4793.83
-- Different winner: Gyumri, not Abovyan.

-- CHECK 2 -- the fixed CTE adds up to the known total:
WITH customer_spend AS (
    SELECT customerID, sum(orderTotal) AS spent
    FROM orders
    WHERE status = 'completed'
    GROUP BY customerID
)
SELECT sum(spent) AS total_spend, count(*) AS customers
FROM customer_spend;
-- total_spend | customers
-- 157078.41 |        28

-- ---- 5.4 The trap: ORDER BY inside the CTE ----
-- "Top 5 customers by spend". The sorting is done -- inside the CTE.
WITH top_spenders AS (
    SELECT customerID, sum(orderTotal) AS spent
    FROM orders
    WHERE status = 'completed'
    GROUP BY customerID
    ORDER BY spent DESC
)
SELECT c.firstName, c.lastName, t.spent
FROM top_spenders t
JOIN customers c ON c.customerID = t.customerID
LIMIT 5;
-- WRONG (PostgreSQL 16 on this data):
-- firstname | lastname  | spent
-- Anna      | Sargsyan  | 6651.60
-- Davit     | Petrosyan | 8838.85
-- Mariam    | Hakobyan  | 4084.22
-- Tigran    | Grigoryan | 5762.87
-- Lusine    | Avetisyan | 2861.90
-- These are customers 1-5 in customerID order. The join re-read the
-- rows in its own order, and LIMIT took the first five of THAT.
-- Read the spent column: it isn't even descending.

-- FIX -- ORDER BY belongs to the query whose output you look at:
WITH top_spenders AS (
    SELECT customerID, sum(orderTotal) AS spent
    FROM orders
    WHERE status = 'completed'
    GROUP BY customerID
)
SELECT c.firstName, c.lastName, t.spent
FROM top_spenders t
JOIN customers c ON c.customerID = t.customerID
ORDER BY t.spent DESC
LIMIT 5;
-- firstname | lastname     | spent
-- Aram      | Vardanyan    | 14625.38
-- Artur     | Baghdasaryan | 11235.95
-- Armen     | Gevorgyan    | 10028.09
-- Lilit     | Hovhannisyan |  9410.64
-- Vahan     | Torosyan     |  8925.87
-- Not one name in common with the wrong list.



-- ============================================================
-- Lecture 5 — Part 6: Recursive CTEs (a preview)
-- Run after Part 5.
-- ============================================================

-- ---- 6.1 Lecture 4's two-hop self-join ----
SELECT e.firstName AS employee, m.firstName AS manager, mm.firstName AS managers_manager
FROM employees e
LEFT JOIN employees m  ON m.employeeID  = e.managerID
LEFT JOIN employees mm ON mm.employeeID = m.managerID
WHERE e.firstName = 'Nare';
-- employee | manager | managers_manager
-- Nare     | Hayk    | Vahe
-- Two hops reach the top, because the shop's chart is only 3 deep.

-- ---- 6.2 Add one level and the self-join falls short ----
-- HYPOTHETICAL: a trainee, Sevak, reporting to Nare. He is not in the
-- data -- the staff CTE adds him for this query only; nothing is saved.
WITH staff AS (
    SELECT employeeID, firstName, position, managerID FROM employees
  UNION ALL
    SELECT 9, 'Sevak', 'Trainee', 4                -- 4 = Nare
)
SELECT e.firstName AS employee, m.firstName AS manager, mm.firstName AS managers_manager
FROM staff e
LEFT JOIN staff m  ON m.employeeID  = e.managerID
LEFT JOIN staff mm ON mm.employeeID = m.managerID
WHERE e.firstName = 'Sevak';
-- employee | manager | managers_manager
-- Sevak    | Nare    | Hayk
-- Vahe is missing, and nothing says so. A third hop needs a third
-- join; a fourth level needs a fourth. The query hard-codes the depth.

-- ---- 6.3 WITH RECURSIVE: keep hopping until there's no manager ----
WITH RECURSIVE staff AS (
    SELECT employeeID, firstName, position, managerID FROM employees
  UNION ALL
    SELECT 9, 'Sevak', 'Trainee', 4
),
chain AS (
    -- start: the employee himself
    SELECT employeeID, firstName, position, managerID, 1 AS level
    FROM staff
    WHERE firstName = 'Sevak'
  UNION ALL
    -- step: the manager of whoever we found last time
    SELECT m.employeeID, m.firstName, m.position, m.managerID, c.level + 1
    FROM staff m
    JOIN chain c ON m.employeeID = c.managerID
)
SELECT level, firstName, position
FROM chain
ORDER BY level;
-- level | firstname | position
-- 1 | Sevak     | Trainee
-- 2 | Nare      | Sales Associate
-- 3 | Hayk      | Senior Sales
-- 4 | Vahe      | Store Manager
-- Stops by itself: Vahe's managerID is NULL, the step finds no row.

-- The real chart (no Sevak), top down, every level at once:
WITH RECURSIVE org AS (
    SELECT employeeID, firstName, managerID, 1 AS level,
           firstName::text AS path
    FROM employees
    WHERE managerID IS NULL
  UNION ALL
    SELECT e.employeeID, e.firstName, e.managerID, o.level + 1,
           o.path || ' > ' || e.firstName
    FROM employees e
    JOIN org o ON e.managerID = o.employeeID
)
SELECT level, path
FROM org
ORDER BY path;
-- level | path
-- 1 | Vahe
-- 2 | Vahe > Ani
-- 2 | Vahe > Gor
-- 2 | Vahe > Hayk
-- 3 | Vahe > Hayk > Lilit
-- 3 | Vahe > Hayk > Nare
-- 2 | Vahe > Marine
-- 3 | Vahe > Marine > Arman



-- ============================================================
-- Lecture 5 — Part 7: Verification drill
-- Run after Part 6. Four queries that run, look fine, and are wrong.
-- For each one: which check from the notes catches it?
-- ============================================================

SELECT e.firstName
FROM employees e
WHERE e.employeeID NOT IN (SELECT employeeID FROM orders WHERE rating = 1);
-- "Salespeople who never got a 1-star rating": 0 rows

SELECT count(*) AS returners
FROM customers c
WHERE EXISTS (SELECT 1 FROM orders WHERE customerID = customerID AND status = 'returned');
-- "Customers who returned something": 30

WITH customer_orders AS (
    SELECT customerID, count(*) AS order_count
    FROM orders
    GROUP BY customerID
)
SELECT sum(co.order_count) AS total_orders
FROM customer_orders co
JOIN orders o ON o.customerID = co.customerID;
-- "Total orders": 17778

WITH ranked AS (
    SELECT productID, count(*) AS times_ordered
    FROM order_items
    GROUP BY productID
    ORDER BY times_ordered DESC
)
SELECT p.productName, r.times_ordered
FROM ranked r
JOIN products p ON p.productID = r.productID
LIMIT 3;
-- "Top 3 products": ThinkPad X1 Carbon 19, Laptop Sleeve 14 27, MX Keys 37

-- ---- Answers ----
-- 1. NOT IN + NULL: the 1-star list holds the online order's NULL.
SELECT count(*) AS one_star, count(employeeID) AS with_an_employee
FROM orders WHERE rating = 1;
-- one_star | with_an_employee
-- 5 |                4

SELECT e.firstName
FROM employees e
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.employeeID = e.employeeID AND o.rating = 1)
ORDER BY e.employeeID;
-- 5 rows: Ani, Nare, Hayk, Lilit, Marine

-- 2. Missing correlation: 30 includes Levon and Astghik, who never ordered.
SELECT count(*) AS returners
FROM customers c
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customerID = c.customerID AND o.status = 'returned');
-- returners
-- 22

-- 3. Fan-out: you know the total is 600.
SELECT count(*) AS total_orders FROM orders;
-- 600

-- 4. ORDER BY in the CTE: the times_ordered column isn't descending.
SELECT p.productName, count(*) AS times_ordered
FROM order_items i
JOIN products p ON p.productID = i.productID
GROUP BY p.productID, p.productName
ORDER BY times_ordered DESC, p.productName
LIMIT 3;
-- productname       | times_ordered
-- USB-C Cable 1m    |           128
-- HDMI 2.1 Cable 2m |            85
-- USB Flash 128GB   |            82
