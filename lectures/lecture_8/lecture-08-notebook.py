import marimo

__generated_with = "0.25.0"
app = marimo.App(width="medium")


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    # Lecture 8 — Files and Engines: Parquet, DuckDB, Python

    **Working notebook.** The queries come from `steps/`, where every one is annotated with its real output; the notes (`lecture-08-notes.md`) have the details and sources. The diagrams are PNG files in `diagrams/`, drawn by `notebook_tools/diagrams.py`.

    > **A file doesn't know its own types, and two engines don't always agree. The totals you already know are the check.**

    **Before you run this**, from the `lecture_8/` folder:

    1. `LECTURE08_DSN=postgresql://postgres:postgres@localhost:5432/lecture08 marimo edit lecture-08-notebook.py`
    2. click **Create lecture08** below, or run `./setup.sh` in a terminal. Either one runs `steps/00-setup.sql` with psql (about 45 seconds: the small shop and `orders_big`, 5,000,000 orders, the same rows as Lecture 7; it **drops** `lecture08` first) and `steps/00-make-files.py` (about 15 seconds: the CSV and Parquet files in `files/`). Needs `psql` on your PATH.

    The SQL cells run on **DuckDB** (`engine=duck_db`) unless they say otherwise. Run the notebook top to bottom: Parts 3, 4 and 6 write files that later Parts read.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.outline(label="Table of contents")
    return


@app.cell(hide_code=True)
def _(mo):
    mo.accordion({
        "New words in this lecture (click to open)": mo.md(r"""
        **Storage and files (Parts 1–2)**

        - **Row-based storage**: a table saved one whole row after another (CSV, PostgreSQL). Good for "show me this order".
        - **Column-based (columnar) storage**: one whole column after another (Parquet). Good for "sum one column over millions of rows".
        - **Parquet**: a column-based file format that stores each column's type and compresses each column.
        - **Row group**: a block of rows inside a Parquet file (about 120,000 here); inside it, each column is a **column chunk**.
        - **Footer (metadata)**: the end of a Parquet file: column names, types, and the **min / max** of every column chunk.
        - **Type guessing (auto-detection)**: a CSV is only text, so every reader guesses each column's type from a sample of rows.
        - **DOUBLE vs DECIMAL**: DOUBLE is an approximate number (tiny rounding errors); DECIMAL(10,2) is exact. Money is DECIMAL.
        - **.xlsx (Excel)**: a zip of XML files; at most 1,048,576 rows per sheet, and no column types (numbers come back as DOUBLE).

        **Engines (Part 3)**

        - **Database server**: a program that is always running (PostgreSQL); other programs connect to it.
        - **Client**: anything that connects to a server: psql, pgAdmin, DBeaver, your Python.
        - **Connection string (DSN)**: where the server is and who you are: `postgresql://user:password@host:port/database`.
        - **Host / port**: the machine the server runs on / which program on that machine (PostgreSQL: 5432).
        - **Data directory**: the server's folder of files (hundreds of them) that only the server touches.
        - **DuckDB**: a database engine that runs **inside** the program using it (in-process): no server. In Python, a library; also a command-line tool (CLI).
        - **CLI**: command-line interface, a program you type commands into, like `psql` or `duckdb`.
        - **Index vs zonemap**: an index (PostgreSQL) points to the page holding a row; a zonemap (DuckDB, automatic) is the min / max of a column per row group, used to skip row groups.

        **Working with files (Part 4)**

        - **Glob**: a file-name pattern: `*.csv` = every CSV file in the folder.
        - **Schema**: the list of a table's columns and their types.
        - **Partitioning (Hive-style)**: one folder per value, named `key=value`: `year=2025/month=6/`.
        - **Pruning**: skipping folders or row groups that can't contain the rows a filter asks for.
        - **Pushdown**: doing the work as early as possible: reading only the needed columns, applying filters while reading.

        **Python (Part 5)**

        - **psycopg**: the Python package that connects to PostgreSQL.
        - **Cursor**: the object that runs SQL and fetches the result (`execute`, `fetchone`, `fetchall`).
        - **Parameter / placeholder**: `%s` in the SQL; the value is sent separately, so it can't change the query.
        - **SQL injection**: text pasted into SQL that changes what the query does.
        - **DataFrame**: a table inside Python (pandas, polars).

        **Putting it together (Parts 6–8)**

        - **ATTACH**: making another database (a DuckDB file, or PostgreSQL) usable from DuckDB, as `name.table`.
        - **Pipeline**: a repeatable job in steps: **extract** (copy data out of the source), **transform** (build the result), **check** (prove nothing was lost).
        - **.env**: a file with credentials (host, user, password), read by the program and never committed to git.
        - **Logging**: timestamped messages about what a program did, to the screen and a log file, instead of `print`.
        - **Matching totals**: after every move of data, the row count and a sum compared with the source.
        """),
    })
    return


@app.cell
def _():
    import os
    import subprocess
    import sys
    import time
    import warnings

    import duckdb
    import marimo as mo
    import pandas as pd
    import polars as pl
    import psycopg

    from notebook_tools import diagrams
    from notebook_tools.files import clean_class_files, list_files

    # Every path in this notebook (files/..., data/...) is relative to lecture_8/.
    os.chdir(mo.notebook_dir())
    DSN = os.environ.get("LECTURE08_DSN", "postgresql://postgres:postgres@localhost:5432/lecture08")

    # DuckDB, in memory, inside this Python process. The SQL cells use it (engine=duck_db).
    duck_db = duckdb.connect()
    return (
        DSN,
        clean_class_files,
        diagrams,
        duck_db,
        duckdb,
        list_files,
        mo,
        os,
        pd,
        pl,
        psycopg,
        subprocess,
        sys,
        time,
        warnings,
    )


@app.cell
def _(mo):
    setup_button = mo.ui.run_button(label="Create lecture08 and files/ (runs setup.sh, about a minute)")
    setup_button
    return (setup_button,)


@app.cell
def _(DSN, mo, os, setup_button, subprocess, sys):
    # Runs setup.sh: psql steps/00-setup.sql (DROPS and recreates lecture08), then
    # steps/00-make-files.py. Only when the button is clicked.
    if setup_button.value:
        _r = subprocess.run(["bash", "setup.sh"], capture_output=True, text=True,
                            env={**os.environ, "LECTURE08_DSN": DSN, "PYTHON": sys.executable})
        _out = mo.plain_text(_r.stdout[-3000:] + _r.stderr[-3000:] + f"\nexit code {_r.returncode}")
    else:
        _out = mo.md("*Click the button above to (re)create `lecture08` and `files/`. "
                     "Skip it if you've already run `./setup.sh`.*")
    setup_done = setup_button.value      # cells that use PostgreSQL re-run after a setup
    _out
    return (setup_done,)


@app.cell
def _(DSN, psycopg, setup_done):
    # One PostgreSQL connection for the whole notebook, made automatically when the
    # notebook runs (and made again after the setup button recreates lecture08).
    _ = setup_done
    pg_conn = psycopg.connect(DSN, autocommit=True)
    return (pg_conn,)


@app.cell
def _(mo):
    clean_button = mo.ui.run_button(label="Clean the files written in class (to show the writing steps again)")
    clean_button
    return (clean_button,)


@app.cell
def _(clean_button, clean_class_files, mo):
    # Deletes only what Parts 4, 6 and 8 write (see CLASS_FILES in notebook_tools/files.py),
    # never the files setup.sh made.
    if clean_button.value:
        _out = mo.md("Deleted: " + (", ".join(f"`{f}`" for f in clean_class_files()) or "nothing to delete"))
    else:
        _out = mo.md("*Click to delete `files/by_month/`, `files/orders_2025.parquet`, "
                     "`files/shop_orders.parquet` and the Parquet files in `pipeline/data/`.*")
    _out
    return


@app.cell
def _(diagrams, mo):
    # Draw the diagrams as PNG files in diagrams/ (only the ones that changed).
    DIAGRAMS = diagrams.render_all(mo.notebook_dir() / "diagrams")
    return (DIAGRAMS,)


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 1 — Row vs column storage

    A table is a grid, but a file is one long line of bytes, so the grid has to be laid out in some order.

    - **Row-based** (CSV, PostgreSQL): one whole row, then the next. Good for "show me order 4890168": all its columns are in one place.
    - **Column-based** (Parquet): all of one column, then the next. Good for "sum one column over 5 million rows": that column is in one place.

    Lecture 7, 2.7: in PostgreSQL, `sum(orderTotal)` read the whole of `orders_big`: 59,739 pages of 8 kB.
    """)
    return


@app.cell
def _(DIAGRAMS, mo):
    mo.image(DIAGRAMS["row-vs-col"])
    return


@app.cell
def _(DIAGRAMS, mo):
    mo.image(DIAGRAMS["parquet"])
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 1.1 A file is a table

    No `CREATE TABLE`, no load: DuckDB queries the file where it is. Same count and total as PostgreSQL.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.accordion({
        "DuckDB: FROM 'file.parquet' and read_parquet()": mo.md(r"""

        `SELECT ... FROM 'files/orders_big.parquet'` reads the file directly: "If your file ends in `.parquet`, the function syntax is optional."
        It's the same as `FROM read_parquet('files/orders_big.parquet')`. Write the function when you need its options:

        | Option | What it does |
        |---|---|
        | `hive_partitioning` | read `key=value` folder names as columns (auto-detected; Part 4) |
        | `union_by_name` | match columns of many files by name, not by position |
        | `filename` | add a column with the file each row came from |

        A list or a glob reads many files as one table: `read_parquet(['a.parquet', 'b.parquet'])`, `'files/by_month/*/*/*.parquet'`.
        *Source: DuckDB 2.0, Reading and Writing Parquet Files.*
        """),
    })
    return


@app.cell
def _(duck_db, mo):
    _df = mo.sql(
        f"""
        SELECT count(*) AS orders, sum(ordertotal) AS total
        FROM 'files/orders_big.parquet'
        """,
        engine=duck_db
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 1.2 Row groups and column chunks

    The file is cut into **row groups**; inside each, every column is stored on its own (a **column chunk**). `ordertotal` is 22 MB of the 102 MB file; `orderdate` is almost nothing (the file is in date order, so long runs of one date compress to almost nothing).
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.accordion({
        'DuckDB: parquet_metadata() and parquet_schema()': mo.md(r"""

        `parquet_metadata('file.parquet')` reads only the footer and returns **one row per column chunk**: `row_group_id`, `row_group_num_rows`, `path_in_schema` (the column), `stats_min`, `stats_max`, `compression`, `total_compressed_size`, … The data itself is not read.
        `parquet_schema('file.parquet')` returns the column types as Parquet stores them. To just see names and types, `DESCRIBE` is easier.
        *Source: DuckDB 2.0, Querying Parquet Metadata.*
        """),
    })
    return


@app.cell
def _(duck_db, mo):
    _df = mo.sql(
        f"""
        SELECT count(DISTINCT row_group_id) AS row_groups,
               min(row_group_num_rows)      AS smallest,
               max(row_group_num_rows)      AS largest
        FROM parquet_metadata('files/orders_big.parquet')
        """,
        engine=duck_db
    )
    return


@app.cell(hide_code=True)
def _(duck_db, mo):
    _df = mo.sql(
        f"""
        select * from 'files/orders_big.parquet' limit 10;
        """,
        engine=duck_db
    )
    return


@app.cell(hide_code=True)
def _(duck_db, mo):
    _df = mo.sql(
        f"""
        SELECT row_group_id, path_in_schema, stats_min, stats_max
        FROM parquet_metadata('files/orders_big.parquet')
        WHERE path_in_schema = 'orderid';
        """,
        engine=duck_db
    )
    return


@app.cell
def _(duck_db, mo):
    _df = mo.sql(
        f"""
        SELECT path_in_schema                             AS column_name,
               round(sum(total_compressed_size) / 1e6, 1) AS mb
        FROM parquet_metadata('files/orders_big.parquet')
        GROUP BY path_in_schema
        ORDER BY min(column_id)
        """,
        engine=duck_db
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 1.3 Sum one column, read one column

    DuckDB on Parquet: look for **Data Read** at the top of the plan, about 22 MB, the `ordertotal` chunks only. Then the same question in PostgreSQL: **Buffers** counts 8 kB pages, `hit` (in memory) + `read` (from disk) = 59,739 pages × 8,192 bytes = 489 MB, the whole table. (Lecture 7 printed it as 467 MB: `pg_size_pretty` counts 1 MB = 1,048,576 bytes. This lecture uses 1 MB = 1,000,000 bytes, like DuckDB.)
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.accordion({
        "DuckDB: EXPLAIN ANALYZE (and PostgreSQL's)": mo.md(r"""

        `EXPLAIN ANALYZE <query>` "both pretty-prints the query plan, and executes it", with times and row counts per step. DuckDB adds a summary: **Total Time** and **Data Read**. Inside the scan step, **Row Groups Scanned** shows how many were skipped.
        PostgreSQL's `EXPLAIN (ANALYZE, BUFFERS)` (Lecture 7) counts **pages** of 8 kB instead: `Buffers: shared hit=…` (found in memory) `read=…` (from disk).
        Both really run the query.
        *Source: DuckDB 2.0, EXPLAIN ANALYZE; PostgreSQL 18, EXPLAIN.*
        """),
    })
    return


@app.cell
def _(duck_db, mo):
    mo.plain_text(duck_db.execute("""
        EXPLAIN ANALYZE
        SELECT sum(ordertotal) FROM 'files/orders_big.parquet'
    """).fetchall()[0][1])
    return


@app.cell
def _(mo, pg_conn):
    # The same question in PostgreSQL. Buffers: pages of 8 kB, hit + read.
    mo.plain_text("\n".join(r[0] for r in pg_conn.execute("""
        EXPLAIN (ANALYZE, BUFFERS)
        SELECT sum(orderTotal) FROM orders_big
    """)))
    return


@app.cell
def _():
    59739 * 8 / 1000
    return


@app.cell
def _():
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 1.4 Min / max: skipping row groups

    The footer keeps the smallest and largest value of every column chunk. A June 2025 filter skips every row group whose dates can't contain June 2025: **Row Groups Scanned: 2 / 41**. PostgreSQL, with no index on `orderDate`, reads every page and throws most rows away (`Rows Removed by Filter`).
    """)
    return


@app.cell
def _(duck_db, mo):
    _df = mo.sql(
        f"""
        SELECT row_group_id, stats_min AS min_date, stats_max AS max_date
        FROM parquet_metadata('files/orders_big.parquet')
        WHERE path_in_schema = 'orderdate'
        ORDER BY row_group_id
        LIMIT 3
        """,
        engine=duck_db
    )
    return


@app.cell
def _(duck_db, mo):
    mo.plain_text(duck_db.execute("""
        EXPLAIN ANALYZE
        SELECT count(*), sum(ordertotal)
        FROM 'files/orders_big.parquet'
        WHERE orderdate >= DATE '2025-06-01' AND orderdate < DATE '2025-07-01'
    """).fetchall()[0][1])
    return


@app.cell
def _(mo, pg_conn):
    mo.plain_text("\n".join(r[0] for r in pg_conn.execute("""
        EXPLAIN (ANALYZE, BUFFERS)
        SELECT count(*), sum(orderTotal) FROM orders_big
        WHERE orderDate >= DATE '2025-06-01' AND orderDate < DATE '2025-07-01'
    """)))
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 2 — Parquet vs CSV (and Excel): size, types, speed

    ### 2.1 Size

    Compare like with like: a **file** with a file (CSV vs Parquet), a **database** with a database (PostgreSQL vs DuckDB). PostgreSQL's table is not comparable with a CSV: a database keeps more than the data (pages, an index).
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.accordion({
        'DuckDB: read_blob()': mo.md(r"""

        `read_blob('path')` reads files as raw bytes and returns one row per file: `filename`, `content`, `size` (bytes), `last_modified`. Here only `size` is used: a way to list file sizes from SQL. Takes a file name, a list, or a glob.
        *Source: DuckDB 2.0, Directly Reading Files.*
        """),
    })
    return


@app.cell
def _(DIAGRAMS, mo):
    mo.image(DIAGRAMS["formats"])
    return


@app.cell
def _(duck_db, mo):
    _df = mo.sql(
        f"""
        -- two files with the same 5,000,000 orders
        SELECT filename, round(size / 1e6, 1) AS mb
        FROM read_blob(['files/orders_big.csv', 'files/orders_big.parquet'])
        """,
        engine=duck_db
    )
    return


@app.cell
def _(os, pd, pg_conn):
    # Two databases with the same table: PostgreSQL's orders_big, and the DuckDB
    # database file files/shop.duckdb (00-make-files.py wrote it).
    _table, _index = pg_conn.execute(
        "SELECT pg_relation_size('orders_big'), pg_indexes_size('orders_big')").fetchone()
    pd.DataFrame([
        {"database": "PostgreSQL: orders_big table", "mb": round(_table / 1e6, 1)},
        {"database": "PostgreSQL: its primary-key index", "mb": round(_index / 1e6, 1)},
        {"database": "DuckDB: files/shop.duckdb (the whole file)",
         "mb": round(os.path.getsize("files/shop.duckdb") / 1e6, 1)},
    ])
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 2.2 Types

    A CSV is text, so DuckDB **guesses** each column's type from a sample: `ordertotal` becomes `DOUBLE`. The Parquet file **stores** the types: `DECIMAL(10,2)`, as PostgreSQL had it.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.accordion({
        'DuckDB: read_csv(), and why not just the file name': mo.md(r"""

        `FROM 'file.csv'` is short for `FROM read_csv('file.csv')` with every setting **guessed** ("auto-detected"): the delimiter, whether there is a header, and each column's type, from a sample of the rows.
        Write `read_csv(...)` when the guess isn't good enough:

        | Option | What it does | Default |
        |---|---|---|
        | `header` | first line has the column names | detected |
        | `delim` (`sep`) | the separator: `','`, `';'`, `'\t'` | detected |
        | `types` | the type of some columns, by name: `types = {'ordertotal': 'DECIMAL(10,2)'}` (Part 7.1) | guessed |
        | `columns` | names **and** types of all columns; switches detection off | — |
        | `nullstr` | text that means NULL: `nullstr = 'n/a'` (Part 7.2) | empty field |
        | `sample_size` | rows used to guess; `-1` = all | 20,480 |
        | `all_varchar` | read every column as text | false |
        | `dateformat` | e.g. `'%d/%m/%Y'` | detected |
        | `union_by_name`, `filename` | for many files (Part 4) | false |

        *Source: DuckDB 2.0, CSV Import; FROM and JOIN Clauses.*
        """),
        'DuckDB: DESCRIBE': mo.md(r"""

        `DESCRIBE <table>` or `DESCRIBE <query>` lists the column names and types (and whether NULL is allowed) without returning the data: "To view the schema of the result of a query, prepend `DESCRIBE` to a query."
        *Source: DuckDB 2.0, Describe.*
        """),
    })
    return


@app.cell
def _(duck_db, mo):
    _df = mo.sql(
        f"""
        DESCRIBE SELECT * FROM 'files/orders_big.csv'
        """,
        engine=duck_db
    )
    return


@app.cell
def _(duck_db, mo):
    _df = mo.sql(
        f"""
        DESCRIBE SELECT * FROM 'files/orders_big.parquet'
        """,
        engine=duck_db
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 2.3 Speed

    The same three questions on each file, median of 3 runs. Your times will differ; the gap won't.
    """)
    return


@app.cell
def _(duck_db, pd, time):
    def median_ms(sql):
        times = []
        for _ in range(3):
            start = time.perf_counter()
            duck_db.execute(sql).fetchall()
            times.append((time.perf_counter() - start) * 1000)
        return round(sorted(times)[1])

    _questions = {
        "count(*)": "SELECT count(*) FROM '{f}'",
        "sum(ordertotal)": "SELECT sum(ordertotal) FROM '{f}'",
        "one order": "SELECT * FROM '{f}' WHERE orderid = 4890168",
    }
    pd.DataFrame([
        {"question": q,
         "CSV (ms)": median_ms(sql.format(f="files/orders_big.csv")),
         "Parquet (ms)": median_ms(sql.format(f="files/orders_big.parquet"))}
        for q, sql in _questions.items()
    ])
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 2.4 And Excel?

    Analysts get a lot of data as `.xlsx`. Three things to know:

    - **Rows:** a worksheet holds at most **1,048,576 rows**. Our 5,000,000 orders don't fit (last cell below).
    - **Types:** Excel cells have no column type. DuckDB writes every number as a `DOUBLE`, and reading guesses types from the **first data row**, so ids and money come back as `DOUBLE`, and a column that's empty in the first row can get the wrong type.
    - **Size and speed:** an `.xlsx` file is a zip of XML text files: smaller than CSV, but slow to write and read.

    So, the same month in three formats: June 2025, 155,419 orders.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.accordion({
        "DuckDB: the excel extension (read_xlsx, COPY ... TO 'file.xlsx')": mo.md(r"""
        `INSTALL excel; LOAD excel;` once (it downloads the first time). Then:

        - **read:** `FROM 'file.xlsx'`, or `read_xlsx('file.xlsx', sheet = 'Sheet1', header = true)` for options. Types are "inferred based on the first "data" row in the sheet", and "almost all columns are inferred as either `DOUBLE` or `VARCHAR`".
        - **write:** `COPY (query) TO 'file.xlsx' (FORMAT xlsx, HEADER true)`. `HEADER` (write the column names) is **false** by default. "Numeric types are cast to `DOUBLE` when writing to an XLSX file."
        - **row limit:** `sheet_row_limit` (default 1,048,576): "An error is thrown if this limit is exceeded."

        *Sources: DuckDB 2.0, Excel Extension; Microsoft, Excel specifications and limits: "1,048,576 rows by 16,384 columns".*
        """),
    })
    return


@app.cell
def _(duck_db, os, pd, time):
    # June 2025 written as CSV, Parquet and Excel, then read back: count(*) and sum(ordertotal).
    duck_db.execute("INSTALL excel")
    duck_db.execute("LOAD excel")
    _june = """SELECT * FROM 'files/orders_big.parquet'
               WHERE orderdate >= DATE '2025-06-01' AND orderdate < DATE '2025-07-01'"""
    _formats = {
        "CSV":     ("files/june_2025.csv",     "FORMAT csv",              "'files/june_2025.csv'"),
        "Parquet": ("files/june_2025.parquet", "FORMAT parquet",          "'files/june_2025.parquet'"),
        "Excel":   ("files/june_2025.xlsx",    "FORMAT xlsx, HEADER true", "read_xlsx('files/june_2025.xlsx')"),
    }
    _rows = []
    for _name, (_path, _options, _source) in _formats.items():
        _t = time.perf_counter()
        duck_db.execute(f"COPY ({_june}) TO '{_path}' ({_options})").fetchall()
        _write = time.perf_counter() - _t
        _t = time.perf_counter()
        _n, _total, _type = duck_db.execute(
            f"SELECT count(*), sum(ordertotal)::VARCHAR, typeof(any_value(ordertotal)) FROM {_source}").fetchall()[0]
        _rows.append({"format": _name, "mb": round(os.path.getsize(_path) / 1e6, 1),
                      "write s": round(_write, 2), "read s": round(time.perf_counter() - _t, 3),
                      "orders": _n, "total": _total, "ordertotal is": _type})
    excel_written = True
    pd.DataFrame(_rows)
    return (excel_written,)


@app.cell
def _(duck_db, excel_written, mo):
    _ = excel_written
    _df = mo.sql(
        f"""
        -- What came back from Excel: ids and money as DOUBLE; deliverydate is empty
        -- in the first row (an in-store order), so it isn't even a DATE any more
        DESCRIBE FROM read_xlsx('files/june_2025.xlsx')
        """,
        engine=duck_db
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **All 5,000,000 orders into one sheet.** This error is on purpose: DuckDB stops at the row limit. (It takes about 10 seconds: it writes a million rows before it gives up.)
    """)
    return


@app.cell
def _(duck_db, duckdb, excel_written, mo, os):
    _ = excel_written
    try:
        duck_db.execute("""COPY (FROM 'files/orders_big.parquet')
                           TO 'files/orders_big.xlsx' (FORMAT xlsx, HEADER true)""").fetchall()
        _out = mo.md("No error?")
    except duckdb.Error as _e:
        _out = mo.callout(mo.md(f"**The error, on purpose:**\n```text\n{str(_e)[:400]}\n```"), kind="warn")
    if os.path.exists("files/orders_big.xlsx"):          # don't leave a half-written file behind
        os.remove("files/orders_big.xlsx")
    _out
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 3 — A database server, and a database in a file

    ### 3.1 PostgreSQL is a server

    Everything so far ran on PostgreSQL. It is a **server**: a program that is always running. psql, pgAdmin or DBeaver, your Python and the shop's website are all **clients**: they connect over the network, with a user and password, and send it SQL. Each connection gets its own server process. The data sits in the server's **data directory**, hundreds of files that only the server touches.

    **What it is for:** many people and programs reading and writing the same data at the same time, safely, all day.

    **A connection string says where the server is and who you are.** Ours:

    ```
    postgresql://postgres:postgres@localhost:5432/lecture08
    └─ kind ──┘  └ user ┘ └ pass ┘ └─ host ─┘ └port┘ └ database ┘
    ```

    | Part | Here | Means |
    |---|---|---|
    | `postgresql://` | | talk to a PostgreSQL server |
    | user, password | `postgres`, `postgres` | who you are; the server checks it (`pg_hba.conf`) |
    | host | `localhost` | the machine the server runs on: this computer. A company server would be a name like `db.example.com` |
    | port | `5432` | which program on that machine: PostgreSQL's usual port |
    | database | `lecture08` | one of the server's databases (`postgres`, `lecture08`, …) |

    A DuckDB "connection string" is just a file name: `duckdb.connect("files/shop.duckdb")`. No host, no port, no password.
    """)
    return


@app.cell
def _(DSN, psycopg):
    # Your connection string, taken apart by psycopg.
    psycopg.conninfo.conninfo_to_dict(DSN)
    return


@app.cell
def _(DIAGRAMS, mo):
    mo.image(DIAGRAMS["postgres"])
    return


@app.cell
def _(DSN, psycopg):
    # The data directory, the files of this one database, and the server's processes.
    # (pg_ls_dir needs a superuser: the Docker setup's postgres user is one.)
    _a = psycopg.connect(DSN, autocommit=True)
    _b = psycopg.connect(DSN, autocommit=True)          # a second client, like a second psql
    print(_a.execute("SHOW data_directory").fetchone()[0])
    print([r[0] for r in _a.execute("SELECT name FROM pg_ls_dir('.') AS name ORDER BY name")])
    print(_a.execute("""
        SELECT count(*) AS files, pg_size_pretty(sum((pg_stat_file(d.dir || '/' || f)).size))
        FROM (SELECT 'base/' || oid AS dir FROM pg_database WHERE datname = current_database()) AS d,
             pg_ls_dir(d.dir) AS f
    """).fetchone())
    for _row in _a.execute("SELECT pid, backend_type FROM pg_stat_activity ORDER BY backend_type, pid"):
        print(_row)
    _a.close()
    _b.close()
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 3.2 DuckDB: the database in your program, in one file

    DuckDB is a **database engine** that runs **inside the program that uses it** ("primarily an in-process database system"), not as a server. You use it two ways:

    - **from a terminal:** the DuckDB **CLI**, "a single, dependency-free executable": download it, run `duckdb files/shop.duckdb`, type SQL (like `psql`, but with no server behind it);
    - **from a program:** in Python it's a library, `import duckdb`; there are clients for R, Java, Node.js, Go, Rust, C/C++ and more.

    Either way there's no server, no user, no password. Its database is **one file** (or just memory): copy the file and you have copied the database. The price: only one process may write to it at a time.
    """)
    return


@app.cell
def _(DIAGRAMS, mo):
    mo.image(DIAGRAMS["embedded"])
    return


@app.cell
def _(duckdb, os):
    # A database file: tables that stay. One file holds the whole database
    # (00-make-files.py wrote it, with orders_big inside). Opening it is the whole "connection".
    shop = duckdb.connect("files/shop.duckdb")
    print(shop.sql("SHOW TABLES").fetchall())
    print(shop.sql("SELECT count(*) AS orders, sum(ordertotal) AS total FROM orders_big").fetchall())
    print(f"files/shop.duckdb: {os.path.getsize('files/shop.duckdb') / 1e6:.0f} MB")
    return (shop,)


@app.cell
def _(shop, subprocess, sys):
    # The trap: a second process wants the same file while this notebook has it open.
    _ = shop
    _second = "import duckdb; duckdb.connect('files/shop.duckdb')"
    _r = subprocess.run([sys.executable, "-c", _second], capture_output=True, text=True)
    print(_r.stderr.strip().splitlines()[-1][:160])
    return


@app.cell
def _(shop, subprocess, sys):
    # Close it, and two read-only readers are fine.
    shop.close()
    _reader = ("import duckdb; c = duckdb.connect('files/shop.duckdb', read_only=True); "
               "print(c.sql('SELECT count(*) FROM orders_big').fetchall())")
    _procs = [subprocess.Popen([sys.executable, "-c", _reader], stdout=subprocess.PIPE, text=True) for _ in range(2)]
    shop_closed = [p.communicate()[0].strip() for p in _procs]
    print(shop_closed)
    return (shop_closed,)


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 3.3 Use cases: PostgreSQL and DuckDB
    """)
    return


@app.cell
def _(DIAGRAMS, mo):
    mo.image(DIAGRAMS["when"])
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 3.4 One record: row store vs column store

    "Give me order 4890168" and "give me customer 4242's orders", asked of the same 5,000,000 orders in both databases: PostgreSQL's `orders_big` (rows) and DuckDB's `files/shop.duckdb` (columns).

    - **One order, by `orderID`.** PostgreSQL has an index on it (the primary key): the index gives the row's address, and **one page holds the whole row**. DuckDB has no such index, but it keeps the **min / max of every column in every row group** automatically ("zonemaps"), and `orderid` is in order, so it skips straight to 1 row group, then picks the order's 11 values out of 11 separate column chunks.
    - **One customer's orders, by `customerID`.** No index in PostgreSQL: it reads **every page**, every whole row. DuckDB scans only the `customerid` column (min/max can't help: one customer's orders are spread through the whole year) and fetches the other columns for the 97 matching rows only.

    So: a row store with the right index is the fastest way to one record; without an index a column store wins, because it reads one column instead of whole rows. (Lecture 7: with an index on `customerID`, PostgreSQL reads 97 pages for these 97 orders.)
    """)
    return


@app.cell
def _(duck_db, pd, pg_conn, shop_closed, time):
    # The same two lookups in both databases; median of 5 runs, in milliseconds.
    _ = shop_closed                                  # shop.duckdb is closed by now (3.2)
    duck_db.execute("ATTACH IF NOT EXISTS 'files/shop.duckdb' AS shopfile (READ_ONLY)")
    _lookups = {
        "one order (orderID = 4890168)": "WHERE orderID = 4890168",
        "one customer's orders (customerID = 4242)": "WHERE customerID = 4242",
    }

    def _median_ms(run):
        _times = []
        for _ in range(5):
            _t = time.perf_counter()
            _n = len(run())
            _times.append((time.perf_counter() - _t) * 1000)
        return round(sorted(_times)[2], 1), _n

    _rows = []
    for _what, _where in _lookups.items():
        _pg_ms, _n = _median_ms(lambda: pg_conn.execute(f"SELECT * FROM orders_big {_where}").fetchall())
        _dk_ms, _ = _median_ms(lambda: duck_db.execute(f"SELECT * FROM shopfile.orders_big {_where}").fetchall())
        _rows.append({"lookup": _what, "rows": _n, "PostgreSQL ms": _pg_ms, "DuckDB ms": _dk_ms})
    one_record_done = True
    pd.DataFrame(_rows)
    return (one_record_done,)


@app.cell
def _(duck_db, mo, one_record_done, pg_conn):
    # How each one found the rows: the key lines of each plan.
    _ = one_record_done
    _keep = ("Scan", "Index Cond", "Filter", "Buffers", "Row Groups", "Total Time", "Execution Time")
    _out = []
    for _where in ["WHERE orderID = 4890168", "WHERE customerID = 4242"]:
        _out.append(f"===== {_where}")
        _out.append("PostgreSQL:")
        _out += ["  " + r[0].strip() for r in pg_conn.execute(
            f"EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders_big {_where}") if any(k in r[0] for k in _keep)]
        _out.append("DuckDB:")
        _plan = duck_db.execute(f"EXPLAIN ANALYZE SELECT * FROM shopfile.orders_big {_where}").fetchall()[0][1]
        _out += ["  " + l.strip("│╭╮╰╯─┚┖┒┎ ") for l in _plan.splitlines() if any(k in l for k in _keep)]
    mo.plain_text("\n".join(_out))
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 4 — Querying and writing files

    `files/monthly/` holds twelve CSV exports, one per month of 2025. In July the shop changed its till system. Nobody told the analysts.

    ### 4.1 A glob: many files, one query

    `*` matches any characters, so `'files/monthly/*.csv'` reads all twelve files as one table. DuckDB takes the columns from the **first** file (January). The files from July on have no `ordertotal`, so it stops at the first one it reaches. **This error is on purpose**: a loud failure is good. (Which file it names varies from run to run: the files are read in parallel.)
    """)
    return


@app.cell
def _(duck_db, duckdb, mo):
    try:
        duck_db.sql("""
            SELECT count(*) AS orders, sum(ordertotal) AS total
            FROM 'files/monthly/*.csv'
        """).fetchall()
        _out = mo.md("No error?")
    except duckdb.Error as _e:
        _out = mo.callout(mo.md(f"**The error, on purpose:**\n```text\n{_e}\n```"), kind="warn")
    _out
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 4.2 The suggested fix runs, and is wrong

    `union_by_name` matches columns by name and fills a missing one with NULL. All 1,895,177 orders are there, and the total is **about half** the year's revenue.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.accordion({
        'DuckDB: many files: globs, union_by_name, filename': mo.md(r"""

        A **glob** is a file-name pattern: `*` any characters, `**` any sub-folders, `?` one character. `'files/monthly/*.csv'` = every CSV in that folder.
        By default DuckDB "reads the schema of the first file": a column missing from a later file is an error, an extra column in a later file is dropped.

        | Option (read_csv, read_parquet) | What it does |
        |---|---|
        | `union_by_name = true` | match columns by **name**; a column a file doesn't have becomes NULL |
        | `filename = true` | add a column `filename`: which file each row came from |

        `glob('pattern')` (a function) lists the matching files, one row each, in a column `file`.
        *Source: DuckDB 2.0, Reading Multiple Files; Combining Schemas; Utility Functions.*
        """),
    })
    return


@app.cell
def _(duck_db, mo):
    _df = mo.sql(
        f"""
        SELECT count(*) AS orders, sum(ordertotal)::DECIMAL(15,2) AS total
        FROM read_csv('files/monthly/*.csv', union_by_name = true)
        """,
        engine=duck_db
    )
    return


@app.cell
def _(duck_db, mo):
    _df = mo.sql(
        f"""
        -- filename = true: which file each row came from
        SELECT filename, count(*) AS orders, count(ordertotal) AS with_total
        FROM read_csv('files/monthly/*.csv', union_by_name = true, filename = true)
        GROUP BY filename
        ORDER BY filename
        """,
        engine=duck_db
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 4.3 The real fix, and the check

    From July the column is called `order_total`. Take whichever is there, then compare with a source you trust.
    """)
    return


@app.cell
def _(duck_db, mo):
    _df = mo.sql(
        f"""
        SELECT 'monthly CSVs' AS source, count(*) AS orders,
               sum(coalesce(ordertotal, order_total))::DECIMAL(15,2) AS total
        FROM read_csv('files/monthly/*.csv', union_by_name = true)
        UNION ALL
        SELECT 'Parquet, 2025', count(*), sum(ordertotal)
        FROM 'files/orders_big.parquet'
        WHERE orderdate >= DATE '2025-01-01'
        """,
        engine=duck_db
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 4.4 Write: one folder per month

    `COPY ... TO` writes a query's result to a file. `PARTITION_BY` writes a folder per value: `year=2025/month=6/data_0.parquet`. First, what's in `files/` now (the clean button at the top deletes what this Part writes, to show it again):
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.accordion({
        'DuckDB: COPY ... TO': mo.md(r"""

        `COPY (query) TO 'path' (options)` "exports data from DuckDB to an external CSV, Parquet, JSON, or BLOB file". A single file is overwritten if it exists.

        | Option | What it does | Default |
        |---|---|---|
        | `FORMAT` | `parquet`, `csv`, `json` | from the file extension |
        | `PARTITION_BY (cols)` | a folder per value: `year=2025/month=6/` (columns, not expressions) | — |
        | `OVERWRITE` | with `PARTITION_BY`: empty the target folders first | false |
        | `COMPRESSION` | Parquet codec: `snappy`, `zstd`, `gzip`, … | snappy |
        | `ROW_GROUP_SIZE` | rows per Parquet row group | 122,880 |
        | `HEADER` | CSV: write the column names | true |

        *Source: DuckDB 2.0, COPY Statement; Partitioned Writes.*
        """),
    })
    return


@app.cell
def _(list_files):
    # Before: what files/ holds now
    list_files("files")
    return


@app.cell
def _(duck_db, mo):
    _df = mo.sql(
        f"""
        COPY (
            SELECT *, year(orderdate) AS year, month(orderdate) AS month
            FROM 'files/orders_big.parquet'
        ) TO 'files/by_month' (FORMAT parquet, PARTITION_BY (year, month), OVERWRITE)
        """,
        engine=duck_db
    )
    return


@app.cell
def _(duck_db, mo):
    by_month_files = mo.sql(
        f"""
        SELECT count(*) AS files FROM glob('files/by_month/**/*.parquet')
        """,
        engine=duck_db
    )
    return (by_month_files,)


@app.cell
def _(by_month_files, list_files):
    # After: the new folders, one per year and month
    _ = by_month_files
    list_files("files/by_month")
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 4.5 Read the folders: what the folder names can and can't do

    The 36 files sit in folders named `year=2025/month=6/`. This naming, `key=value` for each folder, is called **Hive partitioning**. When DuckDB reads `'files/by_month/*/*/*.parquet'` it sees the names and adds two columns, `year` and `month`, to every row. Those two columns are **not inside the files**: they exist only in the folder names.

    That gives DuckDB a shortcut, and only one:

    1. **`WHERE year = 2025 AND month = 6`**: DuckDB can answer "which files could hold these rows?" from the folder names alone, **before opening anything**. Plan: `File Filters: (year = 2025)(month = 6)`, `Scanning Files: 1/36`.
    2. **`WHERE orderdate` in June 2025**: same question, same answer, but to DuckDB `month=6` is just a label; it doesn't know the folder holds only June dates. So it must **open all 36 files** and read each footer's min/max of `orderdate` (Part 1.4). Plan: `Total Files Read: 36`, then `Row Groups Scanned: 2 / 65`.

    Same result, both fast on 36 small local files. On thousands of files in cloud storage, opening every file is the slow part. **The rule:** filter on the partition columns, alone or next to the date (`WHERE year = 2025 AND month = 6 AND orderdate >= ...`). It's Lecture 7's partition-pruning trap (9.4) with folders instead of tables.
    """)
    return


@app.cell
def _(by_month_files, duck_db, mo):
    _ = by_month_files
    mo.plain_text(duck_db.execute("""
        EXPLAIN ANALYZE
        SELECT count(*), sum(ordertotal)
        FROM 'files/by_month/*/*/*.parquet'
        WHERE year = 2025 AND month = 6
    """).fetchall()[0][1])
    return


@app.cell
def _(by_month_files, duck_db, mo):
    _ = by_month_files
    mo.plain_text(duck_db.execute("""
        EXPLAIN ANALYZE
        SELECT count(*), sum(ordertotal)
        FROM 'files/by_month/*/*/*.parquet'
        WHERE orderdate >= DATE '2025-06-01' AND orderdate < DATE '2025-07-01'
    """).fetchall()[0][1])
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 5 — Python and PostgreSQL (psycopg, parameters, pandas, polars)

    ### 5.1 Connecting to PostgreSQL, step by step

    **psycopg** is the Python client for PostgreSQL: it does what psql does, from Python. Five steps.

    **Step 1. What you need.** A running server (Part 3.1), the connection string (3.1), and the package (`pip install psycopg`, already in this course's environment).
    """)
    return


@app.cell
def _(DSN, psycopg):
    # Step 1: the package, and the connection string the notebook uses
    print("psycopg", psycopg.__version__)
    print(psycopg.conninfo.conninfo_to_dict(DSN))
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Step 2. Connect.** `psycopg.connect(...)` opens a connection: a session with the server, served by its own server process (3.1). Here every part is written out; it's the same as the connection string `postgresql://postgres:postgres@localhost:5432/lecture08`. (The rest of the notebook uses `DSN`, which holds that string.)
    """)
    return


@app.cell
def _(psycopg):
    _conn = psycopg.connect(
        host="localhost",      # the machine the server runs on
        port=5432,             # PostgreSQL's port on that machine
        dbname="lecture08",    # which database on that server
        user="postgres",       # who we are
        password="postgres",
    )
    print("connected; server process:", _conn.info.backend_pid)
    _conn.close()
    print("closed:", _conn.closed)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Step 3. Run SQL: a cursor.** `cur = conn.cursor()`, `cur.execute(sql)`, then `fetchone()` (one row), `fetchall()` (all rows) or `fetchmany(n)`. Each row is a tuple; `cur.description` has the column names. `NUMERIC` arrives as Python's `Decimal`: exact.

    **Step 4. Close it: `with`.** A `with` block closes the connection at its end, even after an error. psycopg also starts a **transaction** on the first statement: inside `with`, it's committed at the end (rolled back on an error); with `autocommit=True`, every statement is committed at once.
    """)
    return


@app.cell
def _(DSN, psycopg):
    with psycopg.connect(DSN) as _conn:
        _cur = _conn.cursor()
        _cur.execute("SELECT orderID, status, orderTotal FROM orders ORDER BY orderID LIMIT 3")
        print([d.name for d in _cur.description])
        for _row in _cur.fetchall():
            print(_row)
    print("closed after the with block:", _conn.closed)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Step 5. When it goes wrong.** The usual errors, and what they mean. All are `psycopg.OperationalError`: read the message.
    """)
    return


@app.cell
def _(DSN, psycopg):
    from psycopg.conninfo import make_conninfo as _make

    _tries = {
        "wrong password": _make(DSN, password="wrong"),
        "no such database": _make(DSN, dbname="lecture99"),
        "nothing listening on that port": _make(DSN, port="5999"),
    }
    for _what, _dsn in _tries.items():
        try:
            psycopg.connect(_dsn, connect_timeout=3).close()
            print(f"{_what}: connected?!")
        except psycopg.OperationalError as _e:
            print(f"{_what}:\n   {str(_e).strip().splitlines()[-1][:150]}")
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **The notebook's own connection.** Every PostgreSQL cell below uses one connection, `pg_conn`, made automatically at the top of the notebook (`psycopg.connect(DSN, autocommit=True)`). If the server is restarted while the notebook is open, run the notebook again: the connection is made again with it.
    """)
    return


@app.cell
def _(pg_conn):
    print("pg_conn: server process", pg_conn.info.backend_pid, "| closed:", pg_conn.closed)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 5.2 The connection at work
    """)
    return


@app.cell
def _(pg_conn):
    # pg_conn = psycopg.connect(DSN, autocommit=True), made at the top of the notebook
    cur = pg_conn.cursor()       # one cursor, used by the cells below
    cur.execute("SELECT count(*), sum(orderTotal) FROM orders WHERE status = 'completed'")
    _row = cur.fetchone()
    print(_row, type(_row[1]))
    return (cur,)


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 5.3 Parameters, and the f-string trap

    `%s` in the SQL, the values separately. An f-string pastes the text **into** the SQL: the quote in it changes the query, and all 30 customers come back. That's SQL injection.
    """)
    return


@app.cell
def _(cur):
    _status = "cancelled"
    cur.execute("SELECT count(*), sum(orderTotal) FROM orders WHERE status = %s", (_status,))
    print(cur.fetchone())
    return


@app.cell
def _(cur):
    _last_name = "x' OR '1'='1"          # typed into a search box
    _sql = f"SELECT count(*) FROM customers WHERE lastName = '{_last_name}'"
    print(_sql)
    cur.execute(_sql)
    print("f-string:  ", cur.fetchone())
    cur.execute("SELECT count(*) FROM customers WHERE lastName = %s", (_last_name,))
    print("parameter: ", cur.fetchone())
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 5.4 Into pandas

    `pd.read_sql` works with a warning (pandas is tested with SQLAlchemy), and changes three things without a word: lowercase names, `employeeid` as a float (it has NULLs), and `ordertotal` as a float: **157078.40999999997**. Building the DataFrame from the cursor keeps the `Decimal`s.
    """)
    return


@app.cell
def _(pd, pg_conn, warnings):
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")      # the SQLAlchemy warning, read about it in 5.4 of the steps
        _df = pd.read_sql("SELECT * FROM orders", pg_conn)
    print(_df[["employeeid", "rating", "ordertotal"]].dtypes.to_dict())
    print(_df.loc[_df.status == "completed", "ordertotal"].sum())
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Working with it in pandas.** Once the rows are in a DataFrame, it's pandas: group, aggregate, sort, plot. The same questions as Lectures 3–5, in pandas. (`orders` and `customers` pulled from PostgreSQL; `ordertotal` is a float here.)
    """)
    return


@app.cell
def _(pd, pg_conn, warnings):
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        orders_pd = pd.read_sql("SELECT * FROM orders", pg_conn)
        customers_pd = pd.read_sql("SELECT customerID, firstName, lastName, city FROM customers", pg_conn)
    # 1. orders and revenue per status (GROUP BY status)
    print(orders_pd.groupby("status")["ordertotal"].agg(["count", "sum"]).round(2), "\n")
    # 2. completed revenue per month (date_trunc + GROUP BY)
    _done = orders_pd[orders_pd.status == "completed"]
    _monthly = _done.groupby(pd.to_datetime(_done.orderdate).dt.to_period("M"))["ordertotal"].sum().round(2)
    print(_monthly.head(3), "\n")
    # 3. top 3 customers by completed revenue (JOIN + GROUP BY + ORDER BY + LIMIT)
    _top = (_done.merge(customers_pd, on="customerid")
            .groupby(["firstname", "lastname", "city"])["ordertotal"].sum().round(2)
            .sort_values(ascending=False).head(3))
    print(_top)
    return


@app.cell
def _(cur, pd):
    cur.execute("SELECT orderID, status, orderTotal FROM orders")
    _df = pd.DataFrame(cur.fetchall(), columns=[d.name for d in cur.description])
    print(_df.dtypes.to_dict())
    print(_df.loc[_df.status == "completed", "ordertotal"].sum())
    return


@app.cell
def _(pd):
    # pandas guesses from a CSV too: online orders have no employee, so employeeID is a float.
    print(pd.read_csv("data/orders.csv")["employeeID"].head(3).tolist())
    print(pd.read_csv("data/orders.csv", dtype={"employeeID": "Int64"})["employeeID"].head(3).tolist())
    # And a postal code is a number to pandas: 0049 becomes 49.
    print(pd.read_csv("files/messy/customers_export.csv")["postal_code"].head(3).tolist())
    print(pd.read_csv("files/messy/customers_export.csv", dtype={"postal_code": str})["postal_code"].head(3).tolist())
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 5.5 The same with polars

    polars is another DataFrame library. Read from PostgreSQL, it **keeps the types**: `employeeid` stays an integer (with nulls), `ordertotal` stays an exact `Decimal`: **157078.41**. From a CSV it guesses like everyone else: integers right, money as `Float64`. And it stops on `n/a`, like DuckDB.
    """)
    return


@app.cell
def _(pg_conn, pl):
    _df = pl.read_database("SELECT * FROM orders", connection=pg_conn)
    print(_df.select("employeeid", "rating", "ordertotal").schema)
    print(_df.filter(pl.col("status") == "completed")["ordertotal"].sum())
    return


@app.cell
def _(pg_conn, pl):
    orders_pl = pl.read_database("SELECT * FROM orders", connection=pg_conn)
    customers_pl = pl.read_database("SELECT customerID, firstName, lastName, city FROM customers", connection=pg_conn)
    # The same three questions in polars (ordertotal stays an exact Decimal)
    print(orders_pl.group_by("status").agg(pl.len().alias("count"), pl.col("ordertotal").sum()).sort("status"))
    _done = orders_pl.filter(pl.col("status") == "completed")
    print(_done.group_by(pl.col("orderdate").dt.truncate("1mo").alias("month"))
          .agg(pl.col("ordertotal").sum()).sort("month").head(3))
    print(_done.join(customers_pl, on="customerid")
          .group_by("firstname", "lastname", "city").agg(pl.col("ordertotal").sum())
          .sort("ordertotal", descending=True).head(3))
    return


@app.cell
def _(pl):
    _orders = pl.read_csv("data/orders.csv")
    print(_orders.select("employeeID", "orderTotal").schema, _orders["employeeID"].head(3).to_list())
    print(_orders.filter(pl.col("status") == "completed")["orderTotal"].sum())
    try:
        pl.read_csv("files/messy/customers_export.csv")
    except Exception as _e:
        print(type(_e).__name__, str(_e).splitlines()[0])
    print(pl.read_csv("files/messy/customers_export.csv", null_values=["n/a"])["postal_code"].head(3).to_list())
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 5.6 Let the database do the work

    "Total of all 2025 orders", four ways. Same answer each time. The **fetch** column is moving 1.9 million rows from the server into Python; the **sum** column is the adding up once they're there. Watch which one is big.
    """)
    return


@app.cell
def _(pd, pg_conn, pl, time, warnings):
    _where = "WHERE orderDate >= '2025-01-01'"
    _rows = []

    _t = time.perf_counter()
    _total = pg_conn.execute(f"SELECT sum(orderTotal) FROM orders_big {_where}").fetchone()[0]
    _rows.append({"how": "SQL: sum in PostgreSQL", "rows sent": 1,
                  "fetch s": round(time.perf_counter() - _t, 2), "sum s": 0.0, "total": str(_total)})

    _t = time.perf_counter()
    _data = pg_conn.execute(f"SELECT orderTotal FROM orders_big {_where}").fetchall()
    _t2 = time.perf_counter()
    _total = sum(r[0] for r in _data)
    _rows.append({"how": "plain Python: fetchall + sum()", "rows sent": len(_data),
                  "fetch s": round(_t2 - _t, 2), "sum s": round(time.perf_counter() - _t2, 3), "total": str(_total)})
    del _data

    _t = time.perf_counter()
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        _df = pd.read_sql(f"SELECT orderTotal FROM orders_big {_where}", pg_conn)
    _t2 = time.perf_counter()
    _total = _df["ordertotal"].sum()
    _rows.append({"how": "pandas: read_sql + .sum()", "rows sent": len(_df),
                  "fetch s": round(_t2 - _t, 2), "sum s": round(time.perf_counter() - _t2, 3), "total": f"{_total:.2f}"})
    del _df

    _t = time.perf_counter()
    _df = pl.read_database(f"SELECT orderTotal FROM orders_big {_where}", connection=pg_conn)
    _t2 = time.perf_counter()
    _total = _df["ordertotal"].sum()
    _rows.append({"how": "polars: read_database + .sum()", "rows sent": len(_df),
                  "fetch s": round(_t2 - _t, 2), "sum s": round(time.perf_counter() - _t2, 3), "total": str(_total)})
    del _df

    pd.DataFrame(_rows)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The libraries add up 1.9 million numbers in milliseconds; **moving the rows takes seconds**, whichever library receives them. pandas and polars are fast at computing, not at fetching. Filter and aggregate in SQL; bring back only the result.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 6 — DuckDB and PostgreSQL together

    `ATTACH` makes a PostgreSQL database look like a schema in DuckDB: `pg.orders`. The `postgres` extension downloads once (internet needed the first time). `READ_ONLY`: DuckDB can't change anything there by mistake.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.accordion({
        'DuckDB: ATTACH, DETACH, postgres_query()': mo.md(r"""

        `ATTACH 'path' AS name` "adds a new database file to the catalog": its tables become `name.table`. `ATTACH 'files/shop.duckdb' AS shop` attaches another DuckDB file; with `(TYPE postgres)` and a PostgreSQL connection string, a PostgreSQL database. `(READ_ONLY)` forbids writes. `DETACH name` closes it again and releases the file. Attachments last for this connection only.
        `postgres_query('pg', 'SQL text')` sends the text to PostgreSQL as it is and returns the result: the query runs **in PostgreSQL**, with PostgreSQL's rules (Part 7.3 uses that).
        *Source: DuckDB 2.0, ATTACH and DETACH Statements; PostgreSQL Extension.*
        """),
    })
    return


@app.cell
def _(DSN, duck_db):
    duck_db.execute("INSTALL postgres")
    duck_db.execute("LOAD postgres")
    duck_db.execute(f"ATTACH IF NOT EXISTS '{DSN}' AS pg (TYPE postgres, READ_ONLY)")
    pg_attached = True
    return (pg_attached,)


@app.cell
def _(duck_db, mo, pg_attached):
    _ = pg_attached
    _df = mo.sql(
        f"""
        SELECT count(*) AS completed_orders, sum(orderTotal) AS completed_revenue
        FROM pg.orders
        WHERE status = 'completed'
        """,
        engine=duck_db
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 6.2 Who does the work?

    The plan's only node is a **Postgres Query**: DuckDB sent this SQL to PostgreSQL, PostgreSQL did the work, one row came back.
    """)
    return


@app.cell
def _(duck_db, mo, pg_attached):
    _ = pg_attached
    mo.plain_text(duck_db.execute("""
        EXPLAIN
        SELECT count(*), sum(orderTotal)
        FROM pg.orders_big
        WHERE status = 'cancelled'
    """).fetchall()[0][1])
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 6.3 One query, two sources

    2025 orders from the Parquet file, names from PostgreSQL.
    """)
    return


@app.cell
def _(duck_db, mo, pg_attached):
    _ = pg_attached
    _df = mo.sql(
        f"""
        SELECT e.firstName || ' ' || e.lastName AS salesperson,
               count(*)          AS orders,
               sum(o.ordertotal) AS revenue
        FROM 'files/orders_big.parquet' AS o
        JOIN pg.employees AS e ON e.employeeID = o.employeeid
        WHERE o.status = 'completed'
          AND o.orderdate >= DATE '2025-01-01'
        GROUP BY salesperson
        ORDER BY revenue DESC
        """,
        engine=duck_db
    )
    return


@app.cell(hide_code=True)
def _(duck_db, mo):
    _df = mo.sql(
        f"""

        """,
        engine=duck_db
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 6.4 PostgreSQL to Parquet, in one statement

    The types travel with the data: `DECIMAL(10,2)` stays `DECIMAL(10,2)`.
    """)
    return


@app.cell
def _(duck_db, mo, pg_attached):
    _ = pg_attached
    _df = mo.sql(
        f"""
        COPY (SELECT * FROM pg.orders) TO 'files/shop_orders.parquet' (FORMAT parquet)
        """,
        engine=duck_db
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 7 — Traps and checks

    ### 7.1 A total that changes every time you run it

    The CSV's `ordertotal` was guessed as `DOUBLE`, which can't hold most decimal fractions exactly. DuckDB adds in parallel, in a different order each run, so the tiny error differs each run. Run the cell twice. Fix: say the type.
    """)
    return


@app.cell
def _(duck_db, mo):
    _df = mo.sql(
        f"""
        SELECT sum(ordertotal)::VARCHAR AS total FROM 'files/orders_big.csv'
        """,
        engine=duck_db
    )
    return


@app.cell
def _(duck_db, mo):
    _df = mo.sql(
        f"""
        -- doubled braces: this cell's SQL is a Python f-string
        SELECT sum(ordertotal)::VARCHAR AS total
        FROM read_csv('files/orders_big.csv', types = {{'ordertotal': 'DECIMAL(10,2)'}})
        """,
        engine=duck_db
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 7.2 A value the sample didn't see

    A CRM export of 50,000 customers. DuckDB keeps `postal_code` as text (zeros kept), and guesses `discount_pct` from the first 20,480 rows: whole numbers. Customer 30,001 says `n/a`. A loud failure; pandas, on the same file, quietly makes it NaN.
    """)
    return


@app.cell
def _(duck_db, duckdb, mo):
    try:
        duck_db.sql("SELECT avg(discount_pct) FROM 'files/messy/customers_export.csv'").fetchall()
        _out = mo.md("No error?")
    except duckdb.Error as _e:
        _out = mo.callout(mo.md(f"**The error, on purpose:**\n```text\n{str(_e)[:700]}\n```"), kind="warn")
    _out
    return


@app.cell
def _(duck_db, mo):
    _df = mo.sql(
        f"""
        SELECT count(*) AS customers, count(discount_pct) AS with_discount,
               round(avg(discount_pct), 2) AS avg_discount
        FROM read_csv('files/messy/customers_export.csv', nullstr = 'n/a')
        """,
        engine=duck_db
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 7.3 Engine differences: the same SQL, two answers

    `postgres_query` runs the SQL **inside PostgreSQL**; the other query runs in DuckDB.

    - Integer division: PostgreSQL `1329 / 600` = **2**, DuckDB **2.215**.
    - NULLs in `ORDER BY ... DESC`: PostgreSQL puts them **first**, DuckDB last. PostgreSQL's "best-rated orders" are three orders nobody rated.
    """)
    return


@app.cell
def _(duck_db, mo, pg_attached):
    _ = pg_attached
    _df = mo.sql(
        f"""
        SELECT 'DuckDB' AS engine, (sum(quantity) / count(DISTINCT orderID))::VARCHAR AS items_per_order
        FROM pg.order_items
        UNION ALL
        SELECT 'PostgreSQL', items_per_order::VARCHAR
        FROM postgres_query('pg',
            'SELECT sum(quantity) / count(DISTINCT orderID) AS items_per_order FROM order_items')
        """,
        engine=duck_db
    )
    return


@app.cell
def _(duck_db, mo, pg_attached):
    _ = pg_attached
    _df = mo.sql(
        f"""
        SELECT orderID, rating FROM pg.orders ORDER BY rating DESC, orderID LIMIT 3
        """,
        engine=duck_db
    )
    return


@app.cell
def _(duck_db, mo, pg_attached):
    _ = pg_attached
    _df = mo.sql(
        f"""
        SELECT * FROM postgres_query('pg',
            'SELECT orderID, rating FROM orders ORDER BY rating DESC, orderID LIMIT 3')
        """,
        engine=duck_db
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 7.4 Matching totals: one check across every copy

    After every move of data: the row count **and** a sum, compared with the source. Expected: every row 5,000,000 and **3199787987.86**, except "CSV (as guessed)" (a DOUBLE: digits after .86, different every run).

    **If the PostgreSQL row differs from all the others**, the files didn't come from this database. A real case from preparing this lecture: the files were written from a PostgreSQL 18 server, and the notebook compared them with a PostgreSQL **14** server, where the same generator (`random()` with the same seed) gives different order totals (PostgreSQL 15 changed `random()`; the yearly counts still match, because the dates don't use it). Same counts, different sums: exactly what this check is for. The fix: run `setup.sh` (or the button at the top) against the server you compare with. The cell below shows which server that is.
    """)
    return


@app.cell
def _(pg_conn):
    print(pg_conn.execute("SELECT version()").fetchone()[0])
    return


@app.cell
def _(by_month_files, duck_db, mo, pg_attached, shop_closed):
    _ = (by_month_files, pg_attached, shop_closed)
    duck_db.execute("ATTACH IF NOT EXISTS 'files/shop.duckdb' AS shopfile (READ_ONLY)")
    _df = mo.sql(
        f"""
        SELECT 'PostgreSQL' AS source, orders, total::VARCHAR AS total
        FROM postgres_query('pg', 'SELECT count(*) AS orders, sum(orderTotal) AS total FROM orders_big')
        UNION ALL
        SELECT 'CSV (as guessed)', count(*), sum(ordertotal)::VARCHAR FROM 'files/orders_big.csv'
        UNION ALL
        SELECT 'CSV (DECIMAL)', count(*), sum(ordertotal)::VARCHAR
        FROM read_csv('files/orders_big.csv', types = {{'ordertotal': 'DECIMAL(10,2)'}})
        UNION ALL
        SELECT 'Parquet', count(*), sum(ordertotal)::VARCHAR FROM 'files/orders_big.parquet'
        UNION ALL
        SELECT 'Parquet folders', count(*), sum(ordertotal)::VARCHAR FROM 'files/by_month/*/*/*.parquet'
        UNION ALL
        SELECT 'DuckDB file', count(*), sum(ordertotal)::VARCHAR FROM shopfile.orders_big
        """,
        engine=duck_db
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 8 — A small pipeline: PostgreSQL → Parquet → report

    Everything from Parts 4–7 as one repeatable job, in `pipeline/`. Each kind of thing has its own folder:

    ```
    pipeline/
      run.py               the only entry point: runs the steps in order
      queries/
        extract/           PostgreSQL SQL, one query per raw file
        transform/         DuckDB SQL, one query per report
        check/             DuckDB SQL, the checks
      .env                 the credentials (PGHOST, PGPORT, PGUSER, ...): not in git; copy .env.example
      src/                 the Python for each step
        config.py          paths, the period to extract; reads .env
        extract.py         step 1: PostgreSQL -> data/raw/
        transform.py       step 2: data/raw/ -> data/reports/
        check.py           step 3: counts and sums vs PostgreSQL
      data/
        raw/               the data as extracted, untouched
        reports/           what people read
      logs/pipeline.log    what every run did: one timestamped line per step (logging, not print)
    ```

    | Step | Runs in | Reads | Writes |
    |---|---|---|---|
    | 1. extract | **PostgreSQL** (psycopg sends `queries/extract/<name>.sql`) | `orders_big`, `employees` | `data/raw/<name>.parquet` |
    | 2. transform | DuckDB, **files only** | `data/raw/` (as views: `orders`, `employees`) | `data/reports/<name>.parquet` |
    | 3. check | PostgreSQL (`source.sql`, same period), then DuckDB (`checks.sql`) | everything | a table: every row should say `ok` |

    **Parameters.** Which period to extract is not written in the SQL. `queries/extract/orders.sql` says `WHERE orderDate >= %(start)s AND orderDate < %(end)s`, and the values come from `EXTRACT_PARAMS` in `src/config.py`: psycopg sends them **separately from the SQL text**, as in 5.3, so they can't change the query. Pick a period below and run: every file is rebuilt for it, and the check compares it with PostgreSQL for the same period. (All of 2025 takes about 16 s, most of it moving 1.9 million rows; one month about 1.5 s.)

    The SQL files contain no file paths: the steps register each Parquet file as a view named after the file. Run it from a terminal, `python pipeline/run.py`, or with the cells below. After step 1 nobody touches the live database again; the reports can be rebuilt from `data/raw/` at any time, and step 3 says whether they can be trusted.
    """)
    return


@app.cell
def _(mo):
    # Every query of the pipeline, as it is on disk
    import glob as _glob

    mo.ui.tabs({_f.removeprefix("pipeline/queries/"): mo.md(f"```sql\n{open(_f).read()}\n```")
                for _f in sorted(_glob.glob("pipeline/queries/*/*.sql"))})
    return


@app.cell
def _(list_files):
    # Before: pipeline/data/ (empty after the clean button)
    list_files("pipeline/data")
    return


@app.cell
def _(mo):
    # The period to extract. Defaults: EXTRACT_PARAMS in pipeline/src/config.py (all of 2025).
    period_start = mo.ui.date(start="2023-01-01", stop="2026-01-01", value="2025-01-01", label="start")
    period_end = mo.ui.date(start="2023-01-02", stop="2026-01-01", value="2026-01-01", label="end (not included)")
    mo.hstack([period_start, period_end], justify="start")
    return period_end, period_start


@app.cell
def _(DSN, mo, period_end, period_start, setup_done):
    # Run the pipeline (pipeline/run.py) for that period. The check table should say ok four times.
    import importlib.util as _ilu

    _ = setup_done
    _spec = _ilu.spec_from_file_location("pipeline_run", "pipeline/run.py")
    _run = _ilu.module_from_spec(_spec)
    _spec.loader.exec_module(_run)
    _params = {"start": period_start.value, "end": period_end.value}   # replaces EXTRACT_PARAMS
    pipeline_checks = _run.main(DSN, params=_params)
    mo.ui.table(pipeline_checks, selection=None)
    return (pipeline_checks,)


@app.cell
def _(list_files, pipeline_checks):
    # After: what each step wrote
    _ = pipeline_checks
    list_files("pipeline/data")
    return


@app.cell
def _(duck_db, mo, pipeline_checks):
    _ = pipeline_checks
    _df = mo.sql(
        f"""
        -- One report, read back from its Parquet file
        FROM 'pipeline/data/reports/monthly_revenue.parquet'
        """,
        engine=duck_db
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 9 — The one idea to leave with

    | Trap | Looked like | Was |
    |---|---|---|
    | `sum(ordertotal)` on the CSV | the total | a `DOUBLE`, different after the .86 on every run (7.1) |
    | Glob, then `union_by_name` | 1,895,177 orders, a total | half the year's revenue: July on was NULL (4.2) |
    | `WHERE orderdate` on month folders | a filter on the date | all 36 files opened (4.5) |
    | `pd.read_sql` | the orders table | floats: 157078.40999999997, `employeeid` 2.0 (5.3) |
    | `pd.read_csv` | postal codes | 0049 became 49 (5.3) |
    | f-string SQL | a search by last name | all 30 customers (5.2) |
    | `sum / count` | average items per order | 2 in PostgreSQL, 2.215 in DuckDB (7.3) |
    | `ORDER BY rating DESC` | best-rated orders | unrated orders, in PostgreSQL (7.3) |

    **Loud failures:** the glob with a missing column (4.1), `n/a` after the sample (7.2), the locked `.duckdb` file (3.3). Everything else ran without an error.

    **The checks:** say the types (don't let a CSV guess money), compare row counts and a sum with the source after every move, write `NULLS LAST` and `::numeric` when the SQL must mean the same in every engine, pass values with `%s`, and aggregate in the database, not in Python.
    """)
    return


if __name__ == "__main__":
    app.run()
