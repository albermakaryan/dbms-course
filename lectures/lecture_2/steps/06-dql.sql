-- ============================================================
-- Lecture 2 — Part 6: DQL — first queries
-- ============================================================

SELECT * FROM customers;                                    -- everything

SELECT firstName, lastName, birthDate FROM customers;       -- choose columns

SELECT * FROM customers WHERE birthDate < '1990-01-01';     -- choose rows

SELECT * FROM products  WHERE price > 100;

SELECT * FROM products  ORDER BY price DESC;

SELECT * FROM orders    ORDER BY orderDate DESC LIMIT 5;

SELECT * FROM customers WHERE moneySpent > 3000
                          AND birthDate < '1995-01-01';

SELECT DISTINCT category FROM products;

-- FROM which table -> WHERE which rows -> SELECT which columns
-- -> ORDER BY what order -> LIMIT how many.
