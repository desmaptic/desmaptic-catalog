# Slack › Mentions & DMs: the badge on Slack's Dock icon — the number of mentions and direct messages, or Slack's
# dot for other unread messages — on a neon speech bubble (1×1 SVG face). The startup script is this file (app.json).
#
# The badge comes from lsappinfo, which reads the label Slack put on its Dock icon from Launch Services: no
# permission, no Apple event, nothing Slack notices, and Slack is never launched. Every 3 s while the button is on
# screen; off screen nothing is read, only a look at the phone every 5 s. A frame goes out only when the badge changes.
#
# Every frame has the same 6 elements in the same order: the phone glides between them.
# `zsh startup.zsh --face <rest|off|none|dot|count> [number]` prints one frame (rest.svg and demo.svg are made that way).
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT HUP

# MARK: - Face

# badge_frame <state> [number]. rest: the bubble alone (the face before the script runs); off: Slack is not running
# ("—" in a grey bubble); none: nothing waits (a calm, dim bubble); dot: unread messages but no mentions (a glowing
# dot, Slack's own "•"); count: mentions and direct messages (the number, the bubble hot pink).
badge_frame() {
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
      # bubble gradient ends, bubble and halo opacity; bloom colour and opacity; dot, its glow; value opacity
      c1 = "#64D2FF"; c2 = "#5E5CE6"; bO = 0.85; hO = 0.16; gC = "#5E5CE6"; gA = 0.10
      dR = 0; dO = 0; dgC = "#64D2FF"; dgA = 0; vO = 0
      if (st == "off")   { c1 = "#8E8E93"; c2 = "#636366"; bO = 0.55; hO = 0; gC = "#636366"; gA = 0; vO = 0.55 }
      if (st == "none")  { bO = 0.55; hO = 0.08; gA = 0.06 }
      if (st == "dot")   { c1 = "#64D2FF"; c2 = "#5E5CE6"; bO = 1; hO = 0.26; gC = "#64D2FF"; gA = 0.18
                           dR = 14; dO = 1; dgA = 0.65 }
      if (st == "count") { c1 = "#FF375F"; c2 = "#BF5AF2"; bO = 1; hO = 0.34; gC = "#FF375F"; gA = 0.30; vO = 1 }
      vs = (length(val) >= 3) ? 54 : 68        # "99+" still clears the bubble

      bubble = "d=\"M 58 30 L 142 30 Q 172 30 172 60 L 172 110 Q 172 140 142 140 L 94 140 L 60 168 L 66 140 L 58 140 Q 28 140 28 110 L 28 60 Q 28 30 58 30 Z\""

      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\"><defs>"
      printf "<linearGradient id=\"bubbleG\" gradientUnits=\"userSpaceOnUse\" x1=\"28\" y1=\"30\" x2=\"172\" y2=\"168\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></linearGradient>", c1, c2
      printf "<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.55\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient>", gC, f(gA), gC, f(gA * 0.35), gC
      printf "<radialGradient id=\"dotG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.45\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient></defs>", dgC, f(dgA), dgC, f(dgA * 0.35), dgC
      printf "<circle id=\"bloom\" cx=\"100\" cy=\"92\" r=\"90\" fill=\"url(#bloomG)\"/>"
      printf "<path id=\"halo\" %s fill=\"none\" stroke=\"url(#bubbleG)\" stroke-opacity=\"%s\" stroke-width=\"18\" stroke-linejoin=\"round\"/>", bubble, f(hO)
      printf "<path id=\"bubble\" %s fill=\"none\" stroke=\"url(#bubbleG)\" stroke-opacity=\"%s\" stroke-width=\"7\" stroke-linejoin=\"round\"/>", bubble, f(bO)
      printf "<circle id=\"dotGlow\" cx=\"100\" cy=\"85\" r=\"40\" fill=\"url(#dotG)\"/>"
      printf "<circle id=\"dot\" cx=\"100\" cy=\"85\" r=\"%d\" fill=\"#FFFFFF\" fill-opacity=\"%s\"/>", dR, f(dO)
      printf "<text id=\"value\" x=\"100\" y=\"86\" font-size=\"%d\" font-weight=\"700\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"%s\">%s</text>", vs, f(vO), val
      printf "</svg>\n"
    }'
}

if [[ $1 == --face ]]; then
  shift
  badge_frame "$@"
  exit 0
fi

# MARK: - Badge

# REPLY = off (Slack is not running), none (no badge), dot (Slack's "•": unread messages, no mentions) or
# "count <n>" (mentions and direct messages). lsappinfo prints nothing for an app that is not running,
# "StatusLabel"=[ NULL ] or { "label"=kCFNULL } without a badge, and { "label"="3" } with one.
read_badge() {
  local out label=""
  out=$(lsappinfo info -only StatusLabel -app com.tinyspeck.slackmacgap 2>/dev/null)
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

zmodload zsh/datetime zsh/zselect || { print -u2 -- "Slack badge: zsh modules datetime/zselect are missing"; exit 1 }

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
  print -ru2 -- "Slack badge: update-button answered ${code:-nothing}: ${${out%$'\n'*}[1,300]}"
  return 1
}

shown=""                                        # the badge as the phone shows it; "" before the first frame
while true; do
  if visible; then
    read_badge
    if [[ $REPLY != "$shown" ]]; then
      if post "$(badge_frame ${=REPLY})"; then
        shown=$REPLY
      else
        zselect -t 1000                         # the agent is busy or restarting: try again in 10 s
      fi
    fi
  fi
  zselect -t $(( period * 100 ))
done
