#!/usr/bin/env python3
"""
Generate lecture-04-notebook.py (a marimo notebook) from lecture-04-demo.sql.

    python3 build_notebook.py                 # writes lecture-04-notebook.py
    python3 build_notebook.py --verify OUT.py # also writes a VERIFY copy whose
                                              # SQL cells return their DataFrames

The notebook follows lecture-04-notes.md (Parts 1-5, 4.0-4.14) and the model
of ../lecture_5/lecture-05-notebook.py. Every SQL cell's text is copied
VERBATIM from lecture-04-demo.sql, chosen by a unique snippet. The script
fails if a snippet matches no statement or several distinct statements, if a
demo statement (after the setup part) never appears, if a SQL or error cell is
not directly preceded by its own markdown cell, or if SQL contains { or }.
Two queries replace psql's \\d orders (meta-commands can't run in a notebook);
they are the only SQL not taken from the demo.

Steps 13 and 14 (document join, lossless proof) are held back this term and
are not in the demo, so they are not in the notebook either.

The instructor edits the notebook in marimo directly. Before regenerating,
diff the current lecture-04-notebook.py against the previous generated
version and carry their changes over (e.g. into this script).
"""
import argparse, re, sys
from pathlib import Path

HERE = Path(__file__).parent
DEMO = (HERE / "lecture-04-demo.sql").read_text().split("\n")

# ---- statements of the demo -------------------------------------------------
def demo_statements():
    stmts, s = [], None
    part1 = next(i for i, l in enumerate(DEMO) if "Part 1: data models" in l)
    for k, line in enumerate(DEMO):
        t = line.strip()
        if s is None:
            if not t or t.startswith("--"):
                continue
            s = k
        if t.startswith("\\") or (t.endswith(";") and not t.startswith("--")):
            text = "\n".join(DEMO[s:k + 1]).rstrip()
            if text.endswith(";"):
                text = text[:-1]
            stmts.append({"text": text, "after_setup": s > part1, "meta": t.startswith("\\")})
            s = None
    return stmts

STMTS = demo_statements()
DISTINCT = {}
for st in STMTS:
    DISTINCT.setdefault(st["text"], st)

PROBLEMS = []

def pick(snippet):
    hits = [t for t in DISTINCT if snippet in t]
    if len(hits) > 1 and snippet in DISTINCT:      # an exact full statement wins a tie
        hits = [snippet]
    if len(hits) != 1:
        PROBLEMS.append(f"snippet {snippet!r} matches {len(hits)} distinct demo statements")
        return snippet
    if "{" in hits[0] or "}" in hits[0]:
        sys.exit(f"braces in SQL: {snippet!r}")
    return hits[0]

# ---- cell list ----------------------------------------------------------------
CELLS = []
def md(text): CELLS.append(("md", text.strip("\n")))
def sql(name, snippet): CELLS.append(("sql", name, pick(snippet)))
def raw_sql(name, text): CELLS.append(("sql", name, text.strip("\n")))   # not from the demo: replaces \d
def err(snippet): CELLS.append(("err", pick(snippet)))
def mermaid(text): CELLS.append(("mermaid", text.strip("\n")))

md(r"""
# Lecture 4 — Putting the Tables Back Together

The JOIN lecture, one query at a time: what a join really is (every pair, then the pairs you want), every join type, and the traps that return a normal-looking table with the wrong answer. Plus the two schema ideas around it: the three levels of a data model, and a star schema built on top of the normal tables.

**The data:** the shop from Lecture 3, where an order can hold several products. `orders` is the header (one row per order), `order_items` the lines (one row per product in an order), and `sales` is the flat file — one row per order line, with everything written out on every row. 600 orders, 965 lines.

**Before you run this:** from the `lecture_4/` folder, run `psql postgres` and `\i steps/00-setup.sql`. It creates the `lecture04` database if it doesn't exist and loads the six tables (`\copy` only works in psql, so loading can't happen here). Then start the notebook with the connection string in `LECTURE04_DSN`, e.g.

```
LECTURE04_DSN=postgresql://postgres:postgres@localhost:5432/lecture04 marimo edit lecture-04-notebook.py
```

Each trap appears as **wrong query → what's wrong with it → fixed query**, with real results on screen at each step. Errors on purpose are caught and shown as red boxes, so the notebook runs top to bottom.
""")
CELLS.append(("imports",))
CELLS.append(("connect",))

md(r"""
## The data: six tables

`orders` holds what is true once per order (who, when, status, `orderTotal`); `order_items` holds one row per product in the order, keyed by `(orderID, productID)`. Employees point at their manager through `managerID`; online orders have no employee.
""")
mermaid(r"""
erDiagram
    CUSTOMERS ||--o{ ORDERS      : places
    EMPLOYEES |o--o{ ORDERS      : "serves (none if online)"
    EMPLOYEES |o--o{ EMPLOYEES   : manages
    ORDERS    ||--|{ ORDER_ITEMS : "has 1 or more lines"
    PRODUCTS  ||--o{ ORDER_ITEMS : "appears on"
    ORDERS {
        int orderID PK
        int customerID FK
        int employeeID FK "NULL = online"
        date orderDate
        text status
        decimal orderTotal "sum of its lineTotals"
    }
    ORDER_ITEMS {
        int orderID PK, FK
        int productID PK, FK
        int quantity
        decimal unitPrice
        decimal lineTotal
    }
    PRODUCTS {
        int productID PK
        text productName
        text category
    }
    CUSTOMERS {
        int customerID PK
        text firstName
        text email
    }
    EMPLOYEES {
        int employeeID PK
        int managerID FK
        text branch
    }
""")
md(r"""
**And the flat file.** `sales` is the same facts as one wide sheet: one row per order line, with the order, the customer, the employee and the product written out on every row — 30 columns. It's what the tables above look like joined back together, and three traps in Part 4 use it.
""")
mermaid(r"""
erDiagram
    SALES {
        int orderID "order header, repeated on each line"
        text status
        decimal orderTotal "the WHOLE order's total"
        int quantity "this line"
        decimal lineTotal "this line"
        text customerFirstName "customer, repeated"
        text customerEmail
        text employeeBranch "empty if online"
        text productName "product"
        text productCategory
    }
""")
md(r"""
**Check the data first.** One count per table: you should see **965** for `sales` and `order_items`, **30** customers, **8** employees, **37** products and **600** orders.
""")
sql("p0_counts", "SELECT 'sales' AS t, count(*) FROM sales")
md(r"""
### The junction table Lecture 2 deferred

Lecture 2 drew `order_items` in an aside and put it off. Here it is. First, the headers: **600** orders.
""")
sql("p0_orders", "SELECT count(*) AS orders FROM orders")
md(r"""
And the lines: **965** — more lines than orders, because an order can hold several products.
""")
sql("p0_lines", "SELECT count(*) AS lines FROM order_items")
md(r"""
How many lines do orders have? **365** orders hold one product; **133** hold two, **74** three, **28** four.
""")
sql("p0_lines_per_order", "SELECT lines, count(*) AS orders")
md(r"""
The order total is the sum of its lines — checked, not assumed. Expect **0** orders that disagree.
""")
sql("p0_totals_check", "AS orders_where_total_disagrees")

# ---- Part 1 -------------------------------------------------------------------
md(r"""
## Part 1 — Three levels of a data model

1. **Conceptual** — entities and relationships, no tables yet: "A customer places orders. An order holds one or more products. An employee may serve an order — or nobody does, if it's online."
2. **Logical** — tables, columns, keys, constraints, still DBMS-agnostic: `orders.customerID` is a required foreign key; `orders.employeeID` is optional.
3. **Physical** — how one engine stores it. In psql, `\d orders` shows this level. psql commands can't run in a notebook, so here are two catalog queries that show the same thing. First the exact types: **11** columns.
""")
raw_sql("p1_orders_columns", """
SELECT column_name, data_type, numeric_precision, numeric_scale, is_nullable
FROM information_schema.columns
WHERE table_name = 'orders'
ORDER BY ordinal_position
""")
md(r"""
Then the indexes. Nobody asked for one, but PostgreSQL built **orders_pkey** to enforce the primary key — a purely physical decision.
""")
raw_sql("p1_orders_indexes", """
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'orders'
""")
md(r"""
**Why the levels matter:** mistakes at the conceptual level are cheap — erase a box, redraw an arrow. Mistakes at the physical level are expensive — a `VARCHAR(50)` that turns out too short, or a `SERIAL` that should have been `BIGINT`, means an `ALTER TABLE` on live data (Lecture 2, Part 9). The further right you move, the more a change costs.
""")

# ---- Part 2 -------------------------------------------------------------------
md(r"""
## Part 2 — Dimensional modeling: facts, dimensions, grain

A second, purpose-built schema you build *alongside* the normal tables, when the question shifts from "record what happened" to "summarize everything so far".

- **Fact table** = an event, with numbers attached. Here `fact_sales`: one row per order line, holding `quantity`, `revenue`, `cost` and a key to each dimension.
- **Dimension table** = the context: who, what, where, when — `dim_date`, `dim_customer`, `dim_product`, `dim_employee`.
- **Grain** = the one-sentence definition of what a fact row *is*, decided first: **one row = one order line**.

**The next cells change the database:** they create five tables. Each is safe to re-run — the first one drops all five if they exist.
""")
md(r"""
Drop the star schema if an earlier run built it.
""")
sql("p2_drop_star", "DROP TABLE IF EXISTS fact_sales, dim_date, dim_customer, dim_product, dim_employee")
md(r"""
`dim_date`: generated once with `generate_series` — every day of 2024 (a leap year, so 366 days) with quarter, month and day name computed as columns, so no query ever recomputes them.
""")
sql("p2_dim_date", "CREATE TABLE dim_date AS")
md(r"""
Give `dim_date` its primary key.
""")
sql("p2_dim_date_pk", "ALTER TABLE dim_date ADD PRIMARY KEY (dateKey)")
md(r"""
`dim_customer`: one row per customer, with the labels you group by.
""")
sql("p2_dim_customer", "CREATE TABLE dim_customer AS")
md(r"""
`dim_product`: one row per product.
""")
sql("p2_dim_product", "CREATE TABLE dim_product AS")
md(r"""
Primary key for `dim_customer`.
""")
sql("p2_dim_customer_pk", "ALTER TABLE dim_customer ADD PRIMARY KEY (customerKey)")
md(r"""
Primary key for `dim_product`.
""")
sql("p2_dim_product_pk", "ALTER TABLE dim_product  ADD PRIMARY KEY (productKey)")
md(r"""
`dim_employee`: the self-join from Part 4 runs once here, so the manager's name sits on each row.
""")
sql("p2_dim_employee", "CREATE TABLE dim_employee AS")
md(r"""
**The unknown-member trick.** Online orders have no employee. Instead of carrying that NULL into the fact table, add one row that stands for "nobody": key 0, `'Online'`. Every fact row then has a valid employee key — so joins to `dim_employee` never need a LEFT JOIN.
""")
sql("p2_unknown_member", "INSERT INTO dim_employee VALUES")
md(r"""
Primary key for `dim_employee`.
""")
sql("p2_dim_employee_pk", "ALTER TABLE dim_employee ADD PRIMARY KEY (employeeKey)")
md(r"""
`fact_sales`, at line grain: one row per product in an order. `coalesce(o.employeeID, 0)` points online orders at the unknown member.
""")
sql("p2_fact_sales", "CREATE TABLE fact_sales AS")
md(r"""
Keys: the fact's primary key is `(orderID, productKey)`, and each dimension key is a foreign key.
""")
sql("p2_fact_keys", "ADD PRIMARY KEY (orderID, productKey)")

# ---- Part 3 -------------------------------------------------------------------
md(r"""
## Part 3 — Star vs. snowflake

**Star:** one fact table, each dimension attached directly and flat. This is what Part 2 just built.
""")
mermaid(r"""
erDiagram
    DIM_DATE     ||--o{ FACT_SALES : "when"
    DIM_CUSTOMER ||--o{ FACT_SALES : "who bought"
    DIM_PRODUCT  ||--o{ FACT_SALES : "what"
    DIM_EMPLOYEE ||--o{ FACT_SALES : "who sold"
    FACT_SALES {
        int orderID PK
        int productKey PK, FK
        date dateKey FK
        int customerKey FK
        int employeeKey FK "0 = Online"
        int quantity
        decimal revenue
        decimal cost
    }
    DIM_DATE {
        date dateKey PK
        int quarter
        text dayName
    }
    DIM_PRODUCT {
        int productKey PK
        text productName
        text category
    }
    DIM_EMPLOYEE {
        int employeeKey PK
        text branch
        text managerName
    }
    DIM_CUSTOMER {
        int customerKey PK
        text customerName
        text city
    }
""")
md(r"""
Check the build: **965** fact rows for **600** orders, and completed revenue **157,078.41** — the same money as the source tables.
""")
sql("p3_star_check", "AS fact_rows")
md(r"""
Querying the star is plain inner joins — no LEFT JOIN, no `coalesce`, thanks to the unknown member. Completed revenue per branch and quarter: Online leads with **56,855.93**.
""")
sql("p3_star_branch_quarter", "FILTER (WHERE d.quarter = 1) AS q1")
md(r"""
Line grain makes product questions easy: margin by category, Saturdays vs. the year. Laptops earn **9472.00** over the year.
""")
sql("p3_star_margin", "AS sat_margin")
md(r"""
**Snowflake:** the same idea, but a dimension is normalized into sub-tables — e.g. `dim_product` split into `dim_product` + `dim_category` + `dim_brand`, each joined in turn.
""")
mermaid(r"""
erDiagram
    DIM_CATEGORY ||--o{ DIM_PRODUCT : groups
    DIM_BRAND    ||--o{ DIM_PRODUCT : makes
    DIM_PRODUCT  ||--o{ FACT_SALES  : "what"
    DIM_DATE     ||--o{ FACT_SALES  : "when"
    FACT_SALES {
        int orderID PK
        int productKey PK, FK
        decimal revenue
    }
    DIM_PRODUCT {
        int productKey PK
        text productName
        int categoryKey FK
        int brandKey FK
    }
    DIM_CATEGORY {
        int categoryKey PK
        text category
    }
    DIM_BRAND {
        int brandKey PK
        text brand
    }
""")
md(r"""
**Default answer: star.** Kimball's guidance is to avoid snowflaking unless you have a specific, concrete reason. Snowflaking buys less redundancy and costs more joins and more tables to navigate — a bad trade most of the time.

One naming gotcha: "Snowflake" is also a warehouse product. The schema shape and the product are unrelated.
""")

# ---- Part 4 -------------------------------------------------------------------
md(r"""
## Part 4 — JOINs, from one idea

### 4.0 The one idea

**A join is: pair up every row of A with every row of B, then keep the pairs you want.** Every join type is a variation on "which pairs do we keep" and "what do we do with the rows that found no pair".
""")
md(r"""
### 4.1 CROSS JOIN — start here, not last

Every row of `orders` paired with every row of `customers`: 600 × 30 = **18000** pairs, most of them nonsense.
""")
sql("p4_cross", "SELECT count(*) FROM orders CROSS JOIN customers")
md(r"""
PostgreSQL defines `CROSS JOIN` as exactly `INNER JOIN ... ON TRUE` — a join whose condition can never fail. Same **18000**.
""")
sql("p4_on_true", "INNER JOIN customers ON TRUE")
md(r"""
The old comma syntax is the same cross product again: **18000**.
""")
sql("p4_comma", "SELECT count(*) FROM orders, customers")
md(r"""
Zoom in: 3 orders × 3 customers = **9** pairs. In each, compare "order says" with "customer row" — only some pairs are true.
""")
sql("p4_nine_pairs", "ORDER BY o.orderID, c.customerID")
md(r"""
Keep only the pairs where the ids match: **3** rows. That *is* a join — every pair, filtered.
""")
sql("p4_three_pairs", "AND o.customerID = c.customerID")
md(r"""
The same **3** rows written as `JOIN ... ON` — cleaner syntax, nothing more mysterious.
""")
sql("p4_join_on", "SELECT o.orderID, c.firstName, c.lastName, o.orderTotal")

md(r"""
### 4.2 INNER JOIN — keeps only the pairs that match

Every order has exactly one customer, so this keeps one row per order: **600**.
""")
sql("p4_orders_customers", "SELECT count(*)\nFROM orders o\nJOIN customers c ON c.customerID = o.customerID")
md(r"""
Products live on the order **lines**, so reach them through `order_items`. Order 1001 has one line; order 1009 has three. Look at `ordertotal`: 1009's whole total, **147.76**, sits on every one of its lines.
""")
sql("p4_lines_of_two_orders", "WHERE o.orderID IN (1001, 1009)")
md(r"""
Joining the lines changes what a row is: **965** rows, one per line — not one per order.
""")
sql("p4_all_lines", "SELECT count(*)\nFROM orders o\nJOIN customers   c ON c.customerID = o.customerID")
md(r"""
Back to one row per order, and add employees. Guess first: there are 600 orders. Expect **419**.
""")
sql("p4_with_employees", "JOIN customers c ON c.customerID = o.customerID\nJOIN employees e ON e.employeeID = o.employeeID")
md(r"""
The missing ones are exactly the online orders: **181** of **600** have no employee, and NULL matches nothing.
""")
sql("p4_online_count", "AS online_orders")
md(r"""
**Trap: the inner join that drops the online orders.** "Completed revenue, with who sold it" — someone joins `employees` just to have the names.
""")
sql("p4_trap_revenue_wrong", "SELECT sum(o.orderTotal) AS revenue\nFROM orders o\nJOIN employees e")
md(r"""
**What's wrong:** **100,222.48** is a real sum, correctly computed — over a silently incomplete set of rows. The 181 online orders found no employee, so the inner join dropped them. No error. **Fix:** the question needs no employee data at all — drop the join.
""")
sql("p4_trap_revenue_fixed", "SELECT sum(orderTotal) AS revenue\nFROM orders\nWHERE status = 'completed'")
md(r"""
**157,078.41**: the real completed revenue. An inner join doesn't complain when rows don't match — it just quietly leaves them out.

### 4.3 Aliasing — and the two errors that teach you why it exists

Full table names work: **1001**, Davit, **211.65**.
""")
sql("p4_full_names", "SELECT orders.orderID, customers.firstName")
md(r"""
**Error on purpose:** `customerID` exists in both tables, and the engine refuses to guess — even though the values are equal on every joined row.
""")
err("SELECT orderID, customerID, firstName")
md(r"""
The fix: alias the tables and qualify the columns — `o.customerID`. Davit, customer **2**.
""")
sql("p4_alias_fix", "SELECT o.orderID, o.customerID, c.firstName")
md(r"""
**Error on purpose:** once you write `FROM orders o`, the name `orders` stops existing for the rest of the query. PostgreSQL's hint says exactly that: the alias didn't add a nickname, it replaced the name.
""")
err("SELECT orders.orderID\nFROM orders o")

md(r"""
### 4.4 USING and NATURAL JOIN — convenience with a hidden cost

`USING (customerID)` is shorthand for `ON o.customerID = c.customerID`, and the column appears once in the output: customer **2**, order **1001**.
""")
sql("p4_using", "JOIN customers c USING (customerID)")
md(r"""
**Trap: NATURAL JOIN.** `orders` and `sales` hold the same orders — `sales` has one row per line. What does `NATURAL JOIN` give?
""")
sql("p4_natural_wrong", "SELECT count(*) FROM orders NATURAL JOIN sales")
md(r"""
**What's wrong:** **168** rows, and nothing in the query says why. NATURAL JOIN silently joined on *every* column name the two tables share — not just `orderID`. **Fix:** write the condition you mean.
""")
sql("p4_natural_fixed", "SELECT count(*) FROM orders o JOIN sales s ON s.orderID = o.orderID")
md(r"""
**965** — every line finds its order. Here are the column names NATURAL JOIN used: **9** of them, `deliveryDate` and `rating` among them.
""")
sql("p4_shared_columns", "SELECT column_name FROM information_schema.columns WHERE table_name = 'orders'")
md(r"""
`deliveryDate` is NULL for every in-store order, and `NULL = NULL` is not true. The survivors are the lines of online orders that also got a rating: **168** again. The join condition should always be visible in the code — NATURAL JOIN hides it, and it changes silently when either table gains a matching column.
""")
sql("p4_natural_survivors", "SELECT count(*)\nFROM sales\nWHERE deliveryDate IS NOT NULL")

md(r"""
### 4.5 LEFT / RIGHT / FULL OUTER JOIN — keeping what doesn't match

`LEFT JOIN` keeps every row of the left table; with no match on the right, it fills the right side with NULLs. Orders 1005–1007 are online: they stay, with no employee. **8** rows.
""")
sql("p4_left_sample", "WHERE o.orderID BETWEEN 1001 AND 1008")
md(r"""
All **600** orders survive now — the inner join kept 419.
""")
sql("p4_left_count", "SELECT count(*)\nFROM orders o\nLEFT JOIN employees e ON e.employeeID = o.employeeID")
md(r"""
Give the NULLs a name and the lost revenue comes back: "Online" is the biggest branch, **56,855.93**. The four rows add up to 157,078.41.
""")
sql("p4_left_branches", "SELECT coalesce(e.branch, 'Online') AS branch")
md(r"""
`RIGHT JOIN` is the mirror image: every customer kept. **602** — all 600 orders, plus one NULL-padded row for each of the 2 customers who never ordered.
""")
sql("p4_right", "RIGHT JOIN customers c")
md(r"""
Identical to `customers LEFT JOIN orders`: **602**. This course always writes LEFT, so every query reads the same way.
""")
sql("p4_left_reversed", "SELECT count(*)\nFROM customers c\nLEFT JOIN orders o ON o.customerID = c.customerID")
md(r"""
`FULL JOIN` keeps everything from both sides — the classic tool for reconciling two lists. By name: **28** customers only, **6** employees only, **2** on both lists. Hold on to those 2.
""")
sql("p4_full", "WHEN c.customerID IS NULL THEN 'employee only'")
md(r"""
**The anti-join:** "which X have no Y?" = `LEFT JOIN` + `WHERE right.key IS NULL`. Products never ordered: **1** — productID **35**, Ergonomic Chair Pro, **6** in stock.
""")
sql("p4_anti_products", "LEFT JOIN order_items i ON i.productID = p.productID\nWHERE i.orderID IS NULL")
md(r"""
**Trap: testing a nullable column.** Customers who never ordered — but the test is on `o.rating`, a column that can be NULL in a real row.
""")
sql("p4_anti_nullable_wrong", "WHERE o.rating IS NULL")
md(r"""
**What's wrong:** **280** — far more than the customers who never ordered. Every real order without a rating is NULL there too, so it sneaks in. **Fix:** test the right table's primary key, which is never NULL in a real row.
""")
sql("p4_anti_customers_fixed", "SELECT c.customerID, c.firstName, c.lastName, c.signupDate")
md(r"""
**2** customers: Levon (**24**) and Astghik (**29**). "Which X have no Y" comes up constantly — teach it as a named pattern.

### 4.6 count(*) vs. count(column)

Orders per customer, fewest first, with `count(*)`: Levon shows **1** order.
""")
sql("p4_count_star", "SELECT c.firstName, c.lastName, count(*) AS orders\nFROM customers c\nLEFT JOIN orders o ON o.customerID = c.customerID\nGROUP BY c.customerID, c.firstName, c.lastName\nORDER BY orders, c.lastName\nLIMIT 4")
md(r"""
The LEFT JOIN gave Levon one row full of NULLs, and `count(*)` counts rows. `count(o.orderID)` counts non-NULL values: **0**.
""")
sql("p4_count_column", "SELECT c.firstName, c.lastName, count(o.orderID) AS orders\nFROM customers c\nLEFT JOIN orders o ON o.customerID = c.customerID\nGROUP BY c.customerID, c.firstName, c.lastName\nORDER BY orders, c.lastName\nLIMIT 4")
md(r"""
The reflex after every outer join: both counts side by side. **602** rows, **600** real matches — they differ by exactly the 2 unmatched customers.
""")
sql("p4_count_both", "AS joined_rows")

md(r"""
### 4.7 The WHERE-vs-ON trap — the most important trap in the lecture

`ON` applies while deciding what matches; `WHERE` applies after the whole join, NULL-padding included. Revenue per category, including categories that never sold: **13** rows, Chairs at the bottom.
""")
sql("p4_categories_all", "LEFT JOIN order_items i ON i.productID = p.productID\nGROUP BY p.category\nORDER BY revenue DESC NULLS LAST")
md(r"""
**Trap (right-table half):** the boss adds "completed orders only". The obvious edit puts the status filter in `WHERE`.
""")
sql("p4_where_wrong", "count(i.orderID) AS lines, sum(i.lineTotal) AS revenue\nFROM products p\nLEFT JOIN order_items i ON i.productID = p.productID\nLEFT JOIN orders      o ON o.orderID   = i.orderID\nWHERE")
md(r"""
**What's wrong:** **12** rows — Chairs is gone, no error. The LEFT JOIN kept the Chair row with `o.status` NULL; then WHERE ran, `NULL = 'completed'` is not true, and the row was thrown out. First attempt at a fix: move the condition into the `ON` of the orders join.
""")
sql("p4_on_wrong_join", "AND o.status    = 'completed'")
md(r"""
**Still wrong:** Chairs is back (**13** rows), but Laptops shows **58028.50** — the all-orders revenue again. A line of a returned order still exists; it just gets NULL order columns, and its `lineTotal` is still summed. In a chain of joins, ask *which* join the condition belongs to. **Fix:** decide what counts as a match — a line of a completed order — *before* the LEFT JOIN, in brackets.
""")
sql("p4_on_fixed", "LEFT JOIN (order_items i\n           JOIN orders o ON o.orderID = i.orderID\n                        AND o.status  = 'completed')\n       ON i.productID = p.productID\nGROUP BY p.category\nORDER BY revenue DESC")
md(r"""
**13** rows, Laptops at the real **53412.00**, Chairs at **0.00**. "ON decides who gets invited to the party; WHERE decides who's allowed to stay after it already happened — including the guests the LEFT JOIN invited for free."

**Trap (left-table half):** "Gyumri customers and their orders" — with the left-table condition placed in `ON`.
""")
sql("p4_left_condition_wrong", "AND c.city = 'Gyumri'")
md(r"""
**What's wrong:** **233** rows for **210** matches. A LEFT JOIN keeps *every* left row, so all 30 customers are still there — the Gyumri ones with their orders, plus a NULL-padded row for everyone else. **Fix:** conditions on the left table go in `WHERE`.
""")
sql("p4_left_condition_fixed", "WHERE c.city = 'Gyumri'")
md(r"""
**210** rows, **210** matched: only Gyumri customers. The rule: right-table conditions → `ON`; left-table conditions → `WHERE`.

### 4.8 Self-joins — a table joined to itself

The raw data first: **8** employees. `managerID` points at another row of the same table; Vahe's is NULL.
""")
sql("p4_employees", "SELECT employeeID, firstName, position, branch, managerID")
md(r"""
The reporting line those `managerID`s describe:
""")
mermaid(r"""
flowchart TD
    V["Vahe — Store Manager"] --> G["Gor"]
    V --> A["Ani"]
    V --> H["Hayk — Senior Sales"]
    V --> M["Marine — Senior Sales"]
    H --> N["Nare"]
    H --> L["Lilit"]
    M --> R["Arman"]
""")
md(r"""
**Error on purpose:** the same table twice with no aliases — PostgreSQL can't tell "this row" from "that other row of the same table".
""")
err("SELECT employees.firstName, employees.firstName")
md(r"""
With aliases: `e` plays the employee, `m` the manager. LEFT, or Vahe — who has no manager — would vanish. **8** rows.
""")
sql("p4_self_manager", "m.firstName || ' ' || m.lastName AS manager\nFROM employees e")
md(r"""
A second hop, the manager's manager, for the employees outside Yerevan Center: **5** rows. Two levels up took two joins.
""")
sql("p4_self_two_hops", "AS managers_manager")
md(r"""
Self-join + GROUP BY: direct reports per manager — **3** managers, Vahe with **4**.
""")
sql("p4_self_reports", "AS direct_reports")

md(r"""
### 4.9 Joining on the wrong thing — names are not identifiers

"Which employees also shop with us?" Join customers to employees by name: **2** "matches". Read the birth dates.
""")
sql("p4_names_people", "c.birthDate AS customer_born")
md(r"""
Those are four different people who share two names. No column links a customer to an employee, so the honest answer is: this data can't tell.

Now at scale. The flat file has **965** rows, one per order line.
""")
sql("p4_sales_rows", "AS sales_rows")
md(r"""
**Trap: joining on names.** Give each sales row its customer by looking the name up in `customers`.
""")
sql("p4_names_wrong", "JOIN customers c ON c.firstName = s.customerFirstName")
md(r"""
**What's wrong:** **1036** rows out of 965 in — the join invented rows, with no error. Two customers are both named Anna Sargsyan, so every sales row for either Anna matched both. **Fix:** join on something guaranteed unique — `customers.email` has a UNIQUE constraint.
""")
sql("p4_names_fixed", "JOIN customers c ON c.email = s.customerEmail")
md(r"""
**965** — every row finds exactly one customer. The extra rows came from the Annas: **71** sales rows each matched twice (965 − 71 + 2 × 71 = 1036).
""")
sql("p4_anna_rows", "AS anna_rows")

md(r"""
### 4.10 The fan-out trap — the number looks completely normal

`customers.moneySpent` is one number per customer. Someone joins `orders` "to count only real buyers".
""")
sql("p4_fanout_wrong", "SELECT sum(c.moneySpent) AS total_customer_spend\nFROM customers c\nJOIN orders o")
md(r"""
**What's wrong:** **4386925.27** — wildly more than the shop ever took in, from a completely ordinary inner join. Each customer's `moneySpent` was copied onto every one of their order rows, then summed. **Fix:** the summary value already exists — don't join.
""")
sql("p4_fanout_fixed", "SELECT sum(moneySpent) AS total_customer_spend\nFROM customers")
md(r"""
**157,078.41**, the real total. Look at one customer: Aram's **14625.38** was summed **40** times, once per order — **585015.20**.
""")
sql("p4_fanout_aram", "AS summed_after_join")
md(r"""
The proof, and the question to ask before every sum after a join: **600** rows summed, only **28** real customers behind them.
""")
sql("p4_fanout_proof", "count(DISTINCT c.customerID) AS customers")
md(r"""
Fix (a): don't join at all if you already have the summary value — **157,078.41**.
""")
sql("p4_fanout_fix_a", "SELECT sum(moneySpent) FROM customers")
md(r"""
Fix (b): aggregate the fine-grain table first, then join the result back — one row per customer, so nothing can be copied. **157,078.41** again. (A query inside a query: next lecture's topic.)
""")
sql("p4_fanout_fix_b", "SELECT sum(per_customer.spent)")

md(r"""
### 4.11 ON with non-equality conditions

`ON` isn't limited to `=`. First, a small table of price bands typed into the query with `VALUES`: **4** bands.
""")
sql("p4_bands", "SELECT *\nFROM (VALUES")
md(r"""
Join each completed order to the band its total falls in — a range, not a key: **121**, **251**, **120** and **37** orders.
""")
sql("p4_band_join", "SELECT b.band, count(*) AS orders")

md(r"""
### 4.14 GROUP BY column order — clearing up a misconception

Revenue per city and category, grouped city first: **45** groups.
""")
sql("p4_groupby_city_first", "ORDER BY c.city, p.category")
md(r"""
Subtract the category-first version: **0** rows — the same groups, the same totals. Order in `GROUP BY` changes nothing; if a total looks wrong, look for a fan-out instead.
""")
sql("p4_groupby_same", "GROUP BY p.category, c.city")

# ---- drill ----------------------------------------------------------------------
md(r"""
## Verification drill

Each query runs without error and returns a believable answer — and each is wrong. Name the problem before reading on.

**Q1.** "Total completed revenue for 2024, with who sold it."
""")
sql("dq1_wrong", "SELECT sum(o.orderTotal) AS revenue\nFROM orders o\nJOIN employees e")
md(r"""
**What's wrong:** **100,222.48** — the inner join dropped the 181 online orders. **Fix:** leave `employees` out of a question that doesn't need it.
""")
sql("dq1_fixed", "SELECT sum(orderTotal) AS revenue FROM orders WHERE status = 'completed'")
md(r"""
**157,078.41.**

**Q2.** "Customers with the fewest orders: who needs a reminder email?"
""")
sql("dq2_wrong", "HAVING count(*) <= 5")
md(r"""
**What's wrong:** Levon and Astghik show **1** order each — `count(*)` counted the empty match. **Fix:** count the right table's key.
""")
sql("dq2_fixed", "HAVING count(o.orderID) <= 5")
md(r"""
Levon and Astghik have **0** — exactly who the email is for.

**Q3.** "Completed revenue for every product category, including those with none."
""")
sql("dq3_wrong", "SELECT p.category, coalesce(sum(i.lineTotal), 0) AS revenue\nFROM products p\nLEFT JOIN order_items i")
md(r"""
**What's wrong:** **12** rows — the `WHERE` undid the LEFT JOIN, and Chairs is gone. **Fix:** decide what counts as a match before the LEFT JOIN.
""")
sql("dq3_fixed", "SELECT p.category, coalesce(sum(i.lineTotal), 0) AS revenue\nFROM products p\nLEFT JOIN (order_items i")
md(r"""
**13** rows, Chairs at **0.00**.

**Q4.** "Average lifetime spend of the customers who bought in December."
""")
sql("dq4_wrong", "SELECT round(avg(c.moneySpent), 2) AS avg_spend")
md(r"""
**What's wrong:** **7339.20** is an average over December *orders*, not customers — big buyers count once per order (fan-out). **Fix:** pick each customer once.
""")
sql("dq4_fixed", "SELECT round(avg(moneySpent), 2) AS avg_spend, count(*) AS customers")

# ---- Part 5 -------------------------------------------------------------------
md(r"""
**5864.44** across **26** customers.

## Part 5 — Why all of this matters

| Trap | Looked like | Was |
|---|---|---|
| Inner join to `employees` | completed revenue 100,222.48 | 157,078.41 |
| `NATURAL JOIN` | 168 rows | 965 |
| `WHERE` on a LEFT JOIN's right table | 12 categories | 13 (Chairs at 0) |
| Status in the wrong `ON` | Laptops 58,028.50 | 53,412.00 |
| Join on names | 1,036 sales rows | 965 |
| Fan-out over `moneySpent` | 4,386,925.27 | 157,078.41 |

None of them threw an error. All of them produced a result that looked like a completely normal table.

SQL correctness bugs are almost always silent. Nothing turns red; the query runs, returns rows, and is simply wrong — and an AI assistant will write a plausible-looking, syntactically perfect JOIN whether the logic is right or not. The real defense is the handful of independent checks that catch a wrong-but-plausible answer:

- **compare row counts** before and after a join (600 → 419; 965 → 1,036);
- **compare `count(*)` to `count(column)`** after an outer join (602 vs. 600);
- **check `DISTINCT` counts** against what you expect (600 rows, 28 customers);
- **run a symmetric-difference check** against a known-correct source (`EXCEPT` both ways → 0 rows).

For anyone using AI to write their SQL, that's not a side skill. It's the actual skill.
""")

# ---- appendix: the addendum traps (addendum/01..08, standalone scratch tables) ----
def addendum_cells():
    md(r"""
## Appendix — Deeper JOIN traps (from live Q&A)

Eight short demos from `addendum/`, each on its own tiny scratch tables (suffixed `_01` … `_08`), separate from the shop data.

**These cells change the database:** each trap first drops and re-creates its scratch tables, so re-running is safe. The tables are left in place at the end (the addendum files drop them; here later cells still read them). To remove them, run each file's last `DROP TABLE` line from `addendum/`.
""")
    for f in sorted((HERE / "addendum").glob("0*.sql")):
        lines = f.read_text().split("\n")
        n = f.name[:2]
        title = next(l for l in lines if l.startswith("-- TRAP") or l.startswith("-- NOT A TRAP"))[3:].strip()
        lesson = []
        stmts, pending, cur = [], [], []
        for l in lines:
            s = l.strip()
            if not cur:
                if s.startswith("-- LESSON:") or (lesson and s.startswith("--")):
                    lesson.append(s[2:].strip()); continue
                if not s or s.startswith("--"):
                    if s.startswith("-- =") or s.startswith("-- TRAP") or s.startswith("-- NOT A TRAP") or "Standalone:" in s:
                        continue
                    pending.append(l.strip()[3:] if l.strip().startswith("-- ") else "")
                    continue
            cur.append(l)
            if s.split("--")[0].rstrip().endswith(";"):
                body = "\n".join(cur).rstrip()
                last = body.split("\n")[-1]
                if "--" in last and last.split("--")[0].rstrip().endswith(";"):
                    body = body[: len(body) - len(last)] + last.split("--")[0].rstrip()
                stmts.append(("\n".join(pending).strip(), body[:-1]))
                pending, cur = [], []
        stmts = stmts[:-1]          # the file's final DROP: cleanup, skipped here (see above)
        assert stmts and stmts[0][1].startswith("DROP TABLE IF EXISTS"), f.name
        for k, (comment, text) in enumerate(stmts):
            if "{" in text or "}" in text:
                sys.exit(f"braces in SQL: {f.name}")
            head = f"### {title}\n\n" if k == 0 else ""
            if not comment:
                first = text.split("\n")[0]
                comment = ("Drop this trap's scratch tables if an earlier run left them." if first.startswith("DROP")
                           else f"Create `{first.split()[2]}`." if first.startswith("CREATE TABLE")
                           else f"Load the sample rows into `{first.split()[2]}`." if first.startswith("INSERT")
                           else "Run the query.")
            comment = re.sub(r"^---- (.*?) ----$", r"**\1**", comment, flags=re.M)
            # indented comment lines are result rows: show them as a code block
            out_lines, block = [], []
            for line in comment.split("\n") + [""]:
                if line.startswith("  "):
                    block.append(line.strip())
                else:
                    if block:
                        out_lines += ["```", *block, "```"]; block = []
                    out_lines.append(line)
            comment = "\n".join(out_lines).strip()
            md(head + comment)
            CELLS.append(("sql", f"a{n}_{k:02d}", text))
        if lesson:
            md("**Lesson:** " + " ".join(lesson).replace("LESSON:", "").strip())

addendum_cells()

# ---- coverage -------------------------------------------------------------------
if PROBLEMS:
    sys.exit("\n".join(PROBLEMS))
used = {c[2] for c in CELLS if c[0] == "sql"} | {c[1] for c in CELLS if c[0] == "err"}
missing = [t for t, st in DISTINCT.items() if st["after_setup"] and not st["meta"] and t not in used]
if missing:
    sys.exit("demo statements missing from the notebook:\n\n" + "\n\n".join(missing))
for k, c in enumerate(CELLS):
    if c[0] in ("sql", "err") and (k == 0 or CELLS[k - 1][0] != "md"):
        sys.exit(f"cell {k} ({c[0]}) is not directly preceded by a markdown cell")
names = [c[1] for c in CELLS if c[0] == "sql"]
if len(names) != len(set(names)):
    sys.exit("duplicate SQL variable names")

# ---- render -------------------------------------------------------------------
def ind(text, n):
    return "\n".join((" " * n + l) if l.strip() else "" for l in text.split("\n"))

def render(verify=False):
    out = ['import marimo', '', '__generated_with = "0.25.0"', 'app = marimo.App(width="medium")', '']
    for c in CELLS:
        out.append("")
        if c[0] == "md":
            out.append('@app.cell(hide_code=True)\ndef _(mo):\n    mo.md(r"""\n' + ind(c[1], 4) + '\n    """)\n    return\n')
        elif c[0] == "mermaid":
            out.append('@app.cell(hide_code=True)\ndef _(mo):\n    mo.mermaid(r"""\n' + ind(c[1], 4) + '\n    """)\n    return\n')
        elif c[0] == "imports":
            out.append('@app.cell\ndef _():\n    import os\n\n    import marimo as mo\n    import psycopg\n\n    return mo, os, psycopg\n')
        elif c[0] == "connect":
            out.append('@app.cell\ndef _(os, psycopg):\n    # One connection for the whole notebook. Load the data first with\n'
                       '    # psql + steps/00-setup.sql; set LECTURE04_DSN if yours differs.\n'
                       '    engine = psycopg.connect(\n'
                       '        os.environ.get("LECTURE04_DSN", "postgresql://postgres:postgres@localhost:5432/lecture04"),\n'
                       '        autocommit=True,\n    )\n    return (engine,)\n')
        elif c[0] == "sql":
            ret = f"return ({c[1]},)" if verify else "return"
            out.append(f'@app.cell\ndef _(engine, mo):\n    {c[1]} = mo.sql(\n        f"""\n' + ind(c[2], 8) +
                       f'\n        """,\n        engine=engine\n    )\n    {ret}\n')
        elif c[0] == "err":
            out.append('@app.cell\ndef _(engine, mo, psycopg):\n'
                       '    # Error on purpose -- shows PostgreSQL\'s message instead of stopping the notebook.\n'
                       '    try:\n        engine.execute("""\n' + ind(c[1], 8) + '\n        """)\n'
                       '        _shown = mo.callout(mo.md("No error?! This query was supposed to fail."), kind="warn")\n'
                       '    except psycopg.Error as _e:\n'
                       '        _shown = mo.callout(mo.md(f"**ERROR:** `{_e.diag.message_primary}`"), kind="danger")\n'
                       '    _shown\n    return\n')
    out += ["", 'if __name__ == "__main__":', "    app.run()", ""]
    return "\n".join(out)

ap = argparse.ArgumentParser()
ap.add_argument("--verify")
a = ap.parse_args()
(HERE / "lecture-04-notebook.py").write_text(render())
if a.verify:
    Path(a.verify).write_text(render(verify=True))
print(f"{len(CELLS)} cells: {sum(c[0]=='sql' for c in CELLS)} SQL, {sum(c[0]=='err' for c in CELLS)} error, "
      f"{sum(c[0]=='mermaid' for c in CELLS)} mermaid, {sum(c[0]=='md' for c in CELLS)} markdown")
