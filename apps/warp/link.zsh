# Warp › New Tab, New Window, New Agent and Finder Folder: a warp:// link, handed to Warp through Launch Services as a
# link clicked in a browser is. Warp runs it whatever the app in front, the keyboard layout and the user's keybindings,
# and shows and focuses its window; nothing is typed into a session and no command is run, so no permission is needed
# (Finder Folder asks Finder for its folder: that button's first tap brings up the macOS question whether the agent may
# control Finder).
# Checked in Warp v0.2026.09.16.08.27.stable_02 (dev.warp.Warp-Stable) by reading only — Warp was not started. Info.plist
# registers warp:; the routes are those of docs.warp.dev "URI Scheme" (updated 2026-09-24) and of the client's source,
# app/src/uri/mod.rs of warpdotdev/warp at 0eefb74 (master on 2026-09-16, the day of the build), whose route strings the
# installed binary contains:
# - action/new_tab?path=<folder> adds a terminal tab at that folder to Warp's front window (a window when Warp has none),
#   action/new_window?path=<folder> opens a window there; a leading ~ is Warp's home folder. Given a FILE, the same route
#   opens a session beside it and runs the file (uri/mod.rs open_file → execute_file), so the folder is checked first.
# - action/new_agent_conversation adds a tab with a new Agent conversation, as File › New Agent Tab does; nothing is
#   sent until the user types a prompt. The Agent answers only on a paid Warp plan or with the user's own API key
#   (docs.warp.dev, September 2026: the Free plan has no bundled Agent usage).
# New Window and Finder Folder start Warp when it isn't running (the buttons' point): New Window plainly, with Launch
# Services — Warp opens its usual window at launch, and a link would add a second one; Finder Folder with its link,
# which Warp runs once started (a tab of its first window, or a window of its own — not checked live). New Tab and New
# Agent never start Warp.
# Every button's command is one line that names its action, then this file (app.json):
#   "action=tab\n@file:link.zsh"   — tab, window, agent or finder.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
[[ $action == (tab|window|agent|finder) ]] || { print -u2 -- "Warp: unknown action \"$action\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# By bundle id, not by process name: Warp's process is called "stable" (Warp Preview's, "preview"). lsappinfo asks this
# login session's Launch Services — the one `open` hands the link to — and prints nothing for an app that is not running.
running=0
[[ -n $(lsappinfo info -only pid -app dev.warp.Warp-Stable 2>/dev/null) ]] && running=1

case $action in
  tab)
    (( running )) || { print -u2 -- "Warp is not running"; exit 1 }
    link='warp://action/new_tab?path=~'
    ;;
  agent)
    (( running )) || { print -u2 -- "Warp is not running"; exit 1 }
    link='warp://action/new_agent_conversation'
    ;;
  window)
    if (( ! running )); then
      # env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
      env -i /usr/bin/open -b dev.warp.Warp-Stable || { print -u2 -- "Warp did not start"; exit 1 }
      exit 0
    fi
    link='warp://action/new_window?path=~'
    ;;
  finder)
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
    # A folder only: given a file, Warp runs it (above). And not one named like a document Warp shows in its notebook
    # viewer — it looks at the name before it asks whether the path is a folder (uri/mod.rs classify_open_file_action,
    # warp_util file_type.rs: *.md, *.markdown, *.ipynb, and README, CHANGELOG, LICENSE without an extension).
    [[ $folder == /* && -d $folder ]] || { print -ru2 -- "Warp: not a folder: $folder"; exit 1 }
    name=${${folder%/}:t}
    [[ ${name:e:l} != (md|markdown|ipynb) && ( -n ${name:e} || ${name:l} != (readme|changelog|license) ) ]] ||
      { print -ru2 -- "Warp would open this folder as a document: $folder"; exit 1 }

    # The link's query is form-decoded by Warp ("+" is a space there), so every byte but these is %XX. LC_ALL=C: one
    # byte at a time, a name in any script included.
    encoded=
    for (( k = 1; k <= ${#folder}; k++ )); do
      c=${folder[k]}
      if [[ $c == [A-Za-z0-9/._-] ]]; then
        encoded+=$c
      else
        printf -v hex '%%%02X' "'$c"
        encoded+=$hex
      fi
    done
    link="warp://action/new_tab?path=$encoded"
    ;;
esac

# -b: to Warp itself, not to whatever else may have claimed warp:// links (Warp Preview claims warppreview:).
env -i /usr/bin/open -b dev.warp.Warp-Stable "$link" || { print -u2 -- "Warp did not take the link"; exit 1 }
exit 0
