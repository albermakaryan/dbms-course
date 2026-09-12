-- ============================================================
-- Lecture 2 — Part 8: Watch the database say NO
-- Run each one at a time and read the actual error message.
-- ============================================================

-- 1. an order for a customer who does not exist
INSERT INTO orders VALUES (9999, 999, 1, 1, 100.00, '2024-08-15');
-- ERROR: violates foreign key constraint (no customer 999)

-- 2. a negative price
INSERT INTO products (category, price) VALUES ('Broken', -50);
-- ERROR: violates check constraint "products_price_check"

-- 3. a duplicate category
INSERT INTO products (category, price) VALUES ('Laptops', 999.00);
-- ERROR: duplicate key value violates unique constraint

-- A spreadsheet would have accepted all three, silently. That is
-- the difference between a file and a database.
