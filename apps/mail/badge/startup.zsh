# Mail › Unread: the badge on Mail's Dock icon — the number of unread messages Mail counts there (the Inbox, unless
# Mail's settings count another mailbox) — under a neon envelope (1×1 SVG face). The startup script is this file
# (app.json).
#
# The badge comes from lsappinfo, which reads the label Mail put on its Dock icon from Launch Services: no permission,
# no Apple event, nothing Mail notices, and Mail is never launched (a launched Mail would fetch mail). Every 3 s while
# the button is on screen; off screen nothing is read, only a look at the phone every 5 s. A frame goes out only when
# the badge changes.
#
# Every frame has the same 6 elements in the same order: the phone glides between them.
# `zsh startup.zsh --face <rest|off|none|count> [number]` prints one frame (rest.svg and demo.svg are made that way).
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT HUP

# MARK: - Face

# unread_frame <state> [number]. rest: the envelope alone (the face before the script runs); off: Mail is not running
# (a grey envelope over "—"); none: nothing unread (a calm, dim envelope); count: unread messages (the envelope moves up
# and the number sits in a red pill below it, as on Mail's Dock icon).
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
      # envelope gradient ends, body and halo opacity, place and scale; bloom colour and opacity;
      # pill width and opacity; value size, colour and opacity
      c1 = "#64D2FF"; c2 = "#0A84FF"; bO = 0.85; hO = 0.16; ty = 100; sc = 1
      gC = "#0A84FF"; gA = 0.10; pW = 0; pO = 0; vs = 56; vC = "#FFFFFF"; vO = 0
      if (st == "none")  { bO = 0.55; hO = 0.08; gA = 0.06 }
      if (st == "off")   { c1 = "#8E8E93"; c2 = "#636366"; bO = 0.55; hO = 0; gC = "#636366"; gA = 0
                           ty = 62; sc = 0.78; vO = 0.55 }
      if (st == "count") { bO = 1; hO = 0.30; gA = 0.22; ty = 62; sc = 0.78; vO = 1; pO = 1
                           n = length(val); pW = (n <= 1) ? 76 : (n == 2) ? 96 : (n == 3) ? 118 : 142
                           vs = (n <= 3) ? 56 : 46 }
      px = 100 - pW / 2

      body = "x=\"-62\" y=\"-44\" width=\"124\" height=\"88\" rx=\"16\""

      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\"><defs>"
      printf "<linearGradient id=\"envG\" gradientUnits=\"userSpaceOnUse\" x1=\"-62\" y1=\"-44\" x2=\"62\" y2=\"44\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></linearGradient>", c1, c2
      printf "<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.55\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient></defs>", gC, f(gA), gC, f(gA * 0.35), gC
      printf "<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"92\" fill=\"url(#bloomG)\"/>"
      printf "<g id=\"envelope\" transform=\"translate(100 %s) scale(%s)\">", f(ty), f(sc)
      printf "<rect id=\"halo\" %s fill=\"none\" stroke=\"url(#envG)\" stroke-opacity=\"%s\" stroke-width=\"18\"/>", body, f(hO)
      printf "<rect id=\"body\" %s fill=\"none\" stroke=\"url(#envG)\" stroke-opacity=\"%s\" stroke-width=\"7\"/>", body, f(bO)
      printf "<path id=\"flap\" d=\"M -50 -30 L 0 8 L 50 -30\" fill=\"none\" stroke=\"url(#envG)\" stroke-opacity=\"%s\" stroke-width=\"7\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/></g>", f(bO)
      printf "<rect id=\"pill\" x=\"%s\" y=\"108\" width=\"%s\" height=\"64\" rx=\"32\" fill=\"#FF3B30\" fill-opacity=\"%s\"/>", f(px), f(pW), f(pO)
      printf "<text id=\"value\" x=\"100\" y=\"141\" font-size=\"%d\" font-weight=\"700\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"%s\" fill-opacity=\"%s\">%s</text>", vs, vC, f(vO), val
      printf "</svg>\n"
    }'
}

if [[ $1 == --face ]]; then
  shift
  unread_frame "$@"
  exit 0
fi

# MARK: - Badge

# REPLY = off (Mail is not running), none (no badge) or "count <n>". lsappinfo prints nothing for an app that is not
# running, "StatusLabel"=[ NULL ] or { "label"=kCFNULL } without a badge, and { "label"="3" } with one. Mail counts
# with an integer; should it group the digits the Mac's way ("1.234", "1 234" with a no-break space), the separators
# are dropped. Anything else is read as no badge.
read_badge() {
  local out label=""
  out=$(lsappinfo info -only StatusLabel -app com.apple.mail 2>/dev/null)
  if [[ -z $out ]]; then
    REPLY=off
    return
  fi
  if [[ $out == *'"label"="'* ]]; then
    label=${out#*\"label\"=\"}
    label=${label%%\"*}
  fi
  label=${label//($'\xc2\xa0'|$'\xe2\x80\xaf'|[,.\' ])/}   # group separators: , . ' space, no-break and narrow no-break space
  if [[ $label == <-> ]] && (( label > 0 )); then
    REPLY="count $label"
  else
    REPLY=none
  fi
}

# MARK: - Loop

zmodload zsh/datetime zsh/zselect || { print -u2 -- "Mail unread: zsh modules datetime/zselect are missing"; exit 1 }

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
  print -ru2 -- "Mail unread: update-button answered ${code:-nothing}: ${${out%$'\n'*}[1,300]}"
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
