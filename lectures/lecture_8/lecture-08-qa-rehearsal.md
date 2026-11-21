# Lecture 8 — Q&A Rehearsal: Files and Engines

*Questions students are likely to ask, with a short answer for each. Numbers are from `steps/` (DuckDB 2.0.1, PostgreSQL 18.6); sources are in the notes.*

---

**1. Why not just keep everything in PostgreSQL?**
For the live, shared data, we do. But data arrives as files from other systems, and analysis often runs on a copy. DuckDB can query those files directly, with no load step and no server.

**2. Is Parquet always better than CSV?**
For big data that is read many times, yes: 102 MB vs 357 MB, types kept, and `sum(ordertotal)` in about 13 ms vs 200 ms. CSV is still right for a small file someone will open in Excel or a text editor, or for a system that only reads CSV.

**3. Can I open a Parquet file in Excel?**
Not directly: it's binary. Read it with DuckDB or pandas and export what you need.

**4. Why is the Parquet file so much smaller?**
Each column is stored and compressed on its own, and values of one column look alike: the same few statuses, dates in order. `orderdate` takes almost nothing for that reason.

**5. What is a row group?**
A block of rows, about 120,000 in our file (41 groups). Inside each, every column is a separate chunk, and the footer keeps each chunk's min and max. That's how a June filter reads 2 of 41 row groups.

**5a. Is pgAdmin (or DBeaver) the database?**
No, it's a client, like psql with buttons. The database is the PostgreSQL server; pgAdmin connects to it over the network, like your Python does. Close pgAdmin and the server keeps running.

**5b. Where is "the database" in PostgreSQL? Can I copy it?**
In the server's data directory: `lecture08` alone is 337 files (every table and index is its own file), plus the log and settings. You don't copy those files; you ask the server to export the database (`pg_dump`). A DuckDB database is one file: copy it and you've copied the database.

**5c. Is DuckDB a Python library?**
In Python, yes: `import duckdb`. But DuckDB itself is a database engine. It also has a command-line tool (`duckdb`, one downloadable program, like psql without a server) and clients for R, Java, Node.js and more. In all of them the engine runs inside the program using it.

**6. Is DuckDB a replacement for PostgreSQL?**
No. PostgreSQL is a server for many users who read and write at the same time. DuckDB runs inside one program, for analysis: big scans, files, exports. Most teams use both.

**7. Where does DuckDB keep its data?**
In memory (`duckdb.connect()`), gone when Python exits, or in one file (`duckdb.connect('shop.duckdb')`). Or nowhere: it can query Parquet and CSV files where they are.

**8. Why did I get "Could not set lock on file"?**
Another process (often your notebook) has the `.duckdb` file open for writing. Only one process may write to it. Close the other connection, or open both with `read_only=True`.

**9. Why did DuckDB guess DOUBLE for the totals, not DECIMAL?**
DECIMAL isn't one of its default guesses for a CSV. Anything with a decimal point becomes DOUBLE. For money, always say the type: `types = {'ordertotal': 'DECIMAL(10,2)'}`.

**10. Why does the CSV total change every time I run it?**
A DOUBLE can't store most decimal fractions exactly, so each addition carries a tiny error. DuckDB adds in parallel, in a different order each run, so the errors add up differently. A DECIMAL column gives 3199787987.86 every time.

**11. union_by_name fixed the error. Why is the total wrong?**
It matched columns by name. From July the file calls the total `order_total`, so `ordertotal` is NULL for half the year, and `sum()` skips NULLs. `coalesce(ordertotal, order_total)` fixes it. A count alone didn't show the problem; a sum compared with the source did.

**12. What does `%s` do that an f-string doesn't?**
It sends the value separately from the SQL, so it can never become part of the query. With an f-string, `x' OR '1'='1` turned a name search into "every customer" (30 rows).

**13. Why is employeeID 2.0 in pandas?**
Online orders have no employee (NULL). With NumPy types, a column with a missing value becomes float64. Use `dtype={'employeeID': 'Int64'}`.

**14. Why is 157,078.41 shown as 157078.40999999997 in pandas?**
`read_sql` converts PostgreSQL's exact `NUMERIC` (Python `Decimal`) to float by default. Building the DataFrame from the cursor keeps the Decimals.

**15. Why not fetch everything into pandas and work there?**
Because the database is much faster at it, and your laptop's memory runs out first. 2025's total: 0.14 s in PostgreSQL, 3.4 s fetching 1.9 million rows and summing in Python.

**16. When DuckDB queries `pg.orders_big`, who does the work?**
It depends on the query. `EXPLAIN` shows it: for a simple count and sum, DuckDB sends the SQL to PostgreSQL and gets one row back (a "Postgres Query" node).

**17. Same SQL, different answer in two engines: which is right?**
Both follow their own rules. `sum(quantity) / count(...)` is 2 in PostgreSQL (integer division) and 2.215 in DuckDB. `ORDER BY rating DESC` puts NULLs first in PostgreSQL and last in DuckDB. Write it so it means one thing: `::numeric`, `NULLS LAST`.

**17a. My PostgreSQL total is 3198455015.58, every file says 3199787987.86. Which is right?**
Both, for different data. Your files weren't written from your database. On PostgreSQL 14 the generator gives different order totals (PostgreSQL 15 changed `random()`), with the same counts. Run `setup.sh` against your server, and all rows agree. That's the check doing its job.

**17b. Why does `WHERE orderdate` in June open all 36 month folders, when `month = 6` opens one?**
`year` and `month` come from the folder names; DuckDB can test them before opening any file. It doesn't know that the folder `month=6` holds only June dates, so a filter on `orderdate` means opening every file to read its min/max.

**18. What should I check after moving data from one place to another?**
The row count and a sum of an amount column, compared with the source. Part 7.5 does it for six copies of `orders_big` in one query.
