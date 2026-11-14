# Lecture 7 — Performance: EXPLAIN, Indexing, Partitioning: Class Notes

*Scope: reading a plan (`EXPLAIN`, `ANALYZE`, `BUFFERS`), how a table is stored on disk (files, 8 kB pages, row addresses, what `UPDATE` and `DELETE` leave behind), statistics and estimates, scan types and selectivity, B-tree indexes and what they cost, composite / partial / covering / expression indexes, the traps that leave an index unused, plans for the alternatives Lectures 5 and 6 compared on correctness, partitioning, and when to do none of it. Grounded throughout in `lecture-07-demo.sql`. Every Demo number below comes from the same-numbered Part of the demo, run on PostgreSQL 18.6;[^demo] every timing is the median of three runs on one laptop, from `build/measurements-pg18.md`.[^measure]*

**Two kinds of data.**

- **The small shop, unchanged**, for every question about *correctness*: the same five CSV files as Lectures 4–6 (byte-identical copies in `data/`) and Lecture 4's star schema. 600 orders, 529 completed, completed revenue **157,078.41**, 30 customers (28 with orders), 8 employees, 37 products.
- **Two generated tables**, for every question about *speed*: `orders_big` (**5,000,000** orders, the same eleven columns as `orders`) and `customers_big` (**50,000** customers, the same columns as `customers`). 600 rows can't teach performance. Part 1.1 shows why.

**One sentence to carry through the lecture:**

> **A performance bug returns the right answer — slowly, or without the index you think it uses. The plan is the only place it shows.**

The course thesis is that SQL bugs are silent. For performance, the silent failures are a query that is right but slow, an index that exists but isn't used, and an "optimization" that changes the answer. Every topic below goes wrong (or slow) → why, read from the plan → fix, with the plan on screen at each step.

---

## Part 0 — Setup: one script, a 5-million-row table

From the `lecture_7/` folder:

```
psql postgres
\i steps/00-setup.sql
```

As in Lectures 5 and 6, it **drops and recreates the `lecture07` database** (start `psql` in another database), loads the small shop with Lecture 6's statements, and ends with checks: **30 / 8 / 37 / 600 / 965**, **366 / 965** for the star, **50,000 / 5,000,000** for the big tables, and **529** completed orders worth **157,078.41**.

**The generated data.** `orders_big` is built by one `INSERT ... SELECT` over `generate_series(1, 5000000)`, with `random()` after `setseed(0.42)`, so every machine gets the same rows:[^random]

| Column | How it's generated | Result |
|---|---|---|
| `orderID` | 1 … 5,000,000, in date order | like a real order counter |
| `orderDate` | 2023-01-01 … 2025-12-31, growing a little each year | 1,371,464 / 1,733,359 / 1,895,177 per year |
| `customerID` | 48,000 customers, about 104 orders each; every 25th customer (25, 50, …, 50,000) never orders | 2,000 customers with no orders |
| `status` | about 92% completed, 4.8% returned, 3.2% cancelled | 4,600,224 / 239,874 / 159,902 |
| `channel`, `employeeID` | a third online, and online orders have **no** employee, as in the small data | 1,650,020 online, all with NULL `employeeID` |

`customers_big` reuses the small shop's first and last names, gives every customer a unique email (`nane.simonyan4242@mail.ru` is customer 4242, Nane Simonyan of Yerevan, with 97 orders, the customer this lecture keeps coming back to) and sets `moneySpent` to completed revenue, as in `customers`.

**Size and time.** `orders_big`: **467 MB** for the table itself (59,739 pages of 8 kB), plus a 107 MB primary key. `customers_big`: 6.6 MB. The setup takes **about 42 seconds** on the reference machine (Intel i7-13700H laptop, NVMe disk, PostgreSQL 18.6 in Docker), most of it the 5-million-row insert. The whole lecture, with the partitioned copies of Part 9, needs about 2.5 GB of disk at its peak. 5 million rows was the target size and it fitted without trouble, so nothing was reduced.

**Two settings pinned, for this database only.** The setup runs `ALTER DATABASE lecture07 SET max_parallel_workers_per_gather = 0` and `SET jit = off`. With parallel query on (the default is 2 workers), big scans split across processes, plans grow `Gather` nodes, and timings depend on your core count. With JIT on, every query costing over 100,000 units (`jit_above_cost`[^config]) adds a compile step whose time varies between runs. Everything else stays at PostgreSQL's defaults: `shared_buffers` 128 MB, `work_mem` 4 MB, `random_page_cost` 4, `effective_cache_size` 4 GB.[^config] The notebook's first cells show your values.

**Autovacuum is off for `orders_big` only** (`WITH (autovacuum_enabled = off)`), so its statistics (Part 3) and visibility map (Part 4) change only when the lecture says so. The setup runs `VACUUM ANALYZE` itself. Never do this to a real table.

**Version.** The lecture needs **PostgreSQL 11 or later** (13 for one query in Part 2.6), and Part 2 needs a superuser (`pageinspect`, `pg_ls_dir`; the Docker setup's `postgres` user is one). The generated data is identical on **15 and later**: PostgreSQL 15 changed `random()`'s algorithm, so on 14 the same seed gives different, equally shaped rows, and the numbers in these notes won't match exactly.[^random] (PostgreSQL 14 reaches end of life on 12 November 2026.[^eol])

| Feature | Since |
|---|---|
| Declarative partitioning (`PARTITION BY RANGE` / `LIST`) | 10[^v10] |
| `INCLUDE` (covering indexes), `DEFAULT` partitions, hash partitioning, primary keys and unique indexes on partitioned tables (with the partition key), partition pruning at execution time | 11[^v11] |
| B-tree deduplication (small indexes on repeated values, Part 5.3); `pageinspect`'s `htid` column (Part 2.6) | 13[^v13] |
| `random()` results identical across machines with the same seed | 15[^random] |
| `EXPLAIN ANALYZE` prints `Buffers` without being asked, `Index Searches`, fractional row counts (`rows=97.00`), B-tree skip scan | 18[^v18] |

Cross-checked on PostgreSQL 14, 16 and 18; the differences are listed in the TODO section at the end.

**The notebook.** `lecture-07-notebook.py` walks through the lecture in marimo, as in Lectures 5 and 6:

```
LECTURE07_DSN=postgresql://postgres:postgres@localhost:5432/lecture07 marimo edit lecture-07-notebook.py
```

It changes the database as it goes (indexes and tables come and go), so run it top to bottom; each Part removes what it creates. `EXPLAIN` output is shown as text, not as a table, and each plan cell checks the plan's *shape* (node names, and whether a condition is an `Index Cond` or a `Filter`) against the reference run. A green box means "same plan as the notes"; a yellow one shows both shapes side by side.

---

## Part 1 — Reading a plan

### 1.1 Why 600 rows can't teach this

"All orders of customer 5" on the small `orders` table, with no index and then with one. **Demo:** without an index, a `Seq Scan`; with one, the planner does use it (a `Bitmap Heap Scan`). In the demo run they took **0.06 ms** and **0.02 ms**. The whole table is **8 pages** (64 kB). Both plans finish in hundredths of a millisecond, so there is nothing to measure and nothing to learn about speed. Hence the generated tables: `orders_big` is **59,739 pages**.

### 1.2 `EXPLAIN`: the plan, without running anything

```sql
EXPLAIN
SELECT * FROM orders_big WHERE customerID = 4242;
```

```
Seq Scan on orders_big  (cost=0.00..122240.04 rows=106 width=60)
  Filter: (customerid = 4242)
```

One step (a *node*): read every row, keep those that pass the `Filter`. The brackets are **estimates**:[^using]

- `cost=0.00..122240.04`: the cost until the first row, then until the last, in the planner's own units ("traditional practice is to measure the costs in units of disk page fetches"). These are not milliseconds. Use them to compare plans for the *same* query.
- `rows=106`: how many rows the planner expects this node to return.
- `width=60`: the average row size in bytes.

Your last digits may differ: estimates come from a random sample (Part 3).

### 1.3 `EXPLAIN ANALYZE`: run it and measure

`EXPLAIN ANALYZE` **runs** the query and adds what really happened to each node: `actual time=first..last` in milliseconds, `rows=97.00` (estimated 106: close), `loops=1`. **Demo number:** `Rows Removed by Filter: 4999903`. It read five million rows to return 97, in **128 ms** (median).

### 1.4 `BUFFERS`: count pages, not milliseconds

`EXPLAIN (ANALYZE, BUFFERS)` adds how many 8 kB pages each node touched. `shared hit` means the page was in PostgreSQL's own cache (`shared_buffers`); `read` means it had to be asked for from the operating system. **Demo number:** hit + read = **59,739**, every page of the table. Page counts don't depend on how fast your laptop is, which makes them the fairest number for comparing two plans. PostgreSQL 18 includes `Buffers` in every `EXPLAIN ANALYZE` without being asked; before 18 you must write `BUFFERS`.[^explain]

### 1.5 Read a plan inside out

"Nane's orders per status, most first" (`GROUP BY status ORDER BY orders DESC`):

```
Sort                                   ← 4. ORDER BY orders DESC: 3 rows
  ->  GroupAggregate                   ← 3. one row per status: 3 rows
        ->  Sort                       ← 2. sort the 97 rows by status
              ->  Seq Scan on orders_big   ← 1. find Nane's 97 rows
```

The most indented node runs first and feeds the one above it. A node's cost and time **include** its children's,[^using] so nearly all of this query's time is the scan at the bottom.

### 1.6 The hazard: `EXPLAIN ANALYZE` really runs the statement

On a temporary copy of `orders`: **600** rows. `EXPLAIN ANALYZE DELETE FROM orders_copy WHERE status = 'cancelled'` prints a plan, and the copy then has **573**. The 27 cancelled orders are gone, with no warning. The documentation is direct: "the statement is actually executed when the ANALYZE option is used".[^explain]

**Fix:** wrap it in a transaction and roll it back:

```sql
BEGIN;
EXPLAIN ANALYZE DELETE FROM orders_copy WHERE status = 'returned';
ROLLBACK;
```

The plan and timings are real; afterwards the copy still has **573** rows. Do this for every `INSERT`, `UPDATE` or `DELETE` you analyze. Plain `EXPLAIN` never runs anything.

### 1.7 Cold and warm: run it three times

The same range of 10,000 orders through the primary key, three times. **Demo:** the first run shows `shared read=150`, runs 2 and 3 `shared hit=150`. The plan, the rows and the page count are identical; only where the pages came from changed, and with it the time. The same `Seq Scan` three times shows `read=` of about 45,000 pages **every** time: a sequential scan of a table bigger than a quarter of `shared_buffers` goes through a small 256 kB ring of buffers, so one big scan can't push everything else out of the cache.[^ring] The pages come from the operating system's file cache instead, which is why the scan is still fast.

**The rule for the rest of the lecture:** one timing proves nothing. Run three times, take the median, and compare plan shape and pages before you compare milliseconds.

---

## Part 2 — How a table is stored on disk

Part 1 counted pages. This Part opens them. Everything later in the lecture follows from four facts, each shown below:

- **A table is a file.**
- **The file is a row of 8 kB pages.**
- **Every row sits in one page, at an address (page, slot).**
- **A changed or deleted row stays where it was until `VACUUM`.**

That explains why a `Seq Scan` reads every page, what an index stores, why 3% of the rows can be 93% of the pages (Part 4.2), and why `VACUUM` keeps coming up.

Part 2 uses two admin tools that need a superuser, which the `postgres` user of our Docker setup is: `pg_ls_dir`[^adminfn] and the `pageinspect` extension, which ships with PostgreSQL and "allow[s] you to inspect the contents of database pages at a low level".[^pageinspect]

### 2.1 A table is a file

`pg_relation_filepath('orders_big')` gives `base/16384/16561`, relative to the data directory (`/var/lib/postgresql/18/docker` in the Docker image): the folder of the database, then the table's file. The numbers are just names and differ on every machine.[^filelayout] **Demo:** that folder holds three files for `orders_big`:

| File | Size | What's in it |
|---|---:|---|
| `16561` | 467 MB (489,381,888 bytes) | the rows |
| `16561_fsm` | 136 kB | the *free space map*: which pages have room for a new row |
| `16561_vm` | 16 kB | the *visibility map*: which pages `VACUUM` marked all-visible (Part 4.5) |

A table over 1 GB continues in `16561.1`, `16561.2`, and so on.[^filelayout] It is an ordinary file, and you can list it from a terminal: `docker exec pg ls -l /var/lib/postgresql/18/docker/base/16384/16561*`, with your own numbers.

### 2.2 A file is a row of 8 kB pages

**Demo numbers:** `block_size` **8192**. **489,381,888 bytes = 59,739 pages × 8,192**, exactly, and about **84** orders per page. "Every table and index is stored as an array of pages of a fixed size (usually 8 kB)."[^pagelayout] PostgreSQL reads and writes whole pages: to get one row, it reads the 8 kB page the row is on. That's why every plan in this lecture counts pages (`Buffers`), not rows.

### 2.3 Every row has an address: `ctid`

Every table has a hidden column `ctid`, the row's (page, slot).[^syscols] **Demo:** orders 1–84 are `(0,1)` … `(0,84)`; order 85 is `(1,1)`, the first row of page 1; Nane's order 4890168 is `(58425,79)`. The rows were inserted in `orderID` order, so they filled the pages in that order.

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_big WHERE ctid = '(58425,79)';
```

A `Tid Scan`: **1 page** (`shared hit=1`). Every index lookup ends exactly like this: the index gives an address, and the table page at that address is read (2.6). Don't store ctids yourself: "a row's `ctid` will change if it is updated or moved by `VACUUM FULL`."[^syscols]

**Demo numbers, rows vs pages:**

| Rows of | Rows | Pages |
|---|---:|---:|
| Nane (customer 4242) | 97 | **97** |
| one day (2025-06-15) | 5,180 | **63** |

Nane's orders are spread over 97 different days, and orders are stored in the order they arrived, so each one sits on its own page. One day's 5,180 orders sit side by side. That's 50 times the rows on fewer pages. This is what `pg_stats.correlation` measures (Part 3.1), and it decides the scan types in Part 4.

### 2.4 Inside one page

`page_header(get_raw_page('orders_big', 0))` and `heap_page_items(...)` show page 0 as it is on disk.[^pageinspect] **Demo numbers:** `lower` **360**, `upper` **408**, **48** bytes free; slot 1's row starts at byte **8104**, slot 84's at **408**. A page fills from both ends:[^pagelayout]

```
| header 24 B | slot 1 | slot 2 | … | slot 84 |  free  | row 84 | … | row 2 | row 1 |
0                                   lower=360   upper=408                          8192
```

The slots (4 bytes each, "an (offset,length) pair") grow from the front: 24 + 84 × 4 = 360. The rows grow from the back. Where they meet, 48 bytes were left, too few for another order, so order 85 started page 1. `lower` and `upper` are the "offset to start of free space" and "offset to end of free space".[^pagelayout] Pages are numbered from 0, so asking for page 59,739 is the **error on purpose**: `block number 59739 is out of range for relation "orders_big"`.

### 2.5 The bytes of one row

`heap_page_item_attrs` returns order 1's columns exactly as stored. **Demo:**

| Column | Bytes on disk | Value |
|---|---|---|
| `orderid` | `01000000` | 1 (lowest byte first) |
| `customerid` | `1b910000` | 0x911b = 37147 |
| `employeeid` | `01000000` | 1 |
| `orderdate` | `d1200000` | 0x20d1 = 8401 days after 2000-01-01 = **2023-01-01**[^epoch] |
| `status` | `13` + `72 65 74 75 72 6e 65 64` | a length byte, then `returned` |
| `deliverydate`, `rating` | *(none)* | NULL |

A NULL takes **no bytes**: only a bit in the row's header ("a 0 bit is a null").[^pagelayout] Every row starts with a header of 23 bytes, which records which transaction wrote the row and which one deleted it.[^pagelayout] Order 1 has NULLs, so its header also carries those bits and, padded, is 32 bytes. Then the columns follow, one after another.

The same bytes are in the file. Row 1 starts at byte 8,104 and its columns at 8,104 + 32:

```
$ docker exec pg od -A d -t x1 -j 8136 -N 16 /var/lib/postgresql/18/docker/base/16384/16561
0008136 01 00 00 00 1b 91 00 00 01 00 00 00 d1 20 00 00
```

That's order 1, customer 37147, employee 1, 2023-01-01, read straight from the disk. (Run `CHECKPOINT` first if the file looks older than the table: changed pages reach the file a little later.)

### 2.6 An index entry is a key and an address

`bt_page_items('orders_big_pkey', 1)`, the primary key's first leaf page. **Demo:** key `01 00 00 00 00 00 00 00` → row `(0,1)`, key 2 → `(0,2)`, and so on. A B-tree index is a file of pages too, holding sorted keys, each with the address of its row (the `htid`).[^pageinspect] An `Index Scan` finds the key in the index, then reads the table page at the address. That's 2.3's `Tid Scan`, behind every index in Parts 5–7. Entry 1 on each page is skipped: it's a "high key", a boundary for searching, and "not a tuple that is used to visit the heap".[^nbtree]

### 2.7 Rows, not columns: why one column costs the whole table

**Demo numbers:** the `orderTotal` values take **33 MB** (`sum(pg_column_size(orderTotal))`). `SELECT sum(orderTotal) FROM orders_big` read all **59,739** pages, **467 MB**: every column of every row, because each row's columns are stored together and the totals are spread across every page.

This layout is right for "show me order 4890168" (one page, all its columns) and wrong for "sum one column over 5 million rows". **This is why the next lectures move to columnar formats:** Parquet and DuckDB store each column separately, so that sum reads only the totals.

### 2.8 `UPDATE` writes a new row; the old one stays

A three-row table, `storage_demo`. **Demo:** `encode(t_data, 'escape')` shows the raw row, and `Nane Simonyan` and `Yerevan` are readable in it. `xmin` and `xmax` are two more hidden columns: the transaction that wrote this version of the row, and the one that replaced or deleted it (0 = nobody yet).[^syscols]

`UPDATE storage_demo SET total = 130.00 WHERE id = 1` gives this:

- **Nane's row moves** from `(0,1)` to `(0,4)`.
- **Without `ORDER BY`, she now comes last**, because rows come back in page order.
- **Slot 1 still holds the old row.** Its `t_xmax` is the updating transaction and its `t_ctid` points to `(0,4)`, the newer version.

"In PostgreSQL, an `UPDATE` or `DELETE` of a row does not immediately remove the old version of the row."[^routine] That's how other transactions can keep reading the old version while yours runs. `DELETE ... WHERE id = 3` likewise leaves slot 3 in place, with an `xmax`.

After `VACUUM`:
- slot 3 is **free**;
- slot 1 only **points to slot 4**, so an index holding Nane's old address still finds her;[^hot]
- the two live rows have moved together at the end of the page.[^itemid]

### 2.9 The trap: deleting rows doesn't shrink the file

A copy of 2023 (**1,371,464** orders, **128 MB**, 16,390 pages). "Archive" January to November: `DELETE` **1,235,480** rows.

The natural conclusion, "we deleted 90% of the rows, so the table is 10 times smaller", is wrong. **Demo numbers:**

| Step | Rows | File |
|---|---:|---:|
| copy of 2023 | 1,371,464 | 128 MB (16,390 pages) |
| after `DELETE` of Jan–Nov | 135,984 | **128 MB** (16,390 pages) |
| after `VACUUM` | 135,984 | **128 MB** (16,390 pages) |
| after inserting Jan–Mar 2024 | 546,555 | **128 MB** (16,390 pages) |
| after `VACUUM FULL` | 546,555 | **51 MB** (6,530 pages), a new file name |

After the `DELETE`, a `count(*)` still read all 16,390 pages: the deleted rows are still there, marked (2.8). Plain `VACUUM` "reclaims space and makes it available for re-use … However, extra space is not returned to the operating system (in most cases)".[^vacuumcmd] The exception is empty pages at the very end of the file, and here the December rows we kept are at the end.[^routine] The space isn't lost: 410,571 new rows went in without the file growing by a single page.

**Fix, if you need the disk back:** `VACUUM FULL` "rewrites the entire contents of the table into a new disk file". It takes "an `ACCESS EXCLUSIVE` lock" (no reads, no writes) while it runs, and "requires extra disk space, since it writes a new copy of the table".[^vacuumcmd] **Demo:** 51 MB, and `pg_relation_filepath` changed. If you delete old data by date every month, the better answer is partitions you can `DROP` (Part 9.8).

This is the course's pattern again: the `DELETE` succeeded and the counts are right, but the table is exactly as big and as slow to scan as before.

---

## Part 3 — Statistics and estimates

### 3.1 What the planner knows

The planner never looks at the data while planning. It works from statistics that `ANALYZE` builds from a random sample:[^analyze] the table's row and page counts (`pg_class`), and per column (`pg_stats`) the number of distinct values, the most common values with their frequencies, and the *correlation* between the column's order and the rows' order on disk.[^pgstats]

**Demo numbers** (they differ a little on every `ANALYZE`, because the sample is random):[^analyze] the planner thinks `orders_big` has about 5,000,000 rows but not exactly (**5,000,083** in the demo run: it's an estimate) on **59,739** pages; `status` is about **92 / 5 / 3%** completed / returned / cancelled; `customerID` has about **48,000** distinct values (**47,231** in the demo run; really 48,000) and correlation about **0**; `orderDate` and `orderID` have correlation **1.000**, because the rows were written in date order. That number matters in Part 4.

### 3.2 Estimated vs actual

`count(*) WHERE status = 'cancelled'`: estimated within a few percent (**166,003** in the demo run), actual **159,902**. Close, because `cancelled` is in the most-common-values list. When the estimates are close, the plan is chosen on true numbers.

### 3.3 The trap: a bulk load without `ANALYZE`

January 2026 arrives: **200,000** new orders in one `INSERT`, and no `ANALYZE` (autovacuum is off for this table, Part 0; on a real server it would get there eventually, possibly after your report ran). The first report on the new month:

```sql
SELECT c.city, count(*) AS orders, sum(o.orderTotal) AS revenue
FROM orders_big o
JOIN customers_big c ON c.customerID = o.customerID
WHERE o.orderDate >= '2026-01-01'
GROUP BY c.city;
```

**Demo:** the `Seq Scan` on `orders_big` estimated a few hundred January rows (**476** in the demo run); there are **200,000**. The statistics end on 2025-12-31. Everything above that node was planned for a few hundred rows:

- a **Nested Loop**: for each January order, look up its customer through the primary key, **200,000 separate lookups** (`loops=200000`);
- a **Sort** to group by city, which spilled to disk (`Sort Method: external merge  Disk: 4880kB`).

The four city totals are correct. No error.

### 3.4 Fix: `ANALYZE`

After `ANALYZE orders_big`, the same query is estimated at about 200,000 rows and the plan changes shape: a **Hash Join** (read the 50,000 customers once into a hash table, match each January order against it) and a **HashAggregate** in memory. **Demo numbers:** the nested-loop plan touched **662,011** pages and the hash plan **62,831**; median **408 ms → 244 ms**, about 1.7 times faster. Same four rows.

The documentation's advice: "Whenever you have significantly altered the distribution of data within a table, running ANALYZE is strongly recommended. This includes bulk loading large amounts of data into the table."[^populate]

### 3.5 The rule of thumb

In any slow plan, look first for the node where estimated and actual rows differ by **a factor of 10 or more**, usually the lowest such node. Every decision above it was made for the wrong number. (A course rule of thumb, not a PostgreSQL rule.) Then `orders_big` goes back to exactly 5,000,000 rows: `DELETE` the January rows, `VACUUM ANALYZE`.

---

## Part 4 — Scan types, and what the planner chooses

| Node | What it does | Chosen when |
|---|---|---|
| `Seq Scan` | read every page, in order | a large share of the table is needed |
| `Index Scan` | find entries in the index, fetch each row | few rows, or rows that sit together on disk |
| `Bitmap Heap Scan` | collect the matching pages from the index, then read each page once, in disk order | more rows, spread out |
| `Index Only Scan` | answer from the index alone | every column the query needs is in the index |

The deciding factor is **selectivity**: what share of the table the query needs, counted in pages, not just rows.

### 4.1 One day: `Index Scan`

`count(*), sum(orderTotal)` for 2025-06-15, with an index on `orderDate`. **Demo numbers:** **5,180** rows (0.1%), `Index Scan`, **70 pages**. One day's orders sit next to each other on disk (correlation 1, Part 3.1), so 5,180 rows share a few dozen pages (63 table pages, Part 2.3; the rest are index pages).

### 4.2 Cancelled orders: `Bitmap Heap Scan`, and a surprise

**Demo numbers:** **159,902** rows (3.2%), `Bitmap Heap Scan` — but `Heap Blocks: exact=55814`. The cancelled orders are scattered, so **3% of the rows live on 93% of the pages** (55,814 of 59,739). The index saves almost nothing here.

### 4.3 Completed orders: `Seq Scan`, with the index right there

**Demo numbers:** **4,600,224** rows (92%). The index on `status` exists and the planner doesn't use it. Forced through it (`SET enable_seqscan = off`, a testing switch that "discourages" a plan type[^config]): a `Bitmap Heap Scan` that reads **63,674** pages, the whole table plus 3,935 index pages. With bitmaps off too, a plain `Index Scan` reads the same 63,674. Medians: planner's `Seq Scan` **631 ms**, forced bitmap **629 ms**, forced index scan **771 ms**. "The index isn't used" was the right decision. **Don't teach yourself "always add an index"; teach yourself "read the plan".**

### 4.4 `Index Only Scan`: the answer is in the index

`count(*)` for one day needs only `orderDate`, and `orderDate` is in the index. **Demo numbers:** `Index Only Scan`, **8 pages** instead of 70, `Heap Fetches: 0`.

### 4.5 The visibility map: why `Heap Fetches` isn't always 0

An index doesn't know whether the row it points to is visible to your transaction. PostgreSQL keeps one bit per table page, the *visibility map*, saying "every row here is visible to everyone". An index-only scan trusts pages with the bit set; any other page must be read, "so no performance advantage is gained over a standard index scan".[^ios] `VACUUM` sets the bits.

**Demo:** a freshly built copy of 2025's orders (`CREATE TABLE orders_2025 AS ...`, never vacuumed) with an index on `orderDate`. Same query: still called `Index Only Scan`, but `Heap Fetches: 5180` and **70 pages**. After `VACUUM orders_2025`: `Heap Fetches: 0`, **8 pages**. Same plan name, very different work: read the numbers under the node, not just its name.

---

## Part 5 — B-tree indexes, and what they cost

### 5.1 – 5.2 Before and after

Nane's orders, `customerID = 4242`. **Before:** `Seq Scan`, **59,739** pages. **After** `CREATE INDEX orders_big_customerid_idx ON orders_big (customerID)`: `Bitmap Index Scan` (3 index pages: root, branch, leaf) + `Bitmap Heap Scan` (`Heap Blocks: exact=97`: her 97 orders are on 97 different pages), **100 pages**. Medians: **128 ms → 0.04 ms**, thousands of times faster on the reference machine (at that size a timing is noise-dominated; the page counts, 59,739 vs 100, are the solid number). Same 97 rows.

### 5.3 What it costs: space

**Demo numbers:** table **467 MB**, primary key **111 MB** (5 million different `orderID`s; it was 107 MB before Part 3's insert and delete), `customerID` index **34 MB**. The `customerID` index is a third of the primary key because a B-tree stores a repeated value once with a list of its rows (*deduplication*, PostgreSQL 13+[^btree] [^v13]), and each customer repeats about 104 times.

### 5.4 What it costs: every write

The same **1,000,000** orders loaded into an empty copy (`orders_load`, so `orders_big` stays untouched) with no index, one, and five. (The brief asked for inserts into `orders_big` itself; an empty copy keeps each run independent and leaves no dead rows behind. See TODO.)

| Indexes on `orders_load` | Median insert time | vs no index | Pages touched by the insert (one run) |
|---|---:|---:|---:|
| 0 | 574 ms | 1× | about 1.0 million |
| 1 (`customerID`) | 1,496 ms | 2.6× | about 3.8 million |
| 5 (+ `orderDate`, `status`, `employeeID`, `orderTotal`) | 4,868 ms | 8.5× | about 13.5 million |

Each index is another structure to update for every row, in another place. The five indexes add **59 MB** to a **93 MB** table (`orderTotal` alone is 29 MB: almost every value is different, so deduplication can't help).

### 5.5 `ORDER BY ... LIMIT`: an index is already sorted

"The ten biggest orders ever." **Without** an index on `orderTotal`: `Seq Scan` of all 5 million rows + `Sort` (`top-N heapsort`), median **710 ms**. **With** `(orderTotal DESC, orderID)`: `Limit` over an `Index Scan`, **no Sort node**, **13 pages**, median **0.02 ms**.

### 5.6 `JOIN`: an index on the join column

"Look Nane up by email, list her latest five orders": `Index Scan using customers_big_email_key` (the `UNIQUE` constraint on email is enforced by an index) finds one customer; a `Nested Loop` then uses the `customerID` index to find her 97 orders. Nested loop means "for each row outside, look up the inside". It's cheap when the outside is small and the inside has an index. (Part 8.5 shows the other join methods.)

### 5.7 `GROUP BY`: sometimes

`customerID, count(*) GROUP BY customerID`: with the index, the planner reads it end to end (`Index Only Scan`) and gets the rows already grouped, so `GroupAggregate` needs no sort and no hash table. With index scans disabled, a `HashAggregate` over a `Seq Scan`. Medians: **354 ms vs 609 ms**. Both read everything, so neither is dramatic. "Sometimes" is the honest word for `GROUP BY`.

---

## Part 6 — Composite, partial, covering and expression indexes

### 6.1 Composite index: column order matters

`CREATE INDEX ... ON orders_big (customerID, orderDate)` is sorted by customer first, and by date within each customer, like a phone book sorted by last name, then first name.

| Query | Plan | Index pages read | Table pages |
|---|---|---:|---:|
| (a) `customerID = 4242` | `Bitmap Index Scan`, Index Cond on customerid | 3 | 97 |
| (b) `customerID = 4242 AND orderDate >= '2025-01-01'` | Index Cond on **both** columns | 3 | 43 |
| (c) `orderDate = '2025-12-01'` | `Bitmap Index Scan`, Index Cond on orderdate | **13,539** (all of it) | 64 |

The trap is (c). The plan **names** the index, with `orderDate` in the `Index Cond`, but the buffers show it read the whole index. A phone book sorted by last name can't jump to every "Anna". The documentation: constraints on later columns "do not necessarily reduce the portion of the index that has to be scanned".[^multicol] Medians for (c): `Seq Scan` with no index **160 ms**, the composite index **50 ms**, a dedicated `orderDate` index **0.40 ms** (71 pages).

PostgreSQL 18 adds **skip scan**, which can jump through a composite index when the first column has "so few distinct values that the planner expects the scan to skip over most of the index".[^multicol] With 48,000 customers, it doesn't apply: the plan shows `Index Searches: 1`, one pass. **The rule:** a composite index serves queries that filter on its leftmost column(s).

### 6.2 Partial index: only the rows you ask about

`CREATE INDEX ... ON orders_big (orderDate) WHERE status = 'returned'`: **1,672 kB**, against 34 MB for a full `orderDate` index.

- `status = 'returned' AND orderDate >= '2025-12-01'` → `Index Scan` on the partial index, **8,062** rows, median **1.90 ms**.
- `status IN ('returned', 'cancelled') AND ...` → **`Seq Scan`**, **13,430** rows, median **336 ms**. The index holds no cancelled orders, so it can't answer.
- `status <> 'completed' AND status <> 'cancelled' AND ...` → **`Seq Scan`**, although with the `CHECK` constraint that can only mean "returned". The documentation explains: "PostgreSQL does not have a sophisticated theorem prover … the predicate condition must exactly match part of the query's WHERE condition or the index will not be recognized as usable."[^partial]

**Write the condition the index was built with.**

### 6.3 Covering index (`INCLUDE`)

Nane's lifetime spending, `count(*), sum(orderTotal) WHERE customerID = 4242`. With the plain `customerID` index: 3 index pages + 97 table pages, only to read `orderTotal`. With `CREATE INDEX ... (customerID) INCLUDE (orderTotal)`: `Index Only Scan`, `Heap Fetches: 0`, **5 pages**. `INCLUDE` columns are carried in the index but "never used to guide index scans".[^ios] **The price:** **150 MB** against **34 MB**, more than four times bigger, because "INCLUDE indexes can never use deduplication".[^btree] Needs PostgreSQL 11.[^v11] (Medians 0.05 vs 0.02 ms: at this size, compare the pages.)

### 6.4 Expression index

At login, Nane types `Nane.Simonyan4242@Mail.ru`; the app compares `lower(email) = lower(...)`. **Demo:** `Seq Scan` over all 50,000 customers, although `email` has a `UNIQUE` index. That index holds `email`, not `lower(email)`. `CREATE INDEX ... (lower(email))` + `ANALYZE` → `Index Scan`, one row. The query must use **the same expression** as the index.[^expr] Expression indexes cost more on every insert, because the expression is computed for each row.[^expr]

---

## Part 7 — Traps: the index exists but is not used

One reading skill for this whole Part: a condition the index can *search* appears as **`Index Cond:`**; a condition checked row by row appears as **`Filter:`**, even when the node's name says "Index".

Indexes on `orderDate` and `customerID` exist throughout.

### 7.1 A function on the indexed column

`WHERE date_trunc('month', orderDate) = '2025-06-01'`. **Demo:** `Seq Scan`. The index is sorted by `orderDate` and knows nothing about `date_trunc(orderDate)`. The estimate is off too: the planner has no statistics on the expression and guesses a fixed 0.5% (`DEFAULT_EQ_SEL`[^selfuncs]), so **25,000** against **155,419** actual. Two `extract(...)` conditions guess 0.5% of 0.5%: **125** rows.

- **Fix 1: a range on the column.** `orderDate >= '2025-06-01' AND orderDate < '2025-07-01'` → `Index Scan`, estimate close to 155,419, same answer. Median **548 ms → 22 ms** (25×). Write "≥ first day AND < first day of the next month": it is right for timestamps too, where `BETWEEN ... '2025-06-30'` would lose June 30 after midnight.
- **Fix 2: an expression index.** `CREATE INDEX ... (date_trunc('month', orderDate))` fails: **`ERROR: functions in index expression must be marked IMMUTABLE`**. On a `date`, `date_trunc` goes through `timestamp with time zone` (it's visible in the first plan's `Filter`), whose result depends on the session's time zone, and index expressions must "depend only on their arguments".[^createindex] `date_trunc('month', orderDate::timestamp)` is immutable: it works, for queries written with exactly that expression. Prefer Fix 1.

### 7.2 A type mismatch

`WHERE customerID = 4242.0` (an app passing a decimal). **Demo:** the node is `Index Only Scan using orders_big_customerid_idx`, but there is **no `Index Cond`**, only `Filter: ((customerid)::numeric = 4242.0)` with `Rows Removed by Filter: 4999903`. To compare an integer with a numeric, PostgreSQL converts the **column**, row by row, so the index can't be searched. It reads all 5 million entries (about 100,000 pages). Median **269 ms** against **0.02 ms** for `customerID = '4242'`: a quoted literal has no type yet and becomes an integer. `customerID::text = '4242'` is the same trap (a cast on the column is a function on the column). **Fix:** make the *value* the column's type, never cast the column.

### 7.3 `LIKE 'text%'` and `LIKE '%text'`

A search box: the user has typed the start of an email, `email LIKE 'nane.simonyan4242%'` (1 customer, Nane). **Demo:** `Seq Scan` over all 50,000 rows, despite the `UNIQUE` index on email. Our database's collation is **`en_US.utf8`**, and under language rules a B-tree's order can't be used for `LIKE`. **Fix:** an index with `varchar_pattern_ops`, which compares "strictly character by character": `Index Scan`, `Index Cond: email ~>=~ 'nane.simonyan4242' AND email ~<~ 'nane.simonyan4243'`, 4 pages. A prefix is a range of the sorted index. With the C collation, the plain index already works.[^opclass]

`LIKE '%@yahoo.com'` (12,576 customers): `Seq Scan` with any B-tree. A leading wildcard has no place to start in a sorted list, like looking up every surname ending in "-yan" in a phone book. (Searching inside text needs another index type, the `pg_trgm` extension, beyond this lecture.)

### 7.4 `OR` across different columns

"Nane's orders, or anything delivered on 2025-12-14" (the day her last order arrived). **Demo:** `Seq Scan`, **1,749** rows. `customerID` has an index, `deliveryDate` has none, and a row matching the second half could be anywhere.

- **Fix A:** index `deliveryDate` too → `BitmapOr` of two bitmap index scans.[^bitmap] Median **224 ms → 0.32 ms**.
- **Fix B:** split into two queries joined with **`UNION`**: two index scans, `Append`, duplicates removed. Median **0.60 ms**.

### 7.5 Low selectivity

An index on `status` wouldn't change Part 4.3's verdict. At 92% of the rows, reading the table is right. That one isn't a trap; it's the planner being correct.

### 7.6 An index changes speed, never results. Prove it.

The `OR` query's rows saved before the index (`Seq Scan`) and after it (`BitmapOr`), compared with `EXCEPT` both ways. **Demo numbers:** **1,749** and **1,749** rows, **0** and **0**.

**The "optimization" that changes the answer:** a colleague writes Fix B with `UNION ALL`, "because it skips the duplicate removal". **Demo numbers:** **1,750** rows against 1,749, and `EXCEPT` both ways still says **0 and 0**. Order **4890168** is Nane's *and* was delivered on 2025-12-14, so it is listed twice. `EXCEPT` compares sets, so duplicates vanish before the comparison (Lecture 5, Part 6). **`EXCEPT ALL`** shows the extra row. Summed over this result, that order's revenue would count twice. **Fix:** `UNION` (1,749), and check every rewrite with **matching counts and `EXCEPT ALL` both ways**.

The same proof on ground truth: the small `orders` table with an index on `status` and `enable_seqscan = off`. The plan goes through the index, and completed revenue is **157,078.41**, the number from Lectures 4, 5 and 6.

---

## Part 8 — Callbacks: checking earlier claims with plans

### 8.1 – 8.3 `NOT IN` vs `NOT EXISTS` vs `LEFT JOIN ... IS NULL` (Lecture 5)

**Correctness first, unchanged.** "Salespeople who never had an order cancelled" on the small shop: `NOT IN` → **0 rows** (5 of the cancelled orders have a NULL `employeeID`), `NOT EXISTS` → **Hayk Melikyan**, as in Lecture 5, 2.2.[^notin] That remains the main reason to choose `NOT EXISTS`.

**What the planner makes of them**, on "customers who never cancelled an order" (50,000 customers, 159,902 cancelled orders; `customerID` is `NOT NULL`, so all three agree: **3,751**):

| Written as | Plan | Median |
|---|---|---:|
| `NOT EXISTS (...)` | `Hash Right Anti Join` | 275 ms |
| `LEFT JOIN ... WHERE o.customerID IS NULL` | **the same** `Hash Right Anti Join` | (same plan) |
| `NOT IN (SELECT ...)` | `hashed SubPlan`: the subquery once, its values in a hash table | 272 ms |

The planner rewrote `NOT EXISTS` and the `LEFT JOIN` into one anti-join, so how you write it doesn't matter to it. ("Right" anti-join, PostgreSQL 16+: the hash table is built on the smaller side, the customers.[^v16]) `NOT IN` is never turned into an anti-join; while its list fits in memory, it is about as fast.

**When `NOT IN` falls off a cliff.** "Customers with no order in the second half of 2025": the subquery returns about **970,000** values, too many to hash in `work_mem`. `EXPLAIN` (nothing runs) shows a plain `SubPlan` over a `Materialize`: for **each** of the 50,000 customers, scan the stored list until a match. **Demo numbers:** estimated total cost about **3.3 billion** for `NOT IN` against about **137,000** for `NOT EXISTS`. Measured, `NOT IN` on only the **first 100 customers** took **745 ms** (median); `NOT EXISTS` answered for **all 50,000** in **242 ms**. Its answer, **2,000**, is a checkable fact: exactly the customers who never ordered at all. Everyone who ever ordered also ordered in late 2025. Same data, no NULLs, same answer; only the plan differs. Two reasons now for `NOT EXISTS`: NULLs, and this cliff. (When `NOT IN` gets a hashed subplan depends on the estimated list size and the memory allowed for hashing; this is observed behaviour, not a documented threshold.) **On PostgreSQL 14 the cliff comes sooner:** its hash memory is half of 15's (`hash_mem_multiplier` 1.0 instead of 2.0[^hashmem]), so even the cancelled-orders `NOT IN` above becomes a plain `SubPlan`, and took **163.6 seconds** in our run. On 14, run `SET hash_mem_multiplier = 2.0` first, or skip that cell.

### 8.4 Top-N per group (Lecture 6, Part 4)

"Each customer's latest order" (`ORDER BY orderDate DESC, orderID DESC`), three ways:

| Method | No index | With `(customerID, orderDate DESC, orderID DESC)` |
|---|---|---|
| `row_number()` in a CTE | `Sort` (on disk, 142 MB) → `WindowAgg`; **1,852 ms** | `Index Scan` → `WindowAgg`; **9,463 ms** (5.1× slower) |
| `DISTINCT ON` | `Sort` (on disk) → `Unique`; **2,163 ms** | `Index Scan` → `Unique`; **9,413 ms** (4.4× slower) |
| `JOIN LATERAL ... LIMIT 1` | estimated cost about **6.1 billion**: 50,000 scans of 5 million rows. Not run. | `Nested Loop`, 50,000 short index lookups (`Limit`, `loops=50000`); **147 ms** |

(Medians. `Run Condition` on the `WindowAgg`, PostgreSQL 15+, stops numbering a customer after row 1.[^v15])

**The surprise:** the index that makes `LATERAL` the fastest method by far makes the other two **4–5 times slower**. The planner dropped the sort and walked the whole index instead, in customer order, so it jumped to a different table page for almost every one of 5 million rows. **Demo numbers:** **5,014,716** page visits with the index against **59,739** (plus a sort on disk) without. The planner expected those pages to be cached: `effective_cache_size` defaults to 4 GB and "a higher value makes it more likely index scans will be used",[^config] while PostgreSQL's own cache is 128 MB. This depends on the machine's memory, so measure on yours. What doesn't depend on the machine: "which method is fastest" has no answer without "with which index". The three agree on the answer: `LATERAL` (with the index) and `DISTINCT ON` (saved before it), **48,000** rows each, `EXCEPT` both ways **0** and **0**.

### 8.5 Join methods, in brief

| Method | When the planner picks it | Demo |
|---|---|---|
| Nested Loop | few rows outside, an index inside | 10 orders, a primary-key lookup in `customers_big` for each (`loops=10`) |
| Hash Join | many rows, no useful order | 159,902 cancelled orders by city: hash the 50,000 customers once |
| Merge Join | both sides already sorted on the key | customers (primary key order) against per-customer counts (from the `customerID` index, already in order) |

You don't choose the method; the planner does, from the row estimates (Part 3) and the indexes available. Read which one it picked, and check its estimates.

---

## Part 9 — Partitioning

A partitioned table is **one table to your queries, stored as several physical tables**, each holding the rows for one range or list of values of the **partition key**. Three kinds:[^partitioning]

- `PARTITION BY RANGE (orderDate)`: each partition takes a range (`FROM` inclusive, `TO` exclusive). Used below, one partition per year.
- `PARTITION BY LIST (channel)`: one partition per listed value (Lab 7).
- `PARTITION BY HASH (customerID)`: rows spread evenly over N partitions by a hash of the key.

### 9.1 – 9.2 Build it, and prove it's the same data

`orders_big_part` with the same columns, partitions 2023, 2024 and 2025, filled by `INSERT INTO orders_big_part SELECT * FROM orders_big`. Each row goes to its partition by itself. **Demo numbers:** `tableoid` (the physical table a row lives in) gives **1,371,464 + 1,733,359 + 1,895,177 = 5,000,000**. Month by month, count and revenue from both tables, `EXCEPT` both ways: **36** months, **0** and **0**.

### 9.3 Partition pruning

June 2025, neither table indexed. **Demo:** `orders_big`: `Seq Scan` of **59,739** pages. `orders_big_part`: one node, `Seq Scan on orders_big_part_2025`, **22,643** pages. 2023 and 2024 aren't in the plan at all: the planner proved from the partition bounds that they can't hold June 2025.[^partitioning] Median **182 ms → 79 ms**, same answer.

### 9.4 The trap: a filter that can't prune

`WHERE extract(year FROM orderDate) = 2025` → `Append` over **all three** partitions. The 2023 and 2024 scans return **0 rows** after reading every page. Pruning works from the bounds on `orderDate`, not on an expression of it (Part 7.1 again). **Fix:** `orderDate >= '2025-01-01' AND orderDate < '2026-01-01'` → one partition, median **659 ms → 234 ms**. And a query with no date filter at all, "Nane's orders", reads every partition every time. **Partitioning by date helps only queries that filter on date.**

### 9.5 The trap: a row with no partition

An order dated 2026-01-02 (or a typo, 2205 for 2025). **Demo:** **`ERROR: no partition of relation "orders_big_part" found for row`**. A loud error, the good kind.[^partitioning] The usual "fix", a `DEFAULT` partition ("store rows that don't match any of the other defined partitions"[^v11]), accepts it **silently**: `orders_big_part_default`. Every wrong date will collect there now, without a word. When 2026 comes and you add its partition: **`ERROR: updated partition constraint for default partition "orders_big_part_default" would be violated by some row`**. **Fix:** create partitions *before* their data arrives, and keep the default partition empty (check it daily). The repair: take the row out, create the partition, put the row back.

### 9.6 The trap: unique means unique per partition

`ALTER TABLE orders_big_part ADD PRIMARY KEY (orderID)` → **`ERROR: unique constraint on partitioned table must include all partitioning columns`**. Each partition's index "can only directly enforce uniqueness within their own partitions".[^partitioning] `PRIMARY KEY (orderID, orderDate)` is accepted, and then a second order **5000001**, dated 2025-12-31, goes in next to the one dated 2026-01-02. **Demo numbers:** **5,000,002** rows, **5,000,001** distinct `orderID`s. No error. **Fix:** generate IDs from one sequence (an `IDENTITY` column) so duplicates can't be made, and check `count(*) = count(DISTINCT orderID)`.

### 9.7 Too many tiny partitions

The same 5 million rows, one partition **per day**: **1,096** partitions, created by a `DO` loop. What we measured (medians; one machine, not a law):

| Query | 3 yearly partitions | 1,096 daily partitions |
|---|---|---|
| one day, `orderDate = '2025-06-15'` | 69 ms (reads all of 2025: no index) | **0.62 ms** (one partition, 62 pages) |
| Nane's orders, no date filter: planning | 0.13 ms | **7.60 ms** (about 60×) |
| Nane's orders, no date filter: execution | 133 ms | **228 ms** (1.7×) |

The query that can't prune plans 1,096 scans; its plan is thousands of lines long. The documentation's warning, "Too many partitions can mean longer query planning times and higher memory consumption",[^partitioning] is exactly what we saw. **Here, daily partitions made the one-day query much faster and the query without a date filter slower.** Choose partitions that match how you filter, and keep their number modest.

### 9.8 Deleting old data: `DROP` a partition

"Delete everything from 2023." On `orders_big`, inside `BEGIN ... ROLLBACK` (Part 1.6): a `Delete` over 1,371,464 rows, **1,431,203** page visits, median **609 ms**. A real `DELETE` would also leave dead rows for `VACUUM`. Even rolled back, it left work behind: the touched pages lost their all-visible bit (Part 4.5), so the demo runs `VACUUM orders_big` to put the table back. **`ROLLBACK` undoes the data, not the work.** On the partitioned table: `DROP TABLE orders_big_part_2023`, median **16 ms**, no rows deleted one by one and no `VACUUM`.[^partitioning] **3,628,536** rows left. That convenience, more than speed, is why large time-based tables are partitioned. (`ALTER TABLE ... DETACH PARTITION` keeps the old year as a table of its own, to archive it first.)

### 9.9 The same idea, next lectures

Parquet files and lakehouse tables partition by **folder**, for example `.../orders/year=2025/month=06/part-0.parquet` (an illustration of the common layout). A query engine skips the folders a filter rules out: the same pruning, with the same trap. Filter on the partition column itself, or it reads everything.

---

## Part 10 — The decision rule

### 10.1 The rule

**Always first: read the plan.** Find the slow node, compare its estimated and actual rows (Part 3.5), count its pages. Most slow queries are fixed by an `ANALYZE` or a rewrite (a range instead of a function, the right literal type, `NOT EXISTS`, `UNION`), with no new structure at all.

**Add an index when** a frequent query needs a **small share of a big table** (a customer, a day, a top 10) and the plan shows a `Seq Scan` or a `Filter` where an `Index Cond` could be. Shape it to the query: leftmost column first (6.1), a partial index for a fixed subset (6.2), `INCLUDE` for index-only scans (6.3), an expression index only if you can't rewrite the query (6.4, 7.1). **Remember the bill:** every index costs disk and slows every insert (2.6× for one, 8.5× for five, 5.4), and a covering index can be four times the size of a plain one.

**Don't add an index when** the query reads a large share of the table anyway (4.3: 92% is a `Seq Scan`, correctly), when the table is small (1.1), or when nothing filters on that column the way the index is built (10.2).

**Partition when** the table is **very large and time-based**, most queries filter on the time column, and you need to drop or archive old periods (9.8). It's mostly about **maintenance and pruning**, not a general speed-up: a query that can't prune reads every partition (9.4), many tiny partitions make those queries slower (9.7), and unique keys must include the partition key (9.6). 5 million rows doesn't need it; indexes did everything here faster.

**Do neither when** the query is already fast enough, the table is small, or the real problem is stale statistics (3.3) or a query written so no index can help (Part 7). **After any change:** prove the results are identical (counts, and `EXCEPT ALL` both ways, 7.6) and measure three runs, comparing plans and buffers (1.7).

### 10.2 The index nobody uses

The silent failure nobody looks for: an index that exists, costs space and writes, and is never used. Someone adds an `orderDate` index "for the monthly report"; the report filters with `date_trunc('month', orderDate) = ...` (Part 7.1), so it's a `Seq Scan` every month. **Demo numbers:** November 2025, **159,799** orders; December, **165,962**. `pg_stat_user_indexes` counts every use of every index (`idx_scan`, "number of index scans initiated on this index"[^stats]): **0** uses, **34 MB**. After the report is rewritten as a range: same December numbers, and `idx_scan` is no longer 0. (The counts reach the view up to a second after a statement ends,[^stats] hence the `pg_sleep(1.5)` in the demo.) An index still at 0 after weeks of normal traffic means the queries can't use it (fix them) or nobody needs it (drop it). Never drop the index behind a `PRIMARY KEY` or `UNIQUE` constraint: it enforces a rule even if no query reads it.

---

## Part 11 — Why all of this matters (the one idea to leave the room with)

Look back at today's traps:

| Trap | Looked like | Was |
|---|---|---|
| `EXPLAIN ANALYZE` on a `DELETE` | "just checking the plan" | 27 rows deleted (1.6) |
| One timing | the first run's time | a cold cache: `read=150`, then `hit=150` and faster (1.7) |
| `sum(orderTotal)` | reading one 33 MB column | all 467 MB read: rows are stored whole (2.7) |
| `UPDATE` | the row changed in place | a new version at a new address; the old one stays until `VACUUM` (2.8) |
| `DELETE` of 90% of a table | a table 10 times smaller | the same 128 MB file, every page still scanned, even after `VACUUM` (2.9) |
| Bulk load, no `ANALYZE` | a correct city report | a plan for 476 rows run on 200,000: nested loop, sort on disk, 10× the pages (3.3) |
| "The index isn't used!" | a planner mistake | the right choice: 92% of the rows, forced index no faster (4.3) |
| 3% of the rows | "the index makes this cheap" | 93% of the pages (4.2) |
| `Index Only Scan` | the table isn't read | `Heap Fetches: 5180` until `VACUUM` (4.5) |
| Composite index, second column | `Index Cond` on orderDate | all 13,539 pages of the index read (6.1) |
| Partial index, "same" condition | `status <> 'completed' AND <> 'cancelled'` | `Seq Scan`: the planner can't prove it (6.2) |
| `date_trunc` / `extract` on the column | a normal month filter | `Seq Scan`, estimate 25,000 or 125 for 155,419 (7.1) |
| `customerID = 4242.0` | "Index Only Scan using …customerid_idx" | a `Filter` over 5 million entries (7.2) |
| `LIKE 'nane%'` | an indexed column | `Seq Scan` under `en_US.utf8` (7.3) |
| `OR` across columns | one column indexed | `Seq Scan` (7.4) |
| `UNION ALL` rewrite, checked with `EXCEPT` | 0 and 0, "identical" | 1,750 vs 1,749: one order twice (7.6) |
| `NOT IN` on a large list | same answer as `NOT EXISTS` | longer for 100 customers than `NOT EXISTS` for 50,000 (8.3) |
| "Add an index for top-N" | faster | `LATERAL` 147 ms; `DISTINCT ON` 2.2 s → 9.4 s (8.4) |
| `extract(year ...)` on a partitioned table | a filter on the partition column | all partitions read (9.4) |
| `DEFAULT` partition | "rows can't get lost now" | stray rows collect silently, then block the next partition (9.5) |
| `PRIMARY KEY (orderID, orderDate)` | orderID is unique | two orders 5000001 (9.6) |
| Daily partitions | "more pruning, faster" | about 60× the planning time for queries that can't prune (9.7) |
| `ROLLBACK` | "nothing happened" | 2023's pages lost their all-visible bits (9.8) |
| The report's index | "we indexed it" | `idx_scan = 0` (10.2) |

**Four loud failures:** the non-`IMMUTABLE` index expression, the row with no partition, the default partition blocking a new one, and the primary key without the partition key. Everything else in the table ran without an error, and almost all of it returned the **right answer**. That's what makes performance bugs the quietest of all.

**That's the same point as Lectures 4, 5 and 6:** SQL bugs are silent. The checks for this lecture:

- **Read the plan before and after every change.** Node names, `Index Cond` vs `Filter`, and the pages under each node.
- **Compare estimated and actual rows.** The first 10× gap, from the bottom, is where the plan went wrong.
- **Run `ANALYZE` after bulk loads** and big updates or deletes (and `VACUUM` if you want index-only scans).
- **After a big `DELETE`, check the size, not just the count:** `pg_relation_size` doesn't go down by itself.
- **Prove an optimization didn't change the answer:** matching row counts, and `EXCEPT ALL` both ways = 0. `EXCEPT` alone misses duplicates.
- **Measure three runs, not one,** and compare plans and buffers before milliseconds.
- **Check against ground truth you already have:** 157,078.41; 5,000,000 rows; 2,000 customers with no orders; 1,371,464 + 1,733,359 + 1,895,177.

An AI assistant will happily suggest "add an index on that column" or "rewrite the OR as UNION ALL". Both can be wrong, and only the plan, the counts and `EXCEPT ALL` will tell you. Knowing which number to check is the skill.

---

## Lab (not lectured)

Hands-on tasks on `lecture07`, after the whole demo has run (`orders_big` with its primary key only). For each task: show the plan before and after, and say in one sentence what changed and why. Drop everything you create.

1. **Read a plan.** `SELECT * FROM orders_big WHERE orderID = 4242424`: which node, how many pages, `Index Cond` or `Filter`, estimated vs actual rows?
2. **Find and close an estimate gap.** `count(*) WHERE extract(isodow FROM orderDate) = 7` (Sunday orders). How far off is the estimate, and why? Make it accurate without rewriting the query. (Hint: Part 6.4's last sentence.)
3. **An index for one query.** "Customer 777's 20 latest orders" (`ORDER BY orderDate DESC, orderID DESC LIMIT 20`). Design the index so the plan has no `Sort` node and reads a few dozen pages.
4. **A partial index.** The cancellations desk asks for "cancelled orders over 1,000 since December 2025". Build the smallest index that serves it, and report its size.
5. **Three slow queries.** Fix each without changing its answer, and prove it: (a) `WHERE orderDate + 7 > '2025-12-31'`; (b) `WHERE customerID::numeric = 777`; (c) `WHERE customerID = 777 OR orderDate = '2025-12-31'`, rewritten with `UNION`. Use counts and `EXCEPT ALL` both ways.
6. **Measure write cost.** Insert 500,000 rows into an empty copy of `orders_big` with no index and with three; three runs each inside `BEGIN ... ROLLBACK`. Report medians and the ratio.
7. **LIST partitioning.** Partition a copy of `orders_big` by `channel`. Show that `channel = 'online'` prunes and that an `orderDate` filter doesn't. Prove the partitions add up to 5,000,000.
8. **The unused index.** Create indexes on `rating` and `customerID`, run two customer lookups and the dashboard query `count(*), avg(orderTotal) WHERE coalesce(rating, 0) >= 4`, then use `pg_stat_user_indexes` to find which index was never used and explain why. Rewrite the dashboard's condition without `coalesce`, and prove the answer is unchanged.

---

## Lab solution key (instructor only)

*Verified answers in `steps/lab-key.sql` (annotated with real output, PostgreSQL 18). Not part of the demo or the notebook. Run it after Part 10.*

1. `Index Scan using orders_big_pkey`, `Index Cond: (orderid = 4242424)`, **4 pages** (3 index levels + 1 table page), 1 row estimated, 1 actual.
2. Estimated about **25,000** (the 0.5% default guess), actual **714,670**. An expression index on `extract(isodow FROM orderDate)` + `ANALYZE` gives the expression statistics: the estimate becomes close to the actual count (**733,007** in the key's run).[^createindex] (Without an index, PostgreSQL 14+: `CREATE STATISTICS` on the expression.)
3. `(customerID, orderDate DESC, orderID DESC)`: `Limit` over `Index Scan`, `Index Cond: (customerid = 777)`, no `Sort`, **23 pages** (was a `Seq Scan` of the whole table + top-N sort).
4. `(orderDate) WHERE status = 'cancelled'`: **1,104 kB**. `Index Scan`, `Index Cond` on `orderdate`, `Filter` on `ordertotal`; **1,477** orders.
5. (a) `orderDate > DATE '2025-12-31' - 7`: `Index Only Scan` instead of `Seq Scan`, both **37,549**. (b) `customerID = 777`: `Index Cond` instead of `Filter`. (c) `EXCEPT ALL` both ways: **0** and **0**.
6. One run each on the reference machine: about **352 ms** with no index, **1,459 ms** with three (about 4×). Students' medians will differ; the ratio should be several times.
7. `channel = 'online'` → only `orders_by_channel_online`; `orderDate >= '2025-12-01'` → both partitions. **1,650,020 + 3,349,980 = 5,000,000**.
8. `customerID` index used **2** times, `rating` index **0** (the `coalesce` on the column, Part 7.1). `WHERE rating >= 4` gives the same answer, **800,452** orders averaging **640.55**, because a NULL rating never satisfies `>= 4`, and `coalesce` turned it into 0, which doesn't either. Grading note: `idx_scan` also counts *full* scans of an index. With only `count(*)` in the dashboard query, PostgreSQL answers it by reading the whole `rating` index with a `Filter` (Part 7.2), and the index shows 1 use.

---

## Open questions / TODO

Each item in the brief's list, answered in order, then other things worth knowing.

**From the brief's list**

- **Lecture 4–6 files: found, and the schema and counts match the brief.** 600 orders, 529 completed, completed revenue 157,078.41, 30 customers (28 with orders), 8 employees, 37 products. The setup checks all of them. **The two build prompts the brief names, `lecture-05-build-prompt.md` and `lecture-06-build-prompt.md`, are not in the repository** (Lecture 6's notes already reported the Lecture 5 one missing). I followed the Lecture 5 and 6 deliverables themselves, and Lecture 6's `build/` tooling. **The brief's folder `lecture-07/`** is `lectures/lecture_7/` here, matching `lecture_2` … `lecture_6`.
- **`orders_big` was built at the target size:** 5,000,000 rows, 467 MB (table) + 107 MB (primary key), about 42 s on the reference machine. Nothing was reduced. I also added **`customers_big`** (50,000 rows, same columns as `customers`), which the brief didn't ask for: Parts 6.4 and 7.3 need a text column with an index (`email`), and Part 8's `NOT IN` and `LATERAL` comparisons need a customer table at scale. **Same data on every machine holds for PostgreSQL 15 and later only**: 15 changed `random()`, so the same seed gives different rows on 14.
- **The brief's premise for Part 1.1 is half true.** "PostgreSQL correctly chooses a sequential scan on a tiny table": for `customerID = 5` (5 of 600 rows) PostgreSQL 18 *does* use an index on `orders` (a bitmap scan). What's true is that it doesn't matter: both plans take hundredths of a millisecond. 1.1 says that instead.
- **Traps that did not reproduce as first planned, and what I did:**
  - *Part 4, index-only scans after an `UPDATE`:* my first version updated 328 rows of one day and ran `VACUUM`. `Heap Fetches` stayed at 5,167, because `VACUUM` (PostgreSQL 14+, `INDEX_CLEANUP AUTO`) skips index cleanup when very few pages have dead rows,[^vacuum] and those pages can't be marked all-visible. Real, but too deep for this audience. 4.5 uses a freshly built table (`CREATE TABLE ... AS`) instead, where `VACUUM` behaves as expected. Worth knowing if a student tries the `UPDATE` version.
  - *Part 10, "an index nobody uses":* my first version indexed `employeeID` (an eighth of in-store orders, 8% of the table) and `channel` (33%). The planner **used both** (bitmap scans). An index that is genuinely never used needs a query that *can't* use it, so 10.2 indexes `orderDate` for a report that filters with `date_trunc` (Part 7.1's trap). That is more realistic anyway.
  - *Part 5.4, write cost:* the brief says "a bulk insert into `orders_big` with 0, 1 and 5 indexes". `orders_big` always has its primary key, and repeated rolled-back inserts into it leave dead rows and grow the table between runs. I load the same 1,000,000 rows into an empty copy (`orders_load`, `LIKE orders_big`), `TRUNCATE` between runs, so "0 indexes" really is 0.
- **The surprise in Part 8.4 is reported as measured, and it depends on memory.** With the `(customerID, orderDate DESC, orderID DESC)` index, `DISTINCT ON` and `row_number()` got about 5× slower (5.0 million page visits instead of 60,000). The planner trusts `effective_cache_size` (4 GB), but `shared_buffers` is 128 MB and this laptop had about 3 GB free. On a server with a large cache the index plan may win. The notes say so, and give buffer counts, which don't depend on the machine.
- **Pinned settings:** `max_parallel_workers_per_gather = 0` and `jit = off`, set on the `lecture07` database by the setup script (so the notebook gets them too). Everything else is default. Autovacuum is off for `orders_big` only. Within one PostgreSQL version, plans were identical on every run except one in Part 7.3, now fixed (see "One unstable plan" below); estimated row counts move a little after each `ANALYZE` (random sample), so comments say "about" for estimates.
- **Plan differences between versions:** checked with `build/crosscheck.py`, which reruns every statement of every Part and of the lab key on a freshly set-up database and compares plan shapes and result tables with `steps/`.
  - **PostgreSQL 16 (16.15):** same data, same results and same plan shapes as 18 for every statement, except: the sampled statistics and estimates (as between any two runs); in 8.4 an extra `Result` node above `Unique` in the indexed `DISTINCT ON` plan; and `EXPLAIN ANALYZE` prints `Buffers` only when asked (1.3; every later `EXPLAIN` in the lecture asks).
  - **PostgreSQL 14 (14.24):** different generated data (the `random()` change), so counts, sizes and sums differ slightly. Plan shapes match 18 everywhere except Part 8: anti-joins appear as `Hash Anti Join` or `Merge Anti Join` (the "Right" variant arrived in 16[^v16]); no `Run Condition` (15+); the same extra `Result` node; and **8.2's `NOT IN` on the cancelled orders already falls off the cliff**: a plain `SubPlan` over a `Materialize`, **163.6 s** in one run instead of about 0.27 s. PostgreSQL 14's `hash_mem_multiplier` default is 1.0; 15 raised it to 2.0.[^hashmem] With `SET hash_mem_multiplier = 2.0`, PostgreSQL 14 chooses the hashed subplan too (checked with `EXPLAIN`). Part 8.3 tells students on 14 to set it or skip that cell.
  - **One unstable plan, found and fixed.** After Part 2 was added, the whole lecture was run on five fresh PostgreSQL 18 builds: three `crosscheck.py` runs and the notebook verifications. Part 7.3's `LIKE 'nane.simonyan%'` on the pattern index came out as a `Bitmap Heap Scan` instead of the reference `Index Scan` in some of them.
    - **Cause:** depending on the `ANALYZE` sample, the estimate for that prefix was either 5 or 505 rows (64 real). Over 30 samples the plan flipped 4 times, and `'nane.simonyan4%'` still flipped 4 times in 100.
    - **Fix:** 7.3 now searches for Nane's own prefix, `'nane.simonyan4242%'`, which was an `Index Scan` in 100 samples out of 100. The lesson (`Seq Scan` without the pattern index, `Index Cond` with it) is unchanged.
    - **Everything else:** every other plan matched in every run. Nothing beyond Part 0's two settings had to be pinned.
  - PostgreSQL 19 was not tested (no image on this machine).
- **Every performance claim is backed by plan output or `build/measurements-pg18.md`.** The one statement that rests on observation alone, not on documentation, is when `NOT IN` gets a hashed subplan (it depends on estimated size vs `work_mem`); the notes say so. Single-run times in the demo's pasted output differ from the medians (mostly cold first runs); the notes quote medians only.
- **Notebook: connects and runs; `EXPLAIN` is shown as text, not as a `mo.sql` table.** A `mo.sql` cell renders a plan as a one-column table with cut-off lines, which is unreadable. Plan cells are Python cells calling `show_plan(...)`, which prints the plan in a code block and compares its shape (node names, `Index Cond` / `Filter` labels, by depth) with the reference run: green if it matches, yellow with both shapes if not. Statements that return no table (`CREATE INDEX`, `SET`, `VACUUM`, `INSERT` …) are `run_sql(...)` cells showing the command tag; `BEGIN … ROLLBACK` groups are one cell using psycopg's `transaction(force_rollback=True)`. These are the departures from Lecture 6's "markdown + `mo.sql`" pairs; result tables are still `mo.sql` cells. The notebook changes the database as it runs, so it must run top to bottom (marimo's default order, since every cell depends only on the connection). Prose never states milliseconds: ratios are labelled "on the reference machine", and plan shape is asserted instead. **Verified:** `build/verify_notebook.py` ran the whole notebook with `app.run()` on a freshly set-up PostgreSQL 18 database. After Part 2 was added: all 51 comparable result cells match the demo's output, all 88 plan cells match the reference shape, and all 5 error cells raise. **Trimmed on 2026-11-13** ("too big and too crowded"): the notebook now keeps the core sections only, 279 cells instead of 495. Left out: 1.1, 1.3, 1.7, 2.2, 2.4, 2.6, 2.7, 3.1, 3.2, 4.5, 5.4, 5.6, 5.7, 6.2–6.4, 7.3–7.6, 8.1–8.4, 9.5–9.7. They are in the demo and these notes, and `NOTEBOOK_SKIP` in `build/build_notebook.py` lists them (delete a line to bring one back). Where a left-out section creates or drops something later sections need (the index clean-ups of 4.5, 5.7 and 7.6, `pageinspect` in 2.4), the notebook runs just those statements in one small hidden-code cell that says so. Re-verified on a fresh PostgreSQL 18 database: 27 result cells match, 39 of 39 plans match, and the 1 error cell raises. Fifteen cells were skipped: the 3 setup checks; 8 Part 2 cells whose output is machine- or run-specific (file paths, file names, transaction numbers); the 3 `pg_stats`/`pg_class` cells (sampled, they change on every `ANALYZE`); and the last `pg_stat_user_indexes` listing (it counts everything run before). Two fixes came out of it. A `LIKE '…%'` in a `mo.sql` cell fails, because marimo passes parameters and psycopg reads `%` as a placeholder, so 2.1 uses `starts_with()`. And the verifier now compares bytes the way psql prints them. `marimo check` passes and `marimo export html` runs every cell without an error. Every notebook SQL text is copied from the demo by `build/build_notebook.py`, which fails if one isn't. It hasn't been clicked through in `marimo edit`; do that once before class. On PostgreSQL 16 or 14, expect yellow boxes on the plans listed under "Plan differences between versions" above.
- **Scope: too long for one session. Proposed split after Part 5.** With Part 2, the demo has 327 statements (35 of them setup) against Lecture 6's 139, and about 4 minutes of pure run time.
  - **Session A, Parts 1–5 (135 statements):** reading plans, storage, statistics, scan types, and B-trees with their cost. This is "how PostgreSQL reads data, and the basic index".
  - **Session B, Parts 6–11 (157 statements):** index kinds, the traps, the callbacks, partitioning, the decision rule and the synthesis.
  - **The old proposal** (split after what is now Part 6) would give 161 / 131. Part 2's 43 statements tipped the balance.
  - **Cheapest cuts, if it must be one session:** 2.6 and the `VACUUM` half of 2.8, 5.6–5.7, 6.4, 8.5 (join methods) and 9.7 (daily partitions; set it as homework with its table of numbers).

  Nothing has been cut.
- **Part 2 (how a table is stored on disk) was added after the first build, on request.** It sits after Part 1 because the later Parts use what it shows: Part 1.4 counts pages, Part 4 depends on which pages rows sit on, Part 4.5 on the visibility map, Parts 5–7 on index entries pointing to row addresses, and Part 9.8 on dead rows. The old Parts 2–10 became 3–11 everywhere: notes, Q&A, templates, setup comments, lab key, and measurement labels. A script changed only "Part N" and section references, skipped references to other lectures ("Lecture 5, 2.2"), and every change was reviewed.
  - **Unchanged by the insertion:** a statement-by-statement comparison with the previous build found every plan shape and result table in Parts 3–10 and the lab key the same. The only differences were the four outputs that change on every run anyway: the sampled statistics and an index-usage counter.
  - **Sample-dependent "demo run" values resynced:** the rebuild drew a new `ANALYZE` sample, so 1.2's `rows=106`, 3.1's 5,000,083 and 47,231, 3.2's 166,003, 3.3's 476 and the lab key's 733,007 now match the new run.
  - **Requirements:** a superuser, which our Docker `postgres` user is, and PostgreSQL 13+ for 2.6 (the `htid` column). Tested as an ordinary user on PostgreSQL 16:
    - **Fail:** 2.1's `data_directory` and `pg_ls_dir` queries ("permission denied"), and every `pageinspect` query (2.4, 2.5's byte view, 2.6, the page views in 2.8: "must be superuser to use raw page functions"). Creating the extension needs a superuser too.
    - **Run:** `pg_relation_filepath`, 2.2, all of 2.3, 2.7, the `ctid` / `xmin` queries in 2.8, and all of 2.9.
    - **On a managed cloud database**, students get only the second list.
  - **Output that differs per machine:** file paths and names (2.1, 2.9) and transaction numbers (2.8). The verifier skips those cells, and the comments say so.
  - **PostgreSQL 16 (16.15):** every other Part 2 output is identical to 18: file sizes, pages, every `ctid`, the page header and slots, the raw bytes and the index entries. The one difference is 2.9's `CREATE TABLE AS` copy, which is **16,448 pages (129 MB) on 16** against 16,390 (128 MB) on 18. Every later step in 2.9 behaves the same on both, and `VACUUM FULL` gives 6,530 pages on both. Not tested on 14 this time (its data differs anyway).
  - **The terminal commands** in 2.1 and 2.5 (`docker exec pg ls`, `od`) are in comments and the notes, not in the SQL. They were run once on the reference container, and `od` showed the bytes the notes quote.
  - **Not in the lab.** The lab is already at the brief's maximum of eight tasks. A natural swap for Task 1 would be "find the page and slot of order 4242424, read its bytes with `heap_page_item_attrs`, and decode `orderDate`".
- **Voice and structure: matched, with three additions.** (1) Part 0 has a table of how each generated column is built. (2) Part 4 and Part 9 open with reference tables (scan types; partition kinds), as Lecture 6's Parts 3 and 6 did. (3) The lab and its solution key are new; the key is verified like the demo, in `steps/lab-key.sql`, and kept out of the demo and the notebook.

**Also worth knowing**

- **How to change a query:** edit `build/src/NN-*.sql`, never `steps/`. From `lecture_7/`: `psql postgres` + `\i steps/00-setup.sql`, then `PGP=<port> build/build_demo.sh`: it regenerates `steps/01-10`, `steps/lab-key.sql`, the demo and the notebook. `build/verify_notebook.py` reruns the notebook on a freshly set-up database and compares it with the demo; `build/measure.py` regenerates the medians (about 4 minutes); `build/crosscheck.py OUTDIR` compares another PostgreSQL version's output with `steps/`. If you edit the notebook in marimo, a rebuild overwrites it.
- **Two notebooks since 2026-11-13.**
  - **`lecture-07-notebook.py` is Alber's working notebook, edited by hand from 2026-11-13.**
    - **Nothing regenerates it.** No script in `build/` writes it.
    - **Statements are plain SQL cells,** one statement per cell. Plans use `show_plan`, for readable plan text and a check of the plan's shape against the demo.
    - **No functions are defined in the notebook.** They live in `notebook_tools/`: `plans.py` (`show_plan`) and `diagrams.py` (the 11 diagrams, drawn as PNGs into `diagrams/` by one of the notebook's first cells; each diagram cell is `mo.image(DIAGRAMS["…"])`). The PNGs are drawn with `cairosvg` if it's installed, otherwise with headless Chrome (about 9 s the first time), and only changed diagrams are redrawn.
  - **History:** It was first a light version (on request: "keep all diagrams and theoretical content, but less code"). That version held the full text of these notes, all 15 diagrams and 126 cells. `python build/build_notebook.py` builds the current one from `build/light.py`.
  - **`lecture-07-notebook.py.bak` is the detailed step-by-step version** (279 cells, the core sections of the demo). `python build/build_notebook.py --detailed` regenerates it.
  - **Rewritten for students on 2026-11-13** ("they are data analysts, I don't want to go this deep"). The notebook no longer pastes these notes: its text is in `build/light.py`, plain language, one idea, one demo and one trap per Part. It shows 11 diagrams, three of them simplified for students (storage without bytes, `UPDATE` without transaction numbers, statistics in plain words). It runs 16 plans and 7 queries: 95 cells.
  - **Verified on a fresh PostgreSQL 18 database:** all 16 plans match the reference shape, and the 5 comparable result cells match the demo.
  - **One run-dependent number:** in 2.9 the copy of 2023 had **16,388** pages when the student notebook built it, against 16,390 in the demo and the detailed notebook. It's 128 MB either way, and the lesson is unchanged. Synchronized scans were tested and ruled out; the cause is not pinned down. The student text gives the size only, and the verifier skips those two cells.
- **Theory slides in the notebook (added 2026-11-12, on request).**
  - **What they are:** 15 slides, of which the notebook shows 10 since the trim (`IN_NOTEBOOK` in `slides.py`; left out: the query path, the cache, row vs column store, the four scan types, the join methods). Each is a dark 16:9 SVG in Lecture 4's deck style, with a source footer: the query path, a plan as a tree, where pages come from, table → file → page → row, row vs column store, `UPDATE` versions, where estimates come from, the four scan types, a chart of pages read vs share of rows, the B-tree, the composite index as a phone book, a function hiding the column, the three join methods, partition pruning, and the decision flowchart.
  - **Where they come from:** `build/slides.py`. `build_notebook.py` puts each one in a hidden-code cell right before the heading it's anchored to, and fails if an anchor isn't found exactly once.
  - **Numbers:** they come from the demo output. A few come from queries run for the slides on a fresh PostgreSQL 18 setup: `ANALYZE VERBOSE` ("30000 rows in sample"), `bt_metap` (the primary key is 3 levels with 48 root entries, 13,712 pages), and `orderID = 4890168` reading 4 pages.
  - **The chart's colours** are the dataviz reference palette's dark steps, validated against the slide background; the points have hover tooltips.
  - **To change a slide:** edit `slides.py`, then run `python build/build_notebook.py`. `python build/slides.py OUTDIR` writes one HTML file per slide for a browser or screenshots.
  - **Fonts** load from Google Fonts; offline, they fall back to DejaVu and the layout holds.
  - **They are not in the demo, the notes or a separate deck.**
- **The yearly partitions are deliberately unequal:** 1.37M, 1.73M, 1.90M orders, from the `^ 0.85` in the date formula, a shop that grows a little each year.
- **`orders_big`'s primary key is 111 MB after Part 3, not 107 MB**: the January insert and delete grow it, and B-tree pages aren't returned. Part 5.3's comment says so.
- **Disk:** the setup needs about 1 GB; Part 9 briefly holds `orders_big_part` and the 1,096-partition copy (about 1 GB more) and drops both.

[^demo]: `lecture-07-demo.sql` (also split per Part in `steps/`), generated by `build/build_demo.sh`: every statement was run against a freshly set-up `lecture07` database on PostgreSQL 18.6 (Docker `postgres:18`, Intel i7-13700H laptop, NVMe disk, settings as in Part 0), and psql's real output pasted under it. Cross-checked on 14 and 16; see TODO.
[^measure]: `build/measure.py` → `build/measurements-pg18.md`: each query run three times in a row as `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`, median of the three `Execution Time`s. Single-run times in the demo's pasted output differ from these medians, mostly on first (cold) runs.
[^random]: PostgreSQL 15 release notes, Migration: "Improve the algorithm used to compute random() (Fabien Coelho) … This will cause random()'s results to differ from what was emitted by prior versions, even for the same seed value." https://www.postgresql.org/docs/release/15.0/ — Checked: `setseed(0.42)` then four `random()` calls give identical values on 16 and 18 and different ones on 14.
[^eol]: PostgreSQL Versioning Policy, Releases table: "14 | 14.24 | Yes | September 30, 2021 | November 12, 2026". https://www.postgresql.org/support/versioning/
[^config]: PostgreSQL 18 documentation, Query Planning (runtime-config-query): `effective_cache_size` "Sets the planner's assumption about the effective size of the disk cache that is available to a single query. … a higher value makes it more likely index scans will be used … The default is 4 gigabytes (4GB)." `random_page_cost` "The default is 4.0." `enable_seqscan`: "It is impossible to suppress sequential scans entirely, but turning this variable off discourages the planner from using one if there are other methods available." `jit_above_cost`: "The default is 100000." https://www.postgresql.org/docs/18/runtime-config-query.html
[^explain]: PostgreSQL 18 documentation, EXPLAIN: "Keep in mind that the statement is actually executed when the ANALYZE option is used. Although EXPLAIN will discard any output that a SELECT would return, other side effects of the statement will happen as usual. If you wish to use EXPLAIN ANALYZE on an INSERT, UPDATE, DELETE, MERGE, CREATE TABLE AS, or EXECUTE statement without letting the command affect your data, use this approach: BEGIN; EXPLAIN ANALYZE ...; ROLLBACK;" and, under BUFFERS: "Buffers information is automatically included when ANALYZE is used." https://www.postgresql.org/docs/18/sql-explain.html
[^using]: PostgreSQL 18 documentation, Using EXPLAIN: "The costs are measured in arbitrary units determined by the planner's cost parameters … Traditional practice is to measure the costs in units of disk page fetches; that is, seq_page_cost is conventionally set to 1.0." … "It's important to understand that the cost of an upper-level node includes the cost of all its child nodes." … "Note that the 'actual time' values are in milliseconds of real time, whereas the cost estimates are expressed in arbitrary units; so they are unlikely to match up." https://www.postgresql.org/docs/18/using-explain.html
[^ring]: PostgreSQL source, `src/backend/access/heap/heapam.c`, `initscan()`: "If the table is large relative to NBuffers, use a bulk-read access strategy" when `scan->rs_nblocks > NBuffers / 4`; and `src/backend/storage/buffer/README`, "Buffer Ring Replacement Strategy": "For sequential scans, a 256KB ring is used." https://github.com/postgres/postgres/blob/REL_18_STABLE/src/backend/storage/buffer/README
[^analyze]: PostgreSQL 18 documentation, ANALYZE: "For large tables, ANALYZE takes a random sample of the table contents, rather than examining every row. … Note, however, that the statistics are only approximate, and will change slightly each time ANALYZE is run, even if the actual table contents did not change. This might result in small changes in the planner's estimated costs shown by EXPLAIN." https://www.postgresql.org/docs/18/sql-analyze.html
[^pgstats]: PostgreSQL 18 documentation, pg_stats: n_distinct "If less than zero, the negative of the number of distinct values divided by the number of rows … -1 indicates a unique column"; correlation "Statistical correlation between physical row ordering and logical ordering of the column values. … When the value is near -1 or +1, an index scan on the column will be estimated to be cheaper than when it is near zero, due to reduction of random access to the disk." https://www.postgresql.org/docs/18/view-pg-stats.html
[^populate]: PostgreSQL 18 documentation, §14.4.8 Run ANALYZE Afterwards: "Whenever you have significantly altered the distribution of data within a table, running ANALYZE is strongly recommended. This includes bulk loading large amounts of data into the table. … With no statistics or obsolete statistics, the planner might make poor decisions during query planning". https://www.postgresql.org/docs/18/populate.html
[^ios]: PostgreSQL 18 documentation, Index-Only Scans and Covering Indexes: "If it's not set, the heap entry must be visited to find out whether it's visible, so no performance advantage is gained over a standard index scan." … "As payload columns, they are never used to guide index scans." https://www.postgresql.org/docs/18/indexes-index-only-scans.html
[^btree]: PostgreSQL 18 documentation, B-Tree Indexes, Deduplication: "Deduplication works by periodically merging groups of duplicate tuples together, forming a single posting list tuple for each group. The column key value(s) only appear once in this representation." … "INCLUDE indexes can never use deduplication." https://www.postgresql.org/docs/18/btree.html
[^multicol]: PostgreSQL 18 documentation, Multicolumn Indexes: "the index is most efficient when there are constraints on the leading (leftmost) columns. … Constraints on columns to the right of these columns are checked in the index, so they'll always save visits to the table proper, but they do not necessarily reduce the portion of the index that has to be scanned." … skip scan "is generally only taken when there are so few distinct x values that the planner expects the scan to skip over most of the index … If there are many distinct x values, then the entire index will have to be scanned". https://www.postgresql.org/docs/18/indexes-multicolumn.html
[^partial]: PostgreSQL 18 documentation, Partial Indexes: "a partial index can be used in a query only if the system can recognize that the WHERE condition of the query mathematically implies the predicate of the index. PostgreSQL does not have a sophisticated theorem prover that can recognize mathematically equivalent expressions that are written in different forms. … The system can recognize simple inequality implications, for example 'x < 1' implies 'x < 2'; otherwise the predicate condition must exactly match part of the query's WHERE condition or the index will not be recognized as usable." https://www.postgresql.org/docs/18/indexes-partial.html
[^expr]: PostgreSQL 18 documentation, Indexes on Expressions: "This query can use an index if one has been defined on the result of the lower(col1) function" … "Index expressions are relatively expensive to maintain, because the derived expression(s) must be computed for each row insertion and non-HOT update." https://www.postgresql.org/docs/18/indexes-expressional.html
[^createindex]: PostgreSQL 18 documentation, CREATE INDEX: "All functions and operators used in an index definition must be 'immutable', that is, their results must depend only on their arguments and never on any outside influence" … "For new expression indexes, it is necessary to run ANALYZE or wait for the autovacuum daemon to analyze the table to generate statistics for these indexes." https://www.postgresql.org/docs/18/sql-createindex.html
[^selfuncs]: PostgreSQL source, `src/include/utils/selfuncs.h`: "/* default selectivity estimate for equalities such as "A = b" */ #define DEFAULT_EQ_SEL 0.005". https://github.com/postgres/postgres/blob/REL_18_STABLE/src/include/utils/selfuncs.h — 0.005 × 5,000,000 = 25,000; 0.005 × 0.005 × 5,000,000 = 125, the two estimates in 7.1.
[^opclass]: PostgreSQL 18 documentation, Operator Classes and Operator Families: "the values are compared strictly character by character rather than according to the locale-specific collation rules. This makes these operator classes suitable for use by queries involving pattern matching expressions (LIKE or POSIX regular expressions) when the database does not use the standard 'C' locale. … If you do use the C locale, you do not need the xxx_pattern_ops operator classes". https://www.postgresql.org/docs/18/indexes-opclass.html
[^bitmap]: PostgreSQL 18 documentation, §11.5 Combining Multiple Indexes: "The system can form AND and OR conditions across several index scans. … To combine multiple indexes, the system scans each needed index and prepares a bitmap in memory giving the locations of table rows that are reported as matching that index's conditions. The bitmaps are then ANDed and ORed together as needed by the query." https://www.postgresql.org/docs/18/indexes-bitmap-scans.html
[^notin]: PostgreSQL 18 documentation, Subquery Expressions, NOT IN: "if there are no equal right-hand values and at least one right-hand row yields null, the result of the NOT IN construct will be null, not true." https://www.postgresql.org/docs/18/functions-subquery.html (as in Lecture 5).
[^v16]: PostgreSQL 16 release notes: "Allow anti-joins to be performed with the non-nullable input as the inner relation (Richard Guo)". https://www.postgresql.org/docs/release/16.0/
[^v15]: PostgreSQL 15 release notes: "Improve the performance of window functions that use row_number(), rank(), dense_rank() and count() (David Rowley)". https://www.postgresql.org/docs/release/15.0/ — the plan line itself is `Run Condition: (row_number() OVER w1 <= 1)`.
[^partitioning]: PostgreSQL 18 documentation, Table Partitioning: "Inserting data into the parent table that does not map to one of the existing partitions will cause an error; an appropriate partition must be added manually." … "To create a unique or primary key constraint on a partitioned table … the constraint's columns must include all of the partition key columns. This limitation exists because the individual indexes making up the constraint can only directly enforce uniqueness within their own partitions". … pruning: "the planner will examine the definition of each partition and prove that the partition need not be scanned because it could not contain any rows meeting the query's WHERE clause." … "Dropping an individual partition using DROP TABLE, or doing ALTER TABLE DETACH PARTITION, is far faster than a bulk operation. These commands also entirely avoid the VACUUM overhead caused by a bulk DELETE." … "Too many partitions can mean longer query planning times and higher memory consumption during both query planning and execution". https://www.postgresql.org/docs/18/ddl-partitioning.html
[^stats]: PostgreSQL 18 documentation, The Cumulative Statistics System: `idx_scan` "Number of index scans initiated on this index"; "Each individual server process flushes out accumulated statistics to shared memory just before going idle, but not more frequently than once per PGSTAT_MIN_INTERVAL milliseconds (1 second unless altered while building the server)". https://www.postgresql.org/docs/18/monitoring-stats.html
[^vacuum]: PostgreSQL 18 documentation, VACUUM, INDEX_CLEANUP: "Normally, VACUUM will skip index vacuuming when there are very few dead tuples in the table. … The default is AUTO, which allows VACUUM to skip index vacuuming when appropriate." … "the table itself will accumulate dead line pointers that cannot be removed until index cleanup is completed." https://www.postgresql.org/docs/18/sql-vacuum.html — what we saw: `index scan bypassed: 62 pages from table (0.10% of total) have 328 dead item identifiers` in `VACUUM (VERBOSE)`.
[^hashmem]: PostgreSQL 15 release notes: "Increase hash_mem_multiplier default to 2.0 (Peter Geoghegan) — This allows query hash operations to use more work_mem memory than other operations." https://www.postgresql.org/docs/release/15.0/ ; PostgreSQL 18 documentation, Resource Consumption: "The final limit is determined by multiplying work_mem by hash_mem_multiplier. The default value is 2.0". https://www.postgresql.org/docs/18/runtime-config-resource.html
[^v10]: PostgreSQL 10 release notes: "Add table partitioning syntax that automatically creates partition constraints and handles routing of tuple insertions and updates (Amit Langote) — The syntax supports range and list partitioning." https://www.postgresql.org/docs/release/10.0/
[^v11]: PostgreSQL 11 release notes: "Allow B-tree indexes to include columns that are not part of the search key … This is enabled by the new INCLUDE clause of CREATE INDEX"; "Allow partitioned tables to have a default partition … The default partition will store rows that don't match any of the other defined partitions"; "If the partition key is part of the index's column set, a partitioned index may be declared UNIQUE"; "Allow partition elimination during query execution"; "Allow the creation of partitions based on hashing a key column". https://www.postgresql.org/docs/release/11.0/
[^v13]: PostgreSQL 13 release notes: "More efficiently store duplicates in B-tree indexes … This allows efficient B-tree indexing of low-cardinality columns by storing duplicate keys only once." https://www.postgresql.org/docs/release/13.0/
[^v18]: PostgreSQL 18 release notes: "Automatically include BUFFERS output in EXPLAIN ANALYZE"; "In EXPLAIN ANALYZE, report the number of index lookups used per index scan node"; "Modify EXPLAIN to output fractional row counts"; "Allow skip scans of btree indexes". https://www.postgresql.org/docs/release/18.0/
[^adminfn]: PostgreSQL 18 documentation, System Administration Functions: `pg_ls_dir` "Returns the names of all files (and directories and other special files) in the specified directory. … This function is restricted to superusers by default, but other users can be granted EXECUTE to run the function." (the same for `pg_stat_file`); `pg_relation_filepath` "Returns the entire file path name (relative to the database cluster's data directory, PGDATA) of the relation." https://www.postgresql.org/docs/18/functions-admin.html
[^pageinspect]: PostgreSQL 18 documentation, pageinspect: "The pageinspect module provides functions that allow you to inspect the contents of database pages at a low level, which is useful for debugging purposes. All of these functions may be used only by superusers." … "`heap_page_items` shows all line pointers on a heap page. For those line pointers that are in use, tuple headers as well as tuple raw data are also shown. All tuples are shown, whether or not the tuples were visible to an MVCC snapshot at the time the raw page was copied." … "`htid` shows a heap TID for the tuple". https://www.postgresql.org/docs/18/pageinspect.html
[^filelayout]: PostgreSQL 18 documentation, Database File Layout: "For each database in the cluster there is a subdirectory within PGDATA/base, named after the database's OID in pg_database." … "Each table and index is stored in a separate file. For ordinary relations, these files are named after the table or index's filenode number" … "each table and index has a free space map … stored in a file named with the filenode number plus the suffix _fsm. Tables also have a visibility map, stored in a fork with the suffix _vm" … "When a table or index exceeds 1 GB, it is divided into gigabyte-sized segments. The first segment's file name is the same as the filenode; subsequent segments are named filenode.1, filenode.2, etc." https://www.postgresql.org/docs/18/storage-file-layout.html
[^pagelayout]: PostgreSQL 18 documentation, Database Page Layout: "Every table and index is stored as an array of pages of a fixed size (usually 8 kB …)." Table 66.2: PageHeaderData "24 bytes long"; ItemIdData "Array of item identifiers pointing to the actual items. Each entry is an (offset,length) pair. 4 bytes per item."; Free space "New item identifiers are allocated from the start of this area, new items from the end." Table 66.3: pd_lower "Offset to start of free space", pd_upper "Offset to end of free space". "There is a fixed-size header (occupying 23 bytes on most machines), followed by an optional null bitmap" (t_xmin "insert XID stamp", t_xmax "delete XID stamp"); "In this list of bits, a 1 bit indicates not-null, a 0 bit is a null." … "every pointer to an item (ItemPointer, also known as CTID) created by PostgreSQL consists of a page number and the index of an item identifier." https://www.postgresql.org/docs/18/storage-page-layout.html
[^syscols]: PostgreSQL 18 documentation, System Columns: ctid "The physical location of the row version within its table. Note that although the ctid can be used to locate the row version very quickly, a row's ctid will change if it is updated or moved by VACUUM FULL. Therefore ctid should not be used as a row identifier. A primary key should be used to identify logical rows."; xmin "The identity (transaction ID) of the inserting transaction for this row version."; xmax "The identity (transaction ID) of the deleting transaction, or zero for an undeleted row version." https://www.postgresql.org/docs/18/ddl-system-columns.html
[^epoch]: PostgreSQL source, `src/include/datatype/timestamp.h`: `#define POSTGRES_EPOCH_JDATE 2451545 /* == date2j(2000, 1, 1) */`, the day dates are counted from. https://github.com/postgres/postgres/blob/REL_18_STABLE/src/include/datatype/timestamp.h — the demo checks it: `DATE '2000-01-01' + 8401` = 2023-01-01.
[^nbtree]: PostgreSQL source, `src/include/access/nbtree.h`: "Lehman and Yao's algorithm requires a ``high key'' on every non-rightmost page. The high key is not a tuple that is used to visit the heap." https://github.com/postgres/postgres/blob/REL_18_STABLE/src/include/access/nbtree.h
[^routine]: PostgreSQL 18 documentation, Routine Vacuuming: "In PostgreSQL, an UPDATE or DELETE of a row does not immediately remove the old version of the row." … "The standard form of VACUUM removes dead row versions in tables and indexes and marks the space available for future reuse. However, it will not return the space to the operating system, except in the special case where one or more pages at the end of a table become entirely free and an exclusive table lock can be easily obtained." https://www.postgresql.org/docs/18/routine-vacuuming.html
[^hot]: PostgreSQL source, `src/backend/access/heap/README.HOT`: "Redirecting line pointer: A line pointer that points to another line pointer and has no associated tuple. It has the special lp_flags state LP_REDIRECT, and lp_off is the OffsetNumber of the line pointer it links to." … "its line pointer cannot [be reclaimed], since the index still links to that line pointer". https://github.com/postgres/postgres/blob/REL_18_STABLE/src/backend/access/heap/README.HOT
[^itemid]: PostgreSQL source, `src/include/storage/itemid.h`: `LP_UNUSED 0 /* unused (should always have lp_len=0) */`, `LP_NORMAL 1`, `LP_REDIRECT 2 /* HOT redirect */`, `LP_DEAD 3`, the codes behind the demo's "free / row / points to slot". https://github.com/postgres/postgres/blob/REL_18_STABLE/src/include/storage/itemid.h
[^vacuumcmd]: PostgreSQL 18 documentation, VACUUM: "Plain VACUUM (without FULL) simply reclaims space and makes it available for re-use. … However, extra space is not returned to the operating system (in most cases); it's just kept available for re-use within the same table. … VACUUM FULL rewrites the entire contents of the table into a new disk file with no extra space, allowing unused space to be returned to the operating system. This form is much slower and requires an ACCESS EXCLUSIVE lock on each table while it is being processed." FULL: "This method also requires extra disk space, since it writes a new copy of the table and doesn't release the old copy until the operation is complete." https://www.postgresql.org/docs/18/sql-vacuum.html
