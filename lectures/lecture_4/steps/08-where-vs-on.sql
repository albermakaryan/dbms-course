-- ============================================================
-- Lecture 4 — Joins, step 8: the WHERE-vs-ON trap
-- Notes: Part 4.7 — the most important trap in the lecture
-- Run after steps/00-setup.sql. Read-only: safe to re-run.
--
-- With inner joins it doesn't matter whether a condition sits in ON
-- or in WHERE. With outer joins it matters completely, because of
-- WHEN each one runs:
--   ON     applies while deciding what matches — before the outer join
--          NULL-pads the unmatched rows.
--   WHERE  applies after the whole join, NULL-padding included — so it
--          can delete the very rows the LEFT JOIN just protected.
--
-- "ON decides who gets invited to the party. WHERE decides who's
--  allowed to stay after it already happened — including the guests
--  the LEFT JOIN invited for free (the NULL-padded ones)."
-- ============================================================


-- ---- 1. Revenue per category, including categories that sold nothing ----
SELECT p.category, count(o.orderID) AS orders, sum(o.orderTotal) AS revenue
FROM products p
LEFT JOIN orders o ON o.productID = p.productID
GROUP BY p.category
ORDER BY revenue DESC NULLS LAST;
-- Look for Chairs: it never sold, but the LEFT JOIN keeps it.


-- ---- 2. The boss adds "completed orders only". The obvious edit: ----
SELECT p.category, count(o.orderID) AS orders, sum(o.orderTotal) AS revenue
FROM products p
LEFT JOIN orders o ON o.productID = p.productID
WHERE o.status = 'completed'
GROUP BY p.category
ORDER BY revenue DESC NULLS LAST;
-- Walk the order: the LEFT JOIN runs first and keeps the Chair row,
-- with o.status NULL. Then WHERE runs: NULL = 'completed' is not true,
-- so the Chair row is thrown out along with the genuinely
-- non-completed rows. The LEFT JOIN has quietly become an INNER JOIN.


-- ---- 3. Move the same condition into ON ----
SELECT p.category, count(o.orderID) AS orders, coalesce(sum(o.orderTotal), 0) AS revenue
FROM products p
LEFT JOIN orders o ON o.productID = p.productID
                  AND o.status = 'completed'
GROUP BY p.category
ORDER BY revenue DESC;
-- Now the status test only decides which orders count as a MATCH.
-- The Chair has no completed match, so it is NULL-padded and kept.
-- (coalesce turns the NULL sum into 0: sum of no rows is NULL.)


-- ---- 4. The other half of the rule: left-table conditions ----
-- Intent: "Gyumri customers and their orders."
-- Wrong: the left-table condition placed in ON.
SELECT count(*) AS rows, count(o.orderID) AS matched
FROM customers c
LEFT JOIN orders o ON o.customerID = c.customerID
                  AND c.city = 'Gyumri';
-- A LEFT JOIN keeps EVERY left row, so every customer is still there:
-- the Gyumri customers with their orders, plus one NULL-padded row
-- for each customer from anywhere else.

-- Right: the left-table condition in WHERE.
SELECT count(*) AS rows, count(o.orderID) AS matched
FROM customers c
LEFT JOIN orders o ON o.customerID = c.customerID
WHERE c.city = 'Gyumri';


-- ---- The rule to remember ----
--   conditions on the RIGHT table of a LEFT JOIN  ->  ON
--   conditions on the LEFT table                  ->  WHERE
-- A WHERE that mentions the right-hand table after a LEFT JOIN should
-- always make you stop and ask: am I filtering matches, or un-inviting
-- the rows my LEFT JOIN was supposed to protect?
