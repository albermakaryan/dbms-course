-- TRANSFORM (DuckDB): completed revenue per salesperson.
-- Online orders have no salesperson, so the inner join leaves them out.
-- Saved as data/reports/salesperson_revenue.parquet.
SELECT e.firstName || ' ' || e.lastName AS salesperson,
       e.branch,
       count(*)          AS orders,
       sum(o.orderTotal) AS revenue
FROM orders    AS o
JOIN employees AS e USING (employeeID)
WHERE o.status = 'completed'
GROUP BY ALL
ORDER BY revenue DESC
