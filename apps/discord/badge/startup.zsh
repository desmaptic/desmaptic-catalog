# Discord › Mentions: the badge on Discord's Dock icon — mentions, unread DMs and friend and message requests, or
# Discord's dot for other unread messages — in a neon ring (1×1 SVG face). The startup script is this file (app.json).
#
# The badge comes from lsappinfo, which reads the label Discord put on its Dock icon from Launch Services: no
# permission, no Apple event, nothing Discord notices, and Discord is never launched. Discord (0.0.410, web client
# build 621195) sets that label itself: its number of mentions plus requests, "•" when only other messages are unread
# (unless "Unread Message Badge" is off in its settings), nothing otherwise. Every 3 s while the button is on screen;
# off screen nothing is read, only a look at the phone every 5 s. A frame goes out only when the badge changes.
#
# Every frame has the same 6 elements in the same order: the phone glides between them.
# `zsh startup.zsh --face <rest|off|none|dot|count> [number]` prints one frame (rest.svg and demo.svg are made that way).
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT HUP

# MARK: - Face

# mentions_frame <state> [number]. rest: the ring and "@" (the face before the script runs); off: Discord is not running
# ("—" in a grey ring); none: nothing waits (a calm, dim ring); dot: unread messages but no mentions (a glowing dot,
# Discord's own "•"); count: mentions and requests (the number, the ring red and pink).
mentions_frame() {
  emulate -L zsh
  export LC_ALL=C
  local state=${1:-rest} number=${2:-0} value
  [[ $state == (rest|off|none|dot|count) ]] || state=rest
  [[ $number == <-> ]] || number=0
  (( number > 99 )) && value="99+" || value=$number
  [[ $state == (rest|none|dot) ]] && value="@"  # never an empty <text>: the structure must not change
  [[ $state == off ]] && value="—"
  awk -v st=$state -v val="$value" '
    function f(x) { return sprintf("%.2f", x) }
    BEGIN {
      # ring gradient ends, ring and halo opacity; bloom colour and opacity; dot, its glow; value opacity
      c1 = "#8C95FF"; c2 = "#5865F2"; rO = 0.85; hO = 0.16; gC = "#5865F2"; gA = 0.12
      dR = 0; dO = 0; dgC = "#8C95FF"; dgA = 0; vO = 0.80
      if (st == "off")   { c1 = "#8E8E93"; c2 = "#636366"; rO = 0.55; hO = 0; gC = "#636366"; gA = 0; vO = 0.55 }
      if (st == "none")  { rO = 0.55; hO = 0.08; gA = 0.06; vO = 0.45 }
      if (st == "dot")   { rO = 1; hO = 0.26; gC = "#8C95FF"; gA = 0.18; dR = 16; dO = 1; dgA = 0.65; vO = 0 }
      if (st == "count") { c1 = "#ED4245"; c2 = "#EB459E"; rO = 1; hO = 0.34; gC = "#ED4245"; gA = 0.30; vO = 1 }
      vs = (length(val) >= 3) ? 50 : 68        # "99+" still clears the ring

      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\"><defs>"
      printf "<linearGradient id=\"ringG\" gradientUnits=\"userSpaceOnUse\" x1=\"36\" y1=\"36\" x2=\"164\" y2=\"164\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></linearGradient>", c1, c2
      printf "<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.55\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient>", gC, f(gA), gC, f(gA * 0.35), gC
      printf "<radialGradient id=\"dotG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.45\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient></defs>", dgC, f(dgA), dgC, f(dgA * 0.35), dgC
      printf "<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"92\" fill=\"url(#bloomG)\"/>"
      printf "<circle id=\"halo\" cx=\"100\" cy=\"100\" r=\"64\" fill=\"none\" stroke=\"url(#ringG)\" stroke-opacity=\"%s\" stroke-width=\"18\"/>", f(hO)
      printf "<circle id=\"ring\" cx=\"100\" cy=\"100\" r=\"64\" fill=\"none\" stroke=\"url(#ringG)\" stroke-opacity=\"%s\" stroke-width=\"7\"/>", f(rO)
      printf "<circle id=\"dotGlow\" cx=\"100\" cy=\"100\" r=\"42\" fill=\"url(#dotG)\"/>"
      printf "<circle id=\"dot\" cx=\"100\" cy=\"100\" r=\"%d\" fill=\"#FFFFFF\" fill-opacity=\"%s\"/>", dR, f(dO)
      printf "<text id=\"value\" x=\"100\" y=\"102\" font-size=\"%d\" font-weight=\"700\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"%s\">%s</text>", vs, f(vO), val
      printf "</svg>\n"
    }'
}

if [[ $1 == --face ]]; then
  shift
  mentions_frame "$@"
  exit 0
fi

# MARK: - Badge

# REPLY = off (Discord is not running), none (no badge), dot (Discord's "•": unread messages, no mentions) or
# "count <n>" (mentions and requests). lsappinfo prints nothing for an app that is not running,
# "StatusLabel"=[ NULL ] or { "label"=kCFNULL } or an empty label without a badge, and { "label"="3" } with one.
read_badge() {
  local out label=""
  out=$(lsappinfo info -only StatusLabel -app com.hnc.Discord 2>/dev/null)
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
  else
    REPLY=dot                                   # "•", however lsappinfo spells it
  fi
}

# MARK: - Loop

zmodload zsh/datetime zsh/zselect || { print -u2 -- "Discord mentions: zsh modules datetime/zselect are missing"; exit 1 }

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
  print -ru2 -- "Discord mentions: update-button answered ${code:-nothing}: ${${out%$'\n'*}[1,300]}"
  return 1
}

shown=""                                        # the badge as the phone shows it; "" before the first frame
while true; do
  if visible; then
    read_badge
    if [[ $REPLY != "$shown" ]]; then
      if post "$(mentions_frame ${=REPLY})"; then
        shown=$REPLY
      else
        zselect -t 1000                         # the agent is busy or restarting: try again in 10 s
      fi
    fi
  fi
  zselect -t $(( period * 100 ))
done
