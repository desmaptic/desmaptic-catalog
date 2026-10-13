# Terminal › New Window and Finder Folder: a new Terminal window, in the home folder or in the folder the front Finder
# window shows. The folder is handed to Terminal through Launch Services, as a folder dropped on its Dock icon is:
# nothing is typed into a shell, Terminal needs no permission, and it works from any app — Terminal starts if it is
# not running. Finder is asked through its own AppleScript: that button's first tap brings up the macOS question
# whether the agent may control Finder.
# Each button's command is one line that names the folder, then this file (app.json):
#   "where=home\n@file:open-window.zsh"     — the home folder;
#   "where=finder\n@file:open-window.zsh"   — Finder's insertion location: the front Finder window's folder, the
#                                             desktop when no Finder window is open.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
[[ $where == (home|finder) ]] || { print -u2 -- "Terminal: unknown folder \"$where\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

if [[ $where == home ]]; then
  folder=$HOME
else
  # pgrep sees every account's processes; -U keeps it to this one, whose Finder the AppleScript talks to.
  pgrep -xqU $UID Finder || { print -u2 -- "Finder is not running"; exit 1 }

  # Prints the folder's POSIX path, or "!<why not>".
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
fi

# A folder only: Terminal also opens scripts and executables given to it — it would run them.
[[ $folder == /* && -d $folder ]] || { print -ru2 -- "Terminal: not a folder: $folder"; exit 1 }
# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open -b com.apple.Terminal "$folder" || { print -u2 -- "Terminal did not open a window"; exit 1 }
exit 0
