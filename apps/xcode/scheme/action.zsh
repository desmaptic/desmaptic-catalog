# Xcode › Build, Run, Test, Clean and Stop: the scheme action of the front Xcode project, through Xcode's own
# AppleScript command — it works with Xcode in the background and whatever its keyboard shortcuts are, and it
# never launches Xcode. The first tap brings up the macOS question whether the agent may control Xcode.
# Every button's command is one line that names its action, then this file (app.json):
#   "action=build\n@file:scheme/action.zsh"   — build, run, test, clean or stop.
# All but Stop note what they started in $DESMAPTIC_STORAGE/gallery/xcode/last-action, which Build Status follows.
[[ $action == (build|run|test|clean|stop) ]] || { print -u2 -- "Xcode: unknown action \"$action\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime
zmodload -F zsh/files b:zf_mkdir b:zf_mv

# pgrep sees every account's processes; -U keeps it to this one, whose Xcode the AppleScript talks to.
pgrep -xqU $UID Xcode || { print -u2 -- "Xcode is not running"; exit 1 }

# Prints "<scheme>\t<project>" of the front window, or "!<why not>".
read -r -d '' script <<'OSA'
on run argv
	set act to item 1 of argv
	if not (application id "com.apple.dt.Xcode" is running) then return "!Xcode is not running"
	tell application id "com.apple.dt.Xcode"
		set ws to active workspace document
		if ws is missing value then return "!No project is open in Xcode"
		if not (loaded of ws) then return "!The project is still opening in Xcode"
		if act is "build" then
			build ws
		else if act is "run" then
			run ws
		else if act is "test" then
			test ws
		else if act is "clean" then
			clean ws
		else
			stop ws
			return ""
		end if
		set schemeName to ""
		try
			set schemeName to name of active scheme of ws
		end try
		return schemeName & tab & (name of ws)
	end tell
end run
OSA

if ! answer=$(osascript -e "$script" $action 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control Xcode: allow it in System Settings → Privacy & Security → Automation" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Xcode did not take the command: ${answer##*execution error: }" ;;
  esac
  exit 1
fi

# For the Build Status widget: what was started, when, on which scheme of which project.
if [[ $action != stop && -n $DESMAPTIC_STORAGE ]]; then
  dir="$DESMAPTIC_STORAGE/gallery/xcode"
  zf_mkdir -p "$dir" 2>/dev/null
  print -r -- "action=$action"$'\n'"started=$EPOCHREALTIME"$'\n'"scheme=${answer%%$'\t'*}"$'\n'"workspace=${answer#*$'\t'}" \
    > "$dir/last-action.tmp" 2>/dev/null && zf_mv -f "$dir/last-action.tmp" "$dir/last-action" 2>/dev/null
fi
exit 0
