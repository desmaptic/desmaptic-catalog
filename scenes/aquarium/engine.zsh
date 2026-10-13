#!/bin/zsh
# Aquarium: one living fish tank across a whole page of 1×1 Desmaptic buttons (the Gallery's «Unusual»).
#
# This is the startup script of ONE tile of the page — the engine — and it draws every tile of its page. It never
# guesses where the tiles are: it asks the agent what the phone shows (GET /api/view) and draws each tile on screen
# whose button came from this scene (Gallery entry "aquarium.r<row>c<col>") where it really stands. The grid decides
# the tank: upright (4×8 iPhone, 6×8 iPad) it is a tall deep tank — light at the surface, kelp with a seahorse, a
# moray in its rock, an anglerfish with a glowing lure at night — and turned (8×4, 8×6) a wide coral reef with garden
# eels in the sand. A tap on any tile drops food there; the nearest fish takes a pellet while the others circle it.
# The water follows the Mac's clock (dawn, day, dusk, night: moonlight and glowing plankton) and its load (a busy
# Mac clouds the water and makes the fish nervous). Now and then a sea turtle or a ray crosses the whole tank — or a
# barracuda dashes through, and everything scatters: the fish bolt, the school bursts apart, the puffer puffs up, the
# garden eels vanish into the sand and the crab freezes. The chest on the sand opens and lets out a burst of bubbles.
#
# How it is built (the ideas are in the desmaptic-widgets skill, references/scenes.md):
#   * every tile is a window onto one world, 100 units a tile: its viewBox. Neighbouring windows lie as far apart
#     as the buttons on screen (the view's cellSize and cellGap), so a creature crossing a gap is hidden behind it for
#     just as long as it takes to swim that far. Creatures cross button borders.
#   * every frame of a tile has the same elements: a creature out of reach is "parked" (collapsed, invisible, far
#     away), so the phone glides between frames instead of cross-fading. A creature shows in a tile from just outside
#     its window, and is parked again once outside — always through one frame at its real place with opacity 0: the
#     phone starts each glide from where a creature is at that moment, and a creature gliding in from the parking
#     place would fly across the tile.
#   * a creature's parts turn together about its own origin (`rotate(a 0 0)`: the phone turns each element about the
#     pivot the transform names), and the parts merged into one path all wind the same way (nonzero fill: opposite
#     windings cut holes).
#   * one loop, one keep-alive connection to the agent at 127.0.0.1:9848. A long-lived awk process holds the world and
#     writes each tick's frames as ready HTTP requests (a line "B <bytes> <requests> <shown> <period>", then exactly
#     <bytes> bytes); zsh copies them to the socket in large chunks and reads the answers back. The token reaches awk
#     through its environment and zsh writes it into the socket: it is never on a command line.
#   * few elements change their numbers in a frame, counted in every tile that shows them: few elements a creature;
#     a creature is visible in a tile only while it can be seen there within the glide; kelp sways as rigid pieces;
#     the light shafts and the sand never move; a tile with a creature gets a frame every tick, one with only slow
#     scenery every third tick, an unchanged one nothing; a change of light reaches the tiles a few at a time.
#   * between ticks it looks at the view every 0.2 s, so a turned phone gets its new tank at once. Nothing is drawn
#     while the page is not on screen, and the world waits.
#   * stopped (the agent's TERM to the whole process group), it takes its faces off every tile it drew; awk ignores
#     the TERM and ends when the pipe closes.
# Only zsh and awk — what every Mac has.
#
# Tool modes (they never touch the network):
#   zsh engine.zsh --faces faces.json      the resting and sample faces of the 6×8 page (the scene's faces.json)
#   zsh engine.zsh --cover cover.svg       the picture on the scene's Gallery card (the 8×4 reef)
#   zsh engine.zsh --dump <4|6> <portrait|landscape> <HH:MM> <step> out.json   every tile's frame at one moment
emulate -R zsh
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
# zsh keeps a here-document (the world's awk program) in a file it unlinks at once: in the script's own temp folder
TMPPREFIX="${TMPDIR:-/tmp}/zsh"
zmodload zsh/net/tcp zsh/system zsh/zselect zsh/datetime || { print -u2 -- "aquarium: a zsh module is missing"; exit 1 }
zmodload -F zsh/files b:zf_mv b:zf_rm || { print -u2 -- "aquarium: zsh module files is missing"; exit 1 }

# The world. It reads one command per line on stdin:
#   M live <cellId> | M faces | M cover | M dump <columns> <portrait|landscape> <minutes> <steps>   the first line
#   V <body of GET /api/view>   which tiles the phone shows and where       F <cellId>   a tap: food there
#   R   send every tile again on the next tick (a new connection)           Q   quit: frames that remove the faces
#   S <now, s> <minutes since midnight> <load per core> <slow: 1 while the phone is not reading>   one tick
# After every S it writes "B <bytes> <requests> <shown> <seconds to the next tick>\n", after Q the same line starting
# with "Q", and then exactly <bytes> bytes of pipelined requests.
aq_world() {
  # As a coprocess it inherits copies of its own pipes' far ends; closed here, so it sees EOF — and ends — when the
  # script ends, however it ends.
  local fd; for fd in {4..63}; do exec {fd}>&-; done 2>/dev/null
  # The agent stops a script with TERM to its whole process group: the world must outlive that TERM to write the
  # frames that take the faces off the tiles. An ignored signal stays ignored across exec; awk still ends on EOF.
  [[ $1 == live ]] && trap '' TERM INT HUP
  exec awk -f /dev/fd/3 3<<'AWK'
BEGIN {
  PI = 3.141592653589793; RAD = PI / 180
  TOKEN = ENVIRON["DESMAPTIC_TOKEN"]
  NNEON = 9; FISHA = 45; FISHAY = 25; NEONA = 80; FISHP = 90; FISHPY = 60; NEONP = 130; PERS = 0.7; PERL = 0.7; GLIDE = 1.2; GOING = 5
  # an ellipse as two cubic arcs with upright ends (within 3% of the true one; a path's subpath), a lens as two
  # quadratic ones: their unit points
  split("-1 0 1 0 -1", LNX, " "); split("0 -2 0 2 0", LNY, " ")
  split("1 1 -1 -1 -1 1 1", EUX, " "); split("0 1.333 1.333 0 -1.333 -1.333 0", EUY, " ")
  # parked twins write their curves as quadratics: the parser turns them into the same cubics, in fewer bytes
  ELLPK = "M0 0Q0 0 0 0 0 0 0 0Z"; LENSPK = ELLPK
  for (i = 1; i <= 6; i++) { HXC[i] = cos((i - 1) * PI / 3); HXS[i] = sin((i - 1) * PI / 3) }
  palettes(); species()
  GEN = 0; TICK = 0; T = 0; NOW = 0; SHOWN = 0; AGI = -1; AGIT = -100; COLS = 0; LGEN = 0; UPC = 0; KAC = 0
  # the gap between cells in world units (a window is 100): 0 until the phone says (cellSize, cellGap in the view);
  # the Gallery's sample faces and the dumps draw a typical deck's (about 12 pt between 80 pt cells)
  GAP = 0; PITCH = 100; GDEMO = 15
}

# ---------------------------------------------------------------- numbers, randomness, colour
function abs(x) { return x < 0 ? -x : x }
function mn(a, b) { return a < b ? a : b }
function mx(a, b) { return a > b ? a : b }
function cl(x, a, b) { return x < a ? a : (x > b ? b : x) }
# Numbers to a tenth; scenery that never moves (RI) to whole units: fewer bytes in every frame.
function f1(x) { return RI ? sprintf("%.0f", x) : sprintf("%.1f", x) }
function f2(x) { return sprintf("%.2f", x) }
function smooth(t) { t = cl(t, 0, 1); return t * t * (3 - 2 * t) }
function hyp(x, y) { return sqrt(x * x + y * y) }
# Park–Miller: exact in doubles, the same on every Mac (never awk's rand).
function rnd() { SEED = (SEED * 16807) % 2147483647; return SEED / 2147483647 }
function rr(a, b) { return a + (b - a) * rnd() }
function srnd() { SSEED = (SSEED * 16807) % 2147483647; return SSEED / 2147483647 }
function sr(a, b) { return a + (b - a) * srnd() }
# Bubbles and the chest draw from their own stream, so they never change what the fish do.
function brr(a, b) { BSEED = (BSEED * 16807) % 2147483647; return a + (b - a) * BSEED / 2147483647 }
function hx2(s) { return (index("0123456789ABCDEF", toupper(substr(s, 1, 1))) - 1) * 16 + index("0123456789ABCDEF", toupper(substr(s, 2, 1))) - 1 }
function rgb(h) { CR = hx2(substr(h, 2, 2)); CG = hx2(substr(h, 4, 2)); CB = hx2(substr(h, 6, 2)) }
function hexc(r, g, b) { return sprintf("#%02X%02X%02X", cl(int(r + 0.5), 0, 255), cl(int(g + 0.5), 0, 255), cl(int(b + 0.5), 0, 255)) }
function mixh(a, b, t,   r, g, bb) { rgb(a); r = CR; g = CG; bb = CB; rgb(b); return hexc(r + (CR - r) * t, g + (CG - g) * t, bb + (CB - bb) * t) }
# A colour under the light of the moment (dawn is warm, night blue and dark); cached until the light changes.
function lit(h) { if (h in LITC) return LITC[h]; rgb(h); LITC[h] = hexc(CR * LR, CG * LG, CB * LB); return LITC[h] }
# Something that shines by itself (the neon stripe, a lure) keeps most of its colour.
function glow(h, k) { return mixh(lit(h), h, k) }
# Coral fluoresces at night: its colour under the light of the moment, turning to its own neon as the night falls.
function fluo(h, f) { return mixh(lit(h), f, 0.75 * NIGHT) }
# Deeper in the tall tank a swimmer takes on more of the water's colour, so the tank has depth, not only a gradient.
# draw() sets ZB, the 20-unit depth band of the creature it draws (0: no tint); cached until the light changes.
function lz(h,   k, y) {
  if (!ZB) return lit(h)
  k = h SUBSEP ZB
  if (k in LZC) return LZC[k]
  y = ZB * 20 + 10
  LZC[k] = mixh(lit(h), wcol(y), 0.3 * smooth((y - 0.22 * H) / (0.7 * H)))
  return LZC[k]
}
# A point turned by a degrees about (cx, cy): RPX, RPY.
function rotp(px, py, cx, cy, a,   c, s) { c = cos(a * RAD); s = sin(a * RAD); RPX = cx + (px - cx) * c - (py - cy) * s; RPY = cy + (px - cx) * s + (py - cy) * c }

# ---------------------------------------------------------------- light: the Mac's clock and load
function palettes() {
  # water at 4 depths, ray colour and strength, light r g b, night, fish speed, surface crests, caustics. Dawn and dusk
  # warm the surface and the rays; the body of the water stays blue, so the tank never reads as a sky.
  PAL["n"] = "#1C476E #113455 #081E38 #030A17 #9FB8FF 0 0.42 0.52 0.74 1 0.6 0.14 0.03"
  PAL["a"] = "#F4C08E #74AED6 #22649A #0C2A52 #FFD08A 0.46 1 0.88 0.78 0.3 0.9 0.34 0.14"
  PAL["d"] = "#7FD5F5 #37A4DD #1668A6 #0B3161 #F4FDFF 0.40 1 1 1 0 1 0.42 0.22"
  PAL["u"] = "#F59A62 #6670B2 #2A3C84 #0D1437 #FFB27A 0.40 0.94 0.76 0.84 0.3 0.85 0.3 0.12"
  split("0 4.75 6.25 8.25 17.5 19.25 21 24.01", KH, " ")
  split("n n a d d u n n", KP, " ")
}
# The light of a moment. Returns 1 when the colours changed (then LGEN counts on); the same colours are not a change.
function light(minutes, agi,   h, k, t, a, b, i, key, dig) {
  key = int(minutes / 3) " " agi " " DEEP " " W
  if (key == LIGHTKEY) return 0
  LIGHTKEY = key
  h = int(minutes / 3) * 3 / 60
  for (k = 1; k < 8; k++) if (h < KH[k + 1]) break
  t = smooth((h - KH[k]) / (KH[k + 1] - KH[k]))
  split(PAL[KP[k]], a, " "); split(PAL[KP[k + 1]], b, " ")
  for (i = 1; i <= 4; i++) WC[i] = mixh(a[i], b[i], t)
  if (!DEEP) { WC[4] = mixh(WC[3], WC[4], 0.45); WC[3] = mixh(WC[2], WC[3], 0.75) }
  for (i = 1; i <= 4; i++) WC[i] = mixh(WC[i], "#4E6A56", 0.5 * agi)       # a busy Mac clouds the water
  RC = mixh(a[5], b[5], t); RA = (a[6] + (b[6] - a[6]) * t) * (1 - 0.65 * agi)
  LR = a[7] + (b[7] - a[7]) * t; LG = a[8] + (b[8] - a[8]) * t; LB = a[9] + (b[9] - a[9]) * t
  NIGHT = a[10] + (b[10] - a[10]) * t; SPD = a[11] + (b[11] - a[11]) * t
  CRA = a[12] + (b[12] - a[12]) * t; CAA = (a[13] + (b[13] - a[13]) * t) * (1 - 0.5 * agi)
  # the moon: one pale shaft and a glint under the surface, as the rays go out
  MOONA = 0.3 * NIGHT * (1 - 0.5 * agi)
  dig = WC[1] WC[2] WC[3] WC[4] RC " " RA " " LR " " LG " " LB " " NIGHT " " CRA " " CAA " " MOONA
  if (dig == LIGHTDIG) return 0
  LIGHTDIG = dig; LGEN++
  delete LITC; delete LZC
  return 1
}
# The water's colour at a depth, as the world gradient runs from the surface to the floor.
function wcol(y,   f, k) {
  f = cl(y / H, 0, 1)
  for (k = 1; k < 4; k++) if (f <= SF[k + 1]) break
  return mixh(WC[k], WC[k + 1], (f - SF[k]) / (SF[k + 1] - SF[k]))
}

# ---------------------------------------------------------------- SVG building blocks
# In park mode (PK) each block writes its parked twin: the same element, the same kind of paint, no numbers — the
# creature's parked string wraps them all in one <g opacity='0'>. It comes from the very function that draws the
# creature, so the two can never differ in structure.
function el(cx, cy, rx, ry, fill, xt) {
  if (PK) return "<ellipse/>"
  return "<ellipse cx='" f1(cx) "' cy='" f1(cy) "' rx='" f1(rx) "' ry='" f1(ry) "' fill='" fill "'" xt "/>"
}
function ci(cx, cy, r, fill, xt) {
  if (PK) return "<circle/>"
  return "<circle cx='" f1(cx) "' cy='" f1(cy) "' r='" f1(r) "' fill='" fill "'" xt "/>"
}
function re(x, y, w, h, fill, xt) {
  if (PK) return "<rect/>"
  return "<rect x='" f1(x) "' y='" f1(y) "' width='" f1(w) "' height='" f1(h) "' fill='" fill "'" xt "/>"
}
function rr_(x, y, w, h, r, fill, xt) {
  if (PK) return "<rect rx='1'/>"
  return "<rect x='" f1(x) "' y='" f1(y) "' width='" f1(w) "' height='" f1(h) "' rx='" f1(r) "' fill='" fill "'" xt "/>"
}
# A circle ringed by its stroke: an eye (a white ring round the pupil) or a glowing speck (a halo round its core) in
# one element.
function ringc(cx, cy, r, fill, sc, sw, xt) {
  if (PK) return "<circle stroke='#000'/>"
  return "<circle cx='" f1(cx) "' cy='" f1(cy) "' r='" f1(r) "' fill='" fill "' stroke='" sc "' stroke-width='" f1(sw) "'" xt "/>"
}
# An ellipse with a stroke (the neon's stripe and its night glow).
function elr(cx, cy, rx, ry, fill, sc, sw, xt) {
  if (PK) return "<ellipse stroke='#000'/>"
  return "<ellipse cx='" f1(cx) "' cy='" f1(cy) "' rx='" f1(rx) "' ry='" f1(ry) "' fill='" fill "' stroke='" sc "' stroke-width='" f1(sw) "'" xt "/>"
}
function pg(n, fill, xt,   k, s) {
  if (PK) { s = "<polygon points='0,0"; for (k = 2; k <= n; k++) s = s " 0,0"; return s "'/>" }
  s = "<polygon points='" f1(PX[1]) "," f1(PY[1])
  for (k = 2; k <= n; k++) s = s " " f1(PX[k]) "," f1(PY[k])
  return s "' fill='" fill "'" xt "/>"
}
# Several shapes of one colour in one element: a <path> of subpaths — a polygon from PX/PY, or an ellipse (four
# cubic arcs) turned by a degrees about its centre. Every subpath winds the same way (positive area, y down): the
# fill rule is nonzero, and where a fin wound one way overlaps a body wound the other, the two cancel — a hole of
# water in the fish (seen on an old iPad). A mirrored creature (its x times d) flips a shape's winding, so
# each subpath is checked as it is written and, when it winds backwards, written from its last point to its first.
function sub_poly(n,   k, s, ar) {
  if (PK) { s = "M0 0"; for (k = 2; k <= n; k++) s = s " 0 0"; return s "Z" }
  ar = 0; for (k = 1; k <= n; k++) ar += PX[k] * PY[k % n + 1] - PX[k % n + 1] * PY[k]
  if (ar >= 0) { s = "M" f1(PX[1]) " " f1(PY[1]); for (k = 2; k <= n; k++) s = s " " f1(PX[k]) " " f1(PY[k]) }
  else { s = "M" f1(PX[n]) " " f1(PY[n]); for (k = n - 1; k >= 1; k--) s = s " " f1(PX[k]) " " f1(PY[k]) }
  return s "Z"
}
# A small round spot (an eye, a speck): a hexagon — at a few points across nobody sees the corners; a diamond when
# smaller than two units (the same wherever it is: its size never changes).
function sub_dot(cx, cy, r,   k) {
  if (r < 2) { if (PK) return "M0 0 0 0 0 0 0 0Z"; PX[1] = cx + r; PY[1] = cy; PX[2] = cx; PY[2] = cy + r; PX[3] = cx - r; PY[3] = cy; PX[4] = cx; PY[4] = cy - r; return sub_poly(4) }
  if (PK) return "M0 0 0 0 0 0 0 0 0 0 0 0Z"
  for (k = 1; k <= 6; k++) { PX[k] = cx + r * HXC[k]; PY[k] = cy + r * HXS[k] }
  return sub_poly(6)
}
function sub_ell(cx, cy, rx, ry, a,   c, s, i, ux, uy, str, ar, ex, ey) {
  if (PK) return ELLPK
  c = cos(a * RAD); s = sin(a * RAD)
  for (i = 1; i <= 7; i++) { ux = EUX[i] * rx; uy = EUY[i] * ry; ex[i] = cx + ux * c - uy * s; ey[i] = cy + ux * s + uy * c }
  # the winding of the control polygon is the curve's; backwards, the arcs are written from the end (a cubic reversed
  # is its four points reversed), so the path keeps its commands
  ar = 0; for (i = 1; i <= 7; i++) ar += ex[i] * ey[i % 7 + 1] - ex[i % 7 + 1] * ey[i]
  for (i = 1; i <= 7; i++) str = str (i == 1 ? "M" : (i == 2 ? "C" : " ")) (ar >= 0 ? f1(ex[i]) " " f1(ey[i]) : f1(ex[8 - i]) " " f1(ey[8 - i]))
  return str "Z"
}
# A lens: two arcs meeting in points at ±rx, ry at its widest — a small fish's body or stripe, in few bytes.
function sub_lens(cx, cy, rx, ry, a,   c, s, i, ux, uy, str) {
  if (PK) return LENSPK
  c = cos(a * RAD); s = sin(a * RAD)
  for (i = 1; i <= 5; i++) {
    ux = LNX[i] * rx; uy = LNY[i] * ry
    str = str (i == 1 ? "M" : (i == 2 ? "Q" : " ")) f1(cx + ux * c - uy * s) " " f1(cy + ux * s + uy * c)
  }
  return str "Z"
}
function pth(d, fill, xt) { if (PK) return "<path d='" d "'/>"; return "<path d='" d "' fill='" fill "'" xt "/>" }
function pths(d, fill, sc, sw, xt) { if (PK) return "<path d='" d "' stroke='#000'/>"; return "<path d='" d "' fill='" fill "' stroke='" sc "' stroke-width='" f1(sw) "'" xt "/>" }
# Strokes with round ends: stalks, branches, blades, spines — any number of them in one element.
function strk(d, sc, sw, xt) { if (PK) return "<path d='" d "' fill='none' stroke='#000' stroke-linecap='round' stroke-linejoin='round'/>"; return "<path d='" d "' fill='none' stroke='" sc "' stroke-width='" f1(sw) "' stroke-linecap='round' stroke-linejoin='round'" xt "/>" }
function seg_(x0, y0, x1, y1) { return "M" f1(x0) " " f1(y0) "L" f1(x1) " " f1(y1) }
function bub(cx, cy, r, op) {
  if (PK) return "<circle stroke='#000'/>"
  return "<circle cx='" f1(cx) "' cy='" f1(cy) "' r='" f1(r) "' fill='#DDF5FF' fill-opacity='0.2' stroke='#EAFAFF' stroke-width='1.2' opacity='" f2(op * 0.85) "'/>"
}
function spikes(r, w) {
  if (PK) return "<circle fill='none' stroke='#000' stroke-dasharray='1 1'/>"
  return "<circle r='" f1(r) "' fill='none' stroke='" lit("#B98A2E") "' stroke-width='" f1(w) "' stroke-dasharray='1.6 4'/>"
}
function rot(a, x, y) { return " transform='rotate(" f1(a) " " f1(x) " " f1(y) ")'" }
# The same inside a swaying kelp stalk: its turns (KT) first, then the element's own.
function tr_(a, x, y) {
  if (KT == "") return a == 0 ? "" : rot(a, x, y)
  return " transform='" KT (a == 0 ? "" : " rotate(" f1(a) " " f1(x) " " f1(y) ")") "'"
}
# The creature's turn names its pivot, the creature's own origin (`rotate(a 0 0)`, never `rotate(a)`): the phone carries
# that pivot to every part, so the body, fins and tail turn about one point and glide as one piece. Without it each part
# turns about its own centre and the parts drift apart in every glide whose angle changes (seen on an old iPad).
function gin(x, y, a, op, sc) { return PK ? "" : "<g transform='translate(" f1(x) " " f1(y) ") rotate(" f1(a) " 0 0)" (sc ? " scale(" sc ")" : "") "'" (op < 1 ? " opacity='" f2(op) "'" : "") ">" }
function gout() { return PK ? "" : "</g>" }
function sandy(x) { return FLOOR + 4.5 * sin(x * 0.021 + 0.5) + 2.5 * sin(x * 0.067 + 1.3) }

# ---------------------------------------------------------------- the cast
function species() {
  # name L height/L body fin tail cruise(units/s) depth range (share of the tank); the marks — "cx cy rx ry rotation",
  # ";"-separated, all of one colour (SPMC) and one outline (SPMS): one element whatever their number; and where the
  # tail goes (TLW): into the body's path ("b") or the marks' ("m") when it has their colour, or its own element
  # ("t": the regal tang's yellow tail). The ranges spread the cast over the whole height of a tall tank, the floor
  # included.
  SPC = 7
  SPS[1] = "clown 46 0.5 #FF7A1A #FF9C52 #FF8A34 34 0.12 0.95"
  SPM[1] = "5.8 0 2.6 10.6 0;-7.4 0 2.4 9.8 0"; SPMC[1] = "#FFFFFF"; SPMS[1] = "#1C1C1E"; TLW[1] = "b"
  SPS[2] = "tang 58 0.56 #2E6BFF #1E44B8 #FFD60A 30 0.08 0.7"
  SPM[2] = "2 -3.5 16 5 -8;-9 3.5 8 3 18"; SPMC[2] = "#0D1B4E"; TLW[2] = "t"
  SPS[3] = "ytang 50 0.78 #FFD60A #FFE56E #FFD23A 32 0.2 0.8"
  SPM[3] = "-14 3 3.2 1.2 0"; SPMC[3] = "#FFFFFF"; TLW[3] = "b"
  SPS[4] = "angel 44 0.85 #D8E2EA #BFCCD8 #C4D1DC 24 0.4 0.94"
  SPM[4] = "7 0 2.2 16 0;-1 0 2.3 17.6 0;-9 0 2 14 0"; SPMC[4] = "#2B303A"; TLW[4] = "b"
  SPS[5] = "gramma 40 0.52 #A45CFF #B87CFF #FFC933 35 0.3 0.95"
  SPM[5] = "-6.5 0 9.4 9.8 0"; SPMC[5] = "#FFC933"; TLW[5] = "m"
  SPS[6] = "puffer 36 1 #EFCB66 #E0B24E #D9AE4E 18 0.55 0.98"
  SPM[6] = ""
  SPS[7] = "wrasse 54 0.34 #FF5FA2 #FFA0C8 #5AC8FA 38 0.02 0.5"
  SPM[7] = "11 0 9.4 7.6 0"; SPMC[7] = "#4FA8FF"; TLW[7] = "m"
}

function cast(   m, s, a, j) {
  NM = 0
  for (s = 1; s <= SPC; s++) {
    m = ++NM; MK[m] = "fish"; ML[m] = 11; SP[m] = s
    split(SPS[s], a, " "); SPN[m] = a[1]; FL[m] = a[2]; FH[m] = a[2] * a[3]; CB_[m] = a[4]; CF_[m] = a[5]; CT_[m] = a[6]; CRU[m] = a[7]; DMIN[m] = a[8]; DMAX[m] = a[9]
    D[m] = rnd() < 0.5 ? -1 : 1; WPH[m] = rr(0, 6.3); PIT[m] = 0; PUF[m] = 0; PUFT[m] = 0
  }
  # the neons swim each on its own, but are drawn as one mover: the school (SCH)
  NEON0 = NM + 1
  for (j = 0; j < NNEON; j++) { m = ++NM; MK[m] = "neon"; ML[m] = 0; D[m] = 1; NA[m] = j * 2 * PI / NNEON + rr(-0.3, 0.3); NR_[m] = rr(0.45, 1); NP_[m] = rr(-6, 6); NK_X[m] = 0; NK_Y[m] = 0 }
  NEON1 = NM
  SCH = ++NM; MK[SCH] = "school"; ML[SCH] = 12
  CRAB = ++NM; MK[CRAB] = "crab"; ML[CRAB] = 7
  ANG = ++NM; MK[ANG] = "angler"; ML[ANG] = 9; D[ANG] = 1
  # the lure, with its glow, is its own mover (the body's box stays small); it follows ANG
  ANGL = ++NM; MK[ANGL] = "lure"; ML[ANGL] = 9
  TUR = ++NM; MK[TUR] = "turtle"; ML[TUR] = 10; D[TUR] = 1
  # the ray's long whip tail is its own thin mover (the wings' box stays small); it follows RAY
  RAYT = ++NM; MK[RAYT] = "raytail"; ML[RAYT] = 10
  RAY = ++NM; MK[RAY] = "ray"; ML[RAY] = 10; D[RAY] = 1
  # the rare fast guest: a barracuda dashes through and scares everything (drawn above the fish it passes)
  BAR = ++NM; MK[BAR] = "barracuda"; ML[BAR] = 11; D[BAR] = 1; WAG[BAR] = 6; WPH[BAR] = 0
  FOOD0 = NM + 1
  for (j = 0; j < 5; j++) { m = ++NM; MK[m] = "food"; ML[m] = 8; PH[m] = 0; SEEDF[m] = rr(0, 6.3); FC_[m] = j % 3 ? "#FFB252" : "#F08A3C" }
  FOOD1 = NM
  BUB0 = NM + 1
  for (j = 0; j < 5; j++) { m = ++NM; MK[m] = "bub"; ML[m] = 14; PH[m] = 0; BR_[m] = rr(2.4, 5.4); SEEDF[m] = rr(0, 6.3) }
  BUB1 = NM
  # parked: far away and invisible. A creature never glides between here and a place where it shows: a frame reaches
  # the phone while the last glide still runs, and the next glide starts from where the creature is at that moment —
  # thousands of units away, so it would fly in across the tile. It comes and goes through one frame at its real place
  # with opacity 0 (compose): the glide between that and the parked twin is invisible at both ends, and the phone jumps it.
  PK = 1; for (m = 1; m <= NM; m++) PARK[m] = draw(m, 0); PK = 0
  CAST = 1
}

# First placement, or the same creatures moved into a world of another shape (the phone turned).
function place_cast(ow, oh,   m) {
  for (m = 1; m <= NM; m++) {
    if (MK[m] == "fish") {
      if (ow) { X[m] = X[m] * W / ow; Y[m] = Y[m] * H / oh } else { X[m] = rr(60, W - 60); retarget(m); Y[m] = TYF[m] }
      # its depth band: where it swims and feeds, and the tiles that carry it
      FBT[m] = DMIN[m] * (FLOOR - 40) + 20 - 30; FBB[m] = DMAX[m] * (FLOOR - 40) + 20 + 30
      Y[m] = cl(cl(Y[m], 40, FLOOR - 50), FBT[m], FBB[m]); VX[m] = 0; VY[m] = 0; RT[m] = 0; ACT[m] = 1
    }
  }
  if (ow) { SCX = SCX * W / ow; SCY = SCY * H / oh } else { SCX = W * 0.3; SCY = H * 0.35 }
  SCY = cl(SCY, 60, FLOOR - 90); SRT = 0; SCAT = 0
  for (m = NEON0; m <= NEON1; m++) { X[m] = SCX + rr(-20, 20); Y[m] = SCY + rr(-10, 10); ACT[m] = 1; if (!ow) { VX[m] = 0; VY[m] = 0 } }
  ACT[SCH] = 1
  X[CRAB] = ow ? cl(X[CRAB] * W / ow, 50, W - 50) : W * 0.35; ACT[CRAB] = 1; CRW = 0; CRT = 1
  # a guest on its way keeps crossing the new tank; the first one comes soon after the page first shows
  if (ow) { for (m = TUR; m <= BAR; m++) if (ACT[m]) { X[m] = X[m] * W / ow; GY = cl(GY * H / oh, GB0, GB1); Y[m] = GY } }
  else { ACT[TUR] = 0; ACT[RAY] = 0; ACT[BAR] = 0; if (GNEXT > T + 40) GNEXT = T + rr(25, 40) }
  if (!DEEP) ACT[ANG] = 0
  else if (ACT[ANG] && ow) { X[ANG] = X[ANG] * W / ow; Y[ANG] = cl(Y[ANG] * H / oh, AB0, AB1) }
  for (m = FOOD0; m <= BUB1; m++) { PH[m] = 0; ACT[m] = 0; RSP[m] = 0 }
  for (m = 1; m <= NM; m++) PBT[m] = 0
}

# ---------------------------------------------------------------- drawing the creatures (world coordinates)
function draw(m, op,   k) {
  k = MK[m]
  ZB = DEEP && !PK && (k == "fish" || k == "neon" || k == "turtle" || k == "ray" || k == "barracuda") ? int(Y[m] / 20) : 0
  if (k == "fish") return SPN[m] == "puffer" ? d_puffer(m, op) : d_fish(m, op)
  if (k == "neon") return d_neon(m, op)
  if (k == "school") return d_school(op)
  if (k == "bub") return bub(X[m], Y[m], BR_[m], op)
  if (k == "food") return rr_(X[m] - 3.2, Y[m] - 3.2, 6.4, 6.4, 2, lit(FC_[m]), rot(FROT[m], X[m], Y[m]) " opacity='" f2(op) "'")
  if (k == "crab") return d_crab(m, op)
  if (k == "angler") return d_angler(m, op)
  if (k == "lure") return d_lure(op)
  if (k == "turtle") return d_turtle(m, op)
  if (k == "ray") return d_ray(m, op)
  if (k == "barracuda") return d_barracuda(m, op)
  if (k == "raytail") return gin(X[RAY], Y[RAY], 0, op) rr_(D[RAY] > 0 ? -102 : 30, -1.2, 72, 2.4, 1.2, lz("#2B3A48"), rot(4 * sin(RPH * 0.7), -D[RAY] * 30, 0)) gout()
}

# A fish swims in its own coordinates (facing right, centre at 0 0); `D` runs from 1 to -1 through a turn, so a
# turn squashes it through a head-on view. The group moves it and tilts it with its climb. Three or four elements:
# the body with both fins (one path), the species' marks (one ellipse, or one path of several), the eye (a pupil in
# its white ring) — and the tail, wagging about its root, inside the body's path or the marks' when it has their
# colour, else on its own.
function d_fish(m, op,   L, h, d, q, a, b, bx, tx, s, n, i, mk, v, tall, sb, sc, sp, tl, ts, w) {
  L = FL[m]; h = FH[m]; d = D[m]; q = 0.3 + 0.7 * abs(d); a = 0.36 * L * q; b = h / 2; sp = SP[m]; tl = TLW[sp]
  tall = SPN[m] == "angel" ? 1 : 0
  s = gin(X[m], Y[m], PIT[m], op)
  bx = -d * 0.78 * a; tx = -d * (a + 0.3 * L); w = wag(m)
  PX[1] = bx; PY[1] = -0.13 * h; PX[2] = tx; PY[2] = -0.52 * h * (tall ? 0.7 : 1); PX[3] = tx + d * 0.09 * L; PY[3] = 0
  PX[4] = tx; PY[4] = 0.52 * h * (tall ? 0.7 : 1); PX[5] = bx; PY[5] = 0.13 * h
  if (tl == "t") { s = s pg(5, lz(CT_[m]), rot(w, bx, 0)); ts = "" }
  else { for (i = 1; i <= 5; i++) { rotp(PX[i], PY[i], bx, 0, w); PX[i] = RPX; PY[i] = RPY }; ts = sub_poly(5) }
  PX[1] = d * 0.25 * a; PY[1] = -0.44 * h; PX[2] = -d * (tall ? 0.95 : 0.4) * a; PY[2] = -h * (tall ? 1.3 : 0.84); PX[3] = -d * 0.78 * a; PY[3] = -0.36 * h
  sb = sub_poly(3)
  PX[1] = d * 0.05 * a; PY[1] = 0.42 * h; PX[2] = -d * (tall ? 0.95 : 0.36) * a; PY[2] = h * (tall ? 1.25 : 0.7); PX[3] = -d * 0.62 * a; PY[3] = 0.36 * h
  s = s pth((tl == "b" ? ts : "") sb sub_poly(3) sub_ell(0, 0, a, b, 0), lz(CB_[m]))
  n = split(SPM[sp], mk, ";")
  if (n == 1 && tl != "m") { split(mk[1], v, " "); s = s el(d * v[1] * q, v[2], v[3] * q, v[4], lz(SPMC[sp]), v[5] == 0 ? "" : rot(v[5] * (d < 0 ? -1 : 1), d * v[1] * q, v[2])) }
  else {
    sb = tl == "m" ? ts : ""
    for (i = 1; i <= n; i++) { split(mk[i], v, " "); sb = sb sub_ell(d * v[1] * q, v[2], v[3] * q, v[4], v[5] * (d < 0 ? -1 : 1)) }
    sc = SPMS[sp]
    s = s (sc == "" ? pth(sb, lz(SPMC[sp])) : pths(sb, lz(SPMC[sp]), lz(sc), 1.1))
  }
  s = s ringc(d * 0.63 * a, -0.14 * h, 0.058 * L, "#0B1620", lz("#F4FAFF"), 0.036 * L)
  return s gout()
}

function d_puffer(m, op,   d, q, r, s, bx, i) {
  d = D[m]; q = 0.45 + 0.55 * abs(d); r = 14.5 * (1 + 0.5 * PUF[m])
  s = gin(X[m], Y[m], PIT[m] * 0.5, op)
  bx = -d * (r - 2)
  PX[1] = bx; PY[1] = -3; PX[2] = -d * (r + 9); PY[2] = -7.5; PX[3] = -d * (r + 6.5); PY[3] = 0; PX[4] = -d * (r + 9); PY[4] = 7.5; PX[5] = bx; PY[5] = 3
  for (i = 1; i <= 5; i++) { rotp(PX[i], PY[i], bx, 0, wag(m)); PX[i] = RPX; PY[i] = RPY }
  s = s spikes(r + 2.5, 4.4 * PUF[m])
  s = s pth(sub_poly(5) sub_ell(0, 0, r * q, r, 0), lz(CB_[m])) el(0, r * 0.38, r * 0.8 * q, r * 0.5, lz("#FAEBC4"))
  s = s pth(sub_dot(-d * r * 0.3 * q, -r * 0.52, 2.2) sub_dot(d * r * 0.08 * q, -r * 0.66, 1.9) sub_dot(-d * r * 0.62 * q, -r * 0.1, 1.8), lz("#A8783A"))
  s = s ringc(d * r * 0.54 * q, -r * 0.21, r * 0.165, "#1B1B22", lz("#FFFFFF"), r * 0.13)
  return s gout()
}

# A neon tetra: its red lower half and the stripe that shines by itself, with a glow round it at night.
function d_neon(m, op,   d, q, s) {
  d = D[m]; q = 0.3 + 0.7 * abs(d)
  s = gin(X[m], Y[m], PIT[m], op)
  s = s el(-d * 1.6 * q, 0.7, 7.4 * q + 0.8, 2.6, glow("#D8344F", 0.4))
  s = s elr(d * 1.2 * q, -0.9, 6.4 * q + 0.4, 1.5, "#3DEBFF", "#3DEBFF", 3.2, " stroke-opacity='" f2(0.28 * NIGHT) "'")
  return s gout()
}

# The whole school in two elements, whatever it does: every red body in one path, every stripe (and its night glow)
# in another. Each neon is placed, turned and squashed by its own numbers inside them.
function d_school(op,   m, d, q, c, s, P, bd, sd, lx, ly) {
  bd = ""; sd = ""; ZB = DEEP && !PK ? int(SCY / 20) : 0
  for (m = NEON0; m <= NEON1; m++) {
    d = D[m]; q = 0.3 + 0.7 * abs(d); P = PIT[m]; c = cos(P * RAD); s = sin(P * RAD)
    lx = -d * 1.6 * q; ly = 0.7; bd = bd sub_lens(X[m] + lx * c - ly * s, Y[m] + lx * s + ly * c, 8.2 * q + 0.9, 2.7, P)
    lx = d * 1.2 * q; ly = -0.9; sd = sd sub_lens(X[m] + lx * c - ly * s, Y[m] + lx * s + ly * c, 7.2 * q + 0.5, 1.6, P)
  }
  return pth(bd, lz(glow("#D8344F", 0.4)), op < 1 ? " opacity='" f2(op) "'" : "") pths(sd, "#3DEBFF", "#3DEBFF", 3.2, " stroke-opacity='" f2(0.28 * NIGHT) "'" (op < 1 ? " opacity='" f2(op) "'" : ""))
}

# The crab: its legs one stroked path a side, the claws, the body, both eyes in one path.
function d_crab(m, op,   s, k, sd, ax, ay, sw, lift, legc, cx, cy, ld, a) {
  s = gin(X[m], sandy(X[m]), 0, op); legc = lit("#B8400F")
  # resting it lifts its claws for a moment every few seconds, and is still in between
  lift = CRW ? 0 : 6 * smooth(1 - abs((CRV % 4.5) - 1))
  for (sd = -1; sd <= 1; sd += 2) {
    ld = ""
    for (k = 0; k < 2; k++) {
      sw = CRW ? 12 * sin(T * 2.99) * (k % 2 ? 1 : -1) : 0
      ax = sd * (9 + k * 6); ay = -12; a = -sd * (44 + k * 28) + sw
      if (PK) ld = ld "M0 0L0 0"
      else { rotp(ax, ay + 1.5, ax, ay, a); ld = ld "M" f1(RPX) " " f1(RPY); rotp(ax, ay + 15, ax, ay, a); ld = ld "L" f1(RPX) " " f1(RPY) }
    }
    s = s strk(ld, legc, 3)
  }
  for (sd = -1; sd <= 1; sd += 2) {
    cx = sd * 19.5; cy = -25 - lift
    s = s el(cx, cy, 6.6, 5, lit("#F26B3A"), rot(-sd * (24 + 2 * lift), cx, cy))
  }
  s = s el(0, -14.5, 17, 10.5, lit("#E4572E"))
  s = s pth(sub_dot(-4.8, -27.5, 2.7) sub_dot(4.8, -27.5, 2.7), "#16181C")
  return s gout()
}

# The anglerfish: a dark body (its tail in the same path) lit from the front by its own lure, a few needle fangs (one
# path). The lure (d_lure) is the brightest thing in the night tank.
function d_angler(m, op,   d, s, k, sb, g, i) {
  d = D[m]
  s = gin(X[m], Y[m], PIT[m], op, 1.35)
  PX[1] = -d * 22; PY[1] = -3; PX[2] = -d * 38; PY[2] = -13; PX[3] = -d * 34; PY[3] = 0; PX[4] = -d * 38; PY[4] = 13; PX[5] = -d * 22; PY[5] = 3
  for (i = 1; i <= 5; i++) { rotp(PX[i], PY[i], -d * 22, 0, 9 * sin(T * 1.9)); PX[i] = RPX; PY[i] = RPY }
  g = 1 + 0.12 * sin(LP * 2.3)
  s = s pth(sub_poly(5) sub_ell(0, 0, 26, 19, 0), lit("#3A2E46"))
  # the lure's light on the forehead and the upper body facing it
  s = s el(d * 9, -8.5, 19, 12, "#8DFFC8", " fill-opacity='" f2(0.2 * g) "'")
  s = s el(d * 19, 6.5, 9, 6.5, "#0E0A12")
  # a few needle fangs, well apart (a row of them reads as a zigzag at deck size): two from above, one from below
  sb = ""
  for (k = 0; k < 3; k++) {
    if (k < 2) { PX[1] = d * (11.5 + k * 7.5); PY[1] = 2.2; PX[2] = d * (12.4 + k * 7.5); PY[2] = 8.6 - k * 1.4; PX[3] = d * (13.4 + k * 7.5); PY[3] = 2.2 }
    else { PX[1] = d * 15.2; PY[1] = 11.4; PX[2] = d * 16.1; PY[2] = 6.4; PX[3] = d * 17; PY[3] = 11.4 }
    sb = sb sub_poly(3)
  }
  s = s pth(sb, glow("#CFC6B0", 0.2))
  s = s ringc(d * 10, -8, 3, "#0E0A12", glow("#E6F5D8", 0.6), 2.8)
  return s gout()
}
# The lure on its rod: its core, and one glow of two strengths (a fill and a wide faint stroke).
function lure_tip(   d, bx, by, a) { d = D[ANG]; bx = d * 7; by = -17; a = d * (36 + 7 * sin(LP)); LTX = bx + 27 * sin(a * RAD); LTY = by - 27 * cos(a * RAD); LTA = a; LBX = bx; LBY = by }
function d_lure(op,   s, g) {
  g = 1 + 0.12 * sin(LP * 2.3); lure_tip()
  s = gin(X[ANG], Y[ANG], PIT[ANG], op, 1.35)
  s = s rr_(LBX - 1.1, LBY - 27, 2.2, 27, 1.1, glow("#6E6078", 0.5), rot(LTA, LBX, LBY))
  s = s ringc(LTX, LTY, 11 * g, "#8DFFC8", "#8DFFC8", 36 * g, " fill-opacity='0.2' stroke-opacity='0.07'")
  s = s ci(LTX, LTY, 4.4, "#F2FFE4")
  return s gout()
}

function d_turtle(m, op,   d, s, p, far, near, nf) {
  d = D[m]; p = TPH; far = lz("#56753A"); near = lz("#7C9C4E")
  s = gin(X[m], Y[m], 3 * sin(p * 0.5), op)
  s = s el(d * 24, 24, 6, 20, far, rot(d * (34 + 26 * sin(p + 0.7)), d * 24, 7))
  s = s el(0, 9, 34, 9, lz("#D8CB8E")) el(0, -3, 38, 21, lz("#6F8E3D"))
  s = s el(d * 45, 1, 12.5, 8.5, lz("#8BAA5C"))
  s = s pth(sub_ell(-d * 17, -6, 8.5, 6.5, 0) sub_ell(0, -10, 9.5, 7, 0) sub_ell(d * 17, -6, 8.5, 6.5, 0) sub_dot(d * 50, -1.5, 2), lz("#4A6526"))
  # the near flippers, both in one path: they turn about their roots
  rotp(-d * 25, 21, -d * 25, 12, d * (38 + 16 * sin(p + 1))); nf = sub_ell(RPX, RPY, 5, 11, d * (38 + 16 * sin(p + 1)))
  rotp(d * 19, 26, d * 19, 8, d * (30 + 30 * sin(p))); nf = nf sub_ell(RPX, RPY, 7, 22, d * (30 + 30 * sin(p)))
  s = s pth(nf, near)
  return s gout()
}

# An eagle ray seen from above, wings beating: the one creature whose outline changes, and there is only one.
function d_ray(m, op,   d, s, f, c, sb) {
  d = D[m]; f = 0.72 + 0.28 * cos(RPH); c = lz("#34495E")
  s = gin(X[m], Y[m], 0, op)
  PX[1] = d * 40; PY[1] = 0; PX[2] = d * 31; PY[2] = -8; PX[3] = d * 8; PY[3] = -24 * f; PX[4] = -d * 14; PY[4] = -60 * f
  PX[5] = -d * 17; PY[5] = -42 * f; PX[6] = -d * 27; PY[6] = -11; PX[7] = -d * 33; PY[7] = 0; PX[8] = -d * 27; PY[8] = 11
  PX[9] = -d * 17; PY[9] = 42 * f; PX[10] = -d * 14; PY[10] = 60 * f; PX[11] = d * 8; PY[11] = 24 * f; PX[12] = d * 31; PY[12] = 8
  s = s pg(12, c)
  s = s el(d * 6, 0, 27, 8, lz("#44607A"))
  sb = sub_dot(d * 2, -24 * f, 2.6) sub_dot(-d * 9, -37 * f, 2.2) sub_dot(-d * 14, -20 * f, 2)
  sb = sb sub_dot(d * 2, 24 * f, 2.6) sub_dot(-d * 9, 37 * f, 2.2) sub_dot(-d * 14, 20 * f, 2)
  s = s pth(sb, lz("#E8F1F7"))
  s = s pth(sub_dot(d * 25, -5, 1.9) sub_dot(d * 25, 5, 1.9), "#0D1319")
  return s gout()
}

# A barracuda: long, silver, the lower jaw jutting past the upper. It never turns (it crosses the tank one way, fast),
# so it is drawn in profile, its x times D. Four elements: the body with its fins (one path), the pale belly, the dark
# marks — the slanted bars along the back, the forked tail wagging about its root, the line of the jaw (one path) — and
# the eye. Drawn at 1.2 times these numbers: half as long again as the big fish, and slim.
function d_barracuda(m, op,   d, s, bd, mk, w, i) {
  d = D[m]; w = wag(m)
  s = gin(X[m], Y[m], 0, op, 1.2)
  bd = sub_ell(-d * 2, 0, 50, 7.6, 0)
  PX[1] = d * 30; PY[1] = -5.6; PX[2] = d * 57; PY[2] = -1.6; PX[3] = d * 61; PY[3] = 1.4; PX[4] = d * 55; PY[4] = 3.6; PX[5] = d * 30; PY[5] = 5.6
  bd = bd sub_poly(5)
  PX[1] = d * 6; PY[1] = -6.8; PX[2] = -d * 3; PY[2] = -15.5; PX[3] = -d * 10; PY[3] = -6.6; bd = bd sub_poly(3)
  PX[1] = -d * 30; PY[1] = -5; PX[2] = -d * 37; PY[2] = -11.5; PX[3] = -d * 41; PY[3] = -4.2; bd = bd sub_poly(3)
  PX[1] = -d * 30; PY[1] = 5; PX[2] = -d * 37; PY[2] = 10.5; PX[3] = -d * 41; PY[3] = 4.2; bd = bd sub_poly(3)
  PX[1] = d * 4; PY[1] = 6.8; PX[2] = -d * 4; PY[2] = 12; PX[3] = -d * 8; PY[3] = 6.6; bd = bd sub_poly(3)
  s = s pth(bd, lz("#98AAB6"))
  s = s el(-d * 3, 3.2, 38, 2.4, lz("#DDE6EB"))
  PX[1] = -d * 47; PY[1] = -2.6; PX[2] = -d * 66; PY[2] = -13.5; PX[3] = -d * 59; PY[3] = 0; PX[4] = -d * 66; PY[4] = 13.5; PX[5] = -d * 47; PY[5] = 2.6
  for (i = 1; i <= 5; i++) { rotp(PX[i], PY[i], -d * 48, 0, w); PX[i] = RPX; PY[i] = RPY }
  mk = sub_poly(5)
  for (i = 0; i < 6; i++) mk = mk sub_ell(d * (26 - 12 * i), -2.9, 1.4, 3, d * 18)
  mk = mk sub_ell(d * 49, 1.3, 5.5, 0.6, -d * 6)
  s = s pth(mk, lz("#3D4D59"))
  s = s ringc(d * 42, -1.8, 1.9, "#0B1620", lz("#E4D8A6"), 1.2)
  return s gout()
}

# Box a creature can draw in.
function mbox(m,   k, h, r) {
  k = MK[m]
  if (k == "fish") {
    if (SPN[m] == "puffer") { r = 14.5 * (1 + 0.5 * PUF[m]) + 13; B0X[m] = X[m] - r; B1X[m] = X[m] + r; B0Y[m] = Y[m] - r; B1Y[m] = Y[m] + r; return }
    h = SPN[m] == "angel" ? FH[m] * 1.35 : FH[m] * 0.9
    B0X[m] = X[m] - (D[m] > 0 ? 0.68 : 0.42) * FL[m]; B1X[m] = X[m] + (D[m] > 0 ? 0.42 : 0.68) * FL[m]; B0Y[m] = Y[m] - h - 3; B1Y[m] = Y[m] + h + 3; return
  }
  if (k == "neon") { B0X[m] = X[m] - 11; B1X[m] = X[m] + 11; B0Y[m] = Y[m] - 6; B1Y[m] = Y[m] + 6; return }
  if (k == "school") { B0X[m] = 1e9; B1X[m] = -1e9; B0Y[m] = 1e9; B1Y[m] = -1e9; for (h = NEON0; h <= NEON1; h++) { B0X[m] = mn(B0X[m], X[h] - 11); B1X[m] = mx(B1X[m], X[h] + 11); B0Y[m] = mn(B0Y[m], Y[h] - 6); B1Y[m] = mx(B1Y[m], Y[h] + 6) }; return }
  if (k == "bub") { r = BR_[m] + 1.5; B0X[m] = X[m] - r; B1X[m] = X[m] + r; B0Y[m] = Y[m] - r; B1Y[m] = Y[m] + r; return }
  if (k == "food") { B0X[m] = X[m] - 5; B1X[m] = X[m] + 5; B0Y[m] = Y[m] - 5; B1Y[m] = Y[m] + 5; return }
  if (k == "crab") { B0X[m] = X[m] - 36; B1X[m] = X[m] + 36; B0Y[m] = sandy(X[m]) - 40; B1Y[m] = sandy(X[m]) + 6; return }
  if (k == "angler") { B0X[m] = X[m] - 54; B1X[m] = X[m] + 54; B0Y[m] = Y[m] - 32; B1Y[m] = Y[m] + 28; return }
  if (k == "lure") { lure_tip(); r = 1.35 * 32
    B0X[m] = mn(X[ANG] + 1.35 * LTX - r, X[ANG] + 1.35 * LBX - 3); B1X[m] = mx(X[ANG] + 1.35 * LTX + r, X[ANG] + 1.35 * LBX + 3)
    B0Y[m] = mn(Y[ANG] + 1.35 * LTY - r, Y[ANG] + 1.35 * LBY - 3); B1Y[m] = mx(Y[ANG] + 1.35 * LTY + r, Y[ANG] + 1.35 * LBY + 3); return }
  if (k == "turtle") { B0X[m] = X[m] - 60; B1X[m] = X[m] + 60; B0Y[m] = Y[m] - 28; B1Y[m] = Y[m] + 52; return }
  if (k == "ray") { B0X[m] = X[m] - 44; B1X[m] = X[m] + 44; B0Y[m] = Y[m] - 62; B1Y[m] = Y[m] + 62; return }
  if (k == "barracuda") { B0X[m] = X[m] - 82; B1X[m] = X[m] + 82; B0Y[m] = Y[m] - 20; B1Y[m] = Y[m] + 18; return }
  if (k == "raytail") { B0X[m] = X[RAY] + (D[RAY] > 0 ? -104 : 28); B1X[m] = B0X[m] + 76; B0Y[m] = Y[RAY] - 8; B1Y[m] = Y[RAY] + 8; return }
}
function speed_of(m) { return hyp(VX[m], VY[m]) }

# ---------------------------------------------------------------- the world: layout of a tank of this shape
function world(cols, ori,   ow, oh) {
  ow = W; oh = H
  COLS = cols; ORI = ori
  # tiles across and down; a window is 100 units, and the gap between two cells on the phone (GAP, in the same units)
  # is world too — hidden behind the gap, as behind the bars of a window — so a creature crossing it is where it
  # should be on the other side, instead of jumping by the gap
  if (ori == "landscape") { NTA = 8; NTD = cols } else { NTA = cols; NTD = 8 }
  PITCH = 100 + GAP; W = NTA * PITCH - GAP; H = NTD * PITCH - GAP
  DEEP = H > W ? 1 : 0
  GEN++
  FLOOR = H - (DEEP ? 34 : 36)
  if (DEEP) { SF[1] = 0; SF[2] = 0.08; SF[3] = 0.45; SF[4] = 1 } else { SF[1] = 0; SF[2] = 0.15; SF[3] = 0.62; SF[4] = 1 }
  AB0 = H - 200; AB1 = H - 100                                   # where the anglerfish patrols
  if (DEEP) { GB0 = 0.24 * H; GB1 = 0.56 * H } else { GB0 = 0.3 * H; GB1 = mx(0.52 * H, 0.3 * H + 40) }
  LIGHTKEY = ""
  geometry()
  if (!CAST) cast()
  place_cast(ow, oh)
  bucket()
  delete TST
}

function geometry(   n, x) {
  SSEED = 7919 + COLS * 101 + DEEP * 13
  shafts()
  # the scene's centrepieces stand whole in one tile: no gap ever cuts the chest or the moray's head
  CHX = PITCH * (DEEP ? (NTA > 4 ? 3 : 2) : 4) + 50             # the middle of one tile
  HS = DEEP ? 1 : 1 + (H - 400) / 500                             # a taller reef on a taller page
  MRX = PITCH * int(NTA * 0.27) + 12                            # the rock with the moray's hole
  ND = 0; NG = 0; NK = 0; EELG = 0; EMOVE = 0; NEEL = 0; delete GD0; delete GD1; delete GEV
  if (DEEP) {
    kelp(W * 0.1, H * 0.66, 0, 1, 1); kelp(W * 0.43, H * (NTA > 4 ? 0.34 : 0.26), 0, 1, 0); kelp(W * 0.91, H * (NTA > 4 ? 0.74 : 0.52), 1, 1, 0)
    ANX = -1000; EELX = -1000
  } else {
    kelp(186, 118 * HS, 0, 0, 0); kelp(668, 150 * HS, 1, 0, 0); kelp(704, 96 * HS, 0, 0, 0)
    ANX = 540; anemone()
    EELX = 352; eels()
  }
  chest_group()
  if (DEEP) moray()
  crests()
  caustics()
  plankton()
  statics()
}

# ---------------------------------------------------------------- light shafts
# Two or three long shafts falling from the upper right, all at one slope, each a turned rectangle whose gradient
# fades it along its length (two of them: a soft wide one and a brighter core). They never move: a change of light
# is their only change.
function shafts(   r) {
  NSH = DEEP ? (NTA > 4 ? 3 : 2) : 3
  RL = DEEP ? H * 0.8 : H * 0.98
  RSL = DEEP ? 0.21 : 0.28; RANG = atan2(RSL, 1) / RAD
  for (r = 1; r <= NSH; r++) { RX[r] = W * (r - 0.5) / NSH + sr(-22, 22) + (DEEP ? 80 : 70); RWD[r] = sr(40, 56); ROP[r] = sr(0.7, 1) }
  MOONR = int(NSH / 2) + 1                                        # the shaft the moon keeps at night
}
function ray_x(r, y) { return RX[r] - RSL * y }
# A shaft's colour: the day's rays, and at night the moon's one pale shaft.
function ray_col(n) { return n == MOONR && MOONA > RA ? mixh(RC, "#DCE6FF", NIGHT) : RC }
function shaft_str(r,   x0, len, st, g, w) {
  x0 = ray_x(r, -40); len = (RL + 40) / cos(RANG * RAD); st = ROP[r] * RA + (r == MOONR ? MOONA : 0)
  g = "r"; w = RWD[r]
  return "<rect x='" f1(x0 - 0.8 * w) "' y='-40' width='" f1(1.6 * w) "' height='" f1(len) "' fill='url(#" g ")' fill-opacity='" f2(0.3 * st) "'" rot(RANG, x0, -40) "/>" \
         "<rect x='" f1(x0 - 0.24 * w) "' y='-40' width='" f1(0.48 * w) "' height='" f1(len) "' fill='url(#" g ")' fill-opacity='" f2(0.42 * st) "'" rot(RANG, x0, -40) "/>"
}
function shaft_in(r, id,   y0, y1, xa, xb, hw) {
  y0 = mx(TY[id], -40); y1 = mn(TY[id] + THH[id], RL)
  if (y0 >= y1) return 0
  xa = ray_x(r, y1); xb = ray_x(r, y0); hw = 0.8 * RWD[r] / cos(RANG * RAD) + 2
  return xb + hw > TX[id] && xa - hw < TX[id] + TWW[id]
}

# ---------------------------------------------------------------- dynamic scenery: groups of elements that sway
# Each element has an envelope (every place it can be), which decides once which tiles carry it.
function newd(g, layer) { ND++; if (!(g in GD0)) GD0[g] = ND; GD1[g] = ND; DG[ND] = g; DL[ND] = layer; DX0[ND] = 1e9; DY0[ND] = 1e9; DX1[ND] = -1e9; DY1[ND] = -1e9; return ND }
function grow(d, x0, y0, x1, y1) { if (x0 < DX0[d]) DX0[d] = x0; if (y0 < DY0[d]) DY0[d] = y0; if (x1 > DX1[d]) DX1[d] = x1; if (y1 > DY1[d]) DY1[d] = y1 }
# grow() by a box under the matrix of the chain so far (KMa…KMf, as SVG's a b c d e f)
function growt(d, x0, y0, x1, y1,   k, x, y) {
  for (k = 0; k < 4; k++) { x = k % 2 ? x1 : x0; y = k < 2 ? y0 : y1; grow(d, KMa * x + KMc * y + KMe - 1, KMb * x + KMd * y + KMf - 1, KMa * x + KMc * y + KMe + 1, KMb * x + KMd * y + KMf + 1) }
}
function mrot(a, px, py,   c, s, e, f, na, nb, nc, nd) {
  c = cos(a * RAD); s = sin(a * RAD); e = px - c * px + s * py; f = py - s * px - c * py
  na = KMa * c + KMc * s; nb = KMb * c + KMd * s; nc = -KMa * s + KMc * c; nd = -KMb * s + KMd * c
  KMe = KMa * e + KMc * f + KMe; KMf = KMb * e + KMd * f + KMf; KMa = na; KMb = nb; KMc = nc; KMd = nd
}

# A kelp stalk: two segments (one when short), each one rigid element (its stretch of stalk and its leaves in one outlined
# path) turned about its joint, the pieces above riding on the ones below — a slow sway of few elements whose shapes
# never change. One big blade a joint, on alternate sides, with a gas bladder on the golden kelp of the deep tank, and
# a frond at the top: the blades cost bytes, not elements. `horse` puts the seahorse on it.
function kelp(x, h, front, bladders, horse,   k, g, n, j, a, lay) {
  k = ++NK; g = ++NG; GK[g] = "kelp"; GA[g] = k; lay = front ? 13 : 2
  KX[k] = x; KHT[k] = h; KBL[k] = bladders; KPH[k] = sr(0, 6.3); KW[k] = sr(0.42, 0.52); KLEAN[k] = sr(-2.5, 2.5); KHJ[k] = horse
  n = h > 125 ? 2 : 1; KN[k] = n
  KD0[k] = ND + 1
  for (j = 0; j < n; j++) newd(g, lay)
  if (horse) { KHD[k] = ND + 1; for (j = 0; j < 3; j++) newd(g, front ? 13 : 3) }
  kelp_shape(k)
  for (a = 0; a < 24; a++) kelp_eval(k, a * 1.3, ENV, 1)
}
# The stalk at rest, s units up from its root: a gentle S.
function kx_(k, s) { return KX[k] + 7 * sin(s / KHT[k] * 3.4 + KPH[k]) - 7 * sin(KPH[k]) }
function kelp_shape(k,   n, j, s0, s1, i, s, by, d, sp, li, sa, sg, ang, side, bl, ry, cx, cy, lx, ly, w, r, top) {
  n = KN[k]; by = sandy(KX[k]) + 4; KBY[k] = by; w = KBL[k] ? 2.4 : 1.7; RI = 1
  for (j = 0; j < n; j++) {
    s0 = KHT[k] * j / n; s1 = KHT[k] * (j + 1) / n + (j < n - 1 ? 4 : 0)
    KJX[k, j] = kx_(k, s0); KJY[k, j] = by - s0
    # the stalk: a thin strip up one side and down the other
    d = ""; r = ""; KB0X[k, j] = 1e9; KB1X[k, j] = -1e9; KB0Y[k, j] = by - s1 - 4; KB1Y[k, j] = by - s0 + 4
    for (i = 0; i <= 3; i++) {
      s = s0 + (s1 - s0) * i / 3
      d = d (i == 0 ? "M" : (i == 1 ? "L" : " ")) f1(kx_(k, s) - w) " " f1(by - s)
      r = " " f1(kx_(k, s) + w) " " f1(by - s) r
      KB0X[k, j] = mn(KB0X[k, j], kx_(k, s) - 5); KB1X[k, j] = mx(KB1X[k, j], kx_(k, s) + 5)
    }
    KSD[k, j] = d r "Z"
  }
  # the blades: a joint every `sp` units up the stalk, then the frond at the top
  sp = KBL[k] ? 52 : (KHT[k] < 130 ? 30 : 36); li = 0
  for (sa = KBL[k] ? 34 : 24; sa <= KHT[k] + 1; sa += sp) {
    top = sa > KHT[k] - sp * 0.6
    if (top) sa = KHT[k] * 0.985
    for (side = -1; side <= 1; side += 2) {
      if (!top && side != (li % 2 ? 1 : -1)) continue
      sg = int(sa / KHT[k] * n); if (sg >= n) sg = n - 1
      ang = top ? -90 + side * 17 : -90 + side * (48 + 6 * (li % 3))
      bl = (KBL[k] ? 27 : (KHT[k] < 130 ? 13 : 17)) * (0.85 + 0.35 * sa / KHT[k]) * (top ? 1.1 : 1); ry = KBL[k] ? 8.4 : 5.6
      lx = kx_(k, sa); ly = by - sa
      cx = lx + (bl - 2) * cos(ang * RAD); cy = ly + (bl - 2) * sin(ang * RAD)
      KSD[k, sg] = KSD[k, sg] sub_lens(cx, cy, bl, ry, ang)
      if (KBL[k] && !top) KSD[k, sg] = KSD[k, sg] sub_dot(lx + 3.5 * cos(ang * RAD), ly + 3.5 * sin(ang * RAD), 4.3)
      KB0X[k, sg] = mn(KB0X[k, sg], cx - bl); KB1X[k, sg] = mx(KB1X[k, sg], cx + bl); KB0Y[k, sg] = mn(KB0Y[k, sg], cy - bl); KB1Y[k, sg] = mx(KB1Y[k, sg], cy + bl)
    }
    li++
    if (top) break
  }
  KHS[k] = KHT[k] * 0.42; KHG[k] = int(KHS[k] / KHT[k] * n); RI = 0  # where the seahorse holds on
}
# Writes the kelp's elements at time t into arr (or grows their envelopes when arr is ENV).
function kelp_eval(k, t, arr, env,   n, j, a, amp, d, stem, leaf, leaf2) {
  n = KN[k]; d = KD0[k]; amp = env ? 4.6 : 2.6 * (1 + 0.5 * AGI)
  if (KBL[k]) { stem = lit("#5C4816"); leaf = lit("#AE8C2C"); leaf2 = lit("#C8A43C") } else { stem = lit("#1F6B3A"); leaf = lit("#38B06A"); leaf2 = lit("#46C27A") }
  KT = ""; KMa = 1; KMb = 0; KMc = 0; KMd = 1; KMe = 0; KMf = 0
  for (j = 0; j < n; j++) {
    a = amp * sin(t * KW[k] + KPH[k] - j * 0.8) + (j == 0 ? KLEAN[k] : 0)
    if (env) { a = amp * (int(t / 1.3) % 3 == 0 ? 1 : (int(t / 1.3) % 3 == 1 ? -1 : sin(t))) + (j == 0 ? KLEAN[k] : 0) }
    KT = KT (j ? " " : "") "rotate(" f1(a) " " f1(KJX[k, j]) " " f1(KJY[k, j]) ")"
    if (env) {
      mrot(a, KJX[k, j], KJY[k, j])
      growt(d, KB0X[k, j], KB0Y[k, j], KB1X[k, j], KB1Y[k, j])
    } else arr[d] = "<path d='" KSD[k, j] "' fill='" (j == n - 1 ? leaf2 : leaf) "' stroke='" stem "' stroke-width='1.2' stroke-linejoin='round' transform='" KT "'/>"
    if (KHJ[k] && j == KHG[k]) seahorse(k, kx_(k, KHS[k]), KBY[k] - KHS[k], t, arr, env)
    d++
  }
  KT = ""
}

# The seahorse: its tail curled round the stalk, the body, head and snout in one path beside it, its eye; it tilts
# a little. Its parts are placed from a frame at the hold point (HA degrees; HSC its size), inside the stalk's turns.
function hp(lx, ly) { HX_ = HOX + HSC * (lx * HC_ - ly * HS_); HY_ = HOY + HSC * (lx * HS_ + ly * HC_) }
function seahorse(k, x, y, t, arr, env,   d, i, b) {
  HOX = x; HOY = y; HSC = 1.6; HA = 4 * sin(t * 0.6 + 1.3); HC_ = cos(HA * RAD); HS_ = sin(HA * RAD); d = KHD[k]
  if (env) { for (i = 0; i < 3; i++) growt(d + i, x - 16, y - 60, x + 34, y + 10); return }
  hp(1.5, -5.5); b = sub_ell(HX_, HY_, 2.8 * HSC, 7 * HSC, HA + 22); hp(-0.6, 1); b = b sub_dot(HX_, HY_, 2.7 * HSC)
  arr[d] = "<path d='" b "' fill='" lit("#D57F26") "'" tr_(0, 0, 0) "/>"
  hp(6, -17); b = sub_ell(HX_, HY_, 5.2 * HSC, 10.5 * HSC, HA - 10); hp(9.5, -28.5); b = b sub_ell(HX_, HY_, 5 * HSC, 4 * HSC, HA + 15)
  hp(14.5, -27.8); b = b sub_lens(HX_, HY_, 4.6 * HSC, 1.3 * HSC, HA + 12)
  arr[d + 1] = "<path d='" b "' fill='" lit("#F2A33A") "'" tr_(0, 0, 0) "/>"
  hp(10.2, -30); arr[d + 2] = ci(HX_, HY_, 1.3 * HSC, "#1A1208", tr_(0, 0, 0))
}

# An anemone on the reef: its tentacles (one stroked path) and their pale tips (one path), bending slowly.
function anemone(   g, d) {
  g = ++NG; GK[g] = "anem"; AND0 = ND + 1
  d = newd(g, 13); grow(d, ANX - 60, sandy(ANX) - 52, ANX + 60, sandy(ANX))
  d = newd(g, 13); grow(d, ANX - 60, sandy(ANX) - 56, ANX + 60, sandy(ANX))
}
function anemone_eval(t, arr,   j, a, bx, by, len, tc, tip, sd, td, tx, ty) {
  tc = fluo("#FF7FB0", "#FF4FC8"); tip = fluo("#FFD9EA", "#FFE6FA"); sd = ""; td = ""
  for (j = 0; j < 8; j++) {
    bx = ANX + (j - 3.5) * 5; by = sandy(ANX) - 7; len = 28 + 7 * sin(j * 2.1)
    a = (j - 3.5) * 14 + 9 * sin(t * 0.8 + j * 0.8)
    tx = bx + len * sin(a * RAD); ty = by - len * cos(a * RAD)
    sd = sd seg_(bx, by, tx, ty); td = td sub_dot(tx, ty, 4.2)
  }
  arr[AND0] = strk(sd, tc, 6.4); arr[AND0 + 1] = "<path d='" td "' fill='" tip "'/>"
}

# Garden eels in the reef's sand: they stand out of their burrows swaying, and duck in when something swims over them.
function eels(   g, j, d, by) {
  g = ++NG; GK[g] = "eels"; EELG = g; EED0 = ND + 1; NEEL = 3; EUP = 1; EDUCK = -100
  for (j = 0; j < NEEL; j++) {
    EBX[j] = EELX + (j - 1) * 18 + sr(-3, 3); ELEN[j] = (27 + 9 * srnd()) * HS; EPH[j] = sr(0, 6.3); by = sandy(EBX[j]) + 3
    for (d = 0; d < 2; d++) grow(newd(g, 5), EBX[j] - ELEN[j] - 6, by - ELEN[j] - 8, EBX[j] + ELEN[j] + 6, by + 4)
  }
  d = newd(g, 5); grow(d, EELX - 90, sandy(EELX) - 60 * HS, EELX + 90, sandy(EELX) + 4)
}
function eels_eval(t, arr,   j, d, bx, by, a, h, hx, hy, ux, uy, sd, c, cs, ed) {
  d = EED0; c = lit("#F2EAD2"); cs = lit("#DCCFA8"); ed = ""
  for (j = 0; j < NEEL; j++) {
    bx = EBX[j]; by = sandy(bx) + 3; h = 2 + (ELEN[j] - 2) * EUP
    a = 9 * sin(t * 0.8 + EPH[j]) + 5 * sin(t * 1.9 + EPH[j] * 2) + (j - 1) * 6
    ux = sin(a * RAD); uy = -cos(a * RAD); hx = bx + (h - 3) * ux; hy = by + (h - 3) * uy
    sd = sin(t * 0.55 + EPH[j] * 3) > 0 ? 1 : -1                  # which way it looks
    arr[d] = rr_(bx - 2.4, by - h, 4.8, h, 2.4, cs, rot(a, bx, by))
    arr[d + 1] = el(hx, hy, 3.1, 4, c, rot(a, hx, hy))
    ed = ed sub_dot(hx - uy * sd * 1.4 + ux * 1.1, hy + ux * sd * 1.4 + uy * 1.1, 1.05)
    d += 2
  }
  arr[d] = "<path d='" ed "' fill='#15130C' opacity='" f2(cl(EUP * 3 - 0.2, 0, 1)) "'/>"
}

# Plankton that glows at night: a speck in a few tiles, each brightening and fading slowly on its own.
function plankton(   g, tx, ty, d) {
  g = ++NG; GK[g] = "plank"; PLD0 = ND + 1; NPL = 0
  for (ty = int(NTD * 0.3); ty < NTD; ty++) for (tx = 0; tx < NTA; tx++) {
    if (srnd() > 0.32) continue
    NPL++; PLX[NPL] = tx * PITCH + sr(15, 85); PLY[NPL] = ty * PITCH + sr(15, 80); PLP[NPL] = sr(0, 6.3); PLC[NPL] = srnd() < 0.6 ? "#7CFFD9" : "#9AD8FF"
    d = newd(g, 14); grow(d, PLX[NPL] - 6, PLY[NPL] - 6, PLX[NPL] + 6, PLY[NPL] + 6)
  }
}
function plankton_eval(t, arr,   k, d, a) {
  d = PLD0
  for (k = 1; k <= NPL; k++) {
    a = NIGHT * (0.3 + 0.7 * mx(0, sin(t * 0.3 + PLP[k])))
    arr[d] = ringc(PLX[k], PLY[k], 1.6, PLC[k], PLC[k], 5, " fill-opacity='" f2(0.95 * a) "' stroke-opacity='" f2(0.2 * a) "'")
    d++
  }
}

function chest_group(   g, y, d, k) {
  g = ++NG; GK[g] = "chest"; CHG = g; CHD0 = ND + 1; y = sandy(CHX) + 2
  for (k = 0; k < 3; k++) { d = newd(g, 4); grow(d, CHX - 40, y - 70, CHX + 40, y + 2) }
  for (k = 0; k < 2; k++) { d = newd(g, 6); grow(d, CHX - 30, y - 60, CHX + 30, y - 20) }
}
# How far the lid is open at time t: 0 closed … 1 open.
function chest_open(t,   u) {
  u = t - CHT0
  if (u < 0 || u > 7) return 0
  if (u < 0.7) return smooth(u / 0.7)
  if (u < 5.4) return 1
  return 1 - smooth((u - 5.4) / 1.2)
}
function chest_eval(t, arr,   o, y, top, d, ly) {
  o = chest_open(t); y = sandy(CHX) + 2; top = y - 26; d = CHD0
  arr[d] = el(CHX, top - 9, 29 * o + 0.1, 19 * o + 0.1, "#FFE9A0", " fill-opacity='" f2(0.15 * o) "'")
  arr[d + 1] = re(CHX - 21, top - 12 * o, 42, 12 * o + 0.5, "#3A200C", " opacity='" f2(o) "'")
  arr[d + 2] = el(CHX, top - 4 * o, 17 * o + 0.1, 6.5 * o + 0.1, "#FFD45A", " opacity='" f2(o) "'")
  ly = top - 13 - 15 * o
  arr[d + 3] = rr_(CHX - 24, ly, 48, 14, 5, lit("#7A4A22"), rot(-7 * o, CHX, ly + 7))
  arr[d + 4] = re(CHX - 3, ly - 0.5, 6, 15, lit("#D9A93C"), rot(-7 * o, CHX, ly + 7))
}

function crests(   g, x, d) {
  g = ++NG; GK[g] = "crest"; CRD0 = ND + 1; NCR = 0
  for (x = 30; x <= W; x += 82) { d = newd(g, 15); grow(d, x - 30, 0, x + 30, 16); CRX[++NCR] = x }
}
function crests_eval(t, arr,   k, d, c) {
  d = CRD0; c = lit("#E4F7FF"); if (NIGHT > 0.8) t = 0          # invisible at night: they rest, and send nothing
  for (k = 1; k <= NCR; k++) {
    arr[d] = el(CRX[k] + 3 * sin(t * 0.5 + k), 7.5 + 2.2 * sin(t * 0.9 + CRX[k] * 0.09), 25, 4.8 + 1.2 * sin(t * 1.1 + k * 1.3), c, " fill-opacity='" f2(CRA * 1.15) "'")
    d++
  }
}
# Flickers of light under the surface, in the top row only: they stay inside their tile, so each tile keeps its own.
function caustics(   g, tx, k, d) {
  g = ++NG; GK[g] = "caus"; CAD0 = ND + 1; NCA = 0
  for (tx = 0; tx < NTA; tx++) for (k = 0; k < 1; k++) {
    NCA++; CAX[NCA] = tx * PITCH + sr(30, 70); CAY[NCA] = sr(30, 70); CAR[NCA] = sr(10, 15); CAP[NCA] = sr(0, 6.3)
    d = newd(g, 15); grow(d, tx * PITCH + 2, 2, tx * PITCH + 98, 98)
  }
}
function caustics_eval(t, arr,   k, d, c) {
  d = CAD0; c = lit("#F0FCFF"); if (NIGHT > 0.8) t = 0
  for (k = 1; k <= NCA; k++) {
    arr[d] = el(CAX[k] + 4 * sin(t * 0.6 + CAP[k]), CAY[k], CAR[k] * (0.8 + 0.25 * sin(t * 0.9 + CAP[k] * 2)), CAR[k] * 0.32, c, " fill-opacity='" f2(CAA * (0.3 + 0.7 * (0.5 + 0.5 * sin(t * 0.8 + CAP[k])))) "'")
    d++
  }
}

# A group's strings at one moment, for one kind of frame (0: every tick, at TB; 1: every third tick, at TA), evaluated
# once a tick and kept per kind.
function eval_group(g, t, mode,   d) {
  if (GEV[g, mode] == TICK) return
  GEV[g, mode] = TICK
  if (GK[g] == "kelp") kelp_eval(GA[g], t, DST, 0)
  else if (GK[g] == "anem") anemone_eval(t, DST)
  else if (GK[g] == "chest") chest_eval(t, DST)
  else if (GK[g] == "crest") crests_eval(t, DST)
  else if (GK[g] == "caus") caustics_eval(t, DST)
  else if (GK[g] == "moray") moray_eval(t, DST)
  else if (GK[g] == "eels") eels_eval(t, DST)
  else if (GK[g] == "plank") plankton_eval(t, DST)
  for (d = GD0[g]; d <= GD1[g]; d++) DSM[mode, d] = DST[d]
}
function dstr(d, mode) { if (mode == 2) mode = 0; eval_group(DG[d], mode == 1 ? TA : TB, mode); return DSM[mode, d] }
# The chest makes its tiles busy while it moves, and the eels while they duck; the rest of the scenery is slow.
function gfast(g) { return (g == CHG && T > CHT0 - 0.6 && T < CHT0 + 7.6) || (g == EELG && EMOVE) }

# ---------------------------------------------------------------- static scenery (rebuilt when the light changes)
function st(layer, s, x0, y0, x1, y1) { NS++; SL_[NS] = layer; SST[NS] = s; SX0[NS] = x0; SY0[NS] = y0; SX1[NS] = x1; SY1[NS] = y1 }

function statics(   x, y, c, j, r) {
  NS = 0; SSEED = 104729 + COLS * 7 + DEEP; RI = 1
  for (r = 1; r <= NSH; r++) SHS[r] = shaft_str(r)
  st(15, re(-1, -1, W + 2, 8, lit("#EFFCFF"), " fill-opacity='" f2(0.18 + CRA * 0.6) "'") re(-1, -1, W + 2, 2.5, lit("#FFFFFF"), " fill-opacity='" f2(0.2 + CRA * 0.5) "'"), -1, -1, W + 1, 7)
  # the moon's glint under the surface, above its shaft
  x = ray_x(MOONR, 10)
  st(15, el(x, 10, 34, 3.4, "#E6EEFF", " fill-opacity='" f2(0.7 * MOONA) "'") el(x + 6, 9, 14, 1.8, "#FFFFFF", " fill-opacity='" f2(1.3 * MOONA) "'"), x - 35, 6, x + 35, 14)
  # pebbles along the sand
  for (x = 14; x < W; x += sr(34, 58)) {
    y = sandy(x); c = srnd() < 0.5 ? "#9E8E6E" : "#B5A27E"
    st(5, el(x, y + sr(3, 9), sr(3, 6.5), sr(2, 3.2), lit(c)), x - 8, y - 2, x + 8, y + 14)
  }
  # the chest's body (the lid, the light and the gold are the chest group)
  y = sandy(CHX) + 2
  st(5, rr_(CHX - 23, y - 26, 46, 26, 3, lit("#8A5A2B")), CHX - 24, y - 27, CHX + 24, y + 1)
  st(5, re(CHX - 23, y - 18, 46, 2.2, lit("#6B4220")) re(CHX - 23, y - 9, 46, 2.2, lit("#6B4220")), CHX - 24, y - 19, CHX + 24, y - 6)
  st(5, re(CHX - 17, y - 26, 5, 26, lit("#D4A43A")) re(CHX + 12, y - 26, 5, 26, lit("#D4A43A")), CHX - 18, y - 27, CHX + 18, y + 1)
  st(5, rr_(CHX - 5, y - 21, 10, 11, 2, lit("#E4B84A")) el(CHX, y - 16, 1.8, 2.8, lit("#2A1A0C")), CHX - 6, y - 22, CHX + 6, y - 9)
  # the floor: nothing stands across the chest (in the middle of its tile) or in front of the moray's hole
  if (DEEP) {
    rock(MRX, 1.25); st(2, el(MRX + 17, sandy(MRX) - 21, 10, 8, lit("#1F2830")), MRX + 6, sandy(MRX) - 30, MRX + 28, sandy(MRX) - 12)
    rock(W * 0.97, 0.9)
    if (NTA > 4) {
      grass(20); shell(62); softcoral(200, "#FF8FA3"); urchin(232); star(294, sandy(294) + 1, 10, "#FF8A4C")
      shell(404); amphora(452); softcoral(530, "#FFB067"); grass(578)
    } else {
      grass(18); shell(58); softcoral(186, "#FF8FA3"); star(210, sandy(210) + 1, 10, "#FF8A4C")
      shell(290); urchin(306); softcoral(334, "#FFB067")
    }
  } else {
    if (NTD > 4) outcrop()
    reefrock(150, 72, 44); reefrock(622, 64, 40); reefrock(472, 34, 22)
    tubes(30); staghorn(78, "#FF7E8C", "#FFC2CA", "#FF4FA0"); brain(262)
    staghorn(472, "#B06CFF", "#DCC0FF", "#4FD8FF"); table(622); fan(752); tubes(572)
    st(5, el(ANX, sandy(ANX) - 5, 26, 9, fluo("#B8436F", "#C2308F")), ANX - 27, sandy(ANX) - 15, ANX + 27, sandy(ANX) + 4)
    star(398, sandy(398) + 1, 9, "#FF6F4C"); shell(215); shell(712); grass(120); grass(700)
    # the eels' burrows
    for (j = 0; j < NEEL; j++) st(5, el(EBX[j], sandy(EBX[j]) + 3.5, 4.2, 1.7, lit("#8C7A55")), EBX[j] - 5, sandy(EBX[j]) + 1, EBX[j] + 5, sandy(EBX[j]) + 6)
  }
  RI = 0
}
# A rock outcrop that frames a tall reef (8×6): it rises from the floor at the left edge two rows up, coral on its top
# and on a ledge. Far, so a little darker and bluer than the reef's own rocks.
function outcrop(   b, s) {
  b = FLOOR
  # stacked boulders, the lower ones darker, a flat ledge sticking out to the right
  s = el(30, b - 20, 124, 70, lit("#34324F")) el(-6, b - 118, 84, 62, lit("#3B3858")) el(60, b - 96, 60, 40, lit("#403D5E"))
  s = s el(14, b - 196, 58, 44, lit("#433F63")) el(122, b - 124, 48, 13, lit("#4E4A72")) el(126, b - 129, 40, 6, lit("#5E5984"))
  s = s el(-4, b - 226, 40, 16, lit("#524E78")) el(36, b - 148, 30, 10, lit("#4E4A72")) el(88, b - 40, 34, 12, lit("#46425F"))
  s = s ci(52, b - 208, 3.4, fluo("#7DE8C8", "#5CFFD2")) ci(-8, b - 150, 4, fluo("#FF8FB8", "#FF7AD6")) ci(142, b - 132, 2.8, fluo("#FFD36E", "#FFF27A")) ci(72, b - 118, 3, fluo("#7DE8C8", "#5CFFD2"))
  st(2, s, -100, b - 244, 172, b + 52)
  # coral on the top and on the ledge
  softcoral(8, "#C98BFF", b - 234)
  tubes(118, b - 130)
  st(2, el(58, b - 158, 16, 11, fluo("#E0A95B", "#7CFF9C")) el(58, b - 160, 11, 7, fluo("#C78F45", "#2FBF6A")) el(58, b - 161, 5, 3.4, fluo("#E7B46A", "#7CFF9C")), 40, b - 170, 76, b - 146)
}
# A rock the reef grows on: its top is where the coral stands.
function reefrock(x, rx, ry,   y, s) {
  y = sandy(x) + 6; rx *= HS; ry *= HS; RTOP[int(x)] = y - ry * 0.92
  s = el(x, y, rx, ry, lit("#4F4B69")) el(x - rx * 0.25, y - ry * 0.35, rx * 0.62, ry * 0.5, lit("#625D80")) el(x + rx * 0.3, y - ry * 0.62, rx * 0.35, ry * 0.22, lit("#77729A"))
  s = s ci(x - rx * 0.5, y - ry * 0.5, 4, fluo("#FF8FB8", "#FF7AD6")) ci(x + rx * 0.55, y - ry * 0.3, 3.5, fluo("#7DE8C8", "#5CFFD2"))
  st(2, s, x - rx - 2, y - ry - 2, x + rx + 2, y + ry)
}
# A table coral: a flat plate on a short stem, on its rock.
function table(x,   y, h, c) {
  y = RTOP[int(x)] + 4; h = 34 * HS; c = fluo("#E0955B", "#39E6C0")
  st(2, rr_(x - 5, y - h, 10, h + 2, 4, lit("#B8744A")) el(x, y - h, 58 * HS, 9, c) el(x - 4, y - h - 3, 48 * HS, 5, fluo("#F4B988", "#8CFFE4")),
     x - 60 * HS, y - h - 12, x + 60 * HS, y + 4)
}
# A tuft of sea grass: its blades are one stroked path.
function grass(x,   y, k, d, h, bx) {
  y = sandy(x) + 3; d = ""
  for (k = 0; k < 6; k++) { h = sr(14, 30); bx = x + (k - 2.5) * 3.2; rotp(bx, y - h + 1.2, bx, y, sr(-18, 18)); d = d seg_(bx, y - 1.2, RPX, RPY) }
  st(5, strk(d, lit("#47A064"), 2.4), x - 22, y - 34, x + 22, y + 2)
}
# A soft coral that never moves: a plump base, short tentacles (one stroked path).
function softcoral(x, c, base,   y, k, d, a, bx) {
  y = base ? base : sandy(x) + 2; d = ""
  for (k = 0; k < 7; k++) { a = (k - 3) * 20; bx = x + (k - 3) * 2.6; rotp(bx, y - 18.6, bx, y - 4, a); d = d seg_(bx, y - 2.4, RPX, RPY) }
  st(5, strk(d, fluo(c, "#FF6FD0"), 4.8) el(x, y - 3, 11, 5, lit("#C45A6E")), x - 26, y - 28, x + 26, y + 3)
}
# An amphora lying on the sand since some forgotten wreck.
function amphora(x,   y, s) {
  y = sandy(x) - 6
  s = el(x, y + 2, 28, 12, lit("#8E4A28"), rot(-10, x, y + 2)) el(x, y, 26, 11.5, lit("#B5653A"), rot(-10, x, y))
  s = s rr_(x + 22, y - 12, 12, 7, 2, lit("#A55A32"), rot(-10, x, y)) el(x + 35, y - 12, 3.4, 5.6, lit("#3A1C0E"), rot(-10, x, y)) el(x - 6, y - 5, 13, 3, lit("#CF7F52"), rot(-10, x, y))
  st(5, s, x - 32, y - 22, x + 42, y + 16)
}
# A moray eel lives in the big rock and now and then looks out of its hole, opening and closing its mouth.
function moray(   g, k, d) {
  g = ++NG; GK[g] = "moray"; MOD0 = ND + 1
  for (k = 0; k < 4; k++) { d = newd(g, 2); grow(d, MRX - 10, sandy(MRX) - 60, MRX + 70, sandy(MRX) - 4) }
}
function moray_eval(t, arr,   u, o, hx, hy, cx, cy, d, m, a) {
  u = t % 26
  o = u < 5 ? 0 : (u < 7.5 ? smooth((u - 5) / 2.5) : (u < 15 ? 1 : (u < 17.5 ? 1 - smooth((u - 15) / 2.5) : 0)))
  m = o * (0.5 + 0.5 * sin(t * 1.7)); d = MOD0; a = -14
  cx = MRX + 17; cy = sandy(MRX) - 21
  hx = cx + (3 + 26 * o) * cos(a * RAD); hy = cy + (3 + 26 * o) * sin(a * RAD)
  arr[d] = el((cx + hx) / 2, (cy + hy) / 2, 4 + 13 * o, 5.5 * (0.4 + 0.6 * o), lit("#5F6F2E"), rot(a, (cx + hx) / 2, (cy + hy) / 2) " opacity='" f2(0.35 + 0.65 * o) "'")
  arr[d + 1] = el(hx + 2, hy + 3 + 1.5 * m, 7 * (0.4 + 0.6 * o), 2.6 + 1.6 * m, lit("#566628"), rot(a + 8 * m, hx, hy) " opacity='" f2(0.35 + 0.65 * o) "'")
  arr[d + 2] = el(hx, hy - 1, 8.5 * (0.4 + 0.6 * o), 5.5 * (0.4 + 0.6 * o), lit("#72853A"), rot(a - 4 * m, hx, hy) " opacity='" f2(0.35 + 0.65 * o) "'")
  arr[d + 3] = ringc(hx + 1.5, hy - 3.5, 1.7 * o + 0.05, "#1A1A10", "#F5E27A", 1.2 * o, " opacity='" f2(o) "'")
}
function rock(x, s,   y) {
  y = sandy(x)
  st(2, el(x, y - 10 * s, 40 * s, 26 * s, lit("#586775")) el(x - 18 * s, y - 4 * s, 24 * s, 16 * s, lit("#6A7A88")) el(x + 8 * s, y - 24 * s, 20 * s, 8 * s, lit("#7C8D9B")),
     x - 44 * s, y - 38 * s, x + 44 * s, y + 18 * s)
}
function star(x, y, r,  c,   k, a, rad) {
  for (k = 1; k <= 10; k++) { a = (k - 1) * 36 - 90; rad = k % 2 ? r : r * 0.42; PX[k] = x + rad * cos(a * RAD); PY[k] = y + rad * sin(a * RAD) * 0.62 }
  st(5, pg(10, lit(c)) ci(x, y, r * 0.22, lit("#FFB585")), x - r - 1, y - r, x + r + 1, y + r)
}
function shell(x,   y) {
  y = sandy(x) + 3
  st(5, el(x, y, 6.5, 4.2, lit("#F2DCC8")) el(x, y - 1, 4.2, 2.2, lit("#E0B89A")), x - 7, y - 5, x + 7, y + 5)
}
function urchin(x,   y, k, a, d) {
  y = sandy(x) - 3; d = ""
  for (k = 0; k < 7; k++) { a = (k - 3) * 26; rotp(x, y - 12.2, x, y, a); d = d seg_(x, y - 0.8, RPX, RPY) }
  st(5, strk(d, lit("#3B2A55"), 1.6) el(x, y, 7, 5.5, lit("#4B3670")), x - 16, y - 16, x + 16, y + 6)
}
# A staghorn coral: its branches are one stroked path, their pale tips one path of dots.
function staghorn(x, c, tip, f,   k, y, a, len, bx, d, td) {
  y = (int(x) in RTOP ? RTOP[int(x)] + 6 : sandy(x) + 2); d = ""; td = ""
  for (k = 0; k < 7; k++) {
    a = -54 + k * 18 + sr(-6, 6); len = sr(30, 58) * HS; bx = x + (k - 3) * 5
    d = d seg_(bx + 4.2 * sin(a * RAD), y - 4.2 * cos(a * RAD), bx + (len - 4.2) * sin(a * RAD), y - (len - 4.2) * cos(a * RAD))
    td = td sub_dot(bx + (len - 3) * sin(a * RAD), y - (len - 3) * cos(a * RAD), 4.6)
  }
  st(2, strk(d, fluo(c, f), 8.4) "<path d='" td "' fill='" fluo(tip, "#FFFFFF") "'/>", x - 70 * HS, y - 64 * HS, x + 70 * HS, y + 4)
}
function brain(x,   y) {
  y = sandy(x) + 4
  st(2, el(x, y - 16, 44, 30, fluo("#E0A95B", "#7CFF9C")) el(x, y - 18, 34, 22, fluo("#C78F45", "#2FBF6A")) el(x, y - 20, 24, 15, fluo("#E7B46A", "#7CFF9C")) el(x, y - 22, 13, 8, fluo("#C78F45", "#2FBF6A")),
     x - 45, y - 47, x + 45, y + 14)
}
# A sea fan: its web and its ribs (one stroked path).
function fan(x,   y, k, a, h, d) {
  y = sandy(x) + 6; h = 62 * HS; d = ""
  for (k = 0; k < 7; k++) { a = -66 + k * 22; rotp(x, y - h + 1.3, x, y, a); d = d seg_(x, y - 1.3, RPX, RPY) }
  st(2, el(x, y - 6, 44 * HS, h, fluo("#9B59D0", "#8A5CFF"), " fill-opacity='0.85'") strk(d, fluo("#C99BF0", "#D8B8FF"), 2.6), x - 50 * HS, y - h - 12, x + 50 * HS, y + 4)
}
function tubes(x, base,   y, s, k, h, bx) {
  y = base ? base : sandy(x) + 3; s = ""
  for (k = 0; k < 3; k++) {
    h = (30 + k * 12 - (k == 2) * 18) * HS; bx = x + (k - 1) * 12
    s = s rr_(bx - 5.5, y - h, 11, h + 2, 5, fluo(k == 1 ? "#F39C3D" : "#E88A2E", k == 1 ? "#FFB347" : "#FF9A3C")) el(bx, y - h + 2.5, 3.8, 2, lit("#7A3E12"))
  }
  st(2, s, x - 20, y - 46 * HS, x + 20, y + 4)
}

# ---------------------------------------------------------------- tiles
# A tile: the id of its button, its window onto the world, and a fixed list of slots — what it carries, in drawing
# order. The list is decided once for the window, from where each thing can ever be, so the tile's structure never
# changes while the world stays the same shape.
function window_of(row, col) {
  if (ORI == "landscape") { WX_ = row * PITCH; WY_ = (COLS - 1 - col) * PITCH } else { WX_ = col * PITCH; WY_ = row * PITCH }
}
# The world's things by layer, in drawing order: statics, then scenery, then creatures.
function bucket(   L, s, d, m) {
  for (L = 2; L <= 15; L++) LIN[L] = 0
  for (s = 1; s <= NS; s++) { L = SL_[s]; LIN[L]++; LIT[L, LIN[L]] = 4; LIX[L, LIN[L]] = s }
  for (d = 1; d <= ND; d++) { L = DL[d]; LIN[L]++; LIT[L, LIN[L]] = 2; LIX[L, LIN[L]] = d }
  for (m = 1; m <= NM; m++) { L = ML[m]; LIN[L]++; LIT[L, LIN[L]] = 3; LIX[L, LIN[L]] = m }
}
function tile(id, x, y, w, h) {
  TX[id] = x; TY[id] = y; TWW[id] = w; THH[id] = h
  TG[id]++; FIRST[id] = 1; FORCE[id] = 1; LAST[id] = ""; LASTT[id] = 0
  slots(id); upgrade(id)
}
function inbox(id, x0, y0, x1, y1) { return x1 > TX[id] - 1 && x0 < TX[id] + TWW[id] + 1 && y1 > TY[id] - 1 && y0 < TY[id] + THH[id] + 1 }
function add(id, t, n) { NSL[id]++; SLT[id, NSL[id]] = t; SLN[id, NSL[id]] = n }
function band(id, m,   k) {
  k = MK[m]
  if (k == "crab") return inbox(id, 0, FLOOR - 60, W, H + 10)
  if (k == "angler" || k == "lure") return DEEP && inbox(id, 0, AB0 - 110, W, AB1 + 40)
  if (k == "turtle" || k == "ray") return inbox(id, 0, GB0 - 85, W, GB1 + 80)
  if (k == "barracuda") return inbox(id, 0, GB0 - 34, W, GB1 + 34)
  if (k == "fish") return inbox(id, 0, FBT[m] - 1.4 * FH[m] - 30, W, FBB[m] + 1.4 * FH[m] + 30)
  return 1
}
function slots(id,   L, k, t, n, r) {
  NSL[id] = 0; NSR[id] = 0
  for (r = 1; r <= NSH; r++) if (shaft_in(r, id)) { add(id, 1, r); NSR[id] = 1 }
  for (L = 2; L <= 15; L++) {
    if (L == 3 && TY[id] + THH[id] > FLOOR - 12) add(id, 5, 0)
    for (k = 1; k <= LIN[L]; k++) {
      t = LIT[L, k]; n = LIX[L, k]
      if (t == 4) { if (inbox(id, SX0[n], SY0[n], SX1[n], SY1[n])) add(id, 4, n) }
      else if (t == 2) { if (inbox(id, DX0[n], DY0[n], DX1[n], DY1[n])) add(id, 2, n) }
      else if (band(id, n)) add(id, 3, n)
    }
  }
  if (THH[id] == 100) add(id, 6, 0)                                  # the ripple a tap makes in this tile
}
# The tile takes on the light of the moment: its head and its still scenery. TSN counts their elements (the cost of
# the change on the phone).
function upgrade(id,   k, t, n, s, c) {
  HEAD[id] = head(id); c = 2
  for (k = 1; k <= NSL[id]; k++) {
    t = SLT[id, k]; n = SLN[id, k]
    if (t == 1) s = SHS[n]; else if (t == 4) s = SST[n]; else if (t == 5) s = tstr(id); else continue
    TSS[id, k] = s; c += gsub(/</, "<", s)
  }
  TSN[id] = c; TLG[id] = LGEN
}

# The start of a tile's frame: viewBox, the water and light-shaft gradients, the water rect. The water rect's id
# changes with every new layout, so a tile's first frame after a change cross-fades instead of gliding.
function head(id,   x, y, w, h, s, k) {
  x = TX[id]; y = TY[id]; w = TWW[id]; h = THH[id]
  s = "<svg viewBox='" x " " y " " w " " h "'><defs>"
  if (h > 100) { s = s "<linearGradient id='w' gradientUnits='userSpaceOnUse' x1='0' y1='" y "' x2='0' y2='" (y + h) "'>"; for (k = 1; k <= 4; k++) s = s "<stop offset='" SF[k] "' stop-color='" WC[k] "'/>" }
  else s = s "<linearGradient id='w' x2='0' y2='1'><stop stop-color='" wcol(y - 1) "'/><stop offset='1' stop-color='" wcol(y + h + 1) "'/>"
  s = s "</linearGradient>"
  # the shafts' gradient: the day's light, or at night the moon's (the other shafts are out then)
  if (NSR[id]) s = s "<linearGradient id='r' x2='0' y2='1'>" rstops(MOONA > RA ? ray_col(MOONR) : RC) "</linearGradient>"
  return s "</defs><rect id='w" GEN "t" TG[id] "' x='" (x - 1) "' y='" (y - 1) "' width='" (w + 2) "' height='" (h + 2) "' fill='url(#w)'/>"
}
function rstops(c) { return "<stop stop-color='" c "'/><stop offset='0.4' stop-color='" c "' stop-opacity='0.42'/><stop offset='1' stop-color='" c "' stop-opacity='0'/>" }
# The sand of this window: a wavy top on its width, a darker band below.
function tstr(id,   x, y, w, h, k, s, r0) {
  x = TX[id]; y = TY[id]; w = TWW[id]; h = THH[id]; RI = 1
  s = ""; k = int(w / 12.5 + 0.5)
  PX[1] = x - 1; PY[1] = sandy(x - 1)
  for (r0 = 1; r0 <= k; r0++) { PX[r0 + 1] = x - 1 + (w + 2) * r0 / k; PY[r0 + 1] = sandy(PX[r0 + 1]) }
  PX[k + 2] = x + w + 1; PY[k + 2] = y + h + 1; PX[k + 3] = x - 1; PY[k + 3] = y + h + 1
  s = pg(k + 3, lit(DEEP ? "#C9B07E" : "#E3CC95"))
  s = s re(x - 1, FLOOR + 14, w + 2, H - FLOOR, lit(DEEP ? "#A89366" : "#CDB47F")); RI = 0
  return s
}
# A change of light: the scenery's strings anew. The tiles take them on a few at a time (tick); a tile about to be
# drawn for the first time, and every tile of a tool mode, at once.
function relight(   i, id) {
  statics()
  for (i = 1; i <= NT; i++) { id = ORD[i]; if (FIRST[id] || TOOL) upgrade(id) }
}

# ---------------------------------------------------------------- composing a tile's frame
# Where each creature can be seen during the glides around this tick. It is visible in a tile whose window meets its
# box where it was, where it is, or where it can be at the end of the next glide (its velocity for one glide, and
# what its acceleration can add); anywhere else it is parked, and costs the phone nothing.
function prep(per,   m, h, a, e1, e2, vx, vy, k) {
  h = per * 1.05; ACT[RAYT] = ACT[RAY]; VX[RAYT] = VX[RAY]; VY[RAYT] = VY[RAY]; ACT[ANGL] = ACT[ANG]; VX[ANGL] = VX[ANG]; VY[ANGL] = VY[ANG]
  for (m = 1; m <= NM; m++) {
    if (MK[m] == "bub" || MK[m] == "food") ACT[m] = PH[m] != 0
    if (!ACT[m] || MK[m] == "school") { PBT[m] = 0; continue }
    mbox(m)
    # its boxes on the last two ticks (a tile's previous frame was one or two ticks ago); none: where it is now
    if (PBT[m] != TICK || PH[m] == 1) { Q0X[m] = B0X[m]; Q0Y[m] = B0Y[m]; Q1X[m] = B1X[m]; Q1Y[m] = B1Y[m]; R0X[m] = B0X[m]; R0Y[m] = B0Y[m]; R1X[m] = B1X[m]; R1Y[m] = B1Y[m] }
    k = MK[m]
    # near the barracuda a fish or the school may bolt: its reach is the bolt's
    a = k == "neon" ? (SRISK ? NEONP : NEONA) : (k == "fish" ? (RISK[m] ? FISHP : FISHA) : (k == "crab" ? 60 : (k == "angler" || k == "lure" ? 12 : 20)))
    e1 = 0.5 * a * h * h + 3; e2 = k == "fish" ? 0.5 * (RISK[m] ? FISHPY : FISHAY) * h * h + 3 : e1
    vx = VX[m] * h; vy = VY[m] * h
    # a guest's path is known: where it will be, exactly
    if (k == "turtle" || k == "ray" || k == "raytail" || k == "barracuda") { vy = GY + 12 * sin((T + h) * 0.25) - Y[k == "raytail" ? RAY : m]; e1 = 2; e2 = 2 }
    VX0[m] = mn(mn(mn(Q0X[m], R0X[m]), B0X[m]), B0X[m] + vx - e1); VX1[m] = mx(mx(mx(Q1X[m], R1X[m]), B1X[m]), B1X[m] + vx + e1)
    VY0[m] = mn(mn(mn(Q0Y[m], R0Y[m]), B0Y[m]), B0Y[m] + vy - e2); VY1[m] = mx(mx(mx(Q1Y[m], R1Y[m]), B1Y[m]), B1Y[m] + vy + e2)
    # and where it can be a glide later: a tile draws it unseen at its place (coming) a frame before it can show there
    VX0[m] = mn(VX0[m], B0X[m] + 2 * vx - 4 * e1); VX1[m] = mx(VX1[m], B1X[m] + 2 * vx + 4 * e1)
    VY0[m] = mn(VY0[m], B0Y[m] + 2 * vy - 4 * e2); VY1[m] = mx(VY1[m], B1Y[m] + 2 * vy + 4 * e2)
    R0X[m] = Q0X[m]; R0Y[m] = Q0Y[m]; R1X[m] = Q1X[m]; R1Y[m] = Q1Y[m]
    Q0X[m] = B0X[m]; Q0Y[m] = B0Y[m]; Q1X[m] = B1X[m]; Q1Y[m] = B1Y[m]; PBT[m] = TICK + 1
  }
  mbox(SCH); VX0[SCH] = 1e9; VX1[SCH] = -1e9; VY0[SCH] = 1e9; VY1[SCH] = -1e9
  for (m = NEON0; m <= NEON1; m++) { VX0[SCH] = mn(VX0[SCH], VX0[m]); VX1[SCH] = mx(VX1[SCH], VX1[m]); VY0[SCH] = mn(VY0[SCH], VY0[m]); VY1[SCH] = mx(VY1[SCH], VY1[m]) }
}
function hitv(id, m) { return ACT[m] && VX1[m] > TX[id] && VX0[m] < TX[id] + TWW[id] && VY1[m] > TY[id] && VY0[m] < TY[id] + THH[id] }
function seen(id, m) { return ACT[m] && B1X[m] > TX[id] && B0X[m] < TX[id] + TWW[id] && B1Y[m] > TY[id] && B0Y[m] < TY[id] + THH[id] }
function opacity(m) { return (MK[m] == "bub" || MK[m] == "food") ? PH[m] == 2 : 1 }
function mvis(m) { if (MVT[m] != TICK) { MV[m] = draw(m, opacity(m)); MVT[m] = TICK }; return MV[m] }
# Unseen at its place (coming, going) a creature is drawn where the phone will have it on screen when the next frame
# comes (SNX, SNY): the phone starts the showing glide from this frame's place, and a glide longer than the period
# leaves what it shows behind the frames — at the real place the creature would show up ahead of its other half and
# slide back into it. The engine follows the phone's glides for that: each starts where the last one had got to.
function minv(m) { if (MIT[m] != TICK) { onscreen(m, 1); MI[m] = draw(m, 0); onscreen(m, 0); MIT[m] = TICK }; return MI[m] }
function onscreen(m, on,   n) {
  if (MK[m] == "school") { for (n = NEON0; n <= NEON1; n++) os1(n, on); return }
  os1(MK[m] == "raytail" ? RAY : (MK[m] == "lure" ? ANG : m), on)
}
function os1(n, on) { if (on) { LGX[n] = X[n]; LGY[n] = Y[n]; if (n in SNX) { X[n] = SNX[n]; Y[n] = SNY[n] } } else { X[n] = LGX[n]; Y[n] = LGY[n] } }
# where the phone's glides have every creature when the next frame comes (it jumps along with a creature that jumped)
function follow(per,   m, f) {
  f = mn(1, per / DB)
  for (m = 1; m <= NM; m++) {
    if (!(m in SSX) || abs(X[m] - SSX[m]) + abs(Y[m] - SSY[m]) > 80) { SSX[m] = X[m]; SSY[m] = Y[m] }
    SNX[m] = SSX[m] + (X[m] - SSX[m]) * f; SNY[m] = SSY[m] + (Y[m] - SSY[m]) * f
  }
}
function follow_done(   m) { for (m = 1; m <= NM; m++) { SSX[m] = SNX[m]; SSY[m] = SNY[m] } }
# Whether the tile needs a frame on its tick (BF): a creature in it, or one that just left (it is parked at once),
# fast scenery, a ripple still spreading.
function busy(id,   k, t, n) {
  BF = 0
  for (k = 1; k <= NSL[id]; k++) {
    t = SLT[id, k]; n = SLN[id, k]
    if (t == 3) { if (TST[id, n] || hitv(id, n)) BF = 1 }
    else if (t == 2) { if (gfast(DG[n])) BF = 1 }
    else if (t == 6) { if (RINGS[id] == 2) BF = 1 }
  }
}
# mode 0: a frame of every tick of the tile; 1: every third (scenery shown a little ahead, where its longer glide
# ends); 2: a still picture (sample faces, the cover): nothing parked, nothing invisible. Parked creatures next to each other
# share one far-away group (a group is not an element: the tile's structure is the same however they are grouped).
# A creature in a tile is parked (0), coming (1: at its real place with opacity 0), shown (2) or going (3 … 2 + GOING:
# at its real place with opacity 0, then parked). Going lasts GOING frames: a glide longer than the period never ends
# a fade — each frame takes over at 1 - period/glide of the way (a sixth) — so a creature that just went out is still
# a faint ghost. Keep it at its exit point for those frames, else a creature showing again would glide in from
# wherever it was (parked, far away).
# Coming and going are the invisible jump (see the cast): the
# phone never glides a creature it shows to or from far away.
function compose(id, mode,   s, k, t, n, st, pk, ph) {
  s = HEAD[id]; pk = 0
  for (k = 1; k <= NSL[id]; k++) {
    t = SLT[id, k]; n = SLN[id, k]; ph = 0
    if (t == 3 && mode != 2) {
      st = hitv(id, n); ph = TST[id, n]
      if (st) ph = ph ? 2 : 1; else ph = ph == 2 ? 3 : (ph >= 3 && ph < 2 + GOING ? ph + 1 : 0)
      TST[id, n] = ph
    }
    if (pk && (t != 3 || mode == 2 || ph)) { s = s "</g>"; pk = 0 }
    if (t == 1 || t == 4 || t == 5) s = s TSS[id, k]
    else if (t == 2) s = s dstr(n, mode)
    else if (t == 6) { if (mode != 2) s = s ripple(id) }
    else if (mode == 2) { if (seen(id, n) && opacity(n) > 0) s = s mvis(n) }
    else if (ph == 2) s = s mvis(n)
    else if (ph) s = s minv(n)
    else { if (!pk) { s = s "<g transform='translate(1e6 1e6)' opacity='0'>"; pk = 1 }; s = s PARK[n] }
  }
  return s (pk ? "</g>" : "") "</svg>"
}

# A tap answers at once: a ring spreads from where the food drops (visible for one glide, fading out over the next;
# RINGS counts the tile's frames since the tap).
function ripple(id,   r, op) {
  r = 3; op = 0
  if (RINGS[id] == 1) { r = 13; op = 0.8 } else if (RINGS[id] == 2) r = 27
  return "<circle cx='" (TX[id] + 50) "' cy='" (TY[id] + 34) "' r='" r "' fill='none' stroke='#F2FCFF'" (RINGS[id] ? " stroke-width='1.8'" : "") " opacity='" op "'/>"
}

# ---------------------------------------------------------------- simulation
# A tail's wag: a smooth swing of 2.1 s, sampled on every tile's own tick (three samples a swing); tiles that draw
# the same fish on different ticks sample the same swing.
function wag(m) { return WAG[m] * sin(T * 2.99 + WPH[m]) }
function sim(dt,   n, k, sb) {
  n = int(dt / 0.15) + 1; sb = dt / n
  for (k = 0; k < n; k++) { T += sb; step(sb) }
}
function at_risk(x, y, back, ahead, up,   dx) { dx = (x - X[BAR]) * D[BAR]; return dx > -back && dx < ahead && abs(y - Y[BAR]) < up }
function step(dt,   m) {
  # it frightens only from inside the tank; who may bolt in the next second and a half — still frightened, or near
  # enough to its path — gets a wider reach in prep (RISK, SRISK for the school): only they, or every fish would show in
  # more tiles
  BARIN = ACT[BAR] && X[BAR] > -40 && X[BAR] < W + 40
  for (m = 1; m <= SPC; m++) RISK[m] = PAN[m] > 0 || (ACT[BAR] && at_risk(X[m], Y[m], 90, 520, 150))
  SRISK = PSC > 0 || (ACT[BAR] && at_risk(SCX, SCY, 120, 560, 190))
  schedule(dt)
  meals()
  for (m = 1; m <= SPC; m++) fish(m, dt)
  school(dt)
  crab(dt)
  if (ACT[TUR] || ACT[RAY] || ACT[BAR]) guest(dt)
  if (DEEP) angler(dt)
  for (m = FOOD0; m <= FOOD1; m++) food(m, dt)
  for (m = BUB0; m <= BUB1; m++) bubble(m, dt)
  if (EELG) eelwatch(dt)
}
# Who eats what: every fish heads for its nearest sinking pellet; of those heading for the same one, the nearest takes
# it and the others wait their turn round it — a feeding is a ring of nibbling fish, not a heap.
function meals(   m, f, dist) {
  for (f = FOOD0; f <= FOOD1; f++) { EATER[f] = 0; EATD[f] = 1e9 }
  for (m = 1; m <= SPC; m++) {
    FB[m] = 0; FD[m] = 460
    for (f = FOOD0; f <= FOOD1; f++) if (PH[f] == 2 && REST[f] == 0 && Y[f] > FBT[m] - 10 && Y[f] < FBB[m] + 10) { dist = hyp(X[f] - X[m], Y[f] - Y[m]); if (dist < FD[m]) { FD[m] = dist; FB[m] = f } }
    if (FB[m] && FD[m] < EATD[FB[m]]) { EATD[FB[m]] = FD[m]; EATER[FB[m]] = m }
  }
}
# The garden eels duck into the sand when something swims low over them or lands near, and rise again slowly.
function eelwatch(dt,   m, k, tgt, reach) {
  for (m = 1; m <= NM; m++) {
    k = MK[m]
    if (!ACT[m] || k == "bub" || k == "angler" || k == "lure" || k == "school" || k == "raytail") continue
    if ((k == "food") && PH[m] != 2) continue
    reach = (k == "turtle" || k == "ray") ? 115 : (k == "crab" ? 50 : 42)
    if (abs(X[m] - EELX) < reach && Y[m] > sandy(EELX) - (k == "crab" ? 99 : 70)) EDUCK = T
  }
  if (BARIN) EDUCK = T
  tgt = T - EDUCK < 2.5 ? 0.06 : 1
  EUP += (tgt - EUP) * mn(dt * (tgt < EUP ? 7 : 0.7), 1)
  EMOVE = tgt < 0.5 && EUP > 0.12
}
function schedule(dt,   k, src, x, y, j) {
  if (T >= CHNEXT) { CHT0 = T; CHNEXT = T + brr(60, 120); NBQ = 0; for (k = 0; k < 5; k++) BQ[++NBQ] = T + 0.55 + k * 0.22 }
  for (k = 1; k <= NBQ; k++) if (BQ[k] > 0 && T >= BQ[k]) { BQ[k] = 0; launch(CHX + brr(-12, 12), sandy(CHX) - 26, brr(2.6, 5.4)) }
  if (!ACT[TUR] && !ACT[RAY] && !ACT[BAR] && T >= GNEXT) start_guest()
  BT -= dt
  if (BT <= 0) {
    BT = brr(5, 11) / (1 + 0.6 * AGI)
    src = brr(0, 1)
    if (DEEP && src < 0.5) { j = 1 + int(brr(0, 0.999) * NK); x = KX[j] + brr(-8, 8); y = sandy(KX[j]) - brr(30, KHT[j] * 0.8) }
    else if (!DEEP && src < 0.4) { x = ANX + brr(-10, 10); y = sandy(ANX) - 30 }
    else if (src < 0.85) { x = CHX + brr(-6, 6); y = sandy(CHX) - 26 }
    else { x = brr(40, W - 40); y = sandy(x) - 4 }
    launch(x, y, brr(2.2, 4.6))
  }
}

# Particles (food, bubbles) move invisibly when they jump: hidden where they were, then hidden where they start.
function launch(x, y, r,   m, best) {
  best = 0
  for (m = BUB0; m <= BUB1; m++) if (PH[m] == 0) { best = m; break }
  if (!best) return
  BR_[best] = r; p_launch(best, x, y)
}
# A jump: hidden where it was for three frames of every tile (its fade then all but over — see GOING), hidden where it
# starts for two, then shown.
function p_launch(m, x, y) {
  if (PH[m] == 0) { X[m] = x; Y[m] = y; BX_[m] = x; AGE[m] = 0; REST[m] = 0; PH[m] = 1; PHT[m] = TICK + 1 }
  else { RSX[m] = x; RSY[m] = y; RSP[m] = 1; if (PH[m] != 3) { PH[m] = 3; PHT[m] = TICK + 1 } }
}
function p_vanish(m) { RSP[m] = 0; if (PH[m] && PH[m] != 3) { PH[m] = 3; PHT[m] = TICK + 1 } }
function p_advance(   m) {
  for (m = FOOD0; m <= BUB1; m++) {
    if (PH[m] == 3 && TICK >= PHT[m] + 2) { if (RSP[m]) { X[m] = RSX[m]; Y[m] = RSY[m]; BX_[m] = X[m]; AGE[m] = 0; REST[m] = 0; RSP[m] = 0; PH[m] = 1; PHT[m] = TICK + 1 } else PH[m] = 0 }
    else if (PH[m] == 1 && TICK >= PHT[m] + 1) PH[m] = 2
  }
}
function food(m, dt) {
  if (PH[m] != 1 && PH[m] != 2) return
  AGE[m] += dt
  if (Y[m] < sandy(X[m]) - 3) { VY[m] = 15; Y[m] += 15 * dt; X[m] = BX_[m] + 3 * sin(AGE[m] * 2.2 + SEEDF[m]); FROT[m] += 50 * dt }
  else { VY[m] = 0; REST[m] += dt; if (REST[m] > 9 && PH[m] == 2) p_vanish(m) }
}
function bubble(m, dt) {
  if (PH[m] != 1 && PH[m] != 2) return
  AGE[m] += dt
  VY[m] = -(52 + BR_[m] * 6); Y[m] += VY[m] * dt; X[m] = BX_[m] + 3.2 * sin(AGE[m] * 3 + SEEDF[m])
  if (Y[m] < 9 && PH[m] == 2) p_vanish(m)
}
function drop(id,   k, m, x, y, best, age) {
  x = TX[id] + 50; y = TY[id] + 14; RINGS[id] = 1; FORCE[id] = 1
  for (k = 0; k < 2; k++) {
    best = 0; age = -1
    for (m = FOOD0; m <= FOOD1; m++) if (PH[m] == 0) { best = m; break }
    if (!best) for (m = FOOD0; m <= FOOD1; m++) if (AGE[m] > age) { age = AGE[m]; best = m }
    p_launch(best, cl(x + (k - 0.5) * 18 + rr(-5, 5), 12, W - 12), mn(y + k * 5, FLOOR - 30))
  }
  startle(x, y)
}
function startle(x, y,   m) {
  for (m = 1; m <= SPC; m++) if (SPN[m] == "puffer" && hyp(X[m] - x, Y[m] - y) < 200) PUFT[m] = T + 5
  if (hyp(SCX - x, SCY - y) < 360) { SCAT = 1; for (m = NEON0; m <= NEON1; m++) { NK_X[m] = rr(-1, 1); NK_Y[m] = rr(-1, 1) } }
}

function fish(m, dt,   sp, f, best, bd, dist, tx, ty, dx, dy, ease, steer, h, tgt, ymax, ox, oy, ah, a, pn) {
  sp = CRU[m] * (1 + 0.2 * AGI) * SPD
  if (SPN[m] == "puffer") {
    tgt = T < PUFT[m] ? 1 : 0
    if ((ACT[TUR] && hyp(X[TUR] - X[m], Y[TUR] - Y[m]) < 130) || (ACT[RAY] && hyp(X[RAY] - X[m], Y[RAY] - Y[m]) < 130)) tgt = 1
    # the barracuda: the puffer does not bolt, it puffs up
    if (BARIN && hyp(X[BAR] - X[m], Y[BAR] - Y[m]) < 150) tgt = 1
    PUF[m] += (tgt - PUF[m]) * mn(dt * (tgt > PUF[m] ? 2.2 : 0.35), 1)
    sp *= 1 - 0.6 * PUF[m]
  } else {
    # the barracuda: a fish near its path — ahead of it, or just passed — bolts away and forgets food for a while;
    # ahead of it, up or down out of its way; beside or behind it, away along the tank as well. Calm again, it looks
    # for somewhere new to swim.
    pn = PAN[m]; PAN[m] = mx(PAN[m] - dt / 3.5, 0)
    if (pn > 0.15 && PAN[m] <= 0.15) RT[m] = 0
    if (BARIN) {
      dx = X[m] - X[BAR]; dy = Y[m] - Y[BAR]
      if (dx * D[BAR] > -90 && abs(dx) < 260 && abs(dy) < 130) {
        PAN[m] = 1
        FTX[m] = X[m] + (dx * D[BAR] > 0 ? 0.4 : 1) * (dx >= 0 ? 1 : -1) * 150; FTY[m] = Y[m] + (dy >= 0 ? 1 : -1) * 150
      }
    }
  }
  pn = PAN[m] > 0 ? PAN[m] : 0
  best = FB[m]; bd = FD[m]
  if (pn > 0.15) { tx = FTX[m]; ty = FTY[m]; sp *= 1 + 1.4 * pn }
  else if (best && EATER[best] == m) { tx = X[best]; ty = Y[best]; sp *= 1.45; if (bd < FL[m] * 0.45) p_vanish(best) }
  else if (best) {
    # its own place on the ring round the pellet, turning slowly
    a = m * 0.9 + T * 0.3; tx = X[best] + (58 + 0.4 * FL[m]) * cos(a); ty = Y[best] + (30 + 0.25 * FL[m]) * sin(a); sp *= 1.25
  } else {
    RT[m] -= dt
    if (RT[m] <= 0 || hyp(TXF[m] - X[m], TYF[m] - Y[m]) < 25) retarget(m)
    tx = TXF[m]; ty = TYF[m]
  }
  dx = tx - X[m]; dy = ty - Y[m]; dist = mx(hyp(dx, dy), 0.1)
  ease = mn(dist / 60, 1); steer = mn(dt * (1.6 + 3 * pn), 1)
  ox = (dx / dist * sp * ease - VX[m]) * steer; oy = (dy / dist * sp * ease * 0.6 - VY[m]) * steer
  # room between the big fish: a push away from any that is too close
  for (f = 1; f <= SPC; f++) if (f != m) {
    dx = X[m] - X[f]; dy = (Y[m] - Y[f]) * 1.5; dist = hyp(dx, dy); ease = 0.42 * (FL[m] + FL[f]) + 12
    if (dist < ease) { if (dist < 0.1) { dx = m < f ? -1 : 1; dy = 0; dist = 1 }; steer = (ease - dist) / ease * 140 * dt; ox += dx / dist * steer; oy += dy / dist * steer }
  }
  # at most FISHA units/s² of change across, FISHAY up and down: a fish glides round, it never leaps, so a tile knows
  # where it can be at the end of the next glide (prep)
  # (a bolt, up to FISHP and FISHPY)
  a = FISHA + (FISHP - FISHA) * pn; ah = FISHAY + (FISHPY - FISHAY) * pn
  ox = cl(ox, -a * dt, a * dt); oy = cl(oy, -ah * dt, ah * dt)
  VX[m] += ox; VY[m] += oy
  h = SPN[m] == "angel" ? FH[m] * 1.3 : FH[m] * 0.8
  X[m] = cl(X[m] + VX[m] * dt, FL[m] * 0.6, W - FL[m] * 0.6)
  ymax = sandy(X[m]) - h - 6; if (!DEEP) ymax -= 10
  Y[m] = cl(Y[m] + VY[m] * dt, mx(22 + h, FBT[m]), mn(ymax, FBB[m]))
  if (abs(VX[m]) > 4) D[m] += ((VX[m] > 0 ? 1 : -1) - D[m]) * mn(dt * 3.5, 1)
  WAG[m] = 7 + 11 * mn(hyp(VX[m], VY[m]) / 60, 1)
  PIT[m] += (cl(atan2(VY[m], abs(VX[m]) + 8) / RAD, -16, 16) * (D[m] < 0 ? -1 : 1) - PIT[m]) * mn(dt * 3, 1)
}
function retarget(m) {
  RT[m] = rr(3, 8) / (1 + 2 * AGI)
  if (!DEEP && SPN[m] == "clown" && rnd() < 0.7) { TXF[m] = ANX + rr(-70, 70); TYF[m] = sandy(ANX) - rr(45, 90); return }
  TXF[m] = rr(60, W - 60)
  TYF[m] = cl(rr(DMIN[m], DMAX[m]) * (FLOOR - 40) + 20, 40 + FH[m], FLOOR - 40 - FH[m])
}

# The school: a centre that wanders the whole tank and a loose ring around it that breathes. Each fish follows its
# place with a lag; a big fish pushes the places aside, so the school flows around it; food scatters it, and it
# regroups.
function school(dt,   m, best, bd, f, dist, sp, dx, dy, a, ra, rc, al, ac, tx, ty, k, R, ox, oy, ch, sh, own, tp) {
  SCAT = mx(0, SCAT - dt * 0.3); SPH += dt * (0.35 + 0.4 * AGI)
  # the barracuda: the school flinches — a quick loosening — and flees from it together (PSC: its fright)
  PSC = mx(PSC - dt / 4, 0)
  if (BARIN) {
    ox = SCX - X[BAR]; oy = SCY - Y[BAR]
    if (ox * D[BAR] > -120 && abs(ox) < 300 && abs(oy) < 170) {
      if (PSC < 0.5) { SCAT = mx(SCAT, 0.3); for (m = NEON0; m <= NEON1; m++) { NK_X[m] = rr(-1, 1); NK_Y[m] = rr(-1, 1) } }
      PSC = 1; SRT = 3
      STX = cl(SCX + (ox >= 0 ? 1 : -1) * (ox * D[BAR] > 0 ? 70 : 170), 70, W - 70)
      STY = cl(SCY + (oy >= 0 ? 1 : -1) * 160, DEEP ? 90 : 60, DEEP ? FLOOR - 130 : FLOOR - 90)
    }
  }
  best = 0; bd = 500
  if (SCAT < 0.35 && PSC == 0) for (f = FOOD0; f <= FOOD1; f++) if (PH[f] == 2 && REST[f] == 0) { dist = hyp(X[f] - SCX, Y[f] - SCY); if (dist < bd) { bd = dist; best = f } }
  sp = 48 * (1 + 0.2 * AGI) * SPD * (1 + PSC)
  if (best) { STX = X[best]; STY = Y[best]; sp *= 1.5 }
  else { SRT -= dt; if (SRT <= 0 || hyp(STX - SCX, STY - SCY) < 30) { SRT = rr(4, 9); STX = rr(70, W - 70); STY = DEEP ? rr(90, FLOOR - 130) : rr(60, FLOOR - 90) } }
  dx = STX - SCX; dy = STY - SCY; dist = mx(hyp(dx, dy), 0.1)
  SVX += (dx / dist * sp * mn(dist / 80, 1) - SVX) * mn(dt * 1.2, 1); SVY += (dy / dist * sp * 0.7 * mn(dist / 80, 1) - SVY) * mn(dt * 1.2, 1)
  SCX = cl(SCX + SVX * dt, 40, W - 40); SCY = cl(SCY + SVY * dt, 40, FLOOR - 50)
  # the school's heading (flattened: a school swims mostly level) and the pitch it shares
  if (hyp(SVX, SVY) > 5) { STH = atan2(SVY * 0.5, SVX); SPT = cl(atan2(SVY, abs(SVX) + 8) / RAD, -20, 20) }
  if (abs(SVX) > 8) SDIR = SVX > 0 ? 1 : -1
  ch = cos(STH); sh = sin(STH)
  for (m = NEON0; m <= NEON1; m++) {
    # its place on a flat ring stretched along the heading, which slowly turns
    a = NA[m] + SPH * 0.3 + 0.35 * sin(SPH + m)
    ra = (16 + 22 * NR_[m]) * (1 + 1.8 * SCAT); rc = (4 + 8 * NR_[m]) * (1 + 3 * SCAT)
    al = ra * cos(a); ac = rc * sin(a)
    tx = SCX + al * ch - ac * sh + 60 * SCAT * NK_X[m]; ty = SCY + al * sh + ac * ch + 40 * SCAT * NK_Y[m]
    for (k = 1; k <= SPC; k++) {
      R = FL[k] * 0.62 + 12; ox = tx - X[k]; oy = ty - Y[k]; dist = hyp(ox, oy)
      if (dist < R) { if (dist < 0.1) { ox = 0; oy = -1; dist = 1 }; tx = X[k] + ox / dist * R; ty = Y[k] + oy / dist * R }
    }
    if (ACT[TUR]) { ox = tx - X[TUR]; oy = ty - Y[TUR]; dist = hyp(ox, oy); if (dist < 75) { tx = X[TUR] + ox / mx(dist, 0.1) * 75; ty = Y[TUR] + oy / mx(dist, 0.1) * 75 } }
    if (ACT[RAY]) { ox = tx - X[RAY]; oy = ty - Y[RAY]; dist = hyp(ox, oy); if (dist < 80) { tx = X[RAY] + ox / mx(dist, 0.1) * 80; ty = Y[RAY] + oy / mx(dist, 0.1) * 80 } }
    # nobody's place inside the barracuda (a long oval round it)
    if (ACT[BAR]) { ox = (tx - X[BAR]) / 85; oy = (ty - Y[BAR]) / 32; dist = hyp(ox, oy); if (dist < 1) { if (dist < 0.05) { ox = 0; oy = ty < Y[BAR] ? -1 : 1; dist = 1 }; tx = X[BAR] + ox / dist * 85; ty = Y[BAR] + oy / dist * 32 } }
    tx = cl(tx, 14, W - 14); ty = cl(ty, 18, sandy(tx) - 14)
    # the velocity that would reach the place, at most 95 units/s, and at most NEONA units/s² away from the one it
    # has: a dart, never a leap, so a tile always sees a neon coming a tick ahead
    ox = (tx - X[m]) * (2.4 + 1.5 * SCAT); oy = (ty - Y[m]) * (2.4 + 1.5 * SCAT)
    # (frightened: up to 140 units/s and NEONP)
    a = 95 + 45 * PSC; dist = hyp(ox, oy); if (dist > a) { ox *= a / dist; oy *= a / dist }
    a = (NEONA + (NEONP - NEONA) * PSC) * dt
    ox -= VX[m]; oy -= VY[m]; dist = hyp(ox, oy); if (dist > a) { ox *= a / dist; oy *= a / dist }
    VX[m] += ox; VY[m] += oy
    X[m] += VX[m] * dt; Y[m] += VY[m] * dt
    if (best && PH[best] == 2 && hyp(X[best] - X[m], Y[best] - Y[m]) < 7) p_vanish(best)
    # together they face the school's way at its pitch, each a few degrees its own; scattered, each its own way
    own = SCAT > 0.3 || !SDIR
    if (own) { if (abs(VX[m]) > 6) D[m] += ((VX[m] > 0 ? 1 : -1) - D[m]) * mn(dt * 5, 1) }
    else D[m] += (SDIR - D[m]) * mn(dt * 4, 1)
    tp = own ? cl(atan2(VY[m], abs(VX[m]) + 6) / RAD, -24, 24) : SPT + NP_[m]
    PIT[m] += (tp * (D[m] < 0 ? -1 : 1) - PIT[m]) * mn(dt * 4, 1)
  }
}

# The crab walks the floor now and then, from one end of the tank to the other, and goes for food on the sand.
function crab(dt,   f, best, bd, dist) {
  best = 0; bd = 320
  for (f = FOOD0; f <= FOOD1; f++) if (PH[f] == 2 && REST[f] > 0) { dist = abs(X[f] - X[CRAB]); if (dist < bd) { bd = dist; best = f } }
  if (best) {
    CRW = 1; CRD = X[best] > X[CRAB] ? 1 : -1
    if (bd < 10) { p_vanish(best); CRW = 0; CRT = 2; CRV = 0 }
  } else if (BARIN) { CRW = 0; if (CRT < 1.5) CRT = 1.5 }                # it freezes while the barracuda passes
  else {
    CRT -= dt
    if (CRT <= 0) { CRW = !CRW; if (CRW) { CRD = X[CRAB] < W * 0.3 ? 1 : (X[CRAB] > W * 0.7 ? -1 : (rnd() < 0.5 ? -1 : 1)); CRT = rr(3, 7) } else { CRT = rr(6, 12); CRV = 0 } }
  }
  if (CRW) {
    X[CRAB] += CRD * 24 * dt; CRL += dt * 9; VX[CRAB] = CRD * 24
    if (X[CRAB] < 45 || X[CRAB] > W - 45) { CRD = -CRD; X[CRAB] = cl(X[CRAB], 45, W - 45) }
  } else { CRV += dt; VX[CRAB] = 0 }
}

function start_guest(   m, dir, r) {
  GNEXT = T + rr(180, 360)
  m = (GFORCE ? GFORCE : ((r = rnd()) < 1 / 3 ? TUR : (r < 2 / 3 ? RAY : BAR))); GFORCE = 0
  dir = rnd() < 0.5 ? 1 : -1; if (GDIR) { dir = GDIR; GDIR = 0 }
  # outside the tank by more than it can travel before a tile first draws it (two glides ahead): it swims in from
  # the wall; the barracuda, fast and long, needs twice the room
  D[m] = dir; X[m] = (m == BAR ? 340 : 175) * -dir + (dir > 0 ? 0 : W); GY = rr(GB0, GB1); Y[m] = GY; VX[m] = dir * (m == TUR ? 24 : (m == RAY ? 32 : 165)); VY[m] = 0; ACT[m] = 1
}
function guest(dt,   m) {
  m = ACT[TUR] ? TUR : (ACT[RAY] ? RAY : BAR)
  X[m] += VX[m] * dt; Y[m] = GY + 12 * sin(T * 0.25); VY[m] = 3
  if (m == TUR) TPH += dt * 2.2; else if (m == RAY) RPH += dt * 2.6
  if ((D[m] > 0 && X[m] > W + 180) || (D[m] < 0 && X[m] < -180)) ACT[m] = 0
}

function angler(dt,   dx, sp) {
  if (!ACT[ANG]) {
    if (NIGHT > 0.55) { ACT[ANG] = 1; D[ANG] = rnd() < 0.5 ? 1 : -1; X[ANG] = D[ANG] > 0 ? -70 : W + 70; Y[ANG] = rr(AB0, AB1); ATX = rr(80, W - 80); ATY = rr(AB0, AB1); ALEAVE = 0 }
    return
  }
  if (NIGHT < 0.45 && !ALEAVE) { ALEAVE = 1; ATX = X[ANG] < W / 2 ? -120 : W + 120 }
  if (!ALEAVE && (abs(ATX - X[ANG]) < 20 || rnd() < dt * 0.05)) { ATX = rr(60, W - 60); ATY = rr(AB0, AB1) }
  sp = 16 * SPD * (1 + 0.5 * AGI)
  dx = ATX - X[ANG]
  VX[ANG] += ((dx > 0 ? 1 : -1) * sp * mn(abs(dx) / 40, 1) - VX[ANG]) * mn(dt, 1)
  VY[ANG] = (ATY - Y[ANG]) * 0.3
  X[ANG] += VX[ANG] * dt; Y[ANG] = cl(Y[ANG] + VY[ANG] * dt, AB0, AB1)
  if (abs(VX[ANG]) > 3) D[ANG] += ((VX[ANG] > 0 ? 1 : -1) - D[ANG]) * mn(dt * 2, 1)
  # it never shows itself head-on (a round blob with one eye): through the thin middle of a turn it flips at once
  if (abs(D[ANG]) < 0.35) D[ANG] = VX[ANG] > 0 ? 0.35 : -0.35
  LP += dt * 1.6
  if (ALEAVE && (X[ANG] < -110 || X[ANG] > W + 110)) ACT[ANG] = 0
}

# ---------------------------------------------------------------- live: the phone's view, taps, ticks
function view(body,   cols, ori, p, n, parts, k, id, row, col, rs, cs, gi, me, ids, cnt, nid, i, keep, gs, gg, gap) {
  SHOWN = 0
  # a phone that went away comes back without the frames it had: every tile is sent again then
  if (body !~ /"connected":true/ || body ~ /"view":null/) GONE = 1
  if (body !~ /"connected":true/ || body ~ /"view":null/ || body ~ /"isForeground":false/) return
  body = mine(body)
  if (!match(body, /"columns":[0-9]+/)) return
  cols = substr(body, RSTART + 10, RLENGTH - 10) + 0
  if (cols < 1 || cols > 12) return
  ori = body ~ /"orientation":"landscape"|"isLandscape":true/ ? "landscape" : "portrait"
  # the gap between cells, in world units (a window is 100): from the grid's cell side and gap in points; an app
  # that does not say draws the windows side by side, as before
  gs = jflt(body, "cellSize", 0); gg = jflt(body, "cellGap", -1)
  gap = gs > 0 && gg >= 0 ? int(1000 * gg / gs + 0.5) / 10 : 0; if (gap > 40) gap = 40
  p = index(body, "\"cells\":["); if (!p) return
  n = cells_of(substr(body, p + 9), parts); me = 0; cnt = 0
  for (k = 1; k <= n; k++) {
    id = jstr(parts[k], "id"); if (id == "") continue
    id = toupper(id); if (id == ME) me = 1
    gi = jstr(parts[k], "galleryItem"); if (gi !~ /^aquarium\./) continue
    row = jnum(parts[k], "row", -1); col = jnum(parts[k], "col", -1); rs = jnum(parts[k], "rowSpan", 1); cs = jnum(parts[k], "colSpan", 1)
    if (rs != 1 || cs != 1 || row < 0 || row > 7 || col < 0 || col >= cols) continue
    ids[++cnt] = id; VR[id] = row; VC[id] = col
  }
  if (!me) return
  SHOWN = 1
  if (cols != COLS || ori != ORI || abs(gap - GAP) > 0.5) { GAP = gap; world(cols, ori); NT = 0; delete ORD }
  # keep what the tiles that stayed in place know; a new or moved tile starts over with a cross-fade
  delete keep
  for (i = 1; i <= NT; i++) keep[ORD[i]] = 1
  NT = 0; nid = 0
  for (i = 1; i <= cnt; i++) {
    id = ids[i]; window_of(VR[id], VC[id])
    ORD[++NT] = id
    if (!(id in keep) || TX[id] != WX_ || TY[id] != WY_ || THH[id] != 100) { tile(id, WX_, WY_, 100, 100); nid++ }
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
# Splits the "cells" array (from just after its "[") into its objects, each with only its own top-level fields: a
# field a later app adds inside a cell (an object, an array) never breaks the reading. Returns how many.
function cells_of(s, out,   n, i, c, depth, str, esc, cur, len) {
  n = 0; depth = 0; str = 0; esc = 0; cur = ""; len = length(s)
  for (i = 1; i <= len; i++) {
    c = substr(s, i, 1)
    if (str) { if (depth == 1) cur = cur c; if (esc) esc = 0; else if (c == "\\") esc = 1; else if (c == "\"") str = 0; continue }
    if (c == "\"") { str = 1; if (depth == 1) cur = cur c; continue }
    if (c == "{" || c == "[") { depth++; if (depth == 1) cur = ""; continue }
    if (c == "}" || c == "]") {
      if (depth == 0) break
      if (depth == 1 && c == "}") out[++n] = cur
      depth--; continue
    }
    if (depth == 1) cur = cur c
  }
  return n
}
function jstr(s, key,   p) { if (!match(s, "\"" key "\":\"[^\"]*\"")) return ""; return substr(s, RSTART + length(key) + 4, RLENGTH - length(key) - 5) }
function jflt(s, key, def) { if (!match(s, "\"" key "\":-?[0-9]+(\\.[0-9]+)?")) return def; return substr(s, RSTART + length(key) + 3, RLENGTH - length(key) - 3) + 0 }
function jnum(s, key, def) { if (!match(s, "\"" key "\":-?[0-9]+")) return def; return substr(s, RSTART + length(key) + 3, RLENGTH - length(key) - 3) + 0 }

function tap(id,   i) { id = toupper(id); for (i = 1; i <= NT; i++) if (ORD[i] == id) { drop(id); return } }

# Every tile is served on the same tick, once a period, with a glide a third longer than the period: a frame the
# Wi-Fi brings late takes over a creature still moving. The phone starts each glide from what is on screen, and that
# smoothing depends on when the frames come — tiles served at other moments (the two halves this page once had) drew
# a turning fish's halves a few units apart, which then slid together. So: one moment for every tile.
function tick(now, minutes, load, slow,   dt, i, id, s, dur, mode, agt, per, half, k, q) {
  # a tile's period: PERS s, PERL on a big page (the iPad's 48 tiles); 2 s while the phone is not reading
  per = slow ? 2 : (NT > 36 ? PERL : PERS); half = per; PER = half
  if (!SHOWN || !NT) { NOW = now; RESUMED = 1; reply(); return }
  # the world waits while nobody looks, and never takes a leap: a late tick moves it by one tick at most
  dt = NOW > 0 && !RESUMED ? now - NOW : half; if (dt > 1.3 * half || dt < 0) dt = half
  NOW = now; RESUMED = 0
  # the Mac's load clouds the water slowly, and only when it really changed: 0.1 at a time, at most every 15 s
  agt = cl(int((load - 0.45) / 0.6 * 10 + 0.5) / 10, 0, 1)
  if (AGI < 0) AGI = agt
  else if (abs(agt - AGI) > 0.15 && T - AGIT >= 15) { AGI = int((AGI + (agt > AGI ? 0.1 : -0.1)) * 10 + 0.5) / 10; AGIT = T }
  if (light(minutes, AGI)) relight()
  sim(dt)
  prep(per)
  # a glide lasts a third longer than the period: a frame the Wi-Fi brings late takes over a creature still moving
  TICK++; DB = GLIDE * per; DA = 3 * per * 1.08; TB = T; TA = T + (DA - DB); follow(per)
  # a change of light reaches the tiles a few at a time — about 25 recoloured elements a tick (a tile of busy coral
  # waits for enough credit): the phone never recolours the whole page at once
  RCRED = mn(RCRED + 25, 90)
  for (k = 1; k <= NT; k++) {
    id = ORD[UPC % NT + 1]
    if (TLG[id] != LGEN) { if (TSN[id] > RCRED) break; upgrade(id); UPG[id] = 1; RCRED -= TSN[id] }
    UPC = UPC % NT + 1
  }
  # one tile a tick whose frame has not changed for a while is sent again, should the phone have lost it
  KAC = KAC % NT + 1; id = ORD[KAC]; if (now - LASTT[id] > 45) KEEP[id] = 1
  REQ = ""; NREQ = 0
  for (i = 1; i <= NT; i++) {
    id = ORD[i]
    busy(id)
    # a tile that was quick on its last turn and is slow now gets its long frame at once (its short glide would end
    # long before its slow turn, and the scenery would stand)
    q = WASB[id]; WASB[id] = BF || FORCE[id]
    if (BF || FORCE[id]) mode = 0
    else if ((TICK + i) % 3 == 0 || UPG[id] || KEEP[id] || q) mode = 1
    else continue
    s = compose(id, mode)
    if (!FORCE[id] && !KEEP[id] && s == LAST[id]) { UPG[id] = 0; continue }
    dur = FIRST[id] ? 0.35 : (mode == 1 ? DA : DB)
    post(id, s, dur)
    LAST[id] = s; LASTT[id] = now; FORCE[id] = 0; FIRST[id] = 0; UPG[id] = 0; KEEP[id] = 0
    if (RINGS[id]) RINGS[id] = RINGS[id] >= 2 ? 0 : RINGS[id] + 1
  }
  follow_done()
  p_advance()
  reply()
}
function post(id, s, dur,   body) {
  body = "{\"cellId\":\"" id "\",\"svg\":{\"source\":\"" s "\",\"duration\":" sprintf("%.2f", dur) ",\"easing\":\"linear\",\"fit\":\"stretch\"}}"
  REQ = REQ "POST /api/update-button HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer " TOKEN "\r\nContent-Type: application/json\r\nContent-Length: " length(body) "\r\n\r\n" body
  NREQ++
}
function reply() { printf "B %d %d %d %.2f\n%s", length(REQ), NREQ, SHOWN, PER ? PER : 1, REQ; fflush(); REQ = ""; NREQ = 0 }
function resync(   i) { for (i = 1; i <= NT; i++) FORCE[ORD[i]] = 1 }
function quit(   i, body) {
  REQ = ""; NREQ = 0
  for (i = 1; i <= NT; i++) {
    body = "{\"cellId\":\"" ORD[i] "\",\"svg\":{\"remove\":true}}"
    REQ = REQ "POST /api/update-button HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer " TOKEN "\r\nContent-Type: application/json\r\nContent-Length: " length(body) "\r\n\r\n" body
    NREQ++
  }
  printf "Q %d %d %d 1\n%s", length(REQ), NREQ, SHOWN, REQ; fflush()
}

# ---------------------------------------------------------------- tool modes: fixed seed, fixed clock, no network
# A world of this shape with every tile of the page, a story that shows everything (a guest, the chest, food), run
# for `steps` ticks of 0.45 s from a fixed seed. Every tile is composed on every tick, so what a tile tracks is what it
# would track live.
function story(cols, ori, minutes, steps, gkind, gstart,   r, c, k, id, i, drop_at, drop_id, sc) {
  SEED = 20260930; BSEED = 4242; T = 0; TICK = 0; TOOL = 1; AGI = 0
  # every story starts from nothing: the same seed, the same cast, the same moment
  CAST = 0; W = 0; H = 0; COLS = 0; SPH = 0; SVX = 0; SVY = 0; STX = 0; STY = 0; SRT = 0; SCAT = 0; LP = 0; TPH = 0; RPH = 0
  CRL = 0; CRV = 0; CRW = 0; CRT = 1; ACT[ANG] = 0; NBQ = 0; delete TST; delete MVT; delete MIT; delete GEV
  STH = 0; SDIR = 0; SPT = 0; delete RINGS; LIGHTDIG = ""; delete PAN; delete RISK; PSC = 0; SRISK = 0; BARIN = 0
  world(cols, ori)
  NT = 0
  for (r = 0; r < 8; r++) for (c = 0; c < cols; c++) { id = sprintf("R%dC%d", r, c); window_of(r, c); ORD[++NT] = id; RRW[id] = r; RCL[id] = c; tile(id, WX_, WY_, 100, 100) }
  GNEXT = gstart ? gstart : 6; GFORCE = gkind == "turtle" ? TUR : (gkind == "ray" ? RAY : (gkind == "barracuda" ? BAR : 0)); GDIR = 1; CHT0 = -100; CHNEXT = STILLCHEST ? STILLCHEST : 14; BT = 0
  if (DEEP && minutes >= 0) { light(minutes, 0); if (NIGHT > 0.55) { ACT[ANG] = 1; D[ANG] = 1; X[ANG] = W * 0.45; Y[ANG] = (AB0 + AB1) / 2; ATX = W * 0.8; ATY = Y[ANG]; ALEAVE = 0 } }
  LIGHTKEY = ""; LIGHTDIG = ""
  drop_at = steps - 8; drop_id = sprintf("R%dC%d", 3, 1)
  for (k = 1; k <= steps; k++) {
    if (light(minutes, 0)) relight()
    if (k == drop_at && DROPS) drop(drop_id)
    sim(0.45); prep(0.45)
    TICK++; TB = T; TA = T
    if (SCOREFROM && k >= SCOREFROM) { sc = score(); if (sc > BESTSC) { BESTSC = sc; BESTK = k; BESTG = gstart } }
    if (k == steps) return
    # a live-like dump composes every tile each tick (what a tile tracks is what it would track live); a still picture
    # draws what it sees, so its stories skip that
    if (!STILL) for (i = 1; i <= NT; i++) { compose(ORD[i], 0); FIRST[ORD[i]] = 0; if (RINGS[ORD[i]]) RINGS[ORD[i]] = RINGS[ORD[i]] >= 2 ? 0 : RINGS[ORD[i]] + 1 }
    p_advance()
  }
}
function start(mode, a, b, c, d,   i, id) {
  if (mode == "live") { ME = toupper(a); SEED = (b + 0) % 2147483000 + 1; BSEED = SEED % 99991 + 7; CHT0 = -100; CHNEXT = 25 + rnd() * 20; GNEXT = 70 + rnd() * 50; BT = 1; return }
  if (mode == "dump") {
    GAP = GDEMO; DROPS = 1; story(a + 0, b, c + 0, d + 0, 0)
    printf "["
    for (i = 1; i <= NT; i++) { id = ORD[i]; printf "%s{\"row\":%d,\"col\":%d,\"svg\":\"%s\"}", (i > 1 ? "," : ""), RRW[id], RCL[id], compose(id, 0) }
    print "]"
    return
  }
  # still pictures: the same story with the guest arriving at other times, scored at every tick; the best is told again
  if (mode == "faces") {
    # the sample: the iPad's page turned (the 8×6 reef), as the Gallery shows a scene; an iPhone shows its lower four
    # rows (SHOWY), so the moment is chosen with the fish there
    STILL = 1; SCOREFROM = 30; BESTSC = -1e9; GAP = GDEMO; SHOWX = 1e9; SHOWY = 2 * (100 + GAP) + 10; TILES = 1
    for (i = 0; i < 16; i++) story(6, "landscape", 11 * 60, int((26 + 7 * i) / 0.45), "turtle", 6 + 7 * i)
    SCOREFROM = 0; STILLCHEST = BESTK * 0.45 - 2.4; story(6, "landscape", 11 * 60, BESTK, "turtle", BESTG)
    printf "{"
    for (i = 1; i <= NT; i++) { id = ORD[i]; printf "%s\"r%dc%d\":{\"rest\":\"%s\",\"demo\":\"%s\"}", (i > 1 ? "," : ""), RRW[id], RCL[id], rest(RRW[id], RCL[id]), compose(id, 2) }
    print "}"
    return
  }
  if (mode == "cover") {
    STILL = 1; SCOREFROM = 30; BESTSC = -1e9; GAP = 0; SHOWX = 800; SHOWY = -1e9; TILES = 0
    for (i = 0; i < 8; i++) story(4, "landscape", 10 * 60 + 30, int((36 + 9 * i) / 0.45), "ray", 6 + 9 * i)
    SCOREFROM = 0; STILLCHEST = BESTK * 0.45 - 2.4; story(4, "landscape", 10 * 60 + 30, BESTK, "ray", BESTG)
    NT = 1; ORD[1] = "COVER"; tile("COVER", 0, 0, W, H); relight()
    print compose("COVER", 2)
    return
  }
}
# How good a moment is for a still picture: fish spread out, none in the middle of a turn or across another, most of
# them where an iPhone shows the page too, the guest well inside, the chest open and the crab clear of it.
function score(   m, n, sc, dmin, dd, g, f, inside) {
  dmin = 170; sc = 0
  for (m = 1; m <= SPC; m++) {
    for (n = m + 1; n <= SPC; n++) { dd = hyp(X[m] - X[n], (Y[m] - Y[n]) * 1.3); if (dd < dmin) dmin = dd; if (dd < 0.55 * (FL[m] + FL[n])) sc -= 90 }
    if (abs(D[m]) < 0.92) sc -= 150
    if (X[m] < SHOWX - 30 && Y[m] > SHOWY + 30) sc += 12
    # cut by a gap: its body crosses a tile's border
    if (TILES && (int((X[m] - 0.4 * FL[m]) / PITCH) != int((X[m] + 0.4 * FL[m]) / PITCH) || int((Y[m] - 0.6 * FH[m]) / PITCH) != int((Y[m] + 0.6 * FH[m]) / PITCH))) sc -= 60
  }
  # the school: all one way, in open water, where an iPhone shows the page too, most of it in one tile
  inside = 0
  for (m = NEON0; m <= NEON1; m++) {
    if (abs(D[m]) < 0.8) sc -= 15
    for (f = 1; f <= SPC; f++) if (hyp(X[m] - X[f], (Y[m] - Y[f]) * 1.3) < 30 + 0.45 * FL[f]) { sc -= 35; break }
    if (int(X[m] / PITCH) == int(SCX / PITCH) && int(Y[m] / PITCH) == int(SCY / PITCH)) inside++
  }
  if (SCX < SHOWX - 60 && SCY > SHOWY + 40) sc += 120
  # the chest, the scene's centrepiece, not hidden by the crab
  if (abs(X[CRAB] - CHX) < 62) sc -= 200
  if (TILES) sc += 22 * inside
  # no bubble across a fish
  for (m = BUB0; m <= BUB1; m++) if (PH[m] == 2) for (f = 1; f <= SPC; f++) if (abs(X[m] - X[f]) < 0.6 * FL[f] && abs(Y[m] - Y[f]) < FH[f]) sc -= 30
  # the guest well inside, clear of the fish — the ray with its long tail behind it
  g = ACT[TUR] ? TUR : RAY
  if (!ACT[g] || X[g] < 130 || X[g] > mn(W, SHOWX) - 130) sc -= 600
  else for (m = 1; m <= SPC; m++) {
    if (abs(X[m] - X[g]) < (g == RAY ? 70 : 60) + 0.4 * FL[m] && abs(Y[m] - Y[g]) < (g == RAY ? 62 : 45) + 0.5 * FH[m]) sc -= 150
    if (g == RAY && abs(Y[m] - Y[g]) < 24 && (X[m] - X[g]) * D[g] < 0 && abs(X[m] - X[g]) < 115) sc -= 80
  }
  return sc + 1.5 * dmin
}
# A tile's resting face: plain water and now and then a faint bubble — nothing that says where it stands, since after a
# turn the same tile may be anywhere in the tank. The live scene cross-fades in over it.
function rest(row, col,   s, k, n, x, y, r) {
  SSEED = 104729 * (31 + row * 17 + col * 5) % 2147483647
  s = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><rect x='-1' y='-1' width='102' height='102' fill='#0F4A76'/>"
  n = int(srnd() * 2.6)
  for (k = 0; k < n; k++) {
    x = sr(18, 82); y = sr(18, 82); r = sr(2, 4.6)
    s = s "<circle cx='" f1(x) "' cy='" f1(y) "' r='" f1(r) "' fill='#DDF5FF' fill-opacity='0.08' stroke='#EAFAFF' stroke-opacity='0.3' stroke-width='1.1'/>"
  }
  return s "</svg>"
}

{
  c = $1
  if (c == "S") { tick($2 + 0, $3 + 0, $4 + 0, $5 + 0); next }
  if (c == "V") { view(substr($0, 3)); next }
  if (c == "F") { if (SHOWN) tap($2); next }
  if (c == "R") { resync(); next }
  if (c == "Q") { quit(); exit }
  if (c == "M") { start($2, $3, $4, $5, $6); if ($2 != "live") exit; next }
}
AWK
}

usage() {
  print -u2 -- "usage: engine.zsh [--faces out.json | --cover out.svg | --dump <4|6> <portrait|landscape> <HH:MM> <step> out.json]"
  exit 2
}
case $1 in
  --faces) (( $# == 2 )) || usage; print -r -- "M faces" | aq_world > $2; exit $? ;;
  --cover) (( $# == 2 )) || usage; print -r -- "M cover" | aq_world > $2; exit $? ;;
  --dump)
    (( $# == 6 )) && [[ $2 == (4|6) && $3 == (portrait|landscape) && $4 == <0-23>:<0-59> && $5 == <1-5000> ]] || usage
    print -r -- "M dump $2 $3 $(( ${4%%:*} * 60 + ${4##*:} )) $5" | aq_world > $6; exit $? ;;
  "") ;;
  *) usage ;;
esac

# ---------------------------------------------------------------- live
port=9848
cell="{{CELL_ID}}"
token=$DESMAPTIC_TOKEN
store="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/aquarium"
typeset -F SECONDS
typeset -F period=1 load=0 load_at=-100 next=0
integer shown=0 slow=0 pause=0 quitting=0 changed=0
typeset -a lines ld

last_log=""
log_once() { [[ $1 == "$last_log" ]] && return; last_log=$1; print -u2 -r -- "aquarium: $1"; }

# One keep-alive connection to the agent, HTTP/1.1 by hand (the pattern of the catalog's Now Playing). `owed` counts the
# answers still to read on it, `writing` is 1 while a request goes out: a stop in the middle of either must not lose
# the frames that take the faces off.
sock="" http_status=0 http_body="" rx=""
integer api_failures=0 auth_failures=0 owed=0 writing=0
typeset -F api_retry_at=0

api_close() { [[ -n $sock ]] && ztcp -c $sock 2>/dev/null; sock="" rx="" owed=0; }

api_connect() {
  (( SECONDS >= api_retry_at )) || return 1
  if ztcp 127.0.0.1 $port 2>/dev/null; then
    sock=$REPLY api_failures=0 rx=""
    # a new connection: the world sends every tile again (not while quitting: the world has ended)
    (( quitting )) || print -u $aq_in R
    return 0
  fi
  (( api_failures++ ))
  (( api_retry_at = SECONDS + (api_failures > 5 ? 5 : 0.25 * (1 << (api_failures - 1))) ))
  log_once "the agent does not answer on port $port; retrying"
  # Nobody left to talk to: the agent that started this script is gone.
  (( api_failures == 1 || api_failures % 12 == 0 )) && [[ $(ps -o ppid= -p $$ 2>/dev/null) == *[[:space:]]1 ]] && exit 0
  return 1
}

# Writes a request (or a tick's worth of them) to the socket; `n` answers are then owed.
api_write() {
  writing=1
  print -rn -u $sock -- "$1" 2>/dev/null || { writing=0; api_close; return 1; }
  writing=0; (( owed += $2 ))
  return 0
}

# Reads one whole response from the socket into http_status and http_body. Returns 1 when none came.
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
    # A stale token never heals by itself: the agent restarts the script with a fresh one.
    (( ++auth_failures >= 3 )) && { print -u2 -- "aquarium: the agent does not accept DESMAPTIC_TOKEN"; exit 4; }
  else
    auth_failures=0
  fi
  (( close )) && api_close
  return 0
}

# GET /api/view over the connection into vbody. Returns 1 when none came.
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

# The world's answers come through one buffer, whole or not at all, so a stop in the middle of reading one leaves the
# rest where the next reader finds it. One answer: its header line in whead, its bytes in wbody.
wbuf="" whead="" wbody=""
world_reply() {
  local chunk
  integer need
  while [[ $wbuf != *$'\n'* ]]; do sysread -i $aq_out -s 65536 $@ chunk || return 1; wbuf+=$chunk; done
  whead=${wbuf%%$'\n'*}
  need=${${(s: :)whead}[2]}
  while (( ${#wbuf} - ${#whead} - 1 < need )); do sysread -i $aq_out -s 65536 $@ chunk || return 1; wbuf+=$chunk; done
  wbody=${wbuf[${#whead}+2,${#whead}+1+need]}
  wbuf=${wbuf[${#whead}+2+need,-1]}
  return 0
}

# The frames of one tick: awk writes the requests; they go to the socket as one piece; every answer is read back.
integer drops=0
send_tick() {
  integer count got=0
  world_reply || { print -u2 -- "aquarium: the world stopped"; exit 1; }
  count=${${(s: :)whead}[3]} shown=${${(s: :)whead}[4]} period=${${(s: :)whead}[5]}
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

coproc aq_world live
exec {aq_in}>&p {aq_out}<&p
print -r -u $aq_in -- "M live $cell $EPOCHSECONDS"
trap 'quit' TERM INT HUP
trap '' PIPE

# Stopped: take the faces off every tile drawn. The agent sends TERM to the whole group and KILL two seconds later;
# the world ignores the TERM and answers Q with the removing frames. A tick that was on its way is thrown away, a
# request cut in half closes the connection (a fresh one takes the removes), and every answer owed is read before the
# socket closes — closing it with unread answers would reset it and lose the removes.
quit() {
  trap '' TERM INT HUP
  quitting=1
  print -u $aq_in Q 2>/dev/null
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

while true; do
  typeset -F t0=$SECONDS
  # the view goes to the world only when it changed (the world keeps the last one)
  fetch_view || vbody="-"
  if [[ $vbody != "$vlast" ]]; then vlast=$vbody; print -r -u $aq_in -- "V $vbody"; fi
  # taps: every tile's tap appends its id; the file is taken whole each tick — shown or not, so it never grows — and
  # the world uses a tap only while its page is on screen
  if [[ -s $store/taps ]] && zf_mv -f $store/taps $store/taps.work 2>/dev/null; then
    lines=( ${(f)"$(<$store/taps.work)"} )
    zf_rm -f $store/taps.work
    for line in $lines[1,40]; do [[ -n $line && $line != *[^0-9A-Fa-f-]* ]] && print -r -u $aq_in -- "F $line"; done
  fi
  if (( SECONDS - load_at >= 5 )); then
    load_at=$SECONDS
    ld=( ${=$(sysctl -n vm.loadavg hw.ncpu 2>/dev/null)} )
    (( ${#ld} >= 6 && ld[6] > 0 )) && load=$(( ld[2] / ld[6] ))
  fi
  strftime -s hm '%H %M' $EPOCHSECONDS
  # A phone that is not reading drops frames: one tick every 2 s until it reads again.
  print -r -u $aq_in -- "S $EPOCHREALTIME $(( ${hm% *} * 60 + ${hm#* } )) $load $drops"
  send_tick
  # Until the next tick the view is looked at every 0.2 s while the page is on screen: a turned phone, a moved tile
  # or another page ticks at once. Off screen, a tick every 0.5 s.
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
