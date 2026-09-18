-- ============================================================
-- Lecture 3 — Part 6: verification drill
-- Run after Part 5. The shop owner asked an AI assistant for four
-- numbers. Every query runs without error and returns a plausible
-- answer. Every one is wrong. Have a theory for each BEFORE reading
-- the answers at the bottom.
-- ============================================================

-- Q1. "Total revenue for 2024."
SELECT sum(orderTotal) AS revenue FROM sales;
-- 164092.05

-- Q2. "How much has the average customer spent with us, lifetime?"
SELECT round(avg(customerMoneySpent), 2) AS avg_customer_spend FROM sales;
-- 6799.93

-- Q3. "How many different customers bought something in December?"
SELECT count(DISTINCT customerLastName) AS december_customers
FROM sales
WHERE orderDate BETWEEN '2024-12-01' AND '2024-12-31';
-- 24

-- Q4. "What share of our orders are laptops?"
SELECT sum(CASE WHEN productCategory = 'Laptops' THEN 1 ELSE 0 END) / count(*) AS laptop_share
FROM sales;
-- 0


-- ============================================================
-- Answers. Don't scroll here until you have a theory for all four.
-- ============================================================

-- Q1 -- status. 71 of the 600 rows are returned or cancelled orders.
-- Their totals are in the table; they are not revenue.
SELECT sum(orderTotal) AS revenue FROM sales WHERE status = 'completed';   -- 145935.12
-- Overstated by 18,156.93. Every "revenue" query this year needs that WHERE.

-- Q2 -- grain. The flat file repeats a customer's lifetime total on
-- EVERY one of their orders. Aram Vardanyan's 13,544.72 is in there 40
-- times; Diana Aleksanyan's 2,327.00 four times. That's an average of ORDERS
-- weighted by how much people buy, not an average of customers.
SELECT round(avg(moneySpent), 2) FROM customers;                        -- 4864.50 (all 30)
SELECT round(avg(moneySpent), 2) FROM customers WHERE moneySpent > 0;   -- 5211.97 (the 28 who bought)
-- Which of those two is "right" is a business decision; 6799.93 is
-- neither. Before you avg() anything: one row per WHAT?

-- Q3 -- identity. Three different Sargsyans, two of them named Anna.
-- A surname is not a person; neither is a name.
SELECT count(DISTINCT customerEmail) AS december_customers
FROM sales
WHERE orderDate BETWEEN '2024-12-01' AND '2024-12-31';                 -- 26
-- count(DISTINCT x) counts distinct x. Make x something that
-- identifies what you're counting.

-- Q4 -- integer division. Both sides are whole numbers, so 51 / 600
-- is 0 with the remainder thrown away. Make one side a decimal:
SELECT round(100.0 * sum(CASE WHEN productCategory = 'Laptops' THEN 1 ELSE 0 END) / count(*), 1)
       AS laptop_pct
FROM sales;                                                            -- 8.5
-- 0 looked like "no laptops". 51 laptops were sold.

-- Business impact, one sentence each -- the format you'll use all semester:
--   Q1: 2024 revenue is overstated by 18,156.93; returns and
--       cancellations were booked as sales.
--   Q2: the average customer is worth 4,864, not 6,800 -- a marketing
--       budget sized on 6,800 overspends by 40%.
--   Q3: two December customers went uncounted, and any surname shared
--       by two people will be miscounted the same way every month.
--   Q4: the laptop share reads as zero; a buyer trusting it would stop
--       stocking the shop's biggest revenue category.
