# Tailscale › the live face of Tailscale and Exit Node. The startup script is which face, ts.zsh and then this file
# (app.json):
#   "what=power\n@file:ts.zsh\n@file:live.zsh"
#
# what=power — Tailscale: green while it is connected and the coordination server sees this Mac, orange while it
# connects or is offline, orange with a person when it waits for a sign-in or the admin's approval, the plain button
# when it is off or the app is not open. what=exit — Exit Node: green with the exit node's name while the Mac's traffic
# goes through it, orange when that node is offline, the plain button with none. Both: a grey triangle when Tailscale
# is not installed or its status cannot be read (the reason goes to the log once).
#
# Every 10 seconds, and only while the button is on screen: off screen nothing is asked, only the phone every 5 s.
# While the app is not open, only whether it runs is asked (lsappinfo, every 5 s) — never the CLI, nor the phone
# whether the button is on screen. A press of any Tailscale button leaves gallery/tailscale/poke: both look again at
# once.

[[ -n $shared ]] || { print -u2 -- "Tailscale: DESMAPTIC_STORAGE is not set"; exit 1 }
zf_mkdir -p "$shared" 2>/dev/null

period=10                                       # seconds between looks while the button is on screen
green="#32D74B" orange="#FF9F0A" grey="#8E8E93"

told=""
tell() {   # logs a reason once, not on every look
  [[ $1 == "$told" ]] && return
  told=$1
  print -ru2 -- "Tailscale: $1"
}

# look: REPLY = the face — on, connecting, signin, off, exit:<online>:<name>, problem, or keep (a passing hitch:
# the face stays as it is). Only while the app runs: the loop checks that first.
look() {
  if ! status; then
    case $REPLY in
      (notRunning\ *) told=""; REPLY=off ;;
      (timeout\ *)    tell "${REPLY#* }"; REPLY=keep ;;
      (*)             tell "${REPLY#* }"; REPLY=problem ;;
    esac
    return
  fi
  told=""
  if [[ $what == exit ]]; then
    if [[ $state == Running && $exit_name != - ]]; then REPLY="exit:$exit_online:$exit_name"; else REPLY=off; fi
    return
  fi
  case $state in
    (Running)                    [[ $online == true ]] && REPLY=on || REPLY=connecting ;;
    (NeedsLogin|NeedsMachineAuth) REPLY=signin ;;
    (Starting|NoState)           REPLY=connecting ;;
    (*)                          REPLY=off ;;
  esac
}

# 0 when the phone shows the button, or when it cannot say (an older app). Asks at most every 5 s while it does not.
hidden=0 looked=0
visible() {
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

# post <face> → 0 when the agent took it. off is the button's own look.
post() {
  local json out code name colour=$green
  case $1 in
    (on)         json="{\"cellId\":\"$cell\",\"color\":\"$green\",\"icon\":\"point.3.connected.trianglepath.dotted\"}" ;;
    (connecting) json="{\"cellId\":\"$cell\",\"color\":\"$orange\",\"icon\":\"point.3.connected.trianglepath.dotted\"}" ;;
    (signin)     json="{\"cellId\":\"$cell\",\"color\":\"$orange\",\"icon\":\"person.crop.circle.badge.exclamationmark\"}" ;;
    (exit:*)
      [[ $1 == exit:true:* ]] || colour=$orange
      name=${1#exit:*:}
      (( ${#name} > 16 )) && name="${name[1,15]}…"
      json=$(jq -nc --arg c "$cell" --arg k "$colour" --arg t "$name" '{cellId: $c, color: $k, icon: "globe", title: $t}') ;;
    (problem)    json="{\"cellId\":\"$cell\",\"color\":\"$grey\",\"icon\":\"exclamationmark.triangle\"}" ;;
    (*)          json="{\"cellId\":\"$cell\",\"reset\":true}" ;;
  esac
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' \
    -H "Content-Type: application/json" -d "$json")
  code=${out##*$'\n'}
  [[ $code == 200 ]] && return 0
  print -ru2 -- "Tailscale: update-button answered ${code:-nothing}: ${${out%$'\n'*}[1,300]}"
  return 1
}

shown=""                                        # the face as the phone shows it; "" before the first post
poked=$EPOCHREALTIME due=0 recheck=0
while true; do
  poke=""
  [[ -f $shared/poke ]] && IFS= read -r poke < "$shared/poke" 2>/dev/null
  if [[ $poke == <->(.<->|) ]] && (( poke > poked )); then
    poked=$poke shown="" due=0                  # a press changed something, or flashed its own look over the face
  fi

  if (( EPOCHSECONDS >= due )); then
    # the cheapest first: whether Tailscale is there (once a minute) and runs. Without it the phone is never asked
    if (( EPOCHSECONDS >= recheck )); then
      find_cli || ts=()
      recheck=$(( EPOCHSECONDS + 60 ))
    fi
    face=""
    if (( ! $#ts )); then
      tell "Tailscale is not installed"; face=problem
    elif ! app_running; then
      told=""; face=off
    fi
    if [[ -n $face ]]; then
      [[ $face != "$shown" ]] && post $face && shown=$face
      due=$(( EPOCHSECONDS + 5 ))
    elif visible; then
      look
      face=$REPLY
      if [[ $face != keep && $face != "$shown" ]]; then
        if post $face; then shown=$face; else face=keep; fi
      fi
      due=$(( EPOCHSECONDS + period ))
    else
      due=$(( EPOCHSECONDS + 5 ))               # off screen: only the process and the phone, every 5 s
    fi
  fi
  zselect -t 100
done
