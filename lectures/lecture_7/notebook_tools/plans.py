"""Showing EXPLAIN output in lecture-07-notebook.py.

show_plan() runs an EXPLAIN, prints the plan as text (a marimo SQL cell would
show it as a one-column table with cut-off lines), and compares its SHAPE --
node names, and whether a condition is an Index Cond or a Filter, by depth --
with the reference run of lecture-07-demo.sql (PostgreSQL 18): green if it
matches, yellow with both shapes side by side if not.
"""

import re

import marimo as mo


def plan_shape(lines):
    """Node names and condition labels, by depth: the part of a plan that
    should not change between machines (unlike costs, times and buffers)."""
    shape = []
    for line in lines:
        if not line.strip() or line.strip() == "QUERY PLAN":
            continue
        depth = len(line) - len(line.lstrip())
        s = line.strip()
        if s.startswith("->"):
            s = s[2:].strip()
        m = re.match(r"^(.*?)  \((cost|actual)=", s)
        if m:
            shape.append(f"{depth:3d} {m.group(1)}")
            continue
        m = re.match(
            r"^(Index Cond|Filter|Recheck Cond|Hash Cond|Merge Cond|One-Time Filter"
            r"|Run Condition|Subplans Removed|SubPlan \d+|InitPlan \d+)\b",
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
        shape = plan_shape(lines[:head]) + ["..."] + plan_shape(lines[-tail:])
        shown = lines[:head] + [f"...   ({len(lines) - head - tail} more lines)"] + lines[-tail:]
    else:
        shape = plan_shape(lines)
        shown = lines
    plan = mo.md("```\n" + "\n".join(shown) + "\n```")
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
                    mo.md("Reference\n```\n" + "\n".join(reference) + "\n```"),
                    mo.md("Yours\n```\n" + "\n".join(shape) + "\n```"),
                ]),
            ]),
            kind="warn",
        )
    return mo.vstack([note, plan])
