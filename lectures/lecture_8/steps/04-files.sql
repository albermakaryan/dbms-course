-- ============================================================
-- Lecture 8 — Part 4: Querying and writing files
-- DuckDB. Run from the lecture_8/ folder.
--
-- files/monthly/ has twelve CSV exports, one per month of 2025.
-- In July the shop changed its till system. Nobody told the analysts.
-- ============================================================

-- ---- 4.1 Many files, one query: a glob ----
-- * matches any characters, so this reads all twelve files as one table.
SELECT count(*) AS orders, sum(ordertotal) AS total
FROM 'files/monthly/*.csv';
-- ERROR: Invalid Input Error: Schema mismatch between globbed files.
--   Main file schema: files/monthly/orders_2025-01.csv
--   Current file: files/monthly/orders_2025-07.csv
--   Column with name: "ordertotal" is missing
-- DuckDB takes the columns from the FIRST file (January). The files
-- from July on have no "ordertotal" column, so it stops at the first
-- one it reaches (which one varies: files are read in parallel).
-- A loud failure: good.

-- ---- 4.2 The suggested fix ----
-- The error message suggests union_by_name: match columns by name and
-- fill a column a file doesn't have with NULL.
SELECT count(*) AS orders, sum(ordertotal) AS total
FROM read_csv('files/monthly/*.csv', union_by_name = true);
--  orders |    total
-- 1895177 | 591722020.29
-- It runs. All 1,895,177 orders of 2025 are there, and the total looks
-- like a total. It is about half the year's revenue.

-- ---- 4.3 Which file did each row come from? ----
-- filename = true adds a column with the file each row came from.
SELECT filename, count(*) AS orders, count(ordertotal) AS with_total
FROM read_csv('files/monthly/*.csv', union_by_name = true, filename = true)
GROUP BY filename
ORDER BY filename;
--             filename             | orders | with_total
-- files/monthly/orders_2025-01.csv | 155477 |     155477
-- files/monthly/orders_2025-02.csv | 141395 |     141395
-- files/monthly/orders_2025-03.csv | 157578 |     157578
-- files/monthly/orders_2025-04.csv | 153499 |     153499
-- files/monthly/orders_2025-05.csv | 159621 |     159621
-- files/monthly/orders_2025-06.csv | 155419 |     155419
-- files/monthly/orders_2025-07.csv | 161549 |          0
-- files/monthly/orders_2025-08.csv | 162490 |          0
-- files/monthly/orders_2025-09.csv | 158120 |          0
-- files/monthly/orders_2025-10.csv | 164268 |          0
-- files/monthly/orders_2025-11.csv | 159799 |          0
-- files/monthly/orders_2025-12.csv | 165962 |          0
-- From July on, every order has a NULL ordertotal: the new system
-- called the column order_total. sum() skips NULLs, silently.
SELECT DISTINCT column_name
FROM (DESCRIBE SELECT * FROM read_csv('files/monthly/*.csv', union_by_name = true))
WHERE starts_with(column_name, 'order')
ORDER BY column_name;
-- column_name
-- order_total
-- orderdate
-- orderid
-- ordertime
-- ordertotal

-- ---- 4.4 The real fix, and the check ----
SELECT count(*) AS orders,
       sum(coalesce(ordertotal, order_total)) AS total
FROM read_csv('files/monthly/*.csv', union_by_name = true);
--  orders |       total
-- 1895177 | 1213754385.9100044
-- Check it against a source you trust: the Parquet file.
SELECT count(*) AS orders, sum(ordertotal) AS total
FROM 'files/orders_big.parquet'
WHERE orderdate >= DATE '2025-01-01';
--  orders |     total
-- 1895177 | 1213754385.91
-- Same count, same total to the cent. (The CSV sum is a DOUBLE:
-- round it to 2 decimals to compare. Part 7.1.)

-- ---- 4.5 Write: clean CSVs in, one Parquet file out ----
COPY (
    SELECT * EXCLUDE (ordertotal, order_total),
           CAST(coalesce(ordertotal, order_total) AS DECIMAL(10,2)) AS ordertotal
    FROM read_csv('files/monthly/*.csv', union_by_name = true)
) TO 'files/orders_2025.parquet' (FORMAT parquet);
--  Count
-- 1895177
SELECT count(*) AS orders, sum(ordertotal) AS total
FROM 'files/orders_2025.parquet';
--  orders |     total
-- 1895177 | 1213754385.91

-- ---- 4.6 Write one folder per month ----
-- PARTITION_BY writes a folder for every value: year=2025/month=6/...
-- (the layout Lecture 7, 9.9 mentioned). It takes columns, not
-- expressions, so year and month are computed first.
COPY (
    SELECT *, year(orderdate) AS year, month(orderdate) AS month
    FROM 'files/orders_big.parquet'
) TO 'files/by_month' (FORMAT parquet, PARTITION_BY (year, month), OVERWRITE);
--  Count
-- 5000000
SELECT file FROM glob('files/by_month/**/*.parquet')
WHERE contains(file, 'year=2025/month=6/');
--                       file
-- files/by_month/year=2025/month=6/data_0.parquet
SELECT count(*) AS files FROM glob('files/by_month/**/*.parquet');
-- files
--    36

-- ---- 4.7 Read the folders: only the ones you ask for ----
-- DuckDB sees the key=value folder names and adds year and month as columns.
SELECT count(*) AS orders, sum(ordertotal) AS total
FROM 'files/by_month/*/*/*.parquet'
WHERE year = 2025 AND month = 6;
-- orders |    total
-- 155419 | 99974417.46
EXPLAIN ANALYZE
SELECT count(*), sum(ordertotal)
FROM 'files/by_month/*/*/*.parquet'
WHERE year = 2025 AND month = 6;
-- Data Read: 721.1 kB
-- File Filters: (year = 2025)(month = 6)
-- Scanning Files: 1/36
-- Total Files Read: 1
-- Row Groups Scanned: 2 / 2
-- One file of 36 opened.

-- ---- 4.8 The trap: the same month, asked differently ----
EXPLAIN ANALYZE
SELECT count(*), sum(ordertotal)
FROM 'files/by_month/*/*/*.parquet'
WHERE orderdate >= DATE '2025-06-01' AND orderdate < DATE '2025-07-01';
-- Data Read:   1.2 MB
-- Total Files Read: 36
-- Row Groups Scanned: 2 / 65
-- Same answer, but all 36 files are opened to check their min/max.
-- The folders only help a filter on the folder columns, as partition
-- pruning in PostgreSQL only helps a filter on the partition key
-- (Lecture 7, 9.4).
