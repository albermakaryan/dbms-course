-- ============================================================
-- Lecture 2 — Part 7: The payoff — put it back together
-- ============================================================

SELECT o.orderID,
       o.orderDate,
       c.firstName || ' ' || c.lastName AS customer,
       p.category,
       p.price,
       o.orderTotal,
       e.firstName || ' ' || e.lastName AS soldBy
FROM orders o
JOIN customers c ON c.customerID = o.customerID
JOIN products  p ON p.productID  = o.productID
JOIN employees e ON e.employeeID = o.employeeID
ORDER BY o.orderDate, o.orderID;

-- 42 rows -- exactly the file we started with. Nothing was lost.

-- Optional: is the STORED moneySpent still true?
SELECT c.firstName, c.lastName,
       c.moneySpent      AS stored,
       SUM(o.orderTotal) AS computed
FROM customers c
JOIN orders o ON o.customerID = c.customerID
GROUP BY c.customerID, c.firstName, c.lastName, c.moneySpent
ORDER BY c.customerID;

-- They match today. What happens the first time someone inserts
-- an order and forgets to update moneySpent?
