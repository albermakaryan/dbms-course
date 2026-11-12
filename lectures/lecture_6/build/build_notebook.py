"""Build lecture-06-notebook.py from the step templates (src/*.sql).

Each statement becomes a mo.sql cell (or a try/except cell for an error on
purpose), the comment block before it a markdown cell, and the comment block
after its result (the explanation: WRONG..., FIX...) another markdown cell.
Every SQL cell is checked to occur verbatim in lecture-06-demo.sql.
"""

import re
import sys
from pathlib import Path

SP = Path(__file__).resolve().parent
L6 = Path(__file__).resolve().parent.parent
demo = (L6 / "lecture-06-demo.sql").read_text()
demo_norm = re.sub(r"\s+", " ", demo)


def parse(path, step_path=None):
    """-> list of ('comment', [lines]) / ('stmt', sql, is_error)."""
    step = (step_path or (L6 / "steps" / path.name)).read_text().split("\n")
    lines = path.read_text().split("\n")
    items, buf, i = [], [], 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("--") or not line.strip():
            buf.append(line)
            i += 1
            continue
        if buf:
            items.append(("comment", buf))
            buf = []
        start = i
        while not lines[i].split("--")[0].rstrip().endswith(";"):
            i += 1
        sql = "\n".join(lines[start : i + 1]).rstrip().rstrip(";")
        i += 1
        if i < len(lines) and lines[i].strip().startswith("-- =>"):
            i += 1
        # error on purpose? look at the step file's output for this statement
        last = lines[i - 2] if lines[i - 1].startswith("-- =>") else lines[i - 1]
        steptext = "\n".join(step)
        pos = steptext.find(sql + ";\n")
        assert pos >= 0, sql[:60]
        nxt = steptext[pos + len(sql) + 2 :].split("\n", 1)[0]
        is_err = nxt.startswith("-- ERROR")
        items.append(("stmt", sql, is_err))
    if buf:
        items.append(("comment", buf))
    return items


def md_from_comments(lines):
    """Comment lines -> markdown text."""
    out, para, pre, tbl = [], [], [], []

    def flush_para():
        if para:
            out.append(" ".join(para))
            para.clear()

    def flush_pre():
        if pre:
            out.append("```\n" + "\n".join(pre) + "\n```")
            pre.clear()

    def flush_tbl():
        if tbl:
            out.append("\n".join(tbl))
            tbl.clear()

    for raw in lines:
        if not raw.strip():
            flush_para()
            flush_pre()
            flush_tbl()
            continue
        t = raw[2:] if raw.startswith("--") else raw
        if re.match(r"^ ?=+$", t):
            continue
        t = t[1:] if t.startswith(" ") else t
        m = re.match(r"^---- (.*?) ----$", t)
        if m:
            flush_para()
            flush_pre()
            out.append("### " + m.group(1))
            continue
        m = re.match(r"^Lecture 6 — (Part \d+|Recap): (.*)$", t)
        if m:
            flush_para()
            flush_pre()
            out.append(f"## {m.group(1)} — {m.group(2)}")
            continue
        if t.startswith("Run after"):
            continue
        if t.startswith("|"):
            flush_para()
            flush_pre()
            tbl.append(t.replace(" -- ", " — "))
            continue
        flush_tbl()
        starts_pre = re.search(r"\S {2,}\S", t) or (t.startswith("  ") and "->" in t)
        if starts_pre or (pre and t.startswith("  ")):
            flush_para()
            pre.append(t)
            continue
        if t.startswith("* "):
            flush_para()
            flush_pre()
            para.append("\n- " + t[2:])
            continue
        if not t.strip():
            flush_para()
            flush_pre()
            continue
        flush_pre()
        para.append(t.strip().replace(" -- ", " — "))
    flush_para()
    flush_pre()
    flush_tbl()
    out = [x for x in out if not x.startswith("Notebook only")]
    labels = {
        "Task: ": "**Task:** ",
        "Solution: ": "**Solution:** ",
        "Reading the result: ": "**Reading the result:** ",
    }

    def label(x):
        if x.startswith("Real problem: "):
            return "#### " + x
        for k, v in labels.items():
            if x.startswith(k):
                return v + x[len(k) :]
        return x

    out = [label(x) for x in out]
    out = [
        re.sub(
            r"^New function: (.+?) — ",
            lambda m: f"> **New function: `{m.group(1)}`** — ",
            x,
        )
        for x in out
    ]
    text = "\n\n".join(x.strip("\n") for x in out if x.strip())
    return text.replace('"""', "'''")


def md_cell(text):
    if not text.strip():
        return ""
    return f'''@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
{indent(text)}
    """)
    return


'''


def indent(text, n=4):
    return "\n".join((" " * n + l) if l.strip() else "" for l in text.split("\n"))


names = set()


def sql_cell(name, sql, ref=None):
    assert re.sub(r"\s+", " ", sql) in (ref or demo_norm), f"not in demo: {sql[:60]}"
    assert "{" not in sql and '"""' not in sql
    names.add(name)
    return f'''@app.cell
def _(engine, mo):
    {name} = mo.sql(
        f"""
{indent(sql, 8)}
        """,
        engine=engine
    )
    return


'''


def err_cell(sql, ref=None):
    assert re.sub(r"\s+", " ", sql) in (ref or demo_norm), f"not in demo: {sql[:60]}"
    return f'''@app.cell
def _(engine, mo, psycopg):
    # Error on purpose -- shows PostgreSQL's message instead of stopping the notebook.
    try:
        engine.execute("""
{indent(sql, 8)}
        """)
        _shown = mo.callout(mo.md("No error?! This query was supposed to fail."), kind="warn")
    except psycopg.Error as _e:
        _shown = mo.callout(mo.md(f"**ERROR:** `{{_e.diag.message_primary}}`"), kind="danger")
    _shown
    return


'''


def emit(items, part, prefix="p", ref=None):
    cells, n = [], 0
    for it in items:
        if it[0] == "comment":
            cells.append(md_cell(md_from_comments(it[1])))
        else:
            _, sql, is_err = it
            if is_err:
                cells.append(err_cell(sql, ref))
            else:
                n += 1
                cells.append(sql_cell(f"{prefix}{part}_{n:02d}", sql, ref))
    return cells


HEADER = '''import marimo

__generated_with = "0.25.0"
app = marimo.App(width="medium")


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    # Lecture 6 — Window Functions

    The whole lecture, one query at a time, against **the same shop data as Lectures 4 and 5**: `orders` (the header, with `orderTotal`) and `order_items` (the lines, with `lineTotal`), plus Lecture 4's star schema (`fact_sales`, `dim_date`, `dim_customer`, `dim_product`, `dim_employee`).

    What you already know, and every query here can be checked against: 600 orders, 529 completed; completed revenue **157,078.41**; Levon and Astghik never ordered; Ergonomic Chair Pro never sold; 181 online orders with no employee.

    > **A window function computes over a set of related rows, but does not collapse them: every input row survives.**

    **Before you run this:** from the `lecture_6/` folder, run `psql postgres` and `\\i steps/00-setup.sql` (it drops and recreates the `lecture06` database, loads the data, builds the star schema and runs `ANALYZE` so everyone's planner makes the same choices; Parts 2.4, 3.2, 3.3, 4.4 and 4.6 depend on that). Then start the notebook with the connection string in `LECTURE06_DSN`, e.g.

    ```
    LECTURE06_DSN=postgresql://postgres:postgres@localhost:5432/lecture06 marimo edit lecture-06-notebook.py
    ```

    Each trap appears as **wrong query → what's wrong with it → fixed query**, with real results on screen at each step. Needs PostgreSQL 11 or later.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    # Table of contents: built by marimo from every markdown heading below,
    # so it follows the notebook automatically. Click a line to jump there.
    mo.outline(label="Table of contents")
    return


@app.cell
def _():
    import os

    import marimo as mo
    import psycopg

    return mo, os, psycopg


@app.cell
def _(os, psycopg):
    # One connection for the whole notebook. Load the data first with
    # psql + steps/00-setup.sql; set LECTURE06_DSN if yours differs.
    engine = psycopg.connect(
        os.environ.get("LECTURE06_DSN", "postgresql://postgres:postgres@localhost:5432/lecture06"),
        autocommit=True,
    )
    return (engine,)


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Check the data first.** You should see **30 / 8 / 37 / 600 / 965**, then **366** dates and **965** fact rows.
    """)
    return


@app.cell
def _(engine, mo):
    p0_counts = mo.sql(
        f"""
        SELECT 'customers' AS t, count(*) FROM customers
        UNION ALL SELECT 'employees',   count(*) FROM employees
        UNION ALL SELECT 'products',    count(*) FROM products
        UNION ALL SELECT 'orders',      count(*) FROM orders
        UNION ALL SELECT 'order_items', count(*) FROM order_items
        UNION ALL SELECT 'dim_date',    count(*) FROM dim_date
        UNION ALL SELECT 'fact_sales',  count(*) FROM fact_sales
        """,
        engine=engine
    )
    return


'''

SYNTHESIS = (L6 / "lecture-06-notes.md").read_text()
syn = (
    SYNTHESIS[SYNTHESIS.index("## Part 8") : SYNTHESIS.index("## Open questions")]
    .strip()
    .rstrip("-")
    .strip()
)
syn = re.sub(r"\[\^[a-z0-9]+\]", "", syn)

FOOTER = """if __name__ == "__main__":
    app.run()
"""

cells = [HEADER]
for f in sorted((SP / "src").glob("0*.sql")):
    part = f.name[:2].lstrip("0")
    items = parse(f)
    if f.name.startswith("08"):
        # pair each drill question with its answer
        ai = next(
            k
            for k, it in enumerate(items)
            if it[0] == "comment" and any("---- Answers ----" in l for l in it[1])
        )
        qs, ans = items[:ai], items[ai:]
        # first comment of answers block contains the heading + answer 1 text
        q_groups, cur = [], []
        for it in qs:
            cur.append(it)
            if it[0] == "stmt":
                q_groups.append(cur)
                cur = []
        first = q_groups[0][0][1]
        qline = max(k for k, l in enumerate(first) if l.startswith('-- "'))
        intro = [("comment", first[:qline])]
        q_groups[0][0] = ("comment", first[qline:])
        a_groups, cur = [], []
        for it in ans:
            if it[0] == "comment":
                text = [l for l in it[1] if "---- Answers ----" not in l]
                starts = [k for k, l in enumerate(text) if re.match(r"^-- \d\. ", l)]
                if starts:
                    if cur:
                        a_groups.append(cur)
                    cur = [("comment", text[starts[0] :])]
                    continue
            cur.append(it)
        a_groups.append(cur)
        assert len(q_groups) == len(a_groups) == 5, (len(q_groups), len(a_groups))
        cells += emit(intro, part)
        n = 0
        for k, (qg, ag) in enumerate(zip(q_groups, a_groups), 1):
            for it in qg:
                if it[0] == "comment":
                    cells.append(md_cell(f"**Drill {k}.** " + md_from_comments(it[1])))
                else:
                    n += 1
                    cells.append(sql_cell(f"d{k}_wrong", it[1]))
            m = 0
            for it in ag:
                if it[0] == "comment":
                    cells.append(md_cell(md_from_comments(it[1])))
                else:
                    m += 1
                    cells.append(sql_cell(f"d{k}_fix{m if m > 1 else ''}", it[1]))
    else:
        cells += emit(items, part)

cells.append(md_cell(syn))

# Alber's own cells (build/extra_cells.txt): re-insert each group after its anchor.
extra = (SP / "extra_cells.txt").read_text()
for grp in extra.split("### AFTER: ")[1:]:
    anchor, rest = grp.split("\n", 1)
    own = [c.strip("\n") + "\n\n\n" for c in rest.split("### END CELL") if c.strip()]
    hits = [k for k, c in enumerate(cells) if anchor in c]
    assert len(hits) == 1, f"extra_cells anchor found {len(hits)} times: {anchor[:60]}"
    cells[hits[0] + 1 : hits[0] + 1] = own
cells.append(FOOTER)
(L6 / "lecture-06-notebook.py").write_text("".join(c for c in cells if c))
print(len(names), "SQL cells")
