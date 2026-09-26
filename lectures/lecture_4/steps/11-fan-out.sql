-- ============================================================
-- Lecture 4 — Joins, step 11: the fan-out trap
-- Notes: Part 4.10 — the most damaging trap, because the number
-- looks completely normal
-- Run after steps/00-setup.sql. Read-only: safe to re-run.
--
-- It needs no outer join and no strange join type. A completely
-- ordinary inner join breaks it.
-- ============================================================


-- ---- 1. The question: total lifetime spend of our customers ----
-- customers.moneySpent is one number per customer (customer grain).
-- Someone joins orders "to make sure we only count real buyers":
SELECT sum(c.moneySpent) AS total_customer_spend
FROM customers c
JOIN orders o ON o.customerID = c.customerID;
-- Ask the room: does that look plausible? Nothing is red. No error.


-- ---- 2. The real total ----
SELECT sum(moneySpent) AS total_customer_spend
FROM customers;


-- ---- 3. Why: one value copied onto every matching row ----
-- orders has many rows per customer (order grain). The join copies
-- each customer's moneySpent onto EVERY one of their order rows — not
-- divided, not split, copied whole. Look at one customer:
SELECT c.firstName, c.lastName, c.moneySpent,
       count(*)          AS rows_after_join,
       sum(c.moneySpent) AS summed_after_join
FROM customers c
JOIN orders o ON o.customerID = c.customerID
WHERE c.customerID = 8
GROUP BY c.customerID, c.firstName, c.lastName, c.moneySpent;
-- Compare moneySpent with summed_after_join: the same value, added
-- once for every order he placed.


-- ---- 4. The proof: count before you sum ----
SELECT count(*)                     AS rows,
       count(DISTINCT c.customerID) AS customers
FROM customers c
JOIN orders o ON o.customerID = c.customerID;
-- Compare the two counts: how many rows are being summed, and how
-- many real customers are behind them.


-- ---- 5. The fix, in general ----
-- (a) Don't join at all if you already have the summary value:
SELECT sum(moneySpent) FROM customers;

-- (b) Or aggregate the fine-grain table FIRST, then join the result
--     back — one row per customer, so nothing can be copied:
SELECT sum(per_customer.spent) AS total_customer_spend
FROM (SELECT customerID, sum(orderTotal) AS spent
      FROM orders
      WHERE status = 'completed'
      GROUP BY customerID) AS per_customer
JOIN customers c ON c.customerID = per_customer.customerID;
-- (A query inside a query: next lecture's topic.)


-- ---- The question to ask every time you aggregate after a join ----
-- "Is the thing I'm summing at the same grain as the rows I'm joining
--  through? If not, am I about to sum the same value multiple times?"
