# Notes › Open Note (tap): the one note the user keeps coming back to (a shopping list, a journal), named in the button's
# own first line, `note=''`, which the user fills in (app.json: the line, then "@file:open-note.zsh"). Until it is set,
# the button says what to set. Notes' own AppleScript shows the note (Notes 4.13, Notes.sdef: `show` an account, folder or
# note), then Notes comes to the front — a tap while Notes is closed starts it, so it works from any page. A note is found
# by its name, which Notes takes from its first line, in every account and folder; of several with that name, Notes shows
# the first it finds. The name reaches the AppleScript as its argument (`on run argv`), never pasted into its text.
# The first tap brings up the macOS question whether the agent may control Notes, as From Clipboard and Read Later do.
# Silent when it worked; otherwise one line on stderr and the phone shakes the button.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
setopt extended_glob
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

name=${${note##[[:space:]]#}%%[[:space:]]#}
[[ -n $name ]] || { print -u2 -- "Open Note: write the note's name in the first line of the button's script"; exit 1 }

# Prints "ok", or "!<AppleScript error number>".
read -r -d '' script <<'OSA'
on run argv
	set noteName to item 1 of argv
	try
		with timeout of 20 seconds
			tell application id "com.apple.Notes"
				show note named noteName
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
  '!-1743') print -u2 -- "The agent may not control Notes: allow it in System Settings → Privacy & Security → Automation" ;;
  '!-1728') print -ru2 -- "Notes has no note named \"$name\" — the name is the note's first line, as the note list shows it" ;;
  '!-1712') print -u2 -- "Notes did not answer in time" ;;
  '!-600')  print -u2 -- "Notes did not start" ;;
  '!'*)     print -ru2 -- "Notes did not show the note (error ${answer#!})" ;;
  *)        print -ru2 -- "Notes did not show the note: ${answer##*execution error: }" ;;
esac
exit 1
