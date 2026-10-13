# iTerm2 › Next Pane (long press: Previous Pane), and the long presses of New Tab (Close) and Find (Clear Buffer): an
# iTerm2 menu item, clicked through System Events.
# Next Pane and Previous Pane, because their shortcuts ⌘] and ⌘[ sit on keys that German, French, Spanish, Nordic,
# Swiss and other layouts type only with Option or Shift, so the keystroke misses there. Close and Clear Buffer, because
# their ⌘W and ⌘K must never reach another app: with Terminal in front by mistake, ⌘K clears its scrollback.
# iTerm2's menus are in English whatever the Mac's language (iTerm2 3.7.3 ships no translations), so the item is found
# by its English name, menu by menu (Resources/MainMenu.nib; the Window menu is asked for one item by name only, never
# listed: its last items are the titles of the user's windows). The script refuses while iTerm2 is not in front — a
# menu command acts on iTerm2's key window, which it has only then — and refuses an item iTerm2 greys out (Next Pane
# with one pane, Close while the window's layout is locked). It needs Accessibility, and the first tap brings up the
# macOS question about controlling System Events. It never launches iTerm2.
# Every button's command is one line that names its action, then this file (app.json):
#   "action=next-pane\n@file:menu/click.zsh"   — next-pane, previous-pane, close or clear-buffer.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
case $action in
  next-pane)     chain=(Window 'Split Pane' 'Select Split Pane' 'Next Pane') ;;       # ⌘]
  previous-pane) chain=(Window 'Split Pane' 'Select Split Pane' 'Previous Pane') ;;   # ⌘[
  close)         chain=(Shell Close) ;;                                               # ⌘W
  clear-buffer)  chain=(Edit 'Clear Buffer') ;;                                       # ⌘K
  *) print -u2 -- "iTerm2: unknown action \"$action\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose iTerm2 System Events sees. -a: pgrep skips its
# own ancestors, and an agent started from an iTerm2 tab runs inside iTerm2.
pgrep -axqU $UID iTerm2 || { print -u2 -- "iTerm2 is not running"; exit 1 }

# Prints nothing, or "!<why not>". Arguments: the menu bar's item, then the names down to the item to click.
read -r -d '' script <<'OSA'
on run argv
	tell application "System Events"
		set found to (application processes whose bundle identifier is "com.googlecode.iterm2")
		if found is {} then return "!iTerm2 is not running"
		tell item 1 of found
			if not frontmost then return "!iTerm2 is not in front"
			set menuPath to item 1 of argv
			if not (exists menu bar item menuPath of menu bar 1) then return "!iTerm2 has no " & menuPath & " menu in this version"
			set target to menu bar item menuPath of menu bar 1
			repeat with k from 2 to count of argv
				set itemName to item k of argv
				set menuPath to menuPath & " › " & itemName
				if not (exists menu item itemName of menu 1 of target) then return "!iTerm2 has no " & menuPath & " in this version"
				set target to menu item itemName of menu 1 of target
			end repeat
			-- Greyed out (Next Pane with one pane, Close while the layout is locked): say so rather than click for nothing.
			if not (enabled of target) then return "!" & menuPath & " is not available in iTerm2 now"
			click target
		end tell
	end tell
	return ""
end run
OSA

# env -i: System Events, when this starts it, gets the account's own environment, not the agent's token.
if ! answer=$(env -i /usr/bin/osascript -e "$script" $chain 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control System Events: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1719*|*-25211*) print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "iTerm2's menu did not respond: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
