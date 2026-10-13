# Docker Desktop › Containers: how many containers run, on a neon stack of shipping containers (1×1 SVG face). The
# startup script is cli.zsh and then this file (app.json).
#
# Docker Desktop's engine is asked (`docker ps`, on its own socket) only while its Linux VM runs: without the VM no
# container runs, and a question to the engine then could wake a VM that Resource Saver stopped. So: "—" without
# Docker Desktop, 0 while its VM is stopped or runs nothing, "…" while the engine does not answer yet, else the number.
# Every 5 s while the button is on screen, every second for 90 s after a tap on the page's Start or a long press here
# (gallery/docker/poke); off screen nothing is read, only a look at the phone every 5 s. Docker Desktop is never
# launched. A frame goes out only when the face changes.
#
# Every frame has the same 6 elements in the same order: the phone glides between them.
# `zsh startup.zsh --face <rest|off|idle|wait|count> [number]` prints one frame (rest.svg and demo.svg are made that way).
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
asker=0
trap '(( asker )) && kill $asker 2>/dev/null; exit 0' TERM INT HUP

# MARK: - Face

# containers_frame <state> [number]. rest: the containers alone (the face before the script runs); off: Docker Desktop
# is not running ("—", grey); idle: nothing runs ("0", calm and dim); wait: the engine does not answer yet ("…");
# count: containers run (the number, the containers lit).
containers_frame() {
  emulate -L zsh
  export LC_ALL=C
  local state=${1:-rest} number=${2:-0} value
  [[ $state == (rest|off|idle|wait|count) ]] || state=rest
  [[ $number == <-> ]] || number=0
  (( number > 99 )) && value="99+" || value=$number
  [[ $state == (rest|idle) ]] && value=0
  [[ $state == off ]] && value="—"             # never an empty <text>: the structure must not change
  [[ $state == wait ]] && value="…"
  awk -v st=$state -v val="$value" '
    function f(x) { return sprintf("%.2f", x) }
    BEGIN {
      # gradient ends; front, back and ridge opacity; halo opacity and width; bloom colour and opacity; value opacity
      c1 = "#64D2FF"; c2 = "#0A84FF"; fO = 0.85; bO = 0.45; rO = 0.55; hO = 0.14; hW = 16; gC = "#0A84FF"; gA = 0.10; vO = 0
      if (st == "off")   { c1 = "#8E8E93"; c2 = "#636366"; fO = 0.55; bO = 0.28; rO = 0.30; hO = 0; gC = "#636366"; gA = 0; vO = 0.55 }
      if (st == "idle")  { fO = 0.55; bO = 0.26; rO = 0.32; hO = 0.07; gA = 0.05; vO = 0.60 }
      if (st == "wait")  { fO = 0.70; bO = 0.34; rO = 0.40; hO = 0.10; gA = 0.07; vO = 0.55 }
      if (st == "count") { c1 = "#64D2FF"; c2 = "#5E5CE6"; fO = 1; bO = 0.80; rO = 0.85; hO = 0.32; hW = 20; gC = "#64D2FF"; gA = 0.26; vO = 1 }
      vs = (length(val) >= 3) ? 44 : 64        # "99+" clears the ridges
      vy = (st == "wait") ? 93 : 107           # "…" sits on the baseline: raised to the middle

      front = "M 34 62 L 154 62 Q 166 62 166 74 L 166 138 Q 166 150 154 150 L 34 150 Q 22 150 22 138 L 22 74 Q 22 62 34 62 Z"
      back  = "M 34 62 Q 34 50 46 50 L 166 50 Q 178 50 178 62 L 178 126 Q 178 138 166 138"
      ridge = "M 34 78 L 34 134 M 44 78 L 44 134 M 144 78 L 144 134 M 154 78 L 154 134"

      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\"><defs>"
      printf "<linearGradient id=\"boxG\" gradientUnits=\"userSpaceOnUse\" x1=\"22\" y1=\"50\" x2=\"178\" y2=\"150\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></linearGradient>", c1, c2
      printf "<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.55\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient></defs>", gC, f(gA), gC, f(gA * 0.35), gC
      printf "<circle id=\"bloom\" cx=\"96\" cy=\"104\" r=\"90\" fill=\"url(#bloomG)\"/>"
      printf "<path id=\"back\" d=\"%s\" fill=\"none\" stroke=\"url(#boxG)\" stroke-opacity=\"%s\" stroke-width=\"6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>", back, f(bO)
      printf "<path id=\"halo\" d=\"%s\" fill=\"none\" stroke=\"url(#boxG)\" stroke-opacity=\"%s\" stroke-width=\"%d\" stroke-linejoin=\"round\"/>", front, f(hO), hW
      printf "<path id=\"front\" d=\"%s\" fill=\"none\" stroke=\"url(#boxG)\" stroke-opacity=\"%s\" stroke-width=\"7\" stroke-linejoin=\"round\"/>", front, f(fO)
      printf "<path id=\"ridges\" d=\"%s\" fill=\"none\" stroke=\"url(#boxG)\" stroke-opacity=\"%s\" stroke-width=\"4\" stroke-linecap=\"round\"/>", ridge, f(rO)
      printf "<text id=\"value\" x=\"94\" y=\"%d\" font-size=\"%d\" font-weight=\"700\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"%s\">%s</text>", vy, vs, f(vO), val
      printf "</svg>\n"
    }'
}

if [[ $1 == --face ]]; then
  shift
  containers_frame "$@"
  exit 0
fi

# MARK: - What runs

zmodload zsh/datetime zsh/zselect || { print -u2 -- "Docker: zsh modules datetime/zselect are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir
[[ -n $DESMAPTIC_STORAGE ]] || { print -u2 -- "Docker: DESMAPTIC_STORAGE is not set"; exit 1 }

cell="{{CELL_ID}}"
dir="$DESMAPTIC_STORAGE/gallery/$cell"          # ps: the engine's last answer
shared="$DESMAPTIC_STORAGE/gallery/docker"      # poke: when a button of the page last started or stopped something
zf_mkdir -p "$dir" 2>/dev/null

# REPLY = the number of running containers, from `docker ps -q` on Docker Desktop's socket. Returns 1 when the engine
# did not answer within 10 s (still starting, or stuck: the CLI is stopped then).
count_containers() {
  local cli=$1 waited=0 rc id
  local -a ids
  # The CLI itself in the background (not docker_engine, a function: $! would be a subshell, and a stuck CLI would
  # outlive its kill). Its settings as docker_engine's.
  DOCKER_CLI_HINTS=false DOCKER_CLI_HOOKS=false "$cli" --host "unix://$HOME/.docker/run/docker.sock" ps -q \
    > "$dir/ps" 2>/dev/null </dev/null &
  asker=$!
  while kill -0 $asker 2>/dev/null; do
    if (( ++waited > 100 )); then
      kill $asker 2>/dev/null
      wait $asker 2>/dev/null
      asker=0
      return 1
    fi
    zselect -t 10
  done
  wait $asker
  rc=$? asker=0
  (( rc == 0 )) || return 1
  ids=()
  for id in ${(f)"$(<$dir/ps)"}; do
    [[ $id =~ '^[0-9a-f]{12,64}$' ]] && ids+=( $id )
  done
  REPLY=$#ids
}

told=""
# REPLY = off | idle | wait | "count <n>": the face to show.
read_state() {
  local cli
  if ! desktop_running; then REPLY=off; return; fi
  if ! engine_running; then REPLY=idle; return; fi
  if ! docker_cli; then
    [[ $REPLY != "$told" ]] && { told=$REPLY; print -ru2 -- "$REPLY" }
    REPLY=off
    return
  fi
  cli=$REPLY
  if ! count_containers "$cli"; then REPLY=wait; return; fi
  if (( REPLY > 0 )); then REPLY="count $REPLY"; else REPLY=idle; fi
}

# MARK: - Loop

api="http://127.0.0.1:9848/api"
period=5                                        # seconds between looks while the button is on screen
closely=90                                      # seconds of a look every second after a poke

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
  print -ru2 -- "Docker containers: update-button answered ${code:-nothing}: ${${out%$'\n'*}[1,300]}"
  return 1
}

shown=""                                        # the face as the phone shows it; "" before the first frame
poked=0 closely_until=0 due=0
while true; do
  poke=""
  [[ -f $shared/poke ]] && IFS= read -r poke < "$shared/poke" 2>/dev/null
  if [[ $poke == <-> ]] && (( poke > poked )); then
    poked=$poke closely_until=$(( poke + closely )) due=0
  fi

  if (( EPOCHSECONDS >= due )); then
    if visible; then
      read_state
      if [[ $REPLY != "$shown" ]]; then
        if post "$(containers_frame ${=REPLY})"; then
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
