# Cursor › Agents (tap), Settings and Plan & Usage: Cursor's own cursor:// link, handed to Cursor through Launch Services
# as a link clicked in a browser is. Cursor runs it whichever of its windows is in front, whatever its shortcuts and the
# keyboard layout, and brings itself to the front; nothing is typed or clicked, so no permission is needed.
# Checked in Cursor 3.22.7 (com.todesktop.230313mzl4w4u92) by reading only: Info.plist registers cursor:, and both link
# handlers take the authority anysphere.cursor-deeplink — the editor window's built-in extension (extensions/
# cursor-deeplink/dist/main.js) and the Agents window's own (out/vs/workbench/workbench.glass.main.js, handleCursorDeeplink):
# /glass opens or focuses the Agents window (cursor.openOrFocusGlassWindow); /settings opens Cursor Settings
# (aiSettings.action.open), /settings/plan-usage its Plan & Usage page.
# The Agents link opens Cursor when it is closed (the button's point: the agents); Settings and Plan & Usage do not.
# Cursor is found by its bundle id through lsappinfo, not pgrep by name: its executable is just "Cursor", and lsappinfo
# sees only this account's apps.
# Every button's command is one line that names the link, then this file (app.json):
#   "action=settings\n@file:link.zsh"   — agents, settings or usage.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
case $action in
  agents)   link='cursor://anysphere.cursor-deeplink/glass';               launch=1 ;;
  settings) link='cursor://anysphere.cursor-deeplink/settings';            launch=0 ;;
  usage)    link='cursor://anysphere.cursor-deeplink/settings/plan-usage'; launch=0 ;;
  *) print -u2 -- "Cursor: unknown action \"$action\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# lsappinfo prints "pid"=<n> for a running app and nothing at all for one that is not.
if (( ! launch )) && [[ $(lsappinfo info -only pid -app com.todesktop.230313mzl4w4u92 2>/dev/null) != *'"pid"='<->* ]]; then
  print -u2 -- "Cursor is not running"
  exit 1
fi

# -b: to Cursor itself, not to whatever else may have claimed cursor:// links.
# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open -b com.todesktop.230313mzl4w4u92 "$link" || { print -u2 -- "Cursor did not take the link"; exit 1 }
exit 0
