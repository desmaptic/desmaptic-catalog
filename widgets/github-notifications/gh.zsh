# GitHub notifications › what the loop (startup.zsh) and the long press (read.zsh) share: the GitHub CLI (gh), its
# failures in plain words and talking to the agent. Functions and settings only; each script's own file follows it
# (item.json): "@file:gh.zsh\n@file:startup.zsh", "@file:gh.zsh\n@file:read.zsh".
#
# gh signs in by itself (gh auth login, once in Terminal): no key on the button. It runs in a clean environment — the
# account's HOME, USER, LOGNAME and TMPDIR and the system PATH — so the agent's token never reaches it, and never
# asks anything (GH_PROMPT_DISABLED). The notifications API needs no repository folder, so no Command Line Tools
# either. Nothing GitHub answers about a notification — a title, a repository — is ever printed or logged.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
setopt extended_glob
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT HUP
zmodload zsh/datetime zsh/zselect || { print -u2 -- "GitHub notifications: zsh modules datetime and zselect are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_rm

cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"
own=""                                          # this button's state: what its long press armed or did
[[ -n $DESMAPTIC_STORAGE ]] && own="$DESMAPTIC_STORAGE/gallery/{{CELL_ID}}"
confirm=10                                      # seconds the first long press waits for the second one

tmp=""
trap '[[ -n $tmp ]] && rm -rf -- "$tmp"' EXIT
tmp=$(mktemp -d) || { print -u2 -- "GitHub notifications: no room for a temporary folder"; exit 1 }
: > "$tmp/in"

# call <endpoint> <json>: posts to the agent and prints its HTTP code.
call() {
  curl -q -s -o /dev/null -m 5 -w '%{http_code}' "$api/$1" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' \
    -H "Content-Type: application/json" --data-binary @- <<< "$2"
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

# gh_found: 0 with gh set to the GitHub CLI, or 1 with the refusal in REPLY ("<kind> <message>").
gh_found() {
  gh=( /opt/homebrew/bin/gh(N-*) /usr/local/bin/gh(N-*) )
  (( $#gh )) && return 0
  REPLY="notFound The GitHub CLI is not installed: brew install gh, then gh auth login in Terminal"
  return 1
}

# gh_api <seconds> <arguments…>: gh api, as limited runs it.
gh_api() {
  local seconds=$1; shift
  limited $seconds env -i HOME=$HOME USER=$USER LOGNAME=$LOGNAME ${TMPDIR:+TMPDIR=$TMPDIR} PATH="$PATH" \
    GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 NO_COLOR=1 $gh[1] api "$@"
}

# gh_refusal <status> <what>: REPLY = "<lasting> <kind> <message>" for a gh call that failed; lasting is 1 when the
# user must act (gh signed out, its sign-in refused or not allowed to read notifications), 0 when it may pass by itself.
# The words are looked for in all gh said: GitHub's reason may come after a long documentation address.
gh_refusal() {
  local all=$(<$tmp/err) err
  if (( $1 == 124 )); then
    REPLY="0 timeout GitHub did not answer in time"
  elif (( $1 == 4 )) || [[ $all == *(401\ Unauthorized|Bad\ credentials|HTTP\ 401)* ]]; then
    REPLY="1 auth The GitHub CLI is not signed in: run gh auth login in Terminal"
  elif [[ $all == *[Rr]ate\ limit* ]]; then
    REPLY="0 busy GitHub’s limit of questions is used up for now: try again in a few minutes"
  elif [[ $all == *(notifications?\ scope|Resource\ not\ accessible)* ]]; then
    REPLY="1 auth The GitHub CLI may not read notifications: run gh auth refresh -s notifications in Terminal"
  elif [[ $all == *(auth\ login|authenticat)* ]]; then
    REPLY="1 auth The GitHub CLI is not signed in: run gh auth login in Terminal"
  elif [[ $all == *(error\ connecting|dial\ tcp|no\ such\ host|TLS\ handshake|connection\ refused|connection\ reset|i/o\ timeout|EOF)* ]]; then
    REPLY="0 network GitHub cannot be reached"
  elif [[ $all == *HTTP\ 5[0-9][0-9]* ]]; then
    REPLY="0 network GitHub has trouble on its side: it answered ${${all#*HTTP }[1,3]}"
  else
    err=$(first_line $tmp/err)
    REPLY="0 other $2: ${err:-gh ended with status $1}"
  fi
}

# stamp <name>: REPLY = the time in a state file of this button (armed, marking, marked: seconds, maybe with a
# fraction), or 0.
stamp() {
  local t=""
  [[ -n $own && -f $own/$1 ]] && IFS= read -r t < "$own/$1" 2>/dev/null
  [[ $t == (<->|<->.<->) ]] && REPLY=$t || REPLY=0
}
