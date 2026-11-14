-- ============================================================
-- Lecture 7 — Part 2: How a table is stored on disk
-- Run after Part 1.
--
-- Part 1 counted pages. This Part opens them. A table is a file; the
-- file is a row of 8 kB pages; every row sits in one page, at an
-- address (page, slot). Everything later in this lecture -- why a
-- Seq Scan reads every page, what an index stores, why 3% of the rows
-- can be 93% of the pages, why VACUUM matters -- follows from that.
-- (pageinspect and pg_ls_dir need a superuser: the postgres user of
-- our Docker setup is one.)
-- ============================================================

-- Start clean (in case you ran this Part before).
DROP TABLE IF EXISTS storage_demo, orders_2023;

-- ---- 2.1 A table is a file ----
-- Where does orders_big live? The server's data directory, then the
-- path of the table's file inside it:
SELECT current_setting('data_directory') AS data_directory,
       pg_relation_filepath('orders_big') AS file;
--        data_directory         |       file
-- /var/lib/postgresql/18/docker | base/16675/16852
-- base/<number of the database>/<number of the table's file>. Your
-- numbers will differ; they are just names. The file isn't alone --
-- list everything in that folder whose name starts with it:
SELECT f AS file,
       pg_size_pretty((pg_stat_file(dir || '/' || f)).size) AS size,
       (pg_stat_file(dir || '/' || f)).size AS bytes
FROM (SELECT regexp_replace(pg_relation_filepath('orders_big'), '/[^/]+$', '') AS dir,
             regexp_replace(pg_relation_filepath('orders_big'), '^.*/', '') AS node) p,
     pg_ls_dir(p.dir) AS f
WHERE f = node OR starts_with(f, node || '_') OR starts_with(f, node || '.')
ORDER BY f;
--   file    |  size  |   bytes
-- 16852     | 467 MB | 489381888
-- 16852_fsm | 136 kB |    139264
-- 16852_vm  | 16 kB  |     16384
-- Three files: the table itself (467 MB, every row), its free space
-- map (_fsm: which pages have room for a new row) and its visibility
-- map (_vm: which pages VACUUM has marked "all-visible" -- Part 4.5
-- uses it). A table over 1 GB continues in a second file, <name>.1,
-- then .2, and so on.
-- You can look at the same file from outside PostgreSQL. In a
-- terminal (pg = the container from start_postgres.sh; paste YOUR
-- path from the first query):
--     docker exec pg ls -l /var/lib/postgresql/18/docker/base/16384/16561*
-- An ordinary file of 489,381,888 bytes. 2.5 reads bytes from it.

-- ---- 2.2 A file is a row of 8 kB pages ----
SELECT current_setting('block_size') AS page_bytes,
       pg_relation_size('orders_big') AS file_bytes,
       pg_relation_size('orders_big') / current_setting('block_size')::int AS pages,
       round(count(*) / (pg_relation_size('orders_big') / 8192.0), 1) AS rows_per_page
FROM orders_big;
-- page_bytes | file_bytes | pages | rows_per_page
-- 8192       |  489381888 | 59739 |          83.7
-- 489,381,888 bytes = 59,739 pages x 8,192 bytes, exactly. PostgreSQL
-- never reads or writes less than a page: to get one row, it reads
-- the whole 8 kB page the row is on. That's why the plans in this
-- lecture count pages ("Buffers"), not rows. About 84 orders fit on a
-- page.

-- ---- 2.3 Every row has an address: ctid ----
-- Every table has a hidden column, ctid = (page number, slot in the
-- page). Pages are numbered from 0:
SELECT ctid, orderID, orderDate, customerID, status, orderTotal
FROM orders_big
WHERE orderID IN (1, 2, 3, 83, 84, 85, 86, 4890168)
ORDER BY orderID;
--    ctid    | orderid | orderdate  | customerid |  status   | ordertotal
-- (0,1)      |       1 | 2023-01-01 |      37147 | returned  |     476.82
-- (0,2)      |       2 | 2023-01-01 |      48472 | completed |     186.88
-- (0,3)      |       3 | 2023-01-01 |      15856 | completed |      36.88
-- (0,83)     |      83 | 2023-01-01 |      29372 | completed |     490.46
-- (0,84)     |      84 | 2023-01-01 |      43564 | completed |     657.51
-- (1,1)      |      85 | 2023-01-01 |      31986 | returned  |     333.24
-- (1,2)      |      86 | 2023-01-01 |      34116 | completed |     287.49
-- (58425,79) | 4890168 | 2025-12-11 |       4242 | completed |    1768.13
-- The rows were inserted in orderID order, so they fill page 0 (84
-- rows), then page 1, and so on. Nane's order 4890168 is in slot 79
-- of page 58,425.

-- With an address, PostgreSQL can go straight to a row.
-- Predict, then run: how many pages does this read?
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_big WHERE ctid = '(58425,79)';
--                                               QUERY PLAN
-- Tid Scan on orders_big  (cost=0.00..4.01 rows=1 width=60) (actual time=0.001..0.002 rows=1.00 loops=1)
--   TID Cond: (ctid = '(58425,79)'::tid)
--   Buffers: shared hit=1
-- Planning:
--   Buffers: shared hit=25
-- Planning Time: 0.034 ms
-- Execution Time: 0.005 ms
-- Tid Scan, 1 page ("shared hit=1"). Every index lookup ends exactly
-- like this: the index gives an address, the table page is read (2.6).
-- Don't keep ctids in your own tables, though: a row gets a new one
-- when it is updated (2.8).

-- Pages, not rows, are what a query pays for. Nane's 97 orders and one
-- day's 5,180 orders -- on how many different pages?
SELECT 'Nane (customer 4242)' AS rows_of, count(*) AS rows,
       count(DISTINCT (ctid::text::point)[0]) AS pages
FROM orders_big WHERE customerID = 4242
UNION ALL
SELECT 'one day (2025-06-15)', count(*),
       count(DISTINCT (ctid::text::point)[0])
FROM orders_big WHERE orderDate = '2025-06-15';
--       rows_of        | rows | pages
-- Nane (customer 4242) |   97 |    97
-- one day (2025-06-15) | 5180 |    63
-- Nane's 97 orders are on 97 different pages: she ordered on 97
-- different days, and orders are stored in the order they arrived.
-- One day's 5,180 orders are on 63 pages, side by side. 50 times the
-- rows on fewer pages. Parts 3 and 4 come back to this ("correlation",
-- and why 3% of the rows can be 93% of the pages).
-- ((ctid::text::point)[0] is a trick to pull the page number out of
-- the ctid.)

-- ---- 2.4 Inside one page ----
-- The pageinspect extension (part of PostgreSQL) shows a page as it is
-- on disk.
CREATE EXTENSION IF NOT EXISTS pageinspect;
-- The page header of orders_big's page 0:
SELECT lower, upper, special, pagesize, upper - lower AS free_bytes
FROM page_header(get_raw_page('orders_big', 0));
-- lower | upper | special | pagesize | free_bytes
--   360 |   408 |    8192 |     8192 |         48
-- And its slots: where each row starts in the page (lp_off), how many
-- bytes it has (lp_len), and its address:
SELECT lp AS slot, lp_off AS starts_at_byte, lp_len AS bytes, t_ctid
FROM heap_page_items(get_raw_page('orders_big', 0))
ORDER BY lp;
-- slot | starts_at_byte | bytes | t_ctid
--    1 |           8104 |    86 | (0,1)
--    2 |           8008 |    91 | (0,2)
--    3 |           7912 |    91 | (0,3)
--    4 |           7816 |    95 | (0,4)
-- ...   (78 more lines)
--   83 |            504 |    87 | (0,83)
--   84 |            408 |    91 | (0,84)
-- A page is filled from both ends:
--     | header 24 B | slot 1 | slot 2 | ... | slot 84 | free | row 84 | ... | row 2 | row 1 |
--     0                                  lower=360   upper=408                       8192
-- Slots (4 bytes each) grow from the front: 24 + 84 x 4 = 360 = lower.
-- Rows grow from the back: row 1 starts at byte 8104, row 84 at 408 =
-- upper. 48 bytes are left in the middle, too few for another order,
-- so order 85 went to page 1.
-- Pages are numbered 0 to 59,738. Error on purpose:
SELECT * FROM page_header(get_raw_page('orders_big', 59739));
-- ERROR:  block number 59739 is out of range for relation "orders_big"

-- ---- 2.5 The bytes of one row ----
-- Order 1 is slot 1 of page 0. Its columns, as stored:
SELECT a.attname AS column_name, encode(u.v, 'hex') AS bytes_on_disk
FROM heap_page_item_attrs(get_raw_page('orders_big', 0), 'orders_big') h,
     unnest(h.t_attrs) WITH ORDINALITY AS u(v, n)
JOIN pg_attribute a ON a.attrelid = 'orders_big'::regclass AND a.attnum = u.n
WHERE h.lp = 1
ORDER BY u.n;
--  column_name  |   bytes_on_disk
-- orderid       | 01000000
-- customerid    | 1b910000
-- employeeid    | 01000000
-- orderdate     | d1200000
-- ordertime     | 805a083709000000
-- channel       | 13696e5f73746f7265
-- paymentmethod | 0b63617264
-- status        | 1372657475726e6564
-- deliverydate  |
-- rating        |
-- ordertotal    | 0f0081dc010820
SELECT * FROM orders_big WHERE orderID = 1;
-- orderid | customerid | employeeid | orderdate  | ordertime | channel  | paymentmethod |  status  | deliverydate | rating | ordertotal
--       1 |      37147 |          1 | 2023-01-01 | 10:59:38  | in_store | card          | returned |              |        |     476.82
-- Read them side by side. orderid 01000000 is 1, written lowest byte
-- first. customerid 1b910000 is 0x911b = 37147. orderdate d1200000 is
-- 0x20d1 = 8401: a date is stored as days since 2000-01-01:
SELECT DATE '2000-01-01' + 8401 AS day_8401;
--  day_8401
-- 2023-01-01
-- status is the text 'returned' (72 65 74 75 72 6e 65 64), after one
-- length byte. deliverydate and rating are empty: a NULL takes no
-- bytes at all, only one bit in the row's header. Every row starts
-- with that header (23 bytes: which transaction wrote the row, which
-- one deleted it, and so on; plus the NULL bits when a column is NULL
-- -- 32 bytes for order 1), then its columns, one after another.
-- The same bytes are in the file. In a terminal (your path from 2.1):
--     docker exec pg od -A d -t x1 -j 8136 -N 16 /var/lib/postgresql/18/docker/base/16384/16561
--     0008136 01 00 00 00 1b 91 00 00 01 00 00 00 d1 20 00 00
-- Byte 8,136 of the file (row 1 starts at 8,104, plus its 32-byte
-- header): order 1, customer 37147, employee 1, and 2023-01-01. (Run CHECKPOINT first if the file looks older than the
-- table: PostgreSQL writes changed pages to the file a little later.)

-- ---- 2.6 An index entry is a key and an address ----
-- The primary key's index is a file of pages too. Its page 1 holds the
-- smallest orderIDs:
SELECT itemoffset AS entry, data AS key_bytes, htid AS row_address
FROM bt_page_items('orders_big_pkey', 1)
WHERE itemoffset BETWEEN 2 AND 5;
-- entry |        key_bytes        | row_address
--     2 | 01 00 00 00 00 00 00 00 | (0,1)
--     3 | 02 00 00 00 00 00 00 00 | (0,2)
--     4 | 03 00 00 00 00 00 00 00 | (0,3)
--     5 | 04 00 00 00 00 00 00 00 | (0,4)
-- Key 1 (01 00 00 00, padded to 8 bytes) -> row (0,1); key 2 -> (0,2).
-- An index is sorted keys, each with the address of its row. A lookup
-- finds the key in the index, then reads the table page at the
-- address: 2.3's Tid Scan, behind every Index Scan in Part 4.
-- (Entry 1 of an index page is a boundary marker for searching, not a
-- row; that's why we start at 2.)

-- ---- 2.7 Rows, not columns: why one column costs the whole table ----
-- A row's columns are stored together, one row after another. So what
-- does it take to add up ONE column?
SELECT pg_size_pretty(sum(pg_column_size(orderTotal))) AS ordertotal_bytes,
       pg_size_pretty(pg_relation_size('orders_big')) AS table_bytes
FROM orders_big;
-- ordertotal_bytes | table_bytes
-- 33 MB            | 467 MB
EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(orderTotal) FROM orders_big;
--                                                           QUERY PLAN
-- Aggregate  (cost=122240.04..122240.05 rows=1 width=32) (actual time=550.006..550.007 rows=1.00 loops=1)
--   Buffers: shared hit=15142 read=44597
--   ->  Seq Scan on orders_big  (cost=0.00..109739.83 rows=5000083 width=6) (actual time=0.006..149.522 rows=5000000.00 loops=1)
--         Buffers: shared hit=15142 read=44597
-- Planning:
--   Buffers: shared hit=9
-- Planning Time: 0.076 ms
-- Execution Time: 550.036 ms
-- The orderTotal values take 33 MB. To add them up, PostgreSQL read
-- all 59,739 pages, 467 MB: every column of every row, because the
-- totals are spread across every page. That is the right layout for
-- "show me order 4890168" (one page, all its columns) and the wrong one
-- for "sum one column over 5 million rows". Columnar formats (Parquet,
-- DuckDB -- the next lectures) store each column separately, so the
-- sum reads only the totals.

-- ---- 2.8 UPDATE writes a new row; the old one stays ----
-- A three-row table, so the whole thing fits on one page:
CREATE TABLE storage_demo (id int, name text, city text, total numeric(10,2));
INSERT INTO storage_demo VALUES
    (1, 'Nane Simonyan', 'Yerevan', 120.50),
    (2, 'Aram Petrosyan', 'Gyumri', 75.00),
    (3, 'Ani Hakobyan', 'Vanadzor', 9.99);
SELECT lp AS slot, lp_off AS starts_at_byte, lp_len AS bytes,
       encode(t_data, 'escape') AS row_bytes
FROM heap_page_items(get_raw_page('storage_demo', 0));
-- slot | starts_at_byte | bytes |                                 row_bytes
--    1 |           8128 |    57 | \x01\000\000\000\x1DNane Simonyan\x11Yerevan\x0F\000\201x\000\210\x13
--    2 |           8072 |    55 | \x02\000\000\000\x1FAram Petrosyan\x0FGyumri\x0B\000\201K\000
--    3 |           8008 |    57 | \x03\000\000\000\x1BAni Hakobyan\x13Vanadzor\x0F\000\201        \000\254&
-- The names and cities are readable inside the raw bytes; the numbers
-- around them are the id, the length bytes and the total. A row really
-- is just its columns, side by side.
-- xmin and xmax are two more hidden columns: the transaction that wrote
-- this version of the row, and the one that replaced or deleted it (0 =
-- nobody yet). Your transaction numbers will differ.
SELECT ctid, xmin, xmax, * FROM storage_demo;
-- ctid  | xmin | xmax | id |      name      |   city   | total
-- (0,1) |  975 |    0 |  1 | Nane Simonyan  | Yerevan  | 120.50
-- (0,2) |  975 |    0 |  2 | Aram Petrosyan | Gyumri   |  75.00
-- (0,3) |  975 |    0 |  3 | Ani Hakobyan   | Vanadzor |   9.99
UPDATE storage_demo SET total = 130.00 WHERE id = 1;
SELECT ctid, xmin, xmax, * FROM storage_demo;
-- ctid  | xmin | xmax | id |      name      |   city   | total
-- (0,2) |  975 |    0 |  2 | Aram Petrosyan | Gyumri   |  75.00
-- (0,3) |  975 |    0 |  3 | Ani Hakobyan   | Vanadzor |   9.99
-- (0,4) |  976 |    0 |  1 | Nane Simonyan  | Yerevan  | 130.00
-- Nane's row moved: (0,1) became (0,4). And without ORDER BY, she now
-- comes last -- the rows come back in the order they sit on the page.
-- What's in slot 1 now?
SELECT lp AS slot, t_xmin, t_xmax, t_ctid AS newer_version_at,
       encode(t_data, 'escape') AS row_bytes
FROM heap_page_items(get_raw_page('storage_demo', 0));
-- slot | t_xmin | t_xmax | newer_version_at |                                 row_bytes
--    1 |    975 |    976 | (0,4)            | \x01\000\000\000\x1DNane Simonyan\x11Yerevan\x0F\000\201x\000\210\x13
--    2 |    975 |      0 | (0,2)            | \x02\000\000\000\x1FAram Petrosyan\x0FGyumri\x0B\000\201K\000
--    3 |    975 |      0 | (0,3)            | \x03\000\000\000\x1BAni Hakobyan\x13Vanadzor\x0F\000\201        \000\254&
--    4 |    976 |      0 | (0,4)            | \x01\000\000\000\x1DNane Simonyan\x11Yerevan\x0B\000\201\202\000
-- Slot 1 still holds the OLD row (compare its last bytes, the total,
-- with slot 4's), marked "replaced by transaction t_xmax, newer
-- version at (0,4)". UPDATE never
-- overwrites a row: it writes a new version and marks the old one.
-- That's how other transactions can keep reading the old version while
-- yours is still running. DELETE only marks the row:
DELETE FROM storage_demo WHERE id = 3;
SELECT lp AS slot, t_xmin, t_xmax, t_ctid
FROM heap_page_items(get_raw_page('storage_demo', 0));
-- slot | t_xmin | t_xmax | t_ctid
--    1 |    975 |    976 | (0,4)
--    2 |    975 |      0 | (0,2)
--    3 |    975 |    977 | (0,3)
--    4 |    976 |      0 | (0,4)
-- Slot 3 is still there, with an xmax. The space of dead row versions
-- is freed only by VACUUM:
VACUUM storage_demo;
SELECT lp AS slot,
       CASE lp_flags WHEN 0 THEN 'free' WHEN 1 THEN 'row'
                     WHEN 2 THEN 'points to slot ' || lp_off WHEN 3 THEN 'dead' END AS slot_is,
       lp_off AS starts_at_byte, t_ctid
FROM heap_page_items(get_raw_page('storage_demo', 0));
-- slot |     slot_is      | starts_at_byte | t_ctid
--    1 | points to slot 4 |              4 |
--    2 | row              |           8136 | (0,2)
--    3 | free             |              0 |
--    4 | row              |           8080 | (0,4)
-- Slot 3 is free again; slot 1 now only forwards to slot 4 (an index
-- might still hold Nane's old address); the two live rows moved to the
-- end of the page, together.
DROP TABLE storage_demo;

-- ---- 2.9 The trap: deleting rows doesn't shrink the file ----
-- A copy of 2023 (1,371,464 orders) to experiment on:
CREATE TABLE orders_2023 AS
SELECT * FROM orders_big WHERE orderDate < '2024-01-01';
SELECT count(*) AS rows, pg_size_pretty(pg_relation_size('orders_2023')) AS size,
       pg_relation_size('orders_2023') / 8192 AS pages
FROM orders_2023;
--  rows   |  size  | pages
-- 1371464 | 128 MB | 16390
-- "Archive" January to November: delete 90% of the rows.
DELETE FROM orders_2023 WHERE orderDate < '2023-12-01';
SELECT count(*) AS rows, pg_size_pretty(pg_relation_size('orders_2023')) AS size,
       pg_relation_size('orders_2023') / 8192 AS pages
FROM orders_2023;
--  rows  |  size  | pages
-- 135984 | 128 MB | 16390
-- WRONG: "we deleted 90% of the rows, so the table is 10 times
-- smaller." 135,984 rows, and the file is still 128 MB: every deleted
-- row is still there, marked (2.8). A full scan still reads every page:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_2023;
--                                                         QUERY PLAN
-- Aggregate  (cost=24994.75..24994.76 rows=1 width=8) (actual time=10.754..10.754 rows=1.00 loops=1)
--   Buffers: shared hit=16261 read=129 written=1
--   ->  Seq Scan on orders_2023  (cost=0.00..23273.80 rows=688380 width=0) (actual time=2.993..7.507 rows=135984.00 loops=1)
--         Buffers: shared hit=16261 read=129 written=1
-- Planning Time: 0.044 ms
-- Execution Time: 10.773 ms
-- VACUUM removes the dead rows:
VACUUM orders_2023;
SELECT count(*) AS rows, pg_size_pretty(pg_relation_size('orders_2023')) AS size,
       pg_relation_size('orders_2023') / 8192 AS pages
FROM orders_2023;
--  rows  |  size  | pages
-- 135984 | 128 MB | 16390
-- Still 128 MB. VACUUM makes the space reusable INSIDE the table; it
-- doesn't give it back to the disk (only empty pages at the very end
-- of the file are cut off, and here the kept December rows are at the
-- end). The space isn't lost: new rows fill it. Three months of 2024
-- go in, and the file doesn't grow by a single page:
INSERT INTO orders_2023
SELECT * FROM orders_big WHERE orderDate >= '2024-01-01' AND orderDate < '2024-04-01';
SELECT count(*) AS rows, pg_size_pretty(pg_relation_size('orders_2023')) AS size,
       pg_relation_size('orders_2023') / 8192 AS pages
FROM orders_2023;
--  rows  |  size  | pages
-- 546555 | 128 MB | 16390
-- FIX, if you need the disk space back: VACUUM FULL writes the live
-- rows into a NEW file and deletes the old one.
SELECT pg_relation_filepath('orders_2023') AS file_before;
--   file_before
-- base/16675/16951
VACUUM FULL orders_2023;
SELECT count(*) AS rows, pg_size_pretty(pg_relation_size('orders_2023')) AS size,
       pg_relation_size('orders_2023') / 8192 AS pages,
       pg_relation_filepath('orders_2023') AS file_after
FROM orders_2023;
--  rows  | size  | pages |    file_after
-- 546555 | 51 MB |  6530 | base/16675/16954
-- 51 MB, and a different file name. The price: VACUUM FULL locks the
-- table completely (no reads, no writes) while it copies, and needs
-- room for both copies on disk. If you delete old data by date every
-- month, the better answer is partitions you can DROP (Part 9.8).
DROP TABLE orders_2023;

-- Clean up.
DROP EXTENSION pageinspect;
