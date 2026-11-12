"""Run lecture-06-notebook.py with app.run() and compare every mo.sql
DataFrame with the psql output pasted under the same query in steps/*.sql."""

import importlib.util
import re
import sys
from decimal import Decimal
from pathlib import Path

L6 = Path(__file__).resolve().parent.parent
nb_src = (L6 / "lecture-06-notebook.py").read_text()
cells = dict(
    re.findall(r'    (\w+) = mo\.sql\(\n        f"""\n(.*?)\n        """', nb_src, re.S)
)
cells = {k: "\n".join(l[8:] for l in v.split("\n")) for k, v in cells.items()}

steps = "\n".join(
    (L6 / "steps" / f).read_text()
    for f in sorted(p.name for p in (L6 / "steps").glob("0[1-8]*.sql"))
)
slines = steps.split("\n")


src = "\n".join(
    (Path(__file__).parent / "src" / f).read_text()
    for f in sorted(p.name for p in (Path(__file__).parent / "src").glob("0[1-8]*.sql"))
)


def expected(sql):
    joined = "\n".join(slines)
    idx = joined.find(sql + ";\n")
    sidx = src.find(sql + ";\n-- =>")
    if idx < 0 or sidx < 0:
        return None
    s_after = src[sidx + len(sql) + 2 :].split("\n")
    stop = s_after[1]  # the template line right after the marker
    out = []
    for l in joined[idx + len(sql) + 2 :].split("\n"):
        if l == stop:
            break
        out.append(l[3:])
    return out


def norm(v):
    if v is None:
        return ""
    if isinstance(v, bool):
        return "t" if v else "f"
    if isinstance(v, float):
        return repr(v)
    return str(v)


spec = importlib.util.spec_from_file_location("nb", L6 / "lecture-06-notebook.py")
nb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nb)
outputs, defs = nb.app.run()

bad, checked, skipped = 0, 0, []
for name, sql in cells.items():
    df = defs.get(name)
    exp = expected(sql)
    if name == "p0_counts":
        continue
    if exp is None or sql.lstrip().startswith("EXPLAIN"):
        skipped.append(name)
        continue
    rows = (
        df.rows()
        if hasattr(df, "rows")
        else [tuple(r) for r in df.itertuples(index=False)]
    )
    cols = list(df.columns)
    header = [c.strip() for c in exp[0].split("|")]
    total = None
    body = exp[1:]
    if body and body[-1].startswith("..."):
        total = int(re.findall(r"\d+", body[-1])[0])
        body = body[:-1]
    if body and body[0] == "(0 rows)":
        body = []
    want = [[c.strip() for c in r.split("|")] for r in body]
    got = [[norm(v) for v in r] for r in rows[: len(want)]]
    problems = []
    if [c.lower() for c in cols] != header:
        problems.append(f"columns {cols} vs {header}")

    def num(x):
        try:
            return Decimal(x)
        except Exception:
            return x

    if [[num(x) for x in r] for r in got] != [[num(x) for x in r] for r in want]:
        problems.append(f"rows differ:\n   got  {got[:6]}\n   want {want[:6]}")
    if (total or len(want)) != len(rows):
        problems.append(f"row count {len(rows)} vs {total or len(want)}")
    checked += 1
    if problems:
        bad += 1
        print("MISMATCH", name, *problems, sep="\n  ")
print(f"checked {checked} cells, {bad} mismatches, skipped {skipped}")
