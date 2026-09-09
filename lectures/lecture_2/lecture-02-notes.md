# Lecture 2 — From One File to Four Tables

**A hands-on guide** · Introduction to Databases & SQL · YSU, Data Science for Business

---

## How to use this guide

This is written to be worked through at a keyboard, not just read. Each part
explains one idea and then hands you SQL to run yourself. Type or paste it
into your own database, look at what actually comes back, and compare it
to the expected output shown before moving on — don't skim a query and
assume you know what it returns.

Total time if you go through it start to finish: **~75 minutes**, at
whatever pace you need. Stop anywhere; nothing here is timed.

## Before you start

You need:

- **PostgreSQL** running somewhere you can connect to, and the `psql`
  client (any SQL client that runs raw SQL and shows you error messages —
  e.g. DBeaver — also works).
- A terminal open **in this folder** (`lectures/lecture_2/` — the same
  folder as this file and `lecture-02-demo.sql`), which contains a `data/`
  subfolder with `sales_flat.csv` and the four expected-result CSVs.
  `\copy` resolves file paths relative to wherever you *started* `psql`,
  not the database server — getting this wrong is the most common cause
  of a "file not found" error below.

Create a scratch database and connect to it:

```bash
createdb lecture02
psql lecture02
```

No `createdb` on your machine? Connect to any existing database and run
`CREATE DATABASE lecture02;`, then `\c lecture02`.

Two ways to work through what follows — pick one:

- **Statement by statement (recommended the first time):** copy each SQL
  block below into your `psql` session as you read, and compare your
  output to what's shown. All paths in this guide are written relative to
  **this** folder (`lecture_2/`), so run `psql` from here.
- **All at once:** open `lecture-02-demo.sql` and run it with `\i`, then
  scroll back through the output as you read the explanations here. As
  shipped, that script loads the CSV with a bare filename
  (`'sales_flat.csv'`), so it only finds the file if you `cd` into `data/`
  first and run `\i ../lecture-02-demo.sql` from there. If that's more
  friction than you want, use the statement-by-statement path instead —
  every block in this guide already points at `data/` correctly.

## Where we left off

Lecture 1 ended by *defining* SQL — but you haven't written a line of it
yet. It also showed the schema slide: four tables, with exact columns and
types.

| Table | Columns |
|---|---|
| **Customers** | `customerID INT`, `firstName VARCHAR(50)`, `lastName VARCHAR(50)`, `birthDate DATE`, `moneySpent DECIMAL(10,2)`, `anniversary DATE` |
| **Employees** | `employeeID INT`, `firstName VARCHAR(50)`, `lastName VARCHAR(50)`, `birthDate DATE` |
| **Products** | `productID INT`, `category VARCHAR(100)`, `price DECIMAL(8,2)` |
| **Orders** | `orderID INT`, `customerID INT`, `employeeID INT`, `productID INT`, `orderTotal DECIMAL(10,2)`, `orderDate DATE` |

**In this guide, you build exactly that schema — out of one file.**

Lecture 1 also made two claims, on the "File System" and "Database
Approach" slides: that files cause redundancy and inconsistency, and that
the database approach fixes it. Those were assertions. Here, they become
something you do with your own hands.

**By the end of this guide, you should be able to:**

1. Understand what SQL is (and is not), and how its parts are organized.
2. Recognize redundancy in a flat file and explain why it is dangerous.
3. Create tables with primary keys, foreign keys and constraints.
4. Split one wide file into the four tables from the schema slide — and join them back.
5. Write basic `SELECT` queries.

---

## Part 1 — What SQL is (~15 min)

### SQL is declarative

The single most important idea in this lecture.

In Excel or Python you describe **how**: loop through the rows, check each
one, collect the matches. In SQL you describe **what**: "the customers
born before 1990." The database decides *how* — which file to read, in
what order, using which shortcut.

> You state the goal. The system chooses the method.

That is why the same statement can run in 10 milliseconds or 10 minutes —
and why a later lecture is devoted entirely to asking the database *why*
it chose what it chose.

### A short history (one minute)

- **1970** — Edgar Codd at IBM publishes the relational model: store data in plain tables, let a language do the navigating.
- **1974** — IBM's System R builds SEQUEL, later renamed SQL.
- **1979** — Oracle ships the first commercial SQL database.
- **1986** — SQL becomes an ANSI standard.
- **Today** — still the standard, fifty years later.

Worth sitting with: *almost no technology from 1974 is still in daily use.
SQL is. That's why it's worth your semester.*

### The five sub-languages

Think of this as a filing cabinet: every SQL statement you'll meet this
semester goes into one of these five drawers.

| Part | Stands for | Does | Statements |
|---|---|---|---|
| **DDL** | Data **Definition** Language | defines structure | `CREATE`, `ALTER`, `DROP` |
| **DML** | Data **Manipulation** Language | changes data | `INSERT`, `UPDATE`, `DELETE` |
| **DQL** | Data **Query** Language | reads data | `SELECT` |
| **DCL** | Data **Control** Language | controls access | `GRANT`, `REVOKE` |
| **TCL** | **Transaction** Control Language | groups changes | `COMMIT`, `ROLLBACK` |

In this guide, you'll move through them in order: **DDL** → **DML** →
**DQL**. **DCL** and **TCL** come later in the course.

### The types on the schema slide

Every type on that slide is a rule the database enforces for you.

| Type from the slide | Meaning | Note |
|---|---|---|
| `INT` | whole number | ids, counts |
| `VARCHAR(50)` | text, max 50 characters | in PostgreSQL, plain `TEXT` performs identically |
| `DATE` | a calendar date | supports real date arithmetic |
| `DECIMAL(10,2)` | **exact** decimal, 10 digits, 2 after the point | the money type — `0.1 + 0.2` is exactly `0.3` |
| `DECIMAL(8,2)` | same, smaller range | used for `price` |

> **Try it yourself.** If `price` were stored as text instead of a number,
> sorting would put `'9.99'` *after* `'52.00'` — because text sorts
> character by character, not by value. Run this to see it:
>
> ```sql
> SELECT unnest(ARRAY['9.99', '52.00', '100.00']) AS price_as_text
> ORDER BY 1;
> ```
>
> `100.00` sorts before `52.00`, which sorts before `9.99` — the exact
> opposite of numeric order. That's why `price` on the schema is
> `DECIMAL`, not text.

> **Note on naming:** PostgreSQL folds unquoted identifiers to lowercase,
> so `customerID` becomes `customerid`. Everything still works — just
> don't be alarmed when a column header in your own output looks
> different from how it's written here or on the Lecture 1 slide.

---

## Part 2 — The problem in the file (~10 min)

**File:** `data/sales_flat.csv` — 42 rows × 13 columns, one row per sale.
This is what a real spreadsheet export looks like.

```sql
CREATE TABLE sales_raw (
    orderID              INT,
    orderDate            DATE,
    customerFirstName    VARCHAR(50),
    customerLastName     VARCHAR(50),
    customerBirthDate    DATE,
    customerMoneySpent   DECIMAL(10,2),
    customerAnniversary  DATE,
    employeeFirstName    VARCHAR(50),
    employeeLastName     VARCHAR(50),
    employeeBirthDate    DATE,
    productCategory      VARCHAR(100),
    productPrice         DECIMAL(8,2),
    orderTotal           DECIMAL(10,2)
);
```

Load it. `\copy` runs on **your** machine (a psql command); `COPY` runs on
the **server**. Run this from `psql` started in the `lecture_2/` folder:

```sql
\copy sales_raw FROM 'data/sales_flat.csv' WITH (FORMAT csv, HEADER true);

SELECT * FROM sales_raw ORDER BY orderDate, orderID LIMIT 10;
```

### Guess before you run

Look at the 10 rows you just printed and guess: **how many customers does
this shop actually have?** Write your number down — then run the next
three queries and see how close you were.

```sql
SELECT count(*)                         AS total_rows     FROM sales_raw;  -- 42
SELECT count(DISTINCT customerLastName) AS real_customers FROM sales_raw;  -- 8
SELECT count(DISTINCT productCategory)  AS real_products  FROM sales_raw;  -- 6
```

**42 rows, but only 8 customers and 6 product categories.** Anna's birth
date is stored six times. The Audio price is stored nine times.

```sql
SELECT customerFirstName, customerLastName, count(*) AS times_stored
FROM sales_raw
GROUP BY customerFirstName, customerLastName
ORDER BY times_stored DESC;
```

Run it and confirm that for yourself.

### Why redundancy is dangerous

Before reading the table below, work through each row yourself: what
actually breaks, and what would you call the failure?

| Scenario | What happens | Name |
|---|---|---|
| Anna's birth date was entered wrong | You must fix **every** copy | update anomaly |
| You miss one copy | Two different "truths" now exist | **inconsistency** |
| A new product category hasn't sold yet | Nowhere to put it — there's no row | insertion anomaly |
| You delete the last order in a category | The category vanishes entirely | deletion anomaly |

This is exactly what Lecture 1's "File System" slide claimed. Now you've
seen it in your own data.

---

## Part 3 — The design (~10 min — no SQL, just work it out on paper)

**The rule: one table per real-world thing.**

Customers, Employees and Products are **entities** — they exist
independently. An Order is an **event** that connects them. That's
precisely the shape of the schema slide: three boxes feeding into
`Orders`.

```
Customers ──┐
Employees ──┼──> Orders
Products  ──┘
```

### The question that earns the key concept

> *"What identifies a customer? We have no email, no phone number — just
> names and a birth date."*

Try to answer it yourself before reading on:

- **First name?** Obviously not.
- **First + last name?** Two people can both be "Anna Sargsyan."
- **First + last + birthDate?** Now it's *probably* unique. This is a
  **composite natural key** — three columns together doing the job of
  one.
- **But it's fragile:** three columns to carry into every other table, a
  typo in any of them breaks the link, and it still isn't guaranteed
  unique.

**So we invent `customerID`** — a **surrogate key**, one small integer
that means nothing outside the database and never changes. That is
exactly what the schema slide shows, and now you know *why* it's there
rather than just that it is.

> **Optional — worth 3 minutes if you're curious.**
> Look at `moneySpent` on Customers. Where does that number come from?
> It's the sum of that customer's orders — the database can compute it
> any time. Storing it means every new order must also update it, and if
> that ever fails, the stored number silently disagrees with reality.
> Stored-vs-computed is a real design trade-off, and we'll come back to
> it. *(In our file `moneySpent` does match the order totals —
> verifiable after the split, in Part 7.)*

---

## Part 4 — DDL: creating the tables (~10 min)

Exactly the schema slide, now as real SQL. Run all four:

```sql
-- 6 columns
CREATE TABLE customers (
    customerID   SERIAL PRIMARY KEY,          -- surrogate key, auto-generated
    firstName    VARCHAR(50) NOT NULL,
    lastName     VARCHAR(50) NOT NULL,
    birthDate    DATE,
    moneySpent   DECIMAL(10,2) DEFAULT 0 CHECK (moneySpent >= 0),
    anniversary  DATE
);

-- 4 columns
CREATE TABLE employees (
    employeeID   SERIAL PRIMARY KEY,
    firstName    VARCHAR(50) NOT NULL,
    lastName     VARCHAR(50) NOT NULL,
    birthDate    DATE
);

-- 3 columns
CREATE TABLE products (
    productID    SERIAL PRIMARY KEY,
    category     VARCHAR(100) NOT NULL UNIQUE,
    price        DECIMAL(8,2) NOT NULL CHECK (price >= 0)
);

-- 6 columns — the EVENT table
CREATE TABLE orders (
    orderID      INT PRIMARY KEY,
    customerID   INT NOT NULL REFERENCES customers(customerID),
    employeeID   INT NOT NULL REFERENCES employees(employeeID),
    productID    INT NOT NULL REFERENCES products(productID),
    orderTotal   DECIMAL(10,2) NOT NULL CHECK (orderTotal >= 0),
    orderDate    DATE NOT NULL
);
```

**Notice what is *not* in `orders`:** no customer name, no category text,
no employee name. Only references. Each fact lives in exactly one place —
which is what the blue connector lines on the schema slide were showing.

### The vocabulary, now that you've seen it in code

| Constraint | Meaning |
|---|---|
| `PRIMARY KEY` | Uniquely identifies a row. Never null, never duplicated |
| `REFERENCES` (foreign key) | This value **must exist** in the other table — *referential integrity* |
| `UNIQUE` | No two rows may share this value |
| `NOT NULL` | This fact is required |
| `CHECK` | A rule you invent, enforced by the database |
| `SERIAL` | Auto-incrementing integer — the database generates the ids |

This is the "Business Impact" line on the schema slide made literal:
*prevents corrupt data entry, ensures financial transactions always map
to valid customers.* The foreign keys are what deliver it.

---

## Part 5 — DML: filling the tables (~10 min)

**Parents first, children last.** The foreign keys won't allow otherwise
— which is itself the lesson: try inserting into `orders` first if you
want to see that for yourself.

`DISTINCT` is what removes the redundancy: 42 rows become 8.

```sql
INSERT INTO customers (firstName, lastName, birthDate, moneySpent, anniversary)
SELECT DISTINCT customerFirstName, customerLastName, customerBirthDate,
                customerMoneySpent, customerAnniversary
FROM sales_raw;

INSERT INTO employees (firstName, lastName, birthDate)
SELECT DISTINCT employeeFirstName, employeeLastName, employeeBirthDate
FROM sales_raw;

INSERT INTO products (category, price)
SELECT DISTINCT productCategory, productPrice
FROM sales_raw;
```

Orders are harder: the raw file holds *names and categories*, but the
table needs *id numbers*. You have to translate — and translation is a
`JOIN`.

Notice the customer join uses **all three** columns of the natural key.
That's the fragility from Part 3, now visible in the code.

```sql
INSERT INTO orders (orderID, customerID, employeeID, productID, orderTotal, orderDate)
SELECT r.orderID, c.customerID, e.employeeID, p.productID, r.orderTotal, r.orderDate
FROM sales_raw r
JOIN customers c ON c.firstName = r.customerFirstName
                AND c.lastName  = r.customerLastName
                AND c.birthDate = r.customerBirthDate
JOIN employees e ON e.firstName = r.employeeFirstName
                AND e.lastName  = r.employeeLastName
                AND e.birthDate = r.employeeBirthDate
JOIN products  p ON p.category  = r.productCategory;
```

Check the result:

```sql
SELECT 'sales_raw' AS t, count(*) FROM sales_raw
UNION ALL SELECT 'customers', count(*) FROM customers
UNION ALL SELECT 'employees', count(*) FROM employees
UNION ALL SELECT 'products',  count(*) FROM products
UNION ALL SELECT 'orders',    count(*) FROM orders;
```

Expected: **42 / 8 / 4 / 6 / 42**

> If your `orders` count is not 42, the join is wrong somewhere — this is
> the most common mistake at this step, and the row count is how you
> catch it. Go back through the join conditions one at a time against
> `sales_raw` if you need to debug it.

The four resulting tables are also included as separate files so you can
compare your own output against them: `data/customers.csv`,
`data/employees.csv`, `data/products.csv`, `data/orders.csv`.

---

## Part 6 — DQL: first queries (~10 min)

Run each of these yourself. Before you run one, predict what it will
return — then check.

```sql
SELECT * FROM customers;                                    -- everything

SELECT firstName, lastName, birthDate FROM customers;       -- choose columns

SELECT * FROM customers WHERE birthDate < '1990-01-01';     -- choose rows

SELECT * FROM products  WHERE price > 100;

SELECT * FROM products  ORDER BY price DESC;

SELECT * FROM orders    ORDER BY orderDate DESC LIMIT 5;

SELECT * FROM customers WHERE moneySpent > 3000
                          AND birthDate < '1995-01-01';

SELECT DISTINCT category FROM products;
```

The mental model to keep:

- `FROM` — which table
- `WHERE` — which rows
- `SELECT` — which columns
- `ORDER BY` — in what order
- `LIMIT` — how many

Once you're comfortable, try changing the numbers and dates above and
predicting the new result before you run it.

---

## Part 7 — The payoff: put it back together (~5 min)

By this point you might feel uneasy — you broke one perfectly good table
into four pieces. This is where you put it back together, and see that
nothing was lost.

```sql
SELECT o.orderID,
       o.orderDate,
       c.firstName || ' ' || c.lastName AS customer,
       p.category,
       p.price,
       o.orderTotal,
       e.firstName || ' ' || e.lastName AS soldBy
FROM orders o
JOIN customers c ON c.customerID = o.customerID
JOIN products  p ON p.productID  = o.productID
JOIN employees e ON e.employeeID = o.employeeID
ORDER BY o.orderDate, o.orderID;
```

**42 rows — exactly the file you started with.** Nothing was lost.

But now there is one place to fix a birth date, one place to change a
price, and the database itself refuses to accept nonsense (Part 8 shows
that directly).

**Optional closer on `moneySpent`.** Run this to check a stored number
against reality:

```sql
SELECT c.firstName, c.lastName,
       c.moneySpent      AS stored,
       SUM(o.orderTotal) AS computed
FROM customers c
JOIN orders o ON o.customerID = c.customerID
GROUP BY c.customerID, c.firstName, c.lastName, c.moneySpent
ORDER BY c.customerID;
```

They match today. Ask yourself: *what happens the first time someone
inserts an order and forgets to update `moneySpent`?* That question is
most of why the rest of this course exists.

---

## Part 8 — Watch the database say no (~5 min)

Run each of these yourself, one at a time, and actually read the error
message rather than skimming past it.

```sql
-- 1. an order for a customer who does not exist
INSERT INTO orders VALUES (9999, 999, 1, 1, 100.00, '2024-08-15');
-- ERROR: violates foreign key constraint

-- 2. a negative price
INSERT INTO products (category, price) VALUES ('Broken', -50);
-- ERROR: violates check constraint "products_price_check"

-- 3. a duplicate category
INSERT INTO products (category, price) VALUES ('Laptops', 999.00);
-- ERROR: duplicate key value violates unique constraint
```

> **The point:** a spreadsheet would have accepted all three of these,
> silently. That is the difference between a file and a database.

---

## Summary

- SQL is **declarative** — you say what you want, not how to get it.
- **DDL** defines, **DML** changes, **DQL** reads (DCL and TCL come later).
- Redundancy in a flat file causes **update, insertion and deletion anomalies**.
- Fix it by giving each real-world thing its own table, connected by keys.
- A **composite natural key** works but is fragile; that's why we invent **surrogate ids**.
- **Primary key** identifies · **foreign key** connects · **constraints** enforce.
- Splitting is **lossless** — a `JOIN` rebuilds the original view whenever you need it.

**Next lecture:** here you split the file by intuition. Next time, the
actual rules — normal forms — and when it's right to break them.
`moneySpent` will be waiting for us.

---

## Files

| File | What it is |
|---|---|
| `data/sales_flat.csv` | The wide file — 42 rows × 13 columns. Load this first |
| `data/customers.csv` | Expected result — 8 rows. Compare after Part 5 |
| `data/employees.csv` | Expected result — 4 rows. Compare after Part 5 |
| `data/products.csv` | Expected result — 6 rows. Compare after Part 5 |
| `data/orders.csv` | Expected result — 42 rows. Compare after Part 5 |
| `lecture-02-demo.sql` | Every statement above, runnable in order — see "Before you start" for the one path quirk |
