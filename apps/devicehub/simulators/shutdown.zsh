# Device Hub › Simulators, the long press: shuts down every simulator that runs on this Mac, as
# `xcrun simctl shutdown all` does — the simulators of the default set, the ones Device Hub shows (not those of SwiftUI
# previews or of parallel test runs). A shut-down simulator keeps its apps and data, but what its apps had not saved
# is gone, hence the ⚠️ on the long press. Nothing is booted, erased or installed; physical devices are not touched.
# The command is this file (app.json).
#
# simctl is called directly — CoreSimulator's own tool, which every installed Xcode puts in /Library/Developer — not
# through xcrun or Xcode's wrapper: the wrapper runs `xcodebuild -runFirstLaunch` (an install) when CoreSimulator is
# older than that Xcode, and xcrun follows xcode-select, which may name the Command Line Tools. It talks to this
# account's CoreSimulator service only. With no simulator running nothing is asked.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime
zmodload -F zsh/files b:zf_mkdir b:zf_mv

# Anchored at the start of the command line, as in startup.zsh: the text of a script holding the pattern must not count.
pgrep -qfU $UID '^(/[^ ]*/)?launchd_sim /.*/Library/Developer/CoreSimulator/Devices/'
(( $? == 1 )) && exit 0                          # none running (2 and 3 are errors: simctl is asked anyway)

simctl=/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl
[[ -x $simctl ]] || { print -u2 -- "Xcode's simulator tools are not installed"; exit 1 }

if ! out=$("$simctl" shutdown all 2>&1 >/dev/null </dev/null); then
  out=${out%%$'\n'*}                            # its first line
  print -ru2 -- "Not every simulator shut down: ${out[1,200]:-no answer}"
  rc=1
else
  rc=0
fi

# The Simulators face looks again at once, every second for a while, instead of in a few seconds.
if [[ -n $DESMAPTIC_STORAGE ]]; then
  dir="$DESMAPTIC_STORAGE/gallery/{{CELL_ID}}"
  zf_mkdir -p "$dir" 2>/dev/null
  print -r -- $EPOCHSECONDS > "$dir/poke.$$" 2>/dev/null && zf_mv -f "$dir/poke.$$" "$dir/poke" 2>/dev/null
fi
exit $rc
