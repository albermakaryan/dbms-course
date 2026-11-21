"""Where everything is, and what to extract. Every other module takes its settings from here."""

import os
from datetime import date
from pathlib import Path

from dotenv import load_dotenv

PIPELINE = Path(__file__).resolve().parent.parent       # lecture_8/pipeline/
QUERIES = PIPELINE / "queries"
DATA = PIPELINE / "data"
RAW = DATA / "raw"              # written by extract.py: the data as it came out of PostgreSQL
REPORTS = DATA / "reports"      # written by transform.py: built from raw/ only
LOGS = PIPELINE / "logs"        # logs/pipeline.log: what every run did



def ensure_folders():
    """Create data/raw/ and data/reports/ if missing, each with an empty .gitkeep
    (git doesn't keep empty folders; the .gitkeep keeps them in the repository)."""
    for folder in (RAW, REPORTS):
        folder.mkdir(parents=True, exist_ok=True)
        (folder / ".gitkeep").touch(exist_ok=True)


# Credentials live in pipeline/.env (not in the code, not in git): see .env.example.
# load_dotenv puts its lines into os.environ; a variable already set in your
# shell wins over the file.
load_dotenv(PIPELINE / ".env")
for _name in ("PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD"):
    if _name not in os.environ:
        raise SystemExit(f"{_name} is not set: copy pipeline/.env.example to pipeline/.env and fill it in.")

DSN = (f"postgresql://{os.environ['PGUSER']}:{os.environ['PGPASSWORD']}"
       f"@{os.environ['PGHOST']}:{os.environ['PGPORT']}/{os.environ['PGDATABASE']}")

# The period to extract: orders with start <= orderDate < end.
# These values fill %(start)s and %(end)s in queries/extract/orders.sql and
# queries/check/source.sql. Change them here and run again: e.g. one month,
# date(2025, 6, 1) to date(2025, 7, 1). (The data covers 2023-2025.)
EXTRACT_PARAMS = {
    "start": date(2025, 1, 1),
    "end": date(2026, 1, 1),
}
