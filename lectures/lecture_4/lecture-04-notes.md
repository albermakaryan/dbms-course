# Lecture 4 — Putting the Tables Back Together: Class Notes

*Scope: data models, dimensional modeling, star vs. snowflake, and the complete JOIN picture. Grounded throughout in `lecture-04-demo.sql` and your real dataset (30 customers / 8 employees / 37 products / 600 orders holding 965 order lines; the flat `sales` file has one row per line).*

---

## Part 1 — Three levels of a data model

Every table you design goes through three translations, whether you name them or not:

1. **Conceptual** — entities and relationships, no tables yet. "A customer places orders. An order holds one or more products. An employee may serve an order (or nobody does, if it's online)." This is the ER-diagram level from Lecture 2.
2. **Logical** — the same idea as tables, columns, keys, constraints — but still DBMS-agnostic. "`orders.customerID` is a required foreign key; `orders.employeeID` is optional."
3. **Physical** — how one specific engine actually stores it. `\d orders` in Postgres shows you this level directly: exact types (`DECIMAL(10,2)`), exact constraints, exact defaults.

**Why this matters to students:** mistakes at the conceptual level are cheap — you erase a box and redraw an arrow. Mistakes at the physical level are expensive — a `VARCHAR(50)` that turns out too short, or a `SERIAL` you should have made `BIGINT`, means an `ALTER TABLE` on live data (Lecture 2, Part 9) or worse. The further right you move, the more a change costs.

---

## Part 2 — Dimensional modeling (facts, dimensions, grain)

This is a second, purpose-built schema you build *alongside* your normal tables, when the question shifts from "record what happened" to "summarize everything that's happened so far."

- **Fact table** = an event, with numbers attached. One row per thing that occurred. In the demo: `fact_sales`, one row per order line (one product in one order), holding `quantity`, `revenue`, `cost`.
- **Dimension table** = the context around the event — who, what, where, when. `dim_date`, `dim_customer`, `dim_product`, `dim_employee`.
- **Grain** = the one-sentence definition of what a single fact row *is*, decided before you build anything else. Here: "one row = one order line." Everything else follows from that sentence — get the grain wrong (e.g., one row per order, so you can no longer say which product earned the money, or an order-level total copied onto each of its lines) and every aggregate built on top silently means something different than you think.

**Two build tricks worth remembering:**

- `dim_date` is generated once (`generate_series` over the 366 days of 2024, a leap year) with quarter/month/day-name already computed as columns, so no query ever has to compute "what quarter is this date" on the fly. Calendars are cheap to precompute and expensive to keep recomputing.
- **The "unknown member" trick.** Online orders have no employee (`employeeID IS NULL`). Instead of carrying that NULL into `fact_sales.employeeKey`, the demo inserts one extra row into `dim_employee`: `(0, '(online)', 'Online', '(none)')`, and every fact row uses `coalesce(o.employeeID, 0)`. Now *every* fact row has a valid, non-null employee key — including online ones — and every join to `dim_employee` is an ordinary join, never a "what if it's NULL" special case. This is the single cleanest way to make "missing" a *value* instead of an *absence*, and it's why joins in Part 6 of the demo never need `LEFT JOIN` against `dim_employee` — they can all be plain inner joins.

---

## Part 3 — Star vs. snowflake schema

- **Star**: one fact table, dimensions attached directly, each dimension flat (not split further). This is what `fact_sales` + `dim_date`/`dim_customer`/`dim_product`/`dim_employee` is.
- **Snowflake**: same idea, but a dimension gets normalized into sub-tables (e.g., `dim_product` split into `dim_product` + `dim_category` + `dim_brand`, each joined in turn).

**Default answer: star.** Kimball's own guidance is to avoid snowflaking unless you have a specific, concrete reason (a genuinely huge dimension where the storage saved is worth it). Snowflaking buys you less redundancy and costs you more joins and more tables for an analyst to navigate — a bad trade most of the time.

One naming gotcha to mention out loud in class: "Snowflake" is also a warehouse product name. The schema shape and the product are unrelated; don't let students conflate them.

---

## Part 4 — JOINs: building the intuition from the ground up

This is the core of the lecture. The goal isn't memorizing six join keywords — it's building one mental model that all six fall out of.

### 4.0 The one idea everything else is built on

**A join is: pair up every row of A with every row of B, then keep the pairs you want.**

That's genuinely it. Every join type is a variation on "which pairs do we keep" and "what do we do with the ones we don't." If students internalize only one sentence from this lecture, it should be this one — because it means CROSS JOIN isn't a weird separate thing, it's the *whole Cartesian product before you've thrown anything away yet*.

### 4.1 CROSS JOIN — start here, not last

`A CROSS JOIN B` = every row of A paired with every row of B. No condition, no filtering.

**Demo number:** `orders CROSS JOIN customers` → **18,000** rows (600 × 30). No order actually belongs to all 30 customers — this is *every possible pairing*, most of them nonsensical. That's the point: it's the raw material every other join type is carved out of.

Postgres defines `CROSS JOIN` as literally identical to `INNER JOIN ... ON TRUE` — "join everything to everything, no condition to fail." Worth showing students directly: it is not a special case, it's the *default* case with the condition set to always-true.

**Teaching sequence that works well:**
1. Show the CROSS JOIN — all 18,000 pairs.
2. Add a `WHERE` filtering down to the 3 orders × 3 customers you actually care about → 9 rows, then narrow further to the 3 correct pairs.
3. *Now* show the same result written as `JOIN ... ON` — same 3 rows, cleaner syntax.

This order matters pedagogically: students who see `JOIN ... ON` first often think of it as a black box operation ("the magic combine-tables command"). Students who see it *derived* from CROSS JOIN + WHERE understand that a join is just filtered pairing — nothing more mysterious than that.

### 4.2 INNER JOIN — keeps only the pairs that match

`A INNER JOIN B ON condition` = from all possible pairs, keep only the ones where `condition` is true. Anything on either side with no match at all simply disappears from the result — no error, no placeholder, gone.

**Demo number:** the inner join of `orders + customers + employees` returns **419** rows, not 600. The other **181** are exactly the online orders — they have `employeeID IS NULL`, so they can't satisfy `orders.employeeID = employees.employeeID` for *any* employee, and an inner join drops anything that can't find a partner.

**The one sentence to drill until it's automatic:**

> An inner join doesn't complain when rows don't match — it just quietly leaves them out.

That's not a bug, it's the definition — but it's *invisible* unless you go looking for it, which is exactly why the completed-revenue number computed off this join (**100,222.48**, against the real **157,078.41**) is wrong: it's a real sum, correctly computed, over a silently incomplete set of rows.

### 4.3 Aliasing — and the two errors that teach you why it exists

Once two tables in a join share a column name (`customerID` in both `orders` and `customers`), the engine needs to know which one you mean.

- Write `customerID` unqualified with both tables in scope → **ambiguous column reference** error.
- Fix: alias the tables (`FROM orders o JOIN customers c ...`) and qualify (`o.customerID`).
- Second trap: once you write `FROM orders o`, the name `orders` stops existing for the rest of that query — only `o` does. Write `orders.customerID` after aliasing and Postgres won't just error, it'll suggest the fix: *"Perhaps you meant to reference the table alias 'o'."* That's not a coincidence — it's telling you exactly what happened: the alias didn't add a nickname, it *replaced* the name.

### 4.4 USING and NATURAL JOIN — convenience with a hidden cost

`USING (customerID)` — shorthand for `ON o.customerID = c.customerID`, when the column name matches on both sides. Bonus: the column appears once in the output, not twice.

`NATURAL JOIN` — goes further and joins on *every* column name the two tables happen to share, with no condition written at all.

**Why this is dangerous, demonstrated, not just asserted:** `orders NATURAL JOIN sales` returns **168** rows — nowhere near the **965** an honest join on `orderID` gives (`sales` has one row per order line) — because `orders` and `sales` happen to share several column names beyond `orderID`, and NATURAL JOIN silently joined on *all* of them at once, which is a far stricter condition than intended.

**The takeaway to give students in one line:** *the join condition should always be visible in the code you're reading.* NATURAL JOIN hides it — and it changes automatically, without warning, the moment either table gains a new column with a matching name. Never use it in real code.

### 4.5 LEFT / RIGHT / FULL OUTER JOIN — keeping what doesn't match

Build this up as: "INNER JOIN, but we refuse to lose rows from one side (or both)."

- **LEFT JOIN**: keep every row of the left table no matter what; where there's no match on the right, fill the right side with NULLs instead of dropping the row.
- **RIGHT JOIN**: the mirror image.
- **FULL JOIN**: keep everything from both sides — LEFT and RIGHT combined.

**Demo number:** `orders LEFT JOIN employees` returns all **600** rows — the 181 online orders now survive, with `employeeID`/`branch`/etc. simply NULL. Group by `coalesce(e.branch, 'Online')` and the online orders' revenue now lands in a visible "Online" bucket instead of vanishing.

**Anti-join — the single most useful LEFT JOIN pattern:** "find things on the left with *no* match on the right at all" = `LEFT JOIN` + `WHERE right.key IS NULL`. If a real match existed, the right-hand columns wouldn't be NULL; if they *are* NULL, that row's left-hand entity had nothing to match.

**Demo numbers:** applied to customers → exactly **2** customers with zero orders (Levon Arakelyan, Astghik Danielyan) out of 30. Applied to products → exactly **1** product with zero orders (productID 35, "Ergonomic Chair Pro," Chairs, stockQuantity 6) out of 37.

Teach this as a named pattern, not a clever trick — "which X have no Y" comes up constantly (customers with no orders, products never sold, employees with no reports) and this is the standard idiom for it.

### 4.6 count(*) vs. count(column) — the fastest sanity check you have

`count(*)` counts rows that exist. `count(column)` counts rows where `column` is not NULL. After a LEFT JOIN these two numbers *should* diverge exactly at the unmatched rows — if they don't diverge the way you expect, something about your join is wrong. This pair is worth teaching as a reflex: run both, every time, right after writing an outer join, before trusting anything downstream.

### 4.7 The WHERE-vs-ON trap — the most important trap in the lecture

With inner joins only, it genuinely doesn't matter whether a condition lives in `ON` or `WHERE` — same result either way.

**With outer joins it matters completely**, because of *when* each clause runs:
- `ON` conditions are applied *while deciding what to match* — before the outer join decides which rows get NULL-padded.
- `WHERE` conditions are applied *after* the whole join (including the NULL-padding) is already done — so a `WHERE` condition can filter out the very NULL-padded placeholder rows the LEFT JOIN just created, silently turning your LEFT JOIN back into behaving like an INNER JOIN.

**Demo numbers, side by side:**
- `products LEFT JOIN order_items ... LEFT JOIN orders ... WHERE status = 'completed'` grouped by category → **12** rows. The Chairs category (zero orders at all) gets its NULL-padded placeholder filtered out by the WHERE clause along with genuinely non-completed rows — it vanishes entirely.
- Move the condition into `ON` — but in a chain of joins, *which* `ON` matters. Put it on the `orders` join (`LEFT JOIN orders o ON o.orderID = i.orderID AND o.status = 'completed'`) and Chairs comes back (**13** rows), but revenue is wrong: lines of returned orders still exist, they just get NULL order columns, and their `lineTotal` is still summed (Laptops 58,028.50 instead of 53,412.00).
- The fix decides what counts as a match *before* the LEFT JOIN: `products p LEFT JOIN (order_items i JOIN orders o ON o.orderID = i.orderID AND o.status = 'completed') ON i.productID = p.productID` → **13** rows, the correct revenue, and Chairs at 0.

**How to explain this so it sticks:** "`ON` decides who gets invited to the party. `WHERE` decides who's allowed to stay after the party already happened — including the guests the LEFT JOIN invited for free (the NULL-padded ones)." A `WHERE` clause that mentions the right-hand table's columns should always make you stop and ask: am I filtering matches, or am I accidentally un-inviting the rows my LEFT JOIN was supposed to protect?

### 4.8 Self-joins — joining a table to itself

Same table, two roles. Always needs aliasing — there's no other way to refer to "this row" and "that other row from the same table" unambiguously. (An unaliased self-join is a demonstrated error for exactly this reason.)

**Demo pattern:** `employees e LEFT JOIN employees m ON e.managerID = m.employeeID` — `e` plays "the employee," `m` plays "their manager," same underlying table. LEFT JOIN matters here too: employees with `managerID IS NULL` (the top of the hierarchy) still need to appear.

**Demo numbers:** direct-manager lookup → 8 rows. A second hop (manager's manager) → 5 rows. Self-join + GROUP BY to count direct reports per manager → 3 rows.

Any hierarchy stored as "this table points to itself" (org charts, category trees, comment replies) uses this exact shape.

### 4.9 Joining on the wrong thing — names are not identifiers

The demo deliberately joins customers to employees by matching first/last name — and finds **2** accidental collisions (two different people who happen to share a name, distinguishable only by birthdate/branch). A separate name-based join of `sales` to `customers` returns **1,036** rows instead of the expected 965 — extra matches from ambiguous name collisions.

**One-line lesson:** only join on something that is *guaranteed* unique — a real key. Anything that merely "usually" identifies a row correctly will eventually produce a false match once your data is large enough, and the join won't warn you when it happens.

### 4.10 The fan-out trap — the most damaging trap, because the number looks completely normal

This is the one worth spending the most class time on, because unlike the previous traps it doesn't require an outer join or a weird join type — a completely ordinary inner join breaks it.

**The setup:** `customers.moneySpent` is one number per customer (customer-grain). `orders` has many rows per customer (order-grain). Join them, and each customer's `moneySpent` value gets *copied onto every one of their order rows* — not divided, not split, copied whole.

**Demo number:** `SUM(customers.moneySpent)` computed after joining to `orders` returns **4,386,925.27** — wildly higher than the real total of **157,078.41**. Confirmed with `count(*) = 600` (order rows) vs. `count(DISTINCT customerID) = 28` (real customers who have orders): every customer's `moneySpent` got summed once *per order they placed*, not once total.

**The rule to give students, framed as a question they ask themselves every time they aggregate after a join:**

> "Is the thing I'm summing at the same grain as the rows I'm joining through? If not, am I about to sum the same value multiple times?"

**The fix, in general:** either aggregate the fine-grain table first and join the *result* back (one row per customer), or don't join at all if you already have the summary value you need.

### 4.11 ON with non-equality conditions

`ON` isn't limited to `=`. The demo's revenue-band example uses a `VALUES(...)` inline table joined via `>=` / `<` range conditions — this is how bucketing/binning is done natively in SQL (assign each order's `orderTotal` to the band where `band.lower <= orderTotal < band.upper`) without writing a `CASE` per row.

### 4.12 "A document is a join you saved"

The `jsonb_agg` demo — building one JSON document per customer containing all their orders — is worth framing conceptually, not just syntactically: a denormalized JSON document *is* the materialized result of a one-to-many join. The relational model keeps pieces separate and joins on demand; the document model pre-joins once and stores the combined result. Same information, different point in the pipeline where the join cost gets paid.

### 4.13 Proving a join is lossless

The demo's closing check — rejoin all the normalized tables at line grain, `EXCEPT SELECT * FROM sales` (the original flat data), get **0 rows** back — is a real, checkable proof: if the rebuilt data and the original have zero rows of difference in either direction, the split into separate tables lost nothing. Worth presenting as the concrete, runnable version of "lossless-join decomposition," rather than an abstract theory term.

### 4.14 GROUP BY column order — clearing up a common misconception

Grouping is defined by the *combination* of values in the listed columns — the order you list them in doesn't change the result. `GROUP BY a, b` and `GROUP BY b, a` group identically. If a query's total looks wrong, column order in `GROUP BY` is not the place to look — check instead for a fan-out (4.10) or whether a CTE's internal ordering is being relied on somewhere it isn't guaranteed to hold.

---

## Part 5 — Why all of this matters (the one idea to leave the room with)

Look back at three of these: NATURAL JOIN (965 → 168), WHERE-vs-ON (13 → 12), and the fan-out sum (157,078.41 → 4,386,925.27). None of them threw an error. All three produced a result that looked like a completely normal table.

**That's the whole point of this lecture:** SQL correctness bugs are almost always silent. Nothing turns red. The query runs, returns rows, and is simply wrong — and an AI assistant will write a plausible-looking, syntactically perfect JOIN whether the logic is right or not. The only real defense is knowing the handful of independent checks that catch a wrong-but-plausible answer: compare row counts before and after a join, compare `count(*)` to `count(column)`, check `DISTINCT` counts against what you expect, or — as in 4.13 — run a symmetric-difference check against a known-correct source. That's not a side skill. For anyone using AI to write their SQL, it's the actual skill.