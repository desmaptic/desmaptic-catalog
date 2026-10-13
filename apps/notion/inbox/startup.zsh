# Notion › Inbox: the badge on Notion's Dock icon — the number of unread notifications in its Inbox, from every
# workspace of the account — under a tray (1×1 SVG face). The startup script is this file (app.json).
#
# The badge comes from lsappinfo, which reads the label Notion put on its Dock icon from Launch Services: no permission,
# no Apple event, nothing Notion notices, and Notion is never launched. Notion 7.35.1 sets that label itself (app.asar:
# the window sends "notion:set-badge" and the app calls dock.setBadge, "99+" above 99; its web client of 2026-09-27
# sends the unread Inbox count of every workspace in its switcher, "" when there is none). Every 3 s while the button is
# on screen; off screen nothing is read, only a look at the phone every 5 s. A frame goes out only when the badge
# changes.
#
# Every frame has the same 6 elements in the same order: the phone glides between them.
# `zsh startup.zsh --face <rest|off|none|count> [number]` prints one frame (rest.svg and demo.svg are made that way).
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT HUP

# MARK: - Face

# inbox_frame <state> [number]. rest: the tray alone (the face before the script runs); off: Notion is not running
# (a grey tray over "—"); none: nothing unread (a calm, dim tray); count: unread notifications (the tray moves up and
# the number sits in a red pill below it, as on Notion's own Inbox badge). A label that is not a number shows as "•".
inbox_frame() {
  emulate -L zsh
  export LC_ALL=C
  local state=${1:-rest} number=${2:-0} value
  [[ $state == (rest|off|none|count) ]] || state=rest
  if [[ $number == <-> ]]; then
    (( number > 99 )) && value="99+" || value=$number
  elif [[ $number == "99+" ]]; then
    value="99+"
  else
    value="•"
  fi
  [[ $state == (rest|none) ]] && value="0"      # never an empty <text>: the structure must not change
  [[ $state == off ]] && value="—"
  awk -v st=$state -v val="$value" '
    function f(x) { return sprintf("%.2f", x) }
    BEGIN {
      # tray gradient ends, body and halo opacity, place and scale; bloom colour and opacity;
      # pill width and opacity; value size, colour and opacity
      c1 = "#FFFFFF"; c2 = "#A5A29C"; bO = 0.85; hO = 0.14; ty = 100; sc = 1
      gC = "#FFFFFF"; gA = 0.07; pW = 0; pO = 0; vs = 56; vC = "#FFFFFF"; vO = 0
      if (st == "none")  { bO = 0.50; hO = 0.06; gA = 0.04 }
      if (st == "off")   { c1 = "#8E8E93"; c2 = "#636366"; bO = 0.55; hO = 0; gC = "#636366"; gA = 0
                           ty = 62; sc = 0.78; vO = 0.55 }
      if (st == "count") { bO = 1; hO = 0.24; gC = "#EB5757"; gA = 0.20; ty = 62; sc = 0.78; vO = 1; pO = 1
                           n = (val == "•") ? 1 : length(val); pW = (n <= 1) ? 76 : (n == 2) ? 96 : 132
                           vs = (n <= 2) ? 56 : 50 }
      px = 100 - pW / 2

      tray = "d=\"M -62 2 L -41 -38 Q -38 -44 -31 -44 L 31 -44 Q 38 -44 41 -38 L 62 2 L 62 30 Q 62 44 48 44 L -48 44 Q -62 44 -62 30 Z\""

      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\"><defs>"
      printf "<linearGradient id=\"trayG\" gradientUnits=\"userSpaceOnUse\" x1=\"-62\" y1=\"-44\" x2=\"62\" y2=\"44\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></linearGradient>", c1, c2
      printf "<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.55\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient></defs>", gC, f(gA), gC, f(gA * 0.35), gC
      printf "<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"92\" fill=\"url(#bloomG)\"/>"
      printf "<g id=\"tray\" transform=\"translate(100 %s) scale(%s)\">", f(ty), f(sc)
      printf "<path id=\"halo\" %s fill=\"none\" stroke=\"url(#trayG)\" stroke-opacity=\"%s\" stroke-width=\"18\" stroke-linejoin=\"round\"/>", tray, f(hO)
      printf "<path id=\"body\" %s fill=\"none\" stroke=\"url(#trayG)\" stroke-opacity=\"%s\" stroke-width=\"7\" stroke-linejoin=\"round\"/>", tray, f(bO)
      printf "<path id=\"lip\" d=\"M -60 2 L -26 2 Q -22 18 0 18 Q 22 18 26 2 L 60 2\" fill=\"none\" stroke=\"url(#trayG)\" stroke-opacity=\"%s\" stroke-width=\"7\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/></g>", f(bO)
      printf "<rect id=\"pill\" x=\"%s\" y=\"108\" width=\"%s\" height=\"64\" rx=\"32\" fill=\"#EB5757\" fill-opacity=\"%s\"/>", f(px), f(pW), f(pO)
      printf "<text id=\"value\" x=\"100\" y=\"141\" font-size=\"%d\" font-weight=\"700\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"%s\" fill-opacity=\"%s\">%s</text>", vs, vC, f(vO), val
      printf "</svg>\n"
    }'
}

if [[ $1 == --face ]]; then
  shift
  inbox_frame "$@"
  exit 0
fi

# MARK: - Badge

# REPLY = off (Notion is not running), none (no badge) or "count <n>". lsappinfo prints nothing for an app that is not
# running, "StatusLabel"=[ NULL ] or { "label"=kCFNULL } or an empty label without a badge, and { "label"="3" } with
# one ("99+" above 99).
read_badge() {
  local out label=""
  out=$(lsappinfo info -only StatusLabel -app notion.id 2>/dev/null)
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
  elif [[ $label == "99+" ]]; then
    REPLY="count 99+"
  else
    REPLY="count mark"                          # not a number: shown as "•"
  fi
}

# MARK: - Loop

zmodload zsh/datetime zsh/zselect || { print -u2 -- "Notion inbox: zsh modules datetime/zselect are missing"; exit 1 }

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
  print -ru2 -- "Notion inbox: update-button answered ${code:-nothing}: ${${out%$'\n'*}[1,300]}"
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
