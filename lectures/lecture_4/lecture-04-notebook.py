import marimo

__generated_with = "0.25.0"
app = marimo.App(width="medium")


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    # Lecture 4 — Putting the Tables Back Together

    The JOIN lecture, one query at a time: what a join really is (every pair, then the pairs you want), every join type, and the traps that return a normal-looking table with the wrong answer. Plus the two schema ideas around it: the three levels of a data model, and a star schema built on top of the normal tables.

    **The data:** the shop from Lecture 3, where an order can hold several products. `orders` is the header (one row per order), `order_items` the lines (one row per product in an order), and `sales` is the flat file — one row per order line, with everything written out on every row. 600 orders, 965 lines.

    **Before you run this:** from the `lecture_4/` folder, run `psql postgres` and `\i steps/00-setup.sql`. It creates the `lecture04` database if it doesn't exist and loads the six tables (`\copy` only works in psql, so loading can't happen here). Then start the notebook with the connection string in `LECTURE04_DSN`, e.g.

    ```
    LECTURE04_DSN=postgresql://postgres:postgres@localhost:5432/lecture04 marimo edit lecture-04-notebook.py
    ```

    Each trap appears as **wrong query → what's wrong with it → fixed query**, with real results on screen at each step. Errors on purpose are caught and shown as red boxes, so the notebook runs top to bottom.
    """)
    return


@app.cell
def _():
    import os

    import marimo as mo
    import psycopg

    return mo, os, psycopg


@app.cell
def _(os, psycopg):
    # One connection for the whole notebook. Load the data first with
    # psql + steps/00-setup.sql; set LECTURE04_DSN if yours differs.
    engine = psycopg.connect(
        os.environ.get("LECTURE04_DSN", "postgresql://postgres:postgres@localhost:5432/lecture04"),
        autocommit=True,
    )
    return (engine,)


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## The data: six tables

    `orders` holds what is true once per order (who, when, status, `orderTotal`); `order_items` holds one row per product in the order, keyed by `(orderID, productID)`. Employees point at their manager through `managerID`; online orders have no employee.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.mermaid(r"""
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
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **And the flat file.** `sales` is the same facts as one wide sheet: one row per order line, with the order, the customer, the employee and the product written out on every row — 30 columns. It's what the tables above look like joined back together, and three traps in Part 4 use it.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.mermaid(r"""
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
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Check the data first.** One count per table: you should see **965** for `sales` and `order_items`, **30** customers, **8** employees, **37** products and **600** orders.
    """)
    return


@app.cell
def _(engine, mo):
    p0_counts = mo.sql(
        f"""
        SELECT 'sales' AS t, count(*) FROM sales
        UNION ALL SELECT 'customers',   count(*) FROM customers
        UNION ALL SELECT 'employees',   count(*) FROM employees
        UNION ALL SELECT 'products',    count(*) FROM products
        UNION ALL SELECT 'orders',      count(*) FROM orders
        UNION ALL SELECT 'order_items', count(*) FROM order_items
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### The junction table Lecture 2 deferred

    Lecture 2 drew `order_items` in an aside and put it off. Here it is. First, the headers: **600** orders.
    """)
    return


@app.cell
def _(engine, mo):
    p0_orders = mo.sql(
        f"""
        SELECT count(*) AS orders FROM orders
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    And the lines: **965** — more lines than orders, because an order can hold several products.
    """)
    return


@app.cell
def _(engine, mo):
    p0_lines = mo.sql(
        f"""
        SELECT count(*) AS lines FROM order_items
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    How many lines do orders have? **365** orders hold one product; **133** hold two, **74** three, **28** four.
    """)
    return


@app.cell
def _(engine, mo):
    p0_lines_per_order = mo.sql(
        f"""
        SELECT lines, count(*) AS orders
        FROM (SELECT orderID, count(*) AS lines FROM order_items GROUP BY orderID) AS t
        GROUP BY lines
        ORDER BY lines
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The order total is the sum of its lines — checked, not assumed. Expect **0** orders that disagree.
    """)
    return


@app.cell
def _(engine, mo):
    p0_totals_check = mo.sql(
        f"""
        SELECT count(*) AS orders_where_total_disagrees
        FROM orders o
        JOIN (SELECT orderID, sum(lineTotal) AS lines_total FROM order_items GROUP BY orderID) AS l
          ON l.orderID = o.orderID
        WHERE o.orderTotal <> l.lines_total
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 1 — Three levels of a data model

    1. **Conceptual** — entities and relationships, no tables yet: "A customer places orders. An order holds one or more products. An employee may serve an order — or nobody does, if it's online."
    2. **Logical** — tables, columns, keys, constraints, still DBMS-agnostic: `orders.customerID` is a required foreign key; `orders.employeeID` is optional.
    3. **Physical** — how one engine stores it. In psql, `\d orders` shows this level. psql commands can't run in a notebook, so here are two catalog queries that show the same thing. First the exact types: **11** columns.
    """)
    return


@app.cell
def _(engine, mo):
    p1_orders_columns = mo.sql(
        f"""
        SELECT column_name, data_type, numeric_precision, numeric_scale, is_nullable
        FROM information_schema.columns
        WHERE table_name = 'orders'
        ORDER BY ordinal_position
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Then the indexes. Nobody asked for one, but PostgreSQL built **orders_pkey** to enforce the primary key — a purely physical decision.
    """)
    return


@app.cell
def _(engine, mo):
    p1_orders_indexes = mo.sql(
        f"""
        SELECT indexname, indexdef
        FROM pg_indexes
        WHERE tablename = 'orders'
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Why the levels matter:** mistakes at the conceptual level are cheap — erase a box, redraw an arrow. Mistakes at the physical level are expensive — a `VARCHAR(50)` that turns out too short, or a `SERIAL` that should have been `BIGINT`, means an `ALTER TABLE` on live data (Lecture 2, Part 9). The further right you move, the more a change costs.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 2 — Dimensional modeling: facts, dimensions, grain

    A second, purpose-built schema you build *alongside* the normal tables, when the question shifts from "record what happened" to "summarize everything so far".

    - **Fact table** = an event, with numbers attached. Here `fact_sales`: one row per order line, holding `quantity`, `revenue`, `cost` and a key to each dimension.
    - **Dimension table** = the context: who, what, where, when — `dim_date`, `dim_customer`, `dim_product`, `dim_employee`.
    - **Grain** = the one-sentence definition of what a fact row *is*, decided first: **one row = one order line**.

    **The next cells change the database:** they create five tables. Each is safe to re-run — the first one drops all five if they exist.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Drop the star schema if an earlier run built it.
    """)
    return


@app.cell
def _(engine, mo):
    p2_drop_star = mo.sql(
        f"""
        DROP TABLE IF EXISTS fact_sales, dim_date, dim_customer, dim_product, dim_employee
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    `dim_date`: generated once with `generate_series` — every day of 2024 (a leap year, so 366 days) with quarter, month and day name computed as columns, so no query ever recomputes them.
    """)
    return


@app.cell
def _(engine, mo):
    p2_dim_date = mo.sql(
        f"""
        CREATE TABLE dim_date AS
        SELECT d::date                        AS dateKey,
               EXTRACT(quarter FROM d)::int   AS quarter,
               EXTRACT(month FROM d)::int     AS month,
               to_char(d, 'Mon')              AS monthName,
               EXTRACT(isodow FROM d)::int    AS dayOfWeek,
               to_char(d, 'Dy')               AS dayName
        FROM generate_series(DATE '2024-01-01', DATE '2024-12-31', INTERVAL '1 day') AS d
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Give `dim_date` its primary key.
    """)
    return


@app.cell
def _(engine, mo):
    p2_dim_date_pk = mo.sql(
        f"""
        ALTER TABLE dim_date ADD PRIMARY KEY (dateKey)
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    `dim_customer`: one row per customer, with the labels you group by.
    """)
    return


@app.cell
def _(engine, mo):
    p2_dim_customer = mo.sql(
        f"""
        CREATE TABLE dim_customer AS
        SELECT customerID                         AS customerKey,
               firstName || ' ' || lastName       AS customerName,
               city,
               EXTRACT(year FROM signupDate)::int AS signupYear
        FROM customers
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    `dim_product`: one row per product.
    """)
    return


@app.cell
def _(engine, mo):
    p2_dim_product = mo.sql(
        f"""
        CREATE TABLE dim_product AS
        SELECT productID AS productKey, productName, brand, category
        FROM products
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Primary key for `dim_customer`.
    """)
    return


@app.cell
def _(engine, mo):
    p2_dim_customer_pk = mo.sql(
        f"""
        ALTER TABLE dim_customer ADD PRIMARY KEY (customerKey)
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Primary key for `dim_product`.
    """)
    return


@app.cell
def _(engine, mo):
    p2_dim_product_pk = mo.sql(
        f"""
        ALTER TABLE dim_product  ADD PRIMARY KEY (productKey)
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    `dim_employee`: the self-join from Part 4 runs once here, so the manager's name sits on each row.
    """)
    return


@app.cell
def _(engine, mo):
    p2_dim_employee = mo.sql(
        f"""
        CREATE TABLE dim_employee AS
        SELECT e.employeeID                                          AS employeeKey,
               e.firstName || ' ' || e.lastName                      AS employeeName,
               e.branch,
               coalesce(m.firstName || ' ' || m.lastName, '(none)')  AS managerName
        FROM employees e
        LEFT JOIN employees m ON m.employeeID = e.managerID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **The unknown-member trick.** Online orders have no employee. Instead of carrying that NULL into the fact table, add one row that stands for "nobody": key 0, `'Online'`. Every fact row then has a valid employee key — so joins to `dim_employee` never need a LEFT JOIN.
    """)
    return


@app.cell
def _(engine, mo):
    p2_unknown_member = mo.sql(
        f"""
        INSERT INTO dim_employee VALUES (0, '(online)', 'Online', '(none)')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Primary key for `dim_employee`.
    """)
    return


@app.cell
def _(engine, mo):
    p2_dim_employee_pk = mo.sql(
        f"""
        ALTER TABLE dim_employee ADD PRIMARY KEY (employeeKey)
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    `fact_sales`, at line grain: one row per product in an order. `coalesce(o.employeeID, 0)` points online orders at the unknown member.
    """)
    return


@app.cell
def _(engine, mo):
    p2_fact_sales = mo.sql(
        f"""
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
        JOIN products    p ON p.productID = i.productID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Keys: the fact's primary key is `(orderID, productKey)`, and each dimension key is a foreign key.
    """)
    return


@app.cell
def _(engine, mo):
    p2_fact_keys = mo.sql(
        f"""
        ALTER TABLE fact_sales
            ADD PRIMARY KEY (orderID, productKey),
            ADD FOREIGN KEY (dateKey)     REFERENCES dim_date,
            ADD FOREIGN KEY (customerKey) REFERENCES dim_customer,
            ADD FOREIGN KEY (productKey)  REFERENCES dim_product,
            ADD FOREIGN KEY (employeeKey) REFERENCES dim_employee
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 3 — Star vs. snowflake

    **Star:** one fact table, each dimension attached directly and flat. This is what Part 2 just built.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.mermaid(r"""
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
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Check the build: **965** fact rows for **600** orders, and completed revenue **157,078.41** — the same money as the source tables.
    """)
    return


@app.cell
def _(engine, mo):
    p3_star_check = mo.sql(
        f"""
        SELECT count(*) AS fact_rows,
               count(DISTINCT orderID) AS orders,
               sum(revenue) FILTER (WHERE status = 'completed') AS completed_revenue
        FROM fact_sales
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Querying the star is plain inner joins — no LEFT JOIN, no `coalesce`, thanks to the unknown member. Completed revenue per branch and quarter: Online leads with **56,855.93**.
    """)
    return


@app.cell
def _(engine, mo):
    p3_star_branch_quarter = mo.sql(
        f"""
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
        ORDER BY total DESC
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Line grain makes product questions easy: margin by category, Saturdays vs. the year. Laptops earn **9472.00** over the year.
    """)
    return


@app.cell
def _(engine, mo):
    p3_star_margin = mo.sql(
        f"""
        SELECT p.category,
               sum(f.revenue - f.cost) FILTER (WHERE d.dayName = 'Sat') AS sat_margin,
               sum(f.revenue - f.cost)                                  AS year_margin
        FROM fact_sales f
        JOIN dim_date    d ON d.dateKey    = f.dateKey
        JOIN dim_product p ON p.productKey = f.productKey
        WHERE f.status = 'completed'
        GROUP BY p.category
        ORDER BY year_margin DESC
        LIMIT 5
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Snowflake:** the same idea, but a dimension is normalized into sub-tables — e.g. `dim_product` split into `dim_product` + `dim_category` + `dim_brand`, each joined in turn.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.mermaid(r"""
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
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Default answer: star.** Kimball's guidance is to avoid snowflaking unless you have a specific, concrete reason. Snowflaking buys less redundancy and costs more joins and more tables to navigate — a bad trade most of the time.

    One naming gotcha: "Snowflake" is also a warehouse product. The schema shape and the product are unrelated.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 4 — JOINs, from one idea

    ### 4.0 The one idea

    **A join is: pair up every row of A with every row of B, then keep the pairs you want.** Every join type is a variation on "which pairs do we keep" and "what do we do with the rows that found no pair".
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 4.1 CROSS JOIN — start here, not last

    Every row of `orders` paired with every row of `customers`: 600 × 30 = **18000** pairs, most of them nonsense.
    """)
    return


@app.cell
def _(engine, mo):
    p4_cross = mo.sql(
        f"""
        SELECT count(*) FROM orders CROSS JOIN customers
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    PostgreSQL defines `CROSS JOIN` as exactly `INNER JOIN ... ON TRUE` — a join whose condition can never fail. Same **18000**.
    """)
    return


@app.cell
def _(engine, mo):
    p4_on_true = mo.sql(
        f"""
        SELECT count(*) FROM orders INNER JOIN customers ON TRUE
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The old comma syntax is the same cross product again: **18000**.
    """)
    return


@app.cell
def _(engine, mo):
    p4_comma = mo.sql(
        f"""
        SELECT count(*) FROM orders, customers
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Zoom in: 3 orders × 3 customers = **9** pairs. In each, compare "order says" with "customer row" — only some pairs are true.
    """)
    return


@app.cell
def _(engine, mo):
    p4_nine_pairs = mo.sql(
        f"""
        SELECT o.orderID,
               o.customerID AS "order says",
               c.customerID AS "customer row",
               c.firstName, c.lastName
        FROM orders o CROSS JOIN customers c
        WHERE o.orderID IN (1001, 1002, 1003)
          AND c.customerID IN (2, 6, 26)
        ORDER BY o.orderID, c.customerID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Keep only the pairs where the ids match: **3** rows. That *is* a join — every pair, filtered.
    """)
    return


@app.cell
def _(engine, mo):
    p4_three_pairs = mo.sql(
        f"""
        SELECT o.orderID,
               o.customerID AS "order says",
               c.customerID AS "customer row",
               c.firstName, c.lastName
        FROM orders o CROSS JOIN customers c
        WHERE o.orderID IN (1001, 1002, 1003)
          AND c.customerID IN (2, 6, 26)
          AND o.customerID = c.customerID
        ORDER BY o.orderID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The same **3** rows written as `JOIN ... ON` — cleaner syntax, nothing more mysterious.
    """)
    return


@app.cell
def _(engine, mo):
    p4_join_on = mo.sql(
        f"""
        SELECT o.orderID, c.firstName, c.lastName, o.orderTotal
        FROM orders o
        JOIN customers c ON c.customerID = o.customerID
        WHERE o.orderID IN (1001, 1002, 1003)
        ORDER BY o.orderID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 4.2 INNER JOIN — keeps only the pairs that match

    Every order has exactly one customer, so this keeps one row per order: **600**.
    """)
    return


@app.cell
def _(engine, mo):
    p4_orders_customers = mo.sql(
        f"""
        SELECT count(*)
        FROM orders o
        JOIN customers c ON c.customerID = o.customerID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Products live on the order **lines**, so reach them through `order_items`. Order 1001 has one line; order 1009 has three. Look at `ordertotal`: 1009's whole total, **147.76**, sits on every one of its lines.
    """)
    return


@app.cell
def _(engine, mo):
    p4_lines_of_two_orders = mo.sql(
        f"""
        SELECT o.orderID, o.orderDate,
               c.firstName || ' ' || c.lastName AS customer,
               p.productName, i.quantity, i.lineTotal,
               o.orderTotal
        FROM orders o
        JOIN customers   c ON c.customerID = o.customerID
        JOIN order_items i ON i.orderID    = o.orderID
        JOIN products    p ON p.productID  = i.productID
        WHERE o.orderID IN (1001, 1009)
        ORDER BY o.orderID, p.productName
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Joining the lines changes what a row is: **965** rows, one per line — not one per order.
    """)
    return


@app.cell
def _(engine, mo):
    p4_all_lines = mo.sql(
        f"""
        SELECT count(*)
        FROM orders o
        JOIN customers   c ON c.customerID = o.customerID
        JOIN order_items i ON i.orderID    = o.orderID
        JOIN products    p ON p.productID  = i.productID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Back to one row per order, and add employees. Guess first: there are 600 orders. Expect **419**.
    """)
    return


@app.cell
def _(engine, mo):
    p4_with_employees = mo.sql(
        f"""
        SELECT count(*)
        FROM orders o
        JOIN customers c ON c.customerID = o.customerID
        JOIN employees e ON e.employeeID = o.employeeID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The missing ones are exactly the online orders: **181** of **600** have no employee, and NULL matches nothing.
    """)
    return


@app.cell
def _(engine, mo):
    p4_online_count = mo.sql(
        f"""
        SELECT count(*) FILTER (WHERE employeeID IS NULL) AS online_orders,
               count(*)                                   AS all_orders
        FROM orders
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Trap: the inner join that drops the online orders.** "Completed revenue, with who sold it" — someone joins `employees` just to have the names.
    """)
    return


@app.cell
def _(engine, mo):
    p4_trap_revenue_wrong = mo.sql(
        f"""
        SELECT sum(o.orderTotal) AS revenue
        FROM orders o
        JOIN employees e ON e.employeeID = o.employeeID
        WHERE o.status = 'completed'
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **What's wrong:** **100,222.48** is a real sum, correctly computed — over a silently incomplete set of rows. The 181 online orders found no employee, so the inner join dropped them. No error. **Fix:** the question needs no employee data at all — drop the join.
    """)
    return


@app.cell
def _(engine, mo):
    p4_trap_revenue_fixed = mo.sql(
        f"""
        SELECT sum(orderTotal) AS revenue
        FROM orders
        WHERE status = 'completed'
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **157,078.41**: the real completed revenue. An inner join doesn't complain when rows don't match — it just quietly leaves them out.

    ### 4.3 Aliasing — and the two errors that teach you why it exists

    Full table names work: **1001**, Davit, **211.65**.
    """)
    return


@app.cell
def _(engine, mo):
    p4_full_names = mo.sql(
        f"""
        SELECT orders.orderID, customers.firstName, orders.orderTotal
        FROM orders
        JOIN customers ON customers.customerID = orders.customerID
        WHERE orders.orderID = 1001
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Error on purpose:** `customerID` exists in both tables, and the engine refuses to guess — even though the values are equal on every joined row.
    """)
    return


@app.cell
def _(engine, mo, psycopg):
    # Error on purpose -- shows PostgreSQL's message instead of stopping the notebook.
    try:
        engine.execute("""
        SELECT orderID, customerID, firstName
        FROM orders
        JOIN customers ON customers.customerID = orders.customerID
        WHERE orderID = 1001
        """)
        _shown = mo.callout(mo.md("No error?! This query was supposed to fail."), kind="warn")
    except psycopg.Error as _e:
        _shown = mo.callout(mo.md(f"**ERROR:** `{_e.diag.message_primary}`"), kind="danger")
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The fix: alias the tables and qualify the columns — `o.customerID`. Davit, customer **2**.
    """)
    return


@app.cell
def _(engine, mo):
    p4_alias_fix = mo.sql(
        f"""
        SELECT o.orderID, o.customerID, c.firstName
        FROM orders o
        JOIN customers c ON c.customerID = o.customerID
        WHERE o.orderID = 1001
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Error on purpose:** once you write `FROM orders o`, the name `orders` stops existing for the rest of the query. PostgreSQL's hint says exactly that: the alias didn't add a nickname, it replaced the name.
    """)
    return


@app.cell
def _(engine, mo, psycopg):
    # Error on purpose -- shows PostgreSQL's message instead of stopping the notebook.
    try:
        engine.execute("""
        SELECT orders.orderID
        FROM orders o
        WHERE o.orderID = 1001
        """)
        _shown = mo.callout(mo.md("No error?! This query was supposed to fail."), kind="warn")
    except psycopg.Error as _e:
        _shown = mo.callout(mo.md(f"**ERROR:** `{_e.diag.message_primary}`"), kind="danger")
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 4.4 USING and NATURAL JOIN — convenience with a hidden cost

    `USING (customerID)` is shorthand for `ON o.customerID = c.customerID`, and the column appears once in the output: customer **2**, order **1001**.
    """)
    return


@app.cell
def _(engine, mo):
    p4_using = mo.sql(
        f"""
        SELECT customerID, c.firstName, o.orderID
        FROM orders o
        JOIN customers c USING (customerID)
        WHERE o.orderID = 1001
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Trap: NATURAL JOIN.** `orders` and `sales` hold the same orders — `sales` has one row per line. What does `NATURAL JOIN` give?
    """)
    return


@app.cell
def _(engine, mo):
    p4_natural_wrong = mo.sql(
        f"""
        SELECT count(*) FROM orders NATURAL JOIN sales
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **What's wrong:** **168** rows, and nothing in the query says why. NATURAL JOIN silently joined on *every* column name the two tables share — not just `orderID`. **Fix:** write the condition you mean.
    """)
    return


@app.cell
def _(engine, mo):
    p4_natural_fixed = mo.sql(
        f"""
        SELECT count(*) FROM orders o JOIN sales s ON s.orderID = o.orderID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **965** — every line finds its order. Here are the column names NATURAL JOIN used: **9** of them, `deliveryDate` and `rating` among them.
    """)
    return


@app.cell
def _(engine, mo):
    p4_shared_columns = mo.sql(
        f"""
        SELECT column_name FROM information_schema.columns WHERE table_name = 'orders'
        INTERSECT
        SELECT column_name FROM information_schema.columns WHERE table_name = 'sales'
        ORDER BY 1
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    `deliveryDate` is NULL for every in-store order, and `NULL = NULL` is not true. The survivors are the lines of online orders that also got a rating: **168** again. The join condition should always be visible in the code — NATURAL JOIN hides it, and it changes silently when either table gains a matching column.
    """)
    return


@app.cell
def _(engine, mo):
    p4_natural_survivors = mo.sql(
        f"""
        SELECT count(*)
        FROM sales
        WHERE deliveryDate IS NOT NULL
          AND rating IS NOT NULL
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 4.5 LEFT / RIGHT / FULL OUTER JOIN — keeping what doesn't match

    `LEFT JOIN` keeps every row of the left table; with no match on the right, it fills the right side with NULLs. Orders 1005–1007 are online: they stay, with no employee. **8** rows.
    """)
    return


@app.cell
def _(engine, mo):
    p4_left_sample = mo.sql(
        f"""
        SELECT o.orderID, o.channel, e.firstName, e.branch
        FROM orders o
        LEFT JOIN employees e ON e.employeeID = o.employeeID
        WHERE o.orderID BETWEEN 1001 AND 1008
        ORDER BY o.orderID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    All **600** orders survive now — the inner join kept 419.
    """)
    return


@app.cell
def _(engine, mo):
    p4_left_count = mo.sql(
        f"""
        SELECT count(*)
        FROM orders o
        LEFT JOIN employees e ON e.employeeID = o.employeeID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Give the NULLs a name and the lost revenue comes back: "Online" is the biggest branch, **56,855.93**. The four rows add up to 157,078.41.
    """)
    return


@app.cell
def _(engine, mo):
    p4_left_branches = mo.sql(
        f"""
        SELECT coalesce(e.branch, 'Online') AS branch,
               count(*)                     AS orders,
               sum(o.orderTotal)            AS revenue
        FROM orders o
        LEFT JOIN employees e ON e.employeeID = o.employeeID
        WHERE o.status = 'completed'
        GROUP BY coalesce(e.branch, 'Online')
        ORDER BY revenue DESC
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    `RIGHT JOIN` is the mirror image: every customer kept. **602** — all 600 orders, plus one NULL-padded row for each of the 2 customers who never ordered.
    """)
    return


@app.cell
def _(engine, mo):
    p4_right = mo.sql(
        f"""
        SELECT count(*)
        FROM orders o
        RIGHT JOIN customers c ON c.customerID = o.customerID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Identical to `customers LEFT JOIN orders`: **602**. This course always writes LEFT, so every query reads the same way.
    """)
    return


@app.cell
def _(engine, mo):
    p4_left_reversed = mo.sql(
        f"""
        SELECT count(*)
        FROM customers c
        LEFT JOIN orders o ON o.customerID = c.customerID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    `FULL JOIN` keeps everything from both sides — the classic tool for reconciling two lists. By name: **28** customers only, **6** employees only, **2** on both lists. Hold on to those 2.
    """)
    return


@app.cell
def _(engine, mo):
    p4_full = mo.sql(
        f"""
        SELECT CASE WHEN e.employeeID IS NULL THEN 'customer only'
                    WHEN c.customerID IS NULL THEN 'employee only'
                    ELSE 'on both lists' END AS status,
               count(*) AS people
        FROM customers c
        FULL JOIN employees e ON e.firstName = c.firstName AND e.lastName = c.lastName
        GROUP BY 1
        ORDER BY 1
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **The anti-join:** "which X have no Y?" = `LEFT JOIN` + `WHERE right.key IS NULL`. Products never ordered: **1** — productID **35**, Ergonomic Chair Pro, **6** in stock.
    """)
    return


@app.cell
def _(engine, mo):
    p4_anti_products = mo.sql(
        f"""
        SELECT p.productID, p.productName, p.category, p.stockQuantity
        FROM products p
        LEFT JOIN order_items i ON i.productID = p.productID
        WHERE i.orderID IS NULL
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Trap: testing a nullable column.** Customers who never ordered — but the test is on `o.rating`, a column that can be NULL in a real row.
    """)
    return


@app.cell
def _(engine, mo):
    p4_anti_nullable_wrong = mo.sql(
        f"""
        SELECT count(*)
        FROM customers c
        LEFT JOIN orders o ON o.customerID = c.customerID
        WHERE o.rating IS NULL
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **What's wrong:** **280** — far more than the customers who never ordered. Every real order without a rating is NULL there too, so it sneaks in. **Fix:** test the right table's primary key, which is never NULL in a real row.
    """)
    return


@app.cell
def _(engine, mo):
    p4_anti_customers_fixed = mo.sql(
        f"""
        SELECT c.customerID, c.firstName, c.lastName, c.signupDate
        FROM customers c
        LEFT JOIN orders o ON o.customerID = c.customerID
        WHERE o.orderID IS NULL
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **2** customers: Levon (**24**) and Astghik (**29**). "Which X have no Y" comes up constantly — teach it as a named pattern.

    ### 4.6 count(*) vs. count(column)

    Orders per customer, fewest first, with `count(*)`: Levon shows **1** order.
    """)
    return


@app.cell
def _(engine, mo):
    p4_count_star = mo.sql(
        f"""
        SELECT c.firstName, c.lastName, count(*) AS orders
        FROM customers c
        LEFT JOIN orders o ON o.customerID = c.customerID
        GROUP BY c.customerID, c.firstName, c.lastName
        ORDER BY orders, c.lastName
        LIMIT 4
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The LEFT JOIN gave Levon one row full of NULLs, and `count(*)` counts rows. `count(o.orderID)` counts non-NULL values: **0**.
    """)
    return


@app.cell
def _(engine, mo):
    p4_count_column = mo.sql(
        f"""
        SELECT c.firstName, c.lastName, count(o.orderID) AS orders
        FROM customers c
        LEFT JOIN orders o ON o.customerID = c.customerID
        GROUP BY c.customerID, c.firstName, c.lastName
        ORDER BY orders, c.lastName
        LIMIT 4
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The reflex after every outer join: both counts side by side. **602** rows, **600** real matches — they differ by exactly the 2 unmatched customers.
    """)
    return


@app.cell
def _(engine, mo):
    p4_count_both = mo.sql(
        f"""
        SELECT count(*)          AS joined_rows,
               count(o.orderID)  AS real_matches
        FROM customers c
        LEFT JOIN orders o ON o.customerID = c.customerID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 4.7 The WHERE-vs-ON trap — the most important trap in the lecture

    `ON` applies while deciding what matches; `WHERE` applies after the whole join, NULL-padding included. Revenue per category, including categories that never sold: **13** rows, Chairs at the bottom.
    """)
    return


@app.cell
def _(engine, mo):
    p4_categories_all = mo.sql(
        f"""
        SELECT p.category, count(i.orderID) AS lines, sum(i.lineTotal) AS revenue
        FROM products p
        LEFT JOIN order_items i ON i.productID = p.productID
        GROUP BY p.category
        ORDER BY revenue DESC NULLS LAST
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Trap (right-table half):** the boss adds "completed orders only". The obvious edit puts the status filter in `WHERE`.
    """)
    return


@app.cell
def _(engine, mo):
    p4_where_wrong = mo.sql(
        f"""
        SELECT p.category, count(i.orderID) AS lines, sum(i.lineTotal) AS revenue
        FROM products p
        LEFT JOIN order_items i ON i.productID = p.productID
        LEFT JOIN orders      o ON o.orderID   = i.orderID
        WHERE o.status = 'completed'
        GROUP BY p.category
        ORDER BY revenue DESC NULLS LAST
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **What's wrong:** **12** rows — Chairs is gone, no error. The LEFT JOIN kept the Chair row with `o.status` NULL; then WHERE ran, `NULL = 'completed'` is not true, and the row was thrown out. First attempt at a fix: move the condition into the `ON` of the orders join.
    """)
    return


@app.cell
def _(engine, mo):
    p4_on_wrong_join = mo.sql(
        f"""
        SELECT p.category, count(i.orderID) AS lines, coalesce(sum(i.lineTotal), 0) AS revenue
        FROM products p
        LEFT JOIN order_items i ON i.productID = p.productID
        LEFT JOIN orders      o ON o.orderID   = i.orderID
                               AND o.status    = 'completed'
        GROUP BY p.category
        ORDER BY revenue DESC
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Still wrong:** Chairs is back (**13** rows), but Laptops shows **58028.50** — the all-orders revenue again. A line of a returned order still exists; it just gets NULL order columns, and its `lineTotal` is still summed. In a chain of joins, ask *which* join the condition belongs to. **Fix:** decide what counts as a match — a line of a completed order — *before* the LEFT JOIN, in brackets.
    """)
    return


@app.cell
def _(engine, mo):
    p4_on_fixed = mo.sql(
        f"""
        SELECT p.category, count(i.orderID) AS lines, coalesce(sum(i.lineTotal), 0) AS revenue
        FROM products p
        LEFT JOIN (order_items i
                   JOIN orders o ON o.orderID = i.orderID
                                AND o.status  = 'completed')
               ON i.productID = p.productID
        GROUP BY p.category
        ORDER BY revenue DESC
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **13** rows, Laptops at the real **53412.00**, Chairs at **0.00**. "ON decides who gets invited to the party; WHERE decides who's allowed to stay after it already happened — including the guests the LEFT JOIN invited for free."

    **Trap (left-table half):** "Gyumri customers and their orders" — with the left-table condition placed in `ON`.
    """)
    return


@app.cell
def _(engine, mo):
    p4_left_condition_wrong = mo.sql(
        f"""
        SELECT count(*) AS rows, count(o.orderID) AS matched
        FROM customers c
        LEFT JOIN orders o ON o.customerID = c.customerID
                          AND c.city = 'Gyumri'
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **What's wrong:** **233** rows for **210** matches. A LEFT JOIN keeps *every* left row, so all 30 customers are still there — the Gyumri ones with their orders, plus a NULL-padded row for everyone else. **Fix:** conditions on the left table go in `WHERE`.
    """)
    return


@app.cell
def _(engine, mo):
    p4_left_condition_fixed = mo.sql(
        f"""
        SELECT count(*) AS rows, count(o.orderID) AS matched
        FROM customers c
        LEFT JOIN orders o ON o.customerID = c.customerID
        WHERE c.city = 'Gyumri'
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **210** rows, **210** matched: only Gyumri customers. The rule: right-table conditions → `ON`; left-table conditions → `WHERE`.

    ### 4.8 Self-joins — a table joined to itself

    The raw data first: **8** employees. `managerID` points at another row of the same table; Vahe's is NULL.
    """)
    return


@app.cell
def _(engine, mo):
    p4_employees = mo.sql(
        f"""
        SELECT employeeID, firstName, position, branch, managerID
        FROM employees
        ORDER BY employeeID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The reporting line those `managerID`s describe:
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.mermaid(r"""
    flowchart TD
        V["Vahe — Store Manager"] --> G["Gor"]
        V --> A["Ani"]
        V --> H["Hayk — Senior Sales"]
        V --> M["Marine — Senior Sales"]
        H --> N["Nare"]
        H --> L["Lilit"]
        M --> R["Arman"]
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Error on purpose:** the same table twice with no aliases — PostgreSQL can't tell "this row" from "that other row of the same table".
    """)
    return


@app.cell
def _(engine, mo, psycopg):
    # Error on purpose -- shows PostgreSQL's message instead of stopping the notebook.
    try:
        engine.execute("""
        SELECT employees.firstName, employees.firstName
        FROM employees
        JOIN employees ON employees.employeeID = employees.managerID
        """)
        _shown = mo.callout(mo.md("No error?! This query was supposed to fail."), kind="warn")
    except psycopg.Error as _e:
        _shown = mo.callout(mo.md(f"**ERROR:** `{_e.diag.message_primary}`"), kind="danger")
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    With aliases: `e` plays the employee, `m` the manager. LEFT, or Vahe — who has no manager — would vanish. **8** rows.
    """)
    return


@app.cell
def _(engine, mo):
    p4_self_manager = mo.sql(
        f"""
        SELECT e.firstName || ' ' || e.lastName AS employee,
               e.position,
               m.firstName || ' ' || m.lastName AS manager
        FROM employees e
        LEFT JOIN employees m ON m.employeeID = e.managerID
        ORDER BY m.employeeID NULLS FIRST, e.employeeID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    A second hop, the manager's manager, for the employees outside Yerevan Center: **5** rows. Two levels up took two joins.
    """)
    return


@app.cell
def _(engine, mo):
    p4_self_two_hops = mo.sql(
        f"""
        SELECT e.firstName AS employee, m.firstName AS manager, mm.firstName AS managers_manager
        FROM employees e
        LEFT JOIN employees m  ON m.employeeID  = e.managerID
        LEFT JOIN employees mm ON mm.employeeID = m.managerID
        WHERE e.branch <> 'Yerevan Center'
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Self-join + GROUP BY: direct reports per manager — **3** managers, Vahe with **4**.
    """)
    return


@app.cell
def _(engine, mo):
    p4_self_reports = mo.sql(
        f"""
        SELECT m.firstName || ' ' || m.lastName AS manager, count(e.employeeID) AS direct_reports
        FROM employees m
        JOIN employees e ON e.managerID = m.employeeID
        GROUP BY m.employeeID, m.firstName, m.lastName
        ORDER BY direct_reports DESC
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 4.9 Joining on the wrong thing — names are not identifiers

    "Which employees also shop with us?" Join customers to employees by name: **2** "matches". Read the birth dates.
    """)
    return


@app.cell
def _(engine, mo):
    p4_names_people = mo.sql(
        f"""
        SELECT c.firstName, c.lastName,
               c.birthDate AS customer_born, e.birthDate AS employee_born,
               c.city      AS customer_city, e.branch    AS employee_branch
        FROM customers c
        JOIN employees e ON e.firstName = c.firstName AND e.lastName = c.lastName
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Those are four different people who share two names. No column links a customer to an employee, so the honest answer is: this data can't tell.

    Now at scale. The flat file has **965** rows, one per order line.
    """)
    return


@app.cell
def _(engine, mo):
    p4_sales_rows = mo.sql(
        f"""
        SELECT count(*) AS sales_rows FROM sales
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Trap: joining on names.** Give each sales row its customer by looking the name up in `customers`.
    """)
    return


@app.cell
def _(engine, mo):
    p4_names_wrong = mo.sql(
        f"""
        SELECT count(*)
        FROM sales s
        JOIN customers c ON c.firstName = s.customerFirstName
                        AND c.lastName  = s.customerLastName
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **What's wrong:** **1036** rows out of 965 in — the join invented rows, with no error. Two customers are both named Anna Sargsyan, so every sales row for either Anna matched both. **Fix:** join on something guaranteed unique — `customers.email` has a UNIQUE constraint.
    """)
    return


@app.cell
def _(engine, mo):
    p4_names_fixed = mo.sql(
        f"""
        SELECT count(*)
        FROM sales s
        JOIN customers c ON c.email = s.customerEmail
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **965** — every row finds exactly one customer. The extra rows came from the Annas: **71** sales rows each matched twice (965 − 71 + 2 × 71 = 1036).
    """)
    return


@app.cell
def _(engine, mo):
    p4_anna_rows = mo.sql(
        f"""
        SELECT count(*) AS anna_rows
        FROM sales
        WHERE customerFirstName = 'Anna' AND customerLastName = 'Sargsyan'
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 4.10 The fan-out trap — the number looks completely normal

    `customers.moneySpent` is one number per customer. Someone joins `orders` "to count only real buyers".
    """)
    return


@app.cell
def _(engine, mo):
    p4_fanout_wrong = mo.sql(
        f"""
        SELECT sum(c.moneySpent) AS total_customer_spend
        FROM customers c
        JOIN orders o ON o.customerID = c.customerID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **What's wrong:** **4386925.27** — wildly more than the shop ever took in, from a completely ordinary inner join. Each customer's `moneySpent` was copied onto every one of their order rows, then summed. **Fix:** the summary value already exists — don't join.
    """)
    return


@app.cell
def _(engine, mo):
    p4_fanout_fixed = mo.sql(
        f"""
        SELECT sum(moneySpent) AS total_customer_spend
        FROM customers
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **157,078.41**, the real total. Look at one customer: Aram's **14625.38** was summed **40** times, once per order — **585015.20**.
    """)
    return


@app.cell
def _(engine, mo):
    p4_fanout_aram = mo.sql(
        f"""
        SELECT c.firstName, c.lastName, c.moneySpent,
               count(*)          AS rows_after_join,
               sum(c.moneySpent) AS summed_after_join
        FROM customers c
        JOIN orders o ON o.customerID = c.customerID
        WHERE c.customerID = 8
        GROUP BY c.customerID, c.firstName, c.lastName, c.moneySpent
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The proof, and the question to ask before every sum after a join: **600** rows summed, only **28** real customers behind them.
    """)
    return


@app.cell
def _(engine, mo):
    p4_fanout_proof = mo.sql(
        f"""
        SELECT count(*)                     AS rows,
               count(DISTINCT c.customerID) AS customers
        FROM customers c
        JOIN orders o ON o.customerID = c.customerID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Fix (a): don't join at all if you already have the summary value — **157,078.41**.
    """)
    return


@app.cell
def _(engine, mo):
    p4_fanout_fix_a = mo.sql(
        f"""
        SELECT sum(moneySpent) FROM customers
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Fix (b): aggregate the fine-grain table first, then join the result back — one row per customer, so nothing can be copied. **157,078.41** again. (A query inside a query: next lecture's topic.)
    """)
    return


@app.cell
def _(engine, mo):
    p4_fanout_fix_b = mo.sql(
        f"""
        SELECT sum(per_customer.spent) AS total_customer_spend
        FROM (SELECT customerID, sum(orderTotal) AS spent
              FROM orders
              WHERE status = 'completed'
              GROUP BY customerID) AS per_customer
        JOIN customers c ON c.customerID = per_customer.customerID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 4.11 ON with non-equality conditions

    `ON` isn't limited to `=`. First, a small table of price bands typed into the query with `VALUES`: **4** bands.
    """)
    return


@app.cell
def _(engine, mo):
    p4_bands = mo.sql(
        f"""
        SELECT *
        FROM (VALUES ('1. under 50',  0,    50),
                     ('2. 50 - 299',  50,   300),
                     ('3. 300 - 999', 300,  1000),
                     ('4. 1000+',     1000, 100000)) AS b(band, low, high)
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Join each completed order to the band its total falls in — a range, not a key: **121**, **251**, **120** and **37** orders.
    """)
    return


@app.cell
def _(engine, mo):
    p4_band_join = mo.sql(
        f"""
        SELECT b.band, count(*) AS orders, sum(o.orderTotal) AS revenue
        FROM orders o
        JOIN (VALUES ('1. under 50',  0,    50),
                     ('2. 50 - 299',  50,   300),
                     ('3. 300 - 999', 300,  1000),
                     ('4. 1000+',     1000, 100000)) AS b(band, low, high)
          ON o.orderTotal >= b.low AND o.orderTotal < b.high
        WHERE o.status = 'completed'
        GROUP BY b.band
        ORDER BY b.band
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 4.14 GROUP BY column order — clearing up a misconception

    Revenue per city and category, grouped city first: **45** groups.
    """)
    return


@app.cell
def _(engine, mo):
    p4_groupby_city_first = mo.sql(
        f"""
        SELECT c.city, p.category, sum(i.lineTotal) AS revenue
        FROM orders o
        JOIN customers   c ON c.customerID = o.customerID
        JOIN order_items i ON i.orderID    = o.orderID
        JOIN products    p ON p.productID  = i.productID
        GROUP BY c.city, p.category
        ORDER BY c.city, p.category
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Subtract the category-first version: **0** rows — the same groups, the same totals. Order in `GROUP BY` changes nothing; if a total looks wrong, look for a fan-out instead.
    """)
    return


@app.cell
def _(engine, mo):
    p4_groupby_same = mo.sql(
        f"""
        SELECT c.city, p.category, sum(i.lineTotal) AS revenue
        FROM orders o
        JOIN customers   c ON c.customerID = o.customerID
        JOIN order_items i ON i.orderID    = o.orderID
        JOIN products    p ON p.productID  = i.productID
        GROUP BY c.city, p.category
        EXCEPT
        SELECT c.city, p.category, sum(i.lineTotal) AS revenue
        FROM orders o
        JOIN customers   c ON c.customerID = o.customerID
        JOIN order_items i ON i.orderID    = o.orderID
        JOIN products    p ON p.productID  = i.productID
        GROUP BY p.category, c.city
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Verification drill

    Each query runs without error and returns a believable answer — and each is wrong. Name the problem before reading on.

    **Q1.** "Total completed revenue for 2024, with who sold it."
    """)
    return


@app.cell
def _(engine, mo):
    dq1_wrong = mo.sql(
        f"""
        SELECT sum(o.orderTotal) AS revenue
        FROM orders o
        JOIN employees e ON e.employeeID = o.employeeID
        WHERE o.status = 'completed'
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **What's wrong:** **100,222.48** — the inner join dropped the 181 online orders. **Fix:** leave `employees` out of a question that doesn't need it.
    """)
    return


@app.cell
def _(engine, mo):
    dq1_fixed = mo.sql(
        f"""
        SELECT sum(orderTotal) AS revenue FROM orders WHERE status = 'completed'
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **157,078.41.**

    **Q2.** "Customers with the fewest orders: who needs a reminder email?"
    """)
    return


@app.cell
def _(engine, mo):
    dq2_wrong = mo.sql(
        f"""
        SELECT c.firstName, c.lastName, count(*) AS orders
        FROM customers c
        LEFT JOIN orders o ON o.customerID = c.customerID
        GROUP BY c.customerID, c.firstName, c.lastName
        HAVING count(*) <= 5
        ORDER BY orders, c.lastName
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **What's wrong:** Levon and Astghik show **1** order each — `count(*)` counted the empty match. **Fix:** count the right table's key.
    """)
    return


@app.cell
def _(engine, mo):
    dq2_fixed = mo.sql(
        f"""
        SELECT c.firstName, c.lastName, count(o.orderID) AS orders
        FROM customers c
        LEFT JOIN orders o ON o.customerID = c.customerID
        GROUP BY c.customerID, c.firstName, c.lastName
        HAVING count(o.orderID) <= 5
        ORDER BY orders, c.lastName
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Levon and Astghik have **0** — exactly who the email is for.

    **Q3.** "Completed revenue for every product category, including those with none."
    """)
    return


@app.cell
def _(engine, mo):
    dq3_wrong = mo.sql(
        f"""
        SELECT p.category, coalesce(sum(i.lineTotal), 0) AS revenue
        FROM products p
        LEFT JOIN order_items i ON i.productID = p.productID
        LEFT JOIN orders      o ON o.orderID   = i.orderID
        WHERE o.status = 'completed'
        GROUP BY p.category
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **What's wrong:** **12** rows — the `WHERE` undid the LEFT JOIN, and Chairs is gone. **Fix:** decide what counts as a match before the LEFT JOIN.
    """)
    return


@app.cell
def _(engine, mo):
    dq3_fixed = mo.sql(
        f"""
        SELECT p.category, coalesce(sum(i.lineTotal), 0) AS revenue
        FROM products p
        LEFT JOIN (order_items i
                   JOIN orders o ON o.orderID = i.orderID
                                AND o.status  = 'completed')
               ON i.productID = p.productID
        GROUP BY p.category
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **13** rows, Chairs at **0.00**.

    **Q4.** "Average lifetime spend of the customers who bought in December."
    """)
    return


@app.cell
def _(engine, mo):
    dq4_wrong = mo.sql(
        f"""
        SELECT round(avg(c.moneySpent), 2) AS avg_spend
        FROM customers c
        JOIN orders o ON o.customerID = c.customerID
        WHERE o.orderDate BETWEEN '2024-12-01' AND '2024-12-31'
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **What's wrong:** **7339.20** is an average over December *orders*, not customers — big buyers count once per order (fan-out). **Fix:** pick each customer once.
    """)
    return


@app.cell
def _(engine, mo):
    dq4_fixed = mo.sql(
        f"""
        SELECT round(avg(moneySpent), 2) AS avg_spend, count(*) AS customers
        FROM customers
        WHERE customerID IN (SELECT customerID FROM orders
                             WHERE orderDate BETWEEN '2024-12-01' AND '2024-12-31')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
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
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Appendix — Deeper JOIN traps (from live Q&A)

    Eight short demos from `addendum/`, each on its own tiny scratch tables (suffixed `_01` … `_08`), separate from the shop data.

    **These cells change the database:** each trap first drops and re-creates its scratch tables, so re-running is safe. The tables are left in place at the end (the addendum files drop them; here later cells still read them). To remove them, run each file's last `DROP TABLE` line from `addendum/`.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### TRAP 1: a LEFT JOIN + WHERE on the right table collapses to an INNER JOIN

    Drop this trap's scratch tables if an earlier run left them.
    """)
    return


@app.cell
def _(engine, mo):
    a01_00 = mo.sql(
        f"""
        DROP TABLE IF EXISTS items_01, categories_01 CASCADE
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Create `categories_01`.
    """)
    return


@app.cell
def _(engine, mo):
    a01_01 = mo.sql(
        f"""
        CREATE TABLE categories_01 (
            category_id INT PRIMARY KEY,
            name        TEXT NOT NULL
        )
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Create `items_01`.
    """)
    return


@app.cell
def _(engine, mo):
    a01_02 = mo.sql(
        f"""
        CREATE TABLE items_01 (
            item_id     INT PRIMARY KEY,
            category_id INT NOT NULL REFERENCES categories_01,
            name        TEXT NOT NULL,
            status      TEXT NOT NULL          -- 'in_stock' or 'sold_out'
        )
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Load the sample rows into `categories_01`.
    """)
    return


@app.cell
def _(engine, mo):
    a01_03 = mo.sql(
        f"""
        INSERT INTO categories_01 VALUES
            (1, 'Books'),
            (2, 'Games'),
            (3, 'Toys')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Load the sample rows into `items_01`.
    """)
    return


@app.cell
def _(engine, mo):
    a01_04 = mo.sql(
        f"""
        INSERT INTO items_01 VALUES
            (10, 1, 'Atlas',  'in_stock'),
            (11, 1, 'Novel',  'sold_out'),
            (20, 2, 'Chess',  'in_stock')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **The intent: every category, with its in-stock items**
    "Every category" means Toys should appear too, even with nothing in it.

    **WRONG: the condition on the right table sits in WHERE**
    """)
    return


@app.cell
def _(engine, mo):
    a01_05 = mo.sql(
        f"""
        SELECT c.name AS category, i.name AS item
        FROM categories_01 c
        LEFT JOIN items_01 i ON i.category_id = c.category_id
        WHERE i.status = 'in_stock'
        ORDER BY c.category_id, i.item_id
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG: 2 rows
    ```
    Books | Atlas
    Games | Chess
    ```
    Toys is gone. The LEFT JOIN did keep it (as Toys | NULL), but then
    WHERE tested NULL = 'in_stock', which is not true, and dropped it.


    **The same 2 rows from a plain INNER JOIN**
    """)
    return


@app.cell
def _(engine, mo):
    a01_06 = mo.sql(
        f"""
        SELECT c.name AS category, i.name AS item
        FROM categories_01 c
        JOIN items_01 i ON i.category_id = c.category_id
                       AND i.status = 'in_stock'
        ORDER BY c.category_id, i.item_id
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    2 rows
    ```
    Books | Atlas
    Games | Chess
    ```


    **Proof that the two are identical: difference in both directions**
    """)
    return


@app.cell
def _(engine, mo):
    a01_07 = mo.sql(
        f"""
        (SELECT c.name, i.name
         FROM categories_01 c
         LEFT JOIN items_01 i ON i.category_id = c.category_id
         WHERE i.status = 'in_stock'
         EXCEPT
         SELECT c.name, i.name
         FROM categories_01 c
         JOIN items_01 i ON i.category_id = c.category_id AND i.status = 'in_stock')
        UNION ALL
        (SELECT c.name, i.name
         FROM categories_01 c
         JOIN items_01 i ON i.category_id = c.category_id AND i.status = 'in_stock'
         EXCEPT
         SELECT c.name, i.name
         FROM categories_01 c
         LEFT JOIN items_01 i ON i.category_id = c.category_id
         WHERE i.status = 'in_stock')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Lesson:** a WHERE condition on a LEFT JOIN's right-hand table that can't be true for NULL deletes every NULL-padded row, so the LEFT JOIN silently becomes an INNER JOIN.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### TRAP 2 (the fix for trap 1): put the right-table condition in ON

    Same data as file 01.
    """)
    return


@app.cell
def _(engine, mo):
    a02_00 = mo.sql(
        f"""
        DROP TABLE IF EXISTS items_02, categories_02 CASCADE
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Create `categories_02`.
    """)
    return


@app.cell
def _(engine, mo):
    a02_01 = mo.sql(
        f"""
        CREATE TABLE categories_02 (
            category_id INT PRIMARY KEY,
            name        TEXT NOT NULL
        )
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Create `items_02`.
    """)
    return


@app.cell
def _(engine, mo):
    a02_02 = mo.sql(
        f"""
        CREATE TABLE items_02 (
            item_id     INT PRIMARY KEY,
            category_id INT NOT NULL REFERENCES categories_02,
            name        TEXT NOT NULL,
            status      TEXT NOT NULL          -- 'in_stock' or 'sold_out'
        )
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Load the sample rows into `categories_02`.
    """)
    return


@app.cell
def _(engine, mo):
    a02_03 = mo.sql(
        f"""
        INSERT INTO categories_02 VALUES
            (1, 'Books'),
            (2, 'Games'),
            (3, 'Toys')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Load the sample rows into `items_02`.
    """)
    return


@app.cell
def _(engine, mo):
    a02_04 = mo.sql(
        f"""
        INSERT INTO items_02 VALUES
            (10, 1, 'Atlas',  'in_stock'),
            (11, 1, 'Novel',  'sold_out'),
            (20, 2, 'Chess',  'in_stock')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **BROKEN (from file 01): condition in WHERE**
    """)
    return


@app.cell
def _(engine, mo):
    a02_05 = mo.sql(
        f"""
        SELECT c.name AS category, i.name AS item
        FROM categories_02 c
        LEFT JOIN items_02 i ON i.category_id = c.category_id
        WHERE i.status = 'in_stock'
        ORDER BY c.category_id, i.item_id
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG: 2 rows
    ```
    Books | Atlas
    Games | Chess
    ```


    **FIXED: the same condition moved into ON**
    """)
    return


@app.cell
def _(engine, mo):
    a02_06 = mo.sql(
        f"""
        SELECT c.name AS category, i.name AS item
        FROM categories_02 c
        LEFT JOIN items_02 i ON i.category_id = c.category_id
                            AND i.status = 'in_stock'
        ORDER BY c.category_id, i.item_id
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    FIXED: 3 rows
    ```
    Books | Atlas
    Games | Chess
    Toys  | NULL
    ```
    The status test now only decides which items count as a match.
    Toys has no matching item, so it is NULL-padded and kept.


    **The same contrast, aggregated: in-stock items per category**
    """)
    return


@app.cell
def _(engine, mo):
    a02_07 = mo.sql(
        f"""
        SELECT c.name AS category, count(i.item_id) AS in_stock_items
        FROM categories_02 c
        LEFT JOIN items_02 i ON i.category_id = c.category_id
        WHERE i.status = 'in_stock'
        GROUP BY c.category_id, c.name
        ORDER BY c.category_id
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG: 2 rows   Books 1 | Games 1          (Toys missing)
    """)
    return


@app.cell
def _(engine, mo):
    a02_08 = mo.sql(
        f"""
        SELECT c.name AS category, count(i.item_id) AS in_stock_items
        FROM categories_02 c
        LEFT JOIN items_02 i ON i.category_id = c.category_id
                            AND i.status = 'in_stock'
        GROUP BY c.category_id, c.name
        ORDER BY c.category_id
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Lesson:** with a LEFT JOIN, conditions on the right-hand table belong in ON (they decide what counts as a match); conditions on the left-hand table belong in WHERE (they decide which rows you keep).
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### TRAP 3: an INNER JOIN after a LEFT JOIN silently undoes it

    Chain: authors_03 -> books_03 -> publishers_03
    """)
    return


@app.cell
def _(engine, mo):
    a03_00 = mo.sql(
        f"""
        DROP TABLE IF EXISTS books_03, authors_03, publishers_03 CASCADE
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Create `authors_03`.
    """)
    return


@app.cell
def _(engine, mo):
    a03_01 = mo.sql(
        f"""
        CREATE TABLE authors_03 (
            author_id INT PRIMARY KEY,
            name      TEXT NOT NULL
        )
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Create `publishers_03`.
    """)
    return


@app.cell
def _(engine, mo):
    a03_02 = mo.sql(
        f"""
        CREATE TABLE publishers_03 (
            publisher_id INT PRIMARY KEY,
            name         TEXT NOT NULL
        )
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Create `books_03`.
    """)
    return


@app.cell
def _(engine, mo):
    a03_03 = mo.sql(
        f"""
        CREATE TABLE books_03 (
            book_id      INT PRIMARY KEY,
            author_id    INT NOT NULL REFERENCES authors_03,
            publisher_id INT NOT NULL REFERENCES publishers_03,
            title        TEXT NOT NULL
        )
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Load the sample rows into `authors_03`.
    """)
    return


@app.cell
def _(engine, mo):
    a03_04 = mo.sql(
        f"""
        INSERT INTO authors_03 VALUES
            (1, 'Ann'),
            (2, 'Ben'),
            (3, 'Cid')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Load the sample rows into `publishers_03`.
    """)
    return


@app.cell
def _(engine, mo):
    a03_05 = mo.sql(
        f"""
        INSERT INTO publishers_03 VALUES
            (100, 'North Press'),
            (101, 'South House')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Load the sample rows into `books_03`.
    """)
    return


@app.cell
def _(engine, mo):
    a03_06 = mo.sql(
        f"""
        INSERT INTO books_03 VALUES
            (10, 1, 100, 'First Light'),
            (11, 2, 101, 'Deep Water')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **The intent: every author, with their books and publishers**

    **WRONG: LEFT JOIN, then an INNER JOIN on the next table**
    """)
    return


@app.cell
def _(engine, mo):
    a03_07 = mo.sql(
        f"""
        SELECT a.name AS author, b.title, p.name AS publisher
        FROM authors_03 a
        LEFT JOIN books_03      b ON b.author_id    = a.author_id
        JOIN      publishers_03 p ON p.publisher_id = b.publisher_id
        ORDER BY a.author_id
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG: 2 rows
    ```
    Ann | First Light | North Press
    Ben | Deep Water  | South House
    ```
    Cid is gone. The LEFT JOIN kept him (Cid | NULL, with b.publisher_id
    NULL), but the next join is INNER, and p.publisher_id = NULL is never
    true, so that row found no publisher and was dropped.


    **FIXED: every join after the LEFT JOIN is a LEFT JOIN too**
    """)
    return


@app.cell
def _(engine, mo):
    a03_08 = mo.sql(
        f"""
        SELECT a.name AS author, b.title, p.name AS publisher
        FROM authors_03 a
        LEFT JOIN books_03      b ON b.author_id    = a.author_id
        LEFT JOIN publishers_03 p ON p.publisher_id = b.publisher_id
        ORDER BY a.author_id
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Lesson:** once a table is LEFT JOINed, any later INNER JOIN (or WHERE test) on its columns throws away the NULL-padded rows again — keep the rest of the chain LEFT, or the first LEFT JOIN did nothing.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### TRAP 4: the "WHERE condition OR column IS NULL" patch

    looks like the ON fix — but only re-admits rows with NO match

    Starts from the same data as files 01 and 02.
    """)
    return


@app.cell
def _(engine, mo):
    a04_00 = mo.sql(
        f"""
        DROP TABLE IF EXISTS items_04, categories_04 CASCADE
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Create `categories_04`.
    """)
    return


@app.cell
def _(engine, mo):
    a04_01 = mo.sql(
        f"""
        CREATE TABLE categories_04 (
            category_id INT PRIMARY KEY,
            name        TEXT NOT NULL
        )
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Create `items_04`.
    """)
    return


@app.cell
def _(engine, mo):
    a04_02 = mo.sql(
        f"""
        CREATE TABLE items_04 (
            item_id     INT PRIMARY KEY,
            category_id INT NOT NULL REFERENCES categories_04,
            name        TEXT NOT NULL,
            status      TEXT NOT NULL          -- 'in_stock' or 'sold_out'
        )
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Load the sample rows into `categories_04`.
    """)
    return


@app.cell
def _(engine, mo):
    a04_03 = mo.sql(
        f"""
        INSERT INTO categories_04 VALUES
            (1, 'Books'),
            (2, 'Games'),
            (3, 'Toys')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Load the sample rows into `items_04`.
    """)
    return


@app.cell
def _(engine, mo):
    a04_04 = mo.sql(
        f"""
        INSERT INTO items_04 VALUES
            (10, 1, 'Atlas',  'in_stock'),
            (11, 1, 'Novel',  'sold_out'),
            (20, 2, 'Chess',  'in_stock')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Part A: on this data, the patch and the ON fix agree**

    The ON fix (file 02):
    """)
    return


@app.cell
def _(engine, mo):
    a04_05 = mo.sql(
        f"""
        SELECT c.name AS category, i.name AS item
        FROM categories_04 c
        LEFT JOIN items_04 i ON i.category_id = c.category_id
                            AND i.status = 'in_stock'
        ORDER BY c.category_id, i.item_id
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    3 rows:  Books | Atlas,  Games | Chess,  Toys | NULL

    The patch: keep the condition in WHERE, re-admit the NULL-padded rows
    """)
    return


@app.cell
def _(engine, mo):
    a04_06 = mo.sql(
        f"""
        SELECT c.name AS category, i.name AS item
        FROM categories_04 c
        LEFT JOIN items_04 i ON i.category_id = c.category_id
        WHERE i.status = 'in_stock' OR i.item_id IS NULL
        ORDER BY c.category_id, i.item_id
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    3 rows:  Books | Atlas,  Games | Chess,  Toys | NULL   (same as above)

    It looks like the same logic spelled differently. It isn't quite.


    **Part B: add a category whose only item FAILS the condition**
    """)
    return


@app.cell
def _(engine, mo):
    a04_07 = mo.sql(
        f"""
        INSERT INTO categories_04 VALUES (4, 'Puzzles')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Load the sample rows into `items_04`.
    """)
    return


@app.cell
def _(engine, mo):
    a04_08 = mo.sql(
        f"""
        INSERT INTO items_04 VALUES (40, 4, 'Maze', 'sold_out')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The ON fix:
    """)
    return


@app.cell
def _(engine, mo):
    a04_09 = mo.sql(
        f"""
        SELECT c.name AS category, i.name AS item
        FROM categories_04 c
        LEFT JOIN items_04 i ON i.category_id = c.category_id
                            AND i.status = 'in_stock'
        ORDER BY c.category_id, i.item_id
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    4 rows:  Books | Atlas,  Games | Chess,  Toys | NULL,  Puzzles | NULL

    The patch:
    """)
    return


@app.cell
def _(engine, mo):
    a04_10 = mo.sql(
        f"""
        SELECT c.name AS category, i.name AS item
        FROM categories_04 c
        LEFT JOIN items_04 i ON i.category_id = c.category_id
        WHERE i.status = 'in_stock' OR i.item_id IS NULL
        ORDER BY c.category_id, i.item_id
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Lesson:** "OR right_key IS NULL" re-admits only left rows that matched nothing; it is not the same as moving the condition into ON, which keeps every left row. Write the condition in ON.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### TRAP 5: IS NULL on a nullable column — ON and WHERE answer

    two different questions
    """)
    return


@app.cell
def _(engine, mo):
    a05_00 = mo.sql(
        f"""
        DROP TABLE IF EXISTS lines_05, products_05 CASCADE
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Create `products_05`.
    """)
    return


@app.cell
def _(engine, mo):
    a05_01 = mo.sql(
        f"""
        CREATE TABLE products_05 (
            product_id INT PRIMARY KEY,
            name       TEXT NOT NULL
        )
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Create `lines_05`.
    """)
    return


@app.cell
def _(engine, mo):
    a05_02 = mo.sql(
        f"""
        CREATE TABLE lines_05 (
            line_id       INT PRIMARY KEY,
            product_id    INT NOT NULL REFERENCES products_05,
            discount_code TEXT                 -- nullable: NULL = sold at full price
        )
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Load the sample rows into `products_05`.
    """)
    return


@app.cell
def _(engine, mo):
    a05_03 = mo.sql(
        f"""
        INSERT INTO products_05 VALUES
            (1, 'A'),
            (2, 'B'),
            (3, 'C')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Load the sample rows into `lines_05`.
    """)
    return


@app.cell
def _(engine, mo):
    a05_04 = mo.sql(
        f"""
        INSERT INTO lines_05 VALUES
            (1, 1, NULL),                      -- A: one full-price line ...
            (2, 1, 'SPRING'),                  --    ... and one discounted line
            (3, 2, 'SPRING')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    C: no lines at all


    **Version 1: the NULL test in WHERE**
    """)
    return


@app.cell
def _(engine, mo):
    a05_05 = mo.sql(
        f"""
        SELECT p.name AS product, l.line_id, l.discount_code
        FROM products_05 p
        LEFT JOIN lines_05 l ON l.product_id = p.product_id
        WHERE l.discount_code IS NULL
        ORDER BY p.product_id
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    2 rows
    ```
    A | 1    | NULL      <- A's real full-price line
    C | NULL | NULL      <- C's NULL-padded placeholder (no lines at all)
    ```
    B is gone.


    **Version 2: the NULL test in ON**
    """)
    return


@app.cell
def _(engine, mo):
    a05_06 = mo.sql(
        f"""
        SELECT p.name AS product, l.line_id, l.discount_code
        FROM products_05 p
        LEFT JOIN lines_05 l ON l.product_id = p.product_id
                            AND l.discount_code IS NULL
        ORDER BY p.product_id
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Lesson:** when the condition tests a nullable column for NULL, moving it between ON and WHERE changes the question, not just the correctness — WHERE sees both real NULLs and padding NULLs, ON sees only real rows.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### TRAP 6: NATURAL JOIN joins on EVERY shared column name — silently

    A minimal version of the real orders/sales collision (97 rows, not 600).
    """)
    return


@app.cell
def _(engine, mo):
    a06_00 = mo.sql(
        f"""
        DROP TABLE IF EXISTS invoices_06, payments_06 CASCADE
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Both tables have columns named id, amount and status.
    """)
    return


@app.cell
def _(engine, mo):
    a06_01 = mo.sql(
        f"""
        CREATE TABLE invoices_06 (
            id     INT PRIMARY KEY,
            amount NUMERIC(8,2) NOT NULL,
            status TEXT                        -- nullable
        )
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Create `payments_06`.
    """)
    return


@app.cell
def _(engine, mo):
    a06_02 = mo.sql(
        f"""
        CREATE TABLE payments_06 (
            id      INT PRIMARY KEY,           -- same id = payment for that invoice
            amount  NUMERIC(8,2) NOT NULL,
            status  TEXT,                      -- nullable
            paid_on DATE NOT NULL
        )
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Load the sample rows into `invoices_06`.
    """)
    return


@app.cell
def _(engine, mo):
    a06_03 = mo.sql(
        f"""
        INSERT INTO invoices_06 VALUES
            (1, 100.00, 'closed'),
            (2, 250.00, 'closed'),
            (3,  80.00, 'open'),
            (4,  60.00, NULL)
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Load the sample rows into `payments_06`.
    """)
    return


@app.cell
def _(engine, mo):
    a06_04 = mo.sql(
        f"""
        INSERT INTO payments_06 VALUES
            (1, 100.00, 'closed', DATE '2024-03-01'),   -- agrees on all three
            (2, 250.00, 'closed', DATE '2024-03-02'),   -- agrees on all three
            (3,  50.00, 'open',   DATE '2024-03-03'),   -- partial payment: amount differs
            (4,  60.00, NULL,     DATE '2024-03-04')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **The intent: each invoice next to its payment (4 pairs)**

    **WRONG: NATURAL JOIN**
    """)
    return


@app.cell
def _(engine, mo):
    a06_05 = mo.sql(
        f"""
        SELECT *
        FROM invoices_06 NATURAL JOIN payments_06
        ORDER BY id
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG: 2 rows (ids 1 and 2)
    Invoice 3 is dropped because the amounts differ; invoice 4 because
    NULL = NULL is not true. Nothing in the query says so.


    **The hidden condition, spelled out**
    """)
    return


@app.cell
def _(engine, mo):
    a06_06 = mo.sql(
        f"""
        SELECT i.id, i.amount, i.status, p.paid_on
        FROM invoices_06 i
        JOIN payments_06 p ON p.id     = i.id
                          AND p.amount = i.amount
                          AND p.status = i.status
        ORDER BY i.id
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    2 rows (ids 1 and 2): exactly what NATURAL JOIN did.


    **FIXED: say which column the join is on**
    """)
    return


@app.cell
def _(engine, mo):
    a06_07 = mo.sql(
        f"""
        SELECT id, i.amount AS invoiced, p.amount AS paid, p.paid_on
        FROM invoices_06 i
        JOIN payments_06 p USING (id)
        ORDER BY id
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Lesson:** NATURAL JOIN matches on every column name the tables happen to share, including ones that differ or are NULL — write the join condition yourself with ON or USING so it is visible and stable.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### TRAP 7: AND binds tighter than OR — inside ON too

    Drop this trap's scratch tables if an earlier run left them.
    """)
    return


@app.cell
def _(engine, mo):
    a07_00 = mo.sql(
        f"""
        DROP TABLE IF EXISTS transfers_07, accounts_07 CASCADE
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Create `accounts_07`.
    """)
    return


@app.cell
def _(engine, mo):
    a07_01 = mo.sql(
        f"""
        CREATE TABLE accounts_07 (
            account_id INT PRIMARY KEY,
            owner      TEXT NOT NULL
        )
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Create `transfers_07`.
    """)
    return


@app.cell
def _(engine, mo):
    a07_02 = mo.sql(
        f"""
        CREATE TABLE transfers_07 (
            transfer_id INT PRIMARY KEY,
            account_id  INT NOT NULL REFERENCES accounts_07,
            method      TEXT NOT NULL,         -- 'card' or 'cash'
            flagged     BOOLEAN NOT NULL
        )
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Load the sample rows into `accounts_07`.
    """)
    return


@app.cell
def _(engine, mo):
    a07_03 = mo.sql(
        f"""
        INSERT INTO accounts_07 VALUES
            (1, 'Ann'),
            (2, 'Ben'),
            (3, 'Cid')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Load the sample rows into `transfers_07`.
    """)
    return


@app.cell
def _(engine, mo):
    a07_04 = mo.sql(
        f"""
        INSERT INTO transfers_07 VALUES
            (501, 1, 'card', false),
            (502, 2, 'cash', true),            -- flagged, and it belongs to Ben
            (503, 3, 'cash', false)
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **The intent: each account's transfers that were by card OR flagged**

    **WRONG: no parentheses**
    """)
    return


@app.cell
def _(engine, mo):
    a07_05 = mo.sql(
        f"""
        SELECT a.owner, t.transfer_id, t.account_id AS transfer_belongs_to
        FROM accounts_07 a
        JOIN transfers_07 t ON t.account_id = a.account_id
                           AND t.method = 'card'
                            OR t.flagged
        ORDER BY a.account_id, t.transfer_id
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG: 4 rows
    ```
    Ann | 501 | 1
    Ann | 502 | 2      <- Ben's transfer, attached to Ann
    Ben | 502 | 2
    Cid | 502 | 2      <- Ben's transfer, attached to Cid
    ```
    AND binds tighter, so this is
    ```
    (t.account_id = a.account_id AND t.method = 'card') OR t.flagged
    ```
    A flagged transfer satisfies the ON on its own, whatever the account:
    it matches EVERY account.


    **FIXED: parenthesize the OR**
    """)
    return


@app.cell
def _(engine, mo):
    a07_06 = mo.sql(
        f"""
        SELECT a.owner, t.transfer_id, t.account_id AS transfer_belongs_to
        FROM accounts_07 a
        JOIN transfers_07 t ON t.account_id = a.account_id
                           AND (t.method = 'card' OR t.flagged)
        ORDER BY a.account_id, t.transfer_id
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Lesson:** whenever AND and OR appear together — in ON as much as in WHERE — put parentheses around the OR, or the join key can stop applying to some rows.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### NOT A TRAP: several conditional counts in one query —

    count(*) FILTER (WHERE ...) vs the older CASE WHEN
    """)
    return


@app.cell
def _(engine, mo):
    a08_00 = mo.sql(
        f"""
        DROP TABLE IF EXISTS tickets_08 CASCADE
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Create `tickets_08`.
    """)
    return


@app.cell
def _(engine, mo):
    a08_01 = mo.sql(
        f"""
        CREATE TABLE tickets_08 (
            ticket_id INT PRIMARY KEY,
            priority  TEXT NOT NULL,           -- 'high' or 'low'
            status    TEXT NOT NULL            -- 'open' or 'closed'
        )
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Load the sample rows into `tickets_08`.
    """)
    return


@app.cell
def _(engine, mo):
    a08_02 = mo.sql(
        f"""
        INSERT INTO tickets_08 VALUES
            (1, 'high', 'open'),
            (2, 'high', 'closed'),
            (3, 'low',  'open'),
            (4, 'low',  'open'),
            (5, 'high', 'open')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **FILTER: each aggregate sees only the rows its condition keeps**
    """)
    return


@app.cell
def _(engine, mo):
    a08_03 = mo.sql(
        f"""
        SELECT count(*)                                                AS total,
               count(*) FILTER (WHERE priority = 'high')               AS high,
               count(*) FILTER (WHERE status = 'open')                 AS open,
               count(*) FILTER (WHERE priority = 'high' AND status = 'open') AS high_open
        FROM tickets_08
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    1 row:  total 5 | high 3 | open 4 | high_open 2


    **The older idiom: sum a CASE that is 1 or 0**
    """)
    return


@app.cell
def _(engine, mo):
    a08_04 = mo.sql(
        f"""
        SELECT count(*)                                                        AS total,
               sum(CASE WHEN priority = 'high' THEN 1 ELSE 0 END)              AS high,
               sum(CASE WHEN status = 'open' THEN 1 ELSE 0 END)                AS open,
               sum(CASE WHEN priority = 'high' AND status = 'open' THEN 1 ELSE 0 END) AS high_open
        FROM tickets_08
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    1 row:  total 5 | high 3 | open 4 | high_open 2   (identical)


    **Proof they agree**
    """)
    return


@app.cell
def _(engine, mo):
    a08_05 = mo.sql(
        f"""
        SELECT count(*), count(*) FILTER (WHERE priority = 'high'),
               count(*) FILTER (WHERE status = 'open'),
               count(*) FILTER (WHERE priority = 'high' AND status = 'open')
        FROM tickets_08
        EXCEPT
        SELECT count(*), sum(CASE WHEN priority = 'high' THEN 1 ELSE 0 END),
               sum(CASE WHEN status = 'open' THEN 1 ELSE 0 END),
               sum(CASE WHEN priority = 'high' AND status = 'open' THEN 1 ELSE 0 END)
        FROM tickets_08
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Lesson:** FILTER (WHERE ...) says "count only these rows" directly, and several FILTERs give several conditional counts in one pass; the CASE WHEN version means the same and works in any SQL database.
    """)
    return


if __name__ == "__main__":
    app.run()
