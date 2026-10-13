# Finder › Eject All: every disk Finder can eject (external drives, disk images, servers, cards), as File › Eject All
# (⌥⌘E, Option's alternate of Eject) does, through Finder's own AppleScript. It works from any app, never brings Finder
# to the front, and never launches it (macOS keeps it running; should it be quit, the button says so). Disks go one by
# one, so a busy one does not keep the others; then the button checks which disks are still there and names them in
# its one line, each with what is known about it: Finder does not let go of a disk an app is using. The first tap
# brings up the macOS question whether the agent may control Finder.
# Checked in Finder 26.4 by reading only: its dictionary (sdef) — the command `eject`, a disk's `ejectable` and `id`;
# File › Eject All in its MenuBar.nib. The button's command is this file (app.json).
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Finder the AppleScript talks to.
pgrep -xqU $UID Finder || { print -u2 -- "Finder is not running"; exit 1 }

# Prints nothing, or "!<why not>". The time limits keep the whole tap under a minute: a disk still writing its last
# changes may take a while, and one Finder cannot reach must not hold the button. Disks are held by Finder's id, not by
# name: names repeat (two cards called "Untitled", an old Mac's drive in an enclosure called like the startup disk), and
# `disk "<name>"` is the first disk of that name.
read -r -d '' script <<'OSA'
on run argv
	if not (application id "com.apple.finder" is running) then return "!Finder is not running"
	with timeout of 10 seconds
		tell application id "com.apple.finder"
			set diskIds to id of every disk whose ejectable is true
			set diskNames to {}
			repeat with diskId in diskIds
				set end of diskNames to name of (first disk whose id is (contents of diskId))
			end repeat
		end tell
	end timeout
	if diskIds is {} then return "!No disk to eject"
	-- Why each disk may still be there, should it be: the message says only what is known.
	set reasons to {}
	set started to current date
	repeat with diskId in diskIds
		if ((current date) - started) > 25 then
			set reason to "not tried, no time left"
		else
			set reason to "still ejecting"
			try
				with timeout of 15 seconds
					tell application id "com.apple.finder" to eject (first disk whose id is (contents of diskId))
				end timeout
			on error number errorNumber
				if errorNumber is -1712 then
					set reason to "Finder did not answer"
				else
					set reason to "in use"
				end if
			end try
		end if
		set end of reasons to reason
	end repeat
	-- A disk may take a moment to go after the command returns: look a few times before naming it.
	repeat 8 times
		set kept to {}
		repeat with i from 1 to count of diskIds
			with timeout of 5 seconds
				tell application id "com.apple.finder" to set mounted to exists (first disk whose id is (item i of diskIds))
			end timeout
			if mounted then set end of kept to (item i of diskNames) & " (" & (item i of reasons) & ")"
		end repeat
		if kept is {} then return ""
		delay 0.5
	end repeat
	set AppleScript's text item delimiters to ", "
	return "!Not ejected: " & (kept as text)
end run
OSA

if ! answer=$(osascript -e "$script" 2>&1) || [[ $answer == '!'* ]]; then
  # The script's own answers first: they carry the disks' names, which may hold an error number ("Backup-1712").
  case $answer in
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *-1743*) print -u2 -- "The agent may not control Finder: allow it in System Settings → Privacy & Security → Automation" ;;
    *-600*)  print -u2 -- "Finder is not running" ;;
    *-1712*) print -u2 -- "Finder did not answer" ;;
    *)       print -ru2 -- "Finder did not take the command: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
