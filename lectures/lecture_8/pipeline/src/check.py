"""Step 3, CHECK: counts and sums at every stage, compared with PostgreSQL.

1. queries/check/source.sql runs in PostgreSQL, with the same parameters as
   the extract: the numbers the pipeline must reproduce.
2. queries/check/checks.sql runs in DuckDB and compares them with the raw
   and report files (registered as views named after the files).
Returns the check table (a pandas DataFrame); every row should say ok.
"""

import logging

import duckdb
import polars as pl
import psycopg

from .config import DSN, EXTRACT_PARAMS, QUERIES, RAW, REPORTS
from .transform import register_views

log = logging.getLogger("pipeline.check")


def run(dsn=DSN, params=EXTRACT_PARAMS):
    with psycopg.connect(dsn) as conn:
        source = pl.read_database((QUERIES / "check" / "source.sql").read_text(), connection=conn,
                                  execute_options={"params": params})
    con = duckdb.connect()
    register_views(con, RAW)
    register_views(con, REPORTS)
    con.register("source", source)              # a DataFrame, usable as a table in DuckDB SQL
    checks = con.sql((QUERIES / "check" / "checks.sql").read_text()).df()
    con.close()
    for row in checks.itertuples():
        # a failed check is logged as an ERROR, so it stands out in the log
        level = logging.INFO if row.result == "ok" else logging.ERROR
        log.log(level, "%-45s source %-15s pipeline %-15s %s", row.check_name, row.source, row.pipeline, row.result)
    return checks
