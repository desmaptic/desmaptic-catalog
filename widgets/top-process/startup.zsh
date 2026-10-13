#!/bin/zsh
# Top Process: the process using the most CPU right now, its name and CPU % (one core = 100 %) on a neon gauge
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT

# One template for every frame. $1 layout: p = 2×1 (400×200), l = the 1×2 landscape variant (200×400);
# $2 state: rest | live; $3 CPU % of the process; $4 1 = name shown, 0 = name faded out; the rest is the name.
top_frame() {
  emulate -L zsh
  export LC_ALL=C
  local layout=${1:-p} state=${2:-rest} cpu=${3:-0} shown=${4:-1}
  (( $# > 4 )) && shift 4 || set --
  local name="$*"
  [[ $layout == (p|l) ]] || layout=p
  [[ $state == (rest|live) ]] || state=rest
  [[ $cpu == <->(|.<->) ]] || { cpu=0; state=rest }
  [[ $shown == (0|1) ]] || shown=1
  [[ -n $name ]] || name="—"

  # Every number, colour and name line comes from awk as "key value" lines
  # (zsh float arithmetic would print 0.17999999999999999).
  local -A v
  local line
  while IFS= read -r line; do v[${line%% *}]=${line#* }; done < <(TP_NAME=$name awk -v u=$cpu -v st=$state -v ly=$layout -v shown=$shown '
    function hex(h,   i, n) { n = 0; h = toupper(h); for (i = 1; i <= length(h); i++) n = n * 16 + index("0123456789ABCDEF", substr(h, i, 1)) - 1; return n }
    function mix(a, b, t,   i, o, x, y) {
      o = "#"
      for (i = 2; i <= 6; i += 2) { x = hex(substr(a, i, 2)); y = hex(substr(b, i, 2)); o = o sprintf("%02X", int(x + (y - x) * t + 0.5)) }
      return o
    }
    function spectrum(t) {                     # the arc gradient, calm → attention: #64D2FF → #5E5CE6 (.3) → #BF5AF2 (.65) → #FF375F
      if (t <= 0)   return "#64D2FF"
      if (t < 0.3)  return mix("#64D2FF", "#5E5CE6", t / 0.3)
      if (t < 0.65) return mix("#5E5CE6", "#BF5AF2", (t - 0.3) / 0.35)
      if (t < 1)    return mix("#BF5AF2", "#FF375F", (t - 0.65) / 0.35)
      return "#FF375F"
    }
    function kv(k, x) { printf "%s %s\n", k, x }
    function num(k, x) { printf "%s %.2f\n", k, x }

    # --- the name: UTF-8 characters with their widths in ems of the system font (semibold, measured at size 26) ---
    function kind(c) { return (c < "\200") ? 1 : (c < "\300") ? 0 : (c < "\340") ? 2 : (c < "\360") ? 3 : 4 }
    function ascii(c,   i) {
      if (!nasc) {
        ASC = " !\"#$%&\047()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
        nasc = split("0.215 0.310 0.454 0.637 0.642 0.881 0.702 0.278 0.373 0.373 0.444 0.642 0.248 0.449 0.248 0.305 " \
          "0.642 0.642 0.642 0.642 0.642 0.642 0.642 0.642 0.642 0.642 0.248 0.248 0.642 0.642 0.642 0.528 0.895 " \
          "0.683 0.640 0.714 0.705 0.578 0.553 0.731 0.731 0.263 0.547 0.647 0.549 0.862 0.722 0.756 0.616 0.756 " \
          "0.638 0.630 0.607 0.716 0.673 0.962 0.679 0.658 0.638 0.373 0.305 0.373 0.642 0.571 0.508 0.543 0.594 " \
          "0.541 0.594 0.552 0.350 0.590 0.580 0.240 0.240 0.532 0.241 0.856 0.571 0.570 0.591 0.590 0.358 0.510 " \
          "0.349 0.571 0.525 0.776 0.519 0.533 0.506 0.373 0.245 0.373 0.642", AW, " ")
      }
      i = index(ASC, c)
      return i ? AW[i] : 0.64
    }
    # Where a line may end after character j — only between words, never inside one:
    # 2 at a space, after a dot, before "("; 1 (only if the line has no 2) at camelCase, "-", "_", "/"; 0 inside a word.
    function brk(j) {
      if (j >= n) return 2
      if (ch[j] == " " || ch[j] == "." || ch[j + 1] == " " || ch[j + 1] == "(") return 2
      if ((ch[j] ~ /[a-z]/ && ch[j + 1] ~ /[A-Z]/) || index("-_/", ch[j])) return 1
      return 0
    }
    function put(s, e, extra,   j, t, x) {     # line nl = characters s…e, trailing spaces dropped
      while (e >= s && ch[e] == " ") e--
      t = ""; x = 0
      for (j = s; j <= e; j++) { t = t ch[j]; x += w[j] }
      L[nl] = t extra; LW[nl] = x
    }
    # Lays the name out in at most maxl lines of b ems, breaking only where brk() allows; 0 when it does not fit.
    # With clip it never fails and never breaks inside a word either: the first line it cannot finish — a word wider
    # than the line, or the last line with name left over — is cut to what fits and ends the name with "…".
    function lay(b, maxl, clip,   s, e, x, j, bp) {
      nl = 0; s = 1
      while (s <= n) {
        while (s <= n && ch[s] == " ") s++
        if (s > n) break
        nl++; x = 0; e = s - 1
        while (e < n && x + w[e + 1] <= b) { e++; x += w[e] }
        if (e == n) { put(s, n, ""); return 1 }
        bp = 0
        if (nl < maxl) {
          for (j = e; j >= s && !bp; j--) if (brk(j) == 2) bp = j
          for (j = e; j >= s && !bp; j--) if (brk(j) == 1) bp = j
        }
        if (!bp) {
          if (!clip) return 0
          x = 0; e = s - 1
          while (e < n && x + w[e + 1] <= b - 0.68) { e++; x += w[e] }   # 0.68 em: "…"
          while (e >= s && index(" .-_/(", ch[e])) e--
          put(s, e, "…"); LW[nl] += 0.68
          return 1
        }
        put(s, bp, "")
        s = bp + 1
      }
      return 1
    }

    BEGIN {
      live = (st == "live") ? 1 : 0
      p = u + 0
      f = p / 100; if (f > 1) f = 1; if (f < 0) f = 0
      lvl = "rest"
      if (live) { lvl = "ok"; if (p >= 50) lvl = "warn"; if (p >= 90) lvl = "critical" }

      # value: 3.4 · 42 · 197 · 1250 (a process on many cores goes past 100 and the gauge stays full)
      if (!live) val = "—"; else if (p < 9.95) val = sprintf("%.1f", p); else val = sprintf("%d", p + 0.5)
      kv("val", val); kv("vsize", length(val) >= 4 ? 56 : 60)

      # --- gauge: the disk-free geometry, filled clockwise with CPU load ---
      L0 = 335.10                              # arc length: r 80 · 240° = 80 · 4π/3
      if (!live) f = 0.5                       # rest: arc end, bead and glow parked at 12 o’clock
      d = L0 * f; if (d > L0 - 0.3) d = L0 - 0.3
      num("off", L0 * (1 - f)); num("pos", -d)
      ang = -120 + 240 * f; num("ang", ang)
      x = 100 + 80 * sin(ang * 3.14159265 / 180)
      gc = spectrum((x - 24) / 152)            # glow colour = the arc colour under the bead

      # state:       bloom centre / mid colour and opacity, radius   glow r, core opacity   halo width, opacity   unit colour, opacity   chip-glyph gradient
      if (lvl == "rest")     { bC = "#BF5AF2"; bA = 0.12; mC = "#5E5CE6"; bM = 0.04; bR = 82; gR = 28; gA = 0.55; hW = 18; hO = 0.45; uC = "#FFFFFF"; uO = 0.6;  d1 = "#BF5AF2"; d2 = "#64D2FF" }
      if (lvl == "ok")       { bC = "#BF5AF2"; bA = 0.20; mC = "#5E5CE6"; bM = 0.07; bR = 86; gR = 28; gA = 0.55; hW = 18; hO = 0.45; uC = "#FFFFFF"; uO = 0.6;  d1 = "#BF5AF2"; d2 = "#64D2FF" }
      if (lvl == "warn")     { bC = "#E0479E"; bA = 0.32; mC = "#BF5AF2"; bM = 0.10; bR = 90; gR = 28; gA = 0.70; hW = 20; hO = 0.50; uC = "#FFFFFF"; uO = 0.6;  d1 = "#FF6FA0"; d2 = "#BF5AF2" }
      if (lvl == "critical") { bC = "#FF375F"; bA = 0.57; mC = "#BF5AF2"; bM = 0.16; bR = 98; gR = 32; gA = 0.95; hW = 22; hO = 0.60; uC = "#FF7A96"; uO = 0.95; d1 = "#FF375F"; d2 = "#FF8FA8"; gc = "#FF375F" }
      # track: a faint spectrum on the rest face, white 0.18 while live, hot pink when critical
      if (lvl == "rest")     { split("#64D2FF #5E5CE6 #BF5AF2 #FF375F", tc, " "); split("0.30 0.30 0.30 0.30", to, " ") }
      if (lvl == "ok" || lvl == "warn") { split("#FFFFFF #FFFFFF #FFFFFF #FFFFFF", tc, " "); split("0.18 0.18 0.18 0.18", to, " ") }
      if (lvl == "critical") { split("#FF375F #FF375F #FF375F #FF375F", tc, " "); split("0.20 0.20 0.24 0.30", to, " ") }
      for (i = 1; i <= 4; i++) { kv("tc" i, tc[i]); kv("to" i, to[i]) }

      kv("gc", gc); kv("bC", bC); num("bA", bA); kv("mC", mC); num("bM", bM); kv("bR", bR)
      kv("gR", gR); num("gA", live * gA); num("gM", live * 0.4 * gA); kv("hW", hW); num("hO", live * hO)
      num("tHO", lvl == "critical" ? 0 : 0.9); kv("uC", uC); num("uO", live * uO); kv("d1", d1); kv("d2", d2)
      num("live", live); num("litGlowO", live * 0.2); num("coreO", live * 0.45)

      # the big chip glyph is the rest face; when data arrives it sinks to the bottom and fades out
      if (live) { cx = 100; cy = 174; k = 0.3; co = 0 } else { cx = 100; cy = 100; k = 1; co = 0.8 }
      num("chX", cx - 27 * k); num("chY", cy - 27 * k); num("chS", 54 * k); num("chR", 11 * k); num("chW", 5 * k)
      num("diX", cx - 10 * k); num("diY", cy - 10 * k); num("diS", 20 * k); num("diR", 4 * k)
      pins = ""
      for (i = -1; i <= 1; i++) {
        o = cx + 14 * i * k; q = cy + 14 * i * k
        pins = pins sprintf("M %.2f %.2f L %.2f %.2f M %.2f %.2f L %.2f %.2f M %.2f %.2f L %.2f %.2f M %.2f %.2f L %.2f %.2f ", \
          o, cy - 37 * k, o, cy - 30 * k, o, cy + 30 * k, o, cy + 37 * k, cx - 37 * k, q, cx - 30 * k, q, cx + 30 * k, q, cx + 37 * k, q)
      }
      sub(/ $/, "", pins); kv("pins", pins); num("chO", co); num("diO", co > 0 ? 1 : 0)

      # --- the name: the biggest size for each line count (one line up to 36, two up to 32, three up to 28, four at 26),
      # an extra line costs 3 units of size; lines break only between words, so a long word shrinks the text instead;
      # a word wider than the line even at 26, or a name longer than every line → 26, cut at the end with "…" ---
      nm = ENVIRON["TP_NAME"]
      gsub(/[\001-\037\177]/, "", nm)
      sub(/^com\.apple\./, "", nm)             # Apple’s XPC services: the rest of the name is the telling part
      n = 0
      for (i = 1; i <= length(nm); i++) {
        c = substr(nm, i, 1); t = kind(c)
        if (t == 0) { if (n) ch[n] = ch[n] c; continue }
        n++; ch[n] = c; w[n] = (t == 1) ? ascii(c) : (t == 2) ? 0.58 : (t == 3) ? 1 : 1.15
      }
      if (ly == "p") { W = 184; maxl = 3; tx = 208; yc = 100 } else { W = 184; maxl = 4; tx = 100; yc = 284 }
      cap[1] = 36; cap[2] = 32; cap[3] = 28; cap[4] = 26; best = -1
      for (m = 1; m <= maxl; m++)
        for (sz = cap[m]; sz >= 26; sz -= 2)
          if (lay(W / sz, m, 0)) { if (sz - 3 * (m - 1) > best) { best = sz - 3 * (m - 1); bm = m; bs = sz }; break }
      if (best >= 0) { sz = bs; lay(W / sz, bm, 0) } else { sz = 26; lay(W / sz, maxl, 1) }
      if (!live) { sz = 30; nl = 2 }
      lh = sz * 1.18; ug = sz * 0.62 + 6
      y0 = yc - (nl - 1) * lh / 2 - ug / 2
      for (i = 1; i <= maxl; i++) {
        kv("t" i, (live && i <= nl) ? L[i] : "—")
        num("y" i, y0 + ((i <= nl) ? i - 1 : nl - 1) * lh)
        num("o" i, (live && shown && i <= nl) ? 1 : 0)
      }
      kv("nsz", sz); kv("tx", tx)

      # --- rest: a ranking glyph (three bars, the top one lit); live: the top bar becomes the accent under the name ---
      uy = y0 + (nl - 1) * lh + ug
      if (ly == "p") { rx = 216; ry = 100; rs = 34; r1 = 132; r2 = 96; r3 = 60 } else { rx = 46; ry = 280; rs = 32; r1 = 108; r2 = 78; r3 = 48 }
      if (live) {
        ul = 40
        if (ly == "p") { a1 = tx + 2; a2 = a1 + ul } else { a1 = tx - ul / 2; a2 = tx + ul / 2 }
        num("b1x1", a1); num("b1x2", a2); num("b1y", uy); num("b1w", 5)
        num("b2x", a1); num("b2y", uy + 16); num("b3y", uy + 30); num("b2x2", a1); num("b3x2", a1); num("bO", 0)
        kv("k1", gc); num("k1o", 1); kv("k2", gc); num("k2o", 0.35)
      } else {
        num("b1x1", rx); num("b1x2", rx + r1); num("b1y", ry - rs); num("b1w", 10)
        num("b2x", rx); num("b2y", ry); num("b3y", ry + rs); num("b2x2", rx + r2); num("b3x2", rx + r3); num("bO", 0.22)
        kv("k1", "#BF5AF2"); num("k1o", 0.9); kv("k2", "#64D2FF"); num("k2o", 0.9)
      }
    }')

  local t
  for t in t1 t2 t3 t4 val; do
    [[ -n ${v[$t]} ]] || continue
    v[$t]=${v[$t]//&/&amp;}; v[$t]=${v[$t]//</&lt;}; v[$t]=${v[$t]//>/&gt;}
  done
  local vb anchor lines names="" i
  if [[ $layout == p ]]; then vb="0 0 400 200"; anchor=start; lines=3; else vb="0 0 200 400"; anchor=middle; lines=4; fi
  for (( i = 1; i <= lines; i++ )); do
    [[ -n ${v[t$i]} ]] || v[t$i]="—"         # never an empty <text>: the structure must not change
    names+="<text id=\"name$i\" x=\"$v[tx]\" y=\"${v[y$i]}\" font-size=\"$v[nsz]\" font-weight=\"600\" text-anchor=\"$anchor\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"${v[o$i]}\">${v[t$i]}</text>"
  done
  local arc='d="M 30.72 140 A 80 80 0 1 1 169.28 140" fill="none"'

  printf '%s\n' "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"$vb\">\
<defs>\
<linearGradient id=\"spec\" gradientUnits=\"userSpaceOnUse\" x1=\"24\" y1=\"0\" x2=\"176\" y2=\"0\">\
<stop offset=\"0\" stop-color=\"#64D2FF\"/><stop offset=\"0.3\" stop-color=\"#5E5CE6\"/><stop offset=\"0.65\" stop-color=\"#BF5AF2\"/><stop offset=\"1\" stop-color=\"#FF375F\"/>\
</linearGradient>\
<linearGradient id=\"trackG\" gradientUnits=\"userSpaceOnUse\" x1=\"24\" y1=\"0\" x2=\"176\" y2=\"0\">\
<stop offset=\"0\" stop-color=\"$v[tc1]\" stop-opacity=\"$v[to1]\"/><stop offset=\"0.3\" stop-color=\"$v[tc2]\" stop-opacity=\"$v[to2]\"/><stop offset=\"0.65\" stop-color=\"$v[tc3]\" stop-opacity=\"$v[to3]\"/><stop offset=\"1\" stop-color=\"$v[tc4]\" stop-opacity=\"$v[to4]\"/>\
</linearGradient>\
<linearGradient id=\"chipG\" gradientUnits=\"userSpaceOnUse\" x1=\"60\" y1=\"0\" x2=\"140\" y2=\"0\"><stop offset=\"0\" stop-color=\"$v[d1]\"/><stop offset=\"1\" stop-color=\"$v[d2]\"/></linearGradient>\
<linearGradient id=\"rankG\" gradientUnits=\"userSpaceOnUse\" x1=\"$v[b1x1]\" y1=\"0\" x2=\"$v[b1x2]\" y2=\"0\"><stop offset=\"0\" stop-color=\"$v[k1]\" stop-opacity=\"$v[k1o]\"/><stop offset=\"1\" stop-color=\"$v[k2]\" stop-opacity=\"$v[k2o]\"/></linearGradient>\
<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"$v[bC]\" stop-opacity=\"$v[bA]\"/><stop offset=\"0.55\" stop-color=\"$v[mC]\" stop-opacity=\"$v[bM]\"/><stop offset=\"1\" stop-color=\"$v[mC]\" stop-opacity=\"0\"/></radialGradient>\
<radialGradient id=\"glowG\"><stop offset=\"0\" stop-color=\"$v[gc]\" stop-opacity=\"$v[gA]\"/><stop offset=\"0.4\" stop-color=\"$v[gc]\" stop-opacity=\"$v[gM]\"/><stop offset=\"1\" stop-color=\"$v[gc]\" stop-opacity=\"0\"/></radialGradient>\
</defs>\
<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"$v[bR]\" fill=\"url(#bloomG)\"/>\
<path id=\"track\" $arc stroke=\"url(#trackG)\" stroke-width=\"6\" stroke-linecap=\"round\"/>\
<path id=\"ticks\" d=\"M 100 38 L 100 33\" fill=\"none\" stroke=\"#FFFFFF\" stroke-opacity=\"0.3\" stroke-width=\"2.5\" stroke-linecap=\"round\"/>\
<line id=\"tickLow\" x1=\"46.31\" y1=\"131\" x2=\"41.98\" y2=\"133.5\" stroke=\"#64D2FF\" stroke-opacity=\"0.9\" stroke-width=\"3\" stroke-linecap=\"round\"/>\
<line id=\"tickHigh\" x1=\"153.69\" y1=\"131\" x2=\"158.02\" y2=\"133.5\" stroke=\"#FF375F\" stroke-opacity=\"$v[tHO]\" stroke-width=\"3\" stroke-linecap=\"round\"/>\
<path id=\"litGlow\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[litGlowO]\" stroke-width=\"22\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 335.1\" stroke-dashoffset=\"$v[off]\"/>\
<path id=\"lit\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[live]\" stroke-width=\"9\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 335.1\" stroke-dashoffset=\"$v[off]\"/>\
<path id=\"core\" $arc stroke=\"#FFFFFF\" stroke-opacity=\"$v[coreO]\" stroke-width=\"2.5\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 335.1\" stroke-dashoffset=\"$v[off]\"/>\
<circle id=\"glow\" cx=\"100\" cy=\"26\" r=\"$v[gR]\" fill=\"url(#glowG)\" transform=\"rotate($v[ang] 100 100)\"/>\
<path id=\"halo\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[hO]\" stroke-width=\"$v[hW]\" stroke-linecap=\"round\" stroke-dasharray=\"0.1 400\" stroke-dashoffset=\"$v[pos]\"/>\
<path id=\"bead\" $arc stroke=\"#FFFFFF\" stroke-opacity=\"$v[live]\" stroke-width=\"12\" stroke-linecap=\"round\" stroke-dasharray=\"0.1 400\" stroke-dashoffset=\"$v[pos]\"/>\
<text id=\"value\" x=\"100\" y=\"97\" font-size=\"$v[vsize]\" font-weight=\"600\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"$v[live]\">$v[val]</text>\
<text id=\"unit\" x=\"100\" y=\"138\" font-size=\"26\" font-weight=\"600\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"$v[uC]\" fill-opacity=\"$v[uO]\">%</text>\
<rect id=\"chip\" x=\"$v[chX]\" y=\"$v[chY]\" width=\"$v[chS]\" height=\"$v[chS]\" rx=\"$v[chR]\" fill=\"none\" stroke=\"url(#chipG)\" stroke-opacity=\"$v[chO]\" stroke-width=\"$v[chW]\"/>\
<path id=\"pins\" d=\"$v[pins]\" fill=\"none\" stroke=\"url(#chipG)\" stroke-opacity=\"$v[chO]\" stroke-width=\"$v[chW]\" stroke-linecap=\"round\"/>\
<rect id=\"die\" x=\"$v[diX]\" y=\"$v[diY]\" width=\"$v[diS]\" height=\"$v[diS]\" rx=\"$v[diR]\" fill=\"#64D2FF\" fill-opacity=\"$v[diO]\"/>\
<line id=\"rank2\" x1=\"$v[b2x]\" y1=\"$v[b2y]\" x2=\"$v[b2x2]\" y2=\"$v[b2y]\" stroke=\"#FFFFFF\" stroke-opacity=\"$v[bO]\" stroke-width=\"10\" stroke-linecap=\"round\"/>\
<line id=\"rank3\" x1=\"$v[b2x]\" y1=\"$v[b3y]\" x2=\"$v[b3x2]\" y2=\"$v[b3y]\" stroke=\"#FFFFFF\" stroke-opacity=\"$v[bO]\" stroke-width=\"10\" stroke-linecap=\"round\"/>\
<line id=\"rank1\" x1=\"$v[b1x1]\" y1=\"$v[b1y]\" x2=\"$v[b1x2]\" y2=\"$v[b1y]\" stroke=\"url(#rankG)\" stroke-width=\"$v[b1w]\" stroke-linecap=\"round\"/>\
$names\
</svg>"
}

api="http://127.0.0.1:9848/api"
cell="{{CELL_ID}}"
hidden=0

# Posts the portrait and landscape frames; leaves the HTTP status in $code and sets hidden=1 when the button is off screen.
post() {
  local p=$1 l=$2 out body
  p=${p//\\/\\\\}; p=${p//\"/\\\"}; p=${p//$'\n'/}
  l=${l//\\/\\\\}; l=${l//\"/\\\"}; l=${l//$'\n'/}
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' -H "Content-Type: application/json" \
    -d "{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$p\",\"landscapeSource\":\"$l\",\"duration\":$3}}")
  code=${out##*$'\n'}; body=${out%$'\n'*}
  if [[ $code == 200 ]]; then
    [[ ${body//[[:space:]]/} == *'"visible":false'* ]] && hidden=1
  else
    print -u2 -- "update-button $code: ${body[1,300]}"
  fi
}

# Off screen: no sampling, no drawing; one look every 3 s until the phone shows the button again.
wait_until_visible() {
  local out code body
  while true; do
    sleep 3
    out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/view" --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}')
    code=${out##*$'\n'}; body=${(L)${out%$'\n'*}//[[:space:]]/}
    [[ $code == 200 ]] || return               # cannot tell: draw
    [[ $body == *'"view":null'* || $body == *${(L)cell}* ]] && return
  done
}

# "<pid>\t<cpu>\t<name>" of the busiest process. The one on the face stays until another one is clearly busier,
# so two processes at similar load do not swap names every few seconds. ps itself (the sampler) is skipped.
busiest() {
  LC_ALL=en_US.UTF-8 ps -Aceo pid=,pcpu=,comm= -r 2>/dev/null | awk -v cur=$1 '
    {
      line = $0
      if (!sub(/^ *[0-9]+ +[0-9.]+ /, "", line) || line == "ps") next
      if (top == "") { top = $1 "\t" $2 "\t" line; topc = $2 + 0 }
      if ($1 == cur) { mine = $1 "\t" $2 "\t" line; minec = $2 + 0 }
    }
    END {
      if (top == "") exit
      margin = topc * 0.15; if (margin < 5) margin = 5
      print (mine != "" && minec >= topc - margin) ? mine : top
    }'
}

pid="" shown="" key="" last="" code=""
while true; do
  pick=$(busiest "$pid")
  if [[ -n $pick ]]; then
    IFS=$'\t' read -r pid cpu name <<< "$pick"
    state=live
  else
    pid="" cpu=0 name="" state=rest
    print -u2 -- "ps gave no processes"
  fi
  value=$(awk -v p="$cpu" 'BEGIN { if (p < 9.95) printf "%.1f", p; else printf "%d", p + 0.5 }')
  if [[ "$state $value $name" != $key ]]; then
    # a new name: fade the old one out, then put the new one in its own layout while still invisible —
    # text changes at once but its lines glide, so fading in from the old layout overlaps them mid-way
    if [[ -n $shown && $name != $shown ]]; then
      post "$(top_frame p live $cpu 0 $shown)" "$(top_frame l live $cpu 0 $shown)" 0.3
      sleep 0.35
      post "$(top_frame p live $cpu 0 $name)" "$(top_frame l live $cpu 0 $name)" 0.01
      sleep 0.05
    fi
    frame=$(top_frame p $state $cpu 1 $name)
    if [[ $frame != $last ]]; then
      post "$frame" "$(top_frame l $state $cpu 1 $name)" 1
      if [[ $code == 200 ]]; then
        last=$frame key="$state $value $name" shown=$name
      else
        sleep 10
        continue
      fi
    fi
  fi
  if (( hidden )); then
    hidden=0
    wait_until_visible
    continue
  fi
  sleep 3
done
