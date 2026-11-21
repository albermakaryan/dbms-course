-- ============================================================
-- Lecture 8 — Part 6: DuckDB and PostgreSQL together
-- DuckDB. Run from the lecture_8/ folder. Change the connection
-- string in ATTACH to yours (the notebook takes it from LECTURE08_DSN).
-- ============================================================

-- ---- 6.1 Attach a PostgreSQL database ----
-- The postgres extension is downloaded once (needs internet), then loaded.
INSTALL postgres;
LOAD postgres;
ATTACH 'host=localhost port=5432 dbname=lecture08 user=postgres password=postgres'
    AS pg (TYPE postgres, READ_ONLY);
-- READ_ONLY: DuckDB can't change anything in PostgreSQL by mistake.
SELECT table_name
FROM duckdb_tables()
WHERE database_name = 'pg' AND schema_name = 'public'
ORDER BY table_name;
--  table_name
-- customers
-- employees
-- order_items
-- orders
-- orders_big
-- products

-- ---- 6.2 Query PostgreSQL tables from DuckDB ----
SELECT count(*) AS completed_orders, sum(orderTotal) AS completed_revenue
FROM pg.orders
WHERE status = 'completed';
-- completed_orders | completed_revenue
--              529 |         157078.41
-- 529 and 157,078.41, as always: the same table, read through DuckDB.

-- ---- 6.3 Who does the work? ----
EXPLAIN
SELECT count(*), sum(orderTotal)
FROM pg.orders_big
WHERE status = 'cancelled';
-- SQL:
-- SELECT count(*) AS "count_star()", CAST(sum("ordertotal") AS NUMERIC(38,2)) AS "sum(orderTotal)" FROM "public"."orders_big" WHERE ("status" = 'cancelled')
-- The plan's only node is a "Postgres Query": DuckDB sent this SQL to
-- PostgreSQL, PostgreSQL did the work, one row came back.

-- ---- 6.4 One query, two sources ----
-- 2025 orders from the Parquet file, names from PostgreSQL.
SELECT e.firstName || ' ' || e.lastName AS salesperson,
       count(*)           AS orders,
       sum(o.ordertotal)  AS revenue
FROM 'files/orders_big.parquet' AS o
JOIN pg.employees AS e ON e.employeeID = o.employeeid
WHERE o.status = 'completed'
  AND o.orderdate >= DATE '2025-01-01'
GROUP BY salesperson
ORDER BY revenue DESC;
--    salesperson     | orders |   revenue
-- Vahe Sahakyan      | 146455 | 94134848.23
-- Nare Ghazaryan     | 146274 | 94081075.68
-- Arman Grigoryan    | 146161 | 93703592.72
-- Ani Harutyunyan    | 145650 | 93543609.58
-- Marine Avagyan     | 145835 | 93233362.64
-- Lilit Hovhannisyan | 145660 | 93197210.86
-- Hayk Melikyan      | 146038 | 92967638.69
-- Gor Mkrtchyan      | 145714 | 92720112.76
-- Online orders have no salesperson, so the JOIN leaves them out
-- (Lecture 4).

-- ---- 6.5 PostgreSQL to Parquet, in one statement ----
COPY (SELECT * FROM pg.orders) TO 'files/shop_orders.parquet' (FORMAT parquet);
-- Count
--   600
SELECT column_name, column_type
FROM (DESCRIBE SELECT * FROM 'files/shop_orders.parquet')
WHERE column_name IN ('orderid', 'orderdate', 'ordertotal');
-- column_name |  column_type
-- orderid     | INTEGER
-- orderdate   | DATE
-- ordertotal  | DECIMAL(10,2)
-- The types travel with the data: DECIMAL(10,2) stays DECIMAL(10,2).
-- A CSV export would have lost them.

-- ---- 6.6 SQL that runs inside PostgreSQL ----
-- postgres_query sends the text as it is; PostgreSQL runs it.
SELECT * FROM postgres_query('pg', 'SELECT version()');
--                                                      version
-- PostgreSQL 18.6 (Debian 18.6-1.pgdg13+2) on x86_64-pc-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
