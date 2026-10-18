# GitHub notifications › startup: how many unread notifications wait on GitHub, under a bell (1×1 SVG face). After
# gh.zsh (item.json): "@file:gh.zsh\n@file:startup.zsh"; the tap opens github.com/notifications.
#
# One look is `gh api -i notifications?per_page=50 --jq length`: GitHub's headers and the number of unread
# notifications on the first page, never their titles or repositories, and nothing of the answer goes to the log.
# More than one page shows "50+". GitHub names in X-Poll-Interval how often it may be asked (60 s as a rule): the loop
# never looks sooner, and only while the button is on screen; off screen it only asks the phone every 5 s. The time of
# the next look and the last count are kept in gallery/{{CELL_ID}}/look, so a restart does not ask sooner either.
#
# Without gh, or with gh signed out or not allowed to read notifications, the bell turns grey with "—" and the phone
# says what to do (/api/error). Any other failure keeps the last count and its reason goes to the phone; after
# 15 minutes without an answer the count is grey "—" as well, so it never passes for a current one.
#
# The long press (read.zsh) only writes files in gallery/{{CELL_ID}}/: armed (the first hold, its time), marking
# (the second one runs) and marked (GitHub took it). This loop draws them: a green bell with a ring that runs out in
# 10 s, then "0" once all is read.
#
# Every frame has the same 10 elements in the same order: the bell glides between them.
# `zsh startup.zsh --face <rest|none|count|problem|armed> [value] [ring]` prints one frame (rest.svg and demo.svg are
# made that way).

# MARK: - Face

# bell_frame <state> [value] [ring]. rest: the bell alone, large (the face before the script runs); none: nothing
# unread ("0" under a calm, dim bell); count: notifications wait (the number under a lit bell with a red dot);
# problem: the count cannot be had (a grey bell over "—"); armed: the first hold waits for the second (a green bell
# over "✓", the ring around the button holds what is left of the 10 s, 0…1). In the other states the ring is hidden
# where it stands (1, whole, unless given): a frame that hides it must not move it, or the phone glides it while it
# still shows; the next arming fills it from there.
bell_frame() {
  emulate -L zsh
  export LC_ALL=C
  local state=${1:-rest} value=${2:-0} ring=$3
  [[ $state == (rest|none|count|problem|armed) ]] || state=rest
  [[ $value == (<->|50+) ]] || value=0
  [[ -z $ring && $state != armed ]] && ring=1
  [[ $ring == (<->|<->.<->|.<->) ]] || ring=0
  [[ $state == (rest|none) ]] && value=0        # never an empty <text>: the structure must not change
  [[ $state == problem ]] && value="—"
  [[ $state == armed ]] && value="✓"
  awk -v st=$state -v val="$value" -v ring=$ring '
    function f(x) { return sprintf("%.2f", x) }
    BEGIN {
      # gradient ends; bell opacity; bloom colour and opacity; dot opacity; value colour, opacity and size;
      # bell placement and scale; the ring: its length (552.92) and how much of it shows
      c1 = "#64D2FF"; c2 = "#0A84FF"; gO = 0.90; gC = "#0A84FF"; gA = 0.12; dO = 0; vC = "#FFFFFF"; vO = 0; vs = 60
      tx = 50; ty = 50; sc = 1; len = 552.92; rO = 0
      if (ring < 0) ring = 0
      if (ring > 1) ring = 1
      if (st != "rest")    { tx = 65; ty = 22; sc = 0.70 }
      if (st == "none")    { gO = 0.50; gA = 0.05; vO = 0.60 }
      if (st == "count")   { c2 = "#5E5CE6"; gO = 1; gC = "#5E5CE6"; gA = 0.30; dO = 1; vO = 1
                             if (val == "50+") vs = 48 }
      if (st == "problem") { c1 = "#8E8E93"; c2 = "#636366"; gO = 0.70; gC = "#8E8E93"; gA = 0.04; vO = 0.60 }
      if (st == "armed")   { c1 = "#7EE787"; c2 = "#30D158"; gO = 1; gC = "#30D158"; gA = 0.28; vC = "#30D158"; vO = 1
                             rO = 1 }

      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\"><defs>"
      printf "<linearGradient id=\"bellG\" gradientUnits=\"userSpaceOnUse\" x1=\"10\" y1=\"5\" x2=\"90\" y2=\"95\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></linearGradient>", c1, c2
      printf "<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.55\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient></defs>", gC, f(gA), gC, f(gA * 0.35), gC
      printf "<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"92\" fill=\"url(#bloomG)\"/>"
      # the ring around the button: what is left of the 10 s to confirm, from the top, clockwise
      printf "<circle id=\"ring\" cx=\"100\" cy=\"100\" r=\"88\" fill=\"none\" stroke=\"#30D158\" stroke-width=\"6\" stroke-dasharray=\"%s %s\" stroke-dashoffset=\"%s\" opacity=\"%s\" transform=\"rotate(-90 100 100)\"/>", f(len), f(len), f(len * (1 - ring)), f(rO)
      # the bell, drawn in a 100×100 box: its body, the knob on top, the clapper below; a red dot when something waits
      printf "<g id=\"glyph\" transform=\"translate(%s %s) scale(%s)\" fill=\"none\" stroke=\"url(#bellG)\" stroke-opacity=\"%s\" stroke-width=\"8\" stroke-linecap=\"round\" stroke-linejoin=\"round\">", f(tx), f(ty), f(sc), f(gO)
      printf "<path id=\"body\" d=\"M 24 72 L 24 48 Q 24 20 50 20 Q 76 20 76 48 L 76 72 L 84 80 L 16 80 Z\"/>"
      printf "<path id=\"knob\" d=\"M 50 20 L 50 11\"/>"
      printf "<path id=\"clapper\" d=\"M 41 88 Q 50 97 59 88\"/>"
      printf "<circle id=\"dot\" cx=\"80\" cy=\"20\" r=\"13\" fill=\"#FF375F\" stroke=\"none\" opacity=\"%s\"/>", f(dO)
      printf "</g>"
      printf "<text id=\"value\" x=\"100\" y=\"148\" font-size=\"%d\" font-weight=\"700\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"%s\" opacity=\"%s\">%s</text>", vs, vC, f(vO), val
      printf "</svg>\n"
    }'
}

if [[ $1 == --face ]]; then
  shift
  bell_frame "$@"
  exit 0
fi

# MARK: - Looking

stale=900                                       # seconds after the last count when a hitch greys it out
retry=60                                        # seconds before the next look when GitHub named no interval

told=""
tell() {   # logs a reason once, not on every look
  [[ $1 == "$told" ]] && return
  told=$1
  print -ru2 -- "GitHub notifications: $1"
}

# report <kind> <message> | report clear: tells the phone why the count cannot be had, on a change; clear once it
# can again. Remembered only when the agent took it (200), so a refused one is posted again at the next look.
said=""                                         # "<kind> <message>" the phone was told last; "" when all is well
report() {
  local want="" json
  [[ $1 == clear ]] || want="$1 $2"
  [[ $want == "$said" ]] && return 0
  if [[ -z $want ]]; then
    json="{\"cellId\":\"$cell\",\"clear\":true}"
  else
    json=$(jq -nc --arg c "$cell" --arg k "$1" --arg m "$2" '{cellId: $c, kind: $k, message: $m}')
  fi
  [[ $(call error "$json") == 200 ]] && said=$want
  return 0
}

# keep <name> <text>: writes a state file of this button, or removes it for an empty text.
keep() {
  [[ -n $own ]] || return 0
  if [[ -z $2 ]]; then
    zf_rm -f "$own/$1" 2>/dev/null
  else
    zf_mkdir -p "$own" 2>/dev/null
    print -r -- "$2" > "$own/$1" 2>/dev/null
  fi
  return 0
}

# look: REPLY = the face — none, "count <n>", "count 50+", problem, or keep (a passing hitch: the face stays);
# interval = the seconds GitHub asks to wait before the next look.
good=0                                          # when the last count came
interval=$retry
look() {
  local rc n line name next=0 lasting
  local -a lines
  if ! gh_found; then
    trouble ${REPLY%% *} "${REPLY#* }"
    return
  fi
  gh_api 30 -i 'notifications?per_page=50' --jq length
  rc=$?
  if (( rc != 0 )); then
    gh_refusal $rc "GitHub didn’t give the count"
    lasting=${REPLY%% *}; REPLY=${REPLY#* }
    if (( lasting )); then trouble ${REPLY%% *} "${REPLY#* }"; else hitch ${REPLY%% *} "${REPLY#* }"; fi
    return
  fi
  # The answer: the status line, the headers, an empty line, then the count alone on the last line.
  lines=( "${(@f)${$(<$tmp/out)//$'\r'/}}" )
  n=${lines[-1]}
  if [[ $n != <-> ]]; then hitch other "GitHub didn’t give the count."; return; fi
  for line in $lines[1,-2]; do
    name=${(L)line%%:*}
    case $name in
      x-poll-interval) [[ ${${line#*:}##[[:space:]]#} == (#b)(<->)* ]] && interval=$match[1] ;;
      link)            [[ $line == *'rel="next"'* ]] && next=1 ;;
    esac
  done
  (( interval < 60 )) && interval=60
  (( interval > 3600 )) && interval=3600
  told=""
  report clear
  keep problem ""
  good=$EPOCHSECONDS
  if (( next )); then REPLY="count 50+"
  elif (( n > 0 )); then REPLY="count $n"
  else REPLY=none
  fi
}

# trouble <kind> <message>: the count cannot be had until the user acts — a grey "—", the reason to the phone and
# to the long press (gallery/{{CELL_ID}}/problem), which then says it instead of arming.
trouble() {
  tell "$2"
  report $1 "$2"
  keep problem "$1 $2"
  REPLY=problem
}

# hitch <kind> <message>: out of the user's hands for now — the reason to the phone, the last count stays until it
# is $stale seconds old.
hitch() {
  tell "$2"
  report $1 "$2"
  keep problem ""
  if (( EPOCHSECONDS - good > stale )); then REPLY=problem; else REPLY=keep; fi
}

# MARK: - Drawing

hidden=0 asked=0
visible() {   # does the phone show the button (or is it too old to say)? Asks at most every 5 s while it does not.
  local out code body
  (( hidden && EPOCHSECONDS - asked < 5 )) && return 1
  asked=$EPOCHSECONDS
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/view" --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}') || { hidden=1; return 1 }
  code=${out##*$'\n'} body=${(L)${out%$'\n'*}//[[:space:]]/}
  if [[ $code != 200 || $body == *'"view":null'* || $body == *${(L)cell}* ]]; then
    hidden=0
  else
    hidden=1
  fi
  (( ! hidden ))
}

refused=""                                      # why update-button refused the last frame: logged once, not on every try
post() {   # post <seconds> <easing> <state> [value] [ring] → 0 when the agent took the frame
  local seconds=$1 easing=$2 p out code
  shift 2
  p=$(bell_frame "$@")
  p=${p//\\/\\\\}; p=${p//\"/\\\"}; p=${p//$'\n'/}
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' -H "Content-Type: application/json" \
    -d "{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$p\",\"duration\":$seconds,\"easing\":\"$easing\"}}")
  code=${out##*$'\n'}
  if [[ $code == 200 ]]; then refused=""; return 0; fi
  out="${code:-nothing}: ${${out%$'\n'*}[1,300]}"
  [[ $out == "$refused" ]] || print -ru2 -- "GitHub notifications: update-button answered $out"
  refused=$out
  return 1
}

# MARK: - Loop

# What the last run knew: when it may look again, when its count came and what it was.
face=rest due=0
if [[ -n $own && -f $own/look ]]; then
  IFS=' ' read -r d g f < "$own/look" 2>/dev/null
  if [[ $d == <-> && $g == <-> ]]; then
    (( d > EPOCHSECONDS && d - EPOCHSECONDS <= 3600 )) && due=$d
    if [[ $f == (none|count\ (<->|50+)) ]] && (( EPOCHSECONDS - g <= stale )); then face=$f good=$g; fi
  fi
fi
stamp marked; marked=$REPLY                     # a mark the last run already drew is not new

shown=""                                        # what the phone was sent last: the face, or armed/marking
ring=1                                          # where the ring stands on the phone (it stays there while hidden)
failed="" again=0                               # the frame update-button refused last, and when to offer it again
while true; do
  now=$EPOCHREALTIME
  stamp armed;   armed=$REPLY
  stamp marking; marking=$REPLY
  stamp marked
  if (( REPLY > marked )); then                 # GitHub took "mark all read": nothing is unread now
    marked=$REPLY
    (( REPLY >= good )) && face=none
  fi
  if (( marking > 0 && now - marking < 40 )); then
    want=marking
  elif (( armed > 0 && now - armed < confirm )); then
    want="armed $armed"
  else
    want=$face
  fi

  if (( EPOCHSECONDS >= due )) && [[ $want == $face ]]; then
    if visible; then
      look
      [[ $REPLY != keep ]] && face=$REPLY
      due=$(( EPOCHSECONDS + interval ))
      keep look "$due $good $face"
      want=$face shown=""                       # every look sends its face, changed or not
    else
      due=$(( EPOCHSECONDS + 1 ))               # visible() itself asks the phone only every 5 s
    fi
  fi

  # A frame the agent refused (no phone, the agent restarting) is offered again only after 30 s, unless the button
  # wants another one meanwhile: a hold still shows at once.
  if [[ $want != $shown ]] && { [[ $want != $failed ]] || (( EPOCHSECONDS >= again )) }; then
    case $want in
      armed\ *)                                 # fill the ring, then let it run out over what is left of the 10 s
        if post 0.3 easeInOut armed 0 1; then
          ring=1
          zselect -t 30
          printf -v left '%.2f' $(( confirm - (EPOCHREALTIME - armed) ))
          (( left < 0.1 )) && left=0.10
          post $left linear armed 0 0 && ring=0
          shown=$want
        fi ;;
      marking)
        post 0.3 easeInOut armed 0 1 && ring=1 shown=$want ;;
      *)                                        # the ring fades out where it stands
        parts=( ${=want} )
        post 0.6 easeInOut $parts[1] ${parts[2]:-0} $ring && shown=$want ;;
    esac
    if [[ $want == $shown ]]; then failed=""; else failed=$want again=$(( EPOCHSECONDS + 30 )); fi
  fi
  zselect -t 25
done
