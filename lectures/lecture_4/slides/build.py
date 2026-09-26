#!/usr/bin/env python3
"""
Lecture 4 slide deck generator (dark, code-first).

    python3 build.py      # writes project/deck.json and project/slides/*.html

Follows lecture-04-notes.md Part by Part. Every number on a slide comes
from the verified run of the notes. SQL lives in the speaker notes, not
on the slides: the queries are shown live in psql.
"""
import json, html
from pathlib import Path

ROOT = Path(__file__).parent / "project"
SLIDES = ROOT / "slides"
SLIDES.mkdir(parents=True, exist_ok=True)
for f in SLIDES.glob("*.html"):
    f.unlink()

# ---- palette & type ---------------------------------------------------------
BG, SURF, SURF2, LINE = "#0E1116", "#161B22", "#1C2430", "#30363D"
FG, SOFT, FAINT = "#E6EDF3", "#A3AEBB", "#7D8793"
GREEN, AMBER, RED, BLUE = "#7EE787", "#F2CC60", "#FF7B72", "#79C0FF"
MONO = "'JetBrains Mono', 'Courier New', monospace"
SANS = "'IBM Plex Sans', Arial, sans-serif"

order, sections = [], {}

# Mermaid diagrams (diagrams/*.mmd, rendered to PNG and uploaded to the deck)
ASSET = {
    "document": "/_blob/985fda942a9ada7011a764c0ba8c31ce",
    "graph": "/_blob/b05414f33e79b03afe5b704375eb9788",
    "hierarchical": "/_blob/c799f056d62bf0b656e1ef9e460133ea",
    "keyvalue": "/_blob/f2cb67b4eed4c38bc5a626158646baac",
    "levels-conceptual": "/_blob/cdcbf76bf00f9eb9f587b3db87ff5135",
    "levels-logical": "/_blob/b5a130075ef75cd2987bef585f10e150",
    "network": "/_blob/862994b32a1fb4678c3d975cda384b27",
    "normalized": "/_blob/2953938cb495558bac7d8be312f4ec25",
    "order_items": "/_blob/ebc2fb13af16518936be82176d22038c",
    "snowflake": "/_blob/87bce61777981485e499c245a91c6563",
    "star-build": "/_blob/a53350b4ce95aee08ab46dce15c3547b",
    "star": "/_blob/cd9462e8de640e09730fe9fffc06cb57",
}

# One footer per slide. Full references: footnotes in lecture-04-notes.md.
SRC = {
    "left-off": "Source: lecture-04-notes.md Part 4 (anti-join queries); Lecture 3 notes, Part 5 (the two Annas)",
    "dm-def": "Source: E. F. Codd, “Data Models in Database Management”, ACM SIGMOD Record 11(2), 1981",
    "dm-levels": "Sources: Wikipedia, “Data model” (conceptual / logical / physical, citing ANSI 1975); PostgreSQL 16 docs, CREATE TABLE (automatic primary-key index)",
    "dm-hier": "Sources: Wikipedia, “Hierarchical database model” and “IBM Information Management System”; orders 1001 and 1002 from the sales table",
    "dm-network": "Sources: Wikipedia, “CODASYL” (network-model spec, 1969); C. W. Bachman, “The Programmer as Navigator”, CACM 16(11), 1973",
    "dm-relational": "Source: E. F. Codd, “A Relational Model of Data for Large Shared Data Banks”, CACM 13(6):377–387, 1970; rows from orders and customers",
    "dm-document": "Sources: Wikipedia, “MongoDB” (2009, JSON-like documents); Davit’s 52 orders: SELECT count(*) FROM orders WHERE customerID = 2",
    "dm-kv": "Source: AWS, “What is a key-value database?” (sessions, carts, caching). The keys and values drawn here are illustrations, not our data",
    "dm-graph": "Source: Neo4j docs, “What is a graph database?”; reporting line from steps/00-setup.sql; purchases are orders 1001 and 1002",
    "dm-compare": "Sources: the sources on the six previous slides",
    "dm-why": "Sources: Wikipedia, “Relational model” (declarative queries); MongoDB Manual, “Database References” (the application resolves references)",
    "sc-oltp": "Source: Wikipedia, “Online analytical processing” (OLAP vs OLTP; term coined by E. F. Codd, 1993)",
    "sc-normalized": "Sources: Lecture 2 notes, Part 2 (normal forms); lecture_4/steps/00-setup.sql (tables and keys)",
    "sc-flat": "Sources: rows of the sales table (orders 1001–1003, 1094, 1100); Lecture 2 notes, Part 1 (update anomaly)",
    "sc-star": "Sources: Kimball Group, Dimensional Modeling Techniques: “Star Schemas”, “Grain”; Wikipedia, “Star schema”",
    "sc-snowflake": "Sources: Kimball Group, “Snowflaked Dimensions”; Wikipedia, “Snowflake schema”",
    "sc-rules": "This course’s rule of thumb (not a published standard), based on Wikipedia, “Extract, transform, load”",
    "sc-items": "Sources: Lecture 2 notes, Part 2 (junction table, 2NF); lecture-04-notes.md Part 2 (INSERT 0 600; 0 multi-line orders)",
    "j-ids": "Source: lecture-04-notes.md Part 3, first query",
    "j-pairs": "Sources: PostgreSQL 16 docs, “Joined Tables” (cross join = N × M rows) and “Planner/Optimizer” (every plan, same result); Part 3 queries",
    "j-names": "Sources: PostgreSQL 16 docs, “Joined Tables” (USING, NATURAL); the error text is from running the Part 3 query",
    "j-natural": "Sources: PostgreSQL 16 docs, “Joined Tables” (NATURAL) and “Comparison Functions” (NULL = NULL is null); 97 from Part 3",
    "j-order": "Source: PostgreSQL 16 docs, SELECT → Description (the order a query is processed in)",
    "o-inner-left": "Sources: PostgreSQL 16 docs, “Joined Tables” (LEFT OUTER JOIN); 419 / 600 from lecture-04-notes.md Part 4",
    "o-anti": "Source: lecture-04-notes.md Part 4 (anti-join queries)",
    "o-count": "Sources: PostgreSQL 16 docs, “Aggregate Functions” (count(*) vs count(expr)); counts from lecture-04-notes.md Part 4",
    "o-where-on": "Sources: PostgreSQL 16 docs, “Joined Tables” (ON is processed before the join, WHERE after); 12 / 13 rows from Part 4",
    "o-types": "Sources: PostgreSQL 16 docs, “Joined Tables”; counts from lecture-04-notes.md Part 4",
    "m-self": "Sources: steps/00-setup.sql (managerID values); lecture-04-notes.md Part 5",
    "m-wrongkey": "Sources: lecture-04-notes.md Part 5 (637 rows); birth dates from the customers table",
    "m-fanout": "Source: lecture-04-notes.md Part 5 (fan-out query); Aram Vardanyan: 40 orders, moneySpent 13,544.72",
    "m-nonequi": "Source: lecture-04-notes.md Part 5 (price-band query)",
    "st-build": "Sources: Kimball Group, “Nulls in Fact Tables” (default dimension row); row counts from lecture-04-notes.md Part 6",
    "st-etl": "Sources: Wikipedia, “Extract, transform, load”; lecture-04-notes.md Part 6",
    "d-drill": "Source: steps/07-drill.sql (every query and result)",
    "d-checks": "Summary of Parts 3–7 of this lecture",
}

def footer(sid):
    if sid not in SRC:
        return ""
    return (f'\n  <p style="position:absolute; left:128px; bottom:48px; width:1664px; font-family:{SANS}; font-size:24px; '
            f'line-height:1.35; color:{FAINT}">{SRC[sid]}</p>')

def img(key, w, h, alt):
    return f'<img src="{ASSET[key]}" alt="{alt}" style="width:{w}px; height:{h}px; object-fit:contain">'

def emit(sid, body):
    assert sid not in order, sid
    order.append(sid)
    (SLIDES / f"{sid}.html").write_text(body.strip() + "\n")

def notes(n):
    return f"\n  <aside>{html.escape(n.strip(), quote=False)}</aside>" if n else ""

def section(key, desc, sid):
    sections[key] = {"description": desc, "start": sid}

def slide(sid, part, title, body, note="", gap=48):
    emit(sid, f'''
<section id="{sid}" data-transition="fade" style="background:{BG}; color:{FG}; font-family:{SANS}; padding:128px 128px 160px; display:flex; flex-direction:column; gap:{gap}px">
  <div style="display:flex; flex-direction:column; gap:14px">
    <p style="font-family:{MONO}; font-size:24px; color:{GREEN}">-- {part}</p>
    <h2 style="font-family:{MONO}; font-size:60px; font-weight:600; line-height:1.15; letter-spacing:-1px; color:{FG}">{title}</h2>
  </div>
  {body}{footer(sid)}{notes(note)}
</section>''')

# ---- building blocks --------------------------------------------------------
def host(w, h, *children):
    n = sum(c.count('position:absolute') + c.count('<x-connector') for c in children)
    assert n <= 24, f"host has {n} pinned children"
    return f'<div style="position:relative; width:{w}px; height:{h}px">' + "".join(children) + "</div>"

def tbox(l, t, w, h, title, lines=(), tcolor=FG, border=LINE, bstyle="solid", bg=SURF, center=False,
         tsize=26, lsize=24, lcolor=SOFT, strike=False, radius=8, align="left"):
    deco = "; text-decoration:line-through" if strike else ""
    j = "; justify-content:center" if center else ""
    ai = "; align-items:center" if align == "center" else ""
    ls = "".join(f'<p style="font-family:{MONO}; font-size:{lsize}px; line-height:1.35; color:{lcolor}; text-align:{align}">{x}</p>' for x in lines)
    return (f'<div style="position:absolute; left:{l}px; top:{t}px; width:{w}px; height:{h}px; background:{bg}; '
            f'border:2px {bstyle} {border}; border-radius:{radius}px; padding:14px 22px; display:flex; flex-direction:column; gap:4px{j}{ai}">'
            f'<p style="font-family:{MONO}; font-size:{tsize}px; font-weight:600; line-height:1.3; color:{tcolor}; text-align:{align}{deco}">{title}</p>{ls}</div>')

def line(x1, y1, x2, y2, color=FAINT, w=2, head="none", dash=False):
    d = "; border-style:dashed" if dash else ""
    return f'<x-connector x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" head="{head}" style="color:{color}; border-width:{w}px{d}"></x-connector>'

def plabel(l, t, w, text, color=FAINT, size=24, mono=True, align="left", weight=400):
    fam = MONO if mono else SANS
    return (f'<p style="position:absolute; left:{l}px; top:{t}px; width:{w}px; font-family:{fam}; font-size:{size}px; '
            f'font-weight:{weight}; line-height:1.35; color:{color}; text-align:{align}">{text}</p>')

def p(text, color=SOFT, size=30, mono=False, weight=400, extra=""):
    fam = MONO if mono else SANS
    return f'<p style="font-family:{fam}; font-size:{size}px; font-weight:{weight}; line-height:1.4; color:{color}{extra}">{text}</p>'

def row(*c, gap=32, extra=""):
    return f'<div style="display:flex; gap:{gap}px{extra}">' + "".join(c) + "</div>"

def col(*c, gap=20, extra=""):
    return f'<div style="display:flex; flex-direction:column; gap:{gap}px{extra}">' + "".join(c) + "</div>"

def c(t, color):
    return f'<span style="color:{color}">{t}</span>'

def kw(t):
    return c(t, BLUE)

def fbox(title, sub="", color=FG, border=LINE, bstyle="solid", bg=SURF, extra="; flex:1"):
    s = f'<p style="font-family:{SANS}; font-size:26px; line-height:1.35; color:{SOFT}">{sub}</p>' if sub else ""
    return (f'<div style="background:{bg}; border:2px {bstyle} {border}; border-radius:8px; padding:20px 24px; '
            f'display:flex; flex-direction:column; gap:8px{extra}"><p style="font-family:{MONO}; font-size:26px; font-weight:600; '
            f'line-height:1.3; color:{color}">{title}</p>{s}</div>')

def arrow(w=48):
    return f'<x-connector style="width:{w}px; color:{FAINT}; border-width:2px"></x-connector>'

def keyline(label, text, lcolor=AMBER, lw=520, size=32):
    return row(f'<p style="font-family:{MONO}; font-size:{size}px; font-weight:600; color:{lcolor}; width:{lw}px">{label}</p>',
               f'<p style="font-family:{SANS}; font-size:{size}px; line-height:1.4; color:{SOFT}; flex:1">{text}</p>', gap=40,
               extra="; align-items:baseline")

def ruled(text, color=AMBER, size=32):
    return (f'<div style="border-left:4px solid {color}; padding:4px 0px 4px 28px">'
            f'<p style="font-family:{SANS}; font-size:{size}px; line-height:1.4; color:{FG}">{text}</p></div>')

def dtable(headers, rows, widths, size=24, tints=None, aligns=None):
    tints = tints or {}
    aligns = aligns or ["left"] * len(headers)
    out = [f'<table style="width:100%; font-family:{MONO}; font-size:{size}px; color:{FG}">',
           "<tr>" + "".join(f'<th style="width:{w}%; text-align:{a}; font-weight:600; color:{FAINT}">{h}</th>'
                            for h, w, a in zip(headers, widths, aligns)) + "</tr>"]
    for i, r in enumerate(rows):
        bg = f' style="background:{tints[i]}"' if i in tints else ""
        out.append(f"<tr{bg}>" + "".join(f'<td style="text-align:{a}">{x}</td>' for x, a in zip(r, aligns)) + "</tr>")
    return "".join(out) + "</table>"

def pk(t):
    return c(t + " PK", AMBER)

def fk(t):
    return c(t + " FK", BLUE)

# ============================================================================
# OPENING
# ============================================================================
section("open", "Where Lecture 3 left us", "cover")
emit("cover", f'''
<section id="cover" data-transition="fade" style="background:{BG}; color:{FG}; font-family:{SANS}; padding:128px; display:flex; flex-direction:column; gap:40px">
  <p style="font-family:{MONO}; font-size:28px; color:{GREEN}">$ psql lecture04</p>
  <div style="flex:1"></div>
  <h1 style="font-family:{MONO}; font-size:104px; font-weight:600; line-height:1.08; letter-spacing:-3px; color:{FG}">Putting the tables<br>back together<span style="color:{GREEN}">_</span></h1>
  <p style="font-family:{MONO}; font-size:36px; color:{SOFT}">data models · schema types · JOIN</p>
  <div style="flex:1"></div>
  <div style="display:flex; justify-content:space-between">
    <p style="font-family:{MONO}; font-size:24px; color:{FAINT}">Introduction to Databases &amp; SQL · Lecture 4</p>
    <p style="font-family:{MONO}; font-size:24px; color:{FAINT}">YSU · Data Science for Business</p>
  </div>{notes("""Setup: createdb lecture04; psql lecture04; then \\i steps/00-setup.sql from the lecture_4 folder. Expect 600 / 30 / 8 / 37 / 600.
Same data as Lecture 3, plus employees.managerID (used in the self-join).""")}
</section>''')

slide("left-off", "where we left off", "What the flat table can’t tell you",
    col(keyline("Ergonomic Chair Pro", "never sold, so <i>Chairs</i> appears nowhere in <b style=\"color:#E6EDF3\">sales</b>"),
        keyline("Levon, Astghik", "customers who never ordered: sales has never heard of them"),
        keyline("two Annas", "no customer id on the flat table, only the email tells them apart"), gap=44)
    + ruled("The normalized tables know all three. Today: why the data is split this way, and how to ask a question that needs several tables at once.", GREEN),
    note="""Every report in Lecture 3 came off the flat sales table because it had the names on it. A row exists in sales only if a sale happened, so it can't know about things that didn't happen. That idea returns several times today.
Plan: Part 1 data models, Part 2 schema types, Parts 3-5 JOIN, Part 6 build a star, Part 7 drill.""")

# ============================================================================
# PART 1 — DATA MODELS
# ============================================================================
section("models", "Part 1: data models — levels and kinds", "dm-def")

def trio(head, q, a, color):
    return col(p(head, color, 40, True, 600), p(q, SOFT, 30), p(a, FG, 30), gap=16, extra="; flex:1")
slide("dm-def", "01 · data models", "A data model answers three questions",
    row(trio("structure", "What shape does data take?", "relational: tables of rows", BLUE),
        trio("operations", "What can you ask, and how?", "relational: SELECT, WHERE, GROUP BY… and JOIN", GREEN),
        trio("constraints", "What is data <i>not allowed</i> to be?", "relational: keys, NOT NULL, CHECK, foreign keys", AMBER), gap=80)
    + ruled("You’ve worked inside one model for three lectures. The next slides show what you’re choosing when you choose tables.", FAINT),
    note="""A data model is a set of rules for describing data: structure, operations, constraints. Relational operations take tables in and give tables back, which is why a join result can be filtered, grouped and sorted like a stored table.""")

# levels: conceptual and logical are Mermaid ER diagrams; physical is the DDL
lvl_phy = host(480, 460,
    tbox(0, 0, 480, 440, c("CREATE TABLE", BLUE) + " orders (", [
        "&#160;&#160;orderID INT " + c("PRIMARY KEY", BLUE) + ",",
        "&#160;&#160;customerID INT",
        "&#160;&#160;&#160;&#160;" + c("REFERENCES", BLUE) + " customers,",
        "&#160;&#160;orderTotal DECIMAL(10,2)", ");", "",
        c("-- index orders_pkey (btree)", GREEN), c("-- built automatically", GREEN)], tsize=24, lcolor=FG))
def level(name, who, inner):
    return col(p(name, GREEN, 32, True, 600), p(who, FAINT, 26), inner, gap=10, extra="; flex:1")
slide("dm-levels", "01 · data models · levels", "One design, three levels of detail",
    row(level("conceptual", "for the business: things and relationships", img("levels-conceptual", 480, 460, "ER diagram: a customer places many orders")),
        level("logical", "for the designer: tables, keys, 3NF", img("levels-logical", 480, 460, "ER diagram: customers and orders tables with primary and foreign keys")),
        level("physical", "for the DBMS: exact types, indexes", lvl_phy), gap=64),
    note="""Same shop, three levels. Conceptual: the owner's sketch. Logical: the architect's plan. Physical: the builder's drawing with the pipe sizes.
Demo: \\d orders. At the bottom, Indexes: "orders_pkey" PRIMARY KEY, btree (orderid). PostgreSQL creates a unique btree index for every primary key (docs: CREATE TABLE). Remove it and every query returns the same rows, only slower. That's what makes it physical.""")

def side_text(*lines):
    return col(*[p(x, SOFT if i else FG, 30) for i, x in enumerate(lines)], gap=28, extra="; flex:1")

slide("dm-hier", "01 · data models · 1960s", "Hierarchical: data is a tree",
    row(img("hierarchical", 900, 600, "Two trees: Davit to order 1001 to AirPods Pro, Samvel to order 1002 to AirPods Pro"),
        side_text("Every record has exactly one parent.",
                  c("fast:", GREEN) + " all of Davit’s orders sit right under him.",
                  c("slow:", RED) + " “who bought AirPods Pro?” means walking every branch.",
                  c("stored twice:", AMBER) + " the product lives under each order that contains it."), gap=64, extra="; align-items:center"),
    note="""IBM IMS: development began in 1966 for the Apollo program (Wikipedia, IBM Information Management System); still used in banking (Wikipedia, Hierarchical database model, which also states the one-parent rule and that many-to-many needs duplication). Orders 1001 and 1002 are real rows: two customers, both bought AirPods Pro. That's Lecture 2's redundancy problem.""")

slide("dm-network", "01 · data models · 1969", "Network: records linked by pointers",
    row(img("network", 860, 600, "Orders 1001 and 1002 point to their customers and to one shared AirPods Pro record"),
        side_text("Many parents allowed: one AirPods record, no copying.",
                  "But every question is a program: start at Davit, follow this pointer, loop over those.",
                  "Change the pointers and the programs break."), gap=64, extra="; align-items:center"),
    note="""CODASYL's Data Base Task Group published the network-model spec in October 1969, based on Charles Bachman's Integrated Data Store, which linked records with chains of pointers (Wikipedia, CODASYL). Bachman's 1973 Turing Award lecture was titled 'The Programmer as Navigator' (CACM 16(11)).""")

# relational: values matched
def nb(s, w):
    return str(s).ljust(w).replace(" ", "&#160;")
def orow(oid, cid, pid):
    return nb(oid, 9) + c(nb(cid, 12), AMBER) + nb(pid, 9)
def crow(cid, name, city):
    return c(nb(cid, 12), AMBER) + nb(name, 10) + city
rel = host(1664, 560,
    plabel(0, 0, 620, "orders", GREEN, 28, weight=600),
    plabel(1044, 0, 620, "customers", GREEN, 28, weight=600),
    tbox(0, 50, 620, 64, nb("orderID", 9) + nb("customerID", 12) + "productID", tcolor=FAINT, bg=BG, center=True),
    tbox(0, 130, 620, 64, orow("1001", "2", "25"), center=True),
    tbox(0, 210, 620, 64, orow("1002", "26", "25"), center=True),
    tbox(0, 290, 620, 64, orow("1003", "6", "25"), center=True),
    tbox(1044, 50, 620, 64, nb("customerID", 12) + nb("firstName", 10) + "city", tcolor=FAINT, bg=BG, center=True),
    tbox(1044, 130, 620, 64, crow("2", "Davit", "Gyumri"), center=True),
    tbox(1044, 210, 620, 64, crow("6", "Narek", "Gyumri"), center=True),
    tbox(1044, 290, 620, 64, crow("26", "Samvel", "Gyumri"), center=True),
    line(620, 162, 1044, 162, AMBER, 3, dash=True), line(620, 242, 1044, 322, AMBER, 3, dash=True), line(620, 322, 1044, 242, AMBER, 3, dash=True),
    plabel(0, 400, 1664, "Nothing points anywhere. Order 1001 holds the value 2; Davit’s row holds customerID 2. Matching equal values at query time is a " + c("join", AMBER) + ".", FG, 32, False))
slide("dm-relational", "01 · data models · 1970 → today", "Relational: links are values", rel,
    note="""E. F. Codd, 1970. The key idea for the whole lecture: relationships are stored as values, not pointers. The dashed lines aren't stored anywhere; the database finds them when you ask, by matching equal values. You describe the result; the database works out how to get it. That's the declarative idea from Lecture 2.""")

slide("dm-document", "01 · data models · 2009", "Document: one order, one object",
    row(img("document", 780, 620, "Order 1001 as one document with the customer, product and seller nested inside"),
        side_text(c("good at", GREEN) + ": show one order. One read, no joins, no lookups.",
                  c("weak at", RED) + ": “Davit moved to Yerevan.” His city is copied inside all 52 of his order documents.",
                  "That’s Lecture 2’s update anomaly, back because the data was nested."), gap=64, extra="; align-items:center"),
    note="""MongoDB, first released February 2009, stores JSON-like (BSON) documents (Wikipedia, MongoDB). Davit really has 52 orders in our data. Part 5 builds a document like this from our tables with jsonb_agg: a document is a join you saved.""")

slide("dm-kv", "01 · data models · specialists", "Key-value: give a key, get a value",
    img("keyvalue", 1664, 480, "Three keys, each pointing to one value: a cart, a session, a stock count")
    + p("One question, answered extremely fast: what’s under this key? Anything else, like “which carts hold AirPods?”, means reading every value.", SOFT, 30),
    gap=40,
    note="""AWS lists session stores, shopping carts and caching as the typical key-value use cases (AWS, What is a key-value database?). The keys and values on the slide are illustrations of how our shop could use one, not rows from our database.""")

slide("dm-graph", "01 · data models · specialists", "Graph: the connections are the data",
    row(img("graph", 1100, 580, "Graph: Nare reports to Hayk, Hayk to Vahe; Davit and Samvel both bought AirPods Pro"),
        side_text("Built for questions about the connections themselves.",
                  "Who is above Nare, all the way up?",
                  "Who else bought what Davit bought?"), gap=64, extra="; align-items:center"),
    note="""Neo4j docs: data stored as nodes, relationships and properties; relational databases use 'computing-wise expensive JOIN operations' for connected data. The reporting line is ours (steps/00-setup.sql) and Davit and Samvel really both bought AirPods Pro (orders 1001, 1002). In Part 5, two levels up takes two joins.""")

slide("dm-compare", "01 · data models · summary", "Six models, side by side",
    dtable(["model", "shape", "good at", "weak at", "example"],
           [["hierarchical", "tree", "one parent + its children", "many-to-many", "IBM IMS"],
            ["network", "records + pointers", "known navigation paths", "new questions", "CODASYL"],
            [c("relational", AMBER), c("tables + keys", AMBER), c("any question, asked later", AMBER), "deep nesting, huge writes", c("PostgreSQL", AMBER)],
            ["document", "JSON objects", "one whole object", "questions across objects", "MongoDB"],
            ["key-value", "key → value", "one lookup, very fast", "anything else", "Redis"],
            ["graph", "nodes + edges", "long chains of links", "totals over everything", "Neo4j"]],
           [16, 18, 26, 25, 15], size=26, tints={2: SURF2}),
    note="""Don't make them memorise the table. Each model is great at one kind of question. Relational's strength is questions nobody planned for, plus integrity enforced by the database.""")

slide("dm-why", "01 · data models · verdict", "Why business data lives in tables",
    col(keyline("questions come later", "nobody opening the shop knew they’d ask “which categories never sold?”. Joins answer questions nobody planned for.", BLUE),
        keyline("one fact, one place", "normalization only works when relationships are values you can join on", BLUE),
        keyline("the database says no", "an order for a customer who doesn’t exist is refused; MongoDB, for example, leaves references to the application", BLUE), gap=44)
    + ruled("Business impact: the orders, the money and the customers live where you can ask <i>any</i> question and trust that it adds up.", GREEN),
    note="""The other models are still in use: IMS in banking (Wikipedia, Hierarchical database model), key-value stores for carts and sessions (AWS). PostgreSQL even speaks JSON: SELECT jsonb_pretty(to_jsonb(c)) FROM customers c WHERE customerID = 2; turns Davit's row into a document.""")

# ============================================================================
# PART 2 — SCHEMA TYPES
# ============================================================================
section("schemas", "Part 2: schema types — OLTP vs OLAP; normalized, flat, star, snowflake", "sc-oltp")

def side(head, sub, items, color):
    lis = "".join(p(f'{c("›", color)} {i}', SOFT, 32) for i in items)
    return col(p(head, color, 44, True, 600), p(sub, FAINT, 28, True), lis, gap=18, extra="; flex:1")
slide("sc-oltp", "02 · schema types", "Two jobs, two shapes",
    row(side("OLTP", "run the shop", ["one order at a time", "touches a handful of rows", "writes constantly", "the till, the website",
                                     f'shape: {c("normalized", FG)}, one fact in one place'], BLUE),
        f'<div style="width:2px; background:{LINE}"></div>',
        side("OLAP", "understand the shop", ["revenue by quarter and category", "reads every row", "writes in nightly batches", "analysts, managers, you",
                                            f'shape: {c("denormalized", FG)}: flat, star, snowflake'], AMBER), gap=80),
    note="""A schema is the set of tables, columns and keys. The till in Yerevan Center is OLTP: one order at a time, and never a price stored twice in two places that could disagree. The owner's year-end report is OLAP: reads all 600 orders, writes nothing, wants as few joins as possible. Next four slides: four shapes for the same 600 sales.""")

slide("sc-normalized", "02 · schema types · shape 1", "Shape 1: normalized (3NF)",
    row(img("normalized", 880, 620, "ER diagram of customers, products, employees and orders with their keys"),
        side_text(c("one fact, one place.", GREEN) + " Each customer, product and employee is stored once.",
                  "orders holds only keys that point at them.",
                  "Every question with a name in it needs a join."), gap=64, extra="; align-items:center"),
    note="""What we have: customers, employees, products, orders. Lecture 2 built it so an update, insert or delete can't leave the data contradicting itself. employees.managerID is new this lecture and points back into employees (the 'manages' loop). employeeID on orders is optional: NULL for online orders. Cost: every question with a name, category or branch in it needs a join.""")

GRP = [("order", 18, SURF2), ("customer", 23, "#2A2415"), ("employee", 22, SURF2), ("product", 25, "#15222E"), ("", 12, BG)]
grp_row = row(*[f'<div style="width:{round(1664 * w / 100)}px; background:{bg}; padding:6px 12px"><p style="font-family:{MONO}; font-size:24px; color:{SOFT}">{n}</p></div>'
                for n, w, bg in GRP], gap=0)
A, B = (lambda t: c(t, AMBER)), (lambda t: c(t, BLUE))
slide("sc-flat", "02 · schema types · shape 2", "Shape 2: one big table",
    col(grp_row,
        dtable(["orderid", "date", "customer", "city", "sold by", "branch", "product", "category", "total"],
               [["1001", "2024-01-01", A("Davit Petrosyan"), A("Gyumri"), "Ani", "Yerevan Center", B("AirPods Pro"), B("Audio"), "211.65"],
                ["1002", "2024-01-02", "Samvel Nazaryan", "Gyumri", "Gor", "Yerevan Center", B("AirPods Pro"), B("Audio"), "249.00"],
                ["1003", "2024-01-02", "Narek Manukyan", "Gyumri", "Lilit", "Yerevan Mall", B("AirPods Pro"), B("Audio"), "747.00"],
                ["1094", "2024-03-12", A("Davit Petrosyan"), A("Gyumri"), c("—", FAINT), c("—", FAINT), "K380", "Keyboards", "35.99"],
                ["1100", "2024-03-19", A("Davit Petrosyan"), A("Gyumri"), "Marine", "Gyumri", "UltraSharp 27", "Monitors", "640.00"]],
               [7, 11, 15, 8, 8, 14, 14, 11, 12], size=24, aligns=["right"] + ["left"] * 7 + ["right"]), gap=0)
    + col(p(f'{c("repeated:", AMBER)} Davit’s name and city on every one of his 52 rows; a product’s category on every sale', SOFT, 30),
          p(f'{c("blind:", RED)} Chairs, Levon, Astghik have no row: a row exists only if a sale happened', SOFT, 30),
          p(f'{c("fine as an output:", GREEN)} built from the normalized tables by a query, rebuilt, never edited', SOFT, 30), gap=14),
    note="""This is sales, our 29-column flat table, shown with 9 of its columns. Real rows. Analysts love it because every question is one table. Dangerous as the place data LIVES: change Davit's city and you change 52 rows. Respectable as an OUTPUT of a pipeline. By the end of Part 4 students write the query that rebuilds it.""")

slide("sc-star", "02 · schema types · shape 3", "Shape 3: the star schema",
    row(img("star", 1160, 600, "Star schema: fact_sales in the middle, four dimension tables around it"),
        side_text(c("fact:", AMBER) + " one row per order, the numbers you add up, plus a key to each dimension.",
                  c("dimensions:", GREEN) + " the labels you group and filter by, one hop away.",
                  c("grain:", BLUE) + " one row per order, written down before anything else."), gap=48, extra="; align-items:center"),
    note="""Kimball Group: dimensional models divide data into measurements and the 'who, what, where, when, why, and how' context; implemented relationally as star schemas. 'The grain establishes exactly what a single fact table row represents.' Wikipedia, Star schema: fact tables hold numeric values and foreign keys; dimensions are denormalized. We build this in Part 6.""")

slide("sc-snowflake", "02 · schema types · shape 4", "Shape 4: the snowflake schema",
    row(img("snowflake", 980, 620, "Snowflake schema: category split out of product, branch split out of employee"),
        side_text(c("normalized again:", BLUE) + " category and branch move into their own tables.",
                  "Less repetition, one more join per question.",
                  "The Kimball Group advises against it: harder for business users to navigate, can slow queries, and holds nothing the flat dimension doesn’t."), gap=56, extra="; align-items:center"),
    note="""Kimball Group, Snowflaked Dimensions: normalizing a dimension's hierarchy creates a snowflake; they advise against it because snowflakes are hard for business users to understand and navigate and can hurt query performance, while a flat dimension holds the same information. Wikipedia, Snowflake schema: the space saved is often negligible compared with the added complexity.""")

slide("sc-rules", "02 · schema types · denormalizing on purpose", "Copy data only when all four hold",
    row(col(*[row(p(str(i), GREEN, 36, True, 600), p(t, FG, 34), gap=28, extra="; align-items:baseline") for i, t in enumerate(
                ["there is one source of truth, and it’s normalized", "the copy is built from it by a query", "the copy is rebuilt, never edited by hand",
                 "someone owns the rebuild and knows when it ran"], 1)], gap=30, extra="; flex:1"),
        col(ruled(f'{c("passes", GREEN)} · star schema: built from the OLTP tables every night', GREEN, 30),
            ruled(f'{c("fails", RED)} · customers.moneySpent: a copy of sum(orderTotal) inside the source of truth, right only if every insert remembers to update it', RED, 30),
            gap=36, extra="; width:700px"), gap=80),
    note="""The rule Lecture 2 promised. moneySpent fails because it lives inside the OLTP tables and depends on every piece of code that inserts an order also updating it. Part 5 checks whether it is still right today; the lesson is that it can drift and nothing would warn us.""")

slide("sc-items", "02 · schema types · the fix Lecture 2 deferred", "order_items: one row per product",
    row(img("order_items", 760, 620, "ER diagram: orders contains order_items, products appears in order_items"),
        side_text(c("key of two columns:", AMBER) + " a product appears once per order; raise the quantity instead.",
                  c("line facts move here:", AMBER) + " quantity and price describe a line, not the whole order.",
                  c("unitPrice isn’t redundant:", AMBER) + " it’s the price on the day of sale; products.price is today’s."), gap=64, extra="; align-items:center"),
    note="""Many-to-many (an order holds many products; a product appears in many orders) needs a junction table (Lecture 2 notes, Part 2). Run Part 2 of the notes: CREATE TABLE order_items ... then INSERT ... SELECT from orders: INSERT 0 600. The check query finds 0 orders with several lines: the shape allows baskets, the data hasn't used it yet.""")

# ============================================================================
# PART 3 — JOIN: THE IDEA
# ============================================================================
section("join", "Part 3: JOIN — every combination, then keep the matching pairs", "j-ids")

ids = host(1664, 560,
    tbox(282, 0, 1100, 90, f'1001 │ customerID {c("2", AMBER)} │ productID {c("25", AMBER)} │ 211.65', center=True, align="center", tsize=28),
    tbox(182, 270, 560, 110, "customers", ["who is 2?"], tcolor=GREEN, center=True, align="center", bstyle="dashed"),
    tbox(922, 270, 560, 110, "products", ["what is 25?"], tcolor=GREEN, center=True, align="center", bstyle="dashed"),
    line(640, 90, 462, 270, AMBER, 3, "end", dash=True), line(1020, 90, 1202, 270, AMBER, 3, "end", dash=True),
    plabel(0, 450, 1664, "The orders table holds ids, not names. The answers are in two other tables. A join looks them up for every row at once.", SOFT, 30, False, "center"))
slide("j-ids", "03 · join", "Where did the names go?", ids,
    note="""Demo: SELECT orderID, customerID, productID, orderTotal FROM orders ORDER BY orderID LIMIT 3; Customer 2 bought product 25. Until now you'd look each up by hand, one query per id.""")

ORD = [("1001", 2), ("1002", 26), ("1003", 6)]
CUS = [(2, "Davit"), (6, "Narek"), (26, "Samvel")]
YS = [40, 175, 310]
def pair_panel(all_pairs):
    parts = []
    for i, (o, cid) in enumerate(ORD):
        parts.append(tbox(0, YS[i] - 40, 290, 80, f'{o} {c("cust=", FAINT)}{cid}', center=True))
    for j, (cid, name) in enumerate(CUS):
        parts.append(tbox(470, YS[j] - 40, 290, 80, f'{cid} {c("·", FAINT)} {name}', center=True))
    for i, (o, oc) in enumerate(ORD):
        for j, (cid, _) in enumerate(CUS):
            if all_pairs:
                parts.append(line(290, YS[i], 470, YS[j], FAINT, 2))
            elif oc == cid:
                parts.append(line(290, YS[i], 470, YS[j], AMBER, 4))
    return host(760, 350, *parts)
def panel(head, sub, diagram):
    return col(col(p(head, FG, 30, True), p(sub, SOFT, 28), gap=8), diagram, gap=28, extra="; flex:1")
slide("j-pairs", "03 · join", "Every pair, then the pairs that match",
    row(panel(f'orders {kw("CROSS JOIN")} customers', "every pair: 3 × 3 = 9 (all data: 600 × 30 = 18,000)", pair_panel(True)),
        panel(f'{kw("JOIN")} … {kw("ON")} key = key', f'keep pairs whose values match: {c("3", AMBER)}', pair_panel(False)), gap=144)
    + p("A join is a filtered cross product. The database finds the matches faster, but the answer is always exactly this.", SOFT, 30),
    note="""Demo live: (1) SELECT count(*) FROM orders CROSS JOIN customers; → 18000. Guess first. (2) The 9-row version: WHERE o.orderID IN (1001,1002,1003) AND c.customerID IN (2,6,26). Ask which of the nine lines are true. (3) Add AND o.customerID = c.customerID → 3 rows. (4) Rewrite as JOIN customers c ON c.customerID = o.customerID. JOIN alone means INNER JOIN.
PostgreSQL never builds 18,000 rows: its planner picks a nested loop, merge or hash join by estimated cost, and every plan returns the same result (docs: Planner/Optimizer).""")

def colchips(tname, cols, hot):
    chips = "".join(f'<p style="font-family:{MONO}; font-size:26px; color:{RED if x == hot else SOFT}; background:{SURF}; border:2px solid {RED if x == hot else LINE}; border-radius:6px; padding:8px 16px">{x}</p>' for x in cols)
    return row(p(tname, GREEN, 28, True, 600, "; width:260px"), f'<div style="display:flex; gap:12px">{chips}</div>', gap=24, extra="; align-items:center")
slide("j-names", "03 · join · names", "Whose column is it?",
    col(colchips("orders o", ["orderID", "customerID", "productID", "orderTotal"], "customerID"),
        colchips("customers c", ["customerID", "firstName", "lastName", "city"], "customerID"),
        p('ERROR: column reference "customerid" is ambiguous', RED, 28, True), gap=20)
    + col(keyline("o.customerID", "prefix every column in a join, even the ones that aren’t ambiguous yet", GREEN, 460, 30),
          keyline("USING (customerID)", "shorthand when the key has the same name on both sides; merges the two into one column", GREEN, 460, 30),
          keyline("NATURAL JOIN", "joins on every shared name, silently. Next slide.", RED, 460, 30), gap=24),
    note="""Error on purpose: SELECT orderID, customerID, firstName FROM orders JOIN customers ON customers.customerID = orders.customerID; The values are equal on every joined row, but the rule is about names, not values.
Second error on purpose: SELECT orders.orderID FROM orders o ...; once a table has an alias, the alias is its only name. HINT: Perhaps you meant to reference the table alias "o".""")

SHARED = ["orderID", "orderDate", "orderTime", "channel", "status", "paymentMethod", "quantity", "unitPrice", "discountPct", "orderTotal", "deliveryDate", "rating"]
chips = "".join(f'<p style="font-family:{MONO}; font-size:26px; color:{RED if s in ("deliveryDate", "rating") else FG}; background:{SURF}; border:2px solid {RED if s in ("deliveryDate", "rating") else LINE}; border-radius:6px; padding:10px 18px">{s}</p>' for s in SHARED)
slide("j-natural", "03 · join · don’t", "NATURAL JOIN: the invisible condition",
    row(col(p(f'orders {kw("NATURAL JOIN")} sales joins on all 12 shared names:', SOFT, 30),
            f'<div style="display:grid; grid-template-columns:repeat(3, 1fr); gap:14px">{chips}</div>',
            p(f'{c("deliveryDate", RED)} is NULL for every in-store order, {c("rating", RED)} for most. NULL = NULL is not true, so those rows are thrown away.', SOFT, 30), gap=28, extra="; flex:1"),
        col(p("97", RED, 200, True, 600, "; line-height:1"), p("rows. Both tables hold the same 600 sales.", SOFT, 30), p("No error. And nothing in the query says which columns it used.", FG, 30), gap=20, extra="; width:520px"),
        gap=80),
    note="""Demo: SELECT count(*) FROM orders NATURAL JOIN sales; Guess before revealing why. Only online orders that also got a rating have no NULLs in those twelve columns: 97. Add a column to either table next year and the answer silently changes. Always write ON or USING.""")

STEPS = ["FROM + JOINs", "WHERE", "GROUP BY", "HAVING", "SELECT", "ORDER BY", "LIMIT"]
pipe = []
for i, s in enumerate(STEPS, 1):
    hot = i == 1
    pipe.append(f'<div style="flex:1; background:{SURF2 if hot else SURF}; border:2px solid {AMBER if hot else LINE}; border-radius:8px; padding:20px 18px; display:flex; flex-direction:column; gap:6px">'
                f'<p style="font-family:{MONO}; font-size:24px; color:{FAINT}">{i}</p><p style="font-family:{MONO}; font-size:28px; font-weight:600; color:{AMBER if hot else FG}">{s}</p></div>')
    if i < len(STEPS):
        pipe.append(arrow(28))
slide("j-order", "03 · join · execution order", "The joins run first",
    f'<div style="display:flex; gap:8px; align-items:center">{"".join(pipe)}</div>'
    + col(ruled(f'Every {c("ON", BLUE)} is applied at step 1, while the combined rows are built.', AMBER),
          ruled(f'{c("WHERE", BLUE)} never sees the separate tables. It sees the joined rows.', AMBER),
          ruled("After that, everything from Lecture 3 works on the joined rows exactly as on a stored table.", FAINT), gap=24),
    note="""Lecture 3's order with one change: step 1 builds the combined rows. Demo: completed revenue per city (orders JOIN customers, WHERE status, GROUP BY city): Yerevan 82057.54, Gyumri 43495.52, Abovyan 11566.79, Vanadzor 8815.27. Keep this pipeline in mind: the WHERE-vs-ON trap in Part 4 comes straight from it.""")

# ============================================================================
# PART 4 — OUTER JOINS
# ============================================================================
section("outer", "Part 4: outer joins — keeping the rows that found no partner", "o-inner-left")

EMP_ROWS = [("1004", "in_store"), ("1005", "online"), ("1006", "online")]
def join_panel(kind):
    parts = []
    for i, (oid, ch) in enumerate(EMP_ROWS):
        top = i * 130
        dropped = kind == "inner" and ch == "online"
        parts.append(tbox(0, top, 330, 80, f'{oid} {c(ch, FAINT)}', tcolor=RED if dropped else FG, border=RED if dropped else LINE,
                          bstyle="dashed" if dropped else "solid", strike=dropped, center=True))
        if ch == "in_store":
            parts.append(tbox(510, top, 250, 80, "Nare · Mall", center=True))
            parts.append(line(330, top + 40, 510, top + 40, AMBER, 4))
        elif kind == "left":
            parts.append(tbox(510, top, 250, 80, "NULL · NULL", tcolor=FAINT, bstyle="dashed", bg=BG, center=True))
            parts.append(line(330, top + 40, 510, top + 40, FAINT, 2, dash=True))
        else:
            parts.append(plabel(370, top + 22, 390, "no partner → dropped", RED, 26))
    return host(760, 340, *parts)
def result(n, text, color):
    return row(p(n, color, 64, True, 600), p(text, SOFT, 28, True), gap=20, extra="; align-items:baseline")
slide("o-inner-left", "04 · outer joins", "INNER drops the row. LEFT keeps it.",
    row(col(p(f'orders {kw("JOIN")} employees', FG, 30, True), join_panel("inner"), result("419", "rows of 600", RED), gap=32, extra="; flex:1"),
        col(p(f'orders {kw("LEFT JOIN")} employees', FG, 30, True), join_panel("left"), result("600", "rows, NULLs on the right", GREEN), gap=32, extra="; flex:1"), gap=144),
    note="""Hook: run Lecture 2's four-table join on this year's data: 419 rows, not 600. Where did 181 go? Online orders have employeeID NULL; NULL matches nothing; an inner join keeps only rows that found a partner. Revenue joined to employees: 93,534.71 instead of 145,935.12, i.e. 52,400.41 of web-shop revenue gone, no error.
LEFT JOIN keeps every row of the table written before JOIN. Demo: revenue per branch with coalesce(e.branch, 'Online'): Online 52400.41 is the BIGGEST branch.""")

cust = [("Aram Vardanyan", "40", True), ("Davit Petrosyan", "52", True), ("Levon Arakelyan", "0", False), ("Astghik Danielyan", "0", False), ("Diana Aleksanyan", "4", True)]
parts = []
for i, (n, k, has) in enumerate(cust):
    top = i * 110
    parts.append(tbox(0, top, 460, 80, f'{n} {c(k, FAINT)}', tcolor=FG if has else AMBER, border=LINE if has else AMBER, center=True))
    if has:
        parts.append(line(460, top + 40, 700, 170 + i * 40, FAINT, 2))
parts += [tbox(700, 130, 340, 260, "orders", ["600 rows"], center=True, align="center"),
          plabel(1120, 40, 544, c("LEFT JOIN", BLUE) + " keeps Levon and Astghik: one row each, order columns NULL.", SOFT, 30, False),
          plabel(1120, 220, 544, c("WHERE o.orderID IS NULL", BLUE) + " keeps only them: customers who never bought.", SOFT, 30, False),
          plabel(1120, 400, 544, "Same for products: " + c("Ergonomic Chair Pro", AMBER) + ", 6 in stock, 0 sold.", SOFT, 30, False)]
slide("o-anti", "04 · outer joins · the anti-join", "Who never bought? Keep the NULLs", host(1664, 560, *parts),
    note="""customers LEFT JOIN orders: 602 rows. Guess why not 600: two customers have no orders and are kept anyway, one row each. Then WHERE o.orderID IS NULL: a primary key is never NULL in a real row, so NULL there means 'no match'. Levon (signed up 2023-11-01) and Astghik (2022-10-23): a marketing email today. The flat sales table could never answer this.""")

cellrow = row(*[f'<p style="font-family:{MONO}; font-size:28px; color:{FAINT if v == "NULL" else FG}; background:{BG if v == "NULL" else SURF}; border:2px {"dashed" if v == "NULL" else "solid"} {LINE}; border-radius:6px; padding:16px 24px">{v}</p>'
                for v in ["Levon", "Arakelyan", "NULL", "NULL", "NULL"]], gap=12)
slide("o-count", "04 · outer joins · trap", "count(*) counts the empty match",
    col(p(f'customers {kw("LEFT JOIN")} orders gives Levon one row:', SOFT, 30), cellrow,
        p("the customer’s columns, then every order column NULL", FAINT, 26), gap=16)
    + row(col(p("count(*)", RED, 40, True, 600), p("counts rows → Levon: 1, Astghik: 1", SOFT, 30), gap=10, extra="; flex:1"),
          col(p("count(o.orderID)", GREEN, 40, True, 600), p("counts non-NULL values → 0 and 0", SOFT, 30), gap=10, extra="; flex:1"), gap=80)
    + ruled("With a LEFT JOIN, count the right table’s key, never *. Lecture 3’s count(column) rule, back to collect.", AMBER),
    note="""Demo: orders per customer, fewest first, LIMIT 4. count(*): Levon 1, Astghik 1, Diana 4, Lusine 5. Switch to count(o.orderID): 0, 0, 4, 5.""")

def lane(title, steps):
    boxes = []
    for i, (t, s, colr) in enumerate(steps):
        boxes.append(fbox(t, s, colr, border=colr if colr != FG else LINE))
        if i < len(steps) - 1:
            boxes.append(arrow(36))
    return col(p(title, FAINT, 26, True), f'<div style="display:flex; gap:10px; align-items:center">{"".join(boxes)}</div>', gap=12)
slide("o-where-on", "04 · outer joins · trap", "WHERE can undo a LEFT JOIN",
    lane("filter in WHERE", [("LEFT JOIN", "products → orders", FG), ("Chairs kept", "o.status is NULL", AMBER),
                             ("WHERE", "status = 'completed' · NULL is not true", FG), ("12 rows", "Chairs gone", RED)])
    + lane("filter in ON", [("LEFT JOIN … ON", "… AND status = 'completed'", FG), ("Chairs kept", "no completed match → NULLs", AMBER),
                            ("no WHERE", "on the right table", FG), ("13 rows", "Chairs at 0", GREEN)])
    + row(ruled(f'right-table conditions → {c("ON", BLUE)}', GREEN), ruled(f'left-table conditions → {c("WHERE", BLUE)}', GREEN), gap=64),
    gap=40,
    note="""Revenue per category including categories that sold nothing, then the boss adds 'completed only'. The obvious edit puts the status filter in WHERE and Chairs vanishes, no error. The join runs first and keeps the Chair with status NULL; then WHERE throws it out. ON decides what counts as a match; WHERE decides what survives.
Other half: customers LEFT JOIN orders ON ... AND c.city = 'Gyumri' keeps all 30 customers (233 rows): a left-table condition in ON removes nothing.""")

def mini(kind):
    keepA = kind in ("LEFT", "FULL")
    keepD = kind in ("RIGHT", "FULL")
    parts = []
    for i, k in enumerate("ABC"):
        drop = k == "A" and not keepA
        parts.append(tbox(0, i * 70, 110, 56, k, tcolor=RED if drop else FG, border=RED if drop else LINE, bstyle="dashed" if drop else "solid",
                          center=True, align="center", tsize=26, strike=drop))
    for i, k in enumerate("BCD"):
        drop = k == "D" and not keepD
        parts.append(tbox(290, i * 70, 110, 56, k, tcolor=RED if drop else FG, border=RED if drop else LINE, bstyle="dashed" if drop else "solid",
                          center=True, align="center", tsize=26, strike=drop))
    parts += [line(110, 98, 290, 28, AMBER, 3), line(110, 168, 290, 98, AMBER, 3)]
    res = ["B · B", "C · C"] + (["A · NULL"] if keepA else []) + (["NULL · D"] if keepD else [])
    parts.append(plabel(470, 0, 290, "<br>".join(c(r, GREEN if "NULL" in r else FG) for r in res), FG, 26))
    return host(760, 200, *parts)
def mini_cell(kind, cap):
    return col(p(f'{kind} JOIN', BLUE, 30, True, 600), mini(kind), p(cap, FAINT, 24), gap=10)
slide("o-types", "04 · outer joins · summary", "What happens to rows with no partner?",
    f'<div style="display:grid; grid-template-columns:repeat(2, 1fr); gap:24px">'
    + mini_cell("INNER", "only matched pairs · 419 orders with a salesperson")
    + mini_cell("LEFT", "+ unmatched left rows · all 600 orders")
    + mini_cell("RIGHT", "+ unmatched right rows · a LEFT JOIN written backwards")
    + mini_cell("FULL", "+ both · 28 customers only, 6 staff only, 2 on both")
    + "</div>",
    note="""Left rows A, B, C; right rows B, C, D. B and C match. INNER keeps only the pairs; LEFT adds A with NULLs; RIGHT adds D; FULL adds both. CROSS JOIN is the odd one out: every combination, no matching at all.
RIGHT JOIN: orders RIGHT JOIN customers = customers LEFT JOIN orders (602 either way). This course writes LEFT always, as a style choice.
FULL JOIN reconciles two lists: customers vs employees by name: 28 customer only, 6 employee only, 2 on both lists. Hold on to those 2 for Part 5.
Payoff to demo: rebuild sales from orders JOIN customers JOIN products LEFT JOIN employees, EXCEPT SELECT * FROM sales: 0 rows both ways. The split was lossless.""")

# ============================================================================
# PART 5 — MORE JOINS, MORE TRAPS
# ============================================================================
section("more", "Part 5: self-joins, joining on the wrong column, fan-out, ranges", "m-self")

E = [("Nare", "5"), ("Lilit", "5"), ("Arman", "8"), ("Vahe", "NULL")]
M = [("5", "Hayk"), ("8", "Marine")]
parts = [plabel(0, 0, 480, "employees e", GREEN, 28, weight=600), plabel(1184, 0, 480, "employees m", GREEN, 28, weight=600)]
for i, (n, mid) in enumerate(E):
    parts.append(tbox(0, 60 + i * 90, 480, 70, f'{n.ljust(7).replace(" ", "&#160;")}{c("managerID " + mid, AMBER if mid != "NULL" else FAINT)}', center=True))
for i, (eid, n) in enumerate(M):
    parts.append(tbox(1184, 60 + i * 90, 480, 70, f'{c(("employeeID " + eid).ljust(15).replace(" ", "&#160;"), AMBER)}{n}', center=True))
parts.append(tbox(1184, 330, 480, 70, "NULL", tcolor=FAINT, bstyle="dashed", bg=BG, center=True))
parts += [line(480, 95, 1184, 95, AMBER, 3), line(480, 185, 1184, 95, AMBER, 3), line(480, 275, 1184, 185, AMBER, 3),
          line(480, 365, 1184, 365, FAINT, 2, dash=True),
          plabel(0, 460, 1664, f'{kw("FROM")} employees e {kw("LEFT JOIN")} employees m {kw("ON")} m.employeeID = e.managerID', FG, 28, align="center"),
          plabel(0, 520, 1664, "Same table, two roles, two aliases. LEFT, or Vahe, who has no manager, disappears.", SOFT, 30, False, "center")]
slide("m-self", "05 · more joins · self-join", "Self-join: one table, two roles", host(1664, 580, *parts),
    note="""Error on purpose first: FROM employees JOIN employees → table name "employees" specified more than once. With aliases e and m it works. Why LEFT? Vahe has no manager. A third copy (mm) gives two levels up. Direct reports: Vahe 4, Hayk 2, Marine 1. 'All the way up, however many levels' is the graph-model question from Part 1.""")

wk = host(1664, 560,
    tbox(0, 160, 520, 120, "sales row", ["Anna Sargsyan", c("one of 37 Anna rows", FAINT)], center=True),
    tbox(760, 40, 480, 110, "customer 1", ["Anna Sargsyan · born 1991"], center=True, border=AMBER, tcolor=AMBER),
    tbox(760, 300, 480, 110, "customer 11", ["Anna Sargsyan · born 1978"], center=True, border=AMBER, tcolor=AMBER),
    line(520, 220, 760, 95, AMBER, 3, "end"), line(520, 220, 760, 355, AMBER, 3, "end"),
    plabel(1300, 60, 364, "2", AMBER, 120, weight=600),
    plabel(1300, 230, 364, "rows come out for every Anna row that goes in", SOFT, 30, False),
    plabel(0, 470, 1664, f'{c("600 → 637", RED)} sales rows after “looking up the customer by name”. One side of ON must be a key, or rows multiply.', FG, 32, False))
slide("m-wrongkey", "05 · more joins · wrong key", "Join on a non-key and rows multiply", wk,
    note="""SELECT count(*) FROM sales s JOIN customers c ON c.firstName = s.customerFirstName AND c.lastName = s.customerLastName; → 637: 37 invented sales.
Same mistake, smaller: 'which employees also shop with us?' joined on names finds Hayk Melikyan and Lilit Hovhannisyan. Birth dates: customer Hayk 1993, employee Hayk 1985; customer Lilit 1990, employee Lilit 1998. Four different people. A join is only as true as its ON; this data simply can't tell.""")

fan = [tbox(0, 180, 440, 150, "Aram Vardanyan", ["moneySpent", c("13,544.72", AMBER)], center=True)]
for i in range(4):
    top = i * 100
    fan.append(tbox(640, top, 340, 70, "one of his orders", tsize=24, center=True))
    fan.append(line(440, 255, 640, top + 35, FAINT, 2))
    fan.append(plabel(1080, top + 16, 584, c("13,544.72", AMBER), FG, 28))
fan += [plabel(640, 410, 340, "… 40 rows", FAINT, 26, align="center"), plabel(1080, 410, 584, "… 40 times", FAINT, 26),
        plabel(1080, 470, 584, "sum = " + c("541,788.80", RED), FG, 32, weight=600)]
slide("m-fanout", "05 · more joins · fan-out", "Fan-out: one row, counted 40 times",
    host(1664, 520, *fan)
    + p(f'All customers: sum(c.moneySpent) over the join = {c("4,079,958.38", RED)}. The whole year’s revenue is {c("145,935.12", GREEN)}. Count rows before you trust a sum.', SOFT, 30),
    gap=36,
    note="""customers JOIN orders repeats each customer once per order: correct and useful, until you sum a column that belongs to the customer. After the join the grain is one row per order (Lecture 3's grain lesson). Check: count(*) = 600 rows, count(DISTINCT customerID) = 28.
Stored vs computed demo: LEFT JOIN orders ON ... AND o.status = 'completed', GROUP BY customer, HAVING moneySpent <> coalesce(sum(orderTotal), 0) → 0 rows today. Drop the status filter → 24 'disagree'. moneySpent is one forgotten UPDATE away from wrong; the join is right every time.""")

BANDS = [("under 50", 149, "3,486.93"), ("50 – 299", 235, "33,852.39"), ("300 – 999", 113, "62,525.00"), ("1000+", 32, "46,070.80")]
bars = []
for name, n, rev in BANDS:
    h = round(n / 235 * 340)
    bars.append(col(p(str(n), FG, 32, True, 600, "; text-align:center"),
                    f'<div style="height:340px; display:flex; align-items:flex-end; justify-content:center"><div style="width:150px; height:{h}px; background:{BLUE}; border-radius:6px 6px 0px 0px"></div></div>',
                    p(name, AMBER, 26, True, 600, "; text-align:center"), p(rev, FAINT, 24, True, 400, "; text-align:center"), gap=10, extra="; width:200px"))
slide("m-nonequi", "05 · more joins · any condition", "ON can be any condition",
    row(row(*bars, gap=24),
        col(p("completed orders joined to price bands:", SOFT, 30),
            p(f'{kw("ON")} o.orderTotal &gt;= b.low<br>{kw("AND")} o.orderTotal &lt;&#160; b.high', FG, 30, True),
            p("A match by range, not by key. Tax brackets, commission tiers and “which promotion was running” are joins like this.", SOFT, 30), gap=28, extra="; flex:1"),
        gap=80, extra="; align-items:flex-end"),
    note="""The bands are a small table typed into the query with VALUES. A join whose condition isn't = is a non-equi join: same machinery, every combination, keep the ones that pass. Bars show order counts per band; the number under each is completed revenue.""")

# ============================================================================
# PART 6 — BUILD A STAR
# ============================================================================
section("star", "Part 6: building a star schema from the normalized tables", "st-build")

slide("st-build", "06 · build a star", "Build a star from the four tables",
    row(img("star-build", 1120, 580, "The four normalized tables feed CREATE TABLE AS SELECT into a star with row counts"),
        side_text(c("key 0 · Online", AMBER) + ": the web shop gets its own employee row.",
                  "Every fact has an employee key, so no join can lose the web shop.",
                  "Kimball: never leave a fact table’s foreign key NULL; add a default dimension row."), gap=48, extra="; align-items:center"),
    note="""Run Part 6 of the notes. dim_date from generate_series: 366 rows, Sundays included. dim_employee is the self-join from Part 5 plus INSERT (0, '(online)', 'Online', '(none)'), following Kimball Group, 'Nulls in Fact Tables'. fact_sales: coalesce(employeeID, 0), cost = quantity * product cost, frozen at load.
Check: count(*) 600, completed revenue 145935.12. Query: completed revenue per branch per quarter with FILTER: Online 52400.41, Yerevan Center 48113.04, Yerevan Mall 35934.64, Gyumri 9487.03.""")

slide("st-etl", "06 · build a star · the price", "What the star costs",
    f'<div style="display:flex; gap:10px; align-items:center">'
    + fbox("orders, customers…", "normalized · the truth", FG) + arrow(40)
    + fbox("nightly ETL", "extract, transform, load", GREEN, GREEN) + arrow(40)
    + fbox("star schema", "a copy · a snapshot", AMBER, AMBER) + arrow(40)
    + fbox("dashboards", "a day behind", FG) + "</div>"
    + row(col(p("gained", GREEN, 36, True, 600), p("› one hop from the fact to every label", SOFT, 30), p("› quarter, weekday, manager precomputed", SOFT, 30),
              p("› no NULL keys, no coalesce", SOFT, 30), gap=14, extra="; flex:1"),
          col(p("paid", RED, 36, True, 600), p("› data copied: a city lives in two tables", SOFT, 30), p("› stale until the next rebuild", SOFT, 30),
              p("› someone must own the rebuild", SOFT, 30), gap=14, extra="; flex:1"), gap=80),
    note="""By Part 2's four rules the copying is fine: the normalized tables are still the truth, and the star is built from them by a query. But insert an order now and fact_sales doesn't know until someone re-runs the build. In a company that's a scheduled ETL job, and 'the dashboard is a day behind' is the price.""")

# ============================================================================
# PART 7 — DRILL
# ============================================================================
section("drill", "Part 7: verification drill and the four checks", "d-drill")

def q(n, text, res):
    return row(p(f"Q{n}", AMBER, 36, True, 600, "; width:80px"), col(p(text, FG, 32), p(res, FAINT, 26, True), gap=6, extra="; flex:1"), gap=24, extra="; align-items:baseline")
slide("d-drill", "07 · verification drill", "Four queries. No errors. All wrong.",
    col(q(1, "“Total completed revenue for 2024, with who sold it.”", "orders JOIN employees → 93534.71"),
        q(2, "“Customers with the fewest orders: who gets a reminder?”", "LEFT JOIN, count(*) → Levon 1, Astghik 1, Diana 4, Lusine 5"),
        q(3, "“Completed revenue for every category, including zero.”", "LEFT JOIN … WHERE status = 'completed' → 12 rows"),
        q(4, "“Average lifetime spend of customers who bought in December.”", "avg(c.moneySpent) over customers JOIN orders → 6821.14"), gap=40),
    note="""Queries: steps/07-drill.sql. Answers:
Q1 inner join dropped the 181 online orders; real figure 145,935.12.
Q2 count(*) counted the empty match; Levon and Astghik have 0 and are exactly who the email is for. Use count(o.orderID).
Q3 WHERE undid the LEFT JOIN; move status into ON: 13 rows, Chairs 0.
Q4 fan-out: one row per December order. Pick customers with IN (SELECT ...): 5,448.88 across 26 customers.""")

slide("d-checks", "take this with you", "Four checks for any join",
    col(*[row(p(str(i), GREEN, 40, True, 600), col(p(a, FG, 34, weight=600), p(b, SOFT, 30), gap=4), gap=32, extra="; align-items:baseline")
          for i, (a, b) in enumerate([("Did the inner join drop anything?", "count rows with and without the join"),
                                      ("Is a right-table condition in WHERE?", "move it to ON"),
                                      ("Does count(*) include empty matches?", "count the right table’s key"),
                                      ("One row per what, after the join?", "don’t sum a “one”-side column over “many”-side rows")], 1)], gap=32)
    + ruled(f'{c("next lecture:", GREEN)} queries inside queries, like the IN (SELECT …) from Q4, and saving a query under a name.', GREEN),
    note="""Summary line: FROM + JOINs → WHERE → GROUP BY → HAVING → SELECT → DISTINCT → ORDER BY → LIMIT.""")

# ---- index ------------------------------------------------------------------
deck = {
    "v": 4,
    "createdOnFiles": {"v": 1, "at": "2026-09-24T18:07:17Z"},
    "title": "Lecture 4 — Putting the Tables Back Together",
    "order": order,
    "sections": sections,
    "faces": {
        "ibm-plex-sans": {"family": "IBM Plex Sans", "href": "https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600;700&display=swap"},
        "jetbrains-mono": {"family": "JetBrains Mono", "href": "https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600&display=swap"},
    },
    "designSystems": [],
}
(ROOT / "deck.json").write_text(json.dumps(deck, indent=2, ensure_ascii=False) + "\n")
print(len(order), "slides")
