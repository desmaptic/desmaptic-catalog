#!/bin/zsh
# Ask the Project tap: answers the question typed on the phone ($DESMAPTIC_INPUT) about one project folder and
# sends the answer to the phone as a notification. The three quick replies are answered without AI, at once and
# for free — the commits of yesterday and the uncommitted changes by git, the pull requests by the GitHub CLI; any
# other question goes to Claude Code (`claude -p`) in the folder: a light model, tools that only read (Read, Grep,
# Glob), no MCP servers, no session kept, at most 50 s. The folder is the button's setting, on the first line:
# `folder="~/Developer/my-app"` — a full path or one under ~. While it is empty the folder is found (project.zsh,
# before this file): the folder of the last Claude Code or Codex session of the Desmaptic plugin, else the front
# Terminal, iTerm2, Ghostty or Finder window's; with neither, the button says where to set it. The notification names
# the folder, so the user sees which one answered. The button's command (item.json):
#   "folder=\"\"   # ← …\n@file:project.zsh\n@file:ask.zsh"
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
setopt extended_glob
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime zsh/zselect || { print -u2 -- "Ask the Project: zsh modules datetime and zselect are missing"; exit 1 }
started=$EPOCHREALTIME

cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"
tmp=""
trap '[[ -n $tmp ]] && rm -rf -- "$tmp"' EXIT
trap 'exit 0' TERM INT

# call <endpoint> <json>: posts to the agent and prints its HTTP code. The token goes in through a descriptor,
# not the command line, where any user of the Mac could read it.
call() {
  curl -q -s -o /dev/null -m 5 -w '%{http_code}' "$api/$1" -H @/dev/fd/3 \
    -H "Content-Type: application/json" --data-binary @- \
    3<<< "Authorization: Bearer $DESMAPTIC_TOKEN" <<< "$2"
}

# fail <kind> <message>: the toast after the tap says why (/api/error), then the tap ends.
fail() {
  call update-button "{\"cellId\":\"$cell\",\"reset\":true}" >/dev/null
  call error "$(jq -nc --arg c "$cell" --arg k "$1" --arg m "$2" '{cellId: $c, kind: $k, message: $m}')" >/dev/null
  print -ru2 -- "Ask the Project: $2"
  exit 1
}

# answer <text>: the notification on the phone — the question as its title, the project under it: the folder's name,
# then where it is ("my-app · ~/Developer").
answer() {
  local body=${${1##[[:space:]]#}%%[[:space:]]#}
  body=$(shorten "$body" 20000)
  local parent=${folder:h}
  [[ $parent == $HOME || $parent == $HOME/* ]] && parent="~${parent#$HOME}"
  local code=$(call notify "$(jq -nc --arg c "$cell" --arg t "$(shorten "$question" 120)" --arg s "${folder:t} · $parent" --arg b "$body" \
    '{cellId: $c, title: $t, subtitle: $s, body: $b, targets: ["phone"]}')")
  [[ $code == 200 ]] || fail other "The answer could not be sent to the phone (the agent answered ${code:-nothing})"
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

# shorten <text> <n>: the text, cut to at most n characters with "…" at the end. Counted in UTF-8: under LC_ALL=C a
# cut counts bytes and can split a letter in two.
shorten() {
  local LC_ALL=en_US.UTF-8
  local s=$1
  (( ${#s} > $2 )) && s="${s[1,$(( $2 - 1 ))]}…"
  print -r -- "$s"
}

# first_line <file>: the first non-empty line of a file, at most 200 characters.
first_line() {
  local line
  for line in "${(@f)$(<$1)}"; do
    [[ -n ${line//[[:space:]]/} ]] && { shorten "$line" 200; return }
  done
}

# ---- the folder: the setting, or the one found ----
found_in=""
if [[ -z $folder ]]; then
  project_folder
  case $? in
    (0) ;;
    (2) fail $project_kind "$project_why, or set the project folder in this button’s settings" ;;
    (*) fail config "No project folder found: no Claude Code or Codex session is running, and no Terminal or Finder window shows a folder. Set one in this button’s settings, e.g. folder=\"~/Developer/my-app\"" ;;
  esac
fi
case $folder in
  '~')   folder=$HOME ;;
  '~/'*) folder=$HOME/${folder#'~/'} ;;
esac
[[ $folder == /* ]] || fail config "Not a full path: $folder (start it with / or ~/)"
[[ -d $folder ]] || fail notFound "No such folder: $folder"
folder=${folder:a}
cd -- "$folder" || fail permission "The folder cannot be opened: $folder"
# The folder in the button's words: a found one says where it came from.
place=$folder
[[ -n $found_in ]] && place="$folder (the folder of $found_in)"

question=${DESMAPTIC_INPUT//$'\r'/}
question=${${question##[[:space:]]#}%%[[:space:]]#}
[[ -n $question ]] || fail other "Nothing to ask: the question is empty"

tmp=$(mktemp -d) || fail other "No room for a temporary folder"
: > "$tmp/in"
call update-button "{\"cellId\":\"$cell\",\"icon\":\"hourglass\"}" >/dev/null

# The quick replies, in every language the Gallery speaks: the phone sends the reply's words as they are.
case $question in
  ("What did I do yesterday?"|"Was habe ich gestern gemacht?"|"¿Qué hice ayer?"|"Qu’ai-je fait hier ?"|"Qu'ai-je fait hier ?"|"Что я сделал вчера?"|"Что я сделала вчера?")
    kind=yesterday ;;
  ("Status of my PRs"|"Status meiner PRs"|"Estado de mis PR"|"État de mes PR"|"Статус моих PR")
    kind=prs ;;
  ("What isn’t committed?"|"What isn't committed?"|"Was ist nicht committet?"|"¿Qué falta por confirmar?"|"Qu’est-ce qui n’est pas commité ?"|"Qu'est-ce qui n'est pas commité ?"|"Что не закоммичено?")
    kind=uncommitted ;;
  (*)
    kind=claude ;;
esac

# ---- git, for yesterday and the uncommitted changes ----
# A stock Mac has no git: /usr/bin's copy is only a stub that opens an install dialog without the Command
# Line Tools, so the tool is taken from the developer folder xcode-select names, after checking it is there, and
# without them the button says what to install.
if [[ $kind == (yesterday|uncommitted) ]]; then
  dev=$(xcode-select -p 2>/dev/null)
  vcs=( ${dev:+$dev/usr/bin/git(N-*)} )
  (( $#vcs )) || fail notFound "This answer needs Apple’s Command Line Tools: install them in Terminal with xcode-select --install"
  limited 10 $vcs rev-parse --is-inside-work-tree
  [[ $(<$tmp/out) == true ]] || fail config "$place is not a Git repository: set a project folder that uses Git in this button’s settings"
fi

case $kind in
  (yesterday)
    # Your commits, on every branch, of the last day before today that has any: on a Monday, Friday's. One date
    # throughout, the commit date — the one --since and --until filter by (a rebased commit counts on its new day).
    me=$($vcs config user.email 2>/dev/null)
    strftime -s today '%Y-%m-%d' $EPOCHSECONDS
    strftime -r -s midnight '%Y-%m-%d' $today
    strftime -s yesterday '%Y-%m-%d' $(( midnight - 43200 ))
    limited 15 $vcs log --all --no-merges ${me:+--author=$me} --until="$today 00:00:00" -1 --date=format:%Y-%m-%d \
      --format=%cd || fail other "The history could not be read: $(first_line $tmp/err)"
    day=$(first_line $tmp/out)
    if [[ -z $day ]]; then
      out="No commits of yours before today."
    else
      limited 15 $vcs log --all --no-merges ${me:+--author=$me} --since="$day 00:00:00" --until="$day 23:59:59" \
        --reverse --date=format:%H:%M --format='%cd %h %s' || fail other "The history could not be read: $(first_line $tmp/err)"
      out=$(<$tmp/out)
      [[ $day == $yesterday ]] || out="Nothing yesterday. The last day with commits, $day:"$'\n'"$out"
    fi
    answer "$out" ;;

  (uncommitted)
    limited 15 $vcs status --short --branch || fail other "The status could not be read: $(first_line $tmp/err)"
    out=$(<$tmp/out)
    [[ $out == *$'\n'* ]] || out="Nothing uncommitted. ${out#\#\# }"
    answer "$out" ;;

  (prs)
    gh=( /opt/homebrew/bin/gh(N-*) /usr/local/bin/gh(N-*) )
    (( $#gh )) || fail notFound "The GitHub CLI is not installed: brew install gh, then gh auth login in Terminal"
    dev=$(xcode-select -p 2>/dev/null)
    [[ -n $dev && -d $dev/usr/bin ]] ||
      fail notFound "The GitHub CLI needs Apple’s Command Line Tools: install them in Terminal with xcode-select --install"
    # A clean environment (see Claude Code's below), the developer folder first on its PATH; it never asks anything.
    limited 30 env -i HOME=$HOME USER=$USER LOGNAME=$LOGNAME ${TMPDIR:+TMPDIR=$TMPDIR} PATH="$dev/usr/bin:$PATH" \
      GH_PROMPT_DISABLED=1 NO_COLOR=1 $gh[1] pr status
    case $? in
      (0) answer "$(<$tmp/out)" ;;
      (124) fail timeout "GitHub did not answer in 30 seconds" ;;
      (*) err=$(first_line $tmp/err)
          [[ $err == *(auth\ login|authenticat)* ]] && fail auth "The GitHub CLI is not signed in: run gh auth login in Terminal"
          fail other "gh pr status: ${err:-no answer}" ;;
    esac ;;

  (claude)
    claude=( $HOME/.local/bin/claude(N-*) /opt/homebrew/bin/claude(N-*) /usr/local/bin/claude(N-*) )
    (( $#claude )) || fail notFound "Claude Code is not installed on this Mac (the claude command)"
    # A clean environment — the account's HOME, USER, LOGNAME and TMPDIR, and its own PATH (node for an npm
    # install) — so neither the agent's token, under any of its names, nor the question is in it: the question goes
    # in on stdin. --restricted (newer versions only, so asked for first) also keeps the user's settings and their
    # hooks out and the file tools inside the folder.
    cpath="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
    clean=( env -i HOME=$HOME USER=$USER LOGNAME=$LOGNAME ${TMPDIR:+TMPDIR=$TMPDIR} PATH=$cpath )
    restricted=()
    limited 8 $clean $claude[1] --help &&
      [[ $(<$tmp/out) == *--restricted* ]] && restricted=(--restricted)
    print -r -- "$question" > "$tmp/in"
    left=$(( 50 - (EPOCHREALTIME - started) ))
    limited $left $clean \
      $claude[1] -p $restricted --model haiku --tools Read,Grep,Glob --strict-mcp-config --no-session-persistence \
        --output-format text \
        --append-system-prompt "You answer a question about the project in the current folder. Only read; change nothing. The answer is shown as a phone notification: plain text, no Markdown, a few short lines, in the language of the question."
    case $? in
      (0) out=$(<$tmp/out)
          [[ -n ${out//[[:space:]]/} ]] || out="Claude Code gave no answer."
          answer "$out" ;;
      (124) answer "Claude Code did not answer within 50 seconds. Ask something narrower, or ask it on the Mac." ;;
      (*) err=$(first_line $tmp/err)
          [[ -z $err ]] && err=$(first_line $tmp/out)
          [[ $err == *(login|API\ key|authenticat)* ]] && fail auth "Claude Code is not signed in on this Mac: run claude in Terminal and sign in"
          fail other "Claude Code: ${err:-no answer}" ;;
    esac ;;
esac

call update-button "{\"cellId\":\"$cell\",\"reset\":true}" >/dev/null
exit 0
