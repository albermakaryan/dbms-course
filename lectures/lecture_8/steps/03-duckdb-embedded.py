# ============================================================
# Lecture 8 — Part 3, second half: DuckDB, the database in your program
# Python. Run from the lecture_8/ folder:  python steps/03-duckdb-embedded.py
#
# PostgreSQL is a server: a separate program, always running, that your
# code talks to over a connection. DuckDB is a library: it runs inside
# your own Python process. No server, no user, no password.
# ============================================================

# %% 3.4 An in-memory database: nothing on disk
import os
import subprocess
import sys

import duckdb

mem = duckdb.connect()          # no file name = in memory, gone when Python exits
print(mem.sql("SELECT count(*) AS orders FROM 'files/orders_big.parquet'").fetchall())
# [(5000000,)]

# %% 3.5 A database file: tables that stay
# One file holds the whole database. 00-make-files.py wrote it, with
# orders_big inside. Copy it, e-mail it, delete it.
con = duckdb.connect("files/shop.duckdb")
print(con.sql("SHOW TABLES").fetchall())
print(con.sql("SELECT count(*) AS orders, sum(ordertotal) AS total FROM orders_big").fetchall())
print(f"files/shop.duckdb: {os.path.getsize('files/shop.duckdb') / 1e6:.0f} MB")
# [('orders_big',)]
# [(5000000, Decimal('3199787987.86'))]
# files/shop.duckdb: 116 MB

# %% 3.6 The trap: a second process wants the same file
# Here, a second Python (think: the notebook has the file open, and you
# start a script, or the DuckDB CLI, on it).
second = "import duckdb; duckdb.connect('files/shop.duckdb')"
r = subprocess.run([sys.executable, "-c", second], capture_output=True, text=True)
print(r.stderr.strip().splitlines()[-1][:160])
# _duckdb.IOException: IO Error: Could not set lock on file "/home/alber/Desktop/teaching/dbms-course/lectures/lecture_8/files/shop.duckdb": Conflicting lock is h
# A loud failure: the file is locked. One process may open a .duckdb
# file for writing; several may open it read-only, but only while
# nobody has it open for writing.

# %% 3.7 Close it, and two readers are fine
con.close()
reader = ("import duckdb; c = duckdb.connect('files/shop.duckdb', read_only=True); "
          "print(c.sql('SELECT count(*) FROM orders_big').fetchall())")
procs = [subprocess.Popen([sys.executable, "-c", reader], stdout=subprocess.PIPE, text=True) for _ in range(2)]
print([p.communicate()[0].strip() for p in procs])
# ['[(5000000,)]', '[(5000000,)]']
