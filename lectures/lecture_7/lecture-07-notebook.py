import marimo

__generated_with = "0.25.0"
app = marimo.App(width="medium")


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    # Lecture 7 — Performance: EXPLAIN, Indexing, Partitioning

    **Working notebook:** one idea, one demo and one trap per Part, with the diagrams (PNG files in `diagrams/`, drawn by `notebook_tools/diagrams.py`). The notebook's functions live in `notebook_tools/`. Every query is taken from `lecture-07-demo.sql`, where the full lecture runs step by step; details and sources are in `lecture-07-notes.md`. This file is edited by hand: nothing regenerates it.

    **Correctness** questions use the same small shop as Lectures 4–6 (600 orders, 529 completed, completed revenue **157,078.41**). **Speed** questions use two generated tables with the same columns: `orders_big` (**5,000,000** orders over 2023–2025) and `customers_big` (**50,000** customers, 48,000 of whom ordered). On 600 rows every query is instant, so there is nothing to measure.

    > **A performance bug returns the right answer — slowly, or through an index you think it uses. The plan is the only place it shows.**

    **Before you run this:** from the `lecture_7/` folder, run `psql postgres` and `\i steps/00-setup.sql` (about 45 seconds: it drops and recreates the `lecture07` database, loads the small shop, generates the big tables, and pins two planner settings — no parallel query, no JIT — so your plans look like the notes). Then start the notebook with the connection string in `LECTURE07_DSN`, e.g.

    ```
    LECTURE07_DSN=postgresql://postgres:postgres@localhost:5432/lecture07 marimo edit lecture-07-notebook.py
    ```

    **This notebook changes the database as it goes** (it creates and drops indexes and tables), so run it top to bottom; each Part removes what it created. To start over, run the setup script again. Running everything takes a few minutes.

    **Plans, not milliseconds.** Each `EXPLAIN` cell prints the plan and checks its *shape* — node names and whether a condition is an `Index Cond` or a `Filter` — against the reference run (PostgreSQL 18). Timings and buffer counts will differ on your machine; the shape should not. A yellow box means your plan differs: read both, and the notes say why it can (PostgreSQL version, or a step skipped). Needs PostgreSQL 12 or later (for `pg_partition_tree` in Part 8).
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    # Table of contents: built by marimo from every markdown heading below.
    mo.outline(label="Table of contents")
    return


@app.cell
def _():
    import os

    import marimo as mo
    import psycopg

    # All the notebook's functions live in notebook_tools/, next to this file.
    from notebook_tools import diagrams
    from notebook_tools.plans import show_plan
    from notebook_tools.transactions import psql_like

    return diagrams, mo, os, psql_like, psycopg, show_plan


@app.cell
def _(diagrams, mo):
    # Draw the diagrams (notebook_tools/diagrams.py) as PNG files in diagrams/.
    # Only the ones whose drawing changed are redrawn.
    DIAGRAMS = diagrams.render_all(mo.notebook_dir() / "diagrams")
    return (DIAGRAMS,)


@app.cell
def _(os, psql_like, psycopg):
    # One connection for the whole notebook: temporary tables and SET
    # commands made in one cell are seen by the next. Load the data first
    # with psql + steps/00-setup.sql; set LECTURE07_DSN if yours differs.
    engine = psycopg.connect(
        os.environ.get("LECTURE07_DSN", "postgresql://postgres:postgres@localhost:5432/lecture07"),
        autocommit=True,
    )
    # The same connection, for cells with a hand-typed BEGIN ... ROLLBACK:
    # marimo normally sends COMMIT after every cell, tx doesn't.
    tx = psql_like(engine)
    return engine, tx


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Check the data and the settings first.** You should see **30 / 8 / 37 / 600 / 965**, **366 / 965** for the star, and **50,000 / 5,000,000** for the big tables; then **529** completed orders worth **157,078.41**; then `max_parallel_workers_per_gather` **0** and `jit` **off** (pinned by the setup script) and PostgreSQL's defaults for the rest.
    """)
    return


@app.cell
def _(engine, mo):
    p0_01 = mo.sql(
        f"""
        SELECT 'customers' AS t, count(*) FROM customers
        UNION ALL SELECT 'employees',     count(*) FROM employees
        UNION ALL SELECT 'products',      count(*) FROM products
        UNION ALL SELECT 'orders',        count(*) FROM orders
        UNION ALL SELECT 'order_items',   count(*) FROM order_items
        UNION ALL SELECT 'dim_date',      count(*) FROM dim_date
        UNION ALL SELECT 'fact_sales',    count(*) FROM fact_sales
        UNION ALL SELECT 'customers_big', count(*) FROM customers_big
        UNION ALL SELECT 'orders_big',    count(*) FROM orders_big
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    p0_02 = mo.sql(
        f"""
        SELECT count(*) AS completed_orders, sum(orderTotal) AS completed_revenue
        FROM orders
        WHERE status = 'completed'
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    p0_03 = mo.sql(
        f"""
        SELECT name, setting, unit
        FROM pg_settings
        WHERE name IN ('server_version', 'max_parallel_workers_per_gather', 'jit',
                       'shared_buffers', 'work_mem', 'random_page_cost', 'effective_cache_size')
        ORDER BY name
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.accordion({
        "What each setting means": mo.md(r"""
    | Setting | Expected | What it means |
    |---|---|---|
    | `effective_cache_size` | 524288 × 8 kB = **4 GB** (default) | How much memory the **planner assumes** is caching data (PostgreSQL's + the operating system's). Only a hint for choosing plans: no memory is reserved. Larger → indexes look cheaper. |
    | `jit` | **off** (default on; set by the setup script) | Compile parts of a query to machine code before running it. Off, so timings are steadier and plans simpler to read. |
    | `max_parallel_workers_per_gather` | **0** (default 2; set by the setup script) | How many extra processes may help one query step. 0 = one process per query, so plans and timings are the same on every laptop. |
    | `random_page_cost` | **4** (default) | The planner's price for reading one page **out of order** (an index jump), compared with **1** for the next page in order (`seq_page_cost`). Why a full scan can beat an index (Part 4). |
    | `server_version` | 14, 16 or 18 | Your PostgreSQL version. The notes' numbers come from 18. |
    | `shared_buffers` | 16384 × 8 kB = **128 MB** (usual default) | PostgreSQL's own page cache in memory. A page found here is a `shared hit` in `Buffers`; otherwise it's a `read`. |
    | `work_mem` | 4096 kB = **4 MB** (default) | Memory one sort or hash may use before it spills to temporary files on disk. |

    <small>Source: PostgreSQL 18 documentation, [Resource Consumption](https://www.postgresql.org/docs/18/runtime-config-resource.html) (`shared_buffers`: "the default is typically 128 megabytes"; `work_mem`; `max_parallel_workers_per_gather`), [Query Planning](https://www.postgresql.org/docs/18/runtime-config-query.html) (`random_page_cost`, `seq_page_cost`, `jit`; `effective_cache_size`: "a higher value makes it more likely index scans will be used … has no effect on the size of shared memory allocated by PostgreSQL"). Other defaults checked with `pg_settings.boot_val`.</small>
    """)
    })
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 1 — Reading a plan

    Before PostgreSQL runs a query, it makes a **plan**: which tables to read, in which order, and how (the whole table, or through an index).

    **New terms**

    - [`EXPLAIN`](https://www.postgresql.org/docs/18/sql-explain.html): shows the plan PostgreSQL chose for a query, with its **estimates**. Doesn't run the query.
    - `EXPLAIN ANALYZE`: also **runs** the query, and adds what really happened: real row counts and times.
    - `BUFFERS`: adds how many **pages** each step read.
    - **page**: the 8 kB block PostgreSQL reads and writes. A table is a sequence of pages; a page holds many rows.
    """)
    return


@app.cell
def _(DIAGRAMS, mo):
    mo.image(DIAGRAMS["query-path-simple"])
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Predict, then run:** "all orders of customer 4242" (Nane Simonyan). How much of the 5-million-row table will PostgreSQL read to find her orders?
    """)
    return


@app.cell(hide_code=True)
def _(engine, mo):
    _df = mo.sql(
        f"""
        -- ANALYZE orders_big;
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, show_plan):
    show_plan(
        engine,
        """
        EXPLAIN (ANALYZE, BUFFERS)
        SELECT * FROM orders_big WHERE customerID = 4242
        """,
        rollback=False,
        reference=['  0 Seq Scan on orders_big', '  2   Filter'],
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    How to read it:

    - **`Seq Scan`** (sequential scan): read the whole table, page by page, in order.
    - **`cost=0.00..122239.00`**: the planner's **estimated** effort, in its own units (not milliseconds): before the first row .. for all rows. Only useful to compare plans of the same query.
    - **`rows=97.00`** (in `actual …`): what really came out. The `rows=` inside `(cost=…)` is the planner's **estimate**, made before running (about 100). Close estimates mean a well-informed plan.
    - **`actual time=…`**: real milliseconds, first row .. last row.
    - **`Filter`**: a condition checked on every row read. **`Rows Removed by Filter: 4999903`**: it read 5 million rows to return 97.
    - **`Buffers: shared hit + read = 59,739`**: every page of the table. **`shared hit`**: the page was already in PostgreSQL's memory; **`read`**: it had to be fetched from the operating system (disk, or the OS's own cache). Pages are the fairest measure of work: they don't depend on how fast your laptop is.

    <small>Docs: [Using EXPLAIN](https://www.postgresql.org/docs/18/using-explain.html).</small>

    A plan is a **tree**. The most indented step runs first and passes its rows up.
    """)
    return


@app.cell
def _():
    # mo.image(DIAGRAMS["plan-tree"])
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### The hazard: `EXPLAIN ANALYZE` really runs the statement

    On a scratch copy of the small `orders` table (600 rows), "just checking the plan" of a `DELETE`:

    **New term:** [`CREATE TEMP TABLE … AS SELECT …`](https://www.postgresql.org/docs/18/sql-createtableas.html): a **temporary** table, filled with the query's rows. Only this connection sees it, and it disappears when the connection closes: safe for experiments.
    """)
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        CREATE TEMP TABLE orders_copy AS SELECT * FROM orders
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, show_plan):
    show_plan(
        engine,
        """
        EXPLAIN ANALYZE
        DELETE FROM orders_copy WHERE status = 'cancelled'
        """,
        rollback=False,
        reference=['  0 Delete on orders_copy', '  2 Seq Scan on orders_copy', '  8   Filter'],
    )
    return


@app.cell
def _(engine, mo):
    p1_04 = mo.sql(
        f"""
        SELECT count(*) AS rows_after FROM orders_copy
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **573**: the 27 cancelled orders are gone.

    ### The safe way: inside a transaction, then `ROLLBACK`

    Same idea, but worse: the plan of deleting **every** row. Wrapped in `BEGIN` … `ROLLBACK`, it runs, and then is undone. Run the next five cells in order, the same lines you would type in psql.

    #### What is a transaction?

    A **transaction** is a group of SQL statements that PostgreSQL treats as **one** operation: **all or nothing**. Either every change in it is kept, or none is.

    The classic example, a bank transfer: take 100 from Anna's account, add 100 to Aram's. If the second step fails, the first must not stay. In one transaction, it can't.

    | Command | What it does |
    |---|---|
    | [`BEGIN`](https://www.postgresql.org/docs/18/sql-begin.html) | Starts a transaction. Changes from now on are **pending**: only you see them. |
    | [`COMMIT`](https://www.postgresql.org/docs/18/sql-commit.html) | Ends it and **keeps** every change. Now everyone sees them, all at once. |
    | [`ROLLBACK`](https://www.postgresql.org/docs/18/sql-rollback.html) | Ends it and **undoes** every change since `BEGIN`, as if nothing happened. |

    Good to know:

    - **Without `BEGIN`**, every statement is its own small transaction, committed automatically when it succeeds ("autocommit"). That's how you've worked so far: each `INSERT` or `DELETE` was final the moment it ran.
    - **An error inside a transaction** spoils it: PostgreSQL refuses further statements ("current transaction is aborted") until you send `ROLLBACK`.
    - `SAVEPOINT name` marks a point inside a transaction; `ROLLBACK TO name` undoes only back to that point. (We won't need it.)

    Here we use `ROLLBACK` as an **undo button**: run the `DELETE` for real, look at its plan, then take it back.

    <small>Source: PostgreSQL 18 documentation, [Transactions](https://www.postgresql.org/docs/18/tutorial-transactions.html): "bundles multiple steps into a single, all-or-nothing operation"; changes are "invisible to other transactions until the transaction completes"; "If you do not issue a BEGIN command, then each individual statement has an implicit BEGIN and (if successful) COMMIT wrapped around it."</small>

    (These cells use `engine=tx` instead of `engine=engine`: marimo normally sends a `COMMIT` after every cell, which would make the `BEGIN` useless. With `tx`, only the `COMMIT` or `ROLLBACK` you type counts.)
    """)
    return


@app.cell
def _(mo, tx):
    _df = mo.sql(
        f"""
        BEGIN
        """,
        engine=tx
    )
    return


@app.cell
def _(mo, tx):
    _df = mo.sql(
        f"""
        EXPLAIN ANALYZE
        DELETE FROM orders_copy
        """,
        engine=tx
    )
    return


@app.cell
def _(mo, tx):
    _df = mo.sql(
        f"""
        SELECT count(*) AS rows_inside_transaction FROM orders_copy
        """,
        engine=tx
    )
    return


@app.cell
def _(mo, tx):
    _df = mo.sql(
        f"""
        ROLLBACK
        """,
        engine=tx
    )
    return


@app.cell
def _(mo, tx):
    _df = mo.sql(
        f"""
        SELECT count(*) AS rows_after_rollback FROM orders_copy
        """,
        engine=tx
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **0** inside the transaction: the `DELETE` really ran. **573** after `ROLLBACK`: undone. So to look at the plan of an `INSERT`, `UPDATE` or `DELETE`, always `BEGIN; EXPLAIN ANALYZE …; ROLLBACK;`. Plain `EXPLAIN` (without `ANALYZE`) never runs anything.

    If you stop after `BEGIN`, the transaction stays open, and the next ordinary cell (`engine=engine`) commits it.

    **One timing proves nothing:** the first run is often slower (data not in memory yet). Run three times and compare plans and pages, not milliseconds.
    """)
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        DROP TABLE orders_copy
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 2 — How a table is stored on disk

    Why does a query cost what it costs? Because of how the rows sit on disk.
    """)
    return


@app.cell
def _(DIAGRAMS, mo):
    mo.image(DIAGRAMS["latency-simple"])
    return


@app.cell
def _(DIAGRAMS, mo):
    mo.image(DIAGRAMS["storage-simple"])
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### Where is the table?

    A table is an ordinary file on the server's disk. PostgreSQL can tell us which one.

    **New terms** (built-in functions)

    - [`current_setting('…')`](https://www.postgresql.org/docs/18/functions-admin.html#FUNCTIONS-ADMIN-SET): reads one server setting, e.g. `data_directory` (the server's data folder) or `block_size` (the page size).
    - [`pg_relation_filepath('table')`](https://www.postgresql.org/docs/18/functions-admin.html#FUNCTIONS-ADMIN-DBLOCATION): the table's file, inside the data folder.
    - [`pg_stat_file('path')`](https://www.postgresql.org/docs/18/functions-admin.html#FUNCTIONS-ADMIN-GENFILE): facts about a file on the server's disk, such as its `size`. Only a **superuser** (a database user allowed to do everything, like `postgres`) may call it.
    - [`pg_relation_size('table')`](https://www.postgresql.org/docs/18/functions-admin.html#FUNCTIONS-ADMIN-DBOBJECT): the table's size in bytes, as PostgreSQL counts it.
    - [`pg_size_pretty(bytes)`](https://www.postgresql.org/docs/18/functions-admin.html#FUNCTIONS-ADMIN-DBOBJECT): turns bytes into readable text: `489381888` → `467 MB`.
    """)
    return


@app.cell
def _(engine, mo):
    p2_01 = mo.sql(
        f"""
        SELECT current_setting('data_directory') AS data_folder,
               pg_relation_filepath('orders_big') AS table_file,
               pg_size_pretty((pg_stat_file(pg_relation_filepath('orders_big'))).size) AS file_size_on_disk
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    - **`data_folder`**: where this PostgreSQL server keeps all its data.
    - **`table_file`**: the file of `orders_big` inside it: `base/<database number>/<file number>`. The numbers are just names, and differ on every machine.
    - **`file_size_on_disk`**: the size of that file, read from the disk itself (467 MB).

    `pg_stat_file` reads files on the server, so it needs a superuser (we connect as `postgres`). A table over 1 GB continues in a second file, `<file number>.1`, and so on.

    And each **row** has an address inside that file.

    **New term:** [`ctid`](https://www.postgresql.org/docs/18/ddl-system-columns.html): a hidden column every table has: the row's address, (page number, slot in the page).
    """)
    return


@app.cell
def _(engine, mo):
    p2_02 = mo.sql(
        f"""
        SELECT ctid::text AS address, orderID, orderDate, customerID, orderTotal
        FROM orders_big
        WHERE orderID IN (1, 2, 3, 84, 85, 86)
        ORDER BY orderID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The rows were loaded in `orderID` order, so orders 1–84 fill page 0, and order 85 starts page 1 at slot 1. Pages are numbered from 0.

    **More about `ctid`:**

    - **Hidden.** Every table has it, but `SELECT *` doesn't show it: you must name it, as above.
    - **The fastest way to a row.** `(85, 3)` means: jump to page 85 of the file, take slot 3. No searching.
    - **This is what an index stores.** An index is a sorted list of *value → ctid*: "customer 4242 → (page, slot), (page, slot), …". Finding a row through an index = look up the value, then jump to its ctid (Parts 4–5).
    - **It's an address, not an ID.** An `UPDATE` writes a new version of the row in a new place, so the `ctid` changes (next section). `VACUUM FULL` moves every row. So never use `ctid` to identify a row: that's what the **primary key** (`orderID`) is for.

    <small>Sources: PostgreSQL 18 documentation, [Database File Layout](https://www.postgresql.org/docs/18/storage-file-layout.html), [System Columns](https://www.postgresql.org/docs/18/ddl-system-columns.html) (`ctid`: "the physical location of the row version within its table … will change if it is updated or moved by VACUUM FULL … should not be used as a row identifier"), [Index Access Methods](https://www.postgresql.org/docs/18/indexam.html) ("an index is effectively a mapping from some data key values to tuple identifiers, or TIDs"; "a TID consists of a block number and an item number within that block"), [pg_relation_filepath](https://www.postgresql.org/docs/18/functions-admin.html#FUNCTIONS-ADMIN-DBLOCATION), [pg_stat_file](https://www.postgresql.org/docs/18/functions-admin.html#FUNCTIONS-ADMIN-GENFILE).</small>
    """)
    return


@app.cell
def _(engine, mo):
    p2_03 = mo.sql(
        f"""
        SELECT current_setting('block_size') AS page_bytes,
               pg_relation_size('orders_big') AS file_bytes,
               pg_relation_size('orders_big') / current_setting('block_size')::int AS pages,
               round(count(*) / (pg_relation_size('orders_big') / 8192.0), 1) AS rows_per_page
        FROM orders_big
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **59,739 pages × 8,192 bytes = the whole file.** Every row has an address, (page, slot), so the question for any query is: *how many different pages hold the rows I need?*

    The next query counts pages with `(ctid::text::point)[0]`: a trick that turns the address `(85,3)` into a point and takes its first number, the **page**.
    """)
    return


@app.cell
def _(engine, mo):
    p2_05 = mo.sql(
        f"""
        SELECT 'Nane (customer 4242)' AS rows_of, count(*) AS rows,
               count(DISTINCT (ctid::text::point)[0]) AS pages
        FROM orders_big WHERE customerID = 4242
        UNION ALL
        SELECT 'one day (2025-06-15)', count(*),
               count(DISTINCT (ctid::text::point)[0])
        FROM orders_big WHERE orderDate = '2025-06-15'
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Nane's orders are spread over three years, one per page. One day's orders sit together. **50 times the rows, on fewer pages.** Part 4 shows how this decides which plan is fastest.

    ### Rows, not columns

    PostgreSQL stores each row's columns together. So what does it cost to add up **one** column?

    **New term:** [`pg_column_size(value)`](https://www.postgresql.org/docs/18/functions-admin.html#FUNCTIONS-ADMIN-DBOBJECT): how many bytes one value takes on disk.
    """)
    return


@app.cell
def _(engine, mo):
    p2_12 = mo.sql(
        f"""
        SELECT pg_size_pretty(sum(pg_column_size(orderTotal))) AS ordertotal_bytes,
               pg_size_pretty(pg_relation_size('orders_big')) AS table_bytes
        FROM orders_big
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The totals are **33 MB**, but they are spread over every page, so `sum(orderTotal)` reads all **467 MB**. That's right for "show me one order" and wrong for "sum one column over millions of rows": the reason the next lectures use **column stores** (Parquet, DuckDB).
    """)
    return


@app.cell
def _(DIAGRAMS, mo):
    mo.image(DIAGRAMS["row-vs-col"])
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### `UPDATE` and `DELETE` leave the old rows behind
    """)
    return


@app.cell
def _(DIAGRAMS, mo):
    mo.image(DIAGRAMS["mvcc-simple"])
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **New term:** [**dead row**](https://www.postgresql.org/docs/18/routine-vacuuming.html): an old copy left behind by `UPDATE` or `DELETE`. No query sees it any more, but it still takes space in its page.

    The trap, on a copy of 2023 (1,371,464 orders). "Archive" January to November:
    """)
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        CREATE TABLE orders_2023 AS
        SELECT * FROM orders_big WHERE orderDate < '2024-01-01'
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    p2_19 = mo.sql(
        f"""
        SELECT count(*) AS rows, pg_size_pretty(pg_relation_size('orders_2023')) AS size,
               pg_relation_size('orders_2023') / 8192 AS pages
        FROM orders_2023
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        DELETE FROM orders_2023 WHERE orderDate < '2023-12-01'
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    p2_20 = mo.sql(
        f"""
        SELECT count(*) AS rows, pg_size_pretty(pg_relation_size('orders_2023')) AS size,
               pg_relation_size('orders_2023') / 8192 AS pages
        FROM orders_2023
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **90% of the rows deleted, and the file is still 128 MB**: a full scan still reads every page of it. The `DELETE` worked and the counts are right: only the size tells you.

    ### Getting the space back: `VACUUM`, then `VACUUM FULL`

    **New terms**

    - [`VACUUM`](https://www.postgresql.org/docs/18/sql-vacuum.html): cleans a table: frees the space of its dead rows, so **new rows of the same table** can reuse it. The table stays usable while it runs. PostgreSQL also runs it by itself in the background (**autovacuum**).
    - `VACUUM FULL`: rewrites the table into a **new, compact file** and deletes the old one. Gives the space back to the disk, but **locks** the table: nobody can read or write it until it's done.

    First, plain `VACUUM`:
    """)
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        VACUUM orders_2023
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        SELECT count(*) AS rows, pg_size_pretty(pg_relation_size('orders_2023')) AS size,
               pg_relation_filepath('orders_2023') AS file
        FROM orders_2023
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Still 128 MB.** `VACUUM` frees the space *inside* the file, for new rows of this table to reuse; it doesn't give it back to the disk. (It can only cut off empty pages at the very end of the file, and here the December rows we kept are at the end.)

    To really shrink the file: `VACUUM FULL`. Note the file name above, then:
    """)
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        VACUUM FULL orders_2023
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        SELECT count(*) AS rows, pg_size_pretty(pg_relation_size('orders_2023')) AS size,
               pg_relation_filepath('orders_2023') AS file
        FROM orders_2023
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **13 MB, and a different file name:** the same 135,984 rows, 10 times smaller. The price: while it copies, `VACUUM FULL` locks the table completely (no reads, no writes), and it needs disk space for both copies. If you delete old data by date every month, the better answer is partitions you can simply drop (Part 8).

    <small>Source: PostgreSQL 18 documentation, [VACUUM](https://www.postgresql.org/docs/18/sql-vacuum.html): plain VACUUM — "extra space is not returned to the operating system (in most cases); it's just kept available for re-use within the same table"; VACUUM FULL — "rewrites the entire contents of the table into a new disk file … requires an ACCESS EXCLUSIVE lock … requires extra disk space".</small>
    """)
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        DROP TABLE orders_2023
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 3 — Statistics: where the estimates come from
    """)
    return


@app.cell
def _(DIAGRAMS, mo):
    mo.image(DIAGRAMS["stats-simple"])
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **New terms**

    - [**statistics**](https://www.postgresql.org/docs/18/planner-stats.html): PostgreSQL's summary of each table: how many rows, and per column how many distinct values and the most common ones. The planner's estimates come from here.
    - [`ANALYZE table`](https://www.postgresql.org/docs/18/sql-analyze.html): reads a random sample of the table and **refreshes** its statistics. Not the same as `EXPLAIN ANALYZE`, which runs one query. PostgreSQL also runs it by itself in the background, but not right after a big load.
    - [`setseed(0.7)`](https://www.postgresql.org/docs/18/functions-math.html#FUNCTIONS-MATH-RANDOM-TABLE): makes `random()` give the same "random" numbers on every run, so everyone gets the same fake data.

    **The trap.** January 2026 arrives: 200,000 new orders in one `INSERT`, and nobody runs `ANALYZE`. Then the monthly report by city (the next two cells only generate the fake January orders):
    """)
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        SELECT setseed(0.7)
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        INSERT INTO orders_big
        SELECT 5000000 + i,
               c + (c - 1) / 24,
               CASE WHEN online THEN NULL ELSE 1 + floor(random() * 8)::int END,
               DATE '2026-01-01' + floor(random() * 31)::int,
               TIME '08:00' + floor(random() * 50400) * INTERVAL '1 second',
               CASE WHEN online THEN 'online' ELSE 'in_store' END,
               'card',
               'completed',
               NULL,
               NULL,
               round((15 + 2500 * random() ^ 3)::numeric, 2)
        FROM (SELECT i, 1 + floor(random() * 48000)::int AS c, random() < 0.33 AS online
              FROM generate_series(1, 200000) AS i) AS s
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, show_plan):
    show_plan(
        engine,
        """
        EXPLAIN ANALYZE
        SELECT c.city, count(*) AS orders, sum(o.orderTotal) AS revenue
        FROM orders_big o
        JOIN customers_big c ON c.customerID = o.customerID
        WHERE o.orderDate >= '2026-01-01'
        GROUP BY c.city
        """,
        rollback=False,
        reference=['  0 GroupAggregate', '  2 Sort', '  8 Nested Loop', ' 14 Seq Scan on orders_big o', ' 20   Filter', ' 14 Index Scan using customers_big_pkey on customers_big c', ' 20   Index Cond'],
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Compare the scan's estimated rows (a few hundred) with the actual **200,000**. Everything above was planned for the wrong number: a **Nested Loop** doing 200,000 separate lookups, and a sort that ran out of memory and went to disk. The report is still correct. **No error.**

    **New terms** (plan steps)

    - [`Nested Loop`](https://www.postgresql.org/docs/18/planner-optimizer.html): a join that, for **each** row on one side, looks up the matching rows on the other. Fast for a few rows, slow for many.
    - `Sort Method: external merge  Disk: …`: the sort needed more memory than `work_mem` allows, so it wrote to temporary files on disk.

    **The fix:** refresh the summary, and ask again:
    """)
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        ANALYZE orders_big
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, show_plan):
    show_plan(
        engine,
        """
        EXPLAIN ANALYZE
        SELECT c.city, count(*) AS orders, sum(o.orderTotal) AS revenue
        FROM orders_big o
        JOIN customers_big c ON c.customerID = o.customerID
        WHERE o.orderDate >= '2026-01-01'
        GROUP BY c.city
        """,
        rollback=False,
        reference=['  0 HashAggregate', '  2 Hash Join', '  8   Hash Cond', '  8 Seq Scan on orders_big o', ' 14   Filter', '  8 Hash', ' 14 Seq Scan on customers_big c'],
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Now about 200,000 expected, and a different plan: a **Hash Join** and a **HashAggregate**. It read **62,831** pages instead of **662,011** and ran about **1.7 times faster** (median of 3 runs). Same four rows.

    **New terms** (plan steps)

    - [`Hash Join`](https://www.postgresql.org/docs/18/planner-optimizer.html): reads one side **once** into an in-memory lookup table (a hash table), then streams the other side through it. Good for many rows.
    - `HashAggregate`: does a `GROUP BY` with a hash table, one entry per group, without sorting first.
    - [`VACUUM ANALYZE`](https://www.postgresql.org/docs/18/sql-vacuum.html) (the clean-up cells below): `VACUUM` and `ANALYZE` in one command.

    **Rule:** find the step where estimated and actual rows differ by 10× or more. That's where the plan went wrong. After a big load, run `ANALYZE`.
    """)
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        DELETE FROM orders_big WHERE orderID > 5000000
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        VACUUM ANALYZE orders_big
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 4 — Full scan or index?

    ### What an index is
    """)
    return


@app.cell
def _(DIAGRAMS, mo):
    mo.image(DIAGRAMS["index-simple"])
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Reading through an index means two jumps: in the index, find the value; then, for each address found, read that row's page in the table. Few rows: few pages, fast. Many rows spread over the whole table: you end up reading most pages anyway, **plus** the index. So PostgreSQL chooses between two ways to read a table:

    | Plan step | What it does | Chosen when |
    |---|---|---|
    | `Seq Scan` | read every page, in order | the query needs a large share of the table |
    | `Index Scan` | look up the index, then fetch each row | few rows |

    **New terms**

    - [`CREATE INDEX name ON table (column)`](https://www.postgresql.org/docs/18/sql-createindex.html): builds an index. By default a **B-tree**: the sorted, tree-shaped list in the diagram above. [`DROP INDEX`](https://www.postgresql.org/docs/18/sql-dropindex.html) deletes it (`IF EXISTS`: no error if it isn't there).
    - `Index Scan`: the plan step that reads through an index.
    - `Index Cond`: a condition the index **answers** (it finds the matching entries directly). Compare `Filter`, checked row by row.
    - `Aggregate`: the plan step that computes `count`, `sum`, … from the rows coming up from below.

    Two indexes for this Part, then two queries: one needs 0.1% of the rows, the other 92%. **Predict each plan before you run it.**
    """)
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        DROP INDEX IF EXISTS orders_big_orderdate_idx, orders_big_status_idx
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        CREATE INDEX orders_big_orderdate_idx ON orders_big (orderDate)
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        CREATE INDEX orders_big_status_idx ON orders_big (status)
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, show_plan):
    show_plan(
        engine,
        """
        EXPLAIN (ANALYZE, BUFFERS)
        SELECT count(*), sum(orderTotal) FROM orders_big WHERE orderDate = '2025-06-15'
        """,
        rollback=False,
        reference=['  0 Aggregate', '  2 Index Scan using orders_big_orderdate_idx on orders_big', '  8   Index Cond'],
    )
    return


@app.cell
def _(engine, show_plan):
    show_plan(
        engine,
        """
        EXPLAIN (ANALYZE, BUFFERS)
        SELECT count(*), sum(orderTotal) FROM orders_big WHERE status = 'completed'
        """,
        rollback=False,
        reference=['  0 Aggregate', '  2 Seq Scan on orders_big', '  8   Filter'],
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    - **One day (0.1%):** `Index Scan`, about 70 pages instead of 59,739. The day's rows sit together (Part 2).
    - **Completed (92%):** `Seq Scan`, with the index right there. That's **right**: forced through the index, the same query reads more pages (63,674) and is no faster.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Don't teach yourself "always add an index". Teach yourself "read the plan".**
    """)
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        DROP INDEX orders_big_orderdate_idx, orders_big_status_idx
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 5 — What an index buys, and what it costs

    An index is a sorted copy of one column with each row's address, like the index at the back of a book. Nane's orders again, now with an index on `customerID`:
    """)
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        DROP INDEX IF EXISTS orders_big_customerid_idx, orders_big_ordertotal_idx
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        CREATE INDEX orders_big_customerid_idx ON orders_big (customerID)
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, show_plan):
    show_plan(
        engine,
        """
        EXPLAIN (ANALYZE, BUFFERS)
        SELECT * FROM orders_big WHERE customerID = 4242
        """,
        rollback=False,
        reference=['  0 Bitmap Heap Scan on orders_big', '  2   Recheck Cond', '  2 Bitmap Index Scan on orders_big_customerid_idx', '  8   Index Cond'],
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    About **100 pages instead of 59,739**: from **128 ms to 0.04 ms** (medians on the reference laptop). The same 97 rows.

    **New terms** (plan steps)

    - [`Bitmap Index Scan` + `Bitmap Heap Scan`](https://www.postgresql.org/docs/18/indexes-bitmap-scans.html): another way to read through an index. First collect **all** matching addresses from the index and sort them by page; then read each of those pages once, in file order. PostgreSQL picks it when there are more than a few rows. (**Heap** = PostgreSQL's word for the table's file.)
    - `Recheck Cond`: the condition checked again on the rows of each page read.

    **The bill:** an index takes disk space…

    **New term:** [`pg_class`](https://www.postgresql.org/docs/18/catalog-pg-class.html): PostgreSQL's built-in list of every table and index, one row each: `relname` = name, `relkind` = kind (`r` table, `i` index, `p` partitioned table), `oid` = internal number.
    """)
    return


@app.cell
def _(engine, mo):
    p5_01 = mo.sql(
        f"""
        SELECT c.relname AS name,
               CASE c.relkind WHEN 'r' THEN 'table' ELSE 'index' END AS kind,
               pg_size_pretty(pg_relation_size(c.oid)) AS size
        FROM pg_class c
        WHERE c.relname IN ('orders_big', 'orders_big_pkey', 'orders_big_customerid_idx')
        ORDER BY pg_relation_size(c.oid) DESC
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Each index is **its own file**, next to the table's file (same query as in Part 2, now for the indexes too):
    """)
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        SELECT c.relname AS name,
               CASE c.relkind WHEN 'r' THEN 'table' ELSE 'index' END AS kind,
               current_setting('data_directory') AS data_folder,
               pg_relation_filepath(c.oid) AS file,
               pg_size_pretty((pg_stat_file(pg_relation_filepath(c.oid))).size) AS size_on_disk
        FROM pg_class c
        WHERE c.relname IN ('orders_big', 'orders_big_pkey', 'orders_big_customerid_idx')
        ORDER BY c.relkind DESC, c.relname
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Three files in the same folder, `base/<database number>/`: the table, the primary key's index (PostgreSQL creates it with every `PRIMARY KEY`), and the index we just made. `DROP INDEX` deletes the index's file; the table's file is not touched.

    <small>Sources: PostgreSQL 18 documentation, [Database File Layout](https://www.postgresql.org/docs/18/storage-file-layout.html) ("each table and index is stored in a separate file"), [Constraints: Primary Keys](https://www.postgresql.org/docs/18/ddl-constraints.html#DDL-CONSTRAINTS-PRIMARY-KEYS) ("adding a primary key will automatically create a unique B-tree index on the column or group of columns listed in the primary key").</small>
    """)
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        DROP INDEX IF EXISTS orders_big_customerid_idx, orders_big_ordertotal_idx
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    …and **every** `INSERT`, `UPDATE` and `DELETE` must update every index. Loading 1,000,000 rows took **2.6 times** as long with one index and **8.5 times** with five. Add the indexes your queries need, not one per column.

    An index is also already **sorted**: "the 10 biggest orders" with an index on `orderTotal` reads a handful of pages instead of sorting 5 million rows.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 6 — An index on two columns: order matters

    **New term:** [**composite** (multicolumn) **index**](https://www.postgresql.org/docs/18/indexes-multicolumn.html): one index on several columns, `ON orders_big (customerID, orderDate)`: sorted by the first column, then by the second within each value of the first, like a phone book (last name, then first name).
    """)
    return


@app.cell
def _(DIAGRAMS, mo):
    mo.image(DIAGRAMS["composite"])
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        DROP INDEX IF EXISTS orders_big_cust_date_idx, orders_big_orderdate_idx,
                             orders_big_returned_idx, orders_big_customerid_idx,
                             orders_big_cust_incl_idx, customers_big_lower_email_idx
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        CREATE INDEX orders_big_cust_date_idx ON orders_big (customerID, orderDate)
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, show_plan):
    show_plan(
        engine,
        """
        EXPLAIN (ANALYZE, BUFFERS)
        SELECT * FROM orders_big WHERE customerID = 4242 AND orderDate >= '2025-01-01'
        """,
        rollback=False,
        reference=['  0 Bitmap Heap Scan on orders_big', '  2   Recheck Cond', '  2 Bitmap Index Scan on orders_big_cust_date_idx', '  8   Index Cond'],
    )
    return


@app.cell
def _(engine, show_plan):
    show_plan(
        engine,
        """
        EXPLAIN (ANALYZE, BUFFERS)
        SELECT * FROM orders_big WHERE orderDate = '2025-12-01'
        """,
        rollback=False,
        reference=['  0 Bitmap Heap Scan on orders_big', '  2   Recheck Cond', '  2 Bitmap Index Scan on orders_big_cust_date_idx', '  8   Index Cond'],
    )
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        DROP INDEX IF EXISTS orders_big_cust_date_idx, orders_big_orderdate_idx,
                             orders_big_returned_idx, orders_big_customerid_idx,
                             orders_big_cust_incl_idx, customers_big_lower_email_idx
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Both plans name the same index. Look at the pages: **3 index pages** for Nane, **13,539** (the whole index) for one day. The second column only helps once the first is fixed.

    Three more kinds, in one line each (details in the notes):

    - **Partial index**: only some rows (`… WHERE status = 'returned'`): small, used only when the query has the same condition.
    - **Covering index** (`INCLUDE`): carries extra columns so the query never touches the table.
    - **Expression index**: indexes a computed value such as `lower(email)`; the query must use the same expression.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 7 — Traps: the index exists, but isn't used

    The most common performance bug for an analyst: the index is there, and the way the query is **written** keeps it from being used.
    """)
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        DROP INDEX IF EXISTS orders_big_orderdate_idx, orders_big_customerid_idx,
                             orders_big_month_idx, orders_big_deliverydate_idx,
                             customers_big_email_pattern_idx
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        CREATE INDEX orders_big_orderdate_idx ON orders_big (orderDate)
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        CREATE INDEX orders_big_customerid_idx ON orders_big (customerID)
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### Trap 1: a function on the column

    "Revenue for June 2025", written the natural way, and then as a date range:

    **New term:** [`date_trunc('month', date)`](https://www.postgresql.org/docs/18/functions-datetime.html#FUNCTIONS-DATETIME-TRUNC): cuts a date down to the start of its month: `2025-06-17` → `2025-06-01`.
    """)
    return


@app.cell
def _(engine, show_plan):
    show_plan(
        engine,
        """
        EXPLAIN (ANALYZE, BUFFERS)
        SELECT count(*), sum(orderTotal) FROM orders_big
        WHERE date_trunc('month', orderDate) = '2025-06-01'
        """,
        rollback=False,
        reference=['  0 Aggregate', '  2 Seq Scan on orders_big', '  8   Filter'],
    )
    return


@app.cell
def _(engine, show_plan):
    show_plan(
        engine,
        """
        EXPLAIN (ANALYZE, BUFFERS)
        SELECT count(*), sum(orderTotal) FROM orders_big
        WHERE orderDate >= '2025-06-01' AND orderDate < '2025-07-01'
        """,
        rollback=False,
        reference=['  0 Aggregate', '  2 Index Scan using orders_big_orderdate_idx on orders_big', '  8   Index Cond'],
    )
    return


@app.cell
def _(DIAGRAMS, mo):
    mo.image(DIAGRAMS["function"])
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### Trap 2: the wrong type

    `customerID` is an integer. Compare `4242.0` with `'4242'`:
    """)
    return


@app.cell
def _(engine, show_plan):
    show_plan(
        engine,
        """
        EXPLAIN (ANALYZE, BUFFERS)
        SELECT count(*) FROM orders_big WHERE customerID = 4242.0
        """,
        rollback=False,
        reference=['  0 Aggregate', '  2 Index Only Scan using orders_big_customerid_idx on orders_big', '  8   Filter'],
    )
    return


@app.cell
def _(engine, show_plan):
    show_plan(
        engine,
        """
        EXPLAIN (ANALYZE, BUFFERS)
        SELECT count(*) FROM orders_big WHERE customerID = '4242'
        """,
        rollback=False,
        reference=['  0 Aggregate', '  2 Index Only Scan using orders_big_customerid_idx on orders_big', '  8   Index Cond'],
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    With `4242.0` every one of the 5 million index entries is converted to a decimal and checked: the plan says `Filter`, not `Index Cond`. `'4242'` is fine: the value is converted once, to the column's type. **Change the value, never the column.**

    **New term:** [`Index Only Scan`](https://www.postgresql.org/docs/18/indexes-index-only-scans.html) (in both plans): the answer comes from the index alone, without reading the table: `count(*)` needs nothing but `customerID`, which the index already holds.

    ### Trap 3: `LIKE` with a leading wildcard

    `email LIKE '%@yahoo.com'` can never use an ordinary index: a sorted list has no place to start for "ends with". (`LIKE 'nane%'`, "starts with", can, with the right index; see the notes.)

    **After any rewrite, prove the answer didn't change:** the same count, and `EXCEPT ALL` both ways returning 0 rows.
    """)
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        DROP INDEX IF EXISTS orders_big_orderdate_idx, orders_big_customerid_idx,
                             orders_big_month_idx, orders_big_deliverydate_idx,
                             customers_big_email_pattern_idx
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 8 — Partitioning

    A **partitioned** table is one table to your queries, stored as several tables, here one per year. (Not the same as Lecture 6's `OVER (PARTITION BY …)`, which only groups rows for a window function.)

    **New terms**

    - [`CREATE TABLE … (LIKE orders_big INCLUDING DEFAULTS INCLUDING CONSTRAINTS)`](https://www.postgresql.org/docs/18/sql-createtable.html): a new, empty table with the same columns as `orders_big`, plus their default values and checks.
    - [`PARTITION BY RANGE (orderDate)`](https://www.postgresql.org/docs/18/ddl-partitioning.html): makes it a **partitioned table**, split by ranges of `orderDate`.
    - `CREATE TABLE … PARTITION OF … FOR VALUES FROM (a) TO (b)`: one **partition**: an ordinary table that holds the rows with `a <= orderDate < b`.
    - **pruning**: when the `WHERE` names the partition key, PostgreSQL skips the partitions that can't match.

    Built from the same 5,000,000 orders (the `INSERT` takes a few seconds):
    """)
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        DROP TABLE IF EXISTS orders_big_part, orders_big_daily
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        CREATE TABLE orders_big_part (LIKE orders_big INCLUDING DEFAULTS INCLUDING CONSTRAINTS)
            PARTITION BY RANGE (orderDate)
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        CREATE TABLE orders_big_part_2023 PARTITION OF orders_big_part
            FOR VALUES FROM ('2023-01-01') TO ('2024-01-01')
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        CREATE TABLE orders_big_part_2024 PARTITION OF orders_big_part
            FOR VALUES FROM ('2024-01-01') TO ('2025-01-01')
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        CREATE TABLE orders_big_part_2025 PARTITION OF orders_big_part
            FOR VALUES FROM ('2025-01-01') TO ('2026-01-01')
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        INSERT INTO orders_big_part SELECT * FROM orders_big
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        VACUUM ANALYZE orders_big_part
        """,
        engine=engine
    )
    return


@app.cell
def _(DIAGRAMS, mo):
    mo.image(DIAGRAMS["partition"])
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### Where is it on disk?

    The big table, the partitioned table, and each partition.

    **New terms:** [`pg_partition_tree('table')`](https://www.postgresql.org/docs/18/functions-admin.html#FUNCTIONS-INFO-PARTITION) lists a partitioned table and its partitions; [`pg_get_expr(relpartbound, oid)`](https://www.postgresql.org/docs/18/functions-info.html) shows a partition's range as text (`relpartbound` is where `pg_class` stores it).
    """)
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        SELECT c.relname AS name,
               CASE c.relkind WHEN 'p' THEN 'partitioned table' ELSE 'table' END AS kind,
               pg_get_expr(c.relpartbound, c.oid) AS holds,
               pg_relation_filepath(c.oid) AS file,
               pg_size_pretty((pg_stat_file(pg_relation_filepath(c.oid))).size) AS size_on_disk
        FROM pg_class c
        WHERE c.relname = 'orders_big'
           OR c.oid IN (SELECT relid FROM pg_partition_tree('orders_big_part'))
        ORDER BY c.relname
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    - **`orders_big`**: one file, 467 MB.
    - **`orders_big_part`**: **no file at all** (empty `file`). The partitioned table only holds the rules; it stores no rows.
    - **Each partition**: its own file, with the date range it `holds`: 128 + 162 + 177 MB, together exactly the 467 MB of `orders_big`. The same rows, cut into three files.

    **Pruning** (next) means: PostgreSQL reads only the file of the year your `WHERE` asks for. **Dropping a year** means: deleting one file.

    <small>Sources: PostgreSQL 18 documentation, [Table Partitioning](https://www.postgresql.org/docs/18/ddl-partitioning.html) ("The partitioned table itself is a 'virtual' table having no storage of its own. Instead, the storage belongs to partitions, which are otherwise-ordinary tables associated with the partitioned table."); [pg_partition_tree](https://www.postgresql.org/docs/18/functions-admin.html#FUNCTIONS-INFO-PARTITION) ("Lists the tables or indexes in the partition tree of the given partitioned table … with one row for each partition"). Sizes measured on a copy of `orders_big`.</small>
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Pruning:** June 2025 reads only the 2025 partition:
    """)
    return


@app.cell
def _(engine, show_plan):
    show_plan(
        engine,
        """
        EXPLAIN (ANALYZE, BUFFERS)
        SELECT count(*), sum(orderTotal) FROM orders_big_part
        WHERE orderDate >= '2025-06-01' AND orderDate < '2025-07-01'
        """,
        rollback=False,
        reference=['  0 Aggregate', '  2 Seq Scan on orders_big_part_2025 orders_big_part', '  8   Filter'],
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **The trap:** a filter on an expression of the date (Part 7 again) can't be pruned. All three years are read.

    **New term:** `Append` (plan step): reads several partitions one after another and passes all their rows up, as one table.
    """)
    return


@app.cell
def _(engine, show_plan):
    show_plan(
        engine,
        """
        EXPLAIN (ANALYZE, BUFFERS)
        SELECT count(*), sum(orderTotal) FROM orders_big_part
        WHERE extract(year FROM orderDate) = 2025
        """,
        rollback=False,
        reference=['  0 Aggregate', '  2 Append', '  8 Seq Scan on orders_big_part_2023 orders_big_part_1', ' 14   Filter', '  8 Seq Scan on orders_big_part_2024 orders_big_part_2', ' 14   Filter', '  8 Seq Scan on orders_big_part_2025 orders_big_part_3', ' 14   Filter'],
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **What partitioning really buys:** removing a whole year is `DROP TABLE` on one partition, **16 ms**, instead of deleting 1.37 million rows, **609 ms**, which also leaves dead rows behind (Part 2). It is about **maintenance** of very large, time-based tables, not a general speed-up: at 5 million rows, indexes did everything faster.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 9 — Index, partition, or neither?

    The final comparison: one question, **June 2025's revenue** (155,419 orders, 3% of the table), asked in four setups. **Predict the pages for each before you run it.**
    """)
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        DROP INDEX IF EXISTS orders_big_orderdate_idx
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **1. Neither:** the plain table, no index.
    """)
    return


@app.cell
def _(engine, show_plan):
    show_plan(
        engine,
        """
        EXPLAIN (ANALYZE, BUFFERS)
        SELECT count(*), sum(orderTotal) FROM orders_big
        WHERE orderDate >= '2025-06-01' AND orderDate < '2025-07-01'
        """,
        rollback=False,
        reference=['  0 Aggregate', '  2 Seq Scan on orders_big', '  8   Filter'],
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **2. Index, no partitioning:** a B-tree index on `orderDate` (B-tree is what `CREATE INDEX` makes by default).
    """)
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        CREATE INDEX orders_big_orderdate_idx ON orders_big (orderDate)
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, show_plan):
    show_plan(
        engine,
        """
        EXPLAIN (ANALYZE, BUFFERS)
        SELECT count(*), sum(orderTotal) FROM orders_big
        WHERE orderDate >= '2025-06-01' AND orderDate < '2025-07-01'
        """,
        rollback=False,
        reference=['  0 Aggregate', '  2 Index Scan using orders_big_orderdate_idx on orders_big', '  8   Index Cond'],
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **3. Partitioning, no index:** the partitioned table from Part 8.
    """)
    return


@app.cell
def _(engine, show_plan):
    show_plan(
        engine,
        """
        EXPLAIN (ANALYZE, BUFFERS)
        SELECT count(*), sum(orderTotal) FROM orders_big_part
        WHERE orderDate >= '2025-06-01' AND orderDate < '2025-07-01'
        """,
        rollback=False,
        reference=['  0 Aggregate', '  2 Seq Scan on orders_big_part_2025 orders_big_part', '  8   Filter'],
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **4. Both:** one `CREATE INDEX` on the partitioned table makes a separate index in each partition (note the name in the plan: `orders_big_part_2025_orderdate_idx`).
    """)
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        CREATE INDEX orders_big_part_orderdate_idx ON orders_big_part (orderDate)
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, show_plan):
    show_plan(
        engine,
        """
        EXPLAIN (ANALYZE, BUFFERS)
        SELECT count(*), sum(orderTotal) FROM orders_big_part
        WHERE orderDate >= '2025-06-01' AND orderDate < '2025-07-01'
        """,
        rollback=False,
        reference=['  0 Aggregate', '  2 Index Scan using orders_big_part_2025_orderdate_idx on orders_big_part_2025 orders_big_part', '  8   Index Cond'],
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    | Setup | Plan | Pages read | Time |
    |---|---|---:|---:|
    | 1. Neither | `Seq Scan` on the whole table | 59,739 | ~250 ms |
    | 2. Index | `Index Scan` | **1,995** | **~24 ms** |
    | 3. Partitioning | `Seq Scan` on the 2025 partition only | 22,644 | ~95 ms |
    | 4. Both | `Index Scan` in the 2025 partition | **1,994** | **~24 ms** |

    <small>PostgreSQL 18, fresh setup; time = median of 3 runs on the reference laptop. Your times differ; the pages shouldn't.</small>

    - **Partitioning alone** skips 2023 and 2024, but still reads all of 2025 to find June: 2.6× fewer pages.
    - **The index alone** goes straight to June: **30× fewer pages**, 10× faster.
    - **Both** = the index. Partitioning adds nothing for this question.

    So for reading, the **index** does the work. Partitioning earns its place in **maintenance** of very large, time-based tables: dropping a year in milliseconds (Part 8).
    """)
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        DROP INDEX orders_big_orderdate_idx
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    _df = mo.sql(
        f"""
        DROP TABLE orders_big_part
        """,
        engine=engine
    )
    return


@app.cell
def _():
    # mo.image(DIAGRAMS["decision"])
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Why all of this matters

    Almost every trap today returned the **right answer**: a plan built on a stale summary, an index the query couldn't use, a "deleted" table that stayed just as big. Performance bugs are the quietest bugs. The checks:

    - **Read the plan** before and after a change: the step names, `Index Cond` vs `Filter`, and the pages.
    - **Compare estimated and actual rows.** The first 10× gap, from the bottom, is where the plan went wrong.
    - **Run `ANALYZE`** after big loads.
    - **Prove a rewrite didn't change the answer:** same count, `EXCEPT ALL` both ways = 0.
    - **Measure three runs, not one.**

    An AI assistant will happily say "add an index on that column". Only the plan tells you whether it helps.
    """)
    return


if __name__ == "__main__":
    app.run()
