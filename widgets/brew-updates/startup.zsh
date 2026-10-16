# Homebrew updates: how many installed Homebrew packages have a newer version, under a beer mug glyph (1×1 SVG face).
# The startup script is this file (item.json); the tap (tap.zsh) asks for brew upgrade, the long press (hold.zsh) for
# a fresh look. Both only leave a file in $dir: this loop is the only one that runs brew and draws the face.
#
# The count is brew outdated (formulae and casks, the same list brew upgrade takes; pinned formulae are left out, as
# brew upgrade leaves them). brew outdated compares with the package list Homebrew fetched last and never fetches it
# itself here (HOMEBREW_NO_AUTO_UPDATE), so this loop runs brew update before each look: every 6 hours, and only while
# the button is on screen; off screen nothing runs, only a look at the phone every 5 s. A long press looks at once.
# brew update changes only Homebrew's own list of versions, never an installed package. The last count is kept in
# $dir/state, so a reconnected phone gets it at once and no look runs before its time.
#
# The upgrade (a tap, confirmed on the phone) runs in a Terminal window on the Mac, not in this loop. The agent stops
# this loop whenever the phone goes away (its app is suspended soon after it leaves the screen), on a profile switch
# and on an edit, and brew stopped in the middle of a package can leave it broken — a cask's app already taken out of
# /Applications, a formula unlinked: Homebrew rolls back on an error, never on a signal. In Terminal it goes on
# whatever the phone does, in sight. This loop writes $dir/upgrade.command — one brew upgrade per package, the
# formulae first, then every outdated cask but those that install a macOS package (a pkg or installer artifact, or
# pkgutil/kext in their uninstall): those ask for the Mac's password, so they are skipped and named — opens it with
# env -i /usr/bin/open (Terminal gets the account's own environment, never the agent's token) and follows it through
# the files it leaves: upgrade.pid, upgrade.now (the package at work), upgrade.done (how each one went), upgrade.end.
# Anything else that wants a password fails at once (SUDO_ASKPASS=/usr/bin/false, no stdin) instead of waiting.
# While it runs the face counts down the packages left, with a ring of the share done, and the Mac is kept awake
# (/api/keep-awake, 3 hours at most). A notification on the phone and the Mac tells how it ended — the next start
# does, when the loop was away at the end. A window closed in the middle stops brew inside one package: the
# notification names it with the command that repairs it (brew reinstall). Notifications carry no sentences, only
# symbols, package names and commands, the same in every language.
#
# brew runs in a clean environment — the account's HOME, USER, LOGNAME and TMPDIR and the system PATH — so the agent's
# token never reaches it; Homebrew's own settings (brew.env) still apply.
# Without Homebrew the glyph turns grey with "—" and the phone says what to do (/api/error). A failed look keeps the
# last count, and its reason goes to the phone; after a day without a count the face is grey "—" as well.
#
# Every frame has the same 9 elements in the same order: the glyph glides between them.
# `zsh startup.zsh --face <rest|none|count|problem|run> [number] [done] [total]` prints one frame (rest.svg and demo.svg
# are made that way). `zsh startup.zsh --count` prints what a look would find ("outdated: …", "password: …") without
# brew update and without the agent: it only reads.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
setopt extended_glob
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT HUP                      # an upgrade in Terminal goes on without this loop

# MARK: - Face

# brew_frame <state> [number] [done] [total]. rest: the mug alone, large (the face before the script runs); none: all
# up to date ("0" under a calm, dim mug); count: packages to update (the number under a lit mug); problem: no count
# (a grey mug over "—"); run: an upgrade runs (the packages left under a blue mug, a ring of done out of total).
brew_frame() {
  emulate -L zsh
  export LC_ALL=C
  local state=${1:-rest} number=${2:-0} done=${3:-0} total=${4:-0} value
  [[ $state == (rest|none|count|problem|run) ]] || state=rest
  [[ $number == <-> ]] || number=0
  [[ $done == <-> ]] || done=0
  [[ $total == <-> ]] || total=0
  (( number > 99 )) && value="99+" || value=$number
  [[ $state == (rest|none) ]] && value=0        # never an empty <text>: the structure must not change
  [[ $state == problem ]] && value="—"
  awk -v st=$state -v val="$value" -v d=$done -v t=$total '
    function f(x) { return sprintf("%.2f", x) }
    BEGIN {
      # gradient ends; glyph opacity; bloom colour and opacity; value opacity and size; glyph placement and scale;
      # ring opacity and the lit share of it
      c1 = "#FFD60A"; c2 = "#FF9F0A"; gO = 0.90; gC = "#FF9F0A"; gA = 0.12; vO = 0; vs = 60
      tx = 100; ty = 100; sc = 1; rO = 0; share = 0
      if (st != "rest")    { ty = 58; sc = 0.70 }
      if (st == "none")    { gO = 0.50; gA = 0.05; vO = 0.60 }
      if (st == "count")   { gO = 1; gA = 0.30; vO = 1 }
      if (st == "problem") { c1 = "#8E8E93"; c2 = "#636366"; gO = 0.70; gC = "#8E8E93"; gA = 0.04; vO = 0.60 }
      if (st == "run")     { c1 = "#64D2FF"; c2 = "#5E5CE6"; gO = 1; gC = "#64D2FF"; gA = 0.22; vO = 1; rO = 1
                             share = (t > 0) ? d / t : 0; if (share > 1) share = 1 }
      if (val == "99+") vs = 48
      L = 552.92                                # the ring: 2π · 88

      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\"><defs>"
      printf "<linearGradient id=\"mugG\" gradientUnits=\"userSpaceOnUse\" x1=\"10\" y1=\"5\" x2=\"90\" y2=\"95\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></linearGradient>", c1, c2
      printf "<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.55\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient></defs>", gC, f(gA), gC, f(gA * 0.35), gC
      printf "<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"92\" fill=\"url(#bloomG)\"/>"
      printf "<circle id=\"track\" cx=\"100\" cy=\"100\" r=\"88\" fill=\"none\" stroke=\"#FFFFFF\" stroke-width=\"6\" opacity=\"%s\"/>", f(rO * 0.12)
      printf "<circle id=\"ring\" cx=\"100\" cy=\"100\" r=\"88\" fill=\"none\" stroke=\"#64D2FF\" stroke-width=\"6\" stroke-linecap=\"round\" stroke-dasharray=\"%s 600\" transform=\"rotate(-90 100 100)\" opacity=\"%s\"/>", f(L * share), f(rO)
      # the glyph, drawn in a 100×100 box: a mug with a handle on the right, foam on top, two lines down its side
      printf "<g id=\"glyph\" transform=\"translate(%s %s) scale(%s)\" fill=\"none\" stroke=\"url(#mugG)\" stroke-opacity=\"%s\" stroke-width=\"8\" stroke-linecap=\"round\" stroke-linejoin=\"round\">", f(tx - 50 * sc), f(ty - 50 * sc), f(sc), f(gO)
      printf "<path id=\"foam\" d=\"M 14 36 Q 8 22 22 19 Q 26 7 39 11 Q 48 3 58 11 Q 71 8 72 21 Q 80 26 74 36\"/>"
      printf "<path id=\"body\" d=\"M 18 36 L 21 84 Q 22 92 30 92 L 59 92 Q 67 92 68 84 L 71 36 Z\"/>"
      printf "<path id=\"handle\" d=\"M 71 48 L 79 48 Q 89 48 89 58 L 89 66 Q 89 76 79 76 L 69 76\"/>"
      printf "<path id=\"lines\" d=\"M 36 52 L 37 76 M 53 52 L 52 76\"/>"
      printf "</g>"
      printf "<text id=\"value\" x=\"100\" y=\"150\" font-size=\"%d\" font-weight=\"700\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" opacity=\"%s\">%s</text>", vs, f(vO), val
      printf "</svg>\n"
    }'
}

if [[ $1 == --face ]]; then
  shift
  brew_frame "$@"
  exit 0
fi

# MARK: - What runs

zmodload zsh/datetime zsh/zselect || { print -u2 -- "Homebrew updates: zsh modules datetime/zselect are missing"; exit 1 }
zmodload -F zsh/files b:zf_chmod b:zf_mkdir b:zf_mv b:zf_rm || { print -u2 -- "Homebrew updates: zsh module files is missing"; exit 1 }
zmodload -F zsh/stat b:zstat || { print -u2 -- "Homebrew updates: zsh module stat is missing"; exit 1 }

cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"
period=21600                                    # seconds between looks while the button is on screen: 6 hours
retry=900                                       # … after a failed one
stale=86400                                     # seconds after the last count when a failing look greys it out
again=600                                       # seconds a face that did not change is posted again while on screen

tmp=""
trap '[[ -n $tmp ]] && rm -rf -- "$tmp"' EXIT
tmp=$(mktemp -d) || { print -u2 -- "Homebrew updates: no room for a temporary folder"; exit 1 }
: > "$tmp/in"

# brew in a clean environment: no auto-update (the loop decides when), no hints, no colours, no questions.
brewing=( env -i HOME=$HOME USER=$USER LOGNAME=$LOGNAME ${TMPDIR:+TMPDIR=$TMPDIR} PATH="$PATH"
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_COLOR=1 NONINTERACTIVE=1 )

find_brew() {   # REPLY = the brew program; 1 when Homebrew is not installed
  local -a found
  found=( /opt/homebrew/bin/brew(N-*) /usr/local/bin/brew(N-*) )
  (( $#found )) || return 1
  REPLY=$found[1]
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

# count: the outdated packages by Homebrew's last list. Sets n (all of them), formulae (the formulae an upgrade
# takes), casks (the casks it takes) and locked (the casks that ask for the Mac's password). 1 when brew failed:
# then why_kind and why say how, and brew_err is brew's own words (or the time it was given).
n=0 formulae=() casks=() locked=() brew_err=""
count() {
  local rc name line
  local -a all lines
  local -A asks
  brew_err=""
  limited 120 $brewing $brew outdated --json=v2
  rc=$?
  if (( rc )); then
    brew_err=$(first_line $tmp/err)
    why_kind=other why="brew outdated failed: $brew_err"
    (( rc == 124 )) && why_kind=timeout why="brew outdated took longer than 2 minutes" brew_err="⏱ 120 s"
    return 1
  fi
  lines=( "${(@f)$(jq -r '"list", (.formulae[] | select(.pinned | not) | "formula \(.name)"), (.casks[] | "cask \(.name)")' $tmp/out 2>/dev/null)}" )
  if [[ $lines[1] != list ]]; then
    why_kind=other why="brew outdated gave no list"
    return 1
  fi
  formulae=()
  for line in $lines[2,-1]; do
    name=${line#* }
    [[ $name == [a-z0-9][a-z0-9@._+/-]# ]] || continue   # a name goes into a command line: nothing else in it
    if [[ $line == formula\ * ]]; then formulae+=( $name ); else all+=( $name ); fi
  done
  # A cask that installs a macOS package asks for the password on upgrade: a pkg or installer artifact, or pkgutil or
  # kext in its uninstall. When brew cannot tell, every cask is taken for one.
  if (( $#all )); then
    if limited 60 $brewing $brew info --cask --json=v2 $all; then
      for name in ${(f)"$(jq -r '.casks[] | select(([.artifacts[] | keys[]] | any(. == "pkg" or . == "installer"))
          or ([.artifacts[] | .uninstall? // empty | .[]? | objects | keys[]] | any(. == "pkgutil" or . == "kext")))
          | .token' $tmp/out 2>/dev/null)"}; do
        asks[$name]=1
      done
    else
      for name in $all; do asks[${name:t}]=1; done
    fi
  fi
  casks=() locked=()
  for name in $all; do
    (( ${+asks[${name:t}]} )) && locked+=( $name ) || casks+=( $name )
  done
  n=$(( $#formulae + $#all ))
  return 0
}

if [[ $1 == --count ]]; then
  find_brew || { print -u2 -- "Homebrew is not installed"; exit 1 }
  brew=$REPLY
  count || { print -u2 -- "$why"; exit 1 }
  print -r -- "outdated: $n (formulae $#formulae, casks $(( $#casks + $#locked )))"
  print -r -- "password: ${(j:, :)locked:-none}"
  exit 0
fi

told=""
tell() {   # logs a reason once, not on every look
  [[ $1 == "$told" ]] && return
  told=$1
  print -ru2 -- "Homebrew updates: $1"
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

# notify <title> <body>: how an upgrade ended, on the phone (queued while it is away) and on the Mac.
notify() {
  local json code
  print -ru2 -- "Homebrew updates: $1 $2"
  json=$(jq -nc --arg c "$cell" --arg t "$1" --arg b "$2" '{cellId: $c, title: $t, body: $b, targets: ["phone", "mac"]}')
  code=$(curl -q -s -o /dev/null -m 5 -w '%{http_code}' "$api/notify" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' \
    -H "Content-Type: application/json" --data-binary @- <<< "$json")
  [[ $code == 200 ]] || print -ru2 -- "Homebrew updates: notify answered ${code:-nothing}"
}

# The last count, kept between starts: "<when> <how many>".
good=0 kept=0
if [[ -r $dir/state ]]; then
  w=( ${=${"$(<$dir/state)"%%$'\n'*}} )
  [[ $w[1] == <-> && $w[2] == <-> ]] && good=$w[1] kept=$w[2]
fi
save() {   # remembers the count just had
  good=$EPOCHSECONDS kept=$n
  print -r -- "$good $kept" > "$dir/state.new" && zf_mv -f "$dir/state.new" "$dir/state"
}
counted() { (( n > 0 )) && REPLY="count $n" || REPLY=none }

# trouble <kind> <message>: the count cannot be had until the user acts — a grey "—", the reason to the phone.
trouble() {
  tell "$2"
  report $1 "$2"
  REPLY=problem
}

# hitch <kind> <message>: a look failed — the reason to the phone, the last count stays until it is $stale seconds old.
hitch() {
  tell "$2"
  report $1 "$2"
  if (( EPOCHSECONDS - good > stale )); then REPLY=problem; else REPLY=keep; fi
}

# look: brew update, then the count. REPLY = the face — none, "count <n>", problem, or keep (the face stays).
# A failed brew update still counts by the list Homebrew has, and says so.
look() {
  local rc fetched=""
  find_brew || { trouble notFound "Homebrew is not installed: see brew.sh to install it"; return }
  brew=$REPLY
  limited 300 $brewing $brew update --quiet
  rc=$?
  if (( rc == 124 )); then
    fetched="timeout Homebrew did not fetch its package list in 5 minutes: the count may be old"
  elif (( rc )); then
    fetched="network Homebrew could not fetch its package list: $(first_line $tmp/err)"
  fi
  if ! count; then
    hitch $why_kind "$why"
    return
  fi
  save
  if [[ -n $fetched ]]; then
    tell "${fetched#* }"
    report ${fetched%% *} "${fetched#* }"
  else
    told=""
    report clear
  fi
  counted
}

# MARK: - Upgrade

# awake <minutes> | awake off: keeps the Mac from idle sleep while an upgrade runs (the agent's keep-awake, which
# outlives this loop and ends by itself at its time), or takes that back.
awake() {
  local json
  [[ $1 == off ]] && json="{\"cellId\":\"$cell\",\"off\":true}" || json="{\"cellId\":\"$cell\",\"minutes\":$1}"
  curl -q -s -o /dev/null -m 5 "$api/keep-awake" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' \
    -H "Content-Type: application/json" --data-binary @- <<< "$json"
}

# line_for <mark> <brew command> <formula|cask> <name>: one line of a notification, "🔒 name → brew upgrade --cask name".
line_for() {
  local opt=""
  [[ $3 == cask ]] && opt=" --cask"
  print -r -- "$1 $4 → brew $2$opt $4"
}

# write_command <formula|cask> <name> …: $dir/upgrade.command, the upgrade Terminal runs — one brew upgrade per
# package, each one's outcome in upgrade.done, the one at work in upgrade.now, its own pid in upgrade.pid first and
# upgrade.end last. The names were checked in count; the folder and brew are quoted.
write_command() {
  {
    print -r -- '#!/bin/zsh -f'
    print -r -- '# Homebrew updates: the brew upgrade asked for on the phone, one package at a time. Closing this window'
    print -r -- '# stops it; the button then names the package it was at, with the command that repairs it.'
    print -r -- "d=${(qq)dir}"
    print -r -- "brew=${(qq)brew}"
    print -r -- "packages=( ${(j: :)${(qq)@}} )"
    cat <<'RUN'
emulate -R zsh
print -r -- $$ > "$d/upgrade.pid"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 NONINTERACTIVE=1 SUDO_ASKPASS=/usr/bin/false
i=0 ok=0 failed=0
for kind name in $packages; do
  i=$(( i + 1 ))
  print -r -- "$i $kind $name" > "$d/upgrade.now"
  if "$brew" upgrade --$kind $name < /dev/null; then
    print -r -- "ok $kind $name" >> "$d/upgrade.done"
    ok=$(( ok + 1 ))
  else
    print -r -- "fail $kind $name" >> "$d/upgrade.done"
    failed=$(( failed + 1 ))
  fi
done
: > "$d/upgrade.end"
print -r -- "
✓ $ok   ✗ $failed"
RUN
  } > "$dir/upgrade.command.new" && zf_chmod 700 "$dir/upgrade.command.new" &&
    zf_mv -f "$dir/upgrade.command.new" "$dir/upgrade.command"
}

# start_upgrade: counts again by the list Homebrew has and opens the upgrade in Terminal. REPLY = the face.
# $dir/running ("<when> <how many> <skipped casks…>") stays until it has ended: tap.zsh refuses a second one, and a
# start of this loop that finds it follows the upgrade on.
upgrading=0 since=0 total=0 upid=""
start_upgrade() {
  local name
  local -a body pkgs
  find_brew || { trouble notFound "Homebrew is not installed: see brew.sh to install it"; return }
  brew=$REPLY
  if ! count; then
    notify "Homebrew ✗" "✗ brew outdated${brew_err:+$'\n'$brew_err}"
    hitch $why_kind "$why"
    return
  fi
  save
  total=$(( $#formulae + $#casks ))
  if (( ! total )); then
    if (( $#locked )); then
      for name in $locked; do body+=( "$(line_for 🔒 upgrade cask $name)" ); done
      notify "Homebrew 🔒" "${(F)body}"
    fi
    counted
    return
  fi
  for name in $formulae; do pkgs+=( formula $name ); done
  for name in $casks; do pkgs+=( cask $name ); done
  zf_rm -f -- "$dir/upgrade.pid" "$dir/upgrade.now" "$dir/upgrade.done" "$dir/upgrade.end"
  if ! write_command $pkgs; then
    trouble other "Cannot write the upgrade into $dir"
    return
  fi
  since=$EPOCHSECONDS upid=""
  print -r -- "$since $total $locked" > "$dir/running"
  if ! env -i /usr/bin/open -b com.apple.Terminal "$dir/upgrade.command"; then
    zf_rm -f -- "$dir/running" "$dir/upgrade.command"
    notify "Homebrew ✗" "✗ Terminal"
    tell "Terminal did not open the upgrade"
    report other "Terminal did not open the upgrade"
    counted
    return
  fi
  upgrading=1
  awake 180
  print -ru2 -- "Homebrew updates: brew upgrade opened in Terminal: $#formulae formulae, $#casks casks${locked:+, skipped: ${(j:, :)locked}}"
  REPLY="run $total 0 $total"
}

# follow: REPLY = the face while the upgrade runs in Terminal — the packages left, by upgrade.now. Ends it when
# upgrade.end is there, when its process is gone without it (the window was closed), or when Terminal has not
# started it in a minute.
follow() {
  local p got=0
  local -a w
  if [[ -e $dir/upgrade.end ]]; then
    finish done
    return
  fi
  if [[ -z $upid && -r $dir/upgrade.pid ]]; then
    p=${"$(<$dir/upgrade.pid)"//[^0-9]/}
    # the upgrade's own process, not one that took its number later (after a restart of the Mac)
    if [[ -n $p ]]; then
      [[ $(ps -p $p -o args= 2>/dev/null) == *upgrade.command* ]] && upid=$p || upid=gone
    fi
  fi
  if [[ $upid == gone ]] || { [[ -n $upid ]] && ! kill -0 $upid 2>/dev/null }; then
    if [[ -e $dir/upgrade.end ]]; then finish done; else finish stopped; fi
    return
  fi
  if [[ -z $upid ]] && (( EPOCHSECONDS - since > 60 )); then
    finish never
    return
  fi
  if [[ -r $dir/upgrade.now ]]; then
    w=( ${=${"$(<$dir/upgrade.now)"}} )
    [[ $w[1] == <1-> ]] && got=$(( w[1] - 1 ))
  fi
  (( got > total )) && got=$total
  REPLY="run $(( total - got )) $got $total"
}

# finish <done|stopped|never>: the upgrade has ended — the notification (how many updated, which failed, which was
# cut off, which were skipped, each with its command), its files away, a fresh count. REPLY = the face.
finish() {
  local how=$1 line ok=0 title="Homebrew ✓" name
  local -a w body seen
  if [[ -r $dir/upgrade.done ]]; then
    for line in "${(@f)$(<$dir/upgrade.done)}"; do
      w=( ${=line} )
      (( $#w == 3 )) || continue
      seen+=( "$w[2] $w[3]" )
      if [[ $w[1] == ok ]]; then
        (( ok++ ))
      else
        body+=( "$(line_for ✗ upgrade $w[2] $w[3])" )
        title="Homebrew ✗"
      fi
    done
  fi
  if [[ $how == stopped ]]; then
    title="Homebrew ⏹"
    if [[ -r $dir/upgrade.now ]]; then
      w=( ${=${"$(<$dir/upgrade.now)"}} )
      if (( $#w == 3 )) && (( ! ${seen[(Ie)$w[2] $w[3]]} )); then
        body+=( "$(line_for ⏹ reinstall $w[2] $w[3])" )
      fi
    fi
  elif [[ $how == never ]]; then
    title="Homebrew ✗"
    body+=( "✗ Terminal" )
    tell "Terminal did not start the upgrade in a minute"
    report other "Terminal did not start the upgrade in a minute"
  fi
  for name in $locked; do body+=( "$(line_for 🔒 upgrade cask $name)" ); done
  body=( "↑ $ok" $body )
  notify "$title" "${(F)body}"
  zf_rm -f -- "$dir/running" "$dir/upgrade.command" "$dir/upgrade.pid" "$dir/upgrade.now" "$dir/upgrade.done" \
    "$dir/upgrade.end"
  upgrading=0 upid=""
  awake off
  if ! find_brew; then
    trouble notFound "Homebrew is not installed: see brew.sh to install it"
    return
  fi
  brew=$REPLY
  if count; then
    save
    counted
  else
    hitch $why_kind "$why"
    [[ $REPLY == keep ]] && { n=$kept; counted }  # the count from before the upgrade, never the running face
  fi
}

# MARK: - Loop

hidden=0 looked=0
visible() {   # does the phone show the button (or is it too old to say)? Asks at most every 5 s.
  local out code body
  (( EPOCHSECONDS - looked < 5 )) && return $hidden
  looked=$EPOCHSECONDS
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/view" --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}') || { hidden=1; return 1 }
  code=${out##*$'\n'} body=${(L)${out%$'\n'*}//[[:space:]]/}
  if [[ $code != 200 || $body == *'"view":null'* || $body == *${(L)cell}* ]]; then
    hidden=0
  else
    hidden=1
  fi
  return $hidden
}

post() {   # $1 frame → 0 when the agent took it
  local p=$1 out code
  p=${p//\\/\\\\}; p=${p//\"/\\\"}; p=${p//$'\n'/}
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' -H "Content-Type: application/json" \
    -d "{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$p\",\"duration\":0.6}}")
  code=${out##*$'\n'}
  [[ $code == 200 ]] && return 0
  print -ru2 -- "Homebrew updates: update-button answered ${code:-nothing}: ${${out%$'\n'*}[1,300]}"
  return 1
}

# fresh <file>: the file is there, and was left in the last 10 minutes (an older one is from a loop that was not
# running: it is dropped). Either way it is taken away.
fresh() {
  local -A st
  [[ -e $1 ]] || return 1
  zstat -H st -- "$1" 2>/dev/null
  zf_rm -f -- "$1"
  (( EPOCHSECONDS - ${st[mtime]:-0} <= 600 ))
}

zf_mkdir -p -- "$dir" || { print -u2 -- "Homebrew updates: cannot make $dir"; exit 1 }
zf_rm -f -- "$dir/upgrade" "$dir/poke"         # taps left while no loop ran: not this start's
if [[ -r $dir/running ]]; then                  # an upgrade opened before: follow it on, or tell how it ended
  w=( ${=${"$(<$dir/running)"%%$'\n'*}} )
  since=${w[1]:-0} total=${w[2]:-0} locked=( $w[3,-1] )
  [[ $since == <-> ]] || since=0
  [[ $total == <-> ]] || total=0
  upgrading=1
fi

face=""                                         # the face to show
shown="" posted=0                               # the face the agent took last, and when
if (( good && EPOCHSECONDS - good <= stale )); then
  n=$kept; counted; face=$REPLY
fi
due=$(( good + period ))
while true; do
  if (( upgrading )); then
    follow
    (( upgrading )) || due=$(( EPOCHSECONDS + period ))
    [[ $REPLY != keep ]] && face=$REPLY
  elif fresh "$dir/upgrade"; then
    zf_rm -f -- "$dir/poke"
    start_upgrade
    [[ $REPLY != keep ]] && face=$REPLY
  else
    poked=0
    fresh "$dir/poke" && poked=1                # a long press: look now, the button is on screen
    if (( poked )) || { (( EPOCHSECONDS >= due )) && visible }; then
      look
      [[ $REPLY != keep ]] && face=$REPLY
      [[ $REPLY == (keep|problem) ]] && due=$(( EPOCHSECONDS + retry )) || due=$(( EPOCHSECONDS + period ))
    fi
  fi
  # a changed face at once, the same one every $again seconds (a face reset from outside comes back)
  if [[ -n $face ]] && { [[ $face != "$shown" ]] || (( EPOCHSECONDS - posted >= again )) }; then
    if visible && post "$(brew_frame ${=face})"; then
      shown=$face posted=$EPOCHSECONDS
    fi
  fi
  zselect -t 100
done
