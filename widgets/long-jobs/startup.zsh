long_jobs="xcodebuild swift-build swift-test docker:build docker:buildx ffmpeg HandBrakeCLI avconvert"   # ← the programs to watch, with a space between each; name:word watches one command of a program (docker:build)
# Long Jobs, the live loop (the button's startup script). Up to three lines on a 2×2 face, one per job: what runs on
# the Mac now and for how long, then what finished last and when, ✓ or ✗ with the time.
#
# Running now: the programs of the line above (as the process list names them; xcodebuild shows its -scheme), a build
# in Xcode itself (its build service at work), a Time Machine backup with its percent (tmutil status) and an AI
# session of the Desmaptic plugin at work (Claude Code, Codex). Finished: only what the Mac recorded itself — Xcode's
# build logs in DerivedData (the scheme, success or error), the last Time Machine backup (tmutil latestbackup), the
# last finished file in Downloads and the plugin's AI session records; no plugin, no AI line. What finished more than
# 12 hours ago is left out, except the last backup.
#
# It reads only while the button is on the phone's screen: every 20 s while something runs, every 60 s otherwise; a
# changed face is posted at once, the same one every 5 min. Off screen it asks the agent every 10 s whether the button
# is back and reads nothing but the AI session records (a session's "done" is kept before its idle "input" replaces
# it). The long press stops the top job the face shows that can be stopped (hold.zsh): this loop leaves that one job
# in $dir/stop, and the long press leaves $dir/poke for a fresh look.
#
# The plugin's hook writes only into an existing AISessions folder, so this loop makes it (as the plugin's AI Sessions
# page does) and cleans it the same way: a closed session after 5 min, any record untouched for a day.
#
# Tool modes, no network: --face <rest|demo> <out.svg> writes the Gallery faces (rest.svg, demo.svg); any other
# argument prints the usage. LONGJOBS_DRY=1 reads once, prints the lines ("row: …", "stop: …") and the frame
# ("frame: …") instead of posting it, and ends; it writes nothing. With it, LONGJOBS_FAKE=<folder> takes ps, args,
# tmutil-status, tmutil-latestbackup, DerivedData/ and Downloads/ from that folder instead of the Mac, LONGJOBS_NOW=<epoch>
# sets the clock, and the look keeps and cleans its state as the live loop does (the storage is the test's).
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime zsh/zselect || { print -u2 -- "long-jobs: zsh modules datetime/zselect are missing"; exit 1 }
zmodload -F zsh/stat b:zstat || { print -u2 -- "long-jobs: zsh module stat is missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_mv b:zf_rm || { print -u2 -- "long-jobs: zsh module files is missing"; exit 1 }
trap 'exit 0' TERM INT HUP

# One frame of the face. Every state draws the same elements in the same order, so the phone glides between them.
#   $1 state: rest (nothing read yet) | calm (nothing to show) | live (rows)
#   $2 rows, one per line, the first three are drawn: kind <TAB> name <TAB> value <TAB> percent (empty — no bar)
#      kind: run (cyan) | wait (amber: an AI session waits for you) | ok (green) | err (pink)
long_jobs_frame() {
  emulate -L zsh
  export LC_ALL=C
  LJ_ST=${1:-rest} LJ_ROWS=${2:-} awk '
    function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); return s }

    # Text is measured in em of the semibold system font, one UTF-8 character at a time (the locale is C,
    # so awk sees bytes): Latin by letter shape, other alphabets 0.66, CJK 0.96, emoji 1.25.
    function em(c, b, n) {
      if (n == 4) return 1.25
      if (n == 3) return (b == 226) ? 0.7 : 0.96
      if (n == 2) return 0.66
      if (c ~ /[0-9]/) return 0.62
      if (c == " ") return 0.25
      if (c ~ /[ijl.,:;!|\047]/) return 0.28
      if (c ~ /[frtI()\/"-]/) return 0.38
      if (c ~ /[mwMW@%]/) return 0.86
      if (c ~ /[A-Z&#?]/) return 0.68
      return 0.56
    }
    function chars(s,   i, b, n, k) {      # s → CH[1..k], CW[1..k] (em)
      k = 0; i = 1
      while (i <= length(s)) {
        b = ord[substr(s, i, 1)]
        n = (b >= 240) ? 4 : (b >= 224) ? 3 : (b >= 192) ? 2 : 1
        k++; CH[k] = substr(s, i, n); CW[k] = em(CH[k], b, n); i += n
      }
      return k
    }
    function join(a, b,   i, r) { r = ""; for (i = a; i <= b; i++) r = r CH[i]; return r }
    function fit(s, size, room,   n, i, w, r) {   # s on one line; cut with … when it does not fit
      n = chars(s)
      w = 0; for (i = 1; i <= n; i++) w += CW[i] * size
      if (w <= room) return s
      w = 0.9 * size
      for (i = 1; i <= n; i++) { if (w + CW[i] * size > room) break; w += CW[i] * size }
      r = join(1, i - 1); sub(/ +$/, "", r)
      return r "\342\200\246"
    }
    function textw(s, size,   n, i, w) { n = chars(s); w = 0; for (i = 1; i <= n; i++) w += CW[i] * size; return w }
    function show(s) { return (s == "") ? "\342\200\224" : esc(s) }   # never an empty <text>
    function f2(x) { return sprintf("%.2f", x) }

    BEGIN {
      for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i
      st = ENVIRON["LJ_ST"]
      if (st !~ /^(rest|calm|live)$/) st = "rest"
      col["run"] = "#64D2FF"; col["wait"] = "#FFD60A"; col["ok"] = "#30D158"; col["err"] = "#FF375F"
      shown = 0
      n = (st == "live") ? split(ENVIRON["LJ_ROWS"], L, "\n") : 0
      for (i = 1; i <= n && shown < 3; i++) {
        if (split(L[i], F, "\t") < 3 || !(F[1] in col)) continue
        K[shown] = F[1]; N[shown] = F[2]; V[shown] = F[3]; P[shown] = (F[4] ~ /^[0-9]+$/) ? F[4] : ""; shown++
      }
      if (st == "live" && shown == 0) st = "calm"

      # Nothing to show: an hourglass, faint until the first look, bright once the Mac is known to be idle.
      idle = (st == "rest") ? 0.35 : (st == "calm") ? 0.9 : 0
      bA = (st == "calm") ? 0.16 : (st == "live") ? 0.08 : 0.10

      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\"><defs>"
      printf "<linearGradient id=\"inkG\" gradientUnits=\"userSpaceOnUse\" x1=\"70\" y1=\"0\" x2=\"130\" y2=\"0\"><stop offset=\"0\" stop-color=\"#BF5AF2\"/><stop offset=\"1\" stop-color=\"#64D2FF\"/></linearGradient>"
      printf "<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"#BF5AF2\" stop-opacity=\"%s\"/><stop offset=\"0.55\" stop-color=\"#5E5CE6\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"#5E5CE6\" stop-opacity=\"0\"/></radialGradient>", f2(bA), f2(bA * 0.3)
      printf "</defs>"
      printf "<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"96\" fill=\"url(#bloomG)\"/>"
      printf "<path id=\"frame\" d=\"M 70 58 L 130 58 M 70 142 L 130 142\" fill=\"none\" stroke=\"url(#inkG)\" stroke-opacity=\"%s\" stroke-width=\"7\" stroke-linecap=\"round\"/>", f2(idle)
      printf "<path id=\"glass\" d=\"M 78 58 C 78 86 96 92 96 100 C 96 108 78 114 78 142 M 122 58 C 122 86 104 92 104 100 C 104 108 122 114 122 142\" fill=\"none\" stroke=\"#FFFFFF\" stroke-opacity=\"%s\" stroke-width=\"5\" stroke-linecap=\"round\"/>", f2(idle * 0.8)
      printf "<path id=\"sand\" d=\"M 88 74 L 112 74 L 100 90 Z M 86 136 Q 100 116 114 136 Z\" fill=\"url(#inkG)\" fill-opacity=\"%s\"/>", f2(idle)

      # A row per job: a card, a strip in the colour of its state (glowing while it runs), the name, the value
      # (time, ✓ / ✗ with the time, a percent) and, for a percent, a bar after the value.
      for (i = 0; i < 3; i++) {
        top = 8 + 64 * i
        on = (i < shown) ? 1 : 0
        c = on ? col[K[i]] : "#64D2FF"
        run = on && K[i] == "run"
        name = on ? fit(N[i], 16, 150) : ""
        value = on ? fit(V[i], 20, 150) : ""
        bar = on && P[i] != ""
        bx = 34 + textw(value, 20) + 14
        if (bx > 168) { bx = 168; bar = 0 }
        p = bar ? P[i] / 100 : 0
        if (p > 1) p = 1
        printf "<rect id=\"card%d\" x=\"6\" y=\"%d\" width=\"188\" height=\"56\" rx=\"14\" fill=\"#FFFFFF\" fill-opacity=\"%s\"/>", i, top, f2(on * 0.06)
        printf "<line id=\"glow%d\" x1=\"20\" y1=\"%d\" x2=\"20\" y2=\"%d\" stroke=\"%s\" stroke-opacity=\"%s\" stroke-width=\"12\" stroke-linecap=\"round\"/>", i, top + 13, top + 43, c, f2(run * 0.3)
        printf "<line id=\"strip%d\" x1=\"20\" y1=\"%d\" x2=\"20\" y2=\"%d\" stroke=\"%s\" stroke-opacity=\"%s\" stroke-width=\"4\" stroke-linecap=\"round\"/>", i, top + 13, top + 43, c, f2(on)
        printf "<text id=\"name%d\" x=\"34\" y=\"%d\" font-size=\"16\" font-weight=\"600\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"%s\">%s</text>", i, top + 18, f2(on * 0.7), show(name)
        printf "<text id=\"value%d\" x=\"34\" y=\"%d\" font-size=\"20\" font-weight=\"600\" dominant-baseline=\"middle\" fill=\"%s\" fill-opacity=\"%s\">%s</text>", i, top + 39, c, f2(on), show(value)
        printf "<line id=\"track%d\" x1=\"%s\" y1=\"%d\" x2=\"180\" y2=\"%d\" stroke=\"#FFFFFF\" stroke-opacity=\"%s\" stroke-width=\"6\" stroke-linecap=\"round\"/>", i, f2(bx), top + 39, top + 39, f2(bar * 0.15)
        printf "<line id=\"bar%d\" x1=\"%s\" y1=\"%d\" x2=\"%s\" y2=\"%d\" stroke=\"%s\" stroke-opacity=\"%s\" stroke-width=\"6\" stroke-linecap=\"round\"/>", i, f2(bx), top + 39, f2(bx + (180 - bx) * p), top + 39, c, f2(bar)
      }
      printf "</svg>\n"
    }'
}

usage() {
  print -u2 -- "usage: startup.zsh [--face <rest|demo> <out.svg>]"
  exit 2
}

if (( $# )); then
  [[ $1 == --face && $# == 3 && $2 == (rest|demo) && -n $3 ]] || usage
  if [[ $2 == rest ]]; then
    long_jobs_frame rest > "$3" || exit 1
  else
    # One imaginary Mac at 10:48: a build of 12 min, a backup at 63 %, a download finished at 10:31.
    long_jobs_frame live $'run\tMyApp\t12 min\t\nrun\tTime Machine\t63 %\t63\nok\treport.pdf\t✓ 10:31\t' > "$3" || exit 1
  fi
  exit 0
fi

api="http://127.0.0.1:9848"
cell="{{CELL_ID}}"
store="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}"
dir="$store/gallery/$cell"
dry=${LONGJOBS_DRY:-0}
[[ $dry == 1 ]] || dry=0
fake="" clock="" writes=1      # writes: keeps state in $dir and cleans AISessions (live, or a dry look at a made-up Mac)
if (( dry )); then
  fake=${LONGJOBS_FAKE:-}
  [[ ${LONGJOBS_NOW:-} == <-> ]] && clock=$LONGJOBS_NOW
  [[ -n $fake ]] || writes=0
fi
day=43200                       # s: what finished longer ago than this is left out (12 h)
ai_since=${clock:-$EPOCHSECONDS} # this loop watches the AI sessions from here on

# The job list → watched[program] = the first words it is watched with ("*" — any), and a name per entry.
typeset -A watched
for entry in ${=long_jobs}; do
  program=${entry%%:*}
  [[ -n $program ]] || continue
  if [[ $entry == *:?* ]]; then watched[$program]+="${entry#*:} "; else watched[$program]+="* "; fi
done

# The DerivedData folder Xcode uses (Xcode › Settings › Locations), as Xcode 27 finds it: IDECustomDerivedDataLocation
# missing or empty — the standard place, an absolute path — that folder, a relative one — a folder next to each
# project, so no one folder to read. 1 when there is none.
derived_data() {
  emulate -L zsh
  local custom
  [[ $HOME == /?* ]] || return 1
  custom=$(defaults read com.apple.dt.Xcode IDECustomDerivedDataLocation 2>/dev/null)
  case $custom in
    '')        REPLY=$HOME/Library/Developer/Xcode/DerivedData ;;
    '~'|'~/'*) REPLY=$HOME${custom#\~} ;;
    *'$('*)    return 1 ;;
    /*)        REPLY=$custom ;;
    *)         return 1 ;;
  esac
}

# The newest log of an Xcode build log manifest (Logs/Build/LogStoreManifest.plist):
# "<end, epoch>\t<ok|err>\t<scheme>". Its times count from 2001, so 978307200 s are added.
manifest_newest() {
  plutil -convert xml1 -o - -- "$1" 2>/dev/null | awk '
    function val(s) { if (s ~ /<[a-z]+\/>/) return ""; sub(/^[ \t]*<[a-z]+>/, "", s); sub(/<\/[a-z]+>[ \t]*$/, "", s); return s }
    function unxml(s) { gsub(/&lt;/, "<", s); gsub(/&gt;/, ">", s); gsub(/&quot;/, "\"", s); gsub(/&apos;/, "\047", s); gsub(/&amp;/, "\\&", s); return s }
    /<dict>/   { d++; if (d == 3) { sc = ""; st = 0; hs = ""; er = 0 }; next }
    /<\/dict>/ { if (d == 3 && st > best) { best = st; out = sprintf("%.0f\t%s\t%s", int(st) + 978307200, (hs == "E" || er > 0) ? "err" : "ok", unxml(sc)) }; d--; next }
    /<key>/    { k[d] = val($0); next }
    d == 3 && k[3] == "schemeIdentifier-schemeName" { sc = val($0) }
    d == 3 && k[3] == "timeStoppedRecording"        { st = val($0) + 0 }
    d == 4 && k[3] == "primaryObservable" && k[4] == "highLevelStatus"     { hs = val($0) }
    d == 4 && k[3] == "primaryObservable" && k[4] == "totalNumberOfErrors" { er = val($0) + 0 }
    END { if (best > 0) print out }'
}

# The newest finished item in Downloads, by Finder's Date Added (the creation date where a disk keeps none); hidden
# files, unfinished downloads and a file beside its .part or .aria2 companion are skipped, as Latest Download does.
# Prints "ok\n<epoch>\n<name>|", or "empty", "denied", "unreadable".
read -r -d '' downloads_js <<'JXA'
ObjC.import("Foundation")
function run(argv) {
  const unfinished = ["download", "crdownload", "part", "partial", "opdownload", "aria2", "fdmdownload", "!ut", "!qb"]
  const added = ObjC.unwrap($.NSURLAddedToDirectoryDateKey), created = ObjC.unwrap($.NSURLCreationDateKey)
  const keys = $([added, created]), error = $()
  const list = $.NSFileManager.defaultManager.contentsOfDirectoryAtURLIncludingPropertiesForKeysOptionsError(
    $.NSURL.fileURLWithPathIsDirectory(argv[0], true).URLByResolvingSymlinksInPath, keys, $.NSDirectoryEnumerationSkipsHiddenFiles, error)
  if (list.isNil()) return error.code == $.NSFileReadNoPermissionError ? "denied" : "unreadable"
  const urls = list.js, names = ObjC.deepUnwrap(list.valueForKey("lastPathComponent")), present = new Set(names)
  const extension = name => name.lastIndexOf(".") > 0 ? name.slice(name.lastIndexOf(".") + 1).toLowerCase() : ""
  let best = null, bestTime = -Infinity
  names.forEach((name, i) => {
    if (unfinished.includes(extension(name)) || present.has(name + ".part") || present.has(name + ".aria2")) return
    const values = ObjC.deepUnwrap(urls[i].resourceValuesForKeysError(keys, null)) || {}
    const date = values[added] || values[created], time = date ? date.getTime() : -Infinity
    if (best === null || time > bestTime) { best = name; bestTime = time }
  })
  return best === null || bestTime === -Infinity ? "empty" : "ok\n" + Math.floor(bestTime / 1000) + "\n" + best + "|"
}
JXA

# "12 s", "12 min", "2 h 5 min" in REPLY.
span() {
  local s=$1 m
  (( s < 0 )) && s=0
  if (( s < 60 )); then REPLY="$s s"
  elif (( s < 3600 )); then REPLY="$(( s / 60 )) min"
  else m=$(( s / 60 % 60 )); REPLY="$(( s / 3600 )) h"; (( m )) && REPLY+=" $m min"
  fi
}

# "✓ 14:05" — the mark and when it finished; over 12 h ago "✓ 20 h", over two days "✓ 3 d".
finished() {   # $1 ok | err   $2 epoch
  local mark=✓ age=$(( now - $2 ))
  [[ $1 == err ]] && mark=✗
  if (( age <= day )); then strftime -s REPLY '%H:%M' $2; REPLY="$mark $REPLY"
  elif (( age < 2 * 86400 )); then REPLY="$mark $(( age / 3600 )) h"
  else REPLY="$mark $(( age / 86400 )) d"
  fi
}

# ps's elapsed time [[dd-]hh:]mm:ss → seconds in REPLY.
seconds_of() {
  local e=$1 d=0 h=0 m=0 s=0
  local -a parts
  if [[ $e == <->-* ]]; then d=${e%%-*}; e=${e#*-}; fi
  parts=( ${(s.:.)e} )
  case $#parts in
    3) h=$parts[1] m=$parts[2] s=$parts[3] ;;
    2) m=$parts[1] s=$parts[2] ;;
    *) return 1 ;;
  esac
  [[ $d$h$m$s == <-> ]] || return 1
  REPLY=$(( ((d * 24 + h) * 60 + m) * 60 + s ))
}

# A row: $1 group (0 waits for you, 1 runs, 2 finished)  $2 its time (start, or end)  $3 kind  $4 name  $5 value
# $6 percent  $7 how to stop it ("pid <pid> <process name>" | "tm" | empty). Sorted by the key: the group, then newest first.
add_row() {
  local name=${4//[$'\t\n']/ }
  rows_all+=( "$1${(l:10::0:)$(( 9999999999 - $2 ))}"$'\t'"$3"$'\t'"$name"$'\t'"$5"$'\t'"$6"$'\t'"$7" )
  (( $1 < 2 )) && busy[$name]=1
}

# Processes of this user: p_ppid, p_age (s), p_name (the executable's name). 1 when ps did not answer.
read_processes() {
  local out line
  local -a w
  p_ppid=() p_age=() p_name=()
  if [[ -n $fake ]]; then
    [[ -r $fake/ps ]] && out=$(<$fake/ps)
  else
    out=$(ps -U $UID -co pid=,ppid=,etime=,command= 2>/dev/null) || return 1
  fi
  for line in ${(f)out}; do
    w=( ${=line} )
    (( $#w >= 4 )) && [[ $w[1] == <-> && $w[2] == <-> ]] || continue
    seconds_of $w[3] || continue
    p_ppid[$w[1]]=$w[2] p_age[$w[1]]=$REPLY p_name[$w[1]]=${(j: :)w[4,-1]}
  done
}

# The command lines of the given pids → p_args.
read_args() {
  local out line
  local -a w
  p_args=()
  if [[ -n $fake ]]; then
    [[ -r $fake/args ]] && out=$(<$fake/args)
  else
    out=$(ps -o pid=,args= -p ${(j:,:)@} 2>/dev/null)
  fi
  for line in ${(f)out}; do
    w=( ${=line} )
    [[ $w[1] == <-> ]] && p_args[$w[1]]=${(j: :)w[2,-1]}
  done
}

# Programs of the job list at work for 10 s or more. A job started by another job of the list is part of it, not a
# line of its own.
programs_poll() {
  local pid name first a label up steps i
  local -a candidates allowed w
  local -A matched
  for pid in ${(k)p_name}; do
    (( p_age[$pid] >= 10 )) || continue      # a quick query (xcodebuild -list) is no job
    [[ -n ${watched[$p_name[$pid]]} ]] && candidates+=$pid
  done
  (( $#candidates )) || return 0
  read_args $candidates
  for pid in $candidates; do
    name=$p_name[$pid]
    w=( ${=p_args[$pid]} ) first=""
    for a in $w[2,-1]; do [[ $a == -* ]] && continue; first=$a; break; done
    allowed=( ${=watched[$name]} )
    if (( ${allowed[(Ie)*]} )); then label=$name
    elif [[ -n $first ]] && (( ${allowed[(Ie)$first]} )); then label="$name $first"
    else continue
    fi
    if [[ $name == xcodebuild ]]; then
      i=${w[(Ie)-scheme]}
      (( i && i < $#w )) && label=$w[i+1]
    fi
    matched[$pid]=$label
  done
  for pid in ${(k)matched}; do
    up=$p_ppid[$pid] steps=0
    while [[ -n $up ]] && (( up > 1 && steps++ < 30 )); do
      (( ${+matched[$up]} )) && continue 2
      up=$p_ppid[$up]
    done
    span $p_age[$pid]
    add_row 1 $(( now - p_age[$pid] )) run "$matched[$pid]" "$REPLY" "" "pid $pid $p_name[$pid]"
  done
}

# A build in Xcode itself: Xcode's build service has work running under it (between builds it has none). Its start is
# kept while the loop runs; a pause of under a minute between its jobs is the same build, a log newer than its start
# ends it.
xcode_app_poll() {
  local pid parent age=-1
  for pid in ${(k)p_name}; do
    [[ $p_name[$pid] == swift-plugin-server ]] && continue
    parent=$p_ppid[$pid]
    [[ ${p_name[$parent]} == (SWBBuildService|XCBBuildService) && ${p_name[${p_ppid[$parent]}]} == Xcode ]] || continue
    (( p_age[$pid] > age )) && age=$p_age[$pid]
  done
  if (( age >= 0 )); then
    (( xc_since )) || xc_since=$(( now - age ))
    xc_seen=$now
  elif (( xc_since && (now - xc_seen >= 60 || xc_latest >= xc_since) )); then
    xc_since=0
  fi
  if (( xc_since )); then
    span $(( now - xc_since ))
    add_row 1 $xc_since run Xcode "$REPLY" ""
  fi
}

# Finished Xcode builds: the newest log of the five projects built last. A manifest is read again only when it changed.
xcode_logs_poll() {
  local f line mark name
  local -a m w
  xc_latest=0
  if [[ -n $fake ]]; then
    dd=$fake/DerivedData
  elif (( now - dd_read >= 600 )); then
    dd_read=$now
    if derived_data; then dd=$REPLY; else dd=""; fi
  fi
  [[ -n $dd ]] || return 0
  for f in $dd/*/Logs/Build/LogStoreManifest.plist(N.om[1,5]); do
    zstat -A m +mtime -- $f 2>/dev/null || continue
    if [[ ${mf_time[$f]} != $m[1] ]]; then
      mf_line[$f]=$(manifest_newest $f)
      mf_time[$f]=$m[1]
    fi
    line=${mf_line[$f]}
    [[ -n $line ]] || continue
    w=( "${(@ps:\t:)line}" )
    [[ $w[1] == <-> && $w[2] == (ok|err) ]] || continue
    (( w[1] > xc_latest )) && xc_latest=$w[1]
    (( now - w[1] <= day )) || continue
    name=$w[3]
    [[ -n $name ]] || name=${${f:h:h:h:t}%-*}
    finished $w[2] $w[1]
    add_row 2 $w[1] $w[2] "$name" "$REPLY" ""
  done
}

# Time Machine: a backup at work with its percent; when none runs, the last one. tmutil latestbackup may try to reach
# the backup disk, so it is asked at the first look, after a backup ends and then once an hour; an answer without a
# date (no disk set, the disk away, or no access to it) is asked again only after a day or a backup seen running.
# tmutil gives no start of a backup: it is the look that first saw it after one without it, kept in $dir/tm-since
# while that backup runs (the loop stops while the phone is away); a backup already at work when the loop started,
# with nothing kept, has no start and sorts below the jobs that have one, so it never takes the top line by default.
tm_poll() {
  local out line pct=-1 run=0 depth=0
  local -i p key
  if [[ -n $fake ]]; then
    [[ -r $fake/tmutil-status ]] && out=$(<$fake/tmutil-status)
  else
    out=$(tmutil status 2>/dev/null)
  fi
  for line in ${(f)out}; do
    if (( depth == 1 )); then                   # the session itself, not its Progress = { … } block
      [[ $line == *'Running = 1;'* ]] && run=1
      [[ $line =~ '^[[:space:]]*Percent = "?([0-9]+(\.[0-9]+)?)"?;' ]] && pct=$match[1]
    fi
    depth=$(( depth + ${#line//[^\{]/} - ${#line//[^\}]/} ))
  done
  if (( run )); then
    if (( ! tm_since )); then                   # its start: the look that saw it begin, or -1: unknown
      if (( tm_idle )); then
        tm_since=$now
        (( writes )) && print -r -- $tm_since > "$dir/tm-since.tmp" && zf_mv -f "$dir/tm-since.tmp" "$dir/tm-since"
      else
        tm_since=-1
      fi
    fi
    (( key = tm_since > 0 ? tm_since : 0 ))     # an unknown start sorts below the jobs whose start is known
    if [[ $pct != -1 ]]; then
      (( p = pct * 100 + 0.5 )); (( p > 100 )) && p=100
      add_row 1 $key run "Time Machine" "$p %" $p tm
    else
      add_row 1 $key run "Time Machine" "…" 0 tm
    fi
    return 0
  fi
  [[ -n $out ]] && tm_idle=1
  if (( tm_since )); then
    tm_checked=0
    (( writes )) && zf_rm -f "$dir/tm-since"
  fi
  tm_since=0
  if (( tm_last > 0 && now - tm_checked >= 3600 || now - tm_checked >= 86400 )); then
    tm_checked=$now tm_last=0 out=""
    if [[ -n $fake ]]; then
      [[ -r $fake/tmutil-latestbackup ]] && out=$(<$fake/tmutil-latestbackup)
    else
      out=$(tmutil latestbackup 2>/dev/null)
    fi
    if [[ $out =~ '.*([0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6})' ]]; then
      strftime -r -s tm_last '%Y-%m-%d-%H%M%S' $match[1] 2>/dev/null || tm_last=0
    fi
  fi
  if (( tm_last > 0 )); then
    finished ok $tm_last
    add_row 2 $tm_last ok "Time Machine" "$REPLY" ""
  fi
}

# The last finished download. Listed again when the folder changed and every 10 min.
downloads_poll() {
  local folder out
  local -a m
  if [[ -n $fake ]]; then folder=$fake/Downloads; else folder=$HOME/Downloads; fi
  zstat -A m +mtime -- $folder 2>/dev/null || return 0
  if [[ $m[1] != $dl_mtime ]] || (( now - dl_read >= 600 )); then
    dl_mtime=$m[1] dl_read=$now dl_time=0 dl_name=""
    out=$(osascript -l JavaScript -e "$downloads_js" "$folder" 2>/dev/null)
    case ${out%%$'\n'*} in
      ok)
        out=${out#*$'\n'}
        dl_time=${out%%$'\n'*} dl_name=${${out#*$'\n'}%|}
        [[ $dl_time == <-> ]] || dl_time=0
        ;;
      denied)
        [[ $dl_said == denied ]] || print -ru2 -- "long-jobs: Allow the agent to access Downloads: System Settings → Privacy & Security → Files & Folders"
        dl_said=denied
        ;;
    esac
  fi
  if (( dl_time > 0 && now - dl_time <= day )) && [[ -n $dl_name ]]; then
    finished ok $dl_time
    add_row 2 $dl_time ok "$dl_name" "$REPLY" ""
  fi
}

# AI sessions the Desmaptic plugin's hook records in AISessions/<session>.json: working — runs, permission — waits for
# you, done — finished, error — failed. "input" is the session at its prompt: right after it started (nothing done
# yet), a minute after a finished turn (Claude Code's idle notice, which would move the finish time) or asking the
# user mid-turn. So the last working / permission / done / error of each session is kept (ai_seen, and $dir/ai-seen
# across restarts), and input shows what came before it: the kept finish with its own time, a wait after work, and
# nothing when nothing came before. A record not updated for 12 h is left out. Sets ai_changed when ai_seen changed.
# The loop does not run while the phone is away, so it may miss a done whose idle input came before it started again:
# the hook keeps the last finish in the record ("finished", "result"; 0 while a turn is under way), so an input with one
# is that finish with its time, and one without it is a question mid-turn — "asked", a wait, after anything kept (an
# input this loop saw come after work too, kept across restarts). A record of an older hook has no "finished": there an
# input written before this loop started (ai_since) after kept work, or over 2 min after a kept finish (the idle notice
# comes a minute after its own), is a turn that ended unseen — "ended", ✓ without a time.
ai_poll() {
  local f j sid tool state updated project label text finished result
  local -a m w
  local -A seen
  for f in $store/AISessions/*.json(N.); do
    sid=${f:t:r}
    [[ $sid =~ '^[A-Za-z0-9_-]{1,128}$' && -r $f ]] || continue
    if (( writes )) && zstat -A m +mtime -- $f 2>/dev/null && (( now - m[1] > 86400 )); then
      zf_rm -f -- $f; continue                  # a session that ended without saying so
    fi
    j=$(<$f)
    [[ $j =~ '"tool":"(claude|codex)"' ]] || continue
    tool=$match[1]
    [[ $j =~ '"state":"([a-z]+)"' ]] || continue
    state=$match[1]
    [[ $j =~ '"updated":([0-9]+)' ]] || continue
    updated=$match[1]
    finished="" result=""
    if [[ $j =~ '"finished":([0-9]+)' ]]; then
      finished=$match[1]
      [[ $j =~ '"result":"(done|error)"' ]] && result=$match[1]
    fi
    if [[ $state == closed ]]; then
      (( writes && now - updated > 300 )) && zf_rm -f -- $f
      continue
    fi
    (( now - updated <= day )) || continue
    w=( ${=ai_seen[$sid]} )
    case $state in
      working|permission|done|error) seen[$sid]="$state $updated" ;;
      input)
        if [[ -n $finished ]]; then                                  # the hook keeps the last finish
          if [[ -n $result ]] && (( finished > 0 )); then seen[$sid]="$result $finished"
          elif [[ -n $w[1] ]]; then seen[$sid]="asked $updated"
          fi
        elif [[ $w[1] == asked && $updated == $w[2] ]]; then seen[$sid]=${ai_seen[$sid]}
        elif [[ $w[1] == (working|permission|asked) ]]; then
          if (( updated < ai_since )); then seen[$sid]="ended $updated"; else seen[$sid]="asked $updated"; fi
        elif [[ $w[1] == (done|error|ended) ]]; then
          if (( updated < ai_since && updated - w[2] > 120 )); then seen[$sid]="ended $updated"
          else seen[$sid]=${ai_seen[$sid]}
          fi
        fi ;;
      *) continue ;;
    esac
    project=""
    if [[ $j =~ '"project":"(([^"\\]|\\.)*)"' ]]; then
      project=${match[1]//\\\"/\"}
      project=${project//\\\\/\\}
    fi
    if [[ $tool == claude ]]; then label=Claude; else label=Codex; fi
    [[ -n $project ]] && label="$label · $project"
    w=( ${=seen[$sid]} )
    case $state:$w[1] in
      working:*)                  span $(( now - updated )); add_row 1 $updated run "$label" "$REPLY" "" ;;
      permission:*|*:asked)       span $(( now - updated )); add_row 0 $updated wait "$label" "! $REPLY" "" ;;
      *:done)                     (( now - w[2] <= day )) || continue
                                  finished ok $w[2]; add_row 2 $w[2] ok "$label" "$REPLY" "" ;;
      *:error)                    (( now - w[2] <= day )) || continue
                                  finished err $w[2]; add_row 2 $w[2] err "$label" "$REPLY" "" ;;
      *:ended)                    add_row 2 $w[2] ok "$label" "✓" "" ;;
    esac
  done
  ai_changed=0
  text=""
  for sid in ${(ko)seen}; do text+="$sid $seen[$sid]"$'\n'; done
  [[ $text == $ai_text ]] && return 0
  ai_seen=( "${(@kv)seen}" ) ai_text=$text ai_changed=1
  if (( writes )); then
    print -rn -- "$text" > "$dir/ai-seen.tmp" && zf_mv -f "$dir/ai-seen.tmp" "$dir/ai-seen"
  fi
}

# The kept AI states of an earlier run: "<session> <state> <time>" lines.
ai_load() {
  local line
  local -a w
  ai_seen=() ai_text=""
  (( writes )) && [[ -r $dir/ai-seen ]] || return 0
  for line in ${(f)"$(<$dir/ai-seen)"}; do
    w=( ${=line} )
    (( $#w == 3 )) && [[ $w[1] =~ '^[A-Za-z0-9_-]{1,128}$' && $w[2] == (working|permission|asked|done|error|ended) && $w[3] == <-> ]] \
      || continue
    ai_seen[$w[1]]="$w[2] $w[3]"
  done
  for line in ${(ko)ai_seen}; do ai_text+="$line $ai_seen[$line]"$'\n'; done
}

# One look at the Mac → st, rows (what the face draws), stops, running.
typeset -A p_ppid p_age p_name p_args mf_time mf_line busy ai_seen
typeset -a rows_all stops
xc_since=0 xc_seen=0 xc_latest=0 tm_since=0 tm_idle=0 tm_checked=0 tm_last=0 dd="" dd_read=0
dl_mtime="" dl_read=0 dl_time=0 dl_name="" dl_said="" said_ps="" ai_text="" ai_changed=0
st=rest rows="" running=0
compose() {
  local r g shown=0
  local -a f
  now=${clock:-$EPOCHSECONDS}
  rows_all=() busy=() stops=() rows="" running=0
  if read_processes; then
    said_ps=""
    programs_poll
  elif [[ -z $said_ps ]]; then
    print -ru2 -- "long-jobs: ps did not answer"; said_ps=1
  fi
  xcode_logs_poll
  xcode_app_poll
  tm_poll
  downloads_poll
  ai_poll
  for r in ${(o)rows_all}; do
    f=( "${(@ps:\t:)r}" )
    g=${f[1][1]}
    (( g == 2 && ${+busy[$f[3]]} )) && continue           # a job that runs again shows only as running
    (( g == 2 )) && busy[$f[3]]=1                          # and a job finished twice, only the last time
    (( g < 2 )) && running=1
    rows+="$f[2]"$'\t'"$f[3]"$'\t'"$f[4]"$'\t'"$f[5]"$'\n'
    (( ++shown <= 3 && ! $#stops )) && [[ -n $f[6] ]] && stops=( $f[6] )   # the long press: the top one drawn
  done
  if [[ -n $rows ]]; then st=live; else st=calm; fi
}

frame="" last="" sent=0 hidden=1 looked=0 due=0 retry=0 stopped="" tracked=0
draw() {
  frame=$(long_jobs_frame $st "$rows")
}

prepare() {   # this button's folder, the AISessions folder (the plugin's hook writes only into an existing one)
  local t
  zf_mkdir -p "$dir" 2>/dev/null
  zf_mkdir -p -m 700 "$store/AISessions" 2>/dev/null
  ai_load
  [[ -r $dir/tm-since ]] && t=$(<$dir/tm-since) && [[ $t == <-> ]] && tm_since=$t   # a backup's start, if one still runs
}

if (( dry )); then
  (( writes )) && prepare
  compose
  draw
  for r in ${(f)rows}; do print -r -- "row: ${r//$'\t'/|}"; done
  for r in $stops; do print -r -- "stop: $r"; done
  print -r -- "frame: $frame"
  exit 0
fi

if [[ -z ${DESMAPTIC_TOKEN:-} ]]; then
  print -u2 -- "long-jobs: not started by Desmaptic Agent (no DESMAPTIC_TOKEN): try LONGJOBS_DRY=1"
  exit 1
fi
prepare

post() {   # $1 frame → 0 when the agent took it
  local json=$1 resp code body
  json=${json//\\/\\\\}; json=${json//\"/\\\"}; json=${json//$'\n'/}
  resp=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' -H "Content-Type: application/json" \
    -d "{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$json\",\"duration\":1.2}}")
  code=${resp##*$'\n'} body=${resp%$'\n'*}
  if [[ $code != 200 ]]; then
    print -ru2 -- "long-jobs: update-button answered ${code:-nothing}: $body"
    return 1
  fi
  [[ ${body//[[:space:]]/} == *'"visible":false'* ]] && hidden=1
  return 0
}

on_screen() {   # the phone shows this button (or is too old to say)
  local body
  body=$(curl -q -s -m 5 "$api/api/view" --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}') || return 1
  body=${(L)body//[[:space:]]/}
  [[ $body == *'"view":null'* || $body == *${(L)cell}* ]]
}

# The job the long press may stop: the top one the face shows that can be stopped.
keep_stops() {
  local list=${(F)stops}
  [[ $list == $stopped ]] && return
  if [[ -n $list ]]; then
    print -r -- "$list" > "$dir/stop.tmp" && zf_mv -f "$dir/stop.tmp" "$dir/stop" && stopped=$list
  else
    zf_rm -f "$dir/stop" && stopped=""
  fi
}
zf_rm -f "$dir/stop" "$dir/poke"

while true; do
  if (( EPOCHSECONDS - tracked >= 10 )); then   # AI sessions every 10 s, on screen or not: a "done" before its "input"
    tracked=$EPOCHSECONDS now=$EPOCHSECONDS
    ai_poll
    (( ai_changed && ! hidden )) && due=0
  fi
  if (( hidden )); then                         # off screen: read nothing else, ask the agent every 10 s
    if (( EPOCHSECONDS - looked >= 10 )); then
      looked=$EPOCHSECONDS
      on_screen && hidden=0 last="" due=0
    fi
    (( hidden )) && { zselect -t 100; continue }
  fi
  if [[ -e $dir/poke ]]; then zf_rm -f "$dir/poke"; due=0; fi
  if (( EPOCHSECONDS >= due )); then
    compose
    keep_stops
    draw
    if [[ $frame != $last ]] || (( EPOCHSECONDS - sent >= 300 )); then   # on change, and a keyframe every 5 min
      if post "$frame"; then last=$frame sent=$EPOCHSECONDS retry=0; else retry=1; fi
    fi
    if (( running )); then due=$(( EPOCHSECONDS + 20 )); else due=$(( EPOCHSECONDS + 60 )); fi
    (( retry )) && due=$(( EPOCHSECONDS + 10 ))
  fi
  zselect -t 100
done
