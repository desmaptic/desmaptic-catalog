#!/bin/zsh
# Mac Town: a little town across a whole page of 1×1 Desmaptic buttons that mirrors this Mac (the Gallery's «Unusual»).
#
# This is the startup script of ONE tile of the page — the engine — and it draws every tile of its page, where the
# phone says they stand (GET /api/view, Gallery entries "town.r<row>c<col>"). Every open app is a building with its
# name on a sign: as tall as the memory it uses, its chimney smoking with the processor it uses, its windows lit at
# night while it works. Opening an app raises a building out of the ground, quitting it sinks it, and the most recent
# apps take the town's places (the others wait). The app in front has a glowing sign and a traffic light before it.
# Cars fill the street as the Mac gets busier, up to a jam; a train brings the network in and takes it out, longer as
# the traffic grows. The sky follows the clock,
# the street lamps light up at dusk (dimmer when the battery runs low). A tap on a building switches to its app.
# Upright the town has two quarters (a street, and a viaduct with the railway); turned, one wide street.
#
# The plumbing is the Pet's and the Aquarium's (the desmaptic-widgets skill, references/scenes.md): windows onto one
# world with the phone's real gaps, constant tile structures with parked movers and invisible jumps, one keep-alive
# connection, a long-lived awk process holding the world, slow tiles every third tick. Only zsh and awk.
#
# Tool modes (they never touch the network):
#   zsh engine.zsh --faces faces.json      the resting and sample faces of the 6×8 page (the scene's faces.json)
#   zsh engine.zsh --cover cover.svg       the picture on the scene's Gallery card (the 8×4 street at night)
#   zsh engine.zsh --dump <4|6> <portrait|landscape> <HH:MM> <step> out.json [story]   every tile's frame at one moment
#   zsh engine.zsh --seq  <4|6> <portrait|landscape> <HH:MM> <steps> out.jsonl [story]  every changed frame of a story
emulate -R zsh
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
TMPPREFIX="${TMPDIR:-/tmp}/zsh"
zmodload zsh/net/tcp zsh/system zsh/zselect zsh/datetime || { print -u2 -- "town: a zsh module is missing"; exit 1 }
zmodload -F zsh/files b:zf_mv b:zf_rm || { print -u2 -- "town: zsh module files is missing"; exit 1 }

# The world. It reads one command per line on stdin:
#   M live <cellId> <seed> | M dump|seq <columns> <portrait|landscape> <minutes> <steps> <story>   the first line
#   V <body of GET /api/view>      F <cellId>   a tap      R   send every tile again      Q   quit (remove the faces)
#   A, P <bundle> <memory KB> <cpu %> <name>, Z   the open apps, most recent first
#   N <bundle>   the app in front      W <bytes in> <bytes out> <now>   network      Y <percent> <charging> <battery>
#   S <now, s> <minutes since midnight> <load per core> <slow> <Mac idle, s>   one tick
# After every S it writes "B <bytes> <requests> <shown> <seconds to the next tick> <bundle to open or ->\n", after Q
# the same line starting with "Q", and then exactly <bytes> bytes of pipelined requests.
town_world() {
  local fd; for fd in {4..63}; do exec {fd}>&-; done 2>/dev/null
  [[ $1 == live ]] && trap '' TERM INT HUP
  exec awk -f /dev/fd/3 3<<'AWK'
BEGIN {
  PI = 3.141592653589793; RAD = PI / 180
  TOKEN = ENVIRON["DESMAPTIC_TOKEN"]
  split("1 1 -1 -1 -1 1 1", EUX, " "); split("0 1.333 1.333 0 -1.333 -1.333 0", EUY, " ")
  ELLPK = "M0 0Q0 0 0 0 0 0 0 0Z"
  for (i = 1; i <= 6; i++) { HXC[i] = cos((i - 1) * PI / 3); HXS[i] = sin((i - 1) * PI / 3) }
  palettes(); appdeck()
  GEN = 0; TICK = 0; T = 0; NOW = 0; SHOWN = 0; COLS = 0; LGEN = 0; UPC = 0; KAC = 0
  GAP = 0; PITCH = 100; GDEMO = 15; PER = 0.5; NCAR = 6; NPPL = 0; NFLY = 3; NADR = 10; NFW = 1; GOING = 5; WNEXT = 300; WAVE0 = -100; GLNEXT = 60; KTNEXT = 90
  LOAD = 0; AWAKE = 1; FRONT = ""; FRONTX = -1; HASBAT = 0; BATT = 100; CHARGING = 0; OPENB = ""
}

# ---------------------------------------------------------------- numbers, randomness, colour
function abs(x) { return x < 0 ? -x : x }
function mn(a, b) { return a < b ? a : b }
function mx(a, b) { return a > b ? a : b }
function cl(x, a, b) { return x < a ? a : (x > b ? b : x) }
function sgn(x) { return x < 0 ? -1 : 1 }
function f1(x) { return RI ? sprintf("%.0f", x) : sprintf("%.1f", x) }
function f2(x) { return sprintf("%.2f", x) }
function smooth(t) { t = cl(t, 0, 1); return t * t * (3 - 2 * t) }
function hyp(x, y) { return sqrt(x * x + y * y) }
function rnd() { SEED = (SEED * 16807) % 2147483647; return SEED / 2147483647 }
function rr(a, b) { return a + (b - a) * rnd() }
function srnd() { SSEED = (SSEED * 16807) % 2147483647; return SSEED / 2147483647 }
function sr(a, b) { return a + (b - a) * srnd() }
function hx2(s) { return (index("0123456789ABCDEF", toupper(substr(s, 1, 1))) - 1) * 16 + index("0123456789ABCDEF", toupper(substr(s, 2, 1))) - 1 }
function rgb(h) { CR = hx2(substr(h, 2, 2)); CG = hx2(substr(h, 4, 2)); CB = hx2(substr(h, 6, 2)) }
function hexc(r, g, b) { return sprintf("#%02X%02X%02X", cl(int(r + 0.5), 0, 255), cl(int(g + 0.5), 0, 255), cl(int(b + 0.5), 0, 255)) }
function mixh(a, b, t,   r, g, bb) { rgb(a); r = CR; g = CG; bb = CB; rgb(b); return hexc(r + (CR - r) * t, g + (CG - g) * t, bb + (CB - bb) * t) }
# A colour under the light of a room (0 kitchen, 1 living room, 2 attic, 3 outside); cached until that light changes.
function li(h, r,   k) { k = h SUBSEP r; if (k in LITC) return LITC[k]; rgb(h); LITC[k] = hexc(CR * LR[r], CG * LG[r], CB * LB[r]); return LITC[k] }
# A light source keeps its colour whatever the room's light.
function glow(h, r, k) { return mixh(li(h, r), h, k) }
function rotp(px, py, cx, cy, a,   c, s) { c = cos(a * RAD); s = sin(a * RAD); RPX = cx + (px - cx) * c - (py - cy) * s; RPY = cy + (px - cx) * s + (py - cy) * c }
# ---------------------------------------------------------------- SVG building blocks
# In park mode (PK) each block writes its parked twin: the same element, the same kind of paint, no numbers.
function el(cx, cy, rx, ry, fill, xt) { if (PK) return "<ellipse/>"; return "<ellipse cx='" f1(cx) "' cy='" f1(cy) "' rx='" f1(rx) "' ry='" f1(ry) "' fill='" fill "'" xt "/>" }
function ci(cx, cy, r, fill, xt) { if (PK) return "<circle/>"; return "<circle cx='" f1(cx) "' cy='" f1(cy) "' r='" f1(r) "' fill='" fill "'" xt "/>" }
function re(x, y, w, h, fill, xt) { if (PK) return "<rect/>"; return "<rect x='" f1(x) "' y='" f1(y) "' width='" f1(w) "' height='" f1(h) "' fill='" fill "'" xt "/>" }
function rr_(x, y, w, h, r, fill, xt) { if (PK) return "<rect rx='1'/>"; return "<rect x='" f1(x) "' y='" f1(y) "' width='" f1(w) "' height='" f1(h) "' rx='" f1(r) "' fill='" fill "'" xt "/>" }
function ringc(cx, cy, r, fill, sc, sw, xt) { if (PK) return "<circle stroke='#000'/>"; return "<circle cx='" f1(cx) "' cy='" f1(cy) "' r='" f1(r) "' fill='" fill "' stroke='" sc "' stroke-width='" f1(sw) "'" xt "/>" }
function pg(n, fill, xt,   k, s) {
  if (PK) { s = "<polygon points='0,0"; for (k = 2; k <= n; k++) s = s " 0,0"; return s "'/>" }
  s = "<polygon points='" f1(PX[1]) "," f1(PY[1])
  for (k = 2; k <= n; k++) s = s " " f1(PX[k]) "," f1(PY[k])
  return s "' fill='" fill "'" xt "/>"
}
function sub_poly(n,   k, s) {
  if (PK) { s = "M0 0"; for (k = 2; k <= n; k++) s = s " 0 0"; return s "Z" }
  s = "M" f1(PX[1]) " " f1(PY[1])
  for (k = 2; k <= n; k++) s = s " " f1(PX[k]) " " f1(PY[k])
  return s "Z"
}
function sub_dot(cx, cy, r,   k) {
  if (PK) return "M0 0 0 0 0 0 0 0 0 0 0 0Z"
  for (k = 1; k <= 6; k++) { PX[k] = cx + r * HXC[k]; PY[k] = cy + r * HXS[k] }
  return sub_poly(6)
}
function sub_ell(cx, cy, rx, ry, a,   c, s, i, ux, uy, str) {
  if (PK) return ELLPK
  c = cos(a * RAD); s = sin(a * RAD)
  for (i = 1; i <= 7; i++) {
    ux = EUX[i] * rx; uy = EUY[i] * ry
    str = str (i == 1 ? "M" : (i == 2 ? "C" : " ")) f1(cx + ux * c - uy * s) " " f1(cy + ux * s + uy * c)
  }
  return str "Z"
}
function pth(d, fill, xt) { if (PK) return "<path d='" d "'/>"; return "<path d='" d "' fill='" fill "'" xt "/>" }
function strk(d, sc, sw, xt) { if (PK) return "<path d='" d "' fill='none' stroke='#000' stroke-linecap='round' stroke-linejoin='round'/>"; return "<path d='" d "' fill='none' stroke='" sc "' stroke-width='" f1(sw) "' stroke-linecap='round' stroke-linejoin='round'" xt "/>" }
function seg_(x0, y0, x1, y1) { if (PK) return "M0 0L0 0"; return "M" f1(x0) " " f1(y0) "L" f1(x1) " " f1(y1) }
function rot(a, x, y) { return " transform='rotate(" f1(a) " " f1(x) " " f1(y) ")'" }
# A creature's group names its pivot (`rotate(a 0 0)`): the phone turns every part about that one point, so the
# parts glide as one piece.
function gin(x, y, a, op, sc) { return PK ? "" : "<g transform='translate(" f1(x) " " f1(y) ") rotate(" f1(a) " 0 0)" (sc != "" ? " scale(" sc ")" : "") "'" (op < 1 ? " opacity='" f2(op) "'" : "") ">" }
function gout() { return PK ? "" : "</g>" }
function opa(op) { return op < 1 ? " opacity='" f2(op) "'" : "" }
# ---------------------------------------------------------------- light: the Mac's clock
function palettes() {
  # sky top, sky at the horizon, outside light r g b, night share
  PAL["n"] = "#05040F #3A0F4F 0.62 0.6 0.8 1"
  PAL["a"] = "#1E1640 #B8456E 0.8 0.72 0.8 0.35"
  PAL["d"] = "#2B3A60 #A48DBE 0.92 0.9 0.97 0"
  PAL["u"] = "#1A1036 #E0506E 0.82 0.7 0.8 0.35"
  split("0 5 6.5 8 17.5 19.5 21 24.01", KH, " ")
  split("n n a d d u n n", KP, " ")
}
function light(minutes,   h, k, t, a, b, dig) {
  h = int(minutes / 3) * 3 / 60
  for (k = 1; k < 8; k++) if (h < KH[k + 1]) break
  t = smooth((h - KH[k]) / (KH[k + 1] - KH[k]))
  split(PAL[KP[k]], a, " "); split(PAL[KP[k + 1]], b, " ")
  SKY1 = mixh(a[1], b[1], t); SKY2 = mixh(a[2], b[2], t)
  LR[3] = a[3] + (b[3] - a[3]) * t; LG[3] = a[4] + (b[4] - a[4]) * t; LB[3] = a[5] + (b[5] - a[5]) * t
  LR[4] = 1; LG[4] = 1; LB[4] = 1
  NIGHT = a[6] + (b[6] - a[6]) * t
  SUNA = cl(1 - 1.6 * NIGHT, 0, 1); MOONA = cl(1.6 * NIGHT - 0.6, 0, 1)
  # street lamps: on at dusk, dimmer when the battery runs low
  BLACK = HASBAT && BATT < 10 && !CHARGING
  LAMPA = (0.35 + 0.65 * cl((NIGHT - 0.2) / 0.5, 0, 1)) * (BLACK ? 0.15 : (HASBAT && BATT < 20 && !CHARGING ? 0.45 : 1))
  NEONA = 0.6 + 0.4 * NIGHT
  dig = SKY1 SKY2 LR[3] LG[3] LB[3] " " int(LAMPA * 20) " " RAINY " " BLACK
  if (dig == LIGHTDIG) return 0
  LIGHTDIG = dig; LGEN++
  delete LITC
  return 1
}

# ---------------------------------------------------------------- the world: a town on the tile grid
function tl(i) { return i * PITCH }
function tc(i) { return i * PITCH + 50 }
function tt(j) { return j * PITCH }
function world(cols, ori) {
  COLS = cols; ORI = ori; PORT = ori == "portrait"
  if (PORT) { NTA = cols; NTD = 8 } else { NTA = 8; NTD = cols }
  PITCH = 100 + GAP; W = NTA * PITCH - GAP; H = NTD * PITCH - GAP
  GEN++
  layout()
  LIGHTDIG = ""
  if (!CAST) cast()
  place_cast()
  statics(); dyns()
  bucket()
  delete TST
}
# The downtown street on the lowest row (the pavement 74 units down its tiles, the road below), and on a tall page an
# upper quarter on a viaduct four rows higher, with the railway on its deck. On a low page the railway runs along the
# horizon behind the street. One building stands in the middle of each tile of a quarter, whole inside it.
function layout(   i, s) {
  DOWN = NTD - 1; DY = tt(DOWN) + 74
  UP = NTD == 8 ? 3 : (NTD == 6 ? 2 : -1); UY = UP >= 0 ? tt(UP) + 86 : -1
  RAILY = UP >= 0 ? UY : tt(DOWN - 1) + 62
  HORY = UP >= 0 ? UY : RAILY
  ai_place(); hc_place()
  NSLOT = 0
  for (i = 0; i < NTA; i++) { s = ++NSLOT; SX[s] = tc(i); SG[s] = DY; SMAX[s] = DY - (UP >= 0 ? tt(UP + 1) + 36 : tt(0) + 48); SQ[s] = 0 }
  if (UP >= 0) for (i = 0; i < NTA; i++) { s = ++NSLOT; SX[s] = tc(i); SG[s] = UY; SMAX[s] = UY - (UP >= 2 ? tt(UP - 2) + 40 : tt(0) + 48); SQ[s] = 1 }
}

# ---------------------------------------------------------------- static scenery (rebuilt when the light changes)
function st(layer, s, x0, y0, x1, y1) { NS++; SL_[NS] = layer; SST[NS] = s; SX0[NS] = x0; SY0[NS] = y0; SX1[NS] = x1; SY1[NS] = y1 }
# Everything long is cut into tile columns: a tile carries only its own stars, blocks, lights, rails and road marks.
function statics(   i, j, x, y, s, k) {
  NS = 0; RI = 1
  # stars, a few per tile of the sky
  if (NIGHT > 0.05) for (i = 0; i < NTA; i++) for (j = 0; tt(j) < HORY - 40; j++) {
    SSEED = 7717 + i * 131 + j * 17; s = ""
    for (k = 0; k < 3; k++) { x = tl(i) + sr(2, 98); y = tt(j) + sr(2, 98); if (y < HORY - 40) s = s sub_dot(x, y, sr(0.9, 1.7)) }
    if (s != "") st(1, pth(s, "#FFF6D8", " opacity='" f2(0.9 * NIGHT) "'"), tl(i), tt(j), tl(i) + 100, tt(j) + 100)
  }
  # the far town on the horizon, and on a tall page the near one behind the street
  skyline(HORY, 0)
  if (UP >= 0) skyline(DY, 1)
  # the viaduct's deck with its neon edge
  if (UP >= 0) st(3, re(-1, UY, W + 2, 14, li("#1C1A28", 3)) re(-1, UY + 12, W + 2, 2, "#FF2BD6", " opacity='" f2(0.6 * NEONA) "'"), 0, UY, W, UY + 14)
  rails(RAILY)
  # the downtown street: pavement, kerb, road; its dashed middle line tile by tile
  st(3, re(-1, DY - 3, W + 2, 6, li("#3A3848", 3)) re(-1, DY + 3, W + 2, H - DY, li("#12111A", 3)) re(-1, DY + 3, W + 2, 1.6, "#35E8FF", " opacity='" f2(0.35 * NEONA) "'"), 0, DY - 3, W, H)
  for (i = 0; i < NTA; i++) st(3, "<path d='" seg_(tl(i) + 8, DY + 15, tl(i) + 92, DY + 15) "' fill='none' stroke='#35E8FF' stroke-width='1.4' stroke-dasharray='10 9' opacity='" f2(0.45 * NEONA) "'/>", tl(i), DY + 12, tl(i) + 100, DY + 18)
  for (i = 0; i < NTA; i++) lamp_post(tl(i) + 7, DY - 3)
  if (UP >= 0) for (i = 0; i < NTA; i++) lamp_post(tl(i) + 7, UY)
  RI = 0
}
# The town behind: dark blocks, each with its own grid of windows (a few lit, amber and cyan), a lighter line along the
# roofs, and on the tall ones an antenna with its red light. Tile by tile, so each tile carries only its own.
# The town behind: dark blocks, each with its own grid of windows (a few lit, amber and cyan, spread over its whole
# height), a lighter line along the roofs, and on the tall ones an antenna with its red light. Tile by tile.
function skyline(base, near,   rj, s, i, x, w, h, k, top, lit, lit2, red, ant, edge, r, c, x0, x1, wx, wy, p, nb, b, cells) {
  top = near && UP >= 0 ? base - tt(UP + 1) - 6 : (near ? 110 : 150)
  k = mixh(SKY2, "#0B0A18", near ? 0.62 : 0.68); edge = mixh(k, "#6E6A96", 0.35)
  for (i = 0; i < NTA; i++) {
    SSEED = 3301 + near * 17 + i * 53; s = ""; lit = ""; lit2 = ""; red = ""; ant = ""; r = ""; nb = 0; cells = 0
    x = tl(i) - 2
    while (x < tl(i) + 100) { w = sr(14, 26); h = sr(top * 0.3, top); nb++; BKX0[nb] = x; BKX1[nb] = mn(x + w, tl(i) + 102); BKH[nb] = h; cells += int((h - 14) / 7) * int((BKX1[nb] - x - 5) / 5 + 1); x += w + sr(0, 4) }
    # about 30 lit windows a tile, whatever the blocks' heights (a few more at night)
    p = cells > 0 ? mn(0.3, (22 + 10 * NIGHT) / cells) : 0
    for (b = 1; b <= nb; b++) {
      x0 = BKX0[b]; x1 = BKX1[b]; h = BKH[b]
      s = s "M" f1(x0) " " f1(base) "V" f1(base - h) "H" f1(x1) "V" f1(base) "Z"
      r = r "M" f1(x0) " " f1(base - h) "H" f1(x1)
      for (wy = base - 8; wy > base - h + 6; wy -= 7) for (wx = x0 + 3; wx < x1 - 2; wx += 5) {
        c = srnd()
        # (each window goes to its own tile row's list: a tile carries only the lights it shows)
        if (c < p) { rj = int(wy / PITCH); if (c < p * 0.75) LITR[rj] = LITR[rj] "M" f1(wx) " " f1(wy) "h1.8v2.4h-1.8Z"; else LITR2[rj] = LITR2[rj] "M" f1(wx) " " f1(wy) "h1.8v2.4h-1.8Z" }
      }
      if (h > top * 0.72) { ant = ant "M" f1((x0 + x1) / 2) " " f1(base - h) "V" f1(base - h - 9); red = red sub_dot((x0 + x1) / 2, base - h - 10, 1.4) }
    }
    st(near ? 2 : 1, pth(s, k) strk(r, edge, 1) (ant == "" ? "" : strk(ant, k, 1.2)) (red == "" ? "" : pth(red, "#FF3B5C", " opacity='" f2(0.55 + 0.4 * NIGHT) "'")), tl(i), base - top - 12, tl(i) + 100, base)
    for (rj in LITR) st(near ? 2 : 1, pth(LITR[rj], "#FFD27A", " opacity='" f2(0.45 + 0.45 * NIGHT) "'"), tl(i), tt(rj), tl(i) + 100, tt(rj) + 100)
    for (rj in LITR2) st(near ? 2 : 1, pth(LITR2[rj], "#6FF3FF", " opacity='" f2(0.4 + 0.4 * NIGHT) "'"), tl(i), tt(rj), tl(i) + 100, tt(rj) + 100)
    delete LITR; delete LITR2
  }
  st(near ? 2 : 1, re(-1, base - 26, W + 2, 26, SKY2, " opacity='0.3'"), 0, base - 26, W, base)
}
function rails(y,   s, i, x) {
  for (i = 0; i < NTA; i++) {
    s = ""; for (x = tl(i) + 2; x < tl(i) + 100; x += 9) s = s seg_(x, y - 1, x, y + 2)
    st(3, strk(s, li("#2A2838", 3), 2.4), tl(i), y - 4, tl(i) + 100, y + 3)
  }
  st(3, re(-1, y - 3, W + 2, 1.8, li("#6E6A86", 3)), 0, y - 4, W, y + 3)
}
function lamp_post(x, y) {
  st(7, re(x - 1.2, y - 48, 2.4, 48, li("#2A2838", 3)) re(x - 1.2, y - 48, 10, 2.4, li("#2A2838", 3)) rr_(x + 2, y - 46, 10, 3, 1.5, mixh("#3A2040", "#FF3CAC", 0.85 * LAMPA), rot(8, x + 2, y - 45)), x - 2, y - 50, x + 13, y)
  st(7, el(x + 7, y, 14, 2.3, "#FF3CAC", " opacity='" f2(0.3 * LAMPA) "'"), x - 7, y - 3, x + 21, y + 3)
}

# ---------------------------------------------------------------- the buildings: one per slot, a fixed set of elements
function newd(k, layer, x0, y0, x1, y1) { ND++; DK[ND] = k; DL[ND] = layer; DX0[ND] = x0; DY0[ND] = y0; DX1[ND] = x1; DY1[ND] = y1; return ND }
function dyns(   s, d, i, j) {
  ND = 0
  for (s = 1; s <= NSLOT; s++) { d = newd("bld", 4, SX[s] - 40, SG[s] - SMAX[s] - 44, SX[s] + 40, SG[s] + (SQ[s] ? 0 : 24)); DS_[d] = s }
  newd("hclock", 2, HCX + 4, HCY + 28, HCX + 96, HCY + 72)
  if (PORT) { newd("sun", 1, 0, 0, tl(1) + 40, tt(1) + 40); newd("moon", 1, tl(NTA - 1) - 40, 0, W, tt(1) + 40) }
  else { newd("sun", 1, 0, 0, W, HORY); newd("moon", 1, 0, 0, W, HORY) }
}
function dstr(d, id,   y) {
  # a building is cut to the tile's rows: the tiles below its roof keep the same picture while it grows
  if (DK[d] == "bld") {
    y = id == "COVER" || id == "" ? -1e6 : TY[id]
    if (DBT[d, y] != TICK) { CLY0 = y == -1e6 ? -1e6 : y - 6; CLY1 = y == -1e6 ? 1e6 : y + 106; DBS[d, y] = building(DS_[d]); DBT[d, y] = TICK }
    return DBS[d, y]
  }
  if (DST[d] != TICK) { DSS[d] = dmake(d); DST[d] = TICK }; return DSS[d]
}
function cy(y) { return y < CLY0 ? CLY0 : (y > CLY1 ? CLY1 : y) }
# a vertical dashed stroke from y0 to y1, cut to the tile: the dashes keep their places (the offset is what was cut)
function vd(x, y0, y1,   a, b) { a = cy(y0); b = cy(y1); return "M" f1(x) " " f1(a) "V" f1(b) "' stroke-dashoffset='" f1(abs(y0 - a)) }
# a rect cut to the tile rows
function rrc(x, y, w, h, r, fill, xt,   a, b) { a = cy(y); b = cy(y + h); return rr_(x, a, w, mx(b - a, 0.5), r, fill, xt) }
function dmake(d,   k) {
  k = DK[d]
  if (k == "bld") return building(DS_[d])
  if (k == "rain") return rain(d)
  if (k == "hclock") return hclock()
  if (k == "sun") { sunpos("sun"); return ringc(SPX, SPY, 13, "#FFE58A", "#FFD24A", 8, " stroke-opacity='0.35' opacity='" f2(SUNA) "'") }
  if (k == "moon") { sunpos("moon"); return ringc(SPX, SPY, 10, "#F2F0DC", "#F2F0DC", 7, " stroke-opacity='0.18' opacity='" f2(MOONA) "'") pth(sub_dot(SPX - 3, SPY - 2, 2.4) sub_dot(SPX + 4, SPY + 3, 1.8), "#D8D4BC", " opacity='" f2(MOONA) "'") }
}
# rain in front of everything: slanted streaks inside each tile, the dashes running down (frozen and invisible when dry)
function rain(d,   s, x) {
  s = ""; for (x = RWX[d] + 5; x < RWX[d] + 100; x += 12) s = s "M" f1(x) " " f1(RWY[d]) "L" f1(x - 18) " " f1(RWY[d] + 100)
  return "<path d='" s "' fill='none' stroke='#9FD8FF' stroke-width='1.1' stroke-linecap='round' stroke-dasharray='8 21' stroke-dashoffset='" f1(RAINY ? -170 * (T + AHEAD) + (d * 37) % 29 : 0) "' opacity='" (RAINY ? "0.5" : "0") "'/>"
}
function sunpos(k,   h, u) {
  h = MINUTES / 60
  if (k == "sun") u = (h - 6) / 13; else u = ((h + 24 - 19.5) % 24) / 11
  u = cl(u, -0.1, 1.1)
  SPX = 30 + (W - 60) * u; SPY = HORY - 60 - (HORY - 130) * sin(cl(u, 0, 1) * PI)
}

# An app's building: a dark tower with a neon edge, and its own details — every building carries every element, the
# ones its app does not have are invisible, so a building rising in place of another never changes the structure.
#   outline: eight points whatever its kind (tower, gable, steps, spire, dome, twins, slant)
#   roof: an antenna with a slowly blinking red light, a vent and its steam (the app's processor), and one of a water
#     tank, a dish or a billboard
#   facade: windows as dashed neon strokes in one of four patterns (squares, glass bands, slits, sparse lights) — their
#     length is the height, so the dashes stay put while it grows — and on some, thin floor lines
#   side: one of a vertical neon sign, air-conditioning boxes, a holographic ad panel; a neon strip on some
#   street: a door with a neon lintel, the neon sign with the app's name, the wet reflection, the traffic light before
#     the app in front (downtown)
function building(sl,   s,   rl, gl, dust, scf, bg, nw, ww, xx, a, h, g, x0, x1, xc, w, op, c, dk, win, act, typ, s1, y1, k, fs, nm, cpu, sm, lit, u, tl_, r, ne, n2, na, bl, sh, rf, sd, wv, bd, big, dash, tx, ty) {
  a = SAPP[sl]; h = SH[sl]; g = SG[sl]; xc = SX[sl]; w = a != "" ? AW[a] : 70; x0 = xc - w / 2; x1 = xc + w / 2
  op = cl(h / 30, 0, 1); act = a != "" && a == FRONT
  typ = a != "" ? ATYP[a] : 0; nm = a != "" ? ANAME[a] : "·"; cpu = a != "" ? ACPU[a] : 0
  # a roof piece stands only on a flat roof (the plain tower, the twins): on a slope, steps or a spire it would float
  rf = a != "" && (ATYP[a] == 0 || ATYP[a] == 5) ? AROOF[a] : 0; sd = a != "" ? ASIDE[a] : 0; wv = a != "" ? AWV[a] : 0; bd = a != "" ? ABAND[a] : 0
  big = h > 120 ? 1 : 0
  ne = a != "" ? ANEON[a] : "#35E8FF"; n2 = a != "" ? ANEON2[a] : "#FF2BD6"
  c = li(mixh(a != "" ? ACOL[a] : "#808080", "#0B0A16", 0.72), 3); dk = li(mixh(a != "" ? ACOL[a] : "#808080", "#06050C", 0.85), 3)
  na = NEONA * (act ? 1 : 0.8)
  lit = act || (a != "" && (a in AWORK) && T - AWORK[a] < 30) || (AWAKE && ALIT[a])
  # a flat battery: the lights fail, a window flickers now and then; plugged in, a wave of light runs through town
  if (BLACK) { lit = int(T * 1.3 + SX[sl] / 53) % 9 == 0; na *= 0.45 }
  if (T - WAVE0 >= 0 && T - WAVE0 < 4 && abs(xc - (T - WAVE0) / 3 * W) < 70) { lit = 1; na = 1 }
  win = lit ? mixh("#1A1830", a != "" ? AWINC[a] : "#35E8FF", cl(0.45 + 0.55 * NIGHT, 0, 1) * (act ? 1 : 0.85)) : li("#1C1A2E", 3)
  top = g - h
  if (typ == 1) k = "0 0 0,0 1 0,-4 1 0,35 1 24,74 1 0,70 1 0,70 0 0,70 0 0"
  else if (typ == 2) k = "0 0 0,0 1 -22,14 1 -22,14 1 0,56 1 0,56 1 -22,70 1 -22,70 0 0"
  else if (typ == 3) k = "0 0 0,0 1 0,31 1 0,35 1 34,39 1 0,70 1 0,70 0 0,70 0 0"
  else if (typ == 4) k = "0 0 0,0 1 0,10 1 10,35 1 16,60 1 10,70 1 0,70 0 0,70 0 0"
  else if (typ == 5) k = "0 0 0,0 1 0,31 1 0,31 1 -14,39 1 -14,39 1 0,70 1 0,70 0 0"
  else if (typ == 6) k = "0 0 0,0 1 -16,0 1 -16,35 1 -8,70 1 0,70 1 0,70 0 0,70 0 0"
  else k = "0 0 0,0 1 0,24 1 0,24 1 7,46 1 7,46 1 0,70 1 0,70 0 0"
  split(k, u, ",")
  rl = -1e9; for (r = 1; r <= 8; r++) { split(u[r], s1, " "); PX[r] = x0 + s1[1] * w / 70; PY[r] = g - h * s1[2] - s1[3] * cl(h / 60, 0, 1); if (s1[2] > 0 && PY[r] > rl) rl = PY[r] }
  if (rl < CLY0) for (r = 1; r <= 8; r++) PY[r] = cy(PY[r]); else for (r = 1; r <= 8; r++) if (PY[r] > CLY1) PY[r] = CLY1
  s = "<g opacity='" f2(op) "'>"
  s = s re(x0 + 8, g + 5, w - 16, 12, ne, " opacity='" f2(SQ[sl] ? 0 : (RAINY ? 0.08 : 0.04) * na) "'")
  # dust at its foot while it comes down, scaffolding round it while a new one goes up
  dust = SGONE[sl] && h > 0 ? 1 : 0; scf = SRISE[sl] && h < STGT[sl] ? 1 : 0
  s = s pth(sub_ell(x0 + 6, g - 6, 16, 9, 0) sub_ell(xc, g - 10, 22, 12, 0) sub_ell(x1 - 6, g - 6, 16, 9, 0), li("#8E86A6", 3), " opacity='" f2(0.75 * dust) "'")
  s = s strk(seg_(x0 - 5, cy(g), x0 - 5, cy(top - 4)) seg_(x1 + 5, cy(g), x1 + 5, cy(top - 4)), "#C98A1A", 1.6, " opacity='" scf "'")
  s = s "<path d='" vd(xc, g - 2, mn(top, g - 2)) "' fill='none' stroke='#C98A1A' stroke-width='" f1(w + 10) "' stroke-dasharray='1.6 16' opacity='" scf "'/>"
  s = s pg(8, "none", " stroke='" ne "' stroke-width='4' stroke-opacity='" f2(0.1 * na) "'")
  s = s pg(8, c, " stroke='" ne "' stroke-width='1.4' stroke-opacity='" f2(0.9 * na) "'")
  # floor lines: a stroke as wide as the building, dashed into thin horizontal lines
  s = s "<path d='" vd(xc, g - 46, mn(top + 18, g - 46)) "' fill='none' stroke='" dk "' stroke-width='" f1(w - 2) "' stroke-dasharray='1.4 17' opacity='" (bd ? 1 : 0) "'/>"
  # the roof: the antenna and its steady red light, a vent and its steam, then the app's roof piece
  bl = 1
  s = s re(xc + w * 0.22 - 1, top - 20, 2, 18, dk) ci(xc + w * 0.22, top - 21, 2, "#FF3B5C", " opacity='" (bl ? "0.95" : "0.3") "'")
  s = s re(x1 - 18, top - 11, 7, 9, dk)
  sm = cl(cpu / 30, 0, 1)
  s = s pth(sub_ell(x1 - 14 + 3 * sm, top - 20 - 4 * sm, 4 + 3 * sm, 3.4 + 2 * sm, 0) sub_ell(x1 - 10 + 6 * sm, top - 32 - 8 * sm, 3 + 5 * sm, 2.6 + 3 * sm, 0), li("#B9A8D8", 3), " opacity='" f2(0.7 * sm) "'")
  # a water tank on legs
  s = s re(x0 + 9, top - 16, 2, 16, li("#4A4660", 3), " opacity='" (rf == 1) "'") re(x0 + 19, top - 16, 2, 16, li("#4A4660", 3), " opacity='" (rf == 1) "'") rr_(x0 + 6, top - 30, 18, 15, 3, li("#2E2A40", 3), " stroke='" n2 "' stroke-width='1' stroke-opacity='" f2((rf == 1) * 0.6 * na) "' opacity='" (rf == 1) "'")
  # a dish looking at the sky
  s = s "<path d='M" f1(x0 + 8) " " f1(top - 14) "Q" f1(x0 + 16) " " f1(top - 4) " " f1(x0 + 26) " " f1(top - 18) "M" f1(x0 + 17) " " f1(top - 9) "L" f1(x0 + 17) " " f1(top) "' fill='none' stroke='" li("#8E8AA6", 3) "' stroke-width='2' stroke-linecap='round' opacity='" (rf == 2) "'/>"
  # a billboard on the roof: a glowing screen with scan lines
  s = s rr_(x0 + 3, top - 34, w - 6, 20, 2, n2, " opacity='" f2((rf == 3) * 0.28 * na) "' stroke='" n2 "' stroke-width='1.4'")
  s = s "<path d='M" f1(xc) " " f1(top - 32) "V" f1(top - 16) "' fill='none' stroke='" n2 "' stroke-width='" f1(w - 14) "' stroke-dasharray='2 3' opacity='" f2((rf == 3) * 0.55 * na) "'/>"
  s = s re(x0 + 10, top - 14, 2, 14, li("#4A4660", 3), " opacity='" (rf == 3) "'") re(x1 - 12, top - 14, 2, 14, li("#4A4660", 3), " opacity='" (rf == 3) "'")
  # the windows in the app's pattern
  y1 = top + 16; if (y1 > g - 50) y1 = g - 50
  nw = a != "" ? AWIN[a] : 3
  if (wv == 1) { ww = w - 16; dash = "3 5" } else if (wv == 2) { ww = nw == 4 ? 4 : 6; dash = "16 5" } else if (wv == 3) { ww = nw == 4 ? 5 : 7; dash = "4 13" } else { ww = nw == 4 ? 6 : (nw == 3 ? 8 : 10); dash = nw == 2 ? "4 6" : "5 7" }
  s = s "<path d='"
  for (r = 0; r < 4; r++) { xx = wv == 1 ? xc : (r < nw ? x0 + w * (r + 0.5) / nw : xc); s = s "M" f1(xx) " " f1(cy(g - 50)) "V" f1(cy((wv == 1 ? r == 0 : r < nw) ? y1 : g - 50)) }
  s = s "' stroke-dashoffset='" f1(abs(g - 50 - cy(g - 50))) "' fill='none' stroke='" win "' stroke-width='" ww "' stroke-dasharray='" dash "'/>"
  # the side: a vertical neon sign with glyphs, air-conditioning boxes, or a holographic ad panel
  ty = top + 22; tx = x1 - 3
  s = s rr_(tx, ty, 11, mx(mn(70, h - 90), 1), 2, "#0E0D18", " stroke='" n2 "' stroke-width='1.2' stroke-opacity='" f2(na) "' opacity='" ((sd == 1) * big) "'")
  s = s "<path d='M" f1(tx + 5.5) " " f1(ty + 5) "V" f1(ty + mx(mn(70, h - 90) - 5, 5)) "' fill='none' stroke='" n2 "' stroke-width='5' stroke-dasharray='3 4' opacity='" f2((sd == 1) * big * na) "'/>"
  s = s "<path d='" vd(x0 + 3, g - 60, mn(top + 24, g - 60)) "' fill='none' stroke='" li("#4A4660", 3) "' stroke-width='6' stroke-dasharray='5 22' opacity='" ((sd == 2) * big) "'/>"
  s = s rr_(x0 + 5, top + 26, w * 0.52, 24, 2, n2, " opacity='" f2((sd == 3) * big * 0.3 * na) "' stroke='" n2 "' stroke-width='1.2'")
  s = s "<path d='M" f1(x0 + 5 + w * 0.26) " " f1(top + 29) "V" f1(top + 47) "' fill='none' stroke='#FFFFFF' stroke-width='" f1(w * 0.44) "' stroke-dasharray='1.5 4' opacity='" f2((sd == 3) * big * 0.35 * na) "'/>"
  # a neon strip down the other side
  sh = typ % 2 == 0 && h > 110 && sd != 1 ? 1 : 0
  s = s rrc(x0 + 3, top + 12, 4, mx(h - 70, 1), 2, n2, " opacity='" f2(sh * na) "'") rrc(x0 + 1, top + 10, 8, mx(h - 66, 1), 4, n2, " opacity='" f2(0.22 * sh * na) "'")
  s = s re(xc - 7, g - 17, 14, 17, dk) re(xc - 9, g - 19, 18, 2, ne, " opacity='" f2(0.8 * na) "'")
  # the app's Dock badge as a hologram at the roof's corner
  bg = a != "" ? ABADGE[a] : 0
  s = s ringc(x1 - 6, top + 8, 11, n2, n2, 1.5, " fill-opacity='0.3' opacity='" f2(bg > 0 ? na : 0) "'")
  s = s "<text x='" f1(x1 - 6) "' y='" f1(top + 12.5) "' font-size='12' font-weight='bold' text-anchor='middle' fill='#FFFFFF' opacity='" f2(bg > 0 ? 1 : 0) "'>" (bg > 99 ? "99+" : (bg > 0 ? bg : "0")) "</text>"
  s = s rr_(x0 + 3, g - 42, w - 6, 18, 4, act ? mixh("#0E0D18", ne, 0.3) : "#0E0D18", " stroke='" ne "' stroke-width='" (act ? "2.2" : "1.2") "' stroke-opacity='" f2(na) "'")
  # a glitch: for a moment the sign takes another neon, jumps a little and flickers
  gl = T < SGL[sl]; if (gl) { ne = GLC; na = int(T * 4) % 2 ? 1 : 0.35 }
  fs = fitsize(nm)
  s = s "<text x='" f1(xc + (gl ? 2.5 * (int(T * 4) % 2 ? 1 : -1) : 0)) "' y='" f1(g - 28.5) "' font-size='" fs "' font-weight='bold' text-anchor='middle' fill='" (act ? "#FFFFFF" : mixh("#FFFFFF", ne, 0.55)) "'>" nm "</text>"
  tl_ = act && SQ[sl] == 0 && SX[sl] > 160 ? 1 : 0
  s = s re(x0 - 4, g - 34, 2.4, 34, "#1A1924", " opacity='" tl_ "'") rr_(x0 - 7, g - 44, 8, 14, 2, "#1A1924", " opacity='" tl_ "'")
  s = s ci(x0 - 3, g - 41, 2.2, RED ? "#FF3B5C" : "#3A1420", " opacity='" tl_ "'") ci(x0 - 3, g - 33.5, 2.2, RED ? "#123A2A" : "#39FF88", " opacity='" tl_ "'")
  return s "</g>"
}
# the sign's font: the name fits 62 units (a glyph is about 0.58 em)
function fitsize(nm,   n) { n = length(nm); if (n < 1) n = 1; return cl(int(62 / (n * 0.6) * 2) / 2, 9.5, 15) }

# ---------------------------------------------------------------- apps: which ones, where
# Every app's look from its bundle id: a kind of building and a colour (well-known apps in their own colour).
function appdeck(   k) {
  split("#E07A5F #3D5A80 #81B29A #E9B872 #9C6ADE #5FA8D3 #EF8354 #6D9DC5 #C06C84 #4F7CAC #D4A373 #7A9E7E", PALB, " ")
  BRAND["com.apple.dt.Xcode"] = "#1C7CF4"; BRAND["com.apple.Terminal"] = "#3A3A40"; BRAND["ru.keepcoder.Telegram"] = "#2AABEE"
  BRAND["company.thebrowser.Browser"] = "#F25C7C"; BRAND["com.google.Chrome"] = "#E8B32E"; BRAND["com.apple.finder"] = "#4FA3F7"
  BRAND["com.apple.Music"] = "#FA2D48"; BRAND["com.hnc.Discord"] = "#5865F2"; BRAND["com.linear"] = "#5E6AD2"; BRAND["md.obsidian"] = "#7C3AED"
  BRAND["com.anthropic.claudefordesktop"] = "#D97757"; BRAND["com.openai.codex"] = "#10A37F"; BRAND["com.openai.chat"] = "#10A37F"
  BRAND["com.tinyspeck.slackmacgap"] = "#611F69"; BRAND["com.figma.Desktop"] = "#A259FF"; BRAND["us.zoom.xos"] = "#2D8CFF"
  BRAND["com.postmanlabs.mac"] = "#FF6C37"; BRAND["com.spotify.client"] = "#1DB954"; BRAND["com.apple.Safari"] = "#1E90FF"
  BRAND["com.microsoft.VSCode"] = "#007ACC"; BRAND["com.todesktop.230313mzl4w4u92"] = "#2B2B2B"; BRAND["com.mitchellh.ghostty"] = "#3B3F58"
  for (k = 32; k < 127; k++) ORD_[sprintf("%c", k)] = k
  split("#35E8FF #FF2BD6 #FFB800 #7CFF4F #9D4DFF #FF4D6D", NEONP, " "); split("#6FF3FF #FF7BE8 #FFD37A", WINP, " ")
}
# An app's neon: its own colour made to glow (a dark brand colour takes a neon of the palette), a second neon for its
# strip, and the colour of its lit windows.
function neon(a, hsh,   c) {
  c = ACOL[a]; rgb(c)
  if (CR + CG + CB < 260 || (CR < 90 && CG < 90)) c = NEONP[hsh % 6 + 1]
  else c = mixh(c, "#FFFFFF", 0.18)
  ANEON[a] = c; ANEON2[a] = NEONP[(hsh + 3) % 6 + 1]; AWINC[a] = WINP[int(hsh / 7) % 3 + 1]
}
function hash(s,   i, h) { h = 7; for (i = 1; i <= length(s); i++) h = (h * 31 + ORD_[substr(s, i, 1)]) % 1000003; return h }
function shortname(n,   a, k) {
  if (length(n) <= 9) return n
  k = split(n, a, " ")
  if (k == 1 && length(n) <= 11) return n
  if (k > 1 && length(a[1]) <= 9 && a[1] != "Google" && a[1] != "Microsoft") return a[1]
  if (k > 1 && length(a[k]) <= 9) return a[k]
  return substr(n, 1, 8) "…"
}
# A new list of apps (most recent first): known ones keep their building; the first NSLOT get one, a new app takes a
# free slot (downtown first, left to right), and an app pushed out of the list sinks to make room.
function commit(   i, a, s, want, hsh, h) {
  for (i = 1; i <= NA; i++) {
    a = APPB[i]
    # an app without a colour of its own: a dark body under a bright neon of NEONP (neon()) — the look checked on an
    # old iPad; a colour of PALB would turn its neon pastel
    if (!(a in ACOL)) { hsh = hash(a); ACOL[a] = (a in BRAND) ? BRAND[a] : ""; ATYP[a] = int(hsh / 12) % 7; AROOF[a] = int(hsh / 7) % 4; ASIDE[a] = int(hsh / 29) % 4; AWV[a] = int(hsh / 113) % 4; ABAND[a] = int(hsh / 41) % 2; ALIT[a] = int(hsh / 60) % 3 != 0; neon(a, hsh); AW[a] = 54 + 4 * (int(hsh / 180) % 6); AWIN[a] = 2 + int(hsh / 1080) % 3 }
    ANAME[a] = shortname(LN[i]); ARSS[a] = LR_[i]; RANK[a] = i
    # its processor, in steps (the steam), and when it last worked (its windows stay lit for a while after)
    ACPU[a] = LC[i] > 30 ? 30 : (LC[i] > 12 ? 20 : (LC[i] > 3 ? 10 : 0)); if (LC[i] > 2) AWORK[a] = T
    # a badge that grew: a courier flies to the building (once the building stands)
    if (LBG[i] > ABADGE[a] && (a in SLOTOF) && CQN < 4 && BADGESEEN) CQ[++CQN] = SLOTOF[a]
    ABADGE[a] = LBG[i]
  }
  # who keeps or gets a building
  delete want
  for (i = 1; i <= NA && i <= NSLOT; i++) want[APPB[i]] = 1
  for (s = 1; s <= NSLOT; s++) { a = SAPP[s]; if (a != "" && !(a in want)) SGONE[s] = 1; else SGONE[s] = 0 }
  for (i = 1; i <= NA && i <= NSLOT; i++) {
    a = APPB[i]; if (a in SLOTOF && SAPP[SLOTOF[a]] == a) continue
    for (s = 1; s <= NSLOT; s++) if (SAPP[s] == "" ) break
    if (s > NSLOT) continue
    SAPP[s] = a; SLOTOF[a] = s; SH[s] = 0; SGONE[s] = 0; SRISE[s] = BADGESEEN
  }
  MLO = 1e9; MHI = 0
  for (s = 1; s <= NSLOT; s++) { a = SAPP[s]; if (a != "" && !SGONE[s]) { MLO = mn(MLO, log(ARSS[a] + 1)); MHI = mx(MHI, log(ARSS[a] + 1)) } }
  for (s = 1; s <= NSLOT; s++) {
    a = SAPP[s]; h = a == "" || SGONE[s] ? 0 : height_of(s, a)
    # memory drifts all the time: a standing building changes its height only for a real change
    if (h == 0 || STGT[s] == 0 || abs(h - STGT[s]) >= 20) STGT[s] = h
  }
  BADGESEEN = 1
}
# its height: the app's memory, from one storey to the top of the quarter
# its height: the app's memory among the apps in town — the hungriest the tallest, the lightest one storey
function height_of(s, a,   f) { f = MLO < MHI ? (log(ARSS[a] + 1) - MLO) / (MHI - MLO) : 0.5; f = 0.12 + 0.88 * cl(f, 0, 1); return int((70 + (SMAX[s] - 70) * f) / 4 + 0.5) * 4 }
function grow(dt,   s, d) {
  for (s = 1; s <= NSLOT; s++) {
    d = STGT[s] - SH[s]
    if (d > 0) SH[s] = mn(STGT[s], SH[s] + 90 * dt); else if (d < 0) SH[s] = mx(STGT[s], SH[s] - 120 * dt)
    SH[s] = int(SH[s] + 0.5); if (SH[s] >= STGT[s]) SRISE[s] = 0
    if (SH[s] == 0 && SGONE[s]) { delete SLOTOF[SAPP[s]]; SAPP[s] = ""; SGONE[s] = 0 }
  }
}

# ---------------------------------------------------------------- the cast: cars, the train, people, clouds
function newm(k, layer) { NM++; MK[NM] = k; ML[NM] = layer; return NM }
function cast(   j, m) {
  NM = 0
  for (j = 1; j <= 3; j++) CLOUD[j] = newm("cloud", 1)
  TRAIN = newm("train", 3)
  for (j = 1; j <= NCAR; j++) { m = CAR[j] = newm("car", 8); CARC[m] = j }
  for (j = 1; j <= NPPL; j++) { m = PPL[j] = newm("ppl", 7) }
  for (j = 1; j <= NFLY; j++) { m = FLY[j] = newm("fly", 2) }
  SHIP = newm("ship", 6)
  for (j = 1; j <= NADR; j++) { m = ADR[j] = newm("adrone", 6) }
  CRANE = newm("crane", 5); COUR = newm("courier", 8)
  KAT = newm("kat", 5)
  for (j = 1; j <= NFW; j++) { m = FW[j] = newm("fw", 8) }
  parks()
  CAST = 1
}
function parks(   m) { PK = 1; for (m = 1; m <= NM; m++) PARK[m] = draw(m, 0); PK = 0 }
function draw(m, op,   k) {
  k = MK[m]
  if (k == "cloud") return gin(X[m] + CV[m] * AHEAD, Y[m], 0, op) pth(PK ? ELLPK ELLPK ELLPK : sub_ell(-18, 2, 16, 10, 0) sub_ell(0, -4, 18, 13, 0) sub_ell(18, 2, 15, 10, 0), mixh(SKY2, "#FFFFFF", 0.12), " opacity='0.45'") gout()
  if (k == "fly") return d_fly(m, op)
  if (k == "adrone") return d_adrone(m, op)
  if (k == "ship") return d_ship(op)
  if (k == "crane") return d_crane(op)
  if (k == "courier") return d_courier(op)
  if (k == "kat") return d_kat(op)
  if (k == "fw") return d_fw(m, op)
  if (k == "car") return d_car(m, op)
  if (k == "train") return d_train(op)
  if (k == "ppl") return d_ppl(m, op)
}
function d_car(m, op,   d, s, c) {
  d = D[m]; c = li(CARCOL[m], 3)
  s = gin(X[m], Y[m], 0, op)
  s = s re(-13, -2, 26, 2.4, CARNEON[m], " opacity='" f2(0.8 * NEONA) "'")
  PX[1] = -15; PY[1] = -3; PX[2] = -15; PY[2] = -8; PX[3] = -8 * d - 1; PY[3] = -9; PX[4] = -5 * d; PY[4] = -14; PX[5] = 6 * d; PY[5] = -14; PX[6] = 10 * d; PY[6] = -9; PX[7] = 15; PY[7] = -8; PX[8] = 15; PY[8] = -3
  s = s pg(8, c)
  PX[1] = -4 * d; PY[1] = -12.5; PX[2] = 5 * d; PY[2] = -12.5; PX[3] = 8 * d; PY[3] = -9.5; PX[4] = -6 * d; PY[4] = -9.5
  s = s pg(4, "#6FF3FF", " opacity='0.55'")
  s = s pth(sub_dot(14 * d, -6, 1.8), "#FFF3C4")
  s = s pth(sub_dot(-14 * d, -6, 1.5), "#FF3B5C")
  s = s rr_(-4, -18, 8, 3.4, 1, "#FFD24A", " opacity='" ((QUIET && m % 2) ? f2(0.95) : 0) "'")
  return s gout()
}
# A flying car: a sleek capsule, its light, and a trail of light behind it.
function d_fly(m, op,   d, s) {
  d = D[m]
  s = gin(X[m], Y[m], 0, op)
  s = s strk(PK ? "M0 0L0 0" : seg_(-d * 12, 0, -d * 46, 1), FLYC[m], 2, " opacity='" f2(0.45 * NEONA) "'")
  s = s pth(PK ? ELLPK : sub_ell(0, 0, 13, 4.2, 0), li("#262436", 3))
  s = s pth(PK ? "M0 0 0 0 0 0 0 0 0 0 0 0Z" ELLPK : sub_dot(d * 11, 0, 1.8) sub_ell(-d * 2, -2.5, 5, 2, 0), FLYC[m])
  return s gout()
}
# The train: a maglev — a locomotive and three carriages, dark with neon stripes; carriages the traffic does not need
# are invisible.
function d_train(op,   d, s, k, x, w) {
  d = TD; s = gin(X[TRAIN], RAILY - 3, 0, op); w = 40
  for (k = 0; k < 4; k++) {
    x = -d * k * (w + 4)
    s = s rr_(x - w / 2, -20, w, 16, 5, li("#23212F", 3), " opacity='" (k < TCARS ? 1 : 0) "'")
    s = s (PK ? "<path d='M0 0L0 0' fill='none' stroke='#000' stroke-dasharray='1 1'/>" : "<path d='" seg_(x - w / 2 + 6, -13, x + w / 2 - 6, -13) "' fill='none' stroke='" (TD < 0 ? "#6FF3FF" : "#FF7BE8") "' stroke-width='4' stroke-dasharray='5 3' opacity='" (k < TCARS ? f2(0.9 * NEONA) : 0) "'/>")
    s = s re(x - w / 2 + 2, -3.5, w - 4, 1.8, TD < 0 ? "#35E8FF" : "#FF2BD6", " opacity='" (k < TCARS ? f2(0.9 * NEONA) : 0) "'")
  }
  return s gout()
}
# A passer-by: a dark figure; in the rain, under a glowing umbrella.
function d_ppl(m, op,   s, ph, c) {
  ph = PLEG[m]; c = PPLC[m]
  s = gin(X[m], Y[m], 0, op)
  s = s strk(PK ? "M0 0L0 0M0 0L0 0" : seg_(-1.5, -9, -1.5 - 2.5 * ph, 0) seg_(1.5, -9, 1.5 + 2.5 * ph, 0), "#0E0D18", 2)
  s = s pth(PK ? "M0 0 0 0 0 0 0 0Z" ELLPK : "M-3.5 -9L3.5 -9L2.6 -18L-2.6 -18Z" sub_ell(0, -21.5, 3, 3.2, 0), "#1A1826")
  s = s pth(PK ? "M0 0Q0 0 0 0Z" : "M-9 -26Q0 -38 9 -26Z", c, " opacity='" (RAINY ? f2(0.9 * NEONA) : 0) "'")
  return s gout()
}
function bands(   m, k) {
  for (m = 1; m <= NM; m++) {
    k = MK[m]
    if (k == "cloud") { BX0[m] = -130; BX1[m] = W + 60; BY0[m] = 10; BY1[m] = tt(1) + 20 }
    else if (k == "train") { BX0[m] = -250; BX1[m] = W + 250; BY0[m] = RAILY - 28; BY1[m] = RAILY + 2 }
    else if (k == "car") { BX0[m] = -60; BX1[m] = W + 60; BY0[m] = DY + 2; BY1[m] = H }
    else if (k == "fly") { BX0[m] = -80; BX1[m] = W + 80; BY0[m] = FY0[m] - 8; BY1[m] = FY0[m] + 8 }
    else if (k == "adrone") { BX0[m] = -80; BX1[m] = W + 80; BY0[m] = SHY - 40; BY1[m] = SHY + 40 }
    else if (k == "ship") { BX0[m] = -80; BX1[m] = W + 80; BY0[m] = SHY - 26; BY1[m] = SHY + 34 }
    else if (k == "crane" || k == "courier" || k == "fw" || k == "kat") { BX0[m] = -80; BX1[m] = W + 80; BY0[m] = 0; BY1[m] = DY + 2 }
    else { BX0[m] = -30; BX1[m] = W + 30; BY0[m] = DY - 28; BY1[m] = DY + 2 }
  }
}
function mbox(m,   k) {
  k = MK[m]
  if (k == "cloud") { B0X[m] = X[m] - 36; B1X[m] = X[m] + 36; B0Y[m] = Y[m] - 19; B1Y[m] = Y[m] + 14; return }
  if (k == "train") { B0X[m] = TD > 0 ? X[m] - 3 * 44 - 22 : X[m] - 22; B1X[m] = TD > 0 ? X[m] + 22 : X[m] + 3 * 44 + 22; B0Y[m] = RAILY - 26; B1Y[m] = RAILY; return }
  if (k == "ship") { B0X[m] = X[m] - 60; B1X[m] = X[m] + 60; B0Y[m] = Y[m] - 20; B1Y[m] = Y[m] + 31; return }
  if (k == "adrone") { B0X[m] = X[m] - 10; B1X[m] = X[m] + 10; B0Y[m] = Y[m] - 6; B1Y[m] = Y[m] + 4; return }
  if (k == "crane") { B0X[m] = X[m] - 26; B1X[m] = X[m] + 50; B0Y[m] = Y[m] - 86; B1Y[m] = Y[m] + 1; return }
  if (k == "kat") { B0X[m] = X[m] - 16; B1X[m] = X[m] + 16; B0Y[m] = Y[m] - 22; B1Y[m] = Y[m] + 2; return }
  if (k == "courier") { B0X[m] = X[m] - 14; B1X[m] = X[m] + 14; B0Y[m] = Y[m] - 9; B1Y[m] = Y[m] + 11; return }
  if (k == "fw") { B0X[m] = X[m] - 36; B1X[m] = X[m] + 36; B0Y[m] = Y[m] - 36; B1Y[m] = Y[m] + 56; return }
  if (k == "fly") { B0X[m] = D[m] > 0 ? X[m] - 48 : X[m] - 15; B1X[m] = D[m] > 0 ? X[m] + 15 : X[m] + 48; B0Y[m] = Y[m] - 6; B1Y[m] = Y[m] + 6; return }
  if (k == "car") { B0X[m] = X[m] - 17; B1X[m] = X[m] + 17; B0Y[m] = Y[m] - 18; B1Y[m] = Y[m] + 1; return }
  B0X[m] = X[m] - 6; B1X[m] = X[m] + 6; B0Y[m] = Y[m] - 26; B1Y[m] = Y[m] + 1
}
function place_cast(   m, j) {
  for (m = 1; m <= NM; m++) { ACT[m] = 0; OP[m] = 0; VX[m] = 0; VY[m] = 0 }
  for (j = 1; j <= 3; j++) { m = CLOUD[j]; ACT[m] = 1; OP[m] = 1; X[m] = W * (j - 0.5) / 3 + rr(-30, 30); Y[m] = 30 + 20 * j; CV[m] = rr(2.5, 4.5) }
  split("#2A2838 #1E2A38 #382434 #242432 #2E2438 #20303A", CC, " ")
  for (j = 1; j <= NCAR; j++) { m = CAR[j]; D[m] = j % 2 ? 1 : -1; Y[m] = D[m] > 0 ? DY + 13 : DY + 24; X[m] = rr(0, W); CARCOL[m] = CC[j]; CARNEON[m] = NEONP[j]; CSP[m] = 0; CJ[m] = 0 }
  # flying cars: lanes in the sky above the town
  # two in the sky above everything, two (on a tall page) in the canyon between the quarters
  FLYB = UP >= 0 ? tt(UP - 1) : tt(DOWN - 2)
  for (j = 1; j <= NFLY; j++) {
    m = FLY[j]; D[m] = j % 2 ? 1 : -1; X[m] = rr(0, W); FLYC[m] = NEONP[(j * 2) % 6 + 1]; FJ[m] = 0; FV[m] = rr(45, 75)
    if (UP >= 0 && j == 3) Y[m] = tt(UP + 1) + 50; else Y[m] = 26 + (FLYB - 36) * (UP >= 0 ? (j - 0.5) / 2 : (j - 0.5) / NFLY)
    FNEXT[m] = T + rr(0, 6); ACT[m] = 0
    FY0[m] = Y[m]
  }
  split("#E07A5F #5FA8D3 #F2C94C #9C6ADE #81B29A", PCC, " ")
  for (j = 1; j <= NPPL; j++) { m = PPL[j]; X[m] = rr(20, W - 20); Y[m] = DY - 2; PD[m] = rnd() < 0.5 ? 1 : -1; PPLC[m] = PCC[j]; PLEG[m] = 0 }
  TX_ = 0; ACT[TRAIN] = 0; TNEXT = T + 3
}

# ---------------------------------------------------------------- town life
function step(dt,   hh, j, m, n, want, jam, v, lead, gap, k, x, stop) {
  grow(dt)
  # traffic: more cars when the Mac works harder, a jam when it is very busy
  want = 1 + int(cl((LOAD - 0.25) / 0.8, 0, 1) * (NCAR - 1) + 0.5); jam = cl((LOAD - 0.75) / 0.5, 0, 1)
  # the town's own rhythm: rush hours on weekdays, quiet nights and weekends
  hh = MINUTES / 60; RUSH = WDAY <= 5 && ((hh >= 8 && hh < 10) || (hh >= 17.5 && hh < 19.5)); QUIET = hh < 6 || WDAY >= 6
  if (RUSH) want = mn(NCAR, want + 3); else if (QUIET) want = mx(1, want - 1)
  RED = int(T / 6) % 2 == 0
  for (j = 1; j <= NCAR; j++) {
    m = CAR[j]
    if (!ACT[m] && j <= want && CJ[m] == 0) { ACT[m] = 1; OP[m] = 0; CJ[m] = 2; X[m] = D[m] > 0 ? -75 : W + 75; CSP[m] = 50 }
    v = (58 + 10 * (j % 3)) * (1 - 0.7 * jam)
    # the car in front in the same lane, and the red light before the app in front
    lead = 1e9
    for (k = 1; k <= NCAR; k++) { n = CAR[k]; if (n == m || !ACT[n] || D[n] != D[m]) continue; gap = (X[n] - X[m]) * D[m]; if (gap > 0 && gap < lead) lead = gap }
    stop = 1e9
    # (only with road enough before it: a light at the very edge would stop the cars as they come in)
    if (RED && D[m] > 0 && FRONTX > 160) { gap = (FRONTX - 40) - X[m]; if (gap > -2) stop = gap }
    # the speed it wants: nought close behind a car or at the red light, gently less as it nears them
    if (lead < 38 || stop < 16) v = 0; else v *= cl(mn((lead - 38) / 50, (stop - 16) / 70), 0, 1)
    # and the speed it has: it brakes and speeds up gradually, never in one step
    if (v < CSP[m]) CSP[m] = mx(v, CSP[m] - 140 * dt); else CSP[m] = mn(v, CSP[m] + 70 * dt)
    X[m] += D[m] * CSP[m] * dt; VX[m] = D[m] * CSP[m]
    # off the street: invisible for a frame there, then at the other end, then on again (the invisible jump)
    if (CJ[m] == 1) { CJ[m] = 2; X[m] = D[m] > 0 ? -75 : W + 75; if (j > want) { ACT[m] = 0; CJ[m] = 0 } }
    else if (CJ[m] == 2) { CJ[m] = 0; OP[m] = 1 }
    # past the far end in its own direction (a car coming in from beyond the near end is not leaving)
    else if (ACT[m] && ((D[m] > 0 && X[m] > W + 45) || (D[m] < 0 && X[m] < -45))) { CJ[m] = 1; OP[m] = 0 }
  }
  # people on the pavement while you are at the Mac (fewer at night), none while you are away
  n = AWAKE ? (RUSH ? NPPL : (NIGHT > 0.6 ? 1 : NPPL - 1)) : 0
  for (j = 1; j <= NPPL; j++) {
    m = PPL[j]
    if (j <= n && !ACT[m]) { ACT[m] = 1; OP[m] = 1 }
    if (j > n && ACT[m] && PJ[m] == 0) { OP[m] = 0; PJ[m] = 1 }
    else if (PJ[m] == 1) { ACT[m] = 0; PJ[m] = 0 }
    if (!ACT[m]) continue
    X[m] += PD[m] * 11 * dt; VX[m] = PD[m] * 11; PLEG[m] = int(T * 2 + j) % 2 ? 1 : -1
    if (X[m] < 15) PD[m] = 1; if (X[m] > W - 15) PD[m] = -1
    if (rnd() < dt / 25) PD[m] = -PD[m]
  }
  train(dt); clouds(dt); flyers(dt); airship(dt); drones(dt); crane(dt); coffee(); courier(dt); fireworks(dt); rare_events(dt)
}
# The train carries the network: coming in (downloading) from the right, going out (uploading) to the left; its
# length is the traffic.
function train(dt,   v) {
  if (!ACT[TRAIN]) {
    if (T > TNEXT && NETR > 20) { ACT[TRAIN] = 1; OP[TRAIN] = 0; TJ = 1; TD = NETIN >= NETOUT ? -1 : 1; X[TRAIN] = TD > 0 ? -200 : W + 200; TCARS = NETR > 3000 ? 4 : (NETR > 600 ? 3 : (NETR > 100 ? 2 : 1)) }
    return
  }
  if (TJ == 1) { TJ = 0; OP[TRAIN] = 1 }
  v = 80 + cl(NETR / 5000, 0, 1) * 70
  X[TRAIN] += TD * v * dt; VX[TRAIN] = TD * v
  if ((TD > 0 && X[TRAIN] > W + 200) || (TD < 0 && X[TRAIN] < -200)) { ACT[TRAIN] = 0; OP[TRAIN] = 0; TNEXT = T + (NETR > 300 ? 2 : 8) }
}
# Flying cars cross the sky, more while you are at the Mac; each leaves through the invisible jump and comes back.
# Now and then, not all the time: after crossing, a car waits a while (longer while you are away) before the next pass.
function flyers(dt,   j, m) {
  for (j = 1; j <= NFLY; j++) {
    m = FLY[j]
    if (!ACT[m] && FJ[m] == 0 && T > FNEXT[m]) { ACT[m] = 1; OP[m] = 0; FJ[m] = 2; X[m] = D[m] > 0 ? -70 : W + 70; FV[m] = rr(45, 75) }
    if (!ACT[m]) continue
    X[m] += D[m] * FV[m] * dt; VX[m] = D[m] * FV[m]
    if (FJ[m] == 1) { ACT[m] = 0; FJ[m] = 0; FNEXT[m] = T + (AWAKE ? rr(2, 8) : rr(30, 60)); D[m] = -D[m] }
    else if (FJ[m] == 2) { FJ[m] = 0; OP[m] = 1 }
    else if ((D[m] > 0 && X[m] > W + 65) || (D[m] < 0 && X[m] < -65)) { FJ[m] = 1; OP[m] = 0 }
  }
}
function clouds(dt,   j, m) {
  for (j = 1; j <= 3; j++) {
    m = CLOUD[j]; X[m] += CV[m] * dt; VX[m] = CV[m]
    if (CJ[m] == 1) { CJ[m] = 2; X[m] = -90 } else if (CJ[m] == 2) { CJ[m] = 0; OP[m] = 1 }
    else if (X[m] > W + 40) { CJ[m] = 1; OP[m] = 0 }
  }
}

# ---------------------------------------------------------------- taps: a building switches to its app
function tap(id,   s, x, y) {
  x = TX[id] + 50; y = TY[id] + 50
  for (s = 1; s <= NSLOT; s++) if (SAPP[s] != "" && !SGONE[s] && abs(x - SX[s]) < 50 && y <= SG[s] + 26 && y >= SG[s] - SH[s] - 60) { OPENB = SAPP[s]; return }
  if (y < DY - 30) firework(x, y - 10)
}

# ---------------------------------------------------------------- the extras: AI tower, crane, couriers, fireworks, clock
# The AI airship: while Claude Code or Codex runs, a neon airship cruises over the town, to and fro, turning at the
# ends — in front of everything, so no building hides it; brighter while an agent works, gone when none runs. Its
# screen shows how many sessions run; their drones circle it.
function ai_place() { SHY = PORT ? tt(1) + 40 : tt(1) + 22; SHX0 = 80; SHX1 = W - 80; if (!SHX) SHX = W * 0.4; if (!SHD) SHD = 1; SHX = cl(SHX, SHX0, SHX1) }
# What the agents do, steadied: working if one was busy at any reading in the last 20 s, sessions the most seen in the
# last 10 s — Claude Code starts and ends helper processes all the time, and the airship must not flicker with them.
function agents_steady(   want) {
  if (AGBUSY_) AGBT = T
  if (AGENTS_ >= AGN || T - AGNT > 10) { AGN = AGENTS_; AGNT = T }
  AGENTS = AGN; AGBUSY = AGENTS > 0 && T - AGBT < 20
  want = AGENTS > 0 ? (AGBUSY ? 1 : 0.55) : 0
  if (TOWA < want) TOWA = mn(want, TOWA + 0.15); else if (TOWA > want) TOWA = mx(want, TOWA - 0.15)
  TOWA = int(TOWA * 20 + 0.5) / 20
}
function airship(dt) {
  if (int(T) != AGSEC) { AGSEC = int(T); agents_steady() }
  SHX += SHD * 14 * dt
  if (SHX > SHX1) { SHX = SHX1; SHD = -1 } else if (SHX < SHX0) { SHX = SHX0; SHD = 1 }
  # it turns over a couple of seconds (its tail swings round through a head-on view), never in one frame
  if (!SHDD) SHDD = SHD
  SHDD += cl(SHD - SHDD, -0.35 * dt / 0.5, 0.35 * dt / 0.5)
  X[SHIP] = SHX; Y[SHIP] = SHY + 3 * sin(T * 0.7); VX[SHIP] = SHD * 14; VY[SHIP] = 0
  if (TOWA > 0) { if (!ACT[SHIP]) { ACT[SHIP] = 1; OP[SHIP] = 0 } else OP[SHIP] = TOWA }
  else if (ACT[SHIP]) { if (OP[SHIP] > 0) OP[SHIP] = 0; else ACT[SHIP] = 0 }
}
function d_ship(op,   d, s, n) {
  d = SHDD; n = AGENTS > 99 ? 99 : AGENTS
  s = gin(X[SHIP], Y[SHIP], 0, op)
  s = s el(0, 24, 40, 5, "#FF2BD6", " opacity='0.28'")
  PX[1] = -d * 38; PY[1] = -4; PX[2] = -d * 56; PY[2] = -17; PX[3] = -d * 51; PY[3] = 0; PX[4] = -d * 56; PY[4] = 17; PX[5] = -d * 38; PY[5] = 4
  # (the parked twins of stroked shapes carry a stroke too: the phone counts the paint as structure)
  s = s (PK ? "<polygon points='0,0 0,0 0,0 0,0 0,0' stroke='#000'/>" : pg(5, li("#1A1830", 3), " stroke='#35E8FF' stroke-width='1.2'"))
  s = s (PK ? "<path d='" ELLPK "' fill='none' stroke='#000'/>" : pth(sub_ell(0, 0, 48, 15, 0), "none", " stroke='#35E8FF' stroke-width='5' stroke-opacity='0.15'"))
  s = s (PK ? "<path d='" ELLPK "' stroke='#000'/>" : pth(sub_ell(0, 0, 48, 15, 0), li("#1A1830", 3), " stroke='#35E8FF' stroke-width='1.4'"))
  s = s (PK ? "<rect rx='1' stroke='#000'/>" : rr_(-14, 14, 28, 8, 3, li("#23212F", 3), " stroke='#6FF3FF' stroke-width='0.8'"))
  s = s (PK ? "<path d='M0 0L0 0' fill='none' stroke='#000' stroke-dasharray='1 1'/>" : "<path d='M-10 18H10' fill='none' stroke='#FFD37A' stroke-width='3' stroke-dasharray='3 3'/>")
  s = s (PK ? "<rect rx='1' stroke='#000'/>" : rr_(-20, -8, 40, 15, 3, "#0E0D18", " stroke='#FF2BD6' stroke-width='1'"))
  s = s "<text x='0' y='3.5' font-size='11' font-weight='bold' text-anchor='middle' fill='#FF9BEA'>" (PK ? "0" : n " AI") "</text>"
  s = s ci(d * 47, 0, 2, "#FF3B5C")
  return s gout()
}
# One drone a session, up to ten, on three rings round the airship; the drones of a ring fly in a chain, evenly spaced.
function drones(dt,   j, m, n, ph, r, ry, ring, k, cnt, w) {
  n = ACT[SHIP] ? mn(AGENTS, NADR) : 0
  for (j = 1; j <= NADR; j++) {
    m = ADR[j]; ring = (j - 1) % 3; k = int((j - 1) / 3)
    cnt = int((n - 1 - ring) / 3) + 1; if (cnt < 1) cnt = 1
    w = 0.34 - 0.06 * ring; r = 62 + 16 * ring; ry = 12 + 7 * ring
    ph = T * w * (ring == 1 ? -1 : 1) + 2 * PI * k / cnt + ring * 1.3
    X[m] = X[SHIP] + r * cos(ph); Y[m] = Y[SHIP] + ry * sin(ph); VX[m] = VX[SHIP] - r * w * (ring == 1 ? -1 : 1) * sin(ph); D[m] = 0
    if (j <= n) { if (!ACT[m]) { ACT[m] = 1; OP[m] = 0 } else OP[m] = 1 }
    else if (ACT[m]) { if (OP[m] > 0) OP[m] = 0; else ACT[m] = 0 }
  }
}
# A drone: its body and both rotor arms in one shape, and its light.
function d_adrone(m, op,   s) {
  s = gin(X[m], Y[m], 0, op)
  s = s pth(PK ? ELLPK "M0 0 0 0 0 0 0 0Z" : sub_ell(0, 0, 6, 3, 0) "M-10 -4.6 10 -4.6 10 -3.4 -10 -3.4Z", li("#3A3650", 3))
  s = s pth(PK ? "M0 0 0 0 0 0 0 0 0 0 0 0Z" : sub_dot(0, 1.5, 1.6), j_c(m))
  return s gout()
}
function j_c(m) { return m % 2 ? "#6FF3FF" : "#FF7BE8" }

# The crane: while the Mac builds (a compiler or linker working), a crane stands on Xcode's building — or on the app
# in front — its trolley and hook moving, a beacon blinking; the build ends, it goes.
function crane(dt,   s, want) {
  want = 0
  if (BUILDCPU > 8) { for (s = 1; s <= NSLOT; s++) if (SAPP[s] == "com.apple.dt.Xcode" && !SGONE[s] && SH[s] > 40) want = s
    if (!want) for (s = 1; s <= NSLOT; s++) if (SAPP[s] == FRONT && FRONT != "" && !SGONE[s] && SH[s] > 40) want = s }
  if (want != CRS && ACT[CRANE] && OP[CRANE] > 0) { OP[CRANE] = 0; return }        # leaves unseen, then comes back where wanted
  CRS = want
  if (!CRS) { ACT[CRANE] = 0; OP[CRANE] = 0; return }
  X[CRANE] = SX[CRS] + 6; Y[CRANE] = SG[CRS] - SH[CRS]; VX[CRANE] = 0
  if (!ACT[CRANE]) { ACT[CRANE] = 1; OP[CRANE] = 0 } else OP[CRANE] = 1
}
function d_crane(op,   s, tx, hy) {
  tx = 16 + 26 * (0.5 + 0.5 * sin(T * 0.45)); hy = -58 + 26 * (0.5 + 0.5 * sin(T * 0.8))
  s = gin(X[CRANE], Y[CRANE], 0, op)
  s = s re(-3, -74, 6, 74, "#C98A1A") (PK ? "<path d='M0 0L0 0' fill='none' stroke='#000' stroke-dasharray='1 1'/>" : "<path d='M0 -2V-72' fill='none' stroke='#2A1E08' stroke-width='5' stroke-dasharray='1.4 5'/>")
  s = s re(-22, -78, 70, 4, "#FFB800") re(-24, -76, 10, 9, "#6A5A3A")
  s = s strk(PK ? "M0 0L0 0" : seg_(tx, -74, tx, hy), "#B9B4C8", 1)
  s = s re(tx - 3, hy, 6, 4, "#FFB800") rr_(tx - 7, hy + 4, 14, 8, 1.5, "#35E8FF", " opacity='" f2(0.85 * NEONA) "'")
  s = s ci(0, -81, 2.4, "#FFD24A", " opacity='" (int(T * 1.3) % 2 ? "1" : "0.25") "'")
  return s gout()
}

# Couriers: an app's badge on the Dock grew — a drone flies a parcel to its building, hovers, and flies off.
function courier(dt,   u, s, tx, ty, t1, t2, d1, d2) {
  if (!ACT[COUR]) {
    if (CQN > 0) { CQS = CQ[1]; CKIND = CQK[1] + 0; for (u = 1; u < CQN; u++) { CQ[u] = CQ[u + 1]; CQK[u] = CQK[u + 1] }; CQN--; ACT[COUR] = 1; OP[COUR] = 0; CT0 = T; X[COUR] = -60; Y[COUR] = 30; CPK = 1 }
    return
  }
  # in at a steady 110 units a second, a hover with the parcel, out the same way
  s = CQS; tx = SX[s] + 18; ty = SG[s] - SH[s] - 26
  d1 = hyp(tx + 60, ty - 30); d2 = hyp(W + 60 - tx, ty - 10); t1 = d1 / 110; t2 = d2 / 110
  u = T - CT0
  if (u < t1) { X[COUR] = -60 + (tx + 60) * u / t1; Y[COUR] = 30 + (ty - 30) * u / t1; VX[COUR] = (tx + 60) / t1; OP[COUR] = u < 0.4 ? 0 : 1 }
  else if (u < t1 + 1.5) { X[COUR] = tx; Y[COUR] = ty + 2 * sin(u * 6); VX[COUR] = 0; CPK = u < t1 + 0.8 }
  else if (u < t1 + 1.5 + t2) { X[COUR] = tx + (W + 60 - tx) * (u - t1 - 1.5) / t2; Y[COUR] = ty + (10 - ty) * (u - t1 - 1.5) / t2; VX[COUR] = (W + 60 - tx) / t2; CPK = 0 }
  else if (OP[COUR] > 0) OP[COUR] = 0
  else ACT[COUR] = 0
}
function d_courier(op,   s) {
  s = gin(X[COUR], Y[COUR], 0, op)
  s = s strk(PK ? "M0 0L0 0M0 0L0 0" : seg_(-12, -6, -4, -6) seg_(4, -6, 12, -6), "#8E8AA6", 1.6)
  s = s pth(PK ? ELLPK : sub_ell(0, -2, 8, 4, 0), li("#2A2838", 3))
  s = s rr_(-5, 2, 10, 8, 1.5, "#FFB800", " opacity='" (CPK && !CKIND ? 1 : 0) "'")
  # or a cup of coffee, steaming
  s = s pth(PK ? "M0 0 0 0 0 0 0 0Z" : "M-4 2 4 2 3 11 -3 11Z", "#F2F2F6", " opacity='" (CPK && CKIND ? 1 : 0) "'") re(-4.5, 1, 9, 2, "#6A4A3A", " opacity='" (CPK && CKIND ? 1 : 0) "'")
  s = s pth(PK ? "M0 0 0 0 0 0 0 0 0 0 0 0Z" : sub_dot(0, -2, 1.6), "#FF3B5C")
  return s gout()
}

# Fireworks: a tap in the sky sends one up there — a streak rising, then a burst of neon that spreads and fades.
function firework(x, y,   j, m) {
  for (j = 1; j <= NFW; j++) { m = FW[j]; if (!ACT[m]) break }
  if (j > NFW) return
  ACT[m] = 1; OP[m] = 0; FT0[m] = T; FWX[m] = x; FWY[m] = y; FWC[m] = NEONP[int(rnd() * 6) + 1]; X[m] = x; Y[m] = y
}
function fireworks(dt,   j, m, u) {
  for (j = 1; j <= NFW; j++) {
    m = FW[j]; if (!ACT[m]) continue
    u = T - FT0[m]; VX[m] = 0
    if (u < 0.3) OP[m] = 0
    else if (u < 2.6) OP[m] = u < 1.9 ? 1 : cl((2.6 - u) / 0.7, 0.01, 1)
    else if (OP[m] > 0) OP[m] = 0
    else ACT[m] = 0
  }
}
function d_fw(m, op,   s, u, r, k, a, rays, dots, c, tr) {
  u = T - FT0[m]; r = u < 0.8 ? 2 : 4 + 26 * smooth((u - 0.8) / 1.6); c = FWC[m]
  tr = u < 0.8 ? cl(1 - (u - 0.3) / 0.5, 0, 1) : 0
  s = gin(FWX[m], FWY[m], 0, op)
  s = s strk(PK ? "M0 0L0 0" : seg_(0, 40 * tr + 2, 0, 40 * tr + 14 * (tr > 0)), "#FFE6A0", 1.6)
  rays = ""; dots = ""
  for (k = 0; k < 8; k++) {
    a = k * PI / 4
    rays = rays (PK ? "M0 0L0 0" : seg_(r * 0.45 * cos(a), r * 0.45 * sin(a), r * cos(a), r * sin(a)))
    dots = dots (PK ? "M0 0 0 0 0 0 0 0 0 0 0 0Z" : sub_dot((r + 4) * cos(a + 0.4), (r + 4) * sin(a + 0.4), 1.4))
  }
  s = s strk(rays, c, 1.8, " opacity='" (u < 0.8 ? 0 : 1) "'") pth(dots, "#FFFFFF", " opacity='" (u < 0.8 ? 0 : 0.9) "'")
  return s gout()
}

# The hologram clock: the time in big neon digits on a floating panel in the sky.
function hc_place() { if (PORT) { HCX = tl(1); HCY = 0 } else { HCX = tl(2); HCY = 0 } }
function hclock(   t) {
  t = sprintf("%02d:%02d", int(MINUTES / 60) % 24, MINUTES % 60)
  return rr_(HCX + 6, HCY + 30, 88, 40, 6, "#0E0D18", " opacity='0.55' stroke='#35E8FF' stroke-width='1.2' stroke-opacity='" f2(0.8 * NEONA) "'") \
         "<text x='" f1(HCX + 50) "' y='" f1(HCY + 61) "' font-size='28' font-weight='bold' text-anchor='middle' fill='" mixh("#FFFFFF", "#35E8FF", 0.45) "'>" t "</text>"
}

# Coffee after midnight: working past midnight, a courier brings a cup to the app in front, once an hour.
function coffee(   s) {
  if (!(MINUTES < 300 && AWAKE) || T < COFNEXT || FRONT == "" || !(FRONT in SLOTOF)) return
  s = SLOTOF[FRONT]; if (SGONE[s] || CQN >= 4) return
  CQ[++CQN] = s; CQK[CQN] = 1; COFNEXT = T + 3600
}

# ---------------------------------------------------------------- rare events: a glitch, a cat
# Each comes now and then and is gone again: most of the time the town is as it is.
function rare_events(dt) { glitch(); roofcat(dt) }

# A glitch: now and then one building's sign stutters — for a moment it takes another neon, jumps a little, flickers.
function glitch(   s, n) {
  if (T < GLNEXT) return
  n = 0; for (s = 1; s <= NSLOT; s++) if (SAPP[s] != "" && !SGONE[s] && SH[s] > 40) n++
  if (!n) { GLNEXT = T + 20; return }
  n = int(rnd() * n) + 1; for (s = 1; s <= NSLOT; s++) if (SAPP[s] != "" && !SGONE[s] && SH[s] > 40 && --n == 0) break
  SGL[s] = T + 1.5; GLC = NEONP[int(rnd() * 6) + 1]; GLNEXT = T + rr(60, 180)
}

# A cat of the neon town: now and then it walks along a roof, leaps across the gap to the next building's roof, sits a
# while with its eyes glowing, and walks off.
function roofcat(dt,   s, n, a, b, x, jx) {
  if (!ACT[KAT]) {
    if (T < KTNEXT) return
    KTNEXT = T + rr(120, 300)
    for (n = 0; n < 12; n++) { a = int(rnd() * NSLOT) + 1; b = a + 1; if (b <= NSLOT && SQ[a] == SQ[b] && SAPP[a] != "" && SAPP[b] != "" && !SGONE[a] && !SGONE[b] && SH[a] > 40 && SH[b] > 40 && abs(SH[a] - SH[b]) < 40 && ATYP[SAPP[a]] != 1 && ATYP[SAPP[b]] != 1) break }
    if (n == 12) return
    KA_ = a; KB_ = b; ACT[KAT] = 1; OP[KAT] = 0; KPH = 0; KT0 = T; X[KAT] = SX[a] - AW[SAPP[a]] / 2 + 6; Y[KAT] = SG[a] - SH[a] - 3; D[KAT] = 1
    return
  }
  a = KA_; b = KB_; VY[KAT] = 0; KWALK = 0
  if (KPH == 0) { OP[KAT] = 0; KPH = 1; return }
  if (KPH == 1) { OP[KAT] = 1; x = SX[a] + AW[SAPP[a]] / 2 - 6; X[KAT] += 16 * dt; KWALK = 1; VX[KAT] = 16; Y[KAT] = SG[a] - SH[a] - 3; if (X[KAT] >= x) { KPH = 2; KJ0 = X[KAT]; KJT = T } return }
  # the leap takes as long as its length needs (about 60 units a second): never a big jump in one frame
  if (KPH == 2) { jx = SX[b] - AW[SAPP[b]] / 2 + 6; KJD = mx(0.8, hyp(jx - KJ0, SH[a] - SH[b]) / 60); x = cl((T - KJT) / KJD, 0, 1); X[KAT] = KJ0 + (jx - KJ0) * x; Y[KAT] = (SG[a] - SH[a] - 3) + ((SG[b] - SH[b] - 3) - (SG[a] - SH[a] - 3)) * x - 26 * sin(x * PI); VX[KAT] = (jx - KJ0) / KJD; if (x >= 1) { KPH = 3; KS0 = T } return }
  if (KPH == 3) { VX[KAT] = 0; Y[KAT] = SG[b] - SH[b] - 3; if (T - KS0 > 8) KPH = 4; return }
  if (KPH == 4) { X[KAT] += 16 * dt; KWALK = 1; VX[KAT] = 16; Y[KAT] = SG[b] - SH[b] - 3; if (X[KAT] > SX[b] + AW[SAPP[b]] / 2 - 10) KPH = 5; return }
  if (OP[KAT] > 0) OP[KAT] = 0; else ACT[KAT] = 0
}
function d_kat(op,   s, sit, lg) {
  sit = KPH == 3; lg = KWALK ? (int(T * 3) % 2 ? 1 : -1) : 0
  s = gin(X[KAT], Y[KAT], 0, op)
  s = s strk(PK ? "M0 0L0 0M0 0L0 0" : seg_(-4, -3, -4 - 2 * lg, 0) seg_(4, -3, 4 + 2 * lg, 0), "#15131F", 1.6)
  s = s strk(PK ? "M0 0Q0 0 0 0" : "M-7 " f1(sit ? -3 : -6) "Q-14 " f1(sit ? -2 : -12) " -12 " f1(sit ? -12 : -16 + 3 * sin(T * 3)), "#15131F", 1.8)
  s = s pth(PK ? ELLPK ELLPK "M0 0 0 0 0 0ZM0 0 0 0 0 0Z" : sub_ell(sit ? -1 : 0, sit ? -6 : -5, sit ? 5 : 8, sit ? 6 : 3.4, 0) sub_ell(sit ? 2 : 8, sit ? -13 : -9, 3.6, 3.2, 0) "M" f1(sit ? -0.5 : 5.5) " " f1(sit ? -15 : -11) " " f1(sit ? 0.5 : 6.5) " " f1(sit ? -19 : -15) " " f1(sit ? 2 : 8) " " f1(sit ? -15.5 : -11.5) "ZM" f1(sit ? 2.5 : 8.5) " " f1(sit ? -15.5 : -11.5) " " f1(sit ? 4 : 10) " " f1(sit ? -19 : -15) " " f1(sit ? 5 : 11) " " f1(sit ? -15 : -11) "Z", "#15131F")
  s = s pth(PK ? "M0 0 0 0 0 0 0 0 0 0 0 0ZM0 0 0 0 0 0 0 0 0 0 0 0Z" : sub_dot(sit ? 1 : 7, sit ? -13.5 : -9.5, 0.8) sub_dot(sit ? 3.4 : 9.4, sit ? -13.5 : -9.5, 0.8), "#7CFF4F")
  return s gout()
}
# ---------------------------------------------------------------- tiles
function window_of(row, col) { if (PORT) { WX_ = col * PITCH; WY_ = row * PITCH } else { WX_ = row * PITCH; WY_ = (COLS - 1 - col) * PITCH } }
function bucket(   L, s, d, m) {
  bands()
  for (L = 1; L <= 9; L++) LIN[L] = 0
  for (s = 1; s <= NS; s++) { L = SL_[s]; LIN[L]++; LIT[L, LIN[L]] = 4; LIX[L, LIN[L]] = s }
  for (d = 1; d <= ND; d++) { L = DL[d]; LIN[L]++; LIT[L, LIN[L]] = 2; LIX[L, LIN[L]] = d }
  for (m = 1; m <= NM; m++) { L = ML[m]; LIN[L]++; LIT[L, LIN[L]] = 3; LIX[L, LIN[L]] = m }
}
function tile(id, x, y) { TX[id] = x; TY[id] = y; TG[id]++; FIRST[id] = 1; FORCE[id] = 1; LAST[id] = ""; LASTT[id] = 0; slots(id); upgrade(id) }
function inbox(id, x0, y0, x1, y1) { return x1 > TX[id] - 1 && x0 < TX[id] + 101 && y1 > TY[id] - 1 && y0 < TY[id] + 101 }
function add(id, t, n) { NSL[id]++; SLT[id, NSL[id]] = t; SLN[id, NSL[id]] = n }
function slots(id,   L, k, t, n) {
  NSL[id] = 0
  for (L = 1; L <= 9; L++) for (k = 1; k <= LIN[L]; k++) {
    t = LIT[L, k]; n = LIX[L, k]
    if (t == 4) { if (inbox(id, SX0[n], SY0[n], SX1[n], SY1[n])) add(id, 4, n) }
    else if (t == 2) { if (inbox(id, DX0[n], DY0[n], DX1[n], DY1[n])) add(id, 2, n) }
    else if (inbox(id, BX0[n], BY0[n], BX1[n], BY1[n])) add(id, 3, n)
  }
}
# The tile takes on the light of the moment: its head and its still scenery.
function upgrade(id,   k, t, n, s, c) {
  HEAD[id] = head(id); c = 2
  for (k = 1; k <= NSL[id]; k++) { t = SLT[id, k]; n = SLN[id, k]; if (t == 4) { s = SST[n]; TSS[id, k] = s; c += gsub(/</, "<", s) } }
  TSN[id] = c; TLG[id] = LGEN
}
# The start of a tile's frame: viewBox, the sky gradient (in world space), the sky behind everything. Its id changes
# with every new layout: a tile's first frame then cross-fades.
function head(id,   x, y, s, w, h) {
  x = TX[id]; y = TY[id]; w = id == "COVER" ? W : 100; h = id == "COVER" ? H : 100
  s = "<svg viewBox='" f1(x) " " f1(y) " " w " " h "'><defs><linearGradient id='k' gradientUnits='userSpaceOnUse' x1='0' y1='0' x2='0' y2='" f1(DY) "'><stop stop-color='" SKY1 "'/><stop offset='1' stop-color='" SKY2 "'/></linearGradient></defs>"
  if (id == "COVER") return s "<rect x='-1' y='-1' width='" (W + 2) "' height='" (H + 2) "' fill='url(#k)'/>"
  return s "<rect id='b" GEN "t" TG[id] "' x='" f1(x - 1) "' y='" f1(y - 1) "' width='102' height='102' fill='url(#k)'/>"
}
function relight(   i, id) { statics(); bucket(); for (i = 1; i <= NT; i++) { id = ORD[i]; slots(id); if (FIRST[id] || TOOL) upgrade(id) } }

# ---------------------------------------------------------------- composing a tile's frame
function prep(per,   m, h, vx, vy) {
  h = per * 1.1
  for (m = 1; m <= NM; m++) {
    if (!ACT[m]) { PBT[m] = 0; continue }
    mbox(m)
    if (PBT[m] != TICK) { Q0X[m] = B0X[m]; Q0Y[m] = B0Y[m]; Q1X[m] = B1X[m]; Q1Y[m] = B1Y[m] }
    vx = VX[m] * h; vy = VY[m] * h
    # a cloud's tiles are slow (a frame every third tick, drawn a glide ahead): they must learn of it much earlier
    if (MK[m] == "cloud") vx = VX[m] * per * 7
    VX0[m] = mn(mn(Q0X[m], B0X[m]), B0X[m] + 2 * vx) - 3; VX1[m] = mx(mx(Q1X[m], B1X[m]), B1X[m] + 2 * vx) + 3
    VY0[m] = mn(mn(Q0Y[m], B0Y[m]), B0Y[m] + 2 * vy) - 3; VY1[m] = mx(mx(Q1Y[m], B1Y[m]), B1Y[m] + 2 * vy) + 3
    Q0X[m] = B0X[m]; Q0Y[m] = B0Y[m]; Q1X[m] = B1X[m]; Q1Y[m] = B1Y[m]; PBT[m] = TICK + 1
  }
}
function hitv(id, m) { return ACT[m] && VX1[m] > TX[id] && VX0[m] < TX[id] + 100 && VY1[m] > TY[id] && VY0[m] < TY[id] + 100 }
function seen(id, m,   w, h) { w = id == "COVER" ? W : 100; h = id == "COVER" ? H : 100; return ACT[m] && B1X[m] > TX[id] && B0X[m] < TX[id] + w && B1Y[m] > TY[id] && B0Y[m] < TY[id] + h }
function mvis(m) { if (MVT[m] != TICK SUBSEP AHEAD) { MV[m] = draw(m, OP[m]); MVT[m] = TICK SUBSEP AHEAD }; return MV[m] }
function mfrozen(m, id,   x, y, r) { x = X[m]; y = Y[m]; X[m] = GX[id, m]; Y[m] = GY[id, m]; r = draw(m, 0); X[m] = x; Y[m] = y; return r }
function minv(m) { if (MIT[m] != TICK SUBSEP AHEAD) { MI[m] = draw(m, 0); MIT[m] = TICK SUBSEP AHEAD }; return MI[m] }
# Whether a tile needs a frame every tick: something quick in it (the pet, a guest, the ball, an emote), or one that
# just left, or quick scenery (the screen while typing, the wheel turning, rain). Only clouds and slow scenery: every
# third tick, drawn where the longer glide ends.
function busy(id,   k, t, n) {
  for (k = 1; k <= NSL[id]; k++) {
    t = SLT[id, k]; n = SLN[id, k]
    if (t == 3) { if ((MK[n] != "cloud" || (CJ[n] && TST[id, n])) && (TST[id, n] || hitv(id, n))) return 1 }
    else if (t == 2) { if (DK[n] == "bld" && SH[DS_[n]] != STGT[DS_[n]]) return 1 }
  }
  return 0
}
# A mover in a tile is parked (0), coming (1: at its real place, invisible), shown (2) or going (3 … 2 + GOING: still
# where it went out, invisible; then parked). mode 2: a still picture (nothing parked, nothing invisible).
# A glide longer than the tick never ends a fade: every frame takes over a sixth short of it, so a mover just hidden
# stays a faint ghost for five frames. Going holds it where it
# went out for those five frames (the world may have moved it far, to the other end of the street); and a mover seen
# here lately shows again only where it went out, or after those five frames (HC: frames since it last showed here),
# else the phone would glide the faint ghost to its new place.
function compose(id, mode,   s, k, t, n, st, pk, ph, hc) {
  s = HEAD[id]; pk = 0
  for (k = 1; k <= NSL[id]; k++) {
    t = SLT[id, k]; n = SLN[id, k]; ph = 0
    if (t == 3 && mode != 2) {
      st = hitv(id, n) && OP[n] > 0; ph = TST[id, n]; hc = ((id, n) in HCN) ? HCN[id, n] : 99
      if (st) {
        if (ph >= 3) ph = abs(X[n] - GX[id, n]) + abs(Y[n] - GY[id, n]) < 30 ? 2 : 1
        else if (ph == 1) { if (hc >= GOING) ph = 2 }
        else if (ph == 0) ph = 1
      } else if (ph == 2) { ph = 3; GX[id, n] = X[n]; GY[id, n] = Y[n] }
      else if (ph >= 3) ph = ph < 2 + GOING ? ph + 1 : 0
      else ph = 0
      HCN[id, n] = ph == 2 ? 0 : (hc < 99 ? hc + 1 : 99)
      TST[id, n] = ph
    }
    if (pk && (t != 3 || mode == 2 || ph)) { s = s "</g>"; pk = 0 }
    if (t == 4) s = s TSS[id, k]
    else if (t == 2) s = s dstr(n, id)
    else if (mode == 2) { if (seen(id, n) && OP[n] > 0) s = s mvis(n) }
    else if (ph == 2) s = s mvis(n)
    else if (ph >= 3) s = s mfrozen(n, id)
    else if (ph) s = s minv(n)
    else { if (!pk) { s = s "<g transform='translate(1e6 1e6)' opacity='0'>"; pk = 1 }; s = s PARK[n] }
  }
  return s (pk ? "</g>" : "") "</svg>"
}


# ---------------------------------------------------------------- live: the phone's view, the Mac, ticks
# ---------------------------------------------------------------- live: the phone's view, taps, ticks
function view(body,   cols, ori, p, n, parts, k, id, row, col, rs, cs, gi, me, ids, cnt, i, keep, gs, gg, gap) {
  SHOWN = 0
  if (body !~ /"connected":true/ || body ~ /"view":null/) GONE = 1
  if (body !~ /"connected":true/ || body ~ /"view":null/ || body ~ /"isForeground":false/) return
  body = mine(body)
  if (!match(body, /"columns":[0-9]+/)) return
  cols = substr(body, RSTART + 10, RLENGTH - 10) + 0
  if (cols < 1 || cols > 12) return
  ori = body ~ /"orientation":"landscape"|"isLandscape":true/ ? "landscape" : "portrait"
  gs = jflt(body, "cellSize", 0); gg = jflt(body, "cellGap", -1)
  gap = gs > 0 && gg >= 0 ? int(1000 * gg / gs + 0.5) / 10 : 0; if (gap > 40) gap = 40
  p = index(body, "\"cells\":["); if (!p) return
  n = cells_of(substr(body, p + 9), parts); me = 0; cnt = 0
  for (k = 1; k <= n; k++) {
    id = jstr(parts[k], "id"); if (id == "") continue
    id = toupper(id); if (id == ME) me = 1
    gi = jstr(parts[k], "galleryItem"); if (gi !~ /^town\./) continue
    row = jnum(parts[k], "row", -1); col = jnum(parts[k], "col", -1); rs = jnum(parts[k], "rowSpan", 1); cs = jnum(parts[k], "colSpan", 1)
    if (rs != 1 || cs != 1 || row < 0 || row > 7 || col < 0 || col >= cols) continue
    ids[++cnt] = id; VR[id] = row; VC[id] = col
  }
  if (!me) return
  SHOWN = 1
  if (cols != COLS || ori != ORI || abs(gap - GAP) > 0.5) { GAP = gap; world(cols, ori); NT = 0; delete ORD }
  delete keep
  for (i = 1; i <= NT; i++) keep[ORD[i]] = 1
  NT = 0
  for (i = 1; i <= cnt; i++) {
    id = ids[i]; window_of(VR[id], VC[id])
    ORD[++NT] = id
    if (!(id in keep) || TX[id] != WX_ || TY[id] != WY_) tile(id, WX_, WY_)
  }
  if (GONE) { resync(); GONE = 0 }
}
# The part of the view that holds this page. An iPad shows several windows side by side, each on its own page, and
# the top-level fields are only the window touched last; "windows" lists every one (that one first) with its own
# cells and grid. No window holds this tile (an older app, none yet): the top-level fields, without the windows.
function mine(body,   p, s, n, i, c, d, q, e, st) {
  p = index(body, "\"windows\":["); if (!p) return body
  s = substr(body, p + 11); n = length(s); d = 0; q = 0; e = 0
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (q) { if (e) e = 0; else if (c == "\\") e = 1; else if (c == "\"") q = 0; continue }
    if (c == "\"") q = 1
    else if (c == "{" || c == "[") { if (!d++) st = i }
    else if (c == "}" || c == "]") { if (!d) break; if (!--d && index(toupper(substr(s, st, i - st)), "\"" ME "\"")) return substr(s, st, i - st + 1) }
  }
  return substr(body, 1, p - 1)
}
function cells_of(s, out,   n, i, c, depth, str, esc, cur, len) {
  n = 0; depth = 0; str = 0; esc = 0; cur = ""; len = length(s)
  for (i = 1; i <= len; i++) {
    c = substr(s, i, 1)
    if (str) { if (depth == 1) cur = cur c; if (esc) esc = 0; else if (c == "\\") esc = 1; else if (c == "\"") str = 0; continue }
    if (c == "\"") { str = 1; if (depth == 1) cur = cur c; continue }
    if (c == "{" || c == "[") { depth++; if (depth == 1) cur = ""; continue }
    if (c == "}" || c == "]") { if (depth == 0) break; if (depth == 1 && c == "}") out[++n] = cur; depth--; continue }
    if (depth == 1) cur = cur c
  }
  return n
}
function jstr(s, key,   p) { if (!match(s, "\"" key "\":\"[^\"]*\"")) return ""; return substr(s, RSTART + length(key) + 4, RLENGTH - length(key) - 5) }
function jnum(s, key, def) { if (!match(s, "\"" key "\":-?[0-9]+")) return def; return substr(s, RSTART + length(key) + 3, RLENGTH - length(key) - 3) + 0 }
function jflt(s, key, def) { if (!match(s, "\"" key "\":-?[0-9]+(\\.[0-9]+)?")) return def; return substr(s, RSTART + length(key) + 3, RLENGTH - length(key) - 3) + 0 }


# The network counters: kilobytes a second in and out since the last reading.
function net(ib, ob, now,   dt) {
  if (NETT > 0 && now > NETT) { dt = now - NETT; NETIN = (ib - NETIB) / dt / 1024; NETOUT = (ob - NETOB) / dt / 1024; if (NETIN < 0 || NETOUT < 0) { NETIN = 0; NETOUT = 0 }; NETR = NETIN + NETOUT }
  NETIB = ib; NETOB = ob; NETT = now
}
function front_x(   s) { FRONTX = -1; for (s = 1; s <= NSLOT; s++) if (SAPP[s] == FRONT && FRONT != "" && SQ[s] == 0 && !SGONE[s]) FRONTX = SX[s] }
# One step a tick. The invisible jump (hidden where it left, moved while hidden, shown again) takes one frame a stage:
# with smaller steps two stages could land in one frame, and the phone would glide a car back across the street.
function sim(dt) { T += dt; step(dt) }
function tick(now, minutes, load, slow, idle,   dt, i, id, s, dur, per, k, m, b, q) {
  # a tick every 0.5 s; on the iPad's 48 tiles every 0.6 s (the aquarium's pace there); 2 s while the phone lags
  per = slow ? 2 : (NT > 36 ? 0.6 : PER); PERR = per
  MINUTES = minutes; LOAD = load; AWAKE = idle < 300
  if (!SHOWN || !NT) { NOW = now; RESUMED = 1; reply(); return }
  dt = NOW > 0 && !RESUMED ? now - NOW : per; if (dt > 1.5 * per || dt < 0) dt = per
  NOW = now; RESUMED = 0
  front_x()
  sim(dt)
  if (light(minutes)) relight()
  prep(per)
  TICK++
  RCRED = mn(RCRED + 160, 400)
  for (k = 1; k <= NT; k++) {
    id = ORD[UPC % NT + 1]
    if (TLG[id] != LGEN) { if (TSN[id] > RCRED) break; upgrade(id); RCRED -= TSN[id] }
    UPC = UPC % NT + 1
  }
  KAC = KAC % NT + 1; id = ORD[KAC]; if (now - LASTT[id] > 45) KEEP[id] = 1
  REQS = ""; NREQ = 0
  for (i = 1; i <= NT; i++) {
    id = ORD[i]
    b = busy(id) || FORCE[id]
    # a tile that was quick last tick and is slow now gets its long frame at once: its last short glide ends before
    # the slow turn would come round, and whatever still drifts in it (a cloud) would stand
    q = WASB[id]; WASB[id] = b
    if (!b && (TICK + i) % 3 && !KEEP[id] && !q) continue
    AHEAD = b ? 0 : 2 * per
    s = compose(id, 0); AHEAD = 0
    if (!FORCE[id] && !KEEP[id] && s == LAST[id]) continue
    # a glide a fifth longer than the tick: a frame the Wi-Fi brings late takes over a mover still moving (one length
    # for every tile, so the halves of a mover in two tiles keep together)
    dur = FIRST[id] ? 0.35 : (b ? per * 1.2 : 3 * per * 1.08)
    post(id, s, dur)
    LAST[id] = s; LASTT[id] = now; FORCE[id] = 0; FIRST[id] = 0; KEEP[id] = 0
  }
  reply()
}
function post(id, s, dur,   body) {
  body = "{\"cellId\":\"" id "\",\"svg\":{\"source\":\"" s "\",\"duration\":" sprintf("%.2f", dur) ",\"easing\":\"linear\",\"fit\":\"stretch\"}}"
  REQS = REQS "POST /api/update-button HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer " TOKEN "\r\nContent-Type: application/json\r\nContent-Length: " length(body) "\r\n\r\n" body
  NREQ++
}
function reply() { printf "B %d %d %d %.2f %s\n%s", length(REQS), NREQ, SHOWN, (PERR ? PERR : 1), (OPENB == "" ? "-" : OPENB), REQS; OPENB = ""; fflush(); REQS = ""; NREQ = 0 }
function resync(   i) { for (i = 1; i <= NT; i++) FORCE[ORD[i]] = 1 }
function quit(   i, body) {
  REQS = ""; NREQ = 0
  for (i = 1; i <= NT; i++) {
    body = "{\"cellId\":\"" ORD[i] "\",\"svg\":{\"remove\":true}}"
    REQS = REQS "POST /api/update-button HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer " TOKEN "\r\nContent-Type: application/json\r\nContent-Length: " length(body) "\r\n\r\n" body
    NREQ++
  }
  printf "Q %d %d %d 1\n%s", length(REQS), NREQ, SHOWN, REQS; fflush()
}


# ---------------------------------------------------------------- tool modes: fixed seed, fixed clock, no network
# A town of sample apps told for `steps` ticks of 0.5 s. Stories: busy (a loaded Mac), net (a download), away.
# The sample apps are Apple's own: the sample faces and the cover are shown in the App Store screenshots and the App
# Preview, where no other company's name or mark may appear (a made-up name may well be someone's mark too).
function sample(   k, a, i, p) {
  k = split("com.apple.dt.Xcode|Xcode|1900000|12 com.apple.Terminal|Terminal|80000|6 com.apple.Safari|Safari|700000|3 com.apple.mail|Mail|300000|0.5 com.apple.Music|Music|200000|1 com.apple.Notes|Notes|250000|0 com.apple.MobileSMS|Messages|420000|2 com.apple.finder|Finder|90000|0 com.apple.freeform|Freeform|900000|0 com.apple.iWork.Keynote|Keynote|500000|1 com.apple.Preview|Preview|260000|0 com.apple.podcasts|Podcasts|330000|0 com.apple.reminders|Reminders|120000|0 com.apple.iWork.Pages|Pages|380000|0 com.apple.ActivityMonitor|Activity_Monitor|60000|3 com.apple.iCal|Calendar|240000|0 com.apple.Photos|Photos|70000|0", a, " ")
  NA = 0
  for (i = 1; i <= k; i++) { split(a[i], p, "|"); NA++; APPB[NA] = p[1]; LN[NA] = p[2]; gsub(/_/, " ", LN[NA]); LR_[NA] = p[3] + 0; LC[NA] = p[4] + 0; LBG[NA] = p[1] ~ /mail|MobileSMS/ ? 3 : 0 }
  FRONT = APPB[1]
}
function story(cols, ori, minutes, steps, what,   r, c, id, k, i, m, b, cs) {
  SEED = 20260930; T = 0; TICK = 0; TOOL = 1; MINUTES = minutes
  CAST = 0; delete TST; delete MVT; delete MIT; LIGHTDIG = ""; delete SAPP; delete SLOTOF
  GLNEXT = what ~ /glitch/ ? 2 : 1e9; KTNEXT = what ~ /cat/ ? 2 : 1e9; SHX = 0
  WDAY = what ~ /weekend/ ? 6 : 3; COFNEXT = what ~ /coffee/ ? 3 : 1e9; CQN = 0
  RAINY = what ~ /rain/; WNEXT = 1e9; LOAD = what ~ /busy/ ? 1.3 : 0.35
  AGENTS_ = what ~ /ai10/ ? 10 : (what ~ /ai/ ? 5 : 0); AGBUSY_ = what ~ /ai/; AGN = 0; AGNT = 0; AGBT = -100; TOWA = what ~ /ai/ ? 0.9 : 0; AGSEC = -1; BUILDCPU = what ~ /build/ ? 80 : 0; CQN = 0; BADGESEEN = 0; WAVE0 = -100; HASBAT = what ~ /flat/; BATT = what ~ /flat/ ? 6 : 100; CHARGING = 0; AWAKE = what !~ /away/; NETR = what ~ /net/ ? 2500 : 0; NETIN = NETR; NETOUT = 10
  world(cols, ori); sample(); commit()
  for (m = 1; m <= NSLOT; m++) SH[m] = STGT[m]
  NT = 0
  for (r = 0; r < 8; r++) for (c = 0; c < cols; c++) { id = sprintf("R%dC%d", r, c); window_of(r, c); ORD[++NT] = id; RRW[id] = r; RCL[id] = c; tile(id, WX_, WY_) }
  if (what ~ /net/) TNEXT = 0
  for (k = 1; k <= steps; k++) {
    if (what ~ /badge/ && k == 10) { LBG[4] = 7; commit() }
    if (what ~ /fire/ && k % 12 == 5) firework(tc(k % NTA), tt(0) + 60)
    if (what ~ /plug/ && k == 15) { CHARGING = 1; WAVE0 = T }
    if (what ~ /quit/ && k == 20) { NA--; for (i = 1; i <= NA; i++) { APPB[i] = APPB[i + 1]; LN[i] = LN[i + 1]; LR_[i] = LR_[i + 1]; LC[i] = LC[i + 1] }; FRONT = APPB[1]; commit() }
    front_x(); sim(0.5)
    light(minutes); if (LIGHTDIG != LDONE) { LDONE = LIGHTDIG; relight() }
    prep(0.5); TICK++
    if (k < steps && !STILL) for (i = 1; i <= NT; i++) {
      id = ORD[i]; b = busy(id) || FIRST[id]
      if (!b && (TICK + i) % 3) continue
      AHEAD = b ? 0 : 1; cs = compose(id, 0); AHEAD = 0; FIRST[id] = 0
      if (SEQ && cs != LAST[id]) printf "{\"step\":%d,\"row\":%d,\"col\":%d,\"dur\":%.2f,\"svg\":\"%s\"}\n", k, RRW[id], RCL[id], b ? 0.54 : 1.55, cs
      LAST[id] = cs
    }
  }
}
# A sample face is a still picture: the elements a live frame keeps invisible (for its structure) are left out.
function visible_only(s,   o) {
  o = ""
  while (match(s, /<(rect|circle|ellipse|path|polygon|line)( [^>]*)? opacity='0(\.0+)?'[^>]*\/>/)) { o = o substr(s, 1, RSTART - 1); s = substr(s, RSTART + RLENGTH) }
  s = o s; o = ""
  while (match(s, /<text [^>]* opacity='0(\.0+)?'[^>]*>[^<]*<\/text>/)) { o = o substr(s, 1, RSTART - 1); s = substr(s, RSTART + RLENGTH) }
  return o s
}
# the cover draws the whole world in one document
function slots_all(id,   L, k, t, n) { NSL[id] = 0; for (L = 1; L <= 9; L++) for (k = 1; k <= LIN[L]; k++) { t = LIT[L, k]; n = LIX[L, k]; add(id, t, n) } }
# A tile's resting face: the night, plain — after a turn the same tile may be anywhere in town.
function rest(row, col) { return "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><rect x='-1' y='-1' width='102' height='102' fill='#120E22'/></svg>" }
function start(mode, a, b, c, d, e,   i, id) {
  if (mode == "faces") {
    # the sample: the iPad's page turned (8×6), as the Gallery shows a scene (its preview stands in landscape)
    STILL = 1; GAP = GDEMO; story(6, "landscape", 22 * 60, 30, "net+ai+badge")
    # whole numbers: the sample faces of 48 tiles must stay light in the catalog
    RI = 1; delete DST; delete DBT; delete MVT
    printf "{"
    for (i = 1; i <= NT; i++) { id = ORD[i]; printf "%s\"r%dc%d\":{\"rest\":\"%s\",\"demo\":\"%s\"}", (i > 1 ? "," : ""), RRW[id], RCL[id], rest(RRW[id], RCL[id]), visible_only(compose(id, 2)) }
    print "}"
    return
  }
  if (mode == "cover") {
    STILL = 1; GAP = 0; story(4, "landscape", 22 * 60, 30, "net+ai")
    NT = 1; ORD[1] = "COVER"; TX["COVER"] = 0; TY["COVER"] = 0; slots_all("COVER"); upgrade("COVER")
    # a still picture: whole units are enough (the card has a size limit)
    RI = 1; DST_RESET = 1; delete DST; print compose("COVER", 2)
    return
  }
  if (mode == "live") { ME = toupper(a); SEED = (b + 0) % 2147483000 + 1; return }
  if (mode == "seq") { SEQ = 1; GAP = GDEMO; story(a + 0, b, c + 0, d + 0, e); return }
  if (mode == "dump") {
    GAP = GDEMO; story(a + 0, b, c + 0, d + 0, e)
    printf "["
    for (i = 1; i <= NT; i++) { id = ORD[i]; printf "%s{\"row\":%d,\"col\":%d,\"svg\":\"%s\"}", (i > 1 ? "," : ""), RRW[id], RCL[id], compose(id, 0) }
    print "]"
    return
  }
}

{
  c = $1
  if (c == "S") { WDAY = $7 + 0; tick($2 + 0, $3 + 0, $4 + 0, $5 + 0, $6 + 0); next }
  if (c == "V") { view(substr($0, 3)); next }
  if (c == "F") { if (SHOWN) tap(toupper($2)); next }
  if (c == "A") { NA = 0; next }
  if (c == "P") { NA++; APPB[NA] = $2; LR_[NA] = $3 + 0; LC[NA] = $4 + 0; LBG[NA] = $5 + 0; n = $0; sub(/^P [^ ]+ [^ ]+ [^ ]+ [^ ]+ /, "", n); gsub(/[<>&'"\\]/, "", n); LN[NA] = n; next }
  if (c == "I") { AGENTS_ = $2 + 0; AGBUSY_ = $3 > 5; BUILDCPU = $4 + 0; next }
  if (c == "Z") { commit(); next }
  if (c == "N") { FRONT = $2; next }
  if (c == "W") { net($2 + 0, $3 + 0, $4 + 0); next }
  if (c == "Y") { if (HASBAT && !CHARGING && $3 + 0 && BATTSEEN) WAVE0 = T; BATT = $2 + 0; CHARGING = $3 + 0; HASBAT = $4 + 0; BATTSEEN = 1; next }
  if (c == "R") { resync(); next }
  if (c == "Q") { quit(); exit }
  if (c == "M") { start($2, $3, $4, $5, $6, $7); if ($2 != "live") exit; next }
}

AWK
}

usage() {
  print -u2 -- "usage: engine.zsh [--faces out.json | --cover out.svg | --dump|--seq <4|6> <portrait|landscape> <HH:MM> <steps> out [story]]"
  exit 2
}
case $1 in
  --faces) (( $# == 2 )) || usage; print -r -- "M faces" | town_world > $2; exit $? ;;
  --cover) (( $# == 2 )) || usage; print -r -- "M cover" | town_world > $2; exit $? ;;
  --dump|--seq)
    (( $# >= 6 )) && [[ $2 == (4|6) && $3 == (portrait|landscape) && $4 == <0-23>:<0-59> && $5 == <1-5000> ]] || usage
    print -r -- "M ${1#--} $2 $3 $(( ${4%%:*} * 60 + ${4##*:} )) $5 ${${(j:+:)@[7,-1]}:-day}" | town_world > $6; exit $? ;;
  "") ;;
  *) usage ;;
esac

# ---------------------------------------------------------------- live
port=9848
cell="{{CELL_ID}}"
token=$DESMAPTIC_TOKEN
store="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/town"
mkdir -p "$store" 2>/dev/null
typeset -F SECONDS
typeset -F period=1 load=0 load_at=-100 idle_at=-100 batt_at=-100 next=0
integer shown=0 slow=0 pause=0 quitting=0 changed=0 idle=0
typeset -a lines ld

last_log=""
log_once() { [[ $1 == "$last_log" ]] && return; last_log=$1; print -u2 -r -- "town: $1"; }

sock="" http_status=0 http_body="" rx=""
integer api_failures=0 auth_failures=0 owed=0 writing=0
typeset -F api_retry_at=0

api_close() { [[ -n $sock ]] && ztcp -c $sock 2>/dev/null; sock="" rx="" owed=0; }

api_connect() {
  (( SECONDS >= api_retry_at )) || return 1
  if ztcp 127.0.0.1 $port 2>/dev/null; then
    sock=$REPLY api_failures=0 rx=""
    (( quitting )) || print -u $town_in R
    return 0
  fi
  (( api_failures++ ))
  (( api_retry_at = SECONDS + (api_failures > 5 ? 5 : 0.25 * (1 << (api_failures - 1))) ))
  log_once "the agent does not answer on port $port; retrying"
  (( api_failures == 1 || api_failures % 12 == 0 )) && [[ $(ps -o ppid= -p $$ 2>/dev/null) == *[[:space:]]1 ]] && exit 0
  return 1
}

api_write() {
  writing=1
  print -rn -u $sock -- "$1" 2>/dev/null || { writing=0; api_close; return 1; }
  writing=0; (( owed += $2 ))
  return 0
}

read_response() {
  local chunk header line
  integer len close
  while [[ $rx != *$'\r\n\r\n'* ]]; do
    sysread -i $sock -s 65536 -t 3 chunk
    case $? in
      0) rx+=$chunk ;;
      *) api_close; return 1 ;;
    esac
  done
  header=${rx%%$'\r\n\r\n'*} rx=${rx#*$'\r\n\r\n'} len=0 close=0
  for line in ${(f)header}; do
    line=${(L)line%$'\r'}
    case $line in
      content-length:*) len=${line#*:} ;;
      connection:*close*) close=1 ;;
    esac
  done
  while (( ${#rx} < len )); do
    sysread -i $sock -s 65536 -t 3 chunk || { api_close; return 1 }
    rx+=$chunk
  done
  http_body=${rx[1,len]} rx=${rx[len+1,-1]}
  line=${header%%$'\r'*}; http_status=${${line#* }%% *}
  [[ $http_status == <-> ]] || http_status=0
  (( owed > 0 && owed-- ))
  if (( http_status == 401 )); then
    (( ++auth_failures >= 3 )) && { print -u2 -- "town: the agent does not accept DESMAPTIC_TOKEN"; exit 4; }
  else
    auth_failures=0
  fi
  (( close )) && api_close
  return 0
}

vbody="-" vlast=""
fetch_view() {
  local request="GET /api/view HTTP/1.1"$'\r\n'"Host: 127.0.0.1"$'\r\n'"Authorization: Bearer $token"$'\r\n\r\n'
  integer try
  for try in 1 2; do
    [[ -n $sock ]] || api_connect || return 1
    api_write "$request" 1 || continue
    read_response || continue
    (( http_status == 200 )) || return 1
    vbody=${http_body//$'\n'/ }
    return 0
  done
  return 1
}

wbuf="" whead="" wbody=""
world_reply() {
  local chunk
  integer need
  while [[ $wbuf != *$'\n'* ]]; do sysread -i $town_out -s 65536 $@ chunk || return 1; wbuf+=$chunk; done
  whead=${wbuf%%$'\n'*}
  need=${${(s: :)whead}[2]}
  while (( ${#wbuf} - ${#whead} - 1 < need )); do sysread -i $town_out -s 65536 $@ chunk || return 1; wbuf+=$chunk; done
  wbody=${wbuf[${#whead}+2,${#whead}+1+need]}
  wbuf=${wbuf[${#whead}+2+need,-1]}
  return 0
}

integer drops=0
send_tick() {
  integer count got=0
  world_reply || { print -u2 -- "town: the world stopped"; exit 1; }
  count=${${(s: :)whead}[3]} shown=${${(s: :)whead}[4]} period=${${(s: :)whead}[5]}
  # a tap on a building: switch to its app (a bundle id, nothing else, goes to open)
  local ob=${${(s: :)whead}[6]}
  # env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
  [[ -n $ob && $ob != - && -z ${ob//[A-Za-z0-9.-]/} ]] && { env -i /usr/bin/open -b "$ob" 2>/dev/null &! }
  (( count )) || return 0
  [[ -n $sock ]] || api_connect || return 1
  api_write "$wbody" $count || return 1
  drops=0
  while (( got < count )); do
    read_response || return 1
    (( got++ ))
    if (( http_status == 200 )); then
      [[ $http_body == *'"dropped":true'* ]] && drops=1
    elif (( http_status == 400 )); then
      log_once "a frame was refused: ${http_body[1,300]}"
    fi
    [[ -n $sock ]] || return 1
  done
  return 0
}

coproc town_world live
exec {town_in}>&p {town_out}<&p
print -r -u $town_in -- "M live $cell $EPOCHSECONDS"
trap 'quit' TERM INT HUP
trap '' PIPE

quit() {
  trap '' TERM INT HUP
  quitting=1
  print -u $town_in Q 2>/dev/null
  integer count=0
  while world_reply -t 1; do
    [[ $whead == Q* ]] && { count=${${(s: :)whead}[3]}; break; }
  done
  (( writing )) && api_close
  if (( count )); then
    [[ -n $sock ]] || api_connect
    [[ -n $sock ]] && api_write "$wbody" $count
    while (( owed > 0 )) && [[ -n $sock ]]; do read_response || break; done
  fi
  exit 0
}

# The Mac's state is read by a helper in the background — lsappinfo, ps and netstat take 0.15–0.2 s every 2 s, and a
# loop that waited for them would stop the town's motion each time. It writes a whole snapshot and renames it into
# place; the drawing loop only picks up what is ready. It ends with the engine (the agent's TERM reaches the whole
# group; and it checks that the engine is still there).
gatherer() {
  trap 'exit 0' TERM INT HUP
  local parent=$1 line lab
  local -a apps pids ld
  local -A mem cpu
  integer pass=0 nb badge
  while kill -0 $parent 2>/dev/null; do
    (( pass++ ))
    {
    ld=( ${(M)${(f)"$(ioreg -c IOHIDSystem -d 4 -r -k HIDIdleTime 2>/dev/null)"}:#*HIDIdleTime*} )
    [[ ${ld[1]##*= } == <-> ]] && print -r -- "H $(( ${ld[1]##*= } / 1000000000 ))"
    # the open apps, most recent first (their place in the front-to-back list), with their memory and processor
    apps=( ${(f)"$(lsappinfo list 2>/dev/null | awk -v vis="$(lsappinfo visibleProcessList 2>/dev/null)" '
      /^ *[0-9]+\) "/ { n = $0; sub(/^ *[0-9]+\) "/, "", n); asn = n; sub(/" ASN:.*/, "", n); name = n; sub(/^.*" ASN:/, "", asn); sub(/:.*/, "", asn); b = "" }
      /bundleID="/ { b = $0; sub(/.*bundleID="/, "", b); sub(/".*/, "", b) }
      /pid = / { p = $3 }
      /type="Foreground"/ { if (b != "" && b !~ /[^A-Za-z0-9.-]/ && p ~ /^[0-9]+$/) { k = index(vis, "ASN:" asn "-"); print (k ? k : 999999), b, p, asn, name } }' |
      sort -n | head -40)"} )
    typeset -A mem cpu
    pids=( ${${apps#* * }%% *} )
    if (( ${#pids} )); then
      for line in ${(f)"$(ps -o pid=,rss=,%cpu= -p ${(j:,:)pids} 2>/dev/null)"}; do ld=( ${=line} ); mem[$ld[1]]=$ld[2]; cpu[$ld[1]]=$ld[3]; done
    fi
    print -r -- A
    # the Dock badges of the first sixteen (the ones with a building): a number, or 1 for a dot
    integer nb=0 badge
    for line in $apps; do
      ld=( ${=line} ); badge=0
      if (( ++nb <= 16 )); then
        lab=$(lsappinfo info -only StatusLabel "ASN:$ld[4]" 2>/dev/null)
        if [[ $lab == *'"label"="'* ]]; then lab=${lab#*\"label\"=\"}; lab=${lab%%\"*}; [[ $lab == <-> ]] && badge=$lab || { [[ -n $lab ]] && badge=1 }; fi
      fi
      print -r -- "P $ld[2] ${mem[$ld[3]]:-0} ${cpu[$ld[3]]:-0} $badge ${ld[5,-1]}"
    done
    print -r -- Z
    ld=( ${(f)"$(lsappinfo info -only bundleID "$(lsappinfo front 2>/dev/null)" 2>/dev/null)"} )
    line=${ld[1]#*=\"}; line=${line%\"}
    [[ -n $line && -z ${line//[A-Za-z0-9.-]/} ]] && print -r -- "N $line"
    # AI agents (Claude Code, Codex: sessions and their processor) and builds (compilers and linkers at work)
    ld=( $(ps -Ao pcpu=,comm= 2>/dev/null | awk '{ n = $2; sub(/.*\//, "", n); if (n == "claude" || n == "codex") { s++; c += $1 } if (n ~ /^(swift-frontend|swiftc|clang|ld|ld64|xcodebuild|swift-build)$/) b += $1 } END { print s + 0, c + 0, b + 0 }') )
    # a test: a number in test-agents stands for the sessions (to see the drones without that many agents)
    [[ -r $store/test-agents ]] && { line=$(<$store/test-agents); [[ $line == <-> ]] && ld[1]=$line ld[2]=10; }
    print -r -- "I $ld[1] $ld[2] $ld[3]"
    ld=( $(netstat -ibn 2>/dev/null | awk '$1 ~ /^en[0-9]/ && $3 ~ /Link/ { i += $7; o += $10 } END { print i + 0, o + 0 }') )
    print -r -- "W $ld[1] $ld[2] $EPOCHREALTIME"
  # the battery: every half minute (a Mac without one keeps its lamps bright)
  if (( pass % 15 == 1 )); then
    line=$(pmset -g batt 2>/dev/null)
    if [[ $line == *InternalBattery* ]]; then
      ld=( ${(M)${=line}:#<->%;} )
      print -r -- "Y ${${ld[1]%\%;}:-100} $([[ $line == *"AC Power"* ]] && print 1 || print 0) 1"
    else
      print -r -- "Y 100 1 0"
    fi
  fi

    } > $store/mac.tmp 2>/dev/null && zf_mv -f $store/mac.tmp $store/mac
    zselect -t 200
  done
}
gatherer $$ &!

while true; do
  typeset -F t0=$SECONDS
  fetch_view || vbody="-"
  if [[ $vbody != "$vlast" ]]; then vlast=$vbody; print -r -u $town_in -- "V $vbody"; fi
  if [[ -s $store/taps ]] && zf_mv -f $store/taps $store/taps.work 2>/dev/null; then
    lines=( ${(f)"$(<$store/taps.work)"} )
    zf_rm -f $store/taps.work
    for line in $lines[1,20]; do [[ -n $line && $line != *[^0-9A-Fa-f-]* ]] && print -r -u $town_in -- "F $line"; done
  fi
  if (( SECONDS - load_at >= 5 )); then
    load_at=$SECONDS
    ld=( ${=$(sysctl -n vm.loadavg hw.ncpu 2>/dev/null)} )
    (( ${#ld} >= 6 && ld[6] > 0 )) && load=$(( ld[2] / ld[6] ))
  fi
  # how long nobody touched the Mac: the HID system's idle time (nanoseconds), every 2 s
  # the Mac, as the helper last read it: the idle time stays here, the rest goes to the world
  if [[ -e $store/mac ]] && zf_mv -f $store/mac $store/mac.work 2>/dev/null; then
    for line in ${(f)"$(<$store/mac.work)"}; do
      if [[ $line == "H "* ]]; then idle=${line#H }; else print -r -u $town_in -- "$line"; fi
    done
    zf_rm -f $store/mac.work
  fi
  strftime -s hm '%H %M %u' $EPOCHSECONDS
  hm=( ${=hm} )
  print -r -u $town_in -- "S $EPOCHREALTIME $(( hm[1] * 60 + hm[2] )) $load $drops $idle $hm[3]"
  send_tick
  (( next = t0 + (shown ? period : 0.5) ))
  changed=0
  while (( ! changed )); do
    (( pause = (next - SECONDS) * 100 ))
    (( pause >= 1 )) || break
    (( shown && pause > 20 )) && pause=20
    zselect -t $pause
    (( shown && next - SECONDS > 0.05 )) || continue
    fetch_view && [[ $vbody != "$vlast" ]] && changed=1
  done
done
