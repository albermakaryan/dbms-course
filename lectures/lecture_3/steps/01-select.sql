-- ============================================================
-- Lecture 3 — Part 1: SELECT is a list of expressions
-- Run after steps/00-setup.sql. Expected results in the comments
-- came from running this against Postgres 16.
-- ============================================================

-- ---- What's in here? ----
SELECT count(*) FROM sales;          -- 600

SELECT * FROM sales LIMIT 3;         -- 29 columns. Unreadable. Don't do this.

-- psql trick for ONE wide row: \x flips to one-column-per-line display
\x
SELECT * FROM sales LIMIT 1;
\x

-- Or just ask what the columns are:
\d sales

-- ---- Choose columns. Always. ----
SELECT orderID, orderDate, productName, orderTotal
FROM sales
LIMIT 5;

-- ---- Columns can be expressions ----
-- Arithmetic on numbers; AS names the result.
SELECT orderID, quantity, unitPrice, discountPct, orderTotal,
       quantity * unitPrice               AS list_total,
       quantity * unitPrice - orderTotal  AS discount_given
FROM sales
LIMIT 5;

-- The products table: what does the shop make on each item?
SELECT productName, price, cost,
       price - cost                              AS margin,
       round((price - cost) / price * 100, 1)    AS margin_pct
FROM products
LIMIT 5;

-- AS is optional, but an alias with a space or capitals needs double quotes.
SELECT productName, round(price * 1.2, 2) AS "Price incl. VAT" FROM products LIMIT 3;

-- ---- Text ----
SELECT customerFirstName || ' ' || customerLastName AS customer,   -- || glues text
       upper(customerCity)                          AS city,
       length(customerEmail)                        AS email_length
FROM sales
LIMIT 5;

SELECT email,
       split_part(email, '@', 2) AS domain,     -- piece 2 when split at '@'
       lower(firstName)          AS handle
FROM customers
LIMIT 5;

-- ---- Dates and times ----
SELECT orderDate,
       EXTRACT(YEAR  FROM orderDate)  AS yr,
       EXTRACT(MONTH FROM orderDate)  AS mon,
       to_char(orderDate, 'Mon')      AS mon_name,
       to_char(orderDate, 'Dy')       AS weekday,
       orderTime,
       EXTRACT(HOUR FROM orderTime)   AS hr
FROM sales
LIMIT 5;

-- Date minus date = a number of days.
SELECT orderID, orderDate, deliveryDate,
       deliveryDate - orderDate AS days_to_deliver
FROM sales
WHERE channel = 'online'
LIMIT 5;

-- age() gives an interval; EXTRACT pulls the years out of it.
-- Pinned to a fixed date so your output matches this file.
SELECT firstName, lastName, birthDate,
       age(DATE '2024-12-31', birthDate)                     AS age_at_year_end,
       EXTRACT(YEAR FROM age(DATE '2024-12-31', birthDate))  AS years
FROM customers
LIMIT 5;

-- Today's date is a function. This one's output depends on when you run it.
SELECT CURRENT_DATE, CURRENT_DATE - DATE '2024-01-01' AS days_since_new_year;

-- ---- CASE WHEN: a value that depends on a condition ----
SELECT orderID, orderTotal,
       CASE
           WHEN orderTotal >= 1000 THEN 'large'
           WHEN orderTotal >= 100  THEN 'medium'
           ELSE                         'small'
       END AS size
FROM sales
LIMIT 8;

-- Conditions are checked top to bottom; the first true one wins.
SELECT firstName, lastName, moneySpent,
       CASE
           WHEN moneySpent >= 10000 THEN 'Gold'
           WHEN moneySpent >= 3000  THEN 'Silver'
           ELSE                          'Bronze'
       END AS tier
FROM customers
LIMIT 8;

-- Without ELSE, anything that matches nothing becomes NULL.
SELECT orderID, rating,
       CASE WHEN rating >= 4 THEN 'happy' WHEN rating <= 2 THEN 'unhappy' END AS mood
FROM sales
LIMIT 8;

-- ---- One rule to remember ----
-- An alias is invented by SELECT. Nothing that runs BEFORE SELECT can
-- see it -- and WHERE runs before SELECT (Part 2).
