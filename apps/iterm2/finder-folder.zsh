# iTerm2 › Finder Folder: an iTerm2 session in the folder the front Finder window shows. The folder is handed to iTerm2
# through Launch Services, as a folder dropped on its Dock icon is (iTerm2 lists folders in its Info.plist): nothing is
# typed into a session, iTerm2 needs no permission, and it works from any app. iTerm2 3.7.3 opens it as a new tab of its
# front window by default (a window when it has none; its Advanced settings can ask for windows or split panes), and
# comes forward (iTermApplicationDelegate.m, application:openFile:). When iTerm2 isn't running, this starts it.
# Finder is asked through its own AppleScript: the first tap brings up the macOS question whether the agent may
# control Finder.
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

# A folder only: given a file, iTerm2 offers to run it. And not one named like an iTerm2 document: application:openFile:
# looks at the extension before it asks whether the path is a folder (a script, a recording, an arrangement…).
[[ $folder == /* && -d $folder ]] || { print -ru2 -- "iTerm2: not a folder: $folder"; exit 1 }
[[ ${${folder%/}:e:l} != (its|itermtab|itermcolors|itr|iterm2arrangement|it2triggers) ]] ||
  { print -ru2 -- "iTerm2 would open this folder as one of its own files: $folder"; exit 1 }
# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open -b com.googlecode.iterm2 "$folder" || { print -u2 -- "iTerm2 did not open the folder"; exit 1 }
exit 0
