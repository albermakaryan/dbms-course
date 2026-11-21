# Pipeline: PostgreSQL → Parquet → reports

A small, repeatable job. It copies one period's orders out of PostgreSQL, builds two reports from those files, and checks that nothing was lost.

## Run

From `lecture_8/`, with the `lecture08` database set up (`./setup.sh`). Once, put your credentials in `pipeline/.env`:

```bash
cp pipeline/.env.example pipeline/.env      # then edit pipeline/.env
python pipeline/run.py
```

`.env` holds `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD` (PostgreSQL's standard names). It is git-ignored: passwords never go into the code or the repository. `.env.example` (committed) shows the names.

Each step logs what it did, to the screen and to `logs/pipeline.log` (appended, one timestamped line per event). The last lines are the checks: every one should say `ok`; a failed check is logged as `ERROR`.

## Parameters

The period to extract is set in `src/config.py`, not in the SQL:

```python
EXTRACT_PARAMS = {"start": date(2025, 1, 1), "end": date(2026, 1, 1)}
```

`queries/extract/orders.sql` uses them as placeholders, `WHERE orderDate >= %(start)s AND orderDate < %(end)s`. psycopg sends the values separately from the SQL text, so they can never change the query (lecture Part 5.3). The check uses the same values on the PostgreSQL side. Change the dates, run again, and every file is rebuilt for the new period.

## Steps

| Step | Runs in | Reads | Writes |
|---|---|---|---|
| 1. extract | PostgreSQL | `queries/extract/*.sql` | `data/raw/<name>.parquet` |
| 2. transform | DuckDB, files only | `data/raw/`, `queries/transform/*.sql` | `data/reports/<name>.parquet` |
| 3. check | PostgreSQL (`source.sql`), then DuckDB (`checks.sql`) | everything | the check table |

## Layout

```
run.py         the only entry point: runs the steps in order
queries/       the SQL, one folder per step
src/           the Python for each step, plus config.py (paths, parameters; reads .env)
.env           your credentials (not in git; copy .env.example)
data/raw/      extracted data, untouched
data/reports/  the reports
logs/          pipeline.log: what every run did (not in git)
```

## Add a report

Add `queries/transform/<name>.sql`, a DuckDB `SELECT` over the raw tables `orders` and `employees`. The next run writes `data/reports/<name>.parquet`. The SQL files hold no file paths: the raw files are registered as tables named after the files.
