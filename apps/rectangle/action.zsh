# Rectangle › every button: Rectangle's own rectangle://execute-action link, handed to the running Rectangle through
# Launch Services in the background (open -g), as its README asks: "Do not activate Rectangle if possible". Rectangle
# applies the action to the front window of whatever app is in front; nothing is typed or clicked, so Desmaptic needs
# no permission — Rectangle moves windows with its own Accessibility access.
# Checked in Rectangle 2.0.3 by reading only: Info.plist registers rectangle:, the binary takes the host
# "execute-action" and the "name" query item and matches it against its window actions' names turned from camelCase
# into dashes (leftHalf → left-half); every name below is one of those actions.
# It never launches Rectangle: at its first launch it opens its own windows to ask for access, and the action would be
# lost. Not installed and not running are told apart, so the phone says which.
# The button's command is one line that names the action, then this file (app.json):
#   "action=left-half\n@file:action.zsh"
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
[[ $action == (left-half|right-half|top-half|bottom-half|maximize|almost-maximize|center|larger|smaller|next-display|previous-display|first-third|center-third|last-third|first-two-thirds|center-two-thirds|last-two-thirds|restore) ]] \
  || { print -u2 -- "Rectangle: unknown action \"$action\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# lsappinfo asks this login session's Launch Services by bundle id: Rectangle Pro and another account's Rectangle
# are not this app.
if [[ $(lsappinfo info -only pid -app com.knollsoft.Rectangle 2>/dev/null) != *'"pid"='<->* ]]; then
  app=$(osascript -l JavaScript -e 'function run(argv) {
    ObjC.import("AppKit");
    const url = $.NSWorkspace.sharedWorkspace.URLForApplicationWithBundleIdentifier(argv[0]);
    return url.isNil() ? "" : url.path.js;
  }' com.knollsoft.Rectangle 2>/dev/null)
  [[ $app == /* ]] || { print -u2 -- "Rectangle is not installed: get it free at rectangleapp.com"; exit 1 }
  print -u2 -- "Rectangle is not running: open it on the Mac"
  exit 1
fi

# -b: to Rectangle itself, not to whatever else may have claimed rectangle:// links.
# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open -g -b com.knollsoft.Rectangle "rectangle://execute-action?name=$action" \
  || { print -u2 -- "Rectangle did not take the link"; exit 1 }
exit 0
