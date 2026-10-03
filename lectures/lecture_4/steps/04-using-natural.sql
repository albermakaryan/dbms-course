-- ============================================================
-- Lecture 4 — Joins, step 4: USING, and why NATURAL JOIN is dangerous
-- Notes: Part 4.4
-- Run after steps/00-setup.sql. Read-only: safe to re-run.
-- ============================================================


-- ---- 1. USING: shorthand when the key has the same name on both sides ----
-- USING (customerID)  means  ON o.customerID = c.customerID
SELECT customerID, c.firstName, o.orderID
FROM orders o
JOIN customers c USING (customerID)
WHERE o.orderID = 1001;
-- Bonus: USING merges the two customerID columns into ONE output
-- column, so the bare "customerID" in SELECT is no longer ambiguous
-- (compare step 3's error).


-- ---- 2. NATURAL JOIN: joins on every shared column name ----
-- sales is the flat file: one row per order LINE, with the order's
-- columns copied onto each line. Joined honestly on orderID, every line
-- finds its order:
SELECT count(*) FROM orders o JOIN sales s ON s.orderID = o.orderID;
-- Guess first: what does NATURAL JOIN give?
SELECT count(*) FROM orders NATURAL JOIN sales;


-- ---- 3. Why so few? See which columns it silently joined on ----
-- NATURAL JOIN uses EVERY column name the two tables share:
SELECT column_name FROM information_schema.columns WHERE table_name = 'orders'
INTERSECT
SELECT column_name FROM information_schema.columns WHERE table_name = 'sales'
ORDER BY 1;
-- All nine had to be equal. deliveryDate is NULL for every in-store
-- order, rating is NULL for many orders — and NULL = NULL is not true
-- (Lecture 3's NULL rule). Any row with a NULL in any of the nine is
-- thrown out. The survivors are the lines of online orders that also
-- got a rating:
SELECT count(*)
FROM sales
WHERE deliveryDate IS NOT NULL
  AND rating IS NOT NULL;


-- ---- The one-line takeaway ----
-- The join condition should always be visible in the code you read.
-- NATURAL JOIN hides it — and it changes by itself, without warning,
-- the day either table gains a new column with a matching name.
-- Never use it in real code. Write ON, or USING when the names match.
