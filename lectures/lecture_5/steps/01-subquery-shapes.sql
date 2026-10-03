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
