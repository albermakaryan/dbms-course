#!/usr/bin/env python3
"""
Build lecture-04-slides-dark.html: the Lecture 4 deck in the dark,
code-first look of the claude.ai version, as ONE self-contained local
file with its own small player.

    python3 build_dark.py      # writes ../lecture-04-slides-dark.html

Keys: → / Space / PageDown next · ← / PageUp back · Home / End ·
S speaker notes · O overview · F fullscreen · click right/left half.
The slide number is kept in the URL hash. Print (Ctrl+P) gives one
slide per page, notes included.

Content follows ../lecture-04-notes.md; SQL comes from
../lecture-04-demo.sql; every number is the demo's verified output.
"""
import html, re
from pathlib import Path

HERE = Path(__file__).parent

# ---- palette -----------------------------------------------------------------
BG, SURF, SURF2, LINE = "#0E1116", "#161B22", "#1C2430", "#30363D"
FG, SOFT, FAINT = "#E6EDF3", "#A3AEBB", "#7D8793"
GREEN, AMBER, RED, BLUE, PURPLE, SKY = "#7EE787", "#F2CC60", "#FF7B72", "#79C0FF", "#D2A8FF", "#A5D6FF"
MONO_STACK = "'JetBrains Mono', 'DejaVu Sans Mono', Consolas, monospace"
SANS_STACK = "'IBM Plex Sans', 'Segoe UI', Arial, sans-serif"

CSS = f"""
@import url('https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;600;700&family=JetBrains+Mono:wght@400;600&display=swap');
:root{{ --bg:{BG}; --surf:{SURF}; --surf2:{SURF2}; --line:{LINE}; --fg:{FG}; --soft:{SOFT}; --faint:{FAINT};
  --green:{GREEN}; --amber:{AMBER}; --red:{RED}; --blue:{BLUE}; --purple:{PURPLE}; --sky:{SKY};
  --mono:{MONO_STACK}; --sans:{SANS_STACK}; }}
*{{ box-sizing:border-box; margin:0; padding:0; font-variant-ligatures:none !important; font-feature-settings:'liga' 0, 'calt' 0 !important; }}
html,body{{ height:100%; background:#05070A; overflow:hidden; font-family:var(--sans); color:var(--fg); font-variant-ligatures:none; font-feature-settings:'liga' 0, 'calt' 0; }}
.row > .box{{ flex:1; min-width:0; }}
#stage{{ position:fixed; left:50%; top:50%; width:1920px; height:1080px; transform-origin:0 0; }}
.slide{{ position:absolute; inset:0; width:1920px; height:1080px; background:var(--bg); display:none; flex-direction:column;
  padding:112px 128px 150px; gap:44px; overflow:hidden; }}
.slide.active{{ display:flex; }}
.slide .notes{{ display:none; }}
.eyebrow{{ font:24px/1 var(--mono); color:var(--green); }}
h1.t{{ font:600 60px/1.15 var(--mono); letter-spacing:-1px; color:var(--fg); margin-top:14px; }}
.head{{ display:flex; flex-direction:column; }}
.body{{ flex:1; min-height:0; display:flex; flex-direction:column; gap:32px; }}
.src{{ position:absolute; left:128px; right:128px; bottom:52px; font:22px/1.35 var(--sans); color:var(--faint); }}
p, li{{ font:30px/1.45 var(--sans); color:var(--soft); }}
b, strong{{ color:var(--fg); font-weight:600; }}
code{{ font-family:var(--mono); font-size:.9em; color:var(--fg); }}
.row{{ display:flex; gap:56px; min-height:0; }}
.col{{ display:flex; flex-direction:column; gap:24px; flex:1; min-width:0; }}
.fixed{{ flex:0 0 auto; }}
.center{{ align-items:center; }}
.code{{ background:var(--surf); border:2px solid var(--line); border-radius:10px; padding:22px 28px; font:26px/1.55 var(--mono);
  color:var(--fg); white-space:pre; overflow:hidden; }}
.code .kw{{ color:var(--blue); }} .code .fn{{ color:var(--purple); }} .code .str{{ color:var(--sky); }}
.code .num{{ color:var(--amber); }} .code .com{{ color:var(--faint); }}
.err{{ background:#1F1215; border:2px solid #5A2A2A; border-radius:10px; padding:18px 28px; font:26px/1.5 var(--mono); color:var(--red); white-space:pre; }}
table.t{{ border-collapse:collapse; width:100%; font:24px/1.35 var(--mono); color:var(--fg); }}
table.t th{{ text-align:left; color:var(--faint); font-weight:600; padding:10px 16px; border-bottom:2px solid var(--line); }}
table.t td{{ padding:9px 16px; border-bottom:1px solid var(--line); }}
table.t.sans{{ font-family:var(--sans); font-size:27px; }}
table.t td.num, table.t th.num{{ text-align:right; }}
.key{{ display:flex; gap:40px; align-items:baseline; }}
.key .k{{ font:600 32px var(--mono); color:var(--amber); flex:0 0 auto; }}
.key .v{{ font:32px/1.4 var(--sans); color:var(--soft); }}
.ruled{{ border-left:4px solid var(--amber); padding:4px 0 4px 28px; font:32px/1.4 var(--sans); color:var(--fg); }}
.ruled.green{{ border-color:var(--green); }} .ruled.red{{ border-color:var(--red); }} .ruled.faint{{ border-color:var(--faint); }}
.big{{ font:600 88px/1 var(--mono); color:var(--fg); letter-spacing:-2px; white-space:nowrap; }}
.big.red{{ color:var(--red); }} .big.green{{ color:var(--green); }} .big.amber{{ color:var(--amber); }} .big.blue{{ color:var(--blue); }}
.biglabel{{ font:28px/1.4 var(--sans); color:var(--soft); margin-top:10px; }}
.box{{ background:var(--surf); border:2px solid var(--line); border-radius:10px; padding:28px 32px; display:flex; flex-direction:column; gap:14px; }}
.box h3{{ font:600 32px var(--mono); color:var(--green); }}
.box.amber{{ border-color:var(--amber); }} .box.amber h3{{ color:var(--amber); }}
.chev{{ color:var(--green); }}
.mono{{ font-family:var(--mono); }}
.statement{{ justify-content:center; }}
.statement .line{{ font:600 64px/1.3 var(--mono); color:var(--fg); letter-spacing:-1px; max-width:1600px; }}
.statement .line em{{ font-style:normal; color:var(--amber); }}
.statement .sub{{ font:34px/1.45 var(--sans); color:var(--soft); max-width:1500px; margin-top:36px; }}
.statement .quote{{ font:italic 32px/1.45 var(--sans); color:var(--soft); max-width:1500px; margin-top:36px; }}
.cover{{ justify-content:space-between; padding-bottom:112px; }}
/* player chrome */
#bar{{ position:fixed; left:0; bottom:0; height:4px; background:linear-gradient(90deg,var(--green),var(--blue)); width:0; transition:width .2s; z-index:5; }}
#count{{ position:fixed; right:16px; bottom:12px; font:600 13px var(--mono); color:rgba(230,237,243,.45); z-index:5; }}
#notes{{ position:fixed; left:0; right:0; bottom:0; max-height:34vh; overflow:auto; background:#0A0D12; border-top:3px solid var(--green);
  color:var(--fg); font:17px/1.55 var(--sans); padding:20px 44px; transform:translateY(100%); transition:transform .2s; z-index:10; }}
#notes.show{{ transform:none; }}
#notes .lbl{{ font:600 12px var(--mono); color:var(--green); letter-spacing:.1em; text-transform:uppercase; margin-bottom:8px; }}
#overview{{ position:fixed; inset:0; background:#05070A; z-index:20; display:none; overflow:auto; padding:40px; }}
#overview.show{{ display:block; }}
#grid{{ display:grid; grid-template-columns:repeat(5,1fr); gap:16px; max-width:1600px; margin:0 auto; }}
.thumb{{ aspect-ratio:16/9; background:var(--bg); border:2px solid var(--line); border-radius:6px; padding:12px; cursor:pointer;
  font:600 14px/1.3 var(--mono); color:var(--soft); position:relative; }}
.thumb:hover{{ border-color:var(--green); }}
.thumb span{{ display:block; color:var(--green); font-size:12px; margin-bottom:6px; }}
@media print{{
  @page{{ size:1920px 1080px; margin:0; }}
  html,body{{ overflow:visible; height:auto; background:var(--bg); }}
  #stage{{ position:static; transform:none !important; width:1920px; height:auto; }}
  .slide{{ position:relative; display:flex !important; page-break-after:always; }}
  #bar,#count,#notes,#overview{{ display:none !important; }}
}}
"""

JS = r"""
(function(){
  const slides=[...document.querySelectorAll('.slide')], stage=document.getElementById('stage');
  const bar=document.getElementById('bar'), count=document.getElementById('count');
  const notes=document.getElementById('notes'), ntext=document.getElementById('ntext');
  const ov=document.getElementById('overview'), grid=document.getElementById('grid');
  let i=Math.max(0,Math.min(slides.length-1,(parseInt(location.hash.slice(1),10)||1)-1));
  function fit(){ const s=Math.min(innerWidth/1920,innerHeight/1080);
    stage.style.transform='scale('+s+') translate(-50%,-50%)'; }
  function show(){ slides.forEach((s,k)=>s.classList.toggle('active',k===i));
    bar.style.width=((i+1)/slides.length*100)+'%'; count.textContent=(i+1)+' / '+slides.length;
    const n=slides[i].querySelector('.notes'); ntext.innerHTML=n?n.innerHTML:'(no notes)';
    history.replaceState(null,'','#'+(i+1)); }
  function go(k){ i=Math.max(0,Math.min(slides.length-1,k)); show(); }
  addEventListener('resize',fit);
  addEventListener('keydown',e=>{
    if(ov.classList.contains('show')){ if(['Escape','o','O'].includes(e.key)) ov.classList.remove('show'); return; }
    if(['ArrowRight',' ','PageDown'].includes(e.key)){ go(i+1); e.preventDefault(); }
    else if(['ArrowLeft','PageUp'].includes(e.key)){ go(i-1); e.preventDefault(); }
    else if(e.key==='Home') go(0); else if(e.key==='End') go(slides.length-1);
    else if(e.key==='s'||e.key==='S') notes.classList.toggle('show');
    else if(e.key==='f'||e.key==='F'){ document.fullscreenElement?document.exitFullscreen():document.documentElement.requestFullscreen(); }
    else if(e.key==='o'||e.key==='O'){ grid.innerHTML=''; slides.forEach((s,k)=>{ const d=document.createElement('div'); d.className='thumb';
        d.innerHTML='<span>'+(k+1)+'</span>'+(s.dataset.title||''); d.onclick=ev=>{ev.stopPropagation(); go(k); ov.classList.remove('show');};
        grid.appendChild(d); }); ov.classList.add('show'); }
  });
  document.addEventListener('click',e=>{ if(ov.classList.contains('show')||notes.contains(e.target)) return;
    if(e.clientX>innerWidth/2) go(i+1); else go(i-1); });
  fit(); show();
})();
"""

# ---- SQL highlighting ----------------------------------------------------------
KW = ("SELECT FROM JOIN LEFT RIGHT FULL CROSS INNER NATURAL ON USING WHERE GROUP BY ORDER HAVING AND OR AS IS NULL NOT "
      "EXCEPT LIMIT IN BETWEEN CREATE TABLE INSERT INTO VALUES DISTINCT FILTER DESC NULLS LAST CASE WHEN THEN ELSE END "
      "DATE INTERVAL TRUE").split()
FN = "count sum coalesce generate_series jsonb_agg jsonb_build_object EXTRACT to_char".split()
TOK = re.compile(r"('[^']*')|\b(" + "|".join(KW) + r")\b|\b(" + "|".join(FN) + r")\b|\b(\d+(?:\.\d+)?)\b")

def hl(line):
    code_, com = (line.split("--", 1) if "--" in line else (line, None))
    def rep(m):
        if m.group(1): return f'<span class="str">{m.group(1)}</span>'
        if m.group(2): return f'<span class="kw">{m.group(2)}</span>'
        if m.group(3): return f'<span class="fn">{m.group(3)}</span>'
        return f'<span class="num">{m.group(4)}</span>'
    out = TOK.sub(rep, html.escape(code_, quote=False))
    if com is not None:
        out += f'<span class="com">--{html.escape(com, quote=False)}</span>'
    return out

def code(sql, size=26, style=""):
    body = "\n".join(hl(l) for l in sql.strip("\n").split("\n"))
    return f'<div class="code" style="font-size:{size}px;{style}">{body}</div>'

def err(t):
    return f'<div class="err">{html.escape(t.strip(), quote=False)}</div>'

def tbl(headers, rows, sans=False, nums=(), style=""):
    cls = "t sans" if sans else "t"
    th = "".join(f'<th class="{"num" if k in nums else ""}">{h}</th>' for k, h in enumerate(headers))
    trs = "".join("<tr>" + "".join(f'<td class="{"num" if k in nums else ""}">{c}</td>' for k, c in enumerate(r)) + "</tr>" for r in rows)
    return f'<table class="{cls}" style="{style}"><thead><tr>{th}</tr></thead><tbody>{trs}</tbody></table>'

def key(k, v, w=None):
    ws = f' style="width:{w}px"' if w else ""
    return f'<div class="key"><div class="k"{ws}>{k}</div><div class="v">{v}</div></div>'

def ruled(t, kind=""):
    return f'<div class="ruled {kind}">{t}</div>'

def big(n, label, color=""):
    return f'<div><div class="big {color}">{n}</div><div class="biglabel">{label}</div></div>'

def box(title, body, cls=""):
    return f'<div class="box {cls}"><h3>{title}</h3>{body}</div>'

def row(*c, gap=56, extra=""):
    return f'<div class="row" style="gap:{gap}px;{extra}">' + "".join(c) + "</div>"

def col(*c, gap=24, extra=""):
    return f'<div class="col" style="gap:{gap}px;{extra}">' + "".join(c) + "</div>"

def P(t, extra=""):
    return f'<p style="{extra}">{t}</p>'

def ul(*items):
    return "".join(f'<p><span class="chev">›</span> {x}</p>' for x in items)

def c(t, color):
    return f'<span style="color:{color}">{t}</span>'

# ---- slide builders ------------------------------------------------------------
slides = []
N, D = "lecture-04-notes.md", "lecture-04-demo.sql"

def notes(n):
    return f'<div class="notes">{n}</div>' if n else ""

def src(s):
    return f'<div class="src">Source: {s}</div>' if s else ""

def slide(title, part, heading, body, note="", source=""):
    slides.append(f'''<section class="slide" data-title="{html.escape(title)}">
  <div class="head"><div class="eyebrow">-- {part}</div><h1 class="t">{heading}</h1></div>
  <div class="body">{body}</div>
  {src(source)}{notes(note)}
</section>''')

def statement(title, part, line, sub="", note="", source="", quote=""):
    s = f'<div class="sub">{sub}</div>' if sub else ""
    q = f'<div class="quote">{quote}</div>' if quote else ""
    slides.append(f'''<section class="slide statement" data-title="{html.escape(title)}">
  <div class="eyebrow">-- {part}</div>
  <div class="line" style="margin-top:28px;">{line}</div>{s}{q}
  {src(source)}{notes(note)}
</section>''')

# ---- dark SVG diagrams -----------------------------------------------------------
M = "JetBrains Mono, DejaVu Sans Mono, monospace"
S = "IBM Plex Sans, Arial, sans-serif"

def svg(w, h, inner, width=None):
    width = width or w
    return f'<svg viewBox="0 0 {w} {h}" width="{width}" height="{round(h*width/w)}" style="display:block">{inner}</svg>'

def entity(x, y, w, name, rows, accent=False):
    hc = AMBER if accent else FG
    bc = AMBER if accent else LINE
    h = 16 + 30 * len(rows)
    s = [f'<rect x="{x}" y="{y}" width="{w}" height="{44+h}" rx="8" fill="{SURF}" stroke="{bc}" stroke-width="2"/>',
         f'<rect x="{x}" y="{y}" width="{w}" height="44" rx="8" fill="{SURF2}"/>',
         f'<rect x="{x}" y="{y+30}" width="{w}" height="14" fill="{SURF2}"/>',
         f'<line x1="{x}" y1="{y+44}" x2="{x+w}" y2="{y+44}" stroke="{bc}" stroke-width="2"/>',
         f'<text x="{x+18}" y="{y+30}" font-family="{M}" font-weight="600" font-size="22" fill="{hc}">{name}</text>']
    for k, (tag, txt) in enumerate(rows):
        yy = y + 44 + 34 + 30 * k
        if tag:
            s.append(f'<text x="{x+18}" y="{yy}" font-family="{M}" font-weight="600" font-size="19" fill="{AMBER if tag=="PK" else BLUE}">{tag}</text>')
        s.append(f'<text x="{x+62}" y="{yy}" font-family="{M}" font-size="19" fill="{FG if tag else SOFT}">{txt}</text>')
    return "".join(s), y + 44 + h

def link(pts, color=FAINT):
    d = "M " + " L ".join(f"{a},{b}" for a, b in pts)
    return f'<path d="{d}" fill="none" stroke="{color}" stroke-width="2.5"/>'

def bar1(x, y):
    return f'<path d="M {x},{y-9} V {y+9} M {x+7},{y-9} V {y+9}" stroke="{FAINT}" stroke-width="2.5"/>'

def crow(x, y, side):
    d = -1 if side == "left" else 1
    return f'<path d="M {x+14*d},{y} L {x},{y-11} M {x+14*d},{y} L {x},{y} M {x+14*d},{y} L {x},{y+11}" stroke="{FAINT}" stroke-width="2.5" fill="none"/>'

def lab(x, y, t, anchor="start", color=FAINT, size=20):
    return f'<text x="{x}" y="{y}" font-family="{S}" font-size="{size}" fill="{color}" text-anchor="{anchor}">{t}</text>'

def star_svg():
    W, H = 1664, 600
    fact, fb = entity(632, 150, 400, "fact_sales", [("PK", "orderID"), ("FK", "dateKey"), ("FK", "customerKey"), ("FK", "productKey"),
                                                    ("FK", "employeeKey"), ("", "quantity · revenue · cost")], accent=True)
    parts = [
        link([(440, 90), (536, 90), (536, 250), (632, 250)]), bar1(450, 90), crow(632, 250, "left"),
        link([(440, 470), (536, 470), (536, 350), (632, 350)]), bar1(450, 470), crow(632, 350, "left"),
        link([(1224, 90), (1128, 90), (1128, 250), (1032, 250)]), bar1(1207, 90), crow(1032, 250, "right"),
        link([(1224, 470), (1128, 470), (1128, 350), (1032, 350)]), bar1(1207, 470), crow(1032, 350, "right"),
        lab(452, 74, "when"), lab(452, 500, "who bought"), lab(1206, 74, "what", "end"), lab(1206, 500, "who sold", "end"),
    ]
    d = [entity(40, 40, 400, "dim_date", [("PK", "dateKey"), ("", "quarter · month"), ("", "monthName · dayName")])[0],
         entity(40, 420, 400, "dim_customer", [("PK", "customerKey"), ("", "customerName · city"), ("", "signupYear")])[0],
         entity(1224, 40, 400, "dim_product", [("PK", "productKey"), ("", "productName · brand"), ("", "category")])[0],
         entity(1224, 420, 400, "dim_employee", [("PK", "employeeKey"), ("", "employeeName · branch"), ("", "managerName")])[0]]
    return svg(W, H, "".join(parts) + "".join(d) + fact + lab(632, fb + 36, "grain: one row per order · 600 rows", color=AMBER))

def snowflake_svg():
    W, H = 1664, 600
    fact, fb = entity(470, 150, 360, "fact_sales", [("PK", "orderID"), ("FK", "dateKey"), ("FK", "customerKey"), ("FK", "productKey"),
                                                    ("FK", "employeeKey"), ("", "revenue · cost")], accent=True)
    parts = [
        link([(360, 90), (415, 90), (415, 250), (470, 250)]), bar1(370, 90), crow(470, 250, "left"),
        link([(360, 470), (415, 470), (415, 350), (470, 350)]), bar1(370, 470), crow(470, 350, "left"),
        link([(940, 250), (885, 250), (830, 250)]), bar1(923, 250), crow(830, 250, "right"),
        link([(940, 470), (885, 470), (885, 350), (830, 350)]), bar1(923, 470), crow(830, 350, "right"),
        link([(1300, 90), (1250, 90), (1250, 250), (1260, 250)]),
        link([(1370, 90), (1335, 90), (1335, 262), (1260, 262)], BLUE), bar1(1355, 90), crow(1260, 262, "right"),
        link([(1370, 470), (1335, 470), (1335, 300), (1260, 300)], BLUE), bar1(1355, 470), crow(1260, 300, "right"),
        lab(1370, 580, "split out of dim_product", color=BLUE),
    ]
    parts = [p for p in parts if "1250,90" not in p]
    d = [entity(20, 40, 340, "dim_date", [("PK", "dateKey"), ("", "quarter · dayName")])[0],
         entity(20, 420, 340, "dim_customer", [("PK", "customerKey"), ("", "customerName · city")])[0],
         entity(940, 190, 320, "dim_product", [("PK", "productKey"), ("", "productName"), ("FK", "categoryKey"), ("FK", "brandKey")])[0],
         entity(940, 420, 320, "dim_employee", [("PK", "employeeKey"), ("", "name · branch")])[0],
         entity(1370, 40, 274, "dim_category", [("PK", "categoryKey"), ("", "category")])[0],
         entity(1370, 420, 274, "dim_brand", [("PK", "brandKey"), ("", "brand")])[0]]
    return svg(W, H, "".join(parts) + "".join(d) + fact)

VN = [0]
def venn(kind, left, right, width=560):
    VN[0] += 1
    k = VN[0]
    ax, bx, cy, r = 210, 350, 170, 140
    f = [f'<defs><clipPath id="ca{k}"><circle cx="{ax}" cy="{cy}" r="{r}"/></clipPath></defs>']
    if kind in ("left", "full"): f.append(f'<circle cx="{ax}" cy="{cy}" r="{r}" fill="{BLUE}" fill-opacity=".32"/>')
    if kind in ("right", "full"): f.append(f'<circle cx="{bx}" cy="{cy}" r="{r}" fill="{BLUE}" fill-opacity=".32"/>')
    if kind == "inner": f.append(f'<circle cx="{bx}" cy="{cy}" r="{r}" fill="{BLUE}" fill-opacity=".45" clip-path="url(#ca{k})"/>')
    if kind in ("left", "right"): f.append(f'<circle cx="{bx}" cy="{cy}" r="{r}" fill="{BLUE}" fill-opacity=".25" clip-path="url(#ca{k})"/>')
    f += [f'<circle cx="{ax}" cy="{cy}" r="{r}" fill="none" stroke="{BLUE}" stroke-width="3"/>',
          f'<circle cx="{bx}" cy="{cy}" r="{r}" fill="none" stroke="{BLUE}" stroke-width="3"/>',
          f'<text x="{ax-70}" y="{cy+r+42}" font-family="{M}" font-size="24" fill="{FG}" text-anchor="middle">{left}</text>',
          f'<text x="{bx+70}" y="{cy+r+42}" font-family="{M}" font-size="24" fill="{FG}" text-anchor="middle">{right}</text>']
    return svg(560, 360, "".join(f), width)

def dotgrid(mode, width=620):
    orders = [("1001", 2), ("1002", 26), ("1003", 6)]
    custs = [(2, "Davit"), (6, "Narek"), (26, "Samvel")]
    x0, y0, dx, dy = 250, 110, 140, 90
    s = []
    for j, (cid, n) in enumerate(custs):
        s.append(f'<text x="{x0+dx*j}" y="40" font-family="{M}" font-weight="600" font-size="22" fill="{FG}" text-anchor="middle">{n}</text>')
        s.append(f'<text x="{x0+dx*j}" y="68" font-family="{M}" font-size="18" fill="{FAINT}" text-anchor="middle">id {cid}</text>')
    for k, (oid, oc) in enumerate(orders):
        s.append(f'<text x="10" y="{y0+dy*k+7}" font-family="{M}" font-size="21" fill="{SOFT}">{oid} → {oc}</text>')
        for j, (cid, _) in enumerate(custs):
            hit = oc == cid
            if mode == "all":
                s.append(f'<circle cx="{x0+dx*j}" cy="{y0+dy*k}" r="18" fill="{BLUE}" fill-opacity=".8"/>')
            else:
                s.append(f'<circle cx="{x0+dx*j}" cy="{y0+dy*k}" r="18" fill="{GREEN if hit else "none"}" stroke="{GREEN if hit else LINE}" stroke-width="3"/>')
    cap = "every order × every customer" if mode == "all" else "keep the pairs whose ids match"
    s.append(f'<text x="10" y="{y0+dy*3}" font-family="{S}" font-size="21" fill="{FAINT}">{cap}</text>')
    return svg(620, 400, "".join(s), width)

def orgchart(width=820):
    def bx(x, y, n, r, boss=False):
        return (f'<rect x="{x}" y="{y}" width="170" height="70" rx="8" fill="{SURF}" stroke="{AMBER if boss else LINE}" stroke-width="2"/>'
                f'<text x="{x+85}" y="{y+31}" font-family="{M}" font-weight="600" font-size="22" fill="{AMBER if boss else FG}" text-anchor="middle">{n}</text>'
                f'<text x="{x+85}" y="{y+56}" font-family="{S}" font-size="17" fill="{SOFT}" text-anchor="middle">{r}</text>')
    L = lambda d: f'<path d="{d}" fill="none" stroke="{FAINT}" stroke-width="2"/>'
    return svg(820, 380, "".join([
        L("M 410,80 V 110 M 95,110 H 725 M 95,110 V 140 M 305,110 V 140 M 515,110 V 140 M 725,110 V 140"),
        L("M 515,210 V 240 M 305,240 H 515 M 305,240 V 270 M 515,240 V 270"), L("M 725,210 V 270"),
        bx(325, 10, "Vahe", "Store Manager", True),
        bx(10, 140, "Gor", "Senior Sales"), bx(220, 140, "Ani", "Sales Associate"),
        bx(430, 140, "Hayk", "Senior Sales"), bx(640, 140, "Marine", "Senior Sales"),
        bx(220, 270, "Nare", "Sales Associate"), bx(430, 270, "Lilit", "Sales Associate"), bx(640, 270, "Arman", "Sales Associate"),
    ]), width)

def fanout_svg():
    s = [f'<rect x="10" y="130" width="360" height="100" rx="8" fill="{SURF}" stroke="{LINE}" stroke-width="2"/>',
         f'<text x="190" y="172" font-family="{M}" font-weight="600" font-size="24" fill="{FG}" text-anchor="middle">Aram Vardanyan</text>',
         f'<text x="190" y="206" font-family="{M}" font-size="20" fill="{AMBER}" text-anchor="middle">moneySpent 13,544.72</text>',
         lab(10, 115, "customers: 1 row"), lab(580, 22, "after JOIN orders: 1 row per order")]
    for k in range(4):
        y = 40 + k * 72
        s.append(f'<path d="M 370,180 L 580,{y+26}" stroke="{FAINT}" stroke-width="2" fill="none"/>')
        s.append(f'<rect x="580" y="{y}" width="480" height="52" rx="6" fill="{SURF}" stroke="{LINE}" stroke-width="2"/>')
        s.append(f'<text x="602" y="{y+34}" font-family="{M}" font-size="20" fill="{SOFT}">one of his orders   <tspan fill="{RED}" font-weight="600">13,544.72</tspan></text>')
    s.append(f'<text x="602" y="345" font-family="{M}" font-size="20" fill="{FAINT}">… 40 rows, 13,544.72 on every one</text>')
    s.append(lab(1140, 150, "sum over his rows", size=24, color=SOFT))
    s.append(f'<text x="1140" y="196" font-family="{M}" font-weight="600" font-size="36" fill="{RED}">= 541,788.80</text>')
    s.append(lab(1140, 232, "40 × 13,544.72, not 13,544.72", size=20))
    return svg(1664, 370, "".join(s))

def cost_svg():
    items = [("conceptual", "erase a box, redraw an arrow", 60, GREEN), ("logical", "rework keys and constraints on paper", 170, BLUE),
             ("physical", "ALTER TABLE on live data", 290, RED)]
    s = []
    for k, (n, w, h, colr) in enumerate(items):
        x = 20 + k * 560
        s.append(f'<rect x="{x}" y="{320-h}" width="110" height="{h}" rx="4" fill="{colr}" fill-opacity=".85"/>')
        s.append(f'<text x="{x+140}" y="190" font-family="{M}" font-weight="600" font-size="30" fill="{FG}">{n}</text>')
        s.append(f'<text x="{x+140}" y="228" font-family="{S}" font-size="22" fill="{SOFT}">{w}</text>')
    s.append(f'<line x1="20" y1="320" x2="1640" y2="320" stroke="{LINE}" stroke-width="2"/>')
    s.append(lab(20, 360, "bar height = the cost of changing your mind at that level (direction, not measured cost)"))
    return svg(1664, 370, "".join(s))

# ============================================================================
# SLIDES
# ============================================================================
slides.append(f'''<section class="slide cover" data-title="Title">
  <div class="eyebrow" style="font-size:28px;">$ psql lecture04</div>
  <div>
    <h1 class="t" style="font-size:104px; letter-spacing:-3px; line-height:1.08;">Putting the tables<br>back together<span style="color:{GREEN}">_</span></h1>
    <p class="mono" style="font-size:36px; margin-top:28px;">data models · dimensional modeling · star &amp; snowflake · JOIN</p>
  </div>
  <div style="display:flex; justify-content:space-between;"><p class="mono" style="font-size:24px; color:{FAINT};">Introduction to Databases &amp; SQL · Lecture 4</p><p class="mono" style="font-size:24px; color:{FAINT};">YSU · Data Science for Business</p></div>
  {notes("Last time we took one table apart question by question. Today we put four tables back together, and build a second, analytical schema on top. Setup: createdb lecture04; psql lecture04; \\i steps/00-setup.sql from the lecture_4 folder. Expect 600 / 30 / 8 / 37 / 600.")}
</section>''')

slide("Plan", "today", "Four parts, one running example",
    col(key("01", "three levels of a data model", 120), key("02", "dimensional modeling: facts, dimensions, grain", 120),
        key("03", "star vs. snowflake schema", 120), key("04", "JOINs, built from one idea — most of today", 120), gap=34)
    + ruled("Same shop, same data as Lecture 3: 600 orders, 30 customers, 8 employees, 37 products.", "green"),
    note="Part 4 is the long one. Parts 1–3 give the vocabulary; Part 4 is the skill.",
    source=f"{N}, scope line (600 / 30 / 8 / 37 / 600)")

slide("Where we left off", "where we left off", "We split one wide table into four",
    col(key("lecture 2", "split the flat sales file into four tables — one fact in one place", 280),
        key("lecture 3", "asked questions of one table at a time", 280),
        key("today", "put the four back together with JOIN, and build a second, analytical schema on top", 280), gap=40)
    + ruled("customers · employees · products · orders", "faint"),
    note="Everything today is either putting tables together (JOIN) or deciding what shape the tables should have in the first place.",
    source="Lecture 2 and Lecture 3 notes")

# ---- Part 1 ----
slide("Three levels", "01 · data models", "Conceptual → logical → physical",
    row(box("conceptual", P("<b>Entities and relationships.</b> No tables yet.") +
            P("“A customer places orders. An order is for one product. An employee may serve an order — or nobody does, if it’s online.”")),
        box("logical", P("<b>Tables, columns, keys, constraints.</b> Still DBMS-agnostic.") +
            P("<code>orders.customerID</code> — required foreign key<br><code>orders.employeeID</code> — optional")),
        box("physical", P("<b>How one engine stores it.</b>") +
            P("<code>\\d orders</code> shows exact types (<code>DECIMAL(10,2)</code>), constraints, defaults — and the index PostgreSQL built for the primary key."), "amber"),
        gap=36),
    note="The conceptual level is Lecture 2's ER diagram. Run \\d orders live: the Indexes line shows orders_pkey, a unique btree index PostgreSQL creates automatically for every primary key. Nobody asked for it — that's what 'physical' means.",
    source=f"{N}, Part 1; Wikipedia, “Data model” (three kinds, citing ANSI 1975); PostgreSQL 16 docs, CREATE TABLE")

slide("Cost of a mistake", "01 · data models", "The further right, the more a change costs",
    cost_svg() + ruled("A <code>VARCHAR(50)</code> that turns out too short, or a <code>SERIAL</code> that should have been <code>BIGINT</code>, means an <code>ALTER TABLE</code> on live data — or worse.", "red"),
    note="This is why we draw before we type. A wrong arrow on paper costs an eraser; the same decision in production costs an ALTER TABLE with real rows in the way (Lecture 2, Part 9). A VARCHAR(50) that turns out too short, or a SERIAL that should have been BIGINT.",
    source=f"{N}, Part 1; Lecture 2 notes, Part 9 (ALTER TABLE)")

# ---- Part 2 ----
slide("Fact vs. dimension", "02 · dimensional modeling", "Facts are events. Dimensions are their context.",
    tbl(["", "fact table", "dimension table"],
        [["holds", "an event, with numbers attached", "the context: who, what, where, when"],
         ["one row per", "thing that occurred — one order", "customer, product, employee, day"],
         ["in the demo", c("fact_sales", AMBER), c("dim_date · dim_customer · dim_product · dim_employee", GREEN)],
         ["columns", "quantity, revenue, cost + a key per dimension", "names, city, category, quarter"]], sans=True)
    + P("A second, purpose-built schema you build <b>alongside</b> the normal tables — when the question shifts from “record what happened” to “summarize everything so far.”"),
    note="The fact table is narrow and long: numbers plus keys. The dimensions are wide and short: labels. You add up facts; you group and filter by dimensions.",
    source=f"{N}, Part 2; Kimball Group, “Star Schemas and OLAP Cubes”; Wikipedia, “Star schema”")

statement("Grain", "02 · grain", "“One row = one order.”",
    sub="The <b>grain</b> is the one-sentence definition of what a single fact row <i>is</i> — decided <b>before</b> anything else. Get it wrong (one row per line item, by accident) and every aggregate on top silently means something else.",
    note="Kimball calls declaring the grain 'the pivotal step in a dimensional design'. Everything else — which dimensions, which measures — has to agree with that sentence. Grain returns in Part 4 as the fan-out trap.",
    source=f"{N}, Part 2; Kimball Group, “Grain”")

slide("dim_date", "02 · build tricks", "dim_date: generated once, not every query",
    row(code("""CREATE TABLE dim_date AS
SELECT d::date                      AS dateKey,
       EXTRACT(quarter FROM d)::int AS quarter,
       EXTRACT(month FROM d)::int   AS month,
       to_char(d, 'Mon')            AS monthName,
       EXTRACT(isodow FROM d)::int  AS dayOfWeek,
       to_char(d, 'Dy')             AS dayName
FROM generate_series(DATE '2024-01-01',
                     DATE '2024-12-31',
                     INTERVAL '1 day') AS d;""", 24, "flex:0 0 1000px;"),
        col(big("366", "rows — every day of 2024, a leap year. Sundays included, though the shop is closed.", "amber"),
            ul("quarter, month, day name: computed <b>once</b>, stored as columns",
               "no query ever works out “what quarter is this?” again"), gap=30)),
    note="Calendars are cheap to precompute and expensive to keep recomputing. A date dimension lists every day, not only the days something happened. Kimball: calendar date dimensions are attached to virtually every fact table.",
    source=f"{D}, Part 6 (CREATE TABLE dim_date → SELECT 366); Kimball Group, “Calendar Date Dimensions”")

slide("Unknown member", "02 · build tricks", "Make “missing” a value, not an absence",
    row(col(code("""INSERT INTO dim_employee
VALUES (0, '(online)', 'Online', '(none)');"""),
            P("and in the fact-table build:", f"color:{FAINT};font-size:26px;"),
            code("coalesce(o.employeeID, 0)   AS employeeKey")),
        col(ul("online orders have no employee: <code>employeeID IS NULL</code>",
               "row <b>0</b> gives them one — every fact row now has a valid, non-null employee key",
               "every join to <code>dim_employee</code> is ordinary, never a “what if it’s NULL” case"),
            ruled("Part 6 of the demo never needs LEFT JOIN against dim_employee. Plain inner joins lose nothing.", "green"))),
    note="Why this avoids LEFT JOIN: an inner join drops a row only when it finds no partner. With the unknown member, every fact row's employeeKey (0 for online) matches a real dim_employee row, so the inner join keeps all 600. Compare Part 4: the same inner join against raw employees keeps 419 of 600. Kimball: avoid nulls in fact-table foreign keys; use a default dimension row.",
    source=f"{D}, Part 6; {N}, Part 2; Kimball Group, “Nulls in Fact Tables”")

# ---- Part 3 ----
slide("Star schema", "03 · star", "Star: one fact, flat dimensions around it", star_svg(),
    note="Exactly what Part 6 of the demo builds: fact_sales in the middle, four flat dimensions attached directly. Every 'by what?' is one join from the fact. Line ends: double bar = exactly one, crow's foot = many.",
    source=f"{D}, Part 6 (tables and columns); Kimball Group, “Star Schemas and OLAP Cubes”")

slide("Snowflake schema", "03 · snowflake", "Snowflake: a dimension split into sub-tables", snowflake_svg(),
    note="dim_product normalized into dim_product + dim_category + dim_brand, each joined in turn. Revenue by category is now two hops from the fact. The other dimensions stay flat: snowflaking is per dimension. This split is the notes' example; the demo builds only the star.",
    source=f"{N}, Part 3 (the dim_category / dim_brand example); Kimball Group, “Snowflaked Dimensions”")

slide("Star vs snowflake", "03 · comparison", "Less redundancy, more joins",
    tbl(["", "star", "snowflake"],
        [["dimension shape", "one flat table per dimension", "a dimension split into sub-tables"],
         ["redundancy", "category and brand repeated on every product row", "each category and brand stored once"],
         ["joins per query", "one hop: fact → dimension", "one more hop per sub-table"],
         ["navigability", "one table per “by what?”", "analyst must know the chain"],
         ["default?", c("yes", GREEN), c("only as an exception", RED)]], sans=True),
    note="Snowflaking buys less redundancy and costs more joins and more tables to navigate — a bad trade most of the time. Wikipedia adds that dimension tables are small next to the fact table, so the space saved is often negligible.",
    source=f"{N}, Part 3; Kimball Group, “Snowflaked Dimensions”; Wikipedia, “Snowflake schema”")

statement("Kimball's guidance", "03 · the default", "Star by default. Snowflake only as <em>the exception</em> — with a specific, concrete reason.",
    quote="“We generally encourage you to handle many-to-one hierarchical relationships in a single dimension table rather than snowflaking.” — Kimball Group, Design Tip #105",
    note="Kimball's reasons: snowflakes are harder for business users to navigate and can hurt query performance; a flat dimension holds the same information. Outriggers are 'acceptable in moderation' but 'the exception rather than the rule'. The notes' example reason is a huge dimension; Kimball himself calls the storage savings minimal.",
    source="Kimball Group, Design Tip #105, “Snowflakes, Outriggers, and Bridges” (2008)")

slide("Naming trap", "03 · naming trap", "“Snowflake” means two unrelated things",
    row(box("snowflake schema", ul("a <b>shape</b>: a dimensional model whose dimensions are normalized into sub-tables", "what this part is about")),
        box("Snowflake Inc.", ul("a <b>company</b> (founded 2012) selling a cloud data platform", "you can build a star schema in it — the name is a coincidence"), "amber"), gap=36),
    note="Say it out loud: the schema shape and the product are unrelated. A job ad asking for 'Snowflake experience' means the product.",
    source=f"{N}, Part 3; Wikipedia, “Snowflake Inc.”")

# ---- Part 4 ----
statement("The one idea", "04 · the thesis", "A join is: pair every row of A with every row of B, <em>then keep the pairs you want.</em>",
    sub="Every join type is a variation on two questions: which pairs do we keep, and what do we do with the rows that found no pair?",
    note="That's genuinely it. CROSS JOIN isn't a weird separate thing — it's the whole Cartesian product before anything is thrown away. We start there.",
    source=f"{N}, Part 4.0")

slide("CROSS JOIN", "04 · step 1 of 3", "CROSS JOIN: every row × every row",
    row(col(code("SELECT count(*) FROM orders CROSS JOIN customers;"),
            big("18,000", "rows = 600 orders × 30 customers. Every possible pairing — most of them nonsense.", "amber"),
            P("PostgreSQL defines <code>A CROSS JOIN B</code> as exactly <code>A INNER JOIN B ON TRUE</code>: a join whose condition can never fail."), gap=30),
        f'<div class="fixed">{dotgrid("all")}</div>'),
    note="Guess before running it. No order belongs to all 30 customers — this is every possible pairing, the raw material every other join is carved out of. The grid zooms in on 3 orders × 3 customers.",
    source=f"{D} (18000); PostgreSQL 16 docs, “Joined Tables” (CROSS JOIN ≡ INNER JOIN ON TRUE; N × M rows)")

slide("WHERE narrows the pairs", "04 · step 2 of 3", "Filter the pairs with WHERE: 9 → 3",
    row(col(code("""SELECT o.orderID, c.firstName, c.lastName
FROM orders o CROSS JOIN customers c
WHERE o.orderID IN (1001, 1002, 1003)
  AND c.customerID IN (2, 6, 26)
  AND o.customerID = c.customerID
ORDER BY o.orderID;""", 24),
            P("without the last condition: <b>9 rows</b> · with it: <b>3 rows</b>"),
            tbl(["orderid", "firstname", "lastname"], [["1001", "Davit", "Petrosyan"], ["1002", "Samvel", "Nazaryan"], ["1003", "Narek", "Manukyan"]])),
        f'<div class="fixed">{dotgrid("match")}</div>'),
    note="First run it without the last AND: 9 rows, each order next to all three customers. Ask which three pairs are true. Then add o.customerID = c.customerID: 3 rows.",
    source=f"{D}, Part 3 (9 rows, then 3 rows)")

slide("JOIN ... ON", "04 · step 3 of 3", "Now write it as JOIN … ON — same 3 rows",
    row(col(code("""SELECT o.orderID, c.firstName, c.lastName, o.orderTotal
FROM orders o
JOIN customers c ON c.customerID = o.customerID
WHERE o.orderID IN (1001, 1002, 1003)
ORDER BY o.orderID;""", 24),
            tbl(["orderid", "firstname", "lastname", "ordertotal"],
                [["1001", "Davit", "Petrosyan", "211.65"], ["1002", "Samvel", "Nazaryan", "249.00"], ["1003", "Narek", "Manukyan", "747.00"]], nums=(3,))),
        col(ul("seen first, <b>JOIN … ON</b> looks like a magic combine-tables command",
               "seen <b>derived</b> from CROSS JOIN + WHERE, it’s just filtered pairing",
               "the database never builds all 18,000 pairs — but the answer is always the same as if it had"), extra="flex:0 0 560px;")),
    note="JOIN alone means INNER JOIN. PostgreSQL's planner picks a nested-loop, merge or hash join by estimated cost, and every plan produces the same result: think the slow way, let the database do the fast one.",
    source=f"{D}, Part 3; {N}, Part 4.1; PostgreSQL 16 docs, “Planner/Optimizer”")

slide("INNER JOIN", "04 · inner join", "INNER JOIN keeps only pairs that match",
    row(f'<div class="fixed">{venn("inner", "orders", "employees", 500)}</div>',
        col(code("""SELECT count(*)
FROM orders o
JOIN customers c ON c.customerID = o.customerID
JOIN products  p ON p.productID  = o.productID
JOIN employees e ON e.employeeID = o.employeeID;""", 24),
            row(big("419", "rows, not 600", "blue"), big("181", "online orders gone: employeeID IS NULL matches nobody", "red"), gap=64)), extra="align-items:center;")
    + ruled("An inner join doesn’t complain when rows don’t match — it just quietly leaves them out.", "red"),
    note="Anything with no match simply disappears — no error, no placeholder. The Venn shows which rows survive, not how many rows come out: a join can also multiply rows (the fan-out trap later).",
    source=f"{D}, Part 4 (419); {N}, Part 4.2; PostgreSQL 16 docs, “Joined Tables”")

statement("93,534.71", "04 · inner join", f'<span style="font-size:120px; color:{RED};">93,534.71</span>',
    sub="“Completed revenue”, after joining employees to get the names. A real sum, correctly computed — over a silently incomplete set of rows. The real figure is <b>145,935.12</b>.",
    note="Query: SELECT sum(o.orderTotal) FROM orders o JOIN employees e ON e.employeeID = o.employeeID WHERE o.status = 'completed'. Ask: what on screen would make you suspicious? Nothing — only knowing that online orders have no employee.",
    source=f"{D}, Part 4 (93534.71); {N}, Part 4.2")

slide("Ambiguous column", "04 · aliasing", "Two tables, one column name: ambiguous",
    code("""SELECT orderID, customerID, firstName
FROM orders
JOIN customers ON customers.customerID = orders.customerID
WHERE orderID = 1001;""")
    + err('ERROR:  column reference "customerid" is ambiguous')
    + col(ul("<b>customerID</b> exists in both tables; the engine refuses to guess — even though the values are equal on every joined row",
             "fix: alias and qualify — <code>FROM orders o JOIN customers c</code>, then <code>o.customerID</code>"), gap=8),
    note="Error on purpose — read the message aloud. The rule is about names, not values. Habit: in any multi-table query, prefix every column.",
    source=f"{D}, Part 3 (error text from running it); {N}, Part 4.3")

slide("Alias replaces the name", "04 · aliasing", "An alias doesn’t add a nickname — it replaces the name",
    code("""SELECT orders.orderID
FROM orders o
WHERE o.orderID = 1001;""")
    + err('ERROR:  invalid reference to FROM-clause entry for table "orders"\nHINT:  Perhaps you meant to reference the table alias "o".')
    + P("Once you write <code>FROM orders o</code>, the name <code>orders</code> stops existing for the rest of the query. PostgreSQL’s hint tells you exactly what happened."),
    note="Error on purpose. The HINT is PostgreSQL telling you the fix. Same idea returns in self-joins, where aliases are the only way to tell two copies of one table apart.",
    source=f"{D}, Part 3 (error and hint text from running it); {N}, Part 4.3")

slide("USING and NATURAL", "04 · shorthand", "USING is shorthand. NATURAL JOIN hides the condition.",
    row(col(code("""SELECT customerID, c.firstName, o.orderID
FROM orders o
JOIN customers c USING (customerID)
WHERE o.orderID = 1001;""", 24),
            P("<b>USING (customerID)</b> = <code>ON o.customerID = c.customerID</code>, and the column appears once in the output.")),
        col(code("SELECT count(*)\nFROM orders NATURAL JOIN sales;", 24),
            big("97", "rows — both tables hold the same 600 sales", "red")))
    + ruled("NATURAL JOIN joined on all 12 shared column names — deliveryDate and rating among them. NULL = NULL is not true, so rows with a NULL there vanished. And it changes silently the day either table gains a matching column. Never use it in real code.", "red"),
    note="The two tables share twelve column names; all twelve had to be equal. Only online orders that also got a rating survive: 97. The PostgreSQL manual calls NATURAL 'considerably more risky' than USING. Takeaway: the join condition should always be visible in the code you're reading.",
    source=f"{D}, Part 3 (97); PostgreSQL 16 docs, “Joined Tables” and “Comparison Functions”")

def outer(title, kind, heading, left, right, sql, extra, note, source):
    slide(title, "04 · outer joins", heading,
        row(f'<div class="fixed">{venn(kind, left, right, 500)}</div>', col(code(sql, 24), extra), extra="align-items:center;"),
        note=note, source=source)

outer("LEFT JOIN", "left", "LEFT JOIN: keep every row on the left", "orders", "employees", """SELECT count(*)
FROM orders o
LEFT JOIN employees e ON e.employeeID = o.employeeID;""",
    big("600", "rows — the 181 online orders survive, employee columns NULL", "green")
    + P("Group by <code>coalesce(e.branch, 'Online')</code> and web revenue lands in a visible “Online” bucket: <b>52,400.41</b> — the largest of the four."),
    "INNER JOIN, but we refuse to lose rows from the left. 'Left' is the table written before JOIN. Completed revenue per branch: Online 52,400.41; Yerevan Center 48,113.04; Yerevan Mall 35,934.64; Gyumri 9,487.03.",
    f"{D}, Part 4 (600; revenue per branch); PostgreSQL 16 docs, “Joined Tables”")

outer("RIGHT JOIN", "right", "RIGHT JOIN: the mirror image", "orders", "customers", """SELECT count(*)
FROM orders o
RIGHT JOIN customers c
       ON c.customerID = o.customerID;""",
    big("602", "rows: all 600 orders + one NULL-padded row for each of the 2 customers who never ordered", "blue")
    + P("Identical to <code>customers LEFT JOIN orders</code>. Keep the table you care about on the left and you never need RIGHT."),
    "A RIGHT JOIN B keeps every row of B, which makes it B LEFT JOIN A. Writing LEFT always is this course's style choice.",
    f"{D}, Part 4 (602); PostgreSQL 16 docs, “Joined Tables”")

outer("FULL JOIN", "full", "FULL JOIN: keep everything from both sides", "customers", "employees", """SELECT CASE WHEN e.employeeID IS NULL THEN 'customer only'
            WHEN c.customerID IS NULL THEN 'employee only'
            ELSE 'on both lists' END AS status,
       count(*) AS people
FROM customers c
FULL JOIN employees e
  ON e.firstName = c.firstName
 AND e.lastName  = c.lastName
GROUP BY 1 ORDER BY 1;""",
    tbl(["status", "people"], [["customer only", "28"], ["employee only", "6"], ["on both lists", "2"]], nums=(1,), style="max-width:560px;"),
    "LEFT and RIGHT combined — the classic tool for reconciling two lists. 28 + 6 + 2 = 36 people. Hold on to the 2 'on both lists': the name-collision trap is coming.",
    f"{D}, Part 4 (28 / 6 / 2); PostgreSQL 16 docs, “Joined Tables”")

slide("Anti-join", "04 · outer joins", "The anti-join: LEFT JOIN + IS NULL",
    row(col(code("""SELECT c.customerID, c.firstName, c.lastName
FROM customers c
LEFT JOIN orders o ON o.customerID = c.customerID
WHERE o.orderID IS NULL;""", 24),
            tbl(["customerid", "firstname", "lastname"], [["24", "Levon", "Arakelyan"], ["29", "Astghik", "Danielyan"]])),
        col(row(big("2", "of 30 customers with zero orders", "amber"), big("1", "of 37 products never ordered: #35 Ergonomic Chair Pro, 6 in stock", "amber"), gap=48),
            ul("a real match would fill the right-hand columns — NULL there means <b>nothing matched</b>",
               "test the right table’s <b>key</b>: a primary key is never NULL in a real row"))),
    note="Teach it as a named pattern: 'which X have no Y' — customers with no orders, products never sold, employees with no reports. The flat sales table could never answer this: a table of sales only contains things that sold.",
    source=f"{D}, Part 4 (anti-join queries); {N}, Part 4.5")

slide("count(*) vs count(column)", "04 · sanity check", "count(*) counts rows. count(col) counts non-NULLs.",
    row(col(code("""SELECT c.firstName, count(*) AS orders
FROM customers c
LEFT JOIN orders o
  ON o.customerID = c.customerID
GROUP BY c.customerID, c.firstName;""", 24),
            tbl(["firstname", "orders"], [["Levon", c("1", RED)], ["Astghik", c("1", RED)]], nums=(1,))),
        col(code("""SELECT c.firstName, count(o.orderID) AS orders
FROM customers c
LEFT JOIN orders o
  ON o.customerID = c.customerID
GROUP BY c.customerID, c.firstName;""", 24),
            tbl(["firstname", "orders"], [["Levon", c("0", GREEN)], ["Astghik", c("0", GREEN)]], nums=(1,))))
    + ruled("After every outer join, run both. They should diverge exactly at the unmatched rows — if they don’t, the join is wrong.", "green"),
    note="Levon has no orders, but the LEFT JOIN gave him one row full of NULLs, and count(*) counts rows. count(o.orderID) skips the NULL. The demo query also orders by the count and shows Diana (4) and Lusine (5), where both versions agree.",
    source=f"{D}, Part 4 (count queries); PostgreSQL 16 docs, “Aggregate Functions”")

slide("WHERE vs ON: the rule", "04 · the most important trap", "WHERE vs. ON: it depends on when each runs",
    tbl(["", "ON", "WHERE"],
        [["runs", "<b>while</b> deciding what matches — before NULL-padding", "<b>after</b> the whole join, NULL-padding included"],
         ["inner join", "same result", "same result"],
         ["outer join", "keeps the unmatched rows", c("can delete the NULL-padded rows — LEFT becomes INNER", RED)]], sans=True)
    + P("A <code>WHERE</code> that mentions the right-hand table after a LEFT JOIN should make you stop and ask: am I filtering matches, or un-inviting the rows my LEFT JOIN was supposed to protect?"),
    note="The PostgreSQL manual: a restriction in ON is processed before the join, one in WHERE after the join — 'That does not matter with inner joins, but it matters a lot with outer joins.'",
    source=f"{N}, Part 4.7; PostgreSQL 16 docs, “Joined Tables” (ON vs. WHERE)")

slide("WHERE version", "04 · where vs on · 1", "Filter in WHERE → 12 rows, Chairs gone",
    row(code("""SELECT p.category, count(o.orderID) AS orders,
       sum(o.orderTotal) AS revenue
FROM products p
LEFT JOIN orders o ON o.productID = p.productID
WHERE o.status = 'completed'
GROUP BY p.category
ORDER BY revenue DESC NULLS LAST;""", 24, "flex:0 0 900px;"),
        col(tbl(["category", "orders", "revenue"], [["Laptops", "46", "53412.00"], ["Phones", "38", "25991.90"], ["…", "…", "…"], ["Networking", "17", "2225.75"], ["Cables", "77", "1651.17"]], nums=(1, 2)),
            big("12 rows", "no Chairs row", "red"))),
    note="The LEFT JOIN runs first and keeps the Chair row with o.status NULL. Then WHERE runs: NULL = 'completed' is not true, and the Chair row is thrown out. No error. Middle rows omitted to fit.",
    source=f"{D}, Part 4 (12 rows)")

statement("ON invites, WHERE decides", "04 · where vs on", "<em>ON</em> decides who gets invited to the party. <em>WHERE</em> decides who’s allowed to stay after it already happened.",
    sub="…including the guests the LEFT JOIN invited for free — the NULL-padded ones.",
    note="Use this line verbatim. The NULL-padded Chair row was a guest the LEFT JOIN invited for free; the WHERE clause showed it the door.",
    source=f"{N}, Part 4.7")

slide("ON version", "04 · where vs on · 2", "Same condition in ON → 13 rows, Chairs at 0",
    row(code("""SELECT p.category, count(o.orderID) AS orders,
       coalesce(sum(o.orderTotal), 0) AS revenue
FROM products p
LEFT JOIN orders o ON o.productID = p.productID
                  AND o.status = 'completed'
GROUP BY p.category
ORDER BY revenue DESC;""", 24, "flex:0 0 900px;"),
        col(tbl(["category", "orders", "revenue"], [["Laptops", "46", "53412.00"], ["Phones", "38", "25991.90"], ["…", "…", "…"], ["Cables", "77", "1651.17"], [c("Chairs", GREEN), c("0", GREEN), c("0", GREEN)]], nums=(1, 2)),
            big("13 rows", "Chairs present, revenue 0", "green"))),
    note="Rule: conditions on the right table of a LEFT JOIN go in ON; conditions on the left table go in WHERE. coalesce turns the NULL sum into 0 (sum of no rows is NULL).",
    source=f"{D}, Part 4 (13 rows); PostgreSQL 16 docs, “Aggregate Functions”")

slide("Self-join", "04 · self-joins", "Self-join: one table, two roles",
    row(col(code("""SELECT e.firstName || ' ' || e.lastName AS employee,
       m.firstName || ' ' || m.lastName AS manager
FROM employees e
LEFT JOIN employees m
       ON m.employeeID = e.managerID;""", 22),
            big("8", "rows — every employee, including Vahe, whose manager is NULL", "blue"),
            ul("<b>e</b> plays the employee, <b>m</b> the manager", "<b>LEFT</b>, or the top of the hierarchy disappears")),
        f'<div class="fixed">{orgchart(760)}</div>', extra="align-items:center;"),
    note="Unaliased, it's an error: table name \"employees\" specified more than once. The demo version also selects e.position. Any hierarchy stored as 'this table points to itself' — org charts, category trees, comment replies — uses this shape.",
    source=f"{D}, Part 5 (8 rows); steps/00-setup.sql (managerID values)")

slide("Self-join: two hops, counts", "04 · self-joins", "A second hop, and a count",
    row(col(code("""SELECT e.firstName AS employee,
       m.firstName AS manager,
       mm.firstName AS managers_manager
FROM employees e
LEFT JOIN employees m  ON m.employeeID  = e.managerID
LEFT JOIN employees mm ON mm.employeeID = m.managerID
WHERE e.branch <> 'Yerevan Center';""", 20),
            tbl(["employee", "manager", "mgr's mgr"], [["Hayk", "Vahe", ""], ["Marine", "Vahe", ""], ["Nare", "Hayk", "Vahe"], ["Lilit", "Hayk", "Vahe"], ["Arman", "Marine", "Vahe"]], style="font-size:21px;")),
        col(code("""SELECT m.firstName || ' ' || m.lastName AS manager,
       count(e.employeeID) AS direct_reports
FROM employees m
JOIN employees e ON e.managerID = m.employeeID
GROUP BY m.employeeID, m.firstName, m.lastName
ORDER BY direct_reports DESC;""", 20),
            tbl(["manager", "direct_reports"], [["Vahe Sahakyan", "4"], ["Hayk Melikyan", "2"], ["Marine Avagyan", "1"]], nums=(1,), style="font-size:21px;"))),
    note="Manager's manager: 5 rows. Report count: 3 rows — only people who manage someone appear, because this one is an inner join. 'All the way up' would need one more join per level.",
    source=f"{D}, Part 5 (5 rows; 3 rows)")

slide("Names are not identifiers", "04 · joining on the wrong thing", "Names are not identifiers",
    row(col(code("""SELECT c.firstName, c.lastName,
       c.birthDate AS customer_born,
       e.birthDate AS employee_born
FROM customers c
JOIN employees e ON e.firstName = c.firstName
                AND e.lastName  = c.lastName;""", 22),
            tbl(["name", "customer_born", "employee_born"], [["Hayk Melikyan", "1993-03-30", "1985-02-11"], ["Lilit Hovhannisyan", "1990-06-14", "1998-07-07"]], style="font-size:22px;")),
        col(big("2", "“matches” — four different people sharing two names", "red"),
            big("637", "rows from joining sales to customers by name — not 600. Each Anna Sargsyan row matched both Annas.", "red"), extra="flex:0 0 560px;"))
    + ruled("Only join on something guaranteed unique — a real key. Anything that merely “usually” identifies a row will eventually produce a false match, and the join won’t warn you.", "red"),
    note="These are the 2 'on both lists' from the FULL JOIN slide; the birth dates prove they're different people. Lecture 2 said it with two Annas: names are not keys.",
    source=f"{D}, Part 5 (2 rows; 637); {N}, Part 4.9")

statement("Fan-out: the number", "04 · the fan-out trap", f'<span style="font-size:48px; color:{SOFT};">Total lifetime spend of our customers:</span><br><span style="font-size:140px; color:{FG};">4,079,958.38</span>',
    sub=code("""SELECT sum(c.moneySpent) AS total_customer_spend
FROM customers c
JOIN orders o ON o.customerID = c.customerID;""", 26, "display:inline-block;"),
    note="Present it as if it were a real answer. Ask whether it looks plausible. A completely ordinary inner join — no outer join, no strange join type. That's why it's the most damaging trap. The real total, sum(moneySpent) FROM customers, is 145,935.12.",
    source=f"{D}, Part 5 (4079958.38)")

slide("Fan-out: why", "04 · the fan-out trap", "One customer value, copied onto every order row",
    fanout_svg()
    + col(ul("<b>customers.moneySpent</b> is one number per customer — customer grain",
             "<b>orders</b> has many rows per customer — order grain; the join copies moneySpent onto every one: not divided, not split, <b>copied whole</b>"), gap=6),
    note="Aram placed 40 orders, so his 13,544.72 is summed 40 times. Do that for every customer and you get 4,079,958.38. After this join the result has one row per order, not one per customer.",
    source=f"{D}, Part 5; customers.moneySpent and order counts (Aram Vardanyan: 40 orders)")

slide("Fan-out: proof", "04 · the fan-out trap", "Count before you sum",
    row(col(code("""SELECT count(*) AS rows,
       count(DISTINCT c.customerID) AS customers
FROM customers c
JOIN orders o ON o.customerID = c.customerID;""", 24),
            row(big("600", "rows summed", "red"), big("28", "real customers with orders", "blue"), gap=72)),
        f'<div style="flex:0 0 620px; display:flex;">' + box("the fix, in general", ul("aggregate the fine-grain table <b>first</b>, then join the result back — one row per customer",
                                      "or don’t join at all if you already have the summary: <code>SELECT sum(moneySpent) FROM customers</code> → 145,935.12"), "amber") + "</div>"),
    note="Every customer's moneySpent got summed once per order they placed. 600 rows vs 28 customers is the tell.",
    source=f"{D}, Part 5 (600 / 28); {N}, Part 4.10")

statement("Fan-out: the question", "04 · the fan-out trap", "“Is the thing I’m summing at the same grain as the rows I’m joining through?”",
    sub="If not: am I about to sum the same value multiple times?",
    note="Ask it every time you aggregate after a join. It's the grain from Part 2, applied to a query instead of a schema.",
    source=f"{N}, Part 4.10")

slide("Range join", "04 · non-equality joins", "ON isn’t limited to =",
    row(code("""SELECT b.band, count(*) AS orders,
       sum(o.orderTotal) AS revenue
FROM orders o
JOIN (VALUES ('1. under 50',  0,    50),
             ('2. 50 - 299',  50,   300),
             ('3. 300 - 999', 300,  1000),
             ('4. 1000+',     1000, 100000))
     AS b(band, low, high)
  ON o.orderTotal >= b.low
 AND o.orderTotal <  b.high
WHERE o.status = 'completed'
GROUP BY b.band ORDER BY b.band;""", 21, "flex:0 0 880px;"),
        col(tbl(["band", "orders", "revenue"], [["1. under 50", "149", "3486.93"], ["2. 50 - 299", "235", "33852.39"], ["3. 300 - 999", "113", "62525.00"], ["4. 1000+", "32", "46070.80"]], nums=(1, 2), style="font-size:22px;"),
            P("Bucketing natively in SQL: each order lands in the band where <code>low &lt;= orderTotal &lt; high</code> — no CASE per row."))),
    note="VALUES builds a small table inline. The condition is a range, not key = key — same machinery: every combination, keep the pairs that pass.",
    source=f"{D}, Part 5 (price-band query)")

statement("A document is a join you saved", "04 · bridge", "A document is a join <em>you saved</em>.",
    sub="A denormalized JSON document is the materialized result of a one-to-many join. The relational model keeps the pieces separate and joins on demand; the document model pre-joins once and stores the result. Same information — a different point where the join cost is paid.",
    note="The demo builds one JSON document per customer with jsonb_agg: all of Diana's orders nested inside her customer object. Fast to read; keeping it right when Diana moves is the application's problem.",
    source=f"{N}, Part 4.12; {D}, Part 5 (jsonb_agg query)")

slide("Lossless", "04 · losslessness", "A runnable proof that nothing was lost",
    code("""SELECT o.orderID, o.orderDate, o.orderTime, …, p.brand, p.price, p.cost
FROM orders o
JOIN      customers c ON c.customerID = o.customerID
JOIN      products  p ON p.productID  = o.productID
LEFT JOIN employees e ON e.employeeID = o.employeeID
EXCEPT
SELECT * FROM sales;""", 24)
    + row(big("0 rows", "in both directions", "green"),
          P("Rebuild the flat file from the four tables, subtract the original: nothing left over. Swap the halves: nothing again. That’s <b>lossless-join decomposition</b> — as a query you can run, not a theory term."), extra="align-items:flex-start;"),
    note="The full SELECT lists all 29 columns of sales. The LEFT JOIN to employees matters, or the web shop is lost. EXCEPT treats two NULLs as equal (the manual states that rule for DISTINCT; the 0-row result shows EXCEPT does the same).",
    source=f"{D}, Part 4 (0 rows); PostgreSQL 16 docs, “Select Lists”")

slide("GROUP BY order", "04 · myth", "GROUP BY a, b  =  GROUP BY b, a",
    row(col(code("GROUP BY c.customerID, c.firstName, c.lastName"), code("GROUP BY c.lastName, c.firstName, c.customerID"),
            P("→ the same groups, the same totals", f"font-family:var(--mono); color:{GREEN};")),
        col(ul("a group is defined by the <b>combination</b> of values in the listed columns — order changes nothing",
               "if a total looks wrong, GROUP BY order is not the place to look — check for a <b>fan-out</b> first"))),
    note="PostgreSQL: GROUP BY groups together the rows that have the same values in all the columns listed. 'All the columns listed' is a set, not a sequence. Output order comes from ORDER BY. steps/15-group-by-order.sql proves it with EXCEPT → 0 rows.",
    source=f"{N}, Part 4.14; PostgreSQL 16 docs, “Table Expressions: GROUP BY”")

# ---- closing ----
statement("Three silent traps", "the one idea to leave with",
    f'NATURAL JOIN {c("600 → 97", RED)}<br>WHERE vs. ON {c("13 → 12", RED)}<br>fan-out {c("→ 4,079,958.38", RED)}',
    sub="None of them threw an error. All three returned a table that looked completely normal. <b>SQL correctness bugs are almost always silent</b> — and an AI assistant will write a plausible, syntactically perfect join whether the logic is right or not.",
    note="Nothing turns red. The query runs, returns rows, and is simply wrong. That's the whole point of this lecture.",
    source=f"{N}, Part 5")

slide("Checks", "take this with you", "Checks that catch a wrong-but-plausible answer",
    tbl(["check", "catches"],
        [[c("row count before / after", AMBER), "an inner join dropping rows (600 → 419); a join multiplying them (600 → 637)"],
         [c("count(*) vs count(col)", AMBER), "empty matches after an outer join (Levon: 1 vs 0)"],
         [c("count(DISTINCT key)", AMBER), "fan-out: 600 rows but only 28 customers"],
         [c("symmetric difference", AMBER), "anything lost or invented: EXCEPT both ways → 0 rows"]])
    + ruled("For anyone using AI to write SQL, this is not a side skill. It is the skill.", "green"),
    note="Each check is independent of the query it tests — that's what makes it a check. Run them before trusting anything downstream.",
    source=f"{N}, Part 5; numbers from {D}, Parts 4–5")

slide("Next lecture", "next lecture", "Queries inside queries",
    col(ul("the fan-out fix — “aggregate first, then join the result” — needs a query inside a query",
           "<b>subqueries</b>, and saving a query under a name so everyone asks the same question the same way"), gap=10)
    + P("Practice: steps/01 … steps/15 in the lecture_4 folder walk through every join on this slide deck.", f"color:{FAINT};"),
    note="Good place to stop and take questions.")

slide("Sources", "sources", "Where every claim comes from",
    col(*[P(x, "font-size:24px;") for x in [
        "lecture-04-notes.md and lecture-04-demo.sql — every number on these slides is the demo’s verified output.",
        "PostgreSQL 16 documentation: “Table Expressions” (Joined Tables, GROUP BY), CREATE TABLE, “Comparison Functions”, “Aggregate Functions”, “Select Lists”, “Planner/Optimizer” — postgresql.org/docs/16",
        "Kimball Group, Dimensional Modeling Techniques: “Star Schemas and OLAP Cubes”, “Grain”, “Calendar Date Dimensions”, “Nulls in Fact Tables”, “Snowflaked Dimensions” — kimballgroup.com",
        "Kimball Group, Design Tip #105, “Snowflakes, Outriggers, and Bridges” (2008)",
        "Wikipedia: “Data model”, “Star schema”, “Snowflake schema”, “Snowflake Inc.”",
        "Lecture 2 notes (ER diagrams, normal forms, ALTER TABLE) and Lecture 3 notes (grain)."]], gap=14))

# ---- assemble ------------------------------------------------------------------
out = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Putting the Tables Back Together — Lecture 4</title>
<style>{CSS}</style>
</head>
<body>
<div id="stage">
{chr(10).join(slides)}
</div>
<div id="bar"></div><div id="count"></div>
<div id="notes"><div class="lbl">Speaker notes · S to hide</div><div id="ntext"></div></div>
<div id="overview"><div id="grid"></div></div>
<script>{JS}</script>
</body>
</html>
"""
(HERE / "../lecture-04-slides-dark.html").write_text(out)
print(len(slides), "slides")
