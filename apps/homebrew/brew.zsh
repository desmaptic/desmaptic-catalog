# Homebrew › what the page's scripts share: finding brew, running it, and talking to the agent.
# Functions only; each button's own file follows it (app.json):
#   "action=update\n@file:brew.zsh\n@file:action.zsh"
#
# brew is the one the scripts' PATH finds (the page shows when it is there), else Homebrew's own places. It runs in a
# clean environment — the account's HOME, USER, LOGNAME and TMPDIR and a stock PATH — so the agent's token never
# reaches it, without asking anything (NONINTERACTIVE) and with nothing on its input, never fetching on its own
# (HOMEBREW_NO_AUTO_UPDATE: the Update button fetches) and without colours or hints in what the scripts read.
# A press is stopped after 60 seconds, so every brew call here has a time of its own within it.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
setopt extended_glob
export LC_ALL=C
found=( ${commands[brew]:-} /opt/homebrew/bin/brew(N-*) /usr/local/bin/brew(N-*) )   # before PATH is reset
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime zsh/zselect || { print -u2 -- "Homebrew: zsh modules datetime and zselect are missing"; exit 1 }

cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"
started=$EPOCHREALTIME
tmp=""
trap '[[ -n $tmp ]] && rm -rf -- "$tmp"' EXIT
trap 'exit 1' TERM INT HUP
tmp=$(mktemp -d) || { print -u2 -- "Homebrew: no room for a temporary folder"; exit 1 }
: > "$tmp/in"

# call <endpoint> <json>: posts to the agent and prints its HTTP code. The token goes in through a descriptor,
# not the command line, where any user of the Mac could read it.
call() {
  curl -q -s -o /dev/null -m 5 -w '%{http_code}' "$api/$1" -H @/dev/fd/3 \
    -H "Content-Type: application/json" --data-binary @- \
    3<<< "Authorization: Bearer $DESMAPTIC_TOKEN" <<< "$2"
}

# fail <kind> <message>: the toast after the press says why (/api/error), then the press ends.
fail() {
  call update-button "{\"cellId\":\"$cell\",\"reset\":true}" >/dev/null
  call error "$(jq -nc --arg c "$cell" --arg k "$1" --arg m "$2" '{cellId: $c, kind: $k, message: $m}')" >/dev/null
  print -ru2 -- "Homebrew: $2"
  exit 1
}

# flash <seconds> <colour> <icon> [title]: shows it on the button for a while, then the button's own face again.
flash() {
  call update-button "$(jq -nc --arg c "$cell" --arg k "$2" --arg i "$3" --arg t "${4-}" \
    '{cellId: $c, color: $k, icon: $i} + (if $t == "" then {} else {title: $t} end)')" >/dev/null
  sleep $1
  call update-button "{\"cellId\":\"$cell\",\"reset\":true}" >/dev/null
}

# notify <title> <body>: the whole answer, on the phone. Symbols, names and commands only: the same in every language.
notify() {
  call notify "$(jq -nc --arg c "$cell" --arg t "$1" --arg b "$2" \
    '{cellId: $c, title: $t, body: $b, targets: ["phone"]}')" >/dev/null
}

# limited <seconds> <program> <arg>…: runs the program — the program itself, not a function, so it can be stopped —
# with stdin from $tmp/in, stdout in $tmp/out and stderr in $tmp/err; returns its status, 124 when it ran longer.
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

# left <seconds>: REPLY = the seconds this press may still give a brew call, out of the 60 it has (10 kept for the
# answer), but no more than asked.
left() {
  local rest=$(( 50 - (EPOCHREALTIME - started) ))
  (( rest > $1 )) && rest=$1
  (( rest < 1 )) && rest=1
  printf -v REPLY %.0f $rest
}

# first_line <file>: the first non-empty line of a file, at most 200 characters (counted in UTF-8), without the
# "Error: " brew starts it with.
first_line() {
  local line LC_ALL=en_US.UTF-8
  for line in "${(@f)$(<$1)}"; do
    if [[ -n ${line//[[:space:]]/} ]]; then
      line=${line#Error: }
      (( ${#line} > 200 )) && line="${line[1,199]}…"
      print -r -- "$line"
      return
    fi
  done
}

# need_brew: sets brew (the program) and brewing (how to run it), or the press ends saying what to install.
brew=""
brewing=()
need_brew() {
  (( $#found )) || fail notFound "Homebrew is not installed: see brew.sh to install it"
  brew=$found[1]
  brewing=( env -i HOME=$HOME USER=$USER LOGNAME=$LOGNAME ${TMPDIR:+TMPDIR=$TMPDIR} PATH=$PATH
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_COLOR=1 NONINTERACTIVE=1 $brew )
}

# run_brew <seconds> <what> <arguments…>: brew with them, at most for those seconds (or what the press has left).
# Output as limited's. When it fails, the press ends saying why: <what> is how the message names the job.
run_brew() {
  local seconds=$1 what=$2 rc err
  shift 2
  left $seconds
  limited $REPLY $brewing "$@"
  rc=$?
  (( rc == 0 )) && return 0
  (( rc == 124 )) && fail timeout "$what took longer than this button may wait and was stopped: try again, or run brew $* in Terminal"
  err=$(first_line $tmp/err)
  [[ -n $err ]] || err=$(first_line $tmp/out)
  case $err in
    (*(Could\ not\ resolve\ host|Failed\ to\ connect|timed\ out|network)*)
      fail network "$what failed: the Mac can’t reach GitHub. Check its internet connection" ;;
    (*(already\ locked|is\ locked|another\ active\ Homebrew)*)
      fail busy "Homebrew is busy with another job: try again when it ends" ;;
  esac
  fail other "$what failed: ${err:-brew gave no reason}"
}

# names_after <header>: the package names $tmp/out lists under a "==> <header>…" line (one a line, as brew prints them).
names_after() {
  local line under=0
  for line in "${(@f)$(<$tmp/out)}"; do
    if (( under )); then
      [[ $line == [a-z0-9][a-z0-9@._+/-]# ]] || break
      print -r -- "$line"
    elif [[ $line == "==> $1"* ]]; then
      under=1
    fi
  done
}

# outdated: n = how many packages brew upgrade would take, by the package list Homebrew fetched last: formulae (pinned
# ones left out, as brew upgrade leaves them) and casks — the count the widget brew-updates shows.
n=0
outdated() {
  run_brew 30 "brew outdated" outdated --json=v2
  n=$(jq -r '[.formulae[] | select(.pinned | not)] + .casks | length' $tmp/out 2>/dev/null)
  [[ $n == <-> ]] || fail other "brew outdated gave no list this button can read"
}
