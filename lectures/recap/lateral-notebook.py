import marimo

__generated_with = "0.25.0"
app = marimo.App(width="medium")


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    # LATERAL — a subquery that can see the row next to it

    A detailed look at one keyword, on the shop data of Lectures 4–6. Lecture 5 (3.5) introduced `LATERAL`; Lecture 6 (4.3) used it for top-N per group. This notebook goes through it slowly: what problem it solves, how PostgreSQL evaluates it, the patterns it is good for, and how to call a **function** once per row with it.

    **Before you run this:** the notebook reads the `lecture06` database. From `lectures/lecture_6/`, run `psql postgres` and `\i steps/00-setup.sql`. Then, from `lectures/recap/`:

    ```
    RECAP_DSN=postgresql://postgres:postgres@localhost:5432/lecture06 marimo edit lateral-notebook.py
    ```

    No cell changes your tables. Part 7 creates one **temporary** function, which disappears when the notebook's connection closes.

    | Part | What |
    |---|---|
    | 1 | The problem: two kinds of subquery, two limits |
    | 2 | How LATERAL is evaluated, on three customers |
    | 3 | Why not a plain join? What it can and can't do |
    | 4 | `JOIN LATERAL` vs `LEFT JOIN LATERAL` |
    | 5 | Top N per group |
    | 6 | Two more patterns: aggregates per row, naming computed values |
    | 7 | Calling a function once per row: `generate_series`, and a function of our own |
    | 8 | The trap: `LIMIT` without a complete `ORDER BY` |
    | 9 | LATERAL, window function or DISTINCT ON? |
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
        os.environ.get("RECAP_DSN", "postgresql://postgres:postgres@localhost:5432/lecture06"),
        autocommit=True,
    )
    return (engine,)


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Check the data first:** 30 customers, 600 orders, 965 order lines.
    """)
    return


@app.cell
def _(engine, mo):
    p0_counts = mo.sql(
        f"""
        SELECT (SELECT count(*) FROM customers)   AS customers,
               (SELECT count(*) FROM orders)      AS orders,
               (SELECT count(*) FROM order_items) AS order_lines
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 1 — The problem: two kinds of subquery, two limits

    The question: **"each customer's latest order: its id, date and total."**

    You already know two places a correlated subquery can go, and each one fails here for a different reason.

    **A subquery in `SELECT` can see the outer row, but returns only one value.** Ask it for two columns. Error on purpose:
    """)
    return


@app.cell
def _(engine, mo, psycopg):
    # Error on purpose -- shows PostgreSQL's message instead of stopping the notebook.
    try:
        engine.execute("""
        SELECT c.firstName,
               (SELECT o.orderID, o.orderTotal
                FROM orders o
                WHERE o.customerID = c.customerID
                ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
                LIMIT 1) AS latest
        FROM customers c
        """)
        _shown = mo.callout(mo.md("No error?! This statement was supposed to fail."), kind="warn")
    except psycopg.Error as _e:
        _hint = f"  \n**HINT:** {_e.diag.message_hint}" if _e.diag.message_hint else ""
        _shown = mo.callout(mo.md(f"**ERROR:** `{_e.diag.message_primary}`{_hint}"), kind="danger")
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    (You could write one subquery per column, but then the same search runs three times, and nothing guarantees all three pick the same order.)

    **A subquery in `FROM` can return many columns and many rows, but it can't see the other tables in `FROM`.** PostgreSQL evaluates it on its own, *before* it knows which customer it is next to. Error on purpose:
    """)
    return


@app.cell
def _(engine, mo, psycopg):
    # Error on purpose -- shows PostgreSQL's message instead of stopping the notebook.
    try:
        engine.execute("""
        SELECT c.firstName, latest.orderID
        FROM customers c
        JOIN (SELECT o.orderID
              FROM orders o
              WHERE o.customerID = c.customerID
              ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
              LIMIT 1) AS latest ON true
        """)
        _shown = mo.callout(mo.md("No error?! This statement was supposed to fail."), kind="warn")
    except psycopg.Error as _e:
        _hint = f"  \n**HINT:** {_e.diag.message_hint}" if _e.diag.message_hint else ""
        _shown = mo.callout(mo.md(f"**ERROR:** `{_e.diag.message_primary}`{_hint}"), kind="danger")
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The hint names the fix (PostgreSQL 16 and later; PostgreSQL 14 prints a more general hint: *there is an entry for table "c", but it cannot be referenced from this part of the query*). **`LATERAL` gives a subquery in `FROM` both abilities:** it may use columns of the `FROM` items listed **before** it, and it may return any number of columns and rows.

    | | Sees the outer row? | Returns |
    |---|---|---|
    | Subquery in `SELECT` | yes | one value |
    | Subquery in `FROM` | no | a whole table |
    | **`LATERAL` subquery in `FROM`** | **yes** | **a whole table** |
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 2 — How LATERAL is evaluated, on three customers

    The PostgreSQL documentation describes it in one sentence: *for each row of the FROM item providing the cross-referenced column(s) … the LATERAL item is evaluated using that row … The resulting row(s) are joined as usual with the rows they were computed from.* [1]

    So: **a loop.** For each customer row, run the subquery with that customer's `customerID` filled in, and join whatever comes back to that row.

    Three customers, to watch it happen: Lusine (5), Levon (24, never ordered) and Diana (27). Their orders first, the raw material:
    """)
    return


@app.cell
def _(engine, mo):
    p2_raw = mo.sql(
        f"""
        SELECT customerID, orderID, orderDate, orderTime, status, orderTotal
        FROM orders
        WHERE customerID IN (5, 27)
        ORDER BY customerID, orderDate, orderTime;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Now the LATERAL query: "each customer's latest order" (any status), for the same three customers.
    """)
    return


@app.cell
def _(engine, mo):
    p2_lateral = mo.sql(
        f"""
        SELECT c.customerID, c.firstName, latest.orderID, latest.orderDate, latest.orderTotal
        FROM customers c
        LEFT JOIN LATERAL (SELECT o.orderID, o.orderDate, o.orderTotal
                           FROM orders o
                           WHERE o.customerID = c.customerID
                           ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
                           LIMIT 1) AS latest ON true
        WHERE c.customerID IN (5, 24, 27)
        ORDER BY c.customerID;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **What PostgreSQL did, row by row:**

    | Customer row | The subquery it ran | Rows it returned | Result row(s) |
    |---|---|---|---|
    | Lusine, `c.customerID` = 5 | `… WHERE o.customerID = 5 ORDER BY … DESC LIMIT 1` | order 1577 (2024-12-23, the last of her 5) | Lusine + 1577 |
    | Levon, `c.customerID` = 24 | `… WHERE o.customerID = 24 …` | none | Levon + NULLs (kept by `LEFT`) |
    | Diana, `c.customerID` = 27 | `… WHERE o.customerID = 27 …` | order 1407 (2024-10-07, the last of her 4) | Diana + 1407 |

    Three things to read in the query:

    - **`c.customerID` inside the subquery** is the outer row's value. That is the whole point, and it's what made Part 1 fail without `LATERAL`.
    - **`ORDER BY … LIMIT 1` runs once per customer**, inside the subquery. "Latest" is decided per customer, not across the whole table.
    - **`ON true`**: the matching already happened inside the subquery (`WHERE o.customerID = c.customerID`), so there is nothing left for `ON` to compare. Every row the subquery returns belongs to this customer.

    **"Before" means before.** `LATERAL` can see items to its **left** in `FROM`, never to its right, because the loop needs the outer row first. (You'll see the error for the other order in Part 7.)
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 3 — Why not a plain join?

    A fair question about Part 2's query: the subquery uses `c.customerID` from outside. Why not drop `LATERAL`, select `customerID` inside the subquery, and match it in `ON` like any other join?

    ### 3.1 The direct rewrite

    Same subquery, minus the outer reference; the matching moves to `ON`:
    """)
    return


@app.cell
def _(engine, mo):
    p3x_rewrite = mo.sql(
        f"""
        SELECT c.customerID, c.firstName, latest.orderID, latest.orderDate, latest.orderTotal
        FROM customers c
        LEFT JOIN (SELECT o.customerID, o.orderID, o.orderDate, o.orderTotal
                   FROM orders o
                   ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
                   LIMIT 1) AS latest ON latest.customerID = c.customerID
        WHERE c.customerID IN (5, 24, 27)
        ORDER BY c.customerID;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **WRONG: all three NULL**, with no error, even though Lusine and Diana have orders. Run the subquery on its own to see why:
    """)
    return


@app.cell
def _(engine, mo):
    p3x_subquery_alone = mo.sql(
        f"""
        SELECT o.customerID, o.orderID, o.orderDate, o.orderTotal
        FROM orders o
        ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
        LIMIT 1;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **One row: order 1600, customer 9, the last order of the year.** Without `LATERAL`, the subquery is evaluated **once, on its own, before the join** [1]. It doesn't know which customer it will be joined to, so `LIMIT 1` keeps the latest order **in the whole table**. Only customer 9 could ever match it; Lusine, Levon and Diana all get NULL.

    That is the difference in one sentence:

    - **Plain join:** compute the subquery **once**, then join its rows.
    - **LATERAL:** compute the subquery **once per outer row**, with that row's values filled in, so `LIMIT 1` means "this customer's first row".

    ### 3.2 A plain join to `orders` keeps everything

    Without any subquery, the join matches every order of the customer:
    """)
    return


@app.cell
def _(engine, mo):
    p3x_plain_join = mo.sql(
        f"""
        SELECT c.customerID, c.firstName, o.orderID, o.orderDate, o.orderTotal
        FROM customers c
        LEFT JOIN orders o ON o.customerID = c.customerID
        WHERE c.customerID IN (5, 24, 27)
        ORDER BY c.customerID, o.orderDate;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    10 rows: all 5 of Lusine's orders, all 4 of Diana's. A join decides **which pairs match**; it has no way to say "and of those, keep only the last one". That needs a ranking, a `LIMIT`, or an aggregate *per customer*.

    ### 3.3 What works: compute "latest" for every customer first, then join

    A plain join can do it if the subquery answers the question for **all** customers at once, so that each customer finds its own row in the result. `row_number()` with `PARTITION BY customerID` (Lecture 6) numbers each customer's orders separately; keep number 1:
    """)
    return


@app.cell
def _(engine, mo):
    p3x_row_number = mo.sql(
        f"""
        SELECT c.customerID, c.firstName, latest.orderID, latest.orderDate, latest.orderTotal
        FROM customers c
        LEFT JOIN (SELECT customerID, orderID, orderDate, orderTotal,
                          row_number() OVER (PARTITION BY customerID
                                             ORDER BY orderDate DESC, orderTime DESC, orderID DESC) AS rn
                   FROM orders) AS latest ON latest.customerID = c.customerID
                                         AND latest.rn = 1
        WHERE c.customerID IN (5, 24, 27)
        ORDER BY c.customerID;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The same three rows as Part 2's LATERAL query. `PARTITION BY customerID` does the "per customer" work that LATERAL's loop did. And `latest.rn = 1` sits in **`ON`**, not `WHERE`: in `WHERE` it would throw out Levon's NULL row (Lecture 4's WHERE-vs-ON trap). Check the whole table:
    """)
    return


@app.cell
def _(engine, mo):
    p3x_row_number_count = mo.sql(
        f"""
        SELECT count(*) AS rows, count(latest.orderID) AS with_an_order
        FROM customers c
        LEFT JOIN (SELECT customerID, orderID,
                          row_number() OVER (PARTITION BY customerID
                                             ORDER BY orderDate DESC, orderTime DESC, orderID DESC) AS rn
                   FROM orders) AS latest ON latest.customerID = c.customerID
                                         AND latest.rn = 1;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    30 and 28, exactly Part 4's LATERAL figures. (A `DISTINCT ON (customerID)` subquery works the same way; Part 9 proves all three methods agree.)

    ### 3.4 The classic "max, then join back", and its trap

    Another plain-join version you will see often: find each customer's last **date** with `max()`, then join `orders` back on that date:
    """)
    return


@app.cell
def _(engine, mo):
    p3x_max_join_back = mo.sql(
        f"""
        SELECT c.customerID, c.firstName, o.orderID, o.orderDate, o.orderTotal
        FROM customers c
        LEFT JOIN (SELECT customerID, max(orderDate) AS last_date
                   FROM orders
                   GROUP BY customerID) AS m ON m.customerID = c.customerID
        LEFT JOIN orders o ON o.customerID = m.customerID
                          AND o.orderDate  = m.last_date
        WHERE c.customerID IN (1, 5, 12, 24, 27)
        ORDER BY c.customerID, o.orderID;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Lusine, Levon and Diana are right. **Anna and Armen get two rows each**: both placed two orders on their last day, and joining back on the date matches both. Over all customers:
    """)
    return


@app.cell
def _(engine, mo):
    p3x_max_count = mo.sql(
        f"""
        SELECT count(*) AS rows
        FROM customers c
        LEFT JOIN (SELECT customerID, max(orderDate) AS last_date
                   FROM orders
                   GROUP BY customerID) AS m ON m.customerID = c.customerID
        LEFT JOIN orders o ON o.customerID = m.customerID
                          AND o.orderDate  = m.last_date;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **WRONG: 32 rows for 30 customers.** `max()` returns one *value*, but a value isn't a row: every order that shares it joins back. `row_number()` and LATERAL's `LIMIT 1` pick exactly one *row*, because their `ORDER BY` (date, time, id) is complete. Rows in = rows out (30) is the check that catches it.

    ### 3.5 The difference, side by side

    | | Plain join to a pre-computed result | LATERAL |
    |---|---|---|
    | The subquery runs | once, for all customers | once per outer row |
    | "Per customer" comes from | `PARTITION BY`, `GROUP BY` or `DISTINCT ON` inside it | `WHERE o.customerID = c.customerID` inside it |
    | Top N | `rn <= N` | `LIMIT N` |
    | Matching happens in | `ON latest.customerID = c.customerID` | the subquery; `ON true` |
    | Natural when | you need the answer for most or all rows anyway | the per-row query is complex, the outer list is short or not a table, or it's a **function call** (Part 7) |

    So Part 2's query doesn't *need* LATERAL; it's one of several correct ways to write it. LATERAL becomes the only option when the thing on the right is a **function whose arguments come from the row on the left**, like `pg_temp.top_orders(c.customerID, 2)` in Part 7: a function call can't be "computed for all customers first" without rewriting it.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 4 — `JOIN LATERAL` vs `LEFT JOIN LATERAL`

    A LATERAL subquery is joined like any table, so the join type keeps its usual meaning (Lecture 4). **Predict first:** 30 customers go in. What comes out?
    """)
    return


@app.cell
def _(engine, mo):
    p3_inner = mo.sql(
        f"""
        SELECT count(*) AS rows
        FROM customers c
        JOIN LATERAL (SELECT o.orderID
                      FROM orders o
                      WHERE o.customerID = c.customerID
                      ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
                      LIMIT 1) AS latest ON true;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **28.** `JOIN LATERAL` (also written `CROSS JOIN LATERAL`, or `, LATERAL`) is an **inner** join: when the subquery returns no rows for a customer, that customer disappears, silently, like any inner join. Levon and Astghik are gone. For "when did we last hear from each customer?", they are exactly the two you need to see.

    `LEFT JOIN LATERAL … ON true` keeps them, with NULLs. Check it with Lecture 4's `count(*)` vs `count(column)`:
    """)
    return


@app.cell
def _(engine, mo):
    p3_left = mo.sql(
        f"""
        SELECT count(*) AS rows, count(latest.orderID) AS with_an_order
        FROM customers c
        LEFT JOIN LATERAL (SELECT o.orderID
                           FROM orders o
                           WHERE o.customerID = c.customerID
                           ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
                           LIMIT 1) AS latest ON true;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    30 rows, 28 with an order. The 2 rows without one are Levon and Astghik.

    **Rule of thumb:** with a LATERAL subquery that can come back empty, decide on purpose. `LEFT JOIN LATERAL … ON true` keeps everyone; `JOIN LATERAL` keeps only those with a result. (`LEFT JOIN LATERAL` needs the `ON true`; `CROSS JOIN LATERAL` takes no `ON`.)
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 5 — Top N per group

    The classic use. "Each customer's 3 biggest orders": several **rows** per customer, which no `SELECT` subquery can return. Change `LIMIT 1` to `LIMIT 3`:
    """)
    return


@app.cell
def _(engine, mo):
    p4_top3 = mo.sql(
        f"""
        SELECT c.firstName, c.lastName, top3.orderID, top3.orderTotal
        FROM customers c
        LEFT JOIN LATERAL (SELECT o.orderID, o.orderTotal
                           FROM orders o
                           WHERE o.customerID = c.customerID
                           ORDER BY o.orderTotal DESC, o.orderID
                           LIMIT 3) AS top3 ON true
        WHERE c.customerID IN (2, 24, 27)
        ORDER BY c.customerID, top3.orderTotal DESC;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Davit gets 3 rows, Diana 3 (of her 4 orders), Levon 1 row of NULLs. **The row count is predictable**: every customer who ordered has at least 3 orders, so 28 × 3 = 84 rows, plus 2 NULL rows from the `LEFT` join = 86.
    """)
    return


@app.cell
def _(engine, mo):
    p4_count = mo.sql(
        f"""
        SELECT count(*) AS rows, count(top3.orderID) AS orders
        FROM customers c
        LEFT JOIN LATERAL (SELECT o.orderID
                           FROM orders o
                           WHERE o.customerID = c.customerID
                           ORDER BY o.orderTotal DESC, o.orderID
                           LIMIT 3) AS top3 ON true;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    86 and 84, as predicted. `orderID` in the `ORDER BY` breaks ties between equal totals (Part 8 shows why that matters).

    **The outer table doesn't have to be a real table.** "The best-selling product in each category": the outer side is the list of categories, and the LATERAL subquery does a whole `GROUP BY` for each one:
    """)
    return


@app.cell
def _(engine, mo):
    p4_best_product = mo.sql(
        f"""
        SELECT p.category, best.productName, best.units
        FROM (SELECT DISTINCT category FROM products) AS p
        LEFT JOIN LATERAL (SELECT pr.productName, sum(i.quantity) AS units
                           FROM order_items i
                           JOIN orders   o  ON o.orderID    = i.orderID
                           JOIN products pr ON pr.productID = i.productID
                           WHERE pr.category = p.category
                             AND o.status = 'completed'
                           GROUP BY pr.productID, pr.productName
                           ORDER BY units DESC, pr.productID
                           LIMIT 1) AS best ON true
        ORDER BY p.category;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    13 categories, and **Chairs is there, with NULLs**: it never sold, so its subquery found nothing, and `LEFT JOIN LATERAL` kept it. The recap notebook's window-function version of this question (`rank() OVER (PARTITION BY category …)`) returned 12 rows: a window can only rank rows that exist. LATERAL starts from the list you choose.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 6 — Two more patterns

    ### 6.1 An aggregate per row: always exactly one row

    A subquery that aggregates *without* `GROUP BY` always returns **exactly one row**, even over zero input rows: `count(*)` is 0 and `sum(...)` is NULL. So a LATERAL aggregate never drops anyone, even with an inner join:
    """)
    return


@app.cell
def _(engine, mo):
    p5_agg = mo.sql(
        f"""
        SELECT c.customerID, c.firstName, stats.orders, stats.spent
        FROM customers c
        CROSS JOIN LATERAL (SELECT count(*) AS orders, sum(o.orderTotal) AS spent
                            FROM orders o
                            WHERE o.customerID = c.customerID
                              AND o.status = 'completed') AS stats
        WHERE c.customerID IN (5, 24, 27, 29)
        ORDER BY c.customerID;
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    p5_agg_count = mo.sql(
        f"""
        SELECT count(*) AS rows
        FROM customers c
        CROSS JOIN LATERAL (SELECT count(*) AS orders, sum(o.orderTotal) AS spent
                            FROM orders o
                            WHERE o.customerID = c.customerID
                              AND o.status = 'completed') AS stats;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    30 rows with `CROSS JOIN`: Levon and Astghik stay, with 0 orders and a NULL spend (`coalesce(stats.spent, 0)` if you want 0). Compare Part 4: the `LIMIT 1` subquery *could* return no rows, so the inner join dropped them. Whether the inner join loses rows depends on whether the subquery can come back empty.

    Two values from one search is also what the `SELECT` subquery in Part 1 couldn't do. And unlike `GROUP BY` after a join, nothing here can fan out (Lecture 4, 4.10): each customer gets exactly one `stats` row.

    ### 6.2 Naming a computed value, then reusing it

    Lecture 3's alias rule: a name made in `SELECT` can't be used in `WHERE`. A LATERAL subquery with no `FROM` computes a value **per row, before `WHERE`**, and gives it a name everyone can use. A second LATERAL can build on the first:
    """)
    return


@app.cell
def _(engine, mo):
    p5_calc = mo.sql(
        f"""
        SELECT i.orderID, p.productName, i.quantity, i.lineTotal, calc.profit, pct.margin_pct
        FROM order_items i
        JOIN products p ON p.productID = i.productID
        CROSS JOIN LATERAL (SELECT i.lineTotal - i.quantity * p.cost AS profit) AS calc
        CROSS JOIN LATERAL (SELECT round(100 * calc.profit / i.lineTotal, 1) AS margin_pct) AS pct
        WHERE pct.margin_pct < 15
        ORDER BY pct.margin_pct, i.orderID
        LIMIT 5;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    `profit` is written once, used by `margin_pct`, and both are used in `SELECT`, `WHERE` and `ORDER BY`. Without LATERAL you would repeat `i.lineTotal - i.quantity * p.cost` in four places. And the result is worth knowing: **two lines were sold at a loss** (a MacBook Air 13 at −20.00 and an iPad at −0.80).

    Each subquery returns exactly one row, so `CROSS JOIN` loses nothing. Check that the rows in equal the rows out:
    """)
    return


@app.cell
def _(engine, mo):
    p5_calc_check = mo.sql(
        f"""
        SELECT count(*) AS lines,
               count(*) FILTER (WHERE pct.margin_pct < 15) AS under_15_pct,
               sum(calc.profit) AS total_profit
        FROM order_items i
        JOIN products p ON p.productID = i.productID
        CROSS JOIN LATERAL (SELECT i.lineTotal - i.quantity * p.cost AS profit) AS calc
        CROSS JOIN LATERAL (SELECT round(100 * calc.profit / i.lineTotal, 1) AS margin_pct) AS pct;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    965 lines in, 965 out; 21 of them under a 15% margin.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 7 — Calling a function once per row

    Some functions return a whole **set of rows**, not one value. PostgreSQL calls them *table functions* or *set-returning functions*, and you use them *like a table* in `FROM` [2]. When their arguments come from the row next to them, that is LATERAL again.

    **One difference from subqueries:** for a function in `FROM`, the `LATERAL` keyword is **optional**. *"For functions the key word is optional; the function's arguments can contain references to columns provided by preceding FROM items in any case."* [1] Writing it anyway makes the per-row call visible to the reader, so this notebook writes it, except once, to prove the point.

    ### 7.1 A built-in function: `generate_series`

    `generate_series(start, stop)` returns the integers from start to stop, one row each [3]:
    """)
    return


@app.cell
def _(engine, mo):
    p6_series = mo.sql(
        f"""
        SELECT n FROM generate_series(1, 3) AS g(n);
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Arguments taken from the row next to it.** One row per *unit* sold instead of per line: each line is repeated `quantity` times. Order 1058 has two lines, one cable × 1 and one cable × 2:
    """)
    return


@app.cell
def _(engine, mo):
    p6_units = mo.sql(
        f"""
        SELECT i.orderID, p.productName, i.quantity, unit.n AS unit_no
        FROM order_items i
        JOIN products p ON p.productID = i.productID
        CROSS JOIN generate_series(1, i.quantity) AS unit(n)
        WHERE i.orderID = 1058
        ORDER BY p.productName, unit.n;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    No `LATERAL` keyword, and `i.quantity` is accepted anyway: this is the "optional for functions" rule. For each line, PostgreSQL called `generate_series(1, 1)` or `generate_series(1, 2)` and joined the result to that line. Check: one generated row per unit sold, so the row count must equal the sum of `quantity`:
    """)
    return


@app.cell
def _(engine, mo):
    p6_units_check = mo.sql(
        f"""
        SELECT (SELECT sum(quantity) FROM order_items) AS units_summed,
               (SELECT count(*)
                FROM order_items i
                CROSS JOIN generate_series(1, i.quantity) AS unit(n)) AS rows_generated;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **A real question: "how many months did each customer go quiet?"** Between a customer's first and last order month, which months had no order at all? Two LATERAL steps, one after the other:

    1. a LATERAL **subquery** finds each customer's first and last order month (one row per customer: it's an aggregate, Part 6.1);
    2. a LATERAL **function call** generates every month in between, using step 1's columns as arguments.

    Diana first (all of 2024, so the months are 1–12):
    """)
    return


@app.cell
def _(engine, mo):
    p6_calendar = mo.sql(
        f"""
        SELECT c.firstName, span.first_month, span.last_month, m.month
        FROM customers c
        CROSS JOIN LATERAL (SELECT min(extract(month FROM o.orderDate))::int AS first_month,
                                   max(extract(month FROM o.orderDate))::int AS last_month
                            FROM orders o
                            WHERE o.customerID = c.customerID) AS span
        CROSS JOIN LATERAL generate_series(span.first_month, span.last_month) AS m(month)
        WHERE c.customerID = 27;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    10 months, January to October. Part 2 showed her orders in January, May, June and October, so 6 of these months were quiet. Now count it for everyone, with `NOT EXISTS` (Lecture 5) testing each generated month:
    """)
    return


@app.cell
def _(engine, mo):
    p6_quiet = mo.sql(
        f"""
        SELECT c.customerID, c.firstName,
               count(*) AS months_in_span,
               count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM orders o
                                                  WHERE o.customerID = c.customerID
                                                    AND extract(month FROM o.orderDate) = m.month)) AS quiet_months
        FROM customers c
        CROSS JOIN LATERAL (SELECT min(extract(month FROM o.orderDate))::int AS first_month,
                                   max(extract(month FROM o.orderDate))::int AS last_month
                            FROM orders o
                            WHERE o.customerID = c.customerID) AS span
        CROSS JOIN LATERAL generate_series(span.first_month, span.last_month) AS m(month)
        GROUP BY c.customerID, c.firstName
        ORDER BY quiet_months DESC, c.customerID
        LIMIT 5;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Diana's 6 matches the hand count. **How many customers are in this result, out of 30?**
    """)
    return


@app.cell
def _(engine, mo):
    p6_quiet_customers = mo.sql(
        f"""
        SELECT count(DISTINCT c.customerID) AS customers
        FROM customers c
        CROSS JOIN LATERAL (SELECT min(extract(month FROM o.orderDate))::int AS first_month,
                                   max(extract(month FROM o.orderDate))::int AS last_month
                            FROM orders o
                            WHERE o.customerID = c.customerID) AS span
        CROSS JOIN LATERAL generate_series(span.first_month, span.last_month) AS m(month);
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **28.** The `span` subquery kept Levon and Astghik (an aggregate always returns a row, Part 6.1), but with `first_month` and `last_month` NULL. And `generate_series` returns **zero rows if any input is NULL** [3], so the `CROSS JOIN` dropped them at step 2. Here that's right ("months between first and last order" means nothing without orders), but it is the same silent drop as Part 4. Know which step can come back empty.

    ### 7.2 A function of our own

    You can write your own set-returning function and call it per row the same way. This one returns a customer's *n* biggest completed orders: Part 5's subquery, packaged with two parameters.

    It is created in **`pg_temp`**, the schema for temporary objects, so it lives only as long as this notebook's connection and changes nothing in the database:

    ```sql
    CREATE OR REPLACE FUNCTION pg_temp.top_orders(p_customer int, p_n int)
    RETURNS TABLE (order_id int, order_date date, order_total numeric)
    LANGUAGE sql
    AS $$
        SELECT o.orderID, o.orderDate, o.orderTotal
        FROM orders o
        WHERE o.customerID = p_customer
          AND o.status = 'completed'
        ORDER BY o.orderTotal DESC, o.orderID
        LIMIT p_n
    $$;
    ```

    - `p_customer`, `p_n`: the **parameters**, used inside the body like values.
    - `RETURNS TABLE (…)`: the function returns a **set of rows** with these columns, like a table [4]. The output names differ from the table's column names (`order_id`, not `orderID`) to keep the two apart.
    - `LANGUAGE sql`: the body is one ordinary SQL query.
    - `$$ … $$`: *dollar quoting*, a way to write the body as a string without doubling every `'` inside it [4].
    """)
    return


@app.cell
def _(engine):
    # Creates the temporary function shown above. pg_temp objects belong to
    # this connection only and are dropped when it closes.
    engine.execute("""
        CREATE OR REPLACE FUNCTION pg_temp.top_orders(p_customer int, p_n int)
        RETURNS TABLE (order_id int, order_date date, order_total numeric)
        LANGUAGE sql
        AS $$
            SELECT o.orderID, o.orderDate, o.orderTotal
            FROM orders o
            WHERE o.customerID = p_customer
              AND o.status = 'completed'
            ORDER BY o.orderTotal DESC, o.orderID
            LIMIT p_n
        $$
    """)
    top_orders_created = True
    return (top_orders_created,)


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Call it once, with fixed arguments**, like a table in `FROM`. Davit's (customer 2) 3 biggest completed orders:
    """)
    return


@app.cell
def _(engine, mo, top_orders_created):
    _ = top_orders_created  # run after the CREATE FUNCTION cell
    p6_fn_once = mo.sql(
        f"""
        SELECT * FROM pg_temp.top_orders(2, 3);
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Why `pg_temp.` in front?** PostgreSQL searches the temporary schema for tables, but *never* for function names [5]. Without the schema name, it can't find the function. Error on purpose:
    """)
    return


@app.cell
def _(engine, mo, psycopg, top_orders_created):
    _ = top_orders_created  # run after the CREATE FUNCTION cell
    # Error on purpose -- shows PostgreSQL's message instead of stopping the notebook.
    try:
        engine.execute("""
        SELECT * FROM top_orders(2, 3)
        """)
        _shown = mo.callout(mo.md("No error?! This statement was supposed to fail."), kind="warn")
    except psycopg.Error as _e:
        _hint = f"  \n**HINT:** {_e.diag.message_hint}" if _e.diag.message_hint else ""
        _shown = mo.callout(mo.md(f"**ERROR:** `{_e.diag.message_primary}`{_hint}"), kind="danger")
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    (A function created in a normal schema, such as `public`, would be found without the prefix.)

    **Now call it once per customer.** The argument `c.customerID` comes from the row on the left:
    """)
    return


@app.cell
def _(engine, mo, top_orders_created):
    _ = top_orders_created  # run after the CREATE FUNCTION cell
    p6_fn_lateral = mo.sql(
        f"""
        SELECT c.firstName, c.lastName, t.order_id, t.order_date, t.order_total
        FROM customers c
        CROSS JOIN LATERAL pg_temp.top_orders(c.customerID, 2) AS t
        WHERE c.customerID IN (2, 5, 24, 27)
        ORDER BY c.customerID, t.order_total DESC;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Four customers asked for, three came back: Levon's call returned no rows, and `CROSS JOIN` dropped him (Part 4 again). The `LEFT JOIN … ON true` version keeps him:
    """)
    return


@app.cell
def _(engine, mo, top_orders_created):
    _ = top_orders_created  # run after the CREATE FUNCTION cell
    p6_fn_left = mo.sql(
        f"""
        SELECT c.firstName, c.lastName, t.order_id, t.order_date, t.order_total
        FROM customers c
        LEFT JOIN LATERAL pg_temp.top_orders(c.customerID, 2) AS t ON true
        WHERE c.customerID IN (2, 5, 24, 27)
        ORDER BY c.customerID, t.order_total DESC;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **The anti-join, with a function.** "Which customers have no completed order?" is "whose `top_orders(…, 1)` comes back empty". This is the pattern the PostgreSQL documentation itself uses to show `LEFT JOIN LATERAL` [1]:
    """)
    return


@app.cell
def _(engine, mo, top_orders_created):
    _ = top_orders_created  # run after the CREATE FUNCTION cell
    p6_fn_anti = mo.sql(
        f"""
        SELECT c.customerID, c.firstName, c.lastName
        FROM customers c
        LEFT JOIN LATERAL pg_temp.top_orders(c.customerID, 1) AS t ON true
        WHERE t.order_id IS NULL;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Levon and Astghik, the known answer.

    **The order in `FROM` matters.** The function can only use columns of items listed *before* it. Put the function first, and `c` doesn't exist yet when it is called. Error on purpose:
    """)
    return


@app.cell
def _(engine, mo, psycopg, top_orders_created):
    _ = top_orders_created  # run after the CREATE FUNCTION cell
    # Error on purpose -- shows PostgreSQL's message instead of stopping the notebook.
    try:
        engine.execute("""
        SELECT c.firstName, t.order_id
        FROM pg_temp.top_orders(c.customerID, 2) AS t, customers c
        """)
        _shown = mo.callout(mo.md("No error?! This statement was supposed to fail."), kind="warn")
    except psycopg.Error as _e:
        _hint = f"  \n**HINT:** {_e.diag.message_hint}" if _e.diag.message_hint else ""
        _shown = mo.callout(mo.md(f"**ERROR:** `{_e.diag.message_primary}`{_hint}"), kind="danger")
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **And the keyword really is optional for functions.** The same call with and without `LATERAL`:
    """)
    return


@app.cell
def _(engine, mo, top_orders_created):
    _ = top_orders_created  # run after the CREATE FUNCTION cell
    p6_fn_with_kw = mo.sql(
        f"""
        SELECT count(*) AS rows, sum(t.order_total) AS top1_total
        FROM customers c
        CROSS JOIN LATERAL pg_temp.top_orders(c.customerID, 1) AS t;
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo, top_orders_created):
    _ = top_orders_created  # run after the CREATE FUNCTION cell
    p6_fn_without_kw = mo.sql(
        f"""
        SELECT count(*) AS rows, sum(t.order_total) AS top1_total
        FROM customers c
        CROSS JOIN pg_temp.top_orders(c.customerID, 1) AS t;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Identical: 28 rows, 37,319.99. For a **subquery**, leaving out `LATERAL` is the error from Part 1. For a **function**, PostgreSQL adds it for you.

    **Why package a query as a function?** The logic ("biggest completed orders, ties broken by id") is written once and reused with different arguments; every report that calls it agrees. The cost: the query is no longer visible where it's used, so you have to trust (or read) the function.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 8 — The trap: `LIMIT` without a complete `ORDER BY`

    `LIMIT 1` picks the first row **in the `ORDER BY`**. If two rows tie on everything you ordered by, either one may come first. Which one depends on the query plan, not on anything you wrote (Lecture 3; Lecture 6, 4.6).

    "Latest order" written as `ORDER BY o.orderDate DESC` and nothing else, for Anna Sargsyan (1) and Armen Gevorgyan (12):
    """)
    return


@app.cell
def _(engine, mo):
    p7_wrong = mo.sql(
        f"""
        SELECT c.customerID, c.firstName, l.orderID, l.orderDate, l.orderTime
        FROM customers c
        JOIN LATERAL (SELECT o.orderID, o.orderDate, o.orderTime FROM orders o
                      WHERE o.customerID = c.customerID
                      ORDER BY o.orderDate DESC
                      LIMIT 1) AS l ON true
        WHERE c.customerID IN (1, 12)
        ORDER BY c.customerID;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Looks fine. Now look at their last days:
    """)
    return


@app.cell
def _(engine, mo):
    p7_ties = mo.sql(
        f"""
        SELECT customerID, orderID, orderDate, orderTime
        FROM orders
        WHERE (customerID = 1 AND orderDate = '2024-12-27')
           OR (customerID = 12 AND orderDate = '2024-12-28')
        ORDER BY customerID, orderTime;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **WRONG:** both placed two orders on their last day, and here the query returned the **earlier** one for both (on PostgreSQL 14, 16 and 18 alike, but nothing guarantees it) (1589 at 15:23, 1595 at 12:06). The date tie left the choice to PostgreSQL. **FIX:** order by everything that makes "latest" unique: date, then time, then `orderID` as the final tie-breaker:
    """)
    return


@app.cell
def _(engine, mo):
    p7_fix = mo.sql(
        f"""
        SELECT c.customerID, c.firstName, l.orderID, l.orderDate, l.orderTime
        FROM customers c
        JOIN LATERAL (SELECT o.orderID, o.orderDate, o.orderTime FROM orders o
                      WHERE o.customerID = c.customerID
                      ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
                      LIMIT 1) AS l ON true
        WHERE c.customerID IN (1, 12)
        ORDER BY c.customerID;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    1591 and 1596, the real latest orders. **Every `LIMIT` inside a LATERAL subquery needs an `ORDER BY` whose last key is unique.**
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 9 — LATERAL, window function or DISTINCT ON?

    "Each customer's latest order" has three standard answers (Lecture 6, Part 4). With complete `ORDER BY`s they must agree. Prove it with `EXCEPT` both ways (Lecture 5, 6.5): 0 rows in every direction means identical results.
    """)
    return


@app.cell
def _(engine, mo):
    p8_agree = mo.sql(
        f"""
        WITH m1 AS (
            SELECT customerID, orderID
            FROM (SELECT customerID, orderID,
                         row_number() OVER (PARTITION BY customerID
                                            ORDER BY orderDate DESC, orderTime DESC, orderID DESC) AS rn
                  FROM orders) AS r
            WHERE rn = 1
        ),
        m2 AS (
            SELECT c.customerID, l.orderID
            FROM customers c
            JOIN LATERAL (SELECT o.orderID FROM orders o
                          WHERE o.customerID = c.customerID
                          ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
                          LIMIT 1) AS l ON true
        ),
        m3 AS (
            SELECT DISTINCT ON (customerID) customerID, orderID
            FROM orders
            ORDER BY customerID, orderDate DESC, orderTime DESC, orderID DESC
        )
        SELECT (SELECT count(*) FROM (SELECT * FROM m1 EXCEPT SELECT * FROM m2) x) AS m1_not_m2,
               (SELECT count(*) FROM (SELECT * FROM m2 EXCEPT SELECT * FROM m1) x) AS m2_not_m1,
               (SELECT count(*) FROM (SELECT * FROM m1 EXCEPT SELECT * FROM m3) x) AS m1_not_m3,
               (SELECT count(*) FROM (SELECT * FROM m3 EXCEPT SELECT * FROM m1) x) AS m3_not_m1;
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    All zero. **When to pick which:**

    | | LATERAL | `row_number()` in a CTE | `DISTINCT ON` |
    |---|---|---|---|
    | Starts from | the outer list (customers, categories): keeps groups with **no** rows, via `LEFT JOIN` | the rows that exist | the rows that exist |
    | Top N, not just top 1 | change `LIMIT` | change `rn <= N` | no, only 1 per group |
    | Several columns, an aggregate, a function call per row | yes | — | — |
    | Portability | a function call written directly in `FROM` is PostgreSQL syntax; the standard wraps it in a sub-`SELECT` [6] | standard SQL | PostgreSQL only [6] |

    ## Summary

    - **`LATERAL` = a subquery in `FROM` that can use columns of the `FROM` items before it.** PostgreSQL evaluates it once per row of those items and joins the result to that row.
    - It returns **any number of columns and rows**, which is what a `SELECT` subquery can't do.
    - **A plain join computes its subquery once**, so `LIMIT 1` there means the latest order in the whole table. A plain join works only if the subquery first answers for every customer (`row_number() … PARTITION BY`, `DISTINCT ON`); `max()` then join back duplicates ties.
    - **`JOIN LATERAL` drops rows whose subquery is empty; `LEFT JOIN LATERAL … ON true` keeps them.** Check with `count(*)` vs `count(column)`.
    - **Patterns:** top N per group; several values from one search; an aggregate per row (always one row); naming computed values to reuse in `WHERE`.
    - **Functions in `FROM` are lateral automatically**: `generate_series(1, i.quantity)`, `pg_temp.top_orders(c.customerID, 2)`. A function that returns no rows (or gets a NULL argument, for `generate_series`) drops the row under an inner join, the same as a subquery.
    - **`LIMIT` inside LATERAL needs a complete `ORDER BY`**, or "the latest" is whatever PostgreSQL happens to read first.

    ### Sources

    [1] PostgreSQL 16 documentation, §7.2.1.5 "LATERAL Subqueries": *"Subqueries appearing in FROM can be preceded by the key word LATERAL. This allows them to reference columns provided by preceding FROM items. (Without LATERAL, each subquery is evaluated independently and so cannot cross-reference any other FROM item.) Table functions appearing in FROM can also be preceded by the key word LATERAL, but for functions the key word is optional; the function's arguments can contain references to columns provided by preceding FROM items in any case. … for each row of the FROM item providing the cross-referenced column(s) … the LATERAL item is evaluated using that row or row set's values of the columns. The resulting row(s) are joined as usual with the rows they were computed from. … It is often particularly handy to LEFT JOIN to a LATERAL subquery, so that source rows will appear in the result even if the LATERAL subquery produces no rows for them."* https://www.postgresql.org/docs/16/queries-table-expressions.html#QUERIES-LATERAL

    [2] Same page, §7.2.1.4 "Table Functions": *"Table functions are functions that produce a set of rows, made up of either base data types (scalar types) or composite data types (table rows). They are used like a table, view, or subquery in the FROM clause of a query."*

    [3] PostgreSQL 16 documentation, §9.25 "Set Returning Functions": `generate_series(start integer, stop integer [, step integer])` *"Generates a series of values from start to stop, with a step size of step. step defaults to 1."* … *"Zero rows are also returned if any input is NULL."* https://www.postgresql.org/docs/16/functions-srf.html

    [4] PostgreSQL 16 documentation, CREATE FUNCTION: RETURNS TABLE *"is effectively another way of declaring a named OUT parameter, except that RETURNS TABLE also implies RETURNS SETOF"*; *"It is often helpful to use dollar quoting … to write the function definition string, rather than the normal single quote syntax. Without dollar quoting, any single quotes or backslashes in the function definition must be escaped by doubling them."* https://www.postgresql.org/docs/16/sql-createfunction.html

    [5] PostgreSQL 16 documentation, §20.11 `search_path`: *"the temporary schema is only searched for relation (table, view, sequence, etc.) and data type names. It is never searched for function or operator names."* https://www.postgresql.org/docs/16/runtime-config-client.html

    [6] PostgreSQL 16 documentation, SELECT, Compatibility: *"PostgreSQL allows a function call to be written directly as a member of the FROM list. In the SQL standard it would be necessary to wrap such a function call in a sub-SELECT; that is, the syntax FROM func(...) alias is approximately equivalent to FROM LATERAL (SELECT func(...)) alias. Note that LATERAL is considered to be implicit …"*; *"DISTINCT ON ( ... ) is an extension of the SQL standard."* https://www.postgresql.org/docs/16/sql-select.html

    Every number in this notebook is the output of the cell above it, run against the `lecture06` database on PostgreSQL 14, 16 and 18.
    """)
    return


if __name__ == "__main__":
    app.run()
