#!/usr/bin/env python3
"""
Build lecture-04-slides.html: the Lecture 4 deck on Lecture 2's slide engine.

    python3 build_html.py     # writes ../lecture-04-slides.html

The CSS and JS are copied verbatim from ../../lecture_2/lecture-02-slides.html
(plus a few rules for the Venn and dot-grid diagrams). Content follows
../lecture-04-notes.md; SQL is copied from ../lecture-04-demo.sql; every
number is the verified output of that demo.
"""
import html, re
from pathlib import Path

HERE = Path(__file__).parent
L2 = (HERE / "../../lecture_2/lecture-02-slides.html").read_text()
STYLE = L2[L2.index("<style>") + 7: L2.index("</style>")]
SCRIPT = L2[L2.index("<script>"): L2.index("</script>") + 9]

EXTRA_CSS = """
/* ---- Lecture 4 additions (same palette, same fonts) ---- */
.diagram{ flex:1; min-height:0; display:flex; align-items:center; justify-content:center; }
.vennrow{ display:flex; gap:36px; align-items:center; }
.sidebox{ flex:1; min-width:0; }
.result{ font:700 15px var(--font-sans); color:var(--ink-soft); margin:10px 0 4px; letter-spacing:.02em; }
.bignum{ font:800 44px/1 var(--font-sans); color:var(--blue-dark); }
.bignum.bad{ color:var(--red); }
.bignum.good{ color:var(--green-dark); }
.bignum-label{ font:16px/1.4 var(--font-sans); color:var(--ink-soft); margin-top:6px; }
.err{ background:var(--code-bg); border-radius:10px; padding:14px 20px; font:16px/1.55 var(--font-mono); color:#F28B82; white-space:pre; margin-top:12px; }
.quote{ font:italic 22px/1.45 var(--font-sans); color:var(--ink-soft); max-width:900px; margin-top:18px; }
ol.refs{ margin:0; padding-left:22px; columns:2; column-gap:40px; }
ol.refs li{ font:12.5px/1.4 var(--font-sans); color:var(--ink-soft); margin-bottom:6px; break-inside:avoid; }
"""

# ---- SQL highlighting ---------------------------------------------------------
KW = ("SELECT FROM JOIN LEFT RIGHT FULL CROSS INNER NATURAL ON USING WHERE GROUP BY ORDER HAVING AND OR AS IS NULL NOT "
      "EXCEPT LIMIT IN BETWEEN CREATE TABLE INSERT INTO VALUES DISTINCT FILTER DESC NULLS LAST CASE WHEN THEN ELSE END "
      "DATE INTERVAL TRUE").split()
FN = "count sum coalesce generate_series jsonb_agg jsonb_build_object EXTRACT to_char".split()
TOK = re.compile(r"('[^']*')|\b(" + "|".join(KW) + r")\b|\b(" + "|".join(FN) + r")\b|\b(\d+(?:\.\d+)?)\b")

def hl(line):
    if "--" in line:
        code, com = line.split("--", 1)
        com = "--" + com
    else:
        code, com = line, ""
    def rep(m):
        if m.group(1): return f'<span class="str">{m.group(1)}</span>'
        if m.group(2): return f'<span class="kw">{m.group(2)}</span>'
        if m.group(3): return f'<span class="fn">{m.group(3)}</span>'
        return f'<span class="num">{m.group(4)}</span>'
    out = TOK.sub(rep, html.escape(code, quote=False))
    if com:
        out += f'<span class="com">{html.escape(com, quote=False)}</span>'
    return out

def code(sql, size=17, style=""):
    body = "\n".join(hl(l) for l in sql.strip("\n").split("\n"))
    return f'<div class="code" style="font-size:{size}px; line-height:1.55; padding:18px 24px;{style}">{body}</div>'

def err(text):
    return f'<div class="err">{html.escape(text.strip(), quote=False)}</div>'

def tbl(headers, rows, cls="cmp compact", tints=None, style=""):
    tints = tints or {}
    th = "".join(f"<th>{h}</th>" for h in headers)
    trs = []
    for i, r in enumerate(rows):
        a = f' style="background:{tints[i]};"' if i in tints else ""
        trs.append(f"<tr{a}>" + "".join(f"<td>{x}</td>" for x in r) + "</tr>")
    return f'<table class="{cls}" style="{style}"><thead><tr>{th}</tr></thead><tbody>{"".join(trs)}</tbody></table>'

def mono(t):
    return f'<code style="font-family:var(--font-mono);">{t}</code>'

# ---- slide builders ------------------------------------------------------------
slides = []

def notes(n):
    return f'<div class="notes"><b>Say</b> {n}</div>' if n else ""

def src(s):
    return f'<footer class="tag">Source: {s}</footer>' if s else ""

def title_slide():
    slides.append('''<section class="slide slide--title active" data-title="Title">
      <div class="eyebrow">Introduction to Databases &amp; SQL · Lecture 4</div>
      <h1>Putting the Tables Back Together</h1>
      <div class="sub">YSU, Data Science for Business</div>
      <div class="meta">Data models · dimensional modeling · star &amp; snowflake · JOINs</div>
      <div class="notes"><b>Say</b> Last time we took one table apart question by question. Today we put four tables back together, and build a second, analytical schema on top. Setup for the room: from the lecture_4 folder, psql postgres, then \\i steps/00-setup.sql (it creates and connects to lecture04); expect 965 / 30 / 8 / 37 / 600 / 965.</div>
    </section>''')

def section(num, part, title, lede, note=""):
    slides.append(f'''<section class="slide slide--section" data-title="{part} — {html.escape(title)}">
      <div class="num">{num}</div>
      <div class="kicker">{part}</div>
      <h1 class="title">{title}</h1>
      <p class="lede">{lede}</p>
      {notes(note)}
    </section>''')

def content(dt, kicker, title, body, note="", source="", lede=""):
    l = f'<p class="lede">{lede}</p>' if lede else ""
    slides.append(f'''<section class="slide slide--content" data-title="{html.escape(dt)}">
      <div class="kicker">{kicker}</div>
      <h1 class="title">{title}</h1>
      {l}
      <div class="body-area">
{body}
      </div>
      {src(source)}
      {notes(note)}
    </section>''')

def statement(dt, inner, note="", source=""):
    slides.append(f'''<section class="slide slide--statement" data-title="{html.escape(dt)}">
      {inner}
      {src(source)}
      {notes(note)}
    </section>''')

# ---- diagrams (inline SVG, drawn like Lecture 2's ER diagram) -----------------
BLUE, BLUE_DARK, BLUE_MID, BLUE_LIGHT = "#3D6D9E", "#1F3864", "#5B8FC4", "#BCD7E9"
SLATE, RULE, INK, INK_SOFT, FAINT = "#687F91", "#DCE3EA", "#141517", "#4B5563", "#8A94A3"
GREEN, GREEN_T, RED, RED_T = "#2E7D4F", "#E7F4EC", "#D93025", "#FCEAE8"
MONO = "SFMono-Regular,Consolas,monospace"

def entity(x, y, w, name, rows, head=SLATE):
    """rows: list of (tag, text) with tag in PK/FK/''"""
    h = 12 + 20 * len(rows)
    s = [f'<rect x="{x}" y="{y}" width="{w}" height="30" fill="{head}"/>',
         f'<text x="{x+14}" y="{y+21}" font-family="Arial" font-weight="700" font-size="16" fill="#fff">{name}</text>',
         f'<rect x="{x}" y="{y+30}" width="{w}" height="{h}" fill="#fff" stroke="{RULE}"/>']
    for i, (tag, txt) in enumerate(rows):
        yy = y + 30 + 21 + 20 * i
        if tag:
            col = BLUE_DARK if tag == "PK" else BLUE
            s.append(f'<text x="{x+14}" y="{yy}" font-family="{MONO}" font-size="13" font-weight="700" fill="{col}">{tag}</text>')
        colr = INK if tag else INK_SOFT
        s.append(f'<text x="{x+44}" y="{yy}" font-family="{MONO}" font-size="13" fill="{colr}">{txt}</text>')
    return "".join(s), y + 30 + h

def one_bar(x, y, vertical=False):
    if vertical:  # line runs vertically; bars are horizontal
        return f'<path d="M {x-6},{y} H {x+6} M {x-6},{y+5} H {x+6}" stroke="{BLUE}" stroke-width="1.8"/>'
    return f'<path d="M {x},{y-6} V {y+6} M {x+5},{y-6} V {y+6}" stroke="{BLUE}" stroke-width="1.8"/>'

def crow(x, y, direction):
    """many-end at point (x, y) on an entity edge; direction the line comes from: 'left','right','up','down'"""
    if direction == "left":   # line arrives from the left, entity edge at x
        return f'<path d="M {x-10},{y} L {x},{y-8} M {x-10},{y} L {x},{y} M {x-10},{y} L {x},{y+8}" stroke="{BLUE}" stroke-width="1.8" fill="none"/>'
    if direction == "right":
        return f'<path d="M {x+10},{y} L {x},{y-8} M {x+10},{y} L {x},{y} M {x+10},{y} L {x},{y+8}" stroke="{BLUE}" stroke-width="1.8" fill="none"/>'
    if direction == "up":
        return f'<path d="M {x},{y-10} L {x-8},{y} M {x},{y-10} L {x},{y} M {x},{y-10} L {x+8},{y}" stroke="{BLUE}" stroke-width="1.8" fill="none"/>'
    return f'<path d="M {x},{y+10} L {x-8},{y} M {x},{y+10} L {x},{y} M {x},{y+10} L {x+8},{y}" stroke="{BLUE}" stroke-width="1.8" fill="none"/>'

def link(points):
    d = "M " + " L ".join(f"{a},{b}" for a, b in points)
    return f'<path d="{d}" fill="none" stroke="{BLUE}" stroke-width="1.8"/>'

def star_svg():
    W, H = 1136, 440
    parts = []
    fact, fb = entity(418, 110, 300, "FACT_SALES", [("PK", "orderID"), ("PK", "productKey"), ("FK", "dateKey"), ("FK", "customerKey"),
                                                     ("FK", "employeeKey"), ("", "quantity, revenue, cost")], head=BLUE_DARK)
    d1, _ = entity(30, 20, 300, "DIM_DATE", [("PK", "dateKey"), ("", "quarter, month"), ("", "monthName, dayName")])
    d2, _ = entity(30, 270, 300, "DIM_CUSTOMER", [("PK", "customerKey"), ("", "customerName, city"), ("", "signupYear")])
    d3, _ = entity(806, 20, 300, "DIM_PRODUCT", [("PK", "productKey"), ("", "productName, brand"), ("", "category")])
    d4, _ = entity(806, 270, 300, "DIM_EMPLOYEE", [("PK", "employeeKey"), ("", "employeeName, branch"), ("", "managerName")])
    # links: dim right/left edge -> fact edge, crow's foot at the fact
    parts += [link([(330, 75), (374, 75), (374, 180), (418, 180)]), one_bar(336, 75), crow(418, 180, "left"),
              link([(330, 325), (374, 325), (374, 250), (418, 250)]), one_bar(336, 325), crow(418, 250, "left"),
              link([(806, 75), (762, 75), (762, 180), (718, 180)]), one_bar(795, 75), crow(718, 180, "right"),
              link([(806, 325), (762, 325), (762, 250), (718, 250)]), one_bar(795, 325), crow(718, 250, "right")]
    lab = f'<g font-family="Arial" font-size="13" fill="{FAINT}"><text x="345" y="66">when</text><text x="338" y="344">who bought</text><text x="740" y="66">what</text><text x="742" y="344">who sold</text></g>'
    note = (f'<text x="418" y="{fb+26}" font-family="Arial" font-style="italic" font-size="13" fill="{FAINT}">grain: one row per order line · 965 rows</text>'
            f'<text x="30" y="425" font-family="Arial" font-size="12" fill="{FAINT}">Line ends:  ‖ exactly one  ·  crow\'s foot = many. Every dimension is one join away from the fact.</text>')
    return f'<svg viewBox="0 0 {W} {H}" width="{W}" height="{H}">' + "".join(parts) + d1 + d2 + d3 + d4 + fact + lab + note + "</svg>"

def snowflake_svg():
    W, H = 1136, 440
    parts = []
    fact, fb = entity(330, 120, 260, "FACT_SALES", [("PK", "orderID"), ("PK", "productKey"), ("FK", "dateKey"), ("FK", "customerKey"),
                                                     ("FK", "employeeKey"), ("", "revenue, cost")], head=BLUE_DARK)
    d1, _ = entity(20, 30, 250, "DIM_DATE", [("PK", "dateKey"), ("", "quarter, dayName")])
    d2, _ = entity(20, 280, 250, "DIM_CUSTOMER", [("PK", "customerKey"), ("", "customerName, city")])
    d4, _ = entity(650, 280, 250, "DIM_EMPLOYEE", [("PK", "employeeKey"), ("", "employeeName, branch")])
    d3, _ = entity(650, 110, 250, "DIM_PRODUCT", [("PK", "productKey"), ("", "productName"), ("FK", "categoryKey"), ("FK", "brandKey")])
    c1, _ = entity(950, 20, 170, "DIM_CATEGORY", [("PK", "categoryKey"), ("", "category")], head=GREEN)
    c2, _ = entity(950, 250, 170, "DIM_BRAND", [("PK", "brandKey"), ("", "brand")], head=GREEN)
    parts += [link([(270, 75), (300, 75), (300, 190), (330, 190)]), one_bar(276, 75), crow(330, 190, "left"),
              link([(270, 325), (300, 325), (300, 260), (330, 260)]), one_bar(276, 325), crow(330, 260, "left"),
              link([(650, 165), (620, 165), (620, 190), (590, 190)]), one_bar(639, 165), crow(590, 190, "right"),
              link([(650, 325), (620, 325), (620, 260), (590, 260)]), one_bar(639, 325), crow(590, 260, "right"),
              # sub-tables: category / brand -> product (product is the many side)
              link([(950, 65), (925, 65), (925, 175), (900, 175)]), one_bar(939, 65), crow(900, 175, "right"),
              link([(950, 295), (925, 295), (925, 195), (900, 195)]), one_bar(939, 295), crow(900, 195, "right")]
    note = (f'<text x="950" y="395" font-family="Arial" font-weight="700" font-size="13" fill="{GREEN}">split out of DIM_PRODUCT</text>'
            f'<text x="20" y="425" font-family="Arial" font-size="12" fill="{FAINT}">Same fact, same grain. Revenue by category is now two hops from the fact: fact → product → category.</text>')
    return f'<svg viewBox="0 0 {W} {H}" width="{W}" height="{H}">' + "".join(parts) + d1 + d2 + d3 + d4 + c1 + c2 + fact + note + "</svg>"

VENN_N = [0]
def venn(kind, left="orders", right="employees", w=380, h=240):
    VENN_N[0] += 1
    k = VENN_N[0]
    ax, bx, cy, r = 140, 240, 110, 95
    fill = BLUE_MID
    s = [f'<svg viewBox="0 0 {w} {h}" width="{w}" height="{h}"><defs><clipPath id="clipA{k}"><circle cx="{ax}" cy="{cy}" r="{r}"/></clipPath></defs>']
    if kind in ("left", "full"):
        s.append(f'<circle cx="{ax}" cy="{cy}" r="{r}" fill="{fill}" fill-opacity=".55"/>')
    if kind in ("right", "full"):
        s.append(f'<circle cx="{bx}" cy="{cy}" r="{r}" fill="{fill}" fill-opacity=".55"/>')
    if kind == "inner":
        s.append(f'<circle cx="{bx}" cy="{cy}" r="{r}" fill="{fill}" fill-opacity=".55" clip-path="url(#clipA{k})"/>')
    if kind == "left":
        s.append(f'<circle cx="{bx}" cy="{cy}" r="{r}" fill="{fill}" fill-opacity=".35" clip-path="url(#clipA{k})"/>')
    if kind == "right":
        s.append(f'<circle cx="{ax}" cy="{cy}" r="{r}" fill="{fill}" fill-opacity=".35" clip-path="url(#clipA{k})"/>')
    s.append(f'<circle cx="{ax}" cy="{cy}" r="{r}" fill="none" stroke="{BLUE_DARK}" stroke-width="2"/>')
    s.append(f'<circle cx="{bx}" cy="{cy}" r="{r}" fill="none" stroke="{BLUE_DARK}" stroke-width="2"/>')
    s.append(f'<text x="{ax-50}" y="{h-12}" font-family="Arial" font-weight="700" font-size="15" fill="{BLUE_DARK}" text-anchor="middle">{left}</text>')
    s.append(f'<text x="{bx+50}" y="{h-12}" font-family="Arial" font-weight="700" font-size="15" fill="{BLUE_DARK}" text-anchor="middle">{right}</text>')
    s.append("</svg>")
    return "".join(s)

def dotgrid(mode):
    """3 orders x 3 customers. mode: 'all' (every pair), 'match' (the 3 true pairs highlighted)"""
    orders = [("1001", 2), ("1002", 26), ("1003", 6)]
    custs = [(2, "Davit"), (6, "Narek"), (26, "Samvel")]
    x0, y0, dx, dy = 150, 70, 110, 70
    s = ['<svg viewBox="0 0 470 300" width="470" height="300">']
    for j, (cid, n) in enumerate(custs):
        s.append(f'<text x="{x0+dx*j}" y="30" font-family="Arial" font-weight="700" font-size="14" fill="{BLUE_DARK}" text-anchor="middle">{n}</text>')
        s.append(f'<text x="{x0+dx*j}" y="48" font-family="{MONO}" font-size="12" fill="{FAINT}" text-anchor="middle">id {cid}</text>')
    for i, (oid, oc) in enumerate(orders):
        s.append(f'<text x="20" y="{y0+dy*i+5}" font-family="{MONO}" font-size="13" fill="{INK}">{oid} → {oc}</text>')
        for j, (cid, _) in enumerate(custs):
            hit = oc == cid
            if mode == "all":
                s.append(f'<circle cx="{x0+dx*j}" cy="{y0+dy*i}" r="13" fill="{BLUE_MID}"/>')
            else:
                s.append(f'<circle cx="{x0+dx*j}" cy="{y0+dy*i}" r="13" fill="{GREEN if hit else "#fff"}" stroke="{GREEN if hit else RULE}" stroke-width="2"/>')
    cap = "9 pairs: every order × every customer" if mode == "all" else "keep the 3 pairs where the ids match"
    s.append(f'<text x="20" y="285" font-family="Arial" font-size="13" fill="{INK_SOFT}">{cap}</text>')
    s.append("</svg>")
    return "".join(s)

def orgchart2():
    W, H = 600, 290
    def box(x, y, name, role, dark=False):
        f, t, r = (BLUE_DARK, "#fff", "#BFD6EC") if dark else ("#fff", INK, INK_SOFT)
        return (f'<rect x="{x}" y="{y}" width="126" height="50" rx="6" fill="{f}" stroke="{SLATE}" stroke-width="1.5"/>'
                f'<text x="{x+63}" y="{y+21}" font-family="Arial" font-weight="700" font-size="16" fill="{t}" text-anchor="middle">{name}</text>'
                f'<text x="{x+63}" y="{y+40}" font-family="Arial" font-size="13" fill="{r}" text-anchor="middle">{role}</text>')
    L = lambda d: f'<path d="{d}" fill="none" stroke="{SLATE}" stroke-width="1.5"/>'
    return "".join([f'<svg viewBox="0 0 {W} {H}" width="560" height="{round(H*560/W)}">',
         L("M 298,60 V 82 M 73,82 H 523 M 73,82 V 104 M 223,82 V 104 M 373,82 V 104 M 523,82 V 104"),
         L("M 373,154 V 176 M 223,176 H 373 M 223,176 V 198 M 373,176 V 198"),
         L("M 523,154 V 198"),
         box(235, 10, "Vahe", "Store Manager", True),
         box(10, 104, "Gor", "Senior Sales"), box(160, 104, "Ani", "Sales Associate"),
         box(310, 104, "Hayk", "Senior Sales"), box(460, 104, "Marine", "Senior Sales"),
         box(160, 198, "Nare", "Sales Associate"), box(310, 198, "Lilit", "Sales Associate"),
         box(460, 198, "Arman", "Sales Associate"),
         f'<text x="10" y="280" font-family="Arial" font-size="14" fill="{FAINT}">employees.managerID points at another row of employees</text>',
         "</svg>"])

def fanout_svg():
    W, H = 1136, 250
    s = [f'<svg viewBox="0 0 {W} {H}" width="{W}" height="{H}">',
         f'<rect x="10" y="80" width="250" height="70" rx="6" fill="#fff" stroke="{SLATE}" stroke-width="1.5"/>',
         f'<text x="135" y="108" font-family="Arial" font-weight="700" font-size="15" fill="{INK}" text-anchor="middle">Aram Vardanyan</text>',
         f'<text x="135" y="132" font-family="{MONO}" font-size="13" fill="{INK_SOFT}" text-anchor="middle">moneySpent 14,625.38</text>',
         f'<text x="10" y="70" font-family="Arial" font-size="12" fill="{FAINT}">customers: 1 row</text>',
         f'<text x="400" y="18" font-family="Arial" font-size="12" fill="{FAINT}">after JOIN orders: 1 row per order</text>']
    for i in range(4):
        y = 30 + i * 48
        s.append(f'<path d="M 260,115 L 400,{y+18}" stroke="{BLUE}" stroke-width="1.5" fill="none"/>')
        s.append(f'<rect x="400" y="{y}" width="330" height="36" fill="#fff" stroke="{RULE}"/>')
        s.append(f'<text x="414" y="{y+23}" font-family="{MONO}" font-size="13" fill="{INK}">one of his orders   <tspan fill="{RED}" font-weight="700">14,625.38</tspan></text>')
    s.append(f'<text x="414" y="232" font-family="{MONO}" font-size="13" fill="{FAINT}">… 40 rows, 14,625.38 on every one</text>')
    s.append(f'<text x="780" y="110" font-family="Arial" font-size="15" fill="{INK_SOFT}">sum over his rows</text>')
    s.append(f'<text x="780" y="140" font-family="{MONO}" font-size="22" font-weight="700" fill="{RED}">= 585,015.20</text>')
    s.append(f'<text x="780" y="166" font-family="Arial" font-size="13" fill="{FAINT}">40 × 14,625.38, not 14,625.38</text>')
    s.append("</svg>")
    return "".join(s)

def cost_svg():
    W, H = 1136, 260
    items = [("Conceptual", "erase a box, redraw an arrow", 40, GREEN),
             ("Logical", "rework keys and constraints on paper", 110, BLUE),
             ("Physical", "ALTER TABLE on live data (Lecture 2, Part 9)", 190, RED)]
    s = [f'<svg viewBox="0 0 {W} {H}" width="{W}" height="{H}">']
    for i, (name, what, bar, col) in enumerate(items):
        x = 20 + i * 380
        s.append(f'<rect x="{x}" y="{210-bar}" width="80" height="{bar}" fill="{col}" fill-opacity=".85"/>')
        s.append(f'<text x="{x+100}" y="120" font-family="Arial" font-weight="700" font-size="20" fill="{BLUE_DARK}">{name}</text>')
        s.append(f'<text x="{x+100}" y="146" font-family="Arial" font-size="14" fill="{INK_SOFT}">{what.split(" (")[0]}</text>')
        if "(" in what:
            s.append(f'<text x="{x+100}" y="166" font-family="Arial" font-size="13" fill="{FAINT}">({what.split(" (")[1]}</text>')
        if i < 2:
            s.append(f'<path d="M {x+330},200 H {x+370}" stroke="{FAINT}" stroke-width="2"/><path d="M {x+362},194 L {x+370},200 L {x+362},206" stroke="{FAINT}" stroke-width="2" fill="none"/>')
    s.append(f'<line x1="20" y1="210" x2="1116" y2="210" stroke="{RULE}" stroke-width="1.5"/>')
    s.append(f'<text x="20" y="240" font-family="Arial" font-size="13" fill="{FAINT}">bar height = the cost of changing your mind at that level</text>')
    s.append("</svg>")
    return "".join(s)

# ---- sources (short form; full list on the last slide) -------------------------
N = "lecture-04-notes.md"
D = "lecture-04-demo.sql"

# ============================================================================
# SLIDES
# ============================================================================
title_slide()

content("Agenda", "Today's Arc", "Four parts, one running example",
    '''<ul class="points" style="columns:2; column-gap:48px;">
          <li><b>1</b> — Three levels of a data model</li>
          <li><b>2</b> — Dimensional modeling: facts, dimensions, grain</li>
          <li><b>3</b> — Star vs. snowflake schema</li>
          <li><b>4</b> — JOINs, built from one idea</li>
        </ul>
        <div class="callout callout--green" style="margin-top:30px; max-width:900px;"><b>Most of today is Part 4</b>Every join type falls out of a single sentence — and every trap in it returns a normal-looking table, with no error.</div>''',
    note="Part 4 is the long one. Parts 1–3 give the vocabulary; Part 4 is the skill.",
    lede="Same shop as Lecture 3, but an order can hold several products: 600 orders with 965 lines, 30 customers, 8 employees, 37 products.",
    source=f"{N}, scope line (600 / 30 / 8 / 37 / 600)")

content("Recap: where we left off", "Where We Left Off", "We split one wide table into four",
    '''<div class="chiprow" style="margin-top:0;">
          <div class="chip">customers</div><div class="chip">employees</div><div class="chip">products</div><div class="chip">orders</div><div class="chip">order_items</div>
        </div>
        <div class="defs" style="margin-top:28px;">
          <div class="def"><div class="def__term">Lecture 2</div><div class="def__body">Split the flat sales file into four tables, one fact in one place.</div></div>
          <div class="def"><div class="def__term">Lecture 3</div><div class="def__body">Asked questions of one table at a time.</div></div>
          <div class="def"><div class="def__term">New</div><div class="def__body">An order can hold several products: <code style="font-family:var(--font-mono);">orders</code> is the header, <code style="font-family:var(--font-mono);">order_items</code> has one row per product in an order.</div></div>
          <div class="def"><div class="def__term">Today</div><div class="def__body">Put the tables back together with JOIN — and build a second, analytical schema on top of them.</div></div>
        </div>''',
    note="Everything today is either putting tables together (JOIN) or deciding what shape the tables should have in the first place (models and schemas).",
    source="Lecture 2 and Lecture 3 notes")

# ---- Part 1 ----
section("01", "Part 1", "Three levels of a data model", "Every table you design goes through three translations, whether you name them or not.",
        "Name the three levels today; you have already used all three.")

content("Conceptual, logical, physical", "Part 1 &middot; Data Models", "Conceptual → logical → physical",
    '''<div class="boxrow" style="flex:0 0 auto; align-items:stretch;">
          <div class="box"><div class="box__head">Conceptual</div><div class="box__body" style="font-family:var(--font-sans);">
            <b>Entities and relationships.</b> No tables yet.<br><br>
            <span style="color:var(--ink-soft);">"A customer places orders. An order holds one or more products. An employee may serve an order — or nobody does, if it's online."</span></div></div>
          <div class="box"><div class="box__head">Logical</div><div class="box__body" style="font-family:var(--font-sans);">
            <b>Tables, columns, keys, constraints.</b> Still DBMS-agnostic.<br><br>
            <span style="font-family:var(--font-mono); font-size:14px;">orders.customerID</span> — required foreign key<br>
            <span style="font-family:var(--font-mono); font-size:14px;">orders.employeeID</span> — optional</div></div>
          <div class="box box--accent"><div class="box__head">Physical</div><div class="box__body" style="font-family:var(--font-sans);">
            <b>How one engine stores it.</b><br><br>
            <span style="font-family:var(--font-mono); font-size:14px;">\\d orders</span> shows it: exact types (<span style="font-family:var(--font-mono); font-size:14px;">DECIMAL(10,2)</span>), exact constraints, defaults — and the index PostgreSQL built for the primary key.</div></div>
        </div>''',
    note="The conceptual level is Lecture 2's ER diagram. Run \\d orders live: the Indexes line shows orders_pkey, a unique btree index PostgreSQL creates automatically for every primary key (PostgreSQL docs, CREATE TABLE). Nobody asked for it — that's what 'physical' means.",
    source=f"{N}, Part 1; Wikipedia, “Data model” (three kinds, citing ANSI 1975); PostgreSQL 16 docs, CREATE TABLE")

content("A mistake costs more the further right", "Part 1 &middot; Data Models", "The further right, the more a change costs",
    f'<div class="diagram">{cost_svg()}</div>'
    '''<div class="callout callout--red" style="margin-top:6px; max-width:1000px;"><b>Physical mistakes</b>A VARCHAR(50) that turns out too short, or a SERIAL that should have been BIGINT, means an ALTER TABLE on live data — or worse.</div>''',
    note="This is why we draw before we type. On paper, a wrong arrow costs an eraser. In production, the same wrong decision costs an ALTER TABLE with real rows in the way (Lecture 2, Part 9). The bar heights show the direction, not measured costs.",
    source=f"{N}, Part 1; Lecture 2 notes, Part 9 (ALTER TABLE)")

# ---- Part 2 ----
section("02", "Part 2", "Dimensional modeling", "A second, purpose-built schema — for when the question shifts from “record what happened” to “summarize everything so far.”",
        "Same data, second shape. It sits alongside the normal tables; it does not replace them.")

content("Fact vs. dimension", "Part 2 &middot; Dimensional Modeling", "Facts are events. Dimensions are their context.",
    tbl(["", "Fact table", "Dimension table"],
        [["<b>Holds</b>", "an event, with numbers attached", "the context: who, what, where, when"],
         ["<b>One row per</b>", "thing that occurred — here, one order line", "customer, product, employee, day"],
         ["<b>In the demo</b>", mono("fact_sales"), mono("dim_date") + ", " + mono("dim_customer") + ", " + mono("dim_product") + ", " + mono("dim_employee")],
         ["<b>Typical columns</b>", mono("quantity, revenue, cost") + " + one key per dimension", "names, city, category, quarter — what you GROUP BY"]],
        cls="cmp"),
    note="The fact table is narrow and long: numbers plus keys. The dimensions are wide and short: descriptive labels. You add up facts; you group and filter by dimensions.",
    source=f"{N}, Part 2; Kimball Group, “Star Schemas and OLAP Cubes”; Wikipedia, “Star schema”")

statement("Grain", '''<div class="kicker">Part 2 &middot; Grain</div>
      <div class="big-line">“One row = one order line.”</div>
      <div class="stat-label" style="margin-top:20px; max-width:880px;">The <b>grain</b> is the one-sentence definition of what a single fact row <i>is</i> — decided <b>before</b> you build anything else. Get it wrong (an order's total copied onto each of its lines, by accident) and every aggregate on top silently means something else.</div>''',
    note="Kimball calls declaring the grain 'the pivotal step in a dimensional design': it establishes exactly what a single fact table row represents. Everything else — which dimensions, which measures — has to agree with that sentence. Grain comes back in Part 4 as the fan-out trap.",
    source=f"{N}, Part 2; Kimball Group, “Grain”")

content("dim_date: generated once", "Part 2 &middot; Build Tricks", "dim_date is generated once, not computed every query",
    '<div class="cols"><div class="col col--wide">' + code("""
CREATE TABLE dim_date AS
SELECT d::date                        AS dateKey,
       EXTRACT(quarter FROM d)::int   AS quarter,
       EXTRACT(month FROM d)::int     AS month,
       to_char(d, 'Mon')              AS monthName,
       EXTRACT(isodow FROM d)::int    AS dayOfWeek,
       to_char(d, 'Dy')               AS dayName
FROM generate_series(DATE '2024-01-01',
                     DATE '2024-12-31',
                     INTERVAL '1 day') AS d;""", size=16) + '''</div>
        <div class="col col--narrow"><div class="bignum">366</div><div class="bignum-label">rows — every day of 2024, a leap year. Sundays included, even though the shop is closed.</div>
        <ul class="points tight" style="margin-top:22px;"><li>Quarter, month, day name: computed <b>once</b>, stored as columns.</li><li>No query ever works out “what quarter is this date?” again.</li></ul></div></div>''',
    note="Calendars are cheap to precompute and expensive to keep recomputing. A date dimension lists every day, not only the days something happened — the same idea as the Chair and Levon: a table of events can't show what didn't happen. Kimball: calendar date dimensions are attached to virtually every fact table.",
    source=f"{D}, Part 6 (CREATE TABLE dim_date → SELECT 366); Kimball Group, “Calendar Date Dimensions”")

content("The unknown-member pattern", "Part 2 &middot; Build Tricks", "Make “missing” a value, not an absence",
    '<div class="cols"><div class="col">' + code("""
INSERT INTO dim_employee
VALUES (0, '(online)', 'Online', '(none)');""", size=17) +
    '<div class="result">and in the fact table build:</div>' + code("""
coalesce(o.employeeID, 0)   AS employeeKey""", size=17) + '''</div>
        <div class="col"><ul class="points">
          <li>Online orders have no employee: <code style="font-family:var(--font-mono);">employeeID IS NULL</code>.</li>
          <li>Row <b>0</b> gives them one. Every fact row now has a valid, non-null employee key.</li>
          <li>Every join to <code style="font-family:var(--font-mono);">dim_employee</code> is an ordinary join — never a “what if it's NULL” special case.</li>
        </ul>
        <div class="callout callout--green"><b>Payoff</b>Part 6 of the demo never needs LEFT JOIN against dim_employee. Plain inner joins lose nothing.</div></div></div>''',
    note="Why this avoids LEFT JOIN: an inner join drops a row only when it can't find a partner. With the unknown member, every fact row's employeeKey (0 for online) matches a real row in dim_employee, so the inner join finds a partner for all 965 fact rows and drops nothing. Compare Part 4: the same inner join against the raw employees table keeps 419 of 600. Kimball: nulls must be avoided in fact-table foreign keys; use a default row in the dimension instead.",
    source=f"{D}, Part 6; {N}, Part 2; Kimball Group, “Nulls in Fact Tables”")

# ---- Part 3 ----
section("03", "Part 3", "Star vs. snowflake schema", "Two shapes for the same facts. One of them is the default.",
        "Both are dimensional models. The only difference is what happens to the dimensions.")

content("Star schema", "Part 3 &middot; Star", "Star: one fact, flat dimensions around it",
    f'<div class="erwrap">{star_svg()}</div>',
    note="This is exactly what Part 6 of the demo builds: fact_sales in the middle, dim_date / dim_customer / dim_product / dim_employee attached directly, each dimension flat. Read one line aloud: one customer, many fact rows. Every 'by what?' is one join from the fact.",
    source=f"{D}, Part 6 (tables and columns); Kimball Group, “Star Schemas and OLAP Cubes”")

content("Snowflake schema", "Part 3 &middot; Snowflake", "Snowflake: a dimension split into sub-tables",
    f'<div class="erwrap">{snowflake_svg()}</div>',
    note="Same idea, but dim_product gets normalized into dim_product + dim_category + dim_brand, each joined in turn. The other dimensions stay flat here to show that snowflaking is per dimension. This split is the notes' example — the demo builds only the star.",
    source=f"{N}, Part 3 (the dim_category / dim_brand example); Kimball Group, “Snowflaked Dimensions”")

content("Star vs. snowflake", "Part 3 &middot; Comparison", "Less redundancy, more joins",
    tbl(["", "Star", "Snowflake"],
        [["<b>Dimension shape</b>", "one flat table per dimension", "a dimension split into sub-tables"],
         ["<b>Redundancy</b>", "category and brand repeated on every product row", "each category and brand stored once"],
         ["<b>Joins per query</b>", "one hop: fact → dimension", "one more hop per sub-table: fact → product → category"],
         ["<b>Navigability</b>", "one table per “by what?”", "analyst must know the chain of tables"],
         ["<b>Default?</b>", '<span style="color:var(--green-dark); font-weight:700;">yes</span>', '<span style="color:var(--red); font-weight:700;">only as an exception</span>']],
        cls="cmp"),
    note="Snowflaking buys less redundancy and costs more joins and more tables for an analyst to navigate — a bad trade most of the time. Wikipedia's article adds that dimension tables are usually small next to the fact table, so the space saved is often negligible.",
    source=f"{N}, Part 3; Kimball Group, “Snowflaked Dimensions”; Wikipedia, “Snowflake schema”")

statement("Kimball's guidance", '''<div class="kicker">Part 3 &middot; The Default</div>
      <div class="big-line">Star by default. Snowflake only as the exception — with a specific, concrete reason.</div>
      <div class="quote">“We generally encourage you to handle many-to-one hierarchical relationships in a single dimension table rather than snowflaking.” — Kimball Group, Design Tip #105</div>''',
    note="Kimball's reasons: snowflakes are harder for business users to understand and navigate, and can hurt query performance; a flat dimension holds the same information. Partial normalization ('outriggers') is 'acceptable in moderation', but 'the exception rather than the rule'. The notes' example of a reason is a genuinely huge dimension; note that Kimball himself calls the storage savings of snowflaking minimal.",
    source="Kimball Group, Design Tip #105, “Snowflakes, Outriggers, and Bridges” (2008); Kimball Group, “Snowflaked Dimensions”")

content("Snowflake: schema vs. product", "Part 3 &middot; Naming Trap", "“Snowflake” means two unrelated things",
    '''<div class="cols">
          <div class="col"><div class="panel"><div class="panel__head blue">snowflake schema</div><div class="panel__body"><ul class="points tight">
            <li>A <b>shape</b>: a dimensional model whose dimensions are normalized into sub-tables.</li>
            <li>What this Part is about.</li></ul></div></div></div>
          <div class="col"><div class="panel"><div class="panel__head">Snowflake Inc.</div><div class="panel__body"><ul class="points tight">
            <li>A <b>company</b> (founded 2012) selling a cloud data platform.</li>
            <li>You can build a star schema in it. The name is a coincidence.</li></ul></div></div></div>
        </div>''',
    note="Say it out loud in class: the schema shape and the product are unrelated. A job ad asking for 'Snowflake experience' means the product, not the schema shape.",
    source=f"{N}, Part 3; Wikipedia, “Snowflake Inc.”")

# ---- Part 4 ----
section("04", "Part 4", "JOINs, from one idea", "Not six keywords to memorize — one mental model that all six fall out of.",
        "Everything in this Part hangs off the next slide. If students keep one sentence from today, it's that one.")

statement("The one idea", '''<div class="kicker">Part 4 &middot; The Thesis</div>
      <div class="big-line">A join is: pair every row of A with every row of B, <em>then keep the pairs you want.</em></div>
      <div class="stat-label" style="margin-top:20px; max-width:860px;">Every join type is a variation on two questions: which pairs do we keep, and what do we do with the rows that found no pair?</div>''',
    note="That's genuinely it. It means CROSS JOIN isn't a weird separate thing — it's the whole Cartesian product before you've thrown anything away. We start there.",
    source=f"{N}, Part 4.0")

content("CROSS JOIN: every pair", "Part 4 &middot; Step 1 of 3", "CROSS JOIN: every row × every row",
    '<div class="cols"><div class="col">' + code("SELECT count(*) FROM orders CROSS JOIN customers;", size=17) +
    '''<div style="margin-top:22px;"><div class="bignum">18,000</div><div class="bignum-label">rows = 600 orders × 30 customers. Every possible pairing — most of them nonsense.</div></div>
        <p style="margin-top:18px; font:16px/1.5 var(--font-sans); color:var(--ink-soft);">PostgreSQL defines <code style="font-family:var(--font-mono);">A CROSS JOIN B</code> as exactly <code style="font-family:var(--font-mono);">A INNER JOIN B ON TRUE</code>: a join whose condition can never fail.</p></div>''' +
    f'<div class="col col--narrow" style="flex-basis:470px; justify-content:center;">{dotgrid("all")}</div></div>',
    note="Guess before running it. No order belongs to all 30 customers — this is every possible pairing. That's the point: it's the raw material every other join is carved out of. The grid zooms in on 3 orders × 3 customers; the real product is 600 × 30.",
    source=f"{D}, Part 3 (18000); PostgreSQL 16 docs, “Table Expressions: Joined Tables” (CROSS JOIN ≡ INNER JOIN ON TRUE; N × M rows)")

content("WHERE narrows the pairs", "Part 4 &middot; Step 2 of 3", "Filter the pairs with WHERE: 9 → 3",
    '<div class="cols"><div class="col col--wide">' + code("""
SELECT o.orderID, c.firstName, c.lastName
FROM orders o CROSS JOIN customers c
WHERE o.orderID IN (1001, 1002, 1003)
  AND c.customerID IN (2, 6, 26)
  AND o.customerID = c.customerID
ORDER BY o.orderID;""", size=16) + '''<div class="result">without the last condition: 9 rows · with it: 3 rows</div>''' +
    tbl(["orderid", "firstname", "lastname"], [["1001", "Davit", "Petrosyan"], ["1002", "Samvel", "Nazaryan"], ["1003", "Narek", "Manukyan"]], cls="cmp compact tight") +
    f'</div><div class="col col--narrow" style="flex-basis:470px; justify-content:center;">{dotgrid("match")}</div></div>',
    note="First run it without the last AND line: 9 rows, each order next to all three customers. Ask which three pairs are true. Then add o.customerID = c.customerID: 3 rows. The query in the demo also shows the 'order says' and 'customer row' columns side by side; this slide trims them to fit.",
    source=f"{D}, Part 3 (9 rows, then 3 rows)")

content("Same result as JOIN ... ON", "Part 4 &middot; Step 3 of 3", "Now write it as JOIN … ON — same 3 rows",
    '<div class="cols"><div class="col">' + code("""
SELECT o.orderID, c.firstName, c.lastName, o.orderTotal
FROM orders o
JOIN customers c ON c.customerID = o.customerID
WHERE o.orderID IN (1001, 1002, 1003)
ORDER BY o.orderID;""", size=16) +
    tbl(["orderid", "firstname", "lastname", "ordertotal"], [["1001", "Davit", "Petrosyan", "211.65"], ["1002", "Samvel", "Nazaryan", "249.00"], ["1003", "Narek", "Manukyan", "747.00"]], cls="cmp compact tight", style="margin-top:14px;") +
    '''</div><div class="col col--narrow" style="flex-basis:380px;"><div class="panel"><div class="panel__head blue">Why this order matters</div><div class="panel__body"><ul class="points tight">
          <li>Seen first, <b>JOIN … ON</b> looks like a magic combine-tables command.</li>
          <li>Seen <b>derived</b> from CROSS JOIN + WHERE, it's just filtered pairing.</li>
          <li>The database doesn't build all 18,000 pairs — but the answer is always the same as if it had.</li></ul></div></div></div></div>''',
    note="ON puts the matching condition next to the table it's about. JOIN alone means INNER JOIN. PostgreSQL's planner picks a nested-loop, merge or hash join by estimated cost, and every plan produces the same result — think the slow way, let the database do the fast one.",
    source=f"{D}, Part 3; {N}, Part 4.1; PostgreSQL 16 docs, “Planner/Optimizer” (every plan, same result)")

content("INNER JOIN: only the overlap", "Part 4 &middot; INNER JOIN", "INNER JOIN keeps only pairs that match",
    '<div class="vennrow">' + venn("inner") + '<div class="sidebox">' + code("""
SELECT count(*)
FROM orders o
JOIN customers c ON c.customerID = o.customerID
JOIN employees e ON e.employeeID = o.employeeID;""", size=16) +
    '''<div style="display:flex; gap:36px; margin-top:16px;"><div><div class="bignum">419</div><div class="bignum-label">rows, not 600</div></div>
        <div><div class="bignum bad">181</div><div class="bignum-label">online orders, gone: employeeID IS NULL matches nobody</div></div></div></div></div>
        <div class="callout callout--red" style="margin-top:14px;"><b>Drill this until it's automatic</b>An inner join doesn't complain when rows don't match — it just quietly leaves them out.</div>''',
    note="Anything on either side with no match simply disappears — no error, no placeholder, gone. The Venn picture shows which rows survive; it doesn't show how many rows come out (a join can also multiply rows — that's the fan-out trap later).",
    source=f"{D}, Part 4 (419); {N}, Part 4.2; PostgreSQL 16 docs, “Joined Tables” (INNER JOIN)")

statement("100,222.48 — a real sum, wrong", '''<div class="kicker">Part 4 &middot; INNER JOIN</div>
      <div class="stat">100,222.48</div>
      <div class="stat-label">“completed revenue”, after joining employees to get the names</div>
      <div class="stat-label" style="margin-top:22px; max-width:880px;">A real sum, correctly computed — over a silently incomplete set of rows. That's not a bug; it's the definition of inner join. It's just <b>invisible</b> unless you go looking.</div>''',
    note="The query: SELECT sum(o.orderTotal) FROM orders o JOIN employees e ON e.employeeID = o.employeeID WHERE o.status = 'completed'. Ask: what would make you suspicious of this number? Answer: nothing on screen — only knowing that online orders have no employee.",
    source=f"{D}, Part 4 (100222.48); {N}, Part 4.2")

content("Error: ambiguous column", "Part 4 &middot; Aliasing", "Two tables, one column name: ambiguous",
    code("""
SELECT orderID, customerID, firstName
FROM orders
JOIN customers ON customers.customerID = orders.customerID
WHERE orderID = 1001;""", size=17) +
    err('ERROR:  column reference "customerid" is ambiguous') +
    '''<ul class="points tight" style="margin-top:18px;"><li><b>customerID</b> exists in both tables; the engine refuses to guess — even though the values are equal on every joined row.</li>
        <li>Fix: alias the tables (<code style="font-family:var(--font-mono);">FROM orders o JOIN customers c</code>) and qualify: <code style="font-family:var(--font-mono);">o.customerID</code>.</li></ul>''',
    note="Error on purpose — read the message aloud. orderID and firstName exist in only one table, so they're fine. The rule is about names, not values. Habit: in any query with two tables, prefix every column, even the unambiguous ones.",
    source=f"{D}, Part 3 (error text from running it); {N}, Part 4.3")

content("Error: the alias replaced the name", "Part 4 &middot; Aliasing", "An alias doesn't add a nickname — it replaces the name",
    code("""
SELECT orders.orderID
FROM orders o
WHERE o.orderID = 1001;""", size=17) +
    err('ERROR:  invalid reference to FROM-clause entry for table "orders"\nHINT:  Perhaps you meant to reference the table alias "o".') +
    '''<p style="margin-top:18px; font:18px/1.5 var(--font-sans); color:var(--ink-soft); max-width:1000px;">Once you write <code style="font-family:var(--font-mono);">FROM orders o</code>, the name <code style="font-family:var(--font-mono);">orders</code> stops existing for the rest of that query. PostgreSQL's hint tells you exactly what happened.</p>''',
    note="Error on purpose. The HINT line is PostgreSQL telling you the fix. Same idea returns in self-joins, where aliases are the only way to tell two copies of one table apart.",
    source=f"{D}, Part 3 (error and hint text from running it); {N}, Part 4.3")

content("USING and NATURAL JOIN", "Part 4 &middot; Shorthand", "USING is shorthand. NATURAL JOIN hides the condition.",
    '<div class="cols"><div class="col">' + code("""
SELECT customerID, c.firstName, o.orderID
FROM orders o
JOIN customers c USING (customerID)
WHERE o.orderID = 1001;""", size=16) +
    '''<p style="margin-top:12px; font:16px/1.5 var(--font-sans); color:var(--ink-soft);"><b>USING (customerID)</b> = ON o.customerID = c.customerID, and the column appears once in the output.</p></div>
        <div class="col">''' + code("SELECT count(*)\nFROM orders NATURAL JOIN sales;", size=16) +
    '''<div style="margin-top:14px;"><div class="bignum bad">168</div><div class="bignum-label">rows — an honest join on orderID gives 965</div></div></div></div>
        <div class="callout callout--red" style="margin-top:14px;"><b>The join condition should always be visible in the code</b>NATURAL JOIN joined on every shared column name — orderID and eleven more, deliveryDate and rating among them. NULL = NULL is not true, so rows with a NULL there vanished. And it changes silently the day either table gains a column with a matching name. Never use it in real code.</div>''',
    note="Guess before revealing why 168. The two tables share nine column names; NATURAL JOIN requires all nine to be equal. deliveryDate is NULL for every in-store order, and a comparison with NULL is never true, so those rows are thrown out. Only online orders that also got a rating survive. The PostgreSQL manual itself calls NATURAL 'considerably more risky' than USING.",
    source=f"{D}, Part 3 (168); PostgreSQL 16 docs, “Joined Tables” (USING, NATURAL) and “Comparison Functions” (NULL comparisons)")

def outer_slide(dt, kind, title, codesql, nums, note, source, left="orders", right="employees"):
    content(dt, "Part 4 &middot; Outer Joins", title,
        '<div class="vennrow">' + venn(kind, left, right) + '<div class="sidebox">' + code(codesql, size=16) + nums + "</div></div>",
        note=note, source=source)

outer_slide("LEFT JOIN", "left", "LEFT JOIN: keep every row on the left", """
SELECT count(*)
FROM orders o
LEFT JOIN employees e ON e.employeeID = o.employeeID;""",
    '''<div style="display:flex; gap:36px; margin-top:16px;"><div><div class="bignum good">600</div><div class="bignum-label">rows — the 181 online orders survive, with the employee columns NULL</div></div></div>
       <p style="margin-top:12px; font:16px/1.5 var(--font-sans); color:var(--ink-soft);">Group by <code style="font-family:var(--font-mono);">coalesce(e.branch, 'Online')</code> and online revenue lands in a visible “Online” bucket: <b>56,855.93</b> of completed revenue, the largest of the four.</p>''',
    "INNER JOIN, but we refuse to lose rows from the left side. Where there's no match on the right, the row stays and the right-hand columns are NULL. 'Left' just means the table written before the word JOIN. Branch revenue (completed): Online 56,855.93; Yerevan Center 51,758.15; Yerevan Mall 38,008.16; Gyumri 10,456.17.",
    f"{D}, Part 4 (600; revenue per branch); PostgreSQL 16 docs, “Joined Tables” (LEFT OUTER JOIN)")

outer_slide("RIGHT JOIN", "right", "RIGHT JOIN: the mirror image", """
SELECT count(*)
FROM orders o
RIGHT JOIN customers c ON c.customerID = o.customerID;""",
    '''<div style="display:flex; gap:36px; margin-top:16px;"><div><div class="bignum">602</div><div class="bignum-label">rows: all 600 orders, plus one NULL-padded row for each of the 2 customers who never ordered</div></div></div>
       <p style="margin-top:12px; font:16px/1.5 var(--font-sans); color:var(--ink-soft);">Exactly the same as <code style="font-family:var(--font-mono);">customers LEFT JOIN orders</code>. Keep the table you care about on the left and you never need RIGHT.</p>''',
    "A RIGHT JOIN B keeps every row of B, which makes it B LEFT JOIN A. Writing LEFT always is this course's style choice, so every query reads the same way — know RIGHT for when you meet it in someone else's code.",
    f"{D}, Part 4 (602); PostgreSQL 16 docs, “Joined Tables” (RIGHT OUTER JOIN)", left="orders", right="customers")

outer_slide("FULL JOIN", "full", "FULL JOIN: keep everything from both sides", """
SELECT CASE WHEN e.employeeID IS NULL THEN 'customer only'
            WHEN c.customerID IS NULL THEN 'employee only'
            ELSE 'on both lists' END AS status,
       count(*) AS people
FROM customers c
FULL JOIN employees e
  ON e.firstName = c.firstName AND e.lastName = c.lastName
GROUP BY 1 ORDER BY 1;""",
    tbl(["status", "people"], [["customer only", "28"], ["employee only", "6"], ["on both lists", "2"]], cls="cmp compact tight", style="margin-top:12px; max-width:420px;"),
    "LEFT and RIGHT combined. Its classic use is reconciling two lists — bank statement against ledger. 28 + 6 + 2 = 36 people. Hold on to those 2 'on both lists': it's the name-collision trap coming up.",
    f"{D}, Part 4 (28 / 6 / 2); PostgreSQL 16 docs, “Joined Tables” (FULL OUTER JOIN)", left="customers", right="employees")

content("Anti-join: which X have no Y?", "Part 4 &middot; Outer Joins", "The anti-join: LEFT JOIN + IS NULL",
    '<div class="cols"><div class="col">' + code("""
SELECT c.customerID, c.firstName, c.lastName
FROM customers c
LEFT JOIN orders o ON o.customerID = c.customerID
WHERE o.orderID IS NULL;""", size=16) +
    tbl(["customerid", "firstname", "lastname"], [["24", "Levon", "Arakelyan"], ["29", "Astghik", "Danielyan"]], cls="cmp compact tight", style="margin-top:12px;") +
    '''</div><div class="col"><div style="display:flex; gap:40px;">
          <div><div class="bignum">2</div><div class="bignum-label">of 30 customers with zero orders</div></div>
          <div><div class="bignum">1</div><div class="bignum-label">of 37 products never ordered: #35 Ergonomic Chair Pro, Chairs, 6 in stock</div></div></div>
        <ul class="points tight" style="margin-top:22px;"><li>A real match would fill the right-hand columns. NULL there means: <b>nothing matched</b>.</li>
        <li>Test the right table's <b>key</b> — a primary key is never NULL in a real row.</li></ul></div></div>''',
    note="Teach it as a named pattern, not a clever trick. 'Which X have no Y' comes up constantly: customers with no orders, products never sold, employees with no reports. The flat sales table could never answer this: a table of sales only contains things that sold.",
    source=f"{D}, Part 4 (anti-join queries); {N}, Part 4.5")

content("count(*) vs count(column)", "Part 4 &middot; Sanity Check", "count(*) counts rows. count(column) counts non-NULLs.",
    '<div class="cols"><div class="col">' + code("""
SELECT c.firstName, count(*) AS orders
FROM customers c
LEFT JOIN orders o
  ON o.customerID = c.customerID
GROUP BY c.customerID, c.firstName;""", size=16) +
    tbl(["firstname", "orders"], [["Levon", '<b style="color:var(--red);">1</b>'], ["Astghik", '<b style="color:var(--red);">1</b>']], cls="cmp compact tight", style="margin-top:12px;") +
    '</div><div class="col">' + code("""
SELECT c.firstName, count(o.orderID) AS orders
FROM customers c
LEFT JOIN orders o
  ON o.customerID = c.customerID
GROUP BY c.customerID, c.firstName;""", size=16) +
    tbl(["firstname", "orders"], [["Levon", '<b style="color:var(--green-dark);">0</b>'], ["Astghik", '<b style="color:var(--green-dark);">0</b>']], cls="cmp compact tight", style="margin-top:12px;") +
    '</div></div><div class="callout callout--green" style="margin-top:14px;"><b>A reflex, not a trick</b>After every outer join, run both. They should diverge exactly at the unmatched rows — if they don\'t, something about the join is wrong.</div>',
    note="Levon has no orders, but the LEFT JOIN gave him one row full of NULLs, and count(*) counts rows. count(o.orderID) skips the NULL. The demo query also orders by the count and shows Diana (4) and Lusine (5), where both versions agree.",
    source=f"{D}, Part 4 (count queries); PostgreSQL 16 docs, “Aggregate Functions” (count(*) vs count(expr))")

content("WHERE vs ON: the rule", "Part 4 &middot; The Most Important Trap", "WHERE vs. ON: it depends on when each runs",
    tbl(["", "ON", "WHERE"],
        [["<b>Runs</b>", "<b>while</b> deciding what matches — before NULL-padding", "<b>after</b> the whole join, NULL-padding included"],
         ["<b>Inner join</b>", "same result", "same result"],
         ["<b>Outer join</b>", "keeps the unmatched rows", '<span style="color:var(--red); font-weight:700;">can delete the NULL-padded rows — the LEFT JOIN becomes an INNER JOIN</span>']],
        cls="cmp") +
    '''<p style="margin-top:18px; font:18px/1.5 var(--font-sans); color:var(--ink-soft); max-width:1000px;">A <code style="font-family:var(--font-mono);">WHERE</code> that mentions the right-hand table after a LEFT JOIN should always make you stop and ask: am I filtering matches, or un-inviting the rows my LEFT JOIN was supposed to protect?</p>''',
    note="With inner joins only, it genuinely doesn't matter where a condition lives. With outer joins it matters completely. The PostgreSQL manual says it directly: a restriction in ON is processed before the join, one in WHERE after the join — 'That does not matter with inner joins, but it matters a lot with outer joins.'",
    source=f"{N}, Part 4.7; PostgreSQL 16 docs, “Joined Tables” (ON vs. WHERE with outer joins)")

CATS12 = [["Laptops", "46", "53412.00"], ["Phones", "38", "25991.90"], ["Audio", "78", "19038.90"], ["…", "…", "…"], ["Printers", "13", "2408.65"], ["Networking", "17", "2225.75"]]
content("WHERE version: 12 rows", "Part 4 &middot; WHERE vs. ON · 1", "Filter in WHERE → 12 rows, Chairs gone",
    '<div class="cols"><div class="col col--wide">' + code("""
SELECT p.category, count(i.orderID) AS lines,
       sum(i.lineTotal) AS revenue
FROM products p
LEFT JOIN order_items i ON i.productID = p.productID
LEFT JOIN orders      o ON o.orderID   = i.orderID
WHERE o.status = 'completed'
GROUP BY p.category
ORDER BY revenue DESC NULLS LAST;""", size=16) + '''</div>
        <div class="col">''' + tbl(["category", "lines", "revenue"], CATS12, cls="cmp compact tight") +
    '''<div class="bignum bad" style="margin-top:14px;">12 rows</div><div class="bignum-label">no Chairs row</div></div></div>''',
    note="Walk the execution order: the LEFT JOIN runs first and keeps the Chair row, with o.status NULL. Then WHERE runs: NULL = 'completed' is not true, and the Chair row is thrown out along with the genuinely non-completed rows. No error. Middle rows omitted to fit; full output in the demo.",
    source=f"{D}, Part 4 (12 rows)")

statement("ON invites, WHERE decides who stays", '''<div class="kicker">Part 4 &middot; WHERE vs. ON</div>
      <div class="big-line"><em>ON</em> decides who gets invited to the party. <em>WHERE</em> decides who's allowed to stay after it already happened.</div>
      <div class="stat-label" style="margin-top:20px; max-width:880px;">…including the guests the LEFT JOIN invited for free — the NULL-padded ones.</div>''',
    note="Use this line verbatim. The NULL-padded Chair row was a guest the LEFT JOIN invited for free; the WHERE clause showed it the door. Moving the condition into ON means it's only used to decide who matches — nobody gets thrown out afterwards.",
    source=f"{N}, Part 4.7")

CATS13 = [["Laptops", "46", "53412.00"], ["Phones", "38", "25991.90"], ["…", "…", "…"], ["Networking", "17", "2225.75"], ['<b style="color:var(--green-dark);">Chairs</b>', '<b style="color:var(--green-dark);">0</b>', '<b style="color:var(--green-dark);">0</b>']]
content("ON version: 13 rows", "Part 4 &middot; WHERE vs. ON · 2", "Decide the match first → 13 rows, Chairs at 0",
    '<div class="cols"><div class="col col--wide">' + code("""
SELECT p.category, count(i.orderID) AS lines,
       coalesce(sum(i.lineTotal), 0) AS revenue
FROM products p
LEFT JOIN (order_items i
           JOIN orders o ON o.orderID = i.orderID
                        AND o.status  = 'completed')
       ON i.productID = p.productID
GROUP BY p.category
ORDER BY revenue DESC;""", size=16) + '''</div>
        <div class="col">''' + tbl(["category", "lines", "revenue"], CATS13, cls="cmp compact tight") +
    '''<div class="bignum good" style="margin-top:14px;">13 rows</div><div class="bignum-label">Chairs present, revenue 0</div></div></div>''',
    note="In a chain of joins, ask which join the condition belongs to: putting o.status = 'completed' in the ON of the orders join brings Chairs back but keeps every line of returned orders, so revenue is wrong (Laptops 58,028.50 instead of 53,412.00). The brackets build the match first. Rule to remember: conditions on the right table of a LEFT JOIN go in ON; conditions on the left table go in WHERE. coalesce turns the NULL sum into 0: sum of no rows is NULL, not zero (PostgreSQL docs, Aggregate Functions).",
    source=f"{D}, Part 4 (13 rows); PostgreSQL 16 docs, “Aggregate Functions” (sum of no rows is NULL)")

content("Self-join: direct manager", "Part 4 &middot; Self-Joins", "Self-join: one table, two roles",
    '<div class="cols"><div class="col">' + code("""
SELECT e.firstName || ' ' || e.lastName AS employee,
       m.firstName || ' ' || m.lastName AS manager
FROM employees e
LEFT JOIN employees m
       ON m.employeeID = e.managerID;""", size=15) +
    '''<div style="margin-top:14px;"><div class="bignum">8</div><div class="bignum-label">rows — every employee, including Vahe, whose manager is NULL</div></div>
        <ul class="points tight" style="margin-top:14px;"><li><b>e</b> plays the employee, <b>m</b> the manager — same table.</li><li>Aliases are mandatory: unaliased, it's an error.</li><li><b>LEFT</b>, or the top of the hierarchy disappears.</li></ul></div>''' +
    f'<div class="col" style="justify-content:center;">{orgchart2()}</div></div>',
    note="Error on purpose first if time allows: FROM employees JOIN employees → ERROR: table name \"employees\" specified more than once. The demo's version also selects e.position and orders by manager. Any hierarchy stored as 'this table points to itself' — org charts, category trees, comment replies — uses this exact shape.",
    source=f"{D}, Part 5 (8 rows); lecture_4/steps/00-setup.sql (managerID values)")

content("Self-join: two hops, and counts", "Part 4 &middot; Self-Joins", "Two more self-joins: a second hop, and a count",
    '<div class="cols"><div class="col">' + code("""
SELECT e.firstName AS employee,
       m.firstName AS manager,
       mm.firstName AS managers_manager
FROM employees e
LEFT JOIN employees m  ON m.employeeID  = e.managerID
LEFT JOIN employees mm ON mm.employeeID = m.managerID
WHERE e.branch <> 'Yerevan Center';""", size=14) +
    tbl(["employee", "manager", "managers_manager"], [["Hayk", "Vahe", ""], ["Marine", "Vahe", ""], ["Nare", "Hayk", "Vahe"], ["Lilit", "Hayk", "Vahe"], ["Arman", "Marine", "Vahe"]], cls="cmp compact tight", style="margin-top:10px;") +
    '</div><div class="col">' + code("""
SELECT m.firstName || ' ' || m.lastName AS manager,
       count(e.employeeID) AS direct_reports
FROM employees m
JOIN employees e ON e.managerID = m.employeeID
GROUP BY m.employeeID, m.firstName, m.lastName
ORDER BY direct_reports DESC;""", size=14) +
    tbl(["manager", "direct_reports"], [["Vahe Sahakyan", "4"], ["Hayk Melikyan", "2"], ["Marine Avagyan", "1"]], cls="cmp compact tight", style="margin-top:10px;") +
    '</div></div>',
    note="Manager's manager: 5 rows (the WHERE keeps the employees outside Yerevan Center). Report count: 3 rows — only people who manage someone appear, because this one is an inner join. 'All the way up, however many levels' would need one more join per level.",
    source=f"{D}, Part 5 (5 rows; 3 rows)")

content("Names are not identifiers", "Part 4 &middot; Joining on the Wrong Thing", "Names are not identifiers",
    '<div class="cols"><div class="col col--wide">' + code("""
SELECT c.firstName, c.lastName,
       c.birthDate AS customer_born, e.birthDate AS employee_born
FROM customers c
JOIN employees e ON e.firstName = c.firstName
                AND e.lastName  = c.lastName;""", size=15) +
    tbl(["name", "customer_born", "employee_born"], [["Hayk Melikyan", "1993-03-30", "1985-02-11"], ["Lilit Hovhannisyan", "1990-06-14", "1998-07-07"]], cls="cmp compact tight", style="margin-top:10px;") +
    '''</div><div class="col"><div class="bignum bad">2</div><div class="bignum-label">“matches” — four different people who share two names</div>
        <div class="bignum bad" style="margin-top:18px;">1,036</div><div class="bignum-label">rows from joining <code style="font-family:var(--font-mono);">sales</code> to <code style="font-family:var(--font-mono);">customers</code> by name — not 600. Each Anna Sargsyan row matched both Annas.</div></div></div>
        <div class="callout callout--red" style="margin-top:12px;"><b>One-line lesson</b>Only join on something guaranteed unique — a real key. Anything that merely “usually” identifies a row will eventually produce a false match, and the join won't warn you.</div>''',
    note="These are the 2 'on both lists' from the FULL JOIN slide. The birth dates prove they're different people. Lecture 2 said it with two Annas: names are not keys. The honest answer to 'which employees also shop here?' is: this data can't tell.",
    source=f"{D}, Part 5 (2 rows; 1036); {N}, Part 4.9")

statement("Fan-out: the number", '''<div class="kicker">Part 4 &middot; The Fan-Out Trap</div>
      <div class="stat-label">Total lifetime spend of our customers:</div>
      <div class="stat" style="margin-top:10px;">4,386,925.27</div>
      <div style="margin-top:18px; text-align:left;">''' + code("""
SELECT sum(c.moneySpent) AS total_customer_spend
FROM customers c
JOIN orders o ON o.customerID = c.customerID;""", size=17) + '''</div>''',
    note="Present it as if it were a real answer. Ask the room whether it looks plausible. It's a completely ordinary inner join — no outer join, no strange join type. That's why this is the most damaging trap: nothing about the query looks wrong. The real total, SELECT sum(moneySpent) FROM customers, is 157,078.41.",
    source=f"{D}, Part 5 (4386925.27)")

content("Fan-out: why", "Part 4 &middot; The Fan-Out Trap", "One customer value, copied onto every order row",
    f'<div class="diagram">{fanout_svg()}</div>'
    '''<ul class="points tight"><li><b>customers.moneySpent</b> is one number per customer — customer grain.</li>
        <li><b>orders</b> has many rows per customer — order grain. The join copies moneySpent onto every one of them: not divided, not split, <b>copied whole</b>.</li></ul>''',
    note="Aram placed 40 orders, so his 14,625.38 is summed 40 times. Do that for every customer and you get 4,386,925.27. This is Lecture 3's grain lesson again: after this join, the result has one row per order, not one per customer.",
    source=f"{D}, Part 5; customers.moneySpent and order counts from the lecture data (Aram Vardanyan: 40 orders)")

content("Fan-out: the proof", "Part 4 &middot; The Fan-Out Trap", "Count before you sum",
    '<div class="cols"><div class="col">' + code("""
SELECT count(*) AS rows,
       count(DISTINCT c.customerID) AS customers
FROM customers c
JOIN orders o ON o.customerID = c.customerID;""", size=16) +
    '''<div style="display:flex; gap:40px; margin-top:16px;"><div><div class="bignum bad">600</div><div class="bignum-label">rows summed</div></div>
        <div><div class="bignum">28</div><div class="bignum-label">real customers with orders</div></div></div></div>
        <div class="col"><div class="panel"><div class="panel__head blue">The fix, in general</div><div class="panel__body"><ul class="points tight">
          <li>Aggregate the fine-grain table first, then join the <b>result</b> back — one row per customer.</li>
          <li>Or don't join at all if you already have the summary value: <code style="font-family:var(--font-mono);">SELECT sum(moneySpent) FROM customers</code>.</li></ul></div></div></div></div>''',
    note="Every customer's moneySpent got summed once per order they placed, not once in total. 600 rows vs 28 customers is the tell. The two customers with no orders don't appear at all, because this is an inner join.",
    source=f"{D}, Part 5 (600 / 28); {N}, Part 4.10")

statement("Fan-out: the question to ask", '''<div class="kicker">Part 4 &middot; The Fan-Out Trap</div>
      <div class="big-line">“Is the thing I'm summing at the same grain as the rows I'm joining through?”</div>
      <div class="stat-label" style="margin-top:20px; max-width:860px;">If not: am I about to sum the same value multiple times?</div>''',
    note="Ask it every time you aggregate after a join. It's the grain from Part 2, applied to a query instead of a schema.",
    source=f"{N}, Part 4.10")

content("ON with a range condition", "Part 4 &middot; Non-Equality Joins", "ON isn't limited to =",
    '<div class="cols"><div class="col col--wide">' + code("""
SELECT b.band, count(*) AS orders, sum(o.orderTotal) AS revenue
FROM orders o
JOIN (VALUES ('1. under 50',  0,    50),
             ('2. 50 - 299',  50,   300),
             ('3. 300 - 999', 300,  1000),
             ('4. 1000+',     1000, 100000)) AS b(band, low, high)
  ON o.orderTotal >= b.low AND o.orderTotal < b.high
WHERE o.status = 'completed'
GROUP BY b.band ORDER BY b.band;""", size=14) + '</div><div class="col">' +
    tbl(["band", "orders", "revenue"], [["1. under 50", "121", "3193.18"], ["2. 50 - 299", "251", "35595.33"], ["3. 300 - 999", "120", "66244.24"], ["4. 1000+", "37", "52045.66"]], cls="cmp compact tight") +
    '''<p style="margin-top:14px; font:16px/1.5 var(--font-sans); color:var(--ink-soft);">Bucketing done natively in SQL: each order lands in the band where <code style="font-family:var(--font-mono);">low &lt;= orderTotal &lt; high</code> — no CASE per row.</p></div></div>''',
    note="VALUES builds a small table inline. The condition is a range, not key = key — the same machinery: every combination, keep the pairs that pass. Tax brackets and commission tiers are joins like this.",
    source=f"{D}, Part 5 (price-band query)")

statement("A document is a join you saved", '''<div class="kicker">Part 4 &middot; Bridge</div>
      <div class="big-line">A document is a join <em>you saved</em>.</div>
      <div class="stat-label" style="margin-top:20px; max-width:900px;">A denormalized JSON document is the materialized result of a one-to-many join. The relational model keeps the pieces separate and joins on demand; the document model pre-joins once and stores the result. Same information — different point where the join cost gets paid.</div>''',
    note="The demo builds one JSON document per customer with jsonb_agg: all of Diana's orders nested inside her customer object. Reading it back is fast; keeping it right when Diana moves city is the application's problem.",
    source=f"{N}, Part 4.12; {D}, Part 5 (jsonb_agg query)")

content("Proving the split was lossless", "Part 4 &middot; Losslessness", "A runnable proof that nothing was lost",
    code("""
SELECT o.orderID, o.orderDate, …, i.lineTotal, …, p.price, p.cost
FROM orders o
JOIN      order_items i ON i.orderID    = o.orderID
JOIN      customers   c ON c.customerID = o.customerID
JOIN      products    p ON p.productID  = i.productID
LEFT JOIN employees   e ON e.employeeID = o.employeeID
EXCEPT
SELECT * FROM sales;""", size=16) +
    '''<div style="display:flex; gap:48px; align-items:flex-start; margin-top:16px;"><div><div class="bignum good">0 rows</div><div class="bignum-label">in both directions</div></div>
        <p style="flex:1; font:17px/1.5 var(--font-sans); color:var(--ink-soft); margin:0;">Rebuild the flat file from the five tables, subtract the original: nothing left over. Swap the two halves: nothing again. That's <b>lossless-join decomposition</b> — as a query you can run, not a theory term.</p></div>''',
    note="The full SELECT lists all 30 columns of sales; the slide abbreviates it. The LEFT JOIN to employees matters, or the web shop is lost. EXCEPT compares whole rows and treats two NULLs as equal (the manual states that rule for DISTINCT; the 0-row result shows EXCEPT does the same).",
    source=f"{D}, Part 4 (0 rows); PostgreSQL 16 docs, “Select Lists” (NULLs equal for DISTINCT)")

content("GROUP BY column order", "Part 4 &middot; Myth", "GROUP BY a, b = GROUP BY b, a",
    '''<div class="cols"><div class="col">''' + code("GROUP BY c.customerID, c.firstName, c.lastName", size=16) +
    '<div style="height:10px;"></div>' + code("GROUP BY c.lastName, c.firstName, c.customerID", size=16) +
    '''<div class="result">→ the same groups, the same totals</div></div>
        <div class="col"><ul class="points">
          <li>A group is defined by the <b>combination</b> of values in the listed columns. The order you list them in changes nothing.</li>
          <li>If a total looks wrong, GROUP BY order is not the place to look — check for a <b>fan-out</b> first.</li></ul></div></div>''',
    note="PostgreSQL's definition: GROUP BY groups together the rows that have the same values in all the columns listed. 'All the columns listed' is a set, not a sequence. (The order of output rows is decided by ORDER BY, not GROUP BY.)",
    source=f"{N}, Part 4.14; PostgreSQL 16 docs, “Table Expressions: GROUP BY”")

# ---- closing ----
statement("Three silent traps, one root cause", '''<div class="kicker">The One Idea to Leave With</div>
      <div class="big-line" style="font-size:34px;">NATURAL JOIN <em>965 → 168</em> · WHERE vs. ON <em>13 → 12</em> · fan-out <em>→ 4,386,925.27</em></div>
      <div class="stat-label" style="margin-top:24px; max-width:900px;">None of them threw an error. All three returned a table that looked completely normal. <b>SQL correctness bugs are almost always silent</b> — and an AI assistant will write a plausible, syntactically perfect join whether the logic is right or not.</div>''',
    note="Nothing turns red. The query runs, returns rows, and is simply wrong. That's the whole point of this lecture.",
    source=f"{N}, Part 5")

content("Checks to run after any join", "Takeaway", "The checks that catch a wrong-but-plausible answer",
    '''<table class="vocab"><thead><tr><th style="width:360px;">Check</th><th>Catches</th></tr></thead><tbody>
          <tr><td class="term">row count before / after</td><td>an inner join dropping rows (600 → 419); a join multiplying them (965 → 1,036)</td></tr>
          <tr><td class="term">count(*) vs count(col)</td><td>empty matches after an outer join (Levon: 1 vs 0)</td></tr>
          <tr><td class="term">count(DISTINCT key)</td><td>fan-out: 600 rows but only 28 customers</td></tr>
          <tr><td class="term">symmetric difference</td><td>anything lost or invented: EXCEPT both ways against a known-correct source → 0 rows</td></tr>
        </tbody></table>
        <div class="callout callout--green" style="margin-top:18px;"><b>Not a side skill</b>For anyone using AI to write SQL, this is the actual skill.</div>''',
    note="Each check is independent of the query it tests, which is what makes it a check. Run them every time, before trusting anything downstream.",
    source=f"{N}, Part 5; numbers from {D}, Parts 4–5")

content("Next lecture", "Next Lecture", "Queries inside queries",
    '''<ul class="points">
          <li>The fan-out fix — “aggregate first, then join the result” — needs a query inside a query.</li>
          <li><b>Subqueries</b>, and saving a query under a name so everyone asks the same question the same way.</li>
        </ul>''',
    note="Good place to stop and take questions.")

content("Sources", "Sources", "Where every claim comes from",
    '''<ol class="refs">
          <li>lecture-04-notes.md and lecture-04-demo.sql — every number on these slides is the demo's verified output.</li>
          <li>PostgreSQL 16 documentation: “Table Expressions” (Joined Tables, GROUP BY), CREATE TABLE, “Comparison Functions”, “Aggregate Functions”, “Select Lists”, “Planner/Optimizer”. postgresql.org/docs/16</li>
          <li>Kimball Group, Dimensional Modeling Techniques: “Star Schemas and OLAP Cubes”, “Grain”, “Calendar Date Dimensions”, “Nulls in Fact Tables”, “Snowflaked Dimensions”. kimballgroup.com</li>
          <li>Kimball Group, Design Tip #105, “Snowflakes, Outriggers, and Bridges” (2008). kimballgroup.com/2008/09/design-tip-105-snowflakes-outriggers-and-bridges</li>
          <li>Wikipedia: “Data model”, “Star schema”, “Snowflake schema”, “Snowflake Inc.”</li>
          <li>Lecture 2 notes (ER diagrams, normal forms, ALTER TABLE) and Lecture 3 notes (grain).</li>
        </ol>''',
    note="Hand this slide out with the deck.")

# ---- assemble ------------------------------------------------------------------
out = f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Putting the Tables Back Together — Lecture 4</title>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>{STYLE}{EXTRA_CSS}</style>
</head>
<body>
<div class="deck" id="deck">
  <div class="viewport-fit" id="viewportFit">

    {chr(10).join("    " + s for s in slides)}

  </div>
</div>

<div class="chrome"><div class="chrome__bar" id="bar"></div></div>
<div class="counter" id="counter">1 / 1</div>
<div class="deckname">Lecture 4 &middot; Putting the Tables Back Together</div>
<div class="notes-bar" id="notesBar"><b>Speaker note</b><div id="notesText"></div></div>
<div class="overview" id="overview"><div class="overview__grid" id="overviewGrid"></div></div>

{SCRIPT}
</body>
</html>
'''
(HERE / "../lecture-04-slides.html").write_text(out)
print(len(slides), "slides")
