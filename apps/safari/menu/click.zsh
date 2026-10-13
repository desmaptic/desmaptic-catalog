# Safari › Back, Forward, Tab Overview and Mute Tab: a Safari menu item, clicked through System Events. A click needs no
# key, so it works on every layout, while the shortcuts (⌘[, ⌘], ⇧⌘\) sit on keys that German, French, Spanish, Nordic,
# Swiss and other layouts type only with Option or Shift; Safari's AppleScript has no Back or Forward, and Window › Mute
# Current Tab and Mute Other Tabs have no shortcut at all. The script refuses while Safari is not in front: a menu
# command acts on Safari's key window, which it has only then.
# Safari's menus follow the Mac's language, so no item is found by its name — and not by its shortcut either, because
# AppKit changes that shortcut and Accessibility shows the changed one: Safari 26.6.2's MainMenu.nib leaves
# key-equivalent localization and mirroring on for every item, so a shortcut the layout cannot type moves to another
# key (Apple's table, TIKeyboardShortcut in TextInput: ⌘ö, ⌘ä and ⇧⌘# on German, ⌘^, ⌘$ and ⇧⌘` on French; the
# modifiers stay, and in none of 249 layouts is the new key a letter or a digit), and [ and ] trade places in
# right-to-left languages, where Back shows ⌘]. So an item is found by the identifier the nib gives it (Back, Forward,
# ShowTabOverview, MuteCurrentTab, MuteOtherTabs), which System Events reads as AXIdentifier: it is the same in every
# language and on every layout, wherever the item sits in its menu (View is the 5th menu of the menu bar, History the
# 6th, counting the Apple menu; Window is the one before Help, wherever the Develop menu, shown or hidden, puts it).
# The two Mute items keep their identifier when Safari renames them for the state of the tabs (Mute Current Tab /
# Unmute Tab…); should a Safari version drop it, they are looked up by those English names in the Window menu, from the
# top: macOS adds its own tiling items there and Safari the window list below them, so their place is not fixed.
# Should a Safari version drop the identifier, by its place: Back is the 3rd item of History (after Show History and a
# separator), Forward the 4th, Show Tab Overview the 14th of View. That is the order Safari builds at launch, not the
# nib's (one nib orders the menus for every language): AppController's awakeFromNib moves Always Show Tab Bar above Show
# Favorites Bar and inserts Show Shared with You (⌃⌘S) under Show Reading List Sidebar. Accessibility leaves hidden
# items out, and Safari hides Always Show Tab Bar in the Compact tab layout and Show Reading List Sidebar under Screen
# Time's content restrictions, so the place is tried, then one and two above it. The item there must show a shortcut
# with the expected modifiers on a key that is not a letter or a digit — for Back and Forward, both items of the pair
# must, which also keeps Back and Forward apart. Otherwise the script looks for the shortcut itself, in their menu
# first, then in the others; Back and Forward are then the upper and the lower of two adjacent items showing ⌘[ and ⌘],
# whichever way round. It needs Accessibility, and the first tap brings up the macOS question about controlling System
# Events. It never launches Safari.
# Every button's command is one line that names its action, then this file (app.json):
#   "action=back\n@file:menu/click.zsh"   — back, forward, tab-overview, mute-tab or mute-others.
# Where: the menu's place in the menu bar, -2 for the one before the last. AXMenuItemCmdModifiers: 0 is ⌘ alone, 1 adds
# ⇧, 2 ⌥, 4 ⌃, 8 means no ⌘. Partner: the other item of the pair, as an offset from this one (0 = none). Keys: the
# characters the shortcut search accepts. Names: the item's English names, for an item with no shortcut to look for
# (place 0: no place either). Greyed: what the refusal adds when the item is greyed out.
names=() greyed=
case $action in
  back)         where=6 axid=Back            place=3  partner=1  keys='[]' mods=0 ;;   # History › Back, ⌘[
  forward)      where=6 axid=Forward         place=4  partner=-1 keys='[]' mods=0 ;;   # History › Forward, ⌘]
  tab-overview) where=5 axid=ShowTabOverview place=14 partner=0  keys='\'  mods=1 ;;   # View › Show Tab Overview, ⇧⌘\
  mute-tab)     where=-2 axid=MuteCurrentTab place=0  partner=0  keys=''   mods=0      # Window › Mute Current Tab
                names=("Mute Current Tab" "Unmute Current Tab" "Mute Tab" "Unmute Tab" "Mute This Tab" "Unmute This Tab")
                greyed="the current tab plays no sound" ;;
  mute-others)  where=-2 axid=MuteOtherTabs  place=0  partner=0  keys=''   mods=0      # Window › Mute Other Tabs
                names=("Mute Other Tabs" "Unmute Other Tabs" "Mute Other Tab" "Unmute Other Tab")
                greyed="no other tab plays sound" ;;
  *) print -u2 -- "Safari: unknown action \"$action\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Safari System Events sees.
pgrep -xqU $UID Safari || { print -u2 -- "Safari is not running"; exit 1 }

# Prints nothing, or "!<why not>". The arguments follow "--": the Window menu's place, -2, would read as an option.
read -r -d '' script <<'OSA'
on run argv
	set menuIndex to (item 1 of argv) as integer
	set itemIndex to (item 2 of argv) as integer
	set partnerOffset to (item 3 of argv) as integer
	set keyChars to item 4 of argv
	set keyMods to (item 5 of argv) as integer
	set wantedId to item 6 of argv
	set greyed to item 7 of argv
	set itemNames to {}
	if (count of argv) > 7 then set itemNames to items 8 thru -1 of argv
	tell application "System Events"
		set found to (application processes whose bundle identifier is "com.apple.Safari")
		if found is {} then return "!Safari is not running"
		tell item 1 of found
			if not frontmost then return "!Safari is not in front"
			-- Counted from the end: the menu before Help.
			if menuIndex < 1 then set menuIndex to (count of menu bar items of menu bar 1) + menuIndex + 1
			set chosen to missing value
			try
				set chosen to my itemWithIdentifier(menu 1 of menu bar item menuIndex of menu bar 1, wantedId)
			end try
			if chosen is missing value and itemNames is not {} then
				-- By name, item by item from the top of its menu: the first item that has one of the names.
				try
					set theMenu to menu 1 of menu bar item menuIndex of menu bar 1
					repeat with n from 1 to count of menu items of theMenu
						try
							if itemNames contains (name of menu item n of theMenu) then
								set chosen to menu item n of theMenu
								exit repeat
							end if
						end try
					end repeat
				end try
				if chosen is missing value then return "!Safari has no " & (item 1 of itemNames) & " in its menu"
			end if
			if chosen is missing value and itemIndex > 0 then
				try
					set placeItems to menu items of menu 1 of menu bar item menuIndex of menu bar 1
					set placeCount to count of placeItems
					-- A hidden item above moves it up (see the header): its place first, then one and two above.
					repeat with n from itemIndex to (itemIndex - 2) by -1
						if n >= 1 and n <= placeCount then
							if my shows(item n of placeItems, keyMods, "") then
								set partnerIndex to n + partnerOffset
								if partnerOffset is 0 then
									set chosen to item n of placeItems
								else if partnerIndex >= 1 and partnerIndex <= placeCount then
									if my shows(item partnerIndex of placeItems, keyMods, "") then set chosen to item n of placeItems
								end if
							end if
						end if
						if chosen is not missing value then exit repeat
					end repeat
				end try
			end if
			if chosen is missing value then
				set menuCount to count of menu bar items of menu bar 1
				set order to {menuIndex}
				repeat with i from 2 to menuCount
					if i is not menuIndex then set end of order to i
				end repeat
				repeat with i in order
					set theItems to menu items of menu 1 of menu bar item (contents of i) of menu bar 1
					set itemCount to count of theItems
					repeat with n from 1 to itemCount
						if my shows(item n of theItems, keyMods, keyChars) then
							set partnerIndex to n + partnerOffset
							if partnerOffset is 0 then
								set chosen to item n of theItems
							else if partnerIndex >= 1 and partnerIndex <= itemCount then
								if my shows(item partnerIndex of theItems, keyMods, keyChars) then set chosen to item n of theItems
							end if
						end if
						if chosen is not missing value then exit repeat
					end repeat
					if chosen is not missing value then exit repeat
				end repeat
			end if
			if chosen is missing value then return "!Safari has no menu item with this shortcut"
			-- Greyed out (Back on the first page): say so rather than click for nothing.
			if not (enabled of chosen) then
				if greyed is "" then return "!" & (name of chosen) & " is not available in Safari now"
				return "!" & (name of chosen) & " is not available in Safari now: " & greyed
			end if
			click chosen
		end tell
	end tell
	return ""
end run

-- Whether the item shows a shortcut with exactly these modifiers: on one of keyChars or, with keyChars empty, on any
-- key but a letter or a digit.
on shows(anItem, keyMods, keyChars)
	tell application "System Events"
		try
			set shownChar to value of attribute "AXMenuItemCmdChar" of anItem
			if shownChar is missing value or shownChar is "" then return false
			if keyChars is "" then
				set codes to id of shownChar
				if class of codes is integer then
					if (codes >= 48 and codes <= 57) or (codes >= 65 and codes <= 90) or (codes >= 97 and codes <= 122) then return false
				end if
			else
				considering case
					if (count of shownChar) is not 1 or keyChars does not contain shownChar then return false
				end considering
			end if
			return ((value of attribute "AXMenuItemCmdModifiers" of anItem) is keyMods)
		on error
			return false
		end try
	end tell
end shows

-- The item of theMenu whose AXIdentifier is wanted, or missing value. Asked item by item: System Events refuses one
-- request for the attribute of all items (-1728, macOS 26).
on itemWithIdentifier(theMenu, wanted)
	tell application "System Events"
		repeat with i from 1 to count of menu items of theMenu
			try
				considering case
					if (value of attribute "AXIdentifier" of menu item i of theMenu) is wanted then return menu item i of theMenu
				end considering
			end try
		end repeat
	end tell
	return missing value
end itemWithIdentifier
OSA

# env -i: System Events, when this starts it, gets the account's own environment, not the agent's token.
if ! answer=$(env -i /usr/bin/osascript -e "$script" -- $where $place $partner "$keys" $mods $axid "$greyed" "${names[@]}" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *-1743*) print -u2 -- "The agent may not control System Events: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1719*|*-25211*) print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
    *)       print -ru2 -- "Safari's menu did not respond: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
