# Device Hub › Simulators: how many simulators run on this Mac, on a neon phone (1×1 SVG face); two phones when more
# than one runs. The startup script is this file (app.json).
#
# A running simulator is one launchd_sim process of this account: CoreSimulator starts one for every simulator it
# boots and ends it at shutdown (checked 2026-09-27: two booted iPhone simulators, two launchd_sim, the same UDIDs as
# `simctl list devices booted`). Only simulators of the default set count — the ones Device Hub shows and
# `simctl shutdown all` (the long press) shuts down — so those of SwiftUI previews (Xcode's own set) and of parallel
# test runs (their clones) do not: their launchd_sim reads its bootstrap from another folder. pgrep reads the process
# table: no permission, no simulator and no app is asked or woken, and Device Hub need not run.
# Every 4 s while the button is on screen, every second for 20 s after the long press (gallery/{{CELL_ID}}/poke);
# off screen nothing is read, only a look at the phone every 5 s. A frame goes out only when the number changes.
#
# Every frame has the same 6 elements in the same order: the phone glides between them.
# `zsh startup.zsh --face <rest|none|count> [number]` prints one frame (rest.svg and demo.svg are made that way).
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT HUP

# MARK: - Face

# simulators_frame <state> [number]. rest: the phone alone (the face before the script runs); none: no simulator runs
# ("0", a calm, dim phone); count: simulators run (the number on a lit phone, a second phone behind it from 2 on).
simulators_frame() {
  emulate -L zsh
  export LC_ALL=C
  local state=${1:-rest} number=${2:-0} value
  [[ $state == (rest|none|count) ]] || state=rest
  [[ $number == <-> ]] || number=0
  (( number > 99 )) && value="99+" || value=$number
  [[ $state == (rest|none) ]] && value=0        # never an empty <text>: the structure must not change
  awk -v st=$state -v val="$value" -v n=$number '
    function f(x) { return sprintf("%.2f", x) }
    BEGIN {
      # gradient ends; front, island, back and halo opacity; halo width; bloom colour and opacity; value opacity
      c1 = "#64D2FF"; c2 = "#0A84FF"; fO = 0.85; iO = 0.60; bO = 0; hO = 0.14; hW = 16; gC = "#0A84FF"; gA = 0.10; vO = 0
      if (st == "none")  { fO = 0.55; iO = 0.35; hO = 0.07; gA = 0.05; vO = 0.60 }
      if (st == "count") { c1 = "#64D2FF"; c2 = "#5E5CE6"; fO = 1; iO = 0.90; hO = 0.32; hW = 20; gC = "#64D2FF"; gA = 0.26
                           vO = 1; bO = (n >= 2) ? 0.60 : 0 }
      vs = (length(val) >= 3) ? 34 : (length(val) == 2) ? 52 : 64   # inside the phone, "99+" too

      back = "M 72 28 Q 72 12 88 12 L 144 12 Q 160 12 160 28 L 160 148 Q 160 164 147 164"

      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\"><defs>"
      printf "<linearGradient id=\"phoneG\" gradientUnits=\"userSpaceOnUse\" x1=\"56\" y1=\"12\" x2=\"160\" y2=\"176\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></linearGradient>", c1, c2
      printf "<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.55\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient></defs>", gC, f(gA), gC, f(gA * 0.35), gC
      printf "<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"92\" fill=\"url(#bloomG)\"/>"
      printf "<path id=\"back\" d=\"%s\" fill=\"none\" stroke=\"url(#phoneG)\" stroke-opacity=\"%s\" stroke-width=\"6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>", back, f(bO)
      printf "<rect id=\"halo\" x=\"56\" y=\"24\" width=\"88\" height=\"152\" rx=\"22\" fill=\"none\" stroke=\"url(#phoneG)\" stroke-opacity=\"%s\" stroke-width=\"%d\"/>", f(hO), hW
      printf "<rect id=\"front\" x=\"56\" y=\"24\" width=\"88\" height=\"152\" rx=\"22\" fill=\"none\" stroke=\"url(#phoneG)\" stroke-opacity=\"%s\" stroke-width=\"7\"/>", f(fO)
      printf "<rect id=\"island\" x=\"85\" y=\"37\" width=\"30\" height=\"9\" rx=\"4.5\" fill=\"url(#phoneG)\" fill-opacity=\"%s\"/>", f(iO)
      printf "<text id=\"value\" x=\"100\" y=\"108\" font-size=\"%d\" font-weight=\"700\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"%s\">%s</text>", vs, f(vO), val
      printf "</svg>\n"
    }'
}

if [[ $1 == --face ]]; then
  shift
  simulators_frame "$@"
  exit 0
fi

# MARK: - What runs

zmodload zsh/datetime zsh/zselect || { print -u2 -- "Simulators: zsh modules datetime/zselect are missing"; exit 1 }

cell="{{CELL_ID}}"
poke_file=""
[[ -n $DESMAPTIC_STORAGE ]] && poke_file="$DESMAPTIC_STORAGE/gallery/$cell/poke"   # the long press: "look now"

told=""
# REPLY = none | "count <n>", or return 1 when the process table could not be read (the face stays as it is).
# The pattern is anchored at the start of the command line: the agent runs a script as `zsh -f -c <its text>`, so
# unanchored it would also match this script, the long press and any other copy of the widget (the text holds it).
read_state() {
  local out rc
  local -a pids
  out=$(pgrep -fU $UID '^(/[^ ]*/)?launchd_sim /.*/Library/Developer/CoreSimulator/Devices/' 2>&1)
  rc=$?
  if (( rc > 1 )); then                         # 1 is "none"; 2 and 3 are errors
    [[ $out != "$told" ]] && { told=$out; print -ru2 -- "Simulators: pgrep failed: ${out[1,200]}" }
    return 1
  fi
  (( rc == 1 )) && out=""
  pids=( ${(f)out} )
  (( $#pids > 0 )) && REPLY="count $#pids" || REPLY=none
}

# MARK: - Loop

api="http://127.0.0.1:9848/api"
period=4                                        # seconds between looks while the button is on screen
closely=20                                      # seconds of a look every second after a poke

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
  print -ru2 -- "Simulators: update-button answered ${code:-nothing}: ${${out%$'\n'*}[1,300]}"
  return 1
}

shown=""                                        # the face as the phone shows it; "" before the first frame
poked=0 closely_until=0 due=0
while true; do
  poke=""
  [[ -n $poke_file && -f $poke_file ]] && IFS= read -r poke < "$poke_file" 2>/dev/null
  if [[ $poke == <-> ]] && (( poke > poked )); then
    poked=$poke closely_until=$(( poke + closely )) due=0
  fi

  if (( EPOCHSECONDS >= due )); then
    if visible; then
      if read_state && [[ $REPLY != "$shown" ]]; then
        if post "$(simulators_frame ${=REPLY})"; then
          shown=$REPLY
        else
          zselect -t 1000                       # the agent is busy or restarting: try again in 10 s
        fi
      fi
      (( EPOCHSECONDS < closely_until )) && due=$(( EPOCHSECONDS + 1 )) || due=$(( EPOCHSECONDS + period ))
    else
      due=$(( EPOCHSECONDS + 1 ))               # visible() itself asks the phone only every 5 s
    fi
  fi
  zselect -t 100
done
