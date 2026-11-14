# Lecture 7 — Q&A Rehearsal: Performance (EXPLAIN, Indexing, Partitioning)

*Questions students are likely to ask, easiest to hardest, with a short answer for each. Numbers are from `lecture-07-demo.sql` on PostgreSQL 18; timings are medians of three runs from `build/measurements-pg18.md`, on one laptop.*

---

**1. Why don't we use the shop data from the last three lectures?**
We do, for every correctness check (157,078.41 is still the answer). But on 600 rows every plan finishes in hundredths of a millisecond, with or without an index, so there is nothing to measure. Speed needs a big table: `orders_big`, 5 million rows, the same columns.

**2. What's the difference between EXPLAIN and EXPLAIN ANALYZE?**
`EXPLAIN` shows the plan and the planner's estimates; nothing runs. `EXPLAIN ANALYZE` runs the statement and adds what really happened: actual rows, time per node, and (in PostgreSQL 18 automatically) buffers.

**3. Is "cost" in milliseconds?**
No. It's the planner's own unit, where reading one page in sequence costs 1.0. Use it to compare plans for the same query, never as a time.

**4. Can EXPLAIN ANALYZE break anything?**
Yes. It really runs the statement: `EXPLAIN ANALYZE DELETE` deleted 27 rows from our copy. Wrap anything that writes in `BEGIN; EXPLAIN ANALYZE ...; ROLLBACK;`.

**5. In which order do I read a plan?**
From the most indented node outwards. The innermost node runs first and feeds the one above it. A node's time includes its children's.

**6. What do "shared hit" and "read" mean?**
Pages (8 kB each) found in PostgreSQL's own cache vs pages it had to ask the operating system for. Page counts don't depend on your laptop's speed, so they're the fairest number to compare between two plans.

**7. I ran the same query three times and got three different times. Which is right?**
None alone. The first run often reads from disk ("read=150"), the next from cache ("hit=150"). Run three times, take the median, and compare plan shape and pages before milliseconds.

**8. Why does a full scan of orders_big always show "read", even the third time?**
A table bigger than a quarter of `shared_buffers` is scanned through a small 256 kB ring, so one big scan can't flush everything else out of the cache. The pages come from the operating system's cache instead.

**9. Where is a table, physically?**
In one ordinary file on the server's disk, `base/<database>/<file number>` under the data directory (`pg_relation_filepath` gives the path). `orders_big` is a 467 MB file: 59,739 pages of 8 kB. There are two small companion files, the free space map and the visibility map, and a table over 1 GB continues in a second file.

**10. What is `ctid`? Can I use it as a row ID?**
The row's address: (page, slot in the page). `WHERE ctid = '(58425,79)'` reads exactly one page. But it changes whenever the row is updated or the table is rewritten (`VACUUM FULL`), so never store it. Use the primary key.

**11. What does an index actually store?**
Sorted keys, each with the address (ctid) of its row. In the primary key, key 1 points to `(0,1)`. A lookup reads a few index pages to find the key, then one table page per row. That's why "rows on few pages" (one day's orders: 5,180 rows on 63 pages) is cheap and "rows on many pages" (Nane's 97 orders on 97 pages) isn't.

**12. Why did summing one column read the whole 467 MB table?**
PostgreSQL stores each row's columns together. The totals take 33 MB, but they are spread over all 59,739 pages, so every page is read. Columnar formats (Parquet, DuckDB, next lectures) store each column separately for exactly this kind of query.

**13. I deleted 90% of the rows. Why is the table the same size?**
`DELETE` only marks rows as deleted, and `UPDATE` writes a new version and marks the old one. `VACUUM` makes that space reusable inside the table (410,571 new rows went in without the file growing), but it doesn't give it back to the disk. `VACUUM FULL` does, by writing a new file, and locks the table while it runs. If you delete by date regularly, partition and `DROP` instead.

**14. Where do the planner's row estimates come from?**
From statistics that `ANALYZE` builds from a random sample: row counts, distinct values, most common values, histograms, and how well a column's order matches the disk order.

**15. What goes wrong if I load data and don't run ANALYZE?**
The planner plans for the old data. After loading January 2026, it expected 476 January rows instead of 200,000, chose a nested loop and a sort that spilled to disk, and ran about 1.7 times slower, with no error. `ANALYZE` fixed the plan.

**16. How do I find the bad step in a big plan?**
Find the node where estimated and actual rows differ by 10x or more, usually the lowest one. Every choice above it was made for the wrong number.

**17. Seq Scan, Index Scan, Bitmap Heap Scan, Index Only Scan: what are they?**
Read everything in order; use the index and fetch each row; use the index to collect pages, then read them in order; answer from the index alone.

**18. I have an index and the planner ignores it. Is that a bug?**
Usually not. For `status = 'completed'` (92% of rows) a Seq Scan is cheapest. Forced through the index, the query read more pages and wasn't faster (Bitmap) or was slower (Index Scan).

**19. 3% of the rows should be cheap through an index, right?**
Count pages, not rows. The 3.2% cancelled orders sit on 55,814 of the 59,739 pages, so the index saves almost nothing.

**20. What does "Heap Fetches" mean in an Index Only Scan?**
How many rows it still had to check in the table, because their page wasn't marked all-visible. On a freshly built table it was 5,180 of 5,180. After `VACUUM` it was 0.

**21. How much faster is an index really?**
For one customer (97 rows out of 5 million): about 100 pages instead of 59,739, and thousands of times faster on our laptop (0.04 ms vs 128 ms). For a query that needs most of the table: not faster at all.

**22. What does an index cost?**
Disk (the customerID index is 34 MB, the primary key 111 MB, beside a 467 MB table) and every write. Loading 1,000,000 rows took about 2.6 times as long with one index and about 8.5 times as long with five.

**23. Can an index replace ORDER BY?**
It can replace the Sort: "the ten biggest orders" reads a handful of index pages instead of all 5 million rows. The `ORDER BY` stays in the query; the index only makes it cheap.

**24. Does the column order in a composite index matter?**
Yes. `(customerID, orderDate)` answers `customerID = ?` and `customerID = ? AND orderDate >= ?` in 3 index pages. For `orderDate = ?` alone the plan still names the index, but it reads all 13,539 pages of it.

**25. What is skip scan?**
A PostgreSQL 18 feature that can jump through a composite index when the first column has few distinct values. With 48,000 customers it didn't apply here ("Index Searches: 1").

**26. When is a partial index used?**
Only when the query's `WHERE` provably contains the index's `WHERE`. `status = 'returned'` used our 1.7 MB index. `status IN ('returned', 'cancelled')` and `status <> 'completed' AND status <> 'cancelled'` did not, even though the second means the same thing.

**27. What is INCLUDE for?**
Carrying extra columns in the index so a query can be answered from the index alone: Nane's total went from about 100 pages to 5. The price: that index was 150 MB instead of 34 MB. PostgreSQL 11+.

**28. Why doesn't `WHERE lower(email) = ...` use the unique index on email?**
The index holds `email`, not `lower(email)`. Create an index on `lower(email)` and write the query with the same expression.

**29. Why can't I index `date_trunc('month', orderDate)`?**
On a `date` it goes through `timestamp with time zone`, which depends on the session's time zone, so it isn't IMMUTABLE. Cast to `timestamp` first, or better, write the filter as a range on `orderDate`.

**30. Why is `customerID = 4242.0` slow?**
The integer column gets converted to numeric for every row, so the index can't be searched. It reads all 5 million index entries: "Filter", not "Index Cond". `4242` or `'4242'` is fine.

**31. The plan says "Index Only Scan using ..." so the index is used, isn't it?**
Not necessarily as a lookup. Look under the node: `Index Cond` means the index was searched; `Filter` means every entry was checked. The pages tell you which.

**32. Why doesn't `LIKE 'nane%'` use my index?**
Under a language collation (ours is `en_US.utf8`) the default B-tree order doesn't work for prefixes. A `varchar_pattern_ops` index does. With the C collation the plain index already works.

**33. And `LIKE '%@yahoo.com'`?**
No B-tree can help. A leading wildcard has no place to start in a sorted list. Text search inside strings needs a different index type (pg_trgm).

**34. Why is my OR query slow when both columns look indexed?**
Each side needs its own index. With only `customerID` indexed, `customerID = 4242 OR deliveryDate = ...` read the whole table. Index `deliveryDate` too (BitmapOr), or split into two queries joined with `UNION`.

**35. UNION or UNION ALL for that rewrite?**
`UNION`. `UNION ALL` listed order 4890168 twice, because it matched both conditions: 1,750 rows instead of 1,749. `EXCEPT` didn't notice; counts and `EXCEPT ALL` did.

**36. Can an index change my results?**
No. Before and after, `EXCEPT` both ways gave 0 and 0 and the counts matched; completed revenue through a forced index was 157,078.41. If a "faster" version gives a different answer, it's a different query.

**37. NOT IN or NOT EXISTS: is one faster?**
`NOT EXISTS` and `LEFT JOIN ... IS NULL` became the same hash anti-join. `NOT IN` can't (because of NULLs). It was fine while its list fitted in memory, but on the 970,000-row churn list it needed longer for 100 customers than `NOT EXISTS` did for all 50,000. On PostgreSQL 14, with half the hash memory by default, even the cancelled-orders `NOT IN` fell off: 164 seconds. Choose `NOT EXISTS` for correctness first; this is a second reason.

**38. Which top-N-per-group method is fastest?**
It depends on the index. With an index on `(customerID, orderDate DESC, orderID DESC)`, `LATERAL ... LIMIT 1` was fastest by far (about 0.15 s). The same index made `DISTINCT ON` about 4.4 times slower than its own sort-based plan: it visited about 5 million pages in index order instead of 60,000 in table order. Without the index, never use `LATERAL` on 50,000 customers.

**39. Why did an index make a query slower?**
The planner assumed the table's pages would be cached (`effective_cache_size` says 4 GB) and preferred walking the index over sorting. PostgreSQL's own cache is 128 MB. The estimate was wrong, not the index. Measure, and read Buffers.

**40. Nested loop, hash join, merge join: which should I choose?**
You don't; the planner does, from row estimates and indexes. Nested loop for few outer rows with an index inside, hash join for many rows, merge join when both sides arrive sorted. Check its row estimates.

**41. What does partitioning buy?**
Pruning (a June 2025 query read only the 2025 partition, about 2.3 times faster than the plain table) and cheap deletion of old data (`DROP TABLE` on a partition instead of deleting 1.37 million rows). It is not a general speed-up.

**42. Why did my partitioned query scan every partition?**
Its filter wasn't on the partition key itself. `extract(year FROM orderDate) = 2025` read all three years. Write `orderDate >= '2025-01-01' AND orderDate < '2026-01-01'`.

**43. What happens to a row that fits no partition?**
Without a `DEFAULT` partition it's an error, which is good. With one, it's accepted silently, and later adding the right partition fails until you move the row out. Keep the default partition empty and check it.

**44. Why can't I make orderID the primary key of the partitioned table?**
Each partition can only check uniqueness inside itself, so a unique key must include the partition key. With `(orderID, orderDate)`, two orders numbered 5000001 got in. Generate IDs from one sequence and check `count(*) = count(DISTINCT orderID)`.

**45. Should I partition by day, then? More partitions, more pruning?**
In our test, 1,096 daily partitions made a one-day query faster, but a query without a date filter took about 60 times longer to plan and 1.7 times longer to run than with 3 yearly partitions. Match partitions to how you filter, and keep their number modest.

**46. How do I find indexes nobody uses?**
`pg_stat_user_indexes.idx_scan`. Our "monthly report" index stayed at 0 because the report filtered with `date_trunc(...)`. Fix the query or drop the index, but never the one behind a primary key or unique constraint.

**47. Which of today's problems would the database have warned me about?**
Four loud ones: the non-IMMUTABLE index expression, the row with no partition, the default partition blocking a new partition, and the primary key without the partition key. Everything else returned a correct-looking answer: a `DELETE` that left the file just as big, plans built on stale statistics, indexes that existed but weren't searched (function, cast, LIKE, OR, partial index), an index that made a query slower, a UNION ALL that counted an order twice, unpruned partitions, a silent default partition, duplicate "primary keys", and an index nobody used. Each was caught only by a check: read the plan before and after, compare estimated and actual rows, `ANALYZE` after loads, prove results identical with `EXCEPT ALL` both ways and counts, and measure three runs, comparing plans and buffers. That's the course's thesis again: SQL bugs are silent, and performance bugs are the quietest, because the answer is right.
