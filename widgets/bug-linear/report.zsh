# Bug report › what both bug buttons share (Linear and GitHub: the same file in each widget's folder): the text typed
# on the phone, what the Mac adds to it, the simulator's screenshot, and talking to the agent. Functions and
# settings only; the tracker's own file follows it (item.json):
#   "…settings…\n@file:report.zsh\n@file:linear.zsh"
#
# The text ($DESMAPTIC_INPUT): its first line is the issue's title, the rest its description. The Mac adds the
# branch and the last commit of the project folder (a setting; skipped while it is empty), the app in front and the
# address of the front browser tab (Safari, Chrome, Arc, Brave, Edge — only one already running; macOS asks once
# whether the agent may read it).
#
# The simulator's screenshot is never taken by itself: a screen may show someone else's data. The quick reply
# "+ screenshot" takes it at once and keeps it for the next report from this button (15 minutes); "+ screenshot" as
# the text's last line takes one for this report.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
setopt extended_glob
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime zsh/zselect zsh/stat || { print -u2 -- "Bug: zsh modules datetime, zselect and stat are missing"; exit 1 }

cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"
simctl=/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl
kept=""                                         # the screenshot kept by "+ screenshot"
[[ -n $DESMAPTIC_STORAGE ]] && kept="$DESMAPTIC_STORAGE/gallery/{{CELL_ID}}/screenshot.png"
tmp=""
trap '[[ -n $tmp ]] && rm -rf -- "$tmp"' EXIT
trap 'exit 0' TERM INT
tmp=$(mktemp -d) || { print -u2 -- "Bug: no room for a temporary folder"; exit 1 }
: > "$tmp/in"

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
  print -ru2 -- "Bug: $2"
  exit 1
}

# flash <icon> [title]: shows it on the button for 3 seconds, then the button's own face again.
flash() {
  call update-button "$(jq -nc --arg c "$cell" --arg i "$1" --arg t "${2-}" \
    '{cellId: $c, icon: $i} + (if $t == "" then {} else {title: $t} end)')" >/dev/null
  sleep 3
  call update-button "{\"cellId\":\"$cell\",\"reset\":true}" >/dev/null
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

# expand_folder: $folder as a full path ("~/…" expanded), or a refusal that says what is wrong with it.
expand_folder() {
  case $folder in
    '~')   folder=$HOME ;;
    '~/'*) folder=$HOME/${folder#'~/'} ;;
  esac
  [[ $folder == /* ]] || fail config "Not a full path: $folder (start it with / or ~/)"
  [[ -d $folder ]] || fail notFound "No such folder: $folder"
  folder=${folder:a}
}

# version_control: $vcs, git of the developer folder xcode-select names, or a refusal. A stock Mac has no git:
# /usr/bin's copy is only a stub that opens an install dialog without the Command Line Tools, so it is never called,
# and without them the button says what to install.
version_control() {
  local dev=$(xcode-select -p 2>/dev/null)
  vcs=( ${dev:+$dev/usr/bin/git(N-*)} )
  (( $#vcs )) || fail notFound "This button needs Apple’s Command Line Tools: install them in Terminal with xcode-select --install"
}

# is_screenshot <line>: whether the line asks for the simulator's screenshot, in any language the Gallery speaks.
is_screenshot() {
  case ${${1##[[:space:]]#}%%[[:space:]]#} in
    ("+ screenshot"|"+screenshot"|"+ Screenshot"|"+ captura"|"+ capture d’écran"|"+ capture d'écran"|"+ скриншот"|"+скриншот"|"+ Скриншот") return 0 ;;
  esac
  return 1
}

# screenshot <file>: the booted simulator's screen as a PNG, or a refusal.
screenshot() {
  [[ -x $simctl ]] || fail notFound "No simulator on this Mac: Xcode’s simulator tools are not installed"
  limited 25 $simctl io booted screenshot --type=png "$1"
  local rc=$?
  (( rc == 0 )) && [[ -s $1 ]] && return
  rm -f -- "$1"
  case $rc in
    (0) fail other "The simulator gave an empty screenshot" ;;
    (124) fail timeout "The simulator did not answer in 25 seconds" ;;
    (*) local err=$(first_line $tmp/err)
        [[ $err == *(No\ devices\ are\ booted|Invalid\ device)* ]] && fail notRunning "No simulator is running"
        fail other "The screenshot failed: ${err:-no answer}" ;;
  esac
}

# read_report: title, description and shot (the screenshot's file, or empty) from the text typed on the phone. The
# quick reply "+ screenshot" alone takes the screenshot, keeps it for the next report and ends the tap.
read_report() {
  local text=${DESMAPTIC_INPUT//$'\r'/}
  if is_screenshot "$text"; then
    [[ -n $kept ]] || fail other "The agent gave no folder to keep the screenshot in"
    mkdir -p -- "${kept:h}" 2>/dev/null || fail permission "The screenshot cannot be kept in the agent’s folder"
    screenshot "$kept"
    flash camera.fill
    exit 0
  fi
  local -a lines=( "${(@f)text}" )
  shot=""
  if (( $#lines > 1 )) && is_screenshot "$lines[-1]"; then
    shot="$tmp/screenshot.png"
    screenshot "$shot"
    lines[-1]=()
  elif [[ -n $kept && -f $kept ]]; then
    # kept by "+ screenshot": this report takes it if it is fresh; either way it is not kept any longer
    local -a when
    zstat -A when +mtime -- "$kept" 2>/dev/null
    if (( EPOCHSECONDS - ${when[1]:-0} <= 900 )); then
      shot="$tmp/screenshot.png"
      mv -f -- "$kept" "$shot" 2>/dev/null || shot=""
    fi
    rm -f -- "$kept"
  fi
  while (( $#lines )) && [[ -z ${lines[1]//[[:space:]]/} ]]; do lines[1]=(); done
  (( $#lines )) || fail other "Nothing to report: the text is empty"
  title=${${lines[1]##[[:space:]]#}%%[[:space:]]#}
  title=$(shorten "$title" 250)
  description=${(F)lines[2,-1]}
  description=${${description##[[:space:]]#}%%[[:space:]]#}
}

# context: extra, the lines the Mac adds under the description, as Markdown — the project folder's branch and last
# commit, the app in front, the front browser tab. (Not run in $(…): its refusals must end the tap.)
context() {
  local -a ctx
  if [[ -n $folder ]]; then
    version_control
    if limited 10 $vcs -C "$folder" rev-parse --abbrev-ref HEAD; then
      ctx+=( "- Branch: \`$(first_line $tmp/out)\`" )
      limited 10 $vcs -C "$folder" log -1 --format='%h %s' &&
        ctx+=( "- Last commit: $(first_line $tmp/out)" )
    fi
  fi
  # The app in front and the address of a browser tab, in one osascript. A browser that is not running is not asked
  # (that would start it); the one in front is asked first. One that does not answer in 8 s is left out.
  limited 8 osascript -l JavaScript -e '
ObjC.import("AppKit");
function run() {
  const front = $.NSWorkspace.sharedWorkspace.frontmostApplication;
  const name = front.isNil() ? "" : ObjC.unwrap(front.localizedName);
  const id = front.isNil() ? "" : ObjC.unwrap(front.bundleIdentifier);
  const browsers = ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac"];
  const order = browsers.includes(id) ? [id].concat(browsers.filter(b => b !== id)) : browsers;
  let tab = "";
  for (const b of order) {
    if (Number($.NSRunningApplication.runningApplicationsWithBundleIdentifier(b).count) === 0) continue;  // count comes as a string
    try {
      const app = Application(b);
      tab = b === "com.apple.Safari" ? app.documents[0].url() : app.windows[0].activeTab.url();
    } catch (e) { tab = ""; }
    if (tab) break;
  }
  return (name || "") + "\n" + (tab || "");
}'
  if (( $? == 0 )); then
    local -a seen=( "${(@f)$(<$tmp/out)}" )
    [[ -n $seen[1] ]] && ctx+=( "- App in front: $seen[1]" )
    [[ $seen[2] == http(s|)://* ]] && ctx+=( "- Browser tab: $seen[2]" )
  fi
  extra=${(F)ctx}
}
