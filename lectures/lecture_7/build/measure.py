"""Three runs of every timing comparison quoted in lecture-07-notes.md.

Each query runs as EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON), three times in a
row; we keep Execution Time (and Planning Time), the key plan node, and the
total shared pages (hit + read) of the top node. Writes a Markdown table to
build/measurements-<version>.md. Needs a lecture07 database loaded by
steps/00-setup.sql (any state after a full build is fine: orders_big with
its primary key only). Usage: PGP=<port> python measure.py
"""

import json
import os
import statistics
import sys
import time
from pathlib import Path

import psycopg

port = os.environ.get("PGP", "5432")
conn = psycopg.connect(
    f"host=127.0.0.1 port={port} user=postgres password=postgres dbname=lecture07", autocommit=True
)
ver = conn.execute("SHOW server_version").fetchone()[0].split()[0]
rows_out = []


def x(sql):
    conn.execute(sql)


def key_node(plan):
    """The first node below Aggregate/Limit/Sort wrappers, for the table."""
    names = []

    def walk(n, d=0):
        names.append(n["Node Type"] + (f" ({n['Index Name']})" if "Index Name" in n else ""))
        for c in n.get("Plans", []):
            walk(c, d + 1)

    walk(plan)
    skip = ("Aggregate", "Limit", "Sort", "Subquery Scan", "Unique", "Incremental Sort")
    for nm in names:
        if not nm.startswith(skip):
            return nm
    return names[0]


def measure(part, label, sql, runs=3, rollback=False):
    exe, plan_t, pages = [], [], None
    node = None
    for _ in range(runs):
        q = "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) " + sql
        if rollback:
            with conn.transaction(force_rollback=True):
                j = conn.execute(q).fetchone()[0]
        else:
            j = conn.execute(q).fetchone()[0]
        j = j[0] if isinstance(j, list) else json.loads(j)[0]
        exe.append(j["Execution Time"])
        plan_t.append(j.get("Planning Time", 0.0))
        p = j["Plan"]
        node = key_node(p)
        pages = p.get("Shared Hit Blocks", 0) + p.get("Shared Read Blocks", 0)
    rows_out.append((part, label, node, pages, exe, statistics.median(exe), statistics.median(plan_t)))
    print(f"{part:5} {label:55} {statistics.median(exe):10.2f} ms  {node}", flush=True)


def timed(part, label, sql, setup=None, runs=3):
    """Wall-clock time of a statement with no plan (DROP TABLE), after `setup`."""
    exe = []
    for _ in range(runs):
        if setup:
            for s in setup:
                x(s)
        t0 = time.perf_counter()
        x(sql)
        exe.append((time.perf_counter() - t0) * 1000)
    rows_out.append((part, label, "(no plan: wall clock)", None, exe, statistics.median(exe), 0.0))
    print(f"{part:5} {label:55} {statistics.median(exe):10.2f} ms", flush=True)


x("DROP TABLE IF EXISTS orders_load, orders_big_part, orders_big_daily")
x("VACUUM ANALYZE orders_big")

# ---- Part 1 / 5.1-5.2: customer 4242 ----
q4242 = "SELECT * FROM orders_big WHERE customerID = 4242"
measure("5.1", "customer 4242, no index", q4242)
x("CREATE INDEX m_cust ON orders_big (customerID)")
measure("5.2", "customer 4242, index on customerID", q4242)

# ---- 5.7 GROUP BY ----
qgb = "SELECT customerID, count(*) FROM orders_big GROUP BY customerID"
measure("5.7", "GROUP BY customerID, with the index", qgb)
x("SET enable_indexscan = off; SET enable_indexonlyscan = off; SET enable_bitmapscan = off")
measure("5.7", "GROUP BY customerID, index scans disabled", qgb)
x("RESET enable_indexscan; RESET enable_indexonlyscan; RESET enable_bitmapscan")

# ---- 6.3 covering ----
qcov = "SELECT count(*), sum(orderTotal) FROM orders_big WHERE customerID = 4242"
measure("6.3", "Nane's total, plain customerID index", qcov)
x("CREATE INDEX m_cov ON orders_big (customerID) INCLUDE (orderTotal)")
measure("6.3", "Nane's total, covering index (INCLUDE)", qcov)
x("DROP INDEX m_cov")

# ---- 7.2 type mismatch ----
measure("7.2", "customerID = 4242.0 (numeric)", "SELECT count(*) FROM orders_big WHERE customerID = 4242.0")
measure("7.2", "customerID = '4242'", "SELECT count(*) FROM orders_big WHERE customerID = '4242'")

# ---- 7.4 OR ----
qor = "SELECT orderID, customerID, deliveryDate FROM orders_big WHERE customerID = 4242 OR deliveryDate = '2025-12-14'"
measure("7.4", "OR, deliveryDate not indexed", qor)
x("CREATE INDEX m_deliv ON orders_big (deliveryDate)")
measure("7.4", "OR, both columns indexed (BitmapOr)", qor)
measure("7.4", "UNION rewrite", "SELECT orderID, customerID, deliveryDate FROM orders_big WHERE customerID = 4242 "
        "UNION SELECT orderID, customerID, deliveryDate FROM orders_big WHERE deliveryDate = '2025-12-14'")
x("DROP INDEX m_deliv")

# ---- 8.2 / 8.3 NOT IN vs NOT EXISTS ----
x("DROP INDEX m_cust")
measure("8.2", "NOT EXISTS, cancelled", "SELECT count(*) FROM customers_big c WHERE NOT EXISTS "
        "(SELECT 1 FROM orders_big o WHERE o.customerID = c.customerID AND o.status = 'cancelled')")
measure("8.2", "NOT IN (hashed SubPlan), cancelled", "SELECT count(*) FROM customers_big c WHERE c.customerID NOT IN "
        "(SELECT o.customerID FROM orders_big o WHERE o.status = 'cancelled')")
measure("8.3", "NOT IN, H2 2025, first 100 customers only", "SELECT count(*) FROM customers_big c WHERE c.customerID <= 100 "
        "AND c.customerID NOT IN (SELECT o.customerID FROM orders_big o WHERE o.orderDate >= '2025-07-01')")
measure("8.3", "NOT EXISTS, H2 2025, all 50,000 customers", "SELECT count(*) FROM customers_big c WHERE NOT EXISTS "
        "(SELECT 1 FROM orders_big o WHERE o.customerID = c.customerID AND o.orderDate >= '2025-07-01')")

# ---- 8.4 top-N per group ----
qrn = ("WITH ranked AS (SELECT customerID, orderID, orderTotal, row_number() OVER (PARTITION BY customerID "
       "ORDER BY orderDate DESC, orderID DESC) AS rn FROM orders_big) SELECT count(*), sum(orderTotal) FROM ranked WHERE rn = 1")
qdo = ("SELECT count(*), sum(orderTotal) FROM (SELECT DISTINCT ON (customerID) customerID, orderID, orderTotal "
       "FROM orders_big ORDER BY customerID, orderDate DESC, orderID DESC) AS t")
qlat = ("SELECT count(*), sum(l.orderTotal) FROM customers_big c JOIN LATERAL (SELECT o.orderID, o.orderTotal "
        "FROM orders_big o WHERE o.customerID = c.customerID ORDER BY o.orderDate DESC, o.orderID DESC LIMIT 1) AS l ON true")
measure("8.4", "row_number(), no index", qrn)
measure("8.4", "DISTINCT ON, no index", qdo)
x("CREATE INDEX m_latest ON orders_big (customerID, orderDate DESC, orderID DESC)")
x("ANALYZE orders_big")
measure("8.4", "LATERAL ... LIMIT 1, with the index", qlat)
measure("8.4", "DISTINCT ON, with the index", qdo)
measure("8.4", "row_number(), with the index", qrn)
x("DROP INDEX m_latest")
x("ANALYZE orders_big")

# ---- 3.3 / 3.4 stale statistics ----
x("SELECT setseed(0.7)")
x("""INSERT INTO orders_big
SELECT 5000000 + i, c + (c - 1) / 24, CASE WHEN online THEN NULL ELSE 1 + floor(random() * 8)::int END,
       DATE '2026-01-01' + floor(random() * 31)::int, TIME '08:00' + floor(random() * 50400) * INTERVAL '1 second',
       CASE WHEN online THEN 'online' ELSE 'in_store' END, 'card', 'completed', NULL, NULL,
       round((15 + 2500 * random() ^ 3)::numeric, 2)
FROM (SELECT i, 1 + floor(random() * 48000)::int AS c, random() < 0.33 AS online
      FROM generate_series(1, 200000) AS i) AS s""")
qcity = ("SELECT c.city, count(*), sum(o.orderTotal) FROM orders_big o JOIN customers_big c ON c.customerID = o.customerID "
         "WHERE o.orderDate >= '2026-01-01' GROUP BY c.city")
measure("3.3", "January by city, stale statistics", qcity)
x("ANALYZE orders_big")
measure("3.4", "January by city, after ANALYZE", qcity)
x("DELETE FROM orders_big WHERE orderID > 5000000")
x("VACUUM ANALYZE orders_big")

# ---- 4.3 completed: seq vs forced index ----
x("CREATE INDEX m_status ON orders_big (status)")
qcomp = "SELECT count(*), sum(orderTotal) FROM orders_big WHERE status = 'completed'"
measure("4.3", "completed, planner's choice", qcomp)
x("SET enable_seqscan = off")
measure("4.3", "completed, Seq Scan disabled", qcomp)
x("SET enable_bitmapscan = off")
measure("4.3", "completed, Seq and Bitmap disabled", qcomp)
x("RESET enable_seqscan; RESET enable_bitmapscan")
x("DROP INDEX m_status")

# ---- 5.4 write cost ----
x("CREATE TABLE orders_load (LIKE orders_big) WITH (autovacuum_enabled = off)")
qload = "INSERT INTO orders_load SELECT * FROM orders_big WHERE orderID <= 1000000"
for n, idx in ((0, []), (1, ["customerID"]), (5, ["customerID", "orderDate", "status", "employeeID", "orderTotal"])):
    for c in idx:
        x(f"CREATE INDEX ON orders_load ({c})")
    times = []
    for _ in range(3):
        x("TRUNCATE orders_load")
        j = conn.execute("EXPLAIN (ANALYZE, FORMAT JSON) " + qload).fetchone()[0]
        j = j[0] if isinstance(j, list) else json.loads(j)[0]
        times.append(j["Execution Time"])
    rows_out.append(("4.4", f"INSERT 1,000,000 rows, {n} indexes", "ModifyTable", None, times, statistics.median(times), 0.0))
    print(f"4.4   INSERT 1M rows, {n} indexes {statistics.median(times):10.2f} ms", flush=True)
    for c in idx:
        x(f"DROP INDEX IF EXISTS orders_load_{c.lower()}_idx")
x("DROP TABLE orders_load")

# ---- 5.5 ORDER BY LIMIT ----
qtop = "SELECT orderID, orderDate, orderTotal FROM orders_big ORDER BY orderTotal DESC, orderID LIMIT 10"
measure("5.5", "ten biggest orders, no index", qtop)
x("CREATE INDEX m_total ON orders_big (orderTotal DESC, orderID)")
measure("5.5", "ten biggest orders, index on orderTotal", qtop)
x("DROP INDEX m_total")

# ---- 6.1 composite, second column alone ----
qday = "SELECT * FROM orders_big WHERE orderDate = '2025-12-01'"
measure("6.1", "orderDate alone, no index", qday)
x("CREATE INDEX m_cd ON orders_big (customerID, orderDate)")
measure("6.1", "orderDate alone, (customerID, orderDate) index", qday)
x("DROP INDEX m_cd")
x("CREATE INDEX m_d ON orders_big (orderDate)")
measure("6.1", "orderDate alone, orderDate index", qday)

# ---- 7.1 function on the column vs range ----
measure("7.1", "June 2025 via date_trunc", "SELECT count(*), sum(orderTotal) FROM orders_big WHERE date_trunc('month', orderDate) = '2025-06-01'")
measure("7.1", "June 2025 via range", "SELECT count(*), sum(orderTotal) FROM orders_big WHERE orderDate >= '2025-06-01' AND orderDate < '2025-07-01'")
x("DROP INDEX m_d")

# ---- 6.2 partial ----
x("CREATE INDEX m_ret ON orders_big (orderDate) WHERE status = 'returned'")
measure("6.2", "returned since Dec 2025, partial index", "SELECT count(*), sum(orderTotal) FROM orders_big WHERE status = 'returned' AND orderDate >= '2025-12-01'")
measure("6.2", "returned+cancelled since Dec 2025 (not covered)", "SELECT count(*), sum(orderTotal) FROM orders_big WHERE status IN ('returned', 'cancelled') AND orderDate >= '2025-12-01'")
x("DROP INDEX m_ret")

# ---- Part 9 ----
x("""CREATE TABLE orders_big_part (LIKE orders_big INCLUDING DEFAULTS INCLUDING CONSTRAINTS) PARTITION BY RANGE (orderDate)""")
for y in (2023, 2024, 2025):
    x(f"CREATE TABLE orders_big_part_{y} PARTITION OF orders_big_part FOR VALUES FROM ('{y}-01-01') TO ('{y + 1}-01-01')")
x("INSERT INTO orders_big_part SELECT * FROM orders_big")
x("VACUUM ANALYZE orders_big_part")
qjune = " WHERE orderDate >= '2025-06-01' AND orderDate < '2025-07-01'"
measure("9.3", "June 2025, orders_big (no index)", "SELECT count(*), sum(orderTotal) FROM orders_big" + qjune)
measure("9.3", "June 2025, orders_big_part (pruned)", "SELECT count(*), sum(orderTotal) FROM orders_big_part" + qjune)
measure("9.4", "2025 via extract(year), partitioned", "SELECT count(*), sum(orderTotal) FROM orders_big_part WHERE extract(year FROM orderDate) = 2025")
measure("9.4", "2025 via range, partitioned", "SELECT count(*), sum(orderTotal) FROM orders_big_part WHERE orderDate >= '2025-01-01' AND orderDate < '2026-01-01'")
x("CREATE TABLE orders_big_daily (LIKE orders_big) PARTITION BY RANGE (orderDate)")
x("""DO $$
DECLARE d date;
BEGIN
    FOR d IN SELECT generate_series(DATE '2023-01-01', DATE '2025-12-31', INTERVAL '1 day')::date LOOP
        EXECUTE format('CREATE TABLE orders_big_daily_%s PARTITION OF orders_big_daily FOR VALUES FROM (%L) TO (%L)',
                       to_char(d, 'YYYYMMDD'), d, d + 1);
    END LOOP;
END $$""")
x("INSERT INTO orders_big_daily SELECT * FROM orders_big")
x("VACUUM ANALYZE orders_big_daily")
qn = "SELECT count(*), sum(orderTotal) FROM {} WHERE customerID = 4242"
measure("9.7", "Nane's orders, 3 yearly partitions", qn.format("orders_big_part"))
measure("9.7", "Nane's orders, 1,096 daily partitions", qn.format("orders_big_daily"))
qd = "SELECT count(*), sum(orderTotal) FROM {} WHERE orderDate = '2025-06-15'"
measure("9.7", "one day, 3 yearly partitions", qd.format("orders_big_part"))
measure("9.7", "one day, 1,096 daily partitions", qd.format("orders_big_daily"))
x("DROP TABLE orders_big_daily")
measure("9.8", "DELETE 2023 from orders_big (rolled back)", "DELETE FROM orders_big WHERE orderDate < '2024-01-01'", rollback=True)
timed("8.8", "DROP TABLE orders_big_part_2023 (a partition)", "DROP TABLE orders_big_part_2023",
      setup=["DROP TABLE IF EXISTS orders_big_part_2023",
             "CREATE TABLE orders_big_part_2023 PARTITION OF orders_big_part FOR VALUES FROM ('2023-01-01') TO ('2024-01-01')",
             "INSERT INTO orders_big_part SELECT * FROM orders_big WHERE orderDate < '2024-01-01'"])
x("DROP TABLE orders_big_part")
x("VACUUM ANALYZE orders_big")

# ---- write the table ----
out = SP_OUT = Path(__file__).resolve().parent / f"measurements-pg{ver.split('.')[0]}.md"
cpu = "unknown CPU"
try:
    cpu = [l.split(":", 1)[1].strip() for l in open("/proc/cpuinfo") if l.startswith("model name")][0]
except Exception:
    pass
lines = [
    f"# Lecture 7 timings — PostgreSQL {ver}",
    "",
    f"Generated by `build/measure.py` on {time.strftime('%Y-%m-%d')} ({cpu}; Docker postgres:{ver.split('.')[0]}, "
    "default settings except max_parallel_workers_per_gather = 0 and jit = off). Each query ran 3 times in a row "
    "as EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON); \"pages\" = shared hit + read at the top node, last run. "
    "Times are one machine's: compare the ratios and the plans, not the milliseconds.",
    "",
    "| Part | Query | Key plan node | Pages | Runs (ms) | Median (ms) | Median planning (ms) |",
    "|---|---|---|---:|---|---:|---:|",
]
for part, label, node, pages, exe, med, pl in rows_out:
    runs = ", ".join(f"{e:,.2f}" for e in exe)
    pg = f"{pages:,}" if pages is not None else ""
    lines.append(f"| {part} | {label} | {node} | {pg} | {runs} | {med:,.2f} | {pl:,.2f} |")
out.write_text("\n".join(lines) + "\n")
print("wrote", out)
