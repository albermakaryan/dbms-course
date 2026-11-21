-- ============================================================
-- Lecture 8 — Part 7: Traps and checks
-- DuckDB, with PostgreSQL attached (as in Part 6). Run from lecture_8/.
-- ============================================================
LOAD postgres;
ATTACH 'host=localhost port=5432 dbname=lecture08 user=postgres password=postgres'
    AS pg (TYPE postgres, READ_ONLY);

-- ---- 7.1 A total that changes every time you run it ----
SELECT sum(ordertotal) AS total FROM 'files/orders_big.csv';
--       total
-- 3199787987.860031
SELECT sum(ordertotal) AS total FROM 'files/orders_big.csv';
--       total
-- 3199787987.8600454
-- Two runs, two different totals, both wrong after the .86. DuckDB
-- guessed DOUBLE for ordertotal (2.2), and a DOUBLE can't hold most
-- decimal fractions exactly, so tiny errors add up. DuckDB adds in
-- parallel, in a different order each time, so the error differs too.
-- Fix: tell DuckDB the type.
SELECT sum(ordertotal) AS total
FROM read_csv('files/orders_big.csv', types = {'ordertotal': 'DECIMAL(10,2)'});
--     total
-- 3199787987.86
-- 3199787987.86, every time. (Or read the Parquet file: it has the type.)

-- ---- 7.2 Leading zeros ----
-- A CRM export. Yerevan postal codes start with 00.
SELECT * FROM 'files/messy/customers_export.csv' LIMIT 3;
-- customer_id |   city  | postal_code | discount_pct
--           1 | Yerevan |        0049 |            0
--           2 | Yerevan |        0006 |            0
--           3 | Yerevan |        0065 |            0
DESCRIBE SELECT * FROM 'files/messy/customers_export.csv';
-- column_name  | column_type | null | key | default | extra
-- customer_id  | BIGINT      | YES  |     |         |
-- city         | VARCHAR     | YES  |     |         |
-- postal_code  | VARCHAR     | YES  |     |         |
-- discount_pct | BIGINT      | YES  |     |         |
-- DuckDB kept postal_code as text (VARCHAR), zeros and all.
-- pandas, by default, made it a number: 0049 became 49 (Part 5,
-- 05-python-postgres.py has the same trap for employeeID).

-- ---- 7.3 A value the sample didn't see ----
SELECT avg(discount_pct) FROM 'files/messy/customers_export.csv';
-- ERROR: Conversion Error: CSV Error on Line: 30002
--   Original Line: 30001,Vanadzor,2005,n/a
--   Error when converting column "discount_pct". Could not convert string "n/a" to 'BIGINT'
--   Column discount_pct is being converted as type BIGINT
-- DuckDB guessed the type from the first 20,480 rows: all whole
-- numbers, so BIGINT. Row 30,001 says "n/a". A loud failure.
-- Fix: say what n/a means.
SELECT count(*) AS customers, count(discount_pct) AS with_discount,
       round(avg(discount_pct), 2) AS avg_discount
FROM read_csv('files/messy/customers_export.csv', nullstr = 'n/a');
-- customers | with_discount | avg_discount
--     50000 |         49999 |         7.13
-- pandas reads the same file without a word: "n/a" becomes NaN and the
-- column becomes float64.

-- ---- 7.4 Engine differences: the same SQL, two answers ----
-- Integer division. "Average items per order":
SELECT sum(quantity) / count(DISTINCT orderID) AS items_per_order
FROM pg.order_items;
-- items_per_order
--           2.215
SELECT * FROM postgres_query('pg',
    'SELECT sum(quantity) / count(DISTINCT orderID) AS items_per_order FROM order_items');
-- items_per_order
--               2
-- DuckDB: 2.215. PostgreSQL: 2. In PostgreSQL integer / integer cuts
-- off the fraction; in DuckDB / always keeps it (// cuts it off).
-- Portable: sum(quantity)::numeric / count(...) gives 2.215 in both.

-- NULLs in a descending sort. "Our best-rated orders":
SELECT orderID, rating FROM pg.orders ORDER BY rating DESC, orderID LIMIT 3;
-- orderid | rating
--    1007 |      5
--    1013 |      5
--    1015 |      5
SELECT * FROM postgres_query('pg',
    'SELECT orderID, rating FROM orders ORDER BY rating DESC, orderID LIMIT 3');
-- orderid | rating
--    1001 |
--    1002 |
--    1003 |
-- DuckDB puts NULLs last; PostgreSQL puts them first when sorting
-- DESC, so its "top 3" are three orders nobody rated. Portable: write
-- NULLS LAST yourself.

-- ---- 7.5 Matching totals: one check across every copy ----
-- The DuckDB database file from Part 3, attached read-only:
ATTACH 'files/shop.duckdb' AS shop (READ_ONLY);
-- Totals as text, so that UNION ALL doesn't turn them all into DOUBLEs.
SELECT 'PostgreSQL' AS source, orders, total::VARCHAR AS total
FROM postgres_query('pg', 'SELECT count(*) AS orders, sum(orderTotal) AS total FROM orders_big')
UNION ALL
SELECT 'CSV (as guessed)', count(*), sum(ordertotal)::VARCHAR FROM 'files/orders_big.csv'
UNION ALL
SELECT 'CSV (DECIMAL)', count(*), sum(ordertotal)::VARCHAR
FROM read_csv('files/orders_big.csv', types = {'ordertotal': 'DECIMAL(10,2)'})
UNION ALL
SELECT 'Parquet', count(*), sum(ordertotal)::VARCHAR FROM 'files/orders_big.parquet'
UNION ALL
SELECT 'Parquet folders', count(*), sum(ordertotal)::VARCHAR FROM 'files/by_month/*/*/*.parquet'
UNION ALL
SELECT 'DuckDB file', count(*), sum(ordertotal)::VARCHAR FROM shop.orders_big;
--      source      |  orders |      total
-- PostgreSQL       | 5000000 |    3199787987.86
-- CSV (as guessed) | 5000000 | 3199787987.86002
-- CSV (DECIMAL)    | 5000000 |    3199787987.86
-- Parquet          | 5000000 |    3199787987.86
-- Parquet folders  | 5000000 |    3199787987.86
-- DuckDB file      | 5000000 |    3199787987.86
-- Every copy has 5,000,000 rows. Every total is 3199787987.86 except
-- the guessed CSV's. Run this check after every move of data from one
-- place to another: count, and a sum, compared to the source.
