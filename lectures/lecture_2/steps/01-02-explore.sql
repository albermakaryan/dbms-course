-- ============================================================
-- Lecture 2 — Part 1b: find the problem  (queries only)
-- Assumes 01-01-load.sql has run. Re-run this file as often as
-- you like -- it changes nothing.
-- ============================================================

SELECT * FROM sales_raw ORDER BY orderDate, orderID LIMIT 10;


-- Guess before you run: how many customers does this shop have?
SELECT count(*)                         AS total_rows     FROM sales_raw;  -- 42
SELECT count(DISTINCT customerLastName) AS real_customers FROM sales_raw;  -- 8
SELECT count(DISTINCT productCategory)  AS real_products  FROM sales_raw;  -- 6

-- 42 rows, 8 customers. Davit's birth date is stored eight times.
SELECT customerFirstName, customerLastName, count(*) AS times_stored
FROM sales_raw
GROUP BY customerFirstName, customerLastName
ORDER BY times_stored DESC;

-- Talk through before moving on:
--   wrong birth date entered  -> fix EVERY copy      (update anomaly)
--   miss one copy             -> two "truths"        (INCONSISTENCY)
--   new category, no sales    -> nowhere to put it   (insertion anomaly)
--   delete last order in cat. -> category vanishes   (deletion anomaly)
