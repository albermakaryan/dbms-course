"""Run lecture-07-notebook.py with app.run() on a FRESHLY SET UP lecture07
database and check it against the demo:

  * every mo.sql result cell vs the psql output pasted under the same query
    in steps/*.sql (cells whose output depends on the run are skipped and
    listed);
  * every plan cell: did its shape match the reference? (prints the
    differences);
  * every error-on-purpose cell: did it raise?
Usage: LECTURE07_DSN=... python verify_notebook.py
"""

import importlib.util
import re
import sys
from decimal import Decimal
from pathlib import Path

L7 = Path(__file__).resolve().parent.parent
nb_src = (L7 / "lecture-07-notebook.py").read_text()
cells = dict(re.findall(r'    (\w+) = mo\.sql\(\n        f"""\n(.*?)\n        """', nb_src, re.S))
cells = {k: "\n".join(l[8:] for l in v.split("\n")) for k, v in cells.items()}

def code_part(line):
    return "" if line.lstrip().startswith("--") else line.split(" --")[0].rstrip()


def split_statements(lines):
    stmts, buf_start, in_dollar = [], None, False
    for i, line in enumerate(lines):
        code = code_part(line)
        if buf_start is None and code.strip():
            buf_start = i
        if code.count("$$") % 2 == 1:
            in_dollar = not in_dollar
        if buf_start is not None and not in_dollar and code.endswith(";"):
            m = i + 1 if i + 1 < len(lines) and re.match(r"^-- =>(\d+(,\d+)?|rows)?$", lines[i + 1].strip()) else None
            stmts.append((buf_start, i, m))
            buf_start = None
    return stmts


def expected_by_cell():
    """Cell name -> pasted output lines, matched by position exactly as
    build_notebook.py numbers the cells (pN_MM = the MM-th SELECT/WITH
    with a result in Part N, outside BEGIN...ROLLBACK and error cells)."""
    res = {}
    for f in sorted((L7 / "build" / "src").glob("[0-9][0-9]-*.sql")):
        part = f.name[:2].lstrip("0")
        tpl = f.read_text().split("\n")
        step = (L7 / "steps" / f.name).read_text().split("\n")
        stmts = split_statements(tpl)
        offset, n, in_txn = 0, 0, False
        for a, b, m in stmts:
            sql = "\n".join(tpl[a : b + 1]).strip()
            out = None
            if m is not None:
                start = m + offset
                nxt = tpl[m + 1] if m + 1 < len(tpl) else None
                j = start
                while j < len(step) and step[j].startswith("--") and step[j] != nxt:
                    j += 1
                out = [l[3:] for l in step[start:j]]
                offset += (j - start) - 1
            first = sql.split(None, 1)[0].upper().rstrip(";")
            before = "\n".join(tpl[max(0, a - 3) : a]).lower()
            if first == "BEGIN":
                in_txn = True
                continue
            if first == "ROLLBACK":
                in_txn = False
                continue
            if in_txn or "error on purpose" in before or first not in ("SELECT", "WITH") or m is None:
                continue
            n += 1
            res[f"p{part}_{n:02d}"] = out
    return res


EXPECTED = expected_by_cell()

# Output that legitimately changes from run to run (sampled statistics,
# usage counters that depend on what ran before).
NONDETERMINISTIC = {
    "p2_01", "p2_02", "p2_23", "p2_24",  # file paths and names: differ per machine
    "p2_14", "p2_15", "p2_16", "p2_17",  # transaction numbers (xmin, xmax)
    "p3_01", "p3_02", "p3_03",  # sampled statistics: change on every ANALYZE
    "p10_06",  # pg_stat_user_indexes: counts everything run before
    # 2.9's copy of 2023 (CREATE TABLE AS): 16,390 pages in the demo and the detailed
    # notebook, 16,388 when the student notebook runs it; 128 MB either way. Cause not pinned.
    "p2_19", "p2_20",
}


def expected(name):
    out = EXPECTED.get(name)
    if not out:
        return None
    header = out[0]
    ncol = header.count("|")
    rows = [header]
    for i, l in enumerate(out[1:], 1):
        if l.startswith("...") and "more lines" in l:
            # head/tail listing (-- =>N,K): shown head + hidden + tail rows
            tail = [t for t in out[i + 1 :] if t.count("|") == ncol]
            hidden = int(re.findall(r"\d+", l)[0])
            rows.append(f"... ({len(rows) - 1 + hidden + len(tail)} rows)")
            break
        if l.startswith("...") or l == "(0 rows)":
            rows.append(l)
            break
        if l.count("|") != ncol:
            break
        if ncol == 0 and len(rows) > 1:
            break  # single-column results here are always one value
        rows.append(l)
    return rows


def norm(v):
    if v is None:
        return ""
    if isinstance(v, bool):
        return "t" if v else "f"
    if isinstance(v, float):
        return repr(v)
    # psql prints control characters as \xHH; tabs it expands to spaces
    return re.sub(r"[\x00-\x08\x0b-\x1f]", lambda m: f"\\x{ord(m.group()):02X}", str(v))


def ws(x):
    return re.sub(r"\s+", " ", x) if isinstance(x, str) else x


def num(x):
    try:
        return Decimal(x)
    except Exception:
        return x


sys.path.insert(0, str(L7))  # the notebook imports notebook_tools/, which sits next to it
spec = importlib.util.spec_from_file_location("nb", L7 / "lecture-07-notebook.py")
nb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nb)
outputs, defs = nb.app.run()

bad, checked, skipped = 0, 0, []
for name, sql in cells.items():
    if name.startswith("p0_") or name in NONDETERMINISTIC:
        skipped.append(name)
        continue
    exp = expected(name)
    if exp is None:
        skipped.append(name)
        continue
    df = defs.get(name)
    rows = df.rows() if hasattr(df, "rows") else [tuple(r) for r in df.itertuples(index=False)]
    header = [c.strip() for c in exp[0].split("|")]
    body = exp[1:]
    total = None
    if body and body[-1].startswith("..."):
        total = int(re.findall(r"\d+", body[-1])[0])
        body = body[:-1]
    if body and body[0] == "(0 rows)":
        body = []
    want = [[c.strip() for c in r.split("|")] for r in body]
    got = [[norm(v) for v in r] for r in rows[: len(want)]]
    problems = []
    if [c.lower() for c in df.columns] != header:
        problems.append(f"columns {list(df.columns)} vs {header}")
    if [[ws(num(x)) for x in r] for r in got] != [[ws(num(x)) for x in r] for r in want]:
        problems.append(f"rows differ:\n   got  {got[:6]}\n   want {want[:6]}")
    if (total or len(want)) != len(rows):
        problems.append(f"row count {len(rows)} vs {total or len(want)}")
    checked += 1
    if problems:
        bad += 1
        print("MISMATCH", name, *problems, sep="\n  ")

texts = []
for o in list(outputs):
    t = getattr(o, "text", None)
    if t is None and hasattr(o, "_repr_html_"):
        t = o._repr_html_()
    texts.append(t or "")
html = "\n".join(texts)
match = html.count("Plan shape matches the notes")
differ = html.count("shape differs from the reference")
errors_ok = html.count("<strong>ERROR:</strong>") + html.count("**ERROR:**")
no_error = html.count("No error?!")
print(f"result cells: checked {checked}, {bad} mismatches, skipped {skipped}")
print(f"plan cells: {match} match, {differ} differ")
print(f"error cells: {no_error} did NOT raise")
if differ:
    import html as _html
    clean = html.replace("&#92;u003c", "<").replace("&#92;u003e", ">").replace("&#92;n", "\n")
    clean = _html.unescape(_html.unescape(clean)).replace("\\n", "\n")
    for block in re.findall(r"shape differs.*?(?=Plan shape matches|shape differs|$)", clean, re.S)[:20]:
        txt = re.sub(r"<[^>]+>", " ", block)
        txt = re.sub(r"[ \t]+", " ", txt)
        txt = re.sub(r"\n\s*\n+", "\n", txt)
        print("DIFF:", txt[:3000])
