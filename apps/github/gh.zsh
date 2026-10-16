# GitHub › what the page's scripts share: the repository setting, the GitHub CLI (gh) and talking to the agent.
# Settings and functions only; each button's own file follows it (app.json):
#   "repo=\"\"   # ← …\n@file:gh.zsh\n@file:merge.zsh"
#
# The setting: repo — a repository folder on the Mac (a full path or one starting with ~/; gh's default repository
# there, its current branch) or a GitHub repository as owner/name (its default branch; nothing that needs a local
# branch). A button whose setting is empty takes the repository last set on any GitHub button — one for the whole
# agent, whatever page or profile the button is on (gallery/github/repo); with none set yet it refuses and says where
# to set it. Merge When Green never takes it (merge.zsh). gh signs in by itself (gh auth login,
# once in Terminal): no key on the button.
#
# gh runs in a clean environment — the account's HOME, USER, LOGNAME and TMPDIR, and a PATH with the Command Line
# Tools' folder first, where gh finds the version control tool — so the agent's token, under any of its names, never
# reaches it or what it starts. It never asks anything (GH_PROMPT_DISABLED): what it would ask, the button refuses.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
setopt extended_glob
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime zsh/zselect || { print -u2 -- "GitHub: zsh modules datetime and zselect are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_rm

cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"
own=""                                          # this button's state: what its loop saw, what its long press armed
shared=""                                       # what the page's buttons share: the repository last set
if [[ -n $DESMAPTIC_STORAGE ]]; then
  own="$DESMAPTIC_STORAGE/gallery/{{CELL_ID}}"
  shared="$DESMAPTIC_STORAGE/gallery/github"
fi
tmp=""
trap '[[ -n $tmp ]] && rm -rf -- "$tmp"' EXIT
trap 'exit 0' TERM INT HUP
tmp=$(mktemp -d) || { print -u2 -- "GitHub: no room for a temporary folder"; exit 1 }
: > "$tmp/in"

# call <endpoint> <json>: posts to the agent and prints its HTTP code. The token goes in through a descriptor,
# not the command line, where any user of the Mac could read it.
call() {
  curl -q -s -o /dev/null -m 5 -w '%{http_code}' "$api/$1" -H @/dev/fd/3 \
    -H "Content-Type: application/json" --data-binary @- \
    3<<< "Authorization: Bearer $DESMAPTIC_TOKEN" <<< "$2"
}

# poke: tells the button's own loop (if it has one) to look again now and to show its face again.
poke() {
  [[ -n $own ]] || return 0
  zf_mkdir -p "$own" 2>/dev/null
  print -r -- $EPOCHSECONDS > "$own/poke" 2>/dev/null
  return 0
}

# fail <kind> <message>: the toast after the press says why (/api/error), then the press ends.
fail() {
  call update-button "{\"cellId\":\"$cell\",\"reset\":true}" >/dev/null
  poke
  call error "$(jq -nc --arg c "$cell" --arg k "$1" --arg m "$2" '{cellId: $c, kind: $k, message: $m}')" >/dev/null
  print -ru2 -- "GitHub: $2"
  exit 1
}

# flash <icon> [title]: shows it on the button for 3 seconds, then the button's own face again.
flash() {
  call update-button "$(jq -nc --arg c "$cell" --arg i "$1" --arg t "${2-}" \
    '{cellId: $c, icon: $i} + (if $t == "" then {} else {title: $t} end)')" >/dev/null
  sleep 3
  call update-button "{\"cellId\":\"$cell\",\"reset\":true}" >/dev/null
  poke
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

# open_url <url>: opens it in the default browser. env -i: the browser gets the account's own environment, as from
# the Dock, not the agent's token.
open_url() {
  [[ $1 == https://* ]] || fail other "GitHub gave no address to open"
  env -i /usr/bin/open -- "$1" || fail other "The browser did not open $1"
}

# problem <reason>: why gh is not usable (sets REPLY: <kind> <message>), or 1 when it is. Shared with the loops,
# which show it on the face instead of ending.
problem() {
  local dev
  gh=( /opt/homebrew/bin/gh(N-*) /usr/local/bin/gh(N-*) )
  (( $#gh )) || { REPLY="notFound The GitHub CLI is not installed: brew install gh, then gh auth login in Terminal"; return 0 }
  # gh asks the version control tool which repository a folder is. A stock Mac has only a stub that opens an
  # install dialog: it is never called, and without the Command Line Tools the button says what to install.
  dev=$(xcode-select -p 2>/dev/null)
  vcs=( ${dev:+$dev/usr/bin/git(N-*)} )
  (( $#vcs )) || { REPLY="notFound This button needs Apple’s Command Line Tools: install them in Terminal with xcode-select --install"; return 0 }
  return 1
}

# resolve: folder (a full path) or slug (owner/name) from the setting $repo, or a refusal in REPLY (as problem's).
# An empty setting takes the one last set on any GitHub button; a set one becomes it.
resolve() {
  folder="" slug=""
  local given=$repo
  if [[ -z $given && -n $shared && -f $shared/repo ]]; then
    IFS= read -r given < "$shared/repo"
  elif [[ -n $given && -n $shared ]]; then
    # written when this button's setting changes, not on every look of a loop: "last set" stays the last one set
    local mine=""
    [[ -f $own/repo ]] && IFS= read -r mine < "$own/repo"
    if [[ $mine != "$given" ]]; then
      zf_mkdir -p "$shared" "$own" 2>/dev/null
      print -r -- "$given" > "$shared/repo" 2>/dev/null
      print -r -- "$given" > "$own/repo" 2>/dev/null
    fi
  fi
  [[ -n $given ]] || {
    REPLY="config No repository set: put a folder or owner/name in this button’s settings (under Advanced on CI and My PRs), e.g. repo=\"~/Developer/my-app\""
    return 0
  }
  case $given in
    '~')   given=$HOME ;;
    '~/'*) given=$HOME/${given#'~/'} ;;
  esac
  if [[ $given == /* ]]; then
    [[ -d $given ]] || { REPLY="notFound No such folder: $given"; return 0 }
    folder=${given:a}
  elif [[ $given == [A-Za-z0-9-]##/[A-Za-z0-9._-]## ]]; then
    slug=$given
  else
    REPLY="config Not a folder or owner/name: $given (a folder starts with / or ~/)"
    return 0
  fi
  return 1
}

# ready: problem and resolve, or the press ends with their refusal.
ready() {
  problem && fail ${REPLY%% *} "${REPLY#* }"
  resolve && fail ${REPLY%% *} "${REPLY#* }"
}

# loop_said: the press of a button with a loop (CI, My PRs) ends with what the loop's grey triangle means — gh
# missing, as every press says it, or the reason the loop last could not look (gallery/{{CELL_ID}}/problem).
loop_said() {
  local said=""
  problem && fail ${REPLY%% *} "${REPLY#* }"
  [[ -n $own && -f $own/problem ]] && IFS= read -r said < "$own/problem" 2>/dev/null
  [[ -n $said ]] && fail ${said%% *} "${said#* }"
  return 0
}

# run_gh <seconds> <arguments…>: gh in the repository — in its folder, or with -R owner/name. Output as limited's.
run_gh() {
  local seconds=$1; shift
  local -a args=( "$@" )
  if [[ -n $slug && $args[1,2] == "repo view" ]]; then
    args[3,0]=( $slug )                         # gh repo view takes the repository as its argument, not -R
  elif [[ -n $slug && $args[1] != api ]]; then  # gh api has no -R: its callers name the repository themselves
    args+=( -R $slug )
  fi
  if [[ -n $folder ]]; then
    builtin cd -q -- "$folder" 2>/dev/null || { print -r -- "The folder cannot be opened: $folder" > "$tmp/err"; return 1 }
  fi
  limited $seconds env -i HOME=$HOME USER=$USER LOGNAME=$LOGNAME ${TMPDIR:+TMPDIR=$TMPDIR} PATH="${vcs[1]:h}:$PATH" \
    GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 NO_COLOR=1 $gh[1] "${args[@]}"
}

# gh_refusal <status> <what>: REPLY = <kind> <message> for a gh call that failed — gh's own words when they say
# nothing better known.
gh_refusal() {
  local err=$(first_line $tmp/err)
  case $1 in
    (124) REPLY="timeout GitHub did not answer in time" ;;
    (*)   case $err in
            (*(auth\ login|authenticat)*) REPLY="auth The GitHub CLI is not signed in: run gh auth login in Terminal" ;;
            (*(no\ git\ remotes|not\ a\ git\ repository|could\ not\ determine|none\ of\ the\ git\ remotes)*) # not a call: gh's error text
              REPLY="config ${folder:-$slug} is not a GitHub repository: set the folder of one" ;;
            (*[Rr]ate\ limit*)
              REPLY="busy GitHub’s limit of questions is used up for now: try again in a few minutes" ;;
            (*(Must\ have\ admin\ rights|HTTP\ 403|Resource\ not\ accessible|[Pp]ermission)*)
              REPLY="permission This GitHub account may not do that here: ${err}" ;;
            (*(Could\ not\ resolve\ to\ a\ Repository|HTTP\ 404)*)
              REPLY="notFound GitHub has no repository ${slug:-there} that this account can see" ;;
            (*(error\ connecting|dial\ tcp|no\ such\ host|TLS\ handshake|connection\ refused)*)
              REPLY="network GitHub cannot be reached: ${err}" ;;
            (*) REPLY="other $2: ${err:-no answer}" ;;
          esac ;;
  esac
}

# current_branch: REPLY = the folder's current branch, or 1 with a refusal in REPLY (as problem's).
current_branch() {
  [[ -n $folder ]] || { REPLY="config This button needs the repository’s folder, not owner/name: set repo=\"~/…\""; return 1 }
  limited 10 $vcs -C "$folder" symbolic-ref -q --short HEAD
  (( $? == 0 )) || { REPLY="config $folder is on no branch (a detached HEAD, or not a repository)"; return 1 }
  REPLY=$(first_line $tmp/out)
}

# branch: REPLY = the folder's current branch, or the press ends with the refusal.
branch() {
  current_branch || fail ${REPLY%% *} "${REPLY#* }"
}
