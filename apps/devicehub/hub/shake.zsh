# Device Hub › Shake: shakes a simulator, as the old Simulator app's Device › Shake did. Device Hub 27 has no Shake of its
# own — no menu item, no control (looked for in Device Hub, DeviceKit, SimulatorKit and CoreSimulator, 2026-09-27) — but
# UIKit inside a simulator takes the Darwin notification com.apple.UIKit.SimulatorShake for a shake (the name is in the
# iOS 27.0 runtime's UIKit), so the script posts it inside the device with the device's own notifyutil:
# `simctl spawn <UDID> notifyutil -p com.apple.UIKit.SimulatorShake`. No window, no app in front: Device Hub may stay in
# the background, or not run at all. The command is ax.zsh, booted.zsh, then this file (app.json):
#   "@file:hub/ax.zsh\n@file:hub/booted.zsh\n@file:hub/shake.zsh"
#
# Which simulator — the one in Device Hub's front window, else every booted one (booted_simulators, hub/booted.zsh). None
# booted is a refusal: one line on stderr, the phone shakes the button. It only lists and spawns: nothing is booted,
# erased or installed. A tap costs a process-table check, the list and one spawn per device — well within the 60 s a tap
# may take.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

booted_simulators || exit 1

failed=0 first=""
for i in $chosen; do
  if ! err=$("$simctl" spawn "$udids[i]" notifyutil -p com.apple.UIKit.SimulatorShake 2>&1 >/dev/null </dev/null); then
    (( failed++ ))
    [[ -z $first ]] && first="$names[i]: ${${err%%$'\n'*}[1,160]:-no answer}"
  fi
done
(( failed == 0 )) && exit 0
(( failed > 1 )) && first="$first (and $(( failed - 1 )) more)"
print -ru2 -- "Could not shake $first"
exit 1
