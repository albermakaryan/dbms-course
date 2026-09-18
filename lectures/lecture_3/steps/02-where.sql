-- ============================================================
-- Lecture 3 — Part 2: WHERE, properly
-- Run after Part 1.
-- ============================================================

-- ---- Equality. Text is case-sensitive. ----
SELECT orderID, productName, orderTotal FROM sales WHERE productCategory = 'Laptops' LIMIT 5;

SELECT count(*) FROM sales WHERE productCategory = 'Laptops';    -- 51
SELECT count(*) FROM sales WHERE productCategory = 'laptops';    -- 0. Not an error. Zero rows.

-- ---- Comparison ----
SELECT count(*) FROM sales WHERE status <> 'completed';          -- 71  (<> means "not equal"; != also works)
SELECT count(*) FROM sales WHERE orderTotal >= 1000;             -- 34
SELECT count(*) FROM sales WHERE orderDate >= '2024-12-01';      -- 86  (dates compare like numbers)

-- ---- BETWEEN is inclusive on both ends ----
SELECT count(*) FROM sales WHERE orderTotal BETWEEN 100 AND 200;                        -- 88
SELECT count(*) FROM sales WHERE orderDate  BETWEEN '2024-12-01' AND '2024-12-31';      -- 86

-- ---- IN: any of these ----
SELECT count(*) FROM sales WHERE productCategory IN ('Laptops', 'Phones', 'Tablets');   -- 126

SELECT productName, brand, price
FROM products
WHERE brand IN ('Apple', 'Samsung')
ORDER BY price DESC;

-- ---- LIKE: patterns. % = anything, _ = exactly one character ----
SELECT DISTINCT customerLastName FROM sales WHERE customerLastName LIKE 'S%';   -- starts with S
SELECT count(*) FROM sales WHERE customerEmail LIKE '%@gmail.com';              -- 378
SELECT firstName, lastName FROM customers WHERE firstName LIKE 'A__';           -- exactly three letters

-- LIKE is case-sensitive too. ILIKE isn't.
SELECT productName FROM products WHERE productName LIKE  '%usb%';    -- 0 rows
SELECT productName FROM products WHERE productName ILIKE '%usb%';    -- 3 rows

-- ---- AND, OR, NOT ----
SELECT count(*) FROM sales WHERE channel = 'online' AND status = 'completed';   -- 164
SELECT count(*) FROM sales WHERE NOT status = 'completed';                       -- 71, same as <>
SELECT count(*) FROM sales WHERE productCategory NOT IN ('Cables', 'Accessories');   -- 416

-- ---- The precedence trap: AND binds tighter than OR ----
-- "Laptops or phones, over 1000"?
SELECT count(*) FROM sales
WHERE productCategory = 'Laptops' OR productCategory = 'Phones' AND orderTotal > 1000;
-- 55

-- That was read as:  Laptops  OR  (Phones AND > 1000).  Every laptop got in.
SELECT count(*) FROM sales
WHERE productCategory = 'Laptops' OR (productCategory = 'Phones' AND orderTotal > 1000);
-- 55 -- identical. This is what you wrote, whether you meant it or not.

-- What you meant:
SELECT count(*) FROM sales
WHERE (productCategory = 'Laptops' OR productCategory = 'Phones') AND orderTotal > 1000;
-- 33

-- Rule: the moment AND and OR share a WHERE, put parentheses. Every time.

-- ---- A BOOLEAN column is already a condition ----
SELECT productName FROM products WHERE NOT isActive;    -- K380: discontinued
SELECT count(*)    FROM products WHERE isActive;        -- 36

-- ---- NULL ----
SELECT firstName, lastName, anniversary FROM customers WHERE anniversary = NULL;
-- 0 rows. NOT an error. Nothing is "= NULL" -- not even NULL.

SELECT firstName, lastName FROM customers WHERE anniversary IS NULL;        -- 7 rows
SELECT count(*)            FROM customers WHERE anniversary IS NOT NULL;    -- 23

-- Online orders have no salesperson:
SELECT count(*) FROM sales WHERE employeeLastName IS NULL;                   -- 181

-- A comparison with NULL is neither true nor false, so WHERE drops the row.
-- deliveryDate is NULL for every in-store order, so only online ones can pass:
SELECT count(*) FROM sales WHERE deliveryDate - orderDate > 3;               -- 93

-- ---- Conditions on expressions ----
SELECT count(*) FROM sales WHERE EXTRACT(MONTH FROM orderDate) = 12;         -- 86
SELECT count(*) FROM sales WHERE quantity * unitPrice - orderTotal > 100;    -- 10: discounts over 100

-- ---- The alias rule, proven ----
SELECT orderID, quantity * unitPrice AS list_total
FROM sales
WHERE list_total > 2000;
-- ERROR: column "list_total" does not exist
-- WHERE runs BEFORE SELECT invents the alias. Repeat the expression:
SELECT orderID, quantity * unitPrice AS list_total
FROM sales
WHERE quantity * unitPrice > 2000;
