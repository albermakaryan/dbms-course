"""Build lecture-07-notebook.py from the step templates (src/NN-*.sql) and
their annotated outputs (steps/NN-*.sql).

Cell kinds (Lecture 6's builder, extended for plans and state changes;
plus the theory slides from slides.py, inserted before their headings):
  * comment block              -> markdown cell
  * SELECT / WITH with a result -> mo.sql cell (named pN_MM)
  * EXPLAIN ...                -> plan cell: the plan as text, plus a check
                                  that its SHAPE (node names, Index Cond /
                                  Filter labels) matches the reference run
  * BEGIN; stmt; ROLLBACK;     -> one cell, run in a transaction that is
                                  always rolled back
  * error on purpose           -> try/except cell showing the message
  * anything else (DDL, SET, VACUUM, INSERT, DO ...) -> run cell
Every SQL text is checked to occur verbatim in lecture-07-demo.sql.
"""

import re
import sys
from pathlib import Path

SP = Path(__file__).resolve().parent
L7 = SP.parent
demo = (L7 / "lecture-07-demo.sql").read_text()
demo_norm = re.sub(r"\s+", " ", demo)
REF_VERSION = "PostgreSQL 18"


# ---------------------------------------------------------------- parsing
def code_part(line):
    if line.lstrip().startswith("--"):
        return ""
    return line.split(" --")[0].rstrip()


def split_statements(lines):
    """Same splitting as annotate.py -> [(start, end, marker_or_None)]."""
    stmts, buf_start, in_dollar = [], None, False
    for i, line in enumerate(lines):
        code = code_part(line)
        if buf_start is None and code.strip():
            buf_start = i
        if code.count("$$") % 2 == 1:
            in_dollar = not in_dollar
        if buf_start is not None and not in_dollar and code.endswith(";"):
            marker = None
            if i + 1 < len(lines) and re.match(r"^-- =>(\d+(,\d+)?|rows)?$", lines[i + 1].strip()):
                marker = i + 1
            stmts.append((buf_start, i, marker))
            buf_start = None
    return stmts


def outputs_for(tpl_lines, step_lines, stmts):
    """For each marker statement, the output lines pasted into the step file."""
    res, offset = {}, 0
    for k, (a, b, m) in enumerate(stmts):
        if m is None:
            continue
        start = m + offset
        nxt = tpl_lines[m + 1] if m + 1 < len(tpl_lines) else None
        j = start
        while j < len(step_lines) and step_lines[j].startswith("--") and step_lines[j] != nxt:
            j += 1
        res[k] = [l[3:] if l.startswith("-- ") else l[2:] for l in step_lines[start:j]]
        offset += (j - start) - 1
    return res


def parse(path):
    """-> items: ('comment', lines) | ('stmt', sql, info)"""
    tpl = path.read_text().split("\n")
    step = (L7 / "steps" / path.name).read_text().split("\n")
    stmts = split_statements(tpl)
    outs = outputs_for(tpl, step, stmts)
    items, cursor = [], 0
    for k, (a, b, m) in enumerate(stmts):
        if a > cursor:
            block = tpl[cursor:a]
            if any(l.strip() for l in block):
                items.append(("comment", block))
        sql = "\n".join(tpl[a : b + 1]).rstrip()
        assert sql.endswith(";")
        sql = sql[:-1]
        out = outs.get(k)
        before = "\n".join(tpl[max(0, a - 3) : a]).lower()
        info = {
            "out": out,
            "marker": tpl[m].strip()[5:] if m is not None else None,
            "error": "error on purpose" in before,
        }
        items.append(("stmt", sql, info))
        cursor = (m + 1) if m is not None else (b + 1)
    if cursor < len(tpl) and any(l.strip() for l in tpl[cursor:]):
        items.append(("comment", tpl[cursor:]))
    return items


# ---------------------------------------------------------------- markdown
def md_from_comments(lines):
    out, para, pre, tbl = [], [], [], []

    def flush_para():
        if para:
            out.append(re.sub(r" --( |$)", r" —\1", " ".join(para)))
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
            flush_para(), flush_pre(), flush_tbl()
            continue
        t = raw[2:] if raw.startswith("--") else raw
        if re.match(r"^ ?=+$", t):
            continue
        t = t[1:] if t.startswith(" ") else t
        m = re.match(r"^---- (.*?) ----$", t)
        if m:
            flush_para(), flush_pre()
            out.append("### " + m.group(1))
            continue
        m = re.match(r"^Lecture 7 — (Part \d+): (.*)$", t)
        if m:
            flush_para(), flush_pre()
            out.append(f"## {m.group(1)} — {m.group(2).replace(' -- ', ' — ')}")
            continue
        if t.startswith("Run after"):
            continue
        if t.startswith("|"):
            flush_para(), flush_pre()
            tbl.append(t.replace(" -- ", " — "))
            continue
        flush_tbl()
        if t.startswith("  ") and not pre and any(x.startswith("\n- ") for x in para) \
                and not re.search(r"\S {2,}\S", t.strip()):
            para.append(t.strip())  # continuation of a bullet item
            continue
        starts_pre = re.search(r"\S {2,}\S", t) or re.match(r"^ {2,}\S", t)
        if starts_pre or (pre and t.startswith("  ")):
            flush_para()
            pre.append(t)
            continue
        if t.startswith("* "):
            flush_para(), flush_pre()
            para.append("\n- " + t[2:])
            continue
        flush_pre()
        if any(x.startswith("\n- ") for x in para) and not t.startswith(" "):
            flush_para()  # a plain line after a bullet list starts a new paragraph
        para.append(t.strip().replace(" -- ", " — "))
    flush_para(), flush_pre(), flush_tbl()
    text = "\n\n".join(x.strip("\n") for x in out if x.strip())
    text = re.sub(r"^(WRONG[^:.]*[:.])", r"**\1**", text, flags=re.M)
    text = re.sub(r"^(FIX[^:.]*[:.])", r"**\1**", text, flags=re.M)
    text = re.sub(r"^(Predict, then run[^:]*:?)", r"**\1**", text, flags=re.M)
    text = re.sub(r"(Error on purpose:?)", r"**\1**", text)
    return text.replace('"""', "'''")


def indent(text, n=4):
    return "\n".join((" " * n + l) if l.strip() else "" for l in text.split("\n"))


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


# ---------------------------------------------------------------- plan shape
def plan_shape(lines):
    """Node names and condition labels, by depth: the part of a plan that
    should not change between machines (times and buffer counts do)."""
    shape = []
    for l in lines:
        if not l.strip() or l.strip() == "QUERY PLAN":
            continue
        depth = len(l) - len(l.lstrip())
        s = l.strip()
        if s.startswith("->"):
            s = s[2:].strip()
        m = re.match(r"^(.*?)  \((cost|actual)=", s)
        if m:
            shape.append(f"{depth:3d} {m.group(1)}")
            continue
        m = re.match(r"^(Index Cond|Filter|Recheck Cond|Hash Cond|Merge Cond|One-Time Filter|Run Condition|Subplans Removed|SubPlan \d+|InitPlan \d+)\b", s)
        if m:
            shape.append(f"{depth:3d}   {m.group(1)}")
    return shape


names = set()


def check_sql(sql):
    assert re.sub(r"\s+", " ", sql) in demo_norm, f"not in demo: {sql[:70]}"
    assert '"""' not in sql


def sql_cell(name, sql):
    check_sql(sql)
    assert "{" not in sql, sql[:60]
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


def plan_cell(sql, out, marker, rollback=False):
    check_sql(sql)
    head = tail = None
    if marker and "," in marker:
        head, tail = (int(x) for x in marker.split(","))
    ref = plan_shape(out or [])
    if head is not None:
        # reference: first `head` and last `tail` plan lines only
        body = [l for l in (out or []) if not l.startswith("...")]
        ref = plan_shape(body[1 : 1 + head]) + ["..."] + plan_shape(body[-tail:])
    args = f"head={head}, tail={tail}, " if head is not None else ""
    return f'''@app.cell
def _(engine, show_plan):
    show_plan(
        engine,
        """
{indent(sql, 8)}
        """,
        {args}rollback={rollback},
        reference={ref!r},
    )
    return


'''


def run_cell(sql, rollback=False):
    check_sql(sql)
    return f'''@app.cell
def _(engine, run_sql):
    run_sql(
        engine,
        """
{indent(sql, 8)}
        """,
        rollback={rollback},
    )
    return


'''


def err_cell(sql):
    check_sql(sql)
    return f'''@app.cell
def _(engine, mo, psycopg):
    # Error on purpose -- shows PostgreSQL's message instead of stopping the notebook.
    try:
        engine.execute("""
{indent(sql, 8)}
        """)
        _shown = mo.callout(mo.md("No error?! This statement was supposed to fail."), kind="warn")
    except psycopg.Error as _e:
        _detail = f"\\n\\n{{_e.diag.message_detail}}" if _e.diag.message_detail else ""
        _shown = mo.callout(mo.md(f"**ERROR:** `{{_e.diag.message_primary}}`{{_detail}}"), kind="danger")
    _shown
    return


'''


# ---------------------------------------------------------------- the cut
# The notebook keeps the core of the lecture. These sections are left out
# (they stay in lecture-07-demo.sql and the notes); delete a line to bring a
# section back. The list gives statements that must still run, so later
# sections see the database exactly as the demo leaves it (each must occur
# verbatim in the demo). They run in one small hidden-code cell.
NOTEBOOK_SKIP = {
    "1.1": [], "1.3": [], "1.7": [],
    "2.2": [], "2.4": ["CREATE EXTENSION IF NOT EXISTS pageinspect"], "2.6": [], "2.7": [],
    "3.1": [], "3.2": [],
    "4.5": ["DROP INDEX orders_big_orderdate_idx, orders_big_status_idx"],
    "5.4": [], "5.6": [], "5.7": ["DROP INDEX orders_big_customerid_idx, orders_big_ordertotal_idx"],
    "6.2": [], "6.3": [], "6.4": [],
    "7.3": [], "7.4": [], "7.5": [],
    "7.6": ["DROP INDEX IF EXISTS orders_big_orderdate_idx, orders_big_customerid_idx,\n"
            "                     orders_big_month_idx, orders_big_deliverydate_idx,\n"
            "                     customers_big_email_pattern_idx"],
    "8.1": [], "8.2": [], "8.3": [], "8.4": [],
    "9.5": [], "9.6": [], "9.7": [],
}
SEEN_SKIPS = set()


def tag_sections(items):
    """Split comment blocks at '---- N.M ...' headings and tag every item with
    its section number ('' before the first heading)."""
    out, sec = [], ""
    for it in items:
        if it[0] != "comment":
            out.append((*it, sec))
            continue
        block = []
        for line in it[1]:
            m = re.match(r"^-- ---- (\d+\.\d+)\b.*----$", line)
            if m:
                if any(l.strip() for l in block):
                    out.append(("comment", block, sec))
                block, sec = [], m.group(1)
            block.append(line)
        if any(l.strip() for l in block):
            out.append(("comment", block, sec))
    return out


def housekeeping_cell(sec, stmts):
    for s in stmts:
        check_sql(s)
    calls = "".join(f'    run_sql(engine, """\n{indent(s, 8)}\n        """)\n' for s in stmts)
    shown = " ".join(re.sub(r"\s+", " ", s) + ";" for s in stmts)
    return f'''@app.cell(hide_code=True)
def _(engine, mo, run_sql):
    # Section {sec} is in the demo only; run the statements later sections
    # need, so the database stays exactly as the demo leaves it.
{calls}    mo.md("<small>Section {sec} is in `lecture-07-demo.sql` and the notes. Here we only ran: `{shown}`</small>")
    return


'''


def emit(items, part):
    cells, n, k = [], 0, 0
    items = tag_sections(items)
    while k < len(items):
        it = items[k]
        sec = it[-1]
        if sec in NOTEBOOK_SKIP:
            SEEN_SKIPS.add(sec)
            # left out: keep SQL cell numbering identical to the full lecture
            if it[0] == "stmt":
                sql, info = it[1], it[2]
                if sql.strip().upper() == "BEGIN":
                    k += 3
                    continue
                first = sql.lstrip().split(None, 1)[0].upper()
                if not info["error"] and first in ("SELECT", "WITH") and info["marker"] is not None:
                    n += 1
            k += 1
            if (k == len(items) or items[k][-1] != sec) and NOTEBOOK_SKIP[sec]:
                cells.append(housekeeping_cell(sec, NOTEBOOK_SKIP[sec]))
            continue
        it = it[:-1]
        if it[0] == "comment":
            cells.append(md_cell(md_from_comments(it[1])))
            k += 1
            continue
        _, sql, info = it
        if sql.strip().upper() == "BEGIN":
            # BEGIN; <stmt>; ROLLBACK;  -> one rolled-back cell
            inner = items[k + 1]
            assert inner[0] == "stmt" and items[k + 2][1].strip().upper() == "ROLLBACK", sql
            isql, iinfo = inner[1], inner[2]
            if isql.lstrip().upper().startswith("EXPLAIN"):
                cells.append(plan_cell(isql, iinfo["out"], iinfo["marker"], rollback=True))
            else:
                cells.append(run_cell(isql, rollback=True))
            k += 3
            continue
        first = sql.lstrip().split(None, 1)[0].upper()
        if info["error"]:
            cells.append(err_cell(sql))
        elif first == "EXPLAIN":
            cells.append(plan_cell(sql, info["out"], info["marker"]))
        elif first in ("SELECT", "WITH") and info["marker"] is not None:
            n += 1
            cells.append(sql_cell(f"p{part}_{n:02d}", sql))
        else:
            cells.append(run_cell(sql))
        k += 1
    return cells


# ---------------------------------------------------------------- notebook
HEADER = '''import marimo

__generated_with = "0.25.0"
app = marimo.App(width="medium")


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    # Lecture 7 — Performance: EXPLAIN, Indexing, Partitioning

    The core of the lecture, one statement at a time. Sections left out here (the numbers skip: 1.1, 1.3, 2.2, …) are in `lecture-07-demo.sql` and `lecture-07-notes.md`; the section numbers match the notes. **Correctness** questions use the same small shop as Lectures 4–6 (600 orders, 529 completed, completed revenue **157,078.41**). **Speed** questions use two generated tables with the same columns: `orders_big` (**5,000,000** orders over 2023–2025) and `customers_big` (**50,000** customers, 48,000 of whom ordered). On 600 rows every query is instant, so there is nothing to measure (Part 1.1).

    > **A performance bug returns the right answer — slowly, or through an index you think it uses. The plan is the only place it shows.**

    **Before you run this:** from the `lecture_7/` folder, run `psql postgres` and `\\i steps/00-setup.sql` (about 45 seconds: it drops and recreates the `lecture07` database, loads the small shop, generates the big tables, and pins two planner settings — no parallel query, no JIT — so your plans look like the notes). Then start the notebook with the connection string in `LECTURE07_DSN`, e.g.

    ```
    LECTURE07_DSN=postgresql://postgres:postgres@localhost:5432/lecture07 marimo edit lecture-07-notebook.py
    ```

    **This notebook changes the database as it goes** (it creates and drops indexes and tables), so run it top to bottom; each Part removes what it created. To start over, run the setup script again. Running everything takes a few minutes.

    **Plans, not milliseconds.** Each `EXPLAIN` cell prints the plan and checks its *shape* — node names and whether a condition is an `Index Cond` or a `Filter` — against the reference run (""" + REF_VERSION + """). Timings and buffer counts will differ on your machine; the shape should not. A yellow box means your plan differs: read both, and the notes say why it can (PostgreSQL version, or a step skipped). Needs PostgreSQL 11 or later.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    # Table of contents: built by marimo from every markdown heading below.
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
    # One connection for the whole notebook: temporary tables and SET
    # commands made in one cell are seen by the next. Load the data first
    # with psql + steps/00-setup.sql; set LECTURE07_DSN if yours differs.
    engine = psycopg.connect(
        os.environ.get("LECTURE07_DSN", "postgresql://postgres:postgres@localhost:5432/lecture07"),
        autocommit=True,
    )
    return (engine,)


@app.cell
def _(mo):
    import re
    import time

    def _shape(lines):
        # Node names and condition labels, by depth -- see build_notebook.py.
        shape = []
        for line in lines:
            if not line.strip() or line.strip() == "QUERY PLAN":
                continue
            depth = len(line) - len(line.lstrip())
            s = line.strip()
            if s.startswith("->"):
                s = s[2:].strip()
            m = re.match(r"^(.*?)  \\((cost|actual)=", s)
            if m:
                shape.append(f"{depth:3d} {m.group(1)}")
                continue
            m = re.match(
                r"^(Index Cond|Filter|Recheck Cond|Hash Cond|Merge Cond|One-Time Filter"
                r"|Run Condition|Subplans Removed|SubPlan \\d+|InitPlan \\d+)\\b",
                s,
            )
            if m:
                shape.append(f"{depth:3d}   {m.group(1)}")
        return shape

    def show_plan(engine, sql, reference, rollback=False, head=None, tail=None):
        """Run an EXPLAIN, show the plan as text, compare its shape with the notes."""
        if rollback:
            # BEGIN ... ROLLBACK: the statement runs, then everything is undone.
            with engine.transaction(force_rollback=True):
                lines = [r[0] for r in engine.execute(sql).fetchall()]
        else:
            lines = [r[0] for r in engine.execute(sql).fetchall()]
        if head is not None and len(lines) > head + tail:
            shape = _shape(lines[:head]) + ["..."] + _shape(lines[-tail:])
            shown = lines[:head] + [f"...   ({len(lines) - head - tail} more lines)"] + lines[-tail:]
        else:
            shape = _shape(lines)
            shown = lines
        text = "\\n".join(shown)
        plan = mo.md("```\\n" + text + "\\n```")
        if shape == reference:
            nodes = [s[4:] for s in reference if s != "..." and not s[4:].startswith("  ")]
            note = mo.callout(
                mo.md("Plan shape matches the notes: " + " → ".join(f"`{n}`" for n in nodes[:3])
                      + (" …" if len(nodes) > 3 else "")),
                kind="success",
            )
        else:
            note = mo.callout(
                mo.vstack([
                    mo.md("**Your plan's shape differs from the reference run.** Compare (depth, node or condition):"),
                    mo.hstack([
                        mo.md("Reference\\n```\\n" + "\\n".join(reference) + "\\n```"),
                        mo.md("Yours\\n```\\n" + "\\n".join(shape) + "\\n```"),
                    ]),
                ]),
                kind="warn",
            )
        return mo.vstack([note, plan])

    def run_sql(engine, sql, rollback=False):
        """Run a statement that returns no table (CREATE, DROP, SET, VACUUM, INSERT ...)."""
        t0 = time.perf_counter()
        if rollback:
            with engine.transaction(force_rollback=True):
                cur = engine.execute(sql)
        else:
            cur = engine.execute(sql)
        seconds = time.perf_counter() - t0
        return mo.md(f"`{cur.statusmessage}` ({seconds:.1f} s)")

    return run_sql, show_plan


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Check the data and the settings first.** You should see **30 / 8 / 37 / 600 / 965**, **366 / 965** for the star, and **50,000 / 5,000,000** for the big tables; then **529** completed orders worth **157,078.41**; then `max_parallel_workers_per_gather` **0** and `jit` **off** (pinned by the setup script) and PostgreSQL's defaults for the rest.
    """)
    return


'''

SETUP_CELLS = [
    """SELECT 'customers' AS t, count(*) FROM customers
UNION ALL SELECT 'employees',     count(*) FROM employees
UNION ALL SELECT 'products',      count(*) FROM products
UNION ALL SELECT 'orders',        count(*) FROM orders
UNION ALL SELECT 'order_items',   count(*) FROM order_items
UNION ALL SELECT 'dim_date',      count(*) FROM dim_date
UNION ALL SELECT 'fact_sales',    count(*) FROM fact_sales
UNION ALL SELECT 'customers_big', count(*) FROM customers_big
UNION ALL SELECT 'orders_big',    count(*) FROM orders_big""",
    """SELECT count(*) AS completed_orders, sum(orderTotal) AS completed_revenue
FROM orders
WHERE status = 'completed'""",
    """SELECT name, setting, unit
FROM pg_settings
WHERE name IN ('server_version', 'max_parallel_workers_per_gather', 'jit',
               'shared_buffers', 'work_mem', 'random_page_cost', 'effective_cache_size')
ORDER BY name""",
]

notes = (L7 / "lecture-07-notes.md").read_text() if (L7 / "lecture-07-notes.md").exists() else ""


def notes_section(start, end):
    if start not in notes:
        return ""
    s = notes[notes.index(start) : notes.index(end)].strip().rstrip("-").strip()
    s = re.sub(r"\[\^[a-z0-9-]+\]", "", s)
    return s


FOOTER = """if __name__ == "__main__":
    app.run()
"""

HEADER = HEADER.replace('""" + REF_VERSION + """', REF_VERSION)
cells = [HEADER]
for k, sql in enumerate(SETUP_CELLS, 1):
    cells.append(sql_cell(f"p0_{k:02d}", sql))
for f in sorted((SP / "src").glob("[0-9][0-9]-*.sql")):
    part = f.name[:2].lstrip("0")
    items = parse(f)
    part_cells = emit(items, part)
    if part == "10":
        rule = notes_section("### 10.1 The rule", "### 10.2")
        if rule:
            part_cells.insert(1, md_cell(rule))
    cells += part_cells

assert SEEN_SKIPS == set(NOTEBOOK_SKIP), f"unknown sections in NOTEBOOK_SKIP: {set(NOTEBOOK_SKIP) - SEEN_SKIPS}"

syn = notes_section("## Part 11", "## Lab")
if syn:
    cells.append(md_cell(syn))
cells.append(FOOTER)

# ---- theory slides (build/slides.py): one hide_code cell each, right before
# the markdown heading it is anchored to (the markdown cell is split there).
import slides as _slides  # noqa: E402

MD_HEAD = '@app.cell(hide_code=True)\ndef _(mo):\n    mo.md(r"""\n'
MD_TAIL = '\n    """)\n    return\n\n\n'


def slide_cell(svg):
    assert "'''" not in svg
    return f"@app.cell(hide_code=True)\ndef _(mo):\n    mo.Html(r'''{svg}''')\n    return\n\n\n"


cells = [c for c in cells if c]
for entry in [e for e in _slides.SLIDES if e[1] in _slides.IN_NOTEBOOK]:
    anchor = "\n    " + entry[0]
    hits = [i for i, c in enumerate(cells) if c.startswith(MD_HEAD) and anchor in c]
    assert len(hits) == 1, f"slide anchor {entry[0]!r} found in {len(hits)} markdown cells"
    i = hits[0]
    c = cells[i]
    cut = c.index(anchor)
    before, after = c[:cut], c[cut + 1 :]
    new = []
    if before.strip() != MD_HEAD.strip():
        new.append(before.rstrip() + MD_TAIL)
    new.append(slide_cell(_slides.render(entry)))
    new.append(MD_HEAD + after)
    cells[i : i + 1] = new

text = "".join(c for c in cells if c)


def report(label, text):
    print(label, text.count("mo.sql(\n"), "SQL result cells,", text.count("show_plan(\n"), "plan cells,",
          text.count("run_sql(\n") + text.count("run_sql(engine,"), "run statements,",
          text.count("Error on purpose --"), "error cells,", text.count("mo.Html(r'''<svg"), "slides")


if "--detailed" in sys.argv:
    # the step-by-step notebook (kept as lecture-07-notebook.py.bak)
    (L7 / "lecture-07-notebook.py.bak").write_text(text)
    report("lecture-07-notebook.py.bak:", text)

# lecture-07-notebook.py is Alber's working notebook, edited by hand: this
# script never writes it. Its diagrams and functions are in ../notebook_tools/.
