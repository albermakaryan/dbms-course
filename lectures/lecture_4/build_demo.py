#!/usr/bin/env python3
"""
Assemble lecture-04-demo.sql: every statement of the lecture in one
runnable file, each followed by its real result.

    python3 build_demo.py --port 5436      # needs a running PostgreSQL

Parts:
  0  steps/00-setup.sql
  1  data models: the physical level (\\d orders)
  2  order_items: the junction table Lecture 2 deferred, now loaded
  3  JOINs: steps/01..12 and 15 (13 and 14 are held back this term)
  4  build a star, one fact row per order LINE
  5  verification drill

The script creates a fresh database, runs the assembled file statement
by statement, and writes each statement's output under it as a comment
(full output for up to 6 rows, otherwise the row count).
"""
import argparse, os, re, subprocess
from pathlib import Path

HERE = Path(__file__).parent
STEPS = [f"{n:02d}" for n in range(1, 13)] + ["15"]

def banner(title, note):
    return f"\n\n\n-- ============================================================\n-- Lecture 4 — {title}\n-- {note}\n-- ============================================================\n\n"

PART1 = """-- ---- The physical level: how this engine stores orders ----
-- Exact types, constraints, defaults -- and the primary-key index
-- PostgreSQL built by itself (orders_pkey).
\\d orders
"""

PART2 = """-- ---- order_items: the table Lecture 2 deferred ----
-- An order can hold several products. orders is now the HEADER (one row
-- per order); the products sit on the LINES, one row per product in an
-- order, keyed by (orderID, productID).
SELECT count(*) AS orders FROM orders;

SELECT count(*) AS lines FROM order_items;

-- How many lines do orders have?
SELECT lines, count(*) AS orders
FROM (SELECT orderID, count(*) AS lines FROM order_items GROUP BY orderID) AS t
GROUP BY lines
ORDER BY lines;

-- The order total is the sum of its lines -- checked, not assumed:
SELECT count(*) AS orders_where_total_disagrees
FROM orders o
JOIN (SELECT orderID, sum(lineTotal) AS lines_total FROM order_items GROUP BY orderID) AS l
  ON l.orderID = o.orderID
WHERE o.orderTotal <> l.lines_total;
"""

PART4 = """DROP TABLE IF EXISTS fact_sales, dim_date, dim_customer, dim_product, dim_employee;

-- ---- Dimensions: the context ----
CREATE TABLE dim_date AS
SELECT d::date                        AS dateKey,
       EXTRACT(quarter FROM d)::int   AS quarter,
       EXTRACT(month FROM d)::int     AS month,
       to_char(d, 'Mon')              AS monthName,
       EXTRACT(isodow FROM d)::int    AS dayOfWeek,
       to_char(d, 'Dy')               AS dayName
FROM generate_series(DATE '2024-01-01', DATE '2024-12-31', INTERVAL '1 day') AS d;

ALTER TABLE dim_date ADD PRIMARY KEY (dateKey);

CREATE TABLE dim_customer AS
SELECT customerID                         AS customerKey,
       firstName || ' ' || lastName       AS customerName,
       city,
       EXTRACT(year FROM signupDate)::int AS signupYear
FROM customers;

CREATE TABLE dim_product AS
SELECT productID AS productKey, productName, brand, category
FROM products;

ALTER TABLE dim_customer ADD PRIMARY KEY (customerKey);
ALTER TABLE dim_product  ADD PRIMARY KEY (productKey);

CREATE TABLE dim_employee AS
SELECT e.employeeID                                          AS employeeKey,
       e.firstName || ' ' || e.lastName                      AS employeeName,
       e.branch,
       coalesce(m.firstName || ' ' || m.lastName, '(none)')  AS managerName
FROM employees e
LEFT JOIN employees m ON m.employeeID = e.managerID;

-- The unknown member: online orders get employee key 0, never NULL.
INSERT INTO dim_employee VALUES (0, '(online)', 'Online', '(none)');

ALTER TABLE dim_employee ADD PRIMARY KEY (employeeKey);

-- ---- The fact table. Grain: one row per order LINE ----
-- One row per product in an order, so revenue can be split by product
-- and category. Order-level columns (date, customer, employee, status)
-- are copied onto each of the order's lines.
CREATE TABLE fact_sales AS
SELECT o.orderID,
       i.productID                 AS productKey,
       o.orderDate                 AS dateKey,
       o.customerID                AS customerKey,
       coalesce(o.employeeID, 0)   AS employeeKey,
       o.channel,
       o.status,
       i.quantity,
       i.lineTotal                 AS revenue,
       i.quantity * p.cost         AS cost
FROM orders o
JOIN order_items i ON i.orderID   = o.orderID
JOIN products    p ON p.productID = i.productID;

ALTER TABLE fact_sales
    ADD PRIMARY KEY (orderID, productKey),
    ADD FOREIGN KEY (dateKey)     REFERENCES dim_date,
    ADD FOREIGN KEY (customerKey) REFERENCES dim_customer,
    ADD FOREIGN KEY (productKey)  REFERENCES dim_product,
    ADD FOREIGN KEY (employeeKey) REFERENCES dim_employee;

-- ---- Check the build: same money as the source tables ----
SELECT count(*) AS fact_rows,
       count(DISTINCT orderID) AS orders,
       sum(revenue) FILTER (WHERE status = 'completed') AS completed_revenue
FROM fact_sales;

-- ---- Completed revenue per branch, per quarter: plain inner joins ----
SELECT e.branch,
       sum(f.revenue) FILTER (WHERE d.quarter = 1) AS q1,
       sum(f.revenue) FILTER (WHERE d.quarter = 2) AS q2,
       sum(f.revenue) FILTER (WHERE d.quarter = 3) AS q3,
       sum(f.revenue) FILTER (WHERE d.quarter = 4) AS q4,
       sum(f.revenue)                              AS total
FROM fact_sales f
JOIN dim_date     d ON d.dateKey     = f.dateKey
JOIN dim_employee e ON e.employeeKey = f.employeeKey
WHERE f.status = 'completed'
GROUP BY e.branch
ORDER BY total DESC;

-- ---- Margin by category, Saturdays vs the whole year (line grain) ----
SELECT p.category,
       sum(f.revenue - f.cost) FILTER (WHERE d.dayName = 'Sat') AS sat_margin,
       sum(f.revenue - f.cost)                                  AS year_margin
FROM fact_sales f
JOIN dim_date    d ON d.dateKey    = f.dateKey
JOIN dim_product p ON p.productKey = f.productKey
WHERE f.status = 'completed'
GROUP BY p.category
ORDER BY year_margin DESC
LIMIT 5;
"""

PART5 = """-- Each query runs without error and returns a believable answer.
-- Each one is wrong. Name the problem before reading the answers.

-- Q1. "Total completed revenue for 2024, with who sold it."
SELECT sum(o.orderTotal) AS revenue
FROM orders o
JOIN employees e ON e.employeeID = o.employeeID
WHERE o.status = 'completed';

-- Q2. "Customers with the fewest orders: who needs a reminder email?"
SELECT c.firstName, c.lastName, count(*) AS orders
FROM customers c
LEFT JOIN orders o ON o.customerID = c.customerID
GROUP BY c.customerID, c.firstName, c.lastName
HAVING count(*) <= 5
ORDER BY orders, c.lastName;

-- Q3. "Completed revenue for every product category, including those with none."
SELECT p.category, coalesce(sum(i.lineTotal), 0) AS revenue
FROM products p
LEFT JOIN order_items i ON i.productID = p.productID
LEFT JOIN orders      o ON o.orderID   = i.orderID
WHERE o.status = 'completed'
GROUP BY p.category;

-- Q4. "Average lifetime spend of the customers who bought in December."
SELECT round(avg(c.moneySpent), 2) AS avg_spend
FROM customers c
JOIN orders o ON o.customerID = c.customerID
WHERE o.orderDate BETWEEN '2024-12-01' AND '2024-12-31';

-- ---- Answers ----
-- Q1: the inner join dropped the 181 online orders. Without the join:
SELECT sum(orderTotal) AS revenue FROM orders WHERE status = 'completed';

-- Q2: count(*) counted the empty match. Count the right table's key:
SELECT c.firstName, c.lastName, count(o.orderID) AS orders
FROM customers c
LEFT JOIN orders o ON o.customerID = c.customerID
GROUP BY c.customerID, c.firstName, c.lastName
HAVING count(o.orderID) <= 5
ORDER BY orders, c.lastName;

-- Q3: WHERE undid the LEFT JOIN. Decide what counts as a match first:
SELECT p.category, coalesce(sum(i.lineTotal), 0) AS revenue
FROM products p
LEFT JOIN (order_items i
           JOIN orders o ON o.orderID = i.orderID
                        AND o.status  = 'completed')
       ON i.productID = p.productID
GROUP BY p.category;

-- Q4: fan-out -- one row per December ORDER, so big buyers count
-- several times. Pick each customer once:
SELECT round(avg(moneySpent), 2) AS avg_spend, count(*) AS customers
FROM customers
WHERE customerID IN (SELECT customerID FROM orders
                     WHERE orderDate BETWEEN '2024-12-01' AND '2024-12-31');
"""

HEADER = """-- ============================================================
-- Lecture 4 — Putting the Tables Back Together
-- YSU, Data Science for Business
--
-- Every statement of the lecture in one runnable file, each followed by
-- its result. Data models, the order_items junction table, JOIN in
-- detail (cross, inner, aliases, USING/NATURAL, left/right/full,
-- anti-join, WHERE vs ON, self, wrong key, fan-out, range joins,
-- GROUP BY), a star schema at line grain, and a verification drill.
--
-- Data: Lecture 5's shop -- an order can hold several products
-- (600 orders, 965 lines) -- plus the flat sales file, one row per line.
--
-- Run from the lecture_4/ folder so the \\copy paths resolve:
--     psql postgres
--     \\i lecture-04-demo.sql
-- Three statements error ON PURPOSE -- the comments say which.
-- Generated by build_demo.py from steps/ -- edit those, not this file.
-- ============================================================
"""

def assemble():
    out = [HEADER, banner("Part 0: load the data", "Creates the lecture04 database if missing, and connects to it."),
           (HERE / "steps/00-setup.sql").read_text()]
    out += [banner("Part 1: data models", "Run after Part 0."), PART1]
    out += [banner("Part 2: order_items, the junction table", "Run after Part 0."), PART2]
    out += [banner("Part 3: JOINs, step by step", "The files steps/01 ... steps/15, in order. Read-only.")]
    for s in STEPS:
        f = next((HERE / "steps").glob(f"{s}-*.sql"))
        out += ["\n\n\n", f.read_text()]
    out += [banner("Part 4: build a star (one fact row per order line)", "Creates the star schema (safe to re-run)."), PART4]
    out += [banner("Part 5: verification drill", "Read-only."), PART5]
    return "".join(out)

def statements(text):
    """Split into (start, end) spans of statements: lines up to a ';' at line end, or a backslash command line."""
    lines = text.split("\n")
    spans, start = [], None
    for k, l in enumerate(lines):
        s = l.strip()
        if start is None:
            if not s or s.startswith("--"):
                continue
            start = k
        if s.startswith("\\") or s.rstrip().endswith(";") and not s.startswith("--"):
            spans.append((start, k))
            start = None
    return lines, spans

def summarize(output):
    out = [l.rstrip() for l in output.strip("\n").split("\n") if l.strip() and "NOTICE:" not in l]
    if not out:
        return []
    err = [l for l in out if "ERROR:" in l or l.startswith("HINT:")]
    if err:
        return [re.sub(r"^psql:[^:]*:\d+: ", "", l) for l in err]
    m = re.match(r"\((\d+) rows?\)", out[-1])
    if m:
        n = int(m.group(1))
        body = out[:-1]
        if n <= 6 and all(len(l) <= 110 for l in body):
            return body
        return body[:2] + [f"... {n} rows"]
    return out[:6]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True)
    a = ap.parse_args()
    env = dict(os.environ, PGPASSWORD="secret")
    base = ["psql", "-X", "-h", "localhost", "-p", a.port, "-U", "postgres"]
    subprocess.run(base + ["-d", "postgres", "-qc", "DROP DATABASE IF EXISTS lecture04"], env=env, check=True)
    text = assemble()
    lines, spans = statements(text)
    # psql session per statement keeps outputs separable; \c in setup is handled by
    # running the setup file once, then everything else in lecture04.
    setup_end = text.split("\n").index("UNION ALL SELECT 'order_items', count(*) FROM order_items;")
    r = subprocess.run(base + ["-d", "postgres", "-q", "-f", str(HERE / "steps/00-setup.sql")],
                       env=env, capture_output=True, text=True, cwd=HERE)
    assert "ERROR" not in r.stderr, r.stderr
    results = {}
    for (s, e) in spans:
        if e <= setup_end:
            continue
        stmt = "\n".join(lines[s:e + 1])
        r = subprocess.run(base + ["-d", "lecture04", "-P", "footer=on"], input=stmt, env=env,
                           capture_output=True, text=True, cwd=HERE)
        if stmt.strip().startswith("\\d"):
            continue
        results[e] = summarize(r.stdout + r.stderr)
    final = []
    for k, l in enumerate(lines):
        final.append(l)
        if k in results and results[k]:
            final += ["-- " + x for x in results[k]]
    (HERE / "lecture-04-demo.sql").write_text("\n".join(final).rstrip("\n") + "\n")
    print(f"{len(spans)} statements; {sum(1 for v in results.values() if any('ERROR' in x for x in v))} errors on purpose")

if __name__ == "__main__":
    main()
