# Lecture 8 — Files and Engines: Parquet, DuckDB, Python: Class Notes

*Scope: row vs column storage, Parquet vs CSV (size, types, speed), how a database server works (PostgreSQL: clients, processes, the data directory) and DuckDB as a database in one file, when to use which, querying and writing files with DuckDB (one file, many files, folders), Python and PostgreSQL (psycopg, parameters, pandas, polars), DuckDB and PostgreSQL together, and the traps of moving data between them. Every Demo number below comes from the same-numbered step file in `steps/`, annotated with its real output (PostgreSQL 18.6, DuckDB 2.0.1, pandas 3.0.6, psycopg 3.3.6).[^demo] Timings are medians of 3 runs on one laptop (20 threads); yours will differ.*

**One sentence to carry through the lecture:**

> **A file doesn't know its own types, and two engines don't always agree. The totals you already know are the check.**

Until now, all our data lived inside PostgreSQL. In practice, an analyst gets data as files (exports, CSVs from other systems, Parquet from a data lake), works on it in Python, and moves it between engines. Every move is a chance to lose something without an error.

---

## Part 0 — Setup

From the `lecture_8/` folder:

```
LECTURE08_DSN=postgresql://postgres:postgres@localhost:5432/lecture08 ./setup.sh
```

`setup.sh` runs the two steps below (psql must be on your PATH); the notebook's **Create lecture08** button runs the same script.

`00-setup.sql` drops and recreates `lecture08`, loads the small shop (600 orders, completed revenue **157,078.41**) and generates `orders_big` with Lecture 7's generator and seed: the same **5,000,000** rows (1,371,464 / 1,733,359 / 1,895,177 per year, total **3,199,787,987.86**). About 45 seconds. It drops `lecture08` with `WITH (FORCE)`, so open connections (the notebook) don't block it (PostgreSQL 13+).

`00-make-files.py` writes `files/` (git ignores it), about 15 seconds:

| File | What it is |
|---|---|
| `orders_big.csv` | `orders_big`, exported by PostgreSQL's `COPY ... TO STDOUT` through psycopg[^pgcopy][^copy] |
| `orders_big.parquet` | the same rows as Parquet, written by DuckDB with the types stated |
| `monthly/orders_2025-01.csv` … `-12.csv` | 2025, one CSV per month; from July a new till system calls the total `order_total` (Part 4) |
| `messy/customers_export.csv` | 50,000 customers from a "CRM export": postal codes with leading zeros, one `n/a` (Part 7) |
| `shop.duckdb` | a DuckDB database file holding `orders_big` (Parts 2 and 3) |

**PostgreSQL version.** The numbers in these notes need PostgreSQL **15 or later** (the generator's `random()` changed in 15, Part 7.5) and 13+ for `DROP DATABASE ... WITH (FORCE)`. On 14 everything runs, with different totals; just make sure the files come from the same server (`setup.sh` does both steps against one server).

**Re-running in class.** The notebook's **Clean** button deletes only what the lecture writes (`files/by_month/`, `files/orders_2025.parquet`, `files/shop_orders.parquet`, the Parquet files in `pipeline/data/`; `notebook_tools/files.py`), so the writing steps can be shown again without rebuilding everything.

**Units.** In this lecture 1 MB = 1,000,000 bytes, as DuckDB and file sizes count. `pg_size_pretty` counts 1 MB = 1,048,576 bytes, so the same `orders_big` table is "467 MB" there (and in Lecture 7) and **489 MB** here.

**New packages:** `duckdb` and `pyarrow` (pandas needs it for Parquet); `polars` was already installed, added to the course's `pyproject.toml`. **Part 6** downloads DuckDB's `postgres` extension the first time (internet needed once).

**The notebook.** `lecture-08-notebook.py` walks through the lecture. Its SQL cells run on DuckDB (marimo's SQL cells use DuckDB unless given another engine[^marimo]). Run it top to bottom; Parts 3, 4 and 6 write files later Parts read.

---

## Part 1 — Row vs column storage

### 1.1 Two ways to lay out a table

A table is a grid; a file is one long line of bytes. Something has to decide the order.

- **Row-based** (CSV, PostgreSQL): one whole row, then the next. All of order 4890168's columns are side by side: good for "show me this order", "insert this order".
- **Column-based** (Parquet): all values of one column, then the next column. All the totals are side by side: good for "sum one column over millions of rows".

Lecture 7, 2.7 showed the cost of the first layout: `sum(orderTotal)` on `orders_big` read **all 59,739 pages**, because every page holds whole rows.[^l7] Parquet is "an open source, column-oriented data file format designed for efficient data storage and retrieval."[^parquet]

*Diagram: `row-vs-col` (illustrative rows).*

### 1.2 Inside a Parquet file

Three levels:[^format]

- the file is cut into **row groups** (blocks of rows);
- inside a row group, each column is stored on its own as a **column chunk** ("Column chunks are composed of pages written back to back"[^chunks]);
- at the end, the **footer** (metadata): column names and types, where each chunk starts, and statistics (min/max) for each chunk.[^pageindex] "File metadata is written after the data to allow for single pass writing."[^format]

**Demo (1.2–1.3):** `orders_big.parquet` has **41** row groups of up to about 120,000 rows. `ordertotal` takes **22.1 MB** of the **102 MB** file. `orderdate` takes almost nothing (0.0 MB, rounded): the file is in date order, so long runs of one date compress to nearly nothing.

*Diagram: `parquet`.*

### 1.3 Read one column, read one column's bytes

DuckDB reads only the columns a query uses ("projection pushdown") and uses the footer to skip data a filter rules out ("filter pushdown").[^ddparquet] **Demo (1.4–1.5):**

| Query | Read |
|---|---|
| `sum(ordertotal)` | **22.2 MB** (Data Read in `EXPLAIN ANALYZE`) |
| `count(*), sum(ordertotal) WHERE` June 2025 | **2 of 41** row groups, **1.2 MB** |

**The same two queries in PostgreSQL** (`EXPLAIN (ANALYZE, BUFFERS)`, notebook 1.3–1.4): both read **59,739 pages** (`Buffers: shared hit` + `read`; e.g. 12,971 + 46,768) **× 8,192 bytes = 489 MB**, the whole table: a row store can't read one column, and without an index on `orderDate` it can't skip pages either (the June query shows `Rows Removed by Filter`).

The skipping works because the file is in date order: each row group spans about five weeks, so its min/max rules it out. In a file shuffled by date every row group would span all three years, and none could be skipped.

---

## Part 2 — Parquet vs CSV (and Excel): size, types, speed

*Diagram: `formats`.*

### 2.1 Size

Compare like with like: a file with a file, a database with a database.

**Demo (2.1), two files** with the same 5,000,000 orders: CSV **356.5 MB**, Parquet **102.1 MB**, about 3.5 times smaller. Parquet compresses each column separately (DuckDB's default codec is Snappy[^ddparquet]), and similar values side by side compress well.

**Two databases** with the same table: PostgreSQL's `orders_big` is **489 MB**, plus **112 MB** for its primary-key index; DuckDB's `shop.duckdb` is **116 MB**, the whole file. PostgreSQL's table is not comparable with the CSV: a database keeps more than the data (whole rows in 8 kB pages, Lecture 7; an index).

### 2.2 Types

A CSV is text: it has no types. Every program that reads it guesses them, every time. DuckDB tries each column against a list of candidate types (BOOLEAN, TIME, DATE, TIMESTAMP, BIGINT, DOUBLE, VARCHAR, …) on a sample of rows; DECIMAL is not one of the default candidates.[^csvauto]

**Demo (2.2):** on the CSV, `ordertotal` is guessed **DOUBLE** (a floating-point number) and the ids **BIGINT**; dates and times are guessed right. The Parquet file **stores** the types: `ordertotal DECIMAL(10,2)`, ids `INTEGER`, as PostgreSQL had them. Part 7.1 shows what the DOUBLE costs.

### 2.3 Speed

**Demo (2.3)**, DuckDB, medians of 3:

| Question | CSV | Parquet |
|---|---|---|
| `count(*)` | about 170 ms | about 1 ms (the row counts are in the footer) |
| `sum(ordertotal)` | about 200 ms (457 MB read, parsed as text) | about 13 ms (22 MB) |
| `WHERE orderid = 4890168` | about 330 ms | about 7 ms (1 of 41 row groups, 2.6 MB) |

PostgreSQL's `sum(orderTotal)` on `orders_big`: about 180 ms. (With its primary-key index, PostgreSQL's single-order lookup reads 4 pages, Lecture 7 Lab 1: an index beats any scan for one row.)

**When CSV is still the right choice:** a small file a person will open in Excel or a text editor, or a system that only speaks CSV. For anything big, typed or read many times: Parquet.

### 2.4 And Excel?

Analysts receive a lot of data as `.xlsx`. DuckDB reads and writes it with its `excel` extension (`INSTALL excel; LOAD excel;`, downloaded once).[^ddexcel] Three facts decide how far it goes:

- **Rows.** A worksheet holds "1,048,576 rows by 16,384 columns".[^xllimits] Our 5,000,000 orders don't fit. **Demo:** `COPY (FROM 'files/orders_big.parquet') TO 'files/orders_big.xlsx' (FORMAT xlsx, HEADER true)` stops after about 10 s with `XLSX: Sheet row limit of '1048576' rows exceeded!` (DuckDB's `sheet_row_limit`: "An error is thrown if this limit is exceeded."[^ddexcel])
- **Types.** An Excel cell has no column type. Writing, "Numeric types are cast to `DOUBLE`"; reading, types are "inferred based on the first "data" row in the sheet", and "almost all columns are inferred as either `DOUBLE` or `VARCHAR`".[^ddexcel]
- **Format.** An `.xlsx` file is a zip package of XML files ("A separate XML file is created for each worksheet"; rename it "from .xlsx to .zip" to see them).[^ooxml] Text, compressed: smaller than CSV, slow to write and read.

**Demo (notebook 2.4):** June 2025 (155,419 orders) written three ways, then `count(*)` and `sum(ordertotal)` read back:

| | Size | Write | Read | Total | `ordertotal` comes back as |
|---|---|---|---|---|---|
| CSV | 11.1 MB | 0.06 s | 0.06 s | 99974417.46000026 | DOUBLE (guessed) |
| Parquet | 3.2 MB | 0.06 s | 0.002 s | **99974417.46** | DECIMAL(10,2) (stored) |
| Excel | 8.0 MB | 1.2 s | 0.57 s | 99974417.4599999 | DOUBLE (every number) |

`DESCRIBE` on the `.xlsx` shows `orderid`, `customerid` and `rating` as DOUBLE too, and **`deliverydate` as DOUBLE**: it's empty in the first row (an in-store order), so the first-row guess got it wrong. `orderdate` and `ordertime`, filled in the first row, came back right. **Course rule of thumb:** Excel for a small result a person will open; Parquet for anything you'll compute on.

---

## Part 3 — A database server, and a database in a file

To see what DuckDB is, first look at what PostgreSQL is: we've used it for seven lectures without opening the box.

### 3.1 PostgreSQL is a server

*Diagram: `postgres`. Steps: `03-postgres-server.sql` (psql).*

"PostgreSQL uses a client/server model."[^arch]

- **The server** is a program, `postgres`, that is always running: "A server process, which manages the database files, accepts connections to the database from client applications".[^arch]
- **Clients** are everything that talks to it: psql ("a terminal-based front-end to PostgreSQL"[^psql]), graphical tools such as pgAdmin ("The PostgreSQL management tool"[^pgadmin]) or DBeaver (a "Universal Database Tool" for many databases[^dbeaver]), your Python with psycopg (Part 5), "a web server that accesses the database to display web pages".[^arch] The UI is not the database: pgAdmin and DBeaver are clients like psql, with buttons.
- **Over the network:** "the client and the server can be on different hosts", talking "over a TCP/IP network connection",[^arch] with a user and password; `pg_hba.conf` says who may connect from where.[^hba]
- **One process per connection:** the server "starts ("forks") a new process for each connection."[^arch]

**The connection string** says where the server is and who you are:

```
postgresql://postgres:postgres@localhost:5432/lecture08
└─ kind ──┘  └ user ┘ └ pass ┘ └─ host ─┘ └port┘ └ database ┘
```

| Part | Here | Means |
|---|---|---|
| `postgresql://` | | talk to a PostgreSQL server |
| user, password | `postgres`, `postgres` | who you are; the server checks it against `pg_hba.conf`[^hba] |
| host | `localhost` | the machine the server runs on: this computer. A company server would have a name like `db.example.com` |
| port | `5432` | which program on that machine: PostgreSQL's default port[^port] |
| database | `lecture08` | one of the server's databases |

The notebook takes it apart with `psycopg.conninfo.conninfo_to_dict(DSN)`. DuckDB's "connection string" is a file name, `duckdb.connect("files/shop.duckdb")`: no host, no port, no password.

**Demo (3.1–3.2): many files.** The server keeps everything in its **data directory** (here `/var/lib/postgresql/18/docker`): 24 entries, among them `base` (one folder per database), `pg_wal` (the write-ahead log: changes are logged before the table files change, so the server can recover after a crash[^wal]), `postgresql.conf` (the settings[^conf]) and `pg_hba.conf`.[^layout] "Each table and index is stored in a separate file."[^layout] The `lecture08` database alone is **337 files, 582 MB**; `orders_big` is `base/16384/16502`, its primary key `base/16384/16518` (Lecture 7, Part 2 opened the first). You never open these files: only the server does. To copy a database you ask the server to export it (`pg_dump`, "a utility for exporting a PostgreSQL database"[^pgdump]).

**Demo (3.3): many processes.** With two psql terminals connected, `pg_stat_activity` ("one row per server process"[^stats]) shows **2 `client backend`** rows, one per terminal, each with its own process id, and **8** of the server's own background processes (`checkpointer`, `walwriter`, `autovacuum launcher`, …[^stats]). They run whether anyone is connected or not.

**What it is for:** many people and programs reading and writing the same data at the same time, safely, all day: the shop's tills, its website and its analysts on one database, each with their own login. **The price:** someone installs the server, keeps it running, and looks after it.

### 3.2 DuckDB: the database in your program, in one file

*Diagram: `embedded`. Steps: `03-duckdb-embedded.py`.*

DuckDB is a **database engine** that runs inside the program using it: "DuckDB is primarily an in-process database system, and as such, it offers client APIs ("drivers") for several languages".[^clients] "By default, DuckDB does not run as a separate process but is completely embedded within a host process." "For DuckDB, there is no DBMS server software to install, update, and maintain."[^why] Two ways to use it:

- **from a terminal:** the DuckDB **CLI**, "a single, dependency-free executable":[^cli] `duckdb files/shop.duckdb`, then SQL, much like psql but with no server behind it;
- **from a program:** in Python it's a library (`import duckdb`); the client list also has R, Java, Node.js, Go, Rust, C/C++, ODBC and others.[^clients]

Either way, data "can be stored in DuckDB's native format, a single-file database".[^why]

**Demo (3.4–3.5):** `duckdb.connect()` is an in-memory database ("all data is lost when the process finishes"[^ddconnect]). `duckdb.connect('files/shop.duckdb')` opens one file holding the whole database (`00-make-files.py` wrote it): `orders_big`, **116 MB**. Copy the file, and you have copied the database. (While it's open, DuckDB may keep a second file next to it, `shop.duckdb.wal`, deleted on a normal exit.[^ddfiles])

| | PostgreSQL | DuckDB |
|---|---|---|
| A database is | 337 files the server owns | 1 file you own |
| Runs | always, as a server | inside your program, while it runs |
| Clients | many, over the network, with logins | your program |
| Writers at once | many | one process |
| Works on | rows, in pages (Lecture 7) | columns: a "columnar-vectorized query execution engine"[^why] |

**The trap: one writer. Demo (3.6):** with the notebook holding `shop.duckdb` open, a second Python process opening it fails: `IO Error: Could not set lock on file ... Conflicting lock is held`. A loud failure. The rule: "one process can both read and write to the database", or "multiple processes can read from the database, but no processes can write".[^concurrency] **Demo (3.7):** after `close()`, two `read_only=True` processes read it side by side. (DuckDB 2.0 adds a remote protocol for writing from several processes;[^concurrency] this course doesn't use it.) The usual way to hit this: a notebook has the file open, and you start a script or the DuckDB CLI on the same file.

### 3.3 Use cases: PostgreSQL and DuckDB

*Diagram: `when` (course rule of thumb).*

- **PostgreSQL** when many people or programs use the data at the same time, data is written all day (orders, payments), it must always be on, and who-may-see-what matters.
- **DuckDB** when one analyst works on a copy: big scans and aggregations (it "is designed to support analytical query workloads"[^why]), data arriving as files, results leaving as files, and no server to run.
- **Often both:** the orders live in PostgreSQL; the analysis runs in DuckDB, on a Parquet export or reading PostgreSQL directly (Part 6).


### 3.4 One record: row store vs column store

The same two lookups in both databases, PostgreSQL's `orders_big` and DuckDB's `files/shop.duckdb` (notebook 3.4; median of 5 runs on the reference laptop):

| Lookup | PostgreSQL (rows) | DuckDB (columns) |
|---|---|---|
| one order, `orderID = 4890168` | **0.7 ms**: `Index Scan using orders_big_pkey`, 4 pages | 2.1 ms: `Row Groups Scanned: 1 / 60` |
| one customer's 97 orders, `customerID = 4242` | 103 ms: `Parallel Seq Scan`, all 59,739 pages | **3.6 ms**: `Row Groups Scanned: 60 / 60`, one column |

- **With an index, the row store wins.** PostgreSQL's primary-key index gives the row's address, and one 8 kB page holds the whole row (Lecture 7). DuckDB has no index on `orderid`, but "DuckDB automatically creates zonemaps (also known as min-max indexes) for the columns of all general-purpose data types", and "DuckDB can skip any row group whose min-max range does not contain that filter value".[^ddindex] `orderid` is in order, so 59 of 60 row groups are skipped; then the order's 11 values are collected from 11 column chunks.
- **Without an index, the column store wins.** PostgreSQL reads every page, every whole row. DuckDB reads the `customerid` column of every row group (one customer's orders are spread over the whole period, so min/max can't skip any: "The more ordered the data within a column, the more valuable the zonemap indexes will be"[^ddindex]) and then fetches the other columns for the 97 matches only. (With an index on `customerID`, PostgreSQL reads 97 pages for these orders: Lecture 7.)

DuckDB also has real indexes (ART), created for `PRIMARY KEY` and `UNIQUE` constraints or with `CREATE INDEX`, "to speed up point and very highly selective (i.e., < 0.1%) queries".[^ddart] `shop.duckdb` has none.
---

## Part 4 — Querying and writing files

### 4.1 One file

A file name in `FROM` is a table: `FROM 'files/orders_big.parquet'`, `FROM 'files/orders_big.csv'`. `read_csv(...)` and `read_parquet(...)` do the same with options (Part 7 uses `types` and `nullstr`).

### 4.2 Many files: a glob, and a silent half

`'files/monthly/*.csv'` reads all twelve monthly files as one table (`*` "Matches any number of any characters"[^multi]). The story: in July the shop changed its till system, and the new one exports the total as `order_total`.

**Demo (4.1):** `Schema mismatch between globbed files ... Column with name: "ordertotal" is missing`. "By default, DuckDB reads the schema of the first file provided", and a column of the first file missing from a later file causes an error.[^multi] A loud failure: good, and the notebook shows it as a warning box, on purpose. The file it names varies between runs (`orders_2025-07`, `-09`, `-10`, …): the files are read in parallel and the error comes from whichever one hits it first.

**Demo (4.2):** the error message suggests `union_by_name = true`, which matches columns by name and sets missing values to NULL.[^multi] It runs: **1,895,177** orders (all of 2025) and a total of **591,722,020.29**. That's about half the real 1,213,754,385.91. `sum()` skips NULLs, so July to December added nothing.

**Demo (4.3):** `filename = true` adds the file each row came from.[^multi] Grouping by it shows `with_total = 0` from `orders_2025-07.csv` on.

**Demo (4.4):** `sum(coalesce(ordertotal, order_total))` gives **1,213,754,385.91** (as a DOUBLE, so round it, Part 7.1), the same as the Parquet file's 2025: **1,895,177** orders, **1,213,754,385.91**. The check that caught it: a count *and a sum*, compared with a source you trust. The count alone was right.

### 4.3 Writing files

`COPY (query) TO 'file' (FORMAT parquet)` writes any query's result. **Demo (4.5):** the twelve fixed monthly CSVs become one `orders_2025.parquet` with `ordertotal` cast to `DECIMAL(10,2)`: 1,895,177 orders, 1,213,754,385.91.

### 4.4 Folders as partitions

`PARTITION_BY (year, month)` writes one folder per value, `year=2025/month=6/data_0.parquet`;[^partwrite] it takes columns, not expressions, so the query computes `year` and `month` first.[^partwrite] Reading the folders back, DuckDB recognises the `key=value` names and adds `year` and `month` as columns.[^hive] **Demo (4.6):** 36 files, one per month.

"Filters on the partition keys are automatically pushed down into the files. This way the system skips reading files that are not necessary to answer a query."[^hive] **Demo (4.7–4.8):**

| Filter for June 2025 | Files opened | Read |
|---|---|---|
| `year = 2025 AND month = 6` | **1 of 36** | 721 kB |
| `orderdate >= '2025-06-01' AND orderdate < '2025-07-01'` | **all 36** (min/max then skip all but 2 of 65 row groups) | 1.2 MB |

Same answer (155,419 orders, 99,974,417.46). **Why the difference:** the folder names are `key=value` pairs ("Hive partitioning"), and "Within each folder, the partition key has a value that is determined by the name of the folder".[^hive] So `year` and `month` exist **only in the folder names**, not inside the files. A filter on them can be answered from the names alone, before any file is opened (`File Filters: (year = 2025)(month = 6)`, `Scanning Files: 1/36`). A filter on `orderdate` can't: DuckDB doesn't know that the folder `month=6` holds only June dates, so it opens every file and checks each footer's min/max (Part 1.2), then reads 2 of 65 row groups.

This is Lecture 7's partition-pruning trap (9.4) in files: only a filter on the partition key skips partitions.[^l7] On 36 small local files the difference is milliseconds; with thousands of files, opening every one is the slow part. **Rule:** filter on the partition columns, alone or next to the date filter (`WHERE year = 2025 AND month = 6 AND orderdate >= ...`).

---

## Part 5 — Python and PostgreSQL (psycopg, parameters, pandas, polars)

### 5.1 Connecting, step by step

psycopg is the Python client for PostgreSQL: what psql does, from Python. The notebook walks through it in five steps:

1. **What you need:** a running server, the connection string (3.1), `pip install psycopg`.
2. **Connect:** the notebook writes every part out, `psycopg.connect(host="localhost", port=5432, dbname="lecture08", user="postgres", password="postgres")`, the same as the connection string `postgresql://postgres:postgres@localhost:5432/lecture08` (3.1). `conn.info.backend_pid` is the server process serving this connection; `conn.close()` ends it.
3. **Run SQL:** `cur = conn.cursor()`, `cur.execute(sql)`, `fetchone()` / `fetchall()` / `fetchmany(n)`; rows are tuples, `cur.description` has the column names. **Demo (5.1):** `(529, Decimal('157078.41'))`: `NUMERIC` arrives as Python's `Decimal`, exact.
4. **`with psycopg.connect(DSN) as conn:`** closes the connection at the end of the block. psycopg starts a transaction on the first statement; the `with` block commits it at the end (rolls back on an error); `autocommit=True` commits every statement at once.[^txn]
5. **When it fails** (`psycopg.OperationalError`), the message says why (notebook, run against the reference server): `password authentication failed for user "postgres"`, `database "lecture99" does not exist`, or, nothing listening on the port, `Is the server running on that host and accepting TCP/IP connections?`

The notebook's cells share one connection, `pg_conn`, made automatically when the notebook runs (and again after the setup button recreates `lecture08`). If the server restarts while the notebook is open, run the notebook again.

### 5.3 Parameters

"Passing parameters to a SQL statement happens in functions such as Cursor.execute() by using %s placeholders in the SQL statement, and passing a sequence of values as the second argument."[^params] **Demo (5.2):** `cur.execute("... WHERE status = %s", (status,))`: 27 cancelled orders, 6,169.21. Write `%s` without quotes around it, and pass the values as a tuple (the comma in `(status,)`).

**The trap (5.3):** an f-string. A user types `x' OR '1'='1` into a "search by last name" box:

```python
sql = f"SELECT count(*) FROM customers WHERE lastName = '{last_name}'"
# SELECT count(*) FROM customers WHERE lastName = 'x' OR '1'='1'
```

**30**: every customer. The quote in the text ended the string and the rest became SQL. That's **SQL injection**. With `%s` the same text is only ever a value: **0** (nobody has that name). psycopg's documentation: "Never use % or + to merge values into queries".[^params] (Parameters are for values only; table and column names can't be passed this way.[^params])

### 5.4 Into pandas: three silent changes

**Demo (5.4):** `pd.read_sql("SELECT * FROM orders", conn)` works, with a warning: *"pandas only supports SQLAlchemy connectable (engine/connection) or database string URI or sqlite3 DBAPI2 connection. Other DBAPI2 objects are not tested."* (the docs: a DBAPI2 connection other than sqlite3 isn't supported[^readsql]). Then, without a word:

- column names are **lowercase** (`ordertotal`): PostgreSQL folded them when the table was created;
- `employeeid` and `rating` are **float64**: they contain NULLs, and with NumPy types a missing value forces the column to float64;[^missing]
- `ordertotal` is **float64**: `read_sql` converts `Decimal` to floating point by default (`coerce_float`[^readsql]), so completed revenue is **157078.40999999997**.

**Demo (5.5):** building the DataFrame from the cursor (`pd.DataFrame(cur.fetchall(), columns=[d.name for d in cur.description])`) keeps the `Decimal`s (dtype `object`): **157078.41**, exact but slower to compute with.

**pandas guesses from CSVs too. Demo (5.6):** `pd.read_csv('data/orders.csv')` reads `employeeID` as `2.0, 1.0, 6.0` (float64: online orders have no employee). `dtype={'employeeID': 'Int64'}` (capital I, pandas' integer type that allows missing values[^missing]) gives `2, 1, 6`. The messy export's postal codes: `0049` becomes **49** (notebook, 5.3); `dtype={'postal_code': str}` keeps `'0049'`.

### 5.5 The same with polars

polars is another DataFrame library, used much like pandas. **Demo (5.6b–5.6d):**

- **From PostgreSQL** (`pl.read_database(sql, connection=conn)`), polars keeps the types: `employeeid` and `rating` stay **Int64** (with nulls), `ordertotal` stays **Decimal(38, 2)**, and completed revenue is exactly **157078.41**. pandas, on the same connection, gave floats.
- **From a CSV** it guesses, like everyone: `employeeID` stays an integer (`2, 1, 6`), but `orderTotal` is **Float64**, so completed revenue is **157078.40999999997** again.
- **The messy export:** `n/a` after the sample stops polars with an error (`could not parse n/a as dtype i64`), as it stops DuckDB, where pandas said nothing. With `null_values=["n/a"]` it reads, and the postal codes lose their zeros (`49, 6, 65`), as in pandas.

Whichever library: say the types of the columns that matter.

**Then it's ordinary DataFrame work.** The notebook asks Lectures 3–5's questions of the pulled tables, in both libraries: orders and revenue per status (completed **529**, **157,078.41**), completed revenue per month (January 2024: **9,902.54**), and the top 3 customers after a join with `customers` (Aram Vardanyan, Yerevan, **14,625.38**). Same answers as SQL; in pandas the money is a float, in polars a Decimal.

### 5.6 Let the database do the work

The total of all 2025 orders, four ways (notebook, one run on the reference laptop):

| How | Rows sent | Fetch | Sum |
|---|---|---|---|
| SQL: `sum()` in PostgreSQL | 1 | 0.11 s | — |
| plain Python: `fetchall()` + `sum()` | 1,895,177 | 2.9 s | 0.07 s |
| pandas: `read_sql` + `.sum()` | 1,895,177 | 3.4 s | 0.002 s |
| polars: `read_database` + `.sum()` | 1,895,177 | 3.7 s | 0.005 s |

Same answer every time, 1,213,754,385.91. pandas and polars add 1.9 million numbers in milliseconds: **moving the rows** from the server is what takes seconds, whichever library receives them. (All 5 million rows took about 9 s and 1 GB of memory in a test run.) **Filter and aggregate in SQL; fetch the result.**

---

## Part 6 — DuckDB and PostgreSQL together

`ATTACH` with `TYPE postgres` makes a PostgreSQL database readable from DuckDB; `READ_ONLY` "prevents making modifications".[^ddpg] **Demo (6.1):** after `INSTALL postgres; LOAD postgres; ATTACH '...' AS pg (TYPE postgres, READ_ONLY)`, the six shop tables appear as `pg.customers`, `pg.orders`, …

**Demo (6.2):** `FROM pg.orders WHERE status = 'completed'`: **529**, **157,078.41**. The same table, read through another engine.

### 6.1 Who does the work?

**Demo (6.3):** `EXPLAIN` of a count and sum over `pg.orders_big` has one node, **Postgres Query**, with the SQL DuckDB sent: `SELECT count(*) ..., CAST(sum("ordertotal") AS NUMERIC(38,2)) ... FROM "public"."orders_big" WHERE ("status" = 'cancelled')`. PostgreSQL did the work and sent one row back. This depends on the query and the extension's settings (filter pushdown is on by default[^ddpg]); `EXPLAIN` is how to find out.

### 6.2 One query, two sources

**Demo (6.4):** 2025's completed orders from the Parquet file, joined to `pg.employees` for the names: revenue per salesperson, from **94,134,848.23** (Vahe Sahakyan) to **92,720,112.76** (Gor Mkrtchyan). Online orders have no salesperson, so the inner join leaves them out (Lecture 4).

**Demo (6.5):** `COPY (SELECT * FROM pg.orders) TO 'files/shop_orders.parquet'`: PostgreSQL to Parquet in one statement, 600 rows, and `ordertotal` is still `DECIMAL(10,2)`. A CSV export would have lost the type.

**Demo (6.6):** `postgres_query('pg', 'SQL')` sends the text to PostgreSQL as it is, to run there.[^ddpg] Part 7 uses it to run the same SQL in both engines.

**Which engine when** (course rule of thumb): PostgreSQL for the live, shared, constantly updated data; DuckDB for analysis on a copy: files, big scans, exports, and joining things that don't live in the same place.

---

## Part 7 — Traps and checks

### 7.1 A total that changes every time you run it

**Demo (7.1):** `sum(ordertotal)` on the CSV, twice: **3199787987.860031**, then **3199787987.8600454**. Two runs, two totals, both wrong after the .86. `ordertotal` was guessed **DOUBLE** (2.2), and "real and double precision are inexact, variable-precision numeric types"[^pgnum]: most decimal fractions can't be stored exactly, and 5 million tiny errors add up. DuckDB adds in parallel, in a different order each run, so the error is different each run.

**Fix:** state the type, `read_csv(..., types = {'ordertotal': 'DECIMAL(10,2)'})`: **3199787987.86**, every time. Or read Parquet, which stores the type. Money is never a DOUBLE.

### 7.2 Leading zeros

Armenian postal codes have four digits,[^postal] and some start with 0, like the Foreign Ministry's "Yerevan 0010".[^postal] The export's codes are generated for illustration (Yerevan's as 0001–0099). **Demo (7.2):** DuckDB keeps `postal_code` as `VARCHAR` (`0049`, `0006`, …). pandas makes it a number: **49** (Part 5.3). Any column of digits that isn't a quantity (postal codes, phone numbers, account numbers) must be read as text.

### 7.3 A value the sample didn't see

DuckDB guesses types from a sample: "The default sample size is 20,480 rows."[^csvauto] In the export, `discount_pct` is a whole number until customer 30,001, where someone typed `n/a`.

**Demo (7.3):** `Conversion Error: CSV Error on Line: 30002 ... Could not convert string "n/a" to 'BIGINT'`. A loud failure. The fix is to say what `n/a` means: `read_csv(..., nullstr = 'n/a')`: 50,000 customers, 49,999 with a discount, average **7.13**.

pandas reads the same file without a word: in our run `n/a` became NaN and the column float64 (pandas treats "N/A", "NULL" "and other common representations of missing data" as NaN by default[^readcsv]). Sometimes that's what you want; you should decide it, not find out later.

### 7.4 Engine differences: the same SQL, two answers

`postgres_query` runs a query inside PostgreSQL, so both engines get the same text. **Demo (7.4):**

| Question | SQL | DuckDB | PostgreSQL |
|---|---|---|---|
| Average items per order | `sum(quantity) / count(DISTINCT orderID)` | **2.215** | **2** |
| Best-rated orders | `ORDER BY rating DESC, orderID LIMIT 3` | 1007, 1013, 1015 (rating 5) | **1001, 1002, 1003 (no rating)** |

- **Division:** in PostgreSQL, "for integral types, division truncates the result towards zero".[^pgmath] In DuckDB, "When both operands are integers, / performs floating points division"; `//` is integer division.[^ddnum] Portable: make one side non-integer, `sum(quantity)::numeric / count(...)`.
- **NULLs in a sort:** in PostgreSQL "null values sort as if larger than any non-null value; that is, NULLS FIRST is the default for DESC order".[^pgorder] "DuckDB keeps NULLS LAST even for DESC ordering, whereas PostgreSQL places NULLs first on DESC."[^ddorder] Portable: write `NULLS LAST` yourself.

The same applies to any two engines: a query moved from one to another needs its answer checked, not just its syntax.

### 7.5 Matching totals

**Demo (7.5):** one query, every copy of `orders_big` made in this lecture:

| Source | Rows | Total |
|---|---|---|
| PostgreSQL | 5,000,000 | 3199787987.86 |
| CSV (as guessed) | 5,000,000 | **3199787987.86002** (varies) |
| CSV (DECIMAL) | 5,000,000 | 3199787987.86 |
| Parquet | 5,000,000 | 3199787987.86 |
| Parquet folders | 5,000,000 | 3199787987.86 |
| DuckDB file | 5,000,000 | 3199787987.86 |

(The totals are cast to text so that `UNION ALL` doesn't turn them all into one type.) **After every move of data:** compare the row count *and* a sum of an amount column with the source. Part 4 showed why both: the count was right and the sum was half.

**A real case, from preparing this lecture.** The check was run against a PostgreSQL **14** server, with files written from a PostgreSQL 18 server: every file row said 3199787987.86, the PostgreSQL row **3198455015.58**. Same 5,000,000 rows, same yearly counts, different sums. `orders_big` is generated with `random()` after `setseed(0.42)`, and PostgreSQL 15 changed `random()`'s algorithm, so on 14 the same seed gives different totals (the dates don't use `random()`, so the counts agree).[^l7rand] The files simply didn't come from that database. Fix: run `setup.sh` against the server you compare with; the notebook prints `SELECT version()` next to the check.

---

## Part 8 — A small pipeline: PostgreSQL → Parquet → report

`pipeline/` puts Parts 4–7 together as one repeatable job, organised by kind of thing:

```
pipeline/
  run.py               the only entry point: runs the steps in order
  queries/extract/     PostgreSQL SQL, one query per raw file (orders.sql, employees.sql)
  queries/transform/   DuckDB SQL, one query per report (monthly_revenue.sql, salesperson_revenue.sql)
  queries/check/       source.sql (PostgreSQL) and checks.sql (DuckDB)
  .env                 the credentials: PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD (git-ignored; .env.example is the template)
  src/                 config.py (paths, parameters; loads .env with python-dotenv), extract.py, transform.py, check.py
  data/raw/            written by extract: the data as it came out of PostgreSQL
  data/reports/        written by transform: built from data/raw/ only
  logs/pipeline.log    every run's log: Python's logging module, to the screen and this file (git-ignored)
```

| Step | Runs in | Reads → writes |
|---|---|---|
| 1. extract | **PostgreSQL**: psycopg sends each `queries/extract/<name>.sql` to the server; polars fetches the result (keeping the types) and writes it, since PostgreSQL can't write Parquet | `orders_big`, `employees` → `data/raw/<name>.parquet` |
| 2. transform | DuckDB, files only; each raw file is a view named after it (`orders`, `employees`) | `data/raw/` → `data/reports/<name>.parquet` |
| 3. check | PostgreSQL (`source.sql`, the same period) for the source numbers, then DuckDB (`checks.sql`) | everything → a table of checks |

The SQL files hold no file paths, only table names; adding a report means adding one `.sql` file.

**Parameters.** The period is not written in the SQL: `queries/extract/orders.sql` says `WHERE orderDate >= %(start)s AND orderDate < %(end)s`, and `EXTRACT_PARAMS` in `src/config.py` holds the values (default: all of 2025). psycopg sends them separately from the SQL text (5.3), and the check's `source.sql` uses the same ones. Change the dates, run again, and every file is rebuilt for the new period; the notebook has two date pickers for it. **Demo, June 2025** (`start = 2025-06-01`, `end = 2025-07-01`): extract **1.5 s** for **155,419** orders (the same as Part 4.4's June), all four checks ok, completed revenue **92,038,352.53**, of which in-store **61,453,509.00**. Run it with `python pipeline/run.py` (connection string from `LECTURE08_DSN`) or the notebook's Part 8. **Demo (reference run):** extract **16 s** for 1,895,177 rows, transform **0.04 s**; `data/raw/orders.parquet` **8.8 MB** (polars compresses with zstd by default). Step 1 is the slow one: PostgreSQL runs the query in a fraction of a second, then 1.9 million rows travel to Python (5.6). The check table:

| Check | Source | Pipeline | Result |
|---|---|---|---|
| extract: rows | 1895177 | 1895177 | ok |
| extract: total | 1213754385.91 | 1213754385.91 | ok |
| transform: monthly = completed | 1116859765.85 | 1116859765.85 | ok |
| transform: salespeople = completed in-store | 747581451.16 | 747581451.16 | ok |

The last check is a fact about the data, not just a copy: online orders have no salesperson, so the salespeople must add up to completed **in-store** revenue exactly. Why build it this way: after step 1 nobody touches the live database, the report can be rebuilt from the files at any time, and step 3 says whether it can be trusted.

---

## Part 9 — Why all of this matters (the one idea to leave the room with)

| Trap | Looked like | Was |
|---|---|---|
| `sum(ordertotal)` on the CSV | the total | a DOUBLE, a different wrong total every run (7.1) |
| A glob, then `union_by_name` | 1,895,177 orders and a total | half the year's revenue: July on was NULL (4.2) |
| `WHERE orderdate` on month folders | a filter on the date | all 36 files opened (4.4) |
| `pd.read_sql` | the orders table | floats: 157078.40999999997, `employeeid` 2.0 (5.3) |
| `pd.read_csv`, `pl.read_csv` | postal codes | 0049 became 49 (5.3, 5.4, 7.2) |
| `n/a` in a CSV, read by pandas | a column of discounts | NaN, float64, no warning (7.3) |
| f-string SQL | a search by last name | all 30 customers (5.2) |
| `sum / count` | average items per order | 2 in PostgreSQL, 2.215 in DuckDB (7.4) |
| `ORDER BY rating DESC` | best-rated orders | unrated orders, in PostgreSQL (7.4) |
| Fetch, then sum in Python | the same total | about 25× slower, 1.9 million rows over the network (5.4) |

**Three loud failures:** the glob with a missing column (4.2), `n/a` after DuckDB's sample (7.3), the locked `.duckdb` file (3.2). Read the error before reaching for the option it suggests: in 4.2 the suggested option was what made the answer wrong.

**The checks:**

- **State the types** of anything that matters, especially money (`DECIMAL`) and codes (text). Prefer Parquet, which keeps them.
- **After every move of data,** compare the row count and a sum with the source.
- **Pass values with `%s`,** never with f-strings.
- **Aggregate in the database,** fetch the result.
- **Moving SQL between engines,** check the answer, not just that it runs: integer division and NULL order differ.
- **Filter on the partition column** (folders, as in PostgreSQL).

Same point as every lecture since 4: the wrong answer arrives without an error. Knowing which total to compare it with is the skill.

---

## DuckDB functions used in this lecture

The notebook has an expandable note at each one's first use. In short:

| Function / statement | What it does | Options used here |
|---|---|---|
| `FROM 'file.parquet'`, `read_parquet()` | read Parquet; "If your file ends in `.parquet`, the function syntax is optional"[^ddparquet] | `hive_partitioning`, `union_by_name`, `filename` |
| `FROM 'file.csv'`, `read_csv()` | read CSV; the file name alone means `read_csv` with everything auto-detected[^from][^csvimport] | `types`, `nullstr`, `union_by_name`, `filename`, `sample_size`, `all_varchar`, `header`, `delim` |
| `parquet_metadata()`, `parquet_schema()` | the footer: one row per column chunk (row group, min/max, sizes); the stored types[^pqmeta] | — |
| `read_blob()` | files as bytes, with `filename`, `size`, `last_modified`[^readblob] | — |
| `glob()` | the file names matching a pattern, in a column `file`[^utility] | — |
| `DESCRIBE` | the columns and types of a table or query[^describe] | — |
| `EXPLAIN ANALYZE` | "both pretty-prints the query plan, and executes it"[^explain] | — |
| `COPY ... TO` | "exports data from DuckDB to an external CSV, Parquet, JSON, or BLOB file"[^copy2] | `FORMAT`, `PARTITION_BY`, `OVERWRITE`, `COMPRESSION`, `ROW_GROUP_SIZE` |
| `ATTACH` / `DETACH` | add another database (a DuckDB file, or PostgreSQL with `TYPE postgres`) to the session / close it[^attach][^ddpg] | `READ_ONLY` |
| `postgres_query()` | run SQL text inside the attached PostgreSQL[^ddpg] | — |

---

## Lab (not lectured)

On `lecture08` and `files/`, after the notebook has run. For each, show the query and the check.

1. **2024 from Parquet.** Count and total of 2024's orders from `orders_big.parquet`; prove they match PostgreSQL's.
2. **Write and verify.** Write 2023's completed orders to `files/completed_2023.parquet`. Report its size, and prove its count and total match PostgreSQL's.
3. **The small shop as a CSV.** Read `data/orders.csv` with DuckDB. Which types does it guess for `employeeID`, `rating` and `orderTotal`? Is completed revenue 157,078.41 exactly? Make it so.
4. **A safe search.** With psycopg, write a function `revenue_by_last_name(cur, name)` returning the number of completed orders and their revenue for customers with that last name. Test it with `Sargsyan` and with `x' OR '1'='1`.
5. **Pruning, twice.** November and December 2024 from `files/by_month`: once with `year`/`month`, once with `orderdate`. How many files does each open?

## Lab solution key (instructor only)

*Verified on the reference setup (DuckDB 2.0.1, PostgreSQL 18.6).*

1. **1,733,359** orders, **1,108,299,212.59**, in both (`WHERE orderdate >= '2024-01-01' AND orderdate < '2025-01-01'`).
2. **1,262,294** orders, **808,248,909.24**, both sides; the file is about **25.7 MB**.
3. `employeeID` BIGINT, `rating` BIGINT, `orderTotal` **DOUBLE**; completed revenue **157078.40999999992**. With `types = {'orderTotal': 'DECIMAL(10,2)'}`: **157078.41**.
4. `... WHERE c.lastName = %s AND o.status = 'completed'` with `(name,)`: Sargsyan **42** orders, **11,188.97**; the injection string **0**.
5. `year = 2024 AND month IN (11, 12)`: **2/36** files; the `orderdate` range: **36** files (4 of 65 row groups). Both: **302,513** orders, **194,050,218.11**.

---

## Open questions / TODO

- **Versions.** Verified on DuckDB 2.0.1 only. The `orders_big` rows are identical on PostgreSQL 15+ (Lecture 7). DuckDB's CSV sniffer has changed between versions; older DuckDB may guess `postal_code` differently. Part 6.3's plan (the whole query sent to PostgreSQL) depends on the `postgres` extension's version.
- **Timings** are from one laptop with 20 threads. On a 4-core laptop, expect the CSV numbers to grow more than the Parquet ones.
- **7.1's digits** differ on every run by design; the notebook shows a different number than these notes. Running `SET threads = 1` makes it repeatable (3199787987.86184 in a test run), but no less wrong.
- **Possible split** if the lecture is too long: Parts 1–4 (files and DuckDB), then Parts 5–7 (Python and checks).

---

[^demo]: `steps/00-setup.sql` … `steps/07-traps.sql`; outputs pasted from real runs. Timings: 2.3 medians of 3 (DuckDB), 5.7 single run.
[^l7]: `lectures/lecture_7/lecture-07-notes.md`, Parts 2.7 (467 MB read for one column) and 9.4 (a filter that can't prune).
[^parquet]: Apache Parquet, *Overview*: "Apache Parquet is an open source, column-oriented data file format designed for efficient data storage and retrieval." https://parquet.apache.org/docs/overview/
[^format]: Apache Parquet, *File Format*: "File metadata is written after the data to allow for single pass writing." and "The file metadata contains the locations of all the column chunk start locations." https://parquet.apache.org/docs/file-format/
[^chunks]: Apache Parquet, *Column Chunks*: "Column chunks are composed of pages written back to back." https://parquet.apache.org/docs/file-format/data-pages/columnchunks/
[^pageindex]: Apache Parquet, *Page Index*: "Statistics are stored for ColumnChunks in ColumnMetaData and for individual pages inside DataPageHeader structs", allowing access to pages "based on their min and max values". https://parquet.apache.org/docs/file-format/pageindex/
[^ddparquet]: DuckDB 2.0, *Reading and Writing Parquet Files*: "DuckDB supports projection pushdown into the Parquet file itself." "DuckDB also supports filter pushdown into the Parquet reader." Writing uses "the default compression (Snappy)". https://duckdb.org/docs/2.0/data/parquet/overview.html
[^csvauto]: DuckDB 2.0, *CSV Auto Detection*: "The default sample size is 20,480 rows." "The type detection works by attempting to convert the values in each column to the candidate types." Default candidates: NULL, BOOLEAN, TIME, DATE, TIMESTAMP, TIMESTAMPTZ, BIGINT, HUGEINT, BIGNUM, DOUBLE, VARCHAR. https://duckdb.org/docs/2.0/data/csv/auto_detection.html
[^multi]: DuckDB 2.0, *Reading Multiple Files* (`*` "Matches any number of any characters (including none)"; "The `filename` argument can be used to add an extra `filename` column to the result that indicates which row came from which file.") and *Combining Schemas* ("By default, DuckDB reads the schema of the first file provided"; with `union_by_name` "the columns are correctly unified, and any missing values are set to `NULL`"). https://duckdb.org/docs/2.0/data/multiple_files/overview.html, https://duckdb.org/docs/2.0/data/multiple_files/combining_schemas.html
[^partwrite]: DuckDB 2.0, *Partitioned Writes*: `COPY orders TO 'orders' (FORMAT parquet, PARTITION_BY (year, month));` "Note that the `PARTITION_BY` options cannot use expressions." https://duckdb.org/docs/2.0/data/partitioning/partitioned_writes.html
[^hive]: DuckDB 2.0, *Hive Partitioning*: "By default the system tries to infer if the provided files are in a hive partitioned hierarchy." "Filters on the partition keys are automatically pushed down into the files. This way the system skips reading files that are not necessary to answer a query." https://duckdb.org/docs/2.0/data/partitioning/hive_partitioning.html
[^why]: DuckDB, *Why DuckDB*: "DuckDB uses a columnar-vectorized query execution engine". "Data can be stored in DuckDB's native format, a single-file database". "DuckDB is designed to support analytical query workloads, also known as online analytical processing (OLAP)." "By default, DuckDB does not run as a separate process but is completely embedded within a host process." "For DuckDB, there is no DBMS server software to install, update, and maintain." https://duckdb.org/why_duckdb
[^concurrency]: DuckDB 2.0, *Concurrency*: "Read-write mode: one process can both read and write to the database." "Read-only mode: multiple processes can read from the database, but no processes can write". "Writing to DuckDB's native database format from multiple processes is supported through the Quack remote protocol". https://duckdb.org/docs/2.0/connect/concurrency.html
[^ddnum]: DuckDB 2.0, *Numeric Functions*: "When both operands are integers, `/` performs floating points division (`5 / 2 = 2.5`)"; `//`: `5 // 2` → `2`. https://duckdb.org/docs/2.0/sql/functions/numeric.html
[^ddorder]: DuckDB 2.0, *ORDER BY Clause*: "By default, DuckDB sorts `ASC` and `NULLS LAST`". "DuckDB keeps `NULLS LAST` even for `DESC` ordering, whereas PostgreSQL places `NULL`s first on `DESC`". https://duckdb.org/docs/2.0/sql/query_syntax/orderby.html
[^ddpg]: DuckDB 2.0, *PostgreSQL Extension*: "To make a PostgreSQL database accessible to DuckDB, use the `ATTACH` command with the `postgres` or `postgres_scanner` type." "`ATTACH` can be run with the `READ_ONLY` property which prevents making modifications". "The `postgres_query` table function allows you to run arbitrary read queries within an attached database." Setting `pg_enable_filter_pushdown`: "Whether or not to use filter pushdown", default true. https://duckdb.org/docs/2.0/core_extensions/postgres/overview.html
[^pgmath]: PostgreSQL 18, *Mathematical Functions and Operators*: `/` "Division (for integral types, division truncates the result towards zero)"; `5 / 2 → 2`. https://www.postgresql.org/docs/18/functions-math.html
[^pgorder]: PostgreSQL 18, *Sorting Rows*: "By default, null values sort as if larger than any non-null value; that is, NULLS FIRST is the default for DESC order, and NULLS LAST otherwise." https://www.postgresql.org/docs/18/queries-order.html
[^pgnum]: PostgreSQL 18, *Numeric Types*: "Calculations with numeric values yield exact results where possible"; "The data types real and double precision are inexact, variable-precision numeric types." https://www.postgresql.org/docs/18/datatype-numeric.html
[^pgcopy]: PostgreSQL 18, *COPY*: `STDOUT` "Specifies that output goes to the client application." `HEADER`: "On output, the first line contains the column names from the table." https://www.postgresql.org/docs/18/sql-copy.html
[^copy]: psycopg 3, *Using COPY TO and COPY FROM*: "you can use a COPY ... TO STDOUT statement and iterate over the resulting Copy object, which will produce a stream of bytes objects". https://www.psycopg.org/psycopg3/docs/basic/copy.html
[^params]: psycopg 3, *Passing parameters to SQL queries*: "Passing parameters to a SQL statement happens in functions such as Cursor.execute() by using %s placeholders in the SQL statement, and passing a sequence of values as the second argument". "Never use % or + to merge values into queries". "Only query values should be bound via this method: it shouldn't be used to merge table or field names to the query." https://www.psycopg.org/psycopg3/docs/basic/params.html
[^readsql]: pandas, `read_sql`: `con`: "ADBC Connection, SQLAlchemy connectable, str, or sqlite3 connection"; "If a DBAPI2 object, only sqlite3 is supported." `coerce_float`: "Attempts to convert values of non-string, non-numeric objects (like decimal.Decimal) to floating point". The warning text is from our run (pandas 3.0.6). https://pandas.pydata.org/docs/reference/api/pandas.read_sql.html
[^readcsv]: pandas, `read_csv`: "By default the following values are interpreted as NaN: empty string, "NaN", "N/A", "NULL", and other common representations of missing data." (Lowercase `n/a` is not named on the page; it became NaN in our run, pandas 3.0.6.) https://pandas.pydata.org/docs/reference/api/pandas.read_csv.html
[^missing]: pandas, *Working with missing data*: "The disadvantage of using NumPy data types is that the original data type will be coerced to np.float64 or object."; the nullable types "will maintain the original data type of the data." https://pandas.pydata.org/docs/user_guide/missing_data.html
[^postal]: Wikipedia, *Postal codes in Armenia*: "Postal codes in Armenia consist of four digits."; "the previous postal code for the Foreign Ministry was Yerevan 375010 and is now Yerevan 0010." https://en.wikipedia.org/wiki/Postal_codes_in_Armenia
[^marimo]: marimo, *Using SQL*: "By default, marimo uses the in-memory duckdb connection". https://docs.marimo.io/guides/working_with_data/sql/
[^arch]: PostgreSQL 18, *Architectural Fundamentals*: "In database jargon, PostgreSQL uses a client/server model." "A server process, which manages the database files, accepts connections to the database from client applications". "a client could be a text-oriented tool, a graphical application", or "a web server that accesses the database to display web pages". "the client and the server can be on different hosts", communicating "over a TCP/IP network connection". "it starts ("forks") a new process for each connection." https://www.postgresql.org/docs/18/tutorial-arch.html
[^psql]: PostgreSQL 18, *psql*: "psql is a terminal-based front-end to PostgreSQL." https://www.postgresql.org/docs/18/app-psql.html
[^pgadmin]: pgAdmin: "The PostgreSQL management tool"; "Administration, development and monitoring for PostgreSQL." https://www.pgadmin.org/
[^dbeaver]: DBeaver: "Universal Database Tool"; "Manage and explore SQL databases like MySQL, MariaDB, PostgreSQL, SQLite, Apache Family, and more." https://dbeaver.io/
[^hba]: PostgreSQL 18, *The pg_hba.conf File*: "Client authentication is controlled by a configuration file, which traditionally is named `pg_hba.conf` and is stored in the database cluster's data directory." https://www.postgresql.org/docs/18/auth-pg-hba-conf.html
[^conf]: PostgreSQL 18, *Setting Parameters*: "The most fundamental way to set these parameters is to edit the file `postgresql.conf`, which is normally kept in the data directory." https://www.postgresql.org/docs/18/config-setting.html
[^layout]: PostgreSQL 18, *Database File Layout*: the data is "stored together within the cluster's data directory, commonly referred to as `PGDATA`"; `base`: "Subdirectory containing per-database subdirectories"; `pg_wal`: "Subdirectory containing WAL (Write Ahead Log) files"; "Each table and index is stored in a separate file." https://www.postgresql.org/docs/18/storage-file-layout.html
[^wal]: PostgreSQL 18, *Write-Ahead Logging*: "changes to data files (where tables and indexes reside) must be written only after those changes have been logged"; "in the event of a crash we will be able to recover the database using the log". https://www.postgresql.org/docs/18/wal-intro.html
[^pgdump]: PostgreSQL 18, *pg_dump*: "pg_dump is a utility for exporting a PostgreSQL database." https://www.postgresql.org/docs/18/app-pgdump.html
[^stats]: PostgreSQL 18, *The Cumulative Statistics System*: `pg_stat_activity`: "One row per server process"; `backend_type` values include `client backend`, `autovacuum launcher`, `checkpointer`, `walwriter`. https://www.postgresql.org/docs/18/monitoring-stats.html
[^ddconnect]: DuckDB 2.0, *Connect*: "DuckDB can operate in both persistent mode, where the data is saved to disk, and in in-memory mode". "In in-memory mode, no data is persisted to disk, therefore, all data is lost when the process finishes." https://duckdb.org/docs/2.0/connect/overview.html
[^ddfiles]: DuckDB 2.0, *Files Created by DuckDB*: `database_filename.wal`, "Write-ahead log file"; "If DuckDB exits normally, the WAL file is deleted upon exit." https://duckdb.org/docs/2.0/operations_manual/footprint_of_duckdb/files_created_by_duckdb.html
[^port]: PostgreSQL 18, *Connection Settings*: `port` "The TCP port the server listens on; 5432 by default." https://www.postgresql.org/docs/18/runtime-config-connection.html
[^clients]: DuckDB 2.0, *Client Overview*: "DuckDB is primarily an in-process database system, and as such, it offers client APIs ("drivers") for several languages." The table lists C, CLI, Java (JDBC), Go, Node.js, ODBC, Python, R, Rust, WebAssembly, ADBC, C#, C++. https://duckdb.org/docs/2.0/clients/overview.html
[^cli]: DuckDB 2.0, *Command Line Client*: "The DuckDB CLI (Command Line Interface) is a single, dependency-free executable." https://duckdb.org/docs/2.0/clients/cli/overview.html
[^txn]: psycopg 3, *Transactions management*: "by default, any database operation will start a new transaction"; in a `with` block "Psycopg will commit the connection at the end of the block" "or roll it back if the block is exited with an exception"; "The manual commit requirement can be suspended using autocommit". (That the connection is closed after the block is shown in the notebook, 5.1.) https://www.psycopg.org/psycopg3/docs/basic/transactions.html
[^l7rand]: PostgreSQL 15 release notes, Migration: "This will cause random()'s results to differ from what was emitted by prior versions, even for the same seed value." https://www.postgresql.org/docs/release/15.0/ (cited in Lecture 7, Part 0).
[^from]: DuckDB 2.0, *FROM and JOIN Clauses*: `SELECT * FROM 'test.csv';` "is implicitly translated to a call of the `read_csv` table function". https://duckdb.org/docs/2.0/sql/query_syntax/from.html
[^csvimport]: DuckDB 2.0, *CSV Import*: options `header` ("First line of each file contains the column names."), `delim`, `columns` ("Using this option disables auto detection of the schema."), `types`, `nullstr` ("Strings that represent a `NULL` value."), `sample_size` (default 20480), `all_varchar`, `dateformat`, `filename`, `union_by_name`. https://duckdb.org/docs/2.0/data/csv/overview.html
[^pqmeta]: DuckDB 2.0, *Querying Parquet Metadata*: "The `parquet_metadata` function can be used to query the metadata contained within a Parquet file"; "The `parquet_schema` function can be used to query the internal schema contained within a Parquet file." https://duckdb.org/docs/2.0/data/parquet/metadata.html
[^readblob]: DuckDB 2.0, *Directly Reading Files*: "The `read_blob` table function reads from the selected source(s) to a `BLOB`"; columns filename, content, size, last_modified. https://duckdb.org/docs/2.0/guides/file_formats/read_file.html
[^utility]: DuckDB 2.0, *Utility Functions*, `glob(search_path)`: returns filenames found at the location "in a single column named `file`." https://duckdb.org/docs/2.0/sql/functions/utility.html
[^describe]: DuckDB 2.0, *Describe*: "To view the schema of the result of a query, prepend `DESCRIBE` to a query." https://duckdb.org/docs/2.0/guides/meta/describe.html
[^explain]: DuckDB 2.0, *EXPLAIN ANALYZE*: "Prepending a query with `EXPLAIN ANALYZE` both pretty-prints the query plan, and executes it". https://duckdb.org/docs/2.0/guides/meta/explain_analyze.html
[^copy2]: DuckDB 2.0, *COPY Statement*: "`COPY ... TO` exports data from DuckDB to an external CSV, Parquet, JSON, or BLOB file." Options FORMAT, PARTITION_BY, OVERWRITE, COMPRESSION (default snappy), ROW_GROUP_SIZE (default 122880). https://duckdb.org/docs/2.0/sql/statements/copy.html
[^attach]: DuckDB 2.0, *ATTACH and DETACH Statements*: "The `ATTACH` statement adds a new database file to the catalog that can be read from and written to."; `DETACH` closes it, "releasing any locks held on the database file." https://duckdb.org/docs/2.0/sql/statements/attach.html
[^ddexcel]: DuckDB 2.0, *Excel Extension*: "Writing `.xlsx` files is supported using the `COPY` statement with `XLSX` given as the format."; "Numeric types are cast to `DOUBLE` when writing to an XLSX file."; types "are inferred based on the first "data" row in the sheet"; "While almost all columns are inferred as either `DOUBLE` or `VARCHAR`"; `header` on write: "Whether to write the column names as the first row in the sheet" (default false); `sheet_row_limit`: "The maximum number of rows in a sheet. An error is thrown if this limit is exceeded." (default 1048576). https://duckdb.org/docs/2.0/core_extensions/excel.html
[^xllimits]: Microsoft Support, *Excel specifications and limits*: "Total number of rows and columns on a worksheet | 1,048,576 rows by 16,384 columns". https://support.microsoft.com/en-us/office/excel-specifications-and-limits-1672b34d-7043-467e-8e27-269d656771c3
[^ooxml]: Microsoft Learn, *Structure of a SpreadsheetML document*: "A separate XML file is created for each worksheet."; "Each of these additional parts is contained within the .zip package of the spreadsheet document."; "To view the .zip package, rename the extension on the minimum spreadsheet from .xlsx to .zip." https://learn.microsoft.com/en-us/office/open-xml/spreadsheet/structure-of-a-spreadsheetml-document
[^ddindex]: DuckDB 2.0, *Indexing* (performance guide): "DuckDB automatically creates zonemaps (also known as min-max indexes) for the columns of all general-purpose data types."; "DuckDB can skip any row group whose min-max range does not contain that filter value"; "The more ordered the data within a column, the more valuable the zonemap indexes will be." https://duckdb.org/docs/2.0/guides/performance/indexing.html
[^ddart]: DuckDB 2.0, *Indexes*: ART indexes "are automatically created for columns with a `UNIQUE` or `PRIMARY KEY` constraint", or with `CREATE INDEX`, mainly "to speed up point and very highly selective (i.e., < 0.1%) queries." https://duckdb.org/docs/2.0/sql/indexes.html
