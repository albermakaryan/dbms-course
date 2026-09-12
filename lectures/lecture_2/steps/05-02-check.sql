-- ============================================================
-- Lecture 2 — Part 5b: check the split  (queries only)
-- Assumes 05-01-insert.sql has run. Safe to re-run any time.
-- ============================================================

-- Expect 42 / 8 / 4 / 6 / 42
SELECT 'sales_raw' AS t, count(*) FROM sales_raw
UNION ALL SELECT 'customers', count(*) FROM customers
UNION ALL SELECT 'employees', count(*) FROM employees
UNION ALL SELECT 'products',  count(*) FROM products
UNION ALL SELECT 'orders',    count(*) FROM orders;

-- If orders isn't 42, the join is wrong somewhere -- walk the
-- join conditions in 05-01-insert.sql against sales_raw to find it.

-- Compare against the expected files in data/:
--   customers.csv (8), employees.csv (4), products.csv (6), orders.csv (42)
SELECT * FROM customers ORDER BY customerID;
SELECT * FROM products  ORDER BY productID;
