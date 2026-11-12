# Lecture 6 — Q&A Rehearsal: Window Functions

*Questions students are likely to ask, easiest to hardest, with a short answer for each. Numbers are from `lecture-06-demo.sql` on the course data.*

---

**1. What is a window function?**
A function that computes over a set of rows related to the current row, such as the same customer or all rows so far, without collapsing them. Every input row stays in the result.

**2. How is that different from GROUP BY?**
`GROUP BY` returns one row per group, and the detail rows are gone. A window puts the group's number next to each detail row: each of Anna's completed orders next to her 6,651.60 total.

**3. How did people do this before windows?**
Join an aggregated derived table back to the detail rows, or use a correlated subquery in `SELECT`. Both work, but the first is a join you have to check for fan-out, and the second repeats every filter twice.

**4. How do I know a window didn't add or remove rows?**
Count. A query with only window functions returns exactly as many rows as its input: 600 orders in, 600 rows out.

**5. Can a window cause a fan-out like Lecture 4's moneySpent join?**
No. A window never adds rows, so there's nothing to multiply: 30 customers in, 30 out, total 157,078.41. The join made 600 rows and 4,386,925.27.

**6. What does `OVER ()` with nothing inside mean?**
The whole result is one window. `sum(orderTotal) OVER ()` is the total of every row, on every row, which is handy for percent-of-total.

**7. What does `PARTITION BY` do?**
It splits the rows into groups, and the function restarts for each group. Unlike `GROUP BY`, the rows stay.

**8. What does `ORDER BY` inside `OVER` do?**
It orders the rows *inside* each window: for ranking, for `lag`/`lead`, and for running totals. It does not decide the order of the output.

**9. My window had `ORDER BY orderDate`, so why isn't my output in date order?**
Only the query's own `ORDER BY` controls output order. With two windows, the rows came out in whatever order the last window's sort left them: the five *biggest* orders instead of the first five of the year. Add `ORDER BY` at the end.

**10. Why did my "share of revenue" add up to 100% for one customer?**
`WHERE` runs before windows. Filtering to `customerID = 5` first left only Lusine's orders in the window, so you got shares of *her* revenue (55.84%…). Compute the window in a subquery, then filter outside: 1.02%….

**11. Can I put a window function in WHERE?**
No. It's a loud error: `window functions are not allowed in WHERE` (or `column "rn" does not exist` if you use the alias). Windows run after `WHERE`. Wrap the query in a CTE or subquery and filter there.

**12. What does `sum(sum(orderTotal)) OVER ()` mean?**
The inner `sum` is the `GROUP BY` aggregate, one per customer. The outer `sum ... OVER ()` adds those group totals across the whole result. It's legal and confusing; aggregating in a CTE first reads better.

**13. What is the `WINDOW` clause for?**
Naming a window you use several times: `OVER w ... WINDOW w AS (PARTITION BY customerID)`. Write it once, and you can't write it differently by accident.

**14. row_number, rank, dense_rank: what's the difference?**
On ties: `row_number` gives different numbers (8, 9), `rank` gives the same number and then skips (8, 8, 10), `dense_rank` gives the same number without skipping (8, 8, 9). Narek and Lilit, 29 orders each, show all three.

**15. Which of my two tied customers gets row_number 8?**
Whichever the sort met first, which depends on the plan. Two reasonable queries for "top 8 customers" gave Lilit in one and Narek in the other. Add a unique tie-breaker (`ORDER BY count DESC, customerID`) or use `rank()` and see the tie (9 customers).

**16. Is a tie-breaker by ID fair?**
It's deterministic, not fair. "Lower ID wins" is now a business rule, so say it out loud, or use a tie-breaker with meaning, such as revenue.

**17. For "top 2 per category", rank or dense_rank?**
`rank() <= 2` returns more than 2 only when there's a tie at the cut (28 products). `dense_rank() <= 2` counts distinct values, so a tie at the top pulls in an extra product (29). `row_number() <= 2` returns exactly 25, by dropping tied products arbitrarily. Usually: `row_number` with a complete tie-breaker, or `rank` if ties should share the place.

**18. What does ntile(4) do with ties?**
It deals rows into 4 nearly equal buckets in order, and splits a tie wherever the boundary falls: Narek and Lilit, both with 29 orders, land in quartiles 1 and 2.

**19. Three ways to get each customer's latest order?**
`row_number()` in a CTE with `rn = 1`, `LEFT JOIN LATERAL (... ORDER BY ... LIMIT 1)`, and `DISTINCT ON (customerID) ... ORDER BY customerID, ...`. With a complete order, all three give the same 28 orders, and `EXCEPT` both ways gives 0 rows.

**20. Why did the LATERAL version lose two customers?**
`JOIN LATERAL` is an inner join. Levon and Astghik have no orders, so the subquery returns nothing for them and they drop out: 30 in, 28 out. `LEFT JOIN LATERAL ... ON true` keeps them.

**21. Can I use DISTINCT ON everywhere?**
No. It's PostgreSQL-only, and it can keep only one row per group. Its `ORDER BY` must start with the `DISTINCT ON` columns (otherwise an error), and it needs the rest of the order spelled out (otherwise you get an arbitrary row: customer 1 got a February order).

**22. My three methods agree. Does that prove the answer?**
Only if the question has exactly one answer. Ordered only by `orderDate`, all three agreed that Armen's latest order is 1595, and all three were wrong (1596 was later that day). Make every `ORDER BY` complete, then compare.

**23. Why is lag's first row NULL?**
There's no previous row. That NULL is honest. Replacing it with `lag(x, 1, 0)` invents a previous order of 0: the average order-to-order change becomes 17.23 instead of 1.42.

**24. When is a lag default OK?**
When it's true. A previous *count* of 0 for a first order is true; a previous *amount* of 0 is not.

**25. Is lag "the previous month"?**
No, it's the previous *row*. Nare sold nothing in February, so her March was compared with January. In the full report, 7 rows compare with the wrong month and 8 months are missing. Build every employee × every month first (from `dim_date`), `LEFT JOIN` the sales, `coalesce` to 0, then `lag`.

**26. What is a window frame?**
The part of the partition the function sees for the current row. `sum`, `avg`, `first_value`, `last_value` and `nth_value` use it; `row_number`, `rank` and `lag` don't.

**27. What is the default frame?**
Without `ORDER BY` in `OVER`: the whole partition. With `ORDER BY`: `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`, everything up to the current row *and its peers*.

**28. Why do two orders show the same running total?**
They're on the same date, and the default `RANGE` frame includes all peers. Orders 1002 and 1003 both show 1,207.65. Write `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` and add a unique tie-breaker: 460.65, then 1,207.65.

**29. How do I check a running total?**
It must end at the plain total (157,078.41 overall, and each customer's sum per partition), and with positive amounts it must change on every row. The first check passes even with the `RANGE` bug; the second finds 279 stalled rows.

**30. Why does last_value give me the current row's value?**
The default frame ends at the current row, so the frame's last row *is* the current row: 529 out of 529 rows. Use `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING`, or `first_value` with the order reversed.

**31. What's wrong with my 3-month moving average in January?**
January has no two months before it, so the "3-month" average is January alone (9,902.54), and February's is two months. Count the rows in the same frame and blank out averages built on fewer than 3.

**32. ROWS 6 PRECEDING, or RANGE INTERVAL '6 days' PRECEDING?**
`ROWS` counts rows; `RANGE` with an offset counts days. Orders happened on 250 of 366 days, so the two disagree on 246 of the 250 days. For "the last 7 days", use `RANGE` (PostgreSQL 11+).

**33. What is GROUPS?**
A frame measured in groups of tied rows: `GROUPS 1 PRECEDING` is "this date and the previous date that had orders", per order. PostgreSQL 11+.

**34. Why is my top salesperson nameless?**
`PARTITION BY` / `GROUP BY employeeID` puts all 181 online orders into one NULL group, ranked like a person. Exclude NULLs if the question is about people, or label them `(online)` if it's about channels. Decide which, and make it visible.

**35. Why is every customer's "best-rated order" unrated?**
`ORDER BY rating DESC` puts NULLs first in PostgreSQL. Write `DESC NULLS LAST`.

**36. Do window aggregates skip NULLs?**
Yes, like plain aggregates. Lusine's average rating, 3.67, rests on 3 ratings, not her 4 orders. Put `count(rating)` next to `count(*)`.

**37. I put a window on a joined query and the totals are too big. Why?**
The join had already multiplied the rows; the window summed what it was given. Lusine's revenue came out 5,011.30 instead of 2,861.90 over the order lines. Windows don't repair fan-out. Sum the line column, or window before the join.

**38. Can I use FILTER with a window?**
With aggregate windows, yes: `count(*) FILTER (WHERE status = 'returned') OVER (PARTITION BY customerID)`. Not with `row_number`, `rank` or `lag`.

**39. Window, self-join or correlated subquery for "compare each row to its group"?**
All three give the same 172 orders above their customer's average (`EXCEPT` both ways: 0). The window is usually clearest: one filter, no join to check.

**40. Which of today's mistakes would the database have warned me about?**
One: a window function in `WHERE`. Everything else ran and returned a normal-looking table: output in the wrong order, shares of the wrong total, an arbitrary 8th customer, three methods agreeing on the wrong order, lag across missing months, running totals repeating on tied dates, `last_value` equal to the row itself, a nameless top salesperson, unrated "best" orders, and a fan-out inside a window. Each was caught only by a check: rows in = rows out, a running total that ends at 157,078.41 and moves on every row, two methods compared with `EXCEPT` after making every order complete, and known facts (529 completed orders, 28 customers with orders, 8 salespeople, 12 months). That's the course's thesis again: SQL bugs are silent, and knowing which number to check is the skill, whoever (or whatever) wrote the query.
