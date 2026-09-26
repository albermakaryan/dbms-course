-- ============================================================
-- Lecture 4 — Joins, step 3: aliasing, and the two errors that teach it
-- Notes: Part 4.3
-- Run after steps/00-setup.sql. Read-only: safe to re-run.
-- TWO statements in this file fail ON PURPOSE. Read each error.
-- ============================================================


-- ---- 1. Full table names work, but they're long ----
SELECT orders.orderID, customers.firstName, orders.orderTotal
FROM orders
JOIN customers ON customers.customerID = orders.customerID
WHERE orders.orderID = 1001;


-- ---- 2. Error on purpose: an ambiguous column ----
-- customerID exists in BOTH orders and customers. Which one do you mean?
SELECT orderID, customerID, firstName
FROM orders
JOIN customers ON customers.customerID = orders.customerID
WHERE orderID = 1001;
-- orderID and firstName exist in only one table each, so PostgreSQL
-- finds them. customerID exists in two, and the engine refuses to
-- guess — even though the two values are equal on every joined row.
-- The rule is about NAMES, not values.


-- ---- 3. The fix: alias the tables, qualify the columns ----
SELECT o.orderID, o.customerID, c.firstName
FROM orders o
JOIN customers c ON c.customerID = o.customerID
WHERE o.orderID = 1001;


-- ---- 4. Error on purpose: the alias REPLACED the name ----
-- Once you write FROM orders o, the name "orders" stops existing for
-- the rest of that query. Only "o" does.
SELECT orders.orderID
FROM orders o
WHERE o.orderID = 1001;
-- Read the HINT: PostgreSQL tells you exactly what happened. An alias
-- doesn't add a nickname — it replaces the name.


-- ---- The habit ----
-- In any query with two or more tables, prefix EVERY column, even the
-- ones that aren't ambiguous yet. Next month someone adds a firstName
-- column to orders, and every unprefixed query breaks.
