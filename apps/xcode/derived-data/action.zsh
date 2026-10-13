# Xcode › DerivedData, the tap and the long press. Each command is one line that names its action, then folder.zsh
# and this file (app.json):
#   "action=open\n@file:derived-data/folder.zsh\n@file:derived-data/action.zsh"   — shows the folder in Finder;
#   "action=clear\n…"                                                              — empties it at once, no question.
# Both then ask the widget's loop (startup.zsh) to measure the folder again, through a file in its storage.
#
# Clearing is quick whatever the size — well inside the 60 s a long press may take: everything in the folder is
# moved into one hidden folder next to it (a rename, on the same disk), so Xcode sees an empty DerivedData at once,
# and the widget's loop deletes that folder in the background. It refuses, with the phone shaking the button, while
# Xcode or xcodebuild builds, and when the folder is not certainly Xcode's (safe_to_clear); it keeps the folders an
# app is running from right now — the Debug build you are trying out, the Desmaptic Agent itself when you build it.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
[[ $action == (open|clear) ]] || { print -u2 -- "DerivedData: unknown action \"$action\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime
zmodload -F zsh/files b:zf_mkdir b:zf_mv b:zf_rmdir

derived_data || { print -ru2 -- "$REPLY"; exit 1 }
given=$REPLY folder=${REPLY:A}

# The widget measures again at once (and after a clear shows "…" meanwhile).
measure_now() {
  [[ -n $DESMAPTIC_STORAGE ]] || return 0
  local dir="$DESMAPTIC_STORAGE/gallery/{{CELL_ID}}"
  zf_mkdir -p "$dir" 2>/dev/null
  print -r -- $action > "$dir/measure" 2>/dev/null
  return 0
}

if [[ $action == open ]]; then
  [[ -d $folder ]] || { print -u2 -- "There is no DerivedData folder yet: Xcode makes it with the first build"; exit 1 }
  # env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
  env -i /usr/bin/open "$folder" || exit 1
  measure_now
  exit 0
fi

[[ -d $folder ]] || { measure_now; exit 0 }   # nothing to clear

# A build writes into DerivedData: it would fail halfway. The build service (SWBBuildService in Xcode 27, in older
# versions XCBBuildService) runs a build's compilers and linkers as its own children and has none between builds;
# xcodebuild brings its own service. One ps for this account, no question to Xcode; no answer from ps is a refusal.
building=$(ps -ww -U "$UID" -o pid=,ppid=,comm= 2>/dev/null | awk '
    { n = $0; sub(/^ *[0-9]+ +[0-9]+ +/, "", n); sub(/.*\//, "", n); name[$1] = n; parent[$1] = $2 }
    END {
      if (NR == 0) { print "unknown"; exit }
      for (p in parent) if (name[p] == "xcodebuild" || name[parent[p]] ~ /^(SWB|XCB)BuildService$/) { print "yes"; exit }
      print "no"
    }')
case $building in
  no)  ;;
  yes) print -u2 -- "Xcode is building: clear DerivedData when the build is done"; exit 1 ;;
  *)   print -u2 -- "DerivedData: cannot tell whether Xcode is building (ps said nothing)"; exit 1 ;;
esac

safe_to_clear "$folder" || { print -ru2 -- "$REPLY"; exit 1 }

# The folders in DerivedData that a running app of this account was started from (the path it runs from, as the
# folder was given or resolved).
keep=( ${(f)"$(ps -ww -U "$UID" -o comm= 2>/dev/null | DD_A="$folder/" DD_B="$given/" awk '
  BEGIN { a = ENVIRON["DD_A"]; b = ENVIRON["DD_B"] }   # not -v: awk would read a backslash in the path as an escape
  { r = (index($0, a) == 1) ? a : (index($0, b) == 1) ? b : ""
    if (r == "") next
    s = substr($0, length(r) + 1); sub(/\/.*/, "", s)
    if (s != "" && !(s in seen)) { seen[s] = 1; print s } }')"} )

trash="$folder/.desmaptic-clearing-$EPOCHSECONDS-$$"
zf_mkdir "$trash" || { print -u2 -- "DerivedData: cannot make $trash"; exit 1 }
moved=0 failed=()
for entry in "$folder"/*(DN); do
  name=${entry:t}
  [[ $name == .desmaptic-clearing-* ]] && continue   # an earlier clear, being deleted
  (( ${keep[(Ie)$name]} )) && continue
  if zf_mv -- "$entry" "$trash" 2>/dev/null; then (( moved++ )); else failed+=( $name ); fi
done
(( moved )) || zf_rmdir "$trash" 2>/dev/null
measure_now
if (( $#failed )); then
  print -ru2 -- "DerivedData: could not clear ${(j:, :)failed[1,3]}${failed[4]:+ and more}"
  exit 1
fi
exit 0
