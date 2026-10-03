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
-- Revenue lives on the lines (lineTotal), so go products -> lines.
SELECT p.category, count(i.orderID) AS lines, sum(i.lineTotal) AS revenue
FROM products p
LEFT JOIN order_items i ON i.productID = p.productID
GROUP BY p.category
ORDER BY revenue DESC NULLS LAST;
-- Look for Chairs: it never sold, but the LEFT JOIN keeps it.


-- ---- 2. The boss adds "completed orders only". The obvious edit: ----
-- status lives on the order header, so join orders too, and filter:
SELECT p.category, count(i.orderID) AS lines, sum(i.lineTotal) AS revenue
FROM products p
LEFT JOIN order_items i ON i.productID = p.productID
LEFT JOIN orders      o ON o.orderID   = i.orderID
WHERE o.status = 'completed'
GROUP BY p.category
ORDER BY revenue DESC NULLS LAST;
-- Walk the order: the LEFT JOINs run first and keep the Chair row,
-- with o.status NULL. Then WHERE runs: NULL = 'completed' is not true,
-- so the Chair row is thrown out along with the genuinely
-- non-completed rows. The LEFT JOIN has quietly become an INNER JOIN.


-- ---- 3. Move the condition into ON — but which ON? ----
-- First attempt: into the ON of the orders join.
SELECT p.category, count(i.orderID) AS lines, coalesce(sum(i.lineTotal), 0) AS revenue
FROM products p
LEFT JOIN order_items i ON i.productID = p.productID
LEFT JOIN orders      o ON o.orderID   = i.orderID
                       AND o.status    = 'completed'
GROUP BY p.category
ORDER BY revenue DESC;
-- Chairs is back. But compare the revenue with query 2: it went UP.
-- The status test now only decides whether a line finds its ORDER.
-- A line of a returned order still exists — it just gets NULL order
-- columns — and its lineTotal is still summed. This is part 1's
-- all-orders revenue again, wearing a "completed" label.


-- ---- 4. The fix: decide what counts as a match BEFORE the LEFT JOIN ----
-- A product's match is "a line of a completed order". Build exactly
-- that inside the brackets (an inner join: lines + their completed
-- order), then LEFT JOIN products to the result.
SELECT p.category, count(i.orderID) AS lines, coalesce(sum(i.lineTotal), 0) AS revenue
FROM products p
LEFT JOIN (order_items i
           JOIN orders o ON o.orderID = i.orderID
                        AND o.status  = 'completed')
       ON i.productID = p.productID
GROUP BY p.category
ORDER BY revenue DESC;
-- Every category from query 2 with the same revenue, AND Chairs at 0.
-- (coalesce turns the NULL sum into 0: sum of no rows is NULL.)
-- With one LEFT JOIN, "move it into ON" is the whole fix. With a chain
-- of joins, ask which join the condition belongs to.


-- ---- 5. The other half of the rule: left-table conditions ----
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
