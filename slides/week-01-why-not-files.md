---
marp: true
theme: course
paginate: true
footer: DBMS & Data Platforms
---

<!-- _class: lead -->

# Week 01 — Why not just files?

### Database Systems & Data Platforms

[INSTRUCTOR NAME] · [UNIVERSITY]

<!-- Speaker notes: don't introduce yourself yet. Go straight to the cold-open question on the next slide, then circle back to logistics at the end. -->

---

<!-- _class: lead -->

# Who needs to understand databases in the era of AI?

<!-- Speaker notes: let this hang for ten seconds. Take two or three answers from the room. Common answer: "nobody, AI does it." This whole course exists to answer this question properly — tell them we'll return to it in week 16 with the semester as evidence. -->

---

## The business decision

**Rivertown Coffee Roasters** — 3 shops, 40 employees, growing fast.

Everything runs on one Excel workbook: `orders_FINAL_v3 (2).xlsx`.

- Inventory, orders, customer list, payroll — all tabs in one file
- Shared on a network drive; sometimes emailed
- The owner wants to know: *"Can we keep running like this?"*

<!-- Speaker notes: this is a real pattern — most small businesses genuinely run this way. The point isn't to mock it; files are a legitimate starting point. The question is what breaks, and when. -->

---

## The live failure demo

I'm going to run this business, live, on that spreadsheet.

**Watch what breaks.**

<!-- Speaker notes: the next five slides narrate the demo. Perform each failure live in Excel/LibreOffice + a CSV; the slides are a backup and a summary. Rehearse: the demo IS the lecture. Screenshots as fallback in assets/week-01/. -->

---

## Failure 1 — the silent lost update

Two managers open the workbook at the same time.

1. Ana updates the stock count for beans: `120 → 80`
2. Boris, in his copy, fixes a customer phone number
3. Both hit **Save**

**Whoever saves last wins. The other change vanishes — silently.**

Nobody is notified. Nobody knows.

<!-- Speaker notes: perform with two windows / two volunteers. Emphasize "silently": no error, no warning, no log. Ask: how would you even detect this happened last month? -->

---

## Failure 2 — Excel mangles your data

| You typed | Excel stored |
|---|---|
| `03/04/2026` (4 March) | April 3rd — or a number like `46115` |
| Product code `00742` | `742` — leading zeros gone |
| Gene name `MARCH1` | `1-Mar` (real scientific-literature bug) |

**No types, no rules — the file happily stores nonsense.**

<!-- Speaker notes: the gene-name story lands well: thousands of published genetics papers had corrupted data; the genetics community renamed the genes because fixing Excel was harder. Types are a contract; files have none. -->

---

## Failure 3 — three copies, three truths

`orders_FINAL.xlsx`
`orders_FINAL_v3 (2).xlsx`
`orders_FINAL_v3 (2) - Copy - USE THIS ONE.xlsx`

Finance reports revenue from one file.
Operations counts inventory from another.

**Which number does the owner take to the bank?**

<!-- Speaker notes: everyone laughs because everyone has seen these filenames. The serious version: when two reports disagree, an organization spends real hours arguing about whose number is right instead of deciding. That's the cost of no single source of truth. -->

---

## Failure 4 — crash mid-save

Save a large file. Pull the plug halfway.

- Half the bytes are the new version, half the old
- The file may not open at all — or worse, **open and look fine**

A file has no concept of "this change happened entirely, or not at all."

<!-- Speaker notes: demo with a script that kills a write mid-way if rehearsed, otherwise narrate. Plant the word for later: what we're missing is ATOMICITY. Databases survive being unplugged mid-write; week 6 shows how (WAL). -->

---

## Failure 5 — every question scans everything

*"How much did customer #4589 spend last month?"*

With a CSV, the only way is: **read every row, every time.**

- 10,000 rows: fine
- 10,000,000 rows: minutes, for every single question

And you write the *how* by hand, every time.

<!-- Speaker notes: open a big CSV and let the scan visibly take time. This failure motivates both declarative queries (say WHAT, not HOW) and indexes (week 5). -->

---

## What a DBMS actually promises

| The failure you saw | The promise that fixes it |
|---|---|
| Three versions of truth | **One source of truth** |
| Mangled dates, lost zeros | **Constraints & types** |
| Lost update | **Safe concurrent access** |
| Corrupt half-saved file | **Atomicity** (all-or-nothing) |
| Scan everything by hand | **Declarative queries** |

<!-- Speaker notes: this slide is the week's takeaway. Each promise is one demo failure, inverted. Each row is also a forward pointer: constraints → week 2–3, concurrency → week 6, queries/performance → weeks 4–5. -->

---

## Declarative: say *what*, not *how*

```sql
SELECT customer_id, SUM(amount) AS total_spent
FROM   orders
WHERE  order_date >= DATE '2026-06-01'
GROUP  BY customer_id
ORDER  BY total_spent DESC
LIMIT  10;
```

You state the question. **The database figures out the plan.**

<!-- Speaker notes: first SQL on a slide this semester — read it aloud in English first ("top ten customers by spend since June"). Note how close it is to the business question. The "figures out the plan" part becomes week 4. -->

---

## Under the hood — pages, not rows

Intuition only, no internals exam:

- A database stores data in **fixed-size pages** (8 KB in PostgreSQL)
- The unit of reading is a *page*, never a single row
- Finding one row cheaply = knowing *which page* to read

<!-- Speaker notes: analogy — a warehouse moves whole pallets, not single items. This one idea quietly powers everything about performance later: an index is a way to know which pallet to fetch. -->

---

## Row layout vs column layout

**Row store** — all of one order together:
`(4589, 2026-06-12, 49.90, 'paid') …`
Great for: *fetch order #4589* — operational work.

**Column store** — all the amounts together:
`49.90, 12.50, 230.00, …`
Great for: *average order value this year* — analytics.

<!-- Speaker notes: just plant the distinction; it becomes week 7 (OLTP vs OLAP). One access pattern reads one entity fully; the other reads one attribute across millions of entities. -->

---

## Memory hierarchy — why layout matters

![placeholder]([LATENCY-NUMBERS VISUAL — assets/week-01/latency-numbers.png])

- RAM is ~1000× faster than disk
- **Sequential** reads are far cheaper than **random** hops
- Databases are engineered around exactly these two facts

<!-- Speaker notes: use the classic "latency numbers every programmer should know" scaled to human time: RAM = seconds, disk = weeks. Visual placeholder — drop the diagram into assets/week-01/ before lecture. -->

---

## Anatomy of a database system

```text
   your SQL
      │
   ┌──▼──────┐   understands the query
   │ Parser   │
   ├─────────┤   picks the cheapest plan
   │ Planner  │
   ├─────────┤   runs the plan
   │ Executor │
   ├─────────┤   pages, files, WAL, caching
   │ Storage  │
   └─────────┘
```

**PostgreSQL** — our system all semester — is exactly this picture.

<!-- Speaker notes: four boxes, that's the whole mental model. Week 4 lives in the planner (EXPLAIN), weeks 5–6 in storage. Postgres: 30 years old, open source, runs a huge share of the world's applications — it's not a "teaching database." -->

---

<!-- _class: lead -->

# "AI writes SQL well. You're here to become the person who signs off on the number — and you cannot audit what you cannot do."

<!-- Speaker notes: the course's framing line, stated explicitly in week one. AI's signature failure is plausible-but-wrong: a join that double-counts revenue, a NULL that drops rows. Someone must catch it and be accountable. That person is employable. That's what the next eight weeks build. -->

---

## The course map — the arc

files → **relational** → distributed → modern stack → vectors

- Weeks 1–8: the relational core, on PostgreSQL, by hand
- Weeks 9–11: beyond tables, beyond one machine
- Weeks 12–14: the modern stack — dbt, Airflow, Kafka
- Weeks 15–16: vectors, RAG, and the capstone

<!-- Speaker notes: every system in this arc was built because the previous one failed at some workload — that's the story of the whole semester, told once here. -->

---

## The course map — two phases

**Phase 1 (weeks 1–8): unaided.** No AI on graded work.
Fluency first — judgment only forms by feeling what wrong looks like.

**Phase 2 (weeks 9–16): AI-assisted, disclosed.** Build real things with
AI, and account for where you overrode it and why.

Hinge: the **midterm** — practical SQL, in-lab, unaided.

<!-- Speaker notes: be direct about why: policing AI for 16 weeks is a losing arms race; instead, one strict checkpoint where it matters, then honest disclosed use. From week 3, labs include verification drills — AI-written queries with planted bugs to find. -->

---

## What gets graded

| Component | Weight |
|---|---|
| Weekly labs + standing homework | 20% |
| Midterm practical SQL exam | 20% |
| Final project (public portfolio repo) | 40% |
| Concept exam + participation | 20% |

<!-- Speaker notes: highlight the final project: a public GitHub repo they can link from a CV — for a non-CS graduate, having anything shippable to show is rare and loud in the job market. Details in the syllabus. -->

---

## Lab bridge — the next 90 minutes

1. Connect **DBeaver** to the course PostgreSQL instance
2. 5-minute SQL diagnostic (know SQL already? — you're a lab helper)
3. Your first queries on a real e-commerce dataset:
   `SELECT` · `WHERE` · `ORDER BY` · `LIMIT`

<!-- Speaker notes: goal today is zero-friction setup — nobody leaves without a working connection and one successful query. Credentials handout in lab. The diagnostic is not graded; say so explicitly. -->

---

<!-- _class: lead -->

# See you in lab.

### Next week: How do I model this business as tables?

<!-- Speaker notes: one-line teaser — today we saw why files fail; next week we start building the thing that doesn't. -->
