# Lecture 3 — Asking Questions of One Table

**A hands-on guide** · Introduction to Databases & SQL · YSU, Data Science for Business

---

## How to use this guide

Like last time, this is written to be worked through at a keyboard. Each
part explains one idea and then hands you SQL to run. Type or paste it
into your own database, look at what actually comes back, and compare it
to the expected output before moving on. Five statements in this guide
**fail on purpose** — when one does, read the error message. It is part
of the lesson.

Total time start to finish: **~100 minutes**. Stop anywhere; nothing here
is timed.

## Before you start

You need:

- **PostgreSQL** running, and the `psql` client (or any SQL client that
  runs raw SQL and shows you error messages).
- A terminal open **in this folder** (`lectures/lecture_3/`). Part 0
  loads five CSV files with `\copy`, which resolves paths relative to
  wherever you *started* `psql`. Starting it anywhere else is the most
  common cause of a "file not found" error.

Make a database and load the data:

```bash
createdb lecture03        # or reuse lecture02 -- either works
psql lecture03
```

```
lecture03=# \i steps/00-setup.sql
```

Expected at the end: **600 / 30 / 8 / 37 / 600**. If you see that, you're
set. The script drops and recreates everything it makes, so it is also
the reset button — run it again any time.

> **No access to the CSV files?** Run the `CREATE TABLE` half of
> `steps/00-setup.sql` (everything above the `-- ---- Load` line), then
> `\i data/all_inserts.sql`. Same rows, as plain `INSERT` statements.

Three ways to work through what follows — pick one:

- **Statement by statement (recommended):** copy each SQL block into
  your `psql` session as you read, and compare your output to what's
  shown.
- **All at once:** `\i lecture-03-demo.sql` runs every statement in
  order, then scroll back through the output as you read.
- **One file per Part:** `steps/01-select.sql` through
  `steps/06-drill.sql`, numbered to match the Parts below. Run each with
  `\i steps/02-where.sql` (etc.) as you reach it. Unlike Lecture 2, no
  part changes the data, so they can be run in any order and re-run
  freely.

`psql` folds unquoted names to lowercase, so `orderTotal` comes back as
`ordertotal` in the output. Same as last time — nothing is wrong.

## Where we left off

Lecture 2 turned one 42-row file into four tables — `customers`,
`employees`, `products`, `orders` — connected by foreign keys, in third
normal form. Along the way you wrote eight `SELECT` statements: choose
columns, choose rows with `WHERE`, `ORDER BY`, `LIMIT`, `DISTINCT`.

Everything a business wants from its data goes through `SELECT`, and
those eight statements were the first five percent of it. Real
questions sound like *how much*, *how many*, *on average*, *per month*,
*per branch*, *top five*, *which ones never*. This lecture is the rest
of `SELECT`: expressions, the full `WHERE`, sorting properly,
aggregates, and grouping — the tools that turn 600 rows into a number
someone can act on.

**One table at a time.** Every query in this guide reads from a single
table. Combining tables is next lecture's subject. To make one table
interesting enough for a whole lecture, the data has changed.

### The shop, one year later

The dataset is the same electronics shop, twelve months on. Same first
eight customers, same first four employees, same six product
categories — but the business grew, and every table picked up columns:

| Table | Lecture 2 had | New this lecture |
|---|---|---|
| **customers** | id, first/last name, birthDate, moneySpent, anniversary | `email`, `phone`, `city`, `signupDate` |
| **employees** | id, first/last name, birthDate | `email`, `hireDate`, `position`, `branch`, `salary` |
| **products** | id, category, price | `productName`, `brand`, `cost`, `stockQuantity`, `isActive` — a category now holds several products |
| **orders** | id, three foreign keys, orderTotal, orderDate | `quantity`, `unitPrice`, `discountPct`, `orderTime`, `channel`, `paymentMethod`, `status`, `deliveryDate`, `rating` |

Two things to know before you query it:

- **`orders.status`** is `completed`, `returned` or `cancelled`. A
  returned order has a total in the table. It is not revenue.
- **Online orders have no salesperson.** `orders.employeeID` is NULL for
  them — 181 of the 600. Lecture 2's schema said `NOT NULL` there; the
  business changed its mind when it opened a web shop.

And, as in Lecture 2, there are **two shapes of the same facts**:

- **`sales`** — the flat file. One row per sale, 29 columns, everything
  on it: the customer's name and city, the employee's branch, the
  product's brand and cost. 600 rows. This is `sales_raw` from Lecture
  2, a year of data instead of a month.
- **`customers`, `employees`, `products`, `orders`** — the same 600
  sales, split the way Lecture 2 split them.

Both are loaded. Today you query **whichever answers the question with
less typing** — mostly `sales`, because it has the names on it, and the
small tables when the question is about products or people. Next
lecture puts the four back together, and you'll see why the flat one
was convenient to read and dangerous to keep.

**By the end of this guide, you should be able to:**

1. Write a `SELECT` whose columns are *expressions* — arithmetic, text,
   dates, `CASE WHEN` — and name them.
2. Filter with the full `WHERE` vocabulary: `BETWEEN`, `IN`, `LIKE`,
   `IS NULL`, `AND`/`OR`/`NOT` — and say why `AND` and `OR` need
   parentheses.
3. Explain why `WHERE x = NULL` returns nothing, and what `NULL` does in
   a comparison, a sort, an aggregate and a `GROUP BY`.
4. Sort by several columns, expressions and aliases; use `LIMIT` and
   `OFFSET`; and say why `LIMIT` without `ORDER BY` is not "the top".
5. Use `count`, `sum`, `avg`, `min`, `max`, `count(DISTINCT …)`, and
   know which rows they see and which NULLs they skip.
6. Answer "per what?" with `GROUP BY` and filter groups with `HAVING`,
   and recite the order the clauses actually run in.
7. Catch the four most common ways a query returns a *plausible wrong
   number* without any error.

---

## Part 0 — Load the data (~5 min)

```
\i steps/00-setup.sql
```

Read the file once before running it. The `CREATE TABLE`s are Lecture
2's, grown; the `\copy` lines are Lecture 2's Part 1, five times. One
new detail at the bottom: because the CSVs carry their own ids, each
`SERIAL` counter still thinks the next id is 1, and the three
`setval(...)` calls move them past what's loaded. Rows and counters are
separate things — worth knowing the first time you restore a backup.

```
     t     | count
-----------+-------
 sales     |   600
 customers |    30
 employees |     8
 products  |    37
 orders    |   600
```

Look around before going on. `\d sales` lists the 29 columns. `\d
products` shows a `boolean` column and a two-column `UNIQUE` — new
since Lecture 2, both of them.

---

## Part 1 — SELECT is a list of expressions (~15 min)

### First: the order a query actually runs in

You *write* a query top to bottom — `SELECT`, `FROM`, `WHERE`,
`GROUP BY`, `HAVING`, `ORDER BY`, `LIMIT`. The database *runs* it in a
different order:

```
1. FROM       pick the table
2. WHERE      keep only the rows that pass the condition
3. GROUP BY   collapse the surviving rows into groups
4. HAVING     keep only the groups that pass the condition
5. SELECT     compute the output columns, and name them
6. DISTINCT   drop duplicate output rows
7. ORDER BY   sort the output
8. LIMIT      cut it off
```

`SELECT` is written first and runs **fifth**. Two consequences follow,
and you will hit both within the hour:

- A column name invented in `SELECT` (an alias) exists from step 5
  onward. `ORDER BY` can use it. `WHERE` and `HAVING` cannot — when they
  run, it hasn't been invented yet.
- An aggregate like `sum()` is computed when the groups are formed, at
  step 3. So it can appear in `HAVING` and `SELECT` — and `HAVING` can
  use an aggregate that `SELECT` doesn't even output — but never in
  `WHERE`, which runs before any group exists.

Both kinds of value are "made by the query". They're just made at
different steps, and that decides who can see them.

Every statement in this guide that fails on purpose fails for one of
those two reasons. Keep the list in view; you'll be sent back to it.

### Choose columns. Always.

```sql
SELECT * FROM sales LIMIT 3;
```

Twenty-nine columns. Scroll sideways, give up. `SELECT *` is for
looking, never for reporting. Two better moves — `psql`'s `\x` flips
to one-column-per-line display for a single wide row:

```
\x
SELECT * FROM sales LIMIT 1;
\x
```

…and naming the columns you actually want:

```sql
SELECT orderID, orderDate, productName, orderTotal
FROM sales
LIMIT 5;
```

```
 orderid | orderdate  |    productname     | ordertotal
---------+------------+--------------------+------------
    1545 | 2024-12-12 | ThinkPad X1 Carbon |    1125.00
    1071 | 2024-02-28 | MX Keys            |     269.97
    1104 | 2024-03-21 | M185               |      44.97
    1488 | 2024-11-16 | MacBook Air 13     |     935.00
    1565 | 2024-12-19 | ThinkPad X1 Carbon |    1250.00
```

(Why 1545 first, and not 1001? Hold that thought until Part 3.)

### A column can be an expression

Anything you can compute from a row can be a column of the result.
`AS` gives it a name:

```sql
SELECT orderID, quantity, unitPrice, discountPct, orderTotal,
       quantity * unitPrice               AS list_total,
       quantity * unitPrice - orderTotal  AS discount_given
FROM sales
LIMIT 5;
```

```
 orderid | quantity | unitprice | discountpct | ordertotal | list_total | discount_given
---------+----------+-----------+-------------+------------+------------+----------------
    1545 |        1 |   1250.00 |          10 |    1125.00 |    1250.00 |         125.00
    1071 |        3 |     89.99 |           0 |     269.97 |     269.97 |           0.00
    1104 |        3 |     14.99 |           0 |      44.97 |      44.97 |           0.00
    1488 |        1 |   1100.00 |          15 |     935.00 |    1100.00 |         165.00
    1565 |        1 |   1250.00 |           0 |    1250.00 |    1250.00 |           0.00
```

Order 1545: a laptop at 1250, 10% off, 1125 paid. The two computed
columns weren't stored anywhere — the database worked them out for
this result and threw them away.

What the shop actually makes on each product:

```sql
SELECT productName, price, cost,
       price - cost                              AS margin,
       round((price - cost) / price * 100, 1)    AS margin_pct
FROM products
LIMIT 5;
```

```
     productname     |  price  |  cost  | margin | margin_pct
---------------------+---------+--------+--------+------------
 ThinkPad X1 Carbon  | 1250.00 | 980.00 | 270.00 |       21.6
 Laptop Sleeve 14    |   25.50 |  10.00 |  15.50 |       60.8
 MX Keys             |   89.99 |  55.00 |  34.99 |       38.9
 UltraSharp 27       |  320.00 | 240.00 |  80.00 |       25.0
 Portable SSD T7 1TB |   74.00 |  52.00 |  22.00 |       29.7
```

A laptop sleeve earns a better *percentage* than a laptop. That's the
kind of sentence a shop owner wants, and it took one line.

`AS` is optional — `price - cost margin` also works — but an alias with
a space or capital letters needs double quotes:

```sql
SELECT productName, round(price * 1.2, 2) AS "Price incl. VAT" FROM products LIMIT 3;
```

### Text

```sql
SELECT customerFirstName || ' ' || customerLastName AS customer,   -- || glues text
       upper(customerCity)                          AS city,
       length(customerEmail)                        AS email_length
FROM sales
LIMIT 5;
```

```sql
SELECT email,
       split_part(email, '@', 2) AS domain,     -- piece 2 when split at '@'
       lower(firstName)          AS handle
FROM customers
LIMIT 5;
```

```
            email             |   domain    | handle
------------------------------+-------------+--------
 anna.sargsyan@gmail.com      | gmail.com   | anna
 davit.petrosyan@mail.ru      | mail.ru     | davit
 mariam.hakobyan@gmail.com    | gmail.com   | mariam
 tigran.grigoryan@gmail.com   | gmail.com   | tigran
 lusine.avetisyan@outlook.com | outlook.com | lusine
```

`split_part` is the one to remember: it pulls a piece out of text that
has a separator in it — the domain of an email, the year of a `2024-Q3`
label, the area code of a phone number.

### Dates and times

```sql
SELECT orderDate,
       EXTRACT(YEAR  FROM orderDate)  AS yr,
       EXTRACT(MONTH FROM orderDate)  AS mon,
       to_char(orderDate, 'Mon')      AS mon_name,
       to_char(orderDate, 'Dy')       AS weekday,
       orderTime,
       EXTRACT(HOUR FROM orderTime)   AS hr
FROM sales
LIMIT 5;
```

```
 orderdate  |  yr  | mon | mon_name | weekday | ordertime | hr
------------+------+-----+----------+---------+-----------+----
 2024-12-12 | 2024 |  12 | Dec      | Thu     | 13:55:54  | 13
 2024-02-28 | 2024 |   2 | Feb      | Wed     | 18:05:49  | 18
 2024-03-21 | 2024 |   3 | Mar      | Thu     | 11:39:35  | 11
 2024-11-16 | 2024 |  11 | Nov      | Sat     | 12:06:08  | 12
 2024-12-19 | 2024 |  12 | Dec      | Thu     | 18:32:40  | 18
```

`EXTRACT` gives you a number (for grouping and comparing); `to_char`
gives you a label (for reading). Both will matter in Part 5.

A date minus a date is a number of days:

```sql
SELECT orderID, orderDate, deliveryDate,
       deliveryDate - orderDate AS days_to_deliver
FROM sales
WHERE channel = 'online'
LIMIT 5;
```

```
 orderid | orderdate  | deliverydate | days_to_deliver
---------+------------+--------------+-----------------
    1071 | 2024-02-28 | 2024-03-01   |               2
    1488 | 2024-11-16 | 2024-11-18   |               2
    1275 | 2024-07-22 | 2024-07-29   |               7
```

`age()` gives you an *interval* — years, months, days — and `EXTRACT`
pulls the part you want out of it. This is pinned to a fixed date so
your output matches the guide:

```sql
SELECT firstName, lastName, birthDate,
       age(DATE '2024-12-31', birthDate)                     AS age_at_year_end,
       EXTRACT(YEAR FROM age(DATE '2024-12-31', birthDate))  AS years
FROM customers
LIMIT 5;
```

```
 firstname | lastname  | birthdate  |     age_at_year_end      | years
-----------+-----------+------------+--------------------------+-------
 Anna      | Sargsyan  | 1991-04-12 | 33 years 8 mons 19 days  |    33
 Davit     | Petrosyan | 1988-11-23 | 36 years 1 mon 8 days    |    36
```

Today's date is a function, and this one's output depends on when you
run it:

```sql
SELECT CURRENT_DATE, CURRENT_DATE - DATE '2024-01-01' AS days_since_new_year;
```

### CASE WHEN: a value that depends on a condition

The most useful thing in this part. `CASE` checks conditions top to
bottom and returns the value for the first one that's true:

```sql
SELECT orderID, orderTotal,
       CASE
           WHEN orderTotal >= 1000 THEN 'large'
           WHEN orderTotal >= 100  THEN 'medium'
           ELSE                         'small'
       END AS size
FROM sales
LIMIT 8;
```

```
 orderid | ordertotal |  size
---------+------------+--------
    1545 |    1125.00 | large
    1071 |     269.97 | medium
    1104 |      44.97 | small
    1488 |     935.00 | medium
    1565 |    1250.00 | large
```

Order matters: 1125 is also `>= 100`, but the first true branch wins.
Write the conditions from strictest to loosest.

```sql
SELECT firstName, lastName, moneySpent,
       CASE
           WHEN moneySpent >= 10000 THEN 'Gold'
           WHEN moneySpent >= 3000  THEN 'Silver'
           ELSE                          'Bronze'
       END AS tier
FROM customers
LIMIT 8;
```

That's a loyalty tier that isn't stored anywhere — and so can never be
stale. Compare `moneySpent`, which is stored, and which Lecture 2
already warned you about.

Without an `ELSE`, anything that matches no branch comes back as
`NULL`:

```sql
SELECT orderID, rating,
       CASE WHEN rating >= 4 THEN 'happy' WHEN rating <= 2 THEN 'unhappy' END AS mood
FROM sales
LIMIT 8;
```

Rows with a rating of 3 — and rows with no rating at all — get an
empty `mood`. Remember that empty; it's the subject of the next part.

### One rule to carry forward

An alias is *invented by `SELECT`* — step 5 in the list that opened
this part. Anything that runs before step 5 can't see it. That's most
of the query, and the first casualty is `WHERE`.

---

## Part 2 — WHERE, properly (~20 min)

Lecture 2 used `WHERE` with `<`, `>` and `AND`. Here is the rest of it.
Most of these return a count so you can check yourself quickly; swap
`count(*)` for column names whenever you want to see the rows.

### Equality, and what "equal" means for text

```sql
SELECT count(*) FROM sales WHERE productCategory = 'Laptops';    -- 51
SELECT count(*) FROM sales WHERE productCategory = 'laptops';    -- 0
```

Zero rows, not an error. Text comparison is case-sensitive, and the
database has no opinion about whether you meant `Laptops`. This is the
first of many "wrong but silent" results in this guide.

### Comparison, ranges, lists

```sql
SELECT count(*) FROM sales WHERE status <> 'completed';          -- 71  (<> is "not equal"; != also works)
SELECT count(*) FROM sales WHERE orderTotal >= 1000;             -- 34
SELECT count(*) FROM sales WHERE orderDate >= '2024-12-01';      -- 86  (dates compare like numbers)

SELECT count(*) FROM sales WHERE orderTotal BETWEEN 100 AND 200;                      -- 88
SELECT count(*) FROM sales WHERE orderDate  BETWEEN '2024-12-01' AND '2024-12-31';    -- 86

SELECT count(*) FROM sales WHERE productCategory IN ('Laptops', 'Phones', 'Tablets'); -- 126
```

`BETWEEN` includes both ends. `IN` is "any of these" — the same as
three `= … OR = …` conditions, and far more readable.

```sql
SELECT productName, brand, price
FROM products
WHERE brand IN ('Apple', 'Samsung')
ORDER BY price DESC;
```

### LIKE: patterns

`%` matches anything (including nothing); `_` matches exactly one
character.

```sql
SELECT DISTINCT customerLastName FROM sales WHERE customerLastName LIKE 'S%';   -- starts with S
SELECT count(*) FROM sales WHERE customerEmail LIKE '%@gmail.com';              -- 378
SELECT firstName, lastName FROM customers WHERE firstName LIKE 'A__';           -- exactly three letters: Ani
```

`LIKE` is case-sensitive too. `ILIKE` isn't:

```sql
SELECT productName FROM products WHERE productName LIKE  '%usb%';    -- 0 rows
SELECT productName FROM products WHERE productName ILIKE '%usb%';    -- USB-C Hub, USB Flash, USB-C Cable
```

### AND, OR, NOT

```sql
SELECT count(*) FROM sales WHERE channel = 'online' AND status = 'completed';       -- 164
SELECT count(*) FROM sales WHERE NOT status = 'completed';                           -- 71, same as <>
SELECT count(*) FROM sales WHERE productCategory NOT IN ('Cables', 'Accessories');   -- 416
```

### The precedence trap

"Laptops or phones, over 1000." Type it the way you'd say it:

```sql
SELECT count(*) FROM sales
WHERE productCategory = 'Laptops' OR productCategory = 'Phones' AND orderTotal > 1000;
-- 55
```

**`AND` binds tighter than `OR`.** The database read that as *Laptops,
or (Phones and over 1000)* — every laptop got in, including the 620
ones. Prove it by writing the parentheses it silently added:

```sql
SELECT count(*) FROM sales
WHERE productCategory = 'Laptops' OR (productCategory = 'Phones' AND orderTotal > 1000);
-- 55 -- identical
```

What you meant:

```sql
SELECT count(*) FROM sales
WHERE (productCategory = 'Laptops' OR productCategory = 'Phones') AND orderTotal > 1000;
-- 33
```

55 and 33 are both perfectly plausible counts. Nothing warned you.
**The moment `AND` and `OR` share a `WHERE`, put parentheses — every
time, even when you're sure.**

### A boolean column is already a condition

```sql
SELECT productName FROM products WHERE NOT isActive;    -- K380: discontinued
SELECT count(*)    FROM products WHERE isActive;        -- 36
```

No `= true` needed — the column *is* a true/false value.

### NULL

Seven customers never told the shop their anniversary. Try to find
them:

```sql
SELECT firstName, lastName, anniversary FROM customers WHERE anniversary = NULL;
-- (0 rows)
```

Zero rows — and no error. `NULL` means *"there is no value here."* Is
no-value equal to no-value? The database refuses to say yes, or no; the
comparison comes back `NULL` itself, which `WHERE` treats as "not
true", and the row is dropped. Nothing is `= NULL`, not even `NULL`.
The only way to ask is `IS NULL`:

```sql
SELECT firstName, lastName FROM customers WHERE anniversary IS NULL;        -- 7 rows
SELECT count(*)            FROM customers WHERE anniversary IS NOT NULL;    -- 23

SELECT count(*) FROM sales WHERE employeeLastName IS NULL;                   -- 181: the online orders
```

> NULLs print as blank, which is easy to mistake for an empty string.
> `\pset null '∅'` (from the cheatsheet) makes every NULL visible for
> the rest of your session — worth switching on for this lecture.

The same rule bites through arithmetic. `deliveryDate` is NULL for
every in-store order, so `deliveryDate - orderDate` is NULL for them,
so `> 3` isn't true for them, so only online orders can pass:

```sql
SELECT count(*) FROM sales WHERE deliveryDate - orderDate > 3;               -- 93
```

Which is what you'd want here — but notice it happened *silently*.
When a column can be NULL, every condition on it quietly excludes the
NULL rows, whether that was your intention or not.

### Conditions on expressions

`WHERE` accepts anything that produces true or false — including the
expressions from Part 1:

```sql
SELECT count(*) FROM sales WHERE EXTRACT(MONTH FROM orderDate) = 12;         -- 86
SELECT count(*) FROM sales WHERE quantity * unitPrice - orderTotal > 100;    -- 10: discounts over 100
```

### The alias rule, proven

```sql
SELECT orderID, quantity * unitPrice AS list_total
FROM sales
WHERE list_total > 2000;
-- ERROR: column "list_total" does not exist
```

`WHERE` runs *before* `SELECT` invents the alias. Repeat the expression:

```sql
SELECT orderID, quantity * unitPrice AS list_total
FROM sales
WHERE quantity * unitPrice > 2000;
```

Annoying, but not arbitrary: in the execution order from Part 1,
`WHERE` is step 2 and the alias is born at step 5.

---

## Part 3 — ORDER BY, LIMIT, OFFSET (~10 min)

### Several columns, mixed directions

```sql
SELECT productName, price FROM products ORDER BY price;             -- ascending is the default
SELECT productName, price FROM products ORDER BY price DESC LIMIT 5;
```

The second sort column breaks ties in the first:

```sql
SELECT productName, category, price
FROM products
ORDER BY category, price DESC;
```

```
     productname     |  category   |  price
---------------------+-------------+---------
 MX Master 3S        | Accessories |   99.00
 USB-C Hub 7-in-1    | Accessories |   45.00
 Laptop Sleeve 14    | Accessories |   25.50
 M185                | Accessories |   14.99
 WH-1000XM5          | Audio       |  299.00
 AirPods Pro         | Audio       |  249.00
 ...
```

Categories A→Z; within each, most expensive first. Text sorts
alphabetically — and look who lands next to each other:

```sql
SELECT lastName, firstName, city, birthDate
FROM customers
ORDER BY lastName, firstName;
```

```
 ...
 Sargsyan     | Anna      | Yerevan  | 1991-04-12
 Sargsyan     | Anna      | Yerevan  | 1978-10-02
 Sargsyan     | Mher      | Yerevan  | 1983-04-04
 ...
```

Two customers named Anna Sargsyan. Different people, thirteen years
apart. Lecture 2 said a name is not a key; here's the shop where that's
true. You'll meet them again in Parts 4, 5 and 6.

### By expression, alias, or position

```sql
SELECT productName, price - cost AS margin
FROM products
ORDER BY margin DESC                      -- alias works: ORDER BY runs AFTER SELECT
LIMIT 5;

SELECT productName, price, cost
FROM products
ORDER BY (price - cost) / price DESC      -- an expression that isn't even in SELECT
LIMIT 5;

SELECT productName, price FROM products ORDER BY 2 DESC LIMIT 3;   -- "column 2". Works. Fragile.
```

The alias works in `ORDER BY` and didn't in `WHERE`. Not a quirk:
`ORDER BY` is step 7 in the execution order from Part 1, after the
alias is born at step 5; `WHERE` is step 2, before it.

### NULLs sort as if they were bigger than everything

```sql
SELECT firstName, lastName, anniversary FROM customers ORDER BY anniversary;        -- NULLs at the END
SELECT firstName, lastName, anniversary FROM customers ORDER BY anniversary DESC;   -- NULLs FIRST
SELECT firstName, lastName, anniversary FROM customers ORDER BY anniversary DESC NULLS LAST;
```

"Most recent anniversary first" puts seven blank rows at the top of
your report unless you say `NULLS LAST`. Another silent one.

### LIMIT without ORDER BY is not "the first five"

```sql
SELECT orderID, orderDate FROM sales LIMIT 5;
```

```
 orderid | orderdate
---------+------------
    1545 | 2024-12-12
    1071 | 2024-02-28
    1104 | 2024-03-21
    1488 | 2024-11-16
    1565 | 2024-12-19
```

That's the answer to Part 1's question. `LIMIT` alone means *"stop
after five rows, whichever five you reach first"* — here, the order
the file happened to be in. Not the earliest, not the smallest ids,
and not guaranteed to be the same next week. A table has no order
until you give it one:

```sql
SELECT orderID, orderDate, orderTime FROM sales ORDER BY orderDate, orderTime LIMIT 5;
-- 1001, 1002, 1003, 1004, 1005: the actual first five sales of the year
```

### Ties: say how to break them, or the database decides

```sql
SELECT orderID, orderTotal FROM sales ORDER BY orderTotal DESC LIMIT 3;
-- 1158, 1385, 1363 -- three orders at exactly 2500.00
SELECT orderID, orderTotal FROM sales ORDER BY orderTotal DESC LIMIT 2;
-- 1385, 1158 -- WHICH two? Unspecified. (Notice the order even changed.)
SELECT orderID, orderTotal FROM sales ORDER BY orderTotal DESC, orderID LIMIT 2;
-- 1158, 1363 -- now it's defined
```

"Top 2" with a tie and no tiebreaker is not a question with one answer.
Add a column that *is* unique, so it has one.

### OFFSET, and everything together

```sql
SELECT orderID, orderTotal FROM sales ORDER BY orderTotal DESC, orderID LIMIT 5 OFFSET 5;   -- ranks 6-10
```

```sql
SELECT orderID, orderDate, customerLastName, productName, orderTotal
FROM sales
WHERE EXTRACT(MONTH FROM orderDate) = 12 AND status = 'completed'
ORDER BY orderTotal DESC, orderID
LIMIT 5;
```

```
 orderid | orderdate  | customerlastname |    productname     | ordertotal
---------+------------+------------------+--------------------+------------
    1542 | 2024-12-11 | Vardanyan        | MacBook Air 13     |    1870.00
    1588 | 2024-12-27 | Baghdasaryan     | iPhone 15          |    1358.30
    1516 | 2024-12-02 | Hakobyan         | ThinkPad X1 Carbon |    1250.00
    1557 | 2024-12-17 | Manukyan         | ThinkPad X1 Carbon |    1250.00
    1559 | 2024-12-17 | Kocharyan        | ThinkPad X1 Carbon |    1250.00
```

The five biggest completed sales of December. Every clause you know so
far, in one statement.

---

## Part 4 — DISTINCT and aggregates (~15 min)

### DISTINCT: each value once

```sql
SELECT DISTINCT productCategory FROM sales ORDER BY 1;           -- 12 categories sold
SELECT DISTINCT category        FROM products ORDER BY 1;        -- 13 exist
```

Thirteen categories in the catalogue, twelve in the sales. Chairs never
sold. The flat file *cannot* mention a product nobody bought — there's
no row to put it on. That's Lecture 2's insertion anomaly, and you've
just seen it without any theory: the two shapes disagree about how many
categories the shop has.

`DISTINCT` is step 6 in the execution order — it looks at the *output
rows* of `SELECT`, so on several columns it gives each *combination*
once:

```sql
SELECT DISTINCT channel, paymentMethod FROM sales ORDER BY 1, 2;
```

```
 channel  | paymentmethod
----------+---------------
 in_store | card
 in_store | cash
 in_store | transfer
 online   | card
 online   | transfer
```

Five, not six. Nobody pays cash online — a business rule you can read
straight off the data.

### count(*), count(column), count(DISTINCT column)

Three different questions:

```sql
SELECT count(*)               AS rows,
       count(rating)          AS rated,
       count(DISTINCT rating) AS distinct_ratings
FROM sales;
```

```
 rows | rated | distinct_ratings
------+-------+------------------
  600 |   322 |                5
```

- **`count(*)`** counts rows. 600.
- **`count(column)`** counts rows where that column is *not NULL*. Only
  322 orders were rated.
- **`count(DISTINCT column)`** counts different non-NULL values. Five —
  the ratings 1 to 5.

```sql
SELECT count(*) AS orders, count(employeeLastName) AS served_in_store FROM sales;
-- 600 | 419
```

Now the question every shop asks — *how many customers do we have?* —
and watch the answer depend on what you count:

```sql
SELECT count(DISTINCT customerLastName)                          AS surnames,
       count(DISTINCT (customerFirstName, customerLastName))     AS names,
       count(DISTINCT customerEmail)                             AS people
FROM sales;
```

```
 surnames | names | people
----------+-------+--------
       26 |    27 |     28
```

Three Sargsyans, two of them Anna. A surname isn't a person, and
neither is a full name. `count(DISTINCT x)` counts distinct *x* —
whatever you put there had better be something that identifies what
you're actually counting. And one more:

```sql
SELECT count(*) FROM customers;   -- 30
```

Thirty customers, twenty-eight in the sales. Two signed up and never
bought. The flat file doesn't know they exist.

### sum, avg, min, max

```sql
SELECT sum(orderTotal)           AS gross,
       round(avg(orderTotal), 2) AS avg_order,
       min(orderTotal)           AS smallest,
       max(orderTotal)           AS largest
FROM sales;
```

```
   gross   | avg_order | smallest | largest
-----------+-----------+----------+---------
 164092.05 |    273.49 |     8.42 | 2500.00
```

An aggregate collapses every row it sees into one value. Which rows it
sees is decided by `WHERE`, which runs first:

```sql
SELECT sum(orderTotal) AS revenue FROM sales WHERE status = 'completed';    -- 145935.12
SELECT round(avg(orderTotal), 2) FROM sales WHERE productCategory = 'Laptops';   -- 1137.81
```

164,092 and 145,935. The first is every order total in the table; the
second is the ones that weren't returned or cancelled. Only one of them
is revenue. Keep this in mind for Part 6.

### Aggregates ignore NULL

```sql
SELECT round(avg(rating), 2) AS avg_rating, count(rating) AS votes, count(*) AS orders FROM sales;
-- 4.23 | 322 | 600
```

The average is over the 322 votes, not the 600 orders — `avg` skipped
the NULLs rather than counting them as zero. That's the right behaviour
(an unrated order isn't a zero-star order), but it means every average
comes with a hidden "…of the ones that had a value." Always show the
count next to the average.

And an aggregate of *nothing* is NULL, not zero:

```sql
SELECT avg(rating) FROM sales WHERE status = 'cancelled';
-- (blank) -- no cancelled order was ever rated
SELECT coalesce(avg(rating), 0) AS avg_rating FROM sales WHERE status = 'cancelled';   -- 0
```

`coalesce(x, 0)` means "x, or 0 if x is NULL." Use it when a report
needs a number in every cell.

### min/max work on anything that sorts

```sql
SELECT min(orderDate) AS first_sale, max(orderDate) AS last_sale,
       max(orderDate) - min(orderDate) AS span_days
FROM sales;
-- 2024-01-01 | 2024-12-31 | 365

SELECT min(customerLastName), max(customerLastName) FROM sales;   -- Aleksanyan | Zakaryan
```

### Aggregates over expressions

Anything from Part 1 can go inside an aggregate:

```sql
SELECT sum(quantity)                             AS units_sold,
       sum(quantity * unitPrice)                 AS list_value,
       sum(quantity * unitPrice - orderTotal)    AS discounts_given,
       sum(orderTotal)                           AS revenue
FROM sales
WHERE status = 'completed';
```

```
 units_sold | list_value | discounts_given |  revenue
------------+------------+-----------------+-----------
        817 |  149652.81 |         3717.69 | 145935.12
```

```sql
SELECT sum(quantity * (productPrice - productCost)) AS gross_margin
FROM sales
WHERE status = 'completed';
-- 37459.81
```

The shop kept 37,460 of its 145,935. Two columns and one line of
arithmetic — no spreadsheet, no export.

### A share is a sum of a CASE

"What fraction of orders are online?" Turn the condition into a 1 or 0
and add them up:

```sql
SELECT sum(CASE WHEN channel = 'online' THEN 1 ELSE 0 END) AS online_orders,
       count(*)                                            AS all_orders,
       round(100.0 * sum(CASE WHEN channel = 'online' THEN 1 ELSE 0 END) / count(*), 1) AS online_pct
FROM sales;
-- 181 | 600 | 30.2
```

That `100.0` — not `100` — is doing real work. Part 6 shows what
happens without it. Postgres also has a shorthand for exactly this
pattern:

```sql
SELECT count(*) FILTER (WHERE status = 'returned') AS returned,
       count(*)                                    AS total
FROM sales;
-- 44 | 600
```

### One number per *what*?

Every aggregate so far produced one row. The interesting questions
produce one row *per something* — per category, per month, per
employee. Try the obvious thing:

```sql
SELECT productCategory, sum(orderTotal) FROM sales;
-- ERROR: column "sales.productcategory" must appear in the GROUP BY clause
--        or be used in an aggregate function
```

`sum()` collapses 600 rows into one. `productCategory` has 600 values.
Which one goes in the one row? Postgres won't guess. You have to say
what the groups are.

---

## Part 5 — GROUP BY and HAVING (~25 min)

### One row per group

```sql
SELECT productCategory, count(*) AS orders, sum(orderTotal) AS revenue
FROM sales
WHERE status = 'completed'
GROUP BY productCategory
ORDER BY revenue DESC;
```

```
 productcategory | orders | revenue
-----------------+--------+----------
 Laptops         |     46 | 53412.00
 Phones          |     38 | 25991.90
 Audio           |     55 | 15846.55
 Tablets         |     25 | 11753.30
 Monitors        |     32 | 11718.20
 Accessories     |     88 |  6388.74
 Keyboards       |     40 |  5839.68
 Storage         |     69 |  4996.83
 Webcams         |     29 |  3702.35
 Printers        |     13 |  2408.65
 Networking      |     17 |  2225.75
 Cables          |     77 |  1651.17
```

`GROUP BY productCategory` splits the rows into twelve piles, one per
category, and every aggregate in `SELECT` is computed *inside each
pile*. Twelve rows out. Laptops: 46 orders, 37% of revenue.
Accessories: the most orders, 4% of revenue. That's the report.

**The rule:** every column in `SELECT` is either *in the `GROUP BY`* or
*inside an aggregate*. Nothing else — because for a pile of 46 laptop
orders there is no single `productName` to show. Break it and read the
error:

```sql
SELECT productCategory, productName, count(*)
FROM sales
GROUP BY productCategory;
-- ERROR: column "sales.productname" must appear in the GROUP BY clause
--        or be used in an aggregate function
```

You will see that error a hundred times this semester. It always means
the same thing: *you asked for a per-row value in a per-group answer.*

### Several grouping columns

One row per *combination that actually occurs*:

```sql
SELECT productCategory, productBrand, count(*) AS orders, sum(orderTotal) AS revenue
FROM sales
WHERE status = 'completed'
GROUP BY productCategory, productBrand
ORDER BY productCategory, revenue DESC;
```

```
 productcategory | productbrand | orders | revenue
-----------------+--------------+--------+----------
 Accessories     | Logitech     |     47 |  3564.83
 Accessories     | Anker        |     18 |  1770.75
 Accessories     | Generic      |     23 |  1053.16
 Audio           | Apple        |     16 |  6847.50
 ...
 Laptops         | Lenovo       |     18 | 26937.50
 Laptops         | Apple        |     10 | 11220.00
 ...
(32 rows)
```

```sql
SELECT channel, paymentMethod, count(*) AS orders
FROM sales
GROUP BY channel, paymentMethod
ORDER BY channel, paymentMethod;
-- the five combinations from Part 4, now with counts
```

### Group by an expression

You can group by anything you could put in `SELECT` — which is where
Part 1's date functions pay off:

```sql
SELECT EXTRACT(MONTH FROM orderDate) AS month, count(*) AS orders, sum(orderTotal) AS revenue
FROM sales
WHERE status = 'completed'
GROUP BY month
ORDER BY month;
```

```
 month | orders | revenue
-------+--------+----------
     1 |     35 |  9048.14
     2 |     31 |  5988.88
     3 |     38 |  6214.71
     4 |     33 | 14175.94
     5 |     53 | 13099.89
     6 |     26 |  9345.70
     7 |     37 | 11246.30
     8 |     47 | 11771.40
     9 |     52 | 14084.14
    10 |     37 | 10184.36
    11 |     66 | 14486.72
    12 |     74 | 26288.94
```

December is the whole story of this shop's year. (Postgres lets you
write the alias `month` in `GROUP BY`; strict SQL would make you repeat
the `EXTRACT`.)

```sql
SELECT EXTRACT(DOW FROM orderDate) AS dow, to_char(orderDate, 'Dy') AS weekday, count(*) AS orders
FROM sales
GROUP BY dow, weekday
ORDER BY dow;
```

```
 dow | weekday | orders
-----+---------+--------
   1 | Mon     |     97
   2 | Tue     |     94
   3 | Wed     |    101
   4 | Thu     |     97
   5 | Fri     |    119
   6 | Sat     |     92
```

No row for 0. The shop is closed on Sundays, and nobody had to tell
you — a missing group is information too. (Why group by both `dow` and
`weekday`? Because `weekday` is in `SELECT`, so the rule says it must
be grouped. It adds nothing — every `dow` has exactly one name — but
the rule is the rule. `dow` is there so `ORDER BY` can sort Monday
before Tuesday instead of alphabetically.)

```sql
SELECT EXTRACT(HOUR FROM orderTime) AS hour, count(*) AS orders
FROM sales
WHERE channel = 'online'
GROUP BY hour
ORDER BY orders DESC
LIMIT 5;
-- 20:00, 19:00, 21:00 -- people shop online after dinner

SELECT split_part(email, '@', 2) AS domain, count(*) AS customers
FROM customers
GROUP BY domain
ORDER BY customers DESC;
-- gmail.com 18, mail.ru 6, yahoo.com 3, outlook.com 3
```

### Group by a CASE: buckets

The `size` label from Part 1, as a grouping:

```sql
SELECT CASE
           WHEN orderTotal >= 1000 THEN 'large'
           WHEN orderTotal >= 100  THEN 'medium'
           ELSE                         'small'
       END AS size,
       count(*) AS orders, sum(orderTotal) AS revenue
FROM sales
WHERE status = 'completed'
GROUP BY size
ORDER BY min(orderTotal);
```

```
  size  | orders | revenue
--------+--------+----------
 small  |    247 | 10819.80
 medium |    250 | 89044.52
 large  |     32 | 46070.80
```

Thirty-two orders — six percent of them — are a third of the money.
`CASE` + `GROUP BY` is how you turn a number into a category and then
count the categories; it's one of the most-used patterns in business
SQL. (And `ORDER BY min(orderTotal)` — an aggregate that isn't in
`SELECT` — is allowed, and is how you sort buckets by size rather than
by name.)

### NULL is a group of its own

```sql
SELECT employeeLastName, count(*) AS orders
FROM sales
GROUP BY employeeLastName
ORDER BY orders DESC;
```

```
 employeelastname | orders
------------------+--------
                  |    181
 Harutyunyan      |     91
 Mkrtchyan        |     90
 Melikyan         |     65
 ...
```

The blank row at the top is the 181 online orders — no salesperson.
`GROUP BY` puts all the NULLs in one pile, and that pile can easily be
the biggest one. If this were "sales by employee" on a slide, the top
bar would be a person who doesn't exist.

```sql
SELECT rating, count(*) AS orders
FROM sales
GROUP BY rating
ORDER BY rating;
-- 1: 5, 2: 13, 3: 37, 4: 115, 5: 152, NULL: 278
```

### What you group by decides what a "customer" is

```sql
SELECT customerFirstName, customerLastName, count(*) AS orders, sum(orderTotal) AS spent
FROM sales
WHERE customerLastName = 'Sargsyan'
GROUP BY customerFirstName, customerLastName;
```

```
 customerfirstname | customerlastname | orders |  spent
-------------------+------------------+--------+---------
 Anna              | Sargsyan         |     37 | 9187.60
 Mher              | Sargsyan         |      8 | 2167.56
```

"Anna Sargsyan: 37 orders, 9,188 spent." **There is no such person.**
Two women share the name; `GROUP BY` name made them one pile. Group by
something that identifies a *person*:

```sql
SELECT customerFirstName, customerLastName, customerEmail, count(*) AS orders, sum(orderTotal) AS spent
FROM sales
WHERE customerLastName = 'Sargsyan'
GROUP BY customerFirstName, customerLastName, customerEmail;
```

```
 customerfirstname | customerlastname |      customeremail      | orders |  spent
-------------------+------------------+-------------------------+--------+---------
 Anna              | Sargsyan         | anna.sargsyan78@mail.ru |      9 | 2100.34
 Anna              | Sargsyan         | anna.sargsyan@gmail.com |     28 | 7087.26
 Mher              | Sargsyan         | mher.sargsyan@gmail.com |      8 | 2167.56
```

This is Lecture 2's "what identifies a customer?" question, coming back
to collect. In the normalized tables it's `customerID` and the problem
can't happen. In the flat file there is no id, and it happens the
moment two people share a name.

### A real report

```sql
SELECT employeeFirstName || ' ' || employeeLastName AS employee,
       employeeBranch,
       count(*)                  AS orders,
       sum(orderTotal)           AS revenue,
       round(avg(orderTotal), 2) AS avg_ticket
FROM sales
WHERE status = 'completed' AND channel = 'in_store'
GROUP BY employee, employeeBranch
ORDER BY revenue DESC;
```

```
      employee      | employeebranch | orders | revenue  | avg_ticket
--------------------+----------------+--------+----------+------------
 Ani Harutyunyan    | Yerevan Center |     83 | 22470.92 |     270.73
 Gor Mkrtchyan      | Yerevan Center |     74 | 19323.29 |     261.13
 Hayk Melikyan      | Yerevan Mall   |     58 | 18514.30 |     319.21
 Nare Ghazaryan     | Yerevan Mall   |     49 | 10966.86 |     223.81
 Arman Grigoryan    | Gyumri         |     26 |  7293.02 |     280.50
 Lilit Hovhannisyan | Yerevan Mall   |     26 |  6453.48 |     248.21
 Vahe Sahakyan      | Yerevan Center |     30 |  6318.83 |     210.63
 Marine Avagyan     | Gyumri         |     19 |  2194.01 |     115.47
```

Read the `WHERE` twice. `status = 'completed'` so returns don't count as
sales; `channel = 'in_store'` so the 181-order NULL pile doesn't appear
at the top. Both filters are business decisions, and both are invisible
in the output. Whoever reads this table is trusting you made them.

Ani sold the most; Hayk sells the biggest tickets. Which one is "the
best" isn't a database question — but now both numbers are on the
table, with the definitions that produced them.

### HAVING: a WHERE for groups

`WHERE` picks rows. Once the rows are grouped, you often want to pick
*groups* — customers who spent over 8,000, products with enough ratings
to trust. That's `HAVING`:

```sql
SELECT customerEmail, count(*) AS orders, sum(orderTotal) AS spent
FROM sales
WHERE status = 'completed'
GROUP BY customerEmail
HAVING sum(orderTotal) > 8000
ORDER BY spent DESC;
```

```
        customeremail         | orders |  spent
------------------------------+--------+----------
 aram.vardanyan@gmail.com     |     38 | 13544.72
 artur.baghdasaryan@gmail.com |     33 | 10451.07
 armen.gevorgyan@gmail.com    |     44 |  9172.79
 lilit.hovhannisyan@mail.ru   |     25 |  8978.29
 vahan.torosyan@yahoo.com     |     22 |  8575.72
 davit.petrosyan@mail.ru      |     43 |  8230.04
```

```sql
SELECT productName, count(rating) AS votes, round(avg(rating), 2) AS avg_rating
FROM sales
GROUP BY productName
HAVING count(rating) >= 10
ORDER BY avg_rating DESC, votes DESC;
-- 12 products with at least ten votes; UltraSharp 27 leads at 4.50
```

That `HAVING count(rating) >= 10` is what stops a product with one
five-star review from topping the list. Averages of tiny groups are
noise; `HAVING` is how you say so.

Why two keywords for "filter"? Because they run at different moments.
`WHERE` can't see an aggregate — when it runs, the groups don't exist
yet:

```sql
SELECT productCategory, count(*)
FROM sales
WHERE count(*) > 50
GROUP BY productCategory;
-- ERROR: aggregate functions are not allowed in WHERE
```

And `HAVING` can't see a `SELECT` alias — it runs before `SELECT`:

```sql
SELECT productCategory, sum(orderTotal) AS revenue
FROM sales
GROUP BY productCategory
HAVING revenue > 10000;
-- ERROR: column "revenue" does not exist
```

`HAVING` *does* see aggregates — it just saw `sum(orderTotal)` in the
previous query, and it can use one that `SELECT` doesn't output at all:

```sql
SELECT productCategory
FROM sales
GROUP BY productCategory
HAVING sum(orderTotal) > 10000;
-- 5 rows, and no revenue column anywhere in the output
```

What it can't see is the *name* `SELECT` gives the result. Repeat the
expression, same as in `WHERE`:

```sql
SELECT productCategory, sum(orderTotal) AS revenue
FROM sales
GROUP BY productCategory
HAVING sum(orderTotal) > 10000
ORDER BY revenue DESC;
-- Laptops, Phones, Audio, Tablets, Monitors
```

### Everything at once

```sql
SELECT productBrand,
       count(*)                                      AS orders,
       sum(orderTotal)                               AS revenue,
       sum(quantity * (productPrice - productCost))  AS margin
FROM sales
WHERE status = 'completed' AND orderDate >= '2024-07-01'
GROUP BY productBrand
HAVING count(*) >= 10
ORDER BY margin DESC
LIMIT 5;
```

```
 productbrand | orders | revenue  | margin
--------------+--------+----------+---------
 Lenovo       |     14 | 20687.50 | 4590.00
 Apple        |     38 | 20093.70 | 4269.00
 Samsung      |     28 | 11153.25 | 2724.00
 Logitech     |     63 |  6497.17 | 2591.42
 Anker        |     34 |  2276.13 | 1039.70
```

"Second-half brands with at least ten sales, by margin, top five." Read
it clause by clause and every word of that sentence is in there.

```sql
SELECT productCategory,
       count(*)                                     AS orders,
       count(*) FILTER (WHERE status = 'returned')  AS returned,
       round(100.0 * count(*) FILTER (WHERE status = 'returned') / count(*), 1) AS return_pct
FROM sales
GROUP BY productCategory
ORDER BY return_pct DESC;
-- Printers 22.2%, Monitors 15.4%, ... Webcams 0.0%
```

One in five printers comes back. That's a conversation with the
supplier, and it took six lines.

### The order the clauses actually run in — the full list, again

You've now met every clause. Here is the execution order from Part 1
once more, with what each step can and cannot see. Every error in this
guide is the same fact wearing a different hat:

```
FROM       which table
WHERE      which rows                     (can't see aliases or aggregates)
GROUP BY   collapse rows into groups
HAVING     which groups                   (can see aggregates; can't see aliases)
SELECT     which columns and aggregates   (aliases are born here)
DISTINCT   drop duplicate result rows
ORDER BY   in what order                  (can see aliases)
LIMIT      how many
```

You *write* `SELECT` first. It *runs* fifth. That's why `WHERE
list_total > 2000` failed, why `HAVING revenue > 10000` failed, why
`ORDER BY margin` worked, and why `WHERE count(*) > 50` can never work.
Memorise the list, and the errors stop being surprising.

---

## Part 6 — Verification drill (~10 min)

The shop owner asked an AI assistant for four numbers. Every query runs
without error and returns a plausible answer. Every one is wrong.
**Have a theory for each before reading the answers.** This is the
skill the rest of the course is built on.

**Q1. "Total revenue for 2024."**

```sql
SELECT sum(orderTotal) AS revenue FROM sales;
-- 164092.05
```

**Q2. "How much has the average customer spent with us, lifetime?"**

```sql
SELECT round(avg(customerMoneySpent), 2) AS avg_customer_spend FROM sales;
-- 6799.93
```

**Q3. "How many different customers bought something in December?"**

```sql
SELECT count(DISTINCT customerLastName) AS december_customers
FROM sales
WHERE orderDate BETWEEN '2024-12-01' AND '2024-12-31';
-- 24
```

**Q4. "What share of our orders are laptops?"**

```sql
SELECT sum(CASE WHEN productCategory = 'Laptops' THEN 1 ELSE 0 END) / count(*) AS laptop_share
FROM sales;
-- 0
```

Stop here. Work it out.

### Answers

**Q1 — status.** 71 of the 600 rows are returned or cancelled orders.
Their totals are in the table. They are not revenue.

```sql
SELECT sum(orderTotal) AS revenue FROM sales WHERE status = 'completed';   -- 145935.12
```

Overstated by 18,156.93. Every "revenue" query on this data needs that
`WHERE`, and nothing about the table will remind you.

**Q2 — grain.** The flat file repeats a customer's lifetime total on
*every one of their orders*. Aram Vardanyan's 13,544.72 is in there 40
times; Diana Aleksanyan's 2,327.00 four times. `avg()` over `sales` is
an average of *orders*, weighted by how much each person buys — not an
average of customers.

```sql
SELECT round(avg(moneySpent), 2) FROM customers;                        -- 4864.50 (all 30)
SELECT round(avg(moneySpent), 2) FROM customers WHERE moneySpent > 0;   -- 5211.97 (the 28 who bought)
```

Which of those two is "right" depends on whether the two customers who
never bought count as customers — a business decision. 6,799.93 is
neither. Before you `avg()` anything: *one row per what?* This is the
same redundancy Lecture 2 measured by hand, now costing you money.

**Q3 — identity.** Three Sargsyans, two of them Anna. A surname isn't a
person.

```sql
SELECT count(DISTINCT customerEmail) AS december_customers
FROM sales
WHERE orderDate BETWEEN '2024-12-01' AND '2024-12-31';                 -- 26
```

`count(DISTINCT x)` counts distinct *x*. Make *x* something that
identifies what you're counting.

**Q4 — integer division.** Both sides of that `/` are whole numbers, so
51 / 600 is 0 with the remainder thrown away. One decimal anywhere in
the expression fixes it:

```sql
SELECT round(100.0 * sum(CASE WHEN productCategory = 'Laptops' THEN 1 ELSE 0 END) / count(*), 1)
       AS laptop_pct
FROM sales;                                                            -- 8.5
```

0 looked like "no laptops." Fifty-one were sold, and they're a third of
the revenue.

**Business impact, one sentence each — the format you'll use all
semester:**

- Q1: 2024 revenue is overstated by 18,156.93; returns and
  cancellations were booked as sales.
- Q2: the average customer is worth 4,864, not 6,800 — a marketing
  budget sized on 6,800 overspends by 40%.
- Q3: two December customers went uncounted, and any surname shared by
  two people will be miscounted the same way every month.
- Q4: the laptop share reads as zero; a buyer trusting it would stop
  stocking the shop's biggest revenue category.

None of these threw an error. None of the numbers look absurd. All four
would have gone into a slide deck. Lecture 2 showed you the database
saying no; this is the other kind of wrong — the kind where it says yes.

---

## Summary

- A `SELECT` column can be any **expression**: arithmetic, `||`,
  `round`, `upper`, `split_part`, `EXTRACT`, `to_char`, date
  subtraction, `age`, and **`CASE WHEN`** — a value that depends on a
  condition. `AS` names it.
- The full **`WHERE`**: `=`, `<>`, `BETWEEN` (inclusive), `IN`, `LIKE`
  / `ILIKE` with `%` and `_`, `IS NULL`. Text comparison is
  case-sensitive. **`AND` binds tighter than `OR`** — parenthesise
  whenever both appear.
- **`NULL`** is "no value." `x = NULL` is never true; test with `IS
  NULL`. NULL poisons arithmetic and comparisons, sorts as if largest
  (`NULLS LAST` to fix), is skipped by aggregates, and forms its own
  group in `GROUP BY`.
- **`ORDER BY`** takes several columns, expressions, aliases;
  **`LIMIT`** without `ORDER BY` is not "the top"; ties need a
  tiebreaker; **`OFFSET`** skips.
- **`count(*)`** counts rows, **`count(col)`** counts non-NULLs,
  **`count(DISTINCT col)`** counts different values — and *col* had
  better identify what you're counting. `sum`, `avg`, `min`, `max`
  see only the rows `WHERE` lets through; `coalesce` turns a NULL
  result into a number.
- **`GROUP BY`** gives one row per group. Every `SELECT` column is
  grouped or aggregated. Group by expressions and `CASE` buckets.
  **`HAVING`** filters groups after they exist.
- The clauses run `FROM → WHERE → GROUP BY → HAVING → SELECT →
  DISTINCT → ORDER BY → LIMIT`, whatever order you write them. Aliases
  are born at `SELECT`; nothing earlier can use them.
- Four ways a query lies without an error: a missing **status
  filter**, averaging at the wrong **grain**, counting the wrong
  **identity**, and **integer division**. Before you trust a number:
  which rows did it see, one row per what, and is there a decimal in
  the fraction?

**Next lecture:** combining tables. Every report in this guide came off
the flat `sales` table because it had the names on it — but the flat
table doesn't know about Chairs, or the two customers who never bought,
or that two Annas are two people. The normalized tables know all of
that, and next time you learn to ask them the same questions. Lecture
2's promised topics — `moneySpent`, `order_items`, and when it's right
to denormalize on purpose — come with it.

---

## Files

| File | What it is |
|---|---|
| `steps/00-setup.sql` | Creates the five tables and loads them from `data/*.csv`. Drops and recreates, so it's also the reset button. Run it from this folder |
| `steps/01-select.sql` … `steps/06-drill.sql` | One file per Part, numbered to match. None of them changes the data, so run them in any order, as often as you like |
| `lecture-03-demo.sql` | Every statement above, runnable in order, in one file. Five statements error on purpose |
| `data/sales_flat.csv` | The flat file — 600 rows × 29 columns, one row per sale |
| `data/customers.csv`, `employees.csv`, `products.csv`, `orders.csv` | The same sales, normalized — 30 / 8 / 37 / 600 rows |
| `data/all_inserts.sql` | Every CSV row as a plain `INSERT` — the fallback if `\copy` can't find the files |
| `generate_data.py` | The script that made the CSVs. Seeded, so re-running it reproduces them exactly; the header comment lists every property the lecture relies on |
| `../lecture_2/psql-cheatsheet.md` | Still the reference for `psql` itself — connecting, `\d`, `\x`, `\copy`, troubleshooting |
