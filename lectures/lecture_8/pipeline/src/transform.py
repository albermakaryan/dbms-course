"""Step 2, TRANSFORM: data/raw/ -> data/reports/, in DuckDB.

Each Parquet file in data/raw/ becomes a view with the file's name
(orders, employees), so the queries read like SQL on tables. Every
queries/transform/<name>.sql is a DuckDB query; its result is saved as
data/reports/<name>.parquet. PostgreSQL is not used.
"""

import logging
import time

import duckdb

from .config import QUERIES, RAW, REPORTS, ensure_folders

log = logging.getLogger("pipeline.transform")


def register_views(con, folder):
    """One view per Parquet file in `folder`, named after the file."""
    for f in sorted(folder.glob("*.parquet")):
        con.execute(f"CREATE OR REPLACE VIEW {f.stem} AS FROM read_parquet('{f}')")


def run():
    ensure_folders()
    con = duckdb.connect()                      # in memory: everything it keeps is in files
    register_views(con, RAW)
    for sql_file in sorted((QUERIES / "transform").glob("*.sql")):
        start = time.perf_counter()
        out = REPORTS / f"{sql_file.stem}.parquet"
        con.execute(f"COPY ({sql_file.read_text()}) TO '{out}' (FORMAT parquet)")
        log.info("%s -> data/reports/%s in %.2f s", sql_file.name, out.name, time.perf_counter() - start)
    con.close()
