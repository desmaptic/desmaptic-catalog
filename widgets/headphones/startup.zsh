#!/bin/zsh
# Headphones: battery of the connected Bluetooth headphones — AirPods left, right and case, or one battery — as small neon gauges
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
reader=0
trap '(( reader > 0 )) && kill $reader 2>/dev/null; exit 0' TERM INT
zmodload zsh/datetime zsh/zselect || { print -u2 -- "headphones: zsh modules datetime/zselect are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir 2>/dev/null

# ---- frame ----
# One template for every frame and both layouts: the rest glyph, nothing connected, AirPods, one battery.
# Only numbers, colours and text change, so the phone glides between frames. Attribute quotes are written as `
# and turned into " at the end.
read -r -d '' HEADPHONES_AWK <<'AWK'
function hex(h,   i, n) { n = 0; h = toupper(h); for (i = 1; i <= length(h); i++) n = n * 16 + index("0123456789ABCDEF", substr(h, i, 1)) - 1; return n }
function mix(a, b, t,   i, o, x, y) {
  o = "#"
  for (i = 2; i <= 6; i += 2) { x = hex(substr(a, i, 2)); y = hex(substr(b, i, 2)); o = o sprintf("%02X", int(x + (y - x) * t + 0.5)) }
  return o
}
function spectrum(t) {                         # the arc gradient, empty → full: #FF375F → #BF5AF2 (.35) → #5E5CE6 (.7) → #64D2FF
  if (t <= 0)   return "#FF375F"
  if (t < 0.35) return mix("#FF375F", "#BF5AF2", t / 0.35)
  if (t < 0.7)  return mix("#BF5AF2", "#5E5CE6", (t - 0.35) / 0.35)
  if (t < 1)    return mix("#5E5CE6", "#64D2FF", (t - 0.7) / 0.3)
  return "#64D2FF"
}
function f(x) { return sprintf("%.2f", x) }
function clamp(x, lo, hi) { return x < lo ? lo : (x > hi ? hi : x) }
function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); return s }
function glowGrad(id, c, a) {
  return "<radialGradient id=`" id "`><stop offset=`0` stop-color=`" c "` stop-opacity=`" f(a) "`/>" \
    "<stop offset=`0.4` stop-color=`" c "` stop-opacity=`" f(0.4 * a) "`/><stop offset=`1` stop-color=`" c "` stop-opacity=`0`/></radialGradient>"
}

# --- the device name: UTF-8 characters with estimated widths in ems of the system font ---
function kind(c) { return (c < "\200") ? 1 : (c < "\300") ? 0 : (c < "\340") ? 2 : (c < "\360") ? 3 : 4 }
function ascii(c) {
  if (c == " " || index(".,:;!|'", c)) return 0.28
  if (index("iIjl", c)) return 0.27
  if (index("()[]{}-/", c)) return 0.36
  if (index("frt", c)) return 0.38
  if (index("MWmw@%", c)) return 0.9
  if (c ~ /[A-Z]/) return 0.67
  if (c ~ /[0-9]/) return 0.62
  return 0.56
}
function wide(c, t) {                         # one character, in ems; Apple names it "Anna’s AirPods"
  if (t == 1) return ascii(c)
  if (c == "’" || c == "‘") return 0.28
  if (c == "“" || c == "”") return 0.45
  if (c == "–") return 0.56
  if (c == "—" || c == "…") return 1
  return (t == 2) ? 0.6 : (t == 3) ? 1 : 1.15
}
function brk(j) {                              # 2: a line may end after character j; 1: only if nothing better
  if (j >= n) return 2
  if (index(" .-_/", ch[j]) || ch[j + 1] == " " || ch[j + 1] == "(") return 2
  if (ch[j] ~ /[a-z]/ && ch[j + 1] ~ /[A-Z]/) return 1
  return 0
}
function put(s, e, extra,   j, t) {            # line nl = characters s…e, trailing spaces dropped
  while (e >= s && ch[e] == " ") e--
  t = ""
  for (j = s; j <= e; j++) t = t ch[j]
  NL[nl] = t extra
}
# Lays the name out in at most maxl lines of b ems; 0 when it does not fit or needs a mid-word break
# (unless clip: then it breaks anywhere and ends with "…").
function lay(b, maxl, clip,   s, e, x, j, bp) {
  nl = 0; s = 1
  while (s <= n) {
    while (s <= n && ch[s] == " ") s++
    if (s > n) break
    if (nl == maxl) return 0
    nl++; x = 0; e = s - 1
    while (e < n && x + w[e + 1] <= b) { e++; x += w[e] }
    if (e == n) { put(s, n, ""); return 1 }
    if (nl == maxl && clip) {
      x = 0; e = s - 1
      while (e < n && x + w[e + 1] <= b - 0.8) { e++; x += w[e] }
      while (e >= s && index(" .-_(", ch[e])) e--
      put(s, e, "…")
      return 1
    }
    bp = 0
    for (j = e; j >= s && !bp; j--) if (brk(j) == 2) bp = j
    for (j = e; j >= s && !bp; j--) if (brk(j) == 1) bp = j
    if (!bp) { if (!clip) return 0; bp = (e >= s) ? e : s }   # mid-word only as a last resort
    put(s, bp, "")
    s = bp + 1
  }
  return 1
}

# A small neon gauge: the disk-free arc (240°, lit from the empty end, white core, glow, halo and bead at the tip).
# v: level in %, -1 unknown; show: 0 hides the whole gauge; mk: "L", "R", "case" (a drawn case) or "%" (the unit under
# the value, as on the family's big gauge: the single battery); vz: value size.
function gauge(id, cx, cy, r, v, show, mk, vz,   L, k, known, fr, lit, crit, off, d, ang, bx, by, x1, x2, gc, a, o, out, arc, vt, vs, fill) {
  L = r * 4.18879                              # arc length: r · 240° = r · 4π/3
  k = r > 52 ? r / 52 : 1                      # strokes grow with the single, bigger gauge
  known = (v >= 0)
  fr = known ? clamp(v / 100, 0, 1) : 0
  o = live * show                              # the gauge is on the face
  lit = o * known                              # its level is known
  crit = known && v <= 20
  off = L * (1 - fr)                           # lit dash covers 0 … L·fr
  d = L * fr; if (d > L - 0.3) d = L - 0.3     # bead: a 0.1-long dash at L·fr, kept on the path
  ang = -120 + 240 * fr                        # the tip, degrees clockwise from 12 o’clock
  bx = cx + (r - 3) * sin(ang * pi / 180); by = cy - (r - 3) * cos(ang * pi / 180)
  x1 = cx - 0.95 * r; x2 = cx + 0.95 * r
  gc = crit ? "#FF375F" : spectrum((bx - x1) / (x2 - x1))   # the glow takes the arc colour under the bead
  arc = "d=`M " f(cx - 0.866025 * r) " " f(cy + r / 2) " A " r " " r " 0 1 1 " f(cx + 0.866025 * r) " " f(cy + r / 2) "` fill=`none`"
  fill = crit ? "#FF7A96" : "#FFFFFF"

  defs = defs "<linearGradient id=`" id "Spec` gradientUnits=`userSpaceOnUse` x1=`" f(x1) "` y1=`0` x2=`" f(x2) "` y2=`0`>" \
    "<stop offset=`0` stop-color=`#FF375F`/><stop offset=`0.35` stop-color=`#BF5AF2`/><stop offset=`0.7` stop-color=`#5E5CE6`/><stop offset=`1` stop-color=`#64D2FF`/></linearGradient>"
  defs = defs glowGrad(id "HeatG", gc, lit * (crit ? 0.95 : 0.55))

  out = "<path id=`" id "Track` " arc " stroke=`" (crit ? "#FF375F" : "#FFFFFF") "` stroke-opacity=`" f(o * (crit ? 0.3 : 0.18)) "` stroke-width=`" f(4 * k) "` stroke-linecap=`round`/>"
  out = out "<path id=`" id "Glow` " arc " stroke=`url(#" id "Spec)` stroke-opacity=`" f(0.2 * lit) "` stroke-width=`" f(14 * k) "` stroke-linecap=`round` stroke-dasharray=`" f(L) " " f(L) "` stroke-dashoffset=`" f(off) "`/>"
  out = out "<path id=`" id "Lit` " arc " stroke=`url(#" id "Spec)` stroke-opacity=`" f(lit) "` stroke-width=`" f(6 * k) "` stroke-linecap=`round` stroke-dasharray=`" f(L) " " f(L) "` stroke-dashoffset=`" f(off) "`/>"
  out = out "<path id=`" id "Core` " arc " stroke=`#FFFFFF` stroke-opacity=`" f(0.45 * lit) "` stroke-width=`" f(1.6 * k) "` stroke-linecap=`round` stroke-dasharray=`" f(L) " " f(L) "` stroke-dashoffset=`" f(off) "`/>"
  out = out "<circle id=`" id "Heat` cx=`" f(bx) "` cy=`" f(by) "` r=`" f((crit ? 22 : 18) * k) "` fill=`url(#" id "HeatG)`/>"
  out = out "<path id=`" id "Halo` " arc " stroke=`url(#" id "Spec)` stroke-opacity=`" f(lit * (crit ? 0.6 : 0.45)) "` stroke-width=`" f((crit ? 14 : 11) * k) "` stroke-linecap=`round` stroke-dasharray=`0.1 400` stroke-dashoffset=`" f(-d) "`/>"
  out = out "<path id=`" id "Bead` " arc " stroke=`#FFFFFF` stroke-opacity=`" f(lit) "` stroke-width=`" f(7.5 * k) "` stroke-linecap=`round` stroke-dasharray=`0.1 400` stroke-dashoffset=`" f(-d) "`/>"
  vt = known ? sprintf(mk == "%" ? "%d" : "%d%%", v + 0.5) : "—"
  vs = (length(vt) >= 4) ? vz - 4 : vz          # "100%" is one character wider
  out = out "<text id=`" id "Value` x=`" cx "` y=`" f(cy - 2) "` font-size=`" vs "` font-weight=`600` text-anchor=`middle` dominant-baseline=`middle` fill=`" fill "` fill-opacity=`" f(o * (known ? 1 : 0.6)) "`>" vt "</text>"
  a = o * (crit ? 0.95 : 0.6) * (mk != "")     # the mark under the value: white 0.6 like every unit of the family
  if (id == "c") {
    out = out "<rect id=`" id "Case` x=`" (cx - 13) "` y=`" f(cy + 0.48 * r) "` width=`26` height=`20` rx=`6.5` fill=`none` stroke=`" fill "` stroke-opacity=`" f(a) "` stroke-width=`2.5`/>"
    out = out "<line id=`" id "Lid` x1=`" (cx - 11) "` y1=`" f(cy + 0.48 * r + 7) "` x2=`" (cx + 11) "` y2=`" f(cy + 0.48 * r + 7) "` stroke=`" fill "` stroke-opacity=`" f(a) "` stroke-width=`2`/>"
    out = out "<circle id=`" id "Led` cx=`" cx "` cy=`" f(cy + 0.48 * r + 13.5) "` r=`2` fill=`" fill "` fill-opacity=`" f(a) "`/>"
  } else {
    out = out "<text id=`" id "Mark` x=`" cx "` y=`" f(cy + 0.48 * r + 10) "` font-size=`26` font-weight=`600` text-anchor=`middle` dominant-baseline=`middle` fill=`" fill "` fill-opacity=`" f(a) "`>" (mk != "" ? mk : "—") "</text>"
  }
  body = body out
  if (crit && show && live && (worst < 0 || v < worst)) { worst = v; wx = cx; wy = cy; wr = r }
}

BEGIN {
  pi = 3.14159265
  P = (ly != "l")
  live = (st == "live"); none = (st == "none")
  single = (mode == "single")
  vl += 0; vr += 0; vc += 0; vm += 0
  defs = ""; body = ""; worst = -1

  # --- layout: 2×1 is the name over three gauges in a row (one bigger gauge for a single battery);
  # its 1×2 landscape stacks them under the name ---
  if (P) {
    vb = "0 0 400 200"; r = 52; vz = 32; sr = 64; svz = 56
    ax = 72; ay = 126; bx0 = 200; by0 = 126; cx0 = 328; cy0 = 126; sy = 128
    NX = 200; W = 368; maxl = 1; ny = 34; sny = 34
    rgx = 200; rgy = 95; ngx = 200; ngy = 84; sgx = 200; sgy = 182; dy = 170     # glyph: rest, nothing connected, sunk
    brX = 200; brY = 118; brR = 170
  } else {
    vb = "0 0 200 400"; r = 42; vz = 28; sr = 64; svz = 56
    ax = 100; ay = 140; bx0 = 100; by0 = 238; cx0 = 100; cy0 = 336; sy = 252
    NX = 100; W = 184; maxl = 2; ny = 50; sny = 128
    rgx = 100; rgy = 195; ngx = 100; ngy = 172; sgx = 100; sgy = 378; dy = 264
    brX = 100; brY = 240; brR = 190
  }

  if (single) {
    gauge("a", ax, ay, r, -1, 0, "L", vz)
    gauge("b", bx0, sy, sr, vm, 1, "%", svz)
    gauge("c", cx0, cy0, r, -1, 0, "case", vz)
    ny = sny
  } else {
    gauge("a", ax, ay, r, vl, 1, "L", vz)
    gauge("b", bx0, by0, r, vr, 1, "R", vz)
    gauge("c", cx0, cy0, r, vc, 1, "case", vz)
  }

  # --- bloom: a soft violet glow; it heats up and moves onto the lowest gauge at 20 % and below ---
  bX = rgx; bY = rgy; bR = 120; bC = "#BF5AF2"; bA = 0.12; mC = "#5E5CE6"; bM = 0.04
  if (none) bA = 0.07
  if (live) { bX = brX; bY = brY; bR = brR; bA = 0.16; bM = 0.06 }
  if (worst >= 0) { bX = wx; bY = wy; bR = wr + 44; bC = "#FF375F"; bA = 0.5; mC = "#BF5AF2"; bM = 0.15 }

  # --- the name: the biggest size that fits whole (one line in 2×1, up to two in 1×2); else 26 with "…" ---
  nm = ENVIRON["HP_NAME"]
  gsub(/[\001-\037\177]/, "", nm)
  n = 0
  for (i = 1; i <= length(nm); i++) {
    c = substr(nm, i, 1); t = kind(c)
    if (t == 0) { if (n) ch[n] = ch[n] c; continue }
    n++; ch[n] = c; kd[n] = t
  }
  for (i = 1; i <= n; i++) w[i] = wide(ch[i], kd[i])
  cap[1] = 28; cap[2] = 28; best = -1
  for (m = 1; m <= maxl; m++)
    for (sz = cap[m]; sz >= 26; sz -= 2)
      if (lay(W / sz, m, 0)) { if (sz - 3 * (m - 1) > best) { best = sz - 3 * (m - 1); bm = m; bs = sz }; break }
  if (best >= 0) { sz = bs; lay(W / sz, bm, 0) } else { sz = 26; lay(W / sz, maxl, 1) }
  if (!live || n == 0) nl = 1
  lh = sz * 1.18
  for (i = 1; i <= 2; i++) {
    txt = (live && n > 0 && i <= nl) ? esc(NL[i]) : "—"
    y = ny + (i - 1 - (nl - 1) / 2) * lh        # an unused second line waits under the first, so it never crosses it
    body = body "<text id=`name" i "` x=`" NX "` y=`" f(y) "` font-size=`" sz "` font-weight=`600` text-anchor=`middle` dominant-baseline=`middle` fill=`#FFFFFF` fill-opacity=`" f((live && n > 0 && i <= nl) ? 0.9 : 0) "`>" txt "</text>"
  }

  # --- the rest glyph: big neon headphones; with data they sink to the bottom and dissolve,
  # with nothing connected they stay up, dim, over a dash ---
  if (live) { gx = sgx; gy = sgy; k = 0.3; go = 0; po = 0 }
  else if (none) { gx = ngx; gy = ngy; k = 0.9; go = 0.3; po = 0.3 }
  else { gx = rgx; gy = rgy; k = 1; go = 0.75; po = 1 }
  defs = defs "<linearGradient id=`phonesG` gradientUnits=`userSpaceOnUse` x1=`" f(gx - 60 * k) "` y1=`0` x2=`" f(gx + 60 * k) "` y2=`0`><stop offset=`0` stop-color=`#BF5AF2`/><stop offset=`1` stop-color=`#64D2FF`/></linearGradient>"
  body = body "<path id=`band` d=`M " f(gx - 46 * k) " " f(gy + 8 * k) " A " f(46 * k) " " f(46 * k) " 0 0 1 " f(gx + 46 * k) " " f(gy + 8 * k) "` fill=`none` stroke=`url(#phonesG)` stroke-opacity=`" f(go) "` stroke-width=`" f(5 * k) "` stroke-linecap=`round`/>"
  body = body "<rect id=`cupL` x=`" f(gx - 58 * k) "` y=`" f(gy + 2 * k) "` width=`" f(24 * k) "` height=`" f(42 * k) "` rx=`" f(10 * k) "` fill=`none` stroke=`url(#phonesG)` stroke-opacity=`" f(go) "` stroke-width=`" f(5 * k) "`/>"
  body = body "<rect id=`cupR` x=`" f(gx + 34 * k) "` y=`" f(gy + 2 * k) "` width=`" f(24 * k) "` height=`" f(42 * k) "` rx=`" f(10 * k) "` fill=`none` stroke=`url(#phonesG)` stroke-opacity=`" f(go) "` stroke-width=`" f(5 * k) "`/>"
  body = body "<rect id=`padL` x=`" f(gx - 49.5 * k) "` y=`" f(gy + 12 * k) "` width=`" f(7 * k) "` height=`" f(22 * k) "` rx=`" f(3.5 * k) "` fill=`#BF5AF2` fill-opacity=`" f(po) "`/>"
  body = body "<rect id=`padR` x=`" f(gx + 42.5 * k) "` y=`" f(gy + 12 * k) "` width=`" f(7 * k) "` height=`" f(22 * k) "` rx=`" f(3.5 * k) "` fill=`#64D2FF` fill-opacity=`" f(po) "`/>"
  body = body "<text id=`none` x=`" gx "` y=`" dy "` font-size=`30` font-weight=`600` text-anchor=`middle` dominant-baseline=`middle` fill=`#FFFFFF` fill-opacity=`" f(none ? 0.6 : 0) "`>—</text>"

  s = "<svg xmlns=`http://www.w3.org/2000/svg` viewBox=`" vb "`><defs>"
  s = s "<radialGradient id=`bloomG`><stop offset=`0` stop-color=`" bC "` stop-opacity=`" f(bA) "`/><stop offset=`0.55` stop-color=`" mC "` stop-opacity=`" f(bM) "`/>" \
        "<stop offset=`1` stop-color=`" mC "` stop-opacity=`0`/></radialGradient>"
  s = s defs "</defs>"
  s = s "<circle id=`bloom` cx=`" f(bX) "` cy=`" f(bY) "` r=`" f(bR) "` fill=`url(#bloomG)`/>"
  s = s body "</svg>"
  gsub(/`/, "\"", s)
  printf "%s", s
}
AWK

# hp_frame <p|l> <rest|none|live> <buds|single> <left %> <right %> <case %> <main %> [name…]
# p = the 2×1 face (400×200), l = its 1×2 landscape variant (200×400). A level of -1 is unknown and shows "—".
hp_frame() {
  emulate -L zsh
  export LC_ALL=C
  local layout=${1:-p} state=${2:-rest} mode=${3:-single} vl=${4:--1} vr=${5:--1} vc=${6:--1} vm=${7:--1}
  (( $# > 7 )) && shift 7 || set --
  [[ $layout == (p|l) ]] || layout=p
  [[ $state == (rest|none|live) ]] || state=rest
  [[ $mode == (buds|single) ]] || mode=single
  [[ $vl == <-> ]] || vl=-1
  [[ $vr == <-> ]] || vr=-1
  [[ $vc == <-> ]] || vc=-1
  [[ $vm == <-> ]] || vm=-1
  HP_NAME="$*" awk -v ly=$layout -v st=$state -v mode=$mode -v vl=$vl -v vr=$vr -v vc=$vc -v vm=$vm "$HEADPHONES_AWK"
}
# ---- end frame ----

# ---- reading ----
# system_profiler's Bluetooth JSON → "<name>\t<left>\t<right>\t<case>\t<main>" (-1 = not reported) of the connected
# headphones: minor type Headphones / Headset, anything with per-earbud levels, or an AirPods / Beats product id
# (Apple 0x20xx). The first one with a battery level wins. Nothing connected → no output.
read -r -d '' READER_AWK <<'AWK'
function unq(s) { gsub(/\\"/, "\"", s); gsub(/\\\//, "/", s); gsub(/\\\\/, "\\", s); return s }
function pct(s) { return (s ~ /^[0-9]+%?$/) ? ((s + 0 > 100) ? 100 : s + 0) : -1 }
function flush(   hp, score) {
  if (nm == "") return
  hp = (tolower(mt) ~ /headphone|headset/) || bl >= 0 || br >= 0 || bc >= 0 || (vid ~ /^0x004[cC]$/ && pid ~ /^0x20[0-9A-Fa-f][0-9A-Fa-f]$/)
  if (hp) {
    score = (bl >= 0 || br >= 0 || bc >= 0 || bm >= 0) ? 2 : 1
    if (score > best) { best = score; out = nm "\t" bl "\t" br "\t" bc "\t" bm }
  }
  nm = ""
}
BEGIN { best = 0; depth = 0; conn = 0 }
{
  line = $0
  t = line; gsub(/"([^"\\]|\\.)*"/, "", t)      # brackets outside strings
  o = t; c = t
  no = gsub(/[[{]/, "", o); nc = gsub(/[]}]/, "", c)
  if (!conn && line ~ /"device_connected"[ \t]*:/) { conn = 1; base = depth }
  else if (conn && depth == base + 2 && no > 0 && match(line, /^[ \t]*"([^"\\]|\\.)*"[ \t]*:/)) {
    flush()
    s = substr(line, RSTART, RLENGTH); sub(/^[ \t]*"/, "", s); sub(/"[ \t]*:$/, "", s)
    nm = unq(s); mt = ""; vid = ""; pid = ""; bl = -1; br = -1; bc = -1; bm = -1
  }
  else if (conn && nm != "" && depth == base + 3 && match(line, /"device_[A-Za-z]+"[ \t]*:[ \t]*"([^"\\]|\\.)*"/)) {
    kv = substr(line, RSTART, RLENGTH)
    k = kv; sub(/^"/, "", k); sub(/".*$/, "", k)
    v = kv; sub(/^"[^"]*"[ \t]*:[ \t]*"/, "", v); sub(/"$/, "", v)
    if (k == "device_minorType") mt = v
    else if (k == "device_vendorID") vid = v
    else if (k == "device_productID") pid = v
    else if (k == "device_batteryLevelLeft") bl = pct(v)
    else if (k == "device_batteryLevelRight") br = pct(v)
    else if (k == "device_batteryLevelCase") bc = pct(v)
    else if (k == "device_batteryLevelMain") bm = pct(v)
  }
  depth += no - nc
  if (conn && depth <= base) { flush(); conn = 0 }
}
END { flush(); if (out != "") print out }
AWK

cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"
zf_mkdir -p "$dir" 2>/dev/null || print -u2 -- "headphones: cannot create $dir"

# Sets state, mode, left, right, case_, main and name from one system_profiler run (1–2 s; once a minute at most).
# It runs in the background so the TERM trap can stop it.
sample() {
  local raw="$dir/bluetooth.json" out
  system_profiler -timeout 20 SPBluetoothDataType -json > "$raw" 2>/dev/null &
  reader=$!
  wait $reader
  reader=0
  [[ -s $raw ]] || print -u2 -- "headphones: system_profiler gave nothing (Bluetooth off?)"
  out=$(awk "$READER_AWK" "$raw" 2>/dev/null)
  state=none mode=buds left=-1 right=-1 case_=-1 main=-1 name=""
  [[ -n $out ]] || return 0
  IFS=$'\t' read -r name left right case_ main <<< "$out"
  state=live mode=single
  (( left >= 0 || right >= 0 || case_ >= 0 )) && mode=buds
  return 0
}

# post <2×1 frame> <1×2 frame>: sets code, and seen=0 when the phone says the button is off screen.
# The token goes in through a descriptor, not the command line, where any user of the Mac could read it.
post() {
  local p=$1 l=$2 answer
  p=${p//\\/\\\\}; p=${p//\"/\\\"}; p=${p//$'\n'/}
  l=${l//\\/\\\\}; l=${l//\"/\\\"}; l=${l//$'\n'/}
  answer=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" -H @/dev/fd/3 \
    -H "Content-Type: application/json" --data-binary @- \
    3<<< "Authorization: Bearer $DESMAPTIC_TOKEN" \
    <<< "{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$p\",\"landscapeSource\":\"$l\",\"duration\":1.2}}")
  code=${answer##*$'\n'}
  [[ ${answer//[[:space:]]/} == *'"visible":false'* ]] && seen=0
  [[ $code == 200 ]] || print -u2 -- "headphones: update-button answered ${code:-nothing}: ${${answer%$'\n'*}[1,300]}"
  return 0
}

# 0 when the phone shows this button, or when nobody can tell (an older app, the agent not answering).
on_screen() {
  local answer
  answer=$(curl -q -s -m 5 "$api/view" -H @/dev/fd/3 3<<< "Authorization: Bearer $DESMAPTIC_TOKEN") || return 0
  answer=${(L)answer//[[:space:]]/}
  [[ $answer == *'"visiblecellids"'* ]] || return 0
  [[ $answer == *${(L)cell}* ]]
}

last="" seen=1 next=0
while true; do
  if (( ! seen )); then                          # off screen: no sampling, one look at the phone every 3 s
    until on_screen; do zselect -t 300; done
    seen=1
  fi
  if (( EPOCHSECONDS >= next )); then
    if ! on_screen; then seen=0; continue; fi
    sample
    next=$(( EPOCHSECONDS + 60 ))
  fi
  key="$state $mode $left $right $case_ $main $name"
  if [[ $key != $last ]]; then
    code=""
    post "$(hp_frame p $state $mode $left $right $case_ $main $name)" "$(hp_frame l $state $mode $left $right $case_ $main $name)"
    if [[ $code != 200 ]]; then
      zselect -t 1000                            # the agent did not take it: again in 10 s
      continue
    fi
    last=$key
    (( seen )) || continue
  fi
  wait_s=$(( next - EPOCHSECONDS ))
  (( wait_s > 0 )) && zselect -t $(( wait_s * 100 ))
done
