# Ghostty › Show in Finder: the folder of the terminal in front of Ghostty's front window, in a Finder window. Ghostty
# says which folder that is through its own AppleScript ("working directory" of the focused terminal of the selected
# tab, Ghostty 1.3.1): the folder the shell last reported to it, which Ghostty's shell integration does at every prompt
# and Ghostty keeps only for this Mac (Termio stream_handler, reportPwd, drops a host that is not local). The first tap
# brings up the macOS question whether the agent may control Ghostty. Nothing is typed into the terminal. It never
# launches Ghostty, nor the app of a package the terminal is in.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# Asked by bundle id, not with pgrep: `ghostty` is also the name of Ghostty's command-line tool (the same binary), which
# may run in a shell while the app does not. Launch Services answers for this login session only, whose Ghostty the
# AppleScript talks to — not another account's.
[[ $(lsappinfo info -only pid -app com.mitchellh.ghostty 2>/dev/null) == *=<1-> ]] || { print -u2 -- "Ghostty is not running"; exit 1 }

# Prints the folder, or "!<why not>".
read -r -d '' script <<'OSA'
on run argv
	if not (application id "com.mitchellh.ghostty" is running) then return "!Ghostty is not running"
	with timeout of 10 seconds
		tell application id "com.mitchellh.ghostty"
			set w to missing value
			try
				set w to front window
			end try
			if w is missing value then
				-- With macos-applescript = false Ghostty lists no windows and refuses every command with -10004.
				new surface configuration
				return "!No Ghostty window is open"
			end if
			set t to missing value
			try
				set t to focused terminal of selected tab of w
			end try
			if t is missing value then return "!Ghostty did not say which terminal is in front"
			set here to working directory of t
			if here is "" then return "!Ghostty doesn't know this terminal's folder: its shell integration tells it"
			return here
		end tell
	end timeout
end run
OSA

if ! folder=$(osascript -e "$script" 2>&1) || [[ $folder == '!'* ]]; then
  case $folder in
    *-1743*) print -u2 -- "The agent may not control Ghostty: allow it in System Settings → Privacy & Security → Automation" ;;
    *-10004*|*macos-applescript*) print -u2 -- "Ghostty's AppleScript is turned off: macos-applescript = false in its config" ;;
    '!'*)    print -ru2 -- "${folder#!}" ;;
    *)       print -ru2 -- "Ghostty did not answer: ${folder##*execution error: }" ;;
  esac
  exit 1
fi
[[ $folder == /* ]] || { print -ru2 -- "Not a folder on this Mac: $folder"; exit 1 }
# The shell reports its logical folder, which may be a symlink to a package (an app): the check below would call the
# link no package and Finder would open — launch — the app. Links resolved, it is the package itself.
folder=${folder:A}
[[ -d $folder ]] || { print -ru2 -- "Not a folder on this Mac: $folder"; exit 1 }

# Finder opens a package (an app, an .xcodeproj) as a double click does — in its app, which it would launch — so a
# package, or a folder whose kind cannot be told, is shown selected in its parent folder instead.
package=$(osascript -l JavaScript -e 'ObjC.import("AppKit"); function run(argv) { return $.NSWorkspace.sharedWorkspace.isFilePackageAtPath(argv[0]) }' "$folder" 2>/dev/null)
if [[ $package == false ]]; then
  # env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
  env -i /usr/bin/open -b com.apple.finder "$folder" || { print -ru2 -- "Finder did not open $folder"; exit 1 }
else
  env -i /usr/bin/open -R "$folder" || { print -ru2 -- "Finder did not show $folder"; exit 1 }
fi
exit 0
