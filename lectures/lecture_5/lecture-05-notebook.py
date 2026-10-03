import marimo

__generated_with = "0.25.0"
app = marimo.App(width="medium")


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    # Lecture 5 — Subqueries → CTEs

    The whole lecture, one query at a time, against **Lecture 4's shop — now with real multi-product orders**: `orders` is the header (one row per order, with `orderTotal`), `order_items` the lines (one row per product in an order, with `lineTotal`). 600 orders, 965 lines; 235 orders hold more than one product.

    You already know the answers to most questions here: Levon and Astghik never ordered, Ergonomic Chair Pro (productID 35) never sold, 181 orders are online with no employee, Hayk never had an order cancelled. Completed revenue is **157,078.41** (it was 145,935.12 in Lecture 4, when every order held one product). That is the point — every query can be checked against a number you trust.

    **Before you run this:** from the `lecture_5/` folder, run `psql postgres` and `\i steps/00-setup.sql` (it creates the `lecture05` database if it doesn't exist, loads the data, and runs `ANALYZE` so everyone's planner makes the same choices — Part 5.4 depends on that). Then start the notebook with the connection string in `LECTURE05_DSN`, e.g.

    ```
    LECTURE05_DSN=postgresql://postgres:postgres@localhost:5432/lecture05 marimo edit lecture-05-notebook.py
    ```

    Each trap appears as **wrong query → what's wrong with it → fixed query**, with real results on screen at each step.
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
    # psql + steps/00-setup.sql; set LECTURE05_DSN if yours differs.
    engine = psycopg.connect(
        os.environ.get("LECTURE05_DSN", "postgresql://postgres:postgres@localhost:5432/lecture05"),
        autocommit=True,
    )
    return (engine,)


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## The schema: one order, several products

    **Before (Lecture 4): one product per order.** The order row itself pointed at the product through a single `productID` column — room for exactly one product.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.mermaid(r"""
    erDiagram
        CUSTOMERS ||--o{ ORDERS : places
        PRODUCTS  ||--o{ ORDERS : "is the one product of"
        ORDERS {
            int orderID PK
            int customerID FK
            int productID FK "room for ONE product"
            int quantity
            decimal unitPrice
            decimal orderTotal
        }
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Now: a header and its lines.** `orders` holds what is true once per order (who, when, status, `orderTotal`); `order_items` holds one row per product in the order (`productID`, `quantity`, `unitPrice`, `lineTotal`), keyed by `(orderID, productID)`.
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
            int discountPct
            decimal lineTotal
        }
        PRODUCTS {
            int productID PK
            text productName
            text category
            decimal price
        }
        CUSTOMERS {
            int customerID PK
            text firstName
            text city
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
    **Why it's built this way:**

    1. **A real cart holds several products, and one column holds one value.** Orders and products are many-to-many — the junction table Lecture 2 drew in an aside and deferred. `order_items` is that table.
    2. **Why not one `orders` row per product?** The customer, date, status and total would repeat on every row, and `orderID` could no longer be the key — the redundancy Lecture 2 normalized away.
    3. **Each fact is stored once, at its own grain:** per order in `orders`, per product-in-an-order in `order_items`. Buying two of something is `quantity = 2`, not two lines.
    4. **The price is stored on the line**, so old orders stay correct when `products.price` changes. (Here every line was sold at list price.)
    5. **The price of the split: two grains.** Joining `orders` to `order_items` gives one row per *line*, with the header — `orderTotal` included — copied onto each. That's Part 2.3's fan-out.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Check the data first.** One count per table: you should see **30 / 8 / 37 / 600 / 965** — 600 orders, but 965 order lines.
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
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 1 — Subqueries: the basic shapes

    A subquery is a `SELECT` inside another statement, in parentheses. Where you put it decides what it may return:

    | Shape | Returns | Typical place |
    |---|---|---|
    | Scalar | one value | `WHERE price > (...)` |
    | Column | one column, many rows | `IN`, `= ANY`, `> ALL` |
    | Row | one row, several columns | `WHERE (a, b) = (...)` |
    | Table | a whole result | `FROM (...) AS t` |

    ### 1.1 Scalar subquery — one value

    The average product price, on its own:
    """)
    return


@app.cell
def _(engine, mo):
    p1_avg_price = mo.sql(
        f"""
        SELECT round(avg(price), 2) AS avg_price FROM products
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Use that one value as a constant inside another query. Expect **12** products above **280.10**.
    """)
    return


@app.cell
def _(engine, mo):
    p1_above_avg = mo.sql(
        f"""
        SELECT productName, category, price
        FROM products
        WHERE price > (SELECT avg(price) FROM products)
        ORDER BY price DESC
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    A scalar subquery works anywhere one value does — here as the denominator of a share. Revenue *per category* comes from the lines (`lineTotal`), the total from the headers (`orderTotal`). Laptops should be **34.0%** of 157,078.41.
    """)
    return


@app.cell
def _(engine, mo):
    p1_share = mo.sql(
        f"""
        SELECT p.category,
               sum(i.lineTotal) AS revenue,
               round(100 * sum(i.lineTotal)
                         / (SELECT sum(orderTotal) FROM orders WHERE status = 'completed'), 1) AS pct_of_total
        FROM order_items i
        JOIN orders   o ON o.orderID   = i.orderID
        JOIN products p ON p.productID = i.productID
        WHERE o.status = 'completed'
        GROUP BY p.category
        ORDER BY revenue DESC
        LIMIT 3
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Error on purpose:** "one value" is a promise. There are four phones, so "the price of a phone" is four values.
    """)
    return


@app.cell
def _(engine, mo, psycopg):
    # Error on purpose -- shows PostgreSQL's message instead of stopping the notebook.
    try:
        engine.execute("""
        SELECT productName, price
        FROM products
        WHERE price > (SELECT price FROM products WHERE category = 'Phones')
        """)
        _shown = mo.callout(mo.md("No error?! This query was supposed to fail."), kind="warn")
    except psycopg.Error as _e:
        _shown = mo.callout(mo.md(f"**ERROR:** `{_e.diag.message_primary}`"), kind="danger")
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **No error, no rows.** There is no 'iPhone 16'. A scalar subquery that finds *nothing* becomes NULL, `price > NULL` is never true, and the result is silently empty. Too many rows is loud; zero rows is quiet.
    """)
    return


@app.cell
def _(engine, mo):
    p1_zero_rows = mo.sql(
        f"""
        SELECT productName, price
        FROM products
        WHERE price > (SELECT price FROM products WHERE productName = 'iPhone 16')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 1.2 Column subquery — IN, ANY, ALL

    You wrote this one at the end of Lecture 4: customers who ordered in December. Expect **26**.
    """)
    return


@app.cell
def _(engine, mo):
    p1_in_december = mo.sql(
        f"""
        SELECT count(*) AS customers
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
    The JOIN version counts **rows**, one per December order — **86**. `IN` only asks "is this customer on the list?", so each customer comes out once.
    """)
    return


@app.cell
def _(engine, mo):
    p1_join_december = mo.sql(
        f"""
        SELECT count(*) AS rows
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
    **`= ANY`** — "equal to any value in the list". That is exactly what `IN` means, so it's `IN` under another name: **26** again.
    """)
    return


@app.cell
def _(engine, mo):
    p1_any_december = mo.sql(
        f"""
        SELECT count(*) AS customers
        FROM customers
        WHERE customerID = ANY (SELECT customerID FROM orders
                                WHERE orderDate BETWEEN '2024-12-01' AND '2024-12-31')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **`> ALL`** — greater than *every* value in the list. The dearest phone is 799.00, so only **3** laptops are dearer than all phones.
    """)
    return


@app.cell
def _(engine, mo):
    p1_all_phones = mo.sql(
        f"""
        SELECT productName, category, price
        FROM products
        WHERE price > ALL (SELECT price FROM products WHERE category = 'Phones')
        ORDER BY price DESC
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **`> ANY`** — greater than *at least one* value in the list. The cheapest phone is 249.00, so **13** products qualify.
    """)
    return


@app.cell
def _(engine, mo):
    p1_any_phones = mo.sql(
        f"""
        SELECT count(*) AS products
        FROM products
        WHERE price > ANY (SELECT price FROM products WHERE category = 'Phones')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 1.3 Row subquery — rare

    Every order by the same customer **on the same day** as order 1595: **2** rows — Armen Gevorgyan ordered twice on 2024-12-28.
    """)
    return


@app.cell
def _(engine, mo):
    p1_row = mo.sql(
        f"""
        SELECT orderID, customerID, orderDate, orderTime, orderTotal
        FROM orders
        WHERE (customerID, orderDate) = (SELECT customerID, orderDate
                                         FROM orders WHERE orderID = 1595)
        ORDER BY orderID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 1.4 Table subquery — a derived table in FROM

    "Average orders per customer" is an aggregate of an aggregate. **Error on purpose:**
    """)
    return


@app.cell
def _(engine, mo, psycopg):
    # Error on purpose -- shows PostgreSQL's message instead of stopping the notebook.
    try:
        engine.execute("""
        SELECT avg(count(*)) FROM orders GROUP BY customerID
        """)
        _shown = mo.callout(mo.md("No error?! This query was supposed to fail."), kind="warn")
    except psycopg.Error as _e:
        _shown = mo.callout(mo.md(f"**ERROR:** `{_e.diag.message_primary}`"), kind="danger")
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Count per customer in a subquery, average outside. Expect **21.43** over **28** customers — Levon and Astghik have no orders, so they're not in the derived table (600 / 28, not 600 / 30 = 20.00).
    """)
    return


@app.cell
def _(engine, mo):
    p1_avg_orders = mo.sql(
        f"""
        SELECT round(avg(order_count), 2) AS avg_orders_per_customer,
               count(*)                   AS customers
        FROM (SELECT customerID, count(*) AS order_count
              FROM orders
              GROUP BY customerID) AS per_customer
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    A derived table can be filtered and joined like any table. Customers with 40+ orders: **4**.
    """)
    return


@app.cell
def _(engine, mo):
    p1_40_plus = mo.sql(
        f"""
        SELECT c.firstName, c.lastName, pc.order_count
        FROM (SELECT customerID, count(*) AS order_count
              FROM orders
              GROUP BY customerID) AS pc
        JOIN customers c ON c.customerID = pc.customerID
        WHERE pc.order_count >= 40
        ORDER BY pc.order_count DESC
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 2 — Subqueries vs. JOINs

    ### 2.1 One question, three queries

    "Which products have never been ordered?" Lecture 4's answer: **productID 35, Ergonomic Chair Pro**. Each of the next three cells should return exactly that row.

    **(a) Lecture 4's anti-join.** `LEFT JOIN` keeps every product; a product that appears on no order line gets NULLs in the line columns, and `WHERE i.orderID IS NULL` keeps exactly those. Products live on the lines now, so all three versions ask `order_items`.
    """)
    return


@app.cell
def _(engine, mo):
    p2_anti_join = mo.sql(
        f"""
        SELECT p.productID, p.productName
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
    **(b) `NOT IN`.** Build the list of every productID that appears in `order_items`, and keep the products that are not on it. It reads most like plain English — and it is the one with a catch (2.2).
    """)
    return


@app.cell
def _(engine, mo):
    p2_not_in_products = mo.sql(
        f"""
        SELECT productID, productName
        FROM products
        WHERE productID NOT IN (SELECT productID FROM order_items)
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **(c) `NOT EXISTS`.** For each product, ask "is there at least one order for it?" and keep the products where the answer is no. The subquery mentions `p`, the outer row — it's correlated (Part 3).
    """)
    return


@app.cell
def _(engine, mo):
    p2_not_exists_products = mo.sql(
        f"""
        SELECT p.productID, p.productName
        FROM products p
        WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.productID = p.productID)
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    They agree **here** because `order_items.productID` is `NOT NULL`. Now a column that can be NULL.

    ### 2.2 The NOT IN trap — callback to Lecture 4's anti-join

    In miniature: `5 NOT IN (1, 2, NULL)` means `5 <> 1 AND 5 <> 2 AND 5 <> NULL`, and the last part is unknown. Expect **true**, **null**, **false**.
    """)
    return


@app.cell
def _(engine, mo):
    p2_mini = mo.sql(
        f"""
        SELECT 5 NOT IN (1, 2)       AS no_null,
               5 NOT IN (1, 2, NULL) AS with_null,
               2 NOT IN (1, 2, NULL) AS match_with_null
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The real question: **"Which salespeople have never had an order cancelled?"** Run it and read the answer.
    """)
    return


@app.cell
def _(engine, mo):
    p2_not_in_wrong = mo.sql(
        f"""
        SELECT e.employeeID, e.firstName, e.lastName
        FROM employees e
        WHERE e.employeeID NOT IN (SELECT o.employeeID FROM orders o
                                   WHERE o.status = 'cancelled')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **What's wrong:** zero rows — "nobody has a clean record." No error, and an empty list looks like a real answer.

    It isn't. Some cancelled orders were **online**, so their `employeeID` is NULL (Lecture 4's 181 online orders). One NULL in the `NOT IN` list makes the test unknown for *every* employee, and `WHERE` keeps nothing.

    **Fix 1 — `NOT EXISTS`.** It asks "is there a matching row?", which is only ever true or false — a NULL can't turn it into "unknown". Expect **Hayk Melikyan**.
    """)
    return


@app.cell
def _(engine, mo):
    p2_not_exists_fix = mo.sql(
        f"""
        SELECT e.employeeID, e.firstName, e.lastName
        FROM employees e
        WHERE NOT EXISTS (SELECT 1 FROM orders o
                          WHERE o.employeeID = e.employeeID
                            AND o.status = 'cancelled')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Check the diagnosis:** `count(*)` vs. `count(employeeID)` on the subquery's rows. Expect **27** cancelled orders, only **22** with an employee.
    """)
    return


@app.cell
def _(engine, mo):
    p2_null_check = mo.sql(
        f"""
        SELECT count(*) AS cancelled_orders, count(employeeID) AS with_an_employee
        FROM orders
        WHERE status = 'cancelled'
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Fix 2 — keep `NOT IN`, remove the NULLs yourself.** `AND o.employeeID IS NOT NULL` inside the subquery leaves a list with no NULL in it, and `NOT IN` works again: Hayk.
    """)
    return


@app.cell
def _(engine, mo):
    p2_not_in_fix = mo.sql(
        f"""
        SELECT e.employeeID, e.firstName, e.lastName
        FROM employees e
        WHERE e.employeeID NOT IN (SELECT o.employeeID FROM orders o
                                   WHERE o.status = 'cancelled'
                                     AND o.employeeID IS NOT NULL)
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Fix 3 — Lecture 4's anti-join.** The status test goes in `ON`, not `WHERE`: in `WHERE` it would delete the NULL-padded rows the anti-join is looking for (Lecture 4's WHERE-vs-ON lesson). Hayk again.
    """)
    return


@app.cell
def _(engine, mo):
    p2_anti_join_fix = mo.sql(
        f"""
        SELECT e.employeeID, e.firstName, e.lastName
        FROM employees e
        LEFT JOIN orders o ON o.employeeID = e.employeeID
                          AND o.status = 'cancelled'
        WHERE o.orderID IS NULL
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 2.3 The cart fan-out — joining the lines multiplies the header

    One order has one header row and one or more lines. Join them, and every header column — `orderTotal` included — is copied onto every line. Lecture 4's `moneySpent` fan-out, one level down.

    "Completed revenue, and how many units we sold." Units live on the lines, so someone joins them in:
    """)
    return


@app.cell
def _(engine, mo):
    p2_cart_wrong = mo.sql(
        f"""
        SELECT sum(o.orderTotal) AS revenue,
               sum(i.quantity)   AS units
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
    **What's wrong:** units (**1,174**) are right; revenue (**247,923.72**) is not. Every order with 3 lines had its total added 3 times. No error, and the number looks like a revenue.

    **Check 1 — the revenue without the join:** expect **157,078.41**.
    """)
    return


@app.cell
def _(engine, mo):
    p2_cart_truth = mo.sql(
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
    **Check 2 — count before you sum.** **844** rows for **529** orders: that gap is the fan-out.
    """)
    return


@app.cell
def _(engine, mo):
    p2_cart_counts = mo.sql(
        f"""
        SELECT count(*)                   AS rows,
               count(DISTINCT o.orderID)  AS orders
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
    **Fix 1 — sum what lives on the line.** `sum(i.lineTotal)` instead of the header's `orderTotal`: **157,078.41**, still **1,174** units.
    """)
    return


@app.cell
def _(engine, mo):
    p2_cart_fix1 = mo.sql(
        f"""
        SELECT sum(i.lineTotal) AS revenue,
               sum(i.quantity)  AS units
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
    **Fix 2 — aggregate the lines per order first.** A table subquery (1.4) gives one row per order before the join, so nothing can be copied. Same **157,078.41**.
    """)
    return


@app.cell
def _(engine, mo):
    p2_cart_fix2 = mo.sql(
        f"""
        SELECT sum(o.orderTotal) AS revenue,
               sum(l.units)      AS units
        FROM orders o
        JOIN (SELECT orderID, sum(quantity) AS units
              FROM order_items
              GROUP BY orderID) AS l ON l.orderID = o.orderID
        WHERE o.status = 'completed'
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 2.4 Where a subquery is simply the right tool

    "Revenue from orders that include at least one accessory." The JOIN version — an order with two accessories (sleeve **and** mouse) matches twice:
    """)
    return


@app.cell
def _(engine, mo):
    p2_accessory_wrong = mo.sql(
        f"""
        SELECT sum(o.orderTotal) AS revenue, count(*) AS orders
        FROM orders o
        JOIN order_items i ON i.orderID   = o.orderID
        JOIN products    p ON p.productID = i.productID
        WHERE o.status = 'completed'
          AND p.category = 'Accessories'
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **What's wrong:** "155 orders" is really 155 accessory *lines*. 13 orders hold two accessories, and their totals were counted twice.

    **Fix:** `EXISTS` asks "is there at least one accessory line?" — each order is kept once. Expect **25,955.91** over **142** orders.
    """)
    return


@app.cell
def _(engine, mo):
    p2_accessory_fix = mo.sql(
        f"""
        SELECT sum(o.orderTotal) AS revenue, count(*) AS orders
        FROM orders o
        WHERE o.status = 'completed'
          AND EXISTS (SELECT 1
                      FROM order_items i
                      JOIN products p ON p.productID = i.productID
                      WHERE i.orderID = o.orderID
                        AND p.category = 'Accessories')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 3 — Correlated vs. non-correlated subqueries

    **Non-correlated:** `(SELECT avg(price) FROM products)` from Part 1 runs on its own — one value, computed once.

    **Correlated:** the subquery mentions the outer row (`p.category`), so its answer differs per row. Products above **their own category's** average: expect **19** (vs. 12 against the overall average).
    """)
    return


@app.cell
def _(engine, mo):
    p3_category_avg = mo.sql(
        f"""
        SELECT p.productName, p.category, p.price
        FROM products p
        WHERE p.price > (SELECT avg(p2.price)
                         FROM products p2
                         WHERE p2.category = p.category)
        ORDER BY p.category, p.price DESC
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Error on purpose:** run only the inner query. Without the outer query there is no `p` — the quickest test of whether a subquery is correlated.
    """)
    return


@app.cell
def _(engine, mo, psycopg):
    # Error on purpose -- shows PostgreSQL's message instead of stopping the notebook.
    try:
        engine.execute("""
        SELECT avg(p2.price) FROM products p2 WHERE p2.category = p.category
        """)
        _shown = mo.callout(mo.md("No error?! This query was supposed to fail."), kind="warn")
    except psycopg.Error as _e:
        _shown = mo.callout(mo.md(f"**ERROR:** `{_e.diag.message_primary}`"), kind="danger")
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 3.3 Each customer against their own history

    Customers whose most recent order was bigger than their own average order. Expect **10** rows, Artur Baghdasaryan on top (1,358.30 vs. an average of 355.32).
    """)
    return


@app.cell
def _(engine, mo):
    p3_last_order = mo.sql(
        f"""
        SELECT c.firstName, c.lastName, o.orderID, o.orderDate, o.orderTotal,
               (SELECT round(avg(o3.orderTotal), 2)
                FROM orders o3 WHERE o3.customerID = o.customerID) AS their_avg
        FROM orders o
        JOIN customers c ON c.customerID = o.customerID
        WHERE o.orderID = (SELECT o2.orderID FROM orders o2
                           WHERE o2.customerID = o.customerID
                           ORDER BY o2.orderDate DESC, o2.orderTime DESC
                           LIMIT 1)
          AND o.orderTotal > (SELECT avg(o3.orderTotal)
                              FROM orders o3 WHERE o3.customerID = o.customerID)
        ORDER BY o.orderTotal DESC
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 3.4 Same shape as Lecture 4's self-join

    "Who was hired before their own manager?" Two tools, one answer: **Marine** (2016-08-01, before Vahe's 2017-02-01).

    **Self-join (Lecture 4's tool).** The same table twice: `e` plays the employee, `m` their manager; the join pairs them and `WHERE` compares their hire dates.
    """)
    return


@app.cell
def _(engine, mo):
    p3_self_join = mo.sql(
        f"""
        SELECT e.firstName, e.hireDate, m.firstName AS manager, m.hireDate AS manager_hired
        FROM employees e
        JOIN employees m ON m.employeeID = e.managerID
        WHERE e.hireDate < m.hireDate
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Correlated subquery.** No join: for each employee, a one-value subquery fetches *their* manager's hire date, and the outer `WHERE` compares. Same row: Marine.
    """)
    return


@app.cell
def _(engine, mo):
    p3_correlated = mo.sql(
        f"""
        SELECT e.firstName, e.hireDate
        FROM employees e
        WHERE e.hireDate < (SELECT m.hireDate
                            FROM employees m
                            WHERE m.employeeID = e.managerID)
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Where they differ: a correlated subquery in `SELECT` never drops an outer row. Lecture 4's self-join + `GROUP BY` showed the **3** managers; this shows all **8** employees, 0 reports for five of them, and NULL as Vahe's manager — like a `LEFT JOIN`.
    """)
    return


@app.cell
def _(engine, mo):
    p3_direct_reports = mo.sql(
        f"""
        SELECT e.firstName || ' ' || e.lastName AS employee,
               (SELECT m.firstName || ' ' || m.lastName
                FROM employees m WHERE m.employeeID = e.managerID) AS manager,
               (SELECT count(*)
                FROM employees r WHERE r.managerID = e.employeeID) AS direct_reports
        FROM employees e
        ORDER BY direct_reports DESC, e.employeeID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 3.5 LATERAL — a correlated subquery in FROM

    A correlated subquery in `SELECT` returns **one value**. "Each customer's latest order — id, date, product, total" needs four. **Error on purpose:**
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
                ORDER BY o.orderDate DESC, o.orderTime DESC
                LIMIT 1) AS latest
        FROM customers c
        """)
        _shown = mo.callout(mo.md("No error?! This query was supposed to fail."), kind="warn")
    except psycopg.Error as _e:
        _shown = mo.callout(mo.md(f"**ERROR:** `{_e.diag.message_primary}`"), kind="danger")
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    A subquery in `FROM` can return many columns, but on its own it can't see `c` — it's evaluated independently. **Error on purpose** (PostgreSQL 16+ adds a hint: *mark this subquery with LATERAL*):
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
              ORDER BY o.orderDate DESC, o.orderTime DESC
              LIMIT 1) AS latest ON true
        """)
        _shown = mo.callout(mo.md("No error?! This query was supposed to fail."), kind="warn")
    except psycopg.Error as _e:
        _shown = mo.callout(mo.md(f"**ERROR:** `{_e.diag.message_primary}`"), kind="danger")
    _shown
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    `LATERAL` lets the subquery use columns of the tables before it; it runs once per customer row. `ON true` because the matching is already done inside. Expect **28** rows, Artur Baghdasaryan's in-store order 1588 (1,358.30) on top — 3.3's last orders, with every column in one join.
    """)
    return


@app.cell
def _(engine, mo):
    p3_lateral_latest = mo.sql(
        f"""
        SELECT c.firstName, c.lastName,
               latest.orderID, latest.orderDate, latest.channel, latest.orderTotal
        FROM customers c
        JOIN LATERAL (SELECT o.orderID, o.orderDate, o.channel, o.orderTotal
                      FROM orders o
                      WHERE o.customerID = c.customerID
                      ORDER BY o.orderDate DESC, o.orderTime DESC
                      LIMIT 1) AS latest ON true
        ORDER BY latest.orderTotal DESC
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Top N per group:** each customer's 3 biggest orders — several *rows* per customer, which no scalar subquery can return. `orderID` breaks ties (Suren has two orders of 449.00 tied for 3rd). Davit, Levon and Diana — note Levon:
    """)
    return


@app.cell
def _(engine, mo):
    p3_lateral_top3 = mo.sql(
        f"""
        SELECT c.firstName, c.lastName, top3.orderID, top3.orderTotal
        FROM customers c
        LEFT JOIN LATERAL (SELECT o.orderID, o.orderTotal
                           FROM orders o
                           WHERE o.customerID = c.customerID
                           ORDER BY o.orderTotal DESC, o.orderID
                           LIMIT 3) AS top3 ON true
        WHERE c.customerID IN (2, 24, 27)
        ORDER BY c.customerID, top3.orderTotal DESC
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Predict the row count, then check it:** every customer who ordered has at least 3 orders, so `JOIN LATERAL` should give 28 × 3 = **84**.
    """)
    return


@app.cell
def _(engine, mo):
    p3_lateral_count = mo.sql(
        f"""
        SELECT count(*) AS rows, count(top3.orderID) AS orders
        FROM customers c
        JOIN LATERAL (SELECT o.orderID
                      FROM orders o
                      WHERE o.customerID = c.customerID
                      ORDER BY o.orderTotal DESC, o.orderID
                      LIMIT 3) AS top3 ON true
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    `JOIN LATERAL` is an inner join — Levon and Astghik silently dropped out. `LEFT JOIN LATERAL ... ON true` keeps them: **86** rows, but only **84** orders (Lecture 4's `count(*)` vs. `count(column)`).
    """)
    return


@app.cell
def _(engine, mo):
    p3_lateral_left_count = mo.sql(
        f"""
        SELECT count(*) AS rows, count(top3.orderID) AS orders
        FROM customers c
        LEFT JOIN LATERAL (SELECT o.orderID
                           FROM orders o
                           WHERE o.customerID = c.customerID
                           ORDER BY o.orderTotal DESC, o.orderID
                           LIMIT 3) AS top3 ON true
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 4 — EXISTS / NOT EXISTS

    `EXISTS` is true if the subquery returns at least one row. It never looks at the values.

    **`EXISTS`** — keep the customers for whom at least one order exists: **28**.
    """)
    return


@app.cell
def _(engine, mo):
    p4_exists = mo.sql(
        f"""
        SELECT count(*) AS customers_who_ordered
        FROM customers c
        WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customerID = c.customerID)
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **`NOT EXISTS`** — the opposite: customers with no order at all. Expect **Levon** and **Astghik**, Lecture 4's anti-join answer.
    """)
    return


@app.cell
def _(engine, mo):
    p4_not_exists = mo.sql(
        f"""
        SELECT c.customerID, c.firstName, c.lastName
        FROM customers c
        WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.customerID = c.customerID)
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **What the subquery selects doesn't matter.** `EXISTS` only counts whether a row came back, so even `SELECT NULL` gives **28** — a NULL row is still a row.
    """)
    return


@app.cell
def _(engine, mo):
    p4_select_null = mo.sql(
        f"""
        SELECT count(*) AS customers_who_ordered
        FROM customers c
        WHERE EXISTS (SELECT NULL FROM orders o WHERE o.customerID = c.customerID)
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Managers, with `EXISTS` on the same table.** Keep each employee who appears as someone's `managerID`: **Vahe, Hayk, Marine** — one row each, no join, no `GROUP BY`.
    """)
    return


@app.cell
def _(engine, mo):
    p4_managers = mo.sql(
        f"""
        SELECT m.firstName, m.lastName, m.position
        FROM employees m
        WHERE EXISTS (SELECT 1 FROM employees r WHERE r.managerID = m.employeeID)
        ORDER BY m.employeeID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 4.2 No NULL trap

    Part 2's `NOT EXISTS` found Hayk despite the NULL `employeeID`s: a NULL just fails to match, and `EXISTS` itself is only ever true or false.

    ### 4.3 The trap: the correlation you forgot

    **"Which customers gave us a 1-star rating?"** — the list for an apology email. Here is a version with the line that ties the subquery to `c` missing:
    """)
    return


@app.cell
def _(engine, mo):
    p4_missing_wrong = mo.sql(
        f"""
        SELECT count(*) AS customers
        FROM customers c
        WHERE EXISTS (SELECT 1 FROM orders o
                      WHERE o.rating = 1)
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **What's wrong:** **30** — every customer. The subquery no longer mentions `c`, so it asks the same question for every customer: "does *any* 1-star order exist?" Yes. Levon and Astghik are counted too — and they have never ordered anything.

    **Fix:** correlate it. Expect **4**: Tigran Grigoryan, Narek Manukyan, Vahan Torosyan, Hasmik Zakaryan.
    """)
    return


@app.cell
def _(engine, mo):
    p4_correlated_fix = mo.sql(
        f"""
        SELECT c.customerID, c.firstName, c.lastName
        FROM customers c
        WHERE EXISTS (SELECT 1 FROM orders o
                      WHERE o.customerID = c.customerID
                        AND o.rating = 1)
        ORDER BY c.customerID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **How it happens in real code:** the correlation is there, but unqualified. Inside the subquery, `customerID` means `orders.customerID` on *both* sides — a column compared with itself. **30** again.
    """)
    return


@app.cell
def _(engine, mo):
    p4_unqualified_wrong = mo.sql(
        f"""
        SELECT count(*) AS customers
        FROM customers c
        WHERE EXISTS (SELECT 1 FROM orders
                      WHERE customerID = customerID
                        AND rating = 1)
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **The same rule, nastier — a column the subquery's table doesn't have at all.** `productID` moved from `orders` to `order_items` in this lecture. An old query that still asks `orders` doesn't fail: inside the subquery, `productID` can only mean the outer `products.productID`, so every product is compared with itself. Expect **0** "never ordered" — while Ergonomic Chair Pro never was.
    """)
    return


@app.cell
def _(engine, mo):
    p4_stale_column_wrong = mo.sql(
        f"""
        SELECT count(*) AS never_ordered
        FROM products
        WHERE productID NOT IN (SELECT productID FROM orders)
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **What's wrong:** no error and no rows. Writing `o.productID` would have failed loudly (`column o.productid does not exist`). **Fix:** ask the table that holds the column, as in 2.1 — Ergonomic Chair Pro again.
    """)
    return


@app.cell
def _(engine, mo):
    p4_stale_column_fix = mo.sql(
        f"""
        SELECT productID, productName
        FROM products
        WHERE productID NOT IN (SELECT productID FROM order_items)
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The same slip with `NOT EXISTS` goes the other way: "customers who have never given us 1 star" →
    """)
    return


@app.cell
def _(engine, mo):
    p4_not_exists_wrong = mo.sql(
        f"""
        SELECT count(*) AS customers
        FROM customers c
        WHERE NOT EXISTS (SELECT 1 FROM orders o
                          WHERE o.rating = 1)
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **What's wrong:** **0** — nobody. All-or-nothing (30 or 0) is the tell of an uncorrelated `EXISTS`.

    **Fix:** expect **26** (4 + 26 = 30).
    """)
    return


@app.cell
def _(engine, mo):
    p4_not_exists_fix = mo.sql(
        f"""
        SELECT count(*) AS customers
        FROM customers c
        WHERE NOT EXISTS (SELECT 1 FROM orders o
                          WHERE o.customerID = c.customerID
                            AND o.rating = 1)
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 5 — From subqueries to CTEs

    ### 5.1 A table subquery with a name

    Part 1.4's derived table, rewritten with `WITH`. Same **4** rows — read top to bottom instead of inside out.
    """)
    return


@app.cell
def _(engine, mo):
    p5_cte = mo.sql(
        f"""
        WITH per_customer AS (
            SELECT customerID, count(*) AS order_count
            FROM orders
            GROUP BY customerID
        )
        SELECT c.firstName, c.lastName, pc.order_count
        FROM per_customer pc
        JOIN customers c ON c.customerID = pc.customerID
        WHERE pc.order_count >= 40
        ORDER BY pc.order_count DESC
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 5.2 Several CTEs; a later one reads an earlier one

    `overall` reads `per_customer`. Expect **12** customers above the **21.43** average, Davit (52) down to Tigran Grigoryan (22).
    """)
    return


@app.cell
def _(engine, mo):
    p5_two_ctes = mo.sql(
        f"""
        WITH per_customer AS (
            SELECT customerID, count(*) AS order_count
            FROM orders
            GROUP BY customerID
        ),
        overall AS (
            SELECT avg(order_count) AS avg_count
            FROM per_customer                       -- reads the CTE above
        )
        SELECT c.firstName, c.lastName, pc.order_count,
               round(ov.avg_count, 2) AS avg_count
        FROM per_customer pc
        CROSS JOIN overall ov                       -- one row, so no fan-out
        JOIN customers c ON c.customerID = pc.customerID
        WHERE pc.order_count > ov.avg_count
        ORDER BY pc.order_count DESC
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 5.3 THE TRAP: fan-out in CTE clothing (Lecture 4, 4.10)

    "For each city: completed orders, and average spend per customer." `customer_spend` has one row per **customer**; the query then joins `orders`, one row per **order**.

    > This is the same bug as Lecture 4's `SUM(customers.moneySpent)` fan-out — CTEs don't prevent it, they just make the mistake easier to not notice because the query reads so cleanly.
    """)
    return


@app.cell
def _(engine, mo):
    p5_fanout_wrong = mo.sql(
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
        ORDER BY avg_customer_spend DESC
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **What's wrong:** nothing *looks* wrong — that's the problem. The `orders` column is right. The averages are believable. But each customer's `spent` was copied onto every one of their completed orders before averaging, so big buyers count many times. Abovyan "wins" with 8,507.37.

    **Fix:** keep everything at customer grain — count orders inside the CTE, and never join back to `orders`. Expect Gyumri **6,714.16** on top.
    """)
    return


@app.cell
def _(engine, mo):
    p5_fanout_fix = mo.sql(
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
        ORDER BY avg_customer_spend DESC
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **The checks.** Add the spend back up through the wrong query's join: it should be **157,078.41**, and it's **3,889,069.12** — **529** rows for **28** customers.
    """)
    return


@app.cell
def _(engine, mo):
    p5_fanout_check = mo.sql(
        f"""
        WITH customer_spend AS (
            SELECT customerID, sum(orderTotal) AS spent
            FROM orders
            WHERE status = 'completed'
            GROUP BY customerID
        )
        SELECT sum(cs.spent)                  AS total_spend,
               count(*)                       AS rows,
               count(DISTINCT cs.customerID)  AS customers
        FROM customer_spend cs
        JOIN orders o ON o.customerID = cs.customerID
                     AND o.status = 'completed'
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **The same check on the fixed CTE.** Kept at customer grain, the spend adds up to the known total: **157,078.41** over **28** customers.
    """)
    return


@app.cell
def _(engine, mo):
    p5_fanout_total = mo.sql(
        f"""
        WITH customer_spend AS (
            SELECT customerID, sum(orderTotal) AS spent
            FROM orders
            WHERE status = 'completed'
            GROUP BY customerID
        )
        SELECT sum(spent) AS total_spend, count(*) AS customers
        FROM customer_spend
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 5.4 The trap: ORDER BY inside the CTE

    "Top 5 customers by spend." The sorting is done — inside the CTE.
    """)
    return


@app.cell
def _(engine, mo):
    p5_order_wrong = mo.sql(
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
        LIMIT 5
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **What's wrong:** read the `spent` column — 6,651.60, 8,838.85, 4,084.22 … it isn't descending. These are customers 1–5 by `customerID`. The CTE did sort; the join re-read its rows in its own order, and `LIMIT` took the first five of *that*. Only the outermost `ORDER BY` controls the order you see.

    (Sorting by the grid's column header here would hide the problem — the bug is which 5 rows `LIMIT` picked.) The setup script runs `ANALYZE` so everyone's planner picks this same plan and sees this same wrong order. Without fresh statistics the rows may come out sorted by luck — which is exactly why you can't rely on it.

    **Fix:** `ORDER BY` on the final query. Expect Aram Vardanyan **14,625.38** first — not one name in common with the list above.
    """)
    return


@app.cell
def _(engine, mo):
    p5_order_fix = mo.sql(
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
        LIMIT 5
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 6 — Recursive CTEs (a preview)

    Lecture 4's two-hop self-join, for Nare: **Nare → Hayk → Vahe**. Two hops reach the top because the real chart is only three levels deep.
    """)
    return


@app.cell
def _(engine, mo):
    p6_two_hop = mo.sql(
        f"""
        SELECT e.firstName AS employee, m.firstName AS manager, mm.firstName AS managers_manager
        FROM employees e
        LEFT JOIN employees m  ON m.employeeID  = e.managerID
        LEFT JOIN employees mm ON mm.employeeID = m.managerID
        WHERE e.firstName = 'Nare'
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Add one level: a **hypothetical** trainee, Sevak, reporting to Nare. He is not in the data — the `staff` CTE adds him for this query only. The same two hops now stop at **Hayk**; Vahe is missing and nothing says so.
    """)
    return


@app.cell
def _(engine, mo):
    p6_two_hop_sevak = mo.sql(
        f"""
        WITH staff AS (
            SELECT employeeID, firstName, position, managerID FROM employees
          UNION ALL
            SELECT 9, 'Sevak', 'Trainee', 4                -- 4 = Nare
        )
        SELECT e.firstName AS employee, m.firstName AS manager, mm.firstName AS managers_manager
        FROM staff e
        LEFT JOIN staff m  ON m.employeeID  = e.managerID
        LEFT JOIN staff mm ON mm.employeeID = m.managerID
        WHERE e.firstName = 'Sevak'
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    `WITH RECURSIVE`: a start row, `UNION ALL`, and a step that finds the manager of whoever was found last time — repeated until a step finds nothing. Expect **4** levels: Sevak, Nare, Hayk, Vahe.
    """)
    return


@app.cell
def _(engine, mo):
    p6_recursive = mo.sql(
        f"""
        WITH RECURSIVE staff AS (
            SELECT employeeID, firstName, position, managerID FROM employees
          UNION ALL
            SELECT 9, 'Sevak', 'Trainee', 4
        ),
        chain AS (
            -- start: the employee himself
            SELECT employeeID, firstName, position, managerID, 1 AS level
            FROM staff
            WHERE firstName = 'Sevak'
          UNION ALL
            -- step: the manager of whoever we found last time
            SELECT m.employeeID, m.firstName, m.position, m.managerID, c.level + 1
            FROM staff m
            JOIN chain c ON m.employeeID = c.managerID
        )
        SELECT level, firstName, position
        FROM chain
        ORDER BY level
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **The whole real chart, top down.** Start from the person with no manager (Vahe) and step *down* to direct reports instead of up; `path` records the route. **8** rows over 3 levels — no Sevak, this is the real data.
    """)
    return


@app.cell
def _(engine, mo):
    p6_org_chart = mo.sql(
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
        ORDER BY path
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    > The self-join trick from Lecture 4 doesn't scale past a fixed number of hops — recursive CTEs are the general solution.

    ## Verification drill

    Four queries that run, look fine, and are wrong. Each is followed by what gives it away and the fix.

    **1. "Salespeople who never got a 1-star rating."** A `NOT IN` against the employees on 1-star orders.
    """)
    return


@app.cell
def _(engine, mo):
    d1_wrong = mo.sql(
        f"""
        SELECT e.firstName
        FROM employees e
        WHERE e.employeeID NOT IN (SELECT employeeID FROM orders WHERE rating = 1)
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Gives it away:** 0 rows — every salesperson has a 1-star rating, from only 5 one-star orders all year? **Fix** with `NOT EXISTS`: **5** people.
    """)
    return


@app.cell
def _(engine, mo):
    d1_fix = mo.sql(
        f"""
        SELECT e.firstName
        FROM employees e
        WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.employeeID = e.employeeID AND o.rating = 1)
        ORDER BY e.employeeID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Why:** the 1-star list holds a NULL — **5** one-star orders, only **4** with an employee. One online order is enough to empty the `NOT IN`.
    """)
    return


@app.cell
def _(engine, mo):
    d1_check = mo.sql(
        f"""
        SELECT count(*) AS one_star, count(employeeID) AS with_an_employee
        FROM orders WHERE rating = 1
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **2. "Customers who returned something."** An `EXISTS` with a correlation — or so it looks.
    """)
    return


@app.cell
def _(engine, mo):
    d2_wrong = mo.sql(
        f"""
        SELECT count(*) AS returners
        FROM customers c
        WHERE EXISTS (SELECT 1 FROM orders WHERE customerID = customerID AND status = 'returned')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Gives it away:** **30** includes Levon and Astghik, who never ordered. **Fix:** qualify the correlation — **22**.
    """)
    return


@app.cell
def _(engine, mo):
    d2_fix = mo.sql(
        f"""
        SELECT count(*) AS returners
        FROM customers c
        WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customerID = c.customerID AND o.status = 'returned')
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **3. "Total orders."** Count orders per customer in a CTE, join back to `orders`, add the counts up.
    """)
    return


@app.cell
def _(engine, mo):
    d3_wrong = mo.sql(
        f"""
        WITH customer_orders AS (
            SELECT customerID, count(*) AS order_count
            FROM orders
            GROUP BY customerID
        )
        SELECT sum(co.order_count) AS total_orders
        FROM customer_orders co
        JOIN orders o ON o.customerID = co.customerID
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Gives it away:** you know the total is **600** — the CTE's per-customer count was copied onto every order.
    """)
    return


@app.cell
def _(engine, mo):
    d3_fix = mo.sql(
        f"""
        SELECT count(*) AS total_orders FROM orders
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **4. "Top 3 products."** Rank products by times ordered inside a CTE, then join in the names and take 3.
    """)
    return


@app.cell
def _(engine, mo):
    d4_wrong = mo.sql(
        f"""
        WITH ranked AS (
            SELECT productID, count(*) AS times_ordered
            FROM order_items
            GROUP BY productID
            ORDER BY times_ordered DESC
        )
        SELECT p.productName, r.times_ordered
        FROM ranked r
        JOIN products p ON p.productID = r.productID
        LIMIT 3
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Gives it away:** `times_ordered` isn't descending. **Fix:** `ORDER BY` on the outer query — USB-C Cable 1m (**128** lines) first.
    """)
    return


@app.cell
def _(engine, mo):
    d4_fix = mo.sql(
        f"""
        SELECT p.productName, count(*) AS times_ordered
        FROM order_items i
        JOIN products p ON p.productID = i.productID
        GROUP BY p.productID, p.productName
        ORDER BY times_ordered DESC, p.productName
        LIMIT 3
        """,
        engine=engine
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## Part 7 — Why all of this matters

    | Trap | Looked like | Was |
    |---|---|---|
    | `NOT IN` with a NULL in the list | "nobody has a clean record" — 0 rows | Hayk (1 row) |
    | Cart fan-out (header total summed over its lines) | completed revenue 247,923.72 | 157,078.41 |
    | JOIN where a subquery belonged | accessory orders bring in 29,810.88 | 25,955.91 |
    | `EXISTS` without the correlation | 30 customers gave 1 star | 4 |
    | Fan-out through a CTE | Abovyan has the highest average spend (8,507.37) | Gyumri (6,714.16) |
    | `ORDER BY` inside the CTE | Anna Sargsyan is the top customer | Aram Vardanyan |

    None of them threw an error. Each produced a normal-looking table — an empty list, a revenue figure, a full list, four believable averages, five real customers.

    SQL correctness bugs are almost always silent, and subqueries and CTEs don't change that — a CTE makes a query easier to read, which makes it easier to trust without checking. The checks are the same as last week:

    - **Check against ground truth you already have** — 157,078.41, 600 orders, the two customers with zero orders.
    - **Compare row counts** — `count(*)` vs. `count(column)` finds the NULL that breaks `NOT IN` (27 vs. 22); `count(*)` vs. `count(DISTINCT key)` finds fan-out (844 lines vs. 529 orders; 529 vs. 28 customers). When you can predict a count (28 × 3 = 84 for the LATERAL top-3), check it.
    - **Answer the question two independent ways** — anti-join, `NOT IN` and `NOT EXISTS` should agree.
    - **Look at the column you sorted by.**
    - **All or nothing is suspicious.**

    An AI assistant will write a beautiful three-CTE report whether the logic is right or not. Knowing which number to check is the skill.
    """)
    return


if __name__ == "__main__":
    app.run()
