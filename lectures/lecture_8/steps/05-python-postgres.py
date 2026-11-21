# ============================================================
# Lecture 8 — Part 5: Python and PostgreSQL (psycopg, parameters, pandas)
# Python. Run from the lecture_8/ folder:
#     LECTURE08_DSN=postgresql://postgres:postgres@localhost:5432/lecture08 \
#         python steps/05-python-postgres.py
# ============================================================

# %% 5.1 Connect, run a query, fetch the result
import os
import time
import warnings

import pandas as pd
import polars as pl
import psycopg

DSN = os.environ.get("LECTURE08_DSN", "postgresql://postgres:postgres@localhost:5432/lecture08")
conn = psycopg.connect(DSN)
cur = conn.cursor()
cur.execute("SELECT count(*), sum(orderTotal) FROM orders WHERE status = 'completed'")
row = cur.fetchone()
print(row)
print(type(row[1]))
# (529, Decimal('157078.41'))
# <class 'decimal.Decimal'>
# A tuple per row. NUMERIC arrives as Python's Decimal: exact, 157078.41.

# %% 5.2 Parameters: %s in the SQL, the values separately
status = "cancelled"
cur.execute("SELECT count(*), sum(orderTotal) FROM orders WHERE status = %s", (status,))
print(cur.fetchone())
# (27, Decimal('6169.21'))
# psycopg sends the value apart from the SQL text. Always %s, never
# quotes around it, and the values as a tuple (note the comma).

# %% 5.3 The trap: building the SQL with an f-string
last_name = "x' OR '1'='1"          # typed into a search box
sql = f"SELECT count(*) FROM customers WHERE lastName = '{last_name}'"
print(sql)
cur.execute(sql)
print("f-string:  ", cur.fetchone())
cur.execute("SELECT count(*) FROM customers WHERE lastName = %s", (last_name,))
print("parameter: ", cur.fetchone())
# SELECT count(*) FROM customers WHERE lastName = 'x' OR '1'='1'
# f-string:   (30,)
# parameter:  (0,)
# The f-string pasted the text into the SQL, and the quote inside it
# changed the query: OR '1'='1' is true for every row, so all 30
# customers came back. That's SQL injection. With %s, the text is
# only ever a value: nobody is called x' OR '1'='1, so 0.

# %% 5.4 Into pandas: read_sql
with warnings.catch_warnings(record=True) as w:
    warnings.simplefilter("always")
    df = pd.read_sql("SELECT * FROM orders", conn)
print(str(w[0].message)[:95], "...")
print(df[["employeeid", "rating", "ordertotal"]].dtypes.to_dict())
print(df.loc[df.status == "completed", "ordertotal"].sum())
# pandas only supports SQLAlchemy connectable (engine/connection) or database string URI or sqlit ...
# {'employeeid': dtype('float64'), 'rating': dtype('float64'), 'ordertotal': dtype('float64')}
# 157078.40999999997
# It works, with a warning: pandas is only tested with SQLAlchemy (or
# sqlite3). Three silent changes on the way:
# * column names are lowercase (PostgreSQL folded orderTotal);
# * employeeid and rating are float64: they have NULLs, and a NumPy
#   integer column can't hold a missing value;
# * ordertotal is float64, so the Decimal 157078.41 became
#   157078.40999999997.

# %% 5.5 Keep the exact values: build the DataFrame yourself
cur.execute("SELECT orderID, status, orderTotal FROM orders")
df = pd.DataFrame(cur.fetchall(), columns=[d.name for d in cur.description])
print(df.dtypes.to_dict())
print(df.loc[df.status == "completed", "ordertotal"].sum())
# {'orderid': dtype('int64'), 'status': <StringDtype(na_value=nan)>, 'ordertotal': dtype('O')}
# 157078.41
# Decimals kept (dtype object): exact, but slower to compute with.

# %% 5.6 pandas guesses types from a CSV too
orders = pd.read_csv("data/orders.csv")
print(orders["employeeID"].head(3).tolist(), orders["employeeID"].dtype)
orders = pd.read_csv("data/orders.csv", dtype={"employeeID": "Int64"})
print(orders["employeeID"].head(3).tolist(), orders["employeeID"].dtype)
# [2.0, 1.0, 6.0] float64
# [2, 1, 6] Int64
# Online orders have no employee, so pandas made employeeID a float:
# 2.0, 1.0. "Int64" (capital I) is pandas' integer type that allows
# missing values.

# %% 5.6b polars: the same read from PostgreSQL
# polars: another DataFrame library, used much like pandas.
df = pl.read_database("SELECT * FROM orders", connection=conn)
print({c: str(t) for c, t in df.schema.items() if c in ("employeeid", "rating", "ordertotal")})
print(df.filter(pl.col("status") == "completed")["ordertotal"].sum())
# {'employeeid': 'Int64', 'rating': 'Int64', 'ordertotal': 'Decimal(precision=38, scale=2)'}
# 157078.41
# From PostgreSQL, polars keeps the types: integers with NULLs stay
# integers, NUMERIC stays an exact Decimal: 157078.41.

# %% 5.6c polars guesses from a CSV too
orders = pl.read_csv("data/orders.csv")
print(orders.schema["employeeID"], orders["employeeID"].head(3).to_list(), orders.schema["orderTotal"])
print(orders.filter(pl.col("status") == "completed")["orderTotal"].sum())
# Int64 [2, 1, 6] Float64
# 157078.40999999997
# employeeID stays an integer (polars allows NULLs in any type), but the
# money is a Float64 again: 157078.40999999997.

# %% 5.6d polars and the messy export
try:
    pl.read_csv("files/messy/customers_export.csv")
except Exception as e:
    print(type(e).__name__, str(e).splitlines()[0])
codes = pl.read_csv("files/messy/customers_export.csv", null_values=["n/a"])
print(codes["postal_code"].head(3).to_list())
# ComputeError could not parse `n/a` as dtype `i64` at column 'discount_pct' (column number 4)
# [49, 6, 65]
# The n/a stops polars, loudly, as it stops DuckDB (pandas said
# nothing). Once read, the postal codes lost their zeros, as in pandas.

# %% 5.7 Let the database do the work
t = time.perf_counter()
cur.execute("SELECT sum(orderTotal) FROM orders_big WHERE orderDate >= '2025-01-01'")
total = cur.fetchone()[0]
print(f"sum in PostgreSQL:     {total}   {time.perf_counter() - t:.2f} s, 1 row sent")
t = time.perf_counter()
cur.execute("SELECT orderTotal FROM orders_big WHERE orderDate >= '2025-01-01'")
rows = cur.fetchall()
total = sum(r[0] for r in rows)
print(f"fetch, sum in Python:  {total}   {time.perf_counter() - t:.2f} s, {len(rows):,} rows sent")
# sum in PostgreSQL:     1213754385.91   0.11 s, 1 row sent
# fetch, sum in Python:  1213754385.91   3.32 s, 1,895,177 rows sent
# Same answer. Fetching 1.9 million rows to add them up in Python is
# many times slower and fills your laptop's memory: filter and
# aggregate in SQL, fetch the result.

# %% close
conn.close()
