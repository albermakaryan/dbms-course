-- Lab 01 — Setup & First Queries
-- Database Systems & Data Platforms · Week 01
--
-- Run queries one at a time: place the cursor inside a statement and press
-- Ctrl+Enter (Cmd+Enter on macOS) in DBeaver.

-- Connection check ----------------------------------------------------------

SELECT version();

-- Exercise 1 — look around: first 10 rows of customers -----------------------

SELECT *
FROM   customers
LIMIT  10;

-- Exercise 2 — pick columns: name and city, first 20 customers ---------------

-- YOUR QUERY HERE

-- Exercise 3 — filter: products in category 'electronics' --------------------

-- YOUR QUERY HERE

-- Exercise 4 — filter numerically: price > 50, cheapest first ----------------

-- YOUR QUERY HERE

-- Exercise 5 — sort descending: the 5 most expensive products ----------------

-- YOUR QUERY HERE

-- Exercise 6 — combine filters: delivered orders on/after 2026-01-01 ---------

-- YOUR QUERY HERE

-- Exercise 7 — count: how many customers? ------------------------------------

-- YOUR QUERY HERE

-- Exercise 8 — challenge: 10 largest non-cancelled orders, largest first -----
-- Before running: write in English what business question this answers.

-- YOUR QUERY HERE
