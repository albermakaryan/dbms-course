-- ============================================================
-- Lecture 4 — Joins, step 5: LEFT, RIGHT and FULL outer joins
-- Notes: Part 4.5
-- Run after steps/00-setup.sql. Read-only: safe to re-run.
--
-- Build it up as: INNER JOIN, but we refuse to lose rows from one
-- side (or both). Where a row has no partner, keep it anyway and fill
-- the missing side with NULLs.
-- ============================================================


-- ---- 1. LEFT JOIN: every row of the LEFT table, at least once ----
-- "Left" = the table written before the word JOIN.
SELECT o.orderID, o.channel, e.firstName, e.branch
FROM orders o
LEFT JOIN employees e ON e.employeeID = o.employeeID
WHERE o.orderID BETWEEN 1001 AND 1008
ORDER BY o.orderID;

SELECT count(*)
FROM orders o
LEFT JOIN employees e ON e.employeeID = o.employeeID;


-- ---- 2. Give the NULLs a name, and the lost revenue comes back ----
SELECT coalesce(e.branch, 'Online') AS branch,
       count(*)                     AS orders,
       sum(o.orderTotal)            AS revenue
FROM orders o
LEFT JOIN employees e ON e.employeeID = o.employeeID
WHERE o.status = 'completed'
GROUP BY coalesce(e.branch, 'Online')
ORDER BY revenue DESC;


-- ---- 3. RIGHT JOIN: the mirror image ----
-- A RIGHT JOIN B keeps every row of B — which makes it B LEFT JOIN A.
SELECT count(*)
FROM orders o
RIGHT JOIN customers c ON c.customerID = o.customerID;

SELECT count(*)
FROM customers c
LEFT JOIN orders o ON o.customerID = c.customerID;
-- Why 602 and not 600? Two customers have no orders; each is kept as
-- one NULL-padded row. Step 6 finds them. This course always writes
-- LEFT (put the table you want to keep first) so every query reads
-- the same way. Know RIGHT for when you meet it in someone else's code.


-- ---- 4. FULL JOIN: keep everything from both sides ----
-- LEFT and RIGHT combined. Its classic use is reconciling two lists.
-- Here: compare the customer list with the staff list, by name.
SELECT CASE WHEN e.employeeID IS NULL THEN 'customer only'
            WHEN c.customerID IS NULL THEN 'employee only'
            ELSE 'on both lists' END AS status,
       count(*) AS people
FROM customers c
FULL JOIN employees e ON e.firstName = c.firstName AND e.lastName = c.lastName
GROUP BY 1
ORDER BY 1;
-- 28 + 6 + 2 = 36: the 30 customers and 8 employees, with the matched
-- pairs counted once. Hold on to those 2 "on both lists" — step 10
-- asks who they really are.
