import marimo

__generated_with = "0.25.0"
app = marimo.App(width="medium")


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    # Lecture 6 — Window Functions

    The whole lecture, one query at a time, against **the same shop data as Lectures 4 and 5**: `orders` (the header, with `orderTotal`) and `order_items` (the lines, with `lineTotal`), plus Lecture 4's star schema (`fact_sales`, `dim_date`, `dim_customer`, `dim_product`, `dim_employee`).

    What you already know, and every query here can be checked against: 600 orders, 529 completed; completed revenue **157,078.41**; Levon and Astghik never ordered; Ergonomic Chair Pro never sold; 181 online orders with no employee.

    > **A window function computes over a set of related rows, but does not collapse them: every input row survives.**

    **Before you run this:** from the `lecture_6/` folder, run `psql postgres` and `\i steps/00-setup.sql` (it drops and recreates the `lecture06` database, loads the data, builds the star schema and runs `ANALYZE` so everyone's planner makes the same choices; Parts 2.4, 3.2, 3.3, 4.4 and 4.6 depend on that). Then start the notebook with the connection string in `LECTURE06_DSN`, e.g.

    ```
    LECTURE06_DSN=postgresql://postgres:postgres@localhost:5432/lecture06 marimo edit lecture-06-notebook.py
    ```

    Each trap appears as **wrong query → what's wrong with it → fixed query**, with real results on screen at each step. Needs PostgreSQL 11 or later.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    # Table of contents: built by marimo from every markdown heading below,
    # so it follows the notebook automatically. Click a line to jump there.
    mo.outline(label="Table of contents")
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
    # psql + steps/00-setup.sql; set LECTURE06_DSN if yours differs.
    engine = psycopg.connect(
        os.environ.get("LECTURE06_DSN", "postgresql://postgres:postgres@localhost:5432/lecture06"),
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
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 1 — The problem windows solve

    GROUP BY answers "one number per group" — and throws the rows away to do it. Often you need the group's number AND the row: each order next to its customer's total, each order as a share of all revenue. A window function gives you both.

    ### 1.1 GROUP BY collapses the rows

    Completed revenue per customer: one row per customer, the orders are gone.
    """)
    return


@app.cell
def _(engine, mo):
    p1_01 = mo.sql(
        f"""
        SELECT customerID, sum(orderTotal) AS customer_total
        FROM orders
        WHERE status = 'completed'
        GROUP BY customerID
        ORDER BY customerID
        LIMIT 3
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    p1_02 = mo.sql(
        f"""
        SELECT count(*) AS completed_orders,
               count(DISTINCT customerID) AS customers
        FROM orders
        WHERE status = 'completed'
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The question: "show each completed order NEXT TO its customer's total." Try to keep the order columns and GROUP BY anyway: Error on purpose:
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
        _shown = mo.callout(mo.md("No error?! This query was supposed to fail."), kind="warn")
    except psycopg.Error as _e:
        _shown = mo.callout(mo.md(f"**ERROR:** `{_e.diag.message_primary}`"), kind="danger")
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 1.2 Before windows: aggregate in a derived table, join it back

    (Lecture 5, 1.4: a table subquery at customer grain, joined back to the orders. Here the join is safe — one row per customer on the right — but you have to check that yourself every time.)
    """)
    return


@app.cell
def _(engine, mo):
    p1_03 = mo.sql(
        f"""
        SELECT o.orderID, o.customerID, o.orderTotal, t.customer_total
        FROM orders o
        JOIN (SELECT customerID, sum(orderTotal) AS customer_total
              FROM orders
              WHERE status = 'completed'
              GROUP BY customerID) AS t ON t.customerID = o.customerID
        WHERE o.status = 'completed'
        ORDER BY o.customerID, o.orderID
        LIMIT 3
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ...or a correlated subquery in SELECT (Lecture 5, Part 3). Note that the status filter has to be written TWICE, once per query. Forget it inside and the total quietly includes returned and cancelled orders.
    """)
    return


@app.cell
def _(engine, mo):
    p1_04 = mo.sql(
        f"""
        SELECT o.orderID, o.customerID, o.orderTotal,
               (SELECT sum(o2.orderTotal)
                FROM orders o2
                WHERE o2.customerID = o.customerID
                  AND o2.status = 'completed') AS customer_total
        FROM orders o
        WHERE o.status = 'completed'
        ORDER BY o.customerID, o.orderID
        LIMIT 3
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 1.3 The window version

    sum(...) OVER (PARTITION BY customerID): "the sum over the rows that share this row's customerID". Every input row stays.
    """)
    return


@app.cell
def _(engine, mo):
    p1_05 = mo.sql(
        f"""
        SELECT orderID, customerID, orderTotal,
               sum(orderTotal) OVER (PARTITION BY customerID) AS customer_total
        FROM orders
        WHERE status = 'completed'
        ORDER BY customerID, orderID
        LIMIT 3
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The same numbers as both older versions — one query, no join, the filter written once. (Part 7.5 proves all three agree on every row.)

    ### 1.4 The invariant: rows in = rows out

    A query whose only "extra" is window functions returns exactly as many rows as its input. Predict it, then check it.
    """)
    return


@app.cell(hide_code=True)
def _(engine, mo):
    _df = mo.sql(
        f"""
        select 
            sum(ordertotal) over()
        from orders
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    p1_06 = mo.sql(
        f"""
        SELECT count(*) AS rows_out
        FROM (SELECT orderID,
                     sum(orderTotal)   OVER ()                        AS all_orders,
                     count(*)          OVER (PARTITION BY customerID) AS customer_orders,
                     avg(orderTotal)   OVER (PARTITION BY status)     AS status_avg
              FROM orders) AS w
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    600 in, 600 out. Three windows, three different groupings, and not one row added or lost.

    ### 1.5 Callback: Lecture 4's fan-out (4.10)

    To put each customer's moneySpent next to their orders, Lecture 4 JOINED — and the join copied it onto every order:
    """)
    return


@app.cell
def _(engine, mo):
    p1_07 = mo.sql(
        f"""
        SELECT count(*)          AS rows,
               sum(c.moneySpent) AS total_money_spent
        FROM customers c
        JOIN orders o ON o.customerID = c.customerID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG total: 30 customers became 600 rows, and the sum counted each customer's moneySpent once per order.

    A window brings a group number TO the rows that are already there. It never adds rows, so there is nothing to multiply:
    """)
    return


@app.cell
def _(engine, mo):
    p1_08 = mo.sql(
        f"""
        SELECT count(*)                         AS rows,
               sum(moneySpent)                  AS total_money_spent,
               min(all_customers)               AS window_total
        FROM (SELECT moneySpent,
                     sum(moneySpent) OVER () AS all_customers
              FROM customers) AS w
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    30 in, 30 out; the total is the known completed revenue.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 2 — Anatomy of OVER()

    ```
      function(...) OVER (PARTITION BY ...   which rows belong together
                          ORDER BY ...       in what order, inside each group
                          frame)             which of those rows this row sees
    ```

    Built up one piece at a time. Frames get Part 6 to themselves.

    ### 2.1 OVER () -- the whole result is one window

    Each completed order as a share of completed revenue.
    """)
    return


@app.cell
def _(engine, mo):
    p2_01 = mo.sql(
        f"""
        SELECT orderID, orderTotal,
               sum(orderTotal) OVER ()                                   AS all_completed,
               round(100 * orderTotal / sum(orderTotal) OVER (), 2)      AS pct_of_revenue
        FROM orders
        WHERE status = 'completed'
        ORDER BY orderTotal DESC, orderID
        LIMIT 5
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Check: the shares add up to 100, over all 529 rows.
    """)
    return


@app.cell
def _(engine, mo):
    p2_02 = mo.sql(
        f"""
        SELECT count(*) AS rows, round(sum(pct), 2) AS total_pct
        FROM (SELECT 100 * orderTotal / sum(orderTotal) OVER () AS pct
              FROM orders
              WHERE status = 'completed') AS w
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    #### Real problem: which single orders matter for the whole year?

    **Task:** Finance wants every completed order that on its own brought in more than 1% of the year's completed revenue — how many there are, and how much of the year they make up together.

    **Solution:** compute each order's share with sum() OVER () in a derived table, then filter on the share outside (filtering on a window needs a subquery — Part 4.1 explains why).
    """)
    return


@app.cell
def _(engine, mo):
    p2_03 = mo.sql(
        f"""
        SELECT count(*)                AS big_orders,
               sum(orderTotal)         AS their_revenue,
               round(sum(pct), 2)      AS pct_of_year
        FROM (SELECT orderTotal,
                     100 * orderTotal / sum(orderTotal) OVER () AS pct
              FROM orders
              WHERE status = 'completed') AS shares
        WHERE pct > 1
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Reading the result:** 9 of the 529 completed orders — under 2% of the orders — bring in 11.72% of the year's revenue.

    ### 2.2 PARTITION BY -- one window per group

    Lusine Avetisyan (customerID 5): each completed order next to her total, her average, and how far the order is from that average.
    """)
    return


@app.cell
def _(engine, mo):
    p2_04 = mo.sql(
        f"""
        SELECT orderID, orderDate, orderTotal,
               sum(orderTotal) OVER (PARTITION BY customerID)                         AS her_total,
               round(100 * orderTotal / sum(orderTotal) OVER (PARTITION BY customerID), 1) AS pct_of_her_total,
               round(avg(orderTotal) OVER (PARTITION BY customerID), 2)               AS her_avg,
               round(orderTotal - avg(orderTotal) OVER (PARTITION BY customerID), 2)  AS diff_from_avg
        FROM orders
        WHERE status = 'completed' AND customerID = 5
        ORDER BY orderDate
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The five aggregates all work as window functions:
    """)
    return


@app.cell
def _(engine, mo):
    p2_05 = mo.sql(
        f"""
        SELECT orderID, orderTotal,
               count(*)        OVER (PARTITION BY customerID) AS n,
               min(orderTotal) OVER (PARTITION BY customerID) AS smallest,
               max(orderTotal) OVER (PARTITION BY customerID) AS biggest
        FROM orders
        WHERE status = 'completed' AND customerID = 5
        ORDER BY orderDate
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    #### Real problem: customers who depend on one big purchase

    **Task:** Marketing wants the customers for whom a single order is more than half of everything they spent with us — "one-off buyers" who need a reason to come back.

    **Solution:** each order's share of ITS customer's total, with PARTITION BY customerID; keep the orders above 50%.
    """)
    return


@app.cell
def _(engine, mo):
    p2_06 = mo.sql(
        f"""
        SELECT c.firstName, c.lastName, s.orderID, s.orderTotal, s.customer_total,
               round(100 * s.orderTotal / s.customer_total, 1) AS pct_of_customer
        FROM (SELECT customerID, orderID, orderTotal,
                     sum(orderTotal) OVER (PARTITION BY customerID) AS customer_total
              FROM orders
              WHERE status = 'completed') AS s
        JOIN customers c ON c.customerID = s.customerID
        WHERE s.orderTotal > 0.5 * s.customer_total
        ORDER BY pct_of_customer DESC
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Reading the result:** 4 customers. Lusine is one of them — her order 1276 is the 55.8% from the example above.

    ### 2.3 ORDER BY inside OVER -- an order within each window

    Add ORDER BY and sum() becomes a RUNNING sum: each row sees the rows up to itself. (Why "up to itself" is the default, and where that default bites, is Part 6.)
    """)
    return


@app.cell
def _(engine, mo):
    p2_07 = mo.sql(
        f"""
        SELECT orderID, orderDate, orderTotal,
               sum(orderTotal) OVER (PARTITION BY customerID
                                     ORDER BY orderDate, orderID) AS running_total
        FROM orders
        WHERE status = 'completed' AND customerID = 5
        ORDER BY orderDate
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Why ", orderID" in the window's ORDER BY?** Lusine never ordered twice on one day, so for her it changes nothing. Davit (customer 2) did, four times. Here are his orders around 12 November, with the running total computed both ways. (The date filter is OUTSIDE, in a subquery, so both totals still count from January — a WHERE on the dates would restart them. Part 2.5 explains why.)
    """)
    return


@app.cell
def _(engine, mo):
    p2_08 = mo.sql(
        f"""
        SELECT orderID, orderDate, orderTime, orderTotal, by_date_only, by_date_and_id
        FROM (SELECT orderID, orderDate, orderTime, orderTotal,
                     sum(orderTotal) OVER (PARTITION BY customerID
                                           ORDER BY orderDate)          AS by_date_only,
                     sum(orderTotal) OVER (PARTITION BY customerID
                                           ORDER BY orderDate, orderID) AS by_date_and_id
              FROM orders
              WHERE status = 'completed' AND customerID = 2) AS running
        WHERE orderDate BETWEEN '2024-11-11' AND '2024-11-13'
        ORDER BY orderDate, orderID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **ORDER BY orderDate only:** Davit's three orders on 12 November all show the same 5607.71. Rows with an equal ORDER BY value are "peers", and the default frame takes all peers at once — so order 1466's "running total" already includes 1467 and 1471, which came later that day. The total looks stuck for three rows.

    **ORDER BY orderDate, orderID:** no two rows share a position any more, so each row adds only itself: 5551.47, 5589.47, 5607.71. The day still ends on 5607.71 — only the rows in between change.

    How much of Davit's history is affected?
    """)
    return


@app.cell
def _(engine, mo):
    p2_09 = mo.sql(
        f"""
        SELECT count(*)                                              AS orders,
               count(*) FILTER (WHERE by_date_only <> by_date_and_id) AS different_running_total
        FROM (SELECT sum(orderTotal) OVER (PARTITION BY customerID
                                           ORDER BY orderDate)          AS by_date_only,
                     sum(orderTotal) OVER (PARTITION BY customerID
                                           ORDER BY orderDate, orderID) AS by_date_and_id
              FROM orders
              WHERE status = 'completed' AND customerID = 2) AS running
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    5 of his 43 completed orders: the earlier orders on each day with more than one order. The rest match, which is why the tie-breaker seems to "make no difference" until a day with two orders comes along. The rule: add a unique column (orderID) at the end of a window's ORDER BY whenever the order can have ties. orderTime is the more meaningful choice within a day; orderID guarantees uniqueness. Part 6.2 shows the same effect on the whole year's running total.

    #### Real problem: when did each customer reach Gold status?

    **Task:** the loyalty programme makes a customer "Gold" on the day their completed spending, added up order by order, first reaches 5,000. For each customer who got there: on which date?

    **Solution:** a running total per customer (PARTITION BY customerID, ORDER BY date, time, id); then, per customer, the first date where it is 5,000 or more. (The ORDER BY is unique — no ties — so the default frame is safe here; Part 6 explains why that matters.)
    """)
    return


@app.cell
def _(engine, mo):
    p2_10 = mo.sql(
        f"""
        WITH running AS (
            SELECT customerID, orderDate,
                   sum(orderTotal) OVER (PARTITION BY customerID
                                         ORDER BY orderDate, orderTime, orderID) AS spent_so_far
            FROM orders
            WHERE status = 'completed'
        )
        SELECT c.firstName, c.lastName, min(r.orderDate) AS gold_since
        FROM running r
        JOIN customers c ON c.customerID = r.customerID
        WHERE r.spent_so_far >= 5000
        GROUP BY c.customerID, c.firstName, c.lastName
        ORDER BY gold_since
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Reading the result:** 14 of the 28 customers reached Gold during the year, the first on 2024-04-26 and the last on 2024-11-22.

    ### 2.4 THE TRAP: ORDER BY inside OVER is not the query's ORDER BY

    "The first five completed orders of the year, numbered." No outer ORDER BY — the window is already ordered by date...

    > **New function: `row_number()`** — numbers the rows of each window 1, 2, 3 ... in the order of the window's ORDER BY. Every row gets a different number, even rows that tie, and which of two tied rows comes first is not guaranteed.
    """)
    return


@app.cell
def _(engine, mo):
    p2_11 = mo.sql(
        f"""
        SELECT orderID, orderDate, orderTotal,
               row_number() OVER (ORDER BY orderDate, orderID) AS nr
        FROM orders
        WHERE status = 'completed'
        LIMIT 5
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Looks right — by luck. To number the rows, PostgreSQL sorted them by date, and nothing came after the sort to change their order.

    A colleague adds one column: how big is each order, compared with all the others? Same WHERE, same window for nr, same LIMIT.

    > **New function: `rank()`** — the row's position in the window's ORDER BY. Tied rows share a position, and the positions after a tie are skipped: 1, 2, 2, 4.
    """)
    return


@app.cell
def _(engine, mo):
    p2_12 = mo.sql(
        f"""
        SELECT orderID, orderDate, orderTotal,
               rank()       OVER (ORDER BY orderTotal DESC)  AS size_rank,
               row_number() OVER (ORDER BY orderDate, orderID) AS nr
        FROM orders
        WHERE status = 'completed'
        LIMIT 5
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG: these are not the first five orders of the year (look at nr and orderDate). The rows now come out in whichever order the LAST window sort left them — here, by size. No error.

    FIX: the order you see is decided by the query's own ORDER BY, and nothing else.
    """)
    return


@app.cell
def _(engine, mo):
    p2_13 = mo.sql(
        f"""
        SELECT orderID, orderDate, orderTotal,
               rank()       OVER (ORDER BY orderTotal DESC)  AS size_rank,
               row_number() OVER (ORDER BY orderDate, orderID) AS nr
        FROM orders
        WHERE status = 'completed'
        ORDER BY nr
        LIMIT 5
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The same family as Lecture 5's "I sorted it in the CTE" (5.4): an ORDER BY anywhere but the end of the outer query sorts something, but not your output.

    ### 2.5 When do window functions run?

    ```
      FROM -> WHERE -> GROUP BY -> HAVING -> WINDOW FUNCTIONS
           -> SELECT list -> DISTINCT -> ORDER BY -> LIMIT
    ```

    A window sees only the rows that survived WHERE (and GROUP BY).

    "What share of all completed revenue did Lusine's orders bring in?"
    """)
    return


@app.cell
def _(engine, mo):
    p2_14 = mo.sql(
        f"""
        SELECT orderID, orderTotal,
               round(100 * orderTotal / sum(orderTotal) OVER (), 2) AS pct_of_revenue
        FROM orders
        WHERE status = 'completed' AND customerID = 5
        ORDER BY orderDate
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG: the shares add up to 100 — these are shares of LUSINE'S revenue. WHERE removed everyone else before the window ran, so sum() OVER () only saw her 4 orders. No error.

    FIX: compute the window over all completed orders first, filter after (a derived table, Lecture 5 1.4; Part 4 explains why this is THE pattern):
    """)
    return


@app.cell
def _(engine, mo):
    p2_15 = mo.sql(
        f"""
        SELECT orderID, orderTotal, pct_of_revenue
        FROM (SELECT orderID, customerID, orderDate, orderTotal,
                     round(100 * orderTotal / sum(orderTotal) OVER (), 2) AS pct_of_revenue
              FROM orders
              WHERE status = 'completed') AS w
        WHERE customerID = 5
        ORDER BY orderDate
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Together 1.82% of completed revenue (2,861.90 of 157,078.41).

    ### 2.6 Windows over aggregates

    Windows run AFTER GROUP BY, so they can work on the groups: rank customers by their completed revenue, with their share.
    """)
    return


@app.cell
def _(engine, mo):
    p2_16 = mo.sql(
        f"""
        SELECT customerID,
               sum(orderTotal)                                  AS revenue,
               rank() OVER (ORDER BY sum(orderTotal) DESC)      AS revenue_rank,
               round(100 * sum(orderTotal) / sum(sum(orderTotal)) OVER (), 1) AS pct_of_all
        FROM orders
        WHERE status = 'completed'
        GROUP BY customerID
        ORDER BY revenue_rank
        LIMIT 5
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    sum(sum(orderTotal)) OVER () reads strangely but is legal: the inner sum is the GROUP BY aggregate (one per customer), the outer sum adds those 28 group totals up across the window. Readable alternative: aggregate in a CTE first, window over the CTE in the outer query.
    """)
    return


@app.cell
def _(engine, mo):
    p2_17 = mo.sql(
        f"""
        WITH per_customer AS (
            SELECT customerID, sum(orderTotal) AS revenue
            FROM orders
            WHERE status = 'completed'
            GROUP BY customerID
        )
        SELECT customerID, revenue,
               rank() OVER (ORDER BY revenue DESC)                  AS revenue_rank,
               round(100 * revenue / sum(revenue) OVER (), 1)       AS pct_of_all
        FROM per_customer
        ORDER BY revenue_rank
        LIMIT 5
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 2.7 Named windows

    Four functions over the same window: write the window once.
    """)
    return


@app.cell
def _(engine, mo):
    p2_18 = mo.sql(
        f"""
        SELECT orderID, orderTotal,
               count(*)                  OVER w AS n,
               sum(orderTotal)           OVER w AS her_total,
               round(avg(orderTotal) OVER w, 2) AS her_avg,
               max(orderTotal)           OVER w AS biggest
        FROM orders
        WHERE status = 'completed' AND customerID = 5
        WINDOW w AS (PARTITION BY customerID)
        ORDER BY orderDate
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 3 — Ranking functions

    ```
      row_number()  1, 2, 3, 4 ...  ties get DIFFERENT numbers (who gets which? arbitrary)
      rank()        1, 2, 2, 4 ...  ties share a number, then a gap
      dense_rank()  1, 2, 2, 3 ...  ties share a number, no gap
    ```

    All of them need ORDER BY inside OVER: a rank is a position in an order.

    ### 3.0 Six rows first

    Before the real data: six made-up rows, two pairs of ties (ids 2 and 3 both scored 85; ids 4 and 5 both 70). Every ranking function, score from high to low. Two windows: `w` orders by score only, so rank and friends can SEE the ties; `wt` adds id as a tie-breaker for row_number and ntile, which always split ties — so the split is predictable instead of up to PostgreSQL.

    > **New function: `dense_rank()`** — like rank(), but nothing is skipped after a tie: 1, 2, 2, 3. It counts distinct values.

    > **New function: `ntile(n)`** — deals the rows of each window, in order, into n buckets numbered 1 to n, as equal in size as possible.

    > **New function: `percent_rank()`** — the row's relative position, from 0 (first) to 1 (last): (rank - 1) / (rows - 1).

    > **New function: `cume_dist()`** — the share of the window's rows that come at or before this row, ties included: from 1/N to 1.
    """)
    return


@app.cell
def _(engine, mo):
    p3_01 = mo.sql(
        f"""
        SELECT id, score,
               row_number()  OVER wt AS row_number,
               rank()        OVER w  AS rank,
               dense_rank()  OVER w  AS dense_rank,
               ntile(3)      OVER wt AS ntile_3,
               round((percent_rank() OVER w)::numeric, 3) AS percent_rank,
               round((cume_dist()    OVER w)::numeric, 3) AS cume_dist
        FROM (VALUES (1, 90), (2, 85), (3, 85), (4, 70), (5, 70), (6, 60)) AS t(id, score)
        WINDOW w  AS (ORDER BY score DESC),
               wt AS (ORDER BY score DESC, id)
        ORDER BY id
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **How each number is computed — the three ranks:**

    | id | score | row_number: count the rows in order | rank: 1 + rows with a HIGHER score | dense_rank: 1 + DISTINCT higher scores |
    |---|---|---|---|---|
    | 1 | 90 | 1 | 1 + 0 = **1** | 1 + 0 = **1** |
    | 2 | 85 | 2 | 1 + 1 (id 1) = **2** | 1 + 1 (90) = **2** |
    | 3 | 85 | 3 — tied with id 2; only the id puts it second | 1 + 1 (id 1) = **2** | 1 + 1 (90) = **2** |
    | 4 | 70 | 4 | 1 + 3 (ids 1, 2, 3) = **4** | 1 + 2 (90, 85) = **3** |
    | 5 | 70 | 5 | 1 + 3 (ids 1, 2, 3) = **4** | 1 + 2 (90, 85) = **3** |
    | 6 | 60 | 6 | 1 + 5 (ids 1-5) = **6** | 1 + 3 (90, 85, 70) = **4** |

    rank skips 3 and 5: two rows share 2nd place, so the next row is 4th. dense_rank never skips: it numbers the distinct scores 90, 85, 70, 60 as 1, 2, 3, 4.

    **How each number is computed — the distribution functions:**

    | id | ntile(3): 6 rows into 3 buckets of 2, in order | percent_rank = (rank - 1) / (6 - 1) | cume_dist = rows with a score >= this one / 6 |
    |---|---|---|---|
    | 1 | 1 | (1 - 1) / 5 = **0.000** | 1 / 6 = **0.167** |
    | 2 | 1 | (2 - 1) / 5 = **0.200** | 3 / 6 = **0.500** |
    | 3 | **2** — its tie partner id 2 is in bucket 1 | (2 - 1) / 5 = **0.200** | 3 / 6 = **0.500** |
    | 4 | 2 | (4 - 1) / 5 = **0.600** | 5 / 6 = **0.833** |
    | 5 | **3** — its tie partner id 4 is in bucket 2 | (4 - 1) / 5 = **0.600** | 5 / 6 = **0.833** |
    | 6 | 3 | (6 - 1) / 5 = **1.000** | 6 / 6 = **1.000** |

    ntile, like row_number, cuts wherever the count says, even through a tie. percent_rank and cume_dist give tied rows the same value.

    PARTITION BY restarts the numbering in each group. The same six rows, split into group A (ids 1-3) and group B (ids 4-6):
    """)
    return


@app.cell
def _(engine, mo):
    p3_02 = mo.sql(
        f"""
        SELECT grp, id, score,
               rank() OVER (ORDER BY score DESC)                   AS rank_overall,
               rank() OVER (PARTITION BY grp ORDER BY score DESC)  AS rank_in_group
        FROM (VALUES ('A', 1, 90), ('A', 2, 85), ('A', 3, 85),
                     ('B', 4, 70), ('B', 5, 70), ('B', 6, 60)) AS t(grp, id, score)
        ORDER BY grp, id
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    | id | rank_overall | rank_in_group | Why |
    |---|---|---|---|
    | 4 | 4 | **1** | overall, three rows score higher; inside group B, none do |
    | 6 | 6 | **3** | inside group B, only ids 4 and 5 score higher: 1 + 2 = 3 |

    **What a tie-breaker does to rank.** The same rank(), but over `wt` (score, then id):
    """)
    return


@app.cell
def _(engine, mo):
    p3_03 = mo.sql(
        f"""
        SELECT id, score,
               rank() OVER (ORDER BY score DESC)     AS rank_by_score,
               rank() OVER (ORDER BY score DESC, id) AS rank_by_score_and_id
        FROM (VALUES (1, 90), (2, 85), (3, 85), (4, 70), (5, 70), (6, 60)) AS t(id, score)
        ORDER BY id
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    With the id added, no two rows are equal on (score, id) any more, so there are no ties left to share a place: rank becomes 1, 2, 3, 4, 5, 6 — exactly row_number. A tie-breaker is right for row_number and ntile (to make the split predictable) and wrong for rank and dense_rank, whose whole job is to show ties. Part 3.3 shows what happens to row_number WITHOUT a tie-breaker, on the real data.

    ### 3.1 The three ranks side by side, on real ties

    The customer league table by number of orders — all 30 customers, so Lecture 4's LEFT JOIN keeps the two with none.
    """)
    return


@app.cell
def _(engine, mo):
    p3_04 = mo.sql(
        f"""
        SELECT c.customerID, c.firstName, c.lastName,
               count(o.orderID)                                AS orders,
               row_number() OVER (ORDER BY count(o.orderID) DESC) AS row_number,
               rank()       OVER (ORDER BY count(o.orderID) DESC) AS rank,
               dense_rank() OVER (ORDER BY count(o.orderID) DESC) AS dense_rank
        FROM customers c
        LEFT JOIN orders o ON o.customerID = c.customerID
        GROUP BY c.customerID, c.firstName, c.lastName
        ORDER BY orders DESC, c.customerID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Real ties: Narek and Lilit (29), Mariam and Hayk (16), Meline and Ani (10), Arpine and Mher (8), Levon and Astghik (0). Look at rows 8-10: row_number 8, 9, 10; rank 8, 8, 10; dense_rank 8, 8, 9.

    #### Real problem: salesperson of the month

    **Task:** each month, the salesperson with the highest completed revenue gets a bonus. If two people tie, both get it. Who won each month, and who won most often?

    **Solution:** revenue per salesperson per month (GROUP BY), then rank() inside each month (PARTITION BY month), keep rank 1. rank, not row_number: a tie must give two winners, not one picked at random.
    """)
    return


@app.cell
def _(engine, mo):
    p3_05 = mo.sql(
        f"""
        WITH monthly AS (
            SELECT extract(month FROM o.orderDate)::int AS month,
                   e.firstName,
                   sum(o.orderTotal) AS revenue
            FROM orders o
            JOIN employees e ON e.employeeID = o.employeeID
            WHERE o.status = 'completed'
            GROUP BY extract(month FROM o.orderDate), e.employeeID, e.firstName
        ),
        ranked AS (
            SELECT month, firstName, revenue,
                   rank() OVER (PARTITION BY month ORDER BY revenue DESC) AS place
            FROM monthly
        )
        SELECT month, firstName, revenue
        FROM ranked
        WHERE place = 1
        ORDER BY month
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Reading the result:** 12 months, 12 winners — no month had a tie. Ani won 5 months, Hayk 3, Gor 2, Vahe and Arman 1 each. (The online orders are left out on purpose: the bonus is for people. Part 7.1.)

    ### 3.2 ntile, percent_rank, cume_dist

    Quartiles of the same table: ntile(4) deals 30 customers into 4 buckets of 8, 8, 7, 7, in order.
    """)
    return


@app.cell
def _(engine, mo):
    p3_06 = mo.sql(
        f"""
        SELECT c.firstName, c.lastName,
               count(o.orderID)                                          AS orders,
               ntile(4)       OVER (ORDER BY count(o.orderID) DESC)      AS quartile,
               round(percent_rank() OVER (ORDER BY count(o.orderID) DESC)::numeric, 3) AS percent_rank,
               round(cume_dist()    OVER (ORDER BY count(o.orderID) DESC)::numeric, 3) AS cume_dist
        FROM customers c
        LEFT JOIN orders o ON o.customerID = c.customerID
        GROUP BY c.customerID, c.firstName, c.lastName
        ORDER BY orders DESC, c.customerID
        LIMIT 10
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG, if quartiles are meant to group equal customers: Narek and Lilit placed the same 29 orders and land in DIFFERENT quartiles: the bucket boundary falls between rows 8 and 9, and ntile, like row_number, splits a tie wherever it falls. percent_rank and cume_dist treat ties as equals (both 29s get the same value).

    #### Real problem: four customer tiers for a campaign

    **Task:** split the customers who bought something into 4 equal-sized tiers by completed spending, so each tier gets its own offer. For each tier: how many customers, their spending range, and their revenue.

    **Solution:** spending per customer, ntile(4) over it, then GROUP BY tier.
    """)
    return


@app.cell
def _(engine, mo):
    p3_07 = mo.sql(
        f"""
        WITH spending AS (
            SELECT customerID, sum(orderTotal) AS spent
            FROM orders
            WHERE status = 'completed'
            GROUP BY customerID
        ),
        tiers AS (
            SELECT spent, ntile(4) OVER (ORDER BY spent DESC, customerID) AS tier
            FROM spending
        )
        SELECT tier, count(*) AS customers, min(spent) AS lowest, max(spent) AS highest,
               sum(spent) AS revenue
        FROM tiers
        GROUP BY tier
        ORDER BY tier
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Reading the result:** 28 customers, 7 per tier. Tier 1 alone brings in 71,059.04 — 45% of the 157,078.41. (No two customers spent exactly the same, so no tie is split here; the customerID tie-breaker is there in case one ever is.)

    #### Real problem: the 80/20 check on products

    **Task:** "20% of our products bring 80% of our revenue" — is that true here? Which products make up the top 20% by revenue, and how much do they bring in?

    **Solution:** revenue per product (from Lecture 4's star), cume_dist() over it from the top; the top 20% are the rows with cume_dist <= 0.2.
    """)
    return


@app.cell
def _(engine, mo):
    p3_08 = mo.sql(
        f"""
        WITH product_revenue AS (
            SELECT p.productName, sum(f.revenue) AS revenue
            FROM fact_sales f
            JOIN dim_product p ON p.productKey = f.productKey
            WHERE f.status = 'completed'
            GROUP BY p.productKey, p.productName
        ),
        placed AS (
            SELECT productName, revenue,
                   cume_dist() OVER (ORDER BY revenue DESC) AS share_at_or_above
            FROM product_revenue
        )
        SELECT productName, revenue, round(share_at_or_above::numeric, 3) AS cume_dist
        FROM placed
        WHERE share_at_or_above <= 0.2
        ORDER BY revenue DESC
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    p3_09 = mo.sql(
        f"""
        SELECT sum(revenue) AS top_20pct_revenue,
               round(100 * sum(revenue)
                     / (SELECT sum(revenue) FROM fact_sales WHERE status = 'completed'), 1) AS pct_of_revenue
        FROM (SELECT sum(f.revenue) AS revenue,
                     cume_dist() OVER (ORDER BY sum(f.revenue) DESC) AS share_at_or_above
              FROM fact_sales f
              WHERE f.status = 'completed'
              GROUP BY f.productKey) AS placed
        WHERE share_at_or_above <= 0.2
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Reading the result:** 7 of the 36 products that sold — 20% — bring in 80,843.35, 51.5% of revenue. Not 80/20 here; more like 20/50.

    ### 3.3 THE TRAP: row_number() on ties is arbitrary

    "A loyalty gift for our top 8 customers by number of orders." (Filtering on a window needs a subquery — Part 4 explains why.) Analyst A counts from orders, then looks up the names:
    """)
    return


@app.cell
def _(engine, mo):
    p3_10 = mo.sql(
        f"""
        SELECT x.nr, c.firstName, c.lastName, x.orders
        FROM (SELECT customerID, count(*) AS orders,
                     row_number() OVER (ORDER BY count(*) DESC) AS nr
              FROM orders
              GROUP BY customerID) AS x
        JOIN customers c ON c.customerID = x.customerID
        WHERE x.nr BETWEEN 7 AND 9
        ORDER BY x.nr
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Analyst B starts from customers, as Lecture 4 taught:
    """)
    return


@app.cell
def _(engine, mo):
    p3_11 = mo.sql(
        f"""
        SELECT nr, firstName, lastName, orders
        FROM (SELECT c.firstName, c.lastName, count(o.orderID) AS orders,
                     row_number() OVER (ORDER BY count(o.orderID) DESC) AS nr
              FROM customers c
              LEFT JOIN orders o ON o.customerID = c.customerID
              GROUP BY c.customerID, c.firstName, c.lastName) AS x
        WHERE nr BETWEEN 7 AND 9
        ORDER BY nr
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG, and you can't tell from either result alone: same question, same window, two different 8th customers. Lilit gets the gift in A, Narek in B. Both have 29 orders; row_number had to put one of them first and took whichever its sort met first — which depends on the plan, not on anything in the query. No error, no warning.

    Same family as the LIMIT 1 tie trap from the Chinook lab: whenever "the first N" cuts through a tie, the cut is arbitrary.

    FIX 1: make the order complete — a tie-breaker that is unique (a key). Now every run, every plan, picks the same 8th customer:
    """)
    return


@app.cell
def _(engine, mo):
    p3_12 = mo.sql(
        f"""
        SELECT nr, firstName, lastName, orders
        FROM (SELECT c.firstName, c.lastName, count(o.orderID) AS orders,
                     row_number() OVER (ORDER BY count(o.orderID) DESC, c.customerID) AS nr
              FROM customers c
              LEFT JOIN orders o ON o.customerID = c.customerID
              GROUP BY c.customerID, c.firstName, c.lastName) AS x
        WHERE nr BETWEEN 7 AND 9
        ORDER BY nr
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Deterministic — but "lower customerID wins" is a business rule now. Say it out loud, or pick a tie-breaker that means something (revenue).

    FIX 2: don't hide the tie. rank() <= 8 gives everyone who is tied for 8th place — 9 customers, and the decision goes back to a human.
    """)
    return


@app.cell
def _(engine, mo):
    p3_13 = mo.sql(
        f"""
        SELECT count(*) AS customers
        FROM (SELECT count(o.orderID) AS orders,
                     rank() OVER (ORDER BY count(o.orderID) DESC) AS rnk
              FROM customers c
              LEFT JOIN orders o ON o.customerID = c.customerID
              GROUP BY c.customerID) AS x
        WHERE rnk <= 8
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 3.4 Gaps or no gaps: which one answers "top 2"?

    "The two best-selling products in each category get the front shelf." Times ordered = order lines per product (Ergonomic Chair Pro: 0).
    """)
    return


@app.cell
def _(engine, mo):
    p3_14 = mo.sql(
        f"""
        WITH sold AS (
            SELECT p.category, p.productName, count(i.orderID) AS times_ordered
            FROM products p
            LEFT JOIN order_items i ON i.productID = p.productID
            GROUP BY p.productID, p.category, p.productName
        )
        SELECT category, productName, times_ordered,
               row_number() OVER w AS row_number,
               rank()       OVER w AS rank,
               dense_rank() OVER w AS dense_rank
        FROM sold
        WHERE category IN ('Audio', 'Monitors', 'Phones', 'Storage')
        WINDOW w AS (PARTITION BY category ORDER BY times_ordered DESC)
        ORDER BY category, times_ordered DESC, productName
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    How many products does each version put on the "top 2" shelf?
    """)
    return


@app.cell
def _(engine, mo):
    p3_15 = mo.sql(
        f"""
        WITH sold AS (
            SELECT p.category, p.productName, count(i.orderID) AS times_ordered
            FROM products p
            LEFT JOIN order_items i ON i.productID = p.productID
            GROUP BY p.productID, p.category, p.productName
        ),
        ranked AS (
            SELECT category,
                   row_number() OVER w AS rn,
                   rank()       OVER w AS rnk,
                   dense_rank() OVER w AS drnk
            FROM sold
            WINDOW w AS (PARTITION BY category ORDER BY times_ordered DESC)
        )
        SELECT count(*) FILTER (WHERE rn   <= 2) AS by_row_number,
               count(*) FILTER (WHERE rnk  <= 2) AS by_rank,
               count(*) FILTER (WHERE drnk <= 2) AS by_dense_rank,
               count(DISTINCT category)          AS categories
        FROM ranked
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    13 categories, one of them (Chairs) with a single product: "exactly 2 per category" would be 25. row_number gives 25 — by dropping a tied product at random. rank gives 28: Monitors, Phones and Storage each have a tie for 2nd place. dense_rank gives 29: on top of those, Audio's two products tied at 28 are both "1st", so Flip 6 (27) is "2nd". dense_rank <= N answers "the top N DISTINCT VALUES", not "the top N products" — it can return more rows even with no tie at the cut.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 4 — Top-N per group

    "Each customer's latest order" — the last time we heard from them. The most common window question at work, and three ways to answer it.

    ### 4.1 The loud one: a window function in WHERE

    Number each customer's orders newest first, keep number 1: Error on purpose:
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
        _shown = mo.callout(mo.md("No error?! This query was supposed to fail."), kind="warn")
    except psycopg.Error as _e:
        _shown = mo.callout(mo.md(f"**ERROR:** `{_e.diag.message_primary}`"), kind="danger")
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Error on purpose — the function itself, not the alias:
    """)
    return


@app.cell
def _(engine, mo, psycopg):
    # Error on purpose -- shows PostgreSQL's message instead of stopping the notebook.
    try:
        engine.execute("""
        SELECT customerID, orderID, orderDate
        FROM orders
        WHERE row_number() OVER (PARTITION BY customerID
                                 ORDER BY orderDate DESC, orderTime DESC, orderID DESC) = 1
        """)
        _shown = mo.callout(mo.md("No error?! This query was supposed to fail."), kind="warn")
    except psycopg.Error as _e:
        _shown = mo.callout(mo.md(f"**ERROR:** `{_e.diag.message_primary}`"), kind="danger")
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Both errors are Part 2.5's picture: WHERE runs BEFORE window functions exist. (The first error is the same reason a SELECT alias can't be used in WHERE.) A loud error — the friendly kind.

    ### 4.2 Method 1: row_number() in a CTE, filter outside

    Lecture 5's CTE is the fix: compute the window in one step, filter in the next, where rn is an ordinary column.
    """)
    return


@app.cell
def _(engine, mo):
    p4_01 = mo.sql(
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
        ORDER BY customerID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    28 rows: one per customer WHO HAS ORDERS. Levon and Astghik have no rows in orders, so they have no partition at all.

    ### 4.3 Method 2: LEFT JOIN LATERAL ... LIMIT 1 (Lecture 5, 3.5)
    """)
    return


@app.cell
def _(engine, mo):
    p4_02 = mo.sql(
        f"""
        SELECT c.customerID, latest.orderID, latest.orderDate, latest.orderTime, latest.orderTotal
        FROM customers c
        LEFT JOIN LATERAL (SELECT o.orderID, o.orderDate, o.orderTime, o.orderTotal
                           FROM orders o
                           WHERE o.customerID = c.customerID
                           ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
                           LIMIT 1) AS latest ON true
        ORDER BY c.customerID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Row count check — predict it first: 30 customers in.
    """)
    return


@app.cell
def _(engine, mo):
    p4_03 = mo.sql(
        f"""
        SELECT count(*) AS rows, count(latest.orderID) AS with_an_order
        FROM customers c
        LEFT JOIN LATERAL (SELECT o.orderID
                           FROM orders o
                           WHERE o.customerID = c.customerID
                           ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
                           LIMIT 1) AS latest ON true
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The inner JOIN LATERAL drops the customers whose subquery returned nothing — silently, like any inner join (Lecture 4, 4.2):
    """)
    return


@app.cell
def _(engine, mo):
    p4_04 = mo.sql(
        f"""
        SELECT count(*) AS rows
        FROM customers c
        JOIN LATERAL (SELECT o.orderID
                      FROM orders o
                      WHERE o.customerID = c.customerID
                      ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
                      LIMIT 1) AS latest ON true
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG for this question: 30 customers in, 28 out. Levon and Astghik are gone, no error. For "when did we last hear from each customer?", the two who never ordered are exactly the ones you need to see. LEFT JOIN LATERAL keeps them.

    ### 4.4 Method 3: DISTINCT ON (PostgreSQL only)

    "Keep the first row of each customerID, in this ORDER BY."
    """)
    return


@app.cell
def _(engine, mo):
    p4_05 = mo.sql(
        f"""
        SELECT DISTINCT ON (customerID)
               customerID, orderID, orderDate, orderTime, orderTotal
        FROM orders
        ORDER BY customerID, orderDate DESC, orderTime DESC, orderID DESC
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Shortest of the three — and not standard SQL. MySQL, SQL Server and SQLite don't have it; the row_number() version works on all of them.

    Error on purpose: the ORDER BY must START with the DISTINCT ON columns.
    """)
    return


@app.cell
def _(engine, mo, psycopg):
    # Error on purpose -- shows PostgreSQL's message instead of stopping the notebook.
    try:
        engine.execute("""
        SELECT DISTINCT ON (customerID) customerID, orderID, orderDate
        FROM orders
        ORDER BY orderDate DESC
        """)
        _shown = mo.callout(mo.md("No error?! This query was supposed to fail."), kind="warn")
    except psycopg.Error as _e:
        _shown = mo.callout(mo.md(f"**ERROR:** `{_e.diag.message_primary}`"), kind="danger")
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The quiet version: the ORDER BY starts right, but says nothing about WHICH row of each customer comes first.
    """)
    return


@app.cell
def _(engine, mo):
    p4_06 = mo.sql(
        f"""
        SELECT DISTINCT ON (customerID) customerID, orderID, orderDate
        FROM orders
        ORDER BY customerID
        LIMIT 3
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG: "the first row of each customer" in no particular order. Compare with 4.4 above: customer 1's latest order is 1591 on 2024-12-27, not this one. No error.

    ### 4.5 Prove the three agree: EXCEPT both ways (Lecture 5, 6.5)

    For each pair of methods, rows in one but not the other. 0 rows in both directions = the same result. (LATERAL's inner join here, so all three cover the same 28 customers.)
    """)
    return


@app.cell
def _(engine, mo):
    p4_07 = mo.sql(
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
               (SELECT count(*) FROM (SELECT * FROM m3 EXCEPT SELECT * FROM m1) x) AS m3_not_m1
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ---- 4.6 THE TRAP: an incomplete ORDER BY — inside the window, the LATERAL subquery, or DISTINCT ON ---- "Latest order" = ORDER BY orderDate DESC, and nothing else. Two customers placed two orders on their last day: Anna Sargsyan (customer 1: orders 1589 and 1591 on 2024-12-27) and Armen Gevorgyan (customer 12: 1595 and 1596 on 2024-12-28).
    """)
    return


@app.cell
def _(engine, mo):
    p4_08 = mo.sql(
        f"""
        WITH m1 AS (
            SELECT customerID, orderID
            FROM (SELECT customerID, orderID,
                         row_number() OVER (PARTITION BY customerID ORDER BY orderDate DESC) AS rn
                  FROM orders) AS r
            WHERE rn = 1
        ),
        m2 AS (
            SELECT c.customerID, l.orderID
            FROM customers c
            JOIN LATERAL (SELECT o.orderID FROM orders o
                          WHERE o.customerID = c.customerID
                          ORDER BY o.orderDate DESC
                          LIMIT 1) AS l ON true
        ),
        m3 AS (
            SELECT DISTINCT ON (customerID) customerID, orderID
            FROM orders
            ORDER BY customerID, orderDate DESC
        )
        SELECT 'row_number' AS method, customerID, orderID FROM m1 WHERE customerID IN (1, 12)
        UNION ALL
        SELECT 'lateral',              customerID, orderID FROM m2 WHERE customerID IN (1, 12)
        UNION ALL
        SELECT 'distinct on',          customerID, orderID FROM m3 WHERE customerID IN (1, 12)
        ORDER BY customerID, method
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG, in two different ways:

    - Anna: the methods DISAGREE (1589 vs 1591) -- an EXCEPT check between them would catch it.

    - Armen: all three AGREE on 1595 -- and all three are wrong. His latest order is 1596 (14:28, after 1595 at 12:06). An EXCEPT check says "0 rows, identical". Agreement only proves something when each method's question has exactly one answer. The fix is 4.2-4.4: orderDate DESC, orderTime DESC, orderID DESC -- complete, so the last key is unique.

    ### 4.7 Top 2, not top 1

    DISTINCT ON can only keep ONE row per group. The other two methods just change a number. "Each customer's two most recent orders":
    """)
    return


@app.cell
def _(engine, mo):
    p4_09 = mo.sql(
        f"""
        WITH ranked AS (
            SELECT customerID, orderID,
                   row_number() OVER (PARTITION BY customerID
                                      ORDER BY orderDate DESC, orderTime DESC, orderID DESC) AS rn
            FROM orders
        )
        SELECT count(*) AS rows, count(DISTINCT customerID) AS customers
        FROM ranked
        WHERE rn <= 2
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Predict: every customer who ordered has at least 4 orders (Diana), so 28 x 2 = 56.
    """)
    return


@app.cell
def _(engine, mo):
    p4_10 = mo.sql(
        f"""
        SELECT count(*) AS rows, count(l.orderID) AS order_rows
        FROM customers c
        LEFT JOIN LATERAL (SELECT o.orderID FROM orders o
                           WHERE o.customerID = c.customerID
                           ORDER BY o.orderDate DESC, o.orderTime DESC, o.orderID DESC
                           LIMIT 2) AS l ON true
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    56 order rows + 2 NULL-padded rows for Levon and Astghik = 58.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 5 — Looking sideways -- lag, lead, first_value, nth_value

    Functions that read a value from ANOTHER row of the window. (last_value has a trap of its own — Part 6.)

    ### 5.1 Order over order: lag

    Lusine's completed orders, each next to the one before it.

    > **New function: `lag(x)`** — the value of x from the PREVIOUS row of the window, in its ORDER BY. NULL when there is no previous row.
    """)
    return


@app.cell
def _(engine, mo):
    p5_01 = mo.sql(
        f"""
        SELECT orderID, orderDate, orderTotal,
               lag(orderTotal) OVER w                AS previous_order,
               orderTotal - lag(orderTotal) OVER w   AS change
        FROM orders
        WHERE status = 'completed' AND customerID = 5
        WINDOW w AS (PARTITION BY customerID ORDER BY orderDate, orderTime, orderID)
        ORDER BY orderDate
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The first row of every partition has no previous row: lag gives NULL, and so does the change. That NULL is honest — "there was nothing to compare with."

    #### Real problem: customers who went quiet

    **Task:** customer service wants every time a customer went more than 90 days without ordering, and came back — who, the gap, and when they returned.

    **Solution:** lag(orderDate) per customer gives the previous order's date; subtracting gives the gap in days. Keep the gaps over 90.
    """)
    return


@app.cell
def _(engine, mo):
    p5_02 = mo.sql(
        f"""
        WITH gaps AS (
            SELECT c.firstName, c.lastName, o.orderDate AS came_back_on,
                   lag(o.orderDate) OVER w              AS previous_order,
                   o.orderDate - lag(o.orderDate) OVER w AS days_quiet
            FROM orders o
            JOIN customers c ON c.customerID = o.customerID
            WINDOW w AS (PARTITION BY o.customerID ORDER BY o.orderDate, o.orderTime, o.orderID)
        )
        SELECT firstName, lastName, previous_order, came_back_on, days_quiet
        FROM gaps
        WHERE days_quiet > 90
        ORDER BY days_quiet DESC
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Reading the result:** 7 quiet periods, 5 customers — Lusine and Diana twice each. The longest is Lusine's 148 days (5.4 below shows it from the other side, with lead). Each customer's first order has no gap (lag is NULL), so it can't be counted by mistake.

    ### 5.2 The default argument, and when it lies

    > **New function: `lag(x, n, d)`** — the value of x from n rows back. When there is no such row, d instead of NULL.

    lag(x, 1, 0) fills the gap with 0. Looks tidier:
    """)
    return


@app.cell
def _(engine, mo):
    p5_03 = mo.sql(
        f"""
        SELECT orderID, orderDate, orderTotal,
               lag(orderTotal, 1, 0) OVER w                AS previous_order,
               orderTotal - lag(orderTotal, 1, 0) OVER w   AS change
        FROM orders
        WHERE status = 'completed' AND customerID = 5
        WINDOW w AS (PARTITION BY customerID ORDER BY orderDate, orderTime, orderID)
        ORDER BY orderDate
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG: Lusine's first order is now a "jump" of +1598.00 — from an order that never existed.

    Across all customers: "how much does an order change from the one before, on average?"
    """)
    return


@app.cell
def _(engine, mo):
    p5_04 = mo.sql(
        f"""
        SELECT round(avg(change_null), 2)  AS avg_change_null,
               count(change_null)          AS changes_null,
               round(avg(change_zero), 2)  AS avg_change_zero,
               count(change_zero)          AS changes_zero
        FROM (SELECT orderTotal - lag(orderTotal)       OVER w AS change_null,
                     orderTotal - lag(orderTotal, 1, 0) OVER w AS change_zero
              FROM orders
              WHERE status = 'completed'
              WINDOW w AS (PARTITION BY customerID ORDER BY orderDate, orderTime, orderID)) AS x
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG with the default: 17.23 instead of 1.42 — twelve times the real figure. 529 completed orders, 28 customers: 501 real changes, plus 28 fake ones (every customer's first order counted as growth from 0). avg skips NULLs, so the honest NULL kept them out; the 0 put them in. A default is right only when it is TRUE ("no previous order" = 0 previous orders). For "previous amount" it isn't.

    ### 5.3 THE TRAP: lag gives the previous ROW, not the previous MONTH

    "Each salesperson's completed revenue per month, and the change from the month before."
    """)
    return


@app.cell
def _(engine, mo):
    p5_05 = mo.sql(
        f"""
        WITH monthly AS (
            SELECT employeeID,
                   extract(month FROM orderDate)::int AS month,
                   sum(orderTotal) AS revenue
            FROM orders
            WHERE status = 'completed' AND employeeID IS NOT NULL
            GROUP BY employeeID, extract(month FROM orderDate)
        )
        SELECT employeeID, month, revenue,
               lag(revenue) OVER (PARTITION BY employeeID ORDER BY month) AS prev_month,
               revenue - lag(revenue) OVER (PARTITION BY employeeID ORDER BY month) AS change
        FROM monthly
        WHERE employeeID = 4
        ORDER BY month
        LIMIT 4
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG: Nare (employee 4) sold nothing in February — there is no February row. So March's "prev_month" is JANUARY's revenue, and February's drop to 0 doesn't appear at all. A plausible table, no error.

    How many rows of the full report compare with the wrong month? lag the month number too, and count the rows where it isn't month - 1.
    """)
    return


@app.cell
def _(engine, mo):
    p5_06 = mo.sql(
        f"""
        WITH monthly AS (
            SELECT employeeID,
                   extract(month FROM orderDate)::int AS month,
                   sum(orderTotal) AS revenue
            FROM orders
            WHERE status = 'completed' AND employeeID IS NOT NULL
            GROUP BY employeeID, extract(month FROM orderDate)
        ),
        compared AS (
            SELECT employeeID, month,
                   lag(month) OVER (PARTITION BY employeeID ORDER BY month) AS compared_with
            FROM monthly
        )
        SELECT count(*) AS report_rows,
               count(*) FILTER (WHERE compared_with <> month - 1) AS wrong_month,
               12 * 8 - count(*) AS months_missing
        FROM compared
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    88 rows instead of 8 x 12 = 96: 8 salesperson-months had no completed order and simply aren't there, and 7 rows silently compare with the month two months back (Vahe's November, Nare's March, Lilit's April, Arman's July and September, Marine's March and October). Nothing in the output marks them.

    FIX: build the complete calendar first — every employee x every month — then LEFT JOIN the sales to it (Lecture 4: the side you must not lose goes on the left). Missing months become real rows with 0.
    """)
    return


@app.cell
def _(engine, mo):
    p5_07 = mo.sql(
        f"""
        WITH monthly AS (
            SELECT employeeID,
                   extract(month FROM orderDate)::int AS month,
                   sum(orderTotal) AS revenue
            FROM orders
            WHERE status = 'completed' AND employeeID IS NOT NULL
            GROUP BY employeeID, extract(month FROM orderDate)
        ),
        calendar AS (
            SELECT e.employeeID, m.month
            FROM employees e
            CROSS JOIN (SELECT DISTINCT month FROM dim_date) AS m
        ),
        full_months AS (
            SELECT cal.employeeID, cal.month, coalesce(mo.revenue, 0) AS revenue
            FROM calendar cal
            LEFT JOIN monthly mo ON mo.employeeID = cal.employeeID AND mo.month = cal.month
        )
        SELECT employeeID, month, revenue,
               lag(revenue) OVER (PARTITION BY employeeID ORDER BY month) AS prev_month,
               revenue - lag(revenue) OVER (PARTITION BY employeeID ORDER BY month) AS change
        FROM full_months
        WHERE employeeID = 4
        ORDER BY month
        LIMIT 4
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    February is back with 0, and March is compared with February. Here 0 IS the truth ("sold nothing that month"), unlike 5.2's fake 0.

    Check the fixed report: 96 rows, and the zeros added nothing — its total is still the in-store completed revenue.
    """)
    return


@app.cell
def _(engine, mo):
    p5_08 = mo.sql(
        f"""
        WITH monthly AS (
            SELECT employeeID,
                   extract(month FROM orderDate)::int AS month,
                   sum(orderTotal) AS revenue
            FROM orders
            WHERE status = 'completed' AND employeeID IS NOT NULL
            GROUP BY employeeID, extract(month FROM orderDate)
        ),
        calendar AS (
            SELECT e.employeeID, m.month
            FROM employees e
            CROSS JOIN (SELECT DISTINCT month FROM dim_date) AS m
        )
        SELECT count(*) AS report_rows, sum(coalesce(mo.revenue, 0)) AS total
        FROM calendar cal
        LEFT JOIN monthly mo ON mo.employeeID = cal.employeeID AND mo.month = cal.month
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    p5_09 = mo.sql(
        f"""
        SELECT sum(orderTotal) AS in_store_completed
        FROM orders
        WHERE status = 'completed' AND employeeID IS NOT NULL
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    100,222.48 — the number Lecture 4's inner join gave for "completed revenue" (4.2): the online orders are left out on purpose this time.

    ### 5.4 lead: looking forward

    Days from each of Lusine's orders to her next one (any status).

    > **New function: `lead(x)`** — the same as lag, looking forward: x from the NEXT row of the window. Also takes n and a default.
    """)
    return


@app.cell
def _(engine, mo):
    p5_10 = mo.sql(
        f"""
        SELECT orderID, orderDate, status,
               lead(orderDate) OVER w             AS next_order,
               lead(orderDate) OVER w - orderDate AS days_to_next
        FROM orders
        WHERE customerID = 5
        WINDOW w AS (PARTITION BY customerID ORDER BY orderDate, orderTime, orderID)
        ORDER BY orderDate
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The LAST row gets NULL from lead — no next order (yet).

    #### Real problem: did customers come back after a return?

    **Task:** after a customer returns an order, do they order again? For all returned orders: how many were followed by another order, after how many days on average, and who has not ordered since?

    **Solution:** lead() over each customer's orders gives the next order's date; then look only at the rows that are returns.
    """)
    return


@app.cell
def _(engine, mo):
    p5_11 = mo.sql(
        f"""
        WITH next_orders AS (
            SELECT o.customerID, o.orderID, o.orderDate, o.status,
                   lead(o.orderDate) OVER (PARTITION BY o.customerID
                                           ORDER BY o.orderDate, o.orderTime, o.orderID) AS next_order
            FROM orders o
        )
        SELECT count(*)                              AS returns,
               count(next_order)                     AS followed_by_an_order,
               round(avg(next_order - orderDate), 1) AS avg_days_to_next
        FROM next_orders
        WHERE status = 'returned'
        """,
        engine=engine
    )
    return


@app.cell
def _(engine, mo):
    p5_12 = mo.sql(
        f"""
        WITH next_orders AS (
            SELECT o.customerID, o.orderID, o.orderDate, o.status,
                   lead(o.orderDate) OVER (PARTITION BY o.customerID
                                           ORDER BY o.orderDate, o.orderTime, o.orderID) AS next_order
            FROM orders o
        )
        SELECT c.firstName, c.lastName, n.orderID, n.orderDate AS returned_order_date
        FROM next_orders n
        JOIN customers c ON c.customerID = n.customerID
        WHERE n.status = 'returned' AND n.next_order IS NULL
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Reading the result:** 42 of 44 returns were followed by another order, after 22 days on average. The other two, Vahan and Karen, returned orders on 2024-12-27 — and the data ends on 2024-12-31. "No next order" means "not yet", not "lost". Check the dates before you call a NULL from lead a lost customer.

    ### 5.5 first_value and nth_value

    Each of Lusine's completed orders next to her FIRST completed order and her SECOND one.

    > **New function: `first_value(x)`** — the value of x on the first row of the window frame.

    > **New function: `nth_value(x, n)`** — the value of x on the n-th row of the window frame; NULL if the frame has fewer than n rows so far.
    """)
    return


@app.cell
def _(engine, mo):
    p5_13 = mo.sql(
        f"""
        SELECT orderID, orderDate, orderTotal,
               first_value(orderTotal) OVER w  AS first_order,
               nth_value(orderTotal, 2) OVER w AS second_order
        FROM orders
        WHERE status = 'completed' AND customerID = 5
        WINDOW w AS (PARTITION BY customerID ORDER BY orderDate, orderTime, orderID)
        ORDER BY orderDate
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    first_value is the same on every row. But second_order is NULL on the first row — even though the second order exists. These functions see only the window FRAME, and by default the frame ends at the current row: on row 1, there is no row 2 yet. That default is the subject of Part 6.

    #### Real problem: which channel brings better customers?

    **Task:** marketing pays for in-store promotions and for online ads. Do customers whose FIRST order was online turn out more or less valuable than customers who first bought in a store?

    **Solution:** first_value(channel) per customer gives the channel of their first order (their "acquisition channel"); then group by it.
    """)
    return


@app.cell
def _(engine, mo):
    p5_14 = mo.sql(
        f"""
        WITH acquired AS (
            SELECT customerID, status, orderTotal,
                   first_value(channel) OVER (PARTITION BY customerID
                                              ORDER BY orderDate, orderTime, orderID) AS first_channel
            FROM orders
        )
        SELECT first_channel,
               count(DISTINCT customerID) AS customers,
               sum(orderTotal) FILTER (WHERE status = 'completed') AS revenue,
               round(sum(orderTotal) FILTER (WHERE status = 'completed')
                     / count(DISTINCT customerID), 2) AS revenue_per_customer
        FROM acquired
        GROUP BY first_channel
        ORDER BY first_channel
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Reading the result:** 16 customers came in through a store, 12 online. Store-acquired customers spent 5,841.17 each, online-acquired 5,301.64 — about 9% less, on 28 customers in total. A hint, not a proof. (first_value is safe with the default frame: the frame always starts at the first row. last_value is not — Part 6.4.)
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 6 — Frames

    The FRAME is the part of the partition that the function sees for the current row. It moves as the current row moves.

    ```
      ROWS   BETWEEN 2 PRECEDING AND CURRENT ROW     count physical rows
      RANGE  BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                                                     by VALUE of the ORDER BY:
                                                     rows with an equal value
                                                     ("peers") are all in or all out
      GROUPS BETWEEN 1 PRECEDING AND CURRENT ROW     count groups of peers (PG 11+)
    ```

    start/end: UNBOUNDED PRECEDING, n PRECEDING, CURRENT ROW, n FOLLOWING, UNBOUNDED FOLLOWING

    THE DEFAULTS (this is the whole part):

    ```
      no ORDER BY in OVER  -> the frame is the whole partition
      ORDER BY in OVER     -> RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ```

    ### 6.1 No ORDER BY vs ORDER BY: the frame changes
    """)
    return


@app.cell
def _(engine, mo):
    p6_01 = mo.sql(
        f"""
        SELECT orderID, orderDate, orderTotal,
               sum(orderTotal) OVER (PARTITION BY customerID)                     AS whole_partition,
               sum(orderTotal) OVER (PARTITION BY customerID
                                     ORDER BY orderDate, orderTime, orderID)      AS up_to_this_row
        FROM orders
        WHERE status = 'completed' AND customerID = 5
        ORDER BY orderDate
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Same function, same partition. Adding ORDER BY quietly changed the frame from "all of Lusine's orders" to "her orders up to this one".

    ### 6.2 A running total for the year
    """)
    return


@app.cell
def _(engine, mo):
    p6_02 = mo.sql(
        f"""
        SELECT orderID, orderDate, orderTotal,
               sum(orderTotal) OVER (ORDER BY orderDate) AS running_total
        FROM orders
        WHERE status = 'completed'
        ORDER BY orderDate, orderID
        LIMIT 8
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG (look closely): orders 1002 and 1003 show the SAME running total, 1207.65 — and so do 1004/1005 and 1007/1008. Order 1002's total is already counting 1003's 747.00. The default frame is RANGE ... CURRENT ROW, and RANGE includes every PEER of the current row: every order with the same orderDate. The figure looks stalled or duplicated.

    How much of the column is affected?
    """)
    return


@app.cell
def _(engine, mo):
    p6_03 = mo.sql(
        f"""
        SELECT count(*)                     AS rows,
               count(DISTINCT running_total) AS different_running_totals,
               count(DISTINCT orderDate)     AS order_dates
        FROM (SELECT orderDate,
                     sum(orderTotal) OVER (ORDER BY orderDate) AS running_total
              FROM orders
              WHERE status = 'completed') AS w
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    529 rows, 250 different values: one running total per DATE, not per order. 279 rows repeat a neighbour's figure.

    FIX: say ROWS, and make the order unique with a tie-breaker.
    """)
    return


@app.cell
def _(engine, mo):
    p6_04 = mo.sql(
        f"""
        SELECT orderID, orderDate, orderTotal,
               sum(orderTotal) OVER (ORDER BY orderDate, orderID
                                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total
        FROM orders
        WHERE status = 'completed'
        ORDER BY orderDate, orderID
        LIMIT 8
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The rule: if you mean "running", write ROWS — don't rely on the default. (ROWS without a tie-breaker would number the tied rows in an arbitrary order: Part 3.3 again.)

    ### 6.3 Verification: where must a running total end?

    Check 1 — the last running total is the grand total. Both versions pass this check (at the last date, all peers are in), which is why it can't be the only check.
    """)
    return


@app.cell
def _(engine, mo):
    p6_05 = mo.sql(
        f"""
        SELECT max(range_total) AS range_ends_at,
               max(rows_total)  AS rows_ends_at,
               (SELECT sum(orderTotal) FROM orders WHERE status = 'completed') AS completed_revenue
        FROM (SELECT sum(orderTotal) OVER (ORDER BY orderDate) AS range_total,
                     sum(orderTotal) OVER (ORDER BY orderDate, orderID
                                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS rows_total
              FROM orders
              WHERE status = 'completed') AS w
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Check 2 — per partition: each customer's LAST running total must equal that customer's plain sum. Count the customers where it doesn't.
    """)
    return


@app.cell
def _(engine, mo):
    p6_06 = mo.sql(
        f"""
        WITH running AS (
            SELECT customerID, orderTotal,
                   sum(orderTotal) OVER (PARTITION BY customerID
                                         ORDER BY orderDate, orderTime, orderID
                                         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total,
                   row_number() OVER (PARTITION BY customerID
                                      ORDER BY orderDate DESC, orderTime DESC, orderID DESC) AS from_the_end
            FROM orders
            WHERE status = 'completed'
        )
        SELECT count(*) AS customers,
               count(*) FILTER (WHERE r.running_total <> t.total) AS mismatches,
               sum(r.running_total) AS sum_of_last_running_totals
        FROM running r
        JOIN (SELECT customerID, sum(orderTotal) AS total
              FROM orders WHERE status = 'completed'
              GROUP BY customerID) AS t ON t.customerID = r.customerID
        WHERE r.from_the_end = 1
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    28 customers, 0 mismatches, and the 28 end points add up to the completed revenue.

    Check 3 — the one that catches RANGE: a running total of positive amounts must change on EVERY row. Count the rows where it didn't.
    """)
    return


@app.cell
def _(engine, mo):
    p6_07 = mo.sql(
        f"""
        SELECT count(*) FILTER (WHERE range_total = prev_range) AS stalled_range,
               count(*) FILTER (WHERE rows_total  = prev_rows)  AS stalled_rows
        FROM (SELECT range_total, rows_total,
                     lag(range_total) OVER (ORDER BY orderDate, orderID) AS prev_range,
                     lag(rows_total)  OVER (ORDER BY orderDate, orderID) AS prev_rows
              FROM (SELECT orderID, orderDate,
                           sum(orderTotal) OVER (ORDER BY orderDate) AS range_total,
                           sum(orderTotal) OVER (ORDER BY orderDate, orderID
                                                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS rows_total
                    FROM orders
                    WHERE status = 'completed') AS running) AS compared
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    279 = 529 rows - 250 dates: every row that shares a date with an earlier row "stalls". With ROWS: 0.

    ### 6.4 THE TRAP: last_value with the default frame

    "Each order next to the customer's LATEST order total" — first_value worked in 5.5, so last_value should too:

    > **New function: `last_value(x)`** — the value of x on the last row of the window frame. With the default frame, that is the current row — the trap below.
    """)
    return


@app.cell
def _(engine, mo):
    p6_08 = mo.sql(
        f"""
        SELECT orderID, orderDate, orderTotal,
               first_value(orderTotal) OVER w AS first_order,
               last_value(orderTotal)  OVER w AS latest_order
        FROM orders
        WHERE status = 'completed' AND customerID = 5
        WINDOW w AS (PARTITION BY customerID ORDER BY orderDate, orderTime, orderID)
        ORDER BY orderDate
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG: latest_order is just orderTotal again, on every row. The default frame ends at the CURRENT ROW, so the last row of the frame IS the current row. first_value worked only because the frame starts at the top. A plausible column, no error.

    FIX: extend the frame to the end of the partition.
    """)
    return


@app.cell
def _(engine, mo):
    p6_09 = mo.sql(
        f"""
        SELECT orderID, orderDate, orderTotal,
               first_value(orderTotal) OVER w AS first_order,
               last_value(orderTotal)  OVER w AS latest_order
        FROM orders
        WHERE status = 'completed' AND customerID = 5
        WINDOW w AS (PARTITION BY customerID ORDER BY orderDate, orderTime, orderID
                     ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
        ORDER BY orderDate
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    (Or: first_value with ORDER BY ... DESC — "the first of the newest".)

    **Every kind of frame, on one customer.** Lusine has only 4 orders -- too few to see frames differ. Mher Sargsyan (customer 30) has 8 completed orders, and two of them on the same day (14 November). We number his orders 1-8 (rn) and, for every row, show WHICH rows each frame contains.

    > **New function: `string_agg(x, ',')`** — joins the values of x from all the rows it sees (here: the rows of the frame) into one text, separated by ','. The order inside the list is not guaranteed: read it as a set of rows.

    **Query 1: the ROWS frames — counted in rows.**
    """)
    return


@app.cell
def _(engine, mo):
    p6_10 = mo.sql(
        f"""
        WITH mher AS (
            SELECT orderDate, orderTotal,
                   row_number() OVER (ORDER BY orderDate, orderTime, orderID) AS rn
            FROM orders
            WHERE status = 'completed' AND customerID = 30
        )
        SELECT rn, orderDate, orderTotal,
               string_agg(rn::text, ',') OVER (ORDER BY rn)                                                         AS default_frame,
               string_agg(rn::text, ',') OVER (ORDER BY rn ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING)                AS rows_2p_1p,
               string_agg(rn::text, ',') OVER (ORDER BY rn ROWS BETWEEN 1 PRECEDING AND CURRENT ROW)                AS rows_1p_cur,
               string_agg(rn::text, ',') OVER (ORDER BY rn ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING)                AS rows_1p_1f,
               string_agg(rn::text, ',') OVER (ORDER BY rn ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)        AS rows_cur_unb,
               string_agg(rn::text, ',') OVER (ORDER BY rn ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS rows_all,
               string_agg(rn::text, ',') OVER ()                                                                    AS no_order_by
        FROM mher
        ORDER BY rn
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    | Column | Frame | In words | Row 4 sees |
    |---|---|---|---|
    | `default_frame` | ORDER BY, no frame written | from the start up to this row (rn has no ties, so the default RANGE acts like ROWS) | 1,2,3,4 |
    | `rows_2p_1p` | `ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING` | the two rows before, NOT this one | 2,3 |
    | `rows_1p_cur` | `ROWS BETWEEN 1 PRECEDING AND CURRENT ROW` | the row before, and this one | 3,4 |
    | `rows_1p_1f` | `ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING` | one row either side | 3,4,5 |
    | `rows_cur_unb` | `ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING` | this row to the end | 4,5,6,7,8 |
    | `rows_all` | `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING` | the whole partition | 1-8 |
    | `no_order_by` | `OVER ()` | the whole partition: no order, no frame | 1-8 |

    Look at the edges: on row 1, `rows_2p_1p` is empty (NULL — there are no rows before it), and `rows_1p_1f` is just 1,2. A frame never reaches outside the partition; it simply gets shorter.

    **Query 2: RANGE, GROUPS and EXCLUDE — what happens with ties.** Now the window is ordered by orderDate only, so rows 4 and 5 (both 14 November) are peers. rows_1p is there for comparison.
    """)
    return


@app.cell
def _(engine, mo):
    p6_11 = mo.sql(
        f"""
        WITH mher AS (
            SELECT orderDate, orderTotal,
                   row_number() OVER (ORDER BY orderDate, orderTime, orderID) AS rn
            FROM orders
            WHERE status = 'completed' AND customerID = 30
        )
        SELECT rn, orderDate,
               string_agg(rn::text, ',') OVER (ORDER BY rn        ROWS   BETWEEN 1 PRECEDING AND CURRENT ROW) AS rows_1p,
               string_agg(rn::text, ',') OVER (ORDER BY orderDate GROUPS BETWEEN 1 PRECEDING AND CURRENT ROW) AS groups_1p,
               string_agg(rn::text, ',') OVER (ORDER BY orderDate)                                            AS range_default,
               string_agg(rn::text, ',') OVER (ORDER BY orderDate RANGE BETWEEN INTERVAL '30 days' PRECEDING AND CURRENT ROW) AS range_30_days,
               string_agg(rn::text, ',') OVER (ORDER BY orderDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
                                               EXCLUDE CURRENT ROW) AS excl_current_row,
               string_agg(rn::text, ',') OVER (ORDER BY orderDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
                                               EXCLUDE GROUP)       AS excl_group,
               string_agg(rn::text, ',') OVER (ORDER BY orderDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
                                               EXCLUDE TIES)        AS excl_ties
        FROM mher
        ORDER BY rn
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    | Column | Frame | In words | Row 4 sees | Row 5 sees |
    |---|---|---|---|---|
    | `rows_1p` | `ROWS BETWEEN 1 PRECEDING AND CURRENT ROW` | 1 row back, by position | 3,4 | 4,5 |
    | `groups_1p` | `GROUPS BETWEEN 1 PRECEDING AND CURRENT ROW` | this DATE and the previous date that has orders | 3,4,5 | 3,4,5 |
    | `range_default` | ORDER BY orderDate, no frame | up to this row AND its peers | 1-5 | 1-5 |
    | `range_30_days` | `RANGE BETWEEN INTERVAL '30 days' PRECEDING AND CURRENT ROW` | orders in the 30 days up to this date | 4,5 | 4,5 |
    | `excl_current_row` | whole partition, `EXCLUDE CURRENT ROW` | everyone except this row | all but 4 | all but 5 |
    | `excl_group` | whole partition, `EXCLUDE GROUP` | everyone except this row and its peers | 1,2,3,6,7,8 | 1,2,3,6,7,8 |
    | `excl_ties` | whole partition, `EXCLUDE TIES` | everyone except the peers, but keep this row | all but 5 | all but 4 |

    Rows 4 and 5 are where the modes split: ROWS treats them as two different positions, while GROUPS and RANGE treat them as one date. range_30_days on row 4 drops row 3 (4 October is 41 days earlier), and on row 8 (21 December) it reaches back to 21 November: rows 6,7,8. (EXCLUDE NO OTHERS, the default, excludes nothing.) GROUPS, RANGE with an offset and EXCLUDE need PostgreSQL 11 or later.

    **Query 3: first_value and last_value under three frames.** The functions from the fix above, on Mher's orders. Two named windows build on the first one: `(w_default ROWS ...)` means "w_default, plus this frame".
    """)
    return


@app.cell
def _(engine, mo):
    p6_12 = mo.sql(
        f"""
        SELECT orderID, orderDate, orderTotal,
               first_value(orderTotal) OVER w_default AS first_default,
               last_value(orderTotal)  OVER w_default AS last_default,
               first_value(orderTotal) OVER w_near    AS first_near,
               last_value(orderTotal)  OVER w_near    AS last_near,
               first_value(orderTotal) OVER w_all     AS first_all,
               last_value(orderTotal)  OVER w_all     AS last_all
        FROM orders
        WHERE status = 'completed' AND customerID = 30
        WINDOW w_default AS (PARTITION BY customerID ORDER BY orderDate, orderTime, orderID),
               w_near    AS (w_default ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING),
               w_all     AS (w_default ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
        ORDER BY orderDate, orderTime
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    | Frame | first_value | last_value |
    |---|---|---|
    | default (start to this row) | 38.80 on every row: the frame always starts at the first order | this row's own total: the frame ends here — the trap |
    | 1 row either side | the PREVIOUS order's total (on the first row: its own) | the NEXT order's total (on the last row: its own) |
    | the whole partition | 38.80, the first order | 498.00, the latest order — the right answer |

    The middle frame turns first_value and last_value into a lag and a lead that never return NULL: at the edges the frame just shrinks, so the "previous" of the first order is the order itself.

    Across all customers: on how many rows is the default last_value simply the row's own value?
    """)
    return


@app.cell
def _(engine, mo):
    p6_13 = mo.sql(
        f"""
        SELECT count(*) AS rows,
               count(*) FILTER (WHERE wrong_latest = orderTotal) AS equals_own_value
        FROM (SELECT orderTotal,
                     last_value(orderTotal) OVER (PARTITION BY customerID
                                                  ORDER BY orderDate, orderTime, orderID) AS wrong_latest
              FROM orders
              WHERE status = 'completed') AS w
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    #### Real problem: is each customer's latest order bigger than their first?

    **Task:** are customers trading up (spending more per order over time) or down? Compare each customer's first and latest completed order.

    **Solution:** first_value and last_value over the FULL partition (the fixed frame above), one row per customer with DISTINCT, then count.
    """)
    return


@app.cell
def _(engine, mo):
    p6_14 = mo.sql(
        f"""
        WITH first_and_last AS (
            SELECT DISTINCT customerID,
                   first_value(orderTotal) OVER w AS first_order,
                   last_value(orderTotal)  OVER w AS latest_order
            FROM orders
            WHERE status = 'completed'
            WINDOW w AS (PARTITION BY customerID ORDER BY orderDate, orderTime, orderID
                         ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
        )
        SELECT count(*)                                         AS customers,
               count(*) FILTER (WHERE latest_order > first_order) AS traded_up,
               count(*) FILTER (WHERE latest_order < first_order) AS traded_down
        FROM first_and_last
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Reading the result:** 28 customers: 16 traded up, 12 traded down. With the DEFAULT frame, last_value changes on every row, so DISTINCT can't collapse a customer to one row: the same query then reports 510 "customers", 274 trading up and 208 down — the trap above, inside a real report. Rows in = 28 customers out is the check.

    ### 6.5 Moving averages, and THE TRAP at the edges

    Completed revenue per month, with a 3-month moving average.
    """)
    return


@app.cell
def _(engine, mo):
    p6_15 = mo.sql(
        f"""
        WITH monthly AS (
            SELECT d.month, sum(f.revenue) AS revenue
            FROM fact_sales f
            JOIN dim_date d ON d.dateKey = f.dateKey
            WHERE f.status = 'completed'
            GROUP BY d.month
        )
        SELECT month, revenue,
               round(avg(revenue) OVER (ORDER BY month
                                        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS moving_avg_3
        FROM monthly
        ORDER BY month
        LIMIT 4
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG at the start: January's "3-month average" is January alone, February's is two months. The column header promises 3 months; the first two rows silently use fewer. Plotted, they look like any other point.

    FIX: count the rows in the same frame, and refuse to average fewer than 3 (or show the count, and let the reader decide).
    """)
    return


@app.cell
def _(engine, mo):
    p6_16 = mo.sql(
        f"""
        WITH monthly AS (
            SELECT d.month, sum(f.revenue) AS revenue
            FROM fact_sales f
            JOIN dim_date d ON d.dateKey = f.dateKey
            WHERE f.status = 'completed'
            GROUP BY d.month
        )
        SELECT month, revenue,
               count(*) OVER w AS months_in_frame,
               CASE WHEN count(*) OVER w = 3
                    THEN round(avg(revenue) OVER w, 2) END AS moving_avg_3
        FROM monthly
        WINDOW w AS (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
        ORDER BY month
        LIMIT 4
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 6.6 ROWS vs RANGE with an offset: "the last 7 days"

    Daily completed revenue. Orders happened on 250 of the 366 days, so "the previous 6 ROWS" is not "the previous 6 DAYS".
    """)
    return


@app.cell
def _(engine, mo):
    p6_17 = mo.sql(
        f"""
        WITH daily AS (
            SELECT orderDate, sum(orderTotal) AS revenue
            FROM orders
            WHERE status = 'completed'
            GROUP BY orderDate
        )
        SELECT orderDate, revenue,
               sum(revenue) OVER (ORDER BY orderDate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS last_7_rows,
               sum(revenue) OVER (ORDER BY orderDate
                                  RANGE BETWEEN INTERVAL '6 days' PRECEDING AND CURRENT ROW) AS last_7_days
        FROM daily
        ORDER BY orderDate
        LIMIT 10
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG for "the last 7 days" (last_7_rows): from January 8th on, the two columns disagree: 7 rows reach back further than 7 days, because the days with no orders have no rows. Part 5.3's trap in frame form. RANGE with an offset measures distance in the ORDER BY's own unit (here: days).

    How many of the 250 days get a different answer?
    """)
    return


@app.cell
def _(engine, mo):
    p6_18 = mo.sql(
        f"""
        WITH daily AS (
            SELECT orderDate, sum(orderTotal) AS revenue
            FROM orders
            WHERE status = 'completed'
            GROUP BY orderDate
        )
        SELECT count(*) AS days,
               count(*) FILTER (WHERE last_7_rows <> last_7_days) AS different
        FROM (SELECT sum(revenue) OVER (ORDER BY orderDate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS last_7_rows,
                     sum(revenue) OVER (ORDER BY orderDate
                                        RANGE BETWEEN INTERVAL '6 days' PRECEDING AND CURRENT ROW) AS last_7_days
              FROM daily) AS w
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    #### Real problem: the best week of the year

    **Task:** which 7-day period brought in the most completed revenue?

    **Solution:** daily revenue, then a 7-day window measured in DAYS (RANGE with an interval — not 7 rows, see above), then the top 3.
    """)
    return


@app.cell
def _(engine, mo):
    p6_19 = mo.sql(
        f"""
        WITH daily AS (
            SELECT orderDate, sum(orderTotal) AS revenue
            FROM orders
            WHERE status = 'completed'
            GROUP BY orderDate
        ),
        weekly AS (
            SELECT orderDate,
                   sum(revenue) OVER (ORDER BY orderDate
                                      RANGE BETWEEN INTERVAL '6 days' PRECEDING AND CURRENT ROW) AS last_7_days
            FROM daily
        )
        SELECT orderDate - 6 AS week_from, orderDate AS week_to, last_7_days
        FROM weekly
        ORDER BY last_7_days DESC
        LIMIT 3
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Reading the result:** 5-11 December, 9,678.12 — the run-up to the holidays. All three top windows are in December (they overlap: there is one 7-day window ending on each date).

    ### 6.7 GROUPS: count peer groups, not rows

    "Revenue on this order date and on the previous date that had orders" — per ORDER, without first collapsing to days.
    """)
    return


@app.cell
def _(engine, mo):
    p6_20 = mo.sql(
        f"""
        SELECT orderID, orderDate, orderTotal,
               sum(orderTotal) OVER (ORDER BY orderDate
                                     GROUPS BETWEEN 1 PRECEDING AND CURRENT ROW) AS this_and_previous_date
        FROM orders
        WHERE status = 'completed'
        ORDER BY orderDate, orderID
        LIMIT 5
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    1002 and 1003 (2024-01-02) both see 2024-01-01 and 2024-01-02: 211.65 + 249.00 + 747.00 = 1207.65. Orders 1004/1005 (2024-01-04) see 01-02 and 01-04. GROUPS needs PostgreSQL 11 or later.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 7 — Windows meeting the rest of SQL

    NULLs, joins, FILTER, the older alternatives, and the star schema. Every trap from Lectures 4 and 5 is still there — a window does not protect you from any of them.

    ### 7.1 THE TRAP: NULL is a partition too

    "Rank our salespeople by number of orders."
    """)
    return


@app.cell
def _(engine, mo):
    p7_01 = mo.sql(
        f"""
        SELECT o.employeeID, e.firstName,
               count(*)                              AS orders,
               rank() OVER (ORDER BY count(*) DESC)  AS sales_rank
        FROM orders o
        LEFT JOIN employees e ON e.employeeID = o.employeeID
        GROUP BY o.employeeID, e.firstName
        ORDER BY sales_rank
        LIMIT 4
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG: the "best salesperson", with 181 orders, has no ID and no name — it's the 181 online orders. GROUP BY and PARTITION BY put all NULLs into ONE group, so "no employee" is ranked as if it were one person, and every real salesperson drops a place. No error.

    The same thing inside PARTITION BY: "each salesperson's biggest completed order" returns 9 rows for 8 salespeople.
    """)
    return


@app.cell
def _(engine, mo):
    p7_02 = mo.sql(
        f"""
        SELECT count(*) AS rows, count(employeeID) AS with_an_employee
        FROM (SELECT employeeID,
                     row_number() OVER (PARTITION BY employeeID
                                        ORDER BY orderTotal DESC, orderID) AS rn
              FROM orders
              WHERE status = 'completed') AS w
        WHERE rn = 1
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG: 9 "salespeople" — the ninth is the online shop, employeeID NULL.

    FIX, option A — the question is about PEOPLE: take the online orders out, on purpose, and say so.
    """)
    return


@app.cell
def _(engine, mo):
    p7_03 = mo.sql(
        f"""
        SELECT o.employeeID, e.firstName,
               count(*)                              AS orders,
               rank() OVER (ORDER BY count(*) DESC)  AS sales_rank
        FROM orders o
        JOIN employees e ON e.employeeID = o.employeeID   -- inner join: online orders excluded deliberately
        GROUP BY o.employeeID, e.firstName
        ORDER BY sales_rank
        LIMIT 4
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    FIX, option B — the question is about CHANNELS of sale: keep the online orders, but as a labelled row, not a nameless one (the same idea as Lecture 4's '(online)' unknown member in dim_employee).
    """)
    return


@app.cell
def _(engine, mo):
    p7_04 = mo.sql(
        f"""
        SELECT coalesce(e.firstName, '(online)') AS sold_by,
               count(*)                              AS orders,
               rank() OVER (ORDER BY count(*) DESC)  AS sales_rank
        FROM orders o
        LEFT JOIN employees e ON e.employeeID = o.employeeID
        GROUP BY o.employeeID, e.firstName
        ORDER BY sales_rank
        LIMIT 4
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Neither fix is "right" in general. Decide which question you are answering, then write it so the reader can see the decision.

    ### 7.2 NULLS FIRST / NULLS LAST inside OVER

    "Each customer's best-rated completed order" — for a thank-you note. 207 of the 529 completed orders have no rating.
    """)
    return


@app.cell
def _(engine, mo):
    p7_05 = mo.sql(
        f"""
        SELECT count(*) FILTER (WHERE rating IS NULL) AS best_is_unrated,
               count(*)                               AS customers
        FROM (SELECT customerID, rating,
                     row_number() OVER (PARTITION BY customerID
                                        ORDER BY rating DESC, orderID) AS rn
              FROM orders
              WHERE status = 'completed') AS w
        WHERE rn = 1
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG: in PostgreSQL, NULL sorts as larger than any value, so with DESC the unrated orders come FIRST. Every one of the 28 customers has at least one unrated completed order, so for all 28 the "best- rated order" is one they never rated. No error.

    FIX: say where the NULLs go.
    """)
    return


@app.cell
def _(engine, mo):
    p7_06 = mo.sql(
        f"""
        SELECT count(*) FILTER (WHERE rating IS NULL) AS best_is_unrated,
               count(*)                               AS customers
        FROM (SELECT customerID, rating,
                     row_number() OVER (PARTITION BY customerID
                                        ORDER BY rating DESC NULLS LAST, orderID) AS rn
              FROM orders
              WHERE status = 'completed') AS w
        WHERE rn = 1
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Window aggregates skip NULLs, as plain aggregates do (Lecture 4, 4.6). count(*) vs count(rating) in the same window shows how many ratings an average is built on:
    """)
    return


@app.cell
def _(engine, mo):
    p7_07 = mo.sql(
        f"""
        SELECT orderID, rating,
               count(*)      OVER w           AS orders,
               count(rating) OVER w           AS rated,
               round(avg(rating) OVER w, 2)   AS avg_rating
        FROM orders
        WHERE status = 'completed' AND customerID = 5
        WINDOW w AS (PARTITION BY customerID)
        ORDER BY orderDate
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Lusine's average, 3.67, is built on 3 ratings, not her 4 orders: avg skipped the NULL. count(rating) next to count(*) is how you find out how much an average stands on.

    ### 7.3 A window does not repair a fan-out

    Each order LINE next to its customer's completed revenue — written on the joined lines, with the header's orderTotal:
    """)
    return


@app.cell
def _(engine, mo):
    p7_08 = mo.sql(
        f"""
        SELECT o.orderID, i.productID, i.lineTotal, o.orderTotal,
               sum(o.orderTotal) OVER (PARTITION BY o.customerID) AS customer_revenue
        FROM orders o
        JOIN order_items i ON i.orderID = o.orderID
        WHERE o.status = 'completed' AND o.customerID = 5
        ORDER BY o.orderDate, i.productID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    WRONG: Lusine's completed revenue is 2861.90 (Part 2.2), not 5011.30. Order 1307 has three lines and 1373 has two, so 1307's total was counted three times and 1373's twice — Lecture 5's cart fan-out (2.3), now inside a window. The window summed exactly the rows it was given; the join had already multiplied them.

    FIX: sum what lives on the line.
    """)
    return


@app.cell
def _(engine, mo):
    p7_09 = mo.sql(
        f"""
        SELECT o.orderID, i.productID, i.lineTotal, o.orderTotal,
               sum(i.lineTotal) OVER (PARTITION BY o.customerID) AS customer_revenue
        FROM orders o
        JOIN order_items i ON i.orderID = o.orderID
        WHERE o.status = 'completed' AND o.customerID = 5
        ORDER BY o.orderDate, i.productID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The check, over all customers: rows vs orders, and the total.
    """)
    return


@app.cell
def _(engine, mo):
    p7_10 = mo.sql(
        f"""
        SELECT count(*) AS line_rows, count(DISTINCT o.orderID) AS orders,
               sum(o.orderTotal) AS header_total_over_lines,
               sum(i.lineTotal)  AS line_total
        FROM orders o
        JOIN order_items i ON i.orderID = o.orderID
        WHERE o.status = 'completed'
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    844 rows for 529 orders, and Lecture 5's 247,923.72 again. Count rows against orders BEFORE you put a window on top of a join.

    ### 7.4 FILTER with window aggregates

    Lecture 4's FILTER works inside a window too: each of Lusine's orders next to how many of her orders were completed / returned.
    """)
    return


@app.cell
def _(engine, mo):
    p7_11 = mo.sql(
        f"""
        SELECT orderID, orderDate, status, orderTotal,
               count(*)        FILTER (WHERE status = 'completed') OVER w AS completed,
               count(*)        FILTER (WHERE status = 'returned')  OVER w AS returned,
               sum(orderTotal) FILTER (WHERE status = 'completed') OVER w AS completed_revenue
        FROM orders
        WHERE customerID = 5
        WINDOW w AS (PARTITION BY customerID)
        ORDER BY orderDate
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    FILTER works on aggregates used as windows (sum, count, avg...), not on row_number, rank, lag and the other window-only functions.

    #### Real problem: customers who return a lot

    **Task:** customer service wants the customers who returned at least 15% of their orders, with the numbers behind it.

    **Solution:** count(*) FILTER (WHERE status = 'returned') and count(*) over each customer's orders, on every order row; then one row per customer with DISTINCT.
    """)
    return


@app.cell
def _(engine, mo):
    p7_12 = mo.sql(
        f"""
        WITH rates AS (
            SELECT customerID,
                   count(*) FILTER (WHERE status = 'returned') OVER w AS returned,
                   count(*) OVER w                                     AS orders
            FROM orders
            WINDOW w AS (PARTITION BY customerID)
        )
        SELECT DISTINCT c.firstName, c.lastName, r.returned, r.orders,
               round(100.0 * r.returned / r.orders, 1) AS pct_returned
        FROM rates r
        JOIN customers c ON c.customerID = r.customerID
        WHERE r.returned >= 0.15 * r.orders
        ORDER BY pct_returned DESC, c.lastName
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Reading the result:** 5 customers. Read the counts, not just the percentage: Diana's 25% is 1 return out of 4 orders, Narek's 17.2% is 5 out of 29. A rate built on 4 orders says very little. (A GROUP BY would give the same list; the window version keeps every order row, so the same CTE can also flag each order for review.)

    ### 7.5 Window vs self-join vs correlated subquery

    "Completed orders bigger than their customer's average order" -- three ways. Each method's result is (orderID, avg rounded to cents). Proof by EXCEPT in both directions, for both pairs.
    """)
    return


@app.cell
def _(engine, mo):
    p7_13 = mo.sql(
        f"""
        WITH by_window AS (
            SELECT orderID, round(cust_avg, 2) AS cust_avg
            FROM (SELECT orderID, orderTotal,
                         avg(orderTotal) OVER (PARTITION BY customerID) AS cust_avg
                  FROM orders
                  WHERE status = 'completed') AS w
            WHERE orderTotal > cust_avg
        ),
        by_join AS (
            SELECT o.orderID, round(a.cust_avg, 2) AS cust_avg
            FROM orders o
            JOIN (SELECT customerID, avg(orderTotal) AS cust_avg
                  FROM orders
                  WHERE status = 'completed'
                  GROUP BY customerID) AS a ON a.customerID = o.customerID
            WHERE o.status = 'completed'
              AND o.orderTotal > a.cust_avg
        ),
        by_subquery AS (
            SELECT o.orderID,
                   round((SELECT avg(o2.orderTotal) FROM orders o2
                          WHERE o2.customerID = o.customerID AND o2.status = 'completed'), 2) AS cust_avg
            FROM orders o
            WHERE o.status = 'completed'
              AND o.orderTotal > (SELECT avg(o2.orderTotal) FROM orders o2
                                  WHERE o2.customerID = o.customerID AND o2.status = 'completed')
        )
        SELECT (SELECT count(*) FROM by_window) AS rows_window,
               (SELECT count(*) FROM (SELECT * FROM by_window   EXCEPT SELECT * FROM by_join)     x) AS window_not_join,
               (SELECT count(*) FROM (SELECT * FROM by_join     EXCEPT SELECT * FROM by_window)   x) AS join_not_window,
               (SELECT count(*) FROM (SELECT * FROM by_window   EXCEPT SELECT * FROM by_subquery) x) AS window_not_sub,
               (SELECT count(*) FROM (SELECT * FROM by_subquery EXCEPT SELECT * FROM by_window)   x) AS sub_not_window
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Same rows, three ways. The window version filters completed orders ONCE; the other two must repeat the status filter in two places, and forgetting one of them is a silent bug of its own.

    ### 7.6 Windows on the star schema

    Monthly completed revenue from fact_sales, with a running total across the year. Lecture 4 built the star; dim_date has the months.
    """)
    return


@app.cell
def _(engine, mo):
    p7_14 = mo.sql(
        f"""
        SELECT d.month, d.monthName,
               sum(f.revenue) AS revenue,
               sum(sum(f.revenue)) OVER (ORDER BY d.month
                                         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_revenue
        FROM fact_sales f
        JOIN dim_date d ON d.dateKey = f.dateKey
        WHERE f.status = 'completed'
        GROUP BY d.month, d.monthName
        ORDER BY d.month
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    December's running total is 157,078.41 — the completed revenue. (GROUP BY month first, so there is one row per month and no peers: ROWS and RANGE agree here. Writing ROWS anyway costs nothing.)

    Rank products inside their category by completed revenue, with each product's share of its category.
    """)
    return


@app.cell
def _(engine, mo):
    p7_15 = mo.sql(
        f"""
        SELECT p.category, p.productName,
               sum(f.revenue) AS revenue,
               rank() OVER (PARTITION BY p.category ORDER BY sum(f.revenue) DESC) AS rank_in_category,
               round(100 * sum(f.revenue) / sum(sum(f.revenue)) OVER (PARTITION BY p.category), 1) AS pct_of_category
        FROM fact_sales f
        JOIN dim_product p ON p.productKey = f.productKey
        WHERE f.status = 'completed' AND p.category IN ('Laptops', 'Phones')
        GROUP BY p.category, p.productName
        ORDER BY p.category, rank_in_category
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Check the star version against the known total: every category's products, every share. The category totals must add up to 157,078.41, and each category's shares to 100.
    """)
    return


@app.cell
def _(engine, mo):
    p7_16 = mo.sql(
        f"""
        WITH by_product AS (
            SELECT p.category, p.productKey, sum(f.revenue) AS revenue
            FROM fact_sales f
            JOIN dim_product p ON p.productKey = f.productKey
            WHERE f.status = 'completed'
            GROUP BY p.category, p.productKey
        ),
        shares AS (
            SELECT category, revenue,
                   100 * revenue / sum(revenue) OVER (PARTITION BY category) AS pct_of_category
            FROM by_product
        )
        SELECT count(*) AS products_sold,
               count(DISTINCT category) AS categories,
               sum(revenue) AS total,
               min(round(cat_pct, 6)) AS min_category_pct,
               max(round(cat_pct, 6)) AS max_category_pct
        FROM (SELECT category, revenue,
                     sum(pct_of_category) OVER (PARTITION BY category) AS cat_pct
              FROM shares) AS s
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    36 products in 12 categories — Ergonomic Chair Pro (Chairs) never sold, so it has no fact rows. Total 157,078.41; every category's shares add up to 100.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 8 — Verification drill

    For each one: which check from the notes catches it?
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Drill 1.** "Orders placed so far this year, order by order"
    """)
    return


@app.cell
def _(engine, mo):
    d1_wrong = mo.sql(
        f"""
        SELECT orderID, orderDate,
               count(*) OVER (ORDER BY orderDate) AS orders_so_far
        FROM orders
        ORDER BY orderDate, orderID
        LIMIT 3
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    1. The default RANGE frame: orders 1002 and 1003 share a date, so both count each other. Check: a running count must go up by exactly 1 per row. Fix: ROWS + a tie-breaker.
    """)
    return


@app.cell
def _(engine, mo):
    d1_fix = mo.sql(
        f"""
        SELECT orderID, orderDate,
               count(*) OVER (ORDER BY orderDate, orderID
                              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS orders_so_far
        FROM orders
        ORDER BY orderDate, orderID
        LIMIT 3
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Drill 2.** "The top 3 salespeople by completed revenue"
    """)
    return


@app.cell
def _(engine, mo):
    d2_wrong = mo.sql(
        f"""
        SELECT e.firstName, sum(o.orderTotal) AS revenue,
               rank() OVER (ORDER BY sum(o.orderTotal) DESC) AS revenue_rank
        FROM orders o
        LEFT JOIN employees e ON e.employeeID = o.employeeID
        WHERE o.status = 'completed'
        GROUP BY o.employeeID, e.firstName
        ORDER BY revenue_rank
        LIMIT 3
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    2. The NULL partition: the "salesperson" with no name is the online shop. Check: a ranking of people should have names. Fix: exclude the NULLs on purpose (or label them, if the question is channels).
    """)
    return


@app.cell
def _(engine, mo):
    d2_fix = mo.sql(
        f"""
        SELECT e.firstName, sum(o.orderTotal) AS revenue,
               rank() OVER (ORDER BY sum(o.orderTotal) DESC) AS revenue_rank
        FROM orders o
        JOIN employees e ON e.employeeID = o.employeeID
        WHERE o.status = 'completed'
        GROUP BY o.employeeID, e.firstName
        ORDER BY revenue_rank
        LIMIT 3
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Drill 3.** "Arman's month-over-month change, May to July"
    """)
    return


@app.cell
def _(engine, mo):
    d3_wrong = mo.sql(
        f"""
        WITH monthly AS (
            SELECT extract(month FROM orderDate)::int AS month, sum(orderTotal) AS revenue
            FROM orders
            WHERE status = 'completed' AND employeeID = 7
            GROUP BY 1
        )
        SELECT month, revenue, revenue - lag(revenue) OVER (ORDER BY month) AS change
        FROM monthly
        WHERE month BETWEEN 5 AND 7
        ORDER BY month
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    3. lag across a missing month: Arman sold nothing in June, so July is compared with May. And the WHERE ran before lag (Part 2.5), so even May's lag lost April. Check: lag the month too. Fix: a full calendar, LEFT JOIN, and filter the months AFTER the window.
    """)
    return


@app.cell
def _(engine, mo):
    d3_fix = mo.sql(
        f"""
        WITH monthly AS (
            SELECT extract(month FROM orderDate)::int AS month, sum(orderTotal) AS revenue
            FROM orders
            WHERE status = 'completed' AND employeeID = 7
            GROUP BY 1
        ),
        full_months AS (
            SELECT m.month, coalesce(mo.revenue, 0) AS revenue
            FROM (SELECT DISTINCT month FROM dim_date) AS m
            LEFT JOIN monthly mo ON mo.month = m.month
        ),
        compared AS (
            SELECT month, revenue, revenue - lag(revenue) OVER (ORDER BY month) AS change
            FROM full_months
        )
        SELECT month, revenue, change
        FROM compared
        WHERE month BETWEEN 5 AND 7
        ORDER BY month
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Drill 4.** "Each of Diana's orders next to her latest order"
    """)
    return


@app.cell
def _(engine, mo):
    d4_wrong = mo.sql(
        f"""
        SELECT customerID, orderID, orderTotal,
               last_value(orderID) OVER (PARTITION BY customerID
                                         ORDER BY orderDate, orderTime, orderID) AS latest_order
        FROM orders
        WHERE customerID = 27
        ORDER BY orderDate
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    4. last_value with the default frame returns the current row. Check: a "latest" column that changes on every row isn't the latest. Fix: a frame to UNBOUNDED FOLLOWING.
    """)
    return


@app.cell
def _(engine, mo):
    d4_fix = mo.sql(
        f"""
        SELECT customerID, orderID, orderTotal,
               last_value(orderID) OVER (PARTITION BY customerID
                                         ORDER BY orderDate, orderTime, orderID
                                         ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS latest_order
        FROM orders
        WHERE customerID = 27
        ORDER BY orderDate
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Drill 5.** "Each order's share of completed revenue" (the three biggest)
    """)
    return


@app.cell
def _(engine, mo):
    d5_wrong = mo.sql(
        f"""
        SELECT o.orderID, i.productID,
               round(100 * o.orderTotal / sum(o.orderTotal) OVER (), 3) AS pct_of_revenue
        FROM orders o
        JOIN order_items i ON i.orderID = o.orderID
        WHERE o.status = 'completed'
        ORDER BY o.orderTotal DESC, o.orderID, i.productID
        LIMIT 3
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    5. A window over a fan-out: the join made one row per LINE, so the denominator is every header total summed once per line, and a 3-line order is listed 3 times. Every share comes out too small (order 1158: 1.008% instead of 1.592%). The shares still add up to 100, so that check can't see it. Compare the row count and the denominator with what you know: 529 orders, 157,078.41.
    """)
    return


@app.cell
def _(engine, mo):
    d5_fix = mo.sql(
        f"""
        SELECT count(*) AS rows, count(DISTINCT o.orderID) AS orders,
               min(denominator) AS denominator
        FROM (SELECT o.orderID, sum(o.orderTotal) OVER () AS denominator
              FROM orders o
              JOIN order_items i ON i.orderID = o.orderID
              WHERE o.status = 'completed') AS o
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Fix: the window over orders, one row per order.
    """)
    return


@app.cell
def _(engine, mo):
    d5_fix2 = mo.sql(
        f"""
        SELECT orderID,
               round(100 * orderTotal / sum(orderTotal) OVER (), 3) AS pct_of_revenue
        FROM orders
        WHERE status = 'completed'
        ORDER BY orderTotal DESC, orderID
        LIMIT 3
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 8 — Why all of this matters (the one idea to leave the room with)

    Look back at today's traps:

    | Trap | Looked like | Was |
    |---|---|---|
    | `ORDER BY` inside `OVER` instead of the query's | "the first five orders of the year": 1385, 1158, 1363, 1314, 1542 | 1001–1005 |
    | `WHERE` before the window | Lusine's orders are 55.84% … of revenue | 1.02% … (1.82% in all) |
    | `row_number` on ties | the 8th loyal customer is Lilit (or Narek, depending on the query) | a tie: decide, or use `rank` (9 customers) |
    | Incomplete `ORDER BY` in top-N | three methods agree Armen's latest order is 1595 | 1596 |
    | Inner `JOIN LATERAL` | 28 customers' latest orders | 30 customers, 2 with none |
    | `lag` default of 0 | average order-to-order change 17.23 | 1.42 |
    | `lag` across missing months | Nare's March is +540.19 on January | +872.59 on February's 0; 7 rows wrong |
    | The default `RANGE` frame | running total 1,207.65 on two orders in a row | 460.65, then 1,207.65 |
    | `last_value` without a frame | "latest order" = this order, on 529 of 529 rows | 177.00 for Lusine |
    | Moving average at the edge | a 3-month average of 9,902.54 in January | not enough months |
    | The NULL partition | the top salesperson has 181 orders and no name | Ani, 91 |
    | `NULLS FIRST` with `DESC` | every customer's best-rated order is unrated | 0 of 28 |
    | Fan-out under a window | Lusine spent 5,011.30 | 2,861.90 |

    **One loud failure:** a window function in `WHERE` (`window functions are not allowed in WHERE`). Everything else in the table ran without an error and returned a table that looked completely normal.

    **That's the same point as Lectures 4 and 5, and it will be the point of every lecture:** SQL correctness bugs are almost always silent. Window functions add a family of them, because so much of their meaning lives in defaults you didn't write (the frame, the order of ties, where NULLs sort). The checks are the same ones as before, plus one new one:

    - **Rows in = rows out.** A query with only window functions returns as many rows as its input: 600 in, 600 out. If it doesn't, something else in the query changed the rows.
    - **A running total ends at the plain total**, per partition and overall (157,078.41), and **changes on every row** (279 stalled rows is a RANGE frame).
    - **Answer the question two independent ways and compare with `EXCEPT` both ways**: 0 rows each way. But two methods agreeing proves something only if the question has exactly one answer. Make every `ORDER BY` complete first.
    - **Check against ground truth you already have**: 157,078.41, 100,222.48, 600 and 529, 28 customers with orders and 2 without, 8 salespeople and 12 months.
    - **Read the columns you computed.** A `latest_order` equal to `orderTotal`, a running total that repeats, a "salesperson" with no name, a list sorted by the wrong column: each one is visible if you look.

    **The new functions, in one table** (each is defined where it first appears): 

    | Function | Meaning | First used |
    |---|---|---|
    | `row_number()` | 1, 2, 3 … in the window's order; ties get different numbers, in no guaranteed order | 2.4 |
    | `rank()` | position in the window's order; ties share it, then a gap (1, 2, 2, 4) | 2.4 |
    | `dense_rank()` | like `rank`, no gap (1, 2, 2, 3) | 3.0 |
    | `ntile(n)` | bucket 1 to n, buckets as equal as possible | 3.0 |
    | `percent_rank()` | relative position from 0 to 1: (rank − 1) / (rows − 1) | 3.0 |
    | `cume_dist()` | share of rows at or before this one, ties included | 3.0 |
    | `lag(x, n, d)` | `x` from n rows back (default 1); `d` (default NULL) if there is none | 5.1, 5.2 |
    | `lead(x, n, d)` | `x` from n rows ahead | 5.4 |
    | `first_value(x)` | `x` on the first row of the frame | 5.5 |
    | `nth_value(x, n)` | `x` on the n-th row of the frame; NULL if there isn't one yet | 5.5 |
    | `last_value(x)` | `x` on the last row of the frame: the current row, with the default frame | 6.4 |
    | `string_agg(x, ',')` | the values of `x` from all rows it sees, joined into one text | 6.4 |

    An AI assistant will write a window query that reads beautifully, with `last_value`, `lag(x, 1, 0)` and `row_number` with no tie-breaker, whether the logic is right or not. Knowing which number to check is the skill.
    """)
    return


if __name__ == "__main__":
    app.run()
