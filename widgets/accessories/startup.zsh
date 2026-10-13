#!/bin/zsh
# Accessories: battery of the keyboard, mouse and trackpad connected over Bluetooth, as small neon gauges marked by drawings
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
reader=0
trap '(( reader > 0 )) && kill $reader 2>/dev/null; exit 0' TERM INT
zmodload zsh/datetime zsh/zselect || { print -u2 -- "accessories: zsh modules datetime/zselect are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir 2>/dev/null

# ---- frame ----
# One template for every frame and both layouts: the rest glyph, nothing connected, one to three gauges.
# All three gauges always exist (keyboard, mouse, trackpad, in that order); one that is not shown waits invisible
# at its place in the three-gauge row. Only numbers, colours and text change, so the phone glides between frames.
# Attribute quotes are written as ` and turned into " at the end.
read -r -d '' ACCESSORIES_AWK <<'AWK'
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
function glowGrad(id, c, a) {
  return "<radialGradient id=`" id "`><stop offset=`0` stop-color=`" c "` stop-opacity=`" f(a) "`/>" \
    "<stop offset=`0.4` stop-color=`" c "` stop-opacity=`" f(0.4 * a) "`/><stop offset=`1` stop-color=`" c "` stop-opacity=`0`/></radialGradient>"
}
function rrect(id, x, y, w, h, rx, stroke, a, sw) {
  return "<rect id=`" id "` x=`" f(x) "` y=`" f(y) "` width=`" f(w) "` height=`" f(h) "` rx=`" f(rx) "` fill=`none` stroke=`" stroke "` stroke-opacity=`" f(a) "` stroke-width=`" f(sw) "`/>"
}
function line(id, d, stroke, a, sw, dash) {
  return "<path id=`" id "` d=`" d "` fill=`none` stroke=`" stroke "` stroke-opacity=`" f(a) "` stroke-width=`" f(sw) "` stroke-linecap=`round`" \
    (dash != "" ? " stroke-dasharray=`" dash "`" : "") "/>"
}

# --- the drawings: a keyboard (keys in two dotted rows and a space bar), a mouse (a pill with the button seam)
# and a trackpad (a plain slab with a fingertip); each is centred on (x, y) at scale s ---
function keyboard(id, x, y, s, c, a, keys, ka, sw, kw) {
  return rrect(id "Body", x - 20 * s, y - 11 * s, 40 * s, 22 * s, 4.5 * s, c, a, sw) \
    line(id "Keys", "M " f(x - 12.5 * s) " " f(y - 5 * s) " H " f(x + 12.5 * s) " M " f(x - 12.5 * s) " " f(y + 0.5 * s) " H " f(x + 12.5 * s), \
      keys, ka, kw, "0.1 " f(5 * s - 0.1)) \
    line(id "Space", "M " f(x - 7 * s) " " f(y + 6 * s) " H " f(x + 7 * s), keys, ka, kw, "")
}
function mouse(id, x, y, s, c, a, keys, ka, sw, kw) {
  return rrect(id "Body", x - 8.5 * s, y - 13 * s, 17 * s, 26 * s, 8.5 * s, c, a, sw) \
    line(id "Seam", "M " f(x) " " f(y - 13 * s) " V " f(y - 5.5 * s), keys, ka, kw, "")
}
function trackpad(id, x, y, s, c, a, keys, ka, sw) {
  return rrect(id "Body", x - 16 * s, y - 11 * s, 32 * s, 22 * s, 4 * s, c, a, sw) \
    "<circle id=`" id "Touch` cx=`" f(x + 5 * s) "` cy=`" f(y + 2.5 * s) "` r=`" f(2.8 * s) "` fill=`" keys "` fill-opacity=`" f(ka) "`/>"
}

# A small neon gauge: the disk-free arc (240°, lit from the empty end, white core, glow, halo and bead at the tip),
# the level in % inside and the device's drawing under it. v: level in %, -1 = not shown (the gauge is invisible).
function gauge(id, cx, cy, r, v, vz,   L, k, known, fr, lit, crit, off, d, ang, bx, by, x1, x2, gc, a, o, out, arc, vt, vs, fill, my) {
  L = r * 4.18879                              # arc length: r · 240° = r · 4π/3
  k = r / 56                                   # strokes and the drawing grow with the gauge
  known = (v >= 0)
  fr = known ? clamp(v / 100, 0, 1) : 0
  o = live * known                             # the gauge is on the face
  lit = o
  crit = known && v <= 20
  off = L * (1 - fr)                           # lit dash covers 0 … L·fr
  d = L * fr; if (d > L - 0.3) d = L - 0.3     # bead: a 0.1-long dash at L·fr, kept on the path
  ang = -120 + 240 * fr                        # the tip, degrees clockwise from 12 o’clock
  bx = cx + (r - 3) * sin(ang * pi / 180); by = cy - (r - 3) * cos(ang * pi / 180)
  x1 = cx - 0.95 * r; x2 = cx + 0.95 * r
  gc = crit ? "#FF375F" : spectrum((bx - x1) / (x2 - x1))   # the glow takes the arc colour under the bead
  arc = "d=`M " f(cx - 0.866025 * r) " " f(cy + r / 2) " A " f(r) " " f(r) " 0 1 1 " f(cx + 0.866025 * r) " " f(cy + r / 2) "` fill=`none`"
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
  vt = known ? sprintf("%d%%", v) : "—"
  vs = (length(vt) >= 4) ? int(vz * 0.875 + 0.5) : vz   # "100%" is one character wider
  out = out "<text id=`" id "Value` x=`" f(cx) "` y=`" f(cy - 3 * k) "` font-size=`" vs "` font-weight=`600` text-anchor=`middle` dominant-baseline=`middle` fill=`" fill "` fill-opacity=`" f(o) "`>" vt "</text>"

  a = o * (crit ? 0.95 : 0.6)                  # the drawing under the value: white 0.6 like every unit of the family
  my = cy + 0.48 * r + 12 * k
  if (id == "k") out = out keyboard(id, cx, my, k, fill, a, fill, a, 2.5 * k, 2.4 * k)
  else if (id == "m") out = out mouse(id, cx, my, k, fill, a, fill, a, 2.5 * k, 2.2 * k)
  else out = out trackpad(id, cx, my, k, fill, a, fill, a, 2.5 * k)
  body = body out
  if (crit && live && (worst < 0 || v < worst)) { worst = v; wx = cx; wy = cy; wr = r }
}

BEGIN {
  pi = 3.14159265
  P = (ly != "l")
  live = (st == "live"); none = (st == "none")
  lv[1] = kb + 0; lv[2] = ms + 0; lv[3] = tp + 0
  n = 0
  for (i = 1; i <= 3; i++) { if (!live || lv[i] < 0) lv[i] = -1; if (lv[i] >= 0) n++ }
  if (live && n == 0) { live = 0; none = 1 }
  defs = ""; body = ""; worst = -1

  # --- layout: 2×1 is a row of gauges that grow as fewer are shown; its 1×2 landscape stacks them.
  # Row 3 is the three-gauge layout, and also where a gauge that is not shown waits ---
  if (P) {
    vb = "0 0 400 200"
    split("68 200 332", X3); split("104 104 104", Y3); R3 = 56; V3 = 32
    split("108 292", X2);    split("106 106", Y2);     R2 = 66; V2 = 40
    split("200", X1);        split("108", Y1);         R1 = 78; V1 = 50
    rgx = 200; rgy = 100; ngx = 200; ngy = 86; sgx = 200; sgy = 182; dy = 158     # glyph: rest, nothing connected, sunk
    kox = -22; koy = 0; mox = 66; moy = 1                                         # keyboard and mouse around the glyph centre
    brX = 200; brY = 110; brR = 170
  } else {
    vb = "0 0 200 400"
    split("100 100 100", X3); split("80 204 328", Y3); R3 = 52; V3 = 32
    split("100 100", X2);     split("112 296", Y2);    R2 = 64; V2 = 40
    split("100", X1);         split("207", Y1);        R1 = 74; V1 = 50
    rgx = 100; rgy = 200; ngx = 100; ngy = 178; sgx = 100; sgy = 378; dy = 290
    kox = 0; koy = -32; mox = 0; moy = 36
    brX = 100; brY = 204; brR = 190
  }

  j = 0
  for (i = 1; i <= 3; i++) {
    id = (i == 1) ? "k" : (i == 2) ? "m" : "t"
    if (lv[i] >= 0) {
      j++
      if (n == 3)      { x = X3[j]; y = Y3[j]; r = R3; vz = V3 }
      else if (n == 2) { x = X2[j]; y = Y2[j]; r = R2; vz = V2 }
      else             { x = X1[j]; y = Y1[j]; r = R1; vz = V1 }
    } else { x = X3[i]; y = Y3[i]; r = R3; vz = V3 }
    gauge(id, x, y, r, lv[i], vz)
  }

  # --- bloom: a soft violet glow; it heats up and moves onto the lowest gauge at 20 % and below ---
  bX = rgx; bY = rgy; bR = 120; bC = "#BF5AF2"; bA = 0.12; mC = "#5E5CE6"; bM = 0.04
  if (none) bA = 0.07
  if (live) { bX = brX; bY = brY; bR = brR; bA = 0.16; bM = 0.06 }
  if (worst >= 0) { bX = wx; bY = wy; bR = wr + 44; bC = "#FF375F"; bA = 0.5; mC = "#BF5AF2"; bM = 0.15 }

  # --- the rest glyph: a big neon keyboard and mouse; with data they sink to the bottom and dissolve,
  # with nothing connected they stay up, dim, over a dash ---
  if (live) { gx = sgx; gy = sgy; k = 0.3; go = 0; po = 0 }
  else if (none) { gx = ngx; gy = ngy; k = 0.9; go = 0.3; po = 0.3 }
  else { gx = rgx; gy = rgy; k = 1; go = 0.75; po = 1 }
  kx = gx + kox * k; ky = gy + koy * k; mx = gx + mox * k; my = gy + moy * k
  defs = defs "<linearGradient id=`glyphG` gradientUnits=`userSpaceOnUse` x1=`" f(gx - 84 * k) "` y1=`" f(gy - 60 * k) "` x2=`" f(gx + 84 * k) "` y2=`" f(gy + 60 * k) "`><stop offset=`0` stop-color=`#BF5AF2`/><stop offset=`1` stop-color=`#64D2FF`/></linearGradient>"
  body = body rrect("bigKb", kx - 60 * k, ky - 24 * k, 120 * k, 48 * k, 10 * k, "url(#glyphG)", go, 5 * k)
  body = body line("bigKeys", "M " f(kx - 46 * k) " " f(ky - 10 * k) " H " f(kx + 46 * k) " M " f(kx - 46 * k) " " f(ky + 1 * k) " H " f(kx + 46 * k), \
    "url(#glyphG)", po, 5 * k, "0.1 " f(11.5 * k - 0.1))
  body = body line("bigSpace", "M " f(kx - 22 * k) " " f(ky + 12 * k) " H " f(kx + 22 * k), "url(#glyphG)", po, 5 * k, "")
  body = body rrect("bigMouse", mx - 14 * k, my - 23 * k, 28 * k, 46 * k, 14 * k, "url(#glyphG)", go, 5 * k)
  body = body line("bigSeam", "M " f(mx) " " f(my - 23 * k) " V " f(my - 10 * k), "#64D2FF", po, 4 * k, "")
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

# acc_frame <p|l> <rest|none|live> <keyboard %> <mouse %> <trackpad %>
# p = the 2×1 face (400×200), l = its 1×2 landscape variant (200×400). A level of -1 = that device is not shown.
acc_frame() {
  emulate -L zsh
  export LC_ALL=C
  local layout=${1:-p} state=${2:-rest} kb=${3:--1} ms=${4:--1} tp=${5:--1}
  [[ $layout == (p|l) ]] || layout=p
  [[ $state == (rest|none|live) ]] || state=rest
  [[ $kb == <-> ]] || kb=-1
  [[ $ms == <-> ]] || ms=-1
  [[ $tp == <-> ]] || tp=-1
  awk -v ly=$layout -v st=$state -v kb=$kb -v ms=$ms -v tp=$tp "$ACCESSORIES_AWK"
}
# ---- end frame ----

# ---- reading ----
# ioreg's Apple input devices (AppleDeviceManagementHIDEventService) → "<kind>\t<level>\t<bt|usb>\t<address>"
# kind: kb, ms, tp or - (not told: "Product" is often empty, the product id unknown); level -1 when not reported.
# Printed: every device with a level, and every device on a cable (so system_profiler's entry for it is dropped
# too). Built-in ones are skipped.
read -r -d '' IOREG_AWK <<'AWK'
function val(s, key,   t) { if (!match(s, "\"" key "\"[ ]*=[ ]*[0-9]+")) return -1; t = substr(s, RSTART, RLENGTH); sub(/^.*=[ ]*/, "", t); return t + 0 }
function usageKind(pg, u) {
  if (pg == 13 && u == 5) return "tp"          # digitizer: touch pad
  if (pg == 1 && (u == 6 || u == 7)) return "kb"   # generic desktop: keyboard, keypad
  if (pg == 1 && u == 2) return "ms"           # generic desktop: mouse
  return ""
}
function kindOf(   p, rest, s, k, best) {
  p = tolower(prod)
  if (p ~ /trackpad/) return "tp"
  if (p ~ /keyboard/) return "kb"
  if (p ~ /mouse/) return "ms"
  if (vid == 76) {                             # Apple product ids: Magic Trackpad, Magic Keyboard, Magic Mouse generations
    if (pid == 782 || pid == 613 || pid == 804) return "tp"
    if (pid == 615 || pid == 620 || pid == 666 || pid == 668 || pid == 671 || pid == 800 || pid == 801 || pid == 802) return "kb"
    if (pid == 781 || pid == 617 || pid == 803) return "ms"
  }
  best = ""; rest = pairs
  while (match(rest, /\{[^}]*\}/)) {
    s = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
    k = usageKind(val(s, "DeviceUsagePage"), val(s, "DeviceUsage"))
    if (k == "tp" || (k == "kb" && best != "tp") || (k == "ms" && best == "")) best = k
  }
  if (best != "") return best
  return usageKind(ppage, pusage)
}
function addr(   a) {
  a = tolower(daddr != "" ? daddr : serial)
  gsub(/[^0-9a-f]/, "", a)
  if (length(a) != 12) { a = tolower(bdaddr); gsub(/[^0-9a-f]/, "", a) }
  return (length(a) == 12) ? a : ""
}
function flush(   k, via) {
  if (!svc) return
  svc = 0
  if (builtin == "yes") return
  k = kindOf(); via = (tolower(tr) ~ /usb/) ? "usb" : "bt"
  if (pct > 100) pct = 100
  if (pct >= 0 || via == "usb") print (k != "" ? k : "-") "\t" pct "\t" via "\t" addr()
}
function strv(s) { sub(/^"/, "", s); sub(/"[ \t]*$/, "", s); return s }
/\+-o / {
  flush()
  svc = ($0 ~ /\+-o AppleDeviceManagementHIDEventService/ || $0 ~ /<class AppleDeviceManagementHIDEventService[,>]/)
  prod = ""; pct = -1; pairs = ""; ppage = -1; pusage = -1; tr = ""; builtin = ""; vid = -1; pid = -1; daddr = ""; serial = ""; bdaddr = ""
  next
}
svc && /^[ \t|]*"[^"]+"[ \t]*=/ {
  l = $0; sub(/^[ \t|]*/, "", l)
  key = l; sub(/^"/, "", key); sub(/".*$/, "", key)
  v = l; sub(/^"[^"]*"[ \t]*=[ \t]*/, "", v); sub(/[ \t\r]+$/, "", v)
  if (key == "Product") prod = strv(v)
  else if (key == "BatteryPercent" && v ~ /^[0-9]+$/) pct = v + 0
  else if (key == "DeviceUsagePairs") pairs = v
  else if (key == "PrimaryUsagePage" && v ~ /^[0-9]+$/) ppage = v + 0
  else if (key == "PrimaryUsage" && v ~ /^[0-9]+$/) pusage = v + 0
  else if (key == "Transport") tr = strv(v)
  else if (key == "Built-In") builtin = tolower(v)
  else if (key == "VendorID" && v ~ /^[0-9]+$/) vid = v + 0
  else if (key == "ProductID" && v ~ /^[0-9]+$/) pid = v + 0
  else if (key == "DeviceAddress") daddr = strv(v)
  else if (key == "SerialNumber") serial = strv(v)
  else if (key == "BD_ADDR") bdaddr = v
}
END { flush() }
AWK

# system_profiler's Bluetooth JSON → "<kind>\t<level>\t<address>" of the connected keyboards (kb), mice (ms) and
# trackpads (tp), by minor type (or by name when there is none); level -1 when not reported — it often is not for
# Apple's own devices, and the line still tells ioreg what kind the device at that address is. Headphones and the
# rest are skipped.
read -r -d '' PROFILER_AWK <<'AWK'
function unq(s) { gsub(/\\"/, "\"", s); gsub(/\\\//, "/", s); gsub(/\\\\/, "\\", s); return s }
function pct(s) { return (s ~ /^[0-9]+%?$/) ? ((s + 0 > 100) ? 100 : s + 0) : -1 }
function kind(t) {
  t = tolower(t)
  if (t ~ /trackpad/) return "tp"
  if (t ~ /keyboard/) return "kb"
  if (t ~ /mouse|pointing/) return "ms"
  return ""
}
function flush(   k, a) {
  if (nm == "") return
  k = (mt != "") ? kind(mt) : kind(nm)
  a = tolower(ad); gsub(/[^0-9a-f]/, "", a)
  if (k != "") print k "\t" bm "\t" (length(a) == 12 ? a : "")
  nm = ""
}
BEGIN { depth = 0; conn = 0 }
{
  line = $0
  t = line; gsub(/"([^"\\]|\\.)*"/, "", t)      # brackets outside strings
  o = t; c = t
  no = gsub(/[[{]/, "", o); nc = gsub(/[]}]/, "", c)
  if (!conn && line ~ /"device_connected"[ \t]*:/) { conn = 1; base = depth }
  else if (conn && depth == base + 2 && no > 0 && match(line, /^[ \t]*"([^"\\]|\\.)*"[ \t]*:/)) {
    flush()
    s = substr(line, RSTART, RLENGTH); sub(/^[ \t]*"/, "", s); sub(/"[ \t]*:$/, "", s)
    nm = unq(s); mt = ""; ad = ""; bm = -1
  }
  else if (conn && nm != "" && depth == base + 3 && match(line, /"device_[A-Za-z]+"[ \t]*:[ \t]*"([^"\\]|\\.)*"/)) {
    kv = substr(line, RSTART, RLENGTH)
    k = kv; sub(/^"/, "", k); sub(/".*$/, "", k)
    v = kv; sub(/^"[^"]*"[ \t]*:[ \t]*"/, "", v); sub(/"$/, "", v)
    if (k == "device_minorType") mt = v
    else if (k == "device_address") ad = v
    else if (k == "device_batteryLevelMain" || k == "device_batteryLevel" || k == "device_batteryPercent") bm = pct(v)
  }
  depth += no - nc
  if (conn && depth <= base) { flush(); conn = 0 }
}
END { flush() }
AWK

# take <kind> <level>: keeps the lower level of each kind — with two keyboards the one to charge first is shown.
take() {
  local lvl=$2
  [[ $lvl == <-> ]] || return 0
  (( lvl > 100 )) && lvl=100
  case $1 in
    kb) (( kb < 0 || lvl < kb )) && kb=$lvl ;;
    ms) (( ms < 0 || lvl < ms )) && ms=$lvl ;;
    tp) (( tp < 0 || lvl < tp )) && tp=$lvl ;;
  esac
  return 0
}

# levels <ioreg lines> <system_profiler lines>: sets kb, ms, tp (-1 = none). ioreg wins for a device both know
# (same address): it is fresher, and it tells a cable, which leaves the device out. ioreg often leaves "Product"
# empty; a device it cannot name takes its kind from system_profiler's minor type for the same address.
levels() {
  local line kind lvl via ad
  local -A known kindof
  kb=-1 ms=-1 tp=-1
  for line in ${(f)2}; do
    IFS=$'\t' read -r kind lvl ad <<< "$line"
    [[ -n $ad ]] && kindof[$ad]=$kind
  done
  for line in ${(f)1}; do
    IFS=$'\t' read -r kind lvl via ad <<< "$line"
    [[ -n $ad ]] && known[$ad]=1
    [[ $kind == - && -n $ad ]] && kind=${kindof[$ad]:--}
    [[ $via == usb ]] || take $kind $lvl
  done
  for line in ${(f)2}; do
    IFS=$'\t' read -r kind lvl ad <<< "$line"
    [[ -n $ad && -n ${known[$ad]} ]] && continue
    take $kind $lvl
  done
  return 0
}
# ---- end reading ----

cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"
zf_mkdir -p "$dir" 2>/dev/null || print -u2 -- "accessories: cannot create $dir"

# Sets state, kb, ms and tp: ioreg (instant) for Apple's devices, system_profiler (about a second) for the others.
# system_profiler runs in the background so the TERM trap can stop it.
sample() {
  local raw="$dir/bluetooth.json" io sp=""
  io=$(ioreg -c AppleDeviceManagementHIDEventService -r -l 2>/dev/null | awk "$IOREG_AWK" 2>/dev/null)
  system_profiler -timeout 20 SPBluetoothDataType -json > "$raw" 2>/dev/null &
  reader=$!
  wait $reader
  reader=0
  if [[ -s $raw ]]; then
    sp=$(awk "$PROFILER_AWK" "$raw" 2>/dev/null)
  else
    print -u2 -- "accessories: system_profiler gave nothing (Bluetooth off?)"
  fi
  levels "$io" "$sp"
  state=live
  (( kb < 0 && ms < 0 && tp < 0 )) && state=none
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
  [[ $code == 200 ]] || print -u2 -- "accessories: update-button answered ${code:-nothing}: ${${answer%$'\n'*}[1,300]}"
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

state=rest kb=-1 ms=-1 tp=-1
last="" seen=1 next=0
while true; do
  if (( ! seen )); then                          # off screen: no sampling, one look at the phone every 3 s
    until on_screen; do zselect -t 300; done
    seen=1
  fi
  if (( EPOCHSECONDS >= next )); then
    if ! on_screen; then seen=0; continue; fi
    sample
    next=$(( EPOCHSECONDS + 300 ))               # batteries drain slowly: every 5 minutes
  fi
  key="$state $kb $ms $tp"
  if [[ $key != $last ]]; then
    code=""
    post "$(acc_frame p $state $kb $ms $tp)" "$(acc_frame l $state $kb $ms $tp)"
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
