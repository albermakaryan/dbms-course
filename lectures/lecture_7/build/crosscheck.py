"""Compare another PostgreSQL version's output with the reference steps/.

Run every template through annotate.py against a database on port PGP
(freshly set up with steps/00-setup.sql), into OUTDIR, then compare
statement by statement with steps/*.sql: plan shapes for EXPLAIN, the
pasted table for everything else. Prints only the differences.
Usage: PGP=55416 python crosscheck.py OUTDIR
"""

import os
import re
import subprocess
import sys
from pathlib import Path

SP = Path(__file__).resolve().parent
L7 = SP.parent
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)


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


def outputs(tpl, step, stmts):
    res, offset = {}, 0
    for k, (a, b, m) in enumerate(stmts):
        if m is None:
            continue
        start = m + offset
        nxt = tpl[m + 1] if m + 1 < len(tpl) else None
        j = start
        while j < len(step) and step[j].startswith("--") and step[j] != nxt:
            j += 1
        res[k] = [l[3:] for l in step[start:j]]
        offset += (j - start) - 1
    return res


def shape(lines):
    sh = []
    for l in lines:
        if not l.strip() or l.strip() == "QUERY PLAN" or l.startswith("..."):
            continue
        depth = len(l) - len(l.lstrip())
        s = l.strip()
        s = s[2:].strip() if s.startswith("->") else s
        m = re.match(r"^(.*?)  \((cost|actual)=", s)
        if m:
            sh.append(f"{depth:3d} {m.group(1)}")
            continue
        m = re.match(r"^(Index Cond|Filter|Recheck Cond|Hash Cond|Merge Cond|One-Time Filter|Run Condition|Subplans Removed|SubPlan \d+|InitPlan \d+)\b", s)
        if m:
            sh.append(f"{depth:3d}   {m.group(1)}")
    return sh


def table(lines):
    """Header + rows only (stop at the first prose line)."""
    if not lines:
        return []
    ncol = lines[0].count("|")
    rows = [lines[0]]
    for l in lines[1:]:
        if l.count("|") != ncol or l.startswith("..."):
            break
        rows.append(l)
    return [re.sub(r"\s+", " ", r).strip() for r in rows]


env = {**os.environ}
for f in sorted((SP / "src").glob("[0-9][0-9]-*.sql")) + [SP / "src" / "lab-key.sql"]:
    subprocess.run([sys.executable, str(SP / "annotate.py"), str(f), str(out / f.name)], env=env, check=True)
    tpl = f.read_text().split("\n")
    stmts = split_statements(tpl)
    ref = outputs(tpl, (L7 / "steps" / f.name).read_text().split("\n"), stmts)
    oth = outputs(tpl, (out / f.name).read_text().split("\n"), stmts)
    for k, (a, b, m) in enumerate(stmts):
        if m is None:
            continue
        sql = " ".join(tpl[a : b + 1])[:90]
        r, o = ref.get(k, []), oth.get(k, [])
        if tpl[a].lstrip().upper().startswith("EXPLAIN") or (r and r[0].strip() == "QUERY PLAN"):
            if shape(r) != shape(o):
                print(f"\n{f.name}:{a + 1} PLAN DIFFERS  {sql}")
                print("  ref:", " | ".join(shape(r)))
                print("  oth:", " | ".join(shape(o)))
        elif table(r) != table(o):
            print(f"\n{f.name}:{a + 1} RESULT DIFFERS  {sql}")
            print("  ref:", table(r)[:6])
            print("  oth:", table(o)[:6])
