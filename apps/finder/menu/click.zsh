# Finder › Back, Forward, as Icons (long press: as Gallery), as List, as Columns, New Tab, New Folder, Copy as Pathname,
# Go to Folder and Connect to Server: a Finder menu item, clicked through System Events. A click needs no key, so it
# works on every layout, and the script refuses while Finder is not in front (a menu command acts on Finder's key
# window, which it has only then) — a key pressed for Finder in another app would do something else there (⌘K clears
# Terminal's scrollback).
# Finder's menus follow the Mac's language, so no item is found by its name. Back, Forward and the views are found by
# their place: the 1st and 2nd items of Go, the 1st to 4th of View (File is the 3rd menu of the menu bar, Edit the 4th,
# View the 5th, Go the 6th, counting the Apple menu) — not by their shortcut, because AppKit changes that shortcut and
# Accessibility shows the changed one: Finder 26.4's MenuBar.nib leaves key-equivalent localization and mirroring on,
# so a shortcut the layout cannot type is remapped (⌘[ on German keys, where [ needs ⌥; ⌘1 on French ones, where 1
# needs ⇧) and [ and ] trade places in right-to-left languages (Apple's own example is Finder's Back and Forward; a
# test app with right-to-left forced showed Back's ⌘[ as ⌘] through Accessibility). The item in that place must carry
# a shortcut with the expected modifiers; otherwise (a Finder version that moved it) the script looks for the shortcut.
# The letters (⌘T, ⇧⌘N, ⌥⌘C, ⇧⌘G, ⌘K) are typed on every layout, so those items are found by their shortcut: in their
# menu first, then in the others. It needs Accessibility, and the first tap brings up the macOS question about
# controlling System Events. It never launches Finder.
# Every button's command is one line that names its action, then this file (app.json):
#   "action=back\n@file:menu/click.zsh"   — back, forward, icons, list, columns, gallery, new-tab, new-folder, copy-path,
#                                            go-to-folder or connect.
# AXMenuItemCmdModifiers: 0 is ⌘ alone, 1 adds ⇧, 2 ⌥, 4 ⌃, 8 means no ⌘. Accessibility shows letters in upper case.
case $action in
  back)         where=6 place=1 key='[' mods=0 ;;   # Go › Back, ⌘[
  forward)      where=6 place=2 key=']' mods=0 ;;   # Go › Forward, ⌘]
  icons)        where=5 place=1 key='1' mods=0 ;;   # View › as Icons, ⌘1
  list)         where=5 place=2 key='2' mods=0 ;;   # View › as List, ⌘2
  columns)      where=5 place=3 key='3' mods=0 ;;   # View › as Columns, ⌘3
  gallery)      where=5 place=4 key='4' mods=0 ;;   # View › as Gallery, ⌘4
  new-tab)      where=3 place=0 key='T' mods=0 ;;   # File › New Tab, ⌘T (View › Show Tab Bar is ⇧⌘T, 1)
  new-folder)   where=3 place=0 key='N' mods=1 ;;   # File › New Folder, ⇧⌘N (New Finder Window is ⌘N, 0)
  copy-path)    where=4 place=0 key='C' mods=2 ;;   # Edit › Copy as Pathname, ⌥⌘C (Option's alternate of Copy)
  go-to-folder) where=6 place=0 key='G' mods=1 ;;   # Go › Go to Folder…, ⇧⌘G
  connect)      where=6 place=0 key='K' mods=0 ;;   # Go › Connect to Server…, ⌘K (Network is ⇧⌘K, 1)
  *) print -u2 -- "Finder: unknown action \"$action\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Finder System Events sees.
pgrep -xqU $UID Finder || { print -u2 -- "Finder is not running"; exit 1 }

# Prints nothing, or "!<why not>". Place 0 = find the item by its shortcut only.
read -r -d '' script <<'OSA'
on run argv
	set menuIndex to (item 1 of argv) as integer
	set itemIndex to (item 2 of argv) as integer
	set keyChar to item 3 of argv
	set keyMods to (item 4 of argv) as integer
	tell application "System Events"
		set found to (application processes whose bundle identifier is "com.apple.finder")
		if found is {} then return "!Finder is not running"
		tell item 1 of found
			if not frontmost then return "!Finder is not in front"
			set chosen to missing value
			if itemIndex > 0 then
				try
					set candidate to menu item itemIndex of menu 1 of menu bar item menuIndex of menu bar 1
					set shownChar to value of attribute "AXMenuItemCmdChar" of candidate
					if shownChar is not missing value and shownChar is not "" then
						if (value of attribute "AXMenuItemCmdModifiers" of candidate) is keyMods then set chosen to candidate
					end if
				end try
			end if
			if chosen is missing value then
				set menuCount to count of menu bar items of menu bar 1
				set order to {menuIndex}
				repeat with i from 2 to menuCount
					if i is not menuIndex then set end of order to i
				end repeat
				repeat with i in order
					repeat with candidate in (menu items of menu 1 of menu bar item (contents of i) of menu bar 1)
						set matches to false
						try
							considering case
								set matches to ((value of attribute "AXMenuItemCmdChar" of candidate) is keyChar)
							end considering
							if matches then set matches to ((value of attribute "AXMenuItemCmdModifiers" of candidate) is keyMods)
						end try
						if matches then
							set chosen to contents of candidate
							exit repeat
						end if
					end repeat
					if chosen is not missing value then exit repeat
				end repeat
			end if
			if chosen is missing value then return "!Finder has no menu item with this shortcut"
			-- Greyed out (Back with no history, Copy as Pathname with nothing to copy): say so rather than click for nothing.
			if not (enabled of chosen) then return "!" & (name of chosen) & " is not available in Finder now"
			click chosen
		end tell
	end tell
	return ""
end run
OSA

# env -i: System Events, when this starts it, gets the account's own environment, not the agent's token.
if ! answer=$(env -i /usr/bin/osascript -e "$script" $where $place "$key" $mods 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control System Events: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1719*|*-25211*) print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Finder's menu did not respond: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
