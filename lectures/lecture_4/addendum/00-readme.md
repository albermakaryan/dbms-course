# Lecture 4 addendum — deeper JOIN traps

Eight short demos that go beyond the WHERE-vs-ON example in
`lecture-04-demo.sql`. They came out of live Q&A.

Every file is **standalone**. It creates its own 2–5-row scratch tables
(suffixed with the file number, so none collide), shows the trap and
the fix, and drops its tables at the end. Run any one on its own, in
any database, in any order:

```
psql <any-database> -f addendum/03-cascade-inner-join-after-left-join.sql
```

Each query is followed by a comment with the exact rows it returns.
Every count was checked by running each file alone in a fresh, empty
database, and all eight back to back (twice) in one session.

## Order for class

| # | File | The trap in one sentence |
|---|---|---|
| 1 | `01-left-join-where-collapses-to-inner.sql` | A WHERE condition on the right table of a LEFT JOIN drops the NULL-padded rows, so the result is identical to an INNER JOIN. |
| 2 | `02-left-join-on-fix.sql` | The fix for 1: the same condition in ON decides what counts as a match, and the unmatched category survives with a count of 0. |
| 3 | `03-cascade-inner-join-after-left-join.sql` | An INNER JOIN placed after a LEFT JOIN throws away the rows the LEFT JOIN had kept. |
| 4 | `04-or-is-null-patch.sql` | `WHERE cond OR key IS NULL` looks like the ON fix but only re-admits rows with no match at all; it drops rows whose matches all fail the condition. |
| 5 | `05-nullable-column-on-vs-where.sql` | Testing a nullable column for NULL in ON vs in WHERE answers two different questions; the product with only non-NULL matches is the one that differs. |
| 6 | `06-natural-join-hidden-condition.sql` | NATURAL JOIN silently joins on every shared column name, including ones that differ or are NULL. |
| 7 | `07-and-or-precedence-in-on.sql` | Without parentheses, `ON key AND a OR b` lets `b` match rows whose keys differ, pairing unrelated rows. |
| 8 | `08-count-filter-clause.sql` | Not a trap: several conditional counts in one query with `count(*) FILTER (WHERE …)`, next to the equivalent `CASE WHEN`. |
