-- CHECK (DuckDB): did every step keep the data?
-- `source` = the numbers from PostgreSQL (source.sql, same period);
-- orders, monthly_revenue, salesperson_revenue = the pipeline's files.
-- Every row should say ok.
WITH raw AS (
    SELECT count(*) AS orders, sum(orderTotal) AS total FROM orders
),
monthly AS (
    SELECT sum(total) AS completed FROM monthly_revenue
),
people AS (
    SELECT sum(revenue) AS completed FROM salesperson_revenue
)
SELECT 'extract: rows' AS check_name, source.orders::VARCHAR AS source, raw.orders::VARCHAR AS pipeline,
       CASE WHEN source.orders = raw.orders THEN 'ok' ELSE 'MISMATCH' END AS result
FROM source, raw
UNION ALL
SELECT 'extract: total', source.total::VARCHAR, raw.total::VARCHAR,
       CASE WHEN source.total = raw.total THEN 'ok' ELSE 'MISMATCH' END
FROM source, raw
UNION ALL
SELECT 'transform: monthly = completed', source.completed::VARCHAR, monthly.completed::VARCHAR,
       CASE WHEN source.completed = monthly.completed THEN 'ok' ELSE 'MISMATCH' END
FROM source, monthly
UNION ALL
-- online orders have no salesperson, so the salespeople add up to in-store only
SELECT 'transform: salespeople = completed in-store', source.completed_in_store::VARCHAR,
       people.completed::VARCHAR,
       CASE WHEN source.completed_in_store = people.completed THEN 'ok' ELSE 'MISMATCH' END
FROM source, people
