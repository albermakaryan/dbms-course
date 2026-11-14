"""Diagrams for lecture-07-notebook.py (and the slide previews).

Each diagram is drawn as an SVG (1600 x 900, the dark look of Lecture 4's
deck) and saved as a PNG in lecture_7/diagrams/. The notebook calls
render_all() in one of its first cells and shows each PNG with mo.image().
Every number on a diagram is a verified output of lecture-07-demo.sql; every
diagram ends with its sources.

PNG renderer: cairosvg if it's installed, otherwise headless Chrome/Chromium.
A PNG is redrawn only when its diagram changed (hashes in diagrams/.hashes.json).

    python -m notebook_tools.diagrams      # (from lecture_7/) render them all
"""

import html
import re
import sys
from pathlib import Path

# ---- palette: Lecture 4's dark deck (lectures/lecture_4/slides/build_dark.py)
BG, SURF, SURF2, LINE = "#0E1116", "#161B22", "#1C2430", "#30363D"
FG, SOFT, FAINT = "#E6EDF3", "#A3AEBB", "#7D8793"
GREEN, AMBER, RED, BLUE, PURPLE, SKY = "#7EE787", "#F2CC60", "#FF7B72", "#79C0FF", "#D2A8FF", "#A5D6FF"
# chart series (dataviz reference palette, dark steps; validated on BG)
C_INDEX, C_SEQ = "#3987e5", "#d95926"
MONO = "'JetBrains Mono', 'DejaVu Sans Mono', Consolas, monospace"
SANS = "'IBM Plex Sans', 'Segoe UI', 'DejaVu Sans', Arial, sans-serif"
W, H = 1600, 900

_K = ["s"]  # current slide key, for unique marker ids


# ---------------------------------------------------------------- primitives
def esc(s):
    return html.escape(str(s), quote=False)


def _inline(s, base_fill):
    """**bold** -> FG semibold, `code` -> mono FG, ~~faint~~ -> FAINT."""
    out = []
    for part in re.split(r"(\*\*.+?\*\*|`.+?`|~~.+?~~)", s):
        if not part:
            continue
        if part.startswith("**"):
            out.append(f'<tspan fill="{FG}" font-weight="600">{esc(part[2:-2])}</tspan>')
        elif part.startswith("`"):
            out.append(f'<tspan fill="{FG}" font-family="{MONO}" font-size="0.92em">{esc(part[1:-1])}</tspan>')
        elif part.startswith("~~"):
            out.append(f'<tspan fill="{FAINT}">{esc(part[2:-2])}</tspan>')
        else:
            out.append(esc(part))
    return "".join(out)


def t(x, y, s, size=26, fill=SOFT, font=SANS, weight=400, anchor="start", extra=""):
    return (f'<text x="{x}" y="{y}" font-family="{font}" font-size="{size}" font-weight="{weight}" '
            f'fill="{fill}" text-anchor="{anchor}" {extra}>{_inline(s, fill)}</text>')


def tl(x, y, lines, size=26, lh=None, **kw):
    lh = lh or round(size * 1.4)
    return "".join(t(x, y + i * lh, s, size, **kw) for i, s in enumerate(lines))


def mono(x, y, s, size=24, fill=FG, **kw):
    return t(x, y, s, size, fill=fill, font=MONO, **kw)


def rect(x, y, w, h, fill=SURF, stroke=LINE, rx=10, sw=2, dash=None, extra=""):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"{d} {extra}/>'


def line(x1, y1, x2, y2, stroke=LINE, sw=2, dash=None):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{stroke}" stroke-width="{sw}"{d}/>'


_MCOL = {"faint": FAINT, "soft": SOFT, "green": GREEN, "amber": AMBER, "red": RED, "blue": BLUE, "fg": FG}


def arrow(x1, y1, x2, y2, c="faint", sw=2.5, dash=None):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    return (f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{_MCOL[c]}" stroke-width="{sw}"{d} '
            f'marker-end="url(#{_K[0]}-{c})"/>')


def path_arrow(d, c="faint", sw=2.5, dash=None):
    ds = f' stroke-dasharray="{dash}"' if dash else ""
    return f'<path d="{d}" fill="none" stroke="{_MCOL[c]}" stroke-width="{sw}"{ds} marker-end="url(#{_K[0]}-{c})"/>'


def box(x, y, w, h, title, lines=(), tc=GREEN, stroke=LINE, fill=SURF, size=22, tsize=24, pad=22):
    out = [rect(x, y, w, h, fill=fill, stroke=stroke)]
    out.append(mono(x + pad, y + pad + tsize - 4, title, tsize, fill=tc, weight=600))
    out.append(tl(x + pad, y + pad + tsize + size + 10, list(lines), size))
    return "".join(out)


def slide(key, eyebrow, title, body, source):
    _K[0] = key
    body = body() if callable(body) else body
    markers = "".join(
        f'<marker id="{key}-{n}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
        f'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{c}"/></marker>'
        for n, c in _MCOL.items()
    )
    src_lines = []
    for s_ in (source if isinstance(source, list) else [source]):
        while len(s_) > 170:
            cut = s_.rfind(" ", 0, 170)
            src_lines.append(s_[:cut])
            s_ = s_[cut + 1:]
        src_lines.append(s_)
    src = "".join(t(72, 858 + i * 22, s_, 17, fill=FAINT) for i, s_ in enumerate(src_lines))
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="100%" role="img" '
        f'aria-label="{html.escape(title)}" style="display:block;max-width:1600px;margin:4px auto;'
        f'font-variant-ligatures:none;font-feature-settings:\'liga\' 0,\'calt\' 0">'
        f"<title>{esc(title)}</title>"
        "<style>@import url('https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;600"
        "&amp;family=JetBrains+Mono:wght@400;600&amp;display=swap');</style>"
        f"<defs>{markers}</defs>"
        f'<rect width="{W}" height="{H}" rx="18" fill="{BG}"/>'
        + mono(72, 70, eyebrow, 20, fill=GREEN)
        + mono(72, 124, title, 40, fill=FG, weight=600)
        + body
        + line(72, 828, W - 72, 828, stroke=LINE, sw=1.5)
        + src
        + "</svg>"
    )


# ---------------------------------------------------------------- slides
def s_query_path():
    o = []
    xs, y, w, h, gap = 72, 200, 262, 250, 32
    stages = [
        ("SQL text", ["your query, as", "a string:", "`SELECT * FROM`", "`orders_big WHERE`", "`customerID = 4242`"], FAINT),
        ("Parser", ["checks the syntax,", "builds a query", "tree"], GREEN),
        ("Rewriter", ["applies stored", "rules, e.g. a", "view's definition"], GREEN),
        ("Planner", ["builds possible", "plans, **estimates**", "each one's cost,", "keeps the cheapest"], AMBER),
        ("Executor", ["runs the plan", "tree, reads", "**pages**, returns", "the rows"], GREEN),
    ]
    for i, (name, lines, c) in enumerate(stages):
        x = xs + i * (w + gap)
        st = AMBER if name == "Planner" else LINE
        o.append(box(x, y, w, h, name, lines, tc=c, stroke=st, size=23))
        if i:
            o.append(arrow(x - gap + 2, y + h / 2, x - 4, y + h / 2))
    px = xs + 3 * (w + gap)
    ex = xs + 4 * (w + gap)
    o.append(box(px - 40, 545, w + 40, 150, "statistics", ["`pg_class`, `pg_stats`", "(Part 3)"], tc=SOFT, size=22))
    o.append(arrow(px + w / 2 - 20, 545, px + w / 2 - 20, y + h + 6, "amber"))
    o.append(box(ex + 10, 545, w - 10, 150, "pages", ["`shared_buffers`, OS", "cache, disk (1.7)"], tc=SOFT, size=22))
    o.append(arrow(ex + w / 2 + 5, 545, ex + w / 2 + 5, y + h + 6))
    o.append(rect(72, 545, 840, 150, fill=SURF2, stroke=SURF2))
    o.append(tl(100, 600, ["`EXPLAIN` shows the plan the planner chose, with its estimates.",
                           "`EXPLAIN ANALYZE` also runs the executor and shows what",
                           "really happened, node by node."], 25))
    o.append(t(72, 772, "The planner never runs the query to decide: it predicts from statistics. "
                        "**Wrong statistics, wrong plan.**", 26))
    return "".join(o)


def s_plan_tree():
    o = []
    nodes = [  # label, detail, rows out
        ("Sort", "ORDER BY orders DESC", "3 rows"),
        ("GroupAggregate", "one row per status", "3 rows"),
        ("Sort", "by status", "97 rows"),
        ("Seq Scan on orders_big", "Filter: customerid = 4242 · 59,739 pages", "97 rows"),
    ]
    x0, y0, w, h, step = 72, 175, 640, 112, 152
    for i, (name, det, rows) in enumerate(nodes):
        x = x0 + i * 46
        y = y0 + i * step
        st = AMBER if i == 3 else LINE
        o.append(rect(x, y, w, h, stroke=st))
        o.append(mono(x + 24, y + 44, name, 26, fill=GREEN if i < 3 else AMBER, weight=600))
        o.append(t(x + 24, y + 84, det, 22))
        if i:
            ax = x + 60
            o.append(arrow(ax, y - 4, ax, y - step + h + 6, "blue"))
            o.append(mono(ax + 16, y - 14, rows, 21, fill=BLUE))
    o.append(mono(x0 + 3 * 46 + 60 + 16, y0 + 3 * step + h + 34, "5,000,000 rows read, 4,999,903 removed", 21, fill=FAINT))
    rx = 900
    o.append(t(rx, 210, "**Read it from the bottom up.**", 28, fill=FG))
    o.append(tl(rx, 260, [
        "The most indented node runs first and",
        "hands its rows to the node above it.",
    ], 25))
    o.append(t(rx, 360, "**Each arrow is a stream of rows.**", 28, fill=FG))
    o.append(tl(rx, 410, [
        "97 rows leave the scan; the aggregate",
        "turns them into 3 groups; the top Sort",
        "orders those 3.",
    ], 25))
    o.append(t(rx, 545, "**A node's cost and time include**", 28, fill=FG))
    o.append(t(rx, 583, "**its children's.**", 28, fill=FG))
    o.append(tl(rx, 633, [
        "Almost all of this query's time is the",
        "scan at the bottom: the place to look.",
    ], 25))
    return "".join(o)


def s_cache():
    o = []
    tiers = [
        ("shared_buffers", "PostgreSQL's own cache · 128 MB (default)", "shared hit", GREEN),
        ("OS page cache", "the rest of the machine's free RAM", "shared read", AMBER),
        ("disk", "NVMe on the reference laptop", "shared read", AMBER),
    ]
    x, w, h = 72, 760, 128
    for i, (name, det, label, c) in enumerate(tiers):
        y = 180 + i * 190
        o.append(rect(x, y, w, h))
        o.append(mono(x + 26, y + 50, name, 28, fill=FG, weight=600))
        o.append(t(x + 26, y + 92, det, 23))
        o.append(rect(x + w + 30, y + 34, 250, 60, fill=SURF2, stroke=c))
        o.append(mono(x + w + 155, y + 73, label, 23, fill=c, anchor="middle"))
        if i:
            o.append(arrow(x + 120, y - 4, x + 120, y - 190 + h + 6, "soft"))
    o.append(t(x + 140, 352, "on a miss, the page is copied up", 21, fill=FAINT))
    o.append(t(x + 140, 542, "on a miss, the page is copied up", 21, fill=FAINT))
    rx = 1150
    o.append(t(rx, 205, "**Buffers count pages,**", 27, fill=FG))
    o.append(t(rx, 243, "**not milliseconds.**", 27, fill=FG))
    o.append(tl(rx, 290, ["`read` only says \"not in", "PostgreSQL's cache\": the", "OS cache or the disk."], 24))
    o.append(t(rx, 440, "**1.7, run 1:** `read=150`", 24))
    o.append(t(rx, 478, "**runs 2 and 3:** `hit=150`", 24))
    o.append(tl(rx, 545, ["A `Seq Scan` of a table over", "¼ of `shared_buffers` uses a", "256 kB ring: `orders_big`", "shows `read` every time."], 24))
    return "".join(o)


def s_storage():
    o = []
    # level 1: the file as a row of pages
    o.append(mono(72, 190, "base/16384/16561", 24, fill=AMBER))
    o.append(t(330, 190, "the file of `orders_big` · 467 MB · 59,739 pages of 8 kB", 24))
    x, y, pw = 72, 214, 108
    labels = ["0", "1", "2", "3", "4", "…", "58,425", "…", "59,738"]
    for i, lab in enumerate(labels):
        px = x + i * (pw + 10)
        if lab == "…":
            o.append(mono(px + pw / 2, y + 44, "…", 26, fill=FAINT, anchor="middle"))
            continue
        st = AMBER if lab == "0" else LINE
        o.append(rect(px, y, pw, 66, stroke=st, rx=6))
        o.append(mono(px + pw / 2, y + 42, lab, 20, fill=FG if lab == "0" else SOFT, anchor="middle"))
    o.append(t(1170, 248, "page 58,425 slot 79:", 22))
    o.append(t(1170, 278, "Nane's order 4890168", 22))
    # level 2: page 0 zoomed
    y2 = 360
    o.append(t(72, y2 - 18, "**page 0**, 8,192 bytes, filled from both ends", 24))
    segs = [  # x0, x1 in canvas, label, fill, stroke
        (72, 200, "header", SURF2, LINE),
        (200, 470, "slots 1 … 84", SURF2, BLUE),
        (470, 560, "free", BG, LINE),
        (560, 1528, "rows 84 … 1   (row 1 is at the very end)", SURF, GREEN),
    ]
    for a, b, lab, f, s in segs:
        o.append(rect(a, y2, b - a, 80, fill=f, stroke=s, rx=4))
        o.append(t((a + b) / 2, y2 + 49, lab, 22, fill=FG, anchor="middle"))
    for xx, lab, anc in [(72, "0", "start"), (200, "24", "middle"), (466, "lower = 360", "end"),
                         (564, "408 = upper", "start"), (1528, "8192", "end")]:
        o.append(mono(xx, y2 + 112, lab, 19, fill=FAINT, anchor=anc))
    o.append(path_arrow("M 240 440 C 260 520, 1440 520, 1460 444", "blue", sw=2))
    o.append(t(850, 520, "slot 1 → byte 8104: the address (0,1) is page 0, slot 1", 21, fill=BLUE, anchor="middle"))
    # level 3: row 1 zoomed
    y3 = 590
    o.append(t(72, y3 - 16, "**row 1** = order 1: a header, then the columns, side by side", 24))
    cols = [("header", "32 B", 150), ("orderid", "01000000", 175), ("customerid", "1b910000", 200),
            ("employeeid", "01000000", 200), ("orderdate", "d1200000", 190), ("…", "", 70),
            ("status", "13 'returned'", 250), ("deliverydate, rating", "NULL: 0 bytes", 210)]
    xx = 72
    for name, val, wd in cols:
        st = AMBER if name == "orderdate" else LINE
        o.append(rect(xx, y3, wd - 8, 92, fill=SURF if name != "header" else SURF2, stroke=st, rx=4))
        o.append(t(xx + (wd - 8) / 2, y3 + 36, name, 19, fill=SOFT, anchor="middle"))
        if val:
            o.append(mono(xx + (wd - 8) / 2, y3 + 72, val, 20, fill=FG, anchor="middle"))
        xx += wd
    o.append(t(72, 742, "`d1200000` = 0x20d1 = 8,401 days after 2000-01-01 = **2023-01-01**. "
                        "Bytes are stored lowest first.", 23))
    o.append(t(72, 790, "PostgreSQL reads and writes **whole pages**: one row costs one 8 kB page.", 25, fill=FG))
    return "".join(o)


def s_row_vs_col():
    o = []
    cols = ["orderid", "customerid", "orderdate", "status", "…", "ordertotal"]
    cw = [86, 86, 86, 86, 40, 86]
    # left: row store
    o.append(t(72, 190, "**Row store** (PostgreSQL): a page holds whole rows", 25, fill=FG))
    x0, y0 = 72, 215
    for p in range(3):
        py = y0 + p * 150
        o.append(rect(x0, py, 560, 128, fill=BG, stroke=LINE, rx=6))
        o.append(mono(x0 + 10, py + 22, f"page {p}", 16, fill=FAINT))
        for r in range(3):
            ry = py + 32 + r * 31
            xx = x0 + 14
            for c, w in zip(cols, cw):
                hit = c == "ordertotal"
                o.append(rect(xx, ry, w - 6, 24, fill=C_INDEX if hit else SURF2, stroke="none", rx=3))
                xx += w
    o.append(t(72, 690, "`sum(orderTotal)`: the totals are on **every** page,", 24))
    o.append(t(72, 726, "so it read all **59,739 pages, 467 MB** (2.7).", 24))
    # right: column store
    rx = 860
    o.append(t(rx, 190, "**Column store** (Parquet, DuckDB): one column, together", 25, fill=FG))
    for i, (c, w) in enumerate(zip(["orderid", "customerid", "orderdate", "status", "ordertotal"], range(5))):
        yy = 215 + i * 92
        hit = c == "ordertotal"
        o.append(mono(rx, yy + 44, c, 20, fill=FG if hit else SOFT))
        for k in range(8):
            o.append(rect(rx + 170 + k * 62, yy + 18, 54, 40, fill=C_INDEX if hit else SURF2, stroke="none", rx=3))
    o.append(t(rx, 690, "`sum(orderTotal)` reads only that column: the", 24))
    o.append(t(rx, 726, "values themselves are about **33 MB** here.", 24))
    o.append(t(72, 790, "Right for \"show me order 4890168\" (one page, all columns), wrong for \"sum one column\". "
                        "**Next lectures.**", 24, fill=SOFT))
    return "".join(o)


def s_mvcc():
    o = []
    states = [
        ("after INSERT", [("1", "Nane  120.50", "A", "0", ""), ("2", "Aram   75.00", "A", "0", ""),
                          ("3", "Ani     9.99", "A", "0", "")]),
        ("after UPDATE Nane, DELETE Ani", [("1", "Nane  120.50", "A", "B", "→ (0,4)"), ("2", "Aram   75.00", "A", "0", ""),
                                            ("3", "Ani     9.99", "A", "C", ""), ("4", "Nane  130.00", "B", "0", "")]),
        ("after VACUUM", [("1", "→ slot 4", "", "", ""), ("2", "Aram   75.00", "A", "0", ""),
                          ("3", "free", "", "", ""), ("4", "Nane  130.00", "B", "0", "")]),
    ]
    for si, (title, rows) in enumerate(states):
        x = 72 + si * 496
        o.append(mono(x, 190, title, 22, fill=GREEN, weight=600))
        o.append(t(x + 12, 230, "slot", 18, fill=FAINT))
        o.append(t(x + 80, 230, "row", 18, fill=FAINT))
        o.append(t(x + 236, 230, "xmin", 18, fill=FAINT))
        o.append(t(x + 300, 230, "xmax", 18, fill=FAINT))
        for ri, (slot, val, xmin, xmax, ctid) in enumerate(rows):
            y = 245 + ri * 84
            dead = xmax not in ("", "0")
            fill = SURF if not dead else "#1F1215"
            st = RED if dead else (GREEN if (si and slot == "4") else LINE)
            if val in ("free", "→ slot 4"):
                st, fill = LINE, BG
            o.append(rect(x, y, 456, 70, fill=fill, stroke=st, rx=6, dash="6 5" if val in ("free", "→ slot 4") else None))
            o.append(mono(x + 26, y + 44, slot, 22, fill=FAINT))
            o.append(mono(x + 78, y + 44, val, 22, fill=FG if not dead else SOFT))
            o.append(mono(x + 248, y + 44, xmin, 22, fill=SOFT))
            o.append(mono(x + 312, y + 44, xmax, 22, fill=RED if dead else SOFT))
            if ctid:
                o.append(mono(x + 440, y + 44, ctid, 19, fill=RED, anchor="end"))
        if si < 2:
            o.append(arrow(x + 462, 420, x + 490, 420, "soft"))
    o.append(t(72, 640, "A, B, C = transactions. **UPDATE never overwrites**: it writes a new version (slot 4) "
                        "and stamps the old one", 24))
    o.append(t(72, 676, "with its own number (xmax). **DELETE only stamps.** A query that started before B "
                        "committed still sees 120.50.", 24))
    o.append(t(72, 736, "Dead versions take space and are still read by scans **until VACUUM** frees them. "
                        "The file doesn't shrink:", 24))
    o.append(t(72, 772, "2.9 deleted 90% of a copy of 2023 and it stayed **128 MB**, until `VACUUM FULL` "
                        "rewrote it: **51 MB**.", 24))
    return "".join(o)


def s_stats():
    o = []
    o.append(box(72, 190, 300, 170, "orders_big", ["5,000,000 rows", "59,739 pages"], tc=FG, size=23))
    o.append(arrow(378, 275, 448, 275))
    o.append(box(454, 190, 330, 170, "ANALYZE", ["a random sample:", "**30,000 rows**", "(300 × target 100)"], tc=AMBER,
                 stroke=AMBER, size=23))
    o.append(arrow(790, 245, 860, 225))
    o.append(arrow(790, 305, 860, 330))
    o.append(box(866, 165, 662, 115, "pg_class", ["`reltuples` about 5,000,083 · `relpages` 59,739"], tc=GREEN, size=22))
    o.append(box(866, 296, 662, 175, "pg_stats  (per column)", [
        "`n_distinct`, most common values and their",
        "frequencies, a histogram, `correlation` with",
        "the order on disk"], tc=GREEN, size=22))
    o.append(t(72, 540, "**The estimate is arithmetic:**", 27, fill=FG))
    o.append(mono(72, 592, "status = 'cancelled'", 25, fill=FG))
    o.append(t(420, 592, "frequency 0.0332 in the sample × 5,000,083 rows = **about 166,003**", 25))
    o.append(t(420, 632, "actual: 159,902 (3.2). Close, so the plan is chosen on true numbers.", 25))
    o.append(rect(72, 676, 1456, 120, fill="#1F1215", stroke="#5A2A2A"))
    o.append(t(100, 724, "**Stale statistics (3.3):** 200,000 January orders loaded, no `ANALYZE`. The statistics end "
                         "on 2025-12-31,", 24))
    o.append(t(100, 762, "so the estimate was **476 rows**: a nested loop with 200,000 lookups and a sort on disk. "
                         "No error.", 24))
    return "".join(o)


def s_scans():
    o = []
    panels = [
        ("Seq Scan", "read every page, in order", "most of the table"),
        ("Index Scan", "index → each row's page", "few rows"),
        ("Bitmap Heap Scan", "index → list of pages → read in order", "more rows, spread out"),
        ("Index Only Scan", "answer from the index alone", "every column needed is in it"),
    ]
    for i, (name, how, when) in enumerate(panels):
        cx = 72 + (i % 2) * 740
        cy = 165 + (i // 2) * 315
        o.append(rect(cx, cy, 716, 295, fill=SURF))
        o.append(mono(cx + 24, cy + 44, name, 26, fill=GREEN, weight=600))
        o.append(t(cx + 24, cy + 82, how, 22))
        o.append(t(cx + 24, cy + 272, f"chosen for: **{when}**", 22))
        # index strip (left) and table pages (right)
        ix, iy = cx + 24, cy + 110
        has_index = name != "Seq Scan"
        if has_index:
            o.append(rect(ix, iy, 130, 128, fill=SURF2, stroke=BLUE, rx=6))
            o.append(mono(ix + 65, iy + 26, "index", 17, fill=BLUE, anchor="middle"))
            for k in range(4):
                o.append(rect(ix + 14, iy + 38 + k * 21, 102, 14, fill=LINE, stroke="none", rx=2))
        px0, py0 = cx + 200, cy + 112
        reads = {"Seq Scan": set(range(16)), "Index Scan": {2, 9, 13}, "Bitmap Heap Scan": {1, 2, 5, 9, 10, 13},
                 "Index Only Scan": set()}[name]
        for k in range(16):
            x = px0 + (k % 8) * 60
            y = py0 + (k // 8) * 64
            hit = k in reads
            o.append(rect(x, y, 50, 52, fill=C_SEQ if (hit and name == "Seq Scan") else (C_INDEX if hit else BG),
                          stroke=LINE, rx=4))
        o.append(t(px0 + 470, py0 - 10, "table pages", 17, fill=FAINT, anchor="end"))
        if name == "Index Scan":
            for k, kk in zip((0, 1, 3), (2, 9, 13)):
                tx = px0 + (kk % 8) * 60 + 25
                ty = py0 + (kk // 8) * 64 + 26
                o.append(path_arrow(f"M {ix + 118} {iy + 45 + k * 21} L {tx - 27} {ty}", "blue", sw=2))
        if name == "Bitmap Heap Scan":
            o.append(arrow(ix + 130, iy + 64, px0 - 8, iy + 64, "blue", sw=2))
        if name == "Index Only Scan":
            o.append(rect(px0 + 150, py0 + 40, 172, 44, fill=SURF, stroke="none", rx=6))
            o.append(mono(px0 + 236, py0 + 70, "not read", 22, fill=SOFT, anchor="middle"))
    return "".join(o)


def s_selectivity():
    """Pages read vs share of the table needed: measured in Part 4 (4.1-4.3)."""
    o = []
    X0, X1, Y0, Y1 = 230, 1060, 730, 210  # plot box: x left/right, y bottom/top
    import math
    def xp(frac):  # log scale 0.0005 .. 1
        lo, hi = math.log10(0.0005), math.log10(1.0)
        return X0 + (math.log10(frac) - lo) / (hi - lo) * (X1 - X0)
    def yp(pages):
        return Y0 - pages / 70000 * (Y0 - Y1)
    for pg in (0, 20000, 40000, 60000):
        y = yp(pg)
        o.append(line(X0, y, X1, y, stroke=SURF2, sw=1.5))
        o.append(mono(X0 - 16, y + 7, f"{pg:,}", 18, fill=FAINT, anchor="end"))
    for frac, lab in ((0.001, "0.1%"), (0.01, "1%"), (0.1, "10%"), (1.0, "100%")):
        x = xp(frac)
        o.append(line(x, Y0, x, Y0 + 8, stroke=FAINT, sw=1.5))
        o.append(mono(x, Y0 + 34, lab, 18, fill=FAINT, anchor="middle"))
    o.append(line(X0, Y0, X1, Y0, stroke=FAINT, sw=1.5))
    o.append(t((X0 + X1) / 2, Y0 + 66, "share of the table's rows the query needs (log scale)", 20, fill=SOFT, anchor="middle"))
    o.append(t(X0 - 150, Y1 - 24, "pages read", 20, fill=SOFT))
    # Seq Scan: always the whole table
    ys = yp(59739)
    o.append(f'<line x1="{X0}" y1="{ys}" x2="{X1}" y2="{ys}" stroke="{C_SEQ}" stroke-width="2"/>')
    # through the index: measured points
    pts = [(5180 / 5e6, 70, "one day: 70 pages", "Index Scan, 4.1"),
           (159902 / 5e6, 55953, "cancelled: 55,953 pages", "Bitmap Heap Scan, 4.2"),
           (4600224 / 5e6, 63674, "completed: 63,674 pages", "forced through the index, 4.3")]
    d = " ".join(f"{'M' if i == 0 else 'L'} {xp(f):.1f} {yp(p):.1f}" for i, (f, p, *_r) in enumerate(pts))
    o.append(f'<path d="{d}" fill="none" stroke="{C_INDEX}" stroke-width="2"/>')
    for f, p, lab, sub in pts:
        x, y = xp(f), yp(p)
        o.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="7" fill="{C_INDEX}" stroke="{BG}" stroke-width="2">'
                 f"<title>{esc(lab)} ({esc(sub)}; {f * 100:.1f}% of the rows)</title></circle>")
    # direct labels, in ink colours
    o.append(t(xp(5180 / 5e6) + 56, yp(70) - 12, "one day (0.1%): **70 pages**", 21))
    o.append(t(xp(159902 / 5e6) + 18, yp(55953) + 40, "cancelled (3.2%): **55,953**", 21))
    o.append(t(xp(4600224 / 5e6) - 14, yp(63674) - 18, "completed (92%): **63,674**", 21, anchor="end"))
    o.append(t(X0 + 12, ys - 14, "Seq Scan: always 59,739", 21))
    # legend
    lx, ly = X0 + 12, Y1 + 6
    o.append(f'<line x1="{lx}" y1="{ly}" x2="{lx + 36}" y2="{ly}" stroke="{C_SEQ}" stroke-width="2"/>')
    o.append(t(lx + 46, ly + 7, "Seq Scan", 19))
    o.append(f'<line x1="{lx + 170}" y1="{ly}" x2="{lx + 206}" y2="{ly}" stroke="{C_INDEX}" stroke-width="2"/>')
    o.append(f'<circle cx="{lx + 188}" cy="{ly}" r="6" fill="{C_INDEX}"/>')
    o.append(t(lx + 216, ly + 7, "through the index (measured)", 19))
    # takeaways
    rx = 1120
    o.append(t(rx, 230, "**Count pages, not rows.**", 27, fill=FG))
    o.append(tl(rx, 280, ["3.2% of the rows sat on", "**93% of the pages** (55,814", "of 59,739): the index saved", "almost nothing."], 24))
    o.append(tl(rx, 450, ["At 92%, the index reads more", "pages than the whole table.", "The planner's `Seq Scan` was", "right."], 24))
    o.append(tl(rx, 620, ["One day's rows sit together", "(correlation 1): 5,180 rows", "on a few dozen pages."], 24))
    return "".join(o)


def s_btree():
    o = []
    # root
    o.append(rect(640, 170, 320, 70, stroke=AMBER))
    o.append(mono(800, 214, "root · 48 entries", 22, fill=AMBER, anchor="middle"))
    # internal
    ints = [(260, "…"), (640, "…"), (1020, "…")]
    for x, lab in ints:
        o.append(rect(x, 300, 320, 64, stroke=LINE))
        o.append(mono(x + 160, 341, lab, 20, fill=SOFT, anchor="middle"))
        o.append(line(800, 240, x + 160, 300, stroke=FAINT, sw=2))
    # leaves
    leaves = ["1 … 366", "367 …", "…", "4890168 → (58425,79)", "…", "… 5,000,000"]
    lw = 232
    for i, lab in enumerate(leaves):
        x = 72 + i * (lw + 13)
        hit = "4890168" in lab
        o.append(rect(x, 430, lw, 70, stroke=BLUE if hit else LINE))
        o.append(mono(x + lw / 2, 473, lab, 18 if hit else 20, fill=FG if hit else SOFT, anchor="middle"))
        if i < len(leaves) - 1:
            o.append(arrow(x + lw + 1, 465, x + lw + 12, 465, "soft", sw=1.5))
    for i in (0, 3, 5):
        x = 72 + i * (lw + 13) + lw / 2
        src = {0: 420, 3: 800, 5: 1180}[i]
        o.append(line(src, 364, x, 430, stroke=FAINT, sw=2))
    o.append(path_arrow("M 800 240 L 800 300", "blue", sw=3))
    o.append(path_arrow(f"M 800 364 L {72 + 3 * (lw + 13) + lw / 2} 430", "blue", sw=3))
    # heap page
    hx = 72 + 3 * (lw + 13) + 20
    o.append(rect(hx, 570, 200, 70, stroke=GREEN))
    o.append(mono(hx + 100, 613, "page 58,425", 20, fill=GREEN, anchor="middle"))
    o.append(path_arrow(f"M {hx + 100} 500 L {hx + 100} 566", "blue", sw=3))
    o.append(t(72, 610, "`orderID = 4890168`: root → internal → leaf → table page", 24))
    o.append(t(72, 648, "= **4 pages** (`Buffers` hit + read), out of 13,712 index pages.", 24))
    o.append(t(72, 718, "Leaves are sorted and linked, so a range or `ORDER BY ... LIMIT` just walks along them (5.5).", 24))
    o.append(t(72, 764, "**The bill:** every INSERT updates every index. 1,000,000 rows took **2.6×** as long with one "
                        "index, **8.5×** with five (5.4).", 24))
    return "".join(o)


def s_composite():
    o = []
    o.append(t(72, 186, "Index on **(customerID, orderDate)**: sorted by customer first, then by date, like a phone "
                        "book by surname, then name.", 24))
    rows = [("4241", "2025-12-18"), ("4242", "2023-01-25"), ("4242", "2023-01-26"), ("4242", "2023-02-16"),
            ("4242", "…"), ("4242", "2025-11-20"), ("4242", "2025-12-11"), ("4243", "2023-01-08"),
            ("…", "…"), ("10016", "2025-12-01"), ("…", "…"), ("10019", "2025-12-01"), ("…", "…")]
    x0, y0, rh = 72, 220, 41
    o.append(mono(x0 + 20, y0 + 26, "customerid", 18, fill=FAINT))
    o.append(mono(x0 + 200, y0 + 26, "orderdate", 18, fill=FAINT))
    for i, (c, d) in enumerate(rows):
        y = y0 + 38 + i * rh
        nane = c == "4242"
        day = d == "2025-12-01"
        fill = "#13263B" if nane else ("#2A1A12" if day else SURF)
        st = C_INDEX if nane else (C_SEQ if day else LINE)
        o.append(rect(x0, y, 400, rh - 6, fill=fill, stroke=st, rx=4, sw=1.5))
        o.append(mono(x0 + 20, y + 25, c, 19, fill=FG if (nane or day) else SOFT))
        o.append(mono(x0 + 200, y + 25, d, 19, fill=FG if (nane or day) else SOFT))
    rx = 560
    o.append(rect(rx, 250, 968, 200, stroke=C_INDEX))
    o.append(mono(rx + 26, 296, "WHERE customerID = 4242 [AND orderDate >= ...]", 23, fill=FG))
    o.append(tl(rx + 26, 346, ["Nane's entries are **one block**, already in date order:",
                               "the search jumps to it and reads **3 index pages**",
                               "(`Index Cond` on one column or both)."], 24))
    o.append(rect(rx, 480, 968, 200, stroke=C_SEQ))
    o.append(mono(rx + 26, 526, "WHERE orderDate = '2025-12-01'", 23, fill=FG))
    o.append(tl(rx + 26, 576, ["One day's entries are **scattered**, one small group",
                               "inside each customer's block: the plan still names the",
                               "index, but reads **all 13,539 pages** of it."], 24))
    o.append(t(rx, 740, "**Leftmost column first.** Put the column you filter by alone in front (6.1).", 25, fill=FG))
    return "".join(o)


def s_function():
    o = []
    o.append(t(72, 186, "The index on **orderDate** is a sorted list. A month is one slice of it:", 25))
    days = ["2025-05-30", "2025-05-31", "2025-06-01", "2025-06-02", "…", "2025-06-29", "2025-06-30", "2025-07-01"]
    x0 = 72
    for i, d in enumerate(days):
        x = x0 + i * 182
        june = d.startswith("2025-06") or d == "…"
        o.append(rect(x, 214, 170, 58, fill="#13263B" if june else SURF, stroke=C_INDEX if june else LINE, rx=5))
        o.append(mono(x + 85, 251, d, 19, fill=FG if june else SOFT, anchor="middle"))
    o.append(rect(72, 330, 700, 300, stroke=C_INDEX))
    o.append(mono(96, 376, "WHERE orderDate >= '2025-06-01'", 22, fill=FG))
    o.append(mono(96, 410, "  AND orderDate <  '2025-07-01'", 22, fill=FG))
    o.append(tl(96, 466, ["A range on the column itself: the planner", "finds the slice's two ends in the index.",
                          "`Index Cond`, **1,995 pages**."], 24))
    o.append(rect(828, 330, 700, 300, stroke=C_SEQ))
    o.append(mono(852, 376, "WHERE date_trunc('month', orderDate)", 22, fill=FG))
    o.append(mono(852, 410, "      = '2025-06-01'", 22, fill=FG))
    o.append(tl(852, 466, ["The index is sorted by `orderDate`, not by", "`date_trunc(...)` of it: no slice to find.",
                           "Compute it for every row: `Seq Scan`,", "**59,739 pages**, estimate 25,001 for 155,419."],
                24))
    o.append(t(72, 700, "Same 155,419 rows, same revenue. Any function, cast or arithmetic **on the column** hides "
                        "it from the index:", 24))
    o.append(t(72, 740, "`date_trunc`, `extract`, `lower(email)`, `customerID::numeric`, `orderDate + 7`. "
                        "**Put the work on the value side** (7.1, 7.2).", 24))
    return "".join(o)


def s_joins():
    o = []
    pw = 470
    panels = [
        ("Nested Loop", ["for each outer row,", "look up the inner side", "(through an index)"],
         "10 orders × a `customers_big` primary-key lookup (`loops=10`)", "few outer rows, an index inside"),
        ("Hash Join", ["build a hash table from", "one side once, then", "probe it with the other"],
         "hash 50,000 customers, probe 159,902 cancelled orders", "many rows, no useful order"),
        ("Merge Join", ["walk two inputs sorted", "on the key side by side,", "like a zipper"],
         "customers in key order × counts from the `customerID` index", "both sides already sorted"),
    ]
    for i, (name, how, demo, when) in enumerate(panels):
        x = 72 + i * (pw + 23)
        o.append(rect(x, 165, pw, 590))
        o.append(mono(x + 24, 210, name, 27, fill=GREEN, weight=600))
        o.append(tl(x + 24, 256, how, 23))
        # mini diagrams
        dy = 380
        if i == 0:
            for k in range(4):
                o.append(rect(x + 30, dy + k * 48, 120, 36, fill=SURF2, stroke="none", rx=4))
                o.append(path_arrow(f"M {x + 156} {dy + 18 + k * 48} L {x + 290} {dy + 70}", "blue", sw=1.8))
            o.append(rect(x + 296, dy + 30, 140, 90, fill=SURF2, stroke=BLUE, rx=6))
            o.append(mono(x + 366, dy + 82, "index", 19, fill=BLUE, anchor="middle"))
        elif i == 1:
            o.append(rect(x + 30, dy, 180, 180, fill=SURF2, stroke=AMBER, rx=6))
            o.append(mono(x + 120, dy + 98, "hash table", 19, fill=AMBER, anchor="middle"))
            for k in range(4):
                o.append(rect(x + 300, dy + k * 48, 130, 36, fill=SURF2, stroke="none", rx=4))
                o.append(arrow(x + 296, dy + 18 + k * 48, x + 216, dy + 90, "amber", sw=1.8))
        else:
            for k in range(4):
                o.append(rect(x + 40, dy + k * 48, 140, 36, fill=SURF2, stroke="none", rx=4))
                o.append(mono(x + 110, dy + 25 + k * 48, str(k + 1), 18, fill=SOFT, anchor="middle"))
                o.append(rect(x + 290, dy + k * 48, 140, 36, fill=SURF2, stroke="none", rx=4))
                o.append(mono(x + 360, dy + 25 + k * 48, str(k + 1), 18, fill=SOFT, anchor="middle"))
                o.append(line(x + 184, dy + 18 + k * 48, x + 286, dy + 18 + k * 48, stroke=GREEN, sw=2))
        o.append(t(x + 24, 640, f"chosen for: **{when}**", 21))
        words, lines_, cur = demo.split(), [], ""
        for w_ in words:
            if len(cur) + len(w_) > 33:
                lines_.append(cur)
                cur = w_
            else:
                cur = (cur + " " + w_).strip()
        lines_.append(cur)
        o.append(tl(x + 24, 690, ["~~demo (8.5):~~ " + lines_[0]] + lines_[1:], 19, lh=27))
    o.append(t(72, 802, "You don't choose; the planner does, from the **row estimates**. Read which one it picked, "
                        "and check its estimates.", 22, fill=SOFT))
    return "".join(o)


def s_partition():
    o = []
    o.append(rect(560, 165, 480, 92, stroke=AMBER))
    o.append(mono(800, 205, "orders_big_part", 26, fill=AMBER, anchor="middle", weight=600))
    o.append(t(800, 240, "one table to your queries, no rows of its own", 20, anchor="middle"))
    parts = [("2023", "1,371,464 rows"), ("2024", "1,733,359 rows"), ("2025", "1,895,177 rows"), ("DEFAULT", "optional")]
    for i, (y, rows) in enumerate(parts):
        x = 72 + i * 372
        st = GREEN if y == "2025" else LINE
        o.append(rect(x, 330, 340, 110, stroke=st, dash="7 6" if y == "DEFAULT" else None))
        o.append(mono(x + 170, 375, "orders_big_part_" + y.lower() if y != "DEFAULT" else "…_default", 20,
                      fill=GREEN if y == "2025" else FG, anchor="middle"))
        o.append(t(x + 170, 415, rows, 21, anchor="middle"))
        o.append(line(800, 257, x + 170, 330, stroke=FAINT, sw=2))
    o.append(rect(72, 490, 700, 200, stroke=GREEN))
    o.append(mono(96, 534, "WHERE orderDate >= '2025-06-01'", 21, fill=FG))
    o.append(mono(96, 566, "  AND orderDate <  '2025-07-01'", 21, fill=FG))
    o.append(tl(96, 616, ["**Pruning:** only the 2025 partition is read;", "the plan doesn't even list the others (9.3)."], 23))
    o.append(rect(828, 490, 700, 200, stroke=RED))
    o.append(mono(852, 534, "WHERE extract(year FROM orderDate)", 21, fill=FG))
    o.append(mono(852, 566, "      = 2025", 21, fill=FG))
    o.append(tl(852, 616, ["Not a filter on the key itself: **all three**", "partitions are read (9.4). Same trap as 7.1."],
                23))
    o.append(t(72, 750, "**What it buys:** dropping a year is `DROP TABLE` of one partition, 16 ms, instead of "
                        "deleting 1.37 million rows, 609 ms", 23))
    o.append(t(72, 786, "(medians, 9.8), with no dead rows left behind (2.9). **What it costs:** unique keys must "
                        "include `orderDate` (9.6).", 23))
    return "".join(o)


def s_decision():
    o = []
    def q(x, y, w, s):  # question box
        return rect(x, y, w, 76, fill=SURF2, stroke=AMBER) + t(x + w / 2, y + 48, s, 23, fill=FG, anchor="middle")
    def a(x, y, w, s, c=GREEN, s2=None):  # answer box
        out = rect(x, y, w, 76 if not s2 else 96, fill=SURF, stroke=c) + t(x + 20, y + 46, s, 22, fill=FG)
        if s2:
            out += t(x + 20, y + 80, s2, 19, fill=SOFT)
        return out
    o.append(rect(72, 160, 400, 76, fill=SURF, stroke=LINE) + t(272, 208, "**Slow? Read the plan first.**", 23, anchor="middle"))
    o.append(arrow(472, 198, 548, 198))
    o.append(q(554, 160, 470, "Estimated vs actual off by 10× or more?"))
    o.append(arrow(1024, 198, 1100, 198, "green"))
    o.append(t(1062, 186, "yes", 19, fill=GREEN, anchor="middle"))
    o.append(a(1106, 160, 422, "`ANALYZE`, or rewrite the query", s2="range not function, right literal type"))
    o.append(arrow(789, 236, 789, 300))
    o.append(t(806, 278, "no", 19, fill=FAINT))
    o.append(q(554, 306, 470, "Small share of a big table?"))
    o.append(arrow(1024, 344, 1100, 344, "green"))
    o.append(t(1062, 332, "yes", 19, fill=GREEN, anchor="middle"))
    o.append(a(1106, 296, 422, "**Index**, shaped to the query", s2="leftmost first · partial · INCLUDE"))
    o.append(arrow(789, 382, 789, 446))
    o.append(t(806, 424, "no", 19, fill=FAINT))
    o.append(q(554, 452, 470, "Huge, time-based, drop old periods?"))
    o.append(arrow(1024, 490, 1100, 490, "green"))
    o.append(t(1062, 478, "yes", 19, fill=GREEN, anchor="middle"))
    o.append(a(1106, 442, 422, "**Partition** by the time column", s2="queries must filter on the key"))
    o.append(arrow(789, 528, 789, 592))
    o.append(t(806, 570, "no", 19, fill=FAINT))
    o.append(a(554, 598, 470, "**Neither.** A Seq Scan is right here.", c=LINE))
    o.append(t(72, 330, "**The bill:**", 22))
    o.append(tl(72, 366, ["every index costs disk and", "slows every write: 2.6× for", "one, 8.5× for five (5.4)."], 21))
    o.append(rect(72, 718, 1456, 80, fill=SURF2, stroke=SURF2))
    o.append(t(100, 768, "**After any change:** same counts, `EXCEPT ALL` both ways = 0, then three runs, "
                         "comparing plans and buffers.", 23, fill=SOFT))
    return "".join(o)


# The slides the notebook shows (the others stay here for a deck).
IN_NOTEBOOK = {"plan-tree", "storage", "mvcc", "stats", "selectivity", "btree", "composite", "function",
               "partition", "decision"}

DOCS = "https://www.postgresql.org/docs/18/"
SLIDES = [
    # (insert before the notebook heading starting with ..., key, eyebrow, title, body, sources)
    ("### 1.1 ", "query-path", "-- part 1 · reading a plan", "From SQL text to rows", s_query_path,
     [f"PostgreSQL 18 docs, The Path of a Query ({DOCS}query-path.html): parser, rewrite system, planner/optimizer,"
      " executor; Planner/Optimizer (planner-optimizer.html)."]),
    ("### 1.6 ", "plan-tree", "-- 1.5 · read a plan inside out", "A plan is a tree; rows flow up", s_plan_tree,
     ["Demo 1.3-1.5 (PostgreSQL 18.6). Docs, Using EXPLAIN: \"the cost of an upper-level node includes the cost"
      " of all its child nodes\" (using-explain.html)."]),
    ("### 1.7 ", "cache", "-- 1.7 · cold and warm", "Where a page comes from", s_cache,
     ["Demo 1.7. Docs, Resource Consumption: shared_buffers default 128MB (runtime-config-resource.html);"
      " src/backend/storage/buffer/README: \"For sequential scans, a 256KB ring is used.\""]),
    ("### 2.1 ", "storage", "-- part 2 · how a table is stored on disk", "Table → file → page → row", s_storage,
     ["Demo 2.1-2.5 (file numbers differ per machine). Docs, Database Page Layout (storage-page-layout.html);"
      " Database File Layout (storage-file-layout.html); src/include/datatype/timestamp.h (POSTGRES_EPOCH_JDATE)."]),
    ("### 2.8 ", "row-vs-col", "-- 2.7 · rows, not columns", "Row store vs column store", s_row_vs_col,
     ["Demo 2.7: sum(pg_column_size(orderTotal)) = 33 MB; Seq Scan 59,739 pages. Apache Parquet: \"an open source,"
      " column-oriented data file format\" (parquet.apache.org/docs/overview)."]),
    ("### 2.9 ", "mvcc", "-- 2.8 · update and delete", "UPDATE writes a new version", s_mvcc,
     ["Demo 2.8-2.9 (A, B, C stand for the real transaction numbers). Docs, Routine Vacuuming: \"an UPDATE or"
      " DELETE of a row does not immediately remove the old version\" (routine-vacuuming.html); System Columns."]),
    ("### 3.3 ", "stats", "-- part 3 · statistics and estimates", "Where the estimates come from", s_stats,
     ["Demo 3.1-3.3 (one run's sample; yours differs a little). ANALYZE VERBOSE: \"30000 rows in sample\";"
      " src/backend/commands/analyze.c: minrows = 300 * attstattarget. Docs, Statistics Used by the Planner."]),
    ("### 4.1 ", "scans", "-- part 4 · scan types", "Four ways to read a table", s_scans,
     ["Docs, Combining Multiple Indexes (indexes-bitmap-scans.html); Index-Only Scans (indexes-index-only-scans.html)."
      " Schematic: 16 pages stand for the table."]),
    ("### 4.4 ", "selectivity", "-- 4.1-4.3 · selectivity", "Pages read vs share of rows", s_selectivity,
     ["Demo 4.1-4.3, Buffers at the top node (PostgreSQL 18.6): 70 / 55,953 / 63,674; Seq Scan 59,739."
      " Hover a point for its query."]),
    ("### 5.1 ", "btree", "-- part 5 · b-tree indexes", "A B-tree, and what a lookup costs", s_btree,
     ["orders_big_pkey: bt_metap level 2, root 48 entries, 13,712 pages (fresh setup); EXPLAIN (ANALYZE, BUFFERS)"
      " orderID = 4890168: 4 pages. Demo 5.4 (medians). Docs, B-Tree Indexes (btree.html)."]),
    ("### 6.1 ", "composite", "-- part 6 · composite indexes", "Column order: the phone book", s_composite,
     ["Demo 6.1 (Nane's first and last dates from orders_big). Docs, Multicolumn Indexes: \"the index is most"
      " efficient when there are constraints on the leading (leftmost) columns\" (indexes-multicolumn.html)."]),
    ("### 7.2 ", "function", "-- 7.1 · why the index went unused", "A function hides the column", s_function,
     ["Demo 7.1: date_trunc Seq Scan 59,739 pages (estimate 25,001 = DEFAULT_EQ_SEL 0.005 × rows,"
      " src/include/utils/selfuncs.h); range Index Scan 1,995 pages. Docs, Indexes on Expressions."]),
    ("### 8.5 ", "joins", "-- 8.5 · join methods", "Three ways to join", s_joins,
     ["Docs, Planner/Optimizer: nested loop, merge join, hash join (planner-optimizer.html). Demo 8.5."]),
    ("### 9.1 ", "partition", "-- part 8 · partitioning", "One table, several files: pruning", s_partition,
     ["Demo 9.1-9.8; DELETE vs DROP from build/measurements-pg18.md (medians of 3). Docs, Table Partitioning"
      " (ddl-partitioning.html)."]),
    ("### 10.2 ", "decision", "-- part 9 · the decision rule", "Index, partition, or neither?", s_decision,
     ["The rule in lecture-07-notes.md, Part 10.1; numbers from Demo 5.4 (medians)."]),
]


# ---------------------------------------------------------------- simplified (student notebook)
def s_storage_simple():
    o = []
    o.append(t(72, 190, "**A table is one file** on the server's disk: `orders_big` is **467 MB**, cut into "
                        "**59,739 pages of 8 kB**.", 25))
    x, y, pw = 72, 214, 108
    for i, lab in enumerate(["0", "1", "2", "3", "4", "…", "58,425", "…", "59,738"]):
        px = x + i * (pw + 10)
        if lab == "…":
            o.append(mono(px + pw / 2, y + 44, "…", 26, fill=FAINT, anchor="middle"))
            continue
        o.append(rect(px, y, pw, 66, stroke=LINE, rx=6))
        o.append(mono(px + pw / 2, y + 42, lab, 20, fill=SOFT, anchor="middle"))
    o.append(t(1170, 256, "page numbers", 21, fill=FAINT))
    o.append(t(72, 352, "**A page holds about 84 orders.** PostgreSQL always reads a whole page, never a single row.", 25))
    # two rows of pages: scattered vs together
    def strip(y, hits, label, sub, col):
        out = [t(72, y + 30, label, 23, fill=FG), t(72, y + 62, sub, 21)]
        for k in range(20):
            out.append(rect(520 + k * 50, y, 42, 66, fill=col if k in hits else BG, stroke=LINE, rx=4))
        return "".join(out)
    o.append(strip(410, {0, 2, 5, 7, 8, 11, 13, 16, 18, 19}, "Nane's 97 orders", "on **97 different pages**", C_SEQ))
    o.append(strip(530, {9, 10}, "One day's 5,180 orders", "side by side, on **63 pages**", C_INDEX))
    o.append(t(1528, 650, "(schematic: 20 pages shown)", 18, fill=FAINT, anchor="end"))
    o.append(t(72, 712, "Rows are stored in the order they arrived. One day's orders arrived together; one "
                        "customer's orders arrived over three years.", 24))
    o.append(t(72, 760, "**The cost of a query is the number of pages it reads, not the number of rows it returns.**",
               25, fill=FG))
    return "".join(o)


def s_mvcc_simple():
    o = []
    states = [
        ("after INSERT", [("Nane  120.50", "live"), ("Aram   75.00", "live"), ("Ani     9.99", "live")]),
        ("UPDATE Nane, DELETE Ani", [("Nane  120.50", "old copy"), ("Aram   75.00", "live"),
                                     ("Ani     9.99", "deleted"), ("Nane  130.00", "new copy")]),
        ("after VACUUM", [("", "free"), ("Aram   75.00", "live"), ("", "free"), ("Nane  130.00", "live")]),
    ]
    for si, (title, rows) in enumerate(states):
        x = 72 + si * 496
        o.append(mono(x, 190, title, 22, fill=GREEN, weight=600))
        for ri, (val, state) in enumerate(rows):
            y = 220 + ri * 84
            dead = state in ("old copy", "deleted")
            free = state == "free"
            st = RED if dead else (GREEN if state == "new copy" else LINE)
            o.append(rect(x, y, 456, 70, fill="#1F1215" if dead else (BG if free else SURF), stroke=st, rx=6,
                          dash="6 5" if free else None))
            o.append(mono(x + 24, y + 44, val, 22, fill=SOFT if dead else FG))
            o.append(t(x + 432, y + 44, state, 20, fill=RED if dead else (GREEN if state == "new copy" else FAINT),
                       anchor="end"))
        if si < 2:
            o.append(arrow(x + 462, 395, x + 490, 395, "soft"))
    o.append(t(72, 600, "**UPDATE doesn't change a row in place**: it writes a new copy and marks the old one. "
                        "**DELETE only marks.**", 24))
    o.append(t(72, 640, "The marked copies still take space, and every full scan still reads them, until "
                        "**VACUUM** frees them for reuse.", 24))
    o.append(rect(72, 676, 1456, 120, fill="#1F1215", stroke="#5A2A2A"))
    o.append(t(100, 724, "**The trap (2.9):** delete 90% of a 128 MB table, and the file is **still 128 MB**. "
                         "`VACUUM` reuses the space;", 24))
    o.append(t(100, 762, "only `VACUUM FULL` gives it back, and it locks the table while it runs. For old data: "
                         "partitions you can drop (Part 8).", 24))
    return "".join(o)


def s_stats_simple():
    o = []
    o.append(box(72, 190, 330, 170, "orders_big", ["5,000,000 rows"], tc=FG, size=23))
    o.append(arrow(408, 275, 478, 275))
    o.append(box(484, 190, 330, 170, "ANALYZE", ["reads a random", "sample of rows"], tc=AMBER, stroke=AMBER, size=23))
    o.append(arrow(820, 275, 890, 275))
    o.append(box(896, 190, 632, 170, "a summary, per column", [
        "how many rows, how many distinct values,",
        "the most common values and how often they occur"], tc=GREEN, size=22))
    o.append(t(72, 450, "**The planner never looks at the data. It plans from this summary:**", 27, fill=FG))
    o.append(mono(72, 506, "status = 'cancelled'", 25, fill=FG))
    o.append(t(420, 506, "\"3.3% of about 5,000,000 rows\" = **about 166,000** expected", 25))
    o.append(t(420, 546, "actual: 159,902. Close, so the plan fits the data.", 25))
    o.append(rect(72, 610, 1456, 180, fill="#1F1215", stroke="#5A2A2A"))
    o.append(t(100, 662, "**Stale summary (3.3):** 200,000 January orders loaded, no `ANALYZE`. The summary still "
                         "ends on 2025-12-31,", 24))
    o.append(t(100, 702, "so the planner expected **476 rows** and chose a plan for 476. It ran about 1.7 times "
                         "slower. No error.", 24))
    o.append(t(100, 752, "**After a big load, run** `ANALYZE`**.**", 25, fill=FG))
    return "".join(o)


def s_query_path_simple():
    o = []
    xs, y, w, h, gap = 72, 190, 262, 230, 32
    stages = [
        ("1. your SQL", ["sent from psql or", "this notebook:", "`SELECT … WHERE`", "`customerID = 4242`"], FAINT, LINE),
        ("2. Parser", ["is it valid SQL?", "do the tables and", "columns exist?"], GREEN, LINE),
        ("3. Planner", ["thinks of possible", "plans, **estimates**", "the cost of each,", "picks the cheapest"], AMBER, AMBER),
        ("4. Executor", ["runs that plan:", "reads the **pages**,", "filters, joins,", "sums, sorts"], GREEN, LINE),
        ("5. result", ["the rows come", "back to you"], FAINT, LINE),
    ]
    for i, (name, lines, c, st) in enumerate(stages):
        x = xs + i * (w + gap)
        o.append(box(x, y, w, h, name, lines, tc=c, stroke=st, size=23))
        if i:
            o.append(arrow(x - gap + 2, y + h / 2, x - 4, y + h / 2))
    px = xs + 2 * (w + gap)
    ex = xs + 3 * (w + gap)
    o.append(box(px, 500, w, 130, "statistics", ["a summary of the", "data (Part 3)"], tc=SOFT, size=22))
    o.append(arrow(px + w / 2, 500, px + w / 2, y + h + 6, "amber"))
    o.append(box(ex, 500, w, 130, "the table", ["pages in memory", "or on disk (Part 2)"], tc=SOFT, size=22))
    o.append(arrow(ex + w / 2, 500, ex + w / 2, y + h + 6))
    o.append(tl(72, 520, ["`EXPLAIN`: what the planner", "chose (step 3), with its", "**estimates**."], 23))
    o.append(tl(1260, 520, ["`EXPLAIN ANALYZE`:", "also runs step 4 and", "shows what **really**", "happened."], 23))
    o.append(t(72, 712, "The planner decides **without running the query**: it predicts from the statistics.", 25, fill=FG))
    o.append(t(72, 752, "Good statistics → good plan. Stale statistics → a slow plan, but still the right answer.", 24))
    return "".join(o)


def s_latency_simple():
    import math
    o = []
    o.append(t(72, 195, "If one CPU step took **1 second**, getting the data it needs would take:", 27, fill=FG))
    rows = [("CPU: one step", "1 ns", 1, "1 second", SOFT),
            ("from memory (RAM)", "100 ns", 100, "~2 minutes", SOFT),
            ("from an SSD", "75 µs", 75_000, "~21 hours", C_SEQ),
            ("from a hard disk", "8 ms", 8_000_000, "~3 months", C_SEQ)]
    for i, (label, real, ns, human, col) in enumerate(rows):
        y = 250 + i * 100
        o.append(t(72, y + 34, label, 25, fill=FG))
        o.append(mono(72, y + 66, real, 19, fill=FAINT))
        w = 30 + math.log10(ns) / 7 * 700
        o.append(rect(440, y + 10, w, 46, fill=col, stroke="none", rx=4))
        o.append(t(440 + w + 18, y + 42, f"**{human}**", 26))
    o.append(t(440, 680, "(bars on a log scale: the real gaps are much bigger than they look)", 18, fill=FAINT))
    o.append(t(72, 735, "**PostgreSQL reads whole pages.** Checking a page's rows is quick; waiting for the page is "
                        "the slow part. So: **read fewer pages.**", 24))
    o.append(t(72, 775, "(Your laptop keeps `orders_big` in memory after the first run, so your timings show "
                        "mostly the CPU part.)", 21, fill=FAINT))
    return "".join(o)


def s_index_simple():
    o = []
    o.append(t(72, 190, "**An index is a separate, sorted list:** every value of a column, with the address "
                        "(`ctid`) of each row that has it.", 25))
    o.append(t(72, 230, "Like the index at the back of a book: look up the word, get the page numbers.", 24))
    # ---- left: the index (a small tree over a sorted leaf list)
    o.append(mono(72, 300, "index on customerID", 22, fill=BLUE, weight=600))
    o.append(rect(300, 322, 220, 50, stroke=BLUE, rx=6))
    o.append(mono(410, 354, "start here", 19, fill=SOFT, anchor="middle"))
    o.append(rect(100, 412, 260, 46, stroke=LINE, rx=6))
    o.append(mono(230, 442, "1 … 25,000", 19, fill=SOFT, anchor="middle"))
    o.append(rect(460, 412, 260, 46, stroke=LINE, rx=6))
    o.append(mono(590, 442, "25,001 … 50,000", 19, fill=SOFT, anchor="middle"))
    o.append(path_arrow("M 410 372 L 236 410", "blue", sw=3))
    o.append(line(410, 372, 590, 412, stroke=FAINT, sw=2))
    o.append(path_arrow("M 230 458 L 230 494", "blue", sw=3))
    o.append(rect(72, 498, 688, 234, stroke=LINE, rx=6))
    entries = [("4241 → (233, 17)", False), ("4242 → (12, 40)", True), ("4242 → (1350, 8)", True),
               ("4242 → …  97 addresses, one per order", True), ("4243 → (88, 61)", False)]
    for i, (s_, hit) in enumerate(entries):
        y = 518 + i * 42
        if hit:
            o.append(rect(84, y, 664, 36, fill=SURF2, stroke="none", rx=4))
        o.append(mono(104, y + 26, s_, 20, fill=FG if hit else FAINT))
    o.append(t(72, 760, "sorted by customerID, so 4242 is found in a few steps", 19, fill=FAINT))
    # ---- right: the table's pages
    o.append(mono(840, 300, "table orders_big", 22, fill=FG, weight=600))
    o.append(t(1060, 300, "59,739 pages", 20, fill=FAINT))
    hits = {3, 9, 16, 24, 29, 37, 41}
    for k in range(44):
        x = 840 + (k % 11) * 60
        y = 330 + (k // 11) * 60
        o.append(rect(x, y, 50, 50, fill=C_INDEX if k in hits else BG, stroke=LINE, rx=4))
    o.append(path_arrow("M 760 600 C 800 600, 800 560, 834 560", "blue", sw=3))
    o.append(t(840, 600, "Only the pages with Nane's orders are read (blue).", 22))
    o.append(t(840, 640, "`WHERE customerID = 4242`:", 22))
    o.append(t(840, 676, "with the index: **about 100 pages**", 22))
    o.append(t(840, 712, "without it: all **59,739**, checking every row", 22))
    o.append(t(1528, 760, "(schematic: 44 pages shown; addresses made up)", 18, fill=FAINT, anchor="end"))
    return "".join(o)


SIMPLE = {
    "query-path-simple": ("-- part 1 · how postgresql runs a query", "From SQL text to rows", s_query_path_simple,
                          ["PostgreSQL 18 docs, The Path of a Query (query-path.html): parser, rewrite system,"
                           " planner/optimizer, executor. Simplified: the rewrite step (it expands views) is left out."]),
    "latency-simple": ("-- part 2 · why pages matter", "The CPU is fast; the data is far", s_latency_simple,
                       ["Peter Norvig, Teach Yourself Programming in Ten Years (norvig.com/21-days.html): typical"
                        " instruction 1 ns, fetch from main memory 100 ns, disk seek 8 ms. SSD: Seagate Nytro 5550"
                        " datasheet, average read latency 75 µs (4KB, QD1). Times scaled ×1,000,000,000."]),
    "index-simple": ("-- part 4 · what an index is", "An index: value → row address", s_index_simple,
                     ["Pages from Part 1 (Seq Scan, 59,739) and Part 5 (index on customerID, about 100); PostgreSQL 18.6."
                      " Docs, Index Access Methods: \"a mapping from some data key values to tuple identifiers, or TIDs\""
                      " (indexam.html); B-Tree Indexes (btree.html)."]),
    "storage-simple": ("-- part 2 · how a table is stored", "Table → file → pages", s_storage_simple,
                       ["Demo 2.1-2.3 (PostgreSQL 18.6). Docs, Database Page Layout (storage-page-layout.html)."]),
    "mvcc-simple": ("-- 2.8-2.9 · update and delete", "UPDATE writes a new copy", s_mvcc_simple,
                    ["Demo 2.8-2.9. Docs, Routine Vacuuming: \"an UPDATE or DELETE of a row does not immediately"
                     " remove the old version\" (routine-vacuuming.html); VACUUM (sql-vacuum.html)."]),
    "stats-simple": ("-- part 3 · statistics", "Where the estimates come from", s_stats_simple,
                     ["Demo 3.1-3.4 (one run's sample; yours differs a little). Docs, Statistics Used by the Planner"
                      " (planner-stats.html)."]),
}


def by_key(key):
    """Render a slide by its key, simplified ones included."""
    if key in SIMPLE:
        eyebrow, title, body, src = SIMPLE[key]
        return slide(key, eyebrow, title, body, src)
    return render(next(e for e in SLIDES if e[1] == key))


def render(entry):
    _anchor, key, eyebrow, title, body, src = entry
    return slide(key, eyebrow, title, body, src)



# ---------------------------------------------------------------- PNG output
# The diagrams the notebook shows, in order of appearance.
NOTEBOOK = ["query-path-simple", "plan-tree", "latency-simple", "storage-simple", "row-vs-col", "mvcc-simple", "stats-simple",
            "index-simple", "composite", "function", "partition", "decision"]

_PAGE = ("<!doctype html><meta charset='utf-8'><style>html,body{margin:0;padding:0;overflow:hidden;"
         "background:#0E1116}svg{display:block;width:1600px;height:900px;margin:0!important}</style>")


def _png_cairosvg(svg_text, path):
    import cairosvg

    cairosvg.svg2png(bytestring=svg_text.encode(), write_to=str(path), output_width=W, output_height=H)


def _png_chrome(svg_text, path):
    import shutil
    import subprocess
    import tempfile

    chrome = next((shutil.which(c) for c in ("google-chrome", "chromium", "chromium-browser", "chrome")
                   if shutil.which(c)), None)
    if chrome is None:
        raise RuntimeError("Drawing the diagrams needs cairosvg (pip install cairosvg) or Chrome/Chromium.")
    with tempfile.TemporaryDirectory() as tmp:
        page = Path(tmp) / "diagram.html"
        page.write_text(_PAGE + svg_text)
        # headless Chrome draws only the top 812 px of a 900 px window, so the window is
        # 88 px taller; the extra strip has the diagram's background colour.
        subprocess.run([chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        f"--window-size={W},{H + 88}", "--virtual-time-budget=4000",
                        f"--screenshot={path}", page.as_uri()],
                       check=True, capture_output=True, timeout=120)


def render_all(out_dir, keys=None):
    """Write diagrams/<key>.png for every diagram the notebook uses; return {key: path}."""
    import hashlib
    import json

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    cache_file = out_dir / ".hashes.json"
    try:
        cache = json.loads(cache_file.read_text())
    except (OSError, ValueError):
        cache = {}
    try:
        import cairosvg  # noqa: F401
        draw = _png_cairosvg
    except ImportError:
        draw = _png_chrome
    paths = {}
    for key in keys or NOTEBOOK:
        svg_text = by_key(key)
        digest = hashlib.sha256(svg_text.encode()).hexdigest()
        path = out_dir / f"{key}.png"
        if cache.get(key) != digest or not path.exists():
            draw(svg_text, path)
            cache[key] = digest
        paths[key] = str(path)
    cache_file.write_text(json.dumps(cache, indent=1, sort_keys=True))
    return paths


if __name__ == "__main__":
    here = Path(__file__).resolve().parent.parent
    for k, p in render_all(here / "diagrams").items():
        print(k, "->", p)
