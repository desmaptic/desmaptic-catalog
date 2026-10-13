# Xcode › DerivedData: how much Xcode's DerivedData folder takes, on a neon gauge that fills toward 20 GB and turns
# pink past it (1×1 SVG face). The startup script is folder.zsh and then this file (app.json).
#
# The size comes from du, at the lowest CPU priority, in the background — the loop never waits on a big folder —
# every 3 minutes while the button is on screen, and at once after a tap or a long press (action.zsh leaves a
# "measure" file in this button's storage). Off screen nothing is measured: a look at the phone every 5 s, and only
# once the size is due again. The loop also deletes, in the background, what a clear moved aside.
#
# Every frame has the same 14 elements in the same order: the phone glides between them.
# `zsh startup.zsh --face <rest|wait|none|ok|big> <fill, per mille of 20 GB> [value] [unit]` prints one frame
# (rest.svg and demo.svg are made that way).
emulate -R zsh                                # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
measurer=0 cleaner=0
trap '(( measurer )) && kill $measurer 2>/dev/null; (( cleaner )) && kill $cleaner 2>/dev/null; exit 0' TERM INT HUP

# MARK: - Face

# dd_frame <state> <fill> [value] [unit]. rest: the big folder alone (the face before the script runs); wait: the
# first measurement is running ("…"); none: no folder to measure ("—"); ok: a size; big: a size past 20 GB, pink.
# The gauge is the family's 240° arc, lit up to fill/1000 of 20 GB, with the bead at its end.
dd_frame() {
  emulate -L zsh
  export LC_ALL=C
  local state=${1:-rest} fill=${2:-0} value=${3:-—} unit=${4:-GB}
  [[ $state == (rest|wait|none|ok|big) ]] || state=rest
  [[ $fill == <-> ]] || fill=0
  (( fill > 1000 )) && fill=1000
  [[ $unit == (MB|GB|TB) ]] || unit=GB
  value=${value//[[:cntrl:]&<>]/}
  [[ -n $value ]] || value="—"                 # never an empty <text>: the structure must not change
  DD_VAL=$value awk -v st=$state -v u=$fill -v unit=$unit '
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
    function f(x) { return sprintf("%.2f", x) }
    function P(x, y) { return sprintf("%.2f %.2f", fx + k * x, fy + k * y) }   # a point of the folder, placed
    BEGIN {
      val = ENVIRON["DD_VAL"]
      data = (st == "ok" || st == "big")       # a size on the face: the gauge is lit
      live = (st != "rest")                    # the folder is small, under the value

      L = 335.10                               # arc length: r 80 · 240° = 80 · 4π/3
      fr = data ? u / 1000 : 0.5               # without a size: arc end, bead and glow parked at 12 o’clock
      d = L * fr; if (d > L - 0.3) d = L - 0.3 # keep the bead’s dash on the path
      off = L * (1 - fr); pos = -d             # lit dash covers 0 … L·fr; the bead is a 0.1-long dash at L·fr
      ang = -120 + 240 * fr                    # glow: degrees clockwise from 12 o’clock
      x = 100 + 80 * sin(ang * 3.14159265 / 180)
      gc = spectrum((x - 24) / 152)            # glow colour = the arc colour under the bead

      # bloom centre / mid colour, opacity and radius; bead glow radius and opacity; halo width and opacity;
      # value and unit colour and opacity; folder gradient and opacity
      bC = "#BF5AF2"; bA = 0.12; mC = "#5E5CE6"; bM = 0.04; bR = 82; gR = 28; gA = 0.55; hW = 18; hO = 0.45
      vC = "#FFFFFF"; vO = 0; uC = "#FFFFFF"; uO = 0; f1 = "#BF5AF2"; f2 = "#64D2FF"; fO = 0.8
      if (st == "wait") { bA = 0.14; bM = 0.05; bR = 84; vO = 0.45; fO = 0.9 }
      if (st == "none") { bA = 0.14; bM = 0.05; bR = 84; vO = 0.55; fO = 0.9 }
      if (st == "ok")   { bA = 0.20; bM = 0.07; bR = 86; vO = 1; uO = 0.6; fO = 0.9 }
      if (st == "big")  { bC = "#FF375F"; bA = 0.57; mC = "#BF5AF2"; bM = 0.16; bR = 98; gR = 32; gA = 0.95; hW = 22; hO = 0.60
                          vO = 1; uC = "#FF7A96"; uO = 0.95; f1 = "#FF375F"; f2 = "#FF8FA8"; fO = 1; gc = "#FF375F" }
      # track: a faint spectrum without a size, white 0.18 with one, hot pink past 20 GB
      split("#64D2FF #5E5CE6 #BF5AF2 #FF375F", tc, " "); split("0.30 0.30 0.30 0.30", to, " ")
      if (st == "ok")  { split("#FFFFFF #FFFFFF #FFFFFF #FFFFFF", tc, " "); split("0.18 0.18 0.18 0.18", to, " ") }
      if (st == "big") { split("#FF375F #FF375F #FF375F #FF375F", tc, " "); split("0.20 0.20 0.24 0.30", to, " ") }

      # the folder: big in the middle at rest; once the widget runs it sinks under the value and stays small.
      # Its points are placed here, not by a transform: a translate + scale turns around a point far off the
      # button, and the glide between two of them flings the folder away halfway.
      if (live) { fx = 100; fy = 172; k = 0.36; sw = 3.4 } else { fx = 100; fy = 99; k = 1.05; sw = 5 }
      vs = (length(val) >= 4) ? 56 : 60        # "18.6" still clears the arc
      arc = "d=\"M 30.72 140 A 80 80 0 1 1 169.28 140\" fill=\"none\""

      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\"><defs>"
      printf "<linearGradient id=\"spec\" gradientUnits=\"userSpaceOnUse\" x1=\"24\" y1=\"0\" x2=\"176\" y2=\"0\"><stop offset=\"0\" stop-color=\"#64D2FF\"/><stop offset=\"0.3\" stop-color=\"#5E5CE6\"/><stop offset=\"0.65\" stop-color=\"#BF5AF2\"/><stop offset=\"1\" stop-color=\"#FF375F\"/></linearGradient>"
      printf "<linearGradient id=\"trackG\" gradientUnits=\"userSpaceOnUse\" x1=\"24\" y1=\"0\" x2=\"176\" y2=\"0\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.3\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.65\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"%s\"/></linearGradient>", tc[1], to[1], tc[2], to[2], tc[3], to[3], tc[4], to[4]
      printf "<linearGradient id=\"folderG\" gradientUnits=\"userSpaceOnUse\" x1=\"%s\" y1=\"0\" x2=\"%s\" y2=\"0\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></linearGradient>", f(fx - 42 * k), f(fx + 42 * k), f1, f2
      printf "<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.55\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient>", bC, f(bA), mC, f(bM), mC
      printf "<radialGradient id=\"glowG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.4\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient></defs>", gc, f(data * gA), gc, f(data * 0.4 * gA), gc
      printf "<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"%d\" fill=\"url(#bloomG)\"/>", bR
      printf "<path id=\"track\" %s stroke=\"url(#trackG)\" stroke-width=\"6\" stroke-linecap=\"round\"/>", arc
      printf "<path id=\"tick\" d=\"M 100 38 L 100 33\" fill=\"none\" stroke=\"#FFFFFF\" stroke-opacity=\"0.3\" stroke-width=\"2.5\" stroke-linecap=\"round\"/>"
      printf "<line id=\"tickLow\" x1=\"46.31\" y1=\"131\" x2=\"41.98\" y2=\"133.5\" stroke=\"#64D2FF\" stroke-opacity=\"0.9\" stroke-width=\"3\" stroke-linecap=\"round\"/>"
      printf "<line id=\"tickHigh\" x1=\"153.69\" y1=\"131\" x2=\"158.02\" y2=\"133.5\" stroke=\"#FF375F\" stroke-opacity=\"%s\" stroke-width=\"3\" stroke-linecap=\"round\"/>", f(st == "big" ? 0 : 0.9)
      printf "<path id=\"litGlow\" %s stroke=\"url(#spec)\" stroke-opacity=\"%s\" stroke-width=\"22\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 335.1\" stroke-dashoffset=\"%s\"/>", arc, f(data * 0.2), f(off)
      printf "<path id=\"lit\" %s stroke=\"url(#spec)\" stroke-opacity=\"%s\" stroke-width=\"9\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 335.1\" stroke-dashoffset=\"%s\"/>", arc, f(data), f(off)
      printf "<path id=\"core\" %s stroke=\"#FFFFFF\" stroke-opacity=\"%s\" stroke-width=\"2.5\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 335.1\" stroke-dashoffset=\"%s\"/>", arc, f(data * 0.45), f(off)
      printf "<circle id=\"glow\" cx=\"100\" cy=\"26\" r=\"%d\" fill=\"url(#glowG)\" transform=\"rotate(%s 100 100)\"/>", gR, f(ang)
      printf "<path id=\"halo\" %s stroke=\"url(#spec)\" stroke-opacity=\"%s\" stroke-width=\"%d\" stroke-linecap=\"round\" stroke-dasharray=\"0.1 400\" stroke-dashoffset=\"%s\"/>", arc, f(data * hO), hW, f(pos)
      printf "<path id=\"bead\" %s stroke=\"#FFFFFF\" stroke-opacity=\"%s\" stroke-width=\"12\" stroke-linecap=\"round\" stroke-dasharray=\"0.1 400\" stroke-dashoffset=\"%s\"/>", arc, f(data), f(pos)
      printf "<text id=\"value\" x=\"100\" y=\"97\" font-size=\"%d\" font-weight=\"600\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"%s\" fill-opacity=\"%s\">%s</text>", vs, vC, f(vO), val
      printf "<text id=\"unit\" x=\"100\" y=\"138\" font-size=\"26\" font-weight=\"600\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"%s\" fill-opacity=\"%s\">%s</text>", uC, f(uO), unit
      folder = "M " P(-42, -24) " Q " P(-42, -30) " " P(-36, -30) " L " P(-12, -30) " L " P(-4, -20) " L " P(36, -20) \
        " Q " P(42, -20) " " P(42, -14) " L " P(42, 26) " Q " P(42, 32) " " P(36, 32) " L " P(-36, 32) \
        " Q " P(-42, 32) " " P(-42, 26) " Z M " P(-42, -10) " L " P(42, -10)
      printf "<path id=\"folder\" d=\"%s\" fill=\"none\" stroke=\"url(#folderG)\" stroke-opacity=\"%s\" stroke-width=\"%s\" stroke-linejoin=\"round\" stroke-linecap=\"round\"/>", folder, f(fO), f(sw)
      printf "</svg>\n"
    }'
}

if [[ $1 == --face ]]; then
  shift
  dd_frame "$@"
  exit 0
fi

# MARK: - Size

# "<state> <fill> <value> <unit>" for a size in kB (du's), in decimal units as Finder counts: 412 MB, 7.4 GB, 18.6 GB,
# 142 GB, 1.2 TB; big past 20 GB, the gauge full at 20 GB.
describe() {
  awk -v k="$1" 'BEGIN {
    gb = k * 1024 / 1e9
    if (gb < 0.9995)     { v = sprintf("%d", gb * 1000 + 0.5); u = "MB" }
    else if (gb < 99.95) { v = sprintf("%.1f", gb); u = "GB" }
    else if (gb < 999.5) { v = sprintf("%d", gb + 0.5); u = "GB" }
    else                 { t = gb / 1000; v = (t < 99.95) ? sprintf("%.1f", t) : sprintf("%d", t + 0.5); u = "TB" }
    fill = int(gb / 20 * 1000 + 0.5); if (fill > 1000) fill = 1000
    print ((gb > 20) ? "big" : "ok"), fill, v, u
  }'
}

# MARK: - Loop

zmodload zsh/datetime zsh/zselect || { print -u2 -- "DerivedData: zsh modules datetime/zselect are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_rm || { print -u2 -- "DerivedData: zsh module files is missing"; exit 1 }
[[ -n $DESMAPTIC_STORAGE ]] || { print -u2 -- "DerivedData: DESMAPTIC_STORAGE is not set"; exit 1 }

api="http://127.0.0.1:9848/api"
cell="{{CELL_ID}}"
dir="$DESMAPTIC_STORAGE/gallery/$cell"          # measure: a request from the tap or the long press; size: du's answer
zf_mkdir -p "$dir" 2>/dev/null
period=180                                    # seconds between measurements while the button is on screen
patience=600                                  # a du that takes longer is stopped and tried again a period later

hidden=0
post() {   # $1 frame → 0 when the agent took it; hidden=1 when the phone does not show the button
  local p=$1 out code body
  p=${p//\\/\\\\}; p=${p//\"/\\\"}; p=${p//$'\n'/}
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' -H "Content-Type: application/json" \
    -d "{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$p\",\"duration\":1.2}}")
  code=${out##*$'\n'} body=${out%$'\n'*}
  if [[ $code != 200 ]]; then
    print -ru2 -- "DerivedData: update-button answered ${code:-nothing}: ${body[1,300]}"
    return 1
  fi
  [[ ${body//[[:space:]]/} == *'"visible":false'* ]] && hidden=1 || hidden=0
  return 0
}

looked=0
visible() {   # does the phone show the button (or is it too old to say)? Asks at most every 5 s while it does not.
  local out code body
  (( hidden && EPOCHSECONDS - looked < 5 )) && return 1
  looked=$EPOCHSECONDS
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/view" --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}') || { hidden=1; return 1 }
  code=${out##*$'\n'} body=${(L)${out%$'\n'*}//[[:space:]]/}
  if [[ $code != 200 || $body == *'"view":null'* || $body == *${(L)cell}* ]]; then
    hidden=0
  else
    hidden=1
  fi
  (( ! hidden ))
}

stop_measuring() {
  (( measurer )) || return 0
  kill $measurer 2>/dev/null
  wait $measurer 2>/dev/null
  measurer=0
}

# Deletes what a clear moved aside (action.zsh), in the background: Xcode already sees an empty folder.
swept=""
sweep() {   # $1 the folder
  local -a moved
  (( cleaner )) && return 0
  [[ -n $HOME && $1 == "${HOME:A}"/?* ]] || return 0
  moved=( "$1"/.desmaptic-clearing-*(N/) )    # real folders only: a symlink of that name is left alone
  (( $#moved )) || return 0
  swept=$1
  nice -n 20 rm -rf -- "${moved[@]}" 2>/dev/null &
  cleaner=$!
}

# Starts du on the folder; without one to measure the face says "—" at once.
start_measuring() {
  local folder
  if ! derived_data; then
    face=( none 0 "—" GB ) measured_at=$EPOCHREALTIME cleared=0
    [[ $REPLY != "$told" ]] && { told=$REPLY; print -ru2 -- "$REPLY" }
    return
  fi
  folder=${REPLY:A}
  if [[ ! -d $folder ]]; then                 # not built yet, or a custom location that is not there (a disk away)
    face=( none 0 "—" GB ) measured_at=$EPOCHREALTIME cleared=0
    return
  fi
  sweep "$folder"
  nice -n 20 du -sk -I '.desmaptic-clearing-*' -- "$folder" > "$dir/size" 2>/dev/null &
  measurer=$! began=$EPOCHREALTIME
}

face=( wait 0 "…" GB ) drawn="" measured_at=0 began=0 want=0 told="" cleared=0
while true; do
  if [[ -e $dir/measure ]]; then              # a tap or a long press: measure now, whatever was running
    asked=""
    IFS= read -r asked < "$dir/measure" 2>/dev/null
    zf_rm -f "$dir/measure" 2>/dev/null
    stop_measuring
    want=1
    [[ $asked == clear ]] && cleared=$EPOCHREALTIME
  fi

  if (( measurer )) && ! kill -0 $measurer 2>/dev/null; then
    wait $measurer 2>/dev/null
    measurer=0 measured_at=$EPOCHREALTIME cleared=0 kb=""
    read -r kb _ < "$dir/size" 2>/dev/null   # du prints the total even when a subfolder could not be read
    if [[ $kb == <-> ]]; then face=( ${=$(describe $kb)} ); else face=( none 0 "—" GB ); fi
  elif (( measurer && EPOCHREALTIME - began > patience )); then
    print -u2 -- "DerivedData: du took over $patience s — stopped, trying again later"
    stop_measuring
    measured_at=$EPOCHREALTIME
    (( cleared )) && face=( none 0 "—" GB ) cleared=0
  elif (( cleared && EPOCHREALTIME - cleared > 1 )); then
    # After a clear the bead glides straight down to what is left; only when that takes a while to measure
    # (an app kept running from a big folder) the size on the face — gone now — gives way to "…".
    face=( wait 0 "…" GB ) cleared=0
  fi

  if (( cleaner )) && ! kill -0 $cleaner 2>/dev/null; then
    wait $cleaner 2>/dev/null
    rc=$? cleaner=0
    (( rc == 0 )) && sweep "$swept"          # a clear made while it ran; after a failure, only at the next measure
  fi

  if (( ! measurer && (want || EPOCHREALTIME - measured_at >= period) )) && { (( want )) || visible }; then
    want=0
    start_measuring
  fi

  next="$face"
  if [[ $next != "$drawn" ]]; then
    if post "$(dd_frame $face)"; then
      drawn=$next
    else
      zselect -t 1000                         # the agent is busy or restarting: try again in 10 s
    fi
  fi
  zselect -t 50
done
