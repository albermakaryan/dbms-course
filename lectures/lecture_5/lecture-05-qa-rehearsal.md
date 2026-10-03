# Lecture 5 — Q&A Rehearsal: Subqueries → CTEs

*Questions students are likely to ask, easiest to hardest, with a short answer for each. Numbers are from `lecture-05-demo.sql` on the course data.*

---

**1. Why does an order have two tables now?**
Because a real order can hold several products. `orders` is the header — one row per order (who, when, status, `orderTotal`). `order_items` is the lines — one row per product in the order. 235 of the 600 orders have more than one line; 965 lines in all.

**2. Why did completed revenue change from 145,935.12 to 157,078.41?**
The orders gained extra products, so their totals grew. The orders themselves — customers, dates, statuses — are the same 600 as in Lecture 4.

**3. What is a subquery?**
A `SELECT` inside another statement, in parentheses. The outer query uses its result as a value, a list, a row or a table, depending on where you put it.

**4. What are the four shapes?**
Scalar (one value), column (one column, many rows — used with `IN`/`ANY`/`ALL`), row (one row, several columns — rare), and table (a derived table in `FROM`).

**5. What happens if a scalar subquery returns two rows?**
An error: `more than one row returned by a subquery used as an expression`. Four phones, one "phone price" — the database refuses to guess.

**6. And if it returns no rows?**
No error. It becomes NULL, every comparison with it is unknown, and the outer query returns 0 rows. Too many rows is loud; zero rows is silent.

**7. Is `= ANY (...)` different from `IN (...)`?**
No — same thing. `> ANY` means "greater than at least one value" (13 products are dearer than the cheapest phone); `> ALL` means "greater than every value" (3 are dearer than every phone).

**8. Why use `IN` instead of a JOIN?**
`IN` only asks "is this row on the list?", so each outer row comes out at most once. December: `IN` gives 26 customers; the join gives 86 rows, one per order. That's why `IN` fixed Lecture 4's fan-out drill.

**9. Why does `avg(count(*))` fail?**
Aggregates can't be nested. Count per customer in a derived table, then average the result: 21.43 orders per customer.

**10. Why 21.43 and not 20?**
The derived table is built from `orders`, so it only has the 28 customers who ordered. 600 / 28 = 21.43. Over all 30 customers, 600 / 30 = 20.00. Decide which one the question means.

**11. Do I have to alias a subquery in FROM?**
Write one anyway. PostgreSQL 16+ lets you leave it out; the SQL standard and older PostgreSQL versions don't.

**12. When do anti-join, `NOT IN` and `NOT EXISTS` give the same answer?**
When the subquery's column can't be NULL. "Products never ordered": all three give Ergonomic Chair Pro, because `order_items.productID` is `NOT NULL`.

**13. Why did `NOT IN` return 0 rows for "never had a cancelled order"?**
5 of the 27 cancelled orders are online, with `employeeID` NULL. `x NOT IN (…, NULL)` is never true — it's false or unknown — so no row passes. The right answer is Hayk.

**14. How do I spot that before it bites?**
`count(*)` vs. `count(column)` on the subquery: 27 vs. 22 means there are NULLs in the list. Then use `NOT EXISTS`, or filter `IS NOT NULL` inside the subquery.

**15. Is plain `IN` also broken by NULLs?**
No. `x IN (…, NULL)` is still true when `x` is in the list. The trap is the `NOT` form.

**16. I joined `order_items` to count units, and revenue went up. Why?**
Every header column is copied onto every line of its order, `orderTotal` included. An order with three lines adds its total three times: 247,923.72 instead of 157,078.41. `count(*)` (844 rows) vs. `count(DISTINCT orderID)` (529 orders) shows it.

**17. How do I fix it?**
Sum what lives on the line — `sum(lineTotal)` — or aggregate the lines per order in a subquery first, so there's one row per order before the join. Both give 157,078.41.

**18. "Revenue from orders that contain an accessory" — JOIN or EXISTS?**
EXISTS. The JOIN keeps one row per accessory *line*, so an order with two accessories is counted twice (29,810.88). `EXISTS` keeps each order once (25,955.91 over 142 orders).

**19. What makes a subquery correlated?**
It mentions a column of the outer query (`WHERE p2.category = p.category`), so its answer changes for each outer row. Test: select only the subquery and run it — a correlated one fails with `missing FROM-clause entry`.

**20. Isn't a correlated subquery slow, running once per row?**
Sometimes. `EXPLAIN` on the category-average query shows a `SubPlan` that really is evaluated per product. But `EXPLAIN` on the `NOT EXISTS` customer query shows a `Hash Anti Join` — PostgreSQL rewrote it into a join. On tables this size it doesn't matter. Write the clearest correct version first, and measure before worrying.

**21. When would I use a correlated subquery instead of a self-join?**
They solve the same shape: compare a row to a related row. "Hired before their manager" gives Marine either way. A correlated subquery in `SELECT` never drops outer rows (it returns NULL or 0), which is useful when you want everyone listed — all 8 employees with their report counts, not just the 3 managers.

**22. What is LATERAL for?**
A subquery in `FROM` that can see the row before it — a correlated subquery that returns a whole table. Use it when you need several columns or several rows per outer row: each customer's latest order with all its columns, or each customer's 3 biggest orders. A `SELECT` subquery errors on two columns, and a plain `FROM` subquery can't reference `c` at all.

**23. Why `ON true` after a LATERAL subquery?**
The matching already happened inside it (`WHERE o.customerID = c.customerID`). There's nothing left for `ON` to compare, so it just says "keep every pair".

**24. My LATERAL top-3 query lost two customers. Why?**
`JOIN LATERAL` is an inner join: Levon and Astghik have no orders, the subquery returns no rows for them, and they silently drop out (84 rows). `LEFT JOIN LATERAL ... ON true` keeps them with NULLs (86 rows). Predicting the count first — 28 customers × 3 = 84 — tells you which one you got.

**25. What does `EXISTS` actually check?**
Only whether the subquery returns at least one row. The selected values don't matter — `SELECT 1`, `SELECT *`, even `SELECT NULL` behave the same.

**26. Why is `NOT EXISTS` safe from the NULL trap?**
`EXISTS` only returns true or false, never unknown. A NULL in the subquery's data just fails to match; it can't poison the whole result.

**27. My `EXISTS` filter returned every customer. What happened?**
The subquery isn't correlated — you left out the condition that links it to the outer row, or wrote it unqualified (`customerID = customerID` compares `orders.customerID` with itself). It then asks the same question for every row: 30 customers "gave 1 star" instead of 4.

**28. How do I catch that?**
All-or-nothing results (every row, or none) are the tell. And check against known facts: a list that includes Levon and Astghik, who never ordered, can't be a list of people who rated an order.

**29. I moved a column to another table and my old `NOT IN` query still runs. Should I worry?**
Yes. `productID NOT IN (SELECT productID FROM orders)` still runs after `productID` moved to `order_items` — inside the subquery the name falls back to the outer `products.productID`, and the query reports 0 never-ordered products. Write `o.productID` and the same mistake becomes an error.

**30. What is a CTE?**
`WITH name AS (...)`: a named result that exists only for one query. A table subquery moved to the top, with a name — it reads top to bottom instead of inside out.

**31. Does a CTE change the result compared to the subquery version?**
No. Part 5.1 returns the same 4 customers as the derived table in Part 1.4. It changes readability, not meaning.

**32. Can one CTE use another?**
Yes — separate them with commas; each can read the ones above it. `overall` reads `per_customer` to get the 21.43 average.

**33. Doesn't a CTE protect me from fan-out, since I aggregated first?**
No. Aggregating first is the fix only if you don't join the finer table back in. Joining a customer-grain CTE to `orders` copies each customer's total onto every order: the spend adds up to 3,889,069.12 instead of 157,078.41, and the averages look believable but rank the wrong city first.

**34. How do I fix the CTE fan-out?**
Keep everything at one grain: compute all customer-level numbers (spend and order count) inside the CTE, and don't join back to `orders`. Then check that the totals still add up to 157,078.41 and 529 orders.

**35. I put `ORDER BY` in my CTE. Why isn't the output sorted?**
Only the outermost `ORDER BY` controls the order you see. The join re-reads the CTE in its own order; here it returned customers 1–5 by ID as the "top 5". Put `ORDER BY` on the final query.

**36. But it was sorted when I tried it yesterday.**
It can happen to survive — that depends on the plan the database picks, which depends on the data and the statistics. "Worked yesterday" is exactly why it's a trap. The docs say an unordered result's order "must not be relied on."

**37. What does `WITH RECURSIVE` add?**
A CTE that can refer to its own previous output. It starts with a base query, then repeats a step (`UNION ALL` + a join back to itself) until a step returns no new rows.

**38. Why not just keep adding self-joins?**
Each self-join is one more hop, and the depth is fixed in the query. With a hypothetical trainee under Nare, the two-hop join stops at Hayk and silently misses Vahe; the recursive CTE finds all 4 levels, however deep the chart is.

**39. Can a recursive CTE run forever?**
Yes — if the data has a cycle (A reports to B, B reports to A), the step never runs out of rows. On a proper tree it stops when it reaches someone with no manager.

**40. Which of today's mistakes would the database have warned me about?**
None of them. `NOT IN` returned an empty list, the cart fan-out returned a revenue figure, the uncorrelated `EXISTS` returned everybody, the CTE fan-out returned believable averages, and the `ORDER BY` trap returned five real customers. No errors. Each was caught only by checking against something already known: a revenue of 157,078.41, a count of 600 or 529, two customers with zero orders, a column that should be in order. That's the course's thesis again — SQL bugs are silent, and knowing which number to check is the skill, whoever (or whatever) wrote the query.
