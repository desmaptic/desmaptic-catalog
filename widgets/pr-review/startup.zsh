# Review requests: how many open pull requests on GitHub wait for your review, under a pull-request glyph (1×1 SVG
# face). The startup script is this file (item.json); the tap opens github.com/pulls/review-requested.
#
# The count is GitHub's search for open pull requests that request your review (`gh search prs --review-requested=@me`,
# the same list as that page): only the number of results is read, never a repository or a title, and nothing of the
# answer goes to the log. The search API allows 30 questions a minute for the whole account: one every 2 minutes,
# and only while the button is on screen; off screen nothing is asked, only a look at the phone every 5 s.
# gh signs in by itself (gh auth login, once in Terminal): no key on the button. It runs in a clean environment — the
# account's HOME, USER, LOGNAME and TMPDIR and the system PATH — so the agent's token never reaches it, and never
# asks anything (GH_PROMPT_DISABLED). A search needs no repository folder, so no Command Line Tools either.
#
# Without gh, or with gh signed out or its sign-in refused, the glyph turns grey with "—" and the phone says what to
# do (/api/error). Any other failure (no network, GitHub slow, failing or out of searches) keeps the last count, and
# its reason goes to the phone; after 15 minutes without an answer the count is grey "—" as well, so it never passes
# for a current one.
#
# Every frame has the same 8 elements in the same order: the glyph glides between them.
# `zsh startup.zsh --face <rest|none|count|problem> [number]` prints one frame (rest.svg and demo.svg are made that way).
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
setopt extended_glob
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT HUP

# MARK: - Face

# review_frame <state> [number]. rest: the glyph alone, large (the face before the script runs); none: nothing waits
# ("0" under a calm, dim glyph); count: pull requests wait (the number under a lit orange-to-pink glyph); problem: the
# count cannot be had (a grey glyph over "—").
review_frame() {
  emulate -L zsh
  export LC_ALL=C
  local state=${1:-rest} number=${2:-0} value
  [[ $state == (rest|none|count|problem) ]] || state=rest
  [[ $number == <-> ]] || number=0
  (( number > 99 )) && value="99+" || value=$number
  [[ $state == (rest|none) ]] && value=0        # never an empty <text>: the structure must not change
  [[ $state == problem ]] && value="—"
  awk -v st=$state -v val="$value" '
    function f(x) { return sprintf("%.2f", x) }
    BEGIN {
      # gradient ends; glyph opacity; bloom colour and opacity; value opacity and size; glyph placement and scale
      c1 = "#FFD60A"; c2 = "#FF9F0A"; gO = 0.90; gC = "#FF9F0A"; gA = 0.12; vO = 0; vs = 60
      tx = 50; ty = 50; sc = 1
      if (st != "rest")    { tx = 65; ty = 22; sc = 0.70 }
      if (st == "none")    { gO = 0.50; gA = 0.05; vO = 0.60 }
      if (st == "count")   { c1 = "#FF9F0A"; c2 = "#FF375F"; gO = 1; gC = "#FF6B35"; gA = 0.30; vO = 1
                             if (val == "99+") vs = 48 }
      if (st == "problem") { c1 = "#8E8E93"; c2 = "#636366"; gO = 0.70; gC = "#8E8E93"; gA = 0.04; vO = 0.60 }

      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\"><defs>"
      printf "<linearGradient id=\"prG\" gradientUnits=\"userSpaceOnUse\" x1=\"10\" y1=\"5\" x2=\"90\" y2=\"95\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></linearGradient>", c1, c2
      printf "<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.55\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient></defs>", gC, f(gA), gC, f(gA * 0.35), gC
      printf "<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"92\" fill=\"url(#bloomG)\"/>"
      # the glyph, drawn in a 100×100 box: a branch on the left (two commits), the pull request curving into it
      printf "<g id=\"glyph\" transform=\"translate(%s %s) scale(%s)\" fill=\"none\" stroke=\"url(#prG)\" stroke-opacity=\"%s\" stroke-width=\"8\" stroke-linecap=\"round\" stroke-linejoin=\"round\">", f(tx), f(ty), f(sc), f(gO)
      printf "<circle id=\"top\" cx=\"24\" cy=\"18\" r=\"11\"/>"
      printf "<path id=\"branch\" d=\"M 24 37 L 24 63\"/>"
      printf "<circle id=\"base\" cx=\"24\" cy=\"82\" r=\"11\"/>"
      printf "<circle id=\"head\" cx=\"76\" cy=\"82\" r=\"11\"/>"
      printf "<path id=\"pull\" d=\"M 76 63 L 76 42 Q 76 18 52 18 L 46 18 M 57 7 L 46 18 L 57 29\"/>"
      printf "</g>"
      printf "<text id=\"value\" x=\"100\" y=\"148\" font-size=\"%d\" font-weight=\"700\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" opacity=\"%s\">%s</text>", vs, f(vO), val
      printf "</svg>\n"
    }'
}

if [[ $1 == --face ]]; then
  shift
  review_frame "$@"
  exit 0
fi

# MARK: - What runs

zmodload zsh/datetime zsh/zselect || { print -u2 -- "Review requests: zsh modules datetime/zselect are missing"; exit 1 }

cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"
period=120                                      # seconds between looks while the button is on screen
retry=30                                        # … after a passing hitch (no network, GitHub slow)
stale=900                                       # seconds after the last count when a hitch greys it out

tmp=""
trap '[[ -n $tmp ]] && rm -rf -- "$tmp"' EXIT
tmp=$(mktemp -d) || { print -u2 -- "Review requests: no room for a temporary folder"; exit 1 }
: > "$tmp/in"

told=""
tell() {   # logs a reason once, not on every look
  [[ $1 == "$told" ]] && return
  told=$1
  print -ru2 -- "Review requests: $1"
}

# report <kind> <message> | report clear: tells the phone why the count cannot be had, on a change; clear once it
# can again. Remembered only when the agent took it (200), so a refused one is posted again at the next look.
said=""                                         # "<kind> <message>" the phone was told last; "" when all is well
report() {
  local want="" json code
  [[ $1 == clear ]] || want="$1 $2"
  [[ $want == "$said" ]] && return 0
  if [[ -z $want ]]; then
    json="{\"cellId\":\"$cell\",\"clear\":true}"
  else
    json=$(jq -nc --arg c "$cell" --arg k "$1" --arg m "$2" '{cellId: $c, kind: $k, message: $m}')
  fi
  code=$(curl -q -s -o /dev/null -m 5 -w '%{http_code}' "$api/error" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' \
    -H "Content-Type: application/json" --data-binary @- <<< "$json")
  [[ $code == 200 ]] && said=$want
  return 0
}

# limited <seconds> <program> <arg>…: runs the program with stdin from $tmp/in, stdout in $tmp/out and stderr in
# $tmp/err; returns its status, 124 when it ran longer (then it is stopped).
limited() {
  local seconds=$1; shift
  "$@" < "$tmp/in" > "$tmp/out" 2> "$tmp/err" &
  local pid=$! deadline=$(( EPOCHREALTIME + seconds ))
  while kill -0 $pid 2>/dev/null; do
    if (( EPOCHREALTIME >= deadline )); then
      kill $pid 2>/dev/null
      return 124
    fi
    zselect -t 20
  done
  wait $pid
}

# first_line <file>: the first non-empty line of a file, at most 200 characters (counted in UTF-8).
first_line() {
  local line LC_ALL=en_US.UTF-8
  for line in "${(@f)$(<$1)}"; do
    if [[ -n ${line//[[:space:]]/} ]]; then
      (( ${#line} > 200 )) && line="${line[1,199]}…"
      print -r -- "$line"
      return
    fi
  done
}

# look: REPLY = the face — none, "count <n>", problem, or keep (a passing hitch: the face stays).
# --limit 100: one page of the search, enough to tell "99+".
look() {
  local -a gh
  local rc err all n
  gh=( /opt/homebrew/bin/gh(N-*) /usr/local/bin/gh(N-*) )
  if (( ! $#gh )); then
    trouble notFound "The GitHub CLI isn’t installed. In Terminal, run brew install gh, then gh auth login."
    return
  fi
  limited 30 env -i HOME=$HOME USER=$USER LOGNAME=$LOGNAME ${TMPDIR:+TMPDIR=$TMPDIR} PATH="$PATH" \
    GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 NO_COLOR=1 \
    $gh[1] search prs --review-requested=@me --state=open --archived=false --json number --limit 100 --jq length
  rc=$?
  if (( rc == 0 )); then
    n=$(first_line $tmp/out)
    if [[ $n != <-> ]]; then hitch other "GitHub didn’t give the count."; return; fi
    told=""
    report clear
    good=$EPOCHSECONDS
    (( n > 0 )) && REPLY="count $n" || REPLY=none
    return
  fi
  # The words are looked for in all gh said: it prints GitHub's answer after its own words, and the part that names
  # the reason (a rate limit's message) may come after a long documentation address. Only a missing gh or sign-in
  # greys the count at once; anything else is a hitch.
  all=$(<$tmp/err)
  if (( rc == 124 )); then
    hitch timeout "GitHub didn’t answer in time."
  elif (( rc == 4 )) || [[ $all == *(401\ Unauthorized|Bad\ credentials)* ]]; then
    trouble auth "The GitHub CLI isn’t signed in. Run gh auth login in Terminal."
  elif [[ $all == *[Rr]ate\ limit* ]]; then
    hitch other "You’ve hit GitHub’s search limit for now. The count comes back in a few minutes."
  elif [[ $all == *(auth\ login|authenticat)* ]]; then
    trouble auth "The GitHub CLI isn’t signed in. Run gh auth login in Terminal."
  elif [[ $all == *(error\ connecting|dial\ tcp|no\ such\ host|TLS\ handshake|connection\ refused|connection\ reset|i/o\ timeout|EOF)* ]]; then
    hitch network "The Mac can’t reach GitHub. Check its internet connection."
  elif [[ $all == *status\ code:\ 5[0-9][0-9]* ]]; then
    hitch network "GitHub is having trouble right now. It answered with error ${${all#*status code: }[1,3]}."
  else
    err=$(first_line $tmp/err)
    hitch other "GitHub didn’t give the count: ${err:-gh ended with status $rc}"
  fi
}

# trouble <kind> <message>: the count cannot be had until the user acts — a grey "—", the reason to the phone.
trouble() {
  tell "$2"
  report $1 "$2"
  REPLY=problem
}

# hitch <kind> <message>: out of the user's hands for now — the reason to the phone, the last count stays until it
# is $stale seconds old.
good=0                                          # when the last count came
hitch() {
  tell "$2"
  report $1 "$2"
  if (( EPOCHSECONDS - good > stale )); then REPLY=problem; else REPLY=keep; fi
}

# MARK: - Loop

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
  print -ru2 -- "Review requests: update-button answered ${code:-nothing}: ${${out%$'\n'*}[1,300]}"
  return 1
}

# Every look sends its face, changed or not: a face reset from outside (the user saving the button) comes back
# within one look.
due=0
while true; do
  if (( EPOCHSECONDS >= due )); then
    if visible; then
      look
      face=$REPLY
      if [[ $face != keep ]] && ! post "$(review_frame ${=face})"; then
        face=keep                               # the agent is busy or restarting: try again soon
      fi
      [[ $face == keep ]] && due=$(( EPOCHSECONDS + retry )) || due=$(( EPOCHSECONDS + period ))
    else
      due=$(( EPOCHSECONDS + 1 ))               # visible() itself asks the phone only every 5 s
    fi
  fi
  zselect -t 100
done
