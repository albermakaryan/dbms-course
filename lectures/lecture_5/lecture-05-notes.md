# Lecture 5 — Subqueries → CTEs: Class Notes

*Scope: subqueries in all four shapes, subqueries vs. joins, correlated subqueries and LATERAL, EXISTS, CTEs, and a first look at recursive CTEs. Grounded throughout in `lecture-05-demo.sql` and Lecture 4's shop, now with multi-product orders (30 customers / 8 employees / 37 products / 600 orders / 965 order lines) — every Demo number below comes from the same-numbered Part of the demo, run against that data.[^demo]*

**The data: Lecture 4's shop, with one realistic change — an order can hold several products.**

**Before (Lecture 4): one product per order.** The order row itself pointed at the product, through a single `productID` column — room for exactly one product.

```mermaid
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
```

**Now: a header and its lines.** The order is split in two, the way real systems store a shopping cart:

```mermaid
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
```

- **`orders`** — the *header*, one row per order: who bought, when, where, status, and `orderTotal`. No product columns any more.
- **`order_items`** — the *lines*, one row per product in an order: `productID`, `quantity`, `unitPrice`, `discountPct`, and `lineTotal` (= quantity × unitPrice, minus the discount). The primary key is `(orderID, productID)`.

**Why it's built this way:**

1. **A real cart holds several products, and one column holds one value.** An order has many products and a product is in many orders: a many-to-many relationship. Lecture 2 drew exactly this in an aside and deferred it — every many-to-many needs a *junction table* in the middle.[^l2] `order_items` is that table.
2. **Why not just one `orders` row per product?** Then an order's customer, date, status and total would repeat on every one of its rows, and `orderID` could no longer be the primary key — the redundancy Lecture 2 normalized away.
3. **Each fact is stored once, at its own grain.** What is true once per *order* (who, when, status) lives in `orders`. What is true once per *product in the order* (which product, how many, at what price) lives in `order_items`. The key `(orderID, productID)` means a product appears at most once per order — buying two is `quantity = 2`, not two lines.
4. **The price is stored on the line.** `unitPrice` records what this order paid, so old orders stay correct when `products.price` changes. (In this data every line happens to be sold at list price.)
5. **The price of the split: two grains.** Joining `orders` to `order_items` gives one row per *line*, with the order's header copied onto each — `orderTotal` included. That is what makes Part 2.3's fan-out possible, and why this lecture keeps asking *"what grain is this table?"*

`orderTotal` is the sum of the order's `lineTotal`s. Every Lecture 4 order kept its product as its first line, and **235** of the 600 orders gained 1–3 more lines (a sleeve or a mouse with a laptop, a cable with a phone…) — **965** lines in all.[^gen]

What you already know still holds, and the lecture leans on it: Levon and Astghik have zero orders. Ergonomic Chair Pro (productID 35) has never been ordered. 181 orders are online, with no employee. Hayk has never had an order cancelled. What changed is every total: completed revenue is now **157,078.41** (it was 145,935.12 when every order held one product). Every query in this lecture answers a question you can check against one of those facts, which is the only way to catch a query that is wrong without an error.

---

## Part 0 — Setup: one script, any starting database

From the `lecture_5/` folder (so the `\copy` paths resolve), start `psql` in any database and run the setup script:

```
psql postgres
\i steps/00-setup.sql
```

It does four things:

1. **Creates the `lecture05` database if it doesn't exist yet.** PostgreSQL has no `CREATE DATABASE IF NOT EXISTS`, so the script uses a psql idiom instead: a `SELECT` that produces the *text* `CREATE DATABASE lecture05` only when `pg_database` has no such database, followed by `\gexec`, which runs whatever text the `SELECT` produced. The first time that's one statement; after that it's nothing, so re-running never errors.
2. **Connects to it** (`\c lecture05`), wherever you started.
3. **Loads the data** — five tables: `customers`, `employees` (with Lecture 4's `managerID` reporting line), `products`, `orders` and `order_items`, from `data/*.csv`. It ends with the row counts: **30 / 8 / 37 / 600 / 965**. (Lecture 4's flat `sales` table isn't used in this lecture and isn't loaded.)
4. **Runs `ANALYZE`**, so PostgreSQL has up-to-date statistics about every table before the first query. The planner chooses join methods from those statistics, and Part 5.4 shows a result whose row *order* depends on the join method — with `ANALYZE`, everyone gets the same plan and sees the same wrong order in class.

Safe to re-run: it drops and recreates every table. The full script is Part 0 of `lecture-05-demo.sql`.

**The notebook.** `lecture-05-notebook.py` walks through the same lecture in marimo, one query per cell, with each trap shown as wrong query → what's wrong → fix. After the setup script, start it with your connection string:

```
LECTURE05_DSN=postgresql://postgres:postgres@localhost:5432/lecture05 marimo edit lecture-05-notebook.py
```

(`postgres:postgres` is the notebook's default — set `LECTURE05_DSN` only if yours differs.)

---

## Part 1 — Subqueries: the basic shapes

A subquery is a `SELECT` inside another statement, in parentheses. What it is allowed to return depends on where you put it, and that gives four shapes:

| Shape | Returns | Typical place |
|---|---|---|
| Scalar | one value | `WHERE price > (...)`, or in `SELECT` |
| Column | one column, many rows | `IN (...)`, `= ANY (...)`, `> ALL (...)` |
| Row | one row, several columns | `WHERE (a, b) = (...)` |
| Table | a whole result | `FROM (...) AS t` |

### 1.1 Scalar subquery — one value

`WHERE price > (SELECT avg(price) FROM products)` runs the inner query, gets one number, and uses it like a constant.

**Demo number:** average price is **280.10**; **12** products are above it (four laptops, three phones, two tablets, two monitors, one pair of headphones).

A scalar subquery works anywhere a single value does — including in `SELECT`, as the denominator of a share: Laptops are **34.0%** of completed revenue (53,412.00 of 157,078.41). Note where each number comes from: revenue *per category* has to be summed from the lines (`order_items.lineTotal`), because one order can hold products from several categories; the total comes from the headers (`orders.orderTotal`). The two agree because `orderTotal` is the sum of its lines.

**Two edge cases, and only one of them is loud:**
- The subquery returns *more than one row* → error: `more than one row returned by a subquery used as an expression`. The demo triggers it by comparing against "the price of a phone" when there are four phones.
- The subquery returns *zero rows* → no error. The result is NULL[^scalar], `price > NULL` is never true, and the query quietly returns **0 rows**. The demo asks for products dearer than an 'iPhone 16' that isn't in the table.

Too many rows is an error. Zero rows is a silent empty result. That asymmetry is the first instance of today's theme.

### 1.2 Column subquery — IN, ANY, ALL

You already wrote one: the fix for Lecture 4's drill was `WHERE customerID IN (SELECT customerID FROM orders WHERE ... December ...)`.

**Demo numbers:** the `IN` version counts **26** customers who ordered in December. The `JOIN` version of the same question returns **86** rows — one per December order, not one per customer.

That difference is the main reason to reach for `IN`: it only asks *"is this customer on the list?"* Each outer row comes out at most once, however many times it appears in the list. A join pairs rows, so a customer with five December orders comes out five times. (This is exactly why the `IN` version fixed Lecture 4's fan-out.)

- `= ANY (subquery)` is `IN` under another name — also **26**.
- `> ALL (subquery)` — greater than *every* value. Products dearer than every phone (the dearest is 799.00) → **3** laptops.
- `> ANY (subquery)` — greater than *at least one* value. Products dearer than the cheapest phone (249.00) → **13**.

One oddity worth a sentence in class: `> ALL` over an *empty* subquery is true for every row.[^all] "Dearer than every product in an empty category" — everything qualifies.

### 1.3 Row subquery — rare, mention briefly

Compares several columns at once: `WHERE (customerID, orderDate) = (SELECT customerID, orderDate FROM orders WHERE orderID = 1595)` — every order by the same customer on the same day as order 1595.

**Demo number:** **2** orders — Armen Gevorgyan ordered twice on 2024-12-28 (orders 1595 and 1596). Useful occasionally; you will mostly see the other three shapes.

### 1.4 Table subquery — a derived table in FROM

Some questions need an aggregate of an aggregate: "how many orders does a customer place, on average?" `avg(count(*))` is an error (`aggregate function calls cannot be nested`). The fix is to compute the inner aggregate in a subquery in `FROM`, then treat its result as a table:

```sql
SELECT round(avg(order_count), 2), count(*)
FROM (SELECT customerID, count(*) AS order_count
      FROM orders GROUP BY customerID) AS per_customer;
```

**Demo number:** **21.43** orders per customer, over **28** customers. Not 30: Levon and Astghik have no orders, so they never appear in the derived table. 21.43 = 600 / 28. Over all 30 customers on the books it would be 20.00. Neither is wrong — but they answer different questions, and the query doesn't tell you which one you asked.

Filtering the derived table like any other table: customers with 40+ orders → **4** (Davit 52, Armen 48, Karen 41, Aram 40).

Always give a derived table an alias. PostgreSQL 16 started allowing you to leave it out[^alias], but the SQL standard requires it and older versions reject the query.

---

## Part 2 — Subqueries vs. JOINs: the equivalence, and where it breaks

### 2.1 One question, three queries

"Which products have never been ordered?" Lecture 4 answered it with an anti-join. Now three ways:

| Version | Query shape | Result |
|---|---|---|
| Anti-join (Lecture 4) | `LEFT JOIN order_items i ... WHERE i.orderID IS NULL` | productID 35, Ergonomic Chair Pro |
| `NOT IN` | `WHERE productID NOT IN (SELECT productID FROM order_items)` | productID 35, Ergonomic Chair Pro |
| `NOT EXISTS` | `WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.productID = p.productID)` | productID 35, Ergonomic Chair Pro |

Products are on the order *lines* now, so all three ask `order_items`.

**Demo number:** all three return the same **1** row. Comparing two independent methods for the same answer is a verification habit in its own right — and here they agree.

They agree *here* because `order_items.productID` is `NOT NULL`. Change the question so the subquery's column can be NULL, and one of the three stops working.

### 2.2 The NOT IN trap — a deliberate callback to Lecture 4's anti-join

Lecture 4 taught the anti-join as *the* way to ask "which X have no Y". `NOT IN` looks like an easier way to write it. It isn't safe, and the reason is NULL.

**In miniature first.** `5 NOT IN (1, 2, NULL)` means `5 <> 1 AND 5 <> 2 AND 5 <> NULL`. The last comparison is neither true nor false — it's NULL (unknown) — and `true AND true AND NULL` is NULL. `WHERE NULL` keeps nothing.

**Demo numbers:** `5 NOT IN (1, 2)` → true. `5 NOT IN (1, 2, NULL)` → NULL. `2 NOT IN (1, 2, NULL)` → false. A `NOT IN` whose list contains a NULL can return false or NULL, but never true — for any row.[^notin]

**On the real data.** "Which salespeople have never had an order cancelled?" — a clean record, worth a bonus.

```sql
SELECT e.employeeID, e.firstName, e.lastName
FROM employees e
WHERE e.employeeID NOT IN (SELECT o.employeeID FROM orders o
                           WHERE o.status = 'cancelled');
```

**Demo number:** **0 rows**. No error. The report says nobody has a clean record.

Why: **27** cancelled orders, but only **22** have an employee. The other 5 were online — `employeeID` is NULL, the same 181-online-orders NULL from Lecture 4 — and one NULL in the list is enough.

**The fixes, all returning the same 1 row — Hayk Melikyan (employeeID 5):**
1. `NOT EXISTS (SELECT 1 FROM orders o WHERE o.employeeID = e.employeeID AND o.status = 'cancelled')` — the recommended one; see Part 4.
2. Keep `NOT IN`, but add `AND o.employeeID IS NOT NULL` inside the subquery.
3. Lecture 4's anti-join — with the status test in `ON`, not `WHERE` (Lecture 4's WHERE-vs-ON lesson: in `WHERE` it would delete the NULL-padded rows the anti-join depends on).

**The rule to give students:** never write `NOT IN (subquery)` unless the column is declared `NOT NULL`. Write `NOT EXISTS` instead. The positive form, `IN`, is fine — `x IN (..., NULL)` is still true when `x` is in the list.

### 2.3 The cart fan-out — joining the lines multiplies the header

This is the fan-out students will meet at work. An order has one header row and one or more line rows. Join them, and every header column — `orderTotal` included — is copied onto every line of that order. It is Lecture 4's `moneySpent` fan-out (4.10) one level down: order grain joined to line grain.

"Completed revenue, and how many units we sold." Units live on the lines, so someone joins them in:

```sql
SELECT sum(o.orderTotal) AS revenue, sum(i.quantity) AS units
FROM orders o
JOIN order_items i ON i.orderID = o.orderID
WHERE o.status = 'completed';
```

**Demo number (wrong):** revenue **247,923.72**, units **1,174**. The units are right. The revenue is not, and nothing errors.

**The checks that catch it:**
- The revenue without the join is **157,078.41**.
- `count(*)` = **844** rows, `count(DISTINCT o.orderID)` = **529** orders. An order with three lines had its total added three times: **90,845.31** of revenue that doesn't exist.

**Two fixes, both giving 157,078.41 and 1,174 units:**
1. **Sum what lives on the line** — `sum(i.lineTotal)` instead of the header's `orderTotal`.
2. **Aggregate the lines per order first** — a table subquery (1.4) `(SELECT orderID, sum(quantity) AS units FROM order_items GROUP BY orderID)`, so there is one row per order before the join, and nothing can be copied.

### 2.4 Where a subquery is simply the right tool

"Revenue from orders that include at least one accessory." The JOIN version filters the lines to accessories and sums the order totals — and an order with *two* accessories (a sleeve and a mouse) matches twice.

**Demo numbers:** JOIN → **29,810.88** over "155 orders" — but 155 is the number of accessory *lines*. `EXISTS (SELECT 1 FROM order_items i JOIN products p ... WHERE i.orderID = o.orderID AND p.category = 'Accessories')` → **25,955.91** over **142** orders. Thirteen orders hold two accessories, and the JOIN counted each of them twice (3,854.97 too much).

`EXISTS` asks "is there at least one accessory line?", so each order is kept or dropped, never repeated. When the question is "which X have *any* Y", a subquery (`IN` / `EXISTS`) is not just an alternative to a join — it's the version that can't multiply rows.

---

## Part 3 — Correlated vs. non-correlated subqueries

### 3.1 Non-correlated — the subquery runs on its own

`(SELECT avg(price) FROM products)` doesn't mention the outer query at all. Select just the inner query and run it: you get 280.10. It is computed once, and the outer query uses that one number.

### 3.2 Correlated — the subquery mentions the outer row

"Products priced above *their own category's* average":

```sql
SELECT p.productName, p.category, p.price
FROM products p
WHERE p.price > (SELECT avg(p2.price) FROM products p2
                 WHERE p2.category = p.category);
```

`p.category` belongs to the *outer* query. The subquery's answer is different for every outer row, so conceptually it re-runs once per row, with that row's values filled in as constants.[^scalar]

**Demo number:** **19** products, versus **12** against the overall average. Chairs has one product, which can't beat its own average. Select just the inner query and run it alone, and it fails: `missing FROM-clause entry for table "p"` — the quickest test of whether a subquery is correlated.

### 3.3 Each customer against their own history

"Customers whose most recent order was bigger than their own average order" needs two correlated subqueries — one picks each customer's latest order (by date and time), one computes that customer's average.

**Demo number:** **10** of the 28 customers with orders. Top of the list: Artur Baghdasaryan's last order (1588, 1,358.30) against his average of 355.32.

### 3.4 A correlated subquery and a self-join are two tools for the same shape

Lecture 4's self-join compared each employee to their manager — a related row from the same table. A correlated subquery does the same thing, with different syntax.

"Who was hired before their own manager?"
- Self-join: `JOIN employees m ON m.employeeID = e.managerID WHERE e.hireDate < m.hireDate`
- Correlated: `WHERE e.hireDate < (SELECT m.hireDate FROM employees m WHERE m.employeeID = e.managerID)`

**Demo number:** both return **1** row — Marine (hired 2016-08-01), who joined before her manager Vahe (2017-02-01).

**Where they differ:** a correlated subquery in `SELECT` never removes an outer row. When it finds nothing, it returns NULL — it behaves like a `LEFT JOIN`, not an inner join. Lecture 4's self-join + `GROUP BY` counted direct reports for the **3** people who have any; a correlated `(SELECT count(*) FROM employees r WHERE r.managerID = e.employeeID)` lists all **8** employees, with 0 for the five who manage nobody, and NULL as Vahe's manager.

### 3.5 LATERAL — a correlated subquery in FROM

A correlated subquery in `SELECT` has a hard limit: one value per outer row. Two questions go past it:

- **Several columns:** "each customer's latest order — its id, date, channel and total." Ask a `SELECT` subquery for two columns and it errors: `subquery must return only one column`.
- **Several rows:** "each customer's 3 biggest orders." A scalar subquery can't return three rows at all.

A subquery in `FROM` has no such limit — it's a whole table. But normally it can't see the other tables in `FROM`: it is evaluated once, on its own. Write `JOIN (SELECT ... WHERE o.customerID = c.customerID ...)` and PostgreSQL refuses: `invalid reference to FROM-clause entry for table "c"`. PostgreSQL 16 and later even add the fix to the message: *"To reference that table, you must mark this subquery with LATERAL."*

`LATERAL` is that mark. It lets a subquery in `FROM` use columns from the tables listed before it, and PostgreSQL evaluates it once for each of their rows[^lateral] — a correlated subquery that returns a whole table:

```sql
SELECT c.firstName, c.lastName, latest.*
FROM customers c
JOIN LATERAL (SELECT o.orderID, o.orderDate, o.channel, o.orderTotal
              FROM orders o
              WHERE o.customerID = c.customerID
              ORDER BY o.orderDate DESC, o.orderTime DESC
              LIMIT 1) AS latest ON true;
```

`ON true` because the matching already happened inside the subquery (`WHERE o.customerID = c.customerID`) — there is nothing left to compare.

**Demo number:** **28** rows, one per customer who has ordered, with all four columns. Top of the list: Artur Baghdasaryan's order 1588, in store, for 1,358.30 — the same last order 3.3 found with a subquery in `WHERE`, but now every column comes back in one join.

**Top N per group** — the classic use. Change `LIMIT 1` to `LIMIT 3` and order by `orderTotal DESC`, and you get each customer's three biggest orders: Davit's are 1,000.00, 904.99 and 747.89.

**Two habits from earlier lectures apply directly:**
- **Predict the row count.** Every customer who ordered has at least 3 orders (the fewest is Diana with 4), so the result must be 28 × 3 = **84** rows — and it is. If it weren't, something would be wrong.
- **`JOIN LATERAL` is an inner join.** Levon and Astghik have no orders, so the subquery returns nothing for them and they silently disappear — the same silent drop as Lecture 4's inner join. `LEFT JOIN LATERAL ... ON true` keeps them: **86** rows, `count(*)` = 86 vs. `count(orderID)` = 84, the two NULL-padded rows being Levon and Astghik. Lecture 4's `count(*)` vs. `count(column)` check, unchanged.

One detail for the top-N query: `ORDER BY o.orderTotal DESC, o.orderID`. The `orderID` breaks ties. Suren has two orders of 449.00 tied for the third spot. Without a tiebreaker, which of the two lands in the top 3 is up to the plan, and could change from one run to the next. `LIMIT` after an `ORDER BY` with ties is only well defined if the order is complete.

---

## Part 4 — EXISTS / NOT EXISTS

### 4.1 "Is there at least one?"

`EXISTS (subquery)` is true if the subquery returns at least one row, false otherwise. It never looks at the row's values — it can stop at the first match.[^exists]

**Demo numbers:** `EXISTS` → **28** customers with at least one order. `NOT EXISTS` → **2**: Levon Arakelyan and Astghik Danielyan — the same two as Lecture 4's anti-join. Managers via `EXISTS` on `employees` itself → **3** (Vahe, Hayk, Marine), one row each, no `GROUP BY` needed.

What the subquery selects doesn't matter. `EXISTS (SELECT NULL FROM ...)` still gives **28** — a NULL row is still a row. `SELECT 1` is just the common convention.[^exists]

### 4.2 No NULL trap

Part 2's `NOT EXISTS` found Hayk even though 5 of the cancelled orders have no employee. For those rows, `o.employeeID = e.employeeID` is NULL, so they simply don't match. And `EXISTS` itself only ever returns true or false — never NULL — so `NOT EXISTS` never turns into "unknown" the way `NOT IN` does. Same question, same data, same NULLs: `NOT IN` → 0 rows, `NOT EXISTS` → the right answer.

### 4.3 The trap: the correlation you forgot

"Which customers gave us a 1-star rating?" — the list for an apology email.

**Demo number (right):** **4** customers — Tigran Grigoryan, Narek Manukyan, Vahan Torosyan, Hasmik Zakaryan.

Now drop the line that ties the subquery to the outer row:

```sql
SELECT count(*) FROM customers c
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.rating = 1);
```

**Demo number (wrong):** **30**. The subquery no longer mentions `c`, so it asks the same question for every customer — "does *any* 1-star order exist?" — and the answer is always yes. Every customer passes, including Levon and Astghik, who have never ordered anything. The apology goes to the whole customer list.

**How it actually happens in real code** — the correlation is there, but unqualified: `WHERE customerID = customerID`. Inside the subquery the nearest table with a `customerID` column is `orders`, so both sides mean `orders.customerID`, and the condition compares a column to itself. Demo number: **30** again.

**The same rule, nastier: a column the subquery's table doesn't have at all.** In this lecture `productID` moved from `orders` to `order_items`. An old query that still says `WHERE productID NOT IN (SELECT productID FROM orders)` does *not* fail: `orders` has no `productID`, so inside the subquery the name can only mean the outer `products.productID`, and every product is compared with itself. **Demo number:** **0** products never ordered — while Ergonomic Chair Pro has never been ordered. Writing `o.productID` would have failed loudly (`column o.productid does not exist`). Qualify every column inside a subquery.

**With `NOT EXISTS` the same slip goes the other way:** "customers who have never given us 1 star" → **0** (wrong) instead of **26** (right). 4 + 26 = 30 — a quick check that the two halves add up.

**The tell:** an uncorrelated `EXISTS` is all-or-nothing — every row passes or none does. If an `EXISTS` filter returns *all* of the table or *none* of it, check the correlation first. And check the result against something you know: a list of 1-star raters that includes two people with zero orders cannot be right.

---

## Part 5 — From subqueries to CTEs: same idea, different shape

### 5.1 A table subquery with a name

`WITH name AS (...)` defines a result you can use like a table, for one query only.[^with] It is a table subquery with the subquery moved to the top and given a name:

```sql
WITH per_customer AS (
    SELECT customerID, count(*) AS order_count
    FROM orders
    GROUP BY customerID
)
SELECT c.firstName, c.lastName, pc.order_count
FROM per_customer pc
JOIN customers c ON c.customerID = pc.customerID
WHERE pc.order_count >= 40;
```

**Demo number:** the same **4** rows as Part 1.4. Nothing about the result changes. What changes is reading order: top to bottom ("first count orders per customer, then look up their names") instead of inside out.

### 5.2 Several CTEs, a later one reading an earlier one

Separate CTEs with commas. Each can read the ones above it:

```sql
WITH per_customer AS (...),
     overall AS (SELECT avg(order_count) AS avg_count FROM per_customer)
SELECT ... FROM per_customer pc CROSS JOIN overall ov ...
WHERE pc.order_count > ov.avg_count;
```

**Demo number:** **12** customers order more often than the average customer (21.43 — Part 1.4's number again), from Davit (52) down to Tigran Grigoryan (22). The `CROSS JOIN` is safe here: `overall` has exactly one row, so it can't multiply anything.

### 5.3 The fan-out trap, in CTE clothing — the most important section of this lecture

This is Lecture 4's fan-out (4.10), unchanged, inside a query that looks much tidier.

The question: "For each city: how many completed orders, and the average spend per customer." A natural way to write it — one CTE for spend per customer, then join `orders` to count the orders:

```sql
WITH customer_spend AS (
    SELECT customerID, sum(orderTotal) AS spent
    FROM orders WHERE status = 'completed'
    GROUP BY customerID
)
SELECT c.city,
       count(o.orderID)        AS orders,
       round(avg(cs.spent), 2) AS avg_customer_spend
FROM customers c
JOIN customer_spend cs ON cs.customerID = c.customerID
JOIN orders o          ON o.customerID  = c.customerID AND o.status = 'completed'
GROUP BY c.city;
```

`customer_spend` is at **customer grain** — one row per customer. `orders` is at **order grain**. Joining them copies each customer's `spent` onto every one of their completed orders, exactly the way Lecture 4's join copied `customers.moneySpent` onto every order.

**Demo numbers (wrong):** Abovyan **8,507.37**, Gyumri **7,908.41**, Yerevan **7,063.81**, Vanadzor **5,976.08**. The `orders` column (29, 181, 280, 39) is correct. Every number is believable. Nothing errors.

**The checks that catch it:**
- Add the spend back up through the same join: **3,889,069.12**, against the known **157,078.41** (Part 2.3).
- `count(*)` = **529** rows, `count(DISTINCT customerID)` = **28** customers. Each customer's total was counted once per completed order, so the average was weighted toward the customers with the most orders.

**Demo numbers (fixed):** keep everything at customer grain — count the orders inside the CTE too, and never join back to `orders`: Gyumri **6,714.16**, Abovyan **6,136.27**, Yerevan **5,189.36**, Vanadzor **4,793.83**. The `orders` column is unchanged, and the fixed CTE adds up to **157,078.41** over 28 customers.

The ranking changed: the wrong report says Abovyan customers spend the most, the right one says Gyumri. A decision made from the first report would be wrong, and nothing in the report shows it.

> **This is the same bug as Lecture 4's `SUM(customers.moneySpent)` fan-out — CTEs don't prevent it, they just make the mistake easier to not notice because the query reads so cleanly.**

The question from Lecture 4 applies unchanged, with one word added: *"Is the thing I'm aggregating — **including anything that came out of a CTE** — at the same grain as the rows I'm joining through?"* A CTE has a grain like any table. Name it to yourself when you write it ("one row per customer"), and be suspicious of any join that brings a finer-grained table back in afterwards.

### 5.4 The trap: "I sorted it in the CTE"

"Top 5 customers by spend." The sorting is done — inside the CTE — and the outer query joins in names and takes 5:

```sql
WITH top_spenders AS (
    SELECT customerID, sum(orderTotal) AS spent
    FROM orders WHERE status = 'completed'
    GROUP BY customerID
    ORDER BY spent DESC
)
SELECT c.firstName, c.lastName, t.spent
FROM top_spenders t
JOIN customers c ON c.customerID = t.customerID
LIMIT 5;
```

**Demo number (wrong):** Anna Sargsyan 6,651.60, Davit Petrosyan 8,838.85, Mariam Hakobyan 4,084.22, Tigran Grigoryan 5,762.87, Lusine Avetisyan 2,861.90 — customers 1 to 5 in `customerID` order. The CTE did sort its rows; the join then read them in its own order, and `LIMIT` took the first five of *that*. (`EXPLAIN` shows it: the sorted CTE goes into a hash table, and the output follows the scan of `customers`.)

**Demo number (fixed):** `ORDER BY t.spent DESC` on the outer query → Aram Vardanyan 14,625.38, Artur Baghdasaryan 11,235.95, Armen Gevorgyan 10,028.09, Lilit Hovhannisyan 9,410.64, Vahan Torosyan 8,925.87. Not one name in common with the wrong list.

**The rule:** only the `ORDER BY` of the query whose output you are looking at controls the order you see. Without one, PostgreSQL returns rows "in an unspecified order … it must not be relied on."[^order] An `ORDER BY` inside a CTE or subquery may *happen* to survive — it often does in a simple query — which is what makes this dangerous: it works in testing and breaks when the data, the statistics or the plan changes. (The setup script runs `ANALYZE` so everyone's planner makes the same choice and sees the same wrong order in class.)

This is the same family of misconception as "does the order of columns in `GROUP BY` change my result?" from Lecture 4 (4.14): it doesn't — and an `ORDER BY` in the wrong place doesn't do what it looks like it does. Order is a property of the final output, requested once, at the end.

**Quick check that catches it:** read the column you think you sorted by. 6,651.60 → 8,838.85 → 4,084.22 is not descending.

---

## Part 6 — Recursive CTEs (a preview, not the full story)

Lecture 4 walked the management chain with self-joins: one join for "manager", a second for "manager's manager". Each extra level needs one more join — the query hard-codes the depth.

**Demo number:** for Nare, the two-hop self-join gives Nare → Hayk → Vahe. That reaches the top, because the shop's chart is only three levels deep.

**Add one level and it falls short.** The demo adds a *hypothetical* trainee, Sevak, reporting to Nare — not in the data; a CTE (`staff` = `employees` plus one extra row) adds him for that query only, and nothing is saved. Now the same two-hop self-join gives Sevak → Nare → Hayk, and stops. Vahe is missing, and nothing in the result says so.

**`WITH RECURSIVE`** is the general solution: a starting query, `UNION ALL`, and a step that joins back to the CTE's own previous output.[^recursive]

```sql
WITH RECURSIVE chain AS (
    SELECT employeeID, firstName, managerID, 1 AS level       -- start: the employee
    FROM staff WHERE firstName = 'Sevak'
  UNION ALL
    SELECT m.employeeID, m.firstName, m.managerID, c.level + 1 -- step: their manager
    FROM staff m JOIN chain c ON m.employeeID = c.managerID
)
SELECT level, firstName FROM chain ORDER BY level;
```

**Demo number:** **4** levels — Sevak, Nare, Hayk, Vahe. The step runs again and again, each time finding the manager of the rows found last time. It stops by itself when a step finds nothing: Vahe's `managerID` is NULL, so the join returns no row.

The same shape, started from the top (`WHERE managerID IS NULL`) and walking down, prints the whole real chart in one query: **8** rows across 3 levels, with a path like `Vahe > Hayk > Nare`.

One warning, and that's all for today: if the data contains a cycle (A reports to B, B reports to A), the step never runs out of rows and the query never finishes.[^recursive] Recursive CTEs get a proper treatment later; today's point is only this:

> **The self-join trick from Lecture 4 doesn't scale past a fixed number of hops — recursive CTEs are the general solution.**

---

## Part 7 — Why all of this matters (the one idea to leave the room with)

Look back at the traps from today:

| Trap | Looked like | Was |
|---|---|---|
| `NOT IN` with a NULL in the list | "nobody has a clean record" — 0 rows | Hayk (1 row) |
| Cart fan-out (header total summed over its lines) | completed revenue 247,923.72 | 157,078.41 |
| JOIN where a subquery belonged | accessory orders bring in 29,810.88 | 25,955.91 |
| `EXISTS` without the correlation | 30 customers gave 1 star | 4 |
| Fan-out through a CTE | Abovyan has the highest average spend (8,507.37) | Gyumri (6,714.16) |
| `ORDER BY` inside the CTE | Anna Sargsyan is the top customer | Aram Vardanyan |

None of them threw an error. Every one produced a result that looked like a completely normal table — an empty list, a revenue figure, a full list, four believable averages, five real customers with real totals.

**That's the same point as Lecture 4, and it will be the point of every lecture:** SQL correctness bugs are almost always silent. Subqueries and CTEs don't change that. A CTE makes a query *easier to read*, and that makes it easier to trust without checking. The checks are the same ones as last week:

- **Check against ground truth you already have.** A 1-star list containing Levon and Astghik, a revenue that isn't 157,078.41, an order count that isn't 600 — each is caught in seconds by someone who knows those numbers.
- **Compare row counts.** `count(*)` vs. `count(column)` on the subquery's column catches the NULL that breaks `NOT IN` (27 vs. 22). `count(*)` vs. `count(DISTINCT key)` after a join catches fan-out (844 lines vs. 529 orders; 529 vs. 28 customers). And when you can predict a row count — 28 customers × 3 orders = 84 for the LATERAL top-3 — check it.
- **Answer the question two independent ways.** Anti-join, `NOT IN`, `NOT EXISTS` should agree; when one disagrees, it's the one to distrust.
- **Look at the column you sorted by.** If it isn't in order, your `ORDER BY` is in the wrong place.
- **All or nothing is suspicious.** A filter that keeps every row or no rows usually isn't filtering what you think.

An AI assistant will write a correlated `EXISTS`, a `NOT IN`, or a three-CTE report that reads beautifully, whether the logic is right or not. Knowing which number to check is the skill.

---

## Open questions / TODO

Each item in the brief's TODO list, answered in order, then other things worth knowing.

**From the brief's list**

- **Lecture 4 files and schema: found, and they match the brief** (tables, columns, nullable `employeeID`, CHECK constraints, 600 / 30 / 8 / 37 / 600, and the listed facts) — with one exception: the brief says "Davit has 8 orders"; he has **52**. Arpine Simonyan and Mher Sargsyan have 8. Nothing here uses the "8" claim.
- **The dataset is deliberately NOT identical to Lecture 4's — changed on request, against the brief.** The brief said to reuse Lecture 4's data unchanged; `TODO.md` ("Add multi-product orders") asked for real carts, and you confirmed that every example should use the new schema. So Lecture 5 has its own data, made by `generate_data.py` from the original one-product-per-order CSVs in `lectures/lecture_3/data/` (byte-identical to Lecture 4's; not modified):
  - `orders` is now a header (no `productID`, `quantity`, `unitPrice`, `discountPct` — they moved to the lines); `order_items` holds one row per product per order, with a stored `lineTotal`. `orderTotal` = sum of the lines; `customers.moneySpent` was recomputed the same way as Lecture 3's generator.
  - Every Lecture 4 order kept its product as its first line; 235 of 600 orders gained 1–3 add-on lines (965 lines). Seeded, so re-running the script reproduces the files exactly.
  - **Kept on purpose:** the 600 orders with their customers, employees, dates, channels, statuses and ratings; customers, employees and products byte-identical; Levon and Astghik with no orders; productID 35 never added, so still never ordered; 181 online orders without an employee.
  - **Changed:** every total. Completed revenue is **157,078.41** (Lecture 4: 145,935.12), and every spend, average and share built on totals moved with it. Students who remember 145,935.12 should be told why it changed — that's the opening of the notes.
  - Lecture 4's flat `sales` table and star schema are not loaded; no Lecture 5 query uses them.
  - TODO.md's open question ("what happens to `orders.productID` … once lines exist") is answered by *moving* those columns, not keeping copies on the header.
- **Traps: all reproduce on the real data, with no constructed tables.** NOT IN/NULL: 0 rows instead of Hayk. Omitted-correlation EXISTS: 30 customers instead of 4 (and 0 instead of 26 for NOT EXISTS). CTE fan-out: believable averages that rank Abovyan first instead of Gyumri. New with the multi-product data: the cart fan-out (247,923.72 instead of 157,078.41) and the JOIN-instead-of-EXISTS double count (29,810.88 instead of 25,955.91). The ORDER BY-inside-a-CTE trap also reproduces, with one caveat (see below). The NOT IN case uses the real NULLs (5 online cancelled orders); the only constructed example is the miniature `5 NOT IN (1, 2, NULL)`.
- **Recursive CTE: the real hierarchy is too shallow, so a synthetic extension is used.** The real chart has 3 levels (Vahe → Hayk/Marine → Nare/Lilit/Arman), so Lecture 4's two-hop self-join already reaches the top for everyone. Part 6 adds a hypothetical trainee, Sevak, reporting to Nare, *inside a CTE*, so no table is changed. Say out loud in class that Sevak is invented.
- **Estimated numbers: none in the files.** One shortcut to report: while drafting, I wrote two Part 7 drill comments (the fan-out "Total orders" and the "Top 3 products" list) *before* running them, and both guesses were wrong. Running the draft caught them, and the comments were replaced with real output before the demo file was assembled. After that, every number in the notes, demo, Q&A and notebook was checked by a run (see the last bullet).
- **Style deviations from `lecture-04-notes.md`:** (1) footnotes citing the PostgreSQL documentation, following the "every statement gets a source" preference; Lecture 4's notes don't have them. (2) A few short SQL blocks and three small tables, which Lecture 4's notes mostly avoid, because the subquery shapes are hard to describe in prose alone. (3) The notes are longer than Lecture 4's (seven Parts plus a TODO section).
- **Notebook connection: works, but not the way the brief described.** The brief asked for SQLAlchemy/psycopg2. Neither is installed, so the notebook uses `psycopg` 3, which `pyproject.toml` declares and your Chinook notebook uses. It reads `LECTURE05_DSN` (default `postgresql://postgres:postgres@localhost:5432/lecture05`). It does not load data itself: run `psql postgres`, then `\i steps/00-setup.sql` first, because `\copy` is a psql command. The five error-on-purpose statements are Python cells that catch the error and show PostgreSQL's message, so the notebook runs top to bottom; every other query is a native `mo.sql` cell.
- **Notebook vs. notes/demo: no disagreement.** Each notebook SQL cell is copied word for word from the demo by a generator script, which fails if any demo statement is missing. Run against a database loaded by the setup script, all 70 SQL cells returned exactly the values written in the notes and demo, on PostgreSQL 14, 16 and 18. **Numbers did change, on purpose:** the switch to multi-product orders moved every total (see the dataset bullet above). The notes, demo, steps, Q&A and notebook were all re-run and rewritten against the new data, so they agree with each other — but not with the first version of this lecture, or with Lecture 4's 145,935.12. Earlier non-data fixes: `ANALYZE` was added to the setup script (next bullet), and the demo header's count of wrong-on-purpose queries was corrected (now thirteen).
- **LATERAL (3.5) was added after the first version, on request.** It adds two error-on-purpose statements (five in total) and four queries, checked the same way as everything else on PostgreSQL 14, 16 and 18. The only version difference in the whole demo is in one of those errors: PostgreSQL 16 and later add the hint *"To reference that table, you must mark this subquery with LATERAL"*; PostgreSQL 14 prints a more generic hint. The demo comment says so.

**Also worth knowing**

- **The ORDER BY-inside-CTE trap depends on the query plan.** On a freshly loaded database, *before* PostgreSQL has gathered statistics, the planner can choose a plan that happens to keep the CTE's order: the Part 7 drill's version came out correctly sorted on one run and scrambled on the next. Fix: `steps/00-setup.sql` now ends with `ANALYZE` (Lecture 4's setup doesn't have it). With it, the whole demo returns identical results on fresh PostgreSQL 14, 16 and 18, and both ORDER BY traps scramble on all three. A student who skips the setup script might see a correctly ordered result. That is the lesson itself ("may happen to survive"), but be ready for it.
- **The setup script creates the database.** `steps/00-setup.sql` (and Part 0 of the demo) creates `lecture05` if it doesn't exist (`SELECT ... \gexec`, since PostgreSQL has no `CREATE DATABASE IF NOT EXISTS`) and connects to it with `\c`. Tested on a fresh server: database missing, already present, and started from inside `lecture05`.
- **The notebook was run, not opened.** It was checked with `marimo check`, `marimo export html` (which runs every cell in marimo's runtime) and `app.run()`. It has not been opened in the `marimo edit` browser UI. Click through it once before class.
- **One spot breaks the notebook's wrong → explanation → fix pattern.** In Part 4.3, the extra "unqualified `customerID = customerID`" variant is followed by an explanation but not by a fix cell of its own. Its fix is the correlated query shown just before it. The four main traps all follow the pattern.
- **Folder name.** The brief asked for `lecture-05/`; the files are in `lectures/lecture_5/` to match `lecture_2` … `lecture_4` and the README's layout. Besides the four requested files, the folder has `data/` (this lecture's own CSVs from `generate_data.py`, plus `all_inserts.sql`) and `steps/00-…07-…` (the demo split by Part), because every earlier lecture has them and the demo's Part 0 loads from `data/`.
- **No `joins-qa-rehearsal.md` exists** in this repository (I searched the whole tree), so `lecture-05-qa-rehearsal.md` follows the brief's description ("easiest to hardest, short answers, ending on a synthesis question") rather than a template. Check whether it matches what you had in mind.

[^demo]: `lecture-05-demo.sql` (also split per Part in `steps/`), run on PostgreSQL 14, 16 and 18 against Lecture 4's data; every result identical on all three (one error message's hint is worded differently on 14; see the TODO section).
[^scalar]: PostgreSQL 16 documentation, §4.2.11 "Scalar Subqueries": "It is an error to use a query that returns more than one row or more than one column as a scalar subquery. (But if, during a particular execution, the subquery returns no rows, there is no error; the scalar result is taken to be null.) The subquery can refer to variables from the surrounding query, which will act as constants during any one evaluation of the subquery." https://www.postgresql.org/docs/16/sql-expressions.html#SQL-SYNTAX-SCALAR-SUBQUERIES
[^all]: PostgreSQL 16 documentation, §9.23.5 "ALL": "The result of ALL is 'true' if all rows yield true (including the case where the subquery returns no rows)." https://www.postgresql.org/docs/16/functions-subquery.html
[^alias]: PostgreSQL 16 release notes: "Allow subqueries in the FROM clause to omit aliases." https://www.postgresql.org/docs/release/16.0/ — and §7.2.1.3: "According to the SQL standard, a table alias name must be supplied for a subquery. PostgreSQL allows AS and the alias to be omitted, but writing one is good practice in SQL code that might be ported to another system." https://www.postgresql.org/docs/16/queries-table-expressions.html
[^notin]: PostgreSQL 16 documentation, §9.23.3 "NOT IN": "if the left-hand expression yields null, or if there are no equal right-hand values and at least one right-hand row yields null, the result of the NOT IN construct will be null, not true." https://www.postgresql.org/docs/16/functions-subquery.html
[^exists]: PostgreSQL 16 documentation, §9.23.1 "EXISTS": "The subquery will generally only be executed long enough to determine whether at least one row is returned, not all the way to completion. … Since the result depends only on whether any rows are returned, and not on the contents of those rows, the output list of the subquery is normally unimportant. A common coding convention is to write all EXISTS tests in the form EXISTS(SELECT 1 WHERE ...)." https://www.postgresql.org/docs/16/functions-subquery.html
[^with]: PostgreSQL 16 documentation, §7.8 "WITH Queries": "These statements, which are often referred to as Common Table Expressions or CTEs, can be thought of as defining temporary tables that exist just for one query." https://www.postgresql.org/docs/16/queries-with.html
[^order]: PostgreSQL 16 documentation, §7.5 "Sorting Rows": "If sorting is not chosen, the rows will be returned in an unspecified order. The actual order in that case will depend on the scan and join plan types and the order on disk, but it must not be relied on." https://www.postgresql.org/docs/16/queries-order.html
[^l2]: `lectures/lecture_2/lecture-02-notes.md`, "Optional aside: what if one order could hold several products?" — the same `ORDERS ||--|{ ORDER_ITEMS` / `PRODUCTS ||--o{ ORDER_ITEMS` diagram, and: "Every M:N relationship you'll ever model resolves to this same trick: a junction table in the middle."
[^gen]: `generate_data.py` in this folder: reads the original one-product-per-order CSVs (`lectures/lecture_3/data/`, byte-identical to the ones Lecture 4 started from), keeps every order's product as its first line, adds 1–3 commonly-bought-together products to about 4 in 10 orders (seeded), and recomputes `orderTotal` and `moneySpent`. Counts from `steps/00-setup.sql` (30 / 8 / 37 / 600 / 965) and the demo.
[^lateral]: PostgreSQL 16 documentation, §7.2.1.5 "LATERAL Subqueries": "Subqueries appearing in FROM can be preceded by the key word LATERAL. This allows them to reference columns provided by preceding FROM items. (Without LATERAL, each subquery is evaluated independently and so cannot cross-reference any other FROM item.)" … "for each row of the FROM item providing the cross-referenced column(s) … the LATERAL item is evaluated using that row or row set's values of the columns." … "It is often particularly handy to LEFT JOIN to a LATERAL subquery, so that source rows will appear in the result even if the LATERAL subquery produces no rows for them." https://www.postgresql.org/docs/16/queries-table-expressions.html#QUERIES-LATERAL
[^recursive]: PostgreSQL 16 documentation, §7.8.2 "Recursive Queries": the form is "a non-recursive term, then UNION (or UNION ALL), then a recursive term", evaluated repeatedly "so long as the working table is not empty"; and "it is important to be sure that the recursive part of the query will eventually return no tuples, or else the query will loop indefinitely." https://www.postgresql.org/docs/16/queries-with.html
