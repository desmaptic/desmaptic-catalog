# Ghostty › Finder Folder: a Ghostty terminal in the folder the front Finder window shows. The folder is handed to
# Ghostty through Launch Services, as a folder dropped on its Dock icon is (Ghostty 1.3.1 lists folders in its
# Info.plist): nothing is typed into a terminal, Ghostty needs no permission, and it works from any app. Ghostty opens it
# as a new tab of its front window, or a window when it has none (macos-dock-drop-behavior, new-tab by default), and
# comes forward (AppDelegate, application(_:openFile:), in the v1.3.1 source). When Ghostty isn't running, this
# starts it, without the extra window it opens at a plain launch. Finder is asked through its own AppleScript: the first
# tap brings up the macOS question whether the agent may control Finder.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Finder the AppleScript talks to.
pgrep -xqU $UID Finder || { print -u2 -- "Finder is not running"; exit 1 }

# Prints the folder's POSIX path — Finder's insertion location: the front Finder window's folder, the desktop when no
# Finder window is open — or "!<why not>".
read -r -d '' script <<'OSA'
on run argv
	if not (application id "com.apple.finder" is running) then return "!Finder is not running"
	tell application id "com.apple.finder"
		try
			set here to (insertion location as alias)
		on error
			return "!The front Finder window shows no folder"
		end try
	end tell
	return POSIX path of here
end run
OSA

if ! folder=$(osascript -e "$script" 2>&1) || [[ $folder == '!'* ]]; then
  case $folder in
    *-1743*) print -u2 -- "The agent may not control Finder: allow it in System Settings → Privacy & Security → Automation" ;;
    '!'*)    print -ru2 -- "${folder#!}" ;;
    *)       print -ru2 -- "Finder did not answer: ${folder##*execution error: }" ;;
  esac
  exit 1
fi

# A folder only: given a file, Ghostty offers to run it (it asks first, but the button must not even offer that).
# A folder's name needs no check, unlike iTerm2's: Ghostty's documents are scripts (.command, .sh…), and
# application(_:openFile:) asks the file system whether the path is a folder before anything else.
[[ $folder == /* && -d $folder ]] || { print -ru2 -- "Ghostty: not a folder: $folder"; exit 1 }
# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open -b com.mitchellh.ghostty "$folder" || { print -u2 -- "Ghostty did not open the folder"; exit 1 }
exit 0
