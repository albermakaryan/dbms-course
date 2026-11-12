import marimo

__generated_with = "0.25.0"
app = marimo.App(width="medium")


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    # Recap — Lectures 1 to 6

    Everything important from the first six lectures, in one notebook, on **one database**: the shop data of Lectures 4–6 (`customers`, `employees`, `products`, `orders` = the order header, `order_items` = the lines) plus Lecture 4's star schema (`fact_sales` and its four `dim_` tables).

    Each lecture gets one section: the ideas in a few lines, then the queries that matter, run live. The traps are shown the way the lectures showed them: **wrong query → why it's wrong → fixed query**, with the real numbers on screen.

    **Before you run this:** the notebook reads the `lecture06` database, which Lecture 6's setup script builds. From the `lectures/lecture_6/` folder:

    ```
    psql postgres
    \i steps/00-setup.sql
    ```

    Then, from `lectures/recap/`:

    ```
    RECAP_DSN=postgresql://postgres:postgres@localhost:5432/lecture06 marimo edit recap-notebook.py
    ```

    (`postgres:postgres` on `localhost:5432` is the default; set `RECAP_DSN` only if yours differs.) No cell changes the data: the statements that try to are *meant* to fail, and each shows PostgreSQL's error instead of stopping the notebook.
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
    # psql + lectures/lecture_6/steps/00-setup.sql; set RECAP_DSN if yours differs.
    engine = psycopg.connect(
        os.environ.get(
            "RECAP_DSN", "postgresql://postgres:postgres@localhost:5432/lecture06"
        ),
        autocommit=True,
    )
    return (engine,)


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Check the data first.** You should see **30 / 8 / 37 / 600 / 965**, then **366** dates and **965** fact rows.
    """)
    return


@app.cell
def _(engine, mo):
    p0_counts = mo.sql(
        f"""
        SELECT 'customers' AS t, count(*) FROM customers
        UNION ALL SELECT 'employees',   count(*) FROM employees
        UNION ALL SELECT 'products',    count(*) FROM products
        UNION ALL SELECT 'orders',      count(*) FROM orders
        UNION ALL SELECT 'order_items', count(*) FROM order_items
        UNION ALL SELECT 'dim_date',    count(*) FROM dim_date
        UNION ALL SELECT 'fact_sales',  count(*) FROM fact_sales
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **The facts you already know.** Every lecture checked its queries against these. A query that contradicts one of them is wrong, whatever it looks like.

    | Fact | Value |
    |---|---|
    | Orders / completed orders | 600 / 529 |
    | Order lines | 965 |
    | Completed revenue | **157,078.41** |
    | Customers who never ordered | 2: Levon Arakelyan, Astghik Danielyan |
    | Product never sold | Ergonomic Chair Pro (productID 35, category Chairs) |
    | Online orders (no salesperson, `employeeID` NULL) | 181 |
    | Two different customers named | Anna Sargsyan |
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Lecture 1 — Database foundations

    **Data → processing → business value.** Data is raw material: values, facts, observations. It is worth something only after it has been organised and analysed.

    **Why files aren't enough.** When every application keeps its own files (invoicing, CRM, a map system), the same customer is stored several times, in several formats. That causes:

    - **redundancy and inconsistency**: copies drift apart, and nobody knows which one is true;
    - **no shared access**: each application can read only its own files;
    - **weak security and backup**, left to each application.

    **The database approach.** One central store, managed by a **DBMS** (Database Management System), the software layer between the data and everyone who uses it. Applications share the same, up-to-date data; they all ask for it in one standard language, **SQL**; the DBMS handles security, backup and recovery, and many users at once. Examples: PostgreSQL, MySQL, Oracle, MongoDB.

    | | File system | Database |
    |---|---|---|
    | Redundancy | high: duplicated across files | removed by normalisation (Lecture 2) |
    | Consistency | conflicting copies | integrity enforced for every application |
    | Security and backup | up to each application | built in, central |
    | Sharing | none, each app has its own files | standard access via SQL |

    **A database system is more than software**: hardware, software (the OS and the DBMS), the data, an access language (SQL), procedures (rules for using it) and people (administrators, developers, end users).

    **Schema vs. state.** The **schema** is the blueprint: tables, columns, types, relationships, constraints. It rarely changes. The **state** is the data inside at one moment. It changes with every order.

    **Metadata is data about data**: table names, column names and types, owners, creation dates. The DBMS stores its own metadata in tables you can query, like any other table:
    """)
    return


@app.cell
def _(engine, mo):
    l1_metadata = mo.sql(
        f"""
        SELECT table_name, count(*) AS columns
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name IN ('customers', 'employees', 'products', 'orders', 'order_items')
        GROUP BY table_name
        ORDER BY table_name;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **SQL and NoSQL.** Relational databases (tables, rows, columns, SQL) dominate structured business data. Other shapes exist for other needs:

    | Family | Stores data as | Example |
    |---|---|---|
    | Relational | tables with keys | MySQL, PostgreSQL |
    | Analytical (OLAP) | data organised for summarising | Snowflake (the product, not the schema shape in Lecture 4) |
    | Key–value | a key and its value | Redis |
    | Column-family | columns grouped into families | Cassandra |
    | Graph | nodes and the links between them | Neo4j |
    | Document | nested documents (JSON) | MongoDB |

    **The closing idea of Lecture 1:** AI doesn't replace the database. AI is limited by the quality of the database: its schema, its metadata, its relationships.

    *Source: Lecture 1 slides (`lecture_1/Database_Foundations_and_Frontiers.pptx`), slides 3–18.*
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Lecture 2 — From one file to related tables

    ### Redundancy, and the three anomalies

    Lecture 2 started from one flat sales file, one row per sale, with the customer's details typed again on every row. Our current data would look like that if you stored the lines with everything joined in. Count how many times each customer's details would be repeated:
    """)
    return


@app.cell
def _(engine, mo):
    l2_redundancy = mo.sql(
        f"""
        SELECT c.firstName, c.lastName, c.email, count(*) AS times_stored_in_a_flat_file
        FROM order_items i
        JOIN orders    o ON o.orderID    = i.orderID
        JOIN customers c ON c.customerID = o.customerID
        GROUP BY c.customerID, c.firstName, c.lastName, c.email
        ORDER BY times_stored_in_a_flat_file DESC
        LIMIT 3;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Davit's email would be stored **87** times. In the normalized tables it is stored once. Redundancy causes three **anomalies**:

    | Anomaly | What happens |
    |---|---|
    | **Update** | a fact changes, and you must fix *every* copy; miss one and two "truths" exist (**inconsistency**) |
    | **Insertion** | you can't record something (a new product) until it appears in a sale |
    | **Deletion** | deleting the last sale of something deletes all you knew about it |

    ### Modeling: entities, relationships, cardinality

    - **Entity**: a thing the business tracks (customer, employee, product). **Attribute**: a fact about it. **Relationship**: how entities interact (a customer *places* orders).
    - **Cardinality**: how many relate to how many. One customer places many orders (**1:N**). An order holds many products and a product is in many orders (**M:N**), which needs a **junction table** in between: `order_items`.
    - An **ER diagram** draws it, in **crow's foot notation**: `||` exactly one, `o|` zero or one, `|{` one or many, `o{` zero or many.

    The shop, as Lectures 4–6 use it:
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.mermaid(
        """
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
        """
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### Keys: why we invent ids

    What identifies a customer? Not the name:
    """)
    return


@app.cell
def _(engine, mo):
    l2_two_annas = mo.sql(
        f"""
        SELECT customerID, firstName, lastName, email, city, birthDate
        FROM customers
        WHERE firstName = 'Anna' AND lastName = 'Sargsyan';
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Two different people. A **natural key** made of real attributes (first + last name + birth date) is long, can contain typos, and still isn't guaranteed unique. So we invent a **surrogate key**, `customerID`: one small number that means nothing outside the database and never changes.

    - **Primary key (PK)**: identifies a row. Never NULL, never duplicated.
    - **Foreign key (FK)**: a column whose value must exist as a key in another table (*referential integrity*).

    ### Functional dependencies and normal forms

    **A → B** ("A determines B"): each value of A comes with exactly one value of B. `customerID → email` holds.

    | Normal form | Rule | Broken by |
    |---|---|---|
    | **1NF** | every cell holds one value; no repeating groups | `'Audio, Laptops'` in one cell |
    | **2NF** | no column depends on only *part* of a composite key | `productCategory` stored in `order_items`: depends on `productID` alone |
    | **3NF** | no column depends on another non-key column (no **transitive** dependency) | the flat file: orderID → customer → customer's email |

    Splitting the flat file into one table per entity removed all three problems. Most business schemas stop at 3NF.

    ### SQL: declarative, five sub-languages

    SQL is **declarative**: you say *what* you want, and the database decides *how* to get it.

    | Part | Does | Statements |
    |---|---|---|
    | **DDL** (definition) | defines structure | `CREATE`, `ALTER`, `DROP` |
    | **DML** (manipulation) | changes data | `INSERT`, `UPDATE`, `DELETE` |
    | **DQL** (query) | reads data | `SELECT` |
    | **DCL** (control) | controls access | `GRANT`, `REVOKE` |
    | **TCL** (transactions) | groups changes | `COMMIT`, `ROLLBACK` |

    **Types are rules too.** Money is `DECIMAL(10,2)`, exact to the cent. Store numbers as text and they sort as text, character by character:
    """)
    return


@app.cell
def _(engine, mo):
    l2_text_sort = mo.sql(
        f"""
        SELECT unnest(ARRAY['9.99', '52.00', '100.00']) AS price_as_text
        ORDER BY 1;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### Constraints: the database says no

    Constraints are rules the DBMS enforces on every write: `PRIMARY KEY`, `REFERENCES` (foreign key), `UNIQUE`, `NOT NULL`, `CHECK`. They are metadata too, so you can list them:
    """)
    return


@app.cell
def _(engine, mo):
    l2_constraints = mo.sql(
        f"""
        SELECT conname AS constraint_name,
               CASE contype WHEN 'p' THEN 'PRIMARY KEY' WHEN 'f' THEN 'FOREIGN KEY'
                            WHEN 'c' THEN 'CHECK'       WHEN 'u' THEN 'UNIQUE'
                            WHEN 'n' THEN 'NOT NULL' END AS kind,
               pg_get_constraintdef(oid) AS definition
        FROM pg_constraint
        WHERE conrelid = 'orders'::regclass
        ORDER BY kind, constraint_name;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    On PostgreSQL 14 and 16 you get 8 rows. PostgreSQL 18 also lists the `NOT NULL` rules here, so you get 16.

    Now break each rule once. Every statement below fails on purpose, so nothing is changed. **Read the messages**: each one names the constraint that stopped it.

    An order for customer 999, who doesn't exist (foreign key):
    """)
    return


@app.cell
def _(engine, mo, psycopg):
    # Error on purpose -- shows PostgreSQL's message instead of stopping the notebook.
    try:
        engine.execute("""
        INSERT INTO orders (orderID, customerID, employeeID, orderDate, orderTime, channel, paymentMethod, status, orderTotal)
        VALUES (9999, 999, 1, '2024-08-15', '12:00', 'in_store', 'card', 'completed', 100.00)
        """)
        _shown = mo.callout(
            mo.md("No error?! This statement was supposed to fail."), kind="warn"
        )
    except psycopg.Error as _e:
        _shown = mo.callout(
            mo.md(f"**ERROR:** `{_e.diag.message_primary}`"), kind="danger"
        )
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    A status the shop doesn't use (`CHECK`):
    """)
    return


@app.cell
def _(engine, mo, psycopg):
    # Error on purpose -- shows PostgreSQL's message instead of stopping the notebook.
    try:
        engine.execute("""
        INSERT INTO orders (orderID, customerID, employeeID, orderDate, orderTime, channel, paymentMethod, status, orderTotal)
        VALUES (9999, 1, 1, '2024-08-15', '12:00', 'in_store', 'card', 'shipped', 100.00)
        """)
        _shown = mo.callout(
            mo.md("No error?! This statement was supposed to fail."), kind="warn"
        )
    except psycopg.Error as _e:
        _shown = mo.callout(
            mo.md(f"**ERROR:** `{_e.diag.message_primary}`"), kind="danger"
        )
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    An orderID that is already taken (primary key):
    """)
    return


@app.cell
def _(engine, mo, psycopg):
    # Error on purpose -- shows PostgreSQL's message instead of stopping the notebook.
    try:
        engine.execute("""
        INSERT INTO orders (orderID, customerID, employeeID, orderDate, orderTime, channel, paymentMethod, status, orderTotal)
        VALUES (1001, 1, 1, '2024-08-15', '12:00', 'in_store', 'card', 'completed', 100.00)
        """)
        _shown = mo.callout(
            mo.md("No error?! This statement was supposed to fail."), kind="warn"
        )
    except psycopg.Error as _e:
        _shown = mo.callout(
            mo.md(f"**ERROR:** `{_e.diag.message_primary}`"), kind="danger"
        )
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    No total at all (`NOT NULL`):
    """)
    return


@app.cell
def _(engine, mo, psycopg):
    # Error on purpose -- shows PostgreSQL's message instead of stopping the notebook.
    try:
        engine.execute("""
        INSERT INTO orders (orderID, customerID, employeeID, orderDate, orderTime, channel, paymentMethod, status)
        VALUES (9999, 1, 1, '2024-08-15', '12:00', 'in_store', 'card', 'completed')
        """)
        _shown = mo.callout(
            mo.md("No error?! This statement was supposed to fail."), kind="warn"
        )
    except psycopg.Error as _e:
        _shown = mo.callout(
            mo.md(f"**ERROR:** `{_e.diag.message_primary}`"), kind="danger"
        )
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Deleting a product that order lines still point to (the foreign key protects the *other* table):
    """)
    return


@app.cell
def _(engine, mo, psycopg):
    # Error on purpose -- shows PostgreSQL's message instead of stopping the notebook.
    try:
        engine.execute("""
        DELETE FROM products WHERE productID = 1
        """)
        _shown = mo.callout(
            mo.md("No error?! This statement was supposed to fail."), kind="warn"
        )
    except psycopg.Error as _e:
        _shown = mo.callout(
            mo.md(f"**ERROR:** `{_e.diag.message_primary}`"), kind="danger"
        )
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    A spreadsheet would have accepted all five, silently. That is the difference between a file and a database.

    ### Changing and removing things

    | Statement | Removes / changes | Table survives? |
    |---|---|---|
    | `ALTER TABLE … ADD / RENAME / DROP COLUMN`, `ADD CONSTRAINT` | the structure, on live data | yes |
    | `DELETE FROM t WHERE …` | matching rows | yes |
    | `TRUNCATE t` | every row | yes, empty |
    | `DROP TABLE t` | the table itself | no |

    All of them respect foreign keys. `CASCADE` overrides that on purpose: on `DROP TABLE`, it drops the dependent *constraint*, not the other table's rows. Two Lecture 2 rules for `ALTER`: you can't `SET NOT NULL` while NULLs exist (backfill first), and adding a `DEFAULT` fills existing rows for you.

    ### The split is lossless

    Splitting into tables lost nothing: joining them back rebuilds every line.
    """)
    return


@app.cell
def _(engine, mo):
    l2_lossless = mo.sql(
        f"""
        SELECT count(*) AS lines_rebuilt
        FROM order_items i
        JOIN orders    o ON o.orderID    = i.orderID
        JOIN customers c ON c.customerID = o.customerID
        JOIN products  p ON p.productID  = i.productID;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **965**, every line. Lecture 4 (4.13) proves it fully: rebuilt rows `EXCEPT` the original flat file gives 0 rows.

    *Source: Lecture 2 notes, Parts 1–9 (`lecture_2/lecture-02-notes.md`); Lecture 5 notes, "The data" (order_items); Lecture 4 notes, 4.13.*
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Lecture 3 — Asking questions of one table

    ### The order a query runs in

    You *write* `SELECT … FROM … WHERE … GROUP BY … HAVING … ORDER BY … LIMIT`. The database *runs* it in this order:

    ```
    1. FROM       pick the table(s)
    2. WHERE      keep rows that pass
    3. GROUP BY   collapse rows into groups
    4. HAVING     keep groups that pass
    5. SELECT     compute the output columns, and name them
    6. DISTINCT   drop duplicate output rows
    7. ORDER BY   sort
    8. LIMIT      cut off
    ```

    Two consequences. An **alias** born in `SELECT` (step 5) can't be used in `WHERE` (step 2). An **aggregate** can't be used in `WHERE`, which runs before any group exists; use `HAVING`. Error on purpose:
    """)
    return


@app.cell
def _(engine, mo, psycopg):
    # Error on purpose -- shows PostgreSQL's message instead of stopping the notebook.
    try:
        engine.execute("""
        SELECT orderID, orderTotal * 0.2 AS vat
        FROM orders
        WHERE vat > 100
        """)
        _shown = mo.callout(
            mo.md("No error?! This statement was supposed to fail."), kind="warn"
        )
    except psycopg.Error as _e:
        _shown = mo.callout(
            mo.md(f"**ERROR:** `{_e.diag.message_primary}`"), kind="danger"
        )
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### Expressions and CASE

    A `SELECT` column can be any expression: arithmetic, `||` for text, `round`, `EXTRACT`, `to_char`, date arithmetic. **`CASE WHEN`** gives a value that depends on a condition. Group by it, and you have buckets:
    """)
    return


@app.cell
def _(engine, mo):
    l3_case_buckets = mo.sql(
        f"""
        SELECT CASE WHEN orderTotal < 100  THEN '1: under 100'
                    WHEN orderTotal < 1000 THEN '2: 100 to 999.99'
                    ELSE                        '3: 1000 and over' END AS size,
               count(*)        AS orders,
               sum(orderTotal) AS revenue
        FROM orders
        WHERE status = 'completed'
        GROUP BY size
        ORDER BY size;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    223 + 269 + 37 = 529 completed orders, and the three revenues add up to 157,078.41. **Every bucket report should add back up to the total.**

    ### WHERE, and the precedence trap

    `=`, `<>`, `<`, `BETWEEN` (inclusive at both ends), `IN (…)`, `LIKE` / `ILIKE` with `%` and `_`, `IS NULL`. Text comparison is case-sensitive.

    "Returned or cancelled orders, placed online." Written the way you'd say it:
    """)
    return


@app.cell
def _(engine, mo):
    l3_precedence_wrong = mo.sql(
        f"""
        SELECT count(*) AS orders
        FROM orders
        WHERE status = 'returned' OR status = 'cancelled' AND channel = 'online';
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **WRONG: 49.** `AND` binds tighter than `OR`, so this means *returned (any channel), or (cancelled and online)*. All 44 returned orders got in. With the parentheses you meant:
    """)
    return


@app.cell
def _(engine, mo):
    l3_precedence_fix = mo.sql(
        f"""
        SELECT count(*) AS orders
        FROM orders
        WHERE (status = 'returned' OR status = 'cancelled') AND channel = 'online';
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **17.** Both numbers look plausible, and nothing warned you. When `AND` and `OR` share a `WHERE`, always use parentheses.

    ### NULL: "no value"

    The online orders have no salesperson: `employeeID` is NULL. Try to find them:
    """)
    return


@app.cell
def _(engine, mo):
    l3_null_wrong = mo.sql(
        f"""
        SELECT count(*) AS orders FROM orders WHERE employeeID = NULL;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **0**, and no error. Any comparison with NULL is NULL ("unknown"), and `WHERE` keeps only rows where the condition is **true**. The only way to ask is `IS NULL`:
    """)
    return


@app.cell
def _(engine, mo):
    l3_null_fix = mo.sql(
        f"""
        SELECT count(*) AS orders FROM orders WHERE employeeID IS NULL;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **181.** NULL also spreads through arithmetic (`NULL + 1` is NULL). It sorts as if it were the largest value (`NULLS FIRST` / `NULLS LAST` change that). Aggregates skip it, and `GROUP BY` puts all NULLs into one group of their own.

    ### count(*), count(column), count(DISTINCT column)
    """)
    return


@app.cell
def _(engine, mo):
    l3_counts = mo.sql(
        f"""
        SELECT count(*)                   AS all_rows,
               count(employeeID)          AS with_employee,
               count(DISTINCT employeeID) AS different_employees,
               count(rating)              AS rated,
               round(avg(rating), 2)      AS avg_rating
        FROM orders;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    - `count(*)` counts **rows** (600).
    - `count(column)` counts **non-NULL values** (419 orders have a salesperson, 322 have a rating).
    - `count(DISTINCT column)` counts **different values** (8 salespeople).
    - `avg(rating)` = 4.23 is the average of the **322 rated** orders. The 278 unrated ones are skipped, not counted as 0.

    ### GROUP BY and HAVING

    `GROUP BY` gives one row per group. Every column in `SELECT` must be grouped or inside an aggregate.
    """)
    return


@app.cell
def _(engine, mo):
    l3_group_by = mo.sql(
        f"""
        SELECT channel, status, count(*) AS orders, sum(orderTotal) AS total
        FROM orders
        GROUP BY channel, status
        ORDER BY channel, status;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Completed revenue is 100,222.48 in store + 56,855.93 online = **157,078.41**.

    `HAVING` filters **groups**, after they exist. `WHERE` filters **rows**, before grouping. Customers with at least 20 completed orders:
    """)
    return


@app.cell
def _(engine, mo):
    l3_having = mo.sql(
        f"""
        SELECT customerID, count(*) AS completed_orders
        FROM orders
        WHERE status = 'completed'
        GROUP BY customerID
        HAVING count(*) >= 20
        ORDER BY completed_orders DESC;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### ORDER BY and LIMIT

    - `LIMIT` without `ORDER BY` is **not** "the first five": without `ORDER BY`, the order of rows is not guaranteed.
    - **Ties** need a tie-breaker (`ORDER BY total DESC, customerID`), or the database decides which tied row comes first.
    - `ORDER BY` can use an alias, because it runs after `SELECT`.

    ### The drill: four ways a query lies without an error

    Lecture 3 ended with four queries that run, return a believable number, and are wrong. The same four, on today's tables.

    **1. Status: "total revenue".**
    """)
    return


@app.cell
def _(engine, mo):
    l3_drill_status_wrong = mo.sql(
        f"""
        SELECT sum(orderTotal) AS revenue FROM orders;
        """,
        engine=engine,
    )
    return


@app.cell
def _(engine, mo):
    l3_drill_status_fix = mo.sql(
        f"""
        SELECT sum(orderTotal) AS revenue FROM orders WHERE status = 'completed';
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    177,770.91 includes returned and cancelled orders. Revenue is **157,078.41**, overstated by 20,692.50 without the filter.

    **2. Grain: "how much has the average customer spent?"** Averaging `moneySpent` over *orders* counts each customer once per order:
    """)
    return


@app.cell
def _(engine, mo):
    l3_drill_grain_wrong = mo.sql(
        f"""
        SELECT round(avg(c.moneySpent), 2) AS avg_customer_spend
        FROM orders o JOIN customers c ON c.customerID = o.customerID;
        """,
        engine=engine,
    )
    return


@app.cell
def _(engine, mo):
    l3_drill_grain_fix = mo.sql(
        f"""
        SELECT round(avg(moneySpent), 2) AS avg_customer_spend FROM customers WHERE moneySpent > 0;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    7,311.54 is an average of orders, weighted toward the customers who order most. The average customer who bought spent **5,609.94**. Before you `avg()` anything, ask: one row per *what*?

    **3. Identity: "how many different customers bought in December?"**
    """)
    return


@app.cell
def _(engine, mo):
    l3_drill_identity = mo.sql(
        f"""
        SELECT count(DISTINCT c.lastName)   AS by_surname,
               count(DISTINCT c.firstName || ' ' || c.lastName) AS by_full_name,
               count(DISTINCT c.customerID) AS by_id
        FROM orders o JOIN customers c ON c.customerID = o.customerID
        WHERE o.orderDate BETWEEN '2024-12-01' AND '2024-12-31';
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    24, 25 or **26**. A surname isn't a person, and neither is a full name (two Annas). `count(DISTINCT x)` counts distinct *x*, so make *x* the key.

    **4. Integer division: "what share of our orders are online?"**
    """)
    return


@app.cell
def _(engine, mo):
    l3_drill_intdiv_wrong = mo.sql(
        f"""
        SELECT sum(CASE WHEN channel = 'online' THEN 1 ELSE 0 END) / count(*) AS online_share
        FROM orders;
        """,
        engine=engine,
    )
    return


@app.cell
def _(engine, mo):
    l3_drill_intdiv_fix = mo.sql(
        f"""
        SELECT round(100.0 * sum(CASE WHEN channel = 'online' THEN 1 ELSE 0 END) / count(*), 1) AS online_pct
        FROM orders;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Whole number ÷ whole number drops the remainder: 181 / 600 = **0**. One decimal (`100.0`) fixes it: **30.2%**.

    *Source: Lecture 3 notes, Parts 1–6 (`lecture_3/lecture-03-notes.md`). Lecture 3 ran these on its flat `sales` table, with one product per order; the numbers here come from today's tables.*
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Lecture 4 — Data models and joins

    ### Three levels of a data model

    1. **Conceptual**: entities and relationships, no tables (the ER diagram).
    2. **Logical**: tables, columns, keys, constraints, but no specific DBMS.
    3. **Physical**: how one engine stores it: exact types, constraints, defaults (`\d orders` in psql).

    Mistakes are cheap at the conceptual level and expensive at the physical level.

    ### Dimensional modeling: facts, dimensions, grain

    - A **fact table** records events, with numbers: `fact_sales`, `quantity`, `revenue`, `cost`.
    - **Dimension tables** give the context: who, what, where, when (`dim_customer`, `dim_product`, `dim_employee`, `dim_date`).
    - The **grain** is the one sentence that says what one fact row *is*: here, **one order line**. Decide it first.
    - **Star schema**: dimensions attached directly to the fact table. **Snowflake**: dimensions split further into sub-tables. The default is star (Kimball): fewer joins, simpler for analysts.
    - The **unknown member** trick: online orders get employee key 0, `'(online)'`, instead of NULL, so every join to `dim_employee` is a plain inner join.

    ### A join pairs rows, then keeps the pairs you want

    **A join pairs every row of A with every row of B, then keeps the pairs you want.** With nothing filtered out, that's `CROSS JOIN`:
    """)
    return


@app.cell
def _(engine, mo):
    l4_cross = mo.sql(
        f"""
        SELECT count(*) AS pairs FROM orders CROSS JOIN customers;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    600 × 30 = **18,000** pairs. Every other join keeps some of them.

    ### INNER JOIN quietly drops what doesn't match
    """)
    return


@app.cell
def _(engine, mo):
    l4_inner_rows = mo.sql(
        f"""
        SELECT count(*) AS rows
        FROM orders o
        JOIN employees e ON e.employeeID = o.employeeID;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **419, not 600.** The 181 online orders have `employeeID` NULL, which matches no employee. That matters as soon as you sum: "completed revenue, with the salesperson's name":
    """)
    return


@app.cell
def _(engine, mo):
    l4_inner_revenue = mo.sql(
        f"""
        SELECT sum(o.orderTotal) AS revenue
        FROM orders o
        JOIN employees e ON e.employeeID = o.employeeID
        WHERE o.status = 'completed';
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **WRONG: 100,222.48** instead of 157,078.41. It's a correct sum over an incomplete set of rows.

    > An inner join doesn't complain when rows don't match — it just quietly leaves them out.

    ### LEFT JOIN keeps them

    `LEFT JOIN` keeps every row of the left table and fills the right side with NULLs where nothing matches (`RIGHT JOIN` is the mirror image, `FULL JOIN` keeps both sides). Give the NULLs a label with `coalesce`:
    """)
    return


@app.cell
def _(engine, mo):
    l4_left_branch = mo.sql(
        f"""
        SELECT coalesce(e.branch, 'Online') AS branch, sum(o.orderTotal) AS revenue
        FROM orders o
        LEFT JOIN employees e ON e.employeeID = o.employeeID
        WHERE o.status = 'completed'
        GROUP BY coalesce(e.branch, 'Online')
        ORDER BY revenue DESC;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Four rows adding up to 157,078.41. Online sold the most, and the inner join had hidden all of it.

    **The anti-join**, "which X have no Y": `LEFT JOIN`, then keep the rows where the right side is NULL.
    """)
    return


@app.cell
def _(engine, mo):
    l4_antijoin = mo.sql(
        f"""
        SELECT c.customerID, c.firstName, c.lastName
        FROM customers c
        LEFT JOIN orders o ON o.customerID = c.customerID
        WHERE o.orderID IS NULL;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Levon and Astghik, as expected. **Sanity check after every outer join:** `count(*)` vs `count(right_table.key)`. They differ by exactly the unmatched rows.
    """)
    return


@app.cell
def _(engine, mo):
    l4_count_check = mo.sql(
        f"""
        SELECT count(*) AS rows, count(o.orderID) AS rows_with_an_order
        FROM customers c
        LEFT JOIN orders o ON o.customerID = c.customerID;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    602 rows: 600 orders + 2 customers with none.

    ### The WHERE-vs-ON trap

    "Revenue per category, completed orders only, **including categories that sold nothing**." The obvious version puts the status test in `WHERE`:
    """)
    return


@app.cell
def _(engine, mo):
    l4_where_on_wrong = mo.sql(
        f"""
        SELECT p.category, count(i.orderID) AS lines, sum(i.lineTotal) AS revenue
        FROM products p
        LEFT JOIN order_items i ON i.productID = p.productID
        LEFT JOIN orders      o ON o.orderID   = i.orderID
        WHERE o.status = 'completed'
        GROUP BY p.category
        ORDER BY revenue DESC NULLS LAST;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **WRONG: 12 rows. Chairs has vanished.** The LEFT JOINs kept the unsold chair with `o.status` NULL, then `WHERE` threw it out, because `NULL = 'completed'` isn't true. A `WHERE` on the right-hand table turns a LEFT JOIN back into an INNER JOIN.

    **FIX:** decide what counts as a match *before* the LEFT JOIN, in `ON`:
    """)
    return


@app.cell
def _(engine, mo):
    l4_where_on_fix = mo.sql(
        f"""
        SELECT p.category, count(i.orderID) AS lines, coalesce(sum(i.lineTotal), 0) AS revenue
        FROM products p
        LEFT JOIN (order_items i
                   JOIN orders o ON o.orderID = i.orderID
                                AND o.status  = 'completed')
               ON i.productID = p.productID
        GROUP BY p.category
        ORDER BY revenue DESC;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    13 rows, Chairs at 0, and the same revenue for the other 12. Think of it this way: **ON decides who is invited; WHERE decides who may stay**, and it can throw out the guests the LEFT JOIN invited for free.

    ### Self-join: one table, two roles
    """)
    return


@app.cell
def _(engine, mo):
    l4_self_join = mo.sql(
        f"""
        SELECT e.firstName AS employee, e.position, m.firstName AS manager
        FROM employees e
        LEFT JOIN employees m ON m.employeeID = e.managerID
        ORDER BY e.employeeID;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    `e` is the employee, `m` the manager. Aliases are required. `LEFT JOIN` keeps Vahe, who has no manager.

    **Join on keys, not names.** Joining on names produced extra matches in Lecture 4 (a customer and an employee who share a name). Only a key is guaranteed unique.

    ### The fan-out trap

    `customers.moneySpent` is one number per customer. Join to `orders` "to count only real buyers":
    """)
    return


@app.cell
def _(engine, mo):
    l4_fanout_wrong = mo.sql(
        f"""
        SELECT sum(c.moneySpent) AS total_customer_spend
        FROM customers c
        JOIN orders o ON o.customerID = c.customerID;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **WRONG: 4,386,925.27.** The join copies each customer's `moneySpent` onto every one of their orders. The check that exposes it:
    """)
    return


@app.cell
def _(engine, mo):
    l4_fanout_check = mo.sql(
        f"""
        SELECT count(*) AS rows_after_join, count(DISTINCT c.customerID) AS customers
        FROM customers c
        JOIN orders o ON o.customerID = c.customerID;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    600 rows for 28 customers. **FIX:** don't join through a finer grain. Sum at the customer's own grain:
    """)
    return


@app.cell
def _(engine, mo):
    l4_fanout_fix = mo.sql(
        f"""
        SELECT sum(moneySpent) AS total_customer_spend FROM customers;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **157,078.41.** Ask this every time you aggregate after a join: *is the thing I'm summing at the same grain as the rows I'm joining through?*

    ### The star schema at work

    Completed revenue by branch, from the star. Thanks to the unknown member, online orders sit under branch `'Online'`, and a plain inner join keeps them:
    """)
    return


@app.cell
def _(engine, mo):
    l4_star = mo.sql(
        f"""
        SELECT e.branch, count(DISTINCT f.orderID) AS orders, sum(f.revenue) AS revenue
        FROM fact_sales f
        JOIN dim_employee e ON e.employeeKey = f.employeeKey
        WHERE f.status = 'completed'
        GROUP BY e.branch
        ORDER BY revenue DESC;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The same four numbers as the LEFT JOIN above, adding up to 157,078.41. `count(DISTINCT f.orderID)` because the fact table's grain is the *line*: 529 orders over more lines.

    *Source: Lecture 4 notes, Parts 1–5 (`lecture_4/lecture-04-notes.md`), and `lecture-04-demo.sql`.*
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Lecture 5 — Subqueries, CTEs, set operations

    ### Subqueries: a query inside a query

    | Shape | Returns | Used |
    |---|---|---|
    | **Scalar** | one value | anywhere a value fits: `WHERE price > (SELECT avg(price) …)` |
    | **Column** | one column, many rows | `IN`, `ANY`, `ALL` |
    | **Table** (derived table) | a whole table | in `FROM`, with an alias |

    A scalar subquery: products priced above the average product:
    """)
    return


@app.cell
def _(engine, mo):
    l5_scalar = mo.sql(
        f"""
        SELECT productName, category, price
        FROM products
        WHERE price > (SELECT avg(price) FROM products)
        ORDER BY price DESC;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    A table subquery in `FROM`: aggregate first, then aggregate the result. The average completed spend per customer who bought:
    """)
    return


@app.cell
def _(engine, mo):
    l5_derived = mo.sql(
        f"""
        SELECT round(avg(customer_total), 2) AS avg_per_buyer, count(*) AS buyers
        FROM (SELECT customerID, sum(orderTotal) AS customer_total
              FROM orders
              WHERE status = 'completed'
              GROUP BY customerID) AS t;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    5,609.94 over 28 buyers, the same as Lecture 3's drill fix, reached a second way.

    **Non-correlated** subqueries run once, on their own. **Correlated** ones mention the outer row (`WHERE o.customerID = c.customerID`) and give a different answer for each row.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### IN, NOT IN, EXISTS, NOT EXISTS, side by side

    #### Step 1. Four ways to ask "is there a match?"

    One question pair, on data you know. "Which salespeople have had at least one order CANCELLED?" and the opposite, "which have had NONE?".

    | Operator | What it asks | Result is |
    |---|---|---|
    | `x IN (subquery)` | is x equal to at least one value in the list? | true, false or NULL |
    | `x NOT IN (subquery)` | is x different from every value in the list? | true, false or NULL |
    | `EXISTS (subquery)` | does the subquery return at least one row? | only true or false |
    | `NOT EXISTS (subquery)` | does the subquery return no rows at all? | only true or false |

    `WHERE` keeps a row only when its condition is **true**. NULL ("unknown") is thrown away, just like false. That one rule explains everything below.

    #### Step 2. First, look at the list

    The subquery behind IN and NOT IN is "the employeeID of every cancelled order". Look at what it contains before using it.
    """)
    return


@app.cell
def _(engine, mo):
    l5_inex_01 = mo.sql(
        f"""
        SELECT employeeID, count(*) AS cancelled_orders
        FROM orders
        WHERE status = 'cancelled'
        GROUP BY employeeID
        ORDER BY employeeID NULLS FIRST
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **27** cancelled orders. Seven employees appear in the list. Hayk (employee 5) does not — he never had an order cancelled. And **5** of the cancelled orders were placed online, so their employeeID is **NULL**. The list contains a NULL. Keep that in mind.

    #### Step 3. IN and NOT IN in miniature

    The same two tests on a hand-written list, with and without a NULL in it. x = 1 is in the list; x = 5 is not.
    """)
    return


@app.cell
def _(engine, mo):
    l5_inex_02 = mo.sql(
        f"""
        SELECT x,
               x IN (1, 2)           AS in_list,
               x NOT IN (1, 2)       AS not_in_list,
               x IN (1, 2, NULL)     AS in_list_with_null,
               x NOT IN (1, 2, NULL) AS not_in_list_with_null
        FROM (VALUES (1), (5)) AS t(x)
        ORDER BY x
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    #### Three rules first

    | Expression | Result | Why |
    |---|---|---|
    | `5 = NULL`, `5 <> NULL` | NULL | NULL means "unknown value". It might be 5, it might not, so the comparison is unknown too. |
    | `true OR NULL` | **true** | OR needs just one true, and it already has one. |
    | `false OR NULL` | NULL | Everything known is false; the answer depends on the unknown part. |
    | `false AND NULL` | **false** | AND fails as soon as one part is false. |
    | `true AND NULL` | NULL | Everything known is true; the answer depends on the unknown part. |

    `x IN (a, b, c)` is shorthand for `x = a OR x = b OR x = c`. `x NOT IN (a, b, c)` is shorthand for `x <> a AND x <> b AND x <> c`.

    #### Row x = 1 (1 IS in the list)

    | Column | Expands to | Step by step | Result |
    |---|---|---|---|
    | `in_list` | `1 = 1 OR 1 = 2` | true OR false | **true** |
    | `not_in_list` | `1 <> 1 AND 1 <> 2` | false AND true | **false** |
    | `in_list_with_null` | `1 = 1 OR 1 = 2 OR 1 = NULL` | true OR false OR NULL | **true**: one true is enough for OR |
    | `not_in_list_with_null` | `1 <> 1 AND 1 <> 2 AND 1 <> NULL` | false AND true AND NULL | **false**: one false is enough for AND |

    For a value that IS in the list, the NULL changes nothing: the match (`1 = 1`) decides both answers before the NULL is even needed.

    #### Row x = 5 (5 is NOT in the list)

    | Column | Expands to | Step by step | Result |
    |---|---|---|---|
    | `in_list` | `5 = 1 OR 5 = 2` | false OR false | **false** |
    | `not_in_list` | `5 <> 1 AND 5 <> 2` | true AND true | **true** |
    | `in_list_with_null` | `5 = 1 OR 5 = 2 OR 5 = NULL` | false OR false OR NULL | **NULL**: no true found, and the unknown value might be 5 |
    | `not_in_list_with_null` | `5 <> 1 AND 5 <> 2 AND 5 <> NULL` | true AND true AND NULL | **NULL**: no false found, and the unknown value might be 5 |

    For a value that is NOT in the list, the NULL turns both answers into "unknown". That is the two NULL cells in the result above.

    #### What WHERE does with these answers

    WHERE keeps a row only when the condition is **true**. False and NULL are both thrown away.

    | Filter | x = 1 | x = 5 |
    |---|---|---|
    | `WHERE x IN (1, 2)` | kept | dropped |
    | `WHERE x IN (1, 2, NULL)` | kept | dropped (NULL) |
    | `WHERE x NOT IN (1, 2)` | dropped | **kept** |
    | `WHERE x NOT IN (1, 2, NULL)` | dropped | **dropped (NULL)** |

    - **IN is safe:** with or without the NULL, it keeps exactly the same rows. A row dropped as NULL would have been dropped as false anyway.

    - **NOT IN breaks:** without the NULL it keeps 5; with the NULL it keeps nothing at all. A value in the list gives false, a value not in the list gives NULL, so no row can ever be kept. step 7 shows the same thing on real data.

    #### Step 4. EXISTS and NOT EXISTS in miniature

    The same x = 1 and x = 5, the same list (1, 2, NULL) — now as a tiny table `l` with one column `v`.

    **An everyday picture first.** The cancelled orders are a pile of paper slips, each with the salesperson's name on it. The 5 online orders are slips with **no name** (NULL).

    - NOT IN asks: "Is my name **different from every name** on the slips?" For a blank slip you can't say — the name might be yours. So the answer is "unknown", and WHERE drops you.

    - NOT EXISTS asks: "Is there **at least one slip with my name** on it?" You go through the pile; a blank slip is simply not yours, so you skip it. At the end you either found one or you didn't -- there is no "maybe".

    EXISTS is a question about **rows**, not about values: "if I run this subquery for this x, does anything come back?"

    **Step 1: what the subquery sees.** For each x, the subquery `SELECT 1 FROM l WHERE l.v = x` compares x with every row of `l`, and its own WHERE keeps only the rows where the comparison is true.
    """)
    return


@app.cell
def _(engine, mo):
    l5_inex_03 = mo.sql(
        f"""
        SELECT p.x, l.v,
               l.v = p.x           AS v_equals_x,
               (l.v = p.x) IS TRUE AS subquery_keeps_row
        FROM (VALUES (1), (5)) AS p(x)
        CROSS JOIN (VALUES (1), (2), (NULL::int)) AS l(v)
        ORDER BY p.x, l.v NULLS LAST
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Read it as the subquery's work, one row of `l` at a time:

    | x | Row v = 1 | Row v = 2 | Row v = NULL | Rows that come back |
    |---|---|---|---|---|
    | 1 | `1 = 1` true: **kept** | `2 = 1` false: dropped | `NULL = 1` NULL: dropped | **1 row** |
    | 5 | `1 = 5` false: dropped | `2 = 5` false: dropped | `NULL = 5` NULL: dropped | **0 rows** |

    The NULL row is dropped by the same rule as always: WHERE keeps only true. Here that rule works **for** us — the blank slip is skipped.

    **Step 2: EXISTS only counts what came back.**
    """)
    return


@app.cell
def _(engine, mo):
    l5_inex_04 = mo.sql(
        f"""
        SELECT p.x,
               (SELECT count(*) FROM (VALUES (1), (2), (NULL::int)) AS l(v)
                WHERE l.v = p.x)                                         AS rows_found,
               EXISTS     (SELECT 1 FROM (VALUES (1), (2), (NULL::int)) AS l(v)
                           WHERE l.v = p.x)                              AS exists_match,
               NOT EXISTS (SELECT 1 FROM (VALUES (1), (2), (NULL::int)) AS l(v)
                           WHERE l.v = p.x)                              AS not_exists_match
        FROM (VALUES (1), (5)) AS p(x)
        ORDER BY p.x
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    | x | Rows found | EXISTS | NOT EXISTS |
    |---|---|---|---|
    | 1 | 1 | **true**: at least one row came back | **false** |
    | 5 | 0 | **false**: nothing came back | **true** |

    "Some rows" or "no rows" — nothing in between. That is why EXISTS and NOT EXISTS can only be true or false, never NULL.

    **Side by side with step 3, for x = 5 (not in the list):**

    | Test | Result | WHERE keeps x = 5? |
    |---|---|---|
    | `5 NOT IN (1, 2, NULL)` | NULL | no — the trap |
    | `NOT EXISTS (... WHERE l.v = 5)` | **true** | **yes** — the right answer |

    Same list, same NULL. NOT IN has to compare x with the NULL and gets "unknown"; NOT EXISTS lets the subquery's WHERE throw the NULL row away and just counts what's left. step 7 and step 8 show the same two behaviours on the real data.

    #### Step 5. IN: salespeople with at least one cancelled order
    """)
    return


@app.cell
def _(engine, mo):
    l5_inex_05 = mo.sql(
        f"""
        SELECT e.employeeID, e.firstName, e.lastName
        FROM employees e
        WHERE e.employeeID IN (SELECT o.employeeID
                               FROM orders o
                               WHERE o.status = 'cancelled')
        ORDER BY e.employeeID
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **How it works:** the subquery runs once and produces the list from step 2. Each employee is kept if their ID equals at least one value on it. **Why it's right:** 7 employees, everyone except Hayk. The NULL in the list doesn't matter, as in step 3: a match is a match. Each employee appears once, however many cancelled orders they had — IN asks "is it on the list?", it doesn't pair rows the way a JOIN does.

    #### Step 6. EXISTS: the same question, asked per row
    """)
    return


@app.cell
def _(engine, mo):
    l5_inex_06 = mo.sql(
        f"""
        SELECT e.employeeID, e.firstName, e.lastName
        FROM employees e
        WHERE EXISTS (SELECT 1
                      FROM orders o
                      WHERE o.employeeID = e.employeeID
                        AND o.status = 'cancelled')
        ORDER BY e.employeeID
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **How it works:** for each employee `e`, the subquery looks for a cancelled order with `o.employeeID = e.employeeID` — it mentions the outer row, so it is *correlated*. EXISTS is true as soon as one row comes back, and it never looks at what the row contains (`SELECT 1` is just a convention). **Why it's right:** the same 7 employees. The online orders have `employeeID` NULL, so `NULL = e.employeeID` is never true — they simply never match anyone.

    #### Step 7. NOT IN: salespeople with NO cancelled order
    """)
    return


@app.cell(hide_code=True)
def _(engine, mo):
    _df = mo.sql(
        f"""
        select distinct status from orders
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(engine, mo):
    _df = mo.sql(
        f"""
        SELECT o.employeeID
                                   FROM orders o
                                   WHERE o.status = 'cancelled'
        """,
        engine=engine,
    )
    return


@app.cell
def _(engine, mo):
    l5_inex_07 = mo.sql(
        f"""
        SELECT e.employeeID, e.firstName, e.lastName
        FROM employees e
        WHERE e.employeeID NOT IN (SELECT o.employeeID
                                   FROM orders o
                                   WHERE o.status = 'cancelled')
        ORDER BY e.employeeID
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **WRONG: 0 rows**, no error. "Nobody has a clean record." **Why:** for Hayk, `5 NOT IN (list)` is `5 <> 1 AND 5 <> 2 ... AND 5 <> NULL`. All the real IDs differ from 5, but `5 <> NULL` is unknown, so the whole test is unknown, and WHERE drops him. For everyone else the test is false anyway. One NULL in the list (here: five) empties the result.

    #### Step 8. NOT EXISTS: the same question, done right
    """)
    return


@app.cell(hide_code=True)
def _(engine, mo):
    _df = mo.sql(
        f"""
        with emp as (
            select employeeid, firstname, lastname
            from employees
        ),
            ords_canc as (

            select distinct employeeid, status as canc_status
        	from orders where status='cancelled'
            ),
            ords_no_canc as (

            select distinct employeeid, status  as no_cance_status
        	from orders where status!='cancelled'
            )

        select emp.*, oc.canc_status, no_oc.no_cance_status

            from emp full join ords_canc oc using(employeeid) 
        			full join ords_no_canc no_oc using(employeeid)
        """,
        engine=engine,
    )
    return


@app.cell
def _():
    return


@app.cell
def _(engine, mo):
    l5_inex_08 = mo.sql(
        f"""
        SELECT e.employeeID, e.firstName, e.lastName
        FROM employees e
        WHERE NOT EXISTS (SELECT 1
                          FROM orders o
                          WHERE o.employeeID = e.employeeID
                            AND o.status = 'cancelled')
        ORDER BY e.employeeID
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **How it works:** for each employee, look for a cancelled order of theirs; keep the employee if there is **none**. **Why it's right:** Hayk Melikyan. EXISTS can only be true or false, never unknown — the NULL rows just fail to match — so NOT EXISTS is only true or false too. Same data, same NULLs: NOT IN gave nothing, NOT EXISTS gives the right answer.

    #### Step 9. How to see it coming, and how to fix NOT IN

    The check: count(*) against count(column) on the subquery's rows. If they differ, the list has NULLs, and NOT IN will fail.
    """)
    return


@app.cell
def _(engine, mo):
    l5_inex_09 = mo.sql(
        f"""
        SELECT count(*)          AS cancelled_orders,
               count(employeeID) AS with_an_employee
        FROM orders
        WHERE status = 'cancelled'
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    27 rows, 22 with an employee: 5 NULLs.

    If you keep NOT IN, take the NULLs out of the list yourself:
    """)
    return


@app.cell
def _(engine, mo):
    l5_inex_10 = mo.sql(
        f"""
        SELECT e.employeeID, e.firstName, e.lastName
        FROM employees e
        WHERE e.employeeID NOT IN (SELECT o.employeeID
                                   FROM orders o
                                   WHERE o.status = 'cancelled'
                                     AND o.employeeID IS NOT NULL)
        ORDER BY e.employeeID
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Hayk again.

    | | NULL in the subquery's column | Use it? |
    |---|---|---|
    | `IN` | harmless | yes |
    | `EXISTS` | harmless | yes |
    | `NOT IN` | the result is empty, silently | only if the column is `NOT NULL` |
    | `NOT EXISTS` | harmless | yes — the default for "which X have no Y" |

    The rule from Lecture 5: never write `NOT IN (subquery)` unless the column is declared NOT NULL. Write NOT EXISTS instead. (A third correct version is Lecture 4's anti-join: `LEFT JOIN orders o ON o.employeeID = e.employeeID AND o.status = 'cancelled' WHERE o.orderID IS NULL`, with the status test in `ON`.)
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### EXISTS without the correlation

    "Which customers gave us a 1-star rating?"
    """)
    return


@app.cell
def _(engine, mo):
    l5_exists_wrong = mo.sql(
        f"""
        SELECT count(*) AS customers
        FROM customers c
        WHERE EXISTS (SELECT 1 FROM orders o
                      WHERE o.rating = 1);
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **WRONG: 30**, everyone, including Levon and Astghik, who never ordered. The subquery doesn't mention `c`, so it asks "does *any* 1-star order exist?" for every customer. **FIX:** tie it to the outer row:
    """)
    return


@app.cell
def _(engine, mo):
    l5_exists_fix = mo.sql(
        f"""
        SELECT c.customerID, c.firstName, c.lastName
        FROM customers c
        WHERE EXISTS (SELECT 1 FROM orders o
                      WHERE o.customerID = c.customerID
                        AND o.rating = 1)
        ORDER BY c.customerID;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    4 customers. **All or nothing is suspicious:** a filter that keeps every row, or none, usually isn't filtering what you think.

    ### The cart fan-out: header joined to lines

    "Completed revenue, and units sold." Units live on the lines, so join them:
    """)
    return


@app.cell
def _(engine, mo):
    l5_cart_wrong = mo.sql(
        f"""
        SELECT sum(o.orderTotal) AS revenue,
               sum(i.quantity)   AS units
        FROM orders o
        JOIN order_items i ON i.orderID = o.orderID
        WHERE o.status = 'completed';
        """,
        engine=engine,
    )
    return


@app.cell
def _(engine, mo):
    l5_cart_check = mo.sql(
        f"""
        SELECT count(*) AS rows_after_join, count(DISTINCT o.orderID) AS orders
        FROM orders o
        JOIN order_items i ON i.orderID = o.orderID
        WHERE o.status = 'completed';
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **WRONG revenue: 247,923.72.** 844 lines for 529 orders: an order with three lines has its `orderTotal` counted three times. The units are right, because they *are* at line grain. **FIX:** sum the amount at line grain too:
    """)
    return


@app.cell
def _(engine, mo):
    l5_cart_fix = mo.sql(
        f"""
        SELECT sum(i.lineTotal) AS revenue,
               sum(i.quantity)  AS units
        FROM orders o
        JOIN order_items i ON i.orderID = o.orderID
        WHERE o.status = 'completed';
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### CTEs: a subquery with a name

    `WITH name AS (…)` names a step; later steps, and the final query, read it like a table. Same power as a table subquery, easier to read. **Easier to read also means easier to trust without checking**, and a CTE can fan out like any join.

    "Average spend per customer, by city": the wrong version joins the per-customer CTE back to `orders`:
    """)
    return


@app.cell
def _(engine, mo):
    l5_cte_wrong = mo.sql(
        f"""
        WITH customer_spend AS (
            SELECT customerID, sum(orderTotal) AS spent
            FROM orders
            WHERE status = 'completed'
            GROUP BY customerID
        )
        SELECT c.city,
               count(o.orderID)        AS orders,
               round(avg(cs.spent), 2) AS avg_customer_spend
        FROM customers c
        JOIN customer_spend cs ON cs.customerID = c.customerID
        JOIN orders o          ON o.customerID  = c.customerID
                              AND o.status = 'completed'
        GROUP BY c.city
        ORDER BY avg_customer_spend DESC;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **WRONG:** each customer's total is averaged once per order. **FIX:** keep everything at customer grain inside the CTE, and never join back:
    """)
    return


@app.cell
def _(engine, mo):
    l5_cte_fix = mo.sql(
        f"""
        WITH customer_spend AS (
            SELECT customerID,
                   count(*)        AS orders,
                   sum(orderTotal) AS spent
            FROM orders
            WHERE status = 'completed'
            GROUP BY customerID
        )
        SELECT c.city,
               sum(cs.orders)          AS orders,
               round(avg(cs.spent), 2) AS avg_customer_spend
        FROM customers c
        JOIN customer_spend cs ON cs.customerID = c.customerID
        GROUP BY c.city
        ORDER BY avg_customer_spend DESC;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    A different winner: Gyumri (6,714.16), not Abovyan.

    **ORDER BY inside a CTE doesn't order the result.** "Top 5 customers", sorted inside the CTE:
    """)
    return


@app.cell
def _(engine, mo):
    l5_cte_order_wrong = mo.sql(
        f"""
        WITH top_spenders AS (
            SELECT customerID, sum(orderTotal) AS spent
            FROM orders
            WHERE status = 'completed'
            GROUP BY customerID
            ORDER BY spent DESC
        )
        SELECT c.firstName, c.lastName, t.spent
        FROM top_spenders t
        JOIN customers c ON c.customerID = t.customerID
        LIMIT 5;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **WRONG:** look at the `spent` column. The join read the rows in its own order, and `LIMIT` took the first five of *that*. (Which five you get depends on the query plan; the point is that nothing guarantees the top five.) **FIX:** `ORDER BY` belongs to the query whose output you read:
    """)
    return


@app.cell
def _(engine, mo):
    l5_cte_order_fix = mo.sql(
        f"""
        WITH top_spenders AS (
            SELECT customerID, sum(orderTotal) AS spent
            FROM orders
            WHERE status = 'completed'
            GROUP BY customerID
        )
        SELECT c.firstName, c.lastName, t.spent
        FROM top_spenders t
        JOIN customers c ON c.customerID = t.customerID
        ORDER BY t.spent DESC
        LIMIT 5;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### LATERAL: a correlated subquery in FROM

    For each customer, run a small query that can see that customer's row. Here: each customer's latest order. `LEFT JOIN LATERAL … ON true` keeps customers for whom it finds nothing:
    """)
    return


@app.cell
def _(engine, mo):
    l5_lateral = mo.sql(
        f"""
        SELECT c.customerID, c.firstName, last_order.orderID, last_order.orderDate
        FROM customers c
        LEFT JOIN LATERAL (SELECT o.orderID, o.orderDate
                           FROM orders o
                           WHERE o.customerID = c.customerID
                           ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
                           LIMIT 1) AS last_order ON true
        ORDER BY c.customerID;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    30 rows. Levon (24) and Astghik (29) are there with NULLs. A plain `JOIN LATERAL` would have dropped them.

    ### Set operations: stacking results

    A join puts tables **side by side** (more columns). A set operation **stacks** two results (more rows, same columns).

    | Operator | Keeps |
    |---|---|
    | `UNION ALL` | every row of both |
    | `UNION` | every row of both, **duplicates removed** |
    | `INTERSECT` | rows in both |
    | `EXCEPT` | rows in the first, not in the second |

    Columns are paired **by position, not by name**, and both sides need the same number of columns. The trap: `UNION` in a total.
    """)
    return


@app.cell
def _(engine, mo):
    l5_union_wrong = mo.sql(
        f"""
        SELECT sum(orderTotal) AS revenue, count(*) AS order_totals
        FROM (SELECT orderTotal FROM orders WHERE status = 'completed' AND channel = 'in_store'
              UNION
              SELECT orderTotal FROM orders WHERE status = 'completed' AND channel = 'online') AS t;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **WRONG: 106,263.47 over 324 rows.** `UNION` removed every repeated *value*: seven completed orders of exactly 249.00 became one row. **FIX:** `UNION ALL`:
    """)
    return


@app.cell
def _(engine, mo):
    l5_union_fix = mo.sql(
        f"""
        SELECT sum(orderTotal) AS revenue, count(*) AS order_totals
        FROM (SELECT orderTotal FROM orders WHERE status = 'completed' AND channel = 'in_store'
              UNION ALL
              SELECT orderTotal FROM orders WHERE status = 'completed' AND channel = 'online') AS t;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    `EXCEPT` answers "which X have no Y" a fourth way (after the anti-join, `NOT IN` and `NOT EXISTS`). All four should agree:
    """)
    return


@app.cell
def _(engine, mo):
    l5_except = mo.sql(
        f"""
        SELECT customerID FROM customers
        EXCEPT
        SELECT customerID FROM orders
        ORDER BY customerID;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### Recursive CTEs

    `WITH RECURSIVE`: a starting query, `UNION ALL`, and a step that reads the previous step's rows. It repeats until the step finds nothing. Here it walks the org chart top-down, at any depth:
    """)
    return


@app.cell
def _(engine, mo):
    l5_recursive = mo.sql(
        f"""
        WITH RECURSIVE org AS (
            SELECT employeeID, firstName, managerID, 1 AS level,
                   firstName::text AS path
            FROM employees
            WHERE managerID IS NULL
          UNION ALL
            SELECT e.employeeID, e.firstName, e.managerID, o.level + 1,
                   o.path || ' > ' || e.firstName
            FROM employees e
            JOIN org o ON e.managerID = o.employeeID
        )
        SELECT level, path
        FROM org
        ORDER BY path;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    *Source: Lecture 5 notes, Parts 1–8 (`lecture_5/lecture-05-notes.md`), and `lecture-05-demo.sql`.*
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Lecture 6 — Window functions

    > **A window function computes over a set of related rows, but does not collapse them: every input row survives.**

    ### GROUP BY collapses, a window doesn't

    "Each completed order, **next to** its customer's total." With `GROUP BY` the orders are gone. Error on purpose:
    """)
    return


@app.cell
def _(engine, mo, psycopg):
    # Error on purpose -- shows PostgreSQL's message instead of stopping the notebook.
    try:
        engine.execute("""
        SELECT orderID, customerID, orderTotal, sum(orderTotal) AS customer_total
        FROM orders
        WHERE status = 'completed'
        GROUP BY customerID
        """)
        _shown = mo.callout(
            mo.md("No error?! This statement was supposed to fail."), kind="warn"
        )
    except psycopg.Error as _e:
        _shown = mo.callout(
            mo.md(f"**ERROR:** `{_e.diag.message_primary}`"), kind="danger"
        )
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    With a window, every order stays, and the total sits next to it:
    """)
    return


@app.cell
def _(engine, mo):
    l6_window = mo.sql(
        f"""
        SELECT orderID, customerID, orderTotal,
               sum(orderTotal) OVER (PARTITION BY customerID) AS customer_total,
               round(100 * orderTotal / sum(orderTotal) OVER (PARTITION BY customerID), 1) AS pct_of_customer
        FROM orders
        WHERE status = 'completed'
        ORDER BY customerID, orderID
        LIMIT 5;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **The parts of `OVER (…)`:**

    | Part | Meaning |
    |---|---|
    | `OVER ()` | the whole result is one window |
    | `PARTITION BY x` | one window per value of x (like `GROUP BY`, without collapsing) |
    | `ORDER BY y` | an order *within* each window, for ranking, `lag`, running totals. **Not** the order of the output: that is still the query's own `ORDER BY` |
    | `ROWS / RANGE / GROUPS BETWEEN …` | the **frame**: which rows of the window the function sees |
    | `WINDOW w AS (…)` | name a window once, reuse it as `OVER w` |

    **Rows in = rows out.** A query whose only extra is window functions returns exactly as many rows as its input:
    """)
    return


@app.cell
def _(engine, mo):
    l6_rows_in_out = mo.sql(
        f"""
        SELECT count(*) AS rows_out
        FROM (SELECT orderID,
                     sum(orderTotal)   OVER ()                        AS all_orders,
                     count(*)          OVER (PARTITION BY customerID) AS customer_orders,
                     avg(orderTotal)   OVER (PARTITION BY status)     AS status_avg
              FROM orders) AS w;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### Ranking: row_number, rank, dense_rank

    Six made-up scores, with two pairs of ties (85, 85 and 70, 70):
    """)
    return


@app.cell
def _(engine, mo):
    l6_ranking = mo.sql(
        f"""
        SELECT id, score,
               row_number()  OVER (ORDER BY score DESC, id) AS row_number,
               rank()        OVER (ORDER BY score DESC)     AS rank,
               dense_rank()  OVER (ORDER BY score DESC)     AS dense_rank
        FROM (VALUES (1, 90), (2, 85), (3, 85), (4, 70), (5, 70), (6, 60)) AS t(id, score)
        ORDER BY score DESC, id;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    - `row_number()`: 1, 2, 3, … always different. On ties, **which** row gets the lower number is arbitrary unless you add a tie-breaker (here `id`).
    - `rank()`: ties share a rank, then a gap: 1, 2, 2, **4**.
    - `dense_rank()`: ties share a rank, no gap: 1, 2, 2, **3**.

    Use `rank` / `dense_rank` when ties should *stay* ties ("top 2 scores" with a tie returns 3 rows). Use `row_number` when you need exactly one row each, and then make the `ORDER BY` complete.

    ### Top-N per group

    "Each customer's latest order." A window function can't go in `WHERE`, which runs before windows exist. Error on purpose:
    """)
    return


@app.cell
def _(engine, mo, psycopg):
    # Error on purpose -- shows PostgreSQL's message instead of stopping the notebook.
    try:
        engine.execute("""
        SELECT customerID, orderID, orderDate,
               row_number() OVER (PARTITION BY customerID
                                  ORDER BY orderDate DESC, orderTime DESC, orderID DESC) AS rn
        FROM orders
        WHERE rn = 1
        """)
        _shown = mo.callout(
            mo.md("No error?! This statement was supposed to fail."), kind="warn"
        )
    except psycopg.Error as _e:
        _shown = mo.callout(
            mo.md(f"**ERROR:** `{_e.diag.message_primary}`"), kind="danger"
        )
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **FIX:** compute the window in a CTE, filter in the next step, where `rn` is an ordinary column:
    """)
    return


@app.cell
def _(engine, mo):
    l6_topn = mo.sql(
        f"""
        WITH ranked AS (
            SELECT customerID, orderID, orderDate, orderTime, orderTotal,
                   row_number() OVER (PARTITION BY customerID
                                      ORDER BY orderDate DESC, orderTime DESC, orderID DESC) AS rn
            FROM orders
        )
        SELECT customerID, orderID, orderDate, orderTime, orderTotal
        FROM ranked
        WHERE rn = 1
        ORDER BY customerID;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    28 rows: one per customer *with* orders. (Lecture 5's `LEFT JOIN LATERAL` gave 30 because it keeps Levon and Astghik; PostgreSQL's `DISTINCT ON` is a third way.) The `ORDER BY` inside `OVER` is complete: date, time, then `orderID`. Without the tie-breakers, two orders on the same last day would make "latest" arbitrary.

    The same pattern with `rank()`: the best-selling product (units, completed orders) in each category:
    """)
    return


@app.cell
def _(engine, mo):
    l6_top_product = mo.sql(
        f"""
        WITH product_units AS (
            SELECT p.category, p.productName, sum(i.quantity) AS units
            FROM order_items i
            JOIN orders   o ON o.orderID   = i.orderID
            JOIN products p ON p.productID = i.productID
            WHERE o.status = 'completed'
            GROUP BY p.category, p.productName
        ),
        ranked AS (
            SELECT category, productName, units,
                   rank() OVER (PARTITION BY category ORDER BY units DESC) AS rnk
            FROM product_units
        )
        SELECT category, productName, units, rnk
        FROM ranked
        WHERE rnk = 1
        ORDER BY category, productName;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### Looking sideways: lag and lead

    `lag(x)` is x from the **previous** row of the window, and `lead(x)` from the next row. Lusine's completed orders, each next to the one before:
    """)
    return


@app.cell
def _(engine, mo):
    l6_lag = mo.sql(
        f"""
        SELECT orderID, orderDate, orderTotal,
               lag(orderTotal) OVER w                AS previous_order,
               orderTotal - lag(orderTotal) OVER w   AS change
        FROM orders
        WHERE status = 'completed' AND customerID = 5
        WINDOW w AS (PARTITION BY customerID ORDER BY orderDate, orderTime, orderID)
        ORDER BY orderDate;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The first row has nothing before it, so it gets NULL, which is honest. The trap is "tidying" that NULL with a default, `lag(x, 1, 0)`:
    """)
    return


@app.cell
def _(engine, mo):
    l6_lag_default = mo.sql(
        f"""
        SELECT round(avg(change_null), 2)  AS avg_change_null,
               count(change_null)          AS changes_null,
               round(avg(change_zero), 2)  AS avg_change_zero,
               count(change_zero)          AS changes_zero
        FROM (SELECT orderTotal - lag(orderTotal)       OVER w AS change_null,
                     orderTotal - lag(orderTotal, 1, 0) OVER w AS change_zero
              FROM orders
              WHERE status = 'completed'
              WINDOW w AS (PARTITION BY customerID ORDER BY orderDate, orderTime, orderID)) AS x;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **WRONG with the 0 default: 17.23 instead of 1.42.** 28 fake changes, one per customer's first order, each counted as growth from a 0 order that never existed. A default is right only when it is *true*. Also: `lag` gives the previous **row**, not the previous month. If a month is missing, the row before it is two months back.

    ### Frames: running totals and last_value

    With `ORDER BY` inside `OVER`, the default frame is `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`. `RANGE` includes every **tied** row (same `orderDate`):
    """)
    return


@app.cell
def _(engine, mo):
    l6_running_wrong = mo.sql(
        f"""
        SELECT orderID, orderDate, orderTotal,
               sum(orderTotal) OVER (ORDER BY orderDate) AS running_total
        FROM orders
        WHERE status = 'completed'
        ORDER BY orderDate, orderID
        LIMIT 5;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **WRONG:** orders 1002 and 1003 show the same running total, 1,207.65. Order 1002's figure already includes 1003's 747.00. **FIX:** say `ROWS`, and make the order unique:
    """)
    return


@app.cell
def _(engine, mo):
    l6_running_fix = mo.sql(
        f"""
        SELECT orderID, orderDate, orderTotal,
               sum(orderTotal) OVER (ORDER BY orderDate, orderID
                                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total
        FROM orders
        WHERE status = 'completed'
        ORDER BY orderDate, orderID
        LIMIT 5;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Checks for a running total: it must **end at the plain total** (157,078.41), and it must **change on every row** when the amounts are positive.

    The same default frame breaks `last_value`: the frame ends at the current row, so the "last" value is the current row's own:
    """)
    return


@app.cell
def _(engine, mo):
    l6_last_value_wrong = mo.sql(
        f"""
        SELECT orderID, orderDate, orderTotal,
               first_value(orderTotal) OVER w AS first_order,
               last_value(orderTotal)  OVER w AS latest_order
        FROM orders
        WHERE status = 'completed' AND customerID = 5
        WINDOW w AS (PARTITION BY customerID ORDER BY orderDate, orderTime, orderID)
        ORDER BY orderDate;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **WRONG:** `latest_order` just repeats `orderTotal`. **FIX:** extend the frame to the end of the partition:
    """)
    return


@app.cell
def _(engine, mo):
    l6_last_value_fix = mo.sql(
        f"""
        SELECT orderID, orderDate, orderTotal,
               first_value(orderTotal) OVER w AS first_order,
               last_value(orderTotal)  OVER w AS latest_order
        FROM orders
        WHERE status = 'completed' AND customerID = 5
        WINDOW w AS (PARTITION BY customerID ORDER BY orderDate, orderTime, orderID
                     ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
        ORDER BY orderDate;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Moving averages use the same idea: `avg(x) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)`. In the first months there aren't 2 rows before, so the average covers fewer months.

    ### NULL is a partition too

    "Rank our salespeople by number of orders":
    """)
    return


@app.cell
def _(engine, mo):
    l6_null_partition_wrong = mo.sql(
        f"""
        SELECT o.employeeID, e.firstName,
               count(*)                              AS orders,
               rank() OVER (ORDER BY count(*) DESC)  AS sales_rank
        FROM orders o
        LEFT JOIN employees e ON e.employeeID = o.employeeID
        GROUP BY o.employeeID, e.firstName
        ORDER BY sales_rank
        LIMIT 4;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **WRONG:** the "top salesperson", with 181 orders, has no ID and no name: it's the online orders, grouped together as one NULL group. Every real salesperson drops a place. This one also shows the order of execution: `GROUP BY` first, then the window ranks the groups. **FIX:** decide what the question is about. To rank people, use an inner join (online excluded, on purpose). To rank channels of sale, give the NULL group a label:
    """)
    return


@app.cell
def _(engine, mo):
    l6_null_partition_fix = mo.sql(
        f"""
        SELECT coalesce(e.firstName, '(online)') AS sold_by,
               count(*)                              AS orders,
               rank() OVER (ORDER BY count(*) DESC)  AS sales_rank
        FROM orders o
        LEFT JOIN employees e ON e.employeeID = o.employeeID
        GROUP BY o.employeeID, e.firstName
        ORDER BY sales_rank
        LIMIT 4;
        """,
        engine=engine,
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    A window doesn't repair a fan-out either: `sum(...) OVER (...)` over a header-joined-to-lines result sums the copies, exactly as Lecture 5's cart fan-out did.

    *Source: Lecture 6 notes, Parts 1–8 (`lecture_6/lecture-06-notes.md`), and `lecture-06-demo.sql`.*
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## The one idea across all six lectures

    Lecture 2 showed the database saying **no**: constraints, loud errors. Every lecture since showed the other kind of wrong, where the database says **yes** to a wrong question:

    | Lecture | Trap | Looked like | Was |
    |---|---|---|---|
    | 3 | `AND` / `OR` without parentheses | 49 returned-or-cancelled online orders | 17 |
    | 3 | `= NULL` | 0 online orders | 181 |
    | 3 | no status filter | revenue 177,770.91 | 157,078.41 |
    | 3 | average at the wrong grain | average customer spent 7,311.54 | 5,609.94 |
    | 3 | counting surnames, not customers | 24 December customers | 26 |
    | 3 | integer division | 0% of orders online | 30.2% |
    | 4 | inner join drops NULL keys | completed revenue 100,222.48 | 157,078.41 |
    | 4 | `WHERE` on a LEFT JOIN's right table | 12 categories | 13, Chairs at 0 |
    | 4 | fan-out (`moneySpent` × orders) | 4,386,925.27 | 157,078.41 |
    | 5 | `NOT IN` with a NULL in the list | nobody has a clean record | Hayk |
    | 5 | `EXISTS` without the correlation | 30 customers gave 1 star | 4 |
    | 5 | cart fan-out (header × lines) | revenue 247,923.72 | 157,078.41 |
    | 5 | fan-out through a CTE | Abovyan has the highest average spend | Gyumri |
    | 5 | `ORDER BY` inside the CTE | "top 5" in arbitrary order | sort in the outer query |
    | 5 | `UNION` where `UNION ALL` was meant | revenue 106,263.47 | 157,078.41 |
    | 6 | `lag(x, 1, 0)` | average change 17.23 | 1.42 |
    | 6 | default `RANGE` frame | 1,207.65 on two orders in a row | 460.65, then 1,207.65 |
    | 6 | `last_value` with the default frame | latest order = this order | 177.00 for Lusine |
    | 6 | the NULL partition | top salesperson has no name | Ani, 91 |

    None of them threw an error. Every one returned a table that looked completely normal.

    **The checks that catch them**, the same ones every lecture used:

    - **Check against ground truth you already have**: 600 orders, 529 completed, 157,078.41, Levon and Astghik, the Chair, 181 online orders.
    - **Compare row counts**: `count(*)` vs `count(column)` (NULLs, outer joins); `count(*)` vs `count(DISTINCT key)` after a join (fan-out); rows in = rows out for windows.
    - **Ask "one row per what?"** before every `sum`, `avg` and join.
    - **Answer the question two independent ways** and compare (e.g. `EXCEPT` both ways should return 0 rows). Make every `ORDER BY` complete first.
    - **Totals must add back up**: buckets, branches, running totals, all to the known total.
    - **All or nothing is suspicious**: a filter that keeps every row or no rows isn't filtering what you think.
    - **Read the columns you computed**: a sort column that isn't sorted, a "latest" equal to the current value, a name that is blank.

    An AI assistant will write any of these queries fluently, whether the logic is right or not. Knowing which number to check is the skill.
    """)
    return


if __name__ == "__main__":
    app.run()
