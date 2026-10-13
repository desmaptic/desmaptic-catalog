#!/bin/zsh
# Quit All Apps hold: hide every app with a Dock icon except the one in front, like Hide Others (⌥⌘H)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT

# NSRunningApplication.hide goes through the window server, not an Apple event: no permission, no prompt.
# Its return value says nothing (it reads NO even when the app hides), so it is not checked; the flags
# read here are the state when the script started, which is all one pass needs.
osascript -l JavaScript - <<'JXA' >/dev/null || { print -u2 -- "quit-all-apps: osascript failed"; exit 1 }
ObjC.import('AppKit');
function run() {
  const workspace = $.NSWorkspace.sharedWorkspace;
  const front = workspace.frontmostApplication;
  const frontPid = front.isNil() ? -1 : Number(front.processIdentifier);
  const apps = workspace.runningApplications;
  for (let i = 0; i < apps.count; i++) {
    const app = apps.objectAtIndex(i);
    if (Number(app.activationPolicy) !== 0) continue;                  // no Dock icon
    if (Number(app.processIdentifier) === frontPid || app.hidden || app.terminated) continue;
    app.hide;                                                          // JXA calls a method without arguments when it is read
  }
  return '';
}
JXA
exit 0
