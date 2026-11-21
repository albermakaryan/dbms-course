"""Run the pipeline: extract -> transform -> check.

    python pipeline/run.py          (from lecture_8/, or from anywhere)

    pipeline/
      run.py               this file: runs the steps in order
      queries/extract/     PostgreSQL SQL, one query per raw file
      queries/transform/   DuckDB SQL, one query per report
      queries/check/       DuckDB SQL, the checks
      src/                 the Python for each step (extract, transform, check) and config
      data/raw/            written by extract
      data/reports/        written by transform
      logs/pipeline.log    what every run did (appended)

Credentials: pipeline/.env (copy .env.example); the period to extract:
EXTRACT_PARAMS in src/config.py.
"""

import logging
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))   # so "src" is found from anywhere

from src import check, extract, logs, transform
from src.config import DATA, DSN, EXTRACT_PARAMS, ensure_folders

log = logging.getLogger("pipeline.run")


def main(dsn=DSN, params=EXTRACT_PARAMS):
    """Run the three steps for the period in `params`; return the check table."""
    logs.setup()
    log.info("pipeline started")
    ensure_folders()                            # data/raw/, data/reports/, each with a .gitkeep
    for old in DATA.rglob("*.parquet"):         # start clean: no files from an earlier period
        old.unlink()
    extract.run(dsn, params)
    transform.run()
    checks = check.run(dsn, params)
    for f in sorted(DATA.rglob("*.parquet")):
        log.info("wrote %s (%.1f MB)", f.relative_to(DATA.parent), f.stat().st_size / 1e6)
    failed = (checks["result"] != "ok").sum()
    if failed:
        log.error("pipeline finished: %d check(s) FAILED", failed)
    else:
        log.info("pipeline finished: all %d checks ok", len(checks))
    return checks


if __name__ == "__main__":
    main()
