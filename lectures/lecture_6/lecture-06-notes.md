# Lecture 6 — Window Functions: Class Notes

*Scope: what a window function is, the parts of `OVER()`, ranking functions, top-N per group, `lag`/`lead` and their relatives, window frames, and how windows interact with NULLs, joins, `FILTER` and the star schema. Grounded throughout in `lecture-06-demo.sql` and the same shop data as Lectures 4 and 5 (30 customers / 8 employees / 37 products / 600 orders / 965 order lines, plus Lecture 4's star schema). Every Demo number below comes from the same-numbered Part of the demo, run against that data.[^demo]*

**The data: nothing new.** The same five CSV files as Lectures 4 and 5 (byte-identical copies in `data/`): `orders` is the header (one row per order, with `orderTotal`), `order_items` the lines (one row per product in an order, with `lineTotal`). The setup script also rebuilds Lecture 4's star schema (`dim_date`, `dim_customer`, `dim_product`, `dim_employee`, `fact_sales` at line grain), using the same statements, because Part 7 uses it.

What you already know, and this lecture checks against: 600 orders, 529 of them completed. Completed revenue **157,078.41**. Levon and Astghik have zero orders. Ergonomic Chair Pro (productID 35) was never ordered. 181 orders are online, with no employee. Completed revenue without the online orders is **100,222.48**, the figure Lecture 4's inner join produced (4.2).

**One sentence to carry through the lecture:**

> **A window function computes over a set of related rows, but does not collapse them: every input row survives.**[^tutorial]

---

## Part 0 — Setup: one script, any starting database

From the `lecture_6/` folder, start `psql` in any database and run the setup script:

```
psql postgres
\i steps/00-setup.sql
```

It does what Lecture 5's did: **drops and recreates the `lecture06` database** (so start `psql` in another database, since PostgreSQL can't drop the one you're connected to), connects to it, loads the five tables, sets Lecture 4's `managerID` reporting line, and runs `ANALYZE`. One addition: it then **rebuilds Lecture 4's star schema** with the same statements as Lecture 4's Part 4. It ends with the row counts: **30 / 8 / 37 / 600 / 965**, and **366** dates and **965** fact rows.

`ANALYZE` matters more this week than last. Five results below depend on how PostgreSQL happens to order tied rows (Parts 2.4, 3.2, 3.3, 4.4 and 4.6). With fresh statistics everyone gets the same plan, and the same arbitrary answer, in class.

**Version.** The demo needs **PostgreSQL 11 or later**.

| Feature | Since |
|---|---|
| Window functions, `OVER`, `WINDOW` | 8.4[^v84] |
| `FILTER` on aggregates, including window aggregates | 9.4[^v94] |
| `GROUPS` frames, `RANGE` with an offset (`INTERVAL '6 days' PRECEDING`) | 11[^v11] |
| `DISTINCT ON` | an old PostgreSQL extension, not standard SQL[^distincton] |

Checked on PostgreSQL 14, 16 and 18: every result is identical, including the arbitrary ones.

**The notebook.** `lecture-06-notebook.py` walks through the lecture in marimo, as in Lecture 5:

```
LECTURE06_DSN=postgresql://postgres:postgres@localhost:5432/lecture06 marimo edit lecture-06-notebook.py
```

---

## Part 1 — The problem windows solve

### 1.1 GROUP BY collapses the rows

`GROUP BY customerID` gives one row per customer. The orders themselves are gone: 529 completed orders in, **28** rows out. Often you need both: *each order next to its customer's total*, or *each order as a share of all revenue*. Keep `orderID` in the `SELECT` and the database refuses: `column "orders.orderid" must appear in the GROUP BY clause or be used in an aggregate function`.

### 1.2 Before windows: join an aggregate back, or correlate

Two tools from Lecture 5 do it:

- **A derived table at customer grain, joined back** to the orders (Lecture 5, 1.4). It works, but it's a join, so it is safe only because the right side has one row per customer, and you have to check that every time.
- **A correlated subquery in `SELECT`** (Lecture 5, Part 3). The `status = 'completed'` filter has to be written twice, once in each query. Forget the inner one and the total silently includes returned and cancelled orders.

**Demo number:** both give customer 1 (Anna Sargsyan) **6,651.60** on each of her completed orders.

### 1.3 The window version

```sql
SELECT orderID, customerID, orderTotal,
       sum(orderTotal) OVER (PARTITION BY customerID) AS customer_total
FROM orders
WHERE status = 'completed';
```

`OVER (PARTITION BY customerID)` means "sum over the rows that share this row's `customerID`". **Demo number:** the same 6,651.60, with no join and the filter written once. (Part 7.5 proves the three versions agree on every row.)

### 1.4 The invariant: rows in = rows out

A query whose only addition is window functions returns exactly as many rows as its input. **Demo number:** three windows over three different groupings (`OVER ()`, by customer, by status) on all orders: **600 in, 600 out**. Predict the row count, then check it. This invariant comes back throughout the lecture.

### 1.5 Callback: why there is no fan-out

Lecture 4 (4.10) put each customer's `moneySpent` next to their orders with a join, and the join copied it onto every order: **30** customers became **600** rows, and `sum(c.moneySpent)` came out at **4,386,925.27**.

A window moves the other way. It brings a group's number *to the rows already there* and never adds a row. `sum(moneySpent) OVER ()` on `customers`: **30 in, 30 out**, and the total is **157,078.41**. Windows can't fan out, because they don't join. (They don't repair a fan-out that's already there either. See 7.3.)

---

## Part 2 — Anatomy of OVER()

```
function(...) OVER (PARTITION BY ...   which rows belong together
                    ORDER BY ...       in what order, inside each group
                    frame)             which of those rows this row sees
```

### 2.1 `OVER ()`: the whole result is one window

Each completed order as a share of completed revenue: `100 * orderTotal / sum(orderTotal) OVER ()`.

**Demo numbers:** the three 2,500.00 orders (1158, 1363, 1385) are **1.59%** each. Check: over all 529 rows the shares add up to **100.00**.

#### Real problem: which single orders matter for the whole year?

**Task:** Finance wants every completed order that on its own brought in more than 1% of the year's completed revenue — how many there are, and how much of the year they make up together.

**Solution:** compute each order's share with sum() OVER () in a derived table, then filter on the share outside (filtering on a window needs a subquery — Part 4.1 explains why).

```sql
SELECT count(*)                AS big_orders,
       sum(orderTotal)         AS their_revenue,
       round(sum(pct), 2)      AS pct_of_year
FROM (SELECT orderTotal,
             100 * orderTotal / sum(orderTotal) OVER () AS pct
      FROM orders
      WHERE status = 'completed') AS shares
WHERE pct > 1;
```

**Demo numbers:** 9 of the 529 completed orders — under 2% of the orders — bring in 11.72% of the year's revenue.

### 2.2 `PARTITION BY`: one window per group

Lusine Avetisyan (customer 5) has 4 completed orders. Each next to her total, her share, her average and the difference from it:

**Demo numbers:** total **2,861.90**, average **715.48**. Order 1276 (1,598.00) is **55.8%** of her spending and **+882.53** above her average; order 1373 (24.40) is **−691.08** below it. `count`, `min` and `max` work the same way (4, 24.40, 1,598.00): any ordinary aggregate becomes a window function when `OVER` follows it.[^funcs]

#### Real problem: customers who depend on one big purchase

**Task:** Marketing wants the customers for whom a single order is more than half of everything they spent with us — "one-off buyers" who need a reason to come back.

**Solution:** each order's share of ITS customer's total, with PARTITION BY customerID; keep the orders above 50%.

```sql
SELECT c.firstName, c.lastName, s.orderID, s.orderTotal, s.customer_total,
       round(100 * s.orderTotal / s.customer_total, 1) AS pct_of_customer
FROM (SELECT customerID, orderID, orderTotal,
             sum(orderTotal) OVER (PARTITION BY customerID) AS customer_total
      FROM orders
      WHERE status = 'completed') AS s
JOIN customers c ON c.customerID = s.customerID
WHERE s.orderTotal > 0.5 * s.customer_total
ORDER BY pct_of_customer DESC;
```

**Demo numbers:** 4 customers. Lusine is one of them — her order 1276 is the 55.8% from the example above.

### 2.3 `ORDER BY` inside `OVER`

Add `ORDER BY orderDate, orderID` inside `OVER`, and `sum()` becomes a **running** sum: **1,598.00 → 2,660.50 → 2,684.90 → 2,861.90**. Each row sees the rows up to itself. Part 6 covers why that is the default and where the default goes wrong.

**Why `, orderID`?** Lusine never ordered twice on one day, so for her the tie-breaker changes nothing, and it's tempting to drop it. Davit (customer 2) ordered more than once on four different days. His running total computed both ways, shown for 12 November. The date filter sits *outside*, in a subquery, so both totals still count from January; a `WHERE` on the dates would restart them (2.5):

```sql
SELECT orderID, orderDate, orderTime, orderTotal, by_date_only, by_date_and_id
FROM (SELECT orderID, orderDate, orderTime, orderTotal,
             sum(orderTotal) OVER (PARTITION BY customerID
                                   ORDER BY orderDate)          AS by_date_only,
             sum(orderTotal) OVER (PARTITION BY customerID
                                   ORDER BY orderDate, orderID) AS by_date_and_id
      FROM orders
      WHERE status = 'completed' AND customerID = 2) AS running
WHERE orderDate BETWEEN '2024-11-11' AND '2024-11-13'
ORDER BY orderDate, orderID;
```

| orderID | orderTime | orderTotal | `ORDER BY orderDate` | `ORDER BY orderDate, orderID` |
|---|---|---|---|---|
| 1466 | 06:34 | 25.50 | **5,607.71** | 5,551.47 |
| 1467 | 12:44 | 38.00 | **5,607.71** | 5,589.47 |
| 1471 | 18:05 | 18.24 | **5,607.71** | 5,607.71 |

- **By date only**, the three orders of 12 November are *peers*: they share the same `ORDER BY` value, and the default frame takes all peers at once. So order 1466's "running total" already includes 1467 and 1471, which came later that day, and the figure looks stuck for three rows.
- **With `orderID` added**, no two rows share a position, so each row adds only itself. The day still ends on 5,607.71; only the rows in between change.

**Demo number:** **5 of Davit's 43** completed orders get a different running total: the earlier orders on each day with more than one order. The rest match, which is why the tie-breaker seems to "make no difference" until a day with two orders comes along.

**The rule:** whenever the window's order can have ties, end it with a unique column. `orderTime` is the more meaningful choice within a day; `orderID` guarantees uniqueness. Part 6.2 shows the same effect on the whole year's running total.

#### Real problem: when did each customer reach Gold status?

**Task:** the loyalty programme makes a customer "Gold" on the day their completed spending, added up order by order, first reaches 5,000. For each customer who got there: on which date?

**Solution:** a running total per customer (PARTITION BY customerID, ORDER BY date, time, id); then, per customer, the first date where it is 5,000 or more. (The ORDER BY is unique — no ties — so the default frame is safe here; Part 6 explains why that matters.)

```sql
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
ORDER BY gold_since;
```

**Demo numbers:** 14 of the 28 customers reached Gold during the year, the first on 2024-04-26 and the last on 2024-11-22.

### 2.4 The trap: `ORDER BY` inside `OVER` is not the query's `ORDER BY`

> **New function: `row_number()`** — numbers the rows of each window 1, 2, 3 … in the order of the window's `ORDER BY`. Every row gets a different number, even rows that tie, and which of two tied rows comes first is not guaranteed.[^funcs]

"The year's first five completed orders, numbered":

```sql
SELECT orderID, orderDate, orderTotal,
       row_number() OVER (ORDER BY orderDate, orderID) AS nr
FROM orders
WHERE status = 'completed'
LIMIT 5;
```

**Demo number:** orders 1001–1005, numbered 1–5. It looks right, but only by luck: PostgreSQL sorted the rows by date to number them, and nothing after that sort changed their order.

> **New function: `rank()`** — the row's position in the window's `ORDER BY`. Tied rows share a position, and the positions after a tie are skipped: 1, 2, 2, 4.[^funcs]

A colleague adds one column, `rank() OVER (ORDER BY orderTotal DESC) AS size_rank`, *before* `nr` in the `SELECT` list. Nothing else changes.

**Demo number (wrong):** orders **1385, 1158, 1363, 1314, 1542**, with `nr` 341, 135, 321, 276, 481. These are the five *biggest* orders, not the first five of the year. The rows now come out in whatever order the *last* window's sort left them. No error.

**Fix:** `ORDER BY nr` on the query itself brings back orders 1001–1005. The PostgreSQL tutorial says it directly: "The window `ORDER BY` does not even have to match the order in which the rows are output."[^tutorial] Without a query-level `ORDER BY`, rows come back "in an unspecified order".[^order]

This is the same family as Lecture 5's "I sorted it in the CTE" (5.4). An `ORDER BY` anywhere except the end of the outer query sorts *something*, but not your output.

### 2.5 When do window functions run?

```mermaid
flowchart LR
    A[FROM / JOIN] --> B[WHERE] --> C[GROUP BY] --> D[HAVING] --> E[window functions] --> F[SELECT list] --> G[DISTINCT] --> H[ORDER BY] --> I[LIMIT]
    style E fill:#d6efd6,stroke:#2e7d32
```

Window functions "logically execute after" `WHERE`, `GROUP BY` and `HAVING`, and that's why they are allowed only in the `SELECT` list and `ORDER BY`.[^tutorial] Two consequences, both in this lecture:

1. **A window sees only the rows `WHERE` kept.** "What share of *all* completed revenue did Lusine bring in?", answered with `WHERE customerID = 5` and `sum(orderTotal) OVER ()`, gives **55.84, 37.13, 0.85, 6.18**. Those add up to 100: they are shares of *her own* revenue, because `WHERE` removed everyone else before the window ran. No error. **Fix:** compute the window over all completed orders in a derived table, then filter outside: **1.02, 0.68, 0.02, 0.11** (her 2,861.90 is 1.82% of 157,078.41).
2. **You can't filter on a window in `WHERE`.** That one is loud (Part 4.1).

### 2.6 Windows over aggregates

Since windows run after `GROUP BY`, they can rank the groups: `rank() OVER (ORDER BY sum(orderTotal) DESC)`.

**Demo numbers:** customers ranked by completed revenue: Aram Vardanyan (8) **14,625.38**, **9.3%** of all, then Artur (20) 11,235.95, Armen (12) 10,028.09, Lilit (10) 9,410.64, Vahan (14) 8,925.87. That's Lecture 5's top 5 (5.4), now with ranks and shares.

The share is written `sum(sum(orderTotal)) OVER ()`. It reads strangely but is legal: the inner `sum` is the `GROUP BY` aggregate (one per customer), and the outer `sum ... OVER ()` adds those 28 totals across the window. Warn students it confuses people. The readable version aggregates in a CTE first and windows over the CTE. Same five rows.

### 2.7 Named windows

Four functions over the same window? Write it once: `... OVER w ... WINDOW w AS (PARTITION BY customerID)`. A named window is the tutorial's fix for "duplicative and error-prone" repeated `OVER` clauses.[^tutorial] **Demo numbers:** 4, 2,861.90, 715.48, 1,598.00, as in 2.2.

---

## Part 3 — Ranking functions

| Function | Ties | Customers by order count, rows 7–10 |
|---|---|---|
| `row_number()` | different numbers, in an arbitrary order | 7, 8, 9, 10 |
| `rank()` | same number, then a gap | 7, 8, 8, 10 |
| `dense_rank()` | same number, no gap | 7, 8, 8, 9 |

`rank` is "the row_number of the first row in its peer group"; `dense_rank` "effectively counts peer groups".[^funcs]

### 3.0 Six rows first

Before the real data: six made-up rows with two pairs of ties (ids 2 and 3 both scored 85; ids 4 and 5 both 70), ordered by score from high to low. Two windows: `w` orders by score only, so `rank` and the others can *see* the ties; `wt` adds `id` as a tie-breaker for `row_number` and `ntile`, which always split ties, so the split is predictable.

> **New function: `dense_rank()`** — like `rank()`, but nothing is skipped after a tie: 1, 2, 2, 3. It counts distinct values.[^funcs]

> **New function: `ntile(n)`** — deals the rows of each window, in order, into n buckets numbered 1 to n, as equal in size as possible.[^funcs]

> **New function: `percent_rank()`** — the row's relative position, from 0 (first) to 1 (last): (rank − 1) / (rows − 1).[^funcs]

> **New function: `cume_dist()`** — the share of the window's rows that come at or before this row, ties included: from 1/N to 1.[^funcs]

```sql
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
ORDER BY id;
```

**The three ranks, row by row:**

| id | score | `row_number`: count the rows in order | `rank`: 1 + rows with a *higher* score | `dense_rank`: 1 + *distinct* higher scores |
|---|---|---|---|---|
| 1 | 90 | 1 | 1 + 0 = **1** | 1 + 0 = **1** |
| 2 | 85 | 2 | 1 + 1 (id 1) = **2** | 1 + 1 (90) = **2** |
| 3 | 85 | 3 — tied with id 2; only the id puts it second | 1 + 1 (id 1) = **2** | 1 + 1 (90) = **2** |
| 4 | 70 | 4 | 1 + 3 (ids 1, 2, 3) = **4** | 1 + 2 (90, 85) = **3** |
| 5 | 70 | 5 | 1 + 3 (ids 1, 2, 3) = **4** | 1 + 2 (90, 85) = **3** |
| 6 | 60 | 6 | 1 + 5 (ids 1–5) = **6** | 1 + 3 (90, 85, 70) = **4** |

`rank` skips 3 and 5: two rows share 2nd place, so the next row is 4th. `dense_rank` never skips: it numbers the distinct scores 90, 85, 70, 60 as 1, 2, 3, 4.

**The distribution functions, row by row:**

| id | `ntile(3)`: 6 rows into 3 buckets of 2, in order | `percent_rank` = (rank − 1) / (6 − 1) | `cume_dist` = rows with a score ≥ this one / 6 |
|---|---|---|---|
| 1 | 1 | (1 − 1) / 5 = **0.000** | 1 / 6 = **0.167** |
| 2 | 1 | (2 − 1) / 5 = **0.200** | 3 / 6 = **0.500** |
| 3 | **2** — its tie partner id 2 is in bucket 1 | (2 − 1) / 5 = **0.200** | 3 / 6 = **0.500** |
| 4 | 2 | (4 − 1) / 5 = **0.600** | 5 / 6 = **0.833** |
| 5 | **3** — its tie partner id 4 is in bucket 2 | (4 − 1) / 5 = **0.600** | 5 / 6 = **0.833** |
| 6 | 3 | (6 − 1) / 5 = **1.000** | 6 / 6 = **1.000** |

`ntile`, like `row_number`, cuts wherever the count says, even through a tie. `percent_rank` and `cume_dist` give tied rows the same value.

**`PARTITION BY` restarts the numbering.** The same six rows split into group A (ids 1–3) and group B (ids 4–6), with `rank() OVER (ORDER BY score DESC)` next to `rank() OVER (PARTITION BY grp ORDER BY score DESC)`:

| id | grp | rank overall | rank in group | Why |
|---|---|---|---|---|
| 4 | B | 4 | **1** | overall, three rows score higher; inside group B, none do |
| 5 | B | 4 | **1** | tied with id 4 |
| 6 | B | 6 | **3** | inside group B, only ids 4 and 5 score higher: 1 + 2 = 3 |

**What a tie-breaker does to `rank`.** `rank() OVER (ORDER BY score DESC, id)` gives **1, 2, 3, 4, 5, 6**, exactly `row_number`: no two rows are equal on (score, id), so there are no ties left to share a place. A tie-breaker is right for `row_number` and `ntile` (it makes the split predictable) and wrong for `rank` and `dense_rank`, whose whole job is to show ties. 3.3 shows what happens to `row_number` *without* a tie-breaker, on the real data.

### 3.1 The three side by side, on real ties

The customer league table by number of orders, all 30 customers (Lecture 4's `LEFT JOIN` keeps the two with none). The data has **five genuine ties**: Narek Manukyan and Lilit Hovhannisyan (**29** orders each), Mariam Hakobyan and Hayk Melikyan (16), Meline Poghosyan and Ani Stepanyan (10), Arpine Simonyan and Mher Sargsyan (8), and Levon and Astghik (0).

**Demo numbers:** Ruben (30) is 7th in all three. Narek and Lilit get `row_number` 8 and 9, `rank` 8 and 8, `dense_rank` 8 and 8. Anna Sargsyan (28) is then `row_number` 10, `rank` **10** (a gap: there is no 9th), `dense_rank` **9**. At the bottom, Levon and Astghik share `rank` 29.

#### Real problem: salesperson of the month

**Task:** each month, the salesperson with the highest completed revenue gets a bonus. If two people tie, both get it. Who won each month, and who won most often?

**Solution:** revenue per salesperson per month (GROUP BY), then rank() inside each month (PARTITION BY month), keep rank 1. rank, not row_number: a tie must give two winners, not one picked at random.

```sql
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
ORDER BY month;
```

**Demo numbers:** 12 months, 12 winners — no month had a tie. Ani won 5 months, Hayk 3, Gor 2, Vahe and Arman 1 each. (The online orders are left out on purpose: the bonus is for people. Part 7.1.)

### 3.2 `ntile`, `percent_rank`, `cume_dist` — briefly

- `ntile(4)` deals the 30 customers into quartiles of 8, 8, 7, 7, in order. **Demo number (wrong, if quartiles should group equal customers):** Narek and Lilit, both with 29 orders, land in **different** quartiles (1 and 2). The bucket boundary falls between rows 8 and 9, and `ntile`, like `row_number`, splits a tie wherever it falls.
- `percent_rank` and `cume_dist` treat ties as equals. **Demo:** Narek's `cume_dist` is **0.300**: 9 of 30 customers have 29 orders or more.

#### Real problem: four customer tiers for a campaign

**Task:** split the customers who bought something into 4 equal-sized tiers by completed spending, so each tier gets its own offer. For each tier: how many customers, their spending range, and their revenue.

**Solution:** spending per customer, ntile(4) over it, then GROUP BY tier.

```sql
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
ORDER BY tier;
```

**Demo numbers:** 28 customers, 7 per tier. Tier 1 alone brings in 71,059.04 — 45% of the 157,078.41. (No two customers spent exactly the same, so no tie is split here; the customerID tie-breaker is there in case one ever is.)

#### Real problem: the 80/20 check on products

**Task:** "20% of our products bring 80% of our revenue" — is that true here? Which products make up the top 20% by revenue, and how much do they bring in?

**Solution:** revenue per product (from Lecture 4's star), cume_dist() over it from the top; the top 20% are the rows with cume_dist <= 0.2.

```sql
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
ORDER BY revenue DESC;
```

```sql
SELECT sum(revenue) AS top_20pct_revenue,
       round(100 * sum(revenue)
             / (SELECT sum(revenue) FROM fact_sales WHERE status = 'completed'), 1) AS pct_of_revenue
FROM (SELECT sum(f.revenue) AS revenue,
             cume_dist() OVER (ORDER BY sum(f.revenue) DESC) AS share_at_or_above
      FROM fact_sales f
      WHERE f.status = 'completed'
      GROUP BY f.productKey) AS placed
WHERE share_at_or_above <= 0.2;
```

**Demo numbers:** 7 of the 36 products that sold — 20% — bring in 80,843.35, 51.5% of revenue. Not 80/20 here; more like 20/50.

### 3.3 The trap: `row_number()` on ties is arbitrary

"A loyalty gift for our top 8 customers by number of orders." Two analysts write `row_number() OVER (ORDER BY count(*) DESC)` and keep rows 1–8, using a derived table (Part 4 explains why that's needed):

- **Analyst A** counts from `orders`, then joins the names.
- **Analyst B** starts from `customers LEFT JOIN orders`, as Lecture 4 taught.

**Demo numbers (wrong):** A's 8th customer is **Lilit Hovhannisyan**; B's is **Narek Manukyan**. Same question, same window, two different gift lists. Both have 29 orders. `row_number` had to put one of them first and took whichever its sort met first, which depends on the plan, not on anything in the query. Neither result looks wrong on its own. (This is reproducible: identical on PostgreSQL 14, 16 and 18 after the setup script.)

It's the same family as the `LIMIT 1` tie trap from the Chinook lab: in Chinook the best-selling track is a **256-way tie**, with 256 tracks sold twice each.[^chinook] Whenever "the first N" cuts through a tie, the cut is arbitrary.

**Two fixes. Choose one deliberately:**
1. **Make the order complete.** Add a unique tie-breaker: `ORDER BY count(o.orderID) DESC, c.customerID`. Now every run and every plan gives Narek 8th. But "lower customerID wins" has become a business rule. Say so, or use a tie-breaker that means something (revenue).
2. **Don't hide the tie.** `rank() <= 8` returns **9** customers, everyone tied for 8th, and the decision goes back to a person.

### 3.4 Gaps or no gaps: which one answers "top 2"?

"The two best-selling products in each category get the front shelf." Times ordered = order lines per product.

**Demo numbers:** the real ties: Audio has AirPods Pro and Soundcore Q30 at **28** each, then Flip 6 at 27. Monitors has UltraSharp 27 (19), then ProArt 24 and Odyssey G5 32 at **10** each. Phones has iPhone 15 (14), then Galaxy S24 and Redmi Note 13 at **11** each. Storage has USB Flash 128GB (82), then Portable SSD and Expansion HDD at **28** each.

How many products go on the "top 2" shelf (13 categories, Chairs with only one product):

| Filter | Products | Why |
|---|---|---|
| `row_number() <= 2` | **25** | exactly 2 per category, but in Monitors, Phones and Storage one of two tied products is dropped *arbitrarily* |
| `rank() <= 2` | **28** | ties for 2nd place are all kept: +1 each in Monitors, Phones, Storage |
| `dense_rank() <= 2` | **29** | also Flip 6 in Audio: two products tie for "1st", so the 27 is "2nd" |

`rank() <= N` can return more than N rows, but only when there's a tie at the cut, and then the extra rows are honest. `dense_rank() <= N` answers "the top N *distinct values*", not "the top N products". It returned an extra product in Audio, where the tie was at the top, not at the cut. For "top N things", use `row_number` with a complete tie-breaker, or `rank` if ties should share the place. Use `dense_rank` only when you mean distinct values.

---

## Part 4 — Top-N per group (the flagship use case)

"Each customer's latest order": the last time we heard from each customer. It's one of the most common window questions at work, and there are three ways to answer it.

### 4.1 The loud one: a window function in `WHERE`

```sql
SELECT customerID, orderID, orderDate,
       row_number() OVER (PARTITION BY customerID
                          ORDER BY orderDate DESC, orderTime DESC, orderID DESC) AS rn
FROM orders
WHERE rn = 1;
```

**Demo:** `ERROR:  column "rn" does not exist`. Put the function itself in `WHERE`, and you get `ERROR:  window functions are not allowed in WHERE`. Both errors are Part 2.5's picture: `WHERE` runs before window functions exist.[^tutorial]

This is the one window mistake that **errors**. Contrast it with every other trap today, which return a plausible table.

### 4.2 Method 1: `row_number()` in a CTE, filter outside

Lecture 5's CTE is the fix: compute the window in one step, and filter in the next, where `rn` is an ordinary column. That's also what the PostgreSQL tutorial recommends ("you can use a sub-select").[^tutorial]

```sql
WITH ranked AS (
    SELECT customerID, orderID, orderDate, orderTime, orderTotal,
           row_number() OVER (PARTITION BY customerID
                              ORDER BY orderDate DESC, orderTime DESC, orderID DESC) AS rn
    FROM orders
)
SELECT customerID, orderID, orderDate, orderTime, orderTotal
FROM ranked
WHERE rn = 1;
```

**Demo number:** **28** rows. Anna Sargsyan's latest is order 1591 (2024-12-27, 19:27). Levon and Astghik are missing: they have no rows in `orders`, so they have no partition.

### 4.3 Method 2: `LEFT JOIN LATERAL ... LIMIT 1`

Lecture 5, 3.5: a correlated subquery in `FROM`, with `ORDER BY ... LIMIT 1` inside.

**Demo numbers:** **30** rows, `count(orderID)` = **28**: Levon and Astghik are kept, with NULLs.

**The silent trap: `JOIN LATERAL` (inner) drops them.** Same subquery, `JOIN` instead of `LEFT JOIN`: **30 customers in, 28 out**, no error. For "when did we last hear from each customer?", the two who never ordered are exactly the two you most need to see.

### 4.4 Method 3: `DISTINCT ON` (PostgreSQL only)

```sql
SELECT DISTINCT ON (customerID) customerID, orderID, orderDate, orderTime, orderTotal
FROM orders
ORDER BY customerID, orderDate DESC, orderTime DESC, orderID DESC;
```

"Keep the first row of each `customerID`, in this order." **Demo number:** 28 rows, the same orders. It's the shortest of the three, and it isn't standard SQL: the docs call it "an extension of the SQL standard".[^distincton] The `row_number` version is the one that ports.

Two ways to get it wrong:
- **Loud:** an `ORDER BY` that doesn't start with the `DISTINCT ON` columns → `ERROR:  SELECT DISTINCT ON expressions must match initial ORDER BY expressions`.[^distincton] (The brief expected this to be silent. In PostgreSQL it is an error.)
- **Silent:** `ORDER BY customerID` and nothing more. Then "the first row of each set is unpredictable".[^distincton] **Demo number (wrong):** customer 1 gets order **1071** from February. No error.

### 4.5 Prove the three agree: `EXCEPT` both ways

For each pair of methods, count the rows in one and not in the other (Lecture 5, 6.5). Inner `LATERAL` is used here, so all three cover the same 28 customers.

**Demo number:** **0, 0, 0, 0**: row_number vs LATERAL and row_number vs DISTINCT ON, in both directions.

### 4.6 The trap: an incomplete `ORDER BY`

Write "latest" as `ORDER BY orderDate DESC` and nothing else, in all three methods. Two customers placed two orders on their last day: Anna Sargsyan (1589 at 15:23 and 1591 at 19:27 on 2024-12-27) and Armen Gevorgyan (1595 at 12:06 and 1596 at 14:28 on 2024-12-28).

**Demo numbers (wrong):**

| | row_number | LATERAL | DISTINCT ON | right answer |
|---|---|---|---|---|
| Anna (1) | 1591 | **1589** | 1591 | 1591 |
| Armen (12) | **1595** | **1595** | **1595** | 1596 |

It's wrong in two different ways:
- **Anna:** the methods *disagree*, and an `EXCEPT` check between row_number and LATERAL catches it.
- **Armen:** all three *agree*, and all three are wrong. An `EXCEPT` check says "identical". **Two methods agreeing proves something only when each method's question has exactly one answer.** With an incomplete order, they can agree by accident.

The same `LIMIT` lesson as Lecture 5, 3.5: `LIMIT` (or `rn = 1`, or `DISTINCT ON`) after an order with ties is well defined only if the order is complete. **Fix:** `orderDate DESC, orderTime DESC, orderID DESC`, so the last key is unique.

### 4.7 Top 2

`DISTINCT ON` can keep only one row per group. The other two methods just change a number: `rn <= 2`, or `LIMIT 2`.

**Demo numbers:** predict first: every customer who ordered has at least 4 orders (Diana), so **28 × 2 = 56**. `row_number`: **56** rows, 28 customers. `LEFT JOIN LATERAL ... LIMIT 2`: **58** rows, 56 of them orders, plus Levon and Astghik.

### 4.8 When to use which

- **`row_number()` in a CTE**: the default. It's standard SQL, works for any N, and the window can carry other columns (rank, share) at the same time.
- **`LEFT JOIN LATERAL`**: when you start from the parent table and must keep parents with no children, or the per-group query is complex (its own joins and filters).
- **`DISTINCT ON`**: a quick top-1 in PostgreSQL. It doesn't port and can't do N > 1.

---

## Part 5 — Looking sideways: lag, lead, first_value, nth_value

Functions that read a value from *another* row of the window. (`last_value` has a trap of its own, in Part 6.)

### 5.1 Order over order

> **New function: `lag(x)`** — the value of `x` from the *previous* row of the window, in its `ORDER BY`. NULL when there is no previous row.[^funcs]

Lusine's completed orders, each with the change from the one before: **NULL, −535.50, −1,038.10, +152.60**. The first row has no previous row, so `lag` gives NULL, and the change is NULL. That NULL is honest: there was nothing to compare with.

#### Real problem: customers who went quiet

**Task:** customer service wants every time a customer went more than 90 days without ordering, and came back — who, the gap, and when they returned.

**Solution:** lag(orderDate) per customer gives the previous order's date; subtracting gives the gap in days. Keep the gaps over 90.

```sql
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
ORDER BY days_quiet DESC;
```

**Demo numbers:** 7 quiet periods, 5 customers — Lusine and Diana twice each. The longest is Lusine's 148 days (5.4 below shows it from the other side, with lead). Each customer's first order has no gap (lag is NULL), so it can't be counted by mistake.

### 5.2 The default argument, and when it lies

> **New function: `lag(x, n, d)`** — the value of `x` from `n` rows back. When there is no such row, `d` instead of NULL. (`lag(x)` is `lag(x, 1, NULL)`.)[^funcs]

`lag(orderTotal, 1, 0)` fills the gap with 0. **Demo number (wrong):** Lusine's first order becomes a "jump" of **+1,598.00** from an order that never existed.

Across all customers: "how much does an order change from the one before, on average?"

**Demo numbers:** with NULL, **1.42**, over **501** real changes. With the 0 default, **17.23**, over **529**: twelve times the real figure. 529 completed orders from 28 customers make 501 real changes. The default adds 28 fake ones, each customer's first order counted as growth from zero. `avg` skips NULLs, so the honest NULL kept them out and the 0 put them in.

A default is right only when it's *true*. "Previous order count = 0" is true for a first order. "Previous order amount = 0" isn't.

### 5.3 The trap: `lag` gives the previous *row*, not the previous *month*

"Each salesperson's completed revenue per month, and the change from the month before." Group by employee and month, then `lag(revenue) OVER (PARTITION BY employeeID ORDER BY month)`.

**Demo numbers (wrong), Nare (employee 4):** January **332.40**, then March **872.59**, with `prev_month` 332.40 and change **+540.19**. Nare sold nothing in February, so there's no February row: March was compared with January, and February's drop to zero doesn't appear at all.

It isn't an edge case. The real data has gaps for five of the eight salespeople: Vahe has no completed sales in January or October, Nare none in February, Lilit none in March, Arman none in June or August, Marine none in February or September. **Demo numbers:** the report has **88** rows instead of 8 × 12 = **96**. **8** salesperson-months are missing, and **7** rows silently compare with the month two months back (Vahe's November, Nare's March, Lilit's April, Arman's July and September, Marine's March and October). It's found by `lag`ging the month number too and counting rows where it isn't `month − 1`.

**Fix:** build the complete calendar first, then `LEFT JOIN` the facts to it (Lecture 4: the side you must not lose goes on the left). Every employee × every month from `dim_date` makes 96 rows, and `coalesce(revenue, 0)`. **Demo numbers:** Nare's February is back with **0**, change −332.40, and March is compared with February: +872.59. Check: 96 rows, total **100,222.48**, the in-store completed revenue (Lecture 4's inner-join figure: the online orders are left out on purpose here). The zeros added rows, not money.

Here 0 *is* the truth ("sold nothing that month"), unlike 5.2's fake 0. The difference is whether the 0 describes something that happened.

### 5.4 lead

> **New function: `lead(x)`** — the same as `lag`, looking forward: `x` from the *next* row of the window. Also takes `n` and a default.[^funcs]

Days from each of Lusine's orders to her next one: **148, 17, 41, 94**, then NULL. Her last order has no next order (yet).

#### Real problem: did customers come back after a return?

**Task:** after a customer returns an order, do they order again? For all returned orders: how many were followed by another order, after how many days on average, and who has not ordered since?

**Solution:** lead() over each customer's orders gives the next order's date; then look only at the rows that are returns.

```sql
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
WHERE status = 'returned';
```

```sql
WITH next_orders AS (
    SELECT o.customerID, o.orderID, o.orderDate, o.status,
           lead(o.orderDate) OVER (PARTITION BY o.customerID
                                   ORDER BY o.orderDate, o.orderTime, o.orderID) AS next_order
    FROM orders o
)
SELECT c.firstName, c.lastName, n.orderID, n.orderDate AS returned_order_date
FROM next_orders n
JOIN customers c ON c.customerID = n.customerID
WHERE n.status = 'returned' AND n.next_order IS NULL;
```

**Demo numbers:** 42 of 44 returns were followed by another order, after 22 days on average. The other two, Vahan and Karen, returned orders on 2024-12-27 — and the data ends on 2024-12-31. "No next order" means "not yet", not "lost". Check the dates before you call a NULL from lead a lost customer.

### 5.5 first_value, nth_value, and a warning

> **New function: `first_value(x)`** — the value of `x` on the first row of the window frame.[^funcs]

> **New function: `nth_value(x, n)`** — the value of `x` on the n-th row of the window frame; NULL if the frame has fewer than n rows so far.[^funcs]

Each of Lusine's completed orders next to her first and her second order. `first_value` is **1,598.00** on every row. `nth_value(orderTotal, 2)` is **NULL on the first row**, then 1,062.50, even though the second order exists. These functions see only the window *frame*, and by default the frame ends at the current row. The docs warn that this "is likely to give unhelpful results for `last_value` and sometimes also `nth_value`."[^funcs] That brings us to Part 6.

#### Real problem: which channel brings better customers?

**Task:** marketing pays for in-store promotions and for online ads. Do customers whose FIRST order was online turn out more or less valuable than customers who first bought in a store?

**Solution:** first_value(channel) per customer gives the channel of their first order (their "acquisition channel"); then group by it.

```sql
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
ORDER BY first_channel;
```

**Demo numbers:** 16 customers came in through a store, 12 online. Store-acquired customers spent 5,841.17 each, online-acquired 5,301.64 — about 9% less, on 28 customers in total. A hint, not a proof. (first_value is safe with the default frame: the frame always starts at the first row. last_value is not — Part 6.4.)

---

## Part 6 — Frames: the subtlest part of the lecture

The **frame** is the part of the partition the function sees *for the current row*. It moves as the current row moves.

| Mode | Counts | Example |
|---|---|---|
| `ROWS` | physical rows | `ROWS BETWEEN 2 PRECEDING AND CURRENT ROW` |
| `RANGE` | distance in the `ORDER BY` value. Rows with an equal value (**peers**) are all in or all out | `RANGE BETWEEN INTERVAL '6 days' PRECEDING AND CURRENT ROW` |
| `GROUPS` | groups of peers | `GROUPS BETWEEN 1 PRECEDING AND CURRENT ROW` |

Bounds: `UNBOUNDED PRECEDING`, `n PRECEDING`, `CURRENT ROW`, `n FOLLOWING`, `UNBOUNDED FOLLOWING`. In `RANGE` and `GROUPS` mode, `CURRENT ROW` means "the current row's first/last peer"; in `ROWS` mode it "simply means the current row".[^frames]

**The defaults: the whole of this Part comes down to these two lines**[^frames]

- **No `ORDER BY` in `OVER`**: the frame is the whole partition.
- **`ORDER BY` in `OVER`**: `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`, "all rows from the partition start up through the current row's last `ORDER BY` peer".

### 6.1 No `ORDER BY` vs `ORDER BY`

Same function, same partition, Lusine again: `sum() OVER (PARTITION BY customerID)` is **2,861.90** on every row. Add `ORDER BY` and it's a running total, 1,598.00 → 2,861.90. Adding `ORDER BY` quietly changed the frame.

### 6.2 Trap 1: the default frame and tied rows

A running total of completed revenue for the year: `sum(orderTotal) OVER (ORDER BY orderDate)`.

**Demo numbers (wrong):**

| orderID | orderDate | orderTotal | running_total |
|---|---|---|---|
| 1001 | 2024-01-01 | 211.65 | 211.65 |
| 1002 | 2024-01-02 | 249.00 | **1,207.65** |
| 1003 | 2024-01-02 | 747.00 | **1,207.65** |
| 1004 | 2024-01-04 | 59.00 | **1,305.55** |
| 1005 | 2024-01-04 | 38.90 | **1,305.55** |

Order 1002's "running total" already includes 1003's 747.00. The default frame is `RANGE`, and `RANGE ... CURRENT ROW` includes every peer: every order with the same date. **Demo number:** **529** rows but only **250** different running totals, one per *date* (the 250 dates with a completed order). The figure looks stalled or duplicated, and nothing errors.

**Fix:** `ORDER BY orderDate, orderID ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` → **211.65, 460.65, 1,207.65, 1,266.65, 1,305.55**. Two parts, both needed: `ROWS` stops peers joining the frame, and the unique tie-breaker stops `ROWS` from adding the tied rows in an arbitrary order (Part 3.3 again).

**The rule:** if you mean "running", write `ROWS` explicitly. Don't rely on the default.

### 6.3 Verification: where must a running total end?

1. **The last running total equals the grand total.** Both versions end at **157,078.41**: at the last date, all peers are in. So this check *can't* catch Trap 1, and it shouldn't be your only check.
2. **Per partition, the last running total equals the plain `sum`.** Per customer: **28** customers, **0** mismatches, and the 28 end points add up to **157,078.41**.
3. **A running total of positive amounts must change on every row.** Count the rows where it equals the row before: `RANGE` **279** (= 529 − 250), `ROWS` **0**. This is the check that catches Trap 1.

### 6.4 Trap 2: `last_value` with the default frame

> **New function: `last_value(x)`** — the value of `x` on the last row of the window frame. With the default frame, that is the current row — the trap in this section.[^funcs]

"Each order next to the customer's latest order total." `first_value` worked in 5.5, so `last_value` should too:

**Demo numbers (wrong):** Lusine's `latest_order` column reads **1,598.00, 1,062.50, 24.40, 177.00**, exactly her `orderTotal`. The default frame ends at the current row, so the last row of the frame *is* the current row. Over all completed orders, `last_value` equals the row's own value on **529 of 529** rows. It looks like a real column.

**Fix:** extend the frame: `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING` → **177.00** on every row. (Or `first_value` with the order reversed.)

**Every kind of frame, on one customer.** Lusine has only 4 orders, too few to see frames differ. Mher Sargsyan (customer 30) has 8 completed orders, two of them on the same day (14 November). The demo numbers his orders 1–8 (`rn`) and, for every row, shows *which rows* each frame contains.

> **New function: `string_agg(x, ',')`** — joins the values of `x` from all the rows it sees (here: the rows of the frame) into one text, separated by `','`. The order inside the list is not guaranteed: read it as a set of rows.[^stringagg]

**Query 1: the `ROWS` frames, counted in rows.**

```sql
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
ORDER BY rn;
```

| Column | Frame | In words | Row 4 sees |
|---|---|---|---|
| `default_frame` | `ORDER BY`, no frame written | from the start up to this row (`rn` has no ties, so the default `RANGE` acts like `ROWS`) | 1,2,3,4 |
| `rows_2p_1p` | `ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING` | the two rows before, *not* this one | 2,3 |
| `rows_1p_cur` | `ROWS BETWEEN 1 PRECEDING AND CURRENT ROW` | the row before, and this one | 3,4 |
| `rows_1p_1f` | `ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING` | one row either side | 3,4,5 |
| `rows_cur_unb` | `ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING` | this row to the end | 4,5,6,7,8 |
| `rows_all` | `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING` | the whole partition | 1–8 |
| `no_order_by` | `OVER ()` | the whole partition: no order, no frame | 1–8 |

At the edges a frame gets shorter; it never reaches outside the partition. On row 1, `rows_2p_1p` is empty (NULL: there are no rows before it), and `rows_1p_1f` is just 1,2. "`n PRECEDING`" in `ROWS` mode means "n rows before the current row".[^frames]

**Query 2: `RANGE`, `GROUPS` and `EXCLUDE`, i.e. what happens with ties.** Now the window is ordered by `orderDate` only, so rows 4 and 5 (both 14 November) are peers. `rows_1p` is there for comparison.

```sql
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
ORDER BY rn;
```

| Column | Frame | In words | Row 4 sees | Row 5 sees |
|---|---|---|---|---|
| `rows_1p` | `ROWS BETWEEN 1 PRECEDING AND CURRENT ROW` | 1 row back, by position | 3,4 | 4,5 |
| `groups_1p` | `GROUPS BETWEEN 1 PRECEDING AND CURRENT ROW` | this *date* and the previous date that has orders | 3,4,5 | 3,4,5 |
| `range_default` | `ORDER BY orderDate`, no frame | up to this row *and its peers* | 1–5 | 1–5 |
| `range_30_days` | `RANGE BETWEEN INTERVAL '30 days' PRECEDING AND CURRENT ROW` | orders in the 30 days up to this date | 4,5 | 4,5 |
| `excl_current_row` | whole partition, `EXCLUDE CURRENT ROW` | everyone except this row | all but 4 | all but 5 |
| `excl_group` | whole partition, `EXCLUDE GROUP` | everyone except this row and its peers | 1,2,3,6,7,8 | 1,2,3,6,7,8 |
| `excl_ties` | whole partition, `EXCLUDE TIES` | everyone except the peers, but keep this row | all but 5 | all but 4 |

Rows 4 and 5 are where the modes split: `ROWS` treats them as two different positions, while `GROUPS` and `RANGE` treat them as one date. `range_30_days` on row 4 drops row 3 (4 October is 41 days earlier), and on row 8 (21 December) it reaches back to 21 November: rows 6, 7, 8. The `EXCLUDE` options remove rows "even if they would be included according to the frame start and frame end"; `EXCLUDE NO OTHERS`, the default, removes nothing.[^exclude] `GROUPS`, `RANGE` with an offset and `EXCLUDE` need PostgreSQL 11 or later.[^v11]

**Query 3: `first_value` and `last_value` under three frames.** The functions from the fix above, on Mher's orders. Two named windows build on the first: `(w_default ROWS ...)` means "`w_default`, plus this frame".

```sql
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
ORDER BY orderDate, orderTime;
```

| Frame | `first_value` | `last_value` |
|---|---|---|
| default (start to this row) | **38.80** on every row: the frame always starts at the first order | this row's own total: the frame ends here (the trap) |
| 1 row either side | the *previous* order's total (on the first row: its own) | the *next* order's total (on the last row: its own) |
| the whole partition | **38.80**, the first order | **498.00**, the latest order: the right answer |

The middle frame turns `first_value` and `last_value` into a `lag` and a `lead` that never return NULL: at the edges the frame just shrinks, so the "previous" order of the first order is the order itself.

#### Real problem: is each customer's latest order bigger than their first?

**Task:** are customers trading up (spending more per order over time) or down? Compare each customer's first and latest completed order.

**Solution:** first_value and last_value over the FULL partition (the fixed frame above), one row per customer with DISTINCT, then count.

```sql
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
FROM first_and_last;
```

**Demo numbers:** 28 customers: 16 traded up, 12 traded down. With the DEFAULT frame, last_value changes on every row, so DISTINCT can't collapse a customer to one row: the same query then reports 510 "customers", 274 trading up and 208 down — the trap above, inside a real report. Rows in = 28 customers out is the check.

### 6.5 Trap 3: moving averages at the edges

Monthly completed revenue with a 3-month moving average (`ROWS BETWEEN 2 PRECEDING AND CURRENT ROW`, built on `fact_sales` and `dim_date`).

**Demo numbers (wrong):** January's "3-month average" is **9,902.54**, January alone. February's is **8,405.07**, two months. The column promises 3 months, and the first two rows silently use fewer. On a chart they look like any other point.

**Fix:** count the rows in the same frame (`count(*) OVER w`) and refuse to average fewer than 3, or show the count and let the reader decide. **Demo numbers:** `months_in_frame` 1, 2, 3, 3; `moving_avg_3` NULL, NULL, **7,830.87**, **9,481.76**.

### 6.6 `ROWS` vs `RANGE` with an offset: "the last 7 days"

Daily completed revenue. Orders happened on 250 of the 366 days, so "the previous 6 rows" isn't "the previous 6 days". `ROWS BETWEEN 6 PRECEDING AND CURRENT ROW` vs `RANGE BETWEEN INTERVAL '6 days' PRECEDING AND CURRENT ROW`:

**Demo numbers:** they agree for the first four dates and disagree from **January 8**: 1,894.55 by rows vs 1,682.90 by days. The rows version still includes January 1, which is outside the 7-day window. Over the year they disagree on **246 of 250** days. It's Part 5.3's trap in frame form: missing days have no rows. `RANGE` with an offset measures distance in the `ORDER BY`'s own unit (days here) and needs PostgreSQL 11.[^v11]

#### Real problem: the best week of the year

**Task:** which 7-day period brought in the most completed revenue?

**Solution:** daily revenue, then a 7-day window measured in DAYS (RANGE with an interval — not 7 rows, see above), then the top 3.

```sql
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
LIMIT 3;
```

**Demo numbers:** 5-11 December, 9,678.12 — the run-up to the holidays. All three top windows are in December (they overlap: there is one 7-day window ending on each date).

### 6.7 `GROUPS`: count peer groups, not rows

"Revenue on this order date and on the previous date that had orders", per *order*: `GROUPS BETWEEN 1 PRECEDING AND CURRENT ROW`.[^frames] **Demo numbers:** orders 1002 and 1003 both see January 1 and 2: 211.65 + 249.00 + 747.00 = **1,207.65**. Orders 1004 and 1005 see January 2 and 4: **1,093.90**. PostgreSQL 11 or later.[^v11]

---

## Part 7 — Windows meeting the rest of SQL

### 7.1 The trap: NULL is a partition too

"Rank our salespeople by number of orders": `GROUP BY o.employeeID` with `rank() OVER (ORDER BY count(*) DESC)`.

**Demo numbers (wrong):** the #1 "salesperson", with **181** orders, has no ID and no name: it's the online orders. Ani (91), Gor (90) and Hayk (65) come 2nd, 3rd and 4th. `GROUP BY` and `PARTITION BY` put all NULLs into one group, so "no employee" is ranked as if it were a person. Same inside `PARTITION BY employeeID`: "each salesperson's biggest completed order" returns **9** rows for 8 salespeople. No error.

**Two fixes. Choose one and make the choice visible:**
- **The question is about people:** exclude the online orders on purpose, with an inner join and a comment saying so. Ani 1st (91), Gor, Hayk, then Nare (55).
- **The question is about channels of sale:** keep the online orders as a *labelled* row, `coalesce(e.firstName, '(online)')`. It's the same idea as Lecture 4's `(online)` unknown member in `dim_employee`: `(online)` 181 is honestly first.

### 7.2 `NULLS FIRST` / `NULLS LAST` inside `OVER`

"Each customer's best-rated completed order", for a thank-you note: `row_number() OVER (PARTITION BY customerID ORDER BY rating DESC, orderID)`. 207 of the 529 completed orders have no rating.

**Demo numbers (wrong):** for **28 of 28** customers, the "best-rated" order is **unrated**. In PostgreSQL, `DESC` defaults to `NULLS FIRST`: nulls act "as though nulls are larger than non-nulls".[^nulls] **Fix:** `ORDER BY rating DESC NULLS LAST` → **0** unrated.

Window aggregates skip NULLs, as plain aggregates do (Lecture 4, 4.6). Lusine's average rating, **3.67**, rests on **3** ratings (`count(rating)`), not her 4 orders (`count(*)`). Put the two counts next to every average.

### 7.3 Windows do not repair fan-out

Each order line next to its customer's completed revenue, written over `orders JOIN order_items` with the header's `orderTotal`:

**Demo numbers (wrong):** Lusine's "revenue" is **5,011.30**, not 2,861.90. Order 1307 has three lines and 1373 has two, so 1307's total was counted three times and 1373's twice. It's Lecture 5's cart fan-out (2.3) inside a window. The window summed exactly the rows it was given; the join had already multiplied them. Over all customers: **844** line rows for **529** orders, and the header total over the lines is **247,923.72**, Lecture 5's wrong figure again.

**Fix:** sum what lives on the line, `sum(i.lineTotal) OVER (...)` → 2,861.90 (or put the window on `orders` before joining). Count rows against orders *before* you put a window on top of a join.

### 7.4 `FILTER` with window aggregates

Lecture 4's `FILTER` works inside a window too: `count(*) FILTER (WHERE status = 'returned') OVER (PARTITION BY customerID)`. **Demo numbers:** each of Lusine's 5 orders shows **4** completed, **1** returned, **2,861.90** completed revenue. Only aggregates accept `FILTER`, not `row_number`, `rank` or `lag`.[^frames]

#### Real problem: customers who return a lot

**Task:** customer service wants the customers who returned at least 15% of their orders, with the numbers behind it.

**Solution:** count(*) FILTER (WHERE status = 'returned') and count(*) over each customer's orders, on every order row; then one row per customer with DISTINCT.

```sql
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
ORDER BY pct_returned DESC, c.lastName;
```

**Demo numbers:** 5 customers. Read the counts, not just the percentage: Diana's 25% is 1 return out of 4 orders, Narek's 17.2% is 5 out of 29. A rate built on 4 orders says very little. (A GROUP BY would give the same list; the window version keeps every order row, so the same CTE can also flag each order for review.)

### 7.5 Window vs self-join vs correlated subquery

"Completed orders bigger than their customer's average order", three ways: an `avg() OVER (PARTITION BY customerID)` window; a join to a per-customer derived table (Lecture 5, 1.4); a correlated subquery (Lecture 5, Part 3).

**Demo numbers:** **172** orders. `EXCEPT` in both directions for both pairs: **0, 0, 0, 0**. Same answer three ways. The window version filters `status = 'completed'` once; the other two must repeat it inside the subquery, and forgetting it is a silent bug of its own (1.2).

### 7.6 Windows on the star schema

- **Running revenue by month** from `fact_sales` and `dim_date`: `sum(sum(f.revenue)) OVER (ORDER BY d.month ROWS ...)`. **Demo numbers:** January 9,902.54 … December 27,875.83; the December running total is **157,078.41**. (One row per month, so no peers, and `ROWS` and `RANGE` agree here. Writing `ROWS` costs nothing.)
- **Rank products within their category**, with each one's share of the category: **Demo numbers:** Laptops: ThinkPad X1 Carbon **26,937.50** (**50.4%** of Laptops), MacBook Air 13 21.0%, ZenBook 14 14.7%, Aspire 5 13.8%. Phones: iPhone 15 45.0%, Galaxy S24 28.5%, Pixel 8 16.0%, Redmi Note 13 10.4%. (Ranked by *revenue*, Redmi Note 13 is last. Ranked by *times ordered* in 3.4, it tied for 2nd. Say which you mean.)
- **Check against the known total:** **36** products sold in **12** categories (Ergonomic Chair Pro never sold, so Chairs has no fact rows), total **157,078.41**, and every category's shares add up to exactly **100**.

---

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

**The new functions, in one table** (each is defined where it first appears):[^funcs] [^stringagg]

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

---

## Open questions / TODO

Each item in the brief's list, answered in order, then other things worth knowing.

**From the brief's list**

- **Lecture 4/5 files: found. The brief's revenue anchors do not match the current data, and I did *not* use them.** The brief gives completed revenue **93,534.71** and `fact_sales` revenue **145,935.12**. Both come from the *old* one-product-per-order data: 145,935.12 was Lecture 3's completed revenue, and 93,534.71 was old Lecture 4's *wrong* inner-join figure (it is still in `lectures/lecture_4/slides/build.py`). Since the multi-product switch, Lectures 4 and 5 use 157,078.41. This lecture uses the current data and its real figures: completed revenue **157,078.41** (from `orders` and from `fact_sales`), all-status `fact_sales` revenue **177,770.91**, inner-join/in-store completed revenue **100,222.48**, `moneySpent` fan-out **4,386,925.27**. Everything else in the brief matched: 600 / 30 / 8 / 37, 181 online orders, Levon and Astghik with no orders, productID 35 never ordered. One more thing to check: `lectures/lecture_4/slides/build.py` still contains the old 93,534.71 / 145,935.12 figures, so that light-theme deck may be stale.
- **The `lecture-05-build-prompt.md` named in the brief doesn't exist.** The Lecture 5 brief is only in the desktop Trash (`lecture_5_prmot.md`). I read it there and didn't restore it.
- **Ties: all genuine, nothing synthetic.** Customer order counts (Narek/Lilit 29, Mariam/Hayk 16, Meline/Ani 10, Arpine/Mher 8, Levon/Astghik 0); product popularity within categories (Audio 28/28, Monitors 10/10, Phones 11/11, Storage 28/28); 174 of the year's dates have more than one order, and 2 customers have two orders on their last day (Anna, Armen).
- **Missing periods: genuine, nothing synthetic.** Monthly *totals* have no gaps (every month and every branch has sales), so the `lag` trap uses salesperson × month: 8 of 96 employee-months have no completed sale. Daily data has gaps too (250 of 366 days), used in 6.6.
- **Every trap reproduces with a visibly wrong result on the real data.** The plan-dependent ones (2.4 output order; 3.2, 3.3, 4.4 and 4.6 tie-breaking) were checked on fresh PostgreSQL 14, 16 and 18 databases after the setup script, and gave identical results. They depend on PostgreSQL's sort of tied rows, so a student who skips `ANALYZE` or uses another version might see the "right" answer by luck. That is the lesson itself, but be ready for it.
- **The `DISTINCT ON` trap is partly loud, not silent.** "An `ORDER BY` that doesn't lead with the `DISTINCT ON` expressions" is an *error* in PostgreSQL. 4.4 shows the error, then the silent sibling (an `ORDER BY` with only the `DISTINCT ON` column → customer 1 gets a February order).
- **Performance: left out on request.** No `EXPLAIN`, timings or speed claims anywhere in the lecture. 4.8 compares the three top-N methods on correctness and portability only.
- **Notebook: connects and runs.** Same setup as Lecture 5: psycopg 3, DSN from `LECTURE06_DSN` (default `postgresql://postgres:postgres@localhost:5432/lecture06`), data loaded by `psql` + `steps/00-setup.sql` first. Verification details are in the last bullet.
- **Voice and structure: matched, with two additions.** (1) Part 4.6 has a two-dimensional table (method × customer), because the point is that agreement can mislead. (2) Parts 3 and 6 each open with a reference table. The rest follows Lecture 5: "Part N" headings, **Demo number** callouts, footnotes citing the PostgreSQL docs, the Part 8 synthesis table, and this TODO section.
- **Scope: probably too long for one session. Proposed split after Part 4.** The demo has 139 SQL statements against Lecture 5's 103 (setup included in both), and Parts 4 and 6 are each a full block. Twelve "Real problem" blocks (task → solution → result, one after the first example of each feature) were added on request; they make the lecture longer still, and they are the easiest thing to set as homework if time runs short. Session A: Parts 1–4 (what windows are, OVER, ranking, top-N), ending on the loud error and the `EXCEPT` proof. Session B: Parts 5–8 (lag/lead, frames, NULLs and joins, synthesis). Part 5.5 already ends on "the frame is the next subject", which makes a natural bridge if Part 5 moves to session A instead. Nothing has been cut. If you need one session, the cheapest cuts are 3.2 (ntile etc.) and 6.7 (GROUPS).

**Also worth knowing**

- **Chinook "256 tied tracks": the number is verified, the source isn't visible.** The Lab 5 key isn't in this repository. Loading `lectures/chinook/Chinook_PostgreSql.sql` and counting sales per track gives a 256-way tie at the top (256 tracks sold twice, 1,728 once). The notes say "best-selling track"; check that's the question the lab used.
- **Folder name.** The brief said `lecture-06/`; the files are in `lectures/lecture_6/`, matching `lecture_2` … `lecture_5`. As in Lecture 5, the folder also has `data/` (byte-identical copies of Lecture 5's CSVs and `all_inserts.sql`) and `steps/00-…08-…` (the demo split by Part). New: `build/`, the tools that produced the demo and notebook (Lecture 5's generator was lost in a session scratchpad, so this time they're kept). **To change a query, edit `build/src/NN-*.sql`, not `steps/`**: load the database with `psql postgres` + `\i steps/00-setup.sql` from `lecture_6/`, then run `PGP=<port> build/build_demo.sh`. It regenerates `steps/01-08`, the demo and the notebook. `build/verify_notebook.py` reruns the notebook and compares every cell with the demo. If you edit the notebook by hand in marimo, those edits will be overwritten by the next rebuild.
- **Setup differs from Lecture 5 in one way:** it rebuilds Lecture 4's star schema (Part 7.6 and 6.5 use it). Lecture 4's flat `sales` table is still not loaded.
- **How the numbers were produced.** Each step file was generated by `build/annotate.py`, which runs it and pastes psql's actual output under each query, so no result in a demo comment was typed by hand. Three of my *prose* comments were wrong on the first run and were corrected from the output before anything was written here: the missing-month counts (I had guessed 85/11; it's 88/8), Lusine's rating count, and the number of lines in her orders. Then the notes, Q&A and notebook were written from the step files.
- **Notebook vs notes/demo: no disagreement.** Every notebook SQL cell (90) is copied word for word from the demo by `build/build_notebook.py`, which fails if a cell's SQL isn't in the demo. The notebook was run with `app.run()` against a freshly set-up database on PostgreSQL 14, 16 and 18, and every cell's result was compared with the output pasted in the demo: all 90 cells checked, 0 mismatches on each version. The 4 error cells were checked to raise the expected errors. The notebook passes `marimo check` and `marimo export html` (which runs every cell). It hasn't been clicked through in `marimo edit`; do that once before class. Every decimal number in these notes and the Q&A appears in the demo output.

[^demo]: `lecture-06-demo.sql` (also split per Part in `steps/`), run on PostgreSQL 14.24, 16.15 and 18.6 against Lecture 5's data plus Lecture 4's star schema. Every result was identical on all three.
[^tutorial]: PostgreSQL 16 documentation, §3.5 "Window Functions": "A window function performs a calculation across a set of table rows that are somehow related to the current row. … However, window functions do not cause rows to become grouped into a single output row like non-window aggregate calls would. Instead, the rows retain their separate identities." … "You can also control the order in which rows are processed by window functions using ORDER BY within OVER. (The window ORDER BY does not even have to match the order in which the rows are output.)" … "Window functions are permitted only in the SELECT list and the ORDER BY clause of the query. They are forbidden elsewhere, such as in GROUP BY, HAVING and WHERE clauses. This is because they logically execute after the processing of those clauses." … "If there is a need to filter or group rows after the window calculations are performed, you can use a sub-select." … "When a query involves multiple window functions, it is possible to write out each one with a separate OVER clause, but this is duplicative and error-prone if the same windowing behavior is wanted for several functions. Instead, each windowing behavior can be named in a WINDOW clause and then referenced in OVER." https://www.postgresql.org/docs/16/tutorial-window.html
[^funcs]: PostgreSQL 16 documentation, §9.22 "Window Functions", Table 9.64: row_number "Returns the number of the current row within its partition, counting from 1." rank "Returns the rank of the current row, with gaps; that is, the row_number of the first row in its peer group." dense_rank "Returns the rank of the current row, without gaps; this function effectively counts peer groups." percent_rank "(rank - 1) / (total partition rows - 1)". cume_dist "(number of partition rows preceding or peers with current row) / (total partition rows)". ntile "dividing the partition as equally as possible." lag "Returns value evaluated at the row that is offset rows before the current row within the partition; if there is no such row, instead returns default … If omitted, offset defaults to 1 and default to NULL." And: "any built-in or user-defined ordinary aggregate … can be used as a window function" … "Note that first_value, last_value, and nth_value consider only the rows within the 'window frame', which by default contains the rows from the start of the partition through the last peer of the current row. This is likely to give unhelpful results for last_value and sometimes also nth_value." https://www.postgresql.org/docs/16/functions-window.html
[^frames]: PostgreSQL 16 documentation, §4.2.8 "Window Function Calls": "The default framing option is RANGE UNBOUNDED PRECEDING, which is the same as RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW. With ORDER BY, this sets the frame to be all rows from the partition start up through the current row's last ORDER BY peer. Without ORDER BY, this means all rows of the partition are included in the window frame, since all rows become peers of the current row." … "In RANGE or GROUPS mode, a frame_start of CURRENT ROW means the frame starts with the current row's first peer row (a row that the window's ORDER BY clause sorts as equivalent to the current row), while a frame_end of CURRENT ROW means the frame ends with the current row's last peer row. In ROWS mode, CURRENT ROW simply means the current row." … "In GROUPS mode … the frame starts or ends the specified number of peer groups before or after the current row's peer group … (There must be an ORDER BY clause in the window definition to use GROUPS mode.)" … "In ROWS mode, the offset must yield a non-null, non-negative integer, and the option means that the frame starts or ends the specified number of rows before or after the current row." … "Only window functions that are aggregates accept a FILTER clause." https://www.postgresql.org/docs/16/sql-expressions.html#SYNTAX-WINDOW-FUNCTIONS
[^stringagg]: PostgreSQL 16 documentation, §9.21 "Aggregate Functions", Table 9.59: string_agg "Concatenates the non-null input values into a string. Each value after the first is preceded by the corresponding delimiter (if it's not null)." And: string_agg is among the aggregates that "produce meaningfully different result values depending on the order of the input values. This ordering is unspecified by default". https://www.postgresql.org/docs/16/functions-aggregate.html
[^exclude]: PostgreSQL 16 documentation, §4.2.8 "Window Function Calls": "The frame_exclusion option allows rows around the current row to be excluded from the frame, even if they would be included according to the frame start and frame end options. EXCLUDE CURRENT ROW excludes the current row from the frame. EXCLUDE GROUP excludes the current row and its ordering peers from the frame. EXCLUDE TIES excludes any peers of the current row from the frame, but not the current row itself. EXCLUDE NO OTHERS simply specifies explicitly the default behavior of not excluding the current row or its peers." https://www.postgresql.org/docs/16/sql-expressions.html#SYNTAX-WINDOW-FUNCTIONS
[^order]: PostgreSQL 16 documentation, §7.5 "Sorting Rows": "If sorting is not chosen, the rows will be returned in an unspecified order. The actual order in that case will depend on the scan and join plan types and the order on disk, but it must not be relied on." https://www.postgresql.org/docs/16/queries-order.html
[^distincton]: PostgreSQL 16 documentation, SELECT: "Note that the 'first row' of each set is unpredictable unless ORDER BY is used to ensure that the desired row appears first." … "The DISTINCT ON expression(s) must match the leftmost ORDER BY expression(s)." Compatibility: "DISTINCT ON ( ... ) is an extension of the SQL standard." https://www.postgresql.org/docs/16/sql-select.html
[^nulls]: PostgreSQL 16 documentation, SELECT, ORDER BY clause: "If neither is specified, the default behavior is NULLS LAST when ASC is specified or implied, and NULLS FIRST when DESC is specified (thus, the default is to act as though nulls are larger than non-nulls)." https://www.postgresql.org/docs/16/sql-select.html
[^v84]: PostgreSQL 8.4 release notes: "Add support for WINDOW functions (Hitoshi Harada)". https://www.postgresql.org/docs/release/8.4.0/
[^v94]: PostgreSQL 9.4 release notes: "Add control over which rows are passed into aggregate functions via the FILTER clause (David Fetter)". https://www.postgresql.org/docs/release/9.4.0/
[^v11]: PostgreSQL 11 release notes: "Add all window function framing options specified by SQL:2011 (Oliver Ford, Tom Lane). Specifically, allow RANGE mode to use PRECEDING and FOLLOWING to select rows having grouping values within plus or minus the specified offset. Add GROUPS mode to include plus or minus the number of peer groups. Frame exclusion syntax was also added." https://www.postgresql.org/docs/release/11.0/
[^chinook]: `lectures/chinook/Chinook_PostgreSql.sql`, loaded and queried: `SELECT n, count(*) FROM (SELECT track_id, count(*) AS n FROM invoice_line GROUP BY track_id) t GROUP BY n` → 256 tracks with 2 sales, 1,728 with 1.
