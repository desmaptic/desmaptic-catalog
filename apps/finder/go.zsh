# Finder › Downloads, Desktop, Documents, Home, Applications (long press: Utilities), iCloud Drive and New Window, through
# Finder's own AppleScript: they work from any app. With Finder in front, its front window goes to the folder, as Finder's
# Go menu does (⌥⌘L, ⇧⌘D…); from another app, or with no Finder window open (only the desktop), a new Finder window opens
# there. Either way Finder comes to the front. New Window always opens a new window, where Finder's settings say ("New
# Finder windows show"), as File › New Finder Window (⌘N) does. Nothing is typed into Finder and no file is created,
# moved or read: Finder itself finds the folder (so the script never touches Desktop, Documents, Downloads or iCloud
# Drive, and macOS asks no Files & Folders question). The first tap brings up the macOS question whether the agent may
# control Finder. It never launches Finder (macOS keeps it running; should it be quit, the button says so).
# Checked in Finder 26.4 by reading only: its dictionary (sdef) — `make new Finder window to`, `target`, `frontmost`,
# `collapsed`, `home`, `startup disk`, `activate`; the Go menu's folders in its MenuBar.nib.
# Every button's command is one line that names the place, then this file (app.json):
#   "place=downloads\n@file:go.zsh"   — downloads, desktop, documents, home, applications, utilities, icloud-drive, window.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
[[ $place == (downloads|desktop|documents|home|applications|utilities|icloud-drive|window) ]] ||
  { print -u2 -- "Finder: unknown place \"$place\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Finder the AppleScript talks to.
pgrep -xqU $UID Finder || { print -u2 -- "Finder is not running"; exit 1 }

# Prints nothing, or "!<why not>". The folders are named as Finder names them on disk, whatever the Mac's language.
read -r -d '' script <<'OSA'
on run argv
	set placeName to item 1 of argv
	if not (application id "com.apple.finder" is running) then return "!Finder is not running"
	with timeout of 10 seconds
		tell application id "com.apple.finder"
			-- "a reference to": naming a folder is not asking for it, so a missing one reaches the check below.
			set place to a reference to home
			if placeName is "downloads" then
				set place to a reference to folder "Downloads" of home
			else if placeName is "desktop" then
				set place to a reference to folder "Desktop" of home
			else if placeName is "documents" then
				set place to a reference to folder "Documents" of home
			else if placeName is "applications" then
				-- Finder shows /Applications merged with the system's apps, as the Go menu does.
				set place to a reference to folder "Applications" of startup disk
			else if placeName is "utilities" then
				set place to a reference to folder "Utilities" of folder "Applications" of startup disk
			else if placeName is "icloud-drive" then
				set place to a reference to folder "com~apple~CloudDocs" of folder "Mobile Documents" of folder "Library" of home
			end if
			set newWindow to (placeName is "window")
			if not newWindow then
				if not (exists place) then
					if placeName is "icloud-drive" then return "!iCloud Drive is off on this Mac"
					return "!Finder has no " & placeName & " folder"
				end if
			end if
			-- The window in front, when Finder is: not a minimised one, which the user would not see change.
			set reuse to false
			if (not newWindow) and frontmost then
				if (count of Finder windows) > 0 then
					if not (collapsed of Finder window 1) then set reuse to true
				end if
			end if
			if reuse then
				set target of Finder window 1 to place
			else if newWindow then
				make new Finder window
			else
				make new Finder window to place
			end if
			activate
		end tell
	end timeout
	return ""
end run
OSA

if ! answer=$(osascript -e "$script" $place 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control Finder: allow it in System Settings → Privacy & Security → Automation" ;;
    *-600*)  print -u2 -- "Finder is not running" ;;
    *-1712*) print -u2 -- "Finder did not answer" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Finder did not take the command: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
