# Database Systems & Data Platforms

Slides and labs for a 16-week master's course for business-school students
with no CS background. Every week pairs a real business decision with the
system built to answer it — relational fundamentals unaided first (weeks
1–8), then the modern data stack and vectors with AI as a disclosed tool
(weeks 9–16). The through-line: *AI writes SQL well; you're here to become
the person who signs off on the number.*

Instructor: [INSTRUCTOR NAME] · [UNIVERSITY] · [CONTACT]

## Weekly decks

| # | Week | Slides | Lab |
|---|---|---|---|
| 01 | Why not just files? | [slides](week-01-why-not-files.html) | [lab](labs/week-01/lab-01-handout.md) |
| 02 | How do I model this business as tables? | [slides](week-02-modeling-as-tables.html) | — |
| 03 | What shape should this data take? | [slides](week-03-data-shape.html) | — |
| 04 | Why is this query slow, and where do I even look? | [slides](week-04-why-is-this-slow.html) | — |
| 05 | Do I need an index, a partition, or neither? | [slides](week-05-index-partition-neither.html) | — |
| 06 | Can I trust this data under concurrent writes? | [slides](week-06-trusting-concurrent-writes.html) | — |
| 07 | Is this a reporting problem or an operational one? | [slides](week-07-reporting-vs-operational.html) | — |
| 08 | What happens when one machine isn't enough? | [slides](week-08-one-machine-not-enough.html) | — |
| 09 | My data doesn't look like a table. Now what? | [slides](week-09-not-a-table.html) | — |
| 10 | When do I actually reach for MongoDB over Postgres? | [slides](week-10-mongodb-vs-postgres.html) | — |
| 11 | Where does this data live once the business has "a lot" of it? | [slides](week-11-data-at-scale.html) | — |
| 12 | Who decides what "clean data" means? | [slides](week-12-clean-data-dbt.html) | — |
| 13 | Who — or what — runs this when it breaks at 3am? | [slides](week-13-orchestration-3am.html) | — |
| 14 | Does this need to happen now, or can it wait? | [slides](week-14-batch-vs-streaming.html) | — |
| 15 | When does "search" stop being exact-match? | [slides](week-15-beyond-exact-match.html) | — |
| 16 | Given a real business problem, what would you actually build? | [slides](week-16-what-would-you-build.html) | — |

Slide links are relative to the published GitHub Pages site; lab links point
into this repository. Weeks 02–16 are stubs under active drafting.

## Repository layout

```
slides/     one Marp markdown deck per week + week-template.md
theme/      course.css — the single shared Marp theme
assets/     shared/ + one folder per week for images and diagrams
labs/       one folder per week: handout + starter SQL
datasets/   load scripts and dataset notes (never data dumps)
scripts/    build.sh — renders everything
```

## Building locally

Requires **Node.js** (18+). No global installs — `npx` fetches Marp CLI.

```bash
./scripts/build.sh
```

- HTML decks → `site/`
- PDF decks (university archive) → `dist/pdf/`

On push to `main`, GitHub Actions builds the decks and deploys `site/` to
GitHub Pages ([publish workflow](.github/workflows/publish.yml)).

## Authoring rules

- Marp markdown only; all styling lives in `theme/course.css` — no inline
  styles in decks.
- Decks are self-contained: recap by concept, never by another deck's slide
  numbers.
- Zero-padded filenames (`week-01-…`) so listings sort correctly.
- New week: copy `slides/week-template.md`, keep/delete the phase-conditional
  slides per the comments inside it.
