"""Run a step template through psql and paste each statement's real output
under it, in Lecture 5's comment style.

Markers (a line on its own, right after a statement):
  -- =>        paste the full result (header + rows, no dash line, no row count)
  -- =>N       paste header + first N rows, then "-- ... (M rows)"
  -- =>rows    paste only "-- M rows"
Statements without a marker run but print nothing. Errors print as
"-- ERROR:  <message>". Usage: annotate.py template.sql out.sql [db]
"""

import os
import re
import subprocess
import sys

src, dst = sys.argv[1], sys.argv[2]
db = sys.argv[3] if len(sys.argv) > 3 else "lecture06"
port = os.environ.get("PGP", "5432")
lines = open(src).read().split("\n")

# Split into statements: a statement ends at a line whose code ends in ';'
stmts = []  # (start_line, end_line, marker_line_index or None)
buf_start = None
for i, line in enumerate(lines):
    code = line.split("--")[0].rstrip() if not line.lstrip().startswith("--") else ""
    if buf_start is None and code.strip():
        buf_start = i
    if buf_start is not None and code.endswith(";"):
        marker = None
        if i + 1 < len(lines) and re.match(r"^-- =>(\d+|rows)?$", lines[i + 1].strip()):
            marker = i + 1
        stmts.append((buf_start, i, marker))
        buf_start = None

script = []
for n, (a, b, _) in enumerate(stmts):
    script.append(f"\\echo @@@{n}")
    script.append("\n".join(lines[a : b + 1]))
script.append("\\echo @@@end")
res = subprocess.run(
    [
        "psql",
        "-X",
        "-q",
        "-h",
        "127.0.0.1",
        "-p",
        port,
        "-U",
        "postgres",
        "-d",
        db,
        "-v",
        "ON_ERROR_STOP=0",
        "-P",
        "pager=off",
    ],
    input="\n".join(script),
    capture_output=True,
    text=True,
    env={**os.environ, "PGPASSWORD": "postgres"},
)
out = res.stdout
# stderr lines (errors) are interleaved badly; rerun capturing 2>&1 through a shell
res = subprocess.run(
    f"psql -X -q -h 127.0.0.1 -p {port} -U postgres -d {db} -v ON_ERROR_STOP=0 -P pager=off 2>&1",
    shell=True,
    input="\n".join(script),
    capture_output=True,
    text=True,
    env={**os.environ, "PGPASSWORD": "postgres"},
)
out = res.stdout
parts = re.split(r"^@@@(\d+|end)$", out, flags=re.M)
results = {}
for k in range(1, len(parts) - 1, 2):
    if parts[k] != "end":
        results[int(parts[k])] = parts[k + 1].strip("\n")


def fmt(text, mode):
    tl = text.split("\n")
    errs = [l for l in tl if "ERROR:" in l]
    if errs:
        msg = errs[0].split("ERROR:", 1)[1].strip()
        hints = [l.strip() for l in tl if l.startswith("HINT:")]
        return [f"-- ERROR:  {msg}"] + ["-- " + h for h in hints]
    rows_line = [l for l in tl if re.match(r"^\(\d+ rows?\)$", l)]
    nrows = int(re.findall(r"\d+", rows_line[0])[0]) if rows_line else None
    body = [
        l
        for l in tl
        if not re.match(r"^\(\d+ rows?\)$", l)
        and not re.match(r"^-+(\+-+)*$", l)
        and l.strip() != ""
    ]
    if mode == "rows":
        return [f"-- {nrows} rows"]
    body = [l[1:] if l.startswith(" ") else l for l in body]
    body = [l.rstrip() for l in body]
    if mode.isdigit() and nrows is not None and nrows > int(mode):
        return ["-- " + l for l in body[: int(mode) + 1]] + [f"-- ... ({nrows} rows)"]
    if nrows == 0:
        return ["-- " + body[0], "-- (0 rows)"] if body else ["-- (0 rows)"]
    return ["-- " + l for l in body]


outlines = list(lines)
problems = []
for n, (a, b, marker) in reversed(list(enumerate(stmts))):
    r = results.get(n, "")
    is_err = "ERROR:" in r
    if marker is None:
        if is_err and "-- ERROR" not in "\n".join(lines[b + 1 : b + 3]):
            problems.append(f"line {a + 1}: unexpected error: {r}")
        continue
    mode = lines[marker].strip()[5:] or "all"
    outlines[marker : marker + 1] = fmt(r, mode)
open(dst, "w").write("\n".join(outlines))
for p in problems:
    print("PROBLEM", p)
print(f"{len(stmts)} statements, {sum(1 for s in stmts if s[2] is not None)} annotated")
