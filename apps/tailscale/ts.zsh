# Tailscale › what the page's scripts share: finding the Tailscale CLI, reading the status, and talking to the agent.
# Functions only; each button's own file follows it (app.json):
#   "action=down\n@file:ts.zsh\n@file:action.zsh"
#
# The CLI is the app's own program, run as the CLI (TAILSCALE_BE_CLI=1): the standalone build (io.tailscale.ipn.macsys)
# and the App Store one (io.tailscale.ipn.macos) both have it, in /Applications or ~/Applications. Without the app,
# the command the app installs (/usr/local/bin/tailscale) or Homebrew's. It runs in a clean environment — the account's
# HOME, USER, LOGNAME and TMPDIR and a stock PATH — so the agent's token never reaches it, and with nothing on its
# input, so it never waits for an answer: what it would ask, the button refuses.
#
# Of `tailscale status --json` only BackendState, Self.Online and the exit node (ExitNodeStatus, the peer marked
# ExitNode, how many offer to be one) are read: the rest of the format may change between versions.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
setopt extended_glob
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime zsh/zselect || { print -u2 -- "Tailscale: zsh modules datetime and zselect are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_rm

cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"
shared=""                                       # what the page's buttons share: the last status read, their poke
[[ -n $DESMAPTIC_STORAGE ]] && shared="$DESMAPTIC_STORAGE/gallery/tailscale"
tmp=""
trap '[[ -n $tmp ]] && rm -rf -- "$tmp"' EXIT
trap 'exit 0' TERM INT HUP
tmp=$(mktemp -d) || { print -u2 -- "Tailscale: no room for a temporary folder"; exit 1 }
: > "$tmp/in"

# call <endpoint> <json>: posts to the agent and prints its HTTP code. The token goes in through a descriptor,
# not the command line, where any user of the Mac could read it.
call() {
  curl -q -s -o /dev/null -m 5 -w '%{http_code}' "$api/$1" -H @/dev/fd/3 \
    -H "Content-Type: application/json" --data-binary @- \
    3<<< "Authorization: Bearer $DESMAPTIC_TOKEN" <<< "$2"
}

# poke: tells every Tailscale button's loop to look again now (the status changed) and to show its face again.
poke() {
  [[ -n $shared ]] || return 0
  zf_mkdir -p "$shared" 2>/dev/null
  zf_rm -f "$shared/status" 2>/dev/null       # what was read before the press is no longer so
  print -r -- $EPOCHREALTIME > "$shared/poke" 2>/dev/null
  return 0
}

# fail <kind> <message>: the toast after the press says why (/api/error), then the press ends.
fail() {
  call update-button "{\"cellId\":\"$cell\",\"reset\":true}" >/dev/null
  poke
  call error "$(jq -nc --arg c "$cell" --arg k "$1" --arg m "$2" '{cellId: $c, kind: $k, message: $m}')" >/dev/null
  print -ru2 -- "Tailscale: $2"
  exit 1
}

# flash <seconds> <colour> <icon> [title]: shows it on the button for a while, then the button's own face again.
flash() {
  call update-button "$(jq -nc --arg c "$cell" --arg k "$2" --arg i "$3" --arg t "${4-}" \
    '{cellId: $c, color: $k, icon: $i} + (if $t == "" then {} else {title: $t} end)')" >/dev/null
  sleep $1
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

# first_line <file>: the first non-empty line of a file that is not the CLI's own log (a time stamp, then the
# message), at most 200 characters (counted in UTF-8).
first_line() {
  local line LC_ALL=en_US.UTF-8
  for line in "${(@f)$(<$1)}"; do
    [[ $line == [0-9][0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9]\ * ]] && continue
    if [[ -n ${line//[[:space:]]/} ]]; then
      (( ${#line} > 200 )) && line="${line[1,199]}…"
      print -r -- "$line"
      return
    fi
  done
}

# find_cli: sets ts (the CLI and how to run it) and app (the app's bundle id, empty without the app), or 1 when
# Tailscale is not installed.
ts=() app=""
find_cli() {
  local bundle id
  ts=() app=""
  for bundle in /Applications/Tailscale.app(N/) $HOME/Applications/Tailscale.app(N/); do
    [[ -x $bundle/Contents/MacOS/Tailscale ]] || continue
    id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist" 2>/dev/null)
    [[ $id == io.tailscale.ipn.mac(sys|os) ]] || continue
    ts=( TAILSCALE_BE_CLI=1 $bundle/Contents/MacOS/Tailscale ) app=$id
    return 0
  done
  ts=( /usr/local/bin/tailscale(N-*) /opt/homebrew/bin/tailscale(N-*) )
  (( $#ts )) || return 1
  ts=( $ts[1] )
  return 0
}

# need_cli: find_cli, or the press ends saying what to install.
need_cli() {
  find_cli || fail notFound "Tailscale is not installed: get it from tailscale.com or the App Store, then sign in"
}

# app_running: 0 while the Tailscale app runs (or there is no app to ask about: the CLI's own service then).
app_running() {
  [[ -n $app ]] || return 0
  [[ $(lsappinfo info -only pid -app $app 2>/dev/null) == *=<1->* ]]
}

# run_ts <seconds> <arguments…>: the CLI with them. Output as limited's.
run_ts() {
  local seconds=$1; shift
  limited $seconds env -i HOME=$HOME USER=$USER LOGNAME=$LOGNAME ${TMPDIR:+TMPDIR=$TMPDIR} PATH=$PATH \
    $ts "$@"
}

# ts_refusal <status> <what>: REPLY = <kind> <message> for a CLI call that failed — the CLI's own words when they
# say nothing better known.
ts_refusal() {
  local err=$(first_line $tmp/err)
  [[ -n $err ]] || err=$(first_line $tmp/out)
  case $1 in
    (124) REPLY="timeout Tailscale did not answer in time" ;;
    (*)   case $err in
            (*(failed\ to\ connect\ to\ local\ Tailscale|is\ Tailscale\ running|Tailscale\ is\ not\ running)*)
              REPLY="notRunning Tailscale is not running: open it on the Mac" ;;
            (*reason\ required*)
              REPLY="permission Your organization asks for a reason to turn Tailscale off: turn it off from Tailscale’s menu on the Mac, which asks for one" ;;
            (*always-on*)
              REPLY="permission Your organization keeps Tailscale always on: it can’t be turned off" ;;
            (*accept-risk*)
              REPLY="other Tailscale wants you to confirm this on the Mac: ${err}" ;;
            (*(not\ logged\ in|NeedsLogin|log\ in)*)
              REPLY="auth Tailscale is signed out: sign in from its menu on the Mac" ;;
            (*) REPLY="other $2: ${err:-no answer}" ;;
          esac ;;
  esac
}

# status [fresh]: reads the status — sets state (BackendState: Running, Stopped, NeedsLogin, NeedsMachineAuth,
# Starting…), online (true when Tailscale's coordination server sees this Mac), exit_online (true/false, - with no exit
# node), exit_name (the exit node's name, - with none) and offers (how many devices offer to be an exit node). 1 with a
# refusal in REPLY (as ts_refusal's). The loops share one read (gallery/tailscale/status), stamped with the time the
# CLI was asked: another loop takes it for 5 seconds, unless a press came after that time — an answer that was on its
# way during the press is stale. A press reads fresh: it acts on what is, not on what a loop saw.
state="" online="" exit_online="" exit_name="" offers=""
status() {
  local row rc at asked poked=0
  if [[ $1 != fresh && -n $shared && -f $shared/status ]]; then
    { IFS= read -r at; IFS= read -r row } < "$shared/status" 2>/dev/null
    [[ -f $shared/poke ]] && IFS= read -r poked < "$shared/poke" 2>/dev/null
    [[ $poked == <->(.<->|) ]] || poked=0
    if [[ $at == <->.<-> && -n $row ]] && (( at > poked && EPOCHREALTIME - at < 5 )); then
      read -r state online exit_online offers exit_name <<< "$row"
      return 0
    fi
  fi
  asked=$EPOCHREALTIME
  run_ts 10 status --json
  rc=$?
  if (( rc != 0 )); then ts_refusal $rc "tailscale status"; return 1; fi
  # "-" for an empty field: read would close the gap; the name goes last, as it may hold spaces
  row=$(jq -r '[
      (.BackendState // ""),
      (.Self.Online // false | tostring),
      (if .ExitNodeStatus == null then "" else (.ExitNodeStatus.Online // false | tostring) end),
      ([.Peer // {} | .[] | select(.ExitNodeOption == true)] | length | tostring),
      ([.Peer // {} | .[] | select(.ExitNode == true)
        | if (.DNSName // "") != "" then (.DNSName | split(".")[0]) else (.HostName // "") end][0] // "")
    ] | map(if . == "" then "-" else . end) | join(" ")' "$tmp/out" 2>/dev/null)
  read -r state online exit_online offers exit_name <<< "$row"
  [[ -n $state && $state != - ]] || { REPLY="other Tailscale gave a status this button cannot read"; return 1; }
  if [[ -n $shared ]]; then
    zf_mkdir -p "$shared" 2>/dev/null
    print -rl -- $asked "$row" > "$shared/status.$$" 2>/dev/null && mv -f "$shared/status.$$" "$shared/status" 2>/dev/null
  fi
  return 0
}

# over_tailscale: 0 when a phone reaches this Mac through Tailscale right now — the agent (the program that listens
# on its port for scripts, 9848) has a connection from an address of a tailnet: IPv4 in 100.64/10 (100.64 to
# 100.127), IPv6 under Tailscale's prefix /48 (its first three groups fd7a, 115c, a1e0). 2 when that cannot be told.
tailnet6=( fd7a 115c a1e0 )
over_tailscale() {
  local line remote agent="" listens=0
  local -a groups
  for line in "${(@f)$(lsof -nP -iTCP@127.0.0.1:9848 -sTCP:LISTEN -Fp 2>/dev/null)}"; do
    [[ $line == p<1-> ]] && { agent=${line#p}; break }
  done
  [[ -n $agent ]] || return 2
  for line in "${(@f)$(lsof -nP -a -p $agent -iTCP -FnT 2>/dev/null)}"; do
    case $line in
      (TST=LISTEN) listens=1 ;;
      (n*-\>*)
        remote=${${line#*->}%:*}                # the remote address without its port, [ ] and an IPv4 one's ::ffff:
        remote=${${remote#\[}%\]}
        remote=${remote#(#i)::ffff:}
        groups=( ${(Ls.:.)remote} )
        [[ $remote == *:* && $groups[1,3] == "$tailnet6" ]] && return 0
        if [[ $remote == (#b)100.([0-9]##).[0-9]##.[0-9]## ]] && (( match[1] >= 64 && match[1] <= 127 )); then
          return 0
        fi ;;
    esac
  done
  (( listens )) || return 2                     # the agent's own listening socket missing: nothing was seen
  return 1
}

# guard <what>: the press ends when what it does would cut a phone that reaches the Mac through Tailscale.
guard() {
  over_tailscale
  case $? in
    (0) fail permission "Your phone reaches this Mac through Tailscale: $1 would cut it off, and it couldn’t undo it. Turn Tailscale off on the phone to connect over Wi-Fi first, or do it on the Mac" ;;
    (2) fail other "This button couldn’t tell whether your phone reaches the Mac through Tailscale, so it did nothing: do it on the Mac" ;;
  esac
}
