#!/bin/zsh
# Calendar: the meeting in progress or the next one today as a neon card, the one after it below; tap joins
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime
zmodload -F zsh/files b:zf_mkdir b:zf_mv
zmodload zsh/zselect

reader=0
trap '(( reader > 0 )) && kill $reader 2>/dev/null; exit 0' TERM INT

# One frame of the face. Every state draws the same elements in the same order, so the phone glides between them.
#   $1 state: rest (no answer yet) | calm (no meeting left today) | denied (no calendar access)
#             next (starts later) | soon (starts in 5 min or less) | now (in progress)
#   $2 now, epoch   $3 day of the month
#   $4 start  $5 end  $6 calendar colour #RRGGBB  $7 title  $8 time range        — the event on the card
#   $9 calendar colour  $10 title  $11 start time                                  — the event after it
calendar_frame() {
  emulate -L zsh
  export LC_ALL=C
  CF_ST=${1:-rest} CF_NOW=${2:-0} CF_DAY=${3:-} CF_AS=${4:-0} CF_AE=${5:-0} CF_AC=${6:-} CF_AT=${7:-} CF_TR=${8:-} \
  CF_BC=${9:-} CF_BT=${10:-} CF_BTM=${11:-} awk '
    function hex(h,   i, n) { n = 0; h = toupper(h); for (i = 1; i <= length(h); i++) n = n * 16 + index("0123456789ABCDEF", substr(h, i, 1)) - 1; return n }
    function mix(a, b, t,   i, o, x, y) {
      o = "#"
      for (i = 2; i <= 6; i += 2) { x = hex(substr(a, i, 2)); y = hex(substr(b, i, 2)); o = o sprintf("%02X", int(x + (y - x) * t + 0.5)) }
      return o
    }
    function spectrum(t) {                     # the family gradient: #FF375F → #BF5AF2 (.35) → #5E5CE6 (.7) → #64D2FF
      if (t <= 0)   return "#FF375F"
      if (t < 0.35) return mix("#FF375F", "#BF5AF2", t / 0.35)
      if (t < 0.7)  return mix("#BF5AF2", "#5E5CE6", (t - 0.35) / 0.35)
      if (t < 1)    return mix("#5E5CE6", "#64D2FF", (t - 0.7) / 0.3)
      return "#64D2FF"
    }
    function colour(c, fallback) { return (c ~ /^#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$/) ? toupper(c) : fallback }
    function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); return s }

    # Text is measured in em of the semibold system font, one UTF-8 character at a time (the locale is C,
    # so awk sees bytes): Latin by letter shape, other alphabets 0.6, CJK 0.96, emoji 1.25.
    function em(c, b, n) {
      if (n == 4) return 1.25
      if (n == 3) return (b == 226) ? 0.7 : 0.96
      if (n == 2) return 0.6
      if (c ~ /[0-9]/) return 0.62
      if (c == " ") return 0.25
      if (c ~ /[ijl.,:;!|\047]/) return 0.28
      if (c ~ /[frtI()\/"-]/) return 0.38
      if (c ~ /[mwMW@%]/) return 0.86
      if (c ~ /[A-Z&#?]/) return 0.68
      return 0.56
    }
    function chars(s,   i, b, n, k) {      # s → CH[1..k], CW[1..k] (em)
      k = 0; i = 1
      while (i <= length(s)) {
        b = ord[substr(s, i, 1)]
        n = (b >= 240) ? 4 : (b >= 224) ? 3 : (b >= 192) ? 2 : 1
        k++; CH[k] = substr(s, i, n); CW[k] = em(CH[k], b, n); i += n
      }
      return k
    }
    function join(a, b,   i, r) { r = ""; for (i = a; i <= b; i++) r = r CH[i]; return r }
    function fit(a, n, size, room,   i, w, r) {   # characters a..n on one line; cut with … when they do not fit
      while (a <= n && CH[a] == " ") a++
      w = 0; for (i = a; i <= n; i++) w += CW[i] * size
      if (w <= room) return join(a, n)
      w = 0.9 * size
      for (i = a; i <= n; i++) { if (w + CW[i] * size > room) break; w += CW[i] * size }
      r = join(a, i - 1); sub(/ +$/, "", r)
      return r "\342\200\246"
    }
    function wrap(s, size, room,   n, i, w, space) {   # s → LINE1, LINE2: words kept whole, the second line cut with …
      n = chars(s); w = 0; space = 0
      for (i = 1; i <= n; i++) { if (w + CW[i] * size > room) break; w += CW[i] * size; if (CH[i] == " ") space = i }
      if (i > n) { LINE1 = s; LINE2 = ""; return }
      if (space > 1) { LINE1 = join(1, space - 1); LINE2 = fit(space + 1, n, size, room) }
      else           { LINE1 = join(1, i - 1);     LINE2 = fit(i, n, size, room) }
      sub(/ +$/, "", LINE1)
    }
    function textw(s, size,   n, i, w) { n = chars(s); w = 0; for (i = 1; i <= n; i++) w += CW[i] * size; return w }
    function show(s) { return (s == "") ? "\342\200\224" : esc(s) }   # never an empty <text>
    function f2(x) { return sprintf("%.2f", x) }

    BEGIN {
      for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i
      st = ENVIRON["CF_ST"]
      if (st !~ /^(rest|calm|denied|next|soon|now)$/) st = "rest"
      now = ENVIRON["CF_NOW"] + 0; as = ENVIRON["CF_AS"] + 0; ae = ENVIRON["CF_AE"] + 0
      day = ENVIRON["CF_DAY"]; if (day !~ /^[0-9]+$/) day = ""
      ac = colour(ENVIRON["CF_AC"], "#BF5AF2"); bc = colour(ENVIRON["CF_BC"], "#BF5AF2")
      live = (st == "next" || st == "soon" || st == "now")
      hot = (st == "soon")
      running = (st == "now")
      then = live && ENVIRON["CF_BTM"] != ""

      # the card: title in two lines, time range, a countdown in min / h, the elapsed-time bar
      TT = live ? ENVIRON["CF_AT"] : ""                       # a title that fits one line is set larger, centred in the two-line slot
      TF = 19; T1 = 30; wrap(TT, TF, 155); t1 = LINE1; t2 = LINE2
      if (textw(TT, 22) <= 155) { TF = 22; T1 = 41 } else if (t2 == "") T1 = 41
      tr = live ? ENVIRON["CF_TR"] : ""
      secs = running ? ae - now : as - now
      m = int((secs + 59) / 60); if (m < 1) m = 1
      v1 = m; u1 = "min"; v2 = ""; u2 = "min"; two = 0
      if (m >= 600)     { v1 = int((m + 30) / 60); u1 = "h" }
      else if (m >= 60) { v1 = int(m / 60); u1 = "h"; if (m % 60) { v2 = m % 60; two = 1 } }
      if (!live) { v1 = ""; u1 = "min" }
      VF = 30; UF = 16
      x1 = 31; x2 = x1 + textw(v1, VF) + 4; x3 = x2 + textw(u1, UF) + 9; x4 = x3 + textw(v2, VF) + 4

      f = 0
      if (running && ae > as) f = (now - as) / (ae - as)
      if (f < 0) f = 0; if (f > 1) f = 1
      B0 = 31; B1 = 183; BY = 124; L = B1 - B0
      bx = B0 + L * f
      gc = spectrum((B1 - bx) / L)             # the bar runs cyan → pink: the colour under the bead
      s1 = "#FF375F"; s2 = "#BF5AF2"; s3 = "#5E5CE6"; s4 = "#64D2FF"
      if (hot) { gc = "#FF375F"; s2 = "#FF4F7B"; s3 = "#FF5C80"; s4 = "#FF7A96" }   # attention: the whole bar runs hot

      # the event after it: time, then its title on one line
      bt = then ? ENVIRON["CF_BT"] : ""; n = chars(bt); bt = fit(1, n, 16, 155)
      btm = then ? ENVIRON["CF_BTM"] : ""

      # state:   bloom centre colour, opacity, mid colour, opacity, radius, centre y   card fill, edge colour, edge opacity   value colour, unit colour, unit opacity   track colour, opacity
      bC = "#BF5AF2"; bA = 0.12; mC = "#5E5CE6"; bM = 0.04; bR = 84; bY = 104; cardO = 0; edge = "#FFFFFF"; edgeO = 0
      valC = "#FFFFFF"; uC = "#FFFFFF"; uO = 0.6; trC = "#FFFFFF"; trO = 0.18
      if (st == "calm")   { bA = 0.16; bM = 0.05; bR = 88 }
      if (st == "denied") { bC = "#FF375F"; bA = 0.10; mC = "#BF5AF2"; bM = 0.03; bR = 80 }
      if (st == "next")   { bA = 0.16; bM = 0.05; bR = 96; bY = 76; cardO = 0.06; edgeO = 0.08 }
      if (running)        { bC = "#5E5CE6"; bA = 0.22; mC = "#BF5AF2"; bM = 0.07; bR = 100; bY = 76; cardO = 0.06; edgeO = 0.08 }
      if (hot)            { bC = "#FF375F"; bA = 0.48; mC = "#BF5AF2"; bM = 0.14; bR = 108; bY = 76; cardO = 0.07; edge = "#FF375F"; edgeO = 0.55
                            trC = "#FF375F"; trO = 0.30
                            if (st == "soon") { valC = "#FF5C80"; uC = "#FF7A96"; uO = 0.95 } }   # pink minutes = minutes to the start; minutes left stay white
      bar = running ? 1 : 0
      liveO = live ? 1 : 0; secO = live ? 0.6 : 0
      cardY = live ? 0 : 12                    # the content of the card rises into place as it fades in

      # The calendar page is the face while there is no meeting to show. When one arrives the page opens
      # into the card: its outline becomes the panel of the card, and what is inside grows with it and fades.
      if (live) { px = 6;  py = 6;  pw = 188; ph = 134; pr = 20; pS = 1.5; gx1 = 6;  gx2 = 194 }
      else      { px = 48; py = 60; pw = 104; ph = 96;  pr = 18; pS = 5;   gx1 = 48; gx2 = 152 }
      p1 = "#BF5AF2"; p2 = "#64D2FF"; pA = 1; pGlow = 0.12
      if (st == "denied") { p1 = "#FFFFFF"; p2 = "#FFFFFF"; pA = 0.35 }
      if (live) { p1 = edge; p2 = edge; pA = edgeO; pGlow = 0 }          # the card keeps a faint edge, hot pink for attention
      if (live) { ix = 100; iy = 70.2; isx = 1.81; isy = 1.4; iO = 0 } else { ix = 100; iy = 106; isx = 1; isy = 1; iO = 1 }
      i1 = "#BF5AF2"; i2 = "#64D2FF"; iA = 1; ringO = 0.9
      dotsO = (st == "rest") ? 0.9 : 0; dateO = (st == "calm") ? 1 : 0
      slashO = 0; sx2 = -52; sy2 = 52
      if (st == "denied") { i1 = "#FFFFFF"; i2 = "#FFFFFF"; iA = 0.35; ringO = 0.35; dotsO = 0.35; slashO = 1; sx2 = 52; sy2 = -52 }
      dateS = (st == "calm" && day != "") ? day + 0 : ""

      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\"><defs>"
      printf "<linearGradient id=\"barG\" gradientUnits=\"userSpaceOnUse\" x1=\"%d\" y1=\"0\" x2=\"%d\" y2=\"0\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"0.35\" stop-color=\"%s\"/><stop offset=\"0.7\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></linearGradient>", B1, B0, s1, s2, s3, s4
      printf "<linearGradient id=\"pageG\" gradientUnits=\"userSpaceOnUse\" x1=\"%d\" y1=\"0\" x2=\"%d\" y2=\"0\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"%s\"/></linearGradient>", gx1, gx2, p1, f2(pA), p2, f2(pA)
      printf "<linearGradient id=\"inkG\" gradientUnits=\"userSpaceOnUse\" x1=\"-52\" y1=\"0\" x2=\"52\" y2=\"0\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"%s\"/></linearGradient>", i1, f2(iA), i2, f2(iA)
      printf "<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.55\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient>", bC, f2(bA), mC, f2(bM), mC
      printf "<radialGradient id=\"glowG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.4\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient>", gc, f2(bar * 0.55), gc, f2(bar * 0.22), gc
      printf "</defs>"
      printf "<circle id=\"bloom\" cx=\"100\" cy=\"%d\" r=\"%d\" fill=\"url(#bloomG)\"/>", bY, bR

      printf "<rect id=\"pageGlow\" x=\"%d\" y=\"%d\" width=\"%d\" height=\"%d\" rx=\"%d\" fill=\"none\" stroke=\"url(#pageG)\" stroke-opacity=\"%s\" stroke-width=\"14\"/>", px, py, pw, ph, pr, f2(pGlow)
      printf "<rect id=\"page\" x=\"%d\" y=\"%d\" width=\"%d\" height=\"%d\" rx=\"%d\" fill=\"#FFFFFF\" fill-opacity=\"%s\" stroke=\"url(#pageG)\" stroke-width=\"%s\"/>", px, py, pw, ph, pr, f2(cardO), pS
      printf "<g id=\"ink\" transform=\"translate(%s %s) scale(%s %s) rotate(0 0 0)\">", ix, iy, isx, isy
      printf "<path id=\"band\" d=\"M -49.5 -20 L -49.5 -28 A 15.5 15.5 0 0 1 -34 -43.5 L 34 -43.5 A 15.5 15.5 0 0 1 49.5 -28 L 49.5 -20 Z\" fill=\"url(#inkG)\" fill-opacity=\"%s\"/>", f2(iO * 0.85)
      printf "<path id=\"rings\" d=\"M -26 -58 L -26 -38 M 26 -58 L 26 -38\" fill=\"none\" stroke=\"#FFFFFF\" stroke-opacity=\"%s\" stroke-width=\"7\" stroke-linecap=\"round\"/>", f2(iO * ringO)
      printf "<path id=\"dots\" d=\"M -30 -2 l 0.01 0 M -10 -2 l 0.01 0 M 10 -2 l 0.01 0 M 30 -2 l 0.01 0 M -30 14 l 0.01 0 M -10 14 l 0.01 0 M 10 14 l 0.01 0 M 30 14 l 0.01 0 M -30 30 l 0.01 0 M -10 30 l 0.01 0 M 10 30 l 0.01 0 M 30 30 l 0.01 0\" fill=\"none\" stroke=\"url(#inkG)\" stroke-opacity=\"%s\" stroke-width=\"9\" stroke-linecap=\"round\"/>", f2(iO * dotsO)
      printf "<text id=\"date\" x=\"0\" y=\"15\" font-size=\"46\" font-weight=\"600\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"%s\">%s</text>", f2(iO * dateO), show(dateS)
      printf "<line id=\"slashGlow\" x1=\"-52\" y1=\"52\" x2=\"%d\" y2=\"%d\" stroke=\"#FF375F\" stroke-opacity=\"%s\" stroke-width=\"18\" stroke-linecap=\"round\"/>", sx2, sy2, f2(iO * slashO * 0.25)
      printf "<line id=\"slash\" x1=\"-52\" y1=\"52\" x2=\"%d\" y2=\"%d\" stroke=\"#FF375F\" stroke-opacity=\"%s\" stroke-width=\"7\" stroke-linecap=\"round\"/>", sx2, sy2, f2(iO * slashO)
      printf "</g>"

      printf "<g id=\"card\" transform=\"translate(0 %d)\">", cardY
      printf "<line id=\"stripGlow\" x1=\"18\" y1=\"22\" x2=\"18\" y2=\"124\" stroke=\"%s\" stroke-opacity=\"%s\" stroke-width=\"13\" stroke-linecap=\"round\"/>", ac, f2(liveO * 0.28)
      printf "<line id=\"strip\" x1=\"18\" y1=\"22\" x2=\"18\" y2=\"124\" stroke=\"%s\" stroke-opacity=\"%s\" stroke-width=\"5\" stroke-linecap=\"round\"/>", ac, f2(liveO)
      printf "<text id=\"title1\" x=\"31\" y=\"%d\" font-size=\"%d\" font-weight=\"600\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"%s\">%s</text>", T1, TF, f2(liveO), show(t1)
      printf "<text id=\"title2\" x=\"31\" y=\"53\" font-size=\"19\" font-weight=\"600\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"%s\">%s</text>", f2(t2 == "" ? 0 : liveO), show(t2)
      printf "<text id=\"range\" x=\"31\" y=\"77\" font-size=\"16\" font-weight=\"600\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"%s\">%s</text>", f2(secO), show(tr)
      printf "<text id=\"value\" x=\"%s\" y=\"101\" font-size=\"%d\" font-weight=\"600\" dominant-baseline=\"middle\" fill=\"%s\" fill-opacity=\"%s\">%s</text>", f2(x1), VF, valC, f2(liveO), show(v1)
      printf "<text id=\"unit\" x=\"%s\" y=\"104\" font-size=\"%d\" font-weight=\"600\" dominant-baseline=\"middle\" fill=\"%s\" fill-opacity=\"%s\">%s</text>", f2(x2), UF, uC, f2(live ? uO : 0), u1
      printf "<text id=\"value2\" x=\"%s\" y=\"101\" font-size=\"%d\" font-weight=\"600\" dominant-baseline=\"middle\" fill=\"%s\" fill-opacity=\"%s\">%s</text>", f2(x3), VF, valC, f2(two * liveO), show(v2)
      printf "<text id=\"unit2\" x=\"%s\" y=\"104\" font-size=\"%d\" font-weight=\"600\" dominant-baseline=\"middle\" fill=\"%s\" fill-opacity=\"%s\">%s</text>", f2(x4), UF, uC, f2(two * (live ? uO : 0)), u2
      printf "<line id=\"track\" x1=\"%d\" y1=\"%d\" x2=\"%d\" y2=\"%d\" stroke=\"%s\" stroke-opacity=\"%s\" stroke-width=\"6\" stroke-linecap=\"round\"/>", B0, BY, B1, BY, trC, f2(liveO * trO)
      printf "<line id=\"litGlow\" x1=\"%d\" y1=\"%d\" x2=\"%s\" y2=\"%d\" stroke=\"url(#barG)\" stroke-opacity=\"%s\" stroke-width=\"22\" stroke-linecap=\"round\"/>", B0, BY, f2(bx), BY, f2(bar * 0.2)
      printf "<line id=\"lit\" x1=\"%d\" y1=\"%d\" x2=\"%s\" y2=\"%d\" stroke=\"url(#barG)\" stroke-opacity=\"%s\" stroke-width=\"9\" stroke-linecap=\"round\"/>", B0, BY, f2(bx), BY, f2(bar)
      printf "<line id=\"core\" x1=\"%d\" y1=\"%d\" x2=\"%s\" y2=\"%d\" stroke=\"#FFFFFF\" stroke-opacity=\"%s\" stroke-width=\"2.5\" stroke-linecap=\"round\"/>", B0, BY, f2(bx), BY, f2(bar * 0.45)
      printf "<circle id=\"glow\" cx=\"%s\" cy=\"%d\" r=\"26\" fill=\"url(#glowG)\"/>", f2(bx), BY
      printf "<circle id=\"halo\" cx=\"%s\" cy=\"%d\" r=\"9\" fill=\"%s\" fill-opacity=\"%s\"/>", f2(bx), BY, gc, f2(bar * 0.45)
      printf "<circle id=\"bead\" cx=\"%s\" cy=\"%d\" r=\"6\" fill=\"#FFFFFF\" fill-opacity=\"%s\"/>", f2(bx), BY, f2(bar)
      printf "<circle id=\"thenDot\" cx=\"18\" cy=\"159\" r=\"4.5\" fill=\"%s\" fill-opacity=\"%s\"/>", bc, f2(then ? 0.9 : 0)
      printf "<text id=\"thenTime\" x=\"31\" y=\"159\" font-size=\"16\" font-weight=\"600\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"%s\">%s</text>", f2(then ? 0.6 : 0), show(btm)
      printf "<text id=\"thenTitle\" x=\"31\" y=\"181\" font-size=\"16\" font-weight=\"600\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"%s\">%s</text>", f2(then ? 0.6 : 0), show(bt)
      printf "</g>"
      printf "</svg>\n"
    }'
}

api="http://127.0.0.1:9848"
cell="{{CELL_ID}}"
dir="$DESMAPTIC_STORAGE/gallery/$cell"
zf_mkdir -p "$dir" 2>/dev/null

# The calendar reader: one long-lived JavaScript for Automation process that reads EventKit, so the stock
# osascript is all it needs. Every minute (just after the minute turns) it prints a block:
#   !ok | !ask (waiting for the answer to the access prompt) | !denied <status>
#   <start epoch>|<end epoch>|<calendar colour>|<key>|<call link>|<title>   … one line per event, by start
#   --
# It ends by itself after about three hours; the loop below starts a fresh one.
read -r -d '' reader_js <<'JXA'
ObjC.import("Foundation");
ObjC.import("AppKit");
ObjC.import("EventKit");

var out = $.NSFileHandle.fileHandleWithStandardOutput;
var err = $.NSFileHandle.fileHandleWithStandardError;
function put(handle, text) {
  var data = $(text).dataUsingEncodingAllowLossyConversion($.NSUTF8StringEncoding, true);
  if (!data.isNil()) handle.writeData(data);
}
function block(lines) { put(out, lines.join("\n") + "\n--\n"); }
function access() { return Number($.EKEventStore.authorizationStatusForEntityType($.EKEntityTypeEvent)); }
function text(value) {
  try { var s = ObjC.unwrap(value); return (typeof s === "string") ? s : ""; } catch (e) { return ""; }
}
function clean(s) {
  return Array.from(s.replace(/[\u0000-\u001f\u007f\u2028\u2029]+/g, " ").replace(/\s+/g, " ").trim()).slice(0, 120).join("");
}

// A call link: the event URL, else the first Zoom / Meet / Teams / Webex / FaceTime link in the location or notes.
var CALL_HOSTS = /(^|\.)(zoom\.us|zoomgov\.com|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com|facetime\.apple\.com)$/i;
var SAFE_LINK = /^https?:\/\/[^\s"'<>|\\^`{}]+$/i;
function callLink(s) {
  var re = /https?:\/\/([A-Za-z0-9.-]+)(:[0-9]+)?([\/?#][^\s"'<>|\\^`{}]*)?/g, m;
  while ((m = re.exec(s)) !== null) {
    if (CALL_HOSTS.test(m[1])) return m[0].replace(/[.,;:!?)\]]+$/, "");
  }
  return "";
}
function linkOf(ev) {
  var own = "";
  try { var url = ev.URL; if (!url.isNil()) own = text(url.absoluteString); } catch (e) {}
  if (SAFE_LINK.test(own)) return own;
  return callLink(text(ev.location)) || callLink(text(ev.notes));
}
function colourOf(ev) {
  try {
    var c = ev.calendar.color.colorUsingColorSpace($.NSColorSpace.sRGBColorSpace);
    if (c.isNil()) return "";
    var h = function (x) { var n = Math.round(Math.max(0, Math.min(1, Number(x))) * 255); return (n < 16 ? "0" : "") + n.toString(16).toUpperCase(); };
    return "#" + h(c.redComponent) + h(c.greenComponent) + h(c.blueComponent);
  } catch (e) { return ""; }
}
function declined(ev) {
  try {
    var people = ev.attendees;
    if (people.isNil()) return false;
    for (var i = 0; i < people.count; i++) {
      var p = people.objectAtIndex(i);
      if (p.isCurrentUser) return Number(p.participantStatus) === 3;   // EKParticipantStatusDeclined
    }
  } catch (e) {}
  return false;
}
function keyOf(ev, start) {   // 12 hex characters, the same for one occurrence of one event
  var s = text(ev.eventIdentifier) + "@" + start, a = 0x811c9dc5, b = 0x9747b28c;
  for (var i = 0; i < s.length; i++) {
    a = Math.imul(a ^ s.charCodeAt(i), 16777619) >>> 0;
    b = Math.imul(b ^ s.charCodeAt(i), 2246822519) >>> 0;
  }
  return ("0000000" + a.toString(16)).slice(-8).toUpperCase() + ("000" + (b & 0xffff).toString(16)).slice(-4).toUpperCase();
}
function events(store) {
  var now = $.NSDate.date, nowS = Date.now() / 1000, list = [];
  // Every event calendar, named explicitly: the bridge turns a JavaScript null into NSNull, not nil,
  // and EventKit then raises "-[NSNull count]" (seen on the first live run).
  var found = store.eventsMatchingPredicate(store.predicateForEventsWithStartDateEndDateCalendars(
    now.dateByAddingTimeInterval(-12 * 3600), now.dateByAddingTimeInterval(24 * 3600),
    store.calendarsForEntityType($.EKEntityTypeEvent)));
  var count = found.isNil() ? 0 : Number(found.count);
  for (var i = 0; i < count; i++) {
    var ev = found.objectAtIndex(i);
    if (ev.isAllDay || Number(ev.status) === 3 /* EKEventStatusCanceled */ || declined(ev)) continue;
    var s = Math.floor(Number(ev.startDate.timeIntervalSince1970)), e = Math.floor(Number(ev.endDate.timeIntervalSince1970));
    if (!(e > s)) e = s + 60;
    if (!(e > nowS)) continue;
    list.push({ s: s, e: e, line: [s, e, colourOf(ev), keyOf(ev, s), linkOf(ev), clean(text(ev.title)) || "—"].join("|") });
  }
  list.sort(function (x, y) { return (x.s - y.s) || (x.e - y.e); });
  return list.slice(0, 12).map(function (x) { return x.line; });
}

var NOT_DETERMINED = 0, FULL_ACCESS = 3;   // EKAuthorizationStatus
if (access() === NOT_DETERMINED) {
  block(["!ask"]);
  var asker = $.EKEventStore.alloc.init;
  var answered = function (granted, error) {};
  try { asker.requestFullAccessToEventsWithCompletion(answered); }
  catch (e) {
    try { asker.requestAccessToEntityTypeCompletion($.EKEntityTypeEvent, answered); }
    catch (e2) { put(err, "calendar: cannot ask for calendar access: " + e2 + "\n"); }
  }
  for (var wait = 0; wait < 120 && access() === NOT_DETERMINED; wait++) delay(1);
}
for (var round = 0; round < 180; round++) {
  var status = access();
  if (status === FULL_ACCESS) {
    block(["!ok"].concat(events($.EKEventStore.alloc.init)));   // a fresh store sees every change since the last minute
  } else {
    block(["!denied " + status]);
  }
  delay(60.5 - (Date.now() / 1000) % 60);
}
void 0;   // osascript would print a result
JXA

start_reader() {
  coproc /usr/bin/osascript -l JavaScript -e "$reader_js"
  reader=$! started=$EPOCHSECONDS
}

typeset -a ev_s ev_e ev_c ev_k ev_l ev_t lines notified
if [[ -r $dir/notified ]]; then while IFS= read -r line; do notified+=$line; done < "$dir/notified"; fi
perm="" said="" link="-" last="" sent=0 hidden=0 looked=0 retry=0

# The last block → ev_* arrays and perm (ok | ask | denied).
take_block() {
  local line rest
  ev_s=() ev_e=() ev_c=() ev_k=() ev_l=() ev_t=()
  for line in "${lines[@]}"; do
    case $line in
      '!ok') perm=ok ;;
      '!ask') perm=ask ;;
      '!denied'*) perm=denied ;;
      *)
        rest=$line
        local s=${rest%%|*}; rest=${rest#*|}
        local e=${rest%%|*}; rest=${rest#*|}
        local c=${rest%%|*}; rest=${rest#*|}
        local k=${rest%%|*}; rest=${rest#*|}
        local l=${rest%%|*}; rest=${rest#*|}
        [[ $s == <-> && $e == <-> && ${#k} == 12 && $k != *[^0-9A-F]* ]] || continue
        [[ $l == https://* || $l == http://* ]] || l=""
        ev_s+=$s ev_e+=$e ev_c+=$c ev_k+=$k ev_l+=$l ev_t+=$rest
        ;;
    esac
  done
  lines=()
  if [[ $perm == denied && $said != denied ]]; then
    print -ru2 -- "calendar: Allow the agent to access Calendars: System Settings → Privacy & Security → Calendars"
  fi
  said=$perm
}

# "5 min" notification with a Join action, once per event occurrence.
notify() {   # $1 key  $2 minutes  $3 title  $4 link
  local title=${3//\\/\\\\} url=${4//\\/\\\\} code
  title=${title//\"/\\\"}; url=${url//\"/\\\"}
  code=$(curl -q -s -m 5 -o /dev/null -w '%{http_code}' "$api/api/notify" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' -H "Content-Type: application/json" \
    -d "{\"id\":\"CA1E0DA7-0000-4000-8000-$1\",\"cellId\":\"$cell\",\"title\":\"$title\",\"body\":\"$2 min\",\"targets\":[\"phone\",\"mac\"],\"actions\":[{\"id\":\"join\",\"title\":\"▶︎\",\"command\":{\"openURL\":{\"url\":\"$url\"}}}]}")
  if [[ $code == 200 ]]; then
    notified=( ${notified[-29,-1]} $1 )
    print -rl -- $notified > "$dir/notified.tmp" && zf_mv -f "$dir/notified.tmp" "$dir/notified"
  else
    print -ru2 -- "calendar: notify answered ${code:-nothing}"
  fi
}

# Picks what the card shows now (st, p = the event on the card, q = the one after it), keeps the tap's
# link and sends due notifications. Runs even while the button is hidden: notifications do not wait.
st=rest p=0 q=0
# REPLY = the coming local midnight, epoch. Today's midnight plus 36 hours is always some time tomorrow, however
# long today is (23 or 25 hours when the clocks change).
day_end() {   # $1 now
  local day
  strftime -s day '%Y-%m-%d' $1
  strftime -r -s REPLY '%Y-%m-%d' $day
  strftime -s day '%Y-%m-%d' $(( REPLY + 36 * 3600 ))
  strftime -r -s REPLY '%Y-%m-%d' $day
}
compose() {
  local now=$EPOCHSECONDS i cur=0 u1=0 u2=0 next="" end
  st=calm p=0 q=0
  if [[ $perm == denied ]]; then st=denied
  elif [[ $perm != ok ]]; then st=rest
  else
    # The card is today's: the meeting in progress, then the ones that start before midnight. The face has no
    # day on it, so tomorrow morning's meeting shown in the evening read as today's. One starting in 5 minutes
    # or less shows even across midnight; notifications go out whatever the day.
    day_end $now; end=$REPLY
    for (( i = 1; i <= $#ev_s; i++ )); do
      (( ev_e[i] > now )) || continue
      if (( ev_s[i] <= now )); then cur=$i        # in progress; by start order, the last one began most recently
      elif (( ev_s[i] >= end && ev_s[i] - now > 300 )); then :   # tomorrow: not on today's card
      elif (( ! u1 )); then u1=$i
      elif (( ! u2 )); then u2=$i
      fi
      if (( ev_s[i] > now && ev_s[i] - now <= 300 )) && [[ -n $ev_l[i] ]] && (( ! ${notified[(Ie)$ev_k[i]]} )); then
        notify $ev_k[i] $(( (ev_s[i] - now + 59) / 60 )) "$ev_t[i]" "$ev_l[i]"
      fi
    done
    if (( u1 && ev_s[u1] - now <= 300 )); then p=$u1 q=$u2 st=soon
    elif (( cur )); then p=$cur q=$u1 st=now
    elif (( u1 )); then p=$u1 q=$u2 st=next
    fi
  fi

  if (( p )); then next=$ev_l[p]; elif [[ $st == denied ]]; then next=settings; fi
  if [[ $next != $link ]]; then
    print -r -- "$next" > "$dir/link.tmp" && zf_mv -f "$dir/link.tmp" "$dir/link" && link=$next
  fi
}

# The frame for what compose picked.
draw() {
  local now=$EPOCHSECONDS day tr a b
  strftime -s day '%d' $now; day=${day#0}
  if (( p )); then
    strftime -s a '%H:%M' $ev_s[p]; strftime -s b '%H:%M' $ev_e[p]; tr="$a–$b"
    if (( q )); then
      strftime -s b '%H:%M' $ev_s[q]
      frame=$(calendar_frame $st $now "$day" $ev_s[p] $ev_e[p] "$ev_c[p]" "$ev_t[p]" "$tr" "$ev_c[q]" "$ev_t[q]" "$b")
    else
      frame=$(calendar_frame $st $now "$day" $ev_s[p] $ev_e[p] "$ev_c[p]" "$ev_t[p]" "$tr")
    fi
  else
    frame=$(calendar_frame $st $now "$day")
  fi
}

post() {   # $1 frame → 0 when the agent took it
  local json=$1 resp code body
  json=${json//\\/\\\\}; json=${json//\"/\\\"}; json=${json//$'\n'/}
  resp=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' -H "Content-Type: application/json" \
    -d "{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$json\",\"duration\":1.2}}")
  code=${resp##*$'\n'} body=${resp%$'\n'*}
  if [[ $code != 200 ]]; then
    print -ru2 -- "calendar: update-button answered ${code:-nothing}: $body"
    return 1
  fi
  [[ ${body//[[:space:]]/} == *'"visible":false'* ]] && hidden=1
  return 0
}

on_screen() {   # the phone shows this button (or is too old to say)
  local body
  body=$(curl -q -s -m 5 "$api/api/view" --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}') || return 1
  body=${(L)body//[[:space:]]/}
  [[ $body == *'"view":null'* || $body == *${(L)cell}* ]]
}

start_reader
while true; do
  now=$EPOCHSECONDS
  wait=$(( 61 - now % 60 ))                    # a new frame every minute for the countdown
  (( hidden && wait > 3 )) && wait=3           # hidden: look at the phone every 3 s
  (( retry && wait > 10 )) && wait=10          # the agent did not take the last frame
  t0=$EPOCHREALTIME
  if IFS= read -r -t $wait -p line; then
    if [[ $line != -- ]]; then lines+=("$line"); continue; fi
    take_block
  elif ! kill -0 $reader 2>/dev/null || (( EPOCHREALTIME - t0 < wait - 0.5 )); then
    if (( EPOCHSECONDS - started < 60 )); then
      print -ru2 -- "calendar: the calendar reader stopped; starting it again in 30 s"
      zselect -t 3000
    fi
    lines=()
    start_reader
    continue
  fi
  [[ -n $perm ]] || continue                   # nothing read yet: the saved face stays

  compose
  if (( hidden )); then
    (( EPOCHSECONDS - looked >= 3 )) || continue
    looked=$EPOCHSECONDS
    on_screen || continue
    hidden=0 last=""
  fi
  draw
  if [[ $frame != $last ]] || (( EPOCHSECONDS - sent >= 300 )); then   # on change, and a keyframe every 5 min
    if post "$frame"; then last=$frame sent=$EPOCHSECONDS retry=0; else retry=1; fi
  fi
done
