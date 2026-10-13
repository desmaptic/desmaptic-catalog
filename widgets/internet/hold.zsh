#!/bin/zsh
# Internet hold: copies the Mac's public IP address and shows it on the face for 8 seconds, the local one under it when it fits
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap '[[ -n $ip_file ]] && rm -f -- "$ip_file.$$"; exit 0' TERM INT HUP
zmodload zsh/datetime zsh/zselect || { print -u2 -- "internet: zsh modules datetime/zselect are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_mv || { print -u2 -- "internet: zsh module files is missing"; exit 1 }

# ---- net_frame: identical in startup.zsh and hold.zsh ----
# One template for every face: the rest glyph, a latency, offline, the IP address. Only numbers, colours and text change.
# net_frame <rest|live|offline|ip|bare> <phase 0|1> <latency, ms> <history: 26 latencies in ms, oldest first, -1 = offline>
#           [public IP] [local IP]
# The line scrolls one step per sample: phase 0 draws the history as the previous slide ended (the newest
# sample waits in a slot off the right edge), phase 1 slides it one step left. The rest face ignores both.
# The ip face hides the gauge (its latency and history still describe what lies under it, so the switch is a
# fade in place) and shows the addresses; every other face carries the last addresses invisible, in the same
# layout, so the address fades out as itself. bare is the ip face without the addresses: the step between the
# gauge and the address, both ways, so the two never cross-fade over each other.
NET_AWK='
function hex(x,   i, n) { n = 0; x = toupper(x); for (i = 1; i <= length(x); i++) n = n * 16 + index("0123456789ABCDEF", substr(x, i, 1)) - 1; return n }
function mix(a, b, t,   i, o, x, y) {
  o = "#"
  for (i = 2; i <= 6; i += 2) { x = hex(substr(a, i, 2)); y = hex(substr(b, i, 2)); o = o sprintf("%02X", int(x + (y - x) * t + 0.5)) }
  return o
}
function spectrum(t) {                         # fast → slow: #64D2FF → #5E5CE6 (.3) → #BF5AF2 (.65) → #FF375F
  if (t <= 0)   return "#64D2FF"
  if (t < 0.3)  return mix("#64D2FF", "#5E5CE6", t / 0.3)
  if (t < 0.65) return mix("#5E5CE6", "#BF5AF2", (t - 0.3) / 0.35)
  if (t < 1)    return mix("#BF5AF2", "#FF375F", (t - 0.65) / 0.35)
  return "#FF375F"
}
function lerp(a, b, t) { return a + (b - a) * t }
function p3(a, b, c) { return (H < 0.5) ? lerp(a, b, H * 2) : lerp(b, c, H * 2 - 1) }   # calm → warm → hot
function c3(a, b, c) { return (H < 0.5) ? mix(a, b, H * 2) : mix(b, c, H * 2 - 1) }
function clamp(x) { return x < 0 ? 0 : (x > 1 ? 1 : x) }
function f(x) { return sprintf("%.2f", x) }
# where a latency sits on the gauge and on the line: a log scale, 1 ms empty, 10 ms a third, 100 ms two thirds,
# 1 s full; offline is full
function share(m) { if (m < 0) return 1; if (m <= 1) return 0; return clamp(log(m) / log(1000)) }
function lineY(m) { return 182 - 30 * share(m) }
# the colour the gauge has at a share: the arc gradient runs left to right, so it is picked by the x under the bead
function tint(q) { return spectrum((100 + 80 * sin((-120 + 240 * q) * 3.14159265 / 180) - 24) / 152) }
# the IP face. em: the width of a string in em of the system font (semibold, fixed-width digits; measured
# at 26–100 pt, the widest of those, plus 3 % of air)
function em(s,   i, c, w) {
  w = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c ~ /[0-9]/) w += 0.645
    else if (c == "." || c == ":") w += 0.248
    else if (c == "f") w += 0.35
    else if (c == "b" || c == "d") w += 0.594
    else w += 0.552
  }
  return w * 1.03
}
# P[1..NP]: the address cut after every dot or colon ("::" stays whole), so no line starts with one
function cut(s,   i, c, cur) {
  NP = 0; cur = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1); cur = cur c
    if ((c == "." || c == ":") && i < length(s) && substr(s, i + 1, 1) != ":") { P[++NP] = cur; cur = "" }
  }
  if (cur != "") P[++NP] = cur
}
# the narrowest "widest line" over every way to put the pieces on n lines; BB[1..n-1] = the last piece of each line
function split_best(n,   k, br, i, j, w, mx, last, best) {
  for (k = 1; k < n; k++) br[k] = k
  best = -1
  while (1) {
    mx = 0; j = 1
    for (k = 1; k <= n; k++) {
      last = (k < n) ? br[k] : NP; w = 0
      for (i = j; i <= last; i++) w += em(P[i])
      if (w > mx) mx = w
      j = last + 1
    }
    if (best < 0 || mx < best) { best = mx; for (k = 1; k < n; k++) BB[k] = br[k] }
    k = n - 1
    while (k >= 1 && br[k] == NP - n + k) k--
    if (k < 1) break
    br[k]++
    for (i = k + 1; i < n; i++) br[i] = br[i - 1] + 1
  }
  return best
}
# IS, IN, IL[]: the largest size (at most 56) at which the address, on 1 to most lines 1.12 apart, is at most
# 184 wide and h high; the fewest lines on a tie. Every address reaches 31: two IPv6 groups a line on four lines.
function fit(h, most,   n, s, v, k) {
  IS = 0; IN = 1
  for (n = 1; n <= most && n <= NP; n++) {
    s = 184 / split_best(n)
    v = h / ((n - 1) * 1.12 + 0.705)
    if (v < s) s = v
    if (s > 56) s = 56
    s = int(s)
    if (s > IS) { IS = s; IN = n; for (k = 1; k < n; k++) IL[k] = BB[k] }
  }
  if (IS < 26) IS = 26
}
BEGIN {
  bare = (st == "bare"); ipf = (st == "ip" || bare)   # the IP face: the gauge underneath as live (or offline), hidden
  if (ipf) st = (ms < 0) ? "offline" : "live"
  live = (st == "live"); down = (st == "offline"); shown = live || down
  H = 0                                        # heat: 0 calm, 0.5 warm (200 ms and slower), 1 offline
  if (live && ms > 100) H = 0.5 * clamp((ms - 100) / 100)
  if (down) H = 1

  # gauge: 240° arc, r 80; the lit dash grows from the left end
  L = 335.10                                   # arc length: 80 · 4π/3
  fr = 0.5                                     # rest: arc end, bead and glow parked at 12 o’clock
  if (live) fr = share(ms)
  if (down) fr = 1                             # offline: the arc runs out to the slow end while it fades
  d = L * fr; if (d > L - 0.3) d = L - 0.3     # keep the bead’s dash on the path
  off = L * (1 - fr)
  ang = -120 + 240 * fr                        # glow: degrees clockwise from 12 o’clock
  # the glow rides the bead as two halves (left of 12 o’clock, right of it): a rotation glides the shortest
  # way, so one circle would cut through the gap at the bottom on a jump from 5 ms to offline
  angA = ang < 0 ? ang : 0; angB = ang > 0 ? ang : 0
  wA = clamp(0.5 - ang / 4); wB = 1 - wA
  gc = tint(fr)                                # glow colour = the arc colour under the bead

  if (live) {
    bC = c3("#BF5AF2", "#E0479E", "#FF375F"); bA = p3(0.20, 0.32, 0.57); mC = c3("#5E5CE6", "#BF5AF2", "#BF5AF2"); bM = p3(0.07, 0.10, 0.16); bR = p3(86, 90, 98)
    gR = p3(28, 28, 32); gA = p3(0.55, 0.70, 0.95); hW = p3(18, 20, 22); hO = p3(0.45, 0.50, 0.60)
    lit = 1; vC = "#FFFFFF"; vO = 1; uO = 0.6
    split("#FFFFFF #FFFFFF #FFFFFF #FFFFFF", tc, " "); split("0.18 0.18 0.18 0.18", to, " ")
  } else if (down) {
    bC = "#FF375F"; bA = 0.50; mC = "#BF5AF2"; bM = 0.14; bR = 96; gR = 32; gA = 0; hW = 22; hO = 0
    lit = 0; vC = "#FF7A96"; vO = 0.95; uO = 0
    split("#FF375F #FF375F #FF375F #FF375F", tc, " "); split("0.20 0.20 0.24 0.30", to, " ")
  } else {
    bC = "#BF5AF2"; bA = 0.12; mC = "#5E5CE6"; bM = 0.04; bR = 82; gR = 28; gA = 0; hW = 18; hO = 0
    lit = 0; vC = "#FFFFFF"; vO = 0; uO = 0
    split("#64D2FF #5E5CE6 #BF5AF2 #FF375F", tc, " "); split("0.30 0.30 0.30 0.30", to, " ")
  }
  # end ticks step aside when the bead sits on them; the pink one hides on the pink track
  tLO = live ? 0.9 * clamp((fr - 0.03) / 0.05) : 0.9
  tRO = live ? 0.9 * clamp((0.97 - fr) / 0.05) : (down ? 0 : 0.9)

  val = "—"; unit = "ms"                       # 4.2 · 18 · 240 ms, 1.4 s
  if (live) val = (ms < 9.95) ? sprintf("%.1f", ms) : sprintf("%d", ms + 0.5)
  if (live && ms >= 999.5) { val = sprintf("%.1f", ms / 1000); unit = "s" }
  vs = length(val) >= 4 ? 56 : 60

  # the line: 26 samples 4 apart from x 52; 25 on screen (two minutes at 5 s), the newest waits at x 152
  # outside the clip until the slide. Offline samples sit at the top, where the line turns pink.
  n = split(hist, hv, " ")
  for (i = 1; i <= 26; i++) {
    v = (i <= n && hv[i] ~ /^-?[0-9]+(\.[0-9]+)?$/) ? hv[i] + 0 : -1
    ms_[i] = v
    y[i] = shown ? lineY(v) : 167
  }
  pts = ""
  for (i = 1; i <= 26; i++) pts = pts (i > 1 ? " " : "") (52 + 4 * (i - 1)) "," f(y[i])
  tx = ph ? -4 : 0
  hi = ph ? 26 : 25                            # the sample under the right edge (x 148)
  hy = y[hi]; hc = shown ? tint(share(ms_[hi])) : tint(0.5)
  sO = shown ? 1 : 0

  # the globe: big in the middle on the rest face; with a reading it sinks into the unit and dissolves,
  # offline it comes back there in hot pink and a slash strikes it through
  if (live)      { gx = 100; gy = 128; r = 15; gw = 3;   go = 0;    g1 = "#BF5AF2"; g2 = "#64D2FF"; so = 0; sd = 1 }
  else if (down) { gx = 100; gy = 128; r = 15; gw = 3;   go = 0.7;  g1 = "#FF7A96"; g2 = "#FFC2CF"; so = 1; sd = 0 }
  else           { gx = 100; gy = 100; r = 38; gw = 5;   go = 0.75; g1 = "#BF5AF2"; g2 = "#64D2FF"; so = 0; sd = 1 }

  # The addresses, laid out whether they show or not. IPv4: a small globe on top, the public address in one
  # or two lines as large as it fits (two halves of 41 or more), the local one below in 26 when it fits in
  # one line. IPv6: the whole face for the public address, in up to four lines (never under 31).
  a = pub; lo = loc
  if (a == "") { a = "000.000.000.000"; lo = "0.0.0.0" }   # nothing to show yet: the typical layout
  v6 = (a ~ /:/)
  hasLoc = (!v6 && lo != "" && lo != a && em(lo) * 26 <= 184)
  cut(a)
  if (v6) fit(164, 4)
  else    fit(hasLoc ? 97.7 : 132, 2)              # 176 less the globe (30 + 14) and the local line (16 + 18.3)
  hb = ((IN - 1) * 1.12 + 0.705) * IS             # the height of the digits of all the lines
  tot = hb
  if (!v6) tot += 44 + (hasLoc ? 34.3 : 0)
  top = (200 - tot) / 2
  if (!v6) top += 44
  j = 1
  for (i = 1; i <= 4; i++) {
    if (i <= IN) {
      last = (i < IN) ? IL[i] : NP
      t = ""; for (m = j; m <= last; m++) t = t P[m]
      j = last + 1
      lt[i] = (pub == "") ? "0" : t
      ly[i] = top + (i - 1) * 1.12 * IS + 0.3275 * IS   # the middle of the line box sits 0.025 above the digits’
      lv[i] = 1
    } else { lt[i] = "0"; ly[i] = ly[IN]; lv[i] = 0 }   # a spare line waits under the last one
  }
  locY = top + hb + 16 + 8.5
  locT = (pub != "" && hasLoc) ? lo : "0"
  ipO = 0; locO = 0; drop = 10                   # hidden, the addresses wait a little lower and rise as they appear
  vy = 90; uy = 128; tkO = 0.3
  if (ipf) {
    if (!bare) { ipO = 1; locO = hasLoc ? 0.55 : 0; drop = 0 }
    bC = "#BF5AF2"; bA = 0.20; mC = "#5E5CE6"; bM = 0.07; bR = 86   # the calm bloom of a fast answer
    gA = 0; hO = 0; lit = 0; tLO = 0; tRO = 0; tkO = 0; sO = 0
    for (i = 1; i <= 4; i++) to[i] = 0
    vO = 0; uO = 0; vy = 80; uy = 118            # the reading rises away as the address rises in
    if (!v6) { gx = 100; gy = (200 - tot) / 2 + 15; r = 14; gw = 3; go = 0.85; g1 = "#BF5AF2"; g2 = "#64D2FF" }
    else go = 0
    so = 0; sd = 1
  }
  k = 0.95 * r; SL = 2 * k * 1.41421356        # the slash: corner to corner past the rim, drawn in by its dash
  e = r - gw / 2; c = 0.8 * r                  # equator and latitude half-widths: the round caps end on the rim
  lats = sprintf("M %s %s L %s %s M %s %s L %s %s M %s %s L %s %s", \
    f(gx - e), f(gy), f(gx + e), f(gy), f(gx - c), f(gy - 0.5 * r), f(gx + c), f(gy - 0.5 * r), \
    f(gx - c), f(gy + 0.5 * r), f(gx + c), f(gy + 0.5 * r))

  # the line is coloured by height the way the gauge is coloured along its arc
  lineStops = ""
  split("0 0.25 0.375 0.5 0.625 0.75 1", q, " ")
  for (i = 1; i <= 7; i++) lineStops = lineStops "<stop offset=`" q[i] "` stop-color=`" tint(q[i]) "`/>"

  arc = "d=`M 30.72 140 A 80 80 0 1 1 169.28 140` fill=`none`"
  s = "<svg xmlns=`http://www.w3.org/2000/svg` viewBox=`0 0 200 200`><defs>"
  s = s "<linearGradient id=`spec` gradientUnits=`userSpaceOnUse` x1=`24` y1=`0` x2=`176` y2=`0`>" \
        "<stop offset=`0` stop-color=`#64D2FF`/><stop offset=`0.3` stop-color=`#5E5CE6`/><stop offset=`0.65` stop-color=`#BF5AF2`/><stop offset=`1` stop-color=`#FF375F`/></linearGradient>"
  s = s "<linearGradient id=`trackG` gradientUnits=`userSpaceOnUse` x1=`24` y1=`0` x2=`176` y2=`0`>" \
        "<stop offset=`0` stop-color=`" tc[1] "` stop-opacity=`" to[1] "`/><stop offset=`0.3` stop-color=`" tc[2] "` stop-opacity=`" to[2] "`/>" \
        "<stop offset=`0.65` stop-color=`" tc[3] "` stop-opacity=`" to[3] "`/><stop offset=`1` stop-color=`" tc[4] "` stop-opacity=`" to[4] "`/></linearGradient>"
  s = s "<linearGradient id=`lineG` gradientUnits=`userSpaceOnUse` x1=`0` y1=`182` x2=`0` y2=`152`>" \
        lineStops "</linearGradient>"
  s = s "<linearGradient id=`globeG` gradientUnits=`userSpaceOnUse` x1=`" f(gx - r) "` y1=`0` x2=`" f(gx + r) "` y2=`0`><stop offset=`0` stop-color=`" g1 "`/><stop offset=`1` stop-color=`" g2 "`/></linearGradient>"
  s = s "<radialGradient id=`bloomG`><stop offset=`0` stop-color=`" bC "` stop-opacity=`" f(bA) "`/><stop offset=`0.55` stop-color=`" mC "` stop-opacity=`" f(bM) "`/><stop offset=`1` stop-color=`" mC "` stop-opacity=`0`/></radialGradient>"
  s = s "<radialGradient id=`glowG`><stop offset=`0` stop-color=`" gc "` stop-opacity=`" f(gA) "`/><stop offset=`0.4` stop-color=`" gc "` stop-opacity=`" f(0.4 * gA) "`/><stop offset=`1` stop-color=`" gc "` stop-opacity=`0`/></radialGradient>"
  s = s "<clipPath id=`lineClip`><rect x=`52` y=`140` width=`96` height=`54`/></clipPath></defs>"

  s = s "<circle id=`bloom` cx=`100` cy=`100` r=`" f(bR) "` fill=`url(#bloomG)`/>"
  s = s "<path id=`track` " arc " stroke=`url(#trackG)` stroke-width=`6` stroke-linecap=`round`/>"
  # quiet marks at 10 ms and 100 ms
  s = s "<path id=`ticks` d=`M 60.15 52.51 L 56.93 48.68 M 139.85 52.51 L 143.07 48.68` fill=`none` stroke=`#FFFFFF` stroke-opacity=`" f(tkO) "` stroke-width=`2.5` stroke-linecap=`round`/>"
  s = s "<line id=`tickL` x1=`46.31` y1=`131` x2=`41.98` y2=`133.5` stroke=`#64D2FF` stroke-opacity=`" f(tLO) "` stroke-width=`3` stroke-linecap=`round`/>"
  s = s "<line id=`tickR` x1=`153.69` y1=`131` x2=`158.02` y2=`133.5` stroke=`#FF375F` stroke-opacity=`" f(tRO) "` stroke-width=`3` stroke-linecap=`round`/>"
  s = s "<path id=`litGlow` " arc " stroke=`url(#spec)` stroke-opacity=`" f(0.2 * lit) "` stroke-width=`22` stroke-linecap=`round` stroke-dasharray=`335.1 400` stroke-dashoffset=`" f(off) "`/>"
  s = s "<path id=`lit` " arc " stroke=`url(#spec)` stroke-opacity=`" f(lit) "` stroke-width=`9` stroke-linecap=`round` stroke-dasharray=`335.1 400` stroke-dashoffset=`" f(off) "`/>"
  s = s "<path id=`core` " arc " stroke=`#FFFFFF` stroke-opacity=`" f(0.45 * lit) "` stroke-width=`2.5` stroke-linecap=`round` stroke-dasharray=`335.1 400` stroke-dashoffset=`" f(off) "`/>"
  s = s "<circle id=`glowA` cx=`100` cy=`26` r=`" f(gR) "` fill=`url(#glowG)` fill-opacity=`" f(wA) "` transform=`rotate(" f(angA) " 100 100)`/>"
  s = s "<circle id=`glowB` cx=`100` cy=`26` r=`" f(gR) "` fill=`url(#glowG)` fill-opacity=`" f(wB) "` transform=`rotate(" f(angB) " 100 100)`/>"
  s = s "<path id=`halo` " arc " stroke=`url(#spec)` stroke-opacity=`" f(hO) "` stroke-width=`" f(hW) "` stroke-linecap=`round` stroke-dasharray=`0.1 400` stroke-dashoffset=`" f(-d) "`/>"
  s = s "<path id=`bead` " arc " stroke=`#FFFFFF` stroke-opacity=`" f(lit) "` stroke-width=`12` stroke-linecap=`round` stroke-dasharray=`0.1 400` stroke-dashoffset=`" f(-d) "`/>"

  s = s "<line id=`lineBase` x1=`52` y1=`182` x2=`148` y2=`182` stroke=`#FFFFFF` stroke-opacity=`" f(0.12 * sO) "` stroke-width=`1.5` stroke-linecap=`round`/>"
  s = s "<g id=`chart` clip-path=`url(#lineClip)`><g id=`scroll` transform=`translate(" tx " 0)`>"
  s = s "<polyline id=`lineGlow` points=`" pts "` fill=`none` stroke=`url(#lineG)` stroke-opacity=`" f(0.22 * sO) "` stroke-width=`10` stroke-linecap=`round` stroke-linejoin=`round`/>"
  s = s "<polyline id=`line` points=`" pts "` fill=`none` stroke=`url(#lineG)` stroke-opacity=`" f(sO) "` stroke-width=`3.5` stroke-linecap=`round` stroke-linejoin=`round`/>"
  s = s "<polyline id=`lineCore` points=`" pts "` fill=`none` stroke=`#FFFFFF` stroke-opacity=`" f(0.45 * sO) "` stroke-width=`1.2` stroke-linecap=`round` stroke-linejoin=`round`/>"
  s = s "</g></g>"
  s = s "<circle id=`headHalo` cx=`148` cy=`" f(hy) "` r=`6.5` fill=`" hc "` fill-opacity=`" f(0.5 * sO) "`/>"
  s = s "<circle id=`headBead` cx=`148` cy=`" f(hy) "` r=`3.5` fill=`#FFFFFF` fill-opacity=`" f(sO) "`/>"

  # the globe lies under the text: the number fades in over it while it sinks
  s = s "<circle id=`globe` cx=`" f(gx) "` cy=`" f(gy) "` r=`" f(r) "` fill=`none` stroke=`url(#globeG)` stroke-opacity=`" f(go) "` stroke-width=`" f(gw) "`/>"
  s = s "<ellipse id=`meridian` cx=`" f(gx) "` cy=`" f(gy) "` rx=`" f(0.42 * r) "` ry=`" f(r) "` fill=`none` stroke=`url(#globeG)` stroke-opacity=`" f(go) "` stroke-width=`" f(gw) "`/>"
  s = s "<path id=`lats` d=`" lats "` fill=`none` stroke=`url(#globeG)` stroke-opacity=`" f(go) "` stroke-width=`" f(gw) "` stroke-linecap=`round`/>"
  s = s "<line id=`slash` x1=`" f(gx - k) "` y1=`" f(gy - k) "` x2=`" f(gx + k) "` y2=`" f(gy + k) "` stroke=`#FF375F` stroke-opacity=`" f(so) "` stroke-width=`" f(gw * 1.5) "` stroke-linecap=`round` stroke-dasharray=`" f(SL) " 400` stroke-dashoffset=`" f(sd * SL) "`/>"
  s = s "<text id=`value` x=`100` y=`" vy "` font-size=`" vs "` font-weight=`600` text-anchor=`middle` dominant-baseline=`middle` fill=`" vC "` fill-opacity=`" f(vO) "`>" val "</text>"
  s = s "<text id=`unit` x=`100` y=`" uy "` font-size=`26` font-weight=`600` text-anchor=`middle` dominant-baseline=`middle` fill=`#FFFFFF` fill-opacity=`" f(uO) "`>" unit "</text>"
  for (i = 1; i <= 4; i++) \
    s = s "<text id=`ip" i "` x=`100` y=`" f(ly[i] + drop) "` font-size=`" IS "` font-weight=`600` text-anchor=`middle` dominant-baseline=`middle` fill=`#FFFFFF` fill-opacity=`" f(ipO * lv[i]) "`>" lt[i] "</text>"
  s = s "<text id=`ipLocal` x=`100` y=`" f(locY + drop) "` font-size=`26` font-weight=`600` text-anchor=`middle` dominant-baseline=`middle` fill=`#FFFFFF` fill-opacity=`" f(locO) "`>" locT "</text>"
  s = s "</svg>"
  gsub(/`/, "\"", s)
  printf "%s\n", s
}'

net_frame() {
  emulate -L zsh
  export LC_ALL=C
  local st=${1:-rest} ph=${2:-0} ms=${3:--1} pub=${(L)5:-} loc=${6:-}
  [[ $st == (rest|live|offline|ip|bare) ]] || st=rest
  [[ $ph == (0|1) ]] || ph=0
  [[ $ms == (<->|<->.<->) ]] || ms=-1
  [[ -n $pub && $pub != *[^0-9a-f.:]* && ${#pub} -le 39 ]] || pub=""
  [[ $loc == <0-255>.<0-255>.<0-255>.<0-255> ]] || loc=""
  [[ $st == (ip|bare) && -z $pub ]] && st=live
  [[ $st == live && $ms == -1 ]] && st=offline
  awk -v st=$st -v ph=$ph -v ms=$ms -v hist="${4:-}" -v pub=$pub -v loc=$loc "$NET_AWK"
}
# ---- end net_frame ----
# ---- state and posting: identical in startup.zsh and hold.zsh ----
cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"
hist_file="$dir/history"
# What the hold put on the face, one line: "<public IP> <local IP, - when none> <until, epoch ms>".
ip_file="$dir/ip"

# REPLY = now, epoch milliseconds (zsh/datetime, no process)
now_ms() { REPLY=$(( epochtime[1] * 1000 + epochtime[2] / 1000000 )) }

# The history survives a restart (the phone reconnected, the agent was updated) for two minutes, the span it shows.
# One line: "<epoch seconds> <26 latencies>". Parsed field by field (never sourced); anything else is no history.
# load_history [max age, s]: the hold passes a day, since it wants what the face shows, however old.
load_history() {
  local line="" x
  local -a w
  hist=()
  [[ -r $hist_file ]] || return 0
  IFS= read -r line < $hist_file
  w=( ${=line} )
  (( ${#w} == 27 )) && [[ $w[1] == <-> && ${#w[1]} -le 12 ]] || return 0
  (( w[1] <= EPOCHSECONDS && EPOCHSECONDS - w[1] <= ${1:-120} )) || return 0
  for x in ${w[2,-1]}; do
    [[ $x == (-1|<->.<->) && ${#x} -le 8 ]] || return 0
  done
  hist=( ${w[2,-1]} )
}

# post <frame> <duration> [easing]: sets post_code and post_seen (0 when the button is not on screen).
# The token goes in through a descriptor, not the command line, where any user of the Mac could read it.
post() {
  local json=$1 answer
  json=${json//\\/\\\\}; json=${json//\"/\\\"}; json=${json//$'\n'/}
  answer=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" -H @/dev/fd/3 \
    -H "Content-Type: application/json" --data-binary @- \
    3<<< "Authorization: Bearer $DESMAPTIC_TOKEN" \
    <<< "{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$json\",\"duration\":$2,\"easing\":\"${3:-easeInOut}\"}}")
  post_code=${answer##*$'\n'}
  post_seen=1
  [[ ${answer// /} == *'"visible":false'* ]] && post_seen=0
  [[ $post_code == 200 ]] && return 0
  print -u2 -- "internet: update-button answered ${post_code:-nothing}: ${${answer%$'\n'*}[1,300]}"
  return 1
}
# ---- end state and posting ----

# ---- hold ----
# Sets pub: the address the internet sees this Mac by, as Cloudflare's trace reports it. IPv4 first; when
# there is no IPv4 route (or no answer over it), IPv6.
public_ip() {
  local answer line fam host
  pub=""
  for fam in 4 6; do
    host=1.1.1.1; (( fam == 6 )) && host='[2606:4700:4700::1111]'
    answer=$(curl -q -$fam -s -m 5 "https://$host/cdn-cgi/trace" 2>/dev/null) || continue
    for line in ${(f)answer}; do
      [[ $line == ip=* ]] && pub=${(L)line#ip=}
    done
    [[ $pub == <0-255>.<0-255>.<0-255>.<0-255> ]] && return 0
    [[ $pub == *:* && $pub != *[^0-9a-f:]* && ${#pub} -le 39 ]] && return 0
    pub=""
  done
  return 1
}

# Sets loc: the Mac's address in its own network, on the interface of the default route; "-" when there is none.
local_ip() {
  local out ifc
  loc=-
  out=$(route -n get default 2>/dev/null) || return 0
  ifc=${${(M)${(f)out}:#*interface:*}#*interface:}
  ifc=${ifc// /}
  [[ -n $ifc && $ifc != *[^a-z0-9]* ]] || return 0
  out=$(ipconfig getifaddr $ifc 2>/dev/null)
  [[ $out == <0-255>.<0-255>.<0-255>.<0-255> && $out != "$pub" ]] && loc=$out
  return 0
}

public_ip || { print -u2 -- "internet: Cloudflare gave no IP address over IPv4 or IPv6: is the Mac online?"; exit 1 }
print -rn -- "$pub" | pbcopy || { print -u2 -- "internet: pbcopy could not put $pub on the clipboard"; exit 1 }
local_ip

# The address stays up for 8 s: the loop leaves it alone until then and brings the gauge back after.
now_ms
if ! { zf_mkdir -p -- "$dir" && print -r -- "$pub $loc $(( REPLY + 8000 ))" > "$ip_file.$$" \
    && zf_mv -f -- "$ip_file.$$" "$ip_file" }; then
  rm -f -- "$ip_file.$$"
  print -u2 -- "internet: cannot write $ip_file; $pub is copied, but the face shows it only until the next sample"
fi

# The gauge under the address is the one the face shows now (the last sample, the line as the last slide
# ended), so it fades out in place: first the gauge goes, then the address rises in.
load_history 86400
last=${hist[-1]:--1}
post "$(net_frame bare 1 $last "${hist[*]}" "$pub" "${loc#-}")" 0.3 && zselect -t 30
post "$(net_frame ip 1 $last "${hist[*]}" "$pub" "${loc#-}")" 0.4
exit 0
