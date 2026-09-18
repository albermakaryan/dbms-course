# Introduction to Databases & SQL

Course materials for **Introduction to Databases & SQL**. Written for learners with no computer science
background, and meant to be worked through at a keyboard with
PostgreSQL open, not just read.

The whole course follows one running example: a small electronics shop
in Armenia with customers, employees, products and orders. Lecture 1
introduces it, Lecture 2 turns its spreadsheet into a database, and
each later lecture asks the shop harder questions.

## Lectures

| # | Title | What you do |
|---|---|---|
| 1 | Database Foundations and Frontiers | Slides: what a database is, why files aren't enough, the schema the course will build |
| 2 | From One File to Four Tables | Load a flat sales file, find the redundancy, model it (ER diagram, normal forms), create the tables with keys and constraints, split the data, join it back, evolve the schema with ALTER and DROP |
| 3 | Asking Questions of One Table | The full SELECT: expressions and CASE, WHERE, ORDER BY and LIMIT, DISTINCT, aggregates, GROUP BY and HAVING, the order a query runs in, and a drill on queries that return plausible wrong numbers |

Each hands-on lecture folder has the same layout:

```
lectures/lecture_N/
  lecture-0N-notes.md     the guide -- read this, run the SQL as you go
  lecture-0N-demo.sql     every statement from the notes, in one runnable file
  steps/                  the same statements, one file per Part
  data/                   CSV files the lecture loads, plus an INSERT-only fallback
```

Lecture 2 also has `lecture-02-slides.html` (open it in a browser:
arrow keys to move, `S` for speaker notes, `O` for an overview, `F` for
full screen) and `psql-cheatsheet.md`, the reference for the `psql`
client itself: connecting, `\d`, `\i`, `\copy`, troubleshooting.

## Getting started

You need a PostgreSQL server and the `psql` client. Any recent version
works; Lecture 3 is checked against PostgreSQL 14 and 16.

- **Local install:** see the cheatsheet in `lectures/lecture_2/` for
  roles, databases and the usual connection errors.
- **Docker:** `./start_postgres.sh` starts a server on port 5432 with
  user `postgres` and password `secret`. Then
  `psql -h localhost -U postgres`.

Every lecture starts from its own `steps/00-...sql`, which creates and
loads everything the lecture needs. Run `psql` **from the lecture's
folder** so the relative paths in `\copy` resolve:

```bash
cd lectures/lecture_3
psql lecture03          # create the database first: createdb lecture03
\i steps/00-setup.sql
```

Then open the notes and follow along, one statement at a time.

## About the data

**All data in this repository is synthetic.** The shop, its customers,
employees, orders, emails and phone numbers are invented for teaching.
Any resemblance to real people is coincidental. Product names are
familiar consumer electronics used as recognisable examples; the
prices, costs and stock figures attached to them are made up and do
not describe any real product or seller.

- Lecture 2's data (`lectures/lecture_2/data/`) is a hand-written
  42-row sales file and the four tables it splits into.
- Lecture 3's data (`lectures/lecture_3/data/`) is produced by
  `lectures/lecture_3/generate_data.py`. The generator is seeded, so
  running it again reproduces the CSV files byte for byte, and its
  header comment lists every property the lecture's queries rely on
  (which customers share a name, which product never sold, why online
  orders have no salesperson, and so on). Edit the script, not the
  CSVs.

Expected outputs printed in the notes were produced by running the
statements against a real PostgreSQL server, not written by hand.

## Repository layout

```
lectures/        one folder per lecture (see above)
start_postgres.sh  starts a PostgreSQL server in Docker
```
