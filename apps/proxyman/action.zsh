# Proxyman › Record (tap: Toggle Recording; long press: Clear Session), Block List (tap: turn it on or off; long press:
# its rules) and macOS Proxy (long press: Override macOS Proxy): Proxyman's own proxyman://action link, handed to the
# running Proxyman through Launch Services as a link clicked in a browser is — the link Proxyman's own Raycast commands
# open (raycast/extensions, extensions/proxyman/src/utils/actions.ts: `proxyman://action?name=<action>`, updated
# 2026-07). Proxyman runs it whatever the app in front, the keyboard layout and its language, and `open` brings it to
# the front; nothing is typed or clicked, so no permission is needed. Checked in Proxyman 6.6.0 by reading only:
# Info.plist registers proxyman:, and the binary holds "proxyman://action" and the action names, in the same order as
# the Raycast commands; Block List's ToggleBlocklist and OpenBlocklist are in that list of the binary too.
# Why not proxyman-cli (clear-session, proxy on|off): it posts Darwin notifications (CFNotificationCenterGetDarwinNotify
# Center), which reach Proxyman in every account logged in on the Mac; Launch Services hands the link to this account's
# Proxyman only. Why not Clear Session's ⌥⇧⌘⌫: with Finder in front by mistake, it empties the Trash without asking.
# It never launches Proxyman: `open` would, and at launch Proxyman overrides the Mac's proxy settings by default.
# The button's command is one line that names the action, then this file (app.json):
#   "action=record\n@file:action.zsh"   — record, clear-session, blocklist, blocklist-rules or system-proxy.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
case $action in
  record)        name=ToggleRecordTraffic ;;    # Tools › Toggle Recording (⌘R)
  clear-session) name=ClearSession ;;           # Flow › Clear Session (⌥⇧⌘⌫)
  blocklist)     name=ToggleBlocklist ;;        # Tools › Enable/Disable Tools › Block List
  blocklist-rules) name=OpenBlocklist ;;        # Tools › Block List…
  system-proxy)  name=ToggleSystemProxy ;;      # Tools › Proxy Settings › Override macOS Proxy (⌥⌘O)
  *) print -u2 -- "Proxyman: unknown action \"$action\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Proxyman Launch Services hands the link to.
pgrep -xqU $UID Proxyman || { print -u2 -- "Proxyman is not running"; exit 1 }

# -b: to Proxyman itself, not to whatever else may have claimed proxyman:// links.
# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open -b com.proxyman.NSProxy "proxyman://action?name=$name" || { print -u2 -- "Proxyman did not take the link"; exit 1 }

# macOS Proxy's own live loop (proxy/live.zsh, the same button) looks every second for a few seconds after this.
if [[ $action == system-proxy && -n $DESMAPTIC_STORAGE ]]; then
  mkdir -p "$DESMAPTIC_STORAGE/gallery/{{CELL_ID}}" 2>/dev/null && : > "$DESMAPTIC_STORAGE/gallery/{{CELL_ID}}/changed" 2>/dev/null
fi
exit 0
