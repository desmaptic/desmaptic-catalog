# Slack › Back (tap) and Forward (long press): Go › History › Back or Forward in Slack's menu, clicked through
# System Events. Their shortcuts, ⌘[ and ⌘], sit on bracket keys that German, French, Spanish, Nordic, Swiss and other
# layouts type only with Option or Shift, so the keystroke misses there; the menu works on every layout. Slack names
# its menus in the language chosen in Slack itself, so the script knows the names in every language Slack ships
# (read from its locales, Slack 4.47); it clicks only while Slack is in front, the window the menu acts on. It needs
# Accessibility, and the first tap brings up the macOS question about controlling System Events. It never launches
# Slack. The button's command is one line that names the direction, then this file (app.json):
#   "action=back\n@file:menu/history.zsh"   — back or forward.
[[ $action == (back|forward) ]] || { print -u2 -- "Slack: unknown action \"$action\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Slack System Events sees.
pgrep -xqU $UID Slack || { print -u2 -- "Slack is not running"; exit 1 }

# Prints nothing, or "!<why not>". Electron drops a label's "&" on the Mac, and a "(&B)" with it, which can leave a
# trailing space ("返回 (&B)" → "返回 "): names are compared without trailing spaces.
read -r -d '' script <<'OSA'
on trimmed(theName)
	set theName to theName as text
	repeat while theName ends with " "
		if (count of theName) is 1 then return ""
		set theName to text 1 thru -2 of theName
	end repeat
	return theName
end trimmed

on itemNamed(theItems, theNames)
	repeat with anItem in theItems
		try
			set itemName to name of anItem
			if itemName is not missing value then
				if theNames contains {my trimmed(itemName)} then return contents of anItem
			end if
		end try
	end repeat
	return missing value
end itemNamed

on run argv
	set act to item 1 of argv
	-- en, de, es, fr, it, ja, ko, pt-BR, zh-CN, zh-TW; a CJK name also as it reads with its "(&B)" kept
	set goNames to {"Go", "Gehe zu", "Ir", "Aller", "Vai", "開始", "이동", "开始", "並前往"}
	set historyNames to {"History", "Verlauf", "Historial", "Historique", "Cronologia", "履歴", "내역", "내역(i)", "Histórico", "历史记录", "历史记录 (i)", "歷程", "歷程(I)"}
	if act is "back" then
		set itemNames to {"Back", "Zurück", "Atrás", "Retour", "Indietro", "戻る", "뒤로", "뒤로(B)", "Voltar", "返回", "返回 (B)", "返回(B)"}
		set label to "Go › History › Back"
	else
		set itemNames to {"Forward", "Vorwärts", "Adelante", "Transférer", "Avanti", "進む", "앞으로", "앞으로(F)", "Encaminhar", "转发", "转发 (F)", "轉寄"}
		set label to "Go › History › Forward"
	end if
	tell application "System Events"
		set found to (application processes whose bundle identifier is "com.tinyspeck.slackmacgap")
		if found is {} then return "!Slack is not running"
		tell item 1 of found
			if not frontmost then return "!Slack is not in front"
			set goItem to my itemNamed(menu bar items of menu bar 1, goNames)
			if goItem is missing value then return "!Slack has no Go menu in a language this button knows"
			set historyItem to my itemNamed(menu items of menu 1 of goItem, historyNames)
			if historyItem is missing value then return "!Slack has no Go › History menu"
			set target to my itemNamed(menu items of menu 1 of historyItem, itemNames)
			if target is missing value then return "!Slack has no " & label & " menu item"
			if not (enabled of target) then return "!" & label & " is not available in Slack now"
			click target
		end tell
	end tell
	return ""
end run
OSA

# env -i: System Events, when this starts it, gets the account's own environment, not the agent's token.
if ! answer=$(env -i /usr/bin/osascript -e "$script" "$action" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control System Events: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1719*|*-25211*) print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Slack's menu did not respond: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
