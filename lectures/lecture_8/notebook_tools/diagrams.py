"""Diagrams for lecture-08-notebook.py.

Four theory diagrams, drawn as SVG (1600 x 900, the dark look of Lectures 4
and 7) and saved as PNG files in lecture_8/diagrams/. The notebook calls
render_all() once and shows each PNG with mo.image(). Numbers on a diagram
are outputs of the lecture's step files; each diagram ends with its sources.
The drawing helpers are copied from lecture_7/notebook_tools/diagrams.py.

PNG renderer: cairosvg if it's installed, otherwise headless Chrome/Chromium.
A PNG is redrawn only when its diagram changed (hashes in diagrams/.hashes.json).

    python -m notebook_tools.diagrams      # (from lecture_8/) render them all
"""

import html
import re
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


# ---------------------------------------------------------------- diagrams
ROWS = [("1", "Nane", "06-01", "120.50"), ("2", "Aram", "06-01", "75.00"),
        ("3", "Ani", "06-02", "9.99"), ("4", "Hayk", "06-02", "310.00")]


def _strip(x, y, cells, cw=86, ch=58):
    """A file drawn as one long strip of values; highlighted cells are the totals."""
    o = []
    for i, (val, hit, first) in enumerate(cells):
        cx = x + i * cw
        o.append(rect(cx, y, cw - 4, ch, fill=C_INDEX if hit else SURF2, stroke="none", rx=4))
        o.append(mono(cx + (cw - 4) / 2, y + 37, val, 17, fill=FG if hit else SOFT, anchor="middle"))
        if first and i:
            o.append(line(cx - 2, y - 10, cx - 2, y + ch + 10, stroke=FAINT, sw=2))
    return "".join(o)


def s_row_vs_col():
    o = []
    # the table, as we think of it
    o.append(t(72, 196, "**The table**", 24, fill=FG))
    heads = ["id", "customer", "date", "total"]
    for j, hd in enumerate(heads):
        o.append(mono(300 + j * 150, 196, hd, 20, fill=BLUE if hd == "total" else FAINT))
    for i, r in enumerate(ROWS):
        for j, v in enumerate(r):
            o.append(mono(300 + j * 150, 232 + i * 32, v, 20, fill=FG if j == 3 else SOFT))
    # row layout
    o.append(t(72, 430, "**Row-based** — CSV, PostgreSQL: one row after another", 26, fill=FG))
    cells = [(v, j == 3, j == 0) for r in ROWS for j, v in enumerate(r)]
    o.append(_strip(72, 455, cells))
    o.append(t(72, 560, "`sum(total)`: the totals are spread through the whole file, so it reads **everything**.", 24))
    # column layout
    o.append(t(72, 640, "**Column-based** — Parquet: one column after another", 26, fill=FG))
    cells = [(r[j], j == 3, i == 0) for j in range(4) for i, r in enumerate(ROWS)]
    o.append(_strip(72, 665, cells))
    o.append(t(72, 770, "`sum(total)`: the totals sit together, so it reads **one block**.", 24))
    return "".join(o)


def s_parquet():
    o = []
    x, w = 72, 640
    o.append(rect(x, 165, w, 640, fill=BG, stroke=LINE, rx=10))
    o.append(mono(x + 20, 198, "orders_big.parquet  (102 MB)", 21, fill=FG, weight=600))
    cols = ["orderid", "customerid", "orderdate", "…", "ordertotal"]
    groups = [("row group 0", 220), ("row group 1", 380)]
    for name, gy in groups:
        o.append(rect(x + 20, gy, w - 40, 140, fill=SURF, stroke=LINE, rx=8))
        o.append(mono(x + 36, gy + 28, name + "  ~120,000 rows", 18, fill=GREEN))
        for k, c in enumerate(cols):
            cx = x + 36 + k * 118
            hit = c == "ordertotal"
            o.append(rect(cx, gy + 48, 108, 74, fill=C_INDEX if hit else SURF2, stroke="none", rx=4))
            o.append(mono(cx + 54, gy + 92, c, 15, fill=FG if hit else SOFT, anchor="middle"))
    o.append(mono(x + w / 2, 560, "… 41 row groups …", 20, fill=FAINT, anchor="middle"))
    o.append(rect(x + 20, 600, w - 40, 185, fill="#2A2410", stroke=AMBER, rx=8))
    o.append(mono(x + 36, 632, "footer (metadata)", 20, fill=AMBER, weight=600))
    o.append(tl(x + 36, 672, ["column names and **types**", "where each column chunk starts",
                              "**min / max** of every column chunk"], 21, lh=34))
    # what that buys
    rx = 790
    facts = [
        ("`SELECT sum(ordertotal)`", ["reads only the blue chunks:", "**22 MB** of 102 MB"]),
        ("`WHERE orderdate` in June 2025", ["min/max in the footer rule out", "the rest: **2 of 41** row groups, **1.2 MB**"]),
        ("`DESCRIBE`", ["types come from the footer:", "`DECIMAL(10,2)`, `DATE`. Nothing to guess."]),
    ]
    for i, (head, body) in enumerate(facts):
        fy = 200 + i * 200
        o.append(t(rx, fy, head, 26, fill=FG))
        o.append(tl(rx, fy + 44, body, 24))
    return "".join(o)


def s_formats():
    o = []
    k = 1.8  # px per MB

    def bar(y, name, parts, inside=False):
        o.append(t(72, y + 34, name, 24))
        x = 360
        for mb, c, label in parts:
            o.append(rect(x, y, mb * k - 3, 46, fill=c, stroke="none", rx=4))
            if inside:
                o.append(mono(x + 14, y + 32, label, 21, fill=BG, weight=600))
            x += mb * k
        if not inside:
            o.append(mono(x + 12, y + 33, parts[0][2], 22, fill=FG))
        else:
            o.append(mono(x + 12, y + 33, f"{sum(p[0] for p in parts)} MB", 22, fill=FG))

    o.append(t(72, 190, "**Two files** with the same 5,000,000 orders", 26, fill=FG))
    bar(215, "CSV", [(357, AMBER, "357 MB")])
    bar(285, "Parquet", [(102, GREEN, "102 MB")])
    o.append(t(72, 380, "Parquet: types stored, each column compressed. CSV: text, types guessed on every read.",
               23))
    o.append(t(72, 418, "**Excel (.xlsx)** can't hold them: at most **1,048,576 rows** per sheet (2.4).", 23))
    o.append(t(72, 470, "**Two databases** with the same table", 26, fill=FG))
    bar(495, "PostgreSQL", [(489, SOFT, "table 489 MB"), (112, FAINT, "index 112")], inside=True)
    bar(565, "DuckDB", [(116, BLUE, "116 MB (the whole file)")])
    o.append(t(72, 660, "PostgreSQL: whole rows in 8 kB pages (Lecture 7), plus an index for its primary key.",
               23))
    o.append(t(72, 696, "DuckDB: one file, 116 MB, a quarter of the PostgreSQL table alone. (1 MB = 1,000,000 bytes.)", 23))
    o.append(t(72, 770, "Compare like with like: a file with a file, a database with a database.", 24, fill=FG))
    return "".join(o)


def s_postgres():
    o = []
    # clients
    o.append(t(72, 180, "**Clients**", 24, fill=FG))
    clients = [("psql", "terminal"), ("pgAdmin, DBeaver", "graphical"), ("Python", "psycopg, a notebook"),
               ("the shop's website", "an app")]
    for i, (name, kind) in enumerate(clients):
        y = 205 + i * 120
        o.append(box(72, y, 330, 96, name, [kind], tc=BLUE, size=20, tsize=22))
        o.append(arrow(410, y + 48, 560, 400, "soft"))
    o.append(t(570, 662, "clients connect over the network: port 5432, user + password", 19, fill=FAINT))
    # server
    o.append(rect(570, 190, 470, 440, fill=SURF, stroke=GREEN, rx=10))
    o.append(mono(594, 228, "PostgreSQL server", 24, fill=GREEN, weight=600))
    o.append(t(594, 262, "a program that is always running", 20))
    o.append(t(594, 312, "**one process per connection**", 21, fill=FG))
    for i in range(4):
        o.append(rect(594 + i * 106, 330, 94, 56, fill=SURF2, stroke="none", rx=4))
        o.append(mono(641 + i * 106, 364, "client", 16, fill=BLUE, anchor="middle"))
    o.append(t(594, 440, "**its own background processes**", 21, fill=FG))
    o.append(tl(594, 476, ["write the log, save changed pages,", "start autovacuum, … (8 here)"], 20, lh=30))
    o.append(t(594, 590, "only the server touches the files", 20, fill=AMBER))
    o.append(arrow(1048, 410, 1120, 410, "soft"))
    # data directory
    o.append(rect(1128, 190, 400, 440, fill=BG, stroke=LINE, rx=10, dash="8 6"))
    o.append(mono(1150, 228, "data directory", 22, fill=FAINT, weight=600))
    files = [("base/", "a folder per database"), ("base/16384/", "lecture08: **337 files, 582 MB**"),
             ("pg_wal/", "the log, for crashes"), ("postgresql.conf", "settings"), ("pg_hba.conf", "who may connect")]
    for i, (f, what) in enumerate(files):
        y = 280 + i * 70
        o.append(mono(1150, y, f, 20, fill=FG))
        o.append(t(1150, y + 30, what, 19))
    o.append(t(72, 700, "**What it is for:** many people and programs at once, reading and writing the same data, "
                        "safely,", 24))
    o.append(t(72, 738, "all day: the shop's tills, website and analysts on one database. The price: someone installs, "
                        "runs and", 24))
    o.append(t(72, 776, "looks after the server.", 24))
    return "".join(o)


def s_embedded():
    o = []
    o.append(t(72, 185, "**DuckDB: the engine runs inside your program; the database is one file**", 26, fill=FG))
    o.append(rect(72, 215, 700, 230, fill=BG, stroke=BLUE, rx=10))
    o.append(mono(96, 252, "your program", 22, fill=BLUE, weight=600))
    o.append(box(110, 280, 620, 140, "DuckDB engine", ["Python: `import duckdb` · terminal: the `duckdb` CLI",
                                                      "also R, Java, Node.js, … · no server, no password"],
                 tc=GREEN))
    o.append(arrow(780, 330, 1000, 330, "soft"))
    o.append(rect(1010, 255, 260, 150, fill=SURF2, stroke=GREEN, rx=8))
    o.append(mono(1140, 318, "shop.duckdb", 24, fill=FG, weight=600, anchor="middle"))
    o.append(mono(1140, 360, "1 file, 116 MB", 20, fill=SOFT, anchor="middle"))
    o.append(t(1300, 310, "the whole", 20))
    o.append(t(1300, 338, "database", 20))
    # comparison
    rows = [("", "PostgreSQL", "DuckDB"),
            ("a database is", "337 files the server owns", "**1 file you own**"),
            ("to share it", "give people a login", "copy the file"),
            ("runs", "always, on a server", "only while your program runs"),
            ("writers at once", "many", "**one process**")]
    for i, (a, b, c) in enumerate(rows):
        y = 515 + i * 54
        if i:
            o.append(line(72, y - 36, 1528, y - 36, stroke=LINE, sw=1))
        o.append(t(72, y, a, 22, fill=FAINT))
        o.append(t(420, y, b, 22, fill=FG if i == 0 else SOFT, weight=600 if i == 0 else 400))
        o.append(t(980, y, c, 22, fill=FG if i == 0 else SOFT, weight=600 if i == 0 else 400))
    return "".join(o)


def s_when():
    o = []
    cols = [(72, "PostgreSQL is for", GREEN,
             ["many people and programs using the", "at the same time",
              "data written all day (orders, payments)",
              "a database that is always on",
              "logins: who may see and change what"]),
            (828, "DuckDB is for", BLUE,
             ["one analyst, on a laptop or in a notebook",
              "big scans: sums, GROUP BY, joins",
              "data that arrives as files (CSV, Parquet)",
              "results that leave as files",
              "analysis without running a server"])]
    for x, head, c, items in cols:
        o.append(rect(x, 175, 700, 470, fill=SURF, stroke=c, rx=10))
        o.append(mono(x + 28, 222, head, 28, fill=c, weight=600))
        y = 290
        for it in items:
            if it == "at the same time":
                it = "same data at the same time"
                o.append(t(x + 58, y - 20, it, 24))
                y += 30
                continue
            o.append(t(x + 28, y, "·", 30, fill=c))
            o.append(t(x + 58, y, it, 24))
            y += 64
    o.append(t(72, 705, "**Often both:** the shop's orders live in PostgreSQL; an analyst exports them to Parquet and "
                        "analyses", 24))
    o.append(t(72, 743, "them in DuckDB, or reads PostgreSQL from DuckDB directly (Part 6).", 24))
    return "".join(o)

PQ = "https://parquet.apache.org/docs/"
DD = "https://duckdb.org/docs/2.0/"
SLIDES = {
    "row-vs-col": ("-- part 1 · storage layout", "Same rows, two layouts", s_row_vs_col,
                   ["Illustrative rows. Apache Parquet: \"an open source, column-oriented data file format\" ("
                    + PQ + "overview/). Lecture 7, 2.7: sum(orderTotal) read all 59,739 pages of orders_big."]),
    "parquet": ("-- part 1 · inside a parquet file", "Inside a Parquet file", s_parquet,
                ["Step 01 (parquet_metadata, EXPLAIN ANALYZE; DuckDB 2.0.1). Parquet docs: \"File metadata is written after"
                 " the data\" (" + PQ + "file-format/); statistics per column chunk (" + PQ + "file-format/pageindex/)."]),
    "formats": ("-- part 2 · size", "Files vs files, databases vs databases", s_formats,
                [("Step 02 (read_blob); notebook 2.1 (pg_relation_size, pg_indexes_size; MB = 10^6 bytes; pg_size_pretty shows"
                  " 467 / 107). DuckDB docs: CSV auto detection, Parquet overview. Microsoft: Excel specifications and limits.")]),
    "postgres": ("-- part 3 · a database server", "How PostgreSQL works", s_postgres,
                 [("Step 03-postgres-server.sql (PostgreSQL 18.6). Docs: Architectural Fundamentals (tutorial-arch.html):"
                   " client/server, \"forks\" a new process for each connection; Database File Layout"
                   " (storage-file-layout.html); pgadmin.org; dbeaver.io.")]),
    "embedded": ("-- part 3 · an embedded engine", "The database in one file", s_embedded,
                 ["Steps 03-postgres-server.sql, 03-duckdb-embedded.py. DuckDB: \"primarily an in-process database system\","
                  " clients for many languages and a CLI (" + DD + "clients/overview.html); \"a single-file database\""
                  " (duckdb.org/why_duckdb); Concurrency (" + DD + "connect/concurrency.html)."]),
    "when": ("-- part 3 · use cases", "Use cases: PostgreSQL and DuckDB", s_when,
             ["Course rule of thumb. DuckDB: \"designed to support analytical query workloads\" (duckdb.org/why_duckdb);"
              " one writer process (" + DD + "connect/concurrency.html). PostgreSQL: one process per connection"
              " (tutorial-arch.html)."]),
}

# The diagrams the notebook shows, in order of appearance.
NOTEBOOK = ["row-vs-col", "parquet", "formats", "postgres", "embedded", "when"]


def by_key(key):
    eyebrow, title, body, src = SLIDES[key]
    return slide(key, eyebrow, title, body, src)


# ---------------------------------------------------------------- PNG output
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
