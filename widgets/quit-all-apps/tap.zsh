#!/bin/zsh
# Quit All Apps tap: politely quit every open app with a Dock icon except Finder (unsaved work asks first, as usual)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT

# NSRunningApplication.terminate sends each app the standard Quit Apple event, the same one the Dock's
# Quit sends. macOS keeps it on its safe list, so it needs no Automation permission and shows no prompt,
# and every app answers it its own way: one with unsaved changes asks whether to save them.
# Only apps with a Dock icon (activation policy "regular"): menu bar utilities and background helpers
# stay, and so do Finder and whatever started this script ($PPID). The requests go out at once; the
# script does not wait for the apps to close.
refused=$(osascript -l JavaScript - "$PPID" <<'JXA'
ObjC.import('AppKit');
function run(argv) {
  const parent = Number(argv[0]) || -1;
  const apps = $.NSWorkspace.sharedWorkspace.runningApplications;
  const refused = [];
  for (let i = 0; i < apps.count; i++) {
    const app = apps.objectAtIndex(i);
    if (Number(app.activationPolicy) !== 0) continue;                          // no Dock icon
    if (ObjC.unwrap(app.bundleIdentifier) === 'com.apple.finder') continue;    // Finder stays
    if (Number(app.processIdentifier) === parent || app.terminated) continue;
    // JXA calls a method without arguments when it is read: this line sends the Quit.
    if (app.terminate !== true) refused.push(ObjC.unwrap(app.localizedName));
  }
  return refused.join(', ');
}
JXA
) || { print -u2 -- "quit-all-apps: osascript failed"; exit 1 }

# Not an error for the button: the other apps got the request. Left in the log for whoever looks.
[[ -n $refused ]] && print -u2 -- "quit-all-apps: macOS did not pass Quit to: ${refused[1,300]}"
exit 0
