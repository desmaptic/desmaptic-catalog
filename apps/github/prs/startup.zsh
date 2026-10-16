# GitHub › My PRs: how many of your pull requests are open in the repository and how many wait for your review, as
# the button's title — "2" (two of yours), "2 · 1" (and one waits for you: the button turns orange). The startup
# script is the setting, gh.zsh and then this file (app.json):
#   "repo=\"\"   # ← …\n@file:gh.zsh\n@file:prs/startup.zsh"
#
# From GitHub's search, the same two questions `gh pr status` asks (open pull requests of this repository by you, and
# those that ask your review) — but their totals, where gh pr status lists at most 10 of each: one GraphQL call of
# `gh api` (30 searches a minute for the whole account), every 2 minutes and only while the button is on screen. None
# of either — the plain button; gh cannot be asked — a grey triangle (the reason goes to the log once, and to
# gallery/{{CELL_ID}}/problem for the tap). The folder or owner/name it asked about goes to gallery/{{CELL_ID}}/where
# for the tap (prs/open.zsh), which leaves gallery/{{CELL_ID}}/poke to have it show its face again.

[[ -n $own ]] || { print -u2 -- "GitHub PRs: DESMAPTIC_STORAGE is not set"; exit 1 }
zf_mkdir -p "$own" 2>/dev/null

period=120                                      # seconds between looks while the button is on screen
retry=30                                        # … after a passing hitch (no network, GitHub slow)
color="#BF5AF2" orange="#FF9F0A" grey="#8E8E93"

told=""
tell() {   # logs a reason once, not on every look
  [[ $1 == "$told" ]] && return
  told=$1
  print -ru2 -- "GitHub PRs: $1"
}

# stuck <kind> <message>: the look ends in a grey triangle — the reason to the log once and to the tap.
stuck() {
  tell "${1#* }"
  print -r -- "$1" > "$own/problem" 2>/dev/null
  REPLY=problem
}

# refused <status> <what>: a gh call that failed — a passing hitch (no network, GitHub slow) keeps the face, anything
# else is stuck.
refused() {
  gh_refusal $1 "$2"
  if [[ $REPLY == (network|timeout)\ * ]]; then tell "${REPLY#* }"; REPLY=keep; else stuck "$REPLY"; fi
}

query='query($mine: String!, $review: String!) {
  mine: search(query: $mine, type: ISSUE, first: 0) { issueCount }
  review: search(query: $review, type: ISSUE, first: 0) { issueCount }
}'
named_for="" name=""                            # the folder whose owner/name was asked last, and that owner/name
# look: REPLY = the face — "<mine> <review>", none, problem, or keep (a passing hitch: the face stays).
look() {
  local -a counts
  local rc
  if problem || resolve; then stuck "$REPLY"; return; fi
  print -rl -- "folder=$folder" "slug=$slug" > "$own/where" 2>/dev/null
  if [[ -n $slug ]]; then
    name=$slug named_for=""
  elif [[ $named_for != "$folder" ]]; then
    run_gh 20 repo view --json nameWithOwner --jq .nameWithOwner
    rc=$?
    if (( rc != 0 )); then refused $rc "gh repo view"; return; fi
    name=$(first_line $tmp/out) named_for=$folder
  fi
  [[ $name == */* ]] || { named_for=""; stuck "other GitHub did not say which repository $folder is"; return }
  run_gh 30 api graphql -f query="$query" -f mine="repo:$name state:open is:pr author:@me" \
    -f review="repo:$name state:open is:pr review-requested:@me"
  rc=$?
  if (( rc != 0 )); then refused $rc "gh api graphql"; return; fi
  counts=( $(jq -r '[.data.mine.issueCount, .data.review.issueCount] | map(tostring) | join(" ")' "$tmp/out" 2>/dev/null) )
  if [[ $counts[1] != <-> || $counts[2] != <-> ]]; then
    tell "GitHub gave no counts"
    REPLY=keep
    return
  fi
  told=""
  zf_rm -f "$own/problem" 2>/dev/null
  (( counts[1] + counts[2] )) && REPLY="$counts[1] $counts[2]" || REPLY=none
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
  local json out code mine review
  case $1 in
    none)    json="{\"cellId\":\"$cell\",\"reset\":true}" ;;
    problem) json="{\"cellId\":\"$cell\",\"color\":\"$grey\",\"icon\":\"exclamationmark.triangle\"}" ;;
    *)       mine=${1% *} review=${1#* }
             if (( review > 99 )); then review="99+"; fi
             if (( mine > 99 )); then mine="99+"; fi
             if [[ $review == 0 ]]; then
               json="{\"cellId\":\"$cell\",\"color\":\"$color\",\"icon\":\"arrow.triangle.pull\",\"title\":\"$mine\"}"
             else
               json="{\"cellId\":\"$cell\",\"color\":\"$orange\",\"icon\":\"arrow.triangle.pull\",\"title\":\"$mine · $review\"}"
             fi ;;
  esac
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' \
    -H "Content-Type: application/json" -d "$json")
  code=${out##*$'\n'}
  [[ $code == 200 ]] && return 0
  print -ru2 -- "GitHub PRs: update-button answered ${code:-nothing}: ${${out%$'\n'*}[1,300]}"
  return 1
}

shown=""                                        # the face as the phone shows it; "" before the first post
poked=0 due=0
while true; do
  poke=""
  [[ -f $own/poke ]] && IFS= read -r poke < "$own/poke" 2>/dev/null
  if [[ $poke == <-> ]] && (( poke > poked )); then
    poked=$poke shown=""                        # a press reset the face: show it again at the next look
    (( due > EPOCHSECONDS + retry )) && due=$(( EPOCHSECONDS + retry ))
  fi
  if (( EPOCHSECONDS >= due )) && visible; then   # off screen: visible() asks the phone only every 5 s
    look
    face=$REPLY
    if [[ $face != keep && $face != "$shown" ]]; then
      if post "$face"; then shown=$face; else face=keep; fi
    fi
    [[ $face == keep ]] && due=$(( EPOCHSECONDS + retry )) || due=$(( EPOCHSECONDS + period ))
  fi
  zselect -t 100
done
