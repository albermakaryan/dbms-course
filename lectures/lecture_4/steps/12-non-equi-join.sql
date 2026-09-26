-- ============================================================
-- Lecture 4 — Joins, step 12: ON with non-equality conditions
-- Notes: Part 4.11
-- Run after steps/00-setup.sql. Read-only: safe to re-run.
--
-- ON isn't limited to key = key. It accepts any true/false condition —
-- that's just "every pair, keep the ones that pass" again.
-- ============================================================


-- ---- 1. A small table typed into the query with VALUES ----
SELECT *
FROM (VALUES ('1. under 50',  0,    50),
             ('2. 50 - 299',  50,   300),
             ('3. 300 - 999', 300,  1000),
             ('4. 1000+',     1000, 100000)) AS b(band, low, high);


-- ---- 2. Join each order to the band its total falls in ----
SELECT b.band, count(*) AS orders, sum(o.orderTotal) AS revenue
FROM orders o
JOIN (VALUES ('1. under 50',  0,    50),
             ('2. 50 - 299',  50,   300),
             ('3. 300 - 999', 300,  1000),
             ('4. 1000+',     1000, 100000)) AS b(band, low, high)
  ON o.orderTotal >= b.low AND o.orderTotal < b.high
WHERE o.status = 'completed'
GROUP BY b.band
ORDER BY b.band;
-- Add up the orders column: it equals the number of completed orders.
-- Each order lands in exactly one band, because the bands don't
-- overlap (>= low, < high).
-- Bucketing done natively in SQL, without a CASE per row. Tax
-- brackets and commission tiers are joins like this.
