# Mail › Delete (Archive's long press), Remind Me and Mark All Read: a Mail menu item, clicked through System Events.
# Delete, because its ⌘⌫ must never reach another app: with Finder in front by mistake, the same keys move the selected
# files to the Trash. The script clicks only while Mail is in front, so it acts on the messages the user sees selected.
# Remind Me and Mailbox › Mark All Messages as Read, because their items have no shortcut at all; Mark All acts on the
# mailbox open in Mail's window (All Inboxes, one account's Inbox, a folder), as the menu does.
# Mail's menus follow the Mac's language, so the item is found by the identifier Mail gives it in its menu
# (Base.lproj/MainMenu.nib of Mail 16.0: Mail.menuBar.editMenu.delete, Mail.menuBar.messageMenu.remindMe,
# Mail.menuBar.mailboxMenu.markAllMessagesAsRead…), which System Events reads as AXIdentifier: it is the same in every
# language and on every keyboard layout. It looks in the item's own menu first (Edit is the 4th menu of the menu bar,
# Mailbox the 6th, Message the 7th, counting the Apple menu), then in the others, should a Mail version move it. Delete,
# should the identifier ever be missing, is also found by its shortcut, ⌘⌫ in the Edit menu. The script refuses while
# Mail is not in front: a menu command acts on Mail's key window, which it has only then, and it refuses an item Mail
# greys out (no message selected, nothing unread), saying what to do first. It needs Accessibility, and the first tap
# brings up the macOS question about controlling System Events. It never launches Mail.
# Every button's command is one line that names its action, then this file (app.json):
#   "action=delete\n@file:menu/click.zsh"   — delete, remind-hour, remind-tomorrow or mark-all-read.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
case $action in
  delete)          where=4 key=8 chain=(Mail.menuBar.editMenu.delete) ;;              # Edit › Delete, ⌘⌫ (8 = ⌫)
  remind-hour)     where=7 key=0 chain=(Mail.menuBar.messageMenu.remindMe Mail.menuBar.messageMenu.remindMeIn1Hour) ;;
  remind-tomorrow) where=7 key=0 chain=(Mail.menuBar.messageMenu.remindMe Mail.menuBar.messageMenu.remindMeTomorrow) ;;
  mark-all-read)   where=6 key=0 chain=(Mail.menuBar.mailboxMenu.markAllMessagesAsRead) ;;
  *) print -u2 -- "Mail: unknown action \"$action\""; exit 1 ;;
esac
# What to do first when Mail greys the item out.
case $action in
  mark-all-read) hint='open a mailbox with unread messages' ;;
  *)             hint='select a message first' ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Mail System Events sees.
pgrep -xqU $UID Mail || { print -u2 -- "Mail is not running"; exit 1 }

# Prints nothing, or "!<why not>". Arguments: the menu to look in first, the character code of the shortcut to fall back
# on for the first item (0: none; it must have ⌘ alone, AXMenuItemCmdModifiers 0), what to do first when the item is
# greyed out, then the identifiers from the menu bar's item down to the one to click.
read -r -d '' script <<'OSA'
on run argv
	set menuIndex to (item 1 of argv) as integer
	set shortcutChar to (item 2 of argv) as integer
	set greyedHint to item 3 of argv
	set chain to items 4 thru -1 of argv
	tell application "System Events"
		set found to (application processes whose bundle identifier is "com.apple.mail")
		if found is {} then return "!Mail is not running"
		tell item 1 of found
			if not frontmost then return "!Mail is not in front"
			set menuCount to count of menu bar items of menu bar 1
			set order to {menuIndex}
			repeat with i from 2 to menuCount
				if i is not menuIndex then set end of order to i
			end repeat
			set target to missing value
			repeat with i in order
				set target to my itemWithIdentifier(menu 1 of menu bar item (contents of i) of menu bar 1, item 1 of chain)
				if target is not missing value then exit repeat
			end repeat
			if target is missing value and shortcutChar > 0 then
				repeat with candidate in (menu items of menu 1 of menu bar item menuIndex of menu bar 1)
					set matches to false
					try
						set matches to ((id of ((value of attribute "AXMenuItemCmdChar" of candidate) as text)) is shortcutChar)
						if matches then set matches to ((value of attribute "AXMenuItemCmdModifiers" of candidate) is 0)
					end try
					if matches then
						set target to contents of candidate
						exit repeat
					end if
				end repeat
			end if
			if target is missing value then return "!Mail has no such menu item in this version"
			repeat with k from 2 to count of chain
				set target to my itemWithIdentifier(menu 1 of target, item k of chain)
				if target is missing value then return "!Mail has no such menu item in this version"
			end repeat
			-- Greyed out (no message selected, nothing unread, or a window that is not a mailbox): say so rather than click
			-- for nothing.
			if not (enabled of target) then return "!" & (name of target) & " is not available in Mail now: " & greyedHint
			click target
		end tell
	end tell
	return ""
end run

-- The item of theMenu whose AXIdentifier is wanted, or missing value. Asked item by item: System Events refuses one
-- request for the attribute of all items (-1728, macOS 26).
on itemWithIdentifier(theMenu, wanted)
	tell application "System Events"
		repeat with i from 1 to count of menu items of theMenu
			try
				if (value of attribute "AXIdentifier" of menu item i of theMenu) is wanted then return menu item i of theMenu
			end try
		end repeat
	end tell
	return missing value
end itemWithIdentifier
OSA

# env -i: System Events, when this starts it, gets the account's own environment, not the agent's token.
if ! answer=$(env -i /usr/bin/osascript -e "$script" $where $key "$hint" $chain 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control System Events: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1719*|*-25211*) print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Mail's menu did not respond: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
