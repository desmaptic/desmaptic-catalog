# GitHub › CI: the last GitHub Actions run of the branch, as the button's colour and icon. The startup script is the
# setting, gh.zsh and then this file (app.json):
#   "repo=\"\"   # ← …\n@file:gh.zsh\n@file:ci/startup.zsh"
#
# The branch is the folder's current one (or the repository's default branch for owner/name); its last run comes
# from `gh run list -b <branch> -L 1`: green tick — passed, red cross — failed, orange arrows — running or queued,
# grey slash — cancelled, orange hand — waiting for someone's approval, the plain button — no run yet, a grey
# triangle — gh cannot be asked (the reason goes to the log once). Every 30 s while a run is going, every 90 s
# otherwise, and only while the button is on screen: off screen nothing is asked, only the phone every 5 s.
#
# What the loop saw goes to gallery/{{CELL_ID}}/run (the run's id, address and result, the folder or owner/name):
# the tap opens that run and the long press reruns its failed jobs (ci/open.zsh, ci/rerun.zsh). They leave
# gallery/{{CELL_ID}}/poke to have it look again, and the long press gallery/{{CELL_ID}}/armed while it waits for the
# second press: the loop then leaves the armed look alone. A look that gh cannot answer removes the run (the tap and
# the long press act on no repository the button no longer shows) and leaves its reason in gallery/{{CELL_ID}}/problem:
# what the grey triangle means, which the tap and the long press then say.

[[ -n $own ]] || { print -u2 -- "GitHub CI: DESMAPTIC_STORAGE is not set"; exit 1 }
zf_mkdir -p "$own" 2>/dev/null

period=90                                       # seconds between looks while the button is on screen
busy=30                                         # … while a run is going
green="#32D74B" red="#FF453A" orange="#FF9F0A" grey="#8E8E93"

told=""
tell() {   # logs a reason once, not on every look
  [[ $1 == "$told" ]] && return
  told=$1
  print -ru2 -- "GitHub CI: $1"
}

# stuck <kind> <message>: the look ends in a grey triangle — the reason to the log once and to the presses.
stuck() {
  tell "${1#* }"
  print -r -- "$1" > "$own/problem" 2>/dev/null
  zf_rm -f "$own/run" 2>/dev/null
  REPLY=problem
}

# refused <status> <what>: a gh call that failed — a passing hitch (no network, GitHub slow) keeps the face, anything
# else is stuck.
refused() {
  gh_refusal $1 "$2"
  if [[ $REPLY == (network|timeout)\ * ]]; then tell "${REPLY#* }"; REPLY=keep; else stuck "$REPLY"; fi
}

default_of="" default_branch=""
# look: REPLY = the face — passed, failed, running, cancelled, approval, none, problem, or keep (a passing hitch:
# the face stays as it is).
look() {
  local br row id run_status conclusion url rc
  if problem || resolve; then stuck "$REPLY"; return; fi
  if [[ -n $folder ]]; then
    if ! current_branch; then stuck "$REPLY"; return; fi
    br=$REPLY
  else
    if [[ $default_of != "$slug" ]]; then
      run_gh 20 repo view --json defaultBranchRef --jq .defaultBranchRef.name
      rc=$?
      if (( rc != 0 )); then refused $rc "gh repo view"; return; fi
      default_of=$slug default_branch=$(first_line $tmp/out)
    fi
    br=$default_branch
  fi
  run_gh 20 run list -b "$br" -L 1 --json databaseId,status,conclusion,url
  rc=$?
  if (( rc != 0 )); then refused $rc "gh run list"; return; fi
  # "-" for an empty field (a running run has no conclusion yet): read would close the gap and shift the address
  row=$(jq -r '.[0] // empty | [.databaseId, .status, .conclusion, .url] | map(tostring | if . == "" then "-" else . end)
    | join(" ")' "$tmp/out" 2>/dev/null)
  read -r id run_status conclusion url <<< "$row"
  told=""
  zf_rm -f "$own/problem" 2>/dev/null
  if [[ $id != <-> || $url != https://* ]]; then
    zf_rm -f "$own/run" 2>/dev/null
    REPLY=none
    return
  fi
  print -rl -- "id=$id" "url=$url" "status=$run_status" "conclusion=$conclusion" "folder=$folder" "slug=$slug" \
    > "$own/run.new" 2>/dev/null && mv -f "$own/run.new" "$own/run" 2>/dev/null
  if [[ $run_status != completed ]]; then REPLY=running; return; fi
  case $conclusion in
    (success|neutral|skipped)            REPLY=passed ;;
    (failure|timed_out|startup_failure)  REPLY=failed ;;
    (action_required)                    REPLY=approval ;;
    (*)                                  REPLY=cancelled ;;
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

# post <face> → 0 when the agent took it. none is the button's own look.
post() {
  local json out code
  case $1 in
    passed)    json="{\"cellId\":\"$cell\",\"color\":\"$green\",\"icon\":\"checkmark.circle.fill\"}" ;;
    failed)    json="{\"cellId\":\"$cell\",\"color\":\"$red\",\"icon\":\"xmark.circle.fill\"}" ;;
    running)   json="{\"cellId\":\"$cell\",\"color\":\"$orange\",\"icon\":\"arrow.triangle.2.circlepath\"}" ;;
    approval)  json="{\"cellId\":\"$cell\",\"color\":\"$orange\",\"icon\":\"hand.raised.fill\"}" ;;
    cancelled) json="{\"cellId\":\"$cell\",\"color\":\"$grey\",\"icon\":\"slash.circle\"}" ;;
    problem)   json="{\"cellId\":\"$cell\",\"color\":\"$grey\",\"icon\":\"exclamationmark.triangle\"}" ;;
    *)         json="{\"cellId\":\"$cell\",\"reset\":true}" ;;
  esac
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' \
    -H "Content-Type: application/json" -d "$json")
  code=${out##*$'\n'}
  [[ $code == 200 ]] && return 0
  print -ru2 -- "GitHub CI: update-button answered ${code:-nothing}: ${${out%$'\n'*}[1,300]}"
  return 1
}

shown=""                                        # the face as the phone shows it; "" before the first post
poked=0 due=0
while true; do
  poke=""
  [[ -f $own/poke ]] && IFS= read -r poke < "$own/poke" 2>/dev/null
  if [[ $poke == <-> ]] && (( poke > poked )); then
    poked=$poke shown="" due=$(( EPOCHSECONDS + 3 ))   # a rerun takes a moment to show as queued
  fi
  armed=""
  [[ -f $own/armed ]] && IFS= read -r armed < "$own/armed" 2>/dev/null
  if [[ -n $armed ]]; then
    if [[ $armed == <-> ]] && (( EPOCHSECONDS - armed <= 10 )); then
      zselect -t 100                            # the long press's armed look stays until it ends
      continue
    fi
    zf_rm -f "$own/armed" 2>/dev/null
    shown="" due=0                              # the armed look goes now, not at the next look
  fi

  if (( EPOCHSECONDS >= due )); then
    if visible; then
      look
      face=$REPLY
      if [[ $face != keep && $face != "$shown" ]]; then
        if post $face; then shown=$face; else face=keep; fi
      fi
      [[ $face == running || $face == keep ]] && due=$(( EPOCHSECONDS + busy )) || due=$(( EPOCHSECONDS + period ))
    fi                                          # off screen: visible() itself asks the phone only every 5 s
  fi
  zselect -t 100
done
