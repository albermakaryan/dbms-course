-- ============================================================
-- Lecture 8 — Part 1: Row vs column storage
-- DuckDB. Run from the lecture_8/ folder, after Part 0
-- (in the notebook, or in the DuckDB CLI: duckdb, then .read steps/01-row-vs-column.sql).
--
-- Lecture 7, 2.7: in PostgreSQL, sum(orderTotal) read all of
-- orders_big (59,739 pages), because a page holds whole rows. A Parquet file stores
-- each column separately. This Part looks inside one.
-- ============================================================

-- ---- 1.1 A file is a table: query it directly ----
SELECT count(*) AS orders, sum(ordertotal) AS total
FROM 'files/orders_big.parquet';
--  orders |     total
-- 5000000 | 3199787987.86
-- The same 5,000,000 orders and the same total as PostgreSQL
-- (00-setup.sql: 3199787987.86). No CREATE TABLE, no load.

-- ---- 1.2 Row groups ----
-- A Parquet file is cut into row groups (blocks of rows); inside each,
-- every column is stored on its own (a "column chunk").
SELECT count(DISTINCT row_group_id)  AS row_groups,
       min(row_group_num_rows)       AS smallest,
       max(row_group_num_rows)       AS largest
FROM parquet_metadata('files/orders_big.parquet');
-- row_groups | smallest | largest
--         41 |    43057 |  124156
-- 41 row groups of up to about 120,000 rows.

-- ---- 1.3 How much space each column takes ----
SELECT path_in_schema                              AS column_name,
       round(sum(total_compressed_size) / 1e6, 1)  AS mb
FROM parquet_metadata('files/orders_big.parquet')
GROUP BY path_in_schema
ORDER BY min(column_id);
--  column_name  |  mb
-- orderid       | 20.0
-- customerid    | 20.0
-- employeeid    |  1.9
-- orderdate     |  0.0
-- ordertime     | 32.2
-- channel       |  0.7
-- paymentmethod |  1.3
-- status        |  0.7
-- deliverydate  |  1.7
-- rating        |  1.4
-- ordertotal    | 22.1
-- ordertotal is 22.1 MB of the 102 MB file. orderdate is almost
-- nothing: the file is in date order, so long runs of one date
-- compress to almost nothing.

-- ---- 1.4 Sum one column: read one column ----
EXPLAIN ANALYZE
SELECT sum(ordertotal) FROM 'files/orders_big.parquet';
-- Total Time: 0.0096s
-- Data Read:  22.2 MB
-- Projections: ordertotal
-- Row Groups Scanned: 41 / 41
-- Data Read: 22.2 MB, the ordertotal chunks only.
-- The same question in PostgreSQL (psql, lecture08):
--     EXPLAIN (ANALYZE, BUFFERS) SELECT sum(orderTotal) FROM orders_big;
--     Finalize Aggregate ... (actual time=208.080..210.905 rows=1.00 loops=1)
--       Buffers: shared hit=12971 read=46768
--       ...
--       ->  Parallel Seq Scan on orders_big ...
-- 12,971 + 46,768 = 59,739 pages x 8,192 bytes = 489 MB (Lecture 7's
-- "467 MB" is the same bytes, counted 1 MB = 1,048,576): every page of the
-- table, every column of every row (Lecture 7, 2.7).

-- ---- 1.5 Min / max: skipping row groups ----
-- The footer stores the smallest and largest value of every column
-- chunk. The first three row groups' dates:
SELECT row_group_id, stats_min AS min_date, stats_max AS max_date
FROM parquet_metadata('files/orders_big.parquet')
WHERE path_in_schema = 'orderdate'
ORDER BY row_group_id
LIMIT 3;
-- row_group_id |  min_date  |  max_date
--            0 | 2023-01-01 | 2023-02-17
--            1 | 2023-02-17 | 2023-03-26
--            2 | 2023-03-26 | 2023-05-01
-- A June 2025 filter can skip every row group whose dates don't
-- reach June 2025:
EXPLAIN ANALYZE
SELECT count(*), sum(ordertotal)
FROM 'files/orders_big.parquet'
WHERE orderdate >= DATE '2025-06-01' AND orderdate < DATE '2025-07-01';
-- Data Read:   1.2 MB
-- Row Groups Scanned: 2 / 41
-- 2 of 41 row groups, 1.2 MB. PostgreSQL, same query, no index on
-- orderDate: Parallel Seq Scan, "Rows Removed by Filter", Buffers
-- shared hit=13253 read=46486 = 59,739 pages again: all 489 MB.
-- (This works so well because the file
-- is in date order. In a file shuffled by date, every row group would
-- span the whole three years and none could be skipped.)
