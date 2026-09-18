-- ============================================================
-- Lecture 3 — Part 3: ORDER BY, LIMIT, OFFSET
-- Run after Part 2.
-- ============================================================

-- ---- ASC is the default ----
SELECT productName, price FROM products ORDER BY price;
SELECT productName, price FROM products ORDER BY price DESC LIMIT 5;

-- ---- Several columns: the second breaks ties in the first ----
SELECT productName, category, price
FROM products
ORDER BY category, price DESC;

-- Text sorts alphabetically. Watch the two Annas land next to each other.
SELECT lastName, firstName, city, birthDate
FROM customers
ORDER BY lastName, firstName;

-- ---- Sort by an expression, an alias, or a position ----
SELECT productName, price - cost AS margin
FROM products
ORDER BY margin DESC                      -- alias works here: ORDER BY runs AFTER SELECT
LIMIT 5;

SELECT productName, price, cost
FROM products
ORDER BY (price - cost) / price DESC      -- an expression that isn't even in SELECT
LIMIT 5;

SELECT productName, price FROM products ORDER BY 2 DESC LIMIT 3;   -- "column 2". Works. Fragile.

-- ---- NULLs sort as if they were bigger than everything ----
SELECT firstName, lastName, anniversary FROM customers ORDER BY anniversary;        -- NULLs at the END
SELECT firstName, lastName, anniversary FROM customers ORDER BY anniversary DESC;   -- NULLs FIRST
SELECT firstName, lastName, anniversary FROM customers ORDER BY anniversary DESC NULLS LAST;

-- ---- LIMIT without ORDER BY is not "the first five" ----
SELECT orderID, orderDate FROM sales LIMIT 5;
-- Whatever five rows the database happened to reach first. Not the
-- earliest, not the smallest ids. Different next week, maybe.

SELECT orderID, orderDate, orderTime FROM sales ORDER BY orderDate, orderTime LIMIT 5;
-- 1001..1005: the actual first five sales of the year.

-- ---- Ties: say how to break them, or the database decides ----
SELECT orderID, orderTotal FROM sales ORDER BY orderTotal DESC LIMIT 3;
-- three orders at 2500.00 -- fine, all three fit. Now ask for two:
SELECT orderID, orderTotal FROM sales ORDER BY orderTotal DESC LIMIT 2;
-- WHICH two? Unspecified. Add a tiebreaker:
SELECT orderID, orderTotal FROM sales ORDER BY orderTotal DESC, orderID LIMIT 2;

-- ---- OFFSET: skip some, then take some ----
SELECT orderID, orderTotal FROM sales ORDER BY orderTotal DESC, orderID LIMIT 5 OFFSET 5;   -- ranks 6-10

-- ---- Putting it together: top five December sales ----
SELECT orderID, orderDate, customerLastName, productName, orderTotal
FROM sales
WHERE EXTRACT(MONTH FROM orderDate) = 12 AND status = 'completed'
ORDER BY orderTotal DESC, orderID
LIMIT 5;
