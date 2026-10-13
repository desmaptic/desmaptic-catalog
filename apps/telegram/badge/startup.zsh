# Telegram › Unread: the badge on Telegram's Dock icon — its count of unread messages, or of unread chats, as Telegram's
# Badge Counter setting says — in a neon ring with a paper plane (1×1 SVG face). The startup script is this file (app.json).
#
# The badge comes from lsappinfo, which reads the label Telegram put on its Dock icon from Launch Services: no
# permission, no Apple event, nothing Telegram notices, and Telegram is never launched. Telegram (12.10) sets that label
# itself: a plain number, or nothing when nothing is unread or its badge is off (TelegramSwift 11.15, GlobalBadgeNode:
# dockTile.badgeLabel is the total as digits, nil for 0). Every 3 s while the button is on screen; off screen nothing is
# read, only a look at the phone every 5 s. A frame goes out only when the badge changes.
#
# Every frame has the same 5 elements in the same order: the phone glides between them — with a count, the plane flies
# off to the top right and the number fades in; back to nothing unread, the plane flies home.
# `zsh startup.zsh --face <rest|off|none|count> [number]` prints one frame (rest.svg and demo.svg are made that way).
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT HUP

# MARK: - Face

# unread_frame <state> [number]. rest: the ring and the plane (the face before the script runs); off: Telegram is not
# running ("—" in a grey ring); none: nothing unread (a calm, dim ring with the plane); count: the number, the ring bright.
unread_frame() {
  emulate -L zsh
  export LC_ALL=C
  local state=${1:-rest} number=${2:-0} value
  [[ $state == (rest|off|none|count) ]] || state=rest
  [[ $number == <-> ]] || number=0
  (( number > 999 )) && value="999+" || value=$number
  [[ $state == (rest|none) ]] && value="0"      # never an empty <text>: the structure must not change
  [[ $state == off ]] && value="—"
  awk -v st=$state -v val="$value" '
    function f(x) { return sprintf("%.2f", x) }
    BEGIN {
      # ring gradient ends, ring and halo opacity; bloom colour and opacity; plane opacity and how far it flew;
      # value opacity
      c1 = "#7AD7FF"; c2 = "#229ED9"; rO = 0.85; hO = 0.16; gC = "#2AABEE"; gA = 0.12
      pO = 0.95; pX = 0; pY = 0; vO = 0
      if (st == "off")   { c1 = "#8E8E93"; c2 = "#636366"; rO = 0.55; hO = 0; gC = "#636366"; gA = 0
                           pO = 0; pX = 44; pY = -36; vO = 0.55 }
      if (st == "none")  { rO = 0.55; hO = 0.08; gA = 0.06; pO = 0.55 }
      if (st == "count") { c1 = "#A6E6FF"; c2 = "#2AABEE"; rO = 1; hO = 0.34; gC = "#2AABEE"; gA = 0.32
                           pO = 0; pX = 44; pY = -36; vO = 1 }
      n = length(val)
      vs = (n >= 4) ? 36 : (n == 3) ? 50 : 68   # "999+" still clears the ring

      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\"><defs>"
      printf "<linearGradient id=\"ringG\" gradientUnits=\"userSpaceOnUse\" x1=\"36\" y1=\"36\" x2=\"164\" y2=\"164\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></linearGradient>", c1, c2
      printf "<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.55\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient></defs>", gC, f(gA), gC, f(gA * 0.35), gC
      printf "<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"92\" fill=\"url(#bloomG)\"/>"
      printf "<circle id=\"halo\" cx=\"100\" cy=\"100\" r=\"64\" fill=\"none\" stroke=\"url(#ringG)\" stroke-opacity=\"%s\" stroke-width=\"18\"/>", f(hO)
      printf "<circle id=\"ring\" cx=\"100\" cy=\"100\" r=\"64\" fill=\"none\" stroke=\"url(#ringG)\" stroke-opacity=\"%s\" stroke-width=\"7\"/>", f(rO)
      # the plane, drawn around (100 100), flies off by (pX pY) the way it points
      printf "<path id=\"plane\" transform=\"translate(%s %s)\" d=\"M 138 64 L 56 97 L 88 110 L 104 142 Z M 138 64 L 88 110\" fill=\"none\" stroke=\"#FFFFFF\" stroke-opacity=\"%s\" stroke-width=\"7\" stroke-linejoin=\"round\" stroke-linecap=\"round\"/>", f(pX), f(pY), f(pO)
      printf "<text id=\"value\" x=\"100\" y=\"102\" font-size=\"%d\" font-weight=\"700\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"%s\">%s</text>", vs, f(vO), val
      printf "</svg>\n"
    }'
}

if [[ $1 == --face ]]; then
  shift
  unread_frame "$@"
  exit 0
fi

# MARK: - Badge

# REPLY = off (Telegram is not running), none (no badge) or "count <n>". lsappinfo prints nothing for an app that is
# not running, "StatusLabel"=[ NULL ] or { "label"=kCFNULL } or an empty label without a badge, and { "label"="3" } with
# one. Telegram writes digits only; anything else is read as no badge rather than guessed at.
read_badge() {
  local out label=""
  out=$(lsappinfo info -only StatusLabel -app ru.keepcoder.Telegram 2>/dev/null)
  if [[ -z $out ]]; then
    REPLY=off
    return
  fi
  if [[ $out == *'"label"="'* ]]; then
    label=${out#*\"label\"=\"}
    label=${label%%\"*}
  fi
  if [[ $label == <-> ]] && (( label > 0 )); then
    REPLY="count $label"
  else
    REPLY=none
  fi
}

# MARK: - Loop

zmodload zsh/datetime zsh/zselect || { print -u2 -- "Telegram unread: zsh modules datetime/zselect are missing"; exit 1 }

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
  print -ru2 -- "Telegram unread: update-button answered ${code:-nothing}: ${${out%$'\n'*}[1,300]}"
  return 1
}

shown=""                                        # the badge as the phone shows it; "" before the first frame
while true; do
  if visible; then
    read_badge
    if [[ $REPLY != "$shown" ]]; then
      if post "$(unread_frame ${=REPLY})"; then
        shown=$REPLY
      else
        zselect -t 1000                         # the agent is busy or restarting: try again in 10 s
      fi
    fi
  fi
  zselect -t $(( period * 100 ))
done
