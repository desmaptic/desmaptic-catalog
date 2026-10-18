# Branch CI › what the loop, the tap and the long press share: the settings, the GitHub CLI (gh), talking to the agent.
# Functions only, after the button's own setting lines (item.json):
#   "repo=\"\"   # ← …\nbranch=\"\"   # ← …\n@file:common.zsh\n@file:startup.zsh"
#
# The settings, as on the GitHub page: repo — a repository folder on the Mac (a full path or one starting with ~/; gh's
# default repository there) or a GitHub repository as owner/name; branch — empty for the folder's current branch, or
# the repository's default branch for owner/name. A folder needs Apple's Command Line Tools (gh asks the version
# control tool which repository it is); owner/name does not.
#
# Names of repositories, folders and branches never go to the log, nor gh's own words that may hold them: every message
# below is fixed text. gh signs in by itself (gh auth login, once in Terminal): no key on the button. It runs in a
# clean environment — the account's HOME, USER, LOGNAME and TMPDIR, and the system PATH (the Command Line Tools' folder
# first for a repository folder) — so the agent's token never reaches it, and it never asks anything.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
setopt extended_glob
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime zsh/zselect || { print -u2 -- "Branch CI: zsh modules datetime and zselect are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_rm

cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"
own=""                                          # what the loop saw (run, problem) and what the long press armed
[[ -n $DESMAPTIC_STORAGE ]] && own="$DESMAPTIC_STORAGE/gallery/{{CELL_ID}}"
tmp=""
trap '[[ -n $tmp ]] && rm -rf -- "$tmp"' EXIT
trap 'exit 0' TERM INT HUP
tmp=$(mktemp -d) || { print -u2 -- "Branch CI: no room for a temporary folder"; exit 1 }
: > "$tmp/in"

# call <endpoint> <json>: posts to the agent and prints its HTTP code. The token goes in through a descriptor,
# not the command line, where any user of the Mac could read it.
call() {
  curl -q -s -o /dev/null -m 5 -w '%{http_code}' "$api/$1" -H @/dev/fd/3 \
    -H "Content-Type: application/json" --data-binary @- \
    3<<< "Authorization: Bearer $DESMAPTIC_TOKEN" <<< "$2"
}

# poke [look]: tells the loop to draw its face again now (the long press changed it); with "look", to ask GitHub again
# in a moment as well.
poke() {
  [[ -n $own ]] || return 0
  zf_mkdir -p "$own" 2>/dev/null
  print -r -- $EPOCHREALTIME $1 > "$own/poke" 2>/dev/null
  return 0
}

# fail <kind> <message>: the toast after the press says why (/api/error), then the press ends.
fail() {
  poke
  call error "$(jq -nc --arg c "$cell" --arg k "$1" --arg m "$2" '{cellId: $c, kind: $k, message: $m}')" >/dev/null
  print -ru2 -- "Branch CI: $2"
  exit 1
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

# find_gh: gh in $gh, or 0 with the refusal in REPLY (<kind> <message>).
find_gh() {
  gh=( /opt/homebrew/bin/gh(N-*) /usr/local/bin/gh(N-*) )
  (( $#gh )) && return 1
  REPLY="notFound The GitHub CLI isn’t installed. In Terminal, run brew install gh, then gh auth login."
  return 0
}

# resolve: folder (a full path) or slug (owner/name) from the setting $repo, and the branch setting checked; $vcs for a
# folder. 0 with a refusal in REPLY (as find_gh's) when they cannot be used.
resolve() {
  folder="" slug="" vcs=()
  local given=$repo dev
  [[ -n $given ]] || {
    REPLY="config No repository is set. Put its folder or owner/name in the button’s settings, under Advanced."
    return 0
  }
  case $given in
    '~')   given=$HOME ;;
    '~/'*) given=$HOME/${given#'~/'} ;;
  esac
  if [[ $given == /* ]]; then
    [[ -d $given ]] || { REPLY="notFound The repository folder in the button’s settings doesn’t exist. Check the path there."; return 0 }
    folder=${given:a}
    # gh asks the version control tool which repository a folder is. A stock Mac has only a stub that opens an
    # install dialog: it is never called, and without the Command Line Tools the button says what to install.
    dev=$(xcode-select -p 2>/dev/null)
    vcs=( ${dev:+$dev/usr/bin/git(N-*)} )
    (( $#vcs )) || {
      REPLY="notFound A repository folder needs Apple’s Command Line Tools. Install them in Terminal with xcode-select --install, or set owner/name instead."
      return 0
    }
  elif [[ $given == [A-Za-z0-9-]##/[A-Za-z0-9._-]## ]]; then
    slug=$given
  else
    REPLY="config The repository in the button’s settings is neither a folder nor owner/name. A folder starts with / or ~/."
    return 0
  fi
  if [[ -n $branch && ( $branch != [A-Za-z0-9._/+@-]## || $branch == [-/.]* ) ]]; then
    REPLY="config The branch in the button’s settings isn’t a valid branch name."
    return 0
  fi
  return 1
}

# run_gh <seconds> <arguments…>: gh in the repository — in its folder, or with -R owner/name. Output as limited's.
run_gh() {
  local seconds=$1; shift
  local -a args=( "$@" )
  local search=$PATH
  [[ -n $slug ]] && args+=( -R $slug )
  if [[ -n $folder ]]; then
    builtin cd -q -- "$folder" 2>/dev/null || { : > "$tmp/err"; return 1 }
    search="${vcs[1]:h}:$PATH"
  fi
  limited $seconds env -i HOME=$HOME USER=$USER LOGNAME=$LOGNAME ${TMPDIR:+TMPDIR=$TMPDIR} PATH="$search" \
    GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 NO_COLOR=1 $gh[1] "${args[@]}"
}

# refusal <status>: REPLY = <kind> <message> for a gh call that failed, in fixed words. The words are looked for in all
# gh said: it prints GitHub's answer after its own, and the part that names the reason may come after an address.
# The order matters: gh names "gh auth login" in other errors too (a folder whose remotes are not on GitHub), so only
# its sure signs of a missing sign-in come first, and the loose words last.
refusal() {
  local all=$(<$tmp/err)
  if (( $1 == 124 )); then
    REPLY="timeout GitHub didn’t answer in time."
  elif (( $1 == 4 )) || [[ $all == *(401\ Unauthorized|Bad\ credentials)* ]]; then
    REPLY="auth The GitHub CLI isn’t signed in. Run gh auth login in Terminal."
  elif [[ $all == *(no\ git\ remotes|not\ a\ git\ repository|none\ of\ the\ git\ remotes|known\ GitHub\ host|could\ not\ determine)* ]]; then # not a call: gh's error text
    REPLY="config The folder in the button’s settings isn’t a GitHub repository."
  elif [[ $all == *(No\ default\ remote|set-default)* ]]; then
    REPLY="config The folder’s repository has several remotes. Choose the GitHub one in Terminal with gh repo set-default."
  elif [[ $all == *[Rr]ate\ limit* ]]; then
    REPLY="busy You’ve hit GitHub’s request limit for now. The button tries again in a few minutes."
  elif [[ $all == *over\ a\ month* ]]; then
    REPLY="other This run is too old to rerun. GitHub allows reruns for a month."
  elif [[ $all == *(Unable\ to\ retry|cannot\ be\ re[rt]*)* ]]; then
    REPLY="other GitHub won’t rerun this run."
  elif [[ $all == *(Could\ not\ resolve\ to\ a\ Repository|HTTP\ 404)* ]]; then
    REPLY="notFound Your GitHub account can’t see this repository. Check the name, or sign in to gh with another account."
  elif [[ $all == *(Must\ have\ admin\ rights|HTTP\ 403|Resource\ not\ accessible|[Pp]ermission)* ]]; then
    REPLY="permission Your GitHub account isn’t allowed to do that in this repository."
  elif [[ $all == *(error\ connecting|dial\ tcp|no\ such\ host|TLS\ handshake|connection\ refused|connection\ reset|i/o\ timeout|EOF)* ]]; then
    REPLY="network The Mac can’t reach GitHub. Check its internet connection."
  elif [[ $all == *(HTTP\ 5[0-9][0-9]|status\ code:\ 5[0-9][0-9])* ]]; then
    REPLY="network GitHub is having trouble right now."
  elif [[ $all == *(auth\ login|authenticat)* ]]; then
    REPLY="auth The GitHub CLI isn’t signed in. Run gh auth login in Terminal."
  else
    REPLY="other The GitHub CLI failed with status $1."
  fi
}

# read_run: the run the loop saw last (gallery/{{CELL_ID}}/run) into the associative array run.
typeset -A run
read_run() {
  run=()
  local line
  [[ -n $own && -f $own/run ]] || return 0
  for line in ${(f)"$(<$own/run)"}; do run[${line%%=*}]=${line#*=}; done
}

# loop_said: a press ends with what the loop's grey face means — gh missing, or the reason the loop last could not look
# (gallery/{{CELL_ID}}/problem).
loop_said() {
  local said=""
  find_gh && fail ${REPLY%% *} "${REPLY#* }"
  [[ -n $own && -f $own/problem ]] && IFS= read -r said < "$own/problem" 2>/dev/null
  [[ -n $said ]] && fail ${said%% *} "${said#* }"
  return 0
}
