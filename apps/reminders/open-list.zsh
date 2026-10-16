# Reminders › Open List (tap): one list of the user's own (Groceries, a project), named in the button's own first line,
# `list=''`, which the user fills in (app.json: the line, then "@file:open-list.zsh"); the list buttons beside it reach
# only the smart lists. Until it is set, the button says what to set. Reminders' own AppleScript shows the list
# (Reminders 7.0, Reminders.sdef: `show` a list or a reminder), then Reminders comes to the front — a tap while Reminders
# is closed starts it, so it works from any page. A list is found by its name, in every account; of several with that
# name, Reminders shows the first it finds. The name reaches the AppleScript as its argument (`on run argv`), never pasted
# into its text. By bundle id, so the Mac's Reminders is asked, never an iOS simulator's.
# The first tap brings up the macOS question whether the agent may control Reminders.
# Silent when it worked; otherwise one line on stderr and the phone shakes the button.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
setopt extended_glob
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

name=${${list##[[:space:]]#}%%[[:space:]]#}
[[ -n $name ]] || { print -u2 -- "Open List: write the list’s name in this button’s settings"; exit 1 }

# Prints "ok", or "!<AppleScript error number>".
read -r -d '' script <<'OSA'
on run argv
	set listName to item 1 of argv
	try
		with timeout of 30 seconds
			tell application id "com.apple.reminders"
				show list named listName
				activate
			end tell
		end timeout
	on error number errorNumber
		return "!" & errorNumber
	end try
	return "ok"
end run
OSA

# env -i: an app osascript starts gets its environment; so a closed one gets the account's own, not the agent's token.
answer=$(env -i /usr/bin/osascript -e "$script" -- "$name" 2>&1)   # --: a name starting with "-" is not an option
case $answer in
  ok)       exit 0 ;;
  '!-1743') print -u2 -- "The agent may not control Reminders: allow it in System Settings → Privacy & Security → Automation" ;;
  '!-1728') print -ru2 -- "Reminders has no list named \"$name\" — write it as the sidebar shows it" ;;
  '!-1712') print -u2 -- "Reminders did not answer in time" ;;
  '!-600')  print -u2 -- "Reminders did not start" ;;
  '!'*)     print -ru2 -- "Reminders did not show the list (error ${answer#!})" ;;
  *)        print -ru2 -- "Reminders did not show the list: ${answer##*execution error: }" ;;
esac
exit 1
