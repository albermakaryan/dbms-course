"""Step 1, EXTRACT: PostgreSQL -> data/raw/.

Every queries/extract/<name>.sql is a PostgreSQL query. It is sent to the
PostgreSQL server as it is (psycopg), with the parameters from
config.EXTRACT_PARAMS filling its %(name)s placeholders, and its result is
saved as data/raw/<name>.parquet. PostgreSQL can't write Parquet, so polars
fetches the rows (keeping PostgreSQL's types: NUMERIC stays an exact
Decimal) and writes the file.
"""

import logging
import time

import polars as pl
import psycopg

from .config import DSN, EXTRACT_PARAMS, QUERIES, RAW, ensure_folders

log = logging.getLogger("pipeline.extract")


def run(dsn=DSN, params=EXTRACT_PARAMS):
    ensure_folders()
    log.info("parameters: %s", params)
    with psycopg.connect(dsn) as conn:
        for sql_file in sorted((QUERIES / "extract").glob("*.sql")):
            start = time.perf_counter()
            # Runs in PostgreSQL. The values travel separately from the SQL text
            # (a query without placeholders, like employees.sql, just ignores them).
            df = pl.read_database(sql_file.read_text(), connection=conn,
                                  execute_options={"params": params})
            out = RAW / f"{sql_file.stem}.parquet"
            df.write_parquet(out)
            log.info("%s -> data/raw/%s: %s rows in %.2f s",
                     sql_file.name, out.name, f"{len(df):,}", time.perf_counter() - start)
