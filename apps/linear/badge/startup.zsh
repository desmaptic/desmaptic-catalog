# Linear › Inbox: the badge on Linear's Dock icon — its dot for unread Inbox notifications, or their number — on a neon
# inbox tray (1×1 SVG face). The startup script is this file (app.json).
#
# The badge comes from lsappinfo, which reads the label Linear put on its Dock icon from Launch Services: no permission,
# no Apple event, nothing Linear notices, and Linear is never launched. Linear (1.32.4, web client of 2026-09-27) sets
# that label itself from its unread Inbox notifications and its Preferences › App notification badge: "•" with Unread
# indicator (the default), the number ("99+" above 99) with Unread count, nothing with Off or when all is read. Every 3 s
# while the button is on screen; off screen nothing is read, only a look at the phone every 5 s. A frame goes out only
# when the badge changes.
#
# Every frame has the same 6 elements in the same order: the phone glides between them.
# `zsh startup.zsh --face <rest|off|none|dot|count> [number]` prints one frame (rest.svg and demo.svg are made that way).
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT HUP

# MARK: - Face

# inbox_frame <state> [number]. rest: the tray alone (the face before the script runs); off: Linear is not running
# ("—" in a grey tray); none: nothing unread (a calm, dim tray); dot: unread notifications, Linear's own "•" (a glowing
# dot in the tray); count: their number (the tray orange and red).
inbox_frame() {
  emulate -L zsh
  export LC_ALL=C
  local state=${1:-rest} number=${2:-0} value
  [[ $state == (rest|off|none|dot|count) ]] || state=rest
  [[ $number == <-> ]] || number=0
  (( number > 99 )) && value="99+" || value=$number
  [[ $state == off ]] && value="—"             # never an empty <text>: the structure must not change
  awk -v st=$state -v val="$value" '
    function f(x) { return sprintf("%.2f", x) }
    BEGIN {
      # tray gradient ends, tray and halo opacity; bloom colour and opacity; dot, its glow; value opacity
      c1 = "#A5ADFF"; c2 = "#5E6AD2"; tO = 0.85; hO = 0.16; gC = "#5E6AD2"; gA = 0.12
      dR = 0; dO = 0; dgC = "#A5ADFF"; dgA = 0; vO = 0
      if (st == "off")   { c1 = "#8E8E93"; c2 = "#636366"; tO = 0.55; hO = 0; gC = "#636366"; gA = 0; vO = 0.55 }
      if (st == "none")  { tO = 0.55; hO = 0.08; gA = 0.06 }
      if (st == "dot")   { tO = 1; hO = 0.26; gC = "#A5ADFF"; gA = 0.18; dR = 14; dO = 1; dgA = 0.65 }
      if (st == "count") { c1 = "#F2994A"; c2 = "#EB5757"; tO = 1; hO = 0.34; gC = "#EB5757"; gA = 0.30; vO = 1 }
      vs = (length(val) >= 3) ? 34 : (length(val) == 2) ? 44 : 54   # two digits and "99+" clear the sloping walls
      if (st == "off") vs = 44                  # "—" is one character but 3 bytes, and length() counts bytes here

      # The tray: its outline, then the notch of its opening (an open line).
      tray = "d=\"M 44 104 L 62 54 Q 67 40 82 40 L 118 40 Q 133 40 138 54 L 156 104 L 156 146 Q 156 162 140 162 L 60 162 Q 44 162 44 146 Z M 44 104 L 78 104 Q 83 104 85 110 L 88 118 Q 90 124 97 124 L 103 124 Q 110 124 112 118 L 115 110 Q 117 104 122 104 L 156 104\""

      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\"><defs>"
      printf "<linearGradient id=\"trayG\" gradientUnits=\"userSpaceOnUse\" x1=\"44\" y1=\"40\" x2=\"156\" y2=\"162\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></linearGradient>", c1, c2
      printf "<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.55\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient>", gC, f(gA), gC, f(gA * 0.35), gC
      printf "<radialGradient id=\"dotG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.45\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient></defs>", dgC, f(dgA), dgC, f(dgA * 0.35), dgC
      printf "<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"92\" fill=\"url(#bloomG)\"/>"
      printf "<path id=\"halo\" %s fill=\"none\" stroke=\"url(#trayG)\" stroke-opacity=\"%s\" stroke-width=\"18\" stroke-linejoin=\"round\" stroke-linecap=\"round\"/>", tray, f(hO)
      printf "<path id=\"tray\" %s fill=\"none\" stroke=\"url(#trayG)\" stroke-opacity=\"%s\" stroke-width=\"7\" stroke-linejoin=\"round\" stroke-linecap=\"round\"/>", tray, f(tO)
      printf "<circle id=\"dotGlow\" cx=\"100\" cy=\"74\" r=\"38\" fill=\"url(#dotG)\"/>"
      printf "<circle id=\"dot\" cx=\"100\" cy=\"74\" r=\"%d\" fill=\"#FFFFFF\" fill-opacity=\"%s\"/>", dR, f(dO)
      printf "<text id=\"value\" x=\"100\" y=\"76\" font-size=\"%d\" font-weight=\"700\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"%s\">%s</text>", vs, f(vO), val
      printf "</svg>\n"
    }'
}

if [[ $1 == --face ]]; then
  shift
  inbox_frame "$@"
  exit 0
fi

# MARK: - Badge

# REPLY = off (Linear is not running), none (no badge), dot (Linear's "•") or "count <n>" (unread notifications; "99+" is
# read as 100). lsappinfo prints nothing for an app that is not running, "StatusLabel"=[ NULL ] or { "label"=kCFNULL }
# or an empty label without a badge, and { "label"="3" } with one.
read_badge() {
  local out label=""
  out=$(lsappinfo info -only StatusLabel -app com.linear 2>/dev/null)
  if [[ -z $out ]]; then
    REPLY=off
    return
  fi
  if [[ $out == *'"label"="'* ]]; then
    label=${out#*\"label\"=\"}
    label=${label%%\"*}
  fi
  if [[ -z $label ]]; then
    REPLY=none
  elif [[ $label == <-> ]]; then
    if (( label > 0 )); then REPLY="count $label"; else REPLY=none; fi
  elif [[ $label == <->+ ]]; then
    REPLY="count 100"                           # "99+"
  else
    REPLY=dot                                   # "•", however lsappinfo spells it
  fi
}

# MARK: - Loop

zmodload zsh/datetime zsh/zselect || { print -u2 -- "Linear inbox: zsh modules datetime/zselect are missing"; exit 1 }

api="http://127.0.0.1:9848/api"
cell="{{CELL_ID}}"
period=3                                        # seconds between looks at the badge while the button is on screen

hidden=0 looked=0
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

post() {   # $1 frame → 0 when the agent took it
  local p=$1 out code
  p=${p//\\/\\\\}; p=${p//\"/\\\"}; p=${p//$'\n'/}
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' -H "Content-Type: application/json" \
    -d "{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$p\",\"duration\":0.6}}")
  code=${out##*$'\n'}
  [[ $code == 200 ]] && return 0
  print -ru2 -- "Linear inbox: update-button answered ${code:-nothing}: ${${out%$'\n'*}[1,300]}"
  return 1
}

shown=""                                        # the badge as the phone shows it; "" before the first frame
while true; do
  if visible; then
    read_badge
    if [[ $REPLY != "$shown" ]]; then
      if post "$(inbox_frame ${=REPLY})"; then
        shown=$REPLY
      else
        zselect -t 1000                         # the agent is busy or restarting: try again in 10 s
      fi
    fi
  fi
  zselect -t $(( period * 100 ))
done
