"""Lecture 8 — Part 0, step 2: write the files the lecture reads.

Run it from the lecture_8/ folder, after steps/00-setup.sql:

    LECTURE08_DSN=postgresql://postgres:postgres@localhost:5432/lecture08 \
        python steps/00-make-files.py

It writes (about 600 MB, in files/, which git ignores):

    files/orders_big.csv               orders_big exported by PostgreSQL (COPY)
    files/orders_big.parquet           the same 5,000,000 rows as Parquet
    files/monthly/orders_2025-01.csv   2025, one CSV per month (12 files);
    ...                                from July on, a new till system names
    files/monthly/orders_2025-12.csv   the total column order_total (Part 4)
    files/messy/customers_export.csv   a CRM export for the CSV traps (Part 7)
    files/shop.duckdb                  a DuckDB database with orders_big (Parts 2, 3)

About 30 seconds. Running it again rewrites everything.
"""

import os
import random
from pathlib import Path

import duckdb
import psycopg

DSN = os.environ.get("LECTURE08_DSN", "postgresql://postgres:postgres@localhost:5432/lecture08")
FILES = Path("files")
(FILES / "monthly").mkdir(parents=True, exist_ok=True)
(FILES / "messy").mkdir(parents=True, exist_ok=True)

# ---- 1. PostgreSQL writes the CSV: COPY ... TO STDOUT, streamed into a file ----
with psycopg.connect(DSN) as conn, conn.cursor() as cur:
    with open(FILES / "orders_big.csv", "wb") as f:
        with cur.copy("COPY (SELECT * FROM orders_big ORDER BY orderID) TO STDOUT (FORMAT csv, HEADER)") as copy:
            for chunk in copy:
                f.write(chunk)
print("orders_big.csv written")

# ---- 2. DuckDB writes the Parquet file. A CSV has no types, so we say them. ----
db = duckdb.connect()
db.sql("""
    COPY (
        SELECT * FROM read_csv('files/orders_big.csv', header = true, columns = {
            'orderid': 'INTEGER', 'customerid': 'INTEGER', 'employeeid': 'INTEGER',
            'orderdate': 'DATE', 'ordertime': 'TIME', 'channel': 'VARCHAR',
            'paymentmethod': 'VARCHAR', 'status': 'VARCHAR', 'deliverydate': 'DATE',
            'rating': 'INTEGER', 'ordertotal': 'DECIMAL(10,2)'})
    ) TO 'files/orders_big.parquet' (FORMAT parquet)
""")
print("orders_big.parquet written")

# ---- 3. Twelve monthly CSV exports for 2025 ----
# From July the till system was replaced, and the new one calls the
# total "order_total" instead of "ordertotal". Nothing else changed.
for m in range(1, 13):
    total = "ordertotal" if m <= 6 else "ordertotal AS order_total"
    db.sql(f"""
        COPY (
            SELECT orderid, customerid, employeeid, orderdate, ordertime, channel,
                   paymentmethod, status, deliverydate, rating, {total}
            FROM 'files/orders_big.parquet'
            WHERE orderdate >= DATE '2025-{m:02d}-01'
              AND orderdate <  DATE '2025-{m:02d}-01' + INTERVAL 1 MONTH
            ORDER BY orderid
        ) TO 'files/monthly/orders_2025-{m:02d}.csv' (FORMAT csv, HEADER)
    """)
print("monthly/ written")

# ---- 4. A messy CRM export: 50,000 customers ----
# * postal_code: Yerevan codes start with 00 (0010 = Kentron), so they
#   only survive if the column is read as text
# * discount_pct: a whole number 0-20, except customer 30,001,
#   where somebody typed "n/a"
random.seed(8)
CITIES = [("Yerevan", 1, 99, 0.6), ("Gyumri", 3101, 3126, 0.2), ("Vanadzor", 2001, 2023, 0.1), ("Abovyan", 2201, 2206, 0.1)]
with open(FILES / "messy" / "customers_export.csv", "w") as f:
    f.write("customer_id,city,postal_code,discount_pct\n")
    for cid in range(1, 50001):
        r, acc = random.random(), 0.0
        for city, lo, hi, share in CITIES:
            acc += share
            if r < acc:
                break
        code = f"{random.randint(lo, hi):04d}"
        disc = "n/a" if cid == 30001 else str(random.choice([0, 0, 0, 5, 10, 15, 20]))
        f.write(f"{cid},{city},{code},{disc}\n")
print("messy/customers_export.csv written")

# ---- 5. A DuckDB database file holding orders_big ----
# Deleted first: replacing a table inside an existing file doesn't shrink the file.
db.close()
if (FILES / "shop.duckdb").exists():
    (FILES / "shop.duckdb").unlink()
shop = duckdb.connect(str(FILES / "shop.duckdb"))
shop.execute("CREATE TABLE orders_big AS FROM 'files/orders_big.parquet'")
shop.close()
print("shop.duckdb written")

for p in sorted(FILES.rglob("*.*")):
    print(f"{p}  {p.stat().st_size / 1e6:,.1f} MB")
