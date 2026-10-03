-- ============================================================
-- Lecture 4 — Joins, step 10: joining on the wrong thing
-- Notes: Part 4.9 — names are not identifiers
-- Run after steps/00-setup.sql. Read-only: safe to re-run.
-- ============================================================


-- ---- 1. "Which of our employees also shop with us?" ----
-- Step 5's FULL JOIN found 2 names on both lists. Join on the names:
SELECT c.firstName, c.lastName,
       c.birthDate AS customer_born, e.birthDate AS employee_born,
       c.city      AS customer_city, e.branch    AS employee_branch
FROM customers c
JOIN employees e ON e.firstName = c.firstName AND e.lastName = c.lastName;
-- Read the birth dates: these are FOUR different people. The join did
-- exactly what it was told — it matched names. The honest answer to
-- the question is: this data can't tell. No column links a customer
-- to an employee.


-- ---- 2. The same mistake at scale: rows multiply ----
-- Try to give each flat sales row its customerID by looking the name
-- up in customers. The flat file has one row per order line:
SELECT count(*) AS sales_rows FROM sales;
-- Guess first: that many rows in. How many come out of the name join?
SELECT count(*)
FROM sales s
JOIN customers c ON c.firstName = s.customerFirstName
                AND c.lastName  = s.customerLastName;

-- Where do the extra rows come from? Two customers are both named
-- Anna Sargsyan. Every sales row for either Anna matches BOTH, so each
-- of these rows comes out twice:
SELECT count(*) AS anna_rows
FROM sales
WHERE customerFirstName = 'Anna' AND customerLastName = 'Sargsyan';

-- The fix: join on something guaranteed unique. customers.email has a
-- UNIQUE constraint, and the flat file carries each customer's email:
SELECT count(*)
FROM sales s
JOIN customers c ON c.email = s.customerEmail;
-- One customer per email, so every sales row finds exactly one partner.


-- ---- The one-line lesson ----
-- Only join on something GUARANTEED unique — a real key. Anything that
-- merely "usually" identifies a row correctly will eventually produce
-- a false match once the data is large enough, and the join won't
-- warn you when it happens.
