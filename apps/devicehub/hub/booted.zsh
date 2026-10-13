# Device Hub › which simulators a simulator button acts on — Shake, Open URL, Clean Status Bar. Functions only; it goes
# after hub/ax.zsh (Device Hub's front window is read with $hub_ax) and before the button's own file (app.json):
#   "@file:hub/ax.zsh\n@file:hub/booted.zsh\n@file:hub/shake.zsh"
#
# The simulator in Device Hub's front window: its title is "<device> – <runtime>" ("iPhone 17 Pro – iOS 27.0"), read
# through the Accessibility API ($hub_ax title) without bringing Device Hub forward, and matched against the booted
# simulators by name and runtime, else by name alone (every one of that name). When Device Hub does not run, has no
# window, shows something that is not a booted simulator (a connected iPhone) or cannot be read, every booted simulator.
#
# simctl is CoreSimulator's own, called directly — not xcrun (it follows xcode-select and looks the tool up on its first
# call) nor Xcode's wrapper (it may run `xcodebuild -runFirstLaunch`, an install). The newest Xcode installed, a beta
# included, keeps it up to date in this one place, whichever Xcode xcode-select names. Listing costs about 0.2 s; a few
# seconds when CoreSimulator's service has to start first.

simctl=/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl
typeset -ga udids names runtimes chosen

# booted_simulators: fills names, udids and runtimes with the booted simulators and chosen with the indexes to act on;
# or prints one line on stderr and returns 1.
booted_simulators() {
  [[ -x $simctl ]] || { print -u2 -- "Xcode’s simulator tools are not installed"; return 1 }

  # The cheapest check first: a booted simulator of the default set has a launchd_sim (see simulators/startup.zsh).
  pgrep -qfU $UID '^(/[^ ]*/)?launchd_sim /.*/Library/Developer/CoreSimulator/Devices/'
  (( $? == 1 )) && { print -u2 -- "No simulator is running"; return 1 }   # 2 and 3 are errors: simctl is asked anyway

  # "-- iOS 27.0 --" heads a runtime, "    iPhone 17 Pro (<UDID>) (Booted) " is a device.
  local out line runtime="" title i
  if ! out=$("$simctl" list devices booted 2>&1 </dev/null); then
    print -ru2 -- "The simulators could not be listed: ${${out%%$'\n'*}[1,200]:-no answer}"
    return 1
  fi
  udids=() names=() runtimes=() chosen=()
  for line in ${(f)out}; do
    if [[ $line =~ '^-- (.+) --$' ]]; then
      runtime=$match[1]
    elif [[ $line =~ '^ +(.+) \(([0-9A-Fa-f-]{36})\) \(Booted\) *$' ]]; then
      names+=( "$match[1]" ) udids+=( "$match[2]" ) runtimes+=( "$runtime" )
    fi
  done
  (( $#udids )) || { print -u2 -- "No simulator is running"; return 1 }

  # The device Device Hub shows in front — asked only while Device Hub runs for this account (by bundle id).
  title=""
  if [[ $(lsappinfo info -only pid -app com.apple.dt.Devices 2>/dev/null) == *'"pid"='<1->* ]]; then
    title=$(osascript -l JavaScript -e "$hub_ax" title 2>/dev/null)
    [[ $title == '!'* ]] && title=""            # not readable (no Accessibility, no answer): every booted one
  fi
  local sep=" "$'\xe2\x80\x93'" "               # " – ", an en dash between the device and its runtime
  local -a exact same
  if [[ $title == *"$sep"* ]]; then
    for i in {1..$#udids}; do
      [[ $names[i] == "${title%%"$sep"*}" ]] || continue
      same+=( $i )
      [[ $runtimes[i] == "${title#*"$sep"}" ]] && exact+=( $i )
    done
  fi
  if (( $#exact )); then chosen=( $exact )
  elif (( $#same )); then chosen=( $same )
  else chosen=( {1..$#udids} )
  fi
  return 0
}
