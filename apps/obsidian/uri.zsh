# Obsidian › Search, New Note and Daily Note: an obsidian:// link, handed to Obsidian through Launch Services as a
# link clicked in a browser is. Obsidian runs it whatever its hotkeys, the keyboard layout or the app in front, and
# `open` brings it to the front; nothing is typed and no permission is needed. The links name no vault: Obsidian runs
# them in the vault window focused last. It never launches Obsidian: `open` would, so the script checks first.
# Checked in Obsidian 1.13.7 (main.js routes a link without a vault to the window focused last; the actions are
# app.js "search" and "new" and the Daily notes core plugin's "daily" — with that plugin off, Obsidian itself says
# "Unrecognized URI action: daily").
# Every button's command is one line that names its action, then this file (app.json):
#   "action=search\n@file:uri.zsh"   — search, new, new-split or daily.
case $action in
  search)    uri='obsidian://search' ;;                # the Search pane, as ⇧⌘F with nothing selected
  new)       uri='obsidian://new?paneType=tab' ;;      # an "Untitled" note in a new tab, as ⌘N
  new-split) uri='obsidian://new?paneType=split' ;;    # the same, to the right, as ⇧⌘N
  daily)     uri='obsidian://daily' ;;                 # today's daily note, made the first time
  *) print -u2 -- "Obsidian: unknown action \"$action\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Obsidian Launch Services hands the link to.
pgrep -xqU $UID Obsidian || { print -u2 -- "Obsidian is not running"; exit 1 }

# -b: to Obsidian itself, not to whatever else may have claimed obsidian:// links.
# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open -b md.obsidian "$uri" || { print -u2 -- "Obsidian did not take the link"; exit 1 }
exit 0
