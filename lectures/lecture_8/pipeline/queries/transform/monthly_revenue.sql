-- TRANSFORM (DuckDB): monthly completed revenue, in-store vs online, for the extracted period.
-- Reads the raw tables (views over data/raw/); saved as
-- data/reports/monthly_revenue.parquet.
SELECT date_trunc('month', orderDate)::DATE                    AS month,
       sum(orderTotal) FILTER (WHERE channel = 'in_store')     AS in_store,
       sum(orderTotal) FILTER (WHERE channel = 'online')       AS online,
       sum(orderTotal)                                         AS total
FROM orders
WHERE status = 'completed'
GROUP BY month
ORDER BY month
