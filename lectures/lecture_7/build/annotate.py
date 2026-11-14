"""Run a step template through psql and paste each statement's real output
under it (Lecture 6's tool, extended for Lecture 7).

Markers (a line on its own, right after a statement):
  -- =>        paste the full result (header + rows, no dash line, no row count)
  -- =>N       paste header + first N rows, then "-- ... (M rows)"
  -- =>N,K     paste header + first N rows, "-- ...", then the last K rows
               (for EXPLAIN plans with a thousand partitions)
  -- =>rows    paste only "-- M rows"
Statements without a marker run but print nothing. Errors print as
"-- ERROR:  <message>" plus psql's DETAIL/HINT lines. Dollar-quoted bodies
(DO $$ ... $$;) count as one statement.
Usage: annotate.py template.sql out.sql [db]      (PGP = port)
"""

import os
import re
import subprocess
import sys

src, dst = sys.argv[1], sys.argv[2]
db = sys.argv[3] if len(sys.argv) > 3 else "lecture07"
port = os.environ.get("PGP", "5432")
lines = open(src).read().split("\n")


def code_part(line):
    if line.lstrip().startswith("--"):
        return ""
    return line.split(" --")[0].rstrip()


# Split into statements: a statement ends at a line whose code ends in ';',
# unless we are inside a $$ ... $$ body.
stmts = []  # (start_line, end_line, marker_line_index or None)
buf_start, in_dollar = None, False
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

script = []
for n, (a, b, _) in enumerate(stmts):
    script.append(f"\\echo @@@{n}")
    script.append("\n".join(lines[a : b + 1]))
script.append("\\echo @@@end")
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
        extra = [l.strip() for l in tl if l.startswith(("DETAIL:", "HINT:"))]
        return [f"-- ERROR:  {msg}"] + ["-- " + h for h in extra]
    rows_line = [l for l in tl if re.match(r"^\(\d+ rows?\)$", l)]
    nrows = int(re.findall(r"\d+", rows_line[0])[0]) if rows_line else None
    body = [
        l
        for l in tl
        if not re.match(r"^\(\d+ rows?\)$", l)
        and not re.match(r"^-+(\+-+)*$", l)
        and l.strip() != ""
        and not l.startswith(("NOTICE:", "INFO:"))
    ]
    if mode == "rows":
        return [f"-- {nrows} rows"]
    body = [l[1:] if l.startswith(" ") else l for l in body]
    body = [l.rstrip() for l in body]
    if "," in mode:
        head, tail = (int(x) for x in mode.split(","))
        if len(body) > head + tail + 1:
            return (
                ["-- " + l for l in body[: head + 1]]
                + [f"-- ...   ({len(body) - 1 - head - tail} more lines)"]
                + ["-- " + l for l in body[-tail:]]
            )
        return ["-- " + l for l in body]
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
        if is_err and "error on purpose" not in "\n".join(lines[max(0, a - 3) : a]).lower():
            problems.append(f"line {a + 1}: unexpected error: {r}")
        continue
    mode = lines[marker].strip()[5:] or "all"
    if is_err and "error on purpose" not in "\n".join(lines[max(0, a - 3) : a]).lower():
        problems.append(f"line {a + 1}: unexpected error: {r}")
    outlines[marker : marker + 1] = fmt(r, mode)
open(dst, "w").write("\n".join(outlines))
for p in problems:
    print("PROBLEM", src, p)
print(f"{os.path.basename(src)}: {len(stmts)} statements, {sum(1 for s in stmts if s[2] is not None)} annotated")
