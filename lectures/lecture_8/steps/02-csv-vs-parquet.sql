-- ============================================================
-- Lecture 8 — Part 2: Parquet vs CSV (size, types, speed)
-- DuckDB. Run from the lecture_8/ folder.
-- ============================================================

-- ---- 2.1 Size ----
-- Compare like with like: a file with a file, a database with a database.
-- read_blob lists files with their size in bytes.
-- Two FILES holding the same 5,000,000 orders:
SELECT filename, round(size / 1e6, 1) AS mb
FROM read_blob(['files/orders_big.csv', 'files/orders_big.parquet']);
--         filename         |   mb
-- files/orders_big.csv     | 356.5
-- files/orders_big.parquet | 102.1
-- CSV 356.5 MB, Parquet 102.1 MB: about 3.5 times smaller.
-- Two DATABASES holding the same table. DuckDB's is one file
-- (00-make-files.py wrote it):
SELECT filename, round(size / 1e6, 1) AS mb
FROM read_blob('files/shop.duckdb');
--      filename     |   mb
-- files/shop.duckdb | 115.6
-- DuckDB: 116 MB. PostgreSQL (00-setup.sql): the table 489 MB (whole
-- rows in 8 kB pages, Lecture 7), plus its primary-key index 112 MB.
-- (MB here = 1,000,000 bytes; pg_size_pretty prints 467 and 107.)
-- Don't compare PostgreSQL's table with the CSV or the Parquet file:
-- a database keeps more than the data.

-- ---- 2.2 Types ----
-- A CSV is text. DuckDB guesses each column's type from a sample:
DESCRIBE SELECT * FROM 'files/orders_big.csv';
--  column_name  | column_type | null | key | default | extra
-- orderid       | BIGINT      | YES  |     |         |
-- customerid    | BIGINT      | YES  |     |         |
-- employeeid    | BIGINT      | YES  |     |         |
-- orderdate     | DATE        | YES  |     |         |
-- ordertime     | TIME        | YES  |     |         |
-- channel       | VARCHAR     | YES  |     |         |
-- paymentmethod | VARCHAR     | YES  |     |         |
-- status        | VARCHAR     | YES  |     |         |
-- deliverydate  | DATE        | YES  |     |         |
-- rating        | BIGINT      | YES  |     |         |
-- ordertotal    | DOUBLE      | YES  |     |         |
-- ordertotal: DOUBLE (a floating-point number), not DECIMAL(10,2).
-- Ids: BIGINT. Dates and times were guessed right.
DESCRIBE SELECT * FROM 'files/orders_big.parquet';
--  column_name  |  column_type  | null | key | default | extra
-- orderid       | INTEGER       | YES  |     |         |
-- customerid    | INTEGER       | YES  |     |         |
-- employeeid    | INTEGER       | YES  |     |         |
-- orderdate     | DATE          | YES  |     |         |
-- ordertime     | TIME          | YES  |     |         |
-- channel       | VARCHAR       | YES  |     |         |
-- paymentmethod | VARCHAR       | YES  |     |         |
-- status        | VARCHAR       | YES  |     |         |
-- deliverydate  | DATE          | YES  |     |         |
-- rating        | INTEGER       | YES  |     |         |
-- ordertotal    | DECIMAL(10,2) | YES  |     |         |
-- Parquet stores the types: DECIMAL(10,2), INTEGER, as PostgreSQL had
-- them. Nothing is guessed. Part 7 shows what the DOUBLE costs.

-- ---- 2.3 Speed ----
-- The same three questions on each file. Medians of 3 runs on the
-- reference laptop (20 threads, DuckDB 2.0.1); yours will differ, the
-- gap won't. In the CLI, .timer on prints each query's time.
SELECT count(*) FROM 'files/orders_big.csv';
-- count_star()
--      5000000
SELECT count(*) FROM 'files/orders_big.parquet';
-- count_star()
--      5000000
-- CSV about 170 ms: the whole file is read to count the lines.
-- Parquet about 1 ms: the row counts are in the footer.

SELECT sum(ordertotal) FROM 'files/orders_big.csv';
--  sum(ordertotal)
-- 3199787987.8600445
SELECT sum(ordertotal) FROM 'files/orders_big.parquet';
-- sum(ordertotal)
--   3199787987.86
-- CSV about 200 ms (457 MB read: every byte, parsed as text),
-- Parquet about 13 ms (22 MB). PostgreSQL: about 180 ms.
-- Look at the CSV's total: digits after .86 that shouldn't be there,
-- and they change from run to run. Part 7.1.

SELECT * FROM 'files/orders_big.csv'     WHERE orderid = 4890168;
-- orderid | customerid | employeeid | orderdate  | ordertime | channel | paymentmethod |   status  | deliverydate | rating | ordertotal
-- 4890168 |       4242 |            | 2025-12-11 | 14:05:03  | online  | transfer      | completed | 2025-12-14   |      1 |    1768.13
SELECT * FROM 'files/orders_big.parquet' WHERE orderid = 4890168;
-- orderid | customerid | employeeid | orderdate  | ordertime | channel | paymentmethod |   status  | deliverydate | rating | ordertotal
-- 4890168 |       4242 |            | 2025-12-11 | 14:05:03  | online  | transfer      | completed | 2025-12-14   |      1 |    1768.13
-- CSV about 330 ms, Parquet about 7 ms (min/max on orderid skip
-- 40 of the 41 row groups: 2.6 MB read). In PostgreSQL, with its primary key
-- index, this lookup reads 4 pages (Lecture 7, Lab 1).
