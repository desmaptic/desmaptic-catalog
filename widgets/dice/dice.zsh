# Dice: a tap throws the die on the button, a long press moves on to the next die of your list.
# The button's lines before this file say which: mode=roll (tap) or mode=switch (long press). The long press's
# first line is your list — dice="d6 d20" — in the order a long press steps through it, wrapping round:
#   d4 d6 d8 d10 d12 d20 d100 coin      (other words are skipped; a list of one die only nods; a list with
#                                        none of these refuses, and the phone shakes the button)
# The tap does not read the list: it throws the die the button shows. The whole throw is drawn here and posted
# frame by frame (about a second); nothing runs between taps.
# State, one line in gallery/<button>/state: the die shown, then the last throw of every kind,
#   d20 d4:4 d6:5 d8:8 d10:10 d12:12 d20:17 d100:100 coin:1          (coin: 1 a star, 2 a moon)
# A die never thrown shows its highest number (the d6 a 5, the coin its star). Anything unreadable is a d6 that
# shows 5.
#
# Try it without the phone:
#   zsh dice.zsh --face rest|demo          the button's resting face / the Gallery's sample, as SVG
#   zsh dice.zsh --face <die> <n>          any die at rest showing n, e.g. --face d12 7, --face coin 2
#   mode=roll DICE_DRY=1 zsh dice.zsh      prints every frame of a throw instead of posting it
#   DICE_KIND=<die> makes a dry run start from that die (a throw throws it, a switch leaves it);
#   DICE_RESULT=<n> forces the result of a dry throw; a dry run keeps its state in $DICE_STORAGE or a temp folder,
#   never in the live storage, and never calls the agent. E.g. every switch of a list, from a d4:
#   dice="d4 d12 coin" mode=switch DICE_DRY=1 DICE_KIND=d4 zsh dice.zsh
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime zsh/zselect zsh/stat || { print -u2 -- "dice: a zsh module is missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_mv b:zf_rm b:zf_rmdir || { print -u2 -- "dice: zsh module files is missing"; exit 1 }

# ---- the face: one frame function draws every frame, of every die ---------------------------------------------
# Every frame has the same elements in the same order, whatever the die, so a throw glides, and so does a switch
# from any die to any other: an outline and a number face of ten points each (a kind puts its corners at some of
# the ten, the rest along its edges), nine facets, the d6's seven pips, the number.
#
# awk -v mode=throw|switch|nod|rest -v kind=<die> ... prints one line per frame: "<duration> <easing> <wait> <svg>",
# wait = seconds until the next frame is posted (less than the duration in flight: the next frame takes over the
# glide mid-way and the spin never stops; equal to it on the table: every short move plays to its end).
read -r -d '' dice_awk <<'AWK'
function hexv(h,   i, n) { n = 0; h = toupper(h); for (i = 1; i <= length(h); i++) n = n * 16 + index("0123456789ABCDEF", substr(h, i, 1)) - 1; return n }
function mix(a, b, t,   i, o, x, y) {
  o = "#"
  for (i = 2; i <= 6; i += 2) { x = hexv(substr(a, i, 2)); y = hexv(substr(b, i, 2)); o = o sprintf("%02X", int(x + (y - x) * t + 0.5)) }
  return o
}
function f(x) { x = sprintf("%.1f", x); return x == "-0.0" ? "0.0" : x }
function pt(x, y) { return f(x) "," f(y) }
function norm(a) { while (a > 180) a -= 360; while (a <= -180) a += 360; return a }
function rad(d) { return d * PI / 180 }

# ---- shapes: every kind is ten points ---------------------------------------------------------------------------
# The outline (OX, OY, rounded OC units along its edges at each point) and the face that carries the number (FX,
# FY, FC) are ten points for every kind, in the same order round the die from the top. A kind places its real
# corners at some of the ten and the rest evenly along its edges, so a switch moves point to point and never turns
# a shape inside out.
function corner(i, x, y, r, at) { KX[i] = x; KY[i] = y; KR[i] = r; KI[i] = at }
# A point along a straight edge is rounded too, as far as it can be (half way to its neighbours, short of their
# own rounding): on a straight edge that draws nothing, but a switch to a round shape (the coin) stays smooth
# instead of rippling at every point.
function spread(n, X, Y, C,   i, j, a, b, m, s, k, p, q, lp, lq, CO) {
  for (i = 0; i < n; i++) {
    j = (i + 1) % n; a = KI[i]; b = KI[j]; if (b <= a) b += 10; m = b - a
    for (s = 0; s < m; s++) { k = (a + s) % 10; X[k] = KX[i] + (KX[j] - KX[i]) * s / m; Y[k] = KY[i] + (KY[j] - KY[i]) * s / m; C[k] = s ? -1 : KR[i] }
  }
  for (k = 0; k < 10; k++) {
    if (C[k] >= 0) continue
    p = (k + 9) % 10; q = (k + 1) % 10
    lp = sqrt((X[k] - X[p]) ^ 2 + (Y[k] - Y[p]) ^ 2); lq = sqrt((X[k] - X[q]) ^ 2 + (Y[k] - Y[q]) ^ 2)
    lp = C[p] >= 0 ? lp - C[p] : lp / 2; lq = C[q] >= 0 ? lq - C[q] : lq / 2
    CO[k] = lp < lq ? lp : lq
  }
  for (k = 0; k < 10; k++) if (C[k] < 0) C[k] = CO[k]
}
# a regular polygon of n corners (n = 3, 5 or 10) round (x0, y0), radius R, a corner at the top, rounded r
function regular(n, x0, y0, R, r,   i, a) {
  for (i = 0; i < n; i++) { a = rad(-90 + 360 * i / n); corner(i, x0 + R * cos(a), y0 + R * sin(a), r, n == 3 ? substr("046", i + 1, 1) + 0 : i * 10 / n) }
}
function scaled(X, Y, C, s, x0, y0, rs, TX, TY, TC,   k) { for (k = 0; k < 10; k++) { TX[k] = x0 + (X[k] - x0) * s; TY[k] = y0 + (Y[k] - y0) * s; TC[k] = C[k] * rs } }

# The ten points as a path, each corner rounded into a circular arc: always M, C, then L C nine times, Z.
function rpath(X, Y, C, sc,   k, p, n, vx, vy, r, ux, uy, wx, wy, l, ax, ay, bx, by, th, kk, d) {
  d = ""
  for (k = 0; k < 10; k++) {
    p = (k + 9) % 10; n = (k + 1) % 10
    vx = X[k] * sc; vy = Y[k] * sc; r = C[k] * sc
    ux = X[p] * sc - vx; uy = Y[p] * sc - vy; l = sqrt(ux * ux + uy * uy); if (l > 0) { ux /= l; uy /= l }
    wx = X[n] * sc - vx; wy = Y[n] * sc - vy; l = sqrt(wx * wx + wy * wy); if (l > 0) { wx /= l; wy /= l }
    ax = vx + ux * r; ay = vy + uy * r; bx = vx + wx * r; by = vy + wy * r
    th = atan2(-ux * wy + uy * wx, -ux * wx - uy * wy); if (th < 0) th = -th     # how far the edge turns here
    kk = cos(th / 2) < 1e-6 ? 0 : (th < 1e-6 ? 2 / 3 : 4 / 3 * (sin(th / 4) / cos(th / 4)) / (sin(th / 2) / cos(th / 2)))
    d = d (k == 0 ? "M" : "L") pt(ax, ay) "C" pt(ax + (vx - ax) * kk, ay + (vy - ay) * kk) " " pt(bx + (vx - bx) * kk, by + (vy - by) * kk) " " pt(bx, by)
  }
  return d "Z"
}

# A facet point: "o3" an outline point, "f4" a point of the face, "o3+o7" the middle of several.
function px(t,   p, n, s, i) { n = split(t, p, "+"); s = 0; for (i = 1; i <= n; i++) s += substr(p[i], 1, 1) == "o" ? OX[substr(p[i], 2) + 0] : FX[substr(p[i], 2) + 0]; return s / n }
function py(t,   p, n, s, i) { n = split(t, p, "+"); s = 0; for (i = 1; i <= n; i++) s += substr(p[i], 1, 1) == "o" ? OY[substr(p[i], 2) + 0] : FY[substr(p[i], 2) + 0]; return s / n }

# The nine facets round the face, each five points in the same order (inner start, three along the outline, inner
# end), in nine places round the die: a kind fills the places nearest to its facets (SPEC); a place it does not use
# holds an unseen sliver lying flat on the outline (CANON).
function facets(kind,   s, i, c, gx, gy, n, t, seen, key, spec) {
  for (s = 0; s < 9; s++) {
    spec = SPEC[kind, s]; QO[s] = spec != ""
    split(QO[s] ? spec : CANON[s], c, " ")
    for (i = 1; i <= 5; i++) { QX[s, i] = px(c[i]); QY[s, i] = py(c[i]) }
    # lit from the upper left: the light a facet catches from the direction of its middle (its distinct corners)
    gx = 0; gy = 0; n = 0; split("", seen)
    for (i = 1; i <= 5; i++) {
      if (i == 3) continue
      key = f(QX[s, i]) " " f(QY[s, i]); if (key in seen) continue
      seen[key] = 1; gx += QX[s, i]; gy += QY[s, i]; n++
    }
    gx /= n; gy /= n
    t = (-0.5 * gx - 0.866 * gy) / sqrt(gx * gx + gy * gy + 1e-9)
    QC[s] = mix(PAL[kind, "fd"], PAL[kind, "fl"], (t + 1) / 2)
    # a facet across an edge of the face (two inner corners, one outer) leans less: lighter
    if (QO[s] && c[1] != c[5] && c[2] == c[4]) QC[s] = mix(QC[s], PAL[kind, "ff"], 0.35)
  }
}

# The shape of a kind; val matters only for the coin (1 a star, 2 a moon).
function shape(kind, val,   i, a, s, r1, r2, c1x, c1y, c2x, c2y, dd, aa, hh, mx, my, ux, uy, tux, tuy, tlx, tly, psi, au, al, ins, ix, iy, la, lb, per) {
  NY = 5; TS = 0.9
  if (kind == "d6") {
    corner(0, S, -S, RS, 1); corner(1, S, S, RS, 4); corner(2, -S, S, RS, 6); corner(3, -S, -S, RS, 9); spread(4, OX, OY, OC)
    scaled(OX, OY, OC, 0.62, 0, 0, 0.62, FX, FY, FC)
  } else if (kind == "d4") {
    regular(3, 0, 16, 78, 13); spread(3, OX, OY, OC)        # centred lower than the others: a triangle looks high
    regular(3, 0, 16, 50, 3); spread(3, FX, FY, FC); NY = 22
  } else if (kind == "d8") {
    corner(0, 0, -82, 7, 0); corner(1, 66, 8, 8, 3); corner(2, 0, 80, 7, 5); corner(3, -66, 8, 8, 7); spread(4, OX, OY, OC)
    # the face: the upper triangle, set in by ins round its centre of the inscribed circle
    la = sqrt(66 * 66 + 90 * 90); lb = 132; ins = 6
    ix = 0; iy = (la * 8 + la * 8 + lb * -82) / (2 * la + lb)
    s = 1 - ins / (2 * (0.5 * 132 * 90) / (2 * la + lb))
    corner(0, ix + (0 - ix) * s, iy + (-82 - iy) * s, 3, 0); corner(1, ix + (66 - ix) * s, iy + (8 - iy) * s, 3, 3); corner(2, ix + (-66 - ix) * s, iy + (8 - iy) * s, 3, 7)
    spread(3, FX, FY, FC); NY = (FY[0] + FY[3] + FY[7]) / 3 + 6
  } else if (kind == "d10" || kind == "d100") {
    corner(0, 0, -84, 7, 0); corner(1, 62, -16, 7, 2); corner(2, 0, 84, 7, 5); corner(3, -62, -16, 7, 8); spread(4, OX, OY, OC)
    corner(0, 0, -74, 3, 0); corner(1, 42, 6, 3, 3); corner(2, 0, 50, 3, 5); corner(3, -42, 6, 3, 7); spread(4, FX, FY, FC); NY = 4
  } else if (kind == "d12") {
    regular(10, 0, 0, 80, 6); spread(10, OX, OY, OC)
    regular(5, 0, 0, 46, 3); spread(5, FX, FY, FC); NY = 4
  } else if (kind == "d20") {
    for (i = 0; i < 6; i++) { a = rad(-90 + 60 * i); corner(i, R * cos(a), R * sin(a), RH, substr("014569", i + 1, 1) + 0) }
    spread(6, OX, OY, OC)
    regular(3, 0, 0, RF, 0); spread(3, FX, FY, FC); NY = 0.1 * RF
  } else {                                      # the coin: a disc, its face, and a star or a moon on it
    regular(10, 0, 0, 78, 78 * sin(rad(18))); spread(10, OX, OY, OC); TS = 0.84
    if (val == 2) {
      # a crescent: the disc (c1, r1) less the disc (c2, r2); tips where the two circles cross
      c1x = -5; c1y = 3; r1 = 34; c2x = 9; c2y = -8; r2 = 28
      dd = sqrt((c2x - c1x) ^ 2 + (c2y - c1y) ^ 2); aa = (r1 * r1 - r2 * r2 + dd * dd) / (2 * dd); hh = sqrt(r1 * r1 - aa * aa)
      ux = (c2x - c1x) / dd; uy = (c2y - c1y) / dd; mx = c1x + aa * ux; my = c1y + aa * uy
      tux = mx + hh * uy; tuy = my - hh * ux; tlx = mx - hh * uy; tly = my + hh * ux    # the upper tip, the lower one
      if (tuy > tly) { a = tux; tux = tlx; tlx = a; a = tuy; tuy = tly; tly = a }
      psi = atan2(c1y - c2y, c1x - c2x)                                                 # from c2 towards c1
      au = atan2(tuy - c2y, tux - c2x); per = psi - au; while (per > PI) per -= 2 * PI; while (per < -PI) per += 2 * PI
      corner(0, tux, tuy, 0, 0)
      for (i = 1; i <= 3; i++) corner(i, c2x + r2 * cos(au + per * i / 2), c2y + r2 * sin(au + per * i / 2), 0, i)
      corner(4, tlx, tly, 0, 4)
      al = atan2(tly - c1y, tlx - c1x); per = psi - al; while (per > PI) per -= 2 * PI; while (per < -PI) per += 2 * PI
      for (i = 1; i <= 5; i++) corner(4 + i, c1x + r1 * cos(al + per * i / 3), c1y + r1 * sin(al + per * i / 3), 0, 4 + i)
      spread(10, FX, FY, FC)
      for (i = 1; i < 10; i++) if (i != 4) FC[i] = 0.5 * sqrt((FX[i] - FX[i - 1]) ^ 2 + (FY[i] - FY[i - 1]) ^ 2)
    } else {
      for (i = 0; i < 10; i++) { a = rad(-90 + 36 * i); corner(i, (i % 2 ? 14 : 35) * cos(a), (i % 2 ? 14 : 35) * sin(a) + 2, i % 2 ? 1 : 2.5, i) }
      spread(10, FX, FY, FC)
    }
  }
  facets(kind)
}

# One frame from the F* globals: Fkind, Fval, Fblank (0 = the face shows Fval; 1 = in flight: pips dimmed alike,
# number and coin symbol hidden; 2 = nothing on the face), Fh (height over the table, 0..1), Fang (degrees),
# Fsx/Fsy (squash), Fwave/Fwaveo (the ring the landing sends over the table: 0 at the die's edge .. 1 at the
# button's, and its opacity), Fglow (opacity of the light behind the die).
function frame(   sc, k, out, on, pr, po, pc, d6, nat, fs, glowc, ringc, shx, shy, sho, die_t, sh_t, numo, numc, lbl, i, pts, fo) {
  d6 = Fkind == "d6"
  nat = Fkind == "d20" && Fval == 20 && Fblank == 0     # a natural 20 lights up gold
  sc = 1 + 0.14 * Fh                            # higher = closer to the camera above the table
  shape(Fkind, Fval)
  scaled(OX, OY, OC, TS, 0, 0, Fkind == "coin" ? TS : TS * 0.944, TX, TY, TC)
  die_t = "translate(" f(CX) " " f(CY - 3 * Fh) ") rotate(" f(norm(Fang)) " 0 0) scale(" sprintf("%.3f %.3f", sc * Fsx, sc * Fsy) ")"
  shx = CX + 4 + 14 * Fh; shy = CY + 7 + 16 * Fh; sho = 0.42 - 0.24 * (Fh > 0 ? Fh : 0)
  sh_t = "translate(" f(shx) " " f(shy) ") rotate(" f(norm(Fang)) " 0 0) scale(" sprintf("%.3f %.3f", Fsx * (1 - 0.04 * Fh), Fsy * (1 - 0.04 * Fh)) ")"
  glowc = nat ? "#FFD60A" : "#FFF6E0"; ringc = nat ? "#FFD60A" : "#FFFFFF"

  out = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 200 200'><defs>"
  out = out "<linearGradient id='gb' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='" PAL[Fkind, "b1"] "'/><stop offset='1' stop-color='" PAL[Fkind, "b2"] "'/></linearGradient>"
  out = out "<linearGradient id='gf' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='" PAL[Fkind, "t1"] "'/><stop offset='1' stop-color='" PAL[Fkind, "t2"] "'/></linearGradient>"
  out = out "<radialGradient id='gg' cx='0.5' cy='0.5' r='0.5'><stop offset='0' stop-color='" glowc "' stop-opacity='0.85'/><stop offset='0.55' stop-color='" glowc "' stop-opacity='0.3'/><stop offset='1' stop-color='" glowc "' stop-opacity='0'/></radialGradient></defs>"
  out = out "<circle id='glow' cx='" f(CX) "' cy='" f(CY) "' r='98' fill='url(#gg)' opacity='" sprintf("%.2f", Fglow) "'/>"
  out = out "<path id='shadow' d='" rpath(OX, OY, OC, 1) "' fill='#000000' opacity='" sprintf("%.2f", sho) "' transform='" sh_t "'/>"
  out = out "<circle id='ring' cx='" f(CX) "' cy='" f(CY) "' r='" f(78 + 26 * Fwave) "' fill='none' stroke='" ringc "' stroke-width='" f(8 - 7 * Fwave) "' opacity='" sprintf("%.2f", Fwaveo) "'/>"
  out = out "<g id='die' transform='" die_t "'>"
  out = out "<path id='body' d='" rpath(OX, OY, OC, 1) "' fill='url(#gb)'/>"
  out = out "<path id='top' d='" rpath(TX, TY, TC, 1) "' fill='url(#gf)' stroke='" PAL[Fkind, "ts"] "' stroke-opacity='" PAL[Fkind, "tso"] "' stroke-width='2' opacity='" PAL[Fkind, "to"] "'/>"
  for (k = 0; k < 9; k++) {
    pts = ""; for (i = 1; i <= 5; i++) pts = pts (i > 1 ? " " : "") pt(QX[k, i], QY[k, i])
    out = out "<polygon id='f" k "' points='" pts "' fill='" QC[k] "' stroke='" PAL[Fkind, "fs"] "' stroke-opacity='0.55' stroke-width='1.5' stroke-linejoin='round' opacity='" (Fblank == 2 ? 0 : QO[k]) "'/>"
  }
  fo = PAL[Fkind, "fo"] * Ffront; if (Fkind == "coin" && Fblank) fo = 0
  out = out "<path id='front' d='" rpath(FX, FY, FC, 1) "' fill='" PAL[Fkind, "ff"] "' stroke='" PAL[Fkind, "ffs"] "' stroke-opacity='0.7' stroke-width='1.5' stroke-linejoin='round' opacity='" fo "'/>"
  # pips: 0 top left, 1 top right, 2 middle left, 3 centre, 4 middle right, 5 bottom left, 6 bottom right
  for (k = 0; k < 7; k++) {
    on = index(PIPS[Fval], k) > 0
    pr = 11.5; pc = "#26262E"; po = Fblank == 1 ? 0.18 : (Fblank == 2 ? 0 : on)
    if (d6 && Fblank == 0 && Fval == 1 && k == 3) { pr = 16; pc = "#D7263D" }   # the single pip: big and red
    if (!d6) { pr = 0; po = 0 }
    out = out "<circle id='p" k "' cx='" f(d6 ? PX[k] : 0) "' cy='" f(d6 ? PY[k] : 0) "' r='" f(pr) "' fill='" pc "' opacity='" sprintf("%.2f", po) "'/>"
  }
  lbl = Fkind == "d100" && Fval < 10 ? sprintf("%02d", Fval) : Fval
  fs = length(lbl) >= 3 ? 30 : (length(lbl) == 2 ? 38 : (Fkind == "d4" ? 44 : 46))
  numo = (d6 || Fkind == "coin" || Fblank) ? 0 : 1; numc = nat ? "#FFD60A" : "#FFFFFF"
  out = out "<text id='num' x='0' y='" f(NY) "' font-size='" fs "' font-weight='bold' text-anchor='middle' dominant-baseline='middle' fill='" numc "' opacity='" numo "'>" lbl "</text>"
  return out "</g></svg>"
}

function put(kind, val, blank, h, ang, sx, sy, wave, waveo, glow) {
  Ffront = 1; Fkind = kind; Fval = val; Fblank = blank; Fh = h; Fang = ang; Fsx = sx; Fsy = sy; Fwave = wave; Fwaveo = waveo; Fglow = glow
}
# a kind whose number sits on a plain face (not the d6's pips, not the coin's symbol): only between two of them
# does the face stay in sight while one die changes into the other
function plainface(kind) { return PAL[kind, "fo"] + 0 > 0 && kind != "coin" }
# the light behind a die at rest: only a natural 20 keeps one, gold
function aura(kind, val) { return kind == "d20" && val == 20 ? 0.65 : 0 }
function emit(dur, easing, wait) { printf "%.3f %s %.3f %s\n", dur, easing, wait, frame() }

# a kind's colours: body (b1 → b2), its top (t1 → t2, stroke ts at tso, shown at to), facets from dark fd to
# light fl with stroke fs, the face ff with stroke ffs, shown at fo
function pal(kind, s,   n, v, i) { n = split(s, v, " "); for (i = 1; i < n; i += 2) PAL[kind, v[i]] = v[i + 1] }

BEGIN {
  PI = atan2(0, -1)
  CX = 100; CY = 97
  S = 58; RS = 17                               # d6: half its side, corner radius
  R = 78; RH = 5; RF = 0.68 * R                 # d20: outline radius, corner radius, the face turned to us
  d = 0.54 * S
  PX[0] = -d; PY[0] = -d; PX[1] = d; PY[1] = -d; PX[2] = -d; PY[2] = 0; PX[3] = 0; PY[3] = 0
  PX[4] = d; PY[4] = 0; PX[5] = -d; PY[5] = d; PX[6] = d; PY[6] = d
  PIPS[1] = "3"; PIPS[2] = "15"; PIPS[3] = "135"; PIPS[4] = "0156"; PIPS[5] = "01356"; PIPS[6] = "012456"
  # the facets, place by place: the d20's as they were; the others' in the places nearest to theirs
  split("f0 o9 o9+o0 o0 f0|f0 o0 o0+o1 o1 f0|f0 o1 o1 o1 f4|f4 o1 o2+o3 o4 f4|f4 o4 o4+o5 o5 f4|f4 o5 o5 o5 f6|f6 o5 o5+o6 o6 f6|f6 o6 o7+o8 o9 f6|f6 o9 o9 o9 f0", tmp, "|")
  for (k = 0; k < 9; k++) SPEC["d20", k] = tmp[k + 1]
  split("o9 o9 o9+o0 o0 o0|o0 o0 o0+o1 o1 o1|o1 o1 o1 o1 o1|o1 o1 o2+o3 o4 o4|o4 o4 o4+o5 o5 o5|o5 o5 o5 o5 o5|o5 o5 o5+o6 o6 o6|o6 o6 o7+o8 o9 o9|o9 o9 o9 o9 o9", tmp, "|")
  for (k = 0; k < 9; k++) CANON[k] = tmp[k + 1]
  SPEC["d12", 0] = "f8 o8 o9 o0 f0"; SPEC["d12", 1] = "f0 o0 o1 o2 f2"; SPEC["d12", 3] = "f2 o2 o3 o4 f4"; SPEC["d12", 5] = "f4 o4 o5 o6 f6"; SPEC["d12", 7] = "f6 o6 o7 o8 f8"
  SPEC["d10", 0] = "f7 o8 o9 o0 f0"; SPEC["d10", 1] = "f0 o0 o1 o2 f3"; SPEC["d10", 4] = "f3 o2 o3+o4 o5 f5"; SPEC["d10", 6] = "f5 o5 o6+o7 o8 f7"
  for (k = 0; k < 9; k++) SPEC["d100", k] = SPEC["d10", k]
  SPEC["d4", 3] = "f0 o0 o2 o4 f4"; SPEC["d4", 5] = "f4 o4 o5 o6 f6"; SPEC["d4", 7] = "f6 o6 o8 o0 f0"
  SPEC["d8", 4] = "o3+o7 o3 o4 o5 o3+o7"; SPEC["d8", 6] = "o3+o7 o5 o6 o7 o3+o7"

  pal("d4",   "b1 #6BE38A b2 #1C8C3C t1 #6BE38A t2 #1C8C3C ts #FFFFFF tso 0 to 0 fd #145F2A fl #8CEBA3 fs #D2F7DB ff #2FBF57 ffs #E0FBE7 fo 1")
  pal("d6",   "b1 #ECE5D8 b2 #B4A893 t1 #FFFFFF t2 #EAE2D3 ts #FFFFFF tso 0 to 1 fd #8C826F fl #F4EFE6 fs #FFFFFF ff #F4EFE6 ffs #FFFFFF fo 0")
  pal("d8",   "b1 #66B2FF b2 #0B4DB0 t1 #66B2FF t2 #0B4DB0 ts #FFFFFF tso 0 to 0 fd #0A3A85 fl #8CC6FF fs #D3E8FF ff #1F7FEA ffs #E3F0FF fo 1")
  pal("d10",  "b1 #FFBC5C b2 #C45A00 t1 #FFBC5C t2 #C45A00 ts #FFFFFF tso 0 to 0 fd #8C3F00 fl #FFCB7A fs #FFE6C2 ff #E57E0A ffs #FFF0D9 fo 1")
  pal("d12",  "b1 #FF7B70 b2 #A81A12 t1 #FF7B70 t2 #A81A12 ts #FFFFFF tso 0 to 0 fd #74100A fl #FF968C fs #FFD6D2 ff #E23A2E ffs #FFE3E0 fo 1")
  pal("d20",  "b1 #8C72F2 b2 #4127AE t1 #FFFFFF t2 #6A4BDB ts #FFFFFF tso 0 to 0 fd #2E1F86 fl #A792FA fs #C8BBFF ff #7A5DF0 ffs #D6CCFF fo 1")
  pal("d100", "b1 #5CD6E6 b2 #0A6E7E t1 #5CD6E6 t2 #0A6E7E ts #FFFFFF tso 0 to 0 fd #064F5A fl #8AE6F0 fs #CFF5FA ff #139DB0 ffs #E0FAFD fo 1")
  pal("coin", "b1 #F7D774 b2 #A8740A t1 #FFE68C t2 #D9A21E ts #8A5E05 tso 0.5 to 1 fd #A8740A fl #F7D774 fs #FFF2B8 ff #C48E14 ffs #FFF4C2 fo 1")

  if (mode == "rest") { put(kind, val, 0, 0, 0, 1, 1, 0, 0, aura(kind, val)); emit(0, "easeInOut", 0); exit }
  if (mode == "nod") {
    # one die in the list: it only dips and comes back
    put(kind, val, 0, -0.06, 0, 0.92, 0.92, 0, 0, aura(kind, val) * 0.7); emit(0.12, "easeInOut", 0.12)
    put(kind, val, 0, 0, 0, 1, 1, 0, 0, aura(kind, val)); emit(0.2, "easeInOut", 0)
    exit
  }
  if (mode == "switch") {
    # The old die ducks and turns away while its face clears (number, pips, facets); bare, it changes into the
    # new one — outline, face and colour glide point to point — and the new one's facets and number come up on
    # the finished shape. Facets never move while they are seen: kinds cut their facets differently, and a facet
    # gliding between two cuts would stick out of the die. Unless both dice have a plain number face, the face
    # goes with the facets and comes back with them (a triangle does not turn into the d6's pips or a moon).
    both = plainface(okind) && plainface(kind)
    put(okind, oval, 2, -0.1, -24, 0.84, 0.84, 0, 0, 0); Ffront = both; emit(0.16, "easeInOut", 0.16)
    put(kind, val, 2, -0.03, 0, 0.97, 0.97, 0, 0, 0); Ffront = both; emit(0.24, "easeInOut", 0.24)
    put(kind, val, 0, 0, 0, 1, 1, 0, 0, aura(kind, val)); emit(0.16, "easeInOut", 0)
    exit
  }
  # mode == "throw": wind-up, six frames of flight, impact, bounce, a second touch, rest
  coin = kind == "coin"
  put(kind, prev, 1, -0.06, dir * -10, 1.05, 0.93, 0, 0, 0); emit(0.12, "easeInOut", 0.11)
  W[1] = 1.0; W[2] = 0.97; W[3] = 0.92; W[4] = 0.85; W[5] = 0.76; W[6] = 0.64; sw = 0
  for (k = 1; k <= 6; k++) sw += W[k]
  a = dir * -10; turn = coin ? 30 + tilt : 724 + tilt     # a die turns twice and a bit; a coin flips instead
  for (k = 1; k <= 6; k++) {
    a += dir * turn * W[k] / sw                 # under 180 degrees a frame, or the phone turns it back the short way
    u = k / 7; h = (0.85 + lift / 100) * 4 * u * (1 - u)
    # a die keeps the last number (hidden) in flight: text does not glide, the new one would flash; the coin's
    # symbol is a shape, hidden in flight, so it takes the new one at once, unseen
    put(kind, coin ? val : prev, 1, h, a, 1, coin ? (k % 2 ? 0.12 : 1) : 1, 0, 0, 0); emit(0.1, "linear", 0.092)
  }
  nat = kind == "d20" && val == 20              # the result shows from the impact on, never before it
  put(kind, val, 0, 0, dir * tilt, 1.1, 0.88, 0.15, 0.5, nat ? 0.95 : 0.3); emit(0.08, "easeInOut", 0.08)
  put(kind, val, 0, 0.14, dir * tilt * 0.35, 0.97, 1.04, 1, 0, nat ? 0.8 : 0); emit(0.15, "easeInOut", 0.15)
  put(kind, val, 0, 0, 0, 1.035, 0.965, 1, 0, aura(kind, val)); emit(0.1, "easeInOut", 0.1)
  put(kind, val, 0, 0, 0, 1, 1, 0, 0, aura(kind, val)); emit(0.16, "easeInOut", 0)
}
AWK

kinds=(d4 d6 d8 d10 d12 d20 d100 coin)
typeset -A sides=(d4 4 d6 6 d8 8 d10 10 d12 12 d20 20 d100 100 coin 2)

# ---- the faces item.json ships: zsh dice.zsh --face rest|demo ------------------------------------------------
if (( $# )); then
  case "$1 ${2:-} ${3:-}" in
    "--face rest ") face=( -v kind=d6 -v val=5 ) ;;
    "--face demo ") face=( -v kind=d20 -v val=17 ) ;;
    "--face "(d4|d6|d8|d10|d12|d20|d100|coin)" "<1-100>) (( $3 <= sides[$2] )) && face=( -v kind=$2 -v val=$(( $3 )) ) ;|
    *) (( $#face )) || { print -u2 -- "usage: zsh dice.zsh --face rest|demo|<die> <n>   (die: $kinds)"; exit 2 } ;;
  esac
  awk -v mode=rest $face "$dice_awk" | { IFS=' ' read -r _ _ _ svg; print -r -- "$svg" }
  exit 0
fi

# ---- the button --------------------------------------------------------------------------------------------
[[ ${mode:-} == (roll|switch) ]] || { print -u2 -- "dice: mode must be roll or switch"; exit 2 }
cell="{{CELL_ID}}"
dry=0
[[ -n ${DICE_DRY:-} ]] && dry=1
if (( dry )); then
  dir="${DICE_STORAGE:-${TMPDIR:-/tmp}/dice-dry-$UID}/gallery/$cell"     # never the live storage
else
  [[ -n ${DESMAPTIC_TOKEN:-} ]] || { print -u2 -- "dice: not started by Desmaptic Agent (no DESMAPTIC_TOKEN); try DICE_DRY=1"; exit 1 }
  dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"
fi
state_file=$dir/state
lock=$dir/busy

# One throw at a time: a tap or a long press while the die is still moving is ignored, so two animations never
# mix. A lock older than 20 s was left by a script that was stopped: it is taken over.
zf_mkdir -p -- $dir 2>/dev/null
if ! zf_mkdir -- $lock 2>/dev/null; then
  typeset -a mtime
  zstat -A mtime +mtime -- $lock 2>/dev/null && (( EPOCHSECONDS - mtime[1] < 20 )) && exit 0
  zf_rmdir -- $lock 2>/dev/null
  zf_mkdir -- $lock 2>/dev/null || { print -u2 -- "dice: cannot write in $dir"; exit 1 }
fi
trap 'zf_rmdir -- $lock 2>/dev/null' EXIT
trap 'exit 0' TERM INT

# The state, read field by field and checked against the kinds (never sourced, never used as a subscript as it is).
kind=d6
typeset -A last=(d4 4 d6 5 d8 8 d10 10 d12 12 d20 20 d100 100 coin 1)
line=""
{ IFS= read -r line < $state_file } 2>/dev/null
fields=( ${=line} )
[[ ${fields[1]:-} == (d4|d6|d8|d10|d12|d20|d100|coin) ]] && kind=$fields[1]
for word in $fields[2,-1]; do
  name=${word%%:*} n=${word#*:}
  [[ $name == (d4|d6|d8|d10|d12|d20|d100|coin) && $n == <1-100> ]] && (( n <= sides[$name] )) && last[$name]=$(( n ))
done
(( dry )) && [[ ${DICE_KIND:-} == (d4|d6|d8|d10|d12|d20|d100|coin) ]] && kind=$DICE_KIND

# Replaces the state file in one step, so a reader never sees half a line.
write_state() {
  local k out=$kind
  for k in $kinds; do out+=" $k:$last[$k]"; done
  { print -r -- "$out" > "$state_file.$$" } 2>/dev/null &&
    zf_mv -f -- "$state_file.$$" $state_file 2>/dev/null ||
    { zf_rm -f -- "$state_file.$$" 2>/dev/null; print -u2 -- "dice: cannot write in $dir"; return 1 }
}

# post <svg> <duration> <easing>: one frame to the button. The SVG has single-quoted attributes and only digits as
# text, so it goes into the JSON as it is. The token goes from the environment into the request by curl itself.
post() {
  local code
  code=$(curl -q -s -m 3 -o /dev/null -w '%{http_code}' \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' \
    -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:9848/api/update-button \
    <<< "{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$1\",\"duration\":$2,\"easing\":\"$3\"}}")
  [[ $code == 200 ]] && return 0
  print -u2 -- "dice: the agent answered ${code:-nothing}"
  return 1
}

# play <frames>: posts each line of the frame function on time. A frame's wait is counted from the moment it was
# posted, so a slow post shifts the rest of the throw instead of cutting a glide short. DICE_DRY prints the lines.
play() {
  local line dur easing gap svg
  typeset -F next=0 sent
  integer cs
  for line in "${(@f)1}"; do
    dur=${line%% *}; line=${line#* }; easing=${line%% *}; line=${line#* }; gap=${line%% *}; svg=${line#* }
    [[ $dur == <->.<-> && $gap == <->.<-> && $svg == '<svg '* ]] || { print -u2 -- "dice: a frame did not come out"; return 1 }
    if (( dry )); then print -r -- "$dur $easing $gap $svg"; continue; fi
    # zselect waits whole hundredths of a second; the last few milliseconds are counted out here, because in
    # flight a frame has only 8 ms to spare before the glide it takes over would stop
    (( cs = (next - EPOCHREALTIME) * 100 ))
    (( cs > 0 )) && zselect -t $cs
    while (( EPOCHREALTIME < next )); do :; done
    sent=$EPOCHREALTIME
    post "$svg" $dur $easing || return 1
    (( next = sent + gap ))
  done
}

# REPLY = a fair number from 1 to $1, and style = 32 more random bits for the throw's look. The kernel's random
# bytes, the uneven top of their range thrown away, so a d20 shows 20 exactly as often as 1 (and a d100 100, a coin
# either side).
draw() {
  local -a words
  integer limit=$(( 4294967296 - 4294967296 % $1 )) tries
  for (( tries = 0; tries < 8; tries++ )); do
    words=( $(od -An -N8 -tu4 /dev/urandom 2>/dev/null) )
    [[ $words[1] == <-> && $words[2] == <-> ]] || break
    (( words[1] < limit )) || continue
    REPLY=$(( words[1] % $1 + 1 )) style=$words[2]
    return 0
  done
  print -u2 -- "dice: no random numbers from the system"
  return 1
}

if [[ $mode == switch ]]; then
  # The list: the dice it names, in its order, each once; with no list line at all, the d6 and the d20.
  list=()
  for word in ${=${${dice-d6 d20}//,/ }}; do
    word=${(L)word}
    [[ $word == (d4|d6|d8|d10|d12|d20|d100|coin) ]] && (( ! ${list[(Ie)$word]} )) && list+=($word)
  done
  (( $#list )) || { print -u2 -- "dice: no die I know in the list; use $kinds"; exit 1 }
  # the die after the one shown; the first of the list when the one shown is not in it
  integer at=${list[(Ie)$kind]}
  next=${list[at % $#list + 1]}
  if [[ $next == $kind ]]; then
    frames=$(awk -v mode=nod -v kind=$kind -v val=$last[$kind] "$dice_awk")
  else
    okind=$kind kind=$next
    write_state || exit 1
    frames=$(awk -v mode=switch -v okind=$okind -v oval=$last[$okind] -v kind=$kind -v val=$last[$kind] "$dice_awk")
  fi
else
  draw $sides[$kind] || exit 1
  result=$REPLY
  (( dry )) && [[ ${DICE_RESULT:-} == <1-100> ]] && (( DICE_RESULT <= sides[$kind] )) && result=$(( DICE_RESULT ))
  prev=$last[$kind] last[$kind]=$result
  write_state || exit 1
  # the look of this throw: spin direction, how far the die leans when it lands, how high it flies
  frames=$(awk -v mode=throw -v kind=$kind -v prev=$prev -v val=$result -v dir=$(( style % 2 ? 1 : -1 )) \
    -v tilt=$(( 4 + style / 2 % 7 )) -v lift=$(( style / 16 % 16 )) "$dice_awk")
fi
play "$frames" || exit 1
exit 0
